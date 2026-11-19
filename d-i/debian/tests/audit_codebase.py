#!/usr/bin/env python3
"""Inventory and native syntax checks inside the prepared private test image.

Run in a disposable Linux environment with Python 3.11+, Perl and a POSIX shell:
  python3 -B d-i/debian/tests/audit_codebase.py --source-only --output audit.json
  python3 -B d-i/debian/tests/audit_codebase.py --perl-only --prepare-suite forky --output perl.json
Perl -c can execute BEGIN blocks and imports. The isolation guard is mandatory.
Missing tools, dependencies and required template rendering fail the check.
Use --perl-only for the full-program Perl preflight, including the shared
installer renderer. Pure build serialization never calls this validator.
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

import argparse
import ast
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import shutil
import signal
import stat
import sys
import tempfile
import tomllib
import xml.etree.ElementTree as ET
from isolation import fixture_environment

# A copied source-classification fixture still uses the canonical, guarded
# process owner. No helper from an installed target tree is imported.
sys.path.insert(0, '/workspace/repository/tools')
from stage_process import CleanupUnknown, run_stage
sys.path.pop(0)

ROOT = Path(__file__).resolve().parents[3]
SCOPE_NAMES = ('hooks/target', 'hooks/installer', 'scripts', 'hosts')
REQUIRED_SCOPES = tuple('d-i/debian/' + name for name in SCOPE_NAMES) + (
    'd-i/forky/hooks/target', 'd-i/trixie/hooks/target')
SYNTAX_TIMEOUT = 10
SYNTAX_OUTPUT_LIMIT = 64 * 1024
SOURCE_FILE_LIMIT = 16 * 1024 * 1024
SOURCE_TREE_LIMIT = 256 * 1024 * 1024
SOURCE_MEMBER_LIMIT = 10000
INSTALLER_TOKEN = re.compile(rb'__INSTALLER_[A-Z][A-Z0-9_]*__')
PLACEHOLDER = re.compile(r'__[A-Z][A-Z0-9_]+__')
UNIT_SUFFIXES = ('.service', '.socket', '.target', '.timer', '.path', '.slice', '.mount')


def files_under(path: Path) -> set[Path]:
    if path.is_symlink():
        raise ValueError(f'source scope must not be a symlink: {path}')
    if path.is_file():
        return {path}
    return {p for p in path.rglob('*') if p.is_file() and not p.is_symlink()
            and '__pycache__' not in p.parts}


def source_scopes(root: Path) -> dict[str, set[Path]]:
    """Shared implementations and both suites' actual overlays have one owner."""
    names = set(REQUIRED_SCOPES)
    for suite in ('forky', 'trixie'):
        for suffix in SCOPE_NAMES:
            name = f'd-i/{suite}/{suffix}'
            if (root / name).exists():
                names.add(name)
    scopes = {}
    for name in sorted(names):
        path = root / name
        if not path.is_dir() or path.is_symlink():
            raise ValueError(f'missing or invalid expected source scope: {name}')
        entries = files_under(path)
        if not entries:
            raise ValueError(f'empty expected source scope: {name}')
        scopes[name] = entries
    renderer = root / 'd-i/debian/scripts/common/render.pl'
    if renderer not in scopes['d-i/debian/scripts'] or renderer.stat().st_size == 0:
        raise ValueError('missing or empty shared installer renderer')
    return scopes


def perl_library_paths(root: Path) -> list[Path]:
    """Use physical component roots beneath each shared target role."""
    result = []
    for owner in ('debian', 'forky', 'trixie'):
        for role in ('common', 'desktop', 'server'):
            base = root / f'd-i/{owner}/hooks/target/usr/local/lib/{role}/perl5/site_perl'
            if base.is_symlink():
                raise ValueError(f'Perl library root must not be a symlink: {base}')
            if base.is_dir():
                result.extend(path for path in sorted(base.iterdir())
                              if path.is_dir() and not path.is_symlink())
    return result


def is_perl(path: Path, first: str) -> bool:
    return ((first.startswith('#!') and re.search(r'\bperl\b', first) is not None)
            or path.name.removesuffix('.tmpl').endswith(('.pm', '.pl', '.t')))


def perl_shebang_flags(first: str) -> list[str]:
    if not first.startswith('#!'):
        return []
    match = re.fullmatch(r'#!\S*/perl(?:[ \t]+(-T))?[ \t]*', first)
    if match is None:
        raise ValueError(f'unsupported Perl shebang flags: {first!r}')
    return [match[1]] if match[1] else []


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def private_path(path: Path) -> Path:
    path = path.absolute()
    if path != path.resolve() or not path.is_relative_to('/workspace'):
        raise ValueError(f'input must be a direct private workspace path: {path}')
    return path


def read_regular(path: Path, limit: int = SOURCE_FILE_LIMIT) -> bytes:
    path = private_path(path)
    descriptor = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, 'rb') as stream:
        info = os.fstat(stream.fileno())
        if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.geteuid()
                or info.st_mode & 0o022 or info.st_size > limit):
            raise ValueError(f'unsafe or oversized private source file: {path}')
        data = stream.read(limit + 1)
        after = os.fstat(stream.fileno())
        named = path.lstat()
    fields = ('st_dev', 'st_ino', 'st_mode', 'st_uid', 'st_gid', 'st_nlink',
              'st_size', 'st_mtime_ns', 'st_ctime_ns')
    identity = tuple(getattr(info, field) for field in fields)
    if (len(data) != info.st_size or identity != tuple(getattr(after, field) for field in fields)
            or identity != tuple(getattr(named, field) for field in fields)):
        raise ValueError(f'private source changed while reading: {path}')
    return data


def member_name(value: str) -> str:
    if (not isinstance(value, str) or len(value) > 4096
            or not re.fullmatch(r'[A-Za-z0-9_./@+ -]+', value)
            or value.startswith('/') or any(part in {'', '.', '..'} for part in value.split('/'))):
        raise ValueError('invalid captured source member')
    return value


def source_member(path: Path) -> str:
    relative = path.relative_to(ROOT).as_posix()
    if relative.startswith('d-i/debian/'):
        return member_name(relative.removeprefix('d-i/debian/'))
    for suite in ('forky', 'trixie'):
        prefix = f'd-i/{suite}/'
        if relative.startswith(prefix):
            return member_name(f'frontends/{suite}/' + relative.removeprefix(prefix))
    raise ValueError(f'no captured source owner for {relative}')


def captured_manifest(path: Path) -> tuple[bytes, dict[str, tuple[int, str]]]:
    data = read_regular(path, 4 * 1024 * 1024)
    lines = data.decode('ascii').splitlines()
    if not lines or lines.pop(0) != 'format=3':
        raise ValueError('unsupported captured source manifest')
    expected = {}
    total = 0
    for line in lines:
        fields = line.split('\t')
        if len(fields) != 3:
            raise ValueError('invalid captured source manifest row')
        size, digest, member = fields
        member_name(member)
        if (member in expected or not re.fullmatch(r'[0-9]+', size)
                or not re.fullmatch(r'[a-f0-9]{64}', digest)):
            raise ValueError('invalid or duplicate captured source manifest member')
        count = int(size)
        total += count
        if count > SOURCE_FILE_LIMIT or total > SOURCE_TREE_LIMIT or len(expected) >= SOURCE_MEMBER_LIMIT:
            raise ValueError('captured source manifest exceeds its bounds')
        expected[member] = (count, digest)
    if not expected:
        raise ValueError('empty captured source manifest')
    return data, expected


def rendered_inputs(args, paths: list[Path]) -> tuple[dict[str, Path], dict]:
    """Bind actual prepared products to the exact current original Perl sources."""
    rendered = private_path(args.rendered_root)
    if not rendered.is_dir() or rendered.is_relative_to(ROOT):
        raise ValueError('rendered source must be a separate prepared fixture directory')
    prepared = rendered.parent
    if (rendered.name != 'source'
            or private_path(args.published_assets) != prepared / 'inputs/published-assets.tsv'
            or private_path(args.source_manifest) != prepared / 'inputs/payload.manifest'):
        raise ValueError('rendered inputs must share their canonical prepared workspace')
    manifest_data, expected = captured_manifest(args.source_manifest)
    receipt = json.loads(read_regular(prepared / 'receipt.json', 65536))
    fields = {'format', 'members', 'input_bytes', 'rendered_files', 'rendered_bytes',
              'published_perl_files', 'source_archive_sha256', 'source_manifest_sha256', 'source_identity'}
    if (not isinstance(receipt, dict) or set(receipt) != fields or receipt['format'] != 2
            or any(type(receipt[name]) is not int or receipt[name] < 0 for name in (
                'members', 'input_bytes', 'rendered_files', 'rendered_bytes', 'published_perl_files'))
            or receipt['members'] != len(expected)
            or receipt['input_bytes'] != sum(size for size, _digest in expected.values())
            or receipt['source_manifest_sha256'] != sha256(manifest_data)):
        raise ValueError('prepared render receipt does not match the captured source manifest')
    identity = read_regular(prepared / 'identity', 8192).decode('ascii')
    match = re.fullmatch(r'verified-v1 ([a-f0-9]{64}) ([a-f0-9]{64}) ([A-Za-z0-9:/._+?%#@ -]+)\n', identity)
    if (match is None or match[1] != receipt['source_archive_sha256']
            or match[2] != receipt['source_manifest_sha256'] or match[3] != receipt['source_identity']):
        raise ValueError('prepared source identity does not match its completed render receipt')
    suites = []
    for suite in ('forky', 'trixie'):
        frontend = ROOT / 'd-i' / suite
        manifest = frontend / 'payload.manifest'
        if manifest.is_file() and read_regular(manifest, 4 * 1024 * 1024) == manifest_data:
            if sha256(read_regular(frontend / 'payload.tar.gz', SOURCE_TREE_LIMIT)) == match[1]:
                suites.append(suite)
    if not suites:
        raise ValueError('prepared fixture does not identify a current suite payload')
    for path in paths:
        data = read_regular(path)
        if expected.get(source_member(path)) != (len(data), sha256(data)):
            raise ValueError(f'captured payload contains stale or missing Perl source: {path.relative_to(ROOT)}')
    renderer = ROOT / 'd-i/debian/scripts/common/render.pl'
    renderer_data = read_regular(renderer)
    if (read_regular(prepared / 'render.pl') != renderer_data
            or read_regular(rendered / 'scripts/common/render.pl') != renderer_data):
        raise ValueError('prepared fixture used a stale or altered installer renderer')
    publications = {}
    destinations = set()
    publication_data = read_regular(args.published_assets, 4 * 1024 * 1024)
    for line in publication_data.decode('utf-8').splitlines():
        fields = line.split('\t')
        if len(fields) != 3 or fields[2] != '0644':
            raise ValueError('invalid canonical Perl publication row')
        member, destination, _mode = fields
        member_name(member)
        target = private_path(Path(destination))
        if member in publications or target in destinations or member not in expected:
            raise ValueError('duplicate or unlisted canonical Perl publication')
        publications[member] = target
        destinations.add(target)
    modules = {source_member(path) for path in paths if path.name.removesuffix('.tmpl').endswith('.pm')}
    if set(publications) != modules or receipt['published_perl_files'] != len(modules):
        raise ValueError('prepared desktop publication must contain every inventoried Perl module')
    return publications, {'mode': 'canonical-rendered', 'matching_suites': suites,
                          'rendered_root': str(rendered), 'published_assets': str(args.published_assets),
                          'publication_sha256': sha256(publication_data),
                          'source_manifest_sha256': sha256(manifest_data),
                          'source_archive_sha256': match[1], 'renderer_sha256': sha256(renderer_data),
                          'receipt_sha256': sha256(read_regular(prepared / 'receipt.json', 65536))}


def stage_perl(paths: list[Path], work: Path, args) -> tuple[dict[Path, dict], list[Path], dict]:
    """Keep exact original/rendered bytes and only normalize module filenames."""
    publications, provenance = ({}, {'mode': 'strict-source-diagnostic'})
    if args.rendered_root is not None:
        publications, provenance = rendered_inputs(args, paths)
    records = {}
    roots = set()
    destinations = set()
    for path in paths:
        original = read_regular(path)
        member = source_member(path)
        selected = path
        kind = 'unrendered-source'
        if args.rendered_root is not None:
            selected = publications.get(member, args.rendered_root / member)
            kind = 'canonical-perl-publication' if member in publications else 'canonical-base-render'
        data = read_regular(selected)
        tokens = sorted({token.decode('ascii') for token in INSTALLER_TOKEN.findall(data)})
        if args.rendered_root is not None and tokens:
            # These two exact literals belong to the unchanged renderer's own
            # input grammar. No target/template consumer receives an exemption.
            renderer_literals = {'__INSTALLER_DATA_END__', '__INSTALLER_FSTAB_RECORDS__'}
            if member != 'scripts/common/render.pl' or set(tokens) - renderer_literals:
                raise ValueError(f'unresolved installer token in rendered Perl source: {member}')
        relative = path.relative_to(ROOT)
        if relative.name.endswith('.pm.tmpl'):
            relative = relative.with_suffix('')
        destination = work / 'perl-source' / relative
        if destination in destinations:
            raise ValueError('duplicate staged Perl filename')
        destinations.add(destination)
        destination.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
        destination.write_bytes(data)
        destination.chmod(0o600)
        if read_regular(destination) != data:
            raise ValueError('staged Perl bytes differ from their exact selected source')
        if destination.name.endswith('.pm'):
            matched = False
            for package in re.findall(rb'^\s*package\s+([A-Za-z][A-Za-z0-9_:]+)\s*[;{]', data, re.M):
                parts = package.decode('ascii').split('::')
                suffix = tuple(parts[:-1]) + (parts[-1] + '.pm',)
                if destination.parts[-len(suffix):] == suffix:
                    roots.add(destination.parents[len(suffix) - 1])
                    matched = True
            if not matched:
                raise ValueError(f'Perl module has no matching package path: {member}')
        records[path] = {'source_sha256': sha256(original), 'selected_path': str(selected),
                         'selected_sha256': sha256(data), 'selected_bytes': len(data),
                         'selected_kind': kind, 'compile_path': str(destination),
                         'perl_flags': perl_shebang_flags(data.split(b'\n', 1)[0].decode('utf-8')),
                         'remaining_installer_tokens': tokens}
    return records, sorted(roots), provenance


def audit_status(records: list[dict], *, perl_only: bool = False) -> int:
    """An incomplete required parser check is a failure, never a silent skip."""
    if not records:
        return 1
    accepted = {'pass'} if perl_only else {'pass', 'structure-pass', 'inventory-only'}
    return int(any(record['check'] not in accepted for record in records))


def native_syntax(command: list[str], *, work: Path, environment: dict[str, str],
                  number: int) -> tuple[int, str, str]:
    """Bound parser output/time and own cleanup of its complete child session."""
    if not os.access(command[0], os.X_OK):
        return 127, 'blocked-tool', f'{command[0]} is not installed or executable'
    log = work / f'{number:05d}.log'
    previous = resource.getrlimit(resource.RLIMIT_FSIZE)
    limit = (SYNTAX_OUTPUT_LIMIT if previous[1] == resource.RLIM_INFINITY
             else min(SYNTAX_OUTPUT_LIMIT, previous[1]))
    try:
        resource.setrlimit(resource.RLIMIT_FSIZE, (limit, previous[1]))
        with log.open('xb') as stream:
            result = run_stage(command, cwd=work, env=environment, timeout=SYNTAX_TIMEOUT,
                               stdout=stream, stderr=stream)
    finally:
        resource.setrlimit(resource.RLIMIT_FSIZE, previous)
    with log.open('rb') as stream:
        raw = stream.read(SYNTAX_OUTPUT_LIMIT + 1)
    detail = raw.decode('utf-8', 'replace')
    if result.cancelled is not None:
        raise InterruptedError('syntax audit was cancelled')
    if result.timed_out:
        return result.returncode, 'blocked-timeout', f'syntax checker exceeded {SYNTAX_TIMEOUT} seconds'
    if len(raw) >= limit or result.returncode == -signal.SIGXFSZ:
        return result.returncode or 1, 'blocked-output-limit', 'syntax checker exceeded its output bound'
    return result.returncode, 'pass' if result.returncode == 0 else 'fail', detail


def unit_structure(text: str) -> tuple[dict[str, list[str]], list[str]]:
    """Lexical structure only: repeated keys are legal in systemd unit files."""
    section = ''
    values: dict[str, list[str]] = {}
    pending = ''
    problems: list[str] = []
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith(('#', ';')):
            continue
        if line.endswith('\\'):
            pending += line[:-1] + ' '
            continue
        line = pending + line
        pending = ''
        if line.startswith('[') and line.endswith(']'):
            section = line[1:-1]
            continue
        if PLACEHOLDER.fullmatch(line):
            continue
        if '=' not in line or not section:
            problems.append(f'line {number}: invalid section/key structure')
            continue
        key, value = line.split('=', 1)
        values.setdefault(f'{section}.{key.strip()}', []).append(value.strip())
    if pending:
        problems.append('unterminated continuation')
    return values, problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--perl-only', action='store_true',
                        help='compile every complete Perl source in the required shared/suite scopes')
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument('--source-only', action='store_true',
                       help='strict diagnostic of unrendered sources; incomplete checks still fail')
    modes.add_argument('--rendered-root', type=Path,
                       help='actual prepared/source tree for the complete Perl gate')
    modes.add_argument('--prepare-suite', choices=('forky', 'trixie'),
                       help='prepare actual desktop payload products through the canonical fixture helper')
    parser.add_argument('--prepare-family', choices=('desktop',), default='desktop')
    parser.add_argument('--published-assets', type=Path)
    parser.add_argument('--source-manifest', type=Path)
    args = parser.parse_args()
    if not args.source_only and not args.perl_only:
        parser.error('rendered preparation is supported by the complete --perl-only gate')
    if args.rendered_root is not None:
        if args.published_assets is None or args.source_manifest is None:
            parser.error('--rendered-root requires --published-assets and --source-manifest')
    elif args.published_assets is not None or args.source_manifest is not None:
        parser.error('explicit prepared inputs require --rendered-root')
    try:
        scopes = source_scopes(ROOT)
        physical_perl_dirs = [str(path) for path in perl_library_paths(ROOT)]
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 1
    scope_paths = set().union(*(items for name, items in scopes.items() if '/hooks/' in name))
    paths = set().union(*scopes.values())
    perl_paths = sorted(path for path in paths
                        if is_perl(path, path.read_bytes().split(b'\n', 1)[0].decode('utf-8', errors='replace')))
    if not perl_paths:
        print('no complete Perl source found in the required scopes', file=sys.stderr)
        return 1
    if args.perl_only:
        paths = set(perl_paths)
    work = Path(tempfile.mkdtemp(prefix='syntax-audit-', dir='/workspace'))
    work.chmod(0o700)
    (work / 'tmp').mkdir(mode=0o700)
    environment = fixture_environment(Path('/workspace/home') / str(os.geteuid()))
    environment.update({'TMPDIR': str(work / 'tmp'), 'TMP': str(work / 'tmp'), 'TEMP': str(work / 'tmp')})
    try:
        if args.prepare_suite is not None:
            # Use the same maintained production-map/render preparation API as
            # explicit fixture callers. No second template implementation lives
            # in the auditor.
            sys.path.insert(0, '/workspace/repository/tools')
            try:
                from prepare_syntax_fixture import prepare_syntax_fixture
            finally:
                sys.path.pop(0)
            prepared = prepare_syntax_fixture(work / 'prepared-payload', args.prepare_suite, args.prepare_family)
            args.rendered_root = Path(prepared['rendered_root'])
            args.published_assets = Path(prepared['published_assets'])
            args.source_manifest = Path(prepared['source_manifest'])
        if args.rendered_root is not None:
            args.rendered_root = private_path(args.rendered_root)
        staged_perl, module_roots, provenance = stage_perl(perl_paths, work, args)
    except CleanupUnknown as error:
        print(f'Perl preparation cleanup is unknown: {error}; private evidence retained in {work}', file=sys.stderr)
        return 75
    except (OSError, ValueError, RuntimeError) as error:
        print(f'Perl preparation failed: {error}; private evidence retained in {work}', file=sys.stderr)
        return 1
    perl_dirs = [str(path) for path in module_roots]
    perl_args = [arg for directory in perl_dirs for arg in ('-I', directory)]

    def scan(number: int, path: Path) -> dict:
        raw = path.read_bytes()
        text = raw.decode('utf-8', errors='replace')
        first = text.split('\n', 1)[0]
        relative = str(path.relative_to(ROOT))
        name = path.name.removesuffix('.tmpl')
        kind = 'config-or-data'
        state = 'inventory-only'
        detail = ''
        cmd = None
        native_returncode = None
        facts = {}
        if (first.startswith('#!') and 'python' in first) or name.endswith('.py'):
            kind = 'python'
        elif is_perl(path, first):
            kind = 'perl'
            selected = staged_perl[path]
            cmd = ['/usr/bin/perl', *selected['perl_flags'], '-f', '-c', *perl_args, selected['compile_path']]
        elif '/etc/apparmor.d/' in '/' + relative and not (
                first.startswith('#!') and re.search(r'\b(sh|bash|dash|ash)\b', first)):
            # Attachment names can end in .sh without being shell programs.
            # Policy compilation needs rendered inputs and system abstractions;
            # keep this inventory-only rather than claiming a syntax pass.
            kind = 'apparmor-policy'
        elif ((first.startswith('#!') and re.search(r'\b(sh|bash|dash)\b', first))
              or name.endswith(('.sh', '.env')) or '/etc/default/grub.d/' in relative
              or name in ('.bashrc', '.bash_profile', '.profile')):
            kind = 'shell'
            cmd = ['/usr/bin/bash' if 'bash' in first or name.startswith('.bash') else '/bin/sh', '-n', str(path)]
        elif '/polkit-1/rules.d/' in relative:
            kind = 'javascript'
            script = work / f'javascript-{number:05d}.js'
            script.write_bytes(raw)
            cmd = ['/usr/bin/node', '--check', str(script)]
        elif (name.endswith(UNIT_SUFFIXES) or re.search(r'/[^/]+\.(?:service|socket|slice|target)\.d/', relative)):
            kind = 'systemd-structure'
        elif name.endswith('.json'):
            kind = 'json'
        elif name.endswith('.toml'):
            kind = 'toml'
        elif name.endswith('.xml') or text.lstrip().startswith(('<?xml', '<!DOCTYPE busconfig', '<busconfig')):
            kind = 'xml'
        try:
            if kind == 'python':
                ast.parse(text, filename=relative)
                state = 'pass'
            elif kind == 'json':
                json.loads(text)
                state = 'pass'
            elif kind == 'toml':
                # Unquoted tokens are intentionally not valid TOML before rendering.
                if PLACEHOLDER.search(text):
                    state = 'template-needs-render'
                else:
                    tomllib.loads(text)
                    state = 'pass'
            elif kind == 'xml':
                ET.fromstring(text)
                state = 'pass'
            elif kind == 'systemd-structure':
                values, errors = unit_structure(text)
                facts = {k: v for k, v in values.items() if k.split('.', 1)[-1] in {
                    'Type', 'ExecStart', 'ExecStartPre', 'ExecStop', 'ExecStopPost',
                    'KillMode', 'TimeoutStartSec', 'TimeoutStopSec', 'Restart',
                    'PartOf', 'BindsTo', 'Requires', 'Wants', 'After', 'Before',
                    'TasksMax', 'MemoryMax', 'NoNewPrivileges', 'User', 'Delegate'}}
                state = 'fail' if errors else 'structure-pass'
                detail = '; '.join(errors)
            elif cmd:
                if kind == 'perl' and sha256(read_regular(Path(selected['compile_path']))) != selected['selected_sha256']:
                    raise ValueError('staged Perl source changed before compilation')
                native_returncode, state, detail = native_syntax(cmd, work=work, environment=environment, number=number)
                detail = detail.replace(str(ROOT), '$ROOT')
                if state == 'pass' and kind == 'perl' and not re.search(r'^.+ syntax OK\s*$', detail, re.M):
                    state = 'fail'
                    detail = 'Perl returned success without its complete-program syntax marker: ' + detail
                elif state == 'fail' and kind == 'perl':
                    if 'Can\'t locate ' in detail or 'Can\'t load ' in detail:
                        state = 'blocked-dependency'
                    elif re.search(r'Bareword "__INSTALLER_[A-Z0-9_]+__" not allowed', detail):
                        # This exact typed scalar needs the canonical renderer.
                        # Other syntax errors in templated files remain failures.
                        state = 'template-needs-render'
                if state == 'pass':
                    detail = ''
        except (CleanupUnknown, InterruptedError):
            raise
        except (OSError, SyntaxError, ValueError, ET.ParseError) as exc:
            state = 'fail'
            detail = str(exc).replace(str(ROOT), '$ROOT')
        return {'path': relative, 'requested_scope': path in scope_paths,
                'kind': kind, 'check': state, 'detail': detail, 'unit_facts': facts,
                'command': cmd, 'returncode': native_returncode,
                'lines': len(raw.splitlines()), 'bytes': len(raw),
                'mode': oct(path.stat().st_mode & 0o777),
                'sha256': hashlib.sha256(raw).hexdigest(),
                'placeholder_count': len(PLACEHOLDER.findall(text)),
                'perl_source': staged_perl.get(path)}

    try:
        # Shared process ownership uses the main thread for bounded cancellation
        # and cleanup. A Perl import cannot leave a timed-out child session behind.
        records = [scan(number, path) for number, path in enumerate(sorted(paths), 1)]
    except CleanupUnknown as error:
        print(f'{error}; private evidence retained in {work}', file=sys.stderr)
        return 75
    except InterruptedError as error:
        print(f'{error}; private evidence retained in {work}', file=sys.stderr)
        return 1
    checks = Counter(record['check'] for record in records)
    report = {
        'scope_counts': {name: len(items) for name, items in scopes.items()},
        'requested_unique_files': len(scope_paths), 'total_with_installers_and_hosts': len(records),
        'check_counts': dict(sorted(checks.items())),
        'kind_counts': dict(sorted(Counter(r['kind'] for r in records).items())),
        'perl_only': args.perl_only,
        'perl_source_count': len(perl_paths),
        'perl_source_inventory': [str(path.relative_to(ROOT)) for path in perl_paths],
        'physical_perl_library_roots': physical_perl_dirs,
        'perl_library_roots': perl_dirs,
        'perl_provenance': provenance,
        'success': audit_status(records, perl_only=args.perl_only) == 0,
        'limits': ['Syntax and inventory are not semantic or runtime proof.',
                   'Systemd structure checks do not resolve vendor units or template values.',
                   'Blocked dependency/template checks are not passes.',
                   'No kernel policies, network changes, services or installers are applied.'],
        'files': records,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile('w', dir=args.output.parent, delete=False) as stream:
        temporary = stream.name
        json.dump(report, stream, indent=2)
        stream.write('\n')
    os.replace(temporary, args.output)
    print(json.dumps({k: report[k] for k in ('requested_unique_files', 'total_with_installers_and_hosts', 'check_counts', 'kind_counts')}, indent=2))
    shutil.rmtree(work)
    return audit_status(records, perl_only=args.perl_only)


if __name__ == '__main__':
    raise SystemExit(main())
