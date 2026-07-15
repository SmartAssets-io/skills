#!/usr/bin/env bash
#
# harmonize-smart-asset.sh - Smart Asset functions for harmonize-policies.sh
#
# This library provides:
# - Smart Asset repository detection
# - Smart Asset type classification
# - Smart Asset structure scaffolding
# - Smart Asset validation
#
# Usage:
#   source /path/to/lib/harmonize-smart-asset.sh
#   sa_type=$(detect_smart_asset_type "/path/to/repo")
#   harmonize_smart_asset "/path/to/repo" "$sa_type"
#

# Prevent re-sourcing
if [[ -n "${HARMONIZE_SMART_ASSET_LOADED:-}" ]]; then
    return 0
fi
HARMONIZE_SMART_ASSET_LOADED=1

# Source UI library for logging (if not already loaded)
HARMONIZE_SA_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${HARMONIZE_UI_LOADED:-}" ]]; then
    source "${HARMONIZE_SA_SCRIPT_DIR}/harmonize-ui.sh"
fi

# Smart Asset harmonization tracking
# Set by harmonize_smart_asset() function
HARMONIZE_SA_RESULT=""        # scaffolded, validated, skipped, error
declare -a HARMONIZE_SA_FILES=()

#
# Check if repository is a Smart Asset repo (has smartasset.jsonc manifest)
# A true Smart Asset repo must have a manifest file, not just a spec directory.
# This distinguishes actual Smart Assets from repos that only contain SA documentation.
#
# Arguments:
#   $1 - Repository path
#
# Returns:
#   0 if has smartasset.jsonc (at root or in docs/SmartAssetSpec/)
#   1 otherwise
#
is_smart_asset_repo() {
    local repo_path="$1"
    # Check for manifest at root level or in spec directory
    [[ -f "$repo_path/smartasset.jsonc" ]] || [[ -f "$repo_path/docs/SmartAssetSpec/smartasset.jsonc" ]]
}

#
# Check if repository is a root-level Smart Asset repo
# Root Smart Asset repos have smartasset.jsonc at the root level
#
# Arguments:
#   $1 - Repository path
#
# Returns:
#   0 if has smartasset.jsonc at root
#   1 otherwise
#
is_smart_asset_root_repo() {
    local repo_path="$1"
    [[ -f "$repo_path/smartasset.jsonc" ]]
}

#
# Check if repository should be scaffolded as a Smart Asset
# Detection criteria:
#   1. Has .smart-asset marker file (explicit opt-in)
#   2. Repository name contains "SmartAsset" or "smart-asset"
#
# Arguments:
#   $1 - Repository path
#
# Returns:
#   0 if should scaffold Smart Asset structure
#   1 otherwise
#
should_scaffold_smart_asset() {
    local repo_path="$1"
    local repo_name
    repo_name=$(basename "$repo_path")

    # Check for explicit marker file
    if [[ -f "$repo_path/.smart-asset" ]]; then
        return 0
    fi

    # Check if name contains SmartAsset (case-insensitive)
    if [[ "${repo_name,,}" == *"smartasset"* ]] || [[ "${repo_name,,}" == *"smart-asset"* ]]; then
        return 0
    fi

    return 1
}

#
# Detect the type of Smart Asset repository
# Returns a classification for how harmonize should handle the repo
#
# Arguments:
#   $1 - Repository path
#
# Output (to stdout):
#   "spec"      - Has smartasset.jsonc in docs/SmartAssetSpec/ only
#   "root"      - Has smartasset.jsonc at root only
#   "hybrid"    - Has both root manifest and spec manifest
#   "candidate" - Should be scaffolded (name match or marker, but no SA manifest yet)
#   "none"      - Not a Smart Asset repository
#
# Returns:
#   0 always (check stdout for classification)
#
detect_smart_asset_type() {
    local repo_path="$1"
    local has_spec_manifest=false
    local has_root_manifest=false
    local should_scaffold=false

    # Check for manifest in spec directory
    if [[ -f "$repo_path/docs/SmartAssetSpec/smartasset.jsonc" ]]; then
        has_spec_manifest=true
    fi

    # Check for root manifest
    if [[ -f "$repo_path/smartasset.jsonc" ]]; then
        has_root_manifest=true
    fi

    # Check if should scaffold (only if no manifests exist)
    if ! $has_spec_manifest && ! $has_root_manifest; then
        if should_scaffold_smart_asset "$repo_path"; then
            should_scaffold=true
        fi
    fi

    # Determine classification
    if $has_spec_manifest && $has_root_manifest; then
        echo "hybrid"
    elif $has_root_manifest; then
        echo "root"
    elif $has_spec_manifest; then
        echo "spec"
    elif $should_scaffold; then
        echo "candidate"
    else
        echo "none"
    fi

    return 0
}

#
# Harmonize Smart Asset structure for a repository
# Validates existing SA repos and scaffolds missing structure for candidates
#
# Arguments:
#   $1 - Repository path
#   $2 - SA type (from detect_smart_asset_type): spec, root, hybrid, candidate
#
# Global variables required:
#   SOURCE_PATH - Path to source templates
#   DRY_RUN - true/false for dry-run mode
#   SCRIPT_DIR - Path to main script directory (for validator)
#
# Returns:
#   0 on success (or no action needed)
#   1 on error
#
# Output:
#   Sets HARMONIZE_SA_RESULT to: scaffolded, validated, skipped, error
#   Sets HARMONIZE_SA_FILES array with created/updated files
#
harmonize_smart_asset() {
    local repo_path="$1"
    local sa_type="$2"
    local repo_name
    repo_name=$(basename "$repo_path")

    # Reset result variables
    HARMONIZE_SA_RESULT="skipped"
    HARMONIZE_SA_FILES=()

    # Determine target directory based on SA type
    # - root/hybrid: Smart Asset files at repo root
    # - spec: Smart Asset files in docs/SmartAssetSpec/
    # - candidate: Default to docs/SmartAssetSpec/ for app repos
    local sa_dir=""
    case "$sa_type" in
        root|hybrid)
            sa_dir="$repo_path"
            ;;
        spec)
            sa_dir="$repo_path/docs/SmartAssetSpec"
            ;;
        candidate)
            # For candidate repos (like SwellSmartAsset), use docs/SmartAssetSpec/
            sa_dir="$repo_path/docs/SmartAssetSpec"
            ;;
        none|*)
            # Not a Smart Asset repo - nothing to do
            return 0
            ;;
    esac

    # For existing SA repos (spec, root, hybrid), validate structure
    if [[ "$sa_type" != "candidate" ]]; then
        _validate_smart_asset "$repo_path" "$sa_dir"
        return 0
    fi

    # For candidate repos, scaffold missing structure
    _scaffold_smart_asset "$repo_path" "$sa_dir" "$repo_name"
}

#
# Internal: Validate an existing Smart Asset structure
#
_validate_smart_asset() {
    local repo_path="$1"
    local sa_dir="$2"

    if [[ -x "${SCRIPT_DIR:-}/validate-smart-asset.sh" ]]; then
        local validation_result
        validation_result=$("${SCRIPT_DIR}/validate-smart-asset.sh" --quiet --json "$sa_dir" 2>/dev/null) || true

        if [[ -n "$validation_result" ]]; then
            local error_count warning_count pass_count
            error_count=$(echo "$validation_result" | jq -r '.errors // 0' 2>/dev/null || echo "0")
            warning_count=$(echo "$validation_result" | jq -r '.warnings // 0' 2>/dev/null || echo "0")
            pass_count=$(echo "$validation_result" | jq -r '.passes // 0' 2>/dev/null || echo "0")

            HARMONIZE_SA_RESULT="validated"
            if [[ "$error_count" -gt 0 ]]; then
                log_action "SA_WARN" "Smart Asset validation: $error_count errors, $warning_count warnings"
            elif [[ "$warning_count" -gt 0 ]]; then
                log_action "SA_OK" "Smart Asset validated ($pass_count passes, $warning_count warnings)"
            else
                log_action "SA_OK" "Smart Asset valid ($pass_count checks passed)"
            fi
        else
            # Validation script ran but returned no output
            HARMONIZE_SA_RESULT="validated"
            log_action "SA_OK" "Smart Asset structure present"
        fi
    else
        # No validation script available
        log_action "SA_OK" "Smart Asset structure detected (validator not available)"
    fi
}

#
# Internal: Scaffold Smart Asset structure for candidate repos
#
_scaffold_smart_asset() {
    local repo_path="$1"
    local sa_dir="$2"
    local repo_name="$3"

    # Extract asset name from repo name (remove "SmartAsset" suffix/prefix patterns)
    local asset_name="$repo_name"
    asset_name="${asset_name//SmartAsset/}"
    asset_name="${asset_name//smart-asset/}"
    asset_name="${asset_name//-/}"
    asset_name="${asset_name//_/}"
    # If asset name is empty after cleaning, use repo name
    [[ -z "$asset_name" ]] && asset_name="$repo_name"

    # Template variables for substitution
    local asset_type="primitive"
    local description="Smart Asset for $repo_name"

    # Check if template directory exists
    local template_dir="${SOURCE_PATH:-}/docs/templates"
    if [[ ! -d "$template_dir" ]]; then
        log_warning "Template directory not found: $template_dir"
        HARMONIZE_SA_RESULT="error"
        return 1
    fi

    # Create directory structure
    local dirs_to_create=(
        "$sa_dir"
        "$sa_dir/schema"
        "$sa_dir/ai"
        "$sa_dir/icons"
        "$sa_dir/docs"
    )

    for dir in "${dirs_to_create[@]}"; do
        if [[ ! -d "$dir" ]]; then
            if [[ "${DRY_RUN:-false}" == true ]]; then
                log_action "SA_CREATE" "Directory: ${dir#$repo_path/}"
            else
                mkdir -p "$dir"
                HARMONIZE_SA_FILES+=("${dir#$repo_path/}/")
            fi
        fi
    done

    # Scaffold files with template substitution
    local files_to_scaffold=(
        "smartasset.jsonc.template:smartasset.jsonc"
        "value-flows.jsonc.template:schema/value-flows.jsonc"
        "behavior.md.template:ai/behavior.md"
    )

    for file_spec in "${files_to_scaffold[@]}"; do
        local template_file="${file_spec%%:*}"
        local target_rel="${file_spec##*:}"
        local source_path="$template_dir/$template_file"
        local target_path="$sa_dir/$target_rel"

        # Skip if template doesn't exist
        if [[ ! -f "$source_path" ]]; then
            continue
        fi

        # Skip if target already exists
        if [[ -f "$target_path" ]]; then
            log_action "SA_OK" "$target_rel (exists)"
            continue
        fi

        if [[ "${DRY_RUN:-false}" == true ]]; then
            log_action "SA_CREATE" "$target_rel (would scaffold)"
        else
            # Perform template substitution
            if command -v envsubst &>/dev/null; then
                ASSET_NAME="$asset_name" \
                ASSET_TYPE="$asset_type" \
                DESCRIPTION="$description" \
                envsubst '${ASSET_NAME} ${ASSET_TYPE} ${DESCRIPTION}' < "$source_path" > "$target_path"
            else
                # Fallback: sed-based substitution when envsubst not available
                sed -e "s/\${ASSET_NAME}/$asset_name/g" \
                    -e "s/\${ASSET_TYPE}/$asset_type/g" \
                    -e "s/\${DESCRIPTION}/$description/g" \
                    "$source_path" > "$target_path"
            fi

            if [[ -f "$target_path" ]]; then
                HARMONIZE_SA_FILES+=("${target_path#$repo_path/}")
                log_action "SA_CREATE" "$target_rel"
            else
                log_action "SA_ERROR" "Failed to create $target_rel"
            fi
        fi
    done

    # Create a basic README in docs/ if missing
    _create_sa_readme "$repo_path" "$sa_dir" "$asset_name"

    if [[ ${#HARMONIZE_SA_FILES[@]} -gt 0 ]]; then
        HARMONIZE_SA_RESULT="scaffolded"
    else
        HARMONIZE_SA_RESULT="skipped"
    fi

    return 0
}

#
# Internal: Create Smart Asset README
#
_create_sa_readme() {
    local repo_path="$1"
    local sa_dir="$2"
    local asset_name="$3"
    local readme_path="$sa_dir/docs/README.md"

    if [[ ! -f "$readme_path" ]]; then
        if [[ "${DRY_RUN:-false}" == true ]]; then
            log_action "SA_CREATE" "docs/README.md (would create)"
        else
            cat > "$readme_path" << EOF
# $asset_name Smart Asset Documentation

This directory contains documentation for the $asset_name Smart Asset.

## Structure

- \`../smartasset.jsonc\` - Smart Asset manifest
- \`../schema/value-flows.jsonc\` - Value flow definitions
- \`../ai/behavior.md\` - AI behavior specification
- \`../icons/\` - Asset icons

## Getting Started

See the main project README for development setup.
EOF
            HARMONIZE_SA_FILES+=("${readme_path#$repo_path/}")
            log_action "SA_CREATE" "docs/README.md"
        fi
    fi
}
