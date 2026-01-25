#!/usr/bin/env bash
# session-common.sh - Shared functions for session workflow
# Part of Session Workflow Enhancement (#566)

set -euo pipefail

# Constants
SESSION_ROOT=".session"
SESSIONS_DIR="${SESSION_ROOT}/sessions"
ACTIVE_SESSION_FILE="${SESSION_ROOT}/ACTIVE_SESSION"
PROJECT_CONTEXT_DIR="${SESSION_ROOT}/project-context"
TEMPLATES_DIR="${SESSION_ROOT}/templates"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Directory & Structure Functions
# ============================================================================

ensure_session_structure() {
    # Create session directory structure if it doesn't exist
    mkdir -p "${SESSIONS_DIR}"
    mkdir -p "${PROJECT_CONTEXT_DIR}"
    mkdir -p "${TEMPLATES_DIR}"
    mkdir -p "${SESSION_ROOT}/scripts/bash"
}

# ============================================================================
# Prerequisite Checks
# ============================================================================

check_prerequisites() {
    local errors=0
    
    # Check git
    if ! command -v git &> /dev/null; then
        echo -e "${RED}ERROR: git is not installed${NC}" >&2
        ((errors++))
    fi
    
    # Check if in git repo
    if ! git rev-parse --git-dir &> /dev/null; then
        echo -e "${RED}ERROR: Not in a git repository${NC}" >&2
        ((errors++))
    fi
    
    # Check jq for JSON output
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}WARNING: jq not installed - JSON output may be malformed${NC}" >&2
    fi
    
    return $errors
}

# ============================================================================
# PR Helper Functions (#665)
# ============================================================================

detect_existing_pr() {
    # Check if PR exists for current branch
    # Returns: PR number or empty string
    gh pr view --json number -q .number 2>/dev/null || echo ""
}

get_pr_status() {
    # Get PR status details
    # Args: $1 = PR number
    # Returns: JSON with state, draft status, merged status
    local pr_number="$1"
    gh pr view "$pr_number" --json state,isDraft,merged 2>/dev/null || echo "{}"
}

check_pr_merged() {
    # Check if PR is merged
    # Args: $1 = PR number
    # Returns: 0 if merged, 1 if not
    local pr_number="$1"
    local merged=$(gh pr view "$pr_number" --json merged -q .merged 2>/dev/null || echo "false")
    
    if [ "$merged" = "true" ]; then
        return 0
    else
        return 1
    fi
}

generate_pr_title_from_commits() {
    # Generate PR title from recent commits
    # Returns: Suggested PR title
    local first_commit=$(git log origin/main..HEAD --oneline --reverse | head -1)
    echo "$first_commit" | cut -d' ' -f2-
}

get_commits_for_pr() {
    # Get list of commits for PR description
    # Returns: Formatted commit list
    git log origin/main..HEAD --oneline --reverse
}

# ============================================================================
# Validation Functions (#665)
# ============================================================================

run_quality_checks() {
    # Run lint and format checks
    # Returns: 0 if passed, 1 if failed
    # Tries common patterns based on project structure
    local errors=0
    
    # Try Makefile first (most reliable)
    if [ -f "Makefile" ] && grep -q "lint:" Makefile 2>/dev/null; then
        make lint >/dev/null 2>&1 || ((errors++))
    # Node.js project
    elif [ -f "package.json" ]; then
        npm run lint >/dev/null 2>&1 || ((errors++))
    # Python project
    elif [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
        if command -v pylint &>/dev/null; then
            pylint . >/dev/null 2>&1 || ((errors++))
        fi
    fi
    
    return $errors
}

run_all_tests() {
    # Run all test suites
    # Returns: 0 if all passed, 1 if any failed
    # Tries common patterns based on project structure
    local errors=0
    
    # Try Makefile first (most reliable)
    if [ -f "Makefile" ] && grep -q "test" Makefile 2>/dev/null; then
        make test >/dev/null 2>&1 || ((errors++))
    # Node.js project
    elif [ -f "package.json" ]; then
        npm test >/dev/null 2>&1 || ((errors++))
    # Python project
    elif [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
        if command -v pytest &>/dev/null; then
            pytest >/dev/null 2>&1 || ((errors++))
        fi
    # Go project
    elif [ -f "go.mod" ]; then
        go test ./... >/dev/null 2>&1 || ((errors++))
    fi
    
    return $errors
}

check_git_state() {
    # Check git working tree is clean and pushed
    # Returns: 0 if clean, 1 if dirty or unpushed
    local errors=0
    
    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        ((errors++))
    fi
    
    # Check for unpushed commits
    local unpushed=$(git log @{u}.. --oneline 2>/dev/null | wc -l)
    if [ "$unpushed" -gt 0 ]; then
        ((errors++))
    fi
    
    return $errors
}

# ============================================================================
# Issue & Task Management Functions (#665)
# ============================================================================

close_issue_with_comment() {
    # Close issue and post comment
    # Args: $1 = issue number, $2 = comment
    local issue_number="$1"
    local comment="$2"
    
    gh issue close "$issue_number" --comment "$comment" 2>/dev/null
}

update_parent_issue_progress() {
    # Update Speckit parent issue with phase progress
    # Args: $1 = parent issue number, $2 = progress text
    local parent_issue="$1"
    local progress="$2"
    
    gh issue comment "$parent_issue" --body "**Progress Update**: $progress" 2>/dev/null
}

mark_tasks_complete() {
    # Mark tasks [x] in tasks.md file
    # Args: $1 = task file path, $2... = task IDs to mark complete
    local task_file="$1"
    shift
    
    for task_id in "$@"; do
        sed -i "s/^- \[ \] $task_id/- [x] $task_id/" "$task_file"
    done
}

get_task_completion() {
    # Get task completion stats
    # Args: $1 = task file path
    # Returns: JSON with total, completed, incomplete counts
    local task_file="$1"
    
    if [ ! -f "$task_file" ]; then
        echo '{"total": 0, "completed": 0, "incomplete": 0}'
        return
    fi
    
    local total=$(grep -c "^- \[.\] T" "$task_file" || echo "0")
    local completed=$(grep -c "^- \[x\] T" "$task_file" || echo "0")
    local incomplete=$((total - completed))
    
    echo "{\"total\": $total, \"completed\": $completed, \"incomplete\": $incomplete}"
}

check_git_clean() {
    # Returns 0 if clean, 1 if dirty
    if git diff --quiet && git diff --cached --quiet; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# Session ID Functions
# ============================================================================

generate_session_id() {
    # Generate session ID in format YYYY-MM-DD-N
    # Stored in .session/sessions/YYYY-MM/YYYY-MM-DD-N
    # Ensures no collision with existing sessions (active or completed)
    local today
    today=$(date +%Y-%m-%d)
    local year_month
    year_month=$(date +%Y-%m)
    
    # Create year-month directory if it doesn't exist
    mkdir -p "${SESSIONS_DIR}/${year_month}"
    
    # Find the highest session number for today
    local max_num=0
    if [[ -d "${SESSIONS_DIR}/${year_month}" ]]; then
        for dir in "${SESSIONS_DIR}/${year_month}/${today}-"*; do
            if [[ -d "$dir" ]]; then
                local num
                num=$(basename "$dir" | sed "s/${today}-//")
                if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -gt "$max_num" ]]; then
                    max_num="$num"
                fi
            fi
        done
    fi
    
    # Next session number (1-indexed, always increment from max)
    local next=$((max_num + 1))
    
    echo "${today}-${next}"
}

get_session_dir() {
    # Get full path to session directory for a given session ID
    # Args: session_id (YYYY-MM-DD-N format)
    # Returns: .session/sessions/YYYY-MM/YYYY-MM-DD-N
    local session_id="$1"
    
    # Extract year-month from session ID (YYYY-MM from YYYY-MM-DD-N)
    local year_month
    year_month=$(echo "$session_id" | cut -d'-' -f1,2)
    
    echo "${SESSIONS_DIR}/${year_month}/${session_id}"
}

get_active_session() {
    # Returns active session ID if exists, empty string otherwise
    if [[ -f "${ACTIVE_SESSION_FILE}" ]]; then
        cat "${ACTIVE_SESSION_FILE}"
    else
        echo ""
    fi
}

set_active_session() {
    local session_id="$1"
    echo "$session_id" > "${ACTIVE_SESSION_FILE}"
}

clear_active_session() {
    rm -f "${ACTIVE_SESSION_FILE}"
}

# ============================================================================
# Previous Session Functions
# ============================================================================

get_previous_session() {
    # Find the most recent completed session
    # Returns session ID or empty string
    local active
    active=$(get_active_session)
    
    # Get all session directories sorted by name (which is date-based)
    # Search in YYYY-MM subdirectories
    local sessions
    sessions=$(find "${SESSIONS_DIR}" -mindepth 2 -maxdepth 2 -type d -name "????-??-??-*" 2>/dev/null | sort -r)
    
    for session_dir in $sessions; do
        local session_id
        session_id=$(basename "$session_dir")
        
        # Skip active session
        if [[ "$session_id" == "$active" ]]; then
            continue
        fi
        
        # Check if session has state.json with completed status
        local state_file="${session_dir}/state.json"
        if [[ -f "$state_file" ]]; then
            local status
            status=$(jq -r '.status // "unknown"' "$state_file" 2>/dev/null || echo "unknown")
            if [[ "$status" == "completed" ]]; then
                echo "$session_id"
                return 0
            fi
        fi
    done
    
    echo ""
}

# ============================================================================
# Session Context Functions
# ============================================================================

get_session_context_json() {
    # Output complete session context as JSON
    # Used by agents to load context without inline bash
    # Returns: JSON object with session info, paths, and state
    
    local session_id
    session_id=$(get_active_session)
    
    if [[ -z "$session_id" ]]; then
        echo '{"status": "error", "message": "No active session found"}'
        return 1
    fi
    
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    
    if [[ ! -d "$session_dir" ]]; then
        echo '{"status": "error", "message": "Session directory not found"}'
        return 1
    fi
    
    local info_file="${session_dir}/session-info.json"
    if [[ ! -f "$info_file" ]]; then
        echo '{"status": "error", "message": "Session info file not found"}'
        return 1
    fi
    
    # Read session info
    local session_type workflow
    session_type=$(jq -r '.type // "unknown"' "$info_file" 2>/dev/null)
    workflow=$(jq -r '.workflow // "development"' "$info_file" 2>/dev/null)
    
    # Get tasks file path
    local tasks_file
    tasks_file=$(resolve_tasks_file "$session_id")
    
    # Get task counts if tasks file exists
    local task_total=0 task_completed=0
    if [[ -n "$tasks_file" && -f "$tasks_file" ]]; then
        local counts
        counts=$(count_tasks "$tasks_file")
        task_total=$(echo "$counts" | cut -d: -f1)
        task_completed=$(echo "$counts" | cut -d: -f2)
    fi
    
    # Get workflow state
    local current_step="none" step_status="none"
    if [[ -f "${session_dir}/state.json" ]]; then
        current_step=$(jq -r '.current_step // "none"' "${session_dir}/state.json" 2>/dev/null)
        step_status=$(jq -r '.step_status // "none"' "${session_dir}/state.json" 2>/dev/null)
    fi
    
    # Build JSON output
    jq -n \
        --arg status "ok" \
        --arg session_id "$session_id" \
        --arg session_dir "$session_dir" \
        --arg session_type "$session_type" \
        --arg workflow "$workflow" \
        --arg tasks_file "$tasks_file" \
        --argjson task_total "$task_total" \
        --argjson task_completed "$task_completed" \
        --arg current_step "$current_step" \
        --arg step_status "$step_status" \
        '{
            status: $status,
            session: {
                id: $session_id,
                dir: $session_dir,
                type: $session_type,
                workflow: $workflow
            },
            tasks: {
                file: $tasks_file,
                total: $task_total,
                completed: $task_completed
            },
            workflow_state: {
                current_step: $current_step,
                step_status: $step_status
            }
        }'
}

load_session_state() {
    # Load state.json for a session
    local session_id="$1"
    local state_file="${SESSIONS_DIR}/${session_id}/state.json"
    
    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        echo "{}"
    fi
}

load_session_notes_summary() {
    # Extract first 500 chars of notes.md
    local session_id="$1"
    local notes_file="${SESSIONS_DIR}/${session_id}/notes.md"
    
    if [[ -f "$notes_file" ]]; then
        head -c 500 "$notes_file"
    else
        echo ""
    fi
}

get_for_next_session_section() {
    # Extract "For Next Session" section from notes
    local session_id="$1"
    local notes_file="${SESSIONS_DIR}/${session_id}/notes.md"
    
    if [[ -f "$notes_file" ]]; then
        # Extract content from "## For Next Session" until next "##" or end
        awk '/^## For Next Session/,/^## [^F]|^$/' "$notes_file" | head -20
    else
        echo ""
    fi
}

# ============================================================================
# Task Functions
# ============================================================================

resolve_tasks_file() {
    # Resolve the correct tasks.md path based on session type
    # Args: session_id
    # Returns: path to tasks.md (or empty string if not found)
    #
    # For speckit sessions: checks spec_dir and specs/spec_dir
    # For other sessions: uses session directory tasks.md
    
    local session_id="$1"
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    local info_file="${session_dir}/session-info.json"
    
    if [[ ! -f "$info_file" ]]; then
        echo ""
        return 1
    fi
    
    local session_type
    session_type=$(jq -r '.type // "unknown"' "$info_file" 2>/dev/null)
    
    case "$session_type" in
        speckit)
            local spec_dir
            spec_dir=$(jq -r '.spec_dir // empty' "$info_file" 2>/dev/null)
            
            if [[ -z "$spec_dir" ]]; then
                echo ""
                return 1
            fi
            
            # Check direct path first, then specs/ prefix
            if [[ -f "${spec_dir}/tasks.md" ]]; then
                echo "${spec_dir}/tasks.md"
            elif [[ -f "specs/${spec_dir}/tasks.md" ]]; then
                echo "specs/${spec_dir}/tasks.md"
            elif [[ -d "$spec_dir" ]]; then
                echo "${spec_dir}/tasks.md"
            elif [[ -d "specs/${spec_dir}" ]]; then
                echo "specs/${spec_dir}/tasks.md"
            else
                echo ""
                return 1
            fi
            ;;
        github_issue|unstructured|*)
            echo "${session_dir}/tasks.md"
            ;;
    esac
}

count_tasks() {
    # Count total and completed tasks in a tasks.md file
    # Only counts checkboxes under the "## Tasks" section, not Acceptance Criteria
    local tasks_file="$1"
    
    if [[ ! -f "$tasks_file" ]]; then
        echo "0:0"
        return
    fi
    
    # Extract only the content after "## Tasks" heading
    local tasks_section
    tasks_section=$(awk '/^## Tasks/,0' "$tasks_file" 2>/dev/null || true)
    
    if [[ -z "$tasks_section" ]]; then
        echo "0:0"
        return
    fi
    
    local total completed
    total=$(echo "$tasks_section" | grep -c '^\s*- \[' 2>/dev/null || true)
    completed=$(echo "$tasks_section" | grep -c '^\s*- \[x\]' 2>/dev/null || true)
    
    # Ensure we have numbers (grep -c returns nothing on no match sometimes)
    total=${total:-0}
    completed=${completed:-0}
    
    echo "${total}:${completed}"
}

get_incomplete_tasks() {
    # Get list of incomplete tasks (only from ## Tasks section)
    local tasks_file="$1"
    
    if [[ -f "$tasks_file" ]]; then
        awk '/^## Tasks/,0' "$tasks_file" 2>/dev/null | grep '^\s*- \[ \]' 2>/dev/null || true
    fi
}

# ============================================================================
# JSON Output Functions
# ============================================================================

json_escape() {
    # Escape string for JSON
    local str="$1"
    str="${str//\\/\\\\}"  # Backslash
    str="${str//\"/\\\"}"  # Double quote
    str="${str//$'\n'/\\n}" # Newline
    str="${str//$'\r'/\\r}" # Carriage return
    str="${str//$'\t'/\\t}" # Tab
    echo "$str"
}

# ============================================================================
# Output Functions
# ============================================================================

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# ============================================================================
# Validation Functions (for session.validate agent)
# ============================================================================

check_test_status() {
    # Check if tests pass
    # Returns: "pass" | "fail" | "unknown"
    # Note: This is a quick check, not running full test suite
    
    # Check for recent test failures in git log
    if git log -1 --grep="test.*fail" --oneline >/dev/null 2>&1; then
        echo "warning"
        return
    fi
    
    # Check if test files exist
    if [[ -d "backend/tests" ]] || [[ -d "frontend/src/__tests__" ]]; then
        echo "unknown"
    else
        echo "pass"
    fi
}

check_lint_status() {
    # Quick check for obvious lint issues
    # Returns: "pass" | "fail" | "unknown"
    
    # Check for Python syntax errors
    if [[ -d "backend/app" ]]; then
        if ! find backend/app -name "*.py" -exec python3 -m py_compile {} \; 2>/dev/null; then
            echo "fail"
            return
        fi
    fi
    
    # Check for TypeScript syntax errors (basic)
    if [[ -d "frontend/src" ]]; then
        # Just check files exist and are readable
        if find frontend/src -name "*.tsx" -o -name "*.ts" 2>/dev/null | grep -q .; then
            echo "unknown"
        else
            echo "pass"
        fi
    else
        echo "pass"
    fi
}

get_validation_fixes() {
    # Generate list of suggested fixes based on validation failures
    # Args: space-separated list of failed checks
    local failures=("$@")
    local fixes=()
    
    for failure in "${failures[@]}"; do
        case "$failure" in
            "git_status")
                fixes+=('{"fix": "commit_changes", "command": "git add -A && git commit -m \"chore: commit pending changes\"", "description": "Commit uncommitted changes"}')
                ;;
            "tests")
                fixes+=('{"fix": "run_tests", "command": "Check technical-context.md for test command", "description": "Run tests"}')
                ;;
            "lint")
                fixes+=('{"fix": "run_lint", "command": "Check technical-context.md for lint command", "description": "Run linter"}')
                ;;
            "tasks")
                fixes+=('{"fix": "review_tasks", "command": "cat tasks.md", "description": "Review incomplete tasks"}')
                ;;
        esac
    done
    
    # Output as JSON array
    if [[ "${#fixes[@]}" -gt 0 ]]; then
        echo "["
        local first=true
        for fix in "${fixes[@]}"; do
            if [[ "$first" == true ]]; then
                first=false
            else
                echo ","
            fi
            echo -n "    ${fix}"
        done
        echo ""
        echo "  ]"
    else
        echo "[]"
    fi
}

# ============================================================================
# Workflow Detection (#676) - SIMPLIFIED v2.1
# ============================================================================

detect_workflow() {
    # Get workflow from session-info.json (no auto-detection)
    # Args: session_id
    # Returns: development|spike
    
    local session_id="$1"
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    local info_file="${session_dir}/session-info.json"
    
    # Read workflow from session-info.json (defaults to "development")
    local workflow
    workflow=$(jq -r '.workflow // "development"' "$info_file" 2>/dev/null || echo "development")
    
    echo "$workflow"
}

check_branch_for_workflow() {
    # Warn if on main/master during development workflow
    # Args: session_id
    # Returns: 0 always (warning only), outputs warning to stderr if needed
    
    local session_id="$1"
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    
    local workflow
    workflow=$(detect_workflow "$session_id")
    
    # Only warn for development workflow on main branches
    if [[ "$workflow" == "development" && ("$current_branch" == "main" || "$current_branch" == "master") ]]; then
        echo -e "${YELLOW}⚠ WARNING: On '$current_branch' branch during development workflow${NC}" >&2
        echo -e "${YELLOW}  Consider creating a feature branch before making changes${NC}" >&2
        echo -e "${YELLOW}  Suggested: git checkout -b feature/<description>${NC}" >&2
        return 0
    fi
    
    # Spike workflow on main is acceptable
    return 0
}

check_workflow_allowed() {
    # Check if current workflow allows this agent
    # Args: session_id, allowed_workflows...
    # Returns: 0 if allowed, 1 if blocked
    
    local session_id="$1"
    shift
    local allowed_workflows=("$@")
    
    local current_workflow
    current_workflow=$(detect_workflow "$session_id")
    
    # Check if current workflow is in allowed list
    for allowed in "${allowed_workflows[@]}"; do
        if [[ "$current_workflow" == "$allowed" ]]; then
            return 0
        fi
    done
    
    # Not allowed
    echo -e "${RED}ERROR: This agent is not applicable for '${current_workflow}' workflow${NC}" >&2
    echo -e "${YELLOW}This agent is for: ${allowed_workflows[*]}${NC}" >&2
    return 1
}

# ============================================================================
# Workflow State Tracking (Session Continuity)
# ============================================================================

# Valid workflow transitions
# Note: session.start creates the session but does not track step state.
# The first tracked step is typically "plan".
declare -A WORKFLOW_TRANSITIONS=(
    ["none"]="plan"
    ["start"]="plan execute"
    ["plan"]="task execute"
    ["task"]="execute"
    ["execute"]="validate execute"
    ["validate"]="publish execute"
    ["publish"]="finalize"
    ["finalize"]="wrap"
    ["wrap"]=""
)

set_workflow_step() {
    # Track workflow step state for session continuity
    # Args: session_id, step_name, status (in_progress|completed|failed)
    # 
    # This enables detection of interrupted sessions across CLI restarts.
    # If a step is "in_progress" when a new CLI session starts, the 
    # previous session was interrupted.
    
    local session_id="$1"
    local step_name="$2"
    local status="$3"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local session_dir
    session_dir=$(get_session_dir "$session_id")
    local state_file="${session_dir}/state.json"

    if [[ ! -d "$session_dir" ]]; then
        echo -e "${RED}ERROR: Session directory not found: $session_dir${NC}" >&2
        return 1
    fi
    
    # Create or update state.json
    if [[ -f "$state_file" ]]; then
        # Update existing state
        local tmp_file=$(mktemp)
        jq --arg step "$step_name" \
           --arg status "$status" \
           --arg updated "$timestamp" \
           --arg started "$timestamp" \
           '. + {
               current_step: $step,
               step_status: $status,
               step_updated_at: $updated
           } | if .step_status == "in_progress" then . + {step_started_at: $started} else . end' \
           "$state_file" > "$tmp_file" && mv "$tmp_file" "$state_file"
    else
        # Create new state file
        cat > "$state_file" << STATEJSON
{
    "current_step": "$step_name",
    "step_status": "$status",
    "step_started_at": "$timestamp",
    "step_updated_at": "$timestamp"
}
STATEJSON
    fi
    
    echo -e "${GREEN}✓ Workflow step: $step_name ($status)${NC}"
}

get_workflow_step() {
    # Get current workflow step and status
    # Args: session_id
    # Returns: JSON with current_step and step_status
    
    local session_id="$1"
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    local state_file="${session_dir}/state.json"

    if [[ -f "$state_file" ]]; then
        jq '{current_step, step_status, step_started_at, step_updated_at}' "$state_file"
    else
        echo '{"current_step": "none", "step_status": "none"}'
    fi
}

check_interrupted_session() {
    # Check if the previous session was interrupted
    # Args: session_id
    # Returns: 0 if interrupted, 1 if not
    
    local session_id="$1"
    local state=$(get_workflow_step "$session_id")
    local status=$(echo "$state" | jq -r '.step_status // "none"')
    
    if [[ "$status" == "in_progress" ]]; then
        local step=$(echo "$state" | jq -r '.current_step')
        echo -e "${YELLOW}⚠️ INTERRUPTED SESSION DETECTED${NC}"
        echo -e "Previous session was interrupted during: ${BLUE}$step${NC}"
        echo ""
        return 0
    fi
    return 1
}

check_workflow_transition() {
    # Check if transitioning to a step is valid
    # Args: session_id, target_step
    # Returns: 0 if valid, 1 if invalid
    
    local session_id="$1"
    local target_step="$2"
    
    local state=$(get_workflow_step "$session_id")
    local current_step=$(echo "$state" | jq -r '.current_step // "none"')
    local current_status=$(echo "$state" | jq -r '.step_status // "none"')
    
    # If current step is in_progress, can't transition
    if [[ "$current_status" == "in_progress" ]]; then
        echo -e "${RED}ERROR: Cannot transition to '$target_step'${NC}"
        echo -e "Step '$current_step' is still in progress."
        echo ""
        echo "Either:"
        echo "  1. Complete the current step: /session.$current_step --resume"
        echo "  2. Force transition (data loss risk): --force flag"
        return 1
    fi
    
    # Check if transition is valid
    local valid_next="${WORKFLOW_TRANSITIONS[$current_step]:-}"
    
    if [[ -z "$valid_next" && "$current_step" != "none" ]]; then
        echo -e "${RED}ERROR: Session workflow complete - no more steps${NC}"
        return 1
    fi
    
    # Check if target is in valid next steps
    if [[ " $valid_next " =~ " $target_step " ]]; then
        return 0
    else
        echo -e "${RED}ERROR: Invalid workflow transition${NC}"
        echo "Current step: $current_step ($current_status)"
        echo "Requested: $target_step"
        echo "Valid next steps: $valid_next"
        return 1
    fi
}

check_uncommitted_changes() {
    # Check for uncommitted changes that might be lost
    # Returns: 0 if clean, 1 if dirty with details
    
    if git diff --quiet && git diff --cached --quiet; then
        return 0
    fi
    
    echo -e "${YELLOW}⚠️ UNCOMMITTED CHANGES DETECTED${NC}"
    echo ""
    git status --short
    echo ""
    echo "These changes are NOT in any commit/PR."
    echo "They may be lost if you proceed."
    return 1
}

format_workflow_guidance() {
    # Format user-friendly guidance for workflow issues
    # Args: current_step, target_step, status
    
    local current_step="$1"
    local target_step="$2"
    local status="$3"
    
    echo "═══════════════════════════════════════════════════════════"
    echo "  WORKFLOW STATE ISSUE"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "  Current:   $current_step ($status)"
    echo "  Requested: $target_step"
    echo ""
    echo "  Workflow sequence:"
    echo "  start → plan → task → execute → validate → publish → finalize → wrap"
    echo ""
    
    if [[ "$status" == "in_progress" ]]; then
        echo "  ⚠️ Previous session was interrupted during '$current_step'"
        echo ""
        echo "  RECOMMENDED ACTION:"
        echo "  Run: /session.$current_step --resume"
        echo ""
    else
        echo "  ❌ Cannot skip to '$target_step' from '$current_step'"
        echo ""
        echo "  REQUIRED ACTION:"
        local valid_next="${WORKFLOW_TRANSITIONS[$current_step]:-}"
        local next_step=$(echo "$valid_next" | cut -d' ' -f1)
        echo "  Run: /session.$next_step"
        echo ""
    fi
    
    echo "  Use --force to override (may cause data loss)"
    echo "═══════════════════════════════════════════════════════════"
}
