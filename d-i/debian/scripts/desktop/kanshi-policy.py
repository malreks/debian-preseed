#!/usr/bin/python3 -I
"""Installer-only opt-in Kanshi reconciliation. Never run in a live desktop.

Only the named Debian package and explicitly marked installer activation
files are removed. Unmarked administrator files are preserved. Inert display
profiles are retained, not erased. The caller removes this helper after use.
"""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import stat
import signal
import subprocess
import sys

# These three fixed publication interfaces declare installer ownership with the
# existing header convention. This is an ownership declaration, not a checksum
# or a claim that administrator edits can be detected inside a managed file.
OWNED_NAMES = frozenset({'kanshi.service', '60-resource-class.conf', 'labwc-kanshi'})
OWNER_HEADER = b'# Managed by unattended-installer.'
WRAPPER = Path('__INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/labwc-kanshi')
EXECUTABLES = tuple(Path(p) for p in ('__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/kanshi', '__INSTALLER_PATH_DIR_USR_BIN__/kanshi', '__INSTALLER_PATH_DIR_BIN__/kanshi'))
ENV = {'HOME': '__INSTALLER_PATH_DIR_ROOT_HOME__', 'PATH': '__INSTALLER_PATH_DIR_USR_SBIN__:__INSTALLER_PATH_DIR_USR_BIN__:__INSTALLER_PATH_DIR_SBIN__:__INSTALLER_PATH_DIR_BIN__',
       'LC_ALL': 'C', 'DEBIAN_FRONTEND': 'noninteractive'}


def safe_path(path: Path) -> None:
    for parent in reversed(path.parents):
        if parent.is_symlink() or (parent.exists() and not parent.is_dir()):
            raise ValueError(f'unsafe Kanshi policy parent: {parent}')


def unit_roots(home: Path) -> tuple[Path, ...]:
    return (Path('__INSTALLER_PATH_DIR_SYSTEMD_USER__'), Path('__INSTALLER_PATH_DIR_ETC_SKEL_DESKTOP_CONFIG__/systemd/user'),
            home / '.config/systemd/user')


def cleanup_plan(home: Path) -> list[tuple[Path, str | tuple[int, ...]]]:
    plan = []
    for base in unit_roots(home):
        safe_path(base / '.policy-check')
        if not base.exists():
            continue
        dropins = base / 'kanshi.service.d'
        safe_path(dropins / '.policy-check')
        if dropins.exists() and any(p.name != '60-resource-class.conf' for p in dropins.iterdir()):
            raise ValueError(f'unmanaged Kanshi drop-ins preserved: {dropins}')
        for path in (base / 'kanshi.service', dropins / '60-resource-class.conf'):
            check_file(path, plan, uid=home.lstat().st_uid if path.is_relative_to(home) else os.geteuid())
        for directory in sorted(base.iterdir()):
            if not directory.name.endswith(('.wants', '.requires')):
                continue
            safe_path(directory / 'kanshi.service')
            link = directory / 'kanshi.service'
            if not link.exists() and not link.is_symlink():
                continue
            allowed = {'../kanshi.service', str(base / 'kanshi.service'),
                       '__INSTALLER_PATH_DIR_SYSTEMD_USER_LIB__/kanshi.service'}
            if not link.is_symlink() or os.readlink(link) not in allowed:
                raise ValueError(f'unmanaged Kanshi activation preserved: {link}')
            plan.append((link, 'link:' + os.readlink(link)))
    check_file(WRAPPER, plan)
    return plan


def file_identity(info: os.stat_result) -> tuple[int, ...]:
    return (info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_gid,
            info.st_nlink, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def check_file(path: Path, plan: list[tuple[Path, str | tuple[int, ...]]], *, uid: int | None = None) -> None:
    safe_path(path)
    if not path.exists() and not path.is_symlink():
        return
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode):
        raise ValueError(f'unmanaged Kanshi file preserved: {path}')
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    with os.fdopen(descriptor, 'rb') as stream:
        info = os.fstat(stream.fileno())
        if (file_identity(info) != file_identity(before)
                or path.name not in OWNED_NAMES or not stat.S_ISREG(info.st_mode)
                or info.st_uid != (os.geteuid() if uid is None else uid)
                or info.st_nlink != 1 or info.st_mode & 0o022
                or OWNER_HEADER not in stream.read(128).splitlines()[:2]):
            raise ValueError(f'unmanaged Kanshi file preserved: {path}')
    plan.append((path, file_identity(info)))


def command(argv: list[str], *, check: bool = True, capture: bool = False,
            timeout: float = 600) -> subprocess.CompletedProcess[str]:
    # Own the process group: an interrupted installer must not leave apt/dpkg
    # descendants mutating the target after the caller has reported failure.
    def interrupted(number, _frame):
        raise InterruptedError(f"Kanshi command interrupted by signal {number}")

    handlers = {sig: signal.signal(sig, interrupted)
                for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM)}
    child = None
    try:
        child = subprocess.Popen(argv, env=ENV, text=True, start_new_session=True,
                                 stdout=subprocess.PIPE if capture else None,
                                 stderr=subprocess.PIPE if capture else None)
        try:
            stdout, stderr = child.communicate(timeout=timeout)
        except BaseException:
            # Ignore a second termination while reaping our group.
            for sig in handlers:
                signal.signal(sig, signal.SIG_IGN)
            try:
                os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                child.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                pass
            finally:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                child.communicate()
            raise
        result = subprocess.CompletedProcess(argv, child.returncode, stdout, stderr)
        if check:
            result.check_returncode()
        return result
    finally:
        for sig, handler in handlers.items():
            signal.signal(sig, handler)


def package_state() -> str:
    result = command(['__INSTALLER_PATH_DIR_USR_BIN__/dpkg-query', '-W', '-f=${db:Status-Status}', 'kanshi'],
                     check=False, capture=True)
    if result.returncode == 1:
        return 'not-installed'
    if result.returncode:
        raise RuntimeError('cannot inspect Kanshi package state: ' + result.stderr)
    return result.stdout.strip()


def reconcile(enabled: bool, home: Path) -> None:
    if enabled:
        command(['__INSTALLER_PATH_DIR_USR_BIN__/apt-get', '-q', '-y', '-o', 'DPkg::Lock::Timeout=120',
                 '-o', 'Acquire::Retries=2', '-o', 'Acquire::http::Timeout=30',
                 '-o', 'Acquire::https::Timeout=30',
                 '-o', 'Acquire::AllowInsecureRepositories=false',
                 '-o', 'Acquire::AllowDowngradeToInsecureRepositories=false',
                 '-o', 'APT::Get::AllowUnauthenticated=false',
                 '--no-install-recommends', '--no-install-suggests', '--no-remove',
                 'install', 'kanshi'])
        if package_state() != 'installed':
            raise RuntimeError('enabled Kanshi package is not installed')
        # Only the account-local managed session should activate this daemon.
        if any(Path(p).is_file() for p in ('__INSTALLER_PATH_DIR_SYSTEMD_USER_LIB__/kanshi.service',)):
            command(['__INSTALLER_PATH_DIR_USR_BIN__/systemctl', '--global', 'disable', 'kanshi.service'])
        return

    plan = cleanup_plan(home)  # Validate ALL ownership before any mutation.
    if package_state() != 'not-installed':
        # dpkg refuses unmet reverse dependencies; never force them or remove
        # unrelated packages using an automatic dependency solver/autoremove.
        command(['__INSTALLER_PATH_DIR_USR_BIN__/dpkg', '--purge', 'kanshi'])
    if package_state() != 'not-installed':
        raise RuntimeError('disabled Kanshi package is still present')
    for path, expected in plan:
        safe_path(path)
        if not path.exists() and not path.is_symlink():
            continue
        if isinstance(expected, str):
            current = 'link:' + os.readlink(path) if path.is_symlink() else ''
        else:
            current = file_identity(path.lstat())
        if current != expected:
            raise RuntimeError(f'Kanshi asset changed during installer cleanup: {path}')
        path.unlink()
    for base in unit_roots(home):
        dropins = base / 'kanshi.service.d'
        if dropins.is_dir():
            dropins.rmdir()  # Only empty directories, never recursive removal.
    for path in EXECUTABLES:
        if os.path.lexists(path):
            raise RuntimeError(f'unmanaged disabled Kanshi executable preserved: {path}')


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--enabled', required=True, choices=('true', 'false'))
    parser.add_argument('--home', required=True)
    args = parser.parse_args(argv)
    if os.geteuid() != 0:
        raise ValueError('Kanshi package policy must run as installer root')
    home = Path(args.home)
    if not home.is_absolute() or home == Path('/') or str(home) != args.home or '..' in home.parts:
        raise ValueError('account home must be a normalized absolute non-root path')
    safe_path(home / '.policy-check')
    reconcile(args.enabled == 'true', home)
    print('kanshi_policy enabled=' + args.enabled)
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
        print(f'fatal: Kanshi policy: {exc}', file=sys.stderr)
        raise SystemExit(1)
