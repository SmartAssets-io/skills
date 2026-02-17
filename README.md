# Smart Assets Skills

**Operational agent skills for AI-assisted development workflows**

[OpenSkills](https://github.com/numman-ali/openskills)-compatible skill collection with bundled scripts for epoch-based task management, multi-agent coordination, multi-repo git operations, and Smart Asset creation. Works with Claude Code, Cursor, Windsurf, Aider, and any agent that reads `AGENTS.md`.

<!-- badges-start -->
[![OpenSkills](https://img.shields.io/badge/OpenSkills-compatible-blue)](https://github.com/numman-ali/openskills)
[![Skills](https://img.shields.io/badge/skills-15-brightgreen)](./)
[![Changelog](https://img.shields.io/badge/changelog-latest-blue)](https://gitlab.com/smart-assets.io/gitlab-profile/-/blob/master/CHANGELOG.md)
[![License: SSL](https://img.shields.io/badge/license-SSL%20v0.2-orange)](LICENSE.md)
<!-- badges-end -->

> **Source:** [GitLab](https://gitlab.com/smart-assets.io/gitlab-profile) | [Changelog](https://gitlab.com/smart-assets.io/gitlab-profile/-/blob/master/CHANGELOG.md) | [Releases](https://gitlab.com/smart-assets.io/gitlab-profile/-/blob/master/RELEASES.md)

---

## Quick Start

Install globally so skills are available across all projects:

```bash
npx openskills install SmartAssets-io/skills --global
npx openskills sync
```

Or install into a specific project:

```bash
cd your-project/
npx openskills install SmartAssets-io/skills
npx openskills sync
```

After installation, invoke skills with `/skill-name` in Claude Code or `npx openskills read skill-name` for other agents.

---

## Available Skills

| Skill | Description |
|-------|-------------|
| **agent-team** | Launch a coordinated multi-agent Claude Code team with orchestrator and workers in tmux |
| **agent-teams-tmux** | Launch a tmux-based display for monitoring parallel agent teams with real-time dashboard and stigmergic file watchers |
| **create-smart-asset** | Create, initialize, and synchronize Smart Asset schemas and repository structure using SAIntrinsics master schema |
| **epoch-hygiene** | Scan task tracking files for epoch completion status and perform hygiene operations (archiving, cleanup, validation) |
| **epoch-review** | Preview and summarize epochs for high-level review of scope and progress before diving into implementation |
| **implement-task** | Begin implementation of the next task supporting both IPC and stigmergic coordination with epoch-aware progress tracking |
| **multi-agent-code-review** | Perform multi-agent code review using multiple LLM providers with consensus-based aggregation posted to GitHub PR or GitLab MR |
| **multi-repo-sync** | Synchronize conventions and policies across all repositories in the workspace with branch consistency enforcement |
| **next-task** | Review project task tracking and stigmergic signals to identify and explain the next task to work on |
| **policy-harmonization** | Synchronize policies, approaches, and conventions across repositories by harmonizing with top-level-gitlab-profile standards |
| **quick-commit** | Quick commit changes (asks about untracked files, auto-generates message or uses provided one) |
| **recursive-push** | Push unpushed commits across all repositories in the workspace |
| **user-story-management** | Create, link, and synchronize user stories with epochs providing bi-directional linking between UserStories.md and ToDos.md |
| **version** | Show git commit hash and date for workflow tools and current repository |
| **work-tasks** | Launch the todo-task-executor agent to systematically work through remaining tasks using stigmergic coordination |

---

## Skill Structure

Each skill follows the [OpenSkills SKILL.md format](https://github.com/numman-ali/openskills) with optional script bundles:

```
skill-name/
  SKILL.md              # Skill definition (YAML frontmatter + instructions)
  scripts/              # Executable scripts (optional)
    main-script.sh
    lib/                # Script libraries
      helper.sh
  assets/               # Data files (optional)
    schema.yaml
```

---

## Manual Installation

If you prefer not to use `npx openskills`, you can install manually with git:

### Global (all projects)

```bash
mkdir -p ~/.claude/skills
git clone https://github.com/SmartAssets-io/skills.git ~/.claude/skills/smart-assets
```

### Project-local

```bash
mkdir -p .claude/skills
git clone https://github.com/SmartAssets-io/skills.git .claude/skills/smart-assets
```

### For Other Agents (Cursor, Windsurf, Aider)

Copy skill folders to your project and run:

```bash
npx openskills sync
```

This generates an `AGENTS.md` file that non-Claude agents can read.

---

## Source

These skills are maintained in the [Smart Assets GitLab](https://gitlab.com/smart-assets.io/gitlab-profile)
and synced to GitHub automatically. The sync runs nightly via GitLab CI.

## Related Resources

- [OpenSkills CLI](https://github.com/numman-ali/openskills) - Universal skills loader for AI coding agents
- [Smart Assets GitLab](https://gitlab.com/smart-assets.io) - Source repositories

---

## License

[Sovereign Source License (SSL) v0.2](LICENSE.md)

This project is licensed under the Sovereign Source License, which extends Apache 2.0
with optional ecosystem enhancements for sustainable open source development.
