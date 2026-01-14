#!/usr/bin/env bash
# session-validate.sh - Validates session work quality
# Part of Post-Execute Agent Chain (#665)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=session-common.sh
source "${SCRIPT_DIR}/session-common.sh"

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
    if [[ -f "${ACTIVE_SESSION_FILE}" ]]; then
        local session_id
        session_id=$(cat "${ACTIVE_SESSION_FILE}")
        checks+=("{\"check\": \"active_session\", \"status\": \"pass\", \"message\": \"Active session: ${session_id}\"}")
    else
        checks+=('{"check": "active_session", "status": "warning", "message": "No active session file"}')
    fi
    
    # Check 4: Tasks file exists
    if [[ -f "${ACTIVE_SESSION_FILE}" ]]; then
        local session_id
        session_id=$(cat "${ACTIVE_SESSION_FILE}")
        local session_dir="${SESSIONS_DIR}/${session_id}"
        
        if [[ -f "${session_dir}/tasks.md" ]]; then
            # Count tasks
            local total_tasks
            local completed_tasks
            total_tasks=$(grep -c '^\s*- \[' "${session_dir}/tasks.md" || echo 0)
            completed_tasks=$(grep -c '^\s*- \[x\]' "${session_dir}/tasks.md" || echo 0)
            
            if [[ "$total_tasks" -eq "$completed_tasks" ]]; then
                checks+=("{\"check\": \"tasks\", \"status\": \"pass\", \"message\": \"All ${total_tasks} tasks complete\"}")
            else
                local remaining=$((total_tasks - completed_tasks))
                checks+=("{\"check\": \"tasks\", \"status\": \"warning\", \"message\": \"${remaining} of ${total_tasks} tasks incomplete\"}")
            fi
        else
            checks+=('{"check": "tasks", "status": "warning", "message": "No tasks.md found"}')
        fi
    fi
    
    # Determine final status
    if [[ "${#failures[@]}" -gt 0 ]]; then
        status="error"
        local message="Validation failed: ${#failures[@]} critical issues"
    else
        local message="Session validation passed"
    fi
    
    # Output JSON
    output_json "$status" "$message" "${checks[@]}"
}

# Run main
main "$@"
