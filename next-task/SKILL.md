---
name: next-task
description: Review project task tracking and stigmergic signals to identify and explain the next task to work on
license: SSL
---

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/nextTask [EPOCH-ID]

Arguments:
  [EPOCH-ID]            Scope to specific epoch (e.g., EPOCH-008)

Default: Analyzes docs/ToDos.md to find the highest-priority unclaimed task.
Priority: in_progress > pending, then p0 > p1 > p2 > p3, then epoch number.
```

---

# Next Task Discovery

Review the project's task tracking and stigmergic signals to identify and explain the next task to work on.

## Path Resolution

Scripts referenced below live in the `top-level-gitlab-profile` repository. When running from another repository, resolve the base path first. **Combine this resolution with each script invocation in a single shell command:**

```bash
PROFILE_DIR="$(git rev-parse --show-toplevel)"
if [ ! -d "$PROFILE_DIR/AItools/scripts" ]; then
  for _p in "$PROFILE_DIR/.." "$PROFILE_DIR/../.."; do
    _candidate="$_p/top-level-gitlab-profile"
    if [ -d "$_candidate/AItools/scripts" ]; then
      PROFILE_DIR="$(cd "$_candidate" && pwd)"
      break
    fi
  done
fi
```

Use `"$PROFILE_DIR/AItools/scripts/..."` for all script paths below.

## Epoch-Aware Task Selection

This command uses the epoch parser library to understand the hierarchical task structure:

1. **Run the epoch parser** to get the next task:
   ```bash
   PROFILE_DIR="$(git rev-parse --show-toplevel)"; if [ ! -d "$PROFILE_DIR/AItools/scripts" ]; then for _p in "$PROFILE_DIR/.." "$PROFILE_DIR/../.."; do _c="$_p/top-level-gitlab-profile"; [ -d "$_c/AItools/scripts" ] && PROFILE_DIR="$(cd "$_c" && pwd)" && break; done; fi
   "$PROFILE_DIR/AItools/scripts/lib/epoch-parser.sh" next-task docs/ToDos.md
   ```

2. **Interpret the output:**
   - `epoch` - Current epoch context (ID, title, priority, progress)
   - `task` - Next available task with description
   - `epoch_queue` - Other pending epochs in priority order

3. **For epoch metrics:**
   ```bash
   PROFILE_DIR="$(git rev-parse --show-toplevel)"; if [ ! -d "$PROFILE_DIR/AItools/scripts" ]; then for _p in "$PROFILE_DIR/.." "$PROFILE_DIR/../.."; do _c="$_p/top-level-gitlab-profile"; [ -d "$_c/AItools/scripts" ] && PROFILE_DIR="$(cd "$_c" && pwd)" && break; done; fi
   "$PROFILE_DIR/AItools/scripts/lib/epoch-parser.sh" metrics EPOCH-XXX docs/ToDos.md
   ```

## Stigmergic Context Gathering

Before selecting a task, also read these coordination files:

1. **Work logs** (`docs/work-logs/`) - Check for:
   - Existing progress on related tasks
   - Handoff notes from previous sessions
   - Blockers discovered by other agents

2. **Discoveries** (`docs/discoveries/`) - Check for:
   - Relevant findings from other agents
   - Patterns or code discovered that affects available tasks
   - Unresolved questions or decisions

3. **Design docs** (`docs/designs/`) - Check for:
   - Decisions that affect task implementation
   - Open questions needing answers
   - Architecture constraints

## Task Selection Rules

The epoch parser applies these rules automatically:

### Epoch-Level
- Priority ordering: p0 > p1 > p2 > p3
- Prefer epochs with `in_progress` status (continue existing work)
- Respect `blocked_by` dependencies between epochs
- Lower epoch numbers preferred when priority is equal

### Task-Level (within epoch)
- Resume own `in_progress` tasks first
- Select `pending` tasks with no blockers
- Respect `blocked_by` dependencies between tasks
- Lower task numbers preferred as tiebreaker

## Output Format

Provide a structured summary with epoch context:

### Current Epoch
```
Epoch: [EPOCH-ID] [Title]
Progress: [X/Y] tasks complete ([Z]%)
Priority: [p0-p3]
Status: [pending|in_progress|complete|blocked]
```

### Stigmergic Context
- Work logs found: [list any relevant work-logs]
- Discoveries relevant: [list any relevant discoveries]
- Blocked tasks: [list tasks blocked and why]
- In-progress by others: [list tasks with their `claimed_by` identifier, e.g. `human-jeff@example.com`, `design-sprint/researcher`]

### Just Completed
- What was recently finished or committed (if relevant)

### Next Task: **[TODO-XXX-NNN] Title**
- **Goal:** One-sentence description from task description
- **Epoch:** [EPOCH-ID] (task N of M)
- **Status:** Current status and claim state
- **Dependencies:** Any blockers or prerequisites
- **Acceptance Criteria:** Bullet list from task definition
- **Approach:** Numbered implementation steps
- **Files to modify:** List key files
- **Related Discoveries:** Findings that affect this task

### Epoch Queue
List other pending epochs in priority order:
1. EPOCH-XXX (pN) - [status] - X/Y tasks
2. EPOCH-YYY (pN) - [status] - X/Y tasks

### Notes
- Any observations about task status discrepancies
- Suggested task order if multiple are ready
- Any handoff notes from previous agents

## Instructions

- Do NOT start implementing - just explain the task and approach
- Ask for confirmation before proceeding with implementation
- If a task has a `claimed_by` value (human or agent), skip it unless claim is stale (>24h). See [Implementer Identification](../docs/common/stigmergic-collaboration.md#implementer-identification) for identifier formats.
- If no epochs found, fall back to flat task parsing from `docs/ToDos.md`
- If multiple tasks have equal priority within an epoch, prefer one with relevant discoveries

## Fallback: Flat Task Format

If `docs/ToDos.md` contains flat tasks (no epochs), the parser returns individual tasks sorted by priority. In this case, omit the epoch context sections.
