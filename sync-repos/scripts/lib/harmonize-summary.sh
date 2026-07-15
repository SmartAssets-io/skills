#!/usr/bin/env bash
#
# harmonize-summary.sh - Summary functions for harmonize-policies.sh
#
# This library provides:
# - Pre-flight summary display
# - Final summary display
#
# Usage:
#   source /path/to/lib/harmonize-summary.sh
#   show_preflight_summary
#   # ... do work ...
#   show_final_summary
#

# Prevent re-sourcing
if [[ -n "${HARMONIZE_SUMMARY_LOADED:-}" ]]; then
    return 0
fi
HARMONIZE_SUMMARY_LOADED=1

# Source UI library for box drawing (if not already loaded)
HARMONIZE_SUMMARY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${HARMONIZE_UI_LOADED:-}" ]]; then
    source "${HARMONIZE_SUMMARY_SCRIPT_DIR}/harmonize-ui.sh"
fi

# Source mode library for is_agentic_mode (if not already loaded)
if [[ -z "${HARMONIZE_MODE_LOADED:-}" ]]; then
    source "${HARMONIZE_SUMMARY_SCRIPT_DIR}/harmonize-mode.sh"
fi

#
# Show pre-flight summary
#
# Global variables used:
#   SOURCE_PATH - Path to source templates
#   DRY_RUN - true/false
#   FORCE_OVERWRITE - true/false
#   MODE - "yolo" or "interactive"
#   OUTPUT_WIDTH - Box width
#
show_preflight_summary() {
    echo ""
    draw_box_top "Policy Harmonization" "$OUTPUT_WIDTH"
    draw_box_content "Source: ${SOURCE_PATH##*/}/" "$OUTPUT_WIDTH"

    if [[ "${DRY_RUN:-false}" == true ]]; then
        draw_box_content "${COLOR_YELLOW}DRY RUN - No changes will be made${COLOR_RESET}" "$OUTPUT_WIDTH"
    fi

    if [[ "${FORCE_OVERWRITE:-false}" == true ]]; then
        draw_box_content "${COLOR_RED}FORCE MODE - Will overwrite customized files${COLOR_RESET}" "$OUTPUT_WIDTH"
    fi

    case "${MODE:-interactive}" in
        yolo)
            draw_box_content "Mode: YOLO (git worktree)" "$OUTPUT_WIDTH"
            ;;
        interactive)
            draw_box_content "Mode: Interactive" "$OUTPUT_WIDTH"
            ;;
    esac

    if is_agentic_mode; then
        draw_box_content "${COLOR_GREEN}Agentic mode: Will clean deny rules${COLOR_RESET}" "$OUTPUT_WIDTH"
    fi

    draw_box_bottom "$OUTPUT_WIDTH"
    echo ""
}

#
# Show final summary
#
# Global variables used:
#   DRY_RUN - true/false
#   SUMMARY - associative array with counters
#   CREATED_FILES - array of created file paths
#   UPDATED_REPOS - array of updated repo paths
#   CUSTOMIZED_FILES - array of customized file paths
#   PROFILE_REDIRECTED - array of profile redirections
#   DENY_RULES_CLEANED - array of repos with deny rules cleaned
#   ERROR_REPOS - array of repos with errors
#   OUTPUT_WIDTH - Box width
#
show_final_summary() {
    echo ""
    draw_box_top "Summary" "$OUTPUT_WIDTH"

    if [[ "${DRY_RUN:-false}" == true ]]; then
        draw_box_content "DRY RUN - No changes were made" "$OUTPUT_WIDTH"
        draw_box_line "$OUTPUT_WIDTH"
    fi

    draw_box_content "Repositories scanned:  ${SUMMARY[scanned]:-0}" "$OUTPUT_WIDTH"
    draw_box_content "Files created:         ${#CREATED_FILES[@]}" "$OUTPUT_WIDTH"
    draw_box_content "Files updated:         ${SUMMARY[updated]:-0}" "$OUTPUT_WIDTH"
    draw_box_content "Customized (preserved):${#CUSTOMIZED_FILES[@]}" "$OUTPUT_WIDTH"
    draw_box_content "Deny rules cleaned:    ${SUMMARY[deny_rules_cleaned]:-0}" "$OUTPUT_WIDTH"
    draw_box_content "Already in sync:       ${SUMMARY[in_sync]:-0}" "$OUTPUT_WIDTH"
    draw_box_content "Skipped:               ${SUMMARY[skipped]:-0}" "$OUTPUT_WIDTH"
    draw_box_content "Errors:                ${SUMMARY[errors]:-0}" "$OUTPUT_WIDTH"

    if [[ ${#UPDATED_REPOS[@]} -gt 0 ]]; then
        draw_box_line "$OUTPUT_WIDTH"
        draw_box_content "Updated repositories:" "$OUTPUT_WIDTH"
        for repo in "${UPDATED_REPOS[@]}"; do
            draw_box_content "  - $repo" "$OUTPUT_WIDTH"
        done
    fi

    if [[ ${#PROFILE_REDIRECTED[@]} -gt 0 ]]; then
        draw_box_line "$OUTPUT_WIDTH"
        draw_box_content "Profile directory redirections:" "$OUTPUT_WIDTH"
        for redirect in "${PROFILE_REDIRECTED[@]}"; do
            draw_box_content "  - $redirect" "$OUTPUT_WIDTH"
        done
    fi

    if [[ ${#DENY_RULES_CLEANED[@]} -gt 0 ]]; then
        draw_box_line "$OUTPUT_WIDTH"
        draw_box_content "Deny rules removed (agentic mode):" "$OUTPUT_WIDTH"
        for repo in "${DENY_RULES_CLEANED[@]}"; do
            draw_box_content "  - $repo" "$OUTPUT_WIDTH"
        done
    fi

    if [[ ${#ERROR_REPOS[@]} -gt 0 ]]; then
        draw_box_line "$OUTPUT_WIDTH"
        draw_box_content "Repositories with errors:" "$OUTPUT_WIDTH"
        for repo in "${ERROR_REPOS[@]}"; do
            draw_box_content "  - $repo" "$OUTPUT_WIDTH"
        done
    fi

    draw_box_bottom "$OUTPUT_WIDTH"
}
