---
kind: tdd-plan
scope: <path | module-name | candidate-id>
produced_by: /tdd
produced_at: <ISO-timestamp>
source_discovery: docs/discoveries/architecture-review-<ts>.md   # remove if standalone
source_candidate: C<n>                                            # remove if standalone
glossary: docs/Glossary.md
test_runner: pytest | vitest | jest | cargo-test | go-test | rspec | shell | other:<command>
system_boundaries:
  - external-api
  - time
  - filesystem
  - third-party-service
conformance_audit:
  status: pass | warnings | overridden
  notes: []
behaviors:
  - id: B1
    statement: <capability statement, not implementation step>
    priority: must | should | consider
    deep_module: false
    done: false
    cycle_log: []
  - id: B2
    statement: <capability statement>
    priority: must | should | consider
    deep_module: false
    done: false
    cycle_log: []
---

# TDD Plan -- `<scope>`

`<One-paragraph framing: what is under test, the public interface this plan
exercises, and the relationship to the source discovery file or candidate.
Cite glossary anchors for any domain noun.>`

## Public Interface

The interface under test (per `/tdd` Phase 1 Checkpoint T1):

- **Name:** `<canonical glossary anchor>`
- **Signature surface:** `<types, methods, entry points>`
- **Invariants:** `<what must always hold>`
- **Error modes:** `<expected failure shapes>`
- **Performance characteristics:** `<if relevant>`

Any change to this section requires re-running `/tdd` Planning (`--new`
against the same scope) because behaviors are pinned to the interface
shape, not the implementation.

## System Boundaries (Mocking Allowed)

Mocks may be placed at and only at these boundaries (per Checkpoint T4):

- `<boundary-1>` -- `<one sentence on what crosses it>`
- `<boundary-2>` -- `<one sentence>`

Anything inside these boundaries -- internal collaborators, your own
classes, anything you control -- is **not mockable** under this plan.
Cycles that introduce internal mocks must justify the deviation in the
cycle log and surface it during the next `/tdd` audit.

## Behavior Checklist

Each behavior is a **capability statement**, not an implementation step.
Test names should be readable as the statement itself.

- [ ] **B1** -- `<statement>` -- priority: `must` -- deep_module: `false`
- [ ] **B2** -- `<statement>` -- priority: `must` -- deep_module: `true`
- [ ] **B3** -- `<statement>` -- priority: `should` -- deep_module: `false`
- [ ] **B4** -- `<statement>` -- priority: `should` -- deep_module: `false`
- [ ] **B5** -- `<statement>` -- priority: `consider` -- deep_module: `false`

When a `/tdd` cycle completes a behavior, mark `[x]` and add the
corresponding `cycle_log` entry in the frontmatter.

## Cycle Log

Per-cycle records, appended after each `/tdd` invocation. Each entry
documents a single tracer bullet.

### B1 -- `<statement>` -- `<cycle ISO-timestamp>`

- **tracer:** true / false
- **test_name:** `<exact test name, readable as the behavior statement>`
- **test_file:** `path/to/test/file`
- **files_changed:**
  - `path/to/file-1`
  - `path/to/file-2`
- **runner_output:**
  - RED: `<one line confirming the test failed for the right reason>`
  - GREEN: `<one line confirming the test passed>`
  - Full suite: `<pass count / fail count>`
- **observations:**
  - `<what the cycle revealed about the interface or the implementation>`
- **refactor_performed:**
  - `<refactor step 1: e.g., extracted helper for duplication>`
  - `<refactor step 2>`
  - `<none>` if no refactor was warranted
- **refactor_deferred:**
  - `<opportunity to surface in a later --refactor-only invocation>`
- **new_behaviors_surfaced:**
  - `B<n>` -- `<statement>` -- added to checklist pending ratification
- **blockers:**
  - `<if cycle exited with status 3, the blocker is recorded here>`

### B2 -- `<statement>` -- `<cycle ISO-timestamp>`

`<repeat the structure above>`

## Glossary Anchors Used

Every behavior statement and test name cites at least one anchor below.
Definitions live in [docs/Glossary.md](../Glossary.md).

- [`<TermOne>`](../Glossary.md#termone)
- [`<TermTwo>`](../Glossary.md#termtwo)

If a behavior introduces a domain noun not in the glossary, the user
must either add the term (looping `/review-codebase` Checkpoints G4-G7)
or rephrase using an existing term before the cycle can mark `done:
true`.

## Completion

The plan is complete when every behavior is `[x]` and every cycle log
entry has a non-empty GREEN line. At completion:

- `/tdd --status` prints `plan complete: <this-path>` and exits with
  status 2.
- `/loop /tdd` treats status 2 as the natural terminator and stops.
- The user is prompted to invoke `/task-complete TODO-<id>
  --unit-tests <list>` to close the parent task; `<list>` is a
  comma-separated list of completed behaviors (B1, B2, ...).

## Reopening

A plan may be **reopened** by adding new unchecked behaviors. Common
triggers:

- A new behavior surfaced inside an existing cycle (`new_behaviors_
  surfaced`) and ratified by the user
- A reopened ADR (`docs/designs/ADR-<NNN>`) that changes the interface
- A new `/review-codebase` discovery against the same scope that
  proposes additional capabilities

Reopening does not re-time-stamp the plan; the file is the same
artifact across its lifetime. Use a new plan (fresh `<scope>-<ts>.md`)
only when the public interface itself changes.
