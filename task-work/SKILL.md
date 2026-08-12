---
name: task-work
description: Launch the todo-task-executor agent to systematically work through remaining tasks using stigmergic coordination
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
/task:work

Launches the todo-task-executor agent to autonomously work through
remaining tasks in docs/ToDos.md using stigmergic coordination.

The agent claims, implements, and completes tasks in priority order.
For interactive single-task work, use /nextTask + /implement instead.
```

---

# Work Through Tasks

Launch the todo-task-executor agent to systematically work through remaining tasks using stigmergic coordination.

## Instructions

Use the Task tool with these parameters:
- `subagent_type`: "todo-task-executor"
- `prompt`: "Use stigmergic collaboration to work through tasks autonomously. For each task cycle: 1) Read docs/ToDos.md and check for unclaimed pending tasks, 2) Check docs/work-logs/ and docs/discoveries/ for context, 3) Claim the task by setting `status: in_progress` and `claimed_by:` using the Implementer Identification format — solo agents use `{tool}-session[-{id}]` (e.g. `claude-session-a1b2c3`), team members use `{team-name}/{member-name}`, humans use `human-{git config --get user.email}`. See docs/common/stigmergic-collaboration.md#implementer-identification for full reference. 4) Create a work log at docs/work-logs/task-{id}-{timestamp}.md, 5) Implement fully, recording findings in your work log, 6) Update task status and add handoff notes, 7) Continue to next unclaimed task. Work autonomously until all tasks are done or blocked."

The agent will:
1. Read the TODO file and gather stigmergic context
2. Identify the next **unclaimed** pending task
3. **Claim the task** by updating status and claimed_by fields
4. **Create work log** for session visibility
5. Implement it fully, recording discoveries
6. **Update handoff notes** and task status
7. Repeat until all tasks are complete or blocked

## Stigmergic Behavior

The agent follows stigmergic conventions:
- **Claims tasks** before working using [Implementer Identification](../../docs/common/stigmergic-collaboration.md#implementer-identification) format (prevents parallel conflicts)
- **Creates work logs** for visibility across sessions
- **Records discoveries** that help other implementers
- **Updates handoff notes** even when pausing
- **Respects existing claims** — skips tasks with a `claimed_by` value (human or agent) unless stale (>24h)

Note: The agent runs autonomously through the full cycle. For interactive task selection, use /nextTask directly instead.

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
