---
name: cbc-scaffold
description: Initialize CbC evidence/claim scaffolding and apply scanner-proposed cbc=mandatory git-attribute tags
license: SSL
---

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/cbc:scaffold [--base <ref>] [--config <path>] [--dry-run] [--no-tags]

  --base <ref>     Scope tag proposals to files changed vs <ref>.
  --config <path>  Heuristics config for cbc-identify-critical.sh.
  --dry-run        Show planned directory and .gitattributes changes only.
  --no-tags        Create scaffolding only; do not run/apply tag proposals.

Pi: /skill:cbc-scaffold or /cbc-scaffold
```

---

# Scaffold a CbC Workspace

`/cbc:scaffold` initializes the repository for Correctness-by-Construction work
and, by default, applies all current scanner-proposed mission-critical tags.
It is the bootstrap/setup counterpart to `/cbc:review`.

## What it does

The deterministic backing script:

1. Creates `docs/cbc-evidence/.gitkeep` for verification evidence records.
2. Creates `docs/claims/.gitkeep` for claim/specification documents.
3. Ensures `.gitattributes` exists.
4. Runs `cbc-identify-critical.sh --json`.
5. Appends every candidate as:

```gitattributes
path/to/file cbc=mandatory cbc-weight=high|medium|low
```

Existing tags are preserved; the script only appends missing exact lines.
Use `--dry-run` to preview or `--no-tags` to create only the scaffold.

## Usage

```bash
"scripts/cbc-scaffold.sh" [--base <ref>] [--config <path>] [--dry-run] [--no-tags]
```

## Safety

This command intentionally mutates repository files when run without `--dry-run`:
`.gitattributes`, `docs/cbc-evidence/.gitkeep`, and `docs/claims/.gitkeep`.
Only run it when the user explicitly requested CbC scaffolding/tag application.
Review the resulting diff before committing.

## Related

- `/cbc:review` — proposal-only scanner output.
- `/cbc:main identify` or `/cbc identify` — reads ratified `.gitattributes` tags.
- `/cbc:verify` — discharges tagged artifacts and checks the gate.
