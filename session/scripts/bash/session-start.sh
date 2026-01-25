#!/usr/bin/env bash
# session-start.sh - Initialize or resume a session
# Part of Session Workflow Enhancement (#566)

set -euo pipefail

# Get script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/session-common.sh"

# ============================================================================
# Defaults
# ============================================================================

SESSION_TYPE=""
ISSUE_NUMBER=""
SPEC_DIR=""
GOAL=""
JSON_OUTPUT=false
WORKFLOW="development"  # Default workflow
STAGE="production"      # Default stage (strictest)
RESUME_MODE=false
COMMENT=""

# ============================================================================
# Usage
# ============================================================================

usage() {
    cat << EOF
Usage: session-start.sh [OPTIONS] [GOAL]

Initialize a new session or resume an active session.

OPTIONS:
    --issue NUMBER    GitHub issue number (starts github_issue session)
    --spec DIR        Spec directory name (starts speckit session)
    --spike           Spike workflow: exploration/research, no PR expected
    --stage STAGE     Project stage: poc, mvp, or production (default: production)
    --resume          Resume an active session (including interrupted)
    --comment "TEXT"  Additional instructions for the session
    --json            Output JSON for AI consumption
    -h, --help        Show this help

GOAL:
    Positional argument describing the work (for unstructured sessions).
    Not needed if --issue or --spec is provided.

WORKFLOWS:
    development (default) - Full chain: start → plan → execute → validate → publish → finalize → wrap
    spike (--spike)       - Light chain: start → execute → wrap (no PR)

STAGES:
    poc        - Proof of concept: relaxed validation, minimal docs required
    mvp        - Minimum viable product: standard validation, core docs required
    production - Production-ready (default): strict validation, full docs required

EXAMPLES:
    # GitHub issue (development workflow)
    session-start.sh --issue 123

    # Speckit feature (development workflow)
    session-start.sh --spec 001-feature

    # Unstructured work (development workflow)
    session-start.sh "Fix performance bug in API"

    # Spike/research (no PR expected)
    session-start.sh --spike "Explore Redis caching options"

    # PoC project with relaxed validation
    session-start.sh --stage poc "Prototype new auth flow"

    # Resume active session
    session-start.sh --resume

    # Resume with context
    session-start.sh --resume --comment "Continue from task 5"
EOF
}

# ============================================================================
# Argument Parsing
# ============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --issue)
                ISSUE_NUMBER="$2"
                SESSION_TYPE="github_issue"
                shift 2
                ;;
            --spec)
                SPEC_DIR="$2"
                SESSION_TYPE="speckit"
                shift 2
                ;;
            --spike)
                WORKFLOW="spike"
                shift
                ;;
            --stage)
                STAGE="$2"
                # Validate stage value
                if [[ ! "$STAGE" =~ ^(poc|mvp|production)$ ]]; then
                    echo "ERROR: Invalid stage '$STAGE'. Must be: poc, mvp, or production" >&2
                    exit 1
                fi
                shift 2
                ;;
            --resume)
                RESUME_MODE=true
                shift
                ;;
            --comment)
                COMMENT="$2"
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
            -*)
                echo "Unknown option: $1" >&2
                usage
                exit 1
                ;;
            *)
                # Positional argument = goal
                GOAL="$1"
                SESSION_TYPE="unstructured"
                shift
                ;;
        esac
    done
}

# ============================================================================
# Session Creation Functions
# ============================================================================

create_session_info() {
    local session_id="$1"
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    
    local info_file="${session_dir}/session-info.json"
    local created_at
    created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Workflow is either "development" (default) or "spike"
    local workflow="${WORKFLOW}"
    
    # Stage is "poc", "mvp", or "production" (default)
    local stage="${STAGE}"
    
    # Build JSON based on type
    case $SESSION_TYPE in
        speckit)
            cat > "$info_file" << SESSIONEOF
{
  "schema_version": "2.2",
  "session_id": "${session_id}",
  "type": "speckit",
  "workflow": "${workflow}",
  "stage": "${stage}",
  "created_at": "${created_at}",
  "spec_dir": "specs/${SPEC_DIR}"
}
SESSIONEOF
            ;;
        github_issue)
            local issue_title=""
            if command -v gh &> /dev/null && [[ -n "$ISSUE_NUMBER" ]]; then
                issue_title=$(gh issue view "$ISSUE_NUMBER" --json title -q '.title' 2>/dev/null || echo "")
            fi
            cat > "$info_file" << SESSIONEOF
{
  "schema_version": "2.2",
  "session_id": "${session_id}",
  "type": "github_issue",
  "workflow": "${workflow}",
  "stage": "${stage}",
  "created_at": "${created_at}",
  "issue_number": ${ISSUE_NUMBER},
  "issue_title": "$(json_escape "$issue_title")"
}
SESSIONEOF
            ;;
        unstructured)
            cat > "$info_file" << SESSIONEOF
{
  "schema_version": "2.2",
  "session_id": "${session_id}",
  "type": "unstructured",
  "workflow": "${workflow}",
  "stage": "${stage}",
  "created_at": "${created_at}",
  "goal": "$(json_escape "$GOAL")"
}
SESSIONEOF
            ;;
    esac
}

create_session_state() {
    local session_id="$1"
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    
    local state_file="${session_dir}/state.json"
    local started_at
    started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local branch
    branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    
    local last_commit
    last_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    
    cat > "$state_file" << EOF
{
  "schema_version": "1.0",
  "session_id": "${session_id}",
  "status": "active",
  "started_at": "${started_at}",
  "ended_at": null,
  "tasks": {
    "total": 0,
    "completed": 0,
    "current": null
  },
  "git": {
    "branch": "${branch}",
    "last_commit": "${last_commit}"
  },
  "notes_summary": ""
}
EOF
}

create_session_notes() {
    local session_id="$1"
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    
    local notes_file="${session_dir}/notes.md"
    local template_file="${TEMPLATES_DIR}/session-notes.md"
    
    if [[ -f "$template_file" ]]; then
        sed "s/{SESSION_ID}/${session_id}/g" "$template_file" > "$notes_file"
    else
        # Create basic notes file
        cat > "$notes_file" << EOF
# Session Notes: ${session_id}

## Summary

## Key Decisions

## Blockers/Issues

## For Next Session
- Current state: 
- Next steps: 
- Context needed: 

## Technical Notes (optional)
EOF
    fi
}

create_session_tasks() {
    # Only for non-Speckit sessions
    local session_id="$1"
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    
    if [[ "$SESSION_TYPE" != "speckit" ]]; then
        local tasks_file="${session_dir}/tasks.md"
        local goal_text=""
        local issue_body=""
        
        case $SESSION_TYPE in
            github_issue)
                goal_text="GitHub Issue #${ISSUE_NUMBER}"
                # Fetch issue body for context
                if command -v gh &> /dev/null && [[ -n "$ISSUE_NUMBER" ]]; then
                    issue_body=$(gh issue view "$ISSUE_NUMBER" --json body -q '.body' 2>/dev/null || echo "")
                fi
                ;;
            unstructured)
                goal_text="${GOAL}"
                ;;
        esac
        
        cat > "$tasks_file" << EOF
# Session Tasks: ${session_id}

## Goal
${goal_text}
EOF

        # Add issue context if available
        if [[ -n "$issue_body" ]]; then
            cat >> "$tasks_file" << EOF

## Issue Context
${issue_body}
EOF
        fi

        cat >> "$tasks_file" << EOF

## Tasks
<!-- AI will generate tasks based on issue context -->

## Progress
- Started: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
- Status: 0/0 complete
EOF
    fi
}

# ============================================================================
# Output Functions
# ============================================================================

output_json() {
    local session_id="$1"
    local is_resume="$2"
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    
    # Get repo root (absolute path) - prevents agent hallucination
    local repo_root
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
    
    # Get previous session info
    local prev_session
    prev_session=$(get_previous_session)
    local prev_info=""
    
    if [[ -n "$prev_session" ]]; then
        local prev_notes
        prev_notes=$(get_for_next_session_section "$prev_session")
        prev_notes=$(json_escape "$prev_notes")
        
        # Get incomplete tasks from previous session
        local prev_session_dir
        prev_session_dir=$(get_session_dir "$prev_session")
        local prev_tasks_file="${prev_session_dir}/tasks.md"
        local incomplete_tasks=""
        if [[ -f "$prev_tasks_file" ]]; then
            incomplete_tasks=$(get_incomplete_tasks "$prev_tasks_file" | head -5)
            incomplete_tasks=$(json_escape "$incomplete_tasks")
        fi
        
        prev_info=$(cat << EOF
  "previous_session": {
    "id": "${prev_session}",
    "notes_file": "${prev_session_dir}/notes.md",
    "for_next_session": "${prev_notes}",
    "incomplete_tasks": "${incomplete_tasks}"
  },
EOF
)
    else
        prev_info='"previous_session": null,'
    fi
    
    # Get session info
    local session_info
    session_info=$(cat "${session_dir}/session-info.json" 2>/dev/null || echo "{}")
    
    # Get session type and stage
    local sess_type
    sess_type=$(echo "$session_info" | jq -r '.type // "unknown"')
    
    local sess_stage
    sess_stage=$(echo "$session_info" | jq -r '.stage // "production"')
    
    cat << EOF
{
  "status": "ok",
  "action": "$(if [[ "$is_resume" == "true" ]]; then echo "resumed"; else echo "created"; fi)",
  "resume_mode": $(if [[ "$RESUME_MODE" == "true" ]]; then echo "true"; else echo "false"; fi),
  "user_comment": "$(json_escape "$COMMENT")",
  "repo_root": "${repo_root}",
  "session": {
    "id": "${session_id}",
    "type": "${sess_type}",
    "stage": "${sess_stage}",
    "dir": "${session_dir}",
    "files": {
      "info": "${session_dir}/session-info.json",
      "state": "${session_dir}/state.json",
      "notes": "${session_dir}/notes.md"$(if [[ "$sess_type" != "speckit" ]]; then echo ",
      \"tasks\": \"${session_dir}/tasks.md\""; fi)
    }
  },
  ${prev_info}
  "project_context": {
    "constitution": ".session/project-context/constitution-summary.md",
    "technical": ".session/project-context/technical-context.md"
  },
  "stage_behavior": {
    "poc": {
      "constitution": "optional",
      "technical_context": "optional",
      "validation": "relaxed (warnings only)",
      "docs": "minimal"
    },
    "mvp": {
      "constitution": "required (can be brief)",
      "technical_context": "required (can be partial)",
      "validation": "standard",
      "docs": "core sections"
    },
    "production": {
      "constitution": "required (comprehensive)",
      "technical_context": "required (complete)",
      "validation": "strict",
      "docs": "full"
    }
  },
  "tips": {
    "before_starting": "Provide a brief summary of planned tasks before beginning work",
    "before_pushing": "Run project-specific lint and test commands (check technical-context.md)",
    "testing": {
      "check_context": "See .session/project-context/technical-context.md for commands",
      "tail_output": "<test-command> 2>&1 | tail -50",
      "filter_failures": "gh run view <id> --log-failed 2>&1 | grep -A 20 'FAIL'"
    },
    "git": {
      "branches": "ALWAYS work on feature branches, never directly on main",
      "pr_wait": "WAIT for CI checks before merging PRs",
      "skip_ci": "Use [skip ci] in commit message for docs-only changes"
    }
  },
  "instructions": [
    "Read project context files for quick orientation",
    $(if [[ -n "$prev_session" ]]; then echo "\"Review previous session notes for continuity\","; fi)
    $(if [[ "$RESUME_MODE" == "true" ]]; then echo "\"RESUME MODE: Continue from where agent left off, do not restart from beginning\","; fi)
    $(if [[ -n "$COMMENT" ]]; then echo "\"USER INSTRUCTION: ${COMMENT}\","; fi)
    "Update notes.md throughout the session",
    "Run '.session/scripts/bash/session-wrap.sh' at end of session"
  ]
}
EOF
}

output_human() {
    local session_id="$1"
    local is_resume="$2"
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    
    echo ""
    if [[ "$is_resume" == "true" ]]; then
        print_info "Resuming session: ${session_id}"
    else
        print_success "Created new session: ${session_id}"
    fi
    
    echo ""
    echo "Session Directory: ${session_dir}"
    echo ""
    echo "Files:"
    echo "  - session-info.json (session metadata)"
    echo "  - state.json (progress tracking)"
    echo "  - notes.md (handoff notes)"
    
    # Get session type
    local sess_type
    sess_type=$(jq -r '.type // "unknown"' "${session_dir}/session-info.json" 2>/dev/null || echo "unknown")
    
    if [[ "$sess_type" != "speckit" ]]; then
        echo "  - tasks.md (task checklist)"
    fi
    
    echo ""
    echo "Project Context:"
    echo "  - ${PROJECT_CONTEXT_DIR}/constitution-summary.md"
    echo "  - ${PROJECT_CONTEXT_DIR}/technical-context.md"
    
    # Show previous session info
    local prev_session
    prev_session=$(get_previous_session)
    if [[ -n "$prev_session" ]]; then
        echo ""
        print_info "Previous session: ${prev_session}"
        local prev_session_dir
        prev_session_dir=$(get_session_dir "$prev_session")
        echo "  Review: ${prev_session_dir}/notes.md"
    fi
    
    echo ""
    print_warning "Remember: Run '.session/scripts/bash/session-wrap.sh' at end of session!"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    parse_args "$@"
    
    # Ensure structure exists
    ensure_session_structure
    
    # Check prerequisites
    if ! check_prerequisites; then
        exit 1
    fi
    
    # Check for active session
    local active_session
    active_session=$(get_active_session)

    if [[ -n "$active_session" ]]; then
        local session_dir
        session_dir=$(get_session_dir "$active_session")

        if [[ ! -d "$session_dir" ]]; then
            if $JSON_OUTPUT; then
                echo "{\"status\": \"error\", \"message\": \"Active session directory not found: ${session_dir}\", \"hint\": \"Clear .session/ACTIVE_SESSION or start a new session\"}"
            else
                print_error "Active session directory not found: ${session_dir}"
                echo ""
                echo "To fix:"
                echo "  1. Clear:  rm .session/ACTIVE_SESSION"
                echo "  2. Start:  .session/scripts/bash/session-start.sh --issue XXX"
                echo ""
            fi
            exit 1
        fi

        if [[ -f "$session_dir/state.json" ]]; then
            local step_status
            step_status=$(jq -r '.step_status // "unknown"' "$session_dir/state.json" 2>/dev/null || echo "unknown")
            if [[ "$step_status" == "in_progress" || "$step_status" == "starting" ]]; then
                if $JSON_OUTPUT; then
                    output_json "$active_session" "true"
                else
                    output_human "$active_session" "true"
                fi
                exit 0
            fi
        fi

        if [[ "${RESUME_MODE:-false}" == "true" ]]; then
            if $JSON_OUTPUT; then
                output_json "$active_session" "true"
            else
                output_human "$active_session" "true"
            fi
            exit 0
        fi

        local session_date
        session_date=$(echo "$active_session" | cut -d'-' -f1,2,3)
        local today
        today=$(date +%Y-%m-%d)

        if [[ "$session_date" != "$today" ]]; then
            if $JSON_OUTPUT; then
                echo "{\"status\": \"error\", \"message\": \"Stale session detected: ${active_session} is from ${session_date} but today is ${today}\", \"hint\": \"Run: /session.start --resume (or rm .session/ACTIVE_SESSION for a new session)\"}"
            else
                print_error "Stale session detected!"
                echo ""
                echo "Active session: ${active_session}"
                echo "Session date:   ${session_date}"
                echo "Today:          ${today}"
                echo ""
                print_warning "The previous session was not properly closed."
                echo ""
                echo "To fix:"
                echo "  1. Resume:    .session/scripts/bash/session-start.sh --resume"
                echo "  2. Or clear:  rm .session/ACTIVE_SESSION"
                echo ""
            fi
            exit 1
        fi

        if $JSON_OUTPUT; then
            output_json "$active_session" "true"
        else
            output_human "$active_session" "true"
        fi
        exit 0
    fi
    
    # Creating new session - validate type
    if [[ -z "$SESSION_TYPE" ]]; then
        # Auto-detect type from arguments
        if [[ -n "$ISSUE_NUMBER" ]]; then
            SESSION_TYPE="github_issue"
        elif [[ -n "$SPEC_DIR" ]]; then
            SESSION_TYPE="speckit"
        elif [[ -n "$GOAL" ]]; then
            SESSION_TYPE="unstructured"
        else
            echo "ERROR: Must specify --issue, --spec, or a goal description" >&2
            usage
            exit 1
        fi
    fi
    
    # Validate required args for type
    case $SESSION_TYPE in
        speckit)
            if [[ -z "$SPEC_DIR" ]]; then
                echo "ERROR: --spec required for speckit type" >&2
                exit 1
            fi
            ;;
        github_issue)
            if [[ -z "$ISSUE_NUMBER" ]]; then
                echo "ERROR: --issue required for github_issue type" >&2
                exit 1
            fi
            ;;
        unstructured)
            if [[ -z "$GOAL" ]]; then
                echo "ERROR: Goal description required for unstructured type" >&2
                exit 1
            fi
            ;;
        *)
            echo "ERROR: Invalid type: $SESSION_TYPE" >&2
            exit 1
            ;;
    esac
    
    # Generate session ID (collision-safe)
    local session_id
    session_id=$(generate_session_id)
    
    # Validate session ID format (YYYY-MM-DD-N)
    if ! [[ "$session_id" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]+$ ]]; then
        if $JSON_OUTPUT; then
            echo "{\"status\": \"error\", \"message\": \"Invalid session ID format: ${session_id}. Expected YYYY-MM-DD-N\"}"
        else
            print_error "Invalid session ID format: ${session_id}"
            echo "Expected format: YYYY-MM-DD-N (e.g., 2025-12-20-1)"
        fi
        exit 1
    fi
    
    # Double-check: verify no collision with existing session
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    if [[ -d "$session_dir" ]]; then
        if $JSON_OUTPUT; then
            echo "{\"status\": \"error\", \"message\": \"Session collision detected: ${session_id} already exists\"}"
        else
            print_error "Session collision detected: ${session_id} already exists"
            echo "This shouldn't happen. Check .session/sessions/ for conflicts."
        fi
        exit 1
    fi
    
    # Validate session directory path format (must be .session/sessions/YYYY-MM/YYYY-MM-DD-N)
    if ! [[ "$session_dir" =~ \.session/sessions/[0-9]{4}-[0-9]{2}/[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]+$ ]]; then
        if $JSON_OUTPUT; then
            echo "{\"status\": \"error\", \"message\": \"Invalid session directory path: ${session_dir}\"}"
        else
            print_error "Invalid session directory path: ${session_dir}"
            echo "Expected format: .session/sessions/YYYY-MM/YYYY-MM-DD-N"
        fi
        exit 1
    fi
    
    # Create session directory
    mkdir -p "$session_dir"
    
    # Create session files
    create_session_info "$session_id"
    create_session_state "$session_id"
    create_session_notes "$session_id"
    create_session_tasks "$session_id"
    
    # Set as active session
    set_active_session "$session_id"
    
    # Output
    if $JSON_OUTPUT; then
        output_json "$session_id" "false"
    else
        output_human "$session_id" "false"
    fi
}

main "$@"
