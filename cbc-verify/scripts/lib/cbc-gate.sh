#!/usr/bin/env bash
#
# cbc-gate.sh - the CbC discharge gate and waiver recording.
#
#   cbc discharge : every in-scope CbC-mandatory artifact must carry a
#                   discharged or waived evidence record; --strict exits 4 on gaps.
#   cbc waive     : record an explicit waiver (rationale) against an artifact.
#
# Realizes FLOW-009 step 7. Part of /cbc (EPIC-025). See docs/designs/cbc-skill.md.

[[ -n "${_CBC_GATE_SH_LOADED:-}" ]] && return 0
_CBC_GATE_SH_LOADED=1

_CBC_GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cbc-identify.sh
source "$_CBC_GATE_DIR/cbc-identify.sh"
# shellcheck source=cbc-ledger.sh
source "$_CBC_GATE_DIR/cbc-ledger.sh"

# cbc discharge [--scope diff|epic <EID>] [--files "..."] [--base <ref>] [--strict] [--json]
cbc_discharge() {
    local strict=0 json=0 rc=0
    local -a id_args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --strict) strict=1; shift ;;
            --json)   json=1; shift ;;
            --scope)
                id_args+=("--scope" "${2:-}")
                if [[ "${2:-}" == "epic" || "${2:-}" == "flow" ]]; then
                    id_args+=("${3:-}"); shift 3 || true
                else
                    shift 2 || true
                fi ;;
            --files)  id_args+=("--files" "${2:-}"); shift 2 || true ;;
            --base)   id_args+=("--base" "${2:-}"); shift 2 || true ;;
            *) echo "cbc discharge: unknown option '$1'" >&2; return 3 ;;
        esac
    done

    # Reuse `cbc identify` (scope resolution + tag filtering) for the candidate set.
    local mand
    if [[ ${#id_args[@]} -gt 0 ]]; then
        mand=$(cbc_identify "${id_args[@]}" --json) || rc=$?
    else
        mand=$(cbc_identify --json) || rc=$?
    fi
    [[ $rc -ne 0 ]] && return $rc

    local rows="" path st gaps=0 total=0
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        total=$((total + 1))
        st="$(cbc_ledger_status "$path")"
        case "$st" in
            discharged|waived) : ;;
            *) gaps=$((gaps + 1)) ;;
        esac
        rows+="${st}	${path}"$'\n'
    done < <(echo "$mand" | jq -r '.[].path')
    rows=$(printf '%s' "$rows" | sed '/^$/d')

    if [[ "$json" -eq 1 ]]; then
        if [[ -z "$rows" ]]; then
            echo '{"total":0,"gaps":0,"items":[]}'
        else
            printf '%s\n' "$rows" | jq -R -s --argjson g "$gaps" --argjson t "$total" \
                '{total:$t, gaps:$g, items: (split("\n")|map(select(length>0))|map(split("\t"))|map({status:.[0],path:.[1]}))}'
        fi
    else
        if [[ "$total" -eq 0 ]]; then
            echo "cbc discharge: no CbC-mandatory files in scope."
        else
            echo "cbc discharge: $((total - gaps))/$total discharged or waived ($gaps undischarged)"
            printf '%s\n' "$rows" | while IFS=$'\t' read -r st path; do
                printf '  %-12s %s\n' "$st" "$path"
            done
        fi
    fi

    [[ "$gaps" -gt 0 && "$strict" -eq 1 ]] && return 4
    return 0
}

# cbc waive <artifact> --reason TEXT
cbc_waive() {
    local artifact="" reason=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reason) reason="${2:-}"; shift 2 || true ;;
            -*) echo "cbc waive: unknown option '$1'" >&2; return 3 ;;
            *) [[ -z "$artifact" ]] && artifact="$1"; shift ;;
        esac
    done
    [[ -n "$artifact" ]] || { echo "cbc waive: artifact required" >&2; return 3; }
    [[ -n "$reason" ]]   || { echo "cbc waive: --reason TEXT is required" >&2; return 3; }
    [[ -f "$artifact" ]] || { echo "cbc waive: artifact not found: $artifact" >&2; return 1; }

    local by path
    by="$(git config user.email 2>/dev/null || echo unknown)"
    path="$(cbc_ledger_waive "$artifact" "$reason" "$by")"
    echo "cbc waive: $artifact -> waived; evidence: $path"
}
