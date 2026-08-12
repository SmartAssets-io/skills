---
name: task-implement
description: Begin implementation of the next task supporting both IPC and stigmergic coordination with epic-aware progress tracking
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
/task:implement [TASK-ID]

Arguments:
  [TASK-ID]             Specific task to implement (e.g., TASK-001)

Default: Implements the task identified by /nextTask.
Supports IPC and stigmergic coordination with epic-aware progress tracking.
Prerequisite: Run /nextTask first (or have task context ready).
```

---

# Implement Next Task

Begin implementation of the task identified by `/nextTask`. This command assumes you have already reviewed the task and explained the approach to the user.

## Prerequisites

- `/nextTask` has been run (or equivalent task analysis completed)
- User has confirmed they want to proceed with implementation
- Task goal, acceptance criteria, and approach are understood

## Epic Context

When working on epic-based tasks:

1. **Get current epic context**:
   ```bash
   "scripts/lib/epic-parser.sh" next-task docs/ToDos.md
   ```

2. **Track epic progress**:
   - Note the current epic ID and task position (task N of M)
   - Update task status within the epic YAML block
   - Check for epic completion after finishing tasks

## Coordination Setup

### Coordination Mode

- **Agent team member** (IPC tools available, system prompt identifies team role): Use `SendMessage` and `TaskUpdate` for real-time coordination with the orchestrator, AND update `.md` files for persistence/audit.
- **Solo agent** (no IPC tools): Use stigmergic `.md` files only.
- Both modes ALWAYS update `docs/ToDos.md` and work logs -- `.md` files are the system of record.

### 1. Claim the Task (Epic Format)

Before starting work, update the task within its epic in `docs/ToDos.md`:

```yaml
tasks:
  - id: TODO-XXX-NNN
    title: "Task title"
    status: in_progress          # Changed from 'pending'
    claimed_by: claude-session   # Solo agent: {tool}-session[-{id}]
    claimed_at: 2025-01-15T10:00:00Z
    # Other valid claimed_by formats:
    #   human-jeff@example.com      # Human (from: git config --get user.email)
    #   human-Jeff Smith            # Human (fallback: git config --get user.name)
    #   design-sprint/researcher    # Agent team member
    #   design-sprint/lead          # Agent team lead
```

Note: For epic-based tasks, the task is nested within the epic's `tasks:` array. See [Implementer Identification](../../docs/common/stigmergic-collaboration.md#implementer-identification) for the full format reference.

**Agent team members:** After updating `docs/ToDos.md`, notify the orchestrator via `SendMessage` with the task ID and a one-line summary of what you're starting.

### 2. Create Work Log

Create a work log file at `docs/work-logs/task-{id}-{timestamp}.md`:

```markdown
# Work Log: TODO-XXX-NNN Implementation

## Session Info
- **Started**: [ISO timestamp]
- **Implementer**: [your claimed_by value, e.g. claude-session-a1b2c3 or human-jeff@example.com]
- **Task**: [Task title]
- **Epic**: [EPIC-XXX] (task N of M)

## Progress
- [ ] [First step]
- [ ] [Next step]

## Findings
<!-- Document discoveries for other agents -->

## Blockers
<!-- Unresolved issues -->

## Handoff Notes
<!-- Context for next agent/session -->
```

**Agent team members:** Also mark your IPC task as `in_progress` via `TaskUpdate` if the task was assigned by the orchestrator.

## Process

### 1. Create Todo List

Use TodoWrite to create a structured task list based on the approach outlined:
- Break down implementation into discrete, trackable steps
- Include verification steps (tests, typecheck, lint)
- Mark the first task as `in_progress`

### 2. Implementation Loop

For each todo item:

1. **Mark as in_progress** before starting work
2. **Read relevant files** before making changes - never modify code you haven't read
3. **Make focused changes** - one logical unit per todo item
4. **Verify the change** - run tests, typecheck, or lint as appropriate
5. **Mark as completed** immediately after finishing (don't batch completions)
6. **Update work log** with progress after each significant step. **Agent team members:** Send brief progress via `SendMessage` after major milestones (not every micro-step).

### 3. Record Discoveries

When you find something other agents should know:
- Add to `## Findings` section in your work log
- For significant discoveries, create `docs/discoveries/{date}-{topic}.md`
- Update related task notes if discovery affects other work

### 4. Follow Project Conventions

- Check `CLAUDE.md` or `AGENTS.md` for project-specific guidelines
- Use existing patterns from the codebase
- Prefer editing existing files over creating new ones
- Use `data-testid` attributes for test selectors
- Keep changes minimal - don't over-engineer or add unrequested features

### 5. Verification Steps

After all implementation todos are complete:
- Run `pnpm typecheck` or equivalent
- Run `pnpm test` or equivalent
- Run `pnpm lint` or equivalent
- Verify the acceptance criteria are met

### 6. Completion

When implementation is complete:

1. **Update work log** with final status:
   ```yaml
   ---
   handoff_status: complete
   completed_at: [ISO timestamp]
   ---
   ```

2. **Mark the task complete via the wrapper** (do NOT edit YAML by hand):
   ```bash
   "scripts/task-complete.sh" TODO-XXX-NNN \
       --unit-tests tests/unit/file_a.spec.ts,tests/unit/file_b.spec.ts
   ```
   The wrapper:
   - Writes the supplied `--unit-tests` list into the task's `unit_tests:` YAML field.
   - Runs the chain integrity walker (`FLOW → US → EPIC → TASK → unit tests → integration tests`).
   - Stamps any `completion_gaps:` into the task YAML so reviewers see what was left undone (e.g. `no_integration_tests` is normal until the epic is complete).
   - Flips `status: complete` + `completed_date`.

   Pass `--strict` to refuse completion when gaps exist, or `--no-stamp` to skip recording the gaps.

3. **Check epic completion**:
   ```bash
   "scripts/lib/epic-parser.sh" metrics EPIC-XXX docs/ToDos.md
   ```
   If all tasks in the epic are complete, note the epic completion.

4. **IPC completion (agent team members only)**:
   - Mark the IPC task as `completed` via `TaskUpdate`
   - Send a completion summary to the orchestrator via `SendMessage` including: task ID, what was implemented, and any follow-up items

5. **Summarize** what was implemented
6. **List discoveries** recorded for other agents
7. **Note follow-up items** discovered
8. **Do NOT** proactively commit - wait for user to invoke `/quick-commit`

## Epic Completion

When all tasks in an epic are complete:

1. **Verify completion**:
   ```bash
   "scripts/lib/epic-parser.sh" metrics EPIC-XXX docs/ToDos.md
   ```
   Check that `derived_status` is `complete` and `percent_complete` is 100.

1a. **Author integration tests** against `docs/test-specs/<FLOW-ID>.md`
   (generate the spec with `/user-flow test-spec FLOW-XXX` if missing), then
   record them via `/user-flow link FLOW-XXX <path-or-ITEST-id>`.

1b. **Mark the epic complete via the wrapper**:
   ```bash
   "scripts/task-complete.sh" EPIC-XXX
   ```
   The wrapper refuses if any child task is still pending. It runs the chain
   walker (which surfaces `no_integration_tests` if the flow is still
   un-tested), stamps `completion_gaps:`, and flips the epic's `status: complete`.

2. **Display completion message**:
   ```
   Epic EPIC-XXX Complete!
   Title: [Epic title]
   Tasks: X/X (100%)

   Next Epic: EPIC-YYY - [Next epic title]
   ```

3. **Suggest next steps**:
   - Run `/nextTask` to see the next epic's first task
   - Run `/epic-hygiene` to archive the completed epic
   - Consider running `/quick-commit` if work is ready

## Error Handling

- If a step fails, keep it as `in_progress` and create a new todo for the blocker
- **Update work log** with blocker details for other agents
- If blocked by missing information, use AskUserQuestion
- If the approach needs revision, explain and get user confirmation before changing course
- If blocked by another task, update `blocked_by` field in the task YAML
- **Agent team members:** Notify the orchestrator via `SendMessage` when blocked, so the team can reassign or unblock

## Output Style

- Be concise - focus on doing the work, not explaining it
- Show progress through todo updates
- Keep work log updated for stigmergic visibility
- Only output significant decisions or blockers
- IPC messages should be concise (task ID + one-line status); detailed context goes in work logs
- At completion, provide a brief summary including:
  - Epic context (task N of M complete)
  - Any discoveries recorded
  - Whether epic is now complete

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
