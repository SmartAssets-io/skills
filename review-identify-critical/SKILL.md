---
name: review-identify-critical
description: Scan the codebase for mission-critical (CbC-mandatory) files and propose cbc=mandatory .gitattributes tags for human ratification
license: SSL
---

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/review:identify-critical [--base <ref>] [--config <path>] [--json]

  --base <ref>     Only consider files changed vs <ref> (default: all tracked files)
  --config <path>  Heuristics config (default: scripts/lib/cbc-critical-patterns.jsonc)
  --json           Emit a JSON array of candidates instead of the human proposal

Proposes cbc=mandatory .gitattributes tags; never writes .gitattributes.
```

---

# Identify Mission-Critical Code (CbC)

`/review:identify-critical` is the review-tooling step that **identifies the
mission-critical parts of the codebase** and proposes `cbc=mandatory` git
attributes for them. It is the assisted, bootstrapping half of the CbC flow
(FLOW-009 step 1): it produces the tags that `/cbc:main identify` (or the legacy
flat `/cbc identify`) later reads and the `/cbc:verify` discharge gate enforces.

It complements `/code-review` (the built-in diff reviewer): where `/code-review`
finds correctness bugs in a change, `/review:identify-critical` decides *which
code is important enough to require formal discharge*.

## Why this is a separate command

`/code-review` is a Claude Code **built-in skill** with no editable repo file, so
the mission-critical scan is realized here in the repo's review tooling rather
than by modifying `/code-review`. The same capability, owned where it can be
versioned and tested.

## Usage

The command drives a deterministic scanner:

```bash
"scripts/cbc-identify-critical.sh" [--base <ref>] [--config <path>] [--json]
```

## How it scores

A file is a **candidate** only if it matches a rule in
`scripts/lib/cbc-critical-patterns.jsonc` (sensitive extension, path
segment, or basename). Git **churn** (commits touching the file) and file
**size** (LOC) then refine the proposed `cbc-weight`:

```
score  = risk (1-3, from the matched rule)
       + churn_bonus (+2 high tier / +1 mid tier)
       + size_bonus  (+2 high tier / +1 mid tier)
weight = high | medium | low   (by score thresholds in the config)
```

Files already tagged `cbc=mandatory` are excluded.

## Output (proposal only)

The command **never writes `.gitattributes`**. It prints candidates and
ready-to-paste lines for a human to review and commit:

```
Proposed CbC-mandatory tags (2 candidate(s)):
(review and append accepted lines to .gitattributes; nothing is written automatically)

  high    src/consensus/vote.rs    (risk=3 churn=12 loc=420  consensus / safety-critical)
  medium  contracts/escrow.move    (risk=3 churn=2  loc=88   smart-contract code)

Proposed .gitattributes additions:
  src/consensus/vote.rs   cbc=mandatory cbc-weight=high
  contracts/escrow.move   cbc=mandatory cbc-weight=medium
```

Use `--json` for a machine-readable array (`{path, weight, score, risk, churn, loc, reason}`).

## Workflow

1. Run `/review:identify-critical` (optionally `--base <ref>` to scope to a change).
2. Review the proposed tags; edit `scripts/lib/cbc-critical-patterns.jsonc`
   if the heuristics over- or under-reach.
3. Append the accepted lines to `.gitattributes` and commit.
4. `/cbc:main identify` (or legacy `/cbc identify`) then resolves those tags;
   `/cbc:verify verify` / `/cbc:verify discharge` enforce them at the gate.

## Related

- `/cbc:main` and `/cbc:verify` — identify / verify / discharge against the tags this command proposes
- `/code-review` — built-in diff correctness review (runs before the gate)
- Design: `docs/designs/cbc-skill.md` (Assisted identification)

## Files

- **Command**: `AItools/plugins/review/commands/identify-critical.md` (this file)
- **Scanner**: `scripts/cbc-identify-critical.sh`
- **Config**: `scripts/lib/cbc-critical-patterns.jsonc`
- **Tests**: `AItools/tests/test-cbc-identify-critical.sh`
