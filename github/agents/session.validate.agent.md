---
description: Validates session work quality before publishing
handoffs:
  - label: Publish PR
    agent: session.publish
    prompt: Create or update pull request with validation results
    send: true
---

# session.validate

**Purpose**: Validates completed session work before publishing to PR/issues.

**IMPORTANT**: Read `.session/docs/shared-workflow.md` for shared workflow rules.

## User Input

```text
$ARGUMENTS
```

**Argument Support**:
- `--comment "text"`: Specific validation instructions (e.g., "Skip integration tests", "Only lint")
- `--resume`: Re-run only failed checks from previous validation, or resume interrupted validation

**Behavior**:
- **If `--resume` flag present**: 
  - Check validation output from previous run
  - Only re-execute checks that failed
  - Skip checks that passed
  - Also used to resume interrupted validation sessions
- **If `--comment` provided**: 
  - May skip certain validation steps per instruction
  - Use as override for normal validation flow
- **Default**: Run full validation suite

## ⚠️ CRITICAL: Workflow State Tracking

**ON ENTRY** - Use preflight script (recommended):
```bash
.session/scripts/bash/session-preflight.sh --step validate --json
```
This validates workflow state, checks for interrupts, and marks step as in_progress.

**Alternative** - Manual state tracking:
```bash
source .session/scripts/bash/session-common.sh
SESSION_ID=$(get_active_session)

# Mark validation as in-progress (for interrupt recovery)
set_workflow_step "$SESSION_ID" "validate" "in_progress"
```

**ON SUCCESSFUL COMPLETION**:
```bash
set_workflow_step "$SESSION_ID" "validate" "completed"
```

**ON FAILURE**:
```bash
set_workflow_step "$SESSION_ID" "validate" "failed"
```

This tracking enables session continuity - if the CLI is killed during validation, the next session can detect it and resume properly.

## CRITICAL: Validation Must Complete Before Proceeding

**NEVER timeout or skip ahead.** Each validation step MUST complete fully before moving to next step.

## CRITICAL: No Fabricated Results

**You MUST actually run commands and report real output. NEVER:**
- ❌ Assume tests pass because test files exist
- ❌ Assume lint passes because TypeScript compiles
- ❌ Report pass counts without running the actual command
- ❌ Use `tsc` or `npm run build` as a substitute for linting
- ❌ Infer results from code inspection

**You MUST:**
- ✅ Run the actual lint/test command
- ✅ Capture real output (pass/fail counts, error messages)
- ✅ Report "skipped" if a command doesn't exist
- ✅ Show the actual command you ran and its output

## Project-Specific Commands

**IMPORTANT**: Check `.session/project-context/technical-context.md` for project-specific test and lint commands. If not defined there, check `package.json` scripts, `Makefile`, or equivalent.

**If commands are not configured:**
- Report the check as "skipped" with reason "No [lint/test] command configured"
- Do NOT mark as "pass" - absence of a command is not the same as passing

## Stage-Aware Validation

**CRITICAL**: Check the session stage to determine validation strictness:

```bash
source .session/scripts/bash/session-common.sh
SESSION_ID=$(get_active_session)
SESSION_DIR=$(get_session_dir "$SESSION_ID")
STAGE=$(jq -r '.stage // "production"' "$SESSION_DIR/session-info.json")
```

| Stage | Lint Failures | Test Failures | Missing Commands | Overall |
|-------|---------------|---------------|------------------|---------|
| **poc** | ⚠️ Warning only | ⚠️ Warning only | ✅ OK to proceed | Proceed with warnings |
| **mvp** | ❌ Block | ⚠️ Warning on minor | ⚠️ Warning | Fail on errors, warn on style |
| **production** | ❌ Block | ❌ Block | ⚠️ Warning | All checks must pass |

**Stage-specific behavior:**
- **poc**: Collect all results but never block. Add note: "⚠️ PoC validation: Warnings only"
- **mvp**: Block on errors, warn on style issues. Add note: "📦 MVP validation: Standard checks"
- **production**: Block on any failure. Add note: "🚀 Production validation: Strict checks"

## Validation Checklist (Sequential - DO NOT SKIP)

Run each check, WAIT for completion, store results. Continue even if failures occur (collect all issues).

### 1. Lint Check

**CRITICAL: Actually Execute Commands**
- You MUST run actual commands and capture real output
- DO NOT assume or fabricate results based on file existence
- If a command doesn't exist, report "skipped" with reason
- If a command fails, report the actual error

```bash
# First, check if lint command exists in package.json or Makefile
# Then run project-specific lint command (examples):
# npm run lint        # Node.js (check package.json scripts first)
# make lint           # If Makefile has lint target
# pylint app/         # Python
# go vet ./...        # Go
```

**IMPORTANT**: 
- TypeScript compilation (`tsc`) is NOT linting - it's type checking
- If no lint script exists, report status as "skipped" with "No lint script configured"
- DO NOT substitute `tsc` or `npm run build` for linting

**Pass criteria**: Lint command exists AND reports no errors  
**Skip criteria**: No lint command configured (report as "skipped", not "pass")
**Fail**: Record actual lint errors, continue to next check


### 1.5. Check Workflow Compatibility

**NEW (Schema v2.0)**: Verify this agent is appropriate for the workflow:

```bash
# Source common functions
source .session/scripts/bash/session-common.sh

# Check if validation is allowed for this workflow
if ! check_workflow_allowed "$SESSION_ID" "development"; then
    echo "❌ session.validate is only for development workflow"
    echo "Spike workflow skips validation"
    exit 1
fi

echo "✓ Workflow check passed - proceeding with validation"
```

**Allowed workflows**: development only

**Blocked workflows**:
- **spike**: Research/exploration work skips formal validation

Only development workflow requires validation before PR.

### 2. Unit Tests

```bash
# First, verify test command exists and what it is
# Check package.json scripts, Makefile, or pyproject.toml
# Then run project-specific test command (examples):
# npm test            # Node.js (verify script exists first)
# make test           # If Makefile has test target
# pytest tests/unit/  # Python
# go test ./...       # Go
```

**CRITICAL**: 
- Use `initial_wait: 120` minimum
- If still running, use `read_bash` with delay: 30 until complete
- Capture ACTUAL test output - do not estimate or fabricate numbers
- If no test command exists, report as "skipped"

**Pass criteria**: 
- Test command exists AND runs successfully
- All tests pass (capture actual pass/fail counts from output)
- Coverage meets project requirements (if applicable)

**Skip criteria**: No test command configured (report as "skipped", not "pass")
**Fail**: Record actual failure count from test output, continue

### 3. Integration Tests (if applicable)

```bash
# Run project-specific integration tests
# Check technical-context.md for commands
```

**CRITICAL**: Use `initial_wait: 180` minimum. If still running, use `read_bash` until completion.

**Pass criteria**:
- All tests pass
- Coverage meets project requirements

**Fail**: Record failures with test names, continue

### 4. Frontend Tests (if applicable)

```bash
# Run frontend tests (examples):
# npm test            # React/Vue/Angular
# make frontend-test  # If Makefile
```

**Pass criteria**: All test suites pass  
**Fail**: Record failures, continue

### 5. Git Status

```bash
git status
git diff --stat
git diff --cached --stat
```

**Pass criteria**: "working tree clean"  
**Fail**: List uncommitted files

### 6. Task Completion

Check session tasks.md or Speckit tasks.md:
- Count [x] vs [ ] tasks
- Verify all non-[SKIP] tasks complete

## Validation Results Storage

**ALWAYS create** `.session/validation-results.json`:

```json
{
  "timestamp": "2025-12-19T17:30:00Z",
  "session_id": "2025-12-19-1",
  "results": {
    "lint": {
      "status": "pass|fail",
      "details": "All checks passed"
    },
    "unit_tests": {
      "status": "pass|fail",
      "passed": 387,
      "failed": 0,
      "coverage": "72.51%",
      "details": "387 passed"
    },
    "integration_tests": {
      "status": "pass|fail|skipped",
      "details": "..."
    },
    "frontend_tests": {
      "status": "pass|fail|skipped",
      "details": "..."
    },
    "git_status": {
      "status": "pass|fail",
      "details": "Working tree clean"
    },
    "tasks": {
      "status": "pass|fail",
      "completed": 47,
      "total": 47,
      "details": "All tasks complete"
    }
  },
  "overall": "pass|fail",
  "can_publish": true|false,
  "summary": "All checks passed" | "2 tests failed"
}
```

## Decision Logic

### Check Stage First

```bash
STAGE=$(jq -r '.stage // "production"' "$SESSION_DIR/session-info.json")
```

### IF stage is "poc":
1. Create validation-results.json with all results
2. Report warnings but proceed regardless
3. **Auto-chain to session.publish** (with warnings noted)
4. Add note: "⚠️ PoC mode: Proceeding despite validation warnings"

### IF all checks PASS:
1. Create validation-results.json with overall: "pass"
2. Report success clearly
3. **Auto-chain to session.publish**

**Handoff Reasoning**: All quality gates passed, so work is ready to publish. session.publish creates/updates the PR with validation results. User still needs to monitor CI and merge PR before calling session.finalize.

### IF any checks FAIL:
1. Create validation-results.json with overall: "fail"
2. Report failures in detail
3. **DO NOT auto-chain**
4. Present user with options:

```
❌ Validation failed: [summary of failures]

Options:
1. Fix issues now (I can help debug and fix)
2. Publish anyway (creates draft PR with known issues noted)
3. Wrap session (save state, defer fixes to next session)

What would you like to do?
```

**Handoff Reasoning**: Failures block automatic handoff to session.publish. User must decide whether to fix issues, publish as draft with known issues, or wrap session for later. This prevents broken code from being published without explicit user approval.

## Handling Failures

If user chooses "Fix now":
- Analyze failure logs
- Suggest fixes
- Re-run validation after fixes
- Loop until pass or user chooses different option

If user chooses "Publish anyway":
- Note failures in validation-results.json
- Proceed to session.publish (which will include failures in PR description)

If user chooses "Wrap session":
- Save validation-results.json
- Suggest using `/session.wrap`

## What NOT to Do

- ❌ Don't timeout and skip to next validation step
- ❌ Don't run tests without waiting for completion
- ❌ Don't use grep/tail before process completes
- ❌ Don't auto-chain if validation fails
- ❌ Don't re-run tests that session.publish already has results for

## Usage

```bash
/session.validate
```

Typically invoked automatically by `session.execute` after task completion.
