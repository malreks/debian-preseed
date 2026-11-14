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
