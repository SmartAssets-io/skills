---
kind: handoff
from: <Implementer Identification of the writing agent>
to: <Implementer Identification of the receiving agent, or "any">
produced_at: <ISO-8601 timestamp, compact form e.g. 20260522T143052Z>
retention: durable          # or: ephemeral (mirrored to $TMPDIR/sa-handoffs/, not committed)
focus: <one-sentence statement of what the next session should accomplish>
related_task: <TODO-id>     # optional
related_flow: <FLOW-id>     # optional
related_epic: <EPIC-id>   # optional
related_handoff: <relative path>  # optional, when this handoff continues a chain
redaction:
  categories_touched: []    # filled by the writer; e.g., [api_key, email, absolute_home_path]
  total_substitutions: 0
suggested_skills:
  - /tdd
  - /review-codebase
consumed_at: ""             # set by the receiver on read; must remain empty in producer output
consumed_by: ""             # set by the receiver on read; must remain empty in producer output
---

# Handoff -- `<from>` to `<to>`

`<One-paragraph framing: what context is being transferred and why this
handoff exists. Two to four sentences. Reference work logs, discoveries,
commits, or branches by path or hash rather than restating their
content.>`

## Current State

`<Two to four sentences. What has been done; where the cursor is. Cite
work logs, branches, commits, or task IDs by reference. No quoted
excerpts longer than a single short line.>`

## Key Artifacts

One line per entry. Path or URL first, then a short hint at why the
next agent should look there. No quoted excerpts.

- `docs/ToDos.md#TODO-<id>` -- `<one-sentence relevance>`
- `docs/work-logs/<file>` -- `<one-sentence relevance>`
- `docs/discoveries/<file>` -- `<one-sentence relevance>`
- `docs/designs/<file>` -- `<one-sentence relevance>`
- `docs/Glossary.md#<anchor>` -- `<one-sentence relevance>`
- `<git commit hash>` -- `<one-sentence relevance>`
- `<branch name>` -- `<one-sentence relevance>`
- `<URL>` -- `<one-sentence relevance>`

## Next-Agent Focus

`<Two to four sentences expanding the focus: frontmatter field.
Include constraints (deadlines, frozen interfaces, perf budgets),
blockers, and any decisions the next agent should defer rather than
make. If the focus is "continue cycle B3 from the TDD plan," name the
behavior and link the plan file.>`

## Suggested Skills

Mirror the frontmatter `suggested_skills:` list with a one-sentence
rationale per entry.

- `/tdd` -- `<rationale: e.g., next behavior in the plan is B<n>; run
  one cycle>`
- `/review-codebase` -- `<rationale: e.g., refactor surfaced an
  architectural question that should be reviewed before the next
  cycle>`
- `/quick-commit` -- `<rationale: e.g., uncommitted progress should be
  committed before the next agent starts>`
- `/harmonize` -- `<rationale: e.g., upstream policy changes detected;
  sync before continuing>`
- `<other>` -- `<rationale>`

The producer suggests the **minimum** set that lets the next agent
make progress, not every plausibly relevant skill.

## Open Questions

Unresolved questions the next agent should answer before proceeding.
Optional. Empty list is acceptable.

- [ ] `<question 1: e.g., should the deepened interface return a
  Result type or throw?>` (raised by `<from>`)
- [ ] `<question 2>` (raised by `<from>`)

When a future agent answers a question, append the answer inline
with the answering identity:

- [x] `<question text>` -- A: `<answer>` (answered by `<identity>` at
  `<ISO-timestamp>`)

## Redaction Notes

`<Short paragraph listing what was redacted, by category, not by
value. Mirrors the frontmatter redaction: block.>`

Example:

> Two `email` substitutions and one `absolute_home_path` substitution
> were applied at write time. The email occurrences were references to
> the human reviewer in a comment thread; the absolute path was a
> session-specific scratch directory mentioned in the work log.
> Identity-bearing references (e.g., `from:` / `to:` / `consumed_by:`)
> live in structured frontmatter fields and are exempt from body
> redaction.

If no redactions occurred, write:

> No redactions applied at write time. `categories_touched: []`,
> `total_substitutions: 0`.

## Consumption Footer

`<Empty in the producer's output. The consumer fills consumed_at:
and consumed_by: in the frontmatter on read. No body edit is needed
on consumption -- the footer is recorded only in the frontmatter.>`

`<If the consumer disagrees with the handoff or finds it stale, the
correction goes in a new handoff (from the consumer's identity to the
appropriate next agent), referencing this handoff via
related_handoff: in the new artifact's frontmatter. Do not overwrite
or edit a consumed handoff's body.>`
