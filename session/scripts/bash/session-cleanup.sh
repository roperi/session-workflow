#!/usr/bin/env bash
# session-cleanup.sh - Remove errant files and directories from the .session/ tree
#
# Cleans up automatically (no prompts). Categories handled:
#   1. Unknown files/dirs at .session/ root (allowlist-based removal)
#   2. Session dirs misplaced directly under .session/sessions/ (moved to correct YYYY-MM/ sub-path)
#   3. Orphaned files directly under .session/sessions/ (removed)
#   4. Empty non-allowlisted dirs under .session/ (removed)

set -euo pipefail

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
Usage: session-cleanup.sh [OPTIONS]

Remove errant files and directories from the .session/ tree.

Automatically cleans (no prompts):
  - Unknown files/dirs at .session/ root
  - Session directories misplaced at sessions/ root (moved to sessions/YYYY-MM/)
  - Orphaned files directly under sessions/
  - Empty non-allowlisted directories under .session/

OPTIONS:
    --json      Output JSON summary for AI consumption
    --help      Show this help

EXIT CODES:
    0 - Success (cleaned or nothing to clean)
    1 - Error
EOF
}

# ============================================================================
# Constants
# ============================================================================

# Files and directories that are valid at .session/ root
SESSION_ROOT_ALLOWLIST=(
    "ACTIVE_SESSION"
    "validation-results.json"
    "docs"
    "scripts"
    "sessions"
    "templates"
    "project-context"
)

# Pattern: YYYY-MM-DD-N (a misplaced session ID)
SESSION_ID_PATTERN='^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]+$'

# ============================================================================
# Helpers
# ============================================================================

log_action() {
    if $JSON_OUTPUT; then
        echo "$*" >&2
    else
        print_warning "$*"
    fi
}

in_allowlist() {
    local name="$1"
    local entry
    for entry in "${SESSION_ROOT_ALLOWLIST[@]}"; do
        [[ "$entry" == "$name" ]] && return 0
    done
    return 1
}

# ============================================================================
# Cleanup functions
# ============================================================================

removed_count=0
moved_count=0

clean_session_root() {
    local root="$SESSION_ROOT"
    [[ -d "$root" ]] || return 0

    while IFS= read -r -d '' entry; do
        local name
        name="$(basename "$entry")"
        if ! in_allowlist "$name"; then
            log_action "Removing errant item from .session/ root: $name"
            rm -rf "$entry"
            (( removed_count++ )) || true
        fi
    done < <(find "$root" -maxdepth 1 -mindepth 1 -print0)
}

clean_sessions_root() {
    local sdir="$SESSIONS_DIR"
    [[ -d "$sdir" ]] || return 0

    while IFS= read -r -d '' entry; do
        local name
        name="$(basename "$entry")"

        # Skip .gitkeep
        [[ "$name" == ".gitkeep" ]] && continue

        if [[ -d "$entry" ]] && echo "$name" | grep -qE "$SESSION_ID_PATTERN"; then
            # Misplaced session dir — move to sessions/YYYY-MM/
            local year_month="${name:0:7}"
            local dest_dir="${sdir}/${year_month}"
            local dest="${dest_dir}/${name}"
            if [[ -d "$dest" ]]; then
                log_action "Misplaced session dir $name already exists at correct path; removing duplicate"
                rm -rf "$entry"
            else
                mkdir -p "$dest_dir"
                log_action "Moving misplaced session dir: sessions/$name → sessions/$year_month/$name"
                mv "$entry" "$dest"
                (( moved_count++ )) || true
            fi
        elif [[ -f "$entry" ]]; then
            # Orphaned file directly under sessions/
            log_action "Removing orphaned file from sessions/ root: $name"
            rm -f "$entry"
            (( removed_count++ )) || true
        fi
    done < <(find "$sdir" -maxdepth 1 -mindepth 1 -print0)
}

clean_empty_dirs() {
    local root="$SESSION_ROOT"
    [[ -d "$root" ]] || return 0

    # Find empty directories (depth ≥ 1, skip project-context which is user-owned)
    while IFS= read -r dir; do
        local rel="${dir#"$root"/}"
        local top="${rel%%/*}"
        # Never touch project-context
        [[ "$top" == "project-context" ]] && continue
        # Never touch sessions/ itself — only sub-dirs
        [[ "$dir" == "$SESSIONS_DIR" ]] && continue
        log_action "Removing empty directory: $dir"
        rmdir "$dir"
        (( removed_count++ )) || true
    done < <(find "$root" -mindepth 1 -type d -empty 2>/dev/null | sort -r)
}

# ============================================================================
# Main
# ============================================================================

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --json) JSON_OUTPUT=true; shift ;;
            --help) usage; exit 0 ;;
            *) print_error "Unknown option: $1"; usage; exit 1 ;;
        esac
    done

    # Must be run from repo root (where .session/ lives)
    if [[ ! -d "$SESSION_ROOT" ]]; then
        if $JSON_OUTPUT; then
            echo '{"status":"error","message":"No .session/ directory found. Run from repo root."}'
        else
            print_error "No .session/ directory found. Run from repo root."
        fi
        exit 1
    fi

    clean_session_root
    clean_sessions_root
    clean_empty_dirs

    local total=$(( removed_count + moved_count ))

    if $JSON_OUTPUT; then
        printf '{"status":"ok","removed":%d,"moved":%d,"total_actions":%d}\n' \
            "$removed_count" "$moved_count" "$total"
    else
        if [[ $total -eq 0 ]]; then
            print_success ".session/ is clean — nothing to remove"
        else
            print_success "Cleanup complete: $removed_count removed, $moved_count moved"
        fi
    fi
}

main "$@"
