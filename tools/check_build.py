#!/usr/bin/env python3
"""Guarded data-only source/publication checker for the two suite frontends.

This runner remains unexecuted under repository guidance. Generation is owned
by build.py; this file never generates products, imports installer modules,
sources shell snippets or invokes native policy/management tools.
"""
from __future__ import annotations

from pathlib import Path as _IsolationPath
import sys as _isolation_sys
_isolation_sys.path.insert(0, str(_IsolationPath(__file__).resolve().parents[1] / 'tools'))
_isolation_sys.path.insert(0, '/workspace/repository/tools')
from isolation import require_test_isolation as _require_test_isolation
_isolation_sys.path.pop(0)
_require_test_isolation()


import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import tarfile

from source_layout import profile_paths, profile_values, repository_configuration

ROOT = Path(__file__).resolve().parents[1]
SEED = ROOT / 'd-i/debian'


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def validate_apparmor_modes() -> None:
    """All family-owned top-level policy files have a family mode owner."""
    root = SEED / 'hooks/target/etc/apparmor.d'
    for family in ('desktop', 'server'):
        mode_file = SEED / 'hooks/target/etc/apparmor' / family / 'modes.conf.tmpl'
        declared = set()
        for line in mode_file.read_text(encoding='utf-8').splitlines():
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            row = line.split()
            if len(row) != 4 or row[0] not in {'enforce', 'complain', '__DESKTOP_APPARMOR_STATE__'} or row[1] not in {'required', 'optional'}:
                raise ValueError('invalid managed AppArmor mode row')
            if row[2] in declared:
                raise ValueError('duplicate managed AppArmor profile mode row')
            declared.add(row[2])
        names = {path.name.removesuffix('.tmpl') for path in (root / family).glob('*') if path.is_file()}
        missing = names - declared
        if missing:
            raise ValueError('unmanaged repository AppArmor profile: ' + ', '.join(sorted(missing)))


def verify_lifecycle_helpers() -> None:
    begin, end = '# BEGIN EMBEDDED LIFECYCLE\n', '# END EMBEDDED LIFECYCLE\n'
    canonical = (SEED / 'scripts/common/lifecycle.sh').read_text(encoding='utf-8')
    text = (SEED / 'scripts/common/source.sh').read_text(encoding='utf-8')
    if text.count(begin) != 1 or text.count(end) != 1 or text.split(begin)[1].split(end)[0] != canonical:
        raise ValueError('bootstrap lifecycle embedding differs from its canonical source')


def validate(paths: list[Path]) -> None:
    for suite in ('forky', 'trixie'):
        repository_configuration(SEED, suite)
    for path in paths:
        if path.is_symlink() or not path.is_file() or path.stat().st_mode & 0o111:
            raise ValueError('installer source must be a nonexecutable regular file')
    if not profile_paths(SEED, 'desktop') or not profile_paths(SEED, 'server'):
        raise ValueError('both profile families must be present')
    for profile in profile_paths(SEED):
        for suite in ('forky', 'trixie'):
            profile_values(SEED, profile, suite)
    validate_apparmor_modes()
    verify_lifecycle_helpers()


def validate_source_members(members: dict[str, bytes]) -> None:
    """The compiled inventory must describe the actual captured payload once."""
    data = members.get('catalog/compiled/source-members.tsv', b'')
    if len(data) > 4 * 1024 * 1024:
        raise ValueError('source membership table exceeds its bound')
    lines = data.decode('utf-8').splitlines()
    if not lines or lines[0] != 'format\t1' or len(lines) > 10001:
        raise ValueError('invalid source membership header or count')
    seen = set()
    for line in lines[1:]:
        fields = line.split('\t')
        if len(fields) != 3:
            raise ValueError('invalid source membership row')
        member, family, suite = fields
        if (not re.fullmatch(r'[A-Za-z0-9_./@+ -]+', member)
                or member.startswith('/') or len(member) > 240
                or any(part in {'', '.', '..'} for part in member.split('/'))
                or member in seen or member not in members
                or family not in {'any', 'common', 'desktop', 'server'}
                or suite not in {'any', 'forky', 'trixie'}):
            raise ValueError('unsafe, duplicate or absent source member: ' + member)
        selected_suite = re.match(r'frontends/(forky|trixie)/', member)
        if suite != (selected_suite[1] if selected_suite else 'any'):
            raise ValueError('source member has the wrong suite: ' + member)
        seen.add(member)
    if seen != set(members):
        raise ValueError('source membership table omits captured members')


def current_products() -> tuple[str, dict[str, bytes]]:
    identifiers = set()
    for suite in ('forky', 'trixie'):
        data = (ROOT / 'd-i' / suite / 'preseed.cfg').read_bytes()
        matches = set(re.findall(rb'INSTALLER_RELEASE_ID=([a-f0-9]{64})', data))
        if len(matches) != 1:
            raise ValueError('frontend has no unambiguous immutable release')
        identifiers.update(matches)
    if len(identifiers) != 1:
        raise ValueError('frontends bind different releases')
    release_id = identifiers.pop().decode('ascii')
    release = ROOT / 'd-i/forky'
    receipt = json.loads((release / 'receipt.json').read_bytes())
    for name, expected in receipt['compiler_inputs'].items():
        if digest((ROOT / name).read_bytes()) != expected:
            raise ValueError('stale compiler input: ' + name)
    with tarfile.open(release / 'payload.tar.gz', 'r:gz') as archive:
        members = {}
        total = 0
        for entry in archive:
            total += entry.size
            if (not entry.isfile() or len(members) >= 10000 or total > 268435456
                    or any(part in {'', '.', '..'} for part in entry.name.split('/'))
                    or entry.name.startswith('/') or entry.name in members):
                raise ValueError('invalid installer archive member')
            stream = archive.extractfile(entry)
            if stream is None:
                raise ValueError('missing regular archive member')
            with stream:
                members[entry.name] = stream.read(entry.size + 1)
    for name, expected in receipt['source_inputs'].items():
        if name.startswith('frontends/'):
            owner, relative = name.removeprefix('frontends/').split('/', 1)
            source = ROOT / 'd-i' / owner / relative
        else:
            source = SEED / name
        data = source.read_bytes()
        if digest(data) != expected or members.get(name) != data:
            raise ValueError('stale captured source: ' + name)
    for name, expected in receipt['products'].items():
        for suite in ('forky', 'trixie'):
            if digest((ROOT / 'd-i' / suite / name).read_bytes()) != expected:
                raise ValueError('suite product digest differs: ' + suite + '/' + name)
    for name, expected in receipt['frontends'].items():
        if digest((ROOT / 'd-i' / name).read_bytes()) != expected:
            raise ValueError('stale frontend product: ' + name)
    validate_source_members(members)
    return release_id, members


def main() -> int:
    argparse.ArgumentParser(description=__doc__).parse_args()
    try:
        release_id, members = current_products()
        paths = [SEED / name for name in members
                 if not name.startswith(('frontends/', 'catalog/compiled/'))]
        validate(paths)
        print(f'source publication {release_id}: {len(members)} regular members; runtime acceptance unverified')
        return 0
    except (OSError, ValueError, KeyError, tarfile.TarError) as error:
        print('source publication check failed: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
