#!/usr/bin/env bash
set -euo pipefail

KIOSK_USER="pi"
PURGE_PACKAGES="0"
REMOVE_MEDIA="0"

usage() {
    cat <<'EOF'
Usage: sudo bash reset.sh [options]

Options:
  --user <name>          Linux user configured for kiosk mode (default: pi)
  --purge-packages       Purge kiosk packages listed in kiosk/packages.txt
  --remove-media         Remove ~/slideshow directory for kiosk user
  -h, --help             Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)
            KIOSK_USER="${2:-}"
            shift 2
            ;;
        --purge-packages)
            PURGE_PACKAGES="1"
            shift
            ;;
        --remove-media)
            REMOVE_MEDIA="1"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[reset] Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ "$(id -u)" -ne 0 ]]; then
    echo "[reset] Please run as root (use sudo)." >&2
    exit 1
fi

KIOSK_HOME=""
if id -u "${KIOSK_USER}" >/dev/null 2>&1; then
    KIOSK_HOME="$(getent passwd "${KIOSK_USER}" | cut -d: -f6)"
fi

BOOT_MOUNT="/boot/firmware"
if [[ ! -d "${BOOT_MOUNT}" ]]; then
    BOOT_MOUNT="/boot"
fi

echo "[reset] Stopping Samba services if installed..."
systemctl disable smbd nmbd >/dev/null 2>&1 || true
systemctl stop smbd nmbd >/dev/null 2>&1 || true

echo "[reset] Removing kiosk runtime files..."
rm -f /usr/local/bin/slideshow.py
rm -f /usr/local/bin/kiosk-xsession.sh

echo "[reset] Restoring tty1 autologin defaults..."
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf
if [[ -d /etc/systemd/system/getty@tty1.service.d ]]; then
    rmdir /etc/systemd/system/getty@tty1.service.d 2>/dev/null || true
fi

if [[ -n "${KIOSK_HOME}" && -f "${KIOSK_HOME}/.bash_profile" ]]; then
    echo "[reset] Removing kiosk block from ${KIOSK_HOME}/.bash_profile..."
    sed -i '/# BEGIN BSL2026 KIOSK/,/# END BSL2026 KIOSK/d' "${KIOSK_HOME}/.bash_profile"
    chown "${KIOSK_USER}:${KIOSK_USER}" "${KIOSK_HOME}/.bash_profile" || true
fi

if [[ -f /etc/samba/smb.conf ]] && grep -q "Kiosk Media Server" /etc/samba/smb.conf; then
    echo "[reset] Removing kiosk Samba config..."
    rm -f /etc/samba/smb.conf
fi

BOOT_CONFIG=""
if [[ -f /boot/firmware/config.txt ]]; then
    BOOT_CONFIG="/boot/firmware/config.txt"
elif [[ -f /boot/config.txt ]]; then
    BOOT_CONFIG="/boot/config.txt"
fi

if [[ -n "${BOOT_CONFIG}" ]]; then
    sed -i '/# BEGIN BSL2026 KIOSK DISPLAY/,/# END BSL2026 KIOSK DISPLAY/d' "${BOOT_CONFIG}"
fi

CMDLINE_FILE=""
if [[ -f /boot/firmware/cmdline.txt ]]; then
    CMDLINE_FILE="/boot/firmware/cmdline.txt"
elif [[ -f /boot/cmdline.txt ]]; then
    CMDLINE_FILE="/boot/cmdline.txt"
fi

if [[ -n "${CMDLINE_FILE}" ]]; then
    sed -i 's/ consoleblank=0//g' "${CMDLINE_FILE}"
fi

if [[ "${REMOVE_MEDIA}" == "1" && -n "${KIOSK_HOME}" && -d "${KIOSK_HOME}/slideshow" ]]; then
    echo "[reset] Removing media directory ${KIOSK_HOME}/slideshow..."
    rm -rf "${KIOSK_HOME}/slideshow"
fi

if [[ "${REMOVE_MEDIA}" == "1" && -d "${BOOT_MOUNT}/slideshow" ]]; then
    echo "[reset] Removing FAT import folder ${BOOT_MOUNT}/slideshow..."
    rm -rf "${BOOT_MOUNT}/slideshow"
fi

if [[ "${PURGE_PACKAGES}" == "1" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
    PACKAGES_FILE="${REPO_ROOT}/kiosk/packages.txt"

    if [[ -f "${PACKAGES_FILE}" ]]; then
        echo "[reset] Purging kiosk packages from ${PACKAGES_FILE}..."
        xargs -a "${PACKAGES_FILE}" apt-get purge -y || true
        apt-get autoremove -y || true
    else
        echo "[reset] Package list not found; skipping purge." >&2
    fi
fi

systemctl daemon-reload

echo
echo "[reset] Reset complete."
echo "[reset] Reboot is recommended."