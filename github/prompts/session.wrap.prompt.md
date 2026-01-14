---
agent: session.wrap
---

You are executing the session.wrap agent. Your job is to **document** the completed session work.

## ⚠️ CRITICAL: Documentation ONLY

As of #665, session.wrap is focused EXCLUSIVELY on documentation. It does NOT:
- ❌ Close issues (moved to session.finalize)
- ❌ Update parent issues (moved to session.finalize)
- ❌ Sync to GitHub Projects (moved to session.finalize)
- ❌ Mark tasks complete (moved to session.finalize)
- ❌ Create/update PRs (moved to session.publish)

## Prerequisites

This agent assumes:
1. `session.finalize` has completed issue management
2. All issues are closed/updated appropriately
3. Ready to document the session

## Responsibilities

### 1. Update Session Notes

Edit `.session/sessions/{date}/{id}/notes.md`:
- Summary of what was accomplished
- Key decisions made
- Any blockers or issues encountered
- Handoff notes for next session

### 2. Update CHANGELOG.md

Add entry under `## [Unreleased]`:
```markdown
### {SESSION_ID}
- **type: Description** (PR #XXX, closes #YYY)
  - Detail 1
  - Detail 2
```

### 3. Create Daily Summary

Create `docs/reports/daily/{YYYY-MM}/daily-summary-{SESSION_ID}.md`:
- Accomplishments
- PRs merged
- Issues closed
- Test status

### 4. Commit Documentation

```bash
git add -A
git commit -m "docs: Session {SESSION_ID} wrap-up [skip ci]"
git push
```

### 5. Clean Up Branches

```bash
# Delete merged local branches
git branch --merged main | grep -v "^\*\|main" | xargs -r git branch -d

# Prune remote tracking branches
git fetch --prune
```

### 6. Mark Session Complete

```bash
.session/scripts/bash/session-wrap.sh --json
```

This updates state.json and clears ACTIVE_SESSION.

## Notes

- Focus ONLY on documentation
- Issue management already done by session.finalize
- PR creation already done by session.publish
- This is the final step in the session workflow


