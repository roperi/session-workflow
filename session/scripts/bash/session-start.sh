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
CONTINUES_FROM=""
GIT_CONTEXT=false
READ_ONLY=false
BRAINSTORM_MODE=false
AUTO_MODE=false
COPILOT_REVIEW=false

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
    --maintenance     Maintenance workflow: small tasks, docs, housekeeping (no branch/PR)
    --debug           Debug workflow: troubleshooting/investigation, no PR by default
    --operational     Operational workflow: iterative pipeline/batch runs with patching between passes
    --read-only       Audit/read-only mode: no commits or file changes (use with --maintenance)
    --brainstorm      Insert optional brainstorm step before planning (development/spike only)
    --stage STAGE     Project stage: poc, mvp, or production (default: production)
    --resume                   Resume an active session (including interrupted)
    --comment "TEXT"           Additional instructions for the session
    --continues-from SESSION_ID New session continues from a previous session
    --git-context              Append a Git Context scaffold block to notes.md (or set SESSION_GIT_CONTEXT=1)
    --auto                     Accept orchestration auto-chain flag (handled by session.start agent)
    --copilot-review           Accept orchestration review flag (handled by session.start agent)
    --json                     Output JSON for AI consumption
    -h, --help        Show this help

GOAL:
    Positional argument describing the work (for unstructured sessions).
    Not needed if --issue or --spec is provided.

WORKFLOWS:
    development (default) - Full chain: start → [brainstorm] → scope → spec → plan → task → execute → validate → publish → [review] → finalize → wrap
    spike (--spike)       - Light chain: start → [brainstorm] → scope → plan → task → execute → wrap (no PR)
    maintenance           - Lightweight chain: start → execute → STOP by default; --auto adds wrap (no branch, no PR)
    debug (--debug)       - Investigation chain: start → execute → STOP by default; --auto adds wrap (no PR required)
    operational (--operational) - Runtime loop: start → execute → STOP by default; --auto adds wrap (feature branch, no PR by default)

MODIFIERS:
    --read-only           No commits or file modifications; produce report only (use with --maintenance)

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

    # Development with optional brainstorm before scoping/planning
    session-start.sh --brainstorm "Compare caching approaches"

    # Spike/research (no PR expected)
    session-start.sh --spike "Explore Redis caching options"

    # Debug/troubleshoot (no PR required; stops after execute by default)
    session-start.sh --debug "Trace why background jobs stall"

    # Operational batch/pipeline loop (feature branch, no PR by default)
    session-start.sh --operational "Process webpage mp3 files in batches"

    # Maintenance: small change, no branch or PR; stops after execute by default
    session-start.sh --maintenance "Reorder docs/ and update TOC"

    # Audit: read-only, no commits; stops after execute by default
    session-start.sh --maintenance --read-only "Find stale files in src/"

    # Maintenance with explicit auto-closeout
    session-start.sh --maintenance --auto "Reorder docs/ and update TOC"

    # PoC project with relaxed validation
    session-start.sh --stage poc "Prototype new auth flow"

    # Resume active session
    session-start.sh --resume

    # Resume with context
    session-start.sh --resume --comment "Continue from task 5"

    # Agent/orchestrator compatibility flags (accepted during initialization)
    session-start.sh --auto --issue 123                  # auto through publish, then stop for manual/custom review
    session-start.sh --auto --copilot-review --issue 123 # full auto with Copilot review
    session-start.sh --brainstorm --issue 123            # insert brainstorm before normal planning
EOF
}

# ============================================================================
# Argument Parsing
# ============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --issue)
                [[ $# -lt 2 || "$2" == -* ]] && { echo "ERROR: Missing value for --issue" >&2; exit 1; }
                ISSUE_NUMBER="$2"
                SESSION_TYPE="github_issue"
                shift 2
                ;;
            --spec)
                [[ $# -lt 2 || "$2" == -* ]] && { echo "ERROR: Missing value for --spec" >&2; exit 1; }
                SPEC_DIR="$2"
                SESSION_TYPE="speckit"
                shift 2
                ;;
            --spike)
                WORKFLOW="spike"
                shift
                ;;
            --maintenance)
                WORKFLOW="maintenance"
                shift
                ;;
            --debug)
                WORKFLOW="debug"
                shift
                ;;
            --operational)
                WORKFLOW="operational"
                shift
                ;;
            --read-only)
                READ_ONLY=true
                shift
                ;;
            --brainstorm)
                BRAINSTORM_MODE=true
                shift
                ;;
            --stage)
                [[ $# -lt 2 || "$2" == -* ]] && { echo "ERROR: Missing value for --stage" >&2; exit 1; }
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
                [[ $# -lt 2 || "$2" == -* ]] && { echo "ERROR: Missing value for --comment" >&2; exit 1; }
                COMMENT="$2"
                shift 2
                ;;
            --continues-from)
                CONTINUES_FROM="${2:-}"
                if [[ -z "${CONTINUES_FROM}" ]] || [[ "${CONTINUES_FROM}" == -* ]] || [[ ! "${CONTINUES_FROM}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]+$ ]]; then
                    echo "ERROR: Invalid session ID for --continues-from: '${CONTINUES_FROM}' (expected YYYY-MM-DD-N)" >&2
                    exit 1
                fi
                shift 2
                ;;
            --git-context)
                GIT_CONTEXT=true
                shift
                ;;
            --auto)
                AUTO_MODE=true
                shift
                ;;
            --copilot-review)
                COPILOT_REVIEW=true
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
    # Writes session-info.json for the given session.
    # To add a new session type: add a branch to the case block below
    # that writes the type-specific JSON fields, and add the type to
    # resolve_tasks_file() in session-common.sh if it needs a custom task path.
    # See session/docs/schema-versioning.md for the full field reference.
    local session_id="$1"
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    
    local info_file="${session_dir}/session-info.json"
    local created_at
    created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Workflow is either "development" (default), "spike", "maintenance",
    # "debug", or "operational"
    local workflow="${WORKFLOW}"
    
    # Stage is "poc", "mvp", or "production" (default)
    local stage="${STAGE}"

    # read_only is only meaningful for maintenance workflow
    local read_only_json=""
    if [[ "$READ_ONLY" == "true" ]]; then
        read_only_json=$',\n  "read_only": true'
    fi

    local parent_json=""
    if [[ -n "$CONTINUES_FROM" ]]; then
        parent_json=$',\n  "parent_session_id": "'"${CONTINUES_FROM}"'"'
    fi

    # Write atomically via tmp file in same directory (rename is atomic on
    # same filesystem; avoids partial reads if process is interrupted mid-write).
    local tmp_info
    tmp_info=$(mktemp "${info_file}.XXXXXX")

    # Build JSON based on type
    case $SESSION_TYPE in
        speckit)
            cat > "$tmp_info" << SESSIONEOF
{
  "schema_version": "2.2",
  "session_id": "${session_id}",
  "type": "speckit",
  "workflow": "${workflow}",
  "stage": "${stage}",
  "created_at": "${created_at}",
  "spec_dir": "specs/${SPEC_DIR}"${parent_json}${read_only_json}
}
SESSIONEOF
            ;;
        github_issue)
            local issue_title=""
            if command -v gh &> /dev/null && [[ -n "$ISSUE_NUMBER" ]]; then
                issue_title=$(gh issue view "$ISSUE_NUMBER" --json title -q '.title' 2>/dev/null || echo "")
            fi
            cat > "$tmp_info" << SESSIONEOF
{
  "schema_version": "2.2",
  "session_id": "${session_id}",
  "type": "github_issue",
  "workflow": "${workflow}",
  "stage": "${stage}",
  "created_at": "${created_at}",
  "issue_number": ${ISSUE_NUMBER},
  "issue_title": "$(json_escape "$issue_title")"${parent_json}${read_only_json}
}
SESSIONEOF
            ;;
        unstructured)
            cat > "$tmp_info" << SESSIONEOF
{
  "schema_version": "2.2",
  "session_id": "${session_id}",
  "type": "unstructured",
  "workflow": "${workflow}",
  "stage": "${stage}",
  "created_at": "${created_at}",
  "goal": "$(json_escape "$GOAL")"${parent_json}${read_only_json}
}
SESSIONEOF
            ;;
    esac

    mv "$tmp_info" "$info_file"
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
    
    local tmp_state
    tmp_state=$(mktemp "${state_file}.XXXXXX")
    cat > "$tmp_state" << EOF
{
  "schema_version": "${STATE_SCHEMA_VERSION}",
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
  "notes_summary": "",
  "step_history": [
    {
      "step": "start",
      "status": "completed",
      "started_at": "${started_at}",
      "ended_at": "${started_at}",
      "forced": false
    }
  ],
  "current_step": "start",
  "step_status": "completed",
  "step_started_at": "${started_at}",
  "step_updated_at": "${started_at}",
  "pause": $(default_pause_state_json)
}
EOF
    mv "$tmp_state" "$state_file"
}

append_git_context_scaffold() {
    local notes_file="$1"

    local branch sha status
    branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    sha=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

    if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
        status="clean"
    else
        status="dirty"
    fi

    {
        echo ""
        echo "## Git Context (auto)"
        echo "- Branch: ${branch}"
        echo "- HEAD: ${sha}"
        echo "- Working tree: ${status}"
        echo "- Recent commits:"
        if git rev-parse --verify HEAD >/dev/null 2>&1; then
            git log -5 --oneline 2>/dev/null | sed 's/^/  - /'
        else
            echo "  - (no commits)"
        fi
    } >> "$notes_file"
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

    if [[ "${SESSION_GIT_CONTEXT:-}" == "1" ]]; then
        GIT_CONTEXT=true
    fi

    if [[ "$GIT_CONTEXT" == "true" ]]; then
        append_git_context_scaffold "$notes_file"
    fi
}

create_session_next() {
    local session_id="$1"
    local session_dir
    session_dir=$(get_session_dir "$session_id")

    local next_file="${session_dir}/next.md"
    local template_file="${TEMPLATES_DIR}/next-template.md"

    if [[ -f "$template_file" ]]; then
        sed "s/{SESSION_ID}/${session_id}/g" "$template_file" > "$next_file"
    else
        cat > "$next_file" << EOF
# Next Session: ${session_id}

## Completed

## Suggested Next Steps

## Suggested Workflow

## Pending Human Actions

## Blockers

## Carry Forward
EOF
    fi
}

ensure_session_next_exists() {
    local session_id="$1"
    local session_dir
    session_dir=$(get_session_dir "$session_id")

    if [[ ! -f "${session_dir}/next.md" ]]; then
        create_session_next "$session_id"
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
    if [[ -n "${CONTINUES_FROM}" ]] && [[ "$is_resume" == "false" ]]; then
        prev_session="${CONTINUES_FROM}"
    else
        prev_session=$(get_previous_session)
    fi
    local prev_info=""
    local prev_context_instruction=""
    
    if [[ -n "$prev_session" ]]; then
        local prev_notes
        prev_notes=$(get_for_next_session_section "$prev_session")
        prev_notes=$(json_escape "$prev_notes")
        
        # Get incomplete tasks from previous session
        local prev_session_dir
        prev_session_dir=$(get_session_dir "$prev_session")
        local prev_next_file=""
        if [[ -f "${prev_session_dir}/next.md" ]]; then
            prev_next_file="${prev_session_dir}/next.md"
            prev_context_instruction="Review previous session next.md and notes.md for continuity"
        else
            prev_context_instruction="Review previous session notes for continuity"
        fi
        local prev_next_file_json="null"
        if [[ -n "$prev_next_file" ]]; then
            prev_next_file_json="\"$(json_escape "$prev_next_file")\""
        fi
        local prev_tasks_file="${prev_session_dir}/tasks.md"
        local incomplete_tasks=""
        if [[ -f "$prev_tasks_file" ]]; then
            incomplete_tasks=$(get_incomplete_tasks "$prev_tasks_file" | head -5)
            incomplete_tasks=$(json_escape "$incomplete_tasks")
        fi

        # Staleness classification vs current HEAD
        local current_branch current_commit
        current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
        current_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

        local prev_branch="" prev_commit=""
        local prev_state_file="${prev_session_dir}/state.json"
        if [[ -f "$prev_state_file" ]]; then
            prev_branch=$(jq -r '.git.branch // ""' "$prev_state_file" 2>/dev/null || echo "")
            prev_commit=$(jq -r '.git.last_commit // ""' "$prev_state_file" 2>/dev/null || echo "")
        fi

        local staleness_class="unknown"
        local staleness_message=""
        local branch_changed=false
        if [[ -n "$prev_branch" && "$prev_branch" != "$current_branch" ]]; then
            branch_changed=true
        fi

        if [[ -n "$prev_commit" && "$current_commit" != "unknown" ]]; then
            if [[ "$prev_commit" == "$current_commit" ]]; then
                staleness_class="same_head"
                staleness_message="Repo HEAD matches previous session commit."
            elif git cat-file -e "${prev_commit}^{commit}" >/dev/null 2>&1; then
                # If this check fails we treat it as "missing" (could also indicate other git errors).
                if git merge-base --is-ancestor "$prev_commit" HEAD >/dev/null 2>&1; then
                    staleness_class="ahead_of_previous"
                    staleness_message="Current HEAD is ahead of previous session commit; review intervening changes."
                else
                    staleness_class="diverged_from_previous"
                    staleness_message="Current HEAD has diverged from previous session commit; reconcile context carefully."
                fi
            else
                staleness_class="previous_commit_missing"
                staleness_message="Previous session commit not found (or not accessible); repository may have been rewritten."
            fi
        else
            staleness_class="no_previous_commit"
            staleness_message="No previous session git commit recorded."
        fi
        staleness_message=$(json_escape "$staleness_message")

        prev_info=$(cat << EOF
  "previous_session": {
    "id": "${prev_session}",
    "notes_file": "${prev_session_dir}/notes.md",
    "next_file": ${prev_next_file_json},
    "for_next_session": "${prev_notes}",
    "incomplete_tasks": "${incomplete_tasks}",
    "git": {
      "branch": "$(json_escape "$prev_branch")",
      "last_commit": "$(json_escape "$prev_commit")"
    },
    "staleness": {
      "classification": "${staleness_class}",
      "branch_changed": ${branch_changed},
      "message": "${staleness_message}"
    }
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

    local sess_workflow
    sess_workflow=$(echo "$session_info" | jq -r '.workflow // "development"')

    local sess_read_only
    sess_read_only=$(echo "$session_info" | jq -r '.read_only // false')

    local sess_parent
    sess_parent=$(echo "$session_info" | jq -r '.parent_session_id // empty')
    local sess_parent_escaped
    sess_parent_escaped=$(json_escape "$sess_parent")

    local pause_json pause_active pause_summary pause_required_action pause_resume_command
    pause_json=$(get_pause_state_json "$session_id")
    pause_active=$(echo "$pause_json" | jq -r '.active // false')
    pause_summary=$(echo "$pause_json" | jq -r '.summary // ""')
    pause_required_action=$(echo "$pause_json" | jq -r '.required_action // ""')
    pause_resume_command=$(echo "$pause_json" | jq -r '.resume_command // ""')
    
    # Build instructions array incrementally to avoid blank lines from unset vars
    local instructions=()
    instructions+=("\"Read project context files for quick orientation\"")
    [[ -n "$prev_context_instruction" ]] && instructions+=("\"${prev_context_instruction}\"")
    [[ "$RESUME_MODE" == "true" ]] && instructions+=("\"RESUME MODE: Continue from where agent left off, do not restart from beginning\"")
    [[ -n "$COMMENT" ]] && instructions+=("\"USER INSTRUCTION: $(json_escape "${COMMENT}")\"")
    [[ "$BRAINSTORM_MODE" == "true" ]] && instructions+=("\"BRAINSTORM REQUESTED: Insert session.brainstorm before the normal planning chain for this session.\"")
    if [[ "$pause_active" == "true" ]]; then
        instructions+=("\"ACTIVE HUMAN CHECKPOINT: $(json_escape "${pause_summary}. Required action: ${pause_required_action}. Resume with ${pause_resume_command}.")\"")
    fi
    instructions+=("\"Update notes.md and next.md throughout the session\"")
    instructions+=("\"Run '.session/scripts/bash/session-wrap.sh' at end of session\"")
    local instructions_json
    instructions_json=$(printf '    %s,\n' "${instructions[@]}" | sed '$s/,[[:space:]]*$//')

    cat << EOF
{
  "status": "ok",
  "action": "$(if [[ "$is_resume" == "true" ]]; then echo "resumed"; else echo "created"; fi)",
  "resume_mode": $(if [[ "$RESUME_MODE" == "true" ]]; then echo "true"; else echo "false"; fi),
  "user_comment": "$(json_escape "$COMMENT")",
  "orchestration": {
    "brainstorm": $(if [[ "$BRAINSTORM_MODE" == "true" ]]; then echo "true"; else echo "false"; fi),
    "auto": $(if [[ "$AUTO_MODE" == "true" ]]; then echo "true"; else echo "false"; fi),
    "copilot_review": $(if [[ "$COPILOT_REVIEW" == "true" ]]; then echo "true"; else echo "false"; fi)
  },
  "pause": ${pause_json},
  "repo_root": "${repo_root}",
  "session": {
    "id": "${session_id}",
    "type": "${sess_type}",
    "workflow": "${sess_workflow}",
    "stage": "${sess_stage}",
    "read_only": ${sess_read_only},
    "dir": "${session_dir}"$(if [[ -n "$sess_parent" ]]; then echo ",
    \"parent_session_id\": \"${sess_parent_escaped}\""; fi),
    "files": {
      "info": "${session_dir}/session-info.json",
      "state": "${session_dir}/state.json",
      "notes": "${session_dir}/notes.md",
      "next": "${session_dir}/next.md"$(if [[ "$sess_type" != "speckit" ]]; then echo ",
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
${instructions_json}
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
    echo "  - next.md (structured follow-up handoff)"
    
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
        if [[ -f "${prev_session_dir}/next.md" ]]; then
            echo "  Review: ${prev_session_dir}/next.md"
        fi
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

        if [[ "$BRAINSTORM_MODE" == "true" ]]; then
            if $JSON_OUTPUT; then
                echo '{"status":"error","message":"Cannot use --brainstorm with an already active session","hint":"Use invoke session.brainstorm on the active session if it is still at the beginning of planning, or resume/wrap the active session without --brainstorm"}'
            else
                print_error "Cannot use --brainstorm with an already active session"
                echo ""
                echo "Use invoke session.brainstorm on the active session if it is still at the"
                echo "beginning of planning, or resume/wrap the active session without --brainstorm."
                echo ""
            fi
            exit 1
        fi

        if [[ -f "$session_dir/state.json" ]]; then
            local step_status
            step_status=$(jq -r '.step_status // "unknown"' "$session_dir/state.json" 2>/dev/null || echo "unknown")
            if [[ "$step_status" == "in_progress" || "$step_status" == "starting" ]]; then
                if [[ "${RESUME_MODE:-false}" == "true" ]]; then
                    ensure_session_next_exists "$active_session"
                    if $JSON_OUTPUT; then
                        output_json "$active_session" "true"
                    else
                        output_human "$active_session" "true"
                    fi
                    exit 0
                else
                    if $JSON_OUTPUT; then
                        echo "{\"status\": \"error\", \"message\": \"Active session ${active_session} has step '$(jq -r '.current_step // "unknown"' "$session_dir/state.json" 2>/dev/null)' in progress\", \"hint\": \"Wrap or resume the active session first\", \"active_session\": \"${active_session}\"}"
                    else
                        print_error "Active session exists: ${active_session}"
                        echo ""
                        echo "  Step '$(jq -r '.current_step // "unknown"' "$session_dir/state.json" 2>/dev/null)' is still in progress."
                        echo ""
                        echo "To fix:"
                        echo "  1. Resume:  .session/scripts/bash/session-start.sh --resume"
                        echo "  2. Wrap:    .session/scripts/bash/session-wrap.sh --json"
                        echo "  3. Clear:   rm .session/ACTIVE_SESSION"
                        echo ""
                    fi
                    exit 1
                fi
            fi
        fi

        if [[ "${RESUME_MODE:-false}" == "true" ]]; then
            ensure_session_next_exists "$active_session"
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
                echo "{\"status\": \"error\", \"message\": \"Stale session detected: ${active_session} is from ${session_date} but today is ${today}\", \"hint\": \"Run: invoke session.start --resume (or rm .session/ACTIVE_SESSION for a new session)\"}"
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

        ensure_session_next_exists "$active_session"
        if $JSON_OUTPUT; then
            output_json "$active_session" "true"
        else
            output_human "$active_session" "true"
        fi
        exit 0
    fi

    if [[ -n "${CONTINUES_FROM}" ]]; then
        local continue_dir
        continue_dir=$(get_session_dir "${CONTINUES_FROM}")
        if [[ ! -d "${continue_dir}" ]]; then
            if $JSON_OUTPUT; then
                echo "{\"status\": \"error\", \"message\": \"--continues-from session not found: ${CONTINUES_FROM}\", \"hint\": \"Check .session/sessions for existing sessions\"}"
            else
                print_error "--continues-from session not found: ${CONTINUES_FROM}"
            fi
            exit 1
        fi
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
        elif $JSON_OUTPUT; then
            # In JSON/automation mode, no interactive triage — error immediately
            echo '{"status":"error","message":"Must specify --issue, --spec, or a goal description"}' >&2
            exit 1
        else
            # Interactive triage: help the user choose the right workflow
            echo ""
            echo "What kind of work is this?"
            echo "  1) Code change — will open a PR          (development)"
            echo "  2) Research or exploration — no PR       (--spike)"
            echo "  3) Docs, housekeeping, small fixes       (--maintenance)"
            echo "  4) Debug, troubleshoot, investigate      (--debug)"
            echo "  5) Batch/pipeline run → patch → rerun    (--operational)"
            echo "  6) Read-only audit — no commits          (--maintenance --read-only)"
            echo ""
            printf "Enter 1-6, or type your goal directly: "
            read -r triage_input

            case "$triage_input" in
                1)
                    printf "Goal / description: "
                    read -r GOAL
                    SESSION_TYPE="unstructured"
                    WORKFLOW="development"
                    ;;
                2)
                    printf "Goal / description: "
                    read -r GOAL
                    SESSION_TYPE="unstructured"
                    WORKFLOW="spike"
                    ;;
                3)
                    printf "Goal / description: "
                    read -r GOAL
                    SESSION_TYPE="unstructured"
                    WORKFLOW="maintenance"
                    ;;
                4)
                    printf "Goal / description: "
                    read -r GOAL
                    SESSION_TYPE="unstructured"
                    WORKFLOW="debug"
                    ;;
                5)
                    printf "Goal / description: "
                    read -r GOAL
                    SESSION_TYPE="unstructured"
                    WORKFLOW="operational"
                    ;;
                6)
                    printf "Goal / description: "
                    read -r GOAL
                    SESSION_TYPE="unstructured"
                    WORKFLOW="maintenance"
                    READ_ONLY=true
                    ;;
                "")
                    echo "ERROR: Must specify --issue, --spec, or a goal description" >&2
                    usage
                    exit 1
                    ;;
                *)
                    # Treat free-form input as the goal
                    GOAL="$triage_input"
                    SESSION_TYPE="unstructured"
                    WORKFLOW="development"
                    ;;
            esac
        fi
    fi

    # --read-only is only meaningful with --maintenance
    if [[ "$READ_ONLY" == "true" && "$WORKFLOW" != "maintenance" ]]; then
        echo "ERROR: --read-only requires --maintenance workflow" >&2
        exit 1
    fi

    if [[ "$BRAINSTORM_MODE" == "true" && ( "$WORKFLOW" == "maintenance" || "$WORKFLOW" == "debug" ) ]]; then
        echo "ERROR: --brainstorm is only supported for development or spike workflows" >&2
        exit 1
    fi

    if [[ "$BRAINSTORM_MODE" == "true" && "$RESUME_MODE" == "true" ]]; then
        echo "ERROR: --brainstorm cannot be combined with --resume; use invoke session.brainstorm on the active session instead" >&2
        exit 1
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
    
    # Create session directory (mkdir without -p detects race/collision atomically;
    # parent year-month dir was already created by generate_session_id())
    if ! mkdir "$session_dir" 2>/dev/null; then
        if $JSON_OUTPUT; then
            echo "{\"status\":\"error\",\"message\":\"Session collision: directory already exists: ${session_dir}\"}"
        else
            print_error "Session collision: directory already exists: ${session_dir}"
        fi
        exit 1
    fi
    
    # Create session files
    create_session_info "$session_id"
    create_session_state "$session_id"
    create_session_notes "$session_id"
    create_session_next "$session_id"
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
