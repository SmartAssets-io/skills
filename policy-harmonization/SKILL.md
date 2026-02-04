---
name: policy-harmonization
description: Synchronize AI guidance files (CLAUDE.md, AGENTS.md) and documentation patterns across multiple repositories. Use when maintaining consistency across a multi-repo workspace, onboarding new repos to project standards, or detecting policy drift.
---

# Policy Harmonization

Keep AI guidance and documentation patterns consistent across repositories.

## What Gets Harmonized

| File | Purpose |
|------|---------|
| `CLAUDE.md` | AI assistant guidance (Claude Code) |
| `AGENTS.md` | AI guidance (other tools) |
| `docs/ToDos.md` | Task tracking |
| `docs/Backlog.md` | Backlog items |
| `docs/CompletedTasks.md` | Completed work archive |

## Source Templates

Templates live in a central location (e.g., `top-level-gitlab-profile/docs/templates/`):

```
templates/
├── CLAUDE.md.template
├── AGENTS.md.template
├── ToDos.md.template
├── Backlog.md.template
└── CompletedTasks.md.template
```

## Harmonization Process

### 1. Scan for Repositories
```bash
# Find all git repos in workspace
find . -type d -name ".git" -not -path "*/node_modules/*" | sed 's|/.git||'
```

### 2. Compare Each File
For each repo and harmonized file:
- Check if file exists
- Compare content to template
- Flag differences

### 3. Report Status

```
[1/12] BountyForge/ToolChain
       [UPDATE] CLAUDE.md - Content differs
       [OK] docs/ToDos.md
       [CREATE] docs/Backlog.md

[2/12] BountyForge/discord-mcp-bot
       [OK] All files in sync
```

### 4. Apply Changes

**Interactive mode**: Per-file confirmation
```
Apply changes to CLAUDE.md? [y/N/d(iff)/q(uit)]
```

**Agentic mode**: Direct changes without prompts

## Conflict Resolution

When target differs from template:

| Option | Action |
|--------|--------|
| `y` | Apply template |
| `n` | Skip this file |
| `d` | View diff first |
| `q` | Quit harmonization |

## Customization Handling

Some repos need customization. Options:

1. **Extend template**: Add repo-specific sections below template content
2. **Skip file**: Mark as manually maintained
3. **Fork template**: Create repo-specific template

## Three-File Pattern

Every repo should have:
- `docs/ToDos.md` - Active tasks
- `docs/Backlog.md` - Future work
- `docs/CompletedTasks.md` - Done work

This pattern enables epoch-based task management and archival.

## Profile Directory Pattern

For multi-repo subgroups, task files may be centralized:

```
BountyForge/
├── BountyForge_gitlab-profile/  # Profile directory
│   └── docs/
│       ├── ToDos.md             # Shared tasks
│       └── UserStories.md       # Shared stories
├── discord-mcp-bot/             # Sub-repo (no task files)
└── ssl_data_spigot/             # Sub-repo (no task files)
```

## Dry Run

Preview changes without modifying:
```bash
./harmonize.sh --dry-run
```

## Best Practices

- Run harmonization after template updates
- Review diffs before applying
- Commit harmonization changes separately
- Document intentional deviations
- Use profile directories for subgroups
