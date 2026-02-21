#!/usr/bin/env bash
# session-finalize.sh - Finalize session by managing issues and syncing tasks
#
# Usage:
#   session-finalize.sh --json
#
# Outputs JSON with finalization results

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/session-common.sh"

JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Get active session
if [ ! -f "$ACTIVE_SESSION_FILE" ]; then
    json_error_msg "No active session" >&2
    exit 1
fi

SESSION_ID=$(cat "$ACTIVE_SESSION_FILE")
SESSION_DIR=$(get_session_dir "$SESSION_ID")
SESSION_INFO="$SESSION_DIR/session-info.json"

if [ ! -f "$SESSION_INFO" ]; then
    json_error_msg "Session info not found" >&2
    exit 1
fi

# Parse session metadata
SESSION_TYPE=$(jq -r '.type' "$SESSION_INFO")
ISSUE_NUMBER=$(jq -r '.issue_number // empty' "$SESSION_INFO")
PARENT_ISSUE=$(jq -r '.parent_issue // empty' "$SESSION_INFO")
FEATURE_ID=$(jq -r '.feature_id // empty' "$SESSION_INFO")

# Detect PR number for current branch
CURRENT_BRANCH=$(git branch --show-current)
PR_NUMBER=$(gh pr view --json number -q .number 2>/dev/null || echo "")

if [ -z "$PR_NUMBER" ]; then
    json_error_msg "No PR found for current branch" >&2
    exit 1
fi

# Check if PR is merged
PR_MERGED=$(gh pr view "$PR_NUMBER" --json merged -q .merged)
if [ "$PR_MERGED" != "true" ]; then
    PR_STATE=$(gh pr view "$PR_NUMBER" --json state -q .state)
    if [ "$JSON_OUTPUT" = true ]; then
        json_error_msg "PR not merged" "Merge PR #${PR_NUMBER} first, then retry /session.finalize"
    else
        echo "❌ Cannot finalize: PR #$PR_NUMBER not merged (state: $PR_STATE)"
        echo "Please merge the PR first, then run /session.finalize"
    fi
    exit 1
fi

# Handle finalization based on session type
case "$SESSION_TYPE" in
    "github_issue")
        # Close issue with comment
        if [ -n "$ISSUE_NUMBER" ]; then
            ISSUE_STATE=$(gh issue view "$ISSUE_NUMBER" --json state -q .state)
            if [ "$ISSUE_STATE" = "OPEN" ]; then
                gh issue close "$ISSUE_NUMBER" --comment "Resolved via PR #$PR_NUMBER" >/dev/null 2>&1
                ISSUE_CLOSED=true
            else
                ISSUE_CLOSED=false  # Already closed
            fi
        fi
        
        # Mark tasks complete in session tasks.md
        TASK_FILE="$SESSION_DIR/tasks.md"
        TOTAL_TASKS=$(grep -c "^- \[.\] T" "$TASK_FILE" 2>/dev/null || echo "0")
        COMPLETED_TASKS=$(grep -c "^- \[x\] T" "$TASK_FILE" 2>/dev/null || echo "0")
        
        if [ "$JSON_OUTPUT" = true ]; then
            cat <<EOF
{
  "status": "success",
  "pr_merged": true,
  "session_type": "github_issue",
  "issue": {
    "number": ${ISSUE_NUMBER:-null},
    "closed": $ISSUE_CLOSED,
    "comment": "Resolved via PR #$PR_NUMBER"
  },
  "tasks": {
    "file": "$TASK_FILE",
    "total": $TOTAL_TASKS,
    "completed": $COMPLETED_TASKS
  },
  "ready_for_wrap": true
}
EOF
        else
            echo "✅ Session finalized"
            echo "Issue #$ISSUE_NUMBER: Closed"
            echo "PR #$PR_NUMBER: Merged"
            echo "Tasks: $COMPLETED_TASKS/$TOTAL_TASKS complete"
        fi
        ;;
        
    "speckit")
        # Close phase issue
        if [ -n "$ISSUE_NUMBER" ]; then
            ISSUE_STATE=$(gh issue view "$ISSUE_NUMBER" --json state -q .state)
            if [ "$ISSUE_STATE" = "OPEN" ]; then
                gh issue close "$ISSUE_NUMBER" --comment "✅ Phase complete. All tasks done." >/dev/null 2>&1
                PHASE_CLOSED=true
            else
                PHASE_CLOSED=false
            fi
        fi
        
        # Update parent issue (if exists)
        PARENT_UPDATED=false
        PROGRESS=""
        if [ -n "$PARENT_ISSUE" ]; then
            # Note: Parent issue progress update would require parsing checklist
            # For now, just post a completion comment
            gh issue comment "$PARENT_ISSUE" --body "Phase #$ISSUE_NUMBER complete via PR #$PR_NUMBER" >/dev/null 2>&1 || true
            PARENT_UPDATED=true
            PROGRESS="Comment posted"
        fi
        
        # Mark tasks complete in specs/XXX/tasks.md
        TASK_FILE="specs/$FEATURE_ID/tasks.md"
        if [ -f "$TASK_FILE" ]; then
            TOTAL_TASKS=$(grep -c "^- \[.\] T" "$TASK_FILE" 2>/dev/null || echo "0")
            COMPLETED_TASKS=$(grep -c "^- \[x\] T" "$TASK_FILE" 2>/dev/null || echo "0")
        else
            TOTAL_TASKS=0
            COMPLETED_TASKS=0
        fi
        
        # Update draft PR description (if multi-phase)
        PR_DRAFT=$(gh pr view "$PR_NUMBER" --json isDraft -q .isDraft)
        PR_UPDATED=false
        # Note: Draft PR description update intentionally skipped
        # Multi-phase PR description should be managed by the agent
        
        # Sync to GitHub Projects
        SYNCED=false
        # Note: Project sync would require scripts/sync-task-status.sh to exist
        # and GitHub Projects to be configured
        
        if [ "$JSON_OUTPUT" = true ]; then
            cat <<EOF
{
  "status": "success",
  "pr_merged": true,
  "session_type": "speckit",
  "phase_issue": {
    "number": ${ISSUE_NUMBER:-null},
    "closed": $PHASE_CLOSED,
    "comment_posted": true
  },
  "parent_issue": {
    "number": ${PARENT_ISSUE:-null},
    "updated": $PARENT_UPDATED,
    "progress": "$PROGRESS"
  },
  "tasks": {
    "file": "$TASK_FILE",
    "total": $TOTAL_TASKS,
    "completed": $COMPLETED_TASKS
  },
  "pr": {
    "number": $PR_NUMBER,
    "description_updated": $PR_UPDATED,
    "still_draft": $PR_DRAFT
  },
  "synced_to_projects": $SYNCED,
  "ready_for_wrap": true
}
EOF
        else
            echo "✅ Phase finalized"
            echo "Phase issue #$ISSUE_NUMBER: Closed"
            echo "Parent issue #$PARENT_ISSUE: Updated"
            echo "Tasks: $COMPLETED_TASKS/$TOTAL_TASKS complete"
        fi
        ;;
        
    *)
        # Unstructured session - just mark tasks complete
        TASK_FILE="$SESSION_DIR/tasks.md"
        TOTAL_TASKS=$(grep -c "^- \[.\] T" "$TASK_FILE" 2>/dev/null || echo "0")
        COMPLETED_TASKS=$(grep -c "^- \[x\] T" "$TASK_FILE" 2>/dev/null || echo "0")
        
        if [ "$JSON_OUTPUT" = true ]; then
            cat <<EOF
{
  "status": "success",
  "pr_merged": true,
  "session_type": "unstructured",
  "tasks": {
    "file": "$TASK_FILE",
    "total": $TOTAL_TASKS,
    "completed": $COMPLETED_TASKS
  },
  "ready_for_wrap": true
}
EOF
        else
            echo "✅ Session finalized"
            echo "Tasks: $COMPLETED_TASKS/$TOTAL_TASKS complete"
        fi
        ;;
esac
