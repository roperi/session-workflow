---
description: Initialize session tracking and load project context
tools: ['bash', 'github-mcp-server']
handoffs:
  - label: Plan Session Tasks
    agent: session.plan
    prompt: Generate task list for this session
    send: true
    condition: workflow is development
  - label: Execute Tasks
    agent: session.execute
    prompt: Execute experimental tasks
    send: true
    condition: workflow is experiment
  - label: Document Session
    agent: session.wrap
    prompt: Document advisory session
    send: true
    condition: workflow is advisory
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## ⚠️ CRITICAL: Script Execution Required

**DO NOT SKIP ANY STEPS.** This agent ensures session tracking and continuity.

Before doing ANY work:
1. Run the session-start script (Step 2)
2. Wait for and parse the JSON output
3. Only then proceed to subsequent steps

Skipping steps causes: untracked work, documentation mismatch, broken continuity.

## Outline

### 1. Get Repository Owner/Name

Required before any GitHub API calls:

```bash
gh repo view --json owner,name -q '.owner.login + "/" + .name'
```

Use this exact owner/repo for all GitHub MCP tool calls. **Never guess the repository name.**

### 2. Run Session-Start Script (MANDATORY)

```bash
.session/scripts/bash/session-start.sh --json $ARGUMENTS
```

⛔ **STOP HERE** until you receive script output. Do NOT proceed without it.

If no arguments provided, the script will resume an active session or prompt for session type.

**⚠️ Stale Session Detection**: If ACTIVE_SESSION points to a previous day's session, the script will error and suggest:
- Clear stale session: `rm .session/ACTIVE_SESSION`
- Then start fresh session with proper arguments

**Common invocations:**
- `.session/scripts/bash/session-start.sh --json --issue 123` - Work on GitHub issue
- `.session/scripts/bash/session-start.sh --json --spec 001-feature` - Work on Speckit feature  
- `.session/scripts/bash/session-start.sh --json --goal 'Description'` - Unstructured work
- `.session/scripts/bash/session-start.sh --json --resume` - Resume active session (continue from where you left off)
- `.session/scripts/bash/session-start.sh --json --resume --comment "Continue from Test 5.4"` - Resume with specific instructions

**⚠️ CRITICAL - Session Directory Naming**:
The script creates session directories in the format: `.session/sessions/YYYY-MM/YYYY-MM-DD-N`
- ✅ CORRECT: `.session/sessions/2025-12/2025-12-20-1`
- ❌ WRONG: `.session/sessions/2025-12/session-20251220-105707-issue-660`
- ❌ WRONG: `.session/sessions/2025-12/session-20251220-105715-issue-660`

**DO NOT** manually create session directories with timestamp-based names. Always use the script output's `session.dir` path.

### 3. Parse JSON Output

Extract from the script output:
- `session.id` - Session identifier (YYYY-MM-DD-N)
- `session.type` - Type: speckit, github_issue, or unstructured
- `session.dir` - Directory containing session files
- `resume_mode` - Boolean: true if --resume flag was used
- `user_comment` - String: additional instructions from --comment flag
- `previous_session` - Context from prior session (if any)
- `project_context` - Paths to constitution and technical context


### 3.5. Determine Workflow Routing

**NEW (Schema v2.0)**: Check workflow field from JSON output:

```bash
# Extract workflow from session-info.json
WORKFLOW=$(jq -r '.workflow // "smart"' "$SESSION_DIR/session-info.json")
echo "Workflow: $WORKFLOW"

# If smart workflow, detect actual workflow
if [[ "$WORKFLOW" == "smart" ]]; then
    source .session/scripts/bash/session-common.sh
    WORKFLOW=$(detect_workflow "$SESSION_ID")
    echo "Detected workflow: $WORKFLOW"
fi
```

**Workflow determines handoff**:
- **development**: Hand off to session.plan (full workflow)
- **advisory**: Hand off to session.wrap (minimal - just documentation)
- **experiment**: Hand off to session.execute (skip planning)
- **smart**: Detect based on session activity, hand off accordingly

For **advisory** workflow, skip directly to wrap:
```
✅ Advisory session initialized

This is a guidance-only session. No code changes expected.

Ready for documentation → /session.wrap
```

For **experiment** workflow, skip to execute:
```
✅ Experiment session initialized

This is an exploratory session for investigation/prototyping.

Ready for execution → /session.execute
```

### 5. Load Project Context

Quick orientation:
- Read `.session/project-context/constitution-summary.md` for quality standards
- Read `.session/project-context/technical-context.md` for stack and patterns

### 5. Get Bearings (MANDATORY)

```bash
git status --porcelain && git branch --show-current
git log --oneline -5
```

- Check for uncommitted changes from previous work
- Note current branch and recent commits
- Review `tasks.md` for current progress

### 6. Create Feature Branch (MANDATORY for code changes)

⚠️ **CRITICAL: NEVER work directly on main branch for code changes.**

**If current branch is `main` AND session involves code changes:**

```bash
# For GitHub issues (bugs, fixes, improvements)
git checkout -b fix/issue-{number}-short-description

# For Speckit features
git checkout -b feat/{feature-id}-short-description

# Example:
# git checkout -b fix/issue-637-regenerate-button
# git checkout -b feat/001-wizard-redesign
```

**Branch naming conventions:**
- `fix/` - Bug fixes, issue resolutions
- `feat/` - New features, enhancements
- `docs/` - Documentation-only changes
- `refactor/` - Code refactoring
- `test/` - Test additions/fixes

**Exceptions (can work on main):**
- Documentation-only changes (use `[skip ci]` in commit message)
- Session wrap commits (documentation updates)
- Emergency hotfixes (with explicit user approval)

**Workflow:**
1. Create branch BEFORE any code changes
2. Make changes and commits on branch
3. Push branch to remote: `git push -u origin <branch-name>`
4. Create PR for review
5. Wait for CI to pass
6. Merge PR (do NOT push directly to main)

**If already on correct feature branch:**
- Verify with `git branch --show-current`
- Proceed to next step

### 7. Review Previous Session

If `previous_session` is not null:
- Read the `for_next_session` summary
- Note any `incomplete_tasks` to continue
- Optionally read full notes at `notes_file`

### 8. Verify Before New Work (MANDATORY for continuation sessions)

If continuing work with completed tasks from previous sessions:

```bash
# Run the project's test suite
# Check .session/project-context/technical-context.md for project-specific commands
# Common patterns:
#   make test          # If Makefile exists
#   npm test           # Node.js projects
#   pytest             # Python projects
#   go test ./...      # Go projects
```

- If any tests fail, **fix regressions BEFORE new work**
- Verify previous session's changes work as expected
- This prevents regression accumulation across sessions


### 9. Report Initialization Complete

Display session summary:

```
✅ Session initialized successfully

Session ID: {session.id}
Type: {speckit|github_issue|unstructured}
Branch: {current-branch}
Previous session: {session-id or "none"}

Context loaded:
- Constitution: {summary-path}
- Technical: {context-path}
- Session notes: {notes-path}
- Tasks file: {tasks-path or spec-path}

Ready for next step → (see workflow routing above)
```

The CLI will automatically present the handoff to session.plan based on the frontmatter.

**Handoff Reasoning**: session.start only initializes session infrastructure and loads context. Next agent depends on workflow type (plan for development, execute for experiment, wrap for advisory), which can reference existing Speckit tasks or generate new ones based on session type.

## Notes

- **Single responsibility**: Initialize session infrastructure only
- **No task generation**: That's session.plan's job
- **No task execution**: That's session.execute's job
- **Handoff**: Automatically suggests session.plan with send: true
- **Independently callable**: Can resume/verify session without full workflow
