"""Shared unprivileged NFS/Filen operations; native systemd authorization."""
from __future__ import annotations
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import ipaddress
import json
import os
from pathlib import Path
import posixpath
import pwd
import re
import socket
import stat
import subprocess
import sys

CONFIG = Path('__INSTALLER_PATH_DIR_ETC__/network-sharing/config.json')
REPORT = Path('__INSTALLER_PATH_DIR_RUN__/network-sharing/report.json')
FSTAB = Path('__INSTALLER_PATH_DIR_ETC__/fstab')
FILEN_ACCOUNTS = ('private', 'offsec')

def clean(text: str, limit: int = 800) -> str:
    return ''.join(c if c.isprintable() else ' ' for c in str(text))[:limit]


def read_owned_file(path: Path, limit: int) -> bytes:
    # Configuration, reports and fstab have root-owned, non-writable parents.
    for parent in reversed(path.parents):
        metadata = parent.lstat()
        if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != 0 or metadata.st_mode & 0o022:
            raise ValueError('untrusted network sharing directory')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    with os.fdopen(fd, 'rb') as stream:
        metadata = os.fstat(stream.fileno())
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0 or metadata.st_nlink != 1 or metadata.st_mode & 0o022:
            raise ValueError('untrusted network sharing data file')
        raw = stream.read(limit + 1)
    if len(raw) > limit:
        raise ValueError('network sharing data is too large')
    return raw


def read_json(path: Path, limit: int = 4 * 1024 * 1024) -> dict:
    value = json.loads(read_owned_file(path, limit))
    if not isinstance(value, dict):
        raise ValueError('unsupported network sharing data format')
    return value


def load_config() -> dict:
    config = read_json(CONFIG, 65536)
    if config.get('version') != 3:
        raise ValueError('unsupported network sharing configuration; shared-root mounts require version 3')
    if any(key in config for key in ('client_automount', 'client_bind_automount', 'server_bind_automount')):
        raise ValueError('legacy automount configuration is unsupported')
    if any(type(config.get(key)) is not bool for key in ('server_enabled', 'client_enabled')):
        raise ValueError('invalid role flags')
    if not isinstance(config.get('profile'), dict):
        raise ValueError('missing installed profile settings')
    for key in ('client_mount', 'sharing_mount', 'sharing_bind_mount'):
        value = config.get(key)
        if not isinstance(value, str) or (value and (len(value) > 255 or not re.fullmatch(r'(?!-)(?:[A-Za-z0-9_.-]|\\x[0-9a-f]{2})+\.mount', value))):
            raise ValueError('invalid managed mount unit')
    if not config['client_mount']:
        raise ValueError('missing client mount unit')
    if not config['sharing_mount'] or not config['sharing_bind_mount']:
        raise ValueError('missing shared-root mount units')
    return config


def units(config: dict) -> list[str]:
    result = ['nftables.service']
    if config['server_enabled'] or config['client_enabled']:
        result.append('network-sharing-identity.service')
    if config['server_enabled']:
        result += ['nfs-server.service', 'nfs-mountd.service', 'nfs-idmapd.service']
    if config['client_enabled']:
        result += ['nfs-client.target', config['client_mount']]
    result += [config['sharing_mount'], config['sharing_bind_mount']]
    return list(dict.fromkeys(result))


def command(argv: list[str], timeout: int = 100) -> subprocess.CompletedProcess:
    # No environment-controlled pager, bus redirection, shell, or PATH lookup.
    env = {key: value for key, value in os.environ.items()
           if key in ('HOME', 'USER', 'LOGNAME', 'XDG_RUNTIME_DIR', 'LANG', 'LC_ALL', 'TERM')}
    env.update(PATH='__INSTALLER_PATH_DIR_USR__/sbin:__INSTALLER_PATH_DIR_USR__/bin:/sbin:/bin', SYSTEMD_PAGER='cat',
               SYSTEMD_COLORS='0', SYSTEMD_URLIFY='0')
    terminal = None
    try:
        # The native client checks stdin for a TTY before opening its Polkit agent.
        # Only fixed, validated manager mutations receive the invoking TTY.
        # Password input stays between the native agent and that terminal.
        interactive = (argv[0] == '__INSTALLER_PATH_DIR_USR__/bin/systemctl'
                       and any(verb in argv[1:] for verb in ('start', 'stop', 'restart', 'reload')))
        if interactive and sys.stdin.isatty():
            terminal = open('__INSTALLER_PATH_DIR_DEV__/tty', 'rb', buffering=0)
        return subprocess.run(argv, stdin=terminal if terminal is not None else subprocess.DEVNULL,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, check=False, timeout=timeout, env=env)
    except subprocess.TimeoutExpired as error:
        # systemctl's client is killed/reaped, not a remote hard-mounted I/O
        # worker. The manager still owns its bounded mount/service job.
        raise RuntimeError('Command timed out; check Sharing Status. The systemd job may still be completing; no forced unmount was attempted.') from error
    finally:
        if terminal is not None:
            terminal.close()


@contextmanager
def terminal_lock():
    """Serialize terminal toggles before observing state; never unlink the lock."""
    root = Path('__INSTALLER_PATH_DIR_RUN_USER__') / str(os.getuid())
    metadata = root.lstat()
    if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.getuid() or metadata.st_mode & 0o077:
        raise ValueError('A private login runtime directory is required')
    fd = os.open(root / '.sharing-toggle.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK, 0o600)
    try:
        metadata = os.fstat(fd)
        if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid()
                or metadata.st_nlink != 1 or stat.S_IMODE(metadata.st_mode) != 0o600):
            raise ValueError('untrusted sharing toggle lock')
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Another sharing toggle is still running; wait for it to finish') from None
        yield
    finally:
        os.close(fd)


def systemctl(config: dict, verb: str, selected: list[str]) -> subprocess.CompletedProcess:
    # Firewall, identity and RPC dependencies are status-only here. Starting
    # the configured server/mount lets PID 1 enforce their dependency graph.
    client = {config['client_mount']} if config['client_enabled'] else set()
    server = {'nfs-server.service'} if config['server_enabled'] else set()
    diagnostics = {'network-sharing-report.service'} if config['server_enabled'] or config['client_enabled'] else set()
    allowed = {'show': set(units(config)) | diagnostics,
               'start': client | server | diagnostics, 'stop': client | server,
               'restart': server, 'reload': server}
    if verb not in allowed or not selected or any(unit not in allowed[verb] for unit in selected):
        raise ValueError('unmanaged systemd operation rejected')
    args = ['__INSTALLER_PATH_DIR_USR__/bin/systemctl', '--system', '--no-pager', '--no-legend', verb]
    if verb == 'show':
        args += ['--property=Id,LoadState,ActiveState,SubState,Result']
    return command([*args, '--', *selected], 200 if verb != 'show' else 15)


def mount_unit(path: str) -> str:
    # Match the installer's ASCII path grammar without resolving remote paths.
    if (not isinstance(path, str) or len(path) > 2048 or not re.fullmatch(r'/[A-Za-z0-9_./-]+', path)
            or any(part in ('', '.', '..') for part in path[1:].split('/'))):
        raise ValueError('invalid configured NFS mount path')
    escaped = ''.join('/' if c == '/' else (c if c.isalnum() or c in '_.' else f'\\x{ord(c):02x}')
                      for c in path[1:])
    if escaped.startswith('.'):
        escaped = '\\x2e' + escaped[1:]
    return escaped.replace('/', '-') + '.mount'


def client_mounts(config: dict) -> tuple[str, int, list[tuple[str, str, str, str]]]:
    """Match the one configured NFS source to fstab; never select arbitrary units."""
    if not config['client_enabled']:
        raise ValueError('No NFS client is configured in fstab. Enable NFS_CLIENT_ENABLE in the installer profile and rebuild.')
    settings = config['profile']
    server = str(ipaddress.IPv4Address(settings['NFS_CLIENT_TARGET_IP']))
    port_text = settings['NFS_SERVER_PORT']
    if not isinstance(port_text, str) or not re.fullmatch(r'[0-9]{1,5}', port_text) or not 1 <= int(port_text) <= 65535:
        raise ValueError('invalid configured NFS server port')
    source = settings['NFS_CLIENT_PATH']
    remote = server + ':' + settings['NFS_CLIENT_EXPORT_PATH']
    options = settings['NFS_MNT_CLIENT_TARGET_SHARE_OPTS'].split(',')
    if settings['NFS_CLIENT_READ_ONLY'] == 'true':
        options = ['ro' if option == 'rw' else option for option in options]
    expected = [(config['client_mount'], remote, source, 'nfs', options)]
    account = pwd.getpwuid(os.getuid())
    if account.pw_name != settings['ACCOUNT_USERNAME'] or account.pw_dir != settings['ACCOUNT_HOME']:
        raise ValueError('Run nfsmnt as the configured operator account: ' + settings['ACCOUNT_USERNAME'])
    options.append('x-systemd.requires-mounts-for=' + settings['NETWORK_SHARING_ROOT_PATH'])
    options.append('x-systemd.requires-mounts-for=' + settings['ACCOUNT_HOME'] + '/' + settings['NETWORK_SHARING_HOME_BIND_PATH'])
    records = []
    for line in read_owned_file(FSTAB, 1024 * 1024).decode('utf-8').splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        fields = line.split()
        if len(fields) < 4:
            raise ValueError('invalid fstab record; ask an administrator to check __INSTALLER_PATH_DIR_ETC__/fstab')
        records.append([re.sub(r'\\([0-7]{3})', lambda match: chr(int(match[1], 8)), field)
                        for field in fields[:4]])
    mounts = []
    for unit, what, where, kind, flags in expected:
        if unit != mount_unit(where):
            raise ValueError('configured NFS path and mount unit differ')
        matches = [row for row in records if posixpath.normpath(row[1]) == where]
        if len(matches) != 1:
            raise ValueError('missing or duplicate NFS fstab entry for ' + where)
        row = matches[0]
        actual_flags = row[3].split(',')
        types = ('nfs', 'nfs4') if kind == 'nfs' else ('none',)
        if (row[:2] != [what, where] or row[2] not in types or set(actual_flags) != set(flags)
                or len(actual_flags) != len(set(actual_flags))):
            raise ValueError('NFS fstab entry differs from the installed profile: ' + where)
        mounts.append((unit, what, where, row[2]))
    return server, int(port_text), mounts


def check_mount(config: dict, mount: tuple[str, str, str, str], *, active: bool = False,
                inactive: bool = False) -> bool:
    unit, what, where, kind = mount
    if not config['client_enabled'] or unit != config['client_mount']:
        raise ValueError('unmanaged mount status operation rejected')
    result = command(['__INSTALLER_PATH_DIR_USR__/bin/systemctl', '--system', '--no-pager', 'show',
                      '--property=LoadState,ActiveState,SubState,What,Where,Type', '--', unit], 15)
    if result.returncode:
        raise RuntimeError('Cannot check NFS mount: ' + clean(result.stdout, 1600))
    properties = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
    mounted = (properties.get('ActiveState'), properties.get('SubState')) == ('active', 'mounted')
    types = ('nfs', 'nfs4')
    if (properties.get('LoadState') != 'loaded' or properties.get('What') != what
            or properties.get('Where') != where or properties.get('Type') not in types):
        raise RuntimeError('systemd mount differs from fstab: ' + unit
                           + '. Ask an administrator to check the configuration and run systemctl daemon-reload.')
    if active and not mounted:
        raise RuntimeError('NFS mount did not become active: ' + unit)
    if inactive and properties.get('ActiveState') != 'inactive':
        raise RuntimeError('NFS mount did not become inactive: ' + unit)
    if properties.get('ActiveState') not in {'active', 'inactive', 'failed'}:
        raise RuntimeError('NFS mount is changing state; wait for its current job: ' + unit)
    if properties.get('ActiveState') == 'active' and not mounted:
        raise RuntimeError('NFS mount is not in a stable mounted state: ' + unit)
    return mounted


def connect_terminal(config: dict) -> int:
    server, port, mounts = client_mounts(config)
    for mount in mounts:
        check_mount(config, mount)
    print(f'nfsmnt: Checking NFS server {server}:{port} ...', flush=True)
    try:
        # Numeric IPv4 avoids DNS, ICMP and NFSv3/showmount dependencies.
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            probe.settimeout(3)
            probe.connect((server, port))
    except OSError as error:
        raise RuntimeError(f'NFS server {server}:{port} is unavailable: {clean(str(error))}. No mount was requested.') from error
    for mount in mounts:
        print('nfsmnt: Mounting ' + mount[2] + ' ...', flush=True)
        result = systemctl(config, 'start', [mount[0]])
        if result.returncode:
            raise RuntimeError('Cannot mount ' + mount[2] + ': ' + clean(result.stdout, 1600)
                               + '. Authorization requires an configured administrator with a terminal or desktop authentication agent; check Network Sharing status and logs.')
        # A successful but condition-skipped start must not be reported as mounted.
        check_mount(config, mount, active=True)
    print('nfsmnt: Mounted ' + ' and '.join(mount[2] for mount in mounts) + '.')
    print('nfsmnt: The shared home view receives this mount automatically.')
    return 0


def toggle_terminal(config: dict) -> int:
    _, _, mounts = client_mounts(config)
    mount, = mounts
    if not check_mount(config, mount):
        return connect_terminal(config)
    # A disconnect must work even when the server cannot answer a TCP probe.
    print('nfsmnt: Unmounting ' + mount[2] + ' ...', flush=True)
    result = systemctl(config, 'stop', [mount[0]])
    if result.returncode:
        raise RuntimeError('Cannot unmount ' + mount[2] + ': ' + clean(result.stdout, 1600)
                           + '. Close files and applications using the share, then retry.')
    check_mount(config, mount, inactive=True)
    print('nfsmnt: Unmounted ' + mount[2] + '. The shared home view follows automatically.')
    return 0


def filen_state(account: str, *, stopped: bool = False) -> bool:
    if account not in FILEN_ACCOUNTS:
        raise ValueError('unmanaged Filen account rejected')
    unit = 'filen-sync@' + account + '.service'
    result = command(['__INSTALLER_PATH_DIR_USR__/bin/systemctl', '--system', '--no-pager', 'show',
                      '--property=LoadState,ActiveState,SubState,User,Group,FragmentPath,Type', '--', unit], 15)
    if result.returncode:
        raise RuntimeError('Cannot check Filen service: ' + clean(result.stdout, 1600))
    properties = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
    if (properties.get('LoadState') != 'loaded' or properties.get('User') != 'filen-' + account
            or properties.get('Group') != 'filen-' + account or properties.get('Type') != 'simple'
            or properties.get('FragmentPath') != '__INSTALLER_PATH_DIR_SYSTEMD_ETC__/system/filen-sync@.service'):
        raise ValueError('Filen service differs from the installed account: ' + account)
    state = properties.get('ActiveState')
    if stopped and state != 'inactive':
        raise RuntimeError('Filen service did not stop cleanly: ' + account)
    if state not in {'active', 'activating', 'inactive', 'failed'}:
        raise RuntimeError('Filen service is changing state; wait for its current job: ' + account)
    # Restart backoff is activating/auto-restart: toggling must cancel that
    # pending synchronization too, rather than issuing another start.
    return state in {'active', 'activating'}


def toggle_filen(config: dict, selected: str | None = None) -> int:
    settings = config['profile']
    identity = pwd.getpwuid(os.getuid())
    if identity.pw_name != settings['ACCOUNT_USERNAME'] or identity.pw_dir != settings['ACCOUNT_HOME']:
        raise ValueError('Run filenmnt as the configured operator account: ' + settings['ACCOUNT_USERNAME'])
    if selected is not None and selected not in FILEN_ACCOUNTS:
        raise ValueError('unmanaged Filen account rejected')
    planned = []
    # Validate every selected public config and unit before changing any account.
    # Credentials and private service state are never read by the desktop UID.
    for account in (selected,) if selected else FILEN_ACCOUNTS:
        try:
            data = read_json(Path('__INSTALLER_PATH_DIR_ETC__/filen') / (account + '.json'), 65536)
        except FileNotFoundError:
            if selected:
                raise ValueError('Filen account is not configured: ' + account) from None
            continue
        local = settings['NETWORK_SHARING_ROOT_PATH'] + '/filen-' + account
        if (data.get('version') != 1 or data.get('account') != account or data.get('local') != local
                or data.get('sync_mode') not in {'twoWay', 'localToCloud', 'cloudToLocal', 'localBackup', 'cloudBackup'}):
            raise ValueError('Filen configuration differs from the installed sharing profile: ' + account)
        planned.append((account, filen_state(account)))
    if not planned:
        raise ValueError('No Filen sync accounts are configured')
    for account, running in planned:
        verb = 'stop' if running else 'start'
        print('filenmnt: ' + ('Stopping' if running else 'Starting') + ' filen-' + account + ' synchronization ...', flush=True)
        result = command(['__INSTALLER_PATH_DIR_USR__/bin/systemctl', '--system', '--no-pager', '--no-legend',
                          verb, '--', 'filen-sync@' + account + '.service'], 200)
        if result.returncode:
            raise RuntimeError('Cannot ' + verb + ' filen-' + account + ': ' + clean(result.stdout, 1600)
                               + '. Authorization requires an configured administrator with a terminal or desktop authentication agent.')
        if filen_state(account, stopped=running) == running:
            raise RuntimeError('Filen service did not reach the requested state: ' + account)
        print('filenmnt: filen-' + account + (' synchronization stopped; local files remain available.'
              if running else ' synchronization started; initialization and authentication continue in the service.'))
    return 0


def main(argv: list[str]) -> int:
    if argv not in ([], ['--status'], ['--connect'], ['--toggle'], ['--filen-toggle'],
                    ['--filen-toggle', '--private'], ['--filen-toggle', '--offsec']):
        raise ValueError('usage: network-sharing [--status|--connect|--toggle|--filen-toggle [--private|--offsec]]')
    if os.geteuid() == 0:
        raise ValueError('Network Sharing requires the configured operator, never root')
    config = load_config()
    if argv in ([], ['--status']):
        result = systemctl(config, 'show', units(config))
        print(result.stdout, end='')
        return result.returncode
    if argv == ['--connect']:
        return connect_terminal(config)
    with terminal_lock():
        if argv == ['--toggle']:
            return toggle_terminal(config)
        return toggle_filen(config, argv[1][2:] if len(argv) == 2 else None)
