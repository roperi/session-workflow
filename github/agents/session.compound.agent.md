---
description: Capture solved problems as version-controlled solution docs (institutional memory).
tools: ["*"]
---

# session.compound

Capture a non-trivial solved problem (bug fix, incident, tricky design) as a reusable solution doc.

## ⚠️ IMPORTANT

- This is an **optional** agent (not part of the main 8-agent chain).
- **Write output under version control**: `docs/solutions/`.
- Prefer durable learnings: root cause, fix, prevention, and how to detect recurrence.

## User Input

```text
$ARGUMENTS
```

---

## Outline

### 1) Load session + repo context (MANDATORY)

Run preflight:
```bash
.session/scripts/bash/session-preflight.sh --step wrap --json --force
```

Rationale: compound is typically post-implementation; we do not want to block on workflow transitions.

### 2) Identify what to compound

If user input names a topic/PR/issue, use it.
Otherwise, infer from:
- `{session_dir}/notes.md`
- recent git commits
- PR number (if exists)

If nothing meaningful was solved, report that and stop (do not create a doc).

### 3) Write solution doc in docs/solutions/

Ensure directory exists:
```bash
mkdir -p "docs/solutions/{category}"
```

Create a new file:
- `docs/solutions/{category}/YYYY-MM-DD-{slug}.md`

Category examples:
- `workflow/` (process, scripts, agent prompts)
- `bugs/` (root cause + fix)
- `infra/` (CI, tooling)
- `product/` (feature behavior decisions)

Doc template:
```markdown
---
date: YYYY-MM-DD
session_id: {SESSION_ID}
type: solution
category: {category}
related:
  issue: {#123 or null}
  pr: {#456 or null}
---

# {Title}

## Symptoms

- ...

## Root Cause

- ...

## Fix

- ...

## Verification

- Commands run / tests
- Expected output

## Prevention

- Guardrails, tests, monitoring, docs updates

## Notes / Links

- ...
```

### 4) Record reference in session notes

Append to `{session_dir}/notes.md`:
```markdown
## Compounded Knowledge
- {relative path to solution doc}
```

### 5) Handoff

No required next step (optional). If session is ongoing, suggest returning to the main chain.
