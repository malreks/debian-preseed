"""Static target-mode contract regressions; guarded isolated execution only.

These cases project source and invoke ShellCheck. They never execute an
installer, target helper, download, package transaction or service operation.
"""
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from isolation import require_test_isolation
require_test_isolation()

import importlib.util
import json
import re
import shutil
import subprocess
import unittest


SPEC = importlib.util.spec_from_file_location('late_static_checker', ROOT / 'tools/post_change_check.py')
assert SPEC is not None and SPEC.loader is not None
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


class TargetInstallContracts(unittest.TestCase):
    def source(self, component):
        return (ROOT / 'd-i/debian/scripts/late' / (component + '.sh')).read_text()

    def project(self, component, source=None):
        rendered = CHECKER._render_installer_path_placeholders(
            self.source(component) if source is None else source)
        return CHECKER._target_install_scope(rendered)

    def unbound(self, source):
        shellcheck = shutil.which('shellcheck', path='/usr/bin:/bin')
        self.assertIsNotNone(shellcheck, 'the isolated fixture must provide ShellCheck')
        result = subprocess.run(
            [shellcheck, '--norc', '--shell=sh', '--format=json', '--severity=warning',
             '--include=SC2154', '--enable=check-unassigned-uppercase', '-'],
            input=source, text=True, capture_output=True, timeout=15,
            cwd=ROOT, env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'},
        )
        self.assertIn(result.returncode, (0, 1), result.stderr)
        return json.loads(result.stdout)

    def test_both_target_modes_have_complete_explicit_inputs(self):
        for component in ('whisper', 'llama'):
            with self.subTest(component=component):
                body, _origins, fields, missing, functions = self.project(component)
                self.assertTrue(fields)
                self.assertGreater(functions, 1)
                self.assertEqual(missing, set())
                self.assertEqual(self.unbound(body), [])

    def test_reported_whisper_unbound_path_is_detected(self):
        original = '__INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/whisper-cli-default-model'
        source = self.source('whisper')
        self.assertIn(original, source)
        broken = source.replace(original, '"${DIR_USR_LOCAL_LIBEXEC}/whisper-cli-default-model"', 1)
        body, _origins, _fields, _missing, _functions = self.project('whisper', broken)
        messages = self.unbound(body)
        self.assertTrue(any(message['code'] == 2154
                            and 'DIR_USR_LOCAL_LIBEXEC' in message['message']
                            for message in messages), messages)

    def test_a_policy_guard_does_not_substitute_for_serialized_input(self):
        for component in ('whisper', 'llama'):
            with self.subTest(component=component):
                name = component.upper() + '_SERVER_PORT'
                source = self.source(component)
                broken, count = re.subn(r'^  write_shell_config_var ' + name + r' "\$' + name + r'"\n',
                                        '', source, count=1, flags=re.M)
                self.assertEqual(count, 1)
                _body, _origins, _fields, missing, _functions = self.project(component, broken)
                self.assertIn(name, missing)

    def test_reachable_child_helpers_are_checked_without_installer_definitions(self):
        body, _origins, _fields, _missing, _functions = self.project('whisper')
        self.assertIn('whisper_target_cli_entrypoint()', body)
        self.assertNotIn('whisper_stage_mode_perl_modules()', body)
        self.assertNotRegex(body, r'\$\{?DIR_USR_LOCAL_LIBEXEC\b')
        self.assertIn('--target-install "$target_profile" "$INSTALLER_HOST_VARIANT"',
                      self.source('whisper'))

    def test_waypaper_nested_child_has_its_own_environment_scope(self):
        source = (ROOT / 'd-i/debian/scripts/desktop/waypaper.sh').read_text()
        rendered = CHECKER._render_installer_path_placeholders(source)
        children = CHECKER._late_target_shells(rendered)
        self.assertEqual(len(children), 2)
        nested = [body for _line, body, _invocation in children if 'for link_path; do' in body]
        self.assertEqual(len(nested), 2)  # Outer body contains the quoted nested body too.
        broken = source.replace('resolved_path=$(', 'missing="$DIR_USR_LOCAL_LIBEXEC"\nresolved_path=$(', 1)
        self.assertNotEqual(broken, source)
        children = CHECKER._late_target_shells(CHECKER._render_installer_path_placeholders(broken))
        self.assertTrue(any(message['code'] == 2154
                            and 'DIR_USR_LOCAL_LIBEXEC' in message['message']
                            for _line, body, _invocation in children
                            for message in self.unbound(body)))

    def test_only_explicitly_sourced_policy_fields_belong_to_a_child(self):
        statement = '. __INSTALLER_PATH_DIR_ETC_LABWC__/desktop.conf\n'
        rendered = CHECKER._render_installer_path_placeholders(statement)
        self.assertIn('LABWC_DESKTOP_QT_ICON_THEME', CHECKER._target_shell_policy_fields(rendered))
        self.assertEqual(CHECKER._target_shell_policy_fields('printf "%s\\n" "$LABWC_DESKTOP_QT_ICON_THEME"'), set())
        self.assertNotIn('DIR_USR_LOCAL_LIBEXEC', CHECKER._target_shell_policy_fields(rendered))


if __name__ == '__main__':
    unittest.main()
