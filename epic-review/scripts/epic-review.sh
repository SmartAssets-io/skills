#!/usr/bin/env bash
#
# epic-review.sh - Preview and summarize epics for high-level review
#
# This script provides:
# 1. Next epic preview (priority-based selection)
# 2. Specific epic lookup by ID
# 3. List mode for all epics summary
# 4. Validation warnings for task hygiene
#
# Usage:
#   epic-review.sh [EPIC-ID] [--list]
#
# Modes:
#   (no args)     Show next pending epic (priority-based)
#   EPIC-ID      Show specific epic by ID
#   --list        List all epics with summary
#
# Options:
#   --no-color    Disable colored output
#   --help, -h    Show this help message
#
# Dependencies:
#   - jq (required for JSON manipulation)
#   - epic-parser.sh library
#   - bash 4+ for associative arrays
#

set -euo pipefail

# Script location and library path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
EPIC_PARSER="${LIB_DIR}/epic-parser.sh"

# Default configuration
TODOS_FILE="docs/ToDos.md"
NO_COLOR="${NO_COLOR:-}"
OUTPUT_WIDTH=64

# Exit codes
EXIT_SUCCESS=0
EXIT_NOT_FOUND=1
EXIT_NO_EPICS=2
EXIT_INVALID_ARGS=3

# Colors (ANSI escape codes)
if [[ -z "$NO_COLOR" ]] && [[ -t 1 ]]; then
    COLOR_RESET='\033[0m'
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[0;33m'
    COLOR_RED='\033[0;31m'
    COLOR_BLUE='\033[0;34m'
    COLOR_BOLD='\033[1m'
else
    COLOR_RESET=''
    COLOR_GREEN=''
    COLOR_YELLOW=''
    COLOR_RED=''
    COLOR_BLUE=''
    COLOR_BOLD=''
fi

# Status symbols (ASCII-safe)
SYMBOL_PENDING='o'
SYMBOL_IN_PROGRESS='>'
SYMBOL_BLOCKED='x'
SYMBOL_COMPLETE='*'

#
# Show help message
#
show_help() {
    cat <<EOF
epic-review.sh - Preview and summarize epics for high-level review

Usage: $(basename "$0") [EPIC-ID] [--list] [OPTIONS]

Modes:
  (no arguments)     Show next pending epic (priority-based selection)
  EPIC-ID           Show specific epic by ID (e.g., EPIC-008)
  --list             List all epics with compact summary

Options:
  --no-color         Disable colored output
  --help, -h         Show this help message

Examples:
  $(basename "$0")                    # Show next pending epic
  $(basename "$0") EPIC-008          # Show specific epic
  $(basename "$0") --list             # List all epics

Exit Codes:
  0    Success
  1    Epic not found
  2    No epics available
  3    Invalid arguments

Environment:
  NO_COLOR           Set to disable colors (respects standard)
  TODOS_FILE         Override default docs/ToDos.md path

EOF
}

#
# Source the epic parser library
#
load_epic_parser() {
    if [[ ! -f "$EPIC_PARSER" ]]; then
        echo "Error: epic-parser.sh not found at $EPIC_PARSER" >&2
        exit $EXIT_INVALID_ARGS
    fi
    # shellcheck source=lib/epic-parser.sh
    source "$EPIC_PARSER"
}

#
# Get status symbol for a task status
#
get_status_symbol() {
    local status="$1"
    case "$status" in
        pending)     echo "$SYMBOL_PENDING" ;;
        in_progress) echo "$SYMBOL_IN_PROGRESS" ;;
        blocked)     echo "$SYMBOL_BLOCKED" ;;
        complete)    echo "$SYMBOL_COMPLETE" ;;
        *)           echo "?" ;;
    esac
}

#
# Get color for a status
#
get_status_color() {
    local status="$1"
    case "$status" in
        complete)    echo "$COLOR_GREEN" ;;
        in_progress) echo "$COLOR_YELLOW" ;;
        blocked)     echo "$COLOR_RED" ;;
        pending)     echo "$COLOR_RESET" ;;
        *)           echo "$COLOR_RESET" ;;
    esac
}

#
# Draw a box line (top, middle, or bottom)
#
draw_line() {
    local type="$1"  # top, middle, bottom
    local width="${2:-$OUTPUT_WIDTH}"

    case "$type" in
        top)
            printf "+%s+\n" "$(printf '=%.0s' $(seq 1 $((width-2))))"
            ;;
        middle)
            printf "+%s+\n" "$(printf -- '-%.0s' $(seq 1 $((width-2))))"
            ;;
        bottom)
            printf "+%s+\n" "$(printf '=%.0s' $(seq 1 $((width-2))))"
            ;;
    esac
}

#
# Draw a content line with borders
#
draw_content() {
    local content="$1"
    local width="${2:-$OUTPUT_WIDTH}"
    local inner_width=$((width - 4))  # Account for "| " and " |"

    # Truncate if too long
    if [[ ${#content} -gt $inner_width ]]; then
        content="${content:0:$((inner_width-3))}..."
    fi

    # Pad with spaces
    printf "| %-${inner_width}s |\n" "$content"
}

#
# Draw empty line in box
#
draw_empty() {
    local width="${2:-$OUTPUT_WIDTH}"
    draw_content "" "$width"
}

#
# Format a single epic for display
#
format_epic() {
    local epic_json="$1"

    # Extract epic fields
    local epic_id title status priority
    epic_id=$(echo "$epic_json" | jq -r '.epic_id')
    title=$(echo "$epic_json" | jq -r '.title')
    status=$(echo "$epic_json" | jq -r '.status // "pending"')
    priority=$(echo "$epic_json" | jq -r '.priority // "p2"')

    # Get task metrics
    local total complete in_progress blocked pending percent
    total=$(echo "$epic_json" | jq '.tasks | length')
    complete=$(echo "$epic_json" | jq '[.tasks[] | select(.status == "complete")] | length')
    in_progress=$(echo "$epic_json" | jq '[.tasks[] | select(.status == "in_progress")] | length')
    blocked=$(echo "$epic_json" | jq '[.tasks[] | select(.status == "blocked")] | length')
    pending=$(echo "$epic_json" | jq '[.tasks[] | select(.status == "pending")] | length')

    if [[ $total -gt 0 ]]; then
        percent=$((complete * 100 / total))
    else
        percent=0
    fi

    # Determine displayed status. Prefer the authored .status field when present
    # (source of truth — someone set it deliberately, e.g. in_progress when they started
    # the epic even though no task is in_progress yet). Fall back to deriving from task
    # counts only when authored status is missing or "pending" but tasks tell a different
    # story (e.g. all complete but YAML not yet flipped). This matches the eligibility
    # logic in lib/epic-parser.sh get_eligible_epics which also treats "any complete
    # tasks but not all" as in_progress.
    local derived_status
    if [[ $complete -eq $total ]] && [[ $total -gt 0 ]]; then
        derived_status="complete"
    elif [[ "$status" == "in_progress" ]]; then
        derived_status="in_progress"
    elif [[ "$status" == "blocked" ]]; then
        derived_status="blocked"
    elif [[ $in_progress -gt 0 ]]; then
        derived_status="in_progress"
    elif [[ $complete -gt 0 ]]; then
        derived_status="in_progress"
    elif [[ $blocked -gt 0 ]]; then
        derived_status="blocked"
    else
        derived_status="pending"
    fi

    # Draw header
    echo -e "${COLOR_BLUE}"
    draw_line "top"
    draw_content "${epic_id}: ${title}"
    draw_line "middle"
    echo -e "${COLOR_RESET}"

    # Status and priority line
    local status_color
    status_color=$(get_status_color "$derived_status")
    draw_content "Status: ${status_color}${derived_status}${COLOR_RESET}                Priority: ${priority}"
    draw_content "Tasks:  ${complete}/${total} complete (${percent}%)"
    draw_empty

    # Breakdown section
    draw_content "Breakdown:"
    draw_content "  ${SYMBOL_PENDING} pending:     ${pending}"
    draw_content "  ${SYMBOL_IN_PROGRESS} in_progress: ${in_progress}"
    draw_content "  ${SYMBOL_BLOCKED} blocked:     ${blocked}"
    draw_content "  ${SYMBOL_COMPLETE} complete:    ${complete}"

    # Task list
    draw_line "middle"
    draw_content "Tasks:"

    # Display each task
    echo "$epic_json" | jq -r '.tasks[] | "\(.status)|\(.id)|\(.title)"' | while IFS='|' read -r task_status task_id task_title; do
        local symbol
        symbol=$(get_status_symbol "$task_status")
        local color
        color=$(get_status_color "$task_status")

        # Truncate title if needed
        local max_title_len=40
        if [[ ${#task_title} -gt $max_title_len ]]; then
            task_title="${task_title:0:$((max_title_len-3))}..."
        fi

        draw_content "  ${color}${symbol}${COLOR_RESET} ${task_id}  ${task_title}"
    done

    echo -e "${COLOR_BLUE}"
    draw_line "bottom"
    echo -e "${COLOR_RESET}"
}

#
# Format epic list (compact summary)
#
format_epic_list() {
    local epics_json="$1"

    echo -e "${COLOR_BLUE}"
    draw_line "top"
    draw_content "Epic Summary"
    draw_line "middle"
    echo -e "${COLOR_RESET}"

    # Header row
    printf "| %-12s | %-11s | %-8s | %-18s |\n" "ID" "Status" "Priority" "Progress"
    printf "|%s|%s|%s|%s|\n" \
        "$(printf -- '-%.0s' $(seq 1 14))" \
        "$(printf -- '-%.0s' $(seq 1 13))" \
        "$(printf -- '-%.0s' $(seq 1 10))" \
        "$(printf -- '-%.0s' $(seq 1 20))"

    # Data rows
    echo "$epics_json" | jq -r '.[] |
        "\(.epic_id)|\(.status // "pending")|\(.priority // "p2")|\(.task_count)|\(.complete)"' | \
    while IFS='|' read -r eid status priority total complete; do
        local percent=0
        if [[ $total -gt 0 ]]; then
            percent=$((complete * 100 / total))
        fi
        local color
        color=$(get_status_color "$status")
        printf "| %-12s | ${color}%-11s${COLOR_RESET} | %-8s | %d/%d (%d%%)%*s |\n" \
            "$eid" "$status" "$priority" "$complete" "$total" "$percent" \
            $((10 - ${#complete} - ${#total} - ${#percent})) ""
    done

    echo -e "${COLOR_BLUE}"
    draw_line "bottom"
    echo -e "${COLOR_RESET}"

    # Summary line. Counts are mutually exclusive and sum to total: an epic is "complete"
    # if either its authored .status is "complete" OR all its tasks are complete (covers
    # the pre-/epic-hygiene window where the YAML status hasn't yet been flipped). All
    # other epics are tallied by their authored .status field. Earlier versions of this
    # block tested .in_progress / .blocked which are TASK COUNTS, not epic status, and
    # produced contradictory totals.
    local total_epics complete_epics in_progress_epics pending_epics blocked_epics
    total_epics=$(echo "$epics_json" | jq 'length')
    complete_epics=$(echo "$epics_json" | jq '[.[] | select((.status // "pending") == "complete" or (.complete == .task_count and .task_count > 0))] | length')
    in_progress_epics=$(echo "$epics_json" | jq '[.[] | select((.status // "pending") == "in_progress" and ((.complete < .task_count) or .task_count == 0))] | length')
    blocked_epics=$(echo "$epics_json" | jq '[.[] | select((.status // "pending") == "blocked" and ((.complete < .task_count) or .task_count == 0))] | length')
    pending_epics=$(echo "$epics_json" | jq '[.[] | select((.status // "pending") == "pending" and ((.complete < .task_count) or .task_count == 0))] | length')

    echo ""
    echo "Total: ${total_epics} epics (${complete_epics} complete, ${in_progress_epics} in_progress, ${pending_epics} pending, ${blocked_epics} blocked)"
}

#
# Display validation warnings
#
display_warnings() {
    local validation_json="$1"

    local warning_count
    warning_count=$(echo "$validation_json" | jq '.warnings | length')

    if [[ $warning_count -gt 0 ]]; then
        echo ""
        echo -e "${COLOR_YELLOW}[!] Warnings:${COLOR_RESET}"
        echo "$validation_json" | jq -r '.warnings[] | "  - \(.type): \(.task_id // .epic_id // "unknown")"'
        echo ""
        echo "Found ${warning_count} warnings. Run '/epic-hygiene' to fix issues."
    else
        echo ""
        echo -e "${COLOR_GREEN}[!] Warnings:${COLOR_RESET}"
        echo "  - None"
    fi
}

#
# Mode: Show next pending epic
#
mode_next_epic() {
    local epics
    epics=$(get_eligible_epics "$TODOS_FILE")

    local count
    count=$(echo "$epics" | jq 'length')

    if [[ $count -eq 0 ]]; then
        echo "No pending epics found. All epics may be complete or blocked."
        exit $EXIT_NO_EPICS
    fi

    # Get first (highest priority) epic
    local next_epic_id
    next_epic_id=$(echo "$epics" | jq -r '.[0].epic_id')

    local epic
    epic=$(get_epic "$next_epic_id" "$TODOS_FILE")

    format_epic "$epic"

    # Show validation warnings
    local validation
    validation=$(validate_epics "$TODOS_FILE")
    display_warnings "$validation"
}

#
# Mode: Show specific epic by ID
#
mode_specific_epic() {
    local epic_id="$1"

    local epic
    epic=$(get_epic "$epic_id" "$TODOS_FILE")

    if [[ -z "$epic" ]] || [[ "$epic" == "null" ]]; then
        echo "Error: Epic ${epic_id} not found in ${TODOS_FILE}" >&2
        exit $EXIT_NOT_FOUND
    fi

    format_epic "$epic"

    # Show validation warnings
    local validation
    validation=$(validate_epics "$TODOS_FILE")
    display_warnings "$validation"
}

#
# Mode: List all epics
#
mode_list_epics() {
    local epics
    epics=$(list_epics "$TODOS_FILE")

    local count
    count=$(echo "$epics" | jq 'length')

    if [[ $count -eq 0 ]]; then
        echo "No epics found in ${TODOS_FILE}"
        exit $EXIT_NO_EPICS
    fi

    format_epic_list "$epics"
}

#
# Main entry point
#
main() {
    local mode="next"
    local epic_id=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit $EXIT_SUCCESS
                ;;
            --list)
                mode="list"
                shift
                ;;
            --no-color)
                NO_COLOR=1
                COLOR_RESET=''
                COLOR_GREEN=''
                COLOR_YELLOW=''
                COLOR_RED=''
                COLOR_BLUE=''
                COLOR_BOLD=''
                shift
                ;;
            EPIC-*)
                mode="specific"
                epic_id="$1"
                shift
                ;;
            *)
                echo "Unknown argument: $1" >&2
                echo "Run '$(basename "$0") --help' for usage" >&2
                exit $EXIT_INVALID_ARGS
                ;;
        esac
    done

    # Load the epic parser library
    load_epic_parser

    # Check if ToDos.md exists
    if [[ ! -f "$TODOS_FILE" ]]; then
        echo "Error: ${TODOS_FILE} not found" >&2
        exit $EXIT_NOT_FOUND
    fi

    # Execute the appropriate mode
    case "$mode" in
        next)
            mode_next_epic
            ;;
        specific)
            mode_specific_epic "$epic_id"
            ;;
        list)
            mode_list_epics
            ;;
    esac
}

# Run main if script is executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
