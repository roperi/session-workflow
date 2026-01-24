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
    prompt: Document experimental session
    send: true
    condition: workflow is experiment
---

## User Input

```text
$ARGUMENTS
```

**Argument Support**:
- `--comment "text"`: Specific instructions for this execution
- `--resume`: Continue from last checkpoint

## ⚠️ CRITICAL: Script Execution Required

Before doing ANY work:
1. Run the session-execute script (Step 1)
2. Wait for and parse the JSON output
3. Only then proceed to task execution

## Outline

### 1. Run Session-Execute Script (MANDATORY)

Execute the execution support script to load context and validate workflow:

```bash
.session/scripts/bash/session-execute.sh --json $ARGUMENTS
```

⛔ **STOP HERE** until you receive script output.

### 2. Parse JSON Output

Extract from the script output:
- `session.id` - Session identifier
- `session.dir` - **Absolute path for all session file operations**
- `tasks.file` - **Path to the task list to be used**
- `next_task` - The first incomplete task found

### 3. Review Task List

Display current status using `tasks.file` from JSON:
- Total, completed, and remaining tasks.
- Confirm `next_task` is the correct starting point.

### 4. Execute Tasks One at a Time

**MANDATORY: Single-Task Focus**

Complete **one task fully** before moving to the next:

1. **Identify** next incomplete task from `tasks.file`.
2. **Implement** the task.
3. **Write/update tests** (if not a test task itself).
4. **Run tests** to verify (see `technical-context.md` for commands).
5. **Mark complete**: Update task to [x] in `tasks.file`.
6. **Commit** with descriptive message including task ID.
7. **THEN** move to next task.

### 5. Frontend/UI Changes - Manual Verification

**For ANY change with user-visible symptoms:**

1. **Stop** automated execution.
2. **Prompt user** for manual verification.
3. **Wait** for user confirmation.
4. **Mark complete** only after confirmation.

### 6. Monitor Context Window

Track your context usage. If approaching ~80% full, suggest handoff to `/session.validate` or `/session.wrap` to preserve state.

### 7. Phase Completion (Speckit Sessions Only)

When all tasks in a Speckit phase are [x]:
1. Run ALL test suites.
2. Validate coverage.
3. Verify features match specification.

### 8. Report Completion

Summary of completed tasks and commits. Suggest handoff to `/session.validate`.

## Task Execution Guidelines

- **TDD Pattern**: Test → Implement → Verify → Commit
- **One Task = One Commit**: Keep history clean.
- **Manual Verification**: NEVER skip for UI changes.
