#!/usr/bin/env bash
#
# user-flow-parser.sh - Shared library for parsing user flows from docs/User-Flows.md
#
# Provides:
#   - parse_flows         Parse all flows into a JSON array
#   - get_flow            Get a single flow by ID
#   - flow_exists         Check if a flow ID exists
#   - get_next_flow_id    Compute next FLOW-NNN id
#   - get_flow_links      Enumerate flow -> epic links
#   - insert_flow         Insert a new flow block into the file
#   - update_flow_epic_link
#   - update_epic_flow_link
#   - add_story_to_flow
#   - get_flow_integration_tests
#   - add_integration_test_to_flow
#
# Flow markdown shape (h3 header, bold-key fields, bullet sections):
#
#   ### FLOW-001: Title
#
#   **Status:** Planned
#   **Implemented in:** Planned
#   **Related Stories:** US-001, US-002
#   **Related Flows:** FLOW-002
#   **Personas:** Alex, Jordan
#   **Integration Tests:** docs/test-specs/FLOW-001.md, tests/e2e/onboarding.spec.ts
#
#   **Journey:** Step A -> Step B -> Step C
#
#   **Steps:**
#   1. **Name** - description
#
#   **Key Interactions:**
#   - assertion text
#
#   **Success Metrics:**
#   - budget text
#
# Dependencies: jq, bash 4+
#

if [[ -n "${USER_FLOW_PARSER_LOADED:-}" ]]; then
    return 0
fi
USER_FLOW_PARSER_LOADED=1

DEFAULT_USER_FLOWS_FILE="docs/User-Flows.md"

# Escape a string for safe inclusion as a JSON string body (between quotes).
_uf_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/}"
    printf '%s' "$s"
}

# Convert a comma-separated list to a JSON array of strings, trimming whitespace.
_uf_csv_to_json_array() {
    local csv="$1"
    if [[ -z "$csv" ]]; then
        printf '[]'
        return 0
    fi
    local out="["
    local first=true
    local item
    local IFS=','
    for item in $csv; do
        item="${item## }"
        item="${item%% }"
        item="${item## }"
        item="${item%% }"
        [[ -z "$item" ]] && continue
        if [[ "$first" == true ]]; then first=false; else out+=","; fi
        out+="\"$(_uf_json_escape "$item")\""
    done
    out+="]"
    printf '%s' "$out"
}

# Parse all flows from User-Flows.md into a JSON array.
parse_flows() {
    local flows_file="${1:-$DEFAULT_USER_FLOWS_FILE}"
    if [[ ! -f "$flows_file" ]]; then
        echo "[]"
        return 0
    fi

    local flows_json="[" first_flow=true
    local in_flow=false
    local id="" title="" status="" implemented_in=""
    local related_stories="" related_flows="" personas="" journey=""
    local integration_tests=""
    local steps_json="[" steps_first=true
    local interactions_json="[" interactions_first=true
    local metrics_json="[" metrics_first=true
    local current_section=""
    local in_code_fence=false

    _emit_current_flow() {
        local obj="{"
        obj+="\"id\":\"$id\""
        obj+=",\"title\":\"$(_uf_json_escape "$title")\""
        obj+=",\"status\":\"$(_uf_json_escape "${status:-Planned}")\""
        if [[ -n "$implemented_in" ]]; then
            obj+=",\"implemented_in\":\"$(_uf_json_escape "$implemented_in")\""
        else
            obj+=",\"implemented_in\":null"
        fi
        obj+=",\"related_stories\":$(_uf_csv_to_json_array "$related_stories")"
        obj+=",\"related_flows\":$(_uf_csv_to_json_array "$related_flows")"
        obj+=",\"personas\":$(_uf_csv_to_json_array "$personas")"
        obj+=",\"integration_tests\":$(_uf_csv_to_json_array "$integration_tests")"
        obj+=",\"journey\":\"$(_uf_json_escape "$journey")\""
        obj+=",\"steps\":${steps_json}]"
        obj+=",\"key_interactions\":${interactions_json}]"
        obj+=",\"success_metrics\":${metrics_json}]"
        obj+="}"
        if [[ "$first_flow" == true ]]; then first_flow=false; else flows_json+=","; fi
        flows_json+="$obj"
    }

    _reset_flow_state() {
        id=""; title=""; status=""; implemented_in=""
        related_stories=""; related_flows=""; personas=""; journey=""
        integration_tests=""
        steps_json="["; steps_first=true
        interactions_json="["; interactions_first=true
        metrics_json="["; metrics_first=true
        current_section=""
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Track code fences so example markdown inside them is ignored.
        if [[ "$line" =~ ^\`\`\` ]]; then
            if [[ "$in_code_fence" == true ]]; then in_code_fence=false; else in_code_fence=true; fi
            continue
        fi
        [[ "$in_code_fence" == true ]] && continue

        # Flow header
        if [[ "$line" =~ ^###[[:space:]]+FLOW-([0-9]{3,4}):[[:space:]]*(.*)$ ]]; then
            if [[ "$in_flow" == true ]] && [[ -n "$id" ]]; then
                _emit_current_flow
            fi
            _reset_flow_state
            in_flow=true
            id="FLOW-${BASH_REMATCH[1]}"
            title="${BASH_REMATCH[2]}"
            continue
        fi

        # Any other h2/h3 header ends the current flow
        if [[ "$line" =~ ^###?[[:space:]] ]] && [[ "$in_flow" == true ]]; then
            _emit_current_flow
            in_flow=false
            _reset_flow_state
            continue
        fi

        [[ "$in_flow" == false ]] && continue

        # Field lines (bold key prefix)
        if [[ "$line" =~ ^\*\*Status:\*\*[[:space:]]*(.*)$ ]]; then
            status="${BASH_REMATCH[1]}"; current_section=""; continue
        fi
        if [[ "$line" =~ ^\*\*Implemented[[:space:]]+in:\*\*[[:space:]]*(.*)$ ]]; then
            implemented_in="${BASH_REMATCH[1]}"
            # Extract bare EPIC-XXX if linked
            if [[ "$implemented_in" =~ (EPIC-[0-9]{3,4}) ]]; then
                implemented_in="${BASH_REMATCH[1]}"
            fi
            current_section=""; continue
        fi
        if [[ "$line" =~ ^\*\*Related[[:space:]]+Stories:\*\*[[:space:]]*(.*)$ ]]; then
            related_stories="${BASH_REMATCH[1]}"; current_section=""; continue
        fi
        if [[ "$line" =~ ^\*\*Related[[:space:]]+Flows:\*\*[[:space:]]*(.*)$ ]]; then
            related_flows="${BASH_REMATCH[1]}"; current_section=""; continue
        fi
        if [[ "$line" =~ ^\*\*Personas:\*\*[[:space:]]*(.*)$ ]]; then
            personas="${BASH_REMATCH[1]}"; current_section=""; continue
        fi
        if [[ "$line" =~ ^\*\*Integration[[:space:]]+Tests:\*\*[[:space:]]*(.*)$ ]]; then
            integration_tests="${BASH_REMATCH[1]}"; current_section=""; continue
        fi
        if [[ "$line" =~ ^\*\*Journey:\*\*[[:space:]]*(.*)$ ]]; then
            journey="${BASH_REMATCH[1]}"; current_section=""; continue
        fi

        # Section openers
        if [[ "$line" =~ ^\*\*Steps:\*\* ]]; then
            current_section="steps"; continue
        fi
        if [[ "$line" =~ ^\*\*Key[[:space:]]+Interactions:\*\* ]]; then
            current_section="interactions"; continue
        fi
        if [[ "$line" =~ ^\*\*Success[[:space:]]+Metrics:\*\* ]]; then
            current_section="metrics"; continue
        fi

        # Bullet/numbered items inside the current section
        if [[ "$current_section" == "steps" ]]; then
            if [[ "$line" =~ ^[[:space:]]*[0-9]+\.[[:space:]]+(.*)$ ]]; then
                local raw="${BASH_REMATCH[1]}"
                local name="" desc=""
                if [[ "$raw" =~ ^\*\*([^*]+)\*\*[[:space:]]*-[[:space:]]*(.*)$ ]]; then
                    name="${BASH_REMATCH[1]}"; desc="${BASH_REMATCH[2]}"
                elif [[ "$raw" =~ ^\*\*([^*]+)\*\*[[:space:]]*$ ]]; then
                    name="${BASH_REMATCH[1]}"; desc=""
                else
                    name=""; desc="$raw"
                fi
                if [[ "$steps_first" == true ]]; then steps_first=false; else steps_json+=","; fi
                steps_json+="{\"name\":\"$(_uf_json_escape "$name")\",\"description\":\"$(_uf_json_escape "$desc")\"}"
                continue
            fi
        elif [[ "$current_section" == "interactions" ]]; then
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(.*)$ ]]; then
                local item="${BASH_REMATCH[1]}"
                if [[ "$interactions_first" == true ]]; then interactions_first=false; else interactions_json+=","; fi
                interactions_json+="\"$(_uf_json_escape "$item")\""
                continue
            fi
        elif [[ "$current_section" == "metrics" ]]; then
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(.*)$ ]]; then
                local item="${BASH_REMATCH[1]}"
                if [[ "$metrics_first" == true ]]; then metrics_first=false; else metrics_json+=","; fi
                metrics_json+="\"$(_uf_json_escape "$item")\""
                continue
            fi
        fi

        # Blank line or horizontal rule closes the current section but keeps flow open
        if [[ -z "$line" ]] || [[ "$line" == "---" ]]; then
            current_section=""
            continue
        fi
    done < "$flows_file"

    if [[ "$in_flow" == true ]] && [[ -n "$id" ]]; then
        _emit_current_flow
    fi

    flows_json+="]"
    printf '%s\n' "$flows_json"
}

get_flow() {
    local flow_id="$1"
    local flows_file="${2:-$DEFAULT_USER_FLOWS_FILE}"
    local flows
    flows=$(parse_flows "$flows_file")
    echo "$flows" | jq -r ".[] | select(.id == \"$flow_id\")"
}

flow_exists() {
    local flow_id="$1"
    local flows_file="${2:-$DEFAULT_USER_FLOWS_FILE}"
    local flow
    flow=$(get_flow "$flow_id" "$flows_file")
    if [[ -n "$flow" ]] && [[ "$flow" != "null" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

get_next_flow_id() {
    local flows_file="${1:-$DEFAULT_USER_FLOWS_FILE}"
    local flows
    flows=$(parse_flows "$flows_file")
    local max_num
    max_num=$(echo "$flows" | jq -r '[.[] | .id | ltrimstr("FLOW-") | tonumber] | max // 0')
    local next_num=$((max_num + 1))
    printf "FLOW-%03d" "$next_num"
}

get_flow_links() {
    local flows_file="${1:-$DEFAULT_USER_FLOWS_FILE}"
    local flows
    flows=$(parse_flows "$flows_file")
    echo "$flows" | jq '[.[] | select(.implemented_in != null and .implemented_in != "" and .implemented_in != "Planned") | {flow_id: .id, epic_id: .implemented_in}]'
}

# Insert a new flow block before "## Planned Flows" or "## Flow Template",
# else before the final "## Related Documentation", else at end.
# An anchor on the file's first line also falls through to the append path.
insert_flow() {
    local flows_file="$1"
    local flow_md="$2"
    local flow_id="$3"

    cp "$flows_file" "${flows_file}.bak"

    local insert_line
    insert_line=$(grep -n '^## Planned Flows\|^## Flow Template\|^## Related Documentation' "$flows_file" | head -1 | cut -d: -f1)

    # An anchor on line 1 leaves no room to insert above it: `head -n 0` is an
    # error on BSD/macOS head, and prepending would push the flow above the
    # document's opening section. Fall back to appending in that case.
    if [[ -n "$insert_line" ]] && (( insert_line > 1 )); then
        {
            head -n $((insert_line - 1)) "$flows_file"
            echo ""
            echo -e "$flow_md"
            tail -n +"$insert_line" "$flows_file"
        } > "${flows_file}.tmp"
        mv "${flows_file}.tmp" "$flows_file"
    else
        echo "" >> "$flows_file"
        echo -e "$flow_md" >> "$flows_file"
    fi
}

# Set the "Implemented in:" field on a flow.
update_flow_epic_link() {
    local flow_id="$1"
    local epic_id="$2"
    local flows_file="${3:-$DEFAULT_USER_FLOWS_FILE}"

    cp "$flows_file" "${flows_file}.bak"

    local in_flow=false
    local temp_file="${flows_file}.tmp"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^###[[:space:]]+${flow_id}: ]]; then
            in_flow=true
        elif [[ "$line" =~ ^###?[[:space:]] ]]; then
            in_flow=false
        fi

        if [[ "$in_flow" == true ]]; then
            if [[ "$line" =~ ^\*\*Implemented[[:space:]]+in:\*\* ]]; then
                echo "**Implemented in:** ${epic_id}"
                continue
            fi
            if [[ "$line" =~ ^\*\*Status:\*\*[[:space:]]*Planned ]]; then
                echo "**Status:** In Progress"
                continue
            fi
        fi

        echo "$line"
    done < "$flows_file" > "$temp_file"

    mv "$temp_file" "$flows_file"
}

# Append a story to a flow's "Related Stories:" field (deduped).
add_story_to_flow() {
    local flow_id="$1"
    local story_id="$2"
    local flows_file="${3:-$DEFAULT_USER_FLOWS_FILE}"

    cp "$flows_file" "${flows_file}.bak"

    local in_flow=false
    local found_field=false
    local temp_file="${flows_file}.tmp"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^###[[:space:]]+${flow_id}: ]]; then
            in_flow=true
            found_field=false
        elif [[ "$line" =~ ^###?[[:space:]] ]]; then
            # Closing the flow: if we never saw the field, inject before the header
            if [[ "$in_flow" == true ]] && [[ "$found_field" == false ]]; then
                echo "**Related Stories:** ${story_id}"
                echo ""
            fi
            in_flow=false
        fi

        if [[ "$in_flow" == true ]] && [[ "$line" =~ ^\*\*Related[[:space:]]+Stories:\*\*[[:space:]]*(.*)$ ]]; then
            local existing="${BASH_REMATCH[1]}"
            found_field=true
            if [[ ",${existing// /}," == *",${story_id},"* ]]; then
                echo "$line"
            elif [[ -z "$existing" ]] || [[ "$existing" == "None" ]] || [[ "$existing" == "(none)" ]]; then
                echo "**Related Stories:** ${story_id}"
            else
                echo "**Related Stories:** ${existing}, ${story_id}"
            fi
            continue
        fi

        echo "$line"
    done < "$flows_file" > "$temp_file"

    # Handle the case where flow is the last block in the file
    if [[ "$in_flow" == true ]] && [[ "$found_field" == false ]]; then
        echo "**Related Stories:** ${story_id}" >> "$temp_file"
    fi

    mv "$temp_file" "$flows_file"
}

# Return a flow's integration_tests list as a JSON array.
get_flow_integration_tests() {
    local flow_id="$1"
    local flows_file="${2:-$DEFAULT_USER_FLOWS_FILE}"
    local flow
    flow=$(get_flow "$flow_id" "$flows_file")
    if [[ -z "$flow" ]] || [[ "$flow" == "null" ]]; then
        echo "[]"
        return 0
    fi
    echo "$flow" | jq -c '.integration_tests // []'
}

# Append a test artifact (path or ITEST-NNN) to a flow's "Integration Tests:"
# field, deduped. Replaces the literal "None" placeholder, and injects the
# field if it is missing from an older flow.
add_integration_test_to_flow() {
    local flow_id="$1"
    local artifact="$2"
    local flows_file="${3:-$DEFAULT_USER_FLOWS_FILE}"

    # Trim whitespace
    artifact="${artifact## }"; artifact="${artifact%% }"
    if [[ -z "$artifact" ]]; then
        return 0
    fi

    cp "$flows_file" "${flows_file}.bak"

    local in_flow=false
    local found_field=false
    local temp_file="${flows_file}.tmp"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^###[[:space:]]+${flow_id}: ]]; then
            in_flow=true
            found_field=false
        elif [[ "$line" =~ ^###?[[:space:]] ]]; then
            if [[ "$in_flow" == true ]] && [[ "$found_field" == false ]]; then
                echo "**Integration Tests:** ${artifact}"
                echo ""
            fi
            in_flow=false
        fi

        if [[ "$in_flow" == true ]] && [[ "$line" =~ ^\*\*Integration[[:space:]]+Tests:\*\*[[:space:]]*(.*)$ ]]; then
            local existing="${BASH_REMATCH[1]}"
            found_field=true
            # Strict dedupe: split CSV, compare item-by-item
            local already=false
            local IFS=','
            for it in $existing; do
                it="${it## }"; it="${it%% }"
                if [[ "$it" == "$artifact" ]]; then already=true; break; fi
            done
            unset IFS
            if [[ "$already" == true ]]; then
                echo "$line"
            elif [[ -z "$existing" ]] || [[ "$existing" == "None" ]] || [[ "$existing" == "(none)" ]]; then
                echo "**Integration Tests:** ${artifact}"
            else
                echo "**Integration Tests:** ${existing}, ${artifact}"
            fi
            continue
        fi

        echo "$line"
    done < "$flows_file" > "$temp_file"

    # Flow is last block in file and field was never seen
    if [[ "$in_flow" == true ]] && [[ "$found_field" == false ]]; then
        echo "**Integration Tests:** ${artifact}" >> "$temp_file"
    fi

    mv "$temp_file" "$flows_file"
}

# Write user_flow: <flow_id> into the matching epic's YAML block in ToDos.md.
# Mirrors update_epic_story_link from story-parser.sh but for the user_flow field.
update_epic_flow_link() {
    local epic_id="$1"
    local flow_id="$2"
    local todos_file="${3:-docs/ToDos.md}"

    cp "$todos_file" "${todos_file}.bak"

    local in_yaml=false
    local in_target=false
    local added=false
    local temp_file="${todos_file}.tmp"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == '```yaml' ]]; then
            in_yaml=true; echo "$line"; continue
        fi
        if [[ "$line" == '```' ]] && [[ "$in_yaml" == true ]]; then
            if [[ "$in_target" == true ]] && [[ "$added" == false ]]; then
                echo "user_flow: ${flow_id}"
                added=true
            fi
            in_yaml=false; in_target=false
            echo "$line"
            continue
        fi

        if [[ "$in_yaml" == true ]]; then
            if [[ "$line" =~ ^epic_id:[[:space:]]*${epic_id}$ ]]; then
                in_target=true
            fi
            if [[ "$in_target" == true ]] && [[ "$line" =~ ^user_flow: ]]; then
                echo "user_flow: ${flow_id}"
                added=true
                continue
            fi
            if [[ "$in_target" == true ]] && [[ "$line" =~ ^tasks: ]] && [[ "$added" == false ]]; then
                echo "user_flow: ${flow_id}"
                added=true
            fi
        fi

        echo "$line"
    done < "$todos_file" > "$temp_file"

    mv "$temp_file" "$todos_file"
}

# CLI dispatcher when executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    COMMAND="${1:-help}"
    case "$COMMAND" in
        parse|flows)
            parse_flows "${2:-$DEFAULT_USER_FLOWS_FILE}"
            ;;
        get-flow)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 get-flow FLOW-XXX [file]" >&2; exit 1
            fi
            get_flow "$2" "${3:-$DEFAULT_USER_FLOWS_FILE}"
            ;;
        exists)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 exists FLOW-XXX [file]" >&2; exit 1
            fi
            flow_exists "$2" "${3:-$DEFAULT_USER_FLOWS_FILE}"
            ;;
        next-id)
            get_next_flow_id "${2:-$DEFAULT_USER_FLOWS_FILE}"
            ;;
        links)
            get_flow_links "${2:-$DEFAULT_USER_FLOWS_FILE}"
            ;;
        get-tests)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 get-tests FLOW-XXX [file]" >&2; exit 1
            fi
            get_flow_integration_tests "$2" "${3:-$DEFAULT_USER_FLOWS_FILE}"
            ;;
        add-test)
            if [[ -z "${2:-}" ]] || [[ -z "${3:-}" ]]; then
                echo "Usage: $0 add-test FLOW-XXX <artifact> [file]" >&2; exit 1
            fi
            add_integration_test_to_flow "$2" "$3" "${4:-$DEFAULT_USER_FLOWS_FILE}"
            ;;
        help|--help|-h)
            cat <<EOF
user-flow-parser.sh - Parse user flows from docs/User-Flows.md

Usage: $0 <command> [args]

Commands:
  parse [file]                       Parse all flows, output JSON array
  get-flow ID [file]                 Get specific flow by ID
  exists ID [file]                   Check if flow exists (true/false)
  next-id [file]                     Compute next available FLOW-NNN id
  links [file]                       List flow -> epic links
  get-tests FLOW-XXX [file]          Get integration_tests JSON array for a flow
  add-test FLOW-XXX <artifact> [file] Append a test artifact to a flow's field
  help                               Show this help

Default file: docs/User-Flows.md
EOF
            ;;
        *)
            echo "Unknown command: $COMMAND" >&2
            echo "Run '$0 help' for usage" >&2
            exit 1
            ;;
    esac
fi
