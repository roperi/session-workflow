# Session Workflow Reference

Detailed documentation for session-workflow. For getting started, see the [README](../../README.md).

## Table of Contents

1. [SDD Positioning](#sdd-positioning)
2. [Agent Responsibilities](#agent-responsibilities)
3. [Optional Quality Agents](#optional-quality-agents)
4. [Project Stages](#project-stages)
5. [Arguments](#arguments)
6. [Workflow Examples](#workflow-examples)
7. [Session Lifecycle](#session-lifecycle)
8. [File Structure](#file-structure)

---

## SDD Positioning

Session-workflow implements a lightweight **Specification-Driven Development (SDD)** process — inspired by [GitHub Spec Kit](https://github.com/github/spec-kit) but designed to work standalone.

### Standalone (Personal / Small Projects)

Session-workflow on its own gives you a structured development loop:

- `session.scope` → define problem boundaries and success criteria
- `session.spec` → write acceptance criteria and verification contracts
- `session.plan` → create implementation plan from the spec
- `session.task` → generate task breakdown
- `session.execute` → TDD implementation
- `session.validate` → automated quality gates

All artifacts live in `.session/sessions/` — no external tooling required.

### With Spec Kit (Teams / Enterprise)

When used with `--spec <feature>`, session-workflow maps its steps into Spec Kit's `specs/<feature>/` structure:

| Artifact | Standalone path | Speckit path |
|----------|----------------|--------------|
| Scope | `{session_dir}/scope.md` | `specs/{feature}/scope.md` |
| Spec | `{session_dir}/spec.md` | `specs/{feature}/spec.md` |
| Plan | `{session_dir}/plan.md` | `specs/{feature}/plan.md` (reference) |
| Tasks | `{session_dir}/tasks.md` | `specs/{feature}/tasks.md` |

This lets teams use Spec Kit's review and governance workflow while keeping session-workflow's agent chain for implementation.

### When to Use Which

| Scenario | Recommendation |
|----------|---------------|
| Solo developer, quick iteration | Session-workflow standalone |
| Small team, informal process | Session-workflow standalone |
| Team with formal spec review | Session-workflow + Spec Kit |
| Enterprise governance requirements | Session-workflow + Spec Kit |
| Research / spike | Session-workflow standalone (spike workflow) |

### SDD Alignment: Session-Workflow ↔ Spec Kit Commands

| Spec Kit Command | Session-Workflow Equivalent | Notes |
|---|---|---|
| `/speckit.constitution` | `constitution-summary.md` (project-context) | Quality standards and conventions |
| `/speckit.specify` | `session.scope` + `session.spec` | Split into boundary-setting and acceptance criteria |
| `/speckit.clarify` | `session.clarify` (optional) | Requirements disambiguation |
| `/speckit.plan` | `session.plan` | Implementation approach and architecture |
| `/speckit.tasks` | `session.task` | Task breakdown with dependencies |
| `/speckit.implement` | `session.execute` | TDD implementation loop |
| `/speckit.analyze` | `session.analyze` (optional) | Cross-artifact consistency check |

---

## Agent Responsibilities

All chain agents are invoked as sub-agents by `session.start`. Each agent runs preflight, does its scoped work, runs postflight, and returns results.

### session.start (orchestrator)
- Run `session-start.sh`
- Load project context
- Create feature branch
- **Default mode**: Orchestrate Phase 1 (Planning) — scope → spec → plan → task — then stop
- **Auto mode** (`--auto`): Orchestrate the full chain including review cycle and merge
- **Copilot review** (`--auto --copilot-review`): Auto chain + request Copilot PR review before merge

### session.scope
- Define problem boundaries and success criteria
- Interactive dialogue to clarify what's in/out of scope
- Writes `{session_dir}/scope.md` (or `specs/{feature}/scope.md` for speckit sessions)

### session.spec
- Define detailed specification with acceptance criteria
- Derives user stories from scope, defines Given/When/Then criteria
- Identifies edge cases, error scenarios, and non-functional requirements
- Marks ambiguities with `[NEEDS CLARIFICATION]`
- Writes `{session_dir}/spec.md` (or `specs/{feature}/spec.md` for speckit sessions)
- **Only for**: development workflow (skipped in spike)

### session.plan
- Create implementation plan and approach
- Analyze requirements and identify components
- Or reference existing Speckit plan

### session.task
- Generate detailed task breakdown
- Organize by user story with priorities
- Add parallelization markers [P] and dependencies
- Use tasks-template.md structure

### session.execute
- Single-task focus
- TDD: test → implement → verify
- Commit after each task
- **When invoked directly**: Orchestrates Phase 2 (validate → publish for development; wrap for spike/maintenance)

### session.validate
- Run lint, tests
- Check git state
- Verify spec acceptance criteria
- Offer fixes if failures
- **Stage-aware**: poc=warnings only, mvp=standard, production=strict
- **Only for**: development workflow

### session.publish
- Create or update PR
- Link issues
- **Only for**: development workflow

### session.finalize
- Validate PR is merged
- Close issues
- Update parent issues
- **Only for**: development workflow
- **When invoked directly**: Orchestrates Phase 3 (→ wrap)

### session.wrap
- Update session notes
- Update CHANGELOG.md
- Clean up merged branches
- Mark session complete

---

## Optional Quality Agents

These agents are **not part of the main workflow chain**. Invoke them between phases as needed.

### Knowledge Capture Agents

These create **version-controlled** artifacts under `docs/`.

#### session.brainstorm
- Clarify **WHAT/WHY** and explore 2-3 approaches
- Captures decisions + open questions in `{session_dir}/brainstorm.md`
- **Best used**: After `session.start`, before `session.plan` — when you're unsure what to build
- **Skip if**: you already know what you want to do; just `session.plan` directly

#### session.compound
- Capture solved problems as reusable solution docs in `docs/solutions/`
- Focus: symptoms → root cause → fix → prevention
- **Best used**: After a meaningful solution/decision, often near the end of a session

### Quality Agents

Use these for requirements hygiene and consistency checks at any time.

#### session.clarify
- Ask up to 5 targeted questions to reduce ambiguity
- Records clarifications in session notes
- **Best used**: Before `session.task` when requirements are vague
- **Inspired by**: Speckit's `/speckit.clarify`

#### session.analyze
- Cross-artifact consistency and coverage analysis
- **STRICTLY READ-ONLY** - produces report only
- **Best used**: After `session.task`, before `session.execute`
- **Inspired by**: Speckit's `/speckit.analyze`

#### session.checklist
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

# Orchestration
invoke session.start --auto --issue 123                       # Full chain, one shot
invoke session.start --auto --copilot-review --issue 123      # Full chain + Copilot PR review

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

### Example 1: Bug Fix (Development, default mode)

```bash
# Phase 1: Planning
invoke session.start --issue 456
# → scope → spec → plan → task → STOP

# (review artifacts, optionally: invoke session.clarify / session.analyze)

# Phase 2: Implementation
invoke session.execute
# → execute → validate → publish → STOP

# (review and merge the PR)

# Phase 3: Completion
invoke session.finalize
# → finalize → wrap → END
```

### Example 2: Bug Fix (Development, auto mode)

```bash
# Full chain in one shot
invoke session.start --auto --issue 456
# → scope → spec → plan → task → execute → validate → publish → merge → finalize → wrap

# With Copilot PR review
invoke session.start --auto --copilot-review --issue 456
# → ... → publish → Copilot review → address comments → merge → finalize → wrap
```

### Example 3: Research (Spike)

```bash
invoke session.start --spike "Research WebSocket vs SSE"
# → scope → plan → task → STOP

invoke session.execute
# → execute → wrap → END
```

### Example 4: Docs Housekeeping (Maintenance)

```bash
invoke session.start --maintenance "Reorder docs/ sections and update TOC"
# → STOP (no planning phase)

invoke session.execute
# → execute → wrap → END (no branch, no PR)
```

### Example 5: Read-only Audit

```bash
invoke session.start --maintenance --read-only "Find files not referenced by any import"
# → STOP

invoke session.execute
# → execute (report only, no commits) → wrap → END
```

### Example 6: Resuming After Interruption

```bash
invoke session.start --resume
# Resumes from the last completed step in the chain
```

---

## Session Lifecycle

### Start
Creates:
- `session-info.json` - Metadata
- `state.json` - Progress tracking (with `step_history[]`)
- `notes.md` - Handoff notes

### Planning Phase
Creates:
- `scope.md` - Problem boundaries and success criteria
- `spec.md` - Acceptance criteria and user stories (development only)
- `plan.md` - Implementation approach
- `tasks.md` - Task checklist

### Implementation Phase
Updates:
- `tasks.md` - Mark completed: `[ ]` → `[x]`
- `notes.md` - Key decisions, blockers
- `validation-results.json` - Quality gate results
- `pr-summary.md` - PR description

### Wrap
- Updates CHANGELOG.md
- Commits documentation
- Cleans merged branches
- Clears ACTIVE_SESSION

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
│   └── YYYY-MM/
│       └── YYYY-MM-DD-N/
│           ├── session-info.json
│           ├── state.json
│           ├── notes.md
│           └── tasks.md
└── docs/
    ├── copilot-cli-mechanics.md
    ├── reference.md
    ├── schema-versioning.md
    ├── shared-workflow.md
    └── testing.md

.github/
├── agents/
│   └── session.*.agent.md
└── prompts/
    └── session.*.prompt.md
```
