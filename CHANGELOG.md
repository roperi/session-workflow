# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]
- **NEW**: Optional knowledge capture agents:
  - `/session.brainstorm` writes brainstorm docs to `docs/brainstorms/`
  - `/session.compound` writes solution docs to `docs/solutions/`
- **CHANGE**: Installer/updater now includes brainstorm/compound agents and prompts

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
