---
name: quick-commit
description: Quick commit changes (asks about untracked files, auto-generates message or uses provided one)
license: SSL
allowed-tools:
  - Bash
  - Read
  - Grep
---

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/quick-commit [OPTIONS] [message]

Options:
  --single-repo         Commit only in current directory (skip multi-repo detection)
  --discover            Discover repos with changes (multi-repo mode)
  [message]             Commit message (auto-generated if omitted)

Repo selection: Honors .multi-repo-selection.json if present. MULTI_REPO_ALL=true to bypass.
```

---

## Invocation Guard

This skill requires explicit user invocation via `/quick-commit`. It must not be triggered proactively by the assistant after completing code changes, passing tests, or finishing tasks.

**Expected workflow:**
1. Assistant completes work and informs the user
2. Assistant waits for user input
3. User types `/quick-commit` to trigger this skill

**Validation:** This skill should only proceed when `<command-name>/quick-commit</command-name>` is present in the current user message.

---

You are helping the user create git commits (single-repo or multi-repo mode).

**Claude Config Modes**: This command works in both claude configurations:

| Config | Command | Behavior |
|--------|---------|----------|
| `~/.claude` | `claude` / `claude-safe` | Restrictive hooks block direct git commands. Use this `/quick-commit` command for commits (requires user permission approval) |
| `~/.claude-agentic` | `claude-agentic` | No restrictive hooks. Direct git commands allowed, but this command still provides intelligent commit messages |

**Repo selection**: In multi-repo mode, if a `.multi-repo-selection.json` config exists in the workspace root (created by `/multi-repo-sync --wizard`), discovery will only show repos matching the selection. Set `MULTI_REPO_ALL=true` to bypass.

**Auto-detection for multi-repo**: This command uses deterministic mode detection via the `--detect-mode` flag:
1. Call `quick-commit.sh --detect-mode` first (returns JSON with mode decision)
2. The script checks `MULTI_REPO` environment variable (`true` forces multi-repo, `false` forces single-repo)
3. If not set, the script searches for nested `.git` directories from current directory downward
4. Returns `"single-repo"` or `"multi-repo"` - Claude uses this to decide workflow
5. **Claude NEVER runs bash commands to detect mode** - the script handles it deterministically

**CWD-only / single-repo override**: When the user requests committing only in the current working directory (e.g., `/quick-commit - only current directory`), use `--single-repo` to bypass multi-repo auto-detection:
- Pass `--single-repo` as the first argument: `quick-commit.sh --single-repo "message"`
- This forces single-repo mode regardless of nested repositories
- Only tracked changes in the CWD's git repository are committed
- **Skip `--detect-mode`** when using `--single-repo` - mode is already determined

---

## Security Model (Safe Mode)

In safe mode (`~/.claude`), the hook requires explicit user permission for any quick-commit.sh execution.

**How it works:**
1. Claude attempts to run quick-commit.sh
2. The hook intercepts and prompts: "Claude wants to run quick-commit.sh. ONLY ALLOW if YOU typed /quick-commit. DENY if you did not request a commit."
3. User must explicitly approve or deny

This ensures Claude cannot proactively commit without the user invoking `/quick-commit`.

**Optional context hint**: If the user provides text after the command (e.g., `/quick-commit fix the login bug`), use that as guidance when generating the commit message.

---

## Architecture

**This command uses a deterministic bash script for git commit operations:**

```
scripts/quick-commit.sh
```

**Claude's role**:
- Analyze diffs and generate intelligent commit messages
- Ask user about **untracked** files (`??` in status) via AskUserQuestion - NEVER ask about tracked modifications
- Run `git add` for untracked files ONLY IF user approves
- Invoke the script to execute the commit

**Script's role**: Deterministic commit execution with safety checks (never runs `git add`)

---

## Mode Detection (Multi-repo scope)

**CRITICAL: Use the deterministic script for mode detection. NEVER run bash commands directly to detect mode.**

**If the user requested CWD-only or single-repo commit**: Skip `--detect-mode` entirely. Go straight to the Single-Repo Mode workflow using `--single-repo`:
```bash
scripts/quick-commit.sh --single-repo "commit message"
```

**Otherwise**, call the script's `--detect-mode` flag:

```bash
scripts/quick-commit.sh --detect-mode
```

This returns JSON:
```json
{
  "mode": "single-repo",          // or "multi-repo"
  "reason": "no nested repositories found",
  "nested_repo_count": 0,
  "git_root": "/path/to/repo",
  "working_directory": "/path/to/current/dir",
  "single_repo_override": "--single-repo flag bypasses auto-detection"
}
```

**Why this approach:**
- The script handles detection logic deterministically in bash
- Searches from current working directory downward only (never parent directories)
- `--single-repo` provides explicit CWD-only override for multi-repo workspaces
- No room for Claude to make directory-changing mistakes
- Consistent behavior across all sessions
- Version-controlled, testable code

**Use the returned `mode` value** to decide whether to use single-repo or multi-repo workflow.

---

## Critical Rules

1. **ONLY ask about untracked files** - use AskUserQuestion for files shown as `??` in `git status --short`
2. **NEVER run `git add` on tracked files** - the script uses `git commit -a` which automatically includes all tracked modifications (both staged and unstaged). Do NOT ask the user to confirm or stage tracked files.
3. **ALWAYS use the bash script** - it handles formatting, hooks, and retries
4. **Always diff ALL files** before generating commit messages - do not rely on session memory

---

## Branch Consistency Check (Multi-Repo Only)

Before committing in multi-repo mode, check if repositories are on different branches:

### Step 1: Gather branch information

When discovering repositories, collect the branch name for each repo with changes.

### Step 2: Determine majority branch

```bash
# Count occurrences of each branch
# The most common branch is the "majority branch"
# Example: If 5 repos are on "master" and 1 is on "dev", master is the majority
```

### Step 3: Warn about inconsistent branches

If any repos are on a different branch than the majority, use **AskUserQuestion** BEFORE proceeding:

```
Question: "Some repositories are on different branches. Continue with inconsistent branches?"

Header: "Branches"

Options:
1. Yes, commit all - Proceed with commits to all repositories regardless of branch
2. Skip inconsistent - Only commit to repositories on the majority branch (master)
```

**Warning message to show:**
```
Branch Consistency Warning:

Majority branch: master (5 repositories)

Repositories on different branches:
  - SA_build_agentics: dev

Committing to repositories on different branches may cause inconsistency
when merging or reviewing changes across the workspace.
```

### Step 4: Apply user's choice

- **"Yes, commit all"**: Proceed with all repositories
- **"Skip inconsistent"**: Exclude repositories on non-majority branches from the commit
- **"Other"**: User may specify custom handling

---

## Pre-Flight Checks

The bash script runs automated pre-flight checks before every commit. These checks catch common mistakes early and prevent broken commits from entering the repository.

| Check | Behavior | Blocking? |
|-------|----------|-----------|
| **Git author identity** | Verifies `user.name` and `user.email` are configured | Yes - exits with error and fix instructions |
| **Detached HEAD** | Rejects commits when HEAD is not on a branch | Yes - exits with error and fix instructions |
| **.sh file permissions** | Ensures all `.sh` files being committed have `100755` (executable) mode in the git index | No - auto-fixes with `git update-index --chmod=+x` |
| **Repo root validation** | Warns if working directory differs from `git rev-parse --show-toplevel` | No - advisory warning only |

Pre-flight checks run automatically in both single-repo and multi-repo modes. In multi-repo `--execute` mode, a failed pre-flight check for one repository skips that repo and continues with others.

The `--discover` mode also reports `detached_head: true/false` per repository in its JSON output so Claude can warn the user before attempting commits.

---

## Pre-commit Hook Handling

The bash script automatically handles pre-commit hook failures:

1. **Auto-fix formatting BEFORE commit**: Detects and runs biome/prettier/eslint
2. **Retry on failure**: If pre-commit hook fails, auto-fixes and retries once
3. **Supported formatters**: biome (preferred), prettier, eslint

This ensures commits succeed without manual intervention.

---

## Single-Repo Mode

**First, confirm mode with `--detect-mode`** (the returned `mode` should be `"single-repo"`).

### Step 1: Check for changes and analyze

1. Run `git status --short` to see what files changed
2. If no changes (no tracked modifications AND no untracked files), inform user and STOP
3. Check for untracked files with `git ls-files --others --exclude-standard`
4. Run `git diff` to see the actual content of ALL tracked changes (both staged and unstaged)
   - **DO NOT rely on memory** of what you worked on in the session
   - **DO NOT skip files** - every modified file must be analyzed

**Important - understand file states:**
- **Tracked modifications** (` M`, `M `, `MM` in status): Already tracked by git. The script uses `git commit -a` which **automatically includes ALL tracked modifications** - both staged and unstaged. **Do NOT run `git add` or ask the user about these.**
- **Untracked files** (`??` in status): New files git doesn't know about. These are the ONLY files that need `git add` and user confirmation.

### Step 2: Handle untracked files (if any)

**ONLY ask about files shown as `??` (untracked) in `git status --short`.** Do NOT ask about tracked files that are merely unstaged - `git commit -a` handles those automatically.

If untracked files exist, use **AskUserQuestion** to ask the user:

```
Question: "Found N untracked file(s). Include them in this commit?"

Options:
1. Yes, add all untracked files - Will run `git add` for untracked files only
2. No, commit tracked changes only - Proceed with tracked modifications only
```

**If user chooses "Yes"**:
- Run `git add <file1> <file2> ...` for **untracked files only**
- These files will now be included in the commit

**If user chooses "No"** (or "Other" to skip):
- Proceed with tracked files only (the script's `git commit -a` includes all tracked modifications)
- The script will warn about untracked files but commit will proceed

**Special case - only untracked files, no tracked changes**:
- If there are untracked files but NO tracked modifications, you MUST ask the user
- If user declines to add, inform them "No changes to commit" and STOP

**If there are NO untracked files**: Skip this step entirely. Do NOT use AskUserQuestion. Proceed directly to Step 3.

### Step 3: Generate commit message

- If the user provided text after the command (e.g., `/quick-commit fix typo`), use that as context for the commit message
- Analyze ALL the changes (including newly added files) and create an appropriate commit message:
  - **Simple changes** (1-3 files): Single-line conventional commit (e.g., `feat(profile): add banner`)
  - **Major changes** (5+ files): Multi-line format with summary and bullet points
  - Always use conventional commit format: `feat:`, `fix:`, `refactor:`, `chore:`, `docs:`, etc.

### Step 4: Execute commit via script

Run the bash script with the commit message:

```bash
# If --detect-mode returned single-repo (or no nested repos):
scripts/quick-commit.sh "your commit message here"

# If user requested CWD-only in a multi-repo workspace:
scripts/quick-commit.sh --single-repo "your commit message here"
```

**Note**: In safe mode, the hook will prompt: "Claude wants to run quick-commit.sh. ONLY ALLOW if YOU typed /quick-commit. DENY if you did not request a commit." The user must approve.

The script will:
- Show git status
- Warn about untracked files (but NOT add them)
- Execute `git commit -a -m "message"`
- Show the result

### Step 5: Inform user

Tell the user they can push with `git push` (single-repo) or `/recursive-push` (multi-repo) when ready.

---

## Multi-Repo Mode

**First, confirm mode with `--detect-mode`** (the returned `mode` should be `"multi-repo"`).

### Step 1: Discover repositories with changes

Run the script in discovery mode (use the mode from --detect-mode to set MULTI_REPO if needed):

```bash
MULTI_REPO=true scripts/quick-commit.sh --discover
```

This returns JSON with:
- List of repositories with changes
- File counts per repository
- Branch name for each repository
- Whether approval is needed (based on thresholds: >5 files or >2 repos)

If no repositories have changes, inform user and STOP.

### Step 2: Branch Consistency Check

After discovery, perform the Branch Consistency Check described in the "Branch Consistency Check" section above. If repos are on different branches, warn the user and ask for confirmation before proceeding.

### Step 3: Analyze and generate commit messages

For EACH repository with changes:
1. Navigate to the repository
2. Run `git diff` to see ALL changes
3. Generate an appropriate commit message based on actual diff content
4. **DO NOT rely on memory** - always read the actual diffs

Store the repo path and commit message pairs for execution.

### Step 4: Check approval requirement

From the discovery JSON:
- If `needs_approval: false` (<=5 files across <=2 repos): proceed to Step 4
- If `needs_approval: true`: Show preview and ask user for approval

**Preview format:**
```
Found changes in N repositories:

1. repo/path (X files)
   Files: file1.ts, file2.tsx, ...
   Proposed: "type(scope): description"

2. another/repo (Y files)
   Files: file1.js, file2.json
   Proposed: "type(scope): description"

Total: N repositories, M files

Proceed with these commits? [Y/n]
```

If user does not approve, exit without committing.

### Step 5: Execute commits via script

Run the script in execute mode with all repo:message pairs:

```bash
MULTI_REPO=true scripts/quick-commit.sh --execute \
  "repo/path:commit message one" \
  "another/repo:commit message two"
```

**Important**: The message format is `repo_path:commit_message` where:
- `repo_path` is relative to the working directory
- The first `:` separates path from message
- Message can contain colons

The script will:
- Process each repository
- Warn about untracked files
- Execute commits
- Show summary

### Step 6: Show summary

The script outputs a summary. Tell user they can push with `/recursive-push`.

---

## Safety Features

**Claude Code permission system:**
- In claude-safe mode, running this script requires user permission approval
- The hook prompts: "ONLY ALLOW if YOU typed /quick-commit"
- That approval confirms user intent to commit

**Claude's responsibility (before script):**
1. **Ask ONLY about untracked files**: Use AskUserQuestion to get explicit approval for untracked (`??`) files only
2. **NEVER `git add` tracked files**: Tracked modifications (staged or unstaged) are handled by `git commit -a`. Do not run `git add` on them or ask the user about them.
3. **User-approved staging**: Only run `git add` after user explicitly chooses to include untracked files

**Script's responsibility:**
1. **Never runs `git add`**: Uses `git commit -a` for tracked/staged files only
2. **Untracked file warnings**: Detects and warns about any remaining untracked files
3. **Auto-fix formatting**: Runs biome/prettier/eslint before commit
4. **Pre-commit hook retry**: Retries once after auto-fix if hook fails
5. **Threshold-based approval**: >5 files or >2 repos requires user confirmation
6. **Merge conflict safety**: Avoids `git add -A` which could commit conflict markers

---

## Examples

### Single-repo: Basic commit
```
User: /quick-commit
Claude: [runs: ~/src/.../quick-commit.sh --detect-mode]
        [receives: {"mode": "single-repo", ...}]
        [runs git status --short - sees 2 files modified]
        [runs git diff to see ALL changes]
        [generates message: "refactor(topbar): center BountyForge text"]
        [runs: ~/src/.../quick-commit.sh "refactor(topbar): center BountyForge text"]
        [hook prompts: "ONLY ALLOW if YOU typed /quick-commit"]
        [user approves]
        [script commits, shows result]
```

### Single-repo: With context hint
```
User: /quick-commit fix typo in README
Claude: [runs git status, git diff to analyze changes]
        [uses "fix typo in README" as context hint]
        [generates message: "fix(docs): correct typo in README"]
        [runs: ~/src/.../quick-commit.sh "fix(docs): correct typo in README"]
        [hook prompts, user approves]
        [script executes commit]
```

### Single-repo: Untracked files - user adds them
```
User: /quick-commit
Claude: [runs git status --short - sees 1 modified, 1 untracked]
        [runs git ls-files --others --exclude-standard - finds docs/NewFeature.md]
        [uses AskUserQuestion:
         "Do you want to include untracked files in this commit?"
         Options:
         1. Yes, add all untracked files
         2. No, commit tracked changes only]
User: [selects "Yes, add all untracked files"]
Claude: [runs: git add docs/NewFeature.md]
        [runs git diff --cached to see ALL changes including newly staged]
        [generates message for all changes]
        [runs: ~/src/.../quick-commit.sh "feat(docs): add new feature documentation"]
        [script commits all files]
```

### Single-repo: Untracked files - user skips them
```
User: /quick-commit
Claude: [runs git status --short - sees 1 modified, 1 untracked]
        [uses AskUserQuestion]
User: [selects "No, commit tracked changes only"]
Claude: [runs git diff on tracked files only]
        [generates message for tracked changes]
        [runs: ~/src/.../quick-commit.sh "fix(api): correct endpoint"]
        [script commits tracked files only, warns about untracked]
```

### CWD-only: Force single-repo in multi-repo workspace
```
User: /quick-commit - only commit files in the current directory
Claude: [user requested CWD-only - skip --detect-mode]
        [runs git status --short - sees 3 files modified in root repo]
        [runs git diff to see ALL changes]
        [generates message: "docs: consolidate tracking files"]
        [runs: ~/src/.../quick-commit.sh --single-repo "docs: consolidate tracking files"]
        [hook prompts, user approves]
        [script commits only root repo changes, ignores nested repos]
```

### Multi-repo: Basic commit
```
User: /quick-commit
Claude: [runs: ~/src/.../quick-commit.sh --detect-mode]
        [receives: {"mode": "multi-repo", "nested_repo_count": 48, ...}]
        [runs: MULTI_REPO=true ~/src/.../quick-commit.sh --discover]
        [parses JSON: 2 repos, 4 files]
        [for each repo: git diff, generate message]
        [runs: MULTI_REPO=true ~/src/.../quick-commit.sh --execute \
               "BountyForge/ToolChain:chore: update config files" \
               "ssl_data_spigot:chore: update config files"]
        [hook prompts, user approves]
        [script commits both, shows summary]
```

### Multi-repo: Above threshold (requires approval)
```
User: /quick-commit
Claude: [runs discovery - finds 4 repos, 12 files, needs_approval: true]
        [for each repo: analyzes diffs, generates messages]
        [shows preview:
         Found changes in 4 repositories:
         1. BountyForge/ToolChain (5 files)
            Proposed: "feat(profile): add provider checkboxes"
         2. ssl_data_spigot (3 files)
            Proposed: "fix(trace): update schema"
         ...
         Proceed? [Y/n]]
User: yes
Claude: [runs execute with all repo:message pairs]
        [script commits all, shows summary]
```

### Multi-repo: Branch inconsistency
```
User: /quick-commit
Claude: [runs discovery - finds 4 repos with changes]
        [detects branch inconsistency:
         - 3 repos on "master"
         - 1 repo (SA_build_agentics) on "dev"]
        [shows warning:
         "Branch Consistency Warning:

          Majority branch: master (3 repositories)

          Repositories on different branches:
            - SA_build_agentics: dev

          Committing to repositories on different branches may cause
          inconsistency when merging or reviewing changes."]
        [uses AskUserQuestion:
         "Some repositories are on different branches. Continue?"
         Options:
         1. Yes, commit all
         2. Skip inconsistent]
User: [selects "Yes, commit all"]
Claude: [for each repo: analyzes diffs, generates messages]
        [runs execute with all repo:message pairs]
        [script commits all 4 repos, shows summary]
```

---

## Error Handling

- **No changes**: "No changes detected. Nothing to commit."
- **Branch inconsistency**: Warn user and ask for confirmation before committing to repos on different branches
- **Script not found**: Check `scripts/quick-commit.sh` exists and is executable
- **Permission denied**: In claude-safe mode, user must approve running the script
- **Commit fails**: Script continues with other repos, reports failures
- **User cancels**: Exit gracefully with no commits

---

## Script Reference

```bash
# Single-repo mode (auto-detected or natural single-repo)
scripts/quick-commit.sh "commit message"

# Single-repo mode (forced, bypasses multi-repo auto-detection)
scripts/quick-commit.sh --single-repo "commit message"

# Multi-repo mode (MULTI_REPO=true)
MULTI_REPO=true scripts/quick-commit.sh --discover
MULTI_REPO=true scripts/quick-commit.sh --execute "repo:msg" ...
```

## Safety Architecture

**Layered security model:**

1. **Skill definition guard** (text-based): The "CRITICAL: User-Invoked Only" section at the top of this file instructs Claude to verify user intent before proceeding

2. **Hook permission prompt** (claude-safe mode): The git-hook.sh intercepts quick-commit.sh and prompts: "ONLY ALLOW if YOU typed /quick-commit" - this is the primary safeguard

3. **Optional TTY confirmation**: Set `QUICK_COMMIT_CONFIRM=true` for additional interactive confirmation (useful for direct CLI use)

**Note**: A deterministic safeguard that Claude cannot bypass would require Claude Code enhancements. The current hook-based approach relies on users reading and following the permission prompt.

**Known Issue**: Claude Code caches permission decisions in memory for the session. Once a user approves the hook prompt, subsequent calls to `quick-commit.sh` bypass the hook entirely - even after the file-based allow rule is cleaned up. This means the AI can potentially run `quick-commit.sh` without the hook prompting for the rest of the session. See: [permission cache bypass](https://gitlab.com/smart-assets.io/gitlab-profile/-/blob/master/docs/2026-01-31-claude-code-permission-cache-bypass.md)
