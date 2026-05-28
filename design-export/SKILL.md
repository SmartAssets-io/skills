---
name: design-export
description: Export a design session for handoff — bundle the image(s), a design spec (tokens + prompts + version history), a local HTML preview, and an archive.
license: SSL
---

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/design:export --session <dir> [OPTIONS]

Options:
  --session DIR     Session directory (must contain session.json). Required.
  --output DIR      Bundle output directory (default: <session>/export)
  --all             Export every version (default: latest only)
  --no-archive      Skip the .tar.gz archive
  --format png      Image format (png only; svg/figma are unsupported)

Honest scope: raster pipeline -> PNG only. SVG/Figma and hosted shareable
links are not produced (see notes).
```

---

You are helping the user package a design session for handoff, via the
`design-export.sh` script. A session is produced by `/design:iterate`
(`design-output/<session>/` with `v<N>.png` images and a `session.json`).

## Architecture

**This command uses a deterministic bash script:**

```
scripts/design-export.sh
```

It assembles a handoff bundle containing:
- the selected version image(s) (PNG),
- `design-spec.md` — template, subject, theme, a version-history table, and the
  resolved prompt for each version,
- `index.html` — a local preview of the version(s),
- a `.tar.gz` archive of the bundle (unless `--no-archive`).

**Claude's role**:
- Identify the session directory the user wants to export (from a prior
  `/design:iterate` run).
- Run the script with `--latest` (default) or `--all`.
- Report the bundle directory and archive path.

## Honest scope (important)

This pipeline produces **raster PNG** images. The exporter does not fabricate
output it cannot truthfully produce:

- **SVG / Figma**: reported as unsupported (a raster image cannot be losslessly
  vectorized; Figma needs its API/format). Relay this plainly if asked.
- **Shareable links**: only a **local** `index.html` preview is produced;
  externally hosted shareable links require hosting infrastructure (follow-up).

## Usage

```bash
# Export the latest version of a session
scripts/design-export.sh --session design-output/dashboard

# Export every version
scripts/design-export.sh --session design-output/dashboard --all

# Custom bundle location, no archive
scripts/design-export.sh \
    --session design-output/dashboard --output handoff/dashboard --no-archive
```

## Examples

```
User: /design:export the dashboard session
Claude: [runs: design-export.sh --session design-output/dashboard]
        [reports bundle dir + archive; notes index.html is a local preview]
```

## Related

- `/design:iterate` - produces the sessions this command exports
- `/design:wireframe`, `/design:component` - single-shot generation

## Error Handling

- **Missing session.json**: exits 66; the path is not a design session.
- **--format svg|figma**: exits 2 with the reason it is unsupported.
