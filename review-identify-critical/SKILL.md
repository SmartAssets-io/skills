---
name: review-identify-critical
description: Scan the codebase for mission-critical (CbC-mandatory) files and propose cbc=mandatory .gitattributes tags for human ratification
license: SSL
---

<!-- ste-policy: required -->
## Language Standard

For English technical prose, obey the [Simplified Technical English policy](#simplified-technical-english).
Apply the policy to text that this command creates or substantially rewrites.
Machine-significant and quoted text remains exempt.
Honor explicit non-English requests.
For committed prompt or policy files, run the repository STE Check and complete a human STE Review.

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/review:identify-critical [--base <ref>] [--config <path>] [--json]

  --base <ref>     Only consider files changed vs <ref> (default: all tracked files)
  --config <path>  Heuristics config (default: scripts/lib/cbc-critical-patterns.jsonc)
  --json           Emit a JSON array of candidates instead of the human proposal

Proposes cbc=mandatory .gitattributes tags; never writes .gitattributes.
```

---

# Identify Mission-Critical Code (CbC)

`/review:identify-critical` is the review-tooling step that **identifies the
mission-critical parts of the codebase** and proposes `cbc=mandatory` git
attributes for them. It is the assisted, bootstrapping half of the CbC flow
(FLOW-009 step 1): it produces the tags that `/cbc:main identify` (or the legacy
flat `/cbc identify`) later reads and the `/cbc:verify` discharge gate enforces.

It complements `/code-review` (the built-in diff reviewer): where `/code-review`
finds correctness bugs in a change, `/review:identify-critical` decides *which
code is important enough to require formal discharge*.

## Why this is a separate command

`/code-review` is a Claude Code **built-in skill** with no editable repo file, so
the mission-critical scan is realized here in the repo's review tooling rather
than by modifying `/code-review`. The same capability, owned where it can be
versioned and tested.

## Usage

The command drives a deterministic scanner:

```bash
"scripts/cbc-identify-critical.sh" [--base <ref>] [--config <path>] [--json]
```

## How it scores

A file is a **candidate** only if it matches a rule in
`scripts/lib/cbc-critical-patterns.jsonc` (sensitive extension, path
segment, or basename). Git **churn** (commits touching the file) and file
**size** (LOC) then refine the proposed `cbc-weight`:

```
score  = risk (1-3, from the matched rule)
       + churn_bonus (+2 high tier / +1 mid tier)
       + size_bonus  (+2 high tier / +1 mid tier)
weight = high | medium | low   (by score thresholds in the config)
```

Files already tagged `cbc=mandatory` are excluded.

## Output (proposal only)

The command **never writes `.gitattributes`**. It prints candidates and
ready-to-paste lines for a human to review and commit:

```
Proposed CbC-mandatory tags (2 candidate(s)):
(review and append accepted lines to .gitattributes; nothing is written automatically)

  high    src/consensus/vote.rs    (risk=3 churn=12 loc=420  consensus / safety-critical)
  medium  contracts/escrow.move    (risk=3 churn=2  loc=88   smart-contract code)

Proposed .gitattributes additions:
  src/consensus/vote.rs   cbc=mandatory cbc-weight=high
  contracts/escrow.move   cbc=mandatory cbc-weight=medium
```

Use `--json` for a machine-readable array (`{path, weight, score, risk, churn, loc, reason}`).

## Workflow

1. Run `/review:identify-critical` (optionally `--base <ref>` to scope to a change).
2. Review the proposed tags; edit `scripts/lib/cbc-critical-patterns.jsonc`
   if the heuristics over- or under-reach.
3. Append the accepted lines to `.gitattributes` and commit.
4. `/cbc:main identify` (or legacy `/cbc identify`) then resolves those tags;
   `/cbc:verify verify` / `/cbc:verify discharge` enforce them at the gate.

## Related

- `/cbc:main` and `/cbc:verify` — identify / verify / discharge against the tags this command proposes
- `/code-review` — built-in diff correctness review (runs before the gate)
- Design: `docs/designs/cbc-skill.md` (Assisted identification)

## Files

- **Command**: `AItools/plugins/review/commands/identify-critical.md` (this file)
- **Scanner**: `scripts/cbc-identify-critical.sh`
- **Config**: `scripts/lib/cbc-critical-patterns.jsonc`
- **Tests**: `AItools/tests/test-cbc-identify-critical.sh`

---

## Simplified Technical English Policy

The policy in this section governs applicable English technical prose from this skill.
The ASD standard remains authoritative.
Machine-significant text and quoted or external text remain exempt.
Honor explicit requests for another language.
## Simplified Technical English
<!-- ste-policy: full -->

Smart Assets uses ASD-STE100 Simplified Technical English, Issue 9, dated January 2025, for applicable English technical prose.

This policy is a Smart Assets applicability profile. The ASD standard remains the authoritative source for its rules and controlled dictionary.

Get the current standard from the [official ASD-STE100 website](https://www.asd-ste100.org/) or its [official downloads page](https://www.asd-ste100.org/STE_downloads.html).

ASD owns the standard and the ASD-STE100 trademark. Do not copy its controlled dictionary, examples, or substantial rule text into this repository.

### Applicability

Use this policy for English technical prose that an assistant creates or substantially rewrites, including:

- Assistant responses
- Technical documentation
- Plans and specifications
- Procedures and instructions
- Warnings and cautions
- Review findings
- User-facing explanations and status messages.

Preserve unaffected legacy prose. Apply this policy to the text that the assistant adds or substantially changes.

If the user explicitly requests another language, use that language. If you report STE status, mark STE as not applicable to that output.

This policy does not apply to:

- Code, identifiers, commands, flags, paths, URLs, and schema keys
- Data formats, exact test fixtures, and machine-generated text
- Verbatim quotations and user-supplied text
- Third-party names, standard titles, and legal or license text.

Do not change technical meaning, safety controls, legal meaning, or exact user requirements only to satisfy a language rule.

### Words and terminology

Use the official Issue 9 dictionary as the source for general approved words. Do not copy the dictionary into project files.

Use a word only with its approved part of speech, meaning, and form. Use American English spelling unless another directive controls the text.

Use approved technical nouns and technical verbs for the applicable subject field. Record recurring Smart Assets terms in the project glossary.

Use one technical noun for one concept. Do not replace a canonical term with a synonym only for stylistic variation.

Keep a new technical noun short and easy to understand. Use no more than three words unless an approved term requires more words.

Do not use regional words, slang, or unexplained jargon. Define an unavoidable abbreviation at its first use.

Use technical nouns as nouns. Use technical verbs as verbs and only in their approved software-development meaning.

### Grammar and sentences

Use active voice. In descriptive text, use passive voice only when the agent is unknown or technically unimportant.

Use simple verb forms and tenses. Avoid progressive and other complex constructions unless an exempt technical term requires them.

Use a direct verb to describe an action. Do not hide an action in an abstract noun phrase.

Write complete sentences. Do not omit articles, subjects, verbs, or necessary nouns to make a sentence shorter.

Do not use contractions. Do not use semicolons.

Keep each sentence focused on one subject. Use a vertical list when one sentence would contain complex items or actions.

Make each pronoun refer to one clear noun. Repeat the technical noun when a pronoun can have more than one meaning.

### Procedures

Use a maximum of 20 words in each procedural sentence. Use one instruction in each sentence unless actions occur at the same time.

Start each instruction with an imperative verb. Put a necessary condition before the instruction and separate it with a comma.

Use numbered steps when sequence is important. Keep information-only notes separate from instructions, requirements, limits, and safety information.

### Descriptions

Use a maximum of 25 words in each descriptive sentence. Give information gradually and keep one topic in each paragraph.

Start each paragraph with its topic. Use no more than six sentences in one paragraph.

Use consistent key words to connect related sentences. Start a new paragraph when the topic changes.

### Safety information

Use the project-approved risk word or symbol. Start with a clear command or condition, and then state the risk or possible result.

Do not hide safety information in a note. Keep safety controls and their consequences explicit.

### Verification

An **STE Check** is deterministic. It can check policy coverage, sentence limits, paragraph limits, contractions, semicolons, and selected exemptions.

An **STE Review** is semantic. A human reviewer must check vocabulary, meaning, active voice, referents, terminology, and technical accuracy.

For committed prompt and policy files, run the repository STE Check. Review all applicable new or substantially rewritten prose before completion.

A checker cannot establish full ASD-STE100 conformance. Do not claim that text is ASD-STE100 compliant only because an automated check passes.
