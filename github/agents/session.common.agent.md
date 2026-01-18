# Session Workflow Common Rules

**Purpose**: Shared workflow rules for all session agents. This is a reference document, not a runnable agent.

## Workflow State Machine

The session workflow follows a defined state machine. Each step must complete before the next can begin.

```
┌────────┐   ┌────────┐   ┌─────────┐   ┌──────────┐   ┌─────────┐   ┌──────────┐   ┌────────┐
│ START  │──▶│  PLAN  │──▶│ EXECUTE │──▶│ VALIDATE │──▶│ PUBLISH │──▶│ FINALIZE │──▶│  WRAP  │
└────────┘   └────────┘   └─────────┘   └──────────┘   └─────────┘   └──────────┘   └────────┘
```

## Valid Transitions

| From State | Valid Next States |
|------------|-------------------|
| `none` | `start` |
| `start` | `plan`, `execute` |
| `plan` | `execute` |
| `execute` | `validate`, `execute` (loop for more tasks) |
| `validate` | `publish`, `execute` (if fix needed) |
| `publish` | `finalize` |
| `finalize` | `wrap` |
| `wrap` | (terminal - session complete) |

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
- If interrupted during `validate` → run `/session.validate --resume`
- If interrupted during `execute` → run `/session.execute --resume`
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
  "current_step": "validate",
  "step_status": "in_progress",
  "step_started_at": "2026-01-18T10:30:00Z",
  "step_updated_at": "2026-01-18T10:30:00Z"
}
```

## Usage by Agents

All session agents should reference this document:

```markdown
**IMPORTANT**: Read `.github/agents/session.common.agent.md` for shared workflow rules.
```

## Why This Matters

This state tracking enables:

1. **Session continuity** - Resume interrupted work across CLI restarts
2. **Data protection** - Prevent accidental data loss from skipped steps
3. **Clear guidance** - Users know what step to run next
4. **Audit trail** - Track session progress over time
