# Session Workflow

🤖 **Optimized for [GitHub Copilot CLI](https://docs.github.com/en/copilot)** — leverages Copilot's agent invocation, sub-agent orchestration, and code review tools. Works with all models available in Copilot CLI (GPT, Claude, Gemini).

📝 **Changelog**: [CHANGELOG.md](CHANGELOG.md)

> ⚠️ Other CLIs (Claude Code, Gemini CLI standalone) are unverified and may require adjustments.

---

## Overview

When AI context windows reset, work continuity is lost. Session workflow solves this with:

1. **Session tracking** — What's in progress, what's done
2. **Handoff notes** — Context for the next AI session
3. **Agent chain** — Structured workflow from scoping to delivery
4. **Git hygiene** — Ensures clean state before session ends

**Agent Chain**: `start → scope → spec → plan → task → execute → validate → publish → [review] → finalize → wrap`

**Orchestration modes**:
- **Default**: `session.start` runs Phase 1 (Planning) then stops for development/spike. Maintenance runs `execute` and then stops so you can wrap only if you actually want closeout.
- **Auto** (`--auto`): Development auto-chains through `publish`, then stops for manual/custom review. Maintenance auto-chains through `wrap`.
- **Copilot review** (`--auto --copilot-review`): Full end-to-end auto chain with dedicated `session.review` agent before merge

> **GitHub ecosystem integration**: `session.start` uses Copilot CLI's task tool for sub-agent orchestration and optionally uses `request_copilot_review` for automated PR reviews. See [Copilot CLI Mechanics](session/docs/copilot-cli-mechanics.md) for internals.

**Spec Kit support**: Integrates with [GitHub Spec Kit](https://github.com/github/spec-kit) — see [SDD Positioning](session/docs/reference.md#sdd-positioning) for details.

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
- `.github/agents/session.*.agent.md` - AI agent definitions
- `.github/prompts/session.*.prompt.md` - Prompt link files (IDE integration, e.g. VS Code)
- `.session/` - Scripts, templates, project context
- `AGENTS.md` - AI bootstrap file (created if missing)
- `.github/copilot-instructions.md` - Copilot config (created if missing)

**Post-install:**
1. Customize `.session/project-context/technical-context.md` with your stack
2. Customize `.session/project-context/constitution-summary.md` with quality standards
3. Review `AGENTS.md` for project-specific additions

## Updating

When a new version is released, run `update.sh` from inside the target repo:

```bash
curl -sSL https://raw.githubusercontent.com/roperi/session-workflow/main/update.sh | bash

# Or pin to a specific version
bash update.sh --version v2.5.0
```

**What gets updated** (safe to re-run at any time):
- All agent files (`.github/agents/session.*.agent.md`)
- All prompt files (`.github/prompts/session.*.prompt.md`)
- All bash scripts (`.session/scripts/bash/`)
- Templates and documentation (`.session/templates/`, `.session/docs/`)
- The `## Session Workflow` section in `AGENTS.md` and `.github/copilot-instructions.md`

**What is never touched:**
- `.session/project-context/` — your customized stack and quality context
- Any content in `AGENTS.md` or `.github/copilot-instructions.md` outside the `## Session Workflow` block

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

# Phase 3: Completion (finalize, wrap)
invoke session.finalize
```

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

**Other workflows:**

```bash
# Spike (exploration, no PR)
invoke session.start --spike "Explore Redis caching"
invoke session.execute  # execute + wrap to complete spike

# Maintenance (small change, no branch/PR — stops after execute by default)
invoke session.start --maintenance "Reorder docs/"
invoke session.wrap  # close out when you're ready

# Audit (read-only, no commits — stops after execute by default)
invoke session.start --maintenance --read-only "Find stale files"
invoke session.wrap  # close out when you're ready

# Resume interrupted work
invoke session.start --resume
```

---

## Workflow Types

### 1. Development (default)

**Chain**: `start → scope → spec → plan → task → execute → validate → publish → [review] → merge → finalize → wrap`

Use for feature development, bug fixes, and work that needs PR review.

```bash
invoke session.start --issue 123
invoke session.start "Add caching layer"
```

### 2. Spike

**Chain**: `start → scope → plan → task → execute → wrap`

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
│   WRAP   │◀───│ FINALIZE │◀───│  REVIEW  │◀───│ PUBLISH  │◀───│ VALIDATE │
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

**Knowledge capture agents**: `session.brainstorm`, `session.compound`

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
git add -A && git commit -m "wip"
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
- **[Copilot CLI Mechanics](session/docs/copilot-cli-mechanics.md)** — How the orchestration works under the hood
- **[Shared Workflow Rules](session/docs/shared-workflow.md)** — State machine, scope boundaries, stage behavior
- **[Schema Versioning](session/docs/schema-versioning.md)** — JSON schema for session-info.json and state.json
- **[Testing Guide](session/docs/testing.md)** — Manual test cases and edge coverage
