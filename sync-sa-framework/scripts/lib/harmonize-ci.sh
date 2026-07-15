#!/usr/bin/env bash
#
# harmonize-ci.sh - CI configuration harmonization for harmonize-policies.sh
#
# Propagates canonical CI checks into repositories that already run CI.
# Currently handles the markdown link check (lychee); see
# docs/common/markdown-link-check-standard.md.
#
# Usage:
#   source /path/to/lib/harmonize-ci.sh
#   # Called internally by process_repository()
#

# Prevent re-sourcing
if [[ -n "${HARMONIZE_CI_LOADED:-}" ]]; then
    return 0
fi
HARMONIZE_CI_LOADED=1

# Source required libraries (if not already loaded)
HARMONIZE_CI_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "${HARMONIZE_UI_LOADED:-}" ]] && source "${HARMONIZE_CI_SCRIPT_DIR}/harmonize-ui.sh"

#
# YAML parsing helper: PyYAML via python3, uv fallback. Returns 127 when no
# parser is available so callers can fall back to text heuristics.
#
_harmonize_ci_py_yaml() {
    if python3 -c "import yaml" 2>/dev/null; then
        python3 "$@"
    elif command -v uv >/dev/null 2>&1; then
        uv run --with pyyaml python3 "$@" 2>/dev/null
    else
        return 127
    fi
}

#
# Resolve the GitLab CI stage for an appended job
#
# Rules (per docs/common/markdown-link-check-standard.md):
#   - no stages: list declared        -> test (GitLab default stage)
#   - test among declared stages     -> test
#   - otherwise                      -> first declared stage
#
# Parses with PyYAML when available (handles comments, anchors, quoting,
# and GitLab custom tags like !reference); falls back to text heuristics
# covering plain inline/block lists only. Unparseable YAML resolves
# conservatively to test rather than trusting a heuristic guess.
#
# Arguments:
#   $1 - Path to .gitlab-ci.yml
#
# Output:
#   Stage name on stdout
#
resolve_gitlab_stage() {
    local ci_file="$1"
    local stages="" parser_rc=0

    stages=$(_harmonize_ci_py_yaml - "$ci_file" <<'PYEOF'
import sys
import yaml


class GitLabLoader(yaml.SafeLoader):
    pass


# GitLab CI uses custom tags (e.g. !reference). SafeLoader would reject
# them; this catch-all maps any unknown tag (including !!python/*) to None
# without constructing objects, keeping safe_load semantics.
GitLabLoader.add_multi_constructor("", lambda loader, suffix, node: None)

try:
    with open(sys.argv[1]) as fh:
        doc = yaml.load(fh, Loader=GitLabLoader) or {}
except Exception:
    sys.exit(2)

stages = doc.get("stages") if isinstance(doc, dict) else None
if isinstance(stages, list):
    for stage in stages:
        if isinstance(stage, str) and stage.strip():
            print(stage.strip())
PYEOF
    ) || parser_rc=$?

    if [[ $parser_rc -eq 127 ]]; then
        # No YAML parser available - documented-subset text heuristics
        # Inline flow style: stages: [build, test, deploy]
        local inline
        inline=$(grep -m1 -E '^stages:[ \t]*\[' "$ci_file" 2>/dev/null || true)
        if [[ -n "$inline" ]]; then
            stages=$(echo "$inline" | sed -e 's/^stages:[ \t]*\[//' -e 's/\].*$//' \
                | tr ',' '\n' | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//' -e "s/[\"']//g" \
                | grep -v '^$' || true)
        else
            stages=$(awk '
            /^stages:/ { in_stages=1; next }
            in_stages && /^[^ \t#-]/ { in_stages=0 }
            in_stages && /^[ \t]*-[ \t]*/ {
                line=$0
                sub(/^[ \t]*-[ \t]*/, "", line)
                sub(/[ \t#].*$/, "", line)
                gsub(/["'\''"]/, "", line)
                if (line != "") print line
            }
            ' "$ci_file")
        fi
    elif [[ $parser_rc -ne 0 ]]; then
        # Unparseable YAML: do not trust heuristics on a file a real parser
        # rejects; use the GitLab default stage
        echo "test"
        return 0
    fi

    if [[ -z "$stages" ]] || grep -qx 'test' <<< "$stages"; then
        echo "test"
    else
        head -n 1 <<< "$stages"
    fi
}

#
# Process markdown link check: propagate the canonical lychee CI check
#
# Applies only to repositories that already have a CI configuration
# (.gitlab-ci.yml or .github/workflows/); never scaffolds CI from
# scratch. Repositories whose CI already runs lychee (any job name)
# are left untouched to preserve local customizations.
#
# Standard: docs/common/markdown-link-check-standard.md
#
# Arguments:
#   $1 - Repository path
#   $2 - Relative path for display
#   $3 - Name reference for repo_created flag
#   $4 - Name reference for repo_updated flag
#   $5 - Name reference for repo_error flag
#
# Global variables used:
#   SOURCE_PATH, DRY_RUN, CREATED_FILES
#
process_markdown_link_check() {
    local repo_path="$1" rel_path="$2"
    local -n _mlc_created=$3
    local -n _mlc_updated=$4
    local -n _mlc_error=$5

    local gitlab_ci="$repo_path/.gitlab-ci.yml"
    local gh_workflows="$repo_path/.github/workflows"
    local gitlab_template="${SOURCE_PATH}/docs/templates/markdown-link-check.gitlab-ci.yml.template"
    local gh_template="${SOURCE_PATH}/docs/templates/markdown-link-check.github-workflow.yml.template"

    # Standard applies only to repos that already run CI
    [[ ! -f "$gitlab_ci" && ! -d "$gh_workflows" ]] && return

    local detect_re='lychee|markdown[-_]?link[-_]?check'

    # GitLab CI: append canonical job to the existing pipeline
    if [[ -f "$gitlab_ci" && -f "$gitlab_template" ]]; then
        if grep -qiE "$detect_re" "$gitlab_ci"; then
            log_action "OK" ".gitlab-ci.yml (markdown link check present)"
        else
            local stage
            stage=$(resolve_gitlab_stage "$gitlab_ci")
            if [[ "${DRY_RUN:-false}" == true ]]; then
                log_action "UPDATE" ".gitlab-ci.yml (would append markdown-link-check job, stage: $stage)"
            else
                log_action "UPDATE" ".gitlab-ci.yml (appending markdown-link-check job, stage: $stage)"
                if prompt_action "Append markdown-link-check job to .gitlab-ci.yml"; then
                    if { echo ""; sed "s/{{STAGE}}/$stage/" "$gitlab_template"; } >> "$gitlab_ci"; then
                        _mlc_updated=true
                    else
                        log_action "ERROR" "Failed to append markdown-link-check job"
                        _mlc_error=true
                    fi
                else
                    log_action "SKIP" ".gitlab-ci.yml (user skipped)"
                fi
            fi
        fi
    fi

    # GitHub Actions: create standalone workflow
    if [[ -d "$gh_workflows" && -f "$gh_template" ]]; then
        if grep -rqiE "$detect_re" "$gh_workflows" 2>/dev/null; then
            log_action "OK" ".github/workflows (markdown link check present)"
        else
            if [[ "${DRY_RUN:-false}" == true ]]; then
                log_action "CREATE" ".github/workflows/markdown-link-check.yml (would create from template)"
            else
                log_action "CREATE" ".github/workflows/markdown-link-check.yml (from template)"
                if prompt_action "Create .github/workflows/markdown-link-check.yml"; then
                    if cp "$gh_template" "$gh_workflows/markdown-link-check.yml"; then
                        _mlc_created=true
                        CREATED_FILES+=("$rel_path/.github/workflows/markdown-link-check.yml")
                    else
                        log_action "ERROR" "Failed to create markdown-link-check.yml"
                        _mlc_error=true
                    fi
                else
                    log_action "SKIP" ".github/workflows/markdown-link-check.yml (user skipped)"
                fi
            fi
        fi
    fi
}
