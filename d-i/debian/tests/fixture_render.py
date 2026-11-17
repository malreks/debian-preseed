"""Typed renderer adapter for data fixtures inside the reviewed test guest."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation
require_test_isolation()


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
