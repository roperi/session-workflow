#!/usr/bin/env bash
# session-handoff-list.sh - List sessions with basic metadata

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/session-common.sh"

JSON_OUTPUT=false
LIMIT=20
ALL=false

usage() {
    cat << EOF
Usage: session-handoff-list.sh [OPTIONS]

List sessions (most recent first).

OPTIONS:
    --json         Output JSON
    --limit N      Limit number of sessions (default: 20)
    --all          No limit
    -h, --help     Show this help
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --limit)
                LIMIT="$2"
                shift 2
                ;;
            --all)
                ALL=true
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

list_session_dirs() {
    find "${SESSIONS_DIR}" -mindepth 2 -maxdepth 2 -type d -name "????-??-??-*" 2>/dev/null | sort -r
}

output_json() {
    if ! command -v jq >/dev/null 2>&1; then
        echo '{"status":"error","message":"jq is required for --json"}'
        exit 1
    fi

    local active_session
    active_session=$(get_active_session)

    local dirs
    dirs=$(list_session_dirs)

    if ! $ALL; then
        dirs=$(echo "$dirs" | head -n "$LIMIT")
    fi

    local tmp
    tmp=$(mktemp)

    while IFS= read -r d; do
        [[ -n "$d" ]] || continue
        local id
        id=$(basename "$d")

        local info_file state_file
        info_file="${d}/session-info.json"
        state_file="${d}/state.json"

        local type created_at parent
        type=$(jq -r '.type // "unknown"' "$info_file" 2>/dev/null || echo "unknown")
        created_at=$(jq -r '.created_at // ""' "$info_file" 2>/dev/null || echo "")
        parent=$(jq -r '.parent_session_id // ""' "$info_file" 2>/dev/null || echo "")

        local status ended_at branch last_commit tasks_total tasks_completed
        status=$(jq -r '.status // "unknown"' "$state_file" 2>/dev/null || echo "unknown")
        ended_at=$(jq -r '.ended_at // ""' "$state_file" 2>/dev/null || echo "")
        branch=$(jq -r '.git.branch // ""' "$state_file" 2>/dev/null || echo "")
        last_commit=$(jq -r '.git.last_commit // ""' "$state_file" 2>/dev/null || echo "")
        tasks_total=$(jq -r '.tasks.total // 0' "$state_file" 2>/dev/null || echo 0)
        tasks_completed=$(jq -r '.tasks.completed // 0' "$state_file" 2>/dev/null || echo 0)

        jq -n \
            --arg id "$id" \
            --arg dir "$d" \
            --arg type "$type" \
            --arg created_at "$created_at" \
            --arg parent_session_id "$parent" \
            --arg status "$status" \
            --arg ended_at "$ended_at" \
            --arg branch "$branch" \
            --arg last_commit "$last_commit" \
            --arg notes_file "${d}/notes.md" \
            --arg tasks_file "${d}/tasks.md" \
            --argjson tasks_total "$tasks_total" \
            --argjson tasks_completed "$tasks_completed" \
            '{
                id: $id,
                dir: $dir,
                type: $type,
                created_at: $created_at,
                parent_session_id: (if $parent_session_id == "" then null else $parent_session_id end),
                state: {
                    status: $status,
                    ended_at: (if $ended_at == "" then null else $ended_at end),
                    git: {branch: $branch, last_commit: $last_commit},
                    tasks: {total: $tasks_total, completed: $tasks_completed}
                },
                files: {notes: $notes_file, tasks: $tasks_file}
            }' >> "$tmp"
    done <<< "$dirs"

    local sessions_json
    sessions_json=$(jq -s '.' "$tmp")
    rm -f "$tmp"

    jq -n \
        --arg status "ok" \
        --arg active_session "$active_session" \
        --argjson sessions "$sessions_json" \
        '{status: $status, active_session: (if $active_session == "" then null else $active_session end), sessions: $sessions}'
}

output_human() {
    local active_session
    active_session=$(get_active_session)

    local dirs
    dirs=$(list_session_dirs)

    if ! $ALL; then
        dirs=$(echo "$dirs" | head -n "$LIMIT")
    fi

    echo ""
    echo "Sessions (most recent first)"
    echo "============================================"
    [[ -n "$active_session" ]] && echo "Active: $active_session" && echo ""

    while IFS= read -r d; do
        [[ -n "$d" ]] || continue
        local id
        id=$(basename "$d")

        local status type
        status=$(jq -r '.status // "unknown"' "${d}/state.json" 2>/dev/null || echo "unknown")
        type=$(jq -r '.type // "unknown"' "${d}/session-info.json" 2>/dev/null || echo "unknown")

        local marker=" "
        [[ "$id" == "$active_session" ]] && marker="*"
        printf "%s %s  [%s] (%s)\n" "$marker" "$id" "$status" "$type"
    done <<< "$dirs"

    echo ""
}

main() {
    parse_args "$@"
    ensure_session_structure

    if $JSON_OUTPUT; then
        output_json
    else
        output_human
    fi
}

main "$@"
