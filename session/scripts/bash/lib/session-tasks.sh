#!/usr/bin/env bash
# lib/session-tasks.sh - Task counting, task file resolution, and issue/task
# management helpers.
#
# Requires: session-paths.sh (for get_session_dir)

# ============================================================================
# Issue & Task Management Functions (#665)
# ============================================================================

close_issue_with_comment() {
    # Close issue and post comment
    # Args: $1 = issue number, $2 = comment
    local issue_number="$1"
    local comment="$2"
    
    gh issue close "$issue_number" --comment "$comment" 2>/dev/null
}

update_parent_issue_progress() {
    # Update Speckit parent issue with phase progress
    # Args: $1 = parent issue number, $2 = progress text
    local parent_issue="$1"
    local progress="$2"
    
    gh issue comment "$parent_issue" --body "**Progress Update**: $progress" 2>/dev/null
}

mark_tasks_complete() {
    # Mark tasks [x] in tasks.md file
    # Args: $1 = task file path, $2... = task IDs to mark complete
    local task_file="$1"
    shift
    
    for task_id in "$@"; do
        sed -i "s/^- \[ \] $task_id/- [x] $task_id/" "$task_file"
    done
}

get_task_completion() {
    # Get task completion stats
    # Args: $1 = task file path
    # Returns: JSON with total, completed, incomplete, skipped counts
    local task_file="$1"
    
    if [ ! -f "$task_file" ]; then
        echo '{"total": 0, "completed": 0, "incomplete": 0, "skipped": 0}'
        return
    fi

    local task_lines
    task_lines=$(extract_task_lines "$task_file")

    local total=0
    local completed=0
    local skipped=0
    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue

        if [[ "$line" == *"[SKIP]"* ]]; then
            skipped=$((skipped + 1))
            continue
        fi

        total=$((total + 1))
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]\[[xX]\] ]]; then
            completed=$((completed + 1))
        fi
    done <<< "$task_lines"

    local incomplete=$((total - completed))

    jq -n \
        --argjson total "$total" \
        --argjson completed "$completed" \
        --argjson incomplete "$incomplete" \
        --argjson skipped "$skipped" \
        '{total: $total, completed: $completed, incomplete: $incomplete, skipped: $skipped}'
}

# ============================================================================
# Task Functions
# ============================================================================

resolve_tasks_file() {
    # Resolve the correct tasks.md path based on session type
    # Args: session_id
    # Returns: path to tasks.md (or empty string if not found)
    #
    # For speckit sessions: checks spec_dir and specs/spec_dir
    # For other sessions: uses session directory tasks.md
    
    local session_id="$1"
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    local info_file="${session_dir}/session-info.json"
    
    if [[ ! -f "$info_file" ]]; then
        echo ""
        return 1
    fi
    
    local session_type
    session_type=$(jq -r '.type // "unknown"' "$info_file" 2>/dev/null)
    
    case "$session_type" in
        speckit)
            local spec_dir
            spec_dir=$(jq -r '.spec_dir // empty' "$info_file" 2>/dev/null)
            
            if [[ -z "$spec_dir" ]]; then
                echo ""
                return 1
            fi
            
            # Check direct path first, then specs/ prefix
            if [[ -f "${spec_dir}/tasks.md" ]]; then
                echo "${spec_dir}/tasks.md"
            elif [[ -f "specs/${spec_dir}/tasks.md" ]]; then
                echo "specs/${spec_dir}/tasks.md"
            elif [[ -d "$spec_dir" ]]; then
                echo "${spec_dir}/tasks.md"
            elif [[ -d "specs/${spec_dir}" ]]; then
                echo "specs/${spec_dir}/tasks.md"
            else
                echo ""
                return 1
            fi
            ;;
        github_issue|unstructured|*)
            echo "${session_dir}/tasks.md"
            ;;
    esac
}

extract_task_lines() {
    # Get the task checkbox lines from the canonical task region.
    # Args: task_file
    local task_file="$1"

    if [[ ! -f "$task_file" ]]; then
        return
    fi

    local tasks_section
    tasks_section=$(awk '/^## Tasks/,0' "$task_file" 2>/dev/null || true)

    if [[ -n "$tasks_section" ]]; then
        printf '%s\n' "$tasks_section" | grep '^[[:space:]]*- \[' 2>/dev/null || true
    else
        grep '^[[:space:]]*- \[.\] T' "$task_file" 2>/dev/null || true
    fi
}

count_tasks() {
    # Count total and completed tasks in a tasks.md file.
    # Excludes `[SKIP]` tasks from the completion denominator.
    local tasks_file="$1"

    if [[ ! -f "$tasks_file" ]]; then
        echo "0:0"
        return
    fi

    local metrics
    metrics=$(get_task_completion "$tasks_file")

    local total completed
    total=$(echo "$metrics" | jq -r '.total')
    completed=$(echo "$metrics" | jq -r '.completed')

    echo "${total}:${completed}"
}

get_incomplete_tasks() {
    # Get list of incomplete non-skipped tasks.
    local tasks_file="$1"

    if [[ ! -f "$tasks_file" ]]; then
        return
    fi

    local task_lines
    task_lines=$(extract_task_lines "$tasks_file")
    printf '%s\n' "$task_lines" | grep '^[[:space:]]*- \[ \]' 2>/dev/null | grep -v '\[SKIP\]' || true
}
