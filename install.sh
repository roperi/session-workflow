#!/usr/bin/env bash
# install.sh - Install session-workflow in current repository
# https://github.com/roperi/session-workflow

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

REPO_URL="https://raw.githubusercontent.com/roperi/session-workflow/main"
VERSION="1.0.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    info "Installing documentation..."
    
    mkdir -p .session/docs
    download_file "${REPO_URL}/session/docs/README.md" ".session/docs/README.md"
    download_file "${REPO_URL}/session/docs/testing.md" ".session/docs/testing.md"
    
    success "Documentation installed"
}

install_project_context() {
    info "Setting up project context..."
    
    mkdir -p .session/project-context
    
    # Only create stubs if files don't exist (never overwrite)
    if [[ ! -f ".session/project-context/constitution-summary.md" ]]; then
        download_file "${REPO_URL}/stubs/constitution-summary.md" ".session/project-context/constitution-summary.md"
        success "Created constitution-summary.md stub"
    else
        warn "constitution-summary.md already exists, skipping"
    fi
    
    if [[ ! -f ".session/project-context/technical-context.md" ]]; then
        download_file "${REPO_URL}/stubs/technical-context.md" ".session/project-context/technical-context.md"
        success "Created technical-context.md stub"
    else
        warn "technical-context.md already exists, skipping"
    fi
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
    echo -e "${BLUE}║     Session Workflow Installer v${VERSION}    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    check_prerequisites
    
    info "Installing session-workflow in $(pwd)"
    echo ""
    
    install_scripts
    install_templates
    install_docs
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
    echo "Next steps:"
    echo "  1. Customize .session/project-context/ for your project"
    echo "  2. Start a session: /session.start --goal 'Your goal'"
    echo "  3. See docs: .session/docs/README.md"
    echo ""
    echo "Quick start:"
    echo "  /session.start --issue 123       # Work on GitHub issue"
    echo "  /session.start --goal 'Task'     # Unstructured work"
    echo "  /session.start --advisory --goal 'Question'  # Quick question"
    echo ""
}

main "$@"
