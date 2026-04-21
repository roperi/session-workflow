# Tasks: Agnostic Transition

## Phase 1: Preparation
- [x] T001: Create branch `feature/agnostic-workflow`
- [x] T002: Create internal session directory `.session/internal/agnostic-transition/`
- [x] T003: Copy SDD artifacts (scope, spec, plan) to session directory

## Phase 2: Refactoring
- [x] T004: Create root `agents/` directory
- [x] T005: Move all agents from `github/agents/` to `agents/` and rename (`.agent.md` -> `.md`)
- [x] T006: Delete `github/prompts/`
- [x] T007: Update `AGENTS.md` and `README.md` to point to the new `agents/` directory

## Phase 3: Projection Engine
- [x] T008: Implement tool detection in `install.sh`
- [x] T009: Implement `project_agents` function in `install.sh` for Claude Code
- [x] T010: Implement `project_agents` function in `install.sh` for Gemini CLI
- [x] T011: Implement `project_agents` function in `install.sh` for GitHub Copilot CLI
- [x] T012: Implement YAML frontmatter transformation logic

## Phase 4: State Synchronization
- [x] T013: Create `session/scripts/bash/session-sync.sh`
- [x] T014: Implement `update_file_with_markers` helper in `session-sync.sh`
- [x] T015: Integrate `session-sync.sh` into `lib/session-state.sh`

## Phase 5: Handoff Protocol
- [x] T016: Update `session.start.md` with agnostic handoff instructions
- [x] T017: Update planning agents (`scope`, `spec`, `plan`, `task`) with agnostic handoffs
- [x] T018: Update execution agents (`execute`, `validate`, `publish`, `review`) with agnostic handoffs
- [x] T019: Update wrap agents (`finalize`, `wrap`) with agnostic handoffs

## Phase 6: Verification
- [x] T020: Add unit tests for projection in `tests/run.sh`
- [x] T021: Verify cross-tool sync manually
- [x] T022: Run `shellcheck` on all modified scripts
- [x] T023: Close internal session and merge branch
