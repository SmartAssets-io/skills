#!/usr/bin/env bash
# repo-selection.sh - Shared library for multi-repo selection filtering
#
# Provides functions to load and filter repositories based on
# .multi-repo-selection.json configuration file.
#
# Usage:
#   source /path/to/lib/repo-selection.sh
#   load_selection "/path/to/workspace"
#   is_repo_selected "BountyForge/discord-mcp-bot" && echo "selected"

# Prevent re-sourcing
if [[ -n "${REPO_SELECTION_LOADED:-}" ]]; then
    return 0
fi
REPO_SELECTION_LOADED=1

# Global variables
REPO_SELECTION_CONFIG=""       # Path to .multi-repo-selection.json (set by find/load)
REPO_SELECTION_MODE=""         # "include" or empty (no config)
REPO_SELECTION_GROUPS=()       # Group names from config
REPO_SELECTION_REPOS=()        # Individual repo paths from config
REPO_SELECTION_EXCLUDED=()     # Excluded repo paths from config
REPO_SELECTION_TOTAL=0         # Total repos in workspace (set by load_selection)
REPO_SELECTION_SELECTED=0      # Count of selected repos (set by load_selection)

#
# Find .multi-repo-selection.json by walking up from CWD (or $1)
#
# Arguments:
#   $1 - Starting directory (optional, defaults to CWD)
#
# Sets:
#   REPO_SELECTION_CONFIG - path to config file if found
#
# Returns:
#   0 if found, 1 if not found
#
find_selection_config() {
    local search_dir="${1:-$(pwd)}"

    # Resolve to absolute path
    if [[ -d "$search_dir" ]]; then
        search_dir="$(cd "$search_dir" && pwd)"
    else
        return 1
    fi

    local dir="$search_dir"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.multi-repo-selection.json" ]]; then
            REPO_SELECTION_CONFIG="$dir/.multi-repo-selection.json"
            return 0
        fi
        dir="$(dirname "$dir")"
    done

    # Check root as well
    if [[ -f "/.multi-repo-selection.json" ]]; then
        REPO_SELECTION_CONFIG="/.multi-repo-selection.json"
        return 0
    fi

    return 1
}

#
# Load and parse the selection configuration
#
# Arguments:
#   $1 - Workspace root directory
#
# Sets:
#   REPO_SELECTION_MODE, REPO_SELECTION_GROUPS, REPO_SELECTION_REPOS,
#   REPO_SELECTION_EXCLUDED, REPO_SELECTION_TOTAL, REPO_SELECTION_SELECTED
#
# Returns:
#   0 on success (including when no config = all selected)
#
load_selection() {
    local workspace_root="${1:-.}"

    # Resolve to absolute path
    if [[ -d "$workspace_root" ]]; then
        workspace_root="$(cd "$workspace_root" && pwd)"
    fi

    # MULTI_REPO_ALL bypass: treat all repos as selected
    if [[ "${MULTI_REPO_ALL:-}" == "true" ]]; then
        REPO_SELECTION_MODE=""
        _count_workspace_repos "$workspace_root"
        REPO_SELECTION_SELECTED=$REPO_SELECTION_TOTAL
        return 0
    fi

    # Find config if not already set
    if [[ -z "$REPO_SELECTION_CONFIG" ]]; then
        if ! find_selection_config "$workspace_root"; then
            # No config found - all repos selected (backward compat)
            REPO_SELECTION_MODE=""
            _count_workspace_repos "$workspace_root"
            REPO_SELECTION_SELECTED=$REPO_SELECTION_TOTAL
            return 0
        fi
    fi

    # Require jq
    if ! command -v jq &>/dev/null; then
        echo "Warning: jq not available, treating all repos as selected" >&2
        REPO_SELECTION_MODE=""
        _count_workspace_repos "$workspace_root"
        REPO_SELECTION_SELECTED=$REPO_SELECTION_TOTAL
        return 0
    fi

    # Validate JSON
    if ! jq -e '.' "$REPO_SELECTION_CONFIG" >/dev/null 2>&1; then
        echo "Warning: malformed JSON in $REPO_SELECTION_CONFIG, treating all repos as selected" >&2
        REPO_SELECTION_MODE=""
        REPO_SELECTION_CONFIG=""
        _count_workspace_repos "$workspace_root"
        REPO_SELECTION_SELECTED=$REPO_SELECTION_TOTAL
        return 0
    fi

    # Parse config
    REPO_SELECTION_MODE=$(jq -r '.mode // ""' "$REPO_SELECTION_CONFIG")

    # Parse groups array
    REPO_SELECTION_GROUPS=()
    local group
    while IFS= read -r group; do
        [[ -n "$group" ]] && REPO_SELECTION_GROUPS+=("$group")
    done < <(jq -r '.groups[]? // empty' "$REPO_SELECTION_CONFIG" 2>/dev/null)

    # Parse repos array
    REPO_SELECTION_REPOS=()
    local repo
    while IFS= read -r repo; do
        [[ -n "$repo" ]] && REPO_SELECTION_REPOS+=("$repo")
    done < <(jq -r '.repos[]? // empty' "$REPO_SELECTION_CONFIG" 2>/dev/null)

    # Parse excluded_repos array
    REPO_SELECTION_EXCLUDED=()
    local excluded
    while IFS= read -r excluded; do
        [[ -n "$excluded" ]] && REPO_SELECTION_EXCLUDED+=("$excluded")
    done < <(jq -r '.excluded_repos[]? // empty' "$REPO_SELECTION_CONFIG" 2>/dev/null)

    # Count total and selected repos
    _count_workspace_repos "$workspace_root"
    _count_selected_repos "$workspace_root"

    return 0
}

#
# Check if a repo path is selected based on current config
#
# Arguments:
#   $1 - Repo path relative to workspace root (e.g., "BountyForge/discord-mcp-bot")
#
# Returns:
#   0 if selected (or no config), 1 if not selected
#
is_repo_selected() {
    local repo_path="$1"

    # No config loaded = all selected
    if [[ -z "$REPO_SELECTION_MODE" ]]; then
        return 0
    fi

    # Include mode resolution
    if [[ "$REPO_SELECTION_MODE" == "include" ]]; then
        # 1. Check excluded_repos first
        local excluded
        for excluded in "${REPO_SELECTION_EXCLUDED[@]}"; do
            if [[ "$repo_path" == "$excluded" ]]; then
                return 1
            fi
        done

        # 2. Check individual repos
        local repo
        for repo in "${REPO_SELECTION_REPOS[@]}"; do
            if [[ "$repo_path" == "$repo" ]]; then
                return 0
            fi
        done

        # 3. Check group membership (first path component)
        local first_component="${repo_path%%/*}"
        local group
        for group in "${REPO_SELECTION_GROUPS[@]}"; do
            if [[ "$first_component" == "$group" ]]; then
                return 0
            fi
        done

        # 4. Not matched
        return 1
    fi

    # Unknown mode = all selected (safe default)
    return 0
}

#
# Filter repo paths from stdin, outputting only selected ones
#
# Reads one repo path per line from stdin
# Outputs only paths that pass is_repo_selected()
#
filter_repo_list() {
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if is_repo_selected "$line"; then
            echo "$line"
        fi
    done
}

#
# Return a human-readable summary of selection state
#
# Output:
#   String like "42/51 repos selected" or "all repos (no selection config)"
#
selection_summary() {
    if [[ -z "$REPO_SELECTION_MODE" ]]; then
        echo "all repos (no selection config)"
        return
    fi

    echo "${REPO_SELECTION_SELECTED}/${REPO_SELECTION_TOTAL} repos selected"
}

#
# Remove the selection config file
#
# Arguments:
#   $1 - Workspace root directory
#
# Returns:
#   0 on success, 1 if no config to delete
#
clear_selection() {
    local workspace_root="${1:-.}"

    # Resolve to absolute path
    if [[ -d "$workspace_root" ]]; then
        workspace_root="$(cd "$workspace_root" && pwd)"
    fi

    local config_path="$workspace_root/.multi-repo-selection.json"

    if [[ -f "$config_path" ]]; then
        rm -f "$config_path"
        echo "Removed selection config: $config_path"
        REPO_SELECTION_CONFIG=""
        REPO_SELECTION_MODE=""
        REPO_SELECTION_GROUPS=()
        REPO_SELECTION_REPOS=()
        REPO_SELECTION_EXCLUDED=()
        return 0
    fi

    echo "No selection config found at: $config_path"
    return 1
}

# ---- Internal helpers ----

#
# Count total repos in workspace using find
#
# Arguments:
#   $1 - Workspace root
#
# Sets:
#   REPO_SELECTION_TOTAL
#
_count_workspace_repos() {
    local workspace_root="$1"

    if [[ ! -d "$workspace_root" ]]; then
        REPO_SELECTION_TOTAL=0
        return
    fi

    local count
    count=$(find "$workspace_root" -maxdepth 3 -type d -name ".git" -not -path "*/node_modules/*" 2>/dev/null | wc -l)
    REPO_SELECTION_TOTAL=$((count))
}

#
# Count selected repos by iterating discovered repos through filter
#
# Arguments:
#   $1 - Workspace root
#
# Sets:
#   REPO_SELECTION_SELECTED
#
_count_selected_repos() {
    local workspace_root="$1"
    local selected=0

    if [[ ! -d "$workspace_root" ]]; then
        REPO_SELECTION_SELECTED=0
        return
    fi

    local git_dir repo_path
    while IFS= read -r git_dir; do
        [[ -z "$git_dir" ]] && continue
        local repo_dir
        repo_dir="$(dirname "$git_dir")"
        # Make path relative to workspace root
        repo_path="${repo_dir#"$workspace_root"/}"
        if is_repo_selected "$repo_path"; then
            selected=$((selected + 1))
        fi
    done < <(find "$workspace_root" -maxdepth 3 -type d -name ".git" -not -path "*/node_modules/*" 2>/dev/null | sort)

    REPO_SELECTION_SELECTED=$selected
}
