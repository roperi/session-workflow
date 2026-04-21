# Session Workflow

🤖 **AI-Assisted Development Workflow** — Provides a structured, spec-driven development (SDD) lifecycle with session tracking, context continuity, and multi-tool support.

Session Workflow works with your preferred AI coding tool: Claude Code, Gemini CLI, GitHub Copilot, Cursor, and more.

📝 **Changelog**: [CHANGELOG.md](CHANGELOG.md) | ⚖️ **License**: [MIT](LICENSE) | 🤝 **Contributing**: [CONTRIBUTING.md](CONTRIBUTING.md)

---

## Overview

When AI context windows reset, work continuity is lost. Session Workflow solves this with:

1. **Session tracking** — What's in progress, what's done
2. **Standardized Handoffs** — Unified workflow from scoping to delivery
3. **Tool Agnosticism** — Projects workflow logic into native tool commands
4. **Context Syncing** — Maintains cross-tool continuity
5. **next.md Artifacts** — Primary handoff artifact for structured session continuity

---

## Prerequisites

To use or contribute to this project, you need the following dependencies:

- **Bash 4.4+**
- **jq**: For processing JSON session state and manifests.
- **shellcheck**: (Development) For linting bash scripts.
- **git**: For session tracking and archival.

Install on Debian/Ubuntu:
```bash
sudo apt-get update && sudo apt-get install -y jq shellcheck git
```

**Agent Chain**: `start → [brainstorm] → scope → spec → plan → task → execute → validate → publish → [review] → finalize → retrospect → wrap`

**Lightweight chains**: `maintenance`, `debug`, and `operational` start at `execute`; `spike` skips spec/review/publish.

**Orchestration modes**:
- **Default**: `session.start` runs Phase 1 (Planning) then stops for development/spike. Maintenance runs `execute` and then stops; debug and operational do the same, so you can wrap only if you actually want closeout.
- **Auto** (`--auto`): Continue until the next human gate. Development normally auto-chains through `publish`, but scope dialogue and manual-test checkpoints can pause earlier. Maintenance, debug, and operational auto-chain through `wrap` once no human checkpoint is active.
- **Copilot review** (`--auto --copilot-review`): Full end-to-end auto chain with dedicated `session.review` agent before merge

> **Human gates still apply in auto mode**: scope can ask focused clarifying questions, and manual-test checkpoints are recorded in `state.json.pause`. Resume with `invoke session.start --resume`.


---

## Installation

> **⚠️ Security Note**: The one-liner below pipes a remote script directly into bash without review.
> For production or shared environments, prefer the **download-inspect-run** method or pin to a
> specific release tag with `--version vX.Y.Z`:
>
> ```bash
> # Recommended: inspect before running
> curl -sSL https://raw.githubusercontent.com/roperi/session-workflow/main/install.sh -o install.sh
> less install.sh                 # review the script
> bash install.sh                 # run after review
>
> # Or pin to a specific release tag (avoids pulling from mutable main)
> bash install.sh --version v2.0.0
> ```

```bash
# Quick install (unreviewed – see security note above)
curl -sSL https://raw.githubusercontent.com/roperi/session-workflow/main/install.sh | bash

# Or clone and run
git clone https://github.com/roperi/session-workflow.git
cd your-project
../session-workflow/install.sh
```

**What gets installed:**
- `agents/session.*.md` - AI agent definitions
- `.session/` - Scripts, templates, project context, and versioned session history
- `AGENTS.md` - AI bootstrap file (created if missing)
- `.github/copilot-instructions.md` - Copilot config (created if missing)

**Post-install:**
1. Customize `.session/project-context/technical-context.md` with your stack
2. Customize `.session/project-context/constitution-summary.md` with quality standards
3. Review `AGENTS.md` for project-specific additions

## Updating

After installation, use the stable updater wrapper committed into the target repo:

```bash
bash .session/update.sh

# Or sync directly from a local checkout while testing unreleased changes
SESSION_WORKFLOW_SOURCE_DIR=~/workspace/session-workflow bash .session/update.sh

# Or pin to a specific version
bash .session/update.sh --version v2.5.0
```

If you're updating an older installation that does not have `.session/update.sh` yet, bootstrap once with the canonical updater:

```bash
curl -sSL https://raw.githubusercontent.com/roperi/session-workflow/main/update.sh | bash
```

**What gets updated** (safe to re-run at any time):
- All agent files (`agents/session.*.md`)
- All bash scripts (`.session/scripts/bash/`)
- The stable updater wrapper (`.session/update.sh`)
- Templates and documentation (`.session/templates/`, `.session/docs/`)
- The `## Session Workflow` section in `AGENTS.md` and `.github/copilot-instructions.md`

**What is never touched:**
- `.session/project-context/` — your customized stack and quality context
- Any content in `AGENTS.md` or `.github/copilot-instructions.md` outside the `## Session Workflow` block

Managed files are tracked in `.session/install-manifest.json`. On update, files that session-workflow used to manage but no longer ships are removed only if their contents still match the last recorded managed checksum; locally modified files are left in place with a warning.

**Session history policy:**
- Durable session artifacts under `.session/sessions/` are durable repository history and should be committed so scope/spec/plan/tasks/validation/notes/handoffs remain available across future work.
- Volatile workflow bookkeeping is ignored by default: `.session/ACTIVE_SESSION`, `.session/validation-results.json`, and `.session/sessions/**/state.json`.

`state.json` is updated continuously by workflow bookkeeping (`preflight`, `postflight`, pause handling, wrap), so it is treated as local control state rather than archival session history. `.session/validation-results.json` is the latest local validation summary; `{session_dir}/validation-results.json` is the durable session-scoped validation artifact used for historical audits.

If you're updating an older installation that still ignores `.session/sessions/`, run `bash .session/update.sh`, then `git add .session/sessions/` to begin tracking any new or previously ignored session artifacts.

---

## Quick Start

**Default (3-phase, with control points):**

```bash
# Phase 1: Planning (scope, spec, plan, tasks)
invoke session.start --issue 123

# Review artifacts, optionally run quality agents:
#   invoke session.clarify / invoke session.analyze / invoke session.checklist

# Phase 2: Implementation (execute, validate, publish PR)
invoke session.execute

# Review the PR manually, or run `invoke session.review` if you want the
# workflow to use the default/custom review agent. Then merge the PR, then:

# Phase 3: Completion (finalize, retrospect, wrap)
invoke session.finalize
```

**Optional brainstorm first (when the WHAT/WHY is fuzzy):**

```bash
invoke session.start --brainstorm --issue 123
# or
invoke session.start --brainstorm "Explore caching approaches"
```

`session.start` is still the required entrypoint. The `--brainstorm` flag tells `session.start` to insert `session.brainstorm` before the normal planning steps. Use it with development or spike sessions when you need help deciding what to build; it writes a session-scoped `brainstorm.md` that later planning agents reuse.

**Auto mode (through publish by default, or full with Copilot review):**

```bash
invoke session.start --auto --issue 123                    # stops after publish for manual/custom review
invoke session.start --auto --copilot-review --issue 123   # with Copilot PR review + full completion
```

**Custom review agent handoff:**

```bash
invoke session.start --auto --issue 123   # stops after publish
invoke session.review                     # runs whatever .github/agents/session.review.agent.md defines
# merge the PR
invoke session.finalize
```

**Post-session audit (read-only evaluation of recorded session history):**

```bash
./.session/scripts/bash/session-audit.sh
./.session/scripts/bash/session-audit.sh --all --summary
./.session/scripts/bash/session-audit.sh --workflow development --since 2026-01-01
```

Run the audit directly from your shell. It is a deterministic script, not a session agent. Use `--json` when you want a machine-readable report to inspect yourself or share with an AI assistant for interpretation.

**Other workflows:**

```bash
# Spike (exploration, no PR)
invoke session.start --spike "Explore Redis caching"
invoke session.execute  # execute + wrap to complete spike

# Maintenance (small change, no branch/PR — stops after execute by default)
invoke session.start --maintenance "Reorder docs/"
invoke session.wrap  # close out when you're ready

# Debug (troubleshooting / investigation, no PR by default)
invoke session.start --debug "Trace why batch jobs hang after deploy"
invoke session.wrap  # close out when you're ready

# Operational (iterative batch/pipeline work on a branch)
invoke session.start --operational "Process webpage mp3 files in batches"
invoke session.execute --resume  # continue the next monitored run after patching
invoke session.wrap  # close out when you're done

# Live maintenance audit (read-only repo scan — stops after execute by default)
invoke session.start --maintenance --read-only "Find stale files"
invoke session.wrap  # close out when you're ready

# Resume interrupted work
invoke session.start --resume
```

---

## Workflow Types

### 1. Development (default)

**Chain**: `start → [brainstorm] → scope → spec → plan → task → execute → validate → publish → [review] → merge → finalize → retrospect → wrap`

Use for feature development, bug fixes, and work that needs PR review.

```bash
invoke session.start --issue 123
invoke session.start "Add caching layer"
```

### 2. Spike

**Chain**: `start → [brainstorm] → scope → plan → task → execute → wrap`

Use for research, prototypes, and exploratory work. Includes planning but skips PR steps.

```bash
invoke session.start --spike "Benchmark Redis vs Memcached"
```

### 3. Maintenance

**Chain**: `start → execute → STOP` by default; `--auto` adds `wrap`

Use for docs cleanup, small housekeeping. No branch, no PR, no planning.

```bash
invoke session.start --maintenance "Reorder docs/"
invoke session.start --maintenance --read-only "Find stale files"  # audit mode
invoke session.start --maintenance --auto "Reorder docs/"          # execute + wrap
```

### 4. Debug

**Chain**: `start → execute → STOP` by default; `--auto` adds `wrap`

Use for troubleshooting, reproducing failures, tracing behavior, and validating a fix before deciding whether broader development workflow artifacts are needed. No branch or PR is required by default.

```bash
invoke session.start --debug "Investigate why workers stop consuming jobs"
invoke session.start --debug --auto "Trace why the cache warmup stalls"  # execute + wrap
```

### 5. Operational

**Chain**: `start → execute → STOP` by default; `--auto` adds `wrap`

Use for iterative runtime-driven work: batch processing, pipelines, backfills, scraping, reindexing, or any `run → inspect → patch → run again` loop. It uses a feature branch by default, but does not own validation/PR publishing.

If the resulting code should land long-term, hand off into the development review/publish path once the operational loop has stabilized the change.

```bash
invoke session.start --operational "Process webpage mp3 files in batches"
invoke session.execute --resume  # next monitored pass after patching
invoke session.start --operational --auto "Run one guarded backfill pass"  # execute + wrap
```

---

## Agent Chain

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  START   │───▶│  SCOPE   │───▶│   SPEC   │───▶│   PLAN   │───▶│   TASK   │
│          │    │          │    │          │    │          │    │          │
│ Init     │    │ Boundary │    │ Criteria │    │ Approach │    │ Generate │
│ Context  │    │ Define   │    │ Stories  │    │ Strategy │    │ Tasks    │
└──────────┘    └──────────┘    └──────────┘    └──────────┘    └──────────┘
                                                                      │
                                                                      ▼
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│   WRAP   │◀───│ RETROSPECT │◀───│ FINALIZE │◀───│  REVIEW  │◀───│ PUBLISH  │◀───│ VALIDATE │
│          │    │          │    │          │    │          │    │          │
│ Document │    │ Close    │    │ Copilot  │    │ Create   │    │ Quality  │
│ Cleanup  │    │ Issues   │    │ Review   │    │ PR       │    │ Tests    │
└──────────┘    └──────────┘    └──────────┘    └──────────┘    └──────────┘
                                                      ▲
                                                      │
                                                 ┌──────────┐
                                                 │ EXECUTE  │
                                                 │          │
                                                 │ TDD      │
                                                 │ Implement│
                                                 └──────────┘
```

Each step is invoked as a sub-agent with its own context and instructions. State is tracked via preflight/postflight scripts.

**Optional quality agents** (invoke between phases): `session.clarify`, `session.analyze`, `session.checklist`

**Optional planning agent**: `session.brainstorm` — recommended entrypoint is `invoke session.start --brainstorm ...`

**Knowledge capture agent**: `session.compound`

---

## Testing

Session-workflow has both deterministic parts (bash scripts) and non-deterministic parts (LLM output). The test suite focuses on the deterministic core.

```bash
bash tests/run.sh                          # run tests
TEST_VERBOSE=1 bash tests/run.sh           # verbose output
TEST_KEEP_TMP=1 bash tests/run.sh          # keep temp repo for debugging
```

Requires: `bash`, `git`, `jq`.

**What we test**: `session-start.sh`, `session-preflight.sh`, `session-wrap.sh`, `session-cleanup.sh` — JSON contracts, workflow gating, state transitions, and file management.

---

## Troubleshooting

### "Stale session detected"

Previous session wasn't closed properly.

```bash
rm .session/ACTIVE_SESSION
invoke session.start --issue 123
```

### "Git has uncommitted changes (BLOCKING)"

```bash
# session-wrap.sh creates the archival commit for durable session artifacts
# and CHANGELOG.md. If other files are still dirty, commit or stash those
# non-session changes first. Do not stage .session/sessions/**/state.json.
git status --short
git add <relevant-non-session-files> && git commit -m "wip"
invoke session.wrap
```

### "No active session"

```bash
invoke session.start --issue 123
```

### Interrupted Session / CLI Restart

If the CLI crashes or is killed mid-workflow, the next invocation detects this:

```
⚠️ INTERRUPTED SESSION DETECTED
Previous session was interrupted during: validate

RECOMMENDED ACTION:
Run: session.validate --resume
```

**Recovery:**
```bash
# Resume the interrupted step
invoke session.[step] --resume

# Or force skip (may cause data loss)
invoke session.[next-step] --force
```

---

## Reference

For detailed documentation:

- **[Reference Guide](session/docs/reference.md)** — Agent responsibilities, arguments, project stages, lifecycle, file structure, workflow examples, SDD positioning
- **[Shared Workflow Rules](session/docs/shared-workflow.md)** — State machine, scope boundaries, stage behavior
- **[Schema Versioning](session/docs/schema-versioning.md)** — JSON schema for session-info.json and state.json
- **[Next Step Artifacts](session/docs/reference.md#nextmd)** — Primary handoff artifact for structured session continuity
