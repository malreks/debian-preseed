"""Source and failure-injection fixtures for selectors and late diagnostics.

These fixtures remain unexecuted under the repository's static-only policy.
The shell snippets extract narrowly scoped functions, stub their dependencies,
and never invoke an installer, renderer, host service, or management helper.
"""
from __future__ import annotations

from pathlib import Path as _IsolationPath
import sys as _isolation_sys
_isolation_sys.path.insert(0, str(_IsolationPath(__file__).resolve().parents[3] / 'tools'))
_isolation_sys.path.insert(0, '/workspace/repository/tools')
from isolation import require_test_isolation as _require_test_isolation
_isolation_sys.path.pop(0)
_require_test_isolation()

from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from payload_fixture import module_source_paths, repository_selectors

SEED = Path(__file__).resolve().parents[1]


def function_source(relative: str, name: str) -> str:
    text = (SEED / relative).read_text(encoding='utf-8')
    definition = re.search(r'^' + re.escape(name) + r'\(\) [({]\n', text, re.MULTILINE)
    if definition is None:
        raise ValueError('missing fixture function: ' + name)
    start = definition.start()
    following = re.search(r'^\w+\(\) [({]', text[start + 1:], re.MULTILINE)
    end = start + 1 + following.start() if following else len(text)
    return text[start:end]


class SelectorDiagnostics(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix='selector-diagnostics-')
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name)

    def shell(self, snippet: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ['/bin/dash', '-eu', '-c', snippet],
            cwd=self.path, env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'},
            capture_output=True, text=True, encoding='utf-8', timeout=5,
            check=False,
        )

    def test_fail2ban_uses_ssh_policy_without_querying_a_retired_class(self) -> None:
        stage = function_source('scripts/late/security.sh', 'configure_target_fail2ban')
        for enabled in ('true', 'false'):
            with self.subTest(enabled=enabled):
                result = self.shell('''
installer_operation_context_repo() { printf 'context:%s\n' "$3"; }
runtime_apply_ssh_from_classes() { SSH_SERVER_ENABLED=''' + enabled + '''; }
installer_selected_class_reference_is_selected() { exit 99; }
installer_repo_file_value() { printf '%s\n' "$1"; }
installer_repo_asset_path() { printf '%s/%s\n' "$1" "$2"; }
install() { :; }
stage_target_asset() { :; }
render_target_asset_with_placeholder_map() { :; }
normalize_target_tmpfiles_directory_policy() { :; }
run_in_target() { printf 'target:%s\n' "$1"; }
stage_target_systemd_unit_enabled() { printf 'enable:%s\n' "$1"; }
security_mask_target_systemd_unit_if_available() { printf 'mask:%s\n' "$1"; }
TARGET_ROOT=$PWD
DIR_ETC=/etc
DIR_SYSTEMD_SYSTEM_FAIL2BAN_DROPIN=/etc/systemd/system/fail2ban.service.d
''' + stage + '\nconfigure_target_fail2ban\n')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('context:configure_target_fail2ban', result.stdout)
                if enabled == 'true':
                    self.assertIn('target:validate Fail2ban configuration', result.stdout)
                    self.assertIn('enable:fail2ban.service', result.stdout)
                else:
                    self.assertNotIn('target:validate Fail2ban configuration', result.stdout)
                    self.assertIn('mask:fail2ban.service', result.stdout)

    def test_fail2ban_preserves_a_failed_ssh_policy_status(self) -> None:
        stage = function_source('scripts/late/security.sh', 'configure_target_fail2ban')
        result = self.shell('''
installer_operation_context_repo() { :; }
runtime_apply_ssh_from_classes() { return 42; }
install() { printf 'unexpected publication\n'; exit 99; }
''' + stage + '\nconfigure_target_fail2ban\n')
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertEqual(result.stdout, '')

    def test_selected_software_worker_reports_completion_only_after_success(self) -> None:
        stage = function_source('scripts/late/software.sh.tmpl', 'software_run_selected_app')
        # Unlike sourced modules, this entrypoint has executable top-level
        # installation work between definitions. Keep all of it out of fixtures.
        stage = stage.split('\nif [ "$software_scx_only"', 1)[0]
        for status in (0, 37):
            with self.subTest(status=status):
                result = self.shell('''
installer_class_selected_any() { return 0; }
installer_operation_context_repo() { printf 'context:%s\n' "$3"; }
software_info() { printf '%s\n' "$*"; }
software_warn() { printf '%s\n' "$*" >&2; }
software_fatal() { printf '%s\n' "$*" >&2; exit 1; }
fixture_worker() { return ''' + str(status) + '''; }
target_root=$PWD
work_dir=/unused-private-fixture-state
installed=false
''' + stage + '\nsoftware_run_selected_app role/desktop/full Fixture fixture_worker installed\n'
                    + 'printf "installed:%s\\n" "$installed"\n')
                self.assertIn('context:install_managed_application:fixture_worker', result.stdout)
                self.assertIn('starting Fixture', result.stdout)
                if status == 0:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn('completed Fixture', result.stdout)
                    self.assertIn('installed:true', result.stdout)
                else:
                    self.assertEqual(result.returncode, 1, result.stderr)
                    self.assertNotIn('completed Fixture', result.stdout)
                    self.assertIn('status=37', result.stderr)

    def test_software_logs_use_the_shared_console_sink(self) -> None:
        source = '\n'.join(function_source('scripts/late/software.sh.tmpl', name)
                           for name in ('software_info', 'software_warn'))
        result = self.shell('''
installer_info() { printf 'info:%s\n' "$*"; }
installer_warn() { printf 'warning:%s\n' "$*"; }
''' + source + '\nsoftware_info Fixture\nsoftware_warn Fixture\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'info:Fixture\nwarning:Fixture\n')
        self.assertEqual(result.stderr, '')

    def test_file_context_keeps_three_argument_line_and_operation(self) -> None:
        function = function_source('scripts/common/modules/runtime-console.sh',
                                   'installer_operation_context_repo')
        result = self.shell('''
installer_loaded_repo_file_value() { printf '%s\n' fixture.sh; }
installer_operation_context() { printf '%s|%s|%s\n' "$1" "$2" "$3"; }
''' + function + '\ninstaller_operation_context_repo FILE_FIXTURE 37 fetch_fixture\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'fixture.sh|37|fetch_fixture\n')

    def test_missing_diagnostic_selector_does_not_fail_operation(self) -> None:
        function = function_source('scripts/common/modules/runtime-console.sh',
                                   'installer_operation_context_repo')
        result = self.shell('''
installer_loaded_repo_file_value() { return 43; }
installer_operation_context() { printf '%s|%s|%s\n' "$1" "$2" "$3"; }
''' + function + '\ninstaller_operation_context_repo FILE_MISSING 38 continue_fixture\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'unknown|38|continue_fixture\n')

    def test_directory_context_keeps_four_argument_interface(self) -> None:
        function = function_source('scripts/common/modules/runtime-console.sh',
                                   'installer_operation_context_repo')
        result = self.shell('''
installer_loaded_repo_dir_value() { printf '%s\n' fixture; }
installer_operation_context() { printf '%s|%s|%s\n' "$1" "$2" "$3"; }
''' + function + '\ninstaller_operation_context_repo DIR_FIXTURE item.sh 39 directory_fixture\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'fixture/item.sh|39|directory_fixture\n')

    def test_failed_fetch_retains_status_and_source_destination(self) -> None:
        function = function_source('scripts/late/core.sh', 'late_command_fetch_asset')
        result = self.shell('''
fetch_hook() { return 43; }
installer_fatal_status() { fixture_status=$1; shift; printf '%s\n' "$*" >&2; exit "$fixture_status"; }
''' + function + '\nlate_command_fetch_asset fixture.tmpl staged-file fixture\n')
        self.assertEqual(result.returncode, 43, result.stderr)
        self.assertIn('source=fixture.tmpl destination=staged-file', result.stderr)

    def test_profile_is_loaded_before_first_common_asset_render(self) -> None:
        function = function_source('scripts/late/core.sh', 'late_command_fetch_common_assets')
        result = self.shell('''
TMP_ENV_DIR=fixture-env
profile_ready=0
late_command_load_profile_env() { profile_ready=1; }
late_command_fetch_repo_file() { [ "$profile_ready" = 1 ] || exit 91; }
late_command_fetch_asset() { [ "$profile_ready" = 1 ] || exit 92; }
''' + function + '\nlate_command_fetch_common_assets fixture-runtime.sh\n')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_fetch_error_keeps_status_without_publishing_terminal_failure(self) -> None:
        function = function_source('scripts/common/modules/repository-apt.sh',
                                   'installer_fetch_seed_path')
        result = self.shell('''
installer_operation_context_repo() { :; }
installer_load_source_library() { return 43; }
installer_error() { printf '%s\n' "$*" >&2; }
installer_fatal_status() { printf '%s\n' unexpected-terminal-failure >&2; exit 99; }
''' + function + '\ninstaller_fetch_seed_path fixture-source asset.tmpl destination 0600\n')
        self.assertEqual(result.returncode, 43, result.stderr)
        self.assertIn('status=43 step=load_source source=asset.tmpl destination=destination', result.stderr)
        self.assertNotIn('unexpected-terminal-failure', result.stderr)

    def test_nested_fetch_exit_retains_original_acquisition_arguments(self) -> None:
        function = function_source('scripts/common/modules/repository-apt.sh',
                                   'installer_fetch_seed_path')
        for boundary in ('load', 'fetch'):
            with self.subTest(boundary=boundary):
                result = self.shell('''
DIR_HOOKS_TARGET=hooks/target
DIR_SCRIPTS_LATE=scripts/late
DIR_SCRIPTS_DESKTOP=scripts/desktop
DIR_SCRIPTS_FIRSTBOOT=scripts/firstboot
installer_operation_context_repo() { :; }
fixture_nested_fatal() { exit 43; }
installer_load_source_library() {
  [ "$FIXTURE_BOUNDARY" != load ] || fixture_nested_fatal unrelated wrong-source wrong-destination
}
source_fetch() { fixture_nested_fatal unrelated wrong-source wrong-destination; }
installer_error() { printf '%s\n' "$*" >&2; }
''' + f'FIXTURE_BOUNDARY={boundary}\n' + function +
                    '\ninstaller_fetch_seed_path fixture-source asset.tmpl destination 0600\n')
                self.assertEqual(result.returncode, 43, result.stderr)
                self.assertIn('source=asset.tmpl destination=destination', result.stderr)
                self.assertNotIn('wrong-source', result.stderr)
                self.assertNotIn('wrong-destination', result.stderr)

    def test_empty_fetch_inputs_fail_before_loading_source_library(self) -> None:
        function = function_source('scripts/common/modules/repository-apt.sh',
                                   'installer_fetch_seed_path')
        for arguments in ('fixture-source "" destination', 'fixture-source asset.tmpl ""'):
            with self.subTest(arguments=arguments):
                result = self.shell('''
installer_operation_context_repo() { :; }
installer_load_source_library() { printf '%s\n' unexpected-source-load >&2; exit 99; }
installer_error() { printf '%s\n' "$*" >&2; }
''' + function + '\ninstaller_fetch_seed_path ' + arguments + ' 0600\n')
                self.assertEqual(result.returncode, 64, result.stderr)
                self.assertIn('step=validate', result.stderr)
                self.assertNotIn('unexpected-source-load', result.stderr)

    def test_empty_publication_source_fails_before_destination_preparation(self) -> None:
        function = function_source('scripts/late/target-assets.sh', 'publish_target_asset')
        result = self.shell('''
installer_operation_context_repo() { :; }
installer_fatal() { printf '%s\n' "$*" >&2; exit 43; }
installer_fatal_status() { fixture_status=$1; shift; printf '%s\n' "$*" >&2; exit "$fixture_status"; }
target_asset_host_path() { printf '%s\n' unexpected-target-preparation >&2; exit 99; }
''' + function + '\npublish_target_asset "" /fixture-destination 0644 plain\n')
        self.assertEqual(result.returncode, 43, result.stderr)
        self.assertIn('source is empty', result.stderr)
        self.assertNotIn('unexpected-target-preparation', result.stderr)

    def firewall_seed_program(self) -> str:
        source = (SEED / 'scripts/late/security.sh').read_text(encoding='utf-8')
        start = source.index('  # These are administrator state, not disposable generated policy.')
        end = source.index('\n  stage_target_asset \\\n    "$(installer_repo_file_value FILE_TARGET_UNIT_NFTABLES_SERVICE_D_OVERRIDE)"', start)
        block = source[start:end].replace('__INSTALLER_PATH_DIR_ETC__', '/etc')
        values = repository_selectors()
        keys = ('FILE_TARGET_NFTABLES_FIREWALL_SECURITY',
                'FILE_TARGET_NFTABLES_D_95_FIREWALL_SECURITY_NFT')
        catalog_path = self.path / 'selectors.tsv'
        catalog_path.write_text(''.join(key + '\t' + values[key] + '\n' for key in keys))
        return '''
TARGET_ROOT=$PWD
installer_operation_context_repo() { :; }
installer_fatal() { printf '%s\n' "$*" >&2; exit 43; }
installer_metadata_value() { printf '%s\n' 0:0:644:1; }
installer_repo_file_value() {
  [ "${FIXTURE_MISSING_SELECTOR:-false}" = false ] || return 44
  awk -F '\t' -v key="$1" '$1==key {print $2; found=1; exit} END {if(!found) exit 44}' selectors.tsv
}
stage_target_asset() {
  case "$2" in /etc/nftables/firewall-security.rules|/etc/nftables.d/95-firewall-security.nft) ;; *) exit 92 ;; esac
  printf '%s|%s|%s\n' "$1" "$2" "$3" >>published.tsv
}
seed_firewall_state() {
''' + block + '\n}\nseed_firewall_state\n'

    def test_firewall_state_uses_both_physical_source_selectors(self) -> None:
        result = self.shell(self.firewall_seed_program())
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = (self.path / 'published.tsv').read_text().splitlines()
        values = repository_selectors()
        self.assertEqual(rows, [
            values['FILE_TARGET_NFTABLES_FIREWALL_SECURITY'] +
            '|/etc/nftables/firewall-security.rules|0644',
            values['FILE_TARGET_NFTABLES_D_95_FIREWALL_SECURITY_NFT'] +
            '|/etc/nftables.d/95-firewall-security.nft|0644',
        ])

    def test_firewall_state_preserves_existing_bytes_and_rejects_symlink(self) -> None:
        program = self.firewall_seed_program()
        first = self.path / 'etc/nftables/firewall-security.rules'
        second = self.path / 'etc/nftables.d/95-firewall-security.nft'
        for path in (first, second):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('existing administrator state\n')
        result = self.shell(program)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.path / 'published.tsv').exists())
        self.assertEqual(first.read_text(), 'existing administrator state\n')
        second.unlink()
        second.symlink_to(first)
        result = self.shell(program)
        self.assertEqual(result.returncode, 43, result.stderr)
        self.assertTrue(second.is_symlink())
        self.assertEqual(first.read_text(), 'existing administrator state\n')
        self.assertFalse((self.path / 'published.tsv').exists())

    def test_missing_firewall_selector_stops_before_publication(self) -> None:
        result = self.shell('FIXTURE_MISSING_SELECTOR=true\n' + self.firewall_seed_program())
        self.assertEqual(result.returncode, 44, result.stderr)
        self.assertFalse((self.path / 'published.tsv').exists())

    def test_required_account_fetch_retains_original_status(self) -> None:
        function = function_source('scripts/common/modules/profiles.sh',
                                   'installer_fetch_account_env')
        result = self.shell('''
installer_repo_file_value() { printf '%s\n' account.env; }
installer_fetch_seed_path() { return 43; }
installer_fatal_status() { fixture_status=$1; shift; printf '%s\n' "$*" >&2; exit "$fixture_status"; }
''' + function + '\ninstaller_fetch_account_env fixture-source staged-account.env\n')
        self.assertEqual(result.returncode, 43, result.stderr)
        self.assertIn('destination=staged-account.env', result.stderr)

    def test_payload_heredoc_is_not_embedded_in_single_line_preseed_command(self) -> None:
        source = (SEED / 'scripts/common/source.sh').read_text(encoding='utf-8')
        core, payload = source.split('# END BOOTSTRAP CORE', 1)
        self.assertNotIn('source_validate_repo_env_selectors() {', core)
        self.assertNotIn('<<EOF', core)
        self.assertIn('source_validate_repo_env_selectors() {', payload)

    def test_catalog_names_physical_files_and_module_templates(self) -> None:
        values = repository_selectors()
        source_files = [value for key, value in values.items()
                        if key.startswith('FILE_') and not key.startswith('FILE_REPO_')]
        self.assertEqual(len(source_files), len(set(source_files)))
        for relative in source_files:
            self.assertTrue((SEED / relative).is_file(), relative)
        modules = list(module_source_paths(
            (SEED / 'scripts/desktop/components.sh').read_text(encoding='utf-8')))
        self.assertIn(values['FILE_DESKTOP_COMP_CORE_RENDERERS_TMPL'], modules)
        self.assertIn(values['FILE_DESKTOP_COMP_LOGGING_TMPL'], modules)


if __name__ == '__main__':
    unittest.main()
