---
name: multi-agent-code-review
description: Perform multi-agent code review using multiple LLM providers with consensus-based aggregation posted to GitHub PR or GitLab MR
license: SSL
---

# Multi-Agent PR/MR Review

Perform a multi-agent code review using multiple LLM providers (Anthropic, OpenAI, Google, xAI) and post the aggregated results to a GitHub PR or GitLab MR.

## Path Resolution

Scripts referenced below live in the `top-level-gitlab-profile` repository. When running from another repository, resolve the base path first. **Combine this resolution with each script invocation in a single shell command:**

```bash
PROFILE_DIR="$(git rev-parse --show-toplevel)"
if [ ! -d "$PROFILE_DIR/AItools/scripts" ]; then
  for _p in "$PROFILE_DIR/.." "$PROFILE_DIR/../.."; do
    _candidate="$_p/top-level-gitlab-profile"
    if [ -d "$_candidate/AItools/scripts" ]; then
      PROFILE_DIR="$(cd "$_candidate" && pwd)"
      break
    fi
  done
fi
```

Use `"$PROFILE_DIR/AItools/scripts/..."` for all script paths below.

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
"$PROFILE_DIR/AItools/scripts/multi-review.sh" [OPTIONS] [PR_URL|MR_URL|BRANCH]
```

If no target is specified, reviews the PR/MR for the current branch.

## Modes

### Review Mode (Default)

Add a multi-agent review to an existing PR/MR:

```bash
# Review current branch's PR/MR
"$PROFILE_DIR/AItools/scripts/multi-review.sh"

# Review specific PR by number
"$PROFILE_DIR/AItools/scripts/multi-review.sh" 123

# Review by URL
"$PROFILE_DIR/AItools/scripts/multi-review.sh" https://github.com/owner/repo/pull/123

# Review by branch name
"$PROFILE_DIR/AItools/scripts/multi-review.sh" feature/my-branch
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
"$PROFILE_DIR/AItools/scripts/multi-review.sh" --create --verbose

# With explicit title
"$PROFILE_DIR/AItools/scripts/multi-review.sh" --create --title "feat: add auth system" --verbose

# With explicit target branch
"$PROFILE_DIR/AItools/scripts/multi-review.sh" --create --title "feat: add auth" --target-branch develop --verbose
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
"$PROFILE_DIR/AItools/scripts/multi-review.sh" 123
```

### Specify Providers

Use only specific providers:

```bash
"$PROFILE_DIR/AItools/scripts/multi-review.sh" --providers anthropic,openai 123
```

### Available Providers

| Provider | Environment Variable | Model |
|----------|---------------------|-------|
| `anthropic` | `ANTHROPIC_API_KEY` | Claude Opus |
| `openai` | `OPENAI_API_KEY` | ChatGPT |
| `google` | `GOOGLE_API_KEY` | Gemini |
| `xai` | `XAI_API_KEY` | Grok |
| `bedrock` | `AWS_PROFILE` or `AWS_ACCESS_KEY_ID` or IAM role | Amazon Nova Pro |
| `ollama` | `OLLAMA_HOST` | Local models |

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
"$PROFILE_DIR/AItools/scripts/multi-review.sh" --no-post 123
```

### JSON Mode

Output raw JSON for programmatic use:

```bash
"$PROFILE_DIR/AItools/scripts/multi-review.sh" --json --no-post 123
```

## Review Format

The posted review includes:

```markdown
## Multi-Agent Code Review

**Verdict:** :white_check_mark: Approved (80% agreement)

**Reviewed by:**
- Claude Opus: Approve (confidence: 0.92)
- ChatGPT: Approve (confidence: 0.88)
- Gemini: Approve (confidence: 0.85)
- Grok: Needs Work (confidence: 0.78)

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
"$PROFILE_DIR/AItools/scripts/multi-review.sh"

# Review specific PR
"$PROFILE_DIR/AItools/scripts/multi-review.sh" 123
```

### Create and Review

```bash
# Auto-generate title, detect target branch
"$PROFILE_DIR/AItools/scripts/multi-review.sh" --create --verbose

# With explicit title
"$PROFILE_DIR/AItools/scripts/multi-review.sh" --create --title "feat: add auth system" --verbose

# With explicit target branch
"$PROFILE_DIR/AItools/scripts/multi-review.sh" --create --target-branch develop --verbose
```

### Selective Providers

```bash
# Only Claude and ChatGPT
"$PROFILE_DIR/AItools/scripts/multi-review.sh" --providers anthropic,openai 123

# Only local Ollama
"$PROFILE_DIR/AItools/scripts/multi-review.sh" --providers ollama 123
```

### Preview Without Posting

```bash
# See the review without posting
"$PROFILE_DIR/AItools/scripts/multi-review.sh" --no-post 123

# Get JSON for scripting
"$PROFILE_DIR/AItools/scripts/multi-review.sh" --json --no-post 123 > review.json
```

### Verbose Mode

```bash
# See detailed progress
"$PROFILE_DIR/AItools/scripts/multi-review.sh" --verbose 123
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

"$PROFILE_DIR/AItools/scripts/multi-review.sh" --providers bedrock 123
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
"$PROFILE_DIR/AItools/scripts/multi-review.sh" --providers ollama 123
```

### Configuration File

Optional: Create `~/.sa-review-agents.yaml` for advanced configuration:

```yaml
providers:
  cloud:
    - name: anthropic
      enabled: true
      model: claude-opus-4-5-20251101

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
json_summary=$("$PROFILE_DIR/AItools/scripts/multi-review.sh" --verbose 2>&1 1>/dev/null | tail -1)
```

Or more practically, capture both stdout and stderr from the script output. The **last line of stderr** is a JSON object containing the full review result with these fields:

- `platform` — "github" or "gitlab"
- `target` — PR/MR number
- `url` — PR/MR URL
- `consensus.verdict` — "approve", "provide_feedback", "needs_review", or "needs_work"
- `consensus.agreement` — 0.0-1.0
- `providers[]` — array with `.provider`, `.verdict`, `.confidence`, `.summary`
- `issues[]` — array with `.severity`, `.file`, `.line`, `.title`, `.reported_by`
- `issue_stats.by_severity` — `.critical`, `.major`, `.minor`, `.suggestion` counts

### Terminal Synopsis Format

After the script completes, parse the JSON summary and display this synopsis:

```
## Multi-Agent Review Posted

**Platform:** GitLab MR #123 / GitHub PR #456
**URL:** https://gitlab.com/owner/repo/-/merge_requests/123

### Verdict: APPROVED (75% consensus)

| Provider | Verdict | Confidence |
|----------|---------|------------|
| Claude | Approve | 0.92 |
| ChatGPT | Approve | 0.88 |
| Gemini | Needs Work | 0.78 |

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
- `/epoch-review` - Review epoch progress
