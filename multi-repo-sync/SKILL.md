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

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/multi-repo-sync [OPTIONS]

Options:
  --wizard              Interactive repo selection wizard
  --clear               Delete saved repo selection and exit
  --all                 Ignore saved selection (this run only)
  --strict[=BRANCH]     Enforce branch consistency (default: dev)
  --dry-run             Preview changes without modifying files
  --yes, -y             Auto-apply without prompting
  --scope workspace|subtree  Scan scope (default: workspace)
  --verbose             Detailed per-repo output
  --no-color            Disable colored output
```

---

# Multi-Repo Sync

Workspace-wide synchronization that orchestrates `/harmonize` across all repos with additional consistency checks. This command ensures that all repositories in the workspace share consistent conventions, policies, and branch states before applying harmonization.

Unlike `/harmonize` which operates on individual repositories or subtrees, `/multi-repo-sync` adds a workspace-level coordination layer that includes branch consistency enforcement, cross-repo validation, and **interactive repo selection**.

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
| `--all` | Ignore saved repo selection, operate on all repos (this run only) |
| `--clear` | Delete saved repo selection config and exit |
| `--wizard` | Output JSON repo tree for interactive selection wizard |
| `--no-color` | Disable colored output |
| `--help`, `-h` | Show help message |

## Repo Selection Wizard

The wizard allows interactive selection of which repos to sync, rather than operating on all ~48 repos every time. Selections are persisted to `.multi-repo-selection.json` in the workspace root.

### Wizard Flow

**Step 0: Check for existing config**

Before running the wizard, check if `.multi-repo-selection.json` exists in the workspace root:

```bash
"$PROFILE_DIR/AItools/scripts/multi-repo-sync.sh" --wizard
```

If the config file exists, use AskUserQuestion:

```
Question: "Found saved repo selection (N/M repos). How to proceed?"
Header: "Selection"
Options:
1. "Use saved selection (Recommended)" - Proceed with existing saved repo selection
2. "Re-run wizard" - Select repos interactively from scratch
3. "Use all repos (this time)" - Override for this run only, keep config
4. "Clear saved selection" - Delete config file and start fresh
```

- **"Use saved selection"**: Skip wizard, proceed to sync with saved config
- **"Re-run wizard"**: Continue to Step 1
- **"Use all repos"**: Pass `--all` flag, proceed to sync
- **"Clear saved selection"**: Run `multi-repo-sync.sh --clear`, then continue to Step 1

**Step 1: Discover workspace tree**

Run the repo-tree script to get workspace structure:

```bash
"$PROFILE_DIR/AItools/scripts/repo-tree.sh" --json --branches --consistency "$WORKSPACE_ROOT"
```

Format the JSON output as a readable markdown table for the user showing groups, repo counts, and branch status.

**Step 2: Group selection**

Use AskUserQuestion with multiSelect to let user pick groups (up to 4 per question):

```
AskUserQuestion (multiSelect: true):
  Question: "Select repository groups to include:"
  Header: "Groups"
  Options:
  1. "BountyForge (7 repos, master)" - All repos on master branch
  2. "SATCHEL (9 repos, mixed)" - 7 on master, 2 divergent
  3. "SmartAssetPrimitives (19 repos, mixed)" - 17 on master, 2 on dev
  4. "Websites_apps (5 repos, master)" - All repos on master
```

If there are more than 4 groups, split into multiple AskUserQuestion calls.

**Step 3: Standalone repo selection**

Use AskUserQuestion with multiSelect for standalone repos (split into batches of 4):

```
AskUserQuestion (multiSelect: true):
  Question: "Select standalone repos to include (1/2):"
  Header: "Standalone"
  Options:
  1. "SA_build_agentics [master]"
  2. "skills [dev]"
  3. "Smart_Assets [master]"
  4. "SovereignAI [master]"
```

**Step 4: Per-group refinement** (only for selected groups with 5+ repos)

For large groups, offer exclusion:

```
AskUserQuestion:
  Question: "SmartAssetPrimitives: Include all 19 repos or exclude specific ones?"
  Header: "Refine"
  Options:
  1. "Include all 19 (Recommended)"
  2. "Exclude some repos"
```

If "Exclude some", paginate repos in batches of 4 with multiSelect to pick exclusions.

**Step 5: Branch consistency** (per inconsistent group)

For groups where repos are on different branches:

```
AskUserQuestion:
  Question: "SATCHEL has 2 repos on non-majority branches. How to handle?"
  Header: "Branches"
  Options:
  1. "Include all" - Keep divergent repos in selection
  2. "Exclude divergent" - Remove repos not on master
  3. "Exclude entire group"
```

**Step 6: Save config and proceed**

Write `.multi-repo-selection.json` to workspace root using the Write tool:

```json
{
  "version": 1,
  "mode": "include",
  "updated_at": "2026-02-14T10:00:00Z",
  "groups": ["BountyForge", "SATCHEL"],
  "repos": ["SA_build_agentics", "top-level-gitlab-profile"],
  "excluded_repos": ["SATCHEL/lightning-rgb-node"]
}
```

Show summary (e.g., "Selected 42/51 repos") and proceed with sync.

### Selection Config Format

The `.multi-repo-selection.json` file uses "include" mode resolution:

1. Start with empty set
2. Add all repos from listed `groups` (discovered at runtime)
3. Add individually listed `repos`
4. Remove anything in `excluded_repos`

This handles the common case of selecting a large group and excluding 1-2 repos.

### Clearing Selection

Three ways to clear or bypass the saved selection:

| Method | Behavior |
|--------|----------|
| `/multi-repo-sync --clear` | Deletes `.multi-repo-selection.json` and exits |
| Wizard Step 0 option 4 | Deletes config, re-runs wizard from Step 1 |
| `/multi-repo-sync --all` | Ignores config for this run (does not delete it) |

## Cross-Command Selection

When a repo selection config exists, ALL multi-repo commands honor it:

| Command | Behavior with selection config |
|---------|-------------------------------|
| `/multi-repo-sync` | Only syncs selected repos |
| `/quick-commit --discover` | Only discovers changes in selected repos |
| `/harmonize` (via multi-repo-sync) | Only harmonizes selected repos |
| `check-repo-consistency.sh` | Only checks selected repos |

Pass `MULTI_REPO_ALL=true` or `--all` to any command to bypass the selection for a single run.

## What It Does

1. **Checks for saved repo selection** - Loads `.multi-repo-selection.json` if present, or runs wizard if `--wizard` specified.

2. **Discovers workspace repos** - Scans the workspace (or subtree, depending on `--scope`) to enumerate all git repositories that are candidates for synchronization, filtered by selection config.

3. **Runs branch consistency check** - Executes `check-repo-consistency.sh --strict` to verify that all selected repositories are on consistent branches.

4. **If `--strict` fails, blocks and shows fix suggestions** - When branch inconsistency is detected, the sync is blocked before any changes are made.

5. **Runs `/harmonize` per repo with convention awareness** - Iterates through each selected repository and runs the harmonize-policies script.

6. **Generates workspace-wide summary report** - Consolidated report across all selected repositories.

## Prerequisites

- **`check-repo-consistency.sh`** - Branch consistency enforcement script.
- **`harmonize-policies.sh`** - Policy harmonization script.
- **`repo-tree.sh`** - Workspace tree discovery (for wizard mode).
- **`lib/repo-selection.sh`** - Repo selection filtering library.
- **Multi-repo workspace** - The workspace must contain multiple git repositories under a common parent directory.
- **`jq`** - Required for JSON config parsing.

## Examples

### Basic Workspace Sync

```bash
# Sync all repos in the workspace (or saved selection)
/multi-repo-sync

# Preview what would happen without making changes
/multi-repo-sync --dry-run

# Auto-apply all changes without prompting
/multi-repo-sync --yes
```

### With Repo Selection

```bash
# Run interactive wizard to select repos
/multi-repo-sync --wizard

# Override saved selection for this run
/multi-repo-sync --all

# Clear saved selection
/multi-repo-sync --clear
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
| Scope: workspace (SA/)                                    |
| Repos: 42/51 repos selected                              |
+-----------------------------------------------------------+

[INFO] Running branch consistency check...
[OK] Branch consistency: PASS

[INFO] Running harmonize-policies across workspace...
...

+---------------------  Sync Summary  -----------------------+
| Branch consistency: PASS (all on master)                   |
+-----------------------------------------------------------+
```

### Branch Inconsistency Output

```
[BRANCH CHECK] Running consistency check...
[BRANCH FAIL] Inconsistent branches detected:

  Repository                     Branch
  ----------------------------   ----------
  BountyForge/discord-mcp-bot    master      <-- divergent
  SATCHEL/satchel_ux             feature/x   <-- divergent

[BLOCKED] Sync blocked due to branch inconsistency.

Suggested fixes:
  cd BountyForge/discord-mcp-bot && git checkout dev
  cd SATCHEL/satchel_ux && git checkout dev
```

## Related Commands

- `/harmonize` - Synchronize policies for individual repositories or subtrees
- `/recursive-push` - Push commits across all repositories
- `/quick-commit` - Commit changes across repositories
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
