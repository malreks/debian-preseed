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


class DevopsAccountPublicationContracts(unittest.TestCase):
    """Failure injection into source data; never execute the embedded programs."""

    def setUp(self):
        directory = ROOT / 'd-i/debian/scripts/late/devops'
        self.inputs = [(directory / name).read_text(encoding='utf-8') for name in (
            'account-execution.sh', 'tool-configs.sh', 'main-orchestration.sh', 'publication-layout.sh')]

    def issues(self, index=None, before=None, after=None):
        inputs = self.inputs.copy()
        if index is not None:
            self.assertIn(before, inputs[index])
            inputs[index] = inputs[index].replace(before, after)
        return CHECKER._devops_account_publication_issues(*inputs)

    def test_both_skeleton_families_and_all_user_copies_are_wired(self):
        self.assertEqual(self.issues(), [])

    def test_reported_unprivileged_skeleton_copy_is_rejected(self):
        issues = self.issues(1, 'devops_publish_account_config "$rendered_tmp"',
                             'devops_run_as_account "${DEVOPS_SKEL_DIR}/.config/bazel/bazelrc"')
        self.assertTrue(any('unprivileged command' in issue for issue in issues), issues)

    def test_primary_account_must_not_copy_the_installed_skeleton(self):
        issues = self.issues(1, 'devops_publish_account_config "$rendered_tmp"',
                             'devops_publish_account_config "${DEVOPS_SKEL_DIR}/.config/bazel/bazelrc"')
        self.assertTrue(any('must not read the separately installed skeleton' in issue for issue in issues), issues)

    def test_missing_root_descriptor_handoff_is_rejected(self):
        issues = self.issues(0, 'os.dup2(fd, 0, inheritable=True)', 'pass')
        self.assertTrue(any('descriptor handoff' in issue for issue in issues), issues)

    def test_missing_account_copy_is_rejected(self):
        for path in ('.config/yt-dlp/config', '.bazelrc', '.config/bazel/bazelrc',
                     '.config/packer/template.pkr.hcl'):
            with self.subTest(path=path):
                issues = self.issues(1, path + ' 0', path + '-missing 0')
                self.assertTrue(any('directly from' in issue for issue in issues), issues)

    def test_source_identity_and_destination_replacement_guards_are_required(self):
        for guard in ('source.resolve(strict=True) != source', 'info.st_nlink != 1',
                      'os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW', 'follow_symlinks=False',
                      'os.unlink(candidate, dir_fd=parent)', 'os.fsync(parent)'):
            with self.subTest(guard=guard):
                self.assertTrue(self.issues(0, guard, 'removed_guard'))

    def test_private_reader_and_account_writer_are_parsed_as_separate_python(self):
        issues = self.issues(0, 'source = os.fstat(0)', 'source = os.fstat(')
        self.assertTrue(any('invalid account handoff Python' in issue for issue in issues), issues)


class SkeletonDestinationContracts(unittest.TestCase):
    """Mutate source data to detect a lost role or late destination."""

    def setUp(self):
        self.inputs = [(ROOT / 'd-i/debian' / name).read_text() for name in (
            'scripts/server/foundation.sh', 'scripts/desktop/waypaper.sh',
            'scripts/common/modules/target-publication.sh', 'scripts/common/primary-defaults.py')]

    def issues(self, index=None, before=None, after='removed_contract'):
        inputs = self.inputs.copy()
        if index is not None:
            self.assertIn(before, inputs[index])
            inputs[index] = inputs[index].replace(before, after)
        return CHECKER._skeleton_destination_issues(*inputs)

    def test_selected_role_defaults_have_both_destinations(self):
        self.assertEqual(self.issues(), [])

    def test_server_primary_optional_fragments_cannot_be_omitted(self):
        self.assertTrue(self.issues(0, 'installer_publish_primary_defaults server'))

    def test_waypaper_cannot_have_only_the_primary_destination(self):
        self.assertTrue(self.issues(1, '${DIR_ETC_SKEL_DESKTOP}/.local/share/applications/waypaper.desktop'))

    def test_waypaper_cannot_have_only_the_future_account_destination(self):
        self.assertTrue(self.issues(1, '"$waypaper_launcher_target" "$waypaper_launcher_mode"'))

    def test_waypaper_primary_launcher_must_belong_to_the_user_applications_directory(self):
        self.assertTrue(self.issues(1, '${ACCOUNT_HOME}/.local/share/applications'))
        self.assertTrue(self.issues(1, '"$waypaper_account_uid:$waypaper_account_gid"'))

    def test_both_families_and_hidden_defaults_remain_in_the_shared_copy(self):
        for family in ('DESKTOP', 'SERVER'):
            with self.subTest(family=family):
                self.assertTrue(self.issues(2, '${DIR_ETC_SKEL_' + family + '}/'))
        self.assertTrue(self.issues(3, 'with os.scandir(directory) as iterator:'))
        self.assertTrue(self.issues(3, 'publish(input_dir, output_dir, account, budget, depth + 1)'))

    def test_primary_home_group_and_privacy_cannot_be_dropped(self):
        self.assertTrue(self.issues(3, 'os.fchown(home, account.pw_uid, account.pw_gid)'))
        self.assertTrue(self.issues(3, 'os.fchmod(home, 0o700)'))


class FutureAccountContracts(unittest.TestCase):
    """Mutate source only; the privileged account program is never imported."""

    def setUp(self):
        self.inputs = [(ROOT / 'd-i/debian' / name).read_text() for name in (
            'hooks/target/usr/local/sbin/common/account-create',
            'scripts/common/modules/target-publication.sh',
            'scripts/desktop/components/rendering-access.sh',
            'scripts/late/dispatch.sh')]

    def issues(self, index=None, before=None, after='removed_contract'):
        inputs = self.inputs.copy()
        if index is not None:
            self.assertIn(before, inputs[index])
            inputs[index] = inputs[index].replace(before, after)
        return CHECKER._account_creation_issues(*inputs)

    def test_account_types_and_primary_publication_are_independent(self):
        self.assertEqual(self.issues(), [])

    def test_reported_build_failure_cannot_return(self):
        broken = self.issues(1, 'installer_stage_profile_file FILE_TARGET_SKEL_BASE_PROFILE',
                             'installer_stage_profile_file "FILE_TARGET_SKEL_BASE_${base_shell_asset}"')
        self.assertTrue(any('explicit registered source selector' in issue for issue in broken))
        self.assertTrue(any('incomplete prefix' in issue for issue in broken))

    def test_root_gate_and_default_base_type_cannot_be_dropped(self):
        self.assertTrue(self.issues(0, 'os.getuid() == os.geteuid() == 0', 'True'))
        self.assertTrue(self.issues(0, "default='base'", "default='desktop'"))

    def test_no_group_inheritance_or_service_account_templates(self):
        self.assertTrue(self.issues(0, "'--user-group', '--groups', ''", "'--user-group'"))
        self.assertTrue(self.issues(0, 'a service or non-login account cannot receive human defaults'))
        self.assertTrue(self.issues(0, "'--password', '!'", "'--password', ''"))

    def test_lock_identity_and_recovery_evidence_cannot_be_dropped(self):
        for token in ('fcntl.LOCK_EX | fcntl.LOCK_NB', 'info.st_nlink == 1',
                      'template file identity changed', 'template directory changed during capture',
                      "record(work, username, role, 'outcome-unknown')"):
            with self.subTest(token=token):
                self.assertTrue(self.issues(0, token))

    def test_primary_installer_cannot_run_the_future_account_initializer(self):
        self.assertTrue(self.issues(1, 'installer_publish_primary_defaults() {',
                                    'installer_publish_primary_defaults() {\n  "$FILE_ACCOUNT_CREATE" --prepare-home'))

    def test_capture_must_precede_account_relative_template_values(self):
        self.assertTrue(self.issues(2, 'installer_capture_primary_default "$tmp_rendered"'))
        self.assertTrue(self.issues(2, "ACCOUNT_USERNAME) future_value='$USER'"))

    def test_unprivileged_initializer_cannot_read_a_private_skeleton(self):
        self.assertTrue(self.issues(0, 'def personalize(account, role: str) -> None:',
                                    'def personalize(account, role: str) -> None:\n    source = SOURCES[role]'))


if __name__ == '__main__':
    unittest.main()
