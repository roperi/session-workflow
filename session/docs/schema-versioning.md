# Session Workflow Schema Versioning

## Overview

Two JSON files are written per session. Each carries a `schema_version` field.
Scripts that read these files must validate the version matches the expected
constant before trusting field names.

---

## `session-info.json` — current version `2.2`

**Constant**: `SESSION_INFO_SCHEMA_VERSION="2.2"` (in `session-common.sh`)

**Common fields** (all types):

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | string | Always `"2.2"` |
| `session_id` | string | `YYYY-MM-DD-N` format |
| `type` | string | `speckit` \| `github_issue` \| `unstructured` |
| `workflow` | string | `development` \| `spike` \| `maintenance` \| … |
| `stage` | string | `poc` \| `mvp` \| `production` |
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

## `state.json` — current version `1.0`

**Constant**: `STATE_SCHEMA_VERSION="1.0"` (in `session-common.sh`)

**Fields written by `create_session_state()`**:

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | string | Always `"1.0"` |
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

**Fields added by `set_workflow_step()`** (first preflight call):

| Field | Type | Description |
|-------|------|-------------|
| `current_step` | string | `plan` \| `task` \| `execute` \| `validate` \| `publish` \| `finalize` \| `wrap` |
| `step_status` | string | `in_progress` \| `completed` \| `failed` |
| `step_started_at` | ISO 8601 string | |
| `step_updated_at` | ISO 8601 string | |

### Version history

| Version | Change |
|---------|--------|
| `1.0` | Initial. All state.json fields. |

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
