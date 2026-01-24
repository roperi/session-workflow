#!/usr/bin/env bash
# session-validate.sh - Validates session work quality
# Part of Post-Execute Agent Chain (#665)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=session-common.sh
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
                echo "Usage: session-validate.sh [--json]"
                exit 0
                ;; 
            *) 
                echo "Unknown option: $1" >&2
                exit 1
                ;; 
        esac
    done
}

# Output JSON structure for AI parsing
output_json() {
    local status="$1"
    local message="$2"
    shift 2
    local checks=("$@")
    
    echo "{"
    echo "  \"status\": \"${status}\","
    echo "  \"message\": \"${message}\","
    echo "  \"validation_checks\": ["
    
    local first=true
    for check in "${checks[@]}"; do
        if [[ "$first" == true ]]; then
            first=false
        else
            echo ","
        fi
        echo -n "    ${check}"
    done
    echo ""
    echo "  ]"
    echo "}"
}

# Main validation logic
main() {
    parse_args "$@"
    
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

    # 1. Workflow Check
    if ! check_workflow_allowed "$session_id" "development" 2>/dev/null; then
         # Validation is only strictly required for development workflow
         # Spike workflow skips formal validation
         local workflow
         workflow=$(detect_workflow "$session_id")
         if [[ "$workflow" == "spike" ]]; then
             if $JSON_OUTPUT; then
                echo '{"status": "ok", "message": "Spike workflow skips formal validation", "workflow": "spike"}'
             else
                print_info "Spike workflow skips formal validation"
             fi
             exit 0
         fi
    fi

    # Update workflow state
    set_workflow_step "$session_id" "validate" "in_progress" >/dev/null

    local checks=()
    local failures=()
    local status="success"
    
    # Check 1: Git status
    if git diff --quiet && git diff --cached --quiet; then
        checks+=('{"check": "git_status", "status": "pass", "message": "Working tree clean"}')
    else
        checks+=('{"check": "git_status", "status": "fail", "message": "Uncommitted changes found"}')
        failures+=("git_status")
        status="error"
    fi
    
    # Check 2: Branch ahead of origin
    if git rev-parse --verify HEAD >/dev/null 2>&1; then
        local current_branch
        current_branch=$(git rev-parse --abbrev-ref HEAD)
        
        if [[ "$current_branch" != "main" && "$current_branch" != "HEAD" ]]; then
            # Check if branch exists on remote
            if git rev-parse --verify "origin/${current_branch}" >/dev/null 2>&1; then
                local ahead
                ahead=$(git rev-list --count "origin/${current_branch}..HEAD")
                if [[ "$ahead" -gt 0 ]]; then
                    checks+=("{\"check\": \"git_ahead\", \"status\": \"pass\", \"message\": \"Branch ahead by ${ahead} commits\"}")
                else
                    checks+=('{"check": "git_ahead", "status": "warning", "message": "No new commits to push"}')
                fi
            else
                checks+=('{"check": "git_ahead", "status": "pass", "message": "New branch, ready to push"}')
            fi
        else
            checks+=('{"check": "git_ahead", "status": "warning", "message": "On main branch"}')
        fi
    fi
    
    # Check 3: Active session exists
    checks+=("{\"check\": \"active_session\", \"status\": \"pass\", \"message\": \"Active session: ${session_id}\"}")
    
    # Check 4: Tasks completion
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    local info_file="${session_dir}/session-info.json"
    local session_type
    session_type=$(jq -r '.type // "unknown"' "$info_file")
    
    local tasks_file=""
    if [[ "$session_type" == "speckit" ]]; then
        local spec_dir
        spec_dir=$(jq -r '.spec_dir // empty' "$info_file")
        if [[ -d "$spec_dir" ]]; then tasks_file="${spec_dir}/tasks.md";
        elif [[ -d "specs/$spec_dir" ]]; then tasks_file="specs/${spec_dir}/tasks.md"; fi
    else
        tasks_file="${session_dir}/tasks.md"
    fi

    if [[ -f "$tasks_file" ]]; then
        local counts
        counts=$(count_tasks "$tasks_file")
        local total completed
        total=$(echo "$counts" | cut -d: -f1)
        completed=$(echo "$counts" | cut -d: -f2)
        
        if [[ "$total" -eq "$completed" && "$total" -gt 0 ]]; then
            checks+=("{\"check\": \"tasks\", \"status\": \"pass\", \"message\": \"All ${total} tasks complete\"}")
        elif [[ "$total" -eq 0 ]]; then
            checks+=('{"check": "tasks", "status": "warning", "message": "No tasks defined in tasks.md"}')
        else
            local remaining=$((total - completed))
            checks+=("{\"check\": \"tasks\", \"status\": \"fail\", \"message\": \"${remaining} of ${total} tasks incomplete\"}")
            failures+=("tasks")
            status="error"
        fi
    else
        checks+=('{"check": "tasks", "status": "warning", "message": "No tasks.md found"}')
    fi
    
    # Check 5: Technical Context Checks (Linter/Tests)
    # We report if they are CONFIGURED. The agent actually runs them.
    if [[ -f ".session/project-context/technical-context.md" ]]; then
        checks+=('{"check": "technical_context", "status": "pass", "message": "Technical context loaded"}')
    else
        checks+=('{"check": "technical_context", "status": "warning", "message": "technical-context.md missing"}')
    fi

    # Determine final status
    if [[ "${#failures[@]}" -gt 0 ]]; then
        status="error"
        local message="Validation failed: ${#failures[@]} critical issues"
        set_workflow_step "$session_id" "validate" "failed" >/dev/null
    else
        local message="Session validation passed mechanical checks"
        # Note: We don't mark 'completed' yet because the agent still needs 
        # to run tests/lint. We'll let the agent mark it completed.
    fi
    
    # Output JSON
    if $JSON_OUTPUT; then
        output_json "$status" "$message" "${checks[@]}"
    else
        print_info "$message"
        for check in "${checks[@]}"; do
            echo "  - $(echo "$check" | jq -r '.message')"
        done
    fi
}

# Run main
main "$@"