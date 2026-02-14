---
name: agent-teams-tmux
description: Launch a tmux-based display for monitoring parallel agent teams with real-time dashboard and stigmergic file watchers
license: SSL
---

# Agent Teams tmux Display

Launch a tmux session with a real-time dashboard and agent panes for monitoring multi-agent coding sessions.

## Instructions

Run the agent-teams-tmux launcher script:

```bash
scripts/agent-teams-tmux.sh [OPTIONS]
```

## Quick Start

```bash
# Default: 2 agent panes with dashboard
agent-teams-tmux.sh

# 4 agents with tiled layout
agent-teams-tmux.sh --agents 4 --layout tiled

# Attach to existing session
agent-teams-tmux.sh --attach

# Kill session
agent-teams-tmux.sh --kill
```

## Layouts

| Layout | Description |
|--------|-------------|
| `dashboard` | Top pane = status dashboard, bottom = agent panes (default) |
| `tiled` | Equal-sized panes for dashboard + all agents |
| `stacked` | Vertical stack: dashboard on top, agents below |

## Dashboard

The dashboard pane shows:
- **Task Progress**: Epoch completion with status indicators
- **Active Agents**: Current task claims and agent identities
- **Recent Activity**: Work log updates and discoveries
- **Branch State**: Per-repo branch names and dirty status

Dashboard refreshes every 5 seconds in watch mode.

## File Watcher

For real-time event streaming, run the watcher in a separate pane:

```bash
agent-teams-watcher.sh --workspace /path/to/SA --notify
```

Monitors:
- `docs/ToDos.md` for task claim/status changes
- `docs/work-logs/` for new entries
- `docs/discoveries/` for cross-agent signals

Supports fswatch (macOS), inotifywait (Linux), or polling fallback.

## Options

| Option | Description |
|--------|-------------|
| `--agents N` | Number of agent panes (1-8, default: 2) |
| `--layout LAYOUT` | Layout style: dashboard, tiled, stacked |
| `--session NAME` | tmux session name (default: agent-teams) |
| `--workspace PATH` | Workspace root to monitor |
| `--attach` | Attach to existing session |
| `--detach` | Create but don't attach |
| `--kill` | Kill existing session |
| `--no-color` | Disable colored output |

## Multi-Harness Support

The dashboard reads from stigmergic `.md` files, making it tool-agnostic. You can run different AI tools in each pane:

- **Pane 1**: Claude Code (claude-agentic)
- **Pane 2**: Cursor/Windsurf IDE
- **Pane 3**: Aider or Gemini CLI
- **Dashboard**: Shows unified task state from all tools

All tools coordinate through the shared `docs/ToDos.md` and work log files.

## Prerequisites

- `tmux` must be installed
- For file watching: `fswatch` (macOS) or `inotifywait` (Linux)
