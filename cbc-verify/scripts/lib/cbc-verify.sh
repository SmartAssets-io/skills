#!/usr/bin/env bash
#
# cbc-verify.sh - run a verifier adapter to discharge an artifact's claim, then
# record the result in the evidence ledger. Variant-agnostic: it selects a
# pluggable adapter (mock / agentic / embedded), calls the adapter contract, and
# assembles the full ledger record. Part of /cbc (EPIC-025).
#
# See docs/designs/cbc-skill.md.

[[ -n "${_CBC_VERIFY_SH_LOADED:-}" ]] && return 0
_CBC_VERIFY_SH_LOADED=1

_CBC_VERIFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cbc-ledger.sh
source "$_CBC_VERIFY_DIR/cbc-ledger.sh"

# cbc verify <artifact> [--adapter NAME] [--claim PATH] [--prover NAME]
cbc_verify() {
    local artifact="" adapter="${CBC_ADAPTER:-agentic}" claim_file=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --adapter) adapter="${2:-}"; shift 2 || true ;;
            --claim)   claim_file="${2:-}"; shift 2 || true ;;
            --prover)  export CBC_PROVER="${2:-}"; shift 2 || true ;;
            -*)        echo "cbc verify: unknown option '$1'" >&2; return 3 ;;
            *)         [[ -z "$artifact" ]] && artifact="$1"; shift ;;
        esac
    done

    [[ -n "$artifact" ]] || { echo "cbc verify: artifact required" >&2; return 3; }
    [[ -f "$artifact" ]] || { echo "cbc verify: artifact not found: $artifact" >&2; return 1; }

    local adapter_file="$_CBC_VERIFY_DIR/cbc-adapters/${adapter}.sh"
    [[ -f "$adapter_file" ]] || { echo "cbc verify: unknown adapter '$adapter'" >&2; return 3; }
    # shellcheck source=/dev/null
    source "$adapter_file"

    if ! cbc_adapter_available; then
        echo "cbc verify: adapter '$adapter' unavailable (missing toolchain/keys); nothing recorded" >&2
        return 3
    fi

    local claim="" commit evidence_tmp rc=0
    [[ -n "$claim_file" && -f "$claim_file" ]] && claim="$(cat "$claim_file")"
    commit="$(git rev-parse --short HEAD 2>/dev/null || echo uncommitted)"
    evidence_tmp="$(mktemp)"

    cbc_adapter_verify "$artifact" "$claim_file" "$evidence_tmp" || rc=$?
    local evidence; evidence="$(cat "$evidence_tmp" 2>/dev/null)"; rm -f "$evidence_tmp"
    [[ -z "$evidence" ]] && evidence='{"kind":"error","ref":null,"counterexample":null,"detail":"adapter produced no evidence"}'

    local status
    case "$rc" in
        0) status="discharged" ;;
        2) status="refuted" ;;
        *) status="error" ;;
    esac

    local path
    path="$(cbc_ledger_write "$artifact" "$commit" "$claim" "$(cbc_adapter_name)" "$status" "$evidence")"

    echo "cbc verify: $artifact -> $status (adapter: $adapter)"
    echo "  evidence: $path"
    [[ "$status" == "refuted" ]] && echo "  refuted - loop back to synthesis; merge stays gated."
    return "$rc"
}

# cbc status [<artifact>]
cbc_status() {
    local artifact="${1:-}"
    if [[ -n "$artifact" ]]; then
        echo "$artifact: $(cbc_ledger_status "$artifact")"
        return 0
    fi
    local dir; dir="$(cbc_ledger_dir)"
    if [[ ! -d "$dir" ]]; then
        echo "No evidence ledger yet ($dir)."
        return 0
    fi
    local f any=0
    for f in "$dir"/*.md; do
        [[ -e "$f" ]] || continue
        any=1
        local st; st="$(awk '/^```json/{f=1;next} /^```/{f=0} f' "$f" | jq -r '.status // "?"' 2>/dev/null)"
        local p;  p="$(awk '/^```json/{f=1;next} /^```/{f=0} f' "$f" | jq -r '.artifact.path // "?"' 2>/dev/null)"
        printf '  %-12s %s\n' "$st" "$p"
    done
    [[ "$any" -eq 0 ]] && echo "No evidence records in $dir."
    return 0
}
