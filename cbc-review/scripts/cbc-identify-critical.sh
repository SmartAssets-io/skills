#!/usr/bin/env bash
#
# cbc-identify-critical.sh - propose CbC-mandatory .gitattributes tags.
#
# Scans tracked files, scores candidates by sensitive-pattern risk + git churn
# + file size, and emits a PROPOSAL of `cbc=mandatory` (+ cbc-weight) lines.
# It NEVER writes .gitattributes - a human ratifies and commits the lines.
#
# Backs /review:identify-critical (the review-tooling realization of
# /code-review-assisted mission-critical identification). Part of the /cbc
# skill (EPIC-025, TODO-025-006). See docs/designs/cbc-skill.md.
#
# A file is a CANDIDATE only if it matches a rule in cbc-critical-patterns.jsonc
# (risk > 0). Files already tagged cbc=mandatory are excluded.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CONFIG="$SCRIPT_DIR/lib/cbc-critical-patterns.jsonc"

# Mirrors AItools/scripts/lib/repo-selection.sh::_strip_jsonc - strip JSONC
# block/line comments and trailing commas so jq can parse the config.
_strip_jsonc() {
    local file="$1"
    if command -v python3 &>/dev/null; then
        python3 -c "
import re, sys
text = sys.stdin.read()
text = re.sub(r'/\*[\s\S]*?\*/', '', text)
text = re.sub(r'(?<!:)//.*$', '', text, flags=re.MULTILINE)
text = re.sub(r',(\s*[}\]])', r'\1', text)
print(text)" < "$file"
    else
        cat "$file"
    fi
}

usage() {
    cat <<'EOF'
cbc-identify-critical.sh - propose CbC-mandatory .gitattributes tags

Usage:
  cbc-identify-critical.sh [--base <ref>] [--config <path>] [--json]

  --base <ref>    Only consider files changed vs <ref> (default: all tracked files)
  --config <path> Heuristics config (default: lib/cbc-critical-patterns.jsonc)
  --json          Emit a JSON array of candidates instead of the human proposal
  --help, -h      Show this help

Output is a PROPOSAL only; .gitattributes is never modified. Review the
suggested lines and append the ones you accept.
EOF
}

# Rule arrays (parallel), populated from the config.
RULE_TYPE=(); RULE_MATCH=(); RULE_RISK=(); RULE_REASON=()

# Print "<risk>\t<reason>" for the highest-risk matching rule, or "0\t".
_match_file() {
    local f="$1" best=0 best_reason="" i t m r hit base
    base="$(basename "$f")"
    for i in "${!RULE_TYPE[@]}"; do
        t="${RULE_TYPE[$i]}"; m="${RULE_MATCH[$i]}"; r="${RULE_RISK[$i]}"
        hit=0
        case "$t" in
            ext)  [[ "$f" == *."$m" ]] && hit=1 ;;
            dir)  [[ "/$f/" == */"$m"/* ]] && hit=1 ;;
            name) [[ "$base" == *"$m"* ]] && hit=1 ;;
        esac
        if [[ $hit -eq 1 && $r -gt $best ]]; then
            best="$r"; best_reason="${RULE_REASON[$i]}"
        fi
    done
    printf '%s\t%s' "$best" "$best_reason"
}

main() {
    local base="" config="${CBC_CRITICAL_CONFIG:-$DEFAULT_CONFIG}" json=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --base)   base="${2:-}"; shift 2 || true ;;
            --config) config="${2:-}"; shift 2 || true ;;
            --json)   json=1; shift ;;
            -h|--help) usage; return 0 ;;
            *) echo "cbc-identify-critical: unknown option '$1'" >&2; return 3 ;;
        esac
    done

    command -v jq >/dev/null 2>&1 || { echo "cbc-identify-critical: jq is required" >&2; return 3; }
    [[ -f "$config" ]] || { echo "cbc-identify-critical: config not found: $config" >&2; return 3; }

    local cfg
    cfg=$(_strip_jsonc "$config")
    echo "$cfg" | jq -e '.' >/dev/null 2>&1 || { echo "cbc-identify-critical: invalid config JSON after comment-strip: $config" >&2; return 3; }

    # Thresholds.
    local churn_hi churn_mid size_hi size_mid w_hi w_mid
    churn_hi=$(echo "$cfg" | jq -r '.churn.high'); churn_mid=$(echo "$cfg" | jq -r '.churn.mid')
    size_hi=$(echo "$cfg" | jq -r '.size.high');  size_mid=$(echo "$cfg" | jq -r '.size.mid')
    w_hi=$(echo "$cfg" | jq -r '.weight.high');   w_mid=$(echo "$cfg" | jq -r '.weight.medium')

    # Rules.
    local t m r reason
    while IFS=$'\t' read -r t m r reason; do
        [[ -z "$t" ]] && continue
        RULE_TYPE+=("$t"); RULE_MATCH+=("$m"); RULE_RISK+=("$r"); RULE_REASON+=("$reason")
    done < <(echo "$cfg" | jq -r '.rules[] | [.type, .match, (.risk|tostring), .reason] | @tsv')

    # Candidate file list.
    local -a files=()
    if [[ -n "$base" ]]; then
        mapfile -t files < <(git diff --name-only "$base" 2>/dev/null)
    else
        mapfile -t files < <(git ls-files 2>/dev/null)
    fi

    # rows: "score\tweight\tpath\trisk\tchurn\tloc\treason"
    local rows="" f risk reason2 churn loc score weight bonus
    for f in "${files[@]}"; do
        [[ -z "$f" || ! -f "$f" ]] && continue
        IFS=$'\t' read -r risk reason2 < <(_match_file "$f")
        [[ "$risk" -eq 0 ]] && continue
        # Exclude files already tagged cbc=mandatory.
        if [[ "$(git check-attr cbc -- "$f" 2>/dev/null)" == *": cbc: mandatory" ]]; then
            continue
        fi
        churn=$(git log --oneline -- "$f" 2>/dev/null | wc -l | tr -d ' ')
        loc=$(wc -l < "$f" 2>/dev/null | tr -d ' '); loc="${loc:-0}"

        score="$risk"
        if   [[ "$churn" -ge "$churn_hi"  ]]; then score=$((score + 2))
        elif [[ "$churn" -ge "$churn_mid" ]]; then score=$((score + 1)); fi
        if   [[ "$loc" -ge "$size_hi"  ]]; then score=$((score + 2))
        elif [[ "$loc" -ge "$size_mid" ]]; then score=$((score + 1)); fi

        if   [[ "$score" -ge "$w_hi"  ]]; then weight="high"
        elif [[ "$score" -ge "$w_mid" ]]; then weight="medium"
        else weight="low"; fi

        rows+="${score}	${weight}	${f}	${risk}	${churn}	${loc}	${reason2}"$'\n'
    done

    rows=$(printf '%s' "$rows" | sed '/^$/d' | sort -t$'\t' -k1,1nr -k3,3)

    if [[ "$json" -eq 1 ]]; then
        if [[ -z "$rows" ]]; then echo "[]"; return 0; fi
        printf '%s\n' "$rows" | jq -R -s '
            split("\n") | map(select(length > 0)) | map(split("\t")) |
            map({path: .[2], weight: .[1], score: (.[0]|tonumber),
                 risk: (.[3]|tonumber), churn: (.[4]|tonumber),
                 loc: (.[5]|tonumber), reason: .[6]})'
        return 0
    fi

    if [[ -z "$rows" ]]; then
        echo "No new mission-critical candidates found (already-tagged files are excluded)."
        return 0
    fi

    local count
    count=$(printf '%s\n' "$rows" | wc -l | tr -d ' ')
    echo "Proposed CbC-mandatory tags ($count candidate(s)):"
    echo "(review and append accepted lines to .gitattributes; nothing is written automatically)"
    echo ""
    printf '%s\n' "$rows" | while IFS=$'\t' read -r score weight path risk churn loc reason; do
        printf '  %-7s %-45s (risk=%s churn=%s loc=%s  %s)\n' "$weight" "$path" "$risk" "$churn" "$loc" "$reason"
    done
    echo ""
    echo "Proposed .gitattributes additions:"
    printf '%s\n' "$rows" | while IFS=$'\t' read -r score weight path risk churn loc reason; do
        printf '  %s   cbc=mandatory cbc-weight=%s\n' "$path" "$weight"
    done
}

main "$@"
