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
ATTRIBUTES_HELPER="$SCRIPT_DIR/lib/cbc-attributes.py"

usage() {
	cat <<'EOF'
cbc-scaffold.sh - initialize CbC scaffolding and apply scanner tags

Usage:
  cbc-scaffold.sh [--base <ref>] [--config <path>] [--dry-run] [--no-tags]
                  [--root-only] [--acceptance-required]

  --base <ref>     Scope tag proposals to files changed vs <ref>.
  --config <path>  Heuristics config for cbc-identify-critical.sh.
  --dry-run        Show planned directory and .gitattributes changes only.
  --no-tags        Create scaffolding only; do not run/apply tag proposals.
  --root-only      Route new rules to the root policy file.
  --acceptance-required  Add required acceptance to new mandatory rules.
  --help, -h       Show this help.

Creates docs/cbc-evidence/.gitkeep and docs/claims/.gitkeep. By default it
runs cbc-identify-critical.sh --json and appends each candidate to its owner
policy file as an anchored exact-file rule. Existing rules remain unchanged.
EOF
}

main() {
	local base="" config="${CBC_CRITICAL_CONFIG:-}" dry_run=0 apply_tags=1
	local root_only=0 acceptance_required=0
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--base) base="${2:-}"; shift 2 || true ;;
			--config) config="${2:-}"; shift 2 || true ;;
			--dry-run) dry_run=1; shift ;;
			--no-tags) apply_tags=0; shift ;;
			--root-only) root_only=1; shift ;;
			--acceptance-required) acceptance_required=1; shift ;;
			-h|--help) usage; return 0 ;;
			*) echo "cbc-scaffold: unknown option '$1'" >&2; usage >&2; return 3 ;;
		esac
	done

	command -v jq >/dev/null 2>&1 || { echo "cbc-scaffold: jq is required" >&2; return 3; }
	git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "cbc-scaffold: must run inside a git repository" >&2; return 3; }
	[[ -x "$SCANNER" ]] || { echo "cbc-scaffold: scanner missing or not executable: $SCANNER" >&2; return 3; }

	local root evidence_dir claims_dir
	[[ -z "$config" || "$config" == /* ]] || config="$PWD/$config"
	root="$(git rev-parse --show-toplevel)" || return 3
	cd "$root" || return 3
	evidence_dir="$root/docs/cbc-evidence"
	claims_dir="$root/docs/claims"

	echo "CbC scaffold plan:"
	echo "  evidence ledger: docs/cbc-evidence/.gitkeep"
	echo "  claim specs:     docs/claims/.gitkeep"

	local candidates='[]' count=0
	if [[ "$apply_tags" -eq 1 ]]; then
		local -a scanner_args=(--json)
		[[ -n "$base" ]] && scanner_args+=(--base "$base")
		[[ -n "$config" ]] && scanner_args+=(--config "$config")
		[[ "$root_only" -eq 1 ]] && scanner_args+=(--root-only)
		[[ "$acceptance_required" -eq 1 ]] && scanner_args+=(--acceptance-required)
		candidates="$("$SCANNER" "${scanner_args[@]}")" || return $?
		count="$(printf '%s' "$candidates" | jq 'length')" || return 3
		echo "Applying $count CbC tag candidate(s) from scanner output:"
		printf '%s' "$candidates" | jq -r '.[] | "  \(.attributes_file): \(.rule)"'
		if [[ "$dry_run" -eq 0 ]]; then
			printf '%s' "$candidates" | python3 "$ATTRIBUTES_HELPER" apply || return 3
		fi
	fi

	if [[ "$dry_run" -eq 0 ]]; then
		mkdir -p "$evidence_dir" "$claims_dir" || return 3
		[[ -e "$evidence_dir/.gitkeep" ]] || : > "$evidence_dir/.gitkeep"
		[[ -e "$claims_dir/.gitkeep" ]] || : > "$claims_dir/.gitkeep"
	fi

	if [[ "$apply_tags" -eq 0 ]]; then
		echo "CbC scaffolding complete (tag application skipped)."
		return 0
	fi

	if [[ "$dry_run" -eq 1 ]]; then
		echo "Dry run only; no files changed."
	else
		echo "CbC scaffold complete. Review and commit .gitattributes plus scaffold files."
	fi
}

main "$@"
