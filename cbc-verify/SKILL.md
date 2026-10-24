---
name: cbc-verify
description: Verify, inspect, discharge, or waive CbC claims for cbc=mandatory artifacts using the evidence ledger
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
/cbc:verify <action> [arguments]

Actions:
  claim-set <artifact> --claim-id ID [--claim-id ID ...]
  verify    <artifact> [--claim-id ID] [--adapter mock|agentic|embedded] [--claim PATH] [--prover NAME]
  status    [<artifact>] [--json]
  discharge [--scope diff|epic <EID>] [--files "a b c"] [--strict] [--json]
  acceptance-payload <artifact> [--claim-id ID]
  accept    <artifact> [--claim-id ID] --approval PATH --signature PATH
  waive     <artifact> [--claim-id ID] [--claim PATH] --reason TEXT

Pi: /skill:cbc-verify or /cbc-verify
```

---

# Verify and Discharge CbC Claims

`/cbc:verify` is the focused verification/gate skill for CbC-tagged artifacts.
It covers the operational subcommands that write or inspect evidence:
`claim-set`, `verify`, `status`, `discharge`, `waive`, `acceptance-payload`, and `accept`.

Use `/cbc:review` or `/skill:cbc-review` first to propose `cbc=mandatory` tags,
then `/cbc:scaffold` if you want deterministic scaffold/tag application. Use
this skill after claims/specifications exist and tagged artifacts need discharge.

## Backing script

```bash
"scripts/cbc.sh" <claim-set|verify|status|discharge|waive|acceptance-payload|accept> [arguments]
```

Use an immutable tooling checkout for consumer acceptance or migration runs.
Confirm that the tooling checkout has no tracked changes.
Record its full commit ID.
A shared `dev` checkout does not enforce a recorded pin.
Consumer owners configure and verify their invocation paths.

## Actions

### verify

```bash
"scripts/cbc.sh" verify src/consensus/vote.rs \
  --adapter agentic --claim docs/claims/vote-safety.md

"scripts/cbc.sh" verify specs/invariant.smt2 \
  --adapter embedded --prover z3 --claim docs/claims/invariant.md
```

The selected adapter writes a Markdown ledger in the artifact's evidence directory.
Select `cbc-evidence` through Git before `CBC_EVIDENCE_DIR`, then use `docs/cbc-evidence` as the default.
Invalid directories fail closed instead of selecting another directory.
An explicit `-cbc-evidence` is invalid.
Use `!cbc-evidence` to restore environment or default fallback selection.

Attribute directories must be relative and remain inside the worktree, including existing symlinks.
Legacy absolute environment overrides remain valid only inside the worktree.

The optional `pi-formal-verify` CLI writes backend reports under `formal/` in the same selected directory.
Changing routing does not migrate records automatically.
Preserve ledger bytes, signed acceptance envelopes, history, and referenced reports during a separate move.
Several JSON records require stable claim IDs and a declared inventory.
Unidentified records, duplicate IDs, and missing inventory produce one `invalid_record` gap.
Consumer owners must preserve historical bytes and signatures during an explicit migration.

Ledger names and artifact IDs use normalized repository-relative paths.
Equivalent absolute paths and internal `..` components select the same ledger.
Older noncanonical ledgers do not move automatically.

### claim-set

Declare all expected IDs before named verification.

```bash
"scripts/cbc.sh" claim-set src/consensus/vote.rs \
  --claim-id VOTE-SAFETY --claim-id VOTE-LIVENESS
"scripts/cbc.sh" verify src/consensus/vote.rs \
  --claim-id VOTE-SAFETY --claim docs/claims/vote-safety.md --adapter agentic
```

The adjacent `<artifact-id>.claims.json` file declares the artifact and expected IDs with schema `cbc-claim-set/v1`.
IDs are case-sensitive ASCII identifiers with at most 128 characters.
Start an ID with a letter or digit.
Use only letters, digits, periods, underscores, and hyphens after the initial character.

Declaration can add IDs but cannot remove existing IDs.
A missing declared record remains a gap.

Named `verify`, `waive`, `accept`, and `acceptance-payload` operations require `--claim-id`.
Keep `--claim` for a claim-document path.
Unknown or ambiguous selections fail before a verifier runs or evidence changes.
Updates preserve other records and prose byte-for-byte.
A new named waiver requires a claim document unless the selected record already supplies its claim.
If the claim document changed, supply `--claim PATH` to record the new waiver explicitly.

Record writes and acceptance imports acquire the shared ledger lock before selecting legacy or named behavior.
Both operations read the current membership under that lock.

New named records use `cbc-claim/v1` and always require their inventory.
A surviving `.claims` directory or archived inventory also identifies a named collection.
Stripping record fields does not restore legacy behavior while named metadata survives.
Restore a missing inventory before changing membership when named metadata survives.
Single legacy records without named metadata retain their meaning and v1 signatures.
The tooling does not infer IDs, remove independent claims, or migrate records automatically.

Review direct inventory changes as policy changes.
Filesystem owners can replace policy outside these commands.

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

### status

```bash
"scripts/cbc.sh" status
"scripts/cbc.sh" status src/consensus/vote.rs
```

Show one artifact result with its named claim results.
Use `--json` for structured output from an artifact or a summary.
Status separates verification status from the effective gate status.

### discharge

```bash
"scripts/cbc.sh" discharge --scope diff --strict
```

Checks that every in-scope `cbc=mandatory` artifact has `discharged` or
`waived` evidence. `--strict` exits non-zero when gaps remain.

Every declared claim must pass, including required acceptance for waived claims.
Count each artifact once, even when several claims fail.
The aggregate status uses this precedence:

```text
invalid_record > refuted > error > pending > none > acceptance_required > waived > discharged
```

Keep each claim's reason in the report.

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
Its digest covers the complete ledger and the recorded hashes of referenced evidence files.
It excludes the acceptance file to avoid a self-referential digest.
Changes to source, claim, verification records, or referenced evidence invalidate that acceptance.

Named collections use per-claim `cbc-acceptance/v2` approvals in the same SSH signature namespace.
Store envelopes under `<artifact-id>.claims/<sha256-of-claim-id>.acceptance.json`.
The payload binds the selected claim ID, source, claim document, canonical record, referenced reports, and normalized inventory.
Other record updates preserve an unchanged claim's approval when membership stays unchanged.
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

```bash
"scripts/cbc.sh" waive src/consensus/vote.rs \
  --reason "Manually discharged in external audit AUD-014"
```

Records an explicit waiver with rationale. Required maintainer acceptance still applies.

## Formal verifier bridge

Install `pi-formal-verify` with Smart Assets Pi setup when you want direct Pi
formal-verification tools and the CbC embedded Dafny/Z3 bridge:

```bash
"scripts/setup-pi.sh" --local --with-formal-verify
# or:
"scripts/setup-pi.sh" --local --formal-verify /path/to/pi-formal-verify
```

The embedded adapter searches `PI_FORMAL_VERIFY_CLI`, `PI_FORMAL_VERIFY_PATH`,
then `pi-formal-verify` on PATH, then the current git root and standard sibling
workspace paths. A `discharged` backend status satisfies verification, but required acceptance remains separate.
`refuted`, `unknown`, and `tool_error` do not.

## Safety

`verify` and `waive` write evidence records. `discharge` may block completion in
strict mode. Always inspect the resulting evidence and gate output before
marking a task complete.

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
