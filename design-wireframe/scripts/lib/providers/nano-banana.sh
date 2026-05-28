#!/usr/bin/env bash
#
# nano-banana.sh - Google "Nano Banana" image-generation provider
#
# Implements design/image generation via the Gemini API image models (a.k.a.
# "Nano Banana" / "Nano Banana Pro"). Reuses the Gemini API-key resolution from
# gemini.sh; the provider interface mirrors the review providers (name / check /
# cleanup) with `gemini_design()` in place of `review` for image output.
#
# IMPORTANT - values to VERIFY against the live API. TODO-016-001 captured no
# API research, so the defaults below follow the documented Gemini image API
# shape (`:generateContent` with base64 `inlineData` image parts) and are all
# overridable via environment variables. Confirm them before production use.
#
# Environment:
#   GEMINI_API_KEY / GOOGLE_API_KEY    Required (resolved via gemini.sh).
#   NANO_BANANA_MODEL                  Model id. VERIFY: exact Nano Banana Pro id.
#   NANO_BANANA_API_BASE               API base URL override.
#   NANO_BANANA_RESPONSE_MODALITIES    JSON array string. VERIFY per model.
#
# Usage:
#   source nano-banana.sh
#   gemini_design "a dark-mode fintech dashboard" out.png [reference.png ...]
#

# Prevent re-sourcing
if [[ -n "${NANO_BANANA_PROVIDER_LOADED:-}" ]]; then
    return 0
fi
NANO_BANANA_PROVIDER_LOADED=1

# Reuse Gemini API-key resolution. Source gemini.sh if not already loaded.
if ! declare -F _gemini_get_api_key >/dev/null 2>&1; then
    _NANO_BANANA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=/dev/null
    source "${_NANO_BANANA_DIR}/gemini.sh"
fi

# Configuration (all overridable; VERIFY defaults against the live API).
NANO_BANANA_API_BASE="${NANO_BANANA_API_BASE:-https://generativelanguage.googleapis.com/v1beta}"
NANO_BANANA_MODEL="${NANO_BANANA_MODEL:-gemini-2.5-flash-image}"
NANO_BANANA_RESPONSE_MODALITIES="${NANO_BANANA_RESPONSE_MODALITIES:-[\"IMAGE\"]}"

#
# Provider name
#
nano_banana_name() {
    echo "nano-banana"
}

#
# Resolve the API key (reuses gemini.sh: GEMINI_API_KEY or GOOGLE_API_KEY)
#
_nano_banana_get_api_key() {
    _gemini_get_api_key
}

#
# Check if the provider is configured
#
nano_banana_check() {
    local api_key
    api_key=$(_nano_banana_get_api_key)
    if [[ -z "$api_key" ]]; then
        echo "false"
        return 1
    fi
    echo "true"
    return 0
}

#
# Guess a MIME type from a file extension (for reference-image inputs)
#
_nano_banana_mime_type() {
    local path="${1:-}"
    case "${path,,}" in
        *.png)        echo "image/png" ;;
        *.jpg|*.jpeg) echo "image/jpeg" ;;
        *.webp)       echo "image/webp" ;;
        *.gif)        echo "image/gif" ;;
        *)            echo "application/octet-stream" ;;
    esac
}

#
# Build the generateContent request body.
# Args: prompt [reference_image_path ...]
#
_nano_banana_build_request() {
    local prompt="${1:-}"
    shift || true

    # Start with the text prompt part (jq handles all escaping).
    local parts
    parts=$(jq -n --arg text "$prompt" '[{"text": $text}]')

    # Append an inlineData part for each readable reference image.
    local ref mime data
    for ref in "$@"; do
        [[ -f "$ref" ]] || continue
        mime=$(_nano_banana_mime_type "$ref")
        data=$(base64 < "$ref" | tr -d '\n')
        parts=$(printf '%s' "$parts" | jq --arg m "$mime" --arg d "$data" \
            '. + [{"inlineData": {"mimeType": $m, "data": $d}}]')
    done

    jq -n \
        --argjson parts "$parts" \
        --argjson modalities "$NANO_BANANA_RESPONSE_MODALITIES" \
        '{contents: [{parts: $parts}], generationConfig: {responseModalities: $modalities}}'
}

#
# Response parsing helpers
#
_nano_banana_response_error() {
    printf '%s' "${1:-}" | jq -r '.error.message // empty' 2>/dev/null
}

_nano_banana_finish_reason() {
    printf '%s' "${1:-}" | jq -r '.candidates[0].finishReason // empty' 2>/dev/null
}

_nano_banana_first_image_data() {
    printf '%s' "${1:-}" | jq -r \
        '[.candidates[0].content.parts[]? | select(.inlineData != null) | .inlineData.data][0] // empty' 2>/dev/null
}

_nano_banana_first_image_mime() {
    printf '%s' "${1:-}" | jq -r \
        '[.candidates[0].content.parts[]? | select(.inlineData != null) | .inlineData.mimeType][0] // empty' 2>/dev/null
}

_nano_banana_response_text() {
    printf '%s' "${1:-}" | jq -r \
        '[.candidates[0].content.parts[]? | select(.text != null) | .text] | join("")' 2>/dev/null
}

#
# Emit a standard error object (mirrors the review providers' abstain shape)
#
_nano_banana_error_json() {
    local summary="${1:-}" error="${2:-}"
    jq -n --arg s "$summary" --arg e "$error" --arg m "$NANO_BANANA_MODEL" \
        '{verdict: "abstain", provider: "nano-banana", summary: $s, error: $e, model: $m}'
}

#
# Generate an image from a text prompt (+ optional reference images).
# Args: prompt [output_path] [reference_image_path ...]
# Writes the decoded image to output_path and prints a JSON metadata object.
#
gemini_design() {
    local prompt="${1:-}"
    local output="${2:-design-output.png}"
    local refs=()
    if [[ $# -gt 2 ]]; then
        refs=("${@:3}")
    fi

    local api_key
    api_key=$(_nano_banana_get_api_key)
    if [[ -z "$api_key" ]]; then
        _nano_banana_error_json "Nano Banana API key not configured" \
            "Neither GEMINI_API_KEY nor GOOGLE_API_KEY is set"
        return 1
    fi

    local request_body
    request_body=$(_nano_banana_build_request "$prompt" ${refs[@]+"${refs[@]}"})

    local api_url="${NANO_BANANA_API_BASE}/models/${NANO_BANANA_MODEL}:generateContent?key=${api_key}"

    local response curl_exit
    response=$(curl -s -X POST "$api_url" \
        -H "Content-Type: application/json" \
        -d "$request_body" 2>&1)
    curl_exit=$?

    if [[ $curl_exit -ne 0 ]]; then
        _nano_banana_error_json "API request failed" "curl exit code $curl_exit"
        return 1
    fi

    local err
    err=$(_nano_banana_response_error "$response")
    if [[ -n "$err" ]]; then
        _nano_banana_error_json "API error: $err" "$err"
        return 1
    fi

    local data
    data=$(_nano_banana_first_image_data "$response")
    if [[ -z "$data" ]]; then
        local reason
        reason=$(_nano_banana_finish_reason "$response")
        if [[ "$reason" == "SAFETY" ]]; then
            _nano_banana_error_json "Response blocked by safety filters" "Safety filter triggered"
        else
            _nano_banana_error_json "No image in API response" "Empty or text-only response"
        fi
        return 1
    fi

    local mime
    mime=$(_nano_banana_first_image_mime "$response")
    [[ -n "$mime" ]] || mime="image/png"

    # Decode the base64 image data to the output path.
    if ! printf '%s' "$data" | base64 -d > "$output" 2>/dev/null; then
        _nano_banana_error_json "Failed to decode image data" "base64 decode error"
        return 1
    fi

    local text
    text=$(_nano_banana_response_text "$response")

    jq -n \
        --arg provider "nano-banana" \
        --arg model "$NANO_BANANA_MODEL" \
        --arg output "$output" \
        --arg mime "$mime" \
        --arg prompt "$prompt" \
        --arg text "$text" \
        '{verdict: "ok", provider: $provider, model: $model, output: $output, mime_type: $mime, prompt: $prompt, text: $text}'
}

#
# Cleanup (no-op for an API provider)
#
nano_banana_cleanup() {
    return 0
}
