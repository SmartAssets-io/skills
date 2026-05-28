---
name: agent-team
description: Launch a coordinated multi-agent Claude Code team with orchestrator and workers in tmux
license: SSL
---

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
3. **Handoff Documents**: `docs/handoffs/<from>--<to>--<ts>.md` for compact, structured context transfer at delegation and worker-transition edges. See [Handoff Document Standard](../../../../docs/common/handoff-standard.md).

Each agent uses a `claimed_by` identifier following the pattern `{session}/{role}` (e.g., `agent-team/orchestrator`, `agent-team/worker-1`).

## Embedded Handoff Documents

`/agent-team` writes handoff documents automatically at three transition
edges. These are **not** user-invoked; they are side effects of the
orchestrator and workers crossing delegation, pause, completion, or
block boundaries. The artifact shape and redaction rules are defined in
the [Handoff Document Standard](../../../../docs/common/handoff-standard.md);
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
`AItools/templates/handoff-document.md`: Current State, Key Artifacts
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
