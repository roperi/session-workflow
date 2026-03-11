# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

- **NEW (#52)**: Centralized chain orchestration in `session.start` — session.start now orchestrates the entire workflow chain (`scope → spec → plan → task → execute → validate → publish → review → finalize → wrap`) in a single user invocation; sub-agents invoked via task tool with proper context isolation; all agent-to-agent handoffs removed (sub-agents return results instead of invoking next step); session.start handles Copilot review cycle directly (request review, wait, address comments, merge); `session-postflight.sh` script added (symmetric to preflight, marks steps completed/failed); all 9 chain agents updated with `⛔ SCOPE BOUNDARY` sections and preflight+postflight patterns; `session-start.sh` records `start` step as completed in state.json at creation; auto-resume requires explicit `--resume` flag; new reference doc `session/docs/copilot-cli-mechanics.md`
- **NEW (#49)**: Append-only `step_history[]` array in `state.json` — records every workflow step with `step`, `status`, `started_at`, `ended_at`, `forced` fields; preflight appends `in_progress` entries; postflight updates to `completed`/`failed`; survives wrap (preserved on session completion); state schema version bumped to 1.1
- **NEW (#48)**: Speckit integration refinement and SDD positioning — README restructured with SDD alignment table mapping session-workflow agents to Spec Kit commands; `spec_dir` field replaces `feature` in session-info.json for speckit sessions; standalone vs Spec Kit usage guidance
- **NEW (#39)**: Connect spec acceptance criteria to validation — `session-validate.sh` Check 4 parses `spec.md` verification checklist; stage-aware enforcement (poc=skip, mvp=warn, production=block); `resolve_spec_file()` supports both standalone and speckit paths
- **FIX (#40)**: Replace passive handoff language with directive chaining across all 9 chain agents — `session.start` gets chaining intent detection; auto-chain agents use "Proceed now" directives; human-gated agents keep review gates; externally-gated agents document gates explicitly
- **NEW (#38)**: Add scope and spec steps to workflow state machine — `WORKFLOW_TRANSITIONS` in `lib/session-state.sh` updated with `start→scope`, `scope→spec`, `scope→plan`, `spec→plan` transitions; `check_workflow_transition()` enforces ordering with deprecation warnings for skipped steps
- **NEW (#37)**: Extract plan into standalone `plan.md` artifact — plan output written to `{session_dir}/plan.md` instead of inline in agent output; enables downstream agents to read plan as structured input
- **NEW (#36)**: `session.spec` agent — formal specification step between scope and plan; produces `{session_dir}/spec.md` with user stories, acceptance criteria (Given/When/Then), edge cases, error scenarios, non-functional requirements, `[NEEDS CLARIFICATION]` markers, and verification checklist; reads `scope.md` as primary input; development workflow only (spike skips spec); `session.plan` reads spec.md as planning contract when present
- **NEW (#35)**: `session.scope` agent — problem boundary definition step before spec/plan; produces `{session_dir}/scope.md` with in-scope items, out-of-scope items, success criteria, and open questions; interactive dialogue-driven; both development and spike workflows

## [2.6.0] - 2026-02-22

- **FIX (#31)**: `session.brainstorm` absorbed as a proper workflow step — fixes state-machine poisoning bug where calling `--step plan` inside brainstorm would block subsequent `session.plan` runs; brainstorm output now written to `{session_dir}/brainstorm.md`; `session.plan` reads it from there; `session.wrap` daily summary moved to `{session_dir}/final-summary.md`
- **CHANGE**: All `/session.X` slash commands replaced with `invoke session.X` throughout agents, scripts, stubs, installer and docs — adapts to Copilot CLI deprecating custom slash commands; `invoke` keyword triggers agent loading automatically
- **NEW**: `update.sh --dry-run` flag — shows every file that would be downloaded and every bootstrap section that would be replaced/added, without making any changes
- **FIX**: `update.sh` now surgically replaces the `## Session Workflow` section in `AGENTS.md` and `.github/copilot-instructions.md` using awk, instead of only appending when missing — stale content is correctly refreshed on update
- **DOCS**: README `## Updating` section added; compatibility section updated (all models — OpenAI, Anthropic, Google)
- **NEW (#32)**: `session-cleanup.sh` — removes errant files/dirs from `.session/` tree automatically: unknown items at `.session/` root (allowlist-based), misplaced session dirs (moved to correct `sessions/YYYY-MM/` path), orphaned files under `sessions/`, and empty legacy dirs. Integrated into `session.wrap` as step 7. `session.publish` now writes `pr_url.txt` / `pr-summary.md` into `{session_dir}/` to prevent recurrence.

## [2.5.0] - 2026-02-21

Full audit of the codebase (issue #19). 28 findings across security, architecture, maintainability, correctness, and testing — all resolved.

- **FIX (security)**: Command allowlist in `session-validate.sh`; `json_escape` applied to all user-controlled input; scoped agent tool lists; prompt-injection guardrails added to 5 agents; `CODEOWNERS` added; `--version` flag for pinned installs (#25)
- **FIX (architecture)**: `schema_version` field on all JSON files; `validate_schema_version()` helper; atomic writes (mktemp + mv) across all scripts; new `session/docs/schema-versioning.md` reference (#26)
- **REFACTOR**: `session-common.sh` (1004 LOC) split into 5 focused sub-libraries under `lib/`; awk `in` reserved-word bug fixed; SC2155 fixes (#27)
- **FIX (correctness)**: `PHASE_CLOSED` unbound-variable crash fixed; `FEATURE_ID` read from correct field; `count_tasks` phase-template fallback; dynamic default-branch detection; missing-option guards; blank-line-free JSON in agent instructions (#28)
- **FIX (testing/CI)**: shellcheck added to CI pipeline; 12 shellcheck warnings resolved; test suite expanded from 9 → 12 tests with regression coverage; stale docs updated (#29)

## [2.4.1] - 2026-02
- **FIX**: Restore GitHub Copilot custom agent compatibility
  - Removed unsupported YAML frontmatter `handoffs` (and prior `send: true|false` semantics)
  - Agents now suggest the next `/session.*` command (manual chaining)
  - Prompt link files must contain only:
    ```yaml
    ---
    agent: session.<name>
    ---
    ```
  - Added missing YAML frontmatter for `session.analyze`, `session.checklist`, `session.clarify`
- **DOCS**: Remove irrelevant Speckit references and update docs to match the manual-chaining model
- **FIX**: Correct Copilot instructions filename to `.github/copilot-instructions.md`

## [2.4.0] - 2026-01
- **NEW**: Project stage flag `--stage poc|mvp|production`
- **NEW**: Stage-aware validation (poc=warnings, mvp=standard, production=strict)
- **NEW**: Context files optional for poc stage
- Enables gradual formalization from PoC to production

## [2.3.0] - 2026-01
- **NEW**: Added optional quality agents (not part of main chain):
  - `/session.clarify` - Ask targeted questions to reduce ambiguity
  - `/session.analyze` - Cross-artifact consistency check (read-only)
  - `/session.checklist` - Generate requirements quality checklists

## [2.2.0] - 2026-01
- **NEW**: Added dedicated `session.task` agent for task generation
- **CHANGE**: 8-agent chain: `start → plan → task → execute → validate → publish → finalize → wrap`
- **CHANGE**: `session.plan` now focuses on implementation planning only
- **NEW**: Added `tasks-template.md` with user story organization
- **NEW**: Task format includes parallelization markers [P], user story labels [US1], and dependencies

## [2.1.1] - 2026-01
- Added documentation for parallel sessions using git worktree

## [2.1.0] - 2026-01
- **BREAKING**: Simplified to 2 workflows: development (default) and spike
- **BREAKING**: Removed legacy workflow flags
- Goal is now a positional argument: `/session.start "Fix the bug"`
- Standardized on `--spike` for exploration
- Removed auto-detection ("smart" workflow) - user explicitly chooses

## [2.0.0] - 2026-01
- Added workflow types (development, spike, smart)
- Added `--resume` and `--comment` flags
- Added anti-hallucination rules to session.validate
- Added session continuity across CLI restarts

## [1.0.0] - 2025-12
- Initial release
- 8-agent chain
- Basic session tracking
