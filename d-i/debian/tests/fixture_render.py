"""Typed renderer adapter for data fixtures inside the reviewed test guest."""
from pathlib import Path
import os
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
from functools import lru_cache

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation
require_test_isolation()


@lru_cache(maxsize=1)
def compiled_runtime_paths() -> dict[str, str]:
    """Read fixture path values from the current generated profile, as data."""
    seed = Path(__file__).resolve().parents[1]
    member = 'catalog/compiled/forky/profiles/desktop/btrfs-de-p15s.env'
    with tarfile.open(seed.parent / 'forky/payload.tar.gz', 'r:gz') as archive:
        info = archive.getmember(member)
        if not info.isfile() or info.size > 1024 * 1024:
            raise ValueError('invalid compiled fixture profile')
        profile = archive.extractfile(info).read().decode('utf-8')
    profile_values = {}
    for line in profile.splitlines():
        if not line or line.startswith('#'):
            continue
        key, separator, raw = line.partition('=')
        words = shlex.split(raw)
        if not separator or key in profile_values or len(words) != 1:
            raise ValueError('invalid compiled fixture assignment')
        profile_values[key] = words[0]
    schema = seed / 'catalog/runtime-paths.tsv'
    fields = dict(line.split('\t') for line in schema.read_text(encoding='utf-8').splitlines()
                  if line and not line.startswith('#'))
    return {token: profile_values[owner] for token, owner in fields.items()}


def rendered_path_text(text: str) -> str:
    """Give isolated source fixtures the generated canonical path view."""
    values = compiled_runtime_paths()
    return re.sub(r'__INSTALLER_(PATH_[A-Z0-9]+(?:_[A-Z0-9]+)*)__',
                  lambda match: values[match[1]], text)


def render_apparmor_modes(config: Path, state: str) -> subprocess.CompletedProcess:
    """Run actual target Perl, with synthetic paths and no policy activation."""
    if config.is_symlink() or config.stat().st_nlink != 1:
        raise ValueError('mode fixture must be a single-link regular file')
    source = Path(__file__).resolve().parents[1] / 'scripts/common/render.pl'
    with tempfile.TemporaryDirectory(prefix='mode-render-', dir=config.parent) as directory:
        root = Path(directory)
        operation = root / 'operation'
        operation.mkdir(mode=0o700)
        (root / 'inputs').mkdir(mode=0o700)
        data = config.read_bytes()
        fields = sorted(set(re.findall(rb'__INSTALLER_(PATH_[A-Z0-9_]+)__', data)))
        (root / 'inputs/paths.map').write_bytes(b''.join(
            name + b'=/fixture/' + name.lower() + b'\n' for name in fields))
        (operation / 'input').write_bytes(data)
        (operation / 'map').write_text('DESKTOP_APPARMOR_STATE=' + state + '\n')
        shutil.copyfile(source, root / 'render.pl')
        env = {'PATH': '/usr/bin:/bin', 'HOME': str(root), 'TMPDIR': str(root),
               'TMP': str(root), 'TEMP': str(root), 'LC_ALL': 'C'}
        result = subprocess.run(['/usr/bin/perl', '-f', str(root / 'render.pl'),
                                 '--file', str(operation), 'apparmor-modes'],
                                env=env, capture_output=True, text=True, timeout=15, check=False)
        if result.returncode == 0:
            os.replace(operation / 'output', config)
        return result
