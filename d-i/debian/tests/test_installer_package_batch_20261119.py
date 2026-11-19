"""Package batching boundaries; run only inside the reviewed disposable image.

Signing, index publication and APT are explicit doubles. Filesystem snapshots,
input parsing, checksums, identity validation and the publication barrier are
the production implementations. These fixtures never invoke a package install.
"""
from __future__ import annotations

from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation
require_test_isolation()

import copy
import hashlib
import io
import json
import os
import re
import shlex
import shutil
import tarfile
import tempfile
import types
import unittest
from functools import lru_cache
from unittest import mock
from fixture_render import rendered_path_text


SEED = Path(__file__).resolve().parents[1]
SOURCE = SEED / 'hooks/target/usr/local/libexec/common/apt-repo-local.tmpl'


@lru_cache(maxsize=1)
def compiled_package_fixture_values():
    """Read scalar fixture values from the same built profile as path values."""
    member = 'catalog/compiled/forky/profiles/desktop/btrfs-de-p15s.env'
    with tarfile.open(SEED.parent / 'forky/payload.tar.gz', 'r:gz') as archive:
        info = archive.getmember(member)
        if not info.isfile() or info.size > 1024 * 1024:
            raise ValueError('invalid compiled fixture profile')
        text = archive.extractfile(info).read().decode('utf-8')
    values = {}
    for line in text.splitlines():
        if line and not line.startswith('#'):
            name, separator, raw = line.partition('=')
            words = shlex.split(raw)
            if not separator or len(words) != 1 or name in values:
                raise ValueError('invalid compiled fixture assignment')
            values[name] = words[0]
    return values


def publisher_module():
    values = compiled_package_fixture_values()
    source = rendered_path_text(SOURCE.read_text())
    source = re.sub(r'__INSTALLER_(SOFTWARE_[A-Z0-9_]+)__',
                    lambda match: values[match[1]], source)
    if '__INSTALLER_' in source:
        raise ValueError('unrendered package publisher fixture')
    module = types.ModuleType('installer_package_batch_fixture')
    exec(compile(source, str(SOURCE), 'exec'), module.__dict__)
    return module


class InstallerPackageBatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = publisher_module()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='package-batch-', dir='/workspace')
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.plan = self.directory / 'plan.tsv'
        self.receipt = self.directory / 'receipt.json'
        self.commands = []
        self.blocked = mock.patch.object(self.mod.subprocess, 'run',
                                        side_effect=AssertionError('unexpected native command'))
        self.blocked.start()
        self.addCleanup(self.blocked.stop)

    def package(self, name='fixture-one'):
        source = self.directory / (name + '.deb')
        source.write_bytes(b'!<arch>\n' + name.encode() + b'\n')
        source.chmod(0o600)
        return source

    def row(self, source, package='fixture-one', member='/usr/bin/fixture', digest=None):
        digest = digest or hashlib.sha256(source.read_bytes()).hexdigest()
        return '\t'.join((str(source), package, 'amd64', member, '-', '-', digest, '1.0', 'Fixture'))

    def write_plan(self, *rows):
        self.plan.write_text('installer-deb-plan-v1\n' + '\n'.join(rows) + '\n')
        self.plan.chmod(0o600)

    def repository(self):
        repository = self.mod.Repository.__new__(self.mod.Repository)
        repository.root = self.directory / 'software'
        repository.root.mkdir(mode=0o700)
        repository.repo = repository.root / 'repo'
        repository.repo.mkdir(mode=0o755)
        repository.inbox = repository.root / 'inbox'
        repository.inbox.mkdir(mode=0o700)
        repository.etc = self.directory / 'etc'
        repository.policy_file = repository.etc / 'no-policy.json'
        repository.signing = repository.root / 'signing'
        repository.architectures = {'amd64'}
        repository.catalog = {'format': 1, 'packages': {}, 'disabled_seeds': []}
        repository.pending = []
        repository.staged_digests = {}
        repository.staged_inspections = {}
        repository.changed = False
        repository.signing_key = mock.Mock(return_value='A' * 40)
        repository.publish = mock.Mock(side_effect=repository.finish_inbox)
        return repository

    def command(self, argv, **kwargs):
        self.commands.append(argv)
        if argv[0].endswith('/dpkg') and argv[1] == '--validate-version':
            return b''
        if argv[0].endswith('/dpkg-deb'):
            package = Path(argv[2]).read_bytes().splitlines()[1].decode()
            if argv[1] == '--field':
                return (f'Package: {package}\nVersion: 1.0\nArchitecture: amd64\n'
                        'Description: fixture\n').encode()
            if argv[1] == '--contents':
                return b'-rwxr-xr-x root/root 1 2026-11-19 00:00 ./usr/bin/fixture\n'
        raise AssertionError('unexpected fixture command: ' + repr(argv))

    def fake_sign(self, source, destination, *unused, **options):
        shutil.copyfile(source, destination)
        destination.chmod(0o600)
        digest = hashlib.sha256(destination.read_bytes()).hexdigest()
        return digest, digest, self.mod.file_identity(destination.stat())

    def test_batch_inspects_each_snapshot_once_and_publishes_once(self):
        first, second = self.package(), self.package('fixture-two')
        self.write_plan(self.row(first), self.row(second, 'fixture-two'))
        repository = self.repository()
        with mock.patch.object(self.mod, 'run', side_effect=self.command), \
                mock.patch.object(self.mod, 'sign_deb_archive', side_effect=self.fake_sign), \
                mock.patch.object(self.mod, 'digest_file', wraps=self.mod.digest_file) as digests:
            paths = repository.import_installer_plan(self.plan, self.receipt)
        self.assertEqual(len(paths), 2)
        self.assertEqual(sum('--field' in command for command in self.commands), 2)
        self.assertEqual(sum('--contents' in command for command in self.commands), 2)
        # Each copy owner returns its actual byte digest. The signing boundary
        # has separate production fixtures below, including signature padding.
        self.assertEqual(digests.call_count, 0)
        repository.publish.assert_called_once_with()
        self.assertEqual(list(repository.inbox.iterdir()), [])
        receipt = json.loads(self.receipt.read_text())
        self.assertEqual([item['package'] for item in receipt['packages']],
                         ['fixture-one', 'fixture-two'])

    def test_missing_member_in_later_input_never_publishes_partial_batch(self):
        first, second = self.package(), self.package('fixture-two')
        self.write_plan(self.row(first), self.row(second, 'fixture-two', '/usr/bin/missing'))
        repository = self.repository()
        before = copy.deepcopy(repository.catalog)
        with mock.patch.object(self.mod, 'run', side_effect=self.command), \
                mock.patch.object(self.mod, 'sign_deb_archive', side_effect=self.fake_sign), \
                self.assertRaisesRegex(self.mod.Error, 'required member'):
            repository.import_installer_plan(self.plan, self.receipt)
        repository.publish.assert_not_called()
        self.assertEqual(repository.catalog, before)
        self.assertEqual(repository.pending, [])
        self.assertFalse(self.receipt.exists())
        self.assertEqual(list(repository.inbox.iterdir()), [])

    def test_untrusted_expected_digest_is_compared_with_actual_snapshot(self):
        source = self.package()
        self.write_plan(self.row(source, digest='0' * 64))
        repository = self.repository()
        with mock.patch.object(self.mod, 'run', side_effect=self.command), \
                mock.patch.object(self.mod, 'sign_deb_archive') as signer, \
                self.assertRaisesRegex(self.mod.Error, 'SHA-256'):
            repository.import_installer_plan(self.plan, self.receipt)
        signer.assert_not_called()
        repository.publish.assert_not_called()

    def test_snapshot_identity_change_invalidates_in_memory_digest(self):
        source = self.package()
        repository = self.repository()
        staged = repository.stage(source, active=False)
        with mock.patch.object(self.mod, 'run', side_effect=self.command):
            repository.inspect_snapshot(staged)
        replacement = repository.inbox / 'replacement'
        replacement.write_bytes(staged.read_bytes())
        replacement.chmod(0o600)
        os.replace(replacement, staged)
        with self.assertRaisesRegex(self.mod.Error, 'snapshot changed'):
            repository.snapshot_digest(staged)
        with self.assertRaisesRegex(self.mod.Error, 'snapshot changed'):
            repository.activate(staged)
        with self.assertRaisesRegex(self.mod.Error, 'snapshot changed'):
            repository.inspect_snapshot(staged)

    def test_inspection_reused_only_for_the_same_private_snapshot_and_requirements(self):
        source = self.package()
        repository = self.repository()
        staged = repository.stage(source, active=False)
        with mock.patch.object(self.mod, 'run', side_effect=self.command), \
                mock.patch.object(self.mod, 'sign_deb_archive', side_effect=self.fake_sign):
            fields = repository.inspect_snapshot(staged)
            fields['Version'] = '999.0'  # Returned metadata cannot mutate the receipt.
            ready = repository.activate(staged, expected=('fixture-one', 'amd64'))
            record = repository.ingest(ready)
        self.assertEqual(record['version'], '1.0')
        self.assertEqual(sum('--field' in command for command in self.commands), 1)
        self.assertEqual(sum('--contents' in command for command in self.commands), 1)
        self.assertNotIn(staged, repository.staged_inspections)
        repository.finish_inbox()
        self.assertFalse(repository.staged_inspections)
        self.assertFalse(repository.staged_digests)

    def test_changed_member_requirements_cannot_reuse_an_incomplete_inspection(self):
        repository = self.repository()
        staged = repository.stage(self.package(), active=False)
        with mock.patch.object(self.mod, 'run', side_effect=self.command):
            repository.inspect_snapshot(staged, required_members=('/usr/bin/fixture',))
            with self.assertRaisesRegex(self.mod.Error, 'required member'):
                repository.inspect_snapshot(staged, required_members=('/usr/bin/missing',))
        self.assertEqual(sum('--contents' in command for command in self.commands), 2)

    def test_activation_replacement_or_mutation_revokes_evidence_and_quarantines(self):
        repository = self.repository()
        source = self.package()
        replace = self.mod.os.replace
        for kind in ('replacement', 'mutation'):
            with self.subTest(kind=kind):
                staged = repository.stage(source, active=False)
                with mock.patch.object(self.mod, 'run', side_effect=self.command):
                    repository.inspect_snapshot(staged)
                ready = staged.with_suffix('.deb')
                def changed_rename(old, new):
                    replace(old, new)
                    if Path(old) != staged or Path(new) != ready:
                        return
                    if kind == 'replacement':
                        replacement = repository.inbox / 'replacement.part'
                        replacement.write_bytes(ready.read_bytes())
                        replacement.chmod(0o600)
                        replace(replacement, ready)
                    else:
                        before = ready.stat()
                        ready.write_bytes(b'X' * before.st_size)
                        os.utime(ready, ns=(before.st_atime_ns, before.st_mtime_ns + 1))
                with mock.patch.object(self.mod.os, 'replace', side_effect=changed_rename), \
                        self.assertRaisesRegex(self.mod.Error, 'changed during activation'):
                    repository.activate(staged, expected=('fixture-one', 'amd64'))
                self.assertFalse(repository.staged_digests)
                self.assertFalse(repository.staged_inspections)
                self.assertFalse(ready.exists())
                self.assertFalse(list(repository.inbox.glob('*.deb')))
        retained = list(repository.inbox.glob('.activation-failed-*.part'))
        self.assertEqual(len(retained), 2)
        self.assertTrue(all(Path(str(path) + '.json').is_file() for path in retained))
        repository.publish.assert_not_called()

    def test_post_rename_sync_failure_cannot_leave_a_watchable_input(self):
        repository = self.repository()
        staged = repository.stage(self.package(), active=False)
        sync = self.mod.fsync_dir
        failed = False
        def fail_ready_sync(directory):
            nonlocal failed
            if not failed and list(repository.inbox.glob('*.deb')):
                failed = True
                raise OSError('fixture activation synchronization failure')
            return sync(directory)
        with mock.patch.object(self.mod, 'fsync_dir', side_effect=fail_ready_sync), \
                self.assertRaisesRegex(OSError, 'synchronization failure'):
            repository.activate(staged, expected=('fixture-one', 'amd64'))
        self.assertFalse(list(repository.inbox.glob('*.deb')))
        self.assertEqual(len(list(repository.inbox.glob('.activation-failed-*.part'))), 1)
        self.assertFalse(repository.staged_digests)

    def test_failed_activation_isolation_retains_evidence_as_outcome_unknown(self):
        repository = self.repository()
        staged = repository.stage(self.package(), active=False)
        ready = staged.with_suffix('.deb')
        replace = self.mod.os.replace
        def reject_isolation(old, new):
            if Path(old) == ready:
                raise OSError('fixture cannot isolate ready input')
            replace(old, new)
            if Path(old) == staged:
                with ready.open('ab') as stream:
                    stream.write(b'changed')
        with mock.patch.object(self.mod.os, 'replace', side_effect=reject_isolation), \
                self.assertRaisesRegex(self.mod.OutcomeUnknown, 'could not be isolated'):
            repository.activate(staged, expected=('fixture-one', 'amd64'))
        self.assertTrue(ready.is_file())
        self.assertTrue(Path(str(ready) + '.json').is_file())
        self.assertFalse(repository.staged_digests)
        self.assertFalse(repository.staged_inspections)
        repository.publish.assert_not_called()

    def test_independent_inbox_delivery_never_uses_a_process_local_inspection(self):
        repository = self.repository()
        delivered = repository.inbox / 'delivered.deb'
        shutil.copyfile(self.package(), delivered)
        delivered.chmod(0o600)
        with mock.patch.object(self.mod, 'run', side_effect=self.command):
            repository.inspect_snapshot(delivered)
            repository.inspect_snapshot(delivered)
        self.assertEqual(sum('--contents' in command for command in self.commands), 2)
        self.assertFalse(repository.staged_inspections)

    def test_mutation_during_inspection_never_creates_a_reusable_receipt(self):
        repository = self.repository()
        staged = repository.stage(self.package(), active=False)
        def mutate_listing(argv, **kwargs):
            result = self.command(argv, **kwargs)
            if '--contents' in argv:
                with staged.open('ab') as stream:
                    stream.write(b'changed')
            return result
        with mock.patch.object(self.mod, 'run', side_effect=mutate_listing), \
                self.assertRaisesRegex(self.mod.Error, 'changed during inspection'):
            repository.inspect_snapshot(staged)
        self.assertFalse(repository.staged_inspections)

    def test_transformed_bytes_keep_their_own_inspection_and_digest(self):
        repository = self.repository()
        staged = repository.stage(self.package(), active=False)
        def transformed(source, destination, *args, **kwargs):
            destination.write_bytes(source.read_bytes() + b'fixture transformed bytes\n')
            destination.chmod(0o600)
        with mock.patch.object(self.mod, 'run', side_effect=self.command), \
                mock.patch.object(self.mod, 'rewrite_depends', side_effect=transformed), \
                mock.patch.object(self.mod, 'sign_deb_archive', side_effect=self.fake_sign):
            repository.inspect_snapshot(staged)
            result = repository.ingest(staged, policy={'local_revision': 1})
        self.assertEqual(sum('--field' in command for command in self.commands), 2)
        self.assertEqual(sum('--contents' in command for command in self.commands), 2)
        self.assertNotEqual(result['upstream_sha256'], result['transformed_sha256'])

    def test_transformation_cannot_change_the_input_bound_to_the_upstream_digest(self):
        repository = self.repository()
        staged = repository.stage(self.package(), active=False)
        def changed_input(source, destination, *args, **kwargs):
            destination.write_bytes(source.read_bytes() + b'transformed\n')
            destination.chmod(0o600)
            with source.open('ab') as stream:
                stream.write(b'changed upstream')
        with mock.patch.object(self.mod, 'run', side_effect=self.command), \
                mock.patch.object(self.mod, 'rewrite_depends', side_effect=changed_input), \
                mock.patch.object(self.mod, 'sign_deb_archive') as signer, \
                self.assertRaisesRegex(self.mod.Error, 'upstream snapshot changed during transformation'):
            repository.ingest(staged, policy={'local_revision': 1})
        signer.assert_not_called()
        self.assertFalse(repository.catalog['packages'])
        self.assertFalse(repository.pending)

    def test_retained_copy_cannot_publish_bytes_from_a_changed_upstream_snapshot(self):
        repository = self.repository()
        staged = repository.stage(self.package(), active=False)
        identity = repository.snapshot_identity(staged)
        digest = repository.snapshot_digest(staged)
        copyfile = self.mod.shutil.copyfile
        def changed_input(source, destination, **kwargs):
            result = copyfile(source, destination, **kwargs)
            with source.open('ab') as stream:
                stream.write(b'changed upstream')
            return result
        with mock.patch.object(self.mod.shutil, 'copyfile', side_effect=changed_input), \
                self.assertRaisesRegex(self.mod.Error, 'upstream snapshot changed while retaining'):
            repository.retain_upstream(staged, 'fixture-one', digest, expected_identity=identity)
        self.assertFalse(list((repository.root / 'upstream').rglob('*.deb')))

    def test_same_size_corrupt_retained_bytes_are_rejected(self):
        source = self.package()
        repository = self.repository()
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        relative = repository.retain_upstream(source, 'fixture-one', digest)
        retained = repository.root / relative
        retained.write_bytes(b'X' * source.stat().st_size)
        with self.assertRaisesRegex(self.mod.Error, 'digest mismatch'):
            repository.retain_upstream(source, 'fixture-one', digest)

    def test_plan_rejects_duplicate_malformed_and_unsafe_rows(self):
        source = self.package()
        row = self.row(source)
        cases = [row + '\n' + row, row.replace('amd64', 'all'),
                 row.replace('/usr/bin/fixture', '/usr/../bin/fixture'),
                 row.replace('/usr/bin/fixture', '/usr/bin/fixture\v'),
                 row + '\tunexpected', row.replace('1.0\t', 'bad version\t')]
        for candidate in cases:
            with self.subTest(candidate=candidate):
                self.write_plan(candidate)
                with self.assertRaises(self.mod.Error):
                    self.mod.installer_plan(self.plan)

    def test_member_listing_failure_propagates_before_publication(self):
        source = self.package()
        self.write_plan(self.row(source))
        repository = self.repository()
        def fail_listing(argv, **kwargs):
            if '--contents' in argv:
                raise self.mod.CommandFailure('fixture failed listing', 2)
            return self.command(argv, **kwargs)
        with mock.patch.object(self.mod, 'run', side_effect=fail_listing), \
                self.assertRaises(self.mod.CommandFailure):
            repository.import_installer_plan(self.plan, self.receipt)
        repository.publish.assert_not_called()

    def test_uncertain_publication_retains_private_partial_for_recovery(self):
        source = self.package()
        self.write_plan(self.row(source))
        repository = self.repository()
        repository.publish.side_effect = self.mod.OutcomeUnknown('fixture worker still owns output')
        with mock.patch.object(self.mod, 'run', side_effect=self.command), \
                mock.patch.object(self.mod, 'sign_deb_archive', side_effect=self.fake_sign), \
                self.assertRaises(self.mod.OutcomeUnknown):
            repository.import_installer_plan(self.plan, self.receipt)
        self.assertEqual(len(list(repository.inbox.glob('*.part'))), 1)
        self.assertFalse(list(repository.inbox.glob('*.deb')))
        self.assertFalse(self.receipt.exists())

    def test_interrupted_signing_cannot_activate_an_incomplete_batch(self):
        source = self.package()
        self.write_plan(self.row(source))
        repository = self.repository()
        child = os.fork()
        if child == 0:
            def interrupt_after_signing(original, destination, *unused, **options):
                self.fake_sign(original, destination)
                # Simulate abrupt loss after completed signing, bypassing the
                # importer's finally cleanup without running a native signer.
                os._exit(77)
            try:
                with mock.patch.object(self.mod, 'run', side_effect=self.command), \
                        mock.patch.object(self.mod, 'sign_deb_archive',
                                          side_effect=interrupt_after_signing):
                    repository.import_installer_plan(self.plan, self.receipt)
            finally:
                os._exit(78)
        _, status = os.waitpid(child, 0)
        self.assertEqual(os.waitstatus_to_exitcode(status), 77)
        self.assertTrue((self.directory / '.deb-batch-active').is_file())
        signed = list(repository.inbox.glob('.signed-*'))
        self.assertEqual(len(signed), 1)
        self.assertEqual(signed[0].suffix, '.part')
        self.assertEqual(list(repository.inbox.glob('*.deb')), [])
        with mock.patch.object(repository, 'ingest') as ingest:
            self.assertEqual(repository.process_inbox(), 0)
        ingest.assert_not_called()
        self.assertTrue(signed[0].is_file())
        self.assertFalse(self.receipt.exists())

    def test_installed_readiness_uses_one_query_and_rejects_partial_dpkg_state(self):
        executable = self.directory / 'fixture-executable'
        executable.write_text('fixture; never executed\n')
        executable.chmod(0o755)
        record = {'package': 'fixture-one', 'version': '1.0', 'architecture': 'amd64',
                  'upstream_version': '1.0', 'upstream_sha256': 'a' * 64,
                  'published_sha256': 'b' * 64, 'archive': str(self.directory / 'fixture.deb'),
                  'label': 'Fixture', 'executable': str(executable),
                  'desktop_file': '-', 'runtime_library': '-'}
        self.receipt.write_text(json.dumps({'format': 1, 'packages': [record]}))
        self.receipt.chmod(0o600)
        with mock.patch.object(self.mod, 'run', return_value=
                b'fixture-one\tamd64\t1.0\tinstall ok installed\n') as query:
            self.mod.verify_installer_receipt(self.receipt)
        query.assert_called_once()
        with mock.patch.object(self.mod, 'run', return_value=
                b'fixture-one\tamd64\t1.0\tinstall ok unpacked\n'), \
                self.assertRaisesRegex(self.mod.Error, 'not fully installed'):
            self.mod.verify_installer_receipt(self.receipt)
        executable.unlink()
        with mock.patch.object(self.mod, 'run', return_value=
                b'fixture-one\tamd64\t1.0\tinstall ok installed\n'), \
                self.assertRaisesRegex(self.mod.Error, 'missing executable'):
            self.mod.verify_installer_receipt(self.receipt)

    def test_symlink_or_hardlink_plan_is_rejected(self):
        source = self.package()
        self.write_plan(self.row(source))
        alias = self.directory / 'alias.tsv'
        os.link(self.plan, alias)
        with self.assertRaises(self.mod.Error):
            self.mod.installer_plan(self.plan)
        alias.unlink()
        alias.symlink_to(self.plan)
        with self.assertRaises(OSError):
            self.mod.installer_plan(alias)

    def test_shell_barrier_preserves_application_postwork_and_failure_evidence(self):
        text = (SEED / 'scripts/late/software.sh.tmpl').read_text()
        self.assertNotIn('software_deb_contains_path', text)
        self.assertNotIn('dpkg-deb -f', text)
        self.assertNotIn('dpkg-deb -c', text)
        self.assertNotIn('apt-repo-local rebuild', text)
        self.assertIn('import-plan --receipt', text)
        self.assertIn('verify-installed-plan --', text)
        self.assertIn('.deb-batch-active', text)
        barrier = text.index('\nsoftware_flush_deb_batch\n', text.index('software_begin_deb_batch desktop'))
        for app in ('bitwarden', 'qoredb', 'obsidian', 'tomat', 'sleek', 'filen'):
            self.assertLess(text.index(' software_prepare_' + app + '_app '), barrier)
            self.assertGreater(text.index(' software_finish_' + app + '_app '), barrier)
        self.assertIn('NEEDRESTART_SUSPEND=1', text)
        self.assertIn('install "$@"', text)


class SignedArchiveCopyTests(unittest.TestCase):
    """Exercise the actual signing copy; only OpenPGP output is a fixture."""

    @classmethod
    def setUpClass(cls):
        cls.mod = publisher_module()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='package-signing-', dir='/workspace')
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.source = self.directory / 'source.part'
        self.destination = self.directory / 'signed.part'
        archive = bytearray(b'!<arch>\n')
        for name, blob in (('debian-binary', b'2.0\n'), ('control.tar', b'fixture-control'),
                           ('data.tar', b'fixture-payload')):
            archive.extend(self.mod.ar_header(name, len(blob)))
            archive.extend(blob)
            if len(blob) % 2:
                archive.extend(b'\n')
        self.original = bytes(archive)
        self.source.write_bytes(self.original)
        self.source.chmod(0o600)
        self.signature = b'-----BEGIN PGP SIGNED MESSAGE-----\nfixture-signature\n'
        self.blocked = mock.patch.object(self.mod.subprocess, 'run',
                                        side_effect=AssertionError('unexpected native command'))
        self.blocked.start()
        self.addCleanup(self.blocked.stop)

    def signature_command(self, argv, **kwargs):
        self.assertTrue(argv[0].endswith('/gpg'))
        path = Path(argv[argv.index('--output') + 1])
        path.write_bytes(self.signature)
        path.chmod(0o600)
        return b''

    def sign(self):
        return self.mod.sign_deb_archive(
            self.source, self.destination, self.directory, 'A' * 40,
            expected_identity=self.mod.file_identity(self.source.stat()))

    def test_copy_digests_include_exact_header_signature_and_odd_padding(self):
        for odd in (False, True):
            with self.subTest(odd=odd):
                self.destination.unlink(missing_ok=True)
                if bool(len(self.signature) % 2) != odd:
                    self.signature += b'x'
                with mock.patch.object(self.mod, 'run', side_effect=self.signature_command), \
                        mock.patch.object(self.mod, 'digest_file',
                                          side_effect=AssertionError('extra full-file digest read')):
                    source_digest, signed_digest, identity = self.sign()
                expected = (self.original + self.mod.ar_header('_gpgorigin', len(self.signature))
                            + self.signature + (b'\n' if odd else b''))
                self.assertEqual(self.destination.read_bytes(), expected)
                self.assertEqual(source_digest, hashlib.sha256(self.original).hexdigest())
                self.assertEqual(signed_digest, hashlib.sha256(expected).hexdigest())
                self.assertEqual(identity, self.mod.file_identity(self.destination.stat()))
                self.assertEqual(self.destination.stat().st_mode & 0o777, 0o644)
                self.assertEqual(sorted(path.name for path in self.directory.iterdir()),
                                 ['signed.part', 'source.part'])

    def test_short_writes_hash_each_accepted_byte_once(self):
        class ShortWriter(io.BytesIO):
            def write(self, data):
                return super().write(data[:3])
        writer = ShortWriter()
        digest = hashlib.sha256()
        self.mod.write_hashed(writer, b'complete fixture bytes', digest)
        self.assertEqual(writer.getvalue(), b'complete fixture bytes')
        self.assertEqual(digest.hexdigest(), hashlib.sha256(writer.getvalue()).hexdigest())
        for result in (None, 0, -1, 999):
            with self.subTest(result=result), self.assertRaises(self.mod.Error):
                self.mod.write_hashed(mock.Mock(write=mock.Mock(return_value=result)),
                                      b'fixture', hashlib.sha256())

    def test_replaced_source_cannot_reuse_member_signature_or_digest(self):
        def replace_source(argv, **kwargs):
            result = self.signature_command(argv, **kwargs)
            replacement = self.directory / 'replacement.part'
            replacement.write_bytes(self.original)
            replacement.chmod(0o600)
            os.replace(replacement, self.source)
            return result
        with mock.patch.object(self.mod, 'run', side_effect=replace_source), \
                self.assertRaisesRegex(self.mod.Error, 'changed during signing'):
            self.sign()
        self.assertFalse(self.destination.exists())
        self.assertEqual([path.name for path in self.directory.iterdir()], ['source.part'])

    def test_write_failure_discards_only_unpublished_signing_scratch(self):
        original_write = self.mod.write_hashed
        writes = 0
        def fail_header(stream, data, digest):
            nonlocal writes
            writes += 1
            if writes == 2:
                raise OSError('fixture interrupted output')
            return original_write(stream, data, digest)
        with mock.patch.object(self.mod, 'run', side_effect=self.signature_command), \
                mock.patch.object(self.mod, 'write_hashed', side_effect=fail_header), \
                self.assertRaisesRegex(OSError, 'interrupted output'):
            self.sign()
        self.assertFalse(self.destination.exists())
        self.assertEqual(self.source.read_bytes(), self.original)
        self.assertEqual([path.name for path in self.directory.iterdir()], ['source.part'])

    def test_appended_signature_cannot_exceed_the_package_bound(self):
        with mock.patch.object(self.mod, 'run', side_effect=self.signature_command), \
                mock.patch.object(self.mod, 'MAX_DEB', len(self.original) + 60), \
                self.assertRaisesRegex(self.mod.Error, 'signed package exceeds size limit'):
            self.sign()
        self.assertFalse(self.destination.exists())
        self.assertEqual(self.source.read_bytes(), self.original)


if __name__ == '__main__':
    unittest.main()
