# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

- **FIX (#72)**: `state.json` is now treated consistently as volatile workflow bookkeeping — install/update add a dedicated ignore rule, validation excludes bookkeeping-only dirtiness, wrap strips `state.json` from archival commits, and docs/agent guidance now distinguish it from durable session artifacts
- **FIX (#70)**: `session-wrap.sh` now creates the archival wrap commit for durable session-history artifacts, `CHANGELOG.md`, and the resolved Speckit `tasks.md` path when needed; it force-adds session-history paths if older repos still ignore them, blocks before clearing `ACTIVE_SESSION` when unrelated dirty paths would be swept into that commit, and aligns wrap docs/tests/agent guidance with the new behavior
- **FIX (#68)**: `.session/sessions/` is now treated consistently as versioned session history — fresh installs stop ignoring it, `.session/update.sh` removes the legacy ignore rule for existing repos, docs now distinguish durable session artifacts from ephemeral `.session/ACTIVE_SESSION` / `.session/validation-results.json`, and tests cover both install and update behavior
- **NEW**: Added an `operational` workflow for iterative runtime work — `session.start --operational` now supports monitored batch/pipeline loops that run `execute` and stop by default, use a feature branch, and rely on repeated `session.execute --resume` passes before optional wrap; docs and tests now distinguish this from development, maintenance, and debug
- **NEW**: `session.start` now accepts `--brainstorm` as the clear entrypoint for the optional brainstorm step — the flag is surfaced in `orchestration.brainstorm`, limited to development/spike planning sessions, and docs now consistently describe brainstorm as a session-scoped `{session_dir}/brainstorm.md` artifact that still requires `session.start` first
- **NEW**: Installed repos now get a stable `.session/update.sh` wrapper plus `.session/install-manifest.json` managed-file tracking — updates can use the committed wrapper directly, support local-source syncing, and safely prune deprecated managed files only when they still match the last recorded checksum
- **NEW (#56)**: Added `next.md` as a first-class session handoff artifact — new sessions create a dedicated follow-up template, continuation flow prefers structured `next.md` content over legacy `notes.md` handoff text, and install/update/docs now surface the artifact explicitly
- **NEW (#59)**: Added a dedicated `debug` workflow for troubleshooting/investigation — `session.start --debug` now initializes lightweight debug sessions that run `execute` and stop by default, with optional `--auto` continuing to `wrap`; workflow docs and routing guidance now recognize debugging language like `debug`, `troubleshoot`, `trace`, and `reproduce`
- **CHANGE (#58)**: `--auto` now means "continue until the next human gate" — scope prompts may remain interactive, manual-test pauses are recorded in `state.json.pause`, and resume surfaces the active checkpoint
- **CHANGE (#57)**: Maintenance workflow is now lightweight by default — `session.start --maintenance` runs `execute` then stops; only `--auto` continues to `wrap`, including read-only maintenance runs
- **FIX**: `update.sh` now refreshes the latest installed surface area for session-workflow, including `session.review` agent/prompt, `session/docs/reference.md`, and the current Session Workflow bootstrap block; it also updates `AGENTS.md` when present and supports local-source syncing via `SESSION_WORKFLOW_SOURCE_DIR`
- **FIX**: `install.sh` and `stubs/copilot_instructions.md` now reflect the current review-stage workflow and include the `session.review`/`reference.md` additions used by the latest bootstrap
- **FIX**: `session-start.sh` now accepts orchestration-only flags `--auto` and `--copilot-review` instead of rejecting them; the script records those flags in JSON output under `orchestration` so `session.start` auto-mode invocations no longer degrade to planning-only after an unknown-option failure
- **CHANGE (#54)**: `--auto` without `--copilot-review` now stops after `session.publish` so users can review the PR manually or invoke a custom `session.review` agent explicitly; only `--auto --copilot-review` continues through automated review, merge, finalize, and wrap
- **CHANGE (#54)**: `session.review` now uses a single review pass by default — request Copilot review once, address actionable comments, push fixes, and leave one final PR summary comment; no automatic re-request loop and no inline replies on each review thread
- **NEW (#54)**: Dedicated `session.review` agent — review is now a first-class workflow step instead of inline logic in `session.start`; default implementation uses GitHub Copilot Review (`request_copilot_review`); overridable by replacing `session.review.agent.md` with a custom review agent; `WORKFLOW_TRANSITIONS` updated with `publish → review` and `review → finalize`; backward compatible (review can be skipped: `publish → finalize`); `session.execute` Phase 2 chain updated to include review step; development workflow is now 11-agent chain

- **FIX (#53)**: Wrap step stuck `in_progress` — `session-wrap.sh` now calls `set_workflow_step()` to mark wrap as completed in `state.json`; added test 29 for regression coverage
- **CHANGE (#53)**: Auto-chaining and Copilot review now opt-in — default mode runs Phase 1 (Planning: scope → spec → plan → task) then stops; `--auto` flag runs full chain; `--auto --copilot-review` adds PR review; `session.execute` and `session.finalize` agents updated with Phase 2/3 orchestration for direct invocation
- **DOCS (#53)**: README restructured (725 → 282 lines) — prominent Copilot CLI optimization callout; 3-phase Quick Start; detailed content moved to `session/docs/reference.md` (agent responsibilities, quality agents, project stages, arguments, workflow examples, session lifecycle, file structure, SDD positioning)
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
