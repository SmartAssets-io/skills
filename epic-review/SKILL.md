---
name: epic-review
description: Preview and summarize epics for high-level review of scope and progress before diving into implementation
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
/epic:review [EPIC-ID] [OPTIONS]

Arguments:
  [EPIC-ID]            Show specific epic (e.g., EPIC-008)

Options:
  --list                List all epics with status summary
  --no-color            Disable colored output

Default: Shows next pending epic based on priority ordering.
```

---

# Epic Review

Preview and summarize epics for high-level review. Use this command to quickly understand the scope and status of epics before diving into implementation.

## Usage

Run the epic-review script to display epic information:

```bash
# Run from any repo with docs/ToDos.md
scripts/epic-review.sh [EPIC-ID] [--list] [--no-color]
```

## Modes

### Next Epic (Default)

When run without arguments, shows the next pending epic based on priority ordering:

```bash
scripts/epic-review.sh
```

Priority selection:
1. Prefer `in_progress` epics over `pending` (continue existing work)
2. Sort by priority field: `p0` > `p1` > `p2` > `p3`
3. Use epic number as tiebreaker (lower first)

### Specific Epic

Show a specific epic by ID:

```bash
scripts/epic-review.sh EPIC-008
```

Displays full details regardless of epic status.

### List All Epics

Show compact summary of all epics:

```bash
scripts/epic-review.sh --list
```

## Options

| Option | Description |
|--------|-------------|
| `--list` | List all epics in compact format |
| `--no-color` | Disable colored output |
| `--help`, `-h` | Show help message |

## Output Format

### Single Epic View

```
+==============================================================+
| EPIC-008: Multi-Agent PR/MR Review System                   |
+--------------------------------------------------------------+
| Status: pending                Priority: p3                  |
| Tasks:  0/9 complete (0%)                                    |
|                                                              |
| Breakdown:                                                   |
|   o pending:     9                                           |
|   > in_progress: 0                                           |
|   x blocked:     0                                           |
|   * complete:    0                                           |
+--------------------------------------------------------------+
| Tasks:                                                       |
|   o TODO-008-001  Design multi-agent review architecture     |
|   o TODO-008-002  Implement LLM provider interface           |
|   ...                                                        |
+==============================================================+

[!] Warnings:
  - None
```

### Status Symbols

| Symbol | Status |
|--------|--------|
| `o` | pending |
| `>` | in_progress |
| `x` | blocked |
| `*` | complete |

## When to Use

- **Before starting an epic:** Review scope and task count
- **During sprint planning:** Understand upcoming work
- **Quick status check:** See completion percentage at a glance
- **Task hygiene:** Check for validation warnings

## Related Commands

- `/nextTask` - Get the next task to work on
- `/implement` - Implement a specific task
- `/epic-hygiene` - Archive completed epics

## Environment Variables

| Variable | Description |
|----------|-------------|
| `NO_COLOR` | Set to disable colored output |
| `TODOS_FILE` | Override default `docs/ToDos.md` path |

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
