#!/usr/bin/env bash
# session-audit.sh - Deterministic audit of session artifacts and workflow traces

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=session-common.sh
source "${SCRIPT_DIR}/session-common.sh"

JSON_OUTPUT=false
ALL=false
SUMMARY_ONLY=false
SESSION_FILTER=""
WORKFLOW_FILTER=""
SINCE_FILTER=""
SELECTION_MODE="latest"

usage() {
    cat << EOF
Usage: session-audit.sh [OPTIONS]

Audit session artifacts in the current repository.

OPTIONS:
    --session ID     Audit a specific session
    --all            Audit all matching sessions
    --workflow NAME  Filter by workflow (development|spike|maintenance|debug|operational)
    --since DATE     Filter by created/session date (YYYY-MM-DD)
    --summary        Show aggregate summary across the selected sessions
    --json           Output JSON
    -h, --help       Show this help

Default behavior with no selector flags:
    - active session, if one exists
    - otherwise the most recent session
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --session)
                SESSION_FILTER="$2"
                shift 2
                ;;
            --all)
                ALL=true
                shift
                ;;
            --workflow)
                WORKFLOW_FILTER="$2"
                shift 2
                ;;
            --since)
                SINCE_FILTER="$2"
                shift 2
                ;;
            --summary)
                SUMMARY_ONLY=true
                shift
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
}

validate_args() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "ERROR: jq is required for session-audit.sh" >&2
        exit 1
    fi

    if [[ -n "$SESSION_FILTER" && "$ALL" == "true" ]]; then
        echo "ERROR: --session and --all cannot be used together" >&2
        exit 1
    fi

    if [[ -n "$WORKFLOW_FILTER" ]]; then
        case "$WORKFLOW_FILTER" in
            development|spike|maintenance|debug|operational)
                ;;
            *)
                echo "ERROR: Unsupported workflow: $WORKFLOW_FILTER" >&2
                exit 1
                ;;
        esac
    fi

    if [[ -n "$SINCE_FILTER" && ! "$SINCE_FILTER" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "ERROR: --since must use YYYY-MM-DD format" >&2
        exit 1
    fi
}

build_checks_json() {
    local checks=("$@")
    local checks_json="[]"
    local check

    for check in "${checks[@]}"; do
        checks_json=$(echo "$checks_json" | jq --argjson c "$check" '. + [$c]')
    done

    echo "$checks_json"
}

build_check_json() {
    local check="$1"
    local status="$2"
    local message="$3"
    local details_json="$4"

    jq -n \
        --arg check "$check" \
        --arg status "$status" \
        --arg message "$message" \
        --argjson details "$details_json" \
        '{check: $check, status: $status, message: $message, details: $details}'
}

json_array_from_lines() {
    local lines="${1:-}"
    printf '%s\n' "$lines" | jq -R -s 'split("\n") | map(select(length > 0))'
}

file_has_meaningful_content() {
    local path="$1"
    [[ -f "$path" ]] || return 1

    sed \
        -e '/^[[:space:]]*#/d' \
        -e '/^[[:space:]]*<!--.*-->[[:space:]]*$/d' \
        -e '/^[[:space:]]*$/d' \
        "$path" | grep -q '[^[:space:]]'
}

step_in_list() {
    local step="$1"
    local step_list="${2:-}"
    [[ -n "$step_list" ]] || return 1
    printf '%s\n' "$step_list" | grep -qxF "$step"
}

allowed_steps_for_workflow() {
    local workflow="$1"

    case "$workflow" in
        development)
            printf '%s\n' start brainstorm scope spec plan task execute validate publish review finalize wrap
            ;;
        spike)
            printf '%s\n' start brainstorm scope plan task execute wrap
            ;;
        maintenance|debug|operational)
            printf '%s\n' start execute wrap
            ;;
        *)
            printf '%s\n' start execute wrap
            ;;
    esac
}

required_steps_for_workflow() {
    local workflow="$1"
    local session_completed="$2"
    local observed_steps="${3:-}"

    case "$workflow" in
        development)
            printf '%s\n' start scope spec plan task execute
            if [[ "$session_completed" == "true" ]] || step_in_list validate "$observed_steps" || step_in_list publish "$observed_steps" || step_in_list review "$observed_steps" || step_in_list finalize "$observed_steps" || step_in_list wrap "$observed_steps"; then
                printf '%s\n' validate
            fi
            if [[ "$session_completed" == "true" ]] || step_in_list publish "$observed_steps" || step_in_list review "$observed_steps" || step_in_list finalize "$observed_steps" || step_in_list wrap "$observed_steps"; then
                printf '%s\n' publish
            fi
            if [[ "$session_completed" == "true" ]] || step_in_list finalize "$observed_steps" || step_in_list wrap "$observed_steps"; then
                printf '%s\n' finalize wrap
            fi
            ;;
        spike)
            printf '%s\n' start scope plan task execute
            if [[ "$session_completed" == "true" ]] || step_in_list wrap "$observed_steps"; then
                printf '%s\n' wrap
            fi
            ;;
        maintenance|debug|operational)
            printf '%s\n' start execute
            if [[ "$session_completed" == "true" ]] || step_in_list wrap "$observed_steps"; then
                printf '%s\n' wrap
            fi
            ;;
        *)
            printf '%s\n' start
            ;;
    esac
}

get_session_date() {
    local session_dir="$1"
    local info_file="${session_dir}/session-info.json"
    local created_at=""

    if [[ -f "$info_file" ]]; then
        created_at=$(jq -r '.created_at // ""' "$info_file" 2>/dev/null || echo "")
    fi

    if [[ -n "$created_at" && "$created_at" != "null" ]]; then
        printf '%s\n' "${created_at:0:10}"
    else
        basename "$session_dir" | cut -d'-' -f1-3
    fi
}

session_matches_filters() {
    local session_dir="$1"
    local info_file="${session_dir}/session-info.json"

    if [[ -n "$WORKFLOW_FILTER" ]]; then
        local workflow
        workflow=$(jq -r '.workflow // "unknown"' "$info_file" 2>/dev/null || echo "unknown")
        [[ "$workflow" == "$WORKFLOW_FILTER" ]] || return 1
    fi

    if [[ -n "$SINCE_FILTER" ]]; then
        local session_date
        session_date=$(get_session_date "$session_dir")
        [[ "$session_date" < "$SINCE_FILTER" ]] && return 1
    fi

    return 0
}

select_session_dirs() {
    ensure_session_structure

    if [[ -n "$SESSION_FILTER" ]]; then
        SELECTION_MODE="session"
        local session_dir
        session_dir=$(get_session_dir "$SESSION_FILTER")
        if [[ -d "$session_dir" ]]; then
            printf '%s\n' "$session_dir"
        fi
        return
    fi

    local dirs
    dirs=$(list_session_dirs)

    if [[ "$ALL" == "true" || "$SUMMARY_ONLY" == "true" || -n "$WORKFLOW_FILTER" || -n "$SINCE_FILTER" ]]; then
        SELECTION_MODE="query"
        while IFS= read -r session_dir; do
            [[ -n "$session_dir" ]] || continue
            if session_matches_filters "$session_dir"; then
                printf '%s\n' "$session_dir"
            fi
        done <<< "$dirs"
        return
    fi

    local active_session
    active_session=$(get_active_session)
    if [[ -n "$active_session" ]]; then
        local active_dir
        active_dir=$(get_session_dir "$active_session")
        if [[ -d "$active_dir" ]]; then
            SELECTION_MODE="active"
            printf '%s\n' "$active_dir"
            return
        fi
    fi

    SELECTION_MODE="latest"
    printf '%s\n' "$dirs" | head -n 1
}

resolve_validation_results_file() {
    local session_id="$1"
    local session_dir="$2"
    local session_results_file="${session_dir}/validation-results.json"
    local local_results_file="${SESSION_ROOT}/validation-results.json"

    if [[ -f "$session_results_file" ]]; then
        validate_schema_version "$session_results_file" "$VALIDATION_RESULTS_SCHEMA_VERSION"
        printf '%s\t%s\n' "$session_results_file" "session"
        return
    fi

    if [[ -f "$local_results_file" ]]; then
        validate_schema_version "$local_results_file" "$VALIDATION_RESULTS_SCHEMA_VERSION"
        local local_session_id
        local_session_id=$(jq -r '.session_id // ""' "$local_results_file" 2>/dev/null || echo "")
        if [[ "$local_session_id" == "$session_id" ]]; then
            printf '%s\t%s\n' "$local_results_file" "local"
            return
        fi
    fi

    printf '\t%s\n' "missing"
}

audit_workflow_adherence() {
    local workflow="$1"
    local state_file="$2"
    local session_completed="$3"

    if [[ "$workflow" == "unknown" ]]; then
        build_check_json "workflow_adherence" "unavailable" \
            "Workflow expectations are unavailable because session-info.json is missing" \
            '{"state_file": null, "observed_steps": [], "required_steps": [], "missing_steps": [], "unexpected_steps": [], "forced_steps": 0}'
        return
    fi

    if [[ ! -f "$state_file" ]]; then
        build_check_json "workflow_adherence" "unavailable" \
            "No local state.json available; workflow adherence cannot be verified" \
            '{"state_file": null, "observed_steps": [], "required_steps": [], "missing_steps": [], "unexpected_steps": [], "forced_steps": 0}'
        return
    fi

    validate_schema_version "$state_file" "$STATE_SCHEMA_VERSION"

    local observed_steps
    observed_steps=$(jq -r '.step_history[]?.step' "$state_file" 2>/dev/null || true)
    if [[ -z "$observed_steps" ]]; then
        build_check_json "workflow_adherence" "unavailable" \
            "state.json does not contain step_history entries" \
            "{\"state_file\": \"${state_file}\", \"observed_steps\": [], \"required_steps\": [], \"missing_steps\": [], \"unexpected_steps\": [], \"forced_steps\": 0}"
        return
    fi

    local observed_unique
    observed_unique=$(printf '%s\n' "$observed_steps" | awk 'NF && !seen[$0]++')

    local required_steps
    required_steps=$(required_steps_for_workflow "$workflow" "$session_completed" "$observed_unique")
    local allowed_steps
    allowed_steps=$(allowed_steps_for_workflow "$workflow")

    local missing_steps=""
    local step
    while IFS= read -r step; do
        [[ -n "$step" ]] || continue
        if ! step_in_list "$step" "$observed_unique"; then
            missing_steps+="${step}"$'\n'
        fi
    done <<< "$required_steps"

    local unexpected_steps=""
    while IFS= read -r step; do
        [[ -n "$step" ]] || continue
        if ! step_in_list "$step" "$allowed_steps"; then
            unexpected_steps+="${step}"$'\n'
        fi
    done <<< "$observed_unique"

    local forced_steps
    forced_steps=$(jq '[.step_history[]? | select(.forced == true)] | length' "$state_file" 2>/dev/null || echo 0)

    local state_status
    state_status=$(jq -r '.status // "unknown"' "$state_file" 2>/dev/null || echo "unknown")

    local details_json
    details_json=$(jq -n \
        --arg state_file "$state_file" \
        --arg state_status "$state_status" \
        --argjson session_completed "$session_completed" \
        --argjson observed_steps "$(json_array_from_lines "$observed_unique")" \
        --argjson required_steps "$(json_array_from_lines "$required_steps")" \
        --argjson missing_steps "$(json_array_from_lines "$missing_steps")" \
        --argjson unexpected_steps "$(json_array_from_lines "$unexpected_steps")" \
        --argjson forced_steps "$forced_steps" \
        '{
            state_file: $state_file,
            state_status: $state_status,
            session_completed: $session_completed,
            observed_steps: $observed_steps,
            required_steps: $required_steps,
            missing_steps: $missing_steps,
            unexpected_steps: $unexpected_steps,
            forced_steps: $forced_steps
        }')

    if [[ -n "$unexpected_steps" ]]; then
        build_check_json "workflow_adherence" "fail" \
            "Observed steps outside the allowed ${workflow} workflow" \
            "$details_json"
    elif [[ -n "$missing_steps" ]]; then
        build_check_json "workflow_adherence" "fail" \
            "Missing required ${workflow} workflow steps" \
            "$details_json"
    elif [[ "$forced_steps" -gt 0 ]]; then
        build_check_json "workflow_adherence" "warning" \
            "Required workflow steps are present, but forced transitions were used" \
            "$details_json"
    else
        build_check_json "workflow_adherence" "pass" \
            "Observed workflow steps match the expected ${workflow} flow" \
            "$details_json"
    fi
}

audit_artifact_completeness() {
    local session_dir="$1"
    local workflow="$2"
    local tasks_file="$3"
    local spec_file="$4"
    local session_completed="$5"
    local observed_steps="$6"

    local -a required_labels=(
        "session-info.json"
        "notes.md"
        "next.md"
        "tasks.md"
    )
    local -a required_paths=(
        "${session_dir}/session-info.json"
        "${session_dir}/notes.md"
        "${session_dir}/next.md"
        "${tasks_file}"
    )

    case "$workflow" in
        development)
            required_labels+=("scope.md" "spec.md" "plan.md")
            required_paths+=("${session_dir}/scope.md" "${spec_file}" "${session_dir}/plan.md")
            ;;
        spike)
            required_labels+=("scope.md" "plan.md")
            required_paths+=("${session_dir}/scope.md" "${session_dir}/plan.md")
            ;;
    esac

    local -a optional_labels=()
    local -a optional_paths=()
    if [[ "$workflow" == "development" ]] && { [[ "$session_completed" == "true" ]] || step_in_list publish "$observed_steps" || step_in_list finalize "$observed_steps" || step_in_list wrap "$observed_steps"; }; then
        optional_labels+=("pr-summary.md")
        optional_paths+=("${session_dir}/pr-summary.md")
    fi
    if step_in_list review "$observed_steps"; then
        optional_labels+=("review-summary.md")
        optional_paths+=("${session_dir}/review-summary.md")
    fi

    local present_files=""
    local missing_files=""
    local placeholder_files=""
    local missing_optional_files=""
    local i label path
    for i in "${!required_labels[@]}"; do
        label="${required_labels[$i]}"
        path="${required_paths[$i]}"

        if [[ -n "$path" && -f "$path" ]]; then
            present_files+="${label}"$'\n'
            if [[ "$label" != "session-info.json" && "$label" != "next.md" ]] && ! file_has_meaningful_content "$path"; then
                placeholder_files+="${label}"$'\n'
            fi
        else
            missing_files+="${label}"$'\n'
        fi
    done

    for i in "${!optional_labels[@]}"; do
        label="${optional_labels[$i]}"
        path="${optional_paths[$i]}"
        if [[ ! -f "$path" ]]; then
            missing_optional_files+="${label}"$'\n'
        fi
    done

    local details_json
    details_json=$(jq -n \
        --argjson present_files "$(json_array_from_lines "$present_files")" \
        --argjson missing_files "$(json_array_from_lines "$missing_files")" \
        --argjson placeholder_files "$(json_array_from_lines "$placeholder_files")" \
        --argjson missing_optional_files "$(json_array_from_lines "$missing_optional_files")" \
        '{
            present_files: $present_files,
            missing_files: $missing_files,
            placeholder_files: $placeholder_files,
            missing_optional_files: $missing_optional_files
        }')

    if [[ -n "$missing_files" ]]; then
        build_check_json "artifact_completeness" "fail" \
            "Required session artifacts are missing" \
            "$details_json"
    elif [[ -n "$placeholder_files" || -n "$missing_optional_files" ]]; then
        build_check_json "artifact_completeness" "warning" \
            "Session artifacts exist, but some expected files are thin or missing" \
            "$details_json"
    else
        build_check_json "artifact_completeness" "pass" \
            "Required session artifacts are present" \
            "$details_json"
    fi
}

audit_task_completion() {
    local tasks_file="$1"
    local session_completed="$2"

    if [[ ! -f "$tasks_file" ]]; then
        build_check_json "task_completion" "unavailable" \
            "No tasks.md file is available for this session" \
            '{"tasks_file": null, "total": 0, "completed": 0, "incomplete": 0, "skipped": 0, "completion_ratio": null}'
        return
    fi

    local metrics_json
    metrics_json=$(get_task_completion "$tasks_file")

    local total completed incomplete skipped
    total=$(echo "$metrics_json" | jq -r '.total')
    completed=$(echo "$metrics_json" | jq -r '.completed')
    incomplete=$(echo "$metrics_json" | jq -r '.incomplete')
    skipped=$(echo "$metrics_json" | jq -r '.skipped')

    local details_json
    details_json=$(echo "$metrics_json" | jq \
        --arg tasks_file "$tasks_file" \
        '. + {
            tasks_file: $tasks_file,
            completion_ratio: (if .total > 0 then (.completed / .total) else null end)
        }')

    if [[ "$total" -eq 0 ]]; then
        build_check_json "task_completion" "warning" \
            "No non-[SKIP] tasks were found in tasks.md" \
            "$details_json"
    elif [[ "$incomplete" -gt 0 ]]; then
        if [[ "$session_completed" == "true" ]]; then
            build_check_json "task_completion" "warning" \
                "The session is completed, but some non-[SKIP] tasks remain incomplete" \
                "$details_json"
        else
            build_check_json "task_completion" "warning" \
                "Some non-[SKIP] tasks remain incomplete" \
                "$details_json"
        fi
    elif [[ "$skipped" -gt 0 ]]; then
        build_check_json "task_completion" "pass" \
            "All non-[SKIP] tasks are complete; skipped tasks were documented" \
            "$details_json"
    else
        build_check_json "task_completion" "pass" \
            "All tracked tasks are complete" \
            "$details_json"
    fi
}

audit_validation_results() {
    local session_id="$1"
    local session_dir="$2"
    local workflow="$3"
    local state_file="$4"

    local resolution
    resolution=$(resolve_validation_results_file "$session_id" "$session_dir")
    local validation_file source
    validation_file=$(printf '%s' "$resolution" | cut -f1)
    source=$(printf '%s' "$resolution" | cut -f2)

    if [[ -z "$validation_file" ]]; then
        if [[ "$workflow" != "development" ]]; then
            build_check_json "validation" "skipped" \
                "Formal validation is not required for ${workflow} workflow sessions" \
                "{\"source\": null, \"validation_file\": null, \"overall\": null, \"timestamp\": null, \"can_publish\": null}"
            return
        fi

        local validate_recorded=false
        if [[ -f "$state_file" ]] && jq -e '.step_history[]? | select(.step == "validate")' "$state_file" >/dev/null 2>&1; then
            validate_recorded=true
        fi

        local details_json
        details_json=$(jq -n \
            --argjson validate_recorded "$validate_recorded" \
            '{source: null, validation_file: null, overall: null, timestamp: null, can_publish: null, validate_recorded: $validate_recorded}')

        if [[ "$validate_recorded" == "true" ]]; then
            build_check_json "validation" "unavailable" \
                "Validation ran, but no validation-results.json is available for this session" \
                "$details_json"
        else
            build_check_json "validation" "unavailable" \
                "No validation results are available for this development session" \
                "$details_json"
        fi
        return
    fi

    local overall timestamp can_publish
    overall=$(jq -r '.overall // "unknown"' "$validation_file" 2>/dev/null || echo "unknown")
    timestamp=$(jq -r '.timestamp // ""' "$validation_file" 2>/dev/null || echo "")
    can_publish=$(jq -r '.can_publish // false' "$validation_file" 2>/dev/null || echo "false")

    local details_json
    details_json=$(jq -n \
        --arg source "$source" \
        --arg validation_file "$validation_file" \
        --arg overall "$overall" \
        --arg timestamp "$timestamp" \
        --arg can_publish "$can_publish" \
        --argjson checks "$(jq '.validation_checks // []' "$validation_file" 2>/dev/null || echo '[]')" \
        '{
            source: $source,
            validation_file: $validation_file,
            overall: $overall,
            timestamp: (if $timestamp == "" then null else $timestamp end),
            can_publish: ($can_publish == "true"),
            checks: $checks
        }')

    case "$overall" in
        pass)
            build_check_json "validation" "pass" \
                "Validation results are present and passing" \
                "$details_json"
            ;;
        fail)
            if [[ "$workflow" == "development" ]]; then
                build_check_json "validation" "fail" \
                    "Validation results are present and failing" \
                    "$details_json"
            else
                build_check_json "validation" "warning" \
                    "Optional validation results are present and failing" \
                    "$details_json"
            fi
            ;;
        *)
            build_check_json "validation" "warning" \
                "Validation results are present, but the overall status is unclear" \
                "$details_json"
            ;;
    esac
}

audit_handoff() {
    local notes_file="$1"
    local next_file="$2"
    local session_completed="$3"

    local next_ready=false
    local notes_ready=false
    if [[ -f "$next_file" ]] && next_file_has_content "$next_file"; then
        next_ready=true
    fi
    if notes_handoff_has_content "$notes_file"; then
        notes_ready=true
    fi

    local details_json
    details_json=$(jq -n \
        --arg notes_file "$notes_file" \
        --arg next_file "$next_file" \
        --argjson next_ready "$next_ready" \
        --argjson notes_ready "$notes_ready" \
        '{
            notes_file: $notes_file,
            next_file: $next_file,
            next_ready: $next_ready,
            notes_ready: $notes_ready
        }')

    if [[ "$next_ready" == "true" ]]; then
        build_check_json "handoff" "pass" \
            "Structured next.md handoff content is present" \
            "$details_json"
    elif [[ "$notes_ready" == "true" ]]; then
        build_check_json "handoff" "warning" \
            "Only the legacy notes.md handoff section is populated" \
            "$details_json"
    elif [[ "$session_completed" == "true" ]]; then
        build_check_json "handoff" "fail" \
            "No actionable handoff content is present for a completed session" \
            "$details_json"
    else
        build_check_json "handoff" "warning" \
            "No actionable handoff content is present yet" \
            "$details_json"
    fi
}

audit_efficiency() {
    local state_file="$1"

    if [[ ! -f "$state_file" ]]; then
        build_check_json "efficiency" "unavailable" \
            "No local state.json available; timing metrics are unavailable" \
            '{"state_file": null, "recorded_steps": 0, "total_duration_seconds": null, "longest_step": null, "longest_step_duration_seconds": null, "durations": []}'
        return
    fi

    local durations_json
    durations_json=$(jq '[.step_history[]? | select(.started_at != null and .ended_at != null) | {
        step,
        duration_seconds: ((.ended_at | fromdateiso8601) - (.started_at | fromdateiso8601)),
        forced: (.forced // false)
    }]' "$state_file" 2>/dev/null || echo '[]')

    local recorded_steps
    recorded_steps=$(echo "$durations_json" | jq 'length')
    if [[ "$recorded_steps" -eq 0 ]]; then
        build_check_json "efficiency" "unavailable" \
            "No completed step durations are available in state.json" \
            "{\"state_file\": \"${state_file}\", \"recorded_steps\": 0, \"total_duration_seconds\": null, \"longest_step\": null, \"longest_step_duration_seconds\": null, \"durations\": []}"
        return
    fi

    local total_duration longest_step longest_step_duration
    total_duration=$(echo "$durations_json" | jq '[.[].duration_seconds] | add // 0')
    longest_step=$(echo "$durations_json" | jq -r 'max_by(.duration_seconds).step')
    longest_step_duration=$(echo "$durations_json" | jq 'max_by(.duration_seconds).duration_seconds')

    local details_json
    details_json=$(jq -n \
        --arg state_file "$state_file" \
        --arg longest_step "$longest_step" \
        --argjson recorded_steps "$recorded_steps" \
        --argjson total_duration_seconds "$total_duration" \
        --argjson longest_step_duration_seconds "$longest_step_duration" \
        --argjson durations "$durations_json" \
        '{
            state_file: $state_file,
            recorded_steps: $recorded_steps,
            total_duration_seconds: $total_duration_seconds,
            longest_step: $longest_step,
            longest_step_duration_seconds: $longest_step_duration_seconds,
            durations: $durations
        }')

    build_check_json "efficiency" "info" \
        "Timing metrics are available for completed workflow steps" \
        "$details_json"
}

audit_session() {
    local session_dir="$1"
    local session_id
    session_id=$(basename "$session_dir")

    local info_file="${session_dir}/session-info.json"
    local state_file="${session_dir}/state.json"
    local notes_file="${session_dir}/notes.md"
    local next_file="${session_dir}/next.md"

    local workflow="unknown"
    local session_type="unknown"
    local stage="unknown"
    local read_only=false
    local created_at=""

    if [[ -f "$info_file" ]]; then
        validate_schema_version "$info_file" "$SESSION_INFO_SCHEMA_VERSION"
        workflow=$(jq -r '.workflow // "unknown"' "$info_file" 2>/dev/null || echo "unknown")
        session_type=$(jq -r '.type // "unknown"' "$info_file" 2>/dev/null || echo "unknown")
        stage=$(jq -r '.stage // "unknown"' "$info_file" 2>/dev/null || echo "unknown")
        read_only=$(jq -r '.read_only // false' "$info_file" 2>/dev/null || echo "false")
        created_at=$(jq -r '.created_at // ""' "$info_file" 2>/dev/null || echo "")
    fi

    local tasks_file
    tasks_file=$(resolve_tasks_file "$session_id" 2>/dev/null || true)
    if [[ -z "$tasks_file" ]]; then
        tasks_file="${session_dir}/tasks.md"
    fi

    local spec_file
    spec_file=$(resolve_spec_file "$session_id" 2>/dev/null || true)
    if [[ -z "$spec_file" ]]; then
        spec_file="${session_dir}/spec.md"
    fi

    local session_completed=false
    local observed_steps=""
    if [[ -f "$state_file" ]]; then
        validate_schema_version "$state_file" "$STATE_SCHEMA_VERSION"
        observed_steps=$(jq -r '.step_history[]?.step' "$state_file" 2>/dev/null || true)
        local state_status state_ended_at
        state_status=$(jq -r '.status // "unknown"' "$state_file" 2>/dev/null || echo "unknown")
        state_ended_at=$(jq -r '.ended_at // ""' "$state_file" 2>/dev/null || echo "")
        if [[ "$state_status" == "completed" || -n "$state_ended_at" ]]; then
            session_completed=true
        fi
    fi

    local observed_unique=""
    if [[ -n "$observed_steps" ]]; then
        observed_unique=$(printf '%s\n' "$observed_steps" | awk 'NF && !seen[$0]++')
    fi

    local adherence_check
    adherence_check=$(audit_workflow_adherence "$workflow" "$state_file" "$session_completed")
    local artifact_check
    artifact_check=$(audit_artifact_completeness "$session_dir" "$workflow" "$tasks_file" "$spec_file" "$session_completed" "$observed_unique")
    local task_check
    task_check=$(audit_task_completion "$tasks_file" "$session_completed")
    local validation_check
    validation_check=$(audit_validation_results "$session_id" "$session_dir" "$workflow" "$state_file")
    local handoff_check
    handoff_check=$(audit_handoff "$notes_file" "$next_file" "$session_completed")
    local efficiency_check
    efficiency_check=$(audit_efficiency "$state_file")

    local checks_json
    checks_json=$(build_checks_json \
        "$adherence_check" \
        "$artifact_check" \
        "$task_check" \
        "$validation_check" \
        "$handoff_check" \
        "$efficiency_check")

    local overall_status
    overall_status=$(echo "$checks_json" | jq -r '
        if any(.[]; (.check != "efficiency") and .status == "fail") then "fail"
        elif any(.[]; (.check != "efficiency") and (.status == "warning" or .status == "unavailable")) then "warning"
        else "pass"
        end')

    local validation_resolution
    validation_resolution=$(resolve_validation_results_file "$session_id" "$session_dir")
    local validation_file validation_source
    validation_file=$(printf '%s' "$validation_resolution" | cut -f1)
    validation_source=$(printf '%s' "$validation_resolution" | cut -f2)

    jq -n \
        --arg id "$session_id" \
        --arg dir "$session_dir" \
        --arg workflow "$workflow" \
        --arg type "$session_type" \
        --arg stage "$stage" \
        --arg created_at "$created_at" \
        --arg overall_status "$overall_status" \
        --argjson read_only "$read_only" \
        --argjson session_completed "$session_completed" \
        --argjson checks "$checks_json" \
        --arg info_file "$info_file" \
        --arg state_file "$state_file" \
        --arg tasks_file "$tasks_file" \
        --arg spec_file "$spec_file" \
        --arg validation_file "$validation_file" \
        --arg validation_source "$validation_source" \
        '{
            id: $id,
            dir: $dir,
            workflow: $workflow,
            type: $type,
            stage: $stage,
            created_at: (if $created_at == "" then null else $created_at end),
            read_only: $read_only,
            session_completed: $session_completed,
            overall_status: $overall_status,
            inputs: {
                info_file: (if ($info_file | length) == 0 or ($info_file | startswith("/")) then $info_file else $info_file end),
                state_file: (if $state_file == "" or $state_file == "null" or ($state_file | startswith("/")) then (if $state_file == "" then null else $state_file end) else $state_file end),
                tasks_file: (if $tasks_file == "" then null else $tasks_file end),
                spec_file: (if $spec_file == "" then null else $spec_file end),
                validation_file: (if $validation_file == "" then null else $validation_file end),
                validation_source: (if $validation_source == "" or $validation_source == "missing" then null else $validation_source end)
            },
            checks: $checks
        }'
}

build_summary_json() {
    local sessions_json="$1"

    local overall_json
    overall_json=$(echo "$sessions_json" | jq '{
        pass: (map(select(.overall_status == "pass")) | length),
        warning: (map(select(.overall_status == "warning")) | length),
        fail: (map(select(.overall_status == "fail")) | length)
    }')

    local workflows_json
    workflows_json=$(echo "$sessions_json" | jq 'reduce .[] as $session ({}; .[$session.workflow] = (.[$session.workflow] // 0) + 1)')

    local tasks_json
    tasks_json=$(echo "$sessions_json" | jq '{
        total: ([.[].checks[] | select(.check == "task_completion") | .details.total // 0] | add // 0),
        completed: ([.[].checks[] | select(.check == "task_completion") | .details.completed // 0] | add // 0),
        incomplete: ([.[].checks[] | select(.check == "task_completion") | .details.incomplete // 0] | add // 0),
        skipped: ([.[].checks[] | select(.check == "task_completion") | .details.skipped // 0] | add // 0)
    }')

    local adherence_json validation_json artifacts_json handoff_json efficiency_json
    adherence_json=$(echo "$sessions_json" | jq '{
        pass: ([.[].checks[] | select(.check == "workflow_adherence" and .status == "pass")] | length),
        warning: ([.[].checks[] | select(.check == "workflow_adherence" and .status == "warning")] | length),
        fail: ([.[].checks[] | select(.check == "workflow_adherence" and .status == "fail")] | length),
        unavailable: ([.[].checks[] | select(.check == "workflow_adherence" and .status == "unavailable")] | length)
    }')
    validation_json=$(echo "$sessions_json" | jq '{
        pass: ([.[].checks[] | select(.check == "validation" and .status == "pass")] | length),
        warning: ([.[].checks[] | select(.check == "validation" and .status == "warning")] | length),
        fail: ([.[].checks[] | select(.check == "validation" and .status == "fail")] | length),
        unavailable: ([.[].checks[] | select(.check == "validation" and .status == "unavailable")] | length),
        skipped: ([.[].checks[] | select(.check == "validation" and .status == "skipped")] | length)
    }')
    artifacts_json=$(echo "$sessions_json" | jq '{
        pass: ([.[].checks[] | select(.check == "artifact_completeness" and .status == "pass")] | length),
        warning: ([.[].checks[] | select(.check == "artifact_completeness" and .status == "warning")] | length),
        fail: ([.[].checks[] | select(.check == "artifact_completeness" and .status == "fail")] | length)
    }')
    handoff_json=$(echo "$sessions_json" | jq '{
        pass: ([.[].checks[] | select(.check == "handoff" and .status == "pass")] | length),
        warning: ([.[].checks[] | select(.check == "handoff" and .status == "warning")] | length),
        fail: ([.[].checks[] | select(.check == "handoff" and .status == "fail")] | length)
    }')
    efficiency_json=$(echo "$sessions_json" | jq '{
        info: ([.[].checks[] | select(.check == "efficiency" and .status == "info")] | length),
        unavailable: ([.[].checks[] | select(.check == "efficiency" and .status == "unavailable")] | length)
    }')

    jq -n \
        --argjson total_sessions "$(echo "$sessions_json" | jq 'length')" \
        --argjson overall "$overall_json" \
        --argjson workflows "$workflows_json" \
        --argjson tasks "$tasks_json" \
        --argjson workflow_adherence "$adherence_json" \
        --argjson artifact_completeness "$artifacts_json" \
        --argjson validation "$validation_json" \
        --argjson handoff "$handoff_json" \
        --argjson efficiency "$efficiency_json" \
        '{
            total_sessions: $total_sessions,
            overall: $overall,
            workflows: $workflows,
            tasks: $tasks,
            checks: {
                workflow_adherence: $workflow_adherence,
                artifact_completeness: $artifact_completeness,
                validation: $validation,
                handoff: $handoff,
                efficiency: $efficiency
            }
        }'
}

status_marker() {
    case "$1" in
        pass) echo "✓" ;;
        warning) echo "⚠" ;;
        fail) echo "✗" ;;
        unavailable) echo "○" ;;
        skipped) echo "○" ;;
        info) echo "ℹ" ;;
        *) echo "-" ;;
    esac
}

output_json_result() {
    local status="$1"
    local message="$2"
    local sessions_json="$3"
    local summary_json="$4"

    jq -n \
        --arg status "$status" \
        --arg message "$message" \
        --arg selection_mode "$SELECTION_MODE" \
        --arg session_filter "$SESSION_FILTER" \
        --arg workflow_filter "$WORKFLOW_FILTER" \
        --arg since_filter "$SINCE_FILTER" \
        --argjson all "$ALL" \
        --argjson summary_only "$SUMMARY_ONLY" \
        --argjson sessions "$sessions_json" \
        --argjson summary "$summary_json" \
        '{
            status: $status,
            message: $message,
            selection: {
                mode: $selection_mode,
                session: (if $session_filter == "" then null else $session_filter end),
                all: $all,
                workflow: (if $workflow_filter == "" then null else $workflow_filter end),
                since: (if $since_filter == "" then null else $since_filter end),
                summary_only: $summary_only
            },
            summary: $summary,
            sessions: $sessions
        }'
}

output_human_result() {
    local sessions_json="$1"
    local summary_json="$2"

    echo ""
    echo "Session audit"
    echo "============================================"
    echo "Selection: ${SELECTION_MODE}"
    echo "Sessions audited: $(echo "$summary_json" | jq -r '.total_sessions')"
    echo "Overall: pass $(echo "$summary_json" | jq -r '.overall.pass'), warning $(echo "$summary_json" | jq -r '.overall.warning'), fail $(echo "$summary_json" | jq -r '.overall.fail')"

    local workflows_line
    workflows_line=$(echo "$summary_json" | jq -r '.workflows | to_entries | map("\(.key)=\(.value)") | join(", ")')
    if [[ -n "$workflows_line" ]]; then
        echo "Workflows: ${workflows_line}"
    fi

    if $SUMMARY_ONLY; then
        echo ""
        return
    fi

    local session_count
    session_count=$(echo "$sessions_json" | jq 'length')
    if [[ "$session_count" -eq 1 ]]; then
        local session_json
        session_json=$(echo "$sessions_json" | jq '.[0]')

        echo ""
        echo "$(echo "$session_json" | jq -r '.id') [$(echo "$session_json" | jq -r '.workflow')] — $(echo "$session_json" | jq -r '.overall_status')"
        echo "Dir: $(echo "$session_json" | jq -r '.dir')"
        echo "Completed: $(echo "$session_json" | jq -r '.session_completed')"

        while IFS=$'\t' read -r check_status check_name check_message; do
            [[ -n "$check_name" ]] || continue
            printf "  %s %s: %s\n" "$(status_marker "$check_status")" "$check_name" "$check_message"
        done < <(echo "$session_json" | jq -r '.checks[] | [.status, .check, .message] | @tsv')
    else
        echo ""
        while IFS=$'\t' read -r session_id workflow overall_status check_summary; do
            [[ -n "$session_id" ]] || continue
            printf "  %s [%s] %s\n" "$session_id" "$workflow" "$overall_status"
            printf "    %s\n" "$check_summary"
        done < <(echo "$sessions_json" | jq -r '
            .[] | [
                .id,
                .workflow,
                .overall_status,
                (.checks | map("\( .check )=\( .status )") | join(", "))
            ] | @tsv')
    fi

    echo ""
}

main() {
    parse_args "$@"
    validate_args

    local selected_dirs
    selected_dirs=$(select_session_dirs)

    if [[ -z "$selected_dirs" ]]; then
        local empty_sessions='[]'
        local empty_summary
        empty_summary=$(jq -n '{
            total_sessions: 0,
            overall: {pass: 0, warning: 0, fail: 0},
            workflows: {},
            tasks: {total: 0, completed: 0, incomplete: 0, skipped: 0},
            checks: {
                workflow_adherence: {pass: 0, warning: 0, fail: 0, unavailable: 0},
                artifact_completeness: {pass: 0, warning: 0, fail: 0},
                validation: {pass: 0, warning: 0, fail: 0, unavailable: 0, skipped: 0},
                handoff: {pass: 0, warning: 0, fail: 0},
                efficiency: {info: 0, unavailable: 0}
            }
        }')
        if $JSON_OUTPUT; then
            output_json_result "warning" "No sessions matched the requested selection" "$empty_sessions" "$empty_summary"
        else
            print_warning "No sessions matched the requested selection"
        fi
        return
    fi

    local tmp_file
    tmp_file=$(mktemp)
    local session_dir
    while IFS= read -r session_dir; do
        [[ -n "$session_dir" ]] || continue
        audit_session "$session_dir" >> "$tmp_file"
    done <<< "$selected_dirs"

    local sessions_json
    sessions_json=$(jq -s '.' "$tmp_file")
    rm -f "$tmp_file"

    local summary_json
    summary_json=$(build_summary_json "$sessions_json")

    if $JSON_OUTPUT; then
        output_json_result "ok" "Session audit complete" "$sessions_json" "$summary_json"
    else
        output_human_result "$sessions_json" "$summary_json"
    fi
}

main "$@"
