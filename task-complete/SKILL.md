---
name: task-complete
description: Mark a task or epic complete with integrity reporting. Runs the user-flow chain walker, stamps any completion_gaps into YAML, and flips status.
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
