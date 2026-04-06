# Session Workflow Schema Versioning

## Overview

Session start writes two core JSON files per session, and validation writes a
third session-scoped summary when it runs. Each structured JSON file carries a
`schema_version` field. Scripts that read these files must validate the version
matches the expected constant before trusting field names.

---

## `session-info.json` — current version `2.2`

**Constant**: `SESSION_INFO_SCHEMA_VERSION="2.2"` (in `session/scripts/bash/lib/session-paths.sh`)

**Common fields** (all types):

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | string | Always `"2.2"` |
| `session_id` | string | `YYYY-MM-DD-N` format |
| `type` | string | `speckit` \| `github_issue` \| `unstructured` |
| `workflow` | string | `development` \| `spike` \| `maintenance` \| `debug` \| `operational` |
| `stage` | string | `poc` \| `mvp` \| `production` |
| `read_only` | boolean \| absent | `true` only for maintenance audit sessions |
| `created_at` | ISO 8601 string | UTC creation timestamp |
| `parent_session_id` | string \| absent | Parent session ID (optional) |

**Type-specific fields**:

| Type | Extra fields |
|------|-------------|
| `speckit` | `spec_dir` (string) |
| `github_issue` | `issue_number` (int), `issue_title` (string) |
| `unstructured` | `goal` (string) |

### Version history

| Version | Change |
|---------|--------|
| `2.2` | Current. Added `parent_session` field. |
| `2.1` | Added `stage` field. |
| `2.0` | Initial versioned schema. |

---

## `state.json` — current version `1.2`

**Constant**: `STATE_SCHEMA_VERSION="1.2"` (in `session/scripts/bash/lib/session-paths.sh`)

`state.json` is local workflow bookkeeping. It is intentionally ignored from git via
`.session/sessions/**/state.json`; durable session history lives in sibling markdown
artifacts plus `session-info.json`.

**Fields written by `create_session_state()`**:

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | string | Always `"1.2"` |
| `session_id` | string | Matches session-info.json |
| `status` | string | `active` \| `completed` |
| `started_at` | ISO 8601 string | UTC |
| `ended_at` | ISO 8601 \| null | Set on wrap |
| `tasks.total` | int | 0 at creation |
| `tasks.completed` | int | 0 at creation |
| `tasks.current` | string \| null | |
| `git.branch` | string | Branch at session start |
| `git.last_commit` | string | Short SHA at session start |
| `notes_summary` | string | |
| `step_history` | array | Initialized with a completed `start` entry |
| `pause` | object | Active human checkpoint state; defaults to inactive fields |
| `current_step` | string | `start` at creation; later updated by workflow steps |
| `step_status` | string | `completed` at creation; later updated by workflow steps |
| `step_started_at` | ISO 8601 string | Start timestamp at creation |
| `step_updated_at` | ISO 8601 string | Start timestamp at creation |

**Fields updated by `set_workflow_step()`** (preflight/postflight calls):

| Field | Type | Description |
|-------|------|-------------|
| `current_step` | string | Updated to the active workflow step |
| `step_status` | string | `in_progress` \| `completed` \| `failed` |
| `step_started_at` | ISO 8601 string | Reset when a step starts |
| `step_updated_at` | ISO 8601 string | Updated on every state transition |

**`step_history` entry schema** (appended by `set_workflow_step()`):

| Field | Type | Description |
|-------|------|-------------|
| `step` | string | Workflow step name |
| `status` | string | `in_progress` → `completed` \| `failed` |
| `started_at` | ISO 8601 string | Set when step begins |
| `ended_at` | ISO 8601 \| null | Set when step completes/fails |
| `forced` | boolean | `true` if `--force` was used to bypass transition checks |

**`pause` schema** (written by pause helper functions in `session-state.sh`):

| Field | Type | Description |
|-------|------|-------------|
| `active` | boolean | `true` while waiting on a human checkpoint |
| `kind` | string \| null | `manual_test` or another pause type |
| `step` | string \| null | Workflow step that owns the pause |
| `task_id` | string \| null | Related task identifier when available |
| `summary` | string \| null | Short human-readable checkpoint summary |
| `required_action` | string \| null | What the user must do before resuming |
| `resume_command` | string \| null | Suggested resume command |
| `created_at` | ISO 8601 \| null | When the pause was recorded |
| `cleared_at` | ISO 8601 \| null | When the pause was cleared |
| `notes` | string \| null | Resume/confirmation notes |

### Version history

| Version | Change |
|---------|--------|
| `1.2` | Added `pause` object for local human checkpoints and resume guidance. |
| `1.1` | Added `step_history` array for append-only workflow audit trail. |
| `1.0` | Initial. All state.json fields. |

---

## `validation-results.json` — current version `1.0`

**Constant**: `VALIDATION_RESULTS_SCHEMA_VERSION="1.0"` (in `session/scripts/bash/lib/session-paths.sh`)

Validation writes the same JSON payload to two locations:

- `{session_dir}/validation-results.json` — durable session-scoped audit artifact
- `.session/validation-results.json` — latest local validation summary used by publish/review flows

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | string | Always `"1.0"` |
| `timestamp` | ISO 8601 string | UTC timestamp for the validation run |
| `session_id` | string \| null | Related session when one is active |
| `project_type` | string | Detected project type (`node`, `python`, `go`, etc.) |
| `overall` | string | `pass` \| `fail` |
| `can_publish` | boolean | Whether publish can proceed without known validation blockers |
| `summary` | string | Top-level validation summary |
| `status` | string | Script result status (`success` \| `error`) |
| `validation_checks` | array | Detailed per-check records emitted by `session-validate.sh` |
| `results` | object | Per-check map keyed by `check` name for easier downstream consumption |

### Version history

| Version | Change |
|---------|--------|
| `1.0` | Initial durable + local validation summary schema. |

---

## Validation

The function `validate_schema_version` in `session-common.sh` checks the
`schema_version` field in a JSON file against an expected constant and emits a
`[WARN]` if there is a mismatch. This allows forward-compatibility while
surfacing drift.

```bash
validate_schema_version "$info_file" "$SESSION_INFO_SCHEMA_VERSION"
validate_schema_version "$state_file" "$STATE_SCHEMA_VERSION"
```

---

## Adding a new session type

1. Add a `<type>)` branch to the `case $SESSION_TYPE in` block in
   `create_session_info()` in `session-start.sh`, writing the JSON for that type
   directly following the pattern of the existing cases (include `schema_version`,
   all common fields, then any type-specific fields).
2. Ensure the fields you emit are consistent with the schema described in this
   document. Bump `SESSION_INFO_SCHEMA_VERSION` if you make a breaking change.
3. Add the type to `resolve_tasks_file()` in `session-common.sh` if it needs a
   non-default task file path.
4. Update this document.
