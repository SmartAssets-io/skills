---
name: cbc-verify
description: Verify, inspect, discharge, or waive CbC claims for cbc=mandatory artifacts using the evidence ledger
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
/cbc:verify <action> [arguments]

Actions:
  verify    <artifact> [--adapter mock|agentic|embedded] [--claim PATH] [--prover NAME]
  status    [<artifact>]
  discharge [--scope diff|epic <EID>] [--files "a b c"] [--strict] [--json]
  waive     <artifact> --reason TEXT

Pi: /skill:cbc-verify or /cbc-verify
```

---

# Verify and Discharge CbC Claims

`/cbc:verify` is the focused verification/gate skill for CbC-tagged artifacts.
It covers the operational subcommands that write or inspect evidence:
`verify`, `status`, `discharge`, and `waive`.

Use `/cbc:review` or `/skill:cbc-review` first to propose `cbc=mandatory` tags,
then `/cbc:scaffold` if you want deterministic scaffold/tag application. Use
this skill after claims/specifications exist and tagged artifacts need discharge.

## Backing script

```bash
"scripts/cbc.sh" <verify|status|discharge|waive> [arguments]
```

## Actions

### verify

```bash
"scripts/cbc.sh" verify src/consensus/vote.rs \
  --adapter agentic --claim docs/claims/vote-safety.md

"scripts/cbc.sh" verify specs/invariant.smt2 \
  --adapter embedded --prover z3 --claim docs/claims/invariant.md
```

Runs the selected adapter and writes a Markdown evidence record under
`docs/cbc-evidence/`. With `--adapter embedded --prover dafny|z3`, CbC prefers
the optional `pi-formal-verify` CLI and links its backend JSON evidence from
`docs/cbc-evidence/formal/`.

### status

```bash
"scripts/cbc.sh" status
"scripts/cbc.sh" status src/consensus/vote.rs
```

Shows ledger state for all records or a single artifact.

### discharge

```bash
"scripts/cbc.sh" discharge --scope diff --strict
```

Checks that every in-scope `cbc=mandatory` artifact has `discharged` or
`waived` evidence. `--strict` exits non-zero when gaps remain.

### waive

```bash
"scripts/cbc.sh" waive src/consensus/vote.rs \
  --reason "Manually discharged in external audit AUD-014"
```

Records an explicit waiver with rationale. Waivers satisfy the gate but remain
visible in the ledger.

## Formal verifier bridge

Install `pi-formal-verify` with Smart Assets Pi setup when you want direct Pi
formal-verification tools and the CbC embedded Dafny/Z3 bridge:

```bash
"scripts/setup-pi.sh" --local --with-formal-verify
# or:
"scripts/setup-pi.sh" --local --formal-verify /path/to/pi-formal-verify
```

The embedded adapter searches `PI_FORMAL_VERIFY_CLI`, `PI_FORMAL_VERIFY_PATH`,
then `pi-formal-verify` on PATH, then the current git root and standard sibling
workspace paths. A `discharged` backend status satisfies the CbC gate;
`refuted`, `unknown`, and `tool_error` do not.

## Safety

`verify` and `waive` write evidence records. `discharge` may block completion in
strict mode. Always inspect the resulting evidence and gate output before
marking a task complete.

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
