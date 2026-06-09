#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
KIOSK_USER="pi"
KIOSK_HOSTNAME=""
AUTO_REBOOT="0"

usage() {
    cat <<'EOF'
Usage: sudo bash install.sh [options]

Options:
  --user <name>        Linux user that runs the kiosk session (default: pi)
  --hostname <name>    Set system hostname
  --repo-root <path>   Override repository root path
  --reboot             Reboot automatically when setup completes
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)
            KIOSK_USER="${2:-}"
            shift 2
            ;;
        --hostname)
            KIOSK_HOSTNAME="${2:-}"
            shift 2
            ;;
        --repo-root)
            REPO_ROOT="${2:-}"
            shift 2
            ;;
        --reboot)
            AUTO_REBOOT="1"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[install] Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ "$(id -u)" -ne 0 ]]; then
    echo "[install] Please run as root (use sudo)." >&2
    exit 1
fi

if [[ ! -d "${REPO_ROOT}" ]]; then
    echo "[install] Repository root not found: ${REPO_ROOT}" >&2
    exit 1
fi

if ! id -u "${KIOSK_USER}" >/dev/null 2>&1; then
    echo "[install] User does not exist: ${KIOSK_USER}" >&2
    exit 1
fi

KIOSK_HOME="$(getent passwd "${KIOSK_USER}" | cut -d: -f6)"
if [[ -z "${KIOSK_HOME}" || ! -d "${KIOSK_HOME}" ]]; then
    echo "[install] Home directory not found for user ${KIOSK_USER}" >&2
    exit 1
fi

MEDIA_DIR="${KIOSK_HOME}/slideshow"
PACKAGES_FILE="${REPO_ROOT}/kiosk/packages.txt"
FILES_DIR="${REPO_ROOT}/kiosk/files"

for required in "${PACKAGES_FILE}" "${FILES_DIR}/slideshow.py" "${FILES_DIR}/xsession.sh" "${FILES_DIR}/smb.conf"; do
    if [[ ! -f "${required}" ]]; then
        echo "[install] Required file missing: ${required}" >&2
        exit 1
    fi
done

echo "[install] Installing OS packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
xargs -a "${PACKAGES_FILE}" apt-get install -y

echo "[install] Installing kiosk runtime files..."
install -m 755 "${FILES_DIR}/slideshow.py" /usr/local/bin/slideshow.py
install -m 755 "${FILES_DIR}/xsession.sh" /usr/local/bin/kiosk-xsession.sh
install -m 644 "${FILES_DIR}/smb.conf" /etc/samba/smb.conf

# Patch user-specific paths into the copied config files.
sed -i "s|/home/pi/slideshow|${MEDIA_DIR}|g" /usr/local/bin/slideshow.py
sed -i "s|path = /home/pi/slideshow|path = ${MEDIA_DIR}|" /etc/samba/smb.conf
sed -i "s|force user = pi|force user = ${KIOSK_USER}|" /etc/samba/smb.conf

echo "[install] Preparing media folder at ${MEDIA_DIR}..."
install -d -m 775 -o "${KIOSK_USER}" -g "${KIOSK_USER}" "${MEDIA_DIR}"
cat > "${MEDIA_DIR}/README.txt" << 'EOF'
Drop your .jpg / .png / .mp4 files here.
EOF
chown "${KIOSK_USER}:${KIOSK_USER}" "${MEDIA_DIR}/README.txt"

echo "[install] Configuring tty1 autologin for ${KIOSK_USER}..."
install -d /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${KIOSK_USER} --noclear %I \$TERM
EOF

BASH_PROFILE="${KIOSK_HOME}/.bash_profile"
if [[ ! -f "${BASH_PROFILE}" ]]; then
    touch "${BASH_PROFILE}"
    chown "${KIOSK_USER}:${KIOSK_USER}" "${BASH_PROFILE}"
fi

if ! grep -q "BEGIN BSL2026 KIOSK" "${BASH_PROFILE}"; then
    cat >> "${BASH_PROFILE}" << 'EOF'

# BEGIN BSL2026 KIOSK
[[ -f ~/.bashrc ]] && . ~/.bashrc

if [[ -z "$DISPLAY" ]] && [[ "$(tty)" == "/dev/tty1" ]]; then
    exec startx /usr/local/bin/kiosk-xsession.sh -- :0 -nocursor 2>>/tmp/kiosk-x.log
fi
# END BSL2026 KIOSK
EOF
fi
chown "${KIOSK_USER}:${KIOSK_USER}" "${BASH_PROFILE}"

echo "[install] Applying Samba and display settings..."
systemctl enable smbd nmbd
systemctl restart smbd nmbd

BOOT_CONFIG=""
if [[ -f /boot/firmware/config.txt ]]; then
    BOOT_CONFIG="/boot/firmware/config.txt"
elif [[ -f /boot/config.txt ]]; then
    BOOT_CONFIG="/boot/config.txt"
fi

if [[ -n "${BOOT_CONFIG}" ]] && ! grep -q "BEGIN BSL2026 KIOSK DISPLAY" "${BOOT_CONFIG}"; then
    cat >> "${BOOT_CONFIG}" << 'EOF'

# BEGIN BSL2026 KIOSK DISPLAY
hdmi_force_hotplug=1
disable_overscan=1
hdmi_pixel_encoding=2
# END BSL2026 KIOSK DISPLAY
EOF
fi

CMDLINE_FILE=""
if [[ -f /boot/firmware/cmdline.txt ]]; then
    CMDLINE_FILE="/boot/firmware/cmdline.txt"
elif [[ -f /boot/cmdline.txt ]]; then
    CMDLINE_FILE="/boot/cmdline.txt"
fi

if [[ -n "${CMDLINE_FILE}" ]] && ! grep -q "consoleblank=0" "${CMDLINE_FILE}"; then
    sed -i 's/$/ consoleblank=0/' "${CMDLINE_FILE}"
fi

if [[ -n "${KIOSK_HOSTNAME}" ]]; then
    echo "[install] Setting hostname to ${KIOSK_HOSTNAME}..."
    echo "${KIOSK_HOSTNAME}" > /etc/hostname
    if grep -q '^127.0.1.1[[:space:]]' /etc/hosts; then
        sed -i "s/^127\.0\.1\.1[[:space:]].*/127.0.1.1\t${KIOSK_HOSTNAME}/" /etc/hosts
    else
        echo "127.0.1.1 ${KIOSK_HOSTNAME}" >> /etc/hosts
    fi
    hostnamectl set-hostname "${KIOSK_HOSTNAME}" || true
fi

systemctl daemon-reload

echo
echo "[install] Setup complete."
echo "[install] Media share: \\\\${KIOSK_HOSTNAME:-$(hostname)}\\slideshow"
echo "[install] Reboot required to apply autologin + display boot settings."

if [[ "${AUTO_REBOOT}" == "1" ]]; then
    echo "[install] Rebooting now..."
    reboot
fi