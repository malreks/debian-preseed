#!/usr/bin/python3 -I
"""Configure NFS in the installer's target chroot, never the running installer.

No probing, mounts, module loads, sysctl writes, or service starts occur here.
The public functions are separable for offline tests; the CLI always uses /.
"""
from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass
import grp
import ipaddress
import json
import os
from pathlib import Path, PurePosixPath
import pwd
import re
import signal
import stat
import subprocess
import sys
import tempfile
from typing import Iterator, Mapping

BEGIN = '# BEGIN managed-network-sharing'
END = '# END managed-network-sharing'
REQUIRED_FLAGS = {'sync', 'subtree_check', 'root_squash', 'secure', 'sec=sys', 'fsid=0'}
PRIVATE_NETWORKS = tuple(ipaddress.ip_network(n) for n in ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'))
BOOLS = ('NFS_SERVER_ENABLE', 'NFS_CLIENT_ENABLE', 'NFS_CLIENT_READ_ONLY')
TOOL_ENV = {'PATH': '__INSTALLER_PATH_DIR_USR_SBIN__:__INSTALLER_PATH_DIR_USR_BIN__:__INSTALLER_PATH_DIR_SBIN__:__INSTALLER_PATH_DIR_BIN__', 'LANG': 'C', 'LC_ALL': 'C',
            'DEBIAN_FRONTEND': 'noninteractive', 'DEBCONF_NONINTERACTIVE_SEEN': 'true',
            'NEEDRESTART_SUSPEND': '1', 'SYSTEMD_OFFLINE': '1'}
RECOVERY = Path(__file__).absolute().parent / 'outcome-unknown.json'


class OutcomeUnknown(RuntimeError):
    """Keep private installer evidence when a child tree cannot be accounted for."""


def retain_uncertainty(cause: str) -> None:
    # The source and its parent are installer-owned private staging data.
    # No argv, credential, command output or environment enters this receipt.
    atomic_write(RECOVERY, json.dumps({'format': 1, 'outcome': 'unknown', 'cause': cause}, sort_keys=True) + '\n', 0o600)


def normalized_path(value: str, *, relative: bool = False, allow_root: bool = False) -> str:
    if not value or len(value) > 2048 or not re.fullmatch(r'[A-Za-z0-9_./-]+', value):
        raise ValueError('sharing paths must use only ASCII letters, digits, _, ., / and -')
    if value.startswith('/') == relative or (value == '/' and not allow_root):
        raise ValueError('unexpected absolute/relative sharing path')
    if value.startswith('//') or (value != '/' and any(part in ('', '.', '..') for part in value.lstrip('/').split('/'))):
        raise ValueError('sharing path is not normalized')
    return value


def bounded_integer(value: str, name: str, lower: int, upper: int) -> int:
    if not re.fullmatch(r'[0-9]+', value) or not lower <= int(value) <= upper:
        raise ValueError(f'{name} must be an integer in {lower}..{upper}')
    return int(value)


def private_ipv4(value: str) -> ipaddress.IPv4Address:
    ip = ipaddress.IPv4Address(value)
    if not any(ip in network for network in PRIVATE_NETWORKS):
        raise ValueError('NFS peers must have RFC1918 IPv4 addresses on a trusted network')
    return ip


def parse_exports(line: str, server_path: str) -> list[tuple[str, str]]:
    """One export, nonoverlapping LAN CIDRs/IPs, never wildcard/DNS entries."""
    if not line or len(line) > 16384 or any(c in line for c in '\r\n\t'):
        raise ValueError('NFS_SERVER_EXPORTS must be one bounded, space-separated line')
    fields = line.split(' ')
    if len(fields) < 2 or fields[0] != server_path or '' in fields:
        raise ValueError('NFS_SERVER_EXPORTS must export exactly NFS_SERVER_PATH')
    peers: list[tuple[str, str]] = []
    networks: list[ipaddress.IPv4Network] = []
    for field in fields[1:]:
        match = re.fullmatch(r'([0-9./]+)\(([a-z0-9_,=]+)\)', field)
        if not match:
            raise ValueError('invalid NFS peer/option grammar')
        network = ipaddress.IPv4Network(match[1], strict=True)
        if not any(network.subnet_of(n) for n in PRIVATE_NETWORKS):
            raise ValueError('NFS exports require explicit RFC1918 CIDRs or addresses')
        if any(network.overlaps(other) for other in networks):
            raise ValueError('overlapping NFS export CIDRs are ambiguous')
        options = match[2].split(',')
        flags = set(options)
        mode = flags & {'ro', 'rw'}
        if len(flags) != len(options) or len(mode) != 1 or flags != REQUIRED_FLAGS | mode:
            raise ValueError('export flags must be ro/rw,sync,subtree_check,root_squash,secure,sec=sys,fsid=0')
        networks.append(network)
        peers.append((str(network), next(iter(mode))))
    return peers


def package_names(value: str, required: set[str]) -> list[str]:
    packages = value.split()
    if not packages or len(packages) > 64 or any(not re.fullmatch(r'[a-z0-9][a-z0-9+.-]{1,79}', p) for p in packages):
        raise ValueError('invalid NFS dependency package names')
    if not required <= set(packages):
        raise ValueError('NFS dependency list omits required packages: ' + ' '.join(sorted(required - set(packages))))
    return sorted(set(packages))


def mount_options(value: str, name: str, required: set[str], optional: set[str]) -> list[str]:
    """Accept configured ordering, but never remove safety/dependency flags."""
    options = value.split(',')
    flags = set(options)
    if (not value or len(value) > 16384 or len(flags) != len(options)
            or not required <= flags or not flags <= required | optional):
        raise ValueError(f'{name} has missing, duplicate or unsupported mount options')
    if 'ro' in flags and 'rw' in flags:
        raise ValueError(f'{name} must not combine ro and rw')
    return options


@dataclass(frozen=True)
class Settings:
    values: dict[str, str]
    flags: dict[str, bool]
    peers: list[tuple[str, str]]
    packages: list[str]

    def __getitem__(self, key: str) -> str:
        return self.values[key]

    def enabled(self, key: str) -> bool:
        return self.flags[key]

    @property
    def active(self) -> bool:
        return self.enabled('NFS_SERVER_ENABLE') or self.enabled('NFS_CLIENT_ENABLE')

    @classmethod
    def from_environment(cls, env: Mapping[str, str]) -> 'Settings':
        names = set(BOOLS) | {
            'ACCOUNT_USERNAME', 'ACCOUNT_HOME', 'SYSTEM_DOMAIN', 'NFT_PROFILE', 'NETWORK_SHARING_ROOT_PATH',
            'NFS_SERVER_PATH', 'NETWORK_SHARING_HOME_BIND_PATH', 'NFS_SERVER_APT_DEPS', 'NFS_SERVER_THREADS',
            'NFS_SERVER_PORT', 'NFS_SERVER_RW_OPTIONS', 'NFS_SERVER_RO_OPTIONS',
            'NFS_SERVER_EXPORTS', 'NFS_CLIENT_PATH',
            'NFS_CLIENT_TARGET_IP', 'NFS_CLIENT_EXPORT_PATH', 'NFS_CLIENT_VERSION',
            'NFS_CLIENT_MOUNT_TIMEOUT', 'NFS_CLIENT_APT_DEPS', 'NFS_ACCOUNT_UID', 'NFS_ACCOUNT_GID',
            'NFS_MNT_CLIENT_TARGET_SHARE_OPTS',
            'NFS_SHARED_GROUP', 'NFS_SHARED_GID', 'NFS_INTERFACES', 'NFS_TCP_RMEM',
            'NFS_TCP_WMEM', 'NFS_SOCKET_RMEM_MAX', 'NFS_SOCKET_WMEM_MAX'}
        missing = names - env.keys()
        if missing:
            raise ValueError('missing network sharing settings: ' + ', '.join(sorted(missing)))
        values = {k: env[k] for k in names}
        family = env.get('INSTALLER_ROLE_FAMILY')
        if family not in ('desktop', 'server'):
            raise ValueError('network sharing requires the validated role family')
        values['INSTALLER_ROLE_FAMILY'] = family
        values['NETWORK_SHARING_FIREWALL_FILE'] = (
            '__INSTALLER_PATH_DIR_ETC__/nftables.d/70-managed-server.nft' if family == 'server'
            else '__INSTALLER_PATH_DIR_ETC__/nftables.d/20-filter.nft')
        values['NETWORK_SHARING_FIREWALL_DROPIN_FILE'] = (
            '__INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_NFTABLES_DROPIN__/70-managed-server.conf' if family == 'server'
            else '__INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_NFTABLES_DROPIN__/override.conf')
        for name in BOOLS:
            if values[name] not in ('true', 'false'):
                raise ValueError(f'{name} must be true or false')
        flags = {name: values[name] == 'true' for name in BOOLS}
        if (flags['NFS_SERVER_ENABLE'] or flags['NFS_CLIENT_ENABLE']) and values['NFT_PROFILE'].lower() == 'none':
            raise ValueError('enabled NFS roles require the managed nftables firewall')
        root = normalized_path(values['NETWORK_SHARING_ROOT_PATH'])
        if not any(root.startswith(base + '/') for base in ('__INSTALLER_PATH_DIR_DATA__', '__INSTALLER_PATH_DIR_POOL__', '__INSTALLER_PATH_DIR_SRV__')):
            raise ValueError('sharing root must be below __INSTALLER_PATH_DIR_DATA__, __INSTALLER_PATH_DIR_POOL__ or __INSTALLER_PATH_DIR_SRV__')
        sources = [normalized_path(values[k]) for k in ('NFS_SERVER_PATH', 'NFS_CLIENT_PATH')]
        if any(not p.startswith(root + '/') for p in sources):
            raise ValueError('NFS paths must be strictly below NETWORK_SHARING_ROOT_PATH')
        if any(a == b or a.startswith(b + '/') for a, b in (sources, sources[::-1])):
            raise ValueError('server and client paths must not overlap')
        home = normalized_path(values['ACCOUNT_HOME'])
        if not home.startswith('__INSTALLER_PATH_DIR_HOME__/'):
            raise ValueError('managed account home must be below __INSTALLER_PATH_DIR_HOME__')
        relative = normalized_path(values['NETWORK_SHARING_HOME_BIND_PATH'], relative=True)
        if len(PurePosixPath(relative).parts) != 1 or relative.startswith('.'):
            raise ValueError('sharing home bind must be one dedicated visible directory')
        for local_path in (root, *sources, home + '/' + relative):
            if len(unit_name(local_path)) > 255:
                raise ValueError('sharing path exceeds the escaped systemd unit-name limit')
        for key in ('ACCOUNT_USERNAME', 'NFS_SHARED_GROUP'):
            if not re.fullmatch(r'[a-z_][a-z0-9_-]{0,31}', values[key]) or values[key] in ('root', 'nogroup', 'nobody'):
                raise ValueError(f'invalid {key}')
        bounded_integer(values['NFS_SHARED_GID'], 'NFS_SHARED_GID', 1000, 59999)
        bounded_integer(values['NFS_ACCOUNT_UID'], 'NFS_ACCOUNT_UID', 1000, 59999)
        bounded_integer(values['NFS_ACCOUNT_GID'], 'NFS_ACCOUNT_GID', 1000, 59999)
        if int(values['NFS_SHARED_GID']) == int(values['NFS_ACCOUNT_GID']):
            raise ValueError('NFS_SHARED_GID must be separate from the primary account GID')
        bounded_integer(values['NFS_SERVER_THREADS'], 'NFS_SERVER_THREADS', 1, 128)
        port = bounded_integer(values['NFS_SERVER_PORT'], 'NFS_SERVER_PORT', 1024, 65535)
        if values['NFS_SERVER_PORT'] != str(port):
            raise ValueError('NFS_SERVER_PORT must use canonical decimal notation')
        bounded_integer(values['NFS_CLIENT_MOUNT_TIMEOUT'], 'NFS_CLIENT_MOUNT_TIMEOUT', 5, 120)
        private_ipv4(values['NFS_CLIENT_TARGET_IP'])
        normalized_path(values['NFS_CLIENT_EXPORT_PATH'], allow_root=True)
        if values['NFS_CLIENT_VERSION'] not in ('4.1', '4.2'):
            raise ValueError('only NFSv4.1 and NFSv4.2 are supported')
        values['SYSTEM_DOMAIN'] = values['SYSTEM_DOMAIN'].lower()
        domain = values['SYSTEM_DOMAIN']
        if len('sharing.' + domain) > 253 or not all(re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', label) for label in domain.split('.')):
            raise ValueError('invalid SYSTEM_DOMAIN for the derived NFS identity namespace')
        ifaces = values['NFS_INTERFACES'].split()
        if not ifaces or len(ifaces) > 8 or any(not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]{0,14}', i) or i == 'lo' for i in ifaces):
            raise ValueError('NFS_INTERFACES requires explicit interface names, never wildcards')
        for direction in ('R', 'W'):
            maximum = bounded_integer(values[f'NFS_SOCKET_{direction}MEM_MAX'], 'socket buffer maximum', 262144, 67108864)
            vector = values[f'NFS_TCP_{direction}MEM'].split()
            if len(vector) != 3:
                raise ValueError('TCP buffer values must contain min default max')
            limits = [bounded_integer(v, 'TCP buffer value', 4096, 67108864) for v in vector]
            if limits != sorted(limits) or limits[-1] > maximum:
                raise ValueError('TCP buffers must be ordered and fit within the socket ceiling')
        peers = parse_exports(values['NFS_SERVER_EXPORTS'], values['NFS_SERVER_PATH'])
        for mode in ('RW', 'RO'):
            options = values[f'NFS_SERVER_{mode}_OPTIONS'].split(',')
            if len(set(options)) != len(options) or set(options) != REQUIRED_FLAGS | {mode.lower()}:
                raise ValueError(f'NFS_SERVER_{mode}_OPTIONS must retain the managed export policy')
        network_flags = {'_netdev', 'noauto',
                         'x-systemd.mount-timeout=' + values['NFS_CLIENT_MOUNT_TIMEOUT'] + 's'}
        required = {'hard', 'proto=tcp', 'port=' + values['NFS_SERVER_PORT'], 'resvport', 'sec=sys',
                    'vers=' + values['NFS_CLIENT_VERSION'], 'nosuid', 'nodev', 'noexec', 'nofail',
                    'x-systemd.requires=nfs-client.target', 'x-systemd.requires=nftables.service',
                    'x-systemd.requires=network-sharing-identity.service'} | network_flags
        options = mount_options(values['NFS_MNT_CLIENT_TARGET_SHARE_OPTS'],
                                'NFS_MNT_CLIENT_TARGET_SHARE_OPTS', required, {'ro', 'rw'})
        if not set(options) & {'ro', 'rw'}:
            raise ValueError('NFS_MNT_CLIENT_TARGET_SHARE_OPTS requires ro or rw')
        common = {'nfs-common', 'libnfsidmap1', 'keyutils', 'nftables'}
        server_required = common | {'nfs-kernel-server', 'acl'}
        client_required = set(common)
        server = package_names(values['NFS_SERVER_APT_DEPS'], server_required)
        client = package_names(values['NFS_CLIENT_APT_DEPS'], client_required)
        packages = (server if flags['NFS_SERVER_ENABLE'] else []) + (client if flags['NFS_CLIENT_ENABLE'] else [])
        return cls(values, flags, peers, sorted(set(packages)))


def run(argv: list[str], *, timeout: int = 60) -> None:
    if not hasattr(os, 'pidfd_open') or not hasattr(signal, 'pidfd_send_signal'):
        raise ValueError('target runtime cannot pin an installer child identity')
    child = subprocess.Popen(argv, stdin=subprocess.DEVNULL, env=TOOL_ENV,
                             start_new_session=True)
    pinned = None
    try:
        try:
            pinned = os.pidfd_open(child.pid)
        except OSError:
            retain_uncertainty('child-identity-unavailable')
            raise OutcomeUnknown('child identity unavailable; private recovery evidence retained') from None
        try:
            returncode = child.wait(timeout=timeout)
        except BaseException as error:
            # No context-manager __exit__: its final wait has no deadline.
            # This shell owns the still-unreaped session leader. Signal its
            # group only with that pinned identity and the original PGID/SID.
            if child.returncode is None:
                try:
                    signal.pidfd_send_signal(pinned, 0)
                    if os.getsid(child.pid) != child.pid or os.getpgid(child.pid) != child.pid:
                        raise OutcomeUnknown('child session identity changed')
                    os.killpg(child.pid, signal.SIGKILL)
                except (OSError, OutcomeUnknown):
                    pass
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
            # A direct-child reap cannot prove that a maintainer's detached
            # descendants stopped. Never restore service activation policy or
            # remove its backup merely because the leader was killed.
            retain_uncertainty('child-timeout-or-interruption')
            raise OutcomeUnknown('command outcome unknown; service inhibition and private evidence retained') from error
        if returncode:
            raise subprocess.CalledProcessError(returncode, argv)
    finally:
        if pinned is not None:
            os.close(pinned)


def trusted_parents(path: Path) -> None:
    """Configuration parents must be root-owned real directories, not writable."""
    for parent in reversed(path.parents):
        metadata = parent.lstat()
        sticky_tmp = parent == Path('__INSTALLER_PATH_DIR_TMP__') and stat.S_IMODE(metadata.st_mode) == 0o1777
        if (not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != 0
                or metadata.st_mode & 0o022 and not sticky_tmp):
            raise ValueError(f'untrusted configuration parent: {parent}')


def read_regular(path: Path, *, limit: int = 1024 * 1024) -> str:
    trusted_parents(path)
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    except FileNotFoundError:
        return ''
    with os.fdopen(fd, 'r', encoding='utf-8') as stream:
        metadata = os.fstat(stream.fileno())
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0 or metadata.st_nlink != 1 or metadata.st_mode & 0o022:
            raise ValueError(f'untrusted managed file: {path}')
        data = stream.read(limit + 1)
        if len(data) > limit:
            raise ValueError(f'oversized managed file: {path}')
        return data


def system_directory(path: Path) -> None:
    if path.exists() or path.is_symlink():
        metadata = path.lstat()
        if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != 0 or metadata.st_mode & 0o022:
            raise ValueError(f'unsafe system directory: {path}')
    else:
        system_directory(path.parent)
        path.mkdir(mode=0o755)
        os.chmod(path, 0o755, follow_symlinks=False)
    trusted_parents(path)


def atomic_write(path: Path, text: str, mode: int = 0o644) -> None:
    system_directory(path.parent)
    read_regular(path)  # Reject symlinks, hardlinks, non-regular or writable files.
    fd, name = tempfile.mkstemp(prefix='.network-sharing-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            os.fchmod(stream.fileno(), mode)
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
        dfd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
        try:
            os.fsync(dfd)
        finally:
            os.close(dfd)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def without_managed_block(text: str) -> str:
    if BEGIN not in text and END not in text:
        return text
    if text.count(BEGIN) != 1 or text.count(END) != 1:
        raise ValueError('duplicate or incomplete managed configuration block')
    start, finish = text.index(BEGIN), text.index(END) + len(END)
    if (start >= text.index(END) or (start and text[start-1] != '\n')
            or text[start + len(BEGIN):start + len(BEGIN) + 1] != '\n'
            or (text.index(END) and text[text.index(END)-1] != '\n')
            or (finish < len(text) and text[finish] != '\n')):
        raise ValueError('malformed managed configuration markers')
    if finish < len(text):
        finish += 1
    return text[:start] + text[finish:]


def append_block(text: str, block: str) -> str:
    return text.rstrip('\n') + ('\n\n' if text.strip() else '') + block


def format_fstab(text: str) -> str:
    """Align each commented section; preserve fields/order/comments, omit blank rows."""
    lines = [line for line in text.splitlines() if line.strip()]
    widths: dict[tuple[int, int], int] = {}
    section = 0
    for line in lines:
        if line.lstrip().startswith('#'):
            section += 1
            continue
        fields = line.split(maxsplit=6)
        if len(fields) < 6 or (len(fields) == 7 and not fields[6].startswith('#')):
            raise ValueError('invalid six-field fstab record')
        for field in range(5):
            key = (section, field)
            widths[key] = max(widths.get(key, 0), len(fields[field]))
    result: list[str] = []
    section = 0
    for line in lines:
        if line.lstrip().startswith('#'):
            section += 1
            result.append(line)
            continue
        fields = line.split(maxsplit=6)
        record = '  '.join(fields[i].ljust(widths[section, i]) for i in range(5)) + '  ' + fields[5]
        if len(fields) == 7:
            record += '  ' + fields[6]
        result.append(record)
    return '\n'.join(result) + ('\n' if result else '')


def render(asset: Path, settings: Settings) -> str:
    text = asset.read_text(encoding='utf-8')
    def substitute(match: re.Match[str]) -> str:
        key = match[1]
        if key not in settings.values:
            raise ValueError('unknown network-sharing template variable: ' + key)
        return settings[key]
    result = re.sub(r'__([A-Z][A-Z0-9_]+)__', substitute, text)
    if re.search(r'__[A-Z][A-Z0-9_]+__', result):
        raise ValueError('unresolved network-sharing template')
    return result


def unit_name(path: str, suffix: str = 'mount') -> str:
    """systemd-escape --path equivalent for our validated ASCII path grammar."""
    normalized_path(path)
    escaped = ''.join('/' if c == '/' else (c if c.isalnum() or c in '_.' else f'\\x{ord(c):02x}')
                      for c in path.strip('/'))
    if escaped.startswith('.'):
        escaped = '\\x2e' + escaped[1:]
    return escaped.replace('/', '-') + '.' + suffix


def fstab_entries(s: Settings) -> list[str]:
    root = s['NETWORK_SHARING_ROOT_PATH']
    home = s['ACCOUNT_HOME'] + '/' + s['NETWORK_SHARING_HOME_BIND_PATH']
    # The public destination stays empty offline. Populate a separate backing
    # tree, then bind it here at boot; a populated self-bind produces systemd's
    # nonempty-destination warning on every activation. Keep shared -> rslave
    # propagation so later NFS mounts also appear in the existing home view.
    entries = [f'{storage_root(s)} {root} none bind,shared,nosuid,nodev,noexec 0 0',
               f'{root} {home} none rbind,rslave,nosuid,nodev,noexec,x-systemd.requires-mounts-for={root} 0 0']
    if s.enabled('NFS_CLIENT_ENABLE'):
        opts = s['NFS_MNT_CLIENT_TARGET_SHARE_OPTS'].split(',')
        if s.enabled('NFS_CLIENT_READ_ONLY'):
            opts = ['ro' if option == 'rw' else option for option in opts]
        opts.append('x-systemd.requires-mounts-for=' + root)
        opts.append('x-systemd.requires-mounts-for=' + home)
        entries.append(f"{s['NFS_CLIENT_TARGET_IP']}:{s['NFS_CLIENT_EXPORT_PATH']} {s['NFS_CLIENT_PATH']} nfs {','.join(opts)} 0 0")
    return entries


def public_config(s: Settings) -> dict:
    return {'version': 3, 'profile': s.values, 'peers': s.peers,
            'storage_root': str(storage_root(s)),
            'server_enabled': s.enabled('NFS_SERVER_ENABLE'), 'client_enabled': s.enabled('NFS_CLIENT_ENABLE'),
            'client_mount': unit_name(s['NFS_CLIENT_PATH']),
            'sharing_mount': unit_name(s['NETWORK_SHARING_ROOT_PATH']),
            'sharing_bind_mount': unit_name(s['ACCOUNT_HOME'] + '/' + s['NETWORK_SHARING_HOME_BIND_PATH'])}


def storage_root(s: Settings) -> str:
    root = PurePosixPath(s['NETWORK_SHARING_ROOT_PATH'])
    parent = root.with_name('.' + root.name + '-store')
    if len(os.fsencode(parent.name)) > 255:
        raise ValueError('sharing backing directory name exceeds the filesystem limit')
    return str(parent / 'root')


def storage_path(s: Settings, path: str) -> Path:
    relative = PurePosixPath(path).relative_to(s['NETWORK_SHARING_ROOT_PATH'])
    if not relative.parts or '..' in relative.parts:
        raise ValueError('sharing storage path must be strictly below its public root')
    return Path(storage_root(s)) / relative


def home_bind_bookmarks(s: Settings, *, home: str | None = None) -> str:
    base = 'file://' + (s['ACCOUNT_HOME'] if home is None else home) + '/' + s['NETWORK_SHARING_HOME_BIND_PATH']
    rows = [base + ' Sharing']
    for role in ('SERVER', 'CLIENT'):
        if s.enabled(f'NFS_{role}_ENABLE'):
            rows.append(base + s[f'NFS_{role}_PATH'][len(s['NETWORK_SHARING_ROOT_PATH']):] + ' nfs-' + role.lower())
    return '\n'.join(rows) + '\n'


def primary_account(s: Settings) -> pwd.struct_passwd:
    account = pwd.getpwnam(s['ACCOUNT_USERNAME'])
    if (account.pw_uid in (0, 65534) or account.pw_gid == 65534
            or account.pw_dir != s['ACCOUNT_HOME'] or pwd.getpwuid(account.pw_uid).pw_name != account.pw_name):
        raise ValueError('sharing operator account identity/home mismatch')
    if s.active and (account.pw_uid != int(s['NFS_ACCOUNT_UID']) or account.pw_gid != int(s['NFS_ACCOUNT_GID'])):
        raise ValueError('NFS primary account UID/GID/home mismatch; refusing to renumber AUTH_SYS identities')
    return account


def group_and_account(s: Settings) -> pwd.struct_passwd:
    account = primary_account(s)
    gid = int(s['NFS_SHARED_GID'])
    try:
        existing = grp.getgrnam(s['NFS_SHARED_GROUP'])
    except KeyError:
        try:
            grp.getgrgid(gid)
        except KeyError:
            run(['__INSTALLER_PATH_DIR_USR_SBIN__/groupadd', '--gid', str(gid), s['NFS_SHARED_GROUP']])
        else:
            raise ValueError('NFS_SHARED_GID is already used by another group')
    else:
        if existing.gr_gid != gid or grp.getgrgid(gid).gr_name != s['NFS_SHARED_GROUP']:
            raise ValueError('NFS_SHARED_GROUP has a different GID; refusing to renumber')
    run(['__INSTALLER_PATH_DIR_USR_SBIN__/usermod', '--append', '--groups', s['NFS_SHARED_GROUP'], s['ACCOUNT_USERNAME']])
    return account


def sharing_directory(path: Path, mode: int, gid: int = 0, *, uid: int = 0, empty: bool = False) -> None:
    system_directory(path.parent)
    if path.exists() or path.is_symlink():
        metadata = path.lstat()
        if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid not in (0, uid) or metadata.st_gid not in (0, gid):
            raise ValueError(f'unsafe sharing directory: {path}')
        if empty and any(path.iterdir()):
            raise ValueError(f'refusing to hide nonempty mount destination: {path}')
    else:
        path.mkdir(mode=0o700)
    os.chown(path, uid, gid, follow_symlinks=False)
    os.chmod(path, mode, follow_symlinks=False)


def home_bind_directory(s: Settings, account: pwd.struct_passwd) -> None:
    home = Path(s['ACCOUNT_HOME'])
    trusted_parents(home)
    metadata = home.lstat()
    if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != account.pw_uid or metadata.st_mode & 0o022:
        raise ValueError('home bind requires a real, private account home')
    # Never follow symlinks or recursively chown existing user content. Existing
    # nonempty user-owned parents are refused rather than taking them over.
    current = home
    for component in PurePosixPath(s['NETWORK_SHARING_HOME_BIND_PATH']).parts:
        current /= component
        if current.exists() or current.is_symlink():
            metadata = current.lstat()
            if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != 0 or metadata.st_mode & 0o022:
                raise ValueError(f'home bind requires dedicated root-owned directories: {current}')
        else:
            current.mkdir(mode=0o755)
            os.chown(current, 0, 0)
            os.chmod(current, 0o755, follow_symlinks=False)
        if current.is_symlink():
            raise ValueError('symlink in home bind path')
    if any(current.iterdir()):
        raise ValueError('refusing to cover files in home bind destination')
    # A disconnected client remains navigable, with no ordinary-user writes
    # into the root-owned local placeholder. Mounted access follows server DAC.
    os.chmod(current, 0o755, follow_symlinks=False)


def protect_home_bind_parents(s: Settings) -> None:
    """Prevent the home owner from redirecting persistent root-managed binds.

    Root ownership alone does not stop rename from the user-owned home. Lock
    each dedicated first-level parent only AFTER every endpoint is created.
    This is an offline installer: no target user session may run concurrently.
    Unsupported immutable flags fail before fstab or success publication.
    """
    parent = str(Path(s['ACCOUNT_HOME']) / s['NETWORK_SHARING_HOME_BIND_PATH'])
    run(['__INSTALLER_PATH_DIR_USR_BIN__/chattr', '+i', '--', parent])


@contextmanager
def inhibit_package_services() -> Iterator[None]:
    """Restore exact policy only for a completed child; retain uncertain state."""
    path = Path('__INSTALLER_PATH_DIR_USR_SBIN__/policy-rc.d')
    trusted_parents(path)
    original = path.exists() or path.is_symlink()
    fd, name = tempfile.mkstemp(prefix='.network-sharing-policy-', dir=path.parent)
    os.close(fd)
    backup = Path(name)
    moved = False
    installed = False
    inhibited_identity = None
    try:
        if original:
            os.replace(path, backup)
            moved = True
        atomic_write(path, '#!__INSTALLER_PATH_DIR_BIN__/sh\nexit 101\n', 0o755)
        info = path.lstat()
        inhibited_identity = (info.st_dev, info.st_ino)
        installed = True
        yield
    finally:
        current = path.lstat() if path.exists() or path.is_symlink() else None
        intact = current is not None and (current.st_dev, current.st_ino) == inhibited_identity
        if (RECOVERY.exists() or (installed and not intact)
                or (moved and not installed and current is not None)):
            retain_uncertainty('package-service-policy-retained')
            # Store the concrete backup as private recovery data, never logs.
            atomic_write(RECOVERY.parent / 'service-policy-recovery.json', json.dumps({
                'format': 1, 'path': str(path), 'backup': str(backup) if moved else None,
                'installed_identity': inhibited_identity, 'restore': 'manual-after-child-termination-review'}, sort_keys=True) + '\n', 0o600)
            raise OutcomeUnknown('package service policy recovery is pending; private evidence retained')
        try:
            if moved:
                os.replace(backup, path)
            elif installed:
                path.unlink(missing_ok=True)
            descriptor = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            try:
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
        except OSError as error:
            retain_uncertainty('package-service-policy-restore-failed')
            raise OutcomeUnknown('service policy restoration failed; private evidence retained') from error
        backup.unlink(missing_ok=True)


def server_firewall(s: Settings) -> None:
    """Replace only the profile NFS block in the server-owned table source."""
    if s['INSTALLER_ROLE_FAMILY'] != 'server':
        return
    path = Path(s['NETWORK_SHARING_FIREWALL_FILE'])
    source = read_regular(path)
    begin, end = '# BEGIN profile NFS ACL', '# END profile NFS ACL'
    if source.count(begin) != 1 or source.count(end) != 1 or source.index(begin) >= source.index(end):
        raise ValueError('server firewall has no unique owned NFS policy boundary')
    rows = []
    if s.enabled('NFS_SERVER_ENABLE'):
        interfaces = ', '.join(json.dumps(name) for name in s['NFS_INTERFACES'].split())
        peers = ', '.join(network for network, _ in s.peers)
        rows.append(f'    iifname {{ {interfaces} }} tcp dport {s["NFS_SERVER_PORT"]} ip saddr {{ {peers} }} accept')
    # NFSv4 uses TCP only. No unapproved physical interface, IPv6, wildcard,
    # rpcbind or UDP listener becomes reachable by enabling a profile.
    rows.extend((f'    tcp dport {s["NFS_SERVER_PORT"]} drop',
                 f'    udp dport {s["NFS_SERVER_PORT"]} drop'))
    start = source.index(begin) + len(begin)
    stop = source.index(end)
    atomic_write(path, source[:start] + '\n' + '\n'.join(rows) + '\n    ' + source[stop:], 0o600)


def configure(s: Settings, assets: Path, payload_defaults: Path | None = None) -> None:
    if s['INSTALLER_ROLE_FAMILY'] == 'desktop':
        if (payload_defaults is None or not payload_defaults.is_absolute()
                or payload_defaults.resolve(strict=True) != payload_defaults):
            raise ValueError('private primary payload defaults path is required')
        system_directory(payload_defaults)
        if stat.S_IMODE(payload_defaults.stat().st_mode) != 0o700:
            raise ValueError('primary payload defaults must remain private')
    # Reject changed-role reruns: this is an offline installer, not a live
    # reconfiguration tool. Never silently leave stale exports/mounts enabled.
    config_path = Path('__INSTALLER_PATH_DIR_ETC_NETWORK_SHARING__/config.json')
    system_directory(config_path.parent)
    old = read_regular(config_path)
    previous = json.loads(old) if old else None
    if old and (not isinstance(previous, dict) or previous.get('version') != 3
                or previous.get('profile') != s.values or previous.get('storage_root') != str(storage_root(s))):
        raise ValueError('network sharing is already configured differently; rebuild/reinstall or follow the administrator migration procedure')
    root = Path(s['NETWORK_SHARING_ROOT_PATH'])
    system_directory(root)
    if any(root.iterdir()):
        raise ValueError('refusing to hide nonempty public sharing mount destination')
    backing = Path(storage_root(s))
    if backing.parent.exists() or backing.parent.is_symlink():
        system_directory(backing.parent)
        if previous is None or stat.S_IMODE(backing.parent.lstat().st_mode) != 0o700:
            raise ValueError('sharing backing directory already exists without matching private installer ownership')
    else:
        # The private parent prevents bypassing nosuid/nodev/noexec through
        # the unmounted source path; the public bind exposes only its 0755 root.
        system_directory(backing.parent.parent)
        backing.parent.mkdir(mode=0o700)
        os.chmod(backing.parent, 0o700, follow_symlinks=False)
    system_directory(backing)
    entries = fstab_entries(s)
    fstab = without_managed_block(read_regular(Path('__INSTALLER_PATH_DIR_ETC__/fstab')))
    destinations = {entry.split()[1] for entry in entries}
    for line in fstab.splitlines():
        parts = line.split()
        if len(parts) > 1 and not line.lstrip().startswith('#'):
            # fstab allows octal escapes; the generator also canonicalizes ./,
            # ../ and repeated slashes. Reject aliases before writing a second
            # definition of the same unit, without probing remote mount paths.
            destination = re.sub(r'\\([0-7]{3})', lambda m: chr(int(m[1], 8)), parts[1])
            if destination.startswith('/'):
                destination = os.path.normpath('/' + destination.lstrip('/'))
            if destination in destinations:
                raise ValueError('an unmanaged fstab entry already owns an NFS mount destination')
    # Validate export ownership before package installation or export mutation.
    exports = ''
    if s.enabled('NFS_SERVER_ENABLE'):
        exports = without_managed_block(read_regular(Path('__INSTALLER_PATH_DIR_ETC__/exports')))
        if any(line.strip() and not line.lstrip().startswith('#') for line in exports.splitlines()):
            raise ValueError('existing unmanaged exports require administrator review')
        exports_dir = Path('__INSTALLER_PATH_DIR_ETC__/exports.d')
        if exports_dir.exists() or exports_dir.is_symlink():
            system_directory(exports_dir)
            for other in exports_dir.glob('*.exports'):
                if any(line.strip() and not line.lstrip().startswith('#') for line in read_regular(other).splitlines()):
                    raise ValueError('unmanaged exports.d entries conflict with the dedicated NFSv4 policy')
    account = primary_account(s)
    server_firewall(s)
    home_bind_directory(s, account)
    protect_home_bind_parents(s)
    if s['INSTALLER_ROLE_FAMILY'] == 'desktop':
        for path, bookmarks in (
                (payload_defaults / '.config/gtk-3.0/bookmarks', home_bind_bookmarks(s)),
                (Path('__INSTALLER_PATH_DIR_ETC_SKEL_DESKTOP_CONFIG__/gtk-3.0/bookmarks'),
                 home_bind_bookmarks(s, home='$HOME'))):
            system_directory(path.parent)
            lines = read_regular(path).splitlines()
            for line in bookmarks.splitlines():
                if line.split()[0] not in {row.split()[0] for row in lines if row.strip()}:
                    lines.append(line)
            atomic_write(path, '\n'.join(lines) + '\n')
    if s.active:
        # primary_account already checked AUTH_SYS numeric credentials before
        # preparing the home view; NFSv4 name mapping cannot replace that check.
        overrides = Path('__INSTALLER_PATH_DIR_ETC__/idmapd.conf.d')
        if overrides.exists() or overrides.is_symlink():
            system_directory(overrides)
            for other in overrides.glob('*.conf'):
                if any(line.strip() and not line.lstrip().startswith(('#', ';')) for line in read_regular(other).splitlines()):
                    raise ValueError('unmanaged idmapd.conf.d settings conflict with the dedicated NFS identity policy')
        if s.enabled('NFS_SERVER_ENABLE'):
            # Package maintscripts may enable a unit even while policy-rc.d
            # blocks starts. Install the boot-time completion guards first.
            name = 'etc/systemd/system/nfs-server.service.d/60-network-sharing.conf.tmpl'
            atomic_write(Path('__INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_NFS_SERVER_DROPIN__/60-network-sharing.conf'),
                         render(assets / name, s))
        with inhibit_package_services():
            run(['__INSTALLER_PATH_DIR_USR_BIN__/apt-get', '-o', 'Acquire::Retries=3', '-o', 'Acquire::http::Timeout=45',
                 '-o', 'Acquire::https::Timeout=45', '-o', 'DPkg::Lock::Timeout=60', '-o', 'DPkg::Use-Pty=0',
                 '-y', '--no-install-recommends', '--no-install-suggests', 'install', *s.packages], timeout=1800)
        account = group_and_account(s)
        for name in ('etc/idmapd.conf.tmpl', 'etc/sysctl.d/60-network-sharing.conf.tmpl',
                     'etc/systemd/system/network-sharing-report.service.tmpl',
                     'etc/systemd/system/network-sharing-identity.service'):
            atomic_write(Path('/') / name.removesuffix('.tmpl'), render(assets / name, s))
        atomic_write(Path('__INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/network-sharing-report'),
                     (assets / 'usr/local/libexec/network-sharing-report').read_text(), 0o755)
        atomic_write(Path('__INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/network-sharing-identity'),
                     (assets / 'usr/local/libexec/network-sharing-identity').read_text(), 0o755)
        modules = ['sunrpc']
        options = ['# Managed NFSv4 name mapping (AUTH_SYS still uses numeric credentials).']
        if s.enabled('NFS_CLIENT_ENABLE'):
            modules += ['nfs', 'nfsv4']
            options.append('options nfs nfs4_disable_idmapping=0')
            # Configure Debian's exact id_resolver handler; preserve other
            # request-key handlers (including DNS and GSS entries).
            atomic_write(Path('__INSTALLER_PATH_DIR_ETC__/request-key.d/id_resolver.conf'),
                         '# Managed NFSv4 identity upcall\ncreate id_resolver * * __INSTALLER_PATH_DIR_USR_SBIN__/nfsidmap -t 600 %k %d\n')
            sharing_directory(storage_path(s, s['NFS_CLIENT_PATH']), 0o755, empty=True)
        if s.enabled('NFS_SERVER_ENABLE'):
            modules.append('nfsd')
            options.append('options nfsd nfs4_disable_idmapping=0')
            sharing_directory(storage_path(s, s['NFS_SERVER_PATH']), 0o2770, int(s['NFS_SHARED_GID']), uid=account.pw_uid)
            # Replace, do not merge: inherited named ACLs must not grant extra
            # access. Only the export root is managed, never existing children.
            run(['__INSTALLER_PATH_DIR_USR_BIN__/setfacl', '--set',
                 'u::rwx,g::rwx,o::---,d:u::rwx,d:g::rwx,d:m::rwx,d:o::---',
                 '--', str(storage_path(s, s['NFS_SERVER_PATH']))])
            atomic_write(Path('__INSTALLER_PATH_DIR_ETC__/exports'), append_block(exports, render(assets / 'etc/exports.tmpl', s)))
            for name, destination in (
                    ('etc/nfs.conf.d/60-network-sharing.conf.tmpl', '__INSTALLER_PATH_DIR_ETC__/nfs.conf.d/60-network-sharing.conf'),
                    ('etc/systemd/system/nfs-mountd.service.d/60-network-sharing.conf', '__INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_NFS_MOUNTD_DROPIN__/60-network-sharing.conf'),
                    ('etc/systemd/system/nfs-idmapd.service.d/60-network-sharing.conf', '__INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_NFS_IDMAPD_DROPIN__/60-network-sharing.conf')):
                atomic_write(Path(destination), render(assets / name, s))
        atomic_write(Path('__INSTALLER_PATH_DIR_MODULES_LOAD__/60-network-sharing.conf'), '\n'.join(modules) + '\n')
        atomic_write(Path('__INSTALLER_PATH_DIR_MODPROBE_D__/60-network-sharing.conf'), '\n'.join(options) + '\n')
        if s.enabled('NFS_CLIENT_ENABLE'):
            atomic_write(Path('__INSTALLER_PATH_DIR_SYSTEMD_SYSTEM__') / (unit_name(s['NFS_CLIENT_PATH']) + '.d') / '60-network-sharing.conf',
                         '[Unit]\nBindsTo=nftables.service\nAfter=nftables.service\n')
        # Deliberately v4-only; these RPC listeners are not needed for this role.
        run(['__INSTALLER_PATH_DIR_USR_BIN__/systemctl', '--root=/', 'mask', 'rpcbind.service', 'rpcbind.socket',
             'rpc-statd.service', 'rpc-statd-notify.service'])
        if s.enabled('NFS_CLIENT_ENABLE'):
            run(['__INSTALLER_PATH_DIR_USR_BIN__/systemctl', '--root=/', 'enable', 'nfs-client.target'])
        if s.enabled('NFS_SERVER_ENABLE'):
            run(['__INSTALLER_PATH_DIR_USR_BIN__/systemctl', '--root=/', 'enable', 'nfs-server.service'])
    if entries:
        sharing_rows = ['# Sharing bind mounts', *entries[:2]]
        if len(entries) > 2:
            sharing_rows.extend(['# Remote NFS mount (started explicitly by nfsmnt)', *entries[2:]])
        fstab = append_block(fstab, BEGIN + '\n' + '\n'.join(sharing_rows) + '\n' + END + '\n')
        atomic_write(Path('__INSTALLER_PATH_DIR_ETC__/fstab'), format_fstab(fstab))
    # Version 3 has one shared root and one persistent home view. Older
    # configuration is rejected rather than silently reactivating path triggers.
    atomic_write(config_path, json.dumps(public_config(s), indent=2, sort_keys=True) + '\n')
    print('Network sharing configured: server=' + str(s.enabled('NFS_SERVER_ENABLE')).lower()
          + ' client=' + str(s.enabled('NFS_CLIENT_ENABLE')).lower() + ' root=' + str(root))


def main(argv: list[str]) -> int:
    if os.getuid() != 0 or os.geteuid() != 0 or len(argv) != 2:
        raise ValueError('usage (installer chroot, root only): network-sharing.py ASSET_DIRECTORY PAYLOAD_DEFAULTS')
    assets = Path(argv[0])
    if not assets.is_absolute() or not assets.is_dir() or assets.is_symlink():
        raise ValueError('assets must be an existing absolute directory')
    settings = Settings.from_environment(os.environ)
    configure(settings, assets, Path(argv[1]))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main(sys.argv[1:]))
    except OutcomeUnknown:
        print('network-sharing: outcome=unknown; retain private staging and service-policy recovery evidence', file=sys.stderr)
        raise SystemExit(76)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print('network-sharing: ' + str(error), file=sys.stderr)
        raise SystemExit(1)
