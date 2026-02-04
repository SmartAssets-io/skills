---
name: session-metrics
description: Track and record AI coding session metrics to measure productivity and reduce AI slop. Use when logging session outcomes, analyzing signal-to-slop ratios, or improving AI-assisted development quality over time.
---

# Session Metrics Tracking

Measure AI coding session quality to identify patterns and reduce slop.

## Key Metrics

### Session Metrics
| Metric | Description | Target |
|--------|-------------|--------|
| Tokens consumed | Input + output tokens | Minimize |
| Cost USD | API cost | Track per-feature |
| LOC generated | Lines produced | Context only |
| LOC accepted | Lines kept after review | Maximize ratio |
| Commits | Commits per session | Higher = incremental |
| Test pass rate | First-run pass rate | >90% |
| Slop/Signal ratio | Discarded / Accepted | <0.2 |

### Quality Metrics
| Metric | Description | Target |
|--------|-------------|--------|
| Acceptance escape rate | Defects post-acceptance | <5% |
| Review escape rate | Defects post-merge | <2% |
| Production defect rate | Production bugs from AI code | <1% |

## What is AI Slop?

Code that exhibits:
- **Over-engineering**: Unnecessary abstractions
- **Hallucinated patterns**: Non-existent APIs
- **Context drift**: Ignoring project patterns
- **Incomplete implementation**: TODOs left in code

## Session Log Format

```yaml
# docs/metrics/sessions.yaml
---
session_id: "2025-01-15-abc123"
type: interactive | agentic
model: claude-opus-4-5
project_name: "my-project"
branch: "feature/xyz"
start_time: "2025-01-15T10:00:00Z"
end_time: "2025-01-15T12:30:00Z"
task_ids: [TASK-001]
metrics:
  tokens_in: 45000
  tokens_out: 12000
  cost_usd: 0.85
  loc_generated: 450
  loc_accepted: 380
  loc_discarded: 50
  loc_corrected: 20
  commits: 8
  tests_passed: 47
  tests_failed: 2
  slop_signal_ratio: 0.18
  test_pass_rate: 95.9
classification: production
outcome: success | partial | failed
notes: "Brief description"
```

## Classification Thresholds

| Classification | Slop Ratio | Test Pass | Description |
|---------------|------------|-----------|-------------|
| `production` | < 0.20 | > 90% | High quality |
| `review` | < 0.50 | > 70% | Needs review |
| `slop` | >= 0.50 | <= 70% | Extensive rework |

## Calculating Slop Ratio

```
slop_signal_ratio = (loc_discarded + loc_corrected) / loc_accepted
```

Example:
- Generated: 450 lines
- Accepted: 380 lines
- Discarded: 50 lines
- Corrected: 20 lines
- Ratio: (50 + 20) / 380 = 0.18 ✅

## Reducing Slop

### Before Session
- Write specs first
- Provide code examples
- Set explicit boundaries
- Reference existing patterns

### During Session
- Review incrementally
- Correct hallucinations immediately
- Check acceptance criteria
- Commit frequently

### After Session
- Record metrics
- Note what AI got wrong
- Update specs if ambiguous
- Track production escapes

## Trend Analysis

Track over time:
- Average slop ratio per project
- Cost per feature
- Time to completion trends
- Common hallucination patterns
