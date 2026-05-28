---
name: design-iterate
description: Conversationally refine a generated design ("make it more X"), tracking versions and history in a design session.
license: SSL
---

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/design:iterate <subcommand> [OPTIONS]

Subcommands:
  start <template> --description "..."   Seed a session (v1) from a template
  refine --session <dir> --feedback "..." Generate the next version from feedback
  history --session <dir>                 Print the session history

Common options: --theme dark|light, --session NAME, --output-dir DIR

Requires GEMINI_API_KEY (or GOOGLE_API_KEY). See gemini.sh configuration.
```

---

You are helping the user iteratively refine a design through conversational
feedback, via the `design-iterate.sh` wrapper around `design-generator.sh`
(TODO-016-005). Refinements reuse the `layout-variation` prompt template,
passing the previous version as a reference image and the feedback as the
variation instruction ("make it more X").

## Architecture

**This command uses a deterministic bash script:**

```
scripts/design-iterate.sh
```

A *session* is an output directory containing versioned images (`v1.png`,
`v2.png`, ...), their generator sidecars, and a `session.json` recording each
version's feedback, reference image, resolved prompt, and timestamp.

**Claude's role**:
- Map the user's intent to a subcommand: begin a new design (`start`), refine
  the latest version (`refine`), or show the conversation (`history`).
- For `refine`, treat the user's "make it more X" phrasing as `--feedback`.
- Report the new version path and the session directory.

**Script's role**: Deterministic version numbering, reference threading,
generation (via design-generator.sh), and session history persistence.

## Configuration

Generation requires a Gemini API key (`GEMINI_API_KEY` / `GOOGLE_API_KEY`),
resolved by the `nano-banana.sh` provider exactly like `gemini.sh`. Model and
endpoint are env-configurable (`NANO_BANANA_MODEL`, ...), with defaults flagged
for verification against the live API.

## Usage

```bash
# 1. Seed a session from a template
scripts/design-iterate.sh start wireframe \
    --description "a project dashboard with a grid of bounty cards" --session dashboard

# 2. Refine the latest version with feedback
scripts/design-iterate.sh refine \
    --session design-output/dashboard --feedback "make it more spacious and minimal"

# 3. Review the conversation history
scripts/design-iterate.sh history \
    --session design-output/dashboard
```

## Output

- `start` creates `design-output/<session>/v1.png` (+ sidecar) and `session.json`.
- `refine` adds `v<N+1>.png`, using `v<N>.png` as the reference, and appends a
  version entry to `session.json`.
- `history` prints the ordered `session.json` history.

Report the created version's path and the session directory to the user.

## Examples

```
User: /design:iterate start wireframe a settings screen with tabbed sections
Claude: [runs: design-iterate.sh start wireframe --description "a settings screen with tabbed sections"]
        [reports the session dir and v1 path]

User: /design:iterate make it more spacious   (with an active session)
Claude: [runs: design-iterate.sh refine --session <dir> --feedback "make it more spacious"]
        [reports v2 path]
```

## Related

- `/design:wireframe`, `/design:component` - single-shot generation
- `/design:export` - export/handoff (TODO-016-008)

## Error Handling

- **No API key**: the provider returns an error; relay that the user must set
  `GEMINI_API_KEY` / `GOOGLE_API_KEY`.
- **refine without a session**: exits 64 (needs `--session` + `--feedback`).
- **missing session.json**: exits 66; suggest running `start` first.
