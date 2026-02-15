---
name: implement-task
description: Begin implementation of the next task supporting both IPC and stigmergic coordination with epoch-aware progress tracking
license: SSL
---

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/implement [TASK-ID]

Arguments:
  [TASK-ID]             Specific task to implement (e.g., TASK-001)

Default: Implements the task identified by /nextTask.
Supports IPC and stigmergic coordination with epoch-aware progress tracking.
Prerequisite: Run /nextTask first (or have task context ready).
```

---

# Implement Next Task

Begin implementation of the task identified by `/nextTask`. This command assumes you have already reviewed the task and explained the approach to the user.

## Prerequisites

- `/nextTask` has been run (or equivalent task analysis completed)
- User has confirmed they want to proceed with implementation
- Task goal, acceptance criteria, and approach are understood

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

## Epoch Context

When working on epoch-based tasks:

1. **Get current epoch context**:
   ```bash
   PROFILE_DIR="$(git rev-parse --show-toplevel)"; if [ ! -d "$PROFILE_DIR/AItools/scripts" ]; then for _p in "$PROFILE_DIR/.." "$PROFILE_DIR/../.."; do _c="$_p/top-level-gitlab-profile"; [ -d "$_c/AItools/scripts" ] && PROFILE_DIR="$(cd "$_c" && pwd)" && break; done; fi
   "$PROFILE_DIR/AItools/scripts/lib/epoch-parser.sh" next-task docs/ToDos.md
   ```

2. **Track epoch progress**:
   - Note the current epoch ID and task position (task N of M)
   - Update task status within the epoch YAML block
   - Check for epoch completion after finishing tasks

## Coordination Setup

### Coordination Mode

- **Agent team member** (IPC tools available, system prompt identifies team role): Use `SendMessage` and `TaskUpdate` for real-time coordination with the orchestrator, AND update `.md` files for persistence/audit.
- **Solo agent** (no IPC tools): Use stigmergic `.md` files only.
- Both modes ALWAYS update `docs/ToDos.md` and work logs -- `.md` files are the system of record.

### 1. Claim the Task (Epoch Format)

Before starting work, update the task within its epoch in `docs/ToDos.md`:

```yaml
tasks:
  - id: TODO-XXX-NNN
    title: "Task title"
    status: in_progress          # Changed from 'pending'
    claimed_by: claude-session   # Solo agent: {tool}-session[-{id}]
    claimed_at: 2025-01-15T10:00:00Z
    # Other valid claimed_by formats:
    #   human-jeff@example.com      # Human (from: git config --get user.email)
    #   human-Jeff Smith            # Human (fallback: git config --get user.name)
    #   design-sprint/researcher    # Agent team member
    #   design-sprint/lead          # Agent team lead
```

Note: For epoch-based tasks, the task is nested within the epoch's `tasks:` array. See [Implementer Identification](../docs/common/stigmergic-collaboration.md#implementer-identification) for the full format reference.

**Agent team members:** After updating `docs/ToDos.md`, notify the orchestrator via `SendMessage` with the task ID and a one-line summary of what you're starting.

### 2. Create Work Log

Create a work log file at `docs/work-logs/task-{id}-{timestamp}.md`:

```markdown
# Work Log: TODO-XXX-NNN Implementation

## Session Info
- **Started**: [ISO timestamp]
- **Implementer**: [your claimed_by value, e.g. claude-session-a1b2c3 or human-jeff@example.com]
- **Task**: [Task title]
- **Epoch**: [EPOCH-XXX] (task N of M)

## Progress
- [ ] [First step]
- [ ] [Next step]

## Findings
<!-- Document discoveries for other agents -->

## Blockers
<!-- Unresolved issues -->

## Handoff Notes
<!-- Context for next agent/session -->
```

**Agent team members:** Also mark your IPC task as `in_progress` via `TaskUpdate` if the task was assigned by the orchestrator.

## Process

### 1. Create Todo List

Use TodoWrite to create a structured task list based on the approach outlined:
- Break down implementation into discrete, trackable steps
- Include verification steps (tests, typecheck, lint)
- Mark the first task as `in_progress`

### 2. Implementation Loop

For each todo item:

1. **Mark as in_progress** before starting work
2. **Read relevant files** before making changes - never modify code you haven't read
3. **Make focused changes** - one logical unit per todo item
4. **Verify the change** - run tests, typecheck, or lint as appropriate
5. **Mark as completed** immediately after finishing (don't batch completions)
6. **Update work log** with progress after each significant step. **Agent team members:** Send brief progress via `SendMessage` after major milestones (not every micro-step).

### 3. Record Discoveries

When you find something other agents should know:
- Add to `## Findings` section in your work log
- For significant discoveries, create `docs/discoveries/{date}-{topic}.md`
- Update related task notes if discovery affects other work

### 4. Follow Project Conventions

- Check `CLAUDE.md` or `AGENTS.md` for project-specific guidelines
- Use existing patterns from the codebase
- Prefer editing existing files over creating new ones
- Use `data-testid` attributes for test selectors
- Keep changes minimal - don't over-engineer or add unrequested features

### 5. Verification Steps

After all implementation todos are complete:
- Run `pnpm typecheck` or equivalent
- Run `pnpm test` or equivalent
- Run `pnpm lint` or equivalent
- Verify the acceptance criteria are met

### 6. Completion

When implementation is complete:

1. **Update work log** with final status:
   ```yaml
   ---
   handoff_status: complete
   completed_at: [ISO timestamp]
   ---
   ```

2. **Update task in `docs/ToDos.md`** (within epoch YAML block):
   ```yaml
   - id: TODO-XXX-NNN
     status: complete
     completed_date: 2025-01-15
   ```

3. **Check epoch completion**:
   ```bash
   PROFILE_DIR="$(git rev-parse --show-toplevel)"; if [ ! -d "$PROFILE_DIR/AItools/scripts" ]; then for _p in "$PROFILE_DIR/.." "$PROFILE_DIR/../.."; do _c="$_p/top-level-gitlab-profile"; [ -d "$_c/AItools/scripts" ] && PROFILE_DIR="$(cd "$_c" && pwd)" && break; done; fi
   "$PROFILE_DIR/AItools/scripts/lib/epoch-parser.sh" metrics EPOCH-XXX docs/ToDos.md
   ```
   If all tasks in the epoch are complete, note the epoch completion.

4. **IPC completion (agent team members only)**:
   - Mark the IPC task as `completed` via `TaskUpdate`
   - Send a completion summary to the orchestrator via `SendMessage` including: task ID, what was implemented, and any follow-up items

5. **Summarize** what was implemented
6. **List discoveries** recorded for other agents
7. **Note follow-up items** discovered
8. **Do NOT** proactively commit - wait for user to invoke `/quick-commit`

## Epoch Completion

When all tasks in an epoch are complete:

1. **Verify completion**:
   ```bash
   PROFILE_DIR="$(git rev-parse --show-toplevel)"; if [ ! -d "$PROFILE_DIR/AItools/scripts" ]; then for _p in "$PROFILE_DIR/.." "$PROFILE_DIR/../.."; do _c="$_p/top-level-gitlab-profile"; [ -d "$_c/AItools/scripts" ] && PROFILE_DIR="$(cd "$_c" && pwd)" && break; done; fi
   "$PROFILE_DIR/AItools/scripts/lib/epoch-parser.sh" metrics EPOCH-XXX docs/ToDos.md
   ```
   Check that `derived_status` is `complete` and `percent_complete` is 100.

2. **Display completion message**:
   ```
   Epoch EPOCH-XXX Complete!
   Title: [Epoch title]
   Tasks: X/X (100%)

   Next Epoch: EPOCH-YYY - [Next epoch title]
   ```

3. **Suggest next steps**:
   - Run `/nextTask` to see the next epoch's first task
   - Run `/epoch-hygiene` to archive the completed epoch
   - Consider running `/quick-commit` if work is ready

## Error Handling

- If a step fails, keep it as `in_progress` and create a new todo for the blocker
- **Update work log** with blocker details for other agents
- If blocked by missing information, use AskUserQuestion
- If the approach needs revision, explain and get user confirmation before changing course
- If blocked by another task, update `blocked_by` field in the task YAML
- **Agent team members:** Notify the orchestrator via `SendMessage` when blocked, so the team can reassign or unblock

## Output Style

- Be concise - focus on doing the work, not explaining it
- Show progress through todo updates
- Keep work log updated for stigmergic visibility
- Only output significant decisions or blockers
- IPC messages should be concise (task ID + one-line status); detailed context goes in work logs
- At completion, provide a brief summary including:
  - Epoch context (task N of M complete)
  - Any discoveries recorded
  - Whether epoch is now complete
