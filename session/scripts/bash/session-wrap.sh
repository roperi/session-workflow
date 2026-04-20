#!/usr/bin/env bash
# session-wrap.sh - Finalize session and archive durable wrap artifacts
# Part of Session Workflow Enhancement (#566, simplified in #584)
#
# This script is mechanical, but it also creates the archival wrap commit for
# durable session artifacts while leaving volatile state.json bookkeeping local.
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

Finalize the current session and archive its durable wrap artifacts.

This script:
  1. Checks an active session exists
  2. Blocks if unrelated dirty git changes would be swept into the wrap commit
  3. Updates local state.json with completion timestamp
  4. Creates the archival wrap commit for session-history artifacts
  5. Clears ACTIVE_SESSION sentinel
  6. Outputs session summary

Validation (git clean, notes, tasks, changelog, etc.) is handled by the
session.wrap prompt, not this script. The script only auto-commits wrap-managed
paths such as durable session artifacts and CHANGELOG.md.
Volatile .session/sessions/**/state.json files are explicitly removed from the
archival commit.

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

get_wrap_tasks_file() {
    local session_id="$1"
    resolve_tasks_file "$session_id" 2>/dev/null || true
}

get_task_counts() {
    local session_id="$1"
    local tasks_file
    tasks_file=$(get_wrap_tasks_file "$session_id")

    if [[ -n "$tasks_file" && -f "$tasks_file" ]]; then
        count_tasks "$tasks_file"
    else
        echo "0:0"
    fi
}

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
        validate_schema_version "$state_file" "$STATE_SCHEMA_VERSION"
        current_step=$(jq -r '.current_step // "none"' "$state_file" 2>/dev/null || echo "none")
    fi
    if [[ "$current_step" == "none" ]]; then
        warnings+=("No workflow steps were tracked — session may have had no tracked work")
    fi

    # Check tasks completion
    local counts
    counts=$(get_task_counts "$session_id")
    local total completed
    total=$(echo "$counts" | cut -d: -f1)
    completed=$(echo "$counts" | cut -d: -f2)
    if [[ "$total" -gt 0 ]] && [[ "$completed" -lt "$total" ]]; then
        warnings+=("Tasks incomplete: ${completed}/${total} done")
    fi

    # Check next-session handoff content (prefer next.md, fall back to notes.md)
    if ! has_next_session_handoff_content "$session_id"; then
        warnings+=("next.md or notes.md missing next-session handoff content")
    fi

    # Return warnings (newline-separated)
    printf '%s\n' "${warnings[@]}"
}

list_dirty_paths() {
    local -A seen=()
    local entry status path other_path

    while IFS= read -r -d '' entry; do
        [[ -z "$entry" ]] && continue

        status="${entry:0:2}"
        path="${entry:3}"

        if [[ -n "$path" && -z "${seen[$path]+x}" ]]; then
            seen["$path"]=1
            printf '%s\n' "$path"
        fi

        if [[ "${status:0:1}" == "R" || "${status:0:1}" == "C" || "${status:1:1}" == "R" || "${status:1:1}" == "C" ]]; then
            IFS= read -r -d '' other_path || true
            if [[ -n "$other_path" && -z "${seen[$other_path]+x}" ]]; then
                seen["$other_path"]=1
                printf '%s\n' "$other_path"
            fi
        fi
    done < <(git status --porcelain=v1 -z --untracked-files=all)
}

is_wrap_managed_path() {
    local session_dir="${1#./}"
    local path="${3#./}"

    case "$path" in
        "${SESSIONS_DIR#./}"|"${SESSIONS_DIR#./}"/*)
            return 0
            ;;
        "$session_dir"|"$session_dir"/*)
            return 0
            ;;
        CHANGELOG.md)
            return 0
            ;;
        .session/ACTIVE_SESSION|.session/validation-results.json)
            return 0
            ;;
    esac

    return 1
}

find_non_wrap_dirty_paths() {
    local session_id="$1"
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    local path

    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        if ! is_wrap_managed_path "$session_dir" "" "$path"; then
            printf '%s\n' "$path"
        fi
    done < <(list_dirty_paths)
}

check_git_commit_identity() {
    git var GIT_AUTHOR_IDENT >/dev/null 2>&1 && git var GIT_COMMITTER_IDENT >/dev/null 2>&1
}

remove_volatile_state_from_index() {
    # state.json is mutable workflow bookkeeping and should remain local-only.
    local state_file

    [[ -d "$SESSIONS_DIR" ]] || return 0

    while IFS= read -r -d '' state_file; do
        git rm --cached --ignore-unmatch --quiet -- "$state_file" >/dev/null 2>&1 || true
    done < <(find "$SESSIONS_DIR" -type f -name state.json -print0 2>/dev/null)
}

# ============================================================================
# Update Functions
# ============================================================================

stage_wrap_artifacts() {
    local session_id="$1"
    local session_dir
    session_dir=$(get_session_dir "$session_id")

    if [[ -d "$SESSIONS_DIR" ]]; then
        git add -A -f -- "$SESSIONS_DIR"
    elif [[ -d "$session_dir" ]]; then
        git add -A -f -- "$session_dir"
    fi

    if [[ -e "CHANGELOG.md" ]] || git ls-files --error-unmatch "CHANGELOG.md" >/dev/null 2>&1; then
        git add -A -- "CHANGELOG.md"
    fi

    remove_volatile_state_from_index
}

commit_wrap_artifacts() {
    local session_id="$1"

    stage_wrap_artifacts "$session_id"

    if git diff --cached --quiet --exit-code; then
        return 0
    fi

    if ! git commit -m "docs: Session ${session_id} wrap-up [skip ci]" >/dev/null; then
        return 1
    fi
}

reset_wrap_artifacts_index() {
    local session_id="$1"
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    local tasks_file
    tasks_file=$(get_wrap_tasks_file "$session_id")
    local reset_paths=()

    if [[ -e "$SESSIONS_DIR" ]]; then
        reset_paths+=("$SESSIONS_DIR")
    elif [[ -e "$session_dir" ]]; then
        reset_paths+=("$session_dir")
    fi

    if [[ -n "$tasks_file" && "$tasks_file" != "${session_dir}/tasks.md" ]]; then
        if [[ -e "$tasks_file" ]] || git ls-files --error-unmatch "$tasks_file" >/dev/null 2>&1; then
            reset_paths+=("$tasks_file")
        fi
    fi

    if [[ -e "CHANGELOG.md" ]] || git ls-files --error-unmatch "CHANGELOG.md" >/dev/null 2>&1; then
        reset_paths+=("CHANGELOG.md")
    fi

    if [[ "${#reset_paths[@]}" -gt 0 ]]; then
        git reset --quiet -- "${reset_paths[@]}" >/dev/null 2>&1 || true
    fi
}

restore_wrap_state_on_failure() {
    local session_id="$1"
    local state_file="$2"
    local backup_file="$3"

    if [[ -f "$backup_file" ]]; then
        cp "$backup_file" "$state_file"
        rm -f "$backup_file"
    fi

    reset_wrap_artifacts_index "$session_id"
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
    local counts
    counts=$(get_task_counts "$session_id")
    local total completed
    total=$(echo "$counts" | cut -d: -f1)
    completed=$(echo "$counts" | cut -d: -f2)
    
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

lines_to_json_array() {
    local text="$1"

    if [[ -n "$text" ]]; then
        printf '%s\n' "$text" | jq -R -s 'split("\n") | map(select(length > 0))'
    else
        echo "[]"
    fi
}

output_json() {
    local session_id="$1"
    local warnings_text="$2"
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    
    # Get task counts for summary
    local counts
    counts=$(get_task_counts "$session_id")
    local total completed
    total=$(echo "$counts" | cut -d: -f1)
    completed=$(echo "$counts" | cut -d: -f2)
    
    # Format warnings as JSON array
    local warnings_json
    warnings_json=$(lines_to_json_array "$warnings_text")
    
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

output_wrap_blocked_json() {
    local dirty_paths_text="$1"
    local dirty_paths_json
    dirty_paths_json=$(lines_to_json_array "$dirty_paths_text")

    jq -n \
        --arg message "Wrap blocked: unrelated git changes would be swept into the archival wrap commit" \
        --arg hint "Commit, stash, or discard non-wrap changes before running session-wrap.sh" \
        --argjson dirty_paths "$dirty_paths_json" \
        '{status:"error", message:$message, hint:$hint, dirty_paths:$dirty_paths}'
}

output_wrap_blocked_human() {
    local dirty_paths_text="$1"

    print_error "Wrap blocked: unrelated git changes would be swept into the archival wrap commit"
    echo ""
    echo "Commit, stash, or discard non-wrap changes before running session-wrap.sh."
    echo "Non-wrap paths:"
    echo "$dirty_paths_text" | while read -r path; do
        if [[ -n "$path" ]]; then
            echo "  - $path"
        fi
    done
    echo ""
}

output_human() {
    local session_id="$1"
    local warnings_text="$2"
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    
    echo ""
    echo "Session Wrapped: ${session_id}"
    echo "============================================"
    echo ""
    echo "Session files preserved in: ${session_dir}"
    echo "Archival wrap commit created automatically for wrap-managed artifacts."
    
    # Display warnings if any
    if [[ -n "$warnings_text" ]]; then
        echo ""
        print_warning "Wrap completed with warnings:"
        echo "$warnings_text" | while read -r warning; do
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
    
    local non_wrap_dirty
    non_wrap_dirty=$(find_non_wrap_dirty_paths "$active_session")
    if [[ -n "$non_wrap_dirty" ]]; then
        if $JSON_OUTPUT; then
            output_wrap_blocked_json "$non_wrap_dirty"
        else
            output_wrap_blocked_human "$non_wrap_dirty"
        fi
        exit 1
    fi

    if ! check_git_commit_identity; then
        if $JSON_OUTPUT; then
            json_error_msg \
                "Git identity is required for wrap archival commits" \
                "Set git user.name and user.email (or the corresponding GIT_* identity env vars) before running session-wrap.sh"
        else
            print_error "Git identity is required for wrap archival commits"
            echo "Set git user.name and user.email (or the corresponding GIT_* identity env vars) before running session-wrap.sh."
        fi
        exit 1
    fi

    # Check session readiness (non-blocking warnings)
    local warnings
    warnings=$(check_session_readiness "$active_session")
    
    # Mark workflow step completed, update state, archive wrap artifacts, and clear sentinel
    # Ensure wrap is tracked in step_history (handles direct calls without preflight)
    local session_dir
    session_dir=$(get_session_dir "$active_session")
    local state_file="${session_dir}/state.json"
    local state_backup
    state_backup=$(mktemp)
    cp "$state_file" "$state_backup"
    local current_step_status
    current_step_status=$(jq -r '.step_status // "none"' "$state_file" 2>/dev/null || echo "none")
    local current_step
    current_step=$(jq -r '.current_step // "none"' "$state_file" 2>/dev/null || echo "none")
    if [[ "$current_step" != "wrap" || "$current_step_status" != "in_progress" ]]; then
        set_workflow_step "$active_session" "wrap" "in_progress" >/dev/null
    fi
    set_workflow_step "$active_session" "wrap" "completed" >/dev/null
    update_session_state "$active_session"
    if ! commit_wrap_artifacts "$active_session"; then
        restore_wrap_state_on_failure "$active_session" "$state_file" "$state_backup"
        if $JSON_OUTPUT; then
            json_error_msg \
                "Failed to create archival wrap commit" \
                "Resolve the git commit error, then rerun session-wrap.sh before clearing the active session"
        else
            print_error "Failed to create archival wrap commit"
            echo "Resolve the git commit error, then rerun session-wrap.sh before clearing the active session."
        fi
        exit 1
    fi
    rm -f "$state_backup"
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
