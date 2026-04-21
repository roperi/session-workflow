# Agnostic Workflow Guide

This guide explains how Session Workflow integrates with various AI coding tools.

## The Projection Principle

Session Workflow maintains a single source of truth in the `agents/` directory. When you run `install.sh` or `update.sh`, the system detects your installed tools and "projects" these agents into tool-specific configurations:

- **Claude Code**: `.claude/commands/`
- **Gemini CLI**: `.gemini/agents/`
- **GitHub Copilot**: `.github/agents/`
- **Cursor**: `.cursorrules`

## Cross-Tool State Synchronization

Session Workflow uses a "Filesystem-as-State" approach. After every transition (e.g., scoping to planning), `session-sync.sh` updates tool-specific memory files:

- `CLAUDE.md`
- `.gemini/context.md`
- `.github/copilot-instructions.md`
- `.cursorrules`

This synchronization ensures that switching from one tool to another mid-session preserves the active `Session ID`, `Current Step`, and `Branch`.

## Unified Handoff Protocol

Agents do not chain themselves. Instead, they use a standard handoff:

1. **Complete Step**: Perform the agent's specific task.
2. **Postflight**: Run `session-postflight.sh --step <step> --json`.
3. **Transition**: Parse `valid_next_steps` and announce the next command in a tool-agnostic format (e.g., "Ready for `session.plan`. Invoke with your tool's native command").
4. **Tool-Specific Invocation**:
   - **Copilot**: `task(agent: "session.plan", ...)`
   - **Claude**: `/session.plan`
   - **Gemini**: `session.plan`

This keeps the orchestration flow identical while allowing each model to use its most natural interaction pattern.
