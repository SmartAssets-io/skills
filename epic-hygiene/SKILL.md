---
name: epic-hygiene
description: Scan task tracking files for epic completion status and perform hygiene operations (archiving, cleanup, validation)
license: SSL
---

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/epic:hygiene [OPTIONS]

Options:
  --json                Machine-readable JSON output
  --verbose             Detailed output for debugging
  --archive             Archive completed epics to CompletedTasks.md
  --validate            Validate YAML integrity only (no changes)

Scans docs/ToDos.md for completed epics and performs cleanup.
```

---

# Epic Hygiene

Scan task tracking files for epic completion status and perform hygiene operations (archiving completed epics, cleaning up stale work logs, validating YAML integrity).

**IMPORTANT**: Run this command when all tasks in an epic reach `status: done`. This keeps `docs/ToDos.md` clean by archiving completed work to `docs/CompletedTasks.md` and removes stale work logs from `docs/work-logs/`.

## Step 1: Run the Hygiene Script

First, run the deterministic bash script to analyze the current state:

```bash
# Run from any repo with docs/ToDos.md
scripts/epic-hygiene.sh --json

# Or with verbose output for debugging
scripts/epic-hygiene.sh --verbose
```

The script analyzes `docs/ToDos.md` relative to the current working directory.

## Step 2: Analyze Epic Status

Parse the script output (or manually scan) to identify:

1. **Epics ready to archive** - All tasks have `status: done`
2. **Stale work logs** - Work logs for completed epics/tasks
3. **Orphan tasks** - Tasks without an `epic:` field
4. **YAML validation errors** - Syntax issues in task definitions

### Manual Analysis (if no script)

Read `docs/ToDos.md` and check each epic:

```yaml
# For each epic definition like:
epic_id: EPIC-004
title: Privacy & Consent Enforcement
status: active
tasks: [TODO-019, TODO-019a, TODO-019b, ...]

# Check if ALL listed tasks have status: done
# If yes, epic is ready to archive
```

## Step 3: Report Findings

Present findings to user:

### Epic Status Report

| Epic | Title | Status | Tasks | Done | Ready? |
|-------|-------|--------|-------|------|--------|
| EPIC-004 | Privacy & Consent | active | 8 | 3 | No |
| ... | ... | ... | ... | ... | ... |

### Epics Ready to Archive
- List any epics where all tasks are done

### Stale Work Logs
- Work logs with `task_id` matching completed tasks
- Work logs with epic references in filename
- Work logs with `status: complete` in frontmatter

### Issues Found
- Orphan tasks (no epic assigned)
- YAML syntax errors
- Missing required fields

## Step 4: Perform Hygiene (with user approval)

**IMPORTANT**: Ask for user confirmation before making any changes.

For each epic ready to archive:

### 4a. Move Epic to CompletedTasks.md

1. **Copy the epic definition** from `docs/ToDos.md` to `docs/CompletedTasks.md`:
   - Change `status: active` to `status: completed`
   - Add `completed_date: YYYY-MM-DD` (today's date)

2. **Copy all tasks in that epic** from ToDos.md to CompletedTasks.md:
   - Optionally renumber task IDs from `TODO-XXX` to `DONE-XXX`
   - Preserve all other fields

3. **Remove the epic and its tasks** from `docs/ToDos.md`

4. **Update frontmatter** in `docs/ToDos.md`:
   - Change `active_epic:` to the next planned epic

### 4b. Clean Up Stale Work Logs

Work logs in `docs/work-logs/` become stale when their associated epic/task is completed. The script identifies stale logs by:

1. **task_id match** - Work log's `task_id` frontmatter matches a completed task
2. **epic reference** - Filename contains an epic ID that's being archived (e.g., `task-EPIC-003-*.md`)
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
│   └── EPIC-003/
│       └── task-003-20251215.md
└── active-work-log.md
```

### 4c. Fix Orphan Tasks

For tasks without an `epic:` field:
- Ask user which epic they belong to
- Add the `epic:` field to the task definition

### 4d. Import Defects as Tasks (optional)

If `docs/Defects.md` has items ready to become tasks:
- Convert defect to task format
- Assign to appropriate epic
- Add to `docs/ToDos.md`

## Files Modified

This command may modify:

| File | Operation |
|------|-----------|
| `docs/ToDos.md` | Remove archived epics, update frontmatter |
| `docs/CompletedTasks.md` | Add archived epics and tasks |
| `docs/work-logs/*.md` | Delete or move stale work logs |
| `docs/work-logs/archived/` | Created if archiving work logs |
| `docs/Backlog.md` | (read-only, for reference) |
| `docs/Defects.md` | Convert defects to tasks (optional) |

## Example Archive Operation

**Before** (in ToDos.md):
```yaml
---
active_epic: EPIC-003
---

## EPIC-003: Consent UI (Active)

epic_id: EPIC-003
status: active
tasks: [TODO-012, TODO-013]

---
id: TODO-012
status: done
epic: EPIC-003
---

---
id: TODO-013
status: done
epic: EPIC-003
---
```

**After** archiving EPIC-003:

ToDos.md frontmatter:
```yaml
active_epic: EPIC-004
```

CompletedTasks.md (added):
```yaml
## EPIC-003: Consent UI (Completed)

epic_id: EPIC-003
status: completed
completed_date: 2025-12-15
tasks: [DONE-012, DONE-013]

---
id: DONE-012
status: done
epic: EPIC-003
---
```

## Instructions

1. **Always run analysis first** before proposing changes
2. **Show the report** to the user and explain what will change
3. **Ask for confirmation** before modifying any files
4. **Use atomic edits** - complete one epic at a time
5. **Commit after each epic** - use `/quick-commit` after archiving each epic
6. **Validate after changes** - re-run the script to confirm no issues remain

## When to Run This Command

**Primary trigger**: When all tasks in an epic reach `status: done`

**Other good times**:
- After completing a significant batch of tasks
- Before creating a merge request
- When `docs/ToDos.md` feels cluttered with done items
- Periodically (weekly/bi-weekly) as part of project hygiene

**AI Agent Reminder**: When you mark the last task in an epic as `done`, remind the user to run `/epic-hygiene` to archive the completed epic.
