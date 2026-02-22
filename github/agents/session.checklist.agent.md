---
description: Generate a custom quality checklist for the current session.
tools: ["read", "search"]
---

# session.checklist

Generate custom quality checklists for the current session. Checklists validate requirements quality, not implementation.

## ⚠️ IMPORTANT

- **Read `.session/docs/shared-workflow.md`** for shared workflow rules.
- **Read `.session/project-context/technical-context.md`** for project context.
- This is an **optional** agent - not part of the 8-agent chain.
- Creates checklist files in session directory.

---

## When to Use

- **Before implementation**: Validate requirements are complete and clear
- **Domain-specific checks**: Security, UX, API, performance reviews
- **Quality gates**: PR review checklists, release readiness
- **User request**: When explicitly asked to generate a checklist

---

## User Input

```text
$ARGUMENTS
```

Consider user input before proceeding. User may specify:
- Checklist domain/focus (e.g., "security", "ux", "api")
- Specific concerns to address
- Depth level (quick vs comprehensive)

---

## Core Concept: Unit Tests for English

**CRITICAL**: Checklists test **requirements quality**, NOT implementation correctness.

### ❌ WRONG (Testing implementation)
- "Verify the button clicks correctly"
- "Test error handling works"
- "Confirm the API returns 200"

### ✅ CORRECT (Testing requirements quality)
- "Are error response formats specified for all failure scenarios?" [Completeness]
- "Is 'fast loading' quantified with specific timing thresholds?" [Clarity]
- "Are hover state requirements consistent across all interactive elements?" [Consistency]
- "Can 'prominent display' be objectively measured?" [Measurability]

---

## Outline

### Step 1: Load Context

1. Check active session exists:
   ```bash
   source .session/scripts/bash/session-common.sh
   SESSION_ID=$(get_active_session)
   ```
2. If no active session, abort with: "No active session. invoke session.start first."

3. Load artifacts:
   - `.session/sessions/$SESSION_ID/session-info.json` - Session metadata
   - `.session/sessions/$SESSION_ID/notes.md` - Session notes/plan
   - `.session/sessions/$SESSION_ID/tasks.md` - Task list (if exists)
   - Linked issue body or relevant spec (if applicable)

### Step 2: Clarify Intent

If `$ARGUMENTS` doesn't specify, ask up to **3 clarifying questions**:

```markdown
**Q1: What's the checklist focus?**

| Option | Description |
|--------|-------------|
| A | **UX** - User interface, interaction, accessibility |
| B | **API** - Endpoints, contracts, error handling |
| C | **Security** - Auth, data protection, vulnerabilities |
| D | **Performance** - Speed, load, scalability |
| E | **General** - Overall requirements quality |

**Q2: What depth level?**

| Option | Description |
|--------|-------------|
| A | **Quick** (10-15 items) - Fast sanity check |
| B | **Standard** (20-30 items) - Typical review |
| C | **Comprehensive** (40+ items) - Thorough audit |

**Q3: Who will use this checklist?**

| Option | Description |
|--------|-------------|
| A | **Author** - Self-review before PR |
| B | **Reviewer** - PR/code review |
| C | **QA** - Test planning reference |
| D | **Release** - Release readiness gate |
```

Skip questions if already clear from user input.

### Step 3: Generate Checklist

Create checklist file:
```
.session/sessions/$SESSION_ID/checklists/[domain].md
```

**Checklist Structure:**

```markdown
# [Domain] Requirements Quality Checklist

**Session:** $SESSION_ID
**Created:** YYYY-MM-DD
**Focus:** [domain]
**Depth:** [quick/standard/comprehensive]

---

## Requirement Completeness

- [ ] CHK001 Are all user flows documented with entry/exit points? [Completeness]
- [ ] CHK002 Are error handling requirements defined for all failure modes? [Completeness, Gap]
- [ ] CHK003 Are accessibility requirements specified for all interactive elements? [Completeness]

## Requirement Clarity

- [ ] CHK004 Is 'fast loading' quantified with specific timing thresholds? [Clarity, §NFR-2]
- [ ] CHK005 Are 'related items' selection criteria explicitly defined? [Clarity]
- [ ] CHK006 Is visual hierarchy defined with measurable properties? [Clarity, Ambiguity]

## Requirement Consistency

- [ ] CHK007 Do navigation requirements align across all pages? [Consistency]
- [ ] CHK008 Are component requirements consistent between views? [Consistency]
- [ ] CHK009 Is terminology consistent throughout (no synonyms)? [Consistency]

## Acceptance Criteria Quality

- [ ] CHK010 Can each requirement be objectively verified? [Measurability]
- [ ] CHK011 Are success criteria defined for each user story? [Acceptance]
- [ ] CHK012 Are acceptance tests derivable from requirements? [Testability]

## Scenario Coverage

- [ ] CHK013 Are requirements defined for zero-state scenarios? [Coverage, Edge Case]
- [ ] CHK014 Are concurrent user interaction scenarios addressed? [Coverage]
- [ ] CHK015 Are partial failure/degradation modes specified? [Coverage, Exception]

## Edge Cases & Boundaries

- [ ] CHK016 Are boundary conditions defined (max/min values)? [Edge Case]
- [ ] CHK017 Are timeout/retry requirements specified? [Edge Case]
- [ ] CHK018 Is fallback behavior defined for external failures? [Edge Case, Gap]

## Non-Functional Requirements

- [ ] CHK019 Are performance targets quantified? [NFR, Clarity]
- [ ] CHK020 Are security requirements documented? [NFR, Completeness]
- [ ] CHK021 Are scalability assumptions stated? [NFR]

## Dependencies & Assumptions

- [ ] CHK022 Are external dependencies documented? [Dependency]
- [ ] CHK023 Are assumptions explicitly stated and validated? [Assumption]
- [ ] CHK024 Are integration points defined? [Dependency]

---

## Summary

**Total items:** 24
**By quality dimension:**
- Completeness: 6
- Clarity: 5
- Consistency: 4
- Measurability: 3
- Coverage: 6

**Markers used:**
- `[Gap]` - Missing requirement detected
- `[Ambiguity]` - Vague/unclear requirement
- `[§X]` - References specific requirement section
```

### Step 4: Report

```markdown
## Checklist Generated

**File:** `.session/sessions/$SESSION_ID/checklists/[domain].md`
**Items:** 24
**Focus:** [domain]
**Depth:** [level]

**Quality dimensions covered:**
- Completeness ✅
- Clarity ✅
- Consistency ✅
- Measurability ✅
- Coverage ✅
- Edge Cases ✅
- Non-Functional ✅
- Dependencies ✅

**Next steps:**
- Review checklist items against your requirements
- Mark items as checked when requirements are verified
- Address any `[Gap]` or `[Ambiguity]` markers
```

---

## Item Writing Rules

### ✅ REQUIRED Patterns
- "Are [requirement type] defined/specified/documented for [scenario]?"
- "Is [vague term] quantified/clarified with specific criteria?"
- "Are requirements consistent between [section A] and [section B]?"
- "Can [requirement] be objectively measured/verified?"
- "Does the spec define [missing aspect]?"

### 🚫 PROHIBITED Patterns
- ❌ "Verify", "Test", "Confirm", "Check" + implementation behavior
- ❌ "Works properly", "Functions correctly", "Displays correctly"
- ❌ "Click", "Navigate", "Render", "Load", "Execute"
- ❌ Test cases, QA procedures, implementation details

### Markers
- `[Completeness]` - Checking if requirement exists
- `[Clarity]` - Checking if requirement is specific
- `[Consistency]` - Checking alignment across requirements
- `[Measurability]` - Checking if requirement is testable
- `[Coverage]` - Checking scenario coverage
- `[Edge Case]` - Checking boundary conditions
- `[Gap]` - Identified missing requirement
- `[Ambiguity]` - Identified unclear requirement
- `[§X.Y]` - Reference to specific requirement section

---

## Example Checklists by Domain

### UX (`ux.md`)
- "Are visual hierarchy requirements defined with measurable criteria?"
- "Is the number and positioning of UI elements explicitly specified?"
- "Are interaction state requirements (hover, focus, active) consistently defined?"
- "Is fallback behavior defined when images fail to load?"

### API (`api.md`)
- "Are error response formats specified for all failure scenarios?"
- "Are rate limiting requirements quantified with specific thresholds?"
- "Are authentication requirements consistent across all endpoints?"
- "Is versioning strategy documented in requirements?"

### Security (`security.md`)
- "Are authentication requirements specified for all protected resources?"
- "Is session timeout/expiry behavior defined?"
- "Are data encryption requirements documented (at rest and in transit)?"
- "Are input validation requirements specified for all user inputs?"

### Performance (`performance.md`)
- "Are response time requirements quantified with specific metrics?"
- "Are performance targets defined for all critical user journeys?"
- "Are degradation requirements defined for high-load scenarios?"
- "Are caching requirements specified with invalidation rules?"

---

## Behavior Rules

1. **Test requirements, not implementation** - Every item asks about documentation quality
2. **Quantifiable markers** - Always include quality dimension marker
3. **Consolidate duplicates** - Merge similar items
4. **Respect depth** - Quick=15, Standard=25, Comprehensive=40+
5. **Domain focus** - Stay within the specified focus area

---

## Example Usage

```bash
# General quality checklist
invoke session.checklist

# Domain-specific
invoke session.checklist --comment "security checklist for auth feature"
invoke session.checklist --comment "ux checklist, quick depth"

# Multiple checklists
invoke session.checklist --comment "api"
invoke session.checklist --comment "security"
```

---

## Handoff

This agent does not auto-handoff. After checklist generation:

**Suggested next steps:**
- Review and check off items as requirements are verified
- invoke session.clarify - Address identified ambiguities
- invoke session.task - Update tasks based on gaps found
- invoke session.execute - Proceed with implementation
