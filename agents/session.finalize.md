---
name: session-finalize
description: Close GitHub issues and sync task progress after a pull request is merged — run after PR merge, before session.wrap
tools: ["*"]
---

# session.finalize

**Purpose**: Post-merge issue management and task completion tracking.

**IMPORTANT**: Read `.session/docs/shared-workflow.md` for shared workflow rules.

## ⛔ SCOPE BOUNDARY

**This agent ONLY handles post-merge issue management. It does NOT:**
- ❌ Write CHANGELOG entries (that's `session.wrap`)
- ❌ Create session documentation or summaries (that's `session.wrap`)
- ❌ Merge PRs (that should already be done)
- ❌ Run validation or create PRs (earlier steps)

**Actions**: Close issues, clean up branches, sync task status — nothing else.

**Note**: When invoked directly by the user (not as a sub-agent), this agent also orchestrates Phase 3 by invoking `session.retrospect` after finalize (which then handles handoff to `session.wrap`) — see Handoff.

## User Input

```text
$ARGUMENTS
```

**Argument Support**:
- `--comment "text"`: Special finalize instructions (e.g., "Skip parent issue update")
- `--force`: Skip workflow validation and safety checks (use with caution)

**Behavior**:
- **`--resume` not applicable**: This is a one-shot operation post-merge
- **If `--comment` provided**: 
  - May skip certain finalize steps per instruction
  - Use for edge cases or special handling
- **Default**: Full finalize workflow with safety checks

## ⚠️ CRITICAL: Workflow State Tracking

**ON ENTRY** — run preflight (validates transition, marks step `in_progress`):
```bash
.session/scripts/bash/session-preflight.sh --step finalize --json
```

⛔ **STOP HERE** until you receive script output. Do NOT proceed without it.

**ON EXIT** — run postflight (marks step `completed`, outputs valid next steps):
```bash
.session/scripts/bash/session-postflight.sh --step finalize --json
```

### Additional Pre-Checks (RUN FIRST)

**BEFORE doing anything else**, check if the workflow state allows finalization:

```bash
source .session/scripts/bash/session-common.sh
SESSION_ID=$(get_active_session)

# Check workflow state
WORKFLOW_STATE=$(get_workflow_step "$SESSION_ID")
CURRENT_STEP=$(echo "$WORKFLOW_STATE" | jq -r '.current_step // "none"')
STEP_STATUS=$(echo "$WORKFLOW_STATE" | jq -r '.step_status // "none"')

echo "Current step: $CURRENT_STEP, Status: $STEP_STATUS"
```

**IF previous step is still `in_progress`:**
```
⚠️ INTERRUPTED SESSION DETECTED

The previous session was interrupted during: [step_name]
This typically happens when:
- CLI was killed/restarted mid-workflow
- Process crashed during [step_name]

REQUIRED ACTION:
Run `session.[step_name] --resume` to complete the interrupted step first.

Cannot proceed with finalize until previous step completes.
```

**IF previous step is `validate` or earlier (not `publish` or `review`):**
```
⚠️ WORKFLOW SEQUENCE ERROR

Cannot run finalize - previous steps not complete.
Current state: [step] ([status])

The workflow sequence is:
  start → plan → execute → validate → publish → [review] → finalize → wrap

REQUIRED ACTION:
Run the next step in sequence: session.[next_step]
```

**Only proceed if:**
- `current_step` is `publish` or `review` AND `step_status` is `completed`
- OR user passed `--force` flag

## ⚠️ CRITICAL: Pre-Flight Safety Checks

**AFTER workflow state check passes**, verify working directory state:

### Check 1: Uncommitted Changes

```bash
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "⚠️ WARNING: Uncommitted changes detected"
    git status --short
    
    echo ""
    echo "These changes are NOT in the merged PR."
    echo "Options:"
    echo "  1. Commit and push these changes (recommended)"
    echo "  2. Stash changes: git stash"  
    echo "  3. Discard changes: git checkout ."
    echo "  4. Continue anyway with --force"
    
    # STOP - do not proceed without user decision
fi
```

### Check 2: Branch State

```bash
CURRENT_BRANCH=$(git branch --show-current)
PR_NUMBER=$(detect_existing_pr)

if [[ -n "$PR_NUMBER" ]]; then
    PR_MERGED=$(check_pr_merged "$PR_NUMBER" && echo "true" || echo "false")
    
    if [[ "$PR_MERGED" != "true" ]]; then
        echo "⚠️ PR #$PR_NUMBER is not merged yet"
        echo "Please merge the PR before running finalize"
        exit 1
    fi
fi
```

### Check 3: Confirm Critical Files Present

```bash
# Verify key session files exist
SESSION_DIR=".session/sessions/$(cat .session/ACTIVE_SESSION 2>/dev/null)"
if [[ ! -f "$SESSION_DIR/session-info.json" ]]; then
    echo "⚠️ Session info not found - session may not have been started properly"
fi
```

**Mark step as in_progress ONLY after all checks pass:**
```bash
set_workflow_step "$SESSION_ID" "finalize" "in_progress"
```

## Responsibilities

### 1. Merge Validation
- Verify PR is actually merged before proceeding
- Error if PR not merged (user must merge first)


### 1.5. Workflow-Specific Behavior

**NEW (Schema v2.0)**: session.finalize handles all workflows but behavior varies:

```bash
# Source common functions
source .session/scripts/bash/session-common.sh

# Detect workflow
WORKFLOW=$(detect_workflow "$SESSION_ID")
echo "Workflow: $WORKFLOW"

case "$WORKFLOW" in
    development)
        echo "✓ Development workflow - will update parent issues"
        ;;
    spike)
        echo "✓ Spike workflow - minimal issue updates"
        ;;
esac
```

**Behavior by workflow**:
- **development**: Full issue management (close phase, update parent, sync tasks)
- **spike**: Minimal (document findings, no formal issue closure)

**All workflows**: Can invoke this agent for issue tracking.

### 2. Issue Management

**ALWAYS update issue BODY, not just comments.**

#### For Regular Issues:
- Update issue body with completion summary
- Close the issue
- Add final comment explaining closure

### 3. PR Updates

**Update PR description** with completion status.

**Add comment to PR:**
```
Work complete. All tasks finished.
```
...
## Chaining & Handoff

**MANDATORY**: Run postflight to mark this step complete and get next steps:
```bash
.session/scripts/bash/session-postflight.sh --step finalize --json
```

### Transition Protocol
1. Parse the `valid_next_steps` from the postflight JSON output.
2. Announce completion and suggest the next command(s).
3. **Invoke the next step** using your tool's native mechanism (e.g., slash command, `@agent`, or sub-agent task) if in `--auto` mode. Otherwise, guide the user to the next step.

**Tool-Specific Invocation Examples:**
- **GitHub Copilot**: `task(agent_type: "session.retrospect", prompt: "...")`
- **Claude Code**: `/session.retrospect`
- **Gemini CLI**: Activate sub-agent or skill `session.retrospect`

⛔ Do NOT perform the work of the next agent yourself.

## Usage

```bash
session.finalize
```

Invoke after:
1. PR has been merged to main (validated by script)
2. CI checks have passed
3. Ready to close issues and update tracking

## Example Output

```
✅ Session finalized and wrapped

Issues: Closed #659, updated parent #654
Tasks: 47 synced
Branches: Cleaned
Session: Documented and archived
```
