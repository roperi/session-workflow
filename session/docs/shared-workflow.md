---
description: Shared workflow rules for all session agents (reference only)
tools: []
---

# Session Workflow Common Rules

**Purpose**: Shared workflow rules for all session agents. This is a reference document, not a runnable agent.
**Reference-only**: Do not execute scripts or commands from this agent.

## ⚠️ CRITICAL: Read Technical Context First

**BEFORE running any commands**, every session agent MUST:
1. Run preflight to get repo_root and session context:
   ```bash
   .session/scripts/bash/session-preflight.sh --step <step> --json
   ```
2. Use `repo_root` from preflight output for ALL file operations (never assume `/home/project`).
3. Read `.session/project-context/technical-context.md` for environment, stack, commands.

### Key Things to Check:
1. **Project Stage**: poc, mvp, or production (affects strictness)
2. **Environment**: containerized (Docker) vs local
3. **Commands**: Test/build/lint commands specific to this project

### If Containerized:
```bash
# Run commands INSIDE containers, not locally
docker compose exec <service> <command>
```

### Common Mistakes to Avoid:
- ❌ Running `python`, `npm`, `go` directly if containerized
- ❌ Using paths like `/root/` (doesn't exist in most environments)
- ❌ Assuming local dependencies are installed
- ❌ Running wrap before PR is merged

## Project Stages

Sessions have a **stage** that affects validation strictness and documentation requirements.

| Stage | Constitution | Technical Context | Validation | Use Case |
|-------|--------------|-------------------|------------|----------|
| **poc** | Optional | Optional | Relaxed (warnings) | Experiments, spikes, early exploration |
| **mvp** | Required (brief OK) | Required (partial OK) | Standard | First working version, core features |
| **production** | Required (full) | Required (complete) | Strict | Production-ready, full quality gates |

### Stage Behavior by Agent

| Agent | poc | mvp | production |
|-------|-----|-----|------------|
| **session.plan** | Skip context validation | Warn if incomplete | Require complete context |
| **session.task** | Simple checklist OK | User stories encouraged | Full structure required |
| **session.validate** | Warnings only, proceed | Fail on errors, warn on style | All checks must pass |
| **session.execute** | WIP commits allowed | Standard commits | Conventional commits required |

### Checking Stage

```bash
# In any agent, check the session stage
STAGE=$(jq -r '.stage // "production"' "$SESSION_DIR/session-info.json")

case $STAGE in
    poc)
        echo "PoC mode: Relaxed validation"
        ;;
    mvp)
        echo "MVP mode: Standard validation"
        ;;
    production)
        echo "Production mode: Strict validation"
        ;;
esac
```

### Upgrading Stage

Projects can upgrade stage as they mature:
```bash
# Update session-info.json manually or start new session with new stage
/session.start --stage mvp --issue 123
```

## Workflow State Machine

The session workflow follows a defined state machine. Each step must complete before the next can begin.

**Development (8-agent chain)**: `start → plan → task → execute → validate → publish → finalize → wrap`

**Spike (5-agent chain)**: `start → plan → task → execute → wrap`

**Maintenance (3-agent chain)**: `start → execute → wrap`

```
START → PLAN → TASK → EXECUTE → VALIDATE → PUBLISH → [MERGE PR] → FINALIZE → WRAP
                                                          │                  │
                                                          └── Manual Step ───┘

Maintenance shortcut:
START → EXECUTE → WRAP
```

**⚠️ IMPORTANT**: PR must be merged BEFORE finalize/wrap (development workflow only)!

## Valid Transitions

| From State | Valid Next States |
|------------|-------------------|
| `none` | `plan`, `execute` |
| `start` | `plan`, `execute` |
| `plan` | `task`, `execute` |
| `task` | `execute` |
| `execute` | `validate`, `execute` (loop), `wrap` (maintenance) |
| `validate` | `publish`, `execute` (if fix needed) |
| `publish` | `finalize` |
| `finalize` | `wrap` |
| `wrap` | (terminal - session complete) |

## Optional Quality Agents

These agents are **not part of the main workflow chain**. They can be invoked at any time for quality checks:

| Agent | Purpose | Best Used |
|-------|---------|-----------|
| `/session.clarify` | Ask targeted questions to reduce ambiguity | Before `task` |
| `/session.analyze` | Cross-artifact consistency check (read-only) | After `task`, before `execute` |
| `/session.checklist` | Generate requirements quality checklists | Before `execute` or PR |

**Usage pattern:**
```
start → plan → [clarify?] → task → [analyze?] → execute → ...
                   ↑                    ↑
            Optional quality checks (not required)
```

These agents help reduce downstream rework by catching issues early.

## Step Status Values

Each workflow step has a status:

- **`in_progress`**: Step is currently running
- **`completed`**: Step finished successfully
- **`failed`**: Step finished with errors

## State Tracking Requirements

**Every session agent MUST:**

1. **ON ENTRY**: Mark step as `in_progress`
   ```bash
   source .session/scripts/bash/session-common.sh
   SESSION_ID=$(get_active_session)
   set_workflow_step "$SESSION_ID" "step_name" "in_progress"
   ```

2. **ON SUCCESS**: Mark step as `completed`
   ```bash
   set_workflow_step "$SESSION_ID" "step_name" "completed"
   ```

3. **ON FAILURE**: Mark step as `failed`
   ```bash
   set_workflow_step "$SESSION_ID" "step_name" "failed"
   ```

## Interrupted Session Detection

If a step has status `in_progress` when a new CLI session starts, the previous session was interrupted.

**Detection:**
```bash
WORKFLOW_STATE=$(get_workflow_step "$SESSION_ID")
CURRENT_STEP=$(echo "$WORKFLOW_STATE" | jq -r '.current_step')
STEP_STATUS=$(echo "$WORKFLOW_STATE" | jq -r '.step_status')

if [[ "$STEP_STATUS" == "in_progress" ]]; then
    echo "⚠️ Previous session was interrupted during: $CURRENT_STEP"
fi
```

**Recovery guidance:**
- If interrupted during `task` → run `/session.task --resume`
- If interrupted during `execute` → run `/session.execute --resume`
- If interrupted during `validate` → run `/session.validate --resume`
- If interrupted during other steps → run that step again

## Transition Validation

Before running, agents should validate the transition is allowed:

```bash
# Check if transition to this step is valid
if ! check_workflow_transition "$SESSION_ID" "finalize"; then
    echo "Cannot run finalize - previous step not complete"
    exit 1
fi
```

## State Storage

Workflow state is stored in `state.json`:

```json
{
  "current_step": "task",
  "step_status": "in_progress",
  "step_started_at": "2026-01-18T10:30:00Z",
  "step_updated_at": "2026-01-18T10:30:00Z"
}
```

## Usage by Agents

All session agents should reference this document:

```markdown
**IMPORTANT**: Read `.session/docs/shared-workflow.md` for shared workflow rules.
```

## Why This Matters

This state tracking enables:

1. **Session continuity** - Resume interrupted work across CLI restarts
2. **Data protection** - Prevent accidental data loss from skipped steps
3. **Clear guidance** - Users know what step to run next
4. **Audit trail** - Track session progress over time
