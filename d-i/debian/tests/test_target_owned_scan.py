"""Native AWK scan fixtures, run only in a reviewed disposable image."""
from __future__ import annotations

from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation
require_test_isolation()

import json
import os
import subprocess
import tempfile
import unittest

SEED = Path(__file__).resolve().parents[1]


class TargetOwnedScanTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='owned-target-scan-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.target = self.root / 'target'
        self.target.mkdir(mode=0o700)
        self.inventory = self.root / 'owned.tsv'
        self.registry = SEED / 'catalog/placeholder-registry.tsv'
        self.environment = {'PATH': '/usr/bin:/bin', 'HOME': str(self.root),
                            'TMPDIR': str(self.root), 'TMP': str(self.root),
                            'TEMP': str(self.root), 'LC_ALL': 'C'}

    def scan(self, files, *, registry=None):
        rows = []
        for destination, source, kind, data in files:
            path = self.target / destination.lstrip('/')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(data, encoding='utf-8')
            rows.append(f'{destination}\t{source}\t{kind}\tlate-command\t0644\n')
        self.inventory.write_text(''.join(rows), encoding='utf-8')
        return subprocess.run(['/usr/bin/awk', '-v', 'target_root=' + str(self.target),
                               '-v', 'registry=' + str(registry or self.registry),
                               '-f', str(SEED / 'scripts/common/target-owned-scan.awk'),
                               str(self.inventory)], env=self.environment, capture_output=True,
                              timeout=15, check=False)

    def test_unknown_tokens_in_perl_share_and_generated_state_fail(self):
        for destination in ('/usr/local/lib/perl5/site_perl/fixture.pm',
                            '/usr/local/share/fixture/generated.conf',
                            '/var/lib/installer-state/generated.conf'):
            with self.subTest(destination=destination):
                result = self.scan([(destination, 'generated', 'stdin', '__UNKNOWN_FIXTURE__\n')])
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(destination.encode(), result.stdout)
                self.assertIn(b'line=1 offset=0 token=__UNKNOWN_FIXTURE__', result.stdout)

    def test_adjacent_markers_are_reported_individually(self):
        result = self.scan([('/etc/fixture', 'generated', 'stdin', '__UNKNOWN_A____UNKNOWN_B__\n')])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'offset=0 token=__UNKNOWN_A__', result.stdout)
        self.assertIn(b'offset=13 token=__UNKNOWN_B__', result.stdout)

    def test_language_grammar_is_allowed_only_in_its_declared_source(self):
        registry = json.loads((SEED / 'catalog/placeholder-registry.json').read_text(encoding='utf-8'))
        entry = next(entry for entry in registry['entries'] if entry['token'] == '__PACKAGE__')
        source = entry['consumer']['source_members'][0]
        result = self.scan([('/usr/local/lib/perl5/site_perl/fixture.pm', source, 'plain',
                             'package Fixture; print __PACKAGE__;\n')])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = self.scan([('/etc/fixture', 'generated', 'stdin', '__PACKAGE__\n')])
        self.assertNotEqual(result.returncode, 0)

    def test_installer_mode_marker_is_forbidden_even_in_comments(self):
        result = self.scan([('/etc/apparmor/modes.conf',
                             'hooks/target/etc/apparmor/desktop/modes.conf.tmpl', 'template',
                             '# __DESKTOP_APPARMOR_STATE__\n')])
        self.assertNotEqual(result.returncode, 0)

    def test_installer_environment_and_repository_files_fail(self):
        for destination, data in (('/etc/repo.env', 'FILE_TARGET_TEST="hooks/target/test"\n'),
                                  ('/etc/di.env', 'TARGET_ROOT="/target"\n'),
                                  ('/usr/local/share/runtime.conf', 'DIR_INSTALLER_RUNTIME="/private"\n')):
            with self.subTest(destination=destination):
                result = self.scan([(destination, 'generated', 'stdin', data)])
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(b'installer environment', result.stdout)

    def test_duplicate_registry_token_fails(self):
        registry = self.root / 'registry.tsv'
        rows = self.registry.read_text(encoding='utf-8').splitlines()
        registry.write_text('\n'.join(rows + [rows[2]]) + '\n', encoding='utf-8')
        result = self.scan([('/etc/fixture', 'generated', 'stdin', 'concrete\n')], registry=registry)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'malformed placeholder ownership registry', result.stdout)

    def test_malformed_and_unknown_marker_grammars_fail(self):
        for marker in ('__INSTALLER_MISSING_CLOSE', '__INSTALLER_lowercase__',
                       '__UNKNOWN.DOTTED__', '__UNKNOWN-HYPHEN__'):
            with self.subTest(marker=marker):
                result = self.scan([('/etc/fixture', 'generated', 'stdin', marker + '\n')])
                self.assertNotEqual(result.returncode, 0)

    def test_appearance_metadata_is_scoped_to_the_exact_source_and_kind(self):
        source = 'hooks/target/usr/local/share/desktop/labwc-appearance/fields.json.tmpl'
        marker = '__INSTALLER_LABWC_WAYBAR_INTERNAL_ACTIVE_SHADOW__'
        for member, kind, succeeds in ((source, 'appearance-registry', True),
                                        (source, 'plain', False),
                                        ('generated', 'appearance-registry', False)):
            with self.subTest(member=member, kind=kind):
                result = self.scan([('/usr/local/share/fields.json', member, kind, marker + '\n')])
                self.assertEqual(result.returncode == 0, succeeds, result.stdout + result.stderr)

    def test_unrelated_package_tree_is_not_scanned(self):
        unrelated = self.target / 'usr/lib/package/unrelated.py'
        unrelated.parent.mkdir(parents=True)
        unrelated.write_text('__UNRELATED_PACKAGE_GRAMMAR__\n', encoding='utf-8')
        result = self.scan([('/etc/fixture', 'generated', 'stdin', 'concrete\n')])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    raise SystemExit(unittest.main())
