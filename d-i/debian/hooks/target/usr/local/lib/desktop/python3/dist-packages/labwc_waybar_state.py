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
            or stat.S_IMODE(info.st_mode) != 0o700 or info.st_nlink != 1):
        raise ValueError("unsafe Waybar state directory")
    return path


def active(button: str) -> bool:
    """Return whether one validated button owns at least one live marker."""
    if button not in BUTTONS:
        raise ValueError("invalid Waybar state button")
    try:
        directory = state_directory()
    except (OSError, ValueError):
        return False
    if directory is None:
        return False
    try:
        for index, path in enumerate(directory.iterdir()):
            if index >= 256:
                break
            if not path.name.startswith(button + "-") or not path.name.endswith(".json"):
                continue
            try:
                info = path.lstat()
                if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                        or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600):
                    continue
                with path.open("r", encoding="ascii") as stream:
                    data = json.load(stream)
                if (isinstance(data, dict) and data.get("version") == 1
                        and data.get("button") == button and data.get("uid") == os.getuid()
                        and ID_RE.fullmatch(str(data.get("id", "")))):
                    return True
            except (OSError, ValueError, TypeError, json.JSONDecodeError):
                continue
    except OSError:
        return False
    return False
