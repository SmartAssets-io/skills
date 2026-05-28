#!/usr/bin/env bash
#
# design-iterate.sh - Conversational design refinement on top of design-generator.sh.
#
# Manages a design "session": an output directory of versioned images
# (v1.png, v2.png, ...) plus a session.json history that records each version's
# feedback, reference image, resolved prompt, and timestamp. Refinement reuses
# the layout-variation prompt template, passing the previous version as a
# --reference and the user's "make it more X" feedback as the VARIATION.
#
# Subcommands:
#   start <template> --description "..." [--var K=V]... [--theme dark|light]
#                    [--session NAME] [--output-dir DIR]
#       Seed a new session: generate v1 from <template> and write session.json.
#
#   refine --session <dir> --feedback "make it more X" [--theme dark|light]
#       Generate the next version from the latest one + feedback.
#
#   history --session <dir>
#       Print the session history (session.json).
#
# Environment:
#   DESIGN_GENERATOR   Path to design-generator.sh (default: alongside this script).
#                      Generation requires GEMINI_API_KEY / GOOGLE_API_KEY.
#

set -uo pipefail

DI_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DI_GENERATOR="${DESIGN_GENERATOR:-$DI_SCRIPT_DIR/design-generator.sh}"
DI_OUTPUT_DIR_DEFAULT="design-output"

di_usage() {
    sed -n '2,34p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Highest existing version number in a session dir (0 if none).
di_latest_version() {
    local sd="$1" f n max=0
    for f in "$sd"/v*.png; do
        [[ -e "$f" ]] || continue
        n="$(basename "$f" .png)"; n="${n#v}"
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n > max )); then max="$n"; fi
    done
    echo "$max"
}

# Read .resolved_prompt from a generator sidecar (empty if absent).
di_sidecar_prompt() {
    jq -r '.resolved_prompt // ""' "$1.json" 2>/dev/null || echo ""
}

di_start() {
    local template="" description="" theme="dark" session="" outdir="$DI_OUTPUT_DIR_DEFAULT"
    local var_args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --description) description="${2:-}"; shift 2 ;;
            --var) var_args+=("--var" "${2:-}"); shift 2 ;;
            --theme) theme="${2:-dark}"; shift 2 ;;
            --session) session="${2:-}"; shift 2 ;;
            --output-dir) outdir="${2:-}"; shift 2 ;;
            -*) echo "design-iterate: unknown option: $1" >&2; return 64 ;;
            *) if [[ -z "$template" ]]; then template="$1"; else
                   echo "design-iterate: unexpected argument: $1" >&2; return 64; fi
               shift ;;
        esac
    done

    if [[ -z "$template" || -z "$description" ]]; then
        echo "design-iterate: start requires <template> and --description" >&2
        return 64
    fi

    [[ -z "$session" ]] && session="${template}-$(date -u +%Y%m%dT%H%M%SZ)"
    local sessdir="$outdir/$session"
    mkdir -p "$sessdir"
    local img="$sessdir/v1.png"

    if ! "$DI_GENERATOR" "$template" --description "$description" \
            ${var_args[@]+"${var_args[@]}"} --theme "$theme" --output "$img"; then
        echo "design-iterate: initial generation failed" >&2
        return 1
    fi

    local prompt ts
    prompt="$(di_sidecar_prompt "$img")"
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    jq -n --arg s "$session" --arg t "$template" --arg subj "$description" \
        --arg ts "$ts" --arg img "v1.png" --arg prompt "$prompt" --arg theme "$theme" \
        '{session: $s, template: $t, subject: $subj, theme: $theme, created_at: $ts,
          versions: [{v: 1, feedback: null, reference: null, image: $img, prompt: $prompt, generated_at: $ts}]}' \
        > "$sessdir/session.json"

    echo "Session started: $sessdir"
    echo "v1: $img"
}

di_refine() {
    local session="" feedback="" theme=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --session) session="${2:-}"; shift 2 ;;
            --feedback) feedback="${2:-}"; shift 2 ;;
            --theme) theme="${2:-}"; shift 2 ;;
            -*) echo "design-iterate: unknown option: $1" >&2; return 64 ;;
            *) echo "design-iterate: unexpected argument: $1" >&2; return 64 ;;
        esac
    done

    if [[ -z "$session" || -z "$feedback" ]]; then
        echo "design-iterate: refine requires --session <dir> and --feedback" >&2
        return 64
    fi
    local sessfile="$session/session.json"
    if [[ ! -f "$sessfile" ]]; then
        echo "design-iterate: no session.json in $session" >&2
        return 66
    fi

    local subject last next refimg img
    subject="$(jq -r '.subject' "$sessfile")"
    [[ -z "$theme" ]] && theme="$(jq -r '.theme // "dark"' "$sessfile")"
    last="$(di_latest_version "$session")"
    if [[ "$last" -lt 1 ]]; then
        echo "design-iterate: session has no versions to refine" >&2
        return 1
    fi
    next=$((last + 1))
    refimg="v${last}.png"
    img="$session/v${next}.png"

    if ! "$DI_GENERATOR" layout-variation --description "$subject" \
            --var "VARIATION=$feedback" --reference "$session/$refimg" \
            --theme "$theme" --output "$img"; then
        echo "design-iterate: refinement generation failed" >&2
        return 1
    fi

    local prompt ts updated
    prompt="$(di_sidecar_prompt "$img")"
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    updated="$(jq --arg fb "$feedback" --arg ref "$refimg" --arg img "v${next}.png" \
        --arg prompt "$prompt" --arg ts "$ts" --argjson v "$next" \
        '.versions += [{v: $v, feedback: $fb, reference: $ref, image: $img, prompt: $prompt, generated_at: $ts}]' \
        "$sessfile")"
    printf '%s\n' "$updated" > "$sessfile"

    echo "v${next} created: $img (refined from $refimg)"
}

di_history() {
    local session=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --session) session="${2:-}"; shift 2 ;;
            *) shift ;;
        esac
    done
    if [[ -z "$session" || ! -f "$session/session.json" ]]; then
        echo "design-iterate: no session.json in ${session:-<none>}" >&2
        return 66
    fi
    jq . "$session/session.json"
}

main() {
    local sub="${1:-}"
    [[ $# -gt 0 ]] && shift
    case "$sub" in
        start)   di_start "$@" ;;
        refine)  di_refine "$@" ;;
        history) di_history "$@" ;;
        -h|--help|"") di_usage ;;
        *) echo "design-iterate: unknown subcommand: $sub" >&2; di_usage; return 64 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
