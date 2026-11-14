"""Exercise real modular entrypoints against the authenticated payload.

Unlike isolated function fixtures, these tests never flatten modules, replace
loader functions, or invoke installer actions against a real installation target.
"""
from __future__ import annotations

# Refuse host execution before importing runtime helpers or creating fixtures.
from pathlib import Path as _IsolationPath
import sys as _isolation_sys
_isolation_sys.path.insert(0, str(_IsolationPath(__file__).resolve().parents[3] / 'tools'))
# Copied checker/GUI fixtures still use the verified private checkout gate.
_isolation_sys.path.insert(0, '/workspace/repository/tools')
from isolation import require_test_isolation as _require_test_isolation
_isolation_sys.path.pop(0)
_require_test_isolation()

import hashlib
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

SEED = Path(__file__).resolve().parents[1]
Q = shlex.quote
SHELLS = [['/bin/dash']]
if shutil.which('busybox'):
    SHELLS.append([shutil.which('busybox'), 'sh'])

class RealModuleLoader(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='real-installer-modules-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.runtime = self.root / 'runtime'
        self.env = {'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'LC_ALL': 'C',
                    'HOME': str(self.root), 'TMPDIR': str(self.root),
                    'FIXTURE_ROOT': str(self.root), 'INSTALLER_CMDLINE': 'quiet'}
        self.use_product('forky')

    def use_product(self, suite):
        product = SEED.parent / suite
        self.env.update(INSTALLER_RUNTIME_DIR=str(self.runtime),
                        INSTALLER_SOURCE_ROOT=str(product), INSTALLER_SUITE=suite)
        archive = hashlib.sha256((product / 'payload.tar.gz').read_bytes()).hexdigest()
        manifest = hashlib.sha256((product / 'payload.manifest').read_bytes()).hexdigest()
        self.prelude = f'''. {Q(str(product / 'source.sh'))}
source_prepare_payload {Q(str(product))} {archive} {manifest}
source_fetch {Q(str(product))} scripts/common/bootstrap.sh "$INSTALLER_RUNTIME_DIR/bootstrap/bootstrap.sh" 0600
. "$INSTALLER_RUNTIME_DIR/bootstrap/bootstrap.sh"
bootstrap_persist_seed_source {Q(str(product))}
'''

    def run_shell(self, code, *, shell=None, prepare=True):
        return subprocess.run([*(shell or SHELLS[0]), '-eu', '-c',
                               (self.prelude if prepare else '') + code],
                              env=self.env, text=True, capture_output=True, timeout=60)

    def assert_ok(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_all_groups_load_in_dash_and_ash_without_changing_arguments_or_globals(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.run_shell('''
set -- first second
module_relative=sentinel
bootstrap_source_common_lib "$INSTALLER_SOURCE_ROOT"
bootstrap_fetch_seed_file "$INSTALLER_SOURCE_ROOT" scripts/runtime/common.sh "$INSTALLER_RUNTIME_DIR/bootstrap/runtime-common.sh"
. "$INSTALLER_RUNTIME_DIR/bootstrap/runtime-common.sh"
bootstrap_fetch_seed_file "$INSTALLER_SOURCE_ROOT" scripts/desktop/components.sh "$INSTALLER_RUNTIME_DIR/bootstrap/components.sh"
. "$INSTALLER_RUNTIME_DIR/bootstrap/components.sh"
'''+''.join(f"bootstrap_source_module {Q(name)}\n" for name in self.devops_modules())+'''
[ "$1:$2" = first:second ]
[ "$module_relative" = sentinel ]
for function in installer_fetch_host_env runtime_generate_crypto_bootstrap_key desktop_normalize_system_perl_module_parents devops_main; do
  command -v "$function" >/dev/null
done
printf 'loaded\\n'
''', shell=shell)
                self.assert_ok(result)
                self.assertEqual(result.stdout, 'loaded\n')

    @staticmethod
    def devops_modules():
        from payload_fixture import module_source_paths
        return list(module_source_paths((SEED / 'scripts/late/devops.sh.tmpl').read_text(encoding='utf-8')))

    def test_cached_common_entrypoint_works_in_a_fresh_hook_process(self):
        self.assert_ok(self.run_shell('bootstrap_source_common_lib "$INSTALLER_SOURCE_ROOT"\n'))
        result = self.run_shell('''. "$INSTALLER_RUNTIME_DIR/bootstrap/common-lib.sh"
command -v installer_fetch_host_env >/dev/null
printf 'standalone-hook-loaded\\n'
''', prepare=False)
        self.assert_ok(result)
        self.assertEqual(result.stdout, 'standalone-hook-loaded\n')

    def test_account_entrypoints_use_real_loader_and_storage_siblings_stay_rejected(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.run_shell('''
bootstrap_source_common_lib "$INSTALLER_SOURCE_ROOT"
bootstrap_source_module "$(bootstrap_repo_file_value FILE_RUNTIME_COMMON)"
bootstrap_source_module "$(bootstrap_repo_file_value FILE_RUNTIME_ACCOUNT)"
command -v runtime_write_effective_account_env >/dev/null
for selector in FILE_RUNTIME_BTRFS FILE_RUNTIME_F2FS; do
  if bootstrap_source_module "$(bootstrap_repo_file_value "$selector")"; then exit 88; fi
done
printf 'account-entrypoints-loaded\\n'
''', shell=shell)
                self.assert_ok(result)
                self.assertEqual(result.stdout, 'account-entrypoints-loaded\n')

    def account_case(self, suite, family, phase, username):
        # Every case has a private runtime/cache and synthetic credentials.
        self.runtime = self.root / suite / family / phase / username / 'runtime'
        self.runtime.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.use_product(suite)
        credentials = self.runtime.parent / 'credentials.env'
        credentials.write_text("PRESEED_PRIMARY_USERNAME='fileuser'\n"
                               "PRESEED_PRIMARY_FULLNAME='Fixture User'\n"
                               "PRESEED_PRIMARY_PASSWORD='fixture-password'\n"
                               "PRESEED_ROOT_PASSWORD='fixture-root-password'\n", encoding='ascii')
        credentials.chmod(0o600)
        profile = 'btrfs-de' if family == 'desktop' else 'btrfs-srv-flex'
        self.env.update(INSTALLER_PRESEED_ENV_FILE=str(credentials),
                        INSTALLER_HOST_VARIANT=family, INSTALLER_HOST_PROFILE_ENV_NAME=profile,
                        INSTALLER_HOST_PROFILE=profile, FIXTURE_USERNAME=username,
                        FIXTURE_ENV_DIR=str(self.runtime.parent / 'phase-env'),
                        INSTALLER_CMDLINE='quiet' if username == 'fileuser' else 'primary_username=bootuser')

    def assert_private_snapshot(self):
        snapshot = Path(self.env['FIXTURE_ENV_DIR']) / 'account.env'
        data = snapshot.read_text(encoding='utf-8')
        self.assertEqual(snapshot.stat().st_mode & 0o777, 0o600)
        self.assertIn("ACCOUNT_USERNAME='" + self.env['FIXTURE_USERNAME'] + "'", data)
        self.assertNotIn('fixture-password', data)
        self.assertNotIn('fixture-root-password', data)
        self.assertFalse(list(snapshot.parent.glob('.account-env*')))

    def test_real_publisher_resolves_both_username_sources_without_inherited_profile(self):
        for suite in ('forky', 'trixie'):
            for family in ('desktop', 'server'):
                for username in ('fileuser', 'bootuser'):
                    for shell in SHELLS:
                        with self.subTest(suite=suite, family=family, username=username, shell=shell):
                            self.account_case(suite, family, 'standalone-' + Path(shell[0]).name, username)
                            result = self.run_shell('''
bootstrap_source_common_lib "$INSTALLER_SOURCE_ROOT"
unset DIR_HOME
ACCOUNT_USERNAME=inherited
ACCOUNT_HOME=inherited
RUNTIME_ACCOUNT_CREDENTIALS_READY=1
installer_prepare_late_account_env "$INSTALLER_SOURCE_ROOT" "$FIXTURE_ENV_DIR/account.env"
[ "${DIR_HOME+x}" != x ]
[ "$ACCOUNT_USERNAME:$ACCOUNT_HOME" = inherited:inherited ]
''', shell=shell)
                            self.assert_ok(result)
                            self.assert_private_snapshot()
                            # A separate shell reads the actual restricted-data
                            # snapshot; no storage provider or inherited user.
                            reader = self.run_shell('''
bootstrap_source_common_lib "$INSTALLER_SOURCE_ROOT"
installer_fetch_host_env "$INSTALLER_SOURCE_ROOT" "$INSTALLER_HOST_PROFILE" "$FIXTURE_ENV_DIR/host.env" 0600
installer_load_data_env "$FIXTURE_ENV_DIR/host.env"
unset ACCOUNT_USERNAME ACCOUNT_HOME
installer_load_data_env "$FIXTURE_ENV_DIR/account.env"
[ "$ACCOUNT_USERNAME" = "$FIXTURE_USERNAME" ]
[ "$ACCOUNT_HOME" = "$DIR_HOME/$FIXTURE_USERNAME" ]
''', shell=shell)
                            self.assert_ok(reader)

    def test_real_core_separates_profile_and_account_at_both_phase_boundaries(self):
        for suite in ('forky', 'trixie'):
            for family in ('desktop', 'server'):
                for phase in ('pre-pkgsel', 'late'):
                    for shell in SHELLS:
                        with self.subTest(suite=suite, family=family, phase=phase, shell=shell):
                            self.account_case(suite, family, phase + '-' + Path(shell[0]).name, 'fileuser')
                            result = self.run_shell('''
bootstrap_source_common_lib "$INSTALLER_SOURCE_ROOT"
TMP_ENV_DIR=$FIXTURE_ENV_DIR
install -d -m 0700 "$TMP_ENV_DIR"
for selector in FILE_LATE_CORE FILE_RUNTIME_COMMON FILE_RUNTIME_ACCOUNT; do
  case "$selector" in
    FILE_LATE_CORE) leaf=core.sh ;;
    FILE_RUNTIME_COMMON) leaf=runtime-common.sh ;;
    FILE_RUNTIME_ACCOUNT) leaf=account-runtime.sh ;;
  esac
  bootstrap_fetch_seed_file "$INSTALLER_SOURCE_ROOT" "$(bootstrap_repo_file_value "$selector")" "$TMP_ENV_DIR/$leaf" 0600
done
. "$TMP_ENV_DIR/core.sh"
# Theme publication and storage/target actions are outside this handoff fixture.
# The profile loader, parser, publisher and module loader remain the real code.
late_command_load_themes() { :; }
SEED_BASE=$INSTALLER_SOURCE_ROOT
HOST_PROFILE=$INSTALLER_HOST_PROFILE
unset DIR_HOME ACCOUNT_USERNAME ACCOUNT_HOME RUNTIME_ACCOUNT_CREDENTIALS_READY
late_command_load_profile_env
[ -n "$DIR_HOME" ]
[ ! -e "$TMP_ENV_DIR/account.env" ]
late_command_load_host_env
[ "$ACCOUNT_USERNAME" = "$FIXTURE_USERNAME" ]
[ "$ACCOUNT_HOME" = "$DIR_HOME/$FIXTURE_USERNAME" ]
[ "$LATE_COMMAND_PROFILE_ENV_LOADED:$LATE_COMMAND_ACCOUNT_ENV_LOADED" = 1:1 ]
late_command_load_host_env
''', shell=shell)
                            self.assert_ok(result)
                            self.assert_private_snapshot()

    def test_real_publisher_preserves_previous_snapshot_if_authenticated_runtime_is_missing(self):
        self.account_case('forky', 'desktop', 'missing-runtime', 'fileuser')
        snapshot = Path(self.env['FIXTURE_ENV_DIR']) / 'account.env'
        snapshot.parent.mkdir(mode=0o700)
        previous = b"ACCOUNT_USERNAME='previous'\nACCOUNT_HOME='/previous-home'\n"
        snapshot.write_bytes(previous)
        snapshot.chmod(0o600)
        result = self.run_shell('''
bootstrap_source_common_lib "$INSTALLER_SOURCE_ROOT"
cache=$(source_cache_root "$INSTALLER_SOURCE_ROOT")
rm "$cache/$(bootstrap_repo_file_value FILE_RUNTIME_ACCOUNT)"
installer_prepare_late_account_env "$INSTALLER_SOURCE_ROOT" "$FIXTURE_ENV_DIR/account.env"
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('selector=FILE_RUNTIME_ACCOUNT', result.stderr)
        self.assertIn('resolved account runtime could not be loaded', result.stderr)
        self.assertEqual(snapshot.read_bytes(), previous)
        self.assertFalse(list(snapshot.parent.glob('.account-env*')))
        self.assertNotIn('fixture-password', result.stdout + result.stderr)
        self.assertNotIn('fixture-root-password', result.stdout + result.stderr)

    def test_missing_authenticated_module_never_falls_back_to_local_source_or_stale_copy(self):
        result = self.run_shell('''
bootstrap_source_common_lib "$INSTALLER_SOURCE_ROOT"
cache=$(source_cache_root "$INSTALLER_SOURCE_ROOT")
rm "$cache/scripts/common/modules/files-logging.sh"
if bootstrap_source_module scripts/common/modules/files-logging.sh; then exit 88; fi
printf 'rejected\\n'
''')
        self.assert_ok(result)
        self.assertIn('file absent from validated payload', result.stderr)
        self.assertEqual(result.stdout, 'rejected\n')

    def test_source_symlink_is_rejected(self):
        result = self.run_shell('''
cache=$(source_cache_root "$INSTALLER_SOURCE_ROOT")
rm "$cache/scripts/common/credentials.sh"
ln -s /etc/passwd "$cache/scripts/common/credentials.sh"
if bootstrap_source_module scripts/common/credentials.sh; then exit 88; fi
''')
        self.assert_ok(result)
        self.assertIn('symlinked repository source', result.stderr)

    def test_module_directory_symlink_cannot_write_outside_runtime(self):
        outside = self.root / 'outside'
        outside.mkdir()
        result = self.run_shell(f'''
ln -s {Q(str(outside))} "$INSTALLER_RUNTIME_DIR/bootstrap/modules"
if bootstrap_source_module scripts/common/credentials.sh; then exit 88; fi
''')
        self.assert_ok(result)
        self.assertIn('symlinked module directory', result.stderr)
        self.assertEqual(list(outside.iterdir()), [])

    def test_world_writable_module_directory_is_not_silently_repaired(self):
        result = self.run_shell('''
mkdir "$INSTALLER_RUNTIME_DIR/bootstrap/modules"
chmod 0777 "$INSTALLER_RUNTIME_DIR/bootstrap/modules"
if bootstrap_source_module scripts/common/credentials.sh; then exit 88; fi
''')
        self.assert_ok(result)
        self.assertIn('unsafe module directory', result.stderr)
        self.assertEqual((self.runtime / 'bootstrap/modules').stat().st_mode & 0o777, 0o777)

    def test_existing_hardlinked_module_destination_is_rejected(self):
        result = self.run_shell('''
bootstrap_source_module scripts/common/credentials.sh
ln "$INSTALLER_RUNTIME_DIR/bootstrap/modules/scripts/common/credentials.sh" "$INSTALLER_RUNTIME_DIR/alias"
        if bootstrap_source_module scripts/common/credentials.sh; then exit 88; fi
''')
        self.assert_ok(result)

    def test_typed_parser_asset_resolver_is_separate_and_authenticated(self):
        result = self.run_shell('''
bootstrap_source_common_lib "$INSTALLER_SOURCE_ROOT"
parser=$(bootstrap_parser_asset_path scripts/common/credential-data.awk)
[ -f "$parser" ] && [ ! -L "$parser" ]
LC_ALL=C awk -f "$parser" -v mode=snapshot /dev/null >/dev/null
if bootstrap_parser_asset_path scripts/common/credentials.sh; then exit 88; fi
if bootstrap_module_path scripts/common/credential-data.awk; then exit 88; fi
printf 'typed-parser-ok\\n'
''')
        self.assert_ok(result)
        self.assertEqual(result.stdout, 'typed-parser-ok\n')

    def test_parser_asset_missing_or_tampered_snapshot_fails_closed(self):
        result = self.run_shell('''
bootstrap_source_common_lib "$INSTALLER_SOURCE_ROOT"
parser_cache=$(source_cache_root "$INSTALLER_SOURCE_ROOT")/scripts/common/credential-data.awk
rm "$parser_cache"
if bootstrap_parser_asset_path scripts/common/credential-data.awk; then exit 88; fi
printf 'missing-parser-rejected\\n'
''')
        self.assert_ok(result)
        self.assertEqual(result.stdout, 'missing-parser-rejected\n')

    def test_parser_asset_path_identity_variants_fail_closed(self):
        result = self.run_shell('''
bootstrap_source_common_lib "$INSTALLER_SOURCE_ROOT"
parser_parent="$INSTALLER_RUNTIME_DIR/bootstrap/data/scripts/common"
parser_destination="$parser_parent/credential-data.awk"
mkdir -p "$parser_parent"
outside="$INSTALLER_RUNTIME_DIR/outside-parser"
printf '%s\\n' fixture >"$outside"
ln -s "$outside" "$parser_destination"
if bootstrap_parser_asset_path scripts/common/credential-data.awk; then exit 88; fi
rm "$parser_destination"
ln "$outside" "$parser_destination"
if bootstrap_parser_asset_path scripts/common/credential-data.awk; then exit 88; fi
rm "$parser_destination"
chmod 0777 "$parser_parent"
if bootstrap_parser_asset_path scripts/common/credential-data.awk; then exit 88; fi
chmod 0700 "$parser_parent"
printf '%s\\n' fixture >"$parser_destination"
chmod 0644 "$parser_destination"
if bootstrap_parser_asset_path scripts/common/credential-data.awk; then exit 88; fi
if bootstrap_parser_asset_path scripts/common/credentials.sh; then exit 88; fi
printf 'parser-path-variants-rejected\\n'
''')
        self.assert_ok(result)
        self.assertEqual(result.stdout, 'parser-path-variants-rejected\n')

    def test_remote_loading_without_authenticated_payload_does_not_contact_network(self):
        result = self.run_shell('''
rm "$INSTALLER_RUNTIME_DIR/bootstrap/payload.ready"
bootstrap_persist_seed_source https://never-fetch.invalid/d-i/forky
source_transfer() { printf 'CONTACTED\\n'; return 99; }
if bootstrap_source_module scripts/common/credentials.sh; then exit 88; fi
''')
        self.assert_ok(result)
        self.assertNotIn('CONTACTED', result.stdout + result.stderr)
        self.assertIn('requires the authenticated payload', result.stderr)

    def test_traversal_and_unregistered_module_prefixes_are_rejected(self):
        result = self.run_shell('''
for path in ../escape.sh /etc/passwd scripts/common/../escape.sh hooks/target/run.sh; do
  if bootstrap_source_module "$path"; then exit 88; fi
done
''')
        self.assert_ok(result)

if __name__ == '__main__': unittest.main()
