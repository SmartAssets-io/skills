#!/usr/bin/env bash
#
# openrouter.sh - OpenRouter provider for unified LLM client and multi-agent reviews
#
# Implements the _openrouter_request() interface for llm-client.sh and the
# openrouter_review() interface for review-providers.sh.
# OpenRouter exposes an OpenAI-compatible API that routes to multiple
# model providers (Anthropic, OpenAI, Google, Meta, Mistral, Moonshot, etc.).
#
# Environment:
#   OPENROUTER_API_KEY    Required. API key for OpenRouter
#   OPENROUTER_MODEL      Optional. Model to use. Defaults differ by interface:
#                         llm-client requests default to anthropic/claude-opus-4-5,
#                         review requests default to moonshotai/kimi-k3
#   OPENROUTER_BASE_URL   Optional. API base URL (default: https://openrouter.ai/api/v1)
#   OPENROUTER_MAX_TOKENS Optional. Max completion tokens for reviews (default: 4096).
#                         On reasoning models this budget covers reasoning tokens
#                         plus the answer.
#   OPENROUTER_TIMEOUT    Optional. Review timeout in seconds (overrides
#                         PROVIDER_TIMEOUT; default 300 for reviews). The default
#                         review model (moonshotai/kimi-k3) is served as a
#                         reasoning model and can need minutes on large diffs.
#   OPENROUTER_REASONING_EFFORT
#                         Optional. Reasoning effort for reviews (default: low).
#                         Valid: max, xhigh, high, medium, low, minimal, none.
#                         "low" caps reasoning tokens so the JSON answer is not
#                         truncated inside OPENROUTER_MAX_TOKENS. Set to "omit"
#                         to send no reasoning parameter at all.
#
# Usage (via llm-client.sh):
#   source llm-client.sh
#   llm_request "prompt" --backend openrouter
#
# Usage (via review-providers.sh):
#   source openrouter.sh
#   result=$(openrouter_review "$diff" "$context")
#
# Usage (direct):
#   source openrouter.sh
#   result=$(_openrouter_request "$request_json")
#

# Prevent re-sourcing
if [[ -n "${OPENROUTER_LLM_PROVIDER_LOADED:-}" ]]; then
    return 0
fi
OPENROUTER_LLM_PROVIDER_LOADED=1

# Configuration
_OPENROUTER_BASE_URL="${OPENROUTER_BASE_URL:-https://openrouter.ai/api/v1}"
_OPENROUTER_DEFAULT_MODEL="${OPENROUTER_MODEL:-anthropic/claude-opus-4-5}"

#
# Get provider name
#
_openrouter_name() {
    echo "openrouter"
}

#
# Check if provider is configured
#
_openrouter_check() {
    if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
        echo "false"
        return 1
    fi
    echo "true"
    return 0
}

#
# Execute an LLM request via OpenRouter.
#
# Args: $1 = unified request JSON from llm-client.sh
# Returns: unified response JSON on stdout
#
# Request format (input):
#   {"model":"auto","messages":[...],"max_tokens":4096,"temperature":0.3,"response_format":"text"}
#
# Response format (output):
#   {"content":"...","model":"...","backend":"openrouter","usage":{...},"error":null}
#
_openrouter_request() {
    local request_json="$1"

    # Validate API key
    if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
        jq -n '{
            content: "",
            model: "",
            backend: "openrouter",
            usage: null,
            error: "OPENROUTER_API_KEY not set"
        }'
        return 1
    fi

    # Extract fields from unified request
    local model max_tokens temperature response_format messages
    model=$(printf '%s' "$request_json" | jq -r '.model // "auto"')
    max_tokens=$(printf '%s' "$request_json" | jq -r '.max_tokens // 4096')
    temperature=$(printf '%s' "$request_json" | jq -r '.temperature // 0.3')
    response_format=$(printf '%s' "$request_json" | jq -r '.response_format // "text"')
    messages=$(printf '%s' "$request_json" | jq -c '.messages // []')

    # Resolve model
    if [[ "$model" == "auto" ]]; then
        model="$_OPENROUTER_DEFAULT_MODEL"
    fi

    # Build OpenRouter request body (OpenAI-compatible format)
    local request_body
    request_body=$(jq -n \
        --arg model "$model" \
        --argjson messages "$messages" \
        --argjson max_tokens "$max_tokens" \
        --arg temperature "$temperature" \
        '{
            model: $model,
            messages: $messages,
            max_tokens: $max_tokens,
            temperature: ($temperature | tonumber)
        }')

    # Add response_format for JSON mode
    if [[ "$response_format" == "json" ]]; then
        request_body=$(printf '%s' "$request_body" | jq '. + {response_format: {type: "json_object"}}')
    fi

    # Make API call
    local response http_code
    local tmp_body tmp_headers
    tmp_body=$(mktemp)
    tmp_headers=$(mktemp)

    http_code=$(curl -s -w "%{http_code}" -o "$tmp_body" \
        -X POST "${_OPENROUTER_BASE_URL}/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENROUTER_API_KEY" \
        -H "HTTP-Referer: https://gitlab.com/smart-assets.io" \
        -H "X-Title: Smart Assets AI Tools" \
        -d "$request_body" 2>/dev/null) || {
        rm -f "$tmp_body" "$tmp_headers"
        jq -n '{
            content: "",
            model: "",
            backend: "openrouter",
            usage: null,
            error: "curl request failed"
        }'
        return 1
    }

    response=$(cat "$tmp_body")
    rm -f "$tmp_body" "$tmp_headers"

    # Check HTTP status
    if [[ "$http_code" -ge 400 ]]; then
        local error_msg
        error_msg=$(printf '%s' "$response" | jq -r '.error.message // .error // "HTTP '"$http_code"'"' 2>/dev/null || echo "HTTP $http_code")
        jq -n --arg error "$http_code: $error_msg" --arg model "$model" '{
            content: "",
            model: $model,
            backend: "openrouter",
            usage: null,
            error: $error
        }'
        return 1
    fi

    # Extract content from OpenAI-compatible response
    local content actual_model usage_json
    content=$(printf '%s' "$response" | jq -r '.choices[0].message.content // ""' 2>/dev/null)
    actual_model=$(printf '%s' "$response" | jq -r '.model // "unknown"' 2>/dev/null)

    # Extract usage (may not always be present)
    usage_json=$(printf '%s' "$response" | jq '{
        prompt_tokens: (.usage.prompt_tokens // 0),
        completion_tokens: (.usage.completion_tokens // 0),
        total_tokens: (.usage.total_tokens // 0)
    }' 2>/dev/null || echo 'null')

    if [[ -z "$content" ]]; then
        jq -n --arg model "$actual_model" '{
            content: "",
            model: $model,
            backend: "openrouter",
            usage: null,
            error: "Empty response content"
        }'
        return 1
    fi

    # Build unified response
    jq -n \
        --arg content "$content" \
        --arg model "$actual_model" \
        --argjson usage "$usage_json" \
        '{
            content: $content,
            model: $model,
            backend: "openrouter",
            usage: $usage,
            error: null
        }'
}

#
# Cleanup (no-op for API provider)
#
_openrouter_cleanup() {
    return 0
}

# ---------------------------------------------------------------------------
# Review interface (review-providers.sh)
# ---------------------------------------------------------------------------
# The review default is resolved after _OPENROUTER_DEFAULT_MODEL above so the
# llm-client default stays anthropic/claude-opus-4-5 when OPENROUTER_MODEL is
# unset, while reviews default to Moonshot Kimi K3.

OPENROUTER_MODEL="${OPENROUTER_MODEL:-moonshotai/kimi-k3}"
OPENROUTER_MAX_TOKENS="${OPENROUTER_MAX_TOKENS:-4096}"

# Reviews default to a 300s budget: the default review model is a reasoning
# model and can need minutes on a review-sized diff. review-providers.sh reads
# this same variable for its outer watchdog, so one default bounds both the
# watchdog and the curl call below.
OPENROUTER_TIMEOUT="${OPENROUTER_TIMEOUT:-300}"

# Cap reasoning effort so reasoning tokens leave room for the JSON answer
# inside OPENROUTER_MAX_TOKENS. Any value outside the valid set (e.g. "omit")
# sends no reasoning parameter.
OPENROUTER_REASONING_EFFORT="${OPENROUTER_REASONING_EFFORT:-low}"

#
# Get provider name
#
openrouter_name() {
    echo "openrouter"
}

#
# Check if provider is properly configured
#
openrouter_check() {
    _openrouter_check
}

#
# Execute review via OpenRouter (OpenAI-compatible chat completions)
#
openrouter_review() {
    local diff="$1"
    local context="${2:-\{\}}"

    # Validate API key
    if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
        jq -n --arg model "$OPENROUTER_MODEL" '{
            verdict: "abstain",
            confidence: 0.0,
            issues: [],
            summary: "OpenRouter API key not configured",
            error: "OPENROUTER_API_KEY environment variable not set",
            model: $model
        }'
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

    # Build request body with jq so the message, model, and configuration
    # values are always valid JSON regardless of quoting
    local max_tokens="$OPENROUTER_MAX_TOKENS"
    [[ "$max_tokens" =~ ^[0-9]+$ ]] || max_tokens=4096
    local request_body
    request_body=$(jq -n \
        --arg model "$OPENROUTER_MODEL" \
        --argjson max_tokens "$max_tokens" \
        --arg content "$full_message" \
        '{
            model: $model,
            max_tokens: $max_tokens,
            response_format: {type: "json_object"},
            messages: [
                {
                    role: "system",
                    content: "You are an expert code reviewer. Always respond with valid JSON."
                },
                {
                    role: "user",
                    content: $content
                }
            ]
        }')

    # OpenRouter normalizes the reasoning parameter across providers and
    # drops it for models that do not support it. Invalid values silently
    # omit the field (no stderr: execute_with_timeout merges stderr into
    # the JSON result).
    if [[ "$OPENROUTER_REASONING_EFFORT" =~ ^(max|xhigh|high|medium|low|minimal|none)$ ]]; then
        request_body=$(printf '%s' "$request_body" | \
            jq --arg effort "$OPENROUTER_REASONING_EFFORT" '. + {reasoning: {effort: $effort}}')
    fi

    # Bound the HTTP call ~5s under the provider timeout so slow responses
    # surface as diagnosable curl timeouts instead of empty output
    local openrouter_timeout="${OPENROUTER_TIMEOUT:-300}"
    [[ "$openrouter_timeout" =~ ^[0-9]+$ ]] || openrouter_timeout=300
    local curl_max_time=$(( openrouter_timeout > 10 ? openrouter_timeout - 5 : openrouter_timeout ))

    # Make API call, capturing the HTTP status alongside the body
    local tmp_body http_code
    tmp_body=$(mktemp)
    http_code=$(curl -s --max-time "$curl_max_time" -w "%{http_code}" -o "$tmp_body" \
        -X POST "${_OPENROUTER_BASE_URL}/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENROUTER_API_KEY" \
        -H "HTTP-Referer: https://gitlab.com/smart-assets.io" \
        -H "X-Title: Smart Assets AI Tools" \
        -d "$request_body" 2>/dev/null)
    local curl_exit_code=$?

    local response
    response=$(cat "$tmp_body")
    rm -f "$tmp_body"

    if [[ $curl_exit_code -ne 0 ]]; then
        local curl_error="curl failed with exit code $curl_exit_code"
        [[ $curl_exit_code -eq 28 ]] && curl_error="request timed out after ${curl_max_time}s (raise OPENROUTER_TIMEOUT for large diffs)"
        jq -n --arg model "$OPENROUTER_MODEL" --arg error "$curl_error" '{
            verdict: "abstain",
            confidence: 0.0,
            issues: [],
            summary: "API request failed",
            error: $error,
            model: $model
        }'
        return 1
    fi

    if [[ "$http_code" -ge 400 ]]; then
        local http_error
        http_error=$(printf '%s' "$response" | jq -r '.error.message // .error // empty' 2>/dev/null)
        jq -n --arg model "$OPENROUTER_MODEL" --arg error "HTTP $http_code: ${http_error:-request failed}" '{
            verdict: "abstain",
            confidence: 0.0,
            issues: [],
            summary: "API request failed",
            error: $error,
            model: $model
        }'
        return 1
    fi

    # Check for API errors
    # Use printf '%s' to preserve escape sequences in JSON
    local error_message
    error_message=$(printf '%s' "$response" | jq -r '.error.message // empty' 2>/dev/null)

    if [[ -n "$error_message" ]]; then
        local error_type
        error_type=$(printf '%s' "$response" | jq -r '.error.type // .error.code // "api_error"')
        jq -n \
            --arg summary "API error: $error_message" \
            --arg error "$error_type: $error_message" \
            --arg model "$OPENROUTER_MODEL" \
            '{
                verdict: "abstain",
                confidence: 0.0,
                issues: [],
                summary: $summary,
                error: $error,
                model: $model
            }'
        return 1
    fi

    # Extract the response content
    local content finish_reason
    content=$(printf '%s' "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
    finish_reason=$(printf '%s' "$response" | jq -r '.choices[0].finish_reason // empty' 2>/dev/null)

    # On reasoning models, max_tokens covers reasoning plus the answer. When
    # reasoning consumes the whole budget the content comes back empty or
    # truncated with finish_reason=length.
    local budget_hint="token budget exhausted (finish_reason=length): reasoning likely consumed OPENROUTER_MAX_TOKENS - raise it or lower OPENROUTER_REASONING_EFFORT"

    if [[ -z "$content" ]]; then
        local empty_error="No content in API response"
        [[ "$finish_reason" == "length" ]] && empty_error="$budget_hint"
        jq -n --arg model "$OPENROUTER_MODEL" --arg error "$empty_error" '{
            verdict: "abstain",
            confidence: 0.0,
            issues: [],
            summary: "Empty response from API",
            error: $error,
            model: $model
        }'
        return 1
    fi

    # Validate JSON response
    # Use printf '%s' instead of echo to preserve literal escape sequences like \n
    if ! printf '%s' "$content" | jq -e '.' >/dev/null 2>&1; then
        # Try to extract JSON from response
        local json_result
        json_result=$(printf '%s' "$content" | grep -o '{.*}' | head -1)

        if ! printf '%s' "$json_result" | jq -e '.' >/dev/null 2>&1; then
            local trunc_error=null
            if [[ "$finish_reason" == "length" ]]; then
                trunc_error=$(jq -n --arg e "$budget_hint" '$e')
            fi
            jq -n \
                --arg summary "$content" \
                --arg model "$OPENROUTER_MODEL" \
                --argjson error "$trunc_error" \
                '{
                    verdict: "abstain",
                    confidence: 0.5,
                    issues: [],
                    summary: $summary,
                    error: $error,
                    model: $model
                }'
            return 0
        fi
        content="$json_result"
    fi

    # Add model info and return
    # Prefer the model the API actually resolved (may differ from the
    # requested alias); keep the requested value for drift visibility
    local actual_model
    actual_model=$(printf '%s' "$response" | jq -r '.model // empty' 2>/dev/null)
    printf '%s' "$content" | jq \
        --arg model "${actual_model:-$OPENROUTER_MODEL}" \
        --arg requested "$OPENROUTER_MODEL" \
        '. + {model: $model, model_requested: $requested}'
}

#
# Cleanup (no-op for API provider)
#
openrouter_cleanup() {
    return 0
}
