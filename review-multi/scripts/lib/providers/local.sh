#!/usr/bin/env bash
#
# local.sh - Local agent support for multi-agent reviews (Ollama + CLI)
#
# This provider implements the review interface for local LLM agents:
#   1. Ollama - Local LLM server
#   2. CLI wrapper - Custom command-line tools
#
# Environment (Ollama):
#   OLLAMA_HOST        Optional. API endpoint (default: http://localhost:11434)
#   OLLAMA_MODEL       Optional. Model to use (default: codellama:latest)
#   OLLAMA_MAX_TOKENS  Optional. Max tokens (default: 4096)
#   OLLAMA_TIMEOUT     Optional. Request timeout in seconds (default: 180)
#
# Environment (CLI Agent):
#   SA_LOCAL_AGENT     Required. Path to custom CLI agent executable
#   SA_LOCAL_ARGS      Optional. Arguments for custom CLI agent
#   SA_LOCAL_TIMEOUT   Optional. Timeout in seconds (default: 120)
#
# Usage:
#   source local.sh
#   result=$(ollama_review "$diff" "$context")
#   result=$(cli_agent_review "$diff" "$context")
#

# Prevent re-sourcing
if [[ -n "${LOCAL_PROVIDER_LOADED:-}" ]]; then
    return 0
fi
LOCAL_PROVIDER_LOADED=1

# Ollama Configuration
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-codellama:latest}"
OLLAMA_MAX_TOKENS="${OLLAMA_MAX_TOKENS:-4096}"
OLLAMA_TIMEOUT="${OLLAMA_TIMEOUT:-180}"

# CLI Agent Configuration
SA_LOCAL_AGENT="${SA_LOCAL_AGENT:-}"
SA_LOCAL_ARGS="${SA_LOCAL_ARGS:-}"
SA_LOCAL_TIMEOUT="${SA_LOCAL_TIMEOUT:-120}"

#
# ============================================================================
# OLLAMA PROVIDER
# ============================================================================
#

#
# Get provider name
#
ollama_name() {
    echo "ollama"
}

#
# Check if Ollama is available
#
ollama_check() {
    # Try to connect to Ollama API
    local response
    response=$(curl -s --connect-timeout 3 "${OLLAMA_HOST}/api/tags" 2>/dev/null)

    if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
        echo "false"
        return 1
    fi

    # Check if response is valid JSON
    # Use printf '%s' to preserve escape sequences in JSON
    if ! printf '%s' "$response" | jq -e '.' >/dev/null 2>&1; then
        echo "false"
        return 1
    fi

    echo "true"
    return 0
}

#
# List available Ollama models
#
ollama_list_models() {
    local response
    response=$(curl -s --connect-timeout 5 "${OLLAMA_HOST}/api/tags" 2>/dev/null)

    if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
        echo "[]"
        return 1
    fi

    printf '%s' "$response" | jq -r '.models // [] | .[].name'
}

#
# Check if specific model is available
#
ollama_model_available() {
    local model="$1"
    local models
    models=$(ollama_list_models)

    echo "$models" | grep -q "^${model}$"
}

#
# Execute review using Ollama
#
ollama_review() {
    local diff="$1"
    local context="${2:-\{\}}"

    # Check if Ollama is available
    if [[ $(ollama_check) != "true" ]]; then
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "issues": [],
    "summary": "Ollama not available",
    "error": "Cannot connect to Ollama at $OLLAMA_HOST",
    "model": "$OLLAMA_MODEL"
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
    "model": "$OLLAMA_MODEL",
    "prompt": $escaped_message,
    "stream": false,
    "options": {
        "num_predict": $OLLAMA_MAX_TOKENS,
        "temperature": 0.3
    },
    "format": "json"
}
EOF
)

    # Make API call with timeout
    local response
    response=$(curl -s --max-time "$OLLAMA_TIMEOUT" \
        -X POST "${OLLAMA_HOST}/api/generate" \
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
    "error": "curl failed with exit code $curl_exit_code (timeout or connection error)",
    "model": "$OLLAMA_MODEL"
}
EOF
        return 1
    fi

    # Check for API errors
    # Use printf '%s' to preserve escape sequences in JSON
    local error_message
    error_message=$(printf '%s' "$response" | jq -r '.error // empty' 2>/dev/null)

    if [[ -n "$error_message" ]]; then
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "issues": [],
    "summary": "Ollama error: $error_message",
    "error": "$error_message",
    "model": "$OLLAMA_MODEL"
}
EOF
        return 1
    fi

    # Extract the response content
    local content
    content=$(printf '%s' "$response" | jq -r '.response // empty' 2>/dev/null)

    if [[ -z "$content" ]]; then
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "issues": [],
    "summary": "Empty response from Ollama",
    "error": "No response content",
    "model": "$OLLAMA_MODEL"
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
            # Create structured response from text
            cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.5,
    "issues": [],
    "summary": "$(printf '%s' "$content" | head -c 500 | tr '\n' ' ' | sed 's/"/\\"/g')",
    "error": null,
    "model": "$OLLAMA_MODEL"
}
EOF
            return 0
        fi
        content="$json_result"
    fi

    # Add model info and return
    printf '%s' "$content" | jq --arg model "$OLLAMA_MODEL" '. + {model: $model}'
}

#
# Cleanup Ollama (no-op)
#
ollama_cleanup() {
    return 0
}

#
# ============================================================================
# CLI AGENT PROVIDER
# ============================================================================
#

#
# Get provider name
#
cli_agent_name() {
    echo "cli_agent"
}

#
# Check if CLI agent is configured and available
#
cli_agent_check() {
    if [[ -z "$SA_LOCAL_AGENT" ]]; then
        echo "false"
        return 1
    fi

    if [[ ! -x "$SA_LOCAL_AGENT" ]]; then
        echo "false"
        return 1
    fi

    echo "true"
    return 0
}

#
# Execute review using CLI agent
#
cli_agent_review() {
    local diff="$1"
    local context="${2:-\{\}}"

    # Check if agent is configured
    if [[ -z "$SA_LOCAL_AGENT" ]]; then
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "issues": [],
    "summary": "CLI agent not configured",
    "error": "SA_LOCAL_AGENT environment variable not set",
    "model": "cli_agent"
}
EOF
        return 1
    fi

    # Check if agent exists and is executable
    if [[ ! -x "$SA_LOCAL_AGENT" ]]; then
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "issues": [],
    "summary": "CLI agent not executable",
    "error": "Agent at $SA_LOCAL_AGENT is not executable",
    "model": "cli_agent"
}
EOF
        return 1
    fi

    # Build prompt
    local prompt
    prompt=$(get_review_prompt "$context")

    # Combine prompt and diff
    local full_input="${prompt}

\`\`\`diff
${diff}
\`\`\`"

    # Execute agent with timeout
    local result
    local exit_code

    if command -v timeout >/dev/null 2>&1; then
        result=$(echo "$full_input" | timeout "$SA_LOCAL_TIMEOUT" "$SA_LOCAL_AGENT" $SA_LOCAL_ARGS 2>&1)
        exit_code=$?
    elif command -v gtimeout >/dev/null 2>&1; then
        result=$(echo "$full_input" | gtimeout "$SA_LOCAL_TIMEOUT" "$SA_LOCAL_AGENT" $SA_LOCAL_ARGS 2>&1)
        exit_code=$?
    else
        result=$(echo "$full_input" | "$SA_LOCAL_AGENT" $SA_LOCAL_ARGS 2>&1)
        exit_code=$?
    fi

    if [[ $exit_code -ne 0 ]]; then
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "issues": [],
    "summary": "CLI agent failed",
    "error": "Agent exited with code $exit_code: $(echo "$result" | head -c 200)",
    "model": "cli_agent"
}
EOF
        return 1
    fi

    # Validate JSON response
    # Use printf '%s' instead of echo to preserve literal escape sequences like \n
    if ! printf '%s' "$result" | jq -e '.' >/dev/null 2>&1; then
        # Try to extract JSON from response
        local json_result
        json_result=$(printf '%s' "$result" | grep -o '{.*}' | head -1)

        if ! printf '%s' "$json_result" | jq -e '.' >/dev/null 2>&1; then
            cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.5,
    "issues": [],
    "summary": "$(printf '%s' "$result" | head -c 500 | tr '\n' ' ' | sed 's/"/\\"/g')",
    "error": null,
    "model": "cli_agent"
}
EOF
            return 0
        fi
        result="$json_result"
    fi

    # Add model info and return
    printf '%s' "$result" | jq '. + {model: "cli_agent"}'
}

#
# Cleanup CLI agent (no-op)
#
cli_agent_cleanup() {
    return 0
}

#
# ============================================================================
# LOCAL AGENTS HEALTH CHECK
# ============================================================================
#

#
# Check all local agents and return status
#
local_agents_health() {
    local results="{"

    # Check Ollama
    results+="\"ollama\": {"
    if [[ $(ollama_check) == "true" ]]; then
        local ollama_models
        ollama_models=$(ollama_list_models | head -5 | tr '\n' ',' | sed 's/,$//')
        results+="\"status\": \"available\", \"endpoint\": \"$OLLAMA_HOST\", \"models\": [\"$ollama_models\"]"
    else
        results+="\"status\": \"unavailable\", \"endpoint\": \"$OLLAMA_HOST\""
    fi
    results+="},"

    # Check CLI agent
    results+="\"cli_agent\": {"
    if [[ $(cli_agent_check) == "true" ]]; then
        results+="\"status\": \"available\", \"path\": \"$SA_LOCAL_AGENT\""
    else
        if [[ -z "$SA_LOCAL_AGENT" ]]; then
            results+="\"status\": \"not_configured\""
        else
            results+="\"status\": \"unavailable\", \"path\": \"$SA_LOCAL_AGENT\""
        fi
    fi
    results+="}"

    results+="}"
    echo "$results"
}

#
# CLI interface when run directly
#
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    COMMAND="${1:-help}"

    case "$COMMAND" in
        check-ollama)
            if [[ $(ollama_check) == "true" ]]; then
                echo "Ollama is available at $OLLAMA_HOST"
                echo "Models:"
                ollama_list_models | sed 's/^/  - /'
            else
                echo "Ollama is not available at $OLLAMA_HOST"
                exit 1
            fi
            ;;
        check-cli)
            if [[ $(cli_agent_check) == "true" ]]; then
                echo "CLI agent is available at $SA_LOCAL_AGENT"
            else
                echo "CLI agent is not available"
                echo "Set SA_LOCAL_AGENT to the path of your review tool"
                exit 1
            fi
            ;;
        health)
            local_agents_health | jq '.'
            ;;
        help|--help|-h)
            cat <<EOF
local.sh - Local agent support for multi-agent reviews

Usage: $0 <command>

Commands:
    check-ollama    Check if Ollama is available
    check-cli       Check if CLI agent is configured
    health          Show health status of all local agents
    help            Show this help message

Ollama Configuration:
    OLLAMA_HOST     API endpoint (default: http://localhost:11434)
    OLLAMA_MODEL    Model to use (default: codellama:latest)
    OLLAMA_TIMEOUT  Request timeout in seconds (default: 180)

CLI Agent Configuration:
    SA_LOCAL_AGENT   Path to custom CLI review tool
    SA_LOCAL_ARGS    Arguments to pass to the agent
    SA_LOCAL_TIMEOUT Timeout in seconds (default: 120)

CLI Agent Interface:
    Your CLI agent should:
    1. Accept review request via stdin
    2. Output JSON response to stdout
    3. Follow the standard review response format

Example CLI Agent Usage:
    export SA_LOCAL_AGENT="/path/to/my-review-tool"
    export SA_LOCAL_ARGS="--json --review"
    source local.sh
    result=\$(cli_agent_review "\$diff" "\$context")
EOF
            ;;
        *)
            echo "Unknown command: $COMMAND" >&2
            echo "Run '$0 help' for usage" >&2
            exit 1
            ;;
    esac
fi
