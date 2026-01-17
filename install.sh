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
    info "Installing session docs..."
    
    # Only install internal session docs (quick reference)
    mkdir -p .session/docs
    download_file "${REPO_URL}/session/docs/README.md" ".session/docs/README.md"
    download_file "${REPO_URL}/session/docs/testing.md" ".session/docs/testing.md"
    
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
            echo "- \`/session.start --goal \"text\"\` - Start unstructured session" >> AGENTS.md
            echo "- \`/session.start --experiment --goal \"text\"\` - Start experiment" >> AGENTS.md
            echo "- \`/session.start --advisory --goal \"text\"\` - Quick question" >> AGENTS.md
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
            echo "- \`/session.start --goal \"text\"\` - Unstructured work" >> .github/copilot_instructions.md
            echo "- \`/session.start --experiment --goal \"text\"\` - Experiment/spike" >> .github/copilot_instructions.md
            echo "- \`/session.start --advisory --goal \"text\"\` - Quick question" >> .github/copilot_instructions.md
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
    echo "Next steps:"
    echo "  1. Customize .session/project-context/ for your project"
    echo "  2. Review AGENTS.md and .github/copilot_instructions.md"
    echo "  3. Start a session: /session.start --goal 'Your goal'"
    echo ""
    echo "Quick start:"
    echo "  /session.start --issue 123       # Work on GitHub issue"
    echo "  /session.start --goal 'Task'     # Unstructured work"
    echo "  /session.start --advisory --goal 'Question'  # Quick question"
    echo ""
}

main "$@"
