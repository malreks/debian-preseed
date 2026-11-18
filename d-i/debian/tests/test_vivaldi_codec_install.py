"""Package-selected codec handoff; native execution requires test isolation."""
from __future__ import annotations

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation

require_test_isolation()

import importlib.util
import io
import json
import os
import random
import stat
import struct
import subprocess
import tempfile
import time
import unittest
from unittest import mock
import zipfile

SOURCE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    'vivaldi_codec_install_fixture', SOURCE / 'scripts/desktop/vivaldi-codecs-install.py')
codec = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = codec
spec.loader.exec_module(codec)

UPDATER = '''FFMPEG_VERSION=8.3-156-Z-fixture # package-selected Electron release
FFMPEG_MIN_GLIBC_ZIP=17
case amd64 in
  amd64|x86_64)
    FFMPEG_URL_ZIP=https://api.github.com/repos/electron/electron/releases/assets/1
    FFMPEG_DEFLATE_OFFSET_ZIP=99999999
    FFMPEG_SUM_ZIP=obsolete-output-digest
    if true; then
      FFMPEG_VERSION=8.3-153-S-fixture
    fi
    ;;
  arm64|aarch64)
    FFMPEG_URL_ZIP=https://api.github.com/repos/electron/electron/releases/assets/2
    ;;
esac
'''
LAUNCHER = 'FFMPEG_VERSIONS="8.3-153-S-fixture 8.3-156-Z-fixture"\n'
ASSET = 'https://api.github.com/repos/electron/electron/releases/assets/1'
DOWNLOAD = 'https://github.com/electron/electron/releases/download/v1/electron-v1-linux-x64.zip'


def library(machine=62):
    data = bytearray(65536)
    data[:7] = b'\x7fELF\x02\x01\x01'
    struct.pack_into('<HH', data, 16, 3, machine)
    return bytes(data)


def archive_bytes(entries):
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in entries:
            archive.writestr(name, data)
    return output.getvalue()


class Response(io.BytesIO):
    def __init__(self, data, status, headers):
        super().__init__(data)
        self.status, self.headers = status, headers


class ReleaseServer:
    """Only metadata and byte ranges from one in-memory fixture, no network."""
    def __init__(self, data, *, changed=False, ignore_range=False):
        self.data, self.changed, self.ignore_range = data, changed, ignore_range
        self.requests = []
        self.transferred = 0

    def open(self, request, timeout):
        self.requests.append(request)
        if request.full_url == ASSET:
            data = json.dumps({'id': 1, 'state': 'uploaded', 'size': len(self.data),
                               'browser_download_url': DOWNLOAD}).encode()
            return Response(data, 200, {})
        if request.full_url != DOWNLOAD:
            raise AssertionError('unexpected fixture endpoint')
        headers = {key.lower(): value for key, value in request.header_items()}
        start, end = map(int, headers['range'].removeprefix('bytes=').split('-'))
        data = self.data[start:end + 1]
        self.transferred += len(data)
        entity = '"changed"' if self.changed and 'if-match' in headers else '"fixture-entity"'
        return Response(data, 200 if self.ignore_range else 206,
                        {'Content-Range': f'bytes {start}-{end}/{len(self.data)}', 'ETag': entity})


class VivaldiCodecInstallTests(unittest.TestCase):
    def setUp(self):
        # The isolated runner supplies a private, owned disk-backed scratch root.
        self.temporary = tempfile.TemporaryDirectory(dir=os.environ['TMPDIR'], prefix='vivaldi-codec-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def write_archive(self, entries):
        path = self.root / 'fixture.zip'
        path.write_bytes(archive_bytes(entries))
        return path

    def test_package_selects_compatible_electron_release_without_offsets_or_output_hash(self):
        selected = codec.package_release(UPDATER, LAUNCHER, 'x86_64')
        self.assertEqual((selected.version, selected.url, selected.machine),
                         ('8.3-156-Z-fixture', ASSET, 62))
        changed = UPDATER.replace('obsolete-output-digest', 'different-output-digest').replace('99999999', '1')
        self.assertEqual(codec.package_release(changed, LAUNCHER, 'x86_64'), selected)
        arm = codec.package_release(UPDATER.replace('case amd64 in', 'case arm64 in'), LAUNCHER, 'aarch64')
        self.assertEqual((arm.url.rsplit('/', 1)[-1], arm.machine), ('2', 183))

    def test_ambiguous_unaccepted_and_executable_package_fields_fail(self):
        for updater, launcher, architecture in (
            (UPDATER + 'FFMPEG_VERSION=duplicate\n', LAUNCHER, 'x86_64'),
            (UPDATER.replace('FFMPEG_URL_ZIP=' + ASSET, 'FFMPEG_URL_ZIP=' + ASSET + '\n    FFMPEG_URL_ZIP=' + ASSET), LAUNCHER, 'x86_64'),
            (UPDATER.replace(ASSET, 'https://example.invalid/codec.zip'), LAUNCHER, 'x86_64'),
            (UPDATER.replace('FFMPEG_VERSION=8.3-156-Z-fixture', 'FFMPEG_VERSION=$(false)'), LAUNCHER, 'x86_64'),
            (UPDATER, 'FFMPEG_VERSIONS="unsupported"\n', 'x86_64'),
            (UPDATER, LAUNCHER, 'aarch64'),
        ):
            with self.subTest(updater=updater[:40], architecture=architecture), self.assertRaises(ValueError):
                codec.package_release(updater, launcher, architecture)

    def test_named_member_extraction_allows_normal_zip_directories(self):
        path = self.write_archive([('locales/', b''), ('locales/en.pak', b'fixture'),
                                   ('libffmpeg.so', library())])
        self.assertEqual(codec.extract(path, 62), library())

    def test_duplicate_traversal_symlink_missing_and_wrong_architecture_members_fail(self):
        link = zipfile.ZipInfo('libffmpeg.so')
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        for entries in (
            [('libffmpeg.so', library()), ('libffmpeg.so', library())],
            [('../escape', b'x'), ('libffmpeg.so', library())],
            [(link, b'other-library')], [('other-file', library())],
            [('libffmpeg.so', library(183))], [('libffmpeg.so', b'incomplete')],
        ):
            with self.subTest(entries=[str(item[0]) for item in entries]), self.assertRaises((ValueError, zipfile.BadZipFile)):
                codec.extract(self.write_archive(entries), 62)

    def test_zip_member_limit_is_checked_before_member_allocation(self):
        path = self.write_archive([('libffmpeg.so', library()), *[(f'file-{n}', b'') for n in range(512)]])
        with self.assertRaisesRegex(ValueError, 'directory exceeds'):
            codec.extract(path, 62)

    def test_corrupted_zip_member_fails_before_publication(self):
        output = io.BytesIO()
        with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_STORED) as archive:
            archive.writestr('libffmpeg.so', library())
        data = bytearray(output.getvalue())
        data[30 + len('libffmpeg.so') + 128] ^= 1
        path = self.root / 'corrupted.zip'
        path.write_bytes(data)
        with self.assertRaises(zipfile.BadZipFile):
            codec.extract(path, 62)

    def test_new_public_directories_ignore_the_private_installer_umask(self):
        destination = self.root / 'media' / 'media-codecs-fixture'
        previous_umask = os.umask(0o077)
        try:
            with codec.directory(destination, create=True):
                pass
        finally:
            os.umask(previous_umask)
        for path in (destination.parent, destination):
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o755)

    def test_range_download_extracts_the_library_without_downloading_electron(self):
        noise = random.Random(1).randbytes(2 * 1024 * 1024)
        data = archive_bytes([('electron', noise), ('libffmpeg.so', library()), ('locales/', b'')])
        server = ReleaseServer(data)
        destination = self.root / 'ranges.zip'
        with mock.patch.object(codec.urllib.request, 'build_opener', return_value=server):
            codec.download(ASSET, destination, time.monotonic() + 10)
        self.assertEqual(codec.extract(destination, 62), library())
        self.assertLess(server.transferred, 131072)
        self.assertTrue(any('If-match' in dict(request.header_items()) for request in server.requests))

    def test_changed_or_ignored_ranges_fail_before_publication(self):
        data = archive_bytes([('libffmpeg.so', library())])
        for changed, ignored in ((True, False), (False, True)):
            destination = self.root / f'ranges-{changed}-{ignored}.zip'
            server = ReleaseServer(data, changed=changed, ignore_range=ignored)
            with mock.patch.object(codec.urllib.request, 'build_opener', return_value=server), \
                    self.assertRaises(ValueError):
                codec.download(ASSET, destination, time.monotonic() + 10)

    def test_publication_is_atomic_and_preserves_previous_file_on_rename_failure(self):
        destination = self.root / 'libffmpeg.so'
        previous = library() + b'previous'
        destination.write_bytes(previous)
        destination.chmod(0o644)
        descriptor = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY)
        self.addCleanup(os.close, descriptor)
        with mock.patch.object(codec.os, 'replace', side_effect=OSError('fixture interruption')), self.assertRaises(OSError):
            codec.publish(descriptor, library())
        self.assertEqual(destination.read_bytes(), previous)
        self.assertEqual(sorted(path.name for path in self.root.iterdir()), ['libffmpeg.so'])
        codec.publish(descriptor, library())
        self.assertEqual(destination.read_bytes(), library())
        self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o644)

    def test_symlink_and_hardlink_destinations_leave_other_files_untouched(self):
        other = self.root / 'other'
        other.write_bytes(b'unchanged')
        destination = self.root / 'libffmpeg.so'
        descriptor = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY)
        self.addCleanup(os.close, descriptor)
        for linked in (False, True):
            if linked:
                os.link(other, destination)
            else:
                destination.symlink_to(other)
            with self.subTest(hardlink=linked), self.assertRaises(ValueError):
                codec.publish(descriptor, library())
            self.assertEqual(other.read_bytes(), b'unchanged')
            destination.unlink()

    def test_post_rename_sync_failure_has_a_distinct_uncertain_outcome(self):
        descriptor = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY)
        self.addCleanup(os.close, descriptor)
        with mock.patch.object(codec.os, 'fsync', side_effect=[None, OSError('fixture sync')]), \
                self.assertRaises(codec.PublicationOutcomeUnknown):
            codec.publish(descriptor, library())
        self.assertEqual((self.root / 'libffmpeg.so').read_bytes(), library())

    def test_updater_wait_is_bounded_and_failed_download_retains_previous_version(self):
        package = self.root / 'package'
        package.mkdir()
        (package / 'update-ffmpeg').write_text(UPDATER)
        (package / 'vivaldi').write_text(LAUNCHER)
        media = self.root / 'media'
        previous = media / 'media-codecs-previous'
        previous.mkdir(parents=True)
        (previous / 'libffmpeg.so').write_bytes(library())
        with mock.patch.object(codec.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1)), \
                mock.patch.object(codec.os, 'confstr', return_value='glibc 2.41'), \
                mock.patch.object(codec.os, 'uname', return_value=mock.Mock(machine='x86_64')), \
                mock.patch.object(codec, '__file__', str(self.root / 'setup.py')), \
                mock.patch.object(codec, 'download', side_effect=ValueError('fixture unavailable')), \
                self.assertRaises(ValueError):
            codec.install(package, media, Path('/fixture/pidwait'))
        self.assertEqual((previous / 'libffmpeg.so').read_bytes(), library())
        self.assertFalse((media / 'media-codecs-8.3-156-Z-fixture').exists())
        self.assertEqual(len(list(self.root.glob('vivaldi-codecs-*'))), 1)
        with mock.patch.object(codec.subprocess, 'run', side_effect=subprocess.TimeoutExpired('pidwait', 60)), \
                self.assertRaises(subprocess.TimeoutExpired):
            codec.install(package, media, Path('/fixture/pidwait'))


if __name__ == '__main__':
    unittest.main()
