# Scope: Agnostic Transition for session-workflow

## Problem Statement
`session-workflow` is currently heavily biased towards GitHub Copilot CLI, specifically in its directory structure (`.github/agents`), its handoff mechanisms (`task` tool calls), and its documentation. This prevents users of other AI tools (Claude Code, Gemini CLI, Cursor, etc.) from leveraging the workflow effectively.

## Objectives
- Decouple agent definitions from GitHub-specific paths.
- Enable automatic "projection" of agents into tool-specific configurations.
- Implement a cross-tool state synchronization mechanism.
- Maintain full backward compatibility with GitHub Copilot CLI.

## In Scope
- Refactoring `github/agents/` to a tool-agnostic root directory.
- Updating `install.sh` to detect and support Claude Code, Gemini CLI, and GitHub Copilot.
- Designing a tool-agnostic "Handoff Protocol" for agents.
- Creating a `session-sync.sh` script to mirror state across tool-specific memory files (`CLAUDE.md`, `.gemini/context.md`, etc.).
- Updating documentation to reflect agnostic usage.

## Out of Scope
- Implementing direct integration with proprietary APIs of other tools (unless through standard filesystem/CLI interfaces).
- Supporting every possible AI tool (focus on the "Big 4": Claude, Gemini, Copilot, Cursor).
- Changing the core Bash logic or JSON schemas (unless strictly required for agnosticism).

## Success Criteria
1. Agents can be "installed" into Claude Code and Gemini CLI without manual file movement.
2. A session started in one tool can be resumed in another tool with correct context.
3. GitHub Copilot CLI continues to function with zero regression.
4. All agents follow a standardized, tool-neutral handoff protocol.
