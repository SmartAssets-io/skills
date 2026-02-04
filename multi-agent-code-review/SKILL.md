---
name: multi-agent-code-review
description: Perform code reviews using multiple LLM providers (Claude, GPT, Gemini, Grok) with consensus-based aggregation. Use when reviewing pull requests or merge requests to get diverse perspectives, reduce blind spots, and achieve higher confidence through multi-model agreement.
---

# Multi-Agent Code Review

Get parallel code reviews from multiple LLMs with consensus-based verdicts.

## Why Multi-Agent Review?

- **Diverse perspectives**: Different models have different strengths
- **Reduced blind spots**: Issues caught by one model may be missed by another
- **Consensus confidence**: Higher confidence when multiple models agree

## Supported Providers

| Provider | Env Variable | Model |
|----------|-------------|-------|
| Anthropic | `ANTHROPIC_API_KEY` | Claude |
| OpenAI | `OPENAI_API_KEY` | GPT-4 |
| Google | `GOOGLE_API_KEY` | Gemini |
| xAI | `XAI_API_KEY` | Grok |
| Ollama | `OLLAMA_HOST` | Local models |

## Review Process

### 1. Gather PR/MR Diff
```bash
# GitHub
gh pr diff $PR_NUMBER

# GitLab
glab mr diff $MR_NUMBER
```

### 2. Create Review Prompt

```
Review this code change for:
- Security vulnerabilities
- Logic errors
- Performance issues
- Code style and best practices

Provide:
- Verdict: approve | needs_work
- Confidence: 0.0-1.0
- Issues found with severity and location
- Summary of changes
```

### 3. Send to Each Provider

Send the same prompt to all configured providers in parallel.

### 4. Aggregate Results

**Consensus Algorithm:**
1. Exclude providers that error/timeout (abstain)
2. Count approve vs needs_work votes
3. Apply 60% threshold for consensus
4. Default to needs_work if no consensus

### 5. Deduplicate Issues

Similar issues from multiple providers are merged:
- Match by file + line number
- Combine descriptions
- Escalate severity if 2+ providers report

## Output Format

```markdown
## Multi-Agent Code Review

**Verdict:** ✅ Approved (80% agreement)

**Reviewed by:**
- Claude: Approve (confidence: 0.92)
- GPT-4: Approve (confidence: 0.88)
- Gemini: Approve (confidence: 0.85)
- Grok: Needs Work (confidence: 0.78)

### Issues Found

**🟡 Minor: Missing documentation**
File: `src/auth.js` (line 42)
Reported by: Claude, Gemini
The function lacks JSDoc documentation.

### Summary
[Combined assessment from all reviewers]
```

## Severity Levels

- 🔴 **Critical**: Security vulnerabilities, data loss risk
- 🟠 **Major**: Logic errors, breaking changes
- 🟡 **Minor**: Style issues, missing docs
- 🔵 **Info**: Suggestions, nitpicks

## Categories

- Security
- Logic
- Performance
- Style
- Documentation
- Testing

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Approved |
| 10 | Needs work |
| 1 | Error |
| 2 | No providers available |

## Configuration

Minimum required: At least one provider API key set.

Recommended: 3+ providers for meaningful consensus.

## Best Practices

- Run before merging to main
- Address all critical/major issues
- Consider minor issues for code quality
- Re-run after addressing feedback
