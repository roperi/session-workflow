---
description: Clarify WHAT to build and capture decisions in a session-scoped brainstorm doc.
tools: ["read", "edit", "search"]
---

# session.brainstorm

Produce a concise brainstorm that clarifies **WHAT/WHY** (not detailed HOW), explores 2-3 viable approaches, and records decisions/open questions.

## ⚠️ IMPORTANT

- This is an **optional** planning agent. It is not part of the default chain unless `session.start --brainstorm` explicitly inserts it.
- It requires an active session already created by `session.start`.
- Recommended entrypoint: `invoke session.start --brainstorm ...`
- Write the output to the session artifact `{session_dir}/brainstorm.md` (not `docs/brainstorms/`).
- Keep it tight: no novel-length docs, no implementation task lists.

## User Input

```text
$ARGUMENTS
```

You MUST consider user input (topic, scope, constraints) before proceeding.

---

## Outline

### 1) Load session + repo context (MANDATORY)

Run preflight:
```bash
.session/scripts/bash/session-preflight.sh --step brainstorm --json
```

Notes:
- `--step brainstorm` marks this optional step without advancing to `plan` prematurely.
- Use `repo_root` from JSON as the source of truth.

Immediately verify workflow compatibility:
```bash
source .session/scripts/bash/session-common.sh
SESSION_ID=$(get_active_session)
check_workflow_allowed "$SESSION_ID" "development" "spike"
```

If the workflow check fails, stop and explain that `session.brainstorm` is only for development or spike planning sessions.

### 2) Read current context

Read (when present):
- Session notes: `{session_dir}/notes.md`
- Session info: `{session_dir}/session-info.json`
- For GitHub issue sessions: issue title/body
- For Speckit: `specs/<feature>/spec.md` and `specs/<feature>/plan.md`
- Project context: `.session/project-context/technical-context.md` and `constitution-summary.md`

### 3) Ask missing critical questions (minimal)

If key inputs are missing, ask up to **3** clarifying questions (one at a time). Prefer multiple-choice.
Stop early if sufficient.

### 4) Produce brainstorm doc in session directory

Create a new file at `{session_dir}/brainstorm.md` (the session directory already exists from `session.start`):
```markdown
---
date: YYYY-MM-DD
session_id: {SESSION_ID}
type: brainstorm
related:
  issue: {#123 or null}
  spec: {spec id or null}
status: draft
---

# Brainstorm: {Topic}

## Problem / Goal (WHAT)

- ...

## Non-goals / Out of scope

- ...

## Constraints & Assumptions

- ...

## Options (2-3)

### Option A: {name}
- Summary:
- Pros:
- Cons:
- Risks:

### Option B: {name}
...

## Recommendation

**Choose:** Option {A/B/C}

Rationale:
- ...

## Key Decisions

- D1: ...

## Open Questions

- Q1: ...

## Next Step

Recommended: invoke session.scope and use this brainstorm as input.
If you intentionally want to skip scope/spec, invoke session.plan directly.
```

### 5) Record reference in session notes

If the notes do not already contain a Brainstorm section, append:
```markdown
## Brainstorm
- {session_dir}/brainstorm.md
```

### 6) Handoff

If invoked directly by the user, suggest the next step:
- `invoke session.scope` (recommended) to turn the brainstorm into explicit boundaries
- or `invoke session.plan` if the user intentionally wants to skip scope/spec and accept the preflight warning
- or `session.clarify` if unresolved questions remain

If invoked by `session.start --brainstorm`, return the brainstorm path and let `session.start` continue the planning chain.
