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
- `--comment "text"`: Specific planning instructions (e.g., "Only plan Tests 5.4 and 5.5")
- `--resume`: Append to existing tasks.md instead of creating new

**Behavior**:
- **If `--resume` flag present**: 
  - Load existing `tasks.md` 
  - Append new tasks rather than replacing
  - Preserve completed task markers [x]
- **If `--comment` provided**: 
  - Use as guidance for task scope
  - May filter or focus tasks per instruction
- **Default**: Generate fresh task list

## ⚠️ CRITICAL: Session Context Required

This agent assumes **session.start** has already run. If not, you will not have session context.

**Session Directory Convention**: Session directories MUST use timestamp format (e.g., `2025-12-21-1`), NOT issue numbers (e.g., `session-670`).

Expected session variables from session-info.json:
- `session.id` - Session identifier (e.g., "2025-12-21-1")
- `session.type` - "speckit" | "github_issue" | "unstructured"
- `session.dir` - Full session directory path (e.g., ".session/sessions/2025-12/2025-12-21-1")
- `session.created_at` - ISO timestamp
- `issue_number` or `spec_id` (if applicable)

**⚠️ NEVER manually construct session directory paths or create new session folders.** Always read `session.dir` from `.session/ACTIVE_SESSION` and `session-info.json`.

## Outline

### 1. Load Session Context

**CRITICAL**: Session context must come from session.start agent's output, NOT by guessing paths.

**Option A - Preflight Script (Recommended):**
```bash
.session/scripts/bash/session-preflight.sh --step plan --json
```
This validates the session, checks for interrupts, and outputs JSON context. If errors, follow the hint.

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

# Read session-info.json
cat "$SESSION_DIR/session-info.json"
```

Parse the JSON output to get:
- `session_id` - Session identifier (e.g., "2025-12-21-1")
- `type` - "speckit" | "github_issue" | "unstructured"
- `created_at` - ISO timestamp
- `issue_number` or `spec_id` (if applicable)

Use `$SESSION_DIR` for all file operations (creating tasks.md, notes.md, etc.).

**⚠️ NEVER manually construct session directory paths or create new session folders.** Always read `session_id` from `.session/ACTIVE_SESSION` and construct the path as shown above.


### 1.5. Check Workflow Compatibility

Verify this agent is appropriate for the workflow:

```bash
# Source common functions
source .session/scripts/bash/session-common.sh

# Both development and spike workflows use planning
WORKFLOW=$(jq -r '.workflow' "$SESSION_DIR/session-info.json")
echo "Workflow: $WORKFLOW"
```

**Allowed workflows**: development, spike (both need planning!)

**Workflow difference**:
- **development**: plan → execute → validate → publish → finalize → wrap
- **spike**: plan → execute → wrap (skips PR steps, NOT planning)

### 2. Determine Session Type

Based on `session.type` or issue labels:

**Check if Speckit session**:
```bash
# If issue provided, check labels
gh issue view {issue-number} --json labels -q '.labels[].name' | grep -q "speckit"
```

### 3. Branch Based on Type

#### A. Speckit Session Path

**DO NOT generate tasks!** Tasks already exist in `specs/{feature}/tasks.md`.

1. **Run prerequisites check**:
   ```bash
   .specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks
   ```

2. **Parse JSON output** to get:
   - `FEATURE_DIR` (e.g., "specs/003-project-model-config")
   - `FEATURE_ID` (e.g., "003-project-model-config")

3. **Validate checklists** (if FEATURE_DIR/checklists/ exists):
   - List all checklist files
   - For each checklist, count:
     - Total items
     - Complete items [x]
     - Incomplete items [ ]
   - Create status table:
     ```
     Checklist               Status    Complete
     ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
     requirements.md         PASS      15/15
     architecture.md         FAIL      8/12
     ```
   - **If any checklist is incomplete**:
     - Display table
     - Ask: "Some checklists are incomplete. Proceed anyway? (yes/no)"
     - If user says no/wait/stop: HALT execution
     - If user says yes: Continue

4. **Load Speckit artifacts**:
   - **REQUIRED**: Read `{FEATURE_DIR}/tasks.md` for task list
   - **REQUIRED**: Read `{FEATURE_DIR}/plan.md` for tech stack and architecture
   - **OPTIONAL**: Read `{FEATURE_DIR}/data-model.md` (if exists)
   - **OPTIONAL**: Read `{FEATURE_DIR}/contracts/` API specs (if exists)
   - **OPTIONAL**: Read `{FEATURE_DIR}/research.md` (if exists)
   - **OPTIONAL**: Read `{FEATURE_DIR}/quickstart.md` (if exists)

5. **Identify phase** from issue title:
   - Parse title format: "[Phase N] Phase Name"
   - Extract phase number (e.g., "5" from "[Phase 5] Wizard & Settings UI")

6. **Extract phase tasks** from `{FEATURE_DIR}/tasks.md`:
   - Find markdown heading `## Phase {N}:`
   - List all tasks under that heading until next `## Phase` or end
   - Count complete [x] vs incomplete [ ]
   - Note task IDs (e.g., T146, T147, etc.)

7. **Write task reference to session notes**:
   ```bash
   cat >> "$SESSION_DIR/notes.md" << EOF

## Task Reference

Tasks for this session are tracked in:
\`{FEATURE_DIR}/tasks.md\` - Phase {N}

**DO NOT duplicate tasks.** Mark complete in spec file directly using edit tool.

**Phase**: {phase-number} - {phase-name}
**Tasks**: {complete}/{total} complete

EOF
   ```

8. **Display summary**:
   ```
   ✅ Speckit session plan loaded

   Feature: {feature-name}
   Phase: {phase-number} - {phase-name}
   Tasks: {complete}/{total} complete
   Task file: {FEATURE_DIR}/tasks.md

   Incomplete tasks:
   - [ ] T146 Create useProjectModels.ts
   - [ ] T147 Implement hook to fetch project models
   ...
   ```

#### B. GitHub Issue Session Path

**Generate tasks from issue body**.

1. **Fetch issue details**:
   ```bash
   gh issue view {issue-number} --json title,body,labels,assignees
   ```

2. **Parse issue body** for:
   - Acceptance criteria
   - Steps to reproduce (if bug report)
   - Expected vs actual behavior
   - Technical requirements mentioned

3. **Generate TDD-first task list**:

   **Rules**:
   - Test tasks BEFORE implementation tasks
   - Mark tasks: [TEST], [DOC], [MANUAL], or unmarked (implementation)
   - Add [MANUAL] browser test tasks for ANY UI-visible changes
   - Number tasks sequentially: T001, T002, T003...

   **Example structure**:
   ```markdown
   - [ ] T001 [TEST] Write unit test for X
   - [ ] T002 Implement X functionality
   - [ ] T003 [TEST] Write integration test for Y
   - [ ] T004 Implement Y functionality
   - [ ] T005 [MANUAL] Browser test: verify X works in UI
   - [ ] T006 [MANUAL] Browser test: verify Y behaves correctly
   - [ ] T007 Commit changes and push branch
   - [ ] T008 Create PR for review
   ```

4. **Write tasks to session tasks.md**:
   ```bash
   cat > "$SESSION_DIR/tasks.md" << EOF
# Session Tasks: $SESSION_ID

**Issue**: #{issue-number} - {title}
**Type**: {bug|feature|improvement}

## Tasks

{generated-tasks}

## Notes

- Follow TDD approach: test → implement → verify
- Complete one task fully before moving to next
- Mark [x] in this file as you complete each task
EOF
   ```

5. **Display summary**:
   ```
   ✅ Task list generated

   Issue: #{issue-number} - {title}
   Tasks: {count} tasks generated
   Task file: $SESSION_DIR/tasks.md

   Next: /session.execute
   ```

#### C. Unstructured Session Path

**Generate tasks from goal description**.

1. **Parse goal** from session-start arguments or prompt user

2. **Generate task breakdown** based on goal:
   - Apply TDD-first principles
   - Break into logical, testable chunks
   - Add manual verification tasks if needed

3. **Write to session tasks.md**:
   ```bash
   cat > "$SESSION_DIR/tasks.md" << EOF
# Session Tasks: $SESSION_ID

**Goal**: {goal-description}
**Type**: Unstructured work

## Tasks

{generated-tasks}
EOF
   ```

4. **Display summary**

### 4. Report Completion

Display final summary with handoff suggestion:

```
✅ Session planning complete

Session: $SESSION_ID
Type: {speckit|github_issue|unstructured}
Tasks: {count} tasks {ready|referenced}

Ready to begin execution → /session.execute
```

The CLI will present the handoff option automatically based on frontmatter.

**Handoff Reasoning**: session.plan generates or references the task list but doesn't execute work. Task execution is session.execute's responsibility, which implements tasks following TDD discipline and makes actual code changes.

## Task Generation Guidelines (Non-Speckit Sessions)

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

### When to Add [MANUAL] Tests

**Required for**:
- ✅ Frontend/UI component changes
- ✅ API endpoints that affect UI behavior
- ✅ Backend fixes where symptom appears in browser
- ✅ Any user-visible change

**Not required for**:
- ❌ Pure backend logic (internal services)
- ❌ Database migrations (unless affecting displayed data)
- ❌ Documentation updates
- ❌ Configuration changes

### Task Numbering

- Sequential: T001, T002, T003...
- Never skip numbers
- Never reuse numbers
- Mark obsolete tasks as [SKIP] with reason, don't delete

## Notes

- **Speckit sessions**: Reference tasks, don't duplicate
- **GitHub issues**: Generate TDD-first tasks
- **Unstructured**: Generate tasks from goal
- **Always validate checklists** for Speckit before proceeding
- **Small, focused agent**: Planning only, no execution
- **Auto-handoff**: session.execute will be suggested with send: true
