"""Read the pinned outer theme release as bounded data, never through tar extraction."""
from __future__ import annotations
import gzip
import hashlib
import io
import os
from pathlib import Path
import stat
import tarfile
import time
from managed_workflows.fs import Tree, parts


def main(archive_path: str, destination: str) -> int:
    deadline = time.monotonic() + 180
    expanded_limit = int('__INSTALLER_LABWC_DESKTOP_THEMES_MAXIMUM_EXTRACTED_BYTES__')
    member_limit = int('__INSTALLER_LABWC_DESKTOP_THEMES_MAXIMUM_MEMBERS__')
    expected_digest = '__INSTALLER_LABWC_DESKTOP_THEMES_SHA256__'
    expected_destination = Path('__INSTALLER_PATH_DIR_USR_LOCAL_SHARE_LABWC_APPEARANCE__/.installer-themes')
    if (Path(destination) != expected_destination
            or not 1 <= expanded_limit <= 1024 * 1024**2 or not 1 <= member_limit <= 4096):
        raise ValueError('invalid outer desktop theme release policy')

    def check():
        if time.monotonic() >= deadline:
            raise TimeoutError('outer desktop theme release deadline exceeded')

    descriptor = os.open(archive_path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    with os.fdopen(descriptor, 'rb') as stream:
        before = os.fstat(stream.fileno())
        if (not stat.S_ISREG(before.st_mode) or before.st_uid != 0 or before.st_gid != 0
                or before.st_nlink != 1 or stat.S_IMODE(before.st_mode) != 0o600
                or before.st_size <= 0):
            raise ValueError('unsafe outer desktop theme release metadata')
        digest = hashlib.sha256()
        while blob := stream.read(1024 * 1024):
            check()
            digest.update(blob)
        after = os.fstat(stream.fileno())
        if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (
                after.st_size, after.st_mtime_ns, after.st_ctime_ns) or digest.hexdigest() != expected_digest:
            raise ValueError('outer desktop theme release identity changed or digest differs')
        stream.seek(0)
        expanded = io.BytesIO()
        with gzip.GzipFile(fileobj=stream) as compressed:
            while blob := compressed.read(min(1024 * 1024, expanded_limit + 1 - expanded.tell())):
                check()
                expanded.write(blob)
                if expanded.tell() > expanded_limit:
                    raise ValueError('expanded outer desktop theme release exceeds its budget')
        final = os.fstat(stream.fileno())
        if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (
                final.st_size, final.st_mtime_ns, final.st_ctime_ns):
            raise ValueError('outer desktop theme release changed during decompression')
    expanded.seek(0)
    root = None
    files = {}
    seen = set()
    total = count = 0
    with tarfile.open(fileobj=expanded, mode='r:') as archive:
        for member in archive:
            check()
            count += 1
            if count > member_limit:
                raise ValueError('outer desktop theme release member budget exceeded')
            if member.name in ('.', './') and member.isdir() and member.size == 0:
                continue  # A tar wrapper directory carries no extracted path.
            name = member.name.removeprefix('./').rstrip('/')
            if '\\' in name or len(name.encode('utf-8')) > 512:
                raise ValueError('outer desktop theme release name exceeds its budget')
            segments = parts(name)
            if name in seen or len(segments) > 16 or member.mode & 0o7000:
                raise ValueError('unsafe or duplicate outer desktop theme release member')
            seen.add(name)
            root = segments[0] if root is None else root
            if segments[0] != root or not (member.isdir() or member.isfile()):
                raise ValueError('outer desktop theme release has mixed roots or non-regular data')
            if member.isdir():
                if member.size:
                    raise ValueError('outer desktop theme release directory carries data')
                continue
            if len(segments) < 2 or not 0 <= member.size <= 32 * 1024**2:
                raise ValueError('outer desktop theme release file exceeds its budget')
            relative = '/'.join(segments[1:])
            if relative != 'sources.json' and segments[1] not in ('gtk', 'qt', 'licenses'):
                raise ValueError('outer desktop theme release has an unexpected source path')
            total += member.size
            if total > expanded_limit:
                raise ValueError('outer desktop theme release data exceeds its budget')
            source = archive.extractfile(member)
            if source is None:
                raise ValueError('missing outer desktop theme release member data')
            with source:
                blob = source.read(member.size + 1)
            if len(blob) != member.size:
                raise ValueError('truncated outer desktop theme release member')
            files[relative] = blob
    if 'sources.json' not in files:
        raise ValueError('outer desktop theme release lacks its source inventory')
    with Tree(expected_destination, uid=0, private=True) as output:
        for relative, blob in files.items():
            check()
            output.write(relative, blob, mode=0o600, replace=False)
    return 0
