---
description: Close GitHub issues and sync task progress after a pull request is merged — run after PR merge, before session.wrap
tools: ["*"]
---

# session.finalize

**Purpose**: Post-merge issue management and task completion tracking.

**IMPORTANT**: Read `.session/docs/shared-workflow.md` for shared workflow rules.

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

## ⚠️ CRITICAL: Workflow State Check (RUN FIRST)

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
Run `/session.[step_name] --resume` to complete the interrupted step first.

Cannot proceed with finalize until previous step completes.
```

**IF previous step is `validate` or earlier (not `publish`):**
```
⚠️ WORKFLOW SEQUENCE ERROR

Cannot run finalize - previous steps not complete.
Current state: [step] ([status])

The workflow sequence is:
  start → plan → execute → validate → publish → finalize → wrap

REQUIRED ACTION:
Run the next step in sequence: /session.[next_step]
```

**Only proceed if:**
- `current_step` is `publish` AND `step_status` is `completed`
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

## CRITICAL: Run Script with FULL Arguments

The `sync-task-status.sh` script requires specific arguments. **DO NOT run it blindly.**

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

#### For Speckit Phase Issues:

**Step 1**: Check if phase is 100% complete
```bash
# Read current phase tasks from specs/XXX/tasks.md
# Count [x] vs [ ] tasks in this phase
```

**Step 2**: IF phase 100% complete:
a. **Update phase issue BODY**:
   ```
   ✅ Phase X Complete
   
   All Y tasks completed successfully.
   
   [original body content preserved]
   ```

b. **Close the phase issue** (not just comment!)

c. **Update parent issue BODY** (NOT comment):
   - Locate parent issue number
   - Update progress tracker in body:
     ```
     ## Progress
     - [x] Phase 1: Feature Specification
     - [x] Phase 2: Implementation Planning
     - [x] Phase 3: Core Implementation
     - [x] Phase 4: Testing & Documentation  ← Mark this complete
     - [ ] Phase 5: Deployment
     
     **Overall**: 4/5 phases complete (80%)
     ```

d. **Add comment to parent issue**:
   ```
   Phase X (#issue-number) complete. See PR #XXX for details.
   ```

#### For Regular Issues:
- Update issue body with completion summary
- Close the issue
- Add final comment explaining closure

### 3. Task Syncing to GitHub

**For Speckit features**, sync tasks to GitHub Issues using the script:

```bash
# STEP 1: Verify milestone name (CRITICAL - must match exactly)
gh api repos/:owner/:repo/milestones | jq -r '.[].title'

# Look for milestone matching feature ID (e.g., "003-project-model-config")
# Milestone name is CASE-SENSITIVE and must include feature ID prefix

# STEP 2: Run sync script with DRY RUN first
scripts/sync-task-status.sh \
  --tasks-file "specs/003-project-model-config/tasks.md" \
  --milestone "003-project-model-config" \
  --dry-run

# STEP 3: Review output carefully

# STEP 4: If output looks correct, run without --dry-run
scripts/sync-task-status.sh \
  --tasks-file "specs/003-project-model-config/tasks.md" \
  --milestone "003-project-model-config"
```

**Arguments required:**
- `--tasks-file`: Path to tasks.md (e.g., `specs/003-project-model-config/tasks.md`)
- `--milestone`: Exact milestone name from GitHub (verify first!)
- `--dry-run`: Optional, but recommended for first run

**Common mistakes to avoid:**
- ❌ Running script without arguments
- ❌ Wrong milestone name (case-sensitive!)
- ❌ Missing feature ID prefix in milestone
- ❌ Skipping dry-run validation

### 4. PR Updates (Speckit Multi-Phase)

**Update draft PR description** with phase completion:

```markdown
## Progress Tracker

- [x] Phase 1: Feature Specification (✅ #601)
- [x] Phase 2: Implementation Planning (✅ #602)
- [x] Phase 3: Core Implementation (✅ #655)
- [x] Phase 4: Testing & Documentation (✅ #659)  ← Update this
- [ ] Phase 5: Deployment & Monitoring

**Overall Progress**: 268/286 tasks (94%)
```

**Add comment to PR:**
```
Phase X (#issue-number) complete. All Y tasks finished.
```

**IF all phases complete:**
- Convert draft PR to ready for review
- Update PR title if needed
- Ensure proper labels/milestone

**IF phases remain:**
- Keep PR as draft
- Note which phase is next

### 5. What NOT to Do

- ❌ Don't just add comments to issues - UPDATE THE BODY
- ❌ Don't leave completed phase issues open
- ❌ Don't run sync-task-status.sh without verifying milestone name
- ❌ Don't skip the --dry-run on first execution
- ❌ Don't forget to update parent issue body (not just comment)

## Handoff

After finalization, **auto-suggest** `session.wrap`:

```
✅ Session finalized successfully

**Next step:** Document and close session
→ invoke session.wrap
```

**Reasoning**: session.finalize completes all post-merge issue management (closing phase issues, updating parent issue, syncing tasks to GitHub). The final step is session.wrap, which documents the session in CHANGELOG.md and daily summary, then archives the session. This separation ensures issue management is complete before documentation.

## Usage

```bash
invoke session.finalize
```

Invoke after:
1. PR has been merged to main (validated by script)
2. CI checks have passed
3. Ready to close issues and update tracking

## Example Output

```
✅ Session finalized successfully

**Phase Issue**: Closed #659 (Phase 6 complete)
**Parent Issue**: Updated #654 (90% complete - 245/271 tasks)
**Tasks Synced**: 47 tasks updated in GitHub milestone "003-project-model-config"
**PR Updated**: #661 - Phase 6 marked complete in description

**Next step:** Document and close session
→ invoke session.wrap
```
