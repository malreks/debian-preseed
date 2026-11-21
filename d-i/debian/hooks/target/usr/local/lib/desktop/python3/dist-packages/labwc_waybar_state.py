"""Read-only validation of the per-launch Waybar state markers."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import stat


BUTTONS = frozenset({
    "cpu", "memory", "notifications", "power", "storage", "taskview",
    "tomat", "wayscriber",
})
ID_RE = re.compile(r"[0-9a-f]{32}\Z")
STATE_NAME = "labwc-waybar-state"


def _identity(value: os.stat_result) -> tuple:
    return (value.st_dev, value.st_ino, value.st_uid, value.st_mode,
            value.st_nlink, value.st_size, value.st_mtime_ns, value.st_ctime_ns)


def _runtime() -> Path:
    uid = os.getuid()
    if uid == 0 or os.geteuid() != uid or os.environ.get("LABWC_SESSION_OWNER") != "desktop":
        raise ValueError("Waybar state requires the ordinary desktop account")
    path = Path("__INSTALLER_PATH_DIR_RUN_USER__") / str(uid)
    info = path.lstat()
    if (not stat.S_ISDIR(info.st_mode) or info.st_uid != uid
            or stat.S_IMODE(info.st_mode) != 0o700):
        raise ValueError("unsafe desktop runtime")
    return path


def state_directory() -> Path | None:
    """Return the existing validated marker directory, without creating it."""
    path = _runtime() / STATE_NAME
    try:
        info = path.lstat()
    except FileNotFoundError:
        return None
    if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid()
            or stat.S_IMODE(info.st_mode) != 0o700 or info.st_nlink < 1):
        raise ValueError("unsafe Waybar state directory")
    return path


def active(button: str) -> bool:
    """Read a bounded marker owned and cleaned by the application service."""
    if button not in BUTTONS:
        raise ValueError("invalid Waybar state button")
    try:
        directory = state_directory()
    except (OSError, ValueError):
        return False
    if directory is None:
        return False
    descriptor = -1
    try:
        descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
        parent = os.fstat(descriptor)
        if parent.st_uid != os.getuid() or stat.S_IMODE(parent.st_mode) != 0o700:
            return False
        with os.scandir(descriptor) as entries:
            for index, entry in enumerate(entries):
                if index >= 256:
                    break
                if not entry.name.startswith(button + "-") or not entry.name.endswith(".json"):
                    continue
                try:
                    marker = os.open(entry.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
                                     dir_fd=descriptor)
                    with os.fdopen(marker, "rb") as stream:
                        info = os.fstat(stream.fileno())
                        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                                or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600
                                or info.st_size > 4096):
                            continue
                        raw = stream.read(4097)
                        after = os.fstat(stream.fileno())
                    current = os.stat(entry.name, dir_fd=descriptor, follow_symlinks=False)
                    # Neither replacement nor an in-place writer can turn a
                    # metadata check into authority over different bytes.
                    if (len(raw) != info.st_size or _identity(info) != _identity(after)
                            or _identity(info) != _identity(current)):
                        continue
                    data = json.loads(raw.decode("ascii"))
                    if (isinstance(data, dict) and type(data.get("version")) is int and data["version"] == 1
                            and data.get("button") == button and type(data.get("uid")) is int
                            and data["uid"] == os.getuid() and isinstance(data.get("id"), str)
                            and ID_RE.fullmatch(data["id"]) and entry.name == f"{button}-{data['id']}.json"):
                        return True
                except (OSError, ValueError, TypeError):
                    continue
    except OSError:
        return False
    finally:
        if descriptor >= 0:
            os.close(descriptor)
    return False
