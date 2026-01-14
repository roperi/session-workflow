# Session Workflow Tests

Manual test cases for the session workflow system.

**Last Tested**: 2025-12-04
**Tested By**: AI Session 2025-12-04-3

---

## Test Cases

### Test 1: Resume Active Session

**Command:**
```bash
.session/scripts/bash/session-start.sh --json
```

**Precondition:** Active session exists (ACTIVE_SESSION file present)

**Expected:** 
- `action: "resumed"`
- Returns existing session ID
- Does not create new session directory

**Result:** ✅ Pass

---

### Test 2: Wrap with Dirty Git (Hard Block)

**Command:**
```bash
echo "test" >> README.md
.session/scripts/bash/session-wrap.sh --json
git checkout README.md  # cleanup
```

**Expected:**
- `status: "blocked"`
- `validation.git_clean: false`
- Blocker message about uncommitted changes
- Exit code 1

**Result:** ✅ Pass

---

### Test 3: Start with Non-Existent Issue

**Command:**
```bash
.session/scripts/bash/session-start.sh --issue 999999 --json
```

**Expected:**
- Session created successfully
- No issue body in tasks.md (graceful failure)
- Issue number still recorded in session-info.json

**Result:** ✅ Pass (graceful degradation)

---

### Test 4: Start Unstructured Session

**Command:**
```bash
.session/scripts/bash/session-start.sh --goal "Investigate performance issue" --json
```

**Expected:**
- `type: "unstructured"`
- Goal appears in tasks.md
- No issue context section

**Result:** ✅ Pass

---

### Test 5: Start Speckit Session (No tasks.md)

**Command:**
```bash
.session/scripts/bash/session-start.sh --spec 001-delete-project --json
```

**Expected:**
- `type: "speckit"`
- No tasks.md file created (speckit uses spec's tasks.md)
- spec_dir recorded in session-info.json

**Result:** ✅ Pass

---

### Test 6: Previous Session Handoff

**Command:**
```bash
rm .session/ACTIVE_SESSION  # ensure no active session
.session/scripts/bash/session-start.sh --issue 566 --json
```

**Precondition:** At least one completed session exists

**Expected:**
- `previous_session.id` set to most recent completed session
- `previous_session.for_next_session` contains notes content
- `previous_session.incomplete_tasks` contains unchecked tasks

**Result:** ✅ Pass

---

### Test 7: Wrap with Empty Notes (Soft Warning)

**Command:**
```bash
echo "" > .session/sessions/{current}/notes.md
.session/scripts/bash/session-wrap.sh --json
```

**Expected:**
- `status: "ok"` (not blocked - soft warning only)
- `validation.notes_valid: false`
- Warning about minimal content
- Session still completes if git is clean

**Result:** ✅ Pass

---

### Test 8: Start with No Arguments

**Command:**
```bash
rm .session/ACTIVE_SESSION
.session/scripts/bash/session-start.sh
```

**Expected:**
- Error message: "Must specify --type, --issue, --spec, or --goal"
- Usage help displayed
- Exit code 1

**Result:** ✅ Pass

---

### Test 9: Make Targets

**Commands:**
```bash
make session-start ARGS="--issue 566"
make session-wrap
```

**Expected:**
- Both targets work correctly
- JSON output from session-start
- Validation output from session-wrap

**Result:** ✅ Pass

---

### Test 10: Session ID Increment

**Command:**
```bash
# Create multiple sessions on same day
.session/scripts/bash/session-start.sh --issue 1 --json  # 2025-12-04-1
# wrap, then:
.session/scripts/bash/session-start.sh --issue 2 --json  # 2025-12-04-2
```

**Expected:**
- Session IDs increment: YYYY-MM-DD-1, YYYY-MM-DD-2, etc.
- Counter resets on new day

**Result:** ✅ Pass

---

### Test 11: GitHub Issue Body Fetched

**Command:**
```bash
.session/scripts/bash/session-start.sh --issue 566 --json
cat .session/sessions/{session_id}/tasks.md
```

**Expected:**
- tasks.md contains "## Issue Context" section
- Issue body from GitHub included
- Requires `gh` CLI authenticated

**Result:** ✅ Pass

---

## Edge Cases Covered

| Scenario | Handling |
|----------|----------|
| No active session on wrap | Error with helpful message |
| No previous session on start | `previous_session: null` |
| Non-existent GitHub issue | Graceful - session created, no body |
| Git dirty on wrap | Hard block (exit 1) |
| Empty notes on wrap | Soft warning (still completes) |
| Missing "For Next Session" | Soft warning |
| Incomplete tasks | Soft warning + included in handoff |
| Speckit session | No tasks.md created |

---

## Running Tests

To run all tests manually:

```bash
# Ensure clean state
rm -f .session/ACTIVE_SESSION

# Test 1: Resume (need active session first)
.session/scripts/bash/session-start.sh --issue 1 --json
.session/scripts/bash/session-start.sh --json  # should resume

# Test 2: Git dirty
echo "test" >> README.md
.session/scripts/bash/session-wrap.sh --json
git checkout README.md

# Test 3-11: See individual test commands above
```

---

## Notes

- Tests require `gh` CLI for GitHub issue fetching
- Tests require `jq` for JSON parsing
- Session directories are created in `.session/sessions/`
- Clean up test sessions after testing: `rm -rf .session/sessions/YYYY-MM-DD-*`
