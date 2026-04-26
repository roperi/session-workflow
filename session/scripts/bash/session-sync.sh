#!/usr/bin/env bash
# session-sync.sh - Synchronize session state across tool-specific context files
# This ensures Claude, Gemini, Copilot, etc. see the same active session context.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/session-common.sh"

# ============================================================================
# Helpers
# ============================================================================

update_file_with_markers() {
    local file="$1"
    local block="$2"
    local start_marker="<!-- SESSION_WORKFLOW_START -->"
    local end_marker="<!-- SESSION_WORKFLOW_END -->"

    [[ -f "$file" ]] || return 0

    local tmp
    tmp=$(mktemp)
    
    if grep -q "$start_marker" "$file"; then
        # Replace existing block
        sed -e "/$start_marker/,/$end_marker/c\\" -e "$start_marker\n$block\n$end_marker" "$file" > "$tmp"
    else
        # Append new block
        cat "$file" > "$tmp"
        echo -e "\n$start_marker\n$block\n$end_marker" >> "$tmp"
    fi
    
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

# ============================================================================
# Main
# ============================================================================

main() {
    local session_id
    session_id=$(get_active_session)

    if [[ -z "$session_id" ]]; then
        # If no active session, we should probably clear the markers or just exit
        exit 0
    fi

    local session_dir
    session_dir=$(get_session_dir "$session_id")
    local state_file="${session_dir}/state.json"
    local info_file="${session_dir}/session-info.json"

    if [[ ! -f "$state_file" || ! -f "$info_file" ]]; then
        exit 0
    fi

    # Extract state info
    local current_step step_status workflow branch
    current_step=$(jq -r '.current_step // "none"' "$state_file")
    step_status=$(jq -r '.step_status // "none"' "$state_file")
    workflow=$(jq -r '.workflow // "development"' "$info_file")
    branch=$(jq -r '.git.branch // "unknown"' "$state_file")

    # Format the block
    local block
    block="## Active Session Context
- **Session ID**: ${session_id}
- **Workflow**: ${workflow}
- **Current Step**: ${current_step} (${step_status})
- **Branch**: ${branch}
- **Directory**: ${session_dir}

Use \`invoke session.<step>\` to continue the workflow."

    # Update tool-specific files
    update_file_with_markers "CLAUDE.md" "$block"
    update_file_with_markers ".clauderules" "$block"
    update_file_with_markers ".gemini/context.md" "$block"
    update_file_with_markers ".github/copilot-instructions.md" "$block"
    update_file_with_markers ".cursorrules" "$block"
}

main "$@"
