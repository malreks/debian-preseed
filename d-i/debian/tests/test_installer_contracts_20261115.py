"""Frozen-plan selection and suite dependency regressions; isolated execution only."""
from __future__ import annotations

from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation
require_test_isolation()

import itertools
import re
import subprocess
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SEED = ROOT / 'd-i/debian'


class InstallerContracts(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='installer-contract-')
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        # No inherited HOME, session bus, runtime directories or credentials.
        self.environment = {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C', 'HOME': str(self.work)}

    def run_private(self, arguments):
        return subprocess.run(arguments, cwd=self.work, env=self.environment,
                              text=True, capture_output=True, timeout=10)

    def test_all_driver_toolkit_combinations_use_explicit_matching_classes(self):
        with tarfile.open(ROOT / 'd-i/forky/payload.tar.gz', 'r:gz') as archive:
            for name in ('scripts/common/resolve-plan.awk', 'catalog/compiled/class-plan.tsv'):
                member = archive.getmember(name)
                self.assertTrue(member.isfile())
                self.assertLess(member.size, 8 * 1024 * 1024)
                (self.work / Path(name).name).write_bytes(archive.extractfile(member).read())
        options = ('nvidia', 'nvidia-legacy', 'cuda', 'cuda-legacy')
        for suite, family, bits in itertools.product(('forky', 'trixie'),
                                                      ('desktop', 'server'),
                                                      itertools.product((False, True), repeat=4)):
            chosen = {name for name, enabled in zip(options, bits) if enabled}
            valid = (not {'nvidia', 'nvidia-legacy'} <= chosen
                     and ('cuda' not in chosen or 'nvidia' in chosen)
                     and ('cuda-legacy' not in chosen or 'nvidia-legacy' in chosen))
            role = 'desktop/base' if family == 'desktop' else 'server/devops'
            profile = 'btrfs-de-p15s' if family == 'desktop' else 'btrfs-srv-flex'
            refs = ['site/lab', 'role/' + role, 'arch/amd64', 'cpu/intel', 'kernel/x64v2',
                    'gpu/generic', 'network/dhcp', 'disk/nvme', 'profile/' + family + '/' + profile]
            refs += ['optional/' + name for name in sorted(chosen)]
            arguments = ['awk', '-v', 'suite=' + suite, '-v', 'family=' + family,
                         '-v', 'architecture=amd64', '-v', 'roles=' + role,
                         '-v', 'refs=' + ' '.join(refs), '-v', 'snapshots=none',
                         '-v', 'profile_codex_only=false', '-v', 'profile_whisper_enable=false',
                         '-v', 'profile_llama_enable=false', '-v', 'profile_ssh=false',
                         '-f', str(self.work / 'resolve-plan.awk'), str(self.work / 'class-plan.tsv')]
            with self.subTest(suite=suite, family=family, classes=sorted(chosen)):
                result = self.run_private(arguments)
                self.assertEqual(result.returncode == 0, valid, result.stderr)
                if valid:
                    actual = {line.split('\t')[1].removeprefix('optional/')
                              for line in result.stdout.splitlines() if line.startswith('class\toptional/')}
                    self.assertEqual(actual, chosen)
                    if not chosen & {'cuda', 'cuda-legacy'}:
                        packages = [line.split('\t')[1] for line in result.stdout.splitlines()
                                    if line.startswith('package\t')]
                        self.assertFalse(any(name.startswith('cuda-') for name in packages))
                else:
                    self.assertNotIn('package\t', result.stdout)

    def test_trixie_does_not_purge_required_public_packages(self):
        source = (SEED / 'scripts/desktop/xwayland.sh').read_text()
        functions = []
        for name in ('desktop_xwayland_suite_requires_public_runtime',
                     'desktop_xwayland_remove_public_runtime'):
            found = re.search(r'^' + name + r'\(\) \{\n.*?^\}', source, re.M | re.S)
            self.assertIsNotNone(found)
            functions.append(found[0])
        script = self.work / 'suite-policy.sh'
        script.write_text('\n'.join(functions) + '''
desktop_xwayland_fail() { exit 99; }
desktop_xwayland_assert_public_runtime_absent() { printf 'checked\n'; }
run_in_target_quiet() { printf 'purged\n'; }
TARGET_SUITE=$1
desktop_xwayland_remove_public_runtime
''')
        for suite, expected in (('trixie', 'checked\n'), ('forky', 'purged\nchecked\n')):
            result = self.run_private(['/bin/sh', '-eu', str(script), suite])
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, expected)

    def test_late_unshare_reuses_the_dispatcher_publication_path(self):
        plan = (SEED / 'scripts/common/modules/installation-plan.sh').read_text()
        function = re.search(r'^installer_pre_pkgsel_stage_path\(\) \{\n.*?^\}', plan, re.M | re.S)
        self.assertIsNotNone(function)
        script = self.work / 'stage-path.sh'
        script.write_text(function[0] + '\nDIR_INSTALLER_RUNTIME=$1\ninstaller_pre_pkgsel_stage_path "$2"\n')
        runtime = self.work / 'runtime'
        result = self.run_private(['/bin/sh', '-eu', str(script), str(runtime), 'installer.namespace'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(runtime / 'bootstrap/installer.namespace.sh'))
        for invalid in ('', '../escape', '/absolute', 'stage/escape'):
            result = self.run_private(['/bin/sh', '-eu', str(script), str(runtime), invalid])
            self.assertNotEqual(result.returncode, 0)
        dispatcher = (SEED / 'hooks/installer/pre-pkgsel.d/50-class-plan.sh').read_text()
        consumer = (SEED / 'scripts/late/software.sh.tmpl').read_text()
        self.assertIn('installer_pre_pkgsel_stage_path "$stage_id"', dispatcher)
        self.assertIn('installer_pre_pkgsel_stage_path installer.namespace', consumer)
        self.assertNotIn('/pre-pkgsel.d/89temporary-unshare', consumer)


if __name__ == '__main__':
    unittest.main()
