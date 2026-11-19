"""Base-render selector regressions; run only in the reviewed private guest."""
from __future__ import annotations

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation
require_test_isolation()

import re
import shlex
import subprocess
import tempfile
import unittest


DEBIAN = Path(__file__).resolve().parents[1]
HOOK = DEBIAN / 'hooks/installer/base-stage.d/00rendertarget'
REPOSITORY = DEBIAN / 'scripts/common/modules/repository-apt.sh'


class BaseRenderSelectorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='base-render-selector-', dir='/workspace')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.environment = {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C',
                            'TMPDIR': str(self.root), 'TMP': str(self.root), 'TEMP': str(self.root)}
        self.registry = 'hooks/target/usr/local/share/desktop/labwc-appearance/fields.json.tmpl'

    def shell(self, family, body):
        # The real family guard is sourced only inside the reviewed guest.
        # Stub unrelated validation; these inputs are fixed captured-source
        # addresses. No target file, package, service or device is accessed.
        roots = {
            'AA': 'etc/apparmor.d', 'APPARMOR': 'etc/apparmor',
            'TMPFILES_D': 'etc/tmpfiles.d', 'SYSCTL_D': 'etc/sysctl.d',
            'BIN': 'usr/local/bin', 'SBIN': 'usr/local/sbin',
            'LIBEXEC': 'usr/local/libexec', 'LIB': 'usr/local/lib',
            'SHARE': 'usr/local/share',
        }
        code = '\n'.join([
            '. ' + shlex.quote(str(REPOSITORY)),
            'installer_validate_repo_file_value() { :; }',
            'installer_fatal() { printf "%s\\n" "$*" >&2; exit 73; }',
            'INSTALLER_HOST_VARIANT=' + shlex.quote(family),
            *['DIR_TARGET_' + key + '=' + shlex.quote('hooks/target/' + leaf)
              for key, leaf in roots.items()],
            'DIR_TARGET_SHARE_LABWC_APPEARANCE="$DIR_TARGET_SHARE/desktop/labwc-appearance"',
            body,
        ])
        return subprocess.run(['/bin/dash', '-eu', '-c', code], cwd=self.root,
                              env=self.environment, capture_output=True, text=True,
                              timeout=10, check=False)

    def test_both_roles_receive_the_captured_registry_classifier_argument(self):
        source = HOOK.read_text(encoding='utf-8')
        option = re.search(r'^\s*--appearance-registry (.*?) \\\n', source, re.M)
        self.assertIsNotNone(option, 'the base hook must pass one explicit registry classifier')
        for family in ('desktop', 'server'):
            with self.subTest(family=family):
                result = self.shell(family, 'set -- ' + option[1] + '\nprintf "%s\\n" "$1"')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, self.registry + '\n')
                self.assertEqual(result.stderr, '')

    def test_server_asset_publication_still_rejects_the_desktop_registry(self):
        result = self.shell('server', 'installer_repo_file_value ' + shlex.quote(self.registry))
        self.assertEqual(result.returncode, 73)
        self.assertIn('incompatible or missing role family', result.stderr)
        self.assertEqual(result.stdout, '')

    def test_desktop_asset_selection_still_accepts_its_registry(self):
        result = self.shell('desktop', 'installer_repo_file_value ' + shlex.quote(self.registry))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, self.registry + '\n')

    def test_base_hook_records_distinct_current_source_lines_for_each_stage(self):
        contexts = []
        for number, line in enumerate(HOOK.read_text(encoding='utf-8').splitlines(), 1):
            match = re.fullmatch(r'prepare_context ([0-9]+) ([a-z][a-z0-9_]+)', line)
            if match:
                self.assertEqual(int(match[1]), number)
                contexts.append(match[2])
        self.assertEqual(len(contexts), len(set(contexts)))
        self.assertGreaterEqual(len(contexts), 15)
        self.assertIn('render_target_source_snapshot', contexts)
        self.assertIn('prepare_system_template_map', contexts)
        self.assertIn('publish_target_render_ready', contexts)


if __name__ == '__main__':
    unittest.main()
