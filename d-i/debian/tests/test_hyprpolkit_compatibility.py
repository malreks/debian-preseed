"""Hyprpolkit compatibility, native-session lifetime and package selection.

Source fixtures only; never executed under the repository static-only boundary.
All helper calls in these cases are mocked; no APT or systemd fixture is retained.
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

import contextlib
import io
import os
from pathlib import Path
import re
import stat
import subprocess
from types import ModuleType, SimpleNamespace
import unittest
from unittest import mock

SEED = Path(__file__).resolve().parents[1]
TARGET = SEED / 'hooks/target'
HELPER = TARGET / 'usr/local/libexec/desktop/labwc-hyprpolkit-agent'
UNIT = TARGET / 'etc/systemd/desktop/user/hyprpolkitagent.service.d'


def load_helper():
    # Fixed package/FHS path substitutions for an inert mock fixture, never
    # target publication. The application renderer remains the sole publisher.
    source = HELPER.read_text(encoding='utf-8')
    for name, value in {'DIR_USR': '/usr', 'DIR_USR_LIBEXEC': '/usr/libexec',
                        'DIR_USR_LOCAL_LIBEXEC': '/usr/local/libexec'}.items():
        source = source.replace('__INSTALLER_PATH_' + name + '__', value)
    module = ModuleType('hyprpolkit_fixture')
    exec(compile(source, str(HELPER), 'exec'), module.__dict__)
    return module


def metadata(version='0.1.3-2', depends=None, state='installed'):
    depends = depends if depends is not None else 'libpolkit-qt6-1-1, libqt6quickcontrols2-6, polkitd'
    return f'{state}\n{version}\n{depends}\n'


class AgentGuardTests(unittest.TestCase):
    def setUp(self):
        self.m = load_helper()

    def test_signed_qt_package_revisions_are_not_fixed_to_a_version(self):
        for version in ('0.1.3-2~bpo13+1', '0.1.3-3', '0.2.0-1', '1:1.0-2'):
            with self.subTest(version=version):
                self.assertEqual(self.m.check_metadata(metadata(version)), version)

    def test_malformed_version_data_is_rejected(self):
        for version in ('', 'no-version', '0.1.3-2\nextra', '1;true', '1$(id)', '1`id`'):
            with self.subTest(version=version), self.assertRaises(ValueError):
                self.m.check_metadata(metadata(version))

    def test_half_configured_and_missing_metadata_are_rejected(self):
        for record in ('', 'installed\n0.1.3-2\n', metadata(state='unpacked'),
                       metadata(state='config-files'), metadata(state='half-configured')):
            with self.subTest(record=record), self.assertRaises(ValueError):
                self.m.check_metadata(record)

    def test_same_version_with_toolkit_or_wrong_dependencies_is_rejected(self):
        for depends in ('libhyprtoolkit6, libpolkit-qt6-1-1, libqt6quickcontrols2-6, polkitd',
                        'libaquamarine14, libpolkit-qt6-1-1, libqt6quickcontrols2-6, polkitd',
                        'libpolkit-agent-1-0, libc6', 'libpolkit-qt6-1-1'):
            with self.subTest(depends=depends), self.assertRaises(ValueError):
                self.m.check_metadata(metadata(depends=depends))

    def valid_info(self, path):
        kind = stat.S_IFREG if path == self.m.BINARY else stat.S_IFDIR
        return SimpleNamespace(st_mode=kind | 0o755, st_uid=0)

    def test_binary_requires_exact_debian_ownership(self):
        for owner in ('hyprpolkitagent: /usr/libexec/hyprpolkitagent\n',
                      'hyprpolkitagent:amd64: /usr/libexec/hyprpolkitagent\n'):
            with mock.patch.object(Path, 'lstat', lambda path: self.valid_info(path)), \
                 mock.patch.object(self.m, 'package_query', return_value=owner):
                self.m.check_binary()
        for owner in ('other: /usr/libexec/hyprpolkitagent',
                      'local diversion from: /usr/libexec/hyprpolkitagent',
                      'hyprpolkitagent: /usr/libexec/hyprpolkitagent\nother: /usr/libexec/hyprpolkitagent'):
            with mock.patch.object(Path, 'lstat', lambda path: self.valid_info(path)), \
                 mock.patch.object(self.m, 'package_query', return_value=owner), self.assertRaises(ValueError):
                self.m.check_binary()

    def test_binary_and_parents_cannot_be_symlinked_writable_or_unowned(self):
        for bad_path in (*self.m.BINARY.parents, self.m.BINARY):
            for bad in (SimpleNamespace(st_mode=stat.S_IFLNK | 0o777, st_uid=0),
                        SimpleNamespace(st_mode=stat.S_IFREG | 0o777, st_uid=0),
                        SimpleNamespace(st_mode=stat.S_IFDIR | 0o775, st_uid=0),
                        SimpleNamespace(st_mode=stat.S_IFREG | 0o4755, st_uid=0),
                        SimpleNamespace(st_mode=stat.S_IFREG | 0o755, st_uid=1000)):
                def info(path):
                    return bad if path == bad_path else self.valid_info(path)
                with self.subTest(path=bad_path, info=bad), mock.patch.object(Path, 'lstat', info), \
                     mock.patch.object(self.m, 'package_query') as query, self.assertRaises(ValueError):
                    self.m.check_binary()
                query.assert_not_called()

    def test_package_query_is_read_only_absolute_and_bounded(self):
        with mock.patch.object(self.m.subprocess, 'run', return_value=SimpleNamespace(stdout='record')) as run:
            self.assertEqual(self.m.package_query('-W', 'hyprpolkitagent'), 'record')
        self.assertEqual(run.call_args.args[0], ['/usr/bin/dpkg-query', '-W', 'hyprpolkitagent'])
        self.assertEqual(run.call_args.kwargs['timeout'], 5)
        self.assertTrue(run.call_args.kwargs['check'])
        self.assertEqual(run.call_args.kwargs['env']['LC_ALL'], 'C')
        self.assertNotIn('shell', run.call_args.kwargs)

    def test_read_only_check_does_not_require_or_start_a_session(self):
        with mock.patch.object(self.m, 'check', return_value='0.1.3-2'), \
             mock.patch.object(self.m.os, 'execve') as execute, \
             mock.patch.dict(os.environ, {}, clear=True), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.m.main(['--check']), 0)
        execute.assert_not_called()

    def test_exec_replaces_guard_with_same_agent_and_native_software_environment(self):
        env = {'LABWC_SESSION_OWNER': 'desktop', 'XDG_SESSION_TYPE': 'wayland',
               'WAYLAND_DISPLAY': 'wayland-1', 'XDG_RUNTIME_DIR': '/run/user/1000',
               'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/run/user/1000/bus',
               'DISPLAY': ':0', 'XAUTHORITY': '/tmp/should-not-be-used',
               'QT_QPA_PLATFORM': 'xcb', 'QT_QUICK_BACKEND': 'rhi',
               'QSG_RHI_BACKEND': 'vulkan', 'QMLSCENE_DEVICE': 'openvg'}
        with mock.patch.dict(os.environ, env, clear=True), \
             mock.patch.object(self.m, 'check', return_value='0.1.3-2'), \
             mock.patch.object(self.m.os, 'execve', side_effect=SystemExit(0)) as execute, \
             self.assertRaises(SystemExit):
            self.m.main(['--exec'])
        binary, argv, launched = execute.call_args.args
        self.assertEqual(binary, '/usr/libexec/hyprpolkitagent')
        self.assertEqual(argv, [binary])
        self.assertEqual(launched['QT_QPA_PLATFORM'], 'wayland')
        self.assertEqual(launched['QT_QUICK_BACKEND'], 'software')
        self.assertEqual(launched['DBUS_SESSION_BUS_ADDRESS'], env['DBUS_SESSION_BUS_ADDRESS'])
        self.assertEqual(launched['XDG_RUNTIME_DIR'], env['XDG_RUNTIME_DIR'])
        for key in ('DISPLAY', 'XAUTHORITY', 'QSG_RHI_BACKEND', 'QMLSCENE_DEVICE'):
            self.assertNotIn(key, launched)
        self.assertEqual(env['QT_QUICK_BACKEND'], 'rhi')  # never mutate caller data

    def test_non_desktop_or_non_wayland_launch_is_rejected(self):
        for env in ({}, {'LABWC_SESSION_OWNER': 'greeter'},
                    {'LABWC_SESSION_OWNER': 'desktop', 'XDG_SESSION_TYPE': 'x11'},
                    {'LABWC_SESSION_OWNER': 'desktop', 'XDG_SESSION_TYPE': 'wayland'}):
            with mock.patch.dict(os.environ, env, clear=True), self.assertRaises(ValueError):
                self.m.launch_environment()

    def test_invalid_package_timeout_and_usage_do_not_start_or_loop(self):
        for failure in (ValueError('incompatible toolkit'), OSError('missing package'),
                        subprocess.TimeoutExpired('dpkg-query', 5)):
            with mock.patch.object(self.m, 'check', side_effect=failure), \
                 mock.patch.object(self.m.os, 'execve') as execute, contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(self.m.main(['--exec']), 78)
            execute.assert_not_called()
        with mock.patch.object(self.m, 'check') as check, contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(self.m.main(['--exec', '--other-agent']), 78)
            self.assertEqual(self.m.main([]), 78)
        check.assert_not_called()


class AgentWiringTests(unittest.TestCase):
    def test_all_desktops_keep_the_agent_and_explicit_signed_release(self):
        for suite in ('forky', 'trixie'):
            root = SEED.parent / suite
            for tier in ('base', 'medium', 'full'):
                text = (root / 'classes/class-select/role/desktop' / (tier + '.cfg')).read_text()
                self.assertIn('hyprpolkitagent', text.split())
                self.assertNotIn('lxqt-policykit', text.split())
                if suite == 'forky':
                    self.assertNotIn('trixie', text)
            if suite == 'trixie':
                fragment = (root / 'fragments/apt.cfg').read_text()
                self.assertIn('https://mirrors.glesys.net/debian trixie-backports main', fragment)
            pin = (root / 'hooks/target/etc/apt/desktop/preferences.d/10-hyprpolkitagent.pref').read_text()
            self.assertNotIn('Pin: version ', pin)
            expected = ('Pin: release o=Debian,n=forky' if suite == 'forky'
                        else 'Pin: release o=Debian,n=trixie-backports')
            self.assertIn(expected, pin)
            self.assertIn('Pin-Priority: 1001', pin)

    def test_native_session_and_bounded_failure_contract_remain(self):
        session = (UNIT / '10-labwc-session.conf').read_text()
        for line in ('Requisite=labwc-session.target', 'PartOf=labwc-session.target',
                     'ConditionEnvironment=LABWC_SESSION_OWNER=desktop',
                     'ConditionEnvironment=XDG_SESSION_TYPE=wayland',
                     'RestartPreventExitStatus=78', 'KillMode=control-group',
                     'StartLimitBurst=5', 'TimeoutStopSec=10s',
                     'Environment=QT_QPA_PLATFORM=wayland',
                     'Environment=QT_QUICK_BACKEND=software',
                     'UnsetEnvironment=DISPLAY XAUTHORITY QSG_RHI_BACKEND QMLSCENE_DEVICE'):
            self.assertIn(line, session)
        self.assertNotIn('NoNewPrivileges=yes', session)
        self.assertNotIn('PrivateUsers=yes', session)
        self.assertIn('LimitCORE=0', (UNIT / '70-no-core.conf').read_text())
        self.assertIn('Slice=session.slice', (UNIT / '60-resource-class.conf').read_text())
