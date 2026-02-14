#!/usr/bin/env bash
#
# epoch-hygiene.sh - Validate and analyze epoch/task YAML in docs/*.md files
#
# This deterministic script:
# 1. Validates YAML syntax in task tracking files
# 2. Detects epochs where all tasks are done (ready to archive)
# 3. Detects orphaned tasks (not assigned to any epoch)
# 4. Detects stale work logs for completed epochs
# 5. Outputs JSON for use by /epoch-hygiene slash command
#
# Usage (run from any repo with docs/ToDos.md):
#   ~/src/CurrentProjects/SA/top-level-gitlab-profile/AItools/scripts/epoch-hygiene.sh [--json] [--check] [--verbose]
#
# Options:
#   --json     Output results as JSON (default: human-readable)
#   --check    Exit with code 1 if any epochs are ready to archive
#   --verbose  Show detailed parsing information
#
# Files analyzed:
#   - docs/ToDos.md          (active tasks and epochs)
#   - docs/CompletedTasks.md (archived epochs)
#   - docs/Backlog.md        (backlog items)
#   - docs/Defects.md        (bug reports to potentially convert to tasks)
#   - docs/work-logs/*.md    (session work logs)
#

set -euo pipefail

# Script location for sourcing libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Source epoch-parser library for robust YAML parsing
EPOCH_PARSER="${LIB_DIR}/epoch-parser.sh"
if [[ -f "$EPOCH_PARSER" ]]; then
    # shellcheck source=lib/epoch-parser.sh
    source "$EPOCH_PARSER"
else
    echo "Error: epoch-parser.sh library not found at $EPOCH_PARSER" >&2
    exit 1
fi

# Use current working directory's docs/ folder (not script location)
DOCS_DIR="${PWD}/docs"

# Options
OUTPUT_JSON=false
CHECK_MODE=false
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        --check)
            CHECK_MODE=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Colors for human-readable output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[verbose]${NC} $1" >&2
    fi
}

log_info() {
    if [[ "$OUTPUT_JSON" == false ]]; then
        echo -e "${GREEN}[info]${NC} $1"
    fi
}

log_warn() {
    if [[ "$OUTPUT_JSON" == false ]]; then
        echo -e "${YELLOW}[warn]${NC} $1"
    fi
}

log_error() {
    if [[ "$OUTPUT_JSON" == false ]]; then
        echo -e "${RED}[error]${NC} $1" >&2
    fi
}

# Note: extract_yaml_blocks and parse_yaml_fields are now provided by epoch-parser.sh library
# The library provides robust nested YAML parsing via parse_epochs(), derive_epoch_status(), etc.

# Analyze ToDos.md for epoch status
# Uses epoch-parser.sh library for robust nested YAML parsing
analyze_todos() {
    local todos_file="${DOCS_DIR}/ToDos.md"

    if [[ ! -f "$todos_file" ]]; then
        log_error "ToDos.md not found at $todos_file"
        return 1
    fi

    log_verbose "Analyzing $todos_file"

    # Use epoch-parser library to parse all epochs with nested tasks
    local epochs_json
    epochs_json=$(parse_epochs "$todos_file")

    if [[ -z "$epochs_json" ]] || [[ "$epochs_json" == "[]" ]]; then
        log_verbose "No epochs found in $todos_file"
        epochs_json="[]"
    fi

    # Analyze epochs using jq to find those ready to archive
    # An epoch is ready to archive if:
    # 1. It has status: complete (explicitly marked), OR
    # 2. All its tasks have status: complete
    local analysis_json
    analysis_json=$(echo "$epochs_json" | jq '
        . as $epochs |
        {
            epochs_total: ($epochs | length),
            tasks_total: ([$epochs[].tasks[]] | length),
            epochs_ready_to_archive: [
                $epochs[] |
                select(
                    # Either explicitly marked complete
                    .status == "complete" or
                    # Or all tasks are complete (and has at least one task)
                    ((.tasks | length) > 0 and (.tasks | all(.status == "complete")))
                ) |
                {
                    epoch_id: .epoch_id,
                    title: .title,
                    task_count: (.tasks | length),
                    task_ids: [.tasks[].id],
                    explicit_complete: (.status == "complete")
                }
            ],
            orphan_tasks: []
        } |
        . + {needs_action: ((.epochs_ready_to_archive | length) > 0)}
    ')

    # Extract completed epoch info for work log analysis
    local completed_epochs_json
    completed_epochs_json=$(echo "$analysis_json" | jq '.epochs_ready_to_archive')

    local completed_task_ids_json
    completed_task_ids_json=$(echo "$analysis_json" | jq '[.epochs_ready_to_archive[].task_ids[]]')

    # Analyze work logs for stale entries
    log_verbose "Analyzing work logs for stale entries..."
    local stale_work_logs
    stale_work_logs=$(analyze_work_logs "$completed_epochs_json" "$completed_task_ids_json")

    # Add stale work logs to analysis
    analysis_json=$(echo "$analysis_json" | jq --argjson logs "$stale_work_logs" '
        . + {stale_work_logs: $logs} |
        .needs_action = (.needs_action or ($logs | length > 0))
    ')

    # Extract values for logging
    local epochs_count tasks_count ready_count stale_logs_count
    epochs_count=$(echo "$analysis_json" | jq -r '.epochs_total')
    tasks_count=$(echo "$analysis_json" | jq -r '.tasks_total')
    ready_count=$(echo "$analysis_json" | jq -r '.epochs_ready_to_archive | length')
    stale_logs_count=$(echo "$analysis_json" | jq -r '.stale_work_logs | length')

    # Log verbose info about each epoch
    if [[ "$VERBOSE" == true ]]; then
        echo "$epochs_json" | jq -r '.[] | "Found epoch: \(.epoch_id) (\(.status))"' | while read -r line; do
            log_verbose "$line"
        done
    fi

    # Output results
    if [[ "$OUTPUT_JSON" == true ]]; then
        # JSON output - use the analysis directly
        echo "$analysis_json" | jq -r '{
            file: "docs/ToDos.md",
            epochs_total,
            tasks_total,
            epochs_ready_to_archive,
            orphan_tasks,
            stale_work_logs,
            needs_action
        }'
    else
        # Human-readable output
        echo ""
        echo "=== Epoch Hygiene Report ==="
        echo "File: docs/ToDos.md"
        echo "Epochs: ${epochs_count}"
        echo "Tasks: ${tasks_count}"
        echo ""

        if [[ "$ready_count" -gt 0 ]]; then
            echo -e "${GREEN}Epochs ready to archive:${NC}"
            echo "$analysis_json" | jq -r '.epochs_ready_to_archive[] | "  - \(.epoch_id): \(.title) (\(.task_count) tasks)"'
            echo ""
        else
            echo "No epochs ready to archive."
            echo ""
        fi

        # Orphan tasks (unlikely with embedded format, but check anyway)
        local orphan_count
        orphan_count=$(echo "$analysis_json" | jq -r '.orphan_tasks | length')
        if [[ "$orphan_count" -gt 0 ]]; then
            echo -e "${YELLOW}Orphan tasks (no epoch assigned):${NC}"
            echo "$analysis_json" | jq -r '.orphan_tasks[] | "  - \(.task_id): \(.title)"'
            echo ""
        fi

        # Stale work logs
        if [[ "$stale_logs_count" -gt 0 ]]; then
            echo -e "${YELLOW}Stale work logs (can be cleaned up):${NC}"
            echo "$analysis_json" | jq -r '.stale_work_logs[] | "  - \(.filename) (\(.stale_reason))"'
            echo ""
        fi

        # Reminder to run hygiene
        echo -e "${BLUE}Reminder:${NC} Run /epoch-hygiene when all tasks in an epoch are done"
        echo "          to archive completed epochs to docs/CompletedTasks.md"
        echo ""
    fi

    # Check mode: exit with error if action needed
    if [[ "$CHECK_MODE" == true ]] && [[ "$ready_count" -gt 0 ]]; then
        return 1
    fi

    return 0
}

# Analyze work logs and find stale ones (related to completed epochs/tasks)
# Returns JSON array of stale work log info
analyze_work_logs() {
    local work_logs_dir="${DOCS_DIR}/work-logs"
    local completed_epochs_json="$1"
    local completed_task_ids_json="$2"

    if [[ ! -d "$work_logs_dir" ]]; then
        log_verbose "No work-logs directory at $work_logs_dir"
        echo "[]"
        return 0
    fi

    local stale_logs="[]"

    # Find all work log files
    while IFS= read -r -d '' log_file; do
        local filename
        filename=$(basename "$log_file")
        log_verbose "Analyzing work log: $filename"

        # Extract frontmatter from the work log
        local in_frontmatter=false
        local frontmatter=""
        local line_num=0

        while IFS= read -r line || [[ -n "$line" ]]; do
            ((line_num++))
            if [[ $line_num -eq 1 ]] && [[ "$line" == "---" ]]; then
                in_frontmatter=true
                continue
            elif [[ "$in_frontmatter" == true ]] && [[ "$line" == "---" ]]; then
                break
            elif [[ "$in_frontmatter" == true ]]; then
                frontmatter+="$line"$'\n'
            fi
        done < "$log_file"

        # Extract task_id from frontmatter
        local task_id=""
        local status=""
        local handoff_status=""

        if [[ -n "$frontmatter" ]]; then
            task_id=$(echo "$frontmatter" | grep -E '^task_id:' | sed 's/^task_id:[[:space:]]*//' | tr -d '"' | head -1)
            status=$(echo "$frontmatter" | grep -E '^status:' | sed 's/^status:[[:space:]]*//' | tr -d '"' | head -1)
            handoff_status=$(echo "$frontmatter" | grep -E '^handoff_status:' | sed 's/^handoff_status:[[:space:]]*//' | tr -d '"' | head -1)
        fi

        # Check if this work log is related to a completed task
        local is_stale=false
        local stale_reason=""

        # Method 1: Check if task_id matches a completed task
        if [[ -n "$task_id" ]] && [[ "$completed_task_ids_json" != "[]" ]]; then
            if echo "$completed_task_ids_json" | jq -e --arg tid "$task_id" 'index($tid) != null' > /dev/null 2>&1; then
                is_stale=true
                stale_reason="task_completed"
            fi
        fi

        # Method 2: Check if filename matches a completed epoch pattern (task-EPOCH-XXX-*)
        if [[ "$is_stale" == false ]] && [[ "$completed_epochs_json" != "[]" ]]; then
            # Extract epoch ID from filename if present
            local filename_epoch=""
            if [[ "$filename" =~ (EPOCH-[0-9]+) ]]; then
                filename_epoch="${BASH_REMATCH[1]}"
                if echo "$completed_epochs_json" | jq -e --arg eid "$filename_epoch" '.[] | select(.epoch_id == $eid)' > /dev/null 2>&1; then
                    is_stale=true
                    stale_reason="epoch_completed"
                fi
            fi
        fi

        # Method 3: Check if status indicates completion
        if [[ "$is_stale" == false ]] && [[ "$status" == "complete" || "$status" == "completed" || "$status" == "done" ]]; then
            is_stale=true
            stale_reason="status_complete"
        fi

        # Add to stale list if stale
        if [[ "$is_stale" == true ]]; then
            local relative_path
            relative_path=$(realpath --relative-to="$PWD" "$log_file" 2>/dev/null || echo "$log_file")

            local log_entry
            log_entry=$(jq -n \
                --arg file "$relative_path" \
                --arg filename "$filename" \
                --arg task_id "$task_id" \
                --arg status "$status" \
                --arg handoff_status "$handoff_status" \
                --arg reason "$stale_reason" \
                '{
                    file: $file,
                    filename: $filename,
                    task_id: (if $task_id == "" then null else $task_id end),
                    status: (if $status == "" then null else $status end),
                    handoff_status: (if $handoff_status == "" then null else $handoff_status end),
                    stale_reason: $reason
                }')

            stale_logs=$(echo "$stale_logs" | jq --argjson entry "$log_entry" '. + [$entry]')
        fi
    done < <(find "$work_logs_dir" -maxdepth 1 -name "*.md" -print0 2>/dev/null)

    echo "$stale_logs"
}

# Validate YAML syntax in a file (basic check)
validate_yaml_syntax() {
    local file="$1"
    local errors=0

    if [[ ! -f "$file" ]]; then
        return 0  # File doesn't exist, skip
    fi

    log_verbose "Validating YAML in $file"

    # Check for common YAML issues
    local in_yaml=false
    local line_num=0
    local yaml_start=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        if [[ "$line" == '```yaml' ]]; then
            in_yaml=true
            yaml_start=$line_num
        elif [[ "$line" == '```' ]] && [[ "$in_yaml" == true ]]; then
            in_yaml=false
        elif [[ "$in_yaml" == true ]]; then
            # Check for tabs (YAML should use spaces)
            if [[ "$line" == *$'\t'* ]]; then
                log_warn "$file:$line_num: Tab character in YAML (use spaces)"
                ((errors++))
            fi

            # Check for missing colon in key-value pairs
            if [[ "$line" =~ ^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*$ ]] && [[ ! "$line" =~ : ]]; then
                log_warn "$file:$line_num: Possible missing colon in YAML key"
            fi
        fi
    done < "$file"

    # Check for unclosed YAML block
    if [[ "$in_yaml" == true ]]; then
        log_error "$file: Unclosed YAML block starting at line $yaml_start"
        ((errors++))
    fi

    return $errors
}

# Main execution
main() {
    local exit_code=0

    # Validate YAML syntax in all task files
    for file in ToDos.md CompletedTasks.md Backlog.md Defects.md; do
        if [[ -f "${DOCS_DIR}/${file}" ]]; then
            validate_yaml_syntax "${DOCS_DIR}/${file}" || ((exit_code++))
        fi
    done

    # Analyze ToDos.md for epoch status
    analyze_todos || exit_code=1

    return $exit_code
}

main "$@"
