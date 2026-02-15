---
name: version
description: Show git commit hash and date for workflow tools and current repository
license: SSL
---

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/version [OPTIONS]

Options:
  --json                Machine-readable JSON output
  MULTI_REPO=true       Show all repos in workspace (env var)

Default: Shows workflow tools version + current repo.
```

---

You are helping the user check the version of their workflow tools and repositories.

**Purpose**: Provide users with commit hash and date information to verify they're on the current iteration of the workflow.

---

## Architecture

**This command uses a deterministic bash script:**

```
scripts/version.sh
```

**Claude's role**:
- Run the script with appropriate options
- Present the output to the user
- Show the current implementer identity (`git config --get user.email` / `git config --get user.name`) and the `claimed_by` value that would be used when claiming tasks
- Explain what the versions mean if asked

**Script's role**: Deterministic version retrieval from git repositories

---

## Mode Detection

The script automatically supports:
1. **Single-repo mode** (default): Shows workflow tools version + current repo if different
2. **Multi-repo mode** (`MULTI_REPO=true`): Shows all repos in the workspace

---

## Usage

### Basic Usage (Single-repo)

Run the script to show workflow tools version and current repo (if different):

```bash
scripts/version.sh
```

### Multi-repo Mode

Show versions for all repositories in the workspace:

```bash
MULTI_REPO=true scripts/version.sh
```

### JSON Output

For programmatic use, add `--json` flag:

```bash
scripts/version.sh --json
```

---

## Output

The script displays:

1. **Workflow Tools** - The top-level-gitlab-profile repository version (where commands/scripts live)
   - Commit hash (short SHA)
   - Commit date

2. **Current Repository** (single-repo mode) - If the user is in a different git repo
   - Repository name
   - Commit hash
   - Commit date

3. **All Repositories** (multi-repo mode) - Every git repo in the workspace
   - Repository name
   - Commit hash
   - Commit date

4. **Implementer Identity** - The current user's `claimed_by` identifier derived from git config
   - `git config --get user.email` → `human-{email}`
   - `git config --get user.name` → fallback if email not set
   - Helps verify which identity will be used when claiming tasks via `/implement` or `/work-tasks`
   - See [Implementer Identification](../docs/common/stigmergic-collaboration.md#implementer-identification) for the full format reference

---

## Examples

### User wants to check their version

```
User: /version
Claude: [runs: scripts/version.sh]
        [displays output showing workflow tools version and current repo]
```

### User wants to see all repo versions

```
User: /version (with MULTI_REPO=true set)
Claude: [runs: MULTI_REPO=true scripts/version.sh]
        [displays output showing all repository versions in workspace]
```

### User wants JSON output

```
User: /version --json
Claude: [runs: scripts/version.sh --json]
        [displays JSON output]
```

---

## When to Use

Users should run `/version` when:
- Verifying they have the latest workflow tools
- Troubleshooting issues (to report exact version)
- Checking which commit they're working from
- Comparing their environment with others

---

## Error Handling

- **Not in a git repo**: Script shows workflow tools version and notes current directory is not a git repository
- **Git not available**: Script fails with error message
- **Repository inaccessible**: Individual repos are skipped with warnings
