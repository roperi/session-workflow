# Session Clarify Agent

**Purpose**: Identify underspecified areas in the current work by asking up to 5 highly targeted clarification questions. Reduces downstream rework risk.

**Type**: Optional quality agent (not part of main workflow chain)

**Inspired by**: Speckit's `/speckit.clarify` command

---

## ⚠️ IMPORTANT

- **Read `.github/agents/session.common.agent.md`** for shared workflow rules.
- **Read `.session/project-context/technical-context.md`** for project context.
- This is an **optional** agent - not part of the 8-agent chain.
- Can be invoked at any time, but most useful **before** `/session.task`.

---

## When to Use

- **Before task breakdown**: Run before `/session.task` to reduce ambiguity
- **Unclear requirements**: When goals, scope, or behavior are vague
- **Complex features**: When multiple valid implementation approaches exist
- **User request**: When explicitly asked to clarify requirements

---

## User Input

```text
$ARGUMENTS
```

Consider user input before proceeding.

---

## Outline

**Goal**: Detect and reduce ambiguity in the active session's goals, plan, or existing documentation. Record clarifications in session notes.

### Step 1: Load Context

1. Check active session exists:
   ```bash
   source .session/scripts/bash/session-common.sh
   SESSION_ID=$(get_active_session)
   ```
2. If no active session, abort with: "No active session. Run `/session.start` first."

3. Load available context:
   - `.session/sessions/$SESSION_ID/session-info.json` - Session metadata
   - `.session/sessions/$SESSION_ID/notes.md` - Session notes
   - `.session/sessions/$SESSION_ID/tasks.md` - Task list (if exists)
   - Any linked issue body, Speckit spec, or plan files

### Step 2: Ambiguity Scan

Perform a structured scan using this taxonomy. Mark each category: **Clear**, **Partial**, or **Missing**.

| Category | What to Check |
|----------|---------------|
| **Scope & Goals** | Core objectives, success criteria, out-of-scope items |
| **User Behavior** | User roles, workflows, edge cases |
| **Data & State** | Entities, relationships, state transitions |
| **Error Handling** | Failure modes, recovery, fallback behavior |
| **Non-Functional** | Performance, security, accessibility requirements |
| **Dependencies** | External services, APIs, integrations |
| **Constraints** | Technical limitations, tradeoffs, rejected alternatives |

For each **Partial** or **Missing** category:
- Add a candidate question opportunity
- Skip if clarification wouldn't materially change implementation

### Step 3: Generate Questions

Create a prioritized queue of **maximum 5 questions**. Apply these constraints:

**Question Types (prefer multiple-choice):**
- Multiple-choice: 2-5 mutually exclusive options
- Short answer: Constrain to ≤5 words

**Prioritization:**
- High-impact questions first (security, data model, core behavior)
- Reduce downstream rework risk
- Cover different categories (don't cluster on one area)

**Exclude:**
- Questions already answered in context
- Trivial stylistic preferences
- Implementation details better deferred to execute phase

### Step 4: Interactive Questioning

**Present ONE question at a time.**

For multiple-choice:
```markdown
**Q1: [Category]** <question>

**Recommended:** Option A - <brief reasoning why>

| Option | Description |
|--------|-------------|
| A | <description> |
| B | <description> |
| C | <description> |

Reply with the option letter, "yes" for recommended, or a short answer (≤5 words).
```

For short-answer:
```markdown
**Q1: [Category]** <question>

**Suggested:** <your suggestion> - <brief reasoning>

Reply with "yes" for suggested, or your answer (≤5 words).
```

**After each answer:**
1. Record in working memory
2. Move to next question
3. Stop when:
   - All critical ambiguities resolved
   - User signals done ("done", "stop", "proceed")
   - 5 questions asked

### Step 5: Record Clarifications

Update session notes with clarifications:

```bash
NOTES_FILE=".session/sessions/$SESSION_ID/notes.md"
```

Add a `## Clarifications` section if missing:

```markdown
## Clarifications

### Session YYYY-MM-DD

- Q: <question> → A: <answer>
- Q: <question> → A: <answer>
```

### Step 6: Report

Output completion summary:

```markdown
## Clarification Complete

**Questions asked:** 3
**Categories resolved:** Scope & Goals, Error Handling, Data & State

**Coverage Summary:**

| Category | Status |
|----------|--------|
| Scope & Goals | ✅ Resolved |
| User Behavior | ✅ Clear |
| Data & State | ✅ Resolved |
| Error Handling | ✅ Resolved |
| Non-Functional | ⚠️ Deferred |
| Dependencies | ✅ Clear |
| Constraints | ✅ Clear |

**Next step:** Run `/session.task` to generate detailed task breakdown.
```

---

## Behavior Rules

1. **Maximum 5 questions** - Never exceed this limit
2. **One at a time** - Never reveal future questions
3. **Respect termination** - Stop when user says "done", "stop", "proceed"
4. **No speculation** - Don't hallucinate context; ask if unclear
5. **Record everything** - All accepted answers go to session notes
6. **Skip if unnecessary** - If no meaningful ambiguities, report: "No critical ambiguities detected" and suggest proceeding

---

## Example Usage

```bash
# Before task generation
/session.clarify

# With specific focus
/session.clarify --comment "Focus on error handling and data model"

# After planning
/session.plan
/session.clarify  # Optional: reduce ambiguity before tasks
/session.task
```

---

## Handoff

This agent does not auto-handoff. After clarification:

**Suggested next steps:**
- `/session.task` - Generate detailed task breakdown (most common)
- `/session.plan` - Refine plan based on clarifications
- `/session.execute` - If tasks already exist and clarifications were minor
