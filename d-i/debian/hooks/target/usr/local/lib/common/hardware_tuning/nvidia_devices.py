"""Read-only NVIDIA node identity shared by policy preparation and the worker."""
from __future__ import annotations

import os
from pathlib import Path
import re
import stat


def snapshot(dev: Path = Path("__INSTALLER_PATH_DIR_DEV__")) -> list[list]:
    descriptors = []
    result = []
    try:
        for directory, pattern, limit in (
            (dev, r"nvidia(?:[0-9]+|ctl|-modeset|-uvm|-uvm-tools)", 4096),
            (dev / "nvidia-caps", r"nvidia-cap[0-9]+", 256),
        ):
            try:
                fd = os.open(directory.name if descriptors else directory,
                             os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                             dir_fd=descriptors[0] if descriptors else None)
            except FileNotFoundError:
                if not descriptors:
                    raise
                continue
            descriptors.append(fd)
            info = os.fstat(fd)
            if info.st_uid != 0 or info.st_mode & 0o022:
                raise ValueError("untrusted NVIDIA device directory")
            with os.scandir(fd) as entries:
                for count, entry in enumerate(entries, 1):
                    if count > limit:
                        raise ValueError("NVIDIA node inventory exceeds limit")
                    if re.fullmatch(pattern, entry.name) is None:
                        continue
                    info = entry.stat(follow_symlinks=False)
                    if not stat.S_ISCHR(info.st_mode) or info.st_uid != 0:
                        raise ValueError("untrusted NVIDIA character device")
                    result.append([str(directory / entry.name), info.st_dev, info.st_ino, info.st_rdev])
                    if len(result) > 256:
                        raise ValueError("too many NVIDIA character devices")
        return sorted(result)
    finally:
        for fd in reversed(descriptors):
            os.close(fd)
