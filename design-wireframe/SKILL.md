---
name: design-wireframe
description: Generate a low-fidelity layout wireframe from a natural-language description, using the Smart Assets design system.
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
/design:wireframe <description> [OPTIONS]

Arguments:
  <description>          Natural-language description of the screen/layout

Options:
  --output PATH          Output image path (default: design-output/wireframe-<ts>.png)
  --theme dark|light     Theme to render (default: dark)
  --dry-run              Print the resolved prompt; skip the API call

Requires GEMINI_API_KEY (or GOOGLE_API_KEY). See gemini.sh configuration.
```

---

You are helping the user generate a low-fidelity wireframe with the Smart Assets
design system, via the `design-generator.sh` pipeline (TODO-016-005).

## Architecture

**This command wraps a deterministic bash script:**

```
scripts/design-generator.sh
```

The script loads the `wireframe` prompt template
(`docs/brand/prompt-templates/wireframe.md`), injects design tokens from
`docs/brand/tokens/design-prompt.yaml`, and calls `gemini_design()` in the
`nano-banana.sh` provider (which reuses the Gemini API key from `gemini.sh`).

**Claude's role**:
- Treat the user's text after `/design:wireframe` as the `<description>`.
- Run the script, passing the description and any options through.
- Present the saved image path and the sidecar metadata file.

**Script's role**: Deterministic prompt assembly, API call, and output/metadata persistence.

## Configuration

Image generation requires a Gemini API key, resolved exactly like the existing
Gemini provider:

- `GEMINI_API_KEY` or `GOOGLE_API_KEY` must be set.
- Model/endpoint are configurable via `NANO_BANANA_MODEL` / `NANO_BANANA_API_BASE`.
  Defaults follow the documented Gemini image API shape and are flagged for
  verification (see `nano-banana.sh`).

## Usage

```bash
# Generate a wireframe
scripts/design-generator.sh wireframe \
    --description "a project dashboard with sidebar nav and a grid of bounty cards"

# Preview the prompt without calling the API
scripts/design-generator.sh wireframe \
    --description "a settings screen" --dry-run

# Light theme, custom output path
scripts/design-generator.sh wireframe \
    --description "a landing page hero" --theme light --output out/hero.png
```

## Output

The script writes the generated image to the output path and a sidecar
`<output>.json` containing the provider metadata plus the template name,
timestamp, and resolved prompt. Present both paths to the user.

## Examples

```
User: /design:wireframe a checkout flow with order summary and payment form
Claude: [runs: design-generator.sh wireframe --description "a checkout flow with order summary and payment form"]
        [reports the saved image + metadata paths]
```

```
User: /design:wireframe a mobile profile screen --dry-run
Claude: [runs: design-generator.sh wireframe --description "a mobile profile screen" --dry-run]
        [shows the resolved prompt that would be sent]
```

## Related

- `/design:component` - generate a single styled UI component
- Iteration/refinement (`--reference`) and export are tracked in TODO-016-007
  and TODO-016-008 respectively.

## Error Handling

- **No API key**: the provider returns an error object; relay that the user must
  set `GEMINI_API_KEY` / `GOOGLE_API_KEY`.
- **No description**: the script exits with a missing-variable error listing
  `DESCRIPTION`; prompt the user for a description.

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
