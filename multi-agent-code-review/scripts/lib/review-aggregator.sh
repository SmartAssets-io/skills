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
        agreement=$(echo "scale=4; $critical_count / $voting_count" | bc)
    else
        # Check for threshold consensus on each verdict (in severity order)
        local critical_ratio needs_review_ratio feedback_ratio comment_ratio approve_ratio
        critical_ratio=$(echo "scale=4; $critical_count / $voting_count" | bc)
        needs_review_ratio=$(echo "scale=4; $needs_review_count / $voting_count" | bc)
        feedback_ratio=$(echo "scale=4; $feedback_count / $voting_count" | bc)
        comment_ratio=$(echo "scale=4; $comment_count / $voting_count" | bc)
        approve_ratio=$(echo "scale=4; $approve_count / $voting_count" | bc)

        if (( $(echo "$approve_ratio >= $CONSENSUS_THRESHOLD" | bc -l) )); then
            verdict="approve"
            agreement="$approve_ratio"
        elif (( $(echo "$comment_ratio >= $CONSENSUS_THRESHOLD" | bc -l) )); then
            verdict="comment_only"
            agreement="$comment_ratio"
        elif (( $(echo "$feedback_ratio >= $CONSENSUS_THRESHOLD" | bc -l) )); then
            verdict="provide_feedback"
            agreement="$feedback_ratio"
        elif (( $(echo "$needs_review_ratio >= $CONSENSUS_THRESHOLD" | bc -l) )); then
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

    # Combine all summaries
    local combined_summary
    combined_summary=$(echo "$reviews_json" | jq -r '
        [.[] | select(.summary != null and .summary != "") | .summary] |
        join("\n\n")
    ')

    # Build final result
    jq -n \
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
        }'
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

    # Provider breakdown
    md+="**Reviewed by:**\n"
    local provider_lines
    provider_lines=$(echo "$aggregated_json" | jq -r '.providers[] | "- \(.provider) (\(.model // "unknown")): \(.verdict | if . == "critical_vulnerabilities" then "Critical Vulnerabilities" elif . == "needs_review" then "Needs Review" elif . == "provide_feedback" then "Feedback Provided" elif . == "comment_only" then "Comments Only" elif . == "approve" then "Approve" elif . == "abstain" then "Abstain" elif . == "error_timeout" then "Timeout Error" elif . == "error_network" then "Network Error" elif . == "error_auth" then "Auth Error" elif . == "error_service" then "Service Error" else . end) (confidence: \(.confidence | . * 100 | floor / 100))"')
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

    # Format individual assessments using jq (avoiding subshell issue)
    local assessments_md
    assessments_md=$(echo "$aggregated_json" | jq -r '.providers[] |
        "#### \(.provider) (\(.model // "unknown"))\n\n\(.summary // "No summary provided")\n"
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
