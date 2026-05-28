#!/usr/bin/env bash
#
# user-flow-manager.sh - Manage user flows via command line
#
# Subcommands:
#   create                                       Three input modes (flag / --from-json / interactive wizard)
#   link FLOW-XXX <US|EPIC|ITEST|path>           Link a flow to a story, epic, or integration test
#   sync                                         Orphan report across flows, stories, epics, and tests
#   review [FLOW-XXX]                            Review one flow or summarize all
#   list                                         Enumerate all flows with status
#   test-spec FLOW-XXX [--out PATH] [--stdout]   Emit framework-agnostic test spec
#                                                Default: writes docs/test-specs/<FLOW-ID>.md and
#                                                auto-links it back into the flow's Integration Tests.
#                                                --stdout prints and skips file/link write.
#
# Dependencies: jq, bash 4+, user-flow-parser.sh, story-parser.sh, epic-parser.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
FLOW_PARSER="${LIB_DIR}/user-flow-parser.sh"
STORY_PARSER="${LIB_DIR}/story-parser.sh"
EPIC_PARSER="${LIB_DIR}/epic-parser.sh"
INTEGRITY_WALKER="${LIB_DIR}/integrity-walker.sh"

USER_FLOWS_FILE="${USER_FLOWS_FILE:-docs/User-Flows.md}"
USER_STORIES_FILE="${USER_STORIES_FILE:-docs/UserStories.md}"
TODOS_FILE="${TODOS_FILE:-docs/ToDos.md}"
NO_COLOR="${NO_COLOR:-}"
OUTPUT_WIDTH=64

EXIT_SUCCESS=0
EXIT_FLOW_NOT_FOUND=1
EXIT_TARGET_NOT_FOUND=2
EXIT_INVALID_ARGS=3
EXIT_FILE_NOT_WRITABLE=4
EXIT_ALREADY_LINKED=5

setup_colors() {
    if [[ -z "$NO_COLOR" ]] && [[ -t 1 ]]; then
        COLOR_RESET='\033[0m'
        COLOR_GREEN='\033[0;32m'
        COLOR_YELLOW='\033[0;33m'
        COLOR_RED='\033[0;31m'
        COLOR_BLUE='\033[0;34m'
        COLOR_CYAN='\033[0;36m'
        COLOR_BOLD='\033[1m'
        COLOR_DIM='\033[2m'
    else
        COLOR_RESET=''; COLOR_GREEN=''; COLOR_YELLOW=''; COLOR_RED=''
        COLOR_BLUE=''; COLOR_CYAN=''; COLOR_BOLD=''; COLOR_DIM=''
    fi
}

show_help() {
    cat <<EOF
user-flow-manager.sh - Manage user flows via command line

Usage: $(basename "$0") <subcommand> [arguments] [OPTIONS]

Subcommands:
  create                                          Create a new flow (flag / JSON / interactive)
  link FLOW-XXX <US|EPIC|ITEST|path>             Link a flow to a story, epic, or integration test
  sync                                            Orphan report (incl. flows missing tests after epic complete)
  review [FLOW-XXX]                               Review a flow or summarize all
  list                                            Enumerate all flows
  test-spec FLOW-XXX [--out PATH] [--stdout]      Emit Given/When/Then test spec
                                                  Default: writes docs/test-specs/<FLOW-ID>.md and
                                                  auto-links it back to the flow.
                                                  --stdout prints to stdout and skips file/link write.
  integrity [--task TID|--epic EID|--flow FID|--all] [--strict] [--json]
                                                  Chain integrity report. Grades each target as
                                                  full / partial / missing and lists any gaps.

Options:
  --no-color                          Disable colored output
  --help, -h                          Show this help

Create flags (non-interactive mode -- REQUIRED when no TTY):
  --title TEXT                Flow title
  --journey TEXT              One-line arrow path summary
  --persona TEXT              Persona (repeatable)
  --step "Name|description"   Step in 'Name|description' format (repeatable)
  --interaction TEXT          Key interaction (repeatable)
  --metric TEXT               Success metric (repeatable)
  --related-story US-XXX      Related story (repeatable)
  --related-flow FLOW-XXX     Related flow (repeatable)
  --from-json PATH            Load all fields from a JSON file (flags override)

JSON schema for --from-json:
  {
    "title": "string",
    "journey": "string",
    "personas": ["string", ...],
    "steps": [{"name": "string", "description": "string"}, ...],
    "key_interactions": ["string", ...],
    "success_metrics": ["string", ...],
    "related_stories": ["US-001", ...],
    "related_flows": ["FLOW-002", ...]
  }

Examples:
  $(basename "$0") create --title "Onboarding" --journey "Signup -> Verify -> Dashboard" \\
      --step "Signup|User submits email + password" \\
      --step "Verify|Confirm email link" \\
      --interaction "Email field validates format" \\
      --metric "Signup completes in <5min"

  $(basename "$0") link FLOW-001 US-010
  $(basename "$0") link FLOW-001 EPIC-014
  $(basename "$0") link FLOW-001 ITEST-001
  $(basename "$0") link FLOW-001 tests/e2e/onboarding.spec.ts
  $(basename "$0") sync
  $(basename "$0") review FLOW-001
  $(basename "$0") test-spec FLOW-001                          # writes docs/test-specs/FLOW-001.md and auto-links
  $(basename "$0") test-spec FLOW-001 --stdout                 # print only
  $(basename "$0") test-spec FLOW-001 --out path/to/spec.md    # custom output location

Exit Codes:
  0  Success
  1  Flow not found
  2  Target (story or epic) not found
  3  Invalid arguments
  4  File not writable
  5  Already linked

Environment:
  NO_COLOR             Disable colored output
  USER_FLOWS_FILE      Override default docs/User-Flows.md path
  USER_STORIES_FILE    Override default docs/UserStories.md path
  TODOS_FILE           Override default docs/ToDos.md path
EOF
}

load_libraries() {
    if [[ ! -f "$FLOW_PARSER" ]]; then
        echo "Error: user-flow-parser.sh not found at $FLOW_PARSER" >&2
        exit $EXIT_INVALID_ARGS
    fi
    # shellcheck source=lib/user-flow-parser.sh
    source "$FLOW_PARSER"
    if [[ -f "$STORY_PARSER" ]]; then
        # shellcheck source=lib/story-parser.sh
        source "$STORY_PARSER"
    fi
    if [[ -f "$EPIC_PARSER" ]]; then
        # shellcheck source=lib/epic-parser.sh
        source "$EPIC_PARSER"
    fi
    if [[ -f "$INTEGRITY_WALKER" ]]; then
        # shellcheck source=lib/integrity-walker.sh
        source "$INTEGRITY_WALKER"
    fi
}

draw_line() {
    local type="$1" width="${2:-$OUTPUT_WIDTH}"
    case "$type" in
        top|bottom) printf "+%s+\n" "$(printf '=%.0s' $(seq 1 $((width-2))))" ;;
        middle)     printf "+%s+\n" "$(printf -- '-%.0s' $(seq 1 $((width-2))))" ;;
    esac
}

draw_content() {
    local content="$1" width="${2:-$OUTPUT_WIDTH}"
    local inner_width=$((width - 4))
    if [[ ${#content} -gt $inner_width ]]; then
        content="${content:0:$((inner_width-3))}..."
    fi
    printf "| %-${inner_width}s |\n" "$content"
}

# Create the flows file from a template if missing.
ensure_flows_file() {
    if [[ -f "$USER_FLOWS_FILE" ]]; then
        return 0
    fi
    local dir
    dir=$(dirname "$USER_FLOWS_FILE")
    mkdir -p "$dir"
    cat > "$USER_FLOWS_FILE" <<'EOF'
---
doc_type: user_flows
version: "1.0"
---

# User Flows

Detailed user interaction patterns for this project. Each flow captures the
journey, ordered steps, key interactions (which become integration test
assertions), and success metrics (which become test budgets). Flows are
linked bidirectionally to user stories (`docs/UserStories.md`) and to
epics (`docs/ToDos.md`).

**Document Structure**
- User flows: this file (`docs/User-Flows.md`)
- User stories: `docs/UserStories.md`
- Implementation tracking: `docs/ToDos.md` (epics + tasks)

**Linkage**
- A flow lists `Related Stories` and an `Implemented in` epic
- Stories carry a `User Flow:` back-reference
- Epic YAML carries a `user_flow:` field
- Integration tests appear on the flow as `Integration Tests:` once authored
  (late-stage: written after the implementation epic completes and unit
  tests pass). Run `test-spec FLOW-XXX` to seed the artifact and `link
  FLOW-XXX <ITEST-NNN|path>` for subsequent additions.

---

## Personas

Add reusable persona definitions here (Name + one-line description) and
reference them by name from each flow's `Personas:` field.

---

## Core Workflows

<!-- Created flows are inserted above the "Planned Flows" section below. -->

---

## Planned Flows

(Empty)

---

## Related Documentation

- [User Stories](UserStories.md)
- [ToDos](ToDos.md)
EOF
}

# ---------------------------------------------------------------------------
# mode_create
# ---------------------------------------------------------------------------
mode_create() {
    load_libraries
    ensure_flows_file

    local title="" journey=""
    local personas=() steps=() interactions=() metrics=()
    local related_stories=() related_flows=()
    local from_json_path=""

    # Pass 1: capture --from-json path
    local i=0
    while [[ $i -lt ${#CREATE_ARGS[@]} ]]; do
        if [[ "${CREATE_ARGS[$i]}" == "--from-json" ]]; then
            i=$((i+1)); from_json_path="${CREATE_ARGS[$i]:-}"
        fi
        i=$((i+1))
    done

    if [[ -n "$from_json_path" ]]; then
        if [[ ! -f "$from_json_path" ]]; then
            echo "Error: --from-json path not found: $from_json_path" >&2
            exit $EXIT_INVALID_ARGS
        fi
        if ! jq empty "$from_json_path" 2>/dev/null; then
            echo "Error: --from-json file is not valid JSON: $from_json_path" >&2
            exit $EXIT_INVALID_ARGS
        fi
        title=$(jq -r '.title // ""' "$from_json_path")
        journey=$(jq -r '.journey // ""' "$from_json_path")
        while IFS= read -r line; do [[ -n "$line" ]] && personas+=("$line"); done < <(jq -r '.personas // [] | .[]' "$from_json_path")
        while IFS= read -r line; do [[ -n "$line" ]] && interactions+=("$line"); done < <(jq -r '.key_interactions // [] | .[]' "$from_json_path")
        while IFS= read -r line; do [[ -n "$line" ]] && metrics+=("$line"); done < <(jq -r '.success_metrics // [] | .[]' "$from_json_path")
        while IFS= read -r line; do [[ -n "$line" ]] && related_stories+=("$line"); done < <(jq -r '.related_stories // [] | .[]' "$from_json_path")
        while IFS= read -r line; do [[ -n "$line" ]] && related_flows+=("$line"); done < <(jq -r '.related_flows // [] | .[]' "$from_json_path")
        # Steps: array of {name, description}, joined as "name|description"
        while IFS= read -r line; do
            [[ -n "$line" ]] && steps+=("$line")
        done < <(jq -r '.steps // [] | .[] | "\(.name)|\(.description)"' "$from_json_path")
    fi

    # Pass 2: per-field flags (override JSON)
    i=0
    while [[ $i -lt ${#CREATE_ARGS[@]} ]]; do
        case "${CREATE_ARGS[$i]}" in
            --title)          i=$((i+1)); title="${CREATE_ARGS[$i]:-}" ;;
            --journey)        i=$((i+1)); journey="${CREATE_ARGS[$i]:-}" ;;
            --persona)        i=$((i+1)); personas+=("${CREATE_ARGS[$i]:-}") ;;
            --step)           i=$((i+1)); steps+=("${CREATE_ARGS[$i]:-}") ;;
            --interaction)    i=$((i+1)); interactions+=("${CREATE_ARGS[$i]:-}") ;;
            --metric)         i=$((i+1)); metrics+=("${CREATE_ARGS[$i]:-}") ;;
            --related-story)  i=$((i+1)); related_stories+=("${CREATE_ARGS[$i]:-}") ;;
            --related-flow)   i=$((i+1)); related_flows+=("${CREATE_ARGS[$i]:-}") ;;
            --from-json)      i=$((i+1)) ;;
        esac
        i=$((i+1))
    done

    # Decide interactive vs non-interactive
    local interactive=true
    if [[ -n "$title" ]] && [[ -n "$journey" ]] && [[ ${#steps[@]} -gt 0 ]]; then
        interactive=false
    elif [[ -n "$title" ]] || [[ -n "$journey" ]] || [[ ${#steps[@]} -gt 0 ]]; then
        if [[ ! -t 0 ]]; then
            echo "Error: Partial input provided but missing required fields." >&2
            echo "  When no TTY is available, --title, --journey, and at least one --step are required." >&2
            echo "  Received: title='${title}' journey='${journey}' steps=${#steps[@]}" >&2
            echo "" >&2
            echo "  Non-interactive template:" >&2
            echo "    $(basename "$0") create \\" >&2
            echo "      --title    \"<flow title>\" \\" >&2
            echo "      --journey  \"<step 1> -> <step 2> -> <step 3>\" \\" >&2
            echo "      --step     \"<Name>|<description>\" \\" >&2
            echo "      --step     \"<Name>|<description>\" \\" >&2
            echo "      --interaction \"<assertion-like detail>\" \\" >&2
            echo "      --metric   \"<budget-like detail>\"" >&2
            echo "" >&2
            echo "  Or supply a JSON file:" >&2
            echo "    $(basename "$0") create --from-json <path/to/flow.json>" >&2
            exit $EXIT_INVALID_ARGS
        fi
    elif [[ ! -t 0 ]]; then
        echo "Error: No TTY and no input flags supplied." >&2
        echo "  Use flag mode or --from-json instead. Run '$(basename "$0") create --help' for the schema." >&2
        echo "  Non-interactive template:" >&2
        echo "    $(basename "$0") create \\" >&2
        echo "      --title    \"<flow title>\" \\" >&2
        echo "      --journey  \"<step 1> -> <step 2> -> <step 3>\" \\" >&2
        echo "      --step     \"<Name>|<description>\" \\" >&2
        echo "      --step     \"<Name>|<description>\"" >&2
        exit $EXIT_INVALID_ARGS
    fi

    echo -e "${COLOR_BLUE}"
    draw_line "top"
    draw_content "Create New User Flow"
    draw_line "bottom"
    echo -e "${COLOR_RESET}"
    echo ""

    if [[ "$interactive" == true ]]; then
        if [[ -z "$title" ]]; then
            echo "Flow title (short, descriptive):"
            read -rp "> " title
        fi

        if [[ -z "$journey" ]]; then
            echo ""
            echo "Journey (one-line arrow path: 'Step A -> Step B -> Step C'):"
            read -rp "> " journey
        fi

        if [[ ${#personas[@]} -eq 0 ]]; then
            echo ""
            echo "Personas involved (comma-separated, or empty to skip):"
            read -rp "> " personas_csv
            if [[ -n "$personas_csv" ]]; then
                IFS=',' read -ra personas <<< "$personas_csv"
            fi
        fi

        if [[ ${#steps[@]} -eq 0 ]]; then
            echo ""
            echo "Steps -- enter as 'Name|description' (empty line to finish):"
            while true; do
                read -rp "> " step
                [[ -z "$step" ]] && break
                steps+=("$step")
            done
        fi

        if [[ ${#interactions[@]} -eq 0 ]]; then
            echo ""
            echo "Key Interactions (empty line to finish):"
            while true; do
                read -rp "> " item
                [[ -z "$item" ]] && break
                interactions+=("$item")
            done
        fi

        if [[ ${#metrics[@]} -eq 0 ]]; then
            echo ""
            echo "Success Metrics (empty line to finish):"
            while true; do
                read -rp "> " item
                [[ -z "$item" ]] && break
                metrics+=("$item")
            done
        fi

        if [[ ${#related_stories[@]} -eq 0 ]]; then
            echo ""
            echo "Related User Stories (comma-separated US-NNN list, empty to skip):"
            read -rp "> " rs_csv
            if [[ -n "$rs_csv" ]]; then
                IFS=',' read -ra related_stories <<< "$rs_csv"
            fi
        fi
    fi

    # Validate minimum content
    if [[ -z "$title" ]] || [[ -z "$journey" ]] || [[ ${#steps[@]} -eq 0 ]]; then
        echo "Error: title, journey, and at least one step are required." >&2
        exit $EXIT_INVALID_ARGS
    fi

    # Join a list of strings into ", "-separated CSV, skipping empty/whitespace
    # entries. Returns empty string when no real values are present, so callers
    # can branch on `-n` cleanly.
    local _join
    _join() {
        local -n _src=$1
        local out="" s
        for s in "${_src[@]:-}"; do
            s="${s## }"; s="${s%% }"
            [[ -z "$s" ]] && continue
            if [[ -z "$out" ]]; then out="$s"; else out+=", $s"; fi
        done
        printf '%s' "$out"
    }

    local rs_joined rf_joined p_joined
    rs_joined=$(_join related_stories)
    rf_joined=$(_join related_flows)
    p_joined=$(_join personas)

    local next_id
    next_id=$(get_next_flow_id "$USER_FLOWS_FILE")

    # Build markdown block. `\n` escapes are preserved because insert_flow uses
    # `echo -e` to write the block.
    local md=""
    md+="### ${next_id}: ${title}\n\n"
    md+="**Status:** Planned\n"
    md+="**Implemented in:** Planned\n"
    if [[ -n "$rs_joined" ]]; then
        md+="**Related Stories:** ${rs_joined}\n"
    else
        md+="**Related Stories:** None\n"
    fi
    if [[ -n "$rf_joined" ]]; then
        md+="**Related Flows:** ${rf_joined}\n"
    else
        md+="**Related Flows:** None\n"
    fi
    if [[ -n "$p_joined" ]]; then
        md+="**Personas:** ${p_joined}\n"
    fi
    md+="**Integration Tests:** None\n"
    md+="\n**Journey:** ${journey}\n\n"
    md+="**Steps:**\n"
    local n=1
    for step in "${steps[@]}"; do
        local sname="" sdesc=""
        if [[ "$step" == *"|"* ]]; then
            sname="${step%%|*}"
            sdesc="${step#*|}"
        else
            sname="$step"
        fi
        if [[ -n "$sname" ]] && [[ -n "$sdesc" ]]; then
            md+="${n}. **${sname}** - ${sdesc}\n"
        elif [[ -n "$sname" ]]; then
            md+="${n}. **${sname}**\n"
        else
            md+="${n}. ${sdesc}\n"
        fi
        n=$((n+1))
    done

    if [[ ${#interactions[@]} -gt 0 ]]; then
        md+="\n**Key Interactions:**\n"
        for item in "${interactions[@]}"; do
            md+="- ${item}\n"
        done
    fi

    if [[ ${#metrics[@]} -gt 0 ]]; then
        md+="\n**Success Metrics:**\n"
        for item in "${metrics[@]}"; do
            md+="- ${item}\n"
        done
    fi

    md+="\n---\n"

    insert_flow "$USER_FLOWS_FILE" "$md" "$next_id"

    echo ""
    echo -e "${COLOR_GREEN}"
    draw_line "top"
    draw_content "Flow Created: ${next_id}"
    draw_line "middle"
    draw_content "Title: ${title}"
    draw_content "Steps: ${#steps[@]}"
    draw_content "Location: ${USER_FLOWS_FILE}"
    draw_line "bottom"
    echo -e "${COLOR_RESET}"
}

# ---------------------------------------------------------------------------
# mode_link FLOW-XXX <US-YYY|EPIC-YYY>
# ---------------------------------------------------------------------------
mode_link() {
    local flow_id="$1"
    local target="$2"

    load_libraries

    if ! [[ "$flow_id" =~ ^FLOW-[0-9]{3,4}$ ]]; then
        echo "Error: Invalid flow ID format. Expected FLOW-NNN (e.g., FLOW-001)" >&2
        exit $EXIT_INVALID_ARGS
    fi

    if [[ "$(flow_exists "$flow_id" "$USER_FLOWS_FILE")" != "true" ]]; then
        echo "Error: Flow ${flow_id} not found in ${USER_FLOWS_FILE}" >&2
        exit $EXIT_FLOW_NOT_FOUND
    fi

    echo "Linking ${flow_id} to ${target}..."
    echo ""

    case "$target" in
        US-*)
            if ! [[ "$target" =~ ^US-[0-9]{3}$ ]]; then
                echo "Error: Invalid story ID format. Expected US-NNN" >&2
                exit $EXIT_INVALID_ARGS
            fi
            if [[ ! -f "$USER_STORIES_FILE" ]]; then
                echo "Error: ${USER_STORIES_FILE} not found" >&2
                exit $EXIT_TARGET_NOT_FOUND
            fi
            if declare -F story_exists >/dev/null 2>&1; then
                if [[ "$(story_exists "$target" "$USER_STORIES_FILE")" != "true" ]]; then
                    echo "Error: Story ${target} not found in ${USER_STORIES_FILE}" >&2
                    exit $EXIT_TARGET_NOT_FOUND
                fi
            fi

            add_story_to_flow "$flow_id" "$target" "$USER_FLOWS_FILE"
            echo "Updated ${USER_FLOWS_FILE}:"
            echo "  - ${flow_id}: Added story ${target} to Related Stories"

            if declare -F update_story_flow_link >/dev/null 2>&1; then
                update_story_flow_link "$target" "$flow_id" "$USER_STORIES_FILE"
                echo ""
                echo "Updated ${USER_STORIES_FILE}:"
                echo "  - ${target}: Added User Flow: ${flow_id}"
            else
                echo ""
                echo -e "${COLOR_YELLOW}Warning: update_story_flow_link helper not available in story-parser.sh${COLOR_RESET}"
                echo "  Skipped back-reference in ${USER_STORIES_FILE}."
            fi
            ;;
        EPIC-*)
            if ! [[ "$target" =~ ^EPIC-[0-9]{3,4}$ ]]; then
                echo "Error: Invalid epic ID format. Expected EPIC-NNN" >&2
                exit $EXIT_INVALID_ARGS
            fi
            if [[ ! -f "$TODOS_FILE" ]]; then
                echo "Error: ${TODOS_FILE} not found" >&2
                exit $EXIT_TARGET_NOT_FOUND
            fi
            if declare -F get_epic >/dev/null 2>&1; then
                local epic
                epic=$(get_epic "$target" "$TODOS_FILE")
                if [[ -z "$epic" ]] || [[ "$epic" == "null" ]]; then
                    echo "Error: Epic ${target} not found in ${TODOS_FILE}" >&2
                    exit $EXIT_TARGET_NOT_FOUND
                fi
            fi

            update_flow_epic_link "$flow_id" "$target" "$USER_FLOWS_FILE"
            echo "Updated ${USER_FLOWS_FILE}:"
            echo "  - ${flow_id}: Implemented in: ${target}"

            update_epic_flow_link "$target" "$flow_id" "$TODOS_FILE"
            echo ""
            echo "Updated ${TODOS_FILE}:"
            echo "  - ${target}: Added user_flow: ${flow_id}"
            ;;
        ITEST-*)
            if ! [[ "$target" =~ ^ITEST-[0-9]{3,4}$ ]]; then
                echo "Error: Invalid integration test ID format. Expected ITEST-NNN" >&2
                exit $EXIT_INVALID_ARGS
            fi
            add_integration_test_to_flow "$flow_id" "$target" "$USER_FLOWS_FILE"
            echo "Updated ${USER_FLOWS_FILE}:"
            echo "  - ${flow_id}: Added integration test ${target}"
            ;;
        *)
            # File-path branch: anything that does not match the ID prefixes
            # above is treated as a test artifact path. No existence check.
            if [[ "$target" =~ ^(US|EPIC|ITEST|FLOW)- ]]; then
                echo "Error: malformed ID '${target}'. Expected US-NNN, EPIC-NNN, or ITEST-NNN." >&2
                exit $EXIT_INVALID_ARGS
            fi
            if [[ -z "$target" ]]; then
                echo "Error: empty target" >&2
                exit $EXIT_INVALID_ARGS
            fi
            add_integration_test_to_flow "$flow_id" "$target" "$USER_FLOWS_FILE"
            echo "Updated ${USER_FLOWS_FILE}:"
            echo "  - ${flow_id}: Added integration test artifact ${target}"
            ;;
    esac

    echo ""
    echo -e "${COLOR_GREEN}* Link recorded${COLOR_RESET}"
}

# ---------------------------------------------------------------------------
# mode_sync
# ---------------------------------------------------------------------------
mode_sync() {
    load_libraries

    echo -e "${COLOR_BLUE}"
    draw_line "top"
    draw_content "User Flow Sync Report"
    draw_line "bottom"
    echo -e "${COLOR_RESET}"
    echo ""

    local flows_json
    flows_json=$(parse_flows "$USER_FLOWS_FILE")
    local total_flows linked_to_epic linked_to_story orphan_flows
    total_flows=$(echo "$flows_json" | jq 'length')
    linked_to_epic=$(echo "$flows_json" | jq '[.[] | select(.implemented_in != null and .implemented_in != "" and .implemented_in != "Planned")] | length')
    linked_to_story=$(echo "$flows_json" | jq '[.[] | select((.related_stories | length) > 0)] | length')
    orphan_flows=$(echo "$flows_json" | jq '[.[] | select((.implemented_in == null or .implemented_in == "" or .implemented_in == "Planned") and (.related_stories | length) == 0)] | length')

    echo "Flows: ${total_flows} total"
    echo "  Linked to epic: ${linked_to_epic}"
    echo "  Linked to story: ${linked_to_story}"
    echo "  Orphans (no story or epic): ${orphan_flows}"
    echo ""

    if [[ "$orphan_flows" -gt 0 ]]; then
        draw_line "middle"
        draw_content "Orphan Flows (no story or epic)"
        draw_line "middle"
        echo "$flows_json" | jq -r '.[] | select((.implemented_in == null or .implemented_in == "" or .implemented_in == "Planned") and (.related_stories | length) == 0) | "  \(.id)  \(.title)"'
        echo ""
    fi

    # Stories with no flow
    if [[ -f "$USER_STORIES_FILE" ]] && declare -F parse_stories >/dev/null 2>&1; then
        local stories_json linked_story_ids
        stories_json=$(parse_stories "$USER_STORIES_FILE")
        linked_story_ids=$(echo "$flows_json" | jq -r '[.[] | .related_stories[]] | unique | .[]' 2>/dev/null | sort -u || true)

        local stories_total
        stories_total=$(echo "$stories_json" | jq 'length')
        if [[ "$stories_total" -gt 0 ]]; then
            local missing
            missing=$(echo "$stories_json" | jq -r '.[] | .id' | while read -r sid; do
                if ! grep -qx "$sid" <<< "$linked_story_ids"; then
                    title=$(echo "$stories_json" | jq -r ".[] | select(.id == \"$sid\") | .title")
                    echo "  $sid  $title"
                fi
            done)
            if [[ -n "$missing" ]]; then
                draw_line "middle"
                draw_content "Stories Missing a User Flow"
                draw_line "middle"
                printf '%s\n' "$missing"
                echo ""
            fi
        fi
    fi

    # Epics with no flow
    if [[ -f "$TODOS_FILE" ]] && declare -F parse_epics >/dev/null 2>&1; then
        local epics_json
        epics_json=$(parse_epics "$TODOS_FILE")
        local linked_epic_ids
        linked_epic_ids=$(echo "$flows_json" | jq -r '.[] | select(.implemented_in != null and .implemented_in != "" and .implemented_in != "Planned") | .implemented_in' | sort -u)

        local missing
        missing=$(echo "$epics_json" | jq -r '.[] | .epic_id' | while read -r eid; do
            if ! grep -qx "$eid" <<< "$linked_epic_ids"; then
                etitle=$(echo "$epics_json" | jq -r ".[] | select(.epic_id == \"$eid\") | .title")
                echo "  $eid  $etitle"
            fi
        done)
        if [[ -n "$missing" ]]; then
            draw_line "middle"
            draw_content "Epics Missing a User Flow"
            draw_line "middle"
            printf '%s\n' "$missing"
            echo ""
        fi
    fi

    # Flows whose implementation epic is complete but have no integration tests yet
    if [[ -f "$TODOS_FILE" ]] && declare -F get_epic >/dev/null 2>&1; then
        local missing_tests=""
        # Iterate flows that have an epic link
        while IFS=$'\t' read -r fid eid ftitle; do
            [[ -z "$fid" || -z "$eid" || "$eid" == "Planned" || "$eid" == "null" ]] && continue
            local epic_obj epic_status
            epic_obj=$(get_epic "$eid" "$TODOS_FILE" 2>/dev/null || echo "")
            [[ -z "$epic_obj" || "$epic_obj" == "null" ]] && continue
            epic_status=$(echo "$epic_obj" | jq -r '.status // ""')
            if [[ "$epic_status" == "complete" ]]; then
                # Effective tests = items other than "None"/empty
                local effective
                effective=$(echo "$flows_json" | jq --arg id "$fid" '[.[] | select(.id == $id) | .integration_tests[] | select(. != "None" and . != "")] | length')
                if [[ "$effective" -eq 0 ]]; then
                    missing_tests+="  ${fid}  (epic ${eid}, complete)  ${ftitle}"$'\n'
                fi
            fi
        done < <(echo "$flows_json" | jq -r '.[] | select(.implemented_in != null and .implemented_in != "" and .implemented_in != "Planned") | "\(.id)\t\(.implemented_in)\t\(.title)"')

        if [[ -n "$missing_tests" ]]; then
            draw_line "middle"
            draw_content "Flows Missing Integration Tests"
            draw_line "middle"
            printf '%s' "$missing_tests"
            echo ""
            echo "  (Implementation epic is complete; author tests then run:"
            echo "   '/user-flow test-spec FLOW-XXX' or"
            echo "   '/user-flow link FLOW-XXX <ITEST-NNN|tests/.../file>')"
            echo ""
        fi
    fi

    echo "Run '/user-flow link FLOW-XXX <US-YYY|EPIC-YYY|ITEST-NNN|path>' to create links."
}

# ---------------------------------------------------------------------------
# mode_review
# ---------------------------------------------------------------------------
mode_review() {
    local flow_id="${1:-}"
    load_libraries

    if [[ -n "$flow_id" ]]; then
        review_single_flow "$flow_id"
    else
        review_all_flows
    fi
}

review_single_flow() {
    local flow_id="$1"

    if ! [[ "$flow_id" =~ ^FLOW-[0-9]{3,4}$ ]]; then
        echo "Error: Invalid flow ID format. Expected FLOW-NNN" >&2
        exit $EXIT_INVALID_ARGS
    fi

    local flow
    flow=$(get_flow "$flow_id" "$USER_FLOWS_FILE")
    if [[ -z "$flow" ]] || [[ "$flow" == "null" ]]; then
        echo "Error: Flow ${flow_id} not found in ${USER_FLOWS_FILE}" >&2
        exit $EXIT_FLOW_NOT_FOUND
    fi

    local title status implemented_in journey
    title=$(echo "$flow" | jq -r '.title // ""')
    status=$(echo "$flow" | jq -r '.status // "Planned"')
    implemented_in=$(echo "$flow" | jq -r '.implemented_in // ""')
    journey=$(echo "$flow" | jq -r '.journey // ""')

    echo -e "${COLOR_BLUE}"
    draw_line "top"
    draw_content "${flow_id}: ${title}"
    draw_line "bottom"
    echo -e "${COLOR_RESET}"
    echo ""

    [[ -n "$journey" ]] && echo "Journey: ${journey}" && echo ""

    draw_line "middle"
    draw_content "Status: ${status}"
    if [[ -n "$implemented_in" ]] && [[ "$implemented_in" != "Planned" ]]; then
        draw_content "Implemented in: ${implemented_in}"
    else
        draw_content "Implemented in: (none)"
    fi
    local rs_count rf_count p_count it_count
    rs_count=$(echo "$flow" | jq '.related_stories | length')
    rf_count=$(echo "$flow" | jq '.related_flows | length')
    p_count=$(echo "$flow" | jq '.personas | length')
    # Effective test count excludes the literal "None" placeholder
    it_count=$(echo "$flow" | jq '[.integration_tests[] | select(. != "None" and . != "")] | length')
    draw_content "Related Stories: ${rs_count}"
    draw_content "Related Flows: ${rf_count}"
    draw_content "Personas: ${p_count}"
    draw_content "Integration Tests: ${it_count}"
    draw_line "middle"

    if [[ "$rs_count" -gt 0 ]]; then
        draw_content "Related Stories:"
        echo "$flow" | jq -r '.related_stories[] | "    - \(.)"'
    fi

    if [[ "$it_count" -gt 0 ]]; then
        draw_content "Integration Tests:"
        echo "$flow" | jq -r '.integration_tests[] | select(. != "None" and . != "") | "    - \(.)"'
    fi

    local step_count
    step_count=$(echo "$flow" | jq '.steps | length')
    draw_content "Steps (${step_count}):"
    echo "$flow" | jq -r '.steps | to_entries[] | "    \(.key + 1). \(.value.name // "")  \(if .value.description != "" then "- " + .value.description else "" end)"'

    local ki_count
    ki_count=$(echo "$flow" | jq '.key_interactions | length')
    draw_content "Key Interactions (${ki_count}):"
    echo "$flow" | jq -r '.key_interactions[] | "    * \(.)"'

    local sm_count
    sm_count=$(echo "$flow" | jq '.success_metrics | length')
    draw_content "Success Metrics (${sm_count}):"
    echo "$flow" | jq -r '.success_metrics[] | "    * \(.)"'

    draw_line "bottom"
}

review_all_flows() {
    local flows_json
    flows_json=$(parse_flows "$USER_FLOWS_FILE")

    echo -e "${COLOR_BLUE}"
    draw_line "top"
    draw_content "User Flows Summary"
    draw_line "bottom"
    echo -e "${COLOR_RESET}"
    echo ""

    local total
    total=$(echo "$flows_json" | jq 'length')

    if [[ "$total" -eq 0 ]]; then
        echo "(no flows found in ${USER_FLOWS_FILE})"
        return 0
    fi

    echo "$flows_json" | jq -r '.[] | "\(.id)  \(.status // "Planned")  \(.title)"' | column -t -s '  ' 2>/dev/null || \
        echo "$flows_json" | jq -r '.[] | "\(.id)  \(.status // "Planned")  \(.title)"'

    echo ""
    draw_line "middle"
    echo "Total: ${total} flows"
}

# ---------------------------------------------------------------------------
# mode_list
# ---------------------------------------------------------------------------
mode_list() {
    load_libraries
    local flows_json
    flows_json=$(parse_flows "$USER_FLOWS_FILE")
    local total
    total=$(echo "$flows_json" | jq 'length')
    if [[ "$total" -eq 0 ]]; then
        echo "(no flows in ${USER_FLOWS_FILE})"
        return 0
    fi
    echo "$flows_json" | jq -r '.[] | "\(.id)\t\(.status)\t\(.implemented_in // "-")\t\(.title)"'
}

# ---------------------------------------------------------------------------
# mode_test_spec FLOW-XXX [--out PATH]
# ---------------------------------------------------------------------------
mode_test_spec() {
    local flow_id="$1"
    shift
    local out_path=""
    local stdout_mode=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --out)    shift; out_path="${1:-}" ;;
            --stdout) stdout_mode=true ;;
            *)        ;;
        esac
        shift || true
    done

    # Default output path when neither --stdout nor --out is given
    if [[ "$stdout_mode" == false ]] && [[ -z "$out_path" ]]; then
        out_path="docs/test-specs/${flow_id}.md"
    fi
    if [[ "$stdout_mode" == true ]]; then
        out_path=""
    fi

    load_libraries

    if ! [[ "$flow_id" =~ ^FLOW-[0-9]{3,4}$ ]]; then
        echo "Error: Invalid flow ID format. Expected FLOW-NNN" >&2
        exit $EXIT_INVALID_ARGS
    fi

    local flow
    flow=$(get_flow "$flow_id" "$USER_FLOWS_FILE")
    if [[ -z "$flow" ]] || [[ "$flow" == "null" ]]; then
        echo "Error: Flow ${flow_id} not found in ${USER_FLOWS_FILE}" >&2
        exit $EXIT_FLOW_NOT_FOUND
    fi

    local title journey
    title=$(echo "$flow" | jq -r '.title // ""')
    journey=$(echo "$flow" | jq -r '.journey // ""')

    # Build scenarios array: each step becomes {step, name, description, given, when, then}
    # Given = previous step's name (or "preconditions are met" for step 1)
    # When  = step description (verbatim)
    # Then  = first matching success metric, else first key interaction, else
    #         "the system advances to the next step"
    local scenarios_json
    scenarios_json=$(echo "$flow" | jq -c '
        .steps as $steps |
        .success_metrics as $metrics |
        .key_interactions as $ki |
        [range(0; $steps|length) as $i |
            ($steps[$i]) as $s |
            {
                step: ($i + 1),
                name: $s.name,
                description: $s.description,
                given: (if $i == 0 then "preconditions are met" else $steps[$i-1].name end),
                when: (if $s.description == "" then $s.name else $s.description end),
                then: (
                    if ($metrics|length) > $i then $metrics[$i]
                    elif ($ki|length) > $i then $ki[$i]
                    elif ($metrics|length) > 0 then $metrics[0]
                    elif ($ki|length) > 0 then $ki[0]
                    else "the system advances to the next step"
                    end
                )
            }
        ]
    ')

    # Budgets: parse each success metric into structured {raw, metric, op, value}
    # using a permissive heuristic. We never block on parse failure -- raw is
    # always preserved so the consumer has the original line.
    local budgets_json
    budgets_json=$(echo "$flow" | jq -c '
        .success_metrics |
        map({
            raw: .,
            parsed: (
                . as $m |
                # Detect comparison operator + numeric (with optional unit)
                ($m | capture("(?<op>[<>])\\s*(?<value>[0-9]+(?:\\.[0-9]+)?)(?<unit>[a-zA-Z%]*)";"x") // null)
            )
        })
    ')

    local assertions_json
    assertions_json=$(echo "$flow" | jq -c '.key_interactions')

    # Build the structured JSON output
    local spec_json
    spec_json=$(jq -n \
        --arg id "$flow_id" \
        --arg title "$title" \
        --arg journey "$journey" \
        --argjson scenarios "$scenarios_json" \
        --argjson budgets "$budgets_json" \
        --argjson assertions "$assertions_json" \
        '{
            flow_id: $id,
            title: $title,
            journey: $journey,
            scenarios: $scenarios,
            assertions: $assertions,
            budgets: $budgets
        }')

    # Build the Markdown rendering
    local md
    md="# Test Spec: ${flow_id} -- ${title}"$'\n\n'
    if [[ -n "$journey" ]]; then
        md+="**Journey:** ${journey}"$'\n\n'
    fi
    md+="## Scenarios"$'\n\n'
    md+=$(echo "$scenarios_json" | jq -r '
        .[] | "### Scenario \(.step): \(.name)\n\n- **Given:** \(.given)\n- **When:** \(.when)\n- **Then:** \(.then)\n"
    ')
    md+=$'\n\n## Assertions (from Key Interactions)\n\n'
    md+=$(echo "$assertions_json" | jq -r 'if length == 0 then "_(none captured)_" else .[] | "- assert: \(.)" end')
    md+=$'\n\n## Budgets (from Success Metrics)\n\n'
    md+=$(echo "$budgets_json" | jq -r '
        if length == 0 then "_(none captured)_"
        else .[] |
            if .parsed != null then
                "- budget: `\(.raw)`  _(parsed: op=\(.parsed.op // "?") value=\(.parsed.value // "?") unit=\(.parsed.unit // ""))_"
            else
                "- budget: `\(.raw)`"
            end
        end
    ')
    md+=$'\n\n## Machine-readable spec\n\n```json\n'
    md+="$(echo "$spec_json" | jq .)"
    md+=$'\n```\n'

    if [[ -n "$out_path" ]]; then
        local out_dir
        out_dir=$(dirname "$out_path")
        mkdir -p "$out_dir"
        printf '%s' "$md" > "$out_path"
        echo "Wrote test spec to: $out_path"
        # Auto-link the artifact back into the flow's Integration Tests field
        add_integration_test_to_flow "$flow_id" "$out_path" "$USER_FLOWS_FILE"
        echo "Linked ${out_path} into ${flow_id}'s Integration Tests"
    else
        printf '%s' "$md"
    fi
}

# ---------------------------------------------------------------------------
# mode_integrity [--task TID | --epic EID | --flow FID | --all] [--strict] [--json]
# ---------------------------------------------------------------------------
mode_integrity() {
    load_libraries

    local mode="all"
    local target=""
    local strict=false
    local as_json=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --task)   mode="task";  shift; target="${1:-}" ;;
            --epic)  mode="epic"; shift; target="${1:-}" ;;
            --flow)   mode="flow";  shift; target="${1:-}" ;;
            --all)    mode="all" ;;
            --strict) strict=true ;;
            --json)   as_json=true ;;
            *)        ;;
        esac
        shift || true
    done

    # Pin the env paths the walker reads
    INTEGRITY_USER_FLOWS_FILE="$USER_FLOWS_FILE"
    INTEGRITY_USER_STORIES_FILE="$USER_STORIES_FILE"
    INTEGRITY_TODOS_FILE="$TODOS_FILE"

    local result_json
    case "$mode" in
        task)
            [[ -z "$target" ]] && { echo "--task requires an id" >&2; exit $EXIT_INVALID_ARGS; }
            result_json=$(validate_task "$target")
            ;;
        epic)
            [[ -z "$target" ]] && { echo "--epic requires an id" >&2; exit $EXIT_INVALID_ARGS; }
            result_json=$(validate_epic "$target")
            ;;
        flow)
            [[ -z "$target" ]] && { echo "--flow requires an id" >&2; exit $EXIT_INVALID_ARGS; }
            result_json=$(validate_flow "$target")
            ;;
        all|*)
            result_json=$(validate_all)
            ;;
    esac

    if [[ "$as_json" == true ]]; then
        echo "$result_json" | jq .
    else
        render_integrity_human "$mode" "$result_json"
    fi

    # Exit code: 0 always, unless --strict and any gaps found
    if [[ "$strict" == true ]]; then
        local any_gaps
        if [[ "$mode" == "all" ]]; then
            any_gaps=$(echo "$result_json" | jq '[.[] | .gaps | length] | add // 0')
        else
            any_gaps=$(echo "$result_json" | jq '.gaps | length')
        fi
        if [[ "$any_gaps" -gt 0 ]]; then
            exit 1
        fi
    fi
    exit $EXIT_SUCCESS
}

render_integrity_human() {
    local mode="$1" payload="$2"

    echo -e "${COLOR_BLUE}"
    draw_line "top"
    draw_content "Integrity Report"
    draw_line "bottom"
    echo -e "${COLOR_RESET}"

    if [[ "$mode" == "all" ]]; then
        local total full partial missing
        total=$(echo "$payload" | jq 'length')
        full=$(echo "$payload" | jq '[.[] | select(.grade == "full")] | length')
        partial=$(echo "$payload" | jq '[.[] | select(.grade == "partial")] | length')
        missing=$(echo "$payload" | jq '[.[] | select(.grade == "missing")] | length')
        echo "Total targets: ${total}    full=${full}  partial=${partial}  missing=${missing}"
        echo ""
        echo "$payload" | jq -r '
            .[] |
            "\(.kind)\t\(.target)\t\(.grade)\t" +
            (if (.gaps | length) == 0 then "-" else (.gaps | join(",")) end)
        ' | column -t -s $'\t' 2>/dev/null || \
            echo "$payload" | jq -r '.[] | "\(.kind) \(.target) \(.grade) \(.gaps | join(","))"'
    else
        local target grade gap_count
        target=$(echo "$payload" | jq -r '.target')
        grade=$(echo "$payload" | jq -r '.grade')
        gap_count=$(echo "$payload" | jq '.gaps | length')
        echo "Target: ${target}"
        echo "Grade:  ${grade}"
        echo "Gaps:   ${gap_count}"
        if [[ "$gap_count" -gt 0 ]]; then
            echo ""
            echo "Details:"
            echo "$payload" | jq -r '.details[] | "  [\(.code)] \(.message)"'
        fi
    fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    setup_colors

    local subcommand=""
    local args=()
    CREATE_ARGS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help; exit $EXIT_SUCCESS
                ;;
            --no-color)
                NO_COLOR=1; setup_colors; shift
                ;;
            create|link|sync|review|list|test-spec|integrity)
                subcommand="$1"; shift
                while [[ $# -gt 0 ]]; do
                    if [[ "$1" == "--no-color" ]]; then
                        NO_COLOR=1; setup_colors; shift; continue
                    fi
                    args+=("$1")
                    CREATE_ARGS+=("$1")
                    shift
                done
                ;;
            *)
                echo "Unknown argument: $1" >&2
                echo "Run '$(basename "$0") --help' for usage" >&2
                exit $EXIT_INVALID_ARGS
                ;;
        esac
    done

    if [[ -z "$subcommand" ]]; then
        echo "Error: Missing subcommand" >&2
        echo "Run '$(basename "$0") --help' for usage" >&2
        exit $EXIT_INVALID_ARGS
    fi

    case "$subcommand" in
        create)
            mode_create
            ;;
        link)
            if [[ ${#args[@]} -lt 2 ]]; then
                echo "Error: link requires FLOW-XXX and a target (US-YYY or EPIC-YYY)" >&2
                exit $EXIT_INVALID_ARGS
            fi
            mode_link "${args[0]}" "${args[1]}"
            ;;
        sync)
            mode_sync
            ;;
        review)
            mode_review "${args[0]:-}"
            ;;
        list)
            mode_list
            ;;
        test-spec)
            if [[ ${#args[@]} -lt 1 ]]; then
                echo "Error: test-spec requires FLOW-XXX" >&2
                exit $EXIT_INVALID_ARGS
            fi
            mode_test_spec "${args[@]}"
            ;;
        integrity)
            mode_integrity "${args[@]}"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
