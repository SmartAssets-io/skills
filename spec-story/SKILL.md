---
name: spec-story
description: Create, link, and synchronize user stories with epics providing bi-directional linking between UserStories.md and ToDos.md
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
/spec:story <subcommand> [arguments]

Subcommands:
  create [flags]        Create a new user story in docs/UserStories.md
                        Non-TTY callers (AI agents / CI) MUST use flag or JSON mode:
                          --persona TEXT --capability TEXT --benefit TEXT
                          --criteria TEXT (repeatable) [--title TEXT]
                        or:
                          --from-json <path>   (JSON file with the same fields)
                        With no flags on a TTY, launches the interactive wizard.
  link STORY-ID EPIC-ID  Link a story to an epic (bi-directional)
  sync                  Synchronize links between UserStories.md and ToDos.md
  review [STORY-ID]     Review story status and progress

Manages user stories with bi-directional linking to epics.
```

---

# Story Management

Create, link, and synchronize user stories with epics. This command provides command-line management of user stories in `docs/UserStories.md` with bi-directional linking to epics in `docs/ToDos.md`.

## Usage

Run the story-manager script with a subcommand:

```bash
"scripts/story-manager.sh" <subcommand> [arguments]
```

## Subcommands

### create

Create a new user story. The script supports **three input modes**; pick the one that matches your context:

> **Rule for AI agents, CI, and any non-TTY caller:** always use flag mode (1) or JSON mode (2). The interactive wizard (3) requires a TTY and will exit with a descriptive error otherwise. If you see `Error: No TTY available`, you are in a non-TTY context — switch to mode 1 or 2.

#### Mode 1 — Flag mode (preferred for AI agents / CI)

Every field is passed on the command line. This is the correct mode when this skill is invoked by an AI tool, a CI job, a background process, or any bash session without a controlling terminal.

Required: `--persona`, `--capability`, `--benefit`. `--criteria` is repeatable. `--title` is optional (auto-generated from `--capability` if omitted).

```bash
"scripts/story-manager.sh" create \
    --persona    "developer using AI assistants" \
    --capability "visualize task dependencies across epics" \
    --benefit    "I can identify critical paths and blockers early" \
    --criteria   "Dependency graph generated from docs/ToDos.md" \
    --criteria   "Output in Mermaid format, renderable in GitLab" \
    --title      "Task dependency visualization"
```

The script auto-assigns the next `US-XXX` ID and writes the story to `docs/UserStories.md`.

#### Mode 2 — JSON mode (`--from-json`)

Put the same fields in a JSON file and pass its path. Useful when fields contain shell-unfriendly characters or when the story is being assembled by another tool.

```bash
"scripts/story-manager.sh" create --from-json path/to/story.json
```

JSON schema:

```json
{
  "persona": "developer using AI assistants",
  "capability": "visualize task dependencies across epics",
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
"scripts/story-manager.sh" create
```

The wizard prompts for:
1. **Persona** - Who benefits from this feature (multi-choice with common options)
2. **Capability** - What the user wants to do
3. **Benefit** - Why they want this capability
4. **Acceptance Criteria** - Definition of done (multiple entries)
5. **Title** - Auto-suggested from capability, can override

In Claude Code specifically, a human user can still drive the wizard by prefixing the command with `!` in the prompt so it runs in their own shell with a real TTY:

```
! "scripts/story-manager.sh" create
```

The output then lands back in the conversation for the AI to follow up with (e.g., linking the new story to an epic).

### link

Link a story to an epic with bi-directional updates:

```bash
"scripts/story-manager.sh" link US-010 EPIC-012
```

Updates both files:
- **UserStories.md**: Sets "Implemented in" field, updates status to "In Progress"
- **ToDos.md**: Adds "user_story" field to epic YAML

### sync

Scan and report unlinked stories and epics:

```bash
"scripts/story-manager.sh" sync
```

Shows:
- Total counts of stories and epics
- Orphan stories (no linked epic)
- Orphan epics (no linked story)
- Suggestions for linking

### review

Review story status and progress:

```bash
# Review all stories
"scripts/story-manager.sh" review

# Review specific story
"scripts/story-manager.sh" review US-010
```

Displays:
- Story statement (persona, capability, benefit)
- Current status and linked epic
- Acceptance criteria with completion status
- Epic progress (task counts)

## Options

| Option | Description |
|--------|-------------|
| `--no-color` | Disable colored output |
| `--help`, `-h` | Show help message |

## Examples

### Create a New Story (Flag mode -- AI / CI)

```bash
$ "scripts/story-manager.sh" create \
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

$ "scripts/story-manager.sh" create --from-json /tmp/story.json

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
$ "scripts/story-manager.sh" create

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

### Link Story to Epic

```bash
$ "scripts/story-manager.sh" link US-010 EPIC-012

Linking US-010 to EPIC-012...

Updated docs/UserStories.md:
  - US-010: Added "Implemented in: EPIC-012"

Updated docs/ToDos.md:
  - EPIC-012: Added "User Story: US-010"

* Bi-directional link created
```

### Sync Report

```bash
$ "scripts/story-manager.sh" sync

+==============================================================+
|  Story Sync Report                                           |
+==============================================================+

Stories: 10 total
  * Linked:   6
  o Orphan:   4

Epics: 12 total
  * Linked:   4
  o Orphan:   8

+--------------------------------------------------------------+
|  Orphan Stories (no epic)                                   |
+--------------------------------------------------------------+
  US-007  Automated Epic Archival
  US-008  Task Dependency Visualization

+--------------------------------------------------------------+
|  Orphan Epics (no story)                                    |
+--------------------------------------------------------------+
  EPIC-008  Multi-Agent PR/MR Review System
  EPIC-009  Epic Review Slash Command

Run '/story link US-XXX EPIC-YYY' to create links.
```

### Review Story

```bash
$ "scripts/story-manager.sh" review US-010

+==============================================================+
|  US-010: Story Management Slash Commands                     |
+==============================================================+

As a **project/team lead**, I want **slash commands to create,
develop, and synchronize user stories with epics** so that **I
can maintain traceability between business needs and tasks**.

+--------------------------------------------------------------+
|  Status: In Progress                                         |
|  Linked Epic: EPIC-012 (pending, 0/9 tasks)               |
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
| 2 | Epic not found |
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

- `/epic-review` - Review epic status and tasks
- `/nextTask` - Get the next task to work on
- `/implement` - Implement a specific task

## Files

- **Script**: `scripts/story-manager.sh`
- **Library**: `scripts/lib/story-parser.sh`
- **Stories**: `docs/UserStories.md`
- **Epics**: `docs/ToDos.md`

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
