#!__INSTALLER_PATH_DIR_USR_BIN__/python3 -IB
"""Private installation-only appearance setup; never installed as a runtime helper."""
from pathlib import Path
import os
import stat
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, '__INSTALLER_PATH_DIR_PYTHON3_SITE_PACKAGES__')
from managed_workflows.fs import Tree


def main(argv):
    if (os.getuid() != 0 or os.geteuid() != 0 or not (
            argv == ['themes'] or (len(argv) == 2 and argv[0] == 'defaults') or (len(argv) == 3 and argv[0] == 'extract'))):
        raise ValueError('invalid private appearance setup request')
    staging = Path(__file__).parent
    with Tree(staging, uid=0, private=True) as tree:
        for relative in ('setup.py', 'appearance_setup/__init__.py',
                         'appearance_setup/defaults.py', 'appearance_setup/release.py', 'appearance_setup/theme_archive.py',
                         'appearance_setup/theme_assets.py', 'appearance_setup/theme_resources.py',
                         'appearance_setup/theme_install.py'):
            with tree.open_read(relative, limit=256 * 1024) as (_stream, info):
                if info.st_gid != 0 or stat.S_IMODE(info.st_mode) != 0o600:
                    raise ValueError('unsafe private appearance setup code')
        sys.path.insert(0, str(staging))
        if argv[0] == 'extract':
            from appearance_setup.release import main as extract
            return extract(argv[1], argv[2])
        if argv == ['themes']:
            from appearance_setup.theme_install import CleanupPending, OutcomeUnknown, main as setup
            try:
                return setup(['--install'])
            except OutcomeUnknown as error:
                print('appearance-setup: status=outcome-unknown ' + str(error), file=sys.stderr)
                raise SystemExit(4) from error
            except CleanupPending as error:
                print('appearance-setup: status=committed-cleanup-pending ' + str(error), file=sys.stderr)
                raise SystemExit(5) from error
        from appearance_setup.defaults import main as setup
        return setup(['--capture', argv[1]])


if __name__ == '__main__':
    os.umask(0o077)
    try:
        raise SystemExit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        print('Appearance setup cancelled; retain publication evidence before retrying.', file=sys.stderr)
        raise SystemExit(130)
    except (OSError, ValueError, RuntimeError, KeyError) as error:
        message = ''.join(c if c.isprintable() else '?' for c in str(error))
        print('appearance-setup: ' + message, file=sys.stderr)
        raise SystemExit(1)
