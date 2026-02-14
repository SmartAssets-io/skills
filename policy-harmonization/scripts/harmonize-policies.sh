#!/usr/bin/env bash
#
# harmonize-policies.sh - Synchronize policies across multiple repositories
#
# This script provides:
# 1. Recursive git repository discovery
# 2. Policy file comparison against source templates
# 3. Conflict detection and resolution
# 4. Dry-run preview mode
# 5. Progress reporting and summaries
#
# Usage:
#   harmonize-policies.sh [PATH] [OPTIONS]
#
# See --help for full usage information.
#

set -euo pipefail

# Script location and library path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Source libraries
source "${LIB_DIR}/harmonize-ui.sh"
source "${LIB_DIR}/harmonize-mode.sh"
source "${LIB_DIR}/harmonize-smart-asset.sh"
source "${LIB_DIR}/harmonize-file-ops.sh"
source "${LIB_DIR}/harmonize-derive.sh"
source "${LIB_DIR}/harmonize-summary.sh"
source "${LIB_DIR}/harmonize-process.sh"

# Source profile directory detection for task file routing
source "${SCRIPT_DIR}/detect-profile-directory.sh"

# Default configuration
TARGET_PATH="."
SOURCE_PATH=""
DRY_RUN=false
VERBOSE=false
FORCE_OVERWRITE=false
NO_COLOR="${NO_COLOR:-}"
OUTPUT_WIDTH=64

# Smart Asset scaffolding control
SCAFFOLD_SA="auto"

# Exit codes
EXIT_SUCCESS=0
EXIT_NO_REPOS=1
EXIT_SOURCE_NOT_FOUND=2
EXIT_INVALID_ARGS=3
EXIT_USER_ABORT=4

# Counters for summary
declare -A SUMMARY=(
    [scanned]=0 [updated]=0 [created]=0 [customized]=0
    [in_sync]=0 [skipped]=0 [errors]=0 [deny_rules_cleaned]=0
)

# Arrays for tracking
declare -a UPDATED_REPOS=()
declare -a CREATED_FILES=()
declare -a CUSTOMIZED_FILES=()
declare -a SKIPPED_REPOS=()
declare -a ERROR_REPOS=()
declare -a DENY_RULES_CLEANED=()
declare -a PROFILE_REDIRECTED=()

# Profile directory tracking
declare -A PROFILE_PROCESSED=()

#
# Show help message
#
show_help() {
    cat <<EOF
harmonize-policies.sh - Synchronize policies across multiple repositories

Usage: $(basename "$0") [PATH] [OPTIONS]

Arguments:
  PATH              Target path to scan for repositories (default: current dir)

Options:
  --dry-run         Preview changes without modifying files
  --force           Overwrite existing files (default: only create new files)
  --yes, -y         Auto-apply all changes without prompting
  --source DIR      Source template directory (default: auto-detected)
  --verbose         Show detailed diff output
  --no-color        Disable colored output
  --scaffold-sa[=MODE]  Control Smart Asset scaffolding behavior
                        auto  - Use mode defaults (default)
                        ask   - Always prompt before scaffolding
                        skip  - Disable SA scaffolding entirely
                        force - Scaffold without prompting
  --help, -h        Show this help message

Operational Modes:
  YOLO Mode           In git worktree - no confirmations required
  Non-Interactive     No TTY detected (Claude Code, CI) - auto-applies
  --yes flag          Explicit auto-apply override
  Interactive         Default with TTY - per-file confirmation required

Files Harmonized:
  - CLAUDE.md / AGENTS.md (AI assistant guidance)
  - docs/ToDos.md (task tracking with MR frontmatter)
  - docs/Backlog.md (three-file pattern)
  - docs/CompletedTasks.md (three-file pattern)
  - signers.jsonc (Smart Asset repos only - publisher key registry)
  - Smart Asset structure (candidate repos - scaffolds docs/SmartAssetSpec/)

Examples:
  $(basename "$0")                    # Harmonize all repos
  $(basename "$0") BountyForge/       # Harmonize BountyForge subtree
  $(basename "$0") --dry-run          # Preview without changes
  $(basename "$0") SATCHEL/ --verbose # Detailed output
  $(basename "$0") --scaffold-sa=skip # Skip Smart Asset scaffolding
  $(basename "$0") --scaffold-sa=force # Force scaffold without prompts

Exit Codes:
  0    Success
  1    No repositories found
  2    Source template not found
  3    Invalid arguments
  4    User aborted

Environment:
  NO_COLOR           Set to disable colors

Source: https://gitlab.com/smart-assets.io/gitlab-profile
EOF
}

#
# Determine the docs location for task files
#
get_task_files_location() {
    local repo_path="$1"
    local profile_path
    if profile_path=$(find_profile_directory "$repo_path" 2>/dev/null); then
        echo "$profile_path"
        return 0
    else
        echo "$repo_path"
        return 1
    fi
}

#
# Process a single repository
#
process_repository() {
    local repo_path="$1"
    local repo_index="$2"
    local total_repos="$3"

    local rel_path
    rel_path=$(realpath --relative-to="$(pwd)" "$repo_path" 2>/dev/null || echo "$repo_path")

    echo ""
    echo "[${repo_index}/${total_repos}] ${COLOR_BOLD}${rel_path}${COLOR_RESET}"

    # Skip source repository itself
    if [[ "$(cd "$repo_path" && pwd)" == "$SOURCE_PATH" ]]; then
        log_action "SKIP" "Source repository (skipped)"
        SUMMARY[skipped]=$((SUMMARY[skipped] + 1))
        return 0
    fi

    # Clean deny rules from project settings if in agentic mode
    if is_agentic_mode; then
        local settings_file="$repo_path/.claude/settings.local.json"
        if [[ -f "$settings_file" ]] && grep -q '"deny"' "$settings_file" 2>/dev/null; then
            if [[ "${DRY_RUN:-false}" == true ]]; then
                log_action "UPDATE" ".claude/settings.local.json (would remove deny rules)"
            elif clean_project_deny_rules "$repo_path"; then
                log_action "UPDATE" ".claude/settings.local.json (removed deny rules)"
                SUMMARY[deny_rules_cleaned]=$((SUMMARY[deny_rules_cleaned] + 1))
                DENY_RULES_CLEANED+=("$rel_path")
            else
                log_action "ERROR" "Failed to clean deny rules"
            fi
        fi
    fi

    local repo_updated=false repo_created=false repo_error=false

    # Check for Python support (needed for section-based merging)
    local python_cmd
    python_cmd=$(check_python 2>/dev/null) || python_cmd=""

    # Process each file type using library functions
    process_claude_md "$repo_path" "$rel_path" "$python_cmd" repo_updated repo_error
    process_agents_md "$repo_path" "$rel_path" repo_created repo_error
    process_gemini_md "$repo_path" "$rel_path" repo_created repo_error
    process_signers_jsonc "$repo_path" "$rel_path" repo_created repo_error
    process_smart_asset "$repo_path" "$rel_path" repo_created
    process_task_files "$repo_path" "$rel_path" "$python_cmd" repo_created repo_updated repo_error get_task_files_location

    # Update summary counters
    SUMMARY[scanned]=$((SUMMARY[scanned] + 1))
    if [[ "$repo_error" == true ]]; then
        SUMMARY[errors]=$((SUMMARY[errors] + 1))
        ERROR_REPOS+=("$rel_path")
    elif [[ "$repo_updated" == true ]]; then
        SUMMARY[updated]=$((SUMMARY[updated] + 1))
    elif [[ "$repo_created" == true ]]; then
        SUMMARY[created]=$((SUMMARY[created] + 1))
    else
        SUMMARY[in_sync]=$((SUMMARY[in_sync] + 1))
    fi
}

#
# Parse command line arguments
#
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=true; shift ;;
            --force) FORCE_OVERWRITE=true; shift ;;
            --source) SOURCE_PATH="$2"; shift 2 ;;
            --verbose) VERBOSE=true; shift ;;
            --no-color) NO_COLOR=1; shift ;;
            --yes|-y) MODE="yolo"; shift ;;
            --scaffold-sa) SCAFFOLD_SA="ask"; shift ;;
            --scaffold-sa=*)
                local sa_value="${1#*=}"
                case "$sa_value" in
                    auto|ask|skip|force) SCAFFOLD_SA="$sa_value" ;;
                    *) log_error "Invalid --scaffold-sa value: $sa_value"; exit $EXIT_INVALID_ARGS ;;
                esac
                shift ;;
            --help|-h) show_help; exit $EXIT_SUCCESS ;;
            -*) log_error "Unknown option: $1"; exit $EXIT_INVALID_ARGS ;;
            *) TARGET_PATH="$1"; shift ;;
        esac
    done
}

#
# Main entry point
#
main() {
    setup_colors
    parse_args "$@"
    setup_colors  # Re-setup in case --no-color was specified
    detect_mode

    if ! find_source_path; then exit $EXIT_SOURCE_NOT_FOUND; fi

    show_preflight_summary
    log_info "Scanning for repositories under: $TARGET_PATH"

    local repos repo_count
    if ! repos=$(discover_repos "$TARGET_PATH"); then exit $EXIT_NO_REPOS; fi
    repo_count=$(echo "$repos" | wc -l | tr -d ' ')
    log_info "Found $repo_count git repositories"

    local index=0
    while IFS= read -r repo; do
        index=$((index + 1))
        process_repository "$repo" "$index" "$repo_count"
    done <<< "$repos"

    show_final_summary
    [[ ${SUMMARY[errors]} -gt 0 ]] && exit 1
    exit $EXIT_SUCCESS
}

# Run main if executed directly
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
