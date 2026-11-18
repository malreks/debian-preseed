"""Timeshift child-shell startup only; guarded isolated execution required.

The real startup prefix loads the real target library's function definitions.
No target command, storage probe, staging operation or service is executed.
"""
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from isolation import require_test_isolation
require_test_isolation()

import shutil
import subprocess
import tempfile
import unittest


COMMON = ROOT / 'd-i/debian/scripts/common'


class TimeshiftStartupTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix='timeshift-startup-')
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        source = (COMMON / 'timeshift.sh').read_text(encoding='utf-8')
        self.startup, boundary, _rest = source.partition('\ninstaller_snapshots_enabled ')
        self.assertTrue(boundary, 'startup must end before policy, device and staging work')
        self.bootstrap = self.root / 'bootstrap.sh'
        self.bootstrap.write_text('''
bootstrap_source_common_lib() { :; }
installer_seed_base() { printf 'fixture-source\\n'; }
installer_ensure_context_loaded() { :; }
bootstrap_source_common_support_libs() {
  [ "$FIXTURE_LOAD_STATUS" -eq 0 ] || return "$FIXTURE_LOAD_STATUS"
  [ "$1" = fixture-source ] || return 88
  shift 2
  [ "$#" -eq 1 ] && [ "$1" = target ] || return 89
  . "$FIXTURE_TARGET_LIB"
}
installer_assert_class_plan() {
  command -v run_in_target >/dev/null 2>&1 || exit 97
  printf 'target-helper-ready\\n'
}
''', encoding='utf-8')

    def run_startup(self, shell, *, status=0, source=None, conditional=False):
        entrypoint = self.root / 'startup.sh'
        entrypoint.write_text((self.startup if source is None else source) + '\n', encoding='utf-8')
        env = {
            'PATH': '/usr/bin:/bin', 'LC_ALL': 'C',
            'TMPDIR': str(self.root), 'TMP': str(self.root), 'TEMP': str(self.root),
            'INSTALLER_BOOTSTRAP_LIB': str(self.bootstrap),
            'INSTALLER_RUNTIME_DIR': str(self.root / 'runtime'),
            'DIR_INSTALLER_LATE_ENV': str(self.root / 'env'),
            'FIXTURE_TARGET_LIB': str(COMMON / 'target.sh'),
            'FIXTURE_LOAD_STATUS': str(status),
        }
        command = [*shell, '-eu', str(entrypoint)]
        if conditional:
            command = [*shell, '-eu', '-c', 'if . "$1"; then printf "startup-complete\\n"; fi',
                       'timeshift-startup', str(entrypoint)]
        return subprocess.run(command, env=env, cwd=self.root,
                              capture_output=True, text=True, timeout=5)

    def shells(self):
        yield ['/bin/dash']
        busybox = shutil.which('busybox', path='/usr/bin:/bin')
        self.assertIsNotNone(busybox, 'the isolated fixture must provide BusyBox')
        yield [busybox, 'sh']

    def test_fresh_child_loads_target_helpers_before_policy_or_publication(self):
        for shell in self.shells():
            with self.subTest(shell=shell):
                result = self.run_startup(shell)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, 'target-helper-ready\n')

    def test_loader_failure_stops_startup_even_under_a_conditional_caller(self):
        for shell in self.shells():
            with self.subTest(shell=shell):
                result = self.run_startup(shell, status=73, conditional=True)
                self.assertEqual(result.returncode, 73, result.stderr)
                self.assertEqual(result.stdout, '')

    def test_negative_control_reproduces_missing_helper_in_a_fresh_child(self):
        broken = '\n'.join(line for line in self.startup.splitlines()
                           if not line.startswith('bootstrap_source_common_support_libs '))
        self.assertNotEqual(broken, self.startup)
        for shell in self.shells():
            with self.subTest(shell=shell):
                result = self.run_startup(shell, source=broken)
                self.assertEqual(result.returncode, 97, result.stderr)
                self.assertEqual(result.stdout, '')
