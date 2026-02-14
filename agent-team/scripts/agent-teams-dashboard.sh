#!/usr/bin/env bash
#
# agent-teams-dashboard.sh - Real-time status dashboard for agent teams
#
# Displays task status, agent claims, and coordination signals from
# stigmergic files. Designed to run in a tmux pane with --watch mode.
#
# Usage:
#   agent-teams-dashboard.sh [OPTIONS]
#   agent-teams-dashboard.sh --workspace /path/to/SA --watch
#
# Options:
#   --workspace PATH   Workspace root (default: auto-detect)
#   --watch            Refresh continuously (every 5s)
#   --interval N       Refresh interval in seconds (default: 5)
#   --compact          Compact output (fewer lines)
#   --no-color         Disable colored output
#   -h, --help         Show help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Options
WORKSPACE_PATH=""
WATCH_MODE=false
INTERVAL=5
COMPACT=false
NO_COLOR="${NO_COLOR:-}"

# Colors
COLOR_RESET='' COLOR_GREEN='' COLOR_YELLOW='' COLOR_RED=''
COLOR_BLUE='' COLOR_CYAN='' COLOR_BOLD='' COLOR_DIM=''

setup_colors() {
    if [[ -z "$NO_COLOR" ]] && [[ -t 1 ]]; then
        COLOR_RESET='\033[0m' COLOR_GREEN='\033[0;32m' COLOR_YELLOW='\033[1;33m'
        COLOR_RED='\033[0;31m' COLOR_BLUE='\033[0;34m' COLOR_CYAN='\033[0;36m'
        COLOR_BOLD='\033[1m' COLOR_DIM='\033[2m'
    fi
}

show_help() {
    cat <<'EOF'
Usage: agent-teams-dashboard.sh [OPTIONS]

Real-time status dashboard for multi-agent coding sessions.

Displays:
  - Current epoch and task progress
  - Agent claims and active work
  - Recent work log activity
  - Branch and worktree state
  - Recent discoveries

Options:
  --workspace PATH   Workspace root to monitor
  --watch            Continuous refresh mode
  --interval N       Refresh interval in seconds (default: 5)
  --compact          Compact output mode
  --no-color         Disable colored output
  -h, --help         Show this help
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --workspace)
                if [[ $# -lt 2 ]]; then echo "Error: --workspace needs path" >&2; exit 1; fi
                WORKSPACE_PATH="$2"; shift 2
                ;;
            --watch)    WATCH_MODE=true; shift ;;
            --interval)
                if [[ $# -lt 2 ]]; then echo "Error: --interval needs number" >&2; exit 1; fi
                INTERVAL="$2"; shift 2
                ;;
            --compact)  COMPACT=true; shift ;;
            --no-color) NO_COLOR=1; setup_colors; shift ;;
            -h|--help)  show_help; exit 0 ;;
            -*)         echo "Error: Unknown option: $1" >&2; exit 1 ;;
            *)          echo "Error: Unexpected: $1" >&2; exit 1 ;;
        esac
    done
}

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

# py_yaml helper for parsing YAML (handles both CI and local)
py_yaml() {
    python3 -c "$1" 2>/dev/null || python3 -c "
import subprocess, sys
subprocess.check_call([sys.executable, '-m', 'pip', 'install', '-q', 'pyyaml'], stderr=subprocess.DEVNULL)
$1" 2>/dev/null || echo ""
}

# --- Dashboard sections ---

render_header() {
    local workspace="$1"
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${COLOR_BOLD}${COLOR_CYAN}=====================================================${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_CYAN}  AGENT TEAMS DASHBOARD${COLOR_RESET}  ${COLOR_DIM}$now${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_CYAN}=====================================================${COLOR_RESET}"
    echo -e "  ${COLOR_DIM}Workspace: $(basename "$workspace")${COLOR_RESET}"
    echo ""
}

render_task_progress() {
    local workspace="$1"

    echo -e "${COLOR_BOLD}  TASK PROGRESS${COLOR_RESET}"
    echo -e "  ${COLOR_DIM}---------------------------------------------${COLOR_RESET}"

    # Find ToDos.md files
    local todos_file=""
    for candidate in "$workspace/top-level-gitlab-profile/docs/ToDos.md" \
                     "$workspace/docs/ToDos.md" \
                     "$PROJECT_ROOT/docs/ToDos.md"; do
        if [[ -f "$candidate" ]]; then
            todos_file="$candidate"
            break
        fi
    done

    if [[ -z "$todos_file" ]]; then
        echo -e "  ${COLOR_DIM}(no ToDos.md found)${COLOR_RESET}"
        echo ""
        return
    fi

    # Parse epoch statuses using awk (portable: BSD awk + GNU awk)
    local epoch_data
    epoch_data=$(awk '
        /epoch_id:/ { epoch_id = $2 }
        /title:/ { sub(/.*title: */, ""); title = $0 }
        /status:/ {
            if (epoch_id != "") {
                status = $2
                print epoch_id "|" title "|" status
                epoch_id = ""
            }
        }
    ' "$todos_file" 2>/dev/null || true)

    if [[ -z "$epoch_data" ]]; then
        echo -e "  ${COLOR_DIM}(no epochs found)${COLOR_RESET}"
        echo ""
        return
    fi

    while IFS='|' read -r eid etitle estatus; do
        local status_icon status_color
        case "$estatus" in
            complete)     status_icon="*"; status_color="$COLOR_GREEN" ;;
            in_progress)  status_icon=">"; status_color="$COLOR_YELLOW" ;;
            pending)      status_icon="o"; status_color="$COLOR_DIM" ;;
            blocked)      status_icon="x"; status_color="$COLOR_RED" ;;
            *)            status_icon="?"; status_color="$COLOR_DIM" ;;
        esac

        # Count tasks per epoch (portable: avoid grep -c || echo double-output)
        local task_total task_done
        task_total=$(grep -c "id: ${eid/EPOCH-/TASK-}" "$todos_file" 2>/dev/null) || task_total=0
        task_done=$(awk -v prefix="${eid/EPOCH-/TASK-}" '
            /id:/ { if (index($0, prefix)) found=1 }
            found && /status: complete/ { count++; found=0 }
            found && /status:/ { if (!/status: complete/) found=0 }
            END { print count+0 }
        ' "$todos_file" 2>/dev/null) || task_done=0

        printf "  %b%s%b %-12s %-35s %b%d/%d%b\n" \
            "$status_color" "$status_icon" "$COLOR_RESET" \
            "$eid" "$etitle" \
            "$status_color" "$task_done" "$task_total" "$COLOR_RESET"
    done <<< "$epoch_data"

    echo ""
}

render_active_agents() {
    local workspace="$1"

    echo -e "${COLOR_BOLD}  ACTIVE AGENTS${COLOR_RESET}"
    echo -e "  ${COLOR_DIM}---------------------------------------------${COLOR_RESET}"

    # Find active claims in ToDos.md
    local todos_file=""
    for candidate in "$workspace/top-level-gitlab-profile/docs/ToDos.md" \
                     "$workspace/docs/ToDos.md" \
                     "$PROJECT_ROOT/docs/ToDos.md"; do
        if [[ -f "$candidate" ]]; then
            todos_file="$candidate"
            break
        fi
    done

    if [[ -z "$todos_file" ]]; then
        echo -e "  ${COLOR_DIM}(no ToDos.md found)${COLOR_RESET}"
        echo ""
        return
    fi

    local claims
    claims=$(awk '
        /^  - id:/ { task_id = $3; active = 0 }
        /title:/ { if (task_id != "") { sub(/.*title: *"?/, ""); sub(/"$/, ""); title = $0 } }
        /status: in_progress/ { if (task_id != "") active = 1 }
        /claimed_by:/ {
            if (active) {
                sub(/.*claimed_by: */, "")
                print task_id "|" $0 "|" title
                active = 0; task_id = ""
            }
        }
    ' "$todos_file" 2>/dev/null || true)

    if [[ -z "$claims" ]]; then
        echo -e "  ${COLOR_DIM}(no active claims)${COLOR_RESET}"
    else
        while IFS='|' read -r tid agent title; do
            printf "  ${COLOR_GREEN}>>${COLOR_RESET} %-14s ${COLOR_CYAN}%-25s${COLOR_RESET} %s\n" \
                "$tid" "$agent" "$title"
        done <<< "$claims"
    fi

    echo ""
}

render_recent_activity() {
    local workspace="$1"

    echo -e "${COLOR_BOLD}  RECENT ACTIVITY${COLOR_RESET}"
    echo -e "  ${COLOR_DIM}---------------------------------------------${COLOR_RESET}"

    # Check work logs
    local work_log_dirs=()
    for candidate in "$workspace/top-level-gitlab-profile/docs/work-logs" \
                     "$workspace/docs/work-logs" \
                     "$PROJECT_ROOT/docs/work-logs"; do
        if [[ -d "$candidate" ]]; then
            work_log_dirs+=("$candidate")
        fi
    done

    local found_logs=0
    for log_dir in "${work_log_dirs[@]}"; do
        # Show last 5 work logs by modification time
        local log_file
        while IFS= read -r log_file; do
            [[ ! -f "$log_file" ]] && continue
            found_logs=$((found_logs + 1))
            if [[ $found_logs -le 5 ]]; then
                local fname
                fname=$(basename "$log_file")
                local mod_time
                mod_time=$(stat -f '%Sm' -t '%H:%M' "$log_file" 2>/dev/null || stat -c '%y' "$log_file" 2>/dev/null | cut -d' ' -f2 | cut -d: -f1,2 || echo "??:??")
                printf "  ${COLOR_DIM}%s${COLOR_RESET}  %s\n" "$mod_time" "$fname"
            fi
        done < <(ls -t "$log_dir"/*.md 2>/dev/null | head -5)
    done

    if [[ $found_logs -eq 0 ]]; then
        echo -e "  ${COLOR_DIM}(no recent work logs)${COLOR_RESET}"
    fi

    # Check discoveries
    local discovery_dirs=()
    for candidate in "$workspace/top-level-gitlab-profile/docs/discoveries" \
                     "$workspace/docs/discoveries" \
                     "$PROJECT_ROOT/docs/discoveries"; do
        if [[ -d "$candidate" ]]; then
            discovery_dirs+=("$candidate")
        fi
    done

    local found_disc=0
    for disc_dir in "${discovery_dirs[@]}"; do
        local disc_file
        while IFS= read -r disc_file; do
            [[ ! -f "$disc_file" ]] && continue
            found_disc=$((found_disc + 1))
            if [[ $found_disc -le 3 ]]; then
                local fname
                fname=$(basename "$disc_file")
                printf "  ${COLOR_YELLOW}!${COLOR_RESET}  %s\n" "$fname"
            fi
        done < <(ls -t "$disc_dir"/*.md 2>/dev/null | head -3)
    done

    echo ""
}

render_branch_state() {
    local workspace="$1"

    echo -e "${COLOR_BOLD}  BRANCH STATE${COLOR_RESET}"
    echo -e "  ${COLOR_DIM}---------------------------------------------${COLOR_RESET}"

    local found=0
    local git_dir
    while IFS= read -r git_dir; do
        local repo_dir
        repo_dir=$(dirname "$git_dir")
        local repo_name
        repo_name=$(basename "$repo_dir")
        local branch
        branch=$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "???")
        local dirty=""
        if [[ -n "$(git -C "$repo_dir" status --porcelain 2>/dev/null | head -1)" ]]; then
            dirty="${COLOR_YELLOW}*${COLOR_RESET}"
        fi

        # Check if worktree
        local wt_marker=""
        if [[ -f "$repo_dir/.git" ]]; then
            wt_marker="${COLOR_CYAN}[wt]${COLOR_RESET}"
        fi

        printf "  %-25s %-15s %b%b\n" "$repo_name" "$branch" "$dirty" "$wt_marker"
        found=$((found + 1))

        if [[ "$COMPACT" == "true" ]] && [[ $found -ge 10 ]]; then
            echo -e "  ${COLOR_DIM}... and more${COLOR_RESET}"
            break
        fi
    done < <(find "$workspace" -maxdepth 3 \( -name node_modules -o -name vendor \) -prune -o -type d -name .git -print 2>/dev/null | sort)

    if [[ $found -eq 0 ]]; then
        echo -e "  ${COLOR_DIM}(no repos found)${COLOR_RESET}"
    fi

    echo ""
}

render_footer() {
    echo -e "  ${COLOR_DIM}Press Ctrl-C to stop | Refresh: ${INTERVAL}s${COLOR_RESET}"
    echo -e "${COLOR_CYAN}=====================================================${COLOR_RESET}"
}

# --- Main render ---

render_dashboard() {
    local workspace="$1"

    if [[ "$WATCH_MODE" == "true" ]]; then
        clear
    fi

    render_header "$workspace"
    render_task_progress "$workspace"
    render_active_agents "$workspace"

    if [[ "$COMPACT" != "true" ]]; then
        render_recent_activity "$workspace"
    fi

    render_branch_state "$workspace"

    if [[ "$WATCH_MODE" == "true" ]]; then
        render_footer
    fi
}

# --- Main ---

main() {
    setup_colors
    parse_args "$@"

    local workspace
    workspace=$(detect_workspace)

    if [[ "$WATCH_MODE" == "true" ]]; then
        while true; do
            render_dashboard "$workspace"
            sleep "$INTERVAL"
        done
    else
        render_dashboard "$workspace"
    fi
}

main "$@"
