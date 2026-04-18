---
name: user-story-management
description: Create, link, and synchronize user stories with epochs providing bi-directional linking between UserStories.md and ToDos.md
license: SSL
---

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/story <subcommand> [arguments]

Subcommands:
  create [flags]        Create a new user story in docs/UserStories.md
                        Non-TTY callers (AI agents / CI) MUST use flag or JSON mode:
                          --persona TEXT --capability TEXT --benefit TEXT
                          --criteria TEXT (repeatable) [--title TEXT]
                        or:
                          --from-json <path>   (JSON file with the same fields)
                        With no flags on a TTY, launches the interactive wizard.
  link STORY-ID EPOCH-ID  Link a story to an epoch (bi-directional)
  sync                  Synchronize links between UserStories.md and ToDos.md
  review [STORY-ID]     Review story status and progress

Manages user stories with bi-directional linking to epochs.
```

---

# Story Management

Create, link, and synchronize user stories with epochs. This command provides command-line management of user stories in `docs/UserStories.md` with bi-directional linking to epochs in `docs/ToDos.md`.

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
# Fallback: SA_GITLAB_PROFILE env var (set via shell-config.sh)
if [ ! -d "$PROFILE_DIR/AItools/scripts" ] && [ -n "$SA_GITLAB_PROFILE" ] && [ -d "$SA_GITLAB_PROFILE/AItools/scripts" ]; then
  PROFILE_DIR="$SA_GITLAB_PROFILE"
fi
```

Use `"$PROFILE_DIR/AItools/scripts/..."` for all script paths below.

## Usage

Run the story-manager script with a subcommand:

```bash
"$PROFILE_DIR/AItools/scripts/story-manager.sh" <subcommand> [arguments]
```

## Subcommands

### create

Create a new user story. The script supports **three input modes**; pick the one that matches your context:

> **Rule for AI agents, CI, and any non-TTY caller:** always use flag mode (1) or JSON mode (2). The interactive wizard (3) requires a TTY and will exit with a descriptive error otherwise. If you see `Error: No TTY available`, you are in a non-TTY context — switch to mode 1 or 2.

#### Mode 1 — Flag mode (preferred for AI agents / CI)

Every field is passed on the command line. This is the correct mode when this skill is invoked by an AI tool, a CI job, a background process, or any bash session without a controlling terminal.

Required: `--persona`, `--capability`, `--benefit`. `--criteria` is repeatable. `--title` is optional (auto-generated from `--capability` if omitted).

```bash
"$PROFILE_DIR/AItools/scripts/story-manager.sh" create \
    --persona    "developer using AI assistants" \
    --capability "visualize task dependencies across epochs" \
    --benefit    "I can identify critical paths and blockers early" \
    --criteria   "Dependency graph generated from docs/ToDos.md" \
    --criteria   "Output in Mermaid format, renderable in GitLab" \
    --title      "Task dependency visualization"
```

The script auto-assigns the next `US-XXX` ID and writes the story to `docs/UserStories.md`.

#### Mode 2 — JSON mode (`--from-json`)

Put the same fields in a JSON file and pass its path. Useful when fields contain shell-unfriendly characters or when the story is being assembled by another tool.

```bash
"$PROFILE_DIR/AItools/scripts/story-manager.sh" create --from-json path/to/story.json
```

JSON schema:

```json
{
  "persona": "developer using AI assistants",
  "capability": "visualize task dependencies across epochs",
  "benefit": "I can identify critical paths and blockers early",
  "criteria": [
    "Dependency graph generated from docs/ToDos.md",
    "Output in Mermaid format, renderable in GitLab"
  ],
  "title": "Task dependency visualization"
}
```

Individual `--persona` / `--capability` / `--benefit` / `--criteria` / `--title` flags passed alongside `--from-json` **override** the JSON values (useful for overriding one field without editing the file).

#### Mode 3 — Interactive wizard (humans only)

With no input flags and a TTY attached, the script runs an interactive wizard that prompts for each field. **This mode does not work from Claude Code's Bash tool, Codex, other AI agents, or CI** -- those contexts have no TTY. Use mode 1 or 2 instead.

```bash
# Human-only; run directly in a terminal
"$PROFILE_DIR/AItools/scripts/story-manager.sh" create
```

The wizard prompts for:
1. **Persona** - Who benefits from this feature (multi-choice with common options)
2. **Capability** - What the user wants to do
3. **Benefit** - Why they want this capability
4. **Acceptance Criteria** - Definition of done (multiple entries)
5. **Title** - Auto-suggested from capability, can override

In Claude Code specifically, a human user can still drive the wizard by prefixing the command with `!` in the prompt so it runs in their own shell with a real TTY:

```
! "$PROFILE_DIR/AItools/scripts/story-manager.sh" create
```

The output then lands back in the conversation for the AI to follow up with (e.g., linking the new story to an epoch).

### link

Link a story to an epoch with bi-directional updates:

```bash
"$PROFILE_DIR/AItools/scripts/story-manager.sh" link US-010 EPOCH-012
```

Updates both files:
- **UserStories.md**: Sets "Implemented in" field, updates status to "In Progress"
- **ToDos.md**: Adds "user_story" field to epoch YAML

### sync

Scan and report unlinked stories and epochs:

```bash
"$PROFILE_DIR/AItools/scripts/story-manager.sh" sync
```

Shows:
- Total counts of stories and epochs
- Orphan stories (no linked epoch)
- Orphan epochs (no linked story)
- Suggestions for linking

### review

Review story status and progress:

```bash
# Review all stories
"$PROFILE_DIR/AItools/scripts/story-manager.sh" review

# Review specific story
"$PROFILE_DIR/AItools/scripts/story-manager.sh" review US-010
```

Displays:
- Story statement (persona, capability, benefit)
- Current status and linked epoch
- Acceptance criteria with completion status
- Epoch progress (task counts)

## Options

| Option | Description |
|--------|-------------|
| `--no-color` | Disable colored output |
| `--help`, `-h` | Show help message |

## Examples

### Create a New Story (Flag mode -- AI / CI)

```bash
$ "$PROFILE_DIR/AItools/scripts/story-manager.sh" create \
    --persona    "project/team lead" \
    --capability "visualize task dependencies" \
    --benefit    "understand critical paths and identify blockers" \
    --criteria   "Generate dependency graph from ToDos.md" \
    --criteria   "Output in Mermaid format"

+==============================================================+
|  Story Created: US-011                                       |
+--------------------------------------------------------------+
|  Title: Visualize task dependencies                          |
|  Status: Planned                                             |
|  Location: docs/UserStories.md                               |
+==============================================================+
```

### Create a New Story (JSON mode)

```bash
$ cat > /tmp/story.json <<'EOF'
{
  "persona": "project/team lead",
  "capability": "visualize task dependencies",
  "benefit": "understand critical paths and identify blockers",
  "criteria": [
    "Generate dependency graph from ToDos.md",
    "Output in Mermaid format"
  ]
}
EOF

$ "$PROFILE_DIR/AItools/scripts/story-manager.sh" create --from-json /tmp/story.json

+==============================================================+
|  Story Created: US-011                                       |
+--------------------------------------------------------------+
|  Title: Visualize task dependencies                          |
|  Status: Planned                                             |
|  Location: docs/UserStories.md                               |
+==============================================================+
```

### Create a New Story (Interactive wizard -- humans only, requires TTY)

```bash
$ "$PROFILE_DIR/AItools/scripts/story-manager.sh" create

+==============================================================+
|  Create New User Story                                       |
+==============================================================+

Persona (who benefits from this feature):
  1. Developer using AI assistants
  2. Project/Team lead
  3. Workspace maintainer
  4. Open source contributor
  5. Other (enter custom)

> 2

What does the user want to do?
> visualize task dependencies

Why do they want this? (benefit)
> understand critical paths and identify blockers

Add acceptance criteria (empty line to finish):
> Generate dependency graph from ToDos.md
> Output in Mermaid format
>

+==============================================================+
|  Story Created: US-011                                       |
+--------------------------------------------------------------+
|  Title: Visualize task dependencies                          |
|  Status: Planned                                             |
|  Location: docs/UserStories.md                               |
+==============================================================+
```

### Link Story to Epoch

```bash
$ "$PROFILE_DIR/AItools/scripts/story-manager.sh" link US-010 EPOCH-012

Linking US-010 to EPOCH-012...

Updated docs/UserStories.md:
  - US-010: Added "Implemented in: EPOCH-012"

Updated docs/ToDos.md:
  - EPOCH-012: Added "User Story: US-010"

* Bi-directional link created
```

### Sync Report

```bash
$ "$PROFILE_DIR/AItools/scripts/story-manager.sh" sync

+==============================================================+
|  Story Sync Report                                           |
+==============================================================+

Stories: 10 total
  * Linked:   6
  o Orphan:   4

Epochs: 12 total
  * Linked:   4
  o Orphan:   8

+--------------------------------------------------------------+
|  Orphan Stories (no epoch)                                   |
+--------------------------------------------------------------+
  US-007  Automated Epoch Archival
  US-008  Task Dependency Visualization

+--------------------------------------------------------------+
|  Orphan Epochs (no story)                                    |
+--------------------------------------------------------------+
  EPOCH-008  Multi-Agent PR/MR Review System
  EPOCH-009  Epoch Review Slash Command

Run '/story link US-XXX EPOCH-YYY' to create links.
```

### Review Story

```bash
$ "$PROFILE_DIR/AItools/scripts/story-manager.sh" review US-010

+==============================================================+
|  US-010: Story Management Slash Commands                     |
+==============================================================+

As a **project/team lead**, I want **slash commands to create,
develop, and synchronize user stories with epochs** so that **I
can maintain traceability between business needs and tasks**.

+--------------------------------------------------------------+
|  Status: In Progress                                         |
|  Linked Epoch: EPOCH-012 (pending, 0/9 tasks)               |
+--------------------------------------------------------------+
|  Acceptance Criteria:                                        |
|    o /story create works interactively                      |
|    o /story link updates both files                         |
|    o /story sync shows orphans                              |
+--------------------------------------------------------------+
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Story not found |
| 2 | Epoch not found |
| 3 | Invalid arguments |
| 4 | File not writable |
| 5 | Already linked |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `NO_COLOR` | Set to disable colored output |
| `USER_STORIES_FILE` | Override default `docs/UserStories.md` path |
| `TODOS_FILE` | Override default `docs/ToDos.md` path |

## Related Commands

- `/epoch-review` - Review epoch status and tasks
- `/nextTask` - Get the next task to work on
- `/implement` - Implement a specific task

## Files

- **Script**: `AItools/scripts/story-manager.sh`
- **Library**: `AItools/scripts/lib/story-parser.sh`
- **Stories**: `docs/UserStories.md`
- **Epochs**: `docs/ToDos.md`
