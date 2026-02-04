---
name: epoch-task-management
description: Manage development tasks organized into epochs (groups of related work) with YAML-structured ToDos.md files. Use when working with epoch-based task tracking, finding next tasks, claiming work, or checking epoch progress. Supports stigmergic multi-agent coordination where agents communicate through shared markdown files.
---

# Epoch Task Management

Organize and track development tasks using epochs - logical groupings of related work with priority-based sequencing.

## Core Concepts

**Epoch**: A group of related tasks (e.g., "EPOCH-011: Authentication System")
**Task**: Individual work items within an epoch (e.g., "TODO-011-001: Design auth flow")
**Stigmergic Coordination**: Agents coordinate through shared files, not direct messaging

## Task File Structure

Tasks live in `docs/ToDos.md` as fenced YAML code blocks:

```yaml
epoch_id: EPOCH-011
title: Authentication System
status: in_progress
priority: p1
tasks:
  - id: TODO-011-001
    title: "Design auth flow"
    status: complete
    completed_date: 2025-01-15
  - id: TODO-011-002
    title: "Implement login endpoint"
    status: pending
    claimed_by: ""
    blocked_by: [TODO-011-001]
```

## Task Selection Algorithm

### Epoch Selection
1. Filter to eligible epochs (`pending` or `in_progress`, not blocked)
2. Prefer `in_progress` epochs (continue existing work)
3. Sort by priority: `p0` > `p1` > `p2` > `p3`
4. Lower epoch number as tiebreaker

### Task Selection (within epoch)
1. Resume own `in_progress` tasks first
2. Select `pending` tasks with no blockers
3. Respect `blocked_by` dependencies
4. Lower task number as tiebreaker

## Claiming a Task

Before starting work, update the task YAML:

```yaml
- id: TODO-011-002
  title: "Implement login endpoint"
  status: in_progress
  claimed_by: claude-session-abc123
  claimed_at: 2025-01-15T10:00:00Z
```

## Completing a Task

```yaml
- id: TODO-011-002
  title: "Implement login endpoint"
  status: complete
  completed_date: 2025-01-15
```

## Status Values

| Status | Meaning |
|--------|---------|
| `pending` | Available for work |
| `in_progress` | Being worked on |
| `blocked` | Waiting on dependency |
| `complete` | Done |

## Priority Levels

- `p0` - Critical/urgent
- `p1` - High priority
- `p2` - Normal (default)
- `p3` - Low priority

## Epoch Status Derivation

Epoch status is derived from task states:
- All tasks `complete` → epoch `complete`
- Any task `in_progress` → epoch `in_progress`
- Any task `blocked`, none `in_progress` → epoch `blocked`
- All tasks `pending` → epoch `pending`

## Work Logs

Create session logs at `docs/work-logs/task-{id}-{timestamp}.md`:

```markdown
# Work Log: TODO-011-002

## Session Info
- **Started**: 2025-01-15T10:00:00Z
- **Agent**: claude-session-abc123
- **Epoch**: EPOCH-011 (task 2 of 5)

## Progress
- [x] Read existing code
- [x] Implement endpoint
- [ ] Write tests

## Findings
- UserService already has password hashing

## Blockers
- Need Redis decision for sessions

## Handoff Notes
- Tests scaffolded in auth.test.ts
```

## Quick Reference

```bash
# Check epoch status
cat docs/ToDos.md | grep -A 20 "epoch_id: EPOCH-011"

# Find unclaimed tasks
grep -B 5 'status: pending' docs/ToDos.md | grep -E '(id:|title:)'
```
