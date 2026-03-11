#!/usr/bin/env bash
# session-postflight.sh - Post-flight completion for all session agents
# Marks workflow step as completed/failed, outputs valid next steps

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/session-common.sh"

# ============================================================================
# Defaults
# ============================================================================

STEP_NAME=""
STEP_STATUS="completed"
JSON_OUTPUT=false

# ============================================================================
# Usage
# ============================================================================

usage() {
    cat << EOF
Usage: session-postflight.sh --step <step_name> [OPTIONS]

Post-flight completion for session agents. Run after agent work is done.

OPTIONS:
    --step NAME       Required. The workflow step that just finished
    --status STATUS   Completion status: completed (default) or failed
    --json            Output JSON for AI consumption
    -h, --help        Show this help

WHAT IT DOES:
    1. Validates the step is currently in_progress
    2. Marks the step as completed or failed
    3. Outputs the valid next steps for chaining

EXAMPLES:
    session-postflight.sh --step scope --json
    session-postflight.sh --step execute --status failed --json
    session-postflight.sh --step validate --json
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
            --status)
                STEP_STATUS="$2"
                shift 2
                ;;
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

    if [[ -z "$STEP_NAME" ]]; then
        echo "ERROR: --step is required" >&2
        usage
        exit 1
    fi

    if [[ "$STEP_STATUS" != "completed" && "$STEP_STATUS" != "failed" ]]; then
        echo "ERROR: --status must be 'completed' or 'failed'" >&2
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

# ============================================================================
# Main Logic
# ============================================================================

main() {
    parse_args "$@"

    # 1. Check for active session
    local session_id
    session_id=$(get_active_session)

    if [[ -z "$session_id" ]]; then
        output_error "No active session found" "invoke session.start first"
        exit 1
    fi

    local session_dir
    session_dir=$(get_session_dir "$session_id")

    if [[ ! -d "$session_dir" ]]; then
        output_error "Session directory not found: $session_dir" "Session may have been cleaned up"
        exit 1
    fi

    # 2. Validate the step is currently in_progress
    local state_file="${session_dir}/state.json"

    if [[ ! -f "$state_file" ]]; then
        output_error "State file not found" "Run session-preflight.sh first"
        exit 1
    fi

    local current_step step_status
    current_step=$(jq -r '.current_step // "none"' "$state_file" 2>/dev/null)
    step_status=$(jq -r '.step_status // "none"' "$state_file" 2>/dev/null)

    if [[ "$current_step" != "$STEP_NAME" ]]; then
        output_error "Step mismatch: current step is '$current_step', not '$STEP_NAME'" "Run session-preflight.sh --step $STEP_NAME first"
        exit 1
    fi

    if [[ "$step_status" != "in_progress" ]]; then
        output_error "Step '$STEP_NAME' is not in_progress (status: $step_status)" "Step may have already been completed"
        exit 1
    fi

    # 3. Mark step as completed or failed
    set_workflow_step "$session_id" "$STEP_NAME" "$STEP_STATUS" >/dev/null

    # 4. Determine valid next steps
    local valid_next="${WORKFLOW_TRANSITIONS[$STEP_NAME]:-}"

    # 5. Output result
    if $JSON_OUTPUT; then
        local info_file="${session_dir}/session-info.json"
        local workflow
        workflow=$(jq -r '.workflow // "development"' "$info_file" 2>/dev/null)

        jq -n \
            --arg status "ok" \
            --arg step "$STEP_NAME" \
            --arg result "$STEP_STATUS" \
            --arg session_id "$session_id" \
            --arg workflow "$workflow" \
            --arg valid_next "$valid_next" \
            '{
                status: $status,
                step: $step,
                result: $result,
                session_id: $session_id,
                workflow: $workflow,
                valid_next_steps: ($valid_next | split(" ") | map(select(. != "")))
            }'
    else
        if [[ "$STEP_STATUS" == "completed" ]]; then
            print_success "Step '$STEP_NAME' completed"
        else
            print_error "Step '$STEP_NAME' failed"
        fi
        if [[ -n "$valid_next" ]]; then
            echo "Valid next steps: $valid_next"
        else
            echo "No further steps (terminal)"
        fi
    fi
}

main "$@"
