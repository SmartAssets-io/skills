#!/usr/bin/env bash
#
# epic-parser.sh - Shared library for parsing epic/task YAML from docs/ToDos.md
#
# This library provides functions to:
# 1. Parse epic YAML blocks from markdown files
# 2. Extract nested task arrays within epics
# 3. Output structured JSON for use by slash commands
# 4. Derive epic status from task states
# 5. Handle epic and task sequencing
#
# Usage:
#   source /path/to/epic-parser.sh
#   parse_epics "docs/ToDos.md"
#   get_epic "EPIC-011" "docs/ToDos.md"
#   get_next_task "docs/ToDos.md"
#
# Dependencies:
#   - jq (required for JSON manipulation)
#   - bash 4+ (for associative arrays)
#
# Note: This script avoids yq dependency by using regex/awk for YAML parsing

# Prevent re-sourcing
if [[ -n "${EPIC_PARSER_LOADED:-}" ]]; then
    return 0
fi
EPIC_PARSER_LOADED=1

# Default file path
DEFAULT_TODOS_FILE="docs/ToDos.md"

# Priority order mapping (lower is higher priority)
declare -A PRIORITY_ORDER=(
    ["p0"]=0
    ["p1"]=1
    ["p2"]=2
    ["p3"]=3
)

# Status values
VALID_STATUSES="pending|in_progress|complete|blocked"

# Priority values (matches PRIORITY_ORDER above; declared here for vocabulary checks)
VALID_PRIORITIES="p0|p1|p2|p3"

# Strict-mode default. When enabled, parse_single_task / parse_epic_block /
# parse_epics hard-fail on non-canonical status or priority values (e.g.
# legacy "done" / "active" / "planned" / "completed") instead of silently
# letting them flow through and being treated as pending downstream.
#
# Migration escape hatch: set BF_TODO_PARSER_STRICT=0 to revert to permissive
# parsing while a workspace is being normalized. Validators (validate_epics /
# validate_strict) override this internally so they can still see drift.
BF_TODO_PARSER_STRICT="${BF_TODO_PARSER_STRICT:-1}"

# Strict-mode propagation marker. parse_single_task is normally called via
# command substitution ($(...)), so a plain `exit 1` from inside only kills
# the subshell — the CLI dispatch above keeps running and exits 0. The
# subshell touches this marker on strict-fail so the top-level CLI block can
# see it post-dispatch and exit 1. Tied to $$ so concurrent invocations don't
# collide.
EPIC_PARSER_STRICT_MARKER="${TMPDIR:-/tmp}/.epic-parser-strict-$$"

#
# Strict vocabulary check.
# Exits the parser with code 1 when a non-canonical value is seen and strict
# mode is on. Empty values are intentionally allowed here — defaulting via
# ${status:-pending} / ${priority:-p2} handles missing fields; this only bites
# unknown values that would otherwise pass through unrecognized.
#
# Args:
#   $1 kind  - "status" or "priority"
#   $2 value - raw value extracted from YAML
#   $3 where - human-readable location (e.g. "task TODO-001" or "epic EPIC-001")
#
_strict_check_value() {
    local kind="$1"
    local value="$2"
    local where="$3"

    [[ "${BF_TODO_PARSER_STRICT:-1}" == "1" ]] || return 0
    [[ -n "$value" ]] || return 0

    local valid_pattern valid_list
    case "$kind" in
        status)   valid_pattern="^($VALID_STATUSES)$"   ; valid_list="$VALID_STATUSES" ;;
        priority) valid_pattern="^($VALID_PRIORITIES)$" ; valid_list="$VALID_PRIORITIES" ;;
        *) return 0 ;;
    esac

    if [[ ! "$value" =~ $valid_pattern ]]; then
        {
            echo "epic-parser: strict mode: invalid $kind \"$value\" on $where"
            echo "  valid: ${valid_list//|/, }"
            echo "  set BF_TODO_PARSER_STRICT=0 to bypass during migration"
        } >&2
        : > "$EPIC_PARSER_STRICT_MARKER" 2>/dev/null || true
        exit 1
    fi
}

#
# Extract all YAML fenced code blocks from a markdown file
# Output: YAML blocks separated by ---BLOCK_END--- markers
#
extract_yaml_blocks() {
    local file="$1"
    local in_yaml=false
    local yaml_content=""

    if [[ ! -f "$file" ]]; then
        echo "Error: File not found: $file" >&2
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == '```yaml' ]]; then
            in_yaml=true
            yaml_content=""
        elif [[ "$line" == '```' ]] && [[ "$in_yaml" == true ]]; then
            in_yaml=false
            echo "$yaml_content"
            echo "---BLOCK_END---"
        elif [[ "$in_yaml" == true ]]; then
            # Dual-recognition: canonicalize legacy "Epoch"-era tokens to the
            # current "Epic" vocabulary so repositories that have not yet
            # migrated their docs/ToDos.md (EPOCH-NNN ids, epoch_id: field)
            # continue to parse. This repo emits EPIC exclusively; the
            # normalization is a no-op here and only matters downstream.
            line="${line//EPOCH-/EPIC-}"
            line="${line//epoch_id:/epic_id:}"
            yaml_content+="$line"$'\n'
        fi
    done < "$file"
}

#
# Check if a YAML block is an epic definition
# Supports both formats:
#   - id: EPIC-XXX (satchelUX format)
#   - epic_id: EPIC-XXX (legacy format)
# Filters out template/example blocks (EPIC-XXX, EPIC-NNN, etc.)
# Input: YAML text
# Output: "true" or "false"
#
is_epic_block() {
    local yaml="$1"
    # Check for either format: "id: EPIC-" or "epic_id: EPIC-"
    if echo "$yaml" | grep -qE '^id:[[:space:]]*EPIC-'; then
        # Filter out template/example epics (XXX, NNN, YYY patterns)
        if echo "$yaml" | grep -qE '^id:[[:space:]]*EPIC-(XXX|NNN|YYY)'; then
            echo "false"
            return
        fi
        echo "true"
        return
    fi
    if echo "$yaml" | grep -qE '^epic_id:[[:space:]]*EPIC-'; then
        # Filter out template/example epics (XXX, NNN, YYY patterns)
        if echo "$yaml" | grep -qE '^epic_id:[[:space:]]*EPIC-(XXX|NNN|YYY)'; then
            echo "false"
            return
        fi
        echo "true"
        return
    fi
    echo "false"
}

#
# Check if a YAML block is a flat task (has id: but not epic_id: or tasks:)
# Used for repos with simple task-per-block format
# Input: YAML text
# Output: "true" or "false"
#
is_flat_task_block() {
    local yaml="$1"
    # Must have id field
    if ! echo "$yaml" | grep -qE '^id:'; then
        echo "false"
        return
    fi
    # Must NOT have epic_id (that's an epic, not a flat task)
    if echo "$yaml" | grep -qE '^epic_id:'; then
        echo "false"
        return
    fi
    # Must NOT have id: EPIC- (that's an epic in satchelUX format)
    if echo "$yaml" | grep -qE '^id:[[:space:]]*EPIC-'; then
        echo "false"
        return
    fi
    # Must NOT have tasks: array (that's an epic structure)
    if echo "$yaml" | grep -qE '^tasks:'; then
        echo "false"
        return
    fi
    # Filter out template IDs (XXX, NNN patterns)
    if echo "$yaml" | grep -qE '^id:[[:space:]]*(TODO|TASK|XXX|NNN)-'; then
        local id_val
        id_val=$(echo "$yaml" | grep -E '^id:' | head -1 | sed 's/^id:[[:space:]]*//')
        if [[ "$id_val" =~ (XXX|NNN|YYY) ]]; then
            echo "false"
            return
        fi
    fi
    echo "true"
}

#
# Extract --- delimited blocks from within YAML content
# Used for flat task format where tasks are separated by ---
# Input: YAML content (from inside a code fence)
# Output: Individual blocks separated by ---BLOCK_END--- markers
#
extract_delimited_blocks() {
    local yaml="$1"
    local current_block=""
    local in_block=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comment lines and empty lines before first block
        if [[ "$line" =~ ^#.*$ ]] && [[ "$in_block" == false ]]; then
            continue
        fi

        # Block delimiter
        if [[ "$line" == "---" ]]; then
            if [[ "$in_block" == true ]] && [[ -n "$current_block" ]]; then
                echo "$current_block"
                echo "---BLOCK_END---"
            fi
            in_block=true
            current_block=""
            continue
        fi

        if [[ "$in_block" == true ]]; then
            current_block+="$line"$'\n'
        fi
    done <<< "$yaml"

    # Output final block if exists
    if [[ -n "$current_block" ]]; then
        echo "$current_block"
        echo "---BLOCK_END---"
    fi
}

#
# Extract a simple field value from YAML (top-level only)
# Usage: extract_field "yaml_text" "field_name"
#
extract_field() {
    local yaml="$1"
    local field="$2"
    echo "$yaml" | grep -E "^${field}:" | sed "s/^${field}:[[:space:]]*//" | tr -d '"' | head -1
}

#
# Extract task ID references from epic's tasks: array
# satchelUX format: tasks contain ID references like "- SATCHEL-WDK-001 (description)"
# Input: YAML text containing tasks: array
# Output: Space-separated list of task IDs
#
extract_task_refs() {
    local yaml="$1"
    local in_tasks=false
    local task_ids=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^tasks: ]]; then
            # Handle inline array format: tasks: [TODO-001, TODO-002, ...]
            local inline
            inline=$(echo "$line" | sed -n 's/^tasks:[[:space:]]*\[//p')
            if [[ -n "$inline" ]]; then
                # Strip trailing bracket, split on commas, extract IDs
                inline="${inline%%]*}"
                local id
                for id in $(echo "$inline" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'); do
                    if [[ "$id" =~ ^[A-Z][A-Za-z0-9_-]+ ]]; then
                        task_ids+="${BASH_REMATCH[0]} "
                    fi
                done
                break
            fi
            in_tasks=true
            continue
        fi
        if [[ "$in_tasks" == true ]]; then
            # Exit tasks section on unindented line
            if [[ "$line" =~ ^[a-zA-Z] ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
                break
            fi
            # Extract task ID from "  - TASK-ID (description)" or "  - TASK-ID"
            # Use sed for portable extraction
            local task_id
            task_id=$(echo "$line" | sed -n 's/^[[:space:]]*-[[:space:]]*\([A-Z][A-Z0-9_-]*\).*/\1/p')
            if [[ -n "$task_id" ]]; then
                task_ids+="$task_id "
            fi
        fi
    done <<< "$yaml"

    echo "$task_ids"
}

#
# Parse the tasks array from an epic YAML block
# Input: YAML text containing tasks: array
# Output: JSON array of task objects
#
# YAML structure expected:
#   tasks:
#     - id: XXX        <- task list item (2 spaces before dash)
#       title: ...     <- task field (4 spaces)
#       description: | <- multiline field
#         content      <- multiline content (6+ spaces)
#         - bullet     <- bullet in content (6+ spaces, NOT a new task)
#
parse_tasks_array() {
    local yaml="$1"
    local in_tasks=false
    local current_task=""
    local tasks_json="["
    local first_task=true
    local task_list_indent=-1  # Indent level of "  - " task items

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Detect start of tasks array
        if [[ "$line" =~ ^tasks: ]]; then
            in_tasks=true
            continue
        fi

        if [[ "$in_tasks" == true ]]; then
            # Check if we've exited the tasks array (non-indented, non-empty line)
            if [[ "$line" =~ ^[a-zA-Z] ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
                in_tasks=false
                # Output final task if we have one
                if [[ -n "$current_task" ]]; then
                    local task_json
                    task_json=$(parse_single_task "$current_task")
                    if [[ -n "$task_json" ]] && [[ "$task_json" != "null" ]]; then
                        if [[ "$first_task" == true ]]; then
                            first_task=false
                        else
                            tasks_json+=","
                        fi
                        tasks_json+="$task_json"
                    fi
                fi
                break
            fi

            # Calculate current line's indent (number of leading spaces)
            local stripped="${line#"${line%%[![:space:]]*}"}"
            local indent=$((${#line} - ${#stripped}))

            # New task item: matches "  - " pattern at the task list indent level
            # First task establishes the indent level
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]][a-zA-Z] ]]; then
                # Check if this is at the correct indent level for task items
                if [[ $task_list_indent -eq -1 ]]; then
                    # First task - establish indent level
                    task_list_indent=$indent
                fi

                if [[ $indent -eq $task_list_indent ]]; then
                    # This is a new task item
                    # Output previous task
                    if [[ -n "$current_task" ]]; then
                        local task_json
                        task_json=$(parse_single_task "$current_task")
                        if [[ -n "$task_json" ]] && [[ "$task_json" != "null" ]]; then
                            if [[ "$first_task" == true ]]; then
                                first_task=false
                            else
                                tasks_json+=","
                            fi
                            tasks_json+="$task_json"
                        fi
                    fi
                    # Start new task - extract content after the dash
                    current_task="${line#*- }"$'\n'
                    continue
                fi
            fi

            # Continuation line: any indented content after we've started a task
            if [[ -n "$current_task" ]] && [[ $indent -gt $task_list_indent ]]; then
                # This is continuation of current task (field or multiline content)
                # Normalize indent by removing task-level indent (keep relative indent)
                local task_field_indent=$((task_list_indent + 2))
                if [[ $indent -ge $task_field_indent ]]; then
                    # Remove the task field indent (e.g., 4 spaces for "    title:")
                    local content="${line:$task_field_indent}"
                    current_task+="$content"$'\n'
                fi
            fi
        fi
    done <<< "$yaml"

    # Handle final task if we ended while still in tasks
    if [[ "$in_tasks" == true ]] && [[ -n "$current_task" ]]; then
        local task_json
        task_json=$(parse_single_task "$current_task")
        if [[ -n "$task_json" ]] && [[ "$task_json" != "null" ]]; then
            if [[ "$first_task" == true ]]; then
                first_task=false
            else
                tasks_json+=","
            fi
            tasks_json+="$task_json"
        fi
    fi

    tasks_json+="]"
    echo "$tasks_json"
}

#
# Parse a single task's YAML into JSON
# Input: Task YAML (key: value pairs, with potential multiline strings)
# Output: JSON object
#
# YAML parsing strategy:
# - Top-level task fields start at column 0 (after list item normalization)
# - Multiline strings (description: |) continue until next top-level field
# - We track when we're inside a multiline block to avoid false matches
#
parse_single_task() {
    local yaml="$1"

    # Extract fields using a state machine to handle multiline strings
    local id="" title="" status="" description="" claimed_by="" claimed_at="" blocked_by="" completed_date=""
    local unit_tests="" completion_gaps=""
    local in_multiline=false
    local multiline_field=""
    local multiline_content=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Check if this is a top-level field (not indented, has colon)
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*): ]]; then
            local field_name="${BASH_REMATCH[1]}"
            local field_value="${line#*: }"
            field_value="${field_value#\"}"
            field_value="${field_value%\"}"

            # If we were in a multiline block, close it
            if [[ "$in_multiline" == true ]]; then
                if [[ "$multiline_field" == "description" ]]; then
                    description="$multiline_content"
                fi
                in_multiline=false
                multiline_field=""
                multiline_content=""
            fi

            # Check if this field starts a multiline block
            if [[ "$field_value" == "|" ]] || [[ "$field_value" == "|-" ]] || [[ "$field_value" == "|+" ]]; then
                in_multiline=true
                multiline_field="$field_name"
                multiline_content=""
            else
                # Regular field - extract value
                case "$field_name" in
                    id) id="$field_value" ;;
                    title) title="$field_value" ;;
                    status) status="$field_value" ;;
                    claimed_by) claimed_by="$field_value" ;;
                    claimed_at) claimed_at="$field_value" ;;
                    completed_date) completed_date="$field_value" ;;
                    blocked_by) blocked_by="$field_value" ;;
                    unit_tests) unit_tests="$field_value" ;;
                    completion_gaps) completion_gaps="$field_value" ;;
                esac
            fi
        elif [[ "$in_multiline" == true ]]; then
            # Accumulate multiline content (strip leading spaces for description)
            local content="${line#"${line%%[![:space:]]*}"}"
            if [[ -n "$multiline_content" ]]; then
                multiline_content+=" $content"
            else
                multiline_content="$content"
            fi
        fi
    done <<< "$yaml"

    # Handle any unclosed multiline block
    if [[ "$in_multiline" == true ]] && [[ "$multiline_field" == "description" ]]; then
        description="$multiline_content"
    fi

    # Clean up blocked_by (remove brackets if array format)
    blocked_by="${blocked_by#\[}"
    blocked_by="${blocked_by%\]}"

    # Skip if no id
    if [[ -z "$id" ]]; then
        echo "null"
        return
    fi

    # Strict vocabulary check (bypassable with BF_TODO_PARSER_STRICT=0)
    _strict_check_value status "$status" "task $id"

    # Build JSON - escape special characters
    local json="{"
    json+="\"id\":\"$(echo "$id" | sed 's/"/\\"/g')\""
    json+=",\"title\":\"$(echo "$title" | sed 's/"/\\"/g')\""
    json+=",\"status\":\"${status:-pending}\""

    if [[ -n "$description" ]]; then
        json+=",\"description\":\"$(echo "$description" | sed 's/"/\\"/g')\""
    fi
    if [[ -n "$claimed_by" ]]; then
        json+=",\"claimed_by\":\"$claimed_by\""
    fi
    if [[ -n "$claimed_at" ]]; then
        json+=",\"claimed_at\":\"$claimed_at\""
    fi
    if [[ -n "$completed_date" ]]; then
        json+=",\"completed_date\":\"$completed_date\""
    fi
    if [[ -n "$blocked_by" ]]; then
        # Convert comma-separated to JSON array
        local blocked_arr="["
        local first=true
        IFS=',' read -ra items <<< "$blocked_by"
        for item in "${items[@]}"; do
            item=$(echo "$item" | tr -d ' ')
            if [[ -n "$item" ]]; then
                if [[ "$first" == true ]]; then
                    first=false
                else
                    blocked_arr+=","
                fi
                blocked_arr+="\"$item\""
            fi
        done
        blocked_arr+="]"
        json+=",\"blocked_by\":$blocked_arr"
    else
        json+=",\"blocked_by\":[]"
    fi

    json+=",\"unit_tests\":$(_ep_bracket_list_to_json "$unit_tests")"
    json+=",\"completion_gaps\":$(_ep_bracket_list_to_json "$completion_gaps")"

    json+="}"
    echo "$json"
}

# Convert a YAML inline list ("[a, b, c]" or "a, b" or "") into a JSON array.
# Used for unit_tests and completion_gaps fields. Trims whitespace and surrounding quotes.
_ep_bracket_list_to_json() {
    local raw="$1"
    raw="${raw#[}"; raw="${raw%]}"
    raw="${raw## }"; raw="${raw%% }"
    if [[ -z "$raw" ]]; then
        printf '[]'
        return 0
    fi
    local out="["
    local first=true
    local IFS=','
    for item in $raw; do
        item="${item## }"; item="${item%% }"
        item="${item#\"}"; item="${item%\"}"
        item="${item#\'}"; item="${item%\'}"
        if [[ -n "$item" ]]; then
            if [[ "$first" == true ]]; then first=false; else out+=","; fi
            out+="\"$(echo "$item" | sed 's/"/\\"/g')\""
        fi
    done
    out+="]"
    printf '%s' "$out"
}

#
# Parse a single epic YAML block into JSON
# Input: YAML text
# Output: JSON object with epic metadata and tasks array
#
parse_epic_block() {
    local yaml="$1"

    # Extract epic-level fields
    # Support both formats: "id: EPIC-XXX" (satchelUX) and "epic_id: EPIC-XXX" (legacy)
    local epic_id title status priority blocked_by user_story

    # Try "id:" first (satchelUX format), fall back to "epic_id:" (legacy)
    epic_id=$(extract_field "$yaml" "id")
    if [[ -z "$epic_id" ]] || [[ ! "$epic_id" =~ ^EPIC- ]]; then
        epic_id=$(extract_field "$yaml" "epic_id")
    fi
    title=$(extract_field "$yaml" "title")
    status=$(extract_field "$yaml" "status")
    priority=$(extract_field "$yaml" "priority")
    blocked_by=$(extract_field "$yaml" "blocked_by" | tr -d '[]')
    user_story=$(extract_field "$yaml" "user_story")
    local completion_gaps
    completion_gaps=$(extract_field "$yaml" "completion_gaps")

    # Strict vocabulary check on raw values, before defaulting hides them
    _strict_check_value status "$status" "epic ${epic_id:-(no id)}"
    _strict_check_value priority "$priority" "epic ${epic_id:-(no id)}"

    # Default priority if not specified
    priority="${priority:-p2}"

    # Parse tasks array
    local tasks_json
    tasks_json=$(parse_tasks_array "$yaml")

    # Build JSON
    local json="{"
    json+="\"epic_id\":\"$epic_id\""
    json+=",\"title\":\"$(echo "$title" | sed 's/"/\\"/g')\""
    json+=",\"status\":\"${status:-pending}\""
    json+=",\"priority\":\"$priority\""

    if [[ -n "$blocked_by" ]]; then
        local blocked_arr="["
        local first=true
        IFS=',' read -ra items <<< "$blocked_by"
        for item in "${items[@]}"; do
            item=$(echo "$item" | tr -d ' "')
            if [[ -n "$item" ]]; then
                if [[ "$first" == true ]]; then
                    first=false
                else
                    blocked_arr+=","
                fi
                blocked_arr+="\"$item\""
            fi
        done
        blocked_arr+="]"
        json+=",\"blocked_by\":$blocked_arr"
    else
        json+=",\"blocked_by\":[]"
    fi

    if [[ -n "$user_story" ]] && [[ "$user_story" != "null" ]]; then
        json+=",\"user_story\":\"$user_story\""
    else
        json+=",\"user_story\":\"\""
    fi

    json+=",\"completion_gaps\":$(_ep_bracket_list_to_json "$completion_gaps")"
    json+=",\"tasks\":$tasks_json"
    json+="}"

    echo "$json"
}

#
# Parse flat tasks from a ToDos.md file (fallback for non-epic format)
# Wraps flat tasks into a synthetic epic for consistent output
# Output: JSON array with one synthetic epic containing all flat tasks
#
parse_flat_tasks() {
    local todos_file="${1:-$DEFAULT_TODOS_FILE}"
    local tasks_json="["
    local first_task=true
    local current_block=""

    # First, extract all YAML blocks from the file
    local yaml_blocks
    yaml_blocks=$(extract_yaml_blocks "$todos_file")

    # Then look for --- delimited blocks within those YAML blocks
    while IFS= read -r line; do
        if [[ "$line" == "---BLOCK_END---" ]]; then
            if [[ -n "$current_block" ]]; then
                # Parse --- delimited blocks within this YAML block
                local inner_block=""
                while IFS= read -r inner_line; do
                    if [[ "$inner_line" == "---BLOCK_END---" ]]; then
                        if [[ -n "$inner_block" ]] && [[ $(is_flat_task_block "$inner_block") == "true" ]]; then
                            local task_json
                            task_json=$(parse_single_task "$inner_block")
                            if [[ -n "$task_json" ]] && [[ "$task_json" != "null" ]]; then
                                if [[ "$first_task" == true ]]; then
                                    first_task=false
                                else
                                    tasks_json+=","
                                fi
                                tasks_json+="$task_json"
                            fi
                        fi
                        inner_block=""
                    else
                        inner_block+="$inner_line"$'\n'
                    fi
                done < <(extract_delimited_blocks "$current_block")
            fi
            current_block=""
        else
            current_block+="$line"$'\n'
        fi
    done <<< "$yaml_blocks"

    tasks_json+="]"

    # If no tasks found, return empty array
    if [[ "$tasks_json" == "[]" ]]; then
        echo "[]"
        return
    fi

    # Wrap in a synthetic epic for consistent output format
    # Use the directory name as a hint for the epic title
    local dir_name
    dir_name=$(basename "$(dirname "$todos_file")")
    if [[ "$dir_name" == "docs" ]]; then
        dir_name=$(basename "$(dirname "$(dirname "$todos_file")")")
    fi

    local synthetic_epic="{"
    synthetic_epic+="\"epic_id\":\"FLAT-TASKS\""
    synthetic_epic+=",\"title\":\"Tasks (${dir_name})\""
    synthetic_epic+=",\"status\":\"pending\""
    synthetic_epic+=",\"priority\":\"p2\""
    synthetic_epic+=",\"blocked_by\":[]"
    synthetic_epic+=",\"tasks\":$tasks_json"
    synthetic_epic+=",\"_flat_format\":true"
    synthetic_epic+="}"

    echo "[$synthetic_epic]"
}

#
# Check if a block is a task definition (has id: but not an EPIC)
# Input: YAML text
# Output: "true" or "false"
#
is_task_definition() {
    local yaml="$1"
    # Must have id field
    if ! echo "$yaml" | grep -qE '^id:'; then
        echo "false"
        return
    fi
    # Must NOT be an EPIC
    if echo "$yaml" | grep -qE '^id:[[:space:]]*EPIC-'; then
        echo "false"
        return
    fi
    # Must have title (to distinguish from other YAML blocks)
    if ! echo "$yaml" | grep -qE '^title:'; then
        echo "false"
        return
    fi
    echo "true"
}

#
# Parse all epics from a ToDos.md file
# Supports satchelUX format where epics reference tasks defined separately
# Also handles --- delimited sub-blocks within yaml code fences
# Falls back to flat task format if no epics found
# Output: JSON array of epic objects
#
parse_epics() {
    local todos_file="${1:-$DEFAULT_TODOS_FILE}"

    # First pass: collect all YAML blocks (including --- delimited sub-blocks)
    local epic_blocks=()
    local task_defs=""  # JSON object mapping task ID to task JSON
    local current_yaml_block=""

    # Process each yaml code fence
    while IFS= read -r line; do
        if [[ "$line" == "---BLOCK_END---" ]]; then
            if [[ -n "$current_yaml_block" ]]; then
                # Check if this yaml block contains --- delimited sub-blocks
                if echo "$current_yaml_block" | grep -q '^---$'; then
                    # Extract each --- delimited sub-block
                    local sub_block=""
                    while IFS= read -r sub_line; do
                        if [[ "$sub_line" == "---BLOCK_END---" ]]; then
                            if [[ -n "$sub_block" ]]; then
                                if [[ $(is_epic_block "$sub_block") == "true" ]]; then
                                    epic_blocks+=("$sub_block")
                                elif [[ $(is_task_definition "$sub_block") == "true" ]]; then
                                    local task_json
                                    task_json=$(parse_single_task "$sub_block")
                                    if [[ -n "$task_json" ]] && [[ "$task_json" != "null" ]]; then
                                        local task_id
                                        task_id=$(echo "$task_json" | jq -r '.id')
                                        if [[ -n "$task_defs" ]]; then
                                            task_defs+=","
                                        fi
                                        task_defs+="\"$task_id\":$task_json"
                                    fi
                                fi
                            fi
                            sub_block=""
                        else
                            sub_block+="$sub_line"$'\n'
                        fi
                    done < <(extract_delimited_blocks "$current_yaml_block")
                else
                    # Single block (no --- delimiters)
                    if [[ $(is_epic_block "$current_yaml_block") == "true" ]]; then
                        epic_blocks+=("$current_yaml_block")
                    elif [[ $(is_task_definition "$current_yaml_block") == "true" ]]; then
                        local task_json
                        task_json=$(parse_single_task "$current_yaml_block")
                        if [[ -n "$task_json" ]] && [[ "$task_json" != "null" ]]; then
                            local task_id
                            task_id=$(echo "$task_json" | jq -r '.id')
                            if [[ -n "$task_defs" ]]; then
                                task_defs+=","
                            fi
                            task_defs+="\"$task_id\":$task_json"
                        fi
                    fi
                fi
            fi
            current_yaml_block=""
        else
            current_yaml_block+="$line"$'\n'
        fi
    done < <(extract_yaml_blocks "$todos_file")

    # Wrap task_defs in JSON object
    task_defs="{$task_defs}"

    # Second pass: build epics with resolved tasks
    local epics_json="["
    local first_epic=true

    for block in "${epic_blocks[@]}"; do
        local epic_id title status priority blocked_by user_story

        # Extract epic fields (support both id: EPIC- and epic_id: formats)
        epic_id=$(extract_field "$block" "id")
        if [[ -z "$epic_id" ]] || [[ ! "$epic_id" =~ ^EPIC- ]]; then
            epic_id=$(extract_field "$block" "epic_id")
        fi
        title=$(extract_field "$block" "title")
        status=$(extract_field "$block" "status")
        priority=$(extract_field "$block" "priority")
        blocked_by=$(extract_field "$block" "blocked_by" | tr -d '[]')
        user_story=$(extract_field "$block" "user_story")
        local epic_completion_gaps
        epic_completion_gaps=$(extract_field "$block" "completion_gaps")

        # Strict vocabulary check on raw values, before defaulting hides them
        _strict_check_value status "$status" "epic ${epic_id:-(no id)}"
        _strict_check_value priority "$priority" "epic ${epic_id:-(no id)}"

        priority="${priority:-p2}"

        # Get task references from epic
        local task_refs
        task_refs=$(extract_task_refs "$block")

        # Build tasks array by looking up each referenced task
        local tasks_json="["
        local first_task=true
        for task_id in $task_refs; do
            local task_json
            task_json=$(echo "$task_defs" | jq -r --arg id "$task_id" '.[$id] // empty')
            if [[ -n "$task_json" ]] && [[ "$task_json" != "null" ]]; then
                if [[ "$first_task" == true ]]; then
                    first_task=false
                else
                    tasks_json+=","
                fi
                tasks_json+="$task_json"
            fi
        done
        tasks_json+="]"

        # If no tasks found via refs, try inline tasks (legacy format)
        if [[ "$tasks_json" == "[]" ]]; then
            tasks_json=$(parse_tasks_array "$block")
        fi

        # Build epic JSON
        local epic_json="{"
        epic_json+="\"epic_id\":\"$epic_id\""
        epic_json+=",\"title\":\"$(echo "$title" | sed 's/"/\\"/g')\""
        epic_json+=",\"status\":\"${status:-pending}\""
        epic_json+=",\"priority\":\"$priority\""

        if [[ -n "$blocked_by" ]]; then
            local blocked_arr="["
            local first=true
            IFS=',' read -ra items <<< "$blocked_by"
            for item in "${items[@]}"; do
                item=$(echo "$item" | tr -d ' "')
                if [[ -n "$item" ]]; then
                    if [[ "$first" == true ]]; then
                        first=false
                    else
                        blocked_arr+=","
                    fi
                    blocked_arr+="\"$item\""
                fi
            done
            blocked_arr+="]"
            epic_json+=",\"blocked_by\":$blocked_arr"
        else
            epic_json+=",\"blocked_by\":[]"
        fi

        if [[ -n "$user_story" ]] && [[ "$user_story" != "null" ]]; then
            epic_json+=",\"user_story\":\"$user_story\""
        else
            epic_json+=",\"user_story\":\"\""
        fi

        epic_json+=",\"completion_gaps\":$(_ep_bracket_list_to_json "$epic_completion_gaps")"
        epic_json+=",\"tasks\":$tasks_json"
        epic_json+="}"

        if [[ "$first_epic" == true ]]; then
            first_epic=false
        else
            epics_json+=","
        fi
        epics_json+="$epic_json"
    done

    epics_json+="]"

    # Fallback: if no epics found, try parsing flat task format
    if [[ "$epics_json" == "[]" ]]; then
        local flat_result
        flat_result=$(parse_flat_tasks "$todos_file")
        if [[ "$flat_result" != "[]" ]]; then
            echo "$flat_result"
            return
        fi
    fi

    echo "$epics_json"
}

#
# Get a specific epic by ID
# Output: JSON object or empty
#
get_epic() {
    local epic_id="$1"
    local todos_file="${2:-$DEFAULT_TODOS_FILE}"

    local epics
    epics=$(parse_epics "$todos_file")

    echo "$epics" | jq -r ".[] | select(.epic_id == \"$epic_id\")"
}

#
# Get all tasks across all epics (flattened)
# Output: JSON array of task objects with epic_id field added
#
get_all_tasks() {
    local todos_file="${1:-$DEFAULT_TODOS_FILE}"

    local epics
    epics=$(parse_epics "$todos_file")

    echo "$epics" | jq '[.[] | .epic_id as $eid | .tasks[] | . + {epic_id: $eid}]'
}

#
# Derive epic status from its tasks
# Input:
#   $1 tasks_json:           JSON array of this epic's tasks
#   $2 all_tasks_json:       Optional JSON array of all tasks across all epics
#                            (for cross-epic blocked_by resolution). Defaults to tasks_json.
#   $3 all_epics_json:      Optional JSON array of all epics in the file. Used to recognize
#                            archived blockers: any epic_id in blocked_by NOT present in this
#                            list is presumed archived (and therefore complete). Without it,
#                            archiving a completed upstream epic via /epic-hygiene would
#                            silently mark every downstream epic as blocked. Defaults to "[]".
#   $4 epic_blocked_by_json: Optional JSON array of THIS epic's epic-level blocked_by
#                            (e.g. ["EPIC-009"]). Used together with all_epics_json to
#                            derive whether the epic itself is gated. Defaults to "[]".
# Output: JSON object with derived_status and metrics
#
# Status derivation matches get_eligible_epics / list_epics to keep the three call paths
# consistent. An epic is "blocked" only if:
#   (a) its epic-level blocked_by references unresolved (non-complete, non-archived) epics, OR
#   (b) all incomplete tasks within the epic are themselves blocked.
#
# A task is considered effectively blocked if:
#   - Its explicit status is "blocked", OR
#   - It has blocked_by entries referencing incomplete tasks (cross-epic aware).
#
derive_epic_status() {
    local tasks_json="$1"
    local all_tasks_json="${2:-$tasks_json}"   # Fall back to same list if not provided
    local all_epics_json="${3:-[]}"           # Empty array → no archived-blocker awareness
    local epic_blocked_by_json="${4:-[]}"     # Empty array → epic has no upstream blockers

    # Use jq to compute counts with blocked_by awareness
    local metrics_json
    metrics_json=$(echo "$tasks_json" | jq \
        --argjson all_tasks "$all_tasks_json" \
        --argjson all_epics "$all_epics_json" \
        --argjson epic_blocked_by "$epic_blocked_by_json" '
        # Build lookup of complete task IDs (for task-level blocked_by resolution)
        ($all_tasks | [.[] | select(.status == "complete") | .id]) as $complete_ids |

        # Build lookup of all known epic IDs (those still present in the file).
        # Any epic_id in epic_blocked_by NOT in this set is presumed archived.
        ($all_epics | [.[] | .epic_id]) as $known_epic_ids |

        # Build lookup of complete epic IDs (still present in the file, all tasks complete)
        ($all_epics | [.[] | select(
            (.tasks | length) > 0 and
            ([.tasks[] | select(.status == "complete")] | length) == (.tasks | length)
        ) | .epic_id]) as $complete_epic_ids |

        # An epic-level blocker is resolved if EITHER:
        #   (a) it is in $complete_epic_ids (still present, all tasks complete), OR
        #   (b) it is NOT in $known_epic_ids (archived to CompletedTasks.md, presumed complete)
        ((($epic_blocked_by | length) == 0) or
         ($epic_blocked_by | all(. as $bid |
            ($complete_epic_ids | index($bid)) or
            (($known_epic_ids | index($bid)) | not)
         ))) as $epic_unblocked |

        # Store input array for reuse (crucial - prevents context loss)
        . as $tasks |

        ($tasks | length) as $total |
        ([$tasks[] | select(.status == "complete")] | length) as $complete |
        ([$tasks[] | select(.status == "in_progress")] | length) as $in_progress |
        # Blocked: explicit blocked OR has unresolved blocked_by
        ([$tasks[] | select(
            .status == "blocked" or
            (((.blocked_by // []) | length > 0) and
             (((.blocked_by // []) | all(. as $bid | $complete_ids | index($bid))) | not))
        )] | length) as $blocked |
        # Pending: status pending AND no unresolved blockers
        ([$tasks[] | select(
            .status == "pending" and
            (((.blocked_by // []) | length == 0) or
             ((.blocked_by // []) | all(. as $bid | $complete_ids | index($bid))))
        )] | length) as $pending |

        # Derive status — matches get_eligible_epics semantics
        (if $total == 0 then "pending"
         elif $complete == $total then "complete"
         elif ($epic_unblocked | not) then "blocked"
         elif $in_progress > 0 then "in_progress"
         elif $blocked > 0 and $blocked == ($total - $complete) then "blocked"
         elif $complete > 0 then "in_progress"
         else "pending" end) as $derived |

        # Calculate percent
        (if $total > 0 then ($complete * 100 / $total | floor) else 0 end) as $percent |

        {
            derived_status: $derived,
            metrics: {
                total: $total,
                pending: $pending,
                in_progress: $in_progress,
                complete: $complete,
                blocked: $blocked,
                percent_complete: $percent
            }
        }
    ')

    echo "$metrics_json"
}

#
# Get metrics for an epic by ID
# Output: JSON with epic info and derived metrics
#
get_epic_metrics() {
    local epic_id="$1"
    local todos_file="${2:-$DEFAULT_TODOS_FILE}"

    local epic
    epic=$(get_epic "$epic_id" "$todos_file")

    if [[ -z "$epic" ]]; then
        echo "null"
        return 1
    fi

    # Get all epics and tasks for cross-epic blocked_by resolution
    local all_epics
    all_epics=$(parse_epics "$todos_file")
    local all_tasks
    all_tasks=$(echo "$all_epics" | jq '[.[] | .tasks[]]')

    local tasks
    tasks=$(echo "$epic" | jq '.tasks')

    # Extract this epic's epic-level blocked_by so derive_epic_status can recognize
    # archived blockers (e.g. blocked_by: [EPIC-009] when EPIC-009 has been moved to
    # CompletedTasks.md) and not falsely report the epic as blocked.
    local epic_blocked_by
    epic_blocked_by=$(echo "$epic" | jq '.blocked_by // []')

    local status_info
    status_info=$(derive_epic_status "$tasks" "$all_tasks" "$all_epics" "$epic_blocked_by")

    # Merge epic data with derived status
    echo "$epic" | jq --argjson status "$status_info" '. + {derived: $status}'
}

#
# Check if all blockers for an epic are complete
# Input: epic blocked_by array, all epics JSON
# Output: "true" or "false"
#
check_epic_blockers_complete() {
    local blocked_by="$1"
    local all_epics="$2"

    # If no blockers, return true
    if [[ -z "$blocked_by" ]] || [[ "$blocked_by" == "[]" ]]; then
        echo "true"
        return
    fi

    # Check each blocker
    local result
    result=$(echo "$all_epics" | jq --argjson blockers "$blocked_by" '
        ($blockers | length) == 0 or
        ([$blockers[] as $bid | .[] | select(.epic_id == $bid) | .status == "complete" or (.tasks | all(.status == "complete"))] | all)
    ')

    echo "$result"
}

#
# Check if all blockers for a task are complete
# Input: task blocked_by array, all tasks in epic JSON
# Output: "true" or "false"
#
check_task_blockers_complete() {
    local blocked_by="$1"
    local all_tasks="$2"

    if [[ -z "$blocked_by" ]] || [[ "$blocked_by" == "[]" ]]; then
        echo "true"
        return
    fi

    local result
    result=$(echo "$all_tasks" | jq --argjson blockers "$blocked_by" '
        ($blockers | length) == 0 or
        ([$blockers[] as $bid | .[] | select(.id == $bid) | .status == "complete"] | length) == ($blockers | length)
    ')

    echo "$result"
}

#
# Get eligible epics (pending or in_progress, blockers resolved)
# Output: JSON array of epics sorted by priority
#
get_eligible_epics() {
    local todos_file="${1:-$DEFAULT_TODOS_FILE}"

    local epics
    epics=$(parse_epics "$todos_file")

    # Get all tasks for cross-epic blocked_by resolution
    local all_tasks
    all_tasks=$(echo "$epics" | jq '[.[] | .tasks[]]')

    # Add derived status to each epic and filter
    # Respects both epic-level blocked_by and task-level blocked_by
    echo "$epics" | jq --argjson all_tasks "$all_tasks" '
        # Build lookup of all known epic IDs (those still present in ToDos.md).
        # Used to recognize archived blockers: any blocked_by reference NOT in this set
        # is presumed archived (and therefore complete) rather than blocking. Without
        # this, archiving a completed upstream epic via /epic-hygiene would silently
        # mark every downstream epic with blocked_by referencing it as blocked.
        ([.[] | .epic_id]) as $known_epic_ids |

        # Build lookup of complete epic IDs (still present in ToDos.md, all tasks complete)
        ([.[] | select(
            (.tasks | length) > 0 and
            ([.tasks[] | select(.status == "complete")] | length) == (.tasks | length)
        ) | .epic_id]) as $complete_epic_ids |

        # Build lookup of complete task IDs
        ($all_tasks | [.[] | select(.status == "complete") | .id]) as $complete_task_ids |

        # Add derived status based on tasks (with blocked_by awareness)
        [.[] |
            . as $epic |

            # An epic-level blocker is resolved if EITHER:
            #   (a) it is in $complete_epic_ids (still present, all tasks complete), OR
            #   (b) it is NOT in $known_epic_ids (archived to CompletedTasks.md, presumed complete)
            (((.blocked_by // []) | length == 0) or
             ((.blocked_by // []) | all(. as $bid |
                ($complete_epic_ids | index($bid)) or
                (($known_epic_ids | index($bid)) | not)
             ))) as $epic_unblocked |

            (.tasks | length) as $total |
            ([.tasks[] | select(.status == "complete")] | length) as $complete |
            ([.tasks[] | select(.status == "in_progress")] | length) as $in_progress |
            # Count tasks that are blocked (explicit or unresolved blocked_by)
            ([.tasks[] | select(
                .status == "blocked" or
                (((.blocked_by // []) | length > 0) and
                 (((.blocked_by // []) | all(. as $bid | $complete_task_ids | index($bid))) | not))
            )] | length) as $blocked |

            # Derive status (considering both explicit and implicit blocking)
            (if $total == 0 then "pending"
             elif $complete == $total then "complete"
             elif ($epic_unblocked | not) then "blocked"
             elif $in_progress > 0 then "in_progress"
             elif $blocked > 0 and $blocked == ($total - $complete) then "blocked"
             elif $complete > 0 then "in_progress"
             else "pending" end) as $derived |

            . + {
                derived_status: $derived,
                task_metrics: {total: $total, complete: $complete},
                _epic_blockers_resolved: $epic_unblocked
            }
        ] |
        # Filter to eligible (pending or in_progress, epic-level blockers resolved)
        [.[] | select(
            (.derived_status == "pending" or .derived_status == "in_progress") and
            ._epic_blockers_resolved
        )] |
        # Sort: in_progress first, then by priority, then by epic number
        # Use try-catch for epic_id parsing to handle non-numeric IDs (e.g., FLAT-TASKS)
        sort_by(
            (if .derived_status == "in_progress" then 0 else 1 end),
            (if .priority == "p0" then 0 elif .priority == "p1" then 1 elif .priority == "p2" then 2 else 3 end),
            (try (.epic_id | ltrimstr("EPIC-") | tonumber) catch 9999)
        )
    '
}

#
# Get next eligible task from an epic
# Input: epic JSON, session ID, optional all tasks JSON (for cross-epic blocked_by)
# Output: JSON task object or null
#
get_next_task_from_epic() {
    local epic_json="$1"
    local session_id="${2:-claude-session}"
    local all_tasks_json="${3:-}"

    # If all_tasks not provided, use tasks from this epic only
    if [[ -z "$all_tasks_json" ]]; then
        all_tasks_json=$(echo "$epic_json" | jq '.tasks')
    fi

    echo "$epic_json" | jq --arg session "$session_id" --argjson all_tasks "$all_tasks_json" '
        # Build lookup of complete task IDs (from all epics)
        ($all_tasks | [.[] | select(.status == "complete") | .id]) as $complete_task_ids |

        .tasks |
        # Filter to eligible tasks:
        # - Own in_progress tasks (can continue)
        # - Pending tasks with all blockers resolved (no unresolved blocked_by)
        [.[] | select(
            (.status == "in_progress" and .claimed_by == $session) or
            (.status == "pending" and
             # Check task does NOT have unresolved blockers
             (((.blocked_by // []) | length == 0) or
              ((.blocked_by // []) | all(. as $bid | $complete_task_ids | index($bid)))))
        )] |
        # Sort: own in_progress first, then fewer blockers, then by task number
        sort_by(
            (if .status == "in_progress" and .claimed_by == $session then 0 else 1 end),
            (.blocked_by | length),
            (try (.id | split("-") | .[-1] | tonumber) catch 9999)
        ) |
        first
    '
}

#
# Get the next task to work on (main entry point)
# Output: JSON object with epic context and next task
#
get_next_task() {
    local todos_file="${1:-$DEFAULT_TODOS_FILE}"
    local session_id="${2:-claude-session}"

    # Parse all epics first (needed for cross-epic blocked_by resolution)
    local all_epics
    all_epics=$(parse_epics "$todos_file")

    # Get all tasks for cross-epic blocked_by resolution
    local all_tasks
    all_tasks=$(echo "$all_epics" | jq '[.[] | .tasks[]]')

    # Get eligible epics
    local eligible
    eligible=$(get_eligible_epics "$todos_file")

    # Check if any eligible epics
    local count
    count=$(echo "$eligible" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        cat <<EOF
{
  "status": "no_work_available",
  "message": "No eligible epics found. All epics may be complete or blocked.",
  "epic": null,
  "task": null
}
EOF
        return
    fi

    # Get first eligible epic
    local current_epic
    current_epic=$(echo "$eligible" | jq '.[0]')

    # Get next task from that epic (pass all_tasks for cross-epic blocked_by)
    local next_task
    next_task=$(get_next_task_from_epic "$current_epic" "$session_id" "$all_tasks")

    # If no eligible task in this epic (all blocked), try next epic
    if [[ "$next_task" == "null" ]] || [[ -z "$next_task" ]]; then
        local epic_idx=1
        while [[ $epic_idx -lt $count ]]; do
            current_epic=$(echo "$eligible" | jq ".[$epic_idx]")
            next_task=$(get_next_task_from_epic "$current_epic" "$session_id" "$all_tasks")
            if [[ "$next_task" != "null" ]] && [[ -n "$next_task" ]]; then
                break
            fi
            ((epic_idx++))
        done
    fi

    # Build epic queue (other pending epics)
    local epic_queue
    epic_queue=$(echo "$eligible" | jq '[.[] | {epic_id, title, priority, derived_status, task_metrics}]')

    # Build result
    jq -n \
        --argjson epic "$current_epic" \
        --argjson task "$next_task" \
        --argjson queue "$epic_queue" \
        '{
            status: (if $task == null then "no_work_available" else "task_available" end),
            message: (if $task == null then "All tasks in eligible epics are blocked." else null end),
            epic: {
                epic_id: $epic.epic_id,
                title: $epic.title,
                priority: $epic.priority,
                derived_status: $epic.derived_status,
                task_count: ($epic.tasks | length),
                complete_count: ([$epic.tasks[] | select(.status == "complete")] | length)
            },
            task: $task,
            epic_queue: $queue
        }'
}

#
# List all epics with summary
# Output: JSON array with epic summaries
#
list_epics() {
    local todos_file="${1:-$DEFAULT_TODOS_FILE}"

    local epics
    epics=$(parse_epics "$todos_file")

    # Get all tasks for cross-epic blocked_by resolution
    local all_tasks
    all_tasks=$(echo "$epics" | jq '[.[] | .tasks[]]')

    echo "$epics" | jq --argjson all_tasks "$all_tasks" '
        # Build lookup of complete task IDs
        ($all_tasks | [.[] | select(.status == "complete") | .id]) as $complete_task_ids |

        # Build lookup of all known epic IDs (still present in ToDos.md). Any blocked_by
        # reference NOT in this set is presumed archived (and therefore complete).
        ([.[] | .epic_id]) as $known_epic_ids |

        # Build lookup of complete epic IDs (still present in ToDos.md, all tasks complete)
        ([.[] | select(
            (.tasks | length) > 0 and
            ([.tasks[] | select(.status == "complete")] | length) == (.tasks | length)
        ) | .epic_id]) as $complete_epic_ids |

        [.[] |
            # An epic-level blocker is resolved if EITHER:
            #   (a) it is in $complete_epic_ids (still present, all tasks complete), OR
            #   (b) it is NOT in $known_epic_ids (archived to CompletedTasks.md)
            (((.blocked_by // []) | length == 0) or
             ((.blocked_by // []) | all(. as $bid |
                ($complete_epic_ids | index($bid)) or
                (($known_epic_ids | index($bid)) | not)
             ))) as $epic_unblocked |

            {
                epic_id,
                title,
                status,
                priority,
                blocked_by,
                epic_blocked: ($epic_unblocked | not),
                task_count: (.tasks | length),
                complete: ([.tasks[] | select(.status == "complete")] | length),
                in_progress: ([.tasks[] | select(.status == "in_progress")] | length),
                # Pending: status pending AND not blocked by unresolved tasks
                pending: ([.tasks[] | select(
                    .status == "pending" and
                    (((.blocked_by // []) | length == 0) or
                     ((.blocked_by // []) | all(. as $bid | $complete_task_ids | index($bid))))
                )] | length),
                # Blocked: explicit blocked OR has unresolved blocked_by
                blocked: ([.tasks[] | select(
                    .status == "blocked" or
                    (((.blocked_by // []) | length > 0) and
                     (((.blocked_by // []) | all(. as $bid | $complete_task_ids | index($bid))) | not))
                )] | length)
            }
        ] |
        # Use try-catch for epic_id parsing to handle non-numeric IDs (e.g., FLAT-TASKS)
        sort_by(
            (if .priority == "p0" then 0 elif .priority == "p1" then 1 elif .priority == "p2" then 2 else 3 end),
            (try (.epic_id | ltrimstr("EPIC-") | tonumber) catch 9999)
        )
    '
}

#
# Validate epics and tasks structure
# Output: JSON with validation results and warnings
#
validate_epics() {
    local todos_file="${1:-$DEFAULT_TODOS_FILE}"

    # Disable strict parsing here so we can *detect* drift rather than abort
    # on it. The validator is the path that reports drift; if the parser
    # bailed out first, we'd have nothing to report.
    local epics
    epics=$(BF_TODO_PARSER_STRICT=0 parse_epics "$todos_file")

    # Validation checks
    local warnings="[]"
    local errors="[]"

    # Check each epic.
    #
    # Warning shape: {type, scope, id, value} for invalid_status/invalid_priority;
    # legacy keys (task_id, status, epic_id, index) preserved on relevant types
    # so existing consumers don't break.
    warnings=$(echo "$epics" | jq '
        [
            .[] | . as $epic |

            # Missing task IDs
            (.tasks | to_entries | .[] | select(.value.id == null or .value.id == "") |
                {type: "missing_task_id", epic_id: $epic.epic_id, index: .key}) // empty,

            # Invalid task status (e.g. legacy "done" / "active" / "completed" / "planned")
            (.tasks[] | select(.status | test("^(pending|in_progress|complete|blocked)$") | not) |
                {type: "invalid_status", scope: "task", id: .id, value: .status,
                 task_id: .id, status: .status, epic_id: $epic.epic_id}) // empty,

            # Invalid epic status
            (select(.status | test("^(pending|in_progress|complete|blocked)$") | not) |
                {type: "invalid_status", scope: "epic", id: .epic_id, value: .status,
                 epic_id: .epic_id, status: .status}) // empty,

            # Invalid epic priority (must be p0|p1|p2|p3)
            (select(.priority | test("^(p0|p1|p2|p3)$") | not) |
                {type: "invalid_priority", scope: "epic", id: .epic_id, value: .priority,
                 epic_id: .epic_id, priority: .priority}) // empty,

            # Empty epics
            (select(.tasks | length == 0) |
                {type: "empty_epic", epic_id: .epic_id}) // empty
        ]
    ')

    local valid="true"
    if [[ $(echo "$warnings" | jq 'length') -gt 0 ]]; then
        valid="false"
    fi

    jq -n \
        --argjson warnings "$warnings" \
        --arg valid "$valid" \
        --argjson epic_count "$(echo "$epics" | jq 'length')" \
        '{
            valid: ($valid == "true"),
            epic_count: $epic_count,
            warnings: $warnings
        }'
}

#
# Strict validation: same checks as validate_epics, but exit nonzero with a
# human-readable report when any drift is found. Pre-commit hooks and the
# upcoming bountyforge-lint StatusVocabularyChecker call this path so legacy
# values (done/active/planned/completed, etc.) hard-fail instead of silently
# being treated as pending.
#
# Output: human-readable drift report on stderr.
# Returns: 0 on clean, 1 on drift, 2 on internal errors.
#
validate_strict() {
    local todos_file="${1:-$DEFAULT_TODOS_FILE}"

    if [[ ! -f "$todos_file" ]]; then
        echo "epic-parser: file not found: $todos_file" >&2
        return 2
    fi

    local result
    result=$(validate_epics "$todos_file") || return 2

    local warning_count
    warning_count=$(echo "$result" | jq '.warnings | length')

    if [[ "$warning_count" -eq 0 ]]; then
        return 0
    fi

    {
        echo "epic-parser: $todos_file has $warning_count drift issue(s):"
        echo "$result" | jq -r '.warnings[] |
            if .type == "invalid_status" then
                "  invalid status \"\(.value)\" on \(.scope) \(.id)"
            elif .type == "invalid_priority" then
                "  invalid priority \"\(.value)\" on \(.scope) \(.id)"
            elif .type == "missing_task_id" then
                "  missing task id in epic \(.epic_id) (index \(.index))"
            elif .type == "empty_epic" then
                "  empty epic \(.epic_id)"
            else
                "  \(.type): \(. | tostring)"
            end'
        echo ""
        echo "Canonical vocabulary:"
        echo "  status:   pending | in_progress | complete | blocked"
        echo "  priority: p0 | p1 | p2 | p3"
    } >&2

    return 1
}

# If script is run directly (not sourced), provide CLI interface
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # CLI mode
    COMMAND="${1:-help}"

    # Surface strict-mode failures from subshell parsers as a non-zero CLI exit.
    # Without this, _strict_check_value's `exit 1` only kills the $(...) subshell
    # and the CLI returns 0 with corrupted JSON.
    trap 'rc=$?; if [[ -f "$EPIC_PARSER_STRICT_MARKER" ]]; then rm -f "$EPIC_PARSER_STRICT_MARKER"; exit 1; fi; exit $rc' EXIT

    case "$COMMAND" in
        parse|epics)
            parse_epics "${2:-$DEFAULT_TODOS_FILE}"
            ;;
        get-epic)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 get-epic EPIC-ID [todos_file]" >&2
                exit 1
            fi
            get_epic "$2" "${3:-$DEFAULT_TODOS_FILE}"
            ;;
        metrics)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 metrics EPIC-ID [todos_file]" >&2
                exit 1
            fi
            get_epic_metrics "$2" "${3:-$DEFAULT_TODOS_FILE}"
            ;;
        next-task)
            get_next_task "${2:-$DEFAULT_TODOS_FILE}" "${3:-claude-session}"
            ;;
        list)
            list_epics "${2:-$DEFAULT_TODOS_FILE}"
            ;;
        all-tasks)
            get_all_tasks "${2:-$DEFAULT_TODOS_FILE}"
            ;;
        validate)
            validate_epics "${2:-$DEFAULT_TODOS_FILE}"
            ;;
        validate-strict)
            if validate_strict "${2:-$DEFAULT_TODOS_FILE}"; then
                echo "epic-parser: ${2:-$DEFAULT_TODOS_FILE} OK"
                exit 0
            else
                exit 1
            fi
            ;;
        help|--help|-h)
            cat <<EOF
epic-parser.sh - Parse epic/task YAML from docs/ToDos.md

Usage: $0 <command> [args]

Commands:
  parse [file]              Parse all epics, output JSON array
  get-epic ID [file]       Get specific epic by ID
  metrics ID [file]         Get epic with derived status metrics
  next-task [file] [agent]  Get next eligible task to work on
  list [file]               List all epics with summary
  all-tasks [file]          Get all tasks (flattened across epics)
  validate [file]           Validate epic/task structure (returns JSON, exit 0)
  validate-strict [file]    Validate vocabulary; exit 1 on drift (pre-commit gate)
  help                      Show this help message

Environment:
  BF_TODO_PARSER_STRICT     1 (default) hard-fails on non-canonical status or
                            priority values during parsing. Set to 0 as a
                            migration escape hatch while normalizing legacy
                            values (done/active/planned/completed/etc.).

Default file: docs/ToDos.md

Examples:
  $0 parse
  $0 get-epic EPIC-011
  $0 next-task docs/ToDos.md claude-session
  $0 list
  $0 validate

As a library (source in other scripts):
  source /path/to/epic-parser.sh
  epics=\$(parse_epics "docs/ToDos.md")
  next=\$(get_next_task "docs/ToDos.md")
EOF
            ;;
        *)
            echo "Unknown command: $COMMAND" >&2
            echo "Run '$0 help' for usage" >&2
            exit 1
            ;;
    esac
fi
