# AI Onboarding & Context

Welcome, AI Agent. This project uses **Spec-Driven Development (SDD)**. Your goal is to maintain architectural integrity while enabling tool-agnostic coding workflows.

## 1. Project Overview
- **What**: A Bash-based framework for AI context continuity and session orchestration.
- **Stack**: Bash 4.4+, `jq`, `git`.
- **Agnostic Principle**: Logic lives in `agents/` and is projected into tool-native commands (Claude, Gemini, Copilot).

## 2. User Capabilities (Reference)
This section describes how an **end-user** interacts with the tool once installed. This documentation is required for capability verification.

- **Standard Workflows**: Users follow the chain: `start → scope → spec → plan → tasks → execute → validate → wrap`.
- **GitHub Integration**: Users can ask the agent to "Start a session for issue [N]" to link work directly to GitHub.
- **Brainstorming**: Users can ask for a `session.start --brainstorm` session for fuzzy goals.
- **Maintenance workflow**: Ask the agent to "Run a maintenance session" (start → execute → STOP).
- **Debug workflow**: Ask to "Start a debug session" (start → execute → STOP).
- **Operational workflow**: Ask to "Run an operational session" (start → execute → STOP).
- **Audit**: Users can run `./.session/scripts/bash/session-audit.sh --all --summary` directly in their shell to check session health.
- **Continuity**: The `next.md` artifact is the primary handoff tool between sessions.

## 3. Maintainer Workflow (Development)
**IMPORTANT**: Do NOT use slash commands (e.g. `/session.start`) or agent mentions (e.g. `@session.start`) when working *inside* this repository. Maintainers use direct script execution to avoid circular dependencies.

1. **Initiate Session**:
   ```bash
   bash session/scripts/bash/session-start.sh "Description of work"
   # For fuzzy goals:
   bash session/scripts/bash/session-start.sh --brainstorm "Fuzzy goal"
   ```
2. **Workflow Transitions**:
   ```bash
   bash session/scripts/bash/session-preflight.sh --step <step>
   bash session/scripts/bash/session-postflight.sh --step <step> --json
   ```
3. **Context Sync**:
   ```bash
   bash session/scripts/bash/session-sync.sh
   ```

## 4. Validation & Guardrails
- **No Self-Installation**: NEVER run `install.sh` inside this repository.
- **Test Suite**: Always verify changes with `bash tests/run.sh`.
- **Shellcheck**: All scripts must pass `shellcheck`.
