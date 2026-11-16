#!/usr/bin/python3 -I
"""Render a private copy of the authenticated payload before preseed/late_command.

The installer supplies validated maps once. No environment is sourced, no
program is imported from the payload, and no target service is activated.
Caller-specific scalar/block inputs remain the responsibility of their typed
publication adapters; account skeletons must remain reusable for future users.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
import time

FILE_LIMIT = 16 * 1024 * 1024
BYTE_LIMIT = 256 * 1024 * 1024
MEMBER_LIMIT = 10000
ENTRY_LIMIT = 20000
KEY = re.compile(rb'[A-Z][A-Z0-9_]*\Z')
PATH_TOKEN = re.compile(rb'__INSTALLER_(PATH_[A-Z0-9]+(?:_[A-Z0-9]+)*|APPARMOR_PROFILE_[A-Z0-9]+(?:_[A-Z0-9]+)*)__')
LOG_TOKEN = re.compile(rb'__INSTALLER_(LOG_[A-Z0-9]+(?:_[A-Z0-9]+)*)__')
THEME_TOKEN = re.compile(rb'__THEME_([A-Z0-9]+(?:_[A-Z0-9]+)*)__')
SCALAR_TOKEN = re.compile(rb'__INSTALLER_([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*)__')
BINARY_SUFFIXES = frozenset(('.png', '.jpg', '.jpeg', '.webp', '.gif', '.ico', '.ttf',
                             '.otf', '.woff', '.woff2', '.gz', '.xz', '.bz2', '.zip', '.deb'))


def read_regular(path: Path, maximum: int = FILE_LIMIT) -> bytes:
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    with os.fdopen(descriptor, 'rb') as stream:
        before = os.fstat(stream.fileno())
        if (not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or
                before.st_uid != os.geteuid() or before.st_mode & 0o022 or
                not 0 <= before.st_size <= maximum):
            raise ValueError('unsafe or excessive render input: ' + str(path))
        data = stream.read(maximum + 1)
        after = os.fstat(stream.fileno())
        identity = lambda info: (info.st_dev, info.st_ino, info.st_mode, info.st_nlink,
                                 info.st_uid, info.st_gid, info.st_size, info.st_mtime_ns, info.st_ctime_ns)
        if len(data) != before.st_size or identity(before) != identity(after):
            raise ValueError('render input changed during reading: ' + str(path))
        return data


def value_map(path: Path) -> dict[bytes, bytes]:
    values: dict[bytes, bytes] = {}
    for line in read_regular(path, 1024 * 1024).splitlines():
        key, separator, value = line.partition(b'=')
        if not separator or not KEY.fullmatch(key) or key in values or b'\0' in value:
            raise ValueError('malformed or duplicate render-map key')
        values[key] = value
    return values


def relative(value: str) -> str:
    if (not value or value.startswith('/') or
            any(part in ('', '.', '..') for part in value.split('/'))):
        raise ValueError('render source selector must be relative and normalized')
    return value


def manifest_records(path: Path) -> dict[str, tuple[int, str]]:
    lines = read_regular(path, 4 * 1024 * 1024).decode('utf-8').splitlines()
    if not lines or lines[0] != 'format=3':
        raise ValueError('invalid payload manifest format')
    records = {}
    total = 0
    for line in lines[1:]:
        fields = line.split('\t')
        if len(fields) != 3 or not fields[0].isdecimal() or not re.fullmatch(r'[a-f0-9]{64}', fields[1]):
            raise ValueError('invalid payload manifest row')
        size, digest, member = int(fields[0]), fields[1], relative(fields[2])
        total += size
        if size > FILE_LIMIT or total > BYTE_LIMIT or len(records) >= MEMBER_LIMIT or member in records:
            raise ValueError('excessive or duplicate payload manifest member')
        records[member] = (size, digest)
    return records


def substitute(data: bytes, pattern: re.Pattern[bytes], values: dict[bytes, bytes]) -> bytes:
    def replacement(match: re.Match[bytes]) -> bytes:
        key = match[1]
        if key not in values:
            raise ValueError('missing render field: ' + key.decode('ascii'))
        return values[key]
    return pattern.sub(replacement, data)


def theme_bytes(data: bytes, values: dict[bytes, bytes], target_source: str,
                *, defaults_only: bool = False) -> bytes:
    def replacement(match: re.Match[bytes]) -> bytes:
        key = match[1]
        if key.startswith(b'TARGET_PATH_'):
            value = values[key.removeprefix(b'TARGET_PATH_')]
            prefix = target_source.encode() + b'/'
            if not value.startswith(prefix) or b'..' in value.split(b'/'):
                raise ValueError('theme target path is outside its source tree')
            return b'/' + value.removeprefix(prefix)
        if key not in values:
            raise ValueError('unknown theme field: ' + key.decode('ascii'))
        return values[key]
    if defaults_only:
        # Registry mappings and token lists are executable editor metadata.
        # Only defaults consume theme values, exactly as in theme-render.awk.
        lines = []
        field = b''
        count = 0
        for line in data.splitlines(keepends=True):
            key = re.fullmatch(rb'\s*"key": "([A-Z][A-Z0-9_]*)",\s*', line)
            if key:
                field = key[1]
            if re.match(rb'\s*"default"\s*:', line):
                match = re.fullmatch(rb'\s*"default": "__THEME_([A-Z0-9_]+)__",\s*', line)
                if not match or match[1] != field:
                    raise ValueError('invalid appearance default template')
                line = THEME_TOKEN.sub(replacement, line)
                count += 1
            lines.append(line)
        if not 0 < count <= 1024:
            raise ValueError('invalid appearance default count')
        return b''.join(lines)
    rendered = THEME_TOKEN.sub(replacement, data)
    if b'__THEME_' in rendered:
        raise ValueError('malformed or unresolved theme token')
    return rendered


def render_tree(root: Path, paths: dict[bytes, bytes], logging: dict[bytes, bytes],
                themes: dict[bytes, bytes], selectors: dict[str, str]) -> dict:
    started = time.monotonic()
    for parent in (*reversed(root.parents), root):
        info = parent.lstat()
        if not stat.S_ISDIR(info.st_mode):
            raise ValueError('indirect staging ancestry')
    if root.stat().st_uid != os.geteuid() or root.stat().st_mode & 0o077:
        raise ValueError('render workspace must be private and owned')
    source = root / 'source'
    info = source.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o022:
        raise ValueError('unsafe copied source root')
    expected = manifest_records(root / 'inputs/payload.manifest')
    seen: set[str] = set()
    script_prefix = selectors['scripts'] + '/'
    target_prefix = selectors['target'] + '/'
    logged = tuple(selectors[key] + '/' for key in ('target', 'late', 'desktop', 'firstboot'))
    themed = tuple(selectors[key] + '/' for key in ('target', 'desktop', 'firstboot'))
    appearance = selectors['appearance-python'] + '/'
    registry = selectors['appearance-registry']
    entries = members = total = rendered_count = rendered_bytes = 0
    fingerprints = hashlib.sha256()
    # Walk once, with aggregate limits enforced during traversal, not after a
    # recursive list has already allocated unbounded memory or inode metadata.
    for parent, directories, files in os.walk(source, followlinks=False):
        if len(Path(parent).relative_to(source).parts) > 64:
            raise ValueError('render tree exceeds depth limit')
        directories.sort()
        files.sort()
        for name in (*directories, *files):
            path = Path(parent) / name
            entries += 1
            if entries > ENTRY_LIMIT:
                raise ValueError('render tree exceeds entry limit')
            info = path.lstat()
            if (info.st_uid != os.geteuid() or info.st_mode & 0o022 or
                    not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode))):
                raise ValueError('unsafe render-tree member: ' + str(path))
        for name in files:
            path = Path(parent) / name
            member = path.relative_to(source).as_posix()
            size = path.lstat().st_size
            members += 1
            total += size
            if members > MEMBER_LIMIT or total > BYTE_LIMIT or size > FILE_LIMIT:
                raise ValueError('render tree exceeds input limits')
            data = read_regular(path)
            if expected.get(member) != (len(data), hashlib.sha256(data).hexdigest()):
                raise ValueError('copied source differs from authenticated manifest: ' + member)
            seen.add(member)
            if not member.startswith((script_prefix, target_prefix)) or path.suffix in BINARY_SUFFIXES:
                fingerprints.update(member.encode() + b'\0' + hashlib.sha256(data).digest())
                continue
            if b'\0' in data:
                fingerprints.update(member.encode() + b'\0' + hashlib.sha256(data).digest())
                continue
            try:
                result = substitute(data, PATH_TOKEN, paths)
                if member.startswith(logged):
                    result = substitute(result, LOG_TOKEN, logging)
                if ((THEME_TOKEN.search(result) or member.startswith(target_prefix) and b'__THEME_' in result)
                        and member.startswith(themed) and
                        not (member.startswith(appearance) and member.endswith('.py'))):
                    result = theme_bytes(result, themes, selectors['target'], defaults_only=member == registry)
            except (ValueError, KeyError) as error:
                raise ValueError(member + ': ' + str(error)) from error
            rendered_bytes += len(result)
            if len(result) > FILE_LIMIT or rendered_bytes > BYTE_LIMIT:
                raise ValueError('render output exceeds byte limit')
            if result != data:
                # The entire candidate is private until the finish hook's one
                # rename. No consumer can observe these in-place writes.
                descriptor = os.open(path, os.O_WRONLY | os.O_TRUNC | os.O_NOFOLLOW | os.O_CLOEXEC)
                with os.fdopen(descriptor, 'wb') as stream:
                    stream.write(result)
                rendered_count += 1
            fingerprints.update(member.encode() + b'\0' + hashlib.sha256(result).digest())
    if seen != expected.keys():
        raise ValueError('copied payload is missing manifest members')
    return {'format': 1, 'members': members, 'input_bytes': total,
            'rendered_files': rendered_count, 'rendered_bytes': rendered_bytes,
            'rendered_sha256': fingerprints.hexdigest(),
            'duration_seconds': round(time.monotonic() - started, 3)}


def owned_directory(path: Path) -> None:
    if not path.is_absolute() or '..' in path.parts:
        raise ValueError('publication root must be absolute and normalized')
    for parent in (*reversed(path.parents), path):
        try:
            info = parent.lstat()
        except FileNotFoundError:
            parent.mkdir(mode=0o755)
            parent.chmod(0o755)
            info = parent.lstat()
        if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o022):
            raise ValueError('untrusted publication ancestry: ' + str(parent))


def publish_perl(root: Path, catalog: str, destination: Path, family: str, snapshots: bool) -> int:
    """Publish the existing class-owned Perl inventory as complete namespaces."""
    if family not in ('desktop', 'server'):
        raise ValueError('invalid target role family')
    values = value_map(root / 'inputs/perl.map')
    assets: dict[str, bytes] = {}
    publications: list[tuple[str, str]] = []
    total = 0
    for line in read_regular(root / 'source' / relative(catalog), 1024 * 1024).decode().splitlines():
        fields = line.split('\t')
        if len(fields) != 3 or fields[2] not in ('common', 'desktop', 'server'):
            raise ValueError('invalid shared Perl inventory row')
        source, target, owner = relative(fields[0]), relative(fields[1]), fields[2]
        if owner not in ('common', family) or not snapshots and target.startswith('timeshift/'):
            continue
        if '/' not in target or not target.endswith('.pm') or target in assets:
            raise ValueError('invalid or duplicate Perl namespace member')
        data = substitute(read_regular(root / 'source' / source), SCALAR_TOKEN, values)
        total += len(data)
        if len(data) > FILE_LIMIT or total > BYTE_LIMIT or len(assets) >= MEMBER_LIMIT:
            raise ValueError('shared Perl publication exceeds bounds')
        assets[target] = data
        publications.append((source, target))
    if not assets:
        raise ValueError('empty selected shared Perl inventory')
    # All bytes and source identities are validated before creating any final
    # namespace. One ancestry check replaces one shell walk per module.
    owned_directory(destination)
    namespaces = sorted({target.split('/', 1)[0] for target in assets})
    for name in namespaces:
        if (destination / name).exists() or (destination / name).is_symlink():
            raise ValueError('refusing to replace a pre-existing Perl namespace: ' + name)
    with tempfile.TemporaryDirectory(prefix='.installer-perl-', dir=destination) as temporary:
        work = Path(temporary)
        directories: set[Path] = set()
        for target, data in assets.items():
            output = work / target
            output.parent.mkdir(parents=True, exist_ok=True)
            directories.update(parent for parent in output.parents if parent != work and work in parent.parents)
            with output.open('xb') as stream:
                stream.write(data)
            output.chmod(0o644)
        for directory in directories:
            directory.chmod(0o755)
        for name in namespaces:
            os.rename(work / name, destination / name)
    with (root / 'inputs/published-assets.tsv').open('x', encoding='utf-8') as stream:
        for source, target in publications:
            stream.write(source + '\t' + str(destination / target) + '\t0644\n')
    return len(assets)


def cleanup_workspace(root: Path) -> None:
    """Remove only a completed private workspace after all late owners exit."""
    if not root.is_absolute() or '..' in root.parts:
        raise ValueError('cleanup workspace must be absolute and normalized')
    for parent in (*reversed(root.parents), root):
        info = parent.lstat()
        if not stat.S_ISDIR(info.st_mode):
            raise ValueError('indirect cleanup ancestry')
    info = root.lstat()
    if info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError('cleanup requires a private owned workspace')
    if {child.name for child in root.iterdir()} != {'source', 'inputs', 'identity', 'render.py', 'receipt.json'}:
        raise ValueError('cleanup workspace inventory differs')
    receipt = json.loads(read_regular(root / 'receipt.json', 65536))
    if receipt.get('format') != 1 or not re.fullmatch(r'[a-f0-9]{64}', receipt.get('rendered_sha256', '')):
        raise ValueError('cleanup requires a completed render receipt')
    files: list[Path] = []
    directories: list[Path] = []
    for parent, children, names in os.walk(root, followlinks=False):
        for name in children + names:
            path = Path(parent) / name
            info = path.lstat()
            if info.st_uid != os.geteuid() or info.st_mode & 0o022:
                raise ValueError('cleanup member ownership or mode differs')
            if stat.S_ISREG(info.st_mode) and info.st_nlink == 1:
                files.append(path)
            elif stat.S_ISDIR(info.st_mode):
                directories.append(path)
            else:
                raise ValueError('cleanup member is indirect or special')
            if len(files) + len(directories) > ENTRY_LIMIT + 32:
                raise ValueError('cleanup inventory exceeds limit')
    for path in files:
        path.unlink()
    for path in sorted(directories, key=lambda item: len(item.parts), reverse=True):
        path.rmdir()
    root.rmdir()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('workspace', type=Path)
    parser.add_argument('--cleanup', action='store_true')
    parser.add_argument('--perl-assets', type=relative)
    parser.add_argument('--perl-root', type=Path)
    parser.add_argument('--family', choices=('desktop', 'server'))
    parser.add_argument('--snapshots', choices=('true', 'false'))
    for name in ('scripts', 'target', 'late', 'desktop', 'firstboot',
                 'appearance-python', 'appearance-registry'):
        parser.add_argument('--' + name, type=relative)
    args = parser.parse_args()
    os.umask(0o077)
    try:
        if args.cleanup:
            cleanup_workspace(args.workspace)
            print('completed target rendering workspace removed')
            return 0
        maps = args.workspace / 'inputs'
        selectors = {name.replace('_', '-'): value for name, value in vars(args).items()
                     if name not in ('workspace', 'cleanup', 'perl_assets', 'perl_root', 'family', 'snapshots')}
        if any(value is None for value in selectors.values()):
            raise ValueError('all source selectors are required for rendering')
        report = render_tree(args.workspace, value_map(maps / 'paths.map'),
                             value_map(maps / 'logging.map'), value_map(maps / 'themes.map'), selectors)
        if not all((args.perl_assets, args.perl_root, args.family, args.snapshots)):
            raise ValueError('shared Perl publication requires its explicit inventory and target policy')
        report['published_perl_files'] = publish_perl(args.workspace, args.perl_assets, args.perl_root,
                                                     args.family, args.snapshots == 'true')
        with (args.workspace / 'receipt.json').open('x', encoding='utf-8') as stream:
            json.dump(report, stream, sort_keys=True)
            stream.write('\n')
        print('prepared target payload: ' + json.dumps(report, sort_keys=True))
        return 0
    except (OSError, ValueError, KeyError) as error:
        print('target payload rendering failed: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
