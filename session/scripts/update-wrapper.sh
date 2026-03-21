#!/usr/bin/env bash
# Stable updater entrypoint installed into downstream repos as .session/update.sh

set -euo pipefail

REPO_URL="${SESSION_WORKFLOW_REPO_URL:-https://raw.githubusercontent.com/roperi/session-workflow/main}"
SOURCE_DIR="${SESSION_WORKFLOW_SOURCE_DIR:-}"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || (cd "${SCRIPT_DIR}/.." && pwd))

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

download_updater() {
    local dest="$1"

    if command -v curl >/dev/null 2>&1; then
        curl -sSL "${REPO_URL}/update.sh" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "${REPO_URL}/update.sh" -O "$dest"
    else
        error "Neither curl nor wget found. Please install one."
    fi
}

main() {
    cd "$REPO_ROOT"

    if [[ -n "$SOURCE_DIR" ]]; then
        if [[ ! -d "$SOURCE_DIR" ]]; then
            error "SESSION_WORKFLOW_SOURCE_DIR does not exist: $SOURCE_DIR"
        fi

        SOURCE_DIR=$(cd "$SOURCE_DIR" && pwd)
        if [[ ! -f "${SOURCE_DIR}/update.sh" ]]; then
            error "Canonical updater not found at ${SOURCE_DIR}/update.sh"
        fi

        bash "${SOURCE_DIR}/update.sh" "$@"
        exit $?
    fi

    local tmp
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT

    download_updater "$tmp"
    bash "$tmp" "$@"
}

main "$@"
