---
agent: session.finalize
version: 1.1.0
---

You are executing the session.finalize agent. Your job is to finalize the session by managing issues and syncing task completion after PR merge.

## ⚠️ CRITICAL: Workflow Order

**session.finalize runs AFTER the PR is merged, but BEFORE session.wrap!**

The correct workflow order is:
```
validate → publish → [USER MERGES PR] → finalize → wrap
```

If the PR has not been merged yet, tell the user to merge first.

## ⚠️ CRITICAL: Read Technical Context First

**BEFORE running any commands**, read `.session/project-context/technical-context.md` to understand:
- Whether this is a **containerized** environment (Docker)
- The correct commands for any operations
- The project root path

### Common Mistakes to Avoid:
- ❌ Running `python`, `npm`, `go` directly if containerized
- ❌ Using paths like `/root/` (doesn't exist)
- ❌ Assuming local dependencies are installed

## Prerequisites

This agent assumes:
1. `session.execute` completed implementation
2. `session.validate` verified quality
3. `session.publish` created/updated PR
4. **PR has been merged** (validated by script)

## Outline

### 1. Load Session Context

```bash
# Get active session
SESSION_DIR=$(cat .session/ACTIVE_SESSION)
SESSION_INFO="$SESSION_DIR/session-info.json"

# Parse session metadata
SESSION_TYPE=$(jq -r '.session.type' "$SESSION_INFO")
ISSUE_NUMBER=$(jq -r '.issue_number // empty' "$SESSION_INFO")
PARENT_ISSUE=$(jq -r '.parent_issue // empty' "$SESSION_INFO")
FEATURE_ID=$(jq -r '.feature_id // empty' "$SESSION_INFO")
PR_NUMBER=$(jq -r '.pr_number // empty' "$SESSION_INFO")
```

### 2. Call Finalize Script

```bash
.session/scripts/bash/session-finalize.sh --json
```

The script will:
- Validate PR is merged
- Handle session type-specific logic
- Close appropriate issues
- Update parent issue (if Speckit)
- Mark tasks complete
- Sync to GitHub Projects

### 3. Parse Script Output

Expected JSON structure:

**For GitHub issue session:**
```json
{
  "status": "success",
  "pr_merged": true,
  "session_type": "github_issue",
  "issue": {
    "number": 663,
    "closed": true,
    "comment": "Resolved via PR #664"
  },
  "tasks": {
    "file": ".session/sessions/2025-12-18-2/tasks.md",
    "total": 7,
    "completed": 7
  },
  "ready_for_wrap": true
}
```

**For Speckit session:**
```json
{
  "status": "success",
  "pr_merged": true,
  "session_type": "speckit",
  "phase_issue": {
    "number": 610,
    "closed": true,
    "comment_posted": true
  },
  "parent_issue": {
    "number": 654,
    "updated": true,
    "progress": "4/6 phases complete",
    "checklist_updated": true
  },
  "tasks": {
    "file": "specs/003-project-model-config/tasks.md",
    "total": 47,
    "completed": 30,
    "marked_complete": ["T042", "T043", "T044"]
  },
  "pr": {
    "number": 661,
    "description_updated": true,
    "still_draft": true,
    "reason": "More phases remaining"
  },
  "synced_to_projects": true,
  "ready_for_wrap": true
}
```

**If PR not merged:**
```json
{
  "status": "error",
  "error": "PR not merged",
  "pr": {
    "number": 665,
    "state": "open",
    "merged": false
  },
  "message": "Please merge PR first, then retry /session.finalize"
}
```

### 4. Report Results

Based on session type and results, report to user:

**For GitHub issue:**
```
✅ Session finalized

Issue #663: Closed
PR #664: Merged
Tasks: 7/7 complete

Ready to wrap → /session.wrap
```

**For Speckit:**
```
✅ Phase finalized

Phase issue #610: Closed
Parent issue #654: Updated (4/6 phases complete)
PR #661: Description updated (draft, more phases remaining)
Tasks: specs/003-project-model-config/tasks.md (30/47 complete)
Synced to GitHub Projects: ✅

Ready to wrap → /session.wrap
```

**On error:**
```
❌ Cannot finalize: PR not merged

PR #665 status: open
Please:
1. Merge the PR in GitHub
2. Then run: /session.finalize

Or if PR was merged but not detected:
- Check PR status: gh pr view 665
- Verify merge commit exists
```

### 5. Handoff

Suggest `/session.wrap` but don't auto-invoke (`send: false`):

```
Ready to document session → /session.wrap
```

## Speckit Logic Details

The script handles Speckit sessions specially:

1. **Close Phase Issue**:
   ```bash
   gh issue close $PHASE_ISSUE --comment "✅ Phase X complete. All tasks done."
   ```

2. **Update Parent Issue**:
   - Calculate progress (phases complete / total phases)
   - Update progress in parent issue body
   - Mark phase checkbox complete if parent has checklist

3. **Update Draft PR**:
   - Add phase completion notes to PR description
   - Keep as draft if more phases remain
   - Convert to ready if all phases complete

4. **Sync to Projects**:
   ```bash
   ./scripts/sync-task-status.sh specs/$FEATURE_ID/tasks.md \
     --milestone "Feature Name"
   ```

5. **Mark Tasks Complete**:
   - Update specs/$FEATURE_ID/tasks.md with [x]
   - Only mark tasks completed in this session

## Error Handling

### PR Not Merged
- Check via `gh pr view --json merged`
- If not merged: ERROR and exit
- User must merge first

### Issue Already Closed
- Check issue state before closing
- If already closed: Skip, report in output
- Not an error (idempotent)

### Parent Issue Not Found
- For Speckit: ERROR if parent issue missing
- Check session-info.json for parent_issue
- Report clear error message

### Sync Script Fails
- Report warning but don't fail
- Manual sync may be needed
- Provide manual sync command

## Notes

- **Validates merge**: Always checks PR merged before proceeding
- **Idempotent**: Can run multiple times safely
- **Handles both workflows**: GitHub issue and Speckit
- **Manual handoff**: User decides when to wrap
