---
name: cbc-verify
description: Verify, inspect, discharge, or waive CbC claims for cbc=mandatory artifacts using the evidence ledger
license: SSL
---

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/cbc:verify <action> [arguments]

Actions:
  verify    <artifact> [--adapter mock|agentic|embedded] [--claim PATH] [--prover NAME]
  status    [<artifact>]
  discharge [--scope diff|epic <EID>] [--files "a b c"] [--strict] [--json]
  waive     <artifact> --reason TEXT

Pi: /skill:cbc-verify or /cbc-verify
```

---

# Verify and Discharge CbC Claims

`/cbc:verify` is the focused verification/gate skill for CbC-tagged artifacts.
It covers the operational subcommands that write or inspect evidence:
`verify`, `status`, `discharge`, and `waive`.

Use `/cbc:review` or `/skill:cbc-review` first to propose `cbc=mandatory` tags,
then `/cbc:scaffold` if you want deterministic scaffold/tag application. Use
this skill after claims/specifications exist and tagged artifacts need discharge.

## Backing script

```bash
"scripts/cbc.sh" <verify|status|discharge|waive> [arguments]
```

## Actions

### verify

```bash
"scripts/cbc.sh" verify src/consensus/vote.rs \
  --adapter agentic --claim docs/claims/vote-safety.md
```

Runs the selected adapter and writes a Markdown evidence record under
`docs/cbc-evidence/`.

### status

```bash
"scripts/cbc.sh" status
"scripts/cbc.sh" status src/consensus/vote.rs
```

Shows ledger state for all records or a single artifact.

### discharge

```bash
"scripts/cbc.sh" discharge --scope diff --strict
```

Checks that every in-scope `cbc=mandatory` artifact has `discharged` or
`waived` evidence. `--strict` exits non-zero when gaps remain.

### waive

```bash
"scripts/cbc.sh" waive src/consensus/vote.rs \
  --reason "Manually discharged in external audit AUD-014"
```

Records an explicit waiver with rationale. Waivers satisfy the gate but remain
visible in the ledger.

## Safety

`verify` and `waive` write evidence records. `discharge` may block completion in
strict mode. Always inspect the resulting evidence and gate output before
marking a task complete.
