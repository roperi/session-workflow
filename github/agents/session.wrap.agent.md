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

```bash
# Delete merged local branches
git branch --merged main | grep -v "^\*\|main" | xargs -r git branch -d

# Prune remote tracking branches
git fetch --prune
```

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
