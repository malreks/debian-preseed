"""Advisory renderer identity logging inside the reviewed private guest."""
from __future__ import annotations

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import fixture_environment, require_test_isolation
require_test_isolation()

import hashlib
import os
import re
import shutil
import stat
import tempfile
import unittest

from stage_process import CleanupUnknown, run_stage


DEBIAN = Path(__file__).resolve().parents[1]
HOOK = DEBIAN / 'hooks/installer/base-stage.d/00rendertarget'
SOURCE = DEBIAN / 'scripts/common/source.sh'
RENDERER = DEBIAN / 'scripts/common/render.pl'
RELEASE = '1' * 64
ARCHIVE = '2' * 64
MANIFEST = '3' * 64
PRIVATE_ORIGIN = 'https://private-user:private-token@example.invalid/private-seed'
IDENTITY = f'verified-v1 {ARCHIVE} {MANIFEST} {PRIVATE_ORIGIN}\n'.encode()

# The actual source_sha256 helper invokes this counted adapter. Its successful
# branch uses the private image's real SHA256 program over the copied renderer
# on stdin. The failure branches never execute any external command.
DRIVER = r'''#!/bin/sh
set -eu
umask 077
. "$FIXTURE_FUNCTIONS"
sha256sum() {
  printf 'call\n' >>"$FIXTURE_HASH_CALLS"
  case "$FIXTURE_HASH_MODE" in
    real) /usr/bin/sha256sum ;;
    fail) printf 'private-hash-error\n' >&2; return 17 ;;
    malformed) printf 'private-malformed-hash\n' ;;
    *) exit 90 ;;
  esac
}
installer_info() {
  printf '%s\n' "$*"
  return "$FIXTURE_LOG_STATUS"
}
prepare_log_renderer_provenance "$FIXTURE_WORK"
printf 'fixture continued\n'
exit "$FIXTURE_CALLER_STATUS"
'''


class RendererProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='renderer-provenance-', dir='/workspace'))
        self.cleanup_unknown = False
        self.addCleanup(self.cleanup)
        metadata = self.root.lstat()
        self.assertTrue(stat.S_ISDIR(metadata.st_mode))
        self.assertEqual(metadata.st_uid, os.getuid())
        self.assertEqual(stat.S_IMODE(metadata.st_mode), 0o700)
        self.assertTrue(os.access('/usr/bin/sha256sum', os.X_OK))
        self.counter = 0
        empty_path = self.root / 'empty-path'
        empty_path.mkdir(mode=0o700)
        self.environment = fixture_environment(self.root)
        self.environment.update({'PATH': str(empty_path), 'LC_ALL': 'C',
                                 'TMPDIR': str(self.root), 'TMP': str(self.root),
                                 'TEMP': str(self.root)})
        hook_source = HOOK.read_text(encoding='utf-8')
        source_source = SOURCE.read_text(encoding='utf-8')
        diagnostic = re.findall(
            r'^prepare_log_renderer_provenance\(\) \(\n.*?^\) 2>/dev/null\n',
            hook_source, re.M | re.S)
        hasher = re.findall(r'^source_sha256\(\) \{\n.*?^\};\n',
                            source_source, re.M | re.S)
        self.assertEqual(len(diagnostic), 1)
        self.assertEqual(len(hasher), 1)
        self.functions = self.write(self.root / 'functions.sh',
                                    (hasher[0] + diagnostic[0]).encode())
        self.driver = self.write(self.root / 'driver.sh', DRIVER.encode())
        self.current_renderer = RENDERER.read_bytes()

    def cleanup(self):
        if not self.cleanup_unknown:
            shutil.rmtree(self.root)

    @staticmethod
    def write(path, data):
        with path.open('xb') as stream:
            stream.write(data)
        path.chmod(0o600)
        return path

    def invoke(self, *, identity=IDENTITY, renderer=None, release=RELEASE,
               hash_mode='real', log_status=0, caller_status=0,
               missing_renderer=False, identity_kind='regular'):
        self.counter += 1
        work = self.root / f'case-{self.counter}'
        work.mkdir(mode=0o700)
        if identity_kind == 'fifo':
            os.mkfifo(work / 'identity', 0o600)
        elif identity is not None:
            if identity_kind == 'symlink':
                self.write(work / 'identity-data', identity)
                (work / 'identity').symlink_to(work / 'identity-data')
            else:
                self.write(work / 'identity', identity)
        if not missing_renderer:
            self.write(work / 'render.pl', self.current_renderer if renderer is None else renderer)
        calls = work / 'hash-calls'
        output = work / 'stdout'
        error = work / 'stderr'
        environment = {**self.environment, 'INSTALLER_RELEASE_ID': release,
                       'FIXTURE_FUNCTIONS': str(self.functions), 'FIXTURE_WORK': str(work),
                       'FIXTURE_HASH_CALLS': str(calls), 'FIXTURE_HASH_MODE': hash_mode,
                       'FIXTURE_LOG_STATUS': str(log_status),
                       'FIXTURE_CALLER_STATUS': str(caller_status)}
        try:
            with output.open('xb') as stdout, error.open('xb') as stderr:
                output.chmod(0o600)
                error.chmod(0o600)
                result = run_stage(['/bin/dash', str(self.driver)], cwd=work,
                                   env=environment, timeout=5, stdout=stdout, stderr=stderr)
        except CleanupUnknown:
            self.cleanup_unknown = True
            raise
        self.assertFalse(result.timed_out)
        self.assertIsNone(result.cancelled)
        self.assertLessEqual(output.stat().st_size, 4096)
        self.assertLessEqual(error.stat().st_size, 4096)
        self.assertEqual(error.read_bytes(), b'')
        lines = output.read_text(encoding='ascii').splitlines()
        self.assertEqual(len(lines), 2)
        self.assertEqual(lines[1], 'fixture continued')
        self.assertNotIn('private-', lines[0])
        self.assertNotIn('://', lines[0])
        fields = lines[0].removeprefix('target renderer provenance ').split()
        self.assertEqual(len(fields), 4)
        parsed = dict(item.split('=', 1) for item in fields)
        self.assertEqual(set(parsed), {'release', 'archive_sha256',
                                      'manifest_sha256', 'renderer_sha256'})
        for value in parsed.values():
            self.assertRegex(value, r'\A(?:[a-f0-9]{64}|unavailable)\Z')
        call_count = len(calls.read_text().splitlines()) if calls.exists() else 0
        return result.returncode, parsed, call_count

    def test_current_and_old_expression_bytes_are_hashed_exactly_once(self):
        # Representative former malformed expression: this is data only, not
        # a reconstructed historical full renderer or a Perl execution test.
        older = b'$context->{PHASE} =~ /\\A[A-Za-z0-9_./@+:-]+\\z/;\n'
        hashes = []
        for data in (self.current_renderer, older):
            with self.subTest(renderer_sha256=hashlib.sha256(data).hexdigest()):
                status, fields, calls = self.invoke(renderer=data)
                self.assertEqual(status, 0)
                self.assertEqual(calls, 1)
                self.assertEqual(fields, {
                    'release': RELEASE, 'archive_sha256': ARCHIVE,
                    'manifest_sha256': MANIFEST,
                    'renderer_sha256': hashlib.sha256(data).hexdigest(),
                })
                hashes.append(fields['renderer_sha256'])
        self.assertNotEqual(*hashes)

    def test_missing_malformed_or_indirect_identity_is_advisory(self):
        malformed = [
            None, b'', IDENTITY.replace(b'verified-v1', b'unverified-v1'),
            IDENTITY.replace(ARCHIVE.encode(), b'g' * 64),
            IDENTITY.replace(MANIFEST.encode(), b'3' * 63),
            f'verified-v1 {ARCHIVE} {MANIFEST} \n'.encode(),
            IDENTITY + b'\n', IDENTITY + b'partial', IDENTITY.rstrip(b'\n'),
            f'verified-v1 {ARCHIVE} {MANIFEST} /private\tdata\n'.encode(),
            f'verified-v1 {ARCHIVE} {MANIFEST} /'.encode() + b'a' * 8192 + b'\n',
        ]
        for index, identity in enumerate(malformed):
            with self.subTest(malformed=index):
                status, fields, calls = self.invoke(identity=identity)
                self.assertEqual((status, calls), (0, 1))
                self.assertEqual(fields['archive_sha256'], 'unavailable')
                self.assertEqual(fields['manifest_sha256'], 'unavailable')
                self.assertEqual(fields['renderer_sha256'], hashlib.sha256(self.current_renderer).hexdigest())
        for kind in ('symlink', 'fifo'):
            with self.subTest(identity_kind=kind):
                status, fields, calls = self.invoke(identity_kind=kind)
                self.assertEqual((status, calls), (0, 1))
                self.assertEqual(fields['archive_sha256'], 'unavailable')
                self.assertEqual(fields['manifest_sha256'], 'unavailable')

    def test_invalid_release_or_failed_hash_is_unavailable(self):
        for release in ('', 'a' * 63, 'G' * 64, 'https://private-release/unsafe'):
            with self.subTest(release=release):
                status, fields, calls = self.invoke(release=release)
                self.assertEqual((status, calls), (0, 1))
                self.assertEqual(fields['release'], 'unavailable')
        for mode in ('fail', 'malformed'):
            with self.subTest(hash_mode=mode):
                status, fields, calls = self.invoke(hash_mode=mode)
                self.assertEqual((status, calls), (0, 1))
                self.assertEqual(fields['renderer_sha256'], 'unavailable')
        status, fields, calls = self.invoke(missing_renderer=True)
        self.assertEqual((status, calls), (0, 0))
        self.assertEqual(fields['renderer_sha256'], 'unavailable')

    def test_logger_failure_does_not_replace_the_callers_status(self):
        status, fields, calls = self.invoke(log_status=9, caller_status=37)
        self.assertEqual((status, calls), (37, 1))
        self.assertEqual(fields['renderer_sha256'], hashlib.sha256(self.current_renderer).hexdigest())


if __name__ == '__main__':
    unittest.main()
