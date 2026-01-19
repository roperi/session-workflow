# Session Workflow

A lightweight session management system for AI context continuity and structured work tracking.

**Status**: Production-ready  
**Location**: `.session/`

---

## Quick Start

```bash
# Start a session for a GitHub issue
/session.start --issue 123

# Start a session for unstructured work
/session.start --goal 'Fix performance bug'

# Resume an active session
/session.start

# Wrap a session (at end of work)
/session.wrap
```

**Note**: Use the `/session.*` prompts which call the underlying scripts directly.

---

## Why Session Workflow?

When AI context windows reset, work continuity is lost. The session workflow solves this by:

1. **Tracking session state** - What's in progress, what's done
2. **Handoff notes** - Context for the next AI session
3. **Git hygiene** - Ensures clean state before session ends
4. **Project context** - Quick orientation for new sessions
5. **Operational tips** - Testing, git workflow, environment reminders

---

## Session Types

| Type | Command | Use Case |
|------|---------|----------|
| **GitHub Issue** | `--issue 123` | Bugs, improvements, tasks with GitHub issues |
| **Speckit** | `--spec 001-feature` | Feature work using Speckit workflow |
| **Unstructured** | `--goal "Description"` | Exploration, maintenance, ad-hoc work |

---

## Session Lifecycle

```
start → plan → execute → validate → publish → finalize → wrap
```

Manual handoffs:
- publish → finalize (after PR merge)
- finalize → wrap (user confirms)

Resume behavior:
- If a step was interrupted (state.json shows in_progress/starting), rerun that step with `--resume`.
- To resume an older session, run `/session.start --resume`.

### 1. Start (`/session.start`)

Creates or resumes a session:
- Creates session directory in `.session/sessions/YYYY-MM-DD-N/`
- Loads previous session context for continuity
- Outputs JSON with project context paths and operational tips

**Output files:**
- `session-info.json` - Session metadata (type, goal, timestamps)
- `state.json` - Progress tracking
- `notes.md` - Handoff notes (ALWAYS update this!)
- `tasks.md` - Task checklist (non-Speckit sessions only)

**JSON output includes:**
- `session` - Current session info and files
- `previous_session` - Handoff notes and incomplete tasks from last session
- `project_context` - Paths to constitution and technical context
- `tips` - Operational tips (testing, git workflow, environment)
- `instructions` - What to do next

### 2. Execute (your work)

During the session:
- Update `tasks.md` as you complete tasks: `- [ ]` → `- [x]`
- Update `notes.md` with key decisions and progress
- Commit code regularly
- Use `/session.execute` prompt for guidance

### 3. Wrap (`/session.wrap`)

Finalizes the session with validation:
- **HARD BLOCK**: Git must be clean (no uncommitted changes)
- **SOFT WARN**: Notes should have content
- **SOFT WARN**: "For Next Session" should be filled in

Post-wrap actions (handled by prompt):
- Update CHANGELOG.md if user-facing changes
- Update tasks.md with completion status
- Commit documentation changes
---

## File Structure

```
.session/
├── ACTIVE_SESSION              # Current session ID (sentinel file)
├── project-context/            # Shared context (read-only)
│   ├── constitution-summary.md # Quality standards quick reference
│   └── technical-context.md    # Stack and patterns
├── scripts/bash/               # Workflow scripts
│   ├── session-start.sh
│   ├── session-wrap.sh
│   └── session-common.sh
├── templates/
│   └── session-notes.md        # Template for notes
├── sessions/                   # Per-session data
│   └── YYYY-MM-DD-N/
│       ├── session-info.json
│       ├── state.json
│       ├── notes.md
│       └── tasks.md
└── docs/
    ├── README.md               # This file
    └── testing.md              # Test cases
```

---

## Prompts

AI guidance prompts are available in `.github/prompts/`:

| Prompt | Purpose |
|--------|---------|
| `/session.start` | Initialize or resume a session |
| `/session.plan` | Generate task list |
| `/session.execute` | Execute tasks with TDD focus |
| `/session.validate` | Run quality checks and tests |
| `/session.publish` | Create/update pull request |
| `/session.finalize` | Post-merge issue management |
| `/session.wrap` | Document and close session |

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

If needed, scripts can be called directly:

```bash
# Start session
.session/scripts/bash/session-start.sh --json --issue 123

# Wrap session
.session/scripts/bash/session-wrap.sh --json

# Check active session
cat .session/ACTIVE_SESSION
```

---

## Operational Tips (from JSON output)

### Before Starting
- Provide a brief summary of planned tasks before beginning work

### Before Pushing Code
```bash
# Run your project's lint and test commands
# Check .session/project-context/technical-context.md for specifics
```

### Testing
- Check project-specific test commands in technical-context.md
- Tail long output: `<test-command> 2>&1 | tail -50`
- Filter failures: `gh run view <id> --log-failed 2>&1 | grep -A 20 "FAIL"`

### Git Workflow
- **ALWAYS** work on feature branches, never directly on main
- **WAIT for CI** before merging PRs
- Use `[skip ci]` for docs-only commits

---

## Integration with Speckit

For Speckit features:
- Session tracks which spec you're working on
- Tasks come from `specs/{feature}/tasks.md` (not duplicated)
- Session provides notes for handoff between AI sessions

---

## Troubleshooting

### "Must specify --type, --issue, --spec, or --goal"
No active session exists and no arguments provided. Specify what you want to work on.

### "Git has uncommitted changes (BLOCKING)"
Commit or stash changes before wrapping:
```bash
git add -A && git commit -m "chore: work in progress"
/session.wrap
```

### "No active session"
Start a new session with `/session.start --issue 123` or similar.

---

## Related Documentation

- **Official Guide**: `docs/workflows/session-workflow.md`
- **Plan**: `docs/planning/session-workflow/session-workflow-plan-v2.md`
- **Tests**: `.session/docs/testing.md`
- **Constitution**: `.session/project-context/constitution-summary.md`
- **Technical Context**: `.session/project-context/technical-context.md`
