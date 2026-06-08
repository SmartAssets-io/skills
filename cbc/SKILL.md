---
name: cbc
description: Identify mission-critical (CbC-mandatory) code in a change, discharge its correctness claims through a pluggable verifier, record the evidence, and gate completion on undischarged claims
license: SSL
---

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/cbc:main <subcommand> [arguments]
/cbc <subcommand> [arguments]   # legacy flat alias

Subcommands:
  identify  [--scope diff|epic EID|flow FID]
                          List CbC-mandatory files in scope (default: working diff).
  verify    <artifact> [--adapter mock|agentic|embedded] [--claim PATH] [--prover NAME]
                          Run the verifier adapter to discharge the artifact's
                          claim; write an evidence record to docs/cbc-evidence/.
  discharge [--scope diff|epic EID|flow FID] [--strict] [--json]
                          Gate: every in-scope mandatory artifact has a
                          discharged or waived record. --strict exits non-zero on gaps.
  waive     <artifact> --reason TEXT
                          Record an explicit waiver with rationale against a claim.
  status    [<artifact>] [--json]
                          Show ledger state for an artifact, or a ledger summary.

Treats AI synthesis as a claim discharged against a specification. CbC-mandatory
code is tagged via git attributes; evidence lives in docs/cbc-evidence/.

Focused skills: /cbc:review, /cbc:scaffold, /cbc:verify. Pi aliases:
/skill:cbc, /skill:cbc-review, /skill:cbc-scaffold, /skill:cbc-verify.
```

---

> **Status: implemented (EPIC-025).** `identify`, `verify`, `status`,
> `discharge`, and `waive` are wired in `scripts/cbc.sh` and its
> libraries. The `agentic`/`embedded` verifier adapters are real but
> **availability-gated** — they report unavailable (exit 3) unless an LLM key
> and/or a prover (`CBC_PROVER`) are present; the `mock` adapter is for tests.
> See [docs/designs/cbc-skill.md](../../docs/designs/cbc-skill.md) for the full
> design and rationale.

# CbC Mission-Critical Code Verification

`/cbc:main` (legacy alias: `/cbc`) is the umbrella CbC skill the Agentic CbC Engineer tier uses to **prove** changes
to mission-critical code rather than eyeball them. It identifies CbC-mandatory
files in a change, discharges their correctness claims through a pluggable
verifier adapter, records auditable **evidence**, and gates completion on any
undischarged claim unless explicitly waived with a recorded rationale.

It implements [FLOW-009](../../docs/User-Flows.md) and complements `/code-review`:
review (FLOW-009 step 4) catches correctness bugs *before* the gate;
`/cbc:verify` discharges the formal claims.

## Usage

```bash
"scripts/cbc.sh" <subcommand> [arguments]
```

For focused entry points, use:

- `/cbc:review` / `/skill:cbc-review` — scan for mission-critical files and propose tags.
- `/cbc:scaffold` / `/skill:cbc-scaffold` — initialize CbC directories and apply scanner-proposed tags.
- `/cbc:verify` / `/skill:cbc-verify` — verify/status/discharge/waive evidence workflows.

## Mental model

```
Identify  ->  Claim  ->  Synthesis  ->  Review  ->  Verification  ->  Evidence  ->  Discharge gate
(/cbc:main identify)                  (/code-review)  (/cbc:verify)   (ledger)     (/cbc:verify discharge)
```

CbC-mandatory code is marked with **git attributes** (no separate registry).
Each verification writes an **evidence record** under `docs/cbc-evidence/`.
Completion is **gated**: `/task-complete` reports an `undischarged_cbc_claim`
gap for any mandatory artifact lacking a `discharged`/`waived` record.

## Subcommands

### identify

List the CbC-mandatory files in scope. Resolves the in-scope file set (working
diff by default; the epic/flow `files:` for `--scope epic|flow`) and selects
those carrying the `cbc=mandatory` git attribute.

```bash
"scripts/cbc.sh" identify
"scripts/cbc.sh" identify --scope epic EPIC-025
```

Tagging lives in `.gitattributes`:

```gitattributes
contracts/**          cbc=mandatory
src/consensus/**.rs   cbc=mandatory cbc-weight=high
```

| Attribute | Values | Meaning |
|-----------|--------|---------|
| `cbc` | `mandatory` | Path requires discharge before completion |
| `cbc-weight` | `low` \| `medium` (default) \| `high` | risk x value x cognitive weighting |

> Tags are authored manually or **proposed by `/code-review`'s mission-critical
> scan** (EPIC-025 TODO-025-006), which scores files by risk x value x
> cognitive weight; a human ratifies before commit. `cbc identify` only
> *reads* the resulting tags.

### verify

Run a verifier adapter to discharge the artifact's claim and write an evidence
record. The adapter is pluggable; selection is variant-agnostic.

```bash
# Agentic (reference): LLM proposes annotations/proof, verifier discharges
"scripts/cbc.sh" verify src/consensus/vote.rs \
    --adapter agentic --claim docs/claims/vote-safety.md

# Embedded (smart contracts): prover consumes requires/ensures in the source
"scripts/cbc.sh" verify contracts/escrow.move \
    --adapter embedded --prover move

# Embedded via pi-formal-verify: Dafny/Z3 evidence is captured as JSON and linked
"scripts/cbc.sh" verify specs/invariant.smt2 \
    --adapter embedded --prover z3 --claim docs/claims/invariant.md
```

| Adapter | Use | Reference tools |
|---------|-----|-----------------|
| `agentic` | Default. LLM proposes, verifier discharges; counterexamples loop back | ProofWright, Lean Copilot (+ `lib/llm-client.sh`) |
| `embedded` | Smart contracts / systems code with embedded `requires`/`ensures`; Dafny/Z3 runs prefer `pi-formal-verify` for JSON evidence | Move Prover, Verus, Dafny, Z3, `pi-formal-verify` |

### discharge

Gate check across the scope. Exits `0` when every in-scope mandatory artifact
has a `discharged` or `waived` evidence record; `--strict` exits non-zero when
any gap remains. This is the read side of the gate that `/task-complete` also
consults.

```bash
"scripts/cbc.sh" discharge --scope epic EPIC-025 --strict
```

### waive

Record an explicit waiver with rationale against an artifact's claim. Waived
artifacts satisfy the gate but remain visible in the ledger.

```bash
"scripts/cbc.sh" waive contracts/escrow.move \
    --reason "Discharged manually in audit AUD-014; prover lacks Move generics support"
```

### status

Show the ledger record for an artifact, or a summary across `docs/cbc-evidence/`.

```bash
"scripts/cbc.sh" status contracts/escrow.move
"scripts/cbc.sh" status --json
```

## Evidence records

One Markdown file per artifact under `docs/cbc-evidence/`, with an embedded
machine-readable JSON block. When the embedded adapter uses `pi-formal-verify`
for Dafny or Z3, it also writes backend evidence JSON under
`docs/cbc-evidence/formal/` and links it from the Markdown ledger record.

```json
{
  "artifact": { "path": "contracts/escrow.move", "commit": "44eeace", "id": "contracts-escrow-move" },
  "claim": "escrow release requires both signer approvals (invariant: balance >= 0)",
  "adapter": "embedded",
  "status": "discharged",
  "evidence": { "kind": "discharged-assertions", "ref": "move-prover-report.txt", "counterexample": null },
  "waiver": null,
  "verified_at": "2026-05-25T00:00:00Z"
}
```

`status` is one of `discharged` | `refuted` | `waived` | `pending`.

## Options

| Option | Description |
|--------|-------------|
| `--scope diff\|epic EID\|flow FID` | Selection scope (default: working diff) |
| `--adapter mock\|agentic\|embedded` | Verifier adapter (default: `agentic`; `mock` is test-only) |
| `--claim PATH` | Claim/specification file for `verify` |
| `--prover NAME` | Embedded-adapter prover (e.g. `move`, `verus`, `dafny`, `z3`, `pi-formal-verify`) |
| `--reason TEXT` | Waiver rationale (required for `waive`) |
| `--strict` | `discharge` exits non-zero on any gap |
| `--json` | Machine-readable output |
| `--no-color` | Disable colored output |
| `--help`, `-h` | Show help message |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success / all in-scope claims discharged or waived |
| 1 | Artifact or claim not found |
| 2 | Verification refuted (counterexample recorded) |
| 3 | Adapter/tooling error (verifier unavailable) |
| 4 | Undischarged claims remain (`discharge --strict`) |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `NO_COLOR` | Disable colored output |
| `CBC_EVIDENCE_DIR` | Override default `docs/cbc-evidence/` path |
| `CBC_ADAPTER` | Default adapter when `--adapter` is omitted |
| `CBC_PROVER` | Embedded adapter prover when `--prover` is omitted (`move`, `verus`, `dafny`, `z3`, or `pi-formal-verify`) |
| `PI_FORMAL_VERIFY_CLI` | Optional absolute path to the `pi-formal-verify` CLI |
| `PI_FORMAL_VERIFY_PATH` | Optional path to a `pi-formal-verify` checkout; otherwise CbC searches PATH, the current git root, and the standard sibling workspace location |

## Formal verification bridge

Install the sibling `pi-formal-verify` Pi package during Smart Assets Pi setup for Dafny/Z3 tools and formal evidence generation:

```bash
scripts/setup-pi.sh --local --with-formal-verify
# or:
scripts/setup-pi.sh --local --formal-verify /path/to/pi-formal-verify
```

When `CBC_PROVER=dafny`, `CBC_PROVER=z3`, or `--prover dafny|z3` is used with `--adapter embedded`, CbC prefers the `pi-formal-verify` CLI. It searches `PI_FORMAL_VERIFY_CLI`, `PI_FORMAL_VERIFY_PATH`, PATH, and the standard sibling workspace layout. It writes formal JSON evidence under `docs/cbc-evidence/formal/` and references that file from the CbC ledger record. A `discharged` formal status satisfies the CbC gate; `refuted`, `unknown`, or `tool_error` remain not discharged.

## Related Commands

- `/cbc:review` — CbC-owned mission-critical scanner (proposal-only)
- `/cbc:scaffold` — initializes CbC evidence/claim directories and applies scanner tags
- `/cbc:verify` — focused verify/status/discharge/waive workflows
- `/review:identify-critical` — retained review-genre entry point for the same scanner
- `/code-review` — correctness-bug review of the current diff (runs before the gate)
- `/task-complete` — consults the discharge gate (`undischarged_cbc_claim`)
- `/spec:flow` — FLOW-009 is the flow this skill implements
- `/skill:formal-verify` — provided by the optional `pi-formal-verify` Pi package for direct Dafny/Z3 checks

## Files

- **Design**: `docs/designs/cbc-skill.md`
- **Command**: `AItools/plugins/cbc/commands/main.md` (legacy symlink: `AItools/commands/cbc.md`)
- **Driver**: `scripts/cbc.sh` (EPIC-025, TODO-025-002+)
- **Libraries**: `scripts/lib/cbc-identify.sh`, `cbc-verify.sh`, `cbc-ledger.sh`, `cbc-adapters/*.sh`
- **Evidence ledger**: `docs/cbc-evidence/`
