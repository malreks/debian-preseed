#!/usr/bin/python3
"""Installation-only publication of rendered payload defaults, never a runtime helper.

The interpreter spelling is Debian's package interface. All state and account
paths arrive through explicit installer arguments, not installed skeletons.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import pwd
import stat
import sys
import time

FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
DEADLINE = time.monotonic() + 60
MAX_MEMBERS = 8192
MAX_BYTES = 128 * 1024 * 1024


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)
    if time.monotonic() > DEADLINE:
        raise TimeoutError('primary defaults operation deadline exceeded')


def open_source(path: Path) -> int:
    require(path.is_absolute() and path.resolve(strict=True) == path, 'indirect payload defaults root')
    for parent in (path, *path.parents):
        info = parent.stat()
        require(info.st_uid == info.st_gid == 0 and not info.st_mode & 0o022,
                'payload defaults ancestry is not root controlled')
    descriptor = os.open(path, FLAGS)
    try:
        require(stat.S_IMODE(os.fstat(descriptor).st_mode) == 0o700, 'payload defaults root is not private')
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def entries(directory: int):
    names = []
    with os.scandir(directory) as iterator:
        for entry in iterator:
            require(len(names) < MAX_MEMBERS, 'too many payload defaults in one directory')
            require(entry.name not in ('.', '..'), 'invalid payload default name')
            names.append(entry.name)
    return sorted(names)


def identity(info: os.stat_result) -> tuple[int, ...]:
    return (info.st_dev, info.st_ino, info.st_uid, info.st_gid, info.st_mode,
            info.st_nlink, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def publish(source: int, destination: int, account, budget: list[int], depth: int = 0,
            selected: tuple[str, ...] | None = None) -> None:
    require(depth <= 32, 'payload defaults nesting exceeds the supported depth')
    found = selected is None
    for name in entries(source):
        if selected is not None and name != selected[0]:
            continue
        found = True
        budget[0] += 1
        require(budget[0] <= MAX_MEMBERS, 'too many primary payload defaults')
        info = os.stat(name, dir_fd=source, follow_symlinks=False)
        require(info.st_uid == info.st_gid == 0 and not info.st_mode & 0o022,
                'untrusted payload default metadata')
        if stat.S_ISDIR(info.st_mode):
            require(selected is None or len(selected) > 1,
                    'selected payload default must name a regular file')
            input_dir = os.open(name, FLAGS, dir_fd=source)
            try:
                require(identity(os.fstat(input_dir)) == identity(info), 'payload directory identity changed')
                try:
                    os.mkdir(name, 0o700, dir_fd=destination)
                except FileExistsError:
                    pass
                output_dir = os.open(name, FLAGS, dir_fd=destination)
                try:
                    current = os.fstat(output_dir)
                    require(current.st_uid in (0, account.pw_uid) and not current.st_mode & 0o022,
                            'unsafe primary account directory')
                    os.fchown(output_dir, account.pw_uid, account.pw_gid)
                    os.fchmod(output_dir, 0o700)
                    publish(input_dir, output_dir, account, budget, depth + 1,
                            selected[1:] if selected is not None else None)
                    os.fsync(output_dir)
                finally:
                    os.close(output_dir)
            finally:
                os.close(input_dir)
            continue
        require(selected is None or len(selected) == 1,
                'selected payload default has a nondirectory ancestor')
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1, 'nonregular payload default')
        input_file = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, dir_fd=source)
        candidate = '.primary-default-' + os.urandom(16).hex()
        try:
            require(identity(os.fstat(input_file)) == identity(info), 'payload default identity changed')
            try:
                current = os.stat(name, dir_fd=destination, follow_symlinks=False)
            except FileNotFoundError:
                current = None
            if current is not None:
                require(stat.S_ISREG(current.st_mode) and current.st_nlink == 1
                        and current.st_uid in (0, account.pw_uid), 'unsafe existing primary account file')
            output_file = os.open(candidate, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                                  0o600, dir_fd=destination)
            try:
                with os.fdopen(output_file, 'wb') as stream:
                    copied = 0
                    while chunk := os.read(input_file, 65536):
                        budget[1] += len(chunk)
                        copied += len(chunk)
                        require(budget[1] <= MAX_BYTES, 'aggregate primary payload defaults exceed the policy')
                        stream.write(chunk)
                    require(copied == info.st_size and identity(os.fstat(input_file)) == identity(info),
                            'payload default bytes changed during publication')
                    stream.flush()
                    os.fchown(stream.fileno(), account.pw_uid, account.pw_gid)
                    os.fchmod(stream.fileno(), 0o700 if info.st_mode & 0o111 else 0o600)
                    os.fsync(stream.fileno())
                os.replace(candidate, name, src_dir_fd=destination, dst_dir_fd=destination)
                os.fsync(destination)
            finally:
                try:
                    os.unlink(candidate, dir_fd=destination)
                except FileNotFoundError:
                    pass
        finally:
            os.close(input_file)
    require(found, 'selected payload default is absent')


def cleanup(source: int, device: int, depth: int = 0, budget: list[int] | None = None) -> None:
    if budget is None:
        budget = [0]
    require(depth <= 32, 'payload cleanup nesting exceeds the supported depth')
    for name in entries(source):
        budget[0] += 1
        require(budget[0] <= MAX_MEMBERS, 'too many staged payload defaults to clean')
        info = os.stat(name, dir_fd=source, follow_symlinks=False)
        require(info.st_dev == device and info.st_uid == info.st_gid == 0
                and not info.st_mode & 0o022, 'unsafe payload cleanup entry')
        if stat.S_ISDIR(info.st_mode):
            child = os.open(name, FLAGS, dir_fd=source)
            try:
                cleanup(child, device, depth + 1, budget)
            finally:
                os.close(child)
            os.rmdir(name, dir_fd=source)
        else:
            require(stat.S_ISREG(info.st_mode), 'nonregular payload cleanup entry')
            os.unlink(name, dir_fd=source)


def btop_profiles(home: int, account) -> None:
    """Create the two fixed XDG config views after dropping root permanently.

    Publication has already installed the regular authored files. This operation
    selects them; it never parses, renders, copies or executes user config.
    """
    require(os.geteuid() == account.pw_uid, 'btop views require the account identity')
    descriptors = []

    def directory(parent: int, name: str) -> int:
        try:
            os.mkdir(name, 0o700, dir_fd=parent)
        except FileExistsError:
            pass
        descriptor = os.open(name, FLAGS, dir_fd=parent)
        try:
            info = os.fstat(descriptor)
            require(info.st_uid == account.pw_uid and info.st_gid == account.pw_gid
                    and not info.st_mode & 0o022, 'unsafe btop view directory')
            os.fchmod(descriptor, 0o700)
        except BaseException:
            os.close(descriptor)
            raise
        descriptors.append(descriptor)
        return descriptor

    try:
        config = directory(home, '.config')
        btop = directory(config, 'btop')
        profiles = directory(btop, 'profiles')
        for profile in ('cpu', 'memory'):
            info = os.stat('btop-' + profile + '.conf', dir_fd=btop, follow_symlinks=False)
            require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1
                    and info.st_uid == account.pw_uid and info.st_gid == account.pw_gid
                    and not info.st_mode & 0o022 and 0 < info.st_size <= 1024 * 1024,
                    'unsafe btop profile config')
            selected = directory(directory(profiles, profile), 'btop')
            directory(selected, 'themes')
            target = '../../../btop-' + profile + '.conf'
            try:
                os.symlink(target, 'btop.conf', dir_fd=selected)
            except FileExistsError:
                current = os.stat('btop.conf', dir_fd=selected, follow_symlinks=False)
                require(stat.S_ISLNK(current.st_mode) and current.st_nlink == 1
                        and current.st_uid == account.pw_uid and current.st_gid == account.pw_gid
                        and os.readlink('btop.conf', dir_fd=selected) == target,
                        'conflicting btop config view')
            os.fsync(selected)
        for descriptor in reversed(descriptors):
            os.fsync(descriptor)
    finally:
        for descriptor in reversed(descriptors):
            os.close(descriptor)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('publish', 'cleanup', 'btop-profiles'))
    parser.add_argument('source', type=Path)
    parser.add_argument('username', nargs='?')
    parser.add_argument('home', type=Path, nargs='?')
    parser.add_argument('--relative', help='publish one exact file below the independent payload defaults root')
    args = parser.parse_args()
    require(os.geteuid() == 0, 'primary defaults require the installer root context')
    selected = None
    if args.relative is not None:
        selected = tuple(args.relative.split('/'))
        require(args.operation == 'publish' and 0 < len(selected) <= 32
                and all(name not in ('', '.', '..') for name in selected),
                'selected payload default must be a normalized relative file')
    source = open_source(args.source)
    try:
        if args.operation == 'cleanup':
            cleanup(source, os.fstat(source).st_dev)
            os.fsync(source)
            parent = os.open(args.source.parent, FLAGS)
            try:
                require(identity(os.stat(args.source.name, dir_fd=parent, follow_symlinks=False))
                        == identity(os.fstat(source)), 'payload cleanup root identity changed')
                os.rmdir(args.source.name, dir_fd=parent)
                os.fsync(parent)
            finally:
                os.close(parent)
            return
        account = pwd.getpwnam(args.username)
        require(account.pw_uid >= 1000 and account.pw_gid != 0 and args.home == Path(account.pw_dir),
                'primary account identity differs from the target passwd entry')
        require(args.home.is_absolute() and args.home.resolve(strict=True) == args.home,
                'indirect primary account home')
        home = os.open(args.home, FLAGS)
        try:
            info = os.fstat(home)
            require(info.st_uid == account.pw_uid and not info.st_mode & 0o022,
                    'primary account home has unsafe ownership or permissions')
            os.fchown(home, account.pw_uid, account.pw_gid)
            os.fchmod(home, 0o700)
            if args.operation == 'btop-profiles':
                # The validated root-owned source is no longer needed. Do not
                # retain its read authority in the account-owned phase.
                closed_source, source = source, -1
                os.close(closed_source)
                # No privilege restoration or user-code import follows this
                # boundary. Relative operations remain pinned to the HOME fd.
                os.setgroups([])
                os.setgid(account.pw_gid)
                os.setuid(account.pw_uid)
                btop_profiles(home, account)
            else:
                publish(source, home, account, [0, 0], selected=selected)
            os.fsync(home)
        finally:
            os.close(home)
    finally:
        if source >= 0:
            os.close(source)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, TimeoutError) as error:
        print('primary payload defaults: ' + str(error), file=sys.stderr)
        raise SystemExit(1)
