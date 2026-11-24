#!/usr/bin/env python3
"""NVIDIA storage guard and offline activation fixture checks, without a GPU."""
from __future__ import annotations

# Refuse host execution before importing runtime helpers or creating fixtures.
from pathlib import Path as _IsolationPath
import sys as _isolation_sys
_isolation_sys.path.insert(0, str(_IsolationPath(__file__).resolve().parents[3] / 'tools'))
# Copied checker/GUI fixtures still use the verified private checkout gate.
_isolation_sys.path.insert(0, '/workspace/repository/tools')
from isolation import require_test_isolation as _require_test_isolation
_isolation_sys.path.pop(0)
_require_test_isolation()

from payload_fixture import installed_argv as payload_installed_argv, source_exists as payload_source_exists, source_stat as payload_source_stat
from payload_fixture import installed_script
from payload_fixture import read_text as payload_read_text
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import shlex
import shutil
import stat
import subprocess
import tempfile
import types
import unittest
from unittest import mock
from fixture_render import rendered_path_text

from test_hardware_restore import make_chroot, FORKY
TARGET = FORKY / 'hooks/target'
GUARD = TARGET / 'usr/local/libexec/nvidia-vram-check'
PHASES = ('suspend', 'suspend-then-hibernate', 'hibernate', 'resume')


def load_guard():
    loader = importlib.machinery.SourceFileLoader('nvidia_vram_check', str(installed_script(GUARD)))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class NvidiaGuardTests(unittest.TestCase):
    def setUp(self):
        self.guard = load_guard()

    def test_all_gpu_capacity_plus_five_percent(self):
        total = (8192 + 4096) * 1024 * 1024
        self.assertEqual(self.guard.required_bytes('8192\n4096\n'), (total * 105 + 99) // 100)

    def test_unavailable_empty_zero_and_malformed_memory_fail(self):
        for output in ('', '0\n', 'N/A\n', '-1\n', '8192 MiB\n', '8192\n\n', '1' * 65537):
            with self.subTest(output=output[:30]):
                with self.assertRaises((RuntimeError, ValueError)):
                    self.guard.required_bytes(output)

    @unittest.skipUnless(os.geteuid() == 0, 'root ownership fixture')
    def test_tmpfs_is_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            path = Path(name)
            path.chmod(0o700)
            with mock.patch.object(self.guard.subprocess, 'run', return_value=types.SimpleNamespace(stdout='tmpfs\n')):
                with self.assertRaisesRegex(RuntimeError, 'disk-backed'):
                    self.guard.check_directory(path)

    @unittest.skipUnless(os.geteuid() == 0, 'root ownership fixture')
    def test_indirect_or_public_backing_is_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            path = Path(name)
            path.chmod(0o755)
            with self.assertRaisesRegex(RuntimeError, 'mode 0700'):
                self.guard.check_directory(path)
            path.chmod(0o700)
            link = path / 'link'
            link.symlink_to(path)
            with self.assertRaises(RuntimeError):
                self.guard.check_directory(link)

    @unittest.skipUnless(os.geteuid() == 0, 'root ownership fixture')
    def test_disk_backing_requires_successful_unnamed_file_creation(self):
        with tempfile.TemporaryDirectory() as name:
            path = Path(name)
            path.chmod(0o700)
            with mock.patch.object(self.guard.subprocess, 'run', return_value=types.SimpleNamespace(stdout='btrfs\n')):
                with mock.patch.object(self.guard.os, 'open', side_effect=OSError('unsupported')):
                    with self.assertRaises(OSError):
                        self.guard.check_directory(path)

    def run_main(self, available, args=None):
        with mock.patch.object(self.guard.os, 'geteuid', return_value=0), \
             mock.patch.object(self.guard, 'check_directory'), \
             mock.patch.object(self.guard.subprocess, 'run', return_value=types.SimpleNamespace(stdout='8192\n')) as command, \
             mock.patch.object(self.guard.os, 'statvfs', return_value=types.SimpleNamespace(f_bavail=available, f_frsize=1)):
            result = self.guard.main(args or [])
            return result, command

    def test_insufficient_space_blocks_sleep(self):
        with self.assertRaisesRegex(RuntimeError, 'insufficient NVIDIA backing space'):
            self.run_main(1)

    def test_sufficient_space_permits_sleep(self):
        result, command = self.run_main(16 * 1024**3)
        self.assertEqual(result, 0)
        self.assertEqual(command.call_args.kwargs['timeout'], 15)

    def test_install_time_validation_does_not_require_live_gpu(self):
        result, command = self.run_main(0, ['--directory-only'])
        self.assertEqual(result, 0)
        command.assert_not_called()


@unittest.skipUnless(os.geteuid() == 0 and shutil.which('chroot') and shutil.which('busybox'), 'root chroot fixtures')
class NvidiaActivationTests(unittest.TestCase):
    def fixture(self, root, missing=None):
        make_chroot(root)
        for name in ('etc/systemd/system', 'usr/lib/systemd/system', 'usr/lib/systemd/system-sleep',
                     'usr/bin', 'usr/local/libexec', 'var/lib'):
            (root / name).mkdir(parents=True, exist_ok=True)
        for phase in PHASES:
            if phase != missing:
                (root / f'usr/lib/systemd/system/nvidia-{phase}.service').write_text('[Service]\nType=oneshot\nExecStart=/bin/true\n')
        for path, text in {
            'usr/bin/nvidia-sleep.sh': '#!/bin/sh\nexit 0\n',
            'usr/lib/systemd/system-sleep/nvidia': '#!/bin/sh\nexit 0\n',
            'usr/local/libexec/nvidia-vram-check': '#!/bin/sh\nprintf "%s\\n" "$*" > /guard.args\n',
            'bin/systemctl': '''#!/bin/sh
printf '%s\\n' "$*" > /systemctl.args
shift 2
for unit do
    [ -f "/usr/lib/systemd/system/$unit" ] || {
        printf 'Failed to enable unit: Unit %s does not exist\\n' "$unit" >&2
        exit 1
    }
done
''',
        }.items():
            file = root / path
            file.write_text(text)
            file.chmod(0o755)
        (root / 'etc/passwd').write_text('root:x:0:0:root:/root:/bin/sh\n')
        (root / 'etc/group').write_text('root:x:0:\n')

    def activate(self, root):
        q = shlex.quote
        core = root / 'fixture-core.sh'
        core.write_text(rendered_path_text(payload_read_text(FORKY / 'scripts/late/core.sh')))
        code = f'''
. {q(str(core))}
installer_repo_join_var() {{ printf '%s\\n' {q(str(TARGET))}; }}
installer_repo_file_value() {{ printf '%s\\n' "$1"; }}
installer_repo_asset_path() {{ printf '%s/%s\\n' "$1" "$2"; }}
installer_systemd_dropin_dir() {{ printf '/etc/systemd/system/%s.d\\n' "$2"; }}
stage_target_asset() {{ :; }}
run_in_target() {{ shift; {q(shutil.which('chroot'))} {q(str(root))} "$@"; }}
DIR_USR_LOCAL_LIBEXEC=/usr/local/libexec
configure_target_nvidia_power_management true
'''
        return subprocess.run(payload_installed_argv(['/bin/sh', '-eu', '-c', code]), env={**os.environ, 'PATH':'/bin:/usr/bin'},
                              text=True, capture_output=True, timeout=15)

    def test_offline_enable_all_four_units_without_start(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            self.fixture(root)
            result = self.activate(root)
            self.assertEqual(result.returncode, 0, result.stderr)
            arguments = payload_read_text(root / 'systemctl.args')
            self.assertTrue(arguments.startswith('--no-reload enable '))
            self.assertNotIn('--now', arguments)
            for phase in PHASES:
                self.assertIn(f'nvidia-{phase}.service', arguments)
            self.assertFalse(payload_source_exists(root / 'guard.args'))
            self.assertEqual(stat.S_IMODE(payload_source_stat(root / 'var/lib/nvidia-vram').st_mode), 0o700)

    def test_systemctl_error_is_propagated(self):
        for missing in PHASES:
            with self.subTest(missing=missing), tempfile.TemporaryDirectory() as name:
                root = Path(name)
                self.fixture(root, missing=missing)
                result = self.activate(root)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f'nvidia-{missing}.service', result.stderr)
                self.assertTrue(payload_source_exists(root / 'systemctl.args'))


if __name__ == '__main__':
    unittest.main()
