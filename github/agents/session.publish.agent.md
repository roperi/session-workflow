---
description: Create or update pull request for session work
tools: ["*"]
---

# session.publish

**Purpose**: Creates or updates pull request with AI-generated description.

## User Input

```text
$ARGUMENTS
```

**Argument Support**:
- `--comment "text"`: Special PR instructions (e.g., "Mark as draft", "Add WIP to title")
- `--resume`: Update existing PR instead of creating new

**Behavior**:
- **If `--resume` flag present**: 
  - Find existing PR for current branch
  - Update PR description/title instead of creating new
  - Append to existing PR body if needed
- **If `--comment` provided**: 
  - Use for PR customization (draft status, labels, etc.)
  - May affect PR title or description format
- **Default**: Create new PR or update if exists

## BEFORE Running Tests

**Check for existing validation results** to avoid re-running tests:

```bash
if [ -f .session/validation-results.json ]; then
  cat .session/validation-results.json
  # Check timestamp (must be <30 min old)
  timestamp=$(jq -r '.timestamp' .session/validation-results.json)
fi
```

**IF validation-results.json exists AND is fresh (<30 min old):**
- Use those results for PR description
- **DO NOT re-run any tests**
- Include test summary from validation results

**IF no validation file OR stale:**
- Run minimal validation:
  ```bash
  # Run project-specific lint and test commands
  # Check .session/project-context/technical-context.md
  ```
- Create basic validation-results.json

## Responsibilities

1. **PR Detection**:
   - Check if PR already exists for current branch
   - Determine if creating new or updating existing

2. **PR Description Generation** (AI responsibility):
   
   **Use validation-results.json** for test status:
   ```
   ## Test Results
   
   ✅ **Backend Lint**: Passed (9.99/10)
   ✅ **Unit Tests**: 387 passed, 72.51% coverage
   ❌ **Integration Tests**: 248 passed, 2 failed
      - test_api_compatibility.py::test_foo
      - test_api_compatibility.py::test_bar
   ✅ **Frontend Tests**: 522 passed, 65 suites
   
   **Coverage**: 71.11% (exceeds 70% requirement)
   ```
   
   Also include:
   - Session summary
   - Changes from commit messages
   - Link to related issues
   - Known issues (if validation failed)

3. **PR Creation/Update**:
   - Create draft PR (for work in progress)
   - Update existing PR description
   - Link to issues (Closes #XXX for parent, Addresses #XXX for phases)
   - Assign labels and milestone

4. **Report Status**:
   - Provide PR URL
   - Summary of validation results
   - Next steps

## Decision Logic

### IF validation passed (overall: "pass"):
```
✅ PR updated successfully

**Next Steps:**
1. Monitor CI at [PR URL]
2. Once CI passes and PR is merged: `/session.finalize`
3. Then wrap up: `/session.wrap`

**Why /session.finalize next?**
- session.finalize closes issues and syncs task progress (requires merged PR)
- session.wrap documents the session (requires all work complete)
- User must monitor CI and merge PR before finalizing
```

### IF validation failed (overall: "fail"):
```
⚠️ PR updated with known issues

**Known Issues:**
- 2 integration tests failing (see PR description)

**Next Steps:**
1. Fix issues in next session, OR
2. If acceptable, merge as-is (draft PR)
3. After merge: `/session.finalize`
4. Then wrap up: `/session.wrap`

**Why /session.finalize next?**
- session.finalize handles post-merge issue management
- session.wrap is the final documentation step
- Can't finalize until PR is merged to main
```

## Next step

After successful PR creation/update:

**Next step:** `/session.finalize` (after PR merged to main)

## CRITICAL: PR Merge Rules

**🚨 NEVER bypass these rules:**

1. **CI Must Pass Before Merge**
   - DO NOT merge a PR before CI completes successfully
   - User must monitor CI in GitHub UI
   - Code review agents (if any) must review first

2. **Check PR Status Before Merging**
   ```bash
   # User should check:
   gh pr view <number> --json statusCheckRollup,reviews
   # Verify CI status: "SUCCESS"
   ```

3. **After Merge**
   - User runs `/session.finalize` to close issues
   - session.finalize handles issue management

## What NOT to Do

- ❌ Don't re-run tests if validation-results.json exists and is fresh
- ❌ Don't suggest `/session.start` or `/session.wrap` immediately
- ❌ Don't monitor CI (that's user's responsibility in GitHub UI)
- ❌ Don't auto-merge PRs
- ❌ Don't auto-chain to session.finalize (PR must be merged first)

## Usage

```bash
/session.publish
```


### 1.5. Check Workflow Compatibility

**NEW (Schema v2.0)**: Verify this agent is appropriate for the workflow:

```bash
# Source common functions
source .session/scripts/bash/session-common.sh

# Check if publishing is allowed for this workflow
if ! check_workflow_allowed "$SESSION_ID" "development"; then
    echo "❌ session.publish is only for development workflow"
    echo "Spike workflow does not create PRs"
    exit 1
fi

echo "✓ Workflow check passed - proceeding with PR creation"
```

**Allowed workflows**: development only

**Blocked workflows**:
- **spike**: Research/exploration work not intended for production PRs

Only development workflow creates pull requests for review.

