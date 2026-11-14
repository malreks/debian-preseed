#!/usr/bin/env python3
"""Validate executable module wiring without generating or modifying sources."""
from __future__ import annotations

# Refuse host execution before importing runtime helpers or creating fixtures.
from pathlib import Path as _IsolationPath
import sys as _isolation_sys
_isolation_sys.path.insert(0, str(_IsolationPath(__file__).resolve().parents[1] / 'tools'))
# Copied checker/GUI fixtures still use the verified private checkout gate.
_isolation_sys.path.insert(0, '/workspace/repository/tools')
from isolation import require_test_isolation as _require_test_isolation
_isolation_sys.path.pop(0)
_require_test_isolation()

import argparse
import hashlib
from pathlib import Path
import re
import subprocess
import sys
import tarfile

from source_layout import profile_paths, profile_values, repository_selectors

SEED = Path(__file__).resolve().parents[1] / 'd-i/debian'
# Written plainly so shell quoting and validation are easy to review together.
CALL = re.compile(r'^bootstrap_source_module "\$\((?:installer|bootstrap)_repo_file_value (FILE_[A-Z0-9_]+)\)" \|\| (?:return|exit) "\$\?"$', re.M)
MODULE_DIRS = ('scripts/common/modules', 'scripts/runtime/modules',
               'scripts/desktop/components', 'scripts/late/devops')
ENTRYPOINTS = ('scripts/common/lib.sh', 'scripts/runtime/common.sh',
               'scripts/desktop/components.sh', 'scripts/late/devops.sh.tmpl')
SHARED = {'scripts/common/debconf.sh', 'scripts/common/lifecycle.sh',
          'scripts/common/apt-sources.sh', 'scripts/common/credentials.sh'}
PARSER_ASSETS = {'scripts/common/credential-data.awk': 'awk'}
PARSER_CALL = re.compile(r'bootstrap_parser_asset_path\s+"?\$\((?:installer|bootstrap)_repo_file_value\s+(FILE_[A-Z0-9_]+)\)"?')


def module_file(seed: Path, relative: str) -> Path:
    if not re.fullmatch(r'scripts/[A-Za-z0-9_/-]+[.]sh', relative) or '..' in relative:
        raise ValueError(f'unsafe module reference: {relative!r}')
    path = seed / relative
    template = path.with_name(path.name + '.tmpl')
    if path.exists() and template.exists():
        raise ValueError(f'ambiguous module: {relative}')
    path = template if template.exists() else path
    for p in (path, *path.relative_to(seed).parents):
        p = p if p.is_absolute() else seed / p
        if p.is_symlink():
            raise ValueError(f'symlinked module: {relative}')
    if not path.is_file() or path.stat().st_nlink != 1:
        raise ValueError(f'missing or hardlinked module: {relative}')
    return path


def check_data_assets(seed: Path, selectors: dict[str, str]) -> int:
    """Inventory typed parser consumers and verify both suite closures as data."""
    declared = selectors.get('FILE_COMMON_CREDENTIAL_DATA', '')
    parser_relative = declared.replace('${DIR_SCRIPTS_COMMON}/', 'scripts/common/', 1)
    if parser_relative not in PARSER_ASSETS or PARSER_ASSETS[parser_relative] != 'awk':
        raise ValueError('credential parser selector must be the declared AWK asset')
    asset = seed / parser_relative
    if not asset.is_file() or asset.is_symlink() or asset.stat().st_nlink != 1:
        raise ValueError('credential parser must be a regular single-link source file')
    if asset.stat().st_size > 65536:
        raise ValueError('credential parser exceeds the 64 KiB source bound')

    shell_files = sorted(path for path in seed.rglob('*')
                         if path.is_file() and path.suffix in {'.sh', '.tmpl'})
    parser_consumers = []
    for path in shell_files:
        text = path.read_text(encoding='utf-8')
        if 'bootstrap_module_path' in text and parser_relative in text:
            raise ValueError(f'shell resolver receives the AWK parser: {path.relative_to(seed)}')
        for match in PARSER_CALL.finditer(text):
            parser_consumers.append((path.relative_to(seed).as_posix(), match.group(1)))
        if 'bootstrap_parser_asset_path' in text and parser_relative not in text:
            raise ValueError(f'non-AWK parser asset uses the typed parser resolver: {path.relative_to(seed)}')
    expected = {'FILE_COMMON_CREDENTIAL_DATA'}
    if not parser_consumers or {selector for _, selector in parser_consumers} != expected:
        raise ValueError('typed parser resolver has missing or undeclared consumers')

    asset_digest = hashlib.sha256(asset.read_bytes()).hexdigest()
    closure_sources = (
        parser_relative,
        'scripts/common/bootstrap.sh',
        'scripts/common/credentials.sh',
        'scripts/common/modules/profiles.sh',
    )
    canonical_source = seed / 'scripts/common/source.sh'
    canonical_core = canonical_source.read_text(encoding='utf-8').split(
        '# BEGIN BOOTSTRAP CORE\n', 1)[1].split('# END BOOTSTRAP CORE', 1)[0]
    for suite in ('forky', 'trixie'):
        suite_root = seed.parent / suite
        manifest = suite_root / 'payload.manifest'
        archive = suite_root / 'payload.tar.gz'
        if not manifest.is_file() or not archive.is_file():
            # Source-only fixture copies intentionally omit generated products;
            # the checkout path below verifies both suite closures when present.
            continue
        records = {}
        for number, line in enumerate(manifest.read_text(encoding='utf-8').splitlines(), 1):
            if number == 1:
                if line != 'format=3':
                    raise ValueError(f'{suite} payload manifest has an invalid header')
                continue
            fields = line.split('\t')
            if len(fields) != 3:
                raise ValueError(f'{suite} payload manifest has a malformed record')
            size, digest, member_relative = fields
            if member_relative in records:
                raise ValueError(f'{suite} payload manifest repeats {member_relative}')
            records[member_relative] = (int(size), digest)
        if records.get(parser_relative) != (asset.stat().st_size, asset_digest):
            raise ValueError(f'{suite} manifest does not close over credential-data.awk')
        with tarfile.open(archive, 'r:gz') as payload:
            member = payload.getmember(parser_relative)
            if not member.isfile() or payload.extractfile(member).read() != asset.read_bytes():
                raise ValueError(f'{suite} payload does not close over credential-data.awk')
            for closure_relative in closure_sources[1:]:
                member = payload.getmember(closure_relative)
                if member.isfile() and payload.extractfile(member).read() != (seed / closure_relative).read_bytes():
                    raise ValueError(f'{suite} payload source copy differs: {closure_relative}')
        generated_source = suite_root / 'source.sh'
        if generated_source.is_file():
            generated_core = generated_source.read_text(encoding='utf-8').split(
                '# BEGIN BOOTSTRAP CORE\n', 1)[1].split('# END BOOTSTRAP CORE', 1)[0]
            if generated_core != canonical_core:
                raise ValueError(f'{suite} embedded source core differs from canonical source.sh')
        generated_preseed = suite_root / 'preseed.cfg'
        if generated_preseed.is_file() and f'INSTALLER_SUITE={suite};' not in generated_preseed.read_text(encoding='utf-8'):
            raise ValueError(f'{suite} preseed carries the wrong suite identity')
    return len(parser_consumers)


def check(seed: Path = SEED) -> int:
    seed = seed.resolve()
    if (seed.parents[1] / 'src').exists():
        raise ValueError('root src/ is not an installer input; keep editable code in the shared Debian subtree')
    used = set()
    selectors = repository_selectors(seed)
    for relative in ENTRYPOINTS:
        path = seed / relative
        text = path.read_text()
        names = CALL.findall(text)
        lines = [line for line in text.splitlines() if line.startswith('bootstrap_source_module ')]
        if not names or len(names) != len(lines) or len(set(names)) != len(names):
            raise ValueError(f'invalid, empty or repeated module list: {relative}')
        for selector in names:
            if selector not in selectors:
                raise ValueError('undeclared module selector: ' + selector)
            name = selectors[selector].removesuffix('.tmpl')
            module = module_file(seed, name)
            if name not in SHARED and name in used:
                raise ValueError(f'module has multiple owners: {name}')
            used.add(name)
            parsed = subprocess.run(['/bin/sh', '-n', str(module)], capture_output=True, text=True)
            if parsed.returncode:
                raise ValueError(f'module syntax error: {name}: {parsed.stderr.strip()}')
    inventory = {p.relative_to(seed).as_posix().removesuffix('.tmpl')
                 for directory in MODULE_DIRS for p in (seed / directory).rglob('*') if p.is_file()}
    if inventory != used - SHARED:
        raise ValueError(f'unwired or missing module: {sorted(inventory ^ (used - SHARED))}')
    # Profile policy belongs to the compiler's restricted data grammar, not
    # an obsolete set of flat desktop-only environment fields.
    for profile in profile_paths(seed):
        for suite in ('forky', 'trixie'):
            profile_values(seed, profile, suite)
    return len(inventory) + check_data_assets(seed)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    try:
        print(f'{check()} runtime modules wired; environment files are read-only inputs')
        return 0
    except (OSError, ValueError) as exc:
        print(f'module validation failed: {exc}', file=sys.stderr)
        return 1

if __name__ == '__main__':
    raise SystemExit(main())
