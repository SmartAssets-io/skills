#!/usr/bin/env bash
#
# epoch-review.sh - Preview and summarize epochs for high-level review
#
# This script provides:
# 1. Next epoch preview (priority-based selection)
# 2. Specific epoch lookup by ID
# 3. List mode for all epochs summary
# 4. Validation warnings for task hygiene
#
# Usage:
#   epoch-review.sh [EPOCH-ID] [--list]
#
# Modes:
#   (no args)     Show next pending epoch (priority-based)
#   EPOCH-ID      Show specific epoch by ID
#   --list        List all epochs with summary
#
# Options:
#   --no-color    Disable colored output
#   --help, -h    Show this help message
#
# Dependencies:
#   - jq (required for JSON manipulation)
#   - epoch-parser.sh library
#   - bash 4+ for associative arrays
#

set -euo pipefail

# Script location and library path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
EPOCH_PARSER="${LIB_DIR}/epoch-parser.sh"

# Default configuration
TODOS_FILE="docs/ToDos.md"
NO_COLOR="${NO_COLOR:-}"
OUTPUT_WIDTH=64

# Exit codes
EXIT_SUCCESS=0
EXIT_NOT_FOUND=1
EXIT_NO_EPOCHS=2
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
epoch-review.sh - Preview and summarize epochs for high-level review

Usage: $(basename "$0") [EPOCH-ID] [--list] [OPTIONS]

Modes:
  (no arguments)     Show next pending epoch (priority-based selection)
  EPOCH-ID           Show specific epoch by ID (e.g., EPOCH-008)
  --list             List all epochs with compact summary

Options:
  --no-color         Disable colored output
  --help, -h         Show this help message

Examples:
  $(basename "$0")                    # Show next pending epoch
  $(basename "$0") EPOCH-008          # Show specific epoch
  $(basename "$0") --list             # List all epochs

Exit Codes:
  0    Success
  1    Epoch not found
  2    No epochs available
  3    Invalid arguments

Environment:
  NO_COLOR           Set to disable colors (respects standard)
  TODOS_FILE         Override default docs/ToDos.md path

EOF
}

#
# Source the epoch parser library
#
load_epoch_parser() {
    if [[ ! -f "$EPOCH_PARSER" ]]; then
        echo "Error: epoch-parser.sh not found at $EPOCH_PARSER" >&2
        exit $EXIT_INVALID_ARGS
    fi
    # shellcheck source=lib/epoch-parser.sh
    source "$EPOCH_PARSER"
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
# Format a single epoch for display
#
format_epoch() {
    local epoch_json="$1"

    # Extract epoch fields
    local epoch_id title status priority
    epoch_id=$(echo "$epoch_json" | jq -r '.epoch_id')
    title=$(echo "$epoch_json" | jq -r '.title')
    status=$(echo "$epoch_json" | jq -r '.status // "pending"')
    priority=$(echo "$epoch_json" | jq -r '.priority // "p2"')

    # Get task metrics
    local total complete in_progress blocked pending percent
    total=$(echo "$epoch_json" | jq '.tasks | length')
    complete=$(echo "$epoch_json" | jq '[.tasks[] | select(.status == "complete")] | length')
    in_progress=$(echo "$epoch_json" | jq '[.tasks[] | select(.status == "in_progress")] | length')
    blocked=$(echo "$epoch_json" | jq '[.tasks[] | select(.status == "blocked")] | length')
    pending=$(echo "$epoch_json" | jq '[.tasks[] | select(.status == "pending")] | length')

    if [[ $total -gt 0 ]]; then
        percent=$((complete * 100 / total))
    else
        percent=0
    fi

    # Derive status if needed
    local derived_status
    if [[ $complete -eq $total ]] && [[ $total -gt 0 ]]; then
        derived_status="complete"
    elif [[ $in_progress -gt 0 ]]; then
        derived_status="in_progress"
    elif [[ $blocked -gt 0 ]]; then
        derived_status="blocked"
    else
        derived_status="pending"
    fi

    # Draw header
    echo -e "${COLOR_BLUE}"
    draw_line "top"
    draw_content "${epoch_id}: ${title}"
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
    echo "$epoch_json" | jq -r '.tasks[] | "\(.status)|\(.id)|\(.title)"' | while IFS='|' read -r task_status task_id task_title; do
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
# Format epoch list (compact summary)
#
format_epoch_list() {
    local epochs_json="$1"

    echo -e "${COLOR_BLUE}"
    draw_line "top"
    draw_content "Epoch Summary"
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
    echo "$epochs_json" | jq -r '.[] |
        "\(.epoch_id)|\(.status // "pending")|\(.priority // "p2")|\(.task_count)|\(.complete)"' | \
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

    # Summary line
    local total_epochs complete_epochs in_progress_epochs pending_epochs blocked_epochs
    total_epochs=$(echo "$epochs_json" | jq 'length')
    complete_epochs=$(echo "$epochs_json" | jq '[.[] | select(.status == "complete" or (.complete == .task_count and .task_count > 0))] | length')
    in_progress_epochs=$(echo "$epochs_json" | jq '[.[] | select(.in_progress > 0)] | length')
    blocked_epochs=$(echo "$epochs_json" | jq '[.[] | select(.blocked > 0 and .in_progress == 0)] | length')
    pending_epochs=$(echo "$epochs_json" | jq '[.[] | select(.status == "pending" and .complete == 0 and .in_progress == 0 and .blocked == 0)] | length')

    echo ""
    echo "Total: ${total_epochs} epochs (${complete_epochs} complete, ${in_progress_epochs} in_progress, ${pending_epochs} pending, ${blocked_epochs} blocked)"
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
        echo "$validation_json" | jq -r '.warnings[] | "  - \(.type): \(.task_id // .epoch_id // "unknown")"'
        echo ""
        echo "Found ${warning_count} warnings. Run '/epoch-hygiene' to fix issues."
    else
        echo ""
        echo -e "${COLOR_GREEN}[!] Warnings:${COLOR_RESET}"
        echo "  - None"
    fi
}

#
# Mode: Show next pending epoch
#
mode_next_epoch() {
    local epochs
    epochs=$(get_eligible_epochs "$TODOS_FILE")

    local count
    count=$(echo "$epochs" | jq 'length')

    if [[ $count -eq 0 ]]; then
        echo "No pending epochs found. All epochs may be complete or blocked."
        exit $EXIT_NO_EPOCHS
    fi

    # Get first (highest priority) epoch
    local next_epoch_id
    next_epoch_id=$(echo "$epochs" | jq -r '.[0].epoch_id')

    local epoch
    epoch=$(get_epoch "$next_epoch_id" "$TODOS_FILE")

    format_epoch "$epoch"

    # Show validation warnings
    local validation
    validation=$(validate_epochs "$TODOS_FILE")
    display_warnings "$validation"
}

#
# Mode: Show specific epoch by ID
#
mode_specific_epoch() {
    local epoch_id="$1"

    local epoch
    epoch=$(get_epoch "$epoch_id" "$TODOS_FILE")

    if [[ -z "$epoch" ]] || [[ "$epoch" == "null" ]]; then
        echo "Error: Epoch ${epoch_id} not found in ${TODOS_FILE}" >&2
        exit $EXIT_NOT_FOUND
    fi

    format_epoch "$epoch"

    # Show validation warnings
    local validation
    validation=$(validate_epochs "$TODOS_FILE")
    display_warnings "$validation"
}

#
# Mode: List all epochs
#
mode_list_epochs() {
    local epochs
    epochs=$(list_epochs "$TODOS_FILE")

    local count
    count=$(echo "$epochs" | jq 'length')

    if [[ $count -eq 0 ]]; then
        echo "No epochs found in ${TODOS_FILE}"
        exit $EXIT_NO_EPOCHS
    fi

    format_epoch_list "$epochs"
}

#
# Main entry point
#
main() {
    local mode="next"
    local epoch_id=""

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
            EPOCH-*)
                mode="specific"
                epoch_id="$1"
                shift
                ;;
            *)
                echo "Unknown argument: $1" >&2
                echo "Run '$(basename "$0") --help' for usage" >&2
                exit $EXIT_INVALID_ARGS
                ;;
        esac
    done

    # Load the epoch parser library
    load_epoch_parser

    # Check if ToDos.md exists
    if [[ ! -f "$TODOS_FILE" ]]; then
        echo "Error: ${TODOS_FILE} not found" >&2
        exit $EXIT_NOT_FOUND
    fi

    # Execute the appropriate mode
    case "$mode" in
        next)
            mode_next_epoch
            ;;
        specific)
            mode_specific_epoch "$epoch_id"
            ;;
        list)
            mode_list_epochs
            ;;
    esac
}

# Run main if script is executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
