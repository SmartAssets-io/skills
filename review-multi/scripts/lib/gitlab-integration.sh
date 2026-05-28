#!/usr/bin/env bash
#
# gitlab-integration.sh - GitLab MR integration for multi-agent reviews
#
# This library provides:
# 1. GitLab MR diff extraction via glab CLI or API
# 2. MR creation and comment posting
# 3. MR metadata fetching
# 4. Review comment formatting
#
# Dependencies:
#   - glab CLI (GitLab CLI) or curl for API - At least one required
#   - jq - Required for JSON manipulation
#
# Usage:
#   source /path/to/gitlab-integration.sh
#   diff=$(gitlab_get_mr_diff 123)
#   gitlab_post_review_comment 123 "$markdown"
#

# Prevent re-sourcing
if [[ -n "${GITLAB_INTEGRATION_LOADED:-}" ]]; then
    return 0
fi
GITLAB_INTEGRATION_LOADED=1

# Configuration
GITLAB_HOST="${GITLAB_HOST:-https://gitlab.com}"
GITLAB_API_VERSION="${GITLAB_API_VERSION:-v4}"

# MCP mode flag - when true, assumes MCP will handle GitLab operations
GITLAB_MCP_MODE="${GITLAB_MCP_MODE:-false}"

#
# Check if glab CLI is available and authenticated
#
gitlab_check_glab() {
    # Check if glab is installed
    if ! command -v glab >/dev/null 2>&1; then
        echo "false"
        return 1
    fi

    # Check if glab is authenticated
    if ! glab auth status >/dev/null 2>&1; then
        echo "false"
        return 1
    fi

    echo "true"
    return 0
}

#
# Check if GitLab API token is available
#
gitlab_check_api() {
    if [[ -n "${GITLAB_TOKEN:-}" ]] || [[ -n "${GITLAB_PRIVATE_TOKEN:-}" ]]; then
        echo "true"
        return 0
    fi
    echo "false"
    return 1
}

#
# Get GitLab API token
#
gitlab_get_token() {
    echo "${GITLAB_TOKEN:-${GITLAB_PRIVATE_TOKEN:-}}"
}

#
# Check if MCP mode is enabled
#
gitlab_check_mcp() {
    if [[ "$GITLAB_MCP_MODE" == "true" ]]; then
        echo "true"
        return 0
    fi
    echo "false"
    return 1
}

#
# Check if GitLab integration is available (MCP, glab, or API)
#
gitlab_check() {
    # MCP mode - external orchestrator handles GitLab operations
    if [[ $(gitlab_check_mcp) == "true" ]]; then
        echo "true"
        return 0
    fi

    if [[ $(gitlab_check_glab) == "true" ]]; then
        echo "true"
        return 0
    fi

    if [[ $(gitlab_check_api) == "true" ]]; then
        echo "true"
        return 0
    fi

    echo "false"
    return 1
}

#
# Get current repository info (project path)
#
gitlab_get_project_path() {
    local remote_url
    remote_url=$(git config --get remote.origin.url 2>/dev/null || echo "")

    if [[ -z "$remote_url" ]]; then
        echo ""
        return 1
    fi

    # Extract project path from various URL formats
    local project_path=""

    if [[ "$remote_url" == *"gitlab"* ]]; then
        # HTTPS: https://gitlab.com/group/project.git
        # SSH: git@gitlab.com:group/project.git
        project_path=$(echo "$remote_url" | sed -E 's|.*gitlab\.[^/:]*/||' | sed -E 's|.*gitlab\.[^:]*:||' | sed 's|\.git$||')
    fi

    echo "$project_path"
}

#
# URL-encode a string for API calls
#
gitlab_url_encode() {
    local string="$1"
    echo "$string" | jq -Rr @uri
}

#
# Parse MR identifier (number or URL)
#
gitlab_parse_mr_id() {
    local input="$1"

    # If numeric, return as-is
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        echo "$input"
        return 0
    fi

    # If URL, extract MR number
    if [[ "$input" =~ gitlab.*/-/merge_requests/([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    # If branch name, find MR for that branch
    if [[ $(gitlab_check_glab) == "true" ]]; then
        local mr_iid
        mr_iid=$(glab mr view --output json -- "$input" 2>/dev/null | jq -r '.iid // empty')

        if [[ -n "$mr_iid" ]]; then
            echo "$mr_iid"
            return 0
        fi
    fi

    echo ""
    return 1
}

#
# Make GitLab API request
#
# Uses temp file for POST data to avoid shell injection risks
# and handle large payloads safely.
#
gitlab_api_request() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local token
    token=$(gitlab_get_token)

    local project_path
    project_path=$(gitlab_get_project_path)

    if [[ -z "$token" ]]; then
        echo '{"error": "No GitLab API token available"}'
        return 1
    fi

    local url="${GITLAB_HOST}/api/${GITLAB_API_VERSION}/${endpoint}"

    if [[ -n "$data" ]]; then
        # Write data to temp file to avoid shell injection and handle special characters safely
        local temp_file
        temp_file=$(mktemp)
        printf '%s' "$data" > "$temp_file"

        curl -s -X "$method" "$url" \
            -H "PRIVATE-TOKEN: $token" \
            -H "Content-Type: application/json" \
            --data-binary "@${temp_file}"

        local curl_exit=$?
        rm -f "$temp_file"
        return $curl_exit
    else
        curl -s -X "$method" "$url" \
            -H "PRIVATE-TOKEN: $token"
    fi
}

#
# Get MR metadata using glab
#
gitlab_get_mr_info_glab() {
    local mr_id="$1"

    local mr_iid
    mr_iid=$(gitlab_parse_mr_id "$mr_id")

    if [[ -z "$mr_iid" ]]; then
        cat <<EOF
{"error": "Could not parse MR identifier: $mr_id"}
EOF
        return 1
    fi

    glab mr view --output json -- "$mr_iid" 2>/dev/null || \
    echo '{"error": "Failed to fetch MR info"}'
}

#
# Get MR metadata using API
#
gitlab_get_mr_info_api() {
    local mr_id="$1"

    local mr_iid
    mr_iid=$(gitlab_parse_mr_id "$mr_id")

    if [[ -z "$mr_iid" ]]; then
        cat <<EOF
{"error": "Could not parse MR identifier: $mr_id"}
EOF
        return 1
    fi

    local project_path
    project_path=$(gitlab_get_project_path)
    local encoded_path
    encoded_path=$(gitlab_url_encode "$project_path")

    gitlab_api_request "GET" "projects/${encoded_path}/merge_requests/${mr_iid}"
}

#
# Get MR metadata (auto-selects method)
#
gitlab_get_mr_info() {
    local mr_id="$1"

    if [[ $(gitlab_check_glab) == "true" ]]; then
        gitlab_get_mr_info_glab "$mr_id"
    else
        gitlab_get_mr_info_api "$mr_id"
    fi
}

#
# Get MR diff using glab
#
gitlab_get_mr_diff_glab() {
    local mr_id="$1"

    local mr_iid
    mr_iid=$(gitlab_parse_mr_id "$mr_id")

    if [[ -z "$mr_iid" ]]; then
        echo "Error: Could not parse MR identifier: $mr_id" >&2
        return 1
    fi

    glab mr diff -- "$mr_iid" 2>/dev/null
}

#
# Get MR diff using API
#
gitlab_get_mr_diff_api() {
    local mr_id="$1"

    local mr_iid
    mr_iid=$(gitlab_parse_mr_id "$mr_id")

    if [[ -z "$mr_iid" ]]; then
        echo "Error: Could not parse MR identifier: $mr_id" >&2
        return 1
    fi

    local project_path
    project_path=$(gitlab_get_project_path)
    local encoded_path
    encoded_path=$(gitlab_url_encode "$project_path")

    # Get changes and format as unified diff
    local changes
    changes=$(gitlab_api_request "GET" "projects/${encoded_path}/merge_requests/${mr_iid}/changes")

    # Extract diffs from changes
    echo "$changes" | jq -r '.changes[] | "diff --git a/\(.old_path) b/\(.new_path)\n--- a/\(.old_path)\n+++ b/\(.new_path)\n\(.diff)"'
}

#
# Get MR diff (auto-selects method)
#
gitlab_get_mr_diff() {
    local mr_id="$1"

    if [[ $(gitlab_check_glab) == "true" ]]; then
        gitlab_get_mr_diff_glab "$mr_id"
    else
        gitlab_get_mr_diff_api "$mr_id"
    fi
}

#
# Get list of files changed in MR
#
gitlab_get_mr_files() {
    local mr_id="$1"

    local mr_info
    if [[ $(gitlab_check_glab) == "true" ]]; then
        mr_info=$(glab mr view --output json -- "$mr_id" 2>/dev/null)
    else
        mr_info=$(gitlab_get_mr_info_api "$mr_id")
    fi

    local mr_iid
    mr_iid=$(gitlab_parse_mr_id "$mr_id")

    local project_path
    project_path=$(gitlab_get_project_path)
    local encoded_path
    encoded_path=$(gitlab_url_encode "$project_path")

    # Get changes for file list
    local changes
    changes=$(gitlab_api_request "GET" "projects/${encoded_path}/merge_requests/${mr_iid}/changes" 2>/dev/null)

    if [[ -n "$changes" ]]; then
        echo "$changes" | jq -r '.changes[].new_path'
    fi
}

#
# Build review context from MR info
#
gitlab_build_review_context() {
    local mr_info="$1"

    local repo_name mr_title mr_description target_branch file_count additions deletions

    repo_name=$(gitlab_get_project_path)
    mr_title=$(echo "$mr_info" | jq -r '.title // "Unknown"')
    # Allow up to 4000 chars for description to give reviewers full context
    mr_description=$(echo "$mr_info" | jq -r '.description // ""' | head -c 4000)
    target_branch=$(echo "$mr_info" | jq -r '.target_branch // "main"')

    # Get stats from diff_stats or changes_count
    local changes_count
    changes_count=$(echo "$mr_info" | jq -r '.changes_count // "0"')

    cat <<EOF
{
    "repo_name": "$repo_name",
    "pr_title": "$mr_title",
    "pr_description": $(echo "$mr_description" | jq -Rs '.'),
    "target_branch": "$target_branch",
    "file_count": "$changes_count",
    "platform": "gitlab"
}
EOF
}

#
# Post a note (comment) to an MR using glab
#
gitlab_post_comment_glab() {
    local mr_id="$1"
    local comment="$2"

    local mr_iid
    mr_iid=$(gitlab_parse_mr_id "$mr_id")

    if [[ -z "$mr_iid" ]]; then
        echo "Error: Could not parse MR identifier: $mr_id" >&2
        return 1
    fi

    # Write comment to temp file
    local temp_file
    temp_file=$(mktemp)
    echo "$comment" > "$temp_file"

    glab mr note --message "$(cat "$temp_file")" -- "$mr_iid" 2>&1
    local exit_code=$?

    rm -f "$temp_file"

    return $exit_code
}

#
# Post a note (comment) to an MR using API
#
gitlab_post_comment_api() {
    local mr_id="$1"
    local comment="$2"

    local mr_iid
    mr_iid=$(gitlab_parse_mr_id "$mr_id")

    if [[ -z "$mr_iid" ]]; then
        echo "Error: Could not parse MR identifier: $mr_id" >&2
        return 1
    fi

    local project_path
    project_path=$(gitlab_get_project_path)
    local encoded_path
    encoded_path=$(gitlab_url_encode "$project_path")

    # Escape comment for JSON
    local escaped_comment
    escaped_comment=$(echo "$comment" | jq -Rs '.')

    gitlab_api_request "POST" \
        "projects/${encoded_path}/merge_requests/${mr_iid}/notes" \
        "{\"body\": $escaped_comment}"
}

#
# Post a comment to an MR (auto-selects method)
#
gitlab_post_comment() {
    local mr_id="$1"
    local comment="$2"

    if [[ $(gitlab_check_glab) == "true" ]]; then
        gitlab_post_comment_glab "$mr_id" "$comment"
    else
        gitlab_post_comment_api "$mr_id" "$comment"
    fi
}

#
# Approve an MR (GitLab Premium feature)
#
gitlab_approve_mr() {
    local mr_id="$1"

    local mr_iid
    mr_iid=$(gitlab_parse_mr_id "$mr_id")

    if [[ -z "$mr_iid" ]]; then
        echo "Error: Could not parse MR identifier: $mr_id" >&2
        return 1
    fi

    if [[ $(gitlab_check_glab) == "true" ]]; then
        glab mr approve -- "$mr_iid" 2>&1
    else
        local project_path
        project_path=$(gitlab_get_project_path)
        local encoded_path
        encoded_path=$(gitlab_url_encode "$project_path")

        gitlab_api_request "POST" \
            "projects/${encoded_path}/merge_requests/${mr_iid}/approve"
    fi
}

#
# Create a new MR
#
gitlab_create_mr() {
    local title="$1"
    local body="$2"
    local target="${3:-main}"
    local source="${4:-}"

    # Get current branch if source not specified
    if [[ -z "$source" ]]; then
        source=$(git branch --show-current 2>/dev/null)
    fi

    if [[ -z "$source" ]]; then
        echo "Error: Could not determine source branch" >&2
        return 1
    fi

    if [[ $(gitlab_check_glab) == "true" ]]; then
        # Write body to temp file
        local temp_file
        temp_file=$(mktemp)
        echo "$body" > "$temp_file"

        glab mr create --title "$title" --description "$(cat "$temp_file")" \
            --target-branch "$target" --source-branch "$source" 2>&1
        local exit_code=$?

        rm -f "$temp_file"
        return $exit_code
    else
        local project_path
        project_path=$(gitlab_get_project_path)
        local encoded_path
        encoded_path=$(gitlab_url_encode "$project_path")

        local escaped_title escaped_body escaped_source escaped_target
        escaped_title=$(echo "$title" | jq -Rs '.')
        escaped_body=$(echo "$body" | jq -Rs '.')
        escaped_source=$(echo "$source" | jq -Rs '.')
        escaped_target=$(echo "$target" | jq -Rs '.')

        gitlab_api_request "POST" \
            "projects/${encoded_path}/merge_requests" \
            "{\"source_branch\": $escaped_source, \"target_branch\": $escaped_target, \"title\": $escaped_title, \"description\": $escaped_body}"
    fi
}

#
# Get MR for current branch
#
gitlab_get_current_mr() {
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null)

    if [[ -z "$current_branch" ]]; then
        echo '{"error": "Not on a branch"}'
        return 1
    fi

    if [[ $(gitlab_check_glab) == "true" ]]; then
        glab mr view --output json -- "$current_branch" 2>/dev/null || \
        echo '{"error": "No MR for current branch"}'
    else
        local project_path
        project_path=$(gitlab_get_project_path)
        local encoded_path
        encoded_path=$(gitlab_url_encode "$project_path")

        # Search for MR by source branch
        local result
        result=$(gitlab_api_request "GET" \
            "projects/${encoded_path}/merge_requests?source_branch=${current_branch}&state=opened")

        if echo "$result" | jq -e '.[0]' >/dev/null 2>&1; then
            echo "$result" | jq '.[0]'
        else
            echo '{"error": "No MR for current branch"}'
        fi
    fi
}

#
# Check if current branch has an open MR
#
gitlab_has_open_mr() {
    local mr_info
    mr_info=$(gitlab_get_current_mr)

    if echo "$mr_info" | jq -e '.iid' >/dev/null 2>&1; then
        local state
        state=$(echo "$mr_info" | jq -r '.state // "unknown"')

        if [[ "$state" == "opened" ]]; then
            echo "true"
            return 0
        fi
    fi

    echo "false"
    return 1
}

#
# Get MR URL
#
gitlab_get_mr_url() {
    local mr_id="$1"

    local mr_info
    mr_info=$(gitlab_get_mr_info "$mr_id")

    echo "$mr_info" | jq -r '.web_url // empty'
}

#
# CLI interface when run directly
#
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    COMMAND="${1:-help}"

    case "$COMMAND" in
        check)
            echo "GitLab Integration Status:"
            if [[ $(gitlab_check_glab) == "true" ]]; then
                echo "  glab CLI: Available and authenticated"
            else
                echo "  glab CLI: Not available or not authenticated"
            fi
            if [[ $(gitlab_check_api) == "true" ]]; then
                echo "  API Token: Available"
            else
                echo "  API Token: Not set (GITLAB_TOKEN or GITLAB_PRIVATE_TOKEN)"
            fi
            echo "  Project: $(gitlab_get_project_path)"
            ;;
        info)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 info MR_NUMBER_OR_URL" >&2
                exit 1
            fi
            gitlab_get_mr_info "$2" | jq '.'
            ;;
        diff)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 diff MR_NUMBER_OR_URL" >&2
                exit 1
            fi
            gitlab_get_mr_diff "$2"
            ;;
        files)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 files MR_NUMBER_OR_URL" >&2
                exit 1
            fi
            gitlab_get_mr_files "$2"
            ;;
        comment)
            if [[ -z "${2:-}" ]] || [[ -z "${3:-}" ]]; then
                echo "Usage: $0 comment MR_NUMBER_OR_URL MESSAGE" >&2
                exit 1
            fi
            gitlab_post_comment "$2" "$3"
            ;;
        current)
            gitlab_get_current_mr | jq '.'
            ;;
        help|--help|-h)
            cat <<EOF
gitlab-integration.sh - GitLab MR integration for multi-agent reviews

Usage: $0 <command> [args]

Commands:
    check               Check if glab CLI or API token is available
    info MR_ID          Get MR metadata as JSON
    diff MR_ID          Get MR diff
    files MR_ID         List files changed in MR
    comment MR_ID MSG   Post a comment to MR
    current             Get MR for current branch
    help                Show this help message

MR_ID can be:
    - MR number/IID (e.g., 123)
    - MR URL (e.g., https://gitlab.com/group/project/-/merge_requests/123)
    - Branch name (e.g., feature/my-branch)

Environment Variables:
    GITLAB_HOST           GitLab host URL (default: https://gitlab.com)
    GITLAB_TOKEN          GitLab API token (alternative to glab)
    GITLAB_PRIVATE_TOKEN  GitLab API token (alternative name)

Examples:
    $0 check
    $0 info 123
    $0 diff https://gitlab.com/group/project/-/merge_requests/123
    $0 files feature/my-branch
    $0 comment 123 "Great work!"

As a library:
    source /path/to/gitlab-integration.sh
    diff=\$(gitlab_get_mr_diff 123)
    gitlab_post_comment 123 "\$review_markdown"
EOF
            ;;
        *)
            echo "Unknown command: $COMMAND" >&2
            echo "Run '$0 help' for usage" >&2
            exit 1
            ;;
    esac
fi
