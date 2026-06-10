#!/usr/bin/env python3
"""BSL2026 Kiosk Slideshow

Loops through all image and video files in MEDIA_DIR indefinitely.
Dropped into /home/pi/slideshow (accessible via SMB share).

Supported formats
  Images : .jpg  .jpeg  .png  .bmp  .gif
  Video  : .mp4  .mkv  .avi  .mov  .webm  .m4v
"""

import logging
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Optional

# â”€â”€ Configuration â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# Location of the slideshow media folder (also the Samba share target)
MEDIA_DIR = Path("/home/pi/slideshow")

# How long (seconds) each image is displayed before moving to the next
IMAGE_DURATION = 10

# How long (seconds) to wait before re-scanning when the folder is empty
RETRY_DELAY = 30

# Safety cap: maximum seconds allowed for a single video before it is skipped
VIDEO_TIMEOUT = 3600  # 1 hour

IMAGE_EXTS = frozenset({".jpg", ".jpeg", ".png", ".bmp", ".gif"})
VIDEO_EXTS = frozenset({".mp4", ".mkv", ".avi", ".mov", ".webm", ".m4v"})
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger(__name__)

# Module-level reference so signal handler can clean up the active child process
_current_proc: Optional[subprocess.Popen] = None


def _handle_signal(signum, frame) -> None:
    """Terminate any running child process cleanly on SIGTERM / SIGINT."""
    if _current_proc and _current_proc.poll() is None:
        _current_proc.terminate()
    sys.exit(0)


signal.signal(signal.SIGTERM, _handle_signal)
signal.signal(signal.SIGINT, _handle_signal)


def _display_env() -> dict:
    """Build environment dict with DISPLAY set (inherits from env or defaults to :0)."""
    env = os.environ.copy()
    env.setdefault("DISPLAY", ":0")
    return env


def list_media() -> list:
    """Return a sorted list of supported media files from MEDIA_DIR."""
    if not MEDIA_DIR.is_dir():
        return []
    supported = IMAGE_EXTS | VIDEO_EXTS
    return sorted(
        f for f in MEDIA_DIR.iterdir()
        if f.is_file() and f.suffix.lower() in supported
    )


def show_image(path: Path) -> None:
    """Display a single image for IMAGE_DURATION seconds using feh."""
    global _current_proc
    log.info("Image  (%ds): %s", IMAGE_DURATION, path.name)
    try:
        _current_proc = subprocess.Popen(
            [
                "feh",
                "--fullscreen",
                "--hide-pointer",
                "--no-menus",
                "--zoom", "max",
                str(path),
            ],
            env=_display_env(),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        # feh stays open until killed; sleep for the configured duration
        time.sleep(IMAGE_DURATION)
    except Exception as exc:
        log.error("feh failed for %s: %s", path.name, exc)
    finally:
        if _current_proc and _current_proc.poll() is None:
            _current_proc.terminate()
            try:
                _current_proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                _current_proc.kill()
        _current_proc = None


def play_video(path: Path) -> None:
    """Play a video file to completion (or until VIDEO_TIMEOUT) using mpv."""
    global _current_proc
    log.info("Video: %s", path.name)
    try:
        _current_proc = subprocess.Popen(
            [
                "mpv",
                "--fullscreen",
                "--no-terminal",
                "--no-input-default-bindings",
                "--cursor-autohide=always",
                "--really-quiet",
                str(path),
            ],
            env=_display_env(),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        _current_proc.wait(timeout=VIDEO_TIMEOUT)
    except subprocess.TimeoutExpired:
        log.warning("Video exceeded timeout (%ds), skipping: %s", VIDEO_TIMEOUT, path.name)
        _current_proc.kill()
        _current_proc.wait()
    except Exception as exc:
        log.error("mpv failed for %s: %s", path.name, exc)
    finally:
        if _current_proc and _current_proc.poll() is None:
            _current_proc.terminate()
            try:
                _current_proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                _current_proc.kill()
        _current_proc = None


def main() -> None:
    log.info("Kiosk slideshow starting. Media dir: %s", MEDIA_DIR)

    while True:
        files = list_media()

        if not files:
            log.warning(
                "No media files found in %s â€” retrying in %ds",
                MEDIA_DIR, RETRY_DELAY,
            )
            time.sleep(RETRY_DELAY)
            continue

        log.info("Found %d file(s). Starting loop.", len(files))

        for path in files:
            ext = path.suffix.lower()
            if ext in IMAGE_EXTS:
                show_image(path)
            elif ext in VIDEO_EXTS:
                play_video(path)
        # After one full pass, re-scan so newly added files are picked up


if __name__ == "__main__":
    main()
