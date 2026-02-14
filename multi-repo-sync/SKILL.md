---
name: multi-repo-sync
description: Synchronize conventions and policies across all repositories in the workspace with branch consistency enforcement
license: SSL
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
---

# Multi-Repo Sync

Workspace-wide synchronization that orchestrates `/harmonize` across all repos with additional consistency checks. This command ensures that all repositories in the workspace share consistent conventions, policies, and branch states before applying harmonization.

Unlike `/harmonize` which operates on individual repositories or subtrees, `/multi-repo-sync` adds a workspace-level coordination layer that includes branch consistency enforcement and cross-repo validation.

## Path Resolution

Scripts referenced below live in the `top-level-gitlab-profile` repository. When running from another repository, resolve the base path first. **Combine this resolution with each script invocation in a single shell command:**

```bash
PROFILE_DIR="$(git rev-parse --show-toplevel)"
if [ ! -d "$PROFILE_DIR/AItools/scripts" ]; then
  for _p in "$PROFILE_DIR/.." "$PROFILE_DIR/../.."; do
    _candidate="$_p/top-level-gitlab-profile"
    if [ -d "$_candidate/AItools/scripts" ]; then
      PROFILE_DIR="$(cd "$_candidate" && pwd)"
      break
    fi
  done
fi
```

Use `"$PROFILE_DIR/AItools/scripts/..."` for all script paths below.

## Usage

```bash
/multi-repo-sync [OPTIONS]
```

## Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Preview all changes without modifying files or running harmonization |
| `--yes`, `-y` | Auto-apply all changes without prompting |
| `--scope [workspace\|subtree]` | Control scan scope: `workspace` scans the entire SA workspace, `subtree` scans from the current directory downward (default: `workspace`) |
| `--verbose` | Show detailed output including per-repo branch states and diff details |
| `--strict[=BRANCH]` | Enforce that all repos are on the specified branch (default: `dev`); blocks sync if any repo diverges |
| `--no-color` | Disable colored output |
| `--help`, `-h` | Show help message |

## What It Does

1. **Discovers all workspace repos** - Scans the workspace (or subtree, depending on `--scope`) to enumerate all git repositories that are candidates for synchronization.

2. **Runs branch consistency check** - Executes `check-repo-consistency.sh --strict` to verify that all discovered repositories are on consistent branches. This catches situations where some repos are on `dev`, others on `master`, and others on feature branches.

3. **If `--strict` fails, blocks and shows fix suggestions** - When branch inconsistency is detected, the sync is blocked before any changes are made. The output includes per-repo branch status and suggested commands to bring repos into alignment (e.g., `git checkout dev` or `git worktree add`).

4. **Runs `/harmonize` per repo with convention awareness** - Iterates through each discovered repository and runs the harmonize-policies script with appropriate flags. Convention-aware settings are passed through so that each repo receives the correct templates and policy sections.

5. **Sets up consistent worktree paths if YOLO mode** - When running in a git worktree (YOLO mode), ensures that worktree paths follow the standardized placement conventions for all repos in the workspace.

6. **Generates workspace-wide summary report** - Produces a consolidated report across all repositories, including total files created, updated, merged, skipped, and any errors. Also reports branch consistency status and any repos that were excluded.

## Prerequisites

- **`check-repo-consistency.sh`** - Branch consistency enforcement script (from EPOCH-019/020). Must be available at `$PROFILE_DIR/AItools/scripts/check-repo-consistency.sh`.
- **`harmonize-policies.sh`** - Policy harmonization script. Must be available at `$PROFILE_DIR/AItools/scripts/harmonize-policies.sh`.
- **Multi-repo workspace** - The workspace must contain multiple git repositories under a common parent directory.

## Examples

### Basic Workspace Sync

```bash
# Sync all repos in the workspace with default settings
/multi-repo-sync

# Preview what would happen without making changes
/multi-repo-sync --dry-run

# Auto-apply all changes without prompting
/multi-repo-sync --yes
```

### Branch-Strict Sync

```bash
# Enforce all repos must be on 'dev' branch (default)
/multi-repo-sync --strict

# Enforce all repos must be on 'master' branch
/multi-repo-sync --strict=master

# Strict mode with dry run to check branch status
/multi-repo-sync --strict --dry-run
```

### Scoped Sync

```bash
# Sync only repos under the current directory
/multi-repo-sync --scope subtree

# Sync entire workspace (default)
/multi-repo-sync --scope workspace
```

## Output Format

### Progress Display

```
+------------------  Multi-Repo Sync  ----------------------+
| Scope: workspace                                          |
| Mode: Interactive                                         |
| Strict: dev                                               |
+-----------------------------------------------------------+

[INFO] Discovering workspace repositories...
[INFO] Found 14 git repositories

[BRANCH CHECK] Running consistency check...
[BRANCH OK] All 14 repositories on branch: dev

[1/14] BountyForge/ToolChain
       /harmonize output...

[2/14] BountyForge/discord-mcp-bot
       /harmonize output...

...

+------------------------  Summary  --------------------------+
| Repositories scanned:  14                                   |
| Branch consistency:    PASS (all on dev)                    |
| Files created:         3                                    |
| Files updated:         1                                    |
| Files merged:          8                                    |
| Already in sync:       42                                   |
| Skipped:               2                                    |
| Errors:                0                                    |
+-------------------------------------------------------------+
```

### Branch Inconsistency Output

```
[BRANCH CHECK] Running consistency check...
[BRANCH FAIL] Inconsistent branches detected:

  Repository                     Branch
  ----------------------------   ----------
  BountyForge/ToolChain          dev
  BountyForge/discord-mcp-bot    master      <-- divergent
  SATCHEL/satchel_ux             feature/x   <-- divergent
  SA_build_agentics              dev

[BLOCKED] Sync blocked due to branch inconsistency.

Suggested fixes:
  cd BountyForge/discord-mcp-bot && git checkout dev
  cd SATCHEL/satchel_ux && git checkout dev
```

## Related Commands

- `/harmonize` - Synchronize policies for individual repositories or subtrees
- `/recursive-push` - Push commits across all repositories
- `/epoch-review` - Review epoch progress across the workspace

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success - all repos synchronized |
| 1 | No repositories found in scope |
| 2 | Branch consistency check failed (with `--strict`) |
| 3 | Invalid arguments |
| 4 | User aborted |
| 5 | One or more repos failed harmonization |
