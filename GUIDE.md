# Session Workflow Guide

**Version**: 2.0.0  
**Status**: Production-ready

This is the single source of truth for session workflow. It consolidates all documentation into one reference.

---

## Table of Contents

1. [Overview](#overview)
2. [Installation](#installation)
3. [Quick Start](#quick-start)
4. [Workflow Types](#workflow-types)
5. [Agent Chain](#agent-chain)
6. [Agent Responsibilities](#agent-responsibilities)
7. [Arguments](#arguments)
8. [Workflow Examples](#workflow-examples)
9. [Session Lifecycle](#session-lifecycle)
10. [File Structure](#file-structure)
11. [Troubleshooting](#troubleshooting)

---

## Overview

When AI context windows reset, work continuity is lost. Session workflow solves this with:

1. **Session tracking** - What's in progress, what's done
2. **Handoff notes** - Context for the next AI session
3. **7-agent chain** - Structured workflow with automatic handoffs
4. **Git hygiene** - Ensures clean state before session ends

**Agent Chain**: `start → plan → execute → validate → publish → finalize → wrap`

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

# Unstructured work
/session.start --goal "Fix performance bug"

# Experiment (no PR)
/session.start --experiment --goal "Test Redis caching"

# Quick question (no code)
/session.start --advisory --goal "How should I structure the API?"

# Resume interrupted work
/session.execute --resume

# Provide guidance
/session.plan --comment "Focus only on the API changes"

# After PR merged
/session.finalize

# End session
/session.wrap
```

---

## Workflow Types

### 1. Development (default)

**Chain**: `start → plan → execute → validate → publish → finalize → wrap`

Use for:
- Feature development
- Bug fixes
- Work that needs PR review

```bash
/session.start --issue 123
/session.start --development --goal "Add caching"
```

### 2. Advisory

**Chain**: `start → wrap`

Use for:
- Quick questions
- Code reviews
- Architecture discussions

```bash
/session.start --advisory --goal "Review auth approach"
```

### 3. Experiment

**Chain**: `start → execute → wrap`

Use for:
- Prototypes and spikes
- Performance testing
- Work that may be discarded

```bash
/session.start --experiment --goal "Benchmark Redis vs Memcached"
```

### 4. Smart (auto-detect)

**Chain**: Adaptive based on activity

- Creates tasks → upgrades to Development
- Makes commits → upgrades to Experiment
- Neither → remains Advisory

```bash
/session.start --goal "Investigate slow API"
```

---

## Agent Chain

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  START   │───▶│   PLAN   │───▶│ EXECUTE  │───▶│ VALIDATE │
│          │    │          │    │          │    │          │
│ Init     │    │ Tasks    │    │ TDD      │    │ Quality  │
│ Context  │    │ Generate │    │ Implement│    │ Tests    │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
   (auto)          (auto)          (auto)          (auto)
                                                      │
                                                      ▼
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│   WRAP   │◀───│ FINALIZE │◀───│ PUBLISH  │◀───┤          │
│          │    │          │    │          │    │          │
│ Document │    │ Close    │    │ Create   │    │          │
│ Cleanup  │    │ Issues   │    │ PR       │    │          │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
                  (manual)        (manual)
```

**Automatic handoffs** (`send: true`):
- start → plan → execute → validate → publish

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
- Generate TDD-first task list
- Or reference existing Speckit tasks
- **Handoff**: → session.execute (auto)

### session.execute
- Single-task focus
- TDD: test → implement → verify
- Commit after each task
- **Handoff**: → session.validate (auto)

### session.validate
- Run lint, tests
- Check git state
- Offer fixes if failures
- **Handoff**: → session.publish (auto if pass)

### session.publish
- Create or update PR
- Link issues
- **Handoff**: → session.finalize (manual)

### session.finalize
- Validate PR is merged
- Close issues
- Update parent issues
- **Handoff**: → session.wrap (manual)

### session.wrap
- Update session notes
- Update CHANGELOG.md
- Clean up merged branches
- Mark session complete
- **No handoff** (end of chain)

---

## Arguments

All agents support these flags:

### `--comment "text"`

Provide specific instructions to the agent.

```bash
/session.plan --comment "Only plan the API changes"
/session.execute --comment "Skip task 3, already done"
/session.validate --comment "Focus on unit tests only"
```

### `--resume`

Continue from where you left off (after ESC interruption).

```bash
/session.execute --resume
/session.execute --resume --comment "Continue from task 5"
```

**Support matrix:**

| Agent | --comment | --resume |
|-------|-----------|----------|
| session.start | ✅ | ✅ |
| session.plan | ✅ | ✅ |
| session.execute | ✅ | ✅ |
| session.validate | ✅ | ⚠️ (re-runs failed only) |
| session.publish | ✅ | ✅ |
| session.finalize | ✅ | N/A |
| session.wrap | ✅ | N/A |

---

## Workflow Examples

### Example 1: Bug Fix

```bash
# Start
/session.start --issue 456

# Auto-chains through: plan → execute → validate → publish
# You interact at each step, providing "pass" or fixing issues

# After PR merged
/session.finalize

# Document and close
/session.wrap
```

### Example 2: Quick Question

```bash
/session.start --advisory --goal "Best approach for rate limiting?"

# AI provides guidance
# Session auto-wraps
```

### Example 3: Experiment

```bash
/session.start --experiment --goal "Test WebSocket vs SSE"

# Work through experiments
# No planning, no PR

/session.wrap  # Document findings
```

### Example 4: Resuming After Interruption

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
    └── testing.md

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

### Agent creates unexpected files

Agent prompts have explicit file allowlists. If this happens:
1. Delete the unexpected file
2. Report the issue so the agent prompt can be fixed

### Agent reports fake test results

Agent prompts require actual command execution. If fabrication occurs:
1. Re-run `/session.validate`
2. Report the issue so anti-hallucination rules can be strengthened

---

## Version History

### 2.0.0 (2026-01)
- Added workflow types (development, advisory, experiment, smart)
- Added `--resume` and `--comment` flags
- Added anti-hallucination rules to session.validate
- Added file allowlist to session.wrap
- Added remote branch cleanup with merge safety check
- Added AGENTS.md and copilot_instructions.md bootstrap

### 1.0.0 (2025-12)
- Initial release
- 7-agent chain
- Basic session tracking
