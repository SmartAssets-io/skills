# Glossary

> This glossary is **load-bearing**: documentation, design decisions
> (`docs/designs/`), candidate discovery files (`docs/discoveries/`), and code
> review notes cite its anchors directly. Adding, renaming, or removing a term
> here is a documentation change, not a stylistic one.

This file keeps the repository's terminology consistent. It distinguishes the
canonical name for each concept from the near-synonyms that the codebase has
accumulated, and pins each name to a **Preferred usage** statement that
describes when the term applies and what to use instead in adjacent contexts.

The file is structured so anchor cross-links between entries always resolve.
Run `/review-codebase --glossary-only` to audit anchor integrity and the
minimum-term floor.

## Domain

`[domain]` -- one of: data plane, control plane, protocol, UI, SDK, research
toolkit, other (specify). Captured during `/review-codebase` Checkpoint G1.

## Canonical Terms

Each entry uses the following shape:

```
### <Term>

<canonical definition: 1-3 sentences, no jargon outside this glossary>

**Preferred usage.** <when to use; what to use instead in adjacent contexts>.
*Distinguish from* [<near-synonym>](#near-synonym): <one sentence>.
*Avoid*: <terms that look similar but mean something else>.
```

Anchors are GitHub-style slugs derived from the H3 heading (lowercase, spaces
to hyphens, punctuation stripped).

---

### `<TermOne>`

`<TermOne>` is `<one-sentence canonical definition>`. `<Extend with one or two
sentences naming the mechanism, role, or invariant the term carries.>`

**Preferred usage.** Use when `<context where this is the right word>`.
*Distinguish from* [`<TermTwo>`](#termtwo): `<one-sentence boundary>`.
*Avoid*: `<near-synonyms commonly mistaken>`.

### `<TermTwo>`

`<TermTwo>` names the role that `<does what>`. `<Extend with mechanism.>`

**Preferred usage.** Use when `<context>`.
*Distinguish from* [`<TermOne>`](#termone): `<boundary>`.
*Avoid*: `<near-synonyms>`.

### `<TermThree>`

...

---

Replace the placeholder entries above with the canonical terms ratified during
`/review-codebase` Checkpoints G4 through G6. The minimum-term floor is 8
(override with `REVIEW_GLOSSARY_FLOOR`).

## Architecture Stack Mapping

Name the tiers in this repository's stack using this repository's own
vocabulary, not generic "frontend / backend / database." This section is the
single most predictive input for architectural reviews because it pins which
canonical term applies at each tier.

- **`<tier-name-1>`** = `<one-sentence description of what runs at this tier
  and which canonical terms apply>`
- **`<tier-name-2>`** = ...
- **`<tier-name-3>`** = ...

If the project's stack vocabulary is borrowed from an upstream framework
(Ports and Adapters, Onion, Clean Architecture, BCE, etc.), cite the source
once and use the repository's own terms thereafter.

## Usage Notes

- Canonical terms are case-sensitive; the **Preferred usage** statement is
  the source of truth.
- When a recommendation in a design document or discovery file uses a term
  not listed here, either add the term (looping `/review-codebase`
  Checkpoints G4-G7) or rephrase using an existing term.
- Generic engineering words (component, service, boundary, layer, API,
  module) are not banned in user prose but should not appear in
  architectural recommendations when a canonical term is available. The
  architectural-review skill replaces such substitutions in its own output.
- *Distinguish from* callouts are required for any term whose meaning could
  be confused with another canonical term in this file, with a near-synonym
  in common engineering vocabulary, or with a term from an adjacent
  repository's glossary.

## License or Policy Alignment

If this repository ships under SSL or another structural license whose
definitions overlap with this glossary, map the alignment here:

- `<glossary term>` -- `<license section reference>`
- `<glossary term>` -- `<policy reference>`

Canonical source: `<link to the license or policy file>`.

Omit this section if no formal alignment is required.

## Maintenance

- Update this file before merging code or documentation that introduces a new
  domain term.
- Removing a term requires removing or rewriting every anchor that links to
  it; the `/review-codebase --glossary-only` audit will flag unresolved
  anchors.
- Renaming a term: add the new entry, mark the old entry as deprecated with a
  pointer to the new anchor, and migrate references over time. Do not delete
  the deprecated entry until no anchor links to it.
