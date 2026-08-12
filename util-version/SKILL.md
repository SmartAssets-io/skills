---
name: util-version
description: Show git commit hash and date for workflow tools and current repository
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
/util:version [OPTIONS]

Options:
  --json                Machine-readable JSON output
  MULTI_REPO=true       Show all repos in workspace (env var)

Default: Shows workflow tools version + current repo.
```

---

You are helping the user check the version of their workflow tools and repositories.

**Purpose**: Provide users with commit hash and date information to verify they're on the current iteration of the workflow.

---

## Architecture

**This command uses a deterministic bash script:**

```
scripts/version.sh
```

**Claude's role**:
- Run the script with appropriate options
- Present the output to the user
- Show the current implementer identity (`git config --get user.email` / `git config --get user.name`) and the `claimed_by` value that would be used when claiming tasks
- Explain what the versions mean if asked

**Script's role**: Deterministic version retrieval from git repositories

---

## Mode Detection

The script automatically supports:
1. **Single-repo mode** (default): Shows workflow tools version + current repo if different
2. **Multi-repo mode** (`MULTI_REPO=true`): Shows all repos in the workspace

---

## Usage

### Basic Usage (Single-repo)

Run the script to show workflow tools version and current repo (if different):

```bash
scripts/version.sh
```

### Multi-repo Mode

Show versions for all repositories in the workspace:

```bash
MULTI_REPO=true scripts/version.sh
```

### JSON Output

For programmatic use, add `--json` flag:

```bash
scripts/version.sh --json
```

---

## Output

The script displays:

1. **Workflow Tools** - The top-level-gitlab-profile repository version (where commands/scripts live)
   - Commit hash (short SHA)
   - Commit date

2. **Current Repository** (single-repo mode) - If the user is in a different git repo
   - Repository name
   - Commit hash
   - Commit date

3. **All Repositories** (multi-repo mode) - Every git repo in the workspace
   - Repository name
   - Commit hash
   - Commit date

4. **Implementer Identity** - The current user's `claimed_by` identifier derived from git config
   - `git config --get user.email` → `human-{email}`
   - `git config --get user.name` → fallback if email not set
   - Helps verify which identity will be used when claiming tasks via `/implement` or `/work-tasks`
   - See [Implementer Identification](../../docs/common/stigmergic-collaboration.md#implementer-identification) for the full format reference

---

## Examples

### User wants to check their version

```
User: /version
Claude: [runs: scripts/version.sh]
        [displays output showing workflow tools version and current repo]
```

### User wants to see all repo versions

```
User: /version (with MULTI_REPO=true set)
Claude: [runs: MULTI_REPO=true scripts/version.sh]
        [displays output showing all repository versions in workspace]
```

### User wants JSON output

```
User: /version --json
Claude: [runs: scripts/version.sh --json]
        [displays JSON output]
```

---

## When to Use

Users should run `/version` when:
- Verifying they have the latest workflow tools
- Troubleshooting issues (to report exact version)
- Checking which commit they're working from
- Comparing their environment with others

---

## Error Handling

- **Not in a git repo**: Script shows workflow tools version and notes current directory is not a git repository
- **Git not available**: Script fails with error message
- **Repository inaccessible**: Individual repos are skipped with warnings

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
