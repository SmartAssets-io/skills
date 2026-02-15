#!/usr/bin/env bash
#
# multi-repo-sync.sh - Workspace-wide convention synchronization
#
# Orchestrates /harmonize across all repositories in the workspace
# with branch consistency enforcement and cross-repo validation.
#
# Usage:
#   multi-repo-sync.sh [OPTIONS]
#
# Options:
#   --dry-run           Preview all changes without modifying files
#   --yes, -y           Auto-apply all changes without prompting
#   --scope [workspace|subtree]  Scan scope (default: workspace)
#   --verbose           Show detailed output per repo
#   --strict[=BRANCH]   Enforce branch consistency (default branch: dev)
#   --no-color          Disable colored output
#   --help, -h          Show help message
#
# Exit codes:
#   0 - Success
#   1 - No repositories found
#   2 - Branch consistency check failed (with --strict)
#   3 - Invalid arguments
#   4 - User aborted
#   5 - One or more repos failed harmonization
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Scripts we depend on
HARMONIZE_SCRIPT="$SCRIPT_DIR/harmonize-policies.sh"
CONSISTENCY_SCRIPT="$SCRIPT_DIR/check-repo-consistency.sh"
REPO_TREE_SCRIPT="$SCRIPT_DIR/repo-tree.sh"

# Exit codes
EXIT_SUCCESS=0
EXIT_NO_REPOS=1
EXIT_BRANCH_FAIL=2
EXIT_INVALID_ARGS=3
EXIT_USER_ABORT=4
EXIT_HARMONIZE_FAIL=5

# Options
DRY_RUN=false
AUTO_YES=false
SCOPE="workspace"
VERBOSE=false
STRICT=false
STRICT_BRANCH=""
NO_COLOR=""
MULTI_REPO_ALL="${MULTI_REPO_ALL:-false}"
CLEAR_SELECTION=false
RUN_WIZARD=false

# Colors
COLOR_RESET=''
COLOR_GREEN=''
COLOR_YELLOW=''
COLOR_RED=''
COLOR_BLUE=''
COLOR_CYAN=''
COLOR_BOLD=''
COLOR_DIM=''

setup_colors() {
    if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then
        COLOR_RESET='\033[0m'
        COLOR_GREEN='\033[0;32m'
        COLOR_YELLOW='\033[1;33m'
        COLOR_RED='\033[0;31m'
        COLOR_BLUE='\033[0;34m'
        COLOR_CYAN='\033[0;36m'
        COLOR_BOLD='\033[1m'
        COLOR_DIM='\033[2m'
    fi
}

# Summary counters
REPOS_SCANNED=0
REPOS_SYNCED=0
REPOS_SKIPPED=0
REPOS_FAILED=0
BRANCH_STATUS="N/A"

# --- Logging ---

log_info()    { echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"; }
log_success() { echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $*"; }
log_warning() { echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"; }
log_error()   { echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*"; }

# --- Help ---

show_help() {
    cat <<'HELP_EOF'
Usage: multi-repo-sync.sh [OPTIONS]

Workspace-wide synchronization that orchestrates /harmonize across all repos
with branch consistency enforcement.

Options:
  --dry-run             Preview all changes without modifying files
  --yes, -y             Auto-apply all changes without prompting
  --scope [workspace|subtree]  Scan scope (default: workspace)
  --verbose             Show detailed output per repo
  --strict              Enforce all repos on majority branch
  --strict=BRANCH       Enforce all repos on specified branch (e.g., dev)
  --all                 Ignore saved repo selection, operate on all repos
  --clear               Delete saved repo selection config and exit
  --wizard              Output JSON repo tree for interactive selection wizard
  --no-color            Disable colored output
  -h, --help            Show help message

Exit codes:
  0  All repos synchronized successfully
  1  No repositories found in scope
  2  Branch consistency check failed (with --strict)
  3  Invalid arguments
  4  User aborted
  5  One or more repos failed harmonization
HELP_EOF
}

# --- Argument parsing ---

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)      DRY_RUN=true; shift ;;
            --yes|-y)       AUTO_YES=true; shift ;;
            --verbose)      VERBOSE=true; shift ;;
            --no-color)     NO_COLOR=1; shift ;;
            --strict)       STRICT=true; shift ;;
            --strict=*)     STRICT=true; STRICT_BRANCH="${1#--strict=}"; shift ;;
            --all)          MULTI_REPO_ALL=true; shift ;;
            --clear)        CLEAR_SELECTION=true; shift ;;
            --wizard)       RUN_WIZARD=true; shift ;;
            --scope)
                if [[ $# -lt 2 ]]; then
                    log_error "--scope requires an argument (workspace or subtree)"
                    exit $EXIT_INVALID_ARGS
                fi
                case "$2" in
                    workspace|subtree) SCOPE="$2" ;;
                    *) log_error "Invalid scope: $2 (must be workspace or subtree)"; exit $EXIT_INVALID_ARGS ;;
                esac
                shift 2 ;;
            -h|--help)      show_help; exit $EXIT_SUCCESS ;;
            -*)             log_error "Unknown option: $1"; exit $EXIT_INVALID_ARGS ;;
            *)              log_error "Unexpected argument: $1"; exit $EXIT_INVALID_ARGS ;;
        esac
    done
}

# --- Workspace discovery ---

find_workspace_root() {
    # Walk up from PROJECT_ROOT to find the SA workspace root
    local dir="$PROJECT_ROOT"
    while [[ "$dir" != "/" ]]; do
        # Look for the SA workspace marker (CLAUDE.md at workspace level)
        if [[ -f "$dir/CLAUDE.md" ]] && [[ -d "$dir/top-level-gitlab-profile" || "$(basename "$dir")" == "SA" ]]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    # Fallback: parent of PROJECT_ROOT
    dirname "$PROJECT_ROOT"
}

get_scan_root() {
    case "$SCOPE" in
        workspace) find_workspace_root ;;
        subtree)   pwd ;;
    esac
}

# --- Branch consistency ---

run_branch_check() {
    local scan_root="$1"

    if [[ "$STRICT" != "true" ]]; then
        BRANCH_STATUS="SKIPPED (no --strict)"
        return 0
    fi

    if [[ ! -f "$CONSISTENCY_SCRIPT" ]]; then
        log_warning "check-repo-consistency.sh not found, skipping branch check"
        BRANCH_STATUS="SKIPPED (script missing)"
        return 0
    fi

    echo ""
    log_info "Running branch consistency check..."

    local strict_flag="--strict"
    if [[ -n "$STRICT_BRANCH" ]]; then
        strict_flag="--strict=$STRICT_BRANCH"
    fi

    local check_output exit_code=0
    check_output=$(cd "$scan_root" && bash "$CONSISTENCY_SCRIPT" "$strict_flag" --all --fix-suggestion --no-color 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        local branch_name="${STRICT_BRANCH:-majority}"
        BRANCH_STATUS="PASS (all on $branch_name)"
        log_success "Branch consistency: PASS"
        return 0
    else
        BRANCH_STATUS="FAIL"
        log_error "Branch consistency: FAIL (exit code $exit_code)"
        echo ""
        echo "$check_output"
        echo ""

        if [[ "$DRY_RUN" == true ]]; then
            log_warning "Dry run: would block here due to branch inconsistency"
            return 0
        fi

        log_error "Sync blocked due to branch inconsistency."
        log_error "Fix the branch issues above and re-run."
        return 1
    fi
}

# --- Preflight summary ---

show_preflight() {
    local scan_root="$1"
    local rel_root
    rel_root=$(basename "$scan_root")

    echo ""
    echo "+------------------  Multi-Repo Sync  ----------------------+"

    local scope_line="| Scope: $SCOPE ($rel_root/)"
    printf "%-60s|\n" "$scope_line"

    if [[ "$DRY_RUN" == true ]]; then
        printf "%-60s|\n" "| DRY RUN - No changes will be made"
    fi

    if [[ "$STRICT" == true ]]; then
        local strict_display="strict"
        if [[ -n "$STRICT_BRANCH" ]]; then
            strict_display="strict=$STRICT_BRANCH"
        fi
        printf "%-60s|\n" "| Branch enforcement: $strict_display"
    fi

    if [[ "$AUTO_YES" == true ]]; then
        printf "%-60s|\n" "| Mode: Auto-apply (--yes)"
    fi

    # Show repo selection status
    if type -t selection_summary &>/dev/null; then
        local sel_summary
        sel_summary=$(selection_summary)
        printf "%-60s|\n" "| Repos: $sel_summary"
    fi

    echo "+-----------------------------------------------------------+"
}

# --- Core orchestration ---

run_sync() {
    local scan_root="$1"

    show_preflight "$scan_root"

    # Phase 1: Branch consistency check
    if ! run_branch_check "$scan_root"; then
        exit $EXIT_BRANCH_FAIL
    fi

    # Phase 2: Run harmonize
    echo ""
    log_info "Running harmonize-policies across workspace..."

    # Build harmonize flags
    local harmonize_flags=()
    if [[ "$DRY_RUN" == true ]]; then
        harmonize_flags+=("--dry-run")
    fi
    if [[ "$AUTO_YES" == true ]]; then
        harmonize_flags+=("--yes")
    fi
    if [[ -n "$NO_COLOR" ]]; then
        harmonize_flags+=("--no-color")
    fi
    if [[ "$VERBOSE" == true ]]; then
        harmonize_flags+=("--verbose")
    fi

    local harmonize_exit=0
    bash "$HARMONIZE_SCRIPT" "$scan_root" "${harmonize_flags[@]}" || harmonize_exit=$?

    if [[ $harmonize_exit -ne 0 ]]; then
        REPOS_FAILED=$((REPOS_FAILED + 1))
        log_error "Harmonization failed with exit code $harmonize_exit"
    fi

    return $harmonize_exit
}

# --- Final summary ---

show_summary() {
    echo ""
    echo "+---------------------  Sync Summary  -----------------------+"

    if [[ "$DRY_RUN" == true ]]; then
        printf "%-60s|\n" "| DRY RUN - No changes were made"
    fi

    printf "%-60s|\n" "| Branch consistency: $BRANCH_STATUS"
    echo "+-----------------------------------------------------------+"
}

# --- Main ---

main() {
    setup_colors
    parse_args "$@"
    setup_colors  # Re-run after --no-color parsed

    if [[ ! -f "$HARMONIZE_SCRIPT" ]]; then
        log_error "harmonize-policies.sh not found at $HARMONIZE_SCRIPT"
        exit $EXIT_INVALID_ARGS
    fi

    local scan_root
    scan_root=$(get_scan_root)

    if [[ ! -d "$scan_root" ]]; then
        log_error "Scan root does not exist: $scan_root"
        exit $EXIT_NO_REPOS
    fi

    # Source repo-selection library (optional - graceful if missing)
    if [[ -f "$SCRIPT_DIR/lib/repo-selection.sh" ]]; then
        source "$SCRIPT_DIR/lib/repo-selection.sh"
    fi

    # Handle --clear: delete selection config and exit
    if [[ "$CLEAR_SELECTION" == "true" ]]; then
        if type -t clear_selection &>/dev/null; then
            clear_selection "$scan_root"
        else
            log_error "repo-selection.sh not found, cannot clear selection"
            exit $EXIT_INVALID_ARGS
        fi
        exit $EXIT_SUCCESS
    fi

    # Handle --wizard: output JSON repo tree for Claude's wizard UX
    if [[ "$RUN_WIZARD" == "true" ]]; then
        if [[ -x "$REPO_TREE_SCRIPT" ]]; then
            exec bash "$REPO_TREE_SCRIPT" --json --branches --consistency "$scan_root"
        else
            log_error "repo-tree.sh not found at $REPO_TREE_SCRIPT"
            exit $EXIT_INVALID_ARGS
        fi
    fi

    # Load repo selection (no-op if no config or --all)
    if [[ "$MULTI_REPO_ALL" != "true" ]] && type -t load_selection &>/dev/null; then
        load_selection "$scan_root"
    fi

    # Export for harmonize-policies.sh to inherit
    export REPO_SELECTION_CONFIG
    export MULTI_REPO_ALL

    local sync_exit=0
    run_sync "$scan_root" || sync_exit=$?

    show_summary

    if [[ $sync_exit -ne 0 ]]; then
        exit $EXIT_HARMONIZE_FAIL
    fi

    exit $EXIT_SUCCESS
}

main "$@"
