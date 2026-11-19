"""Broker retirement and native workspace configuration regressions.

The fixtures relocate only the installation root. They do not start services,
contact Wayland, modify the host, compile binaries or claim live GUI acceptance.
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

from payload_fixture import copyfile as payload_copyfile, installed_argv as payload_installed_argv, source_exists as payload_source_exists, source_is_file as payload_source_is_file, source_path as payload_source_path
from payload_fixture import read_bytes as payload_read_bytes, read_text as payload_read_text
from theme_fixture import render_theme_defaults, render_theme_bytes, theme_values, render_theme_tree

import ast
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
FORKY = ROOT / 'd-i/forky'
TARGET = FORKY / 'hooks/target'
FIXTURE = FORKY / 'tests/fixtures/workspaces/render.sh'


def embedded_code(filename: str, function: str) -> str:
    source = render_theme_defaults(payload_read_text(FORKY / 'scripts/desktop' / filename))
    section = source.split(function + '() {', 1)[1].split('\n}\n', 1)[0]
    code = section.split("-c '\n", 1)[1].split("\n' ", 1)[0]
    ast.parse(code)
    return code


def relocate(code: str, root: Path) -> str:
    assert code.count('root = Path("/")') == 1
    return code.replace('root = Path("/")', 'root = Path(' + repr(str(root)) + ')')


def run_code(code: str, *arguments: str) -> subprocess.CompletedProcess:
    return subprocess.run(payload_installed_argv([sys.executable, '-I', '-B', '-c', code, *arguments]),
                          capture_output=True, text=True, timeout=10)


def render(root: Path, count: int, style: str) -> subprocess.CompletedProcess:
    result = subprocess.run(payload_installed_argv(['/bin/sh', str(FIXTURE), str(ROOT), str(root), str(count), style]),
                            capture_output=True, text=True, timeout=20)
    if result.returncode == 0:
        render_theme_tree(root)
    return result


def complete_fixture(root: Path, count: int = 4, style: str = 'thumbnail') -> None:
    result = render(root, count, style)
    if result.returncode:
        raise AssertionError(result.stderr)
    config = root / 'etc/skel-desktop/.config'
    units = config / 'systemd/user'
    units.mkdir(parents=True, exist_ok=True)
    for name in ('waybar.service',):
        payload_copyfile(TARGET / 'etc/skel-desktop/.config/systemd/user' / name, units / name)
    shutil.copytree(config, root / 'home/test/.config')




class NativeWorkspaceRenderingTests(unittest.TestCase):
    def test_all_twelve_counts_use_native_thumbnails(self):
        for count in range(1, 13):
            with self.subTest(workspaces=count), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                result = render(root, count, 'thumbnail')
                self.assertEqual(result.returncode, 0, result.stderr)
                config = root / 'etc/skel-desktop/.config'
                rc = ET.parse(payload_source_path(config / 'labwc/rc.xml')).getroot()
                self.assertEqual(int(rc.findtext('desktops/number')), count)
                self.assertEqual([n.text for n in rc.findall('desktops/names/name')],
                                 [str(i) for i in range(1, count + 1)])
                for key, action in (('A-Tab', 'NextWindow'), ('A-S-Tab', 'PreviousWindow')):
                    binding = rc.findall(f'keyboard/keybind[@key="{key}"]')
                    self.assertEqual(len(binding), 1)
                    actions = binding[0].findall('action')
                    self.assertEqual(len(actions), 1)
                    self.assertEqual(actions[0].attrib, dict(name=action, workspace='current',
                                                            output='all', identifier='all'))
                self.assertEqual(rc.find("keyboard/keybind[@key='F13']/action").attrib,
                                 {'name': 'NextWindow', 'workspace': 'current',
                                  'output': 'all', 'identifier': 'all'})
                switchers = rc.findall('windowSwitcher')
                self.assertEqual(len(switchers), 1)
                self.assertEqual(switchers[0].attrib,
                                 dict(preview='yes', outlines='yes', unshade='yes', order='focus'))
                self.assertEqual(switchers[0].find('osd').attrib,
                                 dict(show='yes', style='thumbnail', output='focused',
                                      thumbnailLabelFormat='%n \u2014 %T  %S  %o'))
                # Preserve the existing direct keys for workspaces 1--9.
                # Higher workspaces remain reachable through ext/workspaces.
                for index in range(1, min(count, 9) + 1):
                    for key, name in ((f'W-{index}', 'GoToDesktop'),
                                      (f'W-S-{index}', 'SendToDesktop')):
                        action = rc.find(f'keyboard/keybind[@key="{key}"]/action')
                        self.assertIsNotNone(action)
                        self.assertEqual(action.attrib, dict(name=name, to=str(index)))
                bars = json.loads(payload_read_text(config / 'waybar/config'))
                self.assertEqual(len(bars), 2)
                for bar in bars:
                    expected = ['custom/launcher', 'ext/workspaces', 'custom/tomat', 'custom/wayscriber', 'custom/window-switcher', 'group/apps']
                    if count == 1:
                        expected += ['wlr/taskbar']
                    self.assertEqual(bar['modules-left'], expected)
                    self.assertEqual(bar['ext/workspaces']['on-click'], 'activate')
                    self.assertTrue(bar['ext/workspaces']['all-outputs'])
                    self.assertFalse(bar['ext/workspaces']['active-only'])
                    taskbar = bar['wlr/taskbar']
                    self.assertEqual(taskbar['format'], '{icon}')
                    self.assertEqual(taskbar['icon-theme'], 'Papirus-Dark')
                    self.assertFalse(taskbar['all-outputs'])
                    self.assertFalse(taskbar['sort-by-app-id'])
                    self.assertEqual(taskbar['on-click'], 'minimize-raise')
                    self.assertEqual(taskbar['on-click-right'], 'minimize-raise')
                    self.assertEqual(taskbar['on-click-middle'], 'close')
                    self.assertNotIn('group/workspace-taskbar', bar)
                for name in ('waybar/config', 'waybar/style.css', 'labwc/rc.xml'):
                    self.assertNotIn('__INSTALLER_', render_theme_defaults(payload_read_text(config / name)))

    def test_valid_alternative_switcher_profile(self):
        choices = dict(LABWC_WINDOW_SWITCHER_ORDER='age', LABWC_WINDOW_SWITCHER_PREVIEW='no',
                       LABWC_WINDOW_SWITCHER_OUTLINES='no', LABWC_WINDOW_SWITCHER_UNSHADE='no',
                       LABWC_WINDOW_SWITCHER_OSD_OUTPUT='cursor', LABWC_WINDOW_SWITCHER_CYCLE_OUTPUT='focused')
        with tempfile.TemporaryDirectory() as temporary:
            result = subprocess.run(payload_installed_argv(['/bin/sh', str(FIXTURE), str(ROOT), temporary, '4', 'thumbnail']),
                                    env=dict(os.environ, **choices), capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
            rc = ET.parse(payload_source_path(Path(temporary) / 'etc/skel-desktop/.config/labwc/rc.xml')).getroot()
            switcher = rc.find('windowSwitcher')
            self.assertEqual(switcher.attrib, dict(order='age', preview='no', outlines='no', unshade='no'))
            self.assertEqual(switcher.find('osd').get('output'), 'cursor')
            for key in ('A-Tab', 'A-S-Tab'):
                action = rc.find(f'keyboard/keybind[@key="{key}"]/action')
                self.assertEqual(action.get('workspace'), 'current')
                self.assertEqual(action.get('output'), 'focused')

    def test_native_theme_geometry_preserved(self):
        text = render_theme_defaults(payload_read_text(TARGET / 'etc/skel-desktop/.config/labwc/themerc-override'))
        for line in ('osd.window-switcher.style-thumbnail.width.max: 82%',
                     'osd.window-switcher.style-thumbnail.item.width: 300',
                     'osd.window-switcher.style-thumbnail.item.height: 230'):
            self.assertIn(line, text)

    def test_switcher_enums_reject_invalid_values(self):
        source = render_theme_defaults(payload_read_text(FORKY / 'scripts/desktop/detect.sh'))
        start = source.index('  case "${LABWC_WINDOW_SWITCHER_STYLE:-thumbnail}"')
        end = source.index('  qbittorrent_peer_port_placeholder_map >/dev/null', start)
        checks = source[start:end]
        for key, value in (('STYLE', 'broken'), ('STYLE', 'classic'), ('ORDER', 'focus" />'), ('PREVIEW', 'true'),
                           ('OUTLINES', 'yes; id'), ('UNSHADE', 'YES'), ('OSD_OUTPUT', 'HDMI-A-1'),
                           ('CYCLE_OUTPUT', 'other')):
            with self.subTest(key=key):
                env = dict(os.environ, **{'LABWC_WINDOW_SWITCHER_' + key: value})
                code = '. "$1"; installer_fatal() { exit 17; }; ' + checks
                result = subprocess.run(payload_installed_argv(['/bin/sh', '-c', code, 'test',
                                         str(FORKY / 'scripts/desktop/detect.sh')]),
                                        env=env, capture_output=True, timeout=5)
                self.assertEqual(result.returncode, 17)

    def test_workspace_module_generator_validates_input(self):
        script = ('. "$1"; . "$2"; installer_fatal() { exit 17; }; '
                  'desktop_waybar_modules_left_json')
        for count in ('0', '13', '1; id', '-1', 'one'):
            with self.subTest(count=count):
                result = subprocess.run(payload_installed_argv(['/bin/sh', '-c', script, 'test',
                                         str(FORKY / 'scripts/desktop/detect.sh'),
                                         str(FORKY / 'scripts/desktop/components.sh')]),
                                        env={'PATH': '/usr/bin:/bin',
                                             'LABWC_WORKSPACE_COUNT_INTERNAL': count,
                                             'LABWC_WORKSPACE_COUNT_EXTERNAL': count},
                                        capture_output=True, timeout=5)
                self.assertEqual(result.returncode, 17)




class SourceWiringTests(unittest.TestCase):
    def test_retired_runtime_files_absent(self):
        for relative in ('usr/local/lib/labwc-workspace-broker',
                         'usr/local/libexec/labwc-workspace-broker',
                         'usr/local/libexec/labwc-workspace-wayland-adapter',
                         'usr/local/bin/labwc-workspace-broker-client',
                         'etc/skel-desktop/.config/systemd/user/labwc-workspace-broker.service'):
            self.assertFalse(payload_source_exists(TARGET / relative))
        for path in TARGET.rglob('*'):
            if payload_source_is_file(path) and path.suffix not in ('.png', '.jpg', '.zip', '.gz', '.xz'):
                self.assertNotIn(b'labwc-workspace-broker', render_theme_bytes(payload_read_bytes(path)), str(path))

    def test_cleanup_and_verification_are_wired(self):
        components = render_theme_defaults(payload_read_text(FORKY / 'scripts/desktop/components.sh'))
        self.assertNotIn('desktop_retire_workspace_broker', components)
        for path in (FORKY / 'scripts/desktop/detect.sh', TARGET / 'etc/labwc/desktop.conf.tmpl'):
            self.assertNotIn('LABWC_WORKSPACE_BROKER_', render_theme_defaults(payload_read_text(path)))
        packages = render_theme_defaults(payload_read_text(FORKY / 'classes/class-select/role/desktop.cfg')).split()
        self.assertNotIn('python3-pywayland', packages)
        # These dependencies predated the broker and are not removed wholesale.
        self.assertIn('libmoo-perl', packages)
        self.assertIn('libmoox-options-perl', packages)


if __name__ == '__main__':
    unittest.main()
