---
name: git-commit
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
/git-commit [OPTIONS] [message]
/skill:git-commit [OPTIONS] [message]
/git:commit [OPTIONS] [message]      # legacy alias
/quick-commit [OPTIONS] [message]    # legacy alias

Options:
  --single-repo         Commit only in current directory (skip multi-repo detection)
  --discover            Discover repos with changes (multi-repo mode)
  [message]             Commit message (auto-generated if omitted)

Repo selection: Honors .multi-repo-selection.jsonc if present. MULTI_REPO_ALL=true to bypass.
```

---

## Invocation Guard

This skill requires explicit user invocation. It must not be triggered proactively by the assistant after completing code changes, passing tests, or finishing tasks.

**Accepted invocations:**
- Claude/legacy surfaces: `/quick-commit` or `/git:commit`
- Pi slash commands: `/skill:git-commit`, `/git-commit`, or `/skill:quick-commit`
- Pi selected-skill payloads: `<skill name="git-commit" ...>` or
  `<skill name="quick-commit" ...>` injected by the harness for this turn

**Expected workflow:**
1. Assistant completes work and informs the user
2. Assistant waits for user input
3. User explicitly invokes one of the accepted commit commands, or the harness
   injects this selected skill payload as the user's command for the turn

**Validation:** Proceed when either condition is true:
- the current user message contains an accepted commit command, such as
  `<command-name>/quick-commit</command-name>`,
  `<command-name>/git:commit</command-name>`,
  `<command-name>/skill:git-commit</command-name>`, or
  `<command-name>/git-commit</command-name>`; or
- Pi has injected the selected skill payload for this turn, visible as
  `<skill name="git-commit" ...>` or `<skill name="quick-commit" ...>`.

Do not require the literal slash command in addition to a Pi selected-skill
payload. Do not proceed from ordinary prose such as "please commit" unless one
of the accepted command or selected-skill signals above is present.

---

You are helping the user create git commits (single-repo or multi-repo mode).

**Claude Config Modes**: This command works in both claude configurations:

| Config | Command | Behavior |
|--------|---------|----------|
| `~/.claude` | `claude` / `claude-safe` | Restrictive hooks block direct git commands. Use `/quick-commit` or `/git:commit` for commits (requires user permission approval) |
| `~/.claude-agentic` | `claude-agentic` | No restrictive hooks. Direct git commands allowed, but this command still provides intelligent commit messages |
| Pi | `pi` | Invoke as `/skill:git-commit` or `/git-commit`. Pi does not load Claude Code hooks, so rely on explicit invocation and review script actions before approving them. |

**Repo selection**: In multi-repo mode, if a `.multi-repo-selection.jsonc` config exists in the workspace root (created by `/multi-repo-sync --wizard`), discovery will only show repos matching the selection. Set `MULTI_REPO_ALL=true` to bypass.

**Auto-detection for multi-repo**: This command uses deterministic mode detection via the `--detect-mode` flag:
1. Call `git-commit.sh --detect-mode` first (returns JSON with mode decision)
2. The script checks `MULTI_REPO` environment variable (`true` forces multi-repo, `false` forces single-repo)
3. If not set, the script searches for nested `.git` directories from current directory downward
4. Returns `"single-repo"` or `"multi-repo"` - Claude uses this to decide workflow
5. **Claude NEVER runs bash commands to detect mode** - the script handles it deterministically

**CWD-only / single-repo override**: When the user requests committing only in the current working directory (e.g., `/quick-commit - only current directory`), use `--single-repo` to bypass multi-repo auto-detection:
- Pass `--single-repo` as the first argument: `git-commit.sh --single-repo "message"`
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

```bash
scripts/git-commit.sh
```

Resolve the commit script relative to this skill/command's own location, not
relative to the target repository being committed. In Pi the script is bundled
under this generated skill directory (the sibling `scripts/git-commit.sh`); in
Claude it resolves via `$SA_GITLAB_PROFILE`.

`git-commit.sh` is the canonical entrypoint. It delegates to `quick-commit.sh`, which remains available as the legacy compatibility implementation.

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
scripts/git-commit.sh --single-repo "commit message"
```

**Otherwise**, call the script's `--detect-mode` flag:

```bash
scripts/git-commit.sh --detect-mode
```

This returns JSON:
```json
{
  "mode": "single-repo",          // or "multi-repo" or "ambiguous"
  "reason": "no nested repositories found",
  "nested_repo_count": 0,
  "cwd_is_git_repo": true,
  "cwd_has_tracked_changes": false,
  "cwd_origin": "git@gitlab.com:smart-assets.io/foo.git",
  "recommended_default": "single-repo", // present only when "ambiguous"; always single-repo (fan-out is opt-in)
  "git_root": "/path/to/repo",
  "working_directory": "/path/to/current/dir",
  "single_repo_override": "--single-repo flag bypasses auto-detection"
}
```

**Three modes:**
- `"single-repo"`: no nested repos found, or `MULTI_REPO=false`. Use Single-Repo Mode workflow.
- `"multi-repo"`: nested repos exist and cwd has no tracked changes (no risk of dropping work), or `MULTI_REPO=true`. Use Multi-Repo Mode workflow.
- `"ambiguous"`: nested repos exist AND cwd has tracked changes. **You MUST prompt the user** before proceeding (see "Ambiguous Mode" section below). Never silently pick — the cwd's tracked changes will be silently dropped if you default to multi-repo without confirmation.

**Why this approach:**
- The script handles detection logic deterministically in bash
- Searches from current working directory downward only (never parent directories)
- `--single-repo` provides explicit CWD-only override for multi-repo workspaces
- No room for Claude to make directory-changing mistakes
- Consistent behavior across all sessions
- Version-controlled, testable code

**Use the returned `mode` value** to decide whether to use single-repo, multi-repo, or ambiguous-prompt workflow.

---

## Ambiguous Mode

When `--detect-mode` returns `"mode": "ambiguous"`, the cwd is itself a git repo with tracked changes AND there are nested repos below it. Auto-picking multi-repo would silently drop the cwd's tracked changes — this is the bug fixed by ambiguous-mode classification.

**You MUST prompt the user with AskUserQuestion before proceeding.** Use the `recommended_default` field to mark the recommended option.

```
Question: "Detected tracked changes in the current directory AND nested git repositories. Which scope should /quick-commit use?"

Header: "Scope"

Options:
1. Single-repo (commit only the current directory) - Commits tracked changes in the cwd repo only; ignores nested repos. Equivalent to --single-repo.
2. Multi-repo (commit across cwd + nested repos) - Includes the cwd repo and nested repos in the discover/execute flow.

Mark whichever option matches `recommended_default` from the --detect-mode JSON with "(Recommended)".
```

**Why the recommendation is always single-repo (in the script):**
- Workspace convention: fan-out across nested repositories is an explicit, user-chosen opt-in — never a recommendation. `recommended_default` is therefore always `single-repo` in ambiguous mode.
- Multi-repo remains available as the non-default option; choosing it leads into the plan-gated discover/execute flow below.
- (An earlier origin-comparison heuristic recommended multi-repo for no-origin umbrella directories — exactly backwards for umbrella workspaces, where the umbrella itself is the intended commit target.)

**Apply the user's choice:**
- "Single-repo" → run `git-commit.sh --single-repo "message"` (skip Multi-Repo Mode entirely)
- "Multi-repo" → set `MULTI_REPO=true` and follow Multi-Repo Mode below; the discover output will include the cwd as a `is_start_directory: true` entry

---

## Critical Rules

1. **ONLY ask about untracked files** - use AskUserQuestion for files shown as `??` in `git status --short`
2. **NEVER run `git add` on tracked files** - the script uses `git commit -a` which automatically includes all tracked modifications (both staged and unstaged). Do NOT ask the user to confirm or stage tracked files.
3. **ALWAYS use the bash script** - it handles formatting, hooks, and retries
4. **Always diff ALL files** before generating commit messages - do not rely on session memory
5. **NEVER offer to `git add` a directory that contains its own `.git`** - see Nested Untracked Git Repos below. Adding such a path creates an unwanted gitlink/submodule reference.
6. **Mixed staging is valid** - staged additions plus unstaged tracked
   modifications are a normal commit state. Do not block, ask the user to
   clean the index, or unstage/restage files just because status is mixed
   (`A`, `M`, `AM`, `MM`). Analyze the combined `HEAD` diff and let the script
   commit the staged index plus tracked modifications.

---

## Nested Untracked Git Repos

When iterating untracked paths from `git ls-files --others --exclude-standard` (or `??` lines from `git status --short`), some entries may be directories that contain their own `.git`. These are **independent git repositories**, not regular untracked content. `git add` on such a path produces a gitlink (a special index entry pointing to a commit SHA) — a submodule reference that is almost certainly not the user's intent in a subtree-style workspace.

**For each untracked path** (Bash):

```bash
if [ -d "<path>/.git" ]; then
    # Nested git repo - DO NOT include in "add untracked?" prompt
fi
```

**Handling rules:**
- **Exclude** these paths from the AskUserQuestion "add untracked?" options entirely. Never offer them as options the user can select.
- **Surface them separately** in your response, once, before or after the prompt. Example wording:
  > Detected N nested git repo(s) appearing as untracked content from this repo's perspective: `path1/`, `path2/`. These would create gitlink/submodule references if added — they are skipped automatically. If you intended to add one as a submodule, run `git submodule add <url> <path>` yourself and re-run /quick-commit.
- The script's `--discover` output (multi-repo mode) already separates nested repos into their own entries, so this rule applies primarily to the single-repo flow's untracked handling.

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

The bash script does **not** auto-fix formatting or lint issues. If the pre-commit hook fails, the script retries the commit once and then surfaces the failure.

**Why no auto-fix:** Running fixers (biome/prettier/eslint, ruff/black, `cargo clippy --fix`, `cargo fix`, etc.) between staging and `write-tree` mutates tracked files mid-commit and desyncs the index / cache-tree. This produced corrupted commits, so the auto-fix path was removed entirely.

**Anti-pattern — do NOT do this:**
- Do not invoke `cargo clippy --fix` (even with `--allow-dirty --allow-staged`), `cargo fix`, or any in-place rewriter as part of the commit pipeline. `--allow-staged` rewrites the working tree without re-staging, so the indexed blobs no longer match the files on disk and the cache-tree becomes invalid.
- The same hazard applies to `prettier --write`, `eslint --fix`, `ruff check --fix`, `ruff format`, `black .`, and any other formatter that edits tracked files.

**If the pre-commit hook fails:** Claude (the caller) is responsible for fixing it — run the appropriate formatter, re-stage, then re-invoke `/quick-commit`. The script will not paper over hook failures.

---

## Single-Repo Mode

**First, confirm mode with `--detect-mode`** (the returned `mode` should be `"single-repo"`).

### Step 1: Check for changes and analyze

1. Run `git status --short` to see what files changed
2. If no changes (no tracked modifications AND no untracked files), inform user and STOP
3. Check for untracked files with `git ls-files --others --exclude-standard`
4. Run `git diff HEAD --` to see the actual content of ALL changes that
   would be committed (staged additions, staged modifications, and unstaged
   tracked modifications)
   - **DO NOT rely on memory** of what you worked on in the session
   - **DO NOT skip files** - every modified file must be analyzed
   - Mixed status (`A`, `M`, `AM`, `MM`) is expected and should be handled as
     one combined commit unless the user asks for a narrower scope

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
scripts/git-commit.sh "your commit message here"

# If user requested CWD-only in a multi-repo workspace:
scripts/git-commit.sh --single-repo "your commit message here"
```

**Note**: In safe mode, the hook will prompt: "Claude wants to run quick-commit.sh. ONLY ALLOW if YOU typed /quick-commit. DENY if you did not request a commit." The user must approve.

The script will:
- Show git status
- Warn about untracked files (but NOT add them)
- Execute `git commit -a -m "message"`
- Show the result

### Step 5: Inform user

Tell the user they can push with `git push` (single-repo), `/git:push` (canonical Smart Assets workflow), or `/recursive-push` (legacy alias) when ready.

---

## Multi-Repo Mode

**First, confirm mode with `--detect-mode`** (the returned `mode` should be `"multi-repo"`).

### Step 1: Discover repositories with changes

Run the script in discovery mode (use the mode from --detect-mode to set MULTI_REPO if needed):

```bash
MULTI_REPO=true scripts/git-commit.sh --discover
```

This returns JSON with:
- A top-level `start_directory` block describing the cwd repo (`is_git_repo`, `has_changes`, `origin`, `included_in_array`)
- List of repositories with changes — including the cwd repo as the first entry with `"is_start_directory": true` when it has tracked or untracked changes
- File counts per repository
- Branch name for each repository
- Whether approval is needed (based on thresholds: >5 files or >2 repos)
- A `plan` block (`plan.id`) recording the discovered repo set and each repo's state — `--execute` requires this id (see the plan gate in Step 5)

**Start-directory inclusion is critical.** A previous version of this script silently omitted the cwd repo when nested repos existed, dropping tracked changes from `--discover` output. The `is_start_directory: true` flag and the `start_directory` metadata block exist precisely so you can never miss it. **Before generating commit messages, verify: if `start_directory.has_changes == true`, the repositories array MUST contain an entry with `is_start_directory: true`. If it does not, that is a bug — surface it to the user and STOP.**

**Selection-config filtering must also be surfaced.** The discover output includes a top-level `selection` block:

```json
"selection": {
  "config_path": "/path/to/.multi-repo-selection.jsonc",
  "config_loaded": true,
  "config_updated_at": "2026-02-28T00:00:00Z",
  "stale": true,
  "auto_bypassed": true,
  "stale_reason": "selection config excluded 6 repo(s) with uncommitted changes; config bypassed for this run",
  "excluded_total": 0,
  "excluded_with_changes": [],
  "bypassed_with_changes": ["SATCHEL/SatchelSmartWallet", "Websites_apps/foo"]
}
```

**Stale configs are detected and bypassed automatically — you do NOT prompt about them.** A selection config is "stale" (drift) when it would exclude one or more repos that currently have uncommitted changes. The script detects this during `--discover` and, per policy, does NOT use a stale config: it disables the selection for that run so the `repositories` array already includes every dirty repo. When this happens, `selection.stale` and `selection.auto_bypassed` are both `true`, and `selection.bypassed_with_changes` lists the repos that the stale config would have dropped. `config_updated_at` is surfaced for context only — age does not define staleness.

**If `selection.auto_bypassed` is `true`**, simply inform the user (one line, no AskUserQuestion) that the stale config was bypassed and all repos with changes are included, then continue with the normal flow:

```
Note: .multi-repo-selection.jsonc was stale (it would have excluded N repo(s) with uncommitted changes: <bypassed_with_changes list>). It was bypassed automatically — all repos with changes are included below.
```

The normal `needs_approval` preview (Step 4) remains the confirmation gate before any commit is made; do not add a separate prompt for the bypass. If the user genuinely wants the filtered set honored, they must update or remove `.multi-repo-selection.jsonc` (a stale config is never silently honored).

If no repositories have changes, inform user and STOP.

### Step 2: Branch Consistency Check

After discovery, perform the Branch Consistency Check described in the "Branch Consistency Check" section above. If repos are on different branches, warn the user and ask for confirmation before proceeding.

### Step 3: Analyze and generate commit messages

For EACH repository with changes:
1. Navigate to the repository
2. Run `git diff HEAD --` to see ALL staged and unstaged tracked changes
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

Run the script in execute mode with the plan id from Step 1 and all repo:message pairs:

```bash
MULTI_REPO=true scripts/git-commit.sh --execute \
  --plan <plan.id> \
  "repo/path:commit message one" \
  "another/repo:commit message two"
```

**Important**: The message format is `repo_path:commit_message` where:
- `repo_path` is relative to the working directory
- The first `:` separates path from message
- Message can contain colons

**Plan gate (two-phase confirm)**: `--execute` requires `--plan <plan.id>` — the id emitted by this session's `--discover` output. This is a deterministic guard in the script, not an instruction: plans are single-use, expire after 15 minutes (`QUICK_COMMIT_PLAN_TTL` seconds), and execution is refused outright if any target repo is missing from the plan or its state changed since discovery (new commits or files; staging previously-discovered files is fine). On refusal, re-run `--discover`, re-confirm the repo list with the user, and use the fresh plan id. The confirmed repo set is therefore exactly — and the most — that can execute.

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
3. **Never auto-fixes lint/format**: Mutating tracked files mid-commit corrupts the index/cache-tree (see Pre-commit Hook Handling). Fixing hook failures is the caller's responsibility.
4. **Pre-commit hook retry**: Retries the commit once on failure (no auto-fix between attempts)
5. **Threshold-based approval**: >5 files or >2 repos requires user confirmation
6. **Merge conflict safety**: Avoids `git add -A` which could commit conflict markers

---

## Examples

### Single-repo: Basic commit
```
User: /quick-commit
Claude: [runs: scripts/quick-commit.sh --detect-mode]
        [receives: {"mode": "single-repo", ...}]
        [runs git status --short - sees 2 files modified]
        [runs git diff to see ALL changes]
        [generates message: "refactor(topbar): center BountyForge text"]
        [runs: scripts/quick-commit.sh "refactor(topbar): center BountyForge text"]
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
        [runs: scripts/quick-commit.sh "fix(docs): correct typo in README"]
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
        [runs: scripts/quick-commit.sh "feat(docs): add new feature documentation"]
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
        [runs: scripts/quick-commit.sh "fix(api): correct endpoint"]
        [script commits tracked files only, warns about untracked]
```

### CWD-only: Force single-repo in multi-repo workspace
```
User: /quick-commit - only commit files in the current directory
Claude: [user requested CWD-only - skip --detect-mode]
        [runs git status --short - sees 3 files modified in root repo]
        [runs git diff to see ALL changes]
        [generates message: "docs: consolidate tracking files"]
        [runs: scripts/quick-commit.sh --single-repo "docs: consolidate tracking files"]
        [hook prompts, user approves]
        [script commits only root repo changes, ignores nested repos]
```

### Multi-repo: Basic commit
```
User: /quick-commit
Claude: [runs: scripts/quick-commit.sh --detect-mode]
        [receives: {"mode": "multi-repo", "nested_repo_count": 48, ...}]
        [runs: MULTI_REPO=true scripts/quick-commit.sh --discover]
        [parses JSON: 2 repos, 4 files]
        [for each repo: git diff, generate message]
        [runs: MULTI_REPO=true scripts/quick-commit.sh --execute \
               --plan <plan.id from --discover> \
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
- **Script not found**: Check `scripts/git-commit.sh` exists and is executable
- **Permission denied**: In claude-safe mode, user must approve running the script
- **Commit fails**: Script continues with other repos, reports failures
- **User cancels**: Exit gracefully with no commits

---

## Script Reference

```bash
# Single-repo mode (auto-detected or natural single-repo)
scripts/git-commit.sh "commit message"

# Single-repo mode (forced, bypasses multi-repo auto-detection)
scripts/git-commit.sh --single-repo "commit message"

# Multi-repo mode (MULTI_REPO=true)
MULTI_REPO=true scripts/git-commit.sh --discover
MULTI_REPO=true scripts/git-commit.sh --execute --plan <plan.id> "repo:msg" ...
```

## Safety Architecture

**Layered security model:**

0. **Plan gate** (deterministic, in-script): multi-repo `--execute` requires a fresh, single-use plan id from `--discover` covering exactly the repos being committed (see Step 5). A PreToolUse hook (`scripts/fanout-gate-hook.sh`, wired via the workspace `.claude/settings.json`) additionally forces a native user permission prompt on any `--execute` invocation, independent of what the model decided.

1. **Skill definition guard** (text-based): The "CRITICAL: User-Invoked Only" section at the top of this file instructs Claude to verify user intent before proceeding

2. **Hook permission prompt** (claude-safe mode): The bash-permission-hook.sh intercepts quick-commit.sh and prompts: "ONLY ALLOW if YOU typed /quick-commit" - this is the primary safeguard

3. **Optional TTY confirmation**: Set `QUICK_COMMIT_CONFIRM=true` for additional interactive confirmation (useful for direct CLI use)

**Note**: A deterministic safeguard that Claude cannot bypass would require Claude Code enhancements. The current hook-based approach relies on users reading and following the permission prompt.

**Known Issue**: Claude Code caches permission decisions in memory for the session. Once a user approves the hook prompt, subsequent calls to `quick-commit.sh` bypass the hook entirely - even after the file-based allow rule is cleaned up. This means the AI can potentially run `quick-commit.sh` without the hook prompting for the rest of the session. See: [permission cache bypass](https://gitlab.com/smart-assets.io/gitlab-profile/-/blob/master/docs/2026-01-31-claude-code-permission-cache-bypass.md)
