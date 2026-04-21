# Implementation Plan: Agnostic Transition (SDD Version)

## Objective
Refactor `session-workflow` into an agent-agnostic system following the SDD specification (`spec.md`).

## Phase 1: Preparation & Branching
1. Create and switch to `feature/agnostic-workflow` branch.
2. Initialize the internal session directory: `.session/internal/agnostic-transition/`.
3. Copy `scope.md` and `spec.md` to the internal session directory for tracking.

## Phase 2: Directory Refactoring
1. **Move Agents**:
    ```bash
    mkdir -p agents
    mv github/agents/*.agent.md agents/
    # Rename for cleaner agnostic naming
    for f in agents/*.agent.md; do mv "$f" "${f%.agent.md}.md"; done
    ```
2. **Remove Redundant Directories**:
    - Remove `github/prompts/` (logic is in agents).
    - Keep `github/` empty for now to ensure no regressions during transition.

## Phase 3: Enhanced Projection Engine (`install.sh`)
1. **Tool Detection**:
    - Add functions to detect `.claude/`, `.gemini/`, `~/.copilot/`, and `.cursorrules`.
2. **Projection Logic**:
    - Implement a `project_agents()` function that iterates over `agents/*.md`.
    - For each tool detected:
        - **GitHub Copilot**: Write to `.github/agents/*.agent.md`. Generate `.prompt.md` symlinks.
        - **Claude Code**: Write to `.claude/commands/*.md`.
        - **Gemini CLI**: Write to `.gemini/agents/*.md`.
        - **Cursor**: Update `.cursorrules` with instructions to use the agents.
3. **Template Logic**:
    - Use a simple `sed` or `awk` script to transform YAML frontmatter between formats if needed.

## Phase 4: Cross-Tool State Synchronization
1. **Create `session-sync.sh`**:
    - Source `session-common.sh`.
    - Load `state.json`.
    - Extract `session_id`, `current_step`, `step_status`, `workflow`.
    - Format a "Workflow Status" Markdown block.
2. **Implement File Update Logic**:
    - Function `update_file_with_markers(file, block)` that uses `sed` or `perl` to replace content between `<!-- SESSION_WORKFLOW_START -->` and `<!-- SESSION_WORKFLOW_END -->`.
    - If markers are missing, append them to the end of the file.
3. **Integration**:
    - Add `session-sync.sh` call to `set_workflow_step()` in `lib/session-state.sh` so it runs automatically after every transition.

## Phase 5: Handoff Protocol Updates
1. **Update Agent Instructions**:
    - Systematically update all 16 agents to use generalized handoff language.
    - Example: "Transition: suggest the next command (e.g., `/session.plan` or `@session.plan`)."

## Verification
1. **Unit Tests**:
    - Update `tests/run.sh` to verify that `install.sh` creates the expected directories and files for simulated tool environments.
2. **Integration Tests**:
    - Manually verify a session "handoff" between a simulated Claude environment and a Copilot environment.
3. **Regression Tests**:
    - Ensure `shellcheck` still passes on all modified scripts.
