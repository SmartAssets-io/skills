#!/usr/bin/env bash
#
# agent-teams-tmux.sh - tmux-based visibility for parallel agent work
#
# Creates a tmux session with dashboard and agent panes for monitoring
# multi-agent coding sessions in real-time.
#
# Usage:
#   agent-teams-tmux.sh [OPTIONS]
#   agent-teams-tmux.sh --agents 3 --layout tiled
#   agent-teams-tmux.sh --attach
#   agent-teams-tmux.sh --kill
#
# Options:
#   --agents N         Number of agent panes (default: 2)
#   --layout LAYOUT    Layout: dashboard|tiled|stacked (default: dashboard)
#   --session NAME     tmux session name (default: agent-teams)
#   --workspace PATH   Workspace root to monitor (default: auto-detect)
#   --attach           Attach to existing session
#   --detach           Create but don't attach
#   --kill             Kill existing session
#   --no-color         Disable colored output
#   -h, --help         Show help
#
# Exit codes:
#   0 - Success
#   1 - tmux not available
#   2 - Session creation failed
#   3 - Invalid arguments
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DASHBOARD_SCRIPT="$SCRIPT_DIR/agent-teams-dashboard.sh"

# Defaults
AGENT_COUNT=2
LAYOUT="dashboard"
SESSION_NAME="agent-teams"
WORKSPACE_PATH=""
ACTION="create"
NO_COLOR="${NO_COLOR:-}"
DETACH=false
SKIP_TMUX_CHECK="${SKIP_TMUX_CHECK:-false}"

# Exit codes
EXIT_SUCCESS=0
EXIT_NO_TMUX=1
EXIT_CREATE_FAIL=2
EXIT_INVALID_ARGS=3

# Colors
COLOR_RESET='' COLOR_GREEN='' COLOR_YELLOW='' COLOR_RED='' COLOR_BLUE='' COLOR_CYAN='' COLOR_BOLD='' COLOR_DIM=''

setup_colors() {
    if [[ -z "$NO_COLOR" ]] && [[ -t 1 ]]; then
        COLOR_RESET='\033[0m' COLOR_GREEN='\033[0;32m' COLOR_YELLOW='\033[1;33m'
        COLOR_RED='\033[0;31m' COLOR_BLUE='\033[0;34m' COLOR_CYAN='\033[0;36m'
        COLOR_BOLD='\033[1m' COLOR_DIM='\033[2m'
    fi
}

log_info() { echo -e "${COLOR_BLUE}[TMUX]${COLOR_RESET} $*"; }
log_ok()   { echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $*"; }
log_warn() { echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"; }
log_fail() { echo -e "${COLOR_RED}[FAIL]${COLOR_RESET} $*"; }

show_help() {
    cat <<'EOF'
Usage: agent-teams-tmux.sh [OPTIONS]

Create a tmux session for monitoring parallel agent work.

Layouts:
  dashboard     Top pane = status dashboard, bottom = agent panes (default)
  tiled         Equal-sized panes for all agents + dashboard
  stacked       Vertical stack: dashboard on top, agents below
  orchestrator  Left pane = orchestrator, right = dashboard + worker panes

Options:
  --agents N         Number of agent panes (default: 2, max: 8)
  --layout LAYOUT    Layout style: dashboard|tiled|stacked
  --session NAME     tmux session name (default: agent-teams)
  --workspace PATH   Workspace root to monitor
  --attach           Attach to existing session
  --detach           Create session but don't attach
  --kill             Kill existing agent-teams session
  --no-color         Disable colored output
  --no-tmux-check    Skip the tmux session check
  -h, --help         Show this help

Examples:
  agent-teams-tmux.sh --agents 3
  agent-teams-tmux.sh --layout tiled --agents 4
  agent-teams-tmux.sh --attach
  agent-teams-tmux.sh --kill
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --agents)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --agents requires a number" >&2
                    exit $EXIT_INVALID_ARGS
                fi
                AGENT_COUNT="$2"
                if [[ ! "$AGENT_COUNT" =~ ^[1-8]$ ]]; then
                    echo "Error: --agents must be 1-8" >&2
                    exit $EXIT_INVALID_ARGS
                fi
                shift 2
                ;;
            --layout)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --layout requires a value" >&2
                    exit $EXIT_INVALID_ARGS
                fi
                LAYOUT="$2"
                case "$LAYOUT" in
                    dashboard|tiled|stacked|orchestrator) ;;
                    *) echo "Error: --layout must be dashboard|tiled|stacked|orchestrator" >&2; exit $EXIT_INVALID_ARGS ;;
                esac
                shift 2
                ;;
            --session)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --session requires a name" >&2
                    exit $EXIT_INVALID_ARGS
                fi
                SESSION_NAME="$2"
                shift 2
                ;;
            --workspace)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --workspace requires a path" >&2
                    exit $EXIT_INVALID_ARGS
                fi
                WORKSPACE_PATH="$2"
                shift 2
                ;;
            --attach)   ACTION="attach"; shift ;;
            --detach)   DETACH=true; shift ;;
            --kill)     ACTION="kill"; shift ;;
            --no-color) NO_COLOR=1; setup_colors; shift ;;
            --no-tmux-check) SKIP_TMUX_CHECK=true; shift ;;
            -h|--help)  show_help; exit $EXIT_SUCCESS ;;
            -*)         echo "Error: Unknown option: $1" >&2; exit $EXIT_INVALID_ARGS ;;
            *)          echo "Error: Unexpected argument: $1" >&2; exit $EXIT_INVALID_ARGS ;;
        esac
    done
}

# Auto-detect workspace root
detect_workspace() {
    if [[ -n "$WORKSPACE_PATH" ]]; then
        echo "$WORKSPACE_PATH"
        return
    fi

    local dir="$PROJECT_ROOT"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/CLAUDE.md" ]] && [[ "$(basename "$dir")" == "SA" || -d "$dir/top-level-gitlab-profile" ]]; then
            echo "$dir"
            return
        fi
        dir=$(dirname "$dir")
    done
    dirname "$PROJECT_ROOT"
}

# Check prerequisites
check_prerequisites() {
    if ! command -v tmux &>/dev/null; then
        log_fail "tmux is not installed"
        log_info "Install with: brew install tmux (macOS) or apt install tmux (Linux)"
        exit $EXIT_NO_TMUX
    fi

    if [[ "$SKIP_TMUX_CHECK" != "true" ]] && [[ -z "${TMUX:-}" ]]; then
        # Skip tmux check when running from Claude Code or IDE - the parent
        # script (agent-team.sh) handles this by opening a new terminal tab
        if [[ -n "${CLAUDECODE:-}" ]] || [[ -n "${TERM_PROGRAM:-}" && "${TERM_PROGRAM}" == "vscode" ]]; then
            log_info "Running from IDE/Claude Code - tmux session will be created detached"
        else
            log_fail "Not running inside a tmux session"
            log_info "Start tmux first, then run agent-teams-tmux from within it:"
            log_info "  tmux new -s work"
            log_info "  claude-agentic    # interactive agentic or YOLO mode"
            log_info "Or bypass with: --no-tmux-check or SKIP_TMUX_CHECK=true"
            exit $EXIT_NO_TMUX
        fi
    fi
}

# Kill existing session
kill_session() {
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        tmux kill-session -t "$SESSION_NAME"
        log_ok "Killed session: $SESSION_NAME"
    else
        log_warn "No session named '$SESSION_NAME' found"
    fi
}

# Attach to existing session
attach_session() {
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        tmux attach-session -t "$SESSION_NAME"
    else
        log_fail "No session named '$SESSION_NAME' found"
        log_info "Create one with: agent-teams-tmux.sh --agents N"
        exit $EXIT_CREATE_FAIL
    fi
}

# Create the tmux session with layout
create_session() {
    local workspace
    workspace=$(detect_workspace)

    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        log_warn "Session '$SESSION_NAME' already exists"
        log_info "Use --attach to connect or --kill to remove"
        exit $EXIT_CREATE_FAIL
    fi

    log_info "Creating tmux session: $SESSION_NAME"
    log_info "  Layout: $LAYOUT"
    log_info "  Agents: $AGENT_COUNT"
    log_info "  Workspace: $workspace"

    # Create session with first window
    tmux new-session -d -s "$SESSION_NAME" -x 220 -y 50

    case "$LAYOUT" in
        dashboard)    create_dashboard_layout "$workspace" ;;
        tiled)        create_tiled_layout "$workspace" ;;
        stacked)      create_stacked_layout "$workspace" ;;
        orchestrator) create_orchestrator_layout "$workspace" ;;
    esac

    # Set status bar
    tmux set-option -t "$SESSION_NAME" status-style "bg=colour235,fg=colour136"
    tmux set-option -t "$SESSION_NAME" status-left "#[fg=colour46,bold] AGENT TEAMS #[fg=colour245]| "
    tmux set-option -t "$SESSION_NAME" status-right "#[fg=colour245]${AGENT_COUNT} agents | #[fg=colour136]%H:%M"
    tmux set-option -t "$SESSION_NAME" status-left-length 30

    # Set terminal title for iTerm2 tab display (use cwd, not workspace root)
    local dir_name
    dir_name=$(basename "$PWD")
    tmux set-option -t "$SESSION_NAME" set-titles on
    tmux set-option -t "$SESSION_NAME" set-titles-string "agent team: $dir_name"
    tmux rename-window -t "$SESSION_NAME:0" "agent team: $dir_name"

    log_ok "Session created: $SESSION_NAME"

    if [[ "$DETACH" != "true" ]]; then
        log_info "Attaching..."
        tmux attach-session -t "$SESSION_NAME"
    else
        log_info "Session running in background. Attach with:"
        log_info "  tmux attach -t $SESSION_NAME"
    fi
}

# Dashboard layout: top = dashboard, bottom = agent panes
create_dashboard_layout() {
    local workspace="$1"

    # Rename first window
    tmux rename-window -t "$SESSION_NAME:0" "agents"

    # Start dashboard in first pane
    tmux send-keys -t "$SESSION_NAME:0" "bash '$DASHBOARD_SCRIPT' --workspace '$workspace' --watch" C-m

    # Split horizontally for agent area (dashboard gets 30% top)
    tmux split-window -t "$SESSION_NAME:0" -v -p 70

    # Create agent panes in the bottom area
    local i
    for ((i=2; i<=AGENT_COUNT; i++)); do
        tmux split-window -t "$SESSION_NAME:0" -h -p $((100 / (AGENT_COUNT - i + 2)))
    done

    # Label each agent pane
    local pane_idx=1
    for ((i=1; i<=AGENT_COUNT; i++)); do
        tmux send-keys -t "$SESSION_NAME:0.${pane_idx}" "echo '--- Agent $i pane ---'; echo 'Launch your agent here or use: claude-agentic'" C-m
        pane_idx=$((pane_idx + 1))
    done

    # Select dashboard pane
    tmux select-pane -t "$SESSION_NAME:0.0"
}

# Tiled layout: equal panes for dashboard + agents
create_tiled_layout() {
    local workspace="$1"

    tmux rename-window -t "$SESSION_NAME:0" "agents"

    # Dashboard in first pane
    tmux send-keys -t "$SESSION_NAME:0" "bash '$DASHBOARD_SCRIPT' --workspace '$workspace' --watch" C-m

    # Create agent panes
    local i
    for ((i=1; i<=AGENT_COUNT; i++)); do
        tmux split-window -t "$SESSION_NAME:0"
        tmux send-keys -t "$SESSION_NAME:0" "echo '--- Agent $i pane ---'; echo 'Launch your agent here'" C-m
    done

    # Apply tiled layout
    tmux select-layout -t "$SESSION_NAME:0" tiled
}

# Stacked layout: vertical stack
create_stacked_layout() {
    local workspace="$1"

    tmux rename-window -t "$SESSION_NAME:0" "agents"

    # Dashboard in first pane
    tmux send-keys -t "$SESSION_NAME:0" "bash '$DASHBOARD_SCRIPT' --workspace '$workspace' --watch" C-m

    # Create agent panes stacked below
    local pane_height=$((70 / AGENT_COUNT))
    local i
    for ((i=1; i<=AGENT_COUNT; i++)); do
        tmux split-window -t "$SESSION_NAME:0" -v -p $pane_height
        tmux send-keys -t "$SESSION_NAME:0" "echo '--- Agent $i pane ---'; echo 'Launch your agent here'" C-m
    done

    # Select dashboard
    tmux select-pane -t "$SESSION_NAME:0.0"
}

# Orchestrator layout: left = orchestrator, right = dashboard + workers (stacked vertically)
#
# +---------------------+------------------------+
# |                     |   Dashboard (compact)   |
# |                     +------------------------+
# |   Orchestrator      |       Worker 1          |
# |   (left, 40%)       +------------------------+
# |                     |       Worker 2          |
# |                     +------------------------+
# |                     |       Worker 3          |
# +---------------------+------------------------+
create_orchestrator_layout() {
    local workspace="$1"

    tmux rename-window -t "$SESSION_NAME:0" "agents"

    # Pane 0 = orchestrator (left, 40%)
    tmux send-keys -t "$SESSION_NAME:0.0" "echo '--- Orchestrator pane ---'; echo 'Launch orchestrating agent here or use: claude-agentic'" C-m

    # Split right for dashboard + workers (60% right)
    tmux split-window -t "$SESSION_NAME:0.0" -h -p 60

    # Right side pane is now pane 1
    # Calculate dashboard height as percentage of right column
    local total_right_panes=$((AGENT_COUNT + 1))  # dashboard + workers
    local dashboard_pct=$((100 / total_right_panes))

    # Start dashboard in pane 1 (will become top-right after splits)
    tmux send-keys -t "$SESSION_NAME:0.1" "bash '$DASHBOARD_SCRIPT' --workspace '$workspace' --watch --compact" C-m

    # Split right column into stacked panes from top to bottom
    # Strategy: split pane 1 once to create dashboard (top) + worker area (bottom),
    # then split the bottom pane for additional workers
    local split_target=1
    local i
    for ((i=1; i<=AGENT_COUNT; i++)); do
        # Each split takes a percentage from the remaining space
        local remaining=$((AGENT_COUNT - i + 1))
        local pct=$((100 * remaining / (remaining + 1)))

        tmux split-window -t "$SESSION_NAME:0.${split_target}" -v -p "$pct"
        # After splitting pane N, the new pane gets the next index
        # and the original pane stays as the top portion
        split_target=$((split_target + 1))
    done

    # Pane mapping after splits:
    #   pane 0 = orchestrator (left)
    #   pane 1 = dashboard (top-right)
    #   pane 2 = worker 1
    #   pane 3 = worker 2
    #   pane N+1 = worker N

    # Label each worker pane
    local pane_idx=2
    for ((i=1; i<=AGENT_COUNT; i++)); do
        tmux send-keys -t "$SESSION_NAME:0.${pane_idx}" "echo '--- Worker $i pane ---'; echo 'Launch your agent here or use: claude-agentic'" C-m
        pane_idx=$((pane_idx + 1))
    done

    # Select orchestrator pane
    tmux select-pane -t "$SESSION_NAME:0.0"
}

# --- Main ---

main() {
    setup_colors
    parse_args "$@"

    case "$ACTION" in
        create)
            check_prerequisites
            create_session
            ;;
        attach)  attach_session ;;
        kill)    kill_session ;;
    esac
}

main "$@"
