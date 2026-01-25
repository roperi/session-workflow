# Session Workflow

A lightweight session management system for AI context continuity and structured work tracking.

**Status**: Production-ready (v2.1)  
**Location**: `.session/`

---

## Quick Start

```bash
# Development workflow (full 8-agent chain)
/session.start --issue 123
/session.start "Fix performance bug"

# Spike workflow (exploration, no PR)
/session.start --spike "Research caching options"

# Resume an active session
/session.start --resume

# Wrap a session (at end of work)
/session.wrap
```

**Note**: Use the `/session.*` prompts which call the underlying scripts. When consuming preflight or session-start JSON, use `repo_root` to resolve repo paths.

---

## Why Session Workflow?

When AI context windows reset, work continuity is lost. The session workflow solves this by:

1. **Tracking session state** - What's in progress, what's done
2. **Handoff notes** - Context for the next AI session
3. **Git hygiene** - Ensures clean state before session ends
4. **Project context** - Quick orientation for new sessions

---

## Workflow Types

| Workflow | Flag | Agent Chain | Use Case |
|----------|------|-------------|----------|
| **Development** | (default) | start → plan → task → execute → validate → publish → finalize → wrap | Features, bugs, anything needing PR |
| **Spike** | `--spike` | start → plan → task → execute → wrap | Research, exploration, prototyping |

**Both workflows include planning and task generation.** Spike only skips the PR-related steps (validate, publish, finalize).

---

## Session Types

| Type | Command | Use Case |
|------|---------|----------|
| **GitHub Issue** | `--issue 123` | Bugs, improvements, tasks with GitHub issues |
| **Speckit** | `--spec 001-feature` | Feature work using Speckit workflow |
| **Unstructured** | `"Goal description"` | Exploration, maintenance, ad-hoc work |

---

## Session Lifecycle

### Development Workflow
```
start → plan → task → execute → validate → publish → [MERGE PR] → finalize → wrap
```

### Spike Workflow
```
start → plan → task → execute → wrap
```

**⚠️ IMPORTANT for Development**: PR must be merged BEFORE finalize/wrap!

---

## Slash Commands

| Command | Purpose |
|---------|---------|
| `/session.start` | Initialize or resume a session |
| `/session.plan` | Create implementation plan and approach |
| `/session.task` | Generate detailed task list |
| `/session.execute` | Execute tasks with TDD |
| `/session.validate` | Quality checks before PR (development only) |
| `/session.publish` | Create/update pull request (development only) |
| `/session.finalize` | Post-merge issue management (development only) |
| `/session.wrap` | Document and close session |

---

## Arguments

### session.start

```bash
# Development (default)
/session.start --issue 123
/session.start --spec 001-feature
/session.start "Fix the bug in login"

# Spike
/session.start --spike "Explore WebSocket options"

# Resume
/session.start --resume
/session.start --resume --comment "Continue from task 5"
```

### All agents

- `--comment "text"` - Provide specific instructions
- `--resume` - Continue from where you left off
- `--force` - Skip workflow validation (use with caution)

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
│   └── session-wrap.sh
├── sessions/
│   └── YYYY-MM-DD-N/
│       ├── session-info.json
│       ├── state.json
│       ├── notes.md
│       └── tasks.md
└── docs/
    └── README.md
```

---

## Handoff Notes

The most important file is `notes.md`. Always fill in:

```markdown
## Summary
What was accomplished this session?

## Key Decisions
Decisions that affect future work

## Blockers/Issues
Problems encountered, unresolved issues

## For Next Session
- Current state: What's done and what's pending
- Next steps: Specific actions for next AI
- Context needed: Special context next AI should know
```

---

## Direct Script Usage

```bash
# Start session (JSON output for AI)
.session/scripts/bash/session-start.sh --json --issue 123
.session/scripts/bash/session-start.sh --json "Fix the bug"
.session/scripts/bash/session-start.sh --json --spike "Research"

# Wrap session
.session/scripts/bash/session-wrap.sh --json

# Check active session
cat .session/ACTIVE_SESSION
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

---

## Parallel Sessions (Multiple Agents)

The session workflow assumes **one active session per repository**. If you need to run concurrent sessions (e.g., one agent on backend, another on frontend), use **git worktree**.

### Why Worktree?

Each worktree has its own working directory with its own `.session/` folder, providing natural isolation with no code changes.

### Setup

```bash
# From your main project
cd ~/workspace/myproject

# Create worktrees for parallel work
git worktree add ../myproject-backend -b feature/backend-api
git worktree add ../myproject-frontend -b feature/frontend-ui

# Terminal 1: Backend session
cd ../myproject-backend
/session.start --issue 123

# Terminal 2: Frontend session
cd ../myproject-frontend
/session.start --issue 124
```

### Key Points

- Each worktree **must be on a different branch** (git requirement)
- Each worktree has independent `.session/` state
- Changes are visible across worktrees after commit (shared `.git`)
- Worktrees are lightweight (no full clone)

### Cleanup

```bash
# When done with a worktree
git worktree remove ../myproject-backend

# Or delete folder and prune
rm -rf ../myproject-backend
git worktree prune

# List active worktrees
git worktree list
```

### Alternative: Inside Project

You can also create worktrees inside your project (add `.worktrees/` to `.gitignore`):

```bash
git worktree add .worktrees/backend-fix feature/backend
```
