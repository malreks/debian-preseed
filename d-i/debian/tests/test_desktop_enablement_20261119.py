"""Required offline desktop enablement, inside the reviewed disposable image."""
from __future__ import annotations

from pathlib import Path as _IsolationPath
import sys as _isolation_sys
_isolation_sys.path.insert(0, str(_IsolationPath(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation as _require_test_isolation
_require_test_isolation()

from pathlib import Path
from isolation import fixture_environment

import os
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = ROOT / 'd-i/debian/scripts'
UNITS = ('labwc-system-desktop-overrides.service', 'labwc-system-desktop-overrides.path')


class RequiredDesktopEnablementTests(unittest.TestCase):
    def setUp(self):
        self.environment = fixture_environment(Path(os.environ['HOME']))
        self.temporary = tempfile.TemporaryDirectory(
            prefix='desktop-enablement-', dir=self.environment['TMPDIR'])
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.target = self.root / 'target'
        self.target.mkdir(mode=0o700)
        self.unit_dir = self.target / 'etc/systemd/system'
        self.unit_dir.mkdir(parents=True)
        self.sibling = self.root / 'sibling'
        self.sibling.mkdir()
        self.sentinel = self.sibling / 'sentinel'
        self.sentinel.write_text('unchanged\n')
        self.broker = self.root / 'dbus-broker.sh'
        self.broker.write_text((SCRIPTS / 'late/dbus-broker.sh').read_text().replace(
            '__INSTALLER_PATH_DIR_DEV__', '/dev'))
        for unit in UNITS:
            self.make_unit(unit)

    def make_unit(self, unit, wanted='multi-user.target'):
        path = self.unit_dir / unit
        path.write_text('[Unit]\nDescription=Isolated fixture\n[Install]\nWantedBy=' + wanted + '\n')
        path.chmod(0o644)
        return path

    def run_fixture(self, unit=UNITS[0], before=''):
        # Use production target-boundary, metadata, parser and link writer code.
        # Only the installed mount-table lookup is replaced by the exact private
        # fixture target; no host mount table or service manager is consulted.
        sources = (
            SCRIPTS / 'common/lifecycle.sh',
            SCRIPTS / 'common/modules/target-publication.sh',
            SCRIPTS / 'late/target-assets.sh',
            self.broker,
            SCRIPTS / 'desktop/components/services.sh',
        )
        script = '\n'.join('. ' + shlex.quote(str(path)) for path in sources)
        script += '''
TARGET_ROOT=$1
INSTALLER_TARGET_DIR=$1
INSTALLER_ROOT=$2
DIR_INSTALLER_ROOT=$2
DIR_SYSTEMD_SYSTEM=/etc/systemd/system
DIR_SYSTEMD_SYSTEM_LIB=/usr/lib/systemd/system
fixture_target=$1
installer_fatal() { printf 'fixture fatal: %s\n' "$*" >&2; return 1; }
desktop_log() { :; }
installer_mounts_find_record() {
  [ "$1" = "$fixture_target" ] || return 1
  INSTALLER_MOUNT_POINT=$fixture_target
}
'''
        script += before + '\ndesktop_enable_required_system_unit "$3"\n'
        return subprocess.run(
            ['/bin/sh', '-eu', '-c', script, 'fixture', str(self.target),
             str(self.root / 'installer'), unit],
            cwd=self.root, env=self.environment, capture_output=True, text=True,
            timeout=15, check=False)

    def assert_rejected(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.sentinel.read_text(), 'unchanged\n')

    def test_required_units_enable_after_staging_and_repeat_without_replacement(self):
        for unit in UNITS:
            result = self.run_fixture(unit)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            link = self.unit_dir / 'multi-user.target.wants' / unit
            self.assertEqual(os.readlink(link), '/etc/systemd/system/' + unit)
            identity = link.lstat().st_ino
            result = self.run_fixture(unit)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(link.lstat().st_ino, identity)

    def test_missing_required_source_fails_instead_of_optional_skip(self):
        (self.unit_dir / UNITS[0]).unlink()
        self.assert_rejected(self.run_fixture())

    def test_indirect_source_fails(self):
        path = self.unit_dir / UNITS[0]
        path.unlink()
        path.symlink_to(self.sentinel)
        self.assert_rejected(self.run_fixture())

    def test_hardlinked_source_fails(self):
        os.link(self.unit_dir / UNITS[0], self.root / 'unit-alias')
        self.assert_rejected(self.run_fixture())

    def test_changed_source_mode_fails(self):
        (self.unit_dir / UNITS[0]).chmod(0o666)
        self.assert_rejected(self.run_fixture())

    def test_indirect_wants_parent_fails_before_link_creation(self):
        (self.unit_dir / 'multi-user.target.wants').symlink_to(self.sibling)
        self.assert_rejected(self.run_fixture())
        self.assertEqual(sorted(p.name for p in self.sibling.iterdir()), ['sentinel'])

    def test_failed_or_noop_link_writer_cannot_report_readiness(self):
        for body in ('return 37', ':'):
            with self.subTest(writer=body):
                self.assert_rejected(self.run_fixture(
                    before='stage_target_systemd_unit_enabled() { ' + body + '; }'))

    def test_wrong_target_link_is_rejected_after_writer_returns(self):
        wanted = self.unit_dir / 'multi-user.target.wants'
        wanted.mkdir()
        (wanted / UNITS[0]).symlink_to('/dev/null')
        self.assert_rejected(self.run_fixture(before='stage_target_systemd_unit_enabled() { :; }'))

    def test_final_readiness_keeps_required_link_assertion(self):
        finish = (ROOT / 'd-i/debian/hooks/installer/finish-install.d/94zz-99-validate-target').read_text()
        self.assertIn('required desktop unit is not safely enabled', finish)
        self.assertIn('[ "$(readlink "$unit_link")" = "$unit_file" ]', finish)
        self.assertIn('test -r "$unit_link"', finish)
        self.assertLess(finish.index('required desktop unit is not safely enabled'),
                        finish.index('state=TARGET_VALIDATED'))


if __name__ == '__main__':
    unittest.main()
