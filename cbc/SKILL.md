---
name: cbc
description: Identify mission-critical (CbC-mandatory) code in a change, discharge its correctness claims through a pluggable verifier, record the evidence, and gate completion on undischarged claims
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
/cbc:main <subcommand> [arguments]
/cbc <subcommand> [arguments]   # legacy flat alias

Subcommands:
  attributes snapshot|lint [--cached]
  attributes compare <snapshot> [--cached]
                          Inspect hierarchical policy through Git.
  identify  [--scope diff|epic EID|flow FID]
                          List CbC-mandatory files in scope (default: working diff).
  claim-set <artifact> --claim-id ID [--claim-id ID ...]
                          Declare expected independent claims without removing claims.
  verify    <artifact> [--claim-id ID] [--adapter mock|agentic|embedded] [--claim PATH] [--prover NAME]
                          Run the verifier adapter to discharge the artifact's
                          claim; write an evidence record to docs/cbc-evidence/.
  discharge [--scope diff|epic EID|flow FID] [--strict] [--json]
                          Gate: every in-scope mandatory artifact has a
                          discharged or waived record. --strict exits non-zero on gaps.
  acceptance-payload <artifact> [--claim-id ID]
  accept    <artifact> [--claim-id ID] --approval PATH --signature PATH
  waive     <artifact> [--claim-id ID] [--claim PATH] --reason TEXT
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

`/cbc:main` (legacy alias: `/cbc`) coordinates verification of mission-critical changes.
It identifies mandatory files and sends their claims to a verifier adapter.
It records evidence and blocks completion when verification or required acceptance is missing.
Explicit waivers need a recorded rationale and do not bypass required acceptance.

It implements [FLOW-009](../../docs/User-Flows.md) and complements `/code-review`:
review (FLOW-009 step 4) catches correctness bugs *before* the gate.
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
gap for any mandatory artifact lacking verification or required maintainer acceptance.
Completion refuses this gap even without `--strict` or with `--force`.

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
| `cbc-acceptance` | `required` | Path also requires current signed maintainer acceptance |
| `cbc-weight` | `low` \| `medium` (default) \| `high` | risk x value x cognitive weighting |
| `cbc-evidence` | Repository-relative directory | Per-artifact evidence location |

> Tags are authored manually or **proposed by `/code-review`'s mission-critical
> scan** (EPIC-025 TODO-025-006), which scores files by risk x value x
> cognitive weight; a human ratifies before commit. `cbc identify` only
> *reads* the resulting tags.

### attributes

Git resolves attributes from root and nested `.gitattributes` files.
Owner declarations route new proposals but do not define verification obligations.

```bash
"scripts/cbc.sh" attributes snapshot > before.json
"scripts/cbc.sh" attributes compare before.json
"scripts/cbc.sh" attributes lint
```

Use matching `--cached` options to compare index policy instead of working-tree policy.
Snapshots contain every tracked path and all effective attributes, including unrelated formatting and filter attributes.
Comparison exits `4` when values or tracked paths change.
Lint exits `3` for invalid effective acceptance policy.
Other diagnostics are advisory and do not replace Git precedence.

The scanner emits anchored exact-file patterns and an `attributes_file` destination for each proposal.
Configure optional `attribute_owners` in the scanner configuration.
Use `--root-only` for root authoring or `--acceptance-required` for new mandatory-and-acceptance rules.
Inherited acceptance remains valid without a same-line rule.
The writer does not rewrite existing rules or evidence.

Keep root-only attribute macros and repository-wide rules at the root.
Before policy redistribution, save a snapshot.
After redistribution, compare both working-tree and index snapshots.
Equivalent policy moves retain approval bindings.
Source moves need fresh verification and required acceptance.

Per-artifact evidence routing uses `cbc-evidence`, then `CBC_EVIDENCE_DIR`, then `docs/cbc-evidence`.
Invalid routing fails instead of selecting another directory.
An explicit `-cbc-evidence` is invalid.
Use `!cbc-evidence` to restore environment or default fallback selection.
Enforcement against ambient overrides remains deferred.

### Evidence directories

Place `cbc-evidence=<directory>` in the artifact's owner policy file.
Git resolves inherited and overridden values.
Attribute values must be nonempty relative directory strings inside the worktree.
Reject Boolean values, escapes, unsafe symlinks, and Git metadata destinations.
The reserved Git results `set` and `unset` are not directory values.
Use `./set` or `./unset` if a directory needs one of those names.

Legacy absolute `CBC_EVIDENCE_DIR` overrides work only inside the worktree.
All affected commands use the same artifact directory, including formal reports and acceptance imports.
Summary status reports active ledgers across the selected directories.
Lint validates both worktree and indexed attribute policy.
Identification validates every candidate path before it selects mandatory paths.
Invalid routing on a non-mandatory candidate therefore stops identification.

Ledger filenames and artifact IDs use normalized repository-relative paths.
Equivalent absolute paths and internal `..` components select the same ledger.
A `./` prefix already produces the same name.
Older ledgers created from noncanonical arguments do not move automatically.
Preserve their bytes and review an explicit migration when necessary.

A routing change does not migrate existing evidence.
Preserve ledger bytes, signed acceptance envelopes, history, and referenced reports during an explicit move.
Keep referenced reports available at their recorded paths.
Do not rewrite signed records or create acceptance on another person's behalf.

Several JSON records require explicit claim IDs and a declared inventory.
Missing or duplicate IDs, missing inventory, and mixed artifact paths produce one `invalid_record` gap.
Do not select a favorable record or remove an independent claim.
Consumer owners must preserve original records and signatures during an explicit migration.

### claim-set

Declare every expected independent claim before named verification.
Keep `--claim-id` separate from `--claim`, which names a claim document.

```bash
"scripts/cbc.sh" claim-set src/consensus/vote.rs \
  --claim-id VOTE-SAFETY --claim-id VOTE-LIVENESS
"scripts/cbc.sh" verify src/consensus/vote.rs \
  --claim-id VOTE-SAFETY --claim docs/claims/vote-safety.md --adapter agentic
```

The adjacent `<artifact-id>.claims.json` file uses schema `cbc-claim-set/v1`.
Its `artifact` identifies the repository-relative source, and `claim_ids` lists the expected IDs.
IDs are case-sensitive ASCII identifiers with at most 128 characters.
Start an ID with a letter or digit.
Use only letters, digits, periods, underscores, and hyphens after the initial character.

Declaration can add IDs but cannot remove existing IDs.
A missing declared record remains a gap.

Named `verify`, `waive`, `accept`, and `acceptance-payload` operations require `--claim-id`.
Unknown or ambiguous selections fail before a verifier runs or evidence changes.
Updates preserve other claim blocks and ledger prose byte-for-byte.
A new named waiver requires `--claim PATH` unless the selected record already supplies its claim.
If the claim document changed, supply `--claim PATH` to record the new waiver explicitly.

Record writes and acceptance imports acquire the shared ledger lock before selecting legacy or named behavior.
Both operations read the current membership under that lock.

New named records use schema `cbc-claim/v1` and require their inventory even when only one record remains.
A surviving `.claims` directory or archived inventory also identifies a named collection.
Stripping record fields does not restore legacy behavior while named metadata survives.
Restore a missing inventory before changing membership when named metadata survives.
Single legacy records without named metadata retain their current meaning and v1 signatures.
The tooling does not infer IDs, combine independent claims, or migrate evidence automatically.

The inventory is reviewed policy.
Direct inventory changes need an independent review.
Filesystem owners can still replace policy outside these commands.

Evidence writes require POSIX filesystem locks, with a five-second acquisition limit.
Add this rule to the consumer's root `.gitignore`:

```gitignore
*.claims.lock
```

The rule excludes untracked lock files, not files already tracked by Git.
Consumer owners must separately review changes to tracked lock files.
Do not delete a lock file while commands run.

### Consumer migration

Migration is manual, consumer-owned, and independently reviewed.
The tooling provides no migration command.
Keep changes on the consumer's approved adoption branch.

1. Preserve original ledgers, inventories, acceptance envelopes, reports, and history before you edit evidence.
2. Assign an explicit `claim_id` and schema `cbc-claim/v1` to each independent record.
3. Place every record in the artifact's selected ledger without combining claim meanings.
4. Obtain an independent review of the record mapping and preserved originals.
5. Declare the complete ID set with `claim-set`.
6. Reverify claims that lack current input bindings.
7. Obtain required v2 acceptance for each current claim.
8. Run strict discharge for all affected artifacts.

Do not invent input bindings, verification results, or approval fields.
Do not change claim text, statuses, evidence, or waiver reasons merely to remove a gap.

### Tooling revision

For consumer acceptance or migration runs, use an immutable checkout of the approved tooling commit or release tag.
Confirm that the tooling checkout has no tracked changes.
Record the full tooling commit ID with verification results.
A recorded pin does not constrain a shared checkout on `dev`.
Consumer owners configure invocation paths and confirm the executed revision.
This tooling change does not switch consumer checkouts automatically.

### verify

Run a verifier adapter to discharge the artifact's claim and write an evidence
record. The adapter is pluggable. Selection is variant-agnostic.

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
| `agentic` | Default. LLM proposes, verifier discharges. Counterexamples loop back | ProofWright, Lean Copilot (+ `lib/llm-client.sh`) |
| `embedded` | Smart contracts / systems code with embedded `requires`/`ensures`. Dafny/Z3 runs prefer `pi-formal-verify` for JSON evidence | Move Prover, Verus, Dafny, Z3, `pi-formal-verify` |

### discharge

Gate check across the scope. Exits `0` when every in-scope mandatory artifact
has a `discharged` or `waived` evidence record. `--strict` exits non-zero when
any gap remains. This is the read side of the gate that `/task-complete` also
consults.

Every declared claim must pass, including required acceptance for waived claims.
Artifact results include per-claim results and count each artifact once.
The aggregate status uses this precedence:

```text
invalid_record > refuted > error > pending > none > acceptance_required > waived > discharged
```

The aggregate reason never removes another claim's gap.

```bash
"scripts/cbc.sh" discharge --scope epic EPIC-025 --strict
```

## Required maintainer acceptance

Use `cbc=mandatory cbc-acceptance=required` when discharge also requires maintainer approval.
Only `required` and an unspecified acceptance attribute are valid.
A required acceptance attribute without `cbc=mandatory` is a policy error.

Verification and approval are separate actions.
Neither a verifier result, tool permission, waiver, nor agent review establishes maintainer acceptance.
Status checks and verifier runs do not require approval.

The operator configures `cbc.acceptanceAllowedSigners` in local Git configuration.
The value must name an absolute OpenSSH allowed-signers file outside the worktree.
The operator must protect this file and Git configuration from unauthorized changes.
Agents must not enroll trusted keys, access maintainer private keys, or sign approvals.
This trust boundary does not protect against an operator who can replace authorized keys.

Each approval requires an authorized SSH signature in the `cbc-acceptance` namespace.
The signature identity must match `accepted_by` and an explicit principal in the allowed-signers file.
Wildcard principals cannot authorize acceptance.
The signed JSON includes `approved_at`, `approval_ref`, the artifact path, and source, claim, and evidence bindings.
`approval_ref` identifies the maintainer's review record.
The signature authenticates that reference but does not fetch an external review service.

Run commands from the repository root.
Source and external claim files must remain inside the repository.
Python 3.9 or later and OpenSSH with SSH signature support are required.

1. Run verification with the applicable claim.
2. Export the unsigned acceptance payload.
3. Ask the authorized maintainer to inspect the source, claim, and evidence.
4. Ask the maintainer to fill `accepted_by`, `approved_at`, and `approval_ref`.
5. Ask the maintainer to sign the exact approval file.
6. Import the approval and signature.
7. Run the strict discharge gate.

```bash
"scripts/cbc.sh" acceptance-payload src/example.rs > approval.json
# The maintainer completes the fields and signs this file independently:
ssh-keygen -Y sign -f /path/to/maintainer-key -n cbc-acceptance approval.json
"scripts/cbc.sh" accept src/example.rs \
  --approval approval.json --signature approval.json.sig
"scripts/cbc.sh" discharge --files src/example.rs --strict
```

Legacy v1 acceptance resides in `<artifact-id>.acceptance.json` beside the evidence ledger.
Its evidence digest covers the complete ledger and the recorded hashes of referenced evidence files.
It excludes the acceptance file to avoid a self-referential digest.
Changes to source, claim, verification records, or referenced evidence invalidate that acceptance.

Named collections use per-claim `cbc-acceptance/v2` approvals in the same SSH signature namespace.
Store each envelope under `<artifact-id>.claims/<sha256-of-claim-id>.acceptance.json`.
The payload binds the claim ID, source, claim document, canonical selected record, referenced reports, and normalized inventory.
Updates to another record preserve an unchanged claim's approval when membership stays unchanged.
Membership changes invalidate all earlier v2 approvals.

A new verification run requires new approval for the selected claim, even when source bytes remain unchanged.
Never reinterpret a v1 signature as per-claim acceptance.

Replacement records preserve earlier bytes under `history/`.
Formal reports use unique filenames.
Historical records without input bindings remain readable but cannot satisfy required acceptance.
Run verification and obtain a signed approval instead of inventing approval metadata.

Waivers still require signed acceptance on required paths.
Missing or stale acceptance produces an `acceptance_required` gate status.
Malformed policy produces a policy error.
Completion reports `undischarged_cbc_claim` and refuses completion, including with `--force`.
Informational discharge without `--strict` can report gaps with exit zero.
Never use that exit code as permission to complete a mandatory task.

Claude Code and Pi use the same `cbc_gate_status` implementation.
Generate Pi resources from the canonical commands and manifest.

### waive

Record an explicit waiver with rationale against an artifact's claim. Waived
artifacts satisfy the verification requirement but do not bypass required acceptance.

```bash
"scripts/cbc.sh" waive contracts/escrow.move \
    --reason "Discharged manually in audit AUD-014; prover lacks Move generics support"
```

### status

Show one artifact's status or a summary across the active evidence directories.

```bash
"scripts/cbc.sh" status contracts/escrow.move
"scripts/cbc.sh" status
```

## Evidence records

Each artifact has one Markdown ledger in its selected evidence directory.
The ledger contains one legacy JSON record or one named JSON record for each declared claim.
Formal verification writes backend JSON under `formal/` in that directory.
The ledger references each backend report.

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
| `--claim-id ID` | Stable selector for a named claim or a repeated inventory member |
| `--claim PATH` | Claim document for verification or a new named waiver |
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
| 3 | Invalid policy or selection, unavailable verifier, or command error |
| 4 | Strict discharge gaps or invalid acceptance |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `NO_COLOR` | Disable colored output |
| `CBC_EVIDENCE_DIR` | Override default `docs/cbc-evidence/` path |
| `CBC_ADAPTER` | Default adapter when `--adapter` is omitted |
| `CBC_PROVER` | Embedded adapter prover when `--prover` is omitted (`move`, `verus`, `dafny`, `z3`, or `pi-formal-verify`) |
| `PI_FORMAL_VERIFY_CLI` | Optional absolute path to the `pi-formal-verify` CLI |
| `PI_FORMAL_VERIFY_PATH` | Optional path to a `pi-formal-verify` checkout. Otherwise CbC searches PATH, the current git root, and the standard sibling workspace location |

## Formal verification bridge

Install the sibling `pi-formal-verify` Pi package during Smart Assets Pi setup for Dafny/Z3 tools and formal evidence generation:

```bash
scripts/setup-pi.sh --local --with-formal-verify
# or:
scripts/setup-pi.sh --local --formal-verify /path/to/pi-formal-verify
```

For Dafny or Z3 with `--adapter embedded`, CbC prefers the `pi-formal-verify` CLI.
It searches `PI_FORMAL_VERIFY_CLI`, `PI_FORMAL_VERIFY_PATH`, PATH, and the standard sibling workspace layout.
It writes formal JSON under `formal/` in the artifact's evidence directory.
The ledger references that report.
A `discharged` formal status satisfies verification, but required acceptance remains separate.
`refuted`, `unknown`, or `tool_error` remain not discharged.

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
