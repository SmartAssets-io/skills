#!/usr/bin/env bash
#
# story-parser.sh - Shared library for parsing user stories from docs/UserStories.md
#
# This library provides functions to:
# 1. Parse user stories from markdown format
# 2. Extract story metadata (ID, title, status, acceptance criteria)
# 3. Manage story-epic linking
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
    local story_user_flow=""
    local in_criteria=false
    local criteria_json="["
    local first_criterion=true

    if [[ ! -f "$stories_file" ]]; then
        echo "[]"
        return 1
    fi

    local in_code_fence=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Track markdown code fences to skip template examples
        if [[ "$line" =~ ^\`\`\` ]]; then
            if [[ "$in_code_fence" == true ]]; then
                in_code_fence=false
            else
                in_code_fence=true
            fi
            continue
        fi

        # Skip lines inside code fences
        if [[ "$in_code_fence" == true ]]; then
            continue
        fi

        # A level-2 header (## ...) ends the current story
        if [[ "$line" =~ ^##[[:space:]] ]] && [[ ! "$line" =~ ^#### ]]; then
            if [[ "$in_story" == true ]] && [[ -n "$story_id" ]]; then
                criteria_json+="]"
                local story_obj
                story_obj=$(build_story_json "$story_id" "$story_title" "$story_status" "$story_implemented_in" "$story_persona" "$story_capability" "$story_benefit" "$criteria_json" "$story_user_flow")
                if [[ "$first_story" == true ]]; then
                    first_story=false
                else
                    stories_json+=","
                fi
                stories_json+="$story_obj"
            fi
            in_story=false
            in_criteria=false
            continue
        fi

        # Detect story header: #### US-XXX: Title
        if [[ "$line" =~ ^####[[:space:]]+US-([0-9]{3}):[[:space:]]*(.*)$ ]]; then
            # Save previous story if exists
            if [[ "$in_story" == true ]] && [[ -n "$story_id" ]]; then
                criteria_json+="]"
                local story_obj
                story_obj=$(build_story_json "$story_id" "$story_title" "$story_status" "$story_implemented_in" "$story_persona" "$story_capability" "$story_benefit" "$criteria_json" "$story_user_flow")
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
            story_user_flow=""
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
                # Extract just the EPIC-XXX part if present
                if [[ "$story_implemented_in" =~ (EPIC-[0-9]{3}) ]]; then
                    story_implemented_in="${BASH_REMATCH[1]}"
                fi
                continue
            fi

            # Parse Status field
            if [[ "$line" =~ ^\*\*Status:\*\*[[:space:]]*(.*)$ ]]; then
                story_status="${BASH_REMATCH[1]}"
                continue
            fi

            # Parse User Flow back-reference: **User Flow:** FLOW-NNN
            if [[ "$line" =~ ^\*\*User[[:space:]]+Flow:\*\*[[:space:]]*(.*)$ ]]; then
                story_user_flow="${BASH_REMATCH[1]}"
                if [[ "$story_user_flow" =~ (FLOW-[0-9]{3,4}) ]]; then
                    story_user_flow="${BASH_REMATCH[1]}"
                fi
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
        story_obj=$(build_story_json "$story_id" "$story_title" "$story_status" "$story_implemented_in" "$story_persona" "$story_capability" "$story_benefit" "$criteria_json" "$story_user_flow")
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
    local user_flow="${9:-}"

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
    if [[ -n "$user_flow" ]]; then
        json+=",\"user_flow\":\"$user_flow\""
    else
        json+=",\"user_flow\":null"
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
# Get all story-epic links
# Output: JSON array of {story_id, epic_id} objects
#
get_story_links() {
    local stories_file="${1:-$DEFAULT_USER_STORIES_FILE}"

    local stories
    stories=$(parse_stories "$stories_file")

    echo "$stories" | jq '[.[] | select(.implemented_in != null and .implemented_in != "" and .implemented_in != "Planned") | {story_id: .id, epic_id: .implemented_in}]'
}

#
# Insert a new story into UserStories.md
# Inserts before the "## Planned Stories" section or at end
# (also appends at end when the anchor heading is the file's first line)
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

    # An anchor on line 1 leaves no room to insert above it: `head -n 0` is an
    # error on BSD/macOS head, and prepending would push the story above the
    # document's opening section. Fall back to appending in that case.
    if [[ -n "$insert_line" ]] && (( insert_line > 1 )); then
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
update_story_epic_link() {
    local story_id="$1"
    local epic_id="$2"
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
            # Preserve existing links and add each epic only once.
            if [[ "$line" =~ ^\*\*Implemented[[:space:]]+in:\*\*[[:space:]]*(.*)$ ]]; then
                local implemented_in="${BASH_REMATCH[1]}"
                if [[ "$implemented_in" =~ ^[[:space:]]*(Planned)?[[:space:]]*$ ]]; then
                    printf '**Implemented in:** %s\n' "$epic_id"
                elif [[ "$implemented_in" =~ (^|[^[:alnum:]_-])${epic_id}([^[:alnum:]_-]|$) ]]; then
                    printf '%s\n' "$line"
                else
                    printf '%s, %s\n' "$line" "$epic_id"
                fi
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
# Update story's "User Flow:" field in UserStories.md (back-reference from a flow).
# Idempotent: if the field already exists, replaces its value; otherwise injects
# the field after "Implemented in:" or at the end of the story block.
#
update_story_flow_link() {
    local story_id="$1"
    local flow_id="$2"
    local stories_file="${3:-$DEFAULT_USER_STORIES_FILE}"

    cp "$stories_file" "${stories_file}.bak"

    local in_story=false
    local found_field=false
    local injected=false
    local temp_file="${stories_file}.tmp"

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Detect story boundaries
        if [[ "$line" =~ ^####[[:space:]]+${story_id}: ]]; then
            in_story=true
            found_field=false
            injected=false
        elif [[ "$line" =~ ^####[[:space:]]+US- ]] || [[ "$line" =~ ^##[[:space:]] ]]; then
            # Closing a different story; inject if needed before leaving target
            if [[ "$in_story" == true ]] && [[ "$found_field" == false ]] && [[ "$injected" == false ]]; then
                echo "**User Flow:** ${flow_id}"
                injected=true
            fi
            in_story=false
        fi

        if [[ "$in_story" == true ]]; then
            # Replace existing User Flow: field. If the inject path below already
            # emitted the field (it fires on "Implemented in:", which normally
            # precedes this line), swallow the original instead of replacing it -
            # otherwise both copies survive and the block accumulates duplicates.
            if [[ "$line" =~ ^\*\*User[[:space:]]+Flow:\*\* ]]; then
                if [[ "$injected" == false ]]; then
                    echo "**User Flow:** ${flow_id}"
                fi
                found_field=true
                continue
            fi
        fi

        echo "$line"

        # Inject right after the Implemented in: line for nicer placement
        if [[ "$in_story" == true ]] && [[ "$found_field" == false ]] && [[ "$injected" == false ]]; then
            if [[ "$line" =~ ^\*\*Implemented[[:space:]]+in:\*\* ]]; then
                echo "**User Flow:** ${flow_id}"
                injected=true
            fi
        fi
    done < "$stories_file" > "$temp_file"

    # Tail-case: story is the last block in the file
    if [[ "$in_story" == true ]] && [[ "$found_field" == false ]] && [[ "$injected" == false ]]; then
        echo "**User Flow:** ${flow_id}" >> "$temp_file"
    fi

    mv "$temp_file" "$stories_file"
}

#
# Update only the target epic document. Prefer an existing story list.
# Buffer each document so keys after tasks: do not cause duplicate insertion.
#
update_epic_story_link() {
    local epic_id="$1"
    local story_id="$2"
    local todos_file="${3:-docs/ToDos.md}"
    local content ending updated
    local temp_file="${todos_file}.tmp"

    if [[ ! "$epic_id" =~ ^EPIC-[0-9]{3}$ || ! "$story_id" =~ ^US-[0-9]{3}$ ]]; then
        printf '%s\n' 'Error: Invalid epic or story ID.' >&2
        return 1
    fi

    # Preserve final newlines, including an absent final newline.
    content=$(cat "$todos_file" && printf '.') || return 1
    content="${content%.}"
    ending="${content##*[!$'\n']}"
    updated=$(awk -v epic="$epic_id" -v story="$story_id" '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
        function value(s) {
            sub(/[ \t]*#.*/, "", s)
            s = trim(s)
            gsub(/^["\047]|["\047]$/, "", s)
            return s
        }
        function reject() {
            print "Error: Cannot safely update the epic story list." > "/dev/stderr"
            failed = 1
            exit 1
        }
        function flush(    i, plural, singular, tasks, at, rhs, end, inner, tail, n, items, item, seen, indent, eol) {
            if (target) {
                found++
                for (i = 1; i <= count; i++) {
                    if (text[i] ~ /^user_stories:/) { if (plural) reject(); plural = i }
                    if (text[i] ~ /^user_story:/) { if (singular) reject(); singular = i }
                    if (!tasks && text[i] ~ /^tasks:/) tasks = i
                }
                eol = raw[1] ~ /\r$/ ? "\r" : ""
                if (plural) {
                    rhs = text[plural]
                    sub(/^user_stories:[ \t]*/, "", rhs)
                    if (rhs ~ /^\[/) {
                        end = index(rhs, "]")
                        if (!end) reject()
                        inner = substr(rhs, 2, end - 2)
                        tail = substr(rhs, end + 1)
                        if (tail !~ /^[ \t]*(#.*)?$/) reject()
                        n = split(inner, items, ",")
                        for (i = 1; i <= n; i++) {
                            item = value(items[i])
                            if (!item && n == 1) continue
                            if (item !~ /^US-[0-9][0-9][0-9]$/) reject()
                            if (item == story) seen = 1
                        }
                        if (!seen) {
                            sub(/[ \t]+$/, "", inner)
                            raw[plural] = substr(text[plural], 1, length(text[plural]) - length(rhs)) \
                                "[" inner (trim(inner) == "" ? "" : ", ") story "]" tail eol
                        }
                    } else if (rhs ~ /^[ \t]*(#.*)?$/ || rhs == "null" || rhs == "~") {
                        at = plural + 1
                        indent = "  "
                        for (i = plural + 1; i <= count; i++) {
                            if (text[i] ~ /^[ \t]*($|#)/) continue
                            if (text[i] !~ /^[ \t]*-[ \t]+/) {
                                if (text[i] ~ /^[ \t]+/) reject()
                                break
                            }
                            item = text[i]
                            sub(/^[ \t]*-[ \t]+/, "", item)
                            item = value(item)
                            if (item !~ /^US-[0-9][0-9][0-9]$/) reject()
                            if (item == story) seen = 1
                            indent = text[i]
                            sub(/[^ \t].*$/, "", indent)
                            at = i + 1
                        }
                        if (!seen) {
                            if (rhs == "null" || rhs == "~") raw[plural] = "user_stories:" eol
                            insertion = indent "- " story eol
                        } else at = 0
                    } else reject()
                } else if (singular) {
                    if (value(substr(text[singular], index(text[singular], ":") + 1)) != story)
                        raw[singular] = "user_story: " story eol
                } else {
                    at = tasks ? tasks : count + 1
                    insertion = "user_story: " story eol
                }
            }
            for (i = 1; i <= count; i++) {
                if (i == at) print insertion
                print raw[i]
                delete raw[i]
                delete text[i]
            }
            if (at == count + 1) print insertion
            count = target = identity = 0
            insertion = ""
        }
        {
            line = $0
            sub(/\r$/, "", line)
            if (!yaml) {
                print $0
                if (line ~ /^```yaml[ \t]*$/) yaml = 1
                next
            }
            if (line ~ /^```[ \t]*$/ || line ~ /^---[ \t]*(#.*)?$/) {
                flush()
                print $0
                if (line ~ /^```/) yaml = 0
                next
            }
            if (line ~ /^(epic_id|id):/) {
                if (identity) flush()
                identity = 1
                id = line
                sub(/^[^:]*:[ \t]*/, "", id)
                target = value(id) == epic
            }
            raw[++count] = $0
            text[count] = line
        }
        END {
            if (failed) exit 1
            flush()
            if (found != 1) {
                print "Error: Expected one target epic document." > "/dev/stderr"
                exit 1
            }
        }
    ' <<<"$content") || return 1

    cp "$todos_file" "${todos_file}.bak" || return 1
    printf '%s%s' "$updated" "$ending" > "$temp_file" || return 1
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
  links [file]              Get all story-epic links
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
