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
        if [[ -n "$spec_dir" ]]; then
            if [[ -d "$spec_dir" ]]; then
                tasks_file="${spec_dir}/tasks.md"
            elif [[ -d "specs/$spec_dir" ]]; then
                tasks_file="specs/${spec_dir}/tasks.md"
            fi
        fi
    else
        tasks_file="${session_dir}/tasks.md"
    fi
    
    local task_stats="{}"
    if [[ -n "$tasks_file" && -f "$tasks_file" ]]; then
        local counts
        counts=$(count_tasks "$tasks_file")
        local total completed
        total=$(echo "$counts" | cut -d: -f1)
        completed=$(echo "$counts" | cut -d: -f2)
        task_stats=$(jq -n --argjson total "$total" --argjson completed "$completed" '{total: $total, completed: $completed}')
    fi

    # 4. Output JSON
    if $JSON_OUTPUT; then
        local workflow
        workflow=$(jq -r '.workflow // "development"' "$info_file")
        
        jq -n \
            --arg status "ok" \
            --arg id "$session_id" \
            --arg dir "$session_dir" \
            --arg type "$session_type" \
            --arg workflow "$workflow" \
            --arg tasks_file "$tasks_file" \
            --argjson task_stats "$task_stats" \
            '{
                status: $status,
                session: {
                    id: $id,
                    dir: $dir,
                    type: $type,
                    workflow: $workflow
                },
                tasks: {
                    file: $tasks_file,
                    stats: $task_stats
                }
            }'
    else
        print_info "Session Execution Ready"
        echo "Session: $session_id"
        echo "Type: $session_type"
        if [[ -n "$tasks_file" ]]; then
            echo "Tasks file: $tasks_file"
        fi
    fi
}

main "$@"