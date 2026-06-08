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

# ── Clone pi-gen if not present ───────────────────────────────────────────────
if [ ! -d "${PIGEN_DIR}" ]; then
    echo "[build] Cloning pi-gen..."
    git clone --depth 1 https://github.com/RPi-Distro/pi-gen.git "${PIGEN_DIR}"
fi

# ── Copy project files into pi-gen ────────────────────────────────────────────
echo "[build] Copying config and stage..."
cp "${SCRIPT_DIR}/config" "${PIGEN_DIR}/config"

# Remove any previous copy of our stage, then copy fresh
rm -rf "${PIGEN_DIR}/stage-kiosk"
cp -r "${SCRIPT_DIR}/stage-kiosk" "${PIGEN_DIR}/stage-kiosk"

# Skip the desktop / full stages — we only want Lite + our kiosk layer
for stage in stage3 stage4 stage5; do
    touch "${PIGEN_DIR}/${stage}/SKIP"
done
# Also skip image export from stage4/5 (they're skipped anyway, but belt+braces)
for stage in stage4 stage5; do
    touch "${PIGEN_DIR}/${stage}/SKIP_IMAGES"
done

# ── Build ─────────────────────────────────────────────────────────────────────
cd "${PIGEN_DIR}"

if [[ "${1:-}" == "--docker" ]]; then
    echo "[build] Starting Docker build..."
    sudo bash build-docker.sh
else
    echo "[build] Starting native build (requires root)..."
    sudo bash build.sh
fi

echo
echo "[build] Done. Image is in: ${PIGEN_DIR}/deploy/"
echo "Flash with: sudo dd if=deploy/*.img of=/dev/sdX bs=4M status=progress"
echo "Or use the Raspberry Pi Imager (Custom image option)."
