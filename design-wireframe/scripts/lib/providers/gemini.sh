#!/usr/bin/env bash
#
# gemini.sh - Google Gemini provider for multi-agent reviews
#
# This provider implements the review interface for Google's Gemini models.
#
# Environment:
#   GEMINI_API_KEY    Required. API key for Gemini (or use GOOGLE_API_KEY)
#   GOOGLE_API_KEY    Required. Alternative to GEMINI_API_KEY
#   GEMINI_MODEL      Optional. Model to use (default: gemini-2.5-pro)
#   GEMINI_MAX_TOKENS Optional. Max tokens (default: 16384)
#
# Usage:
#   source gemini.sh
#   result=$(gemini_review "$diff" "$context")
#

# Prevent re-sourcing
if [[ -n "${GEMINI_PROVIDER_LOADED:-}" ]]; then
    return 0
fi
GEMINI_PROVIDER_LOADED=1

# Configuration
GEMINI_API_BASE="https://generativelanguage.googleapis.com/v1beta"
GEMINI_MODEL="${GEMINI_MODEL:-${GOOGLE_MODEL:-gemini-2.5-pro}}"
# Gemini 3 models use "thinking" tokens which count toward total output
# Set higher limit to ensure enough room for both thinking and actual response
GEMINI_MAX_TOKENS="${GEMINI_MAX_TOKENS:-${GOOGLE_MAX_TOKENS:-16384}}"

#
# Get provider name
#
gemini_name() {
    echo "gemini"
}

#
# Get the API key (supports both GEMINI_API_KEY and GOOGLE_API_KEY)
#
_gemini_get_api_key() {
    echo "${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}"
}

#
# Check if provider is properly configured
#
gemini_check() {
    local api_key
    api_key=$(_gemini_get_api_key)
    if [[ -z "$api_key" ]]; then
        echo "false"
        return 1
    fi
    echo "true"
    return 0
}

#
# Execute review using Gemini
#
gemini_review() {
    local diff="$1"
    local context="${2:-\{\}}"

    # Get API key (supports both GEMINI_API_KEY and GOOGLE_API_KEY)
    local api_key
    api_key=$(_gemini_get_api_key)

    # Validate API key
    if [[ -z "$api_key" ]]; then
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "issues": [],
    "summary": "Gemini API key not configured",
    "error": "Neither GEMINI_API_KEY nor GOOGLE_API_KEY environment variable is set",
    "model": "$GEMINI_MODEL"
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

Please provide your review as a JSON object. Respond ONLY with valid JSON, no additional text."

    # Escape for JSON
    # Use printf '%s' to preserve escape sequences
    local escaped_message
    escaped_message=$(printf '%s' "$full_message" | jq -Rs '.')

    # Build request body
    local request_body
    request_body=$(cat <<EOF
{
    "contents": [
        {
            "parts": [
                {
                    "text": $escaped_message
                }
            ]
        }
    ],
    "generationConfig": {
        "maxOutputTokens": $GEMINI_MAX_TOKENS,
        "temperature": 0.3
    }
}
EOF
)

    # Build API URL
    local api_url="${GEMINI_API_BASE}/models/${GEMINI_MODEL}:generateContent?key=${api_key}"

    # Make API call
    local response
    response=$(curl -s -X POST "$api_url" \
        -H "Content-Type: application/json" \
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
    "model": "$GEMINI_MODEL"
}
EOF
        return 1
    fi

    # Check for API errors
    # Use printf '%s' to preserve escape sequences in JSON
    local error_message
    error_message=$(printf '%s' "$response" | jq -r '.error.message // empty' 2>/dev/null)

    if [[ -n "$error_message" ]]; then
        local error_code
        error_code=$(printf '%s' "$response" | jq -r '.error.code // "unknown"')
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "issues": [],
    "summary": "API error: $error_message",
    "error": "$error_code: $error_message",
    "model": "$GEMINI_MODEL"
}
EOF
        return 1
    fi

    # Extract the response content
    local content
    content=$(printf '%s' "$response" | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null)

    if [[ -z "$content" ]]; then
        # Check for safety filters
        local block_reason
        block_reason=$(printf '%s' "$response" | jq -r '.candidates[0].finishReason // empty' 2>/dev/null)

        if [[ "$block_reason" == "SAFETY" ]]; then
            cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "issues": [],
    "summary": "Response blocked by safety filters",
    "error": "Safety filter triggered",
    "model": "$GEMINI_MODEL"
}
EOF
            return 1
        fi

        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "issues": [],
    "summary": "Empty response from API",
    "error": "No content in API response",
    "model": "$GEMINI_MODEL"
}
EOF
        return 1
    fi

    # Validate JSON response
    # Use printf '%s' instead of echo to preserve literal escape sequences like \n
    if ! printf '%s' "$content" | jq -e '.' >/dev/null 2>&1; then
        # Try to extract JSON from markdown code fences or raw text
        local json_result

        # First try: extract from ```json ... ``` code fence
        json_result=$(printf '%s' "$content" | sed -n '/^```json/,/^```$/p' | sed '1d;$d')

        # Second try: extract from ``` ... ``` code fence
        if ! printf '%s' "$json_result" | jq -e '.' >/dev/null 2>&1; then
            json_result=$(printf '%s' "$content" | sed -n '/^```/,/^```$/p' | sed '1d;$d')
        fi

        # Third try: find JSON object in response (single line)
        if ! printf '%s' "$json_result" | jq -e '.' >/dev/null 2>&1; then
            json_result=$(printf '%s' "$content" | grep -o '{.*}' | head -1)
        fi

        if ! printf '%s' "$json_result" | jq -e '.' >/dev/null 2>&1; then
            # Escape content for JSON
            local escaped_content
            escaped_content=$(printf '%s' "$content" | jq -Rs '.')
            cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.5,
    "issues": [],
    "summary": $escaped_content,
    "error": "Invalid JSON response",
    "model": "$GEMINI_MODEL"
}
EOF
            return 0
        fi
        content="$json_result"
    fi

    # Add model info and return
    printf '%s' "$content" | jq --arg model "$GEMINI_MODEL" '. + {model: $model}'
}

#
# Cleanup (no-op for API provider)
#
gemini_cleanup() {
    return 0
}
