#!/usr/bin/env bash
#
# review-providers.sh - Provider interface and registry for multi-agent reviews
#
# This library provides:
# 1. Abstract provider interface definition
# 2. Provider registry management
# 3. API key validation
# 4. Standard request/response format
# 5. Error handling and retry logic
#
# Usage:
#   source /path/to/review-providers.sh
#   providers_init
#   providers_list_enabled
#   provider_execute_review "anthropic" "$diff" "$context"
#
# Dependencies:
#   - jq (required for JSON manipulation)
#   - curl (for API calls)
#   - bash 4+ for associative arrays
#

# Prevent re-sourcing
if [[ -n "${REVIEW_PROVIDERS_LOADED:-}" ]]; then
    return 0
fi
REVIEW_PROVIDERS_LOADED=1

# Script location
PROVIDERS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVIDERS_DIR="${PROVIDERS_LIB_DIR}/providers"

# Configuration
DEFAULT_CONFIG_FILE="${SA_REVIEW_CONFIG:-$HOME/.sa-review-agents.yaml}"
PROVIDER_TIMEOUT="${PROVIDER_TIMEOUT:-120}"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-2}"

#
# Get current timestamp in milliseconds (portable across macOS and Linux)
#
get_timestamp_ms() {
    # Try GNU date with nanoseconds first (Linux)
    if date +%s%N >/dev/null 2>&1; then
        local ns
        ns=$(date +%s%N 2>/dev/null)
        # Check if we got a valid number (not ending in N)
        if [[ "$ns" =~ ^[0-9]+$ ]]; then
            echo $((ns / 1000000))
            return 0
        fi
    fi

    # Fallback: use perl if available (works on macOS)
    if command -v perl >/dev/null 2>&1; then
        perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000'
        return 0
    fi

    # Fallback: use python if available
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import time; print(int(time.time() * 1000))'
        return 0
    fi

    # Last resort: seconds * 1000 (loses millisecond precision)
    echo $(($(date +%s) * 1000))
}

# Provider registry (populated by init)
declare -A PROVIDER_REGISTRY=()
declare -a ENABLED_PROVIDERS=()

# Optional: source unified LLM client for backend routing
# Set LLM_USE_UNIFIED_CLIENT=true to route API calls through llm-client.sh
# instead of making direct curl calls per provider. This enables:
#   - Centralized configuration (.llm-client.yaml)
#   - Automatic fallback between backends
#   - Unified retry logic
_LLM_CLIENT_AVAILABLE=false
if [[ -f "${PROVIDERS_LIB_DIR}/llm-client.sh" ]]; then
    # shellcheck source=/dev/null
    source "${PROVIDERS_LIB_DIR}/llm-client.sh" 2>/dev/null && _LLM_CLIENT_AVAILABLE=true
fi

# Standard severities
SEVERITY_CRITICAL="critical"
SEVERITY_MAJOR="major"
SEVERITY_MINOR="minor"
SEVERITY_SUGGESTION="suggestion"

# Standard categories
CATEGORY_SECURITY="security"
CATEGORY_LOGIC="logic"
CATEGORY_PERFORMANCE="performance"
CATEGORY_STYLE="style"
CATEGORY_DOCUMENTATION="documentation"

# Standard verdicts (ordered by severity, most severe first)
VERDICT_CRITICAL="critical_vulnerabilities"  # Security/critical issues - MUST fix before merge
VERDICT_NEEDS_REVIEW="needs_review"          # Requires human review/decision
VERDICT_FEEDBACK="provide_feedback"          # Has suggestions but can proceed
VERDICT_COMMENT="comment_only"               # Informational only, no action needed
VERDICT_APPROVE="approve"                    # Code looks good, no issues found
VERDICT_ABSTAIN="abstain"                    # Provider couldn't determine
# Error verdicts (differentiate error types)
VERDICT_ERROR_TIMEOUT="error_timeout"        # Request timed out
VERDICT_ERROR_NETWORK="error_network"        # Network/connection issues
VERDICT_ERROR_AUTH="error_auth"              # Authentication failures
VERDICT_ERROR_SERVICE="error_service"        # Generic service errors

#
# Logging utilities
#
log_provider_debug() {
    if [[ "${DEBUG:-}" == "true" ]]; then
        echo "[DEBUG] $1" >&2
    fi
}

log_provider_info() {
    echo "[INFO] $1" >&2
}

log_provider_warning() {
    echo "[WARN] $1" >&2
}

log_provider_error() {
    echo "[ERROR] $1" >&2
}

#
# Initialize providers from configuration
#
providers_init() {
    local config_file="${1:-$DEFAULT_CONFIG_FILE}"

    # Clear existing registry
    PROVIDER_REGISTRY=()
    ENABLED_PROVIDERS=()

    # Default providers (environment-based)
    _register_default_providers

    # Load config file if exists
    if [[ -f "$config_file" ]]; then
        _load_config_file "$config_file"
    fi

    # Validate enabled providers
    _validate_providers

    log_provider_debug "Initialized ${#ENABLED_PROVIDERS[@]} providers"
}

#
# Register default cloud providers based on environment variables
#
_register_default_providers() {
    # Anthropic (Claude)
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        PROVIDER_REGISTRY["anthropic"]="cloud"
        PROVIDER_REGISTRY["anthropic_model"]="${ANTHROPIC_MODEL:-claude-opus-4-5-20251101}"
        PROVIDER_REGISTRY["anthropic_key_var"]="ANTHROPIC_API_KEY"
        PROVIDER_REGISTRY["anthropic_enabled"]="true"
        ENABLED_PROVIDERS+=("anthropic")
    fi

    # OpenAI (ChatGPT)
    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        PROVIDER_REGISTRY["openai"]="cloud"
        PROVIDER_REGISTRY["openai_model"]="${OPENAI_MODEL:-gpt-4-turbo}"
        PROVIDER_REGISTRY["openai_key_var"]="OPENAI_API_KEY"
        PROVIDER_REGISTRY["openai_enabled"]="true"
        ENABLED_PROVIDERS+=("openai")
    fi

    # Gemini - supports both GEMINI_API_KEY and GOOGLE_API_KEY
    local gemini_key="${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}"
    if [[ -n "$gemini_key" ]]; then
        PROVIDER_REGISTRY["gemini"]="cloud"
        PROVIDER_REGISTRY["gemini_model"]="${GEMINI_MODEL:-${GOOGLE_MODEL:-gemini-2.5-pro}}"
        # Store which key variable is actually set
        if [[ -n "${GEMINI_API_KEY:-}" ]]; then
            PROVIDER_REGISTRY["gemini_key_var"]="GEMINI_API_KEY"
        else
            PROVIDER_REGISTRY["gemini_key_var"]="GOOGLE_API_KEY"
        fi
        PROVIDER_REGISTRY["gemini_enabled"]="true"
        ENABLED_PROVIDERS+=("gemini")
    fi

    # xAI (Grok) - supports both XAI_API_KEY and GROK_API_KEY
    local xai_key="${XAI_API_KEY:-${GROK_API_KEY:-}}"
    if [[ -n "$xai_key" ]]; then
        PROVIDER_REGISTRY["xai"]="cloud"
        PROVIDER_REGISTRY["xai_model"]="${XAI_MODEL:-${GROK_MODEL:-grok-4-fast-non-reasoning}}"
        # Store which key variable is actually set
        if [[ -n "${XAI_API_KEY:-}" ]]; then
            PROVIDER_REGISTRY["xai_key_var"]="XAI_API_KEY"
        else
            PROVIDER_REGISTRY["xai_key_var"]="GROK_API_KEY"
        fi
        PROVIDER_REGISTRY["xai_enabled"]="true"
        ENABLED_PROVIDERS+=("xai")
    fi

    # Ollama (local)
    if [[ -n "${OLLAMA_HOST:-}" ]] || curl -s --connect-timeout 1 "http://localhost:11434/api/tags" >/dev/null 2>&1; then
        PROVIDER_REGISTRY["ollama"]="local"
        PROVIDER_REGISTRY["ollama_model"]="${OLLAMA_MODEL:-codellama:latest}"
        PROVIDER_REGISTRY["ollama_endpoint"]="${OLLAMA_HOST:-http://localhost:11434}"
        PROVIDER_REGISTRY["ollama_enabled"]="false"  # Disabled by default
    fi

    # Amazon Bedrock (Nova models)
    # Lazy check: only verify AWS CLI exists or env vars are set
    # Actual authentication is validated in bedrock_check() when provider is used
    # This avoids slow/blocking STS calls during initialization
    local aws_potentially_configured=false
    if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] && [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        aws_potentially_configured=true
    elif command -v aws >/dev/null 2>&1; then
        # AWS CLI exists - credentials may be configured via profile
        aws_potentially_configured=true
    fi

    if [[ "$aws_potentially_configured" == "true" ]]; then
        PROVIDER_REGISTRY["bedrock"]="cloud"
        PROVIDER_REGISTRY["bedrock_model"]="${BEDROCK_MODEL:-us.amazon.nova-pro-v1:0}"
        PROVIDER_REGISTRY["bedrock_key_var"]="AWS_ACCESS_KEY_ID"
        PROVIDER_REGISTRY["bedrock_enabled"]="true"
        ENABLED_PROVIDERS+=("bedrock")
    fi
}

#
# Load configuration from YAML file
#
_load_config_file() {
    local config_file="$1"

    # Simple YAML parsing (for basic config)
    # For complex configs, consider using yq
    log_provider_debug "Loading config from $config_file"

    # This is a simplified parser - for production, use yq
    # For now, we rely on environment variables primarily
}

#
# Validate that enabled providers are properly configured
#
_validate_providers() {
    local valid_providers=()

    for provider in "${ENABLED_PROVIDERS[@]}"; do
        local type="${PROVIDER_REGISTRY[$provider]}"
        local enabled="${PROVIDER_REGISTRY[${provider}_enabled]}"

        if [[ "$enabled" != "true" ]]; then
            continue
        fi

        if [[ "$type" == "cloud" ]]; then
            local key_var="${PROVIDER_REGISTRY[${provider}_key_var]}"
            if [[ -z "${!key_var:-}" ]]; then
                log_provider_warning "Provider $provider missing API key ($key_var)"
                continue
            fi
        fi

        valid_providers+=("$provider")
    done

    ENABLED_PROVIDERS=("${valid_providers[@]}")
}

#
# List enabled providers
#
providers_list_enabled() {
    printf '%s\n' "${ENABLED_PROVIDERS[@]}"
}

#
# Get provider info
#
provider_get_info() {
    local provider="$1"

    if [[ -z "${PROVIDER_REGISTRY[$provider]:-}" ]]; then
        echo "null"
        return 1
    fi

    local type="${PROVIDER_REGISTRY[$provider]}"
    local model="${PROVIDER_REGISTRY[${provider}_model]:-unknown}"
    local enabled="${PROVIDER_REGISTRY[${provider}_enabled]:-false}"

    cat <<EOF
{
    "name": "$provider",
    "type": "$type",
    "model": "$model",
    "enabled": $enabled
}
EOF
}

#
# Check if a provider is available
#
provider_is_available() {
    local provider="$1"

    # Check if in enabled list
    for p in "${ENABLED_PROVIDERS[@]}"; do
        if [[ "$p" == "$provider" ]]; then
            return 0
        fi
    done

    return 1
}

#
# Create standard review request
#
create_review_request() {
    local diff="$1"
    local context="${2:-\{\}}"
    local max_tokens="${3:-4096}"

    # Escape diff for JSON
    local escaped_diff
    escaped_diff=$(echo "$diff" | jq -Rs '.')

    cat <<EOF
{
    "diff": $escaped_diff,
    "context": $context,
    "max_tokens": $max_tokens,
    "request_id": "$(uuidgen 2>/dev/null || echo "req-$$-$(date +%s)")"
}
EOF
}

#
# Parse standard review response
#
parse_review_response() {
    local response="$1"
    local provider="$2"

    # Validate response structure
    if ! echo "$response" | jq -e '.' >/dev/null 2>&1; then
        create_error_response "$provider" "Invalid JSON response"
        return 1
    fi

    # Ensure required fields
    local verdict
    verdict=$(echo "$response" | jq -r '.verdict // "abstain"')

    local confidence
    confidence=$(echo "$response" | jq -r '.confidence // 0.5')

    # Normalize response
    echo "$response" | jq --arg provider "$provider" --arg verdict "$verdict" --argjson conf "$confidence" '
        {
            provider: $provider,
            model: (.model // "unknown"),
            verdict: $verdict,
            confidence: $conf,
            issues: (.issues // []),
            summary: (.summary // "No summary provided"),
            error: null,
            duration_ms: (.duration_ms // 0)
        }
    '
}

#
# Create error response
#
create_error_response() {
    local provider="$1"
    local error_msg="$2"
    local duration="${3:-0}"
    local exit_code="${4:-0}"

    # Categorize error type based on exit code and error message
    local verdict="$VERDICT_ERROR_SERVICE"
    local error_type="Service Error"

    # Timeout errors (exit code 124 or 143)
    if [[ $exit_code -eq 124 ]] || [[ $exit_code -eq 143 ]]; then
        verdict="$VERDICT_ERROR_TIMEOUT"
        error_type="Timeout"
    # Network errors
    elif echo "$error_msg" | grep -qiE "connection refused|network|dns|could not resolve|failed to connect|curl.*failed"; then
        verdict="$VERDICT_ERROR_NETWORK"
        error_type="Network Error"
    # Authentication errors (but not config errors like max_tokens)
    elif echo "$error_msg" | grep -qiE "unauthorized|authentication|invalid.*(api.key|token|credentials)|401|403" && \
         ! echo "$error_msg" | grep -qiE "max_tokens|invalid.*request|model.*not.*found"; then
        verdict="$VERDICT_ERROR_AUTH"
        error_type="Auth Error"
    fi

    # Escape error message for JSON using jq
    local escaped_error escaped_summary
    escaped_error=$(printf '%s' "$error_msg" | jq -Rs '.')
    escaped_summary=$(printf '%s' "$error_type: $error_msg" | jq -Rs '.')

    cat <<EOF
{
    "provider": "$provider",
    "model": "unknown",
    "verdict": "$verdict",
    "confidence": 0.0,
    "issues": [],
    "summary": $escaped_summary,
    "error": $escaped_error,
    "error_type": "$error_type",
    "duration_ms": $duration
}
EOF
}

#
# Create abstain response (when provider cannot complete review)
#
create_abstain_response() {
    local provider="$1"
    local reason="$2"
    local duration="${3:-0}"

    cat <<EOF
{
    "provider": "$provider",
    "model": "${PROVIDER_REGISTRY[${provider}_model]:-unknown}",
    "verdict": "$VERDICT_ABSTAIN",
    "confidence": 0.0,
    "issues": [],
    "summary": "Review abstained: $reason",
    "error": null,
    "duration_ms": $duration
}
EOF
}

#
# Execute API call with retry logic
#
api_call_with_retry() {
    local cmd="$1"
    local max_retries="${MAX_RETRIES:-3}"
    local delay="${RETRY_DELAY:-2}"

    for ((i=1; i<=max_retries; i++)); do
        local result
        local exit_code

        result=$(eval "$cmd" 2>&1)
        exit_code=$?

        if [[ $exit_code -eq 0 ]] && [[ -n "$result" ]]; then
            echo "$result"
            return 0
        fi

        # Check for rate limiting
        if echo "$result" | grep -qi "rate.limit\|429\|too.many.requests"; then
            log_provider_warning "Rate limited, waiting ${delay}s (attempt $i/$max_retries)"
            sleep "$delay"
            delay=$((delay * 2))
            continue
        fi

        # Other errors - fail immediately or retry
        if [[ $i -lt $max_retries ]]; then
            log_provider_debug "API call failed (attempt $i/$max_retries): $result"
            sleep 1
        else
            log_provider_error "API call failed after $max_retries attempts: $result"
            return 1
        fi
    done

    return 1
}

#
# Execute review with timeout
#
# Uses temp files to safely pass arguments containing special characters
# (newlines, quotes, etc.) to subshell when timeout is needed.
#
execute_with_timeout() {
    local timeout_secs="${1:-$PROVIDER_TIMEOUT}"
    shift
    local func_name="$1"
    shift

    # Create temp directory for argument files
    local tmp_dir
    tmp_dir=$(mktemp -d)

    # Write arguments to temp files (preserves all special characters)
    local i=0
    for arg in "$@"; do
        printf '%s' "$arg" > "$tmp_dir/arg_$i"
        ((i++))
    done

    # Build script that reads args from files and calls the function
    # The script sources required libraries to get function definitions
    local script
    script="
        set -euo pipefail
        # Source the provider libraries to get function definitions
        if ! source '${PROVIDERS_LIB_DIR}/review-providers.sh' 2>&1; then
            echo '{\"verdict\":\"error_service\",\"error\":\"Failed to source review-providers.sh\"}' >&2
            exit 1
        fi
        if [[ -f '${PROVIDERS_DIR}/${func_name%%_*}.sh' ]]; then
            if ! source '${PROVIDERS_DIR}/${func_name%%_*}.sh' 2>&1; then
                echo '{\"verdict\":\"error_service\",\"error\":\"Failed to source provider script\"}' >&2
                exit 1
            fi
        else
            echo '{\"verdict\":\"error_service\",\"error\":\"Provider script not found\"}' >&2
            exit 1
        fi

        # Read arguments from temp files
        args=()
        for f in '$tmp_dir'/arg_*; do
            [[ -f \"\$f\" ]] && args+=(\"\$(cat \"\$f\")\")
        done

        # Call the function with arguments
        $func_name \"\${args[@]}\"
    "

    local result
    local exit_code

    if command -v timeout >/dev/null 2>&1; then
        result=$(timeout "$timeout_secs" bash -c "$script" 2>&1)
        exit_code=$?
    elif command -v gtimeout >/dev/null 2>&1; then
        result=$(gtimeout "$timeout_secs" bash -c "$script" 2>&1)
        exit_code=$?
    else
        # Fallback: no timeout available, run directly
        # This path doesn't need bash -c, so call function directly
        result=$("$func_name" "$@" 2>&1)
        exit_code=$?
    fi

    # Cleanup temp files
    rm -rf "$tmp_dir"

    echo "$result"
    return $exit_code
}

#
# Load provider implementation
#
_load_provider_impl() {
    local provider="$1"
    local provider_file="${PROVIDERS_DIR}/${provider}.sh"

    if [[ -f "$provider_file" ]]; then
        # shellcheck source=/dev/null
        source "$provider_file"
        return 0
    fi

    log_provider_warning "Provider implementation not found: $provider_file"
    return 1
}

#
# Execute review using specified provider
#
provider_execute_review() {
    local provider="$1"
    local diff="$2"
    local context="${3:-\{\}}"

    local start_time
    start_time=$(get_timestamp_ms)

    # Check provider availability
    if ! provider_is_available "$provider"; then
        create_error_response "$provider" "Provider not available or not enabled"
        return 1
    fi

    # Load provider implementation
    if ! _load_provider_impl "$provider"; then
        create_error_response "$provider" "Provider implementation not found"
        return 1
    fi

    # Call provider-specific review function
    local review_func="${provider}_review"
    if ! declare -f "$review_func" >/dev/null 2>&1; then
        create_error_response "$provider" "Provider review function not implemented"
        return 1
    fi

    # Execute with timeout
    local result
    result=$(execute_with_timeout "$PROVIDER_TIMEOUT" "$review_func" "$diff" "$context")
    local exit_code=$?

    local end_time
    end_time=$(get_timestamp_ms)
    local duration=$((end_time - start_time))

    # Check if result is empty
    if [[ -z "$result" ]]; then
        create_error_response "$provider" "Empty response from provider" "$duration" "$exit_code"
        return 1
    fi

    # Check if result is valid JSON (providers may return JSON even with non-zero exit)
    if printf '%s' "$result" | jq -e '.' >/dev/null 2>&1; then
        # Valid JSON response - parse it (may contain abstain or error verdict)
        parse_review_response "$result" "$provider" | jq --argjson dur "$duration" '.duration_ms = $dur'
    elif [[ $exit_code -ne 0 ]]; then
        # Non-zero exit with invalid JSON - treat as error
        create_error_response "$provider" "$result" "$duration" "$exit_code"
        return 1
    else
        # Zero exit with invalid JSON - still try to parse
        parse_review_response "$result" "$provider" | jq --argjson dur "$duration" '.duration_ms = $dur'
    fi
}

#
# Execute reviews in parallel across multiple providers
#
providers_execute_parallel() {
    local diff="$1"
    local context="${2:-\{\}}"
    local providers="${3:-}"  # Optional comma-separated list

    # Determine which providers to use
    local provider_list
    if [[ -n "$providers" ]]; then
        IFS=',' read -ra provider_list <<< "$providers"
    else
        provider_list=("${ENABLED_PROVIDERS[@]}")
    fi

    if [[ ${#provider_list[@]} -eq 0 ]]; then
        log_provider_error "No providers available"
        echo '{"error": "No providers available", "reviews": []}'
        return 1
    fi

    # Create temp directory for results
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT

    # Launch parallel reviews
    local pids=()
    for provider in "${provider_list[@]}"; do
        (
            log_provider_info "Starting review with $provider"
            local result
            result=$(provider_execute_review "$provider" "$diff" "$context")
            echo "$result" > "$temp_dir/${provider}.json"
        ) &
        pids+=($!)
    done

    # Wait for all to complete
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    # Collect results
    local reviews="["
    local first=true
    for provider in "${provider_list[@]}"; do
        local result_file="$temp_dir/${provider}.json"
        if [[ -f "$result_file" ]]; then
            if [[ "$first" == "true" ]]; then
                first=false
            else
                reviews+=","
            fi
            reviews+=$(cat "$result_file")
        fi
    done
    reviews+="]"

    # Build final result
    cat <<EOF
{
    "providers_requested": ${#provider_list[@]},
    "providers_completed": $(echo "$reviews" | jq '[.[] | select(.error == null)] | length'),
    "reviews": $reviews
}
EOF
}

#
# Get review prompt template
#
# Builds a review prompt with context values substituted in.
# Uses printf instead of sed to avoid issues with special characters.
#
get_review_prompt() {
    local context="$1"

    local repo_name pr_title pr_description target_branch file_count
    repo_name=$(echo "$context" | jq -r '.repo_name // "unknown"')
    pr_title=$(echo "$context" | jq -r '.pr_title // "Code Review"')
    pr_description=$(echo "$context" | jq -r '.pr_description // ""')
    target_branch=$(echo "$context" | jq -r '.target_branch // "main"')
    file_count=$(echo "$context" | jq -r '.file_count // "unknown"')

    # Use printf with %s to safely substitute values without sed issues
    printf '%s\n' "You are reviewing a code change for a pull request.

## Context
- Repository: ${repo_name}
- PR Title: ${pr_title}
- PR Description: ${pr_description}
- Target Branch: ${target_branch}
- Files Changed: ${file_count}

## Your Task
Review the following code diff and identify:
1. **Security Issues** - Vulnerabilities, injection risks, authentication problems
2. **Logic Errors** - Bugs, incorrect behavior, edge cases not handled
3. **Performance Issues** - Inefficiencies, N+1 queries, memory leaks
4. **Style Issues** - Convention violations, naming issues, missing documentation

## Response Format
You MUST respond with a valid JSON object containing:
{
    \"verdict\": \"critical_vulnerabilities\" | \"needs_review\" | \"provide_feedback\" | \"comment_only\" | \"approve\" | \"abstain\",
    \"confidence\": 0.0 to 1.0,
    \"issues\": [
        {
            \"severity\": \"critical\" | \"major\" | \"minor\" | \"suggestion\",
            \"category\": \"security\" | \"logic\" | \"performance\" | \"style\" | \"documentation\",
            \"file\": \"path/to/file\",
            \"line\": 42,
            \"title\": \"Brief issue title\",
            \"description\": \"Detailed explanation of the issue\",
            \"suggestion\": \"Optional: suggested fix or improvement\"
        }
    ],
    \"summary\": \"One paragraph overall assessment of the code change\"
}

## Verdict Guidelines
- **critical_vulnerabilities**: Security holes, data leaks, authentication bypasses - MUST fix before merge
- **needs_review**: Complex changes requiring human judgment, architectural decisions, unclear requirements
- **provide_feedback**: Has suggestions/improvements but code is functional and safe to merge
- **comment_only**: Informational observations, style preferences, no action needed
- **approve**: Code looks good, no issues found
- **abstain**: Cannot determine (insufficient context or unclear changes)

Focus on actionable feedback. Be specific about file paths and line numbers.

## Code Diff"
}

#
# Bridge: execute a review using the unified LLM client
#
# When LLM_USE_UNIFIED_CLIENT=true and llm-client.sh is available,
# this function routes the review through the unified client instead
# of using the provider-specific curl call directly. This provides
# centralized config, fallback routing, and retry logic.
#
# Args: $1 = provider name, $2 = prompt text, $3 = system prompt
# Returns: raw LLM response text on stdout
#
provider_llm_request() {
    local provider="$1"
    local prompt="$2"
    local system_prompt="${3:-}"

    if [[ "${LLM_USE_UNIFIED_CLIENT:-false}" == "true" ]] && [[ "$_LLM_CLIENT_AVAILABLE" == "true" ]]; then
        if [[ "$_LLM_CONFIGURED" != "true" ]]; then
            llm_configure
        fi

        local args=(--backend "$provider" --json)
        if [[ -n "$system_prompt" ]]; then
            args+=(--system "$system_prompt")
        fi

        local result
        result=$(llm_request "$prompt" "${args[@]}")
        local exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            echo "$result" | jq -r '.content // ""'
            return 0
        fi

        log_provider_warning "Unified client request failed for $provider, falling back to direct call"
    fi

    return 1
}

#
# CLI interface when run directly
#
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    COMMAND="${1:-help}"

    case "$COMMAND" in
        init)
            providers_init "${2:-}"
            echo "Initialized ${#ENABLED_PROVIDERS[@]} providers"
            ;;
        list)
            providers_init
            providers_list_enabled
            ;;
        info)
            providers_init
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 info PROVIDER" >&2
                exit 1
            fi
            provider_get_info "$2"
            ;;
        check)
            providers_init
            if [[ -z "${2:-}" ]]; then
                echo "Usage: $0 check PROVIDER" >&2
                exit 1
            fi
            if provider_is_available "$2"; then
                echo "Provider $2 is available"
            else
                echo "Provider $2 is not available"
                exit 1
            fi
            ;;
        help|--help|-h)
            cat <<EOF
review-providers.sh - Provider interface and registry for multi-agent reviews

Usage: $0 <command> [args]

Commands:
    init [config]     Initialize providers (optionally from config file)
    list              List enabled providers
    info PROVIDER     Get info about a specific provider
    check PROVIDER    Check if provider is available
    help              Show this help message

Environment Variables:
    ANTHROPIC_API_KEY    API key for Anthropic Claude
    OPENAI_API_KEY       API key for OpenAI ChatGPT
    GOOGLE_API_KEY       API key for Google Gemini (or use GEMINI_API_KEY)
    GEMINI_API_KEY       Alternative to GOOGLE_API_KEY
    XAI_API_KEY          API key for xAI Grok (or use GROK_API_KEY)
    GROK_API_KEY         Alternative to XAI_API_KEY
    AWS_ACCESS_KEY_ID    AWS credentials for Amazon Bedrock Nova
    AWS_SECRET_ACCESS_KEY AWS credentials for Amazon Bedrock Nova
    AWS_REGION           AWS region (default: us-east-1)
    BEDROCK_MODEL        Bedrock model (default: us.amazon.nova-pro-v1:0)
    OLLAMA_HOST          Ollama API endpoint (default: http://localhost:11434)
    SA_REVIEW_CONFIG     Path to config file
    PROVIDER_TIMEOUT     Timeout in seconds (default: 120)
    DEBUG                Set to "true" for debug output

As a library:
    source /path/to/review-providers.sh
    providers_init
    provider_execute_review "anthropic" "\$diff" "\$context"
EOF
            ;;
        *)
            echo "Unknown command: $COMMAND" >&2
            echo "Run '$0 help' for usage" >&2
            exit 1
            ;;
    esac
fi
