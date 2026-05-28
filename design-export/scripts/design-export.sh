#!/usr/bin/env bash
#
# design-export.sh - Export a design session for handoff.
#
# Bundles a design session (created by design-iterate.sh) into a handoff
# package: the selected version image(s) plus a design-spec.md (template,
# subject, theme, version-history table, and resolved prompts), a local
# index.html preview, and a .tar.gz archive.
#
# Honest scope: the pipeline produces raster PNGs, so this exporter does NOT
# fabricate vector/SVG, Figma, or hosted "shareable link" output:
#   - SVG / Figma formats are reported as unsupported (with the reason).
#   - "Shareable preview" is a LOCAL index.html; external hosting is a follow-up.
#
# Usage:
#   design-export.sh --session <dir> [OPTIONS]
#
# Options:
#   --session DIR     Session directory (must contain session.json). Required.
#   --output DIR      Bundle output directory (default: <session>/export)
#   --format FMT      Image format to export (supported: png; default: png)
#   --all             Export every version (default: latest only)
#   --latest          Export only the latest version (default)
#   --no-archive      Do not create the .tar.gz archive
#   -h, --help        Show this help
#

set -uo pipefail

DE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

de_usage() {
    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

main() {
    local session="" output="" format="png" select="latest" make_archive="true"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) de_usage; return 0 ;;
            --session) session="${2:-}"; shift 2 ;;
            --output) output="${2:-}"; shift 2 ;;
            --format) format="${2:-png}"; shift 2 ;;
            --all) select="all"; shift ;;
            --latest) select="latest"; shift ;;
            --no-archive) make_archive="false"; shift ;;
            -*) echo "design-export: unknown option: $1" >&2; return 64 ;;
            *) echo "design-export: unexpected argument: $1" >&2; return 64 ;;
        esac
    done

    if [[ -z "$session" ]]; then
        echo "design-export: --session <dir> is required" >&2
        de_usage
        return 64
    fi
    local sessfile="$session/session.json"
    if [[ ! -f "$sessfile" ]]; then
        echo "design-export: no session.json in $session" >&2
        return 66
    fi

    # Honest format handling: only PNG is real for a raster pipeline.
    case "$format" in
        png) ;;
        svg)
            echo "design-export: SVG export is not supported -- the pipeline produces raster" >&2
            echo "  images that cannot be losslessly vectorized. Follow-up: true vector export." >&2
            return 2 ;;
        figma)
            echo "design-export: Figma export is not supported -- requires the Figma API/format." >&2
            echo "  Follow-up: Figma integration." >&2
            return 2 ;;
        *) echo "design-export: unknown format: $format (supported: png)" >&2; return 64 ;;
    esac

    [[ -z "$output" ]] && output="$session/export"
    mkdir -p "$output"

    # Determine which versions to export.
    local versions_json
    versions_json=$(jq -c '.versions' "$sessfile")
    local indices
    if [[ "$select" == "latest" ]]; then
        indices=$(jq -r '.versions | (length - 1)' "$sessfile")
    else
        indices=$(jq -r '.versions | keys[]' "$sessfile")
    fi

    # Copy selected images into the bundle.
    local idx img copied=0 missing=0
    for idx in $indices; do
        img=$(jq -r ".versions[$idx].image" "$sessfile")
        if [[ -f "$session/$img" ]]; then
            cp "$session/$img" "$output/$img"
            copied=$((copied + 1))
        else
            echo "design-export: warning: missing image $session/$img" >&2
            missing=$((missing + 1))
        fi
    done

    # Write the design spec (markdown).
    de_write_spec "$sessfile" "$output/design-spec.md"
    # Write a local HTML preview.
    de_write_preview "$sessfile" "$output/index.html" "$select"

    # Archive the bundle.
    local archive=""
    if [[ "$make_archive" == "true" ]]; then
        archive="$output.tar.gz"
        tar -czf "$archive" -C "$(dirname "$output")" "$(basename "$output")"
    fi

    echo "Exported $copied image(s) to: $output"
    echo "  - design-spec.md (specs + version history)"
    echo "  - index.html (local preview; external shareable links are a follow-up)"
    [[ -n "$archive" ]] && echo "  - archive: $archive"
    [[ "$missing" -gt 0 ]] && echo "  ($missing referenced image(s) were missing)"
    return 0
}

de_write_spec() {
    local sessfile="$1" out="$2"
    {
        local s t subj theme created n
        s=$(jq -r '.session' "$sessfile")
        t=$(jq -r '.template' "$sessfile")
        subj=$(jq -r '.subject' "$sessfile")
        theme=$(jq -r '.theme // "dark"' "$sessfile")
        created=$(jq -r '.created_at // ""' "$sessfile")
        n=$(jq '.versions | length' "$sessfile")
        echo "# Design Spec: $s"
        echo ""
        echo "- **Template:** $t"
        echo "- **Subject:** $subj"
        echo "- **Theme:** $theme"
        echo "- **Created:** $created"
        echo "- **Versions:** $n"
        echo ""
        echo "## Version History"
        echo ""
        echo "| v | feedback | reference | image | generated_at |"
        echo "|---|----------|-----------|-------|--------------|"
        jq -r '.versions[] | "| \(.v) | \(.feedback // "-") | \(.reference // "-") | \(.image) | \(.generated_at // "-") |"' "$sessfile"
        echo ""
        echo "## Resolved Prompts"
        echo ""
        jq -r '.versions[] | "### v\(.v)\n\n```\n\(.prompt // "")\n```\n"' "$sessfile"
    } > "$out"
}

de_write_preview() {
    local sessfile="$1" out="$2" select="$3"
    local s
    s=$(jq -r '.session' "$sessfile")
    {
        echo "<!DOCTYPE html>"
        echo "<html><head><meta charset=\"utf-8\"><title>Design: $s</title>"
        echo "<style>body{font-family:Inter,Segoe UI,Helvetica,sans-serif;background:#060e1a;color:#c8d6e5;padding:2rem}"
        echo "figure{margin:0 0 2rem}img{max-width:100%;border:1px solid #1e3a5f;border-radius:8px}"
        echo "figcaption{color:#8ea4c8;margin-top:.5rem}h1{color:#3490dc}</style></head><body>"
        echo "<h1>$s</h1>"
        local filter='.versions[]'
        [[ "$select" == "latest" ]] && filter='.versions[-1]'
        jq -r "$filter | \"<figure><img src=\\\"\(.image)\\\" alt=\\\"v\(.v)\\\"><figcaption>v\(.v): \(.feedback // \"initial\")</figcaption></figure>\"" "$sessfile"
        echo "</body></html>"
    } > "$out"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
