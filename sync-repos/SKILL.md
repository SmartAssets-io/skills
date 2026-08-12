---
name: sync-repos
description: Synchronize conventions and policies across all repositories in the workspace with branch consistency enforcement
license: SSL
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
---

<!-- ste-policy: required -->
## Language Standard

For English technical prose, obey the [Simplified Technical English policy](#simplified-technical-english).
Apply the policy to text that this command creates or substantially rewrites.
Machine-significant and quoted text remains exempt.
Honor explicit non-English requests.
For committed prompt or policy files, run the repository STE Check and complete a human STE Review.

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/sync:repos [OPTIONS]

Options:
  --wizard              Interactive repo selection wizard
  --clear               Delete saved repo selection and exit
  --all                 Ignore saved selection (this run only)
  --strict[=BRANCH]     Enforce branch consistency (default: dev)
  --dry-run             Preview changes without modifying files
  --yes, -y             Auto-apply without prompting
  --scope workspace|subtree  Scan scope (default: subtree, i.e. cwd downward)
  --verbose             Detailed per-repo output
  --no-color            Disable colored output
```

---

# Multi-Repo Sync

Workspace-wide synchronization that orchestrates `/harmonize` across all repos with additional consistency checks. This command ensures that all repositories in the workspace share consistent conventions, policies, and branch states before applying harmonization.

Unlike `/harmonize` which operates on individual repositories or subtrees, `/multi-repo-sync` adds a workspace-level coordination layer that includes branch consistency enforcement, cross-repo validation, and **interactive repo selection**.

## Usage

```bash
/multi-repo-sync [OPTIONS]
```

## Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Preview all changes without modifying files or running harmonization |
| `--yes`, `-y` | Auto-apply all changes without prompting |
| `--scope [workspace\|subtree]` | Control scan scope: `subtree` (default) scans from the current directory downward; `workspace` scans the entire SA workspace |
| `--verbose` | Show detailed output including per-repo branch states and diff details |
| `--strict[=BRANCH]` | Enforce that all repos are on the specified branch (default: `dev`); blocks sync if any repo diverges |
| `--all` | Ignore saved repo selection, operate on all repos (this run only) |
| `--clear` | Delete saved repo selection config and exit |
| `--wizard` | Output JSON repo tree for interactive selection wizard |
| `--no-color` | Disable colored output |
| `--help`, `-h` | Show help message |

## Repo Selection Wizard

The wizard allows interactive selection of which repos to sync, rather than operating on all ~48 repos every time. Selections are persisted to `.multi-repo-selection.jsonc` in the workspace root (JSONC format supports comments and annotations).

### Wizard Flow

**Step 0: Check for existing config**

Before running the wizard, check if `.multi-repo-selection.jsonc` exists in the workspace root:

```bash
"scripts/multi-repo-sync.sh" --wizard
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
"scripts/repo-tree.sh" --json --branches --consistency "$WORKSPACE_ROOT"
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

Write `.multi-repo-selection.jsonc` to workspace root using the Write tool:

```jsonc
{
  // Multi-repo selection config
  // Controls which repos are included in /multi-repo-sync,
  // /quick-commit, /recursive-push, and /harmonize
  "version": 1,
  "mode": "include",
  "updated_at": "2026-02-14T10:00:00Z",
  // Repository groups to include
  "groups": ["BountyForge", "SATCHEL"],
  // Standalone repos (not in a group)
  "repos": ["SA_build_agentics", "gitlab-profile"],
  // Repos to exclude even if their group is included
  "excluded_repos": ["SATCHEL/lightning-rgb-node"]
}
```

Show summary (e.g., "Selected 42/51 repos") and proceed with sync.

### Selection Config Format

The `.multi-repo-selection.jsonc` file uses "include" mode resolution:

1. Start with empty set
2. Add all repos from listed `groups` (discovered at runtime)
3. Add individually listed `repos`
4. Remove anything in `excluded_repos`

This handles the common case of selecting a large group and excluding 1-2 repos.

### Clearing Selection

Three ways to clear or bypass the saved selection:

| Method | Behavior |
|--------|----------|
| `/multi-repo-sync --clear` | Deletes `.multi-repo-selection.jsonc` and exits |
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

1. **Checks for saved repo selection** - Loads `.multi-repo-selection.jsonc` if present, or runs wizard if `--wizard` specified.

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
# Sync only repos under the current directory (default)
/multi-repo-sync --scope subtree

# Sync entire workspace
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
- `/epic-review` - Review epic progress across the workspace

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success - all repos synchronized |
| 1 | No repositories found in scope |
| 2 | Branch consistency check failed (with `--strict`) |
| 3 | Invalid arguments |
| 4 | User aborted |
| 5 | One or more repos failed harmonization |

---

## Simplified Technical English Policy

The policy in this section governs applicable English technical prose from this skill.
The ASD standard remains authoritative.
Machine-significant text and quoted or external text remain exempt.
Honor explicit requests for another language.
## Simplified Technical English
<!-- ste-policy: full -->

Smart Assets uses ASD-STE100 Simplified Technical English, Issue 9, dated January 2025, for applicable English technical prose.

This policy is a Smart Assets applicability profile. The ASD standard remains the authoritative source for its rules and controlled dictionary.

Get the current standard from the [official ASD-STE100 website](https://www.asd-ste100.org/) or its [official downloads page](https://www.asd-ste100.org/STE_downloads.html).

ASD owns the standard and the ASD-STE100 trademark. Do not copy its controlled dictionary, examples, or substantial rule text into this repository.

### Applicability

Use this policy for English technical prose that an assistant creates or substantially rewrites, including:

- Assistant responses
- Technical documentation
- Plans and specifications
- Procedures and instructions
- Warnings and cautions
- Review findings
- User-facing explanations and status messages.

Preserve unaffected legacy prose. Apply this policy to the text that the assistant adds or substantially changes.

If the user explicitly requests another language, use that language. If you report STE status, mark STE as not applicable to that output.

This policy does not apply to:

- Code, identifiers, commands, flags, paths, URLs, and schema keys
- Data formats, exact test fixtures, and machine-generated text
- Verbatim quotations and user-supplied text
- Third-party names, standard titles, and legal or license text.

Do not change technical meaning, safety controls, legal meaning, or exact user requirements only to satisfy a language rule.

### Words and terminology

Use the official Issue 9 dictionary as the source for general approved words. Do not copy the dictionary into project files.

Use a word only with its approved part of speech, meaning, and form. Use American English spelling unless another directive controls the text.

Use approved technical nouns and technical verbs for the applicable subject field. Record recurring Smart Assets terms in the project glossary.

Use one technical noun for one concept. Do not replace a canonical term with a synonym only for stylistic variation.

Keep a new technical noun short and easy to understand. Use no more than three words unless an approved term requires more words.

Do not use regional words, slang, or unexplained jargon. Define an unavoidable abbreviation at its first use.

Use technical nouns as nouns. Use technical verbs as verbs and only in their approved software-development meaning.

### Grammar and sentences

Use active voice. In descriptive text, use passive voice only when the agent is unknown or technically unimportant.

Use simple verb forms and tenses. Avoid progressive and other complex constructions unless an exempt technical term requires them.

Use a direct verb to describe an action. Do not hide an action in an abstract noun phrase.

Write complete sentences. Do not omit articles, subjects, verbs, or necessary nouns to make a sentence shorter.

Do not use contractions. Do not use semicolons.

Keep each sentence focused on one subject. Use a vertical list when one sentence would contain complex items or actions.

Make each pronoun refer to one clear noun. Repeat the technical noun when a pronoun can have more than one meaning.

### Procedures

Use a maximum of 20 words in each procedural sentence. Use one instruction in each sentence unless actions occur at the same time.

Start each instruction with an imperative verb. Put a necessary condition before the instruction and separate it with a comma.

Use numbered steps when sequence is important. Keep information-only notes separate from instructions, requirements, limits, and safety information.

### Descriptions

Use a maximum of 25 words in each descriptive sentence. Give information gradually and keep one topic in each paragraph.

Start each paragraph with its topic. Use no more than six sentences in one paragraph.

Use consistent key words to connect related sentences. Start a new paragraph when the topic changes.

### Safety information

Use the project-approved risk word or symbol. Start with a clear command or condition, and then state the risk or possible result.

Do not hide safety information in a note. Keep safety controls and their consequences explicit.

### Verification

An **STE Check** is deterministic. It can check policy coverage, sentence limits, paragraph limits, contractions, semicolons, and selected exemptions.

An **STE Review** is semantic. A human reviewer must check vocabulary, meaning, active voice, referents, terminology, and technical accuracy.

For committed prompt and policy files, run the repository STE Check. Review all applicable new or substantially rewritten prose before completion.

A checker cannot establish full ASD-STE100 conformance. Do not claim that text is ASD-STE100 compliant only because an automated check passes.
