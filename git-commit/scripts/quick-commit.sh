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
# - Threshold-based approval for multi-repo (>5 files or >2 repos)
#
# Note: this script does NOT auto-fix formatting/lint issues. Mutating
# tracked files mid-commit (between staging and write-tree) caused
# index/cache-tree desync bugs. The pre-commit hook verifies only;
# fixing failures is the caller's responsibility (e.g., the LLM
# invoking /quick-commit should run the appropriate fixer, re-stage,
# and retry).
#
# Safety model:
# - In safe mode, the bash-permission-hook.sh intercepts and prompts user for permission
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

# Encode a kv-list value into the URL-safe subset defined in
# docs/designs/machine-readable-commit-format.md §4. Characters outside
# [A-Za-z0-9._/+:T-] become %XX (uppercase hex).
_quick_commit_kv_encode() {
    local input="$1"
    local out=""
    local i char
    local safe_re='^[A-Za-z0-9._/+:T-]$'
    for (( i=0; i<${#input}; i++ )); do
        char="${input:i:1}"
        if [[ "$char" =~ $safe_re ]]; then
            out+="$char"
        else
            out+=$(printf '%%%02X' "'$char")
        fi
    done
    printf '%s' "$out"
}

# Resolve the workspace root used to normalize per-repo identifiers into the
# workspace-relative form required by docs/designs/machine-readable-commit-format.md §2.1.
#
# Resolution order:
#   1. Walk up from $PWD looking for .multi-repo-selection.jsonc or
#      .multi-repo-selection.json; return its containing directory.
#   2. If $PWD is inside a git repo, return the parent of its toplevel
#      (matches the SATCHEL -> SA layout where workspace dirs hold sibling repos).
#   3. Fall back to $PWD.
_quick_commit_resolve_workspace_root() {
    # Walk up using the physical path so the result is consistent with
    # `git rev-parse --show-toplevel` (which always returns the realpath form).
    # This matters when the workspace lives under a symlinked path
    # (e.g. /var -> /private/var on macOS).
    local dir
    dir=$(pwd -P)
    local prev=""

    while [[ "$dir" != "$prev" && -n "$dir" ]]; do
        if [[ -f "$dir/.multi-repo-selection.jsonc" || -f "$dir/.multi-repo-selection.json" ]]; then
            printf '%s' "$dir"
            return 0
        fi
        prev="$dir"
        dir=$(dirname "$dir")
    done

    local toplevel
    if toplevel=$(git rev-parse --show-toplevel 2>/dev/null); then
        printf '%s' "$(dirname "$toplevel")"
        return 0
    fi

    pwd -P
}

# Convert a repo path (cwd-relative, absolute, or ".") into the workspace-relative
# form used as the `repo=` kv-list value. Falls back to the original input when
# the resolved absolute path lies outside the workspace root.
#
# Args:
#   $1 = repo_path as accepted by execute_commits (e.g. ".", "BountyForge/ssl_data_spigot",
#        or an absolute path)
#   $2 = absolute workspace root (from _quick_commit_resolve_workspace_root)
_quick_commit_workspace_relative() {
    local repo_path="$1" workspace_root="$2"
    local repo_abs

    # Always normalize to the physical path so prefix comparison against
    # workspace_root (also physical) works even under symlinked paths.
    if [[ -d "$repo_path" ]]; then
        repo_abs=$(cd "$repo_path" && pwd -P)
    elif [[ "$repo_path" == /* ]]; then
        repo_abs="$repo_path"
    else
        repo_abs="$(pwd -P)/$repo_path"
    fi
    repo_abs="${repo_abs%/}"

    local ws="${workspace_root%/}"
    if [[ "$repo_abs" == "$ws" ]]; then
        printf '%s' "$(basename "$ws")"
    elif [[ "$repo_abs" == "$ws"/* ]]; then
        printf '%s' "${repo_abs#"$ws"/}"
    else
        printf '%s' "$repo_path"
    fi
}

# Generate a batch identifier for a single recursive /quick-commit run.
# Shape: <UTC compact ISO>-<4 hex>, e.g. 20260516T204117Z-a1b2.
_quick_commit_generate_batch_id() {
    local ts hex
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    hex=$(od -An -N2 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' | head -c 4 || true)
    if [[ -z "$hex" ]]; then
        hex=$(printf '%04x' $(( ($$ ^ RANDOM) & 0xFFFF )))
    fi
    printf '%s-%s' "$ts" "$hex"
}

# Compose a machine-readable recursive commit message per
# docs/designs/machine-readable-commit-format.md.
#
# Args:
#   $1 = repo identifier (workspace-relative path)
#   $2 = batch id (from _quick_commit_generate_batch_id)
#   $3 = seq number (1-based)
#   $4 = total count of commits in this batch
#   $5 = branch name ("" or "HEAD" suppresses the branch key)
#   $6 = user-provided message (subject + optional body separated by \n)
#
# Output: rewritten message with kv-list prefix in the conventional-commit
# scope slot. Body and trailers are passed through unchanged.
build_machine_message() {
    local repo="$1" batch="$2" seq="$3" total="$4" branch="$5" user_msg="$6"

    # Split first line (subject) from rest (body)
    local subject body
    subject="${user_msg%%$'\n'*}"
    if [[ "$user_msg" == *$'\n'* ]]; then
        body=$'\n'"${user_msg#*$'\n'}"
    else
        body=""
    fi

    # Parse conventional commit: type(scope)?: summary
    local type="" scope="" summary=""
    local cc_re='^([a-z]+)(\(([^)]*)\))?:[[:space:]]+(.*)$'
    if [[ "$subject" =~ $cc_re ]]; then
        type="${BASH_REMATCH[1]}"
        scope="${BASH_REMATCH[3]}"
        summary="${BASH_REMATCH[4]}"
    else
        type="chore"
        summary="$subject"
    fi

    # Canonical key order: repo, batch, seq, branch, scope
    local kv="repo=$(_quick_commit_kv_encode "$repo"),batch=$(_quick_commit_kv_encode "$batch")"
    if [[ "$total" -gt 1 ]]; then
        kv+=",seq=${seq}/${total}"
    fi
    if [[ -n "$branch" && "$branch" != "HEAD" ]]; then
        kv+=",branch=$(_quick_commit_kv_encode "$branch")"
    fi
    if [[ -n "$scope" ]]; then
        kv+=",scope=$(_quick_commit_kv_encode "$scope")"
    fi

    printf '%s(%s): %s%s' "$type" "$kv" "$summary" "$body"
}

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
            log_warning "Commit failed (exit code $commit_result), retrying..."
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

# Emit one repository entry as JSON. Used by discover_repos() for both
# the synthetic start-directory entry and each nested repo entry.
# Args: $1 = first-flag-name (var name to track JSON comma separator),
#       $2 = repo_dir (relative path or "."),
#       $3 = is_start_directory ("true"/"false"),
#       $4 = start_dir (absolute path of discovery root)
# Returns: file count contributed by this entry, written to stdout-after-JSON
#          via the global $LAST_REPO_FILE_COUNT variable.
# Side effects (selection-config tracking):
# - EXCLUDED_TOTAL_COUNT increments for every repo this discovery encounters
#   that is filtered out by the selection config — regardless of whether
#   that repo has uncommitted changes. This counter is what populates the
#   `selection.excluded_total` field in --discover JSON, replacing an
#   earlier (wrong) reading from REPO_SELECTION_EXCLUDED that returned 0
#   for include-mode configs even when many repos were filtered.
# - EXCLUDED_WITH_CHANGES additionally records rel_path for excluded repos
#   that have porcelain entries, so the skill can surface them to the user.
LAST_REPO_FILE_COUNT=0
EXCLUDED_WITH_CHANGES=()
EXCLUDED_TOTAL_COUNT=0
emit_repo_entry() {
    local first_var="$1"
    local repo_dir="$2"
    local is_start_directory="$3"
    local start_dir="$4"
    LAST_REPO_FILE_COUNT=0

    # Compute rel_path up front; both the selection check and the JSON
    # emission below rely on it.
    local rel_path
    if [ "$is_start_directory" = "true" ]; then
        rel_path="."
    else
        rel_path=$(realpath --relative-to="$start_dir" "$repo_dir" 2>/dev/null || echo "$repo_dir")
        rel_path="${rel_path#./}"  # Strip ./ prefix (macOS realpath lacks --relative-to)
    fi

    # Selection-config check runs BEFORE the file_count early-return so
    # the EXCLUDED_TOTAL_COUNT tally includes filtered repos that happen
    # to be clean. The start-directory entry is always exempt from
    # filtering — dropping it silently is the bug that motivated the
    # is_start_directory flag.
    local is_excluded="false"
    if [ "$is_start_directory" != "true" ] \
        && type -t is_repo_selected &>/dev/null \
        && [[ -n "${REPO_SELECTION_CONFIG:-}" ]]; then
        local selection_path="$rel_path"
        if [[ -n "${REPO_SELECTION_ROOT:-}" && "$REPO_SELECTION_ROOT" != "$start_dir" ]]; then
            local abs_repo_dir
            abs_repo_dir=$(cd "$repo_dir" && pwd)
            selection_path="${abs_repo_dir#"$REPO_SELECTION_ROOT"/}"
        fi
        if ! is_repo_selected "$selection_path"; then
            is_excluded="true"
            EXCLUDED_TOTAL_COUNT=$((EXCLUDED_TOTAL_COUNT + 1))
        fi
    fi

    local file_count
    file_count=$(git -C "$repo_dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

    if [ "$is_excluded" = "true" ]; then
        # Excluded repos with porcelain entries get surfaced separately so
        # the user sees what the config dropped. Excluded-and-clean repos
        # are tallied (EXCLUDED_TOTAL_COUNT above) but not surfaced — they
        # have no actionable signal.
        if [ "$file_count" -gt 0 ]; then
            EXCLUDED_WITH_CHANGES+=("$rel_path")
        fi
        return 0
    fi

    if [ "$file_count" -eq 0 ]; then
        return 0
    fi

    local abs_repo_dir
    abs_repo_dir=$(cd "$repo_dir" && pwd)

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

    if [ "${!first_var}" = "true" ]; then
        printf -v "$first_var" "false"
    else
        echo ","
    fi

    echo '    {'
    echo '      "path": "'"$rel_path"'",'
    echo '      "absolute_path": "'"$abs_repo_dir"'",'
    echo '      "is_start_directory": '"$is_start_directory"','
    echo '      "branch": "'"$branch"'",'
    echo '      "file_count": '"$file_count"','
    echo '      "untracked_count": '"$untracked_count"','
    echo '      "in_worktree": '"$in_worktree"','
    echo '      "detached_head": '"$detached_head"','
    echo '      "changed_files": "'"$changed_files"'"'
    echo -n '    }'

    LAST_REPO_FILE_COUNT=$file_count
    return 0
}

# Multi-repo: Discover repositories with changes
# Uses git -C to avoid changing working directory
discover_repos() {
    local start_dir
    start_dir=$(pwd)

    # Reset selection-tracking state for this discovery run.
    EXCLUDED_WITH_CHANGES=()
    EXCLUDED_TOTAL_COUNT=0

    # Load repo selection config if not already loaded (standalone invocation)
    if [[ -z "${REPO_SELECTION_CONFIG:-}" ]] && type -t load_selection &>/dev/null; then
        load_selection "$start_dir"
    fi

    # Inspect cwd as a potential start-directory repo. Including it
    # explicitly (with is_start_directory: true) prevents the silent-drop
    # bug where a workspace root with tracked changes plus nested repos
    # would have its cwd changes omitted from discover output.
    local sd_is_git_repo="false"
    local sd_has_changes="false"
    local sd_origin=""
    if git rev-parse --git-dir >/dev/null 2>&1; then
        sd_is_git_repo="true"
        if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
            sd_has_changes="true"
        fi
        sd_origin=$(cwd_origin)
    fi

    echo "{"
    echo '  "mode": "multi-repo",'
    echo '  "start_directory": {'
    echo '    "path": "'"$start_dir"'",'
    echo '    "is_git_repo": '"$sd_is_git_repo"','
    echo '    "has_changes": '"$sd_has_changes"','
    echo '    "origin": "'"$sd_origin"'",'
    echo '    "included_in_array": '"$sd_has_changes"
    echo '  },'
    echo '  "repositories": ['

    local first=true
    local total_files=0
    local repo_count=0

    # Emit start-directory entry first (when applicable) so consumers
    # that read sequentially see it before any nested entries.
    if [ "$sd_has_changes" = "true" ]; then
        emit_repo_entry first "." "true" "$start_dir"
        if [ "$LAST_REPO_FILE_COUNT" -gt 0 ]; then
            total_files=$((total_files + LAST_REPO_FILE_COUNT))
            repo_count=$((repo_count + 1))
        fi
    fi

    # Walk nested .git directories (mindepth 2 skips cwd's own .git, which
    # is handled above as the start-directory entry).
    while IFS= read -r git_dir; do
        local repo_dir
        repo_dir=$(dirname "$git_dir")

        emit_repo_entry first "$repo_dir" "false" "$start_dir"
        if [ "$LAST_REPO_FILE_COUNT" -gt 0 ]; then
            total_files=$((total_files + LAST_REPO_FILE_COUNT))
            repo_count=$((repo_count + 1))
        fi
    done < <(find . -mindepth 2 -type d -name ".git" -not -path "*/node_modules/*" 2>/dev/null)

    echo ""
    echo '  ],'

    # Selection block: surface what the .multi-repo-selection.jsonc config
    # filtered out. Without this, the user has no signal that excluded
    # repos with uncommitted changes were silently dropped.
    #
    # excluded_total counts repos this discovery encountered that the config
    # filtered out (regardless of whether they had changes). It is NOT the
    # size of the config's literal exclude list — that interpretation gave
    # zero for include-mode configs even when many repos were filtered, and
    # contradicted the EXCLUDED_WITH_CHANGES count.
    local config_loaded="false"
    local config_path=""
    if [[ -n "${REPO_SELECTION_CONFIG:-}" ]]; then
        config_loaded="true"
        config_path="$REPO_SELECTION_CONFIG"
    fi
    echo '  "selection": {'
    echo '    "config_path": "'"$config_path"'",'
    echo '    "config_loaded": '"$config_loaded"','
    echo '    "excluded_total": '"$EXCLUDED_TOTAL_COUNT"','
    echo -n '    "excluded_with_changes": ['
    if [ ${#EXCLUDED_WITH_CHANGES[@]} -gt 0 ]; then
        local sep=""
        local p
        for p in "${EXCLUDED_WITH_CHANGES[@]}"; do
            echo -n "$sep\"$p\""
            sep=", "
        done
    fi
    echo ']'
    echo '  },'

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

    # Batch identifier shared across every per-repo commit produced by this
    # recursive invocation. Injected into each commit message via the kv-list
    # prefix defined in docs/designs/machine-readable-commit-format.md.
    local batch_id total_pairs seq_index workspace_root
    batch_id=$(_quick_commit_generate_batch_id)
    workspace_root=$(_quick_commit_resolve_workspace_root)
    total_pairs=$#
    seq_index=0

    echo "=========================================="
    echo "Multi-Repo Commit Execution"
    echo "Batch: $batch_id"
    echo "=========================================="
    echo ""

    # Pre-flight consistency check (advisory only)
    preflight_consistency_check

    for arg in "$@"; do
        seq_index=$((seq_index + 1))

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

        # Inject the machine-readable kv-list prefix. Recursive runs always
        # emit the prefix so downstream tooling can reassemble the batch.
        # The repo identifier is normalized to a workspace-relative path per
        # docs/designs/machine-readable-commit-format.md §2.1 so a batch
        # launched from any cwd produces stable repo= values.
        local repo_id
        repo_id=$(_quick_commit_workspace_relative "$repo_path" "$workspace_root")
        message=$(build_machine_message \
            "$repo_id" "$batch_id" "$seq_index" "$total_pairs" \
            "$branch" "$message")

        # Create commit
        echo "Commit message: $message"

        # Require user confirmation before proceeding
        confirm_commit

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

# Returns the cwd repo's origin URL on stdout, or empty string when cwd is
# not a git repo or has no origin remote configured.
cwd_origin() {
    git remote get-url origin 2>/dev/null || true
}

# Returns 0 (true) if cwd is a git repo with tracked modifications that
# would be picked up by `git commit -a`. Returns 1 otherwise (not a repo,
# no tracked changes, or untracked-only).
cwd_has_tracked_changes() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        return 1
    fi
    if ! git diff --quiet 2>/dev/null; then
        return 0
    fi
    if ! git diff --cached --quiet 2>/dev/null; then
        return 0
    fi
    return 1
}

# Emit one origin URL per line for nested git repos that have changes.
# Skips nested repos whose remote.origin.url is unset.
nested_changed_origins() {
    while IFS= read -r git_dir; do
        local repo_dir
        repo_dir=$(dirname "$git_dir")
        if [ -n "$(git -C "$repo_dir" status --porcelain 2>/dev/null)" ]; then
            local origin
            origin=$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)
            [ -n "$origin" ] && echo "$origin"
        fi
    done < <(find . -mindepth 2 -type d -name ".git" -not -path "*/node_modules/*" 2>/dev/null)
}

# Decide the recommended default for ambiguous mode.
# Echoes "multi-repo" when cwd has no origin OR any nested repo with
# changes has an origin different from cwd's origin. Otherwise echoes
# "single-repo".
recommend_ambiguous_default() {
    local cwd_origin_url="$1"
    if [ -z "$cwd_origin_url" ]; then
        echo "multi-repo"
        return
    fi
    while IFS= read -r nested_origin; do
        if [ -n "$nested_origin" ] && [ "$nested_origin" != "$cwd_origin_url" ]; then
            echo "multi-repo"
            return
        fi
    done < <(nested_changed_origins)
    echo "single-repo"
}

# Mode detection with JSON output
# Outputs deterministic mode decision for Claude to use.
#
# Modes:
#   single-repo  - no nested repos, or MULTI_REPO=false override
#   multi-repo   - nested repos exist and cwd has no tracked changes (no risk
#                  of dropping cwd work), or MULTI_REPO=true override
#   ambiguous    - nested repos exist AND cwd has tracked changes; the
#                  caller MUST prompt the user (see recommended_default)
detect_mode() {
    local git_root
    git_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

    local mode="single-repo"
    local reason=""
    local nested_count=0
    local cwd_is_git_repo="false"
    local cwd_changes="false"
    local cwd_origin_url=""
    local recommended_default=""

    if [ -n "$git_root" ]; then
        cwd_is_git_repo="true"
        cwd_origin_url=$(cwd_origin)
        if cwd_has_tracked_changes; then
            cwd_changes="true"
        fi
    fi

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
        if [ "$nested_count" -eq 0 ]; then
            reason="no nested repositories found"
        elif [ "$cwd_changes" = "true" ]; then
            mode="ambiguous"
            reason="cwd has tracked changes AND $nested_count nested repositories detected"
            recommended_default=$(recommend_ambiguous_default "$cwd_origin_url")
        else
            mode="multi-repo"
            reason="detected $nested_count nested repositories; cwd has no tracked changes to drop"
        fi
    fi

    echo "{"
    echo '  "mode": "'"$mode"'",'
    echo '  "reason": "'"$reason"'",'
    echo '  "nested_repo_count": '"$nested_count"','
    echo '  "cwd_is_git_repo": '"$cwd_is_git_repo"','
    echo '  "cwd_has_tracked_changes": '"$cwd_changes"','
    echo '  "cwd_origin": "'"$cwd_origin_url"'",'
    if [ -n "$recommended_default" ]; then
        echo '  "recommended_default": "'"$recommended_default"'",'
    fi
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

# Only run main when executed directly. Tests source this file to call
# individual helpers (e.g. build_machine_message) in isolation.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
