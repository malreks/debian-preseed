"""Native ownership writer/scan fixtures; reviewed isolated execution only."""
from __future__ import annotations

from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation
require_test_isolation()

import json
import os
import shutil
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
        return self.scan_inventory(registry=registry)

    def scan_inventory(self, *, registry=None):
        return subprocess.run(['/usr/bin/awk', '-v', 'target_root=' + str(self.target),
                               '-v', 'registry=' + str(registry or self.registry),
                               '-f', str(SEED / 'scripts/common/target-owned-scan.awk'),
                               str(self.inventory)], env=self.environment, capture_output=True,
                              timeout=15, check=False)

    def shells(self):
        yield ['/bin/dash']
        busybox = shutil.which('busybox', path='/usr/bin:/bin')
        self.assertIsNotNone(busybox, 'the isolated fixture must provide BusyBox')
        yield [busybox, 'sh']

    def record(self, shell, source, destination, kind='plain', phase='late-command'):
        # Root identity is fixture metadata; all actual writes stay under the
        # private fixture root. No target or host metadata helper is executed.
        script = '''
. "$1"
installer_fatal() { printf 'fatal: %s\\n' "$*" >&2; exit 1; }
installer_lifecycle_parent_safe() { [ "$1" = "$DIR_INSTALLER_TARGET_OWNERSHIP" ]; }
installer_metadata_value() {
  case "$1:$2" in
    "$DIR_INSTALLER_TARGET_OWNERSHIP:uid_gid_mode") printf '0:0:700\\n' ;;
    "$DIR_INSTALLER_TARGET_OWNERSHIP/"*:uid_gid_mode_links) printf '0:0:600:1\\n' ;;
    *) return 1 ;;
  esac
}
installer_target_ownership_record "$2" "$3" "$4" 0644
installer_target_ownership_snapshot >"$HOME/owned-snapshot.tsv"
'''
        return subprocess.run(
            [*shell, '-eu', '-c', script, 'owned-record',
             str(SEED / 'scripts/common/modules/target-publication.sh'),
             source, destination, kind],
            cwd=self.root, env={**self.environment,
                               'DIR_INSTALLER_TARGET_OWNERSHIP': str(self.root / 'records'),
                               'INSTALLER_PHASE': phase},
            capture_output=True, text=True, timeout=5, check=False)

    def test_spaced_source_round_trips_through_writer_and_final_scan(self):
        source = 'hooks/target/etc/skel-desktop/.config/vivaldi/Local State'
        destination = '/etc/skel-desktop/.config/vivaldi/Local State'
        for shell in self.shells():
            with self.subTest(shell=shell):
                result = self.record(shell, source, destination)
                self.assertEqual(result.returncode, 0, result.stderr)
                records = list((self.root / 'records').glob('*.tsv'))
                self.assertEqual(len(records), 1)
                data = (self.root / 'owned-snapshot.tsv').read_bytes()
                self.assertEqual(data.decode().splitlines(), [
                    f'{destination}\t{source}\tplain\tlate-command\t0644'])
                self.inventory.write_bytes(data)
                target = self.target / destination.lstrip('/')
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('{}\n', encoding='utf-8')
                scan = self.scan_inventory()
                self.assertEqual(scan.returncode, 0, scan.stdout + scan.stderr)
                target.write_text('__UNKNOWN_FIXTURE__\n', encoding='utf-8')
                scan = self.scan_inventory()
                self.assertNotEqual(scan.returncode, 0)
                self.assertIn(b'token=__UNKNOWN_FIXTURE__', scan.stdout)

    def test_source_field_separators_and_empty_source_fail_before_record_creation(self):
        for shell in self.shells():
            for source in ('', 'source\tother', 'source\nother', 'source\rother',
                           'source\\other', 'source;other', 'source$other', 'source|other'):
                with self.subTest(shell=shell, source=source):
                    result = self.record(shell, source, '/etc/fixture')
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('invalid target ownership source', result.stderr)
                    self.assertFalse((self.root / 'records').exists())

    def test_phase_and_kind_keep_their_identifier_grammar(self):
        for shell in self.shells():
            for phase, kind in (('late command', 'plain'), ('late\ncommand', 'plain'),
                                ('late-command', 'template input'), ('late-command', ''),
                                ('late-command', 'plain\tother')):
                with self.subTest(shell=shell, phase=phase, kind=kind):
                    result = self.record(shell, 'generated', '/etc/fixture', kind, phase)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('invalid target ownership context', result.stderr)
                    self.assertFalse((self.root / 'records').exists())

    def test_generated_stdin_retains_its_declared_source(self):
        for shell in self.shells():
            with self.subTest(shell=shell):
                result = self.record(shell, '-', '/etc/fixture', 'stdin')
                self.assertEqual(result.returncode, 0, result.stderr)
                record, = (self.root / 'records').glob('*.tsv')
                self.assertEqual((self.root / 'owned-snapshot.tsv').read_text().split('\t')[1:4],
                                 ['generated', 'stdin', 'late-command'])

    def test_invalid_replacement_preserves_previous_record_and_target(self):
        target = self.target / 'etc/fixture'
        target.parent.mkdir()
        target.write_text('previous target\n', encoding='utf-8')
        for shell in self.shells():
            with self.subTest(shell=shell):
                result = self.record(shell, 'generated', '/etc/fixture', 'stdin')
                self.assertEqual(result.returncode, 0, result.stderr)
                record, = (self.root / 'records').glob('*.tsv')
                before = record.read_bytes()
                result = self.record(shell, 'bad\tsource', '/etc/fixture')
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(record.read_bytes(), before)
                self.assertEqual(target.read_text(), 'previous target\n')
                self.assertEqual(list((self.root / 'records').glob('.record.*')), [])

    def test_journal_updates_and_removal_use_exact_destination_keys(self):
        shell = ['/bin/dash']
        first = self.record(shell, 'one', '/etc/fixture')
        self.assertEqual(first.returncode, 0, first.stderr)
        second = self.record(shell, 'two', '/etc/fixture')
        self.assertEqual(second.returncode, 0, second.stderr)
        snapshot = (self.root / 'owned-snapshot.tsv').read_text().splitlines()
        self.assertEqual(snapshot, ['/etc/fixture\ttwo\tplain\tlate-command\t0644'])
        removed = self.record(shell, 'generated', '/etc/fixture', 'deleted')
        self.assertEqual(removed.returncode, 0, removed.stderr)
        self.assertEqual((self.root / 'owned-snapshot.tsv').read_bytes(), b'')
        self.assertEqual(len((self.root / 'records/journal.tsv').read_text().splitlines()), 3)
        self.assertEqual(sorted(path.name for path in (self.root / 'records').iterdir()), ['journal.tsv'])

    def test_interrupted_journal_is_retained_and_cannot_become_a_snapshot(self):
        shell = ['/bin/dash']
        result = self.record(shell, 'one', '/etc/fixture')
        self.assertEqual(result.returncode, 0, result.stderr)
        journal = self.root / 'records/journal.tsv'
        with journal.open('ab') as stream:
            stream.write(b'/etc/incomplete\t')
        result = self.record(shell, 'two', '/etc/other')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'/etc/incomplete\t', journal.read_bytes())
        self.assertEqual((self.root / 'owned-snapshot.tsv').read_bytes(), b'')

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

    def test_app_veth_runtime_template_passes_final_ownership_scan(self):
        source = 'hooks/target/etc/app-veth.nft.tmpl'
        data = (SEED / source).read_text(encoding='utf-8').replace(
            '__INSTALLER_PROXY3_PORTS_ALLOW_WEB_BROWSER__', '443,5380,8443,53443')
        result = self.scan([('/etc/app-veth.nft', source, 'template', data)])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_app_veth_runtime_fields_are_forbidden_in_unrelated_sources(self):
        for name in ('APP_INTERFACES', 'DNS_ADDRESS', 'DNS_HOST_ADDRESS', 'DNS_HOST_PORT'):
            with self.subTest(name=name):
                result = self.scan([('/etc/unrelated.nft', 'generated', 'stdin',
                                     '__' + name + '__\n')])
                self.assertNotEqual(result.returncode, 0)

    def test_app_veth_template_does_not_allow_unknown_or_installer_markers(self):
        source = 'hooks/target/etc/app-veth.nft.tmpl'
        for marker in ('__UNKNOWN_FIXTURE__', '__INSTALLER_PROXY3_PORTS_ALLOW_WEB_BROWSER__',
                       '__INSTALLER_PATH_DIR_ETC__'):
            with self.subTest(marker=marker):
                result = self.scan([('/etc/app-veth.nft', source, 'template', marker + '\n')])
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
