---
name: design-wireframe
description: Generate a low-fidelity layout wireframe from a natural-language description, using the Smart Assets design system.
license: SSL
---

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
