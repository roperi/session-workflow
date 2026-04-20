#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

log() {
  echo "$*"
}

vlog() {
  if [[ "${TEST_VERBOSE:-0}" == "1" ]]; then
    echo "$*"
  fi
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    fail "assert_eq failed: expected='$expected' actual='$actual' ${msg}"
  fi
}

assert_file_exists() {
  local path="$1"
  [[ -f "$path" ]] || fail "expected file to exist: $path"
}

assert_dir_exists() {
  local path="$1"
  [[ -d "$path" ]] || fail "expected dir to exist: $path"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

make_tmp_repo() {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/repo"
  (cd "$tmp/repo" && git init -q)
  echo "$tmp/repo"
}

install_session_workflow_into_repo() {
  local repo_root="$1"
  mkdir -p "$repo_root/.session/scripts/bash" "$repo_root/.session/templates"
  cp "$ROOT_DIR"/session/scripts/bash/*.sh "$repo_root/.session/scripts/bash/"
  cp "$ROOT_DIR"/session/scripts/update-wrapper.sh "$repo_root/.session/update.sh"
  # Copy lib sub-directory (session-common.sh now sources these)
  mkdir -p "$repo_root/.session/scripts/bash/lib"
  cp "$ROOT_DIR"/session/scripts/bash/lib/*.sh "$repo_root/.session/scripts/bash/lib/"
  cp "$ROOT_DIR"/session/templates/*.md "$repo_root/.session/templates/" 2>/dev/null || true
  chmod +x "$repo_root/.session/scripts/bash"/*.sh
  chmod +x "$repo_root/.session/update.sh"

  cat > "$repo_root/.gitignore" <<'EOF'
.session/ACTIVE_SESSION
.session/validation-results.json
.session/sessions/**/state.json
EOF
}

write_audit_fixture_session() {
  local session_dir="$1"
  local session_id="$2"
  local workflow="${3:-development}"
  local state_schema="${4:-1.2}"
  local step_count="${5:-6}"

  mkdir -p "$session_dir"

  cat > "${session_dir}/session-info.json" <<EOF
{
  "schema_version": "2.2",
  "session_id": "${session_id}",
  "type": "unstructured",
  "workflow": "${workflow}",
  "stage": "production",
  "created_at": "2026-03-01T00:00:00Z",
  "goal": "Synthetic audit fixture"
}
EOF

  cat > "${session_dir}/tasks.md" <<'EOF'
# Tasks

- [x] T001 Synthetic completed task
EOF

  cat > "${session_dir}/notes.md" <<'EOF'
# Session Notes

## Summary

Synthetic audit fixture.

## For Next Session
- Nothing pending.
EOF

  cat > "${session_dir}/next.md" <<'EOF'
# Next Session

- Nothing pending.
EOF

  cat > "${session_dir}/plan.md" <<'EOF'
# Plan

- Synthetic audit fixture
EOF

  cat > "${session_dir}/scope.md" <<'EOF'
# Scope

- Synthetic audit fixture
EOF

  cat > "${session_dir}/spec.md" <<'EOF'
# Spec

- [x] Synthetic acceptance criterion
EOF

  jq -n \
    --arg schema_version "$state_schema" \
    --arg session_id "$session_id" \
    --argjson step_count "$step_count" \
    '{
      schema_version: $schema_version,
      session_id: $session_id,
      status: "completed",
      started_at: "2026-03-01T00:00:00Z",
      ended_at: "2026-03-01T00:10:00Z",
      tasks: {
        total: 1,
        completed: 1,
        current: null
      },
      git: {
        branch: "main",
        last_commit: "abc1234"
      },
      notes_summary: "Synthetic audit fixture",
      step_history: (
        [{
          step: "start",
          status: "completed",
          started_at: "2026-03-01T00:00:00Z",
          ended_at: "2026-03-01T00:00:01Z",
          forced: false
        }] + [
          range(0; $step_count) | {
            step: ("synthetic-step-\(.)"),
            status: "completed",
            started_at: "2026-03-01T00:00:00Z",
            ended_at: "2026-03-01T00:00:01Z",
            forced: false
          }
        ]
      ),
      pause: {
        active: false,
        kind: null,
        step: null,
        task_id: null,
        summary: null,
        required_action: null,
        resume_command: null,
        created_at: null,
        cleared_at: null,
        notes: null
      },
      current_step: "wrap",
      step_status: "completed",
      step_started_at: "2026-03-01T00:00:00Z",
      step_updated_at: "2026-03-01T00:10:00Z"
    }' > "${session_dir}/state.json"
}

seed_fixture_repo() {
  local repo_root="$1"
  (
    cd "$repo_root"
    git config user.name "Session Workflow Tests"
    git config user.email "session-workflow-tests@example.com"
    git add .
    git commit -qm "test: seed session workflow fixture"
  )
}

sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    fail "missing SHA-256 tool"
  fi
}

main() {
  require_cmd git
  require_cmd jq

  log "Running session-workflow bash tests..."

  local repo_root
  repo_root=$(make_tmp_repo)
  local tmp_base
  tmp_base=$(dirname "$repo_root")

  if [[ "${TEST_KEEP_TMP:-0}" == "1" ]]; then
    # Expand $tmp_base at trap definition time (avoid relying on locals at EXIT).
    # shellcheck disable=SC2064
    trap "echo \"Keeping temp dir: $tmp_base\" >&2" EXIT
    log "Temp repo: $repo_root"
  else
    # Expand $tmp_base at trap definition time (avoid relying on locals at EXIT).
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp_base'" EXIT
    vlog "Temp repo: $repo_root"
  fi

  install_session_workflow_into_repo "$repo_root"
  seed_fixture_repo "$repo_root"

  cd "$repo_root"

  # 1) Start unstructured session (JSON)
  log "1) session-start (JSON)"
  local start_json session_id repo_root_json year_month session_dir
  start_json=$(./.session/scripts/bash/session-start.sh --json "Test goal")
  vlog "start_json: $start_json"
  assert_eq "ok" "$(echo "$start_json" | jq -r '.status')" "session-start status"

  repo_root_json=$(echo "$start_json" | jq -r '.repo_root')
  assert_eq "$repo_root" "$repo_root_json" "repo_root should be deterministic"

  session_id=$(echo "$start_json" | jq -r '.session.id')
  [[ -n "$session_id" && "$session_id" != "null" ]] || fail "missing session_id"

  year_month=$(echo "$session_id" | cut -d'-' -f1,2)
  session_dir=".session/sessions/${year_month}/${session_id}"

  assert_file_exists ".session/ACTIVE_SESSION"
  assert_dir_exists "$session_dir"
  assert_file_exists "$session_dir/session-info.json"
  assert_file_exists "$session_dir/state.json"
  assert_file_exists "$session_dir/notes.md"
  assert_file_exists "$session_dir/next.md"
  assert_file_exists "$session_dir/tasks.md"

  assert_eq "unstructured" "$(jq -r '.type' "$session_dir/session-info.json")" "session type"
  assert_eq "development" "$(jq -r '.workflow' "$session_dir/session-info.json")" "workflow default"
  assert_eq "production" "$(jq -r '.stage' "$session_dir/session-info.json")" "stage default"
  assert_eq "$session_dir/next.md" "$(echo "$start_json" | jq -r '.session.files.next')" "session JSON should surface next.md"

  # 2) session-handoff-list should include the created session
  log "2) session-handoff-list (JSON)"
  local list_json
  list_json=$(./.session/scripts/bash/session-handoff-list.sh --json)
  vlog "list_json: $list_json"
  assert_eq "ok" "$(echo "$list_json" | jq -r '.status')" "handoff list status"
  assert_eq "$session_id" "$(echo "$list_json" | jq -r '.sessions[0].id')" "most recent session should be first"
  assert_eq "$session_dir/next.md" "$(echo "$list_json" | jq -r '.sessions[0].files.next')" "handoff list should surface next.md"

  # 3) Preflight plan should succeed
  log "3) session-preflight plan (JSON)"
  local preflight_plan_json
  preflight_plan_json=$(./.session/scripts/bash/session-preflight.sh --step plan --json)
  vlog "preflight_plan_json: $preflight_plan_json"
  assert_eq "ok" "$(echo "$preflight_plan_json" | jq -r '.status')" "preflight plan status"
  assert_eq "$repo_root" "$(echo "$preflight_plan_json" | jq -r '.repo_root')" "preflight repo_root"

  # 4) Attempt to move to execute while plan is in_progress should warn + exit 2
  log "4) session-preflight execute (expects interrupted warning + exit 2)"
  set +e
  local preflight_execute_json
  preflight_execute_json=$(./.session/scripts/bash/session-preflight.sh --step execute --json)
  local exit_code=$?
  set -e
  vlog "preflight_execute_json: $preflight_execute_json"
  assert_eq "2" "$exit_code" "expected interrupted-session exit code"
  assert_eq "warning" "$(echo "$preflight_execute_json" | jq -r '.status')" "expected warning JSON"

  # 5) Complete plan, then task should be allowed
  log "5) mark plan completed; preflight task"
  # shellcheck source=/dev/null
  source ./.session/scripts/bash/session-common.sh
  set_workflow_step "$session_id" "plan" "completed" >/dev/null

  local preflight_task_json
  preflight_task_json=$(./.session/scripts/bash/session-preflight.sh --step task --json)
  vlog "preflight_task_json: $preflight_task_json"
  assert_eq "ok" "$(echo "$preflight_task_json" | jq -r '.status')" "preflight task status"

  # 6) Complete task, then execute should be allowed
  log "6) mark task completed; preflight execute"
  set_workflow_step "$session_id" "task" "completed" >/dev/null
  local preflight_exec_ok_json
  preflight_exec_ok_json=$(./.session/scripts/bash/session-preflight.sh --step execute --json)
  vlog "preflight_exec_ok_json: $preflight_exec_ok_json"
  assert_eq "ok" "$(echo "$preflight_exec_ok_json" | jq -r '.status')" "preflight execute status"

  # 7) Wrap should clear ACTIVE_SESSION
  log "7) mark execute completed; wrap clears ACTIVE_SESSION"
  # Mark execute completed to avoid interrupted warnings
  set_workflow_step "$session_id" "execute" "completed" >/dev/null
  local wrap_json
  wrap_json=$(././.session/scripts/bash/session-wrap.sh --json)
  vlog "wrap_json: $wrap_json"
  assert_eq "ok" "$(echo "$wrap_json" | jq -r '.status')" "wrap status"
  [[ ! -f ".session/ACTIVE_SESSION" ]] || fail "ACTIVE_SESSION should be cleared after wrap"
  assert_eq "docs: Session ${session_id} wrap-up [skip ci]" "$(git log -1 --pretty=%s)" "wrap should create the archival commit"
  [[ -z "$(git status --porcelain)" ]] || fail "git should be clean after wrap archival commit"

  # 7b) Wrap should block on unrelated dirty paths and keep session active
  log "7b) wrap blocks on unrelated dirty paths"
  local dirty_wrap_start_json dirty_wrap_id dirty_wrap_ym dirty_wrap_dir dirty_wrap_json dirty_wrap_exit head_before_block dirty_wrap_recover_json
  dirty_wrap_start_json=$(./.session/scripts/bash/session-start.sh --json "Dirty wrap block")
  dirty_wrap_id=$(echo "$dirty_wrap_start_json" | jq -r '.session.id')
  dirty_wrap_ym=$(echo "$dirty_wrap_id" | cut -d'-' -f1,2)
  dirty_wrap_dir=".session/sessions/${dirty_wrap_ym}/${dirty_wrap_id}"
  set_workflow_step "$dirty_wrap_id" "execute" "completed" >/dev/null
  head_before_block=$(git rev-parse HEAD)
  echo "scratch" > unrelated.txt
  set +e
  dirty_wrap_json=$(./.session/scripts/bash/session-wrap.sh --json)
  dirty_wrap_exit=$?
  set -e
  [[ "$dirty_wrap_exit" != "0" ]] || fail "wrap should fail when unrelated dirty changes are present"
  assert_eq "error" "$(echo "$dirty_wrap_json" | jq -r '.status')" "blocked wrap should return error JSON"
  echo "$dirty_wrap_json" | jq -e '.dirty_paths[] | select(. == "unrelated.txt")' >/dev/null \
    || fail "blocked wrap should report unrelated dirty paths"
  assert_eq "$head_before_block" "$(git rev-parse HEAD)" "wrap should not create a commit when blocked"
  [[ -f ".session/ACTIVE_SESSION" ]] || fail "ACTIVE_SESSION should remain while wrap is blocked"
  assert_eq "completed" "$(jq -r '.step_status' "$dirty_wrap_dir/state.json")" "blocked wrap should not rewrite state after execute completion"
  rm -f unrelated.txt
  dirty_wrap_recover_json=$(./.session/scripts/bash/session-wrap.sh --json)
  assert_eq "ok" "$(echo "$dirty_wrap_recover_json" | jq -r '.status')" "wrap should succeed after unrelated dirty changes are removed"
  [[ ! -f ".session/ACTIVE_SESSION" ]] || fail "ACTIVE_SESSION should be cleared after recovered wrap"
  [[ -z "$(git status --porcelain)" ]] || fail "git should be clean after recovered wrap"

  # 7c) Wrap should restore session state if the archival commit fails
  log "7c) wrap restores state when archival commit fails"
  local hook_wrap_start_json hook_wrap_id hook_wrap_ym hook_wrap_dir hook_wrap_json hook_wrap_exit hook_wrap_recover_json
  hook_wrap_start_json=$(./.session/scripts/bash/session-start.sh --json "Hook blocked wrap")
  hook_wrap_id=$(echo "$hook_wrap_start_json" | jq -r '.session.id')
  hook_wrap_ym=$(echo "$hook_wrap_id" | cut -d'-' -f1,2)
  hook_wrap_dir=".session/sessions/${hook_wrap_ym}/${hook_wrap_id}"
  set_workflow_step "$hook_wrap_id" "execute" "completed" >/dev/null
  mkdir -p .git/hooks
  cp "$ROOT_DIR/.git-hooks/pre-commit" .git/hooks/pre-commit
  # Overwrite with failing hook for testing
  cat > .git/hooks/pre-commit <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x .git/hooks/pre-commit
  set +e
  hook_wrap_json=$(./.session/scripts/bash/session-wrap.sh --json)
  hook_wrap_exit=$?
  set -e
  [[ "$hook_wrap_exit" != "0" ]] || fail "wrap should fail when the archival commit itself fails"
  assert_eq "error" "$(echo "$hook_wrap_json" | jq -r '.status')" "commit-failure wrap should return error JSON"
  [[ -f ".session/ACTIVE_SESSION" ]] || fail "ACTIVE_SESSION should remain after archival commit failure"
  assert_eq "active" "$(jq -r '.status' "$hook_wrap_dir/state.json")" "session status should remain active after archival commit failure"
  assert_eq "execute" "$(jq -r '.current_step' "$hook_wrap_dir/state.json")" "current_step should be restored after archival commit failure"
  assert_eq "completed" "$(jq -r '.step_status' "$hook_wrap_dir/state.json")" "step_status should be restored after archival commit failure"
  git diff --cached --quiet --exit-code || fail "archival commit failure should leave no staged wrap artifacts"
  rm -f .git/hooks/pre-commit
  hook_wrap_recover_json=$(./.session/scripts/bash/session-wrap.sh --json)
  assert_eq "ok" "$(echo "$hook_wrap_recover_json" | jq -r '.status')" "wrap should succeed after archival commit failure is resolved"
  [[ ! -f ".session/ACTIVE_SESSION" ]] || fail "ACTIVE_SESSION should be cleared after recovered archival commit"
  [[ -z "$(git status --porcelain)" ]] || fail "git should be clean after recovered archival commit"

  # 7d) Wrap should drop tracked state.json from the archival commit
  log "7d) wrap drops tracked state.json from the index"
  local tracked_wrap_start_json tracked_wrap_id tracked_wrap_ym tracked_wrap_dir tracked_wrap_json
  tracked_wrap_start_json=$(./.session/scripts/bash/session-start.sh --json "Tracked state wrap")
  tracked_wrap_id=$(echo "$tracked_wrap_start_json" | jq -r '.session.id')
  tracked_wrap_ym=$(echo "$tracked_wrap_id" | cut -d'-' -f1,2)
  tracked_wrap_dir=".session/sessions/${tracked_wrap_ym}/${tracked_wrap_id}"
  set_workflow_step "$tracked_wrap_id" "execute" "completed" >/dev/null
  git add -f -- "$tracked_wrap_dir"
  git commit -qm "test: simulate tracked state bookkeeping"
  git ls-files --error-unmatch "$tracked_wrap_dir/state.json" >/dev/null 2>&1 \
    || fail "state.json should be tracked before wrap regression test"
  tracked_wrap_json=$(./.session/scripts/bash/session-wrap.sh --json)
  assert_eq "ok" "$(echo "$tracked_wrap_json" | jq -r '.status')" "wrap should succeed with tracked state.json"
  git ls-files --error-unmatch "$tracked_wrap_dir/state.json" >/dev/null 2>&1 \
    && fail "wrap should remove state.json from the archival commit/index"
  [[ -f "$tracked_wrap_dir/state.json" ]] || fail "wrap should preserve the local state.json file"
  git check-ignore -q "$tracked_wrap_dir/state.json" \
    || fail "state.json should remain ignored after wrap"
  [[ -z "$(git status --porcelain)" ]] || fail "git should be clean after tracked state.json wrap"

  # 7e) Validate should ignore tracked state.json bookkeeping dirtiness
  log "7e) validate ignores tracked state.json bookkeeping"
  local validate_state_start_json validate_state_id validate_state_ym validate_state_dir validate_state_json
  validate_state_start_json=$(./.session/scripts/bash/session-start.sh --json "Tracked state validate")
  validate_state_id=$(echo "$validate_state_start_json" | jq -r '.session.id')
  validate_state_ym=$(echo "$validate_state_id" | cut -d'-' -f1,2)
  validate_state_dir=".session/sessions/${validate_state_ym}/${validate_state_id}"
  set_workflow_step "$validate_state_id" "execute" "completed" >/dev/null
  git add -f -- "$validate_state_dir"
  git commit -qm "test: track state for validate"
  ./.session/scripts/bash/session-preflight.sh --step validate --json >/dev/null
  assert_eq "$validate_state_dir/state.json" "$(git diff --name-only)" "validate preflight should only dirty state.json"
  validate_state_json=$(./.session/scripts/bash/session-validate.sh --json --skip-lint --skip-tests --skip-spec)
  assert_eq "pass" "$(echo "$validate_state_json" | jq -r '.validation_checks[] | select(.check == "git_status") | .status')" "validate should ignore volatile state.json changes"
  assert_file_exists ".session/validation-results.json"
  assert_file_exists "$validate_state_dir/validation-results.json"
  assert_eq "1.0" "$(jq -r '.schema_version' ".session/validation-results.json")" "local validation summary should carry schema version"
  assert_eq "$validate_state_id" "$(jq -r '.session_id' ".session/validation-results.json")" "local validation summary should record the session id"
  assert_eq "$validate_state_id" "$(jq -r '.session_id' "$validate_state_dir/validation-results.json")" "session-scoped validation summary should record the session id"
  assert_eq "pass" "$(jq -r '.overall' "$validate_state_dir/validation-results.json")" "session-scoped validation summary should persist the overall pass/fail state"
  ./.session/scripts/bash/session-postflight.sh --step validate --json >/dev/null
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null

  # 7f) session-audit reads the persisted session-scoped validation summary
  log "7f) session-audit consumes persisted validation results"
  local validate_audit_json
  validate_audit_json=$(./.session/scripts/bash/session-audit.sh --json --session "$validate_state_id")
  assert_eq "ok" "$(echo "$validate_audit_json" | jq -r '.status')" "session-audit should return ok JSON status"
  assert_eq "1" "$(echo "$validate_audit_json" | jq -r '.summary.total_sessions')" "session-audit should report one audited session"
  assert_eq "$validate_state_id" "$(echo "$validate_audit_json" | jq -r '.sessions[0].id')" "session-audit should return the requested session"
  assert_eq "session" "$(echo "$validate_audit_json" | jq -r '.sessions[0].checks[] | select(.check == "validation") | .details.source')" "session-audit should prefer the session-scoped validation summary"
  assert_eq "pass" "$(echo "$validate_audit_json" | jq -r '.sessions[0].checks[] | select(.check == "validation") | .status')" "session-audit should report persisted passing validation results"
  echo "$validate_audit_json" | jq -e '.summary.follow_up' >/dev/null \
    || fail "session-audit JSON summary should expose follow_up counts"

  # 7g) session-audit --summary keeps the default latest-session selection after wrap
  log "7g) session-audit --summary preserves default latest-session selection"
  local default_audit_summary_json
  default_audit_summary_json=$(./.session/scripts/bash/session-audit.sh --summary --json)
  assert_eq "latest" "$(echo "$default_audit_summary_json" | jq -r '.selection.mode')" \
    "session-audit --summary should preserve the default latest-session selection when no active session exists"
  assert_eq "1" "$(echo "$default_audit_summary_json" | jq -r '.summary.total_sessions')" \
    "session-audit --summary should audit the default latest session only"

  # 7h) session-audit summary surfaces the key follow-up dimensions
  log "7h) session-audit summary surfaces key follow-up dimensions"
  local validate_audit_summary
  validate_audit_summary=$(./.session/scripts/bash/session-audit.sh --summary --session "$validate_state_id")
  echo "$validate_audit_summary" | grep -q "Missing/thin artifacts:" \
    || fail "session-audit summary should surface artifact follow-up counts"
  echo "$validate_audit_summary" | grep -q "Missing/unavailable validation evidence:" \
    || fail "session-audit summary should surface validation follow-up counts"
  echo "$validate_audit_summary" | grep -q "Incomplete non-\\[SKIP\\] tasks:" \
    || fail "session-audit summary should surface incomplete task follow-up counts"
  echo "$validate_audit_summary" | grep -q "Weak/missing handoff content:" \
    || fail "session-audit summary should surface handoff follow-up counts"

  # 7i) session-audit handles large --all JSON output and suppresses schema-warning floods
  log "7i) session-audit handles large --all JSON output without schema-warning floods"
  local fixture_dir fixture_id audit_all_err audit_all_json audit_all_exit expected_total

  cat > .session/validation-results.json <<'EOF'
{
  "timestamp": "2026-03-01T00:00:00Z",
  "session_id": "unrelated-session",
  "overall": "pass",
  "can_publish": true,
  "validation_checks": []
}
EOF

  for n in $(seq 1 2); do
    fixture_id=$(printf '2026-02-%02d-1' "$n")
    fixture_dir=".session/sessions/2026-02/${fixture_id}"
    write_audit_fixture_session "$fixture_dir" "$fixture_id" "development" "1.1" 12
  done

  for n in $(seq 1 20); do
    fixture_id=$(printf '2026-01-%02d-9' "$n")
    fixture_dir=".session/sessions/2026-01/${fixture_id}"
    write_audit_fixture_session "$fixture_dir" "$fixture_id" "development" "1.2" 500
  done

  expected_total=$(find .session/sessions -mindepth 2 -maxdepth 2 -type d | wc -l | tr -d ' ')
  audit_all_err=$(mktemp)
  set +e
  audit_all_json=$(./.session/scripts/bash/session-audit.sh --all --json 2>"$audit_all_err")
  audit_all_exit=$?
  set -e
  assert_eq "0" "$audit_all_exit" "session-audit --all --json should succeed for large histories"
  assert_eq "ok" "$(echo "$audit_all_json" | jq -r '.status')" "session-audit should return ok status for large histories"
  assert_eq "all" "$(echo "$audit_all_json" | jq -r '.selection.mode')" "session-audit should preserve all-selection mode"
  assert_eq "$expected_total" "$(echo "$audit_all_json" | jq -r '.summary.total_sessions')" "session-audit should report every selected session"
  if grep -q "Schema version mismatch" "$audit_all_err"; then
    fail "session-audit should not flood stderr with schema mismatch warnings"
  fi
  if grep -q "Argument list too long" "$audit_all_err"; then
    fail "session-audit should not overflow jq arguments on large histories"
  fi
  rm -f "$audit_all_err"

  # 8) Start a chained session with git context scaffold
  log "8) session-start --continues-from + --git-context"
  local start2_json session_id2 year_month2 session_dir2
  start2_json=$(./.session/scripts/bash/session-start.sh --json --continues-from "$session_id" --git-context "Test goal 2")
  vlog "start2_json: $start2_json"
  assert_eq "ok" "$(echo "$start2_json" | jq -r '.status')" "session-start (chained) status"
  assert_eq "$session_id" "$(echo "$start2_json" | jq -r '.session.parent_session_id')" "parent_session_id should be set"
  assert_eq "$session_id" "$(echo "$start2_json" | jq -r '.previous_session.id')" "previous_session should be explicit parent"
  [[ -n "$(echo "$start2_json" | jq -r '.previous_session.staleness.classification')" ]] || fail "missing staleness classification"

  session_id2=$(echo "$start2_json" | jq -r '.session.id')
  year_month2=$(echo "$session_id2" | cut -d'-' -f1,2)
  session_dir2=".session/sessions/${year_month2}/${session_id2}"
  assert_file_exists "$session_dir2/notes.md"
  grep -q "^## Git Context (auto)" "$session_dir2/notes.md" || fail "expected Git Context scaffold in notes"

  # Wrap second session
  set_workflow_step "$session_id2" "execute" "completed" >/dev/null
  ././.session/scripts/bash/session-wrap.sh --json >/dev/null
  [[ ! -f ".session/ACTIVE_SESSION" ]] || fail "ACTIVE_SESSION should be cleared after wrap (session2)"

  # 9) --continues-from should error for missing session
  log "9) session-start --continues-from missing session (expects error)"
  set +e
  local start_missing_json
  start_missing_json=$(./.session/scripts/bash/session-start.sh --json --continues-from 2099-01-01-1 "X")
  local missing_exit=$?
  set -e
  [[ "$missing_exit" != "0" ]] || fail "expected non-zero exit for missing continues-from"
  assert_eq "error" "$(echo "$start_missing_json" | jq -r '.status')" "expected error JSON for missing continues-from"

  # 10) --comment produces valid JSON (F-3 / F-26 regression: no blank lines in instructions)
  log "10) session-start --comment produces valid JSON instructions array"
  local start_comment_json
  start_comment_json=$(./.session/scripts/bash/session-start.sh --json --comment "hello world" "Commented goal")
  echo "$start_comment_json" | jq -e '.instructions | length > 0' >/dev/null || fail "instructions array empty"
  # Validate no null/empty entries in instructions
  local null_count
  null_count=$(echo "$start_comment_json" | jq '[.instructions[] | select(. == null or . == "")] | length')
  assert_eq "0" "$null_count" "instructions must have no null/empty entries"
  # Confirm user instruction appears
  echo "$start_comment_json" | jq -e '.instructions[] | select(test("hello world"))' >/dev/null \
    || fail "user comment not found in instructions"
  # Wrap to clean up
  local s3_id
  s3_id=$(echo "$start_comment_json" | jq -r '.session.id')
  set_workflow_step "$s3_id" "execute" "completed" >/dev/null
  ././.session/scripts/bash/session-wrap.sh --json >/dev/null

  # 11) for_next_session remains compatible with legacy notes handoff content
  log "11) for_next_session remains compatible with legacy notes handoff content"
  local start4_json s4_id s4_year_month s4_dir
  start4_json=$(./.session/scripts/bash/session-start.sh --json "Notes continuity goal")
  s4_id=$(echo "$start4_json" | jq -r '.session.id')
  s4_year_month=$(echo "$s4_id" | cut -d'-' -f1,2)
  s4_dir=".session/sessions/${s4_year_month}/${s4_id}"
  assert_file_exists "${s4_dir}/next.md"
  # Populate the legacy "For Next Session" section for fallback compatibility
  cat > "${s4_dir}/notes.md" <<'EOF'
# Session Notes: fallback-test

## Summary

## Key Decisions

## Blockers/Issues

## For Next Session
- carry this forward

## Technical Notes (optional)
EOF
  set_workflow_step "$s4_id" "execute" "completed" >/dev/null
  ././.session/scripts/bash/session-wrap.sh --json >/dev/null
  # Chain a new session and check for_next_session is populated
  local start5_json
  start5_json=$(./.session/scripts/bash/session-start.sh --json --continues-from "$s4_id" "Continuation goal")
  local for_next
  for_next=$(echo "$start5_json" | jq -r '.previous_session.for_next_session')
  [[ -n "$for_next" && "$for_next" != "null" ]] || fail "for_next_session should not be empty after wrap (F-4 regression)"
  echo "$for_next" | grep -q "carry this forward" \
    || fail "for_next_session should fall back to notes.md content when next.md is still empty"
  assert_eq "${s4_dir}/next.md" "$(echo "$start5_json" | jq -r '.previous_session.next_file')" "previous_session.next_file should surface next.md path"
  # Wrap the continuation session
  local s5_id
  s5_id=$(echo "$start5_json" | jq -r '.session.id')
  set_workflow_step "$s5_id" "execute" "completed" >/dev/null
  ././.session/scripts/bash/session-wrap.sh --json >/dev/null

  # 12) count_tasks fallback: phase-based template (no ## Tasks heading) (F-16 regression)
  log "12) count_tasks works on phase-based template (no ## Tasks section)"
  local phase_tasks_file="${s4_dir}/phase_tasks_test.md"
  cat > "$phase_tasks_file" << 'TMPL'
# Tasks: test

## Phase 1: Setup
- [ ] T001 First task
- [x] T002 Done task

## Phase 2: Core
- [ ] T003 Another task
TMPL
  # Source the lib and call count_tasks directly
  # shellcheck disable=SC1090
  source ./.session/scripts/bash/lib/session-output.sh
  # shellcheck disable=SC1090
  source ./.session/scripts/bash/lib/session-paths.sh
  # shellcheck disable=SC1090
  source ./.session/scripts/bash/lib/session-tasks.sh
  local task_counts
  task_counts=$(count_tasks "$phase_tasks_file")
  assert_eq "3:1" "$task_counts" "count_tasks on phase-based template (3 total, 1 done)"

  # 13) session-cleanup: removes errant root files, moves misplaced session dir
  log "13) session-cleanup removes errant files and moves misplaced session dir"
  # Drop errant files at .session/ root
  echo "junk" > .session/errant-file.txt
  mkdir -p .session/daily-summaries
  # Create a misplaced session dir directly under .session/sessions/
  local misplaced_id="2026-01-01-9"
  mkdir -p ".session/sessions/${misplaced_id}"
  echo '{}' > ".session/sessions/${misplaced_id}/state.json"
  # Create an orphaned file directly under .session/sessions/
  echo "orphaned" > .session/sessions/orphaned.txt
  # Run cleanup
  ./.session/scripts/bash/session-cleanup.sh --json > /tmp/cleanup_out.json
  vlog "cleanup output: $(cat /tmp/cleanup_out.json)"
  # Errant root file should be gone
  [[ ! -f .session/errant-file.txt ]] || fail "errant-file.txt should have been removed"
  # Empty legacy dir should be gone
  [[ ! -d .session/daily-summaries ]] || fail "daily-summaries/ should have been removed"
  # Orphaned file should be gone
  [[ ! -f .session/sessions/orphaned.txt ]] || fail "orphaned.txt should have been removed"
  # Misplaced session dir should be at correct path
  [[ -d ".session/sessions/2026-01/${misplaced_id}" ]] || fail "misplaced session dir not moved to sessions/2026-01/"
  [[ ! -d ".session/sessions/${misplaced_id}" ]] || fail "misplaced session dir should be gone from sessions/ root"
  # validation-results.json is allowlisted — should NOT have been removed
  echo '{"overall":"pass"}' > .session/validation-results.json
  ./.session/scripts/bash/session-cleanup.sh --json >/dev/null
  [[ -f .session/validation-results.json ]] || fail "validation-results.json (allowlisted) should NOT have been removed"
  rm -f .session/validation-results.json
  # JSON output should be status:ok
  local cleanup_status
  cleanup_status=$(jq -r '.status' /tmp/cleanup_out.json)
  assert_eq "ok" "$cleanup_status" "cleanup status should be ok"

  log "All tests passed (start, preflight, wrap, cleanup)."

  # === Scope/Spec Transition Tests (Issue #38) ===

  # 14) scope → spec → plan transition (development workflow)
  log "14) scope → spec → plan transition (development)"
  local start_dev_json s_dev_id s_dev_ym s_dev_dir
  start_dev_json=$(./.session/scripts/bash/session-start.sh --json "Dev scope-spec test")
  s_dev_id=$(echo "$start_dev_json" | jq -r '.session.id')
  s_dev_ym=$(echo "$s_dev_id" | cut -d'-' -f1,2)
  s_dev_dir=".session/sessions/${s_dev_ym}/${s_dev_id}"
  assert_eq "development" "$(jq -r '.workflow' "$s_dev_dir/session-info.json")" "workflow should be development"

  # Preflight scope should succeed (none → scope)
  local preflight_scope_json
  preflight_scope_json=$(./.session/scripts/bash/session-preflight.sh --step scope --json)
  assert_eq "ok" "$(echo "$preflight_scope_json" | jq -r '.status')" "preflight scope status"
  # Complete scope, then spec should be allowed (scope → spec)
  set_workflow_step "$s_dev_id" "scope" "completed" >/dev/null
  local preflight_spec_json
  preflight_spec_json=$(./.session/scripts/bash/session-preflight.sh --step spec --json)
  assert_eq "ok" "$(echo "$preflight_spec_json" | jq -r '.status')" "preflight spec status"
  # Complete spec, then plan should be allowed (spec → plan)
  set_workflow_step "$s_dev_id" "spec" "completed" >/dev/null
  local preflight_plan14_json
  preflight_plan14_json=$(./.session/scripts/bash/session-preflight.sh --step plan --json)
  assert_eq "ok" "$(echo "$preflight_plan14_json" | jq -r '.status')" "preflight plan after spec status"
  # Wrap
  set_workflow_step "$s_dev_id" "plan" "completed" >/dev/null
  set_workflow_step "$s_dev_id" "execute" "completed" >/dev/null
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null

  # 15) scope → plan transition (spike, skipping spec)
  log "15) scope → plan transition (spike, skipping spec)"
  local start_spike_json s_spike_id s_spike_ym s_spike_dir
  start_spike_json=$(./.session/scripts/bash/session-start.sh --json --spike "Spike scope test")
  s_spike_id=$(echo "$start_spike_json" | jq -r '.session.id')
  s_spike_ym=$(echo "$s_spike_id" | cut -d'-' -f1,2)
  s_spike_dir=".session/sessions/${s_spike_ym}/${s_spike_id}"
  assert_eq "spike" "$(jq -r '.workflow' "$s_spike_dir/session-info.json")" "workflow should be spike"

  # Preflight scope
  local preflight_spike_scope_json
  preflight_spike_scope_json=$(./.session/scripts/bash/session-preflight.sh --step scope --json)
  assert_eq "ok" "$(echo "$preflight_spike_scope_json" | jq -r '.status')" "preflight scope (spike) status"
  # Complete scope, then plan should be allowed (scope → plan, skipping spec)
  set_workflow_step "$s_spike_id" "scope" "completed" >/dev/null
  local preflight_spike_plan_json
  preflight_spike_plan_json=$(./.session/scripts/bash/session-preflight.sh --step plan --json)
  assert_eq "ok" "$(echo "$preflight_spike_plan_json" | jq -r '.status')" "preflight plan after scope (spike) status"
  # Wrap
  set_workflow_step "$s_spike_id" "plan" "completed" >/dev/null
  set_workflow_step "$s_spike_id" "execute" "completed" >/dev/null
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null

  # 16) start → plan backward compatibility with deprecation warning
  log "16) start → plan backward compatibility (deprecation warning)"
  local start_bc_json s_bc_id s_bc_ym
  start_bc_json=$(./.session/scripts/bash/session-start.sh --json "Backward compat test")
  s_bc_id=$(echo "$start_bc_json" | jq -r '.session.id')
  s_bc_ym=$(echo "$s_bc_id" | cut -d'-' -f1,2)
  assert_eq "development" "$(jq -r '.workflow' ".session/sessions/${s_bc_ym}/${s_bc_id}/session-info.json")" "workflow should be development"

  # Preflight plan directly (skipping scope/spec) — should succeed with deprecation warning
  # Capture stderr separately to check for deprecation warning
  local preflight_bc_json preflight_bc_stderr
  preflight_bc_stderr=$(./.session/scripts/bash/session-preflight.sh --step plan --json 2>&1 1>/tmp/preflight_bc.json)
  preflight_bc_json=$(cat /tmp/preflight_bc.json)
  vlog "preflight_bc_json: $preflight_bc_json"
  vlog "preflight_bc_stderr: $preflight_bc_stderr"
  # Transition should succeed (status ok)
  assert_eq "ok" "$(echo "$preflight_bc_json" | jq -r '.status')" "start→plan backward compat should succeed"
  # JSON should contain deprecation_warning field
  local json_warning
  json_warning=$(echo "$preflight_bc_json" | jq -r '.deprecation_warning // ""')
  [[ -n "$json_warning" ]] || fail "expected deprecation_warning in JSON output"
  echo "$json_warning" | grep -q "scope/spec" || fail "deprecation_warning should mention scope/spec"
  # Stderr should also contain the deprecation warning
  echo "$preflight_bc_stderr" | grep -q "scope/spec" || fail "expected deprecation warning on stderr"
  # Wrap
  set_workflow_step "$s_bc_id" "plan" "completed" >/dev/null
  set_workflow_step "$s_bc_id" "execute" "completed" >/dev/null
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null

  log "All scope/spec transition tests passed."

  # === Spec Verification Tests (Issue #39) ===

  # 17) spec verification with spec.md present (production stage)
  log "17) spec verification passes with all items checked (production)"
  local start_sv_json sv_id sv_ym sv_dir
  start_sv_json=$(./.session/scripts/bash/session-start.sh --json "Spec verification test")
  sv_id=$(echo "$start_sv_json" | jq -r '.session.id')
  sv_ym=$(echo "$sv_id" | cut -d'-' -f1,2)
  sv_dir=".session/sessions/${sv_ym}/${sv_id}"
  # Create a spec.md with verification checklist — all items checked
  cat > "$sv_dir/spec.md" << 'SPECMD'
# Spec: Test Feature

## User Stories and Acceptance Criteria

### US-1: Basic Feature
**Acceptance Criteria:**
- AC-1.1: Given a user, when they act, then result happens

## Verification Checklist
- [x] All acceptance criteria have at least one happy-path test
- [x] Edge cases identified for each user story
- [x] Error scenarios documented
SPECMD
  # Run validate with --skip-lint --skip-tests to isolate spec check
  local validate_json
  validate_json=$(./.session/scripts/bash/session-validate.sh --json --skip-lint --skip-tests)
  vlog "validate_json (spec pass): $validate_json"
  # Spec verification should pass
  local spec_status spec_verified spec_total
  spec_status=$(echo "$validate_json" | jq -r '.validation_checks[] | select(.check == "spec_verification") | .status')
  spec_verified=$(echo "$validate_json" | jq -r '.validation_checks[] | select(.check == "spec_verification") | .verified')
  spec_total=$(echo "$validate_json" | jq -r '.validation_checks[] | select(.check == "spec_verification") | .total')
  assert_eq "pass" "$spec_status" "spec verification should pass when all items checked"
  assert_eq "3" "$spec_verified" "spec verified count should be 3"
  assert_eq "3" "$spec_total" "spec total count should be 3"

  # 18) spec verification with unmet items (production = fail)
  log "18) spec verification fails with unmet items (production)"
  cat > "$sv_dir/spec.md" << 'SPECMD'
# Spec: Test Feature

## Verification Checklist
- [x] First item verified
- [ ] Second item NOT verified
- [x] Third item verified
SPECMD
  set +e
  validate_json=$(./.session/scripts/bash/session-validate.sh --json --skip-lint --skip-tests)
  local sv_exit=$?
  set -e
  vlog "validate_json (spec fail): $validate_json"
  spec_status=$(echo "$validate_json" | jq -r '.validation_checks[] | select(.check == "spec_verification") | .status')
  assert_eq "fail" "$spec_status" "spec verification should fail in production with unmet items"
  assert_eq "1" "$sv_exit" "validate should exit 1 when spec verification fails in production"

  # 19) spec verification skipped when no spec.md
  log "19) spec verification skipped when no spec.md"
  rm -f "$sv_dir/spec.md"
  validate_json=$(./.session/scripts/bash/session-validate.sh --json --skip-lint --skip-tests)
  vlog "validate_json (no spec): $validate_json"
  spec_status=$(echo "$validate_json" | jq -r '.validation_checks[] | select(.check == "spec_verification") | .status')
  assert_eq "skipped" "$spec_status" "spec verification should be skipped when no spec.md"

  # 20) spec verification skipped at poc stage
  log "20) spec verification skipped at poc stage"
  # Patch session-info.json to poc stage
  local info_file="${sv_dir}/session-info.json"
  local tmp_info
  tmp_info=$(mktemp)
  jq '.stage = "poc"' "$info_file" > "$tmp_info" && mv "$tmp_info" "$info_file"
  # Create spec.md with unchecked items — should still be skipped
  cat > "$sv_dir/spec.md" << 'SPECMD'
# Spec: Test Feature

## Verification Checklist
- [ ] Unchecked item
SPECMD
  validate_json=$(./.session/scripts/bash/session-validate.sh --json --skip-lint --skip-tests)
  vlog "validate_json (poc): $validate_json"
  spec_status=$(echo "$validate_json" | jq -r '.validation_checks[] | select(.check == "spec_verification") | .status')
  assert_eq "skipped" "$spec_status" "spec verification should be skipped at poc stage"

  # 21) spec verification warns at mvp stage with unmet items
  log "21) spec verification warns at mvp stage (unmet items)"
  tmp_info=$(mktemp)
  jq '.stage = "mvp"' "$info_file" > "$tmp_info" && mv "$tmp_info" "$info_file"
  validate_json=$(./.session/scripts/bash/session-validate.sh --json --skip-lint --skip-tests)
  vlog "validate_json (mvp): $validate_json"
  spec_status=$(echo "$validate_json" | jq -r '.validation_checks[] | select(.check == "spec_verification") | .status')
  assert_eq "warning" "$spec_status" "spec verification should warn at mvp stage with unmet items"
  # Overall status should still be success (warning doesn't block)
  local overall_status
  overall_status=$(echo "$validate_json" | jq -r '.status')
  assert_eq "success" "$overall_status" "overall status should be success at mvp with spec warnings"

  # 22) --skip-spec flag skips spec verification
  log "22) --skip-spec skips spec verification"
  tmp_info=$(mktemp)
  jq '.stage = "production"' "$info_file" > "$tmp_info" && mv "$tmp_info" "$info_file"
  validate_json=$(./.session/scripts/bash/session-validate.sh --json --skip-lint --skip-tests --skip-spec)
  vlog "validate_json (skip-spec): $validate_json"
  spec_status=$(echo "$validate_json" | jq -r '.validation_checks[] | select(.check == "spec_verification") | .status')
  assert_eq "skipped" "$spec_status" "spec verification should be skipped with --skip-spec"

  # 22b) task helpers exclude [SKIP] items from completion counts
  log "22b) task helpers exclude [SKIP] items from completion counts"
  local skip_tasks_file skip_task_metrics skip_incomplete
  skip_tasks_file=$(mktemp)
  cat > "$skip_tasks_file" <<'EOF'
# Session Tasks: skip-metrics

## Tasks
- [x] T001 Completed task
- [ ] T002 Remaining task
- [ ] T003 [SKIP] Obsolete after refactor
EOF
  skip_task_metrics=$(get_task_completion "$skip_tasks_file")
  assert_eq "2" "$(echo "$skip_task_metrics" | jq -r '.total')" "effective task total should exclude [SKIP] items"
  assert_eq "1" "$(echo "$skip_task_metrics" | jq -r '.completed')" "completed count should include only non-[SKIP] items"
  assert_eq "1" "$(echo "$skip_task_metrics" | jq -r '.incomplete')" "incomplete count should exclude [SKIP] items"
  assert_eq "1" "$(echo "$skip_task_metrics" | jq -r '.skipped')" "skipped count should be tracked separately"
  assert_eq "2:1" "$(count_tasks "$skip_tasks_file")" "count_tasks should exclude [SKIP] items from its denominator"
  skip_incomplete=$(get_incomplete_tasks "$skip_tasks_file")
  grep -q "T002" <<< "$skip_incomplete" \
    || fail "get_incomplete_tasks should include real incomplete tasks"
  ! grep -q "T003" <<< "$skip_incomplete" \
    || fail "get_incomplete_tasks should exclude [SKIP] items"
  rm -f "$skip_tasks_file"

  # Wrap spec verification test session
  set_workflow_step "$sv_id" "execute" "completed" >/dev/null
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null

  log "All spec verification tests passed."

  # === Step History Tests (Issue #49) ===

  # 23) step_history initialized with start entry on session creation
  log "23) step_history initialized with start entry"
  local start_sh_json sh_id sh_ym sh_dir
  start_sh_json=$(./.session/scripts/bash/session-start.sh --json "Step history test")
  sh_id=$(echo "$start_sh_json" | jq -r '.session.id')
  sh_ym=$(echo "$sh_id" | cut -d'-' -f1,2)
  sh_dir=".session/sessions/${sh_ym}/${sh_id}"
  assert_eq "1" "$(jq '.step_history | length' "$sh_dir/state.json")" "step_history should have 1 entry (start)"
  assert_eq "start" "$(jq -r '.step_history[0].step' "$sh_dir/state.json")" "first entry should be start"
  assert_eq "completed" "$(jq -r '.step_history[0].status' "$sh_dir/state.json")" "start should be completed"
  assert_eq "start" "$(jq -r '.current_step' "$sh_dir/state.json")" "current_step should be start"
  assert_eq "completed" "$(jq -r '.step_status' "$sh_dir/state.json")" "step_status should be completed"
  assert_eq "1.2" "$(jq -r '.schema_version' "$sh_dir/state.json")" "state schema should be 1.2"
  assert_eq "false" "$(jq -r '.pause.active' "$sh_dir/state.json")" "pause should default to inactive"

  # 24) preflight appends in_progress entry to step_history
  log "24) preflight appends in_progress entry to step_history"
  local preflight_sh_json
  preflight_sh_json=$(./.session/scripts/bash/session-preflight.sh --step scope --json)
  assert_eq "ok" "$(echo "$preflight_sh_json" | jq -r '.status')" "preflight scope status"
  assert_eq "2" "$(jq '.step_history | length' "$sh_dir/state.json")" "step_history should have 2 entries (start + scope)"
  assert_eq "scope" "$(jq -r '.step_history[1].step' "$sh_dir/state.json")" "second entry step should be scope"
  assert_eq "in_progress" "$(jq -r '.step_history[1].status' "$sh_dir/state.json")" "second entry status should be in_progress"
  assert_eq "null" "$(jq -r '.step_history[1].ended_at' "$sh_dir/state.json")" "second entry ended_at should be null"
  assert_eq "false" "$(jq -r '.step_history[1].forced' "$sh_dir/state.json")" "second entry forced should be false"

  # 25) completing a step updates the last history entry
  log "25) completing step updates history entry"
  set_workflow_step "$sh_id" "scope" "completed" >/dev/null
  assert_eq "2" "$(jq '.step_history | length' "$sh_dir/state.json")" "step_history should still have 2 entries"
  assert_eq "completed" "$(jq -r '.step_history[1].status' "$sh_dir/state.json")" "entry status should be completed"
  [[ "$(jq -r '.step_history[1].ended_at' "$sh_dir/state.json")" != "null" ]] || fail "ended_at should be set after completion"
  [[ "$(jq -r '.step_history[1].started_at' "$sh_dir/state.json")" != "null" ]] || fail "started_at should be preserved"

  # 26) full workflow builds complete step_history
  log "26) full workflow builds multi-entry step_history"
  set_workflow_step "$sh_id" "spec" "in_progress" >/dev/null
  set_workflow_step "$sh_id" "spec" "completed" >/dev/null
  set_workflow_step "$sh_id" "plan" "in_progress" >/dev/null
  set_workflow_step "$sh_id" "plan" "completed" >/dev/null
  set_workflow_step "$sh_id" "execute" "in_progress" >/dev/null
  set_workflow_step "$sh_id" "execute" "completed" >/dev/null
  assert_eq "5" "$(jq '.step_history | length' "$sh_dir/state.json")" "step_history should have 5 entries (start + 4 steps)"
  assert_eq "start" "$(jq -r '.step_history[0].step' "$sh_dir/state.json")" "entry 0 should be start"
  assert_eq "scope" "$(jq -r '.step_history[1].step' "$sh_dir/state.json")" "entry 1 should be scope"
  assert_eq "spec" "$(jq -r '.step_history[2].step' "$sh_dir/state.json")" "entry 2 should be spec"
  assert_eq "plan" "$(jq -r '.step_history[3].step' "$sh_dir/state.json")" "entry 3 should be plan"
  assert_eq "execute" "$(jq -r '.step_history[4].step' "$sh_dir/state.json")" "entry 4 should be execute"
  # All entries should be completed with ended_at set
  local all_completed
  all_completed=$(jq '[.step_history[] | select(.status == "completed" and .ended_at != null)] | length' "$sh_dir/state.json")
  assert_eq "5" "$all_completed" "all 5 entries should be completed with ended_at"

  # 27) forced flag is recorded in step_history
  log "27) forced flag recorded in step_history"
  set_workflow_step "$sh_id" "validate" "in_progress" "true" >/dev/null
  assert_eq "6" "$(jq '.step_history | length' "$sh_dir/state.json")" "step_history should have 6 entries"
  assert_eq "true" "$(jq -r '.step_history[5].forced' "$sh_dir/state.json")" "forced entry should have forced=true"
  set_workflow_step "$sh_id" "validate" "completed" >/dev/null

  # Wrap
  set_workflow_step "$sh_id" "execute" "completed" >/dev/null
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null

  # 28) step_history survives wrap (preserved in final state)
  log "28) step_history preserved after wrap"
  local post_wrap_count
  post_wrap_count=$(jq '.step_history | length' "$sh_dir/state.json")
  [[ "$post_wrap_count" -ge 5 ]] || fail "step_history should be preserved after wrap (got $post_wrap_count entries)"
  assert_eq "completed" "$(jq -r '.status' "$sh_dir/state.json")" "session should be completed"

  # 29) wrap step should be marked completed (not stuck in_progress)
  log "29) wrap step marked completed in state.json"
  assert_eq "completed" "$(jq -r '.step_status' "$sh_dir/state.json")" "wrap step_status should be completed"
  assert_eq "wrap" "$(jq -r '.current_step' "$sh_dir/state.json")" "current_step should be wrap"
  local wrap_history_status
  wrap_history_status=$(jq -r '[.step_history[] | select(.step == "wrap")] | last | .status' "$sh_dir/state.json")
  assert_eq "completed" "$wrap_history_status" "wrap step_history entry should be completed"

  log "All step history tests passed."

  # === Postflight Tests ===

  # 30) postflight marks step as completed
  log "30) postflight marks step completed"
  local start_pf_json pf_id pf_ym pf_dir
  start_pf_json=$(./.session/scripts/bash/session-start.sh --json "Postflight test")
  pf_id=$(echo "$start_pf_json" | jq -r '.session.id')
  pf_ym=$(echo "$pf_id" | cut -d'-' -f1,2)
  pf_dir=".session/sessions/${pf_ym}/${pf_id}"

  # Run preflight to mark scope as in_progress
  ./.session/scripts/bash/session-preflight.sh --step scope --json >/dev/null
  assert_eq "scope" "$(jq -r '.current_step' "$pf_dir/state.json")" "current step should be scope"
  assert_eq "in_progress" "$(jq -r '.step_status' "$pf_dir/state.json")" "step should be in_progress"

  # Run postflight to mark scope as completed
  local postflight_json
  postflight_json=$(./.session/scripts/bash/session-postflight.sh --step scope --json)
  vlog "postflight_json: $postflight_json"
  assert_eq "ok" "$(echo "$postflight_json" | jq -r '.status')" "postflight status"
  assert_eq "scope" "$(echo "$postflight_json" | jq -r '.step')" "postflight step"
  assert_eq "completed" "$(echo "$postflight_json" | jq -r '.result')" "postflight result"
  assert_eq "completed" "$(jq -r '.step_status' "$pf_dir/state.json")" "step should be completed in state.json"
  [[ "$(jq -r '.step_history[0].ended_at' "$pf_dir/state.json")" != "null" ]] || fail "ended_at should be set"

  # 30) postflight outputs valid next steps
  log "31) postflight outputs valid next steps"
  local next_steps
  next_steps=$(echo "$postflight_json" | jq -r '.valid_next_steps[]' | sort | tr '\n' ' ' | sed 's/ $//')
  assert_eq "plan spec" "$next_steps" "scope's valid next steps should be spec and plan"

  # 31) postflight rejects mismatched step
  log "32) postflight rejects mismatched step"
  ./.session/scripts/bash/session-preflight.sh --step spec --json >/dev/null
  set +e
  local postflight_mismatch
  postflight_mismatch=$(./.session/scripts/bash/session-postflight.sh --step scope --json)
  local pf_exit=$?
  set -e
  assert_eq "1" "$pf_exit" "postflight should fail on step mismatch"
  assert_eq "error" "$(echo "$postflight_mismatch" | jq -r '.status')" "should be error on mismatch"

  # 32) postflight rejects already-completed step
  log "33) postflight rejects already-completed step"
  ./.session/scripts/bash/session-postflight.sh --step spec --json >/dev/null
  set +e
  local postflight_double
  postflight_double=$(./.session/scripts/bash/session-postflight.sh --step spec --json)
  local pf_double_exit=$?
  set -e
  assert_eq "1" "$pf_double_exit" "postflight should fail on already-completed step"
  assert_eq "error" "$(echo "$postflight_double" | jq -r '.status')" "should be error on double-complete"

  # 33) postflight with --status failed
  log "34) postflight marks step as failed"
  ./.session/scripts/bash/session-preflight.sh --step plan --json >/dev/null
  local postflight_fail_json
  postflight_fail_json=$(./.session/scripts/bash/session-postflight.sh --step plan --status failed --json)
  assert_eq "ok" "$(echo "$postflight_fail_json" | jq -r '.status')" "postflight status should be ok"
  assert_eq "failed" "$(echo "$postflight_fail_json" | jq -r '.result')" "postflight result should be failed"
  assert_eq "failed" "$(jq -r '.step_status' "$pf_dir/state.json")" "step should be failed in state.json"

  # 34) preflight + postflight full chain integration
  log "35) preflight + postflight full chain integration"

  # Clean up previous test session (test 33 left plan in failed state)
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null 2>&1 || true

  local start_chain_json chain_id chain_ym chain_dir
  start_chain_json=$(./.session/scripts/bash/session-start.sh --json "Chain integration test")
  chain_id=$(echo "$start_chain_json" | jq -r '.session.id')
  chain_ym=$(echo "$chain_id" | cut -d'-' -f1,2)
  chain_dir=".session/sessions/${chain_ym}/${chain_id}"

  # Run full chain: scope → spec → plan → execute → validate → publish → review using preflight+postflight
  for step in scope spec plan execute validate publish review; do
    ./.session/scripts/bash/session-preflight.sh --step "$step" --json >/dev/null
    ./.session/scripts/bash/session-postflight.sh --step "$step" --json >/dev/null
  done

  # Verify all 8 steps are in step_history (start + 7 chain steps) with completed status
  assert_eq "8" "$(jq '.step_history | length' "$chain_dir/state.json")" "chain should have 8 entries (start + 7 steps)"
  local chain_all_completed
  chain_all_completed=$(jq '[.step_history[] | select(.status == "completed" and .ended_at != null)] | length' "$chain_dir/state.json")
  assert_eq "8" "$chain_all_completed" "all 8 chain entries should be completed"
  assert_eq "review" "$(jq -r '.current_step' "$chain_dir/state.json")" "current step should be review"
  assert_eq "completed" "$(jq -r '.step_status' "$chain_dir/state.json")" "step status should be completed"

  # Wrap chain test session
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null

  # 36) publish → review transition
  log "36) publish → review transition"

  ./.session/scripts/bash/session-wrap.sh --json >/dev/null 2>&1 || true
  local start_rev_json rev_id rev_ym rev_dir
  start_rev_json=$(./.session/scripts/bash/session-start.sh --json "Review transition test")
  rev_id=$(echo "$start_rev_json" | jq -r '.session.id')
  rev_ym=$(echo "$rev_id" | cut -d'-' -f1,2)
  rev_dir=".session/sessions/${rev_ym}/${rev_id}"

  # Advance to publish completed
  for step in scope spec plan execute validate publish; do
    ./.session/scripts/bash/session-preflight.sh --step "$step" --json >/dev/null
    ./.session/scripts/bash/session-postflight.sh --step "$step" --json >/dev/null
  done
  assert_eq "publish" "$(jq -r '.current_step' "$rev_dir/state.json")" "current step should be publish"

  # Transition to review should succeed
  ./.session/scripts/bash/session-preflight.sh --step review --json >/dev/null
  assert_eq "review" "$(jq -r '.current_step' "$rev_dir/state.json")" "current step should be review"
  assert_eq "in_progress" "$(jq -r '.step_status' "$rev_dir/state.json")" "review should be in_progress"

  # Complete review
  local review_postflight_json
  review_postflight_json=$(./.session/scripts/bash/session-postflight.sh --step review --json)
  assert_eq "ok" "$(echo "$review_postflight_json" | jq -r '.status')" "review postflight should succeed"
  local review_next_steps
  review_next_steps=$(echo "$review_postflight_json" | jq -r '.valid_next_steps[]')
  assert_eq "finalize" "$review_next_steps" "review's valid next step should be finalize"

  # 37) publish → finalize transition (skip review, backward compatibility)
  log "37) publish → finalize transition (skip review)"

  # Rewind to publish completed state (we need to start fresh)
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null 2>&1 || true
  local start_skip_json skip_id skip_ym skip_dir
  start_skip_json=$(./.session/scripts/bash/session-start.sh --json "Skip review test")
  skip_id=$(echo "$start_skip_json" | jq -r '.session.id')
  skip_ym=$(echo "$skip_id" | cut -d'-' -f1,2)
  skip_dir=".session/sessions/${skip_ym}/${skip_id}"

  for step in scope spec plan execute validate publish; do
    ./.session/scripts/bash/session-preflight.sh --step "$step" --json >/dev/null
    ./.session/scripts/bash/session-postflight.sh --step "$step" --json >/dev/null
  done

  # Transition directly to finalize (skipping review) should succeed
  ./.session/scripts/bash/session-preflight.sh --step finalize --json >/dev/null
  assert_eq "finalize" "$(jq -r '.current_step' "$skip_dir/state.json")" "should be able to skip review and go to finalize"
  ./.session/scripts/bash/session-postflight.sh --step finalize --json >/dev/null

  ./.session/scripts/bash/session-wrap.sh --json >/dev/null

  log "All postflight tests passed."

  # === session-start orchestration flag compatibility tests ===

  # 38) session-start accepts --auto without error
  log "38) session-start accepts --auto"
  local start_auto_json auto_session_id
  start_auto_json=$(./.session/scripts/bash/session-start.sh --json --auto "Auto compatibility test")
  assert_eq "ok" "$(echo "$start_auto_json" | jq -r '.status')" "session-start should accept --auto"
  assert_eq "true" "$(echo "$start_auto_json" | jq -r '.orchestration.auto')" "orchestration.auto should be true"
  assert_eq "false" "$(echo "$start_auto_json" | jq -r '.orchestration.copilot_review')" "copilot_review should default to false"
  auto_session_id=$(echo "$start_auto_json" | jq -r '.session.id')
  set_workflow_step "$auto_session_id" "execute" "completed" >/dev/null
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null

  # 39) session-start accepts --auto --copilot-review without error
  log "39) session-start accepts --auto --copilot-review"
  local start_auto_review_json auto_review_session_id
  start_auto_review_json=$(./.session/scripts/bash/session-start.sh --json --auto --copilot-review "Auto review compatibility test")
  assert_eq "ok" "$(echo "$start_auto_review_json" | jq -r '.status')" "session-start should accept --auto --copilot-review"
  assert_eq "true" "$(echo "$start_auto_review_json" | jq -r '.orchestration.auto')" "orchestration.auto should be true with review"
  assert_eq "true" "$(echo "$start_auto_review_json" | jq -r '.orchestration.copilot_review')" "copilot_review should be true"
  auto_review_session_id=$(echo "$start_auto_review_json" | jq -r '.session.id')
  set_workflow_step "$auto_review_session_id" "execute" "completed" >/dev/null
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null

  # 40) maintenance help text documents lightweight default
  log "40) maintenance help text documents lightweight default"
  local help_output
  help_output=$(./.session/scripts/bash/session-start.sh --help)
  grep -q "maintenance" <<< "$help_output" \
    || fail "session-start help should mention the maintenance workflow"
  grep -q "Lightweight chain" <<< "$help_output" \
    || fail "session-start help should describe maintenance as a lightweight chain"
  grep -q "start → execute → STOP by default" <<< "$help_output" \
    || fail "session-start help should describe maintenance as stop-after-execute by default"
  grep -q -- "--auto adds wrap" <<< "$help_output" \
    || fail "session-start help should document that --auto adds wrap for maintenance"

  # 41) maintenance docs/agent contract reflect stop-after-execute default
  log "41) maintenance docs and agent contract reflect lightweight default"
  grep -q "Maintenance Workflow: execute → STOP" "$ROOT_DIR/github/agents/session.start.agent.md" \
    || fail "session.start agent should document maintenance execute → STOP default"
  grep -q "agent_type: \"session.execute\"" "$ROOT_DIR/github/agents/session.start.agent.md" \
    || fail "session.start agent should include an explicit maintenance execute sub-agent block"
  grep -q "Maintenance Workflow: → STOP" "$ROOT_DIR/github/agents/session.execute.agent.md" \
    || fail "session.execute agent should document maintenance stop-after-execute direct mode"
  grep -q "Maintenance runs \`execute\` and then stops" "$ROOT_DIR/README.md" \
    || fail "README should describe maintenance stop-after-execute default"
  grep -q "# → execute → STOP (no branch, no PR)" "$ROOT_DIR/session/docs/reference.md" \
    || fail "reference docs should show maintenance execute → STOP example"
  grep -q "Maintenance (lightweight default)" "$ROOT_DIR/session/docs/shared-workflow.md" \
    || fail "shared workflow docs should describe the lightweight maintenance default"
  grep -q "start → execute → STOP" "$ROOT_DIR/session/docs/shared-workflow.md" \
    || fail "shared workflow docs should show lightweight maintenance default"
  grep -q "Maintenance workflow" "$ROOT_DIR/.github/copilot-instructions.md" \
    || fail "copilot instructions should mention the maintenance workflow"
  grep -q "start → execute → STOP" "$ROOT_DIR/.github/copilot-instructions.md" \
    || fail "copilot instructions should show maintenance stop-after-execute default"
  grep -q "Maintenance workflow is now lightweight by default" "$ROOT_DIR/CHANGELOG.md" \
    || fail "CHANGELOG should record the maintenance default change"
  ! grep -q "Maintenance workflow always auto-chains" "$ROOT_DIR/CHANGELOG.md" \
    || fail "CHANGELOG should not retain the old always-auto maintenance wording"

  log "All session-start orchestration flag tests passed."

  # 42) pause helpers record and clear human checkpoints
  log "42) pause helpers record and clear human checkpoints"
  local start_pause_json pause_id pause_ym pause_dir
  start_pause_json=$(./.session/scripts/bash/session-start.sh --json "Pause helper test")
  pause_id=$(echo "$start_pause_json" | jq -r '.session.id')
  pause_ym=$(echo "$pause_id" | cut -d'-' -f1,2)
  pause_dir=".session/sessions/${pause_ym}/${pause_id}"
  set_pause_state "$pause_id" "manual_test" "execute" "T042" "Manual browser checkpoint" "Verify the dialog appears in the browser" "invoke session.start --resume"
  assert_eq "true" "$(jq -r '.pause.active' "$pause_dir/state.json")" "pause should be active after set_pause_state"
  assert_eq "manual_test" "$(jq -r '.pause.kind' "$pause_dir/state.json")" "pause kind should be recorded"
  assert_eq "execute" "$(jq -r '.pause.step' "$pause_dir/state.json")" "pause step should be execute"
  assert_eq "T042" "$(jq -r '.pause.task_id' "$pause_dir/state.json")" "pause task_id should be recorded"
  clear_pause_state "$pause_id" "User confirmed manual checkpoint"
  assert_eq "false" "$(jq -r '.pause.active' "$pause_dir/state.json")" "pause should be inactive after clear_pause_state"
  assert_eq "User confirmed manual checkpoint" "$(jq -r '.pause.notes' "$pause_dir/state.json")" "pause clear notes should be recorded"
  set_workflow_step "$pause_id" "execute" "completed" >/dev/null
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null

  # 43) session-start --resume surfaces active pause checkpoints
  log "43) session-start --resume surfaces active pause checkpoints"
  local start_resume_json resume_id resume_ym resume_dir resume_json
  start_resume_json=$(./.session/scripts/bash/session-start.sh --json "Pause resume test")
  resume_id=$(echo "$start_resume_json" | jq -r '.session.id')
  resume_ym=$(echo "$resume_id" | cut -d'-' -f1,2)
  resume_dir=".session/sessions/${resume_ym}/${resume_id}"
  set_pause_state "$resume_id" "manual_test" "execute" "T043" "Resume checkpoint" "Confirm the manual browser test result" "invoke session.start --resume"
  resume_json=$(./.session/scripts/bash/session-start.sh --json --resume)
  assert_eq "true" "$(echo "$resume_json" | jq -r '.pause.active')" "resume JSON should surface active pause"
  assert_eq "manual_test" "$(echo "$resume_json" | jq -r '.pause.kind')" "resume JSON should include pause kind"
  assert_eq "T043" "$(echo "$resume_json" | jq -r '.pause.task_id')" "resume JSON should include pause task id"
  echo "$resume_json" | jq -e '.instructions[] | select(test("ACTIVE HUMAN CHECKPOINT"))' >/dev/null \
    || fail "resume instructions should mention the active human checkpoint"
  clear_pause_state "$resume_id" "Resume flow verified"
  set_workflow_step "$resume_id" "execute" "completed" >/dev/null
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null

  # 44) session-preflight JSON includes active pause state
  log "44) session-preflight JSON includes active pause state"
  local start_pf_pause_json pf_pause_id pf_pause_ym pf_pause_dir preflight_pause_json
  start_pf_pause_json=$(./.session/scripts/bash/session-start.sh --json --maintenance "Pause preflight test")
  pf_pause_id=$(echo "$start_pf_pause_json" | jq -r '.session.id')
  pf_pause_ym=$(echo "$pf_pause_id" | cut -d'-' -f1,2)
  pf_pause_dir=".session/sessions/${pf_pause_ym}/${pf_pause_id}"
  set_pause_state "$pf_pause_id" "manual_test" "execute" "T044" "Preflight checkpoint" "Review the generated audit report" "invoke session.start --resume"
  preflight_pause_json=$(./.session/scripts/bash/session-preflight.sh --step execute --json)
  assert_eq "true" "$(echo "$preflight_pause_json" | jq -r '.pause.active')" "preflight JSON should surface active pause"
  assert_eq "execute" "$(echo "$preflight_pause_json" | jq -r '.pause.step')" "preflight JSON should include pause step"
  assert_eq "T044" "$(echo "$preflight_pause_json" | jq -r '.pause.task_id')" "preflight JSON should include pause task id"
  clear_pause_state "$pf_pause_id" "Preflight pause JSON verified"
  ./.session/scripts/bash/session-postflight.sh --step execute --json >/dev/null
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null

  # 45) auto-mode docs and agent contracts reflect human checkpoints
  log "45) auto-mode docs and agent contracts reflect human checkpoints"
  grep -q "session.scope\` remains interactive" "$ROOT_DIR/github/agents/session.start.agent.md" \
    || fail "session.start agent should keep scope interactive"
  grep -q "Ask concise clarifying questions when needed" "$ROOT_DIR/github/agents/session.start.agent.md" \
    || fail "session.start agent should allow scope clarification prompts"
  grep -q "required human checkpoint" "$ROOT_DIR/github/agents/session.start.agent.md" \
    || fail "session.start agent should describe auto mode as stopping at human checkpoints"
  grep -q "running in \`--auto\` mode" "$ROOT_DIR/github/agents/session.scope.agent.md" \
    || fail "session.scope agent should explicitly allow dialogue in auto mode"
  grep -q "set_pause_state" "$ROOT_DIR/github/agents/session.execute.agent.md" \
    || fail "session.execute agent should document pause recording"
  grep -q "clear_pause_state" "$ROOT_DIR/github/agents/session.execute.agent.md" \
    || fail "session.execute agent should document pause clearing"
  grep -q "current version \`1.2\`" "$ROOT_DIR/session/docs/schema-versioning.md" \
    || fail "schema docs should show state version 1.2"
  grep -q "\`pause\` object" "$ROOT_DIR/session/docs/schema-versioning.md" \
    || fail "schema docs should document the pause object"
  grep -q "next human gate" "$ROOT_DIR/README.md" \
    || fail "README should describe auto mode in terms of human gates"
  grep -q "state.json.pause" "$ROOT_DIR/session/docs/reference.md" \
    || fail "reference docs should mention the pause checkpoint field"

  log "All pause-checkpoint and auto human-gate tests passed."

  # 46) session-start accepts --debug and records debug workflow
  log "46) session-start accepts --debug"
  local start_debug_json debug_session_id
  start_debug_json=$(./.session/scripts/bash/session-start.sh --json --debug "Trace flaky worker timeout")
  assert_eq "ok" "$(echo "$start_debug_json" | jq -r '.status')" "session-start should accept --debug"
  assert_eq "debug" "$(echo "$start_debug_json" | jq -r '.session.workflow')" "session workflow should be debug"
  assert_eq "false" "$(echo "$start_debug_json" | jq -r '.session.read_only')" "debug workflow should not imply read-only mode"
  debug_session_id=$(echo "$start_debug_json" | jq -r '.session.id')
  set_workflow_step "$debug_session_id" "execute" "completed" >/dev/null
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null

  # 47) debug help text documents lightweight default
  log "47) debug help text documents lightweight default"
  help_output=$(./.session/scripts/bash/session-start.sh --help)
  grep -q -- "--debug" <<< "$help_output" \
    || fail "session-start help should mention the --debug flag"
  grep -q "Debug workflow: troubleshooting/investigation" <<< "$help_output" \
    || fail "session-start help should describe the debug workflow"
  grep -q "debug (--debug)       - Investigation chain: start → execute → STOP by default; --auto adds wrap" <<< "$help_output" \
    || fail "session-start help should describe debug as stop-after-execute by default with optional auto wrap"

  # 48) debug docs and agent contracts reflect lightweight investigation workflow
  log "48) debug docs and agent contracts reflect lightweight investigation workflow"
  grep -q "Debug Workflow: execute → STOP" "$ROOT_DIR/github/agents/session.start.agent.md" \
    || fail "session.start agent should document debug execute → STOP default"
  grep -q "\`debug\`, \`troubleshoot\`, \`diagnose\`, \`trace\`, \`reproduce\`, \`investigate\`, \`why is\`" "$ROOT_DIR/github/agents/session.start.agent.md" \
    || fail "session.start agent should include debug smart-routing signals"
  grep -q "check_workflow_allowed \"\$SESSION_ID\" \"development\" \"spike\" \"maintenance\" \"debug\" \"operational\"" "$ROOT_DIR/github/agents/session.execute.agent.md" \
    || fail "session.execute agent should allow debug and operational workflows"
  grep -q "Debug Workflow: → STOP" "$ROOT_DIR/github/agents/session.execute.agent.md" \
    || fail "session.execute agent should document debug stop-after-execute direct mode"
  grep -q "invoke session.start --debug" "$ROOT_DIR/README.md" \
    || fail "README should include a debug workflow example"
  grep -q "### 4. Debug" "$ROOT_DIR/README.md" \
    || fail "README should describe the debug workflow type"
  grep -q "invoke session.start --debug" "$ROOT_DIR/session/docs/reference.md" \
    || fail "reference docs should include the debug workflow"
  grep -q "Debug (lightweight investigation)" "$ROOT_DIR/session/docs/shared-workflow.md" \
    || fail "shared workflow docs should describe the debug workflow"
  grep -Fq "\`development\` \| \`spike\` \| \`maintenance\` \| \`debug\` \| \`operational\`" "$ROOT_DIR/session/docs/schema-versioning.md" \
    || fail "schema docs should include debug and operational as workflow values"
  grep -q "Debug workflow" "$ROOT_DIR/.github/copilot-instructions.md" \
    || fail "copilot instructions should mention the debug workflow"
  grep -q "invoke session.start --debug" "$ROOT_DIR/stubs/copilot_instructions.md" \
    || fail "copilot instructions stub should include the debug workflow"
  grep -q "development/spike/maintenance/debug/operational" "$ROOT_DIR/session/docs/copilot-cli-mechanics.md" \
    || fail "Copilot CLI mechanics docs should mention the debug and operational workflows"
  grep -q "dedicated \`debug\` workflow" "$ROOT_DIR/CHANGELOG.md" \
    || fail "CHANGELOG should record the new debug workflow"

  log "All debug workflow tests passed."

  # 49) next.md handoff content is preferred over legacy notes section
  log "49) next.md handoff content is preferred over legacy notes section"
  local start_next_pref_json next_pref_id next_pref_ym next_pref_dir next_pref_continue_json next_pref_summary
  start_next_pref_json=$(./.session/scripts/bash/session-start.sh --json "Next artifact priority test")
  next_pref_id=$(echo "$start_next_pref_json" | jq -r '.session.id')
  next_pref_ym=$(echo "$next_pref_id" | cut -d'-' -f1,2)
  next_pref_dir=".session/sessions/${next_pref_ym}/${next_pref_id}"
  cat > "${next_pref_dir}/next.md" <<'EOF'
# Next Session: priority-test

## Completed
- Reproduced the problem locally

## Suggested Next Steps
- Follow the structured next artifact

## Suggested Workflow
- debug
EOF
  cat > "${next_pref_dir}/notes.md" <<'EOF'
# Session Notes: next-pref-test

## Summary

## Key Decisions

## Blockers/Issues

## For Next Session
- legacy notes fallback

## Technical Notes (optional)
EOF
  set_workflow_step "$next_pref_id" "execute" "completed" >/dev/null
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null
  next_pref_continue_json=$(./.session/scripts/bash/session-start.sh --json --continues-from "$next_pref_id" "Continue next artifact priority test")
  next_pref_summary=$(echo "$next_pref_continue_json" | jq -r '.previous_session.for_next_session')
  echo "$next_pref_summary" | grep -q "Follow the structured next artifact" \
    || fail "for_next_session should prefer next.md content when it exists"
  ! echo "$next_pref_summary" | grep -q "legacy notes fallback" \
    || fail "for_next_session should not prefer legacy notes when next.md has content"
  assert_eq "${next_pref_dir}/next.md" "$(echo "$next_pref_continue_json" | jq -r '.previous_session.next_file')" "previous_session.next_file should point to next.md"
  local next_pref_continue_id
  next_pref_continue_id=$(echo "$next_pref_continue_json" | jq -r '.session.id')
  set_workflow_step "$next_pref_continue_id" "execute" "completed" >/dev/null
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null

  # 50) next.md docs and install surfaces reflect first-class artifact support
  log "50) next.md docs and install surfaces reflect first-class artifact support"
  grep -q "next.md" "$ROOT_DIR/README.md" \
    || fail "README should mention next.md"
  grep -q "next-template.md" "$ROOT_DIR/install.sh" \
    || fail "install.sh should install the next.md template"
  grep -q "next-template.md" "$ROOT_DIR/update.sh" \
    || fail "update.sh should update the next.md template"
  grep -q "previous_session.next_file" "$ROOT_DIR/github/agents/session.start.agent.md" \
    || fail "session.start agent should mention previous_session.next_file"
  grep -q "primary follow-up artifact" "$ROOT_DIR/github/agents/session.wrap.agent.md" \
    || fail "session.wrap agent should treat next.md as the primary follow-up artifact"
  grep -q "structured handoff" "$ROOT_DIR/github/agents/session.scope.agent.md" \
    || fail "session.scope agent should accept next.md continuation context"
  grep -q "previous-session \`next.md\` path" "$ROOT_DIR/github/agents/session.plan.agent.md" \
    || fail "session.plan agent should accept next.md continuation context"
  grep -q "next.md" "$ROOT_DIR/session/docs/reference.md" \
    || fail "reference docs should mention next.md"
  grep -q "next.md" "$ROOT_DIR/.github/copilot-instructions.md" \
    || fail "copilot instructions should mention next.md"
  grep -q "next.md" "$ROOT_DIR/stubs/copilot_instructions.md" \
    || fail "copilot instructions stub should mention next.md"

  log "All next.md artifact tests passed."

  # 51) session-start --resume backfills next.md for older active sessions
  log "51) session-start --resume backfills missing next.md"
  local start_resume_next_json resume_next_id resume_next_ym resume_next_dir resume_next_json
  start_resume_next_json=$(./.session/scripts/bash/session-start.sh --json "Resume next backfill test")
  resume_next_id=$(echo "$start_resume_next_json" | jq -r '.session.id')
  resume_next_ym=$(echo "$resume_next_id" | cut -d'-' -f1,2)
  resume_next_dir=".session/sessions/${resume_next_ym}/${resume_next_id}"
  rm -f "${resume_next_dir}/next.md"
  resume_next_json=$(./.session/scripts/bash/session-start.sh --json --resume)
  assert_file_exists "${resume_next_dir}/next.md"
  assert_eq "${resume_next_dir}/next.md" "$(echo "$resume_next_json" | jq -r '.session.files.next')" "resume JSON should surface a valid next.md path"
  set_workflow_step "$resume_next_id" "execute" "completed" >/dev/null
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null

  # 52) stable updater wrapper writes manifest and prunes deprecated managed files safely
  log "52) stable updater wrapper writes manifest and prunes deprecated managed files safely"
  local obsolete_sha preserved_sha protected_sha
  chmod -x .session/scripts/bash/session-start.sh
  cat > .session/templates/obsolete-template.md <<'EOF'
obsolete managed template
EOF
  obsolete_sha=$(sha256_file ".session/templates/obsolete-template.md")
  cat > .session/templates/preserved-obsolete-template.md <<'EOF'
preserve this deprecated file
EOF
  preserved_sha=$(sha256_file ".session/templates/preserved-obsolete-template.md")
  echo "local modification" >> .session/templates/preserved-obsolete-template.md
  cat > do-not-delete.txt <<'EOF'
do not delete via manifest traversal
EOF
  protected_sha=$(sha256_file "do-not-delete.txt")
  mkdir -p .session/templates/obsolete-dir
  cat > .session/install-manifest.json <<EOF
{
  "schema_version": "1",
  "generated_at": "2026-03-21T00:00:00Z",
  "tool": "update",
  "tool_version": "test",
  "managed_files": [
    {
      "path": ".session/templates/obsolete-template.md",
      "source": "session/templates/obsolete-template.md",
      "sha256": "${obsolete_sha}"
    },
    {
      "path": ".session/templates/preserved-obsolete-template.md",
      "source": "session/templates/preserved-obsolete-template.md",
      "sha256": "${preserved_sha}"
    },
    {
      "path": ".session/templates/../../do-not-delete.txt",
      "source": "session/templates/../../do-not-delete.txt",
      "sha256": "${protected_sha}"
    },
    {
      "path": ".session/templates/obsolete-dir",
      "source": "session/templates/obsolete-dir",
      "sha256": "directory-placeholder"
    }
  ],
  "managed_sections": []
}
EOF
  cat > .gitignore <<'EOF'
# Session workflow
.session/sessions/
.session/ACTIVE_SESSION
.session/validation-results.json
EOF
  mkdir -p ".session/sessions/2026-03/2026-03-01-1"
  cat > ".session/sessions/2026-03/2026-03-01-1/notes.md" <<'EOF'
tracked session artifact
EOF
  echo "active" > .session/ACTIVE_SESSION
  echo '{"overall":"pass"}' > .session/validation-results.json
  SESSION_WORKFLOW_SOURCE_DIR="$ROOT_DIR" bash ./.session/update.sh >/dev/null
  [[ -x ".session/scripts/bash/session-start.sh" ]] \
    || fail "updater should restore executable bits for managed scripts"
  [[ ! -e ".session/templates/obsolete-template.md" ]] \
    || fail "updater should remove deprecated managed files when the checksum still matches"
  assert_file_exists ".session/templates/preserved-obsolete-template.md"
  assert_file_exists "do-not-delete.txt"
  assert_dir_exists ".session/templates/obsolete-dir"
  assert_file_exists ".session/install-manifest.json"
  assert_eq "true" "$(jq -r 'any(.managed_files[]?; .path == ".session/update.sh")' .session/install-manifest.json)" "manifest should track the stable updater wrapper"
  assert_eq "false" "$(jq -r 'any(.managed_files[]?; .path == ".session/templates/obsolete-template.md")' .session/install-manifest.json)" "new manifest should not retain pruned deprecated files"
  assert_eq "false" "$(jq -r 'any(.managed_files[]?; .path == ".session/templates/preserved-obsolete-template.md")' .session/install-manifest.json)" "new manifest should omit deprecated files that were left in place"
  assert_eq "false" "$(jq -r 'any(.managed_files[]?; .path == ".session/templates/../../do-not-delete.txt")' .session/install-manifest.json)" "new manifest should omit unsafe deprecated paths"
  assert_eq "false" "$(jq -r 'any(.managed_files[]?; .path == ".session/templates/obsolete-dir")' .session/install-manifest.json)" "new manifest should omit deprecated directory entries"
  ! grep -qxF ".session/sessions/" .gitignore \
    || fail "updater should remove the legacy .session/sessions/ ignore rule"
  grep -qxF ".session/ACTIVE_SESSION" .gitignore \
    || fail "updater should keep ACTIVE_SESSION ignored"
  grep -qxF ".session/validation-results.json" .gitignore \
    || fail "updater should keep validation-results.json ignored"
  grep -qxF ".session/sessions/**/state.json" .gitignore \
    || fail "updater should ignore volatile state.json bookkeeping"
  git check-ignore -q ".session/sessions/2026-03/2026-03-01-1/notes.md" \
    && fail "session artifacts should not be gitignored after updater migration"
  git check-ignore -q ".session/sessions/2026-03/2026-03-01-1/state.json" \
    || fail "state.json should be gitignored after updater migration"
  git check-ignore -q ".session/ACTIVE_SESSION" \
    || fail "ACTIVE_SESSION should remain gitignored after updater migration"
  git check-ignore -q ".session/validation-results.json" \
    || fail "validation-results.json should remain gitignored after updater migration"
  rm -f .session/ACTIVE_SESSION .session/validation-results.json

  # 52b) fresh install keeps session history trackable while ignoring ephemeral files
  log "52b) fresh install keeps session history trackable"
  mkdir -p fresh-install-repo
  (
    cd fresh-install-repo
    git init -q
    SESSION_WORKFLOW_SOURCE_DIR="$ROOT_DIR" bash "$ROOT_DIR/install.sh" >/dev/null
    grep -qxF ".session/ACTIVE_SESSION" .gitignore \
      || fail "install should ignore ACTIVE_SESSION"
    grep -qxF ".session/validation-results.json" .gitignore \
      || fail "install should ignore validation-results.json"
    grep -qxF ".session/sessions/**/state.json" .gitignore \
      || fail "install should ignore volatile state.json bookkeeping"
    ! grep -qxF ".session/sessions/" .gitignore \
      || fail "install should not ignore .session/sessions/"
    mkdir -p ".session/sessions/2026-03/2026-03-02-1"
    cat > ".session/sessions/2026-03/2026-03-02-1/notes.md" <<'EOF'
fresh install session artifact
EOF
    echo '{}' > ".session/sessions/2026-03/2026-03-02-1/state.json"
    echo "active" > .session/ACTIVE_SESSION
    echo '{"overall":"pass"}' > .session/validation-results.json
    git check-ignore -q ".session/sessions/2026-03/2026-03-02-1/notes.md" \
      && fail "fresh installs should not ignore session artifacts"
    git check-ignore -q ".session/sessions/2026-03/2026-03-02-1/state.json" \
      || fail "fresh installs should ignore state.json"
    git check-ignore -q ".session/ACTIVE_SESSION" \
      || fail "fresh installs should ignore ACTIVE_SESSION"
    git check-ignore -q ".session/validation-results.json" \
      || fail "fresh installs should ignore validation-results.json"
  )
  rm -rf fresh-install-repo

  # 53) install/update/docs reflect the stable updater wrapper and manifest
  log "53) stable updater wrapper and manifest are documented"
  grep -q "\.session/update\.sh" "$ROOT_DIR/README.md" \
    || fail "README should document the stable updater wrapper"
  grep -q "install-manifest.json" "$ROOT_DIR/README.md" \
    || fail "README should document the managed-file manifest"
  grep -q "update-wrapper.sh" "$ROOT_DIR/install.sh" \
    || fail "install.sh should install the stable updater wrapper source"
  grep -q "install-manifest.json" "$ROOT_DIR/install.sh" \
    || fail "install.sh should write the managed-file manifest"
  grep -q "update-wrapper.sh" "$ROOT_DIR/update.sh" \
    || fail "update.sh should refresh the stable updater wrapper"
  grep -q "install-manifest.json" "$ROOT_DIR/update.sh" \
    || fail "update.sh should manage the install manifest"
  grep -q "\.session/sessions/" "$ROOT_DIR/README.md" \
    || fail "README should describe the session-history policy"
  grep -q "durable repository history" "$ROOT_DIR/README.md" \
    || fail "README should say that session artifacts are durable repository history"
  grep -qi "volatile workflow bookkeeping" "$ROOT_DIR/README.md" \
    || fail "README should distinguish volatile state.json bookkeeping"
  grep -q "\.session/update\.sh" "$ROOT_DIR/session/docs/reference.md" \
    || fail "reference docs should mention the stable updater wrapper"
  grep -q "install-manifest.json" "$ROOT_DIR/session/docs/reference.md" \
    || fail "reference docs should mention the managed-file manifest"
  grep -q "durable repository history" "$ROOT_DIR/session/docs/reference.md" \
    || fail "reference docs should document the versioned session-history policy"
  grep -qi "volatile workflow bookkeeping" "$ROOT_DIR/session/docs/reference.md" \
    || fail "reference docs should distinguish volatile state.json bookkeeping"
  grep -q "intentionally ignored from git" "$ROOT_DIR/session/docs/schema-versioning.md" \
    || fail "schema docs should classify state.json as local bookkeeping"
  grep -q "Never stage \`.session/sessions.*/state.json\`" "$ROOT_DIR/github/agents/session.execute.agent.md" \
    || fail "session.execute agent should forbid staging volatile state.json"
  grep -q "excluding volatile session bookkeeping" "$ROOT_DIR/github/agents/session.validate.agent.md" \
    || fail "session.validate agent should exclude volatile state.json bookkeeping"
  grep -q "not state.json" "$ROOT_DIR/github/agents/session.wrap.agent.md" \
    || fail "session.wrap agent should exclude state.json from archival artifacts"
  grep -q "FIX (#72)" "$ROOT_DIR/CHANGELOG.md" \
    || fail "CHANGELOG should record the state.json bookkeeping fix"
  grep -q "FIX (#68)" "$ROOT_DIR/CHANGELOG.md" \
    || fail "CHANGELOG should record the session-history policy fix"

  # The updater/install coverage above intentionally dirties the temp repo.
  # Checkpoint those changes so later wrap tests only need to archive
  # wrap-managed session artifacts.
  if [[ -n "$(git status --porcelain)" ]]; then
    git add -A
    git commit -qm "test: checkpoint updater coverage"
  fi

  # 54) session-start accepts --brainstorm and records the orchestration flag
  log "54) session-start accepts --brainstorm"
  local start_brainstorm_json brainstorm_session_id
  start_brainstorm_json=$(./.session/scripts/bash/session-start.sh --json --brainstorm "Brainstorm compatibility test")
  assert_eq "ok" "$(echo "$start_brainstorm_json" | jq -r '.status')" "session-start should accept --brainstorm"
  assert_eq "true" "$(echo "$start_brainstorm_json" | jq -r '.orchestration.brainstorm')" "orchestration.brainstorm should be true"
  assert_eq "development" "$(echo "$start_brainstorm_json" | jq -r '.session.workflow')" "brainstorm should keep the default development workflow"
  brainstorm_session_id=$(echo "$start_brainstorm_json" | jq -r '.session.id')
  set_workflow_step "$brainstorm_session_id" "execute" "completed" >/dev/null
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null

  # 55) brainstorm workflow contract and docs are explicit
  log "55) brainstorm workflow is explicitly documented"
  local invalid_brainstorm_output invalid_brainstorm_status invalid_brainstorm_operational_output invalid_brainstorm_operational_status brainstorm_help_output
  set +e
  invalid_brainstorm_output=$(./.session/scripts/bash/session-start.sh --json --maintenance --brainstorm "Bad combo" 2>&1)
  invalid_brainstorm_status=$?
  set -e
  [[ $invalid_brainstorm_status -ne 0 ]] \
    || fail "session-start should reject --brainstorm for maintenance workflow"
  echo "$invalid_brainstorm_output" | grep -q -- "--brainstorm is only supported for development or spike workflows" \
    || fail "session-start should explain that brainstorm is limited to planning workflows"

  set +e
  invalid_brainstorm_operational_output=$(./.session/scripts/bash/session-start.sh --json --operational --brainstorm "Bad operational combo" 2>&1)
  invalid_brainstorm_operational_status=$?
  set -e
  [[ $invalid_brainstorm_operational_status -ne 0 ]] \
    || fail "session-start should reject --brainstorm for operational workflow"
  echo "$invalid_brainstorm_operational_output" | grep -q -- "--brainstorm is only supported for development or spike workflows" \
    || fail "session-start should explain that brainstorm is limited to development or spike workflows"

  brainstorm_help_output=$(./.session/scripts/bash/session-start.sh --help)
  echo "$brainstorm_help_output" | grep -q -- "--brainstorm" \
    || fail "session-start help should mention the --brainstorm flag"
  echo "$brainstorm_help_output" | grep -q "Insert optional brainstorm step before planning" \
    || fail "session-start help should explain what --brainstorm does"
  grep -q "invoke session.start --brainstorm" "$ROOT_DIR/README.md" \
    || fail "README should document the recommended brainstorm entrypoint"
  grep -q "orchestration.brainstorm" "$ROOT_DIR/github/agents/session.start.agent.md" \
    || fail "session.start agent should inspect the brainstorm orchestration flag"
  grep -q "requires an active session already created by \`session.start\`" "$ROOT_DIR/github/agents/session.brainstorm.agent.md" \
    || fail "session.brainstorm agent should say that session.start must run first"
  grep -q "Recommended entrypoint: \`invoke session.start --brainstorm" "$ROOT_DIR/session/docs/reference.md" \
    || fail "reference docs should recommend session.start --brainstorm"
  grep -q "session.start --brainstorm" "$ROOT_DIR/session/docs/shared-workflow.md" \
    || fail "shared workflow docs should mention the brainstorm entrypoint"
  grep -q "session.start --brainstorm" "$ROOT_DIR/.github/copilot-instructions.md" \
    || fail "copilot instructions should mention the brainstorm entrypoint"
  grep -q "session.start --brainstorm" "$ROOT_DIR/stubs/copilot_instructions.md" \
    || fail "copilot instructions stub should mention the brainstorm entrypoint"
  grep -q "session.start.*--brainstorm" "$ROOT_DIR/CHANGELOG.md" \
    || fail "CHANGELOG should record the brainstorm entrypoint change"

  # 56) session-start accepts --operational and records operational workflow
  log "56) session-start accepts --operational"
  local start_operational_json operational_session_id
  start_operational_json=$(./.session/scripts/bash/session-start.sh --json --operational "Run monitored batch pipeline")
  assert_eq "ok" "$(echo "$start_operational_json" | jq -r '.status')" "session-start should accept --operational"
  assert_eq "operational" "$(echo "$start_operational_json" | jq -r '.session.workflow')" "session workflow should be operational"
  assert_eq "false" "$(echo "$start_operational_json" | jq -r '.session.read_only')" "operational workflow should not imply read-only mode"
  operational_session_id=$(echo "$start_operational_json" | jq -r '.session.id')
  set_workflow_step "$operational_session_id" "execute" "completed" >/dev/null
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null

  # 57) operational help text documents runtime-loop default
  log "57) operational help text documents runtime loop"
  help_output=$(./.session/scripts/bash/session-start.sh --help)
  grep -q -- "--operational" <<< "$help_output" \
    || fail "session-start help should mention the --operational flag"
  grep -q "Operational workflow: iterative pipeline/batch runs" <<< "$help_output" \
    || fail "session-start help should describe the operational workflow"
  grep -q "operational (--operational) - Runtime loop: start → execute → STOP by default; --auto adds wrap" <<< "$help_output" \
    || fail "session-start help should describe operational as a stop-after-execute runtime loop"

  # 58) operational docs and agent contracts reflect iterative runtime workflow
  log "58) operational docs and agent contracts reflect runtime workflow"
  grep -q "Operational Workflow: execute → STOP" "$ROOT_DIR/github/agents/session.start.agent.md" \
    || fail "session.start agent should document operational execute → STOP default"
  grep -q "\`batch\`, \`pipeline\`, \`backfill\`, \`ingest\`, \`scrape\`, \`transcode\`, \`reprocess\`, \`rerun\`" "$ROOT_DIR/github/agents/session.start.agent.md" \
    || fail "session.start agent should include operational smart-routing signals"
  grep -q "workflow is \`development\`, \`spike\`, or \`operational\`" "$ROOT_DIR/github/agents/session.start.agent.md" \
    || fail "session.start agent should create a branch for operational workflow"
  grep -q "check_workflow_allowed \"\$SESSION_ID\" \"development\" \"spike\" \"maintenance\" \"debug\" \"operational\"" "$ROOT_DIR/github/agents/session.execute.agent.md" \
    || fail "session.execute agent should allow operational workflow"
  grep -q "Operational Workflow: → STOP" "$ROOT_DIR/github/agents/session.execute.agent.md" \
    || fail "session.execute agent should document operational stop-after-execute direct mode"
  grep -q "invoke session.start --operational" "$ROOT_DIR/README.md" \
    || fail "README should include an operational workflow example"
  grep -q "### 5. Operational" "$ROOT_DIR/README.md" \
    || fail "README should describe the operational workflow type"
  grep -q "invoke session.start --operational" "$ROOT_DIR/session/docs/reference.md" \
    || fail "reference docs should include the operational workflow"
  grep -q "Operational (iterative runtime work)" "$ROOT_DIR/session/docs/shared-workflow.md" \
    || fail "shared workflow docs should describe the operational workflow"
  grep -Fq "\`development\` \| \`spike\` \| \`maintenance\` \| \`debug\` \| \`operational\`" "$ROOT_DIR/session/docs/schema-versioning.md" \
    || fail "schema docs should include operational as a workflow value"
  grep -q "Operational workflow" "$ROOT_DIR/.github/copilot-instructions.md" \
    || fail "copilot instructions should mention the operational workflow"
  grep -q "invoke session.start --operational" "$ROOT_DIR/stubs/copilot_instructions.md" \
    || fail "copilot instructions stub should include the operational workflow"
  grep -q "development/spike/maintenance/debug/operational" "$ROOT_DIR/session/docs/copilot-cli-mechanics.md" \
    || fail "Copilot CLI mechanics docs should mention the operational workflow"
  grep -q "Added an \`operational\` workflow" "$ROOT_DIR/CHANGELOG.md" \
    || fail "CHANGELOG should record the new operational workflow"

  # 59) session-audit.sh and validation-summary surfaces are wired into docs and installers
  log "59) session-audit.sh and validation summary surfaces are documented"
  grep -q "session-audit.sh" "$ROOT_DIR/install.sh" \
    || fail "install.sh should install the session-audit script"
  grep -q "session-audit.sh" "$ROOT_DIR/update.sh" \
    || fail "update.sh should update the session-audit script"
  [[ ! -f "$ROOT_DIR/github/agents/session.audit.agent.md" ]] \
    || fail "session.audit agent should no longer be shipped"
  [[ ! -f "$ROOT_DIR/github/prompts/session.audit.prompt.md" ]] \
    || fail "session.audit prompt should no longer be shipped"
  if grep -q "session.audit.agent.md" "$ROOT_DIR/install.sh"; then
    fail "install.sh should not install the removed session.audit agent"
  fi
  if grep -q "session.audit.prompt.md" "$ROOT_DIR/update.sh"; then
    fail "update.sh should not update the removed session.audit prompt"
  fi
  grep -q "./.session/scripts/bash/session-audit.sh --all --summary" "$ROOT_DIR/README.md" \
    || fail "README should document the direct session-audit.sh entrypoint"
  grep -q "#### session-audit.sh" "$ROOT_DIR/session/docs/reference.md" \
    || fail "reference docs should document session-audit.sh as a script"
  grep -q "VALIDATION_RESULTS_SCHEMA_VERSION" "$ROOT_DIR/session/docs/schema-versioning.md" \
    || fail "schema docs should document validation-results.json schema version"
  grep -q "./.session/scripts/bash/session-audit.sh --all --summary" "$ROOT_DIR/.github/copilot-instructions.md" \
    || fail "copilot instructions should mention the direct session-audit.sh utility"
  grep -q "./.session/scripts/bash/session-audit.sh --all --summary" "$ROOT_DIR/stubs/copilot_instructions.md" \
    || fail "copilot instructions stub should mention the direct session-audit.sh utility"
  if grep -q "invoke session.audit" "$ROOT_DIR/.github/copilot-instructions.md"; then
    fail "copilot instructions should not advertise session.audit as an agent"
  fi
  if grep -q "invoke session.audit" "$ROOT_DIR/stubs/copilot_instructions.md"; then
    fail "copilot instructions stub should not advertise session.audit as an agent"
  fi
  grep -q "NEW (#50)" "$ROOT_DIR/CHANGELOG.md" \
    || fail "CHANGELOG should record the direct session-audit.sh entrypoint"
}

main "$@"
