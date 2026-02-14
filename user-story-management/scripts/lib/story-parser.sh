#!/usr/bin/env bash
#
# story-parser.sh - Shared library for parsing user stories from docs/UserStories.md
#
# This library provides functions to:
# 1. Parse user stories from markdown format
# 2. Extract story metadata (ID, title, status, acceptance criteria)
# 3. Manage story-epoch linking
# 4. Generate new story IDs
#
# Usage:
#   source /path/to/story-parser.sh
#   parse_stories "docs/UserStories.md"
#   get_story "US-010" "docs/UserStories.md"
#
# Dependencies:
#   - jq (required for JSON manipulation)
#   - bash 4+ (for associative arrays)
#

# Prevent re-sourcing
if [[ -n "${STORY_PARSER_LOADED:-}" ]]; then
    return 0
fi
STORY_PARSER_LOADED=1

# Default file path
DEFAULT_USER_STORIES_FILE="docs/UserStories.md"

#
# Parse all stories from UserStories.md
# Output: JSON array of story objects
#
parse_stories() {
    local stories_file="${1:-$DEFAULT_USER_STORIES_FILE}"
    local stories_json="["
    local first_story=true
    local in_story=false
    local current_story=""
    local story_id=""
    local story_title=""
    local story_status=""
    local story_implemented_in=""
    local story_persona=""
    local story_capability=""
    local story_benefit=""
    local in_criteria=false
    local criteria_json="["
    local first_criterion=true

    if [[ ! -f "$stories_file" ]]; then
        echo "[]"
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Detect story header: #### US-XXX: Title
        if [[ "$line" =~ ^####[[:space:]]+US-([0-9]{3}):[[:space:]]*(.*)$ ]]; then
            # Save previous story if exists
            if [[ "$in_story" == true ]] && [[ -n "$story_id" ]]; then
                criteria_json+="]"
                local story_obj
                story_obj=$(build_story_json "$story_id" "$story_title" "$story_status" "$story_implemented_in" "$story_persona" "$story_capability" "$story_benefit" "$criteria_json")
                if [[ "$first_story" == true ]]; then
                    first_story=false
                else
                    stories_json+=","
                fi
                stories_json+="$story_obj"
            fi

            # Start new story
            in_story=true
            story_id="US-${BASH_REMATCH[1]}"
            story_title="${BASH_REMATCH[2]}"
            story_status=""
            story_implemented_in=""
            story_persona=""
            story_capability=""
            story_benefit=""
            in_criteria=false
            criteria_json="["
            first_criterion=true
            continue
        fi

        if [[ "$in_story" == true ]]; then
            # Parse story statement: > As a **persona**, I want **capability** so that **benefit**.
            if [[ "$line" =~ ^\>[[:space:]]*As[[:space:]]+a[[:space:]]+\*\*([^*]+)\*\*.*want[[:space:]]+\*\*([^*]+)\*\*.*that[[:space:]]+\*\*([^*]+)\*\* ]]; then
                story_persona="${BASH_REMATCH[1]}"
                story_capability="${BASH_REMATCH[2]}"
                story_benefit="${BASH_REMATCH[3]}"
                # Remove trailing period if present
                story_benefit="${story_benefit%.}"
                continue
            fi

            # Parse Implemented in field
            if [[ "$line" =~ ^\*\*Implemented[[:space:]]+in:\*\*[[:space:]]*(.*)$ ]]; then
                story_implemented_in="${BASH_REMATCH[1]}"
                # Extract just the EPOCH-XXX part if present
                if [[ "$story_implemented_in" =~ (EPOCH-[0-9]{3}) ]]; then
                    story_implemented_in="${BASH_REMATCH[1]}"
                fi
                continue
            fi

            # Parse Status field
            if [[ "$line" =~ ^\*\*Status:\*\*[[:space:]]*(.*)$ ]]; then
                story_status="${BASH_REMATCH[1]}"
                continue
            fi

            # Parse Completed field (indicates complete status)
            if [[ "$line" =~ ^\*\*Completed:\*\*[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
                story_status="Completed"
                continue
            fi

            # Detect acceptance criteria section
            if [[ "$line" =~ ^\*\*Acceptance[[:space:]]+Criteria:\*\* ]]; then
                in_criteria=true
                continue
            fi

            # Parse acceptance criteria items
            if [[ "$in_criteria" == true ]]; then
                # Checked item: - [x] text
                if [[ "$line" =~ ^-[[:space:]]+\[x\][[:space:]]+(.*)$ ]]; then
                    local criterion_text="${BASH_REMATCH[1]}"
                    if [[ "$first_criterion" == true ]]; then
                        first_criterion=false
                    else
                        criteria_json+=","
                    fi
                    criteria_json+="{\"text\":\"$(echo "$criterion_text" | sed 's/"/\\"/g')\",\"complete\":true}"
                    continue
                fi

                # Unchecked item: - [ ] text
                if [[ "$line" =~ ^-[[:space:]]+\[\][[:space:]]+(.*)$ ]] || [[ "$line" =~ ^-[[:space:]]+\[[[:space:]]\][[:space:]]+(.*)$ ]]; then
                    local criterion_text="${BASH_REMATCH[1]}"
                    if [[ "$first_criterion" == true ]]; then
                        first_criterion=false
                    else
                        criteria_json+=","
                    fi
                    criteria_json+="{\"text\":\"$(echo "$criterion_text" | sed 's/"/\\"/g')\",\"complete\":false}"
                    continue
                fi

                # End of criteria section (empty line or new section)
                if [[ -z "$line" ]] || [[ "$line" =~ ^(\*\*|####|---) ]]; then
                    in_criteria=false
                fi
            fi

            # End of story (horizontal rule or new story header)
            if [[ "$line" == "---" ]] && [[ "$in_criteria" == false ]]; then
                # Will be saved when next story is found or at EOF
                continue
            fi
        fi
    done < "$stories_file"

    # Save last story if exists
    if [[ "$in_story" == true ]] && [[ -n "$story_id" ]]; then
        criteria_json+="]"
        local story_obj
        story_obj=$(build_story_json "$story_id" "$story_title" "$story_status" "$story_implemented_in" "$story_persona" "$story_capability" "$story_benefit" "$criteria_json")
        if [[ "$first_story" == true ]]; then
            first_story=false
        else
            stories_json+=","
        fi
        stories_json+="$story_obj"
    fi

    stories_json+="]"
    echo "$stories_json"
}

#
# Build story JSON object
#
build_story_json() {
    local id="$1"
    local title="$2"
    local status="${3:-Planned}"
    local implemented_in="$4"
    local persona="$5"
    local capability="$6"
    local benefit="$7"
    local criteria_json="$8"

    # Default status
    if [[ -z "$status" ]]; then
        status="Planned"
    fi

    local json="{"
    json+="\"id\":\"$id\""
    json+=",\"title\":\"$(echo "$title" | sed 's/"/\\"/g')\""
    json+=",\"status\":\"$status\""

    if [[ -n "$implemented_in" ]]; then
        json+=",\"implemented_in\":\"$implemented_in\""
    else
        json+=",\"implemented_in\":null"
    fi

    if [[ -n "$persona" ]]; then
        json+=",\"persona\":\"$(echo "$persona" | sed 's/"/\\"/g')\""
    fi
    if [[ -n "$capability" ]]; then
        json+=",\"capability\":\"$(echo "$capability" | sed 's/"/\\"/g')\""
    fi
    if [[ -n "$benefit" ]]; then
        json+=",\"benefit\":\"$(echo "$benefit" | sed 's/"/\\"/g')\""
    fi

    json+=",\"acceptance_criteria\":$criteria_json"
    json+="}"

    echo "$json"
}

#
# Get a specific story by ID
# Output: JSON object or empty
#
get_story() {
    local story_id="$1"
    local stories_file="${2:-$DEFAULT_USER_STORIES_FILE}"

    local stories
    stories=$(parse_stories "$stories_file")

    echo "$stories" | jq -r ".[] | select(.id == \"$story_id\")"
}

#
# Check if a story exists
# Output: "true" or "false"
#
story_exists() {
    local story_id="$1"
    local stories_file="${2:-$DEFAULT_USER_STORIES_FILE}"

    local story
    story=$(get_story "$story_id" "$stories_file")

    if [[ -n "$story" ]] && [[ "$story" != "null" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

#
# Get next available story ID
# Output: Next ID (e.g., US-011)
#
get_next_story_id() {
    local stories_file="${1:-$DEFAULT_USER_STORIES_FILE}"

    local stories
    stories=$(parse_stories "$stories_file")

    # Extract highest ID number
    local max_num
    max_num=$(echo "$stories" | jq -r '[.[] | .id | ltrimstr("US-") | tonumber] | max // 0')

    local next_num=$((max_num + 1))
    printf "US-%03d" "$next_num"
}

#
# Get all story-epoch links
# Output: JSON array of {story_id, epoch_id} objects
#
get_story_links() {
    local stories_file="${1:-$DEFAULT_USER_STORIES_FILE}"

    local stories
    stories=$(parse_stories "$stories_file")

    echo "$stories" | jq '[.[] | select(.implemented_in != null and .implemented_in != "" and .implemented_in != "Planned") | {story_id: .id, epoch_id: .implemented_in}]'
}

#
# Insert a new story into UserStories.md
# Inserts before the "## Planned Stories" section or at end
#
insert_story() {
    local stories_file="$1"
    local story_md="$2"
    local story_id="$3"

    # Create backup
    cp "$stories_file" "${stories_file}.bak"

    # Find insertion point - before "## Planned Stories" or "## Story Template"
    local insert_line
    insert_line=$(grep -n "^## Planned Stories\|^## Story Template" "$stories_file" | head -1 | cut -d: -f1)

    if [[ -n "$insert_line" ]]; then
        # Insert before the found section
        {
            head -n $((insert_line - 1)) "$stories_file"
            echo ""
            echo -e "$story_md"
            tail -n +$insert_line "$stories_file"
        } > "${stories_file}.tmp"
        mv "${stories_file}.tmp" "$stories_file"
    else
        # Append at end
        echo "" >> "$stories_file"
        echo -e "$story_md" >> "$stories_file"
    fi
}

#
# Update story's "Implemented in" field
#
update_story_epoch_link() {
    local story_id="$1"
    local epoch_id="$2"
    local stories_file="${3:-$DEFAULT_USER_STORIES_FILE}"

    # Create backup
    cp "$stories_file" "${stories_file}.bak"

    local in_story=false
    local updated=false
    local temp_file="${stories_file}.tmp"

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Detect our story
        if [[ "$line" =~ ^####[[:space:]]+${story_id}: ]]; then
            in_story=true
        elif [[ "$line" =~ ^####[[:space:]]+US- ]] || [[ "$line" =~ ^##[[:space:]] ]]; then
            in_story=false
        fi

        if [[ "$in_story" == true ]]; then
            # Update Implemented in field if it exists
            if [[ "$line" =~ ^\*\*Implemented[[:space:]]+in:\*\* ]]; then
                echo "**Implemented in:** ${epoch_id}"
                updated=true
                continue
            fi

            # Update Status to In Progress if currently Planned
            if [[ "$line" =~ ^\*\*Status:\*\*[[:space:]]*Planned ]]; then
                echo "**Status:** In Progress"
                continue
            fi
        fi

        echo "$line"
    done < "$stories_file" > "$temp_file"

    mv "$temp_file" "$stories_file"
}

#
# Update epoch's user_story field in ToDos.md
#
update_epoch_story_link() {
    local epoch_id="$1"
    local story_id="$2"
    local todos_file="${3:-docs/ToDos.md}"

    # Create backup
    cp "$todos_file" "${todos_file}.bak"

    local in_epoch_yaml=false
    local in_target_epoch=false
    local added_link=false
    local temp_file="${todos_file}.tmp"

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Detect YAML block start
        if [[ "$line" == '```yaml' ]]; then
            in_epoch_yaml=true
            echo "$line"
            continue
        fi

        # Detect YAML block end
        if [[ "$line" == '```' ]] && [[ "$in_epoch_yaml" == true ]]; then
            # If we're in the target epoch and haven't added link yet, add it before closing
            if [[ "$in_target_epoch" == true ]] && [[ "$added_link" == false ]]; then
                echo "user_story: ${story_id}"
                added_link=true
            fi
            in_epoch_yaml=false
            in_target_epoch=false
            echo "$line"
            continue
        fi

        if [[ "$in_epoch_yaml" == true ]]; then
            # Check if this is our target epoch
            if [[ "$line" =~ ^epoch_id:[[:space:]]*${epoch_id}$ ]]; then
                in_target_epoch=true
            fi

            # If we find user_story field and we're in target epoch, update it
            if [[ "$in_target_epoch" == true ]] && [[ "$line" =~ ^user_story: ]]; then
                echo "user_story: ${story_id}"
                added_link=true
                continue
            fi

            # Add user_story before tasks: if we haven't added it yet
            if [[ "$in_target_epoch" == true ]] && [[ "$line" =~ ^tasks: ]] && [[ "$added_link" == false ]]; then
                echo "user_story: ${story_id}"
                added_link=true
            fi
        fi

        echo "$line"
    done < "$todos_file" > "$temp_file"

    mv "$temp_file" "$todos_file"
}

# If script is run directly (not sourced), provide CLI interface
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    COMMAND="${1:-help}"

    case "$COMMAND" in
        parse|stories)
            parse_stories "${2:-$DEFAULT_USER_STORIES_FILE}"
            ;;
        get-story)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 get-story US-XXX [stories_file]" >&2
                exit 1
            fi
            get_story "$2" "${3:-$DEFAULT_USER_STORIES_FILE}"
            ;;
        exists)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 exists US-XXX [stories_file]" >&2
                exit 1
            fi
            story_exists "$2" "${3:-$DEFAULT_USER_STORIES_FILE}"
            ;;
        next-id)
            get_next_story_id "${2:-$DEFAULT_USER_STORIES_FILE}"
            ;;
        links)
            get_story_links "${2:-$DEFAULT_USER_STORIES_FILE}"
            ;;
        help|--help|-h)
            cat <<EOF
story-parser.sh - Parse user stories from docs/UserStories.md

Usage: $0 <command> [args]

Commands:
  parse [file]              Parse all stories, output JSON array
  get-story ID [file]       Get specific story by ID
  exists ID [file]          Check if story exists (true/false)
  next-id [file]            Get next available story ID
  links [file]              Get all story-epoch links
  help                      Show this help message

Default file: docs/UserStories.md

Examples:
  $0 parse
  $0 get-story US-010
  $0 exists US-010
  $0 next-id
  $0 links

As a library (source in other scripts):
  source /path/to/story-parser.sh
  stories=\$(parse_stories "docs/UserStories.md")
  story=\$(get_story "US-010")
EOF
            ;;
        *)
            echo "Unknown command: $COMMAND" >&2
            echo "Run '$0 help' for usage" >&2
            exit 1
            ;;
    esac
fi
