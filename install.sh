#!/usr/bin/env bash
set -euo pipefail

REPO_RAW_BASE="https://raw.githubusercontent.com/GlennPegden2/bsl2026-kiosk/main"
BOOTSTRAP_ROOT=""

cleanup() {
	if [[ -n "${BOOTSTRAP_ROOT}" && -d "${BOOTSTRAP_ROOT}" ]]; then
		rm -rf "${BOOTSTRAP_ROOT}"
	fi
}

trap cleanup EXIT

SCRIPT_PATH="${BASH_SOURCE[0]-}"
SCRIPT_DIR=""
if [[ -n "${SCRIPT_PATH}" && -f "${SCRIPT_PATH}" ]]; then
	SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
fi

if [[ -n "${SCRIPT_DIR}" && -f "${SCRIPT_DIR}/scripts/install-kiosk.sh" ]]; then
	exec bash -- "${SCRIPT_DIR}/scripts/install-kiosk.sh" "$@"
fi

if ! command -v curl >/dev/null 2>&1; then
	echo "[install] curl is required when running install.sh without a local repo checkout." >&2
	exit 1
fi

BOOTSTRAP_ROOT="$(mktemp -d)"
mkdir -p "${BOOTSTRAP_ROOT}/scripts" "${BOOTSTRAP_ROOT}/kiosk/files"

download_file() {
	local relative_path="$1"
	curl -fsSL "${REPO_RAW_BASE}/${relative_path}" -o "${BOOTSTRAP_ROOT}/${relative_path}"
}

echo "[install] No local repo checkout detected; downloading installer files..."
download_file scripts/install-kiosk.sh
download_file kiosk/packages.txt
download_file kiosk/files/slideshow.py
download_file kiosk/files/xsession.sh
download_file kiosk/files/smb.conf

chmod +x "${BOOTSTRAP_ROOT}/scripts/install-kiosk.sh"

exec bash -- "${BOOTSTRAP_ROOT}/scripts/install-kiosk.sh" --repo-root "${BOOTSTRAP_ROOT}" "$@"