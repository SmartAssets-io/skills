---
name: cbc-review
description: Review the codebase for mission-critical files and propose cbc=mandatory .gitattributes tags for human ratification
license: SSL
---

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/cbc:review [--base <ref>] [--config <path>] [--json]

  --base <ref>     Only consider files changed vs <ref> (default: all tracked files)
  --config <path>  Heuristics config (default: scripts/lib/cbc-critical-patterns.jsonc)
  --json           Emit a JSON array of candidates instead of the human proposal

Pi: /skill:cbc-review or /cbc-review
```

---

# Review Codebase for CbC-Mandatory Files

`/cbc:review` is the CbC-owned review step that scans a repository for files
that should be marked mission-critical with `cbc=mandatory` git attributes. It
uses the same deterministic scanner as `/review:identify-critical` and keeps
that review-genre command available as a compatibility/specialist entry point.

The command is proposal-only: it prints candidate `.gitattributes` lines for a
human to ratify. To create scaffolding and apply all proposed tags in one step,
use `/cbc:scaffold` / `/skill:cbc-scaffold`.

## Usage

```bash
"scripts/cbc-identify-critical.sh" [--base <ref>] [--config <path>] [--json]
```

## Workflow

1. Run `/cbc:review` to identify candidate critical files.
2. Review the risk, churn, LOC, and reason for each proposal.
3. Either manually append accepted lines to `.gitattributes`, or run
   `/cbc:scaffold` if you want the deterministic scaffold/apply step.
4. Run `/cbc:main identify` or legacy `/cbc identify` to confirm tagged files are in
   scope, then `/cbc:verify` to discharge claims.

## Related

- `/review:identify-critical` — retained review-genre entry point for the same scanner.
- `/cbc:scaffold` — initializes CbC directories and applies scanner-proposed tags.
- `/cbc:verify` — verify/status/discharge/waive workflow.

## Files

- **Command**: `AItools/plugins/cbc/commands/review.md`
- **Scanner**: `scripts/cbc-identify-critical.sh`
- **Config**: `scripts/lib/cbc-critical-patterns.jsonc`
- **Tests**: `AItools/tests/test-cbc-identify-critical.sh`
