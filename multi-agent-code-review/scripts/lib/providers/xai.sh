#!/usr/bin/env bash
#
# xai.sh - xAI Grok provider for multi-agent reviews
#
# This provider implements the review interface for xAI's Grok models
# using the Responses API (stateful, with server-side tools).
#
# Environment:
#   XAI_API_KEY         Required. API key for xAI (or use GROK_API_KEY)
#   GROK_API_KEY        Required. Alternative to XAI_API_KEY
#   XAI_MODEL           Optional. Model to use (default: grok-4-fast-non-reasoning)
#   XAI_MAX_TOKENS      Optional. Max tokens (default: 4096)
#   XAI_ENABLE_TOOLS    Optional. Enable web_search/code_interpreter (default: true)
#   XAI_DEBUG           Optional. Include debug info in error responses
#
# Usage:
#   source xai.sh
#   result=$(xai_review "$diff" "$context")
#

# Prevent re-sourcing
if [[ -n "${XAI_PROVIDER_LOADED:-}" ]]; then
    return 0
fi
XAI_PROVIDER_LOADED=1

# Configuration
# xAI Responses API (stateful, server-side tools)
XAI_API_URL="${XAI_API_URL:-https://api.x.ai/v1/responses}"
XAI_MODEL="${XAI_MODEL:-grok-4-fast-non-reasoning}"
XAI_MAX_TOKENS="${XAI_MAX_TOKENS:-16384}"
XAI_ENABLE_TOOLS="${XAI_ENABLE_TOOLS:-true}"

#
# Get provider name
#
xai_name() {
    echo "xai"
}

#
# Get the API key (supports both XAI_API_KEY and GROK_API_KEY)
#
_xai_get_api_key() {
    echo "${XAI_API_KEY:-${GROK_API_KEY:-}}"
}

#
# Build an error response JSON using jq for proper escaping
# Args: summary, error, [debug_response]
#
_xai_error_response() {
    local summary="$1"
    local error="$2"
    local debug_response="${3:-}"

    if [[ -n "$debug_response" ]]; then
        jq -n \
            --arg summary "$summary" \
            --arg error "$error" \
            --arg model "$XAI_MODEL" \
            --arg debug "$debug_response" \
            '{
                verdict: "abstain",
                confidence: 0.0,
                issues: [],
                summary: $summary,
                error: $error,
                model: $model,
                debug_response: $debug
            }'
    else
        jq -n \
            --arg summary "$summary" \
            --arg error "$error" \
            --arg model "$XAI_MODEL" \
            '{
                verdict: "abstain",
                confidence: 0.0,
                issues: [],
                summary: $summary,
                error: $error,
                model: $model
            }'
    fi
}

#
# Extract content from xAI API response
# Tries multiple extraction paths for compatibility:
#   1. Responses API format: .output[].content[].text
#   2. Direct string output: .output (if string)
#   3. Legacy Chat Completions: .choices[0].message.content
#
_xai_extract_content() {
    local response="$1"
    local content=""

    # Primary: Responses API format - output array with message objects
    content=$(printf '%s' "$response" | jq -r '
        [.output[]? | select(.type == "message") | .content[]? | select(.type == "output_text") | .text]
        | first // empty
    ' 2>/dev/null)

    # Fallback: direct output field (only if string)
    if [[ -z "$content" ]]; then
        content=$(printf '%s' "$response" | jq -r '.output | if type == "string" then . else empty end' 2>/dev/null)
    fi

    # Fallback: legacy Chat Completions format
    if [[ -z "$content" ]]; then
        content=$(printf '%s' "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
    fi

    echo "$content"
}

#
# Check if provider is properly configured
#
xai_check() {
    local api_key
    api_key=$(_xai_get_api_key)
    if [[ -z "$api_key" ]]; then
        echo "false"
        return 1
    fi
    echo "true"
    return 0
}

#
# Execute review using Grok
#
xai_review() {
    local diff="$1"
    local context="${2:-\{\}}"

    # Get API key (supports both XAI_API_KEY and GROK_API_KEY)
    local api_key
    api_key=$(_xai_get_api_key)

    # Validate API key
    if [[ -z "$api_key" ]]; then
        _xai_error_response \
            "xAI API key not configured" \
            "API key environment variable is not set"
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

    # Build request body using jq for robust JSON construction
    local request_body
    local tools_enabled="false"
    if [[ "${XAI_ENABLE_TOOLS,,}" =~ ^(true|yes|1)$ ]]; then
        tools_enabled="true"
    fi

    request_body=$(jq -n \
        --arg model "$XAI_MODEL" \
        --argjson max_tokens "$XAI_MAX_TOKENS" \
        --arg message "$full_message" \
        --argjson tools_enabled "$tools_enabled" \
        '{
            model: $model,
            max_output_tokens: $max_tokens,
            temperature: 0.3,
            store: false,
            input: [
                {
                    role: "developer",
                    content: "You are an expert code reviewer. Always respond with valid JSON."
                },
                {
                    role: "user",
                    content: $message
                }
            ]
        } + (if $tools_enabled then {tools: [{type: "web_search"}, {type: "code_interpreter"}]} else {} end)'
    )

    # Make API call
    local response
    response=$(curl -s -X POST "$XAI_API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $api_key" \
        -d "$request_body" 2>&1)

    local curl_exit_code=$?

    if [[ $curl_exit_code -ne 0 ]]; then
        _xai_error_response \
            "API request failed" \
            "curl failed with exit code $curl_exit_code"
        return 1
    fi

    # Check for API errors
    # Use printf '%s' to preserve escape sequences in JSON
    local error_message
    error_message=$(printf '%s' "$response" | jq -r '.error.message // empty' 2>/dev/null)

    if [[ -n "$error_message" ]]; then
        local error_type
        error_type=$(printf '%s' "$response" | jq -r '.error.type // "api_error"')

        # Sanitize error messages to avoid leaking sensitive info
        local safe_message="API request failed"
        case "$error_type" in
            *auth*|*key*|*token*|*credential*)
                safe_message="Authentication failed"
                ;;
            *rate*|*limit*|*quota*)
                safe_message="Rate limit exceeded"
                ;;
            *model*|*invalid*)
                safe_message="Invalid request"
                ;;
            *)
                # Truncate and use generic message for unknown errors
                safe_message="${error_message:0:100}"
                ;;
        esac

        _xai_error_response \
            "API error: $safe_message" \
            "$error_type"
        return 1
    fi

    # Extract content from response
    local content
    content=$(_xai_extract_content "$response")

    if [[ -z "$content" ]]; then
        # Include debug info only if XAI_DEBUG is set
        local debug_response=""
        if [[ -n "${XAI_DEBUG:-}" ]]; then
            debug_response=$(printf '%s' "$response" | jq -c '.' 2>/dev/null | head -c 500)
        fi
        _xai_error_response \
            "Empty response from API" \
            "No content in API response" \
            "$debug_response"
        return 1
    fi

    # Validate JSON response - try direct parse first
    # Use printf '%s' instead of echo to preserve literal \n sequences in JSON
    if ! printf '%s' "$content" | jq -e '.' >/dev/null 2>&1; then
        # Content is not valid JSON, try to extract JSON object from text
        # Use awk to find balanced braces (handles multi-line JSON)
        local json_result
        json_result=$(printf '%s' "$content" | awk '
            BEGIN { depth=0; capture=0; json="" }
            {
                for (i=1; i<=length($0); i++) {
                    c = substr($0, i, 1)
                    if (c == "{") {
                        if (depth == 0) capture = 1
                        depth++
                    }
                    if (capture) json = json c
                    if (c == "}") {
                        depth--
                        if (depth == 0 && capture) {
                            print json
                            exit
                        }
                    }
                }
                if (capture) json = json "\n"
            }
        ')

        if [[ -z "$json_result" ]] || ! printf '%s' "$json_result" | jq -e '.' >/dev/null 2>&1; then
            # Return non-JSON content as summary (properly escaped)
            jq -n \
                --arg summary "$content" \
                --arg model "$XAI_MODEL" \
                '{
                    verdict: "abstain",
                    confidence: 0.5,
                    issues: [],
                    summary: $summary,
                    error: null,
                    model: $model
                }'
            return 0
        fi
        content="$json_result"
    fi

    # Add model info and return
    printf '%s' "$content" | jq --arg model "$XAI_MODEL" '. + {model: $model}'
}

#
# Cleanup (no-op for API provider)
#
xai_cleanup() {
    return 0
}
