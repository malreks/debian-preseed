"""Unexecuted desktop guard fixtures; no compositor or host helper access.

All paths, metadata replies and executables belong to a private fixture tree.
The Unix socket is an inert filesystem object: nothing connects or listens.
"""
from __future__ import annotations

from pathlib import Path as _IsolationPath
import sys as _isolation_sys
_isolation_sys.path.insert(0, str(_IsolationPath(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation as _require_test_isolation
_isolation_sys.path.pop(0)
_require_test_isolation()

from pathlib import Path
from contextlib import ExitStack, contextmanager, redirect_stderr
import io
import ast
import json
import os
import re
import shlex
import socket
import stat
import struct
import subprocess
import sys
import tempfile
from types import ModuleType, SimpleNamespace
import unittest
from unittest import mock
from fixture_render import render_scalar_fixture, rendered_path_text
from payload_fixture import source_path


TARGET = Path(__file__).resolve().parents[1] / 'hooks/target'
SOURCE = source_path(TARGET / 'usr/local/bin/labwc-window-switcher')
LIBEXEC = TARGET / 'usr/local/libexec'


def target_source(relative):
    return source_path(TARGET / relative)


def target_text(relative):
    with tempfile.TemporaryDirectory(prefix='waybar-target-render-') as temporary:
        return render_scalar_fixture(target_source(relative), Path(temporary)).decode('utf-8')


class FixedShellArgumentFixtures(unittest.TestCase):
    def test_every_configured_trampoline_status_call_crosses_the_shell_and_allowlist(self):
        seed = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory(prefix='waybar-status-shell-') as temporary:
            root = Path(temporary)
            source = seed / 'hooks/target/usr/local/libexec/desktop/labwc-waybar-exec'
            trampoline = ModuleType('fixed_status_trampoline')
            exec(compile(render_scalar_fixture(source, root), str(source), 'exec'), vars(trampoline))
            sink = root / 'argument sink'
            sink.write_text('#!/usr/bin/python3 -IB\nimport json,os,sys\n'
                            'with open(os.environ["ARGV_RESULT"],"w") as f: json.dump(sys.argv[1:],f)\n')
            sink.chmod(0o700)
            count = 0
            for module in sorted((seed / 'hooks/target/etc/skel-desktop/.config/waybar/modules').glob('*.tmpl')):
                if 'labwc-waybar-exec ' not in module.read_text():
                    continue
                for entry in json.loads(render_scalar_fixture(module, root)).values():
                    command = entry.get('exec', '')
                    prefix = '/usr/local/libexec/labwc-waybar-exec '
                    if not command.startswith(prefix) or command == prefix + 'menu-state':
                        continue  # Launcher state is the wrapper's separate fixed interface.
                    result = root / 'arguments.json'
                    subprocess.run(['/bin/sh', '-eu', '-c', command.replace(prefix, shlex.quote(str(sink)) + ' ', 1)],
                                   cwd=root, env={'PATH': '/usr/bin:/bin', 'HOME': str(root / 'home ;literal'),
                                                  'ARGV_RESULT': str(result), 'TMPDIR': str(root),
                                                  'TMP': str(root), 'TEMP': str(root)}, check=True, timeout=5)
                    arguments = json.loads(result.read_text())
                    with self.subTest(module=module.name):
                        self.assertTrue(trampoline.command(arguments))
                        with self.assertRaises(ValueError):
                            trampoline.command(arguments + ['extra'])
                    count += 1
            self.assertGreaterEqual(count, 6)
            with self.assertRaises(ValueError):
                trampoline.command(['/usr/local/libexec/labwc-waybar-state', 'status', 'power'])
            self.assertTrue(
                trampoline.command(['/usr/local/libexec/labwc-waybar-state', 'status', 'wayscriber']))

    def test_rendered_cpu_memory_commands_cross_the_real_shell_without_expansion(self):
        seed = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory(prefix='waybar-shell-') as temporary:
            root = Path(temporary)
            runner_path = seed / 'hooks/target/usr/local/libexec/desktop/labwc-waybar-run'
            runner = ModuleType('fixed_shell_runner')
            exec(compile(render_scalar_fixture(runner_path, root), str(runner_path), 'exec'), vars(runner))
            sink = root / 'argument sink'
            sink.write_text('#!/usr/bin/python3 -IB\nimport json,os,sys\n'
                            'with open(os.environ["ARGV_RESULT"],"w") as f: json.dump(sys.argv[1:],f)\n')
            sink.chmod(0o700)
            for button in ('cpu', 'memory'):
                source = seed / ('hooks/target/etc/skel-desktop/.config/waybar/modules/' + button + '.tmpl')
                value = json.loads(render_scalar_fixture(source, root))[button]
                command = value['on-click-release']
                self.assertTrue(command.startswith('/usr/local/libexec/labwc-waybar-run '))
                command = command.replace('/usr/local/libexec/labwc-waybar-run', shlex.quote(str(sink)), 1)
                for home in ('home with spaces', "home [literal] ;$(false) ' !"):
                    result = root / 'arguments.json'
                    subprocess.run(['/bin/sh', '-eu', '-c', command], cwd=root,
                                   env={'PATH': '/usr/bin:/bin', 'HOME': str(root / home),
                                        'ARGV_RESULT': str(result), 'TMPDIR': str(root),
                                        'TMP': str(root), 'TEMP': str(root)}, check=True, timeout=5)
                    arguments = json.loads(result.read_text())
                    normalized, output_class = runner.normalize_command(arguments)
                    self.assertIsNone(output_class)
                    self.assertEqual(normalized, ('/usr/local/bin/labwc-terminal', '-e', 'btop', '--config',
                                                  '~/.config/btop/btop-' + button + '.conf'))
                    for bad in (arguments + ['extra'], arguments + [';', 'false'],
                                ['--', '/usr/local/bin/../bin/labwc-terminal', *normalized[1:]],
                                ['--', '/usr/local/bin/labwc-terminal-modified', *normalized[1:]],
                                ['--', *normalized[:-1], str(root / 'arbitrary.conf')]):
                        with self.assertRaises(ValueError):
                            runner.normalize_command(bad)


def load_helper(name):
    path = source_path(LIBEXEC / name)
    module = ModuleType('fixture_' + name.replace('-', '_').replace('.', '_'))
    module.__file__ = str(path)
    with tempfile.TemporaryDirectory(prefix='waybar-helper-render-') as temporary:
        rendered = render_scalar_fixture(path, Path(temporary))
    exec(compile(rendered, str(path), 'exec'), module.__dict__)
    return module


class ConfiguredFootCloseFixtures(unittest.TestCase):
    def test_actual_terminal_wrapper_selects_portable_config_without_a_shell_fragment(self):
        seed = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory(prefix='portable-btop-') as temporary:
            root = Path(temporary)
            bindir = root / 'bin'
            bindir.mkdir()
            foot = bindir / 'foot'
            foot.write_text('#!/bin/sh\nexit 99\n')  # Discovery only; delegate captures argv.
            foot.chmod(0o700)
            delegate = bindir / 'labwc-wayland-app'
            delegate.write_text('#!/usr/bin/python3 -IB\nimport json,os,sys\n'
                                'with open(os.environ["ARGV_RESULT"],"w") as f:json.dump(sys.argv[1:],f)\n')
            delegate.chmod(0o700)
            wrapper = root / 'terminal.sh'
            wrapper.write_bytes(render_scalar_fixture(
                seed / 'hooks/target/usr/local/bin/desktop/labwc-terminal', root,
                {'PATH_DIR_ETC': str(root / 'etc'), 'PATH_DIR_USR_LOCAL_BIN': str(bindir)}))
            output = root / 'argv.json'
            for button in ('cpu', 'memory'):
                title = 'Labwc-' + ('CPU' if button == 'cpu' else 'Memory') + '-01234567'
                operand = '~/.config/btop/btop-' + button + '.conf'
                for home in (str(root / 'home with spaces'), str(root / "home ;$(literal) ! ' []")):
                    environment = {'PATH': str(bindir) + ':/usr/bin:/bin', 'HOME': home,
                                   'LANG': 'C.UTF-8', 'LABWC_TERMINAL_TITLE': title,
                                   'ARGV_RESULT': str(output), 'TMPDIR': str(root),
                                   'TMP': str(root), 'TEMP': str(root)}
                    result = subprocess.run(['/bin/sh', str(wrapper), '-e', 'btop', '--config', operand],
                                            env=environment, stdin=subprocess.DEVNULL,
                                            capture_output=True, timeout=5)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(json.loads(output.read_text()), [
                        'auto', '--', 'foot', '--title', title, '-e', '/usr/bin/env',
                        'XDG_CONFIG_HOME=' + home + '/.config/btop/profiles/' + button, 'btop'])
                    output.unlink()
                    rejected = subprocess.run(['/bin/sh', str(wrapper), '-e', 'btop', '--config', operand, 'extra'],
                                              env=environment, stdin=subprocess.DEVNULL,
                                              capture_output=True, timeout=5)
                    self.assertNotEqual(rejected.returncode, 0)
                    self.assertFalse(output.exists())

    def test_real_transient_only_accepts_identity_bound_cpu_memory_close(self):
        seed = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory(prefix='configured-foot-') as temporary:
            root = Path(temporary)
            library = root / 'library'
            package = seed / 'hooks/target/usr/local/lib/desktop/python3/dist-packages/labwc_managed_app'
            for source in sorted([*package.rglob('*.py'), *package.rglob('*.py.tmpl')]):
                target = library / 'labwc_managed_app' / source.relative_to(package).as_posix().removesuffix('.tmpl')
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(render_scalar_fixture(source, root))
            cases = []
            identity = '01234567' + 'a' * 24
            for button in ('cpu', 'memory'):
                for home in ('/home/fixture', "/home/with spaces ;$(literal) ! ' [punctuation]"):
                    title = 'Labwc-' + ('CPU' if button == 'cpu' else 'Memory') + '-' + identity[:8]
                    environment = {'HOME': home, 'LABWC_WAYBAR_STATE_BUTTON': button,
                                   'LABWC_WAYBAR_ACTION_ID': identity, 'LABWC_TERMINAL_TITLE': title}
                    arguments = ['/usr/bin/foot', '--title', title, '-e', '/usr/bin/env',
                                 'XDG_CONFIG_HOME=' + home + '/.config/btop/profiles/' + button, 'btop']
                    cases.append((arguments, environment, True))
                    for argv, changes in (
                        (arguments + ['extra'], {}),
                        ([arguments[0] + '-modified', *arguments[1:]], {}),
                        ([*arguments[:5], 'XDG_CONFIG_HOME=' + home + '/.config/btop/profiles/../' + button, 'btop'], {}),
                        ([*arguments[:5], 'XDG_CONFIG_HOME=/arbitrary', 'btop'], {}),
                        (arguments, {'LABWC_WAYBAR_ACTION_ID': 'f' * 32}),
                        (arguments, {'LABWC_TERMINAL_TITLE': title + 'x'}),
                        (arguments, {'HOME': '/home/../fixture'}),
                        ([*arguments[:4], 'sh', '-c', 'exit 1'], {}),
                    ):
                        cases.append((argv, {**environment, **changes}, False))
            probe = root / 'probe.py'
            probe.write_text("import json,sys\nfrom unittest import mock\n"
                             "sys.path.insert(0,sys.argv[1])\n"
                             "from labwc_managed_app import generic\n"
                             "result=[]\n"
                             "with mock.patch.object(generic,'assert_launch_allowed'), "
                             "mock.patch.object(generic,'menu_action_wait_arguments',return_value=[]):\n"
                             " for arguments,environment,_ in json.load(sys.stdin):\n"
                             "  result.append(generic.transient_argv('wayland','auto',arguments,environment))\n"
                             "print(json.dumps(result))\n")
            result = subprocess.run([sys.executable, '-I', '-B', str(probe), str(library)],
                                    input=json.dumps(cases), text=True, capture_output=True,
                                    env={'PATH': '/usr/bin:/bin', 'HOME': str(root),
                                         'TMPDIR': str(root), 'TMP': str(root), 'TEMP': str(root)},
                                    check=True, timeout=15)
            replies = json.loads(result.stdout)
            self.assertEqual(len(replies), len(cases))
            for (arguments, environment, expected), command in zip(cases, replies):
                with self.subTest(arguments=arguments, title=environment['LABWC_TERMINAL_TITLE']):
                    self.assertEqual('--property=SuccessExitStatus=1' in command, expected)
                    self.assertNotIn('--property=SuccessExitStatus=230', command)
                    self.assertNotIn('--property=SuccessExitStatus=7', command)
                    if expected:
                        for operation, phase in (('ExecStartPre', 'start'), ('ExecStopPost', 'cleanup')):
                            self.assertIn('--property=' + operation + '=/usr/local/libexec/labwc-waybar-state '
                                          + phase + ' ' + environment['LABWC_WAYBAR_STATE_BUTTON']
                                          + ' ' + identity, command)


class StateMarkerReadFixtures(unittest.TestCase):
    def test_actual_reader_rejects_unsafe_and_oversize_markers(self):
        module = ModuleType('waybar_marker_reader_fixture')
        source = target_text('usr/local/lib/python3/dist-packages/labwc_waybar_state.py')
        exec(compile(source, 'rendered-marker-reader', 'exec'), vars(module))
        with tempfile.TemporaryDirectory(prefix='waybar-marker-read-') as temporary:
            root = Path(temporary)
            markers = root / 'markers'
            markers.mkdir(mode=0o700)
            identity = 'a' * 32
            marker = markers / f'cpu-{identity}.json'
            valid = {'version': 1, 'button': 'cpu', 'id': identity, 'uid': os.getuid(), 'pid': 1}

            def publish(data):
                marker.write_text(json.dumps(data), encoding='ascii')
                marker.chmod(0o600)

            with mock.patch.object(module, 'state_directory', return_value=markers):
                publish(valid)
                self.assertTrue(module.active('cpu'))
                for bad in ({**valid, 'id': 'b' * 32}, {**valid, 'version': True},
                            {**valid, 'uid': str(os.getuid())}):
                    publish(bad)
                    self.assertFalse(module.active('cpu'))
                marker.write_bytes(b'x' * 4097)
                self.assertFalse(module.active('cpu'))
                publish(valid)
                outside = root / 'outside'
                marker.rename(outside)
                marker.symlink_to(outside)
                self.assertFalse(module.active('cpu'))
                marker.unlink()
                os.link(outside, marker)
                self.assertFalse(module.active('cpu'))
                marker.unlink()
                publish(valid)
                marker.chmod(0o644)
                self.assertFalse(module.active('cpu'))


class DesktopRuntimeIdentityFixtures(unittest.TestCase):
    def invoke(self, name, *, directory_mode=0o700, directory_owner=1000,
               directory_type=stat.S_IFDIR, socket_mode=0o666, socket_owner=1000,
               socket_type=stat.S_IFSOCK, socket_links=1):
        helper = load_helper(name)
        metadata = {
            '/run/user/1000': SimpleNamespace(st_mode=directory_type | directory_mode,
                                              st_uid=directory_owner, st_nlink=8),
            '/run/user/1000/bus': SimpleNamespace(st_mode=socket_type | socket_mode,
                                                  st_uid=socket_owner, st_nlink=socket_links),
        }
        def lstat(path):
            self.assertIn(str(path), metadata)  # No fallback to host filesystem.
            return metadata[str(path)]
        gi = ModuleType('gi')
        gi.require_version = mock.Mock()
        repository = ModuleType('gi.repository')
        repository.Gio = repository.GLib = repository.GLibUnix = object()
        gi.repository = repository
        with ExitStack() as stack:
            stack.enter_context(mock.patch.object(helper.os, 'getuid', return_value=1000))
            stack.enter_context(mock.patch.object(helper.os, 'geteuid', return_value=1000))
            stack.enter_context(mock.patch.object(Path, 'lstat', lstat))
            stack.enter_context(mock.patch.dict(os.environ, {
                'LABWC_SESSION_OWNER': 'desktop', 'XDG_SESSION_TYPE': 'wayland',
                'XDG_RUNTIME_DIR': '/run/user/1000', 'WAYLAND_DISPLAY': 'wayland-0',
            }, clear=True))
            if name == 'labwc-waybar-events.tmpl':
                stack.enter_context(mock.patch.dict(sys.modules, {'gi': gi, 'gi.repository': repository}))
                reader = stack.enter_context(mock.patch.object(helper, 'Reader'))
                reader.return_value.run.return_value = 0
                return helper.main(['notifications'])
            stack.enter_context(mock.patch.object(helper.pwd, 'getpwuid',
                return_value=SimpleNamespace(pw_dir='/home/fixture', pw_name='fixture')))
            return helper.environment()

    def test_private_runtime_accepts_bus_socket_modes_for_status_controls_and_calendar(self):
        for name in ('labwc-waybar-events.tmpl', 'labwc-notifications.tmpl', 'labwc-calendar-actions'):
            for mode in (0o600, 0o660, 0o700, 0o666, 0o755, 0o777):
                with self.subTest(helper=name, mode=oct(mode)):
                    result = self.invoke(name, socket_mode=mode)
                    if isinstance(result, dict):
                        self.assertEqual(result['DBUS_SESSION_BUS_ADDRESS'], 'unix:path=/run/user/1000/bus')
                    else:
                        self.assertEqual(result, 0)

    def test_unsafe_identity_is_rejected_before_bus_or_gtk_access(self):
        cases = (
            {'directory_mode': 0o755}, {'directory_owner': 1001},
            {'directory_type': stat.S_IFLNK}, {'socket_owner': 1001},
            {'socket_type': stat.S_IFREG}, {'socket_type': stat.S_IFLNK},
            {'socket_links': 2},
        )
        for name in ('labwc-waybar-events.tmpl', 'labwc-notifications.tmpl', 'labwc-calendar-actions'):
            for case in cases:
                with self.subTest(helper=name, case=case), self.assertRaises(Exception) as raised:
                    self.invoke(name, **case)
                self.assertEqual(type(raised.exception).__name__,
                                 'ValueError' if name == 'labwc-waybar-events.tmpl' else 'Error')

    def test_calendar_startup_errors_keep_specific_codes_without_exception_content(self):
        helper = load_helper('labwc-calendar-actions')
        cases = ((helper.Error('unsafe-account'), 1, 'error=unsafe-account'),
                 (helper.Error('credentials-unavailable'), 3, 'error=credentials-unavailable'),
                 (helper.Error('outcome-unknown'), 4, 'status=outcome-unknown'),
                 (PermissionError('private fixture detail'), 1, 'cause=PermissionError'))
        for failure, status, marker in cases:
            errors = io.StringIO()
            with self.subTest(error=type(failure).__name__), \
                    mock.patch.object(helper, 'main', side_effect=failure), redirect_stderr(errors):
                self.assertEqual(helper.cli(), status)
            self.assertIn(marker, errors.getvalue())
            self.assertNotIn('private fixture detail', errors.getvalue())


class TaskviewRuntimeFixtures(unittest.TestCase):
    def invoke(self, *, directory_metadata='1000 700', socket_metadata='1000 1',
               runtime_mismatch=False, directory_alias=False, socket_kind='socket',
               socket_mode=0o755):
        with tempfile.TemporaryDirectory(prefix='waybar-button-') as temporary:
            root = Path(temporary)
            runtime = root / '1000'
            runtime.mkdir(mode=0o700)
            # A real directory has multiple links; children must not hide taskview.
            (runtime / 'children').mkdir()
            endpoint = runtime / 'wayland-0'
            if socket_kind == 'file':
                endpoint.write_text('not a socket')
            else:
                bound = runtime / 'bound' if socket_kind == 'alias' else endpoint
                with socket.socket(socket.AF_UNIX) as inert:
                    inert.bind(str(bound))
                bound.chmod(socket_mode)
                if socket_kind == 'alias':
                    endpoint.symlink_to(bound.name)
            if directory_alias:
                moved = root / 'original'
                runtime.rename(moved)
                runtime.symlink_to(moved.name, target_is_directory=True)

            tools = {
                '/usr/bin/id': '#!/bin/sh\nprintf "%s\\n" 1000\n',
                '/usr/bin/find': '''#!/bin/sh
set -eu
[ "$#" -eq 6 ] && [ "$1" = -P ] && [ "$3" = -maxdepth ] && [ "$4" = 0 ] && [ "$5" = -printf ] || exit 2
case "$2:$6" in
  "$FIXTURE_RUNTIME:%U %m") printf '%s\\n' "$FIXTURE_DIRECTORY_METADATA" ;;
  "$FIXTURE_RUNTIME/wayland-0:%U %n") printf '%s\\n' "$FIXTURE_SOCKET_METADATA" ;;
  *) exit 2 ;;
esac
''',
                # Capture the fixed timeout/wtype argv; execute neither program.
                '/usr/bin/timeout': '#!/bin/sh\nprintf "%s\\n" "$@"\n',
            }
            source = target_text('usr/local/bin/labwc-window-switcher')
            original = 'runtime_root="/run/user/$runtime_uid"'
            self.assertEqual(source.count(original), 1)
            source = source.replace(original, 'runtime_root="$FIXTURE_ROOT/1000"')
            for installed, body in tools.items():
                tool = root / Path(installed).name
                tool.write_text(body, encoding='utf-8')
                tool.chmod(0o700)
                self.assertIn(installed, source)
                source = source.replace(installed, shlex.quote(str(tool)))
            wrapper = root / 'switcher.sh'
            wrapper.write_text(source, encoding='utf-8')
            # No inherited HOME, PATH, runtime bus, credentials or service state.
            environment = {
                'PATH': '/usr/bin:/bin', 'HOME': str(root), 'LC_ALL': 'C',
                'LABWC_SESSION_OWNER': 'desktop', 'XDG_SESSION_TYPE': 'wayland',
                'WAYLAND_DISPLAY': 'wayland-0',
                'XDG_RUNTIME_DIR': str(root / 'foreign' if runtime_mismatch else runtime),
                'FIXTURE_ROOT': str(root), 'FIXTURE_RUNTIME': str(runtime),
                'FIXTURE_DIRECTORY_METADATA': directory_metadata,
                'FIXTURE_SOCKET_METADATA': socket_metadata,
            }
            return subprocess.run(['/bin/sh', '-eu', str(wrapper)], env=environment,
                                  cwd=root, stdin=subprocess.DEVNULL,
                                  capture_output=True, text=True, timeout=3)

    def test_private_parent_accepts_compositor_socket_permissions(self):
        for mode in (0o600, 0o660, 0o700, 0o755, 0o777):
            with self.subTest(mode=oct(mode)):
                result = self.invoke(socket_mode=mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.splitlines(), [
                    '--signal=TERM', '--kill-after=1s', '2s',
                    '/usr/bin/wtype', '-P', 'F13', '-p', 'F13'])

    def test_unsafe_runtime_or_endpoint_never_reaches_key_dispatch(self):
        cases = (
            {'runtime_mismatch': True}, {'directory_alias': True},
            {'directory_metadata': '1001 700'}, {'directory_metadata': '1000 755'},
            {'socket_kind': 'file'}, {'socket_kind': 'alias'},
            {'socket_metadata': '1001 1'}, {'socket_metadata': '1000 2'},
        )
        for case in cases:
            with self.subTest(case=case):
                result = self.invoke(**case)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, '')
                self.assertIn('labwc-window-switcher', result.stderr)


class WaybarDescriptorFixtures(unittest.TestCase):
    """Mock the descriptor syscall; never close a fixture runner descriptor."""

    def test_volume_presets_accept_only_fixed_sink_levels_and_a_unity_limit(self):
        helper = load_helper('labwc-waybar-run')
        prefix = ['/usr/bin/wpctl', 'set-volume', '@DEFAULT_AUDIO_SINK@']
        for level in ('25%', '45%', '65%', '85%', '100%'):
            command = [*prefix, level, '--limit', '1.0']
            self.assertEqual(helper.normalize_command(['--', *command]),
                             (tuple(command), None))
        rejected = [
            [*prefix, level, '--limit', '1.0']
            for level in ('0%', '40%', '101%', '25%+', '65%;id')
        ] + [
            [*prefix, '25%'],
            [*prefix, '25%', '--limit', '1.2'],
            [*prefix, '25%', '--limit', '1.0', '--mute'],
            ['/usr/bin/wpctl', 'set-volume', '@DEFAULT_AUDIO_SOURCE@', '25%', '--limit', '1.0'],
        ]
        for command in rejected:
            with self.subTest(command=command), self.assertRaises(ValueError):
                helper.normalize_command(['--', *command])

    def test_both_wrappers_use_a_valid_c_int_endpoint_without_procfs(self):
        for name in ('labwc-waybar-run', 'labwc-waybar-exec'):
            helper = load_helper(name)
            def closerange(first, end):
                # Model CPython's argument conversion, which rejects
                # sys.maxsize on the 64-bit target before calling close_range.
                if not -(2**31) <= end <= 2**31 - 1:
                    raise OverflowError('Python int too large to convert to C int')
                self.assertEqual(first, 3)
                self.assertEqual(end, 2**31 - 1)
            with self.subTest(helper=name), \
                    mock.patch.object(helper.os, 'closerange', side_effect=closerange) as close, \
                    mock.patch.object(helper.os, 'listdir', side_effect=AssertionError('procfs discovery')):
                helper.close_inherited_fds()
            close.assert_called_once()

    def test_exec_wrapper_removes_loader_and_gui_injection_variables(self):
        helper = load_helper('labwc-waybar-exec')
        captured = {}
        with mock.patch.object(helper, 'command', return_value=('/usr/local/libexec/labwc-waybar-battery',)), \
                mock.patch.object(helper, 'close_inherited_fds'), \
                mock.patch.object(helper.os, 'getuid', return_value=1000), \
                mock.patch.object(helper.os, 'geteuid', return_value=1000), \
                mock.patch.object(helper.os, 'execve', side_effect=lambda path, argv, env: captured.update(
                    path=path, argv=argv, env=env)), \
                mock.patch.dict(helper.os.environ, {
                    'LD_PRELOAD': '/tmp/fixture.so', 'PYTHONPATH': '/tmp/fixture',
                    'GTK_MODULES': 'fixture', 'DISPLAY': ':99', 'WAYLAND_DISPLAY': 'wayland-0',
                }, clear=True):
            helper.main(['labwc-waybar-battery'])
        self.assertEqual(captured['argv'], ('/usr/local/libexec/labwc-waybar-battery',))
        self.assertNotIn('LD_PRELOAD', captured['env'])
        self.assertNotIn('PYTHONPATH', captured['env'])
        self.assertNotIn('GTK_MODULES', captured['env'])
        self.assertNotIn('DISPLAY', captured['env'])
        self.assertEqual(captured['env']['WAYLAND_DISPLAY'], 'wayland-0')


class WaybarSeparationFixtures(unittest.TestCase):
    """Source-only cases; native execution remains prohibited."""


    def test_every_native_menu_leaf_has_one_scoped_action(self):
        import xml.etree.ElementTree as ET
        root = TARGET / 'etc/skel-desktop/.config/waybar'
        count = 0
        for path in sorted((root / 'modules').glob('*.tmpl')):
            # This checks authored leaf/action identity. The native fixture
            # separately exercises the complete producer and final rendering.
            text = rendered_path_text(path.read_text(encoding='utf-8'))
            text = re.sub(r'__[A-Z0-9_]+__(?=\s*[,}\]])', '0', text)
            for entry in json.loads(text).values():
                if 'menu-file' not in entry:
                    continue
                relative = entry['menu-file'].removeprefix('~/.config/waybar/')
                self.assertRegex(relative, r'^gtk/[a-z-]+\.xml$')
                tree = ET.fromstring((root / (relative + '.tmpl')).read_text())
                ids = [item.get('id') for item in tree.iter('object')
                       if item.get('class') == 'GtkMenuItem'
                       and item.find('./child[@type="submenu"]') is None]
                self.assertEqual(len(ids), len(set(ids)))
                self.assertEqual(set(ids), set(entry['menu-actions']))
                for action in entry['menu-actions'].values():
                    argv = shlex.split(action)
                    self.assertEqual(argv[0], '/usr/local/libexec/labwc-waybar-run')
                    self.assertEqual(argv[:argv.index('--')], ['/usr/local/libexec/labwc-waybar-run'])
                count += 1
        self.assertGreater(count, 0)


class PopupIdentityFixtures(unittest.TestCase):
    """Actual helper and XML, mocked GTK/processes inside the isolated image."""

    def test_tomat_popup_keeps_preset_labels_stable_without_rewriting_the_asset(self):
        import xml.etree.ElementTree as ET
        helper = load_helper('labwc-waybar-menu')
        source = TARGET / 'etc/skel-desktop/.config/waybar/gtk/tomat-menu.xml.tmpl'
        tree = ET.fromstring(source.read_text())
        # Icon decoding belongs to the GTK fixture. Keep this check limited to
        # the actual menu's preset labels and preserve its action identities.
        for parent in tree.iter():
            for child in list(parent):
                if child.get('class') == 'GtkImage':
                    parent.remove(child)
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'tomat-menu.xml'
            path.write_text(ET.tostring(tree, encoding='unicode'))
            before = path.read_bytes()
            xml, _icons = helper.prepared_menu_xml(path)
            prepared_menu = ET.fromstring(xml)
            for identity, expected in (('tomat_25_label', '25 / 5'),
                                       ('tomat_50_label', '50 / 10'),
                                       ('tomat_90_label', '90 / 15')):
                label = prepared_menu.find(f".//object[@id='{identity}']/property[@name='label']")
                self.assertEqual(label.text, expected)
            self.assertEqual(path.read_bytes(), before)

    def toolkit(self, xml):
        import xml.etree.ElementTree as ET

        class Item:
            def __init__(self, identity, submenu=False):
                self.identity, self.submenu, self.callbacks = identity, submenu, {}

            def get_name(self):
                return 'GtkMenuItem'  # CSS name deliberately differs from XML ID.

            def get_submenu(self):
                return object() if self.submenu else None

            def connect(self, event, callback, *data):
                self.callbacks[event] = (callback, data)

        class Separator(Item):
            pass

        class Menu:
            def __init__(self, identity, _submenu=False):
                self.identity, self.callbacks = identity, {}

            def connect(self, event, callback, *data):
                self.callbacks[event] = (callback, data)

            def popdown(self):
                for event in ('deactivate', 'selection-done', 'hide'):
                    if event in self.callbacks:
                        callback, data = self.callbacks[event]
                        callback(self, *data)

            def popup_at_pointer(self, _event):
                pass

        objects = {}
        for element in ET.fromstring(xml).iter('object'):
            kind, identity = element.get('class'), element.get('id')
            if kind in ('GtkMenu', 'GtkMenuItem', 'GtkSeparatorMenuItem'):
                cls = Menu if kind == 'GtkMenu' else Separator if kind == 'GtkSeparatorMenuItem' else Item
                objects[identity] = cls(identity, element.find('./child[@type="submenu"]') is not None)
        builder = SimpleNamespace(add_from_string=lambda _xml: None,
                                  get_object=objects.get, get_objects=lambda: list(objects.values()))
        gtk = SimpleNamespace(Menu=Menu, MenuItem=Item, SeparatorMenuItem=Separator,
                              Buildable=SimpleNamespace(get_name=lambda obj: obj.identity),
                              Builder=lambda: builder,
                              CssProvider=lambda: SimpleNamespace(load_from_path=lambda _path: None),
                              StyleContext=SimpleNamespace(add_provider_for_screen=lambda *_args: None),
                               STYLE_PROVIDER_PRIORITY_USER=800,
                               get_current_event=lambda: None,
                              main_level=lambda: 1, main_quit=mock.Mock())
        glib = SimpleNamespace(PRIORITY_DEFAULT=0, child_watch_add=mock.Mock(),
                               idle_add=mock.Mock())
        gdk = SimpleNamespace(Screen=SimpleNamespace(get_default=lambda: object()),
                              EventType=SimpleNamespace(BUTTON_PRESS=4))
        return (gdk, glib, gtk, None), objects

    def popup(self, button):
        helper = load_helper('labwc-waybar-menu')
        root = TARGET / 'etc/skel-desktop/.config/waybar'
        text = rendered_path_text((root / 'modules' / (button + '.tmpl')).read_text())
        module = json.loads(re.sub(r'__[A-Z0-9_]+__(?=\s*[,}\]])', '0', text))
        entry = module['custom/' + button]
        xml = (root / 'gtk' / (button + '-menu.xml.tmpl')).read_text()
        # Identity/dispatch fixtures isolate icon decoding; native fixtures
        # separately exercise recoverable pixbuf loading and the fallback.
        helper.prepared_menu_xml = lambda _path: (xml, [])
        toolkit, objects = self.toolkit(xml)
        actions = {key: helper.fixed_action(value) for key, value in entry['menu-actions'].items()}
        popup = helper.Popup(toolkit, button, Path('fixture.xml'), Path('fixture.css'), actions)
        # Native layer-shell anchoring is exercised in the disconnected GTK
        # guest; these fixtures isolate builder identity and dispatch ordering.
        popup.prepare_surfaces = mock.Mock()
        return helper, popup, objects

    def test_all_four_action_maps_use_builder_leaf_ids_not_css_names(self):
        for button in ('notifications', 'power', 'tomat', 'wayscriber'):
            with self.subTest(button=button):
                _helper, popup, objects = self.popup(button)
                popup.activate()
                bound = {identity for identity, obj in objects.items() if 'activate' in obj.callbacks}
                self.assertEqual(bound, set(popup.actions))
                for identity in bound:
                    self.assertEqual(objects[identity].callbacks['activate'][1], (identity,))
                popup.actions['not_an_xml_leaf'] = ['/not-executed']
                with self.assertRaisesRegex(ValueError, 'leaves'):
                    popup.activate()

    def test_popdown_clears_exact_marker_but_waits_for_one_child_result(self):
        helper, popup, objects = self.popup('wayscriber')
        popup.activate()
        child = SimpleNamespace(pid=1234, returncode=None)
        with mock.patch.dict(os.environ, {'LABWC_WAYBAR_ACTION_ID': 'a' * 32}, clear=True), \
                mock.patch.object(helper.subprocess, 'run') as clear, \
                mock.patch.object(helper.subprocess, 'Popen', return_value=child) as start:
            action_id = next(iter(popup.actions))
            popup.action(objects[action_id], action_id)
            popup.action(objects[action_id], action_id)
            self.assertEqual(start.call_count, 1)
            self.assertEqual(clear.call_count, 1)
            self.assertEqual(clear.call_args.args[0][-3:], ['cleanup', 'wayscriber', 'a' * 32])
            self.assertFalse(popup.done)
            popup.Gtk.main_quit.assert_not_called()
            popup.action_done(child.pid, 1 << 8)
            self.assertEqual(popup.status, 3)
            self.assertEqual(child.returncode, 1)
            popup.Gtk.main_quit.assert_called_once()

    def test_dismissal_and_marker_failure_have_distinct_results(self):
        for error, status in ((None, 0), (OSError('fixture failure'), 3)):
            _helper, popup, _objects = self.popup('wayscriber')
            with mock.patch.dict(os.environ, {'LABWC_WAYBAR_ACTION_ID': 'b' * 32}, clear=True), \
                    mock.patch.object(subprocess, 'run', side_effect=error) as clear, redirect_stderr(io.StringIO()):
                popup.dismiss()
                if error is None:
                    self.assertFalse(popup.done)
                    popup.dismissed()
                popup.dismiss()  # Later GTK close/destroy callbacks must not retry.
                clear.assert_called_once()
            self.assertTrue(popup.done)
            self.assertEqual(popup.status, status)

    def test_gtk_deactivation_before_activation_does_not_discard_action(self):
        helper, popup, objects = self.popup('wayscriber')
        popup.activate()
        child = SimpleNamespace(pid=1234, returncode=None)
        with mock.patch.dict(os.environ, {'LABWC_WAYBAR_ACTION_ID': 'c' * 32}, clear=True), \
                mock.patch.object(helper.subprocess, 'run') as clear, \
                mock.patch.object(helper.subprocess, 'Popen', return_value=child) as start:
            # GTK 3.24 gtk_menu_shell_activate_item deactivates before
            # gtk_widget_activate emits the leaf's activation signal.
            popup.menu.popdown()
            self.assertFalse(popup.done)
            self.assertTrue(popup.dismiss_pending)
            popup.GLib.idle_add.assert_called_once_with(popup.dismissed)
            action_id = next(iter(popup.actions))
            popup.action(objects[action_id], action_id)
            popup.dismissed()
            self.assertFalse(popup.done)
            start.assert_called_once()
            clear.assert_called_once()
            popup.action_done(child.pid, 0)
            self.assertEqual(popup.status, 0)

    def test_menu_grab_routes_anchor_click_through_its_release(self):
        helper, popup, _objects = self.popup('wayscriber')
        popup.activate()
        anchor = SimpleNamespace(hide=mock.Mock(), destroy=mock.Mock())
        popup.windows = [anchor]
        event = SimpleNamespace(button=1, x=100, y=100)
        with mock.patch.dict(os.environ, {'LABWC_WAYBAR_ACTION_ID': 'e' * 32}, clear=True), \
                mock.patch.object(helper.subprocess, 'run') as clear, \
                mock.patch.object(popup.Gtk, 'get_event_widget', create=True, return_value=anchor):
            self.assertTrue(popup.menu_button_press(popup.menu, event))
            self.assertEqual(popup.buttons, {1})
            clear.assert_not_called()
            self.assertTrue(popup.menu_button_release(popup.menu, event))
            self.assertEqual(popup.buttons, set())
            clear.assert_called_once()
            popup.dismissed()
            self.assertTrue(popup.done)
            self.assertEqual(popup.status, 0)


class WaybarMenuSourceFixtures(unittest.TestCase):

    def test_cursor_retry_is_disabled_for_every_native_and_custom_module(self):
        root = TARGET / 'etc/skel-desktop/.config/waybar/modules'
        # Both supplied crashes match the 0.15.0 setCursor timeout lambda at
        # ELF offset 0xb11fd. Removing the key is insufficient: mouse enter
        # and leave then invoke the same retry through the default path.
        for path in sorted(root.glob('*.tmpl')):
            text = path.read_text(encoding='utf-8')
            rendered = re.sub(r'__[A-Z0-9_]+__', '0', text)
            value = json.loads(rendered)
            for module_name, configuration in value.items():
                with self.subTest(file=path.name, module=module_name):
                    self.assertIs(configuration.get('cursor'), False)

    @staticmethod
    def dispatcher():
        path = target_source('usr/local/bin/labwc-system-menu-action')
        module = ModuleType('system_menu_fixture')
        module.__file__ = str(path)
        with tempfile.TemporaryDirectory(prefix='fixed-dispatcher-render-') as temporary:
            rendered = render_scalar_fixture(path, Path(temporary))
        exec(compile(rendered, str(path), 'exec'), module.__dict__)
        return module

    def test_status_and_reload_actions_do_not_restart_services(self):
        helper = self.dispatcher()
        for key, action in (('help_waybar_status', 'waybar-status'),
                            ('help_crystal_dock_status', 'dock-status'),
                            ('session_show_idle_dpms', 'idle-status')):
            self.assertEqual(helper.COMMANDS[key], ('/usr/local/bin/labwc-system-action', action))
        self.assertEqual(helper.COMMANDS['help_reload_waybar'],
                         ('/usr/bin/systemctl', '--user', '--no-block', 'reload', 'waybar.service'))

    def test_capture_menu_uses_controller_actions_and_allows_new_clipboard_ownership(self):
        helper = self.dispatcher()
        for key, action in (('capture_ocr', 'ocr-capture'), ('capture_ocr_last', 'ocr-last'),
                            ('capture_open_folder', 'open-folder'), ('capture_copy_last_path', 'copy-last-path')):
            self.assertEqual(helper.COMMANDS[key], ('/usr/local/bin/labwc-capture', action))
        root = TARGET / 'etc/skel-desktop/.config/waybar'
        entry = json.loads((root / 'modules/system.tmpl').read_text())['custom/settings']
        self.assertNotIn('capture_copy_last_path', entry['menu-actions'])
        self.assertIn('capture_screenshot_full', entry['menu-actions'])
        launcher = load_helper('labwc-waybar-run')
        identifiers = [SimpleNamespace(hex='a' * 32), SimpleNamespace(hex='b' * 32)]
        with mock.patch.object(launcher.uuid, 'uuid4', side_effect=identifiers):
            first = launcher.systemd_command(('/usr/local/bin/labwc-capture', 'record-full'), None)
            second = launcher.systemd_command(('/usr/local/bin/labwc-capture', 'record-full'), None)
        self.assertNotEqual(next(x for x in first if x.startswith('--unit=')),
                            next(x for x in second if x.startswith('--unit=')))
        for command in (first, second):
            self.assertIn('--property=ExitType=cgroup', command)
            self.assertIn('--property=KillMode=control-group', command)
            self.assertIn('--property=PartOf=labwc-session.target waybar.service', command)
            self.assertIn(
                '--property=ConditionPathExists=!/run/user/' + str(os.getuid())
                + '/labwc-session-closing', command)
            self.assertNotIn('--no-block', command)

    def test_system_and_reminder_labels_use_matching_reviewed_workflows(self):
        helper = self.dispatcher()
        expected = {
            'system_cpu_load': ('/usr/local/bin/labwc-system-action', 'cpu-load'),
            'system_battery_power': ('/usr/local/bin/labwc-system-action', 'battery-power'),
            'connectivity_listening_ports': ('/usr/local/bin/labwc-system-action', 'network-listening'),
            'connectivity_veth_lease': ('/usr/local/bin/labwc-system-action', 'network-namespace'),
            'help_wayland_output_info': ('/usr/local/bin/labwc-terminal', '-e', '/usr/bin/wlr-randr'),
            'help_test_audio': ('/usr/local/bin/labwc-terminal', '-e', '/usr/bin/paplay',
                                '/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga'),
            'reminder_upcoming': ('/usr/local/libexec/labwc-reminder-manager', '--upcoming'),
            'reminder_overdue': ('/usr/local/libexec/labwc-reminder-manager', '--overdue'),
            'reminder_mark_selected_complete': ('/usr/local/libexec/labwc-reminder-manager', '--complete-selected'),
            'reminder_edit_selected': ('/usr/local/libexec/labwc-reminder-manager', '--edit-selected'),
            'reminder_delete_selected': ('/usr/local/libexec/labwc-reminder-manager', '--delete-selected'),
            'reminder_clear_expired': ('/usr/local/libexec/labwc-reminder-manager', '--clear-expired'),
        }
        for key, command in expected.items():
            with self.subTest(key=key):
                self.assertEqual(helper.COMMANDS[key], command)

    def test_reminder_manager_routes_have_real_filters_and_selected_operations(self):
        local = target_text('usr/local/lib/python3/dist-packages/labwc_local_reminders.py')
        gtk = target_text('usr/local/lib/python3/dist-packages/labwc_calendar_reminders_gtk.py')
        manager = target_text('usr/local/libexec/labwc-reminder-manager')
        for contract in ('def filtered(self, view: str)', 'def clear_expired(self) -> int',
                         'def clear_paused(self) -> int',
                         'datetime.fromisoformat(item[\'due\'])'):
            self.assertIn(contract, local)
        for contract in ('self.store.filtered(self.view)', 'self.store.clear_expired()',
                         'self.store.clear_paused()',
                         'def apply_selected(self)', 'Gtk.SelectionMode.SINGLE',
                         "'complete-selected'", "'edit-selected'", "'delete-selected'"):
            self.assertIn(contract, gtk)
        for flag in ('--upcoming', '--overdue', '--complete-selected', '--edit-selected',
                     '--delete-selected', '--clear-expired'):
            self.assertIn(flag, manager)

    def test_interactive_delegate_replaces_dispatcher_without_foreground_timer(self):
        helper = self.dispatcher()
        env = {'HOME': '/fixture/home', 'PATH': '/usr/bin:/bin'}
        for action in ('reminder_manager', 'display_appearance', 'help_main_menu'):
            with self.subTest(action=action), \
                    mock.patch.object(helper, 'desktop_environment', return_value=env), \
                    mock.patch.object(helper.os, 'chdir') as chdir, \
                    mock.patch.object(helper.os, 'execvpe', side_effect=StopIteration) as execute, \
                    mock.patch.object(helper.subprocess, 'run', side_effect=AssertionError('unexpected child')):
                with self.assertRaises(StopIteration):
                    helper.main([action])
                chdir.assert_called_once_with('/fixture/home')
                command = helper.COMMANDS[action]
                execute.assert_called_once_with(command[0], command, env)

    def test_mute_feedback_recognizes_wpctl_bracketed_state(self):
        helper = self.dispatcher()
        for output, expected in (('Volume: 0.40 [MUTED]\n', True), ('Volume: 0.40\n', False)):
            with mock.patch.object(helper.subprocess, 'run',
                                   return_value=SimpleNamespace(returncode=0, stdout=output)):
                self.assertIs(helper.audio_muted({'HOME': '/fixture/home'}, '@DEFAULT_AUDIO_SINK@'), expected)

    @staticmethod
    def network_menu():
        path = target_source('usr/local/bin/labwc-network-control-menu')
        module = ModuleType('network_menu_fixture')
        module.__file__ = str(path)
        runtime = ModuleType('labwc_desktop_runtime')
        rendered = target_text('usr/local/bin/labwc-network-control-menu')
        with mock.patch.dict(sys.modules, {'labwc_desktop_runtime': runtime}):
            exec(compile(rendered, str(path), 'exec'), module.__dict__)
        return module

    def test_wireguard_native_actions_keep_selected_identity_and_failure_result(self):
        helper = self.network_menu()
        selected = 'aabbccdd-1234-5678-9876-001122334455'
        for verb, state in (('activate', 'saved'), ('deactivate', 'active')):
            with self.subTest(verb=verb), \
                    mock.patch.object(helper, 'choose_connection', return_value=selected) as choose, \
                    mock.patch.object(helper, 'network_action', return_value=4) as backend:
                self.assertEqual(helper.single_action('wireguard-' + verb), 4)
                choose.assert_called_once_with('wireguard', state)
                backend.assert_called_once_with(verb + '-wireguard', selected)
        with mock.patch.object(helper, 'choose_connection', return_value=None), \
                mock.patch.object(helper, 'network_action') as backend:
            self.assertEqual(helper.single_action('wireguard-activate'), 0)
            backend.assert_not_called()

    def test_dns_restore_requires_confirmation_and_never_reports_backend_failure_as_success(self):
        helper = self.network_menu()
        selected = 'aabbccdd-1234-5678-9876-001122334455'
        for confirmed in (False, True):
            with self.subTest(confirmed=confirmed), \
                    mock.patch.object(helper, 'choose_connection', return_value=selected), \
                    mock.patch.object(helper, 'confirm', return_value=confirmed), \
                    mock.patch.object(helper, 'network_action', return_value=1) as backend:
                self.assertEqual(helper.single_action('dns-restore'), 1 if confirmed else 0)
                if confirmed:
                    backend.assert_called_once_with('restore-automatic-dns', selected, 'confirmed-network-action')
                else:
                    backend.assert_not_called()

    def test_network_timeout_propagates_uncertain_outcome_without_retry(self):
        helper = self.network_menu()
        with mock.patch.object(helper, 'run', side_effect=subprocess.TimeoutExpired(['fixture'], 1)) as run, \
                redirect_stderr(io.StringIO()):
            self.assertEqual(helper.network_action('activate-wireguard', 'fixture-uuid'), 4)
            run.assert_called_once()


class AppArmorExecutePermissionFixtures(unittest.TestCase):
    """Exercise the static check against private policy text, without a parser."""

    def check_policy(self, rule):
        checker = Path(__file__).resolve().parents[3] / 'tools/post_change_check.py'
        tree = ast.parse(checker.read_text(encoding='utf-8'), filename=str(checker))
        function = next(node for node in tree.body
                        if isinstance(node, ast.FunctionDef) and node.name == 'check_apparmor')
        with tempfile.TemporaryDirectory(prefix='apparmor-rule-fixture-') as name:
            root = Path(name)
            target = root / 'target'
            policy = target / 'etc/apparmor.d/fixture'
            policy.parent.mkdir(parents=True)
            policy.write_text('profile fixture {\n  ' + rule + '\n}\n', encoding='utf-8')
            namespace = {'Path': Path, 're': re, 'ROOT': root, 'TARGET_ROOT': target,
                         '_read_text': lambda path: path.read_text(encoding='utf-8')}
            exec(compile(ast.Module(body=[function], type_ignores=[]), str(checker), 'exec'), namespace)
            errors, counts = [], {}
            namespace['check_apparmor']([policy], errors, counts)
            self.assertEqual(counts['apparmor_files'], 1)
            return errors

    def test_allow_directory_execute_requires_a_qualifier(self):
        for rule in ('owner /run/user/[0-9]*/ rwx,', 'audit owner /fixture/** x,',
                     'allow "/fixture path/tool" rx, # invalid allow execution'):
            with self.subTest(rule=rule):
                errors = self.check_policy(rule)
                self.assertEqual(len(errors), 1)
                self.assertIn('execution qualifier', errors[0])

    def test_qualified_execution_and_explicit_deny_execute_are_valid(self):
        for rule in ('owner /run/user/[0-9]*/ rw,', '/usr/bin/helper rix,',
                     '/fixture/tool rPx -> fixture-child,', '/fixture/tool pux,',
                     'deny owner @{HOME}/Downloads/** x,', 'audit deny /fixture/** rwx,'):
            with self.subTest(rule=rule):
                self.assertEqual(self.check_policy(rule), [])


class LocalReminderFailureFixtures(unittest.TestCase):
    """Private state only; every external command and account lookup is blocked."""

    @contextmanager
    def private_store(self):
        path = target_source('usr/local/lib/python3/dist-packages/labwc_local_reminders.py')
        helper = ModuleType('local_reminder_failure_fixture')
        helper.__file__ = str(path)
        source = target_text('usr/local/lib/python3/dist-packages/labwc_local_reminders.py')
        with ExitStack() as stack:
            stack.enter_context(mock.patch.dict(os.environ, {}, clear=True))
            stack.enter_context(mock.patch.object(subprocess, 'run',
                                side_effect=AssertionError('external command prohibited')))
            exec(compile(source, str(path), 'exec'), helper.__dict__)
            stack.enter_context(mock.patch.object(helper.pwd, 'getpwuid',
                                side_effect=AssertionError('host account lookup prohibited')))
            stack.enter_context(mock.patch.object(helper, '_home',
                                side_effect=AssertionError('explicit fixture home required')))
            # Date parsing is outside these locking/publication fixtures; avoid
            # looking up any host timezone files while validating fixture items.
            stack.enter_context(mock.patch.object(helper, '_due', side_effect=lambda value, zone: value))
            name = stack.enter_context(tempfile.TemporaryDirectory(prefix='local-reminder-fixture-'))
            home = Path(name) / 'home'
            for directory in (home, home / '.config', home / '.config/calix'):
                directory.mkdir(mode=0o700)
            yield helper, helper.Store(home)

    @staticmethod
    def item(letter, *, enabled):
        return {'id': letter * 32, 'title': 'Fixture reminder', 'body': '',
                'due': '2030-01-02T03:04+00:00', 'timezone': 'UTC', 'first_minutes': 0,
                'recurrence': 'none', 'sound': False, 'urgency': 'normal',
                'allow_dnd': False, 'enabled': enabled, 'link': None, 'created': 0, 'updated': 0}

    @staticmethod
    def write_state(helper, store, *items):
        path = store.directory / helper.STATE_NAME
        path.write_text(json.dumps({'version': 1, 'items': {item['id']: item for item in items}})
                        + '\n', encoding='utf-8')
        path.chmod(0o600)
        return path

    def test_cleanup_uses_current_state_and_keeps_resumed_reminders(self):
        with self.private_store() as (helper, store):
            paused = self.item('a', enabled=False)
            active = self.item('b', enabled=True)
            path = self.write_state(helper, store, paused, active)
            old_snapshot = store.list()
            self.assertFalse(old_snapshot[0]['enabled'])
            store.mutate('set-enabled', item=True, item_id=paused['id'])
            previous = path.read_bytes()
            self.assertEqual(store.clear_paused(), 0)
            self.assertEqual(path.read_bytes(), previous)
            store.mutate('set-enabled', item=False, item_id=paused['id'])
            with mock.patch.object(helper.os, 'replace', wraps=os.replace) as publish:
                self.assertEqual(store.clear_paused(), 1)
                self.assertEqual(publish.call_count, 1)
            self.assertEqual([item['id'] for item in store.list()], [active['id']])

    def test_busy_cleanup_preserves_previous_state_without_temporary_files(self):
        with self.private_store() as (helper, store):
            path = self.write_state(helper, store, self.item('a', enabled=False))
            previous = path.read_bytes()
            with store.locked():
                with self.assertRaisesRegex(helper.ReminderError, 'busy'):
                    store.clear_paused()
            self.assertEqual(path.read_bytes(), previous)
            self.assertEqual(sorted(item.name for item in store.directory.iterdir()),
                             sorted([helper.STATE_NAME, helper.LOCK_NAME]))

    def test_directory_replacement_cannot_move_lock_to_a_different_directory(self):
        with self.private_store() as (helper, store):
            path = self.write_state(helper, store, self.item('a', enabled=False))
            previous = path.read_bytes()
            original_locked = store.locked
            retired = store.directory.with_name('retired-calix')
            pinned = []

            @contextmanager
            def replace_directory(directory_fd=None):
                self.assertIsNotNone(directory_fd)
                pinned.append(directory_fd)
                store.directory.rename(retired)
                store.directory.mkdir(mode=0o700)
                with original_locked(directory_fd):
                    yield

            with original_locked(), mock.patch.object(store, 'locked', replace_directory):
                with self.assertRaisesRegex(helper.ReminderError, 'busy'):
                    store.list()
            self.assertEqual((retired / helper.STATE_NAME).read_bytes(), previous)
            self.assertEqual(list(store.directory.iterdir()), [])
            with self.assertRaises(OSError):
                os.fstat(pinned[0])

    def test_lock_inode_replacement_is_rejected_before_reading_state(self):
        with self.private_store() as (helper, store):
            path = self.write_state(helper, store, self.item('a', enabled=False))
            previous = path.read_bytes()
            original_flock = helper.fcntl.flock

            def replace_lock(fd, operation):
                original_flock(fd, operation)
                lock = store.directory / helper.LOCK_NAME
                lock.rename(lock.with_name('retired-lock'))
                lock.touch(mode=0o600)

            with mock.patch.object(helper.fcntl, 'flock', side_effect=replace_lock), \
                    mock.patch.object(store, '_read_unlocked', side_effect=AssertionError('state read')):
                with self.assertRaisesRegex(helper.ReminderError, 'lock changed'):
                    store.list()
            self.assertEqual(path.read_bytes(), previous)

    def test_replace_failure_retains_candidate_and_previous_state(self):
        with self.private_store() as (helper, store):
            path = self.write_state(helper, store, self.item('a', enabled=False))
            previous = path.read_bytes()
            with mock.patch.object(helper.os, 'replace', side_effect=OSError('injected replace failure')):
                with self.assertRaisesRegex(helper.ReminderError, 'publication is uncertain'):
                    store.clear_paused()
            self.assertEqual(path.read_bytes(), previous)
            retained = list(store.directory.glob('.' + helper.STATE_NAME + '.*.tmp'))
            self.assertEqual(len(retained), 1)
            self.assertEqual(stat.S_IMODE(retained[0].stat().st_mode), 0o600)
            self.assertEqual(json.loads(retained[0].read_text(encoding='utf-8'))['items'], {})

    def test_directory_sync_failure_reports_uncertain_published_result(self):
        with self.private_store() as (helper, store):
            path = self.write_state(helper, store, self.item('a', enabled=False))
            original_fsync = helper.os.fsync

            def fail_directory_sync(fd):
                if stat.S_ISDIR(os.fstat(fd).st_mode):
                    raise OSError('injected directory sync failure')
                original_fsync(fd)

            with mock.patch.object(helper.os, 'fsync', side_effect=fail_directory_sync):
                with self.assertRaisesRegex(helper.ReminderError, 'publication is uncertain'):
                    store.clear_paused()
            self.assertEqual(json.loads(path.read_text(encoding='utf-8'))['items'], {})

    def test_notification_option_like_text_stays_after_option_terminator(self):
        with self.private_store() as (helper, _store):
            item = self.item('a', enabled=True)
            item.update(title='--help', body='--expire-time=0')
            with mock.patch.object(helper.subprocess, 'run',
                                   return_value=SimpleNamespace(returncode=0)) as run:
                self.assertTrue(helper._notify(item))
            self.assertEqual(run.call_args.args[0], ['/usr/bin/notify-send', '-a', 'Labwc Reminders',
                             '-u', 'normal', '--', '--help', '--expire-time=0'])
            self.assertEqual(run.call_args.kwargs['timeout'], 15)


class LocalReminderDeliveryFixtures(unittest.TestCase):
    """Unexecuted durable-send cases; every state path stays in the private tree."""

    private_store = LocalReminderFailureFixtures.private_store
    item = staticmethod(LocalReminderFailureFixtures.item)
    write_state = staticmethod(LocalReminderFailureFixtures.write_state)

    def test_reserved_snapshot_is_not_replayed_by_a_second_worker(self):
        with self.private_store() as (helper, store):
            item = self.item('a', enabled=True)
            self.write_state(helper, store, item)
            self.assertEqual(store.reserve_delivery(item), 'reserved')
            restarted = helper.Store(store.home)
            self.assertIsNone(restarted.reserve_delivery(item))
            self.assertEqual(restarted.delivery_statuses(), {item['id']: 'reserved'})
            path = store.directory / helper.DELIVERY_NAME
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

    def test_acknowledgement_survives_interruption_before_state_advance(self):
        with self.private_store() as (helper, store):
            item = self.item('a', enabled=True)
            self.write_state(helper, store, item)
            store.reserve_delivery(item)
            store.record_delivery(item, 'accepted')
            restarted = helper.Store(store.home)
            self.assertEqual(restarted.reserve_delivery(item), 'accepted')
            self.assertTrue(restarted.advance(item, None))
            self.assertFalse(restarted.list()[0]['enabled'])

    def test_uncertain_receipt_is_retained_after_item_delete_and_other_sends(self):
        with self.private_store() as (helper, store):
            accepted, uncertain, fresh = [self.item(letter, enabled=True) for letter in 'abc']
            self.write_state(helper, store, accepted, uncertain, fresh)
            store.reserve_delivery(accepted)
            store.record_delivery(accepted, 'accepted')
            store.advance(accepted, None)
            store.reserve_delivery(uncertain)
            store.record_delivery(uncertain, 'outcome-unknown')
            store.mutate('delete', item_id=uncertain['id'])
            self.assertEqual(store.reserve_delivery(fresh), 'reserved')
            ledger = json.loads((store.directory / helper.DELIVERY_NAME).read_text(encoding='utf-8'))
            self.assertIn(helper._fingerprint(uncertain), ledger['items'])
            self.assertNotIn(helper._fingerprint(accepted), ledger['items'])

    def test_only_proven_exec_failure_can_retry_the_same_snapshot(self):
        with self.private_store() as (helper, store):
            item = self.item('a', enabled=True)
            self.write_state(helper, store, item)
            store.reserve_delivery(item)
            store.record_delivery(item, 'not-sent')
            self.assertEqual(store.reserve_delivery(item), 'reserved')
            store.record_delivery(item, 'outcome-unknown')
            self.assertIsNone(store.reserve_delivery(item))
            for failure, expected in ((FileNotFoundError(), False),
                                      (subprocess.TimeoutExpired(['fixture'], 1), None),
                                      (OSError('injected wait failure'), None)):
                with mock.patch.object(helper.subprocess, 'run', side_effect=failure):
                    self.assertIs(helper._notify(item), expected)
            with mock.patch.object(helper.subprocess, 'run', return_value=SimpleNamespace(returncode=1)):
                self.assertIsNone(helper._notify(item))

    def test_concurrent_edit_rejects_the_older_delivery_snapshot(self):
        with self.private_store() as (helper, store):
            item = self.item('a', enabled=True)
            self.write_state(helper, store, item)
            store.mutate('update', item={**item, 'title': 'New title'}, item_id=item['id'])
            self.assertIsNone(store.reserve_delivery(item))
            self.assertFalse((store.directory / helper.DELIVERY_NAME).exists())

    def test_failed_reservation_retains_evidence_and_blocks_later_mutations(self):
        with self.private_store() as (helper, store):
            item = self.item('a', enabled=True)
            state = self.write_state(helper, store, item)
            previous = state.read_bytes()
            with mock.patch.object(helper.os, 'replace', side_effect=OSError('injected reservation failure')):
                with self.assertRaises(helper.OutcomeUnknown) as caught:
                    store.reserve_delivery(item)
            self.assertEqual(state.read_bytes(), previous)
            self.assertTrue(caught.exception.recovery_path.is_file())
            with self.assertRaisesRegex(helper.OutcomeUnknown, 'unresolved'):
                store.set_all_enabled(False)
            self.assertEqual(state.read_bytes(), previous)

    def test_failed_ack_directory_sync_cannot_authorize_another_send(self):
        with self.private_store() as (helper, store):
            item = self.item('a', enabled=True)
            self.write_state(helper, store, item)
            store.reserve_delivery(item)
            original_fsync = helper.os.fsync

            def fail_directory(fd):
                if stat.S_ISDIR(os.fstat(fd).st_mode):
                    raise OSError('injected directory sync failure')
                original_fsync(fd)

            with mock.patch.object(helper.os, 'fsync', side_effect=fail_directory):
                with self.assertRaises(helper.OutcomeUnknown) as caught:
                    store.record_delivery(item, 'accepted')
            self.assertEqual(caught.exception.recovery_path, store.directory / helper.DELIVERY_NAME)
            self.assertEqual(store.reserve_delivery(item), 'accepted')

    def test_malformed_or_redirected_ledger_is_preserved_without_reset(self):
        with self.private_store() as (helper, store):
            item = self.item('a', enabled=True)
            state = self.write_state(helper, store, item)
            previous_state = state.read_bytes()
            path = store.directory / helper.DELIVERY_NAME
            for value in ({'version': True, 'items': {}},
                          {'version': 1, 'items': {helper._fingerprint(item): {'item': item, 'status': []}}}):
                raw = json.dumps(value).encode('utf-8')
                path.write_bytes(raw)
                path.chmod(0o600)
                with self.assertRaises(helper.ReminderError):
                    store.reserve_delivery(item)
                self.assertEqual(path.read_bytes(), raw)
                self.assertEqual(state.read_bytes(), previous_state)
            path.unlink()
            other = store.directory / 'fixture-owned-ledger'
            other.write_text('{"version":1,"items":{}}\n', encoding='utf-8')
            other.chmod(0o600)
            original = other.read_bytes()
            path.symlink_to(other.name)
            with self.assertRaises(OSError):
                store.reserve_delivery(item)
            self.assertEqual(other.read_bytes(), original)
            path.unlink()
            os.link(other, path)
            with self.assertRaises(helper.ReminderError):
                store.reserve_delivery(item)
            self.assertEqual(other.read_bytes(), original)

    def test_worker_finishes_an_acknowledged_attempt_without_notifying_again(self):
        with self.private_store() as (helper, _store):
            item = self.item('a', enabled=True)
            item.update(due='2000-01-01T00:00+00:00', allow_dnd=True)
            store = mock.Mock()
            store.list.return_value = [item]
            store.reserve_delivery.return_value = 'accepted'
            with mock.patch.object(helper, 'Store', return_value=store), \
                    mock.patch.object(helper, '_next_due', return_value=None), \
                    mock.patch.object(helper, '_notify') as notify, \
                    mock.patch.object(helper, 'datetime', wraps=helper.datetime) as clock, \
                    mock.patch.object(helper.time, 'sleep', side_effect=StopIteration):
                clock.now.return_value = clock.fromisoformat('2030-01-01T00:00+00:00')
                with self.assertRaises(StopIteration):
                    helper.run_worker()
            notify.assert_not_called()
            store.record_delivery.assert_not_called()
            store.advance.assert_called_once_with(item, None)

    def test_worker_does_not_send_when_reservation_publication_is_uncertain(self):
        with self.private_store() as (helper, fixture_store):
            item = self.item('a', enabled=True)
            item.update(due='2000-01-01T00:00+00:00', allow_dnd=True)
            store = mock.Mock()
            store.list.return_value = [item]
            store.reserve_delivery.side_effect = helper.OutcomeUnknown('injected reservation',
                                                                       fixture_store.directory)
            with mock.patch.object(helper, 'Store', return_value=store), \
                    mock.patch.object(helper, '_next_due', return_value=None), \
                    mock.patch.object(helper, 'datetime', wraps=helper.datetime) as clock, \
                    mock.patch.object(helper, '_notify') as notify:
                clock.now.return_value = clock.fromisoformat('2030-01-01T00:00+00:00')
                with self.assertRaises(helper.OutcomeUnknown):
                    helper.run_worker()
            notify.assert_not_called()

    def test_worker_reserves_before_send_and_records_before_advancing(self):
        with self.private_store() as (helper, _store):
            item = self.item('a', enabled=True)
            item.update(due='2000-01-01T00:00+00:00', allow_dnd=True)
            for result in (True, False, None):
                events = []
                store = mock.Mock()
                store.list.return_value = [item]
                store.reserve_delivery.side_effect = lambda value: events.append('reserve') or 'reserved'
                store.record_delivery.side_effect = lambda value, status: events.append(status)
                store.advance.side_effect = lambda value, next_due: events.append('advance')
                with mock.patch.object(helper, 'Store', return_value=store), \
                        mock.patch.object(helper, '_next_due', return_value=None), \
                        mock.patch.object(helper, '_notify', side_effect=lambda value: events.append('send') or result), \
                        mock.patch.object(helper, 'datetime', wraps=helper.datetime) as clock, \
                        mock.patch.object(helper.time, 'sleep', side_effect=StopIteration), \
                        redirect_stderr(io.StringIO()):
                    clock.now.return_value = clock.fromisoformat('2030-01-01T00:00+00:00')
                    with self.assertRaises(StopIteration):
                        helper.run_worker()
                status = 'accepted' if result is True else 'not-sent' if result is False else 'outcome-unknown'
                self.assertEqual(events, ['reserve', 'send', status] + (['advance'] if result is True else []))

    def test_ledger_authority_and_restart_prevention_are_staged(self):
        unit = target_text('etc/skel-desktop/.config/systemd/user/labwc-local-reminders.service')
        policy = target_text('etc/apparmor.d/calendars')
        self.assertIn('RestartPreventExitStatus=4', unit)
        self.assertEqual(policy.count('{local-reminder-deliveries.json,.local-reminder-deliveries.json.*.tmp} rwk,'), 2)


class LocalReminderCalendarFixtures(unittest.TestCase):
    """Unexecuted calendar cases with an in-memory TZif, never host tzdata."""

    private_store = LocalReminderFailureFixtures.private_store
    item = staticmethod(LocalReminderFailureFixtures.item)
    write_state = staticmethod(LocalReminderFailureFixtures.write_state)

    @staticmethod
    def stockholm_zone(helper):
        utc = helper.timezone.utc
        transitions = [int(helper.datetime(2026, 3, 29, 1, tzinfo=utc).timestamp()),
                       int(helper.datetime(2026, 10, 25, 1, tzinfo=utc).timestamp())]
        names = b'CET\0CEST\0'
        header = b'TZif\0' + b'\0' * 15 + struct.pack('>6I', 0, 0, 0, 2, 2, len(names))
        data = (header + struct.pack('>2i', *transitions) + b'\x01\x00'
                + struct.pack('>iBB', 3600, 0, 0) + struct.pack('>iBB', 7200, 1, 4) + names)
        return helper.ZoneInfo.from_file(io.BytesIO(data), key='Fixture/Stockholm')

    def test_daily_recurrence_preserves_civil_time_across_both_dst_changes(self):
        with self.private_store() as (helper, _store):
            zone = self.stockholm_zone(helper)
            with mock.patch.object(helper, 'ZoneInfo', return_value=zone):
                for current, expected in [('2026-03-28T09:00+01:00', '2026-03-29T09:00:00+02:00'),
                                          ('2026-10-24T09:00+02:00', '2026-10-25T09:00:00+01:00')]:
                    result = helper._next_due(helper.datetime.fromisoformat(current), 'daily', 'Fixture/Stockholm')
                    self.assertEqual(result.isoformat(), expected)

    def test_nonexistent_initial_time_is_rejected_and_recurring_gap_is_omitted(self):
        with self.private_store() as (helper, _store):
            zone = self.stockholm_zone(helper)
            with mock.patch.object(helper, 'ZoneInfo', return_value=zone):
                with self.assertRaisesRegex(helper.ReminderError, 'does not exist'):
                    helper.localize(helper.datetime(2026, 3, 29, 2, 30), 'Fixture/Stockholm')
                result = helper._next_due(helper.datetime.fromisoformat('2026-03-28T02:30+01:00'),
                                          'daily', 'Fixture/Stockholm')
                self.assertEqual(result.isoformat(), '2026-03-30T02:30:00+02:00')
                folded = helper.localize(helper.datetime(2026, 10, 25, 2, 30), 'Fixture/Stockholm')
                self.assertEqual(folded.isoformat(), '2026-10-25T02:30:00+02:00')

    def test_invalid_month_days_and_leap_years_keep_the_original_calendar_day(self):
        with self.private_store() as (helper, _store):
            with mock.patch.object(helper, 'ZoneInfo', return_value=helper.timezone.utc):
                for current, recurrence, expected in [
                        ('2026-01-31T09:00+00:00', 'monthly', '2026-03-31T09:00:00+00:00'),
                        ('2026-01-31T09:00+00:00', 'quarterly', '2026-07-31T09:00:00+00:00'),
                        ('2024-02-29T09:00+00:00', 'yearly', '2028-02-29T09:00:00+00:00')]:
                    result = helper._next_due(helper.datetime.fromisoformat(current), recurrence, 'UTC')
                    self.assertEqual(result.isoformat(), expected)

    def test_catchup_jumps_to_the_horizon_with_a_bounded_candidate_range(self):
        with self.private_store() as (helper, _store):
            ranges = []

            def bounded_range(start, stop):
                self.assertLessEqual(stop - start, 366)
                ranges.append((start, stop))
                return range(start, stop)

            with mock.patch.object(helper, 'ZoneInfo', return_value=helper.timezone.utc), \
                    mock.patch.object(helper, 'range', bounded_range, create=True):
                result = helper._next_due(helper.datetime.fromisoformat('1600-01-31T09:00+00:00'),
                                          'monthly', 'UTC',
                                          after=helper.datetime.fromisoformat('2030-02-01T00:00+00:00'))
            self.assertEqual(result.isoformat(), '2030-03-31T09:00:00+00:00')
            self.assertEqual(len(ranges), 1)

    def test_linked_upsert_is_one_locked_operation_and_keeps_event_anchor_and_identity(self):
        with self.private_store() as (helper, store):
            link = {'uid': 'fixture-event', 'url': 'https://dav.fruux.com/cal/fixture.ics', 'kind': 'VEVENT'}
            fields = {'summary': 'Fixture event', 'start': '2030-03-01T00:10+00:00',
                      'timezone': 'UTC', 'recurrence': 'monthly'}
            preference = {'enabled': True, 'first_minutes': 30}
            with mock.patch.object(store, 'list', side_effect=AssertionError('stale public read')), \
                    mock.patch.object(store, 'mutate', side_effect=AssertionError('separate writer lock')), \
                    mock.patch.object(store, '_session', wraps=store._session) as session:
                store.sync_remote(link, fields, preference)
                self.assertEqual(session.call_count, 1)
            first = store.list()[0]
            self.assertEqual(first['due'], fields['start'])
            self.assertEqual(first['first_minutes'], 30)
            store.sync_remote(link, {**fields, 'summary': 'Updated event'}, {**preference, 'first_minutes': 180})
            second = store.list()
            self.assertEqual(len(second), 1)
            self.assertEqual(second[0]['id'], first['id'])
            self.assertEqual(second[0]['created'], first['created'])
            self.assertEqual(second[0]['first_minutes'], 180)

    def test_link_removal_preserves_a_rebound_identity_and_other_links(self):
        with self.private_store() as (helper, store):
            selected = {'uid': 'a', 'url': 'https://dav.fruux.com/cal/a.ics', 'kind': 'VEVENT'}
            other = {'uid': 'b', 'url': 'https://dav.fruux.com/cal/b.ics', 'kind': 'VEVENT'}
            changed = {**self.item('a', enabled=True), 'link': other}
            owned = {**self.item('b', enabled=True), 'link': selected}
            self.write_state(helper, store, changed, owned)
            with mock.patch.object(store, 'list', side_effect=AssertionError('stale public read')), \
                    mock.patch.object(store, 'mutate', side_effect=AssertionError('separate writer lock')):
                store.remove_link(selected)
            self.assertEqual([item['id'] for item in store.list()], [changed['id']])

    def test_due_order_uses_utc_instants_instead_of_offset_strings(self):
        with self.private_store() as (helper, store):
            early = {**self.item('a', enabled=True), 'due': '2030-01-02T09:00+02:00'}
            late = {**self.item('b', enabled=True), 'due': '2030-01-02T08:30+00:00'}
            self.write_state(helper, store, early, late)
            self.assertEqual([item['id'] for item in store.list()], [early['id'], late['id']])


class ReminderActivationFixtures(unittest.TestCase):
    """Unexecuted activation logic with no GTK, bus, store or child processes."""

    def setUp(self):
        source = target_source('usr/local/lib/python3/dist-packages/labwc_calendar_reminders_gtk.py')
        rendered = target_text('usr/local/lib/python3/dist-packages/labwc_calendar_reminders_gtk.py')
        environment = mock.patch.dict(os.environ, {}, clear=True)
        environment.start()
        self.addCleanup(environment.stop)
        commands = mock.patch.object(subprocess, 'run', side_effect=AssertionError('external command'))
        commands.start()
        self.addCleanup(commands.stop)
        self.tree = ast.parse(rendered, filename=str(source))
        main = next(node for node in self.tree.body
                    if isinstance(node, ast.FunctionDef) and node.name == 'main')
        self.classes = {node.name: node for node in main.body if isinstance(node, ast.ClassDef)}
        self.source = source

    def application(self):
        class Application:
            def __init__(self, **options):
                self.options = options
                self.signals = {}

            def connect(self, name, callback):
                self.signals[name] = callback

        created = {'manager': [], 'new': []}

        def window(kind):
            def create(_application):
                result = SimpleNamespace(present=mock.Mock(), apply_action=mock.Mock(return_value=0))
                created[kind].append(result)
                return result
            return create

        error = type('ReminderFixtureError', (Exception,), {})
        unknown = type('ReminderFixtureOutcomeUnknown', (error,), {})
        namespace = {'Gtk': SimpleNamespace(Application=Application),
                     'Gio': SimpleNamespace(ApplicationFlags=SimpleNamespace(HANDLES_COMMAND_LINE=8)),
                     'local': SimpleNamespace(ReminderError=error, OutcomeUnknown=unknown),
                     'phone': SimpleNamespace(ReminderError=error),
                     'ManagerWindow': window('manager'), 'ReminderWindow': window('new')}
        nodes = [node for node in self.tree.body
                 if (isinstance(node, ast.FunctionDef)
                     and node.name in {'_request', 'notification_text', 'failure_status'})
                 or (isinstance(node, ast.Assign) and any(isinstance(target, ast.Name)
                     and target.id == 'MANAGER_ACTIONS' for target in node.targets))]
        nodes.append(self.classes['ReminderApplication'])
        exec(compile(ast.Module(body=nodes, type_ignores=[]), str(self.source), 'exec'), namespace)
        return namespace['ReminderApplication'](), created

    @staticmethod
    def command(*arguments):
        return SimpleNamespace(get_arguments=lambda: ['fixture-reminders', *arguments],
                               printerr_literal=mock.Mock())

    def test_later_launches_forward_mode_and_action_without_losing_editor(self):
        application, created = self.application()
        self.assertEqual(application.options['flags'], 8)
        self.assertEqual(application.do_command_line(self.command('manager', 'upcoming')), 0)
        manager = created['manager'][0]
        self.assertEqual(application.do_command_line(self.command('new')), 0)
        editor = created['new'][0]
        editor.unsaved_draft = 'must survive'
        self.assertEqual(application.do_command_line(self.command('manager', 'pause-local')), 0)
        self.assertEqual(manager.apply_action.call_args_list,
                         [mock.call('upcoming'), mock.call('pause-local')])
        self.assertEqual(len(created['manager']), 1)
        self.assertEqual(len(created['new']), 1)
        self.assertEqual(editor.unsaved_draft, 'must survive')

    def test_removed_manager_is_recreated_while_editor_remains_open(self):
        application, created = self.application()
        application.do_command_line(self.command('manager'))
        application.do_command_line(self.command('new'))
        removed = created['manager'][0]
        application.signals['window-removed'](application, removed)
        application.do_command_line(self.command('manager', 'overdue'))
        self.assertEqual(len(created['manager']), 2)
        self.assertIs(application.new_window, created['new'][0])
        self.assertIsNot(application.manager_window, removed)

    def test_invalid_forwarded_requests_are_rejected_before_window_or_store_access(self):
        for arguments in ((), ('unknown',), ('new', 'pause-local'),
                          ('manager', 'unsupported'), ('manager', 'upcoming', 'extra')):
            application, created = self.application()
            command = self.command(*arguments)
            self.assertEqual(application.do_command_line(command), 1)
            self.assertEqual(created, {'manager': [], 'new': []})
            command.printerr_literal.assert_called_once()

    def test_failed_forwarded_action_preserves_result_without_retry(self):
        application, created = self.application()
        application.do_command_line(self.command('manager'))
        action = created['manager'][0].apply_action
        action.reset_mock(return_value=True)
        action.return_value = 1
        self.assertEqual(application.do_command_line(self.command('manager', 'resume-local')), 1)
        action.assert_called_once_with('resume-local')

    def test_uncertain_local_or_phone_publication_returns_four_without_retry(self):
        for source in ('local', 'phone'):
            application, created = self.application()
            application.do_command_line(self.command('manager'))
            namespace = application.do_command_line.__func__.__globals__
            error_type = (namespace['local'].OutcomeUnknown if source == 'local'
                          else namespace['phone'].ReminderError)
            error = error_type('injected unknown publication')
            error.code = 'reminder-state-unknown'
            operation = created['manager'][0].apply_action
            operation.reset_mock()
            operation.side_effect = error
            self.assertEqual(application.do_command_line(self.command('manager', 'pause-local')), 4)
            operation.assert_called_once_with('pause-local')

    def test_manager_reconfigures_filters_buttons_and_operation_result(self):
        method = next(node for node in self.classes['ManagerWindow'].body
                      if isinstance(node, ast.FunctionDef) and node.name == 'apply_action')
        namespace = {}
        exec(compile(ast.Module(body=[method], type_ignores=[]), str(self.source), 'exec'), namespace)
        manager = SimpleNamespace(selected_button=mock.Mock(), expired_button=mock.Mock(),
                                  refresh=mock.Mock(), apply_bulk_action=mock.Mock(return_value=1),
                                  clear_expired=mock.Mock(return_value=1))
        apply = namespace['apply_action']
        self.assertEqual(apply(manager, 'overdue'), 0)
        self.assertEqual(manager.view, 'overdue')
        self.assertIsNone(manager.selected_action)
        self.assertEqual(apply(manager, 'edit-selected'), 0)
        self.assertEqual(manager.view, 'all')
        self.assertEqual(manager.selected_action, 'edit-selected')
        manager.selected_button.set_label.assert_called_with('Edit selected')
        manager.selected_button.set_visible.assert_called_with(True)
        self.assertEqual(apply(manager, 'resume-phone'), 1)
        manager.apply_bulk_action.assert_called_once_with('resume-phone')
        self.assertEqual(apply(manager, 'clear-expired'), 1)
        manager.clear_expired.assert_called_once_with()
