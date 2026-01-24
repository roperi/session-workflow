#!/usr/bin/env bash
# session-plan.sh - Prepare for session planning
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
                echo "Usage: session-plan.sh [--json]"
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
    
    if [[ ! -f "$info_file" ]]; then
        if $JSON_OUTPUT; then
            echo "{\"status\": \"error\", \"message\": \"Session info not found: ${info_file}\"}"
        else
            print_error "Session info not found: ${info_file}"
        fi
        exit 1
    fi
    
    # Update workflow state
    set_workflow_step "$session_id" "plan" "in_progress" >/dev/null
    
    # Read Session Info
    local session_type
    local workflow
    local issue_number
    local spec_dir
    local goal
    
    session_type=$(jq -r '.type // "unknown"' "$info_file")
    workflow=$(jq -r '.workflow // "development"' "$info_file")
    issue_number=$(jq -r '.issue_number // empty' "$info_file")
    spec_dir=$(jq -r '.spec_dir // empty' "$info_file")
    goal=$(jq -r '.goal // empty' "$info_file")
    
    # 2. Type-Specific Logic
    local type_data="{}"
    local warnings="[]"
    
    case "$session_type" in
        speckit)
            # Check for local speckit scripts
            if [[ -f ".specify/scripts/bash/check-prerequisites.sh" ]]; then
                # Run external check if available (capture output? blindly run?)
                # For now, we'll just note it exists. 
                # Ideally, we'd run it and parse its JSON if it supports it.
                # Assuming the agent was running it, we can leave that to the agent 
                # OR we can wrap it here. Let's try to verify the spec dir at least.
                if [[ -n "$spec_dir" && ! -d "$spec_dir" && ! -d "specs/$spec_dir" ]]; then
                     warnings=$(echo "$warnings" | jq '. + ["Spec directory not found: '"$spec_dir"'"]' )
                fi
            else
                # Basic checks
                if [[ -n "$spec_dir" ]]; then
                     if [[ -d "$spec_dir" ]]; then
                        type_data=$(jq -n --arg dir "$spec_dir" '{spec_path: $dir, exists: true}')
                     elif [[ -d "specs/$spec_dir" ]]; then
                        type_data=$(jq -n --arg dir "specs/$spec_dir" '{spec_path: $dir, exists: true}')
                     else
                        type_data=$(jq -n --arg dir "$spec_dir" '{spec_path: $dir, exists: false}')
                        warnings=$(echo "$warnings" | jq '. + ["Spec directory not found"]' )
                     fi
                fi
            fi
            ;;
            
        github_issue)
            if command -v gh &>/dev/null && [[ -n "$issue_number" ]]; then
                # Fetch issue details
                local issue_json
                issue_json=$(gh issue view "$issue_number" --json title,body,labels,state,assignees 2>/dev/null || echo "{}")
                if [[ "$issue_json" != "{}" ]]; then
                    type_data="$issue_json"
                else
                    warnings=$(echo "$warnings" | jq '. + ["Could not fetch GitHub issue #'$issue_number'"]' )
                fi
            fi
            ;;
            
unstructured)
            type_data=$(jq -n --arg goal "$goal" '{goal: $goal}')
            ;; 
    esac

    # 3. Output JSON
    if $JSON_OUTPUT; then
        # Construct full JSON response
        jq -n \
            --arg status "ok" \
            --arg id "$session_id" \
            --arg dir "$session_dir" \
            --arg type "$session_type" \
            --arg workflow "$workflow" \
            --argjson type_data "$type_data" \
            --argjson warnings "$warnings" \
            '{
                status: $status,
                session: {
                    id: $id,
                    dir: $dir,
                    type: $type,
                    workflow: $workflow
                },
                context: $type_data,
                warnings: $warnings
            }'
    else
        print_info "Session Planning Ready"
        echo "Session: $session_id"
        echo "Type: $session_type"
        echo "Workflow: $workflow"
        if [[ -n "$warnings" && "$warnings" != "[]" ]]; then
             echo "Warnings: $warnings"
        fi
    fi
}

main "$@"
