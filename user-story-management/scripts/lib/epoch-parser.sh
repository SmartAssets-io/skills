#!/usr/bin/env bash
#
# epoch-parser.sh - Shared library for parsing epoch/task YAML from docs/ToDos.md
#
# This library provides functions to:
# 1. Parse epoch YAML blocks from markdown files
# 2. Extract nested task arrays within epochs
# 3. Output structured JSON for use by slash commands
# 4. Derive epoch status from task states
# 5. Handle epoch and task sequencing
#
# Usage:
#   source /path/to/epoch-parser.sh
#   parse_epochs "docs/ToDos.md"
#   get_epoch "EPOCH-011" "docs/ToDos.md"
#   get_next_task "docs/ToDos.md"
#
# Dependencies:
#   - jq (required for JSON manipulation)
#   - bash 4+ (for associative arrays)
#
# Note: This script avoids yq dependency by using regex/awk for YAML parsing

# Prevent re-sourcing
if [[ -n "${EPOCH_PARSER_LOADED:-}" ]]; then
    return 0
fi
EPOCH_PARSER_LOADED=1

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
            yaml_content+="$line"$'\n'
        fi
    done < "$file"
}

#
# Check if a YAML block is an epoch definition
# Supports both formats:
#   - id: EPOCH-XXX (satchelUX format)
#   - epoch_id: EPOCH-XXX (legacy format)
# Filters out template/example blocks (EPOCH-XXX, EPOCH-NNN, etc.)
# Input: YAML text
# Output: "true" or "false"
#
is_epoch_block() {
    local yaml="$1"
    # Check for either format: "id: EPOCH-" or "epoch_id: EPOCH-"
    if echo "$yaml" | grep -qE '^id:[[:space:]]*EPOCH-'; then
        # Filter out template/example epochs (XXX, NNN, YYY patterns)
        if echo "$yaml" | grep -qE '^id:[[:space:]]*EPOCH-(XXX|NNN|YYY)'; then
            echo "false"
            return
        fi
        echo "true"
        return
    fi
    if echo "$yaml" | grep -qE '^epoch_id:[[:space:]]*EPOCH-'; then
        # Filter out template/example epochs (XXX, NNN, YYY patterns)
        if echo "$yaml" | grep -qE '^epoch_id:[[:space:]]*EPOCH-(XXX|NNN|YYY)'; then
            echo "false"
            return
        fi
        echo "true"
        return
    fi
    echo "false"
}

#
# Check if a YAML block is a flat task (has id: but not epoch_id: or tasks:)
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
    # Must NOT have epoch_id (that's an epoch, not a flat task)
    if echo "$yaml" | grep -qE '^epoch_id:'; then
        echo "false"
        return
    fi
    # Must NOT have id: EPOCH- (that's an epoch in satchelUX format)
    if echo "$yaml" | grep -qE '^id:[[:space:]]*EPOCH-'; then
        echo "false"
        return
    fi
    # Must NOT have tasks: array (that's an epoch structure)
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
# Extract task ID references from epoch's tasks: array
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
# Parse the tasks array from an epoch YAML block
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

    json+="}"
    echo "$json"
}

#
# Parse a single epoch YAML block into JSON
# Input: YAML text
# Output: JSON object with epoch metadata and tasks array
#
parse_epoch_block() {
    local yaml="$1"

    # Extract epoch-level fields
    # Support both formats: "id: EPOCH-XXX" (satchelUX) and "epoch_id: EPOCH-XXX" (legacy)
    local epoch_id title status priority blocked_by

    # Try "id:" first (satchelUX format), fall back to "epoch_id:" (legacy)
    epoch_id=$(extract_field "$yaml" "id")
    if [[ -z "$epoch_id" ]] || [[ ! "$epoch_id" =~ ^EPOCH- ]]; then
        epoch_id=$(extract_field "$yaml" "epoch_id")
    fi
    title=$(extract_field "$yaml" "title")
    status=$(extract_field "$yaml" "status")
    priority=$(extract_field "$yaml" "priority")
    blocked_by=$(extract_field "$yaml" "blocked_by" | tr -d '[]')

    # Default priority if not specified
    priority="${priority:-p2}"

    # Parse tasks array
    local tasks_json
    tasks_json=$(parse_tasks_array "$yaml")

    # Build JSON
    local json="{"
    json+="\"epoch_id\":\"$epoch_id\""
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

    json+=",\"tasks\":$tasks_json"
    json+="}"

    echo "$json"
}

#
# Parse flat tasks from a ToDos.md file (fallback for non-epoch format)
# Wraps flat tasks into a synthetic epoch for consistent output
# Output: JSON array with one synthetic epoch containing all flat tasks
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

    # Wrap in a synthetic epoch for consistent output format
    # Use the directory name as a hint for the epoch title
    local dir_name
    dir_name=$(basename "$(dirname "$todos_file")")
    if [[ "$dir_name" == "docs" ]]; then
        dir_name=$(basename "$(dirname "$(dirname "$todos_file")")")
    fi

    local synthetic_epoch="{"
    synthetic_epoch+="\"epoch_id\":\"FLAT-TASKS\""
    synthetic_epoch+=",\"title\":\"Tasks (${dir_name})\""
    synthetic_epoch+=",\"status\":\"pending\""
    synthetic_epoch+=",\"priority\":\"p2\""
    synthetic_epoch+=",\"blocked_by\":[]"
    synthetic_epoch+=",\"tasks\":$tasks_json"
    synthetic_epoch+=",\"_flat_format\":true"
    synthetic_epoch+="}"

    echo "[$synthetic_epoch]"
}

#
# Check if a block is a task definition (has id: but not an EPOCH)
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
    # Must NOT be an EPOCH
    if echo "$yaml" | grep -qE '^id:[[:space:]]*EPOCH-'; then
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
# Parse all epochs from a ToDos.md file
# Supports satchelUX format where epochs reference tasks defined separately
# Also handles --- delimited sub-blocks within yaml code fences
# Falls back to flat task format if no epochs found
# Output: JSON array of epoch objects
#
parse_epochs() {
    local todos_file="${1:-$DEFAULT_TODOS_FILE}"

    # First pass: collect all YAML blocks (including --- delimited sub-blocks)
    local epoch_blocks=()
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
                                if [[ $(is_epoch_block "$sub_block") == "true" ]]; then
                                    epoch_blocks+=("$sub_block")
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
                    if [[ $(is_epoch_block "$current_yaml_block") == "true" ]]; then
                        epoch_blocks+=("$current_yaml_block")
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

    # Second pass: build epochs with resolved tasks
    local epochs_json="["
    local first_epoch=true

    for block in "${epoch_blocks[@]}"; do
        local epoch_id title status priority blocked_by

        # Extract epoch fields (support both id: EPOCH- and epoch_id: formats)
        epoch_id=$(extract_field "$block" "id")
        if [[ -z "$epoch_id" ]] || [[ ! "$epoch_id" =~ ^EPOCH- ]]; then
            epoch_id=$(extract_field "$block" "epoch_id")
        fi
        title=$(extract_field "$block" "title")
        status=$(extract_field "$block" "status")
        priority=$(extract_field "$block" "priority")
        blocked_by=$(extract_field "$block" "blocked_by" | tr -d '[]')
        priority="${priority:-p2}"

        # Get task references from epoch
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

        # Build epoch JSON
        local epoch_json="{"
        epoch_json+="\"epoch_id\":\"$epoch_id\""
        epoch_json+=",\"title\":\"$(echo "$title" | sed 's/"/\\"/g')\""
        epoch_json+=",\"status\":\"${status:-pending}\""
        epoch_json+=",\"priority\":\"$priority\""

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
            epoch_json+=",\"blocked_by\":$blocked_arr"
        else
            epoch_json+=",\"blocked_by\":[]"
        fi

        epoch_json+=",\"tasks\":$tasks_json"
        epoch_json+="}"

        if [[ "$first_epoch" == true ]]; then
            first_epoch=false
        else
            epochs_json+=","
        fi
        epochs_json+="$epoch_json"
    done

    epochs_json+="]"

    # Fallback: if no epochs found, try parsing flat task format
    if [[ "$epochs_json" == "[]" ]]; then
        local flat_result
        flat_result=$(parse_flat_tasks "$todos_file")
        if [[ "$flat_result" != "[]" ]]; then
            echo "$flat_result"
            return
        fi
    fi

    echo "$epochs_json"
}

#
# Get a specific epoch by ID
# Output: JSON object or empty
#
get_epoch() {
    local epoch_id="$1"
    local todos_file="${2:-$DEFAULT_TODOS_FILE}"

    local epochs
    epochs=$(parse_epochs "$todos_file")

    echo "$epochs" | jq -r ".[] | select(.epoch_id == \"$epoch_id\")"
}

#
# Get all tasks across all epochs (flattened)
# Output: JSON array of task objects with epoch_id field added
#
get_all_tasks() {
    local todos_file="${1:-$DEFAULT_TODOS_FILE}"

    local epochs
    epochs=$(parse_epochs "$todos_file")

    echo "$epochs" | jq '[.[] | .epoch_id as $eid | .tasks[] | . + {epoch_id: $eid}]'
}

#
# Derive epoch status from its tasks
# Input: JSON array of tasks, optional JSON array of all tasks (for cross-epoch blocked_by)
# Output: JSON object with derived_status and metrics
#
# A task is considered "blocked" if:
#   - Its explicit status is "blocked", OR
#   - It has blocked_by entries referencing incomplete tasks
#
derive_epoch_status() {
    local tasks_json="$1"
    local all_tasks_json="${2:-$tasks_json}"  # Fall back to same list if not provided

    # Use jq to compute counts with blocked_by awareness
    # A task is effectively blocked if status=="blocked" OR has unresolved blocked_by
    local metrics_json
    metrics_json=$(echo "$tasks_json" | jq --argjson all_tasks "$all_tasks_json" '
        # Build lookup of complete task IDs
        ($all_tasks | [.[] | select(.status == "complete") | .id]) as $complete_ids |

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

        # Derive status
        (if $total == 0 then "pending"
         elif $complete == $total then "complete"
         elif $in_progress > 0 then "in_progress"
         elif $blocked > 0 then "blocked"
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
# Get metrics for an epoch by ID
# Output: JSON with epoch info and derived metrics
#
get_epoch_metrics() {
    local epoch_id="$1"
    local todos_file="${2:-$DEFAULT_TODOS_FILE}"

    local epoch
    epoch=$(get_epoch "$epoch_id" "$todos_file")

    if [[ -z "$epoch" ]]; then
        echo "null"
        return 1
    fi

    # Get all tasks for cross-epoch blocked_by resolution
    local all_epochs
    all_epochs=$(parse_epochs "$todos_file")
    local all_tasks
    all_tasks=$(echo "$all_epochs" | jq '[.[] | .tasks[]]')

    local tasks
    tasks=$(echo "$epoch" | jq '.tasks')

    local status_info
    status_info=$(derive_epoch_status "$tasks" "$all_tasks")

    # Merge epoch data with derived status
    echo "$epoch" | jq --argjson status "$status_info" '. + {derived: $status}'
}

#
# Check if all blockers for an epoch are complete
# Input: epoch blocked_by array, all epochs JSON
# Output: "true" or "false"
#
check_epoch_blockers_complete() {
    local blocked_by="$1"
    local all_epochs="$2"

    # If no blockers, return true
    if [[ -z "$blocked_by" ]] || [[ "$blocked_by" == "[]" ]]; then
        echo "true"
        return
    fi

    # Check each blocker
    local result
    result=$(echo "$all_epochs" | jq --argjson blockers "$blocked_by" '
        ($blockers | length) == 0 or
        ([$blockers[] as $bid | .[] | select(.epoch_id == $bid) | .status == "complete" or (.tasks | all(.status == "complete"))] | all)
    ')

    echo "$result"
}

#
# Check if all blockers for a task are complete
# Input: task blocked_by array, all tasks in epoch JSON
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
# Get eligible epochs (pending or in_progress, blockers resolved)
# Output: JSON array of epochs sorted by priority
#
get_eligible_epochs() {
    local todos_file="${1:-$DEFAULT_TODOS_FILE}"

    local epochs
    epochs=$(parse_epochs "$todos_file")

    # Get all tasks for cross-epoch blocked_by resolution
    local all_tasks
    all_tasks=$(echo "$epochs" | jq '[.[] | .tasks[]]')

    # Add derived status to each epoch and filter
    # Respects both epoch-level blocked_by and task-level blocked_by
    echo "$epochs" | jq --argjson all_tasks "$all_tasks" '
        # Build lookup of complete epoch IDs
        ([.[] | select(
            (.tasks | length) > 0 and
            ([.tasks[] | select(.status == "complete")] | length) == (.tasks | length)
        ) | .epoch_id]) as $complete_epoch_ids |

        # Build lookup of complete task IDs
        ($all_tasks | [.[] | select(.status == "complete") | .id]) as $complete_task_ids |

        # Add derived status based on tasks (with blocked_by awareness)
        [.[] |
            . as $epoch |

            # Check if epoch-level blockers are resolved (inline, not def)
            (((.blocked_by // []) | length == 0) or
             ((.blocked_by // []) | all(. as $bid | $complete_epoch_ids | index($bid)))) as $epoch_unblocked |

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
             elif ($epoch_unblocked | not) then "blocked"
             elif $in_progress > 0 then "in_progress"
             elif $blocked > 0 and $blocked == ($total - $complete) then "blocked"
             elif $complete > 0 then "in_progress"
             else "pending" end) as $derived |

            . + {
                derived_status: $derived,
                task_metrics: {total: $total, complete: $complete},
                _epoch_blockers_resolved: $epoch_unblocked
            }
        ] |
        # Filter to eligible (pending or in_progress, epoch-level blockers resolved)
        [.[] | select(
            (.derived_status == "pending" or .derived_status == "in_progress") and
            ._epoch_blockers_resolved
        )] |
        # Sort: in_progress first, then by priority, then by epoch number
        # Use try-catch for epoch_id parsing to handle non-numeric IDs (e.g., FLAT-TASKS)
        sort_by(
            (if .derived_status == "in_progress" then 0 else 1 end),
            (if .priority == "p0" then 0 elif .priority == "p1" then 1 elif .priority == "p2" then 2 else 3 end),
            (try (.epoch_id | ltrimstr("EPOCH-") | tonumber) catch 9999)
        )
    '
}

#
# Get next eligible task from an epoch
# Input: epoch JSON, session ID, optional all tasks JSON (for cross-epoch blocked_by)
# Output: JSON task object or null
#
get_next_task_from_epoch() {
    local epoch_json="$1"
    local session_id="${2:-claude-session}"
    local all_tasks_json="${3:-}"

    # If all_tasks not provided, use tasks from this epoch only
    if [[ -z "$all_tasks_json" ]]; then
        all_tasks_json=$(echo "$epoch_json" | jq '.tasks')
    fi

    echo "$epoch_json" | jq --arg session "$session_id" --argjson all_tasks "$all_tasks_json" '
        # Build lookup of complete task IDs (from all epochs)
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
# Output: JSON object with epoch context and next task
#
get_next_task() {
    local todos_file="${1:-$DEFAULT_TODOS_FILE}"
    local session_id="${2:-claude-session}"

    # Parse all epochs first (needed for cross-epoch blocked_by resolution)
    local all_epochs
    all_epochs=$(parse_epochs "$todos_file")

    # Get all tasks for cross-epoch blocked_by resolution
    local all_tasks
    all_tasks=$(echo "$all_epochs" | jq '[.[] | .tasks[]]')

    # Get eligible epochs
    local eligible
    eligible=$(get_eligible_epochs "$todos_file")

    # Check if any eligible epochs
    local count
    count=$(echo "$eligible" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        cat <<EOF
{
  "status": "no_work_available",
  "message": "No eligible epochs found. All epochs may be complete or blocked.",
  "epoch": null,
  "task": null
}
EOF
        return
    fi

    # Get first eligible epoch
    local current_epoch
    current_epoch=$(echo "$eligible" | jq '.[0]')

    # Get next task from that epoch (pass all_tasks for cross-epoch blocked_by)
    local next_task
    next_task=$(get_next_task_from_epoch "$current_epoch" "$session_id" "$all_tasks")

    # If no eligible task in this epoch (all blocked), try next epoch
    if [[ "$next_task" == "null" ]] || [[ -z "$next_task" ]]; then
        local epoch_idx=1
        while [[ $epoch_idx -lt $count ]]; do
            current_epoch=$(echo "$eligible" | jq ".[$epoch_idx]")
            next_task=$(get_next_task_from_epoch "$current_epoch" "$session_id" "$all_tasks")
            if [[ "$next_task" != "null" ]] && [[ -n "$next_task" ]]; then
                break
            fi
            ((epoch_idx++))
        done
    fi

    # Build epoch queue (other pending epochs)
    local epoch_queue
    epoch_queue=$(echo "$eligible" | jq '[.[] | {epoch_id, title, priority, derived_status, task_metrics}]')

    # Build result
    jq -n \
        --argjson epoch "$current_epoch" \
        --argjson task "$next_task" \
        --argjson queue "$epoch_queue" \
        '{
            status: (if $task == null then "no_work_available" else "task_available" end),
            message: (if $task == null then "All tasks in eligible epochs are blocked." else null end),
            epoch: {
                epoch_id: $epoch.epoch_id,
                title: $epoch.title,
                priority: $epoch.priority,
                derived_status: $epoch.derived_status,
                task_count: ($epoch.tasks | length),
                complete_count: ([$epoch.tasks[] | select(.status == "complete")] | length)
            },
            task: $task,
            epoch_queue: $queue
        }'
}

#
# List all epochs with summary
# Output: JSON array with epoch summaries
#
list_epochs() {
    local todos_file="${1:-$DEFAULT_TODOS_FILE}"

    local epochs
    epochs=$(parse_epochs "$todos_file")

    # Get all tasks for cross-epoch blocked_by resolution
    local all_tasks
    all_tasks=$(echo "$epochs" | jq '[.[] | .tasks[]]')

    echo "$epochs" | jq --argjson all_tasks "$all_tasks" '
        # Build lookup of complete task IDs
        ($all_tasks | [.[] | select(.status == "complete") | .id]) as $complete_task_ids |

        # Build lookup of complete epoch IDs
        ([.[] | select(
            (.tasks | length) > 0 and
            ([.tasks[] | select(.status == "complete")] | length) == (.tasks | length)
        ) | .epoch_id]) as $complete_epoch_ids |

        [.[] |
            # Check if epoch-level blockers are resolved (inline)
            (((.blocked_by // []) | length == 0) or
             ((.blocked_by // []) | all(. as $bid | $complete_epoch_ids | index($bid)))) as $epoch_unblocked |

            {
                epoch_id,
                title,
                status,
                priority,
                blocked_by,
                epoch_blocked: ($epoch_unblocked | not),
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
        # Use try-catch for epoch_id parsing to handle non-numeric IDs (e.g., FLAT-TASKS)
        sort_by(
            (if .priority == "p0" then 0 elif .priority == "p1" then 1 elif .priority == "p2" then 2 else 3 end),
            (try (.epoch_id | ltrimstr("EPOCH-") | tonumber) catch 9999)
        )
    '
}

#
# Validate epochs and tasks structure
# Output: JSON with validation results and warnings
#
validate_epochs() {
    local todos_file="${1:-$DEFAULT_TODOS_FILE}"

    local epochs
    epochs=$(parse_epochs "$todos_file")

    # Validation checks
    local warnings="[]"
    local errors="[]"

    # Check each epoch
    warnings=$(echo "$epochs" | jq '
        [
            .[] |
            # Check for missing task IDs
            (.tasks | to_entries | .[] | select(.value.id == null or .value.id == "") |
                {type: "missing_task_id", epoch_id: .value.epoch_id, index: .key}) // empty,

            # Check for invalid status values
            (.tasks[] | select(.status | test("^(pending|in_progress|complete|blocked)$") | not) |
                {type: "invalid_status", task_id: .id, status: .status}) // empty,

            # Check for empty epochs
            (select(.tasks | length == 0) |
                {type: "empty_epoch", epoch_id: .epoch_id}) // empty
        ]
    ')

    local valid="true"
    if [[ $(echo "$warnings" | jq 'length') -gt 0 ]]; then
        valid="false"
    fi

    jq -n \
        --argjson warnings "$warnings" \
        --arg valid "$valid" \
        --argjson epoch_count "$(echo "$epochs" | jq 'length')" \
        '{
            valid: ($valid == "true"),
            epoch_count: $epoch_count,
            warnings: $warnings
        }'
}

# If script is run directly (not sourced), provide CLI interface
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # CLI mode
    COMMAND="${1:-help}"

    case "$COMMAND" in
        parse|epochs)
            parse_epochs "${2:-$DEFAULT_TODOS_FILE}"
            ;;
        get-epoch)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 get-epoch EPOCH-ID [todos_file]" >&2
                exit 1
            fi
            get_epoch "$2" "${3:-$DEFAULT_TODOS_FILE}"
            ;;
        metrics)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 metrics EPOCH-ID [todos_file]" >&2
                exit 1
            fi
            get_epoch_metrics "$2" "${3:-$DEFAULT_TODOS_FILE}"
            ;;
        next-task)
            get_next_task "${2:-$DEFAULT_TODOS_FILE}" "${3:-claude-session}"
            ;;
        list)
            list_epochs "${2:-$DEFAULT_TODOS_FILE}"
            ;;
        all-tasks)
            get_all_tasks "${2:-$DEFAULT_TODOS_FILE}"
            ;;
        validate)
            validate_epochs "${2:-$DEFAULT_TODOS_FILE}"
            ;;
        help|--help|-h)
            cat <<EOF
epoch-parser.sh - Parse epoch/task YAML from docs/ToDos.md

Usage: $0 <command> [args]

Commands:
  parse [file]              Parse all epochs, output JSON array
  get-epoch ID [file]       Get specific epoch by ID
  metrics ID [file]         Get epoch with derived status metrics
  next-task [file] [agent]  Get next eligible task to work on
  list [file]               List all epochs with summary
  all-tasks [file]          Get all tasks (flattened across epochs)
  validate [file]           Validate epoch/task structure
  help                      Show this help message

Default file: docs/ToDos.md

Examples:
  $0 parse
  $0 get-epoch EPOCH-011
  $0 next-task docs/ToDos.md claude-session
  $0 list
  $0 validate

As a library (source in other scripts):
  source /path/to/epoch-parser.sh
  epochs=\$(parse_epochs "docs/ToDos.md")
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
