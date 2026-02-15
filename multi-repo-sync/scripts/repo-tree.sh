#!/usr/bin/env bash
#
# repo-tree.sh - Discover workspace repository structure
#
# Scans a workspace root for git repositories and classifies them
# into groups (directories containing multiple repos) and standalone
# repos. Outputs either a human-readable ASCII tree or JSON.
#
# Usage:
#   repo-tree.sh [OPTIONS] [SCAN_ROOT]
#
# Options:
#   --json           JSON output (default: human-readable ASCII tree)
#   --branches       Include branch per repo
#   --consistency    Flag groups with mixed branches
#   --depth N        Max find depth (default: 8)
#   --no-color       Disable colored output
#   -h, --help       Show help message
#
# Exit codes:
#   0 - Success
#   1 - No repos found
#   2 - Invalid arguments
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Exit codes
EXIT_SUCCESS=0
EXIT_NO_REPOS=1
EXIT_INVALID_ARGS=2

# Options
JSON_OUTPUT=false
SHOW_BRANCHES=false
CHECK_CONSISTENCY=false
MAX_DEPTH=8
NO_COLOR=""
SCAN_ROOT_ARG=""

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

# --- Logging ---

log_info()    { echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*" >&2; }
log_error()   { echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2; }

# --- Help ---

show_help() {
    cat <<'HELP_EOF'
Usage: repo-tree.sh [OPTIONS] [SCAN_ROOT]

Discover workspace repository structure and output as JSON or ASCII tree.

Options:
  --json           JSON output (default: human-readable ASCII tree)
  --branches       Include branch per repo
  --consistency    Flag groups with mixed branches
  --depth N        Max find depth (default: 8)
  --no-color       Disable colored output
  -h, --help       Show help message

Arguments:
  SCAN_ROOT        Directory to scan (default: auto-discover workspace root)

Exit codes:
  0  Success
  1  No repositories found
  2  Invalid arguments
HELP_EOF
}

# --- Argument parsing ---

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)          JSON_OUTPUT=true; shift ;;
            --branches)      SHOW_BRANCHES=true; shift ;;
            --consistency)   CHECK_CONSISTENCY=true; SHOW_BRANCHES=true; shift ;;
            --no-color)      NO_COLOR=1; shift ;;
            --depth)
                if [[ $# -lt 2 ]]; then
                    log_error "--depth requires an argument"
                    exit $EXIT_INVALID_ARGS
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "--depth must be a positive integer"
                    exit $EXIT_INVALID_ARGS
                fi
                MAX_DEPTH="$2"
                shift 2 ;;
            -h|--help)       show_help; exit $EXIT_SUCCESS ;;
            -*)              log_error "Unknown option: $1"; exit $EXIT_INVALID_ARGS ;;
            *)
                if [[ -n "$SCAN_ROOT_ARG" ]]; then
                    log_error "Unexpected argument: $1 (SCAN_ROOT already set to $SCAN_ROOT_ARG)"
                    exit $EXIT_INVALID_ARGS
                fi
                SCAN_ROOT_ARG="$1"
                shift ;;
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
    if [[ -n "$SCAN_ROOT_ARG" ]]; then
        # Use provided SCAN_ROOT directly
        if [[ ! -d "$SCAN_ROOT_ARG" ]]; then
            log_error "SCAN_ROOT does not exist: $SCAN_ROOT_ARG"
            exit $EXIT_INVALID_ARGS
        fi
        echo "$SCAN_ROOT_ARG"
    else
        find_workspace_root
    fi
}

# --- JSON helper ---

json_escape() {
    local str="$1"
    # Escape backslashes, double quotes, and control characters
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    printf '%s' "$str"
}

# --- Branch detection ---

get_branch() {
    local repo_path="$1"
    local branch
    branch=$(git -C "$repo_path" symbolic-ref --short HEAD 2>/dev/null || echo "DETACHED")
    printf '%s' "$branch"
}

# --- Core scanning ---

discover_repos() {
    local scan_root="$1"

    # Find all .git directories, pruning common non-repo dirs
    find "$scan_root" -maxdepth "$MAX_DEPTH" \
        -name ".git" \
        -not -path "*/node_modules/*" \
        -not -path "*/vendor/*" \
        -not -path "*/__pycache__/*" \
        -not -path "*/.venv/*" \
        -not -path "*/venv/*" \
        2>/dev/null | sort
}

classify_repos() {
    local scan_root="$1"
    shift
    local git_dirs=("$@")

    # Arrays to hold classification results
    # We store: "relative_path_to_repo" for each found repo
    local -a repo_paths=()
    local -a repo_rel_paths=()

    for git_dir in "${git_dirs[@]}"; do
        local repo_path
        repo_path=$(dirname "$git_dir")
        local rel_path="${repo_path#"$scan_root"/}"

        # Skip the scan root itself if it has .git
        if [[ "$repo_path" == "$scan_root" ]]; then
            continue
        fi

        repo_paths+=("$repo_path")
        repo_rel_paths+=("$rel_path")
    done

    if [[ ${#repo_paths[@]} -eq 0 ]]; then
        return 1
    fi

    # Classify: count how many repos share the same parent directory (depth 1 from scan_root)
    # A repo at depth 1 (e.g., "SA_build_agentics") with no siblings at depth 2 = standalone
    # A repo at depth 2+ (e.g., "BountyForge/discord-mcp-bot") where the parent has multiple
    #   .git children = group member
    # The parent directory = group

    # Build a map of parent_rel_path -> list of child repos
    declare -A parent_children
    declare -A parent_is_repo

    for i in "${!repo_rel_paths[@]}"; do
        local rel="${repo_rel_paths[$i]}"
        local depth
        # Count slashes to determine depth
        depth=$(echo "$rel" | tr -cd '/' | wc -c | tr -d ' ')

        if [[ "$depth" -eq 0 ]]; then
            # Depth 1 from scan root (no slash in rel path)
            # Could be standalone or a group parent
            # We'll figure this out after scanning all repos
            # For now, mark it as a potential standalone
            local name
            name=$(basename "$rel")
            # Check if this is also a parent of deeper repos
            if [[ -z "${parent_children[$rel]+_}" ]]; then
                parent_children["$rel"]=""
            fi
            parent_is_repo["$rel"]="true"
        else
            # Depth 2+ from scan root
            # Extract the top-level parent (first component of rel path)
            local top_parent="${rel%%/*}"
            local child_rel="$rel"

            if [[ -z "${parent_children[$top_parent]+_}" ]] || [[ -z "${parent_children[$top_parent]}" ]]; then
                parent_children["$top_parent"]="$child_rel"
            else
                parent_children["$top_parent"]="${parent_children[$top_parent]}|$child_rel"
            fi

            # Mark parent as repo if it has .git
            if [[ -z "${parent_is_repo[$top_parent]+_}" ]]; then
                parent_is_repo["$top_parent"]="false"
            fi
        fi
    done

    # Now classify:
    # - If a top-level entry has children in parent_children, it's a group
    # - If a top-level entry has no children, it's standalone

    local -a groups=()
    local -a standalones=()

    # Collect all top-level entries (sorted)
    local -a top_entries=()
    for key in "${!parent_children[@]}"; do
        top_entries+=("$key")
    done
    # Also check for depth-1 repos that aren't in parent_children yet
    for i in "${!repo_rel_paths[@]}"; do
        local rel="${repo_rel_paths[$i]}"
        local depth
        depth=$(echo "$rel" | tr -cd '/' | wc -c | tr -d ' ')
        if [[ "$depth" -eq 0 ]]; then
            local found=false
            for entry in "${top_entries[@]}"; do
                if [[ "$entry" == "$rel" ]]; then
                    found=true
                    break
                fi
            done
            if [[ "$found" == "false" ]]; then
                top_entries+=("$rel")
                parent_children["$rel"]=""
                parent_is_repo["$rel"]="true"
            fi
        fi
    done

    # Sort top entries
    IFS=$'\n' top_entries=($(sort <<<"${top_entries[*]}")); unset IFS

    # Output classification as lines:
    # GROUP|group_name|group_path|is_repo|child1_rel|child2_rel|...
    # STANDALONE|name|path

    local total_member_repos=0
    local total_standalone_repos=0

    for entry in "${top_entries[@]}"; do
        local children="${parent_children[$entry]:-}"
        local is_repo="${parent_is_repo[$entry]:-false}"

        if [[ -n "$children" ]]; then
            # This is a group - has child repos
            echo "GROUP|$entry|$entry|$is_repo|$children"
            # Count member repos
            local count
            count=$(echo "$children" | tr '|' '\n' | wc -l | tr -d ' ')
            total_member_repos=$((total_member_repos + count))
        else
            # Standalone repo (depth 1, no children)
            if [[ "$is_repo" == "true" ]]; then
                echo "STANDALONE|$entry|$entry"
                total_standalone_repos=$((total_standalone_repos + 1))
            fi
        fi
    done

    echo "TOTAL|$total_member_repos|$total_standalone_repos"
}

# --- Output formatters ---

output_json() {
    local scan_root="$1"
    shift
    local classifications=("$@")

    local total_repos=0
    local groups_json=""
    local standalone_json=""
    local first_group=true
    local first_standalone=true

    for line in "${classifications[@]}"; do
        local type="${line%%|*}"
        local rest="${line#*|}"

        if [[ "$type" == "TOTAL" ]]; then
            local member_count="${rest%%|*}"
            local standalone_count="${rest#*|}"
            total_repos=$((member_count + standalone_count))
            continue
        fi

        if [[ "$type" == "GROUP" ]]; then
            local group_name="${rest%%|*}"
            rest="${rest#*|}"
            local group_path="${rest%%|*}"
            rest="${rest#*|}"
            local is_repo="${rest%%|*}"
            rest="${rest#*|}"
            local children_str="$rest"

            # Get group branch if it's a repo
            local group_branch=""
            if [[ "$SHOW_BRANCHES" == "true" ]] && [[ "$is_repo" == "true" ]]; then
                group_branch=$(get_branch "$scan_root/$group_path")
            fi

            # Build repos array
            local repos_json=""
            local first_repo=true
            local -a child_branches=()

            IFS='|' read -ra children <<< "$children_str"
            for child in "${children[@]}"; do
                [[ -z "$child" ]] && continue
                local child_name
                child_name=$(basename "$child")
                local child_branch=""
                if [[ "$SHOW_BRANCHES" == "true" ]]; then
                    child_branch=$(get_branch "$scan_root/$child")
                    child_branches+=("$child_branch")
                fi

                local repo_entry="{"
                repo_entry+="\"name\":\"$(json_escape "$child_name")\""
                repo_entry+=",\"path\":\"$(json_escape "$child")\""
                if [[ "$SHOW_BRANCHES" == "true" ]]; then
                    repo_entry+=",\"branch\":\"$(json_escape "$child_branch")\""
                fi
                repo_entry+="}"

                if [[ "$first_repo" == "true" ]]; then
                    repos_json="$repo_entry"
                    first_repo=false
                else
                    repos_json="$repos_json,$repo_entry"
                fi
            done

            # Build group entry
            local group_entry="{"
            group_entry+="\"name\":\"$(json_escape "$group_name")\""
            group_entry+=",\"path\":\"$(json_escape "$group_path")\""
            group_entry+=",\"is_repo\":$is_repo"
            if [[ "$SHOW_BRANCHES" == "true" ]] && [[ "$is_repo" == "true" ]]; then
                group_entry+=",\"branch\":\"$(json_escape "$group_branch")\""
            fi
            group_entry+=",\"repos\":[$repos_json]"

            # Consistency checking
            if [[ "$CHECK_CONSISTENCY" == "true" ]] && [[ ${#child_branches[@]} -gt 0 ]]; then
                # Find majority branch
                local majority_branch=""
                local majority_count=0
                declare -A branch_counts=()

                for b in "${child_branches[@]}"; do
                    branch_counts["$b"]=$(( ${branch_counts["$b"]:-0} + 1 ))
                done

                for b in "${!branch_counts[@]}"; do
                    if [[ ${branch_counts[$b]} -gt $majority_count ]]; then
                        majority_count=${branch_counts[$b]}
                        majority_branch="$b"
                    fi
                done

                local consistent=true
                local outliers_json=""
                local first_outlier=true

                for b in "${!branch_counts[@]}"; do
                    if [[ "$b" != "$majority_branch" ]]; then
                        consistent=false
                        # Find which repos are outliers
                        local idx=0
                        IFS='|' read -ra children2 <<< "$children_str"
                        for child2 in "${children2[@]}"; do
                            [[ -z "$child2" ]] && continue
                            if [[ "${child_branches[$idx]}" == "$b" ]]; then
                                local outlier_name
                                outlier_name=$(basename "$child2")
                                local outlier_entry="{"
                                outlier_entry+="\"name\":\"$(json_escape "$outlier_name")\""
                                outlier_entry+=",\"path\":\"$(json_escape "$child2")\""
                                outlier_entry+=",\"branch\":\"$(json_escape "$b")\""
                                outlier_entry+="}"
                                if [[ "$first_outlier" == "true" ]]; then
                                    outliers_json="$outlier_entry"
                                    first_outlier=false
                                else
                                    outliers_json="$outliers_json,$outlier_entry"
                                fi
                            fi
                            idx=$((idx + 1))
                        done
                    fi
                done

                group_entry+=",\"branch_consistent\":$consistent"
                group_entry+=",\"majority_branch\":\"$(json_escape "$majority_branch")\""
                group_entry+=",\"majority_count\":$majority_count"
                group_entry+=",\"outliers\":[$outliers_json]"

                unset branch_counts
            fi

            group_entry+="}"

            if [[ "$first_group" == "true" ]]; then
                groups_json="$group_entry"
                first_group=false
            else
                groups_json="$groups_json,$group_entry"
            fi

        elif [[ "$type" == "STANDALONE" ]]; then
            local standalone_name="${rest%%|*}"
            rest="${rest#*|}"
            local standalone_path="$rest"

            local standalone_branch=""
            if [[ "$SHOW_BRANCHES" == "true" ]]; then
                standalone_branch=$(get_branch "$scan_root/$standalone_path")
            fi

            local standalone_entry="{"
            standalone_entry+="\"name\":\"$(json_escape "$standalone_name")\""
            standalone_entry+=",\"path\":\"$(json_escape "$standalone_path")\""
            if [[ "$SHOW_BRANCHES" == "true" ]]; then
                standalone_entry+=",\"branch\":\"$(json_escape "$standalone_branch")\""
            fi
            standalone_entry+="}"

            if [[ "$first_standalone" == "true" ]]; then
                standalone_json="$standalone_entry"
                first_standalone=false
            else
                standalone_json="$standalone_json,$standalone_entry"
            fi
        fi
    done

    # Build final JSON
    echo "{"
    echo "  \"workspace_root\": \"$(json_escape "$scan_root")\","
    echo "  \"total_repos\": $total_repos,"
    echo "  \"groups\": [$groups_json],"
    echo "  \"standalone\": [$standalone_json]"
    echo "}"
}

output_tree() {
    local scan_root="$1"
    shift
    local classifications=("$@")

    local scan_name
    scan_name=$(basename "$scan_root")

    echo -e "${COLOR_BOLD}${scan_name}/${COLOR_RESET}"

    # Collect all entries (groups and standalones) for proper tree drawing
    local -a entries=()
    for line in "${classifications[@]}"; do
        local type="${line%%|*}"
        if [[ "$type" == "GROUP" ]] || [[ "$type" == "STANDALONE" ]]; then
            entries+=("$line")
        fi
    done

    local total_entries=${#entries[@]}
    local entry_idx=0

    for line in "${entries[@]}"; do
        entry_idx=$((entry_idx + 1))
        local type="${line%%|*}"
        local rest="${line#*|}"
        local is_last=false
        if [[ $entry_idx -eq $total_entries ]]; then
            is_last=true
        fi

        local connector
        local prefix
        if [[ "$is_last" == "true" ]]; then
            connector="└── "
            prefix="    "
        else
            connector="├── "
            prefix="│   "
        fi

        if [[ "$type" == "GROUP" ]]; then
            local group_name="${rest%%|*}"
            rest="${rest#*|}"
            local group_path="${rest%%|*}"
            rest="${rest#*|}"
            local is_repo="${rest%%|*}"
            rest="${rest#*|}"
            local children_str="$rest"

            # Count children
            local child_count=0
            IFS='|' read -ra children <<< "$children_str"
            for child in "${children[@]}"; do
                [[ -n "$child" ]] && child_count=$((child_count + 1))
            done

            # Check consistency for display
            local consistency_note=""
            if [[ "$CHECK_CONSISTENCY" == "true" ]]; then
                local -a child_branches=()
                for child in "${children[@]}"; do
                    [[ -z "$child" ]] && continue
                    local cb
                    cb=$(get_branch "$scan_root/$child")
                    child_branches+=("$cb")
                done

                # Check if all same
                local all_same=true
                if [[ ${#child_branches[@]} -gt 1 ]]; then
                    local first_b="${child_branches[0]}"
                    for cb in "${child_branches[@]}"; do
                        if [[ "$cb" != "$first_b" ]]; then
                            all_same=false
                            break
                        fi
                    done
                fi

                if [[ "$all_same" == "false" ]]; then
                    consistency_note=", ${COLOR_YELLOW}mixed branches${COLOR_RESET}"
                fi
            fi

            echo -e "${connector}${COLOR_BOLD}${group_name}/${COLOR_RESET} ${COLOR_DIM}(group, $child_count repos${consistency_note}${COLOR_DIM})${COLOR_RESET}"

            # Print children
            local child_idx=0
            for child in "${children[@]}"; do
                [[ -z "$child" ]] && continue
                child_idx=$((child_idx + 1))
                local child_name
                child_name=$(basename "$child")

                local child_connector
                if [[ $child_idx -eq $child_count ]]; then
                    child_connector="└── "
                else
                    child_connector="├── "
                fi

                local branch_info=""
                if [[ "$SHOW_BRANCHES" == "true" ]]; then
                    local cb
                    cb=$(get_branch "$scan_root/$child")
                    branch_info=" ${COLOR_CYAN}[$cb]${COLOR_RESET}"
                fi

                echo -e "${prefix}${child_connector}${child_name}${branch_info}"
            done

        elif [[ "$type" == "STANDALONE" ]]; then
            local standalone_name="${rest%%|*}"

            local branch_info=""
            if [[ "$SHOW_BRANCHES" == "true" ]]; then
                rest="${rest#*|}"
                local standalone_path="$rest"
                local sb
                sb=$(get_branch "$scan_root/$standalone_path")
                branch_info=" ${COLOR_CYAN}[$sb]${COLOR_RESET}"
            fi

            echo -e "${connector}${standalone_name}${branch_info}"
        fi
    done
}

# --- Main ---

main() {
    setup_colors
    parse_args "$@"
    setup_colors  # Re-run after --no-color parsed

    local scan_root
    scan_root=$(get_scan_root)

    if [[ ! -d "$scan_root" ]]; then
        log_error "Scan root does not exist: $scan_root"
        exit $EXIT_NO_REPOS
    fi

    # Discover all git repos
    local -a git_dirs=()
    while IFS= read -r line; do
        git_dirs+=("$line")
    done < <(discover_repos "$scan_root")

    if [[ ${#git_dirs[@]} -eq 0 ]]; then
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            echo "{"
            echo "  \"workspace_root\": \"$(json_escape "$scan_root")\","
            echo "  \"total_repos\": 0,"
            echo "  \"groups\": [],"
            echo "  \"standalone\": []"
            echo "}"
        else
            log_error "No repositories found in $scan_root"
        fi
        exit $EXIT_NO_REPOS
    fi

    # Classify repos
    local -a classifications=()
    while IFS= read -r line; do
        classifications+=("$line")
    done < <(classify_repos "$scan_root" "${git_dirs[@]}")

    if [[ ${#classifications[@]} -eq 0 ]]; then
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            echo "{"
            echo "  \"workspace_root\": \"$(json_escape "$scan_root")\","
            echo "  \"total_repos\": 0,"
            echo "  \"groups\": [],"
            echo "  \"standalone\": []"
            echo "}"
        else
            log_error "No repositories found in $scan_root"
        fi
        exit $EXIT_NO_REPOS
    fi

    # Output
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        output_json "$scan_root" "${classifications[@]}"
    else
        output_tree "$scan_root" "${classifications[@]}"
    fi

    exit $EXIT_SUCCESS
}

main "$@"
