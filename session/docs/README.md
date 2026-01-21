# Session Workflow

A lightweight session management system for AI context continuity and structured work tracking.

**Status**: Production-ready (v2.1)  
**Location**: `.session/`

---

## Quick Start

```bash
# Development workflow (full 7-agent chain)
/session.start --issue 123
/session.start "Fix performance bug"

# Spike workflow (exploration, no PR)
/session.start --spike "Research caching options"

# Resume an active session
/session.start --resume

# Wrap a session (at end of work)
/session.wrap
```

**Note**: Use the `/session.*` prompts which call the underlying scripts.

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
| **Development** | (default) | start → plan → execute → validate → publish → finalize → wrap | Features, bugs, anything needing PR |
| **Spike** | `--spike` | start → execute → wrap | Research, exploration, prototyping |

**No auto-detection.** User explicitly chooses `--spike` when needed; otherwise development is assumed.

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
start → plan → execute → validate → publish → [MERGE PR] → finalize → wrap
```

### Spike Workflow
```
start → execute → wrap
```

**⚠️ IMPORTANT for Development**: PR must be merged BEFORE finalize/wrap!

---

## Slash Commands

| Command | Purpose |
|---------|---------|
| `/session.start` | Initialize or resume a session |
| `/session.plan` | Generate task list (development only) |
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

## Version History

### 2.1.0 (2026-01)
- **BREAKING**: Simplified to 2 workflows: development (default) and spike
- **BREAKING**: Removed `--advisory`, `--experiment`, `--workflow`, `--goal`
- Goal is now a positional argument: `/session.start "Fix the bug"`
- Renamed `--experiment` to `--spike` for clarity
- Removed auto-detection ("smart" workflow) - user explicitly chooses

### 2.0.0 (2026-01)
- Added workflow types (development, advisory, experiment, smart)
- Added `--resume` and `--comment` flags
- Added session continuity across CLI restarts

### 1.0.0 (2025-12)
- Initial release
