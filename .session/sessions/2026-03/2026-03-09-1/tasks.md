# Session Tasks: 2026-03-09-1

## Goal
GitHub Issue #38

## Issue Context
**Parent**: #34

## What

Update the workflow state machine in `session-state.sh` to support the new `scope` and `spec` steps, with backward compatibility for existing workflows.

## Deliverables

- [ ] Add `scope` and `spec` to `WORKFLOW_TRANSITIONS` in `session-state.sh`
- [ ] New valid transitions:
  - `start → scope` (development, spike)
  - `brainstorm → scope` (all)
  - `scope → spec` (development)
  - `scope → plan` (spike — skip spec)
  - `spec → plan` (development)
- [ ] **Backward compatibility**: `start → plan` still works but emits a deprecation warning: "ℹ️ Consider using scope/spec steps for better requirement clarity"
- [ ] Update `session-start.sh` next-step guidance: "invoke session.scope" instead of "invoke session.plan" for development/spike
- [ ] Update `detect_workflow` to recognize new steps
- [ ] Add preflight support for `scope` and `spec` steps
- [ ] Add `scope.md` and `spec.md` to `session-cleanup.sh` allowlist

### Per-Workflow Chains (Updated)

| Workflow | Chain |
|---|---|
| **development** | `start → scope → spec → plan → task → execute → validate → publish → finalize → wrap` |
| **spike** | `start → scope → plan → task → execute → wrap` |
| **maintenance** | `start → execute → wrap` (unchanged) |

### Tests

- [ ] Add regression test: `scope → spec → plan` transition (development)
- [ ] Add regression test: `scope → plan` transition (spike, skipping spec)
- [ ] Add regression test: `start → plan` backward compatibility with warning
- [ ] Verify existing tests still pass

## Dependencies

- This is the foundation — #35 and #36 depend on this for transition rules

## Tasks
<!-- AI will generate tasks based on issue context -->

## Progress
- Started: 2026-03-09T13:01:49Z
- Status: 0/0 complete
