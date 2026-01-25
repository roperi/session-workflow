#!/usr/bin/env bash
# install.sh - Install session-workflow in current repository
# https://github.com/roperi/session-workflow

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

REPO_URL="https://raw.githubusercontent.com/roperi/session-workflow/main"
VERSION="2.0.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Detected environment (populated by detect_* functions)
DETECTED_STAGE=""
DETECTED_ENV=""
DETECTED_STACK=""
DETECTED_TEST_CMD=""
DETECTED_BUILD_CMD=""
DETECTED_LINT_CMD=""
PROJECT_ROOT=""

# ============================================================================
# Helper Functions
# ============================================================================

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

check_prerequisites() {
    # Must be in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        error "Not in a git repository. Run 'git init' first."
    fi
    
    # Check for curl or wget
    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        error "Neither curl nor wget found. Please install one."
    fi
    
    # Set project root
    PROJECT_ROOT=$(git rev-parse --show-toplevel)
}

# ============================================================================
# Auto-Detection Functions
# ============================================================================

detect_environment() {
    info "Detecting environment..."
    
    DETECTED_ENV="local"
    
    # Docker detection
    if [[ -f "Dockerfile" ]] || [[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]] || [[ -f "compose.yml" ]] || [[ -f "compose.yaml" ]]; then
        DETECTED_ENV="containerized"
        success "Detected: Containerized (Docker)"
    else
        success "Detected: Local environment"
    fi
}

detect_stack() {
    info "Detecting tech stack..."
    
    DETECTED_STACK=""
    
    # Node.js
    if [[ -f "package.json" ]]; then
        DETECTED_STACK="node"
        # Try to extract test command
        if command -v jq &> /dev/null; then
            local test_script
            test_script=$(jq -r '.scripts.test // empty' package.json 2>/dev/null)
            if [[ -n "$test_script" && "$test_script" != "null" ]]; then
                if [[ "$DETECTED_ENV" == "containerized" ]]; then
                    DETECTED_TEST_CMD="# Run inside container or locally if node available\nnpm test"
                else
                    DETECTED_TEST_CMD="npm test"
                fi
            fi
            
            local build_script
            build_script=$(jq -r '.scripts.build // empty' package.json 2>/dev/null)
            if [[ -n "$build_script" && "$build_script" != "null" ]]; then
                DETECTED_BUILD_CMD="npm run build"
            fi
            
            local lint_script
            lint_script=$(jq -r '.scripts.lint // empty' package.json 2>/dev/null)
            if [[ -n "$lint_script" && "$lint_script" != "null" ]]; then
                DETECTED_LINT_CMD="npm run lint"
            fi
        fi
        success "Detected: Node.js"
    fi
    
    # Python
    if [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then
        if [[ -n "$DETECTED_STACK" ]]; then
            DETECTED_STACK="${DETECTED_STACK}, python"
        else
            DETECTED_STACK="python"
        fi
        
        if [[ "$DETECTED_ENV" == "containerized" ]]; then
            DETECTED_TEST_CMD="docker compose exec <service> python -m pytest"
        else
            DETECTED_TEST_CMD="python -m pytest"
        fi
        success "Detected: Python"
    fi
    
    # Go
    if [[ -f "go.mod" ]]; then
        if [[ -n "$DETECTED_STACK" ]]; then
            DETECTED_STACK="${DETECTED_STACK}, go"
        else
            DETECTED_STACK="go"
        fi
        DETECTED_TEST_CMD="go test ./..."
        DETECTED_BUILD_CMD="go build ./..."
        success "Detected: Go"
    fi
    
    # Rust
    if [[ -f "Cargo.toml" ]]; then
        if [[ -n "$DETECTED_STACK" ]]; then
            DETECTED_STACK="${DETECTED_STACK}, rust"
        else
            DETECTED_STACK="rust"
        fi
        DETECTED_TEST_CMD="cargo test"
        DETECTED_BUILD_CMD="cargo build"
        success "Detected: Rust"
    fi
    
    # Ruby
    if [[ -f "Gemfile" ]]; then
        if [[ -n "$DETECTED_STACK" ]]; then
            DETECTED_STACK="${DETECTED_STACK}, ruby"
        else
            DETECTED_STACK="ruby"
        fi
        if [[ -f "spec" ]] || [[ -d "spec" ]]; then
            DETECTED_TEST_CMD="bundle exec rspec"
        fi
        success "Detected: Ruby"
    fi
    
    if [[ -z "$DETECTED_STACK" ]]; then
        DETECTED_STACK="unknown"
        warn "Could not detect tech stack"
    fi
}

detect_project_stage() {
    info "Detecting project stage..."
    
    local maturity_score=0
    
    # Check for CI/CD (indicates at least MVP)
    if [[ -d ".github/workflows" ]] || [[ -f ".gitlab-ci.yml" ]] || [[ -f "Jenkinsfile" ]]; then
        ((maturity_score+=2))
    fi
    
    # Check for tests
    if [[ -d "tests" ]] || [[ -d "test" ]] || [[ -d "spec" ]] || [[ -d "__tests__" ]]; then
        ((maturity_score+=1))
    fi
    
    # Check for docs
    if [[ -d "docs" ]] && [[ $(find docs -name "*.md" 2>/dev/null | wc -l) -gt 3 ]]; then
        ((maturity_score+=1))
    fi
    
    # Check for README quality
    if [[ -f "README.md" ]]; then
        local readme_lines
        readme_lines=$(wc -l < README.md)
        if [[ $readme_lines -gt 100 ]]; then
            ((maturity_score+=1))
        fi
    fi
    
    # Check for PoC marker folder (experiments/)
    if [[ -d "experiments" ]] || [[ -f "ROADMAP.md" ]]; then
        # Cap at poc if PoC markers exist
        if [[ $maturity_score -gt 2 ]]; then
            maturity_score=2
        fi
    fi
    
    # Determine stage
    if [[ $maturity_score -le 1 ]]; then
        DETECTED_STAGE="poc"
        success "Detected: PoC stage"
    elif [[ $maturity_score -le 2 ]]; then
        DETECTED_STAGE="poc"
        success "Detected: PoC stage"
    elif [[ $maturity_score -le 4 ]]; then
        DETECTED_STAGE="mvp"
        success "Detected: MVP stage"
    else
        DETECTED_STAGE="production"
        success "Detected: Production stage"
    fi
}

download_file() {
    local url="$1"
    local dest="$2"
    
    mkdir -p "$(dirname "$dest")"
    
    if command -v curl &> /dev/null; then
        curl -sSL "$url" -o "$dest"
    else
        wget -q "$url" -O "$dest"
    fi
}

# ============================================================================
# Installation Functions
# ============================================================================

install_scripts() {
    info "Installing session scripts..."
    
    local scripts=(
        "session-common.sh"
        "session-start.sh"
        "session-wrap.sh"
        "session-validate.sh"
        "session-publish.sh"
        "session-finalize.sh"
    )
    
    mkdir -p .session/scripts/bash
    
    for script in "${scripts[@]}"; do
        download_file "${REPO_URL}/session/scripts/bash/${script}" ".session/scripts/bash/${script}"
        chmod +x ".session/scripts/bash/${script}"
    done
    
    success "Scripts installed"
}

install_templates() {
    info "Installing templates..."
    
    mkdir -p .session/templates
    download_file "${REPO_URL}/session/templates/session-notes.md" ".session/templates/session-notes.md"
    
    success "Templates installed"
}

install_docs() {
    info "Installing session docs..."
    
    # Only install internal session docs (quick reference)
    mkdir -p .session/docs
    download_file "${REPO_URL}/session/docs/README.md" ".session/docs/README.md"
    download_file "${REPO_URL}/session/docs/testing.md" ".session/docs/testing.md"
    download_file "${REPO_URL}/session/docs/shared-workflow.md" ".session/docs/shared-workflow.md"
    
    success "Session docs installed"
}

install_bootstrap() {
    info "Installing AI bootstrap files..."
    
    # Create .github directory
    mkdir -p .github
    
    # Install AGENTS.md if it doesn't exist
    if [[ ! -f "AGENTS.md" ]]; then
        download_file "${REPO_URL}/stubs/AGENTS.md" "AGENTS.md"
        success "Created AGENTS.md"
    else
        # Append session workflow section if not already present
        if ! grep -q "Session Workflow" AGENTS.md 2>/dev/null; then
            echo "" >> AGENTS.md
            echo "## Session Workflow" >> AGENTS.md
            echo "" >> AGENTS.md
            echo "This project uses session workflow for AI context continuity." >> AGENTS.md
            echo "See \`.session/docs/README.md\` for quick reference." >> AGENTS.md
            echo "" >> AGENTS.md
            echo "**Commands:**" >> AGENTS.md
            echo "- \`/session.start --issue N\` - Start development session" >> AGENTS.md
            echo "- \`/session.start \"text\"\` - Start unstructured session" >> AGENTS.md
            echo "- \`/session.start --spike \"text\"\` - Start spike/research" >> AGENTS.md
            echo "- \`/session.wrap\` - End session" >> AGENTS.md
            success "Updated AGENTS.md with session workflow section"
        else
            warn "AGENTS.md already has session workflow section, skipping"
        fi
    fi
    
    # Install copilot_instructions.md if it doesn't exist
    if [[ ! -f ".github/copilot_instructions.md" ]]; then
        download_file "${REPO_URL}/stubs/copilot_instructions.md" ".github/copilot_instructions.md"
        success "Created .github/copilot_instructions.md"
    else
        # Append session workflow section if not already present
        if ! grep -q "Session Workflow" .github/copilot_instructions.md 2>/dev/null; then
            echo "" >> .github/copilot_instructions.md
            echo "## Session Workflow" >> .github/copilot_instructions.md
            echo "" >> .github/copilot_instructions.md
            echo "This project uses session workflow for AI context continuity." >> .github/copilot_instructions.md
            echo "" >> .github/copilot_instructions.md
            echo "**Commands:**" >> .github/copilot_instructions.md
            echo "- \`/session.start --issue N\` - Start development session" >> .github/copilot_instructions.md
            echo "- \`/session.start \"text\"\` - Unstructured work" >> .github/copilot_instructions.md
            echo "- \`/session.start --spike \"text\"\` - Spike/research" >> .github/copilot_instructions.md
            echo "- \`/session.wrap\` - End session" >> .github/copilot_instructions.md
            echo "" >> .github/copilot_instructions.md
            echo "**Project context:**" >> .github/copilot_instructions.md
            echo "- \`.session/project-context/technical-context.md\` - Stack, build/test commands" >> .github/copilot_instructions.md
            echo "- \`.session/project-context/constitution-summary.md\` - Quality standards" >> .github/copilot_instructions.md
            success "Updated .github/copilot_instructions.md with session workflow section"
        else
            warn ".github/copilot_instructions.md already has session workflow section, skipping"
        fi
    fi
}

install_project_context() {
    info "Generating project context..."
    
    mkdir -p .session/project-context
    
    # Generate technical-context.md with detected values
    if [[ ! -f ".session/project-context/technical-context.md" ]]; then
        generate_technical_context
        success "Generated technical-context.md"
    else
        warn "technical-context.md already exists, skipping"
    fi
    
    # Generate constitution-summary.md based on project stage
    if [[ ! -f ".session/project-context/constitution-summary.md" ]]; then
        generate_constitution
        success "Generated constitution-summary.md"
    else
        warn "constitution-summary.md already exists, skipping"
    fi
}

generate_technical_context() {
    local output=".session/project-context/technical-context.md"
    
    cat > "$output" << EOF
# Technical Context

## Project Stage

**Stage**: ${DETECTED_STAGE}

<!-- Stage affects how strictly session agents enforce requirements -->
<!-- poc: flexible, discover as you go -->
<!-- mvp: recommended to have full context -->
<!-- production: required to have full context -->

## Project Root

**Path**: ${PROJECT_ROOT}

<!-- Always use relative paths from this root -->
<!-- Never use /root/ or other assumed absolute paths -->
EOF

    # Add environment section
    if [[ "$DETECTED_ENV" == "containerized" ]]; then
        cat >> "$output" << 'EOF'

## ⚠️ Containerized Environment

**This project runs in Docker containers.**

### ❌ NEVER DO THIS:
```bash
# WRONG - Commands may fail outside container
python main.py
python -m pytest
pip install anything
cd /root/...  # This path does not exist
```

### ✅ ALWAYS DO THIS:
```bash
# Start services
docker compose up --build -d

# Run commands inside container
docker compose exec <service> <command>

# View logs
docker compose logs -f <service>

# Restart after code changes
docker compose restart <service>
```
EOF
    fi

    # Add stack section
    cat >> "$output" << EOF

## Stack

**Language(s)**: ${DETECTED_STACK:-unknown}
EOF

    # Add development commands
    cat >> "$output" << 'EOF'

## Development Commands

```bash
EOF

    if [[ -n "$DETECTED_BUILD_CMD" ]]; then
        echo "# Build" >> "$output"
        echo -e "$DETECTED_BUILD_CMD" >> "$output"
        echo "" >> "$output"
    fi

    if [[ -n "$DETECTED_TEST_CMD" ]]; then
        echo "# Test" >> "$output"
        echo -e "$DETECTED_TEST_CMD" >> "$output"
        echo "" >> "$output"
    else
        echo "# Test" >> "$output"
        echo "# TODO: Add test command" >> "$output"
        echo "" >> "$output"
    fi

    if [[ -n "$DETECTED_LINT_CMD" ]]; then
        echo "# Lint" >> "$output"
        echo -e "$DETECTED_LINT_CMD" >> "$output"
    fi

    echo '```' >> "$output"

    # Add workflow order
    cat >> "$output" << 'EOF'

## Session Workflow Order

```
start → plan → execute → validate → publish → [MERGE PR] → finalize → wrap
```

**Key points:**
- `session.wrap` must run AFTER PR is merged
- `session.finalize` handles post-merge issue management
- Always run tests inside containers if containerized

EOF

    # Add footer
    cat >> "$output" << EOF
---

*Auto-generated by session-workflow installer v${VERSION}*
*Last detected: $(date -u +"%Y-%m-%dT%H:%M:%SZ")*
EOF
}

generate_constitution() {
    local output=".session/project-context/constitution-summary.md"
    
    case "$DETECTED_STAGE" in
        poc)
            cat > "$output" << 'EOF'
# Constitution (PoC Stage)

This project is in PoC stage. Formal constitution will emerge from discoveries.

## Working Principles

- **Learning over polish**: Prioritize discovery over production-quality
- **Document discoveries**: Capture learnings in session notes
- **Commit often**: Even incomplete work should be tracked
- **Test manually first**: Add automated tests only for validated patterns

## Code Guidelines

- Type hints: Recommended but not required
- Documentation: Inline comments for non-obvious logic
- Tests: Manual verification acceptable, automate keepers

## Emerging Patterns

<!-- Session agents will suggest patterns discovered during work -->
<!-- Move validated patterns here as they emerge -->

---

*This constitution will evolve as the project matures.*
EOF
            ;;
        mvp)
            cat > "$output" << 'EOF'
# Constitution (MVP Stage)

This project is in MVP stage. Core patterns are established.

## Quality Standards

- **Type safety**: Type hints required on public APIs
- **Testing**: Core paths must have tests
- **Documentation**: README and key docs must be current
- **Code review**: PRs require review before merge

## Code Guidelines

- Follow language-standard style guides
- Write tests for business logic
- Document public APIs
- Handle errors explicitly

## Architecture Principles

<!-- Document key architectural decisions here -->

---

*Update this as the project stabilizes.*
EOF
            ;;
        production)
            cat > "$output" << 'EOF'
# Constitution (Production Stage)

This project is in production. Quality is non-negotiable.

## Quality Standards

- **Type safety**: Full type coverage required
- **Testing**: Minimum 80% coverage, all paths tested
- **Documentation**: Comprehensive and current
- **Code review**: Mandatory reviews, CI must pass
- **Security**: Security review for sensitive changes

## Code Guidelines

- Strict adherence to style guides
- Comprehensive test coverage
- Full API documentation
- Explicit error handling with recovery
- Performance considerations documented

## Architecture Principles

<!-- Document immutable architectural decisions here -->

---

*Changes to this constitution require team consensus.*
EOF
            ;;
        *)
            # Fallback to generic stub
            download_file "${REPO_URL}/stubs/constitution-summary.md" "$output"
            ;;
    esac
}

install_agents() {
    info "Installing GitHub Copilot agents..."
    
    local agents=(
        "session.start.agent.md"
        "session.plan.agent.md"
        "session.execute.agent.md"
        "session.validate.agent.md"
        "session.publish.agent.md"
        "session.finalize.agent.md"
        "session.wrap.agent.md"
    )
    
    mkdir -p .github/agents
    
    for agent in "${agents[@]}"; do
        if [[ ! -f ".github/agents/${agent}" ]]; then
            download_file "${REPO_URL}/github/agents/${agent}" ".github/agents/${agent}"
        else
            warn "${agent} already exists, skipping"
        fi
    done
    
    success "Agents installed"
}

install_prompts() {
    info "Installing GitHub Copilot prompts..."
    
    local prompts=(
        "session.start.prompt.md"
        "session.plan.prompt.md"
        "session.execute.prompt.md"
        "session.validate.prompt.md"
        "session.publish.prompt.md"
        "session.finalize.prompt.md"
        "session.wrap.prompt.md"
    )
    
    mkdir -p .github/prompts
    
    for prompt in "${prompts[@]}"; do
        if [[ ! -f ".github/prompts/${prompt}" ]]; then
            download_file "${REPO_URL}/github/prompts/${prompt}" ".github/prompts/${prompt}"
        else
            warn "${prompt} already exists, skipping"
        fi
    done
    
    success "Prompts installed"
}

update_gitignore() {
    info "Updating .gitignore..."
    
    local patterns=(
        "# Session workflow"
        ".session/sessions/"
        ".session/ACTIVE_SESSION"
        ".session/validation-results.json"
    )
    
    # Create .gitignore if it doesn't exist
    touch .gitignore
    
    for pattern in "${patterns[@]}"; do
        if ! grep -qF "$pattern" .gitignore 2>/dev/null; then
            echo "$pattern" >> .gitignore
        fi
    done
    
    success ".gitignore updated"
}

create_sessions_dir() {
    # Create sessions directory structure
    mkdir -p .session/sessions
    
    # Create .gitkeep to ensure directory is tracked
    touch .session/sessions/.gitkeep
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Session Workflow Installer v${VERSION}   ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    check_prerequisites
    
    info "Installing session-workflow in $(pwd)"
    echo ""
    
    # Auto-detection phase
    echo -e "${BLUE}── Auto-Detection ──${NC}"
    detect_environment
    detect_stack
    detect_project_stage
    echo ""
    
    # Installation phase
    echo -e "${BLUE}── Installation ──${NC}"
    install_scripts
    install_templates
    install_docs
    install_bootstrap
    install_project_context
    install_agents
    install_prompts
    update_gitignore
    create_sessions_dir
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     Installation Complete! ✓           ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Detected:${NC}"
    echo "  Stage:       ${DETECTED_STAGE}"
    echo "  Environment: ${DETECTED_ENV}"
    echo "  Stack:       ${DETECTED_STACK}"
    echo ""
    echo -e "${BLUE}Generated:${NC}"
    echo "  .session/project-context/technical-context.md"
    echo "  .session/project-context/constitution-summary.md"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. Review generated context files (already populated!)"
    echo "  2. Start a session: /session.start 'Your goal'"
    echo ""
    echo -e "${BLUE}Quick start:${NC}"
    echo "  /session.start --issue 123       # Work on GitHub issue"
    echo "  /session.start 'Task'            # Unstructured work"
    echo "  /session.start --spike 'Research' # Spike/research"
    echo ""
}

main "$@"
