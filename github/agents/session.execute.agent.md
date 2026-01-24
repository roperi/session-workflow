---
description: Execute tasks with TDD discipline and single-task focus
tools: ['bash', 'github-mcp-server']
handoffs:
  - label: Validate Session
    agent: session.validate
    prompt: Run quality checks before publishing
    send: true
    condition: workflow is development
  - label: Wrap Session
    agent: session.wrap
    prompt: Document spike/exploration session
    send: true
    condition: workflow is spike
---

## User Input

```text
$ARGUMENTS
```

**Argument Support**:
- `--comment "text"`: Specific instructions for this execution (e.g., "Skip Test 5.3, focus on Test 5.4")
- `--resume`: Continue from last checkpoint - DO NOT restart from beginning

**Behavior**:
- **If `--resume` flag present**: 
  - Check `tasks.md` to see what's already [x] completed
  - Continue from first incomplete task
  - DO NOT re-execute completed tasks
  - DO NOT reset or restart the workflow
- **If `--comment` provided**: 
  - Follow instructions as high-priority guidance
  - May override normal task order or skip tasks per comment
- **Default**: Execute tasks sequentially from start

## ⚠️ CRITICAL: Prerequisites

This agent assumes:
1. **session.start** has initialized the session
2. **session.plan** has generated/referenced tasks

**Session Directory Convention**: Session directories MUST use timestamp format (e.g., `2025-12-21-1`), NOT issue numbers.

Expected context:
- Session info in `.session/ACTIVE_SESSION` pointing to active session ID
- Session directory: `.session/sessions/YYYY-MM/{session-id}/`
- Tasks defined in session `tasks.md` OR `specs/{feature}/tasks.md` (for Speckit)

**⚠️ NEVER manually construct session directory paths.** Always read from `.session/ACTIVE_SESSION`.

## Outline

### 1. Load Session and Task Context

**CRITICAL**: Read session context from ACTIVE_SESSION, NOT by guessing paths.

**Option A - Preflight Script (Recommended):**
```bash
.session/scripts/bash/session-preflight.sh --step execute --json
```
This validates the session, marks step in_progress, and outputs JSON context including task counts.

**Option B - Manual Loading:**
```bash
# Get the active session ID from ACTIVE_SESSION marker
ACTIVE_SESSION_FILE=".session/ACTIVE_SESSION"
if [ ! -f "$ACTIVE_SESSION_FILE" ]; then
  echo "ERROR: No active session found. Run /session.start first."
  exit 1
fi

SESSION_ID=$(cat "$ACTIVE_SESSION_FILE")
YEAR_MONTH=$(echo "$SESSION_ID" | cut -d'-' -f1,2)  # Extract YYYY-MM
SESSION_DIR=".session/sessions/${YEAR_MONTH}/${SESSION_ID}"

echo "Active session: $SESSION_ID"
echo "Session directory: $SESSION_DIR"

# Verify session directory exists
if [ ! -d "$SESSION_DIR" ]; then
  echo "ERROR: Session directory not found: $SESSION_DIR"
  exit 1
fi

# Read session info
SESSION_INFO=$(cat "$SESSION_DIR/session-info.json")
SESSION_TYPE=$(echo "$SESSION_INFO" | jq -r '.type')
ISSUE_NUMBER=$(echo "$SESSION_INFO" | jq -r '.issue_number // empty')

echo "Session type: $SESSION_TYPE"
```

Determine task file location:
- **Speckit**: Tasks in `specs/{feature}/tasks.md`
- **GitHub issue/unstructured**: Tasks in `$SESSION_DIR/tasks.md`


### 1.5. Check Workflow Compatibility

**NEW (Schema v2.0)**: Verify this agent is appropriate for the workflow:

```bash
# Source common functions
source .session/scripts/bash/session-common.sh

# Check if execution is allowed for this workflow
if ! check_workflow_allowed "$SESSION_ID" "development" "spike"; then
    echo "❌ session.execute is only for development or spike workflows"
    echo "Advisory workflow does not include code execution"
    exit 1
fi

echo "✓ Workflow check passed - proceeding with execution"
```

**Allowed workflows**: development, spike

**Note**: Spike workflow proceeds with lighter validation (no PR required).

### 2. Review Task List

Display current task status:
- Count total tasks
- Count completed tasks [x]
- Count incomplete tasks [ ]
- Identify next incomplete task

### 3. Execute Tasks One at a Time

**MANDATORY: Single-Task Focus**

Complete **one task fully** before moving to the next:

1. **Identify** next incomplete task
2. **Implement** the task
3. **Write/update tests** (if not a test task itself)
4. **Run tests** to verify:
   ```bash
   # Run project-specific test command
   # Check .session/project-context/technical-context.md for commands
   # Common patterns:
   #   make test          # If Makefile exists
   #   npm test           # Node.js projects
   #   pytest             # Python projects
   ```
5. **Mark complete**: Update task to [x] in tasks file:
   - For Speckit: Edit `specs/{feature}/tasks.md`
   - For others: Edit session `tasks.md`
6. **Commit** with descriptive message including task ID:
   ```bash
   git add -A
   git commit -m "feat: implement X (T042)"
   ```
7. **THEN** move to next task

**Why single-task focus?**
- Prevents "lost-in-context" behaviors
- Clear commit history
- Easy to track progress
- Easier to debug failures

### 4. Frontend/UI Changes - Manual Verification

**For ANY change with user-visible symptoms:**

#### When Manual Testing is REQUIRED:
- ✅ Frontend component/UI changes
- ✅ API endpoints that affect UI behavior
- ✅ Backend fixes where bug symptom appears in browser
- ✅ Database/storage changes affecting displayed data
- ✅ Download/upload functionality

#### When Manual Testing is NOT Required:
- ❌ Pure backend logic (internal services)
- ❌ Database migrations (unless affecting displayed data)
- ❌ Documentation updates
- ❌ Configuration changes
- ❌ Test-only changes

#### Manual Test Execution:

When you encounter a `[MANUAL]` test task:

1. **Stop** automated execution
2. **Prompt user**:
   ```
   🔍 Manual browser test required:
   
   Task: {task-description}
   Action: {specific-action-to-test}
   Expected: {expected-result}
   
   Please test in browser and confirm:
   - [ ] Test passed (works as expected)
   - [ ] Test failed (describe issue)
   ```
3. **Wait** for user confirmation
4. **If failed**: Debug and fix BEFORE proceeding
5. **If passed**: Mark task [x] and continue
6. **Document** result in notes.md

**NEVER proceed to commit/push/PR tasks without manual test confirmation.**

### 5. TDD Workflow

Follow Test-Driven Development:

```
Test → Implement → Verify → Commit → Repeat
```

**Example sequence**:
1. T001 [TEST] Write unit test for X
   - Write failing test
   - Verify test fails (expected)
   - Mark [x], commit

2. T002 Implement X
   - Implement feature
   - Run tests (should now pass)
   - Mark [x], commit

3. T003 [TEST] Write integration test for X
   - Write integration test
   - Verify passes
   - Mark [x], commit

4. T004 [MANUAL] Browser test: verify X in UI
   - Prompt user for manual testing
   - Wait for confirmation
   - Mark [x], commit

### 6. Monitor Context Window

Track your context usage:
- If approaching token limit (~80% full)
- If multiple tasks remain
- If natural breakpoint reached

**Then**: Suggest handoff:
```
⚠️ Context window filling up ({percentage}%)

Completed: {count} tasks
Remaining: {count} tasks

Recommend pausing now.
You can resume with /session.execute in next session.

Options:
- /session.validate → Run quality checks and chain to publish
- /session.wrap → Skip validation and wrap directly
```

### 7. Phase Completion (Speckit Sessions Only)

**When all tasks in a Speckit phase are [x]:**

1. **Verify completion**:
   - All required tasks marked [x] in `specs/{feature}/tasks.md`
   - No [SKIP] tasks without justification

2. **Run ALL test suites** (even if phase doesn't touch all areas):
   ```bash
   # Run comprehensive tests per project configuration
   # Check .session/project-context/technical-context.md
   ```

3. **Validate coverage**:
   - Check output for coverage percentage
   - Ensure meets requirements (usually 70-80%+)
   - Report any coverage drops

4. **Report pre-existing failures** (but don't block):
   - Note any unrelated test failures
   - Distinguish from new failures

5. **Verify features match specification**:
   - Review acceptance criteria from spec.md
   - Confirm implemented features work as specified

6. **Prepare for validation**:
   - Phase will be validated and published
   - Parent issue will be updated in session.finalize

### 8. Report Completion

When all incomplete tasks are done (or pausing for context):

```
✅ Task execution complete

Session: $SESSION_ID
Completed: {count} tasks
Commits: {count} commits made

{If Speckit phase complete}:
Phase {N} complete - all tasks [x]
Ready for validation and publishing

{If more tasks remain}:
Remaining: {count} tasks
Can resume with /session.execute

Next steps:
→ /session.validate (recommended) - Auto-chains to publish
→ /session.wrap - Skip validation and document only
```

The CLI will present handoff to session.validate with send: true (auto-invoke).
User can override and call session.wrap directly if needed.

**Handoff Reasoning**: session.execute completes implementation tasks but doesn't verify quality or create PRs. session.validate runs comprehensive quality checks (lint, tests, coverage) before publishing, ensuring nothing broken is pushed. session.wrap is for documentation only without validation.

## Failure Modes to Avoid

| ❌ Failure Mode | Description | ✅ Instead |
|----------------|-------------|-----------|
| **One-shot** | Trying to complete everything at once | Complete one task, verify, commit, then next |
| **Skip tests** | Implementing without verifying tests pass | Always run tests after each task |
| **Frontend without browser test** | Committing UI changes without manual verification | ALWAYS complete [MANUAL] tasks before proceeding |
| **Multi-task commits** | Committing multiple unrelated changes | One task = one commit |
| **Context overflow** | Continuing until context exhausted | Monitor usage, wrap at 80% |

## Notes

- **Single responsibility**: Execute tasks only
- **No planning**: session.plan already handled that
- **Validation & finalization**: session.validate/publish/finalize chain handles that
- **TDD discipline**: Test → implement → verify → commit
- **Manual verification**: Required for UI-visible changes
- **Small commits**: One task per commit
- **Handoff when done**: Auto-chain to session.validate (send: true)
