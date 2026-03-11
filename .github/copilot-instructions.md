# GitHub Copilot Instructions

## What This Project Is

Session Workflow is an AI-assisted development workflow system written in Bash. It provides session tracking, context continuity across AI context resets, and a structured agent chain for specification-driven development. It works standalone or integrates with GitHub Spec Kit.

**Core architecture**: Bash scripts handle mechanical work (state, JSON, git); Markdown agent files handle AI reasoning; JSON state files maintain continuity across sessions.

## Build, Test, and Lint

```bash
# Lint all bash scripts
shellcheck session/scripts/bash/*.sh session/scripts/bash/lib/*.sh install.sh update.sh tests/run.sh

# Run full test suite
bash tests/run.sh

# Run tests with verbose output
TEST_VERBOSE=1 bash tests/run.sh

# Keep temp directory after tests (for debugging)
TEST_KEEP_TMP=1 bash tests/run.sh
```

Tests are a single sequential harness in `tests/run.sh` — there is no single-test runner. The harness creates isolated temp git repos, runs numbered scenarios, and uses custom assertions (`assert_eq`, `assert_file_exists`).

## Architecture

### Script Layers

- **`session/scripts/bash/*.sh`** — Top-level workflow scripts (start, wrap, validate, publish, etc.)
- **`session/scripts/bash/lib/`** — Shared libraries sourced via `session-common.sh` in dependency order:
  1. `session-output.sh` — Colors, `print_*` helpers, `json_escape()`
  2. `session-paths.sh` — Path constants, schema version constants, session ID generation
  3. `session-tasks.sh` — Task counting, task file resolution
  4. `session-git.sh` — Git prerequisites, PR helpers
  5. `session-state.sh` — Schema validation, workflow FSM, state transitions

All scripts source `session-common.sh` which aggregates the libraries. Never source individual libs directly.

### Agent System (15 agents)

Agents live in `github/agents/session.*.agent.md` with corresponding `github/prompts/session.*.prompt.md` link files for IDE integration.

**Development workflow chain**: `start → [brainstorm →] [scope →] [spec →] plan → task → execute → validate → publish → finalize → wrap`

**Spike workflow** (no PR): `start → [scope →] plan → task → execute → wrap`

**Maintenance workflow** (minimal): `start → execute → wrap`

### Workflow State Machine

Transitions are defined in `lib/session-state.sh` via `WORKFLOW_TRANSITIONS` associative array and enforced by `session-preflight.sh`. Each step transitions through `in_progress → completed|failed`. Step history is append-only in `state.json`.

### JSON Schemas

Two mutable JSON files per session in `.session/sessions/{id}/`:

- **`session-info.json`** (v2.2) — Immutable metadata: session type (`github_issue|speckit|unstructured`), workflow (`development|spike|maintenance`), stage (`poc|mvp|production`)
- **`state.json`** (v1.1) — Mutable state: `current_step`, `step_status`, append-only `step_history[]`

Schema version constants live in `lib/session-paths.sh` (`SESSION_INFO_SCHEMA_VERSION`, `STATE_SCHEMA_VERSION`).

For speckit sessions, `session-info.json` uses `spec_dir` (value: `"specs/{SPEC_DIR}"`), not `feature`.

## Bash Conventions

- Every script starts with `set -euo pipefail`
- Constants/globals are `UPPERCASE`; functions are `lowercase_with_underscores`
- Function naming: `get_*`, `set_*`, `ensure_*`, `check_*`, `validate_*`
- JSON output uses standardized envelope: `{"status": "ok"|"error"|"warning", ...}`
- Use `jq --arg varname "$value"` for safe JSON construction — never `jq -Rs '.' | sed`
- Error messages go to stderr; structured JSON goes to stdout
- Section headers use `# ====...====` separators
- Color output: `print_success()`, `print_error()`, `print_warning()`, `print_info()` with emoji prefixes

## Shellcheck

The `.shellcheckrc` disables four rules project-wide:
- `SC1091` — Sourced files use runtime paths
- `SC2034` — Cross-file shared variables appear unused
- `SC2129` — `{}` grouping for redirects is acceptable
- `SC2001` — `sed` is preferred over `${var//s/r}` for multichar patterns

## Session Workflow

This project uses session workflow for AI context continuity.

**Agents:**
- `invoke session.start --issue N` — Development session from GitHub issue
- `invoke session.start --spec 001-feature` — Spec Kit session
- `invoke session.start "description"` — Development session (positional description)
- `invoke session.start --spike "description"` — Spike/research (no PR)
- `invoke session.start --resume` — Resume active session
- `invoke session.finalize` — Post-merge cleanup (after PR merge)
- `invoke session.wrap` — End session

**Project context:**
- `.session/project-context/technical-context.md` — Stack, build/test commands
- `.session/project-context/constitution-summary.md` — Quality standards
