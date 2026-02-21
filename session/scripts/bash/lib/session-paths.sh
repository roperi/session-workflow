#!/usr/bin/env bash
# lib/session-paths.sh - Path constants, schema version constants, and session
# directory/ID functions.
#
# Requires: session-output.sh (for color variables used in set_active_session error path)
# Can be sourced after session-output.sh for unit testing.

# ============================================================================
# Constants
# ============================================================================

SESSION_ROOT=".session"
SESSIONS_DIR="${SESSION_ROOT}/sessions"
ACTIVE_SESSION_FILE="${SESSION_ROOT}/ACTIVE_SESSION"
PROJECT_CONTEXT_DIR="${SESSION_ROOT}/project-context"
TEMPLATES_DIR="${SESSION_ROOT}/templates"

# Schema version constants — keep in sync with session/docs/schema-versioning.md
SESSION_INFO_SCHEMA_VERSION="2.2"
STATE_SCHEMA_VERSION="1.0"

# ============================================================================
# Directory & Structure Functions
# ============================================================================

ensure_session_structure() {
    # Create session directory structure if it doesn't exist
    mkdir -p "${SESSIONS_DIR}"
    mkdir -p "${PROJECT_CONTEXT_DIR}"
    mkdir -p "${TEMPLATES_DIR}"
    mkdir -p "${SESSION_ROOT}/scripts/bash"
}

# ============================================================================
# Session ID Functions
# ============================================================================

generate_session_id() {
    # Generate session ID in format YYYY-MM-DD-N
    # Stored in .session/sessions/YYYY-MM/YYYY-MM-DD-N
    # Ensures no collision with existing sessions (active or completed)
    local today
    today=$(date +%Y-%m-%d)
    local year_month
    year_month=$(date +%Y-%m)
    
    # Create year-month directory if it doesn't exist
    mkdir -p "${SESSIONS_DIR}/${year_month}"
    
    # Find the highest session number for today
    local max_num=0
    if [[ -d "${SESSIONS_DIR}/${year_month}" ]]; then
        for dir in "${SESSIONS_DIR}/${year_month}/${today}-"*; do
            if [[ -d "$dir" ]]; then
                local num
                num=$(basename "$dir" | sed "s/${today}-//")
                if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -gt "$max_num" ]]; then
                    max_num="$num"
                fi
            fi
        done
    fi
    
    # Next session number (1-indexed, always increment from max)
    local next=$((max_num + 1))
    
    echo "${today}-${next}"
}

get_session_dir() {
    # Get full path to session directory for a given session ID
    # Args: session_id (YYYY-MM-DD-N format)
    # Returns: .session/sessions/YYYY-MM/YYYY-MM-DD-N
    local session_id="$1"
    
    # Extract year-month from session ID (YYYY-MM from YYYY-MM-DD-N)
    local year_month
    year_month=$(echo "$session_id" | cut -d'-' -f1,2)
    
    echo "${SESSIONS_DIR}/${year_month}/${session_id}"
}

get_active_session() {
    # Returns active session ID if exists, empty string otherwise
    if [[ -f "${ACTIVE_SESSION_FILE}" ]]; then
        cat "${ACTIVE_SESSION_FILE}"
    else
        echo ""
    fi
}

set_active_session() {
    local session_id="$1"
    # Write atomically (rename is atomic on the same filesystem)
    local tmp
    tmp=$(mktemp "${ACTIVE_SESSION_FILE}.XXXXXX")
    echo "$session_id" > "$tmp"
    mv "$tmp" "${ACTIVE_SESSION_FILE}"
}

clear_active_session() {
    rm -f "${ACTIVE_SESSION_FILE}"
}

# ============================================================================
# Previous Session Functions
# ============================================================================

get_previous_session() {
    # Get the most recent completed or active session ID (excluding the current active one)
    # Returns: session_id or empty string
    
    local active_session
    active_session=$(get_active_session)
    
    # Find all session directories, sorted by name (date order)
    local sessions=()
    local session_dir
    while IFS= read -r session_dir; do
        local session_id
        session_id=$(basename "$session_dir")
        # Skip the current active session
        if [[ "$session_id" != "$active_session" ]]; then
            sessions+=("$session_id")
        fi
    done < <(find "${SESSIONS_DIR}" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | sort)
    
    # Return the most recent one (last in sorted order)
    if [[ "${#sessions[@]}" -gt 0 ]]; then
        echo "${sessions[-1]}"
    else
        echo ""
    fi
}
