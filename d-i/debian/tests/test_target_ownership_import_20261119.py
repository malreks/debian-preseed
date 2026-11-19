"""Real ownership import and snapshot contracts inside the private guest."""
from __future__ import annotations

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import fixture_environment, require_test_isolation
require_test_isolation()

import os
import shutil
import stat
import tempfile
import unittest

from stage_process import CleanupUnknown, run_stage


DEBIAN = Path(__file__).resolve().parents[1]
SOURCE = DEBIAN / 'scripts/common/source.sh'
PUBLICATION = DEBIAN / 'scripts/common/modules/target-publication.sh'
PHASE = 'hook-base-00rendertarget'

# The real metadata, ancestry, prepare, import, record and snapshot functions
# remain intact. Only fatal UI transport and parser selection are fixture
# adapters; neither adapter changes any ownership decision or input row.
DRIVER = r'''#!/bin/sh
set -eu
umask 077
installer_fatal() { printf 'fatal: %s\n' "$*" >&2; exit 1; }
awk() {
  if [ "${FIXTURE_AWK_FAILURE:-0}" = 1 ] && [ "${1:-}" = -F ]; then
    printf 'fixture ownership awk failure\n' >&2
    return 23
  fi
  case "$FIXTURE_AWK_KIND" in
    busybox) "$FIXTURE_AWK" awk "$@" ;;
    default) "$FIXTURE_AWK" "$@" ;;
    *) exit 90 ;;
  esac
}
. "$FIXTURE_SOURCE"
. "$FIXTURE_PUBLICATION"
fixture_action=$1
shift
case "$fixture_action" in
  import) installer_target_ownership_import "$@" ;;
  snapshot) installer_target_ownership_snapshot ;;
  record) installer_target_ownership_record "$@" ;;
  forget) installer_target_ownership_forget "$@" ;;
  *) exit 91 ;;
esac
'''


class TargetOwnershipImportTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='target-ownership-', dir='/workspace'))
        self.cleanup_unknown = False
        self.addCleanup(self.cleanup)
        metadata = self.root.lstat()
        self.assertTrue(stat.S_ISDIR(metadata.st_mode))
        self.assertEqual(metadata.st_uid, os.getuid())
        self.assertEqual(stat.S_IMODE(metadata.st_mode), 0o700)
        self.counter = 0
        self.ownership = self.root / 'ownership'
        self.journal = self.ownership / 'journal.tsv'
        self.driver = self.write('driver.sh', DRIVER.encode())
        self.environment = fixture_environment(self.root)
        self.environment.update({
            'TMPDIR': str(self.root), 'TMP': str(self.root), 'TEMP': str(self.root),
            'LC_ALL': 'C', 'FIXTURE_SOURCE': str(SOURCE),
            'FIXTURE_PUBLICATION': str(PUBLICATION),
            'DIR_INSTALLER_TARGET_OWNERSHIP': str(self.ownership),
            'INSTALLER_PHASE': PHASE, 'DIR_TMP': str(self.root / 'tmp'),
        })

    def cleanup(self):
        if not self.cleanup_unknown:
            shutil.rmtree(self.root)

    def write(self, name, data, mode=0o600):
        path = self.root / name
        with path.open('xb') as stream:
            stream.write(data)
        path.chmod(mode)
        return path

    def parser(self, kind):
        if kind == 'busybox':
            path = shutil.which('busybox')
            self.assertIsNotNone(path, 'BusyBox is required; installer-dialect coverage cannot be skipped')
            return path
        path = '/usr/bin/awk'
        self.assertTrue(os.access(path, os.X_OK), 'the private image must provide /usr/bin/awk')
        return path

    def invoke(self, kind, action, *arguments, fail_awk=False):
        parser = self.parser(kind)
        self.counter += 1
        output = self.root / f'run-{self.counter}.stdout'
        error = self.root / f'run-{self.counter}.stderr'
        shell = [parser, 'ash'] if kind == 'busybox' else ['/bin/dash']
        environment = {**self.environment, 'FIXTURE_AWK_KIND': kind,
                       'FIXTURE_AWK': parser, 'FIXTURE_AWK_FAILURE': str(int(fail_awk))}
        try:
            with output.open('xb') as stdout, error.open('xb') as stderr:
                output.chmod(0o600)
                error.chmod(0o600)
                result = run_stage(
                    [*shell, str(self.driver), action, *(str(arg) for arg in arguments)],
                    cwd=self.root, env=environment, timeout=10, stdout=stdout, stderr=stderr,
                )
        except CleanupUnknown:
            self.cleanup_unknown = True
            raise
        self.assertFalse(result.timed_out)
        self.assertIsNone(result.cancelled)
        self.assertLessEqual(output.stat().st_size, 65536)
        self.assertLessEqual(error.stat().st_size, 65536)
        return result.returncode, output.read_bytes(), error.read_bytes()

    @staticmethod
    def row(target='/usr/local/lib/perl5/site_perl/Test.pm',
            source='hooks/target/usr/local/lib/common/Test.pm.tmpl',
            kind='plain', phase=PHASE, mode='0644'):
        return f'{target}\t{source}\t{kind}\t{phase}\t{mode}\n'.encode()

    def exercise_contract(self, kind):
        self.parser(kind)  # Missing BusyBox is an explicit failing gate.
        first = self.row()
        second = self.row('/etc/skel-desktop/Local State',
                          'hooks/target/etc/skel-desktop/Local State', mode='0600')
        batch = self.write('valid.tsv', first + second)
        self.assertEqual(self.invoke(kind, 'import', batch), (0, b'', b''))
        self.assertEqual(self.journal.read_bytes(), first + second)
        status, output, error = self.invoke(kind, 'snapshot')
        self.assertEqual((status, error), (0, b''))
        self.assertEqual(sorted(output.splitlines()), sorted((first + second).splitlines()))

        target = '/usr/local/lib/perl5/site_perl/Test.pm'
        updated_source = 'scripts/common:fixture@+-.pm'
        self.assertEqual(self.invoke(kind, 'record', updated_source, target, 'plain', '0600'),
                         (0, b'', b''))
        self.assertEqual(self.invoke(kind, 'forget', '/etc/skel-desktop/Local State'),
                         (0, b'', b''))
        expected = self.row(target, updated_source, mode='0600')
        self.assertEqual(self.invoke(kind, 'snapshot'), (0, expected, b''))

        original = self.journal.read_bytes()
        malformed = [
            b'', b'only\ttwo\n', self.row('relative/path'), self.row('/'),
            self.row('/bad//path'), self.row('/bad/../path'), self.row('/bad/./path'),
            self.row(source='bad!source'), self.row(kind='bad kind'),
            self.row(phase='bad phase'), self.row(mode='0999'),
            self.row(source='a' * 16385), first * 20001,
        ]
        for index, data in enumerate(malformed):
            with self.subTest(parser=kind, malformed=index):
                path = self.write(f'malformed-{index}.tsv', data)
                status, output, error = self.invoke(kind, 'import', path)
                self.assertNotEqual(status, 0)
                self.assertEqual(output, b'')
                self.assertIn(b'malformed target ownership batch', error)
                self.assertEqual(self.journal.read_bytes(), original)

        unsafe_mode = self.write('unsafe-mode.tsv', first, 0o644)
        symlink = self.root / 'symlink.tsv'
        symlink.symlink_to(batch)
        hardlink = self.root / 'hardlink.tsv'
        os.link(batch, hardlink)
        for path in (unsafe_mode, symlink, hardlink):
            with self.subTest(parser=kind, unsafe_metadata=path.name):
                status, output, error = self.invoke(kind, 'import', path)
                self.assertNotEqual(status, 0)
                self.assertEqual(output, b'')
                self.assertIn(b'unsafe target ownership batch', error)
                self.assertEqual(self.journal.read_bytes(), original)

    def test_default_awk_ownership_contract(self):
        self.exercise_contract('default')

    def test_busybox_ownership_contract(self):
        self.exercise_contract('busybox')

    def test_child_awk_diagnostics_and_status_are_preserved(self):
        batch = self.write('valid.tsv', self.row())
        self.assertEqual(self.invoke('default', 'import', batch), (0, b'', b''))
        original = self.journal.read_bytes()
        status, output, error = self.invoke('default', 'import', batch, fail_awk=True)
        self.assertEqual(status, 1)
        self.assertEqual(output, b'')
        self.assertIn(b'fixture ownership awk failure', error)
        self.assertIn(b'malformed target ownership batch', error)
        self.assertEqual(self.journal.read_bytes(), original)
        self.assertEqual(self.invoke('default', 'snapshot', fail_awk=True),
                         (23, b'', b'fixture ownership awk failure\n'))

    def test_snapshot_rejects_empty_and_malformed_journals(self):
        batch = self.write('valid.tsv', self.row())
        self.assertEqual(self.invoke('default', 'import', batch), (0, b'', b''))
        for data in (b'', self.row() + b'partial\trow',
                     self.row() + self.row('/bad/../path')):
            with self.subTest(data=data):
                self.journal.write_bytes(data)
                status, output, error = self.invoke('default', 'snapshot')
                self.assertEqual(status, 1, error)
                self.assertEqual(output, b'')


if __name__ == '__main__':
    unittest.main()
