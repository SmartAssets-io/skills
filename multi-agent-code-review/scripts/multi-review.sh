#!/usr/bin/env bash
#
# multi-review.sh - Multi-agent PR/MR review orchestrator
#
# This script orchestrates multi-agent code reviews by:
# 1. Detecting platform (GitHub/GitLab)
# 2. Fetching PR/MR diff and metadata
# 3. Dispatching reviews to multiple LLM providers in parallel
# 4. Aggregating results and calculating consensus
# 5. Formatting and posting the review comment
#
# Usage:
#   multi-review.sh [OPTIONS] [PR_URL|MR_URL|BRANCH]
#
# Modes:
#   --create     Create a new PR/MR and add review
#   --review     Add review to existing PR/MR (default)
#
# Options:
#   --providers LIST    Comma-separated provider list
#   --no-post           Don't post, just output to stdout
#   --json              Output raw JSON results
#   --verbose           Show detailed progress
#   --dry-run           Show what would be done
#   --help, -h          Show help message
#
# Dependencies:
#   - jq (required)
#   - curl (required)
#   - gh CLI (for GitHub) or glab CLI (for GitLab)
#

set -euo pipefail

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Source libraries
source "${LIB_DIR}/review-providers.sh"
source "${LIB_DIR}/review-aggregator.sh"
source "${LIB_DIR}/github-integration.sh"
source "${LIB_DIR}/gitlab-integration.sh"

# Configuration
MODE="review"              # review or create
TARGET=""                  # PR/MR URL, number, or branch
PROVIDERS_LIST=""          # Comma-separated provider list (empty = all enabled)
NO_POST=false              # Don't post to PR/MR
OUTPUT_JSON=false          # Output raw JSON
CREATE_TITLE=""            # PR/MR title for --create mode (auto-generated if empty)
CREATE_TARGET_BRANCH=""    # Target branch for --create mode (auto-detected if empty)
VERBOSE=false              # Verbose output
DRY_RUN=false              # Dry run mode
MAX_DIFF_SIZE=100000       # Max diff size before chunking (100KB)

# MCP mode - external orchestrator provides diff/context and handles posting
MCP_MODE=false             # Enable MCP mode
DIFF_FILE=""               # Path to file containing diff (for MCP mode)
CONTEXT_FILE=""            # Path to file containing context JSON (for MCP mode)
PR_INFO_FILE=""            # Path to file containing PR/MR info JSON (for MCP mode)

# Exit codes
EXIT_SUCCESS=0
EXIT_ERROR=1
EXIT_NO_PROVIDERS=2
EXIT_PLATFORM_UNKNOWN=3
EXIT_PR_NOT_FOUND=4
EXIT_NEEDS_WORK=10         # Review completed, verdict: needs_work

#
# Show help message
#
show_help() {
    cat <<EOF
multi-review.sh - Multi-agent PR/MR code review

Usage: $(basename "$0") [OPTIONS] [PR_URL|MR_URL|BRANCH]

If no target is specified, reviews the PR/MR for the current branch.

Modes:
    --create        Create a new PR/MR and add multi-agent review
    --review        Add review to existing PR/MR (default)

Options:
    --providers LIST    Comma-separated list of providers to use
                        (default: all enabled providers)
    --title TITLE       PR/MR title for --create mode (auto-generated if omitted)
    --target-branch BR  Target/base branch for --create mode (auto-detected if omitted)
    --no-post           Don't post comment, output to stdout
    --json              Output raw JSON results
    --verbose           Show detailed progress
    --dry-run           Show what would be done without executing
    --help, -h          Show this help message

MCP Mode (for external orchestration by Claude Code, etc.):
    --mcp               Enable MCP mode (skip platform auth checks)
    --diff-file FILE    Read diff from file instead of fetching
    --context-file FILE Read context JSON from file
    --pr-info-file FILE Read PR/MR info JSON from file

Target Formats:
    GitHub:
        - PR number: 123
        - PR URL: https://github.com/owner/repo/pull/123
        - Branch name: feature/my-branch

    GitLab:
        - MR number: 123
        - MR URL: https://gitlab.com/group/project/-/merge_requests/123
        - Branch name: feature/my-branch

Examples:
    $(basename "$0") 123
    $(basename "$0") --review https://github.com/owner/repo/pull/123
    $(basename "$0") --providers anthropic,openai feature/my-branch
    $(basename "$0") --no-post --json
    $(basename "$0") --create --verbose

Environment Variables:
    ANTHROPIC_API_KEY     Required for Anthropic Claude provider
    OPENAI_API_KEY        Required for OpenAI ChatGPT provider
    GOOGLE_API_KEY        Required for Google Gemini provider (or GEMINI_API_KEY)
    GEMINI_API_KEY        Alternative to GOOGLE_API_KEY
    XAI_API_KEY           Required for xAI Grok provider (or GROK_API_KEY)
    GROK_API_KEY          Alternative to XAI_API_KEY
    AWS_ACCESS_KEY_ID     Required for Amazon Bedrock Nova provider
    AWS_SECRET_ACCESS_KEY Required for Amazon Bedrock Nova provider
    AWS_REGION            AWS region for Bedrock (default: us-east-1)
    BEDROCK_MODEL         Bedrock model (default: us.amazon.nova-pro-v1:0)
    OLLAMA_HOST           Ollama endpoint (default: http://localhost:11434)
    SA_REVIEW_CONFIG      Path to config file (~/.sa-review-agents.yaml)

Exit Codes:
    0   Success, PR/MR approved
    1   General error
    2   No providers available
    3   Platform not detected
    4   PR/MR not found
    10  Success, but verdict is needs_work

EOF
}

#
# Log functions
#
log_info() {
    echo "[INFO] $1" >&2
}

log_success() {
    echo "[OK] $1" >&2
}

log_warning() {
    echo "[WARN] $1" >&2
}

log_error() {
    echo "[ERROR] $1" >&2
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] $1" >&2
    fi
}

#
# Progress indicator
#
show_progress() {
    local message="$1"
    echo -n "$message..." >&2
}

show_progress_done() {
    echo " done" >&2
}

#
# Truncate diff to fit within size limit
# Prioritizes keeping file headers and recent changes visible
#
truncate_diff() {
    local diff="$1"
    local max_size="$2"
    local diff_size=${#diff}

    if [[ $diff_size -le $max_size ]]; then
        echo "$diff"
        return 0
    fi

    # Strategy: Keep first part (file list overview) and truncate intelligently
    # Reserve space for truncation notice
    local notice_size=200
    local available_size=$((max_size - notice_size))

    # Get list of changed files for summary
    local file_list
    file_list=$(echo "$diff" | grep -E '^diff --git|^\+\+\+|^---' | head -50)
    local file_count
    file_count=$(echo "$diff" | grep -c '^diff --git' || echo "0")

    # Calculate how much of the diff we can keep
    # Take the first portion up to available_size
    local truncated_diff
    truncated_diff=$(echo "$diff" | head -c "$available_size")

    # Find the last complete file boundary to avoid cutting mid-file
    # Look for the last "diff --git" marker we can include
    local last_diff_pos
    last_diff_pos=$(echo "$truncated_diff" | grep -b -o '^diff --git' | tail -1 | cut -d: -f1 || echo "0")

    # If we found a boundary, truncate there for cleaner output
    if [[ -n "$last_diff_pos" ]] && [[ "$last_diff_pos" -gt $((available_size / 2)) ]]; then
        truncated_diff=$(echo "$diff" | head -c "$last_diff_pos")
    fi

    # Add truncation notice
    cat <<EOF
${truncated_diff}

... [TRUNCATED - Diff too large for API context]

=== TRUNCATION SUMMARY ===
Original size: ${diff_size} bytes
Truncated to: ${#truncated_diff} bytes
Total files changed: ${file_count}
Files shown: Partial (first files in diff)

Note: This review covers only the first portion of the diff.
For complete review, consider reviewing in smaller batches by file.
EOF
}

#
# Detect platform from remote URL or target
#
detect_platform() {
    local target="${1:-}"

    # Check target URL first
    if [[ "$target" == *"github.com"* ]]; then
        echo "github"
        return 0
    fi

    if [[ "$target" == *"gitlab"* ]]; then
        echo "gitlab"
        return 0
    fi

    # Check remote URL
    local remote_url
    remote_url=$(git config --get remote.origin.url 2>/dev/null || echo "")

    if [[ "$remote_url" == *"github.com"* ]]; then
        echo "github"
        return 0
    fi

    if [[ "$remote_url" == *"gitlab"* ]]; then
        echo "gitlab"
        return 0
    fi

    echo "unknown"
    return 1
}

#
# Check platform tools availability
#
check_platform_tools() {
    local platform="$1"

    case "$platform" in
        github)
            if [[ $(github_check) != "true" ]]; then
                log_error "GitHub CLI (gh) not available or not authenticated"
                log_info "Install: https://cli.github.com/"
                log_info "Authenticate: gh auth login"
                return 1
            fi
            ;;
        gitlab)
            if [[ $(gitlab_check) != "true" ]]; then
                log_error "GitLab CLI (glab) or API token not available"
                log_info "Install glab: https://gitlab.com/gitlab-org/cli"
                log_info "Or set GITLAB_TOKEN environment variable"
                return 1
            fi
            ;;
        *)
            log_error "Unknown platform"
            return 1
            ;;
    esac

    return 0
}

#
# Get PR/MR diff based on platform
#
get_diff() {
    local platform="$1"
    local target="$2"

    case "$platform" in
        github)
            github_get_pr_diff "$target"
            ;;
        gitlab)
            gitlab_get_mr_diff "$target"
            ;;
    esac
}

#
# Get PR/MR info based on platform
#
get_info() {
    local platform="$1"
    local target="$2"

    case "$platform" in
        github)
            github_get_pr_info "$target"
            ;;
        gitlab)
            gitlab_get_mr_info "$target"
            ;;
    esac
}

#
# Build review context based on platform
#
build_context() {
    local platform="$1"
    local pr_info="$2"

    case "$platform" in
        github)
            github_build_review_context "$pr_info"
            ;;
        gitlab)
            gitlab_build_review_context "$pr_info"
            ;;
    esac
}

#
# Post review comment based on platform
#
post_review() {
    local platform="$1"
    local target="$2"
    local comment="$3"
    local verdict="${4:-abstain}"

    case "$platform" in
        github)
            github_post_review "$target" "$comment" "$verdict"
            ;;
        gitlab)
            gitlab_post_comment "$target" "$comment"
            # GitLab approval is a separate operation
            if [[ "$verdict" == "approve" ]]; then
                gitlab_approve_mr "$target" 2>/dev/null || true
            fi
            ;;
    esac
}

#
# Get current branch PR/MR
#
get_current_pr() {
    local platform="$1"

    case "$platform" in
        github)
            github_get_current_pr
            ;;
        gitlab)
            gitlab_get_current_mr
            ;;
    esac
}

#
# Parse command line arguments
#
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --create)
                MODE="create"
                shift
                ;;
            --review)
                MODE="review"
                shift
                ;;
            --title)
                CREATE_TITLE="$2"
                shift 2
                ;;
            --target-branch)
                CREATE_TARGET_BRANCH="$2"
                shift 2
                ;;
            --providers)
                PROVIDERS_LIST="$2"
                shift 2
                ;;
            --no-post)
                NO_POST=true
                shift
                ;;
            --json)
                OUTPUT_JSON=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --mcp)
                MCP_MODE=true
                export GITLAB_MCP_MODE=true
                shift
                ;;
            --diff-file)
                DIFF_FILE="$2"
                shift 2
                ;;
            --context-file)
                CONTEXT_FILE="$2"
                shift 2
                ;;
            --pr-info-file)
                PR_INFO_FILE="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit $EXIT_SUCCESS
                ;;
            -*)
                log_error "Unknown option: $1"
                show_help
                exit $EXIT_ERROR
                ;;
            *)
                TARGET="$1"
                shift
                ;;
        esac
    done
}

#
# Main function
#
main() {
    parse_args "$@"

    # Initialize providers
    log_verbose "Initializing providers..."
    providers_init

    # Check for available providers
    local enabled_count
    enabled_count=$(providers_list_enabled | wc -l | tr -d ' ')

    if [[ $enabled_count -eq 0 ]]; then
        log_error "No LLM providers available"
        log_info "Set at least one API key:"
        log_info "  ANTHROPIC_API_KEY, OPENAI_API_KEY, GOOGLE_API_KEY, or XAI_API_KEY"
        exit $EXIT_NO_PROVIDERS
    fi

    log_info "Found $enabled_count enabled provider(s): $(providers_list_enabled | tr '\n' ' ')"

    # MCP mode - use provided files instead of fetching
    if [[ "$MCP_MODE" == "true" ]]; then
        log_info "MCP mode enabled - using provided files"

        # Validate required files
        if [[ -z "$DIFF_FILE" ]] || [[ ! -f "$DIFF_FILE" ]]; then
            log_error "MCP mode requires --diff-file with a valid file"
            exit $EXIT_ERROR
        fi

        # Read diff from file
        local diff
        diff=$(cat "$DIFF_FILE")
        local diff_size=${#diff}
        log_verbose "Diff size: $diff_size bytes (from file)"

        # Read context from file or generate minimal context
        local context
        if [[ -n "$CONTEXT_FILE" ]] && [[ -f "$CONTEXT_FILE" ]]; then
            context=$(cat "$CONTEXT_FILE")
        else
            context='{"platform": "gitlab", "repo_name": "unknown", "pr_title": "MR Review"}'
        fi
        log_verbose "Context: $context"

        # Read PR info from file or use minimal info
        local pr_info
        if [[ -n "$PR_INFO_FILE" ]] && [[ -f "$PR_INFO_FILE" ]]; then
            pr_info=$(cat "$PR_INFO_FILE")
        else
            pr_info='{"title": "MR Review", "additions": 0, "deletions": 0}'
        fi

        # Skip to review execution (no posting in MCP mode - orchestrator handles it)
        NO_POST=true

    else
        # Standard mode - detect platform and fetch from API

        # Detect platform
        local platform
        platform=$(detect_platform "$TARGET")

        if [[ "$platform" == "unknown" ]]; then
            log_error "Could not detect platform (GitHub/GitLab)"
            log_info "Ensure you're in a git repository with a GitHub or GitLab remote"
            exit $EXIT_PLATFORM_UNKNOWN
        fi

        log_info "Detected platform: $platform"

        # Check platform tools
        if ! check_platform_tools "$platform"; then
            exit $EXIT_ERROR
        fi

        # Create mode: create PR/MR first, then fall through to review
        if [[ "$MODE" == "create" ]]; then
            local current_branch
            current_branch=$(git branch --show-current 2>/dev/null)

            if [[ -z "$current_branch" ]]; then
                log_error "Not on a branch (detached HEAD)"
                exit $EXIT_ERROR
            fi

            # Verify branch is pushed to remote
            if ! git rev-parse --verify "origin/$current_branch" &>/dev/null; then
                log_error "Branch '$current_branch' not pushed to remote. Push first."
                exit $EXIT_ERROR
            fi

            # Auto-detect target branch if not specified (default: dev)
            if [[ -z "$CREATE_TARGET_BRANCH" ]]; then
                CREATE_TARGET_BRANCH="dev"
            fi

            # Auto-generate title if not specified
            if [[ -z "$CREATE_TITLE" ]]; then
                CREATE_TITLE=$(echo "$current_branch" | sed 's/[-_]/ /g')
            fi

            log_info "Creating $platform PR/MR: '$CREATE_TITLE' ($current_branch -> $CREATE_TARGET_BRANCH)"

            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would create $platform PR/MR: '$CREATE_TITLE' ($current_branch -> $CREATE_TARGET_BRANCH)"
                log_info "[DRY RUN] Would then review the new PR/MR"
                exit $EXIT_SUCCESS
            fi

            local create_output
            case "$platform" in
                github)
                    create_output=$(github_create_pr "$CREATE_TITLE" "" "$CREATE_TARGET_BRANCH" "$current_branch")
                    # gh pr create outputs the PR URL; extract number from it or use gh pr view
                    TARGET=$(echo "$create_output" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+' || true)
                    if [[ -z "$TARGET" ]]; then
                        TARGET=$(gh pr view --json number -q '.number' 2>/dev/null || true)
                    fi
                    ;;
                gitlab)
                    create_output=$(gitlab_create_mr "$CREATE_TITLE" "" "$CREATE_TARGET_BRANCH" "$current_branch")
                    # glab mr create outputs a URL like .../merge_requests/7; extract the number
                    TARGET=$(echo "$create_output" | grep -oE 'merge_requests/[0-9]+' | grep -oE '[0-9]+' | tail -1 || true)
                    if [[ -z "$TARGET" ]]; then
                        # Fallback: query the MR for current branch
                        TARGET=$(glab mr view --json iid -q '.iid' 2>/dev/null || true)
                    fi
                    ;;
            esac

            if [[ -z "$TARGET" ]]; then
                log_error "Failed to create PR/MR"
                log_verbose "Create output: $create_output"
                exit $EXIT_ERROR
            fi

            log_success "Created $platform PR/MR #$TARGET"
            # Fall through to review logic below
        fi

        # Determine target (for review mode, or after create mode set TARGET)
        if [[ -z "$TARGET" ]]; then
            log_verbose "No target specified, using current branch..."
            local current_pr
            current_pr=$(get_current_pr "$platform")

            if echo "$current_pr" | jq -e '.error' >/dev/null 2>&1; then
                log_error "No PR/MR found for current branch"
                log_info "Create a PR/MR first, or specify a target"
                exit $EXIT_PR_NOT_FOUND
            fi

            # Extract PR/MR number
            case "$platform" in
                github)
                    TARGET=$(echo "$current_pr" | jq -r '.number')
                    ;;
                gitlab)
                    TARGET=$(echo "$current_pr" | jq -r '.iid')
                    ;;
            esac
        fi

        log_info "Target: $TARGET"

        # Dry run mode
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would review $platform PR/MR $TARGET"
            log_info "[DRY RUN] Providers: ${PROVIDERS_LIST:-all enabled}"
            log_info "[DRY RUN] Post to PR/MR: $(if [[ "$NO_POST" == "true" ]]; then echo "no"; else echo "yes"; fi)"
            exit $EXIT_SUCCESS
        fi

        # Get PR/MR info
        show_progress "Fetching PR/MR info"
        local pr_info
        pr_info=$(get_info "$platform" "$TARGET")
        show_progress_done

        if echo "$pr_info" | jq -e '.error' >/dev/null 2>&1; then
            log_error "Failed to fetch PR/MR info: $(echo "$pr_info" | jq -r '.error')"
            exit $EXIT_PR_NOT_FOUND
        fi

        log_verbose "PR/MR Title: $(echo "$pr_info" | jq -r '.title // "Unknown"')"

        # Get diff
        show_progress "Fetching diff"
        local diff
        diff=$(get_diff "$platform" "$TARGET")
        show_progress_done

        if [[ -z "$diff" ]]; then
            log_error "Failed to fetch diff"
            exit $EXIT_ERROR
        fi

        local diff_size=${#diff}
        log_verbose "Diff size: $diff_size bytes"

        # Handle oversized diffs
        if [[ $diff_size -gt $MAX_DIFF_SIZE ]]; then
            log_warning "Diff size ($diff_size bytes) exceeds limit ($MAX_DIFF_SIZE bytes)"
            log_info "Truncating diff to fit API context limits..."
            diff=$(truncate_diff "$diff" "$MAX_DIFF_SIZE")
            local new_size=${#diff}
            log_info "Truncated diff from $diff_size to $new_size bytes"
        fi

        # Build context
        local context
        context=$(build_context "$platform" "$pr_info")
        log_verbose "Context: $context"
    fi

    # Execute parallel reviews
    show_progress "Running multi-agent review"
    local reviews_result
    reviews_result=$(providers_execute_parallel "$diff" "$context" "$PROVIDERS_LIST")
    show_progress_done

    # Extract reviews array
    local reviews
    reviews=$(echo "$reviews_result" | jq '.reviews')

    # Aggregate results
    show_progress "Aggregating results"
    local aggregated
    aggregated=$(aggregate_reviews "$reviews")
    show_progress_done

    # Get verdict
    local verdict
    verdict=$(echo "$aggregated" | jq -r '.consensus.verdict')
    local agreement
    agreement=$(echo "$aggregated" | jq -r '.consensus.agreement')

    log_info "Verdict: $verdict (agreement: $(echo "scale=0; $agreement * 100" | bc)%)"

    # Generate markdown output
    local additions deletions
    additions=$(echo "$pr_info" | jq -r '.additions // 0')
    deletions=$(echo "$pr_info" | jq -r '.deletions // 0')

    local markdown
    markdown=$(format_markdown "$aggregated")

    # Output based on options
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        echo "$aggregated" | jq '.'
    elif [[ "$NO_POST" == "true" ]]; then
        echo "$markdown"
    else
        # Post to PR/MR
        show_progress "Posting review comment"
        local post_result
        post_result=$(post_review "$platform" "$TARGET" "$markdown" "$verdict")
        show_progress_done

        log_success "Review posted to $platform PR/MR $TARGET"

        # Get PR/MR URL
        local pr_url=""
        case "$platform" in
            github)
                pr_url=$(github_get_pr_url "$TARGET")
                ;;
            gitlab)
                pr_url=$(gitlab_get_mr_url "$TARGET")
                ;;
        esac

        if [[ -n "$pr_url" ]]; then
            log_info "URL: $pr_url"
        fi

        # Emit JSON summary to stderr for agent parsing (terminal synopsis)
        echo "$aggregated" | jq -c --arg url "$pr_url" --arg target "$TARGET" \
            --arg platform "$platform" \
            '. + {url: $url, target: $target, platform: $platform}' >&2
    fi

    # Exit with appropriate code based on verdict
    if [[ "$verdict" == "needs_work" ]]; then
        exit $EXIT_NEEDS_WORK
    fi

    exit $EXIT_SUCCESS
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
