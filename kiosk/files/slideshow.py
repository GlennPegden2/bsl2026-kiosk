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
import json
import shutil
from pathlib import Path
from typing import Optional
from urllib.error import URLError, HTTPError
from urllib.request import Request, urlopen

# â”€â”€ Configuration â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# Location of the slideshow media folder (also the Samba share target)
MEDIA_DIR = Path("/home/pi/slideshow")

# Optional import folder on the FAT boot partition.
FAT_IMPORT_DIR = Path("/boot/firmware/slideshow")

# GitHub API endpoint for repository media folder.
REPO_MEDIA_API_URL = "https://api.github.com/repos/GlennPegden2/bsl2026-kiosk/contents/kiosk/repo-media"

# Minimum seconds between repo checks to avoid API rate limits.
REPO_SYNC_MIN_INTERVAL = 900

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
_last_repo_sync_ts = 0.0


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


def _is_supported_media(path: Path) -> bool:
    return path.suffix.lower() in (IMAGE_EXTS | VIDEO_EXTS)


def _copy_if_missing_or_changed(src: Path, dst: Path) -> bool:
    """Copy src to dst when dst is missing or differs by size/mtime."""
    if not dst.exists():
        shutil.copy2(src, dst)
        return True

    src_stat = src.stat()
    dst_stat = dst.stat()
    if src_stat.st_size != dst_stat.st_size or int(src_stat.st_mtime) > int(dst_stat.st_mtime):
        shutil.copy2(src, dst)
        return True

    return False


def sync_from_fat_import_dir() -> None:
    """Import supported media files from FAT boot partition folder."""
    if not FAT_IMPORT_DIR.is_dir():
        return

    imported = 0
    for src in sorted(FAT_IMPORT_DIR.iterdir()):
        if not src.is_file() or not _is_supported_media(src):
            continue
        dst = MEDIA_DIR / src.name
        try:
            if _copy_if_missing_or_changed(src, dst):
                imported += 1
        except Exception as exc:
            log.warning("Failed FAT import for %s: %s", src.name, exc)

    if imported:
        log.info("Imported %d file(s) from FAT folder: %s", imported, FAT_IMPORT_DIR)


def _list_repo_media() -> list[tuple[str, str]]:
    """Return list of (name, download_url) for media files in repo folder."""
    req = Request(REPO_MEDIA_API_URL, headers={"User-Agent": "bsl2026-kiosk"})
    with urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode("utf-8"))

    results = []
    for item in data:
        if item.get("type") != "file":
            continue
        name = item.get("name", "")
        download_url = item.get("download_url", "")
        if not name or not download_url:
            continue
        if Path(name).suffix.lower() not in (IMAGE_EXTS | VIDEO_EXTS):
            continue
        results.append((name, download_url))
    return results


def sync_missing_from_repo() -> None:
    """Download any missing media files from repo folder into MEDIA_DIR."""
    global _last_repo_sync_ts

    now = time.time()
    if now - _last_repo_sync_ts < REPO_SYNC_MIN_INTERVAL:
        return
    _last_repo_sync_ts = now

    try:
        repo_files = _list_repo_media()
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
        log.info("Repo sync skipped (%s)", exc)
        return
    except Exception as exc:
        log.warning("Repo sync failed: %s", exc)
        return

    downloaded = 0
    for name, url in repo_files:
        dst = MEDIA_DIR / name
        if dst.exists():
            continue

        tmp = MEDIA_DIR / f".{name}.download"
        try:
            req = Request(url, headers={"User-Agent": "bsl2026-kiosk"})
            with urlopen(req, timeout=20) as resp, tmp.open("wb") as out_f:
                shutil.copyfileobj(resp, out_f)
            tmp.replace(dst)
            downloaded += 1
        except Exception as exc:
            log.warning("Failed repo download for %s: %s", name, exc)
            if tmp.exists():
                tmp.unlink(missing_ok=True)

    if downloaded:
        log.info("Downloaded %d new file(s) from repository media.", downloaded)


def sync_media_sources() -> None:
    """Refresh local media from external sources at loop start."""
    MEDIA_DIR.mkdir(parents=True, exist_ok=True)
    sync_from_fat_import_dir()
    sync_missing_from_repo()


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
                "--zoom", "fill",
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
    log.info("FAT import dir: %s", FAT_IMPORT_DIR)

    while True:
        sync_media_sources()
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
