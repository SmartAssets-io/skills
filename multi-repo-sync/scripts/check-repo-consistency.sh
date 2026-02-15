#!/usr/bin/env bash
#
# check-repo-consistency.sh - Verify multi-repo workspace consistency
#
# Checks that all repositories in the workspace have consistent branch
# and worktree state, preventing mixed-mode operations that can cause
# merge conflicts or orphaned branches.
#
# Usage:
#   check-repo-consistency.sh                    # Human-readable report
#   check-repo-consistency.sh --json             # Machine-readable JSON
#   check-repo-consistency.sh --check            # Exit code only (0=ok)
#   check-repo-consistency.sh --all              # All repos regardless
#   check-repo-consistency.sh --strict           # Hard gate: branch mismatch is fatal
#   check-repo-consistency.sh --strict=dev       # Hard gate: all repos must be on 'dev'
#   check-repo-consistency.sh --fix-suggestion   # Print fix commands
#   check-repo-consistency.sh --help / -h        # Usage info
#
# Exit codes:
#   0 - All repos consistent
#   1 - Worktree state inconsistent (mixed worktree/regular)
#   2 - Branch inconsistent (repos on different branches)
#   3 - Both worktree and branch inconsistent
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source repo-selection library (optional - graceful if missing)
if [[ -f "$SCRIPT_DIR/lib/repo-selection.sh" ]]; then
    source "$SCRIPT_DIR/lib/repo-selection.sh"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Options (set by parse_args)
OUTPUT_MODE="human"      # human | json | check
SCOPE="changes-only"     # changes-only | all
FIX_SUGGESTION=false
STRICT=false             # --strict: treat inconsistency as hard gate
STRICT_BRANCH=""         # --strict=BRANCH: require specific branch

# Collected repo data (parallel arrays)
REPO_PATHS=()
REPO_REL_PATHS=()
REPO_BRANCHES=()
REPO_WORKTREES=()
REPO_HAS_CHANGES=()

# Analysis results
MAJORITY_BRANCH=""
MAJORITY_COUNT=0
WORKTREE_COUNT=0
REGULAR_COUNT=0
WORKTREE_CONSISTENT=true
BRANCH_CONSISTENT=true
BRANCH_OUTLIERS=()       # "rel_path:branch" entries
FIX_COMMANDS=()

# --- Logging (suppressed in json/check modes) ---

log_info()    { [[ "$OUTPUT_MODE" == "human" ]] && echo -e "${BLUE}i${NC} $*" || true; }
log_success() { [[ "$OUTPUT_MODE" == "human" ]] && echo -e "${GREEN}*${NC} $*" || true; }
log_warning() { [[ "$OUTPUT_MODE" == "human" ]] && echo -e "${YELLOW}!${NC} $*" || true; }
log_error()   { [[ "$OUTPUT_MODE" == "human" ]] && echo -e "${RED}x${NC} $*" || true; }

# --- Help ---

show_help() {
    cat <<'EOF'
Usage: check-repo-consistency.sh [OPTIONS]

Verify that all repositories in a multi-repo workspace have consistent
branch and worktree state.

Options:
  --json             Machine-readable JSON output
  --check            Exit code only (no output), for scripting
  --all              Check all repos (default: only repos with changes)
  --changes-only     Only check repos with uncommitted changes (default)
  --strict           Hard gate: any inconsistency is a blocking failure
  --strict=BRANCH    Hard gate: all repos must be on the specified branch
  --fix-suggestion   Include suggested commands to fix inconsistencies
  -h, --help         Show this help message

Exit codes:
  0  All repos consistent (or no repos to check)
  1  Worktree state inconsistent (mixed worktree/regular checkouts)
  2  Branch inconsistent (repos on different branches)
  3  Both worktree and branch inconsistent

In --strict mode, any non-zero exit is treated as a blocking preflight
failure for orchestrated agentic sessions. Use --strict=BRANCH to enforce
a specific branch (e.g., --strict=dev) instead of majority-based detection.

Environment:
  MULTI_REPO=true    Explicitly enable multi-repo mode
  NO_COLOR           Disable colored output

Examples:
  check-repo-consistency.sh                  # Human report, changes-only
  check-repo-consistency.sh --json --all     # Full JSON for all repos
  check-repo-consistency.sh --check && echo "consistent"
EOF
}

# --- Core functions ---

# Check if directory is a git worktree (not a regular checkout)
# Matches is_worktree() from quick-commit.sh
is_worktree() {
    local dir="${1:-.}"
    if [ -f "$dir/.git" ]; then
        return 0
    elif git -C "$dir" rev-parse --git-dir 2>/dev/null | grep -q '/worktrees/'; then
        return 0
    fi
    return 1
}

# Check if repo has uncommitted changes
has_changes() {
    local dir="$1"
    local count
    count=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    [ "$count" -gt 0 ]
}

# Discover repos and populate parallel arrays
# Args: $1 = start directory (default: .)
collect_repo_info() {
    local start_dir="${1:-.}"

    REPO_PATHS=()
    REPO_REL_PATHS=()
    REPO_BRANCHES=()
    REPO_WORKTREES=()
    REPO_HAS_CHANGES=()

    while IFS= read -r git_dir; do
        local repo_dir
        repo_dir=$(dirname "$git_dir")

        local changes=false
        if has_changes "$repo_dir"; then
            changes=true
        fi

        # In changes-only mode, skip repos without changes
        if [[ "$SCOPE" == "changes-only" ]] && [[ "$changes" == "false" ]]; then
            continue
        fi

        local rel_path
        rel_path=$(realpath --relative-to="$start_dir" "$repo_dir" 2>/dev/null || echo "$repo_dir")
        rel_path="${rel_path#./}"  # Strip ./ prefix (macOS realpath lacks --relative-to)

        # Skip repos not in selection config (if loaded and not --all scope)
        if type -t is_repo_selected &>/dev/null && [[ -n "${REPO_SELECTION_CONFIG:-}" ]]; then
            if ! is_repo_selected "$rel_path"; then
                continue
            fi
        fi

        local branch
        branch=$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

        local wt="false"
        if is_worktree "$repo_dir"; then
            wt="true"
        fi

        REPO_PATHS+=("$repo_dir")
        REPO_REL_PATHS+=("$rel_path")
        REPO_BRANCHES+=("$branch")
        REPO_WORKTREES+=("$wt")
        REPO_HAS_CHANGES+=("$changes")
    done < <(find "$start_dir" \( -type d -o -type f \) -name ".git" -not -path "*/node_modules/*" 2>/dev/null | sort)
}

# Determine the most common branch (portable, no declare -A)
detect_majority_branch() {
    MAJORITY_BRANCH=""
    MAJORITY_COUNT=0

    if [[ ${#REPO_BRANCHES[@]} -eq 0 ]]; then
        return
    fi

    local tmp
    tmp=$(mktemp)
    printf '%s\n' "${REPO_BRANCHES[@]}" | sort | uniq -c | sort -rn > "$tmp"

    MAJORITY_COUNT=$(head -1 "$tmp" | awk '{print $1}')
    MAJORITY_BRANCH=$(head -1 "$tmp" | awk '{print $2}')
    rm -f "$tmp"
}

# Check worktree consistency across collected repos
check_worktree_consistency() {
    WORKTREE_COUNT=0
    REGULAR_COUNT=0
    WORKTREE_CONSISTENT=true

    for wt in "${REPO_WORKTREES[@]}"; do
        if [[ "$wt" == "true" ]]; then
            WORKTREE_COUNT=$((WORKTREE_COUNT + 1))
        else
            REGULAR_COUNT=$((REGULAR_COUNT + 1))
        fi
    done

    if [[ $WORKTREE_COUNT -gt 0 ]] && [[ $REGULAR_COUNT -gt 0 ]]; then
        WORKTREE_CONSISTENT=false
    fi
}

# Check branch consistency across collected repos
# In --strict=BRANCH mode, checks against the specified branch instead of majority
check_branch_consistency() {
    BRANCH_CONSISTENT=true
    BRANCH_OUTLIERS=()

    if [[ ${#REPO_BRANCHES[@]} -eq 0 ]]; then
        return
    fi

    # If --strict=BRANCH was specified, use that as the expected branch
    local expected_branch="$MAJORITY_BRANCH"
    if [[ -n "$STRICT_BRANCH" ]]; then
        expected_branch="$STRICT_BRANCH"
    fi

    for i in "${!REPO_BRANCHES[@]}"; do
        if [[ "${REPO_BRANCHES[$i]}" != "$expected_branch" ]]; then
            BRANCH_CONSISTENT=false
            BRANCH_OUTLIERS+=("${REPO_REL_PATHS[$i]}:${REPO_BRANCHES[$i]}")
        fi
    done
}

# Generate fix suggestions
generate_fix_suggestions() {
    FIX_COMMANDS=()

    # Branch fixes: checkout target branch for outliers
    local target_branch="$MAJORITY_BRANCH"
    if [[ -n "$STRICT_BRANCH" ]]; then
        target_branch="$STRICT_BRANCH"
    fi
    for entry in "${BRANCH_OUTLIERS[@]}"; do
        local path="${entry%%:*}"
        FIX_COMMANDS+=("git -C \"$path\" checkout $target_branch")
    done

    # Worktree fixes: suggest based on which is minority
    if [[ "$WORKTREE_CONSISTENT" == "false" ]]; then
        if [[ $WORKTREE_COUNT -lt $REGULAR_COUNT ]]; then
            # Worktrees are minority -- suggest removing them
            for i in "${!REPO_WORKTREES[@]}"; do
                if [[ "${REPO_WORKTREES[$i]}" == "true" ]]; then
                    FIX_COMMANDS+=("# ${REPO_REL_PATHS[$i]} is a worktree -- consider using the main checkout instead")
                fi
            done
        else
            # Regular checkouts are minority -- suggest using worktrees
            for i in "${!REPO_WORKTREES[@]}"; do
                if [[ "${REPO_WORKTREES[$i]}" == "false" ]]; then
                    FIX_COMMANDS+=("# ${REPO_REL_PATHS[$i]} is a regular checkout -- consider using a worktree for consistency")
                fi
            done
        fi
    fi
}

# Compute combined exit code
compute_exit_code() {
    local code=0
    if [[ "$WORKTREE_CONSISTENT" == "false" ]]; then
        code=$((code + 1))
    fi
    if [[ "$BRANCH_CONSISTENT" == "false" ]]; then
        code=$((code + 2))
    fi
    echo "$code"
}

# --- Output functions ---

output_human_report() {
    local total=${#REPO_PATHS[@]}
    local exit_code
    exit_code=$(compute_exit_code)

    echo ""
    echo -e "${CYAN}===========================================${NC}"
    echo -e "${CYAN} Workspace Consistency Report${NC}"
    echo -e "${CYAN}===========================================${NC}"
    echo ""
    echo "  Scope:          $SCOPE"
    echo "  Repos checked:  $total"
    if [[ "$STRICT" == "true" ]]; then
        if [[ -n "$STRICT_BRANCH" ]]; then
            echo -e "  Mode:           ${RED}STRICT${NC} (required branch: $STRICT_BRANCH)"
        else
            echo -e "  Mode:           ${RED}STRICT${NC} (enforcing majority branch)"
        fi
    fi
    echo ""

    if [[ $total -eq 0 ]]; then
        echo -e "  ${GREEN}No repos to check (vacuously consistent)${NC}"
        echo ""
        return
    fi

    # Branch status
    echo -e "  ${CYAN}--- Branch Status ---${NC}"
    if [[ -n "$STRICT_BRANCH" ]]; then
        echo "  Required branch: $STRICT_BRANCH"
        echo "  Majority branch: $MAJORITY_BRANCH ($MAJORITY_COUNT repos)"
    else
        echo "  Majority branch: $MAJORITY_BRANCH ($MAJORITY_COUNT repos)"
    fi
    if [[ "$BRANCH_CONSISTENT" == "true" ]]; then
        echo -e "  Status:          ${GREEN}CONSISTENT${NC}"
    else
        echo -e "  Status:          ${RED}INCONSISTENT${NC}"
        echo "  Outliers:"
        for entry in "${BRANCH_OUTLIERS[@]}"; do
            local path="${entry%%:*}"
            local branch="${entry#*:}"
            echo -e "    ${YELLOW}-${NC} $path (on $branch)"
        done
    fi
    echo ""

    # Worktree status
    echo -e "  ${CYAN}--- Worktree Status ---${NC}"
    echo "  Worktrees: $WORKTREE_COUNT    Regular: $REGULAR_COUNT"
    if [[ "$WORKTREE_CONSISTENT" == "true" ]]; then
        echo -e "  Status:    ${GREEN}CONSISTENT${NC}"
    else
        echo -e "  Status:    ${RED}INCONSISTENT (mixed worktree/regular)${NC}"
    fi
    echo ""

    # Verdict
    echo -e "${CYAN}===========================================${NC}"
    if [[ $exit_code -eq 0 ]]; then
        echo -e "  Verdict: ${GREEN}CONSISTENT${NC}"
    elif [[ "$STRICT" == "true" ]]; then
        echo -e "  Verdict: ${RED}BLOCKED${NC} (strict mode - exit code $exit_code)"
        echo -e "  ${RED}Orchestrated agentic session cannot proceed.${NC}"
    else
        echo -e "  Verdict: ${RED}INCONSISTENT${NC} (exit code $exit_code)"
    fi
    echo -e "${CYAN}===========================================${NC}"

    # Fix suggestions
    if [[ "$FIX_SUGGESTION" == "true" ]] && [[ ${#FIX_COMMANDS[@]} -gt 0 ]]; then
        echo ""
        echo -e "  ${YELLOW}Suggested fixes:${NC}"
        for cmd in "${FIX_COMMANDS[@]}"; do
            echo "    $cmd"
        done
    fi
    echo ""
}

output_json() {
    local total=${#REPO_PATHS[@]}
    local exit_code
    exit_code=$(compute_exit_code)
    local consistent="true"
    [[ $exit_code -ne 0 ]] && consistent="false"

    echo "{"
    echo "  \"consistent\": $consistent,"
    echo "  \"strict\": $STRICT,"
    if [[ -n "$STRICT_BRANCH" ]]; then
        echo "  \"strict_branch\": \"$STRICT_BRANCH\","
    fi
    echo "  \"scope\": \"$SCOPE\","
    echo "  \"total_repos_checked\": $total,"

    # Branch
    echo "  \"branch\": {"
    echo "    \"consistent\": $BRANCH_CONSISTENT,"
    echo "    \"majority\": \"$MAJORITY_BRANCH\","
    echo "    \"majority_count\": $MAJORITY_COUNT,"
    echo -n "    \"outliers\": ["
    if [[ ${#BRANCH_OUTLIERS[@]} -gt 0 ]]; then
        echo ""
        local first=true
        for entry in "${BRANCH_OUTLIERS[@]}"; do
            local path="${entry%%:*}"
            local branch="${entry#*:}"
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            echo -n "      {\"path\": \"$path\", \"branch\": \"$branch\"}"
        done
        echo ""
        echo "    ]"
    else
        echo "]"
    fi
    echo "  },"

    # Worktree
    echo "  \"worktree\": {"
    echo "    \"consistent\": $WORKTREE_CONSISTENT,"
    echo "    \"worktree_count\": $WORKTREE_COUNT,"
    echo "    \"regular_count\": $REGULAR_COUNT"
    echo "  },"

    # Repositories
    echo -n "  \"repositories\": ["
    if [[ $total -gt 0 ]]; then
        echo ""
        local first=true
        for i in "${!REPO_PATHS[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            echo -n "    {\"path\": \"${REPO_REL_PATHS[$i]}\", \"branch\": \"${REPO_BRANCHES[$i]}\", \"is_worktree\": ${REPO_WORKTREES[$i]}, \"has_changes\": ${REPO_HAS_CHANGES[$i]}}"
        done
        echo ""
        echo "  ],"
    else
        echo "],"
    fi

    # Exit code
    echo "  \"exit_code\": $exit_code,"

    # Fix suggestions
    echo -n "  \"fix_suggestions\": ["
    if [[ "$FIX_SUGGESTION" == "true" ]] && [[ ${#FIX_COMMANDS[@]} -gt 0 ]]; then
        echo ""
        local first=true
        for cmd in "${FIX_COMMANDS[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            # Escape double quotes in command
            local escaped="${cmd//\"/\\\"}"
            echo -n "    \"$escaped\""
        done
        echo ""
        echo "  ]"
    else
        echo "]"
    fi

    echo "}"
}

# --- Argument parsing ---

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                OUTPUT_MODE="json"
                shift
                ;;
            --check)
                OUTPUT_MODE="check"
                shift
                ;;
            --all)
                SCOPE="all"
                shift
                ;;
            --changes-only)
                SCOPE="changes-only"
                shift
                ;;
            --strict)
                STRICT=true
                shift
                ;;
            --strict=*)
                STRICT=true
                STRICT_BRANCH="${1#--strict=}"
                shift
                ;;
            --fix-suggestion|--fix-suggestions)
                FIX_SUGGESTION=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Run with --help for usage information" >&2
                exit 1
                ;;
        esac
    done
}

# --- Main ---

main() {
    parse_args "$@"

    # Disable colors if NO_COLOR is set
    if [[ -n "${NO_COLOR:-}" ]]; then
        RED="" GREEN="" YELLOW="" BLUE="" CYAN="" NC=""
    fi

    local start_dir
    start_dir=$(pwd)

    collect_repo_info "$start_dir"

    local total=${#REPO_PATHS[@]}

    if [[ $total -eq 0 ]]; then
        case "$OUTPUT_MODE" in
            human)
                log_info "No repositories to check (scope: $SCOPE)"
                ;;
            json)
                echo '{"consistent": true, "strict": '"$STRICT"', "scope": "'"$SCOPE"'", "total_repos_checked": 0, "branch": {"consistent": true, "majority": "", "majority_count": 0, "outliers": []}, "worktree": {"consistent": true, "worktree_count": 0, "regular_count": 0}, "repositories": [], "exit_code": 0, "fix_suggestions": []}'
                ;;
        esac
        exit 0
    fi

    detect_majority_branch
    check_worktree_consistency
    check_branch_consistency

    if [[ "$FIX_SUGGESTION" == "true" ]]; then
        generate_fix_suggestions
    fi

    local exit_code
    exit_code=$(compute_exit_code)

    case "$OUTPUT_MODE" in
        human)
            output_human_report
            ;;
        json)
            output_json
            ;;
        check)
            # No output, just exit code
            ;;
    esac

    exit "$exit_code"
}

main "$@"
