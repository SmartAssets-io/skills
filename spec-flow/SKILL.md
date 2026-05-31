---
name: spec-flow
description: Create, link, and synchronize user flows in docs/User-Flows.md with bi-directional links to stories and epics; emits framework-agnostic test specs for integration-test authoring
license: SSL
---

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/spec:flow <subcommand> [arguments]

Subcommands:
  create [flags]                  Create a new user flow in docs/User-Flows.md
                                  Non-TTY callers (AI agents / CI) MUST use flag or JSON mode:
                                    --title TEXT --journey TEXT
                                    --step "Name|description" (repeatable)
                                    [--persona TEXT]... [--interaction TEXT]...
                                    [--metric TEXT]... [--related-story US-NNN]...
                                  or:
                                    --from-json <path>
                                  With no flags on a TTY, launches the interactive wizard.
                                  No integration-test inputs at creation time; that
                                  linkage is added later via `link` or `test-spec`.
  link FLOW-XXX <target>          Bi-directional link. Target is one of:
                                    US-NNN     -> story link
                                    EPIC-NNN  -> epic link
                                    ITEST-NNN  -> integration test (by stable id)
                                    <path>     -> integration test (by file path)
  sync                            Report orphan flows, stories without flows, epics
                                  without flows, AND flows whose implementation
                                  epic is complete but lack integration tests.
  review [FLOW-XXX]               Review a flow or list all
  list                            Enumerate all flows (tab-separated id/status/epic/title)
  test-spec FLOW-XXX [--out PATH] [--stdout]
                                  Emit Given/When/Then test spec.
                                  Default: writes docs/test-specs/<FLOW-ID>.md and
                                  auto-links it back into the flow's Integration Tests.
                                  --stdout prints only (no file, no link).
  integrity [--task TID|--epic EID|--flow FID|--all] [--strict] [--json]
                                  Chain integrity report. Grades each target as
                                  full / partial / missing and lists any gaps.

Manages user flows with bi-directional linking to stories, epics, and integration tests.
```

---

# User Flow Management

Create, link, and synchronize user flows. This command provides command-line management of user flows in `docs/User-Flows.md` with bi-directional linking to stories in `docs/UserStories.md` and epics in `docs/ToDos.md`.

User flows formalize interaction patterns that:

1. Describe the **journey** a user takes through the product end-to-end.
2. Decompose into **steps** with deterministic preconditions and outcomes.
3. Surface **key interactions** that double as integration-test assertions.
4. State **success metrics** that double as integration-test budgets.

The `test-spec` subcommand emits this content as a Given/When/Then artifact so reviewers can author or generate integration tests during final implementation review.

## Lifecycle

Flows participate in this sequence:

1. `/user-flow create` -> `FLOW-NNN` (Integration Tests field begins empty).
2. `/story create` and `/user-flow link FLOW-NNN US-NNN` -> stories linked.
3. Epic + tasks authored in `docs/ToDos.md`; `/user-flow link FLOW-NNN EPIC-NNN`.
4. `/implement` works through tasks; unit tests are produced alongside code.
5. Epic reaches `complete` status (every task done).
6. `/user-flow test-spec FLOW-NNN` writes `docs/test-specs/FLOW-NNN.md`
   and auto-links that artifact back into the flow's `Integration Tests`.
7. Test author writes the actual integration tests against the spec,
   then `/user-flow link FLOW-NNN <path-or-ITEST-id>` for each additional
   artifact.

`sync` only reports a flow as "missing integration tests" once step 5
has happened. Pre-`complete` flows are not flagged as gaps.

## Usage

Run the user-flow-manager script with a subcommand:

```bash
"scripts/user-flow-manager.sh" <subcommand> [arguments]
```

## Subcommands

### create

Create a new user flow. Three input modes:

> **Rule for AI agents, CI, and any non-TTY caller:** always use flag mode (1) or JSON mode (2). The interactive wizard requires a TTY.

#### Mode 1 — Flag mode (preferred for AI agents / CI)

Required: `--title`, `--journey`, and at least one `--step`.

```bash
"scripts/user-flow-manager.sh" create \
    --title    "First-Time User Onboarding" \
    --journey  "Signup -> SSL consent -> Tool integration -> Dashboard" \
    --persona  "developer using AI assistants" \
    --step     "Registration|Email/GitHub OAuth, SATCHEL connection, SSL consent" \
    --step     "Welcome Tutorial|Interactive dashboard overview (skip option)" \
    --step     "Integration Setup|Choose CLI or IDE, configure spigot, test connection" \
    --interaction "Email verification succeeds" \
    --interaction "SATCHEL creation visible" \
    --metric   "Onboarding completes in <5min" \
    --metric   "Connection test success rate >95%" \
    --related-story US-001
```

The script auto-assigns the next `FLOW-XXX` ID and writes the flow to `docs/User-Flows.md`. If the file does not exist, it is created from a template.

#### Mode 2 — JSON mode (`--from-json`)

```bash
"scripts/user-flow-manager.sh" create --from-json path/to/flow.json
```

JSON schema:

```json
{
  "title": "First-Time User Onboarding",
  "journey": "Signup -> SSL consent -> Tool integration -> Dashboard",
  "personas": ["developer using AI assistants"],
  "steps": [
    {"name": "Registration", "description": "Email/GitHub OAuth, SATCHEL connection, SSL consent"},
    {"name": "Welcome Tutorial", "description": "Interactive dashboard overview (skip option)"}
  ],
  "key_interactions": [
    "Email verification succeeds",
    "SATCHEL creation visible"
  ],
  "success_metrics": [
    "Onboarding completes in <5min",
    "Connection test success rate >95%"
  ],
  "related_stories": ["US-001"],
  "related_flows": []
}
```

Per-field flags passed alongside `--from-json` override the JSON values for that field.

#### Mode 3 — Interactive wizard (humans only)

Run on a TTY with no flags:

```bash
"scripts/user-flow-manager.sh" create
```

The wizard prompts for title, journey, personas, steps, key interactions, success metrics, and related stories.

In Claude Code specifically, a human can drive the wizard by prefixing with `!`:

```
! "scripts/user-flow-manager.sh" create
```

### link

Link a flow bidirectionally. The target type is auto-detected from its prefix:

```bash
"scripts/user-flow-manager.sh" link FLOW-001 US-010
"scripts/user-flow-manager.sh" link FLOW-001 EPIC-014
"scripts/user-flow-manager.sh" link FLOW-001 ITEST-001
"scripts/user-flow-manager.sh" link FLOW-001 tests/e2e/onboarding.spec.ts
```

For a story (`US-NNN`):
- **User-Flows.md**: the story id is appended to the flow's `Related Stories` field
- **UserStories.md**: `User Flow: FLOW-NNN` is written into the story block

For an epic (`EPIC-NNN`):
- **User-Flows.md**: the flow's `Implemented in` field is set to the epic id
- **ToDos.md**: `user_flow: FLOW-NNN` is written into the epic's YAML block

For an integration test (`ITEST-NNN` or any non-ID file path):
- **User-Flows.md**: the artifact is appended to the flow's `Integration Tests` field.

Integration-test linkage is a late-stage step — perform it after the
implementation epic is `complete` and tests have been authored. See the
Lifecycle section above.

### sync

Scan and report:
- orphan flows (no story or epic),
- stories with no linked flow,
- epics with no linked flow,
- flows whose `Implemented in` epic is `complete` but whose `Integration
  Tests` is empty/None.

```bash
"scripts/user-flow-manager.sh" sync
```

### review

Review a single flow or list all:

```bash
"scripts/user-flow-manager.sh" review            # summary of all
"scripts/user-flow-manager.sh" review FLOW-001   # detail view
```

### list

Tab-separated enumeration: `id\tstatus\timplemented_in\ttitle`. Suitable for piping into other tools.

```bash
"scripts/user-flow-manager.sh" list
```

### integrity

Walk the chain `FLOW → US → EPIC → TASK → unit tests → integration tests`
and grade each target.

```bash
"scripts/user-flow-manager.sh" integrity --all
"scripts/user-flow-manager.sh" integrity --task TODO-016-002
"scripts/user-flow-manager.sh" integrity --epic EPIC-016
"scripts/user-flow-manager.sh" integrity --flow FLOW-001
"scripts/user-flow-manager.sh" integrity --all --json
"scripts/user-flow-manager.sh" integrity --epic EPIC-016 --strict
```

**Grades**

- `full` — chain intact AND every required test / back-reference present.
- `partial` — target exists, some chain links missing. The report lists the gap codes.
- `missing` — target not found or chain unreadable.

**Gap codes**

- `no_unit_tests` — task carries no `unit_tests:` entry.
- `no_integration_tests` — flow's `Integration Tests` is empty/None (only counted once the implementing epic is `complete`).
- `no_flow_link` — epic is missing the `user_flow:` field.
- `flow_not_found` — referenced flow not in `docs/User-Flows.md`.
- `no_related_stories` — flow's `Related Stories` is empty.
- `story_not_found` — referenced story missing from `docs/UserStories.md`.
- `story_missing_backref` — story does not carry `User Flow: FLOW-XXX`.
- `no_epic_link` — flow has no `Implemented in` epic.
- `epic_not_found` — referenced epic not in `docs/ToDos.md`.

**Strict mode**

By default `integrity` exits 0 and prints a report. `--strict` exits 1 when
any gaps are found — useful from CI or pre-commit hooks. Use `--json` to
consume the raw walker output programmatically.

`integrity` is the read-only counterpart to `/task-complete`, which uses the
same walker but also writes `completion_gaps:` into YAML when marking tasks
or epics complete.

### test-spec

Emit a framework-agnostic test specification for a flow. Each step becomes a Given/When/Then scenario; key interactions become assertions; success metrics become budgets with a heuristic numeric parse.

```bash
# Default: writes docs/test-specs/FLOW-001.md and auto-links it into the flow
"scripts/user-flow-manager.sh" test-spec FLOW-001

# Print only (no file, no link)
"scripts/user-flow-manager.sh" test-spec FLOW-001 --stdout

# Custom output location (still auto-linked)
"scripts/user-flow-manager.sh" test-spec FLOW-001 --out docs/test-specs/onboarding.md
```

The output contains:

- A Markdown summary of each scenario (Given / When / Then)
- An assertions list derived from `Key Interactions`
- A budgets list derived from `Success Metrics`, with each line parsed into `{op, value, unit}` when possible
- A `Machine-readable spec` block containing the canonical JSON form

By default the resulting `.md` file is added to the flow's `Integration
Tests` field, satisfying the linkage that `sync` will look for. Pass
`--stdout` if you want raw piping (e.g. to feed another tool) and need to
suppress the write-back.

This spec is the handoff artifact for whoever writes the integration tests during final review. No test code is generated automatically; the framework choice and test layout remain repository decisions.

## Options

| Option | Description |
|--------|-------------|
| `--no-color` | Disable colored output |
| `--help`, `-h` | Show help message |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Flow not found |
| 2 | Target (story or epic) not found |
| 3 | Invalid arguments |
| 4 | File not writable |
| 5 | Already linked |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `NO_COLOR` | Set to disable colored output |
| `USER_FLOWS_FILE` | Override default `docs/User-Flows.md` path |
| `USER_STORIES_FILE` | Override default `docs/UserStories.md` path |
| `TODOS_FILE` | Override default `docs/ToDos.md` path |

## Related Commands

- `/story` — Manage user stories
- `/epic-review` — Review epic status and tasks
- `/nextTask` — Select the next task to work on
- `/implement` — Implement a specific task

## Files

- **Command**: `AItools/commands/user-flow.md`
- **Driver**: `scripts/user-flow-manager.sh`
- **Library**: `scripts/lib/user-flow-parser.sh`
- **Flows**: `docs/User-Flows.md`
- **Stories**: `docs/UserStories.md`
- **Epics**: `docs/ToDos.md`
