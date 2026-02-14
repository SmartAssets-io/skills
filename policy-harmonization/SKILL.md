---
name: policy-harmonization
description: Synchronize policies, approaches, and conventions across repositories by harmonizing with top-level-gitlab-profile standards
license: SSL
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
---

# Harmonize Policies

Synchronize policies, approaches, and conventions across repositories. This command harmonizes target projects with the patterns and standards defined in `top-level-gitlab-profile`.

**Important:** The script scans **downward from your current working directory**. It does NOT scan parent directories or the entire workspace.

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

## Configuration File Conventions

When this command creates or modifies any configuration files:

1. **Check for existing files first**: Before creating any `.json` file, check if `.jsonc` or `.json5` variants exist
2. **Prefer existing format**: If `config.jsonc` or `config.json5` exists, use that format instead of creating `config.json`
3. **Default to JSONC**: When creating new config files, prefer `.jsonc` (JSON with Comments) for better maintainability

This applies to all project scaffolding and template operations.

## Usage

Run the harmonize-policies script from the directory you want to harmonize:

```bash
# From any directory - use the full path to the script
"$PROFILE_DIR/AItools/scripts/harmonize-policies.sh" [PATH] [OPTIONS]
```

The script auto-detects its location to find templates, so you can run it from anywhere.

## Modes

### Current Repository Only

When run from a project directory without arguments, harmonizes only that repository:

```bash
cd /path/to/my-project
"$PROFILE_DIR/AItools/scripts/harmonize-policies.sh"
# Scans only my-project/
```

### Subtree of Repositories

To harmonize multiple repositories, run from a parent directory or specify a PATH:

```bash
cd /path/to/SATCHEL
"$PROFILE_DIR/AItools/scripts/harmonize-policies.sh"
# Scans all repos under SATCHEL/

# Or specify a relative path from cwd:
"$PROFILE_DIR/AItools/scripts/harmonize-policies.sh" ./subdir/
```

### Dry Run Preview

Preview what would change without modifying any files:

```bash
"$PROFILE_DIR/AItools/scripts/harmonize-policies.sh" --dry-run
"$PROFILE_DIR/AItools/scripts/harmonize-policies.sh" ./subdir/ --dry-run
```

## Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Preview changes without modifying files |
| `--force` | Overwrite customized files (default: preserve them) |
| `--yes`, `-y` | Auto-apply all changes without prompting |
| `--source DIR` | Override source template directory |
| `--scaffold-sa[=MODE]` | Control Smart Asset scaffolding (see below) |
| `--verbose` | Show detailed diff output |
| `--no-color` | Disable colored output |
| `--help`, `-h` | Show help message |

### Smart Asset Scaffolding Modes (`--scaffold-sa`)

| Mode | Behavior |
|------|----------|
| `auto` | (Default) Use YOLO mode setting - scaffold without prompts in worktrees, prompt in interactive mode |
| `ask` | Always prompt before scaffolding, even in YOLO mode |
| `skip` | Disable all Smart Asset scaffolding |
| `force` | Scaffold without prompting, even in interactive mode |

**Important:** By default, files that exist and differ from templates are **preserved** and marked as `[CUSTOMIZED]`. Use `--force` only if you explicitly want to overwrite customized content with templates.

## Operational Modes

The command behaves differently based on the environment:

| Mode | Detection | Behavior |
|------|-----------|----------|
| **YOLO** | Git worktree | Direct changes, no confirmation prompts |
| **Non-Interactive** | No TTY (Claude Code, CI/CD) | Auto-applies all changes |
| **Explicit Auto** | `--yes` or `-y` flag | Auto-applies all changes |
| **Interactive** | TTY present (terminal) | Per-file confirmation required |

### Auto-Apply Mode (Non-Interactive)

When run from Claude Code, CI/CD pipelines, or any context without a TTY, the command automatically applies all changes without prompting. This enables seamless automation.

```bash
# These all auto-apply (no TTY):
# - From Claude Code via /harmonize
# - From CI/CD pipeline
# - Piped input: echo "" | ./harmonize-policies.sh

# Explicit auto-apply with TTY present:
./harmonize-policies.sh --yes
./harmonize-policies.sh -y
```

### YOLO Mode (Git Worktrees)

When running in a git worktree, the command also auto-applies:

```bash
# Create worktree and use claude-agentic
git worktree add ../myproject-worktree feature/updates
cd ../myproject-worktree
claude-agentic
# Then run /harmonize - auto-applies
```

### Interactive Mode

When a TTY is present (running directly in terminal), prompts for each change:

```
[3/12] SATCHEL/satchelprotocol
       [UPDATE] CLAUDE.md - Content differs from template

       Apply changes? [y/N/d(iff)/q(uit)]:
```

Responses:
- `y` - Apply the change
- `n` or Enter - Skip this file
- `d` - View full diff before deciding
- `q` - Quit and skip all remaining

## Files Harmonized

The command checks and synchronizes files using **section-based merging**. Files are categorized into two types:

### File Categories

| Category | Behavior | Rationale |
|----------|----------|-----------|
| **Merge-only** | Only merge policy sections when file already exists; never auto-create | Too project-specific to create from template |
| **Create-able** | Create from template if missing; merge sections when file exists | Structural templates with clear patterns |

### Files by Category

#### Merge-Only Files (Never Auto-Created)

| File | Source | Purpose |
|------|--------|---------|
| `CLAUDE.md` | Template + prompts | AI assistant guidance (primary, single source of truth) |
| `AGENTS.md` | Derived from CLAUDE.md | AI assistant guidance (condensed) |

These files require significant project-specific customization (project context, architecture, commands) that cannot be templated. The harmonize command will:
- **Skip** the file if it doesn't exist (user must create manually or via `/create-smart-asset`)
- **Merge** standard policy sections if the file exists, preserving project-specific content

#### Create-able Files (Auto-Created from Template)

| File | Source | Purpose |
|------|--------|---------|
| `GEMINI.md` | Template | Gemini CLI pointer to CLAUDE.md |
| `docs/ToDos.md` | Template | Task tracking with MR frontmatter |
| `docs/UserStories.md` | Template | User stories driving feature development |
| `docs/Backlog.md` | Template | Three-file pattern - backlog |
| `docs/CompletedTasks.md` | Template | Three-file pattern - completed |
| `signers.jsonc` | Template | Publisher key registry (Smart Asset repos only) |

These files follow well-defined structural patterns. The harmonize command will:
- **Create** the file from template if it doesn't exist
- **Merge** standard sections if the file exists, preserving project-specific content

### Example Behavior

```bash
# Repository without CLAUDE.md
/harmonize --dry-run
# Output: [SKIP] CLAUDE.md - merge-only file does not exist

# Repository with CLAUDE.md
/harmonize --dry-run
# Output: [MERGE] CLAUDE.md - 2 policy sections will be updated

# Repository without docs/ToDos.md
/harmonize --dry-run
# Output: [CREATE] docs/ToDos.md - will be created from template

# Repository with docs/ToDos.md
/harmonize --dry-run
# Output: [MERGE] docs/ToDos.md - preserving project content, updating structure
```

### Smart Asset Repository Detection

The harmonize command detects different types of Smart Asset repositories and applies appropriate handling:

| Type | Detection Criteria | Behavior |
|------|-------------------|----------|
| **spec** | Has `smartasset.jsonc` in `docs/SmartAssetSpec/` | Validate existing structure, apply SA templates |
| **root** | Has `smartasset.jsonc` at repository root | Root-level SA repo, validate and harmonize |
| **hybrid** | Has `smartasset.jsonc` at both root and `docs/SmartAssetSpec/` | Full SA repo with subdirectory specs |
| **candidate** | Name contains "SmartAsset" or has `.smart-asset` marker (but no manifest) | Offer to scaffold SA structure |
| **none** | No SA manifest or indicators | Standard harmonization only |

**Smart Asset repos** (spec, root, hybrid) require additional files:

- `signers.jsonc` - Publisher key registry listing authorized signers for the Smart Asset
- `smartasset.jsonc` - Smart Asset manifest (root or in `docs/SmartAssetSpec/`)
- `schema/value-flows.jsonc` - Value/signal flow definitions
- `ai/behavior.md` - AI behavior specifications

**Candidate repos** (apps that should have SA specs) will be offered scaffolding based on the `--scaffold-sa` mode setting.

### Smart Asset Scaffolding

When a candidate repository is detected, harmonization can scaffold the complete Smart Asset structure:

```
docs/SmartAssetSpec/
  smartasset.jsonc       # Asset manifest
  schema/
    value-flows.jsonc    # Value/signal map
  ai/
    behavior.md          # AI behavior specification
  icons/                 # Asset icons (directory created)
```

Scaffolding uses template variable substitution:

| Variable | Source | Example |
|----------|--------|---------|
| `${ASSET_NAME}` | Derived from repo name | `SwellSmartAsset` |
| `${ASSET_TYPE}` | Default: `composite` | `primitive` or `composite` |
| `${DESCRIPTION}` | Default placeholder | User-customizable |

### Smart Asset Validation

For existing SA repos (spec, root, hybrid), harmonization runs validation:

```bash
# Validation is automatic during harmonization
# Uses validate-smart-asset.sh --quiet --json internally
```

Validation checks:
- Required files exist (smartasset.jsonc, value-flows.jsonc)
- JSON/JSONC syntax is valid
- Schema references resolve correctly
- Required fields are present in manifests

Validation results appear in output:

```
[3/12] samplesmartassets/SmartTreasury
       [SA] hybrid - Root SA with docs/SmartAssetSpec/
       [SA OK] Validation passed (3 checks, 0 warnings)
```

## Profile Directory Support

Some repository groups use a dedicated **profile directory** to store Task/Epoch/Story files centrally, rather than duplicating them in each repository. This is common for:

- Multi-repo projects (e.g., BountyForge with multiple sub-repos)
- Groups with shared task tracking (e.g., SATCHEL)

### How It Works

When harmonizing, the command can detect if a peer-level profile directory exists and place task files there instead of in each individual repository.

**Profile Directory Patterns** (checked in order):

| Pattern | Example |
|---------|---------|
| `{parent}/{ParentName}_gitlab-profile/` | `BountyForge/BountyForge_gitlab-profile/` |
| `{parent}/{ParentName}-gitlab-profile/` | `BountyForge/BountyForge-gitlab-profile/` |
| `{parent}/gitlab-profile/` | `SATCHEL/gitlab-profile/` |
| `{parent}/{ParentName}_github-profile/` | For GitHub-hosted projects |
| `{parent}/{ParentName}-github-profile/` | For GitHub-hosted projects |
| `{parent}/github-profile/` | For GitHub-hosted projects |
| `{parent}/codeberg/` | For Codeberg-hosted projects |

### Detection Script

Use the detection script to check if a repository should use a profile directory. See [Path Resolution](#path-resolution) for resolving `$PROFILE_DIR`:

```bash
# Human-readable output
"$PROFILE_DIR/AItools/scripts/detect-profile-directory.sh" /path/to/repo

# JSON output (for scripting)
"$PROFILE_DIR/AItools/scripts/detect-profile-directory.sh" --json /path/to/repo

# Quiet mode (just the path, empty if none)
"$PROFILE_DIR/AItools/scripts/detect-profile-directory.sh" -q /path/to/repo
```

### Example Scenarios

**BountyForge repositories:**
```
BountyForge/
  BountyForge_gitlab-profile/   <- Profile directory (task files here)
    docs/
      ToDos.md
      UserStories.md
  discord-mcp-bot/              <- No task files needed here
  ssl_data_spigot/              <- No task files needed here
  ToolChain/                    <- No task files needed here
```

**SATCHEL repositories:**
```
SATCHEL/
  gitlab-profile/               <- Profile directory (task files here)
    docs/
      ToDos.md
      UserStories.md
  satchel_ux/                   <- No task files needed here
  ZeroAuth_lib/                 <- No task files needed here
```

**Top-level repositories** (no parent profile):
```
SA/
  SA_build_agentics/            <- Task files in repo itself
    docs/
      ToDos.md
      UserStories.md
```

### Exit Codes (detect-profile-directory.sh)

| Code | Meaning |
|------|---------|
| 0 | Profile directory found (use that for task files) |
| 1 | No profile directory (use repository's own `docs/`) |
| 2 | Invalid arguments or path |

### Backward Compatibility

- Repositories without a peer profile directory continue to use their own `docs/` folder
- Profile directories themselves (e.g., `gitlab-profile`) store their own task files locally
- The detection is automatic and transparent to the harmonization process

## Output Format

### Progress Display

```
+--------------------  Policy Harmonization  --------------------+
| Source: top-level-gitlab-profile/                              |
| Mode: Interactive                                              |
+----------------------------------------------------------------+

[INFO] Scanning for repositories under: .
[INFO] Found 12 git repositories

[1/12] BountyForge/ToolChain
       [UPDATE] CLAUDE.md - Content differs from template
       [UPDATE] docs/ToDos.md - Add MR frontmatter
       [OK] docs/Backlog.md

[2/12] BountyForge/discord-mcp-bot
       [OK] CLAUDE.md
       [OK] docs/ToDos.md
```

### Action Indicators

| Indicator | Meaning |
|-----------|---------|
| `[CREATE]` | New file will be added from template |
| `[DERIVE]` | AGENTS.md will be derived from CLAUDE.md |
| `[CUSTOMIZED]` | File exists with custom content (preserved by default) |
| `[UPDATE]` | File will be modified (only with `--force`) |
| `[MERGE]` | Policy sections will be merged into existing file |
| `[OK]` | File already in sync |
| `[SKIP]` | File skipped (user choice or no template) |
| `[ERROR]` | Operation failed |

**Smart Asset Indicators:**

| Indicator | Meaning |
|-----------|---------|
| `[SA]` | Smart Asset type detected (spec, root, hybrid, candidate) |
| `[SA OK]` | SA validation passed |
| `[SA WARN]` | SA validation warnings (non-blocking) |
| `[SA CREATE]` | SA file scaffolded from template |
| `[SA SCAFFOLD]` | SA directory structure created |
| `[SA ERROR]` | SA validation or scaffolding failed |

### Final Summary

```
+------------------------  Summary  --------------------------+
| Repositories scanned:  12                                   |
| Files created:         2                                    |
| Files updated:         0                                    |
| Customized (preserved):4                                    |
| Already in sync:       5                                    |
| Skipped:               1                                    |
| Errors:                0                                    |
+-------------------------------------------------------------+
```

## When to Use

- **After updating workspace policies:** Propagate changes to all repos
- **Before major releases:** Ensure consistency across projects
- **Onboarding new repos:** Apply standard patterns quickly
- **Audit compliance:** Verify all repos follow guidelines
- **Smart Asset setup:** Scaffold SA structure in candidate repositories

## Examples

### Standard Harmonization

```bash
# Harmonize current directory
"$PROFILE_DIR/AItools/scripts/harmonize-policies.sh"

# Preview changes first
"$PROFILE_DIR/AItools/scripts/harmonize-policies.sh" --dry-run

# Harmonize all repos under a directory
"$PROFILE_DIR/AItools/scripts/harmonize-policies.sh" /path/to/workspace
```

### Smart Asset Harmonization

```bash
# Harmonize with SA scaffolding prompts (default in interactive mode)
"$PROFILE_DIR/AItools/scripts/harmonize-policies.sh"

# Force SA scaffolding without prompts
"$PROFILE_DIR/AItools/scripts/harmonize-policies.sh" --scaffold-sa=force

# Skip SA scaffolding entirely
"$PROFILE_DIR/AItools/scripts/harmonize-policies.sh" --scaffold-sa=skip

# Always prompt for SA scaffolding (even in YOLO mode)
"$PROFILE_DIR/AItools/scripts/harmonize-policies.sh" --scaffold-sa=ask
```

### Example Output with Smart Assets

```
[1/5] samplesmartassets/SmartTreasury
      [OK] CLAUDE.md
      [SA] hybrid - Root SA with docs/SmartAssetSpec/
      [SA OK] Validation passed (3 checks, 0 warnings)

[2/5] Websites_apps/SwellSmartAsset
      [OK] CLAUDE.md
      [SA] candidate - Name contains "SmartAsset"
      Scaffold Smart Asset structure? [y/N]: y
      [SA SCAFFOLD] Created docs/SmartAssetSpec/
      [SA CREATE] smartasset.jsonc
      [SA CREATE] schema/value-flows.jsonc
      [SA CREATE] ai/behavior.md

[3/5] BountyForge/ToolChain
      [OK] CLAUDE.md
      [SA] none - Not a Smart Asset repository
```

## Convention Embedding

Templates can embed content from `docs/common/` convention files using EMBED directives:

```markdown
<!-- EMBED:development-modes.md#Details -->
```

This injects the specified section from the convention file into the template during harmonization. Convention changes in `docs/common/` propagate automatically without template edits.

## Development Modes

Harmonization propagates a three-mode convention to target repos:

| Mode | Detection | Behavior |
|------|-----------|----------|
| **Safe** | `claude` / `claude-safe` | Restrictive hooks, use slash commands for git |
| **Orchestrated Agentic** | `claude-agentic` | No hooks, direct git access |
| **YOLO** | `claude-agentic` in worktree | Full autonomy in isolated worktree |

Mode support is detected per-repo (`.claude/` directory, worktree config) and logged during harmonization.

## Slash Command Injection

The template contains an `[OPTIONAL_COMMANDS]` marker that is replaced with repo-appropriate slash commands:

| Command | Injected When |
|---------|--------------|
| `/multi-review` | `.gitlab-ci.yml` or `.github/workflows` exists |
| `/story` | `docs/UserStories.md` exists |
| `/create-smart-asset` | `smartasset.jsonc` or `docs/SmartAssetSpec` exists |
| `/work-tasks` | `docs/ToDos.md` exists |

## .claude/ Directory Scaffold

Harmonization generates `.claude/` directory files for target repos:

- **`settings.json`** - Mode-appropriate settings stub
- **`worktree-config.json`** - Worktree placement convention with workspace-relative root

Existing files are never overwritten.

## Workspace-Wide Sync

For workspace-level orchestration with branch consistency enforcement, use `/multi-repo-sync`:

```bash
/multi-repo-sync --dry-run              # Preview all repos
/multi-repo-sync --strict=dev           # Enforce dev branch
/multi-repo-sync --scope subtree        # Current directory only
```

See [multi-repo-sync.md](multi-repo-sync.md) for full documentation.

## Related Commands

- `/multi-repo-sync` - Workspace-wide sync with branch consistency
- `/recursive-push` - Push commits across all repositories
- `/quick-commit` - Commit changes with standard message
- `/epoch-review` - Review epoch progress
- `/create-smart-asset` - Create new Smart Asset repository structure

## Related Documentation

For Smart Asset repositories, these reference documents define standards:

- [GLOSSARY.md](https://gitlab.com/smart-assets.io/smart-asset-primitives/-/blob/master/GLOSSARY.md) - Composition terminology (signal link, value link, boundary, etc.)
- [CompositionModel.md](https://gitlab.com/smart-assets.io/smart-asset-primitives/-/blob/master/docs/CompositionModel.md) - Canonical interface orientation
- [SAIntrinsics](https://gitlab.com/smart-assets.io/smart-asset-primitives/-/tree/master/SAIntrinsics) - Intrinsic element catalog

## Environment Variables

| Variable | Description |
|----------|-------------|
| `NO_COLOR` | Set to disable colored output |

## Conventions Propagated

Harmonization ensures these conventions are consistent across all target repositories:

| Convention | Source | Propagated Via |
|-----------|--------|----------------|
| Implementer Identification | [stigmergic-collaboration.md](../docs/common/stigmergic-collaboration.md#implementer-identification) | `CLAUDE.md.template` claiming section, `ToDos.md.template` field comments |
| `claimed_by` format | Same as above | `human-{email}`, `{tool}-session[-{id}]`, `{team}/{role}` |
| Epoch task structure | [epoch-task-structure.md](../docs/common/epoch-task-structure.md) | `ToDos.md.template` YAML structure |
| Git config identity | `git config --get user.email` | Human `claimed_by` values derived from git config |

## Source Templates

Templates are located in `top-level-gitlab-profile/docs/templates/`:

**Standard Templates:**
- `CLAUDE.md.template` - AI assistant guidance template (includes Implementer Identification, claiming conventions)
- `GEMINI.md.template` - Gemini CLI pointer to CLAUDE.md
- `ToDos.md.template` - Task tracking template (includes `claimed_by` format reference)
- `UserStories.md.template` - User stories template
- `Backlog.md.template` - Backlog template
- `CompletedTasks.md.template` - Completed tasks template

**Smart Asset Templates:**
- `signers.jsonc.template` - Publisher key registry template
- `smartasset.jsonc.template` - Smart Asset manifest template
- `value-flows.jsonc.template` - Value/signal flow schema template
- `behavior.md.template` - AI behavior specification template

### AGENTS.md Derivation

`AGENTS.md` is **derived from** the project's `CLAUDE.md`, not from a separate template:

1. `/harmonize` first ensures `CLAUDE.md` exists (creates from template + prompts if needed)
2. Then derives `AGENTS.md` by condensing key sections from `CLAUDE.md`
3. Extracted sections: Project Overview, Git Interaction, Attribution Policy, Code Style, Security, Development Modes, Slash Commands

This ensures `AGENTS.md` stays synchronized with project-specific `CLAUDE.md` content.

### GEMINI.md Creation

`GEMINI.md` is created from a template that **points to** `CLAUDE.md` as the single source of truth:

1. `/harmonize` first ensures `CLAUDE.md` exists
2. If `GEMINI.md` doesn't exist, creates it from the template
3. The template directs Gemini CLI to read `CLAUDE.md` for all project guidelines

This approach:
- Maintains vendor neutrality (no AI tool gets preferential documentation)
- Prevents documentation drift across multiple files
- Keeps `CLAUDE.md` as the canonical reference for all AI assistants

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | No repositories found |
| 2 | Source template not found |
| 3 | Invalid arguments |
| 4 | User aborted |
