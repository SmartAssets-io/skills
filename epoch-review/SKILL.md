---
name: epoch-review
description: Preview and summarize epochs for high-level review of scope and progress before diving into implementation
license: SSL
---

# Epoch Review

Preview and summarize epochs for high-level review. Use this command to quickly understand the scope and status of epochs before diving into implementation.

## Usage

Run the epoch-review script to display epoch information:

```bash
# Run from any repo with docs/ToDos.md
scripts/epoch-review.sh [EPOCH-ID] [--list] [--no-color]
```

## Modes

### Next Epoch (Default)

When run without arguments, shows the next pending epoch based on priority ordering:

```bash
scripts/epoch-review.sh
```

Priority selection:
1. Prefer `in_progress` epochs over `pending` (continue existing work)
2. Sort by priority field: `p0` > `p1` > `p2` > `p3`
3. Use epoch number as tiebreaker (lower first)

### Specific Epoch

Show a specific epoch by ID:

```bash
scripts/epoch-review.sh EPOCH-008
```

Displays full details regardless of epoch status.

### List All Epochs

Show compact summary of all epochs:

```bash
scripts/epoch-review.sh --list
```

## Options

| Option | Description |
|--------|-------------|
| `--list` | List all epochs in compact format |
| `--no-color` | Disable colored output |
| `--help`, `-h` | Show help message |

## Output Format

### Single Epoch View

```
+==============================================================+
| EPOCH-008: Multi-Agent PR/MR Review System                   |
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

- **Before starting an epoch:** Review scope and task count
- **During sprint planning:** Understand upcoming work
- **Quick status check:** See completion percentage at a glance
- **Task hygiene:** Check for validation warnings

## Related Commands

- `/nextTask` - Get the next task to work on
- `/implement` - Implement a specific task
- `/epoch-hygiene` - Archive completed epochs

## Environment Variables

| Variable | Description |
|----------|-------------|
| `NO_COLOR` | Set to disable colored output |
| `TODOS_FILE` | Override default `docs/ToDos.md` path |
