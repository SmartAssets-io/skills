#!/usr/bin/env bash
#
# harmonize-derive.sh - AGENTS.md derivation for harmonize-policies.sh
#
# This library provides:
# - Derivation of AGENTS.md from CLAUDE.md
# - Section extraction and condensation
#
# Usage:
#   source /path/to/lib/harmonize-derive.sh
#   derive_agents_md "/path/to/CLAUDE.md" "/path/to/AGENTS.md"
#

# Prevent re-sourcing
if [[ -n "${HARMONIZE_DERIVE_LOADED:-}" ]]; then
    return 0
fi
HARMONIZE_DERIVE_LOADED=1

#
# Derive AGENTS.md from CLAUDE.md
# Extracts and condenses key sections for other AI tools
#
# Arguments:
#   $1 - Path to CLAUDE.md (source)
#   $2 - Path to AGENTS.md (destination)
#
derive_agents_md() {
    local claude_file="$1"
    local agents_file="$2"

    # Extract project name from first heading
    local project_name
    project_name=$(grep -m1 '^# ' "$claude_file" | sed 's/^# //')

    # Create AGENTS.md header
    cat > "$agents_file" << EOF
# ${project_name}

AI assistant guidance for ${project_name}. This file follows the Agentic AI Foundation (Linux Foundation) standard for AI coding assistants.

**Full documentation:** See [CLAUDE.md](CLAUDE.md) for comprehensive project guidelines.

EOF

    # Extract and append key sections from CLAUDE.md
    # Sections to extract: Project Overview/Context, Git Interaction, Attribution Policy,
    # Code Style, Security, Stigmergic Collaboration
    local in_section=false
    local in_code_block=false
    local current_section=""
    local section_content=""
    local sections_to_extract="Project Overview|Project Context|Git Interaction|Attribution Policy|Code Style|Security|Stigmergic Collaboration|Development Modes|Slash Commands"

    # Sections where ### subsections should be included (not stripped)
    local sections_with_subsections="Slash Commands|Development Modes"

    while IFS= read -r line; do
        # Track fenced code blocks to skip header detection inside them
        # Check for lines starting with ``` or ~~~ (with optional leading whitespace)
        if echo "$line" | grep -qE '^[[:space:]]*(```|~~~)'; then
            if [[ "$in_code_block" == true ]]; then
                in_code_block=false
            else
                in_code_block=true
            fi
            # If in a section, include the code fence in content
            if [[ "$in_section" == true ]]; then
                section_content="${section_content}${line}"$'\n'
            fi
            continue
        fi

        # Skip header detection while inside code blocks
        if [[ "$in_code_block" == true ]]; then
            if [[ "$in_section" == true ]]; then
                section_content="${section_content}${line}"$'\n'
            fi
            continue
        fi

        # Check for section headers (## level) - only when not in code block
        if [[ "$line" =~ ^##[[:space:]]+ ]]; then
            # Save previous section if it was one we wanted
            if [[ "$in_section" == true && -n "$section_content" ]]; then
                printf '%s\n' "## ${current_section}" >> "$agents_file"
                printf '%s' "$section_content" >> "$agents_file"
            fi

            # Check if this is a section we want
            local section_title="${line#\#\# }"
            if echo "$section_title" | grep -qE "($sections_to_extract)"; then
                in_section=true
                current_section="$section_title"
                section_content=""
            else
                in_section=false
                current_section=""
                section_content=""
            fi
        elif [[ "$in_section" == true ]]; then
            # Check for next section at same or higher level
            if [[ "$line" =~ ^##[[:space:]] ]] || [[ "$line" =~ ^#[[:space:]] ]]; then
                # End of current section
                if [[ -n "$section_content" ]]; then
                    printf '%s\n' "## ${current_section}" >> "$agents_file"
                    printf '%s' "$section_content" >> "$agents_file"
                fi
                in_section=false
                current_section=""
                section_content=""
            else
                # Accumulate content
                # Include ### subsections for sections that need them,
                # skip ### for others to keep AGENTS.md concise
                if [[ "$line" =~ ^### ]]; then
                    if echo "$current_section" | grep -qE "($sections_with_subsections)"; then
                        section_content="${section_content}${line}"$'\n'
                    fi
                    # else skip the ### heading line for brevity
                else
                    section_content="${section_content}${line}"$'\n'
                fi
            fi
        fi
    done < "$claude_file"

    # Don't forget the last section
    if [[ "$in_section" == true && -n "$section_content" ]]; then
        printf '%s\n' "## ${current_section}" >> "$agents_file"
        printf '%s' "$section_content" >> "$agents_file"
    fi

    # Add footer
    cat >> "$agents_file" << EOF

---

**Detailed guidelines:** [CLAUDE.md](CLAUDE.md)
EOF
}
