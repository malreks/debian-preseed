#!/usr/bin/env python3
"""Run non-mutating source checks for every changed regular checkout file.

The checker inventories staged, unstaged and untracked paths without executing
their contents. The default audit checks syntax and structure, without asserting
application lists, package versions, source lines, implementation tokens or
archive contents. It parses languages for which
the repository has local or standard-library parsers, runs shell syntax and
ShellCheck only on changed shell files, validates changed structured data, and
performs targeted theme/AppArmor checks. It never imports project modules,
executes repository scripts, starts services, contacts host sockets, or writes
validation artifacts.
"""
from __future__ import annotations

import ast
import bisect
import builtins
from concurrent.futures import ThreadPoolExecutor
import configparser
import fnmatch
import hashlib
import io
import json
import os
import re
import shlex
import shutil
import stat
import subprocess
import sys
import symtable
import tarfile
import tempfile
import tomllib
import xml.etree.ElementTree as ElementTree
import zipfile
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover - reported only for changed YAML input.
    yaml = None

YAML_ERROR = yaml.YAMLError if yaml is not None else ValueError


ROOT = Path(__file__).resolve().parents[1]
DEBIAN_ROOT = ROOT / 'd-i/debian'
TARGET_ROOT = DEBIAN_ROOT / 'hooks/target'
BASELINE_ZIP: Path | None = None
ARCHIVE_CHANGES: dict[str, bytes | None] = {}

# Source ownership is independent of the installed FHS spelling. This is
# data-only lookup: it never renders or executes a target program. Logical FHS
# names resolve to exactly one common or selected-family physical source.
ASSET_GROUPS = ('etc/apparmor.d', 'etc/apparmor', 'etc/tmpfiles.d', 'etc/sysctl.d',
                'usr/local/libexec', 'usr/local/lib', 'usr/local/sbin',
                'usr/local/bin', 'usr/local/share')


def target_source(relative: str, family: str = 'desktop') -> Path:
    if family not in {'desktop', 'server'} or any(part in {'', '.', '..'} for part in relative.split('/')):
        raise ValueError('invalid target source lookup')
    candidates = [TARGET_ROOT / relative]
    for group in ASSET_GROUPS:
        if relative.startswith(group + '/'):
            leaf = relative[len(group) + 1:]
            if leaf.split('/', 1)[0] not in {'common', 'desktop', 'server'}:
                candidates += [TARGET_ROOT / group / owner / leaf for owner in ('common', family)]
            break
    if not relative.endswith('.tmpl'):
        candidates += [path.with_name(path.name + '.tmpl') for path in tuple(candidates)]
    existing = [path for path in candidates if path.is_file() and not path.is_symlink()]
    if len(existing) != 1:
        raise ValueError('target source has missing or ambiguous physical ownership: ' + relative)
    return existing[0]


SCHEMA = DEBIAN_ROOT / 'hosts/themes/theme-schema.tsv'
# Historical focused checks below use these source paths. The routine audit
# does not resolve or inspect unrelated application assets during startup.
APPEARANCE_REGISTRY = TARGET_ROOT / 'usr/local/share/desktop/labwc-appearance/fields.json.tmpl'
APPEARANCE_FIELDS = TARGET_ROOT / 'usr/local/lib/desktop/python3/dist-packages/labwc_appearance/fields.py'
APPEARANCE_NATIVE = TARGET_ROOT / 'usr/local/lib/desktop/python3/dist-packages/labwc_appearance/native.py'
THEME_FETCH_CORE = DEBIAN_ROOT / 'scripts/late/core.sh'
THEME_RENDER_SUPPORT = DEBIAN_ROOT / 'scripts/late/themes.sh'
THEME_RENDER_AWK = DEBIAN_ROOT / 'tests/fixtures/theme-render-reference.awk'
THEME_VALIDATE_AWK = DEBIAN_ROOT / 'scripts/late/theme-validate.awk'
APPEARANCE_STAGE = DEBIAN_ROOT / 'scripts/desktop/components/appearance.sh'
DESKTOP_INSTALLER = DEBIAN_ROOT / 'scripts/desktop/labwc.sh'
WAYBAR_GEOMETRY_SCHEMA = DEBIAN_ROOT / 'scripts/desktop/waybar-geometry.tsv'
WAYBAR_PROFILE_ROOT = DEBIAN_ROOT / 'hosts/profiles/desktop'
THEME_TOKEN = re.compile(rb'__THEME_([A-Z0-9_]+)__')
THEME_PREFIX = b'__THEME_'
REGISTRY_TOKEN = re.compile(r'__(?:THEME|INSTALLER)_[A-Z0-9_]+__')
APPEARANCE_COMPONENTS = frozenset({
    'DOCK', 'FUZZEL', 'WAYBAR', 'TASKVIEW', 'WAYCAL', 'MAKO', 'TERMINAL', 'SWAYLOCK', 'GTKGREET',
})
APPEARANCE_TYPES = frozenset({
    'hash6', 'hash8', 'hex6', 'hex8', 'swaylock-rgb', 'swaylock-rgba', 'rgba', 'alpha', 'decimal', 'text-color',
    'mako-progress',
})
APPEARANCE_GRAMMARS = frozenset({
    'gtk3-css-color', 'gtk4-css-color', 'pango-color', 'qt-color', 'mako-color',
    'mako-progress', 'fuzzel-rgba', 'foot-rgb', 'kitty-color', 'swaylock-rgb', 'swaylock-rgba', 'alpha', 'decimal',
})
APPEARANCE_PATHS = frozenset({
    'fuzzel/base.ini', 'fuzzel/fuzzel.ini', 'fuzzel/menu.ini',
    'fuzzel/computer-management.ini', 'waybar/style.css', 'waybar/style-common.css', 'waybar/config',
    'waybar/modules/app-files',
    'waybar/modules/app-notes',
    'waybar/modules/app-sleek',
    'waybar/modules/app-terminal',
    'waybar/modules/app-tuta',
    'waybar/modules/apps',
    'waybar/modules/backlight',
    'waybar/modules/battery',
    'waybar/modules/bluetooth',
    'waybar/modules/clock',
    'waybar/modules/cpu',
    'waybar/modules/disk',
    'waybar/modules/external-apps-drawer',
    'waybar/modules/external-launcher',
    'waybar/modules/external-quick-controls',
    'waybar/modules/external-taskbar',
    'waybar/modules/external-tray',
    'waybar/modules/internal-apps-drawer',
    'waybar/modules/internal-launcher',
    'waybar/modules/internal-quick-controls',
    'waybar/modules/internal-taskbar',
    'waybar/modules/internal-tray',
    'waybar/modules/keyboard',
    'waybar/modules/lock',
    'waybar/modules/memory',
    'waybar/modules/network',
    'waybar/modules/notifications',
    'waybar/modules/power',
    'waybar/modules/pulseaudio',
    'waybar/modules/screenshot',
    'waybar/modules/system',
    'waybar/modules/tomat',
    'waybar/modules/wayscriber',
    'waybar/modules/window-switcher',
    'waybar/modules/workspaces',
    'waybar/style/gtk.css',
    'waybar/style/menu.css', 'waybar/style/workspaces.css', 'waybar/style/tomat.css',
    'waybar/style/wayscriber.css', 'waybar/style/taskview.css', 'waybar/style/apps.css',
    'waybar/style/clock.css', 'waybar/style/audio.css', 'waybar/style/brightness.css',
    'waybar/style/battery.css', 'waybar/style/storage.css', 'waybar/style/cpu.css',
    'waybar/style/memory.css', 'waybar/style/tray.css', 'waybar/style/system.css',
    'waybar/style/notifications.css', 'waybar/style/lock.css', 'waybar/style/power.css',
    'waybar/icons/apps-symbolic.svg',
    'waybar/icons/wayscriber-symbolic.svg', 'waycal/style.css',
    'crystal-dock/labwc/appearance.conf',
    'foot/foot.ini', 'kitty/kitty.conf', 'mako/config', 'gtk-3.0/settings.ini',
    'gtk-4.0/settings.ini', 'gtk-4.0/gtk.css', 'swaylock/config', 'qt5ct/qt5ct.conf', 'qt6ct/qt6ct.conf',
    'qt5ct/colors/labwc-appearance.conf', 'qt6ct/colors/labwc-appearance.conf',
    'Kvantum/kvantum.kvconfig', 'labwc/themerc-override', 'labwc/environment',
    '/etc/greetd/gtkgreet.css', '/etc/greetd/gtkgreet-power.css',
})
SHELL_SUFFIXES = frozenset({'.env', '.sh'})
BINARY_SUFFIXES = frozenset({
    '.7z', '.bz2', '.deb', '.gif', '.gz', '.ico', '.jpeg', '.jpg', '.otf',
    '.png', '.tar', '.tgz', '.ttf', '.webp', '.woff', '.woff2', '.xz', '.zip',
})


def _run(command: list[str], *, timeout: int = 15,
         input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            command,
            cwd=ROOT,
            capture_output=True,
            input=input_text,
            text=True,
            encoding='utf-8',
            errors='replace',
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        return subprocess.CompletedProcess(
            command, 124, stdout=error.stdout or '', stderr='static checker timed out'
        )


def _changed_paths() -> list[Path]:
    """Return existing regular changed files anywhere in the checkout."""
    if BASELINE_ZIP is not None:
        return _archive_changed_paths(BASELINE_ZIP)
    names: set[str] = set()
    commands = (
        ['git', 'diff', '--name-only', '-z', '--diff-filter=ACMRTUXB'],
        ['git', 'diff', '--cached', '--name-only', '-z', '--diff-filter=ACMRTUXB'],
        ['git', 'ls-files', '--others', '--exclude-standard', '-z'],
    )
    for command in commands:
        result = _run(command)
        if result.returncode:
            detail = (result.stderr or result.stdout).strip().replace('\n', ' ')[:300]
            raise RuntimeError(f'cannot enumerate changed files: {detail}')
        names.update(part for part in result.stdout.split('\0') if part)

    paths = []
    for name in sorted(names):
        path = ROOT / name
        if Path(name).is_absolute() or any(part in {'', '.', '..'} for part in Path(name).parts):
            raise ValueError('noncanonical changed path')
        if path.is_symlink():
            raise ValueError(f'changed symlink is outside static regular-file contract: {name}')
        if path.is_file() and path.resolve().is_relative_to(ROOT):
            paths.append(path)
    return paths


def _archive_changed_paths(baseline: Path) -> list[Path]:
    """Compare an attached source snapshot without manufacturing a Git commit.

    Only changed regular files enter the existing checks. Archive entries are
    read as bounded data; no archived source or import hook is executed.
    """
    previous: set[str] = set()
    total = 0
    with zipfile.ZipFile(baseline) as archive:
        entries = archive.infolist()
        roots = {item.filename.split('/', 1)[0] for item in entries}
        if len(roots) != 1 or len(entries) > 20000:
            raise ValueError('baseline requires one bounded source root')
        prefix = next(iter(roots)) + '/'
        for item in entries:
            if not item.filename.startswith(prefix):
                raise ValueError('invalid baseline member root')
            name = item.filename[len(prefix):].rstrip('/')
            if not name:
                continue
            if Path(name).is_absolute() or any(part in {'', '.', '..'} for part in name.split('/')):
                raise ValueError('unsafe baseline member')
            if name.split('/', 1)[0] in {'.git', '.build'}:
                continue
            kind = stat.S_IFMT(item.external_attr >> 16)
            if kind not in {0, stat.S_IFREG, stat.S_IFDIR}:
                raise ValueError('nonregular baseline source')
            if item.is_dir():
                continue
            total += item.file_size
            if name in previous or item.file_size > 67108864 or total > 268435456:
                raise ValueError('duplicate or excessive baseline data')
            previous.add(name)
            path = ROOT / name
            if path.is_symlink():
                raise ValueError('changed symlink is outside static regular-file contract: ' + name)
            old = archive.read(item)
            if not path.is_file() or path.read_bytes() != old:
                ARCHIVE_CHANGES[name] = old
    for path in ROOT.rglob('*'):
        name = path.relative_to(ROOT).as_posix()
        if name.split('/', 1)[0] in {'.git', '.build'}:
            continue
        if name not in previous and path.is_file():
            if path.is_symlink():
                raise ValueError('new symlink is outside static regular-file contract: ' + name)
            ARCHIVE_CHANGES[name] = None
    return [ROOT / name for name in sorted(ARCHIVE_CHANGES) if (ROOT / name).is_file()]


def _first_line(path: Path) -> str:
    with path.open('r', encoding='utf-8', errors='replace') as stream:
        return stream.readline(4096).strip()


def _logical_suffix(path: Path) -> str:
    return Path(path.name.removesuffix('.tmpl')).suffix.lower()


def _shell_kind(path: Path) -> str | None:
    first = _first_line(path)
    relative = path.relative_to(ROOT).as_posix()
    if '/etc/apparmor.d/' in '/' + relative and not first.startswith('#!'):
        return None
    if first.startswith('#!') and 'bash' in first:
        return 'bash'
    if first.startswith('#!') and re.search(r'\b(?:sh|dash|ash)\b', first):
        return 'sh'
    # Login defaults are sourced shell programs without shebangs or suffixes.
    # Include them in syntax/SC2154 checks when they are changed regular files.
    login_name = path.name.removesuffix('.tmpl')
    if login_name in {'.bashrc', '.bash_profile', '.bash_logout'}:
        return 'bash'
    if login_name == '.profile':
        return 'sh'
    if _logical_suffix(path) in SHELL_SUFFIXES or path.name.endswith('.sh.tmpl'):
        return 'sh'
    return None


def _detail(result: subprocess.CompletedProcess[str]) -> str:
    return (result.stderr or result.stdout).strip().replace('\n', ' ')[:500]


def _report_command(errors: list[str], label: str,
                    result: subprocess.CompletedProcess[str]) -> None:
    errors.append(f'{label}: command failed ({result.returncode}): {_detail(result)}')


def _read_text(path: Path) -> str:
    data = path.read_bytes()
    if b'\0' in data:
        raise ValueError('unexpected NUL byte in text source')
    return data.decode('utf-8')


def _custom_apt_input(path: Path) -> bool:
    """Operator-owned finish-install bytes have no content validation here."""
    return re.fullmatch(
        r'd-i/(forky|trixie)/hooks/target/etc/apt/(desktop|server)/'
        r'(sources\.list\.d|preferences\.d)/custom/.+',
        path.relative_to(ROOT).as_posix(),
    ) is not None


def _runtime_path_schema_rows(text: str | None = None) -> list[tuple[str, str]]:
    """Read the shared canonical map schema without sourcing its shell adapter."""
    if text is None:
        text = _read_text(DEBIAN_ROOT / 'catalog/runtime-paths.tsv')
    result: list[tuple[str, str]] = []
    seen: set[str] = set()
    for line in text.splitlines():
        if not line or line.startswith('#'):
            continue
        fields = line.split('\t')
        if len(fields) != 2:
            raise ValueError('malformed canonical path schema')
        key, variable = fields
        if (not re.fullmatch(r'(?:DIR_|FILE_|APPARMOR_PROFILE_)[A-Z0-9_]+|GITBUILD_DISTRIBUTION', variable)
                or key != ('PATH_' + variable if variable.startswith(('DIR_', 'FILE_')) else variable)
                or key in seen):
            raise ValueError('invalid or duplicate canonical path owner: ' + key)
        seen.add(key)
        result.append((key, variable))
    return result


def _installer_path_token_values() -> list[tuple[str, str]]:
    """Read the authored runtime path contract as data for static checks."""
    runtime = DEBIAN_ROOT / 'hosts/installer/runtime.env'
    assignments: dict[str, str] = {}
    for line in _read_text(runtime).splitlines():
        match = re.fullmatch(r'((?:DIR|FILE|CMD|LIB|PATH)_[A-Z0-9_]+)="([^"]*)"', line)
        if match:
            assignments[match[1]] = match[2]
    resolved: dict[str, str] = {}
    for _ in range(len(assignments) + 1):
        changed = False
        for name, value in assignments.items():
            if name in resolved:
                continue
            references = re.findall(r'\$\{([A-Z][A-Z0-9_]*)\}', value)
            if any(reference not in resolved for reference in references):
                continue
            for reference in references:
                value = value.replace('${' + reference + '}', resolved[reference])
            if '${' in value:
                continue
            resolved[name] = value
            changed = True
        if not changed:
            break
    return sorted(
        (
            f'__INSTALLER_PATH_{name}__',
            value,
        )
        for name, value in resolved.items()
        if value.startswith('/') and value != '/'
    )


def _render_installer_path_placeholders(value: str) -> str:
    for token, replacement in sorted(_installer_path_token_values(),
                                     key=lambda item: len(item[0]), reverse=True):
        value = value.replace(token, replacement)
    return value


def _repository_selector_values(suite: str = 'forky') -> dict[str, str]:
    """Read parent-first shared repository roots as data, never as shell code."""
    if suite not in ('forky', 'trixie'):
        raise ValueError('unknown suite map')
    values: dict[str, str] = {'INSTALLER_SUITE': suite}
    source = DEBIAN_ROOT / 'repo.env'
    for number, line in enumerate(_read_text(source).splitlines(), 1):
        if line.startswith('FILE_'):
            raise ValueError(f'repo.env:{number}: retired per-file source inventory')
        if not line.startswith('DIR_'):
            continue
        match = re.fullmatch(r'(DIR_[A-Z0-9_]+)="([^"`\\]*)"', line)
        if match is None:
            raise ValueError(f'repo.env:{number}: malformed source selector')
        name, raw = match.groups()
        if name in values:
            raise ValueError(f'repo.env:{number}: duplicate source selector {name}')

        def expand(reference: re.Match[str]) -> str:
            key = reference.group(1)
            if key not in values:
                raise ValueError(f'repo.env:{number}: undefined parent {key}')
            return values[key]

        value = re.sub(r'\$\{([A-Z][A-Z0-9_]*)\}', expand, raw)
        if '$' in value or not value or value.startswith('/'):
            raise ValueError(f'repo.env:{number}: invalid relative selector {name}')
        if value != '.' and any(part in {'', '.', '..'} for part in value.split('/')):
            raise ValueError(f'repo.env:{number}: noncanonical selector {name}')
        values[name] = value
    return values


def _resolve_repository_source_contract(value: str) -> str:
    """Expand shared roots for source assertions without running loaders."""
    values = _repository_selector_values()
    return re.sub(r'\$\{(DIR_[A-Z0-9_]+)\}',
                  lambda match: values.get(match.group(1), match.group(0)), value)


def _python_defined_globals(table: symtable.SymbolTable) -> set[str]:
    defined = set()
    pending = [table]
    while pending:
        scope = pending.pop()
        for symbol in scope.get_symbols():
            # A setup function may explicitly populate the module namespace.
            # Ordinary local assignments must not satisfy another scope's use.
            if ((scope is table or symbol.is_global())
                    and (symbol.is_assigned() or symbol.is_imported() or symbol.is_namespace())):
                defined.add(symbol.get_name())
        pending.extend(scope.get_children())
    return defined


def _python_unbound_globals(source: str, label: str, extra_globals: set[str] | None = None
                            ) -> list[tuple[str, int, str]]:
    """Use Python's lexical symbol tables as data; never import the program."""
    tree = ast.parse(source, filename=label)
    table = symtable.symtable(source, label, 'exec')
    names = {node.id for node in ast.walk(tree) if isinstance(node, ast.Name)
             and isinstance(node.ctx, ast.Load)}
    defined = (_python_defined_globals(table) | set(dir(builtins)) | (extra_globals or set())
               | {'__name__', '__file__', '__package__', '__spec__', '__loader__',
                  '__cached__', '__builtins__', '__doc__'})
    pending, issues = [table], []
    while pending:
        scope = pending.pop()
        for symbol in scope.get_symbols():
            name = symbol.get_name()
            # Compiler-synthesized annotation state has no source Name node.
            # A declared installer token in code is checked by its registry.
            if (symbol.is_referenced() and symbol.is_global() and name in names
                    and name not in defined and REGISTRY_TOKEN.fullmatch(name) is None):
                issues.append((scope.get_name(), scope.get_lineno(), name))
        pending.extend(scope.get_children())
    return sorted(issues)


def check_python(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    candidates = [path for path in paths if _logical_suffix(path) == '.py'
                  or re.match(r'^#!.*\bpython(?:[0-9]+(?:\.[0-9]+)*)?\b', _first_line(path))]
    for path in candidates:
        try:
            label = str(path.relative_to(ROOT))
            source = _read_text(path)
            ast.parse(source, filename=label)
            if path.is_relative_to(DEBIAN_ROOT) and not path.is_relative_to(DEBIAN_ROOT / 'tests'):
                extra_globals = set()
                if path == DEBIAN_ROOT / 'scripts/late/crypto-bootstrap.py.tmpl':
                    # This installer explicitly captures the validated maintenance
                    # helper into its namespace. Inspect that one producer as data.
                    provider = DEBIAN_ROOT / 'hooks/target/usr/local/libexec/common/tpm2-policy-check'
                    extra_globals = _python_defined_globals(symtable.symtable(
                        _read_text(provider), str(provider.relative_to(ROOT)), 'exec'))
                for scope, line, name in _python_unbound_globals(source, label, extra_globals):
                    errors.append(f'{label}:{line}: undefined Python global {name!r} in {scope}')
                counts['python_global_scopes'] = counts.get('python_global_scopes', 0) + 1
        except (OSError, UnicodeError, SyntaxError) as error:
            errors.append(f'{path.relative_to(ROOT)}: Python syntax: {error}')
    counts['python_ast'] = len(candidates)


def check_text_files(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    checked = 0
    for path in paths:
        suffix = _logical_suffix(path)
        if suffix in BINARY_SUFFIXES or path.name.endswith(('.tar.gz', '.tgz')):
            continue
        try:
            _read_text(path)
            checked += 1
        except (OSError, UnicodeError, ValueError) as error:
            errors.append(f'{path.relative_to(ROOT)}: text encoding/content: {error}')
    counts['text_files'] = checked


def _shellcheck_findings(output: str, *, unbound: bool) -> list[dict]:
    """Select required errors/SC2154 from one warning-inclusive analysis."""
    messages = json.loads(output)
    if not isinstance(messages, list) or any(
        not isinstance(message, dict)
        or message.get('level') not in {'error', 'warning', 'info', 'style'}
        or not isinstance(message.get('code'), int)
        for message in messages
    ):
        raise ValueError('malformed ShellCheck diagnostic records')
    return [message for message in messages
            if message['level'] == 'error' or unbound and message['code'] == 2154]


def _shellcheck_batch(errors: list[str], executable: str, kind: str,
                      paths: list[Path], *, unbound: bool) -> None:
    if not paths:
        return

    def check_one(path: Path) -> tuple[Path, list[subprocess.CompletedProcess[str]]]:
        input_text = None
        shellcheck_path = str(path)
        if _logical_suffix(path) == '.env':
            # Host profiles are assignment-only data with a handful of
            # intentional cross-file expansions. ShellCheck's data-flow graph
            # becomes superlinear on the full 1,600-line files. Syntax is still
            # checked against the complete source above; feed ShellCheck only
            # expansion lines, preserving their original line numbers, for the
            # error and SC2154 contracts.
            source_lines = _read_text(path).splitlines()
            data_only = all(
                not line.strip()
                or line.lstrip().startswith('#')
                or re.fullmatch(r'(?:export\s+)?[A-Z][A-Z0-9_]*=.*', line)
                for line in source_lines
            )
            if data_only:
                compact: list[str] = []
                for line_number, line in enumerate(source_lines, 1):
                    if '$' not in line:
                        continue
                    compact.extend([''] * (line_number - 1 - len(compact)))
                    compact.append(line)
                input_text = '\n'.join(compact) + '\n' if compact else '\n'
                shellcheck_path = '-'
                if path == DEBIAN_ROOT / 'repo.env':
                    # The small root contract no longer needs catalog batching.
                    # Validate parent order as data, then inspect every original
                    # assignment together. The suite is the explicit external
                    # input; preserve original diagnostic line numbers.
                    _repository_selector_values()
                    source_lines[0] = 'INSTALLER_SUITE=; ' + source_lines[0]
                    input_text = '\n'.join(source_lines) + '\n'
        commands = [[
            executable,
            '--norc',
            '--shell=' + kind,
            '--format=json',
            '--severity=warning' if unbound else '--severity=error',
            shellcheck_path,
        ]]
        return path, [_run(command, timeout=30, input_text=input_text)
                      for command in commands]

    # Analyze each source independently. A bounded worker pool keeps the total
    # audit time proportional to the slowest changed source while limiting
    # process and memory pressure on the installer checkout.
    worker_count = min(2, len(paths))
    with ThreadPoolExecutor(max_workers=worker_count) as executor:
        results = list(executor.map(check_one, paths))
    for path, command_results in results:
        for result in command_results:
            if result.returncode not in (0, 1):
                _report_command(errors, f'ShellCheck {kind} {path.relative_to(ROOT)}', result)
                continue
            if not result.stdout.strip():
                continue
            try:
                messages = _shellcheck_findings(result.stdout, unbound=unbound)
            except (ValueError, TypeError) as error:
                errors.append(
                    f'ShellCheck {kind} {path.relative_to(ROOT)} returned malformed JSON: {error}'
                )
                continue
            for message in messages:
                errors.append(
                    f"{path.relative_to(ROOT)}:{message.get('line', '?')}: "
                    f"ShellCheck SC{message.get('code', '?')}: {message.get('message', 'error')}"
                )


def check_shell(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    sources = [(path, _shell_kind(path)) for path in paths]
    sources = [(path, kind) for path, kind in sources if kind]
    counts['shell_sources'] = len(sources)
    if not sources:
        counts['shell_unbound_sources'] = 0
        return
    dash = shutil.which('dash')
    bash = shutil.which('bash')
    busybox = shutil.which('busybox')
    shellcheck = shutil.which('shellcheck')
    missing = [name for name, value in (
        ('dash', dash), ('bash', bash), ('busybox', busybox), ('shellcheck', shellcheck)
    ) if not value]
    if missing:
        errors.append('required static shell checker is unavailable: ' + ', '.join(missing))
    syntax_checks = 0
    for path, kind in sources:
        commands = ([[bash, '-n', str(path)]] if bash else []) if kind == 'bash' else (
            ([[dash, '-n', str(path)]] if dash else [])
            + ([[busybox, 'sh', '-n', str(path)]] if busybox else []))
        for command in commands:
            result = _run(command)
            syntax_checks += 1
            if result.returncode:
                _report_command(errors, f'{path.relative_to(ROOT)}: shell syntax', result)
    counts['shell_syntax_parses'] = syntax_checks
    counts['shell_unbound_sources'] = len(sources) if shellcheck else 0
    # Missing tools still fail the audit. Continue the independent parsers that
    # are available so the report distinguishes findings from blocked checks.
    if not shellcheck:
        return
    for kind in ('sh', 'bash'):
        _shellcheck_batch(
            errors, shellcheck, kind,
            [path for path, source_kind in sources if source_kind == kind],
            # One warning-inclusive pass retains SC2154 and all errors.
            unbound=True,
        )


def _literal_shell_word(source: str, start: int) -> tuple[str, int]:
    """Decode one literal shell word, without expansion or shell execution.

    Shell scripts can concatenate single quotes, escaped quotes, double-quoted
    apostrophes and unquoted literal segments in one -c argument. Stopping at
    the first closing quote truncates otherwise valid scripts. Reject dynamic
    or globbing segments rather than guessing their eventual target contents.
    """
    if source[start:start + 1] != "'":
        raise ValueError('embedded shell -c requires a literal single-quoted script')
    position = start
    parts: list[str] = []
    quote = ''
    while position < len(source):
        character = source[position]
        if quote == "'":
            end = source.find("'", position)
            if end < 0:
                raise ValueError('unterminated embedded shell string')
            parts.append(source[position:end])
            position = end + 1
            quote = ''
            continue
        if not quote and (character.isspace() or character in ';|&()<>'):
            break
        if character == quote:
            quote = ''
        elif not quote and character in "'\"":
            quote = character
        elif character in '$`' or (not quote and character in '*?[~'):
            raise ValueError('embedded shell -c contains a nonliteral segment')
        elif character == '\\':
            position += 1
            if position >= len(source):
                raise ValueError('unterminated embedded shell escape')
            escaped = source[position]
            if escaped != '\n':
                if quote == '"' and escaped not in '$`"\\':
                    parts.append('\\')
                parts.append(escaped)
        else:
            parts.append(character)
        position += 1
    if quote:
        raise ValueError('unterminated embedded shell string')
    return ''.join(parts), position


def _shell_invocation_arguments(source: str, start: int) -> list[str] | None:
    """Read a fixed child argv as data; None means its width is dynamic/unknown.

    Accept literal words and quoted scalar expansions only. Never expand a
    variable, run a substitution, or guess the width of forwarded "$@", globs,
    unquoted expansions, redirections or compound shell syntax. The first word
    after the script supplies $0, rather than the child's first parameter.
    """
    # Consume one physical command, joining only explicit backslash-newline
    # continuations. This is linear in the source size and avoids a repeated
    # whitespace regex over long generated shell calls.
    lines = []
    position = start
    while position <= len(source):
        newline = source.find('\n', position)
        if newline < 0:
            lines.append(source[position:])
            break
        line = source[position:newline]
        if line.endswith('\\'):
            lines.append(line[:-1])
            position = newline + 1
            continue
        lines.append(line)
        break
    logical = ' '.join(lines)

    # Reject shell syntax and unquoted expansion before shlex normalization.
    # Quoted scalar variables are fixed-width values; positional forwarding,
    # command substitution and globbing are deliberately unknown-width.
    quote = ''
    escaped = False
    index = 0
    while index < len(logical):
        character = logical[index]
        if escaped:
            escaped = False
            index += 1
            continue
        if character == '\\' and quote != "'":
            escaped = True
            index += 1
            continue
        if quote:
            if character == quote:
                quote = ''
            elif quote == '"' and character in '`':
                return None
            elif quote == '"' and character == '$':
                if logical[index + 1:index + 2] in ('@', '*', '('):
                    return None
                if logical[index + 1:index + 3] == '${' and logical[index + 3:index + 4] in ('@', '*'):
                    return None
            index += 1
            continue
        if character in "'\"":
            quote = character
        elif character in '$`*?[~;&|<>':
            return None
        index += 1
    if quote or escaped:
        return None
    try:
        words = shlex.split(logical)
    except ValueError:
        return None
    return words[1:]


def _shell_positional_issues(body: str, arguments: list[str] | None) -> list[str]:
    """Check fixed, entry-scope bindings and explicit arity guards as data.

    Function parameters belong to their callers, not to the outer sh -c argv.
    Stop at argv replacement/shift: later parameter positions have a different
    contract. This deliberately does not claim full shell control-flow analysis.
    """
    if arguments is None:
        return []
    scope = re.sub(r'(?ms)^([ \t]*)[A-Za-z_][A-Za-z0-9_]*\(\) \{\n.*?^\1\}[ \t]*$',
                   '', body)
    scope = re.split(r'(?m)^[ \t]*(?:shift\b|set[ \t]+--(?:[ \t]|$))', scope, maxsplit=1)[0]
    issues = []
    for guard in re.finditer(r'\[ "\$#" -eq ([0-9]+) \]', scope):
        if int(guard[1]) != len(arguments):
            issues.append(f'argument guard requires {guard[1]} values, '
                          f'but invocation supplies {len(arguments)} (excluding $0)')
    for binding in re.finditer(r'(?m)^[ \t]*([A-Za-z_][A-Za-z0-9_]*)=["\x27]?'
                               r'\$(?:([1-9])|\{([1-9][0-9]*)\})', scope):
        index = int(binding[2] or binding[3])
        if index > len(arguments):
            issues.append(f'positional binding {binding[1]} requires ${index}, '
                          f'but invocation supplies {len(arguments)} arguments (excluding $0)')
    return issues


def _late_target_shells(source: str, depth: int = 0) -> list[tuple[int, str, str, list[str] | None]]:
    """Read child shell programs as data, including their nested -c scopes."""
    if depth > 8:
        raise ValueError('embedded shell quoting exceeds the supported nesting depth')
    prefix = (r'(?:/(?:usr/)?bin|"\$\{DIR_(?:USR_)?BIN\})/(?:sh|dash|bash)"?'
              r'\s+(?:-[a-z]+\s+)*-[a-z]*c[a-z]*\b')
    commands = list(re.finditer(prefix, source))
    scripts = []
    consumed_until = 0
    for command in commands:
        # The nested program is still shell-quoted at this layer. Decode its
        # owning argument first, then inspect the resulting child source.
        if command.start() < consumed_until:
            continue
        start = command.end()
        while start < len(source) and source[start].isspace():
            start += 1
        command_start = source.rfind('\n', 0, command.start()) + 1
        while command_start > 0:
            previous_start = source.rfind('\n', 0, command_start - 1) + 1
            if not source[previous_start:command_start - 1].endswith('\\'):
                break
            command_start = previous_start
        body, consumed_until = _literal_shell_word(source, start)
        source_line = source.count('\n', 0, start) + 1
        arguments = _shell_invocation_arguments(source, consumed_until)
        scripts.append((source_line, body, source[command_start:command.start()], arguments))
        scripts.extend((source_line + nested_line - 1, nested_body, invocation, nested_arguments)
                       for nested_line, nested_body, invocation, nested_arguments
                       in _late_target_shells(body, depth + 1))
    for heredoc in re.finditer(r"<<'([A-Z][A-Z0-9_]*_SH)'\n", source):
        end = re.search(r'^' + re.escape(heredoc[1]) + r'$', source[heredoc.end():], re.M)
        if end is None:
            raise ValueError('unterminated embedded shell heredoc')
        scripts.append((source.count('\n', 0, heredoc.end()) + 1,
                        source[heredoc.end():heredoc.end() + end.start()], '', None))
    return scripts


def _target_install_scope(source: str) -> tuple[str, dict[int, int], set[str], set[str], int]:
    """Project a self-reentering target mode from source data, never execution.

    Installer globals and unreachable installer functions do not belong to the
    child. Its serialized configuration and the mode flag establish its input
    variables; reachable function definitions establish the rest of its scope.
    """
    mode = re.search(r'^if \[ "\$([a-z_]+_target_mode)" = 1 \]; then\n'
                     r'  ([a-z_]+_target_install) "\$@"\n', source, re.M)
    config = re.search(r'^\{\n((?:  write_shell_config_var [^\n]+\n)+)'
                       r'\} >"\$target_profile_host"$', source, re.M)
    if mode is None or config is None:
        raise ValueError('target-install mode has no recognized entrypoint/configuration producer')
    fields: set[str] = set()
    for line in config[1].splitlines():
        words = shlex.split(line)
        if (len(words) != 3 or words[0] != 'write_shell_config_var'
                or re.fullmatch(r'[A-Z][A-Z0-9_]*', words[1]) is None
                or words[2] not in ('$' + words[1], '${' + words[1] + '}')
                or words[1] in fields):
            raise ValueError('target-install configuration has an ambiguous field producer')
        fields.add(words[1])
    definitions: dict[str, tuple[int, str]] = {}
    for function in re.finditer(r'^([a-zA-Z_][a-zA-Z0-9_]*)\(\) \{\n', source, re.M):
        closing = re.search(r'^\}\s*$', source[function.end():], re.M)
        if closing is None or function[1] in definitions:
            raise ValueError('target-install function definition is incomplete or duplicated')
        end = function.end() + closing.end()
        definitions[function[1]] = (source.count('\n', 0, function.start()) + 1,
                                    source[function.start():end])
    if mode[2] not in definitions:
        raise ValueError('target-install entrypoint definition is missing')
    reachable: set[str] = set()
    pending = [mode[2]]
    while pending:
        name = pending.pop()
        if name in reachable:
            continue
        reachable.add(name)
        # Overapproximate literal function references, including trap callbacks.
        # An extra definition is safe; omitting a reachable definition is not.
        words = set(re.findall(r'\b[a-zA-Z_][a-zA-Z0-9_]*\b', definitions[name][1]))
        pending.extend(sorted((words & definitions.keys()) - reachable))
    lines = ['#!/bin/sh', 'set -eu', mode[1] + '=1',
             *(field + '=' for field in sorted(fields))]
    origins: dict[int, int] = {}
    for name in sorted(reachable, key=lambda item: definitions[item][0]):
        original_line, body = definitions[name]
        for offset, line in enumerate(body.splitlines()):
            origins[len(lines) + 1] = original_line + offset
            lines.append(line)
    lines.append(mode[2] + ' "$@"')
    projected = '\n'.join(lines) + '\n'
    component = mode[2].split('_', 1)[0].upper() + '_'
    bodies = '\n'.join(definitions[name][1] for name in sorted(reachable))
    required = set(re.findall(r'\$\{?(' + component + r'[A-Z0-9_]+)\b', bodies))
    assigned = set(re.findall(r'^\s*(?:export\s+)?(' + component + r'[A-Z0-9_]+)=', bodies, re.M))
    return projected, origins, fields, required - assigned - fields, len(reachable)


def _target_shell_policy_fields(body: str) -> set[str]:
    """Read the fields of a policy explicitly sourced by the child itself."""
    published = _render_installer_path_placeholders('__INSTALLER_PATH_DIR_ETC_LABWC__/desktop.conf')
    if re.search(r'^\s*\.\s+' + re.escape(published) + r'\s*$', body, re.M) is None:
        return set()
    selectors = _repository_selector_values()
    source = _read_text(DEBIAN_ROOT / 'hooks/target/etc/labwc/desktop.conf.tmpl')
    return set(re.findall(r'^([A-Z][A-Z0-9_]*)=', source, re.M))


def check_late_target_shells(paths: list[Path], errors: list[str],
                            counts: dict[str, int]) -> None:
    """Check separate shell scopes against their explicit invocation contract."""
    scripts_root = DEBIAN_ROOT / 'scripts'
    late_root = scripts_root / 'late'
    account_wrapper = late_root / 'devops/account-execution.sh'
    owners = sorted(path for path in paths if path.is_relative_to(scripts_root)
                    and _shell_kind(path))
    if not owners:
        return
    shellcheck = shutil.which('shellcheck')
    dash, busybox = shutil.which('dash'), shutil.which('busybox')
    if not shellcheck or not dash or not busybox:
        errors.append('embedded shell checker requires shellcheck, dash and busybox')
    syntax_commands = ([[dash, '-n']] if dash else []) + ([[busybox, 'sh', '-n']] if busybox else [])
    # Only this wrapper's env -i declarations establish its target API. Never
    # declare arbitrary installer/global names merely to silence SC2154.
    wrapper_source = _read_text(account_wrapper)
    wrapper_names = sorted(set(re.findall(r'^\s+([A-Z][A-Z0-9_]*)=', wrapper_source, re.M)))
    checked = 0
    positional_checked = 0
    managed_checked = 0
    target_modes = target_functions = target_fields = 0
    for owner in owners:
        try:
            source = _render_installer_path_placeholders(_read_text(owner))
            if re.search(r'__INSTALLER_PATH_[A-Z0-9_]+__', source):
                raise ValueError('installer script has unresolved runtime path placeholders')
            for source_line, body, invocation, arguments in _late_target_shells(source):
                for issue in _shell_positional_issues(body, arguments):
                    errors.append(f'{owner.relative_to(ROOT)}:{source_line}: {issue}')
                positional_checked += arguments is not None
                declared = _target_shell_policy_fields(body)
                if re.match(r'\s*devops_run_as_account(?:_from_payload)?\b', invocation):
                    declared.update(wrapper_names)
                else:
                    # Early/partman children can run in d-i rather than the
                    # target. Only explicit inline environment assignments
                    # belong to the invocation, never the parent's globals.
                    declared.update(re.findall(r'(?<!\S)([A-Z][A-Z0-9_]*)=', invocation))
                for command in syntax_commands:
                    result = _run(command, timeout=15, input_text=body)
                    if result.returncode:
                        _report_command(errors, f'{owner.relative_to(ROOT)}:{source_line}: '
                                        'embedded shell syntax', result)
                # Outer shellcheck directives and assignments do not apply to
                # this new shell. Include uppercase names: DIR_* variables are
                # not an implicit target environment API.
                checked_body = '\n'.join(name + '=' for name in sorted(declared)) + '\n' + body
                result = (_run([shellcheck, '--norc', '--shell=sh', '--format=json',
                                '--severity=warning', '--enable=check-unassigned-uppercase', '-'],
                               timeout=15, input_text=checked_body) if shellcheck else None)
                if result is None:
                    pass  # Missing checker is an audit error recorded above.
                elif result.returncode not in (0, 1):
                    _report_command(errors, f'{owner.relative_to(ROOT)}:{source_line}: '
                                    'embedded target shell', result)
                else:
                    for message in _shellcheck_findings(result.stdout, unbound=True):
                        errors.append(f'{owner.relative_to(ROOT)}:{source_line}: '
                                      f"target shell line {message.get('line', 0) - len(declared) - 1}: "
                                      f"ShellCheck SC{message.get('code', '?')}: "
                                      f"{message.get('message', 'error')}")
                checked += 1
                if owner.name in {'software.sh.tmpl', 'tor-browser.sh'}:
                    managed_checked += 1
            if re.search(r'^\s*--target-install\)', source, re.M):
                body, origins, fields, missing, functions = _target_install_scope(source)
                if missing:
                    errors.append(f'{owner.relative_to(ROOT)}: target-install configuration omits '
                                  + ', '.join(sorted(missing)))
                for command in syntax_commands:
                    result = _run(command, timeout=15, input_text=body)
                    if result.returncode:
                        _report_command(errors, f'{owner.relative_to(ROOT)}: target-install syntax', result)
                result = (_run([shellcheck, '--norc', '--shell=sh', '--format=json',
                                '--severity=warning', '--enable=check-unassigned-uppercase', '-'],
                               timeout=15, input_text=body) if shellcheck else None)
                if result is None:
                    pass  # Missing checker is an audit error recorded above.
                elif result.returncode not in (0, 1):
                    _report_command(errors, f'{owner.relative_to(ROOT)}: target-install scope', result)
                else:
                    for message in _shellcheck_findings(result.stdout, unbound=True):
                        line = origins.get(message.get('line', 0), 1)
                        errors.append(f'{owner.relative_to(ROOT)}:{line}: target-install '
                                      f"ShellCheck SC{message.get('code', '?')}: "
                                      f"{message.get('message', 'error')}")
                target_modes += 1
                target_functions += functions
                target_fields += len(fields)
        except (OSError, UnicodeError, ValueError) as error:
            errors.append(f'{owner.relative_to(ROOT)}: embedded target shell: {error}')
    counts['installer_child_shell_owners'] = len(owners)
    counts['installer_child_shells'] = checked
    counts['installer_child_fixed_argv'] = positional_checked
    counts['managed_software_target_shells'] = managed_checked
    counts['late_target_install_scopes'] = target_modes
    counts['late_target_install_functions'] = target_functions
    counts['late_target_install_config_fields'] = target_fields
    counts['installer_child_shellcheck_scopes'] = checked + target_modes if shellcheck else 0
    counts['installer_child_syntax_parses'] = (checked + target_modes) * len(syntax_commands)


def _devops_account_publication_issues(wrapper: str, configs: str, orchestration: str,
                                     layout: str) -> list[str]:
    """Inspect direct payload publication as data, never run target code."""
    issues = []
    programs = []
    for command in re.finditer(r'(?:/usr/bin/python3|"\$\{DIR_USR_BIN\}/python3")\s+-I\s+-c\s+', wrapper):
        try:
            program, _end = _literal_shell_word(wrapper, command.end())
            ast.parse(program)
            programs.append(program)
        except (SyntaxError, ValueError) as error:
            issues.append('invalid account handoff Python: ' + str(error))
    if len(programs) != 2:
        issues.append('account handoff requires one privileged reader and one account writer')
    else:
        reader, writer = programs
        for token in ('os.geteuid() != 0', 'source.is_relative_to(root)',
                      'source.resolve(strict=True) != source', 'directory.stat()',
                      'info.st_uid or info.st_gid or info.st_mode & 0o022',
                      'os.O_NOFOLLOW', 'os.O_NONBLOCK', 'info.st_nlink != 1'):
            if token not in reader:
                issues.append('privileged payload reader omits ' + token)
        positions = [reader.find(token) for token in (
            'fd = os.open(source,', 'info = os.fstat(fd)',
            'os.dup2(fd, 0, inheritable=True)', 'os.close(fd)', 'os.execv(')]
        if -1 in positions or positions != sorted(positions):
            issues.append('payload input must be opened and checked before descriptor handoff and exec')
        for token in ('source = os.fstat(0)', 'data = sys.stdin.buffer.read(',
                      'source.st_nlink != 1', 'source.st_mode & 0o022',
                      'home_path.resolve(strict=True) != home_path',
                      'name in (".", "..")', 'owned_directory(home)', 'owned_directory(parent)',
                      'os.O_DIRECTORY | os.O_NOFOLLOW', 'info.st_uid != os.getuid()',
                      'info.st_gid != os.getgid()',
                      'os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW', 'os.link(candidate,',
                      'follow_symlinks=False', 'except FileExistsError:',
                      'existing account configuration differs; preserve it for review',
                      'os.unlink(candidate, dir_fd=parent)', 'os.fsync(parent)'):
            if token not in writer:
                issues.append('account configuration writer omits ' + token)
        if re.search(r'os\.open\(source\b|Path\(sys\.argv\[1\]\)', writer):
            issues.append('account writer must consume the open payload descriptor')

    for token in ("devops_execute_as_account '' \"$@\"", '/env -i \\\n',
                  "set -- \"${DIR_USR_BIN}/python3\" -I -c '",
                  "' \"${account_input%/*}\" \"$account_input\" \"$@\"",
                  'run_in_target "$run_label" "$@"',
                  'devops_run_as_account_from_payload "$config_source" "$config_label"',
                  'input_parent="${target_root}${DIR_VAR_LIB_INSTALLER_STATE}"',
                  'installer_apt_safe_path "$input_parent"',
                  'mktemp -d "$input_parent/.devops-account.XXXXXX"',
                  'install -m 0600 -- "$payload_input" "$input_stage/input"',
                  'chown root:root "$input_stage" "$input_stage/input"',
                  'trap cleanup_account_input 0', 'rmdir -- "$input_stage"'):
        if token not in wrapper:
            issues.append('account execution/publication contract omits ' + repr(token))
    publications = []
    for match in re.finditer(r'(?m)^  devops_publish_account_config\b(?:[^\n]*\\\n)*[^\n]*', configs):
        try:
            words = shlex.split(match[0].replace('\\\n', ''), comments=True)
            publications.append(tuple(words[1:]))
        except ValueError as error:
            issues.append('invalid account publication argv: ' + str(error))
    expected = {
        ('$rendered_tmp',
         'publish the account Bazel cache policy', '.bazelrc', '0600'),
        ('$rendered_tmp',
         'publish the account Bazel shell policy', '.config/bazel/bazelrc', '0600'),
        ('$rendered_tmp',
         'stage managed Packer template for primary account',
         '.config/packer/template.pkr.hcl', '0644', '.config/mise'),
    }
    if len(publications) != len(expected) or set(publications) != expected:
        issues.append('both Bazel entrypoints and Packer must publish their account copies directly from the rendered payload')
    for token in ('[ "$selector" = hooks/target/usr/local/share/common/devops/config/yt-dlp.conf ]',
                  'set -- "stage downloader user configuration and plugin directory"',
                  '.config/yt-dlp/config 0600 .config/yt-dlp/plugins',
                  '0644 youtube-configuration "$@"'):
        if token not in configs:
            issues.append('yt-dlp must publish its private account copy directly from the payload: ' + token)
    stages = [layout.find(token) for token in (
        'install -m "$mode" "$tmp_asset" "$target_host_path"', 'shift 4',
        'devops_publish_account_config "$tmp_asset" "$@"', 'rm -f -- "$tmp_asset"')]
    if -1 in stages or stages != sorted(stages):
        issues.append('shared asset publication must use the rendered payload for both destinations before cleanup')
    if 'DEVOPS_SKEL_DIR' in wrapper or any('DEVOPS_SKEL_DIR' in words[0] for words in publications):
        issues.append('primary account publication must not read the separately installed skeleton')
    for name in ('devops_install_youtube_policy', 'devops_render_bazelrc', 'devops_render_packer_template'):
        function = re.search(r'^' + name + r'\(\) [({]\n.*?^[})]$', configs, re.M | re.S)
        if function is None:
            issues.append('missing skeleton publisher: ' + name)
            continue
        body = function[0]
        if re.search(r'\bdevops_run_as_account\b', body):
            issues.append(name + ': unprivileged command must not open a private skeleton pathname')
        if 'install ' not in body or 'chown root:root' not in body or 'DEVOPS_SKEL_DIR' not in body:
            issues.append(name + ': retain the separately published root-owned skeleton copy')
        if name != 'devops_install_youtube_policy':
            stages = [body.find('devops_publish_account_config '),
                      body.rfind('rm -f -- "$template_tmp" "$rendered_tmp"')]
            if -1 in stages or stages != sorted(stages):
                issues.append(name + ': rendered account input must remain available until publication')
    for family in ('desktop', 'server'):
        if family + ') DEVOPS_SKEL_DIR=$DIR_ETC_SKEL_' + family.upper() not in orchestration:
            issues.append('account publication must use the selected ' + family + ' skeleton')
    return issues


def check_devops_account_publication(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    directory = DEBIAN_ROOT / 'scripts/late/devops'
    owners = [directory / name for name in (
        'account-execution.sh', 'tool-configs.sh', 'main-orchestration.sh', 'publication-layout.sh')]
    if not set(owners + [Path(__file__).resolve()]).intersection(paths):
        return
    for issue in _devops_account_publication_issues(*map(_read_text, owners)):
        errors.append('DevOps skeleton/account publication: ' + issue)
    counts['devops_account_publications'] = 4
    counts['devops_account_python_programs'] = 2


def check_private_skeletons(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    owners = {
        DEBIAN_ROOT / 'scripts/late/account.sh': (
            'install -d -m 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}',
            'chmod 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}'),
        DEBIAN_ROOT / 'scripts/late/devops/codex-appserver.sh': (
            '"${target_root}${DEVOPS_SKEL_DIR}") managed_base_mode=0700',
            'chmod "$managed_base_mode" "$managed_base_dir"'),
        DEBIAN_ROOT / 'scripts/common/modules/target-publication.sh': (
            '"${DIR_ETC_SKEL_BASE:-}" "${DIR_ETC_SKEL_DESKTOP:-}" "${DIR_ETC_SKEL_SERVER:-}"',
            'install -d -m 0700 -- "${TARGET_ROOT}${skeleton}"',
            'chown root:root "${TARGET_ROOT}${skeleton}"'),
        DEBIAN_ROOT / 'scripts/common/render.pl': (
            '|| grep { $current eq $_ } @{$policy->{skeletons}}) ? 0700 : 0755',
            'chmod(0700, $skeleton) == 1', 'chown(0, 0, $temporary) == 1'),
        DEBIAN_ROOT / 'scripts/firstboot/04-validation.sh.tmpl': (
            'find -P "$skeleton" -maxdepth 0 -printf "%U:%G:%m")" = "0:0:700"',),
        target_source('usr/local/bin/labwc-sync-application-launchers.tmpl'): (
            'TUTA_MANAGED_DESKTOP_SOURCE = "__INSTALLER_PATH_DIR_USR_LOCAL_SHARE_APPLICATIONS__/tutanota-desktop.desktop"',),
        target_source('usr/local/lib/python3/dist-packages/labwc_managed_app/profiles.py.tmpl'): (
            '"__INSTALLER_PATH_DIR_USR_LOCAL_SHARE__/keepassxc/keepassxc.ini"',),
        DEBIAN_ROOT / 'scripts/desktop/components/target-assets.sh': (
            '"${DIR_USR_LOCAL_SHARE_APPLICATIONS}/tutanota-desktop.desktop"',
            'hooks/target/etc/skel-desktop/.config/keepassxc/keepassxc.ini.tmpl "${DIR_USR_LOCAL_SHARE}/keepassxc/keepassxc.ini" 0644'),
        DEBIAN_ROOT / 'scripts/late/software.sh.tmpl': (
            'tuta_desktop_file=__INSTALLER_PATH_DIR_USR_LOCAL_SHARE_APPLICATIONS__/tutanota-desktop.desktop',),
        target_source('etc/apparmor.d/desktop-wrappers.tmpl'): (
            '__INSTALLER_PATH_DIR_USR_LOCAL_SHARE__/keepassxc/keepassxc.ini r,',
            'applications/{discord,postman,ledger-live,tutanota-desktop}.desktop r,'),
    }
    if not set(owners.keys() | {Path(__file__).resolve()}).intersection(paths):
        return
    for owner, contracts in owners.items():
        source = _read_text(owner)
        for token in contracts:
            if token not in source:
                errors.append(f'{owner.relative_to(ROOT)}: private skeleton contract omits {token}')
    counts['private_skeleton_roots'] = 3
    counts['private_skeleton_runtime_defaults'] = 2


def _skeleton_destination_issues(foundation: str, waypaper: str, publication: str,
                                 program: str, publisher: str) -> list[str]:
    """Check independent template/HOME destinations without running installer code."""
    issues = []
    server_publish = 'installer_publish_primary_defaults server "$server_operator" "$ACCOUNT_HOME"'
    account_check = 'account server "$server_operator"'
    if server_publish not in foundation:
        issues.append('server foundation must publish every selected payload default to the primary HOME')
    elif account_check not in foundation or foundation.index(server_publish) < foundation.index(account_check):
        issues.append('server primary defaults must follow the explicit account identity check')
    for token in ('hooks/target/etc/skel-server/.profile.d/73-whisper-llama-srv.sh', 'hooks/target/etc/skel-server/.profile.d/72-ci-runners-srv.sh.tmpl',
                  'hooks/target/etc/skel-server/.bashrc', 'hooks/target/etc/skel-server/.bash_profile',
                  'hooks/target/etc/skel-server/.bash_aliases', 'hooks/target/etc/skel-server/.profile '):
        if token not in foundation:
            issues.append('server template publication omits ' + token)
    for token in ('waypaper_launcher_dir="${ACCOUNT_HOME}/.local/share/applications"',
                  'waypaper_launcher="${waypaper_launcher_dir}/waypaper.desktop"',
                  '"${DIR_ETC_SKEL_DESKTOP}/.local/share/applications/waypaper.desktop" 0644',
                  'hooks/target/etc/skel-desktop/.local/share/applications/waypaper.desktop.tmpl',
                  'installer_publish_primary_defaults desktop "$ACCOUNT_USERNAME" "$ACCOUNT_HOME"',
                  '    .local/share/applications/waypaper.desktop'):
        if token not in waypaper:
            issues.append('Waypaper must render its payload launcher to both destinations: ' + token)
    rendered = waypaper.find('hooks/target/etc/skel-desktop/.local/share/applications/waypaper.desktop.tmpl')
    barrier = waypaper.find('installer_asset_batch_flush', rendered)
    primary = waypaper.find('installer_publish_primary_defaults desktop', rendered)
    if not (0 <= rendered < barrier < primary):
        issues.append('Waypaper primary launcher must follow its concrete capture and publication barrier')
    if '--relative "$4"' not in publication:
        issues.append('primary payload adapter must support an exact-file publication without replaying HOME defaults')
    batch = publisher.split('sub publish_assets {', 1)[-1].split('\nsub main {', 1)[0]
    captured = batch.find('$primary{$primary_path} = [$result, oct($mode)]')
    future = batch.find("$future{ACCOUNT_HOME} = '$HOME'")
    if not (0 <= captured < future):
        issues.append('independent primary payload capture must precede reusable account values')
    for family in ('desktop', 'server'):
        token = '"${DIR_ETC_SKEL_' + family.upper() + '}/"*) default_family=' + family
        if token not in publication:
            issues.append(f'{family} template publication must retain an independent payload input')
    for token in ('with os.scandir(directory) as iterator:', 'for name in entries(source):',
                  'publish(input_dir, output_dir, account, budget, depth + 1,',
                  'selected[1:] if selected is not None else None',
                  'if selected is not None and name != selected[0]:',
                  'selected payload default must name a regular file',
                  "require(found, 'selected payload default is absent')",
                  'args.home == Path(account.pw_dir)',
                  'os.fchown(stream.fileno(), account.pw_uid, account.pw_gid)',
                  'os.fchmod(stream.fileno(), 0o700 if info.st_mode & 0o111 else 0o600)',
                  'os.fchown(home, account.pw_uid, account.pw_gid)', 'os.fchmod(home, 0o700)'):
        if token not in program:
            issues.append('complete private HOME publication omits ' + token)
    return issues


def check_primary_payload_defaults(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    publication = DEBIAN_ROOT / 'scripts/common/modules/target-publication.sh'
    publisher = DEBIAN_ROOT / 'scripts/common/render.pl'
    program = DEBIAN_ROOT / 'scripts/common/primary-defaults.py'
    boundaries = [DEBIAN_ROOT / name for name in (
        'scripts/late/target-assets.sh', 'scripts/desktop/components/rendering-access.sh')]
    runtime_roots = [TARGET_ROOT / 'usr/local' / leaf for leaf in ('bin', 'sbin', 'libexec', 'lib')]
    foundation = DEBIAN_ROOT / 'scripts/server/foundation.sh'
    waypaper = DEBIAN_ROOT / 'scripts/desktop/waypaper.sh'
    related = [DEBIAN_ROOT / name for name in (
        'scripts/late/account.sh', 'scripts/desktop/components/user-config.sh',
        'scripts/desktop/components/gpg-bootstrap.sh', 'scripts/late/ch341a.sh',
        'scripts/common/hardware-tuning-config.py', 'scripts/common/hardware-tuning.sh',
        'scripts/server/setup.py.tmpl', 'scripts/late/dispatch.sh')]
    affected = ({publication, publisher, program, foundation, waypaper, Path(__file__).resolve(),
                 DEBIAN_ROOT / 'hooks/installer/di.env'} | set(boundaries) | set(related))
    if not (affected.intersection(paths) or any(
            path.is_relative_to(directory) for path in paths for directory in runtime_roots)):
        return
    banned = re.compile(rb'skel[-_](?:base|desktop|server)', re.I)
    account_creator = target_source('usr/local/sbin/account-create')
    inspected = 0
    for directory in runtime_roots:
        for owner in sorted(directory.rglob('*')):
            if not owner.is_file() or owner.is_symlink():
                continue
            # The sole administrative account creator has a separate root-only
            # provisioning contract below. No application/library is exempt.
            if owner == account_creator:
                continue
            # Every library/wrapper file, including all Python and Perl tree
            # support files, is data here. Never import even a discovery hook.
            inspected += 1
            if banned.search(owner.read_bytes()):
                errors.append(f'{owner.relative_to(ROOT)}: installed runtime code mentions a private future-account skeleton')
    for owner in [publication, boundaries[0]]:
        source = _read_text(owner)
        if 'installer_capture_primary_default ' not in source:
            errors.append(f'{owner.relative_to(ROOT)}: publication does not retain independent rendered payload defaults')
    desktop = _read_text(boundaries[1])
    if ('installer_asset_publish "$desktop_plan_kind" "$desktop_plan_source"' not in desktop
            or 'installer_capture_primary_default ' in desktop):
        errors.append('desktop templates must delegate primary/future publication to the shared Perl owner')
    batch = _read_text(publisher).split('sub publish_assets {', 1)[-1].split('\nsub main {', 1)[0]
    capture = batch.find('$primary{$primary_path} = [$result, oct($mode)]')
    future = batch.find("$future{ACCOUNT_HOME} = '$HOME'")
    if (capture < 0 or future < 0 or capture > future
            or "$future{ACCOUNT_USERNAME} = '$USER'" not in batch
            or "for my $key (grep { /\\ADIR_HOME_/ } keys %future)" not in batch
            or 'future-account directory escapes the primary account HOME' not in batch
            or 'publication_render($data, $kind, \\%future, \\%blocks, $paths)' not in batch):
        errors.append('Perl publication must retain concrete primary inputs before rendering bounded account-relative defaults')
    source = _read_text(publication)
    for token in ('default_output=$(installer_primary_default_path "$default_target")',
                  'scripts/common/primary-defaults.py', '"${DIR_INSTALLER_TARGET_DEFAULTS}/$1"'):
        if token not in source:
            errors.append('primary account payload contract omits ' + token)
    source = _read_text(program)
    ast.parse(source)
    for token in ('account.pw_uid', 'account.pw_gid', 'args.home == Path(account.pw_dir)',
                  'args.home.resolve(strict=True) == args.home', 'os.O_DIRECTORY | os.O_NOFOLLOW',
                  'os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW', 'os.fchown(stream.fileno(),',
                  'os.replace(candidate, name, src_dir_fd=destination, dst_dir_fd=destination)',
                  'os.fsync(destination)', 'identity(os.fstat(input_file)) == identity(info)'):
        if token not in source:
            errors.append('primary account publication omits ' + token)
    if source.find('os.fchown(stream.fileno(),') > source.find('os.replace(candidate, name,'):
        errors.append('primary payload files must receive their account ownership before publication')
    for issue in _skeleton_destination_issues(_read_text(foundation), _read_text(waypaper),
                                              _read_text(publication), source, _read_text(publisher)):
        errors.append('payload template/HOME destinations: ' + issue)
    for owner in [DEBIAN_ROOT / 'scripts/late/account.sh',
                  DEBIAN_ROOT / 'scripts/desktop/components/user-config.sh']:
        if 'installer_publish_primary_defaults desktop "$ACCOUNT_USERNAME" "$ACCOUNT_HOME"' not in _read_text(owner):
            errors.append(f'{owner.relative_to(ROOT)}: primary home is not published from payload inputs')
    server = _read_text(DEBIAN_ROOT / 'scripts/server/setup.py.tmpl')
    if 'source = payload_defaults_root() /' not in server or 'DIR_ETC_SKEL' in server:
        errors.append('server account setup must consume private payload inputs')
    gpg = _read_text(DEBIAN_ROOT / 'scripts/desktop/components/gpg-bootstrap.sh')
    if ('gpg_agent_template=$6' not in gpg
            or '"${DIR_INSTALLER_TARGET_DEFAULTS}/desktop/.gnupg/gpg-agent.conf"' not in gpg
            or banned.search(gpg.encode())):
        errors.append('desktop GPG setup must consume independent rendered payload inputs')
    firmware = _read_text(DEBIAN_ROOT / 'scripts/late/ch341a.sh')
    if '"${DIR_INSTALLER_TARGET_DEFAULTS}/desktop/.profile.d/75-firmware-workspace.sh"' not in firmware:
        errors.append('desktop firmware account profile must consume independent payload inputs')
    hardware = _read_text(DEBIAN_ROOT / 'scripts/common/hardware-tuning-config.py')
    hardware_caller = _read_text(DEBIAN_ROOT / 'scripts/common/hardware-tuning.sh')
    if ("str(payload_defaults / '.config/waybar/modules/battery')" not in hardware
            or 'payload_defaults=Path(argv[4])' not in hardware
            or '"${DIR_INSTALLER_TARGET_DEFAULTS}/desktop" $hardware_vendors' not in hardware_caller):
        errors.append('hardware battery defaults must be rendered independently for both publications')
    policy = _read_text(target_source('etc/apparmor.d/desktop-wrappers.tmpl'))
    for hook in ('autostart', 'shutdown'):
        attachment = '__INSTALLER_PATH_DIR_HOME__/*/.config/labwc/' + hook
        if (f'profile labwc-{hook}-hook {attachment} flags=' not in policy
                or attachment + ' rix,' not in policy):
            errors.append('desktop ' + hook + ' confinement must cover future accounts under the home root')
    if banned.search(policy.encode()):
        errors.append('desktop wrappers must not execute or read private skeleton defaults')
    counts['runtime_skeleton_free_files'] = inspected
    counts['primary_payload_capture_boundaries'] = 3
    counts['primary_account_payload_publishers'] = 4
    counts['skeleton_payload_source_files'] = sum(
        1 for family in ('desktop', 'server')
        for path in (TARGET_ROOT / 'etc' / ('skel-' + family)).rglob('*') if path.is_file())
    counts['skeleton_role_destination_pairs'] = 2


def _account_creation_issues(program: str, publication: str, rendering: str,
                             dispatcher: str, publisher: str) -> list[str]:
    """Inspect the administrative boundary without importing its implementation."""
    issues = []
    try:
        tree = ast.parse(program)
    except SyntaxError as error:
        return ['account creator has invalid Python: ' + str(error)]
    functions = {node.name: ast.get_source_segment(program, node) or ''
                 for node in tree.body if isinstance(node, ast.FunctionDef)}
    main = functions.get('main', '')
    root_gate = 'os.getuid() == os.geteuid() == 0'
    if root_gate not in main or main.find(root_gate) > main.find('create(args.username, args.role)'):
        issues.append('future account creation requires real and effective root before mutation')
    for token in ("choices=('base', 'desktop', 'server'), default='base'",
                  "'base': Path('__INSTALLER_PATH_DIR_ETC_SKEL_BASE__')",
                  "'desktop': Path('__INSTALLER_PATH_DIR_ETC_SKEL_DESKTOP__')",
                  "'server': Path('__INSTALLER_PATH_DIR_ETC_SKEL_SERVER__')",
                  "'--create-home'", "'--user-group', '--groups', ''",
                  "'--password', '!'", "'HOME_MODE=0700'", "'UMASK=077'",
                  'os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC',
                  'fcntl.LOCK_EX | fcntl.LOCK_NB',
                  'info.st_uid == info.st_gid == 0', 'stat.S_IMODE(info.st_mode) == 0o700',
                  'same-named group already exists', 'HOME already exists',
                  'info.st_nlink == 1', 'template file identity changed',
                  'template directory changed during capture',
                  "role == 'desktop'", "incoming / '.config/labwc/rc.xml'",
                  'user=account.pw_uid, group=account.pw_gid',
                  'os.getuid() == os.geteuid() == account.pw_uid',
                  'a service or non-login account cannot receive human defaults',
                  'external_unit_link(relative, target)',
                  "record(work, username, role, 'outcome-unknown')",
                  'do not retry automatically; retained evidence:',
                  'os.fsync(parent)'):
        if token not in program:
            issues.append('future-account ownership/recovery contract omits ' + token)
    personalize = functions.get('personalize', '')
    initializer = next((node for node in tree.body
                        if isinstance(node, ast.FunctionDef) and node.name == 'personalize'), None)
    if initializer is None or any(
            isinstance(node, ast.Name) and node.id == 'SOURCES'
            or isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
            and node.func.id in {'snapshot', 'create'} for node in ast.walk(initializer)):
        issues.append('unprivileged HOME initialization must not read private templates or create accounts')
    for token in ("'todoFilePath'", "'lastSavePath', 'lastOpenPath', 'lastImagePath', 'audioFolder'",
                  "'preferred_temp_dir', 'preferred_extract_dir'", "uri.startswith('file://$HOME/')",
                  "user_file(home, '.bazelrc'", "user_file(home, '.config/bazel/bazelrc'"):
        if token not in personalize:
            issues.append('future HOME typed application initialization omits ' + token)
    for suffix, leaf in (('PROFILE', '.profile'), ('BASH_PROFILE', '.bash_profile'),
                         ('BASHRC', '.bashrc'), ('BASH_LOGOUT', '.bash_logout')):
        token = 'installer_stage_profile_file hooks/target/etc/skel-base/' + leaf
        if token not in publication or '${DIR_ETC_SKEL_BASE}/' + leaf not in publication:
            issues.append('base skeleton requires an explicit registered source member: ' + suffix)
    if '"FILE_TARGET_SKEL_BASE_${' in publication:
        issues.append('base skeleton source selectors must not be constructed from an incomplete prefix')
    primary = publication.split('installer_publish_primary_defaults()', 1)[-1].split('\n}', 1)[0]
    if 'FILE_ACCOUNT_CREATE' in primary or '--personalize' in primary or '--prepare-home' in primary:
        issues.append('installer primary HOME must be published directly from its own rendered payload input')
    staged = dispatcher.find('\ninstaller_stage_account_creation\n')
    plan = dispatcher.find('while IFS=')
    if staged < 0 or (plan >= 0 and staged > plan):
        issues.append('future-account assets must be staged before late plan execution')
    if 'installer_asset_publish "$desktop_plan_kind" "$desktop_plan_source"' not in rendering:
        issues.append('desktop account defaults must delegate to the shared publication owner')
    batch = publisher.split('sub publish_assets {', 1)[-1].split('\nsub main {', 1)[0]
    captured = batch.find('$primary{$primary_path} = [$result, oct($mode)]')
    generic = batch.find("$future{ACCOUNT_HOME} = '$HOME'")
    if captured < 0 or generic < 0 or captured > generic:
        issues.append('primary concrete HOME input must be captured before reusable account-relative rendering')
    if "$future{ACCOUNT_USERNAME} = '$USER'" not in batch:
        issues.append('reusable defaults must not retain the installer primary username')
    for token in ("for my $family_name (qw(desktop server))",
                  'future-account directory escapes the primary account HOME',
                  'publication_render($data, $kind, \\%future, \\%blocks, $paths)'):
        if token not in batch:
            issues.append('shared primary/future publication omits ' + token)
    return issues


def check_account_creation(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    creator = target_source('usr/local/sbin/account-create')
    publication = DEBIAN_ROOT / 'scripts/common/modules/target-publication.sh'
    rendering = DEBIAN_ROOT / 'scripts/desktop/components/rendering-access.sh'
    dispatcher = DEBIAN_ROOT / 'scripts/late/dispatch.sh'
    base = TARGET_ROOT / 'etc/skel-base'
    runtime = DEBIAN_ROOT / 'hosts/installer/runtime.env'
    renderer = DEBIAN_ROOT / 'scripts/common/modules/files-logging.sh'
    publisher = DEBIAN_ROOT / 'scripts/common/render.pl'
    if not ({creator, publication, rendering, dispatcher, runtime, renderer, publisher, Path(__file__).resolve()}.intersection(paths)
            or any(path.is_relative_to(base) for path in paths)):
        return
    for issue in _account_creation_issues(*map(_read_text, (creator, publication, rendering, dispatcher, publisher))):
        errors.append('account defaults: ' + issue)
    runtime_source = _read_text(runtime)
    runtime_fields = dict(_runtime_path_schema_rows())
    for name in ('FILE_ACCOUNT_CREATE', 'DIR_ACCOUNT_PROVISIONING', 'DIR_ETC_SKEL_BASE'):
        if not re.search(r'^' + name + r'="', runtime_source, re.M) or runtime_fields.get('PATH_' + name) != name:
            errors.append('new account path lacks its canonical runtime owner/shared renderer: ' + name)
    for leaf in ('.profile', '.bash_profile', '.bashrc', '.bash_logout'):
        source = _read_text(base / leaf)
        if (re.search(r'skel[-_](?:desktop|server)|/home/[A-Za-z0-9_-]+', source)
                or 'umask 077' not in source and leaf not in ('.bash_profile',)):
            errors.append('minimal base defaults must remain private and independent of desktop/server defaults: ' + leaf)
    counts['future_account_types'] = 3
    counts['base_shell_defaults'] = 4


def check_lifecycle_frontend_contract(paths: list[Path], errors: list[str],
                                      counts: dict[str, int]) -> None:
    """Check the bootstrapped fatal UI contract as data, without opening a frontend."""
    selectors = _repository_selector_values('forky')
    lifecycle = DEBIAN_ROOT / 'scripts/common/lifecycle.sh'
    source = DEBIAN_ROOT / 'scripts/common/source.sh'
    generated = {ROOT / 'd-i' / suite / name for suite in ('forky', 'trixie')
                 for name in ('source.sh', 'preseed.cfg', 'payload.tar.gz')}
    if not ({lifecycle, source} | generated).intersection(paths):
        return
    canonical, embedded = _read_text(lifecycle), _read_text(source)
    begin, end = '# BEGIN EMBEDDED LIFECYCLE\n', '# END EMBEDDED LIFECYCLE\n'
    if (embedded.count(begin) != 1 or embedded.count(end) != 1
            or embedded.split(begin, 1)[1].split(end, 1)[0] != canonical):
        errors.append('bootstrap lifecycle differs from canonical fatal-handler source')
    component = re.search(r'^installer_failure_component\(\) \(\n(.*?)^\);',
                          canonical, re.M | re.S)
    if (not component or any(token not in component[1] for token in (
            '"${1:-}" "${INSTALLER_LOG_TAG:-}" "${INSTALLER_PHASE:-}"',
            '*://*|*[!A-Za-z0-9_./:+-]*',
            '[ "${#lc_component_candidate}" -le 240 ]'))
            or 'lc_component=$(installer_failure_component "${2:-}") || lc_component=unknown;'
            not in canonical):
        errors.append('failure recording must keep prose out of the structured component and retain a bounded tag/phase fallback')
    counts['lifecycle_structured_component_contracts'] = 1
    bodies = []
    for declaration, terminator in (('installer_failure_frontend() (\n', '\n);'),
                                    ('installer_terminal_hold() {\n', '\n};'),
                                    ('installer_failure_frontend_prepare() {\n', '\n};')):
        prefix, found, body = canonical.partition(declaration)
        body, closed, suffix = body.partition(terminator)
        if not found or not closed:
            errors.append('fatal frontend function missing or malformed: ' + declaration.strip())
            return
        bodies.append(body)
    frontend, hold, prepare = bodies
    required = ('${DEBIAN_HAS_FRONTEND:-}', '${DEBCONF_REDIR:-}',
                '${INSTALLER_DEBCONF_STDIN_SAVED:-}', '${LC_CHILD_PID:-}',
                'exec 0<&8;', 'mkdir "$lf_dir"', 'umask 077;',
                'installer_run_bounded 15 installer_failure_frontend_prepare',
                'if db_go >/dev/null 2>&1; then', '16384', '${#lf_value}')
    if any(value not in frontend for value in required):
        errors.append('fatal frontend lacks an inherited-channel, bounded-input or one-shot guard')
    if ('installer_failure_frontend ||' not in hold or 'kill -STOP' not in hold
            or hold.index('installer_failure_frontend ||') > hold.index('kill -STOP')):
        errors.append('fatal frontend must be presented before main-menu is stopped')
    if any(value in frontend for value in ('db_stop', 'debconf-communicate', 'lf_detail=',
                                           'installer_lifecycle_complete')):
        errors.append('fatal frontend must preserve failure state and exclusive frontend ownership')
    for request in ('db_x_loadtemplatefile', 'db_progress STOP', 'db_clear',
                    'db_capb', 'db_settitle', 'db_fset "$lf_question" seen false',
                    'db_input critical "$lf_question"'):
        if request not in prepare:
            errors.append('fatal frontend setup is missing: ' + request)
    template_lines = [line for line in frontend.splitlines()
                      if "'Template: unattended-installer/fatal-error'" in line]
    if len(template_lines) != 1 or template_lines[0].endswith('\\'):
        errors.append('fatal template must survive flattened bootstrap serialization')
    else:
        words = shlex.split(template_lines[0])
        for field in ('Template: unattended-installer/fatal-error', 'Type: error',
                      'Description: Unattended installation failed', ' Phase: ${PHASE}',
                      ' Component: ${COMPONENT}', ' Operation: ${OPERATION}',
                      ' Source: ${SOURCE}:${LINE}', ' Status: ${STATUS}'):
            if field not in words:
                errors.append('fatal error template field missing: ' + field)
    counts['lifecycle_frontend_contracts'] = 1


def check_preseed_commands(paths: list[Path], errors: list[str],
                           counts: dict[str, int]) -> None:
    for suite in ('forky', 'trixie'):
        path = ROOT / 'd-i' / suite / 'preseed.cfg'
        if path in paths:
            _check_preseed_commands(path, errors, counts)


def _check_preseed_commands(path: Path, errors: list[str],
                            counts: dict[str, int]) -> None:
    """Parse both shell layers of changed generated preseed data, never execute."""
    keys = {'preseed/include_command', 'preseed/early_command',
            'partman/early_command', 'preseed/late_command'}
    commands: dict[str, tuple[int, str]] = {}
    pending = ''
    first_number = 0
    for number, raw in enumerate(_read_text(path).splitlines(), 1):
        if not pending:
            first_number = number
            pending = raw
        else:
            pending += ' ' + raw.lstrip()
        if re.search(r'[ \t]\\$', pending):
            pending = re.sub(r'[ \t]\\$', '', pending)
            continue
        fields = pending.split(None, 3)
        pending = ''
        if len(fields) < 2 or fields[1] not in keys:
            continue
        if len(fields) != 4 or fields[0] != 'd-i' or fields[2] != 'string':
            errors.append(f'{path.relative_to(ROOT)}:{first_number}: malformed preseed command')
            continue
        if fields[1] in commands:
            errors.append(f'{path.relative_to(ROOT)}:{first_number}: duplicate {fields[1]}')
        commands[fields[1]] = (first_number, fields[3])
    if pending:
        errors.append(f'{path.relative_to(ROOT)}:{first_number}: unterminated continuation')
    dash = shutil.which('dash')
    busybox = shutil.which('busybox')
    if not dash or not busybox:
        errors.append('preseed syntax requires dash and busybox; no silent skips')
    interpreters = ([('dash', [dash])] if dash else []) + ([('busybox', [busybox, 'sh'])] if busybox else [])
    checks = 0
    for key, (number, value) in commands.items():
        try:
            words = shlex.split(value)
        except ValueError as error:
            errors.append(f'{path.relative_to(ROOT)}:{number}: {key}: {error}')
            continue
        layers = [('outer', value)]
        if len(words) >= 3 and Path(words[0]).name in {'sh', 'dash', 'ash', 'bash'} and words[1] == '-c':
            layers.append(('body', words[2]))
        for layer, source in layers:
            for name, interpreter in interpreters:
                result = _run([*interpreter, '-n'], input_text=source)
                checks += 1
                if result.returncode:
                    _report_command(errors, f'{path.relative_to(ROOT)}:{number}: {key} {layer} [{name}]', result)
    counts['preseed_commands'] = counts.get('preseed_commands', 0) + len(commands)
    counts['preseed_shell_parses'] = counts.get('preseed_shell_parses', 0) + checks


def _schema_keys() -> set[str]:
    keys = set()
    for number, line in enumerate(SCHEMA.read_text(encoding='utf-8').splitlines(), 1):
        if not line or line.startswith('#'):
            continue
        fields = line.split('\t')
        if len(fields) != 3:
            raise ValueError(f'{SCHEMA}:{number}: malformed schema row')
        keys.add(fields[1])
    return keys


def _scan_markers(name: str, data: bytes, errors: list[str],
                  schema_keys: set[str] | None, counts: dict[str, int]) -> set[str] | None:
    if THEME_PREFIX not in data:
        return schema_keys
    counts['marker_files'] = counts.get('marker_files', 0) + 1
    for line_number, line in enumerate(data.splitlines(), 1):
        offset = 0
        while True:
            start = line.find(THEME_PREFIX, offset)
            if start < 0:
                break
            match = THEME_TOKEN.match(line, start)
            if not match:
                errors.append(f'{name}:{line_number}: malformed/partial __THEME_ marker')
            else:
                counts['theme_markers'] = counts.get('theme_markers', 0) + 1
            offset = start + len(THEME_PREFIX)
    return schema_keys


def check_markers(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    schema_keys: set[str] | None = None
    # The installer theme renderer processes the staged target tree. Installer
    # source code has its own marker grammar and may construct marker strings
    # dynamically, so it is not mistaken for a staged asset here.
    for path in (path for path in paths if path.is_relative_to(TARGET_ROOT)):
        schema_keys = _scan_markers(str(path.relative_to(ROOT)), path.read_bytes(), errors,
                                    schema_keys, counts)
    counts.setdefault('marker_files', 0)
    counts.setdefault('theme_markers', 0)


def check_appearance_registry(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Validate the raw registry contract without importing installed code."""
    theme_inputs = {
        SCHEMA,
        *(DEBIAN_ROOT / 'hosts/themes' / (group + '.env') for group in ('base', 'apps', 'office')),
    }
    appearance_source_changed = any(
        path in {APPEARANCE_REGISTRY, APPEARANCE_FIELDS, APPEARANCE_NATIVE,
                 THEME_FETCH_CORE, THEME_RENDER_SUPPORT, THEME_RENDER_AWK,
                 THEME_VALIDATE_AWK, APPEARANCE_STAGE, DESKTOP_INSTALLER}
        or path in theme_inputs
        or (path.is_relative_to(TARGET_ROOT)
            and path.relative_to(TARGET_ROOT).parts[:2] in {('etc', 'greetd'), ('etc', 'skel-desktop')})
        for path in paths
    )
    if not appearance_source_changed:
        counts['appearance_registry_fields'] = 0
        counts['appearance_registry_mappings'] = 0
        counts['appearance_source_checks'] = 0
        counts['appearance_capture_line_checks'] = 0
        counts['appearance_native_token_checks'] = 0
        return
    field_count = 0
    mapping_count = 0
    multitoken_count = 0
    source_checks = 0
    capture_line_checks = 0
    native_token_checks = 0
    source_cache: dict[Path, list[str]] = {}
    try:
        value = json.loads(_read_text(APPEARANCE_REGISTRY))
        if (not isinstance(value, dict) or value.get('schema') != 3
                or value.get('captured') is not False
                or not isinstance(value.get('components'), list)
                or not isinstance(value.get('fields'), list)
                or not value['fields'] or len(value['fields']) > 1024):
            raise ValueError('registry must be schema 3 with captured=false and bounded fields')
        components = value['components']
        component_ids: list[str] = []
        for component in components:
            if (not isinstance(component, dict)
                    or component.get('id') not in APPEARANCE_COMPONENTS
                    or not isinstance(component.get('label'), str)
                    or not component['label']
                    or type(component.get('field_count')) is not int
                    or component['field_count'] < 1):
                raise ValueError('invalid component descriptor')
            component_ids.append(component['id'])
        if len(component_ids) != len(set(component_ids)):
            raise ValueError('duplicate component descriptor')
        seen: set[str] = set()
        theme_values: dict[str, str] = {}
        theme_types: dict[str, str] = {}
        for schema_line_number, schema_line in enumerate(_read_text(SCHEMA).splitlines(), 1):
            if not schema_line or schema_line.startswith('#'):
                continue
            schema_parts = schema_line.split('\t')
            if len(schema_parts) != 3:
                raise ValueError(f'{SCHEMA}:{schema_line_number}: malformed schema row')
            theme_types[schema_parts[1]] = schema_parts[2]
        for group in ('base', 'apps', 'office'):
            env_path = DEBIAN_ROOT / 'hosts/themes' / (group + '.env')
            for env_line_number, env_line in enumerate(_read_text(env_path).splitlines(), 1):
                if not env_line or env_line.startswith('#'):
                    continue
                match = re.fullmatch(r'([A-Z][A-Z0-9_]*)="([^"\r\n]*)"', env_line)
                if match:
                    theme_values[match[1]] = match[2]
        for field_number, field in enumerate(value['fields'], 1):
            if not isinstance(field, dict):
                raise ValueError(f'field {field_number} is not an object')
            key = field.get('key')
            if (not isinstance(key, str) or re.fullmatch(r'[A-Z][A-Z0-9_]{2,127}', key) is None
                    or key in seen or field.get('component') not in APPEARANCE_COMPONENTS
                    or field.get('component') not in component_ids
                    or field.get('type') not in APPEARANCE_TYPES
                    or not isinstance(field.get('default'), str)
                    or not isinstance(field.get('label'), str)
                    or not isinstance(field.get('category'), str)
                    or not isinstance(field.get('mappings'), list)
                    or not field['mappings']):
                raise ValueError(f'invalid field descriptor at index {field_number}')
            seen.add(key)
            field_count += 1
            for mapping_number, mapping in enumerate(field['mappings'], 1):
                if not isinstance(mapping, dict):
                    raise ValueError(f'{key} mapping {mapping_number} is not an object')
                path = mapping.get('path')
                source_name = mapping.get('source')
                template = mapping.get('template')
                tokens = mapping.get('tokens')
                target_index = mapping.get('target_index')
                rendered_path = (_render_installer_path_placeholders(path)
                                 if isinstance(path, str) else path)
                if (not isinstance(path, str) or rendered_path not in APPEARANCE_PATHS
                        or type(mapping.get('line')) is not int
                        or not 1 <= mapping['line'] <= 100000
                        or not isinstance(template, str) or len(template) > 32768
                        or not isinstance(source_name, str)
                        or not isinstance(tokens, list) or not tokens or len(tokens) > 32
                        or not all(isinstance(token, str) and REGISTRY_TOKEN.fullmatch(token)
                                   for token in tokens)
                        or tokens != REGISTRY_TOKEN.findall(template)
                        or type(target_index) is not int
                        or not 0 <= target_index < len(tokens)
                        or tokens[target_index] != '__THEME_' + key + '__'
                        or mapping.get('grammar') not in APPEARANCE_GRAMMARS):
                    raise ValueError(f'invalid mapping for {key}')
                source = ROOT / source_name
                if (Path(source_name).is_absolute() or
                        source_name != source.relative_to(ROOT).as_posix() or
                        not source.is_relative_to(TARGET_ROOT) or
                        not source.is_file() or source.is_symlink()):
                    raise ValueError(f'{key} mapping {mapping_number} has an unsafe source path')
                source_lines = source_cache.get(source)
                if source_lines is None:
                    source_lines = _read_text(source).splitlines()
                    source_cache[source] = source_lines
                if mapping['line'] > len(source_lines):
                    raise ValueError(f'{key} mapping {mapping_number} source line is unavailable')
                source_line = source_lines[mapping['line'] - 1]
                if source_line != template:
                    raise ValueError(f'{key} mapping {mapping_number} template differs from source line')
                # Reproduce the data substitution boundary for this one source
                # line without importing or executing installer renderers. Use
                # actual checked-in theme literals and distinct safe sentinels
                # for installer-owned placeholders; then ensure the target
                # field remains uniquely extractable from the rendered line.
                rendered_line = source_line
                marker_matches = list(REGISTRY_TOKEN.finditer(rendered_line))
                for marker_index, marker in reversed(list(enumerate(marker_matches))):
                    token = marker.group(0)
                    if token.startswith('__THEME_'):
                        theme_key = token[len('__THEME_'):-2]
                        if theme_key not in theme_values:
                            raise ValueError(f'{key} mapping {mapping_number} references missing theme input {theme_key}')
                        replacement = theme_values[theme_key]
                    else:
                        replacement = f'INSTALLER_STATIC_VALUE_{marker_index}'
                    rendered_line = (rendered_line[:marker.start()] + replacement
                                     + rendered_line[marker.end():])
                pieces: list[str] = []
                cursor = 0
                for token in tokens:
                    start = template.find(token, cursor)
                    pieces.append(template[cursor:start])
                    cursor = start + len(token)
                pieces.append(template[cursor:])
                candidates: list[list[str]] = []

                def collect(index: int, position: int, extracted: list[str]) -> None:
                    if len(candidates) > 4096:
                        return
                    literal = pieces[index]
                    if not rendered_line.startswith(literal, position):
                        return
                    start = position + len(literal)
                    if index == len(tokens):
                        if start == len(rendered_line):
                            candidates.append(extracted)
                        return
                    delimiter = pieces[index + 1]
                    if delimiter:
                        ends = []
                        probe = start
                        while True:
                            probe = rendered_line.find(delimiter, probe)
                            if probe < 0:
                                break
                            ends.append(probe)
                            probe += 1
                    else:
                        ends = range(start, len(rendered_line) + 1)
                    for end in ends:
                        token_value = rendered_line[start:end]
                        theme_token = tokens[index]
                        if theme_token.startswith('__THEME_'):
                            theme_key = theme_token[len('__THEME_'):-2]
                            expected_value = theme_values.get(theme_key)
                            if expected_value is not None and token_value != expected_value:
                                continue
                        collect(index + 1, end, extracted + [token_value])

                collect(0, 0, [])
                if len(candidates) != 1:
                    raise ValueError(
                        f'{key} mapping {mapping_number} does not have one rendered-line tokenization '
                        f'(found {len(candidates)})'
                    )
                capture_line_checks += 1
                relative = source.relative_to(TARGET_ROOT)
                if relative.parts[:3] == ('etc', 'skel-desktop', '.config'):
                    expected_path = relative.relative_to('etc/skel-desktop/.config')
                    if expected_path.name.endswith('.tmpl'):
                        expected_path = expected_path.with_suffix('')
                    expected_path = expected_path.as_posix()
                elif relative.parts[:2] == ('etc', 'greetd'):
                    expected_path = relative
                    if expected_path.name.endswith('.tmpl'):
                        expected_path = expected_path.with_suffix('')
                    expected_path = '/' + expected_path.as_posix()
                else:
                    raise ValueError(f'{key} mapping {mapping_number} source is not a native template')
                if rendered_path != expected_path:
                    raise ValueError(f'{key} mapping {mapping_number} target path differs from source')
                source_checks += 1
                mapping_count += 1
                multitoken_count += len(tokens) > 1
        # Discover native color tokens from every checked-in appearance source
        # corresponding to an allowlisted installed path. This catches a new
        # color token that was added to a native file but omitted from the
        # registry entirely, including a whole source file with no mappings.
        native_sources: set[Path] = set()
        for target_path in APPEARANCE_PATHS:
            if target_path.startswith('/'):
                relative = Path(target_path[1:])
                source_base = target_source(relative.as_posix())
            else:
                source_base = TARGET_ROOT / 'etc/skel-desktop/.config' / target_path
            for candidate in (source_base.with_name(source_base.name + '.tmpl'), source_base):
                if candidate.is_file() and not candidate.is_symlink():
                    native_sources.add(candidate)
                    break
        for source in sorted(native_sources):
            for token_match in REGISTRY_TOKEN.finditer(_read_text(source)):
                token = token_match.group(0)
                if not token.startswith('__THEME_'):
                    continue
                theme_key = token[len('__THEME_'):-2]
                if theme_types.get(theme_key) not in APPEARANCE_GRAMMARS:
                    continue
                native_token_checks += 1
                if theme_key not in seen:
                    raise ValueError(
                        f'{theme_key} is a native color token without an appearance mapping '
                        f'in {source.relative_to(ROOT)}'
                    )
        for component in components:
            expected = sum(1 for field in value['fields'] if field['component'] == component['id'])
            if component['field_count'] != expected:
                raise ValueError(f"field count mismatch for {component['id']}")
    except (OSError, UnicodeError, TypeError, ValueError, json.JSONDecodeError) as error:
        errors.append(f'{APPEARANCE_REGISTRY.relative_to(ROOT)}: registry contract: {error}')
    counts['appearance_registry_fields'] = field_count
    counts['appearance_registry_mappings'] = mapping_count
    counts['appearance_multitoken_mappings'] = multitoken_count
    counts['appearance_source_checks'] = source_checks
    counts['appearance_capture_line_checks'] = capture_line_checks
    counts['appearance_native_token_checks'] = native_token_checks


def check_appearance_wiring(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Inspect desktop scope, delegates, staging and exact atomic-write authority."""
    package = APPEARANCE_FIELDS.parent
    policy = target_source('etc/apparmor.d/labwc-appearance')
    affected = {policy, APPEARANCE_STAGE, APPEARANCE_REGISTRY,
                DEBIAN_ROOT / 'repo.env', DEBIAN_ROOT / 'hosts/installer/runtime.env'}
    if not affected.intersection(paths) and not any(path.parent == package for path in paths):
        return
    try:
        native = ast.parse(_read_text(APPEARANCE_NATIVE))
        files = next(ast.literal_eval(node.value) for node in native.body
                     if isinstance(node, ast.Assign)
                     and any(isinstance(target, ast.Name) and target.id == 'FILES' for target in node.targets))
        if set(files) != {'fuzzel', 'waybar', 'taskview', 'waycal', 'dock', 'terminal',
                          'swaylock', 'mako', 'theme'}:
            raise ValueError('appearance scope must contain desktop components only')
        if {component['id'] for component in json.loads(_read_text(APPEARANCE_REGISTRY))['components']} != APPEARANCE_COMPONENTS:
            raise ValueError('appearance registry no longer matches the desktop component set')
        module_names = {path.stem for path in package.glob('*.py') if path.is_file() and not path.is_symlink()}
        staging = _read_text(APPEARANCE_STAGE)
        prepared_inputs = 0
        for module in sorted(module_names):
            if '/labwc_appearance/' + module + '.py' not in staging:
                raise ValueError('appearance module is not staged: ' + module)
            for node in ast.walk(ast.parse(_read_text(package / (module + '.py')))):
                if isinstance(node, ast.ImportFrom) and node.level and node.module:
                    if node.module.split('.')[0] not in module_names:
                        raise ValueError('appearance module has a missing relative delegate: ' + module)
                if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                        and isinstance(node.func.value, ast.Name)
                        and node.func.value.id == 'transaction' and node.func.attr == 'plan'):
                    if not any(keyword.arg == 'expected'
                               and not (isinstance(keyword.value, ast.Constant) and keyword.value.value is None)
                               for keyword in node.keywords):
                        raise ValueError('appearance candidate is not bound to its preparation bytes: ' + module)
                    prepared_inputs += 1
        if not prepared_inputs:
            raise ValueError('appearance has no checked preparation boundary')
        if re.search(r'^\s*def capture_registry\(', _read_text(APPEARANCE_FIELDS), re.M):
            raise ValueError('installation-only field capture remains in the runtime editor')
        for marker in ('installer_stage_profile_file scripts/desktop/appearance-setup.py',
                       'trap setup_cleanup 0', 'desktop_run_appearance_setup extract',
                       'desktop_run_appearance_setup themes', 'desktop_run_appearance_setup defaults'):
            if marker not in staging:
                raise ValueError('private appearance setup staging/cleanup is incomplete')
        # The published source is parsed as data, never imported. The narrow
        # owner rules must cover each native file and its atomic sibling.
        source_policy = _read_text(policy).split('profile labwc-appearance-auth ', 1)[0]
        rules = []

        def expand_braces(pattern: str) -> list[str]:
            match = re.search(r'\{([^{}]*)\}', pattern)
            if match is None:
                return [pattern]
            expanded = [leaf for choice in match[1].split(',')
                        for leaf in expand_braces(pattern[:match.start()] + choice + pattern[match.end():])]
            if len(expanded) > 2048:
                raise ValueError('appearance source rule expansion exceeds its budget')
            return expanded

        for line in source_policy.splitlines():
            match = re.fullmatch(r'\s*owner (@\{HOME\}/\.config/\S+)\s+([a-z]+),\s*', line)
            if match and {'r', 'w'} <= set(match[2]):
                rules += expand_braces(match[1].replace('@{HOME}', 'HOME'))

        def covered(path: str) -> bool:
            return any(fnmatch.fnmatchcase('HOME/.config/' + path, pattern) for pattern in rules)

        native_paths = {path for group in files.values() for path in group}
        for path in sorted(native_paths):
            if not covered(path):
                raise ValueError('appearance native file lacks exact write authority: ' + path)
            parent = Path(path).parent.as_posix()
            if not covered(parent + '/') or not covered(parent + '/.managed-static-sibling'):
                raise ValueError('appearance atomic publication lacks directory/sibling authority: ' + parent)
        for marker in ('deny network inet,', 'deny network inet6,',
                       '/bin/pkexec rPx -> labwc-appearance-auth,'):
            if marker not in source_policy:
                raise ValueError('appearance network or authenticated greeter boundary changed')
        entry = _read_text(target_source('usr/local/share/applications/org.labwc.DesktopAppearance.desktop'))
        if '/labwc-desktop-appearance --gtk' not in entry:
            raise ValueError('desktop appearance entry does not open the existing GTK editor')
        # Inspect the shared recovery protocol as syntax. This proves caller
        # shapes and lock placement, not service or failure-injection behavior.
        fields_tree = ast.parse(_read_text(APPEARANCE_FIELDS))
        functions = {node.name: node for node in fields_tree.body if isinstance(node, ast.FunctionDef)}
        coordinator = functions['_apply_updates']
        locks = [node for node in ast.walk(coordinator) if isinstance(node, ast.With)
                 and any(isinstance(item.context_expr, ast.Call)
                         and isinstance(item.context_expr.func, ast.Attribute)
                         and item.context_expr.func.attr == 'lock'
                         and item.context_expr.args
                         and isinstance(item.context_expr.args[0], ast.Name)
                         and item.context_expr.args[0].id == 'USER_LOCK' for item in node.items)]
        if len(locks) != 1:
            raise ValueError('appearance fields do not have one shared account lock owner')
        locked = {id(node) for node in ast.walk(locks[0])}
        dock_calls = [node for node in ast.walk(coordinator) if isinstance(node, ast.Call)
                      and isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name)
                      and node.func.value.id == 'service' and node.func.attr in {'dock_stop', 'dock_start'}]
        if len(dock_calls) != 2 or any(id(node) not in locked for node in dock_calls):
            raise ValueError('appearance dock lifecycle escapes the field transaction lock')
        fields_apply = [node for node in ast.walk(coordinator) if isinstance(node, ast.Call)
                        and isinstance(node.func, ast.Name) and node.func.id == 'apply_greeter']
        if len(fields_apply) != 1 or len(fields_apply[0].args) != 2 or id(fields_apply[0]) not in locked:
            raise ValueError('greeter field preparation is not bound to the locked account token')
        for name, tree in (('_recover_field_updates', fields_tree),
                           ('recover', ast.parse(_read_text(package / 'engine.py')))):
            recovery = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == name)
            checks = [node.lineno for node in ast.walk(recovery) if isinstance(node, ast.Call)
                      and isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name)
                      and node.func.value.id == 'transaction' and node.func.attr == 'check_committed']
            root_calls = [node.lineno for node in ast.walk(recovery) if isinstance(node, ast.Call)
                          and isinstance(node.func, ast.Name) and node.func.id == 'privileged']
            if len(checks) != 1 or not root_calls or min(checks) >= min(root_calls):
                raise ValueError('committed appearance bytes are not checked before root finalization')
        root_tree = ast.parse(_read_text(package / 'greeter.py'))
        root_fields = [node for node in ast.walk(root_tree) if isinstance(node, ast.Call)
                       and isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name)
                       and node.func.value.id == 'fields' and node.func.attr == 'apply_root_greeter']
        if len(root_fields) != 1 or len(root_fields[0].args) != 3:
            raise ValueError('authenticated greeter field dispatch lost its token or caller identity')
        for module in ('fields', 'greeter', 'wallpaper'):
            tree = ast.parse(_read_text(package / (module + '.py')))
            journal_calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)
                             and isinstance(node.func, ast.Attribute) and node.args
                             and isinstance(node.args[0], ast.Constant)
                             and node.args[0].value == 'fields-pending.json']
            if not journal_calls or any(node.func.attr != 'read' for node in journal_calls):
                raise ValueError('unresolved greeter evidence must only block edits, never become a competing commit journal')
            if module == 'wallpaper':
                writer = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'publish')
                recoveries = [node.lineno for node in ast.walk(writer) if isinstance(node, ast.Call)
                              and isinstance(node.func, ast.Attribute) and node.func.attr == 'rollback']
                if not recoveries or min(node.lineno for node in journal_calls) >= min(recoveries):
                    raise ValueError('wallpaper recovery mutates files before checking other greeter evidence')
        counts['appearance_runtime_modules'] = len(module_names)
        counts['appearance_atomic_native_files'] = len(native_paths)
        counts['appearance_desktop_components'] = len(APPEARANCE_COMPONENTS)
        counts['appearance_recovery_protocols'] = 2
        counts['appearance_prepared_input_checks'] = prepared_inputs
    except (OSError, UnicodeError, SyntaxError, StopIteration, TypeError, ValueError, KeyError) as error:
        errors.append(f'{APPEARANCE_STAGE.relative_to(ROOT)}: appearance wiring: {error}')


def check_appearance_render_preservation(paths: list[Path], errors: list[str],
                                         counts: dict[str, int]) -> None:
    """Render defaults as data, preserving all runtime mapping metadata."""
    theme_paths = [DEBIAN_ROOT / 'hosts/themes' / (group + '.env')
                   for group in ('base', 'apps', 'office')]
    inputs = {THEME_FETCH_CORE, THEME_RENDER_SUPPORT, THEME_RENDER_AWK,
              THEME_VALIDATE_AWK, APPEARANCE_REGISTRY, APPEARANCE_STAGE,
              DESKTOP_INSTALLER, SCHEMA, *theme_paths}
    counts['appearance_rendered_defaults'] = 0
    if not inputs.intersection(paths):
        counts['appearance_render_contract'] = 0
        return
    try:
        selectors = _repository_selector_values()
        text = _resolve_repository_source_contract(_read_text(THEME_FETCH_CORE))
        if '*/usr/local/share/labwc-appearance/fields.json) return 0 ;;' in text:
            errors.append(
                f'{THEME_FETCH_CORE.relative_to(ROOT)}: fields.json must not bypass theme rendering'
            )
        if 'fields.json.tmpl' not in text:
            errors.append(
                f'{THEME_FETCH_CORE.relative_to(ROOT)}: missing fields.json.tmpl render contract'
            )
        if ('*/usr/local/lib/python3/dist-packages/labwc_appearance/*.py) return 0 ;;' not in text
                and selectors['DIR_TARGET_PY'] + '/labwc_appearance/' not in text):
            errors.append(
                f'{THEME_FETCH_CORE.relative_to(ROOT)}: missing appearance Python code theme-render exemption'
            )
        support = _resolve_repository_source_contract(_read_text(THEME_RENDER_SUPPORT))
        if ((re.search(r'\*/usr/local/share/labwc-appearance/fields\.json\.tmpl\)\s*'
                       r'theme_render_scope=appearance-defaults\s*;;', support) is None
                 and 'hooks/target/usr/local/share/desktop/labwc-appearance/fields.json.tmpl' not in support)
                or 'installer_target_perl_render' not in support
                or 'appearance-defaults) theme_render_kind=appearance' not in support):
            raise ValueError('registry must select and pass defaults-only rendering before publication')
        stage = _render_installer_path_placeholders(
            _resolve_repository_source_contract(_read_text(APPEARANCE_STAGE)))
        registry_source = re.escape('hooks/target/usr/local/share/desktop/labwc-appearance/fields.json.tmpl')
        if re.search(r'publish_target_asset "\$\(installer_repo_file_value ' + registry_source +
                     r'\)"\s*\\\s*"\$\{DIR_USR_LOCAL_SHARE_LABWC_APPEARANCE\}/fields\.json" '
                     r'0644 appearance-registry', stage) is None:
            raise ValueError('registry must publish as fields.json with mode 0644 and its literal-metadata contract')
        installer = _read_text(DESKTOP_INSTALLER)
        calls = re.findall(r'^  (desktop_[a-z_]+)\s*$', installer, re.MULTILINE)
        order = [calls.index(name) for name in (
            'desktop_stage_target_assets', 'desktop_install_appearance_themes',
            'desktop_install_user_config', 'desktop_capture_appearance_defaults',
            'desktop_enable_target_services',
        )]
        if order != sorted(order):
            raise ValueError('appearance registry must stage before capture/activation')
        target_assets = _read_text(DEBIAN_ROOT / 'scripts/desktop/components/target-assets.sh')
        if re.search(r'^  desktop_stage_appearance\s*$', target_assets, re.MULTILINE) is None:
            raise ValueError('target asset staging must include the appearance registry')

        # Inspect literal theme data and materialize only default fields here.
        # Never execute the repository AWK validator/renderer on the host.
        # Native consumer grammar remains owned by installer theme validation.
        schema_groups = {}
        for line in _read_text(SCHEMA).splitlines():
            if not line or line.startswith('#'):
                continue
            group, key, _grammar = line.split('\t')
            if key in schema_groups:
                raise ValueError('duplicate theme schema field ' + key)
            schema_groups[key] = group
        theme_values = {}
        for path in theme_paths:
            for line in _read_text(path).splitlines():
                if not line.strip() or line.lstrip().startswith('#'):
                    continue
                match = re.fullmatch(r'([A-Z][A-Z0-9_]*)="([^"\r\n]*)"', line)
                if (match is None or match[1] in theme_values
                        or schema_groups.get(match[1]) != path.stem
                        or len(match[2]) > 4096
                        or re.search(r"[\x00-\x1f\x7f'\\$`]", match[2]) or '__' in match[2]):
                    raise ValueError('invalid literal theme assignment in ' + path.name)
                theme_values[match[1]] = match[2]
        if set(theme_values) != set(schema_groups):
            raise ValueError('theme literal/schema coverage differs')
        rendered = re.sub(
            r'("default": )"__THEME_([A-Z0-9_]+)__"',
            lambda match: match[1] + json.dumps(theme_values[match[2]], ensure_ascii=False),
            _read_text(APPEARANCE_REGISTRY))
        expected = json.loads(_read_text(APPEARANCE_REGISTRY))
        for field in expected['fields']:
            key = field['key']
            if field.get('default') != '__THEME_' + key + '__':
                raise ValueError('default template does not match appearance field ' + key)
            field['default'] = theme_values[key]
        actual = json.loads(rendered)
        if actual != expected:
            raise ValueError('rendering must replace every default and preserve all mapping metadata')
        counts['appearance_rendered_defaults'] = len(actual['fields'])
    except (OSError, UnicodeError, KeyError, TypeError, ValueError) as error:
        errors.append(f'{THEME_FETCH_CORE.relative_to(ROOT)}: render contract: {error}')
    counts['appearance_render_contract'] = 1


def check_waybar_render_contract(paths: list[Path], errors: list[str],
                                 counts: dict[str, int]) -> None:
    """Check that Waybar config assets always use their placeholder map."""
    renderer = DEBIAN_ROOT / 'scripts/desktop/components/core-renderers.sh.tmpl'
    waybar_root = TARGET_ROOT / 'etc/skel-desktop/.config/waybar'
    changed_waybar = [path for path in paths if path.is_relative_to(waybar_root)
                      and path.name.endswith('.tmpl')]
    if renderer not in paths and not changed_waybar:
        counts['waybar_render_contract'] = 0
        return
    try:
        renderer_text = _read_text(renderer)
        if 'run_in_target "validate Waybar geometry with target Python"' not in renderer_text:
            errors.append(f'{renderer.relative_to(ROOT)}: geometry validator must run through target run_in_target')
        if re.search(r'/usr/bin/python3\s+-I\s+-B\s+"\$TMP_ENV_DIR/waybar_geometry\.py"', renderer_text):
            errors.append(f'{renderer.relative_to(ROOT)}: geometry validator is being executed in d-i')
        if re.search(r'(?m)^\s*desktop_render_waybar_asset\s+config\s*$', renderer_text):
            errors.append(f'{renderer.relative_to(ROOT)}: config.tmpl is rendered once without its placeholder map')
        if 'desktop_render_waybar_config_asset "$wb_config_asset"' not in renderer_text:
            errors.append(f'{renderer.relative_to(ROOT)}: Waybar config asset loop is missing')
        module_root = waybar_root / 'modules'
        module_assets = {path.name.removesuffix('.tmpl') for path in changed_waybar
                         if path.parent == module_root}
        for asset in sorted(module_assets):
            if asset not in renderer_text:
                errors.append(f'{renderer.relative_to(ROOT)}: module template {asset} is not in the config renderer loop')
        counts['waybar_module_templates'] = len(module_assets)
        style_root = waybar_root / 'style'
        style_assets = {path.name.removesuffix('.tmpl') for path in changed_waybar
                        if path.parent == style_root}
        for asset in sorted(style_assets):
            loop_name = asset
            if loop_name not in renderer_text:
                errors.append(f'{renderer.relative_to(ROOT)}: style template {asset} is not in the style renderer loop')
        counts['waybar_style_templates'] = len(style_assets)
        map_match = re.search(
            r'desktop_render_waybar_config_asset\(\) \{(.*?)\n  \}\n  desktop_render_waybar_config_asset config',
            renderer_text, re.DOTALL,
        )
        if map_match is None:
            errors.append(f'{renderer.relative_to(ROOT)}: config placeholder map body is missing')
            explicit = set()
        else:
            explicit = set(re.findall(r'^\s+(LABWC_[A-Z0-9_]+)\s+"', map_match.group(1), re.MULTILINE))
        geometry = DEBIAN_ROOT / 'scripts/desktop/waybar-geometry.tsv'
        geometry_keys = set()
        for line in _read_text(geometry).splitlines():
            if not line or line.startswith('#'):
                continue
            fields = line.split('\t')
            if len(fields) == 4:
                geometry_keys.add(fields[0])
        accepted = set(explicit)
        for key in geometry_keys:
            accepted.update({f'LABWC_WAYBAR_INTERNAL_{key}', f'LABWC_WAYBAR_EXTERNAL_{key}'})
            if key.startswith(('MENU_', 'POPUP_', 'TOOLTIP_')):
                accepted.add(f'LABWC_WAYBAR_SHARED_{key}')
        tokens = set()
        for path in changed_waybar:
            tokens.update(re.findall(r'__INSTALLER_([A-Z0-9_]+)__', _read_text(path)))
        accepted.update(token for token in tokens
                       if token.startswith(('PATH_', 'APPARMOR_PROFILE_')))
        unknown = sorted(token for token in tokens if token not in accepted)
        for token in unknown:
            errors.append(f'{waybar_root.relative_to(ROOT)}: no Waybar renderer map entry for {token}')
        counts['waybar_installer_tokens'] = len(tokens)
    except (OSError, UnicodeError) as error:
        errors.append(f'{renderer.relative_to(ROOT)}: Waybar render contract: {error}')
    counts['waybar_render_contract'] = 1


def check_waybar_geometry_contract(paths: list[Path], errors: list[str],
                                   counts: dict[str, int]) -> None:
    """Validate profile geometry before the installer reaches target Python."""
    changed_profiles = [
        path for path in paths
        if path.is_relative_to(WAYBAR_PROFILE_ROOT) and path.suffix == '.env'
        and path.name != 'shared-de.env'
    ]
    geometry_inputs_changed = (
        WAYBAR_GEOMETRY_SCHEMA in paths
        or DEBIAN_ROOT / 'scripts/desktop/waybar_geometry.py' in paths
        or DEBIAN_ROOT / 'scripts/desktop/components/core-renderers.sh.tmpl' in paths
    )
    if not changed_profiles and not geometry_inputs_changed:
        counts['waybar_geometry_profiles'] = 0
        return
    profiles = changed_profiles or sorted(path for path in WAYBAR_PROFILE_ROOT.glob('*.env') if path.name != 'shared-de.env')
    try:
        specs: list[tuple[str, str, int, int]] = []
        for line_number, raw in enumerate(_read_text(WAYBAR_GEOMETRY_SCHEMA).splitlines(), 1):
            if not raw or raw.startswith('#'):
                continue
            fields = raw.split('\t')
            if len(fields) != 4:
                raise ValueError(f'{WAYBAR_GEOMETRY_SCHEMA}:{line_number}: malformed schema row')
            key, kind, minimum, maximum = fields
            if re.fullmatch(r'[A-Z][A-Z0-9_]*', key) is None or kind not in {'uint', 'px-tuple'}:
                raise ValueError(f'{WAYBAR_GEOMETRY_SCHEMA}:{line_number}: invalid geometry schema key')
            specs.append((key, kind, int(minimum), int(maximum)))
        expected = {
            f'LABWC_WAYBAR_{output_class}_{key}'
            for output_class in ('INTERNAL', 'EXTERNAL')
            for key, _kind, _minimum, _maximum in specs
        }
        assignment = re.compile(
            r'(?:export\s+)?(LABWC_WAYBAR_(?:INTERNAL|EXTERNAL)_[A-Z][A-Z0-9_]*)="([^"\r\n]*)"$'
        )
        shared = WAYBAR_PROFILE_ROOT / 'shared-de.env'
        if not shared.is_file():
            raise ValueError(f'{shared.relative_to(ROOT)}: mandatory shared profile is missing')
        for profile in profiles:
            values: dict[str, str] = {}
            for source in (shared, profile):
                source_values: dict[str, str] = {}
                for line_number, raw in enumerate(_read_text(source).splitlines(), 1):
                    if not raw.startswith((
                        'LABWC_WAYBAR_INTERNAL_', 'LABWC_WAYBAR_EXTERNAL_',
                        'export LABWC_WAYBAR_INTERNAL_', 'export LABWC_WAYBAR_EXTERNAL_',
                    )):
                        continue
                    match = assignment.fullmatch(raw)
                    if match is None:
                        raise ValueError(f'{source.relative_to(ROOT)}:{line_number}: malformed Waybar geometry assignment')
                    key, value = match.groups()
                    if key in source_values:
                        raise ValueError(f'{source.relative_to(ROOT)}:{line_number}: duplicate {key}')
                    source_values[key] = value
                values.update(source_values)
            if set(values) != expected:
                missing = sorted(expected - set(values))
                extra = sorted(set(values) - expected)
                raise ValueError(
                    f'{profile.relative_to(ROOT)}: geometry key set mismatch '
                    f'missing={missing[:3]} extra={extra[:3]}'
                )
            for output_class in ('INTERNAL', 'EXTERNAL'):
                for key, kind, minimum, maximum in specs:
                    name = f'LABWC_WAYBAR_{output_class}_{key}'
                    value = values[name]
                    if kind == 'uint':
                        if re.fullmatch(r'(?:0|[1-9][0-9]*)', value) is None:
                            raise ValueError(f'{profile.relative_to(ROOT)}: non-canonical {name}')
                        number = int(value)
                        if not minimum <= number <= maximum:
                            raise ValueError(f'{profile.relative_to(ROOT)}: out-of-range {name}')
                    else:
                        parts = value.split()
                        if len(parts) != minimum or any(
                            re.fullmatch(r'(?:0|[1-9][0-9]*)px', part) is None
                            or int(part[:-2]) > maximum for part in parts
                        ):
                            raise ValueError(f'{profile.relative_to(ROOT)}: invalid {name}')
            for key, _kind, _minimum, _maximum in specs:
                if key.startswith('MENU_BUTTON_'):
                    continue
                if key.startswith(('MENU_', 'POPUP_', 'TOOLTIP_')):
                    internal = values[f'LABWC_WAYBAR_INTERNAL_{key}']
                    external = values[f'LABWC_WAYBAR_EXTERNAL_{key}']
                    if internal != external:
                        raise ValueError(
                            f'{profile.relative_to(ROOT)}: native Waybar GTK popup geometry must match '
                            f'INTERNAL/EXTERNAL: {key}'
                        )
            if int(values['LABWC_WAYBAR_INTERNAL_HEIGHT']) >= int(values['LABWC_WAYBAR_EXTERNAL_HEIGHT']):
                raise ValueError(f'{profile.relative_to(ROOT)}: internal Waybar height must be smaller than external')
    except (OSError, UnicodeError, TypeError, ValueError) as error:
        errors.append(f'{WAYBAR_GEOMETRY_SCHEMA.relative_to(ROOT)}: geometry contract: {error}')
    counts['waybar_geometry_profiles'] = len(profiles)


def check_payload_archive(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    archive_paths = [path for path in paths if path.name == 'payload.tar.gz'
                     and any(path.is_relative_to(ROOT / 'd-i' / owner)
                             for owner in ('debian', 'forky', 'trixie'))]
    if not archive_paths:
        return
    for archive_path in archive_paths:
        _check_payload_archive(archive_path, paths, errors, counts)


def _check_payload_archive(archive_path: Path, paths: list[Path],
                           errors: list[str], counts: dict[str, int]) -> None:
    schema_keys: set[str] | None = None
    member_count = 0
    with tarfile.open(archive_path, 'r:*') as archive:
        for member in archive:
            member_count += 1
            if member_count > 100000:
                raise ValueError('payload archive member limit exceeded')
            if not member.isfile() or not member.name.startswith('hooks/target/'):
                continue
            if Path(member.name).suffix.lower() in BINARY_SUFFIXES:
                continue
            stream = archive.extractfile(member)
            if stream is None:
                continue
            data = stream.read(8 * 1024 * 1024 + 1)
            if len(data) > 8 * 1024 * 1024:
                continue
            schema_keys = _scan_markers(member.name, data, errors, schema_keys, counts)
    counts['payload_members'] = member_count
    _check_payload_class_queries(archive_path, errors, counts)


# These interfaces consume canonical class references. The application wrapper
# takes a quoted reference list before its label/worker arguments. Inspect these
# inputs as shell words only; never source an installer or import fixture code.
CLASS_QUERY_ARGUMENTS = {
    'installer_class_selected': (0, 1),
    'installer_class_selected_any': (0, None),
    'installer_selected_class_reference_is_selected': (0, 1),
    'installer_class_reference_matches_selected': (0, 1),
    'installer_class_reference_list_matches_selected': (0, 1),
    'installer_selected_class_allowed_reference_matches': (0, 1),
    'installer_class_token_parts': (0, 1),
    'installer_validate_class_reference': (1, 2),
    'installer_validate_class_reference_list': (1, 2),
    'runtime_class_selected': (0, 1),
    'software_run_selected_app': (0, 1),
}
CLASS_QUERY = re.compile(r'\b(' + '|'.join(CLASS_QUERY_ARGUMENTS) + r')\s+([^\n]+)')
CLASS_REFERENCE = re.compile(r'[a-z0-9_-]+(?:/[a-z0-9_-]+)+\Z')


def _literal_class_queries(source: str) -> list[tuple[int, str]]:
    """Return literal query arguments, with original physical source lines.

    Variable arguments remain a runtime/producer contract, not a claim of static
    validation. Literal arguments in list wrappers are checked individually.
    """
    # Keep physical line positions while joining shell continuations.
    joined = re.sub(r'\\\n', '  ', source)
    # Offsets give correct diagnostics even when a prior continuation was joined.
    offsets = [0]
    for line in source.splitlines(keepends=True):
        offsets.append(offsets[-1] + len(line))
    result = []
    for match in CLASS_QUERY.finditer(joined):
        line_start = joined.rfind('\n', 0, match.start()) + 1
        if joined[line_start:match.start()].lstrip().startswith('#'):
            continue
        lexer = shlex.shlex(match.group(2), posix=True, punctuation_chars=';&|<>()')
        lexer.whitespace_split = True
        words = []
        for word in lexer:
            if word[0] in ';&|<>()':
                if word[0] in '<>' and words and words[-1].isdigit():
                    words.pop()  # Shell I/O descriptor, not a class argument.
                break
            words.append(word)
        start, end = CLASS_QUERY_ARGUMENTS[match.group(1)]
        for word in words[start:end]:
            if any(marker in word for marker in ('$', '`')):
                continue
            for reference in word.split():
                result.append((bisect.bisect_right(offsets, match.start()), reference))
    return result


def _check_class_queries(label: str, source: str, registries: dict[str, set[str]],
                         errors: list[str], counts: dict[str, int]) -> None:
    for line, reference in _literal_class_queries(source):
        missing = [suite for suite, refs in registries.items() if reference not in refs]
        if CLASS_REFERENCE.fullmatch(reference) is None or missing:
            errors.append(f'{label}:{line}: unregistered literal class selector: '
                          f'{reference!r} (suites: {", ".join(missing)})')
        counts['literal_class_queries'] = counts.get('literal_class_queries', 0) + 1


def check_class_queries(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Check changed shell inputs against both authored physical class trees."""
    candidates = [path for path in paths
                  if (path.is_relative_to(DEBIAN_ROOT / 'scripts')
                      or path.is_relative_to(DEBIAN_ROOT / 'hooks/installer'))
                  and _shell_kind(path) is not None]
    if not candidates:
        return
    registries = {}
    for suite in ('forky', 'trixie'):
        refs = set()
        for kind in ('class-auto', 'class-select', 'class-profile'):
            base = ROOT / 'd-i' / suite / 'classes' / kind
            for path in base.rglob('*.cfg'):
                ref = path.relative_to(base).as_posix().removesuffix('.cfg')
                refs.add(('profile/' if kind == 'class-profile' else '') + ref)
        registries[suite] = refs
    for path in candidates:
        _check_class_queries(str(path.relative_to(ROOT)), _read_text(path), registries, errors, counts)


def _check_payload_class_queries(archive_path: Path, errors: list[str], counts: dict[str, int]) -> None:
    """Check every installer query inside a changed payload against its registry."""
    with tarfile.open(archive_path, 'r:*') as archive:
        selectors = _repository_selector_values()

        def read_member(member: tarfile.TarInfo) -> str:
            if not member.isfile() or member.size > 8 * 1024 * 1024:
                raise ValueError('invalid class contract member: ' + member.name)
            stream = archive.extractfile(member)
            if stream is None:
                raise ValueError('unreadable class contract member: ' + member.name)
            with stream:
                return stream.read(8 * 1024 * 1024 + 1).decode('utf-8')

        try:
            registry = archive.getmember('catalog/compiled/class-registry.tsv')
        except KeyError as error:
            raise ValueError('payload class registry is missing') from error
        rows = [line.split('\t') for line in read_member(registry).splitlines()]
        if (rows[:2] != [['manifest', 'version', '8'], ['manifest', 'class_token_formats', 'canonical']]
                or any(len(row) != 13 for row in rows if row[0] == 'class')):
            raise ValueError('invalid payload class registry schema')
        refs = {row[1] + '/' + row[2] for row in rows if row[0] == 'class'}
        if not refs or len(refs) != sum(row[0] == 'class' for row in rows):
            raise ValueError('payload class registry is empty or ambiguous')
        registries = {}
        for suite in ('forky', 'trixie'):
            physical = set()
            prefix = f'frontends/{suite}/classes/'
            for member in archive.getmembers():
                if member.name.startswith(prefix) and member.name.endswith('.cfg'):
                    kind, relative = member.name.removeprefix(prefix).split('/', 1)
                    if kind in {'class-auto', 'class-select', 'class-profile'}:
                        physical.add(('profile/' if kind == 'class-profile' else '')
                                     + relative.removesuffix('.cfg'))
            if refs != physical:
                raise ValueError(f'{suite}: payload class registry differs from physical classes')
            registries[suite] = physical
        for row in rows:
            if row[0] == 'class':
                for value in row[10:13]:  # Allowed/rejected/required class metadata.
                    for reference in value.split():
                        if reference != '__EMPTY__' and reference not in refs:
                            raise ValueError('unregistered class metadata reference: ' + reference)
        sources = {}
        total = 0
        for member in archive.getmembers():
            if member.isfile() and member.name.startswith((selectors['DIR_REPO_SCRIPTS'] + '/',
                                                            selectors['DIR_HOOKS_INSTALLER'] + '/')):
                if not member.name.endswith(('.sh', '.sh.tmpl')):
                    stream = archive.extractfile(member)
                    if stream is None:
                        raise ValueError('unreadable installer source header')
                    with stream:
                        header = stream.read(256).split(b'\n', 1)[0]
                    if re.fullmatch(rb'#!\s*(?:/bin/(?:sh|dash)|/usr/bin/env\s+sh)(?:\s+.*)?', header) is None:
                        continue
                total += member.size
                if total > 64 * 1024 * 1024:
                    raise ValueError('aggregate installer source audit bound exceeded')
                sources[member.name] = read_member(member)
                _check_class_queries(f'{archive_path.name}:{member.name}', sources[member.name],
                                     registries, errors, counts)
        _check_payload_late_contracts(archive, sources, selectors, errors, counts)
        _check_payload_perl_catalog(archive, selectors, errors, counts)
        counts['payload_class_registries'] = counts.get('payload_class_registries', 0) + 1


def _check_payload_perl_catalog(archive: tarfile.TarFile, selectors: dict[str, str],
                                errors: list[str], counts: dict[str, int]) -> None:
    """Compare the prepared Perl work list with source/package owners as data.

    This extends the existing changed-payload audit, never the installer path.
    It imports no target modules and executes no Perl or installer helpers.
    """
    members = {member.name: member for member in archive.getmembers()}

    def read(name: str) -> str:
        member = members[name]
        if not member.isfile() or member.size > 1024 * 1024:
            raise ValueError('invalid shared Perl catalog member: ' + name)
        stream = archive.extractfile(member)
        if stream is None:
            raise ValueError('unreadable shared Perl catalog member: ' + name)
        with stream:
            return stream.read(1024 * 1024 + 1).decode('utf-8')

    # The family segment and Perl include layout are the source partition
    # interface, also used by the serializer's shared-Perl catalog producer.
    prefix = selectors['DIR_TARGET_LIB'] + '/'
    expected = {}
    for name in members:
        if not name.startswith(prefix):
            continue
        match = re.fullmatch(r'(common|desktop|server)/perl5/site_perl/(.+\.pm(?:\.tmpl)?)',
                             name.removeprefix(prefix))
        if match:
            family, relative = match.groups()
            expected[name] = (relative.removesuffix('.tmpl'), family)
    rows = {}
    for line in read('catalog/compiled/shared-perl-assets.tsv').splitlines():
        fields = line.split('\t')
        if len(fields) != 3 or fields[0] in rows:
            raise ValueError('malformed or duplicate prepared Perl catalog row')
        rows[fields[0]] = tuple(fields[1:])
    if not expected or rows != expected:
        raise ValueError('prepared Perl catalog differs from physical source members')
    packages = {}
    for name, (relative, _family) in rows.items():
        namespace, separator, leaf = relative.partition('/')
        if (not separator or not re.fullmatch(r'[a-z][a-z0-9-]*', namespace)
                or not re.fullmatch(r'[A-Za-z_]\w*(?:/[A-Za-z_]\w*)*\.pm', leaf)):
            raise ValueError('invalid prepared Perl namespace member: ' + name)
        package = leaf.removesuffix('.pm').replace('/', '::')
        declarations = re.findall(r'^\s*package\s+([A-Za-z_]\w*(?:::\w+)*)\b', read(name), re.M)
        if declarations != [package]:
            errors.append(f'{name}: Perl package does not match catalog destination: {package}')
        packages[name] = package
    for family in ('desktop', 'server'):
        for snapshots in (False, True):
            selected = [(name, relative) for name, (relative, owner) in rows.items()
                        if owner in {'common', family}
                        and (snapshots or not relative.startswith('timeshift/'))]
            targets, owners = set(), set()
            for name, relative in selected:
                if relative in targets or packages[name] in owners:
                    errors.append(f'{family}: ambiguous prepared Perl member: {name}')
                targets.add(relative)
                owners.add(packages[name])
            counts['prepared_perl_selection_contexts'] = counts.get('prepared_perl_selection_contexts', 0) + 1
    counts['prepared_perl_catalog_members'] = counts.get('prepared_perl_catalog_members', 0) + len(rows)


def _check_payload_late_contracts(archive: tarfile.TarFile, sources: dict[str, str],
                                 selectors: dict[str, str], errors: list[str],
                                 counts: dict[str, int]) -> None:
    """Inspect published selectors, callback declarations and software data only."""
    members = {member.name for member in archive.getmembers() if member.isfile()}
    stream = archive.extractfile('catalog/compiled/source-members.tsv')
    if stream is None:
        raise ValueError('payload source-members catalog is missing')
    rows = stream.read(1048576).decode().splitlines()
    if not rows or rows[0] != 'format\t1':
        raise ValueError('payload source-members schema differs')
    listed = [line.split('\t') for line in rows[1:]]
    if (any(len(row) != 3 for row in listed) or
            len({row[0] for row in listed}) != len(listed) or
            {row[0] for row in listed} != members):
        raise ValueError('generated source membership differs from captured payload')
    counts['payload_source_members'] = len(listed)
    declarations = set()
    for name, text in sources.items():
        declarations.update(re.findall(r'^([a-zA-Z_][a-zA-Z0-9_]*)\(\) [({]', text, re.M))
        for match in re.finditer(r'\b(?:installer_repo_file_value|bootstrap_repo_file_value|'
                                 r'installer_stage_profile_file)(?:\s|\\\n)+'
                                 r'(?:"([A-Za-z0-9_./@+${} -]+)"|'
                                 r"'([A-Za-z0-9_./@+${} -]+)'|([A-Za-z0-9_./@+${}-]+))", text):
            member = next(value for value in match.groups() if value is not None)
            if member.startswith('FILE_'):
                errors.append(f'{name}: retired repository FILE selector: {member}')
            elif '/' in member and ('$' not in member or '${INSTALLER_SUITE}' in member):
                for selected in {member.replace('${INSTALLER_SUITE}', suite)
                                 for suite in ('forky', 'trixie')}:
                    if selected not in members:
                        errors.append(f'{name}: absent fixed source member: {selected}')
    for family in ('BTRFS', 'F2FS'):
        name = f'scripts/late/{family.lower()}-family.sh'
        lines = sources[name].splitlines()
        for index, line in enumerate(lines):
            match = re.fullmatch(r'\s*' + family.lower() + r'_late_command_mark (\d+) \w+', line)
            if match is None:
                continue
            following = index + 1
            while following < len(lines) and (not lines[following].strip()
                                             or lines[following].lstrip().startswith('#')):
                following += 1
            if int(match.group(1)) != following + 1:
                errors.append(f'{name}:{index + 1}: stale late operation source line')
            if following < len(lines):
                callback = re.match(r'\s*([a-zA-Z_]\w*)\b', lines[following])
                if callback and callback.group(1) not in {'case', 'if'} | declarations:
                    errors.append(f'{name}:{following + 1}: missing late callback: {callback.group(1)}')
            counts['late_operation_source_lines'] = counts.get('late_operation_source_lines', 0) + 1
    software_name = 'scripts/late/software.sh.tmpl'
    software = sources[software_name]
    for worker in re.findall(r'^software_run_selected_app "[^"]+" "[^"]+" (\w+) \w+$', software, re.M):
        if worker not in declarations:
            errors.append(f'{software_name}: missing managed application worker: {worker}')
        counts['software_worker_declarations'] = counts.get('software_worker_declarations', 0) + 1
    public_keys = set(re.findall(r'\$(?:\{)?(SOFTWARE_[A-Z0-9_]+)', software))
    for member in archive.getmembers():
        # This is the compiler's captured runtime-view interface, not an
        # installed target path. Account snapshots are a different data shape.
        if (not any(member.name.startswith(selectors['DIR_CATALOG_COMPILED'] + '/' + suite
                                           + '/profiles/desktop/') for suite in ('forky', 'trixie'))
                or not member.name.endswith('.env') or member.name.endswith('.account.env')):
            continue
        if not member.isfile() or member.size > 2 * 1024 * 1024:
            raise ValueError('invalid compiled desktop runtime member')
        stream = archive.extractfile(member)
        if stream is None:
            raise ValueError('unreadable compiled desktop runtime member')
        with stream:
            text = stream.read(2 * 1024 * 1024 + 1).decode('utf-8')
        values = {key: (shlex.split(raw) or [''])[0] for key, raw in
                  re.findall(r'^([A-Z][A-Z0-9_]*)=(.*)$', text, re.M)}
        for key in sorted(public_keys):
            value = values.get(key, '')
            valid = bool(value)
            if key.endswith(('_SHA256', '_SHA512')):
                valid = bool(re.fullmatch(r'[0-9a-f]{' + ('64' if key.endswith('_SHA256') else '128') + '}', value))
            elif key.endswith('_BYTES'):
                valid = bool(re.fullmatch(r'[1-9][0-9]{0,15}', value))
            elif key.endswith('_URL'):
                valid = value.startswith('https://') and not any(char.isspace() for char in value)
            if not valid:
                errors.append(f'{member.name}: missing or malformed software setting: {key}')
        counts['software_runtime_views'] = counts.get('software_runtime_views', 0) + 1

def check_desktop_resources(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Check slice ownership and pressure wiring strictly as source data."""
    if not any(path.is_relative_to(DEBIAN_ROOT) for path in paths):
        return
    skel = TARGET_ROOT / 'etc/skel-desktop/.config/systemd/user'
    units = TARGET_ROOT / 'etc/systemd/desktop'
    if (TARGET_ROOT / 'etc/skel-desktop/.profile.d/72-ci-runners.sh.tmpl').exists():
        raise ValueError('desktop skeleton must not install server CI runner administration')
    for runner_unit in ('ci-github.service.tmpl', 'ci-gitlab.service.tmpl'):
        runner_text = _read_text(TARGET_ROOT / ('etc/systemd/server/system/' + runner_unit))
        if 'scx-workload-handoff' in runner_text:
            raise ValueError('runner daemon must not switch the global scheduler for its whole lifetime: ' + runner_unit)
    for base, unit in ((skel, 'labwc-compositor'), (skel, 'waybar'), (skel, 'crystal-dock'),
                       (units / 'user', 'mako')):
        text = _read_text(base / (unit + '.service.d/60-resource-class.conf'))
        if re.findall(r'^Slice=(\S+)$', text, re.M) != ['session.slice']:
            raise ValueError('desktop infrastructure must use session.slice: ' + unit)
    for module in ('generic.py', 'session.py', 'runtime.py'):
        source = _read_text(target_source('usr/local/lib/python3/dist-packages/labwc_managed_app/' + module))
        if '"--slice=app.slice"' not in source or '"--slice=session.slice"' in source:
            raise ValueError('application transient loses its distinct slice: ' + module)
    build = _read_text(units / 'user/build.slice.tmpl')
    for key in ('CPUWeight', 'IOWeight', 'MemoryHigh', 'MemoryMax', 'MemorySwapMax', 'TasksMax'):
        if re.search(r'^' + key + r'=__SYSTEMD_BUILD_[A-Z_]+__$', build, re.M) is None:
            raise ValueError('build slice lacks profile-owned bound: ' + key)
    for name in ('user.slice.d', 'user-.slice.d', 'user@.service.d'):
        if 'MemoryLow=__SYSTEMD_MEMORY_LOW_DESKTOP_ANCESTRY__' not in _read_text(
                units / 'system' / name / '60-desktop-memory.conf.tmpl'):
            raise ValueError('desktop memory protection loses an ancestor: ' + name)
    helper = _read_text(target_source('usr/local/bin/labwc-build'))
    for option in ('--user', '--scope', '--slice=build.slice', '--expand-environment=no',
                   'KillMode=control-group', 'TimeoutStopSec=15s'):
        if option not in helper:
            raise ValueError('build launcher loses scope ownership: ' + option)
    if '--system' in helper or 'DEVOPS_BUILD_ACTIVE' in helper or '|| exec' in helper:
        raise ValueError('build launcher must not trust a marker or retry unconfined')
    for storage_contract in (
            'mountpoint --quiet -- __INSTALLER_PATH_DIR_POOL__',
            'build_account=$(__INSTALLER_PATH_DIR_USR_BIN__/id -un)',
            'build_account_root="__INSTALLER_PATH_DIR_POOL_BUILD__/${build_account}"',
            'build_tmp="${build_account_root}/tmp"',
            '"$build_uid:2770"', '"$build_uid:700"',
            'TMPDIR=$build_tmp', 'TMP=$build_tmp', 'TEMP=$build_tmp',
            'CARGO_TARGET_DIR="${build_account_root}/cargo/target"',
            'GOTMPDIR=$build_tmp',
            'export TMPDIR TMP TEMP CARGO_TARGET_DIR GOTMPDIR'):
        if storage_contract not in helper:
            raise ValueError('ordinary builds lose their pool boundary: ' + storage_contract)
    if helper.index('export TMPDIR TMP TEMP CARGO_TARGET_DIR GOTMPDIR') > helper.index('0::*/build.slice/*'):
        raise ValueError('nested build scope bypasses pool storage policy')
    pool_policy = _read_text(target_source('etc/tmpfiles.d/75-desktop-pool-storage.conf.tmpl'))
    if ('d __INSTALLER_DIR_POOL_BUILD__/__INSTALLER_ACCOUNT_USERNAME__/tmp 0700 '
            '__INSTALLER_ACCOUNT_USERNAME__ __INSTALLER_ACCOUNT_USERNAME__ -') not in pool_policy:
        raise ValueError('desktop build scratch directory lacks private installer provisioning')
    profile = _read_text(TARGET_ROOT / 'etc/skel-desktop/.profile.d/71-devops-de.sh')
    if '__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-build "$devops_de_shell" -i' not in profile:
        raise ValueError('DevOps shell no longer owns compiler descendants in build.slice')
    for command in ('make', 'cargo', 'rustc', 'c++', 'ninja', 'cmake', 'clang++'):
        if f"alias {command}='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-build {command}'" not in profile:
            raise ValueError('ordinary interactive compiler loses build routing: ' + command)
    perl = TARGET_ROOT / 'usr/local/lib/common/perl5/site_perl/zram-writeback/Zram'
    policy = _read_text(perl / 'Policy.pm')
    controller = _read_text(perl / 'Daemon/Controller.pm')
    if ("'ZRAM_EMERGENCY_WORK_MAX_PAGES'" not in policy
            or '$work_remaining -= $pages' not in policy
            or '$plan{writeback_pass_pages} = $remaining_pages' not in policy
            or "'ZRAM_PRESSURE_WORK_MAX_PAGES'" not in policy
            or "$plan{compact} = $state eq 'normal'" not in policy
            or 'last_emergency_pass_at' not in controller):
        raise ValueError('emergency maintenance loses aggregate work or cooldown ownership')
    template = _read_text(TARGET_ROOT / 'etc/zram-writeback/policy.conf.tmpl')
    renderer = _read_text(DEBIAN_ROOT / 'scripts/late/templates.sh')
    if ('emergency_work_max_pages = __ZRAM_EMERGENCY_WORK_MAX_PAGES__' not in template
            or 'ZRAM_EMERGENCY_WORK_MAX_PAGES=$ZRAM_EMERGENCY_WORK_MAX_PAGES' not in renderer):
        raise ValueError('emergency work policy is not rendered into runtime configuration')
    for name, variable in re.findall(r'^\s*(SYSTEMD_[A-Z0-9_]+)\) value=\$(SYSTEMD_[A-Z0-9_]+) ;;', renderer, re.M):
        if name != variable:
            raise ValueError('resource policy field reads a different variable: ' + name)
    counts['desktop_resource_slice_contracts'] = 3
    counts['desktop_memory_protection_ancestors'] = 3
    counts['desktop_build_pool_boundary'] = 1
    counts['zram_emergency_envelope_contracts'] = 1
    counts['zram_pressure_envelope_contracts'] = 1


def check_crypto_boot_contract(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Inspect crypto acquisition/cleanup contracts without loading a helper."""
    policy = target_source('usr/local/libexec/tpm2-policy-check')
    late = DEBIAN_ROOT / 'scripts/late/crypto.sh'
    hook = TARGET_ROOT / 'etc/initramfs-tools/hooks/tpm2-cryptroot'
    local_top = TARGET_ROOT / 'etc/initramfs-tools/scripts/local-top/00-tpm2-cryptroot'
    cleanup = DEBIAN_ROOT / 'scripts/firstboot/assets/var/lib/firstboot/bin/secondboot-cleanup'
    armor = target_source('etc/apparmor.d/usr.local.sbin.tpm2-enroll.sh')
    boot_armor = DEBIAN_ROOT / 'scripts/firstboot/assets/etc/apparmor.d/firstboot.tmpl'
    runtime = DEBIAN_ROOT / 'hosts/installer/runtime.env'
    enrollment = DEBIAN_ROOT / 'scripts/firstboot/assets/usr/local/sbin/tpm2-enroll.sh'
    bootstrap = DEBIAN_ROOT / 'scripts/late/crypto-bootstrap.py.tmpl'
    installer_paths = DEBIAN_ROOT / 'hooks/installer/di.env'
    owners = {policy, late, hook, local_top, cleanup, armor, boot_armor, runtime, enrollment,
              bootstrap, installer_paths}
    if not owners.intersection(paths):
        return
    source = _read_text(policy)
    tree = ast.parse(source, filename=str(policy.relative_to(ROOT)))
    definitions = {node.name: node for node in tree.body if isinstance(node, ast.FunctionDef)}
    inspection = definitions.get('verify_initramfs')
    gate = definitions.get('verify_boot_cleanup')
    evidence = definitions.get('verify_boot_evidence')
    if not inspection or not gate or not evidence:
        raise ValueError('crypto archive inspection or cleanup gate is missing')
    body = ast.get_source_segment(source, inspection)
    for contract in ("entry.name.endswith('.sig')", 'entry.stat(follow_symlinks=False)',
                     'index >= 4096', 'len(images) > 64', 'time.monotonic() + 300',
                     'total_bytes > 33_554_432', 'timeout=min(120, remaining)',
                     'enumerate(io.BytesIO(raw))', 'member_index >= 100_000',
                     'total_members > 200_000', 'len(encoded) > 4096',
                     'time.monotonic() >= deadline',
                     'identity(image.lstat()) != identity(before)',
                     'identity(BOOT.lstat()) != boot_identity',
                     "name.startswith(state_name + '/')", 'CRYPTO_LUKS2_ROOT'):
        if contract not in body:
            raise ValueError('crypto image inspection loses contract: ' + contract)
    identities = [node for node in inspection.body if isinstance(node, ast.FunctionDef) and node.name == 'identity']
    if len(identities) != 1:
        raise ValueError('crypto image inspection requires one metadata identity contract')
    identity = identities[0]
    fields = {node.attr for node in ast.walk(identity) if isinstance(node, ast.Attribute)}
    if not {'st_dev', 'st_ino', 'st_mode', 'st_uid', 'st_gid', 'st_nlink', 'st_size',
            'st_mtime_ns', 'st_ctime_ns'}.issubset(fields) or 'st_atime' in fields or 'st_atime_ns' in fields:
        raise ValueError('crypto image identity loses content/ownership fields or depends on access time')
    libraries = [node.value for node in inspection.body if isinstance(node, ast.Assign)
                 and any(isinstance(target, ast.Name) and target.id == 'libraries' for target in node.targets)]
    if len(libraries) != 1:
        raise ValueError('crypto image inspection requires one literal native library list')
    families = ast.literal_eval(libraries[0])
    hook_text = _read_text(hook)
    loop = re.search(r'^for token_library in ([A-Za-z0-9 -]+); do$', hook_text, re.M)
    if (not isinstance(families, tuple) or not loop or tuple(loop[1].split()) != families
            or len(families) != 5 or 'libcrypto' not in families):
        raise ValueError('crypto initrd hook and verifier disagree about native dynamic libraries')
    constants = {node.value for node in ast.walk(inspection) if isinstance(node, ast.Constant)
                 and isinstance(node.value, str)}
    if (r'\( -type f -o -type l \)' not in hook_text
            or 'copy_exec "$token_library_file" "$token_library_file"' not in hook_text
            or r'\.so\.[0-9]+' not in constants):
        raise ValueError('crypto initrd hook/verifier loses package SONAME links')
    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)
             and isinstance(node.func, ast.Name) and node.func.id == 'verify_initramfs']
    if len(calls) != 3 or any(len(node.args) != 1 or not isinstance(node.args[0], ast.Name)
                              or node.args[0].id != 'values' for node in calls):
        raise ValueError('crypto archive callers must pass the validated root/home policy')
    late_text = _read_text(late)
    if ('"${DIR_USR_LOCAL_LIBEXEC}/tpm2-policy-check" --initramfs' not in late_text
            or 'lsinitramfs' in late_text or 'initrd.img-*' in late_text):
        raise ValueError('late crypto must use the permanent shared archive verifier')
    gate_text = ast.get_source_segment(source, gate)
    for contract in ('INITRAMFS_CLEANUP_PENDING', 'INITRAMFS_HEALTH_COMMON', 'BOOT_ARTIFACTS_CLEANED',
                     '.lstat()', 'except FileNotFoundError', 'private_read(', 'boot_id()'):
        if contract not in gate_text:
            raise ValueError('crypto enrollment loses cleanup handoff: ' + contract)
    if '.exists()' in gate_text or '.is_symlink()' in gate_text:
        raise ValueError('crypto cleanup gate must not hide metadata/access failures')
    def cleanup_call(node: ast.AST) -> bool:
        return (isinstance(node, ast.Expr) and isinstance(node.value, ast.Call)
                and isinstance(node.value.func, ast.Name) and node.value.func.id == 'verify_boot_cleanup')
    if not cleanup_call(evidence.body[0]) or not cleanup_call(evidence.body[-2]):
        raise ValueError('crypto evidence must check cleanup before and after measured-boot reads')
    cleanup_text = _read_text(cleanup)
    start = cleanup_text.index('remove_initramfs_health_hooks() {')
    function = cleanup_text[start:cleanup_text.index('\n}\n', start)]
    order = [function.index(value) for value in ('sync -f "$pending_candidate"',
        'rm -f -- "$hook_path"', 'update-initramfs -u -k all', '--mark-boot-artifacts',
        'rm -f -- "$initramfs_pending"')]
    if order != sorted(order):
        raise ValueError('crypto cleanup must retain pending evidence through rebuild/inspection/boot stamp')
    pending = '__INSTALLER_PATH_FILE_FIRSTBOOT_INITRAMFS_CLEANUP_PENDING__'
    stamped = '__INSTALLER_PATH_FILE_CRYPTO_BOOT_ARTIFACTS_CLEANED__'
    config = '__INSTALLER_PATH_FILE_TPM2_CRYPTROOT_CONFIG__'
    if (pending not in cleanup_text or pending + ' r,' not in _read_text(armor)
            or stamped not in cleanup_text or stamped not in _read_text(boot_armor)
            or config not in hook_text or config not in _read_text(local_top)
            or '"$FILE_TPM2_CRYPTROOT_CONFIG"' not in late_text):
        raise ValueError('crypto runtime paths, producers, consumers or exact AppArmor rule disagree')
    enrollment_text = _read_text(enrollment)
    for action in ('--boot-evidence', '--initramfs'):
        branch = enrollment_text.split('if "$POLICY_CHECK" ' + action + '; then :; else\n', 1)
        if len(branch) != 2 or '[ "$crypto_status" -ne 76 ] || exit 76' not in branch[1].split('\nfi', 1)[0]:
            raise ValueError('crypto enrollment loses uncertain read/check result: ' + action)
    counts['crypto_shared_initramfs_contracts'] = 1
    counts['crypto_dynamic_library_families'] = len(families)
    counts['crypto_cleanup_handoff_contracts'] = 1
    counts['crypto_uncertain_check_adapters'] = 2
    bootstrap_text = _read_text(bootstrap)
    bootstrap_tree = ast.parse(bootstrap_text, filename=str(bootstrap.relative_to(ROOT)))
    bootstrap_functions = {node.name: node for node in bootstrap_tree.body if isinstance(node, ast.FunctionDef)}
    required = {'bootstrap_runtime_snapshot', 'bootstrap_disk_identity', 'bootstrap_partition',
                'bootstrap_guard', 'bootstrap_command', 'bootstrap_token', 'bootstrap_main'}
    if not required.issubset(bootstrap_functions):
        raise ValueError('installer crypto loses its selected-device or transaction boundary')
    for contract in ('device_identity(7)', 'bootstrap_partition(fd, record[\'slot\'])',
                     "sys_device / 'diskseq'", "member / 'partition'", "member.parent / 'dev'",
                     'time.monotonic() + 600', '_BOOTSTRAP_OUTPUT_REMAINING = 33554432',
                     'len(encoded) > 1048576',
                     "_RUNTIME['command'] = bootstrap_command", 'enrollment_lock()',
                     'os.pread(4, 65, 0)', 'os.link(candidate, credential, follow_symlinks=False)',
                     'private_read(TRANSACTION, 1048576)', "retained.get('state') != 'verified'",
                     "record['state'] = 'enrolling'", "record['state'] = 'verified'",
                     "'--tpm2-public-key='", "'--tpm2-pcrlock='", "'--token-only'", 'sys.exit(76)', 'sys.exit(69)'):
        if contract not in bootstrap_text:
            raise ValueError('installer crypto loses a device/recovery contract: ' + contract)
    main = bootstrap_functions['bootstrap_main']
    writes = [index for index, node in enumerate(main.body) if isinstance(node, ast.Expr)
              and isinstance(node.value, ast.Call) and isinstance(node.value.func, ast.Name)
              and node.value.func.id == 'bootstrap_write']
    transactions = [index for index, node in enumerate(main.body) if isinstance(node, ast.Try)]
    if len(writes) != 1 or len(transactions) != 1 or writes[0] >= transactions[0]:
        raise ValueError('installer crypto must durably record intent before sealing or token mutation')
    if (late_text.count('installer_run_target_setup scripts/late/crypto-bootstrap.py.tmpl ') != 1
            or 'exec 4<"$crypto_bootstrap" 7<"$DEV_INSTALL_DISK"' not in late_text
            or 'exec 5<"$DEV_PART_ROOT"' not in late_text or 'exec 6<"$DEV_PART_HOME"' not in late_text
            or 'systemd-cryptenroll' in late_text or 'systemd-creds' in late_text):
        raise ValueError('late crypto must bind selected handles and delegate initial native enrollment once')
    path_key = 'FILE_INSTALLER_SELECTED_DISK_IDENTITY'
    if path_key not in _read_text(installer_paths) or path_key not in _read_text(DEBIAN_ROOT / 'scripts/common/bootstrap.sh'):
        raise ValueError('selected physical disk identity path is not owned and required by the installer contract')
    for name in ('scripts/common/hook.sh', 'hooks/installer/partman/early.sh',
                 'hooks/installer/partman/finish.d/99-storage-layout.sh'):
        text = _read_text(DEBIAN_ROOT / name)
        if path_key not in text or 'selected-disk.identity' in text:
            raise ValueError('selected disk identity producer/consumer bypasses its canonical path: ' + name)
    counts['crypto_installer_device_bindings'] = 3
    counts['crypto_installer_bootstrap_transactions'] = 1
    handoff = definitions.get('verify_bootstrap_transaction')
    main = definitions.get('main')
    if not handoff or not main:
        raise ValueError('permanent crypto maintenance lacks the installer handoff gate')
    handoff_text = ast.get_source_segment(source, handoff)
    if ('private_read(BOOTSTRAP_TRANSACTION, 1048576)' not in handoff_text
            or "record.get('state') != 'verified'" not in handoff_text
            or 'set(devices) != set(expected)' not in handoff_text
            or 'raise OutcomeUnknown' not in handoff_text
            or 'verify_bootstrap_transaction(values)' not in ast.get_source_segment(source, main)):
        raise ValueError('permanent crypto maintenance accepts an unverified or mismatched installer transaction')
    receipt_token = '__INSTALLER_PATH_FILE_CRYPTO_BOOTSTRAP_TRANSACTION__'
    if any(receipt_token + ' r,' not in _read_text(path) for path in (armor, boot_armor)):
        raise ValueError('permanent crypto handoff is absent from an exact AppArmor consumer')
    if ('crypto_policy_require() {' not in enrollment_text
            or 'if crypto_config_data=$("$POLICY_CHECK" --config-data); then :; else' not in enrollment_text
            or '$("$POLICY_CHECK" --config-data)\nEOF' in enrollment_text):
        raise ValueError('crypto configuration adapter loses its producer or uncertain status')
    counts['crypto_bootstrap_runtime_handoffs'] = 1


def check_class_selection(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Inspect the early POSIX parser and its literal regression inputs as data."""
    owner = DEBIAN_ROOT / 'scripts/common/modules/class-selection.sh'
    fixture = DEBIAN_ROOT / 'tests/fixtures/class-parser-failures.json'
    if not {owner, fixture}.intersection(paths):
        return
    source = _read_text(owner)
    for contract in (
            'case "$raw" in',
            '*[[:space:]]*|*[![:print:]]*)',
            'class_validation_tokens=$(printf',
            "sed 's/\\\\\\([;,]\\)/ /g; s/[;,]/ /g'",
            'for class_validation_token in $class_validation_tokens; do',
            "''|*[!abcdefghijklmnopqrstuvwxyz0123456789_/-]*)"):
        if contract not in source:
            raise ValueError('class selection token validation contract is incomplete: ' + contract)
    for contract in ('installer_normalize_class_tokens() (',
                     'normalize_records=$(installer_configured_class_records) || return "$?"',
                     '[ "$normalize_count" -le 64 ]',
                     '[ "${#normalize_token}" -le 160 ]',
                     '[ "${normalize_name##*/}" = "$normalize_token" ]',
                     'ambiguous class basename; use the canonical group/name spelling',
                     'normalized_raw=$(installer_normalize_class_tokens "$normalized_raw") || return "$?"',
                     'auto_output=$(installer_auto_class_tokens "$(installer_seed_base "$seed_base")") || return "$?"',
                     'class_lines=$(installer_classes_lines "$seed_base") || return "$?"',
                     'for class_token in $class_lines; do'):
        if contract not in source:
            raise ValueError('class parser loses an input or status boundary: ' + contract)
    if 'for class_token in $(installer_classes_lines' in source:
        raise ValueError('class iteration must preserve its producer failure status')
    if source.index('normalized_raw=$(installer_normalize_class_tokens') > source.index('auto_output=$(installer_auto_class_tokens'):
        raise ValueError('manual classes must be canonical before hardware class merging')
    data = json.loads(_read_text(fixture))
    if data.get('execution') != 'unexecuted; static source and literal-data review only':
        raise ValueError('class parser fixture execution boundary is missing')
    cases = {item['id']: item for item in data['cases']}
    logged = cases['fatal-20261112-hyphenated-bare-classes']
    if (logged['input'] != 'prod;full;static;btrfs-de-p15s;nvidia-legacy;cuda-legacy'
            or logged['canonical'] != ['site/prod', 'role/desktop/full', 'network/static',
                                      'profile/desktop/btrfs-de-p15s', 'optional/nvidia-legacy', 'optional/cuda-legacy']):
        raise ValueError('class parser fixture no longer describes the supplied fatal failure')
    if not {'ambiguous-basename', 'duplicate-canonical-basename', 'traversal', 'encoded-traversal',
            'shell-metacharacter', 'empty-selector', 'hardware-producer-failure',
            'stale-cache-is-revalidated'}.issubset(cases):
        raise ValueError('class parser failure fixtures lose a required boundary')
    counts['class_parser_source_contracts'] = 1
    counts['class_parser_unexecuted_cases'] = len(cases)


def check_timeshift_profile_policy(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Profile gating and absence checks; no profile or managed code executes."""
    compiler = ROOT / 'tools/class_compiler.py'
    dispatcher = DEBIAN_ROOT / 'hooks/installer/class-dispatch.tsv'
    owner = DEBIAN_ROOT / 'scripts/common/timeshift.sh'
    profiles = DEBIAN_ROOT / 'hosts/profiles'
    if not any(path in {compiler, dispatcher, owner} or path.is_relative_to(profiles)
               or 'timeshift' in path.name for path in paths):
        return
    for suite in ('forky', 'trixie'):
        classes = ROOT / 'd-i' / suite / 'classes'
        if any(classes.rglob('*timeshift*.cfg')):
            raise ValueError('Timeshift is host-profile policy and must have no class selector')
        for role in (classes / 'class-select/role').glob('*/*.cfg'):
            if re.search(r'\btimeshift\b', _read_text(role)):
                raise ValueError('unconditional Timeshift in role class: ' + str(role.relative_to(ROOT)))
        fragment = ROOT / 'd-i' / suite / 'fragments/timeshift.cfg'
        if 'd-i pkgsel/include string timeshift' not in _read_text(fragment):
            raise ValueError('missing conditional Timeshift package fragment')
    total = 0
    for family in ('desktop', 'server'):
        for profile in (profiles / family).glob('*.env'):
            if profile.name.startswith('shared-'):
                continue
            text = _read_text(profile)
            if len(re.findall(r'^TIMESHIFT_ENABLE=[\'"](?:true|false)[\'"]$', text, re.M)) != 1:
                raise ValueError('profile requires one explicit Timeshift boolean: ' + profile.name)
            if re.search(r'^(?:GRUB_BTRFS_ENABLE|SNAPSHOTS_POLICY)=', text, re.M):
                raise ValueError('profile has a second Timeshift/GRUB policy owner: ' + profile.name)
            total += 1
    source = _read_text(compiler)
    if ("if profile_values['TIMESHIFT_ENABLE'] == 'true':\n                selected_refs.append('fragments/timeshift.cfg')" not in source
            or "values['TIMESHIFT_ENABLE'] == 'true' and profile['filesystem'] != 'btrfs'" not in source):
        raise ValueError('Timeshift packages must follow the validated Btrfs profile switch')
    resolver = _read_text(DEBIAN_ROOT / 'scripts/common/resolve-plan.awk')
    if 'if(snapshots=="timeshift-btrfs") add("fragments/timeshift.cfg")' not in resolver:
        raise ValueError('d-i resolver lost conditional Timeshift package inclusion')
    row = 'stage\tfragments/timeshift.cfg\tos.timeshift\tlate\tscripts/common/timeshift.sh\t'
    dispatch_text = _read_text(dispatcher)
    if sum(line.startswith(row) for line in dispatch_text.splitlines()) != 1:
        raise ValueError('Timeshift requires one profile-enabled fragment stage owner')
    late = _read_text(owner)
    if late.index('installer_snapshots_enabled ||') > late.index('installer_stage_profile_file'):
        raise ValueError('Timeshift publishes assets before checking the frozen profile policy')
    foundation = _read_text(DEBIAN_ROOT / 'scripts/common/system-foundation.sh')
    if 'timeshift/*) installer_snapshots_enabled || continue' not in foundation:
        raise ValueError('disabled Timeshift modules must not be published')
    menu = _read_text(target_source('usr/local/bin/labwc-maintenance-menu.tmpl'))
    recovery = _read_text(target_source('usr/local/libexec/labwc-recovery-action-root'))
    if "if not TIMESHIFT_CONFIG.is_file() or TIMESHIFT_CONFIG.is_symlink():" not in menu or 'exec __INSTALLER_PATH_FILE_TIMESHIFT_SNAPSHOT_HELPER__ manual' not in recovery:
        raise ValueError('desktop snapshot UI bypasses profile absence or the managed snapshot owner')
    counts['timeshift_profile_booleans'] = total
    counts['timeshift_conditional_package_fragments'] = 2


def check_server_configuration(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Inspect configuration ordering and readiness as source, never run it."""
    owner = TARGET_ROOT / 'usr/local/libexec/server/installer-serverctl.py.tmpl'
    runtime = DEBIAN_ROOT / 'hosts/installer/runtime.env'
    renderer = DEBIAN_ROOT / 'scripts/common/modules/files-logging.sh'
    if not {owner, runtime, renderer}.intersection(paths):
        return
    source = _read_text(owner)
    tree = ast.parse(source, filename=str(owner.relative_to(ROOT)))
    functions = {node.name: node for node in tree.body if isinstance(node, ast.FunctionDef)}
    required = {'regular', 'dns_policy_snapshot', 'dns_resolver_plan', 'dns_resolver_handover',
                'dns_configuration_ready', 'configure_dns', 'backup', 'update_dns', 'restore_dns', 'main'}
    if not required.issubset(functions):
        raise ValueError('server configuration loses a recovery or readiness owner')

    def calls(node, name):
        return [child for child in ast.walk(node) if isinstance(child, ast.Call)
                and isinstance(child.func, ast.Name) and child.func.id == name]

    capture = functions['regular']
    fields = {node.attr for node in ast.walk(capture) if isinstance(node, ast.Attribute)}
    if not {'O_NONBLOCK', 'O_NOFOLLOW', 'st_dev', 'st_ino', 'st_mode', 'st_nlink', 'st_uid',
            'st_gid', 'st_size', 'st_mtime_ns', 'st_ctime_ns'}.issubset(fields):
        raise ValueError('shared server data capture loses nonblocking or stable identity checks')
    for name in ('dns_resolver_plan', 'dns_policy_snapshot'):
        if calls(functions[name], 'write') or calls(functions[name], 'protected_directory'):
            raise ValueError('DNS policy inspection must not publish or create directories')
    configure = functions['configure_dns']
    candidate_nodes = [node.value for node in configure.body if isinstance(node, ast.Assign)
                       and any(isinstance(target, ast.Name) and target.id == 'candidates' for target in node.targets)]
    if len(candidate_nodes) != 1 or not isinstance(candidate_nodes[0], ast.Tuple):
        raise ValueError('DNS configuration requires one complete candidate set')
    candidates = candidate_nodes[0].elts
    firewall = [node for node in candidates if isinstance(node, ast.Tuple)
                and isinstance(node.elts[0], ast.Name) and node.elts[0].id == 'firewall']
    if (len(candidates) != 6 or len(firewall) != 1 or len(firewall[0].elts) != 3
            or not isinstance(firewall[0].elts[1], ast.Name) or firewall[0].elts[1].id != 'rules'):
        raise ValueError('DNS firewall must have exactly one complete publication candidate')
    transactions = [node for node in configure.body if isinstance(node, ast.Try)]
    if len(transactions) != 1:
        raise ValueError('DNS configuration requires one uncertainty-preserving publication transaction')
    transaction = transactions[0]
    for call in calls(configure, 'write'):
        if call.lineno < transaction.lineno and (not call.args or not isinstance(call.args[0], ast.Name)
                                                or call.args[0].id != 'saved'):
            raise ValueError('DNS configuration publishes state before candidate validation and recovery capture')
    first = transaction.body[0]
    if (not isinstance(first, ast.Expr) or not isinstance(first.value, ast.Call)
            or not isinstance(first.value.func, ast.Name) or first.value.func.id != 'write'
            or not isinstance(first.value.args[0], ast.Name) or first.value.args[0].id != 'DNS_CONFIGURATION'):
        raise ValueError('DNS configuration must publish its private journal before mutation')
    body = ast.get_source_segment(source, configure)
    for contract in ('rules = before + begin + acl + end + after', 'DNS private bridge overlaps a physical uplink',
                     'snapshots[firewall] != firewall_before', 'dns_policy_snapshot(path) != snapshots[path]',
                     "record.update(backup=str(saved), mode=snapshot['mode'], uid=snapshot['uid'], gid=snapshot['gid']",
                     "transaction['published'].append(str(path))", 'except BaseException as error:',
                     "transaction['state'] = 'configured-activation-pending'"):
        if contract not in body:
            raise ValueError('DNS configuration loses source contract: ' + contract)
    handover = calls(configure, 'dns_resolver_handover')
    prepared = [node for node in ast.walk(configure) if isinstance(node, ast.Call)
                and isinstance(node.func, ast.Attribute) and node.func.attr == 'prepare']
    if len(handover) != 1 or len(prepared) != 1 or prepared[0].lineno >= handover[0].lineno:
        raise ValueError('DNS stopped guest preparation must precede resolver handover')
    for name in ('backup', 'update_dns', 'restore_dns'):
        if not calls(functions[name], 'dns_configuration_ready'):
            raise ValueError('DNS maintenance lacks its complete-configuration gate: ' + name)
    if len(calls(functions['main'], 'dns_configuration_ready')) != 2:
        raise ValueError('DNS start and configured status require a complete configuration receipt')
    key = 'FILE_SERVER_DNS_CONFIGURATION_TRANSACTION'
    if (key not in _read_text(runtime) or dict(_runtime_path_schema_rows()).get('PATH_' + key) != key
            or '__INSTALLER_PATH_' + key + '__' not in source):
        raise ValueError('DNS configuration journal path is not wired through its owning renderer')
    counts['server_configuration_policy_files'] = len(candidates) + 1
    counts['server_configuration_readiness_gates'] = 5


def check_private_server_setup(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Compare installer/maintenance boundaries without managed imports."""
    setup = DEBIAN_ROOT / 'scripts/server/setup.py.tmpl'
    control = TARGET_ROOT / 'usr/local/libexec/server/installer-serverctl.py.tmpl'
    workload = TARGET_ROOT / 'usr/local/lib/server/technitium_incus.py.tmpl'
    credentials = DEBIAN_ROOT / 'scripts/common/credentials.sh'
    owners = {setup, control, workload, credentials}
    if not owners.intersection(paths):
        return
    sources = {path: _read_text(path) for path in (setup, control, workload)}
    trees = {path: ast.parse(source, filename=str(path.relative_to(ROOT))) for path, source in sources.items()}
    definitions = {path: {node.name: node for node in tree.body if isinstance(node, ast.FunctionDef)}
                   for path, tree in trees.items()}
    for name in ('regular', 'trusted_directory', 'json_document', 'dns_account_identity', 'selected_server_roles'):
        if ast.dump(definitions[setup][name], include_attributes=False) != ast.dump(definitions[control][name], include_attributes=False):
            raise ValueError('installer and maintenance disagree about protected server data: ' + name)
    if not {'foundation', 'install', 'configure_runner', 'verify_gitlab_credentials', 'stage_dns_credentials'} <= definitions[setup].keys():
        raise ValueError('initial server setup lacks its installer-only owner')
    if {'foundation', 'install', 'configure_runner', 'enroll'}.intersection(definitions[control]):
        raise ValueError('persistent server maintenance must not install or enroll runners')
    for name in ('foundation.sh', 'services.sh'):
        shell = _read_text(DEBIAN_ROOT / 'scripts/server' / name)
        if 'server_roles=$(installer_plan_roles) || exit "$?"' not in shell or '$(installer_plan_roles)\nEOF' in shell:
            raise ValueError('server role iteration loses its frozen-plan producer status: ' + name)
    if 'configure-runner' in sources[control] or "'enroll'" in sources[control]:
        raise ValueError('target maintenance CLI exposes an installer enrollment operation')
    runner = ast.get_source_segment(sources[setup], definitions[setup]['configure_runner']) or ''
    for contract in ("extra={'ACTIONS_RUNNER_INPUT_TOKEN': token}",
                     "policy['default_image']", "policy['pull_policy']", "policy['helper_flavor'] != 'ubuntu'",
                     "policy.get('helper_images')", "target_architecture()",
                     "policy['podman_socket']",
                     "'installed-but-pending-enrollment'", "'enrollment-uncertain'", "'enrolled-activation-pending'",
                     "'online': False", "'--config', str(path)", 'verify_gitlab_credentials(url, token, home, uid)'):
        if contract not in runner:
            raise ValueError('private native runner setup loses a contract: ' + contract)
    if any(value in runner for value in ('allowed_images', '--token', 'privileged = true', '/var/run/docker.sock', 'alpine')):
        raise ValueError('runner setup exposes a token, forces an image or grants privileged job authority')
    verify = ast.get_source_segment(sources[setup], definitions[setup]['verify_gitlab_credentials']) or ''
    for contract in ("input_data=body, timeout=45", "'--max-time', '30'", "'--max-redirs', '0'",
                     "status_code != b'200'", "'/api/v4/runners/verify'", "'online': False"):
        if contract not in verify:
            raise ValueError('private GitLab verification lacks its structured bounded acknowledgement: ' + contract)
    config_token = '__INSTALLER_PATH_FILE_SERVER_GITLAB_CONFIG__'
    unit = _read_text(TARGET_ROOT / 'etc/systemd/server/system/ci-gitlab.service.tmpl')
    if (config_token not in runner or '--config ' + config_token not in unit
            or '__INSTALLER_PATH_DIR_SERVER_GITLAB_CONFIG__' not in verify):
        raise ValueError('native GitLab configuration and writable manager-identity directory disagree')
    shared_server_profile = _read_text(DEBIAN_ROOT / 'hosts/profiles/server/shared-srv.env')
    for key in ('PODMAN_GITHUB_USER', 'PODMAN_GITHUB_GROUP', 'PODMAN_GITHUB_RUNTIME_DIR',
                'PODMAN_GITHUB_SOCKET', 'PODMAN_GITLAB_USER', 'PODMAN_GITLAB_GROUP',
                'PODMAN_GITLAB_RUNTIME_DIR', 'PODMAN_GITLAB_SOCKET', 'PODMAN_DEVOPS_USER',
                'PODMAN_DEVOPS_GROUP',
                'CI_RUNNER_CPU_WEIGHT', 'CI_RUNNER_IO_WEIGHT', 'CI_RUNNER_TASKS_MAX',
                'CI_RUNNER_MEMORY_HIGH', 'CI_RUNNER_MEMORY_MAX'):
        if not re.search(r'^' + key + r'=', shared_server_profile, re.M):
            raise ValueError('server shared profile loses Podman/runner ownership: ' + key)
    github_unit = _read_text(TARGET_ROOT / 'etc/systemd/server/system/ci-github.service.tmpl')
    for provider, unit_text in (('GITHUB', github_unit), ('GITLAB', unit)):
        suffixes = ('USER', 'GROUP', 'RUNTIME_DIR', 'SOCKET') if provider == 'GITHUB' else ('USER', 'GROUP', 'RUNTIME_DIR')
        for suffix in suffixes:
            token = '__INSTALLER_PODMAN_' + provider + '_' + suffix + '__'
            if token not in unit_text:
                raise ValueError('runner service account is not sourced from server shared policy: ' + token)
    credential_text = _read_text(credentials)
    for field in ('USERNAME', 'PASSWORD', 'WEB_USERNAME', 'WEB_PASSWORD', 'TLS_PASSPHRASE', 'BACKUP_PASSPHRASE'):
        if 'PRESEED_TECHNITIUM_' + field not in credential_text:
            raise ValueError('missing private initrd Technitium credential mapping: ' + field)
    if any(value in credential_text for value in ('PRESEED_CI_GITHUB_URL', 'PRESEED_CI_GITLAB_URL', 'PRESEED_TECHNITIUM_ADMIN_PASSWORD')):
        raise ValueError('public URLs or retired Tech credential alias remain in private inputs')
    identity = ast.get_source_segment(sources[setup], definitions[setup]['stage_dns_credentials']) or ''
    if ("'--method=yescrypt', '--stdin'" not in identity or "user + ':!' + hashed" not in identity
            or "'locked': True" not in identity or "'shell': '/usr/sbin/nologin'" not in identity):
        raise ValueError('designated DNS account loses locked native private-stdin setup')
    configure = ast.get_source_segment(sources[control], definitions[control]['configure_dns']) or ''
    if "set(private) != {'dns_ownership', 'recursion_cidrs'}" not in configure:
        raise ValueError('DNS maintenance introduces another initial secret input channel')
    cipher = ast.get_source_segment(sources[control], definitions[control]['backup_cipher']) or ''
    decrypt = ast.get_source_segment(sources[control], definitions[control]['decrypted_backup']) or ''
    for contract in ('Scrypt(salt=salt, length=32, n=32768, r=8, p=1)',
                     'modes.GCM(nonce, tag)', 'authenticate_additional_data(header)'):
        if contract not in cipher:
            raise ValueError('DNS encrypted backup loses its fixed authenticated format: ' + contract)
    if 'context.finalize()' not in decrypt or decrypt.index('context.finalize()') >= decrypt.index('yield plain'):
        raise ValueError('DNS restore must authenticate before archive parsing')
    work = sources[workload]
    for contract in ("'listen': 'unix:' + str(MANAGEMENT)", "'mode': '0600'", 'socket.SO_PEERCRED',
                     "'private/web-configuration.json'", "'state': 'configuring'", 'def web_credentials(self):',
                     'DNS guest transition may have changed; native and web journals retained'):
        if contract not in work:
            raise ValueError('private DNS management loses its identity or uncertainty boundary: ' + contract)
    if "'listen': 'tcp:" in work:
        raise ValueError('private DNS management must not expose a host TCP listener')
    counts['server_protected_capture_equivalence'] = 5
    counts['installer_only_runner_enrollment'] = 2
    counts['technitium_private_credential_fields'] = 6
    counts['technitium_authenticated_backup_format'] = 3


def check_codex_installer_arguments(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Compare the desktop/session/helper argv as data, without target execution."""
    inputs = (
        DEBIAN_ROOT / 'scripts/desktop/labwc.sh',
        DEBIAN_ROOT / 'scripts/late/codex-installer-session.py',
        TARGET_ROOT / 'usr/local/bin/desktop/codex-standalone-install',
    )
    if not set(inputs).intersection(paths):
        return
    desktop, session, helper = map(_read_text, inputs)
    call = re.search(r'\bpython3[ \t]+(?="\$session_helper")', desktop)
    arguments = _shell_invocation_arguments(desktop, call.end()) if call else None
    guards = [node for node in ast.walk(ast.parse(session))
              if isinstance(node, ast.Compare) and len(node.ops) == 1
              and isinstance(node.ops[0], ast.NotEq)
              and isinstance(node.left, ast.Call) and isinstance(node.left.func, ast.Name)
              and node.left.func.id == 'len' and len(node.left.args) == 1
              and isinstance(node.left.args[0], ast.Name) and node.left.args[0].id == 'argv'
              and isinstance(node.comparators[0], ast.Constant)
              and type(node.comparators[0].value) is int]
    helper_guard = re.search(r'\[ "\$#" -eq ([0-9]+) \]', helper)
    if (arguments is None or len(guards) != 1 or helper_guard is None
            or len(arguments) != guards[0].comparators[0].value
            or len(arguments) - 3 != int(helper_guard[1])):
        errors.append('Codex desktop/session/standalone helper argument counts disagree')
        return
    counts['codex_installer_argument_boundaries'] = 2


def check_codex_and_private_git(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Inspect account/credential boundaries as source, without managed imports."""
    inputs = (
        ROOT / 'tools/class_compiler.py', DEBIAN_ROOT / 'scripts/common/resolve-plan.awk',
        DEBIAN_ROOT / 'scripts/common/ssh.sh', DEBIAN_ROOT / 'scripts/late/ssh/ssh-install.py',
        DEBIAN_ROOT / 'scripts/late/codex.sh.tmpl', DEBIAN_ROOT / 'scripts/server/setup.py.tmpl',
        DEBIAN_ROOT / 'scripts/desktop/components/user-config.sh',
        TARGET_ROOT / 'usr/local/bin/server/codex.tmpl',
    )
    if not set(inputs).intersection(paths):
        return
    compiler, resolver, ssh, helper, provision, server, desktop, launcher = map(_read_text, inputs)
    tree = ast.parse(compiler)
    choices = [node.value for node in ast.walk(tree) if isinstance(node, ast.Assign)
               and any(isinstance(target, ast.Name) and target.id == 'codex_enabled' for target in node.targets)]
    if len(choices) != 1 or not isinstance(choices[0], ast.BoolOp) or not isinstance(choices[0].op, ast.Or):
        raise ValueError('DevOps Codex ownership must be independent of CODEX_ONLY_ENABLE')
    role_ids = {node.value for node in ast.walk(choices[0]) if isinstance(node, ast.Constant) and isinstance(node.value, str)}
    if not {'role/desktop/medium', 'role/desktop/full', 'role/server/devops'} <= role_ids:
        raise ValueError('Codex native role owners are incomplete')
    if ('codex_enabled=(family=="server" && profile_codex_only=="true") || ("role/server/devops" in selected)'
            not in resolver or '("role/desktop/medium" in selected)' not in resolver
            or '("role/desktop/full" in selected)' not in resolver
            or 'codex_only_enable' not in resolver
            or 'ref!="fragments/codex.cfg"' not in resolver):
        raise ValueError('d-i resolver does not preserve independent DevOps Codex selection')
    for source in (compiler, _read_text(ROOT / 'tools/source_layout.py')):
        if 'shared-hosting.env' in source or 'hosts/profiles/shared.env' not in source:
            raise ValueError('profile consumers disagree about common policy ownership')
    if (DEBIAN_ROOT / 'hosts/profiles/shared-hosting.env').exists():
        raise ValueError('retired shared-hosting profile remains a competing owner')
    for name in ('desktop/shared-de.env', 'server/shared-srv.env'):
        source = _read_text(DEBIAN_ROOT / 'hosts/profiles' / name)
        if re.search(r'^DEVOPS_CODEX_TOOLS_ENABLE=', source, re.M):
            raise ValueError('retired server Codex flag remains in family defaults')
    helper_tree = ast.parse(helper)
    functions = {node.name: ast.get_source_segment(helper, node) or ''
                 for node in helper_tree.body if isinstance(node, ast.FunctionDef)}
    for function in ('clone_obsidian', 'clone_netscape'):
        if 'clone_desktop_repository(account, home, stage, agent_env, policy)' not in functions[function]:
            raise ValueError('desktop private clones do not share their pinned publication boundary')
    copy = functions['copy_private_checkout']
    for value in ('os.scandir(source)', 'budget[0] -= 1', 'budget[1] -= info.st_size',
                  'remaining -= len(block)', 'os.O_NOFOLLOW', 'os.fsync(destination)'):
        if value not in copy:
            raise ValueError('private Git checkout copy loses its bounded identity contract: ' + value)
    if ('publication_uncertain = True' not in functions['clone_desktop_repository']
            or 'publication_stage_ready and not publication_uncertain' not in functions['clone_desktop_repository']):
        raise ValueError('private checkout loses retained evidence after uncertain publication')
    for value in ('clone-obsidian:desktop|clone-netscape:desktop',
                  'installer_cmdline_password_value git_ssh_passphrase', 'preseed_env_check_file /git_ed25519',
                  'preseed_env_check_file /git_ed25519.pub', 'printf \'%s\' "$secret" | chroot',
                  '"$saved_status" -eq 76'):
        if value not in ssh:
            raise ValueError('initrd private Git credential boundary is incomplete: ' + value)
    for function in ('desktop_install_obsidian_repository', 'desktop_install_browser_repository'):
        body = desktop.split(function + '() {', 1)[1].split('\n}', 1)[0]
        if 'installer_tools_class_selected' in body or 'installer_fatal_status "$desktop_clone_status"' not in body:
            raise ValueError('all-desktop private cloning loses tier or outcome ownership')
    if (not any(value in provision for value in (
            'ACCOUNT_USERNAME=$(installer_preseed_env_value primary_user)',
            'ACCOUNT_USERNAME=$(installer_cmdline_value primary_user)'))
            or 'hooks/target/usr/local/bin/server/codex.tmpl' not in provision
            or 'getent group devops' not in provision):
        raise ValueError('Codex does not provision the explicit primary account and shared storage group')
    for value in ("'--password', '!'", "'/usr/sbin/nologin'", 'service identity has supplementary access',
                  "operator_profile(account, '99-codex-srv.sh')", "operator_profile(account, '71-devops-srv.sh')"):
        if value not in server:
            raise ValueError('server service/operator account separation is incomplete: ' + value)
    if any(value in launcher for value in ('labwc_managed_app', 'SSH_AUTH_SOCK', 'DOCKER_HOST=', 'CONTAINER_HOST=')):
        raise ValueError('headless Codex imports desktop or runner authority')
    for value in ("uid == 0", "'--unshare-all'", "'--cap-drop', 'ALL'", "'--ro-bind-data'",
                  'resolver_snapshot()', 'os.execve(BWRAP, command, environment)'):
        if value not in launcher:
            raise ValueError('headless Codex loses its non-root namespace/resolver contract: ' + value)
    backend = _read_text(TARGET_ROOT / 'etc/systemd/server/user/codex-app-server.service')
    if 'rsyslog-app-run' in backend or 'ExecStart=__INSTALLER_DEVOPS_CODEX_WRAPPER_PATH__ app-server ' not in backend:
        raise ValueError('headless Codex backend depends on the desktop log supervisor')
    counts['codex_profile_and_role_contracts'] = 2
    counts['desktop_private_git_clones'] = 2
    counts['server_distinct_runner_identities'] = 2


def check_server_podman_ownership(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Keep server Podman identities and persistent paths in shared-srv.env."""
    profile_root = DEBIAN_ROOT / 'hosts/profiles'
    watched = [profile_root / 'server/shared-srv.env', DEBIAN_ROOT / 'repo.env',
               ROOT / 'tools/class_compiler.py',
               DEBIAN_ROOT / 'scripts/server/setup.py.tmpl',
               TARGET_ROOT / 'etc/skel-server/.profile.d/71-devops-srv.sh',
               TARGET_ROOT / 'etc/systemd/server/system/ci-github.service.tmpl',
               TARGET_ROOT / 'etc/systemd/server/system/ci-gitlab.service.tmpl']
    if not set(watched).intersection(paths):
        return
    shared = _read_text(profile_root / 'server/shared-srv.env')
    roots = _repository_selector_values()
    runner_source = roots['DIR_TARGET_BIN_SERVER'] + '/ci-runners'
    foundation = _read_text(DEBIAN_ROOT / 'scripts/server/foundation.sh')
    if 'installer_stage_profile_file ' + runner_source + ' ' not in foundation:
        raise ValueError('server foundation must publish its explicit runner source member')
    if any((TARGET_ROOT / ('usr/local/bin/' + family + '/ci-runners')).exists()
           for family in ('common', 'desktop')):
        raise ValueError('server-only runner control command leaked into another source family')
    if not (TARGET_ROOT / 'usr/local/bin/server/ci-runners').is_file():
        raise ValueError('server-only runner control command is missing from the server source tree')
    keys = (
        'PODMAN_ROOTLESS_STATE_BASE', 'PODMAN_GITHUB_STORAGE_DRIVER',
        'PODMAN_GITHUB_GRAPHROOT', 'PODMAN_GITHUB_RUNROOT',
        'PODMAN_GITHUB_IMAGE_COPY_TMP_DIR', 'PODMAN_GITLAB_STORAGE_DRIVER',
        'PODMAN_GITLAB_GRAPHROOT', 'PODMAN_GITLAB_RUNROOT',
        'PODMAN_GITLAB_IMAGE_COPY_TMP_DIR', 'PODMAN_DEVOPS_STORAGE_DRIVER',
        'PODMAN_DEVOPS_GRAPHROOT_ROOT', 'PODMAN_DEVOPS_GRAPHROOT_SUBDIR',
        'PODMAN_DEVOPS_RUNROOT_BASE', 'PODMAN_DEVOPS_IMAGE_COPY_TMP_ROOT',
        'PODMAN_DEVOPS_IMAGE_COPY_TMP_SUBDIR', 'PODMAN_SERVICE_CPU_WEIGHT',
        'PODMAN_SERVICE_IO_WEIGHT', 'PODMAN_SERVICE_TASKS_MAX',
        'PODMAN_SERVICE_MEMORY_HIGH', 'PODMAN_SERVICE_MEMORY_MAX',
        'PODMAN_GITHUB_USER', 'PODMAN_GITHUB_GROUP', 'PODMAN_GITHUB_RUNTIME_DIR',
        'PODMAN_GITHUB_SOCKET', 'PODMAN_GITLAB_USER', 'PODMAN_GITLAB_GROUP',
        'PODMAN_GITLAB_RUNTIME_DIR', 'PODMAN_GITLAB_SOCKET', 'PODMAN_DEVOPS_USER',
        'PODMAN_DEVOPS_GROUP',
        'CI_RUNNER_CPU_WEIGHT', 'CI_RUNNER_IO_WEIGHT', 'CI_RUNNER_TASKS_MAX',
        'CI_RUNNER_MEMORY_HIGH', 'CI_RUNNER_MEMORY_MAX',
    )
    for key in keys:
        if not re.search(r'^' + key + r'=', shared, re.M):
            raise ValueError('server shared-srv.env lacks Podman/runner default: ' + key)
    for profile in sorted((profile_root / 'server').glob('*.env')):
        if profile.name == 'shared-srv.env':
            continue
        source = _read_text(profile)
        for key in keys:
            if re.search(r'^' + key + r'=', source, re.M):
                raise ValueError('concrete server profile duplicates shared Podman policy: ' + profile.name + ':' + key)
    for provider in ('GITHUB', 'GITLAB'):
        unit = _read_text(TARGET_ROOT / ('etc/systemd/server/system/ci-' + provider.lower() + '.service.tmpl'))
        suffixes = ('USER', 'GROUP', 'RUNTIME_DIR', 'SOCKET') if provider == 'GITHUB' else ('USER', 'GROUP', 'RUNTIME_DIR')
        for suffix in suffixes:
            token = '__INSTALLER_PODMAN_' + provider + '_' + suffix + '__'
            if token not in unit:
                raise ValueError('runner service account is not rendered from shared Podman policy: ' + token)
    if '/pool/build' in shared and re.search(r'^PODMAN_[A-Z0-9_]+=', shared, re.M):
        raise ValueError('server Podman policy points at the compilation pool')
    counts['server_podman_shared_policy'] = len(keys)


def check_server_ai_profile_ownership(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Keep Whisper/Llama release policy in paired concrete profiles only."""
    profile_root = DEBIAN_ROOT / 'hosts/profiles'
    watched = [profile_root / 'server/shared-srv.env', profile_root / 'desktop/btrfs-de-flex-duo.env',
               profile_root / 'desktop/btrfs-de-flex.env', profile_root / 'desktop/f2fs-de-hp14.env',
               profile_root / 'server/btrfs-srv-flex-duo.env', profile_root / 'server/btrfs-srv-flex.env',
               profile_root / 'server/f2fs-srv-hp14.env', ROOT / 'tools/class_compiler.py']
    if not set(watched).intersection(paths):
        return
    shared = _read_text(profile_root / 'server/shared-srv.env')
    if re.search(r'^(?:WHISPER|LLAMA)_', shared, re.M):
        raise ValueError('server shared-srv.env must not own Whisper/Llama policy')
    pairs = {
        'btrfs-srv-flex-duo.env': 'btrfs-de-flex-duo.env',
        'btrfs-srv-flex.env': 'btrfs-de-flex.env',
        'f2fs-srv-hp14.env': 'f2fs-de-hp14.env',
    }
    for server_name, desktop_name in pairs.items():
        server = _read_text(profile_root / 'server' / server_name)
        desktop = _read_text(profile_root / 'desktop' / desktop_name)
        server_ai = [line for line in server.splitlines()
                     if line.startswith(('WHISPER_', 'LLAMA_')) and not line.startswith(('WHISPER_ENABLE=', 'LLAMA_ENABLE='))]
        desktop_ai = [line for line in desktop.splitlines() if line.startswith(('WHISPER_', 'LLAMA_'))]
        if server_ai != desktop_ai:
            raise ValueError('server AI policy differs from paired desktop profile: ' + server_name)
    compiler = _read_text(ROOT / 'tools/class_compiler.py')
    if "'whisper': 'WHISPER_CLI'" in compiler or "'whisper-model': 'WHISPER_MODEL'" in compiler:
        raise ValueError('server artifact compiler still owns obsolete shared Whisper artifacts')
    counts['paired_server_ai_profiles'] = len(pairs)


def check_build_capture(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Inspect generation authority as AST; never import the serializer."""
    owners = {'Makefile', 'tools/build.py', 'tools/class_compiler.py', 'tools/publication.py', 'tools/release_pointer.py'}
    if not any(path.relative_to(ROOT).as_posix() in owners for path in paths):
        return
    builder = ast.parse(_read_text(ROOT / 'tools/build.py'), filename='tools/build.py')
    functions = {node.name: node for node in builder.body if isinstance(node, ast.FunctionDef)}
    captures = [node for node in builder.body if isinstance(node, ast.ClassDef) and node.name == 'SourceCapture']
    if len(captures) != 1 or not {'build', 'serialize', 'generate_preseed'} <= functions.keys():
        raise ValueError('generation requires one source capture and one byte serializer')
    forbidden = {'system', 'popen', 'Popen', 'run', 'call', 'check_call', 'check_output'}
    allowed_imports = {'__future__', 'collections', 'fcntl', 'gzip', 'hashlib', 'io', 'ipaddress',
                       'itertools', 'json', 'os', 'pathlib', 're', 'shlex', 'stat', 'sys',
                       'tarfile', 'tempfile', 'urllib.parse', 'class_compiler', 'publication'}
    for name in ('build.py', 'class_compiler.py', 'publication.py'):
        tree = ast.parse(_read_text(ROOT / 'tools' / name), filename=name)
        for node in ast.walk(tree):
            imports = ([alias.name for alias in node.names] if isinstance(node, ast.Import)
                       else [node.module] if isinstance(node, ast.ImportFrom) else [])
            if any(module not in allowed_imports for module in imports):
                raise ValueError('generation imports an unreviewed execution path: ' + name)
            if isinstance(node, ast.Call):
                called = node.func.id if isinstance(node.func, ast.Name) else (
                    node.func.attr if isinstance(node.func, ast.Attribute) else '')
                if called in forbidden or (isinstance(node.func, ast.Name)
                        and called in {'eval', 'exec', 'compile', '__import__'}):
                    raise ValueError('generation path contains executable discovery: ' + name + '/' + called)
    for name in ('serialize', 'generate_preseed'):
        for node in ast.walk(functions[name]):
            if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                    and isinstance(node.func.value, ast.Name) and node.func.value.id == 'tarfile'
                    and node.func.attr == 'open' and any(key.arg == 'fileobj' for key in node.keywords)):
                continue  # The sole archive writer consumes an in-memory buffer.
            if isinstance(node, ast.Call) and ((isinstance(node.func, ast.Attribute)
                    and node.func.attr in {'open', 'read_text', 'read_bytes', 'stat', 'lstat', 'walk', 'rglob'})
                    or (isinstance(node.func, ast.Name) and node.func.id == 'open')):
                raise ValueError('serializer must consume captured bytes: ' + name)
    steps = functions['build'].body
    if (len(steps) != 1 or not isinstance(steps[0], ast.With)
            or len(steps[0].items) != 1
            or not isinstance(steps[0].items[0].context_expr, ast.Call)
            or not isinstance(steps[0].items[0].context_expr.func, ast.Name)
            or steps[0].items[0].context_expr.func.id != 'SourceCapture'):
        raise ValueError('build must retain source ownership through serialization')
    body = steps[0].body
    if (len(body) < 3 or not isinstance(body[-1], ast.Return)
            or not isinstance(body[-2], ast.Expr) or not isinstance(body[-2].value, ast.Call)
            or not isinstance(body[-2].value.func, ast.Attribute)
            or body[-2].value.func.attr != 'verify'):
        raise ValueError('complete source membership must be checked before publication')
    capture_source = ast.get_source_segment(_read_text(ROOT / 'tools/build.py'), captures[0]) or ''
    for interface in ('os.O_PATH', 'os.O_NOFOLLOW', 'os.O_DIRECTORY', 'os.fstat', 'os.scandir',
                      'SOURCE_ENTRY_LIMIT', 'SOURCE_MEMBER_LIMIT', 'SOURCE_BYTE_LIMIT', 'SOURCE_FILE_LIMIT'):
        if interface not in capture_source:
            raise ValueError('source capture lacks its bounded identity interface: ' + interface)
    for node in ast.walk(captures[0]):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr in {
                'read_text', 'read_bytes', 'rglob', 'walk', 'listdir'}:
            raise ValueError('source capture must not reopen or enumerate inputs by pathname')
    counts['generation_source_capture_contracts'] = 1
    counts['generation_pure_modules'] = 3
    main_source = ast.get_source_segment(_read_text(ROOT / 'tools/build.py'), functions['main']) or ''
    for contract in ("with BuildOwnership(ROOT / 'd-i'):",
                     "atomic_write(ROOT / 'd-i' / suite / name, data, 0o644)",
                     "{'forky/preseed.cfg', 'trixie/preseed.cfg'}"):
        if contract not in main_source:
            raise ValueError('flat suite generation loses output ownership: ' + contract)
    if any(value in main_source for value in ('publish_immutable_tree', '/releases', '/publications', "'releases'", "'publications'")):
        raise ValueError('make build must overwrite flat suite files only')
    counts['generation_flat_suite_output_contracts'] = 2
    publication_source = _read_text(ROOT / 'tools/publication.py')
    publication = ast.parse(publication_source, filename='tools/publication.py')
    publication_functions = {node.name: node for node in publication.body if isinstance(node, ast.FunctionDef)}
    if not {'atomic_write', 'publish_immutable_tree', '_products', '_verify_tree',
            '_verify_file', '_atomic_write_at'} <= publication_functions.keys():
        raise ValueError('publication lacks a bounded immutable-candidate boundary')
    for node in ast.walk(publication):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if node.func.attr in {'read_bytes', 'read_text', 'walk', 'rglob', 'listdir', 'mkdtemp', 'mkstemp', 'resolve'}:
            raise ValueError('publication must not reopen or enumerate paths through a mutable ancestor')
        if not isinstance(node.func.value, ast.Name) or node.func.value.id != 'os':
            continue
        keys = {key.arg: key.value for key in node.keywords}
        if node.func.attr in {'mkdir', 'stat', 'unlink'} and 'dir_fd' not in keys:
            raise ValueError('publication mutation or metadata lookup lacks its pinned parent')
        if node.func.attr == 'stat' and not (
                isinstance(keys.get('follow_symlinks'), ast.Constant)
                and keys['follow_symlinks'].value is False):
            raise ValueError('publication metadata lookup may follow a replaced link')
        if node.func.attr in {'rename', 'replace'} and not {'src_dir_fd', 'dst_dir_fd'} <= keys.keys():
            raise ValueError('publication rename crosses a mutable pathname boundary')
        if node.func.attr == 'open' and 'dir_fd' not in keys:
            first = node.args[0] if node.args else None
            root = isinstance(first, ast.Constant) and first.value == '/'
            pinned = (isinstance(first, ast.JoinedStr) and len(first.values) == 2
                      and isinstance(first.values[0], ast.Constant)
                      and first.values[0].value == '/proc/self/fd/'
                      and isinstance(first.values[1], ast.FormattedValue)
                      and isinstance(first.values[1].value, ast.Name)
                      and first.values[1].value.id == 'pinned')
            if not root and not pinned:
                raise ValueError('publication opens content through a mutable absolute pathname')
    required = ('MEMBER_LIMIT', 'ENTRY_LIMIT', 'BYTE_LIMIT', 'FILE_LIMIT', 'PATH_LIMIT', 'DEPTH_LIMIT',
                'os.O_PATH', 'os.O_NOFOLLOW', 'os.O_DIRECTORY', 'os.scandir(descriptor)',
                'fcntl.LOCK_EX | fcntl.LOCK_NB', 'PublicationOutcomeUnknown',
                "inspect(root, '', content=False) != identities", 'os.fchmod(descriptor, 0o755)',
                'os.fchmod(root, 0o755)', 'os.fchmod(root, 0o700)')
    if any(item not in publication_source for item in required):
        raise ValueError('publication loses bounded capture, writer ownership or recovery evidence')
    body = publication_functions['publish_immutable_tree'].body
    product_validation = next((index for index, node in enumerate(body)
                               if isinstance(node, ast.Assign) and isinstance(node.value, ast.Call)
                               and isinstance(node.value.func, ast.Name) and node.value.func.id == '_products'), None)
    first_mutation = next((index for index, node in enumerate(body) if isinstance(node, ast.With)), None)
    if product_validation is None or first_mutation is None or product_validation >= first_mutation:
        raise ValueError('publication must validate the complete candidate before creating output paths')
    counts['generation_publication_descriptor_contracts'] = 1
    counts['generation_publication_recovery_contracts'] = 1
    for name in ('build.py', 'release_pointer.py'):
        tree = ast.parse(_read_text(ROOT / 'tools' / name), filename=name)
        handlers = [node for node in ast.walk(tree) if isinstance(node, ast.ExceptHandler)
                    and isinstance(node.type, ast.Name) and node.type.id == 'PublicationOutcomeUnknown']
        if (len(handlers) != 1 or not any(isinstance(node, ast.Return)
                and isinstance(node.value, ast.Constant) and node.value.value == 75
                for node in ast.walk(handlers[0]))):
            raise ValueError('publication caller collapses an uncertain mutation into ordinary failure: ' + name)
    counts['publication_uncertain_result_adapters'] = 2


def check_release_equality(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Compare both flat suite products with current source as data only."""
    relevant = any(path.is_relative_to(DEBIAN_ROOT) or path.is_relative_to(ROOT / 'd-i/forky')
                   or path.is_relative_to(ROOT / 'd-i/trixie') or path.name == 'build.py'
                   or path.relative_to(ROOT).as_posix() in {'Makefile', 'tools/class_compiler.py', 'tools/publication.py', '.gitignore'}
                   for path in paths)
    if not relevant:
        return
    product_names = {'payload.tar.gz', 'payload.manifest', 'source.sh',
                     'receipt.json', 'support-matrix.json'}
    ignored_products = {'/d-i/debian/releases/', '/d-i/debian/publications/'}
    if not ignored_products <= set(_read_text(ROOT / '.gitignore').splitlines()):
        raise ValueError('local build-product roots must be explicitly ignored')
    if BASELINE_ZIP is None:
        tracked_products = _run(['git', 'ls-files', '-z', '--',
                                 *(name.removeprefix('/').removesuffix('/')
                                   for name in sorted(ignored_products))])
        if tracked_products.returncode or tracked_products.stdout:
            raise ValueError('generated release/publication products must not be tracked')
    else:
        # Archive snapshots carry no tracking state. Flat source/publication
        # ownership is still checked below; Git whitespace checks use no-index.
        counts['archive_baseline_without_git_tracking'] = 1
    counts['ignored_build_product_roots'] = len(ignored_products)
    suite_products = [f'd-i/{suite}/{name}' for suite in ('forky', 'trixie')
                      for name in product_names]
    if BASELINE_ZIP is None:
        ignored_suite_products = _run(['git', 'check-ignore', '--', *suite_products])
        if ignored_suite_products.returncode not in (0, 1) or ignored_suite_products.stdout:
            raise ValueError('suite build products must remain visible to Git')
    for suite in ('forky', 'trixie'):
        if (ROOT / 'd-i' / suite / 'releases').exists():
            raise ValueError('suite build products must be flat; releases directory is not allowed')
    def member_name(name):
        if (not isinstance(name, str) or not name or len(name) > 240 or name.startswith('/')
                or any(part in ('', '.', '..') for part in name.split('/'))
                or re.fullmatch(r'[A-Za-z0-9_./@+ -]+', name) is None):
            raise ValueError('noncanonical release member path')
        return name
    def read(path, maximum=16777216):
        # Never follow a changed artifact or receipt path to host data.
        relative = path.relative_to(ROOT)
        current = ROOT
        for part in relative.parts:
            current /= part
            if current.is_symlink():
                raise ValueError('symlink in release/source input ancestry')
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
        with os.fdopen(descriptor, 'rb') as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_size > maximum:
                raise ValueError('release/source byte bound exceeded')
            data = stream.read(maximum + 1)
            if len(data) != info.st_size or len(data) > maximum:
                raise ValueError('release/source changed during comparison')
            return data
    digest = lambda data: hashlib.sha256(data).hexdigest()
    release_ids, preseeds = set(), {}
    for suite in ('forky', 'trixie'):
        preseed = read(ROOT / 'd-i' / suite / 'preseed.cfg')
        ids = set(re.findall(rb'INSTALLER_RELEASE_ID=([0-9a-f]{64})', preseed))
        if len(ids) != 1:
            raise ValueError('frontend must bind exactly one immutable release: ' + suite)
        release_ids.update(ids)
        preseeds[suite] = preseed
    if len(release_ids) != 1:
        raise ValueError('the two frontends select different releases')
    release_id = release_ids.pop().decode()
    release = ROOT / 'd-i/forky'
    receipt_bytes = read(release / 'receipt.json')
    receipt = json.loads(receipt_bytes)
    if receipt.get('format') != 1 or receipt.get('release') != release_id or receipt.get('suites') != ['forky', 'trixie']:
        raise ValueError('release receipt identity differs')
    if set(receipt['products']) != {'payload.tar.gz','payload.manifest','source.sh','support-matrix.json'}:
        raise ValueError('release product vocabulary differs')
    products = {name: read(release / name, 67108864) for name in receipt['products']}
    for name, data in products.items():
        if Path(name).name != name or digest(data) != receipt['products'][name]:
            raise ValueError('release product differs from its receipt: ' + name)
    manifest = products['payload.manifest'].decode().splitlines()
    if not manifest or manifest[0] != 'format=3':
        raise ValueError('unsupported current member manifest')
    expected = {}
    for line in manifest[1:]:
        size, sha256, name = line.split('\t')
        if name in expected or not size.isdecimal() or re.fullmatch('[0-9a-f]{64}', sha256) is None:
            raise ValueError('duplicate or malformed manifest member')
        expected[member_name(name)] = (int(size), sha256)
    members, total = {}, 0
    with tarfile.open(fileobj=io.BytesIO(products['payload.tar.gz']), mode='r:gz') as archive:
        for member in archive:
            total += member.size
            if (not member.isfile() or member.name in members or member.name not in expected
                    or member.mode != 0o644 or member.uid or member.gid or member.mtime
                    or len(members) >= 10000 or member.size > 16777216 or total > 268435456):
                raise ValueError('current payload has an unsafe or unexpected member')
            stream = archive.extractfile(member)
            if stream is None:
                raise ValueError('current payload member has no bytes')
            data = stream.read(member.size + 1)
            if (len(data), digest(data)) != expected[member.name]:
                raise ValueError('payload/member manifest differs: ' + member.name)
            members[member.name] = data
    if set(expected) != set(members) or receipt['members'] != len(members):
        raise ValueError('payload membership differs from its complete manifest')
    # Simulated rendering must not invent fields that the real shared renderer
    # never emits. Read the actual serializer's fixed map as source data.
    runtime_map = {key for key, _ in _runtime_path_schema_rows(members['catalog/runtime-paths.tsv'].decode())
                   if key.startswith('PATH_')}
    used_runtime_fields = set()
    for name, data in members.items():
        if name.startswith('frontends/') and _custom_apt_input(ROOT / 'd-i' / name.removeprefix('frontends/')):
            continue
        used_runtime_fields.update(token.decode() for token in re.findall(rb'__INSTALLER_(PATH_[A-Z][A-Z0-9_]*)__', data))
    if used_runtime_fields - runtime_map:
        raise ValueError('target placeholder has no real publication-map producer: '
                         + ', '.join(sorted(used_runtime_fields - runtime_map)))
    counts['runtime_placeholder_producers'] = len(used_runtime_fields)
    runtime_source = members['hosts/installer/runtime.env'].decode()
    dropins = re.findall(r'^(DIR_SYSTEMD_(SYSTEM|USER)_[A-Z0-9_]+_DROPIN)="\$\{DIR_SYSTEMD_\2\}/([^"/]+\.d)"$',
                         runtime_source, re.M)
    dropin_paths = {(scope.lower(), unit): key for key, scope, unit in dropins}
    if len(dropin_paths) != len(dropins) or ('system', 'nftables.service.d') not in dropin_paths:
        raise ValueError('systemd drop-in directories have duplicate or missing canonical owners')
    for key, _, _ in dropins:
        if 'PATH_' + key not in runtime_map:
            raise ValueError('systemd drop-in has no real placeholder producer: ' + key)
    inline_dropin = re.compile(r'(?:__INSTALLER_PATH_DIR_(?:SYSTEMD_(?:SYSTEM|USER)|SYSTEMD_ETC|ETC)__/|\$\{DIR_SYSTEMD_(?:SYSTEM|USER)\}/|/etc/systemd/)(?:(?:systemd/)?(?:system|user)/)?[A-Za-z0-9@_.:-]+\.(?:service|socket|mount|slice|target|timer|scope|path)\.d(?:/|["\x27])')
    dynamic_dropin = re.compile(r'(?:__INSTALLER_PATH_DIR_(?:SYSTEMD_(?:SYSTEM|USER)|SYSTEMD_ETC|ETC)__/|\$\{DIR_SYSTEMD_(?:SYSTEM|USER)\}/|/etc/systemd/)(?:(?:systemd/)?(?:system|user)/)?(?:[A-Za-z0-9@_.:-]*\$\{[A-Za-z_][A-Za-z0-9_]*\})+[A-Za-z0-9@_.:-]*\.d(?:/|["\x27])')
    # Native numeric-UID instance names have no fixed directory to publish.
    # Permit only these four exact negative file assertions in firstboot;
    # the same spellings in an assignment, command or staging call still fail.
    native_instance_absence = re.compile(r'\s*\[ ! -(?:e|L) "__INSTALLER_PATH_DIR_SYSTEMD_SYSTEM__/(?:user@\$\{uid\}\.service|user-\$\{uid\}\.slice)\.d/50-podman-devops\.conf" \]\s*')
    native_instance_checks = 0
    for name, data in members.items():
        unit = re.fullmatch(r'hooks/target/etc/systemd/[^/]+/(system|user)/([^/]+\.d)/.+', name)
        if unit and (unit[1], unit[2]) not in dropin_paths:
            raise ValueError('published unit drop-in lacks a canonical runtime directory: ' + name)
        text = data.decode('utf-8', errors='replace')
        if name.startswith(('scripts/', 'hooks/target/')):
            if inline_dropin.search(text):
                raise ValueError('fixed target unit drop-in reconstructs its directory: ' + name)
            for line in text.splitlines():
                if not dynamic_dropin.search(line):
                    continue
                if name == 'scripts/firstboot/04-validation.sh.tmpl' and native_instance_absence.fullmatch(line):
                    native_instance_checks += 1
                    continue
                raise ValueError('dynamic target unit drop-in bypasses its canonical map: ' + name)
    counts['canonical_systemd_dropin_directories'] = len(dropins)
    counts['native_systemd_instance_absence_checks'] = native_instance_checks
    for name, expected_sha in receipt['source_inputs'].items():
        member_name(name)
        physical = (ROOT / 'd-i' / name.removeprefix('frontends/')) if name.startswith('frontends/') else DEBIAN_ROOT / name
        data = read(physical)
        if digest(data) != expected_sha:
            raise ValueError('current source differs from selected release: ' + name)
        if members.get(name) != data:
            raise ValueError('payload member differs from current source: ' + name)
    for name, expected_sha in receipt['compiler_inputs'].items():
        member_name(name)
        if digest(read(ROOT / name)) != expected_sha:
            raise ValueError('compiler input differs from selected release: ' + name)
    if set(receipt['compiler_inputs']) != {'Makefile', 'tools/build.py', 'tools/class_compiler.py', 'tools/publication.py'}:
        raise ValueError('compiler input ownership differs')
    source_names = set(receipt['source_inputs'])
    for path in paths:
        if path.is_relative_to(DEBIAN_ROOT):
            name = path.relative_to(DEBIAN_ROOT).as_posix()
            parts = Path(name).parts
            if any(part in {'tests','__pycache__','.git','.pytest_cache','releases','publications'} for part in parts):
                continue
            if path.name in {'AGENTS.md','AGENTS.override.md','preseed.env','git_ed25519','git_ed25519.pub','id_git_ed25519'}:
                continue
            # Match SourceCapture.DEVELOPMENT_ONLY_MEMBERS exactly. The full
            # checkout validator still reads this JSON; runtime uses its TSV.
            if name == 'catalog/placeholder-registry.json':
                continue
            if name not in source_names:
                raise ValueError('changed shared source was not captured: ' + name)
    for name, expected_sha in receipt['frontends'].items():
        member_name(name)
        if name.split('/')[0] not in ('forky','trixie'):
            raise ValueError('unknown frontend owner')
        data = read(ROOT / 'd-i' / name)
        if digest(data) != expected_sha:
            raise ValueError('frontend differs from captured source identity: ' + name)
    for suite in ('forky', 'trixie'):
        for name, data in {**products, 'receipt.json': receipt_bytes}.items():
            if read(ROOT / 'd-i' / suite / name, 67108864) != data:
                raise ValueError('suite products differ: ' + suite + '/' + name)
    counts['suite_product_copies'] = 2 * len(product_names)
    if products['source.sh'] != members['scripts/common/source.sh']:
        raise ValueError('separate bootstrap differs from its payload member')
    identity_lines = [sha256 + '  source/' + name + '\n' for name, sha256 in sorted(receipt['source_inputs'].items())]
    identity_lines += [sha256 + '  compiler/' + name + '\n' for name, sha256 in sorted(receipt['compiler_inputs'].items())]
    fingerprint = digest(''.join(sorted(identity_lines)).encode())
    if fingerprint != receipt['source_fingerprint']:
        raise ValueError('source/compiler fingerprint differs')
    release_identity = fingerprint + '\n' + ''.join(digest(data) + '  ' + name + '\n'
        for name, data in sorted(members.items()) if name != 'catalog/compiled/release.tsv')
    if digest(release_identity.encode()) != release_id:
        raise ValueError('release identifier differs from source and compiled members')
    for suite, preseed in preseeds.items():
        if b'INSTALLER_SUITE=' + suite.encode() not in preseed:
            raise ValueError('preseed suite binding differs')
        # Trusted preseed pins are compared with actual acquisition bytes by
        # the early transport owner before parsing or executing those bytes.
        for product in ('payload.manifest', 'payload.tar.gz'):
            if digest(products[product]).encode() not in preseed:
                raise ValueError('preseed lacks declared product identity: ' + suite + '/' + product)
        check = (b'source_verify_sha256 "$boot/source.sh" ' + digest(products['source.sh']).encode()
                 + b' "bootstrap source" || exit 1;')
        execute = b'. "$boot/source.sh";'
        if check not in preseed or execute not in preseed or preseed.index(check) > preseed.index(execute):
            raise ValueError('preseed must verify the source helper before executing it: ' + suite)
    # Setup code is payload input, never a permanent installed target program.
    setup_sources = ('scripts/common/network-profile-stage.py.tmpl',
                     'scripts/common/snander-install.py.tmpl', 'scripts/server/setup.py.tmpl',
                     'scripts/late/crypto-bootstrap.py.tmpl',
                     'scripts/desktop/appearance-setup.py',
                     *(f'scripts/desktop/appearance_setup/{module}.py' for module in (
                         '__init__', 'defaults', 'release', 'theme_archive', 'theme_assets',
                         'theme_resources', 'theme_install')))
    if any(name not in members for name in setup_sources):
        raise ValueError('installation-only source program is missing')
    forbidden_setup = ('installer-ssh-authorize.py.tmpl', 'network-profile-stage.py.tmpl', 'snander-install',
                       'crypto-bootstrap.py', 'crypto-bootstrap.py.tmpl',
                       'labwc-appearance-defaults', 'labwc-appearance-themes',
                       'theme_archive.py', 'theme_assets.py', 'theme_resources.py', 'theme_install.py')
    if any(name.startswith('hooks/target/') and name.rsplit('/', 1)[-1] in forbidden_setup for name in members):
        raise ValueError('installation-only helper remains in the persistent target tree')
    runtime_source = members['hooks/target/usr/local/libexec/server/installer-serverctl.py.tmpl'].decode()
    runtime_tree = ast.parse(runtime_source)
    runtime_functions = {node.name for node in runtime_tree.body if isinstance(node, ast.FunctionDef)}
    if runtime_functions & {'foundation', 'foundation_identity', 'account_skeleton', 'devops_account', 'install_profile_packages', 'install'}:
        raise ValueError('persistent server controller retains installation-only operations')
    if b'optional/ssh' in members['catalog/selection.json'] or any(name.endswith('/optional/ssh.cfg') for name in members):
        raise ValueError('retired optional SSH class remains public')
    counts['installation_only_source_programs'] = len(setup_sources)
    for application in ('Tuta', 'Postman', 'Ledger'):
        vendor_path = ('hooks/target/usr/local/lib/common/perl5/site_perl/apt-repo-local/'
                       'APTRepoLocal/Servicing/' + application + '.pm')
        vendor = members[vendor_path].decode()
        if re.search(r'^sub apply\s*\{', vendor, re.M) or 'acquisition requires the native repository publisher' not in vendor:
            raise ValueError('vendor acquisition retains an unused direct publisher: ' + application)
    counts['vendor_native_publisher_guards'] = 3
    constraints = {}
    for line in members['catalog/compiled/class-plan.tsv'].decode().splitlines():
        cells = line.split('\t')
        if cells[0] == 'class':
            constraints[cells[1], cells[2]] = (list(filter(None, cells[3].split(','))),
                                             list(filter(None, cells[4].split(','))))
    registry = configparser.ConfigParser(interpolation=None)
    registry.read_string(members['catalog/compiled/class-registry.conf'].decode())
    for toolkit, driver, other in (('cuda', 'nvidia', 'cuda-legacy'),
                                    ('cuda-legacy', 'nvidia-legacy', 'cuda')):
        wrong_driver = 'nvidia-legacy' if driver == 'nvidia' else 'nvidia'
        rejected = ['optional/' + other, 'optional/' + wrong_driver]
        for suite in ('forky', 'trixie'):
            if constraints.get((suite, 'optional/' + toolkit)) != (['optional/' + driver], rejected):
                raise ValueError('CUDA class loses its corresponding driver requirement/conflict')
        section = registry['class.optional.' + toolkit]
        if section.get('requires_classes') != 'optional/' + driver or section.get('rejected_classes') != ' '.join(rejected):
            raise ValueError('early CUDA selection metadata differs from the frozen plan')
    for driver, other_driver in (('nvidia', 'nvidia-legacy'), ('nvidia-legacy', 'nvidia')):
        for suite in ('forky', 'trixie'):
            if constraints.get((suite, 'optional/' + driver)) != ([], ['optional/' + other_driver]):
                raise ValueError('NVIDIA driver-only selection is not independent of CUDA')
        if registry['class.optional.' + driver].get('requires_classes', ''):
            raise ValueError('early NVIDIA selection unexpectedly requires a toolkit class')
    dispatcher = members['hooks/installer/pre-pkgsel.d/50-class-plan.sh'].decode()
    software = members['scripts/late/software.sh.tmpl'].decode()
    if ('installer_pre_pkgsel_stage_path "$stage_id"' not in dispatcher
            or 'installer_pre_pkgsel_stage_path installer.namespace' not in software
            or '/pre-pkgsel.d/89temporary-unshare' in software):
        raise ValueError('managed software does not reuse the published namespace stage')
    counts['cuda_driver_selection_contracts'] = 8
    counts['temporary_unshare_stage_contracts'] = 1
    matrix = json.loads(products['support-matrix.json'])['tuples']
    roles = ('desktop/base','desktop/medium','desktop/full','server/github-actions',
             'server/gitlab-cicd','server/technitium','server/devops')
    required = {(suite, role, 'amd64', 'btrfs', 'fresh') for suite in ('forky','trixie') for role in roles}
    actual = {(row['suite'],row['role'],row['architecture'],row['filesystem'],row['mode']) for row in matrix}
    if not required <= actual:
        raise ValueError('minimum suite/role plans are incomplete')
    server_roles = ('server/devops','server/github-actions','server/gitlab-cicd','server/technitium')
    for suite in ('forky','trixie'):
        expected_selections = {tuple(role for bit, role in enumerate(server_roles[:-1]) if mask & (1 << bit)) for mask in range(1, 8)}
        expected_selections.add(('server/technitium',))
        generated_selections = {tuple(row['roles']) for row in matrix if row['suite']==suite and row['roles'][0].startswith('server/')}
        if generated_selections != expected_selections:
            raise ValueError('server role combination plans are incomplete')
        for family in ('desktop', 'server'):
            preference = members[f'frontends/{suite}/hooks/target/etc/apt/{family}/preferences.d/x11.pref'].decode()
            required_exclusions = ['xserver-xorg*', 'xvfb',
                    'mesa-vulkan-drivers', 'vulkan-tools', 'vulkan-headers',
                    'nvidia-vulkan-icd', 'Pin: version *', 'Pin-Priority: -1']
            if (suite, family) == ('trixie', 'desktop'):
                forbidden = set(' '.join(re.findall(r'^Package: (.*)$', preference, re.M)).split())
                if forbidden & {'xwayland', 'x11-xkb-utils', 'xserver-common'}:
                    raise ValueError('Trixie desktop blocks a required native compositor/keyboard dependency')
            else:
                required_exclusions += ['xwayland', 'xserver-common']
                if suite == 'forky':
                    required_exclusions += ['x11-xkb-utils']
                elif 'x11-xkb-utils' in set(' '.join(re.findall(r'^Package: (.*)$', preference, re.M)).split()):
                    raise ValueError('Trixie server blocks Timeshift keyboard dependencies')
            if not all(token in preference for token in required_exclusions):
                raise ValueError('suite/family loses its system X.Org or Vulkan exclusion')
            xanmod = members[f'frontends/{suite}/hooks/target/etc/apt/{family}/preferences.d/15-kernel.pref'].decode()
            xanmod_kernel_pin = ('Pin: origin "deb.xanmod.org"\nPin-Priority: 1001' in xanmod or
                                 'Pin: release o=xanmod\nPin-Priority: 1001' in xanmod)
            xanmod_fallback_pin = ('Package: *\nPin: origin "deb.xanmod.org"\nPin-Priority: 100' in xanmod or
                                   'Package: *\nPin: release o=xanmod\nPin-Priority: 100' in xanmod)
            if not (xanmod_kernel_pin and xanmod_fallback_pin):
                raise ValueError('suite/family loses the XanMod repository policy')
            cramerz = members[f'frontends/{suite}/hooks/target/etc/apt/{family}/preferences.d/16-cramerz.pref'].decode()
            if ('home:cramerz:debian/Debian_Unstable' not in cramerz
                    or 'Pin-Priority: -1' not in cramerz):
                raise ValueError('suite/family loses the Cramerz repository policy')
            vendors = members[f'frontends/{suite}/hooks/target/etc/apt/{family}/preferences.d/20-vendors.pref'].decode()
            if ('Pin: origin pkgs.zabbly.com\nPin-Priority: 1001' not in vendors
                    or 'Package: incus incus-base incus-client incus-ui-canonical' not in vendors):
                raise ValueError('suite/family loses the Zabbly Incus repository policy')
            if ('Pin: origin apt.llvm.org\nPin-Priority: 1001' in vendors
                    or 'Pin: origin apt.llvm.org\nPin-Priority: -1' not in vendors):
                raise ValueError('suite/family does not force LLVM and Clang packages to Debian archives')
            family_suite_pref = members[f'frontends/{suite}/hooks/target/etc/apt/{family}/preferences.d/00-suite.pref'].decode()
            snapshot_pin = ('Package: src:llvm-toolchain-snapshot:any\n'
                            'Pin: release o=Debian,a=experimental\nPin-Priority: 1001')
            if snapshot_pin not in family_suite_pref:
                raise ValueError(f'{suite}/{family} blocks transitive LLVM snapshot dependencies from Experimental')
        suite_pref = members[f'frontends/{suite}/hooks/target/etc/apt/desktop/preferences.d/00-suite.pref'].decode()
        fallback_pins = ('Pin: release o=Debian,n=sid\nPin-Priority: 100',
                         'Pin: release o=Debian,a=experimental\nPin-Priority: 1')
        if any(pin not in suite_pref for pin in fallback_pins):
            raise ValueError('class-selected Debian fallback suites remain unavailable to pkgsel')
        experimental_llvm_pin = ('Package: libclang-rt-24-dev\n'
                                 'Pin: release o=Debian,a=experimental\nPin-Priority: 1001')
        blocked_llvm_vendor_pin = ('Package: libclang-rt-24-dev\n'
                                   'Pin: origin apt.llvm.org\nPin-Priority: -1')
        if experimental_llvm_pin not in suite_pref or blocked_llvm_vendor_pin not in suite_pref:
            raise ValueError('libclang-rt-24-dev is not pinned exclusively to Debian Experimental')
        experimental_lldb_pin = ('Package: lldb-24 liblldb-24 python3-lldb-24\n'
                                 'Pin: release o=Debian,a=experimental\nPin-Priority: 1001')
        blocked_lldb_vendor_pin = ('Package: lldb-24 liblldb-24 python3-lldb-24\n'
                                   'Pin: origin apt.llvm.org\nPin-Priority: -1')
        if experimental_lldb_pin not in suite_pref or blocked_lldb_vendor_pin not in suite_pref:
            raise ValueError('LLDB 24 runtime and Python binding are not pinned exclusively to Debian Experimental')
        agent = members[f'frontends/{suite}/hooks/target/etc/apt/desktop/preferences.d/10-hyprpolkitagent.pref'].decode()
        # Both suites use the signed Trixie Backports Qt implementation.  The
        # native Forky package is the incompatible hyprtoolkit build; the
        # target-side compatibility wrapper independently rejects any future
        # candidate outside the reviewed 0.1.3/dependency contract.
        expected_agent_pin = 'Pin: release o=Debian,n=trixie-backports'
        if (f'Package: hyprpolkitagent:any\n{expected_agent_pin}\nPin-Priority: 1001' not in agent
                or re.search(r'^Pin: version ', agent, re.M)):
            raise ValueError('Qt agent must have one explicit suite-scoped release preference without a version pin')
        for tier in ('base', 'medium', 'full'):
            role_source = members[f'frontends/{suite}/classes/class-select/role/desktop/{tier}.cfg'].decode()
            if suite == 'forky':
                compatibility_archives = set(re.findall(
                    r'^d-i apt-setup/[^\n]+/repository string ([^\n]*\btrixie(?:-backports)?\b[^\n]*)$',
                    role_source, re.M))
                expected_archives = {
                    'https://packages.microsoft.com/debian/13/prod trixie main',
                    'https://repo.mysql.com/apt/debian trixie mysql-9.7-lts mysql-tools',
                } if tier == 'full' else set()
                if compatibility_archives != expected_archives:
                    raise ValueError('Forky desktop vendor compatibility archives differ from the full-class contract')
            if tier == 'full':
                packages = set(re.findall(r'^d-i pkgsel/include string (.*)$', role_source, re.M)[0].split())
                if not {'powershell', 'mysql-shell'} <= packages:
                    raise ValueError('full desktop class omits PowerShell or MySQL Shell')
            if suite == 'forky':
                if tier != 'base' and 'https://pkgs.tailscale.com/stable/debian forky main' not in role_source:
                    raise ValueError('Forky desktop does not use the published Tailscale Forky channel')
        if suite == 'forky':
            apt_fragment = members[f'frontends/{suite}/fragments/apt.cfg'].decode()
            if 'apparmor-profiles-extra/trixie' not in apt_fragment:
                raise ValueError('Forky package policy does not target apparmor-profiles-extra to Trixie')
            if ('https://mirrors.glesys.net/debian trixie main contrib non-free non-free-firmware'
                    not in apt_fragment):
                raise ValueError('Forky APT fragment omits the Debian Trixie compatibility archive')
            foreign_repositories = re.findall(
                r'^d-i apt-setup/[^\n]+/repository string ([^\n]+)$', apt_fragment, re.M)
            if any('trixie' in row and not (
                       'https://mirrors.glesys.net/debian trixie main' in row
                       or 'pkgs.zabbly.com/incus/stable trixie main' in row
                       or 'trixie-backports' in row)
                   for row in foreign_repositories):
                raise ValueError('Forky APT fragment contains an unapproved foreign Trixie repository')
            if 'https://pkgs.zabbly.com/incus/stable trixie main' not in apt_fragment:
                raise ValueError('Forky APT fragment omits the Zabbly Incus repository')
            if 'https://downloadcontent.opensuse.org/repositories/home:/cramerz:/debian/Debian_Unstable/ /' not in apt_fragment:
                raise ValueError('Forky APT fragment omits the Cramerz archive')
            for backports in ('forky-backports', 'trixie-backports'):
                if f'https://mirrors.glesys.net/debian {backports} main' not in apt_fragment:
                    raise ValueError('Forky APT fragment omits the ' + backports + ' repository')
        if suite == 'trixie':
            apt_fragment = members[f'frontends/{suite}/fragments/apt.cfg'].decode()
            if 'apparmor-profiles-extra/trixie' not in apt_fragment:
                raise ValueError('Trixie package policy does not select apparmor-profiles-extra from Trixie')
            if ('https://mirrors.glesys.net/debian forky main contrib non-free non-free-firmware'
                    not in apt_fragment):
                raise ValueError('Trixie APT fragment omits the Debian Forky compatibility archive')
            for backports in ('forky-backports', 'trixie-backports'):
                if f'https://mirrors.glesys.net/debian {backports} main' not in apt_fragment:
                    raise ValueError('Trixie APT fragment omits the ' + backports + ' repository')
            if 'https://pkgs.zabbly.com/incus/stable trixie main' not in apt_fragment:
                raise ValueError('Trixie APT fragment omits the Zabbly Incus repository')
            if 'https://downloadcontent.opensuse.org/repositories/home:/cramerz:/debian/Debian_Unstable/ /' not in apt_fragment:
                raise ValueError('Trixie APT fragment omits the Cramerz archive')
        if f'wget curl/{suite} libcurl4t64/{suite} unzip' not in apt_fragment:
            raise ValueError(f'{suite} APT fragment does not bind curl and libcurl4t64 to the same native suite')
        for name, data in members.items():
            if not (name.startswith(f'frontends/{suite}/classes/') and name.endswith('.cfg')):
                continue
            decoded = data.decode()
            llvm_selector = re.compile(
                r'^(?:clang(?:-[a-z0-9]+)*|clangd|llvm(?:-[a-z0-9]+)*|lldb?|'
                r'libclang(?:-[a-z0-9]+)*|libllvm(?:-[a-z0-9]+)*|liblldb(?:-[a-z0-9]+)*|'
                r'libpolly|python3-lldb)'
                r'-(21|22|24)(?:-|$)|^(?:libclang-cpp|libclang1|libllvm)(21|22|24)(?:-|$)')
            for package_line in re.findall(r'^d-i pkgsel/include string ([^\n]+)$', decoded, re.M):
                packages = package_line.split()
                if 'lldb' in packages and any(item.startswith('lldb-') for item in packages):
                    raise ValueError('generic lldb meta-package conflicts with a versioned LLDB binding')
                for package in packages:
                    package_name, separator, selected_suite = package.partition('/')
                    match = llvm_selector.match(package_name)
                    if not match:
                        continue
                    major = match.group(1) or match.group(2)
                    if major == '24':
                        # The source-wide Experimental pin above selects every
                        # snapshot binary without APT recursively retargeting
                        # unrelated native dependencies such as libcurl4t64.
                        if separator:
                            raise ValueError(
                                f'{suite} LLVM 24 package {package} bypasses the source-wide Experimental pin')
                        continue
                    expected_suite = 'trixie-backports' if suite == 'trixie' and major == '21' else None
                    if expected_suite is not None and (not separator or selected_suite != expected_suite):
                        raise ValueError(
                            f'{suite} LLVM {major} package {package} is not selected from Debian {expected_suite}')
        apt_sources = members['scripts/common/apt-sources.sh'].decode()
        if 'installer_apt_dedupe_source_list' not in apt_sources:
            raise ValueError('shared APT source publication lacks duplicate-target cleanup')
        apt_preferences_hook = members['hooks/installer/apt-setup/generators/99-apt-preferences'].decode()
        if 'sources.list.new' not in apt_preferences_hook:
            raise ValueError('apt-setup preference hook does not deduplicate generated sources.list.new')
        repository_answers = []
        for name, data in members.items():
            if (name == f'frontends/{suite}/fragments/apt.cfg'
                    or (name.startswith(f'frontends/{suite}/classes/') and name.endswith('.cfg'))):
                repository_answers.extend(re.findall(
                    r'^d-i apt-setup/local[0-9]+/repository string ([^\n]+)$',
                    data.decode(), re.M))
        preferences = []
        for family in ('desktop', 'server'):
            root = f'frontends/{suite}/hooks/target/etc/apt/{family}/preferences.d/'
            preferences.extend(data.decode() for name, data in members.items()
                               if name.startswith(root) and name.endswith('.pref')
                               and not name.startswith(root + 'custom/'))
        preference_text = '\n'.join(preferences)
        for repository in sorted(set(repository_answers)):
            url = repository.split()[0]
            if 'mirrors.glesys.net/debian' in url:
                components = repository.split()
                archive = components[1] if len(components) > 1 else ''
                marker = ('a=experimental' if archive == 'experimental'
                          else 'n=' + archive)
            elif 'downloadcontent.opensuse.org/repositories/home:/cramerz' in url:
                marker = 'home:cramerz:debian/Debian_Unstable'
            elif 'developer.download.nvidia.com' in url:
                marker = 'release o=NVIDIA,l=NVIDIA CUDA'
            elif 'deb.xanmod.org' in url:
                marker = 'release o=xanmod'
            else:
                host = re.sub(r'^https?://', '', url).split('/', 1)[0]
                marker = 'origin ' + host
            marker_present = marker in preference_text
            if 'deb.xanmod.org' in url:
                marker_present = marker_present or 'Pin: origin "deb.xanmod.org"' in preference_text
            if not marker_present:
                raise ValueError('APT repository has no staged preference pin: ' + repository)
        counts['apt_source_preference_contracts'] = counts.get('apt_source_preference_contracts', 0) + len(set(repository_answers))
        dns_role = members[f'frontends/{suite}/classes/class-select/role/server/technitium.cfg'].decode()
        if not {'incus-base', 'incus-client', 'tini'} <= set(re.findall(r'^d-i pkgsel/include string (.*)$', dns_role, re.M)[0].split()):
            raise ValueError('Technitium class omits its native Incus runtime')
    for row in matrix:
        plan = json.loads(members[row['plan']])
        if (plan['format'] != 2 or plan['roles'] != row['roles'] or not plan['answers']
                or not plan['packages'] or not plan['stages'] or not plan['class_sources']
                or any(sha256 != digest(members[name]) for name,sha256 in plan['class_sources'].items())):
            raise ValueError('tuple plan has no current physical class/package/stage ownership')
        if plan['family']=='desktop' and len(plan['roles']) != 1:
            raise ValueError('desktop plan selects multiple tiers')
        if 'server/technitium' in plan['roles'] and plan['roles'] != ['server/technitium']:
            raise ValueError('Technitium is currently exclusive of other server classes')
        if len({(s['phase'],s['selector']) for s in plan['stages']}) != len(plan['stages']):
            raise ValueError('combined role plan runs a helper twice in its phase')
        if plan['family'] == 'server' and 'openssh-server' not in plan['packages']:
            raise ValueError('server tuple omits SSH')
        if not {'crowdsec','timeshift'} <= set(plan['packages']):
            raise ValueError('tuple omits universal security/snapshot class content')
        kernel_packages = [name for name in plan['packages'] if name.startswith('linux-image-')]
        if kernel_packages != ['linux-image-7.3.1-x64v2-xanmod1'] or 'linux-headers-7.3.1-x64v2-xanmod1' not in plan['packages']:
            raise ValueError('minimum tuple omits the fixed XanMod EDGE image/header pair')
        if 'os.kernel' not in {stage['id'] for stage in plan['stages']}:
            raise ValueError('tuple omits the shared kernel verification/regulatory-data stage')
        if (plan['crypto_root'] not in ('true', 'false') or plan['crypto_home'] not in ('true', 'false')
                or plan['ssh_enable'] not in ('true', 'false') or not str(plan['ssh_port']).isdecimal()
                or plan['wifi_enable'] not in ('true', 'false') or plan['ipv6_enable'] not in ('true', 'false')
                or plan['snapshots'] != 'timeshift-btrfs' or not plan['primary_iface']):
            raise ValueError('minimum tuple has incomplete explicit profile policy')
        names = {re.split(r'[/:=]', item, maxsplit=1)[0] for item in plan['packages']}
        system_x11 = {'dbus-x11', 'x11-xkb-utils', 'x11-xserver-utils', 'xauth',
                      'xinit', 'xterm', 'xwayland', 'xserver-common', 'xorg',
                      'xvfb', 'xnest', 'xserver-xephyr'}
        if (plan['suite'], plan['family']) == ('trixie', 'desktop'):
            system_x11 -= {'xwayland', 'x11-xkb-utils', 'xserver-common'}
        elif plan['suite'] == 'trixie':
            system_x11 -= {'x11-xkb-utils'}
        if names & system_x11 or any(name.startswith('xserver-xorg') for name in names):
            raise ValueError('tuple selects the forbidden system X11 runtime')
        if plan['family'] == 'desktop':
            if 'hyprpolkitagent' not in names or names & {'lxqt-policykit', 'mate-polkit', 'ukui-polkit'}:
                raise ValueError('desktop does not retain the required Hyprpolkitagent')
        if not {'perl', 'python3', 'initramfs-tools', 'cryptsetup-initramfs', 'systemd-cryptsetup', 'systemd-tpm'} <= names:
            raise ValueError('tuple omits the universal language/initramfs/crypto package baseline')
        if any(re.match(r'^python3\.\d|^python3[=/:]', package) for package in plan['packages']):
            raise ValueError('tuple fixes a native Python minor version, suite override or package version')
        if not {'auditd', 'audispd-plugins', 'apparmor', 'apparmor-profiles',
                'apparmor-profiles-extra', 'apparmor-utils', 'nftables', 'fail2ban',
                'python3-pyinotify', 'rsyslog', 'debsums', 'logrotate'} <= names:
            raise ValueError('tuple omits the universal APT security baseline')
        if any(reference.startswith('security/') for reference in plan['classes']):
            raise ValueError('tuple selects a removed security class')
        stages = {stage['id'] for stage in plan['stages']}
        if not {'os.shared', 'os.uplinks', 'os.crypto', 'os.crowdsec', 'os.timeshift', 'os.sharing', 'os.services'} <= stages:
            raise ValueError('tuple omits a shared phase helper')
        if plan['roles'] == ['desktop/base']:
            if not {'labwc', 'waybar', 'vivaldi-stable', 'spotify-client', 'l3afpad'} <= names:
                raise ValueError('base omits its essential native desktop packages')
            forbidden = {'podman','buildah','qemu-system-x86','incus','flashrom','flashprog','mise','sccache',
                         'chromium', 'microsoft-edge-stable', 'mullvad-browser', 'firefox', 'firefox-esr'}
            if names & forbidden or stages & {'desktop.devops','os.virtualization','os.firmware','desktop.whisper','desktop.ch341a','desktop.tailscale'}:
                raise ValueError('base activates a specialist desktop class closure')
        if plan['family'] == 'server':
            if stages & {'desktop.storage','desktop.software','desktop.session'} or names & {'labwc','waybar','zsh','starship'}:
                raise ValueError('a server tuple activates desktop/session content')
            if 'incus-ui-canonical' in names:
                raise ValueError('a headless server tuple includes the desktop Incus Web UI')
        if plan['codex_only_enable'] not in ('true', 'false') or plan['codex_enable'] not in ('true', 'false'):
            raise ValueError('tuple omits explicit Codex profile and resolved role policy')
        ai_fields = ('requested_whisper_enable', 'requested_llama_enable',
                     'whisper_enable', 'llama_enable')
        if any(plan.get(field) not in ('true', 'false') for field in ai_fields):
            raise ValueError('tuple omits requested or effective Whisper/Llama policy')
        # A profile request and a role-derived capability describe different
        # facts. Desktop DevOps owns Llama independently of server opt-ins.
        expected_whisper = bool(stages & {'desktop.whisper', 'server.whisper'})
        expected_llama = ('server.llama' in stages or
                          plan['family'] == 'desktop' and 'desktop.devops' in stages)
        if ((plan['whisper_enable'] == 'true') != expected_whisper
                or (plan['llama_enable'] == 'true') != expected_llama):
            raise ValueError('effective AI capability differs from selected implementation stages')
        serialized = [line.split('\t') for line in members[row['plan'].removesuffix('.json') + '.tsv'].decode().splitlines()]
        for field in ai_fields:
            if [values for values in serialized if values[0] == field] != [[field, plan[field]]]:
                raise ValueError('AI singleton is duplicated or differs between JSON and TSV: ' + field)
        if plan['family'] == 'server':
            ai_stages = stages & {'server.whisper', 'server.llama'}
            expected_ai = set()
            if plan['requested_whisper_enable'] == 'true':
                expected_ai.add('server.whisper')
            if plan['requested_llama_enable'] == 'true':
                expected_ai.add('server.llama')
            if ai_stages != expected_ai:
                raise ValueError('server AI stage differs from profile enablement')
        elif (plan['requested_whisper_enable'] != 'false'
              or plan['requested_llama_enable'] != 'false'):
            raise ValueError('desktop tuple carries server-only AI profile requests')
        codex = (plan['family'] == 'server' and plan['codex_only_enable'] == 'true'
                 or bool(set(plan['roles']) & {'desktop/medium', 'desktop/full', 'server/devops'}))
        if (plan['codex_enable'] == 'true') != codex or ('os.codex' in stages) != codex:
            raise ValueError('Codex tuple stage differs from primary-account role/profile ownership')
        if plan['classes'].count('fragments/codex.cfg') != int(codex):
            raise ValueError('Codex fragment must be included exactly once by its role/profile policy')
        if codex and not {'bubblewrap', 'openssh-client'} <= names:
            raise ValueError('Codex tuple lacks its namespace and private Git prerequisites')
        if ('server.devops.tools' in stages) != ('server/devops' in plan['roles']):
            raise ValueError('server full toolchain activation differs from the DevOps class')
        virtualization = (plan['roles'] in (['desktop/medium'], ['desktop/full']) or 'server/devops' in plan['roles'])
        if virtualization != ('os.virtualization' in stages):
            raise ValueError('shared virtualization phase differs from physical role ownership')
        if virtualization != ('os.firmware' in stages):
            raise ValueError('shared firmware phase differs from physical role ownership')
        desktop_virtualization = plan['roles'] in (['desktop/medium'], ['desktop/full'])
        if desktop_virtualization != ('desktop.virtualization' in stages):
            raise ValueError('desktop virtualization integration differs from desktop role ownership')
    # Inspect real source declarations and current member bytes. This does
    # not execute a role predicate, render an installer shell, or read docs.
    essential = (
        'hooks/target/etc/apparmor.d/desktop/opt.Bitwarden.bitwarden',
        'hooks/target/etc/apparmor.d/desktop/opt.tuta-mail.AppRun',
        'hooks/target/etc/apparmor.d/desktop/opt.ledger-live.AppRun',
        'hooks/target/etc/apparmor.d/desktop/sleek',
        'hooks/target/etc/apparmor.d/desktop/tomat',
        'hooks/target/etc/apparmor.d/desktop/usr.bin.spotify',
        'hooks/target/usr/local/share/desktop/applications/sleek.desktop.tmpl',
        'hooks/target/usr/local/share/desktop/applications/ledger-live.desktop.tmpl',
        'hooks/target/etc/skel-desktop/.local/share/applications/tutanota-desktop.desktop.tmpl',
        'hooks/target/etc/skel-desktop/.config/waybar/modules/app-sleek.tmpl',
        'hooks/target/etc/skel-desktop/.config/waybar/modules/app-tuta.tmpl',
        'hooks/target/etc/skel-desktop/.config/waybar/modules/tomat.tmpl',
        'hooks/target/etc/apparmor.d/desktop/calendars',
        'hooks/target/usr/local/lib/common/perl5/site_perl/apt-repo-local/APTRepoLocal/Servicing/Bitwarden.pm',
        'hooks/target/usr/local/lib/desktop/python3/dist-packages/labwc_managed_app/integrity.py',
        'hooks/target/usr/local/libexec/desktop/calix-fruux-bootstrap',
        'hooks/target/usr/local/libexec/desktop/labwc-waycal-control',
        'hooks/target/usr/local/libexec/desktop/labwc-calendar-worker',
        'hooks/target/usr/local/share/desktop/applications/com.ianswope.Calix.desktop.tmpl',
        'hooks/target/usr/local/share/desktop/applications/com.github.dahenson.agenda.desktop.tmpl',
        'hooks/target/usr/local/share/desktop/agenda/schemas/90-desktop-agenda.gschema.override',
        'hooks/target/etc/skel-desktop/.config/systemd/user/labwc-calendar-credentials.service',
        'hooks/target/etc/skel-desktop/.config/waybar/modules/clock.tmpl',
    )
    if any(not members.get(name) for name in essential):
        raise ValueError('essential desktop application/policy/schema/menu source is absent')
    software = members['scripts/late/software.sh.tmpl'].decode()
    app_calls = list(re.finditer(
        r'^software_run_selected_app "([^"]+)" "([^"]+)" ([a-z0-9_]+) ([a-z0-9_]+)$',
        software, re.M))
    app_owners: dict[str, list[tuple[str, ...]]] = {}
    for call in app_calls:
        app = re.sub(r' (?:preparation|post-install)$', '', call[2])
        app_owners.setdefault(app, []).append(tuple(call[1].split()))
    desktops = ('role/desktop/base', 'role/desktop/medium', 'role/desktop/full')
    for app in ('Bitwarden Desktop', 'Tuta Mail', 'Sleek', 'Tomat', 'Ledger Live', 'Obsidian'):
        if not app_owners.get(app) or any(owner != desktops for owner in app_owners[app]):
            raise ValueError('common desktop application installer ownership differs: ' + app)
    medium_apps = ('Zoom Workplace', 'Filen Desktop', 'Discord')
    for app in medium_apps:
        if not app_owners.get(app) or any(owner != desktops[1:] for owner in app_owners[app]):
            raise ValueError('medium application installer ownership differs: ' + app)
    for app in ('QoreDB', 'Postman', 'Tor Browser'):
        if not app_owners.get(app) or any(owner != desktops[2:] for owner in app_owners[app]):
            raise ValueError('full-only application installer ownership differs: ' + app)
    deb_batch = (
        ('Bitwarden Desktop', 'bitwarden'), ('QoreDB', 'qoredb'),
        ('Obsidian', 'obsidian'), ('Tomat', 'tomat'), ('Sleek', 'sleek'),
        ('Zoom Workplace', 'zoom'), ('Filen Desktop', 'filen'),
    )
    batch_begin = re.search(r'^software_begin_deb_batch desktop$', software, re.M)
    batch_flushes = list(re.finditer(r'^software_flush_deb_batch$', software, re.M))
    if batch_begin is None or len(batch_flushes) != 1:
        raise ValueError('desktop package batch must have one preparation and install boundary')
    batch_flush = batch_flushes[0]
    for phase, worker_prefix, expected_members in (
            ('preparation', 'prepare', deb_batch),
            ('post-install', 'finish', tuple(member for member in deb_batch if member[1] != 'zoom'))):
        phase_calls = [call for call in app_calls if call[2].endswith(' ' + phase)]
        expected = [(label + ' ' + phase, f'software_{worker_prefix}_{key}_app',
                     f'software_{key}_installed') for label, key in expected_members]
        if [(call[2], call[3], call[4]) for call in phase_calls] != expected:
            raise ValueError('desktop package batch members or order differ: ' + phase)
        if any(not (batch_begin.end() < call.start() < batch_flush.start())
               if phase == 'preparation' else call.start() < batch_flush.end()
               for call in phase_calls):
            raise ValueError('desktop package batch dependency barrier differs: ' + phase)
    staging = members['scripts/desktop/components/stage-assets.sh'].decode()
    predicate = staging.split('desktop_role_owns_target() {', 1)[1].split('\n}', 1)[0]
    cases = predicate.split('case "$1" in', 1)[1].split(')\n', 1)[0]
    patterns = [part.strip() for part in cases.replace('\\\n', '').split('|')]
    for path in ('/bin/labwc-ai-copilots', '/bin/labwc-podman-menu',
                 '/skel/.profile.d/71-devops-de.sh', '/skel/.profile.d/72-incus.sh',
                 '/skel/.profile.d/75-firmware-workspace.sh', '/user/whisper-server.service'):
        if not any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns):
            raise ValueError('base specialist staging exclusion is absent: ' + path)
    if 'installer_class_selected_any role/desktop/medium role/desktop/full' not in predicate:
        raise ValueError('specialist staging is not owned by physical medium/full classes')
    firstboot = members['scripts/firstboot/04-validation.sh.tmpl'].decode()
    for contract in (
            "desktop_selected_role='__INSTALLER_FIRSTBOOT_ROLE_IDS__'",
            "desktop_selected_suite='__INSTALLER_FIRSTBOOT_SUITE__'",
            "desktop_expected_family='__INSTALLER_FIRSTBOOT_HOST_VARIANT__'",
            'desktop:desktop/base:forky|desktop:desktop/medium:forky|desktop:desktop/full:forky|',
            'desktop:desktop/base:trixie|desktop:desktop/medium:trixie|desktop:desktop/full:trixie)',
            '[ "${desktop_selected_role:-}" = desktop/base ] || return 1',
            'check_desktop_role_path "desktop-path-${desktop_path}" "$desktop_path"',
            '"desktop-user-unit-${desktop_user_unit_path}"',
            'desktop_role_excludes_path "__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/$command_name"',
            'whisper_template_link=__INSTALLER_PATH_DIR_ETC_SKEL_DESKTOP_CONFIG__/systemd/user/labwc-session.target.wants/whisper-server.service',
            'desktop-user-unit-whisper-server-disabled'):
        if contract not in firstboot:
            raise ValueError('firstboot desktop class verification loses contract: ' + contract)
    exclusions = firstboot.split('desktop_role_excludes_path() {', 1)[1].split('\n}', 1)[0]
    clauses = exclusions.split('case "$1" in', 1)[1].split('esac', 1)[0].split(';;')
    firstboot_patterns = []
    for clause in clauses:
        if ')' in clause and 'return 0' in clause:
            firstboot_patterns.extend(part.strip() for part in clause.split(')', 1)[0].replace('\\\n', '').split('|'))
    for path in ('__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/resctl-bench',
                 '__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/scrcpy', '/bin/labwc-ai-copilots',
                 '/bin/labwc-adb-menu', '/bin/labwc-podman-menu', '/bin/labwc-qbittorrent',
                 '/skel/user/labwc-adb-server.service', '/home/user/user/llama-server.service'):
        if not any(fnmatch.fnmatchcase(path, pattern) for pattern in firstboot_patterns):
            raise ValueError('firstboot still requires excluded base desktop activation: ' + path)
    for path in ('/bin/labwc-calendar', '/bin/labwc-desktop-appearance', '/user/waybar.service',
                 '/user/labwc-calendar-credentials.service', '/bin/tomat', '/bin/sleek'):
        if any(fnmatch.fnmatchcase(path, pattern) for pattern in firstboot_patterns):
            raise ValueError('firstboot excludes an essential desktop path: ' + path)
    for name, data in members.items():
        if name.startswith(('hooks/target/', 'scripts/firstboot/')) and (
                b'FILE_INSTALLER_CLASSES' in data or b'installer-class-receipt' in data):
            raise ValueError('installed runtime still depends on installer-only class data: ' + name)
    if (b'installer_publish_class_receipt' in members['scripts/common/modules/installation-plan.sh']
            or b'FILE_INSTALLER_CLASSES=' in members['hosts/installer/runtime.env']):
        raise ValueError('installer class data must not have a target publication contract')
    firstboot_staging = members['scripts/late/core.sh'].decode()
    for field in ('FIRSTBOOT_ROLE_IDS "$firstboot_roles"', 'FIRSTBOOT_RELEASE_ID "$INSTALLER_RELEASE_ID"',
                  'FIRSTBOOT_HOST_VARIANT "$INSTALLER_HOST_VARIANT"', 'FIRSTBOOT_SUITE "$INSTALLER_SUITE"'):
        if field not in firstboot_staging:
            raise ValueError('installation does not render boot expectations: ' + field)
    counts['firstboot_rendered_desktop_policy_contracts'] = 1
    counts['firstboot_desktop_absence_patterns'] = len(firstboot_patterns)
    if any(any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns) for path in (
            '/skel/.local/share/applications/tutanota-desktop.desktop',
            '/skel/.config/sleek/userData/config.json', '/skel/.config/tomat/config.toml')):
        raise ValueError('common desktop application configuration is excluded from base staging')
    desktop_config = members['scripts/desktop/components/desktop-config.sh'].decode()
    for function in ('desktop_waybar_modules_left_json', 'desktop_waybar_apps_drawer_json',
                     'desktop_waybar_modules_right_json'):
        body = desktop_config.split(function + '() {', 1)[1].split('\n}', 1)[0]
        if 'class_selected' in body or 'INSTALLER_DESKTOP_ROLE' in body:
            raise ValueError('desktop tier changes the shared Waybar contract: ' + function)
    for tier in ('base', 'medium', 'full'):
        for suite in ('forky', 'trixie'):
            role_source = members[f'frontends/{suite}/classes/class-select/role/desktop/{tier}.cfg'].decode()
            if ('spotify-client' not in re.findall(r'^d-i pkgsel/include string (.*)$', role_source, re.M)[0].split()
                    or 'https://repository.spotify.com stable non-free' not in role_source):
                raise ValueError('a desktop tier omits Spotify or its scoped vendor repository')
    if '--appimage-extract' in software:
        raise ValueError('desktop installation executes an AppImage runtime during extraction')
    workspace_keys = ('LABWC_WORKSPACE_COUNT_INTERNAL', 'LABWC_WORKSPACE_COUNT_EXTERNAL')
    profile_names = [name for name in members if name.startswith('hosts/profiles/desktop/')
                     and name.endswith('.env')]
    for name in profile_names:
        source = members[name].decode()
        for key in workspace_keys:
            if re.search(r'^' + key + r'="(?:[1-9]|1[0-2])"$', source, re.M) is None:
                raise ValueError('desktop profile lacks an explicit internal/external workspace policy: ' + name)
        if re.search(r'^LABWC_WORKSPACE_COUNT=', source, re.M):
            raise ValueError('retired single workspace profile policy remains: ' + name)
    count_defaults = members['hooks/target/etc/labwc/desktop.conf.tmpl'].decode()
    if any(key + '=__INSTALLER_' + key + '__' not in count_defaults for key in workspace_keys):
        raise ValueError('desktop runtime defaults omit a workspace topology count')
    watcher = members['hooks/target/usr/local/libexec/desktop/labwc-output-watch'].decode()
    if not all(text in watcher for text in (*workspace_keys,
            'reconcile_workspace_policy(load_saved_topology())', '.workspace-policy.previous.xml',
            "'--reconfigure'", 'no_network => 1, load_ext_dtd => 0, expand_entities => 0')):
        raise ValueError('native workspace topology policy or retained recovery is incomplete')
    counts['desktop_workspace_profiles'] = len(profile_names)
    for suite in ('forky', 'trixie'):
        selected = {tuple(row['roles']): json.loads(members[row['plan']]) for row in matrix if row['suite'] == suite}
        previous = set()
        for tier in ('base', 'medium', 'full'):
            package_set = set(selected[('desktop/' + tier,)]['packages'])
            if not previous <= package_set:
                raise ValueError('desktop class package inheritance is incomplete: ' + tier)
            previous = package_set
        medium = set(selected[('desktop/medium',)]['packages'])
        if not {'telegram-desktop', 'qbittorrent', 'spotify-client', 'retroarch',
                'microsoft-edge-stable', 'mullvad-browser', 'mullvad-vpn'} <= medium:
            raise ValueError('explicit medium native application list is incomplete')
    server_unit = members['hooks/target/etc/systemd/server/system/managed-buildbuddy.service.tmpl'].decode()
    if any(line not in server_unit.splitlines() for line in (
            'User=srv-devops', 'Slice=ci-workloads.slice', 'CapabilityBoundingSet=',
            'IPAddressDeny=any', 'IPAddressAllow=localhost', 'Restart=no')):
        raise ValueError('headless build cache service loses its private authority contract')
    for artifact_name in ('bazelisk', 'buildbuddy'):
        if "artifact('" + artifact_name + "'" in members['scripts/common/virtualization.sh'].decode():
            raise ValueError('headless DevOps artifact leaked into the common virtualization stage')
    firmware = members['hooks/target/usr/local/sbin/common/fwops-mode'].decode()
    if re.search(r'>[^\n]*(?:driver_override|spidev/bind)', firmware) or 'return 69' not in firmware:
        raise ValueError('firmware mode reintroduces identity-unsafe device mutation')
    counts['essential_desktop_sources'] = len(essential)
    counts['managed_application_owners'] = len(app_owners)
    counts['desktop_package_inheritance'] = 6
    counts['current_release_members'] = len(members)
    counts['current_release_source_equality'] = len(source_names)
    counts['current_release_frontend_equality'] = len(receipt['frontends'])
    counts['minimum_tuple_plans'] = len(required)
    if len(matrix) != 22:
        raise ValueError('source plan matrix does not cover exactly the currently compatible role combinations')
    counts['all_role_combination_plans'] = len(matrix)
    counts['trusted_product_pins'] = 6
    counts['system_x11_exclusion_policies'] = 4
    counts['qt_agent_release_policies'] = 2
    dns_source = members['hooks/target/usr/local/lib/server/technitium_incus.py.tmpl'].decode()
    dns_tree = ast.parse(dns_source)
    workload = next(node for node in dns_tree.body if isinstance(node, ast.ClassDef) and node.name == 'Workload')
    methods = {node.name for node in workload.body if isinstance(node, ast.FunctionDef)}
    if not {'image', 'image_stream', 'upload', 'prepare', 'transition', 'snapshot', 'restore_snapshot', 'export_config'} <= methods:
        raise ValueError('Technitium persistent lifecycle has incomplete maintenance ownership')
    dns_init = members['hooks/target/usr/local/lib/server/technitium-init.sh.tmpl'].decode()
    if not all(item in dns_init for item in ('--reuid=2103', '--regid=2103', '--bounding-set=-all',
                                            'DNS_SERVER_ADMIN_PASSWORD_FILE=', 'DNS_SERVER_RECURSION_NETWORK_ACL=',
                                            'DNS_SERVER_PREFER_IPV6=__INSTALLER_IPV6_ENABLE__')):
        raise ValueError('Technitium guest loses its non-root/private-policy boundary')
    if ('DNS_SERVER_LOCAL_END_POINTS' in dns_init
            or "'privileged': True" in dns_source or "'security.privileged': 'true'" in dns_source):
        raise ValueError('Technitium uses an invented upstream setting or privileged guest')
    counts['technitium_native_incus_contracts'] = 2
    if 'pool_driver' not in methods or not all(token in dns_source for token in (
            "'--mountpoint'", "filesystem == 'xfs'", "{'prjquota', 'pquota'}", "return 'dir'")):
        raise ValueError('Technitium does not qualify its dedicated XFS data-pool backend')
    if any(name in members for name in ('suites/forky/suite.json', 'suites/trixie/suite.json')):
        raise ValueError('retired suite JSON became an installation input again')
    if members['hooks/installer/suite-policy.tsv'] != members['catalog/compiled/suite-qualification.tsv']:
        raise ValueError('compiled native-suite gate differs from the authored installer policy')
    counts['native_suite_policy_rows'] = 4
    gitbuild = members['hooks/target/usr/local/lib/common/python3/dist-packages/gitbuild/core.py'].decode()
    worker = members['hooks/target/usr/local/lib/common/python3/dist-packages/gitbuild/worker.py.tmpl'].decode()
    shell = members['hooks/target/etc/skel-server/.profile.d/71-devops-srv.sh'].decode()
    if ("DISTRIBUTION = '__INSTALLER_GITBUILD_DISTRIBUTION__'" not in gitbuild
            or "self.output = self.repo / 'target/gitbuild'" in gitbuild
            or '__INSTALLER_PATH_DIR_POOL_TMP__' not in worker
            or 'CARGO_TARGET_DIR=$server_devops_build/' not in shell
            or 'server_devops_podman=__INSTALLER_PATH_DIR_POOL_PODMAN__/devops/$server_devops_user' not in shell
            or 'CONTAINERS_STORAGE_CONF=$server_devops_podman/' not in shell):
        raise ValueError('managed build/container outputs escape the dedicated data-pool contract')
    counts['dedicated_pool_storage_contracts'] = 4
    incus_host = members['hooks/target/usr/local/libexec/common/incus-host'].decode()
    for key in ('storage.images_volume', 'storage.backups_volume', 'storage.logs_volume'):
        if key not in incus_host or key not in dns_source:
            raise ValueError('native Incus image/backup/log storage can escape the data pool: ' + key)
    counts['native_incus_pool_volume_policies'] = 6
    for suite in ('forky', 'trixie'):
        arch_source = members[f'frontends/{suite}/classes/class-auto/arch/amd64.cfg'].decode()
        kernel_answers = ('d-i base-installer/kernel/skip-install boolean true',
                          'd-i base-installer/kernel/image select none',
                          'd-i base-installer/kernel/linux/initrd boolean false')
        if (any(answer not in arch_source for answer in kernel_answers)
                or 'linux-image-amd64' in arch_source):
            raise ValueError('amd64 restores a stock kernel fallback instead of the fixed EDGE pair')
        for level in ('x64v2', 'x64v3'):
            kernel_source = members[f'frontends/{suite}/classes/class-auto/kernel/{level}.cfg'].decode()
            if (f'linux-image-7.3.1-{level}-xanmod1' not in kernel_source
                    or f'linux-headers-7.3.1-{level}-xanmod1' not in kernel_source):
                raise ValueError('suite omits a fixed XanMod EDGE CPU variant')
    counts['fixed_xanmod_edge_pairs'] = 4


def check_structured(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    parsed = 0
    yaml_files = 0
    for path in paths:
        suffix = _logical_suffix(path)
        try:
            if suffix in BINARY_SUFFIXES:
                if path.name.endswith(('.tar.gz', '.tgz')):
                    # Parse archive framing only, without extracting files or
                    # asserting a member inventory, modes or payload contents.
                    with tarfile.open(path, 'r|*') as archive:
                        for _member in archive:
                            pass
                continue
            text = _read_text(path)
            waybar_root = TARGET_ROOT / 'etc/skel-desktop/.config/waybar'
            if path.is_relative_to(waybar_root) and (
                    path.name == 'config.tmpl' or path.parent == waybar_root / 'modules'):
                # Numeric/list installer slots are the only unquoted tokens
                # in these JSON templates. Parse as data without executing a
                # renderer, and preserve quoted strings and action arguments.
                json.loads(re.sub(r'__(?:THEME|INSTALLER)_[A-Z0-9_]+__(?=\s*[,}\]])',
                                  '0', text))
                parsed += 1
            elif path.is_relative_to(waybar_root) and suffix in {'.xml', '.svg'}:
                ElementTree.fromstring(text)
                parsed += 1
            elif suffix == '.json' and not path.name.endswith('.json.tmpl'):
                json.loads(text)
                parsed += 1
            elif suffix in {'.yaml', '.yml'} and not path.name.endswith(('.yaml.tmpl', '.yml.tmpl')):
                if yaml is None:
                    errors.append(f'{path.relative_to(ROOT)}: YAML parser unavailable')
                else:
                    list(yaml.parse(text))
                    yaml_files += 1
                    parsed += 1
            elif suffix == '.toml' and not path.name.endswith('.toml.tmpl'):
                tomllib.loads(text)
                parsed += 1
            elif suffix in {'.xml', '.svg'} and not path.name.endswith(('.xml.tmpl', '.svg.tmpl')):
                ElementTree.fromstring(text)
                parsed += 1
            elif suffix in {'.desktop', '.ini'} and not path.name.endswith('.tmpl'):
                parser = configparser.ConfigParser(interpolation=None, strict=True)
                parser.read_string(text)
                parsed += 1
            elif suffix == '.pref' and '/hooks/target/etc/apt/' in path.as_posix():
                # APT preferences are RFC822 records, not shell assignments or
                # arbitrary text. Parse the actual source without invoking APT.
                records = []
                record = {}
                for line_number, line in enumerate([*text.splitlines(), ''], 1):
                    if not line.strip():
                        if record:
                            records.append(record)
                            record = {}
                        continue
                    if line.lstrip().startswith('#'):
                        continue
                    match = re.fullmatch(r'(Package|Pin|Pin-Priority|Explanation):[ \t]+(.+)', line)
                    if match is None:
                        raise ValueError(f'malformed APT preference at line {line_number}')
                    key, value = match.groups()
                    if key in record and key != 'Explanation':
                        raise ValueError(f'duplicate APT preference field at line {line_number}')
                    record[key] = value
                if not records:
                    raise ValueError('empty APT preference policy')
                for record in records:
                    if not {'Package', 'Pin', 'Pin-Priority'} <= record.keys():
                        raise ValueError('incomplete APT preference record')
                    if (re.fullmatch(r'-?[0-9]{1,5}', record['Pin-Priority']) is None
                            or not re.fullmatch(r'(?:version|release|origin) .+', record['Pin'])):
                        raise ValueError('invalid APT preference pin or priority')
                counts['apt_preference_records'] = counts.get('apt_preference_records', 0) + len(records)
                parsed += 1
            elif suffix in {'.service', '.timer'} and not path.name.endswith('.tmpl'):
                for line_number, line in enumerate(text.splitlines(), 1):
                    stripped = line.strip()
                    if not stripped or stripped.startswith(('#', ';')):
                        continue
                    if stripped.startswith('[') and stripped.endswith(']'):
                        continue
                    if '=' not in line or not re.match(r'^[A-Za-z][A-Za-z0-9]+=', line):
                        raise ValueError(f'malformed unit assignment at line {line_number}')
                parsed += 1
            elif path == DEBIAN_ROOT / 'hooks/installer/class-dispatch.tsv':
                rows = text.splitlines()
                if not rows or rows[0] != 'format\t1' or len(rows) > 1000:
                    raise ValueError('invalid class dispatch format or bounds')
                for line_number, line in enumerate(rows[1:], 2):
                    if not line or line.startswith('#'):
                        continue
                    cells = line.split('\t')
                    if cells[0] not in {'class', 'stage'} or len(cells) != (5 if cells[0] == 'class' else 7):
                        raise ValueError(f'invalid class dispatch record at line {line_number}')
                    if any(not cell or re.fullmatch(r'[A-Za-z0-9_./,-]+', cell) is None for cell in cells):
                        raise ValueError(f'invalid class dispatch cell at line {line_number}')
                parsed += 1
            elif path == DEBIAN_ROOT / 'hooks/installer/suite-policy.tsv':
                rows = text.splitlines()
                if not rows or rows[0] != 'format\t1':
                    raise ValueError('native suite policy requires its format header')
                owners = set()
                for row in rows[1:]:
                    cells = row.split('\t')
                    if (len(cells) != 5 or cells[0] not in {'forky', 'trixie'}
                            or cells[1] not in {'desktop', 'server'}
                            or cells[2] not in {'blocked', 'source-candidate'}
                            or re.fullmatch(r'[a-z][a-z0-9-]{1,80}', cells[3]) is None
                            or re.fullmatch(r'[A-Za-z0-9 .;:/,()-]{1,320}', cells[4]) is None
                            or tuple(cells[:2]) in owners):
                        raise ValueError('invalid or duplicate native suite policy record')
                    owners.add(tuple(cells[:2]))
                parsed += 1
            elif suffix == '.tsv' and not path.name.endswith('.tsv.tmpl'):
                widths = {len(line.split('\t')) for line in text.splitlines() if line and not line.startswith('#')}
                if len(widths) > 1:
                    raise ValueError('inconsistent tabular field count')
                parsed += 1
            elif suffix == '.env' and not path.name.endswith('.env.tmpl'):
                for line_number, line in enumerate(text.splitlines(), 1):
                    if line and not line.startswith('#') and not re.fullmatch(r'[A-Z][A-Z0-9_]*=.*', line):
                        raise ValueError(f'malformed environment assignment at line {line_number}')
                parsed += 1
        except (OSError, UnicodeError, ValueError, TypeError, json.JSONDecodeError,
                tomllib.TOMLDecodeError, ElementTree.ParseError, configparser.Error,
                YAML_ERROR) as error:
            errors.append(f'{path.relative_to(ROOT)}: structured syntax: {error}')
    counts['structured_files'] = parsed
    counts['yaml_files'] = yaml_files


def check_plain_classes(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Class .cfg files are plain preseed data; comments never carry dispatch."""
    roots = [ROOT / 'd-i' / suite / 'classes' for suite in ('forky', 'trixie')]
    files = [path for path in paths if path.suffix == '.cfg' and any(path.is_relative_to(root) for root in roots)]
    for path in files:
        pending = ''
        for number, line in enumerate(_read_text(path).splitlines(), 1):
            if line.lstrip().startswith('#'):
                if re.match(r'^\s*#\s*Installer-', line):
                    errors.append(f'{path.relative_to(ROOT)}:{number}: class comment directives are forbidden')
                continue
            if not line.strip():
                continue
            if re.search(r'\$\{|\$[A-Za-z_(]|__INSTALLER_', line):
                errors.append(f'{path.relative_to(ROOT)}:{number}: class variables are forbidden')
            pending += line.lstrip() if pending else line
            if pending.endswith(' \\'):
                pending = pending[:-1]
                continue
            fields = pending.split(None, 3)
            if (len(fields) < 3 or fields[2] not in {'string', 'boolean', 'select', 'multiselect', 'password', 'note', 'text', 'seen'}
                    or re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9+_.-]*', fields[0]) is None
                    or re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9+_./:-]*', fields[1]) is None):
                errors.append(f'{path.relative_to(ROOT)}:{number}: expected an ordinary preseed answer')
            pending = ''
        if pending:
            errors.append(f'{path.relative_to(ROOT)}: incomplete preseed continuation')
    counts['plain_preseed_classes'] = len(files)


def check_asset_partitions(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    checked = 0
    changed = {path.relative_to(TARGET_ROOT).as_posix(): path for path in paths if path.is_relative_to(TARGET_ROOT)}
    for relative, path in changed.items():
        for group in ASSET_GROUPS:
            if not relative.startswith(group + '/'):
                continue
            leaf = relative[len(group) + 1:]
            family, separator, name = leaf.partition('/')
            if family not in {'common', 'desktop', 'server'} or not separator:
                errors.append(f'{path.relative_to(ROOT)}: target source lacks physical family ownership')
                break
            checked += 1
            for other in ({'desktop', 'server'} if family == 'common' else {'common'}):
                candidate = TARGET_ROOT / group / other / name
                alternatives = {candidate, candidate.with_name(candidate.name.removesuffix('.tmpl')),
                                candidate.with_name(candidate.name + '.tmpl')}
                if any(item.is_file() and not item.is_symlink() for item in alternatives):
                    errors.append(f'{path.relative_to(ROOT)}: overlapping common/family source owner')
                    break
            break
    common_policy = TARGET_ROOT / 'etc/apparmor.d/common/incus-host.tmpl'
    common_backend = TARGET_ROOT / 'usr/local/libexec/common/incus-host'
    if common_policy in paths or common_backend in paths:
        for source in (common_policy, common_backend):
            text = _read_text(source)
            if any(value in text for value in ('/incus/ui/', 'INCUS_UI=', 'INCUS_MANAGED_WEB_UI_ENABLE', '<abstractions/wrapper-desktop>', '<abstractions/wrapper-gui>')):
                errors.append(f'{source.relative_to(ROOT)}: desktop UI contract leaked into common Incus backend')
    counts['partitioned_target_sources'] = checked


def check_apparmor(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    policy_root = TARGET_ROOT / 'etc/apparmor.d'
    files = [path for path in paths if path.is_relative_to(policy_root)]
    file_rule = re.compile(
        r'\s*((?:(?:audit|deny|allow|owner)\s+)*)'
        r'(?:"[^"\n]+"|/[^\s"]*|@\{[A-Za-z0-9_]+\}[^\s]*)\s+'
        r'([A-Za-z]+)(?:\s+->\s+[^\s,]+)?\s*,\s*(?:#.*)?'
    )
    for path in files:
        text = _read_text(path)
        depth = 0
        for line_number, raw in enumerate(text.splitlines(), 1):
            stripped = raw.lstrip()
            line = '' if stripped.startswith('#') else raw
            rule = file_rule.fullmatch(line)
            if (rule and 'deny' not in rule.group(1).split()
                    and re.search(r'(?<![ipPcCuU])x', rule.group(2))):
                errors.append(f'{path.relative_to(ROOT)}:{line_number}: '
                              'AppArmor allow execute permission requires an execution qualifier')
            for column, char in enumerate(line, 1):
                if char == '{':
                    depth += 1
                elif char == '}':
                    depth -= 1
                    if depth < 0:
                        errors.append(f'{path.relative_to(ROOT)}:{line_number}:{column}: unmatched closing brace')
                        depth = 0
            if ('{' in line and '}' not in line and not stripped.startswith('profile ')
                    and ('/' in line or stripped.startswith(('owner ', 'deny owner ')))):
                errors.append(f'{path.relative_to(ROOT)}:{line_number}: multiline path/owner brace rule')
            if stripped.startswith('profile ') and not stripped.endswith('{'):
                errors.append(f'{path.relative_to(ROOT)}:{line_number}: profile declaration lacks opening brace')
            # AppArmor's unix addr= conditional describes abstract or anonymous
            # socket addresses. Filesystem pathname sockets are mediated by
            # ordinary file rules; reject the parser-invalid form early,
            # including when it appears inside peer=(addr=...).
            if (re.match(r'^\s*(?:deny\s+)?unix\b', line)
                    and re.search(r"\baddr\s*=\s*(?:\(\s*)?[\"']?/", line)):
                errors.append(f'{path.relative_to(ROOT)}:{line_number}: '
                              'AppArmor unix addr= cannot be a filesystem path; use a file rule')
        if depth:
            errors.append(f'{path.relative_to(ROOT)}:EOF: unclosed brace depth {depth}')
        if not text.endswith('\n'):
            errors.append(f'{path.relative_to(ROOT)}:EOF: missing final newline')
    counts['apparmor_files'] = len(files)


def _awk_regex_slash_issues(program: str) -> list[str]:
    """Find unescaped slash bytes inside AWK regexp bracket expressions.

    This is a lexical portability check, not an AWK parser. Strings, comments,
    and division operators have separate states. Within an identified regexp,
    track bracket expressions only to diagnose the nonportable spelling:
    BusyBox terminates the token at its first unescaped slash even in a class.
    Native parser and behavior checks remain independent requirements.
    """
    issues: list[str] = []
    position = 0
    operand = True
    previous = ''
    parentheses: list[bool] = []
    token = re.compile(r'[A-Za-z_][A-Za-z0-9_]*|(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?')
    while position < len(program):
        char = program[position]
        if char.isspace():
            if char == '\n':
                operand = True
            position += 1
            continue
        if program.startswith('\\\n', position):
            position += 2
            continue
        if char == '#':
            end = program.find('\n', position)
            position = len(program) if end < 0 else end
            continue
        if char == '"':
            position += 1
            while position < len(program):
                if program[position] == '\\':
                    position += 2
                elif program[position] == '"':
                    position += 1
                    break
                else:
                    position += 1
            operand = False
            previous = 'string'
            continue
        if char == '/' and operand:
            position += 1
            bracket = False
            first = False
            negation = False
            while position < len(program):
                char = program[position]
                if char == '\\':
                    position += 2
                    first = False
                    continue
                if char == '/' and not bracket:
                    position += 1
                    break
                if char == '/' and bracket:
                    line = program.count('\n', 0, position) + 1
                    column = position - program.rfind('\n', 0, position)
                    issues.append(f'{line}:{column}: escape slash inside AWK regexp character class')
                if not bracket and char == '[':
                    bracket, first, negation = True, True, False
                elif bracket:
                    # POSIX named classes, equivalence classes, and collating
                    # elements have an inner closing bracket of their own.
                    if char == '[' and program[position + 1:position + 2] in {':', '=', '.'}:
                        marker = program[position + 1]
                        end = program.find(marker + ']', position + 2)
                        if end >= 0:
                            offset = position + 2
                            while offset < end:
                                if program[offset] == '\\':
                                    offset += 2
                                    continue
                                if program[offset] == '/':
                                    line = program.count('\n', 0, offset) + 1
                                    column = offset - program.rfind('\n', 0, offset)
                                    issues.append(f'{line}:{column}: escape slash inside AWK regexp character class')
                                offset += 1
                            position = end + 2
                            first = False
                            continue
                    if char == ']' and not first:
                        bracket = False
                    elif char == '^' and first and not negation:
                        negation = True
                    else:
                        first = False
                position += 1
            operand = False
            previous = 'regexp'
            continue
        match = token.match(program, position)
        if match:
            previous = match[0]
            operand = previous in {'if', 'while', 'for', 'do', 'else', 'return', 'print', 'printf',
                                   'exit', 'delete', 'in', 'BEGIN', 'END', 'next', 'nextfile'}
            position += len(previous)
            continue
        if char == '(':
            parentheses.append(previous in {'if', 'while', 'for'})
            operand = True
        elif char == ')':
            operand = parentheses.pop() if parentheses else False
        elif char == ']':
            operand = False
        elif program[position:position + 2] in {'++', '--'}:
            position += 2
            previous = 'increment'
            continue
        else:
            operand = True
        previous = char
        position += 1
    return issues


def _function_awk_literal(source: str, name: str) -> tuple[str, int]:
    """Decode the one multiline AWK literal in a known owning shell function."""
    function = re.search(r'^' + re.escape(name) + r'\(\) \{\n.*?^\}', source, re.M | re.S)
    if function is None:
        raise ValueError('missing AWK owner function: ' + name)
    calls = list(re.finditer(r"^[ \t]+LC_ALL=C[ \t]+awk\b[^\n]*[ \t]'[ \t]*\n", function[0], re.M))
    if len(calls) != 1:
        raise ValueError('expected exactly one literal AWK program in ' + name)
    start = function.start() + calls[0].start() + calls[0][0].rfind("'")
    body, _ = _literal_shell_word(source, start)
    return body, source.count('\n', 0, start) + 1


def check_awk_literal_portability(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Protect ownership, CrowdSec and phase-plan literals independently of Mawk."""
    publication = DEBIAN_ROOT / 'scripts/common/modules/target-publication.sh'
    crowdsec = DEBIAN_ROOT / 'scripts/late/crowdsec.sh'
    plan = DEBIAN_ROOT / 'scripts/common/modules/installation-plan.sh'
    if not {publication, crowdsec, plan, Path(__file__).resolve()}.intersection(paths):
        return
    checked = 0
    for path, function in ((publication, 'installer_target_ownership_filter'),
                           (crowdsec, 'crowdsec_stage_logging_overlay'),
                           (plan, 'installer_plan_stage_records')):
        body, line = _function_awk_literal(_read_text(path), function)
        for issue in _awk_regex_slash_issues(body):
            errors.append(f'{path.relative_to(ROOT)}:{line}: {function}: {issue}')
        checked += 1
    source = _read_text(publication)
    for name, mode, input_name in (('import', 'validate', 'ownership_input'),
                                  ('snapshot', 'snapshot', 'ownership_journal')):
        caller = re.search(r'^installer_target_ownership_' + name + r'\(\) \(\n.*?^\)', source, re.M | re.S)
        call = f'installer_target_ownership_filter {mode} "${input_name}"'
        if caller is None or call not in caller[0] or re.search(r'\bawk\s', caller[0]):
            errors.append('ownership ' + name + ' must delegate to the one shared AWK grammar')
    counts['awk_portable_owner_literals'] = checked


def check_target_render_contract(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Check the pre-late producer/consumer interface without running hooks."""
    hook = DEBIAN_ROOT / 'hooks/installer/base-stage.d/00rendertarget'
    renderer = DEBIAN_ROOT / 'scripts/common/render.pl'
    dispatch = DEBIAN_ROOT / 'scripts/late/dispatch.sh'
    early = DEBIAN_ROOT / 'hooks/installer/d-i/early.sh'
    stage_table = DEBIAN_ROOT / 'hooks/installer/class-dispatch.tsv'
    prepkg = DEBIAN_ROOT / 'hooks/installer/pre-pkgsel.d/50-class-plan.sh'
    dkms = DEBIAN_ROOT / 'hooks/installer/pre-pkgsel.d/90secure-boot-dkms.sh'
    software = DEBIAN_ROOT / 'scripts/late/software.sh.tmpl'
    runtime_map = DEBIAN_ROOT / 'scripts/common/modules/files-logging.sh'
    owners = {hook, renderer, runtime_map, dispatch, early, stage_table, prepkg, dkms, software, DEBIAN_ROOT / 'repo.env',
              DEBIAN_ROOT / 'hooks/installer/di.env',
              DEBIAN_ROOT / 'scripts/common/bootstrap.sh', Path(__file__).resolve()}
    if not owners.intersection(paths) and not any(
            path.is_relative_to(DEBIAN_ROOT / 'scripts') or path.is_relative_to(TARGET_ROOT)
            for path in paths):
        return
    preparation, consumer, startup = map(_read_text, (hook, dispatch, early))
    renderer_text = _read_text(renderer)
    map_text = _read_text(runtime_map)
    # These are source contracts, not a substitute for isolated Perl -c.
    # A slash inside a /.../ character class still closes Perl's delimiter.
    # Keep paired delimiters and encode delimiter/interpolation bytes explicitly
    # so this grammar cannot regress to the original ambiguous literal spelling.
    phase = re.search(r'\$context->\{PHASE\}\s*=~\s*m\{(\\A\[[^\n]+?\]\+\\z)\}', renderer_text)
    if (phase is None or re.search(r'\\x2[fF]', phase[1]) is None
            or r'\x40' not in phase[1] or '/' in phase[1] or '@' in phase[1]):
        errors.append('publication phase grammar requires paired Perl delimiters and explicit slash/at-sign bytes')
    else:
        grammar = re.compile(phase[1].replace(r'\z', r'\Z'))
        alphabet = set('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./@+:-')
        if any(bool(grammar.fullmatch(chr(number))) != (chr(number) in alphabet)
               for number in range(256)) or grammar.fullmatch(''):
            errors.append('publication phase grammar differs from its bounded ASCII interface')
    service_owner = target_source('usr/local/lib/perl5/site_perl/labwc-security-action/LabwcSecurityAction/Root.pm.tmpl')
    service = re.search(r'^sub _validate_service_name \{\n(.*?)^\}',
                        _read_text(service_owner), re.M | re.S)
    service_grammar = re.search(r'\$name\s*=~\s*/(\\A\[[^\]\n]+\]\+\\z)/', service[1]) if service else None
    if (service_grammar is None or r'\@_' not in service_grammar[1]
            or re.search(r'(?<!\\)@_', service_grammar[1])):
        errors.append('service-name validation must not interpolate Perl argument arrays into its character class')
    counts['perl_grammar_regression_contracts'] = 2
    canonical_fields = {key for key, _ in _runtime_path_schema_rows()}
    matcher = re.search(r'sub path_bytes \{.*?\$data =~ s\{(.*?)\}\{mapped\(', renderer_text, re.S)
    probe = re.search(r"installer_contains_unresolved_path_placeholders\(\) \{.*?grep -Eq '([^']+)'", map_text, re.S)
    for label, pattern in (('batch renderer', matcher[1] if matcher else ''),
                           ('publication fast path', probe[1] if probe else '')):
        missed = sorted(name for name in canonical_fields
                        if not re.fullmatch(pattern, '__INSTALLER_' + name + '__'))
        if not pattern or missed:
            errors.append(label + ' omits canonical runtime-map fields: ' + ', '.join(missed))
    counts['canonical_render_fields'] = len(canonical_fields)
    # Fixed source members are local interfaces, including quoted filenames
    # containing spaces. Resolve them as data against the shared seed, never
    # through a removed FILE_* catalog or by executing a shell expression.
    source_word = (r'(?:"(?:hooks|scripts|frontends)/[^"\n$]+"|'
                   r"'(?:hooks|scripts|frontends)/[^'\n$]+'|"
                   r'''(?:hooks|scripts|frontends)/[^\s;)'"$]+)''')
    plain_call = re.compile(
        r'^\s*(?:desktop_stage_role_asset|stage_target_asset|devops_stage_target_asset)\s+'
        r'(?:"\$\(\s*installer_repo_file_value\s+)?(' + source_word + r')', re.M)
    plain_calls = 0
    for script in sorted((DEBIAN_ROOT / 'scripts').rglob('*.sh*')):
        records = re.sub(r'\\\n[ \t]*', ' ', _read_text(script))
        for match in plain_call.finditer(records):
            relative = shlex.split(match[1])[0]
            asset = DEBIAN_ROOT / relative
            plain_calls += 1
            if not asset.is_file() or asset.is_symlink():
                errors.append(f'{script.relative_to(ROOT)}: missing plain staging source: {relative}')
                continue
            data = asset.read_bytes()
            if b'\0' in data:
                continue
            names = {name.decode('ascii') for name in re.findall(
                rb'__INSTALLER_([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*)__', data)}
            deferred = sorted(name for name in names - canonical_fields if not name.startswith('LOG_'))
            if deferred:
                errors.append(f'{script.relative_to(ROOT)}: plain staging bypasses typed rendering: '
                              f'{relative}: {", ".join(deferred)}')
    if plain_calls < 500:
        errors.append('fixed plain staging source coverage unexpectedly fell below 500 calls')
    counts['plain_staging_sources'] = plain_calls
    option_pattern = re.search(r'--\((scripts\|[^)]+)\)', renderer_text)
    options = {'--' + key for key in option_pattern[1].split('|')} if option_pattern else set()
    options.add('--cleanup')
    call = re.search(r'"\$\{DIR_USR_BIN\}/perl" -f[^\n]*', preparation.replace('\\\n', ' '))
    requested = set(re.findall(r'--[a-z][a-z0-9-]+', call[0])) if call else set()
    if not call or requested != options - {'--cleanup'}:
        errors.append('pre-late hook passes an unsupported target renderer option')
    # These selectors classify the complete captured tree, including the
    # unselected role. Running them through an installed-asset family guard
    # aborts server preparation before the renderer can filter publications.
    renderer_words = shlex.split(call[0]) if call else []
    classifier_contracts = {
        '--appearance-python': '$DIR_TARGET_PY/labwc_appearance',
        '--appearance-registry': '$DIR_TARGET_SHARE_LABWC_APPEARANCE/fields.json.tmpl',
    }
    for option, expected in classifier_contracts.items():
        actual = (renderer_words[renderer_words.index(option) + 1]
                  if option in renderer_words and renderer_words.index(option) + 1 < len(renderer_words)
                  else '')
        actual = re.sub(r'\$\{(DIR_[A-Z0-9_]+)\}', r'$\1', actual)
        if actual != expected:
            errors.append('base renderer classifier must use its captured-source root without role-gated asset acquisition: ' + option)
    counts['base_render_captured_classifiers'] = len(classifier_contracts)
    stage_contexts = []
    for number, line in enumerate(preparation.splitlines(), 1):
        context = re.fullmatch(r'prepare_context ([0-9]+) ([a-z][a-z0-9_]+)', line)
        if context:
            if int(context[1]) != number:
                errors.append(f'base render diagnostic source line is stale: {context[2]}')
            stage_contexts.append(context[2])
    if (len(stage_contexts) < 15 or len(stage_contexts) != len(set(stage_contexts))
            or not {'prepare_system_template_map', 'render_target_source_snapshot',
                    'commit_target_ownership', 'publish_target_render_ready'}.issubset(stage_contexts)):
        errors.append('base render preparation requires distinct source-bound stage diagnostics')
    counts['base_render_stage_contexts'] = len(stage_contexts)
    # A target_exec barrier is too late when the installer shell itself reads
    # queued bytes. Check the actual direct-reader boundary in each shared
    # helper rather than disabling batching for every caller.
    direct_readers = (
        ('scripts/late/storage-maintenance.sh', 'normalize_target_tmpfiles_directory_policy',
         '[ -r "${TARGET_ROOT}${tmpfiles_policy_path}" ]'),
        ('scripts/late/target-assets.sh', 'stage_target_logging_foundation',
         'for forwarding_asset in '),
        ('scripts/desktop/components/devices-network.sh', 'desktop_assert_role_target_template_resolved',
         'desktop_assert_no_unresolved_template_placeholders '),
    )
    for member, function, reader in direct_readers:
        text = _read_text(DEBIAN_ROOT / member)
        body = re.search(r'^' + re.escape(function) + r'\(\) \{\n(.*?)^\}', text, re.M | re.S)
        if not body:
            errors.append('missing direct-reader publication boundary: ' + function)
            continue
        flush_at = body[1].find('installer_asset_batch_flush || return $?')
        read_at = body[1].find(reader)
        if flush_at < 0 or read_at < 0 or flush_at >= read_at:
            errors.append('queued assets must be flushed before installer-side reading: ' + function)
    counts['publication_direct_reader_barriers'] = len(direct_readers)
    if not re.search(r'bootstrap_source_common_support_libs[^\n]*\sfetch\s+target(?:\s|$)', preparation):
        errors.append('pre-late hook must load fetch and target libraries before theme preparation')
    if (startup.count('installer_repo_file_value hooks/installer/base-stage.d/00rendertarget') != 1
            or '"${DIR_INSTALLER_BASE_INSTALLER_D}/00rendertarget"' not in startup
            or 'installer_guard_hook "$base_hook" base' not in startup
            or re.search(r'RENDER_TARGET|installer\.target-render', _read_text(stage_table))
            or 'FILE_INST_FINISH_RENDER_TARGET' in startup
            or 'FILE_INST_PREPKG_RENDER_TARGET' in startup):
        errors.append('target preparation must be the one supervised first base-installer hook')
    if ('/hook-component-bootstrap-base.postinst.running' not in preparation
            or 'postinst.done' in preparation or 'apt-install ' in preparation):
        errors.append('first base hook must run inside bootstrap-base without waiting for itself or installing packages')
    if ('installer_exec_logged "$prepare_output"' not in preparation
            or 'installer_run_bounded "$prepare_limit" installer_exec_logged' not in preparation
            or 'python3' in preparation):
        errors.append('target preparation lost its bounded Perl logger or tty4 diagnostic stream')
    if ('BOOTSTRAP_PREPARED_SOURCE_ROOT:-' not in consumer
            or '/perl" -f' not in consumer or '--cleanup' not in consumer):
        errors.append('late dispatch must require and retire its prepared source workspace')
    software_text = _read_text(software)
    if ('BOOTSTRAP_PREPARED_SOURCE_ROOT:-' not in software_text
            or 'managed software requires the completed base-stage target payload' not in software_text):
        errors.append('managed software must require completed base-stage rendering before downloads')
    prepkg_text = _read_text(prepkg)
    if ('BOOTSTRAP_PREPARED_SOURCE_ROOT:-' not in prepkg_text
            or 'installer_apply_scalar_placeholders' in prepkg_text
            or 'render_pre_pkgsel_asset' in _read_text(dkms)
            or 'installer_apply_scalar_placeholders' in _read_text(dkms)
            or "qw(scripts target installer)" not in renderer_text):
        errors.append('pre-pkgsel must consume batch-rendered installer/DKMS helpers without rendering again')
    if ('/env" -i' not in preparation or '/perl" -f' not in preparation
            or '--family "$INSTALLER_HOST_VARIANT"' not in preparation):
        errors.append('target renderer lost its isolated interpreter or selected-family arguments')
    imports = re.findall(r'^use ([A-Za-z][A-Za-z0-9_:]*)\b', renderer_text, re.M)
    if set(imports) - {'strict', 'warnings', 'bytes', 'constant', 'Fcntl', 'File::Temp', 'IO::Handle'}:
        errors.append('early renderer requires a module outside the reviewed perl-base support set')
    publication = _read_text(DEBIAN_ROOT / 'scripts/common/modules/target-publication.sh')
    batch = renderer_text.split('sub publish_assets {', 1)[-1].split('\nsub main {', 1)[0]
    for token in ('sub publication_plan {', 'publication-plan-v1', '$count <= 1033',
                  '$fields_total += $count', 'truncated or excessive publication field',
                  'sub publication_source {', 'missing or ambiguous publication source owner',
                  'publication source belongs to another suite',
                  'publication source belongs to an incompatible target role',
                  'publication plan belongs to another prepared payload',
                  'O_RDONLY | O_NOFOLLOW | O_NONBLOCK', 'unsafe publication ancestry',
                  '$info->[3] == 1', 'same_metadata(\\@before, \\@after)',
                  'chown(0, 0, $temporary) == 1', 'rename($temporary, $path)',
                  'publication_markers($result, $kind, $source)',
                  'if (!exists($sources{$source}))', 'publication inputs',
                  'publication_sync($_, 0, $policy) for sort keys %written;',
                  'asset_batch phase=', 'unique_input_bytes=', 'elapsed_seconds='):
        if token == 'publication inputs':
            # One prepared membership read and one canonical map load per
            # bounded interpreter invocation, outside the operation loop.
            if (batch.count('read_regular("$root/inputs/prepared-members"') != 1
                    or batch.count('value_map("$root/inputs/paths.map")') != 1):
                errors.append('publication must bind its prepared members and canonical paths once per batch')
        elif token not in renderer_text:
            errors.append('shared publication contract omits ' + token)
    operation_loop = batch.find('for my $row (@{publication_plan(')
    preflight = batch.find('my $before = publication_destination($path, $policy, -1)')
    journal = batch.find('write_file("$work/ownership.pending"')
    mutation = batch.find('write_file($path, $candidate->[0]')
    commit = batch.find('rename("$work/ownership.pending", "$work/ownership.tsv")')
    if not (0 <= operation_loop < preflight < journal < mutation < commit):
        errors.append('publication must resolve/render/preflight the full batch before atomic writes and ownership commit')
    if (r'\Averified-v1 ' not in renderer_text or 'for my $name (sort keys %$blocks)' not in renderer_text
            or '$count == 1' not in renderer_text or 'keys(%blocks) == 3' not in batch):
        errors.append('publication lost verified provenance or exact declared deferred-block handling')
    if re.search(r'\b(?:system|exec)\s*\(|\bqx\s*[({/]', batch):
        errors.append('shared publication must not launch per-asset external programs')
    flush = publication.split('installer_asset_batch_flush() {', 1)[-1].split('\n}', 1)[0]
    for token in ('installer_run_bounded 120 chroot "$TARGET_ROOT"', '"${DIR_USR_BIN}/env" -i',
                  '--publish ', 'installer_target_ownership_import "$INSTALLER_ASSET_BATCH_WORK/ownership.tsv"',
                  ': >"$INSTALLER_ASSET_BATCH_WORK/failed"', 'return "$installer_asset_status"'):
        if token not in flush:
            errors.append('bounded publication flush omits ' + token)
    if flush.count('"${DIR_USR_BIN}/perl" -f') != 1:
        errors.append('each nonempty publication flush requires exactly one target Perl invocation')
    context_source = re.search(r'my @source_keys = qw\((.*?)\);', batch, re.S)
    context_fixed = re.search(r'my @context_keys = \(qw\((.*?)\), @source_keys\);', batch, re.S)
    context_keys = set((context_source[1] if context_source else '').split()) | set(
        (context_fixed[1] if context_fixed else '').split())
    begin = publication.split('installer_asset_batch_begin() {', 1)[-1].split('\n}', 1)[0]
    shell_keys = set(re.findall(r'([A-Z][A-Z0-9_]*)=(?:1|%s)\\n', begin))
    if len(context_keys) < 12 or context_keys != shell_keys:
        errors.append('shell publication context and bounded Perl context schema differ')
    for name, owner in (
            ('target command', DEBIAN_ROOT / 'scripts/common/target.sh'),
            ('legacy renderer', runtime_map),
            ('shell asset reader', DEBIAN_ROOT / 'scripts/late/target-assets.sh')):
        if 'installer_asset_batch_flush' not in _read_text(owner):
            errors.append(name + ' must flush pending publication before consuming target state')
    target_calls = _read_text(DEBIAN_ROOT / 'scripts/common/target.sh')
    execution = target_calls.split('target_exec() (', 1)[-1].split('\n)', 1)[0]
    if not (0 <= execution.find('installer_asset_batch_flush') < execution.find('target_root=$(target_root_dir)')):
        errors.append('every target wrapper must flush at the shared target_exec boundary before target execution')
    session_assets = _read_text(DEBIAN_ROOT / 'scripts/desktop/components/user-session.sh')
    queued_scope = session_assets.find('app-.scope.d/50-session-labwc.conf')
    session_barrier = session_assets.find('installer_asset_batch_flush', queued_scope)
    mode_consumer = session_assets.find('for global_user_systemd_dir in', queued_scope)
    if not (0 <= queued_scope < session_barrier < mode_consumer):
        errors.append('user-session directory modes must consume completed queued drop-in publication')
    late_assets = _read_text(DEBIAN_ROOT / 'scripts/late/target-assets.sh')
    for token in ('if [ "$asset_kind" = helper-doc ]; then',
                  'case "$asset_source" in "$DIR_TARGET_DOCS/"*)',
                  'case "$asset_target" in "$DIR_DATA_DOCS/"*)',
                  '[ "$asset_mode" = 0644 ]',
                  'target_asset_assert_no_unresolved_installer_placeholders "$asset_work/payload" "helper doc $asset_source"',
                  '"${DIR_DATA_DOCS}/README.md" 0644 helper-doc',
                  'target_chown_helper_doc_path "$doc_target_path"'):
        if token not in late_assets:
            errors.append('dedicated account-owned helper-doc publication omits ' + token)
    if ('installer_asset_batch_begin desktop-assets' not in _read_text(
            DEBIAN_ROOT / 'scripts/desktop/components/target-assets.sh')
            or 'installer_asset_batch_begin logging-foundation' not in _read_text(
                DEBIAN_ROOT / 'scripts/late/target-assets.sh')):
        errors.append('desktop and logging assets must retain explicit publication batches')
    for token in ('rows[$1]=$0', 'kinds[path] != "deleted"', '++count > 20000',
                  'installer_target_ownership_snapshot()', 'installer_target_ownership_import()'):
        if token not in publication:
            errors.append('bounded exact-key target ownership journal omits ' + token)
    if 'sha256sum' in publication:
        errors.append('ownership bookkeeping must not hash every destination path')
    final_owner = _read_text(DEBIAN_ROOT / 'hooks/installer/finish-install.d/94zz-99-validate-target')
    retirement_markers = (
        '# Retained source-member interface for older installer inventories.',
        '# Fresh installations no longer stage or run the final target validation sweep.',
        '# Stage exit statuses and the finish/reboot lifecycle own completion records.',
    )
    final_owner_retired = all(marker in final_owner for marker in retirement_markers) and bool(
        re.search(r'^exit 0\s*$', final_owner, re.M)
    )
    if final_owner_retired:
        counts['retired_final_target_validation'] = 1
    else:
        for token in ('installer_target_ownership_snapshot >"$owned_record"',
                      '[ "$owned_count" -le 10000 ]', '[ "$owned_count" -gt 0 ]',
                      '"$(installer_metadata_value "$owned_file" links)" = 1',
                      '[ "$owned_real" = "$owned_file" ]'):
            if token not in final_owner:
                errors.append('final mutable target verification omits ' + token)
    counts['publication_context_fields'] = len(context_keys)
    counts['publication_batch_interpreters'] = flush.count('"${DIR_USR_BIN}/perl" -f')
    counts['publication_journal_snapshot_owners'] = 1
    target_contract = _read_text(DEBIAN_ROOT / 'hosts/installer/runtime.env')
    if re.search(r'^DIR_INSTALLER_TARGET_STAGE=', target_contract, re.M):
        errors.append('installer staging state must not enter the installed runtime contract')
    counts['pre_late_render_contracts'] = 1


def check_perl_validation_contract(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Keep native Perl validation wired without invoking an interpreter here."""
    auditor = DEBIAN_ROOT / 'tests/audit_codebase.py'
    preparer = ROOT / 'tools/prepare_syntax_fixture.py'
    makefile = ROOT / 'Makefile'
    init = ROOT / 'tools/test-init.py'
    aggregate = ROOT / 'tools/validate.py'
    owners = {auditor, preparer, makefile, init, aggregate, Path(__file__).resolve()}
    if not owners.intersection(paths):
        return
    audit = _read_text(auditor)
    for required in ("'d-i/debian/'", "'hooks/target'", "'hooks/installer'", "'scripts'", "'hosts'",
                     "'d-i/forky/hooks/target'", "'d-i/trixie/hooks/target'",
                     "'d-i/debian/scripts/common/render.pl'", 'def source_scopes(',
                     'def stage_perl(', 'def rendered_inputs(', 'def audit_status(',
                     'prepare_syntax_fixture(', 'return audit_status(records, perl_only=args.perl_only)'):
        if required not in audit:
            errors.append('canonical Perl audit lost its shared source/rendered-input contract: ' + required)
    for path in (auditor, preparer):
        source = _read_text(path)
        guard = source.find('_require_test_isolation()')
        imports = source.find('\nimport argparse')
        if not 0 <= guard < imports:
            errors.append(str(path.relative_to(ROOT)) + ': native validation must refuse host execution before fixture imports')
    make = _read_text(makefile)
    recipe = re.search(r'^check-perl:\n((?:\t[^\n]*\n)+)', make, re.M)
    guarded = re.search(r'^([^#\n]*\bcheck-perl\b[^#\n]*): test-isolation$', make, re.M)
    if (not recipe or not guarded or not re.search(r'^check: check-perl$', make, re.M)
            or any(token not in recipe[1] for token in (
                'd-i/debian/tests/audit_codebase.py', '--perl-only', '--prepare-suite', '--prepare-family'))):
        errors.append('make check must require the guarded canonical prepared Perl gate')
    for path, key in ((init, 'check'), (aggregate, 'perl-check')):
        tree = ast.parse(_read_text(path), filename=str(path))
        commands = []
        for node in ast.walk(tree):
            if isinstance(node, ast.Dict):
                commands.extend(value for label, value in zip(node.keys, node.values)
                                if isinstance(label, ast.Constant) and label.value == key)
            elif (isinstance(node, ast.Tuple) and node.elts
                  and isinstance(node.elts[0], ast.Constant) and node.elts[0].value == key):
                commands.append(node)
        required = {'d-i/debian/tests/audit_codebase.py', '--perl-only', '--prepare-suite', '--prepare-family'}
        if not any(required.issubset({node.value for node in ast.walk(command)
                                     if isinstance(node, ast.Constant) and isinstance(node.value, str)})
                   for command in commands):
            errors.append(str(path.relative_to(ROOT)) + ': prepared Perl gate is absent from the isolated stage list')
    if 'd-i/debian/releases' in _read_text(aggregate):
        errors.append('aggregate validation still expects retired generated release directories')
    counts['prepared_perl_validation_entrypoints'] = 3


def check_download_contract(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Inspect transfer interfaces as data; never execute an acquisition helper."""
    owners = (DEBIAN_ROOT / 'scripts', TARGET_ROOT, DEBIAN_ROOT / 'hosts/profiles')
    sources = [path for path in paths if any(path.is_relative_to(owner) for owner in owners)
               and path.suffix not in {'.gz', '.png', '.jpg', '.ico'}]
    if not sources:
        return
    checked = calls = 0
    supported = {'label', 'url', 'destination', 'content_policy', 'allowed_hosts',
                 'user_agent', 'response_metadata'}
    for path in sources:
        try:
            source = path.read_text(encoding='utf-8')
        except UnicodeError:
            continue
        relative = path.relative_to(ROOT)
        for obsolete in ('--max-filesize', 'invalid installer artifact byte bound',
                         'MAX_DOWNLOAD_BYTES', 'release_deb_limits'):
            if obsolete in source:
                errors.append(f'{relative}: obsolete download byte-bound contract: {obsolete}')
        if re.search(r'\b(?:SOFTWARE|DEVOPS|LABWC|WHISPER|LLAMA|FILEN|SCRCPY|RESCTL_BENCH|'
                     r'ANDROID_PLATFORM_TOOLS|SAMLOADER|SNANDER)[A-Z0-9_]*_MIN(?:IMUM)?_BYTES\b', source):
            errors.append(f'{relative}: stale download minimum-byte policy')
        for call in re.finditer(r'->download\(\s*(.*?)^\s*\);', source, re.MULTILINE | re.DOTALL):
            fields = set(re.findall(r'^\s*([a-z_]+)\s*=>', call[1], re.MULTILINE))
            if not fields:
                continue
            calls += 1
            if fields - supported:
                errors.append(f'{relative}: unsupported HTTP download fields: '
                              + ', '.join(sorted(fields - supported)))
        if path.name == 'snander-install.py.tmpl':
            tree = ast.parse(source)
            verifier = next((node for node in tree.body if isinstance(node, ast.FunctionDef)
                             and node.name == 'archive_digest'), None)
            if verifier is None or not any(
                isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                and node.func.attr == 'read' and len(node.args) == 1
                and isinstance(node.args[0], ast.Constant) and node.args[0].value == 65536
                for node in ast.walk(verifier)
            ):
                errors.append(f'{relative}: archive hashing must stream fixed chunks')
        if path.name == 'calendar-install.py':
            tree = ast.parse(source)
            owned = sum(isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                        and node.func.id == 'download'
                        for context in ast.walk(tree) if isinstance(context, ast.With)
                        for item in context.items for node in [item.context_expr])
            if owned != 2 or 'data = bytearray()' in source or 'tempfile.TemporaryFile(' not in source:
                errors.append(f'{relative}: downloaded archives must use caller-owned private files')
        checked += 1

    helper = target_source('usr/local/libexec/installer-artifact-fetch').read_text(encoding='utf-8')
    if '@ARGV == 3 || @ARGV == 4' not in helper:
        errors.append('installer artifact fetch must accept URL, destination, content policy, optional hosts')
    servicing = target_source('usr/local/lib/perl5/site_perl/apt-repo-local/'
                              'APTRepoLocal/Servicing/Postman.pm').parent
    perl_owners = sorted(servicing.glob('*.pm*'))
    # Inspect the complete shared owner set. This catches leftover transfer
    # variables as source data; it is not a Perl compiler or a lexical proof.
    for path in perl_owners:
        source = _read_text(path)
        for variable in ('size', 'minimum', 'maximum', 'minimum_bytes', 'maximum_bytes',
                         'download_limit', 'archive_limit', 'release_bytes'):
            if (re.search(r'\$' + variable + r'\b', source)
                    and not re.search(r'\b(?:my|our|state)\s+(?:\$' + variable
                                      + r'\b|\([^;]*\$' + variable + r'\b)', source)):
                errors.append(f'{path.relative_to(ROOT)}: undeclared transfer variable ${variable}')
    counts['download_contract_perl_owners'] = len(perl_owners)

    policy_path = target_source('usr/local/share/software/software-release-policy.json.tmpl')
    template = policy_path.read_text(encoding='utf-8')
    tokens = set(re.findall(r'__INSTALLER_([A-Z0-9_]+)__', template))
    shape = re.sub(r'"__INSTALLER_[A-Z0-9_]+__"', '"fixture"', template)
    shape = re.sub(r'__INSTALLER_[A-Z0-9_]+__', '1', shape)
    policy = json.loads(shape)
    if set(policy) != {'schema', 'generic_deb', 'service_urls', 'metadata_limits',
                       'postman', 'discord', 'ledger'}:
        errors.append('managed software release policy has obsolete or missing sections')
    for component, entry in policy.get('generic_deb', {}).items():
        if set(entry) != {'url'}:
            errors.append(f'{component}: generic download policy must contain only its URL')
    if set(policy.get('metadata_limits', {})) != {'maximum_bytes'}:
        errors.append('release metadata must retain only its local parser budget')
    if set(policy.get('postman', {})) != {'maximum_extracted_bytes', 'maximum_members',
                                       'metadata_maximum_bytes'}:
        errors.append('Postman policy must contain extraction and local parser budgets only')
    if any(re.search(r'(?:^|_)(?:minimum|maximum)_bytes$', key)
           and key not in {'host_tar_maximum_bytes', 'module_tar_maximum_bytes', 'tree_maximum_bytes'}
           for key in policy.get('discord', {})):
        errors.append('Discord policy retains a transfer byte bound')
    ledger_fields = {'requested_latest_url', 'metadata_url', 'checksums_base_url', 'public_key_sha256',
                     'appimage_maximum_extracted_bytes', 'appimage_maximum_members'}
    if set(policy.get('ledger', {})) != ledger_fields:
        errors.append('Ledger policy has stale transfer fields or missing verification/extraction fields')
    software = (DEBIAN_ROOT / 'scripts/late/software.sh.tmpl').read_text(encoding='utf-8')
    start = software.index('hooks/target/usr/local/share/desktop/software/software-release-policy.json.tmpl')
    end = software.index('  software_stage_seed_asset', start)
    rendered = set(re.findall(r'^\s+(SOFTWARE_[A-Z0-9_]+)\s+"\$\1"', software[start:end], re.MULTILINE))
    if rendered != tokens:
        errors.append('software release-policy renderer fields differ from template placeholders')
    counts['download_contract_sources'] = checked
    counts['download_contract_calls'] = calls
    counts['download_policy_render_fields'] = len(tokens)


def check_chatgpt_bootstrap_contract(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Cross-check role ownership, payload paths and failure handling as data."""
    software_path = DEBIAN_ROOT / 'scripts/late/software.sh.tmpl'
    chatgpt_path = target_source('usr/local/lib/perl5/site_perl/apt-repo-local/APTRepoLocal/Servicing/ChatGPT.pm')
    http_path = target_source('usr/local/lib/perl5/site_perl/apt-repo-local/APTRepoLocal/Servicing/HTTP.pm')
    cli_path = target_source('usr/local/lib/perl5/site_perl/apt-repo-local/APTRepoLocal/Servicing/CLI.pm')
    if not set(paths) & {software_path, chatgpt_path, http_path, cli_path, Path(__file__).resolve()}:
        return
    software = _read_text(software_path)
    chatgpt = _read_text(chatgpt_path)
    bootstrap = software.split('software_enable_chatgpt_integration() {', 1)[1].split(
        '\nsoftware_restore_managed_apparmor_profiles()', 1)[0]
    if (bootstrap.count('--bootstrap-chatgpt') != 1 or 'attempt_in_target' in bootstrap
            or re.search(r'^\s*while\b', bootstrap, re.M) or 'return 75' in bootstrap):
        errors.append('ChatGPT bootstrap must execute its package transaction once; HTTP owns transfer retries')
    if 'run_in_target' not in bootstrap or 'three-retry budget' in bootstrap:
        errors.append('ChatGPT bootstrap masks its stage diagnostic or skips a required application')
    if ('INSTALLER_LOG_CONTEXT=desktop.software' not in software
            or 'export INSTALLER_LOG_CONTEXT' not in software
            or 'software_fatal_status "$selected_status"' not in software):
        errors.append('managed software loses its component or original worker failure status')
    target = _read_text(DEBIAN_ROOT / 'scripts/common/target.sh')
    if ('target_record_command_failure "$1" "$2" "$4"' not in target
            or '"${INSTALLER_LOG_CONTEXT:-in-target}" "$target_failure_detail"' not in target
            or 'tail -c 4096 "$3"' not in target):
        errors.append('target command failure receipt loses its bounded managed diagnostic or component')
    worker_call = re.search(r'^\s*"\$selected_worker"\s*$', software, re.M)
    worker_context = re.search(r'installer_operation_context_repo scripts/late/software.sh.tmpl (\d+) '
                               r'"install_managed_application:', software)
    if (worker_call is None or worker_context is None
            or int(worker_context[1]) != software.count('\n', 0, worker_call.end()) + 1):
        errors.append('managed software worker context names a stale source line')
    rendered_bootstrap = _render_installer_path_placeholders(bootstrap)
    rendered_spec = _render_installer_path_placeholders(chatgpt.split('sub spec {', 1)[1].split('\nsub enabled', 1)[0])
    resources = _render_installer_path_placeholders('__INSTALLER_PATH_DIR_USR_LIB_CHATGPT_RESOURCES__')
    codex = _render_installer_path_placeholders('__INSTALLER_PATH_DIR_USR_LIB_CHATGPT_CODEX__')
    for path in (codex, resources + '/codex-code-mode-host'):
        if path not in rendered_bootstrap or path not in rendered_spec:
            errors.append('ChatGPT installer and servicing disagree on required payload: ' + path)
    if codex + '/code-mode-host' in rendered_bootstrap:
        errors.append('ChatGPT installer treats the Codex executable as a directory')
    classes = re.search(r'^software_run_selected_app "([^"]+)" "ChatGPT/Codex desktop" '
                        r'software_enable_chatgpt_integration\b', software, re.M)
    if classes is None or set(classes[1].split()) != {'role/desktop/medium', 'role/desktop/full'}:
        errors.append('ChatGPT must be selected automatically by desktop medium/full roles')
    http = _read_text(http_path)
    if ('$self->_transport_failure($result)' not in http
            or 'HTTP $http_status' not in http or '--globoff' not in http):
        errors.append('HTTP acquisition loses safe transport diagnostics or literal URL handling')
    vendor = _read_text(target_source('usr/local/libexec/apt-repo-local-vendor'))
    for module in ('Discord', 'Postman', 'Tuta', 'Ledger'):
        if re.search(r'^use APTRepoLocal::Servicing::' + module + r';', vendor, re.M):
            errors.append('ChatGPT configure must not eagerly import sibling vendor module: ' + module)
    if ('require $module;' not in vendor
            or vendor.index('require $module;') < vendor.index("if ($action eq 'configure-chatgpt')")
            or vendor.index('require $module;') > vendor.index('$state->prepare();')):
        errors.append('vendor module loading must follow action validation and precede state mutation')
    counts['chatgpt_bootstrap_contracts'] = 1
    counts['chatgpt_payload_path_contracts'] = 2


def check_runtime_path_publication(paths: list[Path], errors: list[str], counts: dict[str, int]) -> None:
    """Materialize shared path contracts as data and inspect loader ordering.

    No installer function, target helper or fixture is sourced or executed.
    These shared-contract lookups cover sibling scripts and target assets when
    their common publisher, bootstrap or one of the affected entrypoints changes.
    """
    owners = {DEBIAN_ROOT / name for name in (
        'scripts/common/bootstrap.sh', 'scripts/common/fetch.sh',
        'scripts/common/modules/repository-apt.sh',
        'scripts/common/modules/files-logging.sh', 'hosts/installer/runtime.env',
        'scripts/late/tailscale.sh', 'scripts/late/devops.sh.tmpl',
        'scripts/late/devops/main-orchestration.sh', 'scripts/late/whisper.sh',
        'scripts/late/llama.sh', 'scripts/late/desktop.sh', 'scripts/desktop/waypaper.sh',
        'hooks/installer/finish-install.d/09-cuda-legacy-cleanup',
        'hooks/installer/finish-install.d/99-normalize-finish',
        'hooks/installer/finish-install.d/95-normalize-apt',
        'hooks/installer/finish-install.d/94zz-99-validate-target')}
    if not (owners | {Path(__file__).resolve()}).intersection(paths):
        return
    values = dict(_installer_path_token_values())
    published_paths = {}
    for key, variable in _runtime_path_schema_rows():
        if not key.startswith('PATH_'):
            continue
        key = key.removeprefix('PATH_')
        if key != variable:
            errors.append('shared renderer publishes a different runtime path for ' + key)
        published_paths['__INSTALLER_PATH_' + key + '__'] = variable
    marker = re.compile(r'__INSTALLER_PATH_[A-Z0-9_]+__')
    for root, label in ((DEBIAN_ROOT / 'scripts', 'script'), (TARGET_ROOT, 'target')):
        checked = 0
        for path in sorted(root.rglob('*')):
            if not path.is_file() or path.is_symlink() or path.suffix.lower() in BINARY_SUFFIXES:
                continue
            source = _read_text(path)
            tokens = set(marker.findall(source))
            if not tokens:
                continue
            # All selected profiles include this single canonical path owner.
            # Missing names are errors, never replaced with empty strings.
            unresolved = sorted(token for token in tokens if token not in values)
            if unresolved:
                errors.append(f'{path.relative_to(ROOT)}: undefined runtime paths: {unresolved}')
            unpublished = sorted(tokens - published_paths.keys())
            if unpublished:
                errors.append(f'{path.relative_to(ROOT)}: runtime paths absent from the shared renderer: {unpublished}')
            rendered = marker.sub(lambda match: values.get(match[0], match[0]), source)
            if marker.search(rendered):
                errors.append(f'{path.relative_to(ROOT)}: unresolved rendered runtime path')
            checked += 1
        counts[f'runtime_path_{label}_assets'] = checked

    bootstrap = _read_text(DEBIAN_ROOT / 'scripts/common/bootstrap.sh')
    repository = _read_text(DEBIAN_ROOT / 'scripts/common/modules/repository-apt.sh')
    for label, source in (('bootstrap', bootstrap), ('repository', repository)):
        if '"${DIR_REPO_SCRIPTS' not in source or '"${DIR_HOOKS_TARGET' not in source:
            errors.append(f'{label}: path publication does not cover every script/target family')
    module = re.search(r'^bootstrap_module_path\(\) \(\n.*?^\)', bootstrap, re.M | re.S)
    if (module is None or 'bootstrap_fetch_seed_file "$module_seed"' not in module[0]
            or re.search(r'^\s*source_fetch\b', module[0], re.M)):
        errors.append('shell module loader bypasses shared path publication')
    fetch = re.search(r'^installer_fetch_seed_path\(\) \(\n.*?^\)', repository, re.M | re.S)
    if fetch is None:
        errors.append('shared repository publisher is missing')
    else:
        stages = [fetch[0].find(text) for text in (
            'source_fetch "$repository_fetch_seed_base"',
            'installer_apply_scalar_placeholders "$logging_fetch_work/asset"',
            'installer_assert_no_unresolved_path_placeholders "$logging_fetch_work/rendered"',
            'mv -f -- "$logging_fetch_work/asset" "$repository_fetch_destination"')]
        if -1 in stages or stages != sorted(stages):
            errors.append('repository publisher must fetch, render and validate before replacement')
    if 'command -v installer_load_source_library' not in bootstrap:
        errors.append('bootstrap may invoke the partially initialized common library')

    # Renderer dependencies must be token-free: they load before profile paths.
    common = _read_text(DEBIAN_ROOT / 'scripts/common/lib.sh')
    early = {'scripts/common/bootstrap.sh', 'scripts/common/source.sh', 'scripts/common/lib.sh',
             'scripts/common/fetch.sh', 'scripts/common/hook.sh', 'scripts/common/target.sh', 'scripts/common/ssh.sh',
             'scripts/preseed/bootstrap-entry.sh', 'scripts/preseed/apply.sh', 'scripts/preseed/guard-hook.sh',
             'scripts/preseed/answers.sh', 'scripts/early/dispatch.sh', 'scripts/partman/dispatch.sh', 'scripts/late/dispatch.sh'}
    early.update(re.findall(r'bootstrap_source_module "\$\(bootstrap_repo_file_value ([A-Za-z0-9_./@+-]+)\)"', common))
    for member in sorted(early):
        if not (DEBIAN_ROOT / member).is_file():
            errors.append('early script source member is unavailable: ' + member)
        elif marker.search(_read_text(DEBIAN_ROOT / member)):
            errors.append('pre-profile bootstrap dependency contains runtime path tokens: ' + member)
    counts['runtime_path_bootstrap_dependencies'] = len(early)

    tailscale = _read_text(DEBIAN_ROOT / 'scripts/late/tailscale.sh')
    devops = _read_text(DEBIAN_ROOT / 'scripts/late/devops.sh.tmpl')
    for label, source, consumer in (
            ('Tailscale', tailscale, 'fetch_hook_file "$(installer_repo_file_value scripts/late/dbus-broker.sh)"'),
            ('DevOps', devops, 'bootstrap_source_module ')):
        loaded, used = source.find('installer_load_data_env "$host_env"'), source.find(consumer)
        if loaded < 0 or used < 0 or loaded > used:
            errors.append(label + ': profile paths must load before helper rendering')
    if '[ -r "$dbus_helper" ] ||' in tailscale:
        errors.append('Tailscale must not reuse a raw helper cached by a failed older renderer')
    for member, load, consumer in (
            ('scripts/late/desktop.sh', 'late_command_load_host_env', 'fetch_hook '),
            ('scripts/late/whisper.sh', 'installer_load_data_env "$host_env"',
             'whisper_stage_target_asset "$(installer_repo_file_value scripts/late/whisper.sh)"'),
            ('scripts/late/llama.sh', 'installer_load_data_env "$host_env"',
             'bootstrap_fetch_seed_file "$seed_base" "$(installer_repo_file_value scripts/late/llama.sh)"')):
        entrypoint = _read_text(DEBIAN_ROOT / member)
        loaded, used = entrypoint.find(load), entrypoint.find(consumer)
        if loaded < 0 or used < 0 or loaded > used:
            errors.append(member + ': profile paths must load before helper rendering')
    counts['runtime_path_entrypoint_contracts'] = 5
    # d-i launches each finish hook in a fresh shell. The common library and
    # frozen layout state supply no target roots. Check the actual policy
    # handoff before log derivation, source normalization or readiness state.
    finish_contracts = (
        ('09-cuda-legacy-cleanup', 'host_env', 'if installer_cuda_remove_target_source;'),
        ('99-normalize-finish', 'HOST_ENV', 'TARGET_LOG_FILE="${TARGET}${DIR_VAR_LIB_INSTALLER_STATE}/installer.log"'),
        ('95-normalize-apt', 'HOST_ENV', '\nrewrite_apt_http_to_https\n'),
        ('94zz-99-validate-target', 'host_env', 'target_state="${target}${DIR_VAR_LIB_INSTALLER_STATE}"'),
    )
    retirement_markers = (
        '# Retained source-member interface for older installer inventories.',
        '# Fresh installations no longer stage or run the final target validation sweep.',
        '# Stage exit statuses and the finish/reboot lifecycle own completion records.',
    )
    for member, variable, consumer in finish_contracts:
        source = _read_text(DEBIAN_ROOT / 'hooks/installer/finish-install.d' / member)
        if member == '94zz-99-validate-target' and all(marker in source for marker in retirement_markers) \
                and re.search(r'^exit 0\s*$', source, re.M):
            continue
        loaded = source.find('installer_load_data_env "$' + variable + '"')
        used = source.find(consumer)
        if loaded < 0 or used < 0 or loaded > used:
            errors.append(member + ': compiled host policy must load before target path use')
    counts['runtime_path_finish_entrypoint_contracts'] = len(finish_contracts)


def check_diff(errors: list[str]) -> None:
    if BASELINE_ZIP is not None:
        # The checkout archive has no Git metadata. Use the real Git whitespace
        # checker on only the changed before/after bytes, in owned disk scratch.
        scratch = ROOT / '.build/validation'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='archive-diff-', dir=scratch) as directory:
            before, after = Path(directory) / 'before', Path(directory) / 'after'
            before.mkdir(); after.mkdir()
            for name, old in ARCHIVE_CHANGES.items():
                if _custom_apt_input(ROOT / name):
                    continue
                if old is not None:
                    destination = before / name
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_bytes(old)
                current = ROOT / name
                if current.is_file():
                    destination = after / name
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_bytes(current.read_bytes())
            result = _run(['git', 'diff', '--no-index', '--no-ext-diff', '--no-textconv',
                           '--check', '--', str(before), str(after)], timeout=60)
            if result.stdout.strip() or result.stderr.strip() or result.returncode not in (0, 1):
                _report_command(errors, 'git diff --no-index --check (archive baseline)', result)
        return
    for command in (
        ['git', 'diff', '--check', '--', '.',
         ':(exclude)d-i/*/hooks/target/etc/apt/*/sources.list.d/custom/**',
         ':(exclude)d-i/*/hooks/target/etc/apt/*/preferences.d/custom/**'],
        ['git', 'diff', '--cached', '--check', '--', '.',
         ':(exclude)d-i/*/hooks/target/etc/apt/*/sources.list.d/custom/**',
         ':(exclude)d-i/*/hooks/target/etc/apt/*/preferences.d/custom/**'],
    ):
        result = _run(command)
        if result.returncode:
            _report_command(errors, ' '.join(command), result)


def main() -> int:
    global BASELINE_ZIP
    if len(sys.argv) == 3 and sys.argv[1] == '--baseline-zip':
        BASELINE_ZIP = Path(sys.argv[2]).resolve(strict=True)
    elif len(sys.argv) != 1:
        print('usage: post_change_check.py [--baseline-zip SOURCE.zip]', file=sys.stderr)
        return 2
    errors: list[str] = []
    counts: dict[str, int] = {}
    try:
        paths = _changed_paths()
        counts['changed_files'] = len(paths)
        counts['opaque_custom_apt_files'] = sum(_custom_apt_input(path) for path in paths)
        paths = [path for path in paths if not _custom_apt_input(path)]
    except (OSError, UnicodeError, RuntimeError, ValueError) as error:
        errors.append(f'checker failure: {error}')
    else:
        # Check grammar and broad structure only. Exact implementation-token,
        # package-order, source-line and payload-content assertions belong to
        # historical focused fixtures, not this routine changed-file audit.
        checks = (
            check_text_files, check_python, check_shell, check_late_target_shells,
            check_preseed_commands, check_markers, check_structured, check_apparmor,
        )
        for check in checks:
            try:
                check(paths, errors, counts)
            except (OSError, UnicodeError, RuntimeError, ValueError) as error:
                errors.append(f'{check.__name__}: checker failure: {error}')
        try:
            check_diff(errors)
        except (OSError, UnicodeError, RuntimeError, ValueError) as error:
            errors.append(f'check_diff: checker failure: {error}')
    print('post-change static audit: ' + ('PASS' if not errors else 'FAIL'))
    print('counts: ' + ', '.join(f'{key}={value}' for key, value in sorted(counts.items())))
    if errors:
        for error in errors:
            print('ERROR: ' + error, file=sys.stderr)
        return 1
    print('checks: changed-file Python, shell, ShellCheck, decoded preseed commands, theme markers, JSON/YAML/TOML/XML/INI-like data, AppArmor structure, git diff')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
