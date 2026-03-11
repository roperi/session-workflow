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

  # Wrap spec verification test session
  set_workflow_step "$sv_id" "execute" "completed" >/dev/null
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null

  log "All spec verification tests passed."

  # === Step History Tests (Issue #49) ===

  # 23) step_history initialized as empty array on session start
  log "23) step_history initialized as empty array"
  local start_sh_json sh_id sh_ym sh_dir
  start_sh_json=$(./.session/scripts/bash/session-start.sh --json "Step history test")
  sh_id=$(echo "$start_sh_json" | jq -r '.session.id')
  sh_ym=$(echo "$sh_id" | cut -d'-' -f1,2)
  sh_dir=".session/sessions/${sh_ym}/${sh_id}"
  assert_eq "[]" "$(jq -c '.step_history' "$sh_dir/state.json")" "step_history should be empty array at creation"
  assert_eq "1.1" "$(jq -r '.schema_version' "$sh_dir/state.json")" "state schema should be 1.1"

  # 24) preflight appends in_progress entry to step_history
  log "24) preflight appends in_progress entry to step_history"
  local preflight_sh_json
  preflight_sh_json=$(./.session/scripts/bash/session-preflight.sh --step scope --json)
  assert_eq "ok" "$(echo "$preflight_sh_json" | jq -r '.status')" "preflight scope status"
  assert_eq "1" "$(jq '.step_history | length' "$sh_dir/state.json")" "step_history should have 1 entry"
  assert_eq "scope" "$(jq -r '.step_history[0].step' "$sh_dir/state.json")" "first entry step should be scope"
  assert_eq "in_progress" "$(jq -r '.step_history[0].status' "$sh_dir/state.json")" "first entry status should be in_progress"
  assert_eq "null" "$(jq -r '.step_history[0].ended_at' "$sh_dir/state.json")" "first entry ended_at should be null"
  assert_eq "false" "$(jq -r '.step_history[0].forced' "$sh_dir/state.json")" "first entry forced should be false"

  # 25) completing a step updates the last history entry
  log "25) completing step updates history entry"
  set_workflow_step "$sh_id" "scope" "completed" >/dev/null
  assert_eq "1" "$(jq '.step_history | length' "$sh_dir/state.json")" "step_history should still have 1 entry"
  assert_eq "completed" "$(jq -r '.step_history[0].status' "$sh_dir/state.json")" "entry status should be completed"
  [[ "$(jq -r '.step_history[0].ended_at' "$sh_dir/state.json")" != "null" ]] || fail "ended_at should be set after completion"
  [[ "$(jq -r '.step_history[0].started_at' "$sh_dir/state.json")" != "null" ]] || fail "started_at should be preserved"

  # 26) full workflow builds complete step_history
  log "26) full workflow builds multi-entry step_history"
  set_workflow_step "$sh_id" "spec" "in_progress" >/dev/null
  set_workflow_step "$sh_id" "spec" "completed" >/dev/null
  set_workflow_step "$sh_id" "plan" "in_progress" >/dev/null
  set_workflow_step "$sh_id" "plan" "completed" >/dev/null
  set_workflow_step "$sh_id" "execute" "in_progress" >/dev/null
  set_workflow_step "$sh_id" "execute" "completed" >/dev/null
  assert_eq "4" "$(jq '.step_history | length' "$sh_dir/state.json")" "step_history should have 4 entries"
  assert_eq "scope" "$(jq -r '.step_history[0].step' "$sh_dir/state.json")" "entry 0 should be scope"
  assert_eq "spec" "$(jq -r '.step_history[1].step' "$sh_dir/state.json")" "entry 1 should be spec"
  assert_eq "plan" "$(jq -r '.step_history[2].step' "$sh_dir/state.json")" "entry 2 should be plan"
  assert_eq "execute" "$(jq -r '.step_history[3].step' "$sh_dir/state.json")" "entry 3 should be execute"
  # All entries should be completed with ended_at set
  local all_completed
  all_completed=$(jq '[.step_history[] | select(.status == "completed" and .ended_at != null)] | length' "$sh_dir/state.json")
  assert_eq "4" "$all_completed" "all 4 entries should be completed with ended_at"

  # 27) forced flag is recorded in step_history
  log "27) forced flag recorded in step_history"
  set_workflow_step "$sh_id" "validate" "in_progress" "true" >/dev/null
  assert_eq "5" "$(jq '.step_history | length' "$sh_dir/state.json")" "step_history should have 5 entries"
  assert_eq "true" "$(jq -r '.step_history[4].forced' "$sh_dir/state.json")" "forced entry should have forced=true"
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

  log "All step history tests passed."

  # === Postflight Tests ===

  # 29) postflight marks step as completed
  log "29) postflight marks step completed"
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
  log "30) postflight outputs valid next steps"
  local next_steps
  next_steps=$(echo "$postflight_json" | jq -r '.valid_next_steps[]' | sort | tr '\n' ' ' | sed 's/ $//')
  assert_eq "plan spec" "$next_steps" "scope's valid next steps should be spec and plan"

  # 31) postflight rejects mismatched step
  log "31) postflight rejects mismatched step"
  ./.session/scripts/bash/session-preflight.sh --step spec --json >/dev/null
  set +e
  local postflight_mismatch
  postflight_mismatch=$(./.session/scripts/bash/session-postflight.sh --step scope --json)
  local pf_exit=$?
  set -e
  assert_eq "1" "$pf_exit" "postflight should fail on step mismatch"
  assert_eq "error" "$(echo "$postflight_mismatch" | jq -r '.status')" "should be error on mismatch"

  # 32) postflight rejects already-completed step
  log "32) postflight rejects already-completed step"
  ./.session/scripts/bash/session-postflight.sh --step spec --json >/dev/null
  set +e
  local postflight_double
  postflight_double=$(./.session/scripts/bash/session-postflight.sh --step spec --json)
  local pf_double_exit=$?
  set -e
  assert_eq "1" "$pf_double_exit" "postflight should fail on already-completed step"
  assert_eq "error" "$(echo "$postflight_double" | jq -r '.status')" "should be error on double-complete"

  # 33) postflight with --status failed
  log "33) postflight marks step as failed"
  ./.session/scripts/bash/session-preflight.sh --step plan --json >/dev/null
  local postflight_fail_json
  postflight_fail_json=$(./.session/scripts/bash/session-postflight.sh --step plan --status failed --json)
  assert_eq "ok" "$(echo "$postflight_fail_json" | jq -r '.status')" "postflight status should be ok"
  assert_eq "failed" "$(echo "$postflight_fail_json" | jq -r '.result')" "postflight result should be failed"
  assert_eq "failed" "$(jq -r '.step_status' "$pf_dir/state.json")" "step should be failed in state.json"

  # 34) preflight + postflight full chain integration
  log "34) preflight + postflight full chain integration"
  local start_chain_json chain_id chain_ym chain_dir
  start_chain_json=$(./.session/scripts/bash/session-start.sh --json "Chain integration test")
  chain_id=$(echo "$start_chain_json" | jq -r '.session.id')
  chain_ym=$(echo "$chain_id" | cut -d'-' -f1,2)
  chain_dir=".session/sessions/${chain_ym}/${chain_id}"

  # Run full chain: scope → spec → plan → execute using preflight+postflight
  for step in scope spec plan execute; do
    ./.session/scripts/bash/session-preflight.sh --step "$step" --json >/dev/null
    ./.session/scripts/bash/session-postflight.sh --step "$step" --json >/dev/null
  done

  # Verify all 4 steps are in step_history with completed status
  assert_eq "4" "$(jq '.step_history | length' "$chain_dir/state.json")" "chain should have 4 entries"
  local chain_all_completed
  chain_all_completed=$(jq '[.step_history[] | select(.status == "completed" and .ended_at != null)] | length' "$chain_dir/state.json")
  assert_eq "4" "$chain_all_completed" "all 4 chain entries should be completed"
  assert_eq "execute" "$(jq -r '.current_step' "$chain_dir/state.json")" "current step should be execute"
  assert_eq "completed" "$(jq -r '.step_status' "$chain_dir/state.json")" "step status should be completed"

  # Wrap chain test session
  ./.session/scripts/bash/session-wrap.sh --json >/dev/null

  log "All postflight tests passed."
}

main "$@"
