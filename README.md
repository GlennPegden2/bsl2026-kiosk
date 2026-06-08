# BSL2026 Kiosk — Raspberry Pi Slideshow Image

A bootable Raspberry Pi OS image that automatically plays images and videos
from a folder accessible via an SMB (Windows network) share.  Designed to run
headless on a Pi Zero / Pi Zero 2 W connected to a TV via HDMI, with no
keyboard required after first flash.

---

## What it does

| Feature | Detail |
|---|---|
| **Auto-start** | Slideshow launches automatically on boot, no login needed |
| **Images** | `.jpg` `.jpeg` `.png` `.bmp` `.gif` — displayed for 10 s each |
| **Video** | `.mp4` `.mkv` `.avi` `.mov` `.webm` `.m4v` — played to completion |
| **Loop** | Repeats indefinitely; re-scans folder on each pass (picks up new files) |
| **SMB share** | `\\kiosk\slideshow` — drag & drop from any Windows/Mac machine |
| **HDMI** | Forced on even if TV is off at boot |

---

## Build requirements

The image is built with **[pi-gen](https://github.com/RPi-Distro/pi-gen)** on Linux.

### Option A — Linux or WSL2 (native)

```bash
sudo apt-get install -y coreutils quilt parted qemu-user-static debootstrap \
    zerofree zip dosfstools libarchive-tools libcap2-bin grep rsync xz-utils \
    file git curl bc

git clone https://github.com/GlennPegden2/bsl2026-kiosk.git
cd bsl2026-kiosk
chmod +x build.sh
./build.sh
```

### Option B — Docker (recommended for Windows)

Requires Docker Desktop with the WSL2 backend enabled.

```bash
git clone https://github.com/GlennPegden2/bsl2026-kiosk.git
cd bsl2026-kiosk
chmod +x build.sh
./build.sh --docker
```

The finished `.img` file lands in `pi-gen/deploy/`.

---

## Flashing the image

1. Open **[Raspberry Pi Imager](https://www.raspberrypi.com/software/)**
2. Choose **"Use custom"** and select the `.img` file
3. Select your SD card
4. Flash — **do not** apply extra OS customisation settings (the image already
   has everything configured)

---

## First boot

1. Insert SD card into the Pi, connect HDMI cable to TV, then power on
2. First boot takes ~60 seconds (filesystem expansion)
3. The slideshow folder is empty so the screen will be blank — connect to your
   network and copy media files (see below)
4. The slideshow starts on the **next loop cycle** (~30 s after files appear)

---

## Adding / updating media files

When the Pi is on the same network as your computer:

| Platform | Address |
|---|---|
| Windows Explorer | `\\kiosk\slideshow` |
| macOS Finder | `smb://kiosk/slideshow` |
| Linux | `smb://kiosk/slideshow` |

No password is required — the share is open for guest access.

Drag and drop your `.jpg` / `.png` / `.mp4` files.  Files are picked up on the
next loop cycle without rebooting.

> **Tip:** Files are displayed in alphabetical order.  Prefix filenames with
> numbers (`01-welcome.jpg`, `02-product.mp4`) to control the sequence.

---

## Customising the slideshow

Edit `stage-kiosk/files/slideshow.py` and change the values at the top of the
file before building:

```python
# How long (seconds) each image is displayed before moving to the next
IMAGE_DURATION = 10

# How long (seconds) to wait before re-scanning when the folder is empty
RETRY_DELAY = 30
```

If you want to change settings **on an already-flashed Pi** (without
rebuilding), SSH in and edit `/usr/local/bin/slideshow.py` directly:

```bash
ssh pi@kiosk
sudo nano /usr/local/bin/slideshow.py
sudo reboot
```

---

## Default credentials

| | Value |
|---|---|
| Hostname | `kiosk` |
| Username | `pi` |
| Password | `raspberry` |
| SSH | Enabled |

> **⚠️ Change the default password** before deploying at a public event:
> `passwd` over SSH, or edit `FIRST_USER_PASS` in `config` before building.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Black screen on boot | Check HDMI cable; TV may need to be switched to the correct input |
| No picture after adding files | Wait 30 s for the loop to re-scan; check filenames are a supported format |
| SMB share not visible | Ensure Pi and PC are on the same subnet; try `\\<ip-address>\slideshow` |
| Slideshow crashed | SSH in and check `journalctl -u getty@tty1 -f` and `/tmp/kiosk-x.log` |

---

## Project layout

```
bsl2026-kiosk/
  config                     # pi-gen build settings (hostname, locale, password)
  build.sh                   # build script (native Linux or Docker)
  stage-kiosk/
    EXPORT_IMAGE             # tells pi-gen to export the image after this stage
    00-packages              # apt packages to install
    01-run.sh                # stage setup (copies files, enables services)
    files/
      slideshow.py           # Python kiosk application
      xsession.sh            # minimal X session launcher
      smb.conf               # Samba share configuration
```
