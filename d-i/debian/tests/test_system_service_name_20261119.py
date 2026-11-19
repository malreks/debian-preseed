"""Service operands through the real shell owner inside the private guest."""
from __future__ import annotations

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation
require_test_isolation()

import os
import re
import shutil
import stat
import subprocess
import tempfile
import unittest


DEBIAN = Path(__file__).resolve().parents[1]
OWNER = DEBIAN / 'hooks/target/usr/local/libexec/desktop/labwc-system-action-root'
RENDERER = DEBIAN / 'scripts/common/render.pl'

# All external commands reached by inspect-service are shell functions here.
# Each sink verifies its complete argv before returning; no executable lookup
# or management call is delegated to an installed command.
DRIVER = r'''#!/bin/sh
set -eu
umask 077
id() {
  printf '%s\0' "$@" > "$FIXTURE_CALLS/id"
  [ "$#" -eq 1 ] && [ "$1" = -u ] || exit 91
  printf '0\n'
}
getent() {
  printf '%s\0' "$@" > "$FIXTURE_CALLS/getent"
  [ "$#" -eq 2 ] && [ "$1" = passwd ] && [ "$2" = 1000 ] || exit 92
}
systemctl() {
  printf '%s\0' "$@" > "$FIXTURE_CALLS/systemctl"
  [ "$#" -eq 5 ] && [ "$1" = status ] && [ "$2" = --no-pager ] &&
    [ "$3" = --full ] && [ "$4" = -- ] && [ "$5" = "$FIXTURE_UNIT" ] || exit 93
  # Preserve the owner's intentional inactive-service status handling.
  return 3
}
journalctl() {
  printf '%s\0' "$@" > "$FIXTURE_CALLS/journalctl"
  [ "$#" -eq 6 ] && [ "$1" = --unit ] && [ "$2" = "$FIXTURE_UNIT" ] &&
    [ "$3" = --boot ] && [ "$4" = --no-pager ] && [ "$5" = --lines ] &&
    [ "$6" = 200 ] || exit 94
}
fixture_owner=$1
shift
. "$fixture_owner"
'''


class SystemServiceOperandTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='system-service-name-', dir='/workspace')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        metadata = self.root.lstat()
        self.assertTrue(stat.S_ISDIR(metadata.st_mode))
        self.assertEqual(metadata.st_uid, os.getuid())
        self.assertEqual(stat.S_IMODE(metadata.st_mode), 0o700)
        self.calls = self.root / 'calls'
        self.calls.mkdir(mode=0o700)
        empty_path = self.root / 'empty-path'
        empty_path.mkdir(mode=0o700)
        self.environment = {
            'PATH': str(empty_path), 'HOME': str(self.root), 'LC_ALL': 'C',
            'TMPDIR': str(self.root), 'TMP': str(self.root), 'TEMP': str(self.root),
            'PKEXEC_UID': '1000', 'FIXTURE_CALLS': str(self.calls),
        }

        prepared = self.root / 'prepared'
        prepared.mkdir(mode=0o700)
        inputs = prepared / 'inputs'
        inputs.mkdir(mode=0o700)
        operation = prepared / 'operation'
        operation.mkdir(mode=0o700)
        target = self.root / 'target'
        target.mkdir(mode=0o700)
        source = OWNER.read_bytes()
        fields = sorted(set(re.findall(rb'__INSTALLER_(PATH_[A-Z0-9_]+)__', source)))
        self.assertIn(b'PATH_DIR_DEV', fields)
        paths = {name: target / name.decode('ascii').lower() for name in fields}
        for path in paths.values():
            path.mkdir(mode=0o700)
        self._write(paths[b'PATH_DIR_DEV'] / 'null', b'')
        self._write(inputs / 'paths.map', b''.join(
            name + b'=' + str(paths[name]).encode('ascii') + b'\n' for name in fields))
        self._write(operation / 'input', source)
        self._write(operation / 'map', b'')
        renderer = prepared / 'render.pl'
        shutil.copyfile(RENDERER, renderer)
        renderer.chmod(0o600)
        result = subprocess.run(
            ['/usr/bin/perl', '-f', str(renderer), '--file', str(operation), 'scalar'],
            cwd=self.root, env=self.environment, capture_output=True, text=True,
            timeout=15, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.helper = operation / 'output'
        helper_metadata = self.helper.lstat()
        self.assertTrue(stat.S_ISREG(helper_metadata.st_mode))
        self.assertEqual(helper_metadata.st_uid, os.getuid())
        self.assertEqual(helper_metadata.st_nlink, 1)
        self.assertEqual(stat.S_IMODE(helper_metadata.st_mode), 0o600)
        self.assertNotIn(b'__INSTALLER_', self.helper.read_bytes())
        self.driver = self.root / 'driver.sh'
        self._write(self.driver, DRIVER.encode('utf-8'))

    @staticmethod
    def _write(path, data):
        with path.open('xb') as output:
            output.write(data)
        path.chmod(0o600)

    def invoke(self, arguments):
        for name in ('id', 'getent', 'systemctl', 'journalctl'):
            (self.calls / name).unlink(missing_ok=True)
        result = subprocess.run(
            ['/bin/sh', str(self.driver), str(self.helper), 'inspect-service', *arguments],
            cwd=self.root,
            env={**self.environment, 'FIXTURE_UNIT': arguments[0] if arguments else ''},
            capture_output=True, text=True, timeout=5, check=False,
        )
        calls = {}
        for path in self.calls.iterdir():
            self.assertIn(path.name, ('id', 'getent', 'systemctl', 'journalctl'))
            data = path.read_bytes()
            self.assertTrue(data.endswith(b'\0'))
            calls[path.name] = [value.decode('utf-8') for value in data[:-1].split(b'\0')]
        self.assertEqual(calls.get('id'), ['-u'])
        self.assertEqual(calls.get('getent'), ['passwd', '1000'])
        return result, calls

    def test_inspect_service_uses_a_unit_operand_and_rejects_invalid_names(self):
        for name in ('-Hhost.service', 'plain.service',
                     'worker_name@instance.service', 'worker-a:b.service'):
            with self.subTest(valid=name):
                result, calls = self.invoke([name])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, '')
                self.assertEqual(calls, {
                    'id': ['-u'], 'getent': ['passwd', '1000'],
                    'systemctl': ['status', '--no-pager', '--full', '--', name],
                    'journalctl': ['--unit', name, '--boot', '--no-pager', '--lines', '200'],
                })
        for arguments in (['bad/name.service'], ['bad name.service'], ['bad!.service'],
                          ['bad\nname.service'], ['../bad.service'], ['plain.timer'],
                          [''], [], ['plain.service', 'extra.service']):
            with self.subTest(invalid=arguments):
                result, calls = self.invoke(arguments)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual(calls, {'id': ['-u'], 'getent': ['passwd', '1000']})
                self.assertIn('fatal:', result.stderr)


if __name__ == '__main__':
    unittest.main()
