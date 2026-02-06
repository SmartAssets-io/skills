# Smart Assets Skills

**Agent Skills for AI-assisted development workflows**

Skills for epoch-based task management, multi-agent coordination, and multi-repo development.

> **Mirror Notice:** This repository is a GitHub mirror of the skills maintained in the [Smart Assets GitLab profile](https://gitlab.com/smart-assets.io/gitlab-profile/). The GitLab repository is the source of truth. This mirror exists so that skills can be installed directly via the OpenSkills CLI from GitHub.

---

## Quick Start

```bash
npx openskills install SmartAssets-io/skills
npx openskills sync
```

---

## 📦 Available Skills

| Skill | Description |
|-------|-------------|
| **epoch-task-management** | Manage tasks organized into epochs with YAML-structured ToDos.md |
| **stigmergic-collaboration** | Multi-agent coordination through shared markdown files |
| **user-story-management** | Create and link user stories to implementation epochs |
| **multi-repo-git** | Git operations across multiple repositories |
| **multi-agent-code-review** | Parallel code reviews with consensus aggregation |
| **agentic-development-modes** | Safe vs agentic vs YOLO mode guidelines |
| **session-metrics** | Track AI session quality and reduce slop |
| **policy-harmonization** | Sync AI guidance files across repos |

---

## 🧠 What Are These Skills For?

These skills teach AI coding agents the **Smart Assets development methodology**:

- **Epoch-based task management** - Organize work into logical groups with priorities and dependencies
- **Stigmergic collaboration** - Multiple AI agents coordinate through shared files (like ants with pheromones)
- **Multi-repo workflows** - Commit and push across many repos at once
- **Quality metrics** - Track signal-to-slop ratio to improve AI output quality

---

## 🔧 Manual Installation

### For Claude Code

```bash
mkdir -p .claude/skills
git clone https://github.com/SmartAssets-io/skills.git .claude/skills/smart-assets
```

### For Other Agents

Copy the skill folders to your project and reference in `AGENTS.md`.

---

## 🧬 Skill Structure

Each skill follows Anthropic's SKILL.md format:

```
/
├── epoch-task-management/
│   └── SKILL.md
├── stigmergic-collaboration/
│   └── SKILL.md
├── multi-repo-git/
│   └── SKILL.md
└── ...
```

---

## 📖 Related Resources

- [Smart Assets GitLab](https://gitlab.com/smart-assets.io)
- [OpenSkills CLI](https://github.com/numman-ali/openskills)
- [Anthropic Agent Skills](https://github.com/anthropics/skills)

---

## 📜 License

[Sovereign Source License (SSL) v0.2](LICENSE.md)

This project is licensed under the Sovereign Source License, which extends Apache 2.0 with optional ecosystem enhancements for sustainable open source development.
