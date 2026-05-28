---
name: epic-review
description: Preview and summarize epics for high-level review of scope and progress before diving into implementation
license: SSL
---

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/epic:review [EPIC-ID] [OPTIONS]

Arguments:
  [EPIC-ID]            Show specific epic (e.g., EPIC-008)

Options:
  --list                List all epics with status summary
  --no-color            Disable colored output

Default: Shows next pending epic based on priority ordering.
```

---

# Epic Review

Preview and summarize epics for high-level review. Use this command to quickly understand the scope and status of epics before diving into implementation.

## Usage

Run the epic-review script to display epic information:

```bash
# Run from any repo with docs/ToDos.md
scripts/epic-review.sh [EPIC-ID] [--list] [--no-color]
```

## Modes

### Next Epic (Default)

When run without arguments, shows the next pending epic based on priority ordering:

```bash
scripts/epic-review.sh
```

Priority selection:
1. Prefer `in_progress` epics over `pending` (continue existing work)
2. Sort by priority field: `p0` > `p1` > `p2` > `p3`
3. Use epic number as tiebreaker (lower first)

### Specific Epic

Show a specific epic by ID:

```bash
scripts/epic-review.sh EPIC-008
```

Displays full details regardless of epic status.

### List All Epics

Show compact summary of all epics:

```bash
scripts/epic-review.sh --list
```

## Options

| Option | Description |
|--------|-------------|
| `--list` | List all epics in compact format |
| `--no-color` | Disable colored output |
| `--help`, `-h` | Show help message |

## Output Format

### Single Epic View

```
+==============================================================+
| EPIC-008: Multi-Agent PR/MR Review System                   |
+--------------------------------------------------------------+
| Status: pending                Priority: p3                  |
| Tasks:  0/9 complete (0%)                                    |
|                                                              |
| Breakdown:                                                   |
|   o pending:     9                                           |
|   > in_progress: 0                                           |
|   x blocked:     0                                           |
|   * complete:    0                                           |
+--------------------------------------------------------------+
| Tasks:                                                       |
|   o TODO-008-001  Design multi-agent review architecture     |
|   o TODO-008-002  Implement LLM provider interface           |
|   ...                                                        |
+==============================================================+

[!] Warnings:
  - None
```

### Status Symbols

| Symbol | Status |
|--------|--------|
| `o` | pending |
| `>` | in_progress |
| `x` | blocked |
| `*` | complete |

## When to Use

- **Before starting an epic:** Review scope and task count
- **During sprint planning:** Understand upcoming work
- **Quick status check:** See completion percentage at a glance
- **Task hygiene:** Check for validation warnings

## Related Commands

- `/nextTask` - Get the next task to work on
- `/implement` - Implement a specific task
- `/epic-hygiene` - Archive completed epics

## Environment Variables

| Variable | Description |
|----------|-------------|
| `NO_COLOR` | Set to disable colored output |
| `TODOS_FILE` | Override default `docs/ToDos.md` path |
