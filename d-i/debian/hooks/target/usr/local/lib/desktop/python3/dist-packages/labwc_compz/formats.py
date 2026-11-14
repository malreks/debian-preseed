"""Fixed codec commands: no shell, user configuration, plugin paths or argv secrets."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import os

from . import CompzError

SEVEN = '__INSTALLER_PATH_DIR_USR_LOCAL_LIB__/compz/7zz'
WORKER = '__INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/compz-worker'
PIPELINE = '__INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/compz-pipeline'
ENV = {'PATH': '__INSTALLER_PATH_DIR_USR__/bin:/bin', 'HOME': '/nonexistent', 'LC_ALL': 'C.UTF-8',
       'TMPDIR': '__INSTALLER_PATH_DIR_TMP__', 'LRZIP': 'NOCONFIG', 'PYTHONDONTWRITEBYTECODE': '1'}


@dataclass(frozen=True)
class Codec:
    key: str
    label: str
    suffix: str
    binary: str
    stream: bool = True


CODECS = (
    Codec('zstd', 'Zstandard', '.tar.zst', '__INSTALLER_PATH_DIR_USR__/bin/zstd'),
    Codec('gzip', 'gzip / DEFLATE', '.tar.gz', '__INSTALLER_PATH_DIR_USR__/bin/gzip'),
    Codec('xz', 'XZ / LZMA2', '.tar.xz', '__INSTALLER_PATH_DIR_USR__/bin/xz'),
    Codec('flzma2', 'Fast-LZMA2 (7z)', '.tar.flzma2.7z', SEVEN, False),
    Codec('7z', '7z / LZMA2', '.tar.7z', SEVEN, False),
    Codec('zip', 'ZIP / DEFLATE', '.tar.zip', SEVEN, False),
    Codec('rar', 'RAR5', '.tar.rar', '__INSTALLER_PATH_DIR_USR__/bin/rar', False),
    Codec('zpaq', 'ZPAQ', '.tar.zpaq', '__INSTALLER_PATH_DIR_USR__/bin/zpaq', False),
    Codec('zpaqfranz', 'ZPAQFRANZ', '.tar.zpaq', '__INSTALLER_PATH_DIR_USR__/bin/zpaqfranz', False),
    Codec('lrzip', 'LRZIP / LZMA', '.tar.lrz', '__INSTALLER_PATH_DIR_USR__/bin/lrzip', False),
    Codec('rzip', 'RZIP', '.tar.rz', '__INSTALLER_PATH_DIR_USR__/bin/rzip', False),
    Codec('kanzi', 'Kanzi (maximum = level 9 / TPAQX)', '.tar.knz', '__INSTALLER_PATH_DIR_USR__/bin/kanzi'),
    Codec('bzip3', 'bzip3 (maximum = 511 MiB block)', '.tar.bz3', '__INSTALLER_PATH_DIR_USR__/bin/bzip3'),
    Codec('bzip2', 'bzip2', '.tar.bz2', '__INSTALLER_PATH_DIR_USR__/bin/bzip2'),
    Codec('lzip', 'lzip / LZMA', '.tar.lz', '__INSTALLER_PATH_DIR_USR__/bin/lzip'),
    Codec('lz4', 'LZ4', '.tar.lz4', '__INSTALLER_PATH_DIR_USR__/bin/lz4'),
    Codec('tar', 'TAR (uncompressed)', '.tar', '__INSTALLER_PATH_DIR_USR__/bin/python3'),
)
BY_KEY = {codec.key: codec for codec in CODECS}


def available_codecs() -> tuple[Codec, ...]:
    # Debian's non-free rar archiver is published for amd64 only. Extraction
    # remains available through unrar on arm64; never offer an unusable writer.
    return tuple(codec for codec in CODECS if codec.key != 'rar' or os.access(codec.binary, os.X_OK))


SUFFIXES = {
    '.tar.flzma2.7z': '7z', '.7z': '7z', '.zip': 'zip', '.rar': 'rar',
    '.zpaq': 'zpaqfranz', '.gz': 'gzip', '.tgz': 'gzip', '.xz': 'xz',
    '.txz': 'xz', '.lzma': 'xz', '.zst': 'zstd', '.zstd': 'zstd',
    '.tzst': 'zstd', '.bz2': 'bzip2', '.tbz2': 'bzip2', '.tbz': 'bzip2',
    '.bz3': 'bzip3', '.lz': 'lzip', '.lz4': 'lz4', '.lrz': 'lrzip',
    '.rz': 'rzip', '.knz': 'kanzi', '.tar': 'tar', '.gpg': 'gpg', '.pgp': 'gpg',
}


def identify(name: str) -> str:
    lower = name.lower()
    for suffix in sorted(SUFFIXES, key=len, reverse=True):
        if lower.endswith(suffix):
            return SUFFIXES[suffix]
    raise CompzError('Unrecognized archive extension; rename it to its actual format first.')


def stem(name: str) -> str:
    value = name
    if value.lower().endswith(('.gpg', '.pgp')):
        value = value[:-4]
    for suffix in sorted({c.suffix for c in CODECS} | set(SUFFIXES), key=len, reverse=True):
        if value.lower().endswith(suffix):
            value = value[:-len(suffix)]
            break
    if value.lower().endswith('.tar'):
        value = value[:-4]
    if value in ('', '.', '..'):
        value = 'archive'
    return value


def compression(codec: Codec, tier: int, threads: int, memory_mib: int, output: Path) -> list[str]:
    if tier not in (0, 1, 2) or not 1 <= threads <= 64 or memory_mib < 256:
        raise CompzError('Invalid codec resource policy.')
    level = (1, 6, 9)[tier]
    key, binary = codec.key, codec.binary
    if key == 'gzip':
        return [binary, '-n', '-c', f'-{level}']
    if key == 'bzip2':
        return [binary, '-c', f'-{level}']
    if key == 'xz':
        return [binary, '-c', ('-0', '-6', '-9e')[tier], f'-T{threads}',
                f'--memlimit-compress={memory_mib}MiB']
    if key == 'zstd':
        return [binary, '-q', '-c', '--check', f'-T{threads}', '--ultra', f'-{(3, 9, 22)[tier]}']
    if key == 'lzip':
        return [binary, '-c', f'-{(0, 6, 9)[tier]}']
    if key == 'lz4':
        return [binary, '-q', '-c', f'-{(1, 6, 12)[tier]}']
    if key == 'bzip3':
        block = (4, 16, 511)[tier]
        jobs = min(threads, max(1, (memory_mib - 128) // (6 * block)))
        if memory_mib < 6 * block + 128:
            raise CompzError('bzip3 maximum needs at least 3194 MiB; raise the memory limit or choose a smaller ratio.')
        return [binary, '-c', '-b', str(block), '-j', str(jobs)]
    if key == 'kanzi':
        # Upstream explicitly forbids stdout with jobs > 1. One job still
        # pipelines concurrently with the tar producer, without a disk spool.
        return [binary, '-c', '--input=stdin', '--output=stdout', '--jobs=1',
                f'--level={(1, 6, 9)[tier]}', '--checksum=64', '--verbose=0']
    if key in ('7z', 'flzma2', 'zip'):
        method = {'7z': '-m0=LZMA2', 'flzma2': '-m0=FLZMA2', 'zip': '-mm=Deflate'}[key]
        return [binary, 'a', '-bd', '-y', '-tzip' if key == 'zip' else '-t7z', method,
                f'-mx={level}', f'-mmt={threads}', '--', str(output), 'payload.tar']
    if key == 'rar':
        if not os.access(binary, os.X_OK):
            raise CompzError('RAR creation needs the amd64 Debian rar package.')
        return [binary, 'a', '-cfg-', '-idq', '-ma5', f'-m{(1, 3, 5)[tier]}',
                '-ep', '-o-', '--', str(output), 'payload.tar']
    if key in ('zpaq', 'zpaqfranz'):
        return [binary, 'a', str(output), 'payload.tar', '-method', str((1, 3, 5)[tier]),
                '-threads', str(threads)]
    if key == 'lrzip':
        return [binary, '-q', '-L', str(level), '-p', str(threads), '-o', str(output), 'payload.tar']
    if key == 'rzip':
        return [binary, '-k', f'-{level}', '-o', str(output), 'payload.tar']
    raise CompzError('Codec has no compression command.')


def decompression(key: str, source: Path, threads: int, memory_mib: int) -> list[str]:
    binary = BY_KEY[key].binary
    if key == 'kanzi':
        return [binary, '-d', '-i', str(source), '-o', 'stdout', '-j', '1', '-v', '0']
    if key == 'xz':
        return [binary, '-dc', f'-T{threads}', f'--memlimit-decompress={memory_mib}MiB', '--', str(source)]
    if key == 'zstd':
        return [binary, '-q', '-dc', f'--memory={memory_mib}MB', '--', str(source)]
    if key == 'bzip3':
        return [binary, '-dc', '-j', '1', '--', str(source)]
    return [binary, '-dc', '--', str(source)]


def missing() -> list[str]:
    required = {codec.binary for codec in available_codecs()} | {
        '__INSTALLER_PATH_DIR_USR__/bin/bwrap', '__INSTALLER_PATH_DIR_USR__/bin/aa-exec', '__INSTALLER_PATH_DIR_USR__/bin/systemd-run', '__INSTALLER_PATH_DIR_USR__/bin/systemctl', '__INSTALLER_PATH_DIR_USR__/bin/fzf',
        '__INSTALLER_PATH_DIR_USR__/bin/perl', '__INSTALLER_PATH_DIR_USR__/bin/gpg', '__INSTALLER_PATH_DIR_USR__/bin/gpgconf', '__INSTALLER_PATH_DIR_USR__/bin/gpg-agent',
        '__INSTALLER_PATH_DIR_USR__/bin/unrar-nonfree', WORKER, PIPELINE, '__INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/compz-sandbox',
    }
    return sorted(path for path in required if not os.access(path, os.X_OK))
