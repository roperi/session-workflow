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

**IMPORTANT**: Read `.github/agents/session.common.agent.md` for shared workflow rules.

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

**ON ENTRY** (before running any validation):
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

## Outline

### 1. Run Session-Validate Script (MANDATORY)

Execute the validation support script to perform mechanical checks (Git, Tasks, Session State):

```bash
.session/scripts/bash/session-validate.sh --json $ARGUMENTS
```

⛔ **STOP HERE** until you receive script output.

### 2. Parse JSON Output

Extract from the script output:
- `status` - Overall status of mechanical checks
- `session.id` - Session identifier
- `session.dir` - Directory for storing `validation-results.json`
- `validation_checks` - Results of individual mechanical checks

If mechanical checks fail (e.g., uncommitted changes, incomplete tasks), report them and ask the user how to proceed before running tests.

### 3. Project-Specific Validation (MANDATORY)

For each check below, consult `.session/project-context/technical-context.md` for the correct commands.

#### A. Lint Check
- **Execute** the project's lint command.
- **Capture** output and status.
- Report "skipped" if no command is configured.

#### B. Unit & Integration Tests
- **Execute** the project's test suite.
- **Capture** pass/fail counts and coverage if available.
- Report "skipped" if no command is configured.

### 4. Create Validation Results File

**ALWAYS** generate `{session.dir}/validation-results.json` with the combined results of mechanical and project-specific checks.

```json
{
  "timestamp": "ISO-TIMESTAMP",
  "session_id": "SESSION_ID",
  "overall": "pass|fail",
  "checks": { ... }
}
```

### 5. Decision Logic & Handoff

#### IF all checks PASS:
- Mark step as `completed`: `set_workflow_step "$SESSION_ID" "validate" "completed"`
- **Auto-chain** to `/session.publish`

#### IF any checks FAIL:
- Mark step as `failed`: `set_workflow_step "$SESSION_ID" "validate" "failed"`
- Present failures to user.
- Offer options: Fix now, Publish anyway (as draft), or Wrap session.

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
