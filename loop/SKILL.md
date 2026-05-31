---
name: loop
description: Repeatedly run a target Smart Assets skill or prompt alias until it reports completion, no remaining work, a blocker, or the iteration limit is reached
license: SSL
---

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop.

```
/loop <target-command> [target-arguments]

Examples:
  /loop /tdd
  /loop /task-tdd
  /loop /skill:task-tdd

Purpose: Re-run one single-cycle command until it naturally terminates, blocks,
or reaches the safety limit.
```

---

# Loop Runner

Run a target Smart Assets workflow repeatedly while preserving the target workflow's single-cycle contract.

## Intended use

Primary supported use:

```text
/loop /tdd
```

In Pi, `/tdd` is compatibility shorthand for the canonical `task-tdd` skill. Treat these target spellings as equivalent:

| User target | Canonical target |
|-------------|------------------|
| `/tdd` | `/skill:task-tdd` |
| `/task-tdd` | `/skill:task-tdd` |
| `/skill:task-tdd` | `/skill:task-tdd` |
| `/skill:tdd` | `/skill:task-tdd` |

## Safety rules

1. Do not loop arbitrary mutating commands unless the user explicitly requested this skill.
2. Default maximum iterations: 10.
3. Stop immediately if the target reports a blocker, user decision point, failing test that needs human judgment, permission denial, or unclear next step.
4. Stop when the target reports no remaining work or plan complete.
5. Summarize each iteration before starting the next.
6. Never hide repeated failures. If the same failure appears twice in a row, stop and report it.

## Execution protocol

1. Parse the target command and arguments from the user input.
2. Resolve known compatibility aliases to canonical skills:
   - `/tdd`, `/task-tdd`, `/skill:tdd`, `/skill:task-tdd` -> `task-tdd`
3. For each iteration:
   - Announce `Loop iteration N/<limit>: <target>`.
   - Load and follow the target skill.
   - Let the target perform exactly one cycle.
   - Inspect the target result.
4. Continue only when the target clearly indicates more work remains and no blocker is present.
5. Final response must include:
   - iterations run
   - completed cycles
   - stop reason
   - remaining work, if known

## Stop reasons

Stop when any of these is true:

- target says plan complete or no behaviors remain
- target returns or reports a natural no-work status
- target reports a blocker or asks for user input
- tests fail in a way that requires diagnosis beyond the target's single-cycle contract
- maximum iteration count is reached
- the target command is unknown or unsafe to loop

## Unknown target

If the target is not recognized, ask the user to choose one of:

1. `/loop /tdd` (Recommended) - Run TDD cycles until the plan is empty or blocked.
2. `/loop /skill:task-tdd` - Same as above using canonical Pi skill syntax.
3. Other - User specifies a target and explicit iteration limit.
