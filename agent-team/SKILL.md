---
name: agent-team
description: Launch a coordinated multi-agent Claude Code team with orchestrator and workers in tmux
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
/agent:team [OPTIONS]

Options:
  --task "DESCRIPTION"  Task description for the team
  --workers N           Number of worker agents (default: 2)
  --orchestrator-model MODEL  Model for orchestrator (opus, sonnet, haiku)
  --model MODEL         Model for workers (default: sonnet)
  --dry-run             Preview commands without launching
  --attach              Attach to existing session
  --kill                Kill existing session
  --workspace DIR       Working directory (default: CWD)
```

---

# Agent Team

Launch a coordinated multi-agent Claude Code team in tmux with automatic orchestration.

## Instructions

Run the agent-team launcher script:

```bash
scripts/agent-team.sh [OPTIONS]
```

## Critical Rules

1. **NEVER use `--detach`** when launching from Claude Code or an IDE. The script auto-detects the environment and opens a new terminal tab (iTerm2/Terminal.app on macOS, gnome-terminal/konsole on Linux). Using `--detach` bypasses this and leaves the session invisible to the user.
2. **Always pass `--workspace`** with the current working directory to ensure the dashboard and agents operate on the correct repository.
3. **Use `--dry-run` first** if unsure about options - it previews all commands without launching anything.

## Quick Start

```bash
# Default: orchestrator + 2 workers (auto-opens new terminal tab)
agent-team.sh --task "Implement the auth module"

# 4 workers with specific models
agent-team.sh --workers 4 --orchestrator-model opus --model sonnet

# Preview commands without launching
agent-team.sh --dry-run --workers 3 --task "Refactor database layer"

# Attach to existing session
agent-team.sh --attach

# Kill session
agent-team.sh --kill
```

## Architecture

```
+---------------------+------------------------+
|                     |   Dashboard (compact)   |
|   Orchestrator      |   (top-right, 30%)      |
|   (left, 40%)       +------------+------------+
|                     |  Worker 1  |  Worker 2  |
|                     |  (bottom-right panes)   |
+---------------------+------------+------------+
```

- **Orchestrator** (left pane): Team lead that reads `docs/ToDos.md`, creates tasks, and assigns work to workers using Claude Code's built-in team features (`TeamCreate`, `TaskCreate`, `SendMessage`).
- **Dashboard** (top-right): Compact real-time status display showing task progress, active agents, and branch state.
- **Workers** (bottom-right): Independent Claude Code agents that receive task assignments, work autonomously, and report completion.

## Coordination

Agents coordinate through three complementary mechanisms:

1. **Claude Code Teams**: Built-in `TeamCreate`/`TaskCreate`/`SendMessage` for real-time task assignment and communication.
2. **Stigmergic Files**: `docs/ToDos.md` for task claiming, `docs/work-logs/` for progress, `docs/discoveries/` for cross-agent signals.
3. **Handoff Documents**: `docs/handoffs/<from>--<to>--<ts>.md` for compact, structured context transfer at delegation and worker-transition edges. See [Handoff Document Standard](../../docs/common/handoff-standard.md).

Each agent uses a `claimed_by` identifier following the pattern `{session}/{role}` (e.g., `agent-team/orchestrator`, `agent-team/worker-1`).

## Embedded Handoff Documents

`/agent-team` writes handoff documents automatically at three transition
edges. These are **not** user-invoked; they are side effects of the
orchestrator and workers crossing delegation, pause, completion, or
block boundaries. The artifact shape and redaction rules are defined in
the [Handoff Document Standard](../../docs/common/handoff-standard.md);
this section describes the embedded behavior unique to agent teams.

### Edge 1 -- Orchestrator delegates to a worker

When the orchestrator assigns a task to a worker, **before** sending
the `SendMessage` brief, it writes:

```
docs/handoffs/<team-name>-orchestrator--<team-name>-<worker-name>--<ISO-timestamp>.md
```

Frontmatter highlights:

```yaml
---
kind: handoff
from: <team-name>/orchestrator
to: <team-name>/<worker-name>
produced_at: <ISO-timestamp>
retention: durable
focus: <one-sentence statement of what the worker should accomplish>
related_task: TODO-<NNN>-<MMM>
suggested_skills:
  - /tdd
  - /quick-commit
---
```

Body sections follow the template at
`assets/handoff-document.md`: Current State, Key Artifacts
(paths and URLs only), Next-Agent Focus, Suggested Skills, Open
Questions, Redaction Notes.

After writing the artifact, the orchestrator's `SendMessage` to the
worker contains **only** the handoff path -- the worker reads the
artifact directly. This keeps live-IPC traffic compact and preserves
the audit trail.

### Edge 2 -- Worker pauses, completes, or blocks

When a worker transitions out of `in_progress`, it writes a handoff
**back to the orchestrator** (or to `any` if the orchestrator is no
longer needed). One artifact per transition:

| Transition | `to:` | `focus:` shape |
|------------|-------|----------------|
| Pause | `<team-name>/orchestrator` | "Resume from cycle B<n> when [condition] holds" |
| Complete | `<team-name>/orchestrator` | "Task TODO-<id> complete; orchestrator may close or reassign" |
| Block | `<team-name>/orchestrator` | "Blocked on [dependency]; unblock by [action]" |

The worker also updates its work-log frontmatter to point at the new
artifact:

```yaml
---
handoff_status: ready | paused | blocked
handoff_artifact: docs/handoffs/<this-handoff>.md
---
```

### Edge 3 -- Team session end

When the tmux session is torn down (`--kill` invocation or user-driven
close), the orchestrator writes a final handoff with `to: any` and a
`focus:` describing the team's outstanding work. The handoff names the
next likely slash command in `suggested_skills:` so a future
`/nextTask` invocation can pick the thread up.

### Redaction

Each write applies the regex denylist from the Handoff Document
Standard at write time. Categories touched and substitution count are
recorded in the artifact's `redaction:` frontmatter block. The
orchestrator does **not** include redaction values in its `SendMessage`
brief to workers -- workers read the redacted artifact and may request
clarification through IPC if a redaction obscured load-bearing context.

### Reading on worker start

Each worker begins by reading the handoff artifact named in its
`SendMessage` brief. After reading, the worker updates the artifact's
frontmatter:

```yaml
---
consumed_at: <ISO-timestamp of read>
consumed_by: <team-name>/<worker-name>
---
```

These are the only edits a consumer makes to a handoff. The body is
append-only thereafter -- if the worker disagrees with the handoff or
finds it stale, the correction goes in a new handoff (worker to
orchestrator), referencing the original via `related_handoff:`.

## Options

| Option | Description |
|--------|-------------|
| `--workers N` | Number of worker agents (1-6, default: 2) |
| `--task DESCRIPTION` | Task for the orchestrator to coordinate |
| `--model MODEL` | Worker model (default: sonnet) |
| `--orchestrator-model M` | Orchestrator model (default: opus) |
| `--session NAME` | tmux session name (default: agent-team) |
| `--workspace PATH` | Workspace root directory |
| `--attach` | Attach to existing session |
| `--detach` | Create session but don't attach |
| `--kill` | Kill existing agent-team session |
| `--no-dashboard` | Disable the dashboard pane |
| `--dry-run` | Show commands without executing |
| `--no-color` | Disable colored output |

## Prerequisites

- `tmux` must be installed
- `claude` CLI must be available
- `~/.claude-agentic` config directory must exist (run `setup-claude-links.sh`)

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
