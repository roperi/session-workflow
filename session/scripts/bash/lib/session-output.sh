#!/usr/bin/env bash
# lib/session-output.sh - Colors, print helpers, JSON output primitives
#
# No dependencies on other session libs.
# Can be sourced independently for unit testing.

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# JSON Output Functions
# ============================================================================

json_escape() {
    # Escape string for JSON
    local str="$1"
    str="${str//\\/\\\\}"  # Backslash
    str="${str//\"/\\\"}"  # Double quote
    str="${str//$'\n'/\\n}" # Newline
    str="${str//$'\r'/\\r}" # Carriage return
    str="${str//$'\t'/\\t}" # Tab
    echo "$str"
}

json_error_msg() {
    # Emit a consistent JSON error envelope to stdout.
    # Args: message [hint]
    local message="$1"
    local hint="${2:-}"
    if [[ -n "$hint" ]]; then
        jq -n --arg m "$message" --arg h "$hint" '{"status":"error","message":$m,"hint":$h}'
    else
        jq -n --arg m "$message" '{"status":"error","message":$m}'
    fi
}

# ============================================================================
# Output Functions
# ============================================================================

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}
