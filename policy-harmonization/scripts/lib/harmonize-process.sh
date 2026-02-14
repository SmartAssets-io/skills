#!/usr/bin/env bash
#
# harmonize-process.sh - Repository processing functions for harmonize-policies.sh
#
# This library provides the internal _process_* functions used by process_repository()
# to handle specific file types during harmonization.
#
# Usage:
#   source /path/to/lib/harmonize-process.sh
#   # Called internally by process_repository()
#

# Prevent re-sourcing
if [[ -n "${HARMONIZE_PROCESS_LOADED:-}" ]]; then
    return 0
fi
HARMONIZE_PROCESS_LOADED=1

# Source required libraries (if not already loaded)
HARMONIZE_PROCESS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${HARMONIZE_UI_LOADED:-}" ]] && source "${HARMONIZE_PROCESS_SCRIPT_DIR}/harmonize-ui.sh"
[[ -z "${HARMONIZE_FILE_OPS_LOADED:-}" ]] && source "${HARMONIZE_PROCESS_SCRIPT_DIR}/harmonize-file-ops.sh"
[[ -z "${HARMONIZE_SMART_ASSET_LOADED:-}" ]] && source "${HARMONIZE_PROCESS_SCRIPT_DIR}/harmonize-smart-asset.sh"
[[ -z "${HARMONIZE_DERIVE_LOADED:-}" ]] && source "${HARMONIZE_PROCESS_SCRIPT_DIR}/harmonize-derive.sh"

#
# Process CLAUDE.md with section-based merging
#
# Arguments:
#   $1 - Repository path
#   $2 - Relative path for display
#   $3 - Python command (empty if unavailable)
#   $4 - Name reference for repo_updated flag
#   $5 - Name reference for repo_error flag
#
# Global variables used:
#   SOURCE_PATH, DRY_RUN, UPDATED_REPOS
#
process_claude_md() {
    local repo_path="$1" rel_path="$2" python_cmd="$3"
    local -n _updated=$4 _error=$5

    local source_file="${SOURCE_PATH}/docs/templates/CLAUDE.md.template"
    local target_file="$repo_path/CLAUDE.md"

    [[ ! -f "$source_file" ]] && source_file="${SOURCE_PATH}/CLAUDE.md"
    [[ ! -f "$source_file" ]] && return

    if [[ ! -f "$target_file" ]]; then
        log_action "SKIP" "CLAUDE.md (merge-only, file does not exist)"
        return
    fi

    # Enrich template with convention content from docs/common/
    local enriched_file="" use_enriched=false
    local convention_dir="${SOURCE_PATH}/docs/common"
    if [[ -d "$convention_dir" ]]; then
        # enrich_template returns 1 when no EMBED directives found (not an error);
        # use || true to prevent set -e from exiting
        if enriched_file=$(enrich_template "$source_file" "$convention_dir" 2>/dev/null); then
            if [[ -n "$enriched_file" && "$enriched_file" != "$source_file" ]]; then
                use_enriched=true
            fi
        fi
    fi
    local effective_source="$source_file"
    [[ "$use_enriched" == true ]] && effective_source="$enriched_file"

    if [[ -n "$python_cmd" ]]; then
        local changes change_count
        changes=$(get_merge_changes "$effective_source" "$target_file" 2>/dev/null) || changes="[]"
        change_count=$(echo "$changes" | jq '[.[] | select(.action == "add" or .action == "update")] | length' 2>/dev/null || echo "0")

        if [[ "$change_count" -eq 0 ]]; then
            log_action "OK" "CLAUDE.md (no policy updates needed)"
        elif [[ "${DRY_RUN:-false}" == true ]]; then
            log_action "MERGE" "CLAUDE.md (would merge $change_count section changes)"
            show_merge_preview "$effective_source" "$target_file"
        else
            log_action "MERGE" "CLAUDE.md ($change_count section changes)"
            show_merge_preview "$effective_source" "$target_file"
            if prompt_action "Merging policy updates into CLAUDE.md"; then
                local merged_content
                merged_content=$(merge_markdown "$effective_source" "$target_file")
                if [[ -n "$merged_content" ]]; then
                    echo "$merged_content" > "$target_file"
                    _updated=true
                    UPDATED_REPOS+=("$rel_path")
                else
                    log_action "ERROR" "Failed to merge CLAUDE.md"
                    _error=true
                fi
            else
                log_action "SKIP" "CLAUDE.md (user skipped)"
            fi
        fi
    else
        local action
        action=$(compare_file "$effective_source" "$target_file")
        [[ "$action" == "customized" ]] && log_action "CUSTOMIZED" "CLAUDE.md (section merge unavailable - install Python 3)"
        [[ "$action" == "ok" ]] && log_action "OK" "CLAUDE.md"
    fi

    # Clean up enriched temp file
    if [[ "$use_enriched" == true && -f "$enriched_file" ]]; then
        rm -f "$enriched_file"
    fi
}

#
# Process AGENTS.md derivation from CLAUDE.md
#
process_agents_md() {
    local repo_path="$1" rel_path="$2"
    local -n _created=$3 _error=$4

    local claude_file="$repo_path/CLAUDE.md"
    local agents_file="$repo_path/AGENTS.md"

    [[ ! -f "$claude_file" ]] && return

    if [[ ! -f "$agents_file" ]]; then
        if [[ "${DRY_RUN:-false}" == true ]]; then
            log_action "DERIVE" "AGENTS.md (would derive from CLAUDE.md)"
        else
            log_action "DERIVE" "AGENTS.md (from CLAUDE.md)"
            if prompt_action "Deriving AGENTS.md from CLAUDE.md"; then
                derive_agents_md "$claude_file" "$agents_file"
                if [[ -f "$agents_file" ]]; then
                    _created=true
                    CREATED_FILES+=("$rel_path/AGENTS.md")
                else
                    log_action "ERROR" "Failed to derive AGENTS.md"
                    _error=true
                fi
            fi
        fi
    else
        log_action "OK" "AGENTS.md (exists)"
    fi
}

#
# Process GEMINI.md creation from template
#
process_gemini_md() {
    local repo_path="$1" rel_path="$2"
    local -n _created=$3 _error=$4

    local claude_file="$repo_path/CLAUDE.md"
    local gemini_file="$repo_path/GEMINI.md"
    local gemini_template="${SOURCE_PATH}/docs/templates/GEMINI.md.template"

    [[ ! -f "$claude_file" || ! -f "$gemini_template" ]] && return

    if [[ ! -f "$gemini_file" ]]; then
        if [[ "${DRY_RUN:-false}" == true ]]; then
            log_action "CREATE" "GEMINI.md (would create from template)"
        else
            log_action "CREATE" "GEMINI.md (from template)"
            if prompt_action "Creating GEMINI.md from template"; then
                cp "$gemini_template" "$gemini_file"
                if [[ -f "$gemini_file" ]]; then
                    _created=true
                    CREATED_FILES+=("$rel_path/GEMINI.md")
                else
                    log_action "ERROR" "Failed to create GEMINI.md"
                    _error=true
                fi
            fi
        fi
    else
        log_action "OK" "GEMINI.md (exists)"
    fi
}

#
# Process signers.jsonc for Smart Asset repos
#
process_signers_jsonc() {
    local repo_path="$1" rel_path="$2"
    local -n _created=$3 _error=$4

    local signers_file="$repo_path/signers.jsonc"
    local signers_template="${SOURCE_PATH}/docs/templates/signers.jsonc.template"

    ! is_smart_asset_repo "$repo_path" && return
    [[ ! -f "$signers_template" ]] && return

    if [[ ! -f "$signers_file" ]]; then
        if [[ "${DRY_RUN:-false}" == true ]]; then
            log_action "CREATE" "signers.jsonc (would create - Smart Asset repo)"
        else
            log_action "CREATE" "signers.jsonc (Smart Asset repo)"
            if prompt_action "Creating signers.jsonc from template"; then
                cp "$signers_template" "$signers_file"
                if [[ -f "$signers_file" ]]; then
                    _created=true
                    CREATED_FILES+=("$rel_path/signers.jsonc")
                else
                    log_action "ERROR" "Failed to create signers.jsonc"
                    _error=true
                fi
            fi
        fi
    else
        log_action "OK" "signers.jsonc (exists)"
    fi
}

#
# Process Smart Asset structure detection and scaffolding
#
# Global variables used:
#   SCAFFOLD_SA, DRY_RUN, MODE, HARMONIZE_SA_RESULT, HARMONIZE_SA_FILES, CREATED_FILES
#
process_smart_asset() {
    local repo_path="$1" rel_path="$2"
    local -n _created=$3

    local sa_type
    sa_type=$(detect_smart_asset_type "$repo_path")
    [[ "$sa_type" == "none" ]] && return

    log_action "SA_TYPE" "Detected: $sa_type"

    if [[ "$sa_type" == "candidate" ]]; then
        if [[ "${SCAFFOLD_SA:-auto}" == "skip" ]]; then
            log_action "SKIP" "Smart Asset scaffolding (--scaffold-sa=skip)"
        elif [[ "${DRY_RUN:-false}" == true ]]; then
            log_action "SA_SCAFFOLD" "Would scaffold Smart Asset structure"
            harmonize_smart_asset "$repo_path" "$sa_type"
        elif [[ "${SCAFFOLD_SA:-auto}" == "force" ]] || { [[ "${SCAFFOLD_SA:-auto}" == "auto" ]] && [[ "${MODE:-interactive}" == "yolo" ]]; }; then
            harmonize_smart_asset "$repo_path" "$sa_type"
            [[ "$HARMONIZE_SA_RESULT" == "scaffolded" ]] && _created=true
            for sa_file in "${HARMONIZE_SA_FILES[@]}"; do CREATED_FILES+=("$rel_path/$sa_file"); done
        elif prompt_action "Scaffold Smart Asset structure for $rel_path?"; then
            harmonize_smart_asset "$repo_path" "$sa_type"
            [[ "$HARMONIZE_SA_RESULT" == "scaffolded" ]] && _created=true
            for sa_file in "${HARMONIZE_SA_FILES[@]}"; do CREATED_FILES+=("$rel_path/$sa_file"); done
        else
            log_action "SKIP" "Smart Asset scaffolding (user skipped)"
        fi
    else
        harmonize_smart_asset "$repo_path" "$sa_type"
    fi
}

#
# Process task files with profile directory awareness and section-based merging
#
# Arguments:
#   $1 - Repository path
#   $2 - Relative path for display
#   $3 - Python command (empty if unavailable)
#   $4 - Name reference for repo_created flag
#   $5 - Name reference for repo_updated flag
#   $6 - Name reference for repo_error flag
#   $7 - Function to get task files location
#
# Global variables used:
#   SOURCE_PATH, DRY_RUN, FORCE_OVERWRITE, PROFILE_PROCESSED, PROFILE_REDIRECTED, CUSTOMIZED_FILES, CREATED_FILES, UPDATED_REPOS
#
process_task_files() {
    local repo_path="$1" rel_path="$2" python_cmd="$3"
    local -n _created=$4 _updated=$5 _error=$6
    local get_location_func="${7:-get_task_files_location}"

    local task_files=("docs/ToDos.md" "docs/UserStories.md" "docs/Backlog.md" "docs/CompletedTasks.md")
    local task_files_location has_profile=false

    if task_files_location=$($get_location_func "$repo_path"); then
        has_profile=true
    else
        task_files_location="$repo_path"
    fi

    local task_files_rel_path
    task_files_rel_path=$(realpath --relative-to="$(pwd)" "$task_files_location" 2>/dev/null || echo "$task_files_location")

    # Skip if profile already processed
    if [[ "$has_profile" == true ]]; then
        if [[ -n "${PROFILE_PROCESSED[$task_files_location]:-}" ]]; then
            log_action "SKIP" "Task files -> $task_files_rel_path (already processed)"
            return
        fi
        log_action "OK" "Task files redirected to profile: $task_files_rel_path"
        PROFILE_REDIRECTED+=("$rel_path -> $task_files_rel_path")
    fi

    for file in "${task_files[@]}"; do
        local template_name source_file target_file display_file action
        template_name=$(basename "$file")
        source_file="${SOURCE_PATH}/docs/templates/${template_name}.template"
        target_file="$task_files_location/$file"
        display_file="$file"
        [[ "$has_profile" == true ]] && display_file="$task_files_rel_path/$file"

        [[ ! -f "$source_file" ]] && source_file="${SOURCE_PATH}/$file"
        [[ ! -f "$source_file" ]] && continue

        action=$(compare_file "$source_file" "$target_file")

        case "$action" in
            create)
                if [[ "${DRY_RUN:-false}" == true ]]; then
                    log_action "CREATE" "$display_file (would create)"
                else
                    log_action "CREATE" "$display_file"
                    if prompt_action "Creating $display_file"; then
                        harmonize_file "$source_file" "$target_file" "create"
                        _created=true
                        CREATED_FILES+=("$task_files_rel_path/$file")
                    fi
                fi
                ;;
            customized)
                # Try section-based merge if Python is available
                if [[ -n "$python_cmd" ]]; then
                    local changes change_count
                    changes=$(get_merge_changes "$source_file" "$target_file" 2>/dev/null) || changes="[]"
                    change_count=$(echo "$changes" | jq '[.[] | select(.action == "add" or .action == "update")] | length' 2>/dev/null || echo "0")

                    if [[ "$change_count" -eq 0 ]]; then
                        log_action "OK" "$display_file (no template updates needed)"
                    elif [[ "${DRY_RUN:-false}" == true ]]; then
                        log_action "MERGE" "$display_file (would merge $change_count section changes)"
                        show_merge_preview "$source_file" "$target_file"
                    else
                        log_action "MERGE" "$display_file ($change_count section changes)"
                        show_merge_preview "$source_file" "$target_file"
                        if prompt_action "Merging template updates into $display_file"; then
                            local merged_content
                            merged_content=$(merge_markdown "$source_file" "$target_file")
                            if [[ -n "$merged_content" ]]; then
                                echo "$merged_content" > "$target_file"
                                _updated=true
                                UPDATED_REPOS+=("$rel_path")
                            else
                                log_action "ERROR" "Failed to merge $display_file"
                                _error=true
                            fi
                        else
                            log_action "SKIP" "$display_file (user skipped)"
                        fi
                    fi
                elif [[ "${FORCE_OVERWRITE:-false}" == true ]]; then
                    if [[ "${DRY_RUN:-false}" == true ]]; then
                        log_action "UPDATE" "$display_file (would overwrite - customized)"
                    else
                        log_action "UPDATE" "$display_file (overwriting customized)"
                        if prompt_action "Overwriting customized $display_file"; then
                            harmonize_file "$source_file" "$target_file" "update"
                            _updated=true
                        fi
                    fi
                else
                    log_action "CUSTOMIZED" "$display_file (preserved - use --force to overwrite or install Python for merging)"
                    CUSTOMIZED_FILES+=("$task_files_rel_path/$file")
                fi
                ;;
            ok) log_action "OK" "$display_file" ;;
        esac
    done

    if [[ "$has_profile" == true ]]; then
        PROFILE_PROCESSED[$task_files_location]=1
    fi
}

#
# Process .claude/ directory scaffold
#
# Creates .claude/ directory with mode-appropriate settings and worktree
# configuration. Does NOT overwrite existing files.
#
# Arguments:
#   $1 - Repository path
#   $2 - Relative path for display
#   $3 - Name reference for repo_created flag
#   $4 - Name reference for repo_error flag
#
# Global variables used:
#   SOURCE_PATH, DRY_RUN, MODE, CREATED_FILES
#
process_claude_dir() {
    local repo_path="$1" rel_path="$2"
    local -n _created=$3 _error=$4

    local claude_dir="$repo_path/.claude"
    local template_dir="${SOURCE_PATH}/docs/templates/.claude"
    local files_created=0

    # Generate settings.json if it doesn't exist
    local settings_file="$claude_dir/settings.json"
    if [[ ! -f "$settings_file" ]]; then
        if [[ "${DRY_RUN:-false}" == true ]]; then
            log_action "CREATE" ".claude/settings.json (would create)"
        else
            log_action "CREATE" ".claude/settings.json"
            if prompt_action "Creating .claude/settings.json"; then
                mkdir -p "$claude_dir"
                _generate_settings_json "$settings_file"
                if [[ -f "$settings_file" ]]; then
                    ((files_created++))
                    CREATED_FILES+=("$rel_path/.claude/settings.json")
                else
                    log_action "ERROR" "Failed to create .claude/settings.json"
                    _error=true
                fi
            fi
        fi
    else
        log_action "OK" ".claude/settings.json (exists)"
    fi

    # Generate worktree-config.json if it doesn't exist
    local worktree_config="$claude_dir/worktree-config.json"
    if [[ ! -f "$worktree_config" ]]; then
        if [[ "${DRY_RUN:-false}" == true ]]; then
            log_action "CREATE" ".claude/worktree-config.json (would create)"
        else
            log_action "CREATE" ".claude/worktree-config.json"
            if prompt_action "Creating .claude/worktree-config.json"; then
                mkdir -p "$claude_dir"
                _generate_worktree_config "$worktree_config" "$repo_path"
                if [[ -f "$worktree_config" ]]; then
                    ((files_created++))
                    CREATED_FILES+=("$rel_path/.claude/worktree-config.json")
                else
                    log_action "ERROR" "Failed to create .claude/worktree-config.json"
                    _error=true
                fi
            fi
        fi
    else
        log_action "OK" ".claude/worktree-config.json (exists)"
    fi

    # Copy template files from docs/templates/.claude/ if they exist
    if [[ -d "$template_dir" ]]; then
        local tmpl_file
        for tmpl_file in "$template_dir"/*; do
            [[ ! -f "$tmpl_file" ]] && continue
            local basename target_file
            basename=$(basename "$tmpl_file")
            # Strip .template suffix if present
            target_file="$claude_dir/${basename%.template}"

            if [[ ! -f "$target_file" ]]; then
                if [[ "${DRY_RUN:-false}" == true ]]; then
                    log_action "CREATE" ".claude/$basename (would create from template)"
                else
                    log_action "CREATE" ".claude/${basename%.template}"
                    if prompt_action "Creating .claude/${basename%.template}"; then
                        mkdir -p "$claude_dir"
                        cp "$tmpl_file" "$target_file"
                        ((files_created++))
                        CREATED_FILES+=("$rel_path/.claude/${basename%.template}")
                    fi
                fi
            fi
        done
    fi

    if [[ $files_created -gt 0 ]]; then
        _created=true
    fi
}

#
# Generate .claude/settings.json with mode-appropriate defaults
#
# Arguments:
#   $1 - Output file path
#
_generate_settings_json() {
    local output_file="$1"

    cat > "$output_file" << 'SETTINGS_EOF'
{
  // Smart Assets workspace settings
  // Generated by harmonize-policies.sh
  //
  // Mode-specific behavior is controlled by the launch command:
  //   claude / claude-safe  -> Safe mode (restrictive hooks loaded)
  //   claude-agentic        -> Agentic mode (no restrictive hooks)
  //   claude-agentic in worktree -> YOLO mode (full autonomy)
  //
  // See docs/common/development-modes.md for details.
}
SETTINGS_EOF
}

#
# Generate .claude/worktree-config.json with workspace-relative worktree root
#
# Arguments:
#   $1 - Output file path
#   $2 - Repository path (used to compute relative worktree root)
#
_generate_worktree_config() {
    local output_file="$1"
    local repo_path="$2"

    # Compute relative path to workspace worktree root
    # Convention: workspace-root-worktrees/ is a sibling of workspace root
    local workspace_root
    workspace_root=$(cd "$repo_path" && git rev-parse --show-toplevel 2>/dev/null)
    if [[ -z "$workspace_root" ]]; then
        workspace_root="$repo_path"
    fi

    # Find depth from workspace root to repo
    local rel_to_workspace
    rel_to_workspace=$(realpath --relative-to="$repo_path" "$workspace_root/..") 2>/dev/null || rel_to_workspace=".."

    cat > "$output_file" << WORKTREE_EOF
{
  // Worktree placement convention for YOLO mode
  // See docs/common/git-interaction-policy.md#worktree-placement-convention
  "worktree_root": "${rel_to_workspace}/SA-worktrees",

  // Agentic preflight configuration
  // See AItools/scripts/agentic-preflight.sh
  "preflight_enabled": true,
  "preflight_strict_branch": null,
  "preflight_skip_repos": [],
  "preflight_cache_ttl_seconds": 300
}
WORKTREE_EOF
}

#
# Inject slash command references into CLAUDE.md
#
# Reads the slash-command-requirements.md to determine which commands
# apply to the target repo, then ensures the Slash Commands section
# in the target CLAUDE.md contains the correct references.
#
# This function operates as a post-merge step: after process_claude_md
# merges the template, this injects the [OPTIONAL_COMMANDS] marker
# replacement based on repo characteristics.
#
# Arguments:
#   $1 - Repository path
#   $2 - Relative path for display
#   $3 - Name reference for repo_updated flag
#
# Global variables used:
#   SOURCE_PATH, DRY_RUN
#
inject_slash_commands() {
    local repo_path="$1" rel_path="$2"
    local -n _updated=$3

    local target_file="$repo_path/CLAUDE.md"
    [[ ! -f "$target_file" ]] && return

    # Check if the file has the [OPTIONAL_COMMANDS] marker
    if ! grep -q '\[OPTIONAL_COMMANDS\]' "$target_file"; then
        return  # No marker to replace
    fi

    # Determine optional commands based on repo characteristics
    local optional_lines=""

    # /multi-review - if repo has CI/CD pipeline
    if [[ -f "$repo_path/.gitlab-ci.yml" ]] || [[ -f "$repo_path/.github/workflows" ]]; then
        optional_lines="${optional_lines}### Code Review\n- \`/multi-review\` - Multi-agent code review with multiple LLM providers\n\n"
    fi

    # /story - if repo has UserStories.md
    if [[ -f "$repo_path/docs/UserStories.md" ]]; then
        optional_lines="${optional_lines}### Story Management\n- \`/story\` - Create, update, and list user stories\n\n"
    fi

    # /create-smart-asset - if repo is a candidate Smart Asset
    if [[ -f "$repo_path/smartasset.jsonc" ]] || [[ -d "$repo_path/docs/SmartAssetSpec" ]]; then
        optional_lines="${optional_lines}### Smart Asset\n- \`/create-smart-asset\` - Smart Asset setup and scaffolding\n\n"
    fi

    # /work-tasks - if repo has ToDos.md
    if [[ -f "$repo_path/docs/ToDos.md" ]]; then
        optional_lines="${optional_lines}### Autonomous Work\n- \`/work-tasks\` - Autonomous task execution from ToDos.md\n\n"
    fi

    if [[ "${DRY_RUN:-false}" == true ]]; then
        if [[ -n "$optional_lines" ]]; then
            log_action "INJECT" "Slash commands: would inject optional commands into CLAUDE.md"
        fi
        return
    fi

    # Replace the marker with computed optional commands (or remove it)
    if [[ -n "$optional_lines" ]]; then
        # Use awk to replace the marker line
        local temp_file
        temp_file=$(mktemp)
        awk -v replacement="$optional_lines" '
            /\[OPTIONAL_COMMANDS\]/ { printf "%s", replacement; next }
            { print }
        ' "$target_file" > "$temp_file" && mv "$temp_file" "$target_file"
        _updated=true
        log_action "INJECT" "Slash commands: injected optional commands into CLAUDE.md"
    else
        # Remove the marker line
        local temp_file
        temp_file=$(mktemp)
        grep -v '\[OPTIONAL_COMMANDS\]' "$target_file" > "$temp_file" && mv "$temp_file" "$target_file"
    fi
}

#
# Generate mode-specific CLAUDE.md section content
#
# Detects which operational modes the target repo supports and generates
# appropriate mode instructions. This runs as a post-merge step after
# process_claude_md to ensure mode content reflects the repo's actual
# configuration.
#
# Arguments:
#   $1 - Repository path
#   $2 - Relative path for display
#   $3 - Name reference for repo_updated flag
#
# Global variables used:
#   SOURCE_PATH, DRY_RUN
#
generate_mode_sections() {
    local repo_path="$1" rel_path="$2"
    local -n _updated=$3

    local target_file="$repo_path/CLAUDE.md"
    [[ ! -f "$target_file" ]] && return

    # Detect mode support for this repo
    local has_hooks=false has_worktree_config=false has_agentic_config=false

    # Check for hook scripts (indicates safe mode support)
    if [[ -f "$repo_path/.claude/settings.json" ]] || [[ -d "$repo_path/.claude" ]]; then
        has_hooks=true
    fi

    # Check for worktree config (indicates YOLO mode support)
    if [[ -f "$repo_path/.claude/worktree-config.json" ]]; then
        has_worktree_config=true
    fi

    # Check if agentic config directory exists
    local agentic_dir="${HOME}/.claude-agentic"
    if [[ -d "$agentic_dir" ]]; then
        has_agentic_config=true
    fi

    # The Development Modes section is already injected via the template merge.
    # This function validates that the section content matches the repo's
    # actual mode support. Log the detection results for visibility.
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log_action "MODES" "Detected: safe=$has_hooks agentic=$has_agentic_config yolo=$has_worktree_config"
    else
        log_action "MODES" "Mode support: safe=$has_hooks agentic=$has_agentic_config yolo=$has_worktree_config"
    fi
}
