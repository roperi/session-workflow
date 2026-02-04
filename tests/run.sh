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
  cp "$ROOT_DIR"/session/templates/*.md "$repo_root/.session/templates/" 2>/dev/null || true
  chmod +x "$repo_root/.session/scripts/bash"/*.sh
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
    trap "echo \"Keeping temp dir: $tmp_base\" >&2" EXIT
    log "Temp repo: $repo_root"
  else
    # Expand $tmp_base at trap definition time (avoid relying on locals at EXIT).
    trap "rm -rf '$tmp_base'" EXIT
    vlog "Temp repo: $repo_root"
  fi

  install_session_workflow_into_repo "$repo_root"

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
  assert_file_exists "$session_dir/tasks.md"

  assert_eq "unstructured" "$(jq -r '.type' "$session_dir/session-info.json")" "session type"
  assert_eq "development" "$(jq -r '.workflow' "$session_dir/session-info.json")" "workflow default"
  assert_eq "production" "$(jq -r '.stage' "$session_dir/session-info.json")" "stage default"

  # 2) session-handoff-list should include the created session
  log "2) session-handoff-list (JSON)"
  local list_json
  list_json=$(./.session/scripts/bash/session-handoff-list.sh --json)
  vlog "list_json: $list_json"
  assert_eq "ok" "$(echo "$list_json" | jq -r '.status')" "handoff list status"
  assert_eq "$session_id" "$(echo "$list_json" | jq -r '.sessions[0].id')" "most recent session should be first"

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
  [[ ! -f ".session/ACTIVE_SESSION" ]] || fail "ACTIVE_SESSION should be cleared after wrap"

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

  log "All tests passed (start, preflight, wrap)."
}

main "$@"
