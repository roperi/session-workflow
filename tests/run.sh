#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

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

  local repo_root
  repo_root=$(make_tmp_repo)
  local tmp_base
  tmp_base=$(dirname "$repo_root")
  # Expand $tmp_base at trap definition time (avoid relying on locals at EXIT).
  trap "rm -rf '$tmp_base'" EXIT

  install_session_workflow_into_repo "$repo_root"

  cd "$repo_root"

  # 1) Start unstructured session (JSON)
  local start_json session_id repo_root_json year_month session_dir
  start_json=$(./.session/scripts/bash/session-start.sh --json "Test goal")
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

  # 2) Preflight plan should succeed
  local preflight_plan_json
  preflight_plan_json=$(./.session/scripts/bash/session-preflight.sh --step plan --json)
  assert_eq "ok" "$(echo "$preflight_plan_json" | jq -r '.status')" "preflight plan status"
  assert_eq "$repo_root" "$(echo "$preflight_plan_json" | jq -r '.repo_root')" "preflight repo_root"

  # 3) Attempt to move to execute while plan is in_progress should warn + exit 2
  set +e
  local preflight_execute_json
  preflight_execute_json=$(./.session/scripts/bash/session-preflight.sh --step execute --json)
  local exit_code=$?
  set -e
  assert_eq "2" "$exit_code" "expected interrupted-session exit code"
  assert_eq "warning" "$(echo "$preflight_execute_json" | jq -r '.status')" "expected warning JSON"

  # 4) Complete plan, then task should be allowed
  # shellcheck source=/dev/null
  source ./.session/scripts/bash/session-common.sh
  set_workflow_step "$session_id" "plan" "completed" >/dev/null

  local preflight_task_json
  preflight_task_json=$(./.session/scripts/bash/session-preflight.sh --step task --json)
  assert_eq "ok" "$(echo "$preflight_task_json" | jq -r '.status')" "preflight task status"

  # 5) Complete task, then execute should be allowed
  set_workflow_step "$session_id" "task" "completed" >/dev/null
  local preflight_exec_ok_json
  preflight_exec_ok_json=$(./.session/scripts/bash/session-preflight.sh --step execute --json)
  assert_eq "ok" "$(echo "$preflight_exec_ok_json" | jq -r '.status')" "preflight execute status"

  # 6) Wrap should clear ACTIVE_SESSION
  # Mark execute completed to avoid interrupted warnings
  set_workflow_step "$session_id" "execute" "completed" >/dev/null
  ././.session/scripts/bash/session-wrap.sh --json >/dev/null
  [[ ! -f ".session/ACTIVE_SESSION" ]] || fail "ACTIVE_SESSION should be cleared after wrap"

  echo "All tests passed."
}

main "$@"
