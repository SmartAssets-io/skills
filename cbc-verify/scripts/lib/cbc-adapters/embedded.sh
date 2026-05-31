#!/usr/bin/env bash
#
# embedded.sh - assertion/design-for-verification CbC adapter for smart contracts
# and systems code with embedded requires/ensures. The prover is selected via
# CBC_PROVER (e.g. move, verus, dafny) and must be on PATH. Availability-gated:
# when no prover is configured/installed, verification is reported as
# unavailable (exit 3) rather than silently passing.
#
# Part of /cbc (EPIC-025). See docs/designs/cbc-skill.md.

cbc_adapter_name() { echo "embedded"; }

cbc_adapter_available() {
    local prover="${CBC_PROVER:-}"
    [[ -n "$prover" ]] && command -v "$prover" >/dev/null 2>&1
}

cbc_adapter_verify() {
    local artifact="$1" out="$3"
    local prover="${CBC_PROVER:-}"
    if [[ -z "$prover" ]] || ! command -v "$prover" >/dev/null 2>&1; then
        jq -n '{kind:"error", ref:null, counterexample:null, detail:"embedded: prover not available (set CBC_PROVER to an installed prover)"}' > "$out"
        return 3
    fi
    local log rc=0
    log=$("$prover" "$artifact" 2>&1) || rc=$?
    if [[ $rc -eq 0 ]]; then
        jq -n --arg ref "$prover" '{kind:"discharged-assertions", ref:$ref, counterexample:null, detail:"assertions discharged by prover"}' > "$out"
        return 0
    fi
    jq -n --arg ce "$log" '{kind:"counterexample", ref:null, counterexample:$ce, detail:"prover refuted"}' > "$out"
    return 2
}
