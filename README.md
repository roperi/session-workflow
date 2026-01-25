# Session Workflow

**📝 Changelog**: [CHANGELOG.md](CHANGELOG.md)

This is the single source of truth for session workflow documentation.

**Compatibility**:
- ✅ Tested with **GitHub Copilot CLI**
- ⚠️ Other CLIs (Claude Code, Gemini CLI) are unverified and may require adjustments

**Spec-kit support**:
- ✅ Integrates with **GitHub Spec Kit** specs and tasks  
  https://github.com/github/spec-kit

---

## Table of Contents

1. [Overview](#overview)
2. [Installation](#installation)
3. [Quick Start](#quick-start)
4. [Workflow Types](#workflow-types)
5. [Project Stages](#project-stages)
6. [Agent Chain](#agent-chain)
7. [Agent Responsibilities](#agent-responsibilities)
8. [Optional Quality Agents](#optional-quality-agents)
9. [Arguments](#arguments)
10. [Workflow Examples](#workflow-examples)
11. [Session Lifecycle](#session-lifecycle)
12. [File Structure](#file-structure)
13. [Troubleshooting](#troubleshooting)

---

## Overview

When AI context windows reset, work continuity is lost. Session workflow solves this with:

1. **Session tracking** - What's in progress, what's done
2. **Handoff notes** - Context for the next AI session
3. **8-agent chain** - Structured workflow with automatic handoffs
4. **Git hygiene** - Ensures clean state before session ends

**Agent Chain**: `start → plan → task → execute → validate → publish → finalize → wrap`

---

## Installation

```bash
# Quick install
curl -sSL https://raw.githubusercontent.com/roperi/session-workflow/main/install.sh | bash

# Or clone and run
git clone https://github.com/roperi/session-workflow.git
cd your-project
../session-workflow/install.sh
```

**What gets installed:**
- `.github/agents/session.*.agent.md` - AI agent definitions
- `.github/prompts/session.*.prompt.md` - Slash command links
- `.session/` - Scripts, templates, project context
- `AGENTS.md` - AI bootstrap file (created if missing)
- `.github/copilot_instructions.md` - Copilot config (created if missing)

**Post-install:**
1. Customize `.session/project-context/technical-context.md` with your stack
2. Customize `.session/project-context/constitution-summary.md` with quality standards
3. Review `AGENTS.md` for project-specific additions

---

## Quick Start

```bash
# Development workflow (full chain)
/session.start --issue 123
/session.start "Fix performance bug"

# Spike (exploration, no PR)
/session.start --spike "Explore Redis caching"

# Resume interrupted work
/session.start --resume
/session.execute --resume --comment "Continue from task 5"

# After PR merged
/session.finalize

# End session
/session.wrap
```

**Note**: When consuming preflight or session-start JSON, use `repo_root` to resolve repo paths.

---

## Workflow Types

### 1. Development (default)

**Chain**: `start → plan → task → execute → validate → publish → finalize → wrap`

Use for:
- Feature development
- Bug fixes
- Work that needs PR review

```bash
/session.start --issue 123
/session.start "Add caching layer"
```

### 2. Spike

**Chain**: `start → plan → task → execute → wrap`

Use for:
- Research and exploration
- Prototypes
- Work that may be discarded

```bash
/session.start --spike "Benchmark Redis vs Memcached"
```

**Note**: Spike still includes planning and task generation - it only skips PR steps (validate, publish, finalize).

---

## Project Stages

The `--stage` flag controls validation strictness and documentation requirements.

| Stage | Constitution | Technical Context | Validation | Use Case |
|-------|--------------|-------------------|------------|----------|
| **poc** | Optional | Optional | Relaxed (warnings) | PoCs, spikes, early exploration |
| **mvp** | Required (brief OK) | Required (partial OK) | Standard | First working version, core features |
| **production** | Required (full) | Required (complete) | Strict (default) | Production-ready, full quality gates |

### Usage

```bash
# PoC: PoC work, don't know the stack yet
/session.start --stage poc "Prototype auth flow"

# MVP: Building first version, core requirements defined
/session.start --stage mvp --issue 123

# Production: Full quality (default, flag optional)
/session.start --issue 456
/session.start --stage production --issue 456
```

### Stage Behavior

**poc** (Proof of Concept):
- Constitution/technical-context files can be empty stubs
- Validation reports warnings but never blocks
- Simple task checklists OK (no user stories required)
- WIP commits allowed

**mvp** (Minimum Viable Product):
- Core sections of constitution/technical-context required
- Validation fails on errors, warns on style issues
- User stories encouraged but not enforced
- Standard commit messages

**production** (default):
- Full constitution and technical-context required
- All validation checks must pass
- Full task structure with dependencies
- Conventional commits required

### Upgrading Stage

As your project matures, upgrade the stage:
```bash
# Started as PoC, now building MVP
/session.start --stage mvp --issue 123

# MVP proven, now going to production
/session.start --stage production --issue 456
```

---

## Agent Chain

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  START   │───▶│   PLAN   │───▶│   TASK   │───▶│ EXECUTE  │───▶│ VALIDATE │
│          │    │          │    │          │    │          │    │          │
│ Init     │    │ Approach │    │ Generate │    │ TDD      │    │ Quality  │
│ Context  │    │ Strategy │    │ Tasks    │    │ Implement│    │ Tests    │
└──────────┘    └──────────┘    └──────────┘    └──────────┘    └──────────┘
   (auto)          (auto)          (auto)          (auto)          (auto)
                                                                      │
                                                                      ▼
┌──────────┐    ┌──────────┐    ┌──────────┐                    ┌──────────┐
│   WRAP   │◀───│ FINALIZE │◀───│ PUBLISH  │◀───────────────────┤          │
│          │    │          │    │          │                    │          │
│ Document │    │ Close    │    │ Create   │                    │          │
│ Cleanup  │    │ Issues   │    │ PR       │                    │          │
└──────────┘    └──────────┘    └──────────┘                    └──────────┘
                  (manual)        (manual)
```

**Development workflow** uses all 8 agents.

**Spike workflow** uses: `start → plan → task → execute → wrap` (skips validate, publish, finalize)

**Automatic handoffs** (`send: true`):
- start → plan → task → execute → validate → publish

**Manual handoffs** (`send: false`):
- publish → finalize (user monitors CI, merges PR)
- finalize → wrap (user confirms)

---

## Agent Responsibilities

### session.start
- Run `session-start.sh`
- Load project context
- Create feature branch
- Review previous session notes
- **Handoff**: → session.plan (auto)

### session.plan
- Create implementation plan and approach
- Analyze requirements and identify components
- Or reference existing Speckit plan
- **Handoff**: → session.task (auto)

### session.task
- Generate detailed task breakdown
- Organize by user story with priorities
- Add parallelization markers [P] and dependencies
- Use tasks-template.md structure
- **Handoff**: → session.execute (auto)

### session.execute
- Single-task focus
- TDD: test → implement → verify
- Commit after each task
- **Handoff**: → session.validate (development) or session.wrap (spike)

### session.validate
- Run lint, tests
- Check git state
- Offer fixes if failures
- **Stage-aware**: poc=warnings only, mvp=standard, production=strict
- **Handoff**: → session.publish (auto if pass)
- **Only for**: development workflow

### session.publish
- Create or update PR
- Link issues
- **Handoff**: → session.finalize (manual)
- **Only for**: development workflow

### session.finalize
- Validate PR is merged
- Close issues
- Update parent issues
- **Handoff**: → session.wrap (manual)
- **Only for**: development workflow

### session.wrap
- Update session notes
- Update CHANGELOG.md
- Clean up merged branches
- Mark session complete
- **No handoff** (end of chain)

---

## Optional Quality Agents

These agents are **not part of the main 8-agent chain**. Use them for quality checks at any time.

### session.clarify
- Ask up to 5 targeted questions to reduce ambiguity
- Records clarifications in session notes
- **Best used**: Before `/session.task` when requirements are vague
- **Inspired by**: Speckit's `/speckit.clarify`

### session.analyze
- Cross-artifact consistency and coverage analysis
- **STRICTLY READ-ONLY** - produces report only
- **Best used**: After `/session.task`, before `/session.execute`
- **Inspired by**: Speckit's `/speckit.analyze`

### session.checklist
- Generate requirements quality checklists ("unit tests for English")
- Domain-specific: UX, API, security, performance
- **Best used**: Before implementation or PR review
- **Inspired by**: Speckit's `/speckit.checklist`

**Usage pattern:**
```
start → plan → [clarify?] → task → [analyze?] → [checklist?] → execute → ...
                   ↑                    ↑              ↑
            Optional quality checks (reduce downstream rework)
```

---

## Arguments

### session.start

```bash
# Session types
/session.start --issue 123           # GitHub issue
/session.start --spec 001-feature    # Speckit feature
/session.start "Fix the bug"         # Unstructured (goal as positional arg)

# Workflow selection
/session.start --spike "Research"    # Spike workflow

# Resume
/session.start --resume
/session.start --resume --comment "Continue from task 5"
```

### All agents

- `--comment "text"` - Provide specific instructions
- `--resume` - Continue from where you left off
- `--force` - Skip workflow validation (use with caution)

**Support matrix:**

| Agent | --comment | --resume |
|-------|-----------|----------|
| session.start | ✅ | ✅ |
| session.plan | ✅ | ✅ |
| session.task | ✅ | ✅ |
| session.execute | ✅ | ✅ |
| session.validate | ✅ | ⚠️ (re-runs failed only) |
| session.publish | ✅ | ✅ |
| session.finalize | ✅ | N/A |
| session.wrap | ✅ | N/A |

---

## Workflow Examples

### Example 1: Bug Fix (Development)

```bash
# Start
/session.start --issue 456

# Auto-chains through: plan → task → execute → validate → publish
# You interact at each step

# After PR merged
/session.finalize

# Document and close
/session.wrap
```

### Example 2: Research (Spike)

```bash
/session.start --spike "Research WebSocket vs SSE"

# Work through exploration
# No planning, no PR

/session.wrap  # Document findings
```

### Example 3: Resuming After Interruption

```bash
# Started working, pressed ESC mid-task
/session.execute --resume --comment "Continue from task 7"
```

---

## Session Lifecycle

### Start
Creates:
- `session-info.json` - Metadata
- `state.json` - Progress tracking
- `notes.md` - Handoff notes
- `tasks.md` - Task checklist

### During
Update regularly:
- `tasks.md` - Mark completed: `[ ]` → `[x]`
- `notes.md` - Key decisions, blockers

### Wrap
- Updates CHANGELOG.md
- Commits documentation
- Cleans merged branches
- Clears ACTIVE_SESSION

---

## File Structure

```
.session/
├── ACTIVE_SESSION              # Current session ID
├── project-context/
│   ├── constitution-summary.md # Quality standards
│   └── technical-context.md    # Stack, commands
├── scripts/bash/
│   ├── session-common.sh
│   ├── session-start.sh
│   ├── session-wrap.sh
│   └── ...
├── templates/
│   └── session-notes.md
├── sessions/
│   └── YYYY-MM-DD-N/
│       ├── session-info.json
│       ├── state.json
│       ├── notes.md
│       └── tasks.md
└── docs/
    ├── README.md
    ├── testing.md
    └── shared-workflow.md

.github/
├── agents/
│   └── session.*.agent.md
└── prompts/
    └── session.*.prompt.md
```

---

## Troubleshooting

### "Stale session detected"

Previous session wasn't closed properly.

```bash
rm .session/ACTIVE_SESSION
/session.start --issue 123
```

### "Git has uncommitted changes (BLOCKING)"

```bash
git add -A && git commit -m "wip"
/session.wrap
```

### "No active session"

```bash
/session.start --issue 123
```

### Interrupted Session / CLI Restart

If the CLI crashes or is killed mid-workflow, the next invocation detects this:

```
⚠️ INTERRUPTED SESSION DETECTED
Previous session was interrupted during: validate

RECOMMENDED ACTION:
Run: /session.validate --resume
```

**Recovery:**
```bash
# Resume the interrupted step
/session.[step] --resume

# Or force skip (may cause data loss)
/session.[next-step] --force
```
