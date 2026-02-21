#!/usr/bin/env bash
# lib/session-git.sh - Git/PR helpers, prerequisite checks, quality/validation
# functions.
#
# Requires: session-output.sh (for color variables and print_* functions)

# ============================================================================
# Prerequisite Checks
# ============================================================================

check_prerequisites() {
    local errors=0
    
    # Check git
    if ! command -v git &> /dev/null; then
        echo -e "${RED}ERROR: git is not installed${NC}" >&2
        ((errors++))
    fi
    
    # Check if in git repo
    if ! git rev-parse --git-dir &> /dev/null; then
        echo -e "${RED}ERROR: Not in a git repository${NC}" >&2
        ((errors++))
    fi
    
    # Check jq for JSON output
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}WARNING: jq not installed - JSON output may be malformed${NC}" >&2
    fi
    
    return $errors
}

# ============================================================================
# PR Helper Functions (#665)
# ============================================================================

detect_existing_pr() {
    # Check if PR exists for current branch
    # Returns: PR number or empty string
    gh pr view --json number -q .number 2>/dev/null || echo ""
}

get_pr_status() {
    # Get PR status details
    # Args: $1 = PR number
    # Returns: JSON with state, draft status, merged status
    local pr_number="$1"
    gh pr view "$pr_number" --json state,isDraft,merged 2>/dev/null || echo "{}"
}

check_pr_merged() {
    # Check if PR is merged
    # Args: $1 = PR number
    # Returns: 0 if merged, 1 if not
    local pr_number="$1"
    local merged
    merged=$(gh pr view "$pr_number" --json merged -q .merged 2>/dev/null || echo "false")
    
    if [ "$merged" = "true" ]; then
        return 0
    else
        return 1
    fi
}

generate_pr_title_from_commits() {
    # Generate PR title from recent commits
    # Returns: Suggested PR title
    local first_commit
    first_commit=$(git log origin/main..HEAD --oneline --reverse | head -1)
    echo "$first_commit" | cut -d' ' -f2-
}

get_commits_for_pr() {
    # Get list of commits for PR description
    # Returns: Formatted commit list
    git log origin/main..HEAD --oneline --reverse
}

# ============================================================================
# Validation Functions (#665)
# ============================================================================

run_quality_checks() {
    # Run lint and format checks
    # Returns: 0 if passed, 1 if failed
    # Tries common patterns based on project structure
    local errors=0
    
    # Try Makefile first (most reliable)
    if [ -f "Makefile" ] && grep -q "lint:" Makefile 2>/dev/null; then
        make lint >/dev/null 2>&1 || ((errors++))
    # Node.js project
    elif [ -f "package.json" ]; then
        npm run lint >/dev/null 2>&1 || ((errors++))
    # Python project
    elif [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
        if command -v pylint &>/dev/null; then
            pylint . >/dev/null 2>&1 || ((errors++))
        fi
    fi
    
    return $errors
}

run_all_tests() {
    # Run all test suites
    # Returns: 0 if all passed, 1 if any failed
    # Tries common patterns based on project structure
    local errors=0
    
    # Try Makefile first (most reliable)
    if [ -f "Makefile" ] && grep -q "test" Makefile 2>/dev/null; then
        make test >/dev/null 2>&1 || ((errors++))
    # Node.js project
    elif [ -f "package.json" ]; then
        npm test >/dev/null 2>&1 || ((errors++))
    # Python project
    elif [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
        if command -v pytest &>/dev/null; then
            pytest >/dev/null 2>&1 || ((errors++))
        fi
    # Go project
    elif [ -f "go.mod" ]; then
        go test ./... >/dev/null 2>&1 || ((errors++))
    fi
    
    return $errors
}

check_git_state() {
    # Check git working tree is clean and pushed
    # Returns: 0 if clean, 1 if dirty or unpushed
    local errors=0
    
    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        ((errors++))
    fi
    
    # Check for unpushed commits
    local unpushed
    unpushed=$(git log @{u}.. --oneline 2>/dev/null | wc -l)
    if [ "$unpushed" -gt 0 ]; then
        ((errors++))
    fi
    
    return $errors
}

check_git_clean() {
    # Returns 0 if clean, 1 if dirty
    if git diff --quiet && git diff --cached --quiet; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# Validation Functions (for session.validate agent)
# ============================================================================

check_test_status() {
    # Check if tests pass
    # Returns: "pass" | "fail" | "unknown"
    # Note: This is a quick check, not running full test suite
    
    # Check for recent test failures in git log
    if git log -1 --grep="test.*fail" --oneline >/dev/null 2>&1; then
        echo "warning"
        return
    fi
    
    # Check if test files exist
    if [[ -d "backend/tests" ]] || [[ -d "frontend/src/__tests__" ]]; then
        echo "unknown"
    else
        echo "pass"
    fi
}

check_lint_status() {
    # Quick check for obvious lint issues
    # Returns: "pass" | "fail" | "unknown"
    
    # Check for Python syntax errors
    if [[ -d "backend/app" ]]; then
        if ! find backend/app -name "*.py" -exec python3 -m py_compile {} \; 2>/dev/null; then
            echo "fail"
            return
        fi
    fi
    
    # Check for TypeScript syntax errors (basic)
    if [[ -d "frontend/src" ]]; then
        # Just check files exist and are readable
        if find frontend/src -name "*.tsx" -o -name "*.ts" 2>/dev/null | grep -q .; then
            echo "unknown"
        else
            echo "pass"
        fi
    else
        echo "pass"
    fi
}

get_validation_fixes() {
    # Generate list of suggested fixes based on validation failures
    # Args: space-separated list of failed checks
    local failures=("$@")
    local fixes=()
    
    for failure in "${failures[@]}"; do
        case "$failure" in
            "git_status")
                fixes+=('{"fix": "commit_changes", "command": "git add -A && git commit -m \"chore: commit pending changes\"", "description": "Commit uncommitted changes"}')
                ;;
            "tests")
                fixes+=('{"fix": "run_tests", "command": "Check technical-context.md for test command", "description": "Run tests"}')
                ;;
            "lint")
                fixes+=('{"fix": "run_lint", "command": "Check technical-context.md for lint command", "description": "Run linter"}')
                ;;
            "tasks")
                fixes+=('{"fix": "review_tasks", "command": "cat tasks.md", "description": "Review incomplete tasks"}')
                ;;
        esac
    done
    
    # Output as JSON array
    if [[ "${#fixes[@]}" -gt 0 ]]; then
        echo "["
        local first=true
        for fix in "${fixes[@]}"; do
            if [[ "$first" == true ]]; then
                first=false
            else
                echo ","
            fi
            echo -n "    ${fix}"
        done
        echo ""
        echo "  ]"
    else
        echo "[]"
    fi
}
