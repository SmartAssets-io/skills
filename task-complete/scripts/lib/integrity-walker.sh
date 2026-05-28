#!/usr/bin/env bash
#
# integrity-walker.sh - Validate the user-flow chain:
#
#   FLOW -> related stories (US-*) -> implementing epic -> tasks ->
#   unit tests (per task) -> integration tests (per flow, once epic complete)
#
# Pure-function library: returns JSON, never blocks. Callers (task-complete.sh,
# /user-flow integrity) decide how to surface results.
#
# Output shape for every validate_* function:
#   {
#     "target":  "<id-or-label>",
#     "kind":    "task|epic|flow",
#     "grade":   "full|partial|missing",
#     "gaps":    [ "<gap_code>", ... ],
#     "details": [ {"code": "...", "message": "...", "location": "..."}, ... ]
#   }
#
# Gap codes (canonical):
#   no_unit_tests              - task has no unit_tests entry
#   no_integration_tests       - flow's Integration Tests is empty/None
#   no_flow_link               - epic has no user_flow field
#   flow_not_found             - referenced flow not in User-Flows.md
#   no_related_stories         - flow has no Related Stories
#   story_not_found            - referenced story not in UserStories.md
#   story_missing_backref      - story does not carry User Flow: FLOW-XXX
#   no_epic_link              - flow has no Implemented in epic
#   epic_not_found            - referenced epic not in ToDos.md
#   undischarged_cbc_claim     - task touches CbC-mandatory files with no
#                                discharged/waived evidence record (additive;
#                                only when cbc=mandatory git attributes exist)
#
# Dependencies: jq, bash 4+, user-flow-parser.sh, story-parser.sh, epic-parser.sh
#   (optional) cbc-ledger.sh for the undischarged_cbc_claim gap

if [[ -n "${INTEGRITY_WALKER_LOADED:-}" ]]; then
    return 0
fi
INTEGRITY_WALKER_LOADED=1

INTEGRITY_USER_FLOWS_FILE="${USER_FLOWS_FILE:-docs/User-Flows.md}"
INTEGRITY_USER_STORIES_FILE="${USER_STORIES_FILE:-docs/UserStories.md}"
INTEGRITY_TODOS_FILE="${TODOS_FILE:-docs/ToDos.md}"

# Optional CbC evidence ledger, for the additive undischarged_cbc_claim gap.
_INTEGRITY_WALKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || _INTEGRITY_WALKER_DIR="."
# shellcheck source=cbc-ledger.sh
[[ -f "$_INTEGRITY_WALKER_DIR/cbc-ledger.sh" ]] && source "$_INTEGRITY_WALKER_DIR/cbc-ledger.sh"

# Echo "yes" if any file (newline-separated on stdin) is tagged cbc=mandatory
# but lacks a discharged/waived evidence record; else "no". Additive + guarded:
# a no-op ("no") unless cbc=mandatory git attributes exist and git + the ledger
# are available, so existing chains are unaffected.
_iw_cbc_undischarged() {
    command -v git >/dev/null 2>&1 || { echo "no"; return 0; }
    git rev-parse --git-dir >/dev/null 2>&1 || { echo "no"; return 0; }
    declare -F cbc_ledger_status >/dev/null 2>&1 || { echo "no"; return 0; }
    local f st
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        if [[ "$(git check-attr cbc -- "$f" 2>/dev/null)" == *": cbc: mandatory" ]]; then
            st="$(cbc_ledger_status "$f" 2>/dev/null)"
            [[ "$st" == "discharged" || "$st" == "waived" ]] || { echo "yes"; return 0; }
        fi
    done
    echo "no"
}

# Build a JSON object literal from id/kind/grade and arrays of gaps/details.
_iw_make_result() {
    local target="$1" kind="$2" grade="$3"
    local gaps_json="$4" details_json="$5"
    jq -n \
        --arg target "$target" \
        --arg kind "$kind" \
        --arg grade "$grade" \
        --argjson gaps "$gaps_json" \
        --argjson details "$details_json" \
        '{target: $target, kind: $kind, grade: $grade, gaps: $gaps, details: $details}'
}

# Push a {code, message, location} triple into a details JSON array (string).
# Echoes back the updated JSON.
_iw_push_detail() {
    local current="$1" code="$2" message="$3" location="$4"
    echo "$current" | jq \
        --arg code "$code" \
        --arg message "$message" \
        --arg location "$location" \
        '. + [{code: $code, message: $message, location: $location}]'
}

# Echo back gaps array with $code appended (deduped).
_iw_push_gap() {
    local current="$1" code="$2"
    echo "$current" | jq --arg c "$code" '. + [$c] | unique'
}

# Decide the grade given a populated gaps array and a presence boolean.
# - missing: target not found / chain unreadable
# - full: zero gaps
# - partial: target exists, has gaps
_iw_grade_from() {
    local present="$1" gap_count="$2"
    if [[ "$present" != "true" ]]; then
        echo "missing"
    elif [[ "$gap_count" -eq 0 ]]; then
        echo "full"
    else
        echo "partial"
    fi
}

# -----------------------------------------------------------------------------
# Resolve the story -> User Flow back-reference from UserStories.md.
# Returns the FLOW-NNN id, or empty string if absent / file missing / parser absent.
# -----------------------------------------------------------------------------
_iw_story_flow_backref() {
    local story_id="$1"
    local stories_file="$2"
    [[ -f "$stories_file" ]] || { printf ''; return 0; }
    if ! declare -F get_story >/dev/null 2>&1; then
        printf ''
        return 0
    fi
    local story
    story=$(get_story "$story_id" "$stories_file" 2>/dev/null || echo "")
    if [[ -z "$story" || "$story" == "null" ]]; then
        printf ''
        return 0
    fi
    echo "$story" | jq -r '.user_flow // ""'
}

# -----------------------------------------------------------------------------
# validate_flow FLOW-XXX
# -----------------------------------------------------------------------------
validate_flow() {
    local flow_id="$1"
    local flows_file="${INTEGRITY_USER_FLOWS_FILE}"
    local stories_file="${INTEGRITY_USER_STORIES_FILE}"
    local todos_file="${INTEGRITY_TODOS_FILE}"

    local gaps='[]'
    local details='[]'
    local present="false"

    local flow
    flow=$(get_flow "$flow_id" "$flows_file" 2>/dev/null || echo "")
    if [[ -z "$flow" || "$flow" == "null" ]]; then
        details=$(_iw_push_detail "$details" "flow_not_found" "Flow ${flow_id} not in ${flows_file}" "$flows_file")
        gaps=$(_iw_push_gap "$gaps" "flow_not_found")
        _iw_make_result "$flow_id" "flow" "missing" "$gaps" "$details"
        return 0
    fi
    present="true"

    # Related stories present and resolvable
    local rs_count
    rs_count=$(echo "$flow" | jq '.related_stories | length')
    if [[ "$rs_count" -eq 0 ]]; then
        gaps=$(_iw_push_gap "$gaps" "no_related_stories")
        details=$(_iw_push_detail "$details" "no_related_stories" "Flow has no Related Stories" "$flows_file")
    else
        while IFS= read -r sid; do
            [[ -z "$sid" ]] && continue
            local backref
            backref=$(_iw_story_flow_backref "$sid" "$stories_file")
            if [[ -z "$backref" ]] && [[ -f "$stories_file" ]] && declare -F story_exists >/dev/null 2>&1; then
                if [[ "$(story_exists "$sid" "$stories_file" 2>/dev/null)" != "true" ]]; then
                    gaps=$(_iw_push_gap "$gaps" "story_not_found")
                    details=$(_iw_push_detail "$details" "story_not_found" "Story ${sid} referenced by ${flow_id} not in ${stories_file}" "$stories_file")
                    continue
                fi
            fi
            if [[ "$backref" != "$flow_id" ]]; then
                gaps=$(_iw_push_gap "$gaps" "story_missing_backref")
                details=$(_iw_push_detail "$details" "story_missing_backref" "Story ${sid} does not carry 'User Flow: ${flow_id}' back-reference" "$stories_file")
            fi
        done < <(echo "$flow" | jq -r '.related_stories[]')
    fi

    # Implemented-in epic
    local epic_id
    epic_id=$(echo "$flow" | jq -r '.implemented_in // ""')
    if [[ -z "$epic_id" || "$epic_id" == "Planned" || "$epic_id" == "null" ]]; then
        gaps=$(_iw_push_gap "$gaps" "no_epic_link")
        details=$(_iw_push_detail "$details" "no_epic_link" "Flow has no Implemented-in epic" "$flows_file")
    else
        if [[ -f "$todos_file" ]] && declare -F get_epic >/dev/null 2>&1; then
            local epic
            epic=$(get_epic "$epic_id" "$todos_file" 2>/dev/null || echo "")
            if [[ -z "$epic" || "$epic" == "null" ]]; then
                gaps=$(_iw_push_gap "$gaps" "epic_not_found")
                details=$(_iw_push_detail "$details" "epic_not_found" "Epic ${epic_id} referenced by ${flow_id} not in ${todos_file}" "$todos_file")
            else
                # Integration tests only required when the implementing epic is complete
                local epic_status
                epic_status=$(echo "$epic" | jq -r '.status // ""')
                if [[ "$epic_status" == "complete" ]]; then
                    local effective
                    effective=$(echo "$flow" | jq '[.integration_tests[] | select(. != "None" and . != "")] | length')
                    if [[ "$effective" -eq 0 ]]; then
                        gaps=$(_iw_push_gap "$gaps" "no_integration_tests")
                        details=$(_iw_push_detail "$details" "no_integration_tests" "Implementing epic ${epic_id} is complete but flow has no integration tests" "$flows_file")
                    fi
                fi
            fi
        fi
    fi

    local gap_count grade
    gap_count=$(echo "$gaps" | jq 'length')
    grade=$(_iw_grade_from "$present" "$gap_count")
    _iw_make_result "$flow_id" "flow" "$grade" "$gaps" "$details"
}

# -----------------------------------------------------------------------------
# validate_task TODO-XXX-NNN
# -----------------------------------------------------------------------------
validate_task() {
    local task_id="$1"
    local todos_file="${INTEGRITY_TODOS_FILE}"
    local flows_file="${INTEGRITY_USER_FLOWS_FILE}"

    local gaps='[]'
    local details='[]'
    local present="false"

    if [[ ! -f "$todos_file" ]] || ! declare -F parse_epics >/dev/null 2>&1; then
        details=$(_iw_push_detail "$details" "epic_not_found" "ToDos.md or epic parser unavailable" "$todos_file")
        _iw_make_result "$task_id" "task" "missing" "$gaps" "$details"
        return 0
    fi

    local all_epics
    all_epics=$(parse_epics "$todos_file")
    local owner
    owner=$(echo "$all_epics" | jq -c --arg tid "$task_id" '[.[] | select(.tasks[]?.id == $tid)][0] // null')
    if [[ "$owner" == "null" || -z "$owner" ]]; then
        details=$(_iw_push_detail "$details" "epic_not_found" "Task ${task_id} not found in any epic" "$todos_file")
        _iw_make_result "$task_id" "task" "missing" "$gaps" "$details"
        return 0
    fi
    present="true"

    local owner_epic_id
    owner_epic_id=$(echo "$owner" | jq -r '.epic_id')
    local task
    task=$(echo "$owner" | jq -c --arg tid "$task_id" '.tasks[] | select(.id == $tid)')

    # Unit tests
    local ut_count
    ut_count=$(echo "$task" | jq '.unit_tests // [] | length')
    if [[ "$ut_count" -eq 0 ]]; then
        gaps=$(_iw_push_gap "$gaps" "no_unit_tests")
        details=$(_iw_push_detail "$details" "no_unit_tests" "Task ${task_id} has no unit_tests entry" "$todos_file")
    fi

    # CbC discharge (additive; no-op unless cbc=mandatory git attributes exist)
    if [[ "$(echo "$task" | jq -r '.files // [] | .[]' 2>/dev/null | _iw_cbc_undischarged)" == "yes" ]]; then
        gaps=$(_iw_push_gap "$gaps" "undischarged_cbc_claim")
        details=$(_iw_push_detail "$details" "undischarged_cbc_claim" "Task ${task_id} touches CbC-mandatory files lacking a discharged/waived evidence record" "$todos_file")
    fi

    # Epic -> flow link
    local flow_id
    # `user_flow:` isn't a parser-recognized field on epic JSON, so re-read raw.
    # Dual-recognition: tolerate legacy "epoch_id:"/"EPOCH-NNN" in un-migrated
    # downstream repos (leaves non-EPIC ids such as FLAT-TASKS untouched).
    local _eid_pat="$owner_epic_id"
    [[ "$owner_epic_id" == EPIC-* ]] && _eid_pat="(EPIC|EPOCH)-${owner_epic_id#EPIC-}"
    flow_id=$(grep -E -A 30 "^(epic_id|epoch_id|id):[[:space:]]*${_eid_pat}\$" "$todos_file" 2>/dev/null \
        | grep -m1 '^user_flow:' | sed 's/^user_flow:[[:space:]]*//' | tr -d ' ')
    if [[ -z "$flow_id" ]]; then
        gaps=$(_iw_push_gap "$gaps" "no_flow_link")
        details=$(_iw_push_detail "$details" "no_flow_link" "Epic ${owner_epic_id} has no user_flow field" "$todos_file")
    else
        # Cascade flow-level gaps onto this task
        local flow_result
        flow_result=$(validate_flow "$flow_id")
        local flow_grade
        flow_grade=$(echo "$flow_result" | jq -r '.grade')
        if [[ "$flow_grade" == "missing" ]]; then
            gaps=$(_iw_push_gap "$gaps" "flow_not_found")
            details=$(_iw_push_detail "$details" "flow_not_found" "Epic ${owner_epic_id} references missing flow ${flow_id}" "$flows_file")
        elif [[ "$flow_grade" == "partial" ]]; then
            # Cascade the flow's chain gaps that affect this task's view of integrity
            while IFS= read -r code; do
                [[ -z "$code" ]] && continue
                case "$code" in
                    no_related_stories|story_not_found|story_missing_backref|no_epic_link|no_integration_tests)
                        gaps=$(_iw_push_gap "$gaps" "$code")
                        details=$(_iw_push_detail "$details" "$code" "Cascaded from flow ${flow_id}" "$flows_file")
                        ;;
                esac
            done < <(echo "$flow_result" | jq -r '.gaps[]')
        fi
    fi

    local gap_count grade
    gap_count=$(echo "$gaps" | jq 'length')
    grade=$(_iw_grade_from "$present" "$gap_count")
    _iw_make_result "$task_id" "task" "$grade" "$gaps" "$details"
}

# -----------------------------------------------------------------------------
# validate_epic EPIC-XXX
# -----------------------------------------------------------------------------
validate_epic() {
    local epic_id="$1"
    local todos_file="${INTEGRITY_TODOS_FILE}"
    local flows_file="${INTEGRITY_USER_FLOWS_FILE}"

    local gaps='[]'
    local details='[]'
    local present="false"

    if [[ ! -f "$todos_file" ]] || ! declare -F get_epic >/dev/null 2>&1; then
        details=$(_iw_push_detail "$details" "epic_not_found" "ToDos.md or epic parser unavailable" "$todos_file")
        _iw_make_result "$epic_id" "epic" "missing" "$gaps" "$details"
        return 0
    fi

    local epic
    epic=$(get_epic "$epic_id" "$todos_file" 2>/dev/null || echo "")
    if [[ -z "$epic" || "$epic" == "null" ]]; then
        details=$(_iw_push_detail "$details" "epic_not_found" "Epic ${epic_id} not in ${todos_file}" "$todos_file")
        _iw_make_result "$epic_id" "epic" "missing" "$gaps" "$details"
        return 0
    fi
    present="true"

    # Aggregate per-task gaps (deduped)
    while IFS= read -r tid; do
        [[ -z "$tid" ]] && continue
        local r
        r=$(validate_task "$tid")
        while IFS= read -r code; do
            [[ -z "$code" ]] && continue
            gaps=$(_iw_push_gap "$gaps" "$code")
        done < <(echo "$r" | jq -r '.gaps[]')
        # Carry over task-specific details with the originating task id
        while IFS= read -r dline; do
            [[ -z "$dline" ]] && continue
            local code message
            code=$(echo "$dline" | jq -r '.code')
            message=$(echo "$dline" | jq -r '.message')
            details=$(_iw_push_detail "$details" "$code" "[task ${tid}] ${message}" "$todos_file")
        done < <(echo "$r" | jq -c '.details[]')
    done < <(echo "$epic" | jq -r '.tasks[]?.id')

    # Flow link + integration test gate (only when all tasks are complete)
    local all_tasks_count complete_count
    all_tasks_count=$(echo "$epic" | jq '.tasks | length')
    complete_count=$(echo "$epic" | jq '[.tasks[] | select(.status == "complete")] | length')

    local flow_id
    # Dual-recognition: tolerate legacy "epoch_id:"/"EPOCH-NNN" (see validate above).
    local _eid_pat="$epic_id"
    [[ "$epic_id" == EPIC-* ]] && _eid_pat="(EPIC|EPOCH)-${epic_id#EPIC-}"
    flow_id=$(grep -E -A 30 "^(epic_id|epoch_id|id):[[:space:]]*${_eid_pat}\$" "$todos_file" 2>/dev/null \
        | grep -m1 '^user_flow:' | sed 's/^user_flow:[[:space:]]*//' | tr -d ' ')

    if [[ -z "$flow_id" ]]; then
        gaps=$(_iw_push_gap "$gaps" "no_flow_link")
        details=$(_iw_push_detail "$details" "no_flow_link" "Epic ${epic_id} has no user_flow field" "$todos_file")
    else
        local flow
        flow=$(get_flow "$flow_id" "$flows_file" 2>/dev/null || echo "")
        if [[ -z "$flow" || "$flow" == "null" ]]; then
            gaps=$(_iw_push_gap "$gaps" "flow_not_found")
            details=$(_iw_push_detail "$details" "flow_not_found" "Referenced flow ${flow_id} not in ${flows_file}" "$flows_file")
        elif [[ "$all_tasks_count" -gt 0 ]] && [[ "$complete_count" -eq "$all_tasks_count" ]]; then
            local effective
            effective=$(echo "$flow" | jq '[.integration_tests[] | select(. != "None" and . != "")] | length')
            if [[ "$effective" -eq 0 ]]; then
                gaps=$(_iw_push_gap "$gaps" "no_integration_tests")
                details=$(_iw_push_detail "$details" "no_integration_tests" "All tasks complete but flow ${flow_id} has no integration tests" "$flows_file")
            fi
        fi
    fi

    local gap_count grade
    gap_count=$(echo "$gaps" | jq 'length')
    grade=$(_iw_grade_from "$present" "$gap_count")
    _iw_make_result "$epic_id" "epic" "$grade" "$gaps" "$details"
}

# -----------------------------------------------------------------------------
# validate_all - walk every flow, every epic; return JSON array of results.
# -----------------------------------------------------------------------------
validate_all() {
    local flows_file="${INTEGRITY_USER_FLOWS_FILE}"
    local todos_file="${INTEGRITY_TODOS_FILE}"

    local out="["
    local first=true

    # Flows
    if [[ -f "$flows_file" ]] && declare -F parse_flows >/dev/null 2>&1; then
        while IFS= read -r fid; do
            [[ -z "$fid" ]] && continue
            local r
            r=$(validate_flow "$fid")
            if [[ "$first" == true ]]; then first=false; else out+=","; fi
            out+="$r"
        done < <(parse_flows "$flows_file" | jq -r '.[].id')
    fi

    # Epics
    if [[ -f "$todos_file" ]] && declare -F parse_epics >/dev/null 2>&1; then
        while IFS= read -r eid; do
            [[ -z "$eid" ]] && continue
            local r
            r=$(validate_epic "$eid")
            if [[ "$first" == true ]]; then first=false; else out+=","; fi
            out+="$r"
        done < <(parse_epics "$todos_file" | jq -r '.[].epic_id')
    fi

    out+="]"
    echo "$out"
}

# CLI dispatch when executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR_IW="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # Auto-load sibling parser libraries
    [[ -f "${SCRIPT_DIR_IW}/user-flow-parser.sh" ]] && source "${SCRIPT_DIR_IW}/user-flow-parser.sh"
    [[ -f "${SCRIPT_DIR_IW}/story-parser.sh" ]]     && source "${SCRIPT_DIR_IW}/story-parser.sh"
    [[ -f "${SCRIPT_DIR_IW}/epic-parser.sh" ]]     && source "${SCRIPT_DIR_IW}/epic-parser.sh"

    cmd="${1:-help}"
    case "$cmd" in
        flow)
            [[ -z "${2:-}" ]] && { echo "Usage: $0 flow FLOW-XXX" >&2; exit 1; }
            validate_flow "$2"
            ;;
        task)
            [[ -z "${2:-}" ]] && { echo "Usage: $0 task TODO-XXX-NNN" >&2; exit 1; }
            validate_task "$2"
            ;;
        epic)
            [[ -z "${2:-}" ]] && { echo "Usage: $0 epic EPIC-XXX" >&2; exit 1; }
            validate_epic "$2"
            ;;
        all)
            validate_all
            ;;
        help|--help|-h|*)
            cat <<EOF
integrity-walker.sh - Chain integrity validator

Usage: $0 <command> [args]

Commands:
  flow  FLOW-XXX              Validate a flow's chain
  task  TODO-XXX-NNN          Validate a task's chain
  epic EPIC-XXX             Validate an epic's chain
  all                         Validate everything (flows + epics)

Environment:
  USER_FLOWS_FILE             override docs/User-Flows.md
  USER_STORIES_FILE           override docs/UserStories.md
  TODOS_FILE                  override docs/ToDos.md

Output: JSON object {target, kind, grade, gaps, details} per target,
or JSON array of same for 'all'.
EOF
            ;;
    esac
fi
