---
description: Finalize session by managing issues and syncing tasks post-merge
handoffs:
  - label: Wrap Session
    agent: session.wrap
    prompt: Document and close session
    send: false
---

# session.finalize

**Purpose**: Post-merge issue management and task completion tracking.

## User Input

```text
$ARGUMENTS
```

**Argument Support**:
- `--comment "text"`: Special finalize instructions (e.g., "Skip parent issue update")

**Behavior**:
- **`--resume` not applicable**: This is a one-shot operation post-merge
- **If `--comment` provided**: 
  - May skip certain finalize steps per instruction
  - Use for edge cases or special handling
- **Default**: Full finalize workflow

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
    advisory|experiment)
        echo "✓ $WORKFLOW workflow - issue updates only (no phase/PR tracking)"
        ;;
esac
```

**Behavior by workflow**:
- **development**: Full issue management (close phase, update parent, sync tasks)
- **advisory**: Minimal (document advice given, no issue closure)
- **experiment**: Document findings, close associated issue if applicable

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

After finalization, **auto-suggest** `/session.wrap`:

```
✅ Session finalized successfully

**Next step:** Document and close session
→ `/session.wrap`
```

**Handoff**: `send: false` - suggest next step but wait for user confirmation

**Handoff Reasoning**: session.finalize completes all post-merge issue management (closing phase issues, updating parent issue, syncing tasks to GitHub). The final step is session.wrap, which documents the session in CHANGELOG.md and daily summary, then archives the session. This separation ensures issue management is complete before documentation.

## Usage

```bash
/session.finalize
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
→ `/session.wrap`
```
