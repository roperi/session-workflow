#!/usr/bin/env bash
# session-validate.sh - Validates session work quality
# Part of Post-Execute Agent Chain (#665)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=session-common.sh
source "${SCRIPT_DIR}/session-common.sh"

# ============================================================================
# Configuration
# ============================================================================

TIMEOUT_SECONDS=${VALIDATE_TIMEOUT:-300}  # 5 minutes default
RUN_TESTS=${VALIDATE_RUN_TESTS:-true}
RUN_LINT=${VALIDATE_RUN_LINT:-true}
JSON_OUTPUT=false

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
            --skip-tests)
                RUN_TESTS=false
                shift
                ;;
            --skip-lint)
                RUN_LINT=false
                shift
                ;;
            --timeout)
                TIMEOUT_SECONDS="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done
}

usage() {
    cat << EOF
Usage: session-validate.sh [OPTIONS]

Validates session work quality including git state, tasks, lint, and tests.

OPTIONS:
    --json          Output JSON for AI consumption
    --skip-tests    Skip test execution
    --skip-lint     Skip lint execution
    --timeout N     Set timeout for lint/test commands (default: 300s)
    -h, --help      Show this help

ENVIRONMENT:
    VALIDATE_TIMEOUT     Default timeout seconds (300)
    VALIDATE_RUN_TESTS   Whether to run tests (true)
    VALIDATE_RUN_LINT    Whether to run lint (true)
EOF
}

# ============================================================================
# Project Detection
# ============================================================================

detect_project_type() {
    # Returns: node, python, go, rust, bash, or unknown
    if [[ -f "package.json" ]]; then
        echo "node"
    elif [[ -f "pyproject.toml" || -f "setup.py" || -f "requirements.txt" ]]; then
        echo "python"
    elif [[ -f "go.mod" ]]; then
        echo "go"
    elif [[ -f "Cargo.toml" ]]; then
        echo "rust"
    elif [[ -f "Makefile" ]]; then
        echo "make"
    else
        echo "unknown"
    fi
}

get_lint_command() {
    local project_type="$1"
    
    # Check technical-context.md first
    local context_file=".session/project-context/technical-context.md"
    if [[ -f "$context_file" ]]; then
        local lint_cmd
        lint_cmd=$(grep -A1 "lint" "$context_file" 2>/dev/null | grep -E '^\s*`' | head -1 | tr -d '`' || true)
        if [[ -n "$lint_cmd" ]]; then
            echo "$lint_cmd"
            return
        fi
    fi
    
    # Fall back to project type detection
    case "$project_type" in
        node)
            if [[ -f "package.json" ]]; then
                if jq -e '.scripts.lint' package.json >/dev/null 2>&1; then
                    echo "npm run lint"
                elif jq -e '.scripts["lint:check"]' package.json >/dev/null 2>&1; then
                    echo "npm run lint:check"
                else
                    echo ""
                fi
            fi
            ;;
        python)
            if command -v ruff >/dev/null 2>&1; then
                echo "ruff check ."
            elif command -v flake8 >/dev/null 2>&1; then
                echo "flake8"
            else
                echo ""
            fi
            ;;
        go)
            echo "go vet ./..."
            ;;
        rust)
            echo "cargo clippy"
            ;;
        *)
            echo ""
            ;;
    esac
}

get_test_command() {
    local project_type="$1"
    
    # Check technical-context.md first
    local context_file=".session/project-context/technical-context.md"
    if [[ -f "$context_file" ]]; then
        local test_cmd
        test_cmd=$(grep -A1 "test" "$context_file" 2>/dev/null | grep -E '^\s*`' | head -1 | tr -d '`' || true)
        if [[ -n "$test_cmd" ]]; then
            echo "$test_cmd"
            return
        fi
    fi
    
    # Fall back to project type detection
    case "$project_type" in
        node)
            if [[ -f "package.json" ]]; then
                if jq -e '.scripts.test' package.json >/dev/null 2>&1; then
                    echo "npm test"
                else
                    echo ""
                fi
            fi
            ;;
        python)
            if command -v pytest >/dev/null 2>&1; then
                echo "pytest"
            elif [[ -f "setup.py" ]]; then
                echo "python -m unittest discover"
            else
                echo ""
            fi
            ;;
        go)
            echo "go test ./..."
            ;;
        rust)
            echo "cargo test"
            ;;
        make)
            if grep -q "^test:" Makefile 2>/dev/null; then
                echo "make test"
            else
                echo ""
            fi
            ;;
        *)
            echo ""
            ;;
    esac
}

# ============================================================================
# Run Command with Timeout
# ============================================================================

run_with_timeout() {
    local cmd="$1"
    local timeout_secs="${2:-$TIMEOUT_SECONDS}"
    local output
    local exit_code
    
    # Run command with timeout
    set +e
    output=$(timeout "$timeout_secs" bash -c "$cmd" 2>&1)
    exit_code=$?
    set -e
    
    if [[ $exit_code -eq 124 ]]; then
        echo "TIMEOUT"
        return 124
    fi
    
    echo "$output"
    return $exit_code
}

# ============================================================================
# JSON Output
# ============================================================================

output_json() {
    local status="$1"
    local message="$2"
    local project_type="$3"
    shift 3
    local checks=("$@")
    
    # Build JSON using jq for proper escaping
    local checks_json="[]"
    for check in "${checks[@]}"; do
        checks_json=$(echo "$checks_json" | jq --argjson c "$check" '. + [$c]')
    done
    
    jq -n \
        --arg status "$status" \
        --arg message "$message" \
        --arg project_type "$project_type" \
        --argjson checks "$checks_json" \
        '{
            status: $status,
            message: $message,
            project_type: $project_type,
            validation_checks: $checks
        }'
}

output_text() {
    local status="$1"
    local message="$2"
    shift 2
    
    if [[ "$status" == "success" ]]; then
        print_success "$message"
    else
        print_error "$message"
    fi
}

# ============================================================================
# Main Validation Logic
# ============================================================================

main() {
    parse_args "$@"
    
    local checks=()
    local failures=()
    local status="success"
    
    # Detect project type
    local project_type
    project_type=$(detect_project_type)
    
    # -------------------------------------------------------------------------
    # Check 1: Git status
    # -------------------------------------------------------------------------
    if git diff --quiet && git diff --cached --quiet; then
        checks+=('{"check": "git_status", "status": "pass", "message": "Working tree clean"}')
    else
        checks+=('{"check": "git_status", "status": "fail", "message": "Uncommitted changes found"}')
        failures+=("git_status")
        status="error"
    fi
    
    # -------------------------------------------------------------------------
    # Check 2: Branch ahead of origin
    # -------------------------------------------------------------------------
    if git rev-parse --verify HEAD >/dev/null 2>&1; then
        local current_branch
        current_branch=$(git rev-parse --abbrev-ref HEAD)
        
        if [[ "$current_branch" != "main" && "$current_branch" != "HEAD" ]]; then
            if git rev-parse --verify "origin/${current_branch}" >/dev/null 2>&1; then
                local ahead
                ahead=$(git rev-list --count "origin/${current_branch}..HEAD")
                if [[ "$ahead" -gt 0 ]]; then
                    checks+=("{\"check\": \"git_ahead\", \"status\": \"pass\", \"message\": \"Branch ahead by ${ahead} commits\"}")
                else
                    checks+=('{"check": "git_ahead", "status": "warning", "message": "No new commits to push"}')
                fi
            else
                checks+=('{"check": "git_ahead", "status": "pass", "message": "New branch, ready to push"}')
            fi
        else
            checks+=('{"check": "git_ahead", "status": "warning", "message": "On main branch"}')
        fi
    fi
    
    # -------------------------------------------------------------------------
    # Check 3: Active session and tasks
    # -------------------------------------------------------------------------
    local session_id=""
    local tasks_file=""
    
    if [[ -f "${ACTIVE_SESSION_FILE}" ]]; then
        session_id=$(cat "${ACTIVE_SESSION_FILE}")
        checks+=("{\"check\": \"active_session\", \"status\": \"pass\", \"message\": \"Active session: ${session_id}\"}")
        
        # Resolve tasks file using helper function
        tasks_file=$(resolve_tasks_file "$session_id")
        
        if [[ -n "$tasks_file" && -f "$tasks_file" ]]; then
            local counts
            counts=$(count_tasks "$tasks_file")
            local total_tasks completed_tasks
            total_tasks=$(echo "$counts" | cut -d: -f1)
            completed_tasks=$(echo "$counts" | cut -d: -f2)
            
            if [[ "$total_tasks" -eq "$completed_tasks" ]]; then
                checks+=("{\"check\": \"tasks\", \"status\": \"pass\", \"message\": \"All ${total_tasks} tasks complete\"}")
            else
                local remaining=$((total_tasks - completed_tasks))
                checks+=("{\"check\": \"tasks\", \"status\": \"warning\", \"message\": \"${remaining} of ${total_tasks} tasks incomplete\"}")
            fi
        else
            checks+=('{"check": "tasks", "status": "warning", "message": "No tasks.md found"}')
        fi
    else
        checks+=('{"check": "active_session", "status": "warning", "message": "No active session file"}')
    fi
    
    # -------------------------------------------------------------------------
    # Check 4: Lint (if enabled)
    # -------------------------------------------------------------------------
    if [[ "$RUN_LINT" == "true" ]]; then
        local lint_cmd
        lint_cmd=$(get_lint_command "$project_type")
        
        if [[ -n "$lint_cmd" ]]; then
            local lint_output
            local lint_exit
            
            set +e
            lint_output=$(run_with_timeout "$lint_cmd" "$TIMEOUT_SECONDS")
            lint_exit=$?
            set -e
            
            if [[ $lint_exit -eq 0 ]]; then
                checks+=("{\"check\": \"lint\", \"status\": \"pass\", \"message\": \"Lint passed\", \"command\": \"${lint_cmd}\"}")
            elif [[ $lint_exit -eq 124 ]]; then
                checks+=("{\"check\": \"lint\", \"status\": \"warning\", \"message\": \"Lint timed out after ${TIMEOUT_SECONDS}s\", \"command\": \"${lint_cmd}\"}")
            else
                # Escape the output for JSON
                local escaped_output
                escaped_output=$(echo "$lint_output" | head -20 | jq -Rs '.')
                checks+=("{\"check\": \"lint\", \"status\": \"fail\", \"message\": \"Lint failed\", \"command\": \"${lint_cmd}\", \"output\": ${escaped_output}}")
                failures+=("lint")
                status="error"
            fi
        else
            checks+=("{\"check\": \"lint\", \"status\": \"skipped\", \"message\": \"No lint command found for ${project_type}\"}")
        fi
    else
        checks+=('{"check": "lint", "status": "skipped", "message": "Lint skipped via --skip-lint"}')
    fi
    
    # -------------------------------------------------------------------------
    # Check 5: Tests (if enabled)
    # -------------------------------------------------------------------------
    if [[ "$RUN_TESTS" == "true" ]]; then
        local test_cmd
        test_cmd=$(get_test_command "$project_type")
        
        if [[ -n "$test_cmd" ]]; then
            local test_output
            local test_exit
            
            set +e
            test_output=$(run_with_timeout "$test_cmd" "$TIMEOUT_SECONDS")
            test_exit=$?
            set -e
            
            if [[ $test_exit -eq 0 ]]; then
                checks+=("{\"check\": \"tests\", \"status\": \"pass\", \"message\": \"Tests passed\", \"command\": \"${test_cmd}\"}")
            elif [[ $test_exit -eq 124 ]]; then
                checks+=("{\"check\": \"tests\", \"status\": \"warning\", \"message\": \"Tests timed out after ${TIMEOUT_SECONDS}s\", \"command\": \"${test_cmd}\"}")
            else
                local escaped_output
                escaped_output=$(echo "$test_output" | tail -30 | jq -Rs '.')
                checks+=("{\"check\": \"tests\", \"status\": \"fail\", \"message\": \"Tests failed\", \"command\": \"${test_cmd}\", \"output\": ${escaped_output}}")
                failures+=("tests")
                status="error"
            fi
        else
            checks+=("{\"check\": \"tests\", \"status\": \"skipped\", \"message\": \"No test command found for ${project_type}\"}")
        fi
    else
        checks+=('{"check": "tests", "status": "skipped", "message": "Tests skipped via --skip-tests"}')
    fi
    
    # -------------------------------------------------------------------------
    # Determine final status
    # -------------------------------------------------------------------------
    local message
    if [[ "${#failures[@]}" -gt 0 ]]; then
        status="error"
        message="Validation failed: ${failures[*]}"
    else
        message="Session validation passed"
    fi
    
    # -------------------------------------------------------------------------
    # Output
    # -------------------------------------------------------------------------
    if $JSON_OUTPUT; then
        output_json "$status" "$message" "$project_type" "${checks[@]}"
    else
        output_text "$status" "$message"
        for check in "${checks[@]}"; do
            local check_name check_status check_message
            check_name=$(echo "$check" | jq -r '.check')
            check_status=$(echo "$check" | jq -r '.status')
            check_message=$(echo "$check" | jq -r '.message')
            
            case "$check_status" in
                pass)    echo "  ✓ ${check_name}: ${check_message}" ;;
                fail)    echo "  ✗ ${check_name}: ${check_message}" ;;
                warning) echo "  ⚠ ${check_name}: ${check_message}" ;;
                skipped) echo "  ○ ${check_name}: ${check_message}" ;;
            esac
        done
    fi
    
    # Return appropriate exit code
    if [[ "$status" == "error" ]]; then
        exit 1
    fi
}

# Run main
main "$@"
