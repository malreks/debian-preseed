"""Physical stage-member regressions; execute only in the private test image."""
from __future__ import annotations

from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation
require_test_isolation()

import shutil
import subprocess
import tempfile
import unittest

from class_compiler import class_dispatch


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'd-i/debian'
FIXTURE = SOURCE / 'tests/fixtures/contracts/pre-pkgsel-plan.sh'
CASES = (
    'dispatch', 'records', 'completed', 'child-failure', 'second-failure',
    'fetch-failure', 'invalid-policy', 'changed-plan', 'missing-ready',
    'unprepared', 'interrupted', 'wrong-stamp', 'symlink-stamp', 'unresolved',
    'invalid-id', 'invalid-phase', 'invalid-path', 'invalid-traversal',
    'invalid-dot', 'invalid-empty-component', 'invalid-trailing-slash',
    'invalid-empty-path', 'invalid-field', 'invalid-column',
    'invalid-duplicate-id', 'invalid-duplicate-provider', 'invalid-late-path',
)


class PlanStageDispatch(unittest.TestCase):
    def test_dispatch_and_failure_contracts_in_dash_and_installer_ash(self):
        for shell in ('/bin/dash', '/bin/busybox'):
            self.assertTrue(shutil.which(shell), 'required Debian fixture shell: ' + shell)
            for case in CASES:
                with self.subTest(shell=shell, case=case), tempfile.TemporaryDirectory(
                        prefix='plan-stage-dispatch-') as directory:
                    result = subprocess.run(
                        ['/bin/sh', str(FIXTURE), str(SOURCE), directory, case, shell],
                        env={'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'LC_ALL': 'C',
                             'HOME': directory, 'TMPDIR': directory,
                             'TMP': directory, 'TEMP': directory},
                        capture_output=True, text=True, timeout=20)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn('PASS case=' + case, result.stdout)

    def test_compiler_rejects_stage_names_that_cannot_be_phase_filenames(self):
        for name, provider, after in (
                ('installer/invalid', 'scripts/early/dispatch.sh', '-'),
                ('installer.valid', 'scripts/a file.sh', '-'),
                ('installer.valid', 'scripts/../escape.sh', '-'),
                ('installer.valid', '__INSTALLER_PATH_DIR_BIN__/child.sh', '-'),
                ('installer.valid', 'scripts/early/dispatch.sh', 'installer/invalid')):
            with self.subTest(name=name, provider=provider, after=after):
                source = ('format\t1\nstage\tfragments/apt.cfg\t' + name
                          + '\tpre-pkgsel\t' + provider + '\t' + after + '\t-\n')
                with self.assertRaises(ValueError):
                    class_dispatch({'hooks/installer/class-dispatch.tsv': source.encode()},
                                   {'fragments/apt.cfg': {'stages': []}})


if __name__ == '__main__':
    unittest.main()
