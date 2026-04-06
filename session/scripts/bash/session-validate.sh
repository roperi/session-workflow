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
RUN_SPEC=${VALIDATE_RUN_SPEC:-true}
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
            --skip-spec)
                RUN_SPEC=false
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
    --skip-spec     Skip spec verification
    --timeout N     Set timeout for lint/test commands (default: 300s)
    -h, --help      Show this help

ENVIRONMENT:
    VALIDATE_TIMEOUT     Default timeout seconds (300)
    VALIDATE_RUN_TESTS   Whether to run tests (true)
    VALIDATE_RUN_LINT    Whether to run lint (true)
    VALIDATE_RUN_SPEC    Whether to run spec verification (true)
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
            if validate_safe_command "$lint_cmd"; then
                echo "$lint_cmd"
            else
                warn "Ignoring unsafe lint command from technical-context.md: '$lint_cmd'"
            fi
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
            if validate_safe_command "$test_cmd"; then
                echo "$test_cmd"
            else
                warn "Ignoring unsafe test command from technical-context.md: '$test_cmd'"
            fi
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
# Spec Verification
# ============================================================================

resolve_spec_file() {
    # Find spec.md for the active session.
    # For speckit sessions: specs/<feature>/spec.md
    # For other sessions: <session_dir>/spec.md
    # Args: session_id
    # Returns: path to spec.md or empty string
    local session_id="$1"
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    local info_file="${session_dir}/session-info.json"

    # Check for speckit session type
    local session_type=""
    if [[ -f "$info_file" ]]; then
        session_type=$(jq -r '.type // ""' "$info_file" 2>/dev/null)
    fi

    if [[ "$session_type" == "speckit" ]]; then
        local spec_dir
        spec_dir=$(jq -r '.spec_dir // ""' "$info_file" 2>/dev/null)
        if [[ -n "$spec_dir" && -f "${spec_dir}/spec.md" ]]; then
            echo "${spec_dir}/spec.md"
            return
        fi
    fi

    # Default: session directory spec.md
    if [[ -f "${session_dir}/spec.md" ]]; then
        echo "${session_dir}/spec.md"
        return
    fi

    echo ""
}

get_session_stage() {
    # Get stage from session-info.json, defaulting to "production"
    # Args: session_id
    local session_id="$1"
    local session_dir
    session_dir=$(get_session_dir "$session_id")
    local info_file="${session_dir}/session-info.json"

    if [[ -f "$info_file" ]]; then
        jq -r '.stage // "production"' "$info_file" 2>/dev/null
    else
        echo "production"
    fi
}

check_spec_verification() {
    # Parse spec.md and verify checklist items.
    # Args: spec_file stage
    # Outputs: JSON check object to stdout
    # Returns: 0 if pass/skipped, 1 if fail
    local spec_file="$1"
    local stage="$2"

    if [[ -z "$spec_file" || ! -f "$spec_file" ]]; then
        echo '{"check": "spec_verification", "status": "skipped", "message": "No spec.md found"}'
        return 0
    fi

    if [[ "$stage" == "poc" ]]; then
        echo '{"check": "spec_verification", "status": "skipped", "message": "Spec verification skipped (poc stage)"}'
        return 0
    fi

    # Extract Verification Checklist section
    local in_section=false
    local total=0
    local verified=0
    local items_json="[]"

    while IFS= read -r line; do
        # Detect start of Verification Checklist section
        if [[ "$line" =~ ^##[[:space:]]+Verification[[:space:]]+Checklist ]]; then
            in_section=true
            continue
        fi
        # Stop at next heading
        if $in_section && [[ "$line" =~ ^## ]]; then
            break
        fi
        if $in_section; then
            # Match checked items: - [x] or - [X]
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]\[[xX]\][[:space:]]+(.*) ]]; then
                total=$((total + 1))
                verified=$((verified + 1))
                local item_text="${BASH_REMATCH[1]}"
                items_json=$(echo "$items_json" | jq --arg item "$item_text" --arg status "met" '. + [{"item": $item, "status": $status}]')
            # Match unchecked items: - [ ]
            elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]\[[[:space:]]\][[:space:]]+(.*) ]]; then
                total=$((total + 1))
                local item_text="${BASH_REMATCH[1]}"
                items_json=$(echo "$items_json" | jq --arg item "$item_text" --arg status "unmet" '. + [{"item": $item, "status": $status}]')
            fi
        fi
    done < "$spec_file"

    if [[ "$total" -eq 0 ]]; then
        echo '{"check": "spec_verification", "status": "skipped", "message": "No verification checklist found in spec.md"}'
        return 0
    fi

    local unmet=$((total - verified))
    local check_status="pass"
    local check_message="All ${total} spec verification items met"
    local return_code=0

    if [[ "$unmet" -gt 0 ]]; then
        if [[ "$stage" == "production" ]]; then
            check_status="fail"
            check_message="${unmet} of ${total} spec verification items unmet"
            return_code=1
        else
            # mvp: warn on unmet items
            check_status="warning"
            check_message="${unmet} of ${total} spec verification items unmet"
        fi
    fi

    jq -n \
        --arg check "spec_verification" \
        --arg status "$check_status" \
        --arg message "$check_message" \
        --argjson verified "$verified" \
        --argjson total "$total" \
        --argjson items "$items_json" \
        '{check: $check, status: $status, message: $message, verified: $verified, total: $total, items: $items}'

    return $return_code
}

# ============================================================================
# Command Allowlist Validation
# ============================================================================

# Validate that a command extracted from technical-context.md is safe to run.
# Only commands starting with a known-safe tool prefix are permitted.
# This prevents RCE via malicious content in Markdown configuration files.
validate_safe_command() {
    local cmd="$1"
    # Strip leading whitespace
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"
    [[ -z "$cmd" ]] && return 1

    local safe_prefixes=(
        "npm" "yarn" "pnpm" "npx" "bun"
        "pytest" "python" "python3" "ruff" "flake8" "black" "isort" "mypy" "pylint"
        "go" "cargo" "rustfmt" "clippy"
        "make" "rake"
        "bundle" "rspec" "rubocop"
        "mvn" "gradle" "./gradlew" "./mvnw"
        "docker" "docker-compose" "docker compose"
        "swift" "xcodebuild"
        "dotnet"
    )
    for prefix in "${safe_prefixes[@]}"; do
        if [[ "$cmd" == "${prefix}"* ]]; then
            return 0
        fi
    done
    return 1
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
    
    local checks_json
    checks_json=$(build_checks_json "${checks[@]}")
    
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

build_checks_json() {
    local checks=("$@")
    local checks_json="[]"
    local check

    for check in "${checks[@]}"; do
        checks_json=$(echo "$checks_json" | jq --argjson c "$check" '. + [$c]')
    done

    echo "$checks_json"
}

build_validation_results_object() {
    local checks_json="$1"
    echo "$checks_json" | jq 'reduce .[] as $check ({}; .[$check.check] = ($check | del(.check)))'
}

persist_validation_results() {
    local status="$1"
    local message="$2"
    local project_type="$3"
    local session_id="$4"
    local checks_json="$5"

    local overall="pass"
    local can_publish=true
    if [[ "$status" != "success" ]]; then
        overall="fail"
        can_publish=false
    fi

    local results_json
    results_json=$(build_validation_results_object "$checks_json")

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local tmp_file
    tmp_file=$(mktemp)
    jq -n \
        --arg schema_version "$VALIDATION_RESULTS_SCHEMA_VERSION" \
        --arg timestamp "$timestamp" \
        --arg session_id "$session_id" \
        --arg project_type "$project_type" \
        --arg overall "$overall" \
        --arg summary "$message" \
        --arg status "$status" \
        --argjson can_publish "$can_publish" \
        --argjson validation_checks "$checks_json" \
        --argjson results "$results_json" \
        '{
            schema_version: $schema_version,
            timestamp: $timestamp,
            session_id: (if $session_id == "" then null else $session_id end),
            project_type: $project_type,
            overall: $overall,
            can_publish: $can_publish,
            summary: $summary,
            status: $status,
            validation_checks: $validation_checks,
            results: $results
        }' > "$tmp_file"

    local local_results_file="${SESSION_ROOT}/validation-results.json"
    cp "$tmp_file" "$local_results_file"

    if [[ -n "$session_id" ]]; then
        local session_results_file
        session_results_file="$(get_session_dir "$session_id")/validation-results.json"
        cp "$tmp_file" "$session_results_file"
    fi

    rm -f "$tmp_file"
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
    local dirty_paths
    dirty_paths=$(list_nonvolatile_tracked_dirty_paths)
    if [[ -z "$dirty_paths" ]]; then
        checks+=('{"check": "git_status", "status": "pass", "message": "Working tree clean (excluding volatile session bookkeeping)"}')
    else
        local dirty_paths_json
        dirty_paths_json=$(printf '%s\n' "$dirty_paths" | jq -R -s 'split("\n") | map(select(length > 0))')
        checks+=("{\"check\": \"git_status\", \"status\": \"fail\", \"message\": \"Uncommitted tracked changes found\", \"paths\": ${dirty_paths_json}}")
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
    # Check 4: Spec verification (if enabled and session active)
    # -------------------------------------------------------------------------
    if [[ "$RUN_SPEC" == "true" && -n "$session_id" ]]; then
        local spec_file stage spec_check
        spec_file=$(resolve_spec_file "$session_id")
        stage=$(get_session_stage "$session_id")

        set +e
        spec_check=$(check_spec_verification "$spec_file" "$stage")
        local spec_exit=$?
        set -e

        checks+=("$spec_check")
        if [[ $spec_exit -ne 0 ]]; then
            failures+=("spec_verification")
            status="error"
        fi
    elif [[ "$RUN_SPEC" != "true" ]]; then
        checks+=('{"check": "spec_verification", "status": "skipped", "message": "Spec verification skipped via --skip-spec"}')
    else
        checks+=('{"check": "spec_verification", "status": "skipped", "message": "Spec verification skipped (no active session)"}')
    fi
    
    # -------------------------------------------------------------------------
    # Check 5: Lint (if enabled)
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
    # Check 6: Tests (if enabled)
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

    local checks_json
    checks_json=$(build_checks_json "${checks[@]}")
    persist_validation_results "$status" "$message" "$project_type" "$session_id" "$checks_json"
    
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
