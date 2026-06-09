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

# ── Configuration ────────────────────────────────────────────────────────────
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
# ─────────────────────────────────────────────────────────────────────────────

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