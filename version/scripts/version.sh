#!/usr/bin/env bash
#
# version.sh - Display git version info for workflow tools and repositories
#
# Usage:
#   version.sh                    # Show workflow tools + current repo version
#   MULTI_REPO=true version.sh    # Show all repos in workspace
#   version.sh --json             # Output in JSON format
#
# Output: commit hash and date for each repository

set -euo pipefail

# Path to the workflow tools repository (where this script lives)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

JSON_OUTPUT=false
MULTI_REPO="${MULTI_REPO:-false}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --help|-h)
            echo "Usage: version.sh [--json]"
            echo ""
            echo "Display git version information for workflow tools and repositories."
            echo ""
            echo "Options:"
            echo "  --json    Output in JSON format"
            echo ""
            echo "Environment:"
            echo "  MULTI_REPO=true    Show versions for all repos in workspace"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Get version info for a git repository
# Returns: commit_hash|date|repo_path
get_repo_version() {
    local repo_path="$1"

    if [[ ! -e "$repo_path/.git" ]]; then
        return 1
    fi

    local commit_hash date_str
    commit_hash=$(git -C "$repo_path" log -1 --format='%h' 2>/dev/null) || return 1
    date_str=$(git -C "$repo_path" log -1 --format='%ci' 2>/dev/null) || return 1

    echo "${commit_hash}|${date_str}|${repo_path}"
}

# Discover all git repositories in workspace
discover_repos() {
    local workspace_root="${1:-.}"
    local repos=()

    # Find all .git directories (excluding node_modules)
    while IFS= read -r git_dir; do
        local repo_dir
        repo_dir=$(dirname "$git_dir")
        repos+=("$repo_dir")
    done < <(find "$workspace_root" -type d -name ".git" -not -path "*/node_modules/*" 2>/dev/null | sort)

    printf '%s\n' "${repos[@]}"
}

# Output a single repo version
output_repo() {
    local name="$1"
    local hash="$2"
    local date="$3"
    local path="$4"

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo "    {"
        echo "      \"name\": \"$name\","
        echo "      \"commit\": \"$hash\","
        echo "      \"date\": \"$date\","
        echo "      \"path\": \"$path\""
        echo -n "    }"
    else
        echo -e "${CYAN}$name${NC}"
        echo -e "  Commit: ${GREEN}$hash${NC}"
        echo -e "  Date:   ${YELLOW}$date${NC}"
    fi
}

# Main execution
main() {
    local workflow_version current_version
    local workflow_hash workflow_date
    local current_hash current_date current_path

    # Always get workflow tools version
    workflow_version=$(get_repo_version "$WORKFLOW_REPO") || {
        echo -e "${RED}Error: Cannot read workflow tools repository${NC}" >&2
        exit 1
    }

    IFS='|' read -r workflow_hash workflow_date _ <<< "$workflow_version"

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo "{"
        echo "  \"workflow_tools\": {"
        echo "    \"commit\": \"$workflow_hash\","
        echo "    \"date\": \"$workflow_date\","
        echo "    \"path\": \"$WORKFLOW_REPO\""
        echo "  },"
    else
        echo ""
        echo -e "${BLUE}=== Workflow Tools ===${NC}"
        echo -e "  Commit: ${GREEN}$workflow_hash${NC}"
        echo -e "  Date:   ${YELLOW}$workflow_date${NC}"
        echo -e "  Path:   $WORKFLOW_REPO"
        echo ""
    fi

    if [[ "$MULTI_REPO" == "true" ]]; then
        # Multi-repo mode: show all repos in workspace
        local workspace_root
        workspace_root=$(dirname "$WORKFLOW_REPO")

        if [[ "$JSON_OUTPUT" == "true" ]]; then
            echo "  \"repositories\": ["
        else
            echo -e "${BLUE}=== Workspace Repositories ===${NC}"
        fi

        local first=true
        while IFS= read -r repo_path; do
            # Skip workflow repo (already shown)
            [[ "$repo_path" == "$WORKFLOW_REPO" ]] && continue

            local version_info
            version_info=$(get_repo_version "$repo_path") || continue

            IFS='|' read -r hash date path <<< "$version_info"
            local name
            name=$(basename "$repo_path")

            if [[ "$JSON_OUTPUT" == "true" ]]; then
                [[ "$first" != "true" ]] && echo ","
                first=false
                output_repo "$name" "$hash" "$date" "$path"
            else
                output_repo "$name" "$hash" "$date" "$path"
                echo ""
            fi
        done < <(discover_repos "$workspace_root")

        if [[ "$JSON_OUTPUT" == "true" ]]; then
            echo ""
            echo "  ]"
            echo "}"
        fi
    else
        # Single-repo mode: show current directory's repo if different
        current_path=$(git rev-parse --show-toplevel 2>/dev/null) || current_path=""

        if [[ -n "$current_path" && "$current_path" != "$WORKFLOW_REPO" ]]; then
            current_version=$(get_repo_version "$current_path") || {
                echo -e "${RED}Error: Cannot read current repository${NC}" >&2
                exit 1
            }

            IFS='|' read -r current_hash current_date _ <<< "$current_version"
            local current_name
            current_name=$(basename "$current_path")

            if [[ "$JSON_OUTPUT" == "true" ]]; then
                echo "  \"current_repo\": {"
                echo "    \"name\": \"$current_name\","
                echo "    \"commit\": \"$current_hash\","
                echo "    \"date\": \"$current_date\","
                echo "    \"path\": \"$current_path\""
                echo "  }"
                echo "}"
            else
                echo -e "${BLUE}=== Current Repository ===${NC}"
                echo -e "  Name:   ${CYAN}$current_name${NC}"
                echo -e "  Commit: ${GREEN}$current_hash${NC}"
                echo -e "  Date:   ${YELLOW}$current_date${NC}"
                echo ""
            fi
        else
            if [[ "$JSON_OUTPUT" == "true" ]]; then
                echo "  \"current_repo\": null"
                echo "}"
            else
                if [[ -z "$current_path" ]]; then
                    echo -e "${YELLOW}(Not in a git repository)${NC}"
                else
                    echo -e "${YELLOW}(Currently in workflow tools repository)${NC}"
                fi
                echo ""
            fi
        fi
    fi
}

main "$@"
