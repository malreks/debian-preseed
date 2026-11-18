#!/usr/bin/python3
"""Install Vivaldi's compatible Electron codec without vendor byte offsets.

The signed browser package selects the release. HTTPS authenticates transport;
ZIP integrity and the ELF header validate the artifact shape. No fixed library
digest is imposed on package-selected releases, and no downloaded code is run.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from dataclasses import dataclass
import json
import os
from pathlib import Path, PurePosixPath
import re
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
import zlib

MAX_ARCHIVE = 256 * 1024 * 1024
MAX_LIBRARY = 32 * 1024 * 1024
MAX_MEMBERS = 512
FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK


class PublicationOutcomeUnknown(RuntimeError):
    """A codec rename completed but its durable completion is uncertain."""


@dataclass(frozen=True)
class Release:
    version: str
    url: str
    machine: int
    minimum_glibc: int


def package_release(updater: str, launcher: str, architecture: str) -> Release:
    """Read only declared literal fields; never source the package's shell."""
    if len(updater) > 131072 or len(launcher) > 131072:
        raise ValueError('packaged codec metadata exceeds its size limit')

    def literal(source: str, name: str, *, indented: bool = False) -> str:
        prefix = r'[ \t]+' if indented else ''
        values = re.findall(r'^' + prefix + re.escape(name)
                            + r'=([^\n]+)$', source, re.MULTILINE)
        if len(values) != 1:
            raise ValueError('packaged codec metadata is missing or ambiguous: ' + name)
        value = values[0].split(' #', 1)[0].strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
            value = value[1:-1]
        if not re.fullmatch(r'[A-Za-z0-9:/._-]{1,256}', value):
            raise ValueError('packaged codec metadata is not literal: ' + name)
        return value

    branches = {'x86_64': ('amd64', 'amd64|x86_64', 62),
                'aarch64': ('arm64', 'arm64|aarch64', 183)}
    if architecture not in branches:
        raise ValueError('unsupported Vivaldi codec target architecture')
    debian_arch, branch, machine = branches[architecture]
    cases = re.findall(r'^case ([a-z0-9_]+) in[ \t]*$', updater, re.MULTILINE)
    if cases != [debian_arch]:
        raise ValueError('packaged codec updater does not match the target architecture')
    sections = re.findall(r'^[ \t]+' + re.escape(branch)
                          + r'\)[ \t]*\n(.*?)^[ \t]+;;[ \t]*$',
                          updater, re.MULTILINE | re.DOTALL)
    if len(sections) != 1:
        raise ValueError('packaged codec architecture branch is missing or ambiguous')
    version = literal(updater, 'FFMPEG_VERSION')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,95}', version):
        raise ValueError('invalid packaged codec version')
    inventories = re.findall(r'^FFMPEG_VERSIONS="([A-Za-z0-9. _-]+)"[ \t]*$',
                             launcher, re.MULTILINE)
    if (len(inventories) != 1 or not 1 <= len(inventories[0].split()) <= 16
            or version not in inventories[0].split()):
        raise ValueError('packaged Electron codec is not accepted by this Vivaldi launcher')
    url = literal(sections[0], 'FFMPEG_URL_ZIP', indented=True)
    if not re.fullmatch(r'https://api\.github\.com/repos/electron/electron/releases/assets/[1-9][0-9]{0,19}', url):
        raise ValueError('packaged codec URL is not an Electron release asset')
    minimum = literal(updater, 'FFMPEG_MIN_GLIBC_ZIP')
    if not re.fullmatch(r'[0-9]{1,3}', minimum):
        raise ValueError('invalid packaged codec glibc requirement')
    return Release(version, url, machine, int(minimum))


@contextmanager
def directory(path: Path, *, create: bool = False):
    if not path.is_absolute() or '..' in path.parts:
        raise ValueError('codec directory must be absolute without traversal')
    descriptor = os.open('/', os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        for part in path.parts[1:]:
            created = False
            try:
                child = os.open(part, FLAGS | os.O_DIRECTORY, dir_fd=descriptor)
            except FileNotFoundError:
                if not create:
                    raise
                os.mkdir(part, 0o700, dir_fd=descriptor)
                child = os.open(part, FLAGS | os.O_DIRECTORY, dir_fd=descriptor)
                created = True
            try:
                info = os.fstat(child)
                if info.st_uid != os.geteuid() or info.st_mode & 0o022:
                    raise ValueError('unsafe codec directory owner or mode')
                if created:
                    os.fchmod(child, 0o755)
                    os.fsync(child)
                    os.fsync(descriptor)
            except BaseException:
                os.close(child)
                raise
            os.close(descriptor)
            descriptor = child
        yield descriptor
    finally:
        os.close(descriptor)


def regular(parent: int, name: str, maximum: int, *, prefix: int | None = None
            ) -> tuple[os.stat_result, bytes]:
    descriptor = os.open(name, FLAGS, dir_fd=parent)
    with os.fdopen(descriptor, 'rb') as stream:
        info = os.fstat(stream.fileno())
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid()
                or info.st_mode & 0o022 or info.st_nlink != 1 or info.st_size > maximum):
            raise ValueError('unsafe packaged codec input')
        data = stream.read(maximum + 1 if prefix is None else prefix)
        if len(data) > maximum or file_identity(os.fstat(stream.fileno())) != file_identity(info):
            raise ValueError('packaged codec input changed during reading')
        return info, data


def file_identity(info: os.stat_result) -> tuple[int, ...]:
    # Reading a packaged file may update atime; that is not source mutation.
    return (info.st_dev, info.st_ino, info.st_mode, info.st_nlink, info.st_uid,
            info.st_gid, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def elf(data: bytes, machine: int) -> None:
    if (len(data) < 64 or data[:7] != b'\x7fELF\x02\x01\x01'
            or struct.unpack_from('<HH', data, 16) != (3, machine)):
        raise ValueError('codec is not an ELF64 shared library for this target')


class Redirects(urllib.request.HTTPRedirectHandler):
    def __init__(self):
        super().__init__()
        self.hops = 0

    def redirect_request(self, request, response, code, message, headers, url):
        self.hops += 1
        parsed = urllib.parse.urlsplit(url)
        if (self.hops > 5 or parsed.scheme != 'https' or parsed.username or parsed.password
                or parsed.port not in (None, 443) or parsed.fragment
                or parsed.hostname not in {'api.github.com', 'github.com',
                                           'release-assets.githubusercontent.com',
                                           'objects.githubusercontent.com'}):
            raise ValueError('codec download redirect is outside the Electron release contract')
        return super().redirect_request(request, response, code, message, headers, url)


def zip_directory(stream) -> tuple[int, int, int]:
    """Bound member allocation before asking ZipFile to read its directory."""
    stream.seek(0, os.SEEK_END)
    size = stream.tell()
    if not 22 <= size <= MAX_ARCHIVE:
        raise ValueError('invalid codec ZIP size')
    stream.seek(max(0, size - 65557))
    tail = stream.read(65557)
    offset = tail.rfind(b'PK\x05\x06')
    if offset < 0 or offset + 22 > len(tail):
        raise ValueError('codec ZIP has no end record')
    _, disk, cd_disk, disk_count, count, length, start, comment = struct.unpack_from('<4s4H2LH', tail, offset)
    if (disk or cd_disk or disk_count != count or not 1 <= count <= MAX_MEMBERS
            or length > 262144 or start + length != size - len(tail) + offset
            or offset + 22 + comment != len(tail)):
        raise ValueError('codec ZIP directory exceeds its bounds')
    return count, start, length


def download(url: str, archive: Path, deadline: float) -> None:
    """Fetch the ZIP directory and codec ranges, never the Electron executable.

    Byte ranges come from ZIP records, not offsets embedded in vendor shell.
    A strong HTTP entity tag binds the ranges to the same release object. This
    private sparse ZIP is never retained or represented as a complete archive.
    """
    redirects = Redirects()
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), redirects)
    transferred = 0

    def read(address: str, headers: dict[str, str], maximum: int):
        nonlocal transferred
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError('codec download deadline exceeded')
        redirects.hops = 0
        request = urllib.request.Request(address, headers={
            'User-Agent': 'Debian-Vivaldi-codec-installer', **headers})
        with opener.open(request, timeout=min(15, remaining)) as response:
            data = bytearray()
            while True:
                if time.monotonic() >= deadline:
                    raise TimeoutError('codec download deadline exceeded')
                block = response.read1(min(65536, maximum + 1 - len(data)))
                if not block:
                    break
                data.extend(block)
                transferred += len(block)
                if len(data) > maximum or transferred > MAX_LIBRARY + 1048576:
                    raise ValueError('codec range download exceeded its transfer limit')
            return response.status, response.headers, bytes(data)

    status, _, raw = read(url, {'Accept': 'application/vnd.github+json'}, 65536)
    metadata = json.loads(raw)
    if not isinstance(metadata, dict):
        raise ValueError('codec asset metadata is not an object')
    address = metadata.get('browser_download_url', '')
    size = metadata.get('size', 0)
    if (status != 200 or type(size) is not int or not 22 <= size <= MAX_ARCHIVE
            or type(metadata.get('id')) is not int or str(metadata['id']) != url.rsplit('/', 1)[-1]
            or metadata.get('state') != 'uploaded' or not isinstance(address, str)
            or not re.fullmatch(r'https://github\.com/electron/electron/releases/download/'
                                r'[A-Za-z0-9._-]+/electron-[A-Za-z0-9._-]+\.zip', address)):
        raise ValueError('codec asset metadata does not describe the packaged Electron release')
    entity = None

    def byte_range(start: int, length: int) -> bytes:
        nonlocal entity
        if not 0 <= start < size or not 0 < length <= MAX_LIBRARY or start + length > size:
            raise ValueError('codec ZIP range is outside the release object')
        headers = {'Range': f'bytes={start}-{start + length - 1}'}
        if entity is not None:
            headers['If-Match'] = entity
        status, response, data = read(address, headers, length)
        observed = response.get('ETag', '')
        if (status != 206 or len(data) != length
                or response.get('Content-Range') != f'bytes {start}-{start + length - 1}/{size}'
                or re.fullmatch(r'"[^"\r\n]{1,128}"', observed) is None
                or entity is not None and observed != entity):
            raise ValueError('codec server returned incomplete or changed ZIP ranges')
        entity = observed
        return data

    tail_start = max(0, size - 65557)
    tail = byte_range(tail_start, size - tail_start)
    with archive.open('x+b') as output:
        output.seek(tail_start)
        output.write(tail)
        output.flush()
        _, start, length = zip_directory(output)
        if start < tail_start:
            output.seek(start)
            output.write(byte_range(start, length))
            output.flush()
        with zipfile.ZipFile(output) as package:
            selected = [item for item in package.infolist() if item.filename == 'libffmpeg.so']
            if (len(selected) != 1 or not 65536 <= selected[0].file_size <= MAX_LIBRARY
                    or not 0 < selected[0].compress_size <= MAX_LIBRARY - 131100
                    or selected[0].compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)):
                raise ValueError('codec ZIP has no unique bounded library member')
            member = selected[0]
        header = byte_range(member.header_offset, 30)
        if header[:4] != b'PK\x03\x04':
            raise ValueError('codec ZIP library has no local header')
        name_size, extra_size = struct.unpack_from('<HH', header, 26)
        output.seek(member.header_offset)
        output.write(header)
        output.write(byte_range(member.header_offset + 30,
                                name_size + extra_size + member.compress_size))
    print(f'Vivaldi codec ZIP transfer: {transferred} bytes from a {size}-byte Electron release')


def extract(archive: Path, machine: int) -> bytes:
    with archive.open('rb') as stream:
        count, _, _ = zip_directory(stream)
        stream.seek(0)
        with zipfile.ZipFile(stream) as package:
            names = set()
            total = 0
            for member in package.infolist():
                path = PurePosixPath(member.filename)
                kind = stat.S_IFMT(member.external_attr >> 16)
                if (not path.parts or path.is_absolute() or '..' in path.parts
                        or member.filename != path.as_posix() + ('/' if member.is_dir() else '')
                        or '\\' in member.filename
                        or any(ord(char) < 32 or ord(char) == 127 for char in member.filename)
                        or member.filename in names or member.flag_bits & 1
                        or member.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)
                        or kind not in (0, stat.S_IFDIR if member.is_dir() else stat.S_IFREG)):
                    raise ValueError('codec ZIP has unsafe or duplicate members')
                names.add(member.filename)
                total += member.file_size
                if total > 1024 * 1024 * 1024:
                    raise ValueError('codec ZIP exceeds its expanded-byte limit')
            if len(names) != count or 'libffmpeg.so' not in names:
                raise ValueError('codec ZIP has no unique libffmpeg.so member')
            with package.open('libffmpeg.so') as source:
                data = source.read(MAX_LIBRARY + 1)
    if not 65536 <= len(data) <= MAX_LIBRARY:
        raise ValueError('codec library has an invalid size')
    elf(data, machine)
    return data


def publish(parent: int, data: bytes) -> None:
    def identity():
        try:
            info = os.stat('libffmpeg.so', dir_fd=parent, follow_symlinks=False)
        except FileNotFoundError:
            return None
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid()
                or info.st_nlink != 1 or info.st_mode & 0o022):
            raise ValueError('unsafe existing codec destination')
        return file_identity(info)

    previous = identity()
    name = '.libffmpeg.so.' + os.urandom(12).hex()
    descriptor = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                         0o600, dir_fd=parent)
    try:
        with os.fdopen(descriptor, 'wb') as output:
            output.write(data)
            os.fchmod(output.fileno(), 0o644)
            output.flush()
            os.fsync(output.fileno())
        if identity() != previous:
            raise ValueError('codec destination changed before publication')
        os.replace(name, 'libffmpeg.so', src_dir_fd=parent, dst_dir_fd=parent)
        try:
            os.fsync(parent)
        except OSError as error:
            raise PublicationOutcomeUnknown('codec renamed but directory sync failed') from error
    finally:
        try:
            os.unlink(name, dir_fd=parent)
        except FileNotFoundError:
            pass


def install(package_directory: Path, media_directory: Path, pidwait: Path) -> None:
    # The package postinst may already own an asynchronous updater. Observe it
    # without signalling, and do not race its destructive cleanup operation.
    status = subprocess.run([str(pidwait), '--exact', '--uid', '0', '--', 'update-ffmpeg'],
                            env={'LC_ALL': 'C'}, stdin=subprocess.DEVNULL,
                            stdout=subprocess.DEVNULL, timeout=60, check=False).returncode
    if status not in (0, 1):
        raise ValueError('cannot observe the packaged codec updater')
    with directory(package_directory) as parent:
        _, updater = regular(parent, 'update-ffmpeg', 131072)
        _, launcher = regular(parent, 'vivaldi', 131072)
    release = package_release(updater.decode('utf-8'), launcher.decode('utf-8'), os.uname().machine)
    glibc = os.confstr('CS_GNU_LIBC_VERSION') or ''
    match = re.fullmatch(r'glibc 2\.([0-9]+)', glibc)
    if match is None or int(match[1]) < release.minimum_glibc:
        raise ValueError('target glibc does not meet the packaged codec requirement')
    destination = media_directory / ('media-codecs-' + release.version)
    try:
        with directory(destination) as parent:
            info, data = regular(parent, 'libffmpeg.so', MAX_LIBRARY, prefix=64)
            if info.st_size >= 65536:
                elf(data[:64], release.machine)
                print('Vivaldi compatible codec already installed: ' + release.version)
                return
    except FileNotFoundError:
        pass
    # A private workspace beside the staged setup program stays on the target.
    # Failed downloads are retained; no previous codec is removed on failure.
    work = Path(tempfile.mkdtemp(prefix='vivaldi-codecs-', dir=Path(__file__).parent))
    archive = work / 'ffmpeg.zip'
    try:
        download(release.url, archive, time.monotonic() + 120)
        data = extract(archive, release.machine)
        with directory(destination, create=True) as parent:
            publish(parent, data)
    except BaseException:
        print('Vivaldi codec private evidence retained: ' + str(work), file=sys.stderr)
        raise
    try:
        archive.unlink()
        work.rmdir()
    except OSError as error:
        raise PublicationOutcomeUnknown('codec published; private staging cleanup failed: ' + str(work)) from error
    print('Vivaldi compatible codec installed from packaged Electron release: ' + release.version)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package_directory', type=Path)
    parser.add_argument('media_directory', type=Path)
    parser.add_argument('pidwait', type=Path)
    args = parser.parse_args()
    def expired(_signum, _frame):
        raise TimeoutError('Vivaldi codec operation deadline exceeded')

    try:
        if os.geteuid() != 0:
            raise ValueError('codec installation requires the target root account')
        os.umask(0o077)
        signal.signal(signal.SIGALRM, expired)
        signal.alarm(180)
        install(args.package_directory, args.media_directory, args.pidwait)
    except PublicationOutcomeUnknown as error:
        print('fatal: Vivaldi codec publication outcome unknown: ' + str(error)
              + '; retain evidence and do not retry automatically', file=sys.stderr)
        return 3
    except (OSError, ValueError, UnicodeError, EOFError, zipfile.BadZipFile, zlib.error,
            urllib.error.URLError, subprocess.TimeoutExpired) as error:
        # Network errors may contain signed redirect URLs. Keep those private.
        detail = str(error) if isinstance(error, ValueError) else type(error).__name__
        print('fatal: Vivaldi codec installation failed: ' + detail
              + '; previous codec preserved; private staging retained', file=sys.stderr)
        return 1
    finally:
        signal.alarm(0)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
