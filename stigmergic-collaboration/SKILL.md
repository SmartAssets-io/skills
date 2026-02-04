---
name: stigmergic-collaboration
description: Multi-agent coordination through shared markdown files instead of direct messaging. Use when multiple AI agents need to work in parallel without conflicts, when you need to leave context for future sessions, or when coordinating work across team members (human or AI). Enables session continuity and audit trails through version control.
---

# Stigmergic Collaboration

Coordinate work through shared `.md` files - like ants leaving pheromone trails. Agents communicate indirectly by modifying files that other agents read.

## Key Principles

1. **Environment as Communication**: Modify shared files, not direct messages
2. **Traces Persist**: Signals remain for future sessions to discover
3. **Self-Organization**: No central coordinator needed
4. **Asynchronous**: Agents don't need to run simultaneously

## Coordination Files

| File | Purpose |
|------|---------|
| `docs/ToDos.md` | Task assignment and status |
| `docs/work-logs/*.md` | Session progress and handoffs |
| `docs/discoveries/*.md` | Shared findings |
| `docs/designs/*.md` | Architectural decisions |

## Task Claiming Pattern

Before working on a task, claim it:

```yaml
# In docs/ToDos.md
- id: TASK-001
  status: in_progress      # Changed from 'pending'
  claimed_by: claude-session-abc123
  claimed_at: 2025-01-15T10:00:00Z
```

Other agents see the claim and work on different tasks.

## Handoff Pattern

When pausing or completing work:

```markdown
# In docs/work-logs/task-001-session.md
---
handoff_status: ready
handoff_to: any
---

## Handoff Notes
- Login working, logout not started
- Tests at 60% coverage
- See blockers for Redis decision

## Next Steps
- Implement logout endpoint
- Add session cleanup job
```

## Discovery Pattern

Share findings for other agents:

```markdown
# docs/discoveries/2025-01-15-rate-limiter.md
---
discovered_by: claude-session-abc123
relevance: [TASK-001, TASK-002]
category: pattern
---

# Discovery: Rate Limiter Exists

Found existing rate limiter at `src/middleware/rateLimiter.ts`.
TASK-002 can reuse this instead of implementing new.
```

## Conflict Prevention

### Optimistic Locking
1. Read file, note `last_modified_at`
2. Make changes
3. Before writing, re-read and check timestamp
4. If changed, merge or abort

### Race Condition Resolution
If two agents claim simultaneously:
1. First commit wins (git history)
2. Second agent re-reads, finds another task

## Agent Identification

Use consistent identifiers:

| Context | Format | Example |
|---------|--------|---------|
| YAML fields | `{tool}-session-{id}` | `claude-session-abc123` |
| Commits | `[agent:{id}]` | `[agent:abc123] feat: add login` |
| Human | `human-{name}` | `human-jeff` |

## Status Flow

```
pending → in_progress (claimed) → complete
              ↓                      ↑
           blocked ─────────────────→
```

## Best Practices

- Always claim before working
- Document discoveries for future sessions
- Update handoff notes when pausing
- Commit stigmergic file updates promptly
- Check ToDos.md for existing claims before starting
