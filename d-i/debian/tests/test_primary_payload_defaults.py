"""Primary HOME publication failure fixtures; reviewed isolated execution only.

No account is created. All file mutation is inside one private checkout fixture;
the fake account numbers are used only for ownership of those fixture files.
"""
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from isolation import require_test_isolation
require_test_isolation()

import importlib.util
import os
import stat
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


@unittest.skipUnless(os.geteuid() == 0, 'private isolated fixture requires root file ownership')
class PrimaryPayloadPublication(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location(
            'primary_payload_fixture', ROOT / 'd-i/debian/scripts/common/primary-defaults.py')
        self.assertIsNotNone(spec)
        self.assertIsNotNone(spec.loader)
        self.program = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.program)
        parent = ROOT / '.build/primary-defaults-fixtures'
        parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix='publication-', dir=parent)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / 'payload'
        self.home = self.root / 'home'
        self.source.mkdir(mode=0o700)
        self.home.mkdir(mode=0o700)
        self.account = SimpleNamespace(pw_uid=12345, pw_gid=12346)
        os.chown(self.home, self.account.pw_uid, self.account.pw_gid)
        self.input = self.source / 'config'
        self.input.write_bytes(b'rendered authenticated payload\n')
        self.input.chmod(0o600)

    def publish(self):
        source = os.open(self.source, self.program.FLAGS)
        destination = os.open(self.home, self.program.FLAGS)
        try:
            self.program.publish(source, destination, self.account, [0, 0])
        finally:
            os.close(destination)
            os.close(source)

    def previous(self):
        target = self.home / 'config'
        target.write_bytes(b'previous account bytes\n')
        target.chmod(0o600)
        os.chown(target, self.account.pw_uid, self.account.pw_gid)
        return target

    def assert_no_candidates(self):
        self.assertEqual(list(self.home.glob('.primary-default-*')), [])

    def test_published_files_have_account_owner_group_and_private_modes(self):
        executable = self.source / 'autostart'
        executable.write_bytes(b'#!/bin/sh\nexit 0\n')
        executable.chmod(0o755)
        self.publish()
        for name, mode in (('config', 0o600), ('autostart', 0o700)):
            info = (self.home / name).stat()
            self.assertEqual((info.st_uid, info.st_gid, stat.S_IMODE(info.st_mode)),
                             (self.account.pw_uid, self.account.pw_gid, mode))
            self.assertEqual((self.home / name).read_bytes(), (self.source / name).read_bytes())
        self.assertEqual(self.input.stat().st_uid, 0)
        self.assert_no_candidates()

    def test_failed_replace_preserves_previous_bytes_and_rendered_input(self):
        target = self.previous()
        with patch.object(self.program.os, 'replace', side_effect=OSError('injected replace failure')):
            with self.assertRaises(OSError):
                self.publish()
        self.assertEqual(target.read_bytes(), b'previous account bytes\n')
        self.assertEqual(self.input.read_bytes(), b'rendered authenticated payload\n')
        self.assert_no_candidates()

    def test_destination_symlink_and_hardlink_cannot_modify_other_fixture_files(self):
        outside = self.root / 'other-account-file'
        outside.write_bytes(b'preserve sibling\n')
        for kind in ('symlink', 'hardlink'):
            with self.subTest(kind=kind):
                target = self.home / 'config'
                if kind == 'symlink':
                    target.symlink_to(outside)
                else:
                    os.link(outside, target)
                try:
                    with self.assertRaises(ValueError):
                        self.publish()
                    self.assertEqual(outside.read_bytes(), b'preserve sibling\n')
                    self.assert_no_candidates()
                finally:
                    target.unlink()

    def test_source_replacement_is_rejected_before_account_publication(self):
        target = self.previous()
        original_open = os.open

        def replaced_input(path, flags, *args, **kwargs):
            descriptor = original_open(path, flags, *args, **kwargs)
            if path == 'config' and flags & os.O_NONBLOCK:
                self.input.write_bytes(b'replaced input bytes\n')
            return descriptor

        with patch.object(self.program.os, 'open', side_effect=replaced_input):
            with self.assertRaisesRegex(ValueError, 'identity changed'):
                self.publish()
        self.assertEqual(target.read_bytes(), b'previous account bytes\n')
        self.assert_no_candidates()

    def test_deadline_failure_retains_unmodified_account_and_payload_evidence(self):
        target = self.previous()
        with patch.object(self.program.time, 'monotonic', return_value=self.program.DEADLINE + 1):
            with self.assertRaises(TimeoutError):
                self.publish()
        self.assertEqual(target.read_bytes(), b'previous account bytes\n')
        self.assertTrue(self.input.is_file())
        self.assert_no_candidates()

    def test_cleanup_rejects_links_and_preserves_external_fixture_data(self):
        outside = self.root / 'retained-evidence'
        outside.write_bytes(b'outside cleanup boundary\n')
        (self.source / 'unsafe-link').symlink_to(outside)
        source = os.open(self.source, self.program.FLAGS)
        try:
            with self.assertRaises(ValueError):
                self.program.cleanup(source, os.fstat(source).st_dev)
        finally:
            os.close(source)
        self.assertEqual(outside.read_bytes(), b'outside cleanup boundary\n')
        self.assertTrue(self.source.is_dir())


if __name__ == '__main__':
    unittest.main()
