#!/usr/bin/env bash
# Claude Code Quick Commit Script
# Deterministic git commit execution for single-repo and multi-repo modes
#
# Mode detection (for Claude to call first):
#   ~/.claude/scripts/quick-commit.sh --detect-mode           # Returns JSON mode decision
#
# Single-repo mode (default when no nested repos):
#   ~/.claude/scripts/quick-commit.sh "commit message"
#   ~/.claude/scripts/quick-commit.sh  # auto-generates simple message
#
# Single-repo mode (forced, bypasses auto-detection):
#   ~/.claude/scripts/quick-commit.sh --single-repo "commit message"
#
# Multi-repo mode (MULTI_REPO=true):
#   ~/.claude/scripts/quick-commit.sh --discover              # List repos with changes
#   ~/.claude/scripts/quick-commit.sh --execute "repo1:msg1" "repo2:msg2"  # Commit with messages
#
# Safety features:
# - NEVER runs git add - only commits tracked modified/deleted files
# - Warns about untracked files
# - Auto-fixes formatting before commit (biome/prettier/eslint)
# - Retries once if pre-commit hook fails after auto-fix
# - Threshold-based approval for multi-repo (>5 files or >2 repos)
#
# Safety model:
# - In safe mode, the git-hook.sh intercepts and prompts user for permission
# - The hook prompt is the primary safeguard against proactive commits
# - After each successful commit, dangerous allow rules are auto-cleaned
#   (fixes Claude Code's permission model that persists wildcarded approvals)
# - Set QUICK_COMMIT_CONFIRM=true to also require interactive TTY confirmation
# - TTY confirmation is optional but provides defense-in-depth for direct CLI use

set -e

# Configuration
THRESHOLD_FILES=5
THRESHOLD_REPOS=2

# Optional TTY confirmation (disabled by default)
# In safe mode, the hook permission prompt is the primary safeguard
# Set QUICK_COMMIT_CONFIRM=true for additional TTY confirmation (direct CLI use)
REQUIRE_CONFIRMATION="${QUICK_COMMIT_CONFIRM:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source repo-selection library (optional - graceful if missing)
if [[ -f "$SCRIPT_DIR/lib/repo-selection.sh" ]]; then
    source "$SCRIPT_DIR/lib/repo-selection.sh"
fi

# Clean up dangerous Claude Code allow rules after commit
# This fixes the permission model mismatch where approving quick-commit.sh
# via hook prompt saves a wildcarded allow rule that bypasses future prompts
cleanup_dangerous_allow_rules() {
    local audit_script="$SCRIPT_DIR/audit-allow-rules.sh"
    if [[ -x "$audit_script" ]]; then
        # Run silently - only output if there's an actual problem
        "$audit_script" --fix --quiet 2>/dev/null || true
    fi
}

# Optional interactive confirmation
# Provides defense-in-depth for direct CLI use
# In Claude Code safe mode, the hook permission prompt is the primary safeguard
confirm_commit() {
    # Skip if not enabled (default)
    if [ "$REQUIRE_CONFIRMATION" != "true" ]; then
        return 0
    fi

    # Check if running interactively (has a TTY)
    if [ ! -t 0 ]; then
        log_error "TTY confirmation requested but no TTY available"
        echo "Set QUICK_COMMIT_CONFIRM=false to skip interactive confirmation"
        exit 1
    fi

    echo ""
    echo -n "Proceed with commit? [y/N]: "
    read -r response
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            log_warning "Commit cancelled - good catch if this was proactive!"
            exit 0
            ;;
    esac
}

# Check if in git worktree (YOLO mode)
# Uses git -C to avoid changing working directory
is_worktree() {
    local dir="${1:-.}"
    if [ -f "$dir/.git" ]; then
        # .git is a file (not directory) = worktree
        return 0
    elif git -C "$dir" rev-parse --git-dir 2>/dev/null | grep -q '/worktrees/'; then
        # git-dir contains /worktrees/ = worktree
        return 0
    fi
    return 1
}

# Check .sh file permissions in git index
# Auto-fixes 100644 -> 100755 for .sh files being committed
# Args: $1 = repo path (optional, defaults to ".")
check_sh_permissions() {
    local repo_path="${1:-.}"

    # Collect .sh files that will be part of this commit
    # (staged + tracked-modified that git commit -a will auto-stage)
    local sh_files
    sh_files=$(
        { git -C "$repo_path" diff --cached --name-only 2>/dev/null
          git -C "$repo_path" diff --name-only 2>/dev/null
        } | sort -u | grep '\.sh$' || true
    )

    if [[ -z "$sh_files" ]]; then
        return 0
    fi

    local fixed=0
    while IFS= read -r sh_file; do
        local file_mode
        file_mode=$(git -C "$repo_path" ls-files --stage "$sh_file" 2>/dev/null | awk '{print $1}')
        if [[ "$file_mode" == "100644" ]]; then
            log_warning ".sh file not executable in git: $sh_file (mode $file_mode)"
            if git -C "$repo_path" update-index --chmod=+x "$sh_file" 2>/dev/null; then
                log_info "Auto-fixed: $sh_file -> 100755"
                fixed=$((fixed + 1))
            fi
        fi
    done <<< "$sh_files"

    if [[ $fixed -gt 0 ]]; then
        log_info "Fixed $fixed .sh file(s) with missing executable bit"
    fi

    return 0
}

# Pre-flight checks before commit
# Validates: author identity, HEAD state, .sh permissions, repo root
# Args: $1 = repo path (optional, defaults to ".")
preflight_commit_checks() {
    local repo_path="${1:-.}"
    local errors=0

    # 1. Git author identity must be configured
    local user_name user_email
    user_name=$(git -C "$repo_path" config user.name 2>/dev/null || echo "")
    user_email=$(git -C "$repo_path" config user.email 2>/dev/null || echo "")
    if [[ -z "$user_name" || -z "$user_email" ]]; then
        log_error "Git author identity not configured in $repo_path"
        if [[ -z "$user_name" ]]; then
            echo "  Missing: user.name"
        fi
        if [[ -z "$user_email" ]]; then
            echo "  Missing: user.email"
        fi
        echo "  Fix: git config user.name \"Your Name\" && git config user.email \"you@example.com\""
        errors=$((errors + 1))
    fi

    # 2. Reject commits in detached HEAD state
    if ! git -C "$repo_path" symbolic-ref HEAD >/dev/null 2>&1; then
        log_error "Detached HEAD in $repo_path"
        echo "  HEAD at: $(git -C "$repo_path" rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
        echo "  Fix: git checkout <branch-name>"
        errors=$((errors + 1))
    fi

    # 3. Ensure .sh files have executable bit in git index (auto-fix)
    check_sh_permissions "$repo_path"

    # 4. Verify repo root matches working directory
    local actual_root expected_root
    actual_root=$(git -C "$repo_path" rev-parse --show-toplevel 2>/dev/null || echo "")
    if [[ "$repo_path" == "." ]]; then
        expected_root=$(pwd)
    else
        expected_root=$(cd "$repo_path" && pwd)
    fi
    if [[ -n "$actual_root" && "$actual_root" != "$expected_root" ]]; then
        log_warning "Working directory is not repo root"
        echo "  Working dir: $expected_root"
        echo "  Repo root:   $actual_root"
        echo "  Commits will affect the full repository at $actual_root"
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Pre-flight failed: $errors blocking issue(s)"
        return 1
    fi

    return 0
}

# Check for untracked files and warn
# Always returns 0 (success) - this is informational only
# Args: $1 = repo path (optional, defaults to ".")
warn_untracked() {
    local repo_path="${1:-.}"
    local untracked
    untracked=$(git -C "$repo_path" ls-files --others --exclude-standard)
    if [ -n "$untracked" ]; then
        echo ""
        log_warning "Untracked files detected (will NOT be committed):"
        echo "$untracked" | sed 's/^/  /'
        echo ""
        echo "To include these files, run 'git add <files>' yourself, then re-run this script"
        echo ""
    fi
    return 0
}

# Auto-fix formatting issues before commit
# Detects project type and runs the appropriate lint/format command
# Args: $1 = repo path (optional, defaults to ".")
auto_fix_formatting() {
    local repo_path="${1:-.}"
    echo "=== Auto-fixing formatting ==="

    # JavaScript/TypeScript projects: try common fix/format scripts
    if [ -f "$repo_path/package.json" ]; then
        if command -v pnpm &> /dev/null; then
            # Try lint:fix first (common convention for auto-fix)
            if grep -q '"lint:fix"' "$repo_path/package.json" 2>/dev/null; then
                log_info "Running pnpm lint:fix..."
                ( cd "$repo_path" && pnpm lint:fix 2>/dev/null ) || true
                return 0
            fi
            # Try format script (common for prettier/biome format)
            if grep -q '"format"' "$repo_path/package.json" 2>/dev/null; then
                log_info "Running pnpm format..."
                ( cd "$repo_path" && pnpm format 2>/dev/null ) || true
                return 0
            fi
            # Fallback: run lint (check only, may still help with pre-commit hooks)
            if grep -q '"lint"' "$repo_path/package.json" 2>/dev/null; then
                log_info "Running pnpm lint..."
                ( cd "$repo_path" && pnpm lint 2>/dev/null ) || true
                return 0
            fi
        fi
    fi

    # Rust projects: use cargo clippy with fix
    if [ -f "$repo_path/Cargo.toml" ]; then
        if command -v cargo &> /dev/null; then
            log_info "Running cargo clippy --fix..."
            ( cd "$repo_path" && cargo clippy --fix --allow-dirty --allow-staged 2>/dev/null ) || true
            return 0
        fi
    fi

    # Python projects: try ruff (fast), then black
    if [ -f "$repo_path/pyproject.toml" ] || [ -f "$repo_path/setup.py" ] || [ -f "$repo_path/requirements.txt" ]; then
        if command -v ruff &> /dev/null; then
            log_info "Running ruff check --fix..."
            ( cd "$repo_path" && ruff check --fix . 2>/dev/null ) || true
            ( cd "$repo_path" && ruff format . 2>/dev/null ) || true
            return 0
        elif command -v black &> /dev/null; then
            log_info "Running black..."
            ( cd "$repo_path" && black . 2>/dev/null ) || true
            return 0
        fi
    fi

    log_info "No linter detected, skipping auto-fix"
    return 0
}

# Execute commit with retry on pre-commit hook failure
# Args: $1 = commit message, $2 = repo path (optional, defaults to ".")
do_commit_with_retry() {
    local message="$1"
    local repo_path="${2:-.}"
    local attempt=1
    local max_attempts=2
    local commit_result

    while [ $attempt -le $max_attempts ]; do
        echo "=== Creating commit (attempt $attempt/$max_attempts) ==="

        # Try to commit (disable set -e temporarily)
        set +e
        git -C "$repo_path" commit -a -m "$message"
        commit_result=$?
        set -e

        if [ $commit_result -eq 0 ]; then
            return 0
        fi

        # Commit failed - check if we should retry
        if [ $attempt -lt $max_attempts ]; then
            log_warning "Commit failed (exit code $commit_result), attempting auto-fix and retry..."
            auto_fix_formatting "$repo_path"
            echo ""
        else
            log_error "Commit failed after $max_attempts attempts"
            return 1
        fi

        attempt=$((attempt + 1))
    done

    return 1
}

# Single-repo mode
single_repo_commit() {
    local message="$1"

    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not in a git repository"
        exit 1
    fi

    # Pre-flight checks (author, HEAD state, .sh perms, repo root)
    if ! preflight_commit_checks; then
        exit 1
    fi

    echo "=== Git Status ==="
    git status --short

    # Check if there are any modified or deleted tracked files
    if git diff --quiet && git diff --cached --quiet; then
        echo ""
        log_error "No changes to commit - all tracked files are up to date"
        exit 1
    fi

    echo ""

    # Warn about untracked files
    warn_untracked

    # Use provided message or auto-generate
    if [ -n "$message" ]; then
        echo "=== Using provided commit message ==="
    else
        echo "=== Generating commit message from tracked changes ==="
        local num_files
        num_files=$(git diff --name-only | wc -l | tr -d ' ')
        if [ "$num_files" -eq 0 ]; then
            num_files=$(git diff --cached --name-only | wc -l | tr -d ' ')
        fi
        message="chore: update $num_files file(s)"
    fi

    echo "Commit message: $message"

    # Require user confirmation before proceeding
    confirm_commit

    echo ""

    # Auto-fix formatting BEFORE commit to avoid pre-commit hook failures
    auto_fix_formatting
    echo ""

    # Commit with retry logic
    if do_commit_with_retry "$message"; then
        echo ""
        log_success "Commit successful"
        git log -1 --oneline
        echo ""
        echo "Tip: Don't forget to push your changes with 'git push'"

        # Clean up dangerous allow rules that Claude Code may have saved
        cleanup_dangerous_allow_rules
    else
        exit 1
    fi
}

# Multi-repo: Discover repositories with changes
# Uses git -C to avoid changing working directory
discover_repos() {
    local start_dir
    start_dir=$(pwd)

    # Load repo selection config if not already loaded (standalone invocation)
    if [[ -z "${REPO_SELECTION_CONFIG:-}" ]] && type -t load_selection &>/dev/null; then
        load_selection "$start_dir"
    fi

    echo "{"
    echo '  "mode": "multi-repo",'
    echo '  "start_directory": "'"$start_dir"'",'
    echo '  "repositories": ['

    local first=true
    local total_files=0
    local repo_count=0

    while IFS= read -r git_dir; do
        local repo_dir
        repo_dir=$(dirname "$git_dir")

        # Use git -C instead of cd to avoid working directory issues
        local file_count
        file_count=$(git -C "$repo_dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

        if [ "$file_count" -gt 0 ]; then
            local rel_path
            rel_path=$(realpath --relative-to="$start_dir" "$repo_dir" 2>/dev/null || echo "$repo_dir")
            rel_path="${rel_path#./}"  # Strip ./ prefix (macOS realpath lacks --relative-to)

            # Skip repos not in selection config (if loaded)
            if type -t is_repo_selected &>/dev/null && [[ -n "${REPO_SELECTION_CONFIG:-}" ]]; then
                if ! is_repo_selected "$rel_path"; then
                    continue
                fi
            fi

            local branch
            branch=$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

            local in_worktree="false"
            if is_worktree "$repo_dir"; then
                in_worktree="true"
            fi

            local detached_head="false"
            if ! git -C "$repo_dir" symbolic-ref HEAD >/dev/null 2>&1; then
                detached_head="true"
            fi

            local changed_files
            changed_files=$(git -C "$repo_dir" status --porcelain | awk '{print $2}' | head -10 | tr '\n' ',' | sed 's/,$//')

            local untracked_count
            untracked_count=$(git -C "$repo_dir" ls-files --others --exclude-standard | wc -l | tr -d ' ')

            if [ "$first" = true ]; then
                first=false
            else
                echo ","
            fi

            echo '    {'
            echo '      "path": "'"$rel_path"'",'
            echo '      "absolute_path": "'"$repo_dir"'",'
            echo '      "branch": "'"$branch"'",'
            echo '      "file_count": '"$file_count"','
            echo '      "untracked_count": '"$untracked_count"','
            echo '      "in_worktree": '"$in_worktree"','
            echo '      "detached_head": '"$detached_head"','
            echo '      "changed_files": "'"$changed_files"'"'
            echo -n '    }'

            total_files=$((total_files + file_count))
            repo_count=$((repo_count + 1))
        fi
    done < <(find . -type d -name ".git" -not -path "*/node_modules/*" 2>/dev/null)

    echo ""
    echo '  ],'
    echo '  "summary": {'
    echo '    "total_repositories": '"$repo_count"','
    echo '    "total_files": '"$total_files"','
    echo '    "threshold_files": '"$THRESHOLD_FILES"','
    echo '    "threshold_repos": '"$THRESHOLD_REPOS"','

    local needs_approval="true"
    if [ "$total_files" -le "$THRESHOLD_FILES" ] && [ "$repo_count" -le "$THRESHOLD_REPOS" ]; then
        needs_approval="false"
    fi
    echo '    "needs_approval": '"$needs_approval"
    echo '  }'
    echo "}"
}

# Pre-flight consistency check for multi-repo operations
# Warns on inconsistency but does not block execution
preflight_consistency_check() {
    local checker="$SCRIPT_DIR/check-repo-consistency.sh"

    if [[ ! -x "$checker" ]]; then
        return 0  # Skip if checker not available
    fi

    # Run --check first (silent, exit code only)
    local check_exit=0
    "$checker" --check --changes-only >/dev/null 2>&1 || check_exit=$?

    if [[ $check_exit -ne 0 ]]; then
        log_warning "Workspace consistency issue detected (code $check_exit)"
        # Show abbreviated human report for context
        NO_COLOR=1 "$checker" --changes-only 2>/dev/null | awk '
            /Branch Status/,/^$/ { print }
            /Worktree Status/,/^$/ { print }
            /Verdict:/ { print }
        ' | head -15 | while IFS= read -r line; do
            echo "  $line"
        done
        echo ""
        log_info "Proceeding with commit (consistency check is advisory only)"
        echo ""
    fi

    return 0
}

# Multi-repo: Execute commits
# Arguments: "repo_path:commit_message" pairs
# Uses git -C to avoid changing working directory
execute_commits() {
    local success_count=0
    local failed_count=0
    local skipped_count=0

    echo "=========================================="
    echo "Multi-Repo Commit Execution"
    echo "=========================================="
    echo ""

    # Pre-flight consistency check (advisory only)
    preflight_consistency_check

    for arg in "$@"; do
        # Parse "repo_path:commit_message" format
        local repo_path="${arg%%:*}"
        local message="${arg#*:}"

        if [ "$repo_path" = "$arg" ]; then
            log_error "Invalid format: $arg (expected 'repo_path:commit_message')"
            failed_count=$((failed_count + 1))
            continue
        fi

        echo "----------------------------------------"
        echo "Repository: $repo_path"
        echo "----------------------------------------"

        # Verify repo path exists (use git -C instead of cd)
        if [ ! -d "$repo_path" ]; then
            log_error "Cannot access repository: $repo_path"
            failed_count=$((failed_count + 1))
            continue
        fi

        # Verify it's a git repo
        if ! git -C "$repo_path" rev-parse --git-dir > /dev/null 2>&1; then
            log_error "Not a git repository: $repo_path"
            failed_count=$((failed_count + 1))
            continue
        fi

        # Pre-flight checks (author, HEAD state, .sh perms, repo root)
        if ! preflight_commit_checks "$repo_path"; then
            log_error "Pre-flight checks failed for $repo_path"
            failed_count=$((failed_count + 1))
            continue
        fi

        local branch
        branch=$(git -C "$repo_path" rev-parse --abbrev-ref HEAD)
        echo "Branch: $branch"
        echo ""

        # Log context - detect mode
        if is_worktree "$repo_path"; then
            log_success "YOLO mode (git worktree) - proceeding"
        else
            log_info "Interactive mode - proceeding with commit"
        fi
        echo ""

        # Check for changes
        if git -C "$repo_path" diff --quiet && git -C "$repo_path" diff --cached --quiet; then
            log_warning "No tracked changes to commit in $repo_path"
            skipped_count=$((skipped_count + 1))
            echo ""
            continue
        fi

        # Warn about untracked files
        warn_untracked "$repo_path"

        # Show what will be committed
        echo "Changes to commit:"
        git -C "$repo_path" status --short
        echo ""

        # Create commit
        echo "Commit message: $message"

        # Require user confirmation before proceeding
        confirm_commit

        echo ""

        # Auto-fix formatting BEFORE commit
        auto_fix_formatting "$repo_path"
        echo ""

        if do_commit_with_retry "$message" "$repo_path"; then
            local commit_hash
            commit_hash=$(git -C "$repo_path" rev-parse --short HEAD)
            log_success "Commit created: $commit_hash"
            git -C "$repo_path" log -1 --oneline
            success_count=$((success_count + 1))
        else
            log_error "Commit failed"
            failed_count=$((failed_count + 1))
        fi

        echo ""
    done

    # Summary
    echo "=========================================="
    echo "Summary"
    echo "=========================================="
    echo "Successfully committed: $success_count"
    echo "Failed: $failed_count"
    echo "Skipped: $skipped_count"
    echo ""

    if [ "$success_count" -gt 0 ]; then
        log_success "Use /recursive-push to push all commits"

        # Clean up dangerous allow rules that Claude Code may have saved
        cleanup_dangerous_allow_rules
    fi

    # Return appropriate exit code
    if [ "$failed_count" -gt 0 ]; then
        exit 1
    fi
}

# Auto-detect nested git repositories
# Returns 0 (true) if nested repos exist, 1 (false) otherwise
has_nested_repos() {
    local nested_count
    nested_count=$(find . -mindepth 2 -type d -name ".git" -not -path "*/node_modules/*" 2>/dev/null | wc -l | tr -d ' ')
    [ "$nested_count" -gt 0 ]
}

# Mode detection with JSON output
# Outputs deterministic mode decision for Claude to use
detect_mode() {
    local git_root
    git_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

    local mode="single-repo"
    local reason=""
    local nested_count=0

    # Check explicit environment variable first
    if [ "${MULTI_REPO:-}" = "false" ]; then
        mode="single-repo"
        reason="MULTI_REPO explicitly set to false"
    elif [ "${MULTI_REPO:-false}" = "true" ]; then
        mode="multi-repo"
        reason="MULTI_REPO environment variable set to true"
    else
        # Auto-detect nested repositories (search from current directory downward only)
        nested_count=$(find . -mindepth 2 -type d -name ".git" -not -path "*/node_modules/*" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$nested_count" -gt 0 ]; then
            mode="multi-repo"
            reason="detected $nested_count nested repositories below current directory"
        else
            reason="no nested repositories found"
        fi
    fi

    echo "{"
    echo '  "mode": "'"$mode"'",'
    echo '  "reason": "'"$reason"'",'
    echo '  "nested_repo_count": '"$nested_count"','
    echo '  "git_root": "'"$git_root"'",'
    echo '  "working_directory": "'"$(pwd)"'",'
    echo '  "single_repo_override": "--single-repo flag bypasses auto-detection"'
    echo "}"
}

# Main entry point
main() {
    # Handle --detect-mode flag (before any other logic)
    if [ "${1:-}" = "--detect-mode" ]; then
        detect_mode
        exit 0
    fi

    # Handle --single-repo flag: force single-repo mode regardless of
    # nested repositories or MULTI_REPO env var. Useful when you only
    # want to commit tracked changes in the current git repository.
    if [ "${1:-}" = "--single-repo" ]; then
        log_info "Forced single-repo mode (--single-repo)"
        shift
        single_repo_commit "$1"
        return
    fi

    local multi_repo_mode=false

    # Check for explicit overrides via environment variable
    if [ "${MULTI_REPO:-}" = "false" ]; then
        # MULTI_REPO=false explicitly disables multi-repo auto-detection
        multi_repo_mode=false
    elif [ "${MULTI_REPO:-false}" = "true" ]; then
        multi_repo_mode=true
    else
        # Auto-detect: Check if there are nested git repositories
        if has_nested_repos; then
            log_info "Auto-detected nested git repositories - using multi-repo mode"
            log_info "Use --single-repo to commit only in the current repository"
            multi_repo_mode=true
        fi
    fi

    if [ "$multi_repo_mode" = true ]; then
        case "${1:-}" in
            --discover)
                discover_repos
                ;;
            --execute)
                shift
                if [ $# -eq 0 ]; then
                    log_error "No commit messages provided"
                    echo "Usage: $0 --execute 'repo1:message1' 'repo2:message2' ..."
                    exit 1
                fi
                execute_commits "$@"
                ;;
            "")
                log_error "Multi-repo mode requires --discover or --execute"
                echo ""
                echo "Usage:"
                echo "  $0 --discover                    # List repos with changes (JSON)"
                echo "  $0 --execute 'repo:msg' ...      # Execute commits"
                echo "  $0 --single-repo 'message'       # Force single-repo commit"
                exit 1
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --discover, --execute, or --single-repo in multi-repo workspace"
                exit 1
                ;;
        esac
    else
        # Single-repo mode
        single_repo_commit "$1"
    fi
}

main "$@"
