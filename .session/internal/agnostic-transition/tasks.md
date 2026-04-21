# Tasks: Agnostic Transition

## Phase 1: Preparation
- [ ] T001: Create branch `feature/agnostic-workflow`
- [ ] T002: Create internal session directory `.session/internal/agnostic-transition/`
- [ ] T003: Copy SDD artifacts (scope, spec, plan) to session directory

## Phase 2: Refactoring
- [ ] T004: Create root `agents/` directory
- [ ] T005: Move all agents from `github/agents/` to `agents/` and rename (`.agent.md` -> `.md`)
- [ ] T006: Delete `github/prompts/`
- [ ] T007: Update `AGENTS.md` and `README.md` to point to the new `agents/` directory

## Phase 3: Projection Engine
- [ ] T008: Implement tool detection in `install.sh`
- [ ] T009: Implement `project_agents` function in `install.sh` for Claude Code
- [ ] T010: Implement `project_agents` function in `install.sh` for Gemini CLI
- [ ] T011: Implement `project_agents` function in `install.sh` for GitHub Copilot CLI
- [ ] T012: Implement YAML frontmatter transformation logic

## Phase 4: State Synchronization
- [ ] T013: Create `session/scripts/bash/session-sync.sh`
- [ ] T014: Implement `update_file_with_markers` helper in `session-sync.sh`
- [ ] T015: Integrate `session-sync.sh` into `lib/session-state.sh`

## Phase 5: Handoff Protocol
- [ ] T016: Update `session.start.md` with agnostic handoff instructions
- [ ] T017: Update planning agents (`scope`, `spec`, `plan`, `task`) with agnostic handoffs
- [ ] T018: Update execution agents (`execute`, `validate`, `publish`, `review`) with agnostic handoffs
- [ ] T019: Update wrap agents (`finalize`, `wrap`) with agnostic handoffs

## Phase 6: Verification
- [ ] T020: Add unit tests for projection in `tests/run.sh`
- [ ] T021: Verify cross-tool sync manually
- [ ] T022: Run `shellcheck` on all modified scripts
- [ ] T023: Close internal session and merge branch
