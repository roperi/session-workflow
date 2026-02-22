#!/usr/bin/env bash
# update.sh - Update session-workflow to latest version
# https://github.com/roperi/session-workflow

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

REPO_URL="https://raw.githubusercontent.com/roperi/session-workflow/main"
VERSION="2.5.0"

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
# Update Functions
# ============================================================================

update_scripts() {
    info "Updating session scripts..."

    local scripts=(
        "session-common.sh"
        "session-start.sh"
        "session-wrap.sh"
        "session-validate.sh"
        "session-publish.sh"
        "session-finalize.sh"
        "session-preflight.sh"
        "session-handoff-list.sh"
    )

    local lib_scripts=(
        "session-output.sh"
        "session-paths.sh"
        "session-tasks.sh"
        "session-git.sh"
        "session-state.sh"
    )

    for script in "${scripts[@]}"; do
        download_file "${REPO_URL}/session/scripts/bash/${script}" ".session/scripts/bash/${script}"
        chmod +x ".session/scripts/bash/${script}"
    done

    mkdir -p .session/scripts/bash/lib
    for script in "${lib_scripts[@]}"; do
        download_file "${REPO_URL}/session/scripts/bash/lib/${script}" ".session/scripts/bash/lib/${script}"
    done

    success "Scripts updated"
}

update_templates() {
    info "Updating templates..."
    download_file "${REPO_URL}/session/templates/session-notes.md" ".session/templates/session-notes.md"
    download_file "${REPO_URL}/session/templates/tasks-template.md" ".session/templates/tasks-template.md"
    success "Templates updated"
}

update_docs() {
    info "Updating documentation..."
    download_file "${REPO_URL}/README.md" ".session/docs/README.md"
    download_file "${REPO_URL}/session/docs/testing.md" ".session/docs/testing.md"
    download_file "${REPO_URL}/session/docs/shared-workflow.md" ".session/docs/shared-workflow.md"
    success "Documentation updated"
}

update_agents() {
    info "Updating GitHub Copilot agents..."

    local agents=(
        "session.start.agent.md"
        "session.plan.agent.md"
        "session.task.agent.md"
        "session.execute.agent.md"
        "session.validate.agent.md"
        "session.publish.agent.md"
        "session.finalize.agent.md"
        "session.wrap.agent.md"
        "session.clarify.agent.md"
        "session.analyze.agent.md"
        "session.checklist.agent.md"
        "session.brainstorm.agent.md"
        "session.compound.agent.md"
    )

    for agent in "${agents[@]}"; do
        download_file "${REPO_URL}/github/agents/${agent}" ".github/agents/${agent}"
    done

    success "Agents updated"
}

update_prompts() {
    info "Updating GitHub Copilot prompts..."

    local prompts=(
        "session.start.prompt.md"
        "session.plan.prompt.md"
        "session.task.prompt.md"
        "session.execute.prompt.md"
        "session.validate.prompt.md"
        "session.publish.prompt.md"
        "session.finalize.prompt.md"
        "session.wrap.prompt.md"
        "session.clarify.prompt.md"
        "session.analyze.prompt.md"
        "session.checklist.prompt.md"
        "session.brainstorm.prompt.md"
        "session.compound.prompt.md"
    )

    for prompt in "${prompts[@]}"; do
        download_file "${REPO_URL}/github/prompts/${prompt}" ".github/prompts/${prompt}"
    done

    success "Prompts updated"
}

update_bootstrap_sections() {
    info "Updating Session Workflow sections in AGENTS.md and copilot-instructions.md..."

    # The canonical section content — kept in sync with stubs/
    local section
    section=$(cat << 'SECTION'
## Session Workflow

This project uses session workflow for AI context continuity.
See `.session/docs/README.md` for quick reference.

**Agents:**
- `invoke session.start --issue N` - Development session from GitHub issue
- `invoke session.start --spec 001-feature` - Spec Kit session
- `invoke session.start "description"` - Development session (positional description)
- `invoke session.start --spike "description"` - Spike/research (no PR)
- `invoke session.start --resume` - Resume active session
- `invoke session.finalize` - Post-merge cleanup (after PR merge)
- `invoke session.wrap` - End session

**Project context:**
- `.session/project-context/technical-context.md` - Stack, build/test commands
- `.session/project-context/constitution-summary.md` - Quality standards
SECTION
)

    for file in "AGENTS.md" ".github/copilot-instructions.md"; do
        if [[ ! -f "$file" ]]; then
            warn "$file not found, skipping"
            continue
        fi

        if grep -q "^## Session Workflow" "$file" 2>/dev/null; then
            # Replace existing block: strip from ## Session Workflow up to (but not
            # including) the next ## heading, or to EOF if it's the last section.
            local tmp
            tmp=$(mktemp)
            awk '
                /^## Session Workflow/ { skip=1; next }
                /^## / && skip        { skip=0 }
                !skip                 { print }
            ' "$file" > "$tmp"
            # Remove trailing blank lines, then append refreshed section
            printf '%s\n\n%s\n' "$(sed -e 's/[[:space:]]*$//' "$tmp" | awk 'NF{found=NR} {lines[NR]=$0} END{for(i=1;i<=found;i++) print lines[i]}')" "$section" > "$file"
            rm -f "$tmp"
            success "Replaced Session Workflow section in $file"
        else
            printf '\n%s\n' "$section" >> "$file"
            success "Added Session Workflow section to $file"
        fi
    done
}



main() {
    # Parse --version flag to pin download to a specific release tag
    local arg_version=""
    local args=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                arg_version="$2"
                shift 2
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done
    set -- "${args[@]+"${args[@]}"}"

    if [[ -n "$arg_version" ]]; then
        REPO_URL="https://raw.githubusercontent.com/roperi/session-workflow/refs/tags/${arg_version}"
        info "Pinned to version ${arg_version} (${REPO_URL})"
    fi

    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Session Workflow Updater v${VERSION}     ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    # Check if session-workflow is installed
    if [[ ! -d ".session/scripts/bash" ]]; then
        error "Session workflow not installed. Run install.sh first."
    fi
    
    info "Updating session-workflow in $(pwd)"
    echo ""
    
    update_scripts
    update_templates
    update_docs
    update_agents
    update_prompts
    update_bootstrap_sections
    
    # Note: We don't update project-context (user customized)
    warn "Skipping project-context/ (user-customized files)"
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        Update Complete! ✓              ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
}

main "$@"
