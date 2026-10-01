#!/usr/bin/env bash
#
# review-aggregator.sh - Aggregation and consensus logic for multi-agent reviews
#
# This library provides:
# 1. Consensus calculation from multiple reviews
# 2. Issue deduplication and merging
# 3. Severity escalation for multi-reported issues
# 4. Summary generation
# 5. Markdown output formatting
#
# Usage:
#   source /path/to/review-aggregator.sh
#   result=$(aggregate_reviews "$reviews_json")
#   summary=$(generate_summary "$aggregated_result")
#
# Dependencies:
#   - jq (required for JSON manipulation)
#   - bash 4+ for associative arrays
#

# Prevent re-sourcing
if [[ -n "${REVIEW_AGGREGATOR_LOADED:-}" ]]; then
    return 0
fi
REVIEW_AGGREGATOR_LOADED=1

# Configuration
CONSENSUS_THRESHOLD="${CONSENSUS_THRESHOLD:-0.6}"  # 60% agreement required
MIN_PROVIDERS_FOR_CONSENSUS="${MIN_PROVIDERS_FOR_CONSENSUS:-2}"

# Severity levels (lower is more severe)
declare -A SEVERITY_RANK=(
    ["critical"]=0
    ["major"]=1
    ["minor"]=2
    ["suggestion"]=3
)

# Verdict icons for output (ordered by severity)
declare -A VERDICT_ICONS=(
    ["critical_vulnerabilities"]=":rotating_light:"
    ["needs_review"]=":mag:"
    ["provide_feedback"]=":bulb:"
    ["comment_only"]=":speech_balloon:"
    ["approve"]=":white_check_mark:"
    ["abstain"]=":grey_question:"
    ["error_timeout"]=":hourglass:"
    ["error_network"]=":globe_with_meridians:"
    ["error_auth"]=":key:"
    ["error_service"]=":warning:"
)

# Verdict severity ranks (lower = more severe, used for consensus)
declare -A VERDICT_SEVERITY=(
    ["critical_vulnerabilities"]=0
    ["needs_review"]=1
    ["provide_feedback"]=2
    ["comment_only"]=3
    ["approve"]=4
    ["abstain"]=99
    ["error_timeout"]=99
    ["error_network"]=99
    ["error_auth"]=99
    ["error_service"]=99
)

# Severity icons for output
declare -A SEVERITY_ICONS=(
    ["critical"]=":red_circle:"
    ["major"]=":orange_circle:"
    ["minor"]=":yellow_circle:"
    ["suggestion"]=":white_circle:"
)

# Root of the repository that holds this library (fallback for SA_GITLAB_PROFILE)
REVIEW_AGGREGATOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd)"

# jq definitions for the redaction filter. The literal prefixes come first
# because the pattern rules change the text that the prefixes must match.
# A prefix shorter than 4 characters (for example "/") is ignored.
#
# A prefix matches only as a full path: the character before it must not be
# a path character, and the character after it must be "/" or a character
# that cannot continue the name. Thus HOME=/root does not change
# packages/root/src, and a HOME prefix does not match the start of a longer
# user name (the user path rule redacts that path).
#
# The email rule skips SSH remotes (git@host:owner/repo) and needs a letter
# at the start of the domain, so serde@1.0.rc and icon@2x.png stay unchanged.
#
# A key must not have a letter or digit directly before or after it, so
# names such as bitmask-or-merge stay unchanged.
REDACTION_JQ_DEFS='
def re_escape:
    gsub("(?<c>[.*+?^$|()\\[\\]{}\\\\])"; "\\\(.c)");
def lit($from; $to):
    if ($from | length) < 4 then .
    else gsub("(?<![A-Za-z0-9._~-])" + ($from | re_escape) + "(?=[^A-Za-z0-9._~-]|$)"; $to)
    end;
def redact_text:
    lit($workspace; "[WORKSPACE_ROOT]")
    | lit($repo; "[REPO_ROOT]")
    | lit($tmpdir; "[TMPDIR]")
    | lit($home; "~")
    | gsub("(?<![A-Za-z0-9._~-])/(?<root>Users|home)/[^/\\s\"`<>:,;)]+"; "/\(.root)/[USER]")
    | gsub("(?<![A-Za-z0-9._~-])(/private)?/var/folders/[A-Za-z0-9_+]+/[A-Za-z0-9_+]+(/T)?"; "[TMPDIR]")
    | gsub("(?<![A-Za-z0-9._%+-])(?!git@[A-Za-z0-9.-]+:)[A-Za-z0-9._%+-]+@[A-Za-z][A-Za-z0-9-]*(\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}"; "[EMAIL]")
    | gsub("(?<![A-Za-z0-9])(sk-[A-Za-z0-9_-]{20,}|xai-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,}|glpat-[A-Za-z0-9_-]{20,})(?![A-Za-z0-9])"; "[REDACTED]");
'

#
# Run jq with the redaction definitions and the local prefixes
#
_redaction_jq() {
    local options="$1"
    local program="$2"

    local workspace="${SA_GITLAB_PROFILE:-$REVIEW_AGGREGATOR_ROOT}"
    local repo
    repo=$(git rev-parse --show-toplevel 2>/dev/null || true)
    local tmpdir="${TMPDIR:-}"
    local home="${HOME:-}"

    jq "$options" \
        --arg workspace "${workspace%/}" \
        --arg repo "${repo%/}" \
        --arg tmpdir "${tmpdir%/}" \
        --arg home "${home%/}" \
        "${REDACTION_JQ_DEFS} ${program}"
}

#
# Redact local paths, email addresses, and credentials from public text
#
# Reads text from stdin and writes the redacted text to stdout. The filter is
# idempotent: redacted text passes through with no change.
#
redact_public_text() {
    _redaction_jq -Rsj 'redact_text'
}

#
# Redact each string value in a JSON document
#
redact_public_json() {
    local json="$1"

    local redacted
    if ! redacted=$(printf '%s' "$json" | _redaction_jq -c \
        'walk(if type == "string" then redact_text else . end)'); then
        return 1
    fi

    # jq can stop with no output. A JSON document never redacts to nothing.
    if [[ -n "$json" && -z "$redacted" ]]; then
        return 1
    fi

    printf '%s\n' "$redacted"
}

#
# Check that the redaction filter finds nothing to redact in the text
#
# Returns 0 when the text is clean. When the text has unredacted data, prints
# the line numbers that contain it and returns 1. The output has no matched
# text, because a match can be a credential. Returns 2 when the filter fails.
#
public_text_is_clean() {
    local text="$1"

    local redacted
    if ! redacted=$(printf '%s' "$text" | redact_public_text); then
        return 2
    fi
    if [[ -n "$text" && -z "$redacted" ]]; then
        return 2
    fi

    if [[ "$redacted" == "$text" ]]; then
        return 0
    fi

    diff <(printf '%s\n' "$text") <(printf '%s\n' "$redacted") |
        sed -nE 's/^([0-9]+(,[0-9]+)?)[acd].*/\1/p' | paste -sd ' ' -
    return 1
}

#
# Calculate consensus verdict from multiple reviews
#
# Verdicts (ordered by severity, most severe first):
#   critical_vulnerabilities - Security/critical issues, MUST fix before merge
#   needs_review            - Requires human review/decision
#   provide_feedback        - Has suggestions but can proceed
#   comment_only            - Informational only, no action needed
#   approve                 - Code looks good, no issues found
#   abstain                 - Provider couldn't determine
#
# Consensus logic:
#   - If any provider returns critical_vulnerabilities, overall is critical_vulnerabilities
#   - If threshold providers agree on a verdict, that's the consensus
#   - Otherwise, the most severe non-abstain verdict wins
#
# Portable fixed-point helpers. bc is absent on minimal CI images, and its
# output drops the leading zero (.5000), which is not valid JSON.
_ratio4() {
    awk -v n="$1" -v d="$2" 'BEGIN { printf "%.4f", (d != 0) ? n / d : 0 }'
}

_num_ge() {
    awk -v a="$1" -v b="$2" 'BEGIN { exit !(a >= b) }'
}

calculate_consensus() {
    local reviews_json="$1"

    # Count all verdict types
    local critical_count needs_review_count feedback_count comment_count approve_count abstain_count total_count
    critical_count=$(echo "$reviews_json" | jq '[.[] | select(.verdict == "critical_vulnerabilities")] | length')
    needs_review_count=$(echo "$reviews_json" | jq '[.[] | select(.verdict == "needs_review")] | length')
    feedback_count=$(echo "$reviews_json" | jq '[.[] | select(.verdict == "provide_feedback")] | length')
    comment_count=$(echo "$reviews_json" | jq '[.[] | select(.verdict == "comment_only")] | length')
    approve_count=$(echo "$reviews_json" | jq '[.[] | select(.verdict == "approve")] | length')
    abstain_count=$(echo "$reviews_json" | jq '[.[] | select(.verdict == "abstain" or .verdict == "error_timeout" or .verdict == "error_network" or .verdict == "error_auth" or .verdict == "error_service")] | length')
    total_count=$(echo "$reviews_json" | jq 'length')

    # Voting count excludes abstains and errors
    local voting_count=$((total_count - abstain_count))

    if [[ $voting_count -eq 0 ]]; then
        # All abstained
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "agreement": 0.0,
    "voting_count": 0,
    "total_count": $total_count,
    "verdict_counts": {
        "critical_vulnerabilities": 0,
        "needs_review": 0,
        "provide_feedback": 0,
        "comment_only": 0,
        "approve": 0,
        "abstain": $abstain_count
    },
    "no_consensus": true
}
EOF
        return
    fi

    # Calculate average confidence
    local avg_confidence
    avg_confidence=$(echo "$reviews_json" | jq '[.[] | select(.verdict != "abstain") | .confidence] | add / length // 0')

    # Determine consensus verdict
    local verdict agreement no_consensus="false"

    # Critical vulnerabilities always wins (security-first)
    if [[ $critical_count -gt 0 ]]; then
        verdict="critical_vulnerabilities"
        agreement=$(_ratio4 "$critical_count" "$voting_count")
    else
        # Check for threshold consensus on each verdict (in severity order)
        local critical_ratio needs_review_ratio feedback_ratio comment_ratio approve_ratio
        critical_ratio=$(_ratio4 "$critical_count" "$voting_count")
        needs_review_ratio=$(_ratio4 "$needs_review_count" "$voting_count")
        feedback_ratio=$(_ratio4 "$feedback_count" "$voting_count")
        comment_ratio=$(_ratio4 "$comment_count" "$voting_count")
        approve_ratio=$(_ratio4 "$approve_count" "$voting_count")

        if _num_ge "$approve_ratio" "$CONSENSUS_THRESHOLD"; then
            verdict="approve"
            agreement="$approve_ratio"
        elif _num_ge "$comment_ratio" "$CONSENSUS_THRESHOLD"; then
            verdict="comment_only"
            agreement="$comment_ratio"
        elif _num_ge "$feedback_ratio" "$CONSENSUS_THRESHOLD"; then
            verdict="provide_feedback"
            agreement="$feedback_ratio"
        elif _num_ge "$needs_review_ratio" "$CONSENSUS_THRESHOLD"; then
            verdict="needs_review"
            agreement="$needs_review_ratio"
        else
            # No clear consensus - use most severe verdict present
            no_consensus="true"
            if [[ $needs_review_count -gt 0 ]]; then
                verdict="needs_review"
                agreement="$needs_review_ratio"
            elif [[ $feedback_count -gt 0 ]]; then
                verdict="provide_feedback"
                agreement="$feedback_ratio"
            elif [[ $comment_count -gt 0 ]]; then
                verdict="comment_only"
                agreement="$comment_ratio"
            else
                verdict="approve"
                agreement="$approve_ratio"
            fi
        fi
    fi

    cat <<EOF
{
    "verdict": "$verdict",
    "confidence": $avg_confidence,
    "agreement": $agreement,
    "voting_count": $voting_count,
    "total_count": $total_count,
    "verdict_counts": {
        "critical_vulnerabilities": $critical_count,
        "needs_review": $needs_review_count,
        "provide_feedback": $feedback_count,
        "comment_only": $comment_count,
        "approve": $approve_count,
        "abstain": $abstain_count
    },
    "no_consensus": $no_consensus
}
EOF
}

#
# Deduplicate and merge issues from multiple reviews
#
deduplicate_issues() {
    local reviews_json="$1"

    # Collect all issues with provider attribution
    echo "$reviews_json" | jq '
        [
            .[] |
            .provider as $provider |
            .confidence as $conf |
            (.issues // [])[] |
            . + {reported_by: $provider, provider_confidence: $conf}
        ] |
        # Group by file + line range (within 5 lines) + category
        group_by([
            .file,
            ((.line // 0) / 5 | floor),
            .category
        ]) |
        # Merge each group
        map({
            file: .[0].file,
            line: .[0].line,
            category: .[0].category,
            # Take highest severity
            severity: (
                map(.severity) |
                map(
                    if . == "critical" then 0
                    elif . == "major" then 1
                    elif . == "minor" then 2
                    else 3 end
                ) |
                min |
                if . == 0 then "critical"
                elif . == 1 then "major"
                elif . == 2 then "minor"
                else "suggestion" end
            ),
            # Use first title (usually most descriptive)
            title: .[0].title,
            # Combine descriptions
            description: (map(.description) | unique | join("\n\n---\n\n")),
            # Collect suggestions
            suggestion: (map(.suggestion // empty) | unique | first // null),
            # Track which providers reported this
            reported_by: [.[].reported_by] | unique,
            # Average confidence
            confidence: ([.[].provider_confidence] | add / length),
            # Count of reporters
            reporter_count: ([.[].reported_by] | unique | length)
        }) |
        # Sort by severity then reporter count
        sort_by([
            (if .severity == "critical" then 0
             elif .severity == "major" then 1
             elif .severity == "minor" then 2
             else 3 end),
            (-.reporter_count)
        ])
    '
}

#
# Escalate severity for issues reported by multiple providers
#
escalate_severity() {
    local issues_json="$1"

    echo "$issues_json" | jq '
        map(
            if .reporter_count >= 3 and .severity == "minor" then
                .severity = "major" | .escalated = true
            elif .reporter_count >= 2 and .severity == "major" then
                .severity = "critical" | .escalated = true
            elif .reporter_count >= 2 and .severity == "minor" then
                .severity = "major" | .escalated = true
            else
                .escalated = false
            end
        )
    '
}

#
# Generate statistics from issues
#
generate_issue_stats() {
    local issues_json="$1"

    echo "$issues_json" | jq '
        {
            total: length,
            by_severity: {
                critical: [.[] | select(.severity == "critical")] | length,
                major: [.[] | select(.severity == "major")] | length,
                minor: [.[] | select(.severity == "minor")] | length,
                suggestion: [.[] | select(.severity == "suggestion")] | length
            },
            by_category: (
                group_by(.category) |
                map({key: .[0].category, value: length}) |
                from_entries
            ),
            escalated_count: [.[] | select(.escalated == true)] | length,
            multi_reporter_count: [.[] | select(.reporter_count > 1)] | length
        }
    '
}

#
# Generate provider summary
#
generate_provider_summary() {
    local reviews_json="$1"

    echo "$reviews_json" | jq '
        map({
            provider: .provider,
            model: .model,
            model_requested: (.model_requested // .model),
            verdict: .verdict,
            confidence: .confidence,
            issue_count: (.issues | length),
            error: .error,
            duration_ms: .duration_ms,
            summary: (.summary // "No summary provided")
        }) |
        sort_by(.provider)
    '
}

#
# Aggregate all reviews into single result
#
aggregate_reviews() {
    local reviews_json="$1"

    # Calculate consensus
    local consensus
    consensus=$(calculate_consensus "$reviews_json")

    # Deduplicate and escalate issues
    local issues
    issues=$(deduplicate_issues "$reviews_json")
    issues=$(escalate_severity "$issues")

    # Generate stats
    local issue_stats
    issue_stats=$(generate_issue_stats "$issues")

    # Generate provider summary
    local provider_summary
    provider_summary=$(generate_provider_summary "$reviews_json")

    # Combine summaries from non-error providers only
    local combined_summary
    combined_summary=$(echo "$reviews_json" | jq -r '
        [.[] | select(
            .summary != null and .summary != "" and
            (.verdict | startswith("error_") | not) and
            .verdict != "abstain"
        ) | .summary] |
        join("\n\n")
    ')

    # Build final result
    local result
    result=$(jq -n \
        --argjson consensus "$consensus" \
        --argjson issues "$issues" \
        --argjson stats "$issue_stats" \
        --argjson providers "$provider_summary" \
        --arg summary "$combined_summary" \
        '{
            consensus: $consensus,
            issues: $issues,
            issue_stats: $stats,
            providers: $providers,
            combined_summary: $summary
        }')

    # The result goes into the posted review and the JSON summary. Provider
    # errors and reviewer text can contain local paths or credentials.
    local redacted
    if ! redacted=$(redact_public_json "$result"); then
        echo "ERROR: the redaction filter failed on the aggregated review" >&2
        return 1
    fi
    printf '%s\n' "$redacted" | jq '.'
}

#
# Format review result as markdown
#
format_markdown() {
    local aggregated_json="$1"

    local verdict agreement total_count
    verdict=$(echo "$aggregated_json" | jq -r '.consensus.verdict')
    agreement=$(echo "$aggregated_json" | jq -r '.consensus.agreement')
    total_count=$(echo "$aggregated_json" | jq -r '.consensus.total_count')

    local verdict_icon="${VERDICT_ICONS[$verdict]:-:grey_question:}"
    local verdict_text
    case "$verdict" in
        critical_vulnerabilities) verdict_text="Critical Vulnerabilities Found" ;;
        needs_review) verdict_text="Needs Review" ;;
        provide_feedback) verdict_text="Feedback Provided" ;;
        comment_only) verdict_text="Comments Only" ;;
        approve) verdict_text="Approved" ;;
        abstain) verdict_text="Review Inconclusive" ;;
        error_timeout) verdict_text="Timeout Error" ;;
        error_network) verdict_text="Network Error" ;;
        error_auth) verdict_text="Auth Error" ;;
        error_service) verdict_text="Service Error" ;;
        *) verdict_text="Unknown" ;;
    esac

    # Agreement percentage
    local agreement_pct
    agreement_pct=$(echo "scale=0; $agreement * 100" | bc)

    # Start building markdown
    local md=""

    # Header
    md+="## Multi-Agent Code Review\n\n"
    md+="**Verdict:** ${verdict_icon} ${verdict_text} (${agreement_pct}% agreement)\n\n"

    # Provider breakdown table - model id in backticks; when the API served
    # a different model than requested, the cell shows both
    md+="**Reviewed by:**\n\n"
    md+="| Provider | Model | Verdict | Confidence |\n"
    md+="|----------|-------|---------|------------|\n"
    local provider_lines
    provider_lines=$(echo "$aggregated_json" | jq -r '.providers[] |
        (.model // "unknown") as $model |
        (.model_requested // $model) as $requested |
        (if $requested != $model then "`\($model)` (requested `\($requested)`)" else "`\($model)`" end) as $model_cell |
        "| \(.provider) | \($model_cell) | \(.verdict | if . == "critical_vulnerabilities" then "Critical Vulnerabilities" elif . == "needs_review" then "Needs Review" elif . == "provide_feedback" then "Feedback Provided" elif . == "comment_only" then "Comments Only" elif . == "approve" then "Approve" elif . == "abstain" then "Abstain" elif . == "error_timeout" then "Timeout Error" elif . == "error_network" then "Network Error" elif . == "error_auth" then "Auth Error" elif . == "error_service" then "Service Error" else . end) | \(.confidence | . * 100 | floor / 100) |"')
    if [[ -n "$provider_lines" ]]; then
        md+="${provider_lines}\n"
    fi
    md+="\n"

    # Divider
    md+="---\n\n"

    # Summary section
    md+="### Summary\n\n"
    local combined_summary
    combined_summary=$(echo "$aggregated_json" | jq -r '.combined_summary // "No summary available"')
    md+="${combined_summary}\n\n"

    md+="---\n\n"

    # Issues section
    local issue_count
    issue_count=$(echo "$aggregated_json" | jq '.issues | length')

    md+="### Issues Found\n\n"

    if [[ $issue_count -gt 0 ]]; then
        # Format each issue as collapsible using jq (avoiding subshell issue)
        local issues_md
        issues_md=$(echo "$aggregated_json" | jq -r '.issues[] |
            (if .severity == "critical" then ":red_circle:"
             elif .severity == "major" then ":orange_circle:"
             elif .severity == "minor" then ":yellow_circle:"
             else ":white_circle:" end) as $icon |
            (if .severity == "critical" then "Critical"
             elif .severity == "major" then "Major"
             elif .severity == "minor" then "Minor"
             else "Suggestion" end) as $label |
            "<details>\n<summary><b>\($icon) \($label): \(.title)</b> (Reported by: \(.reported_by | join(", ")))</summary>\n\n**File:** `\(.file // "unknown")` (line \(.line // "N/A"))\n\n\(.description)\n\n" +
            (if .suggestion then "**Suggestion:**\n```\n\(.suggestion)\n```\n\n" else "" end) +
            "</details>\n"
        ')
        md+="${issues_md}\n"
    fi

    md+="---\n\n"

    # Individual reviewer assessments (collapsible)
    md+="<details>\n"
    md+="<summary>View individual reviewer assessments</summary>\n\n"

    # Format individual assessments, separating successful from errored providers
    local assessments_md
    assessments_md=$(echo "$aggregated_json" | jq -r '.providers[] |
        if (.verdict | startswith("error_")) or .verdict == "abstain" then
            "#### \(.provider) (\(.model // "unknown"))\n\n> **\(.verdict | gsub("_"; " ") | ascii_upcase)**: \(.error // .summary // "No details")\n"
        elif (.summary // "" | test("^\\s*\\{")) then
            "#### \(.provider) (\(.model // "unknown"))\n\n```json\n\(.summary)\n```\n"
        else
            "#### \(.provider) (\(.model // "unknown"))\n\n\(.summary // "No summary provided")\n"
        end
    ')
    md+="${assessments_md}\n"

    md+="</details>\n\n"

    md+="---\n"
    md+="*Generated by Multi-Agent Review System*\n"

    echo -e "$md"
}

#
# Generate compact summary for large PRs
#
format_summary_markdown() {
    local aggregated_json="$1"
    local files_changed="${2:-unknown}"
    local additions="${3:-0}"
    local deletions="${4:-0}"

    local verdict
    verdict=$(echo "$aggregated_json" | jq -r '.consensus.verdict')

    local verdict_icon="${VERDICT_ICONS[$verdict]:-:grey_question:}"

    # Get issue stats
    local critical major minor suggestion
    critical=$(echo "$aggregated_json" | jq '.issue_stats.by_severity.critical // 0')
    major=$(echo "$aggregated_json" | jq '.issue_stats.by_severity.major // 0')
    minor=$(echo "$aggregated_json" | jq '.issue_stats.by_severity.minor // 0')
    suggestion=$(echo "$aggregated_json" | jq '.issue_stats.by_severity.suggestion // 0')

    local md=""
    md+="## Multi-Agent Review Summary\n\n"
    md+="**Verdict:** ${verdict_icon} $(echo "$verdict" | sed 's/_/ /' | sed 's/\b./\u&/g')\n\n"
    md+="**Files Reviewed:** ${files_changed} files (+${additions}, -${deletions} lines)\n"
    md+="**Issues Found:** ${critical} critical, ${major} major, ${minor} minor, ${suggestion} suggestions\n\n"

    # Category breakdown table
    md+="| Category | Critical | Major | Minor | Suggestions |\n"
    md+="|----------|----------|-------|-------|-------------|\n"

    echo "$aggregated_json" | jq -r '
        .issues |
        group_by(.category) |
        map({
            category: .[0].category,
            critical: [.[] | select(.severity == "critical")] | length,
            major: [.[] | select(.severity == "major")] | length,
            minor: [.[] | select(.severity == "minor")] | length,
            suggestion: [.[] | select(.severity == "suggestion")] | length
        }) |
        .[] |
        "| \(.category) | \(.critical) | \(.major) | \(.minor) | \(.suggestion) |"
    ' | while read -r line; do
        md+="$line\n"
    done

    md+="\n*See individual file comments for details.*\n"

    echo -e "$md"
}

#
# CLI interface when run directly
#
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    COMMAND="${1:-help}"

    case "$COMMAND" in
        aggregate)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 aggregate REVIEWS_JSON_FILE" >&2
                exit 1
            fi
            reviews=$(cat "$2")
            aggregate_reviews "$reviews"
            ;;
        format)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 format AGGREGATED_JSON_FILE" >&2
                exit 1
            fi
            aggregated=$(cat "$2")
            format_markdown "$aggregated"
            ;;
        summary)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 summary AGGREGATED_JSON_FILE [files] [additions] [deletions]" >&2
                exit 1
            fi
            aggregated=$(cat "$2")
            format_summary_markdown "$aggregated" "${3:-unknown}" "${4:-0}" "${5:-0}"
            ;;
        help|--help|-h)
            cat <<EOF
review-aggregator.sh - Aggregate and format multi-agent reviews

Usage: $0 <command> [args]

Commands:
    aggregate FILE    Aggregate reviews from JSON file
    format FILE       Format aggregated result as markdown
    summary FILE      Generate compact summary markdown
    help              Show this help message

Configuration:
    CONSENSUS_THRESHOLD         Agreement ratio for consensus (default: 0.6)
    MIN_PROVIDERS_FOR_CONSENSUS Minimum providers needed (default: 2)

Examples:
    $0 aggregate reviews.json > aggregated.json
    $0 format aggregated.json > review.md
    $0 summary aggregated.json 12 324 89 > summary.md

As a library:
    source /path/to/review-aggregator.sh
    result=\$(aggregate_reviews "\$reviews_json")
    markdown=\$(format_markdown "\$result")
EOF
            ;;
        *)
            echo "Unknown command: $COMMAND" >&2
            echo "Run '$0 help' for usage" >&2
            exit 1
            ;;
    esac
fi
