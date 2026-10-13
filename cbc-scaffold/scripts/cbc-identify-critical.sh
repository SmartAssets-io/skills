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
ATTRIBUTES_HELPER="$SCRIPT_DIR/lib/cbc-attributes.py"

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
                          [--root-only] [--acceptance-required]

  --base <ref>    Only consider files changed vs <ref> (default: all tracked files)
  --config <path> Heuristics and owner config (default: lib/cbc-critical-patterns.jsonc)
  --json          Emit routed candidates with their destination and exact rule.
  --root-only     Route new rules to the root policy file.
  --acceptance-required  Add required acceptance to new mandatory rules.
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
    local root_only=0 acceptance_required=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --base)   base="${2:-}"; shift 2 || true ;;
            --config) config="${2:-}"; shift 2 || true ;;
            --json)   json=1; shift ;;
            --root-only) root_only=1; shift ;;
            --acceptance-required) acceptance_required=1; shift ;;
            -h|--help) usage; return 0 ;;
            *) echo "cbc-identify-critical: unknown option '$1'" >&2; return 3 ;;
        esac
    done

    command -v jq >/dev/null 2>&1 || { echo "cbc-identify-critical: jq is required" >&2; return 3; }
    [[ -f "$config" ]] || { echo "cbc-identify-critical: config not found: $config" >&2; return 3; }
    command -v python3 >/dev/null 2>&1 || { echo "cbc-identify-critical: python3 is required" >&2; return 3; }
    [[ "$config" == /* ]] || config="$PWD/$config"
    local root
    root="$(git rev-parse --show-toplevel)" || return 3
    cd "$root" || return 3

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
        mapfile -d '' -t files < <(git diff --name-only -z "$base" 2>/dev/null)
    else
        mapfile -d '' -t files < <(git ls-files -z 2>/dev/null)
    fi

    # JSON rows keep filenames and reasons separate from presentation delimiters.
    local rows="" f risk reason2 churn loc score weight
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

        rows+="$(jq -cn --arg path "$f" --arg weight "$weight" --arg reason "$reason2" \
            --argjson score "$score" --argjson risk "$risk" --argjson churn "$churn" --argjson loc "$loc" \
            '{path:$path, weight:$weight, score:$score, risk:$risk, churn:$churn, loc:$loc, reason:$reason}')"$'\n'
    done

    local candidates owners
    candidates=$(printf '%s' "$rows" | jq -s 'sort_by([(-.score), .path])') || return 3
    owners=$(echo "$cfg" | jq -c '.attribute_owners // []') || return 3
    candidates=$(jq -n --argjson candidates "$candidates" --argjson owners "$owners" \
        --argjson root_only "$root_only" --argjson acceptance_required "$acceptance_required" \
        '{candidates:$candidates, owners:$owners, root_only:($root_only == 1),
          acceptance_required:($acceptance_required == 1)}' | python3 "$ATTRIBUTES_HELPER" route) || return 3
    if [[ "$json" -eq 1 ]]; then
        printf '%s\n' "$candidates"
        return 0
    fi

    if [[ "$(echo "$candidates" | jq 'length')" -eq 0 ]]; then
        echo "No new mission-critical candidates found (already-tagged files are excluded)."
        return 0
    fi

    local count
    count=$(echo "$candidates" | jq 'length')
    echo "Proposed CbC-mandatory tags ($count candidate(s)):"
    echo "(review and append accepted lines to .gitattributes; nothing is written automatically)"
    echo ""
    echo "$candidates" | jq -r '.[] | [.weight,.path,.risk,.churn,.loc,.reason] | @tsv' |
        while IFS=$'\t' read -r weight path risk churn loc reason; do
            printf '  %-7s %-45s (risk=%s churn=%s loc=%s  %s)\n' "$weight" "$path" "$risk" "$churn" "$loc" "$reason"
        done
    echo ""
    echo "Proposed .gitattributes additions (destination: exact rule):"
    echo "$candidates" | jq -r '.[] | "  \(.attributes_file): \(.rule)"'
}

main "$@"
