"""Source-data helpers for guarded developer tools; never target runtime code.

Callers retain their isolation guard. Profile interpretation uses the same
restricted assignment decoder as the pure compiler, without sourcing shell.
These helpers are not imported by the changed-file static audit.
"""
from __future__ import annotations

from pathlib import Path
import re

from class_compiler import assignment_data

ROOT = Path(__file__).resolve().parents[1]
SHARED = ROOT / 'd-i/debian'
FRONTENDS = tuple(ROOT / 'd-i' / suite for suite in ('forky', 'trixie'))


def profile_paths(seed: Path = SHARED, family: str | None = None) -> list[Path]:
    families = (family,) if family else ('desktop', 'server')
    if any(item not in {'desktop', 'server'} for item in families):
        raise ValueError('unknown profile family')
    return sorted(path for item in families
                  for path in (seed / 'hosts/profiles' / item).glob('*.env')
                  if path.name not in {'shared-de.env', 'shared-srv.env'})


def profile_values(seed: Path, profile: Path, suite: str = 'forky') -> dict[str, str]:
    if suite not in {'forky', 'trixie'} or profile not in profile_paths(seed):
        raise ValueError('profile or suite is outside the registered source layout')
    family = profile.parent.name
    shared = profile.parent / ('shared-de.env' if family == 'desktop' else 'shared-srv.env')
    values, provenance = {}, {}
    for path in (seed / 'suites' / suite / 'runtime.env', seed / 'hosts/installer/runtime.env',
                 seed / 'hosts/installer/zram.env',
                 shared, profile, seed / 'hosts/profiles/shared.env',
                 seed / 'hosts/installer/identity.env', seed / 'hosts/installer/boot.env'):
        # Runtime files dependent on profile values follow the profile layer,
        # matching the compiler's split of directories and concrete files.
        text = path.read_text(encoding='utf-8')
        if path.name == 'runtime.env' and path.parent.name == 'installer':
            text = '\n'.join(line if line.startswith('DIR_') else '' for line in text.splitlines())
        assignment_data(text, values, provenance, path.relative_to(seed).as_posix(),
                        defaults_only=path.name in {'shared.env', 'identity.env', 'boot.env'})
    text = (seed / 'hosts/installer/runtime.env').read_text(encoding='utf-8')
    assignment_data('\n'.join('' if line.startswith('DIR_') else line for line in text.splitlines()),
                    values, provenance, 'hosts/installer/runtime.env:files')
    return values


def repository_selectors(seed: Path) -> dict[str, str]:
    values = {'INSTALLER_SUITE': 'forky'}
    assignment_data((seed / 'repo.env').read_text(encoding='utf-8'), values, {}, 'repo.env')
    return {name: value for name, value in values.items() if name.startswith(('DIR_', 'FILE_'))}


def target_source(seed: Path, relative: str, family: str = 'desktop') -> Path:
    """Resolve physical family ownership for data-only developer inspection."""
    if family not in {'desktop', 'server'} or any(part in {'', '.', '..'} for part in relative.split('/')):
        raise ValueError('unsafe target source lookup')
    root = seed / 'hooks/target'
    groups = ('etc/apparmor.d', 'etc/apparmor', 'etc/tmpfiles.d', 'etc/sysctl.d',
              'usr/local/libexec', 'usr/local/lib', 'usr/local/sbin', 'usr/local/bin', 'usr/local/share')
    for group in groups:
        if relative.startswith(group + '/'):
            leaf = relative[len(group) + 1:]
            owners = ('common', family)
            candidates = [root / group / owner / leaf for owner in owners]
            break
    else:
        match = re.fullmatch(r'etc/systemd/(system|user)/(.*)', relative)
        candidates = ([root / 'etc/systemd' / owner / match[1] / match[2]
                       for owner in ('common', family)] if match else [root / relative])
    found = [path for candidate in candidates
             for path in (candidate, candidate.with_name(candidate.name + '.tmpl')) if path.is_file()]
    if len(found) != 1 or found[0].is_symlink():
        raise ValueError('missing, ambiguous or linked target source: ' + relative)
    return found[0]
