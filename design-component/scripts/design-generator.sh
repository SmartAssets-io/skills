#!/usr/bin/env bash
#
# design-generator.sh - Generate Smart Assets designs from natural language.
#
# A generic engine over the design prompt templates (docs/brand/prompt-templates/)
# and design tokens (docs/brand/tokens/design-prompt.yaml). It:
#   1. loads a template and its frontmatter `variables` contract,
#   2. fills token-sourced variables from design-prompt.yaml (rendered as
#      readable key: value lines) and user-sourced variables from the CLI,
#   3. substitutes {{VAR}} placeholders in the template body,
#   4. calls gemini_design() (nano-banana.sh provider) to render an image,
#   5. saves the image plus a sidecar <output>.json metadata file.
#
# Iteration is minimal pass-through: --reference <image> is forwarded to the
# provider. The richer conversational refinement loop is TODO-016-007.
#
# Usage:
#   design-generator.sh <template> [options]
#
# Options:
#   --description TEXT     value for the {{DESCRIPTION}} variable
#   --var NAME=VALUE       set/override any template variable (repeatable)
#   --theme dark|light     theme subtree used for {{THEME}} (default: dark)
#   --reference IMAGE      reference image forwarded to the provider (repeatable)
#   --output PATH          output image path (default: design-output/<template>-<ts>.png)
#   --templates-dir DIR    template directory (default: docs/brand/prompt-templates)
#   --tokens FILE          tokens file (default: docs/brand/tokens/design-prompt.yaml)
#   --dry-run              build and print the resolved prompt; skip the API call
#   -h, --help             show this help
#
# Environment: GEMINI_API_KEY / GOOGLE_API_KEY required for live generation.
#

set -uo pipefail

DG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DG_REPO_ROOT="$(cd "$DG_SCRIPT_DIR/../.." && pwd)"

# Defaults (overridable via flags)
DG_TEMPLATES_DIR_DEFAULT="$DG_REPO_ROOT/docs/brand/prompt-templates"
DG_TOKENS_DEFAULT="$DG_REPO_ROOT/docs/brand/tokens/design-prompt.yaml"

# Source the image provider (also pulls in gemini.sh for key resolution).
# shellcheck source=/dev/null
source "$DG_SCRIPT_DIR/lib/providers/nano-banana.sh"

dg_usage() {
    sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Resolve a template name to a file, tolerating - / _ differences.
dg_resolve_template_file() {
    local name="$1" dir="$2"
    local candidates=("$name" "${name//_/-}" "${name//-/_}")
    local c
    for c in "${candidates[@]}"; do
        if [[ -f "$dir/$c.md" ]]; then
            echo "$dir/$c.md"
            return 0
        fi
    done
    return 1
}

# Run python3 with PyYAML available, portably across macOS and Linux. Prefers a
# python3 that already has the yaml module; otherwise falls back to
# `uv run --with pyyaml` (ephemeral env, no global / --break-system-packages
# install). Mirrors the convention in sync-skills-to-github.sh.
py_yaml() {
    if python3 -c "import yaml" 2>/dev/null; then
        python3 "$@"
    elif command -v uv >/dev/null 2>&1; then
        uv run -q --with pyyaml python3 "$@"
    else
        echo "design-generator: pyyaml is required (install pyyaml, or install uv for an automatic ephemeral environment)" >&2
        return 3
    fi
}

# Build the resolved prompt by substituting variables in the template body.
# Delegates frontmatter parsing, token rendering, and substitution to python3
# (via py_yaml for portable PyYAML resolution).
# Stdout: the resolved prompt. Exit 2 if required user variables are missing.
dg_build_prompt() {
    local template_file="$1" tokens_file="$2" theme="$3" user_vars_json="$4"
    TEMPLATE_FILE="$template_file" TOKENS_FILE="$tokens_file" \
    DG_THEME="$theme" USER_VARS="$user_vars_json" py_yaml - <<'PY'
import os, re, sys
try:
    import yaml
except ImportError:
    sys.stderr.write("design-generator: pyyaml is required\n")
    sys.exit(3)
import json

template_file = os.environ["TEMPLATE_FILE"]
tokens_file = os.environ["TOKENS_FILE"]
theme = os.environ.get("DG_THEME", "dark")
user_vars = json.loads(os.environ.get("USER_VARS", "{}"))

text = open(template_file).read()
m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
if not m:
    sys.stderr.write("design-generator: template missing frontmatter\n")
    sys.exit(4)
fm = yaml.safe_load(m.group(1)) or {}
body = m.group(2)
variables = fm.get("variables") or {}

tokens = yaml.safe_load(open(tokens_file))

def resolve_path(path):
    cur = tokens
    for part in path.split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return None
    return cur

def render(node, indent=0):
    pad = "  " * indent
    if isinstance(node, dict):
        out = []
        for k, v in node.items():
            if isinstance(v, (dict, list)):
                out.append(f"{pad}{k}:")
                out.append(render(v, indent + 1))
            else:
                out.append(f"{pad}{k}: {v}")
        return "\n".join(out)
    if isinstance(node, list):
        out = []
        for item in node:
            if isinstance(item, (dict, list)):
                out.append(render(item, indent + 1))
            else:
                out.append(f"{pad}- {item}")
        return "\n".join(out)
    return f"{pad}{node}".rstrip()

resolved = {}
missing = []
for var, src in variables.items():
    s = str(src)
    if s.startswith("design-prompt.yaml:"):
        path = s.split(":", 1)[1].strip().split(" ")[0]
        parts = path.split(".")
        if parts[0] == "theme" and len(parts) > 1:
            parts[1] = theme  # honor --theme override
            path = ".".join(parts)
        node = resolve_path(path)
        if node is None:
            sys.stderr.write(f"design-generator: token path not found: {path}\n")
            sys.exit(5)
        resolved[var] = render(node).strip()
    else:
        if var in user_vars and user_vars[var] != "":
            resolved[var] = user_vars[var]
        else:
            missing.append(var)

if missing:
    sys.stderr.write("design-generator: missing required variables: "
                     + ", ".join(sorted(missing)) + "\n")
    sys.exit(2)

def sub(match):
    return resolved.get(match.group(1), match.group(0))

print(re.sub(r"\{\{([A-Z_]+)\}\}", sub, body).rstrip())
PY
}

# Orchestrate generation: build prompt, call provider, save image + metadata.
dg_generate() {
    local template="$1" template_file="$2" tokens_file="$3" theme="$4"
    local output="$5" user_vars_json="$6"
    shift 6
    local refs=("$@")

    local prompt rc
    prompt=$(dg_build_prompt "$template_file" "$tokens_file" "$theme" "$user_vars_json")
    rc=$?
    if [[ $rc -ne 0 ]]; then
        return $rc
    fi

    mkdir -p "$(dirname "$output")"

    local metadata
    metadata=$(gemini_design "$prompt" "$output" ${refs[@]+"${refs[@]}"})
    local gd_rc=$?

    local verdict
    verdict=$(printf '%s' "$metadata" | jq -r '.verdict // "abstain"' 2>/dev/null)
    if [[ "$gd_rc" -ne 0 || "$verdict" != "ok" ]]; then
        echo "design-generator: generation failed" >&2
        printf '%s\n' "$metadata" >&2
        return 1
    fi

    # Write sidecar metadata (provider JSON + template/timestamp/prompt).
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    printf '%s' "$metadata" | jq \
        --arg template "$template" \
        --arg generated_at "$ts" \
        --arg template_file "$template_file" \
        --arg prompt "$prompt" \
        '. + {template: $template, generated_at: $generated_at, template_file: $template_file, resolved_prompt: $prompt}' \
        > "${output}.json"

    echo "Saved: $output"
    echo "Metadata: ${output}.json"
    printf '%s\n' "$metadata"
}

main() {
    local template="" theme="dark" output="" dry_run="false"
    local templates_dir="$DG_TEMPLATES_DIR_DEFAULT"
    local tokens_file="$DG_TOKENS_DEFAULT"
    local user_vars='{}'
    local refs=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) dg_usage; return 0 ;;
            --description) user_vars=$(jq --arg v "${2:-}" '. + {DESCRIPTION: $v}' <<<"$user_vars"); shift 2 ;;
            --var)
                local pair="${2:-}" k v
                k="${pair%%=*}"; v="${pair#*=}"
                user_vars=$(jq --arg k "$k" --arg v "$v" '. + {($k): $v}' <<<"$user_vars")
                shift 2 ;;
            --theme) theme="${2:-dark}"; shift 2 ;;
            --reference) refs+=("${2:-}"); shift 2 ;;
            --output) output="${2:-}"; shift 2 ;;
            --templates-dir) templates_dir="${2:-}"; shift 2 ;;
            --tokens) tokens_file="${2:-}"; shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            -*) echo "design-generator: unknown option: $1" >&2; return 64 ;;
            *)
                if [[ -z "$template" ]]; then template="$1"; else
                    echo "design-generator: unexpected argument: $1" >&2; return 64
                fi
                shift ;;
        esac
    done

    if [[ -z "$template" ]]; then
        echo "design-generator: a template name is required (e.g. wireframe)" >&2
        dg_usage
        return 64
    fi

    local template_file
    if ! template_file=$(dg_resolve_template_file "$template" "$templates_dir"); then
        echo "design-generator: template not found: $template (in $templates_dir)" >&2
        return 66
    fi

    if [[ ! -f "$tokens_file" ]]; then
        echo "design-generator: tokens file not found: $tokens_file" >&2
        return 66
    fi

    if [[ "$dry_run" == "true" ]]; then
        local prompt rc
        prompt=$(dg_build_prompt "$template_file" "$tokens_file" "$theme" "$user_vars")
        rc=$?
        if [[ $rc -ne 0 ]]; then return $rc; fi
        echo "# template: $template ($template_file)"
        echo "# theme: $theme"
        echo "# --- resolved prompt ---"
        printf '%s\n' "$prompt"
        return 0
    fi

    if [[ -z "$output" ]]; then
        output="design-output/${template}-$(date -u +%Y%m%dT%H%M%SZ).png"
    fi

    dg_generate "$template" "$template_file" "$tokens_file" "$theme" \
        "$output" "$user_vars" ${refs[@]+"${refs[@]}"}
}

# Only run main when executed directly (allows sourcing in tests).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
