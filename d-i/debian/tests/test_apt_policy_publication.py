"""Offline APT directory publication; execution requires the isolated runner."""
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

ROOT = Path(__file__).resolve().parents[3]

SETUP = r'''
set -eu
. "$FIXTURE_SOURCE/scripts/common/source.sh"
. "$FIXTURE_SOURCE/scripts/common/modules/files-logging.sh"
. "$FIXTURE_SOURCE/scripts/common/modules/repository-apt.sh"
. "$FIXTURE_SOURCE/scripts/common/apt-sources.sh"
installer_fatal() { printf '%s\n' "$*" >&2; exit 1; }
installer_error() { printf '%s\n' "$*" >&2; }
installer_info() { :; }
installer_seed_base() { printf '%s\n' "$FIXTURE_ROOT/assets"; }
# Use the real small configuration parser and APT catalog consumer. Only the
# fixture acquisition boundary maps safe members to the private source copy.
source_load_repo_env "$FIXTURE_SOURCE/repo.env"
INSTALLER_REPO_ENV_READY=1
INSTALLER_REPO_SOURCE_ROOT=$FIXTURE_ROOT/assets
installer_fetch_file() {
  installer_validate_repo_file_value fixture_member "$2"
  case "$3" in "$FIXTURE_ROOT/target/"*) ;; *) exit 91 ;; esac
  fixture_input=$INSTALLER_REPO_SOURCE_ROOT/$2
  [ -f "$fixture_input" ] && [ ! -L "$fixture_input" ] || exit 92
  cp "$fixture_input" "$3"; chmod "$4" "$3"
}
# FHS/package interfaces are rendered into the private target, never accessed
# on the live host. Every subprocess inherits only this fixture's environment.
DIR_ETC=/etc
DIR_APT=/etc/apt
DIR_APT_CONF_D=$DIR_APT/apt.conf.d
DIR_APT_CONF_D_BACKUP=$DIR_APT_CONF_D.bak
DIR_APT_SOURCES_LIST_D=$DIR_APT/sources.list.d
FILE_APT_DEBIAN_ARCHIVE_KEYRING=/usr/share/keyrings/debian-archive-keyring.gpg
DIR_USR_BIN=/usr/bin
DIR_USR_SBIN=/usr/sbin
DIR_USR_LOCAL_LIBEXEC=/usr/local/libexec
DIR_MEDIA=/media
DIR_MEDIA_CDROM=$DIR_MEDIA/cdrom
FILE_SECURE_BOOT_CONFIG=/etc/secure-boot.conf
installer_runtime_path_placeholder_map() {
  printf 'PATH_DIR_USR_BIN=%s\nPATH_DIR_USR_SBIN=%s\nPATH_DIR_USR_LOCAL_LIBEXEC=%s\nPATH_DIR_MEDIA_CDROM=%s\n' \
    "$DIR_USR_BIN" "$DIR_USR_SBIN" "$DIR_USR_LOCAL_LIBEXEC" "$DIR_MEDIA_CDROM"
}
sync() { :; } # No durability claim is made by this isolated functional fixture.
TARGET_ROOT=$FIXTURE_ROOT/target
installer_apt_install_target_policy "$TARGET_ROOT" "${FIXTURE_PHASE:-install}"
'''


@unittest.skipUnless(os.geteuid() == 0, 'd-i requires uid 0 inside the isolated test image')
class AptPolicyPublication(unittest.TestCase):
    def prepare(self, root: Path, suite: str, family: str) -> dict[str, str]:
        assets = root / 'assets'
        source = ROOT / 'd-i' / suite / 'hooks/target/etc/apt'
        rows = ['format\t1\n']
        for group in ('common', 'desktop', 'server'):
            leaf = 'apt.conf.d' if group == 'common' else group + '/apt.conf.d'
            directory = source / leaf
            member_root = f'frontends/{suite}/hooks/target/etc/apt/{leaf}'
            destination = assets / member_root
            destination.mkdir(parents=True, mode=0o700)
            for path in sorted(directory.iterdir()):
                self.assertTrue(path.is_file() and not path.is_symlink())
                shutil.copyfile(path, destination / path.name)
                rows.append('\t'.join((suite, group, 'apt.conf.d', path.name,
                                       member_root + '/' + path.name)) + '\n')
        catalog = assets / 'catalog/compiled/apt-assets.tsv'
        catalog.parent.mkdir(parents=True)
        catalog.write_text(''.join(rows), encoding='ascii')
        parts = root / 'target/etc/apt/apt.conf.d'
        parts.mkdir(parents=True, mode=0o755)
        (parts / '00trustcdrom').write_text('ORIGINAL MEDIA POLICY\n', encoding='ascii')
        (parts / '.original-hidden').write_text('HIDDEN BACKUP DATA\n', encoding='ascii')
        return {'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'LC_ALL': 'C',
                'HOME': str(root), 'FIXTURE_ROOT': str(root),
                'FIXTURE_SOURCE': str(ROOT / 'd-i/debian'), 'INSTALLER_HOST_VARIANT': family,
                'INSTALLER_SUITE': suite, 'TMPDIR': str(root), 'TMP': str(root), 'TEMP': str(root)}

    def invoke(self, root: Path, environment: dict[str, str], after: str = '') -> subprocess.CompletedProcess[str]:
        return subprocess.run(['/bin/sh', '-eu', '-c', SETUP + '\n' + after], cwd=root,
                              env=environment, capture_output=True, text=True, timeout=30)

    def test_both_suites_and_roles_replace_all_defaults_and_preserve_backup(self) -> None:
        for suite in ('forky', 'trixie'):
            for family in ('desktop', 'server'):
                with self.subTest(suite=suite, family=family), tempfile.TemporaryDirectory(prefix='apt-publish-') as temporary:
                    root = Path(temporary)
                    environment = self.prepare(root, suite, family)
                    result = self.invoke(root, environment, r'''
printf 'LATER PACKAGE DEFAULT\n' >"$TARGET_ROOT$DIR_APT_CONF_D/50package-default"
installer_apt_install_target_policy "$TARGET_ROOT" final
''')
                    self.assertEqual(result.returncode, 0, result.stderr)
                    parts = root / 'target/etc/apt/apt.conf.d'
                    backup = parts.with_name('apt.conf.d.bak')
                    self.assertEqual((backup / '00trustcdrom').read_text(), 'ORIGINAL MEDIA POLICY\n')
                    self.assertEqual((backup / '.original-hidden').read_text(), 'HIDDEN BACKUP DATA\n')
                    self.assertEqual((backup / '50package-default').read_text(), 'LATER PACKAGE DEFAULT\n')
                    self.assertFalse((parts / '50package-default').exists())
                    self.assertIn('APT::Authentication::TrustCDROM "true";', (parts / '00trustcdrom').read_text())
                    media = (parts / '00CDMountPoint').read_text()
                    self.assertIn('Acquire::cdrom {\n  mount "/media/cdrom";\n};', media)
                    self.assertIn('Dir::Media::MountPath "/media/cdrom";', media)
                    self.assertFalse((parts / '99mok-maintenance').exists())
                    self.assertFalse((parts / '71labwc-desktop-apps').exists())
                    self.assertFalse((parts / '20listchanges').exists())
                    metadata = (parts / '25no-pdiffs').read_text()
                    self.assertIn('#clear Acquire::Languages;', metadata)
                    self.assertIn('Acquire::Languages "en";', metadata)
                    self.assertIn('Translations::DefaultEnabled "true";', metadata)
                    self.assertIn('Acquire::PDiffs "false";', metadata)
                    self.assertNotIn('Acquire::Languages "none";', metadata)
                    self.assertIn(f'APT::Default-Release "{suite}";', (parts / '00suite-default-release').read_text())
                    self.assertEqual(bool((parts / '60desktop-local-mail.conf').exists()), family == 'desktop')
                    self.assertEqual(backup.stat().st_mode & 0o777, 0o700)
                    self.assertFalse(list(parts.parent.glob('.installer-apt-policy*')))

    def test_bootstrap_keeps_native_media_and_verification_until_late(self) -> None:
        for suite in ('forky', 'trixie'):
            for family in ('desktop', 'server'):
                for physical_media in (False, True):
                    with self.subTest(suite=suite, family=family, physical=physical_media), tempfile.TemporaryDirectory(prefix='apt-media-') as temporary:
                        root = Path(temporary)
                        environment = self.prepare(root, suite, family)
                        environment['FIXTURE_PHASE'] = 'bootstrap'
                        parts = root / 'target/etc/apt/apt.conf.d'
                        native = {
                            '00CDMountPoint': 'Dir::Media::MountPath "/media/cdrom";\n',
                            '00NoMountCDROM': 'APT::CDROM::NoMount "true";\n',
                            '00IgnoreTimeConflict': 'Acquire::gpgv::Options { "--ignore-time-conflict"; };\n',
                            '70native-debconf': '// native fixture policy\n',
                        }
                        for name, content in native.items():
                            (parts / name).write_text(content, encoding='ascii')
                        (parts / '00IgnoreTimeConflict').chmod(0o600)
                        # Model the state change made by apt-setup/40cdrom for
                        # physical media. No APT, mount or target helper executes.
                        after = ''
                        if physical_media:
                            after = 'rm -- "$TARGET_ROOT$DIR_APT_CONF_D/00NoMountCDROM"\n'
                        after += 'installer_apt_install_target_policy "$TARGET_ROOT" bootstrap\n'
                        result = self.invoke(root, environment, after)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        backup = parts.with_name('apt.conf.d.bak')
                        for name, content in native.items():
                            self.assertEqual((backup / name).read_text(), content)
                            if name == '00NoMountCDROM' and physical_media:
                                self.assertFalse((parts / name).exists())
                            else:
                                self.assertEqual((parts / name).read_text(), content)
                        self.assertEqual((parts / '00IgnoreTimeConflict').stat().st_mode & 0o777, 0o600)
                        self.assertEqual((parts / '00trustcdrom').read_text(), 'ORIGINAL MEDIA POLICY\n')
                        self.assertTrue((parts / '.original-hidden').exists())
                        self.assertFalse((parts / '00installer-policy').exists())
                        self.assertFalse((parts / '52unattended-upgrades').exists())
                        self.assertFalse((parts / '00suite-default-release').exists())
                        self.assertIn('Acquire::Languages "en";', (parts / '25no-pdiffs').read_text())
                        self.assertIn('Acquire::PDiffs "false";', (parts / '25no-pdiffs').read_text())
                        self.assertIn('APT::Install-Recommends "false";', (parts / '99noinstall-recommends').read_text())
                        environment['FIXTURE_PHASE'] = 'install'
                        result = self.invoke(root, environment)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        for name in ('00NoMountCDROM', '00IgnoreTimeConflict', '70native-debconf', '.original-hidden'):
                            self.assertFalse((parts / name).exists())
                        self.assertIn('APT::Authentication::TrustCDROM "true";', (parts / '00trustcdrom').read_text())
                        self.assertIn('Acquire::cdrom {\n  mount "/media/cdrom";\n};', (parts / '00CDMountPoint').read_text())
                        self.assertEqual((backup / '00NoMountCDROM').read_text(), native['00NoMountCDROM'])
                        self.assertFalse(list(parts.parent.glob('.installer-apt-policy*')))

    def test_missing_fields_and_indirect_defaults_preserve_previous_directory(self) -> None:
        for failure in ('placeholder', 'symlink', 'hardlink', 'directory', 'lock'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory(prefix='apt-reject-') as temporary:
                root = Path(temporary)
                environment = self.prepare(root, 'forky', 'desktop')
                parts = root / 'target/etc/apt/apt.conf.d'
                if failure == 'placeholder':
                    with (root / 'assets/common/25no-pdiffs').open('a') as stream:
                        stream.write('__INSTALLER_MISSING_REQUIRED_VALUE__\n')
                elif failure == 'symlink':
                    (parts / 'indirect').symlink_to(root / 'catalog')
                elif failure == 'hardlink':
                    os.link(root / 'catalog', parts / 'indirect')
                elif failure == 'directory':
                    (parts / 'unexpected').mkdir()
                else:
                    (parts.parent / '.installer-apt-policy.lock').mkdir(mode=0o700)
                result = self.invoke(root, environment)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual((parts / '00trustcdrom').read_text(), 'ORIGINAL MEDIA POLICY\n')
                self.assertFalse(parts.with_name('apt.conf.d.bak').exists())

    def test_optional_hooks_are_rendered_only_after_their_helpers_exist(self) -> None:
        for suite in ('forky', 'trixie'):
            for family in ('desktop', 'server'):
                with self.subTest(suite=suite, family=family), tempfile.TemporaryDirectory(prefix='apt-helpers-') as temporary:
                    root = Path(temporary)
                    environment = self.prepare(root, suite, family)
                    for relative in ('usr/local/libexec/apt-mok-prehook', 'usr/local/libexec/labwc-wrap-desktop-files',
                                     'usr/bin/apt-listchanges', 'usr/sbin/dpkg-preconfigure'):
                        path = root / 'target' / relative
                        path.parent.mkdir(parents=True, exist_ok=True)
                        path.write_text('#!/bin/sh\nexit 0\n', encoding='ascii')
                        path.chmod(0o755)
                    (root / 'target/etc/secure-boot.conf').write_text('# fixture configuration\n', encoding='ascii')
                    result = self.invoke(root, environment)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    parts = root / 'target/etc/apt/apt.conf.d'
                    for name in ('01mok-maintenance-cleanup', '99mok-maintenance', '70debconf'):
                        self.assertTrue((parts / name).is_file())
                    for name in ('20listchanges', '71labwc-desktop-apps'):
                        self.assertEqual((parts / name).exists(), family == 'desktop')
                    content = '\n'.join(path.read_text() for path in sorted(parts.iterdir()))
                    self.assertNotIn('__INSTALLER_', content)
                    self.assertIn('apt-mok-prehook::InfoFD "3";', content)
                    self.assertIn('APT::Keep-Fds:: "3";', (parts / '70debconf').read_text())

    def test_bootstrap_preserves_native_debconf_without_installing_managed_hooks(self) -> None:
        for suite in ('forky', 'trixie'):
            for family in ('desktop', 'server'):
                for native_present in (False, True):
                    with self.subTest(suite=suite, family=family, native=native_present), tempfile.TemporaryDirectory(
                            prefix='apt-bootstrap-debconf-') as temporary:
                        root = Path(temporary)
                        environment = self.prepare(root, suite, family)
                        environment['FIXTURE_PHASE'] = 'bootstrap'
                        helper = root / 'target/usr/sbin/dpkg-preconfigure'
                        helper.parent.mkdir(parents=True)
                        helper.write_text('#!/bin/sh\nexit 0\n', encoding='ascii')
                        helper.chmod(0o755)
                        parts = root / 'target/etc/apt/apt.conf.d'
                        previous = ('// native debconf package policy\n'
                                    'DPkg::Pre-Install-Pkgs { "/usr/sbin/dpkg-preconfigure --apt || true"; };\n')
                        if native_present:
                            (parts / '70debconf').write_text(previous, encoding='ascii')
                            (parts / '70debconf').chmod(0o640)
                        # Repeating bootstrap (base-stage, network adapter and
                        # apt-setup) must preserve the same native bytes/mode.
                        result = self.invoke(root, environment,
                            'installer_apt_install_target_policy "$TARGET_ROOT" bootstrap\n')
                        self.assertEqual(result.returncode, 0, result.stderr)
                        active = parts / '70debconf'
                        saved = parts.with_name('apt.conf.d.bak') / '70debconf'
                        if native_present:
                            self.assertEqual(active.read_text(), previous)
                            self.assertEqual(active.stat().st_mode & 0o777, 0o640)
                            self.assertEqual(saved.read_text(), previous)
                        else:
                            self.assertFalse(active.exists())
                            self.assertFalse(saved.exists())
                        self.assertEqual((parts / '00trustcdrom').read_text(), 'ORIGINAL MEDIA POLICY\n')
                        self.assertFalse((parts / '00installer-policy').exists())
                        environment['FIXTURE_PHASE'] = 'install'
                        result = self.invoke(root, environment)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertIn('APT::Keep-Fds:: "3";', active.read_text())

    def test_commit_failure_restores_previous_or_retains_recovery(self) -> None:
        for recovery_failure in (False, True):
            with self.subTest(recovery_failure=recovery_failure), tempfile.TemporaryDirectory(prefix='apt-recover-') as temporary:
                root = Path(temporary)
                environment = self.prepare(root, 'forky', 'server')
                injection = r'''
mv() {
  case "${3:-}" in
    "$FIXTURE_ROOT/target/etc/apt/".installer-apt-policy.*/new) return 1 ;;
    "$FIXTURE_ROOT/target/etc/apt/".installer-apt-policy.*/previous)
      [ "$FIXTURE_FAIL_RECOVERY" = 0 ] || return 1 ;;
  esac
  command mv "$@"
}
'''
                environment['FIXTURE_FAIL_RECOVERY'] = '1' if recovery_failure else '0'
                code = SETUP.replace('installer_apt_install_target_policy "$TARGET_ROOT" "${FIXTURE_PHASE:-install}"',
                                     injection + '\ninstaller_apt_install_target_policy "$TARGET_ROOT" install')
                result = subprocess.run(['/bin/sh', '-eu', '-c', code], cwd=root,
                    env=environment, capture_output=True, text=True, timeout=30)
                self.assertNotEqual(result.returncode, 0)
                parts = root / 'target/etc/apt/apt.conf.d'
                if recovery_failure:
                    self.assertEqual(result.returncode, 125)
                    self.assertIn('outcome-unknown', result.stderr)
                    self.assertTrue((parts.parent / '.installer-apt-policy.lock').is_dir())
                    self.assertEqual(len(list(parts.parent.glob('.installer-apt-policy.*/previous/00trustcdrom'))), 1)
                else:
                    self.assertEqual((parts / '00trustcdrom').read_text(), 'ORIGINAL MEDIA POLICY\n')
                    self.assertFalse(list(parts.parent.glob('.installer-apt-policy*')))


@unittest.skipUnless(os.geteuid() == 0, 'd-i requires uid 0 inside the isolated test image')
class CustomAptPublication(unittest.TestCase):
    """Exercise the copier, without interpreting operator file contents."""

    def invoke(self, root: Path, suite: str, family: str, entries: list[tuple],
               fail: bool = False) -> subprocess.CompletedProcess[str]:
        assets = root / 'assets'
        catalog = assets / 'catalog/compiled/apt-assets.tsv'
        catalog.parent.mkdir(parents=True, exist_ok=True)
        rows = ['format\t1\n']
        for owner_suite, owner_family, kind, leaf, content in entries:
            member = f'frontends/{owner_suite}/hooks/target/etc/apt/{owner_family}/{kind}/{leaf}'
            source = assets / member
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_bytes(content)
            rows.append('\t'.join((owner_suite, owner_family, kind, leaf, member)) + '\n')
        catalog.write_text(''.join(rows), encoding='utf-8')
        (root / 'target').mkdir(exist_ok=True)
        environment = {
            'PATH': '/usr/bin:/bin', 'LC_ALL': 'C', 'HOME': str(root),
            'TMPDIR': str(root), 'TMP': str(root), 'TEMP': str(root),
            'FIXTURE_ROOT': str(root), 'FIXTURE_SOURCE': str(ROOT / 'd-i/debian'),
            'INSTALLER_SUITE': suite, 'INSTALLER_HOST_VARIANT': family,
            'FIXTURE_FAIL': 'true' if fail else 'false',
        }
        code = r'''
set -eu
. "$FIXTURE_SOURCE/scripts/common/modules/repository-apt.sh"
installer_fatal() { printf '%s\n' "$*" >&2; exit 1; }
installer_info() { :; }
installer_seed_base() { printf '%s\n' "$FIXTURE_ROOT/assets"; }
installer_fetch_file() {
  [ "$FIXTURE_FAIL" = false ] || return 73
  case "$2" in frontends/../*|/*) exit 91;; esac
  case "$3" in "$FIXTURE_ROOT/target/"*) ;; *) exit 92;; esac
  cp "$FIXTURE_ROOT/assets/$2" "$3" || return "$?"
  chmod "$4" "$3"
}
INSTALLER_REPO_SOURCE_ROOT=$FIXTURE_ROOT/assets
INSTALLER_TARGET_DIR=$FIXTURE_ROOT/target
DIR_APT_KEYRINGS=/etc/apt/keyrings
DIR_APT_PREFERENCES_D=/etc/apt/preferences.d
DIR_APT_SOURCES_LIST_D=/etc/apt/sources.list.d
installer_stage_suite_custom_apt
'''
        return subprocess.run(['/bin/sh', '-eu', '-c', code], cwd=root, env=environment,
                              capture_output=True, text=True, timeout=15)

    def test_opaque_files_future_names_and_exact_suite_family_selection(self) -> None:
        opaque = b'not APT syntax\x00\xff\n__INSTALLER_LEAVE_UNCHANGED__\n'
        for suite in ('forky', 'trixie'):
            for family in ('desktop', 'server'):
                with self.subTest(suite=suite, family=family), tempfile.TemporaryDirectory(
                        prefix='apt-custom-') as directory:
                    root = Path(directory)
                    entries = [
                        (s, f, kind, 'custom/future.' + suffix, opaque + s.encode() + f.encode())
                        for s in ('forky', 'trixie') for f in ('desktop', 'server')
                        for kind, suffix in (('preferences.d', 'pref'), ('sources.list.d', 'sources'),
                                             ('sources.list.d', 'extension-not-known-to-installer'))
                    ]
                    entries.extend((s, f, kind, leaf, content)
                                   for s in ('forky', 'trixie') for f in ('desktop', 'server')
                                   for kind, leaf, content in (
                                       ('sources.list.d', 'custom/future.sources.tmpl', b'literal suffix\n'),
                                       ('preferences.d', 'custom/empty.pref', b''),
                                       ('preferences.d', 'custom/empty.pref.tmpl', b'not the empty file\n')))
                    result = self.invoke(root, suite, family, entries)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    files = sorted((root / 'target').rglob('*'))
                    files = [path for path in files if path.is_file()]
                    self.assertEqual(len(files), 6)
                    expected = {(kind, leaf.removeprefix('custom/')): content
                                for s, f, kind, leaf, content in entries if (s, f) == (suite, family)}
                    for path in files:
                        self.assertEqual(path.read_bytes(), expected[path.parent.name, path.name])
                        self.assertEqual(path.stat().st_mode & 0o777, 0o644)
                    # A repeat copies the same bytes without deleting unrelated files.
                    unrelated = root / 'target/etc/apt/preferences.d/keep.pref'
                    unrelated.write_bytes(b'operator existing data\n')
                    result = self.invoke(root, suite, family, entries)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(unrelated.read_bytes(), b'operator existing data\n')

    def test_absent_or_empty_custom_directories_are_optional(self) -> None:
        with tempfile.TemporaryDirectory(prefix='apt-custom-empty-') as directory:
            root = Path(directory)
            result = self.invoke(root, 'forky', 'desktop', [])
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(list((root / 'target').iterdir()), [])

    def test_acquisition_failure_propagates(self) -> None:
        with tempfile.TemporaryDirectory(prefix='apt-custom-failure-') as directory:
            root = Path(directory)
            result = self.invoke(root, 'trixie', 'server', [
                ('trixie', 'server', 'sources.list.d', 'custom/future.sources', b'opaque')], fail=True)
            self.assertEqual(result.returncode, 73, result.stderr)
