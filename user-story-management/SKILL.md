---
name: user-story-management
description: Create and manage user stories with bi-directional linking to implementation epochs. Use when capturing business requirements, creating new user stories, linking stories to technical epochs, or reviewing story status and acceptance criteria progress.
---

# User Story Management

Capture business needs in `docs/UserStories.md` with traceability to implementation epochs in `docs/ToDos.md`.

## User Story Format

```markdown
## US-010: Story Management Commands

**Status:** In Progress
**Implemented in:** EPOCH-012

As a **project lead**,
I want **slash commands to manage user stories**
so that **I can maintain traceability between requirements and tasks**.

### Acceptance Criteria
- [ ] /story create works interactively
- [ ] /story link updates both files
- [ ] /story sync shows orphans
```

## Creating a Story

### Required Elements
1. **ID**: `US-XXX` format (auto-increment)
2. **Title**: Brief description
3. **Status**: Planned | In Progress | Complete
4. **Persona**: Who benefits
5. **Capability**: What they want
6. **Benefit**: Why they want it
7. **Acceptance Criteria**: Definition of done

### Template

```markdown
## US-XXX: [Title]

**Status:** Planned
**Implemented in:** [EPOCH-XXX when linked]

As a **[persona]**,
I want **[capability]**
so that **[benefit]**.

### Acceptance Criteria
- [ ] [Criterion 1]
- [ ] [Criterion 2]
```

## Linking Stories to Epochs

Bi-directional linking maintains traceability:

### In UserStories.md
```markdown
**Status:** In Progress
**Implemented in:** EPOCH-012
```

### In ToDos.md (epoch YAML)
```yaml
epoch_id: EPOCH-012
title: Story Management Commands
user_story: US-010
```

## Sync Report

Check for orphans (unlinked items):

**Orphan Stories**: Stories with no linked epoch
**Orphan Epochs**: Epochs with no linked story

Not all epochs need stories (technical debt, infrastructure), but feature work should trace back to requirements.

## Story Lifecycle

```
Planned → In Progress → Complete
   ↓          ↓
(link epoch) (all criteria met)
```

## Status Rules

| Story Status | Condition |
|--------------|-----------|
| Planned | No linked epoch |
| In Progress | Linked epoch exists, not all criteria met |
| Complete | All acceptance criteria checked |

## Common Personas

- Developer using AI assistants
- Project/Team lead
- Workspace maintainer
- Open source contributor
- End user of [product]

## Best Practices

- Write stories before implementation
- Keep acceptance criteria testable
- Link stories to epochs promptly
- Update criteria as implementation reveals scope
- Mark criteria complete as work progresses
