#!/usr/bin/env bash
#
# story-manager.sh - Manage user stories via command line
#
# This script provides:
# 1. Interactive story creation wizard (/story create)
# 2. Bi-directional story-epoch linking (/story link)
# 3. Orphan detection and sync report (/story sync)
# 4. Story status and progress review (/story review)
#
# Usage:
#   story-manager.sh <subcommand> [arguments]
#
# Subcommands:
#   create              Interactive wizard for new story
#   link US-XXX EPOCH-YYY   Link story to epoch bidirectionally
#   sync                Scan and report unlinked items
#   review [US-XXX]     Review story status and progress
#
# Options:
#   --no-color          Disable colored output
#   --help, -h          Show this help message
#
# Dependencies:
#   - jq (required for JSON manipulation)
#   - bash 4+ for associative arrays
#   - story-parser.sh library
#   - epoch-parser.sh library
#

set -euo pipefail

# Script location and library path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
STORY_PARSER="${LIB_DIR}/story-parser.sh"
EPOCH_PARSER="${LIB_DIR}/epoch-parser.sh"

# Default configuration
USER_STORIES_FILE="docs/UserStories.md"
TODOS_FILE="docs/ToDos.md"
NO_COLOR="${NO_COLOR:-}"
OUTPUT_WIDTH=64

# Exit codes
EXIT_SUCCESS=0
EXIT_STORY_NOT_FOUND=1
EXIT_EPOCH_NOT_FOUND=2
EXIT_INVALID_ARGS=3
EXIT_FILE_NOT_WRITABLE=4
EXIT_ALREADY_LINKED=5

# Colors (ANSI escape codes)
setup_colors() {
    if [[ -z "$NO_COLOR" ]] && [[ -t 1 ]]; then
        COLOR_RESET='\033[0m'
        COLOR_GREEN='\033[0;32m'
        COLOR_YELLOW='\033[0;33m'
        COLOR_RED='\033[0;31m'
        COLOR_BLUE='\033[0;34m'
        COLOR_CYAN='\033[0;36m'
        COLOR_BOLD='\033[1m'
        COLOR_DIM='\033[2m'
    else
        COLOR_RESET=''
        COLOR_GREEN=''
        COLOR_YELLOW=''
        COLOR_RED=''
        COLOR_BLUE=''
        COLOR_CYAN=''
        COLOR_BOLD=''
        COLOR_DIM=''
    fi
}

# Status symbols (ASCII-safe)
SYMBOL_PENDING='o'
SYMBOL_IN_PROGRESS='>'
SYMBOL_COMPLETE='*'
SYMBOL_LINKED='*'
SYMBOL_ORPHAN='o'

#
# Show help message
#
show_help() {
    cat <<EOF
story-manager.sh - Manage user stories via command line

Usage: $(basename "$0") <subcommand> [arguments] [OPTIONS]

Subcommands:
  create                     Interactive wizard for new story
  link US-XXX EPOCH-YYY      Link story to epoch bidirectionally
  sync                       Scan and report unlinked items
  review [US-XXX]            Review story status and progress

Options:
  --no-color                 Disable colored output
  --help, -h                 Show this help message

Examples:
  $(basename "$0") create                    # Start story creation wizard
  $(basename "$0") link US-010 EPOCH-012     # Link story to epoch
  $(basename "$0") sync                      # Show orphan report
  $(basename "$0") review                    # Review all stories
  $(basename "$0") review US-010             # Review specific story

Exit Codes:
  0    Success
  1    Story not found
  2    Epoch not found
  3    Invalid arguments
  4    File not writable
  5    Already linked

Environment:
  NO_COLOR                   Set to disable colors
  USER_STORIES_FILE          Override default docs/UserStories.md path
  TODOS_FILE                 Override default docs/ToDos.md path

EOF
}

#
# Source required libraries
#
load_libraries() {
    if [[ ! -f "$STORY_PARSER" ]]; then
        echo "Error: story-parser.sh not found at $STORY_PARSER" >&2
        exit $EXIT_INVALID_ARGS
    fi
    if [[ ! -f "$EPOCH_PARSER" ]]; then
        echo "Error: epoch-parser.sh not found at $EPOCH_PARSER" >&2
        exit $EXIT_INVALID_ARGS
    fi
    # shellcheck source=lib/story-parser.sh
    source "$STORY_PARSER"
    # shellcheck source=lib/epoch-parser.sh
    source "$EPOCH_PARSER"
}

#
# Draw box lines
#
draw_line() {
    local type="$1"
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
# Draw content line with borders
#
draw_content() {
    local content="$1"
    local width="${2:-$OUTPUT_WIDTH}"
    local inner_width=$((width - 4))

    # Truncate if too long
    if [[ ${#content} -gt $inner_width ]]; then
        content="${content:0:$((inner_width-3))}..."
    fi

    printf "| %-${inner_width}s |\n" "$content"
}

#
# Draw empty line in box
#
draw_empty() {
    draw_content "" "${1:-$OUTPUT_WIDTH}"
}

#
# Get status color
#
get_status_color() {
    local status="$1"
    case "$status" in
        Completed|complete)  echo "$COLOR_GREEN" ;;
        "In Progress"|in_progress) echo "$COLOR_YELLOW" ;;
        Planned|pending)     echo "$COLOR_DIM" ;;
        *)                   echo "$COLOR_RESET" ;;
    esac
}

#
# Mode: Create new story (interactive wizard)
#
mode_create() {
    load_libraries

    echo -e "${COLOR_BLUE}"
    draw_line "top"
    draw_content "Create New User Story"
    draw_line "bottom"
    echo -e "${COLOR_RESET}"
    echo ""

    # Persona selection
    echo "Persona (who benefits from this feature):"
    echo "  1. Developer using AI assistants"
    echo "  2. Project/Team lead"
    echo "  3. Workspace maintainer"
    echo "  4. Open source contributor"
    echo "  5. Other (enter custom)"
    echo ""
    read -rp "> " persona_choice

    local persona=""
    case "$persona_choice" in
        1) persona="developer using AI assistants" ;;
        2) persona="project/team lead" ;;
        3) persona="workspace maintainer" ;;
        4) persona="open source contributor" ;;
        5)
            read -rp "Enter custom persona: " persona
            ;;
        *)
            persona="$persona_choice"
            ;;
    esac

    echo ""
    echo "What does the user want to do?"
    read -rp "> " capability

    echo ""
    echo "Why do they want this? (benefit)"
    read -rp "> " benefit

    echo ""
    echo "Add acceptance criteria (empty line to finish):"
    local criteria=()
    while true; do
        read -rp "> " criterion
        if [[ -z "$criterion" ]]; then
            break
        fi
        criteria+=("$criterion")
    done

    # Generate title suggestion from capability
    local suggested_title
    suggested_title=$(echo "$capability" | sed 's/^./\U&/' | cut -c1-50)

    echo ""
    echo "Suggested title: \"$suggested_title\""
    read -rp "Accept? [Y/n] " title_accept

    local title="$suggested_title"
    if [[ "$title_accept" =~ ^[Nn] ]]; then
        read -rp "Enter custom title: " title
    fi

    # Get next story ID
    local next_id
    next_id=$(get_next_story_id "$USER_STORIES_FILE")

    # Generate story markdown
    local story_md=""
    story_md+="#### ${next_id}: ${title}\n\n"
    story_md+="> As a **${persona}**, I want **${capability}** so that **${benefit}**.\n\n"
    story_md+="**Implemented in:** Planned\n\n"
    story_md+="**Status:** Planned\n\n"
    story_md+="**Acceptance Criteria:**\n"
    for c in "${criteria[@]}"; do
        story_md+="- [ ] ${c}\n"
    done
    story_md+="\n---\n"

    # Insert story into UserStories.md
    insert_story "$USER_STORIES_FILE" "$story_md" "$next_id"

    echo ""
    echo -e "${COLOR_GREEN}"
    draw_line "top"
    draw_content "Story Created: ${next_id}"
    draw_line "middle"
    draw_content "Title: ${title}"
    draw_content "Status: Planned"
    draw_content "Location: ${USER_STORIES_FILE}"
    draw_line "bottom"
    echo -e "${COLOR_RESET}"
}

#
# Mode: Link story to epoch
#
mode_link() {
    local story_id="$1"
    local epoch_id="$2"

    load_libraries

    # Validate story ID format
    if ! [[ "$story_id" =~ ^US-[0-9]{3}$ ]]; then
        echo "Error: Invalid story ID format. Expected US-NNN (e.g., US-010)" >&2
        exit $EXIT_INVALID_ARGS
    fi

    # Validate epoch ID format
    if ! [[ "$epoch_id" =~ ^EPOCH-[0-9]{3}$ ]]; then
        echo "Error: Invalid epoch ID format. Expected EPOCH-NNN (e.g., EPOCH-012)" >&2
        exit $EXIT_INVALID_ARGS
    fi

    # Check story exists
    if ! story_exists "$story_id" "$USER_STORIES_FILE"; then
        echo "Error: Story ${story_id} not found in ${USER_STORIES_FILE}" >&2
        exit $EXIT_STORY_NOT_FOUND
    fi

    # Check epoch exists
    local epoch
    epoch=$(get_epoch "$epoch_id" "$TODOS_FILE")
    if [[ -z "$epoch" ]] || [[ "$epoch" == "null" ]]; then
        echo "Error: Epoch ${epoch_id} not found in ${TODOS_FILE}" >&2
        exit $EXIT_EPOCH_NOT_FOUND
    fi

    echo "Linking ${story_id} to ${epoch_id}..."
    echo ""

    # Update UserStories.md
    update_story_epoch_link "$story_id" "$epoch_id" "$USER_STORIES_FILE"
    echo "Updated ${USER_STORIES_FILE}:"
    echo "  - ${story_id}: Added \"Implemented in: ${epoch_id}\""

    # Update ToDos.md
    update_epoch_story_link "$epoch_id" "$story_id" "$TODOS_FILE"
    echo ""
    echo "Updated ${TODOS_FILE}:"
    echo "  - ${epoch_id}: Added \"User Story: ${story_id}\""

    echo ""
    echo -e "${COLOR_GREEN}* Bi-directional link created${COLOR_RESET}"
}

#
# Mode: Sync report (orphan detection)
#
mode_sync() {
    load_libraries

    echo -e "${COLOR_BLUE}"
    draw_line "top"
    draw_content "Story Sync Report"
    draw_line "bottom"
    echo -e "${COLOR_RESET}"
    echo ""

    # Parse stories and epochs
    local stories_json epochs_json
    stories_json=$(parse_stories "$USER_STORIES_FILE")
    epochs_json=$(parse_epochs "$TODOS_FILE")

    # Count totals
    local total_stories linked_stories orphan_stories
    total_stories=$(echo "$stories_json" | jq 'length')
    linked_stories=$(echo "$stories_json" | jq '[.[] | select(.implemented_in != null and .implemented_in != "" and .implemented_in != "Planned")] | length')
    orphan_stories=$((total_stories - linked_stories))

    local total_epochs linked_epochs orphan_epochs
    total_epochs=$(echo "$epochs_json" | jq 'length')
    linked_epochs=$(echo "$epochs_json" | jq '[.[] | select(.user_story != null and .user_story != "")] | length')
    orphan_epochs=$((total_epochs - linked_epochs))

    echo "Stories: ${total_stories} total"
    echo "  ${SYMBOL_LINKED} Linked:   ${linked_stories}"
    echo "  ${SYMBOL_ORPHAN} Orphan:   ${orphan_stories}"
    echo ""
    echo "Epochs: ${total_epochs} total"
    echo "  ${SYMBOL_LINKED} Linked:   ${linked_epochs}"
    echo "  ${SYMBOL_ORPHAN} Orphan:   ${orphan_epochs}"
    echo ""

    # List orphan stories
    if [[ $orphan_stories -gt 0 ]]; then
        draw_line "middle"
        draw_content "Orphan Stories (no epoch)"
        draw_line "middle"
        echo "$stories_json" | jq -r '.[] | select(.implemented_in == null or .implemented_in == "" or .implemented_in == "Planned") | "  \(.id)  \(.title)"'
        echo ""
    fi

    # List orphan epochs
    if [[ $orphan_epochs -gt 0 ]]; then
        draw_line "middle"
        draw_content "Orphan Epochs (no story)"
        draw_line "middle"
        echo "$epochs_json" | jq -r '.[] | select(.user_story == null or .user_story == "") | "  \(.epoch_id)  \(.title)"'
        echo ""
    fi

    echo ""
    echo "Run '/story link US-XXX EPOCH-YYY' to create links."
}

#
# Mode: Review story status
#
mode_review() {
    local story_id="${1:-}"

    load_libraries

    if [[ -n "$story_id" ]]; then
        # Review specific story
        review_single_story "$story_id"
    else
        # Review all stories
        review_all_stories
    fi
}

#
# Review a single story
#
review_single_story() {
    local story_id="$1"

    # Validate story ID format
    if ! [[ "$story_id" =~ ^US-[0-9]{3}$ ]]; then
        echo "Error: Invalid story ID format. Expected US-NNN (e.g., US-010)" >&2
        exit $EXIT_INVALID_ARGS
    fi

    # Get story details
    local story
    story=$(get_story "$story_id" "$USER_STORIES_FILE")

    if [[ -z "$story" ]] || [[ "$story" == "null" ]]; then
        echo "Error: Story ${story_id} not found in ${USER_STORIES_FILE}" >&2
        exit $EXIT_STORY_NOT_FOUND
    fi

    local title status implemented_in persona capability benefit
    title=$(echo "$story" | jq -r '.title // ""')
    status=$(echo "$story" | jq -r '.status // "Planned"')
    implemented_in=$(echo "$story" | jq -r '.implemented_in // ""')
    persona=$(echo "$story" | jq -r '.persona // ""')
    capability=$(echo "$story" | jq -r '.capability // ""')
    benefit=$(echo "$story" | jq -r '.benefit // ""')

    local status_color
    status_color=$(get_status_color "$status")

    echo -e "${COLOR_BLUE}"
    draw_line "top"
    draw_content "${story_id}: ${title}"
    draw_line "bottom"
    echo -e "${COLOR_RESET}"
    echo ""

    # Story statement
    if [[ -n "$persona" ]] && [[ -n "$capability" ]] && [[ -n "$benefit" ]]; then
        echo "As a **${persona}**, I want **${capability}**"
        echo "so that **${benefit}**."
        echo ""
    fi

    draw_line "middle"
    draw_content "Status: ${status_color}${status}${COLOR_RESET}"

    if [[ -n "$implemented_in" ]] && [[ "$implemented_in" != "Planned" ]]; then
        # Get epoch status
        local epoch_json
        epoch_json=$(get_epoch "$implemented_in" "$TODOS_FILE")
        if [[ -n "$epoch_json" ]] && [[ "$epoch_json" != "null" ]]; then
            local epoch_status task_count complete_count
            epoch_status=$(echo "$epoch_json" | jq -r '.status // "pending"')
            task_count=$(echo "$epoch_json" | jq '.tasks | length')
            complete_count=$(echo "$epoch_json" | jq '[.tasks[] | select(.status == "complete")] | length')
            draw_content "Linked Epoch: ${implemented_in} (${epoch_status}, ${complete_count}/${task_count} tasks)"
        else
            draw_content "Linked Epoch: ${implemented_in}"
        fi
    else
        draw_content "Linked Epoch: (none)"
    fi
    draw_line "middle"

    # Acceptance criteria
    draw_content "Acceptance Criteria:"
    echo "$story" | jq -r '.acceptance_criteria[] | if .complete then "    * \(.text)" else "    o \(.text)" end'

    draw_line "bottom"
}

#
# Review all stories
#
review_all_stories() {
    local stories_json
    stories_json=$(parse_stories "$USER_STORIES_FILE")

    echo -e "${COLOR_BLUE}"
    draw_line "top"
    draw_content "User Stories Summary"
    draw_line "bottom"
    echo -e "${COLOR_RESET}"
    echo ""

    # Group by status
    local completed in_progress planned
    completed=$(echo "$stories_json" | jq '[.[] | select(.status == "Completed" or .status == "Complete")]')
    in_progress=$(echo "$stories_json" | jq '[.[] | select(.status == "In Progress")]')
    planned=$(echo "$stories_json" | jq '[.[] | select(.status == "Planned" or .status == null or .status == "")]')

    local completed_count in_progress_count planned_count
    completed_count=$(echo "$completed" | jq 'length')
    in_progress_count=$(echo "$in_progress" | jq 'length')
    planned_count=$(echo "$planned" | jq 'length')

    if [[ $completed_count -gt 0 ]]; then
        echo -e "${COLOR_GREEN}Completed (${completed_count}):${COLOR_RESET}"
        echo "$completed" | jq -r '.[] | "  * \(.id)  \(.title[0:35])  \(.implemented_in // "(pre-epoch)")"'
        echo ""
    fi

    if [[ $in_progress_count -gt 0 ]]; then
        echo -e "${COLOR_YELLOW}In Progress (${in_progress_count}):${COLOR_RESET}"
        echo "$in_progress" | jq -r '.[] | "  > \(.id)  \(.title[0:35])  \(.implemented_in // "(no epoch)")"'
        echo ""
    fi

    if [[ $planned_count -gt 0 ]]; then
        echo -e "${COLOR_DIM}Planned (${planned_count}):${COLOR_RESET}"
        echo "$planned" | jq -r '.[] | "  o \(.id)  \(.title[0:35])  \(.implemented_in // "(no epoch)")"'
        echo ""
    fi

    local total=$((completed_count + in_progress_count + planned_count))
    draw_line "middle"
    echo "Total: ${total} stories (${completed_count} complete, ${in_progress_count} in_progress, ${planned_count} planned)"
}

#
# Main entry point
#
main() {
    setup_colors

    local subcommand=""
    local args=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit $EXIT_SUCCESS
                ;;
            --no-color)
                NO_COLOR=1
                setup_colors
                shift
                ;;
            create|link|sync|review)
                subcommand="$1"
                shift
                # Collect remaining arguments for the subcommand
                while [[ $# -gt 0 ]] && [[ ! "$1" =~ ^-- ]]; do
                    args+=("$1")
                    shift
                done
                ;;
            *)
                echo "Unknown argument: $1" >&2
                echo "Run '$(basename "$0") --help' for usage" >&2
                exit $EXIT_INVALID_ARGS
                ;;
        esac
    done

    # Validate subcommand
    if [[ -z "$subcommand" ]]; then
        echo "Error: Missing subcommand" >&2
        echo "Run '$(basename "$0") --help' for usage" >&2
        exit $EXIT_INVALID_ARGS
    fi

    # Check required files exist
    if [[ ! -f "$USER_STORIES_FILE" ]]; then
        echo "Error: ${USER_STORIES_FILE} not found" >&2
        exit $EXIT_STORY_NOT_FOUND
    fi

    if [[ ! -f "$TODOS_FILE" ]]; then
        echo "Error: ${TODOS_FILE} not found" >&2
        exit $EXIT_EPOCH_NOT_FOUND
    fi

    # Execute subcommand
    case "$subcommand" in
        create)
            mode_create
            ;;
        link)
            if [[ ${#args[@]} -lt 2 ]]; then
                echo "Error: Missing required arguments" >&2
                echo "Usage: $(basename "$0") link US-XXX EPOCH-YYY" >&2
                exit $EXIT_INVALID_ARGS
            fi
            mode_link "${args[0]}" "${args[1]}"
            ;;
        sync)
            mode_sync
            ;;
        review)
            mode_review "${args[0]:-}"
            ;;
    esac
}

# Run main if script is executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
