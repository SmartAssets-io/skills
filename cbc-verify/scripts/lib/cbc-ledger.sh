#!/usr/bin/env bash
#
# cbc-ledger.sh - read/write the CbC evidence ledger.
#
# One auditable record per artifact under docs/cbc-evidence/ (override with
# CBC_EVIDENCE_DIR): Markdown summary + an embedded machine-readable JSON block.
# Part of the /cbc skill (EPIC-025). See docs/designs/cbc-skill.md.

[[ -n "${_CBC_LEDGER_SH_LOADED:-}" ]] && return 0
_CBC_LEDGER_SH_LOADED=1

cbc_ledger_dir() { echo "${CBC_EVIDENCE_DIR:-docs/cbc-evidence}"; }

# Stable slug for an artifact path: non-alphanumeric -> '-', collapsed, trimmed.
cbc_ledger_slug() {
    local p
    p=$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-' | tr -s '-')
    p="${p#-}"; p="${p%-}"
    printf '%s' "$p"
}

cbc_ledger_path() {
    printf '%s/%s.md' "$(cbc_ledger_dir)" "$(cbc_ledger_slug "$1")"
}

# Write a record.
# Args: artifact commit claim adapter status evidence_json [waiver_json]
# Echoes the record path.
cbc_ledger_write() {
    local artifact="$1" commit="$2" claim="$3" adapter="$4" status="$5"
    local evidence="$6" waiver="${7:-null}"
    local dir id path ts record
    dir="$(cbc_ledger_dir)"; mkdir -p "$dir"
    id="$(cbc_ledger_slug "$artifact")"
    path="$(cbc_ledger_path "$artifact")"
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    record=$(jq -n \
        --arg path "$artifact" --arg commit "$commit" --arg id "$id" \
        --arg claim "$claim" --arg adapter "$adapter" --arg status "$status" \
        --arg ts "$ts" --argjson evidence "$evidence" --argjson waiver "$waiver" \
        '{artifact: {path: $path, commit: $commit, id: $id}, claim: $claim,
          adapter: $adapter, status: $status, evidence: $evidence,
          waiver: $waiver, verified_at: $ts}')

    {
        echo "# CbC Evidence: $artifact"
        echo ""
        echo "- **Status:** $status"
        echo "- **Adapter:** $adapter"
        echo "- **Commit:** $commit"
        echo "- **Verified:** $ts"
        echo ""
        echo "Claim:"
        echo ""
        echo "> ${claim:-(none)}"
        echo ""
        echo '```json'
        echo "$record"
        echo '```'
    } > "$path"
    echo "$path"
}

# Record an explicit waiver against an artifact (used by `cbc waive`, TODO-025-004).
# Args: artifact reason by
cbc_ledger_waive() {
    local artifact="$1" reason="$2" by="${3:-unknown}"
    local commit waiver
    commit="$(git rev-parse --short HEAD 2>/dev/null || echo uncommitted)"
    waiver=$(jq -n --arg reason "$reason" --arg by "$by" \
        --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{reason: $reason, by: $by, at: $at}')
    cbc_ledger_write "$artifact" "$commit" "" "waiver" "waived" \
        '{"kind":"waiver","ref":null,"counterexample":null,"detail":"explicit waiver"}' "$waiver"
}

# Echo an artifact's recorded status, or "none".
cbc_ledger_status() {
    local path; path="$(cbc_ledger_path "$1")"
    [[ -f "$path" ]] || { echo "none"; return 0; }
    awk '/^```json/{f=1;next} /^```/{f=0} f' "$path" | jq -r '.status // "none"' 2>/dev/null || echo "none"
}
