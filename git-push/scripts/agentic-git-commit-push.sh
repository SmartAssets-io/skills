#!/usr/bin/env bash
# Agentic Git Commit and Push Script
# This script commits and pushes changes in all repositories with modifications
#
# Usage:
#   agentic-git-commit-push.sh [OPTIONS] [COMMIT_MESSAGE]
#
# Options:
#   --push-only    Skip add/commit, only push existing unpushed commits
#                  Used by /recursive-push
#
# Examples:
#   agentic-git-commit-push.sh "feat: add new feature"     # Full add+commit+push
#   agentic-git-commit-push.sh --push-only                 # Push only (for /recursive-push)

set -euo pipefail

# Load multi-repo selection filter so this script honors
# .multi-repo-selection.jsonc the same way /quick-commit and /harmonize do.
# MULTI_REPO_ALL=true bypass is handled inside load_selection.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/lib/repo-selection.sh
source "$SCRIPT_DIR/../scripts/lib/repo-selection.sh"
load_selection "."

# Parse arguments
PUSH_ONLY=false
COMMIT_MESSAGE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --push-only)
            PUSH_ONLY=true
            shift
            ;;
        *)
            COMMIT_MESSAGE="$1"
            shift
            ;;
    esac
done

# Default commit message if not in push-only mode
if [ "$PUSH_ONLY" = false ] && [ -z "$COMMIT_MESSAGE" ]; then
    COMMIT_MESSAGE="Update documentation and common policy files"
fi

# Count files and repos before displaying warning
total_files=0
total_repos=0
total_unpushed=0

# Parallel arrays tracking repos whose current branch has no upstream
# configured. These are surfaced after the banner so the user knows local work
# exists; first push to a new remote branch stays an explicit manual action.
local_only_repos=()
local_only_branches=()
local_only_counts=()

while IFS= read -r git_dir; do
    repo_dir=$(dirname "$git_dir")
    repo_path="${repo_dir#./}"

    # Honor .multi-repo-selection.jsonc
    is_repo_selected "$repo_path" || continue

    # Skip empty repos (no HEAD): rev-parse/rev-list below would abort the script
    git -C "$repo_dir" rev-parse --verify HEAD >/dev/null 2>&1 || continue

    cd "$repo_dir"

    if [ "$PUSH_ONLY" = true ]; then
        # Count repos with unpushed commits, and separately track repos whose
        # current branch has no upstream configured.
        git fetch 2>/dev/null || true
        ahead_count=$(git rev-list --count @{upstream}..HEAD 2>/dev/null || echo "no-upstream")
        if [ "$ahead_count" = "no-upstream" ]; then
            # Use symbolic-ref to detect detached HEAD robustly. A name-based
            # check would misclassify a branch literally named "HEAD".
            if git symbolic-ref -q HEAD >/dev/null 2>&1; then
                current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
                local_commits=$(git rev-list --count HEAD 2>/dev/null || echo "0")
                if [ "$local_commits" -gt 0 ]; then
                    local_only_repos+=("$repo_dir")
                    local_only_branches+=("$current_branch")
                    local_only_counts+=("$local_commits")
                fi
            fi
        elif [ "$ahead_count" -gt 0 ]; then
            total_repos=$((total_repos + 1))
            total_unpushed=$((total_unpushed + ahead_count))
        fi
    else
        # Count repos with uncommitted changes
        file_count=$(git status --porcelain | wc -l | tr -d ' ')
        if [ "$file_count" -gt 0 ]; then
            total_repos=$((total_repos + 1))
            total_files=$((total_files + file_count))
        fi
    fi
    cd - > /dev/null 2>&1
done < <(find . -type d -name ".git" -not -path "*/node_modules/*")

# Threshold configuration
THRESHOLD_FILES=5
THRESHOLD_REPOS=2

# Display warning banner based on mode
if [ "$PUSH_ONLY" = true ]; then
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    AGENTIC PUSH MODE                          ║"
    echo "╟────────────────────────────────────────────────────────────────╢"
    echo "║ This script will push existing commits to remote repositories ║"
    echo "║                                                                 ║"
    echo "║ Current workspace status:                                      ║"
    printf "║  • %-2d commits across %-2d repositories                         ║\n" "$total_unpushed" "$total_repos"
    echo "║                                                                 ║"
    echo "║ Please ensure commits have been reviewed before pushing.       ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    # Surface local-only branches (no upstream) before deciding what to push.
    # First push to a new remote branch is treated as an explicit action — the
    # script reports these but does not auto-push them. Run the suggested
    # command per repo to publish a local-only branch.
    if [ "${#local_only_repos[@]}" -gt 0 ]; then
        echo "Local-only repositories (no upstream, skipped):"
        for i in "${!local_only_repos[@]}"; do
            printf "  - %s (branch: %s, %s commits)\n" \
                "${local_only_repos[$i]}" \
                "${local_only_branches[$i]}" \
                "${local_only_counts[$i]}"
        done
        echo ""
        echo "To push these, manually set an upstream:"
        echo "  git -C <repo> push --set-upstream origin <branch>"
        echo ""
    fi

    if [ "$total_repos" -eq 0 ]; then
        if [ "${#local_only_repos[@]}" -eq 0 ]; then
            echo "No repositories with unpushed commits found."
        else
            echo "No repositories with tracked unpushed commits; ${#local_only_repos[@]} local-only repo(s) above need manual --set-upstream."
        fi
        exit 0
    fi
else
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    AGENTIC MODE WARNING                       ║"
    echo "╟────────────────────────────────────────────────────────────────╢"
    echo "║ This script will autonomously:                                 ║"
    echo "║  • Add ALL changes (modified, new, deleted files)              ║"
    echo "║  • Create commits in multiple repositories                     ║"
    echo "║  • Push commits to remote repositories                         ║"
    echo "║                                                                 ║"
    echo "║ Current workspace changes:                                     ║"
    printf "║  • %-2d files across %-2d repositories                           ║\n" "$total_files" "$total_repos"
    echo "║                                                                 ║"

    # Show threshold warning if exceeded
    if [ "$total_files" -gt "$THRESHOLD_FILES" ] || [ "$total_repos" -gt "$THRESHOLD_REPOS" ]; then
        echo "║ Changes exceed recommended threshold:                          ║"
        printf "║  • Threshold: <=%d files across <=%d repos                      ║\n" "$THRESHOLD_FILES" "$THRESHOLD_REPOS"
        echo "║                                                                 ║"
        echo "║ To use threshold-based auto-commit instead, use:               ║"
        echo "║  ./commit-workspace-changes.sh \"message\"                       ║"
        echo "║                                                                 ║"
    fi

    echo "║ This includes NEW FILES that may contain sensitive data.       ║"
    echo "║ Please ensure you have reviewed all changes before proceeding. ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
fi

# Check if we're in a git worktree (YOLO mode)
in_worktree=false
if [ -f .git ]; then
    # .git is a file (not directory) = worktree
    in_worktree=true
elif git rev-parse --git-dir 2>/dev/null | grep -q '/worktrees/'; then
    # git-dir contains /worktrees/ = worktree
    in_worktree=true
fi

if [ "$in_worktree" = true ]; then
    echo "✓ YOLO mode detected (git worktree) - proceeding with autonomous git operations"
else
    echo "✓ Interactive Agentic mode - proceeding with git operations"
fi
echo ""

# Counter for repositories processed
repos_with_changes=0
repos_committed=0
repos_pushed=0

# Find all .git directories (excluding node_modules)
# Use process substitution to avoid subshell and preserve counter values
while read -r git_dir; do
    # Get the repository directory (parent of .git)
    repo_dir=$(dirname "$git_dir")
    repo_path="${repo_dir#./}"

    # Honor .multi-repo-selection.jsonc
    is_repo_selected "$repo_path" || continue

    # Skip empty repos (no HEAD): rev-parse below would abort the script
    git -C "$repo_dir" rev-parse --verify HEAD >/dev/null 2>&1 || continue

    # Change to repo directory
    cd "$repo_dir"

    # Get current branch early for both modes
    current_branch=$(git rev-parse --abbrev-ref HEAD)

    if [ "$PUSH_ONLY" = true ]; then
        # Push-only mode: check for unpushed commits (skip repos with no upstream - they are local only)
        git fetch 2>/dev/null || true
        ahead_count=$(git rev-list --count @{upstream}..HEAD 2>/dev/null || echo "no-upstream")
        if [ "$ahead_count" = "no-upstream" ] || [ "$ahead_count" -eq 0 ]; then
            # No upstream (local only) or no unpushed commits, skip
            cd - > /dev/null
            continue
        fi

        repos_with_changes=$((repos_with_changes + 1))

        echo "=========================================="
        echo "Repository: $repo_dir"
        echo "=========================================="
        echo "Branch: $current_branch"
        echo ""

        # Show unpushed commits
        echo "Unpushed commits ($ahead_count):"
        git log @{upstream}..HEAD --oneline 2>/dev/null || git log --oneline -5
        echo ""
    else
        # Full mode: check for uncommitted changes
        if ! git status --porcelain | grep -q '^'; then
            # No changes, skip
            cd - > /dev/null
            continue
        fi

        repos_with_changes=$((repos_with_changes + 1))

        echo "=========================================="
        echo "Repository: $repo_dir"
        echo "=========================================="
        echo "Branch: $current_branch"
        echo ""

        # Show short status
        echo "Status:"
        git status --short
        echo ""

        # Identify and warn about new files
        new_files=$(git ls-files --others --exclude-standard)
        if [ -n "$new_files" ]; then
            echo "WARNING: New untracked files will be added:"
            echo "$new_files" | sed 's/^/     /'
            echo ""
        fi
    fi

    # Skip add/commit for push-only mode
    if [ "$PUSH_ONLY" = false ]; then
        # Show diff shortstat
        echo "Changes summary:"
        git diff --shortstat
        if git diff --cached --quiet; then
            : # No staged changes
        else
            echo "Staged changes:"
            git diff --cached --shortstat
        fi
        echo ""

        # Add all changes (including new files)
        echo "-> Adding all changes (git add -A)..."
        if [ -n "$new_files" ]; then
            echo "   Including new files:"
            echo "$new_files" | sed 's/^/     /'
        fi
        git add -A

        # Create commit
        echo "-> Creating commit..."
        if ! git commit -m "$COMMIT_MESSAGE"; then
            echo "Warning: Commit failed - nothing to commit or commit hook blocked it"
            cd - > /dev/null
            continue
        fi
        repos_committed=$((repos_committed + 1))
        echo "Commit created successfully"
        echo ""

        # Show the commit
        echo "Commit details:"
        git log -1 --oneline
        echo ""
    fi

    # Fetch latest from remote before push (skip if already fetched in push-only mode)
    if [ "$PUSH_ONLY" = false ]; then
        echo "-> Fetching latest from remote..."
        git fetch 2>/dev/null || true
    fi

    # Push to remote
    echo "-> Pushing to remote..."

    # Attempt push and capture output
    push_output=$(git push 2>&1)
    push_exit=$?

    if [ $push_exit -eq 0 ]; then
        # Push succeeded
        repos_pushed=$((repos_pushed + 1))
        echo "Pushed successfully"
    else
        # Push failed - check if it's due to no upstream
        if echo "$push_output" | grep -q "no upstream branch\|has no upstream branch"; then
            # No upstream set - set it automatically
            echo "No upstream branch configured for: $current_branch"
            echo "-> Automatically setting upstream: origin/$current_branch"
            echo ""

            if git push --set-upstream origin "$current_branch"; then
                repos_pushed=$((repos_pushed + 1))
                echo "Pushed successfully to origin/$current_branch"
                echo ""
                echo "New remote branch created: origin/$current_branch"
                echo ""
                echo "To merge changes to default branch:"
                echo "  1. Review changes in GitLab/GitHub web interface"
                echo "  2. Create merge/pull request MANUALLY"
                echo "  3. Request team review if needed"
                echo "  4. Merge after approval"
                echo ""
            else
                echo "Push with upstream failed - check permissions or network"
            fi
        else
            # Push failed for other reasons
            echo "Push failed:"
            echo "$push_output" | sed 's/^/   /'
        fi
    fi

    # Check MR readiness after successful push
    if [ $push_exit -eq 0 ]; then
        # Get path to check-mr-readiness.sh script
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        CHECK_MR_SCRIPT="$SCRIPT_DIR/../scripts/check-mr-readiness.sh"

        if [ -f "$CHECK_MR_SCRIPT" ]; then
            echo ""
            echo "-> Checking MR readiness..."

            # Check if docs/ToDos.md exists
            if [ -f "docs/ToDos.md" ]; then
                mr_result=$("$CHECK_MR_SCRIPT" 2>/dev/null) || true
                mr_ready=$(echo "$mr_result" | jq -r '.ready // false' 2>/dev/null)

                if [ "$mr_ready" = "true" ]; then
                    # Extract MR details
                    mr_target=$(echo "$mr_result" | jq -r '.target_branch')
                    mr_title=$(echo "$mr_result" | jq -r '.title')
                    mr_description=$(echo "$mr_result" | jq -r '.description')

                    # Save description to temp file for gh command
                    echo "$mr_description" > .mr-description.tmp

                    echo ""
                    echo "============================================="
                    echo "          MERGE REQUEST READY"
                    echo "============================================="
                    echo "Tasks in docs/ToDos.md indicate this branch is ready for MR"
                    echo ""
                    echo "Branch: $current_branch"
                    echo "Target: $mr_target"
                    echo ""
                    echo "Suggested title: $mr_title"
                    echo ""
                    echo "To create merge request:"
                    echo "  gh pr create --base $mr_target \\"
                    echo "    --title \"$mr_title\" \\"
                    echo "    --body-file .mr-description.tmp"
                    echo ""
                    echo "Or create manually via GitLab/GitHub web interface"
                    echo "============================================="
                    echo ""
                fi
            fi
        fi
    fi

    echo ""
    cd - > /dev/null
done < <(find . -type d -name ".git" -not -path "*/node_modules/*")

echo "=========================================="
echo "Summary"
echo "=========================================="
if [ "$PUSH_ONLY" = true ]; then
    echo "Repositories with unpushed commits: $repos_with_changes"
    echo "Repositories pushed: $repos_pushed"
    if [ "${#local_only_repos[@]}" -gt 0 ]; then
        echo "Local-only repositories (no upstream, skipped): ${#local_only_repos[@]}"
    fi
else
    echo "Repositories with changes: $repos_with_changes"
    echo "Repositories committed: $repos_committed"
    echo "Repositories pushed: $repos_pushed"
fi
echo ""

if [ $repos_pushed -gt 0 ]; then
    echo "Agentic operations completed successfully"
elif [ "$PUSH_ONLY" = true ]; then
    echo "No repositories were pushed"
else
    echo "No repositories were committed"
fi
