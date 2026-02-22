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
  # Copy lib sub-directory (session-common.sh now sources these)
  mkdir -p "$repo_root/.session/scripts/bash/lib"
  cp "$ROOT_DIR"/session/scripts/bash/lib/*.sh "$repo_root/.session/scripts/bash/lib/"
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

  # 11) for_next_session and notes_summary non-empty after wrap (F-4 regression)
  log "11) for_next_session non-empty after wrap (path correctness)"
  local start4_json s4_id s4_year_month s4_dir
  start4_json=$(./.session/scripts/bash/session-start.sh --json "Notes continuity goal")
  s4_id=$(echo "$start4_json" | jq -r '.session.id')
  s4_year_month=$(echo "$s4_id" | cut -d'-' -f1,2)
  s4_dir=".session/sessions/${s4_year_month}/${s4_id}"
  # Write a "For Next Session" section
  printf '\n## For Next Session\n- carry this forward\n' >> "${s4_dir}/notes.md"
  set_workflow_step "$s4_id" "execute" "completed" >/dev/null
  ././.session/scripts/bash/session-wrap.sh --json >/dev/null
  # Chain a new session and check for_next_session is populated
  local start5_json
  start5_json=$(./.session/scripts/bash/session-start.sh --json --continues-from "$s4_id" "Continuation goal")
  local for_next
  for_next=$(echo "$start5_json" | jq -r '.previous_session.for_next_session')
  [[ -n "$for_next" && "$for_next" != "null" ]] || fail "for_next_session should not be empty after wrap (F-4 regression)"
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
}

main "$@"
