# Changelog

All notable changes to this project will be documented in this file.

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
- Inspired by Speckit's clarify, analyze, and checklist commands

## [2.2.0] - 2026-01
- **NEW**: Added dedicated `session.task` agent for task generation
- **CHANGE**: 8-agent chain: `start → plan → task → execute → validate → publish → finalize → wrap`
- **CHANGE**: `session.plan` now focuses on implementation planning only
- **NEW**: Added `tasks-template.md` with user story organization
- **NEW**: Task format includes parallelization markers [P], user story labels [US1], and dependencies
- Inspired by Speckit's task generation workflow

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
