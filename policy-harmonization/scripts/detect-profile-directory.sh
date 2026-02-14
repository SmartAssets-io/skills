#!/usr/bin/env bash
#
# detect-profile-directory.sh - Detect peer-level profile directory for a repository
#
# This script determines if a repository should use a separate profile directory
# for Task/Epoch/Story files (docs/ToDos.md, docs/UserStories.md, etc.) instead
# of storing them in the repository itself.
#
# Profile Directory Patterns (in order of precedence):
#   1. {parent}/{ParentName}_gitlab-profile/  (e.g., BountyForge/BountyForge_gitlab-profile/)
#   2. {parent}/{ParentName}-gitlab-profile/  (e.g., BountyForge/BountyForge-gitlab-profile/)
#   3. {parent}/gitlab-profile/               (e.g., SATCHEL/gitlab-profile/)
#   4. {parent}/{ParentName}_github-profile/
#   5. {parent}/{ParentName}-github-profile/
#   6. {parent}/github-profile/
#   7. {parent}/codeberg/
#
# Usage:
#   detect-profile-directory.sh [REPO_PATH]
#
# Arguments:
#   REPO_PATH   Path to the repository (default: current directory)
#
# Output Modes:
#   --json      Output as JSON object
#   --quiet     Only output profile path (or empty if none)
#   (default)   Human-readable output
#
# Exit Codes:
#   0   Profile directory found
#   1   No profile directory found (use repo itself)
#   2   Invalid arguments or path
#
# Environment:
#   PROFILE_DEBUG=1   Enable debug output
#
# Examples:
#   # Check current directory
#   detect-profile-directory.sh
#
#   # Check specific repo
#   detect-profile-directory.sh /path/to/repo
#
#   # Get JSON output
#   detect-profile-directory.sh --json /path/to/repo
#
#   # Get just the path (for scripting)
#   detect-profile-directory.sh --quiet /path/to/repo
#

set -euo pipefail

# Script configuration
SCRIPT_NAME="$(basename "$0")"
DEBUG="${PROFILE_DEBUG:-0}"

# Output mode
OUTPUT_MODE="human"  # human, json, quiet

# Colors
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    COLOR_RESET='\033[0m'
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[0;33m'
    COLOR_BLUE='\033[0;34m'
    COLOR_DIM='\033[2m'
else
    COLOR_RESET=''
    COLOR_GREEN=''
    COLOR_YELLOW=''
    COLOR_BLUE=''
    COLOR_DIM=''
fi

#
# Logging functions
#
debug() {
    if [[ "$DEBUG" == "1" ]]; then
        echo -e "${COLOR_DIM}[DEBUG] $1${COLOR_RESET}" >&2
    fi
}

info() {
    if [[ "$OUTPUT_MODE" == "human" ]]; then
        echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $1"
    fi
}

#
# Show help
#
show_help() {
    cat <<EOF
$SCRIPT_NAME - Detect peer-level profile directory for a repository

Usage: $SCRIPT_NAME [OPTIONS] [REPO_PATH]

Arguments:
  REPO_PATH       Path to the repository (default: current directory)

Options:
  --json          Output as JSON object
  --quiet, -q     Only output profile path (or empty if none)
  --help, -h      Show this help message

Profile Directory Patterns (checked in order):
  1. {parent}/{ParentName}_gitlab-profile/
  2. {parent}/{ParentName}-gitlab-profile/
  3. {parent}/gitlab-profile/
  4. {parent}/{ParentName}_github-profile/
  5. {parent}/{ParentName}-github-profile/
  6. {parent}/github-profile/
  7. {parent}/codeberg/

Exit Codes:
  0   Profile directory found
  1   No profile directory found (use repo itself)
  2   Invalid arguments or path

Environment:
  PROFILE_DEBUG=1   Enable debug output
  NO_COLOR          Disable colored output

Examples:
  $SCRIPT_NAME                          # Check current directory
  $SCRIPT_NAME /path/to/repo            # Check specific repo
  $SCRIPT_NAME --json /path/to/repo     # JSON output
  $SCRIPT_NAME -q /path/to/repo         # Just the path
EOF
}

#
# Get the git repository root for a path
#
get_repo_root() {
    local path="$1"
    (
        cd "$path" 2>/dev/null || exit 1
        git rev-parse --show-toplevel 2>/dev/null
    )
}

#
# Check if a directory is a git repository
#
is_git_repo() {
    local path="$1"
    [[ -d "$path/.git" ]] || [[ -f "$path/.git" ]]
}

#
# Check if a directory is a profile directory (has docs/ToDos.md or CLAUDE.md)
#
is_profile_directory() {
    local path="$1"

    # Must be a git repository
    if ! is_git_repo "$path"; then
        return 1
    fi

    # Should have CLAUDE.md or docs/ structure
    if [[ -f "$path/CLAUDE.md" ]] || [[ -d "$path/docs" ]]; then
        return 0
    fi

    return 1
}

#
# Check if a path is the profile directory itself (should not redirect)
#
is_self_profile() {
    local repo_name="$1"

    # Check if the repo name matches profile patterns
    case "$repo_name" in
        *-gitlab-profile|*_gitlab-profile|gitlab-profile)
            return 0
            ;;
        *-github-profile|*_github-profile|github-profile)
            return 0
            ;;
        codeberg|*-codeberg|*_codeberg)
            return 0
            ;;
        top-level-gitlab-profile*)
            return 0
            ;;
    esac

    return 1
}

#
# Find profile directory for a repository
#
# Arguments:
#   $1 - Repository path (absolute)
#
# Output:
#   Profile directory path if found, empty string if not
#
find_profile_directory() {
    local repo_path="$1"
    local repo_name parent_path parent_name

    # Get repository name and parent path
    repo_name="$(basename "$repo_path")"
    parent_path="$(dirname "$repo_path")"
    parent_name="$(basename "$parent_path")"

    debug "Repo: $repo_name"
    debug "Parent: $parent_path ($parent_name)"

    # Don't redirect if we ARE a profile directory
    if is_self_profile "$repo_name"; then
        debug "Repository is itself a profile directory - no redirect"
        return 1
    fi

    # Profile directory patterns to check (in order of precedence)
    local patterns=(
        # GitLab patterns
        "${parent_path}/${parent_name}_gitlab-profile"
        "${parent_path}/${parent_name}-gitlab-profile"
        "${parent_path}/gitlab-profile"
        # GitHub patterns
        "${parent_path}/${parent_name}_github-profile"
        "${parent_path}/${parent_name}-github-profile"
        "${parent_path}/github-profile"
        # Codeberg pattern
        "${parent_path}/codeberg"
    )

    # Check each pattern
    for pattern in "${patterns[@]}"; do
        debug "Checking: $pattern"

        if [[ -d "$pattern" ]] && is_profile_directory "$pattern"; then
            # Found a valid profile directory
            # Make sure it's not the same as the repo we're checking
            local real_pattern real_repo
            real_pattern="$(cd "$pattern" && pwd)"
            real_repo="$(cd "$repo_path" && pwd)"

            if [[ "$real_pattern" != "$real_repo" ]]; then
                debug "Found profile directory: $pattern"
                echo "$pattern"
                return 0
            fi
        fi
    done

    debug "No profile directory found"
    return 1
}

#
# Output results
#
output_result() {
    local repo_path="$1"
    local profile_path="${2:-}"
    local has_profile=false
    local docs_location

    if [[ -n "$profile_path" ]]; then
        has_profile=true
        docs_location="$profile_path/docs"
    else
        docs_location="$repo_path/docs"
    fi

    case "$OUTPUT_MODE" in
        json)
            local repo_name parent_name profile_name
            repo_name="$(basename "$repo_path")"
            parent_name="$(basename "$(dirname "$repo_path")")"

            if [[ "$has_profile" == true ]]; then
                profile_name="$(basename "$profile_path")"
                cat <<EOF
{
  "has_profile_directory": true,
  "repo_path": "$repo_path",
  "repo_name": "$repo_name",
  "parent_name": "$parent_name",
  "profile_path": "$profile_path",
  "profile_name": "$profile_name",
  "docs_location": "$docs_location",
  "todos_file": "$docs_location/ToDos.md",
  "stories_file": "$docs_location/UserStories.md",
  "backlog_file": "$docs_location/Backlog.md",
  "completed_file": "$docs_location/CompletedTasks.md"
}
EOF
            else
                cat <<EOF
{
  "has_profile_directory": false,
  "repo_path": "$repo_path",
  "repo_name": "$repo_name",
  "parent_name": "$parent_name",
  "profile_path": null,
  "profile_name": null,
  "docs_location": "$docs_location",
  "todos_file": "$docs_location/ToDos.md",
  "stories_file": "$docs_location/UserStories.md",
  "backlog_file": "$docs_location/Backlog.md",
  "completed_file": "$docs_location/CompletedTasks.md"
}
EOF
            fi
            ;;

        quiet)
            if [[ "$has_profile" == true ]]; then
                echo "$profile_path"
            fi
            # Empty output if no profile (exit code indicates result)
            ;;

        human|*)
            local repo_name
            repo_name="$(basename "$repo_path")"

            if [[ "$has_profile" == true ]]; then
                local profile_name
                profile_name="$(basename "$profile_path")"
                echo -e "${COLOR_GREEN}Profile directory found${COLOR_RESET}"
                echo ""
                echo "  Repository:     $repo_name"
                echo "  Profile:        $profile_name"
                echo "  Profile path:   $profile_path"
                echo ""
                echo "  Task/Story files should be placed in:"
                echo "    - $docs_location/ToDos.md"
                echo "    - $docs_location/UserStories.md"
                echo "    - $docs_location/Backlog.md"
                echo "    - $docs_location/CompletedTasks.md"
            else
                echo -e "${COLOR_YELLOW}No profile directory found${COLOR_RESET}"
                echo ""
                echo "  Repository:     $repo_name"
                echo "  Repository path: $repo_path"
                echo ""
                echo "  Task/Story files should be placed in the repository itself:"
                echo "    - $docs_location/ToDos.md"
                echo "    - $docs_location/UserStories.md"
                echo "    - $docs_location/Backlog.md"
                echo "    - $docs_location/CompletedTasks.md"
            fi
            ;;
    esac
}

#
# Main entry point
#
main() {
    local repo_path="."

    # Parse arguments directly (not in subshell to preserve OUTPUT_MODE)
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                OUTPUT_MODE="json"
                shift
                ;;
            --quiet|-q)
                OUTPUT_MODE="quiet"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            -*)
                echo "Error: Unknown option: $1" >&2
                echo "Use --help for usage information" >&2
                exit 2
                ;;
            *)
                repo_path="$1"
                shift
                ;;
        esac
    done

    # Validate and resolve path
    if [[ ! -d "$repo_path" ]]; then
        echo "Error: Directory not found: $repo_path" >&2
        exit 2
    fi

    # Get absolute path
    repo_path="$(cd "$repo_path" && pwd)"
    debug "Resolved repo path: $repo_path"

    # Check if it's a git repository
    if ! is_git_repo "$repo_path"; then
        # Try to find git root
        local git_root
        if git_root="$(get_repo_root "$repo_path")"; then
            repo_path="$git_root"
            debug "Using git root: $repo_path"
        else
            echo "Error: Not a git repository: $repo_path" >&2
            exit 2
        fi
    fi

    # Find profile directory
    local profile_path
    if profile_path="$(find_profile_directory "$repo_path")"; then
        output_result "$repo_path" "$profile_path"
        exit 0
    else
        output_result "$repo_path" ""
        exit 1
    fi
}

# Run main if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
