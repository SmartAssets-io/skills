# Smart Assets Skills

**Operational agent skills for AI-assisted development workflows**

Skills with bundled scripts for epoch-based task management, multi-agent coordination, multi-repo git operations, and Smart Asset creation.

<!-- badges-start -->
[![GitLab Pipeline](https://gitlab.com/smart-assets.io/gitlab-profile/badges/master/pipeline.svg)](https://gitlab.com/smart-assets.io/gitlab-profile/-/pipelines)
[![Skill Scanner](https://img.shields.io/badge/skill--scanner-enabled-brightgreen)](https://gitlab.com/smart-assets.io/gitlab-profile/-/pipelines)
[![Changelog](https://img.shields.io/badge/changelog-latest-blue)](https://gitlab.com/smart-assets.io/gitlab-profile/-/blob/master/CHANGELOG.md)
[![Releases](https://img.shields.io/badge/releases-notes-green)](https://gitlab.com/smart-assets.io/gitlab-profile/-/blob/master/RELEASES.md)
<!-- badges-end -->

> **Source:** [GitLab](https://gitlab.com/smart-assets.io/gitlab-profile) | [Changelog](https://gitlab.com/smart-assets.io/gitlab-profile/-/blob/master/CHANGELOG.md) | [Releases](https://gitlab.com/smart-assets.io/gitlab-profile/-/blob/master/RELEASES.md)

---

## Quick Start

```bash
npx openskills install SmartAssets-io/skills
npx openskills sync
```

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

Each skill follows the OpenSkills format with optional script bundles:

```
skill-name/
  SKILL.md              # Skill definition (frontmatter + instructions)
  scripts/              # Executable scripts (optional)
    main-script.sh
    lib/                # Script libraries
      helper.sh
  assets/               # Data files (optional)
    schema.yaml
```

---

## Manual Installation

### For Claude Code

```bash
mkdir -p .claude/skills
git clone https://github.com/SmartAssets-io/skills.git .claude/skills/smart-assets
```

### For Other Agents

Copy skill folders to your project and reference in `AGENTS.md`.

---

## Source

These skills are maintained in the [Smart Assets GitLab](https://gitlab.com/smart-assets.io/gitlab-profile)
and synced to GitHub automatically.

## Related Resources

- [Smart Assets GitLab](https://gitlab.com/smart-assets.io)
- [OpenSkills CLI](https://github.com/numman-ali/openskills)

---

## License

[Sovereign Source License (SSL) v0.2](LICENSE.md)

This project is licensed under the Sovereign Source License, which extends Apache 2.0
with optional ecosystem enhancements for sustainable open source development.
