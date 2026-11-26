"""Read-only NVIDIA node identity shared by policy preparation and the worker."""
from __future__ import annotations

import os
from pathlib import Path
import re
import stat


def same_device_nodes(expected: object, actual: object) -> bool:
    """Compare NVIDIA policy identities by path and device number.

    Driver node recreation legitimately changes ``st_ino`` (and sometimes the
    containing filesystem device) while the character major/minor interface
    remains the same.  The AppArmor include and ``/dev/char`` aliases authorize
    that stable interface, so inode churn must not invalidate a prepared lease.
    Malformed records still fail closed.
    """
    def identities(value: object) -> list[tuple[str, int]] | None:
        if not isinstance(value, list):
            return None
        result: list[tuple[str, int]] = []
        for row in value:
            if (not isinstance(row, list) or len(row) != 4
                    or not isinstance(row[0], str) or not row[0]
                    or type(row[3]) is not int or row[3] < 0):
                return None
            result.append((row[0], row[3]))
        return sorted(result)

    expected_identities = identities(expected)
    actual_identities = identities(actual)
    return (expected_identities is not None and actual_identities is not None
            and expected_identities == actual_identities)


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
