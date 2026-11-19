"""Build explicit data for the real Perl publisher in the reviewed guest only.

This adapter relocates logical fixture destinations beneath one private tree;
production code still sees an ordinary absolute path and has no test bypass.
It executes no package, service, network or installed management helpers.
"""
from __future__ import annotations

from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation
require_test_isolation()

import os
import stat
import subprocess
import tempfile

RENDERER = Path(__file__).resolve().parents[1] / 'scripts/common/render.pl'
ARCHIVE = 'a' * 64


def fields(row):
    encoded = [str(value).encode('utf-8') for value in row]
    return str(len(encoded)).encode('ascii') + b'\n' + b''.join(
        str(len(value)).encode('ascii') + b':' + value + b',' for value in encoded)


def private_write(path, data):
    path.write_bytes(data)
    path.chmod(0o600)


def prepared_fixture(prepared):
    prepared.mkdir(mode=0o700, parents=True, exist_ok=True)
    prepared.chmod(0o700)
    (prepared / 'inputs').mkdir(mode=0o700, exist_ok=True)
    (prepared / 'source').mkdir(mode=0o700, exist_ok=True)
    if not (prepared / 'identity').exists():
        private_write(prepared / 'identity', f'verified-v1 {ARCHIVE} {"b" * 64} /fixture-seed\n'.encode())
    for name, default in (('paths.map', b'GITBUILD_DISTRIBUTION=forky\n'),
                          ('published-assets.tsv', b''), ('resources.map', b'')):
        if not (prepared / 'inputs' / name).exists():
            private_write(prepared / 'inputs' / name, default)
    members = sorted(str(path.relative_to(prepared / 'source'))
                     for path in (prepared / 'source').rglob('*') if not stat.S_ISDIR(path.lstat().st_mode))
    private_write(prepared / 'inputs/prepared-members', ''.join(name + '\n' for name in members).encode())


def plan_fixture(prepared, target, operations, *, family='desktop', suite='forky', account_home='/home/alice',
                 phase='late-command'):
    prepared_fixture(prepared)
    target.mkdir(mode=0o700, parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='publish.', dir=prepared / 'inputs'))
    work.chmod(0o700)
    context = {
        'FORMAT': '1', 'SUITE': suite, 'FAMILY': family, 'PHASE': phase, 'GROUP': 'fixture-assets',
        'DEFAULTS_ROOT': str(target / 'var/lib/installer/primary-defaults'),
        'TEMP_ROOT': str(target / 'tmp'), 'SKELETON_BASE': str(target / 'etc/skel-base'),
        'SKELETON_DESKTOP': str(target / 'etc/skel-desktop'),
        'SKELETON_SERVER': str(target / 'etc/skel-server'), 'ACCOUNT_HOME': account_home,
        'SOURCE_ARCHIVE_SHA256': ARCHIVE, 'SOURCE_TARGET_ROOT': 'hooks/target',
        'SOURCE_AA_ROOT': 'hooks/target/etc/apparmor.d', 'SOURCE_APPARMOR_ROOT': 'hooks/target/etc/apparmor',
        'SOURCE_TMPFILES_ROOT': 'hooks/target/etc/tmpfiles.d', 'SOURCE_SYSCTL_ROOT': 'hooks/target/etc/sysctl.d',
        'SOURCE_BIN_ROOT': 'hooks/target/usr/local/bin', 'SOURCE_SBIN_ROOT': 'hooks/target/usr/local/sbin',
        'SOURCE_LIBEXEC_ROOT': 'hooks/target/usr/local/libexec', 'SOURCE_LIB_ROOT': 'hooks/target/usr/local/lib',
        'SOURCE_SHARE_ROOT': 'hooks/target/usr/local/share', 'SOURCE_SYSTEMD_ROOT': 'hooks/target/etc/systemd',
        'SOURCE_SYSTEMD_COMMON': 'hooks/target/etc/systemd/common',
        'SOURCE_SYSTEMD_DESKTOP': 'hooks/target/etc/systemd/desktop',
        'SOURCE_SYSTEMD_SERVER': 'hooks/target/etc/systemd/server',
        'SOURCE_APT_ROOT': f'frontends/{suite}/hooks/target/etc/apt',
        'SOURCE_APT_DESKTOP': f'frontends/{suite}/hooks/target/etc/apt/desktop',
        'SOURCE_APT_SERVER': f'frontends/{suite}/hooks/target/etc/apt/server',
        'SOURCE_FRONTEND_ROOT': f'frontends/{suite}',
    }
    private_write(work / 'context', ''.join(key + '=' + value + '\n' for key, value in context.items()).encode())
    data = b'publication-plan-v1\n'
    for kind, source, destination, mode, pairs in operations:
        logical = str(destination)
        if not logical.startswith('/') or '..' in Path(logical).parts:
            raise ValueError('fixture destination must be a confined logical path')
        actual = str(target) + logical
        data += fields((kind, source, actual, mode, '0:0', family, suite,
                        phase, 'fixture-assets', *pairs))
    private_write(work / 'plan', data)
    return work


def run_fixture(prepared, work, *, preexec_fn=None):
    environment = {'PATH': '/unavailable', 'HOME': str(prepared), 'LC_ALL': 'C',
                   'TMPDIR': str(prepared), 'TMP': str(prepared), 'TEMP': str(prepared)}
    return subprocess.run(['/usr/bin/perl', '-f', str(RENDERER), '--publish', str(work), str(prepared)],
                          env=environment, capture_output=True, timeout=15, check=False,
                          preexec_fn=preexec_fn)


def main(argv):
    if len(argv) < 7 or (len(argv) - 7) % 2:
        raise SystemExit('fixture publication requires root, prepared, target, source, destination, mode, kind and scalar pairs')
    root, prepared, target = map(Path, argv[:3])
    root = root.resolve(strict=True)
    for path in (prepared, target):
        if not path.resolve(strict=True).is_relative_to(root):
            raise SystemExit('fixture state escapes its private root')
    source, destination, mode, kind = argv[3:7]
    work = plan_fixture(prepared, target, [(kind, source, destination, mode, argv[7:])])
    result = run_fixture(prepared, work)
    sys.stdout.buffer.write(result.stdout)
    sys.stderr.buffer.write(result.stderr)
    return result.returncode if result.returncode >= 0 else 128 - result.returncode


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
