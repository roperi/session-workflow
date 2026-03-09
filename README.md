# Session Workflow

**📝 Changelog**: [CHANGELOG.md](CHANGELOG.md)

This is the single source of truth for session workflow documentation.

**Compatibility**:
- ✅ Works with all models available in **GitHub Copilot CLI** — OpenAI (GPT series), Anthropic (Claude series), Google (Gemini series)
- ⚠️ Other CLIs (Claude Code, Gemini CLI standalone) are unverified and may require adjustments

**Spec-kit support**:
- ✅ Integrates with **GitHub Spec Kit** specs and tasks  
  https://github.com/github/spec-kit

---

## Table of Contents

1. [Overview](#overview)
2. [Installation](#installation)
3. [Updating](#updating)
4. [Quick Start](#quick-start)
4. [Workflow Types](#workflow-types)
5. [Project Stages](#project-stages)
6. [Agent Chain](#agent-chain)
7. [Agent Responsibilities](#agent-responsibilities)
8. [Optional Quality Agents](#optional-quality-agents)
9. [Arguments](#arguments)
10. [Workflow Examples](#workflow-examples)
11. [Session Lifecycle](#session-lifecycle)
12. [Testing](#testing)
13. [File Structure](#file-structure)
14. [Troubleshooting](#troubleshooting)

---

## Overview

When AI context windows reset, work continuity is lost. Session workflow solves this with:

1. **Session tracking** - What's in progress, what's done
2. **Handoff notes** - Context for the next AI session
3. **8-agent chain** - Structured workflow with clear next-step suggestions
4. **Git hygiene** - Ensures clean state before session ends

**Agent Chain**: `start → [brainstorm →] [scope →] [spec →] plan → task → execute → validate → publish → finalize → wrap`

**Optional knowledge agents** (version-controlled docs):
- `session.brainstorm` → writes to `{session_dir}/brainstorm.md` (clarify WHAT/WHY before planning)
- `session.scope` → writes to `{session_dir}/scope.md` (define problem boundaries and success criteria)
- `session.spec` → writes to `{session_dir}/spec.md` (acceptance criteria and verification contracts)
- `session.compound` → writes to `docs/solutions/` (capture reusable learnings after solving)

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

**Pick a workflow:**

```
Will this produce a PR?
├─ Yes → invoke session.start --issue 123        (development — full chain)
├─ Maybe / exploring → invoke session.start --spike "Research caching"
├─ Small change, no PR → invoke session.start --maintenance "Reorder docs/"
└─ Read-only audit → invoke session.start --maintenance --read-only "Find stale files"

Not sure what to build yet? → invoke session.brainstorm first, then session.start
```

```bash
# Development workflow (full chain → PR)
invoke session.start --issue 123
invoke session.start "Fix performance bug"

# Spike (exploration, no PR)
invoke session.start --spike "Explore Redis caching"

# Maintenance (small change or housekeeping, no PR)
invoke session.start --maintenance "Reorder docs/ and update TOC"
invoke session.start --maintenance "Remove stray .DS_Store files"

# Audit (read-only, no commits)
invoke session.start --maintenance --read-only "Find files not referenced in any import"

# Resume interrupted work
invoke session.start --resume
invoke session.execute --resume --comment "Continue from task 5"

# After PR merged
invoke session.finalize

# End session
invoke session.wrap
```

**Note**: When consuming preflight or session-start JSON, use `repo_root` to resolve repo paths.

---

## Workflow Types

### 1. Development (default)

**Chain**: `start → [scope →] [spec →] plan → task → execute → validate → publish → finalize → wrap`

Use for:
- Feature development
- Bug fixes
- Work that needs PR review

```bash
invoke session.start --issue 123
invoke session.start "Add caching layer"
```

### 2. Spike

**Chain**: `start → [scope →] plan → task → execute → wrap`

Use for:
- Research and exploration
- Prototypes
- Work that may be discarded

```bash
invoke session.start --spike "Benchmark Redis vs Memcached"
```

**Note**: Spike still includes planning and task generation - it only skips PR steps (validate, publish, finalize).

### 3. Maintenance

**Chain**: `start → execute → wrap`

Use for:
- Documentation updates, reordering, or cleanup
- Small housekeeping tasks (remove files, rename, reformat)
- Work that doesn't warrant a branch or PR

```bash
invoke session.start --maintenance "Reorder docs/ and update TOC"
invoke session.start --maintenance "Remove stray .DS_Store and build artifacts"
```

No branch is created by default; work happens on the current branch.  
Skips planning and validation — go straight from start to execute.

#### Read-only / Audit mode

Add `--read-only` to prevent any commits or file modifications.  
The session produces a report file instead of committing changes.

```bash
invoke session.start --maintenance --read-only "Audit files not referenced by any import"
invoke session.start --maintenance --read-only "Find TODO comments older than 6 months"
```

---

## Project Stages

The `--stage` flag controls validation strictness and documentation requirements.

| Stage | Constitution | Technical Context | Validation | Use Case |
|-------|--------------|-------------------|------------|----------|
| **poc** | Optional | Optional | Relaxed (warnings) | PoCs, spikes, early exploration |
| **mvp** | Required (brief OK) | Required (partial OK) | Standard | First working version, core features |
| **production** | Required (full) | Required (complete) | Strict (default) | Production-ready, full quality gates |

### Usage

```bash
# PoC: PoC work, don't know the stack yet
invoke session.start --stage poc "Prototype auth flow"

# MVP: Building first version, core requirements defined
invoke session.start --stage mvp --issue 123

# Production: Full quality (default, flag optional)
invoke session.start --issue 456
invoke session.start --stage production --issue 456
```

### Stage Behavior

**poc** (Proof of Concept):
- Constitution/technical-context files can be empty stubs
- Validation reports warnings but never blocks
- Simple task checklists OK (no user stories required)
- WIP commits allowed

**mvp** (Minimum Viable Product):
- Core sections of constitution/technical-context required
- Validation fails on errors, warns on style issues
- User stories encouraged but not enforced
- Standard commit messages

**production** (default):
- Full constitution and technical-context required
- All validation checks must pass
- Full task structure with dependencies
- Conventional commits required

### Upgrading Stage

As your project matures, upgrade the stage:
```bash
# Started as PoC, now building MVP
invoke session.start --stage mvp --issue 123

# MVP proven, now going to production
invoke session.start --stage production --issue 456
```

---

## Agent Chain

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  START   │───▶│   PLAN   │───▶│   TASK   │───▶│ EXECUTE  │───▶│ VALIDATE │
│          │    │          │    │          │    │          │    │          │
│ Init     │    │ Approach │    │ Generate │    │ TDD      │    │ Quality  │
│ Context  │    │ Strategy │    │ Tasks    │    │ Implement│    │ Tests    │
└──────────┘    └──────────┘    └──────────┘    └──────────┘    └──────────┘
   (auto)          (auto)          (auto)          (auto)          (auto)
                                                                      │
                                                                      ▼
┌──────────┐    ┌──────────┐    ┌──────────┐                    ┌──────────┐
│   WRAP   │◀───│ FINALIZE │◀───│ PUBLISH  │◀───────────────────┤          │
│          │    │          │    │          │                    │          │
│ Document │    │ Close    │    │ Create   │                    │          │
│ Cleanup  │    │ Issues   │    │ PR       │                    │          │
└──────────┘    └──────────┘    └──────────┘                    └──────────┘
```

**Development workflow** uses all 8 agents.

**Spike workflow** uses: `start → [scope →] plan → task → execute → wrap` (skips spec, validate, publish, finalize)

**Maintenance workflow** uses: `start → execute → wrap` (skips scope, spec, plan, task, validate, publish, finalize)

At the end of each step, the agent will suggest the next step — invoke it by name or select it from the `/agent` picker.

---

## Agent Responsibilities

### session.start
- Run `session-start.sh`
- Load project context
- Create feature branch
- Review previous session notes
- **Next step:** invoke session.scope (development/spike) or session.plan

### session.scope
- Define problem boundaries and success criteria
- Interactive dialogue to clarify what's in/out of scope
- Writes `{session_dir}/scope.md`
- **Next step:** invoke session.spec (development) or session.plan (spike)

### session.spec
- Define detailed specification with acceptance criteria
- Derives user stories from scope, defines Given/When/Then criteria
- Identifies edge cases, error scenarios, and non-functional requirements
- Marks ambiguities with `[NEEDS CLARIFICATION]`
- Writes `{session_dir}/spec.md`
- **Only for**: development workflow (skipped in spike)
- **Next step:** invoke session.plan

### session.plan
- Create implementation plan and approach
- Analyze requirements and identify components
- Or reference existing Speckit plan
- **Next step:** invoke session.task

### session.task
- Generate detailed task breakdown
- Organize by user story with priorities
- Add parallelization markers [P] and dependencies
- Use tasks-template.md structure
- **Next step:** invoke session.execute

### session.execute
- Single-task focus
- TDD: test → implement → verify
- Commit after each task
- **Next step:** invoke session.validate (development) or session.wrap (spike)

### session.validate
- Run lint, tests
- Check git state
- Offer fixes if failures
- **Stage-aware**: poc=warnings only, mvp=standard, production=strict
- **Suggested next command (if validation passes):** session.publish
- **Only for**: development workflow

### session.publish
- Create or update PR
- Link issues
- **Next step:** After the PR is merged, run session.finalize
- **Only for**: development workflow

### session.finalize
- Validate PR is merged
- Close issues
- Update parent issues
- **Next step:** invoke session.wrap
- **Only for**: development workflow

### session.wrap
- Update session notes
- Update CHANGELOG.md
- Clean up merged branches
- Mark session complete
- **No handoff** (end of chain)

---

## Optional Agents

These agents are **not part of the main 8-agent chain**.

### Knowledge Capture Agents

These create **version-controlled** artifacts under `docs/`.

### session.brainstorm
- Clarify **WHAT/WHY** and explore 2-3 approaches
- Captures decisions + open questions in `{session_dir}/brainstorm.md`
- **Best used**: After `session.start`, before `session.plan` — when you're unsure what to build
- **Skip if**: you already know what you want to do; just `session.plan` directly

### session.compound
- Capture solved problems as reusable solution docs in `docs/solutions/`
- Focus: symptoms → root cause → fix → prevention
- **Best used**: After a meaningful solution/decision, often near the end of a session

### Quality Agents

Use these for requirements hygiene and consistency checks at any time.

### session.clarify
- Ask up to 5 targeted questions to reduce ambiguity
- Records clarifications in session notes
- **Best used**: Before `session.task` when requirements are vague
- **Inspired by**: Speckit's `/speckit.clarify`

### session.analyze
- Cross-artifact consistency and coverage analysis
- **STRICTLY READ-ONLY** - produces report only
- **Best used**: After `session.task`, before `session.execute`
- **Inspired by**: Speckit's `/speckit.analyze`

### session.checklist
- Generate requirements quality checklists ("unit tests for English")
- Domain-specific: UX, API, security, performance
- **Best used**: Before implementation or PR review
- **Inspired by**: Speckit's `/speckit.checklist`

**Usage patterns:**

Quality (requirements hygiene):
```
start → [scope?] → [spec?] → plan → [clarify?] → task → [analyze?] → [checklist?] → execute → ...
           ↑           ↑                 ↑                    ↑              ↑
        boundaries  acceptance    Optional quality checks (reduce downstream rework)
```

Knowledge capture (compounding docs):
```
start → [brainstorm?] → [scope?] → [spec?] → plan → task → execute → ... → wrap → [compound?]
             ↑              ↑           ↑                                              ↑
       clarify WHAT/WHY  boundaries  acceptance                                 capture learnings
```

---

## Arguments

### session.start

```bash
# Session types
invoke session.start --issue 123           # GitHub issue
invoke session.start --spec 001-feature    # Speckit feature
invoke session.start "Fix the bug"         # Unstructured (goal as positional arg)

# Workflow selection
invoke session.start --spike "Research"          # Spike workflow (explore, no PR)
invoke session.start --maintenance "Reorder docs/" # Maintenance workflow (small tasks, no branch/PR)

# Modifiers
invoke session.start --maintenance --read-only "Audit stale files"  # No commits, report only
invoke session.start --stage poc "Prototype auth"                   # Relaxed validation

# Resume
invoke session.start --resume
invoke session.start --resume --comment "Continue from task 5"
```

### All agents

- `--comment "text"` - Provide specific instructions
- `--resume` - Continue from where you left off
- `--force` - Skip workflow validation (use with caution)

**Support matrix:**

| Agent | --comment | --resume |
|-------|-----------|----------|
| session.start | ✅ | ✅ |
| session.plan | ✅ | ✅ |
| session.task | ✅ | ✅ |
| session.execute | ✅ | ✅ |
| session.validate | ✅ | ⚠️ (re-runs failed only) |
| session.publish | ✅ | ✅ |
| session.finalize | ✅ | N/A |
| session.wrap | ✅ | N/A |

---

## Workflow Examples

### Example 1: Bug Fix (Development)

```bash
# Start
invoke session.start --issue 456

# Suggested flow: plan → task → execute → validate → publish
# You interact at each step

# After PR merged
invoke session.finalize

# Document and close
invoke session.wrap
```

### Example 2: Research (Spike)

```bash
invoke session.start --spike "Research WebSocket vs SSE"

# Work through exploration
# No planning, no PR

invoke session.wrap  # Document findings
```

### Example 3: Docs Housekeeping (Maintenance)

```bash
invoke session.start --maintenance "Reorder docs/ sections and update TOC"

# Go straight to execute — no plan, no branch, no PR
invoke session.execute
invoke session.wrap
```

### Example 4: Read-only Audit (Maintenance + read-only)

```bash
invoke session.start --maintenance --read-only "Find files not referenced by any import"

# Execute produces a report; no commits happen
invoke session.execute
invoke session.wrap  # Saves report, no git changes
```

### Example 5: Resuming After Interruption

```bash
# Started working, pressed ESC mid-task
invoke session.execute --resume --comment "Continue from task 7"
```

---

## Session Lifecycle

### Start
Creates:
- `session-info.json` - Metadata
- `state.json` - Progress tracking
- `notes.md` - Handoff notes
- `tasks.md` - Task checklist

### During
Update regularly:
- `tasks.md` - Mark completed: `[ ]` → `[x]`
- `notes.md` - Key decisions, blockers

### Wrap
- Updates CHANGELOG.md
- Commits documentation
- Cleans merged branches
- Clears ACTIVE_SESSION

---

## Testing

Session-workflow has both deterministic parts (bash scripts) and non-deterministic parts (LLM output). Our test suite focuses on the deterministic core so it is safe and stable to run in CI.

### Run locally

```bash
bash tests/run.sh
```

Requires: `bash`, `git`, `jq`.

Optional:

```bash
TEST_VERBOSE=1 bash tests/run.sh   # prints step-by-step + JSON
TEST_KEEP_TMP=1 bash tests/run.sh  # keeps the temp repo and prints its path
```

### What we test

- `session-start.sh --json`: JSON contract (including deterministic `repo_root`) and session file creation
- `session-preflight.sh --json`: workflow gating (detects interrupted sessions and returns exit code `2`)
- `session-wrap.sh --json`: clears `.session/ACTIVE_SESSION`
- `session-cleanup.sh --json`: errant file/dir removal (misplaced session dirs, unknown root files, orphaned files, empty dirs)

### Why we test this (and not the LLM)

We intentionally do not invoke Copilot/LLMs in CI because that would be flaky (model/prompt drift) and typically requires unsafe permissions (paths/tools/URLs). These tests validate the stable “plumbing” that all agents depend on.

---

## File Structure

```
.session/
├── ACTIVE_SESSION              # Current session ID
├── project-context/
│   ├── constitution-summary.md # Quality standards
│   └── technical-context.md    # Stack, commands
├── scripts/bash/
│   ├── session-common.sh
│   ├── session-start.sh
│   ├── session-wrap.sh
│   ├── session-cleanup.sh
│   └── ...
├── templates/
│   └── session-notes.md
├── sessions/
│   └── YYYY-MM-DD-N/
│       ├── session-info.json
│       ├── state.json
│       ├── notes.md
│       └── tasks.md
└── docs/
    ├── README.md
    ├── testing.md
    └── shared-workflow.md

.github/
├── agents/
│   └── session.*.agent.md
└── prompts/
    └── session.*.prompt.md
```

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
```
# Resume the interrupted step
invoke session.[step] --resume

# Or force skip (may cause data loss)
invoke session.[next-step] --force
```
