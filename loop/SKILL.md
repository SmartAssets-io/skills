---
name: loop
description: Repeatedly run a target Smart Assets skill or prompt alias until it reports completion, no remaining work, a blocker, or the iteration limit is reached
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
