---
name: agentic-development-modes
description: Guidelines for autonomous AI-assisted development with appropriate safety levels. Use when deciding between safe mode, agentic mode, or YOLO mode based on change stakes, or when setting up git worktrees for isolated development.
---

# Agentic Development Modes

Match autonomy level to change stakes. Higher risk = more oversight.

## Three Modes

| Mode | Command | Git Access | Use Case |
|------|---------|------------|----------|
| **Safe** | `claude` | Via slash commands | Interactive, reviewed work |
| **Agentic** | `claude-agentic` | Direct access | Autonomous in main repo |
| **YOLO** | `claude-agentic` in worktree | Full autonomy | Isolated experiments |

## Change Stakes Spectrum

### Tier 1: Basic Docs + Unit Tests (Lowest)
- README, comments, unit tests
- High autonomy OK
- Easily reversible

### Tier 2: Specs & Architecture Docs
- ADRs, design docs, API docs
- Moderate autonomy
- Review before finalizing

### Tier 3: AI Guidance Files
- CLAUDE.md, .cursorrules
- Moderate-careful
- Affects future AI sessions

### Tier 4: Security Models
- Threat models, auth specs
- Conservative autonomy
- Requires security expertise

### Tier 5: General Code + E2E Tests
- Application code, integration tests
- Use YOLO mode in worktrees
- Review before merge

### Tier 6: Critical Code
- Auth, payments, crypto
- Careful oversight required
- Expert review before merge

### Tier 7: Single-Source of Truth (Highest)
- DB schemas, API contracts, CI/CD
- Maximum caution
- Coordination required

## Git Worktrees for YOLO Mode

### Create Worktree
```bash
git worktree add ../project-feature feature/new-feature
cd ../project-feature
claude-agentic  # Full autonomy here
```

### Benefits
- Changes isolated from main repo
- Easy to discard: `git worktree remove ../project-feature`
- Review before merging back
- Multiple parallel experiments possible

### Cleanup
```bash
cd ../project-main
git worktree remove ../project-feature
# or to discard
git worktree remove --force ../project-feature
```

## Decision Matrix

| Situation | Recommended Mode |
|-----------|-----------------|
| Large doc refactor | YOLO (worktree) |
| Single typo fix | Safe |
| New feature | YOLO (worktree) |
| Critical security fix | Safe + expert review |
| Database migration | Safe + extensive testing |
| CLAUDE.md updates | Agentic + review |

## Safe Mode Restrictions

In safe mode, these are blocked:
- `git commit`
- `git push`
- `git add`

Use slash commands instead:
- `/quick-commit` - Intelligent commits
- `/recursive-push` - Push across repos

## Agentic Mode

No restrictions, but still supports:
- Slash commands for convenience
- Auto-generated commit messages
- Multi-repo awareness

## Key Principle

> Autonomy scales inversely with stakes.

Low-risk changes → High autonomy
High-risk changes → More human oversight
