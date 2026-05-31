---
name: review-codebase
description: Surface architectural friction and propose deepening candidates after ratifying or bootstrapping a load-bearing project Glossary.md. Insists on a consistent glossary as a precondition for any review.
license: SSL
---

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT proceed with the command.

```
/review:codebase [SCOPE] [OPTIONS]

Arguments:
  [SCOPE]               Optional path to restrict the review (default: repo root)

Options:
  --glossary-only       Run only Phase 0 (glossary ratification / bootstrap)
  --skip-grilling       Stop after Phase 2 (write discovery, no parallel design)
  --min-terms N         Override the glossary floor (default: 8 canonical terms
                        each with **Preferred usage**)

Phases:
  0. Glossary Ratification   load-bearing gate, interview-driven
  1. Project & Goals          multi-checkpoint interview
  2. Exploration & Cards      candidate discovery, written to docs/discoveries/
  3. Grilling Loop            parallel interface-design sub-agents, accept/reject
```

---

# Review Codebase

`/review-codebase` is an architectural review skill. It surfaces friction in the
codebase and proposes **deepening candidates** -- refactors that turn shallow
modules into deep ones, concentrate locality, and raise testability. It refuses
to produce findings until the target repo has a load-bearing `docs/Glossary.md`
that the rest of the review can cite.

The skill is informed by, but does not re-litigate, existing architectural
decisions captured under `docs/designs/`. Settled ADRs are honored unless the
review surfaces friction that warrants reopening one.

## Universal Architectural Language

This vocabulary applies to every recommendation the skill makes. Do not
substitute "component," "service," "API," or "boundary." Consistent language
is a precondition, not a stylistic preference.

**Module**
Anything with an interface and an implementation. Scale-agnostic -- applies
equally to a function, class, package, or tier-spanning slice.
_Avoid_: unit, component, service.

**Interface**
Everything a caller must know to use the module correctly. Includes the type
signature, invariants, ordering constraints, error modes, required
configuration, and performance characteristics.
_Avoid_: API, signature (too narrow -- those refer only to the type-level
surface).

**Implementation**
What is inside a module: its body of code. Distinct from **Adapter**: a thing
can be a small adapter with a large implementation, or a large adapter with a
small implementation.

**Depth**
Leverage at the interface -- the amount of behavior a caller (or test) can
exercise per unit of interface they have to learn. A module is **deep** when a
large amount of behavior sits behind a small interface. A module is **shallow**
when the interface is nearly as complex as the implementation.

**Seam**
A place where you can alter behavior without editing in that place. The
*location* at which a module's interface lives. Choosing where to put the seam
is its own design decision, distinct from what goes behind it.
_Avoid_: boundary (overloaded with DDD's bounded context).

**Adapter**
A concrete thing that satisfies an interface at a seam. Describes *role* (what
slot it fills), not substance (what is inside).

**Leverage**
What callers get from depth: more capability per unit of interface they have
to learn. One implementation pays back across N call sites and M tests.

**Locality**
What maintainers get from depth: change, bugs, knowledge, and verification
concentrate at one place rather than spreading across callers.

### Principles

- **Depth is a property of the interface, not the implementation.** A deep
  module can be internally composed of small, mockable, swappable parts -- they
  just are not part of the interface. A module can have **internal seams**
  (private to its implementation, used by its own tests) as well as the
  **external seam** at its interface.
- **The deletion test.** Imagine deleting the module. If complexity vanishes,
  the module was not hiding anything (it was a pass-through). If complexity
  reappears across N callers, the module was earning its keep.
- **The interface is the test surface.** Callers and tests cross the same
  seam. If you want to test *past* the interface, the module is probably the
  wrong shape.
- **One adapter means a hypothetical seam. Two adapters means a real one.**
  Do not introduce a seam unless something actually varies across it.

These eight terms and four principles are the *universal* layer. The
**project-specific** layer lives in `docs/Glossary.md` of the target repo --
ratified or bootstrapped in Phase 0 below.

## Dependency Categories

Each candidate the skill surfaces must be classified by dependency category.
The category determines how its seam is tested and whether a port and adapter
pair is justified.

| Category | Definition | Seam strategy |
|----------|------------|---------------|
| **In-process** | Pure computation, in-memory state, no I/O | Merge and test through the new interface directly. No port needed. |
| **Local-substitutable** | Has a local test stand-in (in-memory DB, virtual filesystem) | Internal seam only; tests use the stand-in. No port at the external interface. |
| **Remote but owned** | Your own services across a network boundary | Define a port at the seam. In-memory adapter for tests; transport adapter for production. |
| **True external** | Third-party services you do not control | Inject the dependency through a port; tests use a mock adapter. |

## Phase 0 -- Glossary Ratification (Load-bearing Gate)

The glossary is **load-bearing**: every Phase 2 candidate card and every
Phase 3 ADR must cite glossary anchors. The review does not proceed without it.

### Step 0a -- Inventory

1. Look for `docs/Glossary.md` in the target repo.
2. If absent, search common alternates (`GLOSSARY.md`, `docs/glossary/`,
   `docs/common/glossary.md`).
3. If still absent, mark **bootstrap required** and proceed to Step 0b.
4. If present, parse it. For each canonical term, verify:
   - An H3 heading naming the term
   - A canonical-definition paragraph
   - A `**Preferred usage.**` subsection
   - At least one *Distinguish from* / *Avoid* callout for terms that have
     near-synonyms in common engineering vocabulary
   - At least one anchor-style cross-link to another glossary entry where the
     definitions reference each other

5. Count terms passing all four checks. If count `< --min-terms` (default 8),
   mark **bootstrap required** and proceed to Step 0b.

### Step 0b -- Glossary Bootstrap Interview

Use `AskUserQuestion` checkpoints. Each checkpoint is mandatory; the skill
cannot advance until it is answered. The reference style is the OTLaaS
`Glossary.md` -- see `assets/glossary-template.md` for the shape.

**Checkpoint G1 -- Domain scope.** Ask the user to pick the primary domain
this repo serves (data plane / control plane / protocol / UI / SDK / research
toolkit / other). Capture as `domain:` in the glossary header.

**Checkpoint G2 -- Architecture stack mapping.** Ask the user to name the
tiers in this repo's stack -- in this repo's own vocabulary, not generic
"frontend/backend/db." Capture in the **Architecture Stack Mapping** section.
This is the single most predictive input for the rest of the review.

**Checkpoint G3 -- Near-synonyms inventory.** For each tier named in G2, ask
the user to list near-synonyms used loosely in the codebase. The skill then
proposes which one is canonical and which become *Distinguish from* callouts.
Multi-select via `AskUserQuestion`.

**Checkpoint G4 -- Candidate canonical terms.** Walk the codebase
(`grepai search` per `CLAUDE.md`) for capitalized type names, prominent
interfaces, and recurring domain nouns. Present 6-12 candidates to the user
via `AskUserQuestion` (multi-select); the user keeps, drops, or renames each.

**Checkpoint G5 -- Preferred usage drafting.** For every kept term, the
skill drafts a `**Preferred usage.**` line describing *when* to use the term
and *what to use instead* in adjacent contexts. The user ratifies via
`AskUserQuestion` (Accept / Edit / Drop). Edits are captured inline.

**Checkpoint G6 -- Distinguish-from pairings.** For each pair of terms that
risk being conflated, propose a *Distinguish from X* paragraph that fixes the
boundary. User ratifies.

**Checkpoint G7 -- Anchor audit.** Generate Markdown anchors (`#term-slug`)
for every term, write the glossary file, then walk every internal anchor link
and confirm it resolves. Broken links block proceeding.

**Checkpoint G8 -- License or policy alignment (optional).** If the repo
ships under SSL or another structural license, capture the alignment section
mapping glossary terms to license definitions. Otherwise skip.

### Step 0c -- Write or update `docs/Glossary.md`

Write the result using `assets/glossary-template.md` as the
structural reference. Stigmergic: this file is now load-bearing for every
agent that touches the repo.

Add or update the repo's `CLAUDE.md` or `AGENTS.md` to include:

```markdown
**Glossary:** Project terminology lives in [docs/Glossary.md](docs/Glossary.md).
This glossary is load-bearing: documentation, ADRs, and code reviews cite
its anchors. See `**Preferred usage.**` subsections for canonical vs. avoided
phrasings.
```

If the repo lacks `CLAUDE.md` or `AGENTS.md`, do **not** create one as a side
effect; surface the gap in the Phase 2 discovery file instead.

### Phase 0 Gate

Phase 0 is complete when:

- [ ] `docs/Glossary.md` exists with at least `--min-terms` canonical entries
- [ ] Every entry has `**Preferred usage.**`
- [ ] At least three *Distinguish from* / *Avoid* callouts exist across the file
- [ ] The Architecture Stack Mapping section names the repo's tiers in its
      own vocabulary
- [ ] All internal anchors resolve

Only then proceed to Phase 1. Otherwise loop back to the failing checkpoint.

## Phase 1 -- Project and Goals Interview

Use `AskUserQuestion` checkpoints. Each is mandatory.

**Checkpoint P1 -- Review kind.** Greenfield audit / pre-MR check /
refactor-hunt / onboarding map / regression diagnosis.

**Checkpoint P2 -- Scope.** Whole repo / a directory / a feature slice
(user provides path or pattern). The skill confirms by listing the matching
file count back to the user.

**Checkpoint P3 -- Dependency category for the scope.** In-process /
local-substitutable / remote-but-owned / true-external. Use the table above.
Drives seam recommendations downstream.

**Checkpoint P4 -- Pain-point tag.** Locality (changes spread across many
files) / Leverage (small interfaces hide too little) / Coupling (concepts
leak across modules) / Testability (cannot test past the interface). Multi-
select allowed.

**Checkpoint P5 -- Existing ADRs to honor.** Read every file under
`docs/designs/` and summarize. Ask the user via `AskUserQuestion` whether any
listed ADR should be treated as **reopenable** based on Phase 1 friction.

**Checkpoint P6 -- Success criteria.** What would success look like for this
review (e.g., one accepted candidate, three ADRs drafted, a glossary
ratified)? Capture for the closing summary.

## Phase 2 -- Exploration and Candidate Surfacing

Use `grepai search` per `CLAUDE.md` as the primary tool. Fall back to Grep
or Glob only for exact-string lookups (imports, identifiers).

Apply the **deletion test** to every module the exploration touches.
Classify each candidate by dependency category from P3. For each candidate,
note:

- Which glossary anchors apply (link to `docs/Glossary.md#term`)
- The four-vector classification: depth, locality, seam placement, dependency
  category
- A one-sentence problem statement and a one-sentence solution statement
- Affected files (paths only, no excerpts longer than a few lines)
- A before-and-after diagram in Mermaid (no HTML, no Tailwind, no CDN
  dependencies)
- Recommendation strength: **must** / **should** / **consider**

Write the result to:

```
docs/discoveries/architecture-review-<ISO-timestamp>.md
```

using `assets/architecture-review-discovery.md` as the
structural reference. End the file with a single top recommendation and a
links section back to the glossary and any reopenable ADRs.

The file is now stigmergic: any agent that later runs `/nextTask` or reads
`docs/discoveries/` will see it.

## Phase 3 -- Grilling Loop with Parallel Interface Design

For each candidate the user chooses to pursue, launch parallel sub-agents
using the `Agent` tool. Send all of them in a **single message** with
multiple `Agent` tool calls so they run concurrently. Suggested mandates,
adjustable per candidate:

1. **Minimize the interface.** Aim for 1-3 entry points max. Maximize
   leverage per entry point. Agent type: `Plan`.
2. **Maximize flexibility.** Support many use cases and extension paths.
   Agent type: `Plan`.
3. **Optimize for the most common caller.** Make the default case trivial.
   Agent type: `Plan`.
4. **Ports and adapters across the seam.** Only when P3 classified the
   dependency as remote-but-owned or true-external. Agent type:
   `general-purpose`.

Each sub-agent receives a self-contained brief: the candidate problem,
affected files, dependency category, glossary anchors that constrain
vocabulary, and the deliverable (interface specification with usage
examples, dependency strategy, trade-off analysis).

After all sub-agents return, the skill presents the alternatives
sequentially -- one screen each -- then a comparative analysis on three
dimensions: **depth** (leverage at the proposed interface), **locality**
(where change concentrates), **seam placement** (where the interface
lives).

### Accept

If the user accepts a design, append a YAML task entry to `docs/ToDos.md`.
Acceptance criteria are expressed in **TDD-conformant language** so the
follow-on `/tdd` plan can audit them without rewriting:

```yaml
---
id: TODO-<EPIC>-<NNN>
title: "Deepen <module-name>"
status: pending
priority: p2
discovered_in: docs/discoveries/architecture-review-<timestamp>.md
glossary_terms:
  - docs/Glossary.md#<anchor-1>
  - docs/Glossary.md#<anchor-2>
dependency_category: in-process | local-substitutable | remote-but-owned | true-external
tdd_plan: docs/tdd-plans/<scope>-<timestamp>.md   # created by /tdd --from-discovery
acceptance_criteria:
  # Behaviors (what the deepened interface must do), not implementation steps.
  - Tests assert through the deepened interface (cite glossary anchor),
    never through internal state or private collaborators.
  - Mocks (if any) sit at the dependency-category boundary declared above;
    no internal collaborators are mocked.
  - Cycle granularity is one behavior at a time (vertical TDD); /tdd or
    /loop /tdd executes the plan. No horizontal slicing.
  - Old shallow-module tests are replaced, not layered.
  - Test names cite glossary anchors for every domain noun.
---
```

If no epic covers refactoring work in this area, propose adding one and
ask the user to confirm before writing.

### Integration with `/tdd`

`/tdd` is the canonical standard for executing accepted candidates. When
the user accepts a candidate:

1. The skill drafts the `tdd_plan:` path into the YAML task above (the
   plan file itself is not created until `/tdd --from-discovery` runs).
2. The skill emits a hand-off hint at session close:
   `/tdd --from-discovery docs/discoveries/architecture-review-<ts>.md`
   or, for multi-cycle execution:
   `/loop /tdd` (after the plan is created).
3. `/tdd` reads the discovery file, finds the accepted candidate, and
   translates its acceptance criteria into a behavior checklist with
   glossary-anchored test names. The plan persists at
   `docs/tdd-plans/<scope>-<ts>.md`.
4. `/tdd` audits the acceptance criteria against TDD-conformant language
   on a **soft** basis: deviations (implementation-step phrasing, internal
   mocks, horizontal scope) are surfaced in the plan's
   `conformance_audit:` frontmatter, not blocked. The user may re-run
   `/review-codebase` Phase 3 to rewrite the criteria, or override and
   continue.

The two skills share the load-bearing `docs/Glossary.md`: every behavior
statement in the TDD plan cites the same anchors that the candidate card
cited, so the test vocabulary and the architectural vocabulary are
identical by construction.

### Reject

If the user rejects a candidate for a **load-bearing reason** -- a
constraint that would re-emerge if a future review re-proposed the same
candidate -- draft an ADR to:

```
docs/designs/ADR-<NNN>-<slug>.md
```

using `assets/architecture-adr.md` as the structural
reference. The ADR captures: context, decision, consequences, and the
glossary terms that anchor the reasoning.

Rejection without a load-bearing reason produces no ADR -- the candidate
simply falls out of consideration for this review.

## Output Summary

At the end of the session, print:

- Glossary state: created / updated / ratified, with term count
- Discovery file path
- Accepted candidates: list with task IDs
- Rejected candidates with ADRs: list with ADR paths
- Reopenable ADRs flagged during Phase 1, if any
- Stigmergic handoff hint: which slash command runs next (`/nextTask`,
  `/implement`, or `/epic-review`)

## Vocabulary Rules

- Every recommendation must use the universal terms (module, interface,
  depth, seam, adapter, leverage, locality) without substitution.
- Every domain noun in a recommendation must resolve to a glossary anchor.
  If it does not, the skill must either add the term to the glossary
  (looping back through G4-G7) or rephrase using an existing term.
- "Component," "service," "boundary," and "layer" are not banned in user
  text, but the skill replaces them with the canonical term in its own
  output and surfaces the substitution in the discovery file as a glossary
  consistency note.

## Related Commands

- `/harmonize` -- run before `/review-codebase` to sync workspace policies
- `/tdd` -- canonical executor for accepted deepening candidates; pair as
  `/loop /tdd` for autonomous cycle iteration after Phase 3 acceptance
- `/nextTask` -- pick up accepted candidates as work
- `/implement` -- alternative implementation path when vertical TDD is not
  appropriate for the scope
- `/epic-review` -- re-scope after a batch of `/task-complete` invocations
- `/task-complete` -- close out deepening tasks with chain-walker enforcement

## Environment Variables

| Variable | Description |
|----------|-------------|
| `REVIEW_GLOSSARY_FLOOR` | Override the minimum canonical-term count (default 8) |
| `REVIEW_DISCOVERY_DIR` | Override the default `docs/discoveries/` output path |
| `REVIEW_ADR_DIR` | Override the default `docs/designs/` output path |
| `NO_COLOR` | Disable colored output in any summary printing |
