#!/usr/bin/env bash
#
# agent-team.sh - Launch a coordinated multi-agent Claude Code team
#
# Wraps agent-teams-tmux.sh with automatic Claude Code orchestration:
# a team lead on the left, auto-launched workers on the right.
#
# Usage:
#   agent-team.sh [OPTIONS]
#   agent-team.sh --workers 3 --task "Implement feature X"
#   agent-team.sh --kill
#
# Options:
#   --workers N              Number of workers (1-6, default: 2)
#   --task DESCRIPTION       Task description for orchestrator
#   --model MODEL            Worker model (default: sonnet)
#   --orchestrator-model M   Orchestrator model (default: opus)
#   --session NAME           tmux session name (default: agent-team)
#   --workspace PATH         Workspace root
#   --attach                 Attach to existing session
#   --detach                 Create but don't attach
#   --kill                   Kill existing session
#   --no-dashboard           Disable dashboard pane
#   --dry-run                Print commands without executing
#   --no-color               Disable colored output
#   -h, --help               Show help
#
# Exit codes:
#   0 - Success
#   1 - Missing prerequisite
#   2 - Session creation failed
#   3 - Invalid arguments
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_SCRIPT="$SCRIPT_DIR/agent-teams-tmux.sh"

# Defaults
WORKER_COUNT=2
TASK_DESCRIPTION=""
WORKER_MODEL="sonnet"
ORCHESTRATOR_MODEL="opus"
SESSION_NAME="agent-team"
WORKSPACE_PATH=""
ACTION="create"
NO_DASHBOARD=false
DRY_RUN=false
NO_COLOR="${NO_COLOR:-}"
DETACH=false
SKIP_TMUX_CHECK="${SKIP_TMUX_CHECK:-false}"

# Exit codes
EXIT_SUCCESS=0
EXIT_NO_PREREQ=1
EXIT_CREATE_FAIL=2
EXIT_INVALID_ARGS=3

# Colors
COLOR_RESET='' COLOR_GREEN='' COLOR_YELLOW='' COLOR_RED='' COLOR_BLUE=''

setup_colors() {
    if [[ -z "$NO_COLOR" ]] && [[ -t 1 ]]; then
        COLOR_RESET='\033[0m' COLOR_GREEN='\033[0;32m' COLOR_YELLOW='\033[1;33m'
        COLOR_RED='\033[0;31m' COLOR_BLUE='\033[0;34m'
    fi
}

log_info() { echo -e "${COLOR_BLUE}[TEAM]${COLOR_RESET} $*"; }
log_ok()   { echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $*"; }
log_warn() { echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"; }
log_fail() { echo -e "${COLOR_RED}[FAIL]${COLOR_RESET} $*"; }

# Auto-attach to tmux in a new terminal window (cross-platform)
auto_attach_new_terminal() {
    local session_name="$1"

    # Detect OS
    case "$(uname -s)" in
        Darwin)
            # macOS - try iTerm2 first, then Terminal.app
            if [[ -d "/Applications/iTerm.app" ]]; then
                local tab_title="agent team: $(basename "${WORKSPACE_PATH:-$PWD}")"
                log_info "Opening new iTerm2 tab and attaching..."
                osascript <<EOF
tell application "iTerm2"
    activate
    tell current window
        set newTab to (create tab with default profile)
        tell current session of newTab
            write text "printf '\\\\033]1;$tab_title\\\\007'; tmux attach -t $session_name"
        end tell
    end tell
end tell
EOF
            else
                # Fallback to Terminal.app
                log_info "Opening new Terminal window and attaching..."
                osascript <<EOF
tell application "Terminal"
    do script "tmux attach -t $session_name"
    activate
end tell
EOF
            fi
            ;;
        Linux)
            # Linux - try common terminal emulators
            if command -v gnome-terminal >/dev/null 2>&1; then
                log_info "Opening new gnome-terminal window and attaching..."
                gnome-terminal -- tmux attach -t "$session_name" &
            elif command -v konsole >/dev/null 2>&1; then
                log_info "Opening new Konsole window and attaching..."
                konsole -e tmux attach -t "$session_name" &
            elif command -v xterm >/dev/null 2>&1; then
                log_info "Opening new xterm window and attaching..."
                xterm -e tmux attach -t "$session_name" &
            else
                log_warn "No supported terminal emulator found for auto-attach"
                return 1
            fi
            ;;
        *)
            log_warn "Unsupported OS for auto-attach: $(uname -s)"
            return 1
            ;;
    esac
}

show_help() {
    cat <<'EOF'
Usage: agent-team.sh [OPTIONS]

Launch a coordinated multi-agent Claude Code team in tmux.

Creates an orchestrator (team lead) and workers, each running Claude Code
with role-specific system prompts. Coordination happens through Claude Code's
built-in team features and stigmergic file-based collaboration.

Architecture:
  +---------------------+------------------------+
  |                     |   Dashboard (compact)   |
  |   Orchestrator      |   (top-right, 30%)      |
  |   (left, 40%)       +------------+------------+
  |                     |  Worker 1  |  Worker 2  |
  |                     |  (bottom-right panes)   |
  +---------------------+------------+------------+

Options:
  --workers N              Number of worker agents (1-6, default: 2)
  --task DESCRIPTION       Task for the orchestrator to coordinate
  --model MODEL            Worker model (default: sonnet)
  --orchestrator-model M   Orchestrator model (default: opus)
  --session NAME           tmux session name (default: agent-team)
  --workspace PATH         Workspace root directory
  --attach                 Attach to existing session
  --detach                 Create session but don't attach
  --kill                   Kill existing agent-team session
  --no-dashboard           Disable the dashboard pane
  --dry-run                Show commands without executing
  --no-color               Disable colored output
  --no-tmux-check          Skip the tmux session check
  -h, --help               Show this help

Examples:
  agent-team.sh --workers 3 --task "Implement auth module"
  agent-team.sh --dry-run --workers 2 --task "Test run"
  agent-team.sh --orchestrator-model opus --model sonnet
  agent-team.sh --attach
  agent-team.sh --kill

Prerequisites:
  - tmux must be installed
  - claude CLI must be available
  - ~/.claude-agentic config directory must exist
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --workers)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --workers requires a number" >&2
                    exit $EXIT_INVALID_ARGS
                fi
                WORKER_COUNT="$2"
                if [[ ! "$WORKER_COUNT" =~ ^[1-6]$ ]]; then
                    echo "Error: --workers must be 1-6" >&2
                    exit $EXIT_INVALID_ARGS
                fi
                shift 2
                ;;
            --task)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --task requires a description" >&2
                    exit $EXIT_INVALID_ARGS
                fi
                TASK_DESCRIPTION="$2"
                shift 2
                ;;
            --model)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --model requires a value" >&2
                    exit $EXIT_INVALID_ARGS
                fi
                WORKER_MODEL="$2"
                shift 2
                ;;
            --orchestrator-model)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --orchestrator-model requires a value" >&2
                    exit $EXIT_INVALID_ARGS
                fi
                ORCHESTRATOR_MODEL="$2"
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
            --attach)       ACTION="attach"; shift ;;
            --detach)       DETACH=true; shift ;;
            --kill)         ACTION="kill"; shift ;;
            --no-dashboard) NO_DASHBOARD=true; shift ;;
            --dry-run)      DRY_RUN=true; shift ;;
            --no-color)     NO_COLOR=1; setup_colors; shift ;;
            --no-tmux-check) SKIP_TMUX_CHECK=true; shift ;;
            -h|--help)      show_help; exit $EXIT_SUCCESS ;;
            -*)             echo "Error: Unknown option: $1" >&2; exit $EXIT_INVALID_ARGS ;;
            *)              echo "Error: Unexpected argument: $1" >&2; exit $EXIT_INVALID_ARGS ;;
        esac
    done
}

check_prerequisites() {
    local missing=false

    if ! command -v tmux &>/dev/null; then
        log_fail "tmux is not installed"
        log_info "Install with: brew install tmux (macOS) or apt install tmux (Linux)"
        missing=true
    fi

    if [[ "$SKIP_TMUX_CHECK" != "true" ]] && [[ -z "${TMUX:-}" ]]; then
        # Skip tmux check when running from Claude Code or IDE - the script
        # handles this case by opening a new terminal tab via auto_attach_new_terminal
        if [[ -n "${CLAUDECODE:-}" ]] || [[ -n "${TERM_PROGRAM:-}" && "${TERM_PROGRAM}" == "vscode" ]]; then
            log_info "Running from IDE/Claude Code - will open new terminal tab for tmux"
        else
            log_fail "Not running inside a tmux session"
            log_info "Start tmux first, then run agent-team from within it:"
            log_info "  tmux new -s work"
            log_info "  claude-agentic    # interactive agentic or YOLO mode"
            log_info "Or bypass with: --no-tmux-check or SKIP_TMUX_CHECK=true"
            missing=true
        fi
    fi

    if [[ "$DRY_RUN" != "true" ]]; then
        if ! command -v claude &>/dev/null; then
            log_fail "claude CLI is not available"
            log_info "Install Claude Code: https://docs.anthropic.com/claude-code"
            missing=true
        fi

        if [[ ! -d "$HOME/.claude-agentic" ]]; then
            log_fail "~/.claude-agentic config directory not found"
            log_info "Run setup-claude-links.sh to configure agentic mode"
            missing=true
        fi
    fi

    if [[ "$missing" == "true" ]]; then
        exit $EXIT_NO_PREREQ
    fi
}

build_orchestrator_prompt() {
    local workers="$1"
    local task="$2"
    local session="$3"

    local worker_list=""
    local i
    for ((i=1; i<=workers; i++)); do
        if [[ -n "$worker_list" ]]; then
            worker_list="$worker_list, "
        fi
        worker_list="${worker_list}worker-${i}"
    done

    local prompt
    prompt="You are the team orchestrator for a multi-agent Claude Code team.

Your responsibilities:
1. Read docs/ToDos.md to understand current project tasks and status
2. Break down work into discrete, independent tasks for your workers
3. Create task assignments using TaskCreate and assign to workers ($worker_list)
4. Monitor progress via TaskList and coordinate with SendMessage
5. Update docs/ToDos.md task claims with claimed_by: $session/orchestrator

You have $workers worker(s) available: $worker_list
Distribute work evenly. Avoid assigning tasks with dependencies to run simultaneously.
Start by reading docs/ToDos.md, then create and assign tasks."

    if [[ -n "$task" ]]; then
        prompt="$prompt

TASK: $task"
    else
        prompt="$prompt

Review docs/ToDos.md and assign available pending tasks to your workers."
    fi

    printf '%s' "$prompt"
}

build_worker_prompt() {
    local worker_num="$1"
    local session="$2"

    printf '%s' "You are worker-$worker_num in a multi-agent Claude Code team.

Your responsibilities:
1. Check TaskList for tasks assigned to you by the orchestrator
2. Work on assigned tasks autonomously and thoroughly
3. Create work logs at docs/work-logs/ for each task
4. Mark tasks complete via TaskUpdate when finished
5. Use claimed_by: $session/worker-$worker_num for stigmergic file updates

If no tasks are assigned yet, wait briefly then check TaskList again.
When done with a task, notify the orchestrator via SendMessage and check for more work."
}

launch_agents() {
    local orch_prompt
    orch_prompt=$(build_orchestrator_prompt "$WORKER_COUNT" "$TASK_DESCRIPTION" "$SESSION_NAME")

    local orch_cmd="CLAUDE_CONFIG_DIR=~/.claude-agentic claude --model $ORCHESTRATOR_MODEL --append-system-prompt $(printf '%q' "$orch_prompt")"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN - Agent commands that would be launched:"
        echo ""
        echo "--- Orchestrator (pane 0, model: $ORCHESTRATOR_MODEL) ---"
        echo "$orch_cmd"
        echo ""

        local i
        for ((i=1; i<=WORKER_COUNT; i++)); do
            local worker_prompt
            worker_prompt=$(build_worker_prompt "$i" "$SESSION_NAME")
            local worker_cmd="CLAUDE_CONFIG_DIR=~/.claude-agentic claude --model $WORKER_MODEL --append-system-prompt $(printf '%q' "$worker_prompt")"
            echo "--- Worker $i (pane $((i + 1)), model: $WORKER_MODEL) ---"
            echo "$worker_cmd"
            echo ""
        done
        return 0
    fi

    # Wait for all pane shells to fully initialize (zsh + oh-my-zsh + plugins)
    log_info "Waiting for pane shells to initialize..."
    sleep 3

    # Launch orchestrator in pane 0
    log_info "Launching orchestrator (model: $ORCHESTRATOR_MODEL)..."
    tmux send-keys -t "$SESSION_NAME:0.0" C-c
    sleep 0.3
    tmux send-keys -t "$SESSION_NAME:0.0" "$orch_cmd" C-m

    # Launch workers in panes 2+ (pane 1 is dashboard)
    local i
    for ((i=1; i<=WORKER_COUNT; i++)); do
        sleep 2
        local worker_prompt
        worker_prompt=$(build_worker_prompt "$i" "$SESSION_NAME")
        local worker_cmd="CLAUDE_CONFIG_DIR=~/.claude-agentic claude --model $WORKER_MODEL --append-system-prompt $(printf '%q' "$worker_prompt")"
        local pane_idx=$((i + 1))
        log_info "Launching worker-$i (model: $WORKER_MODEL, pane $pane_idx)..."
        # Clear pane, then send command
        tmux send-keys -t "$SESSION_NAME:0.${pane_idx}" C-c
        sleep 0.3
        tmux send-keys -t "$SESSION_NAME:0.${pane_idx}" "$worker_cmd" C-m
    done
}

create_team() {
    local tmux_args=(
        --layout orchestrator
        --agents "$WORKER_COUNT"
        --session "$SESSION_NAME"
        --detach
    )

    if [[ -n "$WORKSPACE_PATH" ]]; then
        tmux_args+=(--workspace "$WORKSPACE_PATH")
    fi

    if [[ -n "$NO_COLOR" ]]; then
        tmux_args+=(--no-color)
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN - Would create tmux session:"
        echo "  $TMUX_SCRIPT ${tmux_args[*]}"
        echo ""
        launch_agents
        return 0
    fi

    # Create tmux session with orchestrator layout
    log_info "Creating team session..."
    bash "$TMUX_SCRIPT" "${tmux_args[@]}"

    # Disable dashboard if requested
    if [[ "$NO_DASHBOARD" == "true" ]]; then
        log_info "Disabling dashboard pane..."
        tmux send-keys -t "$SESSION_NAME:0.1" C-c
        sleep 0.5
        tmux send-keys -t "$SESSION_NAME:0.1" "clear" C-m
    fi

    # Launch Claude agents in panes
    launch_agents

    log_ok "Team launched: 1 orchestrator + $WORKER_COUNT worker(s)"

    if [[ "$DETACH" != "true" ]]; then
        # Check if running inside Claude Code or another incompatible environment
        if [[ -n "${CLAUDECODE:-}" ]] || [[ -n "${TERM_PROGRAM:-}" && "${TERM_PROGRAM}" == "vscode" ]]; then
            log_info "Detected Claude Code/IDE environment - opening new terminal..."
            if auto_attach_new_terminal "$SESSION_NAME"; then
                log_ok "Agent team is running. Attaching now:"
                echo ""
                log_info "  tmux attach -t $SESSION_NAME"
                echo ""
                log_info "  The session is live with:"
                log_info "  - Orchestrator (left pane, $ORCHESTRATOR_MODEL) - reading ToDos.md and assigning tasks"
                log_info "  - Dashboard (top-right) - real-time status"
                for ((i=1; i<=WORKER_COUNT; i++)); do
                    log_info "  - Worker $i (bottom-right) - awaiting task assignment"
                done
                echo ""
                log_info "  tmux shortcuts:"
                log_info "  - Ctrl-b then arrow keys to switch panes"
                log_info "  - Ctrl-b d to detach (session keeps running)"
                log_info "  - agent-team.sh --attach to reattach later"
                log_info "  - agent-team.sh --kill to stop the team"
            else
                log_warn "Could not auto-attach. Attach manually with:"
                log_info "  tmux attach -t $SESSION_NAME"
            fi
        else
            # Direct attach when not in IDE
            log_info "Attaching to session..."
            tmux attach-session -t "$SESSION_NAME"
        fi
    else
        log_info "Session running in background. Attach with:"
        log_info "  tmux attach -t $SESSION_NAME"
    fi
}

# --- Main ---

main() {
    setup_colors
    parse_args "$@"

    case "$ACTION" in
        create)
            check_prerequisites
            create_team
            ;;
        attach)
            local args=(--attach --session "$SESSION_NAME")
            if [[ -n "$NO_COLOR" ]]; then
                args+=(--no-color)
            fi
            bash "$TMUX_SCRIPT" "${args[@]}"
            ;;
        kill)
            local args=(--kill --session "$SESSION_NAME")
            if [[ -n "$NO_COLOR" ]]; then
                args+=(--no-color)
            fi
            bash "$TMUX_SCRIPT" "${args[@]}"
            ;;
    esac
}

main "$@"
