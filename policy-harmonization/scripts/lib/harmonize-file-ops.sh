#!/usr/bin/env bash
#
# harmonize-file-ops.sh - File operations for harmonize-policies.sh
#
# This library provides:
# - Source path discovery
# - Git repository discovery
# - File comparison
# - Python helper integration
# - Markdown merging functions
# - Diff display
# - User prompts
#
# Usage:
#   source /path/to/lib/harmonize-file-ops.sh
#   find_source_path
#   repos=$(discover_repos "/path/to/scan")
#

# Prevent re-sourcing
if [[ -n "${HARMONIZE_FILE_OPS_LOADED:-}" ]]; then
    return 0
fi
HARMONIZE_FILE_OPS_LOADED=1

# Source UI library for logging (if not already loaded)
HARMONIZE_FILE_OPS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${HARMONIZE_UI_LOADED:-}" ]]; then
    source "${HARMONIZE_FILE_OPS_SCRIPT_DIR}/harmonize-ui.sh"
fi

# LIB_DIR for Python helpers (can be overridden)
LIB_DIR="${LIB_DIR:-$HARMONIZE_FILE_OPS_SCRIPT_DIR}"

#
# Find the source template directory
# Sets global SOURCE_PATH variable
#
# Returns:
#   0 on success
#   1 if not found
#
find_source_path() {
    if [[ -n "${SOURCE_PATH:-}" ]]; then
        # User specified source path
        if [[ ! -d "$SOURCE_PATH" ]]; then
            log_error "Source path not found: $SOURCE_PATH"
            return 1
        fi
        return 0
    fi

    # Auto-detect: look for top-level-gitlab-profile
    local candidates=(
        "${SCRIPT_DIR:-}/../.."
        "$(pwd)/top-level-gitlab-profile"
        "$HOME/src/SA/top-level-gitlab-profile"
    )

    for candidate in "${candidates[@]}"; do
        if [[ -d "$candidate" ]] && [[ -d "$candidate/docs/templates" ]]; then
            SOURCE_PATH="$(cd "$candidate" && pwd)"
            return 0
        fi
    done

    # Fall back to script's parent directory
    if [[ -n "${SCRIPT_DIR:-}" ]]; then
        SOURCE_PATH="$(cd "${SCRIPT_DIR}/../.." && pwd)"
        if [[ -d "$SOURCE_PATH/docs/templates" ]]; then
            return 0
        fi
    fi

    log_error "Could not find source template directory"
    log_info "Use --source DIR to specify the template source"
    return 1
}

#
# Discover git repositories recursively
#
# Arguments:
#   $1 - Target directory to scan (optional, defaults to ".")
#
# Output:
#   One repository path per line
#
# Returns:
#   0 on success
#   1 if target not found or no repos found
#
discover_repos() {
    local target="${1:-.}"
    local repos=()

    # Validate target path
    if [[ ! -d "$target" ]]; then
        log_error "Target path not found: $target"
        return 1
    fi

    # Find all .git directories (limit depth to avoid excessive scanning)
    # maxdepth 8 allows for reasonable nesting: workspace/category/project/.git
    # Use -prune to avoid descending into heavy directories (node_modules, vendor, etc.)
    # For .git: match and print it, then prune to avoid descending (handles submodules)
    while IFS= read -r git_dir; do
        local repo_dir
        repo_dir=$(dirname "$git_dir")
        repos+=("$repo_dir")
    done < <(find "$target" -maxdepth 8 \
        \( -name node_modules -o -name vendor -o -name __pycache__ \) -prune \
        -o -type d -name ".git" -print -prune \
        2>/dev/null | sort)

    if [[ ${#repos[@]} -eq 0 ]]; then
        log_error "No git repositories found under: $target"
        return 1
    fi

    # Output repo paths
    printf '%s\n' "${repos[@]}"
}

#
# Compare a single policy file
#
# Arguments:
#   $1 - Source template file
#   $2 - Target file
#
# Output:
#   "create" - Target doesn't exist
#   "customized" - Target differs from source
#   "ok" - Target matches source
#   "skip" - Source doesn't exist
#
compare_file() {
    local source_file="$1"
    local target_file="$2"

    # Check if source template exists
    if [[ ! -f "$source_file" ]]; then
        echo "skip"
        return
    fi

    # Check if target exists
    if [[ ! -f "$target_file" ]]; then
        echo "create"
        return
    fi

    # Compare files - existing files that differ are marked as "customized"
    # They will be preserved unless --force is used
    if diff -q "$source_file" "$target_file" >/dev/null 2>&1; then
        echo "ok"
    else
        echo "customized"
    fi
}

#
# Check if uv is available (preferred) or fall back to Python 3
#
# Output:
#   Command to run Python (e.g., "uv run --script" or "python3")
#
# Returns:
#   0 if Python available
#   1 if not found
#
check_python() {
    if command -v uv &>/dev/null; then
        echo "uv run --script"
        return 0
    elif command -v python3 &>/dev/null; then
        echo "python3"
        return 0
    elif command -v python &>/dev/null; then
        # Check if it's Python 3
        if python --version 2>&1 | grep -q "Python 3"; then
            echo "python"
            return 0
        fi
    fi
    return 1
}

#
# Get merge changes for a markdown file using the Python helper
#
# Arguments:
#   $1 - Template file
#   $2 - Target file
#
# Output:
#   JSON array of changes
#
# Returns:
#   0 on success
#   1 if Python not available
#
get_merge_changes() {
    local template_file="$1"
    local target_file="$2"
    local python_cmd

    python_cmd=$(check_python) || return 1

    $python_cmd "$LIB_DIR/markdown_merge.py" merge "$template_file" "$target_file" --changes-only 2>/dev/null
}

#
# Perform section-based merge using Python helper
#
# Arguments:
#   $1 - Template file
#   $2 - Target file
#
# Output:
#   Merged content
#
# Returns:
#   0 on success
#   1 if Python not available
#
merge_markdown() {
    local template_file="$1"
    local target_file="$2"
    local python_cmd

    python_cmd=$(check_python) || return 1

    $python_cmd "$LIB_DIR/markdown_merge.py" merge "$template_file" "$target_file" 2>/dev/null
}

#
# Show merge preview for a markdown file
#
# Arguments:
#   $1 - Template file
#   $2 - Target file
#
show_merge_preview() {
    local template_file="$1"
    local target_file="$2"
    local changes

    changes=$(get_merge_changes "$template_file" "$target_file") || return 1

    # Count different action types
    local add_count update_count preserve_count
    add_count=$(echo "$changes" | jq '[.[] | select(.action == "add")] | length')
    update_count=$(echo "$changes" | jq '[.[] | select(.action == "update")] | length')
    preserve_count=$(echo "$changes" | jq '[.[] | select(.action == "preserve")] | length')

    echo ""
    echo "       ${COLOR_CYAN}Merge Preview:${COLOR_RESET}"
    echo "       - Sections to add: $add_count"
    echo "       - Sections to update: $update_count"
    echo "       - Sections preserved: $preserve_count"

    if [[ "${VERBOSE:-false}" == true ]]; then
        echo ""
        echo "       ${COLOR_DIM}Changes:${COLOR_RESET}"
        echo "$changes" | jq -r '.[] | select(.action != "preserve") | "         [\(.action | ascii_upcase)] \(.section)"'
    fi
}

#
# Show diff between files
#
# Arguments:
#   $1 - Source file
#   $2 - Target file
#   $3 - Max lines to show (optional, defaults to 20)
#
show_diff() {
    local source_file="$1"
    local target_file="$2"
    local max_lines="${3:-20}"

    echo ""
    echo "       ${COLOR_DIM}--- Source (template)${COLOR_RESET}"
    echo "       ${COLOR_DIM}+++ Target (current)${COLOR_RESET}"
    diff -u "$source_file" "$target_file" 2>/dev/null | head -n "$max_lines" | sed 's/^/       /'
    echo ""
}

#
# Prompt for user action
#
# Arguments:
#   $1 - Message to display (optional)
#
# Global variables used:
#   MODE - "yolo" or "interactive"
#   DRY_RUN - true/false
#   PROMPT_TIMEOUT - timeout in seconds (default: 60)
#
# Returns:
#   0 - apply
#   1 - skip
#   2 - show diff
#   3 - quit
#
prompt_action() {
    local message="$1"
    local timeout="${PROMPT_TIMEOUT:-60}"
    local max_attempts=3
    local attempt=0

    # YOLO mode: auto-apply (no confirmations)
    if [[ "${MODE:-interactive}" == "yolo" ]]; then
        return 0  # apply
    fi

    # Dry-run mode: never apply
    if [[ "${DRY_RUN:-false}" == true ]]; then
        return 1  # skip (but logged as would-apply)
    fi

    # Interactive mode: prompt user with timeout and retry logic
    while [[ $attempt -lt $max_attempts ]]; do
        echo ""
        echo -n "       Apply changes? [y/N/d(iff)/q(uit)] (${timeout}s timeout): "

        local response=""
        if ! read -r -t "$timeout" response; then
            echo ""
            log_warning "Input timeout after ${timeout}s - skipping"
            return 1  # skip on timeout
        fi

        # Sanitize input: only allow expected characters
        response="${response//[^a-zA-Z]/}"

        case "$response" in
            [yY]|[yY][eE][sS])
                return 0  # apply
                ;;
            [dD])
                return 2  # show diff
                ;;
            [qQ]|[qQ][uU][iI][tT])
                return 3  # quit
                ;;
            ""|[nN]|[nN][oO])
                return 1  # skip (empty = default No)
                ;;
            *)
                ((attempt++))
                if [[ $attempt -lt $max_attempts ]]; then
                    echo "       Invalid input. Please enter y, n, d, or q."
                else
                    echo "       Too many invalid attempts - skipping"
                    return 1  # skip after max attempts
                fi
                ;;
        esac
    done

    return 1  # default to skip
}

#
# Enrich a template by processing EMBED directives
#
# Scans the template for <!-- EMBED:path --> directives and replaces
# each directive with the content of the referenced file (relative to
# the SOURCE_PATH/docs/common/ directory).
#
# Supports optional section extraction:
#   <!-- EMBED:filename.md#Section Title -->
# extracts only the named ## section (and its content until the next ##).
#
# Arguments:
#   $1 - Template file path
#   $2 - Convention source directory (e.g., SOURCE_PATH/docs/common)
#
# Output:
#   Path to enriched temporary file (caller must clean up)
#
# Returns:
#   0 on success (enriched file created)
#   1 if template not found or no EMBED directives found
#
enrich_template() {
    local template_file="$1"
    local convention_dir="$2"
    local enriched_file

    if [[ ! -f "$template_file" ]]; then
        log_error "Template file not found: $template_file"
        return 1
    fi

    # Check if template contains any EMBED directives
    if ! grep -q '<!-- EMBED:' "$template_file"; then
        # No directives - return original path (no temp file created)
        echo "$template_file"
        return 1
    fi

    # Create temporary enriched file
    enriched_file=$(mktemp "${TMPDIR:-/tmp}/harmonize-enriched-XXXXXX.md")

    # Process line by line
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Check for EMBED directive: <!-- EMBED:path[#section] -->
        if [[ "$line" =~ \<!--\ EMBED:([^#\ >]+)(#([^\ >]+))?\ --\> ]]; then
            local embed_file="${BASH_REMATCH[1]}"
            local embed_section="${BASH_REMATCH[3]:-}"
            local full_path="${convention_dir}/${embed_file}"

            if [[ ! -f "$full_path" ]]; then
                log_warning "EMBED target not found: $full_path"
                echo "$line" >> "$enriched_file"
                continue
            fi

            if [[ -n "$embed_section" ]]; then
                # Extract specific section (## heading match)
                # URL-decode spaces: replace hyphens with spaces for matching
                local section_title="${embed_section//-/ }"
                _extract_section "$full_path" "$section_title" >> "$enriched_file"
            else
                # Embed entire file (skip YAML frontmatter if present)
                _strip_frontmatter "$full_path" >> "$enriched_file"
            fi
        else
            echo "$line" >> "$enriched_file"
        fi
    done < "$template_file"

    echo "$enriched_file"
    return 0
}

#
# Extract a specific ## section from a markdown file
#
# Arguments:
#   $1 - File path
#   $2 - Section title to extract (matches ## heading text)
#
# Output:
#   Section content (heading + body until next ## or EOF)
#
_extract_section() {
    local file="$1"
    local title="$2"
    local in_section=false
    local in_fence=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Track code fences to avoid false heading matches
        if [[ "$line" =~ ^\`\`\` ]]; then
            if $in_fence; then
                in_fence=false
            else
                in_fence=true
            fi
        fi

        if ! $in_fence; then
            if [[ "$line" =~ ^##\ (.+) ]]; then
                local heading="${BASH_REMATCH[1]}"
                # Case-insensitive comparison
                if [[ "${heading,,}" == "${title,,}" ]]; then
                    in_section=true
                    echo "$line"
                    continue
                elif $in_section; then
                    # Hit next ## heading - stop
                    break
                fi
            fi
        fi

        if $in_section; then
            echo "$line"
        fi
    done < "$file"
}

#
# Strip YAML frontmatter from a markdown file
#
# Arguments:
#   $1 - File path
#
# Output:
#   File content without leading --- ... --- frontmatter block
#
_strip_frontmatter() {
    local file="$1"

    awk '
        BEGIN { in_front=0; past_front=0; first_line=1 }
        first_line && /^---[[:space:]]*$/ { in_front=1; first_line=0; next }
        first_line { first_line=0; past_front=1 }
        in_front && /^---[[:space:]]*$/ { in_front=0; past_front=1; next }
        in_front { next }
        past_front { print }
    ' "$file"
}

#
# Apply harmonization to a single file
#
# Arguments:
#   $1 - Source file
#   $2 - Target file
#   $3 - Action (create or update)
#
harmonize_file() {
    local source_file="$1"
    local target_file="$2"
    local action="$3"

    # Validate source file exists before attempting copy
    if [[ ! -f "$source_file" ]]; then
        log_error "Source file not found: $source_file"
        return 1
    fi

    # Always ensure parent directory exists (handles both create and update)
    mkdir -p "$(dirname "$target_file")"

    case "$action" in
        create|update)
            cp "$source_file" "$target_file"
            ;;
    esac
}
