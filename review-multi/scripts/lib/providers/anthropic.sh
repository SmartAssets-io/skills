#!/usr/bin/env bash
#
# anthropic.sh - Anthropic Claude provider for multi-agent reviews
#
# This provider implements the review interface for Anthropic's Claude models.
#
# Environment:
#   ANTHROPIC_API_KEY    Required. API key for Anthropic
#   ANTHROPIC_MODEL      Optional. Model to use (default: claude-opus-4-5-20251101)
#   ANTHROPIC_MAX_TOKENS Optional. Max tokens (default: 4096)
#
# Usage:
#   source anthropic.sh
#   result=$(anthropic_review "$diff" "$context")
#

# Prevent re-sourcing
if [[ -n "${ANTHROPIC_PROVIDER_LOADED:-}" ]]; then
    return 0
fi
ANTHROPIC_PROVIDER_LOADED=1

# Configuration
ANTHROPIC_API_URL="https://api.anthropic.com/v1/messages"
ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-claude-opus-4-5-20251101}"
ANTHROPIC_MAX_TOKENS="${ANTHROPIC_MAX_TOKENS:-16384}"
ANTHROPIC_API_VERSION="2023-06-01"

#
# Get provider name
#
anthropic_name() {
    echo "anthropic"
}

#
# Check if provider is properly configured
#
anthropic_check() {
    if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
        echo "false"
        return 1
    fi
    echo "true"
    return 0
}

#
# Execute review using Claude
#
anthropic_review() {
    local diff="$1"
    local context="${2:-\{\}}"

    # Validate API key
    if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "issues": [],
    "summary": "Anthropic API key not configured",
    "error": "ANTHROPIC_API_KEY environment variable not set",
    "model": "$ANTHROPIC_MODEL"
}
EOF
        return 1
    fi

    # Build prompt
    local prompt
    prompt=$(get_review_prompt "$context")

    # Build the full message (single user message required by Anthropic API)
    local full_message="${prompt}

\`\`\`diff
${diff}
\`\`\`

Please provide your review as a JSON object."

    # Escape for JSON
    # Use printf '%s' to preserve escape sequences
    local escaped_message
    escaped_message=$(printf '%s' "$full_message" | jq -Rs '.')

    # Build request body
    local request_body
    request_body=$(cat <<EOF
{
    "model": "$ANTHROPIC_MODEL",
    "max_tokens": $ANTHROPIC_MAX_TOKENS,
    "messages": [
        {
            "role": "user",
            "content": $escaped_message
        }
    ]
}
EOF
)

    # Make API call
    local response
    response=$(curl -s -X POST "$ANTHROPIC_API_URL" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: $ANTHROPIC_API_VERSION" \
        -d "$request_body" 2>&1)

    local curl_exit_code=$?

    if [[ $curl_exit_code -ne 0 ]]; then
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "issues": [],
    "summary": "API request failed",
    "error": "curl failed with exit code $curl_exit_code",
    "model": "$ANTHROPIC_MODEL"
}
EOF
        return 1
    fi

    # Check for API errors
    # IMPORTANT: Use printf '%s' instead of echo to preserve escape sequences like \n
    # in the JSON response. Using echo would interpret \n as newlines, corrupting the JSON.
    local error_type
    error_type=$(printf '%s' "$response" | jq -r '.error.type // empty' 2>/dev/null)

    if [[ -n "$error_type" ]]; then
        local error_message
        error_message=$(printf '%s' "$response" | jq -r '.error.message // "Unknown error"')
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "issues": [],
    "summary": "API error: $error_message",
    "error": "$error_type: $error_message",
    "model": "$ANTHROPIC_MODEL"
}
EOF
        return 1
    fi

    # Extract the response content
    # Use printf '%s' to preserve escape sequences in the JSON
    local content
    content=$(printf '%s' "$response" | jq -r '.content[0].text // empty' 2>/dev/null)

    if [[ -z "$content" ]]; then
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "issues": [],
    "summary": "Empty response from API",
    "error": "No content in API response",
    "model": "$ANTHROPIC_MODEL"
}
EOF
        return 1
    fi

    # Try to extract JSON from the response
    local json_result=""

    # Strategy 1: Check if raw content is valid JSON
    # Use printf '%s' instead of echo to preserve literal escape sequences like \n
    if printf '%s' "$content" | jq -e '.' >/dev/null 2>&1; then
        json_result="$content"
    fi

    # Strategy 2: Extract from markdown code block (```json ... ``` or ``` ... ```)
    if [[ -z "$json_result" ]]; then
        # Try to extract content between ```json and ``` or between ``` and ```
        local code_block
        code_block=$(printf '%s' "$content" | sed -n '/^```\(json\)\?$/,/^```$/p' | sed '1d;$d')
        if [[ -n "$code_block" ]] && printf '%s' "$code_block" | jq -e '.' >/dev/null 2>&1; then
            json_result="$code_block"
        fi
    fi

    # Strategy 3: Find JSON object using awk (handles multi-line)
    if [[ -z "$json_result" ]]; then
        local extracted
        extracted=$(printf '%s' "$content" | awk '
            BEGIN { in_json=0; depth=0; json="" }
            /{/ {
                if (!in_json) { in_json=1 }
            }
            in_json {
                json = json $0 "\n"
                depth += gsub(/{/, "{")
                depth -= gsub(/}/, "}")
                if (depth == 0 && in_json) {
                    print json
                    exit
                }
            }
        ')
        if [[ -n "$extracted" ]] && printf '%s' "$extracted" | jq -e '.' >/dev/null 2>&1; then
            json_result="$extracted"
        fi
    fi

    # Validate and normalize the result
    if [[ -z "$json_result" ]] || ! printf '%s' "$json_result" | jq -e '.' >/dev/null 2>&1; then
        # Response wasn't valid JSON - return abstain with content summary
        local summary
        summary=$(printf '%s' "$content" | head -c 500 | tr '\n' ' ' | sed 's/"/\\"/g')
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.5,
    "issues": [],
    "summary": "$summary",
    "error": "Invalid JSON response",
    "model": "$ANTHROPIC_MODEL"
}
EOF
        return 0
    fi

    # Add model info and return
    printf '%s' "$json_result" | jq --arg model "$ANTHROPIC_MODEL" '. + {model: $model}'
}

#
# Cleanup (no-op for API provider)
#
anthropic_cleanup() {
    return 0
}
