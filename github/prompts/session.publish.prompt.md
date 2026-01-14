---
agent: session.publish
---

You are executing the session.publish agent. Your job is to create or update a pull request for the completed session work.

## Prerequisites

This agent assumes:
1. `session.execute` has completed implementation
2. `session.validate` has verified quality checks pass
3. All code is committed and pushed

## Outline

### 1. Load Session Context

```bash
# Get active session
SESSION_DIR=$(cat .session/ACTIVE_SESSION)
SESSION_INFO="$SESSION_DIR/session-info.json"

# Parse session metadata
SESSION_TYPE=$(jq -r '.session.type' "$SESSION_INFO")
ISSUE_NUMBER=$(jq -r '.issue_number // empty' "$SESSION_INFO")
FEATURE_ID=$(jq -r '.feature_id // empty' "$SESSION_INFO")
```

### 2. Generate PR Description

**AI Responsibility**: Create comprehensive PR description including:

```markdown
## Summary
{Brief description from session summary}

## Changes
{List from commit messages on this branch}

## Testing
- ✅ {test_count} tests passing
- ✅ Coverage: {coverage}%
- ✅ Lint: passing

## Related
- Closes #{issue_number}
{For Speckit: - Part of #{parent_issue}}
```

**Pass generated description to script via stdin or file**.

### 3. Call Publish Script

```bash
# Generate description first (AI task)
DESCRIPTION=$(generate_pr_description)

# Determine PR type
if [ "$SESSION_TYPE" = "speckit" ] && [ "$PHASE_NUMBER" = "1" ]; then
  PR_TYPE="--draft"
else
  PR_TYPE="--ready"
fi

# Call script
.session/scripts/bash/session-publish.sh \
  --title "$(generate_pr_title)" \
  --description "$DESCRIPTION" \
  $PR_TYPE \
  --issue "$ISSUE_NUMBER" \
  --json
```

### 4. Parse and Report Results

Parse JSON output from script:

```json
{
  "pr": {
    "number": 665,
    "url": "https://github.com/owner/repo/pull/665",
    "state": "open",
    "draft": false,
    "action": "created",
    "linked_issues": [665]
  },
  "next_steps": [
    "🔍 Monitor CI checks in GitHub",
    "🔧 Fix any CI failures",
    "👀 Get PR reviewed",
    "✅ Merge when ready",
    "▶️  Run: /session.finalize"
  ]
}
```

Report to user:
```
✅ PR #{number} {created|updated}

URL: {pr_url}
Status: {draft ? "Draft" : "Ready for review"}
Linked: Closes #{issue_number}

Next steps:
{list next_steps from JSON}
```

### 5. Handoff

Suggest `/session.finalize` but don't auto-invoke (`send: false`):

```
Ready to finalize after PR merge → /session.finalize
```

## Error Handling

### If PR creation fails
- Report error from script
- Suggest manual PR creation
- Provide all details (title, description, issue link)

### If branch has no commits
- Report: "No commits to create PR from"
- Suggest checking git status
- Exit gracefully

## Notes

- **No CI monitoring**: User monitors in GitHub
- **Manual handoff**: User decides when to finalize (after merge)
- **Idempotent**: Can run multiple times (updates existing PR)
