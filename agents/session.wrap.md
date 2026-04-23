---
name: session-wrap
description: End the session — write final summary, update CHANGELOG, and clear session state. Terminal step in the workflow chain.
tools: ["*"]
---

# session.wrap

**Purpose**: End the session — write final summary, update CHANGELOG, and clear session state. Terminal step.

**IMPORTANT**: Read `.session/docs/shared-workflow.md` for shared workflow rules.

## ⛔ SCOPE BOUNDARY

**This agent ONLY documents and archives the session. It does NOT:**
- ❌ Close issues or clean branches (that's `session.finalize`)
- ❌ Create or merge PRs (that's `session.publish`)
- ❌ Run validation or fix code (earlier steps)
- ❌ Start new sessions

**Output**: Updated `notes.md`, `next.md`, `CHANGELOG.md`, `final-summary.md` — then runs wrap script.

## ⚠️ CRITICAL: Workflow State Tracking

**ON ENTRY** — run preflight (validates transition, marks step `in_progress`):
```bash
.session/scripts/bash/session-preflight.sh --step wrap --json
```

⛔ **STOP HERE** until you receive script output. Do NOT proceed without it.

**Note**: session.wrap is terminal — `session-wrap.sh` marks both the workflow step and session as completed, so no separate postflight call is needed. This is the one exception to the shared-workflow.md rule that every agent runs postflight.

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

Complete ALL steps IN ORDER before running the wrap script. The script enforces the archival wrap commit and blocks unsafe dirty-git states, but it still does not validate checklist compliance for you.

**Pre-flight Checklist** (verify before proceeding):
- [ ] All tasks in `tasks.md` are marked complete or have [SKIP] reason
- [ ] Tests pass (check project-specific test commands)
- [ ] Feature/work changes are already committed and pushed
- [ ] On the correct branch for the archival wrap commit (typically `main` for docs-only, feature branch otherwise)

## Outline

### 1. Update Session Notes and Handoff Artifacts

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

Update `{session_dir}/next.md` as the **primary follow-up artifact** with:

```markdown
## Completed
## Suggested Next Steps
## Suggested Workflow
## Pending Human Actions
## Blockers
## Carry Forward
```

Keep `notes.md`'s `## For Next Session` section compatible during rollout, but prefer `next.md` for structured follow-up guidance.


### 1.5. Workflow-Agnostic Operation

session.wrap is the terminal agent for all workflows. It documents any session type:
- **development**: Document features, tests, PR link
- **spike**: Document findings, exploration results
- **maintenance**: Document changes made

### 2. Mark Tasks Complete

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

### 4. Create Final Summary

Create `{session_dir}/final-summary.md`:

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

### 5. Leave Only Wrap-Managed Changes Pending

```bash
# Before running the wrap script, the remaining dirty paths should be limited to:
# - {session_dir}/** durable session artifacts (not state.json)
# - CHANGELOG.md
#
# Commit or stash anything else first. session-wrap.sh creates the archival
# wrap commit itself, strips `.session/sessions/**/state.json` from that commit,
# and fails before clearing ACTIVE_SESSION if unrelated dirty paths would be
# swept into it.
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

### 7. Clean Up Session Workspace

```bash
.session/scripts/bash/session-cleanup.sh --json
```

This removes errant files left behind by previous agents (e.g., files accidentally written to `.session/` root instead of the session directory), misplaced session directories, orphaned state files, and empty legacy directories. It is idempotent and safe to run on a clean workspace.

Report the cleanup result (what was removed/moved, if anything) in the final-summary.

### 8. Finalize Session

```bash
.session/scripts/bash/session-wrap.sh --json
```

This marks the session complete by:
- Creating the archival wrap commit for `CHANGELOG.md` and durable session-history artifacts
- Updating local `state.json` with completion timestamp (without archiving it in git)
- Clearing `ACTIVE_SESSION` sentinel

After the script succeeds, push the wrap commit:

```bash
git push
```

## Notes

- Complete ALL documentation steps before running the wrap script
- The wrap script is mechanical - it doesn't validate your work, but it does create the archival wrap commit
- Good handoff notes make the next session efficient
- **⛔ Boundary reminder**: Do NOT close issues, merge PRs, or do any work outside documentation. Documentation ONLY.
- Durable session data is preserved in `.session/sessions/{id}/`; local `state.json` bookkeeping remains available but is not part of the archival commit

**No Handoff After Wrap**: session.wrap is the terminal agent in the workflow. It documents and archives the session, then clears the ACTIVE_SESSION sentinel. The next session starts fresh with `session.start`.

## CRITICAL: Only Create Specified Files

**DO NOT create extra files not specified in this prompt.**

The ONLY files you should create or modify are:
1. `{session_dir}/notes.md` - Update with summary
2. `{session_dir}/tasks.md` - Mark tasks complete
3. `CHANGELOG.md` - Add session entry
4. `{session_dir}/final-summary.md` - Create final summary

**DO NOT create:**
- ❌ WRAP_SUMMARY.md
- ❌ SESSION_COMPLETE.md
- ❌ Any other summary/report files not listed above

The session state is tracked locally in `state.json` by the wrap script - no additional files needed.

## Session Type Considerations

**GitHub issue / Unstructured sessions:**
- Tasks tracked in `.session/sessions/{id}/tasks.md`
- Update this file with [x] marks for completed tasks
- Close GitHub issue if work is complete and merged
