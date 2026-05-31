---
name: task-complete
description: Mark a task or epic complete with integrity reporting. Runs the user-flow chain walker, stamps any completion_gaps into YAML, and flips status.
license: SSL
---

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/task:complete <TODO-XXX-NNN | EPIC-XXX> [OPTIONS]

Options:
  --unit-tests p1,p2,...   (task only) write into task's unit_tests: field
  --strict                 refuse on any integrity gaps
  --force                  override --strict refusal
  --no-stamp               do not write completion_gaps: into YAML

Default behaviour: warn on gaps, stamp `completion_gaps:`, then mark complete.
```

---

# Task Completion

Mark a single task or an entire epic complete with integrity reporting against
the user-flow chain (`FLOW → US → EPIC → TASK → unit tests → integration
tests`). The wrapper is the documented way to flip `status: complete`; reviewers
read the stamped `completion_gaps:` field to know which links were still missing
when the item was closed.

## Usage

```bash
"scripts/task-complete.sh" TODO-016-002 \
    --unit-tests tests/unit/banana.spec.ts,tests/unit/gemini.spec.ts

"scripts/task-complete.sh" EPIC-016
```

### Task mode

For `TODO-XXX-NNN` the wrapper:

1. (optional) Writes `unit_tests: [p1, p2, ...]` into the task YAML when `--unit-tests` is supplied.
2. Calls `/user-flow integrity --task TODO-XXX-NNN`.
3. If any gaps are reported they are printed as a warning.
4. Stamps `completion_gaps: [code1, code2, ...]` into the task YAML (skipped with `--no-stamp`).
5. Sets `status: complete` and `completed_date: <today>`.

### Epic mode

For `EPIC-XXX` the wrapper:

1. Requires every child task to already carry `status: complete`. If any are still pending, it refuses and reports the gap.
2. Calls `/user-flow integrity --epic EPIC-XXX`.
3. The most consequential gap to watch for is `no_integration_tests` — the user-flow lifecycle expects integration tests to be authored once all tasks are complete.
4. Stamps `completion_gaps:` and flips `status: complete`.

## Flags

| Flag | Effect |
|------|--------|
| `--unit-tests p1,p2,...` | Write a comma-separated list to the task's `unit_tests:` field before validation. Task mode only. |
| `--strict` | Refuse to flip `status: complete` when any gaps are present. Exit code 3. |
| `--force` | Override a `--strict` refusal. Still prints the gap report. |
| `--no-stamp` | Skip writing `completion_gaps:` into the YAML even when gaps exist. |
| `--help`, `-h` | Show synopsis. |

## Integrity grades

The walker scores each target as one of:

- `full` — chain intact and every test/back-reference is present.
- `partial` — target exists but some chain links are missing.
- `missing` — target not found, or chain unreadable.

The `completion_gaps:` field captures the canonical gap codes
(`no_unit_tests`, `no_integration_tests`, `no_flow_link`, `flow_not_found`,
`no_related_stories`, `story_not_found`, `story_missing_backref`,
`no_epic_link`, `epic_not_found`).

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Marked complete (possibly partial) |
| 1 | Target not found |
| 2 | Invalid arguments |
| 3 | `--strict` blocked completion because of gaps (use `--force` to override) |
| 4 | YAML write error |

## Related commands

- `/user-flow integrity` — read-only chain report (any target or `--all`).
- `/user-flow test-spec` — emit a Given/When/Then artifact for integration test authoring.
- `/user-flow link` — record integration tests / stories / epics on a flow.
- `/implement` — should call this wrapper rather than editing YAML directly.

## Files

- **Command**: `AItools/commands/task-complete.md`
- **Driver**: `scripts/task-complete.sh`
- **Walker library**: `scripts/lib/integrity-walker.sh`
- **Targets**: `docs/ToDos.md`, `docs/User-Flows.md`, `docs/UserStories.md`
