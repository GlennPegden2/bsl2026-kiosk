#!/bin/bash -e
# Stage: kiosk
# Sets up the auto-starting slideshow, Samba share and HDMI settings.

# ── Install application files ──────────────────────────────────────────────────
install -m 755 files/slideshow.py   "${ROOTFS_DIR}/usr/local/bin/slideshow.py"
install -m 755 files/xsession.sh    "${ROOTFS_DIR}/usr/local/bin/kiosk-xsession.sh"
install -m 644 files/smb.conf       "${ROOTFS_DIR}/etc/samba/smb.conf"

# ── Create slideshow media directory ──────────────────────────────────────────
mkdir -p "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/slideshow"
chown 1000:1000 "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/slideshow"

# Drop a placeholder so the folder is visible over SMB immediately
install -m 644 /dev/null \
    "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/slideshow/README.txt"
echo 'Drop your .jpg / .png / .mp4 files here.' > \
    "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/slideshow/README.txt"

# ── Autologin to tty1 as pi ───────────────────────────────────────────────────
mkdir -p "${ROOTFS_DIR}/etc/systemd/system/getty@tty1.service.d"
cat > "${ROOTFS_DIR}/etc/systemd/system/getty@tty1.service.d/autologin.conf" << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${FIRST_USER_NAME} --noclear %I \$TERM
EOF

# ── .bash_profile: start X on tty1 login ─────────────────────────────────────
cat > "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/.bash_profile" << 'EOF'
[[ -f ~/.bashrc ]] && . ~/.bashrc

# Auto-start the kiosk X session on the first virtual terminal
if [[ -z "$DISPLAY" ]] && [[ "$(tty)" == "/dev/tty1" ]]; then
    exec startx /usr/local/bin/kiosk-xsession.sh -- :0 -nocursor 2>>/tmp/kiosk-x.log
fi
EOF
chown 1000:1000 "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/.bash_profile"

# ── Enable Samba ──────────────────────────────────────────────────────────────
on_chroot << EOF
systemctl enable smbd nmbd
EOF

# ── HDMI: force output on, disable overscan, no blanking ──────────────────────
# Locate the boot config (path differs between Bullseye and Bookworm)
if   [ -f "${ROOTFS_DIR}/boot/firmware/config.txt" ]; then
    BOOT_CONFIG="${ROOTFS_DIR}/boot/firmware/config.txt"
elif [ -f "${ROOTFS_DIR}/boot/config.txt" ]; then
    BOOT_CONFIG="${ROOTFS_DIR}/boot/config.txt"
fi

if [ -n "${BOOT_CONFIG:-}" ]; then
    cat >> "${BOOT_CONFIG}" << 'EOF'

# ── Kiosk display settings ────────────────────────────────────────────────────
# Force HDMI output even when no display is detected at boot
hdmi_force_hotplug=1
# Disable black border compensation (overscan)
disable_overscan=1
# Ensure HDMI outputs full-range colour for TV displays
hdmi_pixel_encoding=2
EOF
fi

# ── Disable console screen blanking (kernel-level) ────────────────────────────
# Append to kernel command line
if   [ -f "${ROOTFS_DIR}/boot/firmware/cmdline.txt" ]; then
    CMDLINE="${ROOTFS_DIR}/boot/firmware/cmdline.txt"
elif [ -f "${ROOTFS_DIR}/boot/cmdline.txt" ]; then
    CMDLINE="${ROOTFS_DIR}/boot/cmdline.txt"
fi

if [ -n "${CMDLINE:-}" ]; then
    # consoleblank=0 disables the kernel console blank timer
    sed -i 's/$/ consoleblank=0/' "${CMDLINE}"
fi
