"""Authenticated, fixed-purpose bridge into the existing signed local APT repo."""
from __future__ import annotations
import os
from pathlib import Path
import pwd
import re
import uuid
from managed_workflows.fs import Tree
from managed_workflows.process import checked, environment
from .core import ARTIFACT, JOB, PROJECT, build_root


def caller_source(argument: str) -> tuple[Path, int]:
    raw_uid = os.environ.get('PKEXEC_UID', '')
    if os.getuid() != 0 or os.geteuid() != 0 or not re.fullmatch(r'[1-9][0-9]{0,9}', raw_uid):
        raise ValueError('administrator authentication through pkexec is required')
    uid = int(raw_uid)
    account = pwd.getpwuid(uid)
    path = Path(argument)
    workspace = build_root(account.pw_name)
    if (not path.is_absolute() or str(path) != argument or '..' in path.parts or
            not path.is_relative_to(workspace) or path.suffix != '.deb' or
            not ARTIFACT.fullmatch(path.name) or len(path.parts) < 6 or
            path.parent.name != 'artifacts' or not JOB.fullmatch(path.parent.parent.name) or
            not PROJECT.fullmatch(path.parent.parent.parent.name) or
            path.parent.parent.parent.parent != workspace):
        raise ValueError('only owned gitbuild .deb artifacts below the caller data pool may be imported')
    # Validate every private project/job component, not just the final file.
    with Tree(workspace, uid=uid, private=True) as tree:
        with tree.parent(str(path.relative_to(workspace))):
            pass
    return path, uid


def main(argv: list[str]) -> int:
    if len(argv) not in (1, 3) or (len(argv) == 3 and argv[1] != '--remove-depends'):
        raise ValueError('usage: gitbuild-import-local PACKAGE.deb [--remove-depends NAME,NAME]')
    remove_depends = ''
    if len(argv) == 3:
        remove_depends = argv[2]
        if (not re.fullmatch(r'[a-z0-9][a-z0-9+.-]*(,[a-z0-9][a-z0-9+.-]*)*', remove_depends)
                or len(remove_depends) > 4096):
            raise ValueError('dependency list contains an invalid package name')
    path, uid = caller_source(argv[0])
    # The caller can replace its own artifacts. Copy through descriptors into a
    # root-only directory before handing a pathname to privileged repository IO.
    with Tree(Path('__INSTALLER_PATH_DIR_VAR_LIB_SOFTWARE__'), uid=0) as repository:
        repository.mkdir('.gitbuild-incoming')
        with Tree(repository.root / '.gitbuild-incoming', uid=0, private=True) as incoming, incoming.lock('import.lock'):
            name = uuid.uuid4().hex + '.deb'
            try:
                with Tree(path.parent, uid=uid, private=True) as source:
                    incoming.copy(name, source, path.name)
                with incoming.open_read(name) as (stream, _):
                    if stream.read(8) != b'!<arch>\n':
                        raise ValueError('not a Debian ar package')
                command = ['__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/apt-repo-init', '--add', str(incoming.root / name), '--yes']
                if remove_depends:
                    command.extend(['--remove-depends', remove_depends])
                checked(command, cwd=incoming.root, env=environment(), timeout=3500)
            finally:
                incoming.write(name, None)
    return 0
