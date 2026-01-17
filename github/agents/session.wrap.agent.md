---
description: Finalize session with documentation and cleanup (end of session workflow chain)
tools: ['bash']
---

## User Input

```text
$ARGUMENTS
```

**Argument Support**:
- `--comment "text"`: Special wrap instructions (e.g., "Skip changelog update")

**Behavior**:
- **`--resume` not applicable**: This is a one-shot final operation
- **If `--comment` provided**: 
  - May skip certain wrap steps per instruction
  - Use for edge cases or partial wraps
- **Default**: Full wrap workflow with all documentation

You **MUST** consider the user input before proceeding (if not empty).

## ⚠️ CRITICAL: All Steps Are Mandatory

Complete ALL steps IN ORDER before running the wrap script. The script only marks the session complete - it does not validate.

**Pre-flight Checklist** (verify before proceeding):
- [ ] All tasks in `tasks.md` are marked complete or have [SKIP] reason
- [ ] Tests pass (check project-specific test commands)
- [ ] Code is committed and pushed
- [ ] On correct branch for wrap commits (typically `main` for docs-only, feature branch otherwise)

## Outline

### 1. Update Session Notes

Edit `{session_dir}/notes.md` with:

```markdown
## Summary
<!-- What was accomplished this session? -->

## Key Decisions
<!-- Decisions made that affect future work -->

## Blockers/Issues
<!-- Problems encountered, unresolved issues -->

## For Next Session
- Current state: [describe what's done and what's pending]
- Next steps: [specific actions for next AI]
- Context needed: [any special context next AI should know]
```


### 1.5. Workflow-Agnostic Operation

**NEW (Schema v2.0)**: session.wrap is the terminal agent for all workflows:

```bash
# Source common functions
source .session/scripts/bash/session-common.sh

# Detect workflow
WORKFLOW=$(detect_workflow "$SESSION_ID")
echo "Workflow: $WORKFLOW"

# Wrap handles all workflows the same way - document the session
echo "✓ Documenting $WORKFLOW session"
```

**All workflows welcome**: This agent documents any session type.

**Workflow-specific documentation**:
- **development**: Document features, tests, PR link
- **advisory**: Document advice given, recommendations
- **experiment**: Document findings, conclusions

No workflow guards needed - this is a terminal agent.

### 2. Mark Tasks Complete

**CRITICAL: Update BOTH task files for Speckit sessions**

#### For Speckit Features:

**Step 1**: Update Speckit tasks.md (source of truth)
```bash
# Update specs/XXX/tasks.md
# Mark completed tasks as [x]
# Update progress count
```

**Step 2**: Update session tasks.md (session record)
```bash
# Copy or mirror changes to .session/sessions/YYYY-MM-DD-N/tasks.md
# MUST match Speckit tasks.md for consistency

# Simple approach: Copy if session tasks.md mirrors Speckit
cp specs/003-project-model-config/tasks.md .session/sessions/2025-12-19-1/tasks.md

# OR if session tasks.md is a summary, update it to reflect completion
```

**Rationale**: Next session needs consistent view. If session tasks.md is empty/stale while Speckit tasks.md is updated, it creates confusion.

#### For Non-Speckit Sessions:

Update `.session/sessions/{id}/tasks.md`:
- Mark completed tasks as `[x]`
- Update progress count at bottom

### 3. Update CHANGELOG.md

Add entry under `## [Unreleased]`:

```markdown
### {SESSION_ID}
- **type: Description** (#PR, closes #Issue)
  - Detail 1
  - Detail 2
```

### 4. Create Daily Summary

Create `docs/reports/daily/YYYY-MM/daily-summary-{SESSION_ID}.md`:

```markdown
# Daily Summary: {SESSION_ID}

## Accomplishments
- What was done

## PRs Merged
- #123: Description

## Issues Closed  
- #456: Description

## Test Status
- All tests passing / Notes about test changes
```

### 5. Commit and Push

```bash
git add -A
git commit -m "docs: Session {SESSION_ID} wrap-up [skip ci]"
git push
```

### 6. Clean Up Branches

**CRITICAL**: Only delete remote branches that have been MERGED. Feature branches may span multiple sessions.

```bash
# Get the session's feature branch name from state.json
SESSION_BRANCH=$(cat .session/sessions/{id}/state.json | jq -r '.branch // empty')

# Only attempt deletion if we have a branch and it's not main
if [ -n "$SESSION_BRANCH" ] && [ "$SESSION_BRANCH" != "main" ]; then
    
    # SAFETY CHECK: Only delete if branch is merged into main
    # This prevents deleting active feature branches that span multiple sessions
    if git branch --merged main | grep -q "$SESSION_BRANCH"; then
        echo "Branch '$SESSION_BRANCH' is merged into main"
        
        # Delete local branch if exists
        git branch -d "$SESSION_BRANCH" 2>/dev/null || true
        
        # Delete remote branch if exists
        if git ls-remote --heads origin "$SESSION_BRANCH" | grep -q "$SESSION_BRANCH"; then
            echo "Deleting remote branch: $SESSION_BRANCH"
            git push origin --delete "$SESSION_BRANCH"
        fi
    else
        echo "⚠️  Branch '$SESSION_BRANCH' is NOT merged - keeping it"
        echo "   (Feature branches spanning multiple sessions are preserved)"
    fi
fi

# Clean up any other merged local branches
git branch --merged main | grep -v "^\*\|main" | xargs -r git branch -d

# Prune stale remote tracking branches
git fetch --prune
```

**Safety Rules**:
- ✅ Delete branch only if merged into main
- ✅ Feature branches spanning multiple sessions are preserved
- ❌ NEVER delete unmerged branches

### 7. Finalize Session

```bash
.session/scripts/bash/session-wrap.sh --json
```

This marks the session complete by:
- Updating `state.json` with completion timestamp
- Clearing `ACTIVE_SESSION` sentinel

## Notes

- Complete ALL documentation steps before running the wrap script
- The wrap script is purely mechanical - it doesn't validate your work
- Good handoff notes make the next session efficient
- Session data is preserved in `.session/sessions/{id}/`

**No Handoff After Wrap**: session.wrap is the terminal agent in the workflow. It documents and archives the session, then clears the ACTIVE_SESSION sentinel. The next session starts fresh with `/session.start`.

## CRITICAL: Only Create Specified Files

**DO NOT create extra files not specified in this prompt.**

The ONLY files you should create or modify are:
1. `{session_dir}/notes.md` - Update with summary
2. `{session_dir}/tasks.md` - Mark tasks complete
3. `CHANGELOG.md` - Add session entry
4. `docs/reports/daily/YYYY-MM/daily-summary-{SESSION_ID}.md` - Create daily summary

**DO NOT create:**
- ❌ WRAP_SUMMARY.md
- ❌ SESSION_COMPLETE.md
- ❌ Any other summary/report files not listed above

The session state is tracked in `state.json` by the wrap script - no additional files needed.

## Session Type Considerations

**Speckit sessions:**
- Tasks tracked in `specs/{feature}/tasks.md` (source of truth)
- Session tasks.md MUST be kept in sync (copy or mirror)
- Both files should show same completion status
- This prevents confusion in next session

**GitHub issue / Unstructured sessions:**
- Tasks tracked in `.session/sessions/{id}/tasks.md`
- Update this file with [x] marks for completed tasks
- Close GitHub issue if work is complete and merged
