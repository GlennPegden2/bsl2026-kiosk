# BSL2026 Kiosk - Raspberry Pi Slideshow Setup

This project now targets stock Raspberry Pi OS installs.

New workflow:
1. Flash an off-the-shelf Raspberry Pi OS Lite image with Raspberry Pi Imager.
2. Boot the Pi and connect it to the internet.
3. Run one setup command from this repo to apply kiosk and OS-level changes.

## Viability

Yes, this approach is viable and usually much faster to iterate.

Benefits:
- No long pi-gen image build cycle.
- Faster testing on real hardware.
- Simple rollback: reflash stock image and rerun setup.

Trade-off:
- Setup now happens on-device during installation instead of at image build time.

## Quick Start (on the Pi)

Run this directly on the Pi after first boot:

```bash
curl -fsSL https://raw.githubusercontent.com/GlennPegden2/bsl2026-kiosk/main/install.sh | sudo bash
```

This bootstrap command does not require `git` or a local clone of the repository.
It downloads the installer files it needs directly from GitHub.

Optional hostname override:

```bash
curl -fsSL https://raw.githubusercontent.com/GlennPegden2/bsl2026-kiosk/main/install.sh | sudo bash -s -- --hostname kiosk
```

The installer will:
- install kiosk packages
- install slideshow and X session scripts
- configure Samba share at `\\hostname\slideshow`
- create a FAT boot-partition import folder for easy Windows updates
- enable tty1 autologin kiosk launch
- apply HDMI and console blanking tweaks

Reboot when setup finishes.

## Reset / Uninstall (for fast re-testing)

Run on the Pi to remove kiosk configuration:

```bash
curl -fsSL https://raw.githubusercontent.com/GlennPegden2/bsl2026-kiosk/main/reset.sh | sudo bash
```

Like the installer, the reset bootstrap downloads the required reset files directly
from GitHub and does not require a local repo checkout.

Optional flags:

```bash
# Also purge kiosk packages installed by this project
curl -fsSL https://raw.githubusercontent.com/GlennPegden2/bsl2026-kiosk/main/reset.sh | sudo bash -s -- --purge-packages

# Also remove the slideshow media folder
curl -fsSL https://raw.githubusercontent.com/GlennPegden2/bsl2026-kiosk/main/reset.sh | sudo bash -s -- --remove-media
```

Then reboot.

## What It Does

| Feature | Detail |
|---|---|
| Auto-start | Slideshow launches automatically on boot |
| Images | .jpg .jpeg .png .bmp .gif |
| Video | .mp4 .mkv .avi .mov .webm .m4v |
| Loop | Re-scans media folder every cycle |
| SMB share | `\\kiosk\slideshow` for drag and drop updates |
| HDMI | Forced on at boot |

## Media Updates

Copy files into the network share:

| Platform | Address |
|---|---|
| Windows Explorer | `\\kiosk\slideshow` |
| macOS Finder | `smb://kiosk/slideshow` |
| Linux | `smb://kiosk/slideshow` |

Files appear in the next slideshow scan cycle.

### FAT partition updates (SD card in a Windows PC)

When the SD card is inserted directly into a Windows machine, place media in:

- `slideshow` folder on the FAT boot partition

At loop start, the kiosk imports supported files from that FAT folder into its
runtime media folder automatically.

### Auto-download from repo

At loop start, the kiosk also checks this repository for new media files in:

- `kiosk/repo-media/`

If a file in that folder does not already exist on the device, it is
downloaded automatically.

Files that were previously synced from the repo are also updated when the repo
version changes.

Notes:
- only supported slideshow file extensions are downloaded
- checks are rate-limited in the player to avoid GitHub API limits

## Customization

Edit source before running installer:
- `kiosk/files/slideshow.py`
- `kiosk/files/xsession.sh`
- `kiosk/files/smb.conf`

Or edit on-device after install:

```bash
sudo nano /usr/local/bin/slideshow.py
sudo reboot
```

## Repository Layout

```
bsl2026-kiosk/
   install.sh                 # main entrypoint for curl bootstrap
   reset.sh                   # main entrypoint for rollback/reset
   scripts/
      install-kiosk.sh         # post-install configurator for stock Raspberry Pi OS
      reset-kiosk.sh           # removes kiosk configuration (optional package purge)
   kiosk/
      packages.txt             # apt packages installed by bootstrap
      files/
         slideshow.py           # Python slideshow app
         xsession.sh            # X startup script
         smb.conf               # Samba config template
      repo-media/              # optional repo-hosted media auto-download source
   legacy/
      image-build/             # archived pi-gen and custom image build workflow
```

## Legacy Custom Image Build

The previous custom image build pipeline has been moved to:

- `legacy/image-build/`

That folder is retained for reference only.
