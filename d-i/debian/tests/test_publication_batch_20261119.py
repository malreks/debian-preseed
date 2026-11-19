"""Publication behavior and work-count fixtures; reviewed guest execution only.

The isolated guest provides root-owned /var/lib and perl-base. All mutable
fixture state is created below one exclusive /var/lib/publication-batch-* tree;
no host roots, sockets, package state or network are used or exposed.
"""
from __future__ import annotations

from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation
require_test_isolation()

import hashlib
import os
import re
import resource
import subprocess
import tarfile
import tempfile
import unittest

from fixture_publication import ARCHIVE, RENDERER, fields, plan_fixture, private_write, run_fixture


class PublicationPhaseValidationTests(unittest.TestCase):
    """Exercise the complete parser before any target publication is possible."""

    def predicate_results(self, values):
        source = RENDERER.read_bytes()
        predicates = re.findall(rb'^\s*&& (\$context->\{PHASE\} =~ [^\n]+)$', source, re.M)
        self.assertEqual(len(predicates), 1, 'exact production PHASE predicate must have one owner')
        # Hex input preserves every byte, including NUL and line separators,
        # without putting raw fixture values into generated Perl source.
        program = (b'use strict; use warnings; use bytes;\n'
                   b'while (my $line = <STDIN>) {\n'
                   b'  chomp $line;\n'
                   b'  $line =~ /\\A(?:[0-9a-f]{2})*\\z/ or die "invalid fixture input\\n";\n'
                   b'  my $context = { PHASE => pack("H*", $line) };\n'
                   b'  print((' + predicates[0] + b') ? "1\\n" : "0\\n");\n'
                   b'}\n')
        with tempfile.TemporaryDirectory(prefix='publication-phase-bytes-', dir='/workspace') as temporary:
            root = Path(temporary)
            fixture = root / 'phase-predicate.pl'
            private_write(fixture, program)
            environment = {'PATH': '/unavailable', 'HOME': str(root), 'LC_ALL': 'C',
                           'TMPDIR': str(root), 'TMP': str(root), 'TEMP': str(root)}
            result = subprocess.run(['/usr/bin/perl', '-f', str(fixture)],
                                    input=b''.join(value.hex().encode('ascii') + b'\n' for value in values),
                                    cwd=root, env=environment, capture_output=True, timeout=10, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, b'')
            outcomes = result.stdout.splitlines()
            self.assertEqual(len(outcomes), len(values))
            self.assertTrue(all(outcome in (b'0', b'1') for outcome in outcomes))
            return [outcome == b'1' for outcome in outcomes]

    def test_phase_predicate_accepts_exact_ascii_byte_alphabet(self):
        alphabet = frozenset(b'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./@+:-')
        self.assertEqual(len(alphabet), 69)
        values = [bytes((value,)) for value in range(256)]
        values += [b'prefix/' + bytes((value,)) + b'@suffix' for value in range(256)]
        expected = [value in alphabet for value in range(256)] * 2
        self.assertEqual(self.predicate_results(values), expected)

    def test_phase_predicate_requires_nonempty_complete_multichar_value(self):
        accepted = (b'late-command', b'hook/base@00+v1:render', b'-._/@+:',
                    b'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789', b'a' * 4096)
        rejected = (b'', b'late command', b'\x00late-command', b'late-command\x00',
                    b'\nlate-command', b'late-command\n', b'late\rcommand',
                    b'late\tcommand', b'late;command', b'late$command', b'late[command]',
                    'caf\u00e9'.encode('utf-8'), '\uff0flate'.encode('utf-8'))
        self.assertEqual(self.predicate_results(accepted + rejected),
                         [True] * len(accepted) + [False] * len(rejected))

    def test_complete_source_and_both_suite_archive_renderers_compile(self):
        source = RENDERER.read_bytes()
        source_sha256 = hashlib.sha256(source).hexdigest()
        member = 'scripts/common/render.pl'
        repository_di = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory(prefix='publication-phase-archive-', dir='/workspace') as temporary:
            root = Path(temporary)
            candidates = [('authored', RENDERER)]
            for suite in ('forky', 'trixie'):
                suite_root = repository_di / suite
                rows = (suite_root / 'payload.manifest').read_text(encoding='utf-8').splitlines()
                self.assertEqual(rows[0], 'format=3')
                records = [row.split('\t') for row in rows[1:] if row.split('\t')[-1] == member]
                self.assertEqual(records, [[str(len(source)), source_sha256, member]])
                with tarfile.open(suite_root / 'payload.tar.gz', 'r:gz') as archive:
                    members = [info for info in archive.getmembers() if info.name == member]
                    self.assertEqual(len(members), 1)
                    self.assertTrue(members[0].isfile())
                    self.assertEqual(members[0].size, len(source))
                    data = archive.extractfile(members[0]).read(len(source) + 1)
                self.assertEqual(data, source, suite + ' archive renderer differs from authored source')
                candidate = root / (suite + '-render.pl')
                private_write(candidate, data)
                candidates.append((suite, candidate))
            environment = {'PATH': '/unavailable', 'HOME': str(root), 'LC_ALL': 'C',
                           'TMPDIR': str(root), 'TMP': str(root), 'TEMP': str(root)}
            for label, candidate in candidates:
                with self.subTest(renderer=label):
                    result = subprocess.run(['/usr/bin/perl', '-f', '-c', str(candidate)],
                                            cwd=root, env=environment, capture_output=True,
                                            timeout=10, check=False)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn(b'syntax OK', result.stderr)
                    self.assertEqual(result.stdout, b'')
            self.assertEqual(sorted(path.name for path in root.iterdir()),
                             ['forky-render.pl', 'trixie-render.pl'])

    def check_phase(self, phase, expected_error):
        with tempfile.TemporaryDirectory(prefix='publication-phase-', dir='/workspace') as temporary:
            root = Path(temporary)
            prepared, target = root / 'prepared', root / 'target'
            # An empty plan deliberately stops after all context validation.
            # No target path is passed to publication_destination or written.
            work = plan_fixture(prepared, target, [], phase=phase)
            result = run_fixture(prepared, work)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(expected_error, result.stderr)
            self.assertEqual(list(target.iterdir()), [])
            self.assertFalse((work / 'ownership.pending').exists())
            self.assertFalse((work / 'ownership.tsv').exists())

    def test_declared_phase_punctuation_reaches_plan_validation(self):
        for phase in ('late-command', 'hook-base-00rendertarget', 'base/stage@hook+1:render'):
            with self.subTest(phase=phase):
                self.check_phase(phase, b'empty publication plan')

    def test_unsafe_phase_characters_fail_before_plan_validation(self):
        for phase in ('', 'late command', 'late;command', 'late$command', 'late[command]'):
            with self.subTest(phase=phase):
                self.check_phase(phase, b'invalid selected publication context')


class PublicationBatchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='publication-batch-', dir='/var/lib')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.prepared = self.root / 'prepared'
        self.source = self.prepared / 'source'
        self.source.mkdir(parents=True)
        self.target = self.root / 'target'
        self.target.mkdir(mode=0o700)

    def asset(self, name, data):
        path = self.source / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        path.chmod(0o644)
        return path

    def batch(self, operations, *, succeeds=True, **context):
        work = plan_fixture(self.prepared, self.target, operations, **context)
        result = run_fixture(self.prepared, work)
        self.assertEqual(result.returncode == 0, succeeds, result.stderr.decode(errors='replace'))
        return work, result

    def metrics(self, work):
        return dict(line.split('=', 1) for line in (work / 'report').read_text().splitlines())

    def test_many_destinations_share_one_source_read_and_one_interpreter(self):
        self.asset('hooks/target/fixture', b'fixture bytes\n')
        operations = [('plain', 'fixture', f'/etc/fixture-{number}', '0644', ()) for number in range(250)]
        work, result = self.batch(operations)
        metrics = self.metrics(work)
        self.assertEqual(metrics['source_reads'], '1')
        self.assertEqual(metrics['input_bytes'], str(len(b'fixture bytes\n')))
        self.assertEqual(metrics['perl_launches'], '1')
        self.assertEqual(metrics['written_files'], '250')
        self.assertEqual(metrics['output_bytes'], str(250 * len(b'fixture bytes\n')))
        self.assertEqual(len((work / 'ownership.tsv').read_text().splitlines()), 250)
        for number in range(250):
            path = self.target / f'etc/fixture-{number}'
            self.assertEqual(path.read_bytes(), b'fixture bytes\n')
            self.assertEqual(path.stat().st_mode & 0o7777, 0o644)
            self.assertEqual((path.stat().st_uid, path.stat().st_gid, path.stat().st_nlink), (0, 0, 1))
        # PATH is deliberately empty of executables: the real publisher must
        # not spawn sed, find, sha256sum, a shell or a second interpreter.
        self.assertNotIn(b'not found', result.stderr)

    def test_primary_account_and_future_account_defaults_have_distinct_values(self):
        self.asset('hooks/target/account.tmpl', b'__ACCOUNT_USERNAME__|__ACCOUNT_HOME__|__DIR_HOME_DOWNLOADS__|$RUNTIME\n')
        self.batch([('scalar', 'account.tmpl', '/etc/skel-desktop/account.conf', '0600',
                     ('ACCOUNT_USERNAME', 'alice', 'ACCOUNT_HOME', '/home/alice',
                      'DIR_HOME_DOWNLOADS', '/home/alice/Downloads'))])
        current = self.target / 'var/lib/installer/primary-defaults/desktop/account.conf'
        future = self.target / 'etc/skel-desktop/account.conf'
        self.assertEqual(current.read_bytes(), b'alice|/home/alice|/home/alice/Downloads|$RUNTIME\n')
        self.assertEqual(future.read_bytes(), b'$USER|$HOME|$HOME/Downloads|$RUNTIME\n')
        self.assertEqual(current.stat().st_mode & 0o777, 0o600)
        self.assertEqual(future.stat().st_mode & 0o777, 0o600)
        self.assertEqual((self.target / 'etc/skel-desktop').stat().st_mode & 0o777, 0o700)
        self.assertEqual(current.parent.stat().st_mode & 0o777, 0o700)

    def test_declared_blocks_render_together_and_duplicate_block_prevents_all_publication(self):
        source = 'hooks/target/etc/skel-desktop/.config/labwc/rc.xml.tmpl'
        data = (b'<root>\n__INSTALLER_LABWC_WORKSPACE_NAME_LINES__\n'
                b'__INSTALLER_LABWC_WORKSPACE_KEYBIND_LINES__\n'
                b'__INSTALLER_LABWC_RECORDING_KEYBIND_LINES__\n</root>\n')
        path = self.asset(source, data)
        pairs = ('BLOCK_LABWC_WORKSPACE_NAME_LINES', 'a\nb',
                 'BLOCK_LABWC_WORKSPACE_KEYBIND_LINES', 'c',
                 'BLOCK_LABWC_RECORDING_KEYBIND_LINES', '')
        operation = ('scalar-blocks', source, '/etc/skel-desktop/rc.xml', '0644', pairs)
        self.batch([operation])
        output = self.target / 'etc/skel-desktop/rc.xml'
        self.assertEqual(output.read_bytes(), b'<root>\na\nb\nc\n</root>\n')
        previous = output.read_bytes()
        path.write_bytes(data + b'__INSTALLER_LABWC_WORKSPACE_NAME_LINES__\n')
        work, _ = self.batch([operation], succeeds=False)
        self.assertEqual(output.read_bytes(), previous)
        self.assertTrue((work / 'plan').exists())
        self.assertFalse((work / 'ownership.tsv').exists())

    def test_supported_suite_family_contexts_preserve_binary_data(self):
        data = bytes(range(256)) * 64
        self.asset('hooks/target/icon.png', data)
        for suite, family in (('forky', 'desktop'), ('forky', 'server'), ('trixie', 'server')):
            with self.subTest(suite=suite, family=family):
                self.batch([('plain', 'icon.png', f'/usr/share/{suite}-{family}.png', '0644', ())],
                           suite=suite, family=family)
                self.assertEqual((self.target / f'usr/share/{suite}-{family}.png').read_bytes(), data)

    def test_one_unknown_member_rejects_the_complete_batch_before_writing(self):
        self.asset('hooks/target/valid', b'valid\n')
        self.batch([('plain', 'valid', '/etc/valid', '0644', ()),
                    ('plain', 'missing', '/etc/missing', '0644', ())], succeeds=False)
        self.assertFalse((self.target / 'etc/valid').exists())

    def test_dynamic_members_resolve_selected_family_systemd_and_suite_once(self):
        assets = {
            'hooks/target/usr/local/lib/common/fixture.py': b'common\n',
            'hooks/target/usr/local/share/desktop/fixture.tmpl': b'desktop\n',
            'hooks/target/etc/systemd/common/system/fixture.service': b'common unit\n',
            'frontends/forky/hooks/target/etc/apt/apt.conf.d/10-fixture': b'common apt\n',
            'frontends/forky/hooks/target/etc/apt/desktop/preferences.d/fixture': b'desktop apt\n',
            'hooks/target/etc/skel-desktop/Local State': b'spaced name\n',
        }
        for name, data in assets.items():
            self.asset(name, data)
        work, _ = self.batch([
            ('plain', 'usr/local/lib/fixture.py', '/usr/local/lib/fixture.py', '0644', ()),
            ('plain', 'usr/local/share/fixture', '/usr/local/share/fixture', '0644', ()),
            ('plain', 'etc/systemd/system/fixture.service', '/etc/systemd/system/fixture.service', '0644', ()),
            ('plain', 'etc/apt/apt.conf.d/10-fixture', '/etc/apt/apt.conf.d/10-fixture', '0644', ()),
            ('plain', 'etc/apt/preferences.d/fixture', '/etc/apt/preferences.d/fixture', '0644', ()),
            ('plain', 'hooks/target/etc/skel-desktop/Local State', '/etc/skel-desktop/Local State', '0600', ()),
        ])
        owned = {line.split('\t')[1] for line in (work / 'ownership.tsv').read_text().splitlines()}
        self.assertEqual(owned, set(assets))
        self.assertEqual(self.metrics(work)['source_reads'], '6')
        self.assertEqual((self.target / 'etc/skel-desktop/Local State').read_bytes(), b'spaced name\n')

    def test_ambiguous_family_and_wrong_role_or_suite_sources_reject_complete_batch(self):
        self.asset('hooks/target/valid', b'valid\n')
        self.asset('hooks/target/usr/local/lib/common/ambiguous', b'common\n')
        self.asset('hooks/target/usr/local/lib/desktop/ambiguous', b'desktop\n')
        self.asset('hooks/target/usr/local/lib/server/wrong', b'server\n')
        self.asset('hooks/target/etc/systemd/server/system/wrong.service', b'server unit\n')
        self.asset('frontends/forky/hooks/target/etc/apt/server/preferences.d/wrong', b'server apt\n')
        self.asset('frontends/trixie/hooks/target/etc/apt/desktop/preferences.d/wrong', b'other suite\n')
        self.asset('hooks/target/etc/skel-server/wrong', b'server template\n')
        for source in (
                'usr/local/lib/ambiguous', 'hooks/target/usr/local/lib/server/wrong',
                'hooks/target/etc/systemd/server/system/wrong.service',
                'frontends/forky/hooks/target/etc/apt/server/preferences.d/wrong',
                'frontends/trixie/hooks/target/etc/apt/desktop/preferences.d/wrong',
                'hooks/target/etc/skel-server/wrong'):
            with self.subTest(source=source):
                self.batch([('plain', 'valid', '/etc/valid', '0644', ()),
                            ('plain', source, '/etc/wrong', '0644', ())], succeeds=False)
                self.assertFalse((self.target / 'etc/valid').exists())
                self.assertFalse((self.target / 'etc/wrong').exists())

    def test_symlinks_hardlinks_and_unsafe_ancestry_do_not_modify_protected_bytes(self):
        self.asset('hooks/target/valid', b'new\n')
        protected = self.root / 'protected'
        protected.write_bytes(b'protected\n')
        parent = self.target / 'etc'
        parent.mkdir()
        destination = parent / 'unsafe'
        for kind in ('symlink', 'dangling', 'hardlink', 'directory', 'parent-symlink', 'parent-mode'):
            with self.subTest(kind=kind):
                if kind == 'symlink': destination.symlink_to(protected)
                elif kind == 'dangling': destination.symlink_to(self.root / 'missing')
                elif kind == 'hardlink': os.link(protected, destination)
                elif kind == 'directory': destination.mkdir()
                elif kind == 'parent-symlink':
                    destination.symlink_to(self.root, target_is_directory=True)
                elif kind == 'parent-mode':
                    destination.mkdir(mode=0o777)
                    destination.chmod(0o777)
                logical = '/etc/unsafe/protected' if kind.startswith('parent-') else '/etc/unsafe'
                self.batch([('plain', 'valid', '/etc/first', '0644', ()),
                            ('plain', 'valid', logical, '0644', ())], succeeds=False)
                self.assertEqual(protected.read_bytes(), b'protected\n')
                self.assertFalse((parent / 'first').exists())
                if destination.is_symlink() or destination.is_file(): destination.unlink()
                else: destination.rmdir()

    def test_prepared_source_mutation_and_identity_mismatch_are_rejected(self):
        source = self.asset('hooks/target/valid', b'valid\n')
        work = plan_fixture(self.prepared, self.target, [('plain', 'valid', '/etc/output', '0644', ())])
        other = self.root / 'other'
        os.link(source, other)
        result = run_fixture(self.prepared, work)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.target / 'etc/output').exists())
        other.unlink()
        private_write(self.prepared / 'identity', f'verified-v1 {"c" * 64} {"b" * 64} /fixture-seed\n'.encode())
        work, result = self.batch([('plain', 'valid', '/etc/output', '0644', ())], succeeds=False)
        self.assertIn(b'another prepared payload', result.stderr)
        self.assertFalse((self.target / 'etc/output').exists())

    def test_repeated_publication_reuses_verified_perl_bytes_and_restores_changed_bytes(self):
        member = 'hooks/target/Fixture.pm'
        self.asset(member, b'package Fixture; 1;\n')
        target = self.target / 'usr/local/lib/perl5/site_perl/fixture/Fixture.pm'
        operation = ('plain', member, '/usr/local/lib/perl5/site_perl/fixture/Fixture.pm', '0644', ())
        self.batch([operation])
        private_write(self.prepared / 'inputs/published-assets.tsv', f'{member}\t{target}\t0644\n'.encode())
        identity = target.stat().st_ino
        work, _ = self.batch([operation])
        self.assertEqual(target.stat().st_ino, identity)
        self.assertEqual(self.metrics(work)['reused_files'], '1')
        self.assertEqual(self.metrics(work)['written_files'], '0')
        target.write_bytes(b'changed\n')
        work, _ = self.batch([operation])
        self.assertEqual(target.read_bytes(), b'package Fixture; 1;\n')
        self.assertEqual(self.metrics(work)['written_files'], '1')
        target.unlink()
        self.batch([operation])
        self.assertEqual(target.read_bytes(), b'package Fixture; 1;\n')

    def test_malformed_length_duplicate_fields_and_unsupported_context_fail_closed(self):
        self.asset('hooks/target/valid', b'__VALUE__\n')
        for corruption in ('length', 'duplicate', 'context', 'traversal', 'old-identity'):
            with self.subTest(corruption=corruption):
                work = plan_fixture(self.prepared, self.target, [('scalar', 'valid', '/etc/output', '0644', ('VALUE', 'one'))])
                if corruption == 'length':
                    data = (work / 'plan').read_bytes()
                    private_write(work / 'plan', data[:-1])
                elif corruption == 'duplicate':
                    private_write(work / 'plan', b'publication-plan-v1\n' + fields((
                        'scalar', 'valid', str(self.target / 'etc/output'), '0644', '0:0',
                        'desktop', 'forky', 'late-command', 'fixture-assets', 'VALUE', 'one', 'VALUE', 'two')))
                elif corruption == 'context':
                    with (work / 'context').open('ab') as stream: stream.write(b'UNKNOWN=value\n')
                elif corruption == 'traversal':
                    private_write(work / 'plan', b'publication-plan-v1\n' + fields((
                        'plain', 'valid', str(self.target) + '/etc/../outside', '0644', '0:0',
                        'desktop', 'forky', 'late-command', 'fixture-assets')))
                else:
                    private_write(self.prepared / 'identity', f'{ARCHIVE} {"b" * 64} /fixture-seed\n'.encode())
                result = run_fixture(self.prepared, work)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.target / 'etc/output').exists())
                self.assertFalse((work / 'ownership.tsv').exists())

    def test_failed_write_keeps_previous_file_and_retains_the_plan(self):
        self.asset('hooks/target/large', b'x' * 8192)
        output = self.target / 'etc/output'
        output.parent.mkdir()
        output.write_bytes(b'previous\n')
        work = plan_fixture(self.prepared, self.target, [('plain', 'large', '/etc/output', '0644', ())])
        def limit_writes():
            resource.setrlimit(resource.RLIMIT_FSIZE, (4096, 4096))
        result = run_fixture(self.prepared, work, preexec_fn=limit_writes)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(output.read_bytes(), b'previous\n')
        self.assertTrue((work / 'plan').is_file())
        self.assertTrue((work / 'ownership.pending').is_file())
        self.assertFalse((work / 'ownership.tsv').exists())


if __name__ == '__main__':
    unittest.main()
