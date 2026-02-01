---
description: Create implementation plan and approach for session work
tools: ["*"]
---

## User Input

```text
$ARGUMENTS
```

**Argument Support**:
- `--comment "text"`: Specific planning instructions (e.g., "Focus on API layer only")
- `--resume`: Update existing plan instead of creating new

**Behavior**:
- **If `--resume` flag present**: 
  - Load existing plan from notes.md
  - Update/refine rather than replace
- **If `--comment` provided**: 
  - Use as guidance for planning scope/focus
- **Default**: Create fresh implementation plan

## ⚠️ CRITICAL: Session Context Required

This agent assumes **session.start** has already run. If not, you will not have session context.

**Session Directory Convention**: Session directories MUST use timestamp format (e.g., `2025-12-21-1`).

Expected session variables from session-info.json:
- `session_id` - Session identifier (e.g., "2025-12-21-1")
- `type` - "speckit" | "github_issue" | "unstructured"
- `workflow` - "development" | "spike"
- `issue_number` or `spec_id` (if applicable)

**⚠️ NEVER manually construct session directory paths.** Always read from `.session/ACTIVE_SESSION`.

## Outline

### 1. Load Session Context

**Option A - Preflight Script (Recommended):**
```bash
.session/scripts/bash/session-preflight.sh --step plan --json
```
This validates the session, checks for interrupts, and outputs JSON context.

**Option B - Manual Loading:**
```bash
ACTIVE_SESSION_FILE=".session/ACTIVE_SESSION"
if [ ! -f "$ACTIVE_SESSION_FILE" ]; then
  echo "ERROR: No active session found. Run /session.start first."
  exit 1
fi

SESSION_ID=$(cat "$ACTIVE_SESSION_FILE")
YEAR_MONTH=$(echo "$SESSION_ID" | cut -d'-' -f1,2)
SESSION_DIR=".session/sessions/${YEAR_MONTH}/${SESSION_ID}"

# Read session-info.json
cat "$SESSION_DIR/session-info.json"
```

### 2. Check Workflow Compatibility

```bash
WORKFLOW=$(jq -r '.workflow' "$SESSION_DIR/session-info.json")
echo "Workflow: $WORKFLOW"
```

**Allowed workflows**: development, spike (both need planning!)

**Workflow difference**:
- **development**: plan → task → execute → validate → publish → finalize → wrap
- **spike**: plan → task → execute → wrap (skips PR steps)

### 3. Branch Based on Session Type

#### A. Speckit Session Path

For Speckit sessions, plan already exists in `specs/{feature}/plan.md`.

1. **Run prerequisites check**:
   ```bash
   .specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks
   ```

2. **Load Speckit artifacts**:
   - **REQUIRED**: Read `{FEATURE_DIR}/plan.md` for tech stack and architecture
   - **OPTIONAL**: Read `{FEATURE_DIR}/spec.md` for requirements
   - **OPTIONAL**: Read `{FEATURE_DIR}/data-model.md` (if exists)
   - **OPTIONAL**: Read `{FEATURE_DIR}/contracts/` API specs (if exists)
   - **OPTIONAL**: Read `{FEATURE_DIR}/research.md` (if exists)

3. **Validate checklists** (if FEATURE_DIR/checklists/ exists):
   - Count complete vs incomplete items
   - **If any checklist incomplete**: Ask user to proceed or wait

4. **Write plan reference to session notes**:
   ```bash
   cat >> "$SESSION_DIR/notes.md" << EOF

## Implementation Plan

Plan managed in Speckit: \`{FEATURE_DIR}/plan.md\`

**Tech Stack**: {from plan.md}
**Architecture**: {summary from plan.md}

EOF
   ```

5. **Display summary**:
   ```
   ✅ Speckit plan loaded

   Feature: {feature-name}
   Plan: {FEATURE_DIR}/plan.md
   
   Ready for task generation → /session.task

   Incomplete tasks:
   - [ ] T146 Create useProjectModels.ts
   - [ ] T147 Implement hook to fetch project models
   ...
   ```

#### B. GitHub Issue Session Path

**Create implementation plan from issue details.**

1. **Fetch issue details**:
   ```bash
   gh issue view {issue-number} --json title,body,labels,assignees
   ```

2. **Parse issue body** for:
   - Acceptance criteria
   - Steps to reproduce (if bug report)
   - Expected vs actual behavior
   - Technical requirements mentioned

3. **Read project context**:
   - `.session/project-context/technical-context.md` - Stack, commands
   - `.session/project-context/constitution-summary.md` - Quality standards

4. **Create implementation plan** and write to notes.md:
   ```bash
   cat >> "$SESSION_DIR/notes.md" << EOF

## Implementation Plan

**Issue**: #{issue-number} - {title}
**Type**: {bug|feature|improvement}

### Problem Statement
{extracted from issue body}

### Acceptance Criteria
{extracted from issue body}

### Technical Approach
{your analysis of how to implement}

### Components Affected
- {list of files/modules to modify}

### User Stories (if applicable)
- US1: {story 1 - highest priority}
- US2: {story 2}

### Risks/Considerations
- {any risks or dependencies}

EOF
   ```

5. **Display summary**:
   ```
   ✅ Implementation plan created

   Issue: #{issue-number} - {title}
   Plan saved to: $SESSION_DIR/notes.md

   Ready for task generation → /session.task
   ```

#### C. Unstructured Session Path

**Create implementation plan from goal description.**

1. **Parse goal** from session-start arguments

2. **Analyze scope**:
   - What needs to be done?
   - What components are affected?
   - What's the technical approach?

3. **Write plan to session notes**:
   ```bash
   cat >> "$SESSION_DIR/notes.md" << EOF

## Implementation Plan

**Goal**: {goal-description}

### Scope
{what's in scope, what's out}

### Technical Approach
{how to implement}

### Components Affected
- {list of files/modules}

### Success Criteria
- {how to verify completion}

EOF
   ```

4. **Display summary**

### 4. Report Completion

Display final summary with handoff suggestion:

```
✅ Session planning complete

Session: $SESSION_ID
Type: {speckit|github_issue|unstructured}
Plan: Written to notes.md

Ready for task generation → /session.task
```

**Next step:** `/session.task`

**Why:** session.plan creates the high-level implementation plan but doesn't break it into detailed tasks. session.task generates the structured task list with user story organization, parallelization markers, and dependencies.

## Planning Guidelines

### What to Include in a Plan

1. **Problem Statement**: Clear description of what needs to be solved
2. **Technical Approach**: High-level how (not detailed steps)
3. **Components Affected**: Files, modules, services that will change
4. **User Stories**: If applicable, map requirements to stories
5. **Risks/Considerations**: Dependencies, potential issues

### What NOT to Include

- ❌ Detailed task lists (that's session.task's job)
- ❌ Code snippets or implementation details
- ❌ File-by-file changes (too granular)

### For Bug Fixes

Include:
- Steps to reproduce
- Root cause analysis
- Fix approach
- Verification method

### For Features

Include:
- User stories with priorities
- Acceptance criteria
- Architecture decisions
- Integration points

## Notes

- **Speckit sessions**: Reference existing plan, don't duplicate
- **GitHub issues**: Create plan from issue content
- **Unstructured**: Create plan from goal
- **Single responsibility**: Planning only, no task generation
- **Next step:** `/session.task`
