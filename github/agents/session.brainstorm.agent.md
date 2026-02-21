---
description: Clarify WHAT to build and capture decisions as a version-controlled brainstorm doc.
tools: ["read", "write", "search"]
---

# session.brainstorm

Produce a concise brainstorm that clarifies **WHAT/WHY** (not detailed HOW), explores 2-3 viable approaches, and records decisions/open questions.

## ⚠️ IMPORTANT

- This is an **optional** agent (not part of the main 8-agent chain).
- **Write output under version control**: `docs/brainstorms/`.
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
.session/scripts/bash/session-preflight.sh --step plan --json
```

Notes:
- Using `--step plan` is intentional: brainstorm feeds planning; it should not advance execution steps.
- Use `repo_root` from JSON as the source of truth.

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

### 4) Produce brainstorm doc in docs/brainstorms/

Ensure directory exists:
```bash
mkdir -p docs/brainstorms
```

Create a new file:
- `docs/brainstorms/YYYY-MM-DD-{slug}-brainstorm.md`

Slug rules:
- lowercase
- hyphen-separated
- max ~6 words

Doc template:
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

Run `/session.plan` and reference this brainstorm.
```

### 5) Record reference in session notes

Append to `{session_dir}/notes.md`:
```markdown
## Brainstorm
- {relative path to brainstorm doc}
```

### 6) Handoff

Suggest next step:
- `/session.plan` (most common)
- or `/session.clarify` if unresolved questions remain
