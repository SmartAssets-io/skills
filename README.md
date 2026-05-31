# Smart Assets Skills

**Operational agent skills for AI-assisted development workflows**

[OpenSkills](https://github.com/numman-ali/openskills)-compatible skill collection with bundled scripts for epic-based task management, multi-agent coordination, multi-repo git operations, and Smart Asset creation. Works with Claude Code, Cursor, Windsurf, Aider, and any agent that reads `AGENTS.md`.

<!-- badges-start -->
[![OpenSkills](https://img.shields.io/badge/OpenSkills-compatible-blue)](https://github.com/numman-ali/openskills)
[![Skills](https://img.shields.io/badge/skills-29-brightgreen)](./)
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
| **agent-monitor** | Launch a tmux-based display for monitoring parallel agent teams with real-time dashboard and stigmergic file watchers |
| **agent-team** | Launch a coordinated multi-agent Claude Code team with orchestrator and workers in tmux |
| **asset-create** | Create, initialize, and synchronize Smart Asset schemas and repository structure using SAIntrinsics master schema |
| **cbc** | Identify mission-critical (CbC-mandatory) code in a change, discharge its correctness claims through a pluggable verifier, record the evidence, and gate completion on undischarged claims |
| **cbc-review** | Review the codebase for mission-critical files and propose cbc=mandatory .gitattributes tags for human ratification |
| **cbc-scaffold** | Initialize CbC evidence/claim scaffolding and apply scanner-proposed cbc=mandatory git-attribute tags |
| **cbc-verify** | Verify, inspect, discharge, or waive CbC claims for cbc=mandatory artifacts using the evidence ledger |
| **design-component** | Generate a single UI component (button, card, form, navigation, ...) fully styled to the Smart Assets design system. |
| **design-export** | Export a design session for handoff — bundle the image(s), a design spec (tokens + prompts + version history), a local HTML preview, and an archive. |
| **design-iterate** | Conversationally refine a generated design ("make it more X"), tracking versions and history in a design session. |
| **design-wireframe** | Generate a low-fidelity layout wireframe from a natural-language description, using the Smart Assets design system. |
| **epic-hygiene** | Scan task tracking files for epic completion status and perform hygiene operations (archiving, cleanup, validation) |
| **epic-review** | Preview and summarize epics for high-level review of scope and progress before diving into implementation |
| **git-commit** | Quick commit changes (asks about untracked files, auto-generates message or uses provided one) |
| **git-push** | Push unpushed commits across all repositories in the workspace |
| **loop** | Repeatedly run a target Smart Assets skill or prompt alias until it reports completion, no remaining work, a blocker, or the iteration limit is reached |
| **review-codebase** | Surface architectural friction and propose deepening candidates after ratifying or bootstrapping a load-bearing project Glossary.md. Insists on a consistent glossary as a precondition for any review. |
| **review-identify-critical** | Scan the codebase for mission-critical (CbC-mandatory) files and propose cbc=mandatory .gitattributes tags for human ratification |
| **review-multi** | Perform multi-agent code review using multiple LLM providers with consensus-based aggregation posted to GitHub PR or GitLab MR |
| **spec-flow** | Create, link, and synchronize user flows in docs/User-Flows.md with bi-directional links to stories and epics; emits framework-agnostic test specs for integration-test authoring |
| **spec-story** | Create, link, and synchronize user stories with epics providing bi-directional linking between UserStories.md and ToDos.md |
| **sync-repos** | Synchronize conventions and policies across all repositories in the workspace with branch consistency enforcement |
| **sync-sa-framework** | Synchronize policies, approaches, and conventions across repositories by harmonizing with gitlab-profile standards |
| **task-complete** | Mark a task or epic complete with integrity reporting. Runs the user-flow chain walker, stamps any completion_gaps into YAML, and flips status. |
| **task-implement** | Begin implementation of the next task supporting both IPC and stigmergic coordination with epic-aware progress tracking |
| **task-next** | Review project task tracking and stigmergic signals to identify and explain the next task to work on |
| **task-tdd** | Walk one test-driven development cycle (RED then GREEN, optionally Refactor while GREEN). Single-cycle-per-invocation by design so /loop /tdd composes safely. Reads docs/tdd-plans/<scope>-<ts>.md as the running behavior checklist and may be invoked standalone or as a follow-on to /review-codebase Phase 3 acceptance. |
| **task-work** | Launch the todo-task-executor agent to systematically work through remaining tasks using stigmergic coordination |
| **util-version** | Show git commit hash and date for workflow tools and current repository |

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
