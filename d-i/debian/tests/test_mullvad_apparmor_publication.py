"""Isolated-only Mullvad resource publication and failure-injection fixtures.

The production target shell program is used literally after rendering its path
tokens into the private fixture. The parser is a bounded mock here; the separate
offline parser record covers the actual vendor policy and Debian support data.
"""
from __future__ import annotations

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation

require_test_isolation()

import os
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1]
LABEL = 'validate Mullvad AppArmor profile without loading installer policy'
VENDOR = ('abi <abi/4.0>,\ninclude <tunables/global>\n'
          'profile mullvad "FIXTURE_GUI" flags=(unconfined) {\n  userns,\n}\n')
PARSER = r'''#!/usr/bin/python3
from pathlib import Path
import json, os, sys
root = Path(os.environ['FIXTURE_ROOT'])
assert root.is_absolute() and root.parent == Path('/workspace') and not root.is_symlink()
policy = root / 'policy'
candidate = Path(sys.argv[-1])
assert candidate.parent.parent == policy and not candidate.is_symlink()
assert candidate.is_file() and candidate.stat().st_size <= 65536
for flag in ('--config-file', '--base', '--Include', '--features-file', '--jobs=1',
             '--skip-kernel-load', '--skip-cache'):
    assert flag in sys.argv, flag
assert sys.argv[sys.argv.index('--base')+1] == str(policy)
assert sys.argv[sys.argv.index('--Include')+1] == str(policy)
assert sys.argv[sys.argv.index('--features-file')+1] == str(policy/'abi/4.0')
(root/'parser-args.json').write_text(json.dumps(sys.argv[1:]))
case = os.environ.get('FIXTURE_CASE', '')
if case == 'parser-fail': sys.exit(37)
if case == 'vendor-change':
    with (root/'opt/Mullvad VPN/resources/apparmor_mullvad').open('a') as stream:
        stream.write('# concurrent vendor change\n')
if case == 'destination-race': (policy/'mullvad').write_text('concurrent policy\n')
if case == 'destination-symlink': (policy/'mullvad').symlink_to(root/'sentinel')
if case == 'destination-directory': (policy/'mullvad').mkdir()
if case == 'destination-dir-symlink': (policy/'mullvad').symlink_to(root/'unrelated-directory')
'''


class MullvadAppArmorPublication(unittest.TestCase):
    def setUp(self):
        if os.geteuid() != 0:
            self.skipTest('production policy metadata requires the private image root UID')
        self.temporary = tempfile.TemporaryDirectory(prefix='mullvad-policy-', dir='/workspace')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.policy = self.root/'policy'
        (self.policy/'abi').mkdir(parents=True, mode=0o700)
        (self.policy/'abi/4.0').write_text('fixture ABI\n')
        self.vendor = self.root/'opt/Mullvad VPN/resources/apparmor_mullvad'
        self.vendor.parent.mkdir(parents=True, mode=0o700)
        self.vendor.write_text(VENDOR.replace('FIXTURE_GUI', str(self.root/'opt/Mullvad VPN/mullvad-gui')))
        self.profile = self.policy/'mullvad'
        self.sentinel = self.root/'sentinel'
        self.sentinel.write_text('preserve sentinel\n')
        (self.root/'unrelated-directory').mkdir(mode=0o700)
        self.bin = self.root/'bin'
        self.bin.mkdir(mode=0o700)
        for name in ('find', 'wc', 'mkdir', 'rm', 'rmdir', 'mktemp', 'sed', 'cmp',
                     'cp', 'chown', 'chmod', 'sync', 'ln'):
            tool = shutil.which(name, path='/usr/bin:/bin')
            if tool is None:
                self.skipTest('private image lacks '+name)
            (self.bin/name).symlink_to(tool)
        parser = self.bin/'apparmor_parser'
        parser.write_text(PARSER)
        parser.chmod(0o700)
        text = (SOURCE/'scripts/late/mullvad.sh').read_text()
        start = text.index('  run_in_target_quiet "'+LABEL+'"')
        program = text[start:].split(" -c '\n", 1)[1].split("\n' sh", 1)[0]
        values = {'DIR_APPARMOR': self.policy, 'DIR_OPT': self.root/'opt',
                  'DIR_USR_BIN': self.bin, 'DIR_USR_SBIN': self.bin}
        for key, value in values.items():
            program = program.replace('__INSTALLER_PATH_'+key+'__', str(value))
        self.assertNotIn('__INSTALLER_', program)
        self.program = program
        self.env = {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C', 'HOME': str(self.root),
                    'TMPDIR': str(self.root), 'FIXTURE_ROOT': str(self.root)}

    def run_case(self, case=''):
        return subprocess.run(['/bin/sh', '-eu', '-c', self.program], cwd=self.root,
                              env={**self.env, 'FIXTURE_CASE': case},
                              capture_output=True, text=True, timeout=15)

    def assert_clean(self):
        self.assertFalse(list(self.policy.glob('.mullvad-installer*')))

    def test_missing_policy_is_installed_and_existing_managed_flags_are_preserved(self):
        # Package resources can carry executable mode bits; their contents are
        # read as data, and publication must still create a non-executable file.
        self.vendor.chmod(0o755)
        result = self.run_case()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.profile.read_bytes(), self.vendor.read_bytes())
        self.assertEqual(self.profile.stat().st_mode & 0o777, 0o644)
        self.assertEqual(self.profile.stat().st_nlink, 1)
        self.assert_clean()
        managed = self.vendor.read_text().replace('flags=(unconfined)', 'flags=(complain)')
        self.profile.write_text(managed)
        previous = self.profile.stat()
        result = self.run_case()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.profile.read_text(), managed)
        self.assertEqual(self.profile.stat().st_ino, previous.st_ino)
        self.assert_clean()

    def test_writable_vendor_and_hardlinked_target_are_rejected(self):
        self.vendor.chmod(0o666)
        result = self.run_case()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.profile.exists())
        self.assertFalse((self.root/'parser-args.json').exists())
        self.vendor.chmod(0o644)
        os.link(self.sentinel, self.profile)
        result = self.run_case()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.sentinel.read_text(), 'preserve sentinel\n')
        self.assertEqual(self.profile.stat().st_nlink, 2)
        self.assert_clean()

    def test_compiler_failure_preserves_previous_policy_and_status(self):
        self.profile.write_bytes(self.vendor.read_bytes())
        previous = self.profile.read_bytes()
        result = self.run_case('parser-fail')
        self.assertEqual(result.returncode, 37, result.stderr)
        self.assertEqual(self.profile.read_bytes(), previous)
        self.assertIn('previous policy retained', result.stderr)
        self.assert_clean()

    def test_missing_or_indirect_vendor_and_unrecognized_existing_policy_fail_before_parser(self):
        original = self.vendor.read_bytes()
        self.vendor.unlink()
        result = self.run_case()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.profile.exists())
        self.assertFalse((self.root/'parser-args.json').exists())
        self.vendor.symlink_to(self.sentinel)
        result = self.run_case()
        self.assertNotEqual(result.returncode, 0)
        self.vendor.unlink()
        self.vendor.write_bytes(original)
        self.profile.write_text('unrecognized policy\n')
        result = self.run_case()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.profile.read_text(), 'unrecognized policy\n')
        self.assertFalse((self.root/'parser-args.json').exists())
        self.assert_clean()

    def test_indirect_destination_and_another_publisher_are_not_repaired(self):
        self.profile.symlink_to(self.sentinel)
        result = self.run_case()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.profile.is_symlink())
        self.assertEqual(self.sentinel.read_text(), 'preserve sentinel\n')
        self.assert_clean()
        self.profile.unlink()
        lock = self.policy/'.mullvad-installer.lock'
        lock.mkdir(mode=0o700)
        result = self.run_case()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(lock.is_dir())
        self.assertFalse(self.profile.exists())

    def test_vendor_change_and_destination_replacement_during_validation_are_rejected(self):
        original = self.vendor.read_bytes()
        for case in ('vendor-change', 'destination-race', 'destination-symlink',
                     'destination-directory', 'destination-dir-symlink'):
            with self.subTest(case=case):
                self.vendor.write_bytes(original)
                result = self.run_case(case)
                self.assertNotEqual(result.returncode, 0)
                self.assert_clean()
                if case == 'vendor-change': self.assertFalse(self.profile.exists())
                if case == 'destination-race': self.assertEqual(self.profile.read_text(), 'concurrent policy\n')
                if case in ('destination-symlink', 'destination-dir-symlink'):
                    self.assertTrue(self.profile.is_symlink())
                if self.profile.is_dir() and not self.profile.is_symlink(): self.profile.rmdir()
                elif self.profile.exists() or self.profile.is_symlink(): self.profile.unlink()
                self.assertEqual(self.sentinel.read_text(), 'preserve sentinel\n')
                self.assertEqual(list((self.root/'unrelated-directory').iterdir()), [])

    def test_publication_failure_preserves_original_status_and_absence(self):
        link = self.bin/'ln'
        link.unlink()
        link.write_text('''#!/bin/sh
[ "$1:$2" = -T:-- ] || exit 91
case "$3:$4" in "$FIXTURE_ROOT"/policy/.mullvad-installer.*/candidate:"$FIXTURE_ROOT"/policy/mullvad) ;; *) exit 92 ;; esac
exit 42
''')
        link.chmod(0o700)
        result = self.run_case()
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertFalse(self.profile.exists())
        self.assert_clean()

    def test_cleanup_failure_retains_private_evidence_and_lock(self):
        cleanup = self.bin/'rmdir'
        cleanup.unlink()
        cleanup.write_text('''#!/bin/sh
[ "$1" != -- ] || shift
case "$1" in "$FIXTURE_ROOT"/policy/.mullvad-installer.??????????) exit 51 ;; esac
exec /usr/bin/rmdir "$@"
''')
        cleanup.chmod(0o700)
        result = self.run_case()
        self.assertEqual(result.returncode, 125, result.stderr)
        self.assertEqual(self.profile.read_bytes(), self.vendor.read_bytes())
        self.assertTrue((self.policy/'.mullvad-installer.lock').is_dir())
        self.assertTrue(list(self.policy.glob('.mullvad-installer.??????????')))
        self.assertIn('cleanup failed; evidence and lock retained', result.stderr)

    def test_durable_publication_failure_retains_evidence_and_lock(self):
        sync = self.bin/'sync'
        sync.unlink()
        sync.write_text('''#!/bin/sh
case "$1:$2" in -f:"$FIXTURE_ROOT"/policy/mullvad) exit 42 ;; esac
exec /usr/bin/sync "$@"
''')
        sync.chmod(0o700)
        result = self.run_case()
        self.assertEqual(result.returncode, 125, result.stderr)
        self.assertEqual(self.profile.read_bytes(), self.vendor.read_bytes())
        self.assertTrue((self.policy/'.mullvad-installer.lock').is_dir())
        self.assertTrue(list(self.policy.glob('.mullvad-installer.??????????')))
        self.assertIn('evidence and lock retained', result.stderr)
