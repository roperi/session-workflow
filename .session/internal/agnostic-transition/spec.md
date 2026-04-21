# Specification: Agnostic Transition for session-workflow

## Overview
Transform `session-workflow` into an agent-agnostic toolkit that can project its logic into any supported AI tool (Claude Code, Gemini CLI, Copilot CLI, Cursor) while maintaining a central source of truth and cross-tool state synchronization.

## User Stories
- **US1: Centralized Logic** - As a developer, I want to maintain only one set of agent instructions so that I don't have to duplicate work for different tools.
- **US2: Tool Projection** - As a user, I want `install.sh` to automatically configure my workspace for whatever AI tool I am currently using.
- **US3: Seamless Handoff** - As an AI agent, I want a standard way to signal the next workflow step that works regardless of whether I'm running in Claude or Copilot.
- **US4: Cross-Tool Resumption** - As a developer, I want to be able to start a session in one tool and finish it in another without losing the workflow's place.

## Functional Requirements

### 1. Centralized Source
- All agent definitions must live in `/agents/*.md`.
- No tool-specific logic should be hardcoded into the core agent Markdown (beyond standardized handoff instructions).

### 2. Projection Engine (`install.sh`)
- Detect the presence of:
    - `.claude/` (Claude Code)
    - `.gemini/` or `~/.gemini/` (Gemini CLI)
    - `~/.copilot/` (GitHub Copilot CLI)
    - `.cursorrules` (Cursor)
- Project agents by:
    - Mapping YAML frontmatter (e.g., `description` -> `description`, `tools` -> `tools`).
    - Adding tool-specific file extensions (e.g., `.agent.md` for Copilot).
    - Writing to the tool's native configuration directory.

### 3. Abstract Handoff Protocol
- Agents must parse the JSON output of `session-postflight.sh`.
- The instruction set must include a rule: "If `valid_next_steps` is not empty, suggest the next command using the syntax of the current tool."

### 4. Cross-Tool State Synchronization
- Implement `session/scripts/bash/session-sync.sh`.
- It must update state in:
    - `CLAUDE.md` (for Claude Code)
    - `.gemini/context.md` (for Gemini CLI)
    - `.github/copilot-instructions.md` (for GitHub Copilot)
- Use standard markers: `<!-- SESSION_WORKFLOW_START --> ... <!-- SESSION_WORKFLOW_END -->`.

## Acceptance Criteria

### AC1: Agent Projection
- **Given** I have a workspace with `.claude/` and `agents/session.start.md`.
- **When** I run `install.sh`.
- **Then** `.claude/commands/session.start.md` should be created with the correct instructions.

### AC2: Cross-Tool State Sync
- **Given** a session is active with `current_step: scope`.
- **When** `session-postflight.sh --step scope` is run.
- **Then** `CLAUDE.md` and `.gemini/context.md` (if they exist) should be updated with `Current Step: scope (completed)`.

### AC3: Agnostic Handoff
- **Given** an agent is running in Gemini CLI.
- **When** the agent completes its task.
- **Then** it should suggest the next step using `/session.<next_step>` or similar Gemini-native syntax.

## Edge Cases
- **Missing Tool**: If a tool is not detected, `install.sh` should skip its projection without error.
- **Dirty State**: `session-sync.sh` must not overwrite manual instructions outside the managed markers.
- **Multiple Tools**: If multiple tools are present, all should be synced simultaneously.

## Verification Checklist
- [ ] `agents/` contains all 16 agents from `github/agents/`.
- [ ] `install.sh` detects Claude, Gemini, Copilot, and Cursor.
- [ ] `session-sync.sh` correctly parses `state.json` and updates Markdown files.
- [ ] Handoff instructions are verified in at least two different tools.
- [ ] `github/` directory is removed.
