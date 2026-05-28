---
kind: architecture-decision-record
id: ADR-<NNN>
slug: <kebab-case-title>
status: accepted | superseded | reopenable
produced_by: /review-codebase
produced_at: <ISO-timestamp>
related_discovery: docs/discoveries/architecture-review-<timestamp>.md
related_candidate: C<n>
glossary: docs/Glossary.md
glossary_terms:
  - docs/Glossary.md#<anchor-1>
  - docs/Glossary.md#<anchor-2>
supersedes:
  - ADR-<NNN>  # optional, remove block if not applicable
superseded_by:
  - ADR-<NNN>  # optional, remove block if not applicable
---

# ADR-<NNN>: `<Title>`

## Status

`accepted` -- `<one sentence on why this decision is durable; what would need
to be true for it to be reopened>`

## Context

`<2-4 paragraphs describing the situation that led to this decision. Cite
glossary anchors directly: "the [DeepModule](../Glossary.md#deepmodule) at
`<path>` was proposed as a [PortAdapter](../Glossary.md#portadapter)
deepening candidate during the review at <discovery-link>." Avoid generic
words ("component," "service") where a canonical term applies.>`

## Decision

`<The decision in one paragraph. Speak in declarative present tense.
Example: "We do not introduce a port at the seam between <TermA> and <TermB>
because the dependency is in-process and the deletion test shows that
deleting <TermA> would not redistribute complexity to its callers.">`

## Load-bearing reasons

This is an ADR because the rejection is **load-bearing** -- a future review
will re-encounter this same friction and propose the same candidate again
unless the reasoning below is durable.

- `<constraint 1: e.g., dependency category is in-process and no test stand-
  in is required>`
- `<constraint 2: e.g., the perceived shallowness is intentional under a
  separate decision recorded in ADR-<NNN>>`
- `<constraint 3: e.g., the seam is hypothetical (one-adapter rule) and
  would be indirection>`

## Consequences

**Positive**

- `<consequence 1>`
- `<consequence 2>`

**Negative**

- `<consequence 1>`
- `<consequence 2>`

**Neutral / trade-offs**

- `<observation 1>`

## Alternatives considered

- **Deepen at the proposed seam.** Rejected because `<reason tied to a
  load-bearing reason above>`.
- **<other alternative>.** Rejected because `<reason>`.

## Glossary anchors

This decision cites the following canonical terms:

- [`<TermOne>`](../Glossary.md#termone) -- `<role in this decision>`
- [`<TermTwo>`](../Glossary.md#termtwo) -- `<role in this decision>`

If any of the cited anchors are removed, renamed, or re-scoped in
`docs/Glossary.md`, this ADR must be reviewed for whether the reasoning
still holds.

## Reopening criteria

This ADR may be **reopened** if any of the following becomes true:

- `<criterion 1: e.g., a second adapter is required, converting the
  hypothetical seam into a real one>`
- `<criterion 2: e.g., the dependency category shifts from in-process to
  remote-but-owned>`
- `<criterion 3: e.g., a glossary term cited above is redefined>`

When reopened, mark the status as `reopenable` and link the new discovery
file under `related_discovery`.
