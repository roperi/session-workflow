---
description: Generate or reference task list based on session type (Speckit-aware)
tools: ['bash', 'github-mcp-server']
handoffs:
  - label: Execute Tasks
    agent: session.execute
    prompt: Begin task execution
    send: true
---

## User Input

```text
$ARGUMENTS
```

**Argument Support**:
- `--comment "text"`: Specific planning instructions
- `--resume`: Append to existing tasks.md instead of creating new

## ⚠️ CRITICAL: Script Execution Required

**DO NOT SKIP ANY STEPS.** This agent ensures proper session setup.

Before doing ANY work:
1. Run the session-plan script (Step 1)
2. Wait for and parse the JSON output
3. Only then proceed to task generation

## Outline

### 1. Run Session-Plan Script (MANDATORY)

Execute the planning support script to load context and validate prerequisites:

```bash
.session/scripts/bash/session-plan.sh --json $ARGUMENTS
```

⛔ **STOP HERE** until you receive script output.

### 2. Parse JSON Output

Extract from the script output:
- `session.id` - Session identifier
- `session.dir` - **Absolute path for all file operations**
- `session.type` - "speckit" | "github_issue" | "unstructured"
- `context` - Type-specific data (issue details, spec path, etc.)
- `warnings` - Any issues to address

### 3. Branch Based on Type

#### A. Speckit Session (`session.type` == "speckit")

**DO NOT generate tasks!** Tasks exist in `context.spec_path/tasks.md`.

1. **Validate Checklists**:
   - Look for checklists in `{context.spec_path}/checklists/` (if valid path)
   - Ensure all items are [x]
   - **Halt** if critical checklists are incomplete (ask user)

2. **Load Artifacts**:
   - Read `{context.spec_path}/tasks.md` (Required)
   - Read `{context.spec_path}/plan.md` (Required)

3. **Identify Phase**:
   - Find current phase in tasks.md
   - Create task reference in `{session.dir}/notes.md`

#### B. GitHub Issue Session (`session.type` == "github_issue")

**Generate tasks from issue context**.

1. **Analyze Context**:
   - Use `context.title` and `context.body` from JSON
   - Identify requirements and acceptance criteria

2. **Generate TDD Tasks**:
   - Create `{session.dir}/tasks.md`
   - **Rule**: Test [TEST] → Implement → Verify [MANUAL] → Commit

#### C. Unstructured Session (`session.type` == "unstructured")

**Generate tasks from goal**.

1. **Analyze Context**:
   - Use `context.goal` from JSON

2. **Generate Tasks**:
   - Create `{session.dir}/tasks.md`
   - Break goal into testable steps

### 4. Report Completion

Display summary and suggest handoff to `/session.execute`.

## Task Generation Guidelines

### TDD-First Approach

**Pattern**: Test → Implement → Manual Verify → Commit

```markdown
- [ ] T001 [TEST] Write unit test for user authentication
- [ ] T002 Implement authentication service
- [ ] T003 [TEST] Write integration test for login endpoint
- [ ] T004 Implement login API endpoint
- [ ] T005 [MANUAL] Browser test: verify login form works
- [ ] T006 Commit authentication implementation
```

### Task Numbering

- Sequential: T001, T002, T003...
- Never skip numbers
