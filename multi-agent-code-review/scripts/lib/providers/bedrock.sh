#!/usr/bin/env bash
#
# bedrock.sh - Amazon Bedrock provider for multi-agent reviews (Nova models)
#
# This provider implements the review interface for Amazon Nova models via Bedrock.
# Uses Amazon Nova Pro by default for code review tasks.
#
# Note: Amazon Nova Act is a separate service for browser automation and is not
# suitable for code review. This provider uses Amazon Nova foundation models
# (Pro, Lite, Micro) which are designed for text generation tasks.
#
# Environment:
#   AWS_ACCESS_KEY_ID       Required (or configured via AWS CLI profile)
#   AWS_SECRET_ACCESS_KEY   Required (or configured via AWS CLI profile)
#   AWS_SESSION_TOKEN       Optional. For temporary credentials
#   AWS_REGION              Optional. AWS region (default: us-east-1)
#   BEDROCK_MODEL           Optional. Model to use (default: us.amazon.nova-pro-v1:0)
#
# Available Nova models:
#   us.amazon.nova-pro-v1:0   - Most capable, best for complex code review
#   us.amazon.nova-lite-v1:0  - Faster, lower cost
#   us.amazon.nova-micro-v1:0 - Fastest, text-only
#
# Usage:
#   source bedrock.sh
#   result=$(bedrock_review "$diff" "$context")
#

# Prevent re-sourcing
if [[ -n "${BEDROCK_PROVIDER_LOADED:-}" ]]; then
    return 0
fi
BEDROCK_PROVIDER_LOADED=1

# Configuration
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
BEDROCK_MODEL="${BEDROCK_MODEL:-us.amazon.nova-pro-v1:0}"
BEDROCK_MAX_TOKENS="${BEDROCK_MAX_TOKENS:-16384}"

#
# Get provider name
#
bedrock_name() {
    echo "bedrock"
}

#
# Check if provider is properly configured
#
bedrock_check() {
    # Check if AWS CLI is available (preferred method)
    if command -v aws >/dev/null 2>&1; then
        # Check if credentials are configured (via env vars or profile)
        if aws sts get-caller-identity >/dev/null 2>&1; then
            echo "true"
            return 0
        fi
    fi

    # Fallback: check for explicit env vars
    if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] && [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        echo "true"
        return 0
    fi

    echo "false"
    return 1
}

#
# Execute review using Amazon Nova via Bedrock
#
bedrock_review() {
    local diff="$1"
    local context="${2:-\{\}}"

    # Validate credentials
    if [[ $(bedrock_check) != "true" ]]; then
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "issues": [],
    "summary": "AWS credentials not configured",
    "error": "AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY not set or AWS CLI not authenticated",
    "model": "$BEDROCK_MODEL"
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

    # Escape for JSON using jq
    local escaped_message
    escaped_message=$(printf '%s' "$full_message" | jq -Rs '.')

    # Build request body for Bedrock Invoke API (Nova format)
    # Nova uses the messages array format similar to other providers
    local request_body
    request_body=$(cat <<EOF
{
    "messages": [
        {
            "role": "user",
            "content": [{"text": ${escaped_message}}]
        }
    ],
    "system": [
        {"text": "You are an expert code reviewer. Always respond with valid JSON containing verdict, confidence, issues array, and summary fields."}
    ],
    "inferenceConfig": {
        "maxTokens": $BEDROCK_MAX_TOKENS,
        "temperature": 0.3,
        "topP": 0.9
    }
}
EOF
)

    # Create temp files for request/response in a subshell-safe way
    local temp_dir
    temp_dir=$(mktemp -d)
    local request_file="$temp_dir/request.json"
    local response_file="$temp_dir/response.json"

    # Cleanup helper - removes temp dir only
    _bedrock_cleanup() {
        rm -rf "$temp_dir" 2>/dev/null || true
    }

    printf '%s' "$request_body" > "$request_file"

    # Make API call via AWS CLI (handles authentication automatically)
    local response
    local aws_exit_code
    local aws_error=""
    local error_file="$temp_dir/error.txt"

    if command -v aws >/dev/null 2>&1; then
        # Capture stderr to show meaningful error messages (auth failures, model access, etc.)
        # Redirect stdout to /dev/null since AWS CLI outputs metadata there
        # The actual response is written to the output file
        aws bedrock-runtime invoke-model \
            --model-id "$BEDROCK_MODEL" \
            --region "$AWS_REGION" \
            --body "file://$request_file" \
            --cli-binary-format raw-in-base64-out \
            --content-type "application/json" \
            --accept "application/json" \
            "$response_file" 2>"$error_file" >/dev/null
        aws_exit_code=$?

        if [[ $aws_exit_code -eq 0 ]] && [[ -f "$response_file" ]]; then
            response=$(cat "$response_file")
        else
            response=""
            # Capture error message for user feedback
            if [[ -f "$error_file" ]]; then
                aws_error=$(cat "$error_file" | head -c 500 | tr '\n' ' ')
            fi
        fi
    else
        # AWS CLI not available
        response=""
        aws_exit_code=127
        aws_error="AWS CLI not installed. Install with: brew install awscli (macOS) or apt install awscli (Linux)"
    fi

    # Note: temp_dir cleanup handled by _bedrock_cleanup calls before each return

    if [[ $aws_exit_code -ne 0 ]] || [[ -z "$response" ]]; then
        # Escape error message for JSON
        local escaped_error
        escaped_error=$(printf '%s' "$aws_error" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n')
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "issues": [],
    "summary": "API request failed: ${escaped_error:0:100}",
    "error": "AWS Bedrock API call failed (exit code $aws_exit_code): $escaped_error",
    "model": "$BEDROCK_MODEL"
}
EOF
        _bedrock_cleanup
        return 1
    fi

    # Check for API errors
    local error_message
    error_message=$(printf '%s' "$response" | jq -r '.error.message // empty' 2>/dev/null)

    if [[ -n "$error_message" ]]; then
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "issues": [],
    "summary": "API error: $error_message",
    "error": "$error_message",
    "model": "$BEDROCK_MODEL"
}
EOF
        _bedrock_cleanup
        return 1
    fi

    # Extract the response content from Nova format
    # Nova returns: {"output": {"message": {"role": "assistant", "content": [{"text": "..."}]}}, ...}
    local content
    content=$(printf '%s' "$response" | jq -r '.output.message.content[0].text // .body // empty' 2>/dev/null)

    # If response has 'body' as base64 (older format), decode it
    if [[ -z "$content" ]]; then
        local body_b64
        body_b64=$(printf '%s' "$response" | jq -r '.body // empty' 2>/dev/null)
        if [[ -n "$body_b64" ]]; then
            content=$(printf '%s' "$body_b64" | base64 -d 2>/dev/null | jq -r '.output.message.content[0].text // .completion // empty' 2>/dev/null)
        fi
    fi

    if [[ -z "$content" ]]; then
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.0,
    "issues": [],
    "summary": "Empty response from API",
    "error": "No content in API response",
    "model": "$BEDROCK_MODEL"
}
EOF
        _bedrock_cleanup
        return 1
    fi

    # Try to extract JSON from the response
    local json_result=""

    # Strategy 1: Check if raw content is valid JSON
    # Use printf '%s' instead of echo to preserve literal escape sequences like \n
    if printf '%s' "$content" | jq -e '.' >/dev/null 2>&1; then
        json_result="$content"
    fi

    # Strategy 2: Extract from markdown code block
    if [[ -z "$json_result" ]]; then
        local code_block
        code_block=$(printf '%s' "$content" | sed -n '/^```\(json\)\?$/,/^```$/p' | sed '1d;$d')
        if [[ -n "$code_block" ]] && printf '%s' "$code_block" | jq -e '.' >/dev/null 2>&1; then
            json_result="$code_block"
        fi
    fi

    # Strategy 3: Find JSON object using awk
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
        local summary
        summary=$(printf '%s' "$content" | head -c 500 | tr '\n' ' ' | sed 's/"/\\"/g')
        cat <<EOF
{
    "verdict": "abstain",
    "confidence": 0.5,
    "issues": [],
    "summary": "$summary",
    "error": "Invalid JSON response",
    "model": "$BEDROCK_MODEL"
}
EOF
        _bedrock_cleanup
        return 0
    fi

    # Add model info and return
    _bedrock_cleanup
    printf '%s' "$json_result" | jq --arg model "$BEDROCK_MODEL" '. + {model: $model}'
}

#
# Cleanup (no-op for API provider)
#
bedrock_cleanup() {
    return 0
}
