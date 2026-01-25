#!/usr/bin/env bash
# session-preflight.sh - Pre-flight checks for all session agents
# Validates workflow state, checks for interrupts, outputs context JSON

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/session-common.sh"

# ============================================================================
# Defaults
# ============================================================================

STEP_NAME=""
JSON_OUTPUT=false
FORCE_MODE=false

# ============================================================================
# Usage
# ============================================================================

usage() {
    cat << EOF
Usage: session-preflight.sh --step <step_name> [OPTIONS]

Pre-flight validation for session agents. Run before any agent work.

OPTIONS:
    --step NAME     Required. The workflow step about to run (plan, execute, validate, etc.)
    --json          Output JSON for AI consumption
    --force         Skip workflow validation (use with caution)
    -h, --help      Show this help

WHAT IT DOES:
    1. Validates an active session exists
    2. Checks for interrupted sessions (step still in_progress)
    3. Validates workflow transition is allowed
    4. Marks step as in_progress
    5. Outputs session context JSON

EXAMPLES:
    session-preflight.sh --step plan --json
    session-preflight.sh --step execute --json
    session-preflight.sh --step validate --json --force
EOF
}

# ============================================================================
# Argument Parsing
# ============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --step)
                STEP_NAME="$2"
                shift 2
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --force)
                FORCE_MODE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$STEP_NAME" ]]; then
        echo "ERROR: --step is required" >&2
        usage
        exit 1
    fi
}

# ============================================================================
# Output Functions
# ============================================================================

output_error() {
    local message="$1"
    local hint="${2:-}"
    
    if $JSON_OUTPUT; then
        jq -n \
            --arg status "error" \
            --arg message "$message" \
            --arg hint "$hint" \
            '{status: $status, message: $message, hint: $hint}'
    else
        print_error "$message"
        if [[ -n "$hint" ]]; then
            echo "Hint: $hint"
        fi
    fi
}

output_warning() {
    local message="$1"
    local current_step="$2"
    local step_status="$3"
    
    if $JSON_OUTPUT; then
        jq -n \
            --arg status "warning" \
            --arg message "$message" \
            --arg interrupted_step "$current_step" \
            --arg interrupted_status "$step_status" \
            '{
                status: $status,
                message: $message,
                interrupted: {
                    step: $interrupted_step,
                    status: $interrupted_status
                }
            }'
    else
        print_warning "$message"
        echo "Interrupted step: $current_step ($step_status)"
    fi
}

# ============================================================================
# Main Logic
# ============================================================================

main() {
    parse_args "$@"
    
    # 1. Check for active session
    local session_id
    session_id=$(get_active_session)
    
    if [[ -z "$session_id" ]]; then
        output_error "No active session found" "Run /session.start first"
        exit 1
    fi
    
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    
    if [[ ! -d "$session_dir" ]]; then
        output_error "Session directory not found: $session_dir" "Clear .session/ACTIVE_SESSION and restart"
        exit 1
    fi
    
    # 2. Check for interrupted session
    local state_file="${session_dir}/state.json"
    local current_step="none"
    local step_status="none"
    
    if [[ -f "$state_file" ]]; then
        current_step=$(jq -r '.current_step // "none"' "$state_file" 2>/dev/null)
        step_status=$(jq -r '.step_status // "none"' "$state_file" 2>/dev/null)
        
        if [[ "$step_status" == "in_progress" && "$current_step" != "$STEP_NAME" ]]; then
            if ! $FORCE_MODE; then
                output_warning "Session was interrupted during '$current_step'" "$current_step" "$step_status"
                if ! $JSON_OUTPUT; then
                    echo ""
                    echo "Options:"
                    echo "  1. Resume: /session.$current_step --resume"
                    echo "  2. Force: Add --force flag to skip this check"
                fi
                exit 2
            fi
        fi
    fi
    
    # 3. Validate workflow transition (unless forced)
    if ! $FORCE_MODE; then
        if ! check_workflow_transition "$session_id" "$STEP_NAME" 2>/dev/null; then
            local valid_next="${WORKFLOW_TRANSITIONS[$current_step]:-}"
            output_error "Invalid workflow transition from '$current_step' to '$STEP_NAME'" "Valid next steps: $valid_next"
            exit 1
        fi
    fi
    
    # 4. Mark step as in_progress
    set_workflow_step "$session_id" "$STEP_NAME" "in_progress" >/dev/null
    
    # 5. Output session context
    if $JSON_OUTPUT; then
        # Enhanced context output
        local info_file="${session_dir}/session-info.json"
        local session_type workflow stage
        session_type=$(jq -r '.type // "unknown"' "$info_file" 2>/dev/null)
        workflow=$(jq -r '.workflow // "development"' "$info_file" 2>/dev/null)
        stage=$(jq -r '.stage // "production"' "$info_file" 2>/dev/null)

        local repo_root
        repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
        
        local tasks_file
        tasks_file=$(resolve_tasks_file "$session_id")
        
        local task_total=0 task_completed=0
        if [[ -n "$tasks_file" && -f "$tasks_file" ]]; then
            local counts
            counts=$(count_tasks "$tasks_file")
            task_total=$(echo "$counts" | cut -d: -f1)
            task_completed=$(echo "$counts" | cut -d: -f2)
        fi
        
        jq -n \
            --arg status "ok" \
            --arg step "$STEP_NAME" \
            --arg session_id "$session_id" \
            --arg session_dir "$session_dir" \
            --arg session_type "$session_type" \
            --arg workflow "$workflow" \
            --arg stage "$stage" \
            --arg repo_root "$repo_root" \
            --arg tasks_file "$tasks_file" \
            --argjson task_total "$task_total" \
            --argjson task_completed "$task_completed" \
            --arg previous_step "$current_step" \
            --arg previous_status "$step_status" \
            '{
                status: $status,
                step: $step,
                session: {
                    id: $session_id,
                    dir: $session_dir,
                    type: $session_type,
                    workflow: $workflow,
                    stage: $stage
                },
                repo_root: $repo_root,
                tasks: {
                    file: $tasks_file,
                    total: $task_total,
                    completed: $task_completed
                },
                previous_state: {
                    step: $previous_step,
                    status: $previous_status
                }
            }'
    else
        print_success "Preflight checks passed for '$STEP_NAME'"
        echo "Session: $session_id"
        echo "Type: $(jq -r '.type' "${session_dir}/session-info.json" 2>/dev/null)"
        echo "Workflow: $(jq -r '.workflow' "${session_dir}/session-info.json" 2>/dev/null)"
    fi
}

main "$@"
