#!/usr/bin/env bash
#
# cbc-scaffold.sh - initialize CbC workspace scaffolding and optionally apply
# scanner-proposed cbc=mandatory .gitattributes tags.
#
# This is the deterministic backing script for /cbc:scaffold and /skill:cbc-scaffold.
# It creates the evidence/claims directories and appends accepted scanner output
# to .gitattributes. It never removes or rewrites existing tags.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANNER="$SCRIPT_DIR/cbc-identify-critical.sh"

usage() {
	cat <<'EOF'
cbc-scaffold.sh - initialize CbC scaffolding and apply scanner tags

Usage:
  cbc-scaffold.sh [--base <ref>] [--config <path>] [--dry-run] [--no-tags]

  --base <ref>     Scope tag proposals to files changed vs <ref>.
  --config <path>  Heuristics config for cbc-identify-critical.sh.
  --dry-run        Show planned directory and .gitattributes changes only.
  --no-tags        Create scaffolding only; do not run/apply tag proposals.
  --help, -h       Show this help.

Creates docs/cbc-evidence/.gitkeep and docs/claims/.gitkeep. By default it
runs cbc-identify-critical.sh --json and appends every proposed candidate to
.gitattributes as cbc=mandatory with cbc-weight=<weight>.
EOF
}

_escape_attr_pattern() {
	local p="$1"
	p="${p//\\/\\\\}"
	p="${p// /\\ }"
	printf '%s' "$p"
}

main() {
	local base="" config="" dry_run=0 apply_tags=1
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--base) base="${2:-}"; shift 2 || true ;;
			--config) config="${2:-}"; shift 2 || true ;;
			--dry-run) dry_run=1; shift ;;
			--no-tags) apply_tags=0; shift ;;
			-h|--help) usage; return 0 ;;
			*) echo "cbc-scaffold: unknown option '$1'" >&2; usage >&2; return 3 ;;
		esac
	done

	command -v jq >/dev/null 2>&1 || { echo "cbc-scaffold: jq is required" >&2; return 3; }
	git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "cbc-scaffold: must run inside a git repository" >&2; return 3; }
	[[ -x "$SCANNER" ]] || { echo "cbc-scaffold: scanner missing or not executable: $SCANNER" >&2; return 3; }

	local root evidence_dir claims_dir attrs
	root="$(git rev-parse --show-toplevel)"
	evidence_dir="$root/docs/cbc-evidence"
	claims_dir="$root/docs/claims"
	attrs="$root/.gitattributes"

	echo "CbC scaffold plan:"
	echo "  evidence ledger: docs/cbc-evidence/.gitkeep"
	echo "  claim specs:     docs/claims/.gitkeep"
	echo "  attributes:      .gitattributes"

	if [[ "$dry_run" -eq 0 ]]; then
		mkdir -p "$evidence_dir" "$claims_dir"
		: > "$evidence_dir/.gitkeep"
		: > "$claims_dir/.gitkeep"
		[[ -f "$attrs" ]] || : > "$attrs"
	fi

	if [[ "$apply_tags" -eq 0 ]]; then
		echo "CbC scaffolding complete (tag application skipped)."
		return 0
	fi

	local -a scanner_args=(--json)
	[[ -n "$base" ]] && scanner_args+=(--base "$base")
	[[ -n "$config" ]] && scanner_args+=(--config "$config")

	local candidates
	candidates="$($SCANNER "${scanner_args[@]}")" || return $?
	local count
	count="$(printf '%s' "$candidates" | jq 'length')"
	if [[ "$count" == "0" ]]; then
		echo "No new CbC tag candidates found."
		return 0
	fi

	echo "Applying $count CbC tag candidate(s) from scanner output:"
	local lines line path weight pattern
	lines="$(printf '%s' "$candidates" | jq -r '.[] | [.path, .weight] | @tsv')"
	while IFS=$'\t' read -r path weight; do
		[[ -n "$path" ]] || continue
		pattern="$(_escape_attr_pattern "$path")"
		line="$pattern cbc=mandatory cbc-weight=$weight"
		printf '  %s\n' "$line"
		if [[ "$dry_run" -eq 0 ]]; then
			if ! grep -Fqx -- "$line" "$attrs" 2>/dev/null; then
				printf '%s\n' "$line" >> "$attrs"
			fi
		fi
	done <<< "$lines"

	if [[ "$dry_run" -eq 1 ]]; then
		echo "Dry run only; no files changed."
	else
		echo "CbC scaffold complete. Review and commit .gitattributes plus scaffold files."
	fi
}

main "$@"
