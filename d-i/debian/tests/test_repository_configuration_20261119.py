"""Restricted repository data contract, inside the reviewed disposable image.

Expected roots/defaults are copied from the supplied pre-change source map.
The fixture has no dependency on development scratch or an external checkout.
No repository module is imported or shell code run before the isolation guard.
"""
from __future__ import annotations

from pathlib import Path as _IsolationPath
import sys as _isolation_sys
_isolation_sys.path.insert(0, str(_IsolationPath(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation as _require_test_isolation
_require_test_isolation()

from pathlib import Path
from isolation import fixture_environment

import os
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'd-i/debian/scripts/common/source.sh'
CONFIGURATION = ROOT / 'd-i/debian/repo.env'

# All retained defaults and roots, without the retired per-file inventory.
# ${INSTALLER_SUITE} is the only external expansion input in this contract.
EXPECTED = {'REPOSITORY_FAMILIES': 'desktop server',
 'REPOSITORY_NAME': 'debian-preseed-de',
 'DEBIAN_APT_PREFERENCES': '',
 'DEBIAN_DEFAULT_CLASSES': 'site/prod;network/dhcp',
 'DIR_REPO_ROOT': '.',
 'DIR_REPO_BUILD_STATE': '.build',
 'DIR_OFFLINE_WORK': '.build/offline-work',
 'DIR_CATALOG': 'catalog',
 'DIR_CATALOG_COMPILED': 'catalog/compiled',
 'DIR_FRONTENDS': 'frontends',
 'DIR_FRONTEND': 'frontends/${INSTALLER_SUITE}',
 'DIR_CLASSES': 'frontends/${INSTALLER_SUITE}/classes',
 'DIR_REPO_DI': 'd-i',
 'DIR_REPO_HOOKS': 'hooks',
 'DIR_REPO_HOSTS': 'hosts',
 'DIR_REPO_SCRIPTS': 'scripts',
 'DIR_CLASSES_AUTO': 'frontends/${INSTALLER_SUITE}/classes/class-auto',
 'DIR_CLASSES_PROFILE': 'frontends/${INSTALLER_SUITE}/classes/class-profile',
 'DIR_CLASSES_PROFILE_DESKTOP': 'frontends/${INSTALLER_SUITE}/classes/class-profile/desktop',
 'DIR_CLASSES_PROFILE_SERVER': 'frontends/${INSTALLER_SUITE}/classes/class-profile/server',
 'DIR_CLASSES_SELECT': 'frontends/${INSTALLER_SUITE}/classes/class-select',
 'DIR_REPO_DEBIAN': 'd-i/debian',
 'DIR_HOOKS_INSTALLER': 'hooks/installer',
 'DIR_HOOKS_TARGET': 'hooks/target',
 'DIR_HOSTS_PROFILES': 'hosts/profiles',
 'DIR_HOSTS_PROFILES_DESKTOP': 'hosts/profiles/desktop',
 'DIR_HOSTS_PROFILES_SERVER': 'hosts/profiles/server',
 'DIR_HOSTS_PROFILES_TEMPLATES': 'hosts/profiles/templates',
 'DIR_HOSTS_THEMES': 'hosts/themes',
 'DIR_SCRIPTS_COMMON': 'scripts/common',
 'DIR_SCRIPTS_DESKTOP': 'scripts/desktop',
 'DIR_SCRIPTS_EARLY': 'scripts/early',
 'DIR_SCRIPTS_FIRSTBOOT': 'scripts/firstboot',
 'DIR_SCRIPTS_LATE': 'scripts/late',
 'DIR_SCRIPTS_PARTMAN': 'scripts/partman',
 'DIR_SCRIPTS_PRESEED': 'scripts/preseed',
 'DIR_SCRIPTS_RUNTIME': 'scripts/runtime',
 'DIR_TARGET_DATA': 'hooks/target/data',
 'DIR_TARGET': 'hooks/target/etc',
 'DIR_TARGET_USR': 'hooks/target/usr',
 'DIR_SCRIPTS_COMMON_MODULES': 'scripts/common/modules',
 'DIR_SCRIPTS_DESKTOP_COMPONENTS': 'scripts/desktop/components',
 'DIR_SCRIPTS_DESKTOP_TEMPLATES': 'scripts/desktop/templates',
 'DIR_SCRIPTS_LATE_DEVOPS': 'scripts/late/devops',
 'DIR_SCRIPTS_LATE_SSH': 'scripts/late/ssh',
 'DIR_SCRIPTS_RUNTIME_MODULES': 'scripts/runtime/modules',
 'DIR_SCRIPTS_RUNTIME_TEMPLATES': 'scripts/runtime/templates',
 'DIR_TARGET_CONFIG': 'hooks/target/data/config',
 'DIR_TARGET_DOCS': 'hooks/target/data/docs',
 'DIR_TARGET_APPARMOR': 'hooks/target/etc/apparmor',
 'DIR_TARGET_AA': 'hooks/target/etc/apparmor.d',
 'DIR_FRONTEND_HOOKS': 'frontends/${INSTALLER_SUITE}/hooks',
 'DIR_FRONTEND_TARGET': 'frontends/${INSTALLER_SUITE}/hooks/target',
 'DIR_FRONTEND_TARGET_ETC': 'frontends/${INSTALLER_SUITE}/hooks/target/etc',
 'DIR_TARGET_APT': 'frontends/${INSTALLER_SUITE}/hooks/target/etc/apt',
 'DIR_TARGET_APT_APT_CONF_D': 'frontends/${INSTALLER_SUITE}/hooks/target/etc/apt/apt.conf.d',
 'DIR_TARGET_CROWDSEC_ROOT': 'hooks/target/etc/crowdsec',
 'DIR_TARGET_CROWDSEC': 'hooks/target/etc/crowdsec/common',
 'DIR_TARGET_DEFAULT': 'hooks/target/etc/default',
 'DIR_TARGET_FAIL2BAN': 'hooks/target/etc/fail2ban',
 'DIR_TARGET_LABWC': 'hooks/target/etc/labwc',
 'DIR_TARGET_MODPROBE_D': 'hooks/target/etc/modprobe.d',
 'DIR_TARGET_NFTABLES_ROOT': 'hooks/target/etc/nftables',
 'DIR_TARGET_NFTABLES': 'hooks/target/etc/nftables/desktop',
 'DIR_TARGET_SKEL': 'hooks/target/etc/skel-desktop',
 'DIR_TARGET_SYSCTL_D': 'hooks/target/etc/sysctl.d',
 'DIR_TARGET_SYSTEMD': 'hooks/target/etc/systemd',
 'DIR_TARGET_SYSTEMD_COMMON': 'hooks/target/etc/systemd/common',
 'DIR_TARGET_SYSTEMD_DESKTOP': 'hooks/target/etc/systemd/desktop',
 'DIR_TARGET_SYSTEMD_SERVER': 'hooks/target/etc/systemd/server',
 'DIR_TARGET_COMMON_UNIT': 'hooks/target/etc/systemd/common/system',
 'DIR_TARGET_TMPFILES_D': 'hooks/target/etc/tmpfiles.d',
 'DIR_TARGET_USR_LOCAL': 'hooks/target/usr/local',
 'DIR_TARGET_CONFIG_PODMAN': 'hooks/target/data/config/podman',
 'DIR_TARGET_DEFAULT_GRUB_D': 'hooks/target/etc/default/grub.d',
 'DIR_TARGET_LABWC_3PROXY': 'hooks/target/etc/labwc/3proxy',
 'DIR_TARGET_NFTABLES_PROFILES': 'hooks/target/etc/nftables/desktop/profiles',
 'DIR_TARGET_NFTABLES_SERVICES': 'hooks/target/etc/nftables/desktop/services',
 'DIR_TARGET_SKEL_CONFIG': 'hooks/target/etc/skel-desktop/.config',
 'DIR_TARGET_UNIT': 'hooks/target/etc/systemd/desktop/system',
 'DIR_TARGET_USER_UNIT': 'hooks/target/etc/systemd/desktop/user',
 'DIR_TARGET_BIN': 'hooks/target/usr/local/bin',
 'DIR_TARGET_LIB': 'hooks/target/usr/local/lib',
 'DIR_TARGET_LIBEXEC': 'hooks/target/usr/local/libexec',
 'DIR_TARGET_SBIN': 'hooks/target/usr/local/sbin',
 'DIR_TARGET_SHARE': 'hooks/target/usr/local/share',
 'DIR_TARGET_CONFIG_PODMAN_TEMPLATES': 'hooks/target/data/config/podman/templates',
 'DIR_TARGET_SKEL_VIVALDI': 'hooks/target/etc/skel-desktop/.config/vivaldi',
 'DIR_TARGET_CONFIG_PODMAN_TEMPLATES_DEVOPS': 'hooks/target/data/config/podman/templates/devops',
 'DIR_TARGET_APT_DESKTOP': 'frontends/${INSTALLER_SUITE}/hooks/target/etc/apt/desktop',
 'DIR_TARGET_APT_DESKTOP_APT_CONF_D': 'frontends/${INSTALLER_SUITE}/hooks/target/etc/apt/desktop/apt.conf.d',
 'DIR_TARGET_APT_SERVER': 'frontends/${INSTALLER_SUITE}/hooks/target/etc/apt/server',
 'DIR_TARGET_APT_SERVER_APT_CONF_D': 'frontends/${INSTALLER_SUITE}/hooks/target/etc/apt/server/apt.conf.d',
 'DIR_TARGET_AA_COMMON': 'hooks/target/etc/apparmor.d/common',
 'DIR_TARGET_AA_DESKTOP': 'hooks/target/etc/apparmor.d/desktop',
 'DIR_TARGET_LIB_COMMON': 'hooks/target/usr/local/lib/common',
 'DIR_TARGET_LIB_DESKTOP': 'hooks/target/usr/local/lib/desktop',
 'DIR_TARGET_BIN_SERVER': 'hooks/target/usr/local/bin/server',
 'DIR_TARGET_SHARE_COMMON': 'hooks/target/usr/local/share/common',
 'DIR_TARGET_SHARE_DESKTOP': 'hooks/target/usr/local/share/desktop',
 'DIR_TARGET_AA_ABSTRACTIONS': 'hooks/target/etc/apparmor.d/common/abstractions',
 'DIR_TARGET_AA_LOCAL': 'hooks/target/etc/apparmor.d/desktop/local',
 'DIR_TARGET_LIB_PERL5': 'hooks/target/usr/local/lib/common/perl5',
 'DIR_TARGET_LIB_PYTHON3': 'hooks/target/usr/local/lib/desktop/python3',
 'DIR_TARGET_SHARE_GRUB_PROFILES': 'hooks/target/usr/local/share/common/grub-profiles',
 'DIR_TARGET_SHARE_LABWC_APPEARANCE': 'hooks/target/usr/local/share/desktop/labwc-appearance',
 'DIR_TARGET_PERL': 'hooks/target/usr/local/lib/common/perl5/site_perl',
 'DIR_TARGET_PY': 'hooks/target/usr/local/lib/desktop/python3/dist-packages',
 'DIR_TARGET_PERL_APPARMOR_MODES': 'hooks/target/usr/local/lib/common/perl5/site_perl/apparmor-modes',
 'DIR_TARGET_PERL_APT_REPO_LOCAL': 'hooks/target/usr/local/lib/common/perl5/site_perl/apt-repo-local',
 'DIR_TARGET_PERL_NETWORK': 'hooks/target/usr/local/lib/common/perl5/site_perl/network',
 'DIR_TARGET_PERL_WHISPER': 'hooks/target/usr/local/lib/common/perl5/site_perl/whisper',
 'DIR_TARGET_PERL_ZRAM_WRITEBACK': 'hooks/target/usr/local/lib/common/perl5/site_perl/zram-writeback'}


class RepositoryConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.environment = fixture_environment(Path(os.environ['HOME']))
        self.temporary = tempfile.TemporaryDirectory(
            prefix='repository-configuration-', dir=self.environment['TMPDIR'])
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.environment.update(TMPDIR=str(self.root), TMP=str(self.root), TEMP=str(self.root))
        self.input = self.root / 'repo.env'
        self.original = CONFIGURATION.read_text()
        self.sentinel = self.root / 'executed'

    def run_loader(self, data=None, suite='forky', *, shell=None, environment=None):
        if data is not None:
            self.input.write_text(data)
            self.input.chmod(0o600)
        # The variable names below come only from this literal fixture table.
        # Each expansion reads the actual shell assignment, not the AWK output.
        rows = '\n'.join(
            "printf '%s\\t%s\\n' " + shlex.quote(name) + ' "${' + name + '}"'
            for name in EXPECTED)
        script = '''
. "$1"
INSTALLER_SUITE=$2
REPOSITORY_NAME=unparsed
DIR_REPO_ROOT=unparsed
if source_load_repo_env "$3"; then
''' + rows + '''
else
  printf 'UNMODIFIED\t%s\t%s\n' "$REPOSITORY_NAME" "$DIR_REPO_ROOT"
  exit 1
fi
'''
        return subprocess.run(
            [*(shell or ['/bin/sh']), '-eu', '-c', script, 'fixture', str(SOURCE),
             suite, str(self.input)], cwd=self.root,
            env={**self.environment, **(environment or {})}, capture_output=True,
            text=True, timeout=10, check=False)

    @staticmethod
    def values(result):
        return dict(row.split('\t', 1) for row in result.stdout.splitlines())

    def replace(self, name, value):
        text, count = re.subn(
            r'^' + re.escape(name) + r'=.*$', lambda _: name + '="' + value + '"',
            self.original, flags=re.M)
        self.assertEqual(count, 1)
        return text

    def assert_rejected(self, data, diagnostic, **kwargs):
        result = self.run_loader(data, **kwargs)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(diagnostic, result.stderr)
        self.assertEqual(result.stdout, 'UNMODIFIED\tunparsed\tunparsed\n')
        self.assertFalse(self.sentinel.exists(), 'configuration executed shell code')

    def test_every_retained_root_and_default_matches_original_for_both_suites(self):
        for suite in ('forky', 'trixie'):
            with self.subTest(suite=suite):
                result = self.run_loader(self.original, suite)
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = {name: value.replace('${INSTALLER_SUITE}', suite)
                            for name, value in EXPECTED.items()}
                self.assertEqual(self.values(result), expected)
                self.assertEqual(self.values(result)['DEBIAN_APT_PREFERENCES'], '')
                self.assertFalse(any(name.startswith('FILE_') for name in self.values(result)))

    def test_busybox_shell_preserves_the_same_data_contract(self):
        busybox = shutil.which('busybox')
        if busybox is None:
            self.skipTest('BusyBox is required in the isolated portability image')
        result = self.run_loader(self.original, 'trixie', shell=[busybox, 'sh'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.values(result), {
            name: value.replace('${INSTALLER_SUITE}', 'trixie')
            for name, value in EXPECTED.items()})

    def test_configuration_is_not_executed(self):
        target = shlex.quote(str(self.sentinel))
        mutations = (
            self.replace('DIR_REPO_BUILD_STATE', '$(printf executed > ' + target + ')'),
            self.replace('DIR_REPO_BUILD_STATE', '`printf executed > ' + target + '`'),
            self.original + '\nprintf executed > ' + target + '\n',
            self.original + '\nREPOSITORY_NAME="x"; printf executed > ' + target + '\n',
        )
        for data in mutations:
            with self.subTest(last_line=data.splitlines()[-1]):
                self.assert_rejected(data, 'invalid repository configuration')

    def test_duplicate_keys_fail_before_assigning_any_values(self):
        self.assert_rejected(self.original + 'REPOSITORY_NAME="other"\n', 'duplicate key')

    def test_unknown_and_retired_inventory_keys_fail(self):
        for name in ('UNKNOWN_KEY', 'FILE_LATE_CORE', 'INSTALLER_SUITE'):
            with self.subTest(key=name):
                self.assert_rejected(self.original + name + '="fixture"\n', 'unsupported key')

    def test_missing_key_is_not_filled_from_inherited_environment(self):
        data = re.sub(r'^DIR_TARGET_PERL_WHISPER=.*\n', '', self.original, flags=re.M)
        self.assert_rejected(data, 'missing supported key',
                             environment={'DIR_TARGET_PERL_WHISPER': 'inherited'})

    def test_roots_reject_absolute_traversal_empty_and_ambiguous_paths(self):
        for value in ('/etc', '../escape', 'scripts/../escape', './scripts',
                      'scripts//common', 'scripts/', '', '.', 'scripts/./common'):
            with self.subTest(value=value):
                self.assert_rejected(self.replace('DIR_REPO_BUILD_STATE', value),
                                     'unsafe repository root')

    def test_external_or_forward_parent_is_not_expanded(self):
        for parent in ('UNDECLARED_PARENT', 'DIR_OFFLINE_WORK'):
            with self.subTest(parent=parent):
                self.assert_rejected(
                    self.replace('DIR_REPO_BUILD_STATE', '${' + parent + '}/child'),
                    'undefined parent', environment={parent: 'inherited'})

    def test_shell_parameter_operators_and_backslash_are_not_data(self):
        for value in ('${DIR_REPO_ROOT:-fallback}', '$HOME', r'scripts\common'):
            with self.subTest(value=value):
                self.assert_rejected(self.replace('DIR_REPO_BUILD_STATE', value),
                                     'unsupported data expansion')

    def test_supported_suite_is_required(self):
        for suite in ('', 'stable', 'forky;touch', '../trixie'):
            with self.subTest(suite=suite):
                self.assert_rejected(self.original, 'requires a supported suite', suite=suite)

    def test_symlink_configuration_is_rejected(self):
        direct = self.root / 'direct.env'
        direct.write_text(self.original)
        self.input.symlink_to(direct)
        result = self.run_loader()
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertIn('not a direct readable file', result.stderr)
        self.assertFalse(self.sentinel.exists())

    def test_unsupported_family_and_invalid_name_are_rejected(self):
        self.assert_rejected(self.replace('REPOSITORY_FAMILIES', 'desktop extra'),
                             'unsupported repository families')
        self.assert_rejected(self.replace('REPOSITORY_NAME', 'name with spaces'),
                             'invalid repository name')

    def test_expanded_parent_length_is_bounded(self):
        # Each input line is within 4,096 bytes; a derived shared path exceeds
        # the expanded-value budget as children are resolved.
        self.assert_rejected(self.replace('DIR_HOOKS_TARGET', 'x' * 4077),
                             'unsupported data expansion')

    def test_input_size_limits_are_enforced(self):
        self.assert_rejected('#' + 'x' * 4096 + '\n' + self.original,
                             'input exceeds configuration limits')
        self.assert_rejected(self.original + ('# extra line\n' * 513),
                             'input exceeds configuration limits')
