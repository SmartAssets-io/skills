#!/usr/bin/env bash
#
# github-integration.sh - GitHub PR integration for multi-agent reviews
#
# This library provides:
# 1. GitHub PR diff extraction via gh CLI
# 2. PR creation and comment posting
# 3. PR metadata fetching
# 4. Review comment formatting
#
# Dependencies:
#   - gh CLI (GitHub CLI) - Required
#   - jq - Required for JSON manipulation
#
# Usage:
#   source /path/to/github-integration.sh
#   diff=$(github_get_pr_diff 123)
#   github_post_review_comment 123 "$markdown"
#

# Prevent re-sourcing
if [[ -n "${GITHUB_INTEGRATION_LOADED:-}" ]]; then
    return 0
fi
GITHUB_INTEGRATION_LOADED=1

#
# Check if gh CLI is available and authenticated
#
github_check() {
    # Check if gh is installed
    if ! command -v gh >/dev/null 2>&1; then
        echo "false"
        return 1
    fi

    # Check if gh is authenticated
    if ! gh auth status >/dev/null 2>&1; then
        echo "false"
        return 1
    fi

    echo "true"
    return 0
}

#
# Get current repository info (owner/repo)
#
github_get_repo_info() {
    local remote_url
    remote_url=$(git config --get remote.origin.url 2>/dev/null || echo "")

    if [[ -z "$remote_url" ]]; then
        echo ""
        return 1
    fi

    # Extract owner/repo from various URL formats
    local repo_path=""

    if [[ "$remote_url" == *"github.com"* ]]; then
        # HTTPS: https://github.com/owner/repo.git
        # SSH: git@github.com:owner/repo.git
        repo_path=$(echo "$remote_url" | sed -E 's|.*github\.com[:/]||' | sed 's|\.git$||')
    fi

    echo "$repo_path"
}

#
# Parse PR identifier (number or URL)
#
github_parse_pr_id() {
    local input="$1"

    # If numeric, return as-is
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        echo "$input"
        return 0
    fi

    # If URL, extract PR number
    if [[ "$input" =~ github\.com/.*/pull/([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    # If branch name, find PR for that branch
    local pr_number
    pr_number=$(gh pr view --json number -q '.number' -- "$input" 2>/dev/null)

    if [[ -n "$pr_number" ]]; then
        echo "$pr_number"
        return 0
    fi

    echo ""
    return 1
}

#
# Get PR metadata
#
github_get_pr_info() {
    local pr_id="$1"

    local pr_number
    pr_number=$(github_parse_pr_id "$pr_id")

    if [[ -z "$pr_number" ]]; then
        cat <<EOF
{"error": "Could not parse PR identifier: $pr_id"}
EOF
        return 1
    fi

    gh pr view --json \
        number,title,body,state,baseRefName,headRefName,\
additions,deletions,changedFiles,url,author,labels -- "$pr_number" 2>/dev/null || \
    echo '{"error": "Failed to fetch PR info"}'
}

#
# Get PR diff
#
github_get_pr_diff() {
    local pr_id="$1"

    local pr_number
    pr_number=$(github_parse_pr_id "$pr_id")

    if [[ -z "$pr_number" ]]; then
        echo "Error: Could not parse PR identifier: $pr_id" >&2
        return 1
    fi

    gh pr diff -- "$pr_number" 2>/dev/null
}

#
# Get list of files changed in PR
#
github_get_pr_files() {
    local pr_id="$1"

    local pr_number
    pr_number=$(github_parse_pr_id "$pr_id")

    if [[ -z "$pr_number" ]]; then
        echo "[]"
        return 1
    fi

    gh pr view --json files -q '.files[].path' -- "$pr_number" 2>/dev/null
}

#
# Get PR diff for a specific file
#
github_get_file_diff() {
    local pr_id="$1"
    local file_path="$2"

    local full_diff
    full_diff=$(github_get_pr_diff "$pr_id")

    if [[ -z "$full_diff" ]]; then
        return 1
    fi

    # Extract diff for specific file
    echo "$full_diff" | awk -v file="$file_path" '
        /^diff --git/ {
            current_file = ""
            for (i = 3; i <= NF; i++) {
                if ($i ~ /^b\//) {
                    current_file = substr($i, 3)
                    break
                }
            }
            printing = (current_file == file)
        }
        printing { print }
    '
}

#
# Build review context from PR info
#
github_build_review_context() {
    local pr_info="$1"

    local repo_name pr_title pr_description target_branch file_count additions deletions

    repo_name=$(github_get_repo_info)
    pr_title=$(echo "$pr_info" | jq -r '.title // "Unknown"')
    # Allow up to 4000 chars for description to give reviewers full context
    pr_description=$(echo "$pr_info" | jq -r '.body // ""' | head -c 4000)
    target_branch=$(echo "$pr_info" | jq -r '.baseRefName // "main"')
    file_count=$(echo "$pr_info" | jq -r '.changedFiles // 0')
    additions=$(echo "$pr_info" | jq -r '.additions // 0')
    deletions=$(echo "$pr_info" | jq -r '.deletions // 0')

    cat <<EOF
{
    "repo_name": "$repo_name",
    "pr_title": "$pr_title",
    "pr_description": $(echo "$pr_description" | jq -Rs '.'),
    "target_branch": "$target_branch",
    "file_count": "$file_count",
    "additions": $additions,
    "deletions": $deletions,
    "platform": "github"
}
EOF
}

#
# Post a comment to a PR
#
github_post_comment() {
    local pr_id="$1"
    local comment="$2"

    local pr_number
    pr_number=$(github_parse_pr_id "$pr_id")

    if [[ -z "$pr_number" ]]; then
        echo "Error: Could not parse PR identifier: $pr_id" >&2
        return 1
    fi

    # Write comment to temp file (handles special characters better)
    local temp_file
    temp_file=$(mktemp)
    echo "$comment" > "$temp_file"

    gh pr comment --body-file "$temp_file" -- "$pr_number" 2>&1
    local exit_code=$?

    rm -f "$temp_file"

    return $exit_code
}

#
# Post a review comment to a PR (with approve/request changes)
#
github_post_review() {
    local pr_id="$1"
    local comment="$2"
    local verdict="$3"  # approve, needs_work, abstain

    local pr_number
    pr_number=$(github_parse_pr_id "$pr_id")

    if [[ -z "$pr_number" ]]; then
        echo "Error: Could not parse PR identifier: $pr_id" >&2
        return 1
    fi

    # Write comment to temp file
    local temp_file
    temp_file=$(mktemp)
    echo "$comment" > "$temp_file"

    # Map verdict to gh review event
    local review_event="COMMENT"
    case "$verdict" in
        approve)
            review_event="APPROVE"
            ;;
        needs_work)
            review_event="REQUEST_CHANGES"
            ;;
        *)
            review_event="COMMENT"
            ;;
    esac

    gh pr review --$review_event --body-file "$temp_file" -- "$pr_number" 2>&1
    local exit_code=$?

    rm -f "$temp_file"

    return $exit_code
}

#
# Create a new PR
#
github_create_pr() {
    local title="$1"
    local body="$2"
    local base="${3:-main}"
    local head="${4:-}"

    # Get current branch if head not specified
    if [[ -z "$head" ]]; then
        head=$(git branch --show-current 2>/dev/null)
    fi

    if [[ -z "$head" ]]; then
        echo "Error: Could not determine head branch" >&2
        return 1
    fi

    # Write body to temp file
    local temp_file
    temp_file=$(mktemp)
    echo "$body" > "$temp_file"

    gh pr create --title "$title" --body-file "$temp_file" --base "$base" --head "$head" 2>&1
    local exit_code=$?

    rm -f "$temp_file"

    return $exit_code
}

#
# Get PR for current branch
#
github_get_current_pr() {
    gh pr view --json number,title,state,url 2>/dev/null || echo '{"error": "No PR for current branch"}'
}

#
# Check if current branch has an open PR
#
github_has_open_pr() {
    local pr_info
    pr_info=$(github_get_current_pr)

    local state
    state=$(echo "$pr_info" | jq -r '.state // "NONE"')

    if [[ "$state" == "OPEN" ]]; then
        echo "true"
        return 0
    fi

    echo "false"
    return 1
}

#
# Get PR URL
#
github_get_pr_url() {
    local pr_id="$1"

    local pr_number
    pr_number=$(github_parse_pr_id "$pr_id")

    if [[ -z "$pr_number" ]]; then
        return 1
    fi

    gh pr view --json url -q '.url' -- "$pr_number" 2>/dev/null
}

#
# CLI interface when run directly
#
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    COMMAND="${1:-help}"

    case "$COMMAND" in
        check)
            if [[ $(github_check) == "true" ]]; then
                echo "GitHub CLI is available and authenticated"
                echo "Repository: $(github_get_repo_info)"
            else
                echo "GitHub CLI is not available or not authenticated"
                echo "Install gh: https://cli.github.com/"
                echo "Authenticate: gh auth login"
                exit 1
            fi
            ;;
        info)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 info PR_NUMBER_OR_URL" >&2
                exit 1
            fi
            github_get_pr_info "$2" | jq '.'
            ;;
        diff)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 diff PR_NUMBER_OR_URL" >&2
                exit 1
            fi
            github_get_pr_diff "$2"
            ;;
        files)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 files PR_NUMBER_OR_URL" >&2
                exit 1
            fi
            github_get_pr_files "$2"
            ;;
        comment)
            if [[ -z "${2:-}" ]] || [[ -z "${3:-}" ]]; then
                echo "Usage: $0 comment PR_NUMBER_OR_URL MESSAGE" >&2
                exit 1
            fi
            github_post_comment "$2" "$3"
            ;;
        current)
            github_get_current_pr | jq '.'
            ;;
        help|--help|-h)
            cat <<EOF
github-integration.sh - GitHub PR integration for multi-agent reviews

Usage: $0 <command> [args]

Commands:
    check               Check if gh CLI is available and authenticated
    info PR_ID          Get PR metadata as JSON
    diff PR_ID          Get PR diff
    files PR_ID         List files changed in PR
    comment PR_ID MSG   Post a comment to PR
    current             Get PR for current branch
    help                Show this help message

PR_ID can be:
    - PR number (e.g., 123)
    - PR URL (e.g., https://github.com/owner/repo/pull/123)
    - Branch name (e.g., feature/my-branch)

Examples:
    $0 check
    $0 info 123
    $0 diff https://github.com/owner/repo/pull/123
    $0 files feature/my-branch
    $0 comment 123 "Great work!"

As a library:
    source /path/to/github-integration.sh
    diff=\$(github_get_pr_diff 123)
    github_post_comment 123 "\$review_markdown"
EOF
            ;;
        *)
            echo "Unknown command: $COMMAND" >&2
            echo "Run '$0 help' for usage" >&2
            exit 1
            ;;
    esac
fi
