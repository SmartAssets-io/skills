---
name: asset-create
description: Create, initialize, and synchronize Smart Asset schemas and repository structure using SAIntrinsics master schema
license: SSL
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
/asset:create [name] [subcommand]

Arguments:
  [name]                Create a specific Smart Asset schema
  sync                  Synchronize with master schema definitions

Default (no args): Initialize Smart Asset definitions in repository.
Prerequisite: Run /harmonize first.
```

---

# /create-smart-asset

Create, initialize, and synchronize Smart Asset schemas and repository structure.

## Overview

This command manages **primitive Smart Assets** - foundational Smart Assets that use SAIntrinsics directly and can be composed with other Smart Assets. Run `/harmonize` first to ensure basic repository structure is in place.

## Prerequisites

- Run `/harmonize` first to establish basic repository structure
- For peer repositories (like `BountyForge/BountyForge_gitlab-profile`), ensure the peer repo exists

## Configuration File Conventions

This command creates `.jsonc` files (JSON with Comments) for schema definitions. When working with any JSON configuration files:

1. **Check for existing files first**: Before creating any `.json` file, check if `.jsonc` or `.json5` variants exist
2. **Prefer existing format**: If `config.jsonc` or `config.json5` exists, use that format
3. **Default to JSONC**: This command uses `.jsonc` for all schema files (e.g., `smartasset.jsonc`, `schema/value-flows.jsonc`)

## Usage

```
/create-smart-asset              # Initialize Smart Asset definitions (or detect existing)
/create-smart-asset [name]       # Create a specific Smart Asset schema
/create-smart-asset sync         # Synchronize with master schema definitions
```

### Subcommands

| Subcommand | Description |
|------------|-------------|
| *(none)* | Initialize Smart Asset definitions in repository |
| `[name]` | Create a new Smart Asset with the given name |
| `sync` | Synchronize local schema with master definitions |

## Initialization Detection

When `/create-smart-asset` is run (without `sync`), the command first checks if Smart Asset definitions are already initialized:

### Initialization Markers

The repository is considered **initialized** if ANY of these exist:
- `docs/SmartAssetSpec/` directory exists
- `docs/SmartAssetSpec/*.md` schema files exist (excluding README)
- `.smart-asset-initialized` marker file exists

### Behavior on Detection

```
/create-smart-asset
    │
    ├── Check for initialization markers
    │
    ├── IF NOT initialized:
    │   └── Proceed with initialization workflow
    │
    └── IF ALREADY initialized:
        └── Use AskUserQuestion:
            "Smart Asset definitions already initialized in this repository."

            Options:
            1. Run sync - Synchronize with latest master schema definitions
            2. Create new - Create a new Smart Asset (will prompt for name)
            3. Cancel - Exit without changes
```

## Workflow: Initialization

When initializing a new repository:

```
/create-smart-asset (first time)
    │
    ├── 1. Verify /harmonize has been run
    ├── 2. Create docs/SmartAssetSpec/ structure
    ├── 3. Copy master schema (smart-asset-elements.yaml)
    ├── 4. Create .smart-asset-initialized marker
    ├── 5. Add .smart-asset-initialized to .gitignore
    ├── 6. Create placeholder directories (icons/, wireframes/)
    └── 7. Report initialization complete
```

### Generated Structure

```
<repo>/
├── docs/
│   └── SmartAssetSpec/
│       ├── README.md              # Overview of Smart Asset specs
│       ├── icons/                 # Asset icon placeholders
│       └── wireframes/            # UI wireframe placeholders
├── signers.jsonc                  # Publisher key registry (required)
├── .gitignore                     # Updated to exclude marker file
├── .smart-asset-initialized       # Marker file (gitignored)
└── ...
```

### Marker File Format

`.smart-asset-initialized`:
```yaml
initialized_at: 2025-01-15T10:00:00Z
schema_version: "1.0"
source_schema: "assets/smart-asset-elements.yaml"
last_sync: 2025-01-15T10:00:00Z
```

**Note:** This file is automatically added to `.gitignore` because `source_schema` contains
workspace-relative paths that won't work for other developers. Each developer must run
`/create-smart-asset` to initialize their local workspace.

## Workflow: Sync

The `sync` subcommand synchronizes local Smart Asset definitions with the master schema.

```
/create-smart-asset sync
    │
    ├── 1. Verify initialization (must be initialized first)
    ├── 2. Compare local schema version with master
    ├── 3. Identify changes:
    │   ├── New elements added to master
    │   ├── Elements removed from master (deprecated)
    │   ├── Element definition changes (interfaces, params)
    │   └── Template changes
    ├── 4. Preview changes to user
    ├── 5. Apply updates (with user confirmation)
    ├── 6. Update existing Smart Asset specs (optional)
    └── 7. Update .smart-asset-initialized marker
```

### Sync Operations

| Operation | Description |
|-----------|-------------|
| **Schema Update** | Update local `smart-asset-elements.yaml` with master definitions |
| **Element Sync** | Add new elements, mark deprecated ones |
| **Interface Update** | Update element interfaces and config params |
| **Template Sync** | Update template complexity definitions |
| **Spec Migration** | Optionally update existing Smart Asset specs to new conventions |

### Sync Preview

Before applying changes, show a preview:

```
Smart Asset Schema Sync Preview
================================

Master schema version: 1.1
Local schema version:  1.0

Changes detected:

+ NEW ELEMENTS:
  - StakingVault (category: treasury)
  - RateLimiter (category: governance)

~ UPDATED ELEMENTS:
  - TradTreasury: Added config param 'emergency_multisig'
  - oracle: Interface change - added 'confidence' output

- DEPRECATED ELEMENTS:
  - legacyBuffer (use PaymentBuffer instead)

~ TEMPLATE CHANGES:
  - medium: Added RateLimiter to suggested_elements

Existing Smart Asset specs that may need updates:
  - docs/SmartAssetSpec/MyTreasury.md (uses: TradTreasury)

Apply these changes? [Y/n]
```

### Spec Migration

When existing specs use updated elements, offer migration:

```
The following specs use elements with updated definitions:

1. MyTreasury.md
   - TradTreasury: New config param 'emergency_multisig' available

2. PriceOracle.md
   - oracle: New 'confidence' output interface available

Options:
1. Update specs automatically - Add new params/interfaces with defaults
2. Show migration guide - Manual update instructions
3. Skip spec updates - Only update master schema
```

## Workflow: Create New Smart Asset

When creating a new Smart Asset (after initialization):

```
/create-smart-asset [name]
    │
    ├── 1. Detect context (peer repo vs standalone)
    ├── 2. Gather Smart Asset metadata
    ├── 3. Select template complexity
    ├── 4. Choose SAIntrinsics from master schema
    ├── 5. Generate schema files
    └── 6. Create supporting structure
```

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `name` | Optional | Smart Asset name (prompted if not provided) |

## Interactive Prompts

The command will prompt for:

### 1. Smart Asset Identity

| Field | Description | Example |
|-------|-------------|---------|
| **Name** | PascalCase identifier | `SmartTreasury`, `PAIR`, `TaxManager` |
| **Category** | Functional category | `Treasury Management`, `Oracle & Yield`, `Tax Optimization` |
| **Description** | One-line summary | `Autonomous portfolio manager with deep network allocation` |

### 2. Template Complexity

| Level | Description | Suggested For |
|-------|-------------|---------------|
| **Simple** | Single treasury, basic flow | Learning, simple use cases |
| **Medium** | Oracle integration, gates | Standard Smart Assets |
| **Complex** | Deep network, full automation | Production Smart Assets |

### 3. SAElement Selection

Elements are presented from the master schema (`assets/smart-asset-elements.yaml`):

**Treasury Elements:**
- `TradTreasury` - Multi-sig value storage vault
- `PaymentBuffer` - Buffered payments for external services

**Oracle Elements:**
- `oracle` - External data feed aggregation
- `deepNetwork` - AI/ML allocation engine

**Automation Elements:**
- `auto-fill` - Programmatic outbound distribution
- `auto-top` - Automatic Battery replenishment
- `income_stream` - Revenue aggregation

**Governance Elements:**
- `MultiSigGate` - Boundary gate with n-of-m signatures
- `MultiSigApproval` - Multi-signature approval workflow

**Service Elements:**
- `dataService` - Monetized data feeds

Custom elements can also be specified with relative paths.

## Generated Files

### Schema File

Located at `docs/SmartAssetSpec/<Name>.md` (or appropriate location based on context):

```markdown
---
template_type: MockSmartAsset
name: <Name>
status: draft
category: <Category>
classification: Primitive
icon:
  - ./icons/<Name>.png
elements_used:
  - <selected elements>
composes_with: []  # Filled when composed
related_specs:
  - ../SA-SPEC-007-Composition.md
---

# <Name>

## Overview

<Description>

## Value Flows Schema

```jsonc
{
  // Generated schema based on template and element selection
}
```

## Architecture

<ASCII diagram placeholder>

## Internal Elements

<Element documentation>

## Configuration Parameters

<Config params from selected elements>

## Related Specifications

<Links to related specs>
```

### Supporting Files

| File | Purpose |
|------|---------|
| `docs/SmartAssetSpec/icons/<Name>.png` | Placeholder for asset icon |
| `docs/SmartAssetSpec/wireframes/<Name>_UI.png` | Placeholder for UI wireframe |

## Context Detection

The command detects repository context to determine file placement:

### Standalone Repository

```
<repo>/
├── CLAUDE.md (from /harmonize)
├── docs/
│   ├── SmartAssetSpec/
│   │   ├── <Name>.md           # Generated schema
│   │   ├── icons/
│   │   │   └── <Name>.png      # Placeholder
│   │   └── wireframes/
│   │       └── <Name>_UI.png   # Placeholder
│   └── ToDos.md
└── ...
```

### Peer Repository (e.g., BountyForge structure)

```
<parent>/
├── <Asset>_gitlab-profile/     # Profile repo (current)
│   ├── CLAUDE.md
│   └── docs/
│       └── SmartAssetSpec/
│           └── <Name>.md       # Generated here
├── <Asset>_core/               # Peer: core implementation
├── <Asset>_contracts/          # Peer: smart contracts
└── ...
```

## Template Details

### Simple Template

Minimal schema with single treasury:

```jsonc
{
  "internal_elements": {
    "<name>_treasury": {
      "label": "<Name> Treasury",
      "element_ref": "git+ssh://gitlab.com/smart-assets.io/smart-asset-primitives/SAIntrinsics.git/TradTreasury.md",
      "description": "Primary value storage"
    }
  },
  "composition_interface": {
    "signal_in": { "position": "top", "label": "Control Signal" },
    "signal_out": { "position": "bottom", "label": "Status Signal" }
  },
  "sources": {
    "source_inflow": {
      "label": "Value Inflow",
      "position": "boundary_left"
    }
  },
  "sinks": {
    "sink_outflow": {
      "label": "Value Outflow",
      "position": "boundary_right"
    }
  },
  "boundary": {
    "label": "<Name> Boundary",
    "contains": ["<name>_treasury"],
    "sources": ["source_inflow"],
    "sinks": ["sink_outflow"]
  }
}
```

### Medium Template

Adds oracle integration and boundary gates:

```jsonc
{
  "external_services": {
    // External oracle feeds
  },
  "internal_elements": {
    // Treasury + oracle aggregator
  },
  "boundary_gates": {
    "multisig_gate": {
      "element_ref": "git+ssh://gitlab.com/smart-assets.io/smart-asset-primitives/SAIntrinsics.git/MultiSigGate.md"
    }
  },
  "composition_interface": {
    "signal_in": { "position": "top", "label": "Control Signal" },
    "signal_out": { "position": "bottom", "label": "Status Signal" },
    "value_in": { "position": "left", "label": "Value Input" },
    "value_out": { "position": "right", "label": "Value Output" }
  },
  "sources": { /* ... */ },
  "sinks": { /* ... */ },
  "flows": {
    // Named flow connections
  },
  "boundary": { /* ... */ }
}
```

### Complex Template

Full-featured with deep network and automation (based on SmartTreasury pattern).

## Examples

### Initialize Smart Asset Definitions (First Time)

```
/create-smart-asset

> Checking initialization status...
> Smart Asset definitions not yet initialized.
>
> Creating structure:
>   Created docs/SmartAssetSpec/
>   Created docs/SmartAssetSpec/README.md
>   Created docs/SmartAssetSpec/icons/
>   Created docs/SmartAssetSpec/wireframes/
>   Created .smart-asset-initialized
>   Updated .gitignore (added .smart-asset-initialized)
>
> Initialization complete.
> Would you like to create your first Smart Asset now? [Y/n]
```

### Run on Already Initialized Repository

```
/create-smart-asset

> Smart Asset definitions already initialized.
> [AskUserQuestion displayed]
>
> Options:
> 1. Run sync - Synchronize with latest master schema definitions
> 2. Create new - Create a new Smart Asset (will prompt for name)
> 3. Cancel - Exit without changes
```

### Synchronize Schema Definitions

```
/create-smart-asset sync

> Loading local schema (version 1.0, last sync: 2025-01-10)
> Loading master schema (version 1.1)
>
> Smart Asset Schema Sync Preview
> ================================
>
> + NEW ELEMENTS:
>   - StakingVault (category: treasury)
>
> ~ UPDATED ELEMENTS:
>   - TradTreasury: Added config param 'emergency_multisig'
>
> Apply these changes? [Y/n]
> y
>
> Schema synchronized.
> Updated .smart-asset-initialized (version: 1.1, last_sync: 2025-01-15)
>
> 1 existing spec may need review:
>   - docs/SmartAssetSpec/MyTreasury.md (uses: TradTreasury)
```

### Create a Simple Treasury Asset

```
/create-smart-asset MyTreasury

> Category: Treasury Management
> Template: Simple
> Elements: TradTreasury
```

### Create an Oracle-Based Asset

```
/create-smart-asset PriceOracle

> Category: Oracle & Yield
> Template: Medium
> Elements: oracle, PaymentBuffer, MultiSigGate
```

### Create a Full Portfolio Manager

```
/create-smart-asset PortfolioManager

> Category: Treasury Management
> Template: Complex
> Elements: TradTreasury (x3), oracle, deepNetwork, MultiSigGate, PaymentBuffer, auto-fill
```

## Execution Steps

When invoked, the AI assistant should:

### Step 0: Parse Subcommand

```
/create-smart-asset           → Check initialization, then init or prompt
/create-smart-asset sync      → Run sync workflow
/create-smart-asset [name]    → Check initialization, then create Smart Asset
```

### Step 1: Check Prerequisites

- Verify `/harmonize` has been run (look for CLAUDE.md, docs/ structure)
- Detect repository context (standalone vs peer)

### Step 2: Check Initialization Status

Look for initialization markers:

```bash
# Check for any of these markers
[ -d "docs/SmartAssetSpec" ] ||
[ -f ".smart-asset-initialized" ] ||
ls docs/SmartAssetSpec/*.md 2>/dev/null | grep -v README.md
```

### Step 3: Route Based on Status and Subcommand

**If subcommand is `sync`:**
- Verify initialized (error if not)
- Proceed to Sync Workflow (Step 8)

**If NOT initialized:**
- Proceed to Initialization Workflow (Step 4)
- Then optionally create first Smart Asset

**If ALREADY initialized (and no `sync` subcommand):**
- Use AskUserQuestion:
  ```
  Question: "Smart Asset definitions already initialized. What would you like to do?"

  Options:
  1. Run sync - Synchronize with latest master schema definitions
  2. Create new - Create a new Smart Asset (will prompt for name)
  3. Cancel - Exit without changes
  ```
- Route based on selection

### Step 4: Initialization Workflow

1. Create directory structure:
   ```
   docs/SmartAssetSpec/
   docs/SmartAssetSpec/icons/
   docs/SmartAssetSpec/wireframes/
   ```

2. Create `docs/SmartAssetSpec/README.md`:
   ```markdown
   # Smart Asset Specifications

   This directory contains Smart Asset schema definitions for this repository.

   ## Structure

   - `*.md` - Individual Smart Asset specifications
   - `icons/` - Asset icons and visual assets
   - `wireframes/` - UI wireframes and mockups

   ## Creating New Smart Assets

   Use the `/create-smart-asset [name]` command to create new specifications.

   ## Synchronizing

   Use `/create-smart-asset sync` to update definitions with the latest
   master schema from the workspace.
   ```

3. Create `.smart-asset-initialized` marker:
   ```yaml
   initialized_at: <current_timestamp>
   schema_version: "1.0"
   source_schema: "assets/smart-asset-elements.yaml"
   last_sync: <current_timestamp>
   ```

4. Add `.smart-asset-initialized` to `.gitignore`:
   - If `.gitignore` exists, append entry if not already present
   - If `.gitignore` doesn't exist, create it with the entry
   - Entry: `# Smart Asset local state (workspace-specific paths)\n.smart-asset-initialized`

5. Report initialization complete

6. Ask if user wants to create first Smart Asset now

### Step 5: Gather Metadata (for Create)

- Prompt for name if not provided
- Ask for category and description
- Use AskUserQuestion for multi-choice selections

### Step 6: Select Template and Elements

- Present simple/medium/complex options
- Read `assets/smart-asset-elements.yaml`
- Present categorized element list
- Allow multiple selections
- Support custom element paths

### Step 7: Generate Schema and Files

- Use appropriate template as base
- Populate with selected elements
- Generate YAML frontmatter
- Create JSONC Value Flows Schema
- Create icon/wireframe placeholders
- Update docs/ToDos.md with implementation tasks

### Step 8: Sync Workflow

1. **Verify Initialization**
   - Check `.smart-asset-initialized` exists
   - If not: Error "Repository not initialized. Run `/create-smart-asset` first."

2. **Load Schema Versions**
   - Read local marker file for `schema_version` and `last_sync`
   - Read master schema from `assets/smart-asset-elements.yaml`

3. **Compare Schemas**
   - Identify new elements in master
   - Identify removed/deprecated elements
   - Identify changed element definitions
   - Identify template changes

4. **Preview Changes**
   - Display formatted diff (see Sync Preview section above)
   - If no changes: "Schema is up to date. No changes needed."

5. **Apply Changes (with confirmation)**
   - Copy updated element definitions
   - Update schema_version in marker file
   - Update last_sync timestamp

6. **Scan Existing Specs**
   - Find all `docs/SmartAssetSpec/*.md` files
   - Check which use updated elements
   - Offer spec migration if applicable

7. **Report Results**
   - Summary of changes applied
   - List of specs that may need manual review

### Step 9: Report Results

- Show created/modified files
- Suggest next steps based on workflow:
  - After init: "Run `/create-smart-asset [name]` to create your first Smart Asset"
  - After create: "Review schema, add icon, refine configuration"
  - After sync: "Review updated specs, test integrations"

## Master Schema Reference

The element definitions are maintained in:
```
assets/smart-asset-elements.yaml
```

This file contains:
- Element categories and descriptions
- Interface definitions (inputs/outputs)
- Configuration parameters
- Template complexity definitions
- Icon library reference
- Boundary position conventions

## Related Commands

| Command | Relationship |
|---------|--------------|
| `/harmonize` | Run first to establish repo structure |
| `/create-smart-asset sync` | Synchronize with latest master schema |
| `/nextTask` | Find tasks after schema creation |
| `/implement` | Implement schema components |

## Related Documentation

### SmartAssetPrimitives Reference

| Document | Description |
|----------|-------------|
| [GLOSSARY.md](https://gitlab.com/smart-assets.io/smart-asset-primitives/-/blob/master/GLOSSARY.md) | Composition terminology (signal link, value link, boundary, etc.) |
| [CompositionModel.md](https://gitlab.com/smart-assets.io/smart-asset-primitives/-/blob/master/docs/CompositionModel.md) | Canonical interface orientation (top/bottom signals, left/right value) |
| [smart-asset-definition-import.md](https://gitlab.com/smart-assets.io/smart-asset-primitives/-/blob/master/docs/smart-asset-definition-import.md) | Transfer-in import flow and storage locations |
| [SAIntrinsics](https://gitlab.com/smart-assets.io/smart-asset-primitives/-/tree/master/SAIntrinsics) | Intrinsic element catalog |

### Local Specifications

| Document | Description |
|----------|-------------|
| [MockSmartAssetTemplates](https://gitlab.com/smart-assets.io/satchel/satchel_ux/-/tree/master/docs/SmartAssetSpec/MockSmartAssetTemplates) | Example Smart Assets |
| [SA-SPEC-007-Composition](https://gitlab.com/smart-assets.io/satchel/satchel_ux/-/blob/master/docs/SmartAssetSpec/SA-SPEC-007-Composition.md) | Composition architecture |

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
