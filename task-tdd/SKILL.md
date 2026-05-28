---
name: task-tdd
description: Walk one test-driven development cycle (RED then GREEN, optionally Refactor while GREEN). Single-cycle-per-invocation by design so /loop /tdd composes safely. Reads docs/tdd-plans/<scope>-<ts>.md as the running behavior checklist and may be invoked standalone or as a follow-on to /review-codebase Phase 3 acceptance.
license: SSL
---

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT proceed.

```
/task:tdd [PLAN] [OPTIONS]

Arguments:
  [PLAN]                Path to a docs/tdd-plans/<scope>-<ts>.md plan file.
                        If omitted, the most recently modified plan in
                        docs/tdd-plans/ is used.

Options:
  --new <scope>         Bootstrap a fresh plan for <scope> (interactive)
  --from-discovery <p>  Bootstrap a plan from a /review-codebase discovery
                        file at path <p> and the candidate ID it accepted
  --behavior <id>       Run the cycle for a specific unchecked behavior B<n>
                        (default: first unchecked in the plan)
  --refactor-only       Skip RED+GREEN; run only the refactor pass on the
                        most recently completed cycle (must be GREEN)
  --status              Print plan completion summary, do not run a cycle

Workflow: Planning -> Tracer Bullet -> Incremental Loop -> Refactor
Each /tdd invocation walks exactly ONE cycle for ONE behavior.
Use /loop /tdd to iterate cycles autonomously until the plan is empty.
```

---

# Test-Driven Development (one cycle per invocation)

`/tdd` walks one vertical TDD cycle: a single RED test, the minimal GREEN
implementation that passes it, and an optional refactor pass that runs only
while tests are GREEN. The skill refuses to write more than one new test per
invocation, by design -- this is what makes `/loop /tdd` safe: each loop
iteration is a true tracer bullet, never a horizontal slice.

## Philosophy

Tests verify **behavior through public interfaces**, not implementation
details. A good test reads like a specification of capability: "user can
checkout with a valid cart" tells you exactly what behavior exists. It
survives refactors because it does not care about internal structure.

Tests that mock internal collaborators, assert on call counts, query a
database directly to verify state, or break when an internal function is
renamed are **implementation-detail tests**. They produce false confidence,
break under refactor, and miss real behavior failures. The skill flags and
refuses them at the cycle level.

## Anti-Pattern: Horizontal Slicing

**Do not** write all tests first and then all implementation. Treating RED
as "write every planned test" and GREEN as "write every line of code"
produces tests of *imagined* behavior, not actual behavior. They test
shapes (signatures, data structures), pass when behavior breaks, and fail
when behavior is fine.

**The correct shape is vertical.** One test responds to what you learned
from the previous cycle. Each cycle is end-to-end:

```
WRONG (horizontal):
  RED:   test1, test2, test3, test4
  GREEN: impl1, impl2, impl3, impl4

RIGHT (vertical, one per /tdd invocation):
  /tdd: RED test1 -> GREEN impl1 -> [optional Refactor while GREEN]
  /tdd: RED test2 -> GREEN impl2 -> [optional Refactor while GREEN]
  /tdd: RED test3 -> GREEN impl3 -> [optional Refactor while GREEN]
```

The single-cycle invariant is what makes `/loop /tdd` valid. A loop that
writes five tests per iteration is a horizontal slice with extra steps.

## Invocation Modes

1. **Standalone, fresh plan.** `/tdd --new <scope>` -- the skill interviews
   the user (via `AskUserQuestion`) to draft a behavior checklist, then
   writes `docs/tdd-plans/<scope>-<ISO-ts>.md` and stops. The first cycle
   does not run automatically; the user invokes `/tdd` (no args) to begin.
2. **Standalone, existing plan.** `/tdd` (no args) -- pick the most-recently
   modified plan under `docs/tdd-plans/`, run one cycle for its first
   unchecked behavior, update the plan, exit.
3. **From `/review-codebase` acceptance.** `/tdd --from-discovery
   docs/discoveries/architecture-review-<ts>.md` -- read the discovery
   file, find the accepted candidate, draft a plan that translates the
   candidate's success criteria into a behavior checklist (using glossary
   anchors as test-name vocabulary), and stop. Subsequent `/tdd` invocations
   run cycles.
4. **Loop mode.** `/loop /tdd` -- the loop skill re-invokes `/tdd` on its
   own cadence (or dynamically). Each iteration completes one cycle. When
   the plan's checklist is empty, the next `/tdd` prints "plan complete"
   and exits with a non-zero "no work" signal so the loop terminates.

## Phase 1 -- Planning (one-time, gated)

If no plan exists for the scope, the skill runs the Planning interview
before any cycle. Planning is itself gated on the **load-bearing
`docs/Glossary.md`** -- if the glossary is missing or thin, the skill
recommends running `/review-codebase --glossary-only` first.

`AskUserQuestion` checkpoints, each mandatory:

**T1 -- Public interface.** What is the **interface** under test? (Use the
universal architectural language from `/review-codebase`: interface
includes type signature, invariants, ordering constraints, error modes,
required configuration, performance characteristics.) Multi-choice if a
discovery file is loaded; free-text if `--new`.

**T2 -- Behavior list.** List 3-12 **behaviors** the interface must
satisfy. Each behavior is a capability statement, not an implementation
step. Examples:
- GOOD: "user can checkout with a valid cart"
- BAD: "checkout calls paymentService.process"
- GOOD: "retrieving a created user returns the original name"
- BAD: "createUser inserts a row into users table"

The skill rejects behavior phrasings that name internal methods, mock call
counts, or storage details, and proposes a rephrasing the user ratifies.

**T3 -- Test priorities.** You cannot test everything. Mark each behavior
as **must / should / consider**. The plan walks must first, then should,
then consider. Multi-select via `AskUserQuestion`.

**T4 -- Mocking boundary.** Where does the system end and external code
begin? Capture as a list of **system boundaries** (external APIs, time,
randomness, file system if relevant, third-party services). Mocks are
allowed at and only at this boundary. Anything inside it -- your own
classes, internal collaborators, anything you control -- is **not
mockable** under this plan.

**T5 -- Test runner.** Auto-detect from project signals:
- `pyproject.toml` -> pytest (or whatever `[tool.pytest]` or
  `[project.optional-dependencies]` indicates)
- `package.json` -> first of `vitest`, `jest`, `playwright`, `mocha`
  found in dependencies
- `Cargo.toml` -> `cargo test`
- `go.mod` -> `go test`
- `AItools/tests/test-*.sh` -> shell harness
- `.rspec` / `Gemfile` with rspec -> `rspec`

If detection is ambiguous, `AskUserQuestion` presents the candidates plus
"Other (specify)". The chosen runner persists to the plan's frontmatter
as `test_runner:` and can be overridden by editing the plan.

**T6 -- Deep-module candidates.** Ask the user to mark which behaviors
suggest a **deep module** opportunity (small interface, lots of
implementation hidden behind it). Captured as `deep_module: true` on
matching behaviors. Drives the Refactor pass's deepening heuristic.

The skill writes the plan to `docs/tdd-plans/<scope>-<ISO-ts>.md` using
`AItools/templates/tdd-plan.md` as the structural reference.

## Phase 2 -- Tracer Bullet (first cycle only)

If the plan is fresh (no behaviors completed yet), the first cycle is a
**tracer bullet**: pick the highest-priority behavior, write a test that
exercises the interface end-to-end (even if some pieces are stubbed), and
get to GREEN with the absolute minimum implementation. The tracer proves
the path works; subsequent cycles fill in.

The skill annotates the first behavior's log entry with `tracer: true`
for posterity.

## Phase 3 -- Incremental Loop (every subsequent cycle)

For one unchecked behavior:

1. **RED.** Write exactly **one** new test that fails for the right
   reason. Run the test runner; confirm the failure message is consistent
   with the behavior statement (not, e.g., a compile error or import
   failure).
2. **GREEN.** Write the **minimal** implementation that makes the test
   pass. Do not anticipate the next behavior. Do not write helpers,
   abstractions, or speculative branches.
3. **Run the full test suite.** Confirm no other test regressed.
4. **Refactor while GREEN (optional).** See Phase 4.
5. **Update the plan.** Mark the behavior `[x]`, append a cycle-log entry
   with: test name, files changed, observations, any new behaviors
   discovered (added to the plan as unchecked items, ratified by user on
   next `/tdd` invocation), and any refactor opportunities deferred.

If the test does not go RED for the right reason, **stop**. Surface the
failure mode to the user (compile error, missing import, fixture broken).
Do not paper over.

If GREEN cannot be reached with minimal code, **stop**. Surface the
friction; it may indicate a missing behavior, an interface that does not
match the behavior statement, or an unrecognized dependency at the
boundary. The user decides whether to update the plan or change the
interface.

## Phase 4 -- Refactor (while GREEN, never RED)

After GREEN, look for:

- **Duplication.** Extract a function or class.
- **Long methods.** Break into private helpers; tests remain on the
  public interface.
- **Shallow modules.** Combine or deepen (small interface, large
  implementation hidden behind it).
- **Feature envy.** Move logic to where the data lives.
- **Primitive obsession.** Introduce value objects with named meaning.
- **Existing code the new code reveals as problematic.**

Run the test runner after every refactor step. If any test goes RED,
revert the step and proceed.

**Never refactor while RED.** Get to GREEN first. This rule is
non-negotiable.

`--refactor-only` runs Phase 4 without a new RED+GREEN cycle (useful when
the previous cycle's GREEN logged "deferred refactor" notes).

## Per-Cycle Checklist

Before marking a behavior complete:

- [ ] Test describes behavior, not implementation
- [ ] Test uses the **public interface** only; no internal mocks
- [ ] Test would survive an internal refactor that preserves behavior
- [ ] Code is **minimal** for this test only -- no speculative features
- [ ] Mocks (if any) sit at a **system boundary** declared in T4
- [ ] Test name vocabulary matches `docs/Glossary.md` anchors where the
      domain noun is canonical

## Mocking Rules

Mock **at system boundaries only**:
- External APIs (payment, email, etc.)
- Databases (sometimes; prefer a real test DB)
- Time and randomness
- File system (sometimes)

**Do not mock**:
- Your own classes or modules
- Internal collaborators
- Anything you control

### Designing for mockability at the boundary

- **Dependency injection**: pass external dependencies in rather than
  constructing them inside the unit under test.
- **SDK-style interfaces over generic fetchers**: one specific function
  per operation, not a single `fetch(endpoint, options)` with conditional
  logic inside the mock. Each function returns one shape; tests assert
  one shape.

## Conformance with `/review-codebase`

`/tdd` is the canonical TDD standard cited by `/review-codebase` Phase 3.
When a candidate is accepted, the discovery file's acceptance criteria
should already be expressed in TDD-conformant language:

- "Tests assert through `<interface anchor>`, never through internal
  state"
- "Mocks (if any) sit at the dependency-category boundary declared in P3"
- "Cycle granularity is one behavior at a time"

When `/tdd --from-discovery` reads a discovery file, it audits the
acceptance criteria against this language and **surfaces** (does not
block on) deviations such as:
- Acceptance criteria that name implementation steps instead of behaviors
- Required tests that name internal collaborators or assert call counts
- Mocking that crosses into internal modules

This is **soft conformance**: `/tdd` records the audit in the plan's
frontmatter under `conformance_audit:` and proceeds. The user may rerun
`/review-codebase` Phase 3 against the same candidate to rewrite the
acceptance criteria, or override and continue.

## Plan File Format

Plans live at `docs/tdd-plans/<scope>-<ISO-ts>.md`. See
`AItools/templates/tdd-plan.md` for the structural reference. Frontmatter:

```yaml
---
kind: tdd-plan
scope: <scope>                      # path, module name, or candidate ID
produced_by: /tdd
produced_at: <ISO-timestamp>
source_discovery: docs/discoveries/architecture-review-<ts>.md   # optional
source_candidate: C<n>              # optional
glossary: docs/Glossary.md
test_runner: pytest | vitest | jest | cargo-test | go-test | rspec | shell | other:<command>
system_boundaries:
  - external-api
  - time
  - filesystem
conformance_audit:
  status: pass | warnings | overridden
  notes: []
behaviors:
  - id: B1
    statement: "user can checkout with a valid cart"
    priority: must | should | consider
    deep_module: false
    done: false
    cycle_log: []
---
```

## Loop Compatibility

`/loop /tdd` is the canonical multi-cycle invocation. Each `/tdd` does:

1. Pick the first unchecked behavior in the plan (or honor `--behavior`).
2. Walk one RED-GREEN(-Refactor) cycle.
3. Mark the behavior `done: true` and append a `cycle_log` entry.
4. Print a short summary and exit.

When the plan has no unchecked behaviors, `/tdd` prints
`plan complete: <plan-path>` and exits with status 2 ("no work"). The
loop skill treats status 2 as the natural terminator and stops.

If a cycle aborts mid-step (RED for wrong reason, GREEN unreachable,
refactor broke a test), `/tdd` exits with status 3 ("blocked"), records
the blocker in the plan's last `cycle_log` entry, and the loop pauses
for user input.

## Handoff Points

- **To `/task-complete`**: When a plan's checklist is empty and all
  behaviors are GREEN, suggest `/task-complete TODO-<id> --unit-tests
  <list>` to close the parent task.
- **To `/review-codebase`**: When Phase 4 surfaces a deepening
  opportunity that exceeds the current candidate's scope, suggest a new
  architectural review for the surrounding module. The user decides
  whether to interrupt the loop.
- **To `/quick-commit`**: After each successful cycle, suggest
  `/quick-commit` if the user is in safe mode. Loop mode commits between
  cycles to keep history granular.

## Related Commands

- `/review-codebase` -- architectural review; can hand off accepted
  candidates to `/tdd` via `--from-discovery`
- `/loop` -- multi-iteration runner; pair as `/loop /tdd`
- `/implement` -- alternative implementation path; not vertical-TDD by
  default
- `/task-complete` -- close out a task after all behaviors are GREEN
- `/quick-commit` -- per-cycle granular commits

## Environment Variables

| Variable | Description |
|----------|-------------|
| `TDD_PLANS_DIR` | Override default `docs/tdd-plans/` |
| `TDD_TEST_RUNNER` | Force a runner regardless of plan frontmatter |
| `TDD_FAIL_FAST` | If `true`, exit status 3 immediately on any cycle deviation (default `true` in loop mode) |
| `NO_COLOR` | Disable colored output in summaries |
