#!/usr/bin/env bash
#
# harmonize-ui.sh - UI/output functions for harmonize-policies.sh
#
# This library provides:
# - Color setup for terminal output
# - Logging functions (info, success, warning, error, action)
# - Box drawing functions for formatted output
#
# Usage:
#   source /path/to/lib/harmonize-ui.sh
#   setup_colors
#   log_info "Starting process..."
#   log_action "CREATE" "file.txt"
#

# Prevent re-sourcing
if [[ -n "${HARMONIZE_UI_LOADED:-}" ]]; then
    return 0
fi
HARMONIZE_UI_LOADED=1

# Default output width for box drawing
OUTPUT_WIDTH=${OUTPUT_WIDTH:-64}

# Box drawing characters
BOX_TL='+'
BOX_TR='+'
BOX_BL='+'
BOX_BR='+'
BOX_H='-'
BOX_V='|'
BOX_ML='+'
BOX_MR='+'

# Color variables (set by setup_colors)
COLOR_RESET=''
COLOR_GREEN=''
COLOR_YELLOW=''
COLOR_RED=''
COLOR_BLUE=''
COLOR_CYAN=''
COLOR_BOLD=''
COLOR_DIM=''

#
# Setup color codes based on terminal capabilities
# Call this early in script initialization
#
setup_colors() {
    if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then
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

#
# Log an informational message
#
log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $1"
}

#
# Log a success message
#
log_success() {
    echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $1"
}

#
# Log a warning message
#
log_warning() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $1"
}

#
# Log an error message
#
log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $1"
}

#
# Log an action with specific formatting
# Arguments:
#   $1 - Action type (UPDATE, MERGE, CREATE, DERIVE, OK, SKIP, etc.)
#   $2 - Message to display
#
log_action() {
    local action="$1"
    local message="$2"
    case "$action" in
        UPDATE)
            echo -e "       ${COLOR_YELLOW}[UPDATE]${COLOR_RESET} $message"
            ;;
        MERGE)
            echo -e "       ${COLOR_YELLOW}[MERGE]${COLOR_RESET} $message"
            ;;
        CREATE)
            echo -e "       ${COLOR_GREEN}[CREATE]${COLOR_RESET} $message"
            ;;
        DERIVE)
            echo -e "       ${COLOR_CYAN}[DERIVE]${COLOR_RESET} $message"
            ;;
        OK)
            echo -e "       ${COLOR_DIM}[OK]${COLOR_RESET} $message"
            ;;
        SKIP)
            echo -e "       ${COLOR_DIM}[SKIP]${COLOR_RESET} $message"
            ;;
        CUSTOMIZED)
            echo -e "       ${COLOR_CYAN}[CUSTOMIZED]${COLOR_RESET} $message"
            ;;
        CONFLICT)
            echo -e "       ${COLOR_RED}[CONFLICT]${COLOR_RESET} $message"
            ;;
        ERROR)
            echo -e "       ${COLOR_RED}[ERROR]${COLOR_RESET} $message"
            ;;
        # Smart Asset specific actions
        SA_TYPE)
            echo -e "       ${COLOR_CYAN}[SA]${COLOR_RESET} $message"
            ;;
        SA_OK)
            echo -e "       ${COLOR_DIM}[SA OK]${COLOR_RESET} $message"
            ;;
        SA_WARN)
            echo -e "       ${COLOR_YELLOW}[SA WARN]${COLOR_RESET} $message"
            ;;
        SA_CREATE)
            echo -e "       ${COLOR_GREEN}[SA CREATE]${COLOR_RESET} $message"
            ;;
        SA_SCAFFOLD)
            echo -e "       ${COLOR_GREEN}[SA SCAFFOLD]${COLOR_RESET} $message"
            ;;
        SA_ERROR)
            echo -e "       ${COLOR_RED}[SA ERROR]${COLOR_RESET} $message"
            ;;
        # EPOCH-020: Convention embedding and mode detection actions
        INJECT)
            echo -e "       ${COLOR_GREEN}[INJECT]${COLOR_RESET} $message"
            ;;
        MODES)
            echo -e "       ${COLOR_DIM}[MODES]${COLOR_RESET} $message"
            ;;
    esac
}

#
# Draw the top border of a box with centered title
# Arguments:
#   $1 - Title text
#   $2 - Box width (optional, defaults to OUTPUT_WIDTH)
#
draw_box_top() {
    local title="$1"
    local width=${2:-$OUTPUT_WIDTH}
    local padding=$(( (width - ${#title} - 4) / 2 ))
    echo -n "$BOX_TL"
    printf "%${padding}s" | tr ' ' "$BOX_H"
    echo -n "  $title  "
    printf "%$(( width - padding - ${#title} - 4 ))s" | tr ' ' "$BOX_H"
    echo "$BOX_TR"
}

#
# Draw a horizontal line within a box
# Arguments:
#   $1 - Box width (optional, defaults to OUTPUT_WIDTH)
#
draw_box_line() {
    local width=${1:-$OUTPUT_WIDTH}
    echo -n "$BOX_ML"
    printf "%${width}s" | tr ' ' "$BOX_H"
    echo "$BOX_MR"
}

#
# Draw the bottom border of a box
# Arguments:
#   $1 - Box width (optional, defaults to OUTPUT_WIDTH)
#
draw_box_bottom() {
    local width=${1:-$OUTPUT_WIDTH}
    echo -n "$BOX_BL"
    printf "%${width}s" | tr ' ' "$BOX_H"
    echo "$BOX_BR"
}

#
# Draw a content line within a box
# Arguments:
#   $1 - Content text
#   $2 - Box width (optional, defaults to OUTPUT_WIDTH)
#
draw_box_content() {
    local content="$1"
    local width=${2:-$OUTPUT_WIDTH}
    printf "$BOX_V  %-$(( width - 3 ))s$BOX_V\n" "$content"
}
