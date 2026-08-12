---
name: task-next
description: Review project task tracking and stigmergic signals to identify and explain the next task to work on
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
/task:next [EPIC-ID]

Arguments:
  [EPIC-ID]            Scope to specific epic (e.g., EPIC-008)

Default: Analyzes docs/ToDos.md to find the highest-priority unclaimed task.
Priority: in_progress > pending, then p0 > p1 > p2 > p3, then epic number.
```

---

# Next Task Discovery

Review the project's task tracking and stigmergic signals to identify and explain the next task to work on.

## Inbound Handoffs (read first)

Before scanning epics and tasks, check `docs/handoffs/` for any
**unconsumed** handoff artifacts whose `to:` field matches the current
agent's identity or `to: any`. Handoffs are produced by other agents
(notably `/agent-team` workers and prior sessions) at delegation,
completion, or session-end edges. They carry compact, structured
context that supersedes generic task selection when present.

### Discovery rule

For each file in `docs/handoffs/`:

1. Parse the frontmatter.
2. Skip if `consumed_at:` is non-empty (already consumed).
3. Skip if `to:` is neither the current identity nor `any`.
4. Keep if all checks pass.

### Selection rule

If multiple matching handoffs exist:

1. Sort by `produced_at:` descending (newest first).
2. Group by `from:` and keep only the newest entry per producer
   (older entries are superseded by the same producer's newer ones).
3. Present the resulting set to the user, newest first.

### Surfacing

When at least one matching handoff is found, surface it **before**
running the epic parser. The user decides whether to honor the
handoff's `focus:` or fall through to normal task selection.

Use this template for each surfaced handoff:

```
Inbound handoff from <from> to <to>:
  Path: docs/handoffs/<filename>
  Focus: <one-sentence focus from frontmatter>
  Related task: <related_task or "(none)">
  Suggested skills: <comma-separated suggested_skills>
  Produced: <produced_at>
```

After surfacing, ask the user:

> Honor this handoff and pick up its focus, or proceed with normal
> /nextTask selection? If you honor it, this `/nextTask` invocation
> will surface the related task (or, if no related_task, the handoff's
> focus as a free-form next step).

### Consumption

If the user chooses to honor a handoff, mark it consumed **before**
starting work by updating its frontmatter:

```yaml
consumed_at: <ISO-timestamp of read>
consumed_by: <current Implementer Identification>
```

These are the only edits a consumer makes to a handoff. If the
handoff is stale or wrong, the correction goes in a new handoff
referencing the original via `related_handoff:`. Never overwrite a
handoff body.

If no matching handoffs exist, proceed directly to epic-aware task
selection below.

See [Handoff Document Standard](../../docs/common/handoff-standard.md)
for the full artifact shape, redaction rules, and producer behavior.

## Epic-Aware Task Selection

This command uses the epic parser library to understand the hierarchical task structure:

1. **Run the epic parser** to get the next task:
   ```bash
   "scripts/lib/epic-parser.sh" next-task docs/ToDos.md
   ```

2. **Interpret the output:**
   - `epic` - Current epic context (ID, title, priority, progress)
   - `task` - Next available task with description
   - `epic_queue` - Other pending epics in priority order

3. **For epic metrics:**
   ```bash
   "scripts/lib/epic-parser.sh" metrics EPIC-XXX docs/ToDos.md
   ```

## Stigmergic Context Gathering

Before selecting a task, also read these coordination files:

1. **Work logs** (`docs/work-logs/`) - Check for:
   - Existing progress on related tasks
   - Handoff notes from previous sessions
   - Blockers discovered by other agents

2. **Discoveries** (`docs/discoveries/`) - Check for:
   - Relevant findings from other agents
   - Patterns or code discovered that affects available tasks
   - Unresolved questions or decisions

3. **Design docs** (`docs/designs/`) - Check for:
   - Decisions that affect task implementation
   - Open questions needing answers
   - Architecture constraints

## Task Selection Rules

The epic parser applies these rules automatically:

### Epic-Level
- Priority ordering: p0 > p1 > p2 > p3
- Prefer epics with `in_progress` status (continue existing work)
- Respect `blocked_by` dependencies between epics
- Lower epic numbers preferred when priority is equal

### Task-Level (within epic)
- Resume own `in_progress` tasks first
- Select `pending` tasks with no blockers
- Respect `blocked_by` dependencies between tasks
- Lower task numbers preferred as tiebreaker

## Output Format

Provide a structured summary with epic context:

### Inbound Handoffs (if any)

```
Inbound handoff from <from> to <to>:
  Path: docs/handoffs/<filename>
  Focus: <one-sentence focus>
  Related task: <related_task or "(none)">
  Suggested skills: <comma-separated suggested_skills>
  Produced: <produced_at>
```

If no matching handoffs are found, omit this section entirely.

### Current Epic
```
Epic: [EPIC-ID] [Title]
Progress: [X/Y] tasks complete ([Z]%)
Priority: [p0-p3]
Status: [pending|in_progress|complete|blocked]
```

### Stigmergic Context
- Work logs found: [list any relevant work-logs]
- Discoveries relevant: [list any relevant discoveries]
- Blocked tasks: [list tasks blocked and why]
- In-progress by others: [list tasks with their `claimed_by` identifier, e.g. `human-jeff@example.com`, `design-sprint/researcher`]

### Just Completed
- What was recently finished or committed (if relevant)

### Next Task: **[TODO-XXX-NNN] Title**
- **Goal:** One-sentence description from task description
- **Epic:** [EPIC-ID] (task N of M)
- **Status:** Current status and claim state
- **Dependencies:** Any blockers or prerequisites
- **Acceptance Criteria:** Bullet list from task definition
- **Approach:** Numbered implementation steps
- **Files to modify:** List key files
- **Related Discoveries:** Findings that affect this task

### Epic Queue
List other pending epics in priority order:
1. EPIC-XXX (pN) - [status] - X/Y tasks
2. EPIC-YYY (pN) - [status] - X/Y tasks

### Notes
- Any observations about task status discrepancies
- Suggested task order if multiple are ready
- Any handoff notes from previous agents

## Instructions

- Do NOT start implementing - just explain the task and approach
- Ask for confirmation before proceeding with implementation
- If a task has a `claimed_by` value (human or agent), skip it unless claim is stale (>24h). See [Implementer Identification](../../docs/common/stigmergic-collaboration.md#implementer-identification) for identifier formats.
- If no epics found, fall back to flat task parsing from `docs/ToDos.md`
- If multiple tasks have equal priority within an epic, prefer one with relevant discoveries

## Fallback: Flat Task Format

If `docs/ToDos.md` contains flat tasks (no epics), the parser returns individual tasks sorted by priority. In this case, omit the epic context sections.

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
