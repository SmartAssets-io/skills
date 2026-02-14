---
name: epoch-hygiene
description: Scan task tracking files for epoch completion status and perform hygiene operations (archiving, cleanup, validation)
license: SSL
---

# Epoch Hygiene

Scan task tracking files for epoch completion status and perform hygiene operations (archiving completed epochs, cleaning up stale work logs, validating YAML integrity).

**IMPORTANT**: Run this command when all tasks in an epoch reach `status: done`. This keeps `docs/ToDos.md` clean by archiving completed work to `docs/CompletedTasks.md` and removes stale work logs from `docs/work-logs/`.

## Step 1: Run the Hygiene Script

First, run the deterministic bash script to analyze the current state:

```bash
# Run from any repo with docs/ToDos.md
scripts/epoch-hygiene.sh --json

# Or with verbose output for debugging
scripts/epoch-hygiene.sh --verbose
```

The script analyzes `docs/ToDos.md` relative to the current working directory.

## Step 2: Analyze Epoch Status

Parse the script output (or manually scan) to identify:

1. **Epochs ready to archive** - All tasks have `status: done`
2. **Stale work logs** - Work logs for completed epochs/tasks
3. **Orphan tasks** - Tasks without an `epoch:` field
4. **YAML validation errors** - Syntax issues in task definitions

### Manual Analysis (if no script)

Read `docs/ToDos.md` and check each epoch:

```yaml
# For each epoch definition like:
epoch_id: EPOCH-004
title: Privacy & Consent Enforcement
status: active
tasks: [TODO-019, TODO-019a, TODO-019b, ...]

# Check if ALL listed tasks have status: done
# If yes, epoch is ready to archive
```

## Step 3: Report Findings

Present findings to user:

### Epoch Status Report

| Epoch | Title | Status | Tasks | Done | Ready? |
|-------|-------|--------|-------|------|--------|
| EPOCH-004 | Privacy & Consent | active | 8 | 3 | No |
| ... | ... | ... | ... | ... | ... |

### Epochs Ready to Archive
- List any epochs where all tasks are done

### Stale Work Logs
- Work logs with `task_id` matching completed tasks
- Work logs with epoch references in filename
- Work logs with `status: complete` in frontmatter

### Issues Found
- Orphan tasks (no epoch assigned)
- YAML syntax errors
- Missing required fields

## Step 4: Perform Hygiene (with user approval)

**IMPORTANT**: Ask for user confirmation before making any changes.

For each epoch ready to archive:

### 4a. Move Epoch to CompletedTasks.md

1. **Copy the epoch definition** from `docs/ToDos.md` to `docs/CompletedTasks.md`:
   - Change `status: active` to `status: completed`
   - Add `completed_date: YYYY-MM-DD` (today's date)

2. **Copy all tasks in that epoch** from ToDos.md to CompletedTasks.md:
   - Optionally renumber task IDs from `TODO-XXX` to `DONE-XXX`
   - Preserve all other fields

3. **Remove the epoch and its tasks** from `docs/ToDos.md`

4. **Update frontmatter** in `docs/ToDos.md`:
   - Change `active_epoch:` to the next planned epoch

### 4b. Clean Up Stale Work Logs

Work logs in `docs/work-logs/` become stale when their associated epoch/task is completed. The script identifies stale logs by:

1. **task_id match** - Work log's `task_id` frontmatter matches a completed task
2. **epoch reference** - Filename contains an epoch ID that's being archived (e.g., `task-EPOCH-003-*.md`)
3. **status complete** - Work log's `status` frontmatter is `complete`, `completed`, or `done`

**For each stale work log**, ask the user:

| Action | Description |
|--------|-------------|
| **Delete** | Remove the work log file entirely |
| **Archive** | Move to `docs/work-logs/archived/` subdirectory |
| **Keep** | Leave as-is (user wants to preserve for reference) |

**Archive directory structure**:
```
docs/work-logs/
├── archived/
│   └── EPOCH-003/
│       └── task-003-20251215.md
└── active-work-log.md
```

### 4c. Fix Orphan Tasks

For tasks without an `epoch:` field:
- Ask user which epoch they belong to
- Add the `epoch:` field to the task definition

### 4d. Import Defects as Tasks (optional)

If `docs/Defects.md` has items ready to become tasks:
- Convert defect to task format
- Assign to appropriate epoch
- Add to `docs/ToDos.md`

## Files Modified

This command may modify:

| File | Operation |
|------|-----------|
| `docs/ToDos.md` | Remove archived epochs, update frontmatter |
| `docs/CompletedTasks.md` | Add archived epochs and tasks |
| `docs/work-logs/*.md` | Delete or move stale work logs |
| `docs/work-logs/archived/` | Created if archiving work logs |
| `docs/Backlog.md` | (read-only, for reference) |
| `docs/Defects.md` | Convert defects to tasks (optional) |

## Example Archive Operation

**Before** (in ToDos.md):
```yaml
---
active_epoch: EPOCH-003
---

## EPOCH-003: Consent UI (Active)

epoch_id: EPOCH-003
status: active
tasks: [TODO-012, TODO-013]

---
id: TODO-012
status: done
epoch: EPOCH-003
---

---
id: TODO-013
status: done
epoch: EPOCH-003
---
```

**After** archiving EPOCH-003:

ToDos.md frontmatter:
```yaml
active_epoch: EPOCH-004
```

CompletedTasks.md (added):
```yaml
## EPOCH-003: Consent UI (Completed)

epoch_id: EPOCH-003
status: completed
completed_date: 2025-12-15
tasks: [DONE-012, DONE-013]

---
id: DONE-012
status: done
epoch: EPOCH-003
---
```

## Instructions

1. **Always run analysis first** before proposing changes
2. **Show the report** to the user and explain what will change
3. **Ask for confirmation** before modifying any files
4. **Use atomic edits** - complete one epoch at a time
5. **Commit after each epoch** - use `/quick-commit` after archiving each epoch
6. **Validate after changes** - re-run the script to confirm no issues remain

## When to Run This Command

**Primary trigger**: When all tasks in an epoch reach `status: done`

**Other good times**:
- After completing a significant batch of tasks
- Before creating a merge request
- When `docs/ToDos.md` feels cluttered with done items
- Periodically (weekly/bi-weekly) as part of project hygiene

**AI Agent Reminder**: When you mark the last task in an epoch as `done`, remind the user to run `/epoch-hygiene` to archive the completed epoch.
