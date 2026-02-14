---
name: agent-team
description: Launch a coordinated multi-agent Claude Code team with orchestrator and workers in tmux
license: SSL
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

Agents coordinate through two complementary mechanisms:

1. **Claude Code Teams**: Built-in `TeamCreate`/`TaskCreate`/`SendMessage` for real-time task assignment and communication.
2. **Stigmergic Files**: `docs/ToDos.md` for task claiming, `docs/work-logs/` for progress, `docs/discoveries/` for cross-agent signals.

Each agent uses a `claimed_by` identifier following the pattern `{session}/{role}` (e.g., `agent-team/orchestrator`, `agent-team/worker-1`).

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
