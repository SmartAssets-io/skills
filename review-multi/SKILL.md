---
name: review-multi
description: Perform multi-agent code review using multiple LLM providers with consensus-based aggregation posted to GitHub PR or GitLab MR
license: SSL
---

<!-- ste-policy: required -->
## Language Standard

For English technical prose, obey the [Simplified Technical English policy](#simplified-technical-english).
Apply the policy to text that this command creates or substantially rewrites.
Machine-significant and quoted text remains exempt.
Honor explicit non-English requests.
For committed prompt or policy files, run the repository STE Check and complete a human STE Review.

## Quick Help

If the user passed `?`, `--help`, or `-h` as the argument, display ONLY this synopsis and stop. Do NOT run any scripts or proceed with the command.

```
/review:multi [OPTIONS] [PR#|MR#|URL]

Options:
  --create              Create PR/MR first, then review
  --target BRANCH       Target branch for --create (default: dev)
  --providers LIST      Comma-separated providers (anthropic,openai,google,xai)
  --model MODEL         Override default model per provider
  --post                Post results to PR/MR (default: display only)
  --json                JSON output
```

---

# Multi-Agent PR/MR Review

Perform a multi-agent code review using multiple LLM providers (Anthropic, OpenAI, Google, xAI) and post the aggregated results to a GitHub PR or GitLab MR.

## Prerequisites

### Required Tools

| Tool | Purpose | Installation |
|------|---------|--------------|
| `jq` | JSON parsing and manipulation | `brew install jq` (macOS) / `apt install jq` (Linux) |
| `curl` | API requests to LLM providers | Usually pre-installed |
| `bash` | Script execution (v4.0+) | Usually pre-installed |

### Platform-Specific Tools

For **GitHub** repositories:
| Tool | Purpose | Installation |
|------|---------|--------------|
| `gh` | GitHub CLI for PR operations | `brew install gh` / [GitHub CLI](https://cli.github.com/) |

For **GitLab** repositories:
| Tool | Purpose | Installation |
|------|---------|--------------|
| `glab` | GitLab CLI for MR operations | `brew install glab` / [GitLab CLI](https://gitlab.com/gitlab-org/cli) |
| `GITLAB_TOKEN` | Alternative to glab authentication | Set via environment variable |

### API Keys

At least one LLM provider API key must be set. See [Configuration](#configuration) for details.

## Usage

Run the multi-review script to execute parallel code reviews:

```bash
"scripts/multi-review.sh" [OPTIONS] [PR_URL|MR_URL|BRANCH]
```

If no target is specified, reviews the PR/MR for the current branch.

## Modes

### Review Mode (Default)

Add a multi-agent review to an existing PR/MR:

```bash
# Review current branch's PR/MR
"scripts/multi-review.sh"

# Review specific PR by number
"scripts/multi-review.sh" 123

# Review by URL
"scripts/multi-review.sh" https://github.com/owner/repo/pull/123

# Review by branch name
"scripts/multi-review.sh" feature/my-branch
```

### Create Mode

Create a new PR/MR and immediately add a multi-agent review.

#### Step 1: Verify prerequisites

Before running `--create`:
1. Confirm current branch has been pushed to remote (`git push` first if needed)
2. Detect platform (GitHub/GitLab) from git remote
3. Verify platform CLI is authenticated (`gh`/`glab`)

#### Step 2: Collect PR/MR details

Use **AskUserQuestion** to gather title and target branch:

```
Question: "What title and target branch for the new PR/MR?"
Header: "PR/MR"
Options:
1. Auto-generate from branch name (target: dev) (Recommended)
2. Custom title and target branch
```

- **Auto-generate**: Script derives title from branch name and targets `dev` branch by default
- **Custom**: Ask user for title text and target branch name, pass via `--title` and `--target-branch` flags

#### Step 3: Execute create + review

```bash
# Auto-generate title, detect target branch
"scripts/multi-review.sh" --create --verbose

# With explicit title
"scripts/multi-review.sh" --create --title "feat: add auth system" --verbose

# With explicit target branch
"scripts/multi-review.sh" --create --title "feat: add auth" --target-branch develop --verbose
```

The script will:
1. Create the PR/MR on the detected platform
2. Immediately run multi-agent review on the new PR/MR
3. Post the review comment

#### Step 4: Show completion summary

Display the standard Terminal Synopsis Format (see Claude Code Integration below) with the new PR/MR URL.

## Options

| Option | Description |
|--------|-------------|
| `--create` | Create new PR/MR before reviewing |
| `--review` | Review existing PR/MR (default) |
| `--title TITLE` | PR/MR title for `--create` mode (auto-generated from branch name if omitted) |
| `--target-branch BRANCH` | Target/base branch for `--create` mode (auto-detected if omitted) |
| `--providers LIST` | Comma-separated provider list (e.g., `anthropic,openai`) |
| `--no-post` | Output review to stdout instead of posting |
| `--json` | Output raw JSON results |
| `--verbose` | Show detailed progress information |
| `--dry-run` | Show what would be done without executing |
| `--help`, `-h` | Show help message |

## Provider Selection

### Use All Enabled Providers (Default)

By default, uses all providers with valid API keys:

```bash
"scripts/multi-review.sh" 123
```

### Specify Providers

Use only specific providers:

```bash
"scripts/multi-review.sh" --providers anthropic,openai 123
```

### Available Providers

| Provider | Environment Variable | Default Model |
|----------|---------------------|---------------|
| `anthropic` | `ANTHROPIC_API_KEY` | Claude Fable 5 — `claude-fable-5` (server-side fallback to `claude-opus-4-8` on safety declines; override via `ANTHROPIC_FALLBACK_MODEL`, empty disables) |
| `openai` | `OPENAI_API_KEY` | GPT-5.6 Sol — `gpt-5.6-sol` |
| `google` | `GOOGLE_API_KEY` | Gemini 3.1 Pro — `gemini-3.1-pro-preview` |
| `xai` | `XAI_API_KEY` | Grok — `grok-4.5` |
| `bedrock` | `AWS_PROFILE` or `AWS_ACCESS_KEY_ID` or IAM role | Amazon Nova Pro — `us.amazon.nova-pro-v1:0` |
| `ollama` | `OLLAMA_HOST` | Local models — `codellama:latest` |

Override the default per provider with `ANTHROPIC_MODEL`, `OPENAI_MODEL`,
`GEMINI_MODEL`, `XAI_MODEL`, `BEDROCK_MODEL`, or `OLLAMA_MODEL`. Review output
reports the model the API actually served (`model`) alongside the configured
value (`model_requested`); when they differ, display surfaces show both.

## Output Modes

### Post to PR/MR (Default)

Posts a formatted review comment with:
- Consensus verdict (Approved/Needs Work)
- Per-provider breakdown
- Summary
- Issues found (collapsible sections)
- Individual reviewer assessments

### No Post Mode

Output review to stdout without posting:

```bash
"scripts/multi-review.sh" --no-post 123
```

### JSON Mode

Output raw JSON for programmatic use:

```bash
"scripts/multi-review.sh" --json --no-post 123
```

## Review Format

The posted review includes:

```markdown
## Multi-Agent Code Review

**Verdict:** :white_check_mark: Approved (80% agreement)

**Reviewed by:**

| Provider | Model | Verdict | Confidence |
|----------|-------|---------|------------|
| anthropic | `claude-fable-5` | Approve | 0.92 |
| openai | `gpt-5.6-sol` | Approve | 0.88 |
| gemini | `gemini-3.1-pro-002` (requested `gemini-3.1-pro-preview`) | Approve | 0.85 |
| xai | `grok-4.5` | Needs Work | 0.78 |

The Model cell shows the id the API actually served; when it differs from the
configured value, the requested alias appears in parentheses.

---

### Summary

[Combined assessment from all reviewers]

---

### Issues Found

<details>
<summary><b>:yellow_circle: Minor: Issue title</b> (Reported by: Claude, Gemini)</summary>

**File:** `path/to/file.js` (line 42)

[Issue description]

</details>

---

<details>
<summary>View individual reviewer assessments</summary>

[Per-reviewer summaries]

</details>
```

## Consensus Algorithm

The multi-agent review system uses a weighted consensus algorithm to determine the final verdict.

### Algorithm Steps

1. **Filter Responses**: Exclude providers that returned `abstain` (API errors, timeouts, safety filters)
2. **Count Votes**: Tally `approve` and `needs_work` verdicts from remaining providers
3. **Calculate Ratios**: Compute percentage of each verdict type
4. **Apply Threshold**: Use 60% threshold (configurable) to determine consensus
5. **Determine Final Verdict**: Based on threshold comparison

### Edge Cases

| Scenario | Outcome | Rationale |
|----------|---------|-----------|
| All providers abstain | `needs_work` | Conservative default when no valid reviews |
| Single provider responds | Uses that verdict | Threshold not applicable with n=1 |
| 50/50 split (2 providers) | `needs_work` | No consensus, default to conservative |
| 2 approve, 1 needs_work | `approve` (66%) | Exceeds 60% threshold |
| 1 approve, 2 needs_work | `needs_work` (66%) | Exceeds 60% threshold |
| API timeout | Provider abstains | Does not affect consensus |
| Invalid JSON response | Provider abstains | Malformed responses excluded |

### Confidence Weighting

Provider confidence scores (0.0-1.0) are displayed but currently not used for vote weighting. All valid votes are weighted equally.

### Consensus Examples

```
Providers: [Claude: approve, GPT: approve, Gemini: needs_work, Grok: abstain]
Valid votes: 3 (Grok excluded)
Approve: 2/3 = 66.7% -> Exceeds 60% threshold
Final verdict: APPROVE

Providers: [Claude: approve, GPT: needs_work, Gemini: needs_work]
Valid votes: 3
Approve: 1/3 = 33.3% -> Below 60% threshold
Needs work: 2/3 = 66.7% -> Exceeds 60% threshold
Final verdict: NEEDS_WORK

Providers: [Claude: abstain, GPT: abstain]
Valid votes: 0
Final verdict: NEEDS_WORK (conservative default)
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success, PR/MR approved |
| 1 | General error |
| 2 | No providers available |
| 3 | Platform not detected |
| 4 | PR/MR not found |
| 10 | Success, but verdict is needs_work |

## Examples

### Quick Review

```bash
# Review current branch
"scripts/multi-review.sh"

# Review specific PR
"scripts/multi-review.sh" 123
```

### Create and Review

```bash
# Auto-generate title, detect target branch
"scripts/multi-review.sh" --create --verbose

# With explicit title
"scripts/multi-review.sh" --create --title "feat: add auth system" --verbose

# With explicit target branch
"scripts/multi-review.sh" --create --target-branch develop --verbose
```

### Selective Providers

```bash
# Only Claude and ChatGPT
"scripts/multi-review.sh" --providers anthropic,openai 123

# Only local Ollama
"scripts/multi-review.sh" --providers ollama 123
```

### Preview Without Posting

```bash
# See the review without posting
"scripts/multi-review.sh" --no-post 123

# Get JSON for scripting
"scripts/multi-review.sh" --json --no-post 123 > review.json
```

### Verbose Mode

```bash
# See detailed progress
"scripts/multi-review.sh" --verbose 123
```

## Configuration

### API Keys

Set API keys in your environment:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
export GOOGLE_API_KEY="AIza..."
export XAI_API_KEY="..."
```

### Amazon Bedrock (Nova)

For Amazon Bedrock with Nova models:

```bash
# Option 1: Explicit credentials (not recommended for production)
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."

# Option 2: AWS CLI profile (recommended)
export AWS_PROFILE="my-bedrock-profile"

# Option 3: IAM role (for EC2, ECS, Lambda, etc.)
# No environment variables needed - uses instance metadata

# Optional configuration
export AWS_REGION="us-east-1"  # Optional, defaults to us-east-1
export BEDROCK_MODEL="us.amazon.nova-pro-v1:0"  # Optional

"scripts/multi-review.sh" --providers bedrock 123
```

Available Nova models:
- `us.amazon.nova-pro-v1:0` - Most capable (default)
- `us.amazon.nova-lite-v1:0` - Faster, lower cost
- `us.amazon.nova-micro-v1:0` - Fastest, text-only

**Prerequisites:**
- AWS CLI v2 installed and configured
- Bedrock model access enabled in AWS Console (Bedrock > Model access)
- IAM permissions for `bedrock:InvokeModel` action

**Note:** Nova models require explicit enablement in the AWS Bedrock console for your account and region. You may encounter "AccessDeniedException" if models are not enabled.

### Local Ollama

For local model reviews:

```bash
export OLLAMA_HOST="http://localhost:11434"
export OLLAMA_MODEL="codellama:70b"
"scripts/multi-review.sh" --providers ollama 123
```

### Configuration File

Optional: Create `~/.sa-review-agents.yaml` for advanced configuration:

```yaml
providers:
  cloud:
    - name: anthropic
      enabled: true
      model: claude-fable-5

settings:
  consensus_threshold: 0.6
  timeout_seconds: 120
```

## Troubleshooting

### No Providers Available

Ensure at least one API key is set:

```bash
echo $ANTHROPIC_API_KEY  # Should have a value
```

### Platform Not Detected

Ensure you're in a git repository with a GitHub or GitLab remote:

```bash
git remote -v  # Should show github.com or gitlab.com
```

### GitHub CLI Not Authenticated

```bash
gh auth login  # Follow prompts
```

### GitLab CLI Not Authenticated

```bash
glab auth login  # Follow prompts
# Or set GITLAB_TOKEN environment variable
```

## Claude Code Integration

When invoking this skill, Claude MUST:

1. **Run the script** — it handles platform detection, review, and posting automatically
2. **Parse the JSON summary from stderr** to build a terminal synopsis
3. **Display the synopsis** in the terminal after the review is posted

### How to Run and Parse

The script emits a compact JSON summary to **stderr** after posting. Capture it:

```bash
json_summary=$("scripts/multi-review.sh" --verbose 2>&1 1>/dev/null | tail -1)
```

Or more practically, capture both stdout and stderr from the script output. The **last line of stderr** is a JSON object containing the full review result with these fields:

- `platform` — "github" or "gitlab"
- `target` — PR/MR number
- `url` — PR/MR URL
- `consensus.verdict` — "approve", "provide_feedback", "needs_review", or "needs_work"
- `consensus.agreement` — 0.0-1.0
- `providers[]` — array with `.provider`, `.model` (id the API actually served), `.model_requested` (configured id), `.verdict`, `.confidence`, `.summary`
- `issues[]` — array with `.severity`, `.file`, `.line`, `.title`, `.reported_by`
- `issue_stats.by_severity` — `.critical`, `.major`, `.minor`, `.suggestion` counts

### Terminal Synopsis Format

After the script completes, parse the JSON summary and display this synopsis:

```
## Multi-Agent Review Posted

**Platform:** GitLab MR #123 / GitHub PR #456
**URL:** https://gitlab.com/owner/repo/-/merge_requests/123

### Verdict: APPROVED (75% consensus)

| Provider | Model | Verdict | Confidence |
|----------|-------|---------|------------|
| anthropic | `claude-fable-5` | Approve | 0.92 |
| openai | `gpt-5.6-sol` | Approve | 0.88 |
| gemini | `gemini-3.1-pro-002` (requested `gemini-3.1-pro-preview`) | Needs Work | 0.78 |

### Issues Found: 1 critical, 2 major, 5 minor

### Critical & Major Issues

| Severity | File | Line | Issue | Reporters |
|----------|------|------|-------|-----------|
| Critical | auth.ts | 42 | SQL injection vulnerability | Claude, Gemini |
| Major | api.ts | 156 | Missing error handling | ChatGPT |
| Major | config.js | 23 | Hardcoded credentials | Claude |

### Summary
[1-2 sentence summary of the consensus]

View full review: [MR/PR URL]
```

**IMPORTANT:** Always include a "Critical & Major Issues" table when there are any critical or major severity issues. This ensures actionable items are visible without reading the full MR comment. If there are no critical or major issues, omit that table.

**Model column:** Populate from `providers[].model` (the id the API actually served), wrapped in backticks. When `providers[].model_requested` differs from `providers[].model`, append `(requested \`<model_requested>\`)` so drift between the configured and served model is visible in the terminal.

### Error Handling

If the script fails, show the user:
1. The error message from the script output
2. Suggest checking platform CLI authentication (`gh auth status` / `glab auth status`)
3. Suggest running with `--verbose` for more detail

### JSON Output Parsing

When using `--json` mode, parse the output to extract:

**Consensus:**
- `consensus.verdict`: "approve", "provide_feedback", "needs_review", or "needs_work"
- `consensus.agreement`: 0.0-1.0 (percentage as decimal)
- `consensus.voting_count`: Number of providers that voted

**Providers:**
- `providers[].provider`: Provider name (anthropic, openai, gemini, xai, bedrock)
- `providers[].model`: Model id the API actually served (e.g. `gemini-3.1-pro-002`); falls back to the configured id when the API does not echo one
- `providers[].model_requested`: Model id that was configured/requested (e.g. `gemini-3.1-pro-preview`)
- `providers[].verdict`: Individual verdict
- `providers[].confidence`: 0.0-1.0
- `providers[].summary`: Brief assessment

**Issues:**
- `issues[].severity`: "critical", "major", "minor", or "suggestion"
- `issues[].file`: File path
- `issues[].line`: Line number
- `issues[].title`: Issue title
- `issues[].description`: Detailed description
- `issues[].reported_by`: Array of provider names that reported this issue

**Issue Statistics:**
- `issue_stats.total`: Total issue count
- `issue_stats.by_severity.critical`: Count of critical issues
- `issue_stats.by_severity.major`: Count of major issues
- `issue_stats.by_severity.minor`: Count of minor issues
- `issue_stats.by_severity.suggestion`: Count of suggestions

## Related Commands

- `/quick-commit` - Commit changes with standard message
- `/recursive-push` - Push commits across repositories
- `/epic-review` - Review epic progress

---

## Simplified Technical English Policy

The policy in this section governs applicable English technical prose from this skill.
The ASD standard remains authoritative.
Machine-significant text and quoted or external text remain exempt.
Honor explicit requests for another language.
## Simplified Technical English
<!-- ste-policy: full -->

Smart Assets uses ASD-STE100 Simplified Technical English, Issue 9, dated January 2025, for applicable English technical prose.

This policy is a Smart Assets applicability profile. The ASD standard remains the authoritative source for its rules and controlled dictionary.

Get the current standard from the [official ASD-STE100 website](https://www.asd-ste100.org/) or its [official downloads page](https://www.asd-ste100.org/STE_downloads.html).

ASD owns the standard and the ASD-STE100 trademark. Do not copy its controlled dictionary, examples, or substantial rule text into this repository.

### Applicability

Use this policy for English technical prose that an assistant creates or substantially rewrites, including:

- Assistant responses
- Technical documentation
- Plans and specifications
- Procedures and instructions
- Warnings and cautions
- Review findings
- User-facing explanations and status messages.

Preserve unaffected legacy prose. Apply this policy to the text that the assistant adds or substantially changes.

If the user explicitly requests another language, use that language. If you report STE status, mark STE as not applicable to that output.

This policy does not apply to:

- Code, identifiers, commands, flags, paths, URLs, and schema keys
- Data formats, exact test fixtures, and machine-generated text
- Verbatim quotations and user-supplied text
- Third-party names, standard titles, and legal or license text.

Do not change technical meaning, safety controls, legal meaning, or exact user requirements only to satisfy a language rule.

### Words and terminology

Use the official Issue 9 dictionary as the source for general approved words. Do not copy the dictionary into project files.

Use a word only with its approved part of speech, meaning, and form. Use American English spelling unless another directive controls the text.

Use approved technical nouns and technical verbs for the applicable subject field. Record recurring Smart Assets terms in the project glossary.

Use one technical noun for one concept. Do not replace a canonical term with a synonym only for stylistic variation.

Keep a new technical noun short and easy to understand. Use no more than three words unless an approved term requires more words.

Do not use regional words, slang, or unexplained jargon. Define an unavoidable abbreviation at its first use.

Use technical nouns as nouns. Use technical verbs as verbs and only in their approved software-development meaning.

### Grammar and sentences

Use active voice. In descriptive text, use passive voice only when the agent is unknown or technically unimportant.

Use simple verb forms and tenses. Avoid progressive and other complex constructions unless an exempt technical term requires them.

Use a direct verb to describe an action. Do not hide an action in an abstract noun phrase.

Write complete sentences. Do not omit articles, subjects, verbs, or necessary nouns to make a sentence shorter.

Do not use contractions. Do not use semicolons.

Keep each sentence focused on one subject. Use a vertical list when one sentence would contain complex items or actions.

Make each pronoun refer to one clear noun. Repeat the technical noun when a pronoun can have more than one meaning.

### Procedures

Use a maximum of 20 words in each procedural sentence. Use one instruction in each sentence unless actions occur at the same time.

Start each instruction with an imperative verb. Put a necessary condition before the instruction and separate it with a comma.

Use numbered steps when sequence is important. Keep information-only notes separate from instructions, requirements, limits, and safety information.

### Descriptions

Use a maximum of 25 words in each descriptive sentence. Give information gradually and keep one topic in each paragraph.

Start each paragraph with its topic. Use no more than six sentences in one paragraph.

Use consistent key words to connect related sentences. Start a new paragraph when the topic changes.

### Safety information

Use the project-approved risk word or symbol. Start with a clear command or condition, and then state the risk or possible result.

Do not hide safety information in a note. Keep safety controls and their consequences explicit.

### Verification

An **STE Check** is deterministic. It can check policy coverage, sentence limits, paragraph limits, contractions, semicolons, and selected exemptions.

An **STE Review** is semantic. A human reviewer must check vocabulary, meaning, active voice, referents, terminology, and technical accuracy.

For committed prompt and policy files, run the repository STE Check. Review all applicable new or substantially rewritten prose before completion.

A checker cannot establish full ASD-STE100 conformance. Do not claim that text is ASD-STE100 compliant only because an automated check passes.
