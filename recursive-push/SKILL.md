---
name: recursive-push
description: Push unpushed commits across all repositories in the workspace
license: SSL
---

You are helping the user push git commits across multiple repositories.

**Claude Config Modes**: This command works in both claude configurations:

| Config | Command | Behavior |
|--------|---------|----------|
| `~/.claude` | `claude` / `claude-safe` | Restrictive hooks block direct `git push`. Use `agentic-git-commit-push.sh --push-only` script |
| `~/.claude-agentic` | `claude-agentic` | No restrictive hooks. Can use direct git push OR the script |

**Auto-detection for multi-repo**: This command automatically detects the appropriate scope:
1. If `MULTI_REPO=true` is set, uses multi-repo mode
2. If nested git repositories are detected in subdirectories (even if gitignored), auto-enables multi-repo mode
3. Otherwise, uses single-repo mode for the current directory only

---

## Using the Push Script

In safe mode (`~/.claude`), always use the agentic script to bypass restrictive hooks:

```bash
# Push using the agentic script
scripts/agentic-git-commit-push.sh --push-only
```

The script will:
- Display a summary with commit counts
- Handle all repositories with unpushed commits
- Set upstream branches automatically if needed
- Provide a summary of pushed repositories

---

## Mode Detection (Multi-repo scope)

Determine the mode using intelligent auto-detection:

1. **Check MULTI_REPO environment variable** - if explicitly set to `true`, use multi-repo mode
2. **Auto-detect nested repositories** - if the current directory contains subdirectories with their own `.git/` directories (even if gitignored), automatically use multi-repo mode
3. **Fall back to single-repo mode** - only if there's a single `.git/` in the current directory with no nested repos

```bash
# Check explicit environment variable first
if [ "${MULTI_REPO:-false}" = "true" ]; then
    MODE="multi-repo"
else
    # Auto-detect: Check if there are nested git repositories
    # (subdirectories with .git that are separate from the current repo)
    nested_repos=$(find . -mindepth 2 -type d -name ".git" -not -path "*/node_modules/*" 2>/dev/null | wc -l | tr -d ' ')

    if [ "$nested_repos" -gt 0 ]; then
        # Found nested repos - auto-enable multi-repo mode for this command
        MODE="multi-repo"
        echo "Auto-detected $nested_repos nested git repositories - using multi-repo mode"
    else
        MODE="single-repo"
    fi
fi
```

**Note**: This auto-detection handles the common case where a parent directory has its own `.git/` but contains gitignored subdirectories that are independent git repositories (e.g., a workspace with SA/, FF/, BF/ subdirectories).

---

## Single-Repo Mode

This mode is used when:
- `MULTI_REPO` is not set AND
- No nested git repositories are detected in subdirectories

Follow these steps:

1. **Fetch latest from remote**: Run `git fetch` to ensure we have the latest remote state

2. **Check for unpushed commits**: Run `git status` to check if branch is ahead of remote

3. **Verify commits exist**: If there are no unpushed commits, inform the user and STOP.

4. **Show what will be pushed**: Run `git log origin/$(git branch --show-current)..HEAD --oneline` to show commits

5. **Push**: Run `git push` (with automatic upstream if needed)

6. **Show result**: Confirm push success and show the remote URL

**Examples**:

```
User: /recursive-push
Assistant: [runs git fetch]
          [checks git status - sees 2 commits ahead]
          [shows commits to push]
          [runs git push]
          [shows success]
```

---

## Multi-Repo Mode

**Intelligent recursive push with safety checks**

### Step 1: Discover repositories with unpushed commits

Find all git repositories with commits ahead of remote:

```bash
repos_to_push=()
declare -A repo_commit_counts

# Find all git repositories
for git_dir in $(find . -type d -name ".git" -not -path "*/node_modules/*" -not -path "*/.git/*"); do
    repo_dir=$(dirname "$git_dir")
    cd "$repo_dir"

    # Fetch latest from remote to ensure accurate comparison
    git fetch 2>/dev/null

    # Check if branch has upstream and is ahead
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

    # Count unpushed commits
    ahead_count=$(git rev-list --count @{upstream}..HEAD 2>/dev/null || echo "no-upstream")

    if [ "$ahead_count" = "no-upstream" ]; then
        # No upstream - check if there are any commits at all
        commit_count=$(git rev-list --count HEAD 2>/dev/null || echo "0")
        if [ "$commit_count" -gt 0 ]; then
            repos_to_push+=("$repo_dir")
            repo_commit_counts["$repo_dir"]="$commit_count (no upstream)"
        fi
    elif [ "$ahead_count" -gt 0 ]; then
        repos_to_push+=("$repo_dir")
        repo_commit_counts["$repo_dir"]="$ahead_count"
    fi

    cd - > /dev/null
done
```

If no repos have unpushed commits, inform user and STOP.

### Step 2: Workspace Consistency Check

Before presenting the summary, use the consistency checker script to detect branch and worktree mismatches:

```bash
# Run the consistency checker in JSON mode
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$SCRIPT_DIR/../scripts/check-repo-consistency.sh"

consistency_json=""
if [[ -x "$CHECKER" ]]; then
    consistency_json=$("$CHECKER" --json --changes-only 2>/dev/null) || true
fi

# Parse JSON to extract consistency status and outliers
consistent=$(echo "$consistency_json" | jq -r '.consistent // true')
majority_branch=$(echo "$consistency_json" | jq -r '.branch.majority // ""')
majority_count=$(echo "$consistency_json" | jq -r '.branch.majority_count // 0')
branch_consistent=$(echo "$consistency_json" | jq -r '.branch.consistent // true')
worktree_consistent=$(echo "$consistency_json" | jq -r '.worktree.consistent // true')

# Extract outlier paths and branches
inconsistent_repos=()
if [[ "$branch_consistent" == "false" ]]; then
    while IFS= read -r line; do
        path=$(echo "$line" | jq -r '.path')
        branch=$(echo "$line" | jq -r '.branch')
        inconsistent_repos+=("$path:$branch")
    done < <(echo "$consistency_json" | jq -c '.branch.outliers[]')
fi
```

If the workspace is inconsistent (branches or worktrees), use **AskUserQuestion** BEFORE proceeding:

```
Question: "Workspace consistency check found mismatches. Continue?"

Header: "Consistency"

Options:
1. Yes, push all - Proceed with pushes to all repositories regardless of mismatch
2. Skip inconsistent - Only push repositories on the majority branch
```

**Warning message to show (from checker output):**
```
Workspace Consistency Warning:

Majority branch: master (5 repositories)

Repositories on different branches:
  - SA_build_agentics: dev
  - BountyForge/discord-bot: feature-x

Pushing to repositories on different branches may cause inconsistency
when merging or reviewing changes across the workspace.
```

If worktree inconsistency is also detected, include:
```
Worktree Warning: Mixed worktree/regular checkouts detected.
```

**Apply user's choice:**
- **"Yes, push all"**: Include all repositories in the push
- **"Skip inconsistent"**: Remove inconsistent repos from `repos_to_push` array
- **"Other"**: User may specify custom handling

### Step 4: Present summary

Show preview of what will be pushed:

```
Found unpushed commits in N repositories:

1. relative/path/to/repo1 (X commits)
   Branch: feature-branch -> origin/feature-branch
   Commits:
     abc1234 feat: add new feature
     def5678 fix: resolve bug

2. relative/path/to/repo2 (Y commits, no upstream)
   Branch: new-branch (will create origin/new-branch)
   Commits:
     ghi9012 docs: update readme

Total: N repositories, M commits

Proceed with push? [Y/n]
```

Wait for user response. If user says no or anything other than yes/y/Y, cancel and exit.

### Step 5: Execute pushes with safety checks

For each repository with unpushed commits:

```bash
success_count=0
failed_count=0

for repo in "${repos_to_push[@]}"; do
    cd "$repo"

    echo "=========================================="
    echo "Repository: $repo"
    echo "=========================================="

    # Get current branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    echo "Branch: $current_branch"
    echo ""

    # Show commits to push
    echo "Commits to push:"
    if git rev-parse @{upstream} >/dev/null 2>&1; then
        git log @{upstream}..HEAD --oneline
    else
        echo "(new branch - all commits)"
        git log --oneline -5
        echo "..."
    fi
    echo ""

    # Push to remote
    echo "→ Pushing to remote..."

    if git push 2>&1 | tee /tmp/push_output.txt; then
        echo "✓ Pushed successfully"
        success_count=$((success_count + 1))
    else
        # Check if it's due to no upstream
        if grep -q "no upstream branch\|has no upstream branch" /tmp/push_output.txt; then
            echo "⚠️  No upstream branch configured for: $current_branch"
            echo "→ Automatically setting upstream: origin/$current_branch"
            echo ""

            if git push --set-upstream origin "$current_branch" 2>&1; then
                echo "✓ Pushed successfully to origin/$current_branch"
                echo "📝 New remote branch created: origin/$current_branch"
                success_count=$((success_count + 1))
            else
                echo "❌ Push with upstream failed - check permissions or network"
                failed_count=$((failed_count + 1))
            fi
        else
            echo "❌ Push failed:"
            cat /tmp/push_output.txt | sed 's/^/   /'
            failed_count=$((failed_count + 1))
        fi
    fi

    # MR readiness check
    if [ -f docs/ToDos.md ]; then
        echo ""
        echo "→ Checking MR readiness in docs/ToDos.md..."

        # Look for mr_status.ready: true in frontmatter
        if grep -q "ready: true" docs/ToDos.md; then
            echo ""
            echo "╔════════════════════════════════════════════════════════════════╗"
            echo "║                    MERGE REQUEST READY                          ║"
            echo "╟────────────────────────────────────────────────────────────────╢"
            echo "║ Tasks in docs/ToDos.md indicate this branch is ready for MR    ║"
            echo "║                                                                 ║"
            printf "║ Branch: %-55s║\n" "$current_branch"
            echo "║                                                                 ║"
            echo "║ To create merge request:                                        ║"
            echo "║   gh pr create --base main \\                                    ║"
            echo "║     --title \"Your title\" \\                                      ║"
            echo "║     --body \"Description\"                                        ║"
            echo "║                                                                 ║"
            echo "║ Or create manually via GitLab/GitHub web interface              ║"
            echo "╚════════════════════════════════════════════════════════════════╝"
            echo ""
        fi
    fi

    echo ""
    cd - > /dev/null
done

rm -f /tmp/push_output.txt
```

### Step 6: Show summary

```
==========================================
Summary
==========================================
Repositories pushed: $success_count
Failed/Skipped: $failed_count

if [ $success_count -gt 0 ]; then
    echo ""
    echo "✅ Successfully pushed repositories:"
    echo ""

    for repo in "${repos_to_push[@]}"; do
        echo "  ✓ $repo"
    done
fi

if [ $failed_count -gt 0 ]; then
    echo ""
    echo "⚠️  Some repositories failed to push. Check errors above."
fi
```

---

## Error Handling

- **No unpushed commits**: "No unpushed commits found. Nothing to push."
- **Mode detection**: Auto-detects nested repos; only uses single-repo mode if no nested `.git/` directories found
- **Branch inconsistency**: Warn user and ask for confirmation before pushing to repos on different branches
- **No upstream branch**: Automatically sets upstream with `git push --set-upstream origin <branch>`
- **Push fails**: Continue with other repos, count as failed, show error
- **User cancels**: Exit gracefully with no pushes

---

## Examples

**Single-repo mode** (no nested repos detected):
```
User: /recursive-push
Assistant: [checks for nested git repos - none found]
          [uses single-repo mode]
          [runs git fetch]
          [checks if current repo has unpushed commits]
          [shows commits]
          [runs git push]
          [shows success]
```

**Multi-repo mode** (MULTI_REPO=true):
```
User: /recursive-push
Assistant: [checks MULTI_REPO=true]
          [finds 3 repos with unpushed commits]
          [shows preview:
           Found unpushed commits in 3 repositories:
           1. top-level-gitlab-profile (2 commits)
           2. SA_build_agentics (1 commit)
           3. BountyForge/ssl_semantic_git (1 commit)

           Proceed? [Y/n]]
          [waits for user]
User: y
Assistant: [pushes all 3 repos]
          [shows MR readiness if applicable]
          [shows summary]
```

**Auto-detected multi-repo mode** (nested repos in gitignored subdirectories):
```
User: /recursive-push
(from /Users/jeff/src/CurrentProjects which has .git/ but also SA/, FF/, BF/ subdirs with their own .git/)
Assistant: [checks MULTI_REPO - not set]
          [finds 45 nested git repositories in subdirectories]
          [auto-enables multi-repo mode]
          "Auto-detected 45 nested git repositories - using multi-repo mode"
          [finds repos with unpushed commits]
          [shows preview and asks for confirmation]
          [pushes approved repos]
```

**Multi-repo with branch inconsistency** (repos on different branches):
```
User: /recursive-push
Assistant: [discovers 4 repos with unpushed commits]
          [detects branch inconsistency:
           - 3 repos on "master"
           - 1 repo (SA_build_agentics) on "dev"]
          [shows warning:
           "Branch Consistency Warning:

            Majority branch: master (3 repositories)

            Repositories on different branches:
              - SA_build_agentics: dev

            Pushing to repositories on different branches may cause
            inconsistency when merging or reviewing changes across the workspace."]
          [uses AskUserQuestion:
           "Some repositories are on different branches. Continue with inconsistent branches?"
           Options:
           1. Yes, push all
           2. Skip inconsistent]
User: [selects "Skip inconsistent"]
Assistant: [excludes SA_build_agentics from push list]
          [shows preview of remaining 3 repos]
          [waits for push confirmation]
User: y
Assistant: [pushes 3 repos on master branch]
          [shows summary]
```

---

## Safety Features

This command integrates with existing SA multi-repo infrastructure:

1. **Config-aware execution**:
   - **Safe mode** (`~/.claude`): Uses `agentic-git-commit-push.sh --push-only` script to bypass restrictive hooks
   - **Agentic mode** (`~/.claude-agentic`): Can use direct git commands or the script
2. **Intelligent scope detection**: Auto-detects nested git repositories in subdirectories (even if gitignored) and switches to multi-repo mode automatically
3. **Workspace consistency check**: Uses `check-repo-consistency.sh` to detect branch and worktree mismatches, warns user and asks for confirmation before operating on inconsistent repos
4. **Fetch before push**: Runs `git fetch` before checking for unpushed commits to ensure accurate remote state
5. **Preview before push**: Always shows what will be pushed and asks for confirmation (in multi-repo mode)
6. **Automatic upstream**: Sets upstream on first push to new branches
7. **MR readiness**: Checks docs/ToDos.md after push and prompts for MR creation
8. **Graceful failures**: Continues with other repos if one fails, reports all errors

**Note**: Use `/quick-commit` first to create commits, then `/recursive-push` to push them.
