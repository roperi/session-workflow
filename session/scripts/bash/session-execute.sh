#!/usr/bin/env bash
# session-execute.sh - Prepare for session execution
# Part of Session Workflow Refactor

set -euo pipefail

# Get script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/session-common.sh"

# ============================================================================
# Defaults
# ============================================================================

JSON_OUTPUT=false

# ============================================================================
# Argument Parsing
# ============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --json) 
                JSON_OUTPUT=true
                shift
                ;; 
            -h|--help) 
                echo "Usage: session-execute.sh [--json]"
                exit 0
                ;; 
            *) 
                echo "Unknown option: $1" >&2
                exit 1
                ;; 
        esac
    done
}

# ============================================================================
# Main Logic
# ============================================================================

main() {
    parse_args "$@"
    
    # 1. Load Session Context
    local session_id
    session_id=$(get_active_session)
    
    if [[ -z "$session_id" ]]; then
        if $JSON_OUTPUT; then
            echo '{"status": "error", "message": "No active session found"}'
        else
            print_error "No active session found. Run /session.start first."
        fi
        exit 1
    fi
    
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    local info_file="${session_dir}/session-info.json"
    
    # 2. Check Workflow Compatibility
    if ! check_workflow_allowed "$session_id" "development" "experiment" "spike" 2>/dev/null; then
         if $JSON_OUTPUT; then
            echo '{"status": "error", "message": "Workflow not allowed for execute agent"}'
         else
            print_error "Workflow not allowed for execute agent"
         fi
         exit 1
    fi

    # Update workflow state
    set_workflow_step "$session_id" "execute" "in_progress" >/dev/null

    local session_type
    session_type=$(jq -r '.type // "unknown"' "$info_file")
    
    # 3. Load Tasks
    local tasks_file=""
    if [[ "$session_type" == "speckit" ]]; then
        local spec_dir
        spec_dir=$(jq -r '.spec_dir // empty' "$info_file")
        # Handle relative path
        if [[ -d "$spec_dir" ]]; then
             tasks_file="${spec_dir}/tasks.md"
        elif [[ -d "specs/$spec_dir" ]]; then
             tasks_file="specs/${spec_dir}/tasks.md"
        fi
    else
        tasks_file="${session_dir}/tasks.md"
    fi
    
    local task_stats="{}