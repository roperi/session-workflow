#!/usr/bin/env bash
# session-wrap.sh - Finalize session (mechanical only)
# Part of Session Workflow Enhancement (#566, simplified in #584)
#
# This script is purely mechanical - it marks the session complete.
# Validation and checklist compliance is handled by the prompt, not this script.

set -euo pipefail

# Get script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/session-common.sh"

# ============================================================================
# Defaults
# ============================================================================

JSON_OUTPUT=false

# ============================================================================
# Usage
# ============================================================================

usage() {
    cat << EOF
Usage: session-wrap.sh [OPTIONS]

Finalize the current session by marking it complete.

This script is purely mechanical:
  1. Checks an active session exists
  2. Updates state.json with completion timestamp
  3. Clears ACTIVE_SESSION sentinel
  4. Outputs session summary

Validation (git clean, notes, tasks, changelog, etc.) is handled by the
session.wrap prompt, not this script.

OPTIONS:
    --json      Output JSON for AI consumption
    -h, --help  Show this help
EOF
}

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
}

# ============================================================================
# Validation Functions
# ============================================================================

check_session_readiness() {
    # Returns warnings as array (non-blocking, for informational purposes)
    local session_id="$1"
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    local warnings=()
    
    # Warn if no workflow steps were ever tracked (session may have had zero tracked work)
    local state_file="${session_dir}/state.json"
    local current_step="none"
    if [[ -f "$state_file" ]]; then
        current_step=$(jq -r '.current_step // "none"' "$state_file" 2>/dev/null || echo "none")
    fi
    if [[ "$current_step" == "none" ]]; then
        warnings+=("No workflow steps were tracked — session may have had no tracked work")
    fi

    # Check for uncommitted changes
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        warnings+=("Uncommitted changes present - consider committing before wrap")
    fi
    
    # Check tasks completion
    local tasks_file="${session_dir}/tasks.md"
    if [[ -f "$tasks_file" ]]; then
        local counts
        counts=$(count_tasks "$tasks_file")
        local total completed
        total=$(echo "$counts" | cut -d: -f1)
        completed=$(echo "$counts" | cut -d: -f2)
        if [[ "$total" -gt 0 ]] && [[ "$completed" -lt "$total" ]]; then
            warnings+=("Tasks incomplete: ${completed}/${total} done")
        fi
    fi
    
    # Check notes have "For Next Session" content
    local notes_file="${session_dir}/notes.md"
    if [[ -f "$notes_file" ]]; then
        local for_next
        for_next=$(get_for_next_session_section "$session_id")
        # Extract the body of the "For Next Session" section (excluding the header).
        # A body containing only whitespace (spaces, tabs, newlines) is treated as empty.
        local for_next_body
        for_next_body=$(echo "$for_next" | tail -n +2 2>/dev/null || true)
        if [[ -z "$for_next" ]] || ! printf '%s' "$for_next_body" | grep -q '[^[:space:]]'; then
            warnings+=("notes.md missing 'For Next Session' content")
        fi
    fi
    
    # Return warnings (newline-separated)
    printf '%s\n' "${warnings[@]}"
}

# ============================================================================
# Update Functions
# ============================================================================

update_session_state() {
    local session_id="$1"
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    local state_file="${session_dir}/state.json"
    
    local ended_at
    ended_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local branch
    branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    
    local last_commit
    last_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    
    # Get notes summary
    local notes_summary
    notes_summary=$(load_session_notes_summary "$session_id")
    notes_summary=$(json_escape "$notes_summary")
    
    # Get task counts
    local tasks_file="${session_dir}/tasks.md"
    local total=0
    local completed=0
    if [[ -f "$tasks_file" ]]; then
        local counts
        counts=$(count_tasks "$tasks_file")
        total=$(echo "$counts" | cut -d: -f1)
        completed=$(echo "$counts" | cut -d: -f2)
    fi
    
    # Update state file
    local tmp_file
    tmp_file=$(mktemp)
    jq --arg ended_at "$ended_at" \
       --arg branch "$branch" \
       --arg last_commit "$last_commit" \
       --arg notes_summary "$notes_summary" \
       --argjson total "$total" \
       --argjson completed "$completed" \
       '.status = "completed" |
        .ended_at = $ended_at |
        .git.branch = $branch |
        .git.last_commit = $last_commit |
        .notes_summary = $notes_summary |
        .tasks.total = $total |
        .tasks.completed = $completed' \
       "$state_file" > "$tmp_file"
    mv "$tmp_file" "$state_file"
}

# ============================================================================
# Output Functions
# ============================================================================

output_json() {
    local session_id="$1"
    local warnings="$2"
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    
    # Get task counts for summary
    local tasks_file="${session_dir}/tasks.md"
    local total=0
    local completed=0
    if [[ -f "$tasks_file" ]]; then
        local counts
        counts=$(count_tasks "$tasks_file")
        total=$(echo "$counts" | cut -d: -f1)
        completed=$(echo "$counts" | cut -d: -f2)
    fi
    
    # Format warnings as JSON array
    local warnings_json="[]"
    if [[ -n "$warnings" ]]; then
        warnings_json=$(echo "$warnings" | jq -R -s 'split("\n") | map(select(length > 0))')
    fi
    
    cat << EOF
{
  "status": "ok",
  "session": {
    "id": "${session_id}",
    "dir": "${session_dir}",
    "completed": true
  },
  "summary": {
    "tasks_total": ${total},
    "tasks_completed": ${completed}
  },
  "warnings": ${warnings_json}
}
EOF
}

output_human() {
    local session_id="$1"
    local warnings="$2"
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    
    echo ""
    echo "Session Wrapped: ${session_id}"
    echo "============================================"
    echo ""
    echo "Session files preserved in: ${session_dir}"
    
    # Display warnings if any
    if [[ -n "$warnings" ]]; then
        echo ""
        print_warning "Wrap completed with warnings:"
        echo "$warnings" | while read -r warning; do
            if [[ -n "$warning" ]]; then
                echo "  - $warning"
            fi
        done
    fi
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    parse_args "$@"
    
    # Ensure structure exists
    ensure_session_structure
    
    # Check for active session
    local active_session
    active_session=$(get_active_session)
    
    if [[ -z "$active_session" ]]; then
        # Check for orphan work indicators
        local has_uncommitted=false
        local recent_commits=""
        
        if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
            has_uncommitted=true
        fi
        recent_commits=$(git log --oneline --since="4 hours ago" 2>/dev/null | head -3)
        
        if $JSON_OUTPUT; then
            local orphan_hint=""
            if [[ "$has_uncommitted" == "true" ]] || [[ -n "$recent_commits" ]]; then
                orphan_hint=", \"hint\": \"Detected recent work without session tracking. Consider creating a retroactive session.\""
            fi
            echo "{\"status\": \"error\", \"message\": \"No active session to wrap\"${orphan_hint}}"
        else
            print_error "No active session to wrap"
            if [[ "$has_uncommitted" == "true" ]] || [[ -n "$recent_commits" ]]; then
                echo ""
                print_warning "Orphan work detected:"
                if [[ "$has_uncommitted" == "true" ]]; then
                    echo "  - Uncommitted changes present"
                fi
                if [[ -n "$recent_commits" ]]; then
                    echo "  - Recent commits found:"
                    echo "$recent_commits" | sed 's/^/      /'
                fi
                echo ""
                echo "To create a retroactive session:"
                echo "  1. Run: .session/scripts/bash/session-start.sh --issue 123  (or --spec, \"Goal\")"
                echo "  2. Then run: .session/scripts/bash/session-wrap.sh"
            else
                echo "Start a session first: .session/scripts/bash/session-start.sh --issue 123"
            fi
        fi
        exit 1
    fi
    
    # Check session readiness (non-blocking warnings)
    local warnings
    warnings=$(check_session_readiness "$active_session")
    
    # Update state and clear sentinel
    update_session_state "$active_session"
    clear_active_session
    
    # Output results
    if $JSON_OUTPUT; then
        output_json "$active_session" "$warnings"
    else
        output_human "$active_session" "$warnings"
    fi
    
    exit 0
}

main "$@"
