---
name: work-tasks
description: Launch the todo-task-executor agent to systematically work through remaining tasks using stigmergic coordination
license: SSL
---

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/work-tasks

Launches the todo-task-executor agent to autonomously work through
remaining tasks in docs/ToDos.md using stigmergic coordination.

The agent claims, implements, and completes tasks in priority order.
For interactive single-task work, use /nextTask + /implement instead.
```

---

# Work Through Tasks

Launch the todo-task-executor agent to systematically work through remaining tasks using stigmergic coordination.

## Instructions

Use the Task tool with these parameters:
- `subagent_type`: "todo-task-executor"
- `prompt`: "Use stigmergic collaboration to work through tasks autonomously. For each task cycle: 1) Read docs/ToDos.md and check for unclaimed pending tasks, 2) Check docs/work-logs/ and docs/discoveries/ for context, 3) Claim the task by setting `status: in_progress` and `claimed_by:` using the Implementer Identification format — solo agents use `{tool}-session[-{id}]` (e.g. `claude-session-a1b2c3`), team members use `{team-name}/{member-name}`, humans use `human-{git config --get user.email}`. See docs/common/stigmergic-collaboration.md#implementer-identification for full reference. 4) Create a work log at docs/work-logs/task-{id}-{timestamp}.md, 5) Implement fully, recording findings in your work log, 6) Update task status and add handoff notes, 7) Continue to next unclaimed task. Work autonomously until all tasks are done or blocked."

The agent will:
1. Read the TODO file and gather stigmergic context
2. Identify the next **unclaimed** pending task
3. **Claim the task** by updating status and claimed_by fields
4. **Create work log** for session visibility
5. Implement it fully, recording discoveries
6. **Update handoff notes** and task status
7. Repeat until all tasks are complete or blocked

## Stigmergic Behavior

The agent follows stigmergic conventions:
- **Claims tasks** before working using [Implementer Identification](../docs/common/stigmergic-collaboration.md#implementer-identification) format (prevents parallel conflicts)
- **Creates work logs** for visibility across sessions
- **Records discoveries** that help other implementers
- **Updates handoff notes** even when pausing
- **Respects existing claims** — skips tasks with a `claimed_by` value (human or agent) unless stale (>24h)

Note: The agent runs autonomously through the full cycle. For interactive task selection, use /nextTask directly instead.
