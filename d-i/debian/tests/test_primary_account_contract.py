"""Primary identity selection and fresh late-provider shell regression cases.

Run only in the reviewed disposable test image. Fetching and stage dependencies
are private fixtures; credential parsing and template publication use real code.
"""
from __future__ import annotations

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation

require_test_isolation()

import shlex
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1]
ACCOUNT_ASSET = ('hooks/target/usr/local/lib/desktop/perl5/site_perl/'
                 'labwc-network-scan-action/LabwcNetworkScanAction/Root.pm.tmpl')

# Shared with the recorded diskless-VM probe as literal fixture data. No test
# module needs to be imported on the host to stage this shell program.
SHELL_SETUP = r'''
set -eu
. "$FIXTURE_SOURCE/scripts/common/credentials.sh"
. "$FIXTURE_SOURCE/scripts/common/modules/credentials-probes.sh"
. "$FIXTURE_SOURCE/scripts/runtime/modules/base.sh"
. "$FIXTURE_SOURCE/scripts/common/modules/files-logging.sh"
. "$FIXTURE_SOURCE/scripts/common/modules/profiles.sh"
. "$FIXTURE_SOURCE/scripts/common/modules/target-publication.sh"
bootstrap_repo_file_value() {
  [ "$1" = FILE_COMMON_CREDENTIAL_DATA ] || exit 90
  printf '%s\n' scripts/common/credential-data.awk
}
bootstrap_parser_asset_path() { printf '%s/%s\n' "$FIXTURE_SOURCE" "$1"; }
installer_error() { printf '%s\n' "$*" >&2; }
installer_fatal() { installer_error "$@"; exit 1; }
installer_fatal_status() { status=$1; shift; installer_error "$@"; exit "$status"; }
installer_operation_context() {
  INSTALLER_FAILURE_SOURCE=$1
  INSTALLER_FAILURE_LINE=$2
  INSTALLER_FAILURE_OPERATION=$3
}
installer_repo_assert_asset_family() {
  case "$1" in "$FIXTURE_SOURCE"/*) ;; *) exit 91 ;; esac
}
# Mock target-ancestry authority is restricted to this owned fixture. The real
# target policy/identity checks are outside this account-selection regression.
installer_apt_safe_path() {
  case "$1" in "$FIXTURE_ROOT"/*) ;; *) return 1 ;; esac
  case "$1" in */../*|*/./*|*//*) return 1 ;; esac
  [ ! -L "$1" ]
}
installer_seed_base() { printf '%s\n' "$FIXTURE_SOURCE"; }
installer_fetch_file() {
  installer_repo_assert_asset_family "$2"
  installer_apt_safe_path "$3" || exit 92
  cp "$2" "$3"
  chmod "$4" "$3"
}
'''

FOUNDATION_SETUP = r'''
bootstrap_source_common_lib() { :; }
bootstrap_source_common_support_libs() { :; }
installer_ensure_context_loaded() { :; }
installer_fetch_host_env() { cp "$FIXTURE_ROOT/profile.env" "$3"; }
installer_assert_class_plan() { :; }
installer_runtime_state_dir() { printf '%s\n' "$FIXTURE_ROOT/state"; }
installer_class_metadata_read_path() { printf '%s\n' "$FIXTURE_ROOT/perl-assets.tsv"; }
blkid() { printf '%s\n' 00000000-0000-0000-0000-000000000001; }
# End this bounded stage replay immediately after its real first Perl asset.
# Later Python, AppArmor, swap and service publication is not exercised here.
install() {
  [ "$*" = "-d -m 0755 $TARGET_ROOT$DIR_PYTHON3_SITE_PACKAGES" ] || exit 93
  [ -s "$TARGET_ROOT$DIR_PERL5_SITE_PERL/Root.pm" ] || exit 94
  printf '%s|%s\n' "$ACCOUNT_USERNAME" "$ACCOUNT_HOME"
  exit 0
}
. "$FIXTURE_SOURCE/scripts/common/system-foundation.sh"
'''

LATE_ACCOUNT_SETUP = r'''
# Fetch and path-authority mocks are confined to this owned isolated fixture.
# The credential reader, restricted-data loader and account writer are real.
installer_operation_context_repo() { :; }
installer_apt_safe_path() {
  fixture_probe=$1
  case "$fixture_probe" in "$FIXTURE_ROOT"/*) ;; *) return 92 ;; esac
  case "$fixture_probe" in */../*|*/./*|*//*) return 92 ;; esac
  while [ "$fixture_probe" != "$FIXTURE_ROOT" ]; do
    [ ! -L "$fixture_probe" ] || return 92
    fixture_probe=${fixture_probe%/*}
  done
  [ ! -L "$FIXTURE_ROOT" ]
}
installer_fetch_account_env() {
  case "$2" in "$FIXTURE_ROOT"/state/.account-env.*/policy.env) ;; *) return 93 ;; esac
  cp "$FIXTURE_ROOT/account-policy.env" "$2" && chmod "$3" "$2"
}
installer_fetch_host_env() {
  case "$3" in "$FIXTURE_ROOT"/state/.account-env.*/profile.env) ;; *) return 93 ;; esac
  cp "$FIXTURE_ROOT/profile.env" "$3" && chmod "$4" "$3"
}
installer_repo_file_value() {
  case "$1" in
    FILE_RUNTIME_COMMON) printf '%s\n' scripts/runtime/common.sh ;;
    FILE_RUNTIME_ACCOUNT) printf '%s\n' scripts/runtime/account.sh ;;
    *) return 94 ;;
  esac
}
bootstrap_source_module() {
  case "$1" in
    scripts/runtime/common.sh)
      # Only the common definitions used by the real account writer are needed.
      . "$FIXTURE_SOURCE/scripts/runtime/modules/base.sh"
      . "$FIXTURE_SOURCE/scripts/runtime/modules/identity.sh"
      ;;
    scripts/runtime/account.sh) . "$FIXTURE_SOURCE/$1" ;;
    *) return 94 ;;
  esac
}
RUNTIME_ACCOUNT_CREDENTIALS_READY=1
'''


class PrimaryAccountContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix='primary-account-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for leaf in ('home', 'state', 'temp', 'target/site-perl', 'env'):
            (self.root / leaf).mkdir(parents=True, mode=0o700)
        self.credentials = self.root / 'preseed.env'
        self.credentials.write_text("PRESEED_PRIMARY_USERNAME='fileuser'\n", encoding='utf-8')
        self.credentials.chmod(0o600)
        (self.root / 'cmdline').write_text('quiet\n', encoding='ascii')
        (self.root / 'bootstrap.sh').write_text('# private fixture\n', encoding='ascii')
        self.environment = {
            'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'LC_ALL': 'C',
            'HOME': str(self.root / 'home'), 'TMPDIR': str(self.root / 'temp'),
            'FIXTURE_ROOT': str(self.root), 'FIXTURE_SOURCE': str(SOURCE),
            'INSTALLER_PRESEED_ENV_FILE': str(self.credentials),
            'INSTALLER_CMDLINE_FILE': str(self.root / 'cmdline'),
            'INSTALLER_BOOTSTRAP_LIB': str(self.root / 'bootstrap.sh'),
            'DIR_HOME': str(self.root / 'home'), 'DIR_USR': '/usr',
            'DIR_USR_LOCAL_SHARE': '/usr/local/share',
            'DIR_RUN': str(self.root / 'run'),
            'DIR_INSTALLER_LATE_ENV': str(self.root / 'state'),
            'DIR_INSTALLER_ENV': str(self.root / 'env'),
            'DIR_PERL5_SITE_PERL': '/site-perl', 'DIR_PYTHON3_SITE_PACKAGES': '/site-python',
            'TARGET_ROOT': str(self.root / 'target'),
            'INSTALLER_HOST_PROFILE': 'fixture', 'INSTALLER_HOST_VARIANT': 'desktop',
            'ACCOUNT_USERNAME': 'inherited', 'ACCOUNT_HOME': str(self.root / 'wrong-home'),
        }
        self.shells = [('/bin/sh', ['/bin/sh'])]
        if shutil.which('busybox'):
            self.shells.append(('busybox', [shutil.which('busybox'), 'sh']))

    def run_code(self, code: str, *, cmdline: str = 'quiet', shell: list[str] | None = None
                 ) -> subprocess.CompletedProcess[str]:
        return subprocess.run([*(shell or ['/bin/sh']), '-eu', '-c', SHELL_SETUP + code],
                              cwd=self.root,
                              env={**self.environment, 'INSTALLER_CMDLINE': cmdline},
                              capture_output=True, text=True, encoding='utf-8', timeout=15)

    def test_both_readers_share_username_aliases_and_first_occurrence(self) -> None:
        cases = (
            ('quiet', 'fileuser'), ('primary_username=bootuser', 'bootuser'),
            ('primary_user=legacyuser', 'legacyuser'),
            ('primary_username=first primary_user=second', 'first'),
            ('primary_user=first primary_username=second', 'first'),
            ('primary_username= primary_user=second', ''),
            ('primary_user primary_username=second', ''),
        )
        for name, shell in self.shells:
            for prefix in ('installer', 'runtime'):
                for key in ('primary_user', 'primary_username'):
                    for cmdline, expected in cases:
                        with self.subTest(shell=name, reader=prefix, key=key, cmdline=cmdline):
                            result = self.run_code(f'\n{prefix}_cmdline_value {key}\n',
                                                   cmdline=cmdline, shell=shell)
                            self.assertEqual(result.returncode, 0, result.stderr)
                            self.assertEqual(result.stdout, expected + '\n')

    def test_identity_only_loader_needs_no_password_and_replaces_inherited_identity(self) -> None:
        for cmdline, expected in (('quiet', 'fileuser'), ('primary_username=bootuser', 'bootuser')):
            result = self.run_code('\ninstaller_load_primary_account\n'
                                   'printf "%s|%s\\n" "$ACCOUNT_USERNAME" "$ACCOUNT_HOME"\n',
                                   cmdline=cmdline)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, f'{expected}|{self.root}/home/{expected}\n')

    def test_missing_unsafe_and_invalid_inputs_fail_before_asset_publication(self) -> None:
        original = self.credentials.read_text(encoding='utf-8')
        for cmdline, file_data in (
            ('quiet', ''), ('quiet', "PRESEED_PRIMARY_USERNAME=''\n"),
            ('quiet', "PRESEED_PRIMARY_USERNAME='root'\n"),
            ('quiet', "PRESEED_PRIMARY_USERNAME='one'\nPRESEED_PRIMARY_USERNAME='two'\n"),
            ('primary_username=', original), ('primary_username=../bad', original),
            ('primary_username=Root', original), ('primary_username=' + 'u' * 33, original),
        ):
            self.credentials.write_text(file_data, encoding='utf-8')
            with self.subTest(cmdline=cmdline, file_data=file_data):
                result = self.run_code('\ninstaller_load_primary_account\n'
                    'installer_stage_profile_asset "$FIXTURE_SOURCE/' + ACCOUNT_ASSET + '" /result.pm 0644\n',
                    cmdline=cmdline)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.root / 'target/result.pm').exists())
                self.assertEqual(result.stdout, '')
        self.credentials.write_text(original, encoding='utf-8')
        private_file = self.root / 'private-input.env'
        self.credentials.rename(private_file)
        self.credentials.symlink_to(private_file)
        result = self.run_code('\ninstaller_load_primary_account\n')
        self.assertEqual(result.returncode, 2, result.stderr)

    def test_real_asset_renderer_uses_resolved_account_and_reports_missing_asset_fields(self) -> None:
        render = ('\ninstaller_stage_profile_asset "$FIXTURE_SOURCE/' + ACCOUNT_ASSET +
                  '" /result.pm 0644\n')
        result = self.run_code('\ninstaller_load_primary_account\n' + render)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = (self.root / 'target/result.pm').read_text(encoding='utf-8')
        self.assertIn("default => sub { 'fileuser' }", output)
        self.assertNotIn('__INSTALLER_', output)
        self.assertEqual((self.root / 'target/result.pm').stat().st_mode & 0o777, 0o644)
        result = self.run_code('\nunset ACCOUNT_USERNAME\n' + render)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('profile asset lacks required field: ACCOUNT_USERNAME', result.stderr)
        self.assertIn(ACCOUNT_ASSET, result.stderr)
        self.assertEqual((self.root / 'target/result.pm').read_text(encoding='utf-8'), output)

    def test_early_account_and_late_identity_loader_agree(self) -> None:
        with self.credentials.open('a', encoding='utf-8') as stream:
            stream.write("PRESEED_PRIMARY_FULLNAME='Fixture User'\n"
                         "PRESEED_PRIMARY_PASSWORD='fixture-password'\n"
                         "PRESEED_ROOT_PASSWORD='fixture-root-password'\n")
        for cmdline, expected in (('quiet', 'fileuser'), ('primary_username=bootuser', 'bootuser')):
            result = self.run_code('\n. "$FIXTURE_SOURCE/scripts/runtime/account.sh"\n'
                'runtime_apply_account_from_credentials\n'
                'early_identity="$ACCOUNT_USERNAME|$ACCOUNT_HOME"\n'
                'unset ACCOUNT_USERNAME ACCOUNT_HOME\ninstaller_load_primary_account\n'
                '[ "$early_identity" = "$ACCOUNT_USERNAME|$ACCOUNT_HOME" ]\n'
                'printf "%s\\n" "$ACCOUNT_USERNAME"\n', cmdline=cmdline)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, expected + '\n')
            self.assertNotIn('fixture-password', result.stdout + result.stderr)
            self.assertNotIn('fixture-root-password', result.stdout + result.stderr)

    def test_fresh_shared_stage_renders_its_first_account_dependent_perl_asset(self) -> None:
        (self.root / 'profile.env').write_text(
            'DIR_HOME=' + shlex.quote(str(self.root / 'home')) + '\n', encoding='utf-8')
        (self.root / 'state/runtime.env').write_text(
            'ZRAM_BACKING_RAW_DEVICE=' + shlex.quote(str(self.root / 'zram-fixture')) + '\n',
            encoding='utf-8')
        (self.root / 'perl-assets.tsv').write_text(
            f'{SOURCE}/{ACCOUNT_ASSET}\tRoot.pm\tdesktop\n', encoding='utf-8')
        self.environment['ZRAM_SWAP_DEVICE'] = '/dev/zram0'
        self.environment['DIR_SYS'] = str(self.root / 'sys')
        self.environment['FILE_ZRAM_CONFIG'] = str(self.root / 'zram.conf')
        for name, shell in self.shells:
            for cmdline, expected in (('quiet', 'fileuser'), ('primary_username=bootuser', 'bootuser')):
                with self.subTest(shell=name, cmdline=cmdline):
                    result = self.run_code(FOUNDATION_SETUP, cmdline=cmdline, shell=shell)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, f'{expected}|{self.root}/home/{expected}\n')
                    rendered = (self.root / 'target/site-perl/Root.pm').read_text(encoding='utf-8')
                    self.assertIn(f"default => sub {{ '{expected}' }}", rendered)
                    self.assertNotIn('__INSTALLER_', rendered)

    def prepare_late_account_policy(self) -> Path:
        with self.credentials.open('a', encoding='utf-8') as stream:
            stream.write("PRESEED_PRIMARY_FULLNAME='Fixture User'\n"
                         "PRESEED_PRIMARY_PASSWORD='fixture-password'\n"
                         "PRESEED_ROOT_PASSWORD='fixture-root-password'\n")
        (self.root / 'account-policy.env').write_text(
            "ROOT_LOGIN='true'\nACCOUNT_DEFAULT_GROUPS='audio video sudo'\n"
            "SSHD_CONFIG_SOURCE='ssh/sshd_config'\nSSH_USER_CONFIG_SOURCE='ssh/config'\n"
            "SSH_PUBLIC_KEY_MAX_BYTES='4096'\nSSH_CONFIG_MAX_BYTES='65536'\n", encoding='ascii')
        (self.root / 'profile.env').write_text(
            'DIR_HOME=' + shlex.quote(str(self.root / 'home')) + '\n', encoding='utf-8')
        return self.root / 'state/account.env'

    def test_late_snapshot_reaches_a_fresh_shell_without_storage_stage(self) -> None:
        account = self.prepare_late_account_policy()
        for shell_name, shell in self.shells:
            for suite in ('forky', 'trixie'):
                for family in ('desktop', 'server'):
                    for cmdline, expected in (('quiet', 'fileuser'), ('primary_username=bootuser', 'bootuser')):
                        with self.subTest(shell=shell_name, suite=suite, family=family, cmdline=cmdline):
                            self.environment.update(INSTALLER_SUITE=suite, INSTALLER_HOST_VARIANT=family)
                            result = self.run_code(LATE_ACCOUNT_SETUP + r'''
installer_prepare_late_account_env fixture "$FIXTURE_ROOT/state/account.env"
# Child credential resolution and scratch variables must not change the parent.
[ "$ACCOUNT_USERNAME" = inherited ]
''', cmdline=cmdline, shell=shell)
                            self.assertEqual(result.returncode, 0, result.stderr)
                            data = account.read_text(encoding='utf-8')
                            self.assertNotIn('fixture-password', data + result.stdout + result.stderr)
                            self.assertNotIn('fixture-root-password', data + result.stdout + result.stderr)
                            self.assertNotIn('ACCOUNT_PASSWORD=', data)
                            self.assertNotIn('ROOT_PASSWORD=', data)
                            self.assertEqual(account.stat().st_mode & 0o777, 0o600)
                            self.assertFalse(list((self.root / 'state').glob('.account-env*')))
                            # No storage stage runs here. This checks the shared
                            # snapshot interface with a fresh data-reader shell;
                            # it does not replay individual installer providers.
                            consumer = self.run_code(r'''
unset ACCOUNT_USERNAME ACCOUNT_HOME
installer_load_data_env "$FIXTURE_ROOT/state/account.env"
printf '%s|%s\n' "$ACCOUNT_USERNAME" "$ACCOUNT_HOME"
''', cmdline=cmdline, shell=shell)
                            self.assertEqual(consumer.returncode, 0, consumer.stderr)
                            self.assertEqual(consumer.stdout, f'{expected}|{self.root}/home/{expected}\n')

    def test_late_snapshot_preserves_previous_bytes_on_writer_and_rename_failure(self) -> None:
        account = self.prepare_late_account_policy()
        previous = b"ACCOUNT_USERNAME='previous'\nACCOUNT_HOME='/previous-home'\n"
        for failure in ('writer', 'rename', 'policy'):
            with self.subTest(failure=failure):
                self.environment['FIXTURE_EXPECTED_STATUS'] = '2' if failure == 'policy' else '42'
                account.write_bytes(previous)
                account.chmod(0o600)
                if failure == 'writer':
                    injected = r'''
printf() {
  case "$1" in 'ACCOUNT_HOME=%s\n') return 42 ;; esac
  command printf "$@"
}
'''
                elif failure == 'rename':
                    injected = 'mv() { return 42; }\n'
                else:
                    (self.root / 'account-policy.env').write_text('ROOT_LOGIN=$(false)\n', encoding='ascii')
                    injected = ''
                result = self.run_code(LATE_ACCOUNT_SETUP + injected + r'''
if installer_prepare_late_account_env fixture "$FIXTURE_ROOT/state/account.env"; then
  exit 95
else
  status=$?
fi
[ "$status" = "$FIXTURE_EXPECTED_STATUS" ]
''')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(account.read_bytes(), previous)
                self.assertFalse(list((self.root / 'state').glob('.account-env*')))

    def test_late_snapshot_rejects_indirect_destination_and_another_publisher(self) -> None:
        account = self.prepare_late_account_policy()
        sentinel = self.root / 'sentinel.env'
        sentinel.write_bytes(b'preserve unrelated fixture bytes\n')
        sentinel.chmod(0o600)
        account.symlink_to(sentinel)
        result = self.run_code(LATE_ACCOUNT_SETUP + '\ninstaller_prepare_late_account_env fixture "$FIXTURE_ROOT/state/account.env"\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(sentinel.read_bytes(), b'preserve unrelated fixture bytes\n')
        self.assertTrue(account.is_symlink())
        account.unlink()
        lock = self.root / 'state/.account-env.lock'
        lock.mkdir(mode=0o700)
        result = self.run_code(LATE_ACCOUNT_SETUP + '\ninstaller_prepare_late_account_env fixture "$FIXTURE_ROOT/state/account.env"\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(lock.is_dir())
        self.assertFalse(account.exists())

    def test_late_snapshot_retains_evidence_when_cleanup_fails(self) -> None:
        account = self.prepare_late_account_policy()
        result = self.run_code(LATE_ACCOUNT_SETUP + r'''
rmdir() {
  case "$1" in "$FIXTURE_ROOT"/state/.account-env.*) return 51 ;; esac
  command rmdir "$@"
}
if installer_prepare_late_account_env fixture "$FIXTURE_ROOT/state/account.env"; then
  exit 95
else
  status=$?
fi
[ "$status" = 125 ]
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(account.is_file())
        self.assertTrue((self.root / 'state/.account-env.lock').is_dir())
        self.assertTrue(list((self.root / 'state').glob('.account-env.??????')))
        self.assertIn('private evidence and lock retained', result.stderr)
        self.assertNotIn('fixture-password', result.stdout + result.stderr)
        self.assertNotIn('fixture-root-password', result.stdout + result.stderr)

    def test_late_snapshot_rejects_destination_replacement_before_publication(self) -> None:
        account = self.prepare_late_account_policy()
        previous = b"ACCOUNT_USERNAME='previous'\nACCOUNT_HOME='/previous-home'\n"
        account.write_bytes(previous)
        account.chmod(0o600)
        sentinel = self.root / 'sentinel.env'
        sentinel.write_bytes(b'preserve unrelated fixture bytes\n')
        sentinel.chmod(0o600)
        result = self.run_code(LATE_ACCOUNT_SETUP + r'''
fixture_path_checks=0
installer_apt_safe_path() {
  [ "$1" = "$FIXTURE_ROOT/state/account.env" ] || return 92
  fixture_path_checks=$((fixture_path_checks + 1))
  if [ "$fixture_path_checks" -eq 2 ]; then
    mv "$1" "$FIXTURE_ROOT/retained-account.env" || return 92
    ln -s "$FIXTURE_ROOT/sentinel.env" "$1" || return 92
    return 92
  fi
  [ ! -L "$1" ]
}
installer_prepare_late_account_env fixture "$FIXTURE_ROOT/state/account.env"
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ancestry changed before publication', result.stderr)
        self.assertEqual(sentinel.read_bytes(), b'preserve unrelated fixture bytes\n')
        self.assertEqual((self.root / 'retained-account.env').read_bytes(), previous)
        self.assertTrue(account.is_symlink())
        self.assertFalse(list((self.root / 'state').glob('.account-env*')))
