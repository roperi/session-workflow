# AI Onboarding & Context

Welcome, AI Agent. This project uses **Spec-Driven Development (SDD)**. Your goal is to maintain architectural integrity while enabling tool-agnostic coding workflows.

## 1. Project Overview
- **What**: A Bash-based framework for AI context continuity and session orchestration.
- **Stack**: Bash 4.4+, `jq`, `git`. No external heavy dependencies.
- **Agnostic Principle**: Logic lives in `agents/` and is projected into tool-native commands (Claude, Gemini, Copilot).

## 2. Validation & Build Rigor
- **Test Suite**: `bash tests/run.sh`. 
- **Pre-commit**: The repo uses `shellcheck` and automated tests. NEVER commit without verifying that `bash tests/run.sh` passes 100%.
- **No Self-Installation**: NEVER run `install.sh` inside this repository. Work by calling scripts directly from `session/scripts/bash/`.

## 3. Major Architectural Elements
- `agents/`: Source of truth for all workflow logic (Markdown).
- `install.sh` / `update.sh`: The "Projection Engine" that transforms and distributes agents.
- `session/scripts/bash/lib/`: Core logic for state machine and git orchestration.
- `.maintainer/`: Private workspace for SDD artifacts and checklists (Ignored by Git).

## 4. Operational Guardrails
- **Trust the State**: State is maintained in `.session/sessions/active/state.json`. 
- **Managed Markers**: Use `<!-- SESSION_WORKFLOW_START -->` blocks when updating memory files (CLAUDE.md, etc.).
- **Sequential SDD**: Follow the chain: `scope → spec → plan → tasks → execute → validate → wrap`. Do not skip steps.

## 5. Workflow Definitions (Reference)
- **Maintenance workflow**: Lightweight chain (start → execute → STOP). Skips branch, planning, and PR.
- **Debug workflow**: Investigation chain (start → execute → STOP).
- **Operational workflow**: Runtime loop (start → execute → STOP). Uses a feature branch but skips planning.

- **next.md Artifacts**: Primary handoff artifact.

## 6. Development Instructions
1. **Bootstrap**: Call `bash session/scripts/bash/session-start.sh` directly to initiate internal SDD.
    - Use `session.start --brainstorm` for fuzzy goals.
2. **Sync**: Use `bash session/scripts/bash/session-sync.sh` to update your own memory files (e.g., `.gemini/context.md`).
3. **Verify**: Always run `shellcheck` on scripts before testing.
4. **Audit**: Run `./.session/scripts/bash/session-audit.sh --all --summary` to check progress.
