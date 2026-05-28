---
name: design-component
description: Generate a single UI component (button, card, form, navigation, ...) fully styled to the Smart Assets design system.
license: SSL
---

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/design:component <type> [description] [OPTIONS]

Arguments:
  <type>                 Component kind: button, card, form, navigation, ...
  [description]          What the component should contain/do

Options:
  --output PATH          Output image path (default: design-output/component-<ts>.png)
  --theme dark|light     Theme to render (default: dark)
  --dry-run              Print the resolved prompt; skip the API call

Requires GEMINI_API_KEY (or GOOGLE_API_KEY). See gemini.sh configuration.
```

---

You are helping the user generate a single, fully-styled UI component with the
Smart Assets design system, via the `design-generator.sh` pipeline (TODO-016-005).

## Architecture

**This command wraps a deterministic bash script:**

```
scripts/design-generator.sh
```

The script loads the `component` prompt template
(`docs/brand/prompt-templates/component.md`), injects design tokens from
`docs/brand/tokens/design-prompt.yaml`, and calls `gemini_design()` in the
`nano-banana.sh` provider (which reuses the Gemini API key from `gemini.sh`).

**Claude's role**:
- Parse the first token after `/design:component` as the component `<type>` and
  the remainder as the `[description]`.
- Pass `type` as `--var COMPONENT_TYPE=<type>` and the description via
  `--description`.
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
# Generate a component (type + description)
scripts/design-generator.sh component \
    --var COMPONENT_TYPE=card \
    --description "a bounty summary card with title, reward amount, and status badge"

# Preview the prompt without calling the API
scripts/design-generator.sh component \
    --var COMPONENT_TYPE=button --description "primary CTA" --dry-run

# Light theme
scripts/design-generator.sh component \
    --var COMPONENT_TYPE=navigation --description "top nav bar" --theme light
```

## Output

The script writes the generated image to the output path and a sidecar
`<output>.json` containing the provider metadata plus the template name,
timestamp, and resolved prompt. Present both paths to the user.

## Examples

```
User: /design:component card a bounty summary card with reward and status
Claude: [runs: design-generator.sh component --var COMPONENT_TYPE=card --description "a bounty summary card with reward and status"]
        [reports the saved image + metadata paths]
```

```
User: /design:component button primary call-to-action --dry-run
Claude: [runs: design-generator.sh component --var COMPONENT_TYPE=button --description "primary call-to-action" --dry-run]
        [shows the resolved prompt that would be sent]
```

## Related

- `/design:wireframe` - generate a low-fidelity layout wireframe
- Iteration/refinement (`--reference`) and export are tracked in TODO-016-007
  and TODO-016-008 respectively.

## Error Handling

- **No API key**: the provider returns an error object; relay that the user must
  set `GEMINI_API_KEY` / `GOOGLE_API_KEY`.
- **Missing type/description**: the script exits with a missing-variable error
  listing `COMPONENT_TYPE` / `DESCRIPTION`; prompt the user for them.
