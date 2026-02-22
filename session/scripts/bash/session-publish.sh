#!/usr/bin/env bash
# session-publish.sh - Create or update pull request for session work
#
# Usage:
#   session-publish.sh --title "PR title" --description "PR body" [--draft|--ready] --issue NUM --json
#
# Outputs JSON with PR details and next steps

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/session-common.sh"

# Parse arguments
TITLE=""
DESCRIPTION=""
PR_TYPE="ready"
ISSUE_NUMBER=""
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --title)
            TITLE="$2"
            shift 2
            ;;
        --description)
            DESCRIPTION="$2"
            shift 2
            ;;
        --draft)
            PR_TYPE="draft"
            shift
            ;;
        --ready)
            PR_TYPE="ready"
            shift
            ;;
        --issue)
            ISSUE_NUMBER="$2"
            shift 2
            ;;
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

# Validate required arguments
if [ -z "$TITLE" ]; then
    json_error_msg "Missing required argument: --title" >&2
    exit 1
fi

# Get current branch
CURRENT_BRANCH=$(git branch --show-current)
if [ -z "$CURRENT_BRANCH" ]; then
    json_error_msg "Not on a branch" >&2
    exit 1
fi

# Detect default branch (origin/HEAD, then gh, then fallback to main)
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
if [ -z "$DEFAULT_BRANCH" ]; then
    DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo "")
fi
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

# Check if branch has commits
COMMITS_AHEAD=$(git rev-list --count "origin/${DEFAULT_BRANCH}..HEAD" 2>/dev/null || echo "0")
if [ "$COMMITS_AHEAD" = "0" ]; then
    json_error_msg "No commits to create PR from" >&2
    exit 1
fi

# Check if PR already exists
PR_NUMBER=$(gh pr view --json number -q .number 2>/dev/null || echo "")

if [ -n "$PR_NUMBER" ]; then
    # Update existing PR
    gh pr edit "$PR_NUMBER" --title "$TITLE" --body "$DESCRIPTION" >/dev/null 2>&1
    
    PR_URL=$(gh pr view "$PR_NUMBER" --json url -q .url)
    PR_STATE=$(gh pr view "$PR_NUMBER" --json state -q .state)
    PR_DRAFT=$(gh pr view "$PR_NUMBER" --json isDraft -q .isDraft)
    
    if [ "$JSON_OUTPUT" = true ]; then
        cat <<EOF
{
  "pr": {
    "number": $PR_NUMBER,
    "url": "$PR_URL",
    "state": "$PR_STATE",
    "draft": $PR_DRAFT,
    "action": "updated",
    "linked_issues": [${ISSUE_NUMBER:-}]
  },
  "next_steps": [
    "🔍 Monitor CI checks: ${PR_URL}/checks",
    "🔧 Fix any CI failures if needed",
    "👀 Get PR reviewed (if required)",
    "✅ Merge PR when ready",
    "▶️  Then run: invoke session.finalize"
  ]
}
EOF
    else
        echo "✅ Updated existing PR #$PR_NUMBER"
        echo "URL: $PR_URL"
    fi
else
    # Create new PR
    if [ "$PR_TYPE" = "draft" ]; then
        DRAFT_FLAG="--draft"
    else
        DRAFT_FLAG=""
    fi
    
    # Create PR
    gh pr create \
        --title "$TITLE" \
        --body "$DESCRIPTION" \
        --base "$DEFAULT_BRANCH" \
        --head "$CURRENT_BRANCH" \
        $DRAFT_FLAG \
        >/dev/null 2>&1
    
    # Get PR details
    PR_NUMBER=$(gh pr view --json number -q .number)
    PR_URL=$(gh pr view "$PR_NUMBER" --json url -q .url)
    PR_STATE=$(gh pr view "$PR_NUMBER" --json state -q .state)
    PR_DRAFT=$(gh pr view "$PR_NUMBER" --json isDraft -q .isDraft)
    
    if [ "$JSON_OUTPUT" = true ]; then
        cat <<EOF
{
  "pr": {
    "number": $PR_NUMBER,
    "url": "$PR_URL",
    "state": "$PR_STATE",
    "draft": $PR_DRAFT,
    "action": "created",
    "linked_issues": [${ISSUE_NUMBER:-}]
  },
  "next_steps": [
    "🔍 Monitor CI checks: ${PR_URL}/checks",
    "🔧 Fix any CI failures if needed",
    "👀 Get PR reviewed (if required)",
    "✅ Merge PR when ready",
    "▶️  Then run: invoke session.finalize"
  ]
}
EOF
    else
        echo "✅ Created PR #$PR_NUMBER"
        echo "URL: $PR_URL"
    fi
fi
