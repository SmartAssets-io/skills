#!/usr/bin/env bash
#
# openai.sh - OpenAI ChatGPT provider for multi-agent reviews
#
# This provider implements the review interface for OpenAI's ChatGPT models.
#
# Environment:
#   OPENAI_API_KEY    Required. API key for OpenAI
#   OPENAI_MODEL      Optional. Model to use (default: gpt-4-turbo)
#   OPENAI_MAX_TOKENS Optional. Max tokens (default: 4096)
#
# Usage:
#   source openai.sh
#   result=$(openai_review "$diff" "$context")
#

# Prevent re-sourcing
if [[ -n "${OPENAI_PROVIDER_LOADED:-}" ]]; then
    return 0
fi
OPENAI_PROVIDER_LOADED=1

# Configuration
OPENAI_API_URL="https://api.openai.com/v1/chat/completions"
OPENAI_MODEL="${OPENAI_MODEL:-gpt-4-turbo}"
OPENAI_MAX_TOKENS="${OPENAI_MAX_TOKENS:-16384}"

#
# Get provider name
#
openai_name() {
    echo "openai"
}

#
# Check if provider is properly configured
#
openai_check() {
    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        echo "false"
        return 1
    fi
    echo "true"
    return 0
}

#
# Execute review using ChatGPT
#
openai_review() {
    local diff="$1"
    local context="${2:-\{\}}"

    # Validate API key
    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "issues": [],
    "summary": "OpenAI API key not configured",
    "error": "OPENAI_API_KEY environment variable not set",
    "model": "$OPENAI_MODEL"
}
EOF
        return 1
    fi

    # Build prompt
    local prompt
    prompt=$(get_review_prompt "$context")

    # Build the full message
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
    "model": "$OPENAI_MODEL",
    "max_tokens": $OPENAI_MAX_TOKENS,
    "temperature": 0.3,
    "response_format": { "type": "json_object" },
    "messages": [
        {
            "role": "system",
            "content": "You are an expert code reviewer. Always respond with valid JSON."
        },
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
    response=$(curl -s -X POST "$OPENAI_API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
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
    "model": "$OPENAI_MODEL"
}
EOF
        return 1
    fi

    # Check for API errors
    # Use printf '%s' to preserve escape sequences in JSON
    local error_message
    error_message=$(printf '%s' "$response" | jq -r '.error.message // empty' 2>/dev/null)

    if [[ -n "$error_message" ]]; then
        local error_type
        error_type=$(printf '%s' "$response" | jq -r '.error.type // "api_error"')
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "issues": [],
    "summary": "API error: $error_message",
    "error": "$error_type: $error_message",
    "model": "$OPENAI_MODEL"
}
EOF
        return 1
    fi

    # Extract the response content
    local content
    content=$(printf '%s' "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)

    if [[ -z "$content" ]]; then
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "issues": [],
    "summary": "Empty response from API",
    "error": "No content in API response",
    "model": "$OPENAI_MODEL"
}
EOF
        return 1
    fi

    # Validate JSON response
    # Use printf '%s' instead of echo to preserve literal escape sequences like \n
    if ! printf '%s' "$content" | jq -e '.' >/dev/null 2>&1; then
        # Try to extract JSON from response
        local json_result
        json_result=$(printf '%s' "$content" | grep -o '{.*}' | head -1)

        if ! printf '%s' "$json_result" | jq -e '.' >/dev/null 2>&1; then
            cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.5,
    "issues": [],
    "summary": "$content",
    "error": null,
    "model": "$OPENAI_MODEL"
}
EOF
            return 0
        fi
        content="$json_result"
    fi

    # Add model info and return
    printf '%s' "$content" | jq --arg model "$OPENAI_MODEL" '. + {model: $model}'
}

#
# Cleanup (no-op for API provider)
#
openai_cleanup() {
    return 0
}
