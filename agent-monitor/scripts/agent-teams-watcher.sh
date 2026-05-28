#!/usr/bin/env bash
#
# agent-teams-watcher.sh - File watcher for stigmergic coordination signals
#
# Monitors docs/ToDos.md, work-logs/, and discoveries/ for changes
# and emits events for the dashboard or desktop notifications.
#
# Usage:
#   agent-teams-watcher.sh [OPTIONS]
#   agent-teams-watcher.sh --workspace /path/to/SA
#
# Options:
#   --workspace PATH   Workspace root to monitor
#   --notify           Send desktop notifications (macOS/Linux)
#   --events-file F    Write events to file (for dashboard consumption)
#   --no-color         Disable colored output
#   -h, --help         Show help
#
# Requires: fswatch (macOS) or inotifywait (Linux)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Options
WORKSPACE_PATH=""
NOTIFY=false
EVENTS_FILE=""
NO_COLOR="${NO_COLOR:-}"

# Colors
COLOR_RESET='' COLOR_GREEN='' COLOR_YELLOW='' COLOR_RED='' COLOR_BLUE='' COLOR_CYAN='' COLOR_DIM=''

setup_colors() {
    if [[ -z "$NO_COLOR" ]] && [[ -t 1 ]]; then
        COLOR_RESET='\033[0m' COLOR_GREEN='\033[0;32m' COLOR_YELLOW='\033[1;33m'
        COLOR_RED='\033[0;31m' COLOR_BLUE='\033[0;34m' COLOR_CYAN='\033[0;36m'
        COLOR_DIM='\033[2m'
    fi
}

show_help() {
    cat <<'EOF'
Usage: agent-teams-watcher.sh [OPTIONS]

Watch stigmergic coordination files for real-time events.

Monitors:
  - docs/ToDos.md: task claim/status changes
  - docs/work-logs/: new entries
  - docs/discoveries/: cross-agent signals

Options:
  --workspace PATH   Workspace root to monitor
  --notify           Desktop notifications on key events
  --events-file F    Append events to file (JSON lines)
  --no-color         Disable colored output
  -h, --help         Show this help

Requirements:
  macOS: fswatch (brew install fswatch)
  Linux: inotifywait (apt install inotify-tools)
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --workspace)
                if [[ $# -lt 2 ]]; then echo "Error: --workspace needs path" >&2; exit 1; fi
                WORKSPACE_PATH="$2"; shift 2
                ;;
            --notify)      NOTIFY=true; shift ;;
            --events-file)
                if [[ $# -lt 2 ]]; then echo "Error: --events-file needs path" >&2; exit 1; fi
                EVENTS_FILE="$2"; shift 2
                ;;
            --no-color)    NO_COLOR=1; setup_colors; shift ;;
            -h|--help)     show_help; exit 0 ;;
            -*)            echo "Error: Unknown option: $1" >&2; exit 1 ;;
            *)             echo "Error: Unexpected: $1" >&2; exit 1 ;;
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

# Send desktop notification
send_notification() {
    local title="$1"
    local message="$2"

    if [[ "$NOTIFY" != "true" ]]; then
        return
    fi

    if [[ "$(uname)" == "Darwin" ]]; then
        osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
    elif command -v notify-send &>/dev/null; then
        notify-send "$title" "$message" 2>/dev/null || true
    fi
}

# Write event to events file (JSON lines)
write_event() {
    local event_type="$1"
    local detail="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Console output
    local color
    case "$event_type" in
        task_claimed)   color="$COLOR_GREEN" ;;
        task_completed) color="$COLOR_CYAN" ;;
        task_blocked)   color="$COLOR_RED" ;;
        work_log)       color="$COLOR_BLUE" ;;
        discovery)      color="$COLOR_YELLOW" ;;
        *)              color="$COLOR_DIM" ;;
    esac

    echo -e "${COLOR_DIM}$timestamp${COLOR_RESET} ${color}[$event_type]${COLOR_RESET} $detail"

    # File output
    if [[ -n "$EVENTS_FILE" ]]; then
        echo "{\"timestamp\":\"$timestamp\",\"type\":\"$event_type\",\"detail\":\"$detail\"}" >> "$EVENTS_FILE"
    fi
}

# Classify a file change into an event type
classify_change() {
    local filepath="$1"
    local fname
    fname=$(basename "$filepath")

    case "$filepath" in
        */ToDos.md)
            write_event "task_change" "ToDos.md modified"
            send_notification "Agent Teams" "Task file updated"
            ;;
        */work-logs/*)
            write_event "work_log" "New/updated: $fname"
            send_notification "Agent Teams" "Work log: $fname"
            ;;
        */discoveries/*)
            write_event "discovery" "New finding: $fname"
            send_notification "Agent Teams" "Discovery: $fname"
            ;;
        *)
            write_event "file_change" "$fname"
            ;;
    esac
}

# Build list of paths to watch
build_watch_paths() {
    local workspace="$1"
    local paths=()

    # Find all relevant directories
    local git_dir
    while IFS= read -r git_dir; do
        local repo_dir
        repo_dir=$(dirname "$git_dir")

        # Watch ToDos.md
        if [[ -f "$repo_dir/docs/ToDos.md" ]]; then
            paths+=("$repo_dir/docs/ToDos.md")
        fi

        # Watch work-logs directory
        if [[ -d "$repo_dir/docs/work-logs" ]]; then
            paths+=("$repo_dir/docs/work-logs")
        fi

        # Watch discoveries directory
        if [[ -d "$repo_dir/docs/discoveries" ]]; then
            paths+=("$repo_dir/docs/discoveries")
        fi
    done < <(find "$workspace" -maxdepth 3 \( -name node_modules -o -name vendor \) -prune -o -type d -name .git -print 2>/dev/null | sort)

    printf '%s\n' "${paths[@]}"
}

# Watch using fswatch (macOS)
watch_fswatch() {
    local workspace="$1"

    local watch_paths
    watch_paths=$(build_watch_paths "$workspace")

    if [[ -z "$watch_paths" ]]; then
        echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} No watchable paths found"
        exit 1
    fi

    echo -e "${COLOR_BLUE}[WATCHER]${COLOR_RESET} Monitoring with fswatch..."
    echo -e "${COLOR_DIM}Paths:${COLOR_RESET}"
    echo "$watch_paths" | while read -r p; do
        echo -e "  ${COLOR_DIM}$p${COLOR_RESET}"
    done
    echo ""

    # shellcheck disable=SC2086
    echo "$watch_paths" | xargs fswatch --event Created --event Updated --event Renamed 2>/dev/null | while read -r changed_file; do
        classify_change "$changed_file"
    done
}

# Watch using inotifywait (Linux)
watch_inotify() {
    local workspace="$1"

    local watch_paths
    watch_paths=$(build_watch_paths "$workspace")

    if [[ -z "$watch_paths" ]]; then
        echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} No watchable paths found"
        exit 1
    fi

    echo -e "${COLOR_BLUE}[WATCHER]${COLOR_RESET} Monitoring with inotifywait..."

    # shellcheck disable=SC2086
    echo "$watch_paths" | xargs inotifywait -m -e create -e modify -e moved_to --format '%w%f' 2>/dev/null | while read -r changed_file; do
        classify_change "$changed_file"
    done
}

# Fallback: poll-based watching
watch_poll() {
    local workspace="$1"

    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} Neither fswatch nor inotifywait found"
    echo -e "${COLOR_BLUE}[WATCHER]${COLOR_RESET} Using polling mode (10s interval)"
    echo -e "${COLOR_DIM}Install fswatch (macOS) or inotify-tools (Linux) for real-time events${COLOR_RESET}"
    echo ""

    # Track file checksums
    local checksum_file
    checksum_file=$(mktemp)
    trap "rm -f '$checksum_file'" EXIT

    while true; do
        local new_checksums
        new_checksums=$(mktemp)

        build_watch_paths "$workspace" | while read -r path; do
            if [[ -f "$path" ]]; then
                md5sum "$path" 2>/dev/null || md5 -q "$path" 2>/dev/null || echo "? $path"
            elif [[ -d "$path" ]]; then
                ls -la "$path" 2>/dev/null | md5sum 2>/dev/null || ls -la "$path" 2>/dev/null | md5 -q 2>/dev/null || echo "? $path"
            fi
        done > "$new_checksums"

        if [[ -s "$checksum_file" ]]; then
            local changes
            changes=$(diff "$checksum_file" "$new_checksums" 2>/dev/null || true)
            if [[ -n "$changes" ]]; then
                write_event "poll_change" "Files changed (poll detection)"
                send_notification "Agent Teams" "Workspace files changed"
            fi
        fi

        cp "$new_checksums" "$checksum_file"
        rm -f "$new_checksums"

        sleep 10
    done
}

# --- Main ---

main() {
    setup_colors
    parse_args "$@"

    local workspace
    workspace=$(detect_workspace)

    echo -e "${COLOR_BOLD}${COLOR_CYAN}Agent Teams File Watcher${COLOR_RESET}"
    echo -e "${COLOR_DIM}Workspace: $workspace${COLOR_RESET}"
    echo ""

    if command -v fswatch &>/dev/null; then
        watch_fswatch "$workspace"
    elif command -v inotifywait &>/dev/null; then
        watch_inotify "$workspace"
    else
        watch_poll "$workspace"
    fi
}

main "$@"
