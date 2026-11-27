#!/usr/bin/python3 -IB
"""Explicit contract cases for a disposable, offline QEMU guest only.

The serializer installs this file at /validation/cases.py. No host discovery,
test-runner import, service manager, network or hardware passthrough is used.
Policy reloads and systemd responses are injected; APT and the offline policy
compiler are real guest binaries. These cases do not prove GPU presentation.
"""
from pathlib import Path

if Path(__file__).resolve() != Path('/validation/cases.py'):
    raise SystemExit('REFUSED: package this fixture into its reviewed private guest')
if 'findings_fixture=20261124' not in Path('/proc/cmdline').read_text(encoding='ascii'):
    raise SystemExit('REFUSED: guest identity marker is missing')

import ast
import argparse
import configparser
import contextlib
import fcntl
import hashlib
import importlib.util
import io
import json
import os
import re
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import traceback
import types
from unittest import mock

ROOT = Path('/validation')
SOURCE = ROOT / 'source/d-i/debian'
TARGET = SOURCE / 'hooks/target'
WORK = ROOT / 'work'
WORK.mkdir(mode=0o755)
ROOT.chmod(0o755)  # Only the private guest's later unprivileged DAC case.
os.umask(0o022)
ENV = {'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'HOME': '/validation/home',
       'TMPDIR': '/validation/tmp', 'TMP': '/validation/tmp', 'TEMP': '/validation/tmp',
       'LC_ALL': 'C', 'PYTHONDONTWRITEBYTECODE': '1'}
os.environ.clear()
os.environ.update(ENV)


def canonical_paths():
    values = {}
    for line in (SOURCE / 'hosts/installer/runtime.env').read_text(encoding='utf-8').splitlines():
        match = re.fullmatch(r'((?:DIR_|FILE_)[A-Z0-9_]+)="([^"\n]*)"', line)
        if match is None:
            continue
        names = re.findall(r'\$\{([A-Z0-9_]+)\}', match[2])
        if any(name not in values for name in names):
            continue
        value = re.sub(r'\$\{([A-Z0-9_]+)\}', lambda m: values[m[1]], match[2])
        if '$' in value or '`' in value:
            raise ValueError('unsupported fixture path data')
        values[match[1]] = value
    tokens = {}
    for line in (SOURCE / 'catalog/runtime-paths.tsv').read_text(encoding='utf-8').splitlines():
        if line and not line.startswith('#'):
            token, variable = line.split('\t')
            if variable in values:
                tokens['__INSTALLER_' + token + '__'] = values[variable]
    return tokens


PATHS = canonical_paths()


def render(text):
    for key, value in PATHS.items():
        text = text.replace(key, value)
    text = text.replace('__INSTALLER_LABWC_MANAGED_APP_DEFAULT_EXEC__', '/usr/local/bin/labwc-app nvidia')
    # Appearance fields are data only; never execute a renderer or shell.
    text = re.sub(r'__THEME_TARGET_PATH_[A-Z0-9_]+__', '/usr/share/fixture/theme', text)
    text = re.sub(r'__THEME_[A-Z0-9_]+__', 'fixture-icon', text)
    return text


def load(name, path, *, only_definitions=False):
    text = render(path.read_text(encoding='utf-8'))
    tree = ast.parse(text, filename=str(path))
    if only_definitions:
        tree.body = [node for node in tree.body if isinstance(node, (
            ast.Import, ast.ImportFrom, ast.FunctionDef, ast.ClassDef, ast.Assign, ast.AnnAssign))]
    module = types.ModuleType(name)
    module.__file__ = str(path)
    sys.modules[name] = module
    exec(compile(tree, str(path), 'exec'), module.__dict__)
    return module


def raises(kind, function, *args, **kwargs):
    try:
        function(*args, **kwargs)
    except kind:
        return
    raise AssertionError('expected ' + str(kind))


def firstboot():
    text = (SOURCE / 'scripts/firstboot/04-validation.sh.tmpl').read_text(encoding='utf-8')
    body = text.split('validate_selected_unit_states() {', 1)[1].split("<<'PY'\n", 1)[1].split('\nPY\n}', 1)[0]
    path = WORK / 'firstboot.py'
    path.write_text(body, encoding='utf-8')
    module = load('fixture_firstboot', path, only_definitions=True)
    def record(**extra):
        result = {'Names': (), 'LoadState': 'loaded', 'ActiveState': 'inactive', 'SubState': 'dead',
                  'Result': 'success', 'Type': 'exec', 'ExecMainCode': '1', 'ExecMainStatus': '0',
                  'ExecMainStartTimestampMonotonic': '100', 'ExecMainExitTimestampMonotonic': '200'}
        result.update(extra)
        return result
    greeter = {'greetd.service': record(ActiveState='active', TTYPath='/dev/tty1', Conflicts=('getty@tty1.service',))}
    assert module.classify('getty@tty1.service', record(), greeter)[0] == 'expected'
    assert module.classify('getty@tty2.service', record(), greeter)[0] == 'failed'
    assert module.classify('getty@tty1.service', record(), {})[0] == 'failed'
    related = {'firewalld.service': record(LoadState='not-found'),
               'nftables.service': record(ActiveState='active')}
    listener = record(PartOf=('firewalld.service',), WantedBy=('firewalld.service',))
    assert module.classify('netavark-firewalld-reload.service', listener, related)[0] == 'expected'
    related['nftables.service']['ActiveState'] = 'failed'
    assert module.classify('netavark-firewalld-reload.service', listener, related)[0] == 'failed'
    for value, status in [('manual-auth-required', 'expected'), ('bootstrap-succeeded', 'verified'),
                          ('already-joined', 'verified'), ('unknown', 'failed')]:
        receipt = {'TAILSCALE_BOOTSTRAPPED': 'true' if status == 'verified' else 'false', 'TAILSCALE_STATUS': value}
        with mock.patch.object(module, 'task_receipt', return_value=receipt):
            assert module.classify('tailscale-bootstrap.service', record(), {})[0] == status
            assert module.classify('rsyslog.service', record(), {})[0] == 'failed'
    with mock.patch.object(module, 'task_receipt', side_effect=FileNotFoundError):
        assert module.classify('tailscale-bootstrap.service', record(), {})[0] == 'failed'
    with mock.patch.object(module, 'task_receipt', side_effect=PermissionError):
        state, reason = module.classify('tailscale-bootstrap.service', record(), {})
        assert state == 'failed' and reason == 'finite-task-receipt-inaccessible'
    with mock.patch.object(module, 'task_receipt', return_value={'TAILSCALE_BOOTSTRAPPED': 'false',
                           'TAILSCALE_STATUS': 'pending-machine-approval'}):
        assert module.classify('tailscale-bootstrap.service', record(ActiveState='activating',
                              SubState='auto-restart', ExecMainStatus='75'), {})[0] == 'expected'
        assert module.classify('tailscale-bootstrap.service', record(ExecMainStatus='75'), {})[0] == 'failed'
    for name in module.STRICT:
        assert module.classify(name, record(Result='exit-code'), {})[0] == 'failed'
    return {'injected_systemd': True, 'live_manager_contacted': False}


def managed_modules():
    root = WORK / 'python'
    package = root / 'labwc_managed_app'
    package.mkdir(parents=True)
    source = TARGET / 'usr/local/lib/desktop/python3/dist-packages/labwc_managed_app'
    for path in source.iterdir():
        if path.is_file() and (path.name.endswith('.py') or path.name.endswith('.py.tmpl')):
            (package / path.name.removesuffix('.tmpl')).write_text(render(path.read_text(encoding='utf-8')), encoding='utf-8')
    sys.path.insert(0, str(root))
    from labwc_managed_app import gpu, runtime
    # Exercise the exact close classifier without importing an application
    # catalog whose constructors require installed target policy files.
    tree = ast.parse(render((source / 'generic.py').read_text(encoding='utf-8')))
    classifier = next(node for node in tree.body if isinstance(node, ast.FunctionDef)
                      and node.name == 'foot_window_close_is_expected')
    generic = types.ModuleType('fixture_foot_classifier')
    generic.WAYBAR_STATE_ID = re.compile(r'[0-9a-f]{32}')
    exec(compile(ast.Module(body=[classifier], type_ignores=[]), 'generic.py', 'exec'), generic.__dict__)
    return gpu, runtime, generic


def process_gpu():
    gpu, runtime, generic = managed_modules()
    for value in (0, 1, 124, 137, 247):
        assert runtime.executable_status(value) == value
    for raw, expected in ((-9, 137), (-15, 143), (-1, 129)):
        stream = io.StringIO()
        with contextlib.redirect_stderr(stream):
            assert runtime.executable_status(raw) == expected
        assert f'signal={-raw}' in stream.getvalue()
    assert generic.foot_window_close_is_expected(['/usr/bin/foot', '-e', '/usr/local/bin/nmtui'], {})
    for arguments in (['/usr/bin/foot', '-e', '/usr/local/bin/nmtui', 'extra'],
                      ['/usr/bin/foot', '-e', '/usr/bin/false'], ['/usr/bin/foot', '-e', 'nmtui']):
        assert not generic.foot_window_close_is_expected(arguments, {})
    # The GPU selector class is immutable identity data; no real device opens.
    selection = gpu.Selection('nvidia', '0000:2d:00.0', Path('/dev/dri/renderD129'), ())
    command = selection.chromium_arguments(['/opt/vivaldi/vivaldi-bin', '--render-node-override=/dev/dri/renderD128',
                                              '--hardware-video-device-path', '/dev/dri/renderD128', '--', '--render-node-override=data'])
    assert command[1:3] == ['--render-node-override=/dev/dri/renderD129', '--hardware-video-device-path=/dev/dri/renderD129'], command
    assert command[-2:] == ['--', '--render-node-override=data']
    raises((ValueError, SystemExit), selection.chromium_arguments, ['/usr/bin/chromium', '--render-node-override'])
    assert '--disable-gpu' not in runtime.MANAGED_NATIVE_OPENGL_ENVIRONMENT['QTWEBENGINE_CHROMIUM_FLAGS']
    assert '--disable-gpu' in runtime.MANAGED_NO_VULKAN_ENVIRONMENT['QTWEBENGINE_CHROMIUM_FLAGS']
    for vendor, node in (('intel', 'renderD128'), ('nvidia', 'renderD129')):
        chosen = gpu.Selection(vendor, '0000:00:02.0' if vendor == 'intel' else '0000:2d:00.0',
                               Path('/dev/dri') / node, ())
        environment = dict(runtime.MANAGED_NATIVE_OPENGL_ENVIRONMENT,
                           NVD_DRM_DEVICE='/dev/dri/stale', DRI_PRIME='stale')
        chosen.apply_environment(environment)
        assert environment['MOZ_DRM_DEVICE'] == '/dev/dri/' + node
        assert 'NVD_DRM_DEVICE' not in environment
        assert '--render-node-override=/dev/dri/' + node in environment['QTWEBENGINE_CHROMIUM_FLAGS']
        assert '--disable-gpu' not in environment['QTWEBENGINE_CHROMIUM_FLAGS']
    return {'signals_decoded_at_adapter': True, 'gpu_identity_fixture': True, 'gpu_hardware_opened': False}


def profile_modes():
    source = TARGET / 'usr/local/lib/desktop/python3/dist-packages/labwc_managed_app'
    from labwc_managed_app import runtime
    module = types.ModuleType('fixture_profile_modes')
    module.__dict__.update(runtime.__dict__)
    module.__dict__.update(pathlib=__import__('pathlib'), shlex=shlex, stat=stat)
    wanted = {'_read_validated_text', 'load_managed_defaults', 'acceleration_availability_from_defaults',
              'load_managed_launch_policy', 'validate_acceleration_mode'}
    tree = ast.parse(render((source / 'environment.py').read_text(encoding='utf-8')))
    nodes = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name in wanted]
    nodes += [node for node in tree.body if isinstance(node, ast.Assign)
              and any(isinstance(target, ast.Name) and target.id == 'MANAGED_DEFAULT_EXEC_MODES' for target in node.targets)]
    exec(compile(ast.Module(body=nodes, type_ignores=[]), 'environment.py', 'exec'), module.__dict__)
    defaults = WORK / 'profile-modes.conf'
    generic_tree = ast.parse(render((source / 'generic.py').read_text(encoding='utf-8')))
    generic_main = next(node for node in generic_tree.body if isinstance(node, ast.FunctionDef) and node.name == 'main')
    generic = types.ModuleType('fixture_generic_modes')
    generic.__dict__.update(module.__dict__)
    wrappers = {'wayland': '/usr/local/bin/labwc-wayland-app', 'electron': '/usr/local/bin/labwc-electron-app'}
    generic.__dict__.update(argparse=argparse, WRAPPERS=wrappers, MANAGED_DEFAULTS_PATH=defaults,
                            system_owner=lambda: (0, 0), diagnostics=types.SimpleNamespace(apply=lambda _env: None),
                            session_environment=lambda: {'PATH': '/usr/bin:/bin'})
    class Resolved(Exception):
        pass
    seen = []
    generic.validate_acceleration_mode = lambda mode, available: seen.append(mode)
    generic.unwrap_env = lambda *_args: (_ for _ in ()).throw(Resolved())
    exec(compile(ast.Module(body=[generic_main], type_ignores=[]), 'generic.py', 'exec'), generic.__dict__)
    combinations = 0
    for managed, wayland, electron in (('nvidia', 'nvidia', 'nvidia'), ('intel', 'intel', 'intel'),
                                       ('nvidia', 'intel', 'nvidia'), ('intel', 'nvidia', 'intel')):
        values = {'managed': managed, 'wayland': wayland, 'electron': electron}
        defaults.write_text('\n'.join('LABWC_' + kind.upper() + '_APP_DEFAULT_EXEC="/usr/local/bin/labwc-'
                           + ('app' if kind == 'managed' else kind + '-app') + ' ' + mode + '"'
                           for kind, mode in values.items()) + '\nLABWC_INTEL_ACCELERATION_AVAILABLE=true\n'
                           'LABWC_NVIDIA_ACCELERATION_AVAILABLE=true\n', encoding='ascii')
        assert module.load_managed_launch_policy(defaults)[1] == managed
        for kind in wrappers:
            for requested in ('auto', 'intel', 'nvidia'):
                with mock.patch.object(os, 'geteuid', return_value=1000):
                    raises(Resolved, generic.main, kind, [requested, '--', '/usr/bin/fixture'])
                assert seen[-1] == (values[kind] if requested == 'auto' else requested)
                combinations += 1
    return {'real_private_defaults_file': True, 'generic_mode_cases': combinations,
            'managed_default_cases': 4, 'service_and_gpu_calls_replaced': True}


def dock_namespace():
    home = WORK / 'dock-account'
    home.mkdir(mode=0o700)
    for leaf in ('applications', 'managed-applications', 'Downloads'):
        directory = home / leaf
        directory.mkdir(mode=0o700)
        os.chown(directory, 1000, 1000)
    vendor = home / 'applications/fixture.desktop'
    managed = home / 'managed-applications/fixture.desktop'
    vendor.write_text('Exec=/usr/bin/vendor\n', encoding='ascii')
    managed.write_text('Exec=/usr/local/bin/labwc-app nvidia vivaldi\n', encoding='ascii')
    for path in (home, vendor, managed):
        os.chown(path, 1000, 1000)
    code = r'''
import ctypes, errno, os
from pathlib import Path
home = Path(os.environ['HOME'])
os.setgroups([])
os.setgid(1000)
os.setuid(1000)
libc = ctypes.CDLL(None, use_errno=True)
# A normal desktop-user exec is dumpable; setuid in this guest probe resets
# that flag and would make /proc/self mapping files belong to root instead.
if libc.prctl(4, 1, 0, 0, 0):
    raise OSError(ctypes.get_errno(), 'private guest credential transition')
if libc.unshare(0x10000000 | 0x00020000):
    raise OSError(ctypes.get_errno(), 'private guest user/mount namespace')
Path('/proc/self/setgroups').write_text('deny')
Path('/proc/self/uid_map').write_text('1000 1000 1\n')
Path('/proc/self/gid_map').write_text('1000 1000 1\n')
assert os.getuid() == 1000
assert Path('/usr').stat().st_uid == 65534
source, destination = home / 'managed-applications', home / 'applications'
if libc.mount(bytes(source), bytes(destination), None, 4096, None):
    raise OSError(ctypes.get_errno(), 'private guest bind')
if libc.mount(None, bytes(destination), None, 4096 | 32 | 1 | 2 | 4, None):
    raise OSError(ctypes.get_errno(), 'private guest read-only remount')
assert 'labwc-app nvidia' in (destination / 'fixture.desktop').read_text()
try:
    (destination / 'fixture.desktop').write_text('forbidden')
except OSError as error:
    assert error.errno == errno.EROFS
else:
    raise AssertionError('dock view was writable')
(home / 'Downloads/persistent.txt').write_text('same account, persistent path\n')
'''
    result = subprocess.run(['/usr/bin/python3.14', '-I', '-B', '-c', code],
                            env=dict(ENV, HOME=str(home)), capture_output=True, timeout=15)
    assert result.returncode == 0, result.stderr
    assert vendor.read_text(encoding='ascii') == 'Exec=/usr/bin/vendor\n'
    downloaded = home / 'Downloads/persistent.txt'
    assert downloaded.stat().st_uid == 1000
    assert downloaded.read_text(encoding='ascii') == 'same account, persistent path\n'
    return {'real_guest_user_and_mount_namespaces': True, 'desktop_uid_preserved': 1000,
            'download_persisted_outside_namespace': True, 'systemd_and_dock_ui_executed': False}


def menu_icons():
    tree = ast.parse(render((TARGET / 'usr/local/libexec/desktop/labwc-waybar-menu').read_text(encoding='utf-8')))
    popup = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == 'Popup')
    method = next(node for node in popup.body if isinstance(node, ast.FunctionDef) and node.name == 'populate_icons')
    class Image:
        def __init__(self): self.hidden = False
        def clear(self): pass
        def set_no_show_all(self, value): pass
        def hide(self): self.hidden = True
    class LoaderError(Exception): pass
    class Theme:
        def load_icon(self, *_args): raise LoaderError('injected Glycin denial')
        def connect(self, *_args): pass
    theme = Theme()
    namespace = {'diagnostic': lambda *_args: None}
    exec(compile(ast.Module(body=[method], type_ignores=[]), 'menu-icons', 'exec'), namespace)
    owner = types.SimpleNamespace(Gtk=types.SimpleNamespace(Image=Image,
                 IconTheme=types.SimpleNamespace(get_default=lambda: theme),
                 IconLookupFlags=types.SimpleNamespace(FORCE_SIZE=0)),
                 GLib=types.SimpleNamespace(Error=LoaderError))
    images = {'first': Image(), 'second': Image()}
    builder = types.SimpleNamespace(get_object=images.get)
    namespace['populate_icons'](owner, builder, [('first', 'one', 16), ('second', 'two', 16)])
    assert all(image.hidden for image in images.values())
    return {'gtk_and_glycin_errors_injected': True, 'preflight_failure_keeps_text_menu': True}


def desktop_actions():
    module = load('fixture_desktop_policy', TARGET / 'usr/local/libexec/desktop/labwc-wrap-desktop-files')
    prefix = '/usr/local/bin/labwc-wayland-app nvidia'
    samples = [
        ('vivaldi-stable.desktop', '/usr/bin/vivaldi-stable %U', 'vivaldi'),
        ('chromium.desktop', '/usr/bin/chromium %U', 'chromium'),
        ('org.qbittorrent.qBittorrent.desktop', '/usr/bin/qbittorrent %U', 'qbittorrent'),
        ('unknown.desktop', 'env EXAMPLE="two words" "/opt/Example App/gui" --name="literal value" %F', None),
    ]
    samples.extend((config['desktop_names'][0], ('/opt/vendor/gui ' + config['field_code']).rstrip(), config['action_app'])
                   for config in module.APP_CONFIG if config['action_app'] not in {'discord', 'zoom'})
    for name, command, app in samples:
        original = ('[Desktop Entry]\nType=Application\nName=Fixture\nTerminal=false\n'
                    'Exec=' + command + '\nActions=VendorAction;\nDBusActivatable=true\n'
                    '[Desktop Action VendorAction]\nName=Raw vendor action\nExec=/usr/bin/false\n')
        result = module.rewrite_desktop(original, prefix, name=name, managed_default='/usr/local/bin/labwc-app nvidia')
        assert module.rewrite_desktop(result, prefix, name=name,
                                      managed_default='/usr/local/bin/labwc-app nvidia') == result
        parser = configparser.ConfigParser(interpolation=None)
        parser.optionxform = str
        parser.read_string(result)
        assert parser['Desktop Entry']['Exec'] == command, (name, command, parser['Desktop Entry']['Exec'])
        assert parser['Desktop Entry']['DBusActivatable'] == 'false'
        for action, mode in (('IntelAccelerated', 'intel'), ('NvidiaAccelerated', 'nvidia')):
            section = parser['Desktop Action ' + action]
            assert section['Name'] == action
            assert mode in section['Exec']
        assert not parser.has_section('Desktop Action VendorAction')
        path = WORK / 'fixture.desktop'
        path.write_text(result, encoding='utf-8')
        status = subprocess.run(['/usr/bin/desktop-file-validate', str(path)], env=ENV, capture_output=True, timeout=5)
        assert status.returncode == 0, (name, status.stderr, status.stdout)
    for name, vendor in (('Zoom.desktop', '/usr/bin/zoom --url=%U'), ('discord.desktop', '/opt/discord/Discord %U')):
        result = module.rewrite_desktop('[Desktop Entry]\nType=Application\nName=Private compatibility\nExec=' + vendor + '\n', prefix, name=name)
        assert 'Exec=/usr/local/bin/' + ('zoom' if name == 'Zoom.desktop' else 'discord') in result
        assert 'labwc-wayland-compat-app intel' in result
    # Read-only package classification and publication are injected, never dpkg
    # or a target management command executed by this fixture case.
    source = WORK / 'desktop-vendor'; output = WORK / 'desktop-output'; state = WORK / 'desktop-state'
    for path in (source, output, state): path.mkdir(mode=0o755)
    vendor = source / 'fixture.desktop'
    vendor.write_text('[Desktop Entry]\nName=Fixture\nType=Application\nExec=/usr/bin/fixture %U\n', encoding='utf-8')
    module.APPLICATION_DIRS = (source,)
    module.OUTPUT_DIR = output
    module.STATE_DIR = state
    module.MANIFEST = state / 'overrides.json'
    module.PENDING = state / 'pending.json'
    module.DATABASE_DIRTY = state / 'database-dirty'
    module.package_for = lambda _path: 'fixture'
    module.is_electron = lambda _package: False
    module.acceleration_actions = lambda: ('IntelAccelerated', 'NvidiaAccelerated')
    defaults = {'managed': '/usr/local/bin/labwc-app nvidia', 'wayland': prefix,
                'electron': '/usr/local/bin/labwc-electron-app nvidia'}
    assert module.generate_overrides(defaults)
    first = (output / 'fixture.desktop').read_bytes()
    assert not module.generate_overrides(defaults)
    assert (output / 'fixture.desktop').read_bytes() == first
    (output / 'fixture.desktop').write_text('[Desktop Entry]\nType=Application\nName=Administrator\nExec=/usr/bin/custom\n', encoding='utf-8')
    assert not module.generate_overrides(defaults)
    assert 'Administrator' in (output / 'fixture.desktop').read_text(encoding='utf-8')
    account = load('fixture_account_launchers', TARGET / 'usr/local/bin/desktop/labwc-sync-application-launchers.tmpl')
    account.desktop_policy = lambda: module.__dict__
    home = WORK / 'account'; home.mkdir(mode=0o755)
    local = WORK / 'catalog-local'; local.mkdir(mode=0o755)
    system = WORK / 'catalog-system'; system.mkdir(mode=0o755)
    defaults_file = WORK / 'desktop.conf'
    defaults_file.write_text('\n'.join((
        'LABWC_MANAGED_APP_DEFAULT_EXEC="/usr/local/bin/labwc-app nvidia"',
        'LABWC_WAYLAND_APP_DEFAULT_EXEC="/usr/local/bin/labwc-wayland-app nvidia"',
        'LABWC_ELECTRON_APP_DEFAULT_EXEC="/usr/local/bin/labwc-electron-app nvidia"',
        'LABWC_INTEL_ACCELERATION_AVAILABLE=true', 'LABWC_NVIDIA_ACCELERATION_AVAILABLE=true',
    )) + '\n', encoding='ascii')
    module.DEFAULTS = defaults_file
    account.LOCAL_APPLICATION_DIR, account.SYSTEM_APPLICATION_DIR = str(local), str(system)
    desktop_dir = account.ensure_application_directory(str(home), 0, 0)
    custom = Path(desktop_dir) / 'custom.desktop'
    custom.write_text('[Desktop Entry]\nType=Application\nName=Personal GUI\n'
                      'Exec=/opt/personal/gui --keep-this %F\n', encoding='ascii')
    known = '[Desktop Entry]\nName=Vivaldi\nType=Application\nExec=/usr/bin/vivaldi-stable %U\n'
    known = module.rewrite_desktop(known, prefix, name='vivaldi-stable.desktop', managed_default=defaults['managed'])
    account.write_desktop_file(str(Path(desktop_dir) / 'vivaldi-stable.desktop'), account.parse_desktop(known), 0, 0, '/usr/bin/desktop-file-validate')
    note = system / 'note.desktop'
    note.write_text('[Desktop Entry]\nName=Notes\nType=Application\nExec=/usr/bin/notes %F\n', encoding='ascii')
    def synchronize():
        account.synchronize_catalog(str(home), desktop_dir, 0, 0, '/usr/bin/desktop-file-validate',
                                    {'intel': True, 'nvidia': True})
    publish = account.write_desktop_file
    def interrupted(path, *arguments):
        result = publish(path, *arguments)
        if path == str(Path(desktop_dir) / 'note.desktop'):
            raise RuntimeError('injected interruption after publication, before catalog receipt')
        return result
    with mock.patch.object(account, 'write_desktop_file', side_effect=interrupted):
        raises(RuntimeError, synchronize)
    assert not (home / '.local/share/labwc-dock/catalog.json').exists()
    synchronize()  # Recover the exact unchanged launcher without a manifest.
    catalog = home / '.local/share/labwc-dock/applications'
    normal = account.parse_desktop((Path(desktop_dir) / 'note.desktop').read_text(encoding='utf-8'))
    dock = account.parse_desktop((catalog / 'vivaldi-stable.desktop').read_text(encoding='utf-8'))
    assert normal['Desktop Entry']['Exec'] == '/usr/bin/notes %F'
    assert dock['Desktop Entry']['Exec'] == '/usr/local/bin/labwc-app nvidia vivaldi %U'
    assert 'labwc-wayland-app intel -- /usr/bin/notes %F' in normal['Desktop Action IntelAccelerated']['Exec']
    personal = account.parse_desktop(custom.read_text(encoding='utf-8'))
    assert personal['Desktop Entry']['Exec'] == '/opt/personal/gui --keep-this %F'
    assert 'NvidiaAccelerated' in personal['Desktop Entry']['Actions']
    before = {path: (path.read_bytes(), path.stat().st_mtime_ns) for path in catalog.glob('*.desktop')}
    synchronize()
    assert all(path.read_bytes() == content and path.stat().st_mtime_ns == stamp
               for path, (content, stamp) in before.items())
    note.write_text('[Desktop Entry]\nName=Notes\nType=Application\nExec=/usr/bin/notes-new %F\n', encoding='ascii')
    synchronize()
    assert 'Exec=/usr/bin/notes-new %F' in (Path(desktop_dir) / 'note.desktop').read_text(encoding='utf-8')
    note.unlink()
    synchronize()
    assert not (catalog / 'note.desktop').exists()
    assert not (Path(desktop_dir) / 'note.desktop').exists()
    return {'vendor_exec_samples': len(samples), 'real_desktop_validator': True, 'publication_twice': True,
            'account_catalog_idempotent': True, 'vendor_update_and_removal': True, 'dock_default_is_managed': True}


def devices_policy():
    devices = load('nvidia_devices', TARGET / 'usr/local/lib/common/hardware_tuning/nvidia_devices.py')
    links = load('fixture_char_links', TARGET / 'usr/local/libexec/common/nvidia-char-links')
    dev = WORK / 'dev'; dev.mkdir(mode=0o755)
    (dev / 'nvidia-caps').mkdir(mode=0o755)
    for name, major, minor in (('nvidia0', 195, 0), ('nvidiactl', 195, 255),
                               ('nvidia-caps/nvidia-cap1', 237, 1), ('nvidia-caps/nvidia-cap2', 237, 2)):
        os.mknod(dev / name, stat.S_IFCHR | 0o600, os.makedev(major, minor))
    rows = devices.snapshot(dev)
    assert len(rows) == 4
    assert links.reconcile(dev) == 0
    assert links.reconcile(dev, check=True) == 0
    assert (dev / 'char/237:1').is_symlink()
    (dev / 'char/237:1').unlink()
    (dev / 'char/237:1').write_text('protected occupant', encoding='ascii')
    assert links.reconcile(dev) == 1
    assert (dev / 'char/237:1').read_text(encoding='ascii') == 'protected occupant'
    (dev / 'char/237:1').unlink()
    (dev / 'nvidia-caps/nvidia-cap2').unlink()
    (dev / 'nvidia-caps/nvidia-cap2').symlink_to('../nvidia0')
    raises(ValueError, devices.snapshot, dev)
    (dev / 'nvidia-caps/nvidia-cap2').unlink()
    os.mknod(dev / 'nvidia-caps/nvidia-cap2', stat.S_IFCHR | 0o600, os.makedev(237, 2))
    module = load('fixture_policy_prepare', TARGET / 'usr/local/libexec/common/nvidia-tuning-policy')
    library = WORK / 'hardware-library'; library.mkdir(mode=0o755)
    for name in ('common.py', 'nvidia_devices.py'):
        (library / name).write_text(render((TARGET / 'usr/local/lib/common/hardware_tuning' / name).read_text(encoding='utf-8')), encoding='utf-8')
    common = load('common', library / 'common.py')
    policy = WORK / 'policy'; policy.mkdir(mode=0o755)
    state = WORK / 'policy-state'; state.mkdir(mode=0o755)
    module.LIBRARY, module.POLICY, module.STATE = library, policy, state
    module.prepare_capabilities = lambda: None  # Real driver metadata is absent.
    original_snapshot = devices.snapshot
    devices.snapshot = lambda: original_snapshot(dev)
    module.reload_policy = lambda: None
    with mock.patch.object(sys, 'argv', ['nvidia-tuning-policy']):
        assert module.main() == 0
        rules = (policy / 'nvidia-char').read_text(encoding='ascii')
        assert '/dev/char/237:1 w,' in rules and '234:' not in rules
        receipt = json.loads((policy / 'nvidia.json').read_text(encoding='ascii'))
        assert receipt['nodes'] == devices.snapshot()
        old = (policy / 'nvidia-char').read_bytes()
        old_record = (policy / 'nvidia.json').read_bytes()
        held = os.open(state / 'nvidia.lock', os.O_RDWR)
        try:
            fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with mock.patch.object(module.time, 'monotonic', side_effect=[0, 9]):
                assert module.main() == 75
        finally:
            os.close(held)
        changed = []
        def replace_identity():
            if not changed:
                node = dev / 'nvidia-caps/nvidia-cap2'
                node.unlink()
                os.mknod(node, stat.S_IFCHR | 0o600, os.makedev(237, 2))
                changed.append(True)
        module.reload_policy = replace_identity
        raises(ValueError, module.main)
        assert (policy / 'nvidia-char').read_bytes() == old
        assert (policy / 'nvidia.json').read_bytes() == old_record
        assert not list(policy.glob('*.before'))
        calls = []
        def fail_once():
            calls.append(1)
            if len(calls) == 1: raise RuntimeError('injected reload rejection')
        module.reload_policy = fail_once
        raises(RuntimeError, module.main)
        assert (policy / 'nvidia-char').read_bytes() == old
        assert (policy / 'nvidia.json').read_bytes() == old_record
        assert not list(policy.glob('*.before'))
        module.reload_policy = lambda: (_ for _ in ()).throw(RuntimeError('injected restoration failure'))
        raises(RuntimeError, module.main)
        assert len(list(policy.glob('*.before'))) == 2
        raises(ValueError, module.main)  # Retained evidence blocks republishing.
    assert common is sys.modules['common']
    return {'private_guest_character_nodes': True, 'real_nvidia_devices': False,
            'reloads_injected': True, 'rollback_bytes_restored': True, 'uncertain_evidence_retained': True}


def directory_traversal():
    module = load('fixture_debugsys', TARGET / 'usr/local/libexec/common/debugsys.py.tmpl', only_definitions=True)
    parent = WORK / 'traversal'; parent.mkdir(mode=0o751)
    child = parent / 'logs'; child.mkdir(mode=0o755)
    (child / 'app.log').write_text('guest fixture\n', encoding='ascii')
    (child / 'app.log.1').write_text('guest rotation\n', encoding='ascii')
    # This actually drops credentials in a guest child. The parent and the
    # descriptor path are private guest files, not development-host paths.
    pid = os.fork()
    if pid == 0:
        try:
            os.setgroups([]); os.setgid(1000); os.setuid(1000)
            with module.input_directory(child) as descriptor:
                assert stat.S_ISDIR(os.fstat(descriptor).st_mode)
            found, limited = module.log_paths(child / 'app.log')
            assert not limited and child / 'app.log.1' in found
            os._exit(0)
        except BaseException:
            traceback.print_exc(); os._exit(1)
    _, status = os.waitpid(pid, 0)
    assert status == 0, status
    (parent / 'alias').symlink_to(child, target_is_directory=True)
    raises((OSError, ValueError), lambda: module.input_directory(parent / 'alias').__enter__())
    return {'real_guest_dac': True, 'traversal_parent_mode': '0751', 'host_paths_read': False}


def apparmor():
    root = WORK / 'apparmor'; root.mkdir()
    include = root / 'include'
    shutil.copytree('/etc/apparmor.d', include, symlinks=True)
    features = root / 'features'
    features.write_bytes(Path('/usr/share/apparmor-features/features').read_bytes())
    config = root / 'parser.conf'; config.write_text('# private offline parser\n', encoding='ascii')
    (root / 'apparmorfs').mkdir()
    # The real absolute include is inside this disposable guest. Compile the
    # generated exact-device rules too, instead of silently skipping them.
    dynamic = Path('/run/hardware-tuning-policy')
    dynamic.mkdir(mode=0o755)
    (dynamic / 'nvidia-char').write_bytes((WORK / 'policy/nvidia-char').read_bytes())
    for family in ('common', 'desktop'):
        for source in sorted((TARGET / 'etc/apparmor.d' / family).rglob('*')):
            if not source.is_file() or source.name.startswith('AGENTS'):
                continue
            destination = include / str(source.relative_to(TARGET / 'etc/apparmor.d' / family)).removesuffix('.tmpl')
            destination.parent.mkdir(parents=True, exist_ok=True)
            text = render(source.read_text(encoding='utf-8'))
            for token in set(re.findall(r'__[A-Z0-9_]+__', text)):
                if token.startswith('__INSTALLER_LOG_'): value = '/validation/log/' + token.lower().strip('_')
                elif token in {'__ACCOUNT__', '__INSTALLER_ACCOUNT_USERNAME__'}: value = 'fixture'
                elif token == '__INSTALLER_APP_VETH_HOST_INTERFACE_PREFIX__': value = 'veth'
                elif token == '__INSTALLER_APP_VETH_HOST_INTERFACE_SUFFIX__': value = 'h'
                elif token == '__SHARING_ROOT__': value = '/validation/sharing'
                else: raise ValueError(('unsupported policy fixture token', token, str(source)))
                text = text.replace(token, value)
            destination.write_text(text, encoding='utf-8')
    for source in include.rglob('*'):
        if source.is_file() and not source.is_symlink():
            text = source.read_text(encoding='utf-8')
            source.write_text(text.replace('abi "/usr/share/apparmor-features/features",',
                              'abi "' + str(features) + '",'), encoding='utf-8')
    arguments = ['/usr/sbin/apparmor_parser', '--config-file', str(config), '-Q', '-K', '-j', '1',
                 '--base', str(include), '--Include', str(include), '-f', str(root / 'apparmorfs'),
                 '--kernel-features', str(features), '--policy-features', str(features)]
    firstboot = render((SOURCE / 'scripts/firstboot/assets/etc/apparmor.d/firstboot.tmpl').read_text(encoding='utf-8'))
    for token in set(re.findall(r'__[A-Z0-9_]+__', firstboot)):
        if token.startswith('__INSTALLER_LOG_'):
            firstboot = firstboot.replace(token, '/validation/log/' + token.lower().strip('_'))
        else:
            raise ValueError(('unsupported firstboot fixture token', token))
    firstboot = firstboot.replace('abi "/usr/share/apparmor-features/features",', 'abi "' + str(features) + '",')
    (include / 'firstboot').write_text(firstboot, encoding='utf-8')
    for name in ('hardware-tuning', 'system-wrappers', 'labwc-session', 'desktop-wrappers', 'firstboot'):
        result = subprocess.run([*arguments, '--ofile', str(root / (name + '.compiled')), str(include / name)],
                                stdin=subprocess.DEVNULL, capture_output=True, env=ENV, timeout=85)
        assert result.returncode == 0, (name, result.stderr[-4000:])
    return {'real_guest_parser': True, 'parser_support_package': '4.1.8-3+b1',
            'profiles_compiled': 5, 'kernel_policy_loaded': False, 'abi_relocated': True}


def apt_branch():
    root = WORK / 'apt'; root.mkdir()
    for leaf in ('etc/preferences.d', 'etc/sources.list.d', 'etc/apt.conf.d',
                 'state/lists/partial', 'cache/archives/partial'):
        (root / leaf).mkdir(parents=True)
    (root / 'etc/sources.list').write_text(
        'deb [trusted=yes] https://ppa.pika-os.com pika cockatiel\n', encoding='ascii')
    (root / 'state/status').write_text('', encoding='ascii')
    # apt-cache consumes prebuilt public-shaped lists only. No acquire/update,
    # package installation, external hooks or network transport is run.
    records = [
        ('nvidia-alternative-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('nvidia-support-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('firmware-nvidia-gsp-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('nvidia-kernel-dkms-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('nvidia-kernel-source-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('nvidia-kernel-support-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('nvidia-kernel-common-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('nvidia-modprobe-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('nvidia-smi-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('nvidia-suspend-common-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('nvidia-egl-common-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('nvidia-egl-icd-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('libegl-nvidia0-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('libgles-nvidia1-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('libgles-nvidia2-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('libnvidia-allocator1-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('libnvidia-eglcore-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('libnvidia-glvkspirv-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('libnvidia-gpucomp-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('libnvidia-ml1-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('libnvcuvid1-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('libcuda1-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('libnvidia-ptxjitcompiler1-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('libnvidia-pkcs11-openssl3-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', 1001),
        ('libnvidia-egl-wayland1', '1:1.1.24-101pika1', 'libnvidia-egl-wayland', 1001),
        ('libnvidia-egl-gbm1', '1.1.4-101pika1', 'libnvidia-egl-gbm', 1001),
        ('nvidia-driver-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', -1),
        ('nvidia-driver-bin-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', -1),
        ('xserver-xorg-video-nvidia-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', -1),
        ('nvidia-vulkan-icd-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', -1),
        ('libglx-nvidia0-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', -1),
        ('libnvidia-glcore-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', -1),
        ('nvidia-persistenced-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', -1),
        ('nvidia-powerd-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', -1),
        ('nvidia-opencl-icd-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', -1),
        ('nvidia-cuda-mps-580', '580.196.07-101pika2', 'nvidia-graphics-drivers-580', -1),
        ('nvidia-vaapi-driver', '0.0.18-1', 'nvidia-vaapi-driver', 990),
    ]
    packages = ''
    for name, version, source, _priority in records:
        packages += f'Package: {name}\nVersion: {version}\nSource: {source}\nArchitecture: amd64\nDescription: fixture\n\n'
    lists = root / 'state/lists'
    (lists / 'ppa.pika-os.com_dists_pika_cockatiel_binary-amd64_Packages').write_text(
        packages, encoding='ascii')
    (lists / 'ppa.pika-os.com_dists_pika_Release').write_text(
        'Origin: Pika\nLabel: Pika\nSuite: pika\nCodename: pika\n'
        'Architectures: amd64\nComponents: cockatiel\n', encoding='ascii')
    config = root / 'apt.conf'
    config.write_text(f'Dir "{root}";\nDir::Etc "etc";\nDir::State "state";\nDir::State::status "status";\n'
                      'Dir::Cache "cache";\nAPT::Architecture "amd64";\nAPT::Architectures { "amd64"; };\n'
                      'Dir::Cache::pkgcache "";\nDir::Cache::srcpkgcache "";\n', encoding='ascii')
    for suite in ('forky', 'trixie'):
        for family in ('desktop', 'server'):
            preference = ROOT / 'source/d-i' / suite / 'hooks/target/etc/apt' / family / 'preferences.d/optional/nvidia-legacy.pref'
            (root / 'etc/preferences').write_bytes(preference.read_bytes())
            env = dict(ENV, APT_CONFIG=str(config))
            result = subprocess.run(['/usr/bin/apt-cache', 'policy', *sorted({row[0] for row in records})],
                                    env=env, capture_output=True, timeout=10)
            assert result.returncode == 0, result.stderr
            output = result.stdout.decode()
            for name, version, _source, priority in records:
                section = re.split(r'^\S[^\n]*:\n', output.split(name + ':\n', 1)[1], maxsplit=1, flags=re.M)[0]
                assert re.search(r'^\s+(?:\*\*\* )?' + re.escape(version) + r'\s+' + str(priority) + r'$', section, re.M), (suite, family, name, version, priority, output)
    return {'real_guest_apt': '3.3.7', 'family_suite_combinations': 4, 'synthetic_package_versions': len(records),
            'network_contacted': False, 'packages_installed': False}


def python_launcher():
    source = TARGET / 'usr/local/bin/desktop/labwc-run'
    module = load('fixture_python_launcher', source)
    root = WORK / 'python-launcher'
    root.mkdir(mode=0o700)
    config = root / 'desktop.conf'
    assert module.launcher_command(config) == ['labwc-main-menu', '--search']
    with mock.patch.dict(os.environ, {'LABWC_LAUNCHER_COMMAND':'labwc-fuzzel launcher'}):
        assert module.launcher_command(config) == ['labwc-fuzzel','launcher']
    config.write_text("IGNORED=$(touch should-not-exist)\nLABWC_LAUNCHER_COMMAND='labwc-fuzzel launcher'\n", encoding='utf-8')
    assert module.launcher_command(config) == ['labwc-fuzzel','launcher']
    assert not (root / 'should-not-exist').exists()
    for command in ('labwc-fuzzel; true', '$(true)', '`true`', 'labwc-fuzzel > output'):
        config.write_text('LABWC_LAUNCHER_COMMAND='+shlex.quote(command)+'\n', encoding='utf-8')
        raises(ValueError, module.launcher_command, config)
    config.write_text("LABWC_LAUNCHER_COMMAND='labwc-fuzzel'\nLABWC_LAUNCHER_COMMAND='labwc-main-menu'\n", encoding='utf-8')
    raises(ValueError, module.launcher_command, config)
    config.write_bytes(b'#' * (module.MAX_CONFIG_BYTES + 1))
    raises(ValueError, module.launcher_command, config)
    link = root / 'symlink.conf'
    link.symlink_to(config)
    raises(OSError, module.launcher_command, link)
    fifo = root / 'fifo.conf'
    os.mkfifo(fifo)
    raises(ValueError, module.launcher_command, fifo)
    with mock.patch.dict(os.environ, {'XDG_RUNTIME_DIR':'/run/user/1000'}), \
            mock.patch.object(module.Path,'is_file',return_value=True), \
            mock.patch.object(module,'launcher_command') as command:
        assert module.main() == 0
        command.assert_not_called()
    with mock.patch.object(module,'launcher_command',return_value=['absent-launcher']), \
            mock.patch.object(module.shutil,'which',return_value=None):
        raises(ValueError, module.main)
    # Run the rendered wrapper and its real exec replacement in this private
    # guest. The executed program records its PID and returns a known status.
    output = root / 'executed.json'
    program = root / 'record.py'
    program.write_text('import json, os, pathlib, sys\n'
                       'pathlib.Path('+repr(str(output))+').write_text(json.dumps({"pid":os.getpid(),"args":sys.argv[1:]}))\n'
                       'raise SystemExit(37)\n', encoding='utf-8')
    config.write_text('LABWC_LAUNCHER_COMMAND='+shlex.quote(sys.executable+' -I -B '+str(program)+' chosen')+'\n', encoding='utf-8')
    entry = root / 'labwc-run.py'
    code = render(source.read_text(encoding='utf-8'))
    needle = "CONFIG = Path('/etc/labwc/desktop.conf')"
    assert code.count(needle) == 1
    code = code.replace(needle, 'CONFIG = Path('+repr(str(config))+')')
    entry.write_text(code, encoding='utf-8')
    child = subprocess.Popen([sys.executable,'-I','-B',str(entry)], cwd=root, env=ENV,
                             stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        stdout, stderr = child.communicate(timeout=10)
    finally:
        if child.poll() is None:
            child.kill(); child.communicate(timeout=3)
    assert child.returncode == 37, (child.returncode, stdout, stderr)
    assert json.loads(output.read_text(encoding='utf-8')) == {'pid':child.pid,'args':['chosen']}
    return {'real_guest_exec':True, 'same_pid':True, 'child_status':37,
            'shell_config_executed':False, 'bounded_literal_parser':True}


def live_policy_inputs():
    wlsunset = load('fixture_wlsunset_config', TARGET / 'usr/local/bin/desktop/labwc-wlsunset')
    cfg = {'WLSUNSET_ENABLED':'true','WLSUNSET_LATITUDE':'55.6','WLSUNSET_LONGITUDE':'13.0',
           'WLSUNSET_TEMPERATURE_DAY':'6500','WLSUNSET_TEMPERATURE_NIGHT':'4500','WLSUNSET_GAMMA':'1.0',
           'WLSUNSET_SUNRISE':'','WLSUNSET_SUNSET':'','WLSUNSET_TRANSITION_SECONDS':'1800','WLSUNSET_OUTPUTS':''}
    wlsunset.validate_config(cfg)
    active = {'LoadState':'loaded', 'ActiveState':'active',
              'Environment':'LABWC_WLSUNSET_POLICY_DIGEST=' + wlsunset.policy_digest(cfg)}
    with mock.patch.object(wlsunset,'managed_unit',return_value=active), mock.patch.object(wlsunset,'stop_unit') as stopped, \
            mock.patch.object(wlsunset,'active_session') as session:
        assert wlsunset.operate('apply',dict(cfg),{},1000) == 0
        stopped.assert_not_called(); session.assert_not_called()
    changed = dict(cfg, WLSUNSET_TEMPERATURE_NIGHT='4000')
    with mock.patch.object(wlsunset,'managed_unit',return_value=active), mock.patch.object(wlsunset,'stop_unit') as stopped, \
            mock.patch.object(wlsunset,'active_session',return_value={'WAYLAND_DISPLAY':'wayland-0'}), \
            mock.patch.object(wlsunset,'command',return_value=subprocess.CompletedProcess([],0,'','')):
        assert wlsunset.operate('apply',changed,{},1000) == 0
        stopped.assert_called_once()
    bad = dict(cfg, WLSUNSET_GAMMA='invalid')
    raises(ValueError,wlsunset.validate_config,bad)
    proxy = load('fixture_proxy_config', TARGET / 'usr/local/libexec/desktop/labwc-proxy-session')
    payload = b'maxconn 1024\ntimeouts 1 5 30 60 180 1800 15 60 15 5\nauth iponly\nallow * 127.0.0.1 * 80,443,5380 HTTP_CONNECT\ndeny *\nproxy -4 -a -i127.0.0.1 -p3128\n'
    proxy.validate_proxy_config(payload,3128)
    for bad in (payload+b'daemon\n',payload.replace(b'HTTP_CONNECT',b'HTTP'),payload.replace(b'127.0.0.1',b'0.0.0.0'),payload.replace(b'80,443',b'80,70000')):
        raises(ValueError,proxy.validate_proxy_config,bad,3128)
    raises(ValueError,proxy.validate_proxy_config,payload,3129)
    native = b'[Network]\nProxy\\Port=3128\nProxy\\IP=127.0.0.1\n[Other]\nProxy\\Port=untouched\n'
    projected = proxy.qbittorrent_proxy_config(native, 3129)
    assert projected == native.replace(b'Proxy\\Port=3128', b'Proxy\\Port=3129')
    raises(ValueError, proxy.qbittorrent_proxy_config, native.replace(b'[Other]', b'Proxy\\Port=3000\n[Other]'), 3129)
    primary = load('fixture_primary_config', TARGET / 'usr/local/libexec/desktop/labwc-primary-gpg')
    raises(ValueError,primary.unique_object,[('schema',1),('schema',2)])
    # Credential policy parsing is exercised without GnuPG, HTTP or delivery.
    reminders = load('fixture_reminder_policy', TARGET / 'usr/local/lib/desktop/python3/dist-packages/labwc_calendar_reminders.py')
    values = {'LABWC_PLANS_'+key:value for key,value in (
        ('ENABLED','true'),('TELEGRAM_ENABLED','false'),('TELEGRAM_API_BASE','https://api.telegram.org'),
        ('TELEGRAM_API_KEY',''),('TELEGRAM_CHAT_ID',''),('NTFY_ENABLED','false'),
        ('NTFY_BASE_URL','https://ntfy.sh'),('NTFY_TOPIC',''),('NTFY_ACCESS_TOKEN',''),('NTFY_READER_ACCESS_CONFIRMED','false'))}
    path = WORK/'plans.conf'
    # This owning file has its existing stricter, single-quoted grammar.
    path.write_text(''.join(key+"='"+value+"'\n" for key,value in values.items()),encoding='utf-8'); path.chmod(0o640)
    assert reminders.read_policy(path) == values
    path.write_text(path.read_text()+"LABWC_PLANS_UNKNOWN='true'\n",encoding='utf-8')
    raises(reminders.ReminderError,reminders.read_policy,path)
    return {'wlsunset_duplicate_event_noop': True, 'wlsunset_systemd_injected': True,
            'proxy_listener_mismatch_rejected': True, 'credential_network_operations': False}


def exact_file_events():
    import ctypes
    import struct
    import select
    root = WORK/'file-events'; root.mkdir()
    path = root/'desktop.conf'; path.write_text('original',encoding='ascii')
    libc = ctypes.CDLL(None,use_errno=True)
    libc.inotify_init1.argtypes=[ctypes.c_int]; libc.inotify_init1.restype=ctypes.c_int
    libc.inotify_add_watch.argtypes=[ctypes.c_int,ctypes.c_char_p,ctypes.c_uint32]; libc.inotify_add_watch.restype=ctypes.c_int
    fd=libc.inotify_init1(os.O_NONBLOCK|os.O_CLOEXEC)
    assert fd>=0
    mask=0x8|0x80|0x100|0x200  # CLOSE_WRITE, MOVED_TO, CREATE, DELETE
    try:
        assert libc.inotify_add_watch(fd,os.fsencode(root),mask)>=0
        def changed():
            ready=select.select([fd],[],[],0.2)[0]
            if not ready: return []
            data=os.read(fd,65536); offset=0; found=[]
            while offset<len(data):
                _watch,event,_cookie,size=struct.unpack_from('iIII',data,offset); offset+=16
                name=data[offset:offset+size].rstrip(b'\0').decode(); offset+=size
                if name==path.name and event & (0x8|0x80|0x100|0x200): found.append(name)
            return found
        for name in ('desktop.conf.lock','.desktop.conf.swp','desktop.conf~','desktop.conf.tmp'):
            (root/name).write_text('temporary',encoding='ascii')
            assert changed()==[],name
        path.write_text('in-place',encoding='ascii'); assert changed()
        replacement=root/'.desktop.conf.new'; replacement.write_text('atomic',encoding='ascii')
        assert changed()==[]
        replacement.replace(path); assert changed()
        path.unlink(); assert changed()
        path.write_text('recreated',encoding='ascii'); assert changed()
    finally:
        os.close(fd)
    for relative in ('etc/systemd/desktop/system/labwc-system-desktop-overrides.path',
                     'etc/skel-desktop/.config/systemd/user/labwc-sync-application-launchers.path',
                     'etc/skel-desktop/.config/systemd/user/labwc-wlsunset-apply.path'):
        text=render((TARGET/relative).read_text())
        for line in text.splitlines():
            if line.startswith('PathChanged=/etc/labwc'):
                assert line in ('PathChanged=/etc/labwc/desktop.conf','PathChanged=/etc/labwc/wlsunset.conf')
    return {'real_guest_inotify': True,'exact_name_filter_fixture': True,'atomic_replace': True,
            'sibling_lock_backup_temp_events_ignored': True,'real_systemd_manager': False}


def main():
    failures = 0
    cases = {'firstboot': firstboot, 'process-gpu': process_gpu, 'profile-modes': profile_modes,
             'dock-namespace': dock_namespace, 'menu-icons': menu_icons, 'desktop-actions': desktop_actions,
             'device-policy': devices_policy, 'directory-traversal': directory_traversal,
             'apparmor': apparmor, 'apt-branch': apt_branch, 'python-launcher': python_launcher,
             'live-policy-inputs': live_policy_inputs, 'exact-file-events': exact_file_events}
    selected = sys.argv[1:] or list(cases)
    for name in selected:
        try:
            result = cases[name]()
            print(json.dumps({'case': name, 'passed': True, **result}, sort_keys=True), flush=True)
        except BaseException as error:
            failures += 1
            print(json.dumps({'case': name, 'passed': False, 'error': str(error)[:6000],
                              'traceback': traceback.format_exc()[-4000:]}, sort_keys=True), flush=True)
    print('FINDINGS_FIXTURE_STATUS=' + str(int(bool(failures))), flush=True)
    return int(bool(failures))


if __name__ == '__main__':
    raise SystemExit(main())
