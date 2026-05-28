#!/usr/bin/env bash
#
# task-complete.sh - Mark a task or epic complete, stamping integrity gaps.
#
# Usage:
#   task-complete.sh TODO-XXX-NNN [--unit-tests p1,p2,...] [--strict] [--no-stamp] [--force]
#   task-complete.sh EPIC-XXX                              [--strict] [--no-stamp] [--force]
#
# Default behaviour:
#   1. Run integrity-walker on the target.
#   2. If gaps exist, print them as a warning report.
#   3. Stamp `completion_gaps: [...]` into the task/epic YAML (unless --no-stamp).
#   4. Flip status to `complete` (+ completed_date: YYYY-MM-DD on tasks).
#
# --strict: refuse to mark complete if any gaps exist. Exits non-zero.
# --force:  bypass --strict refusal.
# --no-stamp: skip writing completion_gaps even when gaps exist.
#
# Dependencies: jq, bash 4+, integrity-walker.sh + sibling parsers.

set -euo pipefail

SCRIPT_DIR_TC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR_TC="${SCRIPT_DIR_TC}/lib"

# shellcheck source=lib/user-flow-parser.sh
[[ -f "${LIB_DIR_TC}/user-flow-parser.sh" ]] && source "${LIB_DIR_TC}/user-flow-parser.sh"
# shellcheck source=lib/story-parser.sh
[[ -f "${LIB_DIR_TC}/story-parser.sh" ]]     && source "${LIB_DIR_TC}/story-parser.sh"
# shellcheck source=lib/epic-parser.sh
[[ -f "${LIB_DIR_TC}/epic-parser.sh" ]]     && source "${LIB_DIR_TC}/epic-parser.sh"
# shellcheck source=lib/integrity-walker.sh
[[ -f "${LIB_DIR_TC}/integrity-walker.sh" ]] && source "${LIB_DIR_TC}/integrity-walker.sh"

TODOS_FILE="${TODOS_FILE:-docs/ToDos.md}"
USER_FLOWS_FILE="${USER_FLOWS_FILE:-docs/User-Flows.md}"
USER_STORIES_FILE="${USER_STORIES_FILE:-docs/UserStories.md}"
INTEGRITY_TODOS_FILE="$TODOS_FILE"
INTEGRITY_USER_FLOWS_FILE="$USER_FLOWS_FILE"
INTEGRITY_USER_STORIES_FILE="$USER_STORIES_FILE"

EXIT_OK=0
EXIT_TARGET_NOT_FOUND=1
EXIT_INVALID_ARGS=2
EXIT_GAPS_BLOCKED=3
EXIT_WRITE_ERROR=4

show_help() {
    cat <<EOF
task-complete.sh - Mark a task or epic complete with integrity reporting

Usage:
  $(basename "$0") TODO-XXX-NNN [--unit-tests p1,p2,...] [OPTIONS]
  $(basename "$0") EPIC-XXX                                 [OPTIONS]

Options:
  --unit-tests p1,p2,...   (task only) Write this comma-separated list into the
                           task's unit_tests: field before validation.
  --strict                 Refuse to complete if any integrity gaps exist.
  --force                  Bypass --strict refusal (logs a warning).
  --no-stamp               Do not write completion_gaps: into YAML.
  --help, -h               Show this help.

Default: warn on gaps, stamp completion_gaps:, then mark complete.

Environment:
  TODOS_FILE               override docs/ToDos.md
  USER_FLOWS_FILE          override docs/User-Flows.md
  USER_STORIES_FILE        override docs/UserStories.md
EOF
}

# -----------------------------------------------------------------------------
# YAML writers - in-place edits with .bak mirror
# -----------------------------------------------------------------------------

# Today's date in YYYY-MM-DD (UTC).
_today_iso() { date -u +%F; }

# Render a JSON array of strings into an inline YAML list "[a, b, c]".
# Empty array -> "[]".
_render_yaml_list() {
    echo "$1" | jq -r '"[" + (map(.) | join(", ")) + "]"'
}

# Inside a task entry (lines indented under a `tasks:` list, identified by
# `- id: TASK_ID` or `id: TASK_ID` at the task root), set or insert a field.
# This is a line-based editor matching the existing repo convention; it
# preserves the surrounding YAML untouched.
#
# Args:
#   $1 file
#   $2 task_id (matched against `id:` line)
#   $3 field_name (e.g. status, completed_date, unit_tests, completion_gaps)
#   $4 yaml_value (rendered into "<field>: <value>")
_set_task_field() {
    local file="$1" task_id="$2" field="$3" value="$4"
    [[ -f "$file" ]] || return 4

    cp "$file" "${file}.bak"
    local tmp="${file}.tmp"

    awk -v tid="$task_id" -v field="$field" -v value="$value" '
        BEGIN { in_task=0; matched=0; field_seen=0; indent=""; }
        {
            # Detect task entry: "- id: TID" or "id: TID" at task root.
            if ($0 ~ /^[[:space:]]*-?[[:space:]]*id:[[:space:]]*[A-Za-z0-9_-]+/) {
                # Close any prior task entry by flushing the field if missing.
                # Uses the OLD indent (set during the previous task entry).
                if (in_task && !field_seen && matched) {
                    print indent field ": " value
                }
                # Extract the id value from this line.
                line_id = $0
                sub(/^[[:space:]]*-?[[:space:]]*id:[[:space:]]*/, "", line_id)
                sub(/[[:space:]].*$/, "", line_id)
                # Compute the sibling-field indent: pad to the column of "id:".
                pos = index($0, "id:")
                indent = ""
                for (i = 1; i < pos; i++) indent = indent " "
                in_task = 1
                field_seen = 0
                matched = (line_id == tid)
                print
                next
            }
            # End of task entry: another - or unindented line
            if (in_task && /^[^[:space:]]/) {
                if (matched && !field_seen) {
                    print indent field ": " value
                    field_seen = 1
                }
                in_task = 0
                matched = 0
                print
                next
            }
            # Replace an existing field line within the matched task.
            if (in_task && matched) {
                pat = "^[[:space:]]+" field ":"
                if ($0 ~ pat) {
                    print indent field ": " value
                    field_seen = 1
                    next
                }
            }
            print
        }
        END {
            if (matched && !field_seen) {
                print indent field ": " value
            }
        }
    ' "$file" > "$tmp"

    mv "$tmp" "$file"
}

# Set / insert an epic-level field on the matching epic YAML block.
_set_epic_field() {
    local file="$1" epic_id="$2" field="$3" value="$4"
    [[ -f "$file" ]] || return 4

    cp "$file" "${file}.bak"
    local tmp="${file}.tmp"

    awk -v eid="$epic_id" -v field="$field" -v value="$value" '
        BEGIN { in_yaml=0; in_target=0; field_seen=0; printed_yaml_open=0; }
        /^```yaml/ {
            in_yaml=1; in_target=0; field_seen=0; print; next
        }
        /^```/ && in_yaml {
            # closing fence
            if (in_target && !field_seen) {
                print field ": " value
                field_seen=1
            }
            in_yaml=0; in_target=0; print; next
        }
        {
            if (in_yaml) {
                if ($0 ~ "^id:[[:space:]]*"eid"$" || $0 ~ "^epic_id:[[:space:]]*"eid"$") {
                    in_target=1
                }
                if (in_target && $0 ~ "^"field":") {
                    print field ": " value
                    field_seen=1
                    next
                }
            }
            print
        }
    ' "$file" > "$tmp"

    mv "$tmp" "$file"
}

# -----------------------------------------------------------------------------
# Reporters
# -----------------------------------------------------------------------------

_render_report() {
    local result_json="$1"
    local target grade gap_count
    target=$(echo "$result_json" | jq -r '.target')
    grade=$(echo "$result_json" | jq -r '.grade')
    gap_count=$(echo "$result_json" | jq '.gaps | length')

    echo "Target: ${target}    Grade: ${grade}    Gaps: ${gap_count}"
    if [[ "$gap_count" -gt 0 ]]; then
        echo "Gaps:"
        echo "$result_json" | jq -r '.gaps[] | "  - \(.)"'
        echo "Details:"
        echo "$result_json" | jq -r '.details[] | "  [\(.code)] \(.message)"'
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    local target=""
    local unit_tests=""
    local strict=false
    local force=false
    local no_stamp=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)        show_help; exit $EXIT_OK ;;
            --unit-tests)     shift; unit_tests="${1:-}" ;;
            --strict)         strict=true ;;
            --force)          force=true ;;
            --no-stamp)       no_stamp=true ;;
            -*)
                echo "Unknown option: $1" >&2
                exit $EXIT_INVALID_ARGS
                ;;
            *)
                if [[ -z "$target" ]]; then
                    target="$1"
                else
                    echo "Unexpected argument: $1" >&2
                    exit $EXIT_INVALID_ARGS
                fi
                ;;
        esac
        shift || true
    done

    if [[ -z "$target" ]]; then
        echo "Error: target required (TODO-XXX-NNN or EPIC-XXX)" >&2
        show_help
        exit $EXIT_INVALID_ARGS
    fi

    # Re-export INTEGRITY_* in case TODOS_FILE/USER_FLOWS_FILE/USER_STORIES_FILE
    # were set from the calling environment after this script started.
    INTEGRITY_TODOS_FILE="${TODOS_FILE}"
    INTEGRITY_USER_FLOWS_FILE="${USER_FLOWS_FILE}"
    INTEGRITY_USER_STORIES_FILE="${USER_STORIES_FILE}"

    case "$target" in
        TODO-*)
            mark_task_complete "$target" "$unit_tests" "$strict" "$force" "$no_stamp"
            ;;
        EPIC-*)
            [[ -n "$unit_tests" ]] && echo "Warning: --unit-tests is ignored for epic targets" >&2
            mark_epic_complete "$target" "$strict" "$force" "$no_stamp"
            ;;
        *)
            echo "Error: target must start with TODO- or EPIC-" >&2
            exit $EXIT_INVALID_ARGS
            ;;
    esac
}

mark_task_complete() {
    local task_id="$1" unit_tests_csv="$2" strict="$3" force="$4" no_stamp="$5"

    if [[ ! -f "$TODOS_FILE" ]]; then
        echo "Error: ${TODOS_FILE} not found" >&2
        exit $EXIT_TARGET_NOT_FOUND
    fi

    # 1. Optionally write unit_tests:
    if [[ -n "$unit_tests_csv" ]]; then
        local list_json
        list_json=$(jq -nc --arg s "$unit_tests_csv" \
            '$s | split(",") | map(gsub("^\\s+|\\s+$"; ""))')
        local list_yaml
        list_yaml=$(_render_yaml_list "$list_json")
        _set_task_field "$TODOS_FILE" "$task_id" "unit_tests" "$list_yaml"
        echo "Recorded unit_tests for ${task_id}: ${list_yaml}"
    fi

    # 2. Validate the task chain
    local result
    result=$(validate_task "$task_id")
    local grade
    grade=$(echo "$result" | jq -r '.grade')

    if [[ "$grade" == "missing" ]]; then
        echo "Error: task ${task_id} not found" >&2
        _render_report "$result" >&2
        exit $EXIT_TARGET_NOT_FOUND
    fi

    local gap_count
    gap_count=$(echo "$result" | jq '.gaps | length')

    if [[ "$gap_count" -gt 0 ]]; then
        echo ""
        echo "INTEGRITY REPORT (warning):"
        _render_report "$result"
        echo ""
        if [[ "$strict" == "true" ]] && [[ "$force" != "true" ]]; then
            echo "Refusing to mark ${task_id} complete due to gaps (--strict). Use --force to override." >&2
            exit $EXIT_GAPS_BLOCKED
        fi
    fi

    # 3. Stamp completion_gaps (skip with --no-stamp)
    if [[ "$no_stamp" != "true" ]]; then
        local gaps_yaml
        gaps_yaml=$(_render_yaml_list "$(echo "$result" | jq '.gaps')")
        _set_task_field "$TODOS_FILE" "$task_id" "completion_gaps" "$gaps_yaml"
    fi

    # 4. Flip status + completed_date
    _set_task_field "$TODOS_FILE" "$task_id" "status" "complete"
    _set_task_field "$TODOS_FILE" "$task_id" "completed_date" "$(_today_iso)"

    echo "Marked ${task_id} complete (${grade})."
}

mark_epic_complete() {
    local epic_id="$1" strict="$2" force="$3" no_stamp="$4"

    if [[ ! -f "$TODOS_FILE" ]]; then
        echo "Error: ${TODOS_FILE} not found" >&2
        exit $EXIT_TARGET_NOT_FOUND
    fi

    # Refuse to mass-complete: every child task must already be `complete`.
    local epic
    epic=$(get_epic "$epic_id" "$TODOS_FILE" 2>/dev/null || echo "")
    if [[ -z "$epic" || "$epic" == "null" ]]; then
        echo "Error: epic ${epic_id} not found" >&2
        exit $EXIT_TARGET_NOT_FOUND
    fi
    local total complete
    total=$(echo "$epic" | jq '.tasks | length')
    complete=$(echo "$epic" | jq '[.tasks[] | select(.status == "complete")] | length')
    if [[ "$total" -gt 0 ]] && [[ "$complete" -lt "$total" ]]; then
        echo "Error: epic ${epic_id} has ${complete}/${total} tasks complete. Finish all tasks first (via task-complete TODO-XXX-NNN)." >&2
        exit $EXIT_GAPS_BLOCKED
    fi

    local result
    result=$(validate_epic "$epic_id")
    local grade gap_count
    grade=$(echo "$result" | jq -r '.grade')
    gap_count=$(echo "$result" | jq '.gaps | length')

    if [[ "$gap_count" -gt 0 ]]; then
        echo ""
        echo "INTEGRITY REPORT (warning):"
        _render_report "$result"
        echo ""
        if [[ "$strict" == "true" ]] && [[ "$force" != "true" ]]; then
            echo "Refusing to mark ${epic_id} complete due to gaps (--strict). Use --force to override." >&2
            exit $EXIT_GAPS_BLOCKED
        fi
    fi

    if [[ "$no_stamp" != "true" ]]; then
        local gaps_yaml
        gaps_yaml=$(_render_yaml_list "$(echo "$result" | jq '.gaps')")
        _set_epic_field "$TODOS_FILE" "$epic_id" "completion_gaps" "$gaps_yaml"
    fi

    _set_epic_field "$TODOS_FILE" "$epic_id" "status" "complete"
    echo "Marked ${epic_id} complete (${grade})."
}

main "$@"
