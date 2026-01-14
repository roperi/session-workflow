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

## User Input

```text
$ARGUMENTS
```

**Argument Support**:
- `--comment "text"`: Specific validation instructions (e.g., "Skip integration tests", "Only lint")
- `--resume`: Re-run only failed checks from previous validation

**Behavior**:
- **If `--resume` flag present**: 
  - Check validation output from previous run
  - Only re-execute checks that failed
  - Skip checks that passed
- **If `--comment` provided**: 
  - May skip certain validation steps per instruction
  - Use as override for normal validation flow
- **Default**: Run full validation suite

## CRITICAL: Validation Must Complete Before Proceeding

**NEVER timeout or skip ahead.** Each validation step MUST complete fully before moving to next step.

## Project-Specific Commands

**IMPORTANT**: Check `.session/project-context/technical-context.md` for project-specific test and lint commands. The examples below are common patterns but may need adjustment.

## Validation Checklist (Sequential - DO NOT SKIP)

Run each check, WAIT for completion, store results. Continue even if failures occur (collect all issues).

### 1. Lint Check

```bash
# Run project-specific lint command (examples):
# make lint           # If Makefile
# npm run lint        # Node.js
# pylint app/         # Python
# go vet ./...        # Go
```

**Pass criteria**: No errors reported  
**Fail**: Record details, continue to next check


### 1.5. Check Workflow Compatibility

**NEW (Schema v2.0)**: Verify this agent is appropriate for the workflow:

```bash
# Source common functions
source .session/scripts/bash/session-common.sh

# Check if validation is allowed for this workflow
if ! check_workflow_allowed "$SESSION_ID" "development"; then
    echo "❌ session.validate is only for development workflow"
    echo "Experiment and advisory workflows skip validation"
    exit 1
fi

echo "✓ Workflow check passed - proceeding with validation"
```

**Allowed workflows**: development only

**Blocked workflows**:
- **advisory**: No code to validate
- **experiment**: Experimental work not intended for production

Only development workflow requires validation before PR.

### 2. Unit Tests

```bash
# Run project-specific test command (examples):
# make test           # If Makefile
# npm test            # Node.js
# pytest tests/unit/  # Python
# go test ./...       # Go
```

**CRITICAL**: Use `initial_wait: 120` minimum. If still running, use `read_bash` with delay: 30 until complete.

**Pass criteria**: 
- All tests pass
- Coverage meets project requirements (if applicable)

**Fail**: Record failure count, continue

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
