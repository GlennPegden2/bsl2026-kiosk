#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config"
STAGE_DIR="${SCRIPT_DIR}/stage-kiosk"
DEPLOY_DIR="${SCRIPT_DIR}/deploy"

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "[quick-build] Missing config file: ${CONFIG_FILE}" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "${CONFIG_FILE}"

BASE_IMG="${1:-}"
OUTPUT_IMG="${2:-${DEPLOY_DIR}/${IMG_NAME}-quick.img}"

if [[ -z "${BASE_IMG}" ]]; then
    echo "Usage: ./quick-build.sh /path/to/base-raspios-lite.img [output.img]" >&2
    echo "Example: ./quick-build.sh ./raspios-lite.img ./deploy/${IMG_NAME}-quick.img" >&2
    exit 1
fi

if [[ ! -f "${BASE_IMG}" ]]; then
    echo "[quick-build] Base image not found: ${BASE_IMG}" >&2
    exit 1
fi

if [[ ! -f "${STAGE_DIR}/00-packages" ]]; then
    echo "[quick-build] Missing package list: ${STAGE_DIR}/00-packages" >&2
    exit 1
fi

mkdir -p "${DEPLOY_DIR}"

WORK_DIR="$(mktemp -d)"
ROOT_MNT="${WORK_DIR}/root"
BOOT_MNT="${WORK_DIR}/boot"
mkdir -p "${ROOT_MNT}" "${BOOT_MNT}"

cleanup() {
    set +e
    if mountpoint -q "${ROOT_MNT}"; then
        sudo umount "${ROOT_MNT}"
    fi
    if mountpoint -q "${BOOT_MNT}"; then
        sudo umount "${BOOT_MNT}"
    fi
    if [[ -n "${LOOP_DEV:-}" ]]; then
        sudo losetup -d "${LOOP_DEV}" >/dev/null 2>&1
    fi
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

cp "${BASE_IMG}" "${OUTPUT_IMG}"

echo "[quick-build] Mapping image partitions..."
LOOP_DEV="$(sudo losetup --find --show --partscan "${OUTPUT_IMG}")"
BOOT_DEV="${LOOP_DEV}p1"
ROOT_DEV="${LOOP_DEV}p2"

if [[ ! -b "${BOOT_DEV}" || ! -b "${ROOT_DEV}" ]]; then
    echo "[quick-build] Failed to map image partitions for ${OUTPUT_IMG}" >&2
    exit 1
fi

sudo mount "${ROOT_DEV}" "${ROOT_MNT}"
sudo mount "${BOOT_DEV}" "${BOOT_MNT}"

echo "[quick-build] Installing kiosk files..."
sudo install -m 755 "${STAGE_DIR}/files/slideshow.py" "${ROOT_MNT}/usr/local/bin/slideshow.py"
sudo install -m 755 "${STAGE_DIR}/files/xsession.sh" "${ROOT_MNT}/usr/local/bin/kiosk-xsession.sh"
sudo install -m 644 "${STAGE_DIR}/files/smb.conf" "${ROOT_MNT}/etc/samba/smb.conf"

sudo mkdir -p "${ROOT_MNT}/home/${FIRST_USER_NAME}/slideshow"
sudo chown 1000:1000 "${ROOT_MNT}/home/${FIRST_USER_NAME}/slideshow"
echo 'Drop your .jpg / .png / .mp4 files here.' | sudo tee "${ROOT_MNT}/home/${FIRST_USER_NAME}/slideshow/README.txt" >/dev/null
sudo chown 1000:1000 "${ROOT_MNT}/home/${FIRST_USER_NAME}/slideshow/README.txt"

sudo mkdir -p "${ROOT_MNT}/etc/systemd/system/getty@tty1.service.d"
cat <<EOF | sudo tee "${ROOT_MNT}/etc/systemd/system/getty@tty1.service.d/autologin.conf" >/dev/null
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${FIRST_USER_NAME} --noclear %I \$TERM
EOF

cat <<'EOF' | sudo tee "${ROOT_MNT}/home/${FIRST_USER_NAME}/.bash_profile" >/dev/null
[[ -f ~/.bashrc ]] && . ~/.bashrc

if [[ -z "$DISPLAY" ]] && [[ "$(tty)" == "/dev/tty1" ]]; then
    exec startx /usr/local/bin/kiosk-xsession.sh -- :0 -nocursor 2>>/tmp/kiosk-x.log
fi
EOF
sudo chown 1000:1000 "${ROOT_MNT}/home/${FIRST_USER_NAME}/.bash_profile"

if [[ -f "${BOOT_MNT}/config.txt" ]]; then
    BOOT_CONFIG="${BOOT_MNT}/config.txt"
elif [[ -f "${BOOT_MNT}/firmware/config.txt" ]]; then
    BOOT_CONFIG="${BOOT_MNT}/firmware/config.txt"
else
    BOOT_CONFIG=""
fi

if [[ -n "${BOOT_CONFIG}" ]] && ! grep -q "# kiosk display settings" "${BOOT_CONFIG}"; then
    cat <<'EOF' | sudo tee -a "${BOOT_CONFIG}" >/dev/null

# kiosk display settings
hdmi_force_hotplug=1
disable_overscan=1
hdmi_pixel_encoding=2
EOF
fi

if [[ -f "${BOOT_MNT}/cmdline.txt" ]]; then
    CMDLINE_FILE="${BOOT_MNT}/cmdline.txt"
elif [[ -f "${BOOT_MNT}/firmware/cmdline.txt" ]]; then
    CMDLINE_FILE="${BOOT_MNT}/firmware/cmdline.txt"
else
    CMDLINE_FILE=""
fi

if [[ -n "${CMDLINE_FILE}" ]] && ! grep -q "consoleblank=0" "${CMDLINE_FILE}"; then
    sudo sed -i 's/$/ consoleblank=0/' "${CMDLINE_FILE}"
fi

if [[ -n "${TARGET_HOSTNAME:-}" ]]; then
    echo "${TARGET_HOSTNAME}" | sudo tee "${ROOT_MNT}/etc/hostname" >/dev/null
    if grep -q '^127.0.1.1[[:space:]]' "${ROOT_MNT}/etc/hosts"; then
        sudo sed -i "s/^127\.0\.1\.1[[:space:]].*/127.0.1.1\t${TARGET_HOSTNAME}/" "${ROOT_MNT}/etc/hosts"
    else
        echo "127.0.1.1 ${TARGET_HOSTNAME}" | sudo tee -a "${ROOT_MNT}/etc/hosts" >/dev/null
    fi
fi

if command -v openssl >/dev/null 2>&1; then
    PASS_HASH="$(openssl passwd -6 "${FIRST_USER_PASS}")"
    echo "${FIRST_USER_NAME}:${PASS_HASH}" | sudo tee "${BOOT_MNT}/userconf.txt" >/dev/null
else
    echo "[quick-build] Warning: openssl not found, userconf.txt not written." >&2
fi
sudo touch "${BOOT_MNT}/ssh"

PACKAGE_LIST="$(sed -E 's/#.*$//' "${STAGE_DIR}/00-packages" | xargs)"

cat <<EOF | sudo tee "${ROOT_MNT}/usr/local/sbin/kiosk-firstboot.sh" >/dev/null
#!/bin/bash
set -euo pipefail

if [[ -f /var/lib/kiosk-firstboot.done ]]; then
    exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ${PACKAGE_LIST}

systemctl enable smbd nmbd || true

touch /var/lib/kiosk-firstboot.done
systemctl disable kiosk-firstboot.service || true
rm -f /etc/systemd/system/multi-user.target.wants/kiosk-firstboot.service
EOF

sudo chmod 755 "${ROOT_MNT}/usr/local/sbin/kiosk-firstboot.sh"

cat <<'EOF' | sudo tee "${ROOT_MNT}/etc/systemd/system/kiosk-firstboot.service" >/dev/null
[Unit]
Description=Kiosk first boot package setup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/kiosk-firstboot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo mkdir -p "${ROOT_MNT}/etc/systemd/system/multi-user.target.wants"
sudo ln -sf /etc/systemd/system/kiosk-firstboot.service "${ROOT_MNT}/etc/systemd/system/multi-user.target.wants/kiosk-firstboot.service"

echo "[quick-build] Finalizing image..."
sudo sync
sudo umount "${ROOT_MNT}"
sudo umount "${BOOT_MNT}"
sudo losetup -d "${LOOP_DEV}"
LOOP_DEV=""

echo "[quick-build] Done: ${OUTPUT_IMG}"
echo "[quick-build] Note: first boot installs kiosk packages; allow extra time after initial boot."
