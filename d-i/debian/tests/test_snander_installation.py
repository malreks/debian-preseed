"""Firmware archive publication regressions; guarded image execution only."""
from __future__ import annotations

from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation
require_test_isolation()

import gzip
import hashlib
import io
import os
import tarfile
import tempfile
import time
import types
import unittest
from unittest import mock


SOURCE = Path(__file__).resolve().parents[1] / 'scripts/common/snander-install.py.tmpl'


@unittest.skipUnless(os.geteuid() == 0, 'firmware publication requires uid 0 inside the guarded image')
class FirmwareArchivePublication(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='snander-publication-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        boot = self.root / 'proc/sys/kernel/random/boot_id'
        boot.parent.mkdir(parents=True)
        boot.write_text('fixture-boot\n', encoding='ascii')
        self.program = types.ModuleType('snander_fixture')
        # This fixture materializes only the kernel-data path read by install.
        # All publication roots are private fixture paths assigned below.
        source = SOURCE.read_text(encoding='utf-8').replace(
            '__INSTALLER_PATH_DIR_PROC__', str(self.root / 'proc'))
        exec(compile(source, str(SOURCE), 'exec'), self.program.__dict__)
        self.program.STATE = self.root / 'state'
        self.program.STATE.mkdir(mode=0o700)
        self.program.RELEASES = self.root / 'releases'
        self.program.PENDING = self.program.STATE / 'pending.json'
        self.program.ENTRY = self.root / 'bin/SNANDer'
        self.program.ENTRY.parent.mkdir()
        binary = bytearray(64)
        binary[:6] = b'\x7fELF\x02\x01'
        binary[18:20] = (62).to_bytes(2, 'little')
        self.binary = bytes(binary)
        self.commit = 'a' * 40
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode='w', format=tarfile.USTAR_FORMAT) as archive:
            for name, content in (('Linux/SNANDer', self.binary), ('LICENSE', b'fixture license\n'),
                                  ('readme.txt', b'fixture readme\n'), ('flash_support_list.txt', b'fixture data\n')):
                member = tarfile.TarInfo('SNANDer-' + self.commit + '/' + name)
                member.size = len(content)
                archive.addfile(member, io.BytesIO(content))
        self.archive = gzip.compress(data.getvalue(), mtime=0)
        self.policy = {'format': 1, 'version': '1.2.3.4', 'commit': self.commit,
                       'url': 'https://fixture.invalid/' + self.commit, 'hosts': 'fixture.invalid',
                       'sha256': hashlib.sha256(self.archive).hexdigest(),
                       'binary_sha256': hashlib.sha256(self.binary).hexdigest()}

    def download(self, _value, destination, _lock):
        # Only external transport is mocked. No vendor program is executed.
        destination.write_bytes(self.archive)
        destination.chmod(0o600)

    def install(self, policy=None, deadline=None, download=None):
        with mock.patch.object(self.program, 'download', download or self.download):
            self.program.install(policy or self.policy, 0,
                                 time.monotonic() + 30 if deadline is None else deadline)

    def test_authenticated_archive_is_retained_and_release_is_reused(self):
        self.install()
        release = self.program.RELEASES / self.policy['version']
        archived = release / 'source' / ('SNANDer-' + self.commit + '.tar.gz')
        binary = release / 'bin/SNANDer'
        self.assertEqual(archived.read_bytes(), self.archive)
        self.assertEqual(binary.read_bytes(), self.binary)
        self.assertEqual(binary.stat().st_mode & 0o7777, 0o755)
        self.assertEqual(archived.stat().st_mode & 0o7777, 0o644)
        self.assertEqual(self.program.ENTRY.readlink(), binary)
        before = (archived.stat().st_ino, binary.stat().st_ino)
        self.install(download=mock.Mock(side_effect=AssertionError('unexpected second download')))
        self.assertEqual((archived.stat().st_ino, binary.stat().st_ino), before)
        self.assertFalse(self.program.PENDING.exists())
        self.assertFalse(list(self.program.RELEASES.glob('.release-*')))

    def test_failed_candidates_preserve_the_previous_release_and_entry(self):
        self.install()
        previous = self.program.ENTRY.readlink()
        identity = previous.stat().st_ino
        for failure in ('digest', 'deadline', 'hardlink'):
            with self.subTest(failure=failure):
                policy = {**self.policy, 'version': '1.2.3.5'}
                deadline = time.monotonic() - 1 if failure == 'deadline' else time.monotonic() + 30
                if failure == 'digest':
                    policy['sha256'] = '0' * 64
                protected = self.root / 'protected-archive'
                def download(value, destination, lock):
                    self.download(value, destination, lock)
                    if failure == 'hardlink':
                        os.link(destination, protected)
                with self.assertRaises(ValueError):
                    self.install(policy, deadline, download)
                self.assertEqual(self.program.ENTRY.readlink(), previous)
                self.assertEqual(previous.read_bytes(), self.binary)
                self.assertEqual(previous.stat().st_ino, identity)
                self.assertFalse((self.program.RELEASES / policy['version']).exists())
                self.assertFalse(self.program.PENDING.exists())
                self.assertFalse(list(self.program.STATE.glob('.install-*')))
                self.assertFalse(list(self.program.RELEASES.glob('.release-*')))
                if failure == 'hardlink':
                    self.assertEqual(protected.read_bytes(), self.archive)

    def test_public_release_modes_ignore_the_private_installer_umask(self):
        previous = os.umask(0o077)
        try:
            self.install()
        finally:
            os.umask(previous)
        release = self.program.RELEASES / self.policy['version']
        for directory in (self.program.RELEASES, release, release / 'bin',
                          release / 'metadata', release / 'source'):
            self.assertEqual(directory.stat().st_mode & 0o7777, 0o755)
        self.assertEqual(self.program.STATE.stat().st_mode & 0o7777, 0o700)


if __name__ == '__main__':
    unittest.main()
