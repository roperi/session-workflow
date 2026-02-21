#!/usr/bin/env bash
# session-common.sh - Backward-compatible aggregator for session workflow libs.
#
# All runtime scripts source this file. It sources the sub-libraries in
# dependency order so callers need no changes.
#
# Sub-library layout (session/scripts/bash/lib/):
#   session-output.sh  — colors, print_*, json_escape, json_error_msg
#   session-paths.sh   — path constants, schema version constants, session ID/dir functions
#   session-tasks.sh   — task counting, task file resolution, issue/task management
#   session-git.sh     — prerequisites, PR helpers, git/quality/validation functions
#   session-state.sh   — schema validation, session context, workflow FSM
#
# See session/docs/schema-versioning.md for JSON schema documentation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# shellcheck source=lib/session-output.sh
source "${LIB_DIR}/session-output.sh"
# shellcheck source=lib/session-paths.sh
source "${LIB_DIR}/session-paths.sh"
# shellcheck source=lib/session-tasks.sh
source "${LIB_DIR}/session-tasks.sh"
# shellcheck source=lib/session-git.sh
source "${LIB_DIR}/session-git.sh"
# shellcheck source=lib/session-state.sh
source "${LIB_DIR}/session-state.sh"
