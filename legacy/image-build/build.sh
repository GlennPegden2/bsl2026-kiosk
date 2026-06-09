#!/bin/bash
# Build the BSL2026 kiosk SD card image using pi-gen.
#
# Prerequisites (Linux / WSL2):
#   sudo apt-get install -y coreutils quilt parted qemu-user-static debootstrap \
#       zerofree zip dosfstools libarchive-tools libcap2-bin grep rsync xz-utils \
#       file git curl bc
#
# OR use Docker (recommended for Windows / macOS):
#   Requires Docker Desktop with WSL2 backend.  Run this script with --docker.
#
# Usage:
#   ./build.sh           # native Linux build
#   ./build.sh --docker  # Docker-based build (cross-platform)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIGEN_DIR="${SCRIPT_DIR}/pi-gen"
DOCKER_WRAPPER="${SCRIPT_DIR}/docker-wrapper.sh"

run_with_optional_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        echo "[build] Error: root privileges required, but sudo is not available." >&2
        echo "[build] Re-run as root or install sudo." >&2
        exit 1
    fi
}

# â”€â”€ Clone pi-gen if not present â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
if [ ! -d "${PIGEN_DIR}" ]; then
    echo "[build] Cloning pi-gen..."
    git clone --depth 1 https://github.com/RPi-Distro/pi-gen.git "${PIGEN_DIR}"
fi

# â”€â”€ Copy project files into pi-gen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
echo "[build] Copying config and stage..."
cp "${SCRIPT_DIR}/config" "${PIGEN_DIR}/config"

# Remove any previous copy of our stage, then copy fresh
rm -rf "${PIGEN_DIR}/stage-kiosk"
cp -r "${SCRIPT_DIR}/stage-kiosk" "${PIGEN_DIR}/stage-kiosk"

# Skip the desktop / full stages â€” we only want Lite + our kiosk layer
for stage in stage3 stage4 stage5; do
    touch "${PIGEN_DIR}/${stage}/SKIP"
done
# Also skip image export from stage4/5 (they're skipped anyway, but belt+braces)
for stage in stage4 stage5; do
    touch "${PIGEN_DIR}/${stage}/SKIP_IMAGES"
done
# Disable stage2 image export so only stage-kiosk EXPORT_IMAGE is used.
touch "${PIGEN_DIR}/stage2/SKIP_IMAGES"

# â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
cd "${PIGEN_DIR}"

if [[ "${1:-}" == "--docker" ]]; then
    echo "[build] Starting Docker build..."
    chmod +x "${DOCKER_WRAPPER}" || true
    if command -v docker >/dev/null 2>&1; then
        BASE_IMAGE=i386/debian:bookworm SKIP_BINFMT_CHECK=1 DOCKER="${DOCKER_WRAPPER}" bash build-docker.sh
    else
        run_with_optional_sudo env "PATH=${PATH}" BASE_IMAGE=i386/debian:bookworm SKIP_BINFMT_CHECK=1 DOCKER="${DOCKER_WRAPPER}" bash build-docker.sh
    fi
else
    echo "[build] Starting native build (requires root)..."
    run_with_optional_sudo bash build.sh
fi

echo
echo "[build] Done. Image is in: ${PIGEN_DIR}/deploy/"
echo "Flash with: sudo dd if=deploy/*.img of=/dev/sdX bs=4M status=progress"
echo "Or use the Raspberry Pi Imager (Custom image option)."
