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
import subprocess
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
        parent = ROOT / '.build/validation/primary-defaults-fixtures'
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

    def publish(self, selected=None):
        source = os.open(self.source, self.program.FLAGS)
        destination = os.open(self.home, self.program.FLAGS)
        try:
            self.program.publish(source, destination, self.account, [0, 0], selected=selected)
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

    def test_account_btop_views_are_owned_idempotent_and_reject_unsafe_paths(self):
        config = self.source / '.config/btop'
        config.mkdir(parents=True)
        for profile in ('cpu', 'memory'):
            (config / ('btop-' + profile + '.conf')).write_text('shown_boxes = "proc"\n')
        self.publish()
        probe = self.root / 'btop-view-probe.py'
        probe.write_text("import importlib.util,os,sys\nfrom types import SimpleNamespace\n"
                         "sys.path.insert(0,sys.argv[3])\n"
                         "from isolation import require_test_isolation\nrequire_test_isolation()\n"
                         "spec=importlib.util.spec_from_file_location('actual_primary',sys.argv[1])\n"
                         "module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)\n"
                         "home=os.open(sys.argv[2],module.FLAGS)\n"
                         "os.setgid(12346);os.setuid(12345)\n"
                         "try:module.btop_profiles(home,SimpleNamespace(pw_uid=12345,pw_gid=12346))\n"
                         "finally:os.close(home)\n")

        def invoke():
            return subprocess.run([sys.executable, '-I', '-B', str(probe),
                                   str(ROOT / 'd-i/debian/scripts/common/primary-defaults.py'),
                                   str(self.home), str(ROOT / 'tools')],
                                  env={'PATH': '/usr/bin:/bin', 'HOME': str(self.home),
                                       'TMPDIR': str(self.root), 'TMP': str(self.root), 'TEMP': str(self.root)},
                                  stdin=subprocess.DEVNULL, capture_output=True, timeout=10)
        # This fixture checks the unprivileged writer. Native CLI replay also
        # checks root validation and permanent group/UID drop at its entrypoint.
        first = {}
        for attempt in range(2):
            result = invoke()
            self.assertEqual(result.returncode, 0, result.stderr)
            for profile in ('cpu', 'memory'):
                link = self.home / '.config/btop/profiles' / profile / 'btop/btop.conf'
                info = link.lstat()
                self.assertEqual((info.st_uid, info.st_gid, info.st_nlink), (12345, 12346, 1))
                self.assertEqual(link.readlink(), Path('../../../btop-' + profile + '.conf'))
                self.assertEqual(link.read_bytes(), (self.home / '.config/btop' / ('btop-' + profile + '.conf')).read_bytes())
                if not attempt:
                    first[profile] = info.st_ino
                else:
                    self.assertEqual(info.st_ino, first[profile])
        link = self.home / '.config/btop/profiles/cpu/btop/btop.conf'
        link.unlink()
        link.write_bytes(b'preserve deliberate conflict')
        os.chown(link, 12345, 12346)
        self.assertNotEqual(invoke().returncode, 0)
        self.assertEqual(link.read_bytes(), b'preserve deliberate conflict')
        link.unlink()
        link.symlink_to('../../../btop-cpu.conf')
        os.lchown(link, 12345, 12346)
        profiles = self.home / '.config/btop/profiles'
        retained = profiles.with_name('retained-profiles')
        profiles.rename(retained)
        sibling = self.root / 'sibling'
        sibling.mkdir()
        profiles.symlink_to(sibling)
        self.assertNotEqual(invoke().returncode, 0)
        self.assertEqual(list(sibling.iterdir()), [])
        profiles.unlink()
        retained.rename(profiles)
        self.assertEqual(invoke().returncode, 0)

    def test_failed_replace_preserves_previous_bytes_and_rendered_input(self):
        target = self.previous()
        with patch.object(self.program.os, 'replace', side_effect=OSError('injected replace failure')):
            with self.assertRaises(OSError):
                self.publish()
        self.assertEqual(target.read_bytes(), b'previous account bytes\n')
        self.assertEqual(self.input.read_bytes(), b'rendered authenticated payload\n')
        self.assert_no_candidates()

    def test_exact_selected_file_preserves_other_primary_defaults_and_uses_account_ownership(self):
        previous = self.previous()
        before = previous.stat()
        relative = '.local/share/applications/waypaper.desktop'
        launcher = self.source / relative
        launcher.parent.mkdir(mode=0o700, parents=True)
        launcher.write_bytes(b'independent rendered Waypaper launcher\n')
        launcher.chmod(0o644)
        (launcher.parent / 'unselected.desktop').write_bytes(b'must not be copied\n')
        self.publish(selected=tuple(relative.split('/')))
        target = self.home / relative
        self.assertEqual(target.read_bytes(), launcher.read_bytes())
        info = target.stat()
        self.assertEqual((info.st_uid, info.st_gid, stat.S_IMODE(info.st_mode)),
                         (self.account.pw_uid, self.account.pw_gid, 0o600))
        self.assertEqual(previous.read_bytes(), b'previous account bytes\n')
        self.assertEqual(previous.stat().st_ino, before.st_ino)
        self.assertFalse((target.parent / 'unselected.desktop').exists())

    def test_selected_missing_file_or_directory_fails_without_copying_other_defaults(self):
        previous = self.previous()
        (self.source / 'directory').mkdir(mode=0o700)
        (self.source / 'directory/child').write_bytes(b'not a selected file\n')
        for selected in (('absent',), ('directory',), ('config', 'child')):
            with self.subTest(selected=selected):
                with self.assertRaises(ValueError):
                    self.publish(selected=selected)
                self.assertEqual(previous.read_bytes(), b'previous account bytes\n')
                self.assertFalse((self.home / 'directory/child').exists())

    def test_selected_file_cannot_follow_a_home_directory_symlink(self):
        relative = '.local/share/applications/waypaper.desktop'
        launcher = self.source / relative
        launcher.parent.mkdir(mode=0o700, parents=True)
        launcher.write_bytes(b'new launcher\n')
        sibling = self.root / 'sibling'
        sibling.mkdir()
        (self.home / '.local').symlink_to(sibling, target_is_directory=True)
        with self.assertRaises(OSError):
            self.publish(selected=tuple(relative.split('/')))
        self.assertEqual(list(sibling.iterdir()), [])

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
