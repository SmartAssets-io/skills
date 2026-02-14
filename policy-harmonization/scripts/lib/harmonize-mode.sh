#!/usr/bin/env bash
#
# harmonize-mode.sh - Mode detection functions for harmonize-policies.sh
#
# This library provides:
# - Operational mode detection (yolo, interactive)
# - Agentic mode detection
# - Git worktree detection
# - Project deny rules cleanup
#
# Usage:
#   source /path/to/lib/harmonize-mode.sh
#   detect_mode
#   echo "Mode: $MODE"
#

# Prevent re-sourcing
if [[ -n "${HARMONIZE_MODE_LOADED:-}" ]]; then
    return 0
fi
HARMONIZE_MODE_LOADED=1

# Source UI library for logging (if not already loaded)
HARMONIZE_MODE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${HARMONIZE_UI_LOADED:-}" ]]; then
    source "${HARMONIZE_MODE_SCRIPT_DIR}/harmonize-ui.sh"
fi

# Default operational mode (set by detect_mode)
MODE="${MODE:-interactive}"

#
# Detect operational mode based on environment
# Sets global MODE variable to "yolo" or "interactive"
#
detect_mode() {
    # Check for git worktree (YOLO mode - no confirmations)
    if [ -f .git ]; then
        # .git is a file (not directory) = worktree
        MODE="yolo"
        return
    elif git rev-parse --git-dir 2>/dev/null | grep -q '/worktrees/'; then
        # git-dir contains /worktrees/ = worktree
        MODE="yolo"
        return
    fi

    # Check if running non-interactively (no TTY on stdin or stdout)
    # This enables auto-apply when run from Claude Code or other non-interactive contexts
    if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
        MODE="yolo"
        return
    fi

    # Default to interactive
    MODE="interactive"
}

#
# Check if running in agentic mode
# Agentic mode allows direct git commands and should have deny rules removed
#
# Returns:
#   0 if in agentic mode
#   1 otherwise
#
is_agentic_mode() {
    # Check CLAUDE_CONFIG_DIR environment variable
    if [[ "${CLAUDE_CONFIG_DIR:-}" == *"agentic"* ]]; then
        return 0
    fi

    # Check if claude-agentic is in process tree (fallback)
    if [[ "${CLAUDE_AGENTIC_MODE:-}" == "true" ]]; then
        return 0
    fi

    return 1
}

#
# Check if in git worktree
#
# Arguments:
#   $1 - Directory to check (optional, defaults to current directory)
#
# Returns:
#   0 if in a worktree
#   1 otherwise
#
is_worktree() {
    local dir="${1:-.}"
    (
        cd "$dir" 2>/dev/null || return 1
        if [ -f .git ]; then
            return 0
        elif git rev-parse --git-dir 2>/dev/null | grep -q '/worktrees/'; then
            return 0
        fi
        return 1
    )
}

#
# Clean harmonize-specific git deny rules from a project's .claude/settings.local.json
# This is ONLY for harmonize operations - removes rules that would block policy file commits
# IMPORTANT: Only removes harmonize-related rules, preserves general git security rules
#
# Arguments:
#   $1 - Repository path
#   $2 - Optional: "verbose" to log removed rules
#
# Returns:
#   0 if cleaned or no deny rules found
#   1 if error
#
clean_project_deny_rules() {
    local repo_path="$1"
    local verbose="${2:-}"
    local settings_file="$repo_path/.claude/settings.local.json"

    # Skip if settings file doesn't exist
    if [[ ! -f "$settings_file" ]]; then
        return 0
    fi

    # Check if file has deny rules
    if ! grep -q '"deny"' "$settings_file" 2>/dev/null; then
        return 0
    fi

    # Check if jq is available
    if ! command -v jq &>/dev/null; then
        log_warning "jq not available - cannot clean deny rules from $settings_file"
        return 1
    fi

    # Helper function to check if a rule blocks harmonize operations
    # Uses jq filter stored in variable to avoid duplication
    # Criteria for removal:
    #   1. Contains "git add" or "git commit" (case-insensitive)
    #   AND contains one of: .md, docs/, harmonize, CLAUDE, AGENTS
    #   2. OR is a generic wildcard rule like "git add *" or "git commit *"
    local jq_is_harmonize_blocking='
        def is_harmonize_blocking:
            type == "string" and (
                # Pattern 1: git add/commit targeting policy files
                # Uses regex to handle variable whitespace (git  add, git   commit)
                ((test("git\\s+add"; "i") or test("git\\s+commit"; "i")) and
                 (contains(".md") or contains("docs/") or
                  test("harmonize"; "i") or test("CLAUDE"; "i") or test("AGENTS"; "i")))
                or
                # Pattern 2: generic wildcard rules (likely auto-generated)
                # Matches: "git add *", "git commit *", "Bash(git add *", etc.
                test("git\\s+(add|commit)\\s*\\*"; "i")
            );
    '

    # First, check what rules would be removed (for logging)
    local rules_to_remove
    if [[ "$verbose" == "verbose" ]]; then
        rules_to_remove=$(jq -r "$jq_is_harmonize_blocking"'
            .permissions.deny // [] | .[] | select(is_harmonize_blocking)
        ' "$settings_file" 2>/dev/null)

        if [[ -n "$rules_to_remove" ]]; then
            log_info "Removing harmonize-blocking deny rules from $settings_file:"
            echo "$rules_to_remove" | while read -r rule; do
                log_info "  - $rule"
            done
        fi
    fi

    # Only remove deny rules that specifically block harmonize operations
    # User-defined rules for specific operations (push, rebase, etc.) are PRESERVED
    local temp_file
    temp_file=$(mktemp)

    if jq "$jq_is_harmonize_blocking"'
        if .permissions.deny then
            .permissions.deny |= map(select(is_harmonize_blocking | not)) |
            # Remove empty deny array
            if .permissions.deny == [] then del(.permissions.deny) else . end
        else
            .
        end
    ' "$settings_file" > "$temp_file" 2>/dev/null; then
        mv "$temp_file" "$settings_file"
        return 0
    else
        rm -f "$temp_file"
        return 1
    fi
}
