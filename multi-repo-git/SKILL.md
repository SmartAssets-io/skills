---
name: multi-repo-git
description: Manage git operations across multiple repositories in a workspace. Use when committing changes across repos, pushing to multiple remotes, checking branch consistency, or working in meta-repository/monorepo-style projects with nested git directories.
---

# Multi-Repo Git Operations

Coordinate git operations across multiple repositories in a unified workspace.

## Discovering Repositories

Find all repos with changes:

```bash
# Find nested git repos
find . -mindepth 2 -type d -name ".git" -not -path "*/node_modules/*" 2>/dev/null

# Check each for uncommitted changes
for repo in $(find . -mindepth 2 -type d -name ".git" | sed 's|/.git||'); do
  if [ -n "$(git -C "$repo" status --porcelain)" ]; then
    echo "$repo has changes"
  fi
done
```

## Multi-Repo Commit Workflow

### 1. Gather Status
```bash
# For each repo with changes:
git -C "$repo" status --short
git -C "$repo" diff --stat
```

### 2. Check Branch Consistency
```bash
# Get branch for each repo
git -C "$repo" branch --show-current
```

**Warning** if repos are on different branches - this can cause merge issues.

### 3. Generate Commit Messages
Per-repo messages based on actual changes:
- Small changes (1-3 files): `feat(scope): description`
- Large changes: Multi-line with summary and bullets

### 4. Execute Commits
```bash
# For each repo
git -C "$repo" commit -a -m "message"
```

### 5. Push All
```bash
# Check for unpushed commits
for repo in repos; do
  unpushed=$(git -C "$repo" log @{u}.. --oneline 2>/dev/null | wc -l)
  if [ "$unpushed" -gt 0 ]; then
    echo "$repo: $unpushed commits to push"
  fi
done

# Push with upstream tracking
git -C "$repo" push -u origin "$(git -C "$repo" branch --show-current)"
```

## Branch Consistency Check

When repos are on different branches:

```
Majority branch: master (5 repositories)

Repositories on different branches:
  - subproject: dev

Options:
1. Commit all - proceed despite inconsistency
2. Skip inconsistent - only commit to majority branch repos
```

## Approval Thresholds

Require explicit approval when:
- More than 5 files changed
- More than 2 repositories affected

## Finding Unpushed Commits

```bash
# Count unpushed commits per repo
for repo in $(find . -mindepth 2 -type d -name ".git" | sed 's|/.git||'); do
  count=$(git -C "$repo" log @{u}.. --oneline 2>/dev/null | wc -l)
  if [ "$count" -gt 0 ]; then
    echo "$repo: $count commits"
    git -C "$repo" log @{u}.. --oneline
  fi
done
```

## Setting Upstream on First Push

```bash
# Auto-set upstream for new branches
git push -u origin "$(git branch --show-current)"
```

## Workspace Structure

```
workspace/
├── repo-a/
│   └── .git/
├── repo-b/
│   └── .git/
├── subgroup/
│   ├── repo-c/
│   │   └── .git/
│   └── repo-d/
│       └── .git/
└── shared-docs/  (non-git)
```

## Environment Variable

Set `MULTI_REPO=true` to enable multi-repo mode in tools that support it.

## Safety Rules

- Never auto-add untracked files
- Always show diff summary before commit
- Warn about branch inconsistencies
- Require approval for large changesets
