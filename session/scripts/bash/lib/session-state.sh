#!/usr/bin/env bash
# lib/session-state.sh - Schema validation, session context loading, workflow
# detection, and workflow FSM (state transitions).
#
# Requires: session-output.sh (colors), session-paths.sh (get_session_dir,
#   get_active_session), session-tasks.sh (resolve_tasks_file, count_tasks)

# ============================================================================
# Schema Validation
# ============================================================================

validate_schema_version() {
    # Warn if the schema_version in a JSON file does not match the expected value.
    # Args: json_file expected_version
    # Returns 0 always (warning only — never blocks execution).
    local json_file="$1"
    local expected="$2"
    [[ -f "$json_file" ]] || return 0
    local actual
    actual=$(jq -r '.schema_version // "missing"' "$json_file" 2>/dev/null || echo "unreadable")
    if [[ "$actual" != "$expected" ]]; then
        echo -e "${YELLOW}[WARN]${NC} Schema version mismatch in ${json_file}: expected ${expected}, got ${actual}. Run migration or update scripts." >&2
    fi
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

load_session_notes_summary() {
    # Extract first 500 chars of notes.md
    local session_id="$1"
    local notes_file
    notes_file="$(get_session_dir "$session_id")/notes.md"
    
    if [[ -f "$notes_file" ]]; then
        head -c 500 "$notes_file"
    else
        echo ""
    fi
}

get_for_next_session_section() {
    # Extract "For Next Session" section from notes
    # Includes blank lines; stops only at next markdown H2 heading or EOF.
    local session_id="$1"
    local notes_file
    notes_file="$(get_session_dir "$session_id")/notes.md"

    if [[ -f "$notes_file" ]]; then
        awk '
            /^## For Next Session[[:space:]]*$/ {found=1; print; next}
            found && $0 ~ /^## / {exit}
            found {print}
        ' "$notes_file" | head -20
    else
        echo ""
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
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

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
        local tmp_file
        tmp_file=$(mktemp)
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
    local state
    state=$(get_workflow_step "$session_id")
    local status
    status=$(echo "$state" | jq -r '.step_status // "none"')
    
    if [[ "$status" == "in_progress" ]]; then
        local step
        step=$(echo "$state" | jq -r '.current_step')
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
    
    local state
    state=$(get_workflow_step "$session_id")
    local current_step
    current_step=$(echo "$state" | jq -r '.current_step // "none"')
    local current_status
    current_status=$(echo "$state" | jq -r '.step_status // "none"')
    
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
        local next_step
        next_step=$(echo "$valid_next" | cut -d' ' -f1)
        echo "  Run: /session.$next_step"
        echo ""
    fi
    
    echo "  Use --force to override (may cause data loss)"
    echo "═══════════════════════════════════════════════════════════"
}
