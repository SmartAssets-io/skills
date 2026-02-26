#!/usr/bin/env bash
#
# harmonize-process.sh - Repository processing orchestration for harmonize-policies.sh
#
# Aggregates specialized processing modules and provides post-merge functions
# (slash command injection, mode section generation).
#
# Modules sourced:
#   harmonize-markdown.sh  - CLAUDE.md, AGENTS.md, GEMINI.md, task files
#   harmonize-scaffold.sh  - .claude/ directory, signers.jsonc, Smart Asset structure
#   harmonize-hooks.sh     - Git hook harmonization (pre-push race guard)
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

# Source required libraries and processing modules
HARMONIZE_PROCESS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${HARMONIZE_UI_LOADED:-}" ]] && source "${HARMONIZE_PROCESS_SCRIPT_DIR}/harmonize-ui.sh"
[[ -z "${HARMONIZE_FILE_OPS_LOADED:-}" ]] && source "${HARMONIZE_PROCESS_SCRIPT_DIR}/harmonize-file-ops.sh"
[[ -z "${HARMONIZE_SMART_ASSET_LOADED:-}" ]] && source "${HARMONIZE_PROCESS_SCRIPT_DIR}/harmonize-smart-asset.sh"
[[ -z "${HARMONIZE_DERIVE_LOADED:-}" ]] && source "${HARMONIZE_PROCESS_SCRIPT_DIR}/harmonize-derive.sh"
[[ -z "${HARMONIZE_MARKDOWN_LOADED:-}" ]] && source "${HARMONIZE_PROCESS_SCRIPT_DIR}/harmonize-markdown.sh"
[[ -z "${HARMONIZE_SCAFFOLD_LOADED:-}" ]] && source "${HARMONIZE_PROCESS_SCRIPT_DIR}/harmonize-scaffold.sh"
[[ -z "${HARMONIZE_HOOKS_LOADED:-}" ]] && source "${HARMONIZE_PROCESS_SCRIPT_DIR}/harmonize-hooks.sh"

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
