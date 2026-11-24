#!/usr/bin/env python3
"""Create one flat installer-source bundle and download catalogs for both suites.

Only offline/payload.tar.gz is published. Package files and nested installer
payload archives are never read or included. Public Debian repository metadata
is read to obtain exact Filename/Version/Architecture/SHA256 records; no host
APT state, package manager, credentials, Git checkout or target helper is used.
"""
from __future__ import annotations

import argparse
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack
from email.utils import parsedate_to_datetime
from datetime import timezone
from functools import cmp_to_key, lru_cache
import fnmatch
import gzip
import http.client
import io
import ipaddress
import json
import lzma
import os
from pathlib import Path
import re
import shlex
import shutil
import socket
import sqlite3
import stat
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
from urllib.parse import quote, unquote, urlsplit
import urllib.error
import urllib.request
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / 'tools'))
import build as installer_build
from class_compiler import assignment_data, repository_data
from publication import BuildOwnership, FILE_LIMIT, PublicationOutcomeUnknown, atomic_write

SUITES = ('forky', 'trixie')
# The output and archive layout are the standalone interface requested by the user.
OUTPUT_DIRECTORY = ROOT / 'offline'
OUTPUT_NAME = 'payload.tar.gz'
METADATA_LIMIT = 64 * 1024 * 1024
EXPANDED_INDEX_LIMIT = 256 * 1024 * 1024
GENERATION_SECONDS = 1800
CATALOG_BYTE_LIMIT = 32 * 1024 * 1024
DATABASE_BYTE_LIMIT = 8 * 1024 * 1024 * 1024
BUNDLE_BYTE_LIMIT = 512 * 1024 * 1024
METADATA_BYTE_LIMIT = 1024 * 1024 * 1024
NODE_LIMIT = 100000
EDGE_LIMIT = 2000000
URL_PATTERN = re.compile(r'(?:https?://|git://|ssh://|git@)[^\s\x00-\x20\"\'<>`\\]+')
GIT_HOSTS = {'github.com', 'api.github.com', 'codeload.github.com',
             'raw.githubusercontent.com', 'gitlab.com', 'salsa.debian.org', 'codeberg.org'}
DEBIAN_HOSTS = {'mirrors.glesys.net', 'deb.debian.org', 'security.debian.org',
                'snapshot.debian.org', 'ftp.debian.org', 'ftp-master.debian.org'}


def encoded(value: object) -> bytes:
    return (json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + '\n').encode()


def encoded_catalog(value: object) -> bytes:
    data = (json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False) + '\n').encode()
    print(f'offline: catalog bytes={len(data)} packages={len(value["packages"])} '
          f'sources={len(value["source_packages"])}', flush=True)
    if len(data) > CATALOG_BYTE_LIMIT:
        raise ValueError(f'APT catalog exceeds its byte limit: bytes={len(data)} packages={len(value["packages"])}')
    return data


def safe_relative(name: str) -> None:
    if (not name or name.startswith('/') or len(name) > 240
            or any(p in {'', '.', '..'} for p in name.split('/'))
            or re.fullmatch(r'[A-Za-z0-9_./@+ ~%-]+', name) is None):
        raise ValueError('unsafe archive or metadata member path')


class OfflineCapture(installer_build.SourceCapture):
    """Include this standalone compiler in the shared capture/verify protocol."""

    def _discover(self) -> tuple[dict, dict]:
        files, directories = super()._discover()
        relative = Path(__file__).relative_to(ROOT).as_posix()
        parent, leaf = relative.rsplit('/', 1)
        descriptor = self._directory(parent, directories)
        try:
            pinned = os.open(leaf, os.O_PATH | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=descriptor)
            try:
                info = os.fstat(pinned)
                if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_mode & 0o111
                        or info.st_size > installer_build.SOURCE_FILE_LIMIT):
                    raise ValueError('offline compiler is not a bounded, non-executable regular source')
                files[relative] = (None, installer_build.source_identity(info))
                if (len(files) > installer_build.SOURCE_MEMBER_LIMIT
                        or sum(value[1][6] for value in files.values()) > installer_build.SOURCE_BYTE_LIMIT):
                    raise ValueError('offline compiler capture exceeds source limits')
            finally:
                os.close(pinned)
        finally:
            os.close(descriptor)
        return files, directories


def compile_snapshot(sources: dict[str, bytes], compiler: dict[str, bytes]
                     ) -> tuple[str, str, dict[str, bytes], dict[str, bytes], dict]:
    """Use the shared class compiler without creating its normal payload archive."""
    captured = dict(sources)
    frontends = {name.removeprefix('frontends/'): data for name, data in sources.items()
                 if name.startswith('frontends/')}
    compiled, roles, matrix = installer_build.compile_classes(captured)
    snapshot = dict(sources)
    for name, data in compiled.items():
        if name in snapshot:
            raise ValueError('compiled source collides with an authored member')
        snapshot[name] = data
    # The same compiled membership catalogs serve online and offline payloads;
    # generated FILE aliases are not appended to operator configuration.
    identities = [f'{installer_build.sha(data)}  source/{name}\n' for name, data in sorted(sources.items())]
    identities += [f'{installer_build.sha(data)}  compiler/{name}\n' for name, data in sorted(compiler.items())]
    fingerprint = installer_build.sha(''.join(sorted(identities)).encode())
    release = installer_build.sha((fingerprint + '\n' + ''.join(
        f'{installer_build.sha(data)}  {name}\n' for name, data in sorted(snapshot.items()))).encode())
    snapshot['catalog/compiled/release.tsv'] = f'format\t1\nrelease\t{release}\nsource\t{fingerprint}\n'.encode()
    return release, fingerprint, snapshot, {**frontends, **roles}, matrix


class AcquisitionBudget:
    def __init__(self):
        self.deadline = time.monotonic() + GENERATION_SECONDS
        self.bytes = 0
        self.lock = threading.Lock()

    def add(self, size: int) -> None:
        with self.lock:
            self.bytes += size
            if self.bytes > METADATA_BYTE_LIMIT:
                raise ValueError('aggregate repository metadata byte limit exceeded')

    def remaining(self, maximum: float = 30) -> float:
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise ValueError('offline metadata and dependency generation deadline exceeded')
        return min(maximum, remaining)


def metadata_url(url: str) -> None:
    parsed = urlsplit(url)
    if (parsed.scheme != 'https' or not parsed.hostname or parsed.username is not None or parsed.password is not None
            or parsed.query or parsed.fragment or parsed.port not in {None, 443}
            or '..' in unquote(parsed.path).split('/')):
        raise ValueError('repository metadata requires a credential-free HTTPS URL')


class PublicHTTPSConnection(http.client.HTTPSConnection):
    """Validate DNS results and connect to the validated address without a second lookup."""
    def connect(self):
        if self._tunnel_host:
            raise ValueError('metadata connections may not use a proxy tunnel')
        addresses = socket.getaddrinfo(self.host, self.port, type=socket.SOCK_STREAM)
        if not addresses or any(not ipaddress.ip_address(item[4][0]).is_global for item in addresses):
            raise ValueError('metadata destination is not a public Internet address')
        last_error = None
        for family, kind, protocol, _, address in addresses[:8]:
            connection = socket.socket(family, kind, protocol)
            try:
                connection.settimeout(self.timeout)
                connection.connect(address)
                self.sock = self._context.wrap_socket(connection, server_hostname=self.host)
                return
            except OSError as error:
                connection.close()
                last_error = error
        raise OSError('cannot connect to the public metadata destination') from last_error


class MetadataReader:
    """Bounded metadata-only HTTPS, or an explicit read-only metadata fixture."""

    def __init__(self, mirror: str, directory: Path | None,
                 budget: AcquisitionBudget | None = None, cache: Path | None = None):
        self.mirror = mirror.rstrip('/')
        metadata_url(self.mirror)
        self.directory = directory
        self.budget = budget or AcquisitionBudget()
        self.deadline = self.budget.deadline
        self.cache = cache
        owner = self

        class HTTPS(urllib.request.HTTPSHandler):
            def https_open(self, request):
                return self.do_open(PublicHTTPSConnection, request)

        class Redirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, request, fp, code, msg, headers, newurl):
                parsed = urlsplit(newurl)
                if (parsed.scheme != 'https' or not parsed.hostname or parsed.username is not None
                        or parsed.password is not None or parsed.fragment or parsed.port not in {None, 443}
                        or '..' in unquote(parsed.path).split('/')):
                    raise ValueError('metadata redirect violates HTTPS or credential policy')
                if urlsplit(owner.mirror).hostname == 'mirrors.glesys.net' and parsed.netloc != 'mirrors.glesys.net':
                    raise ValueError('official metadata redirect leaves the GLESYS mirror')
                if getattr(request, '_offline_hops', 0) >= 5:
                    raise ValueError('metadata redirect limit exceeded')
                redirected = super().redirect_request(request, fp, code, msg, headers, newurl)
                redirected._offline_hops = getattr(request, '_offline_hops', 0) + 1
                return redirected

        self.opener = urllib.request.build_opener(HTTPS(), Redirect(), urllib.request.ProxyHandler({}))

    def local_descriptor(self, relative: str) -> int:
        """Pin only a regular metadata leaf, with no symlink traversal."""
        safe_relative(relative)
        assert self.directory is not None
        candidates = ['url-' + installer_build.sha((self.mirror + '/' + relative).encode()), (
            (urlsplit(self.mirror).netloc + urlsplit(self.mirror).path + '/' + relative)
            .replace('_', '%5f').replace('/', '_'))]
        if urlsplit(self.mirror).hostname == 'mirrors.glesys.net':
            candidates.append(relative)
        descriptor = os.open('/', os.O_DIRECTORY | os.O_RDONLY | os.O_CLOEXEC)
        try:
            for part in self.directory.parts[1:]:
                if part in {'', '.', '..'}:
                    raise ValueError('unsafe metadata snapshot directory')
                child = os.open(part, os.O_DIRECTORY | os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC,
                                dir_fd=descriptor)
                os.close(descriptor)
                descriptor = child
            for candidate in candidates:
                parent = os.dup(descriptor)
                try:
                    parts = candidate.split('/')
                    for part in parts[:-1]:
                        child = os.open(part, os.O_DIRECTORY | os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC,
                                        dir_fd=parent)
                        os.close(parent)
                        parent = child
                    pinned = os.open(parts[-1], os.O_PATH | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=parent)
                    if not stat.S_ISREG(os.fstat(pinned).st_mode):
                        os.close(pinned)
                        raise ValueError('metadata snapshot leaf is not a regular file')
                    return pinned
                except FileNotFoundError:
                    continue
                finally:
                    os.close(parent)
            raise FileNotFoundError('required index is absent from the metadata snapshot')
        finally:
            os.close(descriptor)

    def available(self, relative: str) -> bool:
        if self.directory is None:
            return True
        try:
            descriptor = self.local_descriptor(relative)
        except FileNotFoundError:
            return False
        os.close(descriptor)
        return True

    def read(self, relative: str, maximum: int = METADATA_LIMIT) -> bytes:
        safe_relative(relative)
        if self.directory is not None:
            pinned = self.local_descriptor(relative)
            try:
                before = os.fstat(pinned)
                if before.st_size > maximum:
                    raise ValueError('metadata snapshot exceeds its byte limit')
                # Linux descriptor reopening preserves the pinned regular-file identity.
                fd = os.open(f'/proc/self/fd/{pinned}', os.O_RDONLY | os.O_CLOEXEC)
                with os.fdopen(fd, 'rb') as stream:
                    data = stream.read(maximum + 1)
                after = os.fstat(pinned)
                if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (
                        after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns):
                    raise ValueError('metadata snapshot changed while being read')
                if len(data) != before.st_size:
                    raise ValueError('metadata snapshot size changed while being read')
                self.budget.add(len(data))
            finally:
                os.close(pinned)
        else:
            remaining = self.deadline - time.monotonic()
            if remaining <= 0:
                raise ValueError('offline metadata acquisition deadline exceeded')
            request = urllib.request.Request(self.mirror + '/' + relative,
                                             headers={'User-Agent': 'debian-preseed-offline/2'})
            with self.opener.open(request, timeout=min(30, remaining)) as response:
                chunks, size = [], 0
                while True:
                    if time.monotonic() > self.deadline:
                        raise ValueError('offline metadata acquisition deadline exceeded')
                    chunk = response.read(min(1024 * 1024, maximum + 1 - size))
                    if not chunk:
                        break
                    size += len(chunk)
                    if size > maximum:
                        raise ValueError('Debian metadata exceeds byte limit')
                    self.budget.add(len(chunk))
                    chunks.append(chunk)
                data = b''.join(chunks)
        if len(data) > maximum:
            raise ValueError('Debian metadata exceeds byte limit')
        if self.cache is not None and self.directory is None:
            atomic_write(self.cache / ('url-' + installer_build.sha((self.mirror + '/' + relative).encode())), data, 0o600)
        return data

    def optional(self, relative: str, maximum: int = METADATA_LIMIT) -> bytes | None:
        try:
            return self.read(relative, maximum)
        except urllib.error.HTTPError as error:
            if error.code not in {404, 410}:
                raise
            return None
        except FileNotFoundError:
            if self.directory is None:
                raise
            return None


def release_metadata(data: bytes, official: bool = True) -> tuple[dict[str, str], dict[str, tuple[str, int]]]:
    text = data.decode('utf-8')
    if text.startswith('-----BEGIN PGP SIGNED MESSAGE-----\n'):
        if '\n\n' not in text or '-----BEGIN PGP SIGNATURE-----' not in text:
            raise ValueError('malformed clearsigned release metadata')
        body = text.split('\n\n', 1)[1].split('-----BEGIN PGP SIGNATURE-----', 1)[0]
    else:
        body = text
    fields, hashes = {}, {}
    in_hashes = False
    for line in body.splitlines():
        line = line.removeprefix('- ')
        if line == 'SHA256:':
            in_hashes = True
            continue
        if in_hashes:
            match = re.fullmatch(r'\s+([a-f0-9]{64})\s+([0-9]+)\s+(\S+)', line)
            if match:
                hashes[match[3]] = (match[1], int(match[2]))
                continue
            in_hashes = False
        if line and not line[0].isspace() and ': ' in line:
            key, value = line.split(': ', 1)
            fields[key] = value
    if not hashes or official and fields.get('Origin') not in {'Debian', 'Debian Backports'}:
        raise ValueError('metadata is not an official Debian SHA256 release')
    return fields, hashes


def package_paragraphs(data: bytes, filename: str, selected: set[str] | None = None):
    """Stream bounded Deb822 stanzas, including empty multiline field headers."""
    if filename.endswith('.xz'):
        stream = lzma.LZMAFile(io.BytesIO(data))
    elif filename.endswith('.gz'):
        stream = gzip.GzipFile(fileobj=io.BytesIO(data))
    else:
        stream = io.BytesIO(data)
    record, total, record_bytes, last_key, seen = {}, 0, 0, '', set()
    with stream:
        while raw := stream.readline(1024 * 1024 + 1):
            total += len(raw)
            record_bytes += len(raw)
            if len(raw) > 1024 * 1024 or total > EXPANDED_INDEX_LIMIT or record_bytes > 4 * 1024 * 1024:
                raise ValueError('expanded Deb822 index or stanza exceeds its byte limit')
            line = raw.decode('utf-8').rstrip('\r\n')
            if not line.strip():
                if record:
                    yield record
                record, record_bytes, last_key, seen = {}, 0, '', set()
            elif line[0] in ' \t':
                if not last_key:
                    raise ValueError('Deb822 continuation has no field')
                if last_key in record:
                    record[last_key] += '\n' + line[1:]
            else:
                key, separator, value = line.partition(':')
                key = key.lower()
                if not separator or not re.fullmatch(r'[a-z0-9][a-z0-9-]*', key) or key in seen:
                    raise ValueError('malformed or duplicate Deb822 field')
                seen.add(key)
                last_key = key
                if selected is None or key in selected:
                    record[key] = value.strip()
        if record:
            yield record


def cfg_records(data: bytes):
    pending, first = '', 0
    for number, line in enumerate(data.decode().splitlines(), 1):
        if not pending:
            first = number
        pending += line.rstrip()[:-1] + ' ' if line.rstrip().endswith('\\') else line
        if line.rstrip().endswith('\\'):
            continue
        yield first, pending.strip()
        pending = ''
    if pending:
        raise ValueError('unterminated preseed continuation')


def repository_inventory(sources: dict[str, bytes], snapshot: dict[str, bytes]):
    declarations, requests, exclusions = [], {}, {suite: set() for suite in SUITES}
    architectures = sorted({name.rsplit('/', 1)[1].removesuffix('.cfg') for name in sources
                            if '/classes/class-auto/arch/' in name and name.endswith('.cfg')})
    if not architectures or not set(architectures) <= {'amd64', 'arm64'}:
        raise ValueError('unknown package-index architecture set')

    def request(suite, kind, value, origin, arches=None):
        if value in {'none', ''}:
            return
        if re.fullmatch(r'[a-z0-9][a-z0-9+.-]*(?::[a-z0-9-]+)?(?:[=/][A-Za-z0-9.+:~_-]+)?', value) is None:
            raise ValueError('unsupported package request in ' + origin['source'])
        row = requests.setdefault((suite, kind, value), {'suite': suite, 'kind': kind, 'request': value,
                                  'origins': [], 'architectures': set(), 'families': set()})
        row['origins'].append(origin)
        row['architectures'].update(arches or architectures)
        family = re.search(r'/(?:role|scripts)/(desktop|server)/', '/' + origin['source'])
        row['families'].update([family[1]] if family else ['desktop', 'server'])

    for name, data in sorted(sources.items()):
        if not name.startswith('frontends/') or not name.endswith('.cfg'):
            continue
        if re.match(r'frontends/(forky|trixie)/hooks/target/etc/apt/(desktop|server)/(sources.list.d|preferences.d)/custom/', name):
            continue
        suite = name.split('/')[1]
        records = list(cfg_records(data))
        answers = {}
        for number, line in records:
            match = re.fullmatch(r'd-i (apt-setup/[^ ]+)/(repository|key|source|options) (?:string|boolean) (.+)', line)
            if match:
                answers.setdefault(match[1], {})[match[2]] = (number, match[3])
        for slot, values in sorted(answers.items()):
            if 'repository' not in values:
                continue
            number, value = values['repository']
            tokens = shlex.split(value)
            if len(tokens) < 2:
                raise ValueError('incomplete APT repository declaration')
            options = dict(option.split('=', 1) for option in
                           shlex.split(values.get('options', (0, ''))[1]) if '=' in option)
            declarations.append({'url': tokens[0].rstrip('/'), 'archive': tokens[1],
                'components': tokens[2:],
                'architectures': options['arch'].split(',') if 'arch' in options else list(architectures),
                'suite': suite,
                'key_urls': [values['key'][1]] if 'key' in values else [],
                'types': ['deb', 'deb-src'] if values.get('source', (0, 'false'))[1] == 'true' else ['deb'],
                'source': name, 'line': number, 'slot': slot})
        for number, line in records:
            match = re.fullmatch(r'd-i (pkgsel/include|anna/choose_modules|base-installer/includes|base-installer/kernel/image) (?:string|multiselect) (.+)', line)
            if match:
                kind = {'pkgsel/include': 'pkgsel', 'anna/choose_modules': 'anna'}.get(match[1], 'base-installer')
                arch = re.search(r'/classes/class-auto/arch/(amd64|arm64)\.cfg$', name)
                for value in match[2].replace(',', ' ').split():
                    request(suite, kind, value, {'source': name, 'line': number, 'question': match[1]},
                            [arch[1]] if arch else None)
            match = re.fullmatch(r'd-i base-installer/excludes string (.+)', line)
            if match:
                exclusions[suite].update(match[1].split())

    # Additional Debian/FHS APT source files are data, never shell programs.
    for name, data in sorted(sources.items()):
        if re.match(r'frontends/(forky|trixie)/hooks/target/etc/apt/(desktop|server)/(sources.list.d|preferences.d)/custom/', name):
            continue  # Finish-install copies opaque user inputs after pkgsel.
        if '.sources' not in name and not name.endswith(('.list', '.list.tmpl')):
            continue
        suite = name.split('/')[1] if name.startswith('frontends/') else None
        for fields in package_paragraphs(data, name) if '.sources' in name else ():
            if fields.get('enabled', 'yes').lower() == 'no':
                continue
            for uri in fields.get('uris', '').split():
                for archive in fields.get('suites', '').split():
                    for owner in [suite] if suite else SUITES:
                        declarations.append({'url': uri.rstrip('/'), 'archive': archive,
                            'components': fields.get('components', '').split(),
                            'architectures': fields.get('architectures', ' '.join(architectures)).split(),
                            'suite': owner, 'types': fields.get('types', 'deb').split(), 'key_urls': [],
                            'signed_by': fields.get('signed-by', ''), 'source': name, 'line': 1})
        if name.endswith(('.list', '.list.tmpl')):
            for number, line in enumerate(data.decode().splitlines(), 1):
                match = re.fullmatch(r'\s*(deb|deb-src)\s+(?:\[([^]]+)\]\s+)?(\S+)\s+(\S+)(?:\s+(.*))?', line)
                if match:
                    for owner in [suite] if suite else SUITES:
                        options = dict(pair.split('=', 1) for pair in (match[2] or '').split() if '=' in pair)
                        declarations.append({'url': match[3].rstrip('/'), 'archive': match[4],
                            'components': (match[5] or '').split(), 'architectures': options.get('arch', ','.join(architectures)).split(','),
                            'suite': owner, 'types': [match[1]], 'key_urls': [], 'signed_by': options.get('signed-by', ''),
                            'source': name, 'line': number})

    # Profile-defined legacy APT policy is also emitted by the target dispatcher.
    for name, data in sorted(snapshot.items()):
        if '/profiles/' not in name or not name.startswith('catalog/compiled/') or not name.endswith('.env') or name.endswith('.account.env'):
            continue
        values, provenance = {}, {}
        assignment_data(data.decode(), values, provenance, name, literals=True)
        if values.get('CUDA_LEGACY_REPOSITORY_URL'):
            declarations.append({'url': values['CUDA_LEGACY_REPOSITORY_URL'].rstrip('/'), 'archive': '/',
                'components': [], 'architectures': ['amd64'], 'suite': name.split('/')[2], 'types': ['deb'],
                'key_urls': [values['CUDA_LEGACY_REPOSITORY_KEY']], 'source': name, 'line': 0,
                'declared_legacy_policy': 'target dispatcher explicitly allows insecure/weak legacy metadata'})

    # Only authored installer-helper requests seed the udeb closure.
    helper = re.compile(r'\b(?:hook_(?:ensure|preload|require|try)_installer_(?:tool|command|udeb)|ensure_installer_tool)\s+([a-z0-9+.-]+)(?:\s+([a-z0-9+.-]+))?')
    for name, data in sorted(sources.items()):
        if not name.endswith(('.sh', '.tmpl')):
            continue
        if re.match(r'frontends/(forky|trixie)/hooks/target/etc/apt/(desktop|server)/(sources.list.d|preferences.d)/custom/', name):
            continue
        for number, line in enumerate(data.decode(errors='replace').splitlines(), 1):
            match = helper.search(line)
            if match and not line.lstrip().startswith('#'):
                value = match[1] if match[0].split()[0].endswith('_udeb') else match[2]
                if value:
                    for suite in SUITES:
                        request(suite, 'installer-hook', value, {'source': name, 'line': number})

        if name.startswith(('scripts/late/', 'scripts/server/', 'scripts/desktop/')):
            for number, line in cfg_records(data):
                if 'apt-get' not in line or 'install' not in line or line.startswith('#'):
                    continue
                try:
                    tokens = shlex.split(line, comments=True)
                except ValueError:
                    continue  # Multiline target programs contain dynamic argv.
                commands = [i for i, token in enumerate(tokens) if token == 'apt-get' or token.endswith('/apt-get')]
                if not commands: continue
                start = commands[0]
                if 'install' not in tokens[start + 1:]: continue
                position = tokens.index('install', start + 1) + 1
                while position < len(tokens):
                    value = tokens[position]
                    position += 1
                    if value in {'&&', '||', ';', '|', ')'}: break
                    if value in {'-o', '--option', '-t', '--target-release', '-c', '--config-file'}:
                        position += 1
                        continue
                    if value.startswith('-'): continue
                    value = value.rstrip(';)')
                    if re.fullmatch(r'[a-z0-9][a-z0-9+.-]*(?::[a-z0-9-]+)?(?:[=/][A-Za-z0-9.+:~_-]+)?', value):
                        for suite in SUITES:
                            request(suite, 'late-installer', value, {'source': name, 'line': number,
                                                                   'operation': 'literal apt-get install'})

    mirror = 'https://mirrors.glesys.net/debian'
    mirrors = {r['url'] for r in declarations if urlsplit(r['url']).hostname == 'mirrors.glesys.net'}
    if mirrors != {mirror}:
        raise ValueError('configured GLESYS mirror contract differs')
    debian_keys = sorted({key for row in declarations if row['url'] == mirror for key in row['key_urls']})
    for suite in SUITES:
        declarations.append({'url': mirror, 'archive': suite, 'components': ['main', 'contrib', 'non-free', 'non-free-firmware'],
            'architectures': architectures, 'suite': suite, 'types': ['deb', 'deb-src'], 'key_urls': debian_keys,
            'source': 'frontends/' + suite + '/common.cfg', 'line': 0})
    grouped = {}
    for declaration in declarations:
        archive = 'experimental' if declaration['archive'] == 'rc-buggy' else declaration['archive']
        identity = (declaration['url'], archive)
        key = installer_build.sha(('\n'.join(identity)).encode())[:24]
        repo = grouped.setdefault(identity, {'id': key, 'url': identity[0], 'archive': archive,
            'official': identity[0] == mirror, 'suites': set(), 'components': set(), 'architectures': set(),
            'types': set(), 'key_urls': set(), 'declarations': []})
        repo['suites'].add(declaration['suite'])
        for field in ('components', 'architectures', 'types', 'key_urls'):
            repo[field].update(declaration[field])
        repo['declarations'].append(declaration)
    repos = []
    for repo in grouped.values():
        for field in ('suites', 'components', 'architectures', 'types', 'key_urls'):
            repo[field] = sorted(repo[field])
        repos.append(repo)
    for row in requests.values():
        row['architectures'] = sorted(row['architectures'])
        row['families'] = sorted(row['families'])
    return mirror, architectures, sorted(repos, key=lambda r: (not r['official'], r['url'], r['archive'])), list(requests.values()), exclusions


@lru_cache(maxsize=32768)
def version_compare(left: str, right: str) -> int:
    """Debian Policy 5.6.12 ordering; do not compare version strings lexically."""
    def split(value):
        epoch, colon, rest = value.partition(':')
        if colon:
            if not epoch.isdecimal():
                raise ValueError('invalid Debian version epoch')
            value = rest
        else:
            epoch = '0'
        upstream, dash, revision = value.rpartition('-')
        return int(epoch), upstream if dash else value, revision if dash else '0'

    def part(a, b):
        def order(char):
            if char == '~': return -1
            if not char or char.isdigit(): return 0
            return ord(char) if char.isascii() and char.isalpha() else ord(char) + 256
        i = j = 0
        while i < len(a) or j < len(b):
            while (i < len(a) and not a[i].isdigit()) or (j < len(b) and not b[j].isdigit()):
                av, bv = order(a[i] if i < len(a) else ''), order(b[j] if j < len(b) else '')
                if av != bv: return (av > bv) - (av < bv)
                i += i < len(a)
                j += j < len(b)
            while i < len(a) and a[i] == '0': i += 1
            while j < len(b) and b[j] == '0': j += 1
            ai, bj = i, j
            while i < len(a) and a[i].isdigit(): i += 1
            while j < len(b) and b[j].isdigit(): j += 1
            av, bv = a[ai:i], b[bj:j]
            if len(av) != len(bv): return (len(av) > len(bv)) - (len(av) < len(bv))
            if av != bv: return (av > bv) - (av < bv)
        return 0

    a, b = split(left), split(right)
    return (a[0] > b[0]) - (a[0] < b[0]) or part(a[1], b[1]) or part(a[2], b[2])


def version_matches(actual: str | None, operator: str, expected: str) -> bool:
    if not operator:
        return True
    if actual is None:
        return False
    compared = version_compare(actual, expected)
    return {'=': compared == 0, '>=': compared >= 0, '<=': compared <= 0,
            '>>': compared > 0, '<<': compared < 0, '>': compared >= 0, '<': compared <= 0}[operator]


def architecture_matches(pattern: str, architecture: str) -> bool:
    return pattern in {architecture, 'any', 'linux-any', 'any-' + architecture}


RELATION = re.compile(r'\s*([a-z0-9][a-z0-9+.-]*)(?::([a-z0-9-]+))?'
    r'(?:\s*\((<<|<=|=|>=|>>|<|>)\s*([^\s()]+)\))?'
    r'(?:\s*\[([^]]+)\])?((?:\s*<[^>]+>)*)\s*')


def relations(value: str) -> tuple:
    if len(value) > 1024 * 1024:
        raise ValueError('package relationship field exceeds byte limit')
    return cached_relations(value) if len(value) <= 8192 else parse_relations(value)


@lru_cache(maxsize=2048)
def cached_relations(value: str) -> tuple:
    return parse_relations(value)


def parse_relations(value: str) -> tuple:
    groups = []
    for group in value.replace('\n', ' ').split(','):
        if not group.strip():
            continue
        alternatives = []
        for expression in group.split('|'):
            match = RELATION.fullmatch(expression)
            if not match:
                raise ValueError('unsupported package relationship expression')
            alternatives.append(tuple(item or '' for item in match.groups()))
        groups.append(tuple(alternatives))
    return tuple(groups)


def pool_url(root: str, path: str) -> str:
    while path.startswith('./'):
        path = path[2:]
    safe_relative(path)
    safe_relative(unquote(path))
    return root.rstrip('/') + '/' + quote(path, safe='/+~.-_')


class ReleaseVerifier:
    """Verify each release with only that declaration's downloaded public keyrings."""
    def __init__(self, workspace: Path, directory: Path | None, budget: AcquisitionBudget, cache: Path | None):
        self.workspace, self.directory, self.budget, self.cache = workspace, directory, budget, cache
        self.keys = {}
        self.evidence = {}
        self.gpg = shutil.which('gpg', path=os.defpath)
        self.gpgv = shutil.which('gpgv', path=os.defpath)
        if not self.gpg or not self.gpgv:
            raise ValueError('offline metadata verification requires gpg and gpgv')
        self.home = workspace / 'gnupg'
        self.home.mkdir(mode=0o700)
        self.environment = {'PATH': os.defpath, 'HOME': str(self.home), 'GNUPGHOME': str(self.home),
                            'LC_ALL': 'C', 'TMPDIR': str(workspace)}

    def key(self, url):
        if url in self.keys:
            return self.keys[url]
        metadata_url(url)
        parent, _, leaf = url.rpartition('/')
        raw = MetadataReader(parent, self.directory, self.budget, self.cache).read(leaf, 1024 * 1024)
        if b'PRIVATE KEY' in raw:
            raise ValueError('repository key input contains private key material')
        path = self.workspace / ('key-' + installer_build.sha(url.encode()) + '.gpg')
        if raw.lstrip().startswith(b'-----BEGIN PGP PUBLIC KEY BLOCK-----'):
            result = subprocess.run([self.gpg, '--no-options', '--batch', '--no-tty', '--no-autostart',
                '--homedir', str(self.home), '--dearmor'], input=raw, capture_output=True,
                env=self.environment, close_fds=True, timeout=self.budget.remaining(), check=False)
            if result.returncode or not result.stdout or len(result.stdout) > 1024 * 1024:
                raise ValueError('cannot decode the declared repository public key')
            raw = result.stdout
        path.write_bytes(raw)
        path.chmod(0o600)
        inspected = subprocess.run([self.gpg, '--no-options', '--batch', '--no-tty', '--no-autostart',
            '--homedir', str(self.home), '--with-colons', '--show-keys', str(path)],
            capture_output=True, env=self.environment, close_fds=True,
            timeout=self.budget.remaining(), check=False)
        if (inspected.returncode or not any(line.startswith(b'pub:') for line in inspected.stdout.splitlines())
                or any(line.startswith((b'sec:', b'ssb:')) for line in inspected.stdout.splitlines())):
            raise ValueError('declared signing key is not a valid public OpenPGP keyring')
        self.keys[url] = path
        self.evidence['metadata/keys/' + installer_build.sha(url.encode()) + '.gpg'] = raw
        return path

    def verify(self, repo: dict, raw: bytes, signature: bytes | None):
        if not repo['key_urls']:
            raise ValueError('APT declaration has no downloadable scoped signing key')
        keyrings = [self.key(url) for url in repo['key_urls']]
        path = self.workspace / ('release-' + repo['id'])
        path.write_bytes(raw)
        arguments = [self.gpgv, '--homedir', str(self.home), '--status-fd', '1']
        for keyring in keyrings:
            arguments += ['--keyring', str(keyring)]
        if signature is not None:
            sig = path.with_suffix('.sig')
            sig.write_bytes(signature)
            arguments += [str(sig), str(path)]
        else:
            arguments += [str(path)]
        result = subprocess.run(arguments, capture_output=True, env=self.environment,
                                close_fds=True, timeout=self.budget.remaining(), check=False)
        valid = [line.split() for line in result.stdout.splitlines() if line.startswith(b'[GNUPG:] VALIDSIG ')]
        fingerprints = [line[2] for line in valid if len(line) >= 11 and line[9] in {b'8', b'9', b'10', b'11'}]
        unknown = set(re.findall(rb'^\[GNUPG:\] NO_PUBKEY ([A-F0-9]+)', result.stdout, re.M))
        errors = [line.split() for line in result.stdout.splitlines() if line.startswith(b'[GNUPG:] ERRSIG ')]
        invalid = re.search(rb'^\[GNUPG:\] (?:BADSIG|EXPSIG|EXPKEYSIG|REVKEYSIG|KEYEXPIRED|SIGEXPIRED|FAILURE|NODATA)\b', result.stdout, re.M)
        # A multi-signature Debian release may also carry signatures from keys
        # outside this declaration. They confer no trust, but do not invalidate
        # a strong, valid signature under an explicitly scoped trusted key.
        if (result.returncode not in {0, 2} or not fingerprints or invalid
                or any(len(line) < 8 or line[2] not in unknown or line[7] != b'9' for line in errors)):
            raise ValueError('release signature is not valid under the declaration signing key')
        return {'verified': True, 'signer_fingerprints': sorted({v.decode() for v in fingerprints}),
                'untrusted_signers_without_keys': sorted(v.decode() for v in unknown), 'key_urls': repo['key_urls'],
                'key_records': [{'url': url, 'member': 'metadata/keys/' + installer_build.sha(url.encode()) + '.gpg',
                                 'sha256': installer_build.sha(self.keys[url].read_bytes())} for url in repo['key_urls']]}


BINARY_FIELDS = {'package', 'version', 'architecture', 'filename', 'size', 'sha256', 'source', 'depends',
    'pre-depends', 'recommends', 'suggests', 'provides', 'conflicts', 'breaks', 'replaces', 'enhances',
    'multi-arch', 'priority', 'essential', 'protected', 'built-using', 'static-built-using', 'package-type'}
SOURCE_FIELDS = {'package', 'version', 'directory', 'checksums-sha256', 'architecture', 'binary',
    'build-depends', 'build-depends-indep', 'build-depends-arch', 'build-conflicts', 'format', 'homepage',
    'vcs-git', 'vcs-browser'}


class PackageDatabase:
    """Disk-backed public metadata; no host APT database or package manager is used."""
    def __init__(self, path: Path):
        self.path = path
        self.connection = sqlite3.connect(path)
        self.connection.executescript(f'''
            PRAGMA page_size=4096; PRAGMA max_page_count={DATABASE_BYTE_LIMIT // 4096};
            PRAGMA cache_size=-16384; PRAGMA journal_mode=DELETE; PRAGMA synchronous=OFF; PRAGMA temp_store=MEMORY;
            CREATE TABLE binary(id TEXT PRIMARY KEY,repo TEXT,name TEXT,version TEXT,arch TEXT,kind TEXT,data BLOB) WITHOUT ROWID;
            CREATE TABLE provider(name TEXT,id TEXT,version TEXT,PRIMARY KEY(name,id)) WITHOUT ROWID;
            CREATE TABLE source(id TEXT PRIMARY KEY,repo TEXT,name TEXT,version TEXT,data BLOB) WITHOUT ROWID;
        ''')
        self.rows = 0

    def close(self):
        self.connection.close()

    def binary(self, record: dict, repo: dict, component: str, index: str, kind: str):
        if record.get('architecture') not in {*repo.get('index_architectures', repo['architectures']), 'all'}:
            return
        filename = record['filename'].removeprefix('./')
        if not filename.endswith('.' + kind) or repo['official'] and not filename.startswith('pool/'):
            raise ValueError('binary filename disagrees with its index type')
        url = pool_url(repo['url'], filename)
        if re.fullmatch(r'[a-f0-9]{64}', record.get('sha256', '')) is None or not record.get('size', '').isdigit() or int(record['size']) <= 0:
            raise ValueError('binary package lacks a valid SHA256 and size')
        name, version = record['package'], record['version']
        if (re.fullmatch('[a-z0-9][a-z0-9+.-]*', name) is None or len(version) > 512
                or re.fullmatch('[A-Za-z0-9.+:~_-]+', version) is None):
            raise ValueError('invalid package name or version')
        identifier = installer_build.sha(('\n'.join((repo['id'], name, version, record['architecture'], kind, url))).encode())
        source = re.fullmatch(r'([a-z0-9][a-z0-9+.-]*)(?:\s+\(([^()\s]+)\))?', record.get('source', name))
        if not source:
            raise ValueError('malformed binary Source field')
        value = {'id': identifier, 'repository': repo['id'], 'archive': repo['archive'], 'component': component,
            'index': index, 'name': name, 'version': version, 'architecture': record['architecture'], 'type': kind,
            'filename': filename, 'url': url, 'sha256': record['sha256'], 'size': int(record['size']),
            'source_name': source[1], 'source_version': source[2] or version,
            'fields': {key: record[key] for key in sorted(BINARY_FIELDS - {'filename', 'size', 'sha256'}) if key in record}}
        inserted = self.connection.execute('INSERT OR IGNORE INTO binary VALUES(?,?,?,?,?,?,?)',
            (identifier, repo['id'], name, version, record['architecture'], kind,
             zlib.compress(json.dumps(value, separators=(',', ':')).encode()))).rowcount
        if inserted:
            for group in relations(record.get('provides', '')):
                for provided, qualifier, operator, provided_version, restriction, profile in group:
                    if qualifier or restriction or profile or operator not in {'', '='}:
                        raise ValueError('unsupported virtual Provides expression')
                    self.connection.execute('INSERT OR IGNORE INTO provider VALUES(?,?,?)',
                        (provided, identifier, provided_version or None))
            self.rows += 1
            if self.rows > 1000000:
                raise ValueError('repository metadata row limit exceeded')

    def source(self, record: dict, repo: dict, component: str, index: str):
        if (re.fullmatch('[a-z0-9][a-z0-9+.-]*', record['package']) is None
                or len(record['version']) > 512
                or re.fullmatch('[A-Za-z0-9.+:~_-]+', record['version']) is None):
            raise ValueError('invalid source package name or version')
        directory = record['directory'].removeprefix('./').rstrip('/')
        if directory == '.': directory = ''
        files = []
        for line in record.get('checksums-sha256', '').splitlines():
            if not line.strip(): continue
            fields = line.split()
            if (len(fields) != 3 or re.fullmatch('[a-f0-9]{64}', fields[0]) is None
                    or not fields[1].isdigit() or int(fields[1]) <= 0 or '/' in fields[2]):
                raise ValueError('invalid source Checksums-Sha256 entry')
            leaf = (directory + '/' if directory else '') + fields[2]
            files.append({'filename': leaf, 'url': pool_url(repo['url'], leaf), 'size': int(fields[1]), 'sha256': fields[0]})
        if not files or not any(row['filename'].endswith('.dsc') for row in files):
            raise ValueError('source package lacks SHA256 files or its .dsc')
        identifier = installer_build.sha(('\n'.join((repo['id'], record['package'], record['version']))).encode())
        value = {'id': identifier, 'repository': repo['id'], 'archive': repo['archive'], 'component': component,
            'index': index, 'name': record['package'], 'version': record['version'], 'files': files,
            'fields': {key: record[key] for key in sorted(SOURCE_FIELDS - {'checksums-sha256', 'directory'}) if key in record}}
        self.connection.execute('INSERT OR IGNORE INTO source VALUES(?,?,?,?,?)',
            (identifier, repo['id'], record['package'], record['version'],
             zlib.compress(json.dumps(value, separators=(',', ':')).encode())))

    def ready(self):
        self.connection.executescript('''CREATE INDEX binary_name ON binary(name,arch,kind);
            CREATE INDEX source_name ON source(name,version); CREATE INDEX binary_repo ON binary(repo,kind);''')
        self.connection.commit()


def load_repository(repo: dict, database: PackageDatabase, verifier: ReleaseVerifier,
                    directory: Path | None, budget: AcquisitionBudget, cache: Path | None):
    """Release/index hashes are checked before any package or source row is ingested."""
    reader = MetadataReader(repo['url'], directory, budget, cache)
    flat = repo['archive'] in {'/', './'} or repo['archive'].endswith('/')
    prefix = '' if flat else 'dists/' + repo['archive'] + '/'
    raw = reader.optional(prefix + 'InRelease', 4 * 1024 * 1024)
    signature = None
    release_leaf = prefix + 'InRelease'
    if raw is None:
        release_leaf = prefix + 'Release'
        raw = reader.read(release_leaf, 4 * 1024 * 1024)
        signature = reader.optional(prefix + 'Release.gpg', 1024 * 1024)
        if signature is None:
            raise ValueError('repository has no signed Release or InRelease')
    fields, hashes = release_metadata(raw, repo['official'])
    trust = verifier.verify(repo, raw, signature)
    codename = 'rc-buggy' if repo['archive'] == 'experimental' else repo['archive']
    if repo['official'] and fields.get('Codename') != codename:
        raise ValueError('signed Debian Release codename disagrees with the requested archive')
    for field in ('Date', 'Valid-Until'):
        if field in fields:
            stamp = parsedate_to_datetime(fields[field])
            if stamp.tzinfo is None:
                # OBS publishes an asctime Date without an offset. APT Release
                # timestamps use UTC; official Debian timestamps remain strict.
                if repo['official'] or field != 'Date':
                    raise ValueError('Release timestamp has no timezone')
                stamp = stamp.replace(tzinfo=timezone.utc)
            delta = stamp.timestamp() - time.time()
            if field == 'Date' and delta > 86400 or field == 'Valid-Until' and delta < 0:
                raise ValueError('Release metadata is expired or has a future publication date')
    repo['release'] = {'url': reader.mirror + '/' + release_leaf, 'sha256': installer_build.sha(raw),
        'date': fields.get('Date'), 'valid_until': fields.get('Valid-Until'), 'origin': fields.get('Origin'),
        'suite': fields.get('Suite'), 'codename': fields.get('Codename'), 'label': fields.get('Label'),
        'version': fields.get('Version'), 'not_automatic': fields.get('NotAutomatic'),
        'but_automatic_upgrades': fields.get('ButAutomaticUpgrades'), 'signature': trust}
    evidence = {'metadata/repositories/' + repo['id'] + '/release': raw}
    if signature is not None:
        evidence['metadata/repositories/' + repo['id'] + '/release.gpg'] = signature
    available_arches = fields.get('Architectures', ' '.join(repo['architectures'])).split()
    repo['architectures'] = [arch for arch in repo['architectures'] if arch in available_arches]
    # Explicit :i386 dependencies occur in the configured amd64 software set.
    # Some vendors also publish Architecture: all only in binary-all indexes.
    repo['index_architectures'] = sorted(set(repo['architectures']) | (set(available_arches) & {'i386', 'all'}))
    tasks = []
    repo['source_indexes'] = []
    for component in repo['components'] if not flat else ['']:
        for architecture in repo['index_architectures']:
            for kind, base in [('deb', f'{component}/binary-{architecture}/Packages'),
                               ('udeb', f'{component}/debian-installer/binary-{architecture}/Packages')]:
                if kind == 'udeb' and architecture not in repo['architectures']:
                    continue
                if flat:
                    if kind == 'udeb': continue
                    base = 'Packages'
                options = [base + suffix for suffix in ('.xz', '.gz', '') if base + suffix in hashes]
                if directory is not None:
                    available = [leaf for leaf in options if reader.available(prefix + leaf)]
                    if options and not available:
                        raise ValueError('metadata snapshot is missing an advertised binary index')
                    options = available
                if options and not any(task[0] == options[0] for task in tasks):
                    tasks.append((options[0], component, architecture, kind, hashes[options[0]]))
        source_base = (component + '/source/Sources') if not flat else 'Sources'
        options = [source_base + suffix for suffix in ('.xz', '.gz', '') if source_base + suffix in hashes]
        if directory is not None:
            available = [leaf for leaf in options if reader.available(prefix + leaf)]
            if options and not available:
                raise ValueError('metadata snapshot is missing an advertised Sources index')
            options = available
        if options:
            tasks.append((options[0], component, 'source', 'source', hashes[options[0]]))
            repo['source_indexes'].append(options[0])
    if not any(task[3] == 'deb' for task in tasks):
        raise ValueError('repository has no usable binary indexes for configured architectures')
    repo['indexes'] = []

    def fetch(task):
        leaf, _, _, _, expected = task
        maximum = METADATA_LIMIT if leaf.endswith(('.xz', '.gz')) else EXPANDED_INDEX_LIMIT
        if expected[1] > maximum:
            raise ValueError('repository index exceeds its byte limit')
        data = reader.read(prefix + leaf, maximum)
        if (installer_build.sha(data), len(data)) != expected:
            raise ValueError('repository index differs from signed Release SHA256/size')
        return data

    # Bound completed response buffers as well as active network requests.
    with ThreadPoolExecutor(max_workers=4) as pool:
        pending = deque()
        iterator = iter(tasks)
        for _ in range(min(4, len(tasks))):
            task = next(iterator)
            pending.append((task, pool.submit(fetch, task)))
        while pending:
            task, future = pending.popleft()
            data = future.result()
            leaf, component, architecture, kind, expected = task
            index_url = reader.mirror + '/' + prefix + leaf
            repo['indexes'].append({'url': index_url, 'sha256': expected[0], 'size': expected[1],
                                    'architecture': architecture, 'component': component, 'type': kind})
            for record in package_paragraphs(data, leaf, SOURCE_FIELDS if kind == 'source' else BINARY_FIELDS):
                budget.remaining()
                if kind == 'source': database.source(record, repo, component, index_url)
                else: database.binary(record, repo, component, index_url, kind)
            next_task = next(iterator, None)
            if next_task is not None:
                pending.append((next_task, pool.submit(fetch, next_task)))
    repo['status'] = 'available'
    repo['source_status'] = 'available' if repo['source_indexes'] else 'not-published'
    return evidence


class AptPolicy:
    """The install-phase pin set, parsed as data without ambient APT state."""
    def __init__(self, sources, snapshot=None):
        self.records, self.provenance, self.pins, self.variants = {}, [], {}, {}
        self.classes, self.optional_classes = {}, set()
        graph = (snapshot or {}).get('catalog/compiled/class-plan.tsv', b'')
        for line in graph.decode().splitlines():
            cells = line.split('\t')
            if cells[0] == 'class':
                self.classes[cells[1], cells[2]] = {
                    'requires': cells[3].split(',') if cells[3] else [],
                    'conflicts': cells[4].split(',') if cells[4] else [],
                    'architectures': cells[5].split(','), 'family': cells[6]}
        for suite in SUITES:
            schema = re.search(r"source_repo_supported='([^']+)'", sources['scripts/common/source.sh'].decode())
            if schema is None:
                raise ValueError('offline source lacks repository configuration vocabulary')
            selectors = repository_data(sources['repo.env'].decode(), suite, set(schema[1].split()))
            for family in ('desktop', 'server'):
                prefix = selectors['DIR_TARGET_APT_' + family.upper()] + '/preferences.d/'
                files = {}
                for name, data in sorted(sources.items()):
                    if not name.startswith(prefix) or not name.endswith('.pref'):
                        continue
                    leaf = name.removeprefix(prefix)
                    if leaf.startswith('custom/'):
                        continue  # Not parsed or applied during installation.
                    records, block, start = [], [], 0
                    for number, line in enumerate(data.decode().splitlines() + [''], 1):
                        if line.lstrip().startswith('#'): continue
                        if line.strip():
                            if not block: start = number
                            block.append(line)
                        elif block:
                            fields, = package_paragraphs(('\n'.join(block) + '\n').encode(), name)
                            if not {'package', 'pin', 'pin-priority'} <= fields.keys():
                                raise ValueError('incomplete APT preference record: ' + name)
                            priority = int(fields['pin-priority'])
                            if not -32767 <= priority <= 32767 or priority == 0:
                                raise ValueError('unsupported APT preference priority: ' + name)
                            pin = {'source': name, 'line': start, 'package': fields['package'],
                                   'pin': fields['pin'], 'priority': priority}
                            identifier = installer_build.sha(encoded(pin))[:24]
                            self.pins[identifier] = pin
                            records.append(identifier)
                            block = []
                    files[leaf] = (name, records)
                    self.provenance.append({'source': name, 'sha256': installer_build.sha(data)})
                optional = sorted({leaf.removeprefix('optional/').removesuffix('.pref') for leaf in files
                                   if leaf.startswith('optional/') and not leaf.endswith('nvidia-opt-in.pref')})
                if not set(optional) <= {'cuda', 'cuda-legacy', 'nvidia', 'nvidia-legacy'}:
                    raise ValueError('new optional APT policy needs an explicit staging rule')
                self.optional_classes.update('optional/' + value for value in optional)
                # Mirror installer_stage_suite_apt_preferences: immediate files,
                # selected 30-nvidia, then its corresponding optional 31-cuda.
                combinations = [()]
                for value in optional:
                    combinations += [(*values, value) for values in list(combinations)]
                for values in combinations:
                    selected = {'optional/' + value for value in values}
                    if 'nvidia' in values and 'nvidia-legacy' in values: continue
                    if any(set(self.classes.get((suite, ref), {}).get('conflicts', ())) & selected
                           or not set(self.classes.get((suite, ref), {}).get('requires', ())) <= selected
                           for ref in selected): continue
                    variant = '+'.join(sorted(values)) or 'default'
                    staged = {leaf: record for leaf, record in files.items() if '/' not in leaf}
                    nvidia = 'nvidia-legacy' if 'nvidia-legacy' in values else 'nvidia' if 'nvidia' in values else 'nvidia-opt-in'
                    for installed, leaf in [('30-nvidia.pref', 'optional/' + nvidia + '.pref'),
                            *([('31-cuda.pref', 'optional/cuda-legacy.pref')] if 'cuda-legacy' in values else
                              [('31-cuda.pref', 'optional/cuda.pref')] if 'cuda' in values else [])]:
                        if leaf in files: staged[installed] = files[leaf]
                    self.records[suite, family, variant] = [key for leaf in sorted(staged) for key in staged[leaf][1]]
                    self.variants[suite, family, variant] = {
                        'classes': sorted(selected), 'requires_nvidia_hardware': nvidia != 'nvidia-opt-in',
                        'files': [{'installed_name': leaf, 'source': record[0]} for leaf, record in sorted(staged.items())]}
        for name, data in sources.items():
            if name.startswith('frontends/') and name.endswith('.cfg'):
                if re.match(r'frontends/(forky|trixie)/hooks/target/etc/apt/(desktop|server)/(sources.list.d|preferences.d)/custom/', name):
                    continue
                for _, line in cfg_records(data):
                    if re.fullmatch(r'd-i (?:pkgsel|base-installer)/install-recommends boolean true', line):
                        raise ValueError('offline selection must explicitly handle enabled Recommends: ' + name)

    @staticmethod
    def class_ref(source):
        match = re.search(r'/classes/(class-select|class-auto|class-profile)/(.+)\.cfg$', source)
        return ('profile/' if match[1] == 'class-profile' else '') + match[2] if match else ''

    def contexts(self, request, family, architecture):
        if family in {'installer', 'base'} or request['kind'] in {'base-priority', 'base-installer'}:
            return ['default']
        result = []
        for (suite, owner, variant), policy in self.variants.items():
            if suite != request['suite'] or owner != family: continue
            if any(architecture not in self.classes.get((suite, ref), {'architectures': ['amd64']})['architectures']
                   for ref in policy['classes']): continue
            for origin in request.get('origins', []) or [{'source': ''}]:
                ref = self.class_ref(origin.get('source', ''))
                constraints = self.classes.get((suite, ref), {})
                if architecture not in constraints.get('architectures', [architecture]): continue
                if constraints.get('family', 'all') not in {'all', family}: continue
                if ref in self.optional_classes and ref not in policy['classes']: continue
                result.append(variant)
                break
        return result

    def available(self, repo, suite, family, variant):
        if suite not in repo['suites'] or repo.get('status') != 'available': return False
        for declaration in repo.get('declarations', []) or [{'suite': suite, 'source': ''}]:
            if declaration.get('suite') != suite: continue
            source = declaration.get('source', '')
            ref = self.class_ref(source)
            constraints = self.classes.get((suite, ref), {})
            if constraints.get('family', 'all') not in {'all', family}: continue
            if ref in self.optional_classes and ref not in self.variants.get((suite, family, variant), {}).get('classes', []): continue
            if declaration.get('declared_legacy_policy') and 'cuda-legacy' not in variant.split('+'): continue
            return True
        return False

    @staticmethod
    def source_order(repo, suite, family):
        orders = []
        for declaration in repo.get('declarations', []):
            if declaration.get('suite') != suite: continue
            source = declaration.get('source', '')
            if repo['official'] and repo['archive'] == suite: rank = 0
            elif '/fragments/' in source: rank = 1
            elif '/role/' in source: rank = 2
            elif '/optional/' in source: rank = 3
            else: rank = 4
            slot = declaration.get('slot', '')
            number = int(slot.rsplit('local', 1)[1]) if re.fullmatch('apt-setup/local[0-9]+', slot) else 0
            orders.append((rank, source, number, declaration.get('line', 0)))
        return min(orders) if orders else (5, repo['url'], 0, 0)

    @staticmethod
    def pattern(pattern, value):
        if value is None: return False
        return bool(re.search(pattern[1:-1], value)) if pattern.startswith('/') and pattern.endswith('/') else fnmatch.fnmatchcase(value, pattern)

    def applies(self, pin, row, repo, native_architecture):
        matched = False
        for pattern in pin['package'].split():
            source_pattern = pattern.startswith('src:')
            pattern = pattern.removeprefix('src:')
            plain, colon, arch = pattern.rpartition(':')
            if colon:
                pattern = plain
                if arch not in {'any', row['architecture']} and not (arch == 'native' and row['architecture'] in {native_architecture, 'all'}): continue
            elif pin['package'] != '*' and row['architecture'] not in {native_architecture, 'all'}: continue
            if self.pattern(pattern, row['source_name'] if source_pattern else row['name']): matched = True
        if not matched: return False
        kind, _, expression = pin['pin'].partition(' ')
        if kind == 'origin': return self.pattern(expression.strip('"'), urlsplit(repo['url']).hostname or '')
        if kind in {'version', 'source-version'}:
            return self.pattern(expression, row['source_version'] if kind == 'source-version' else row['version'])
        if kind != 'release': raise ValueError('unsupported APT preference type')
        release = repo.get('release', {})
        properties = {'a': release.get('suite', repo['archive']), 'n': release.get('codename', repo['archive']),
                      'o': release.get('origin', 'Debian' if repo['official'] else ''),
                      'l': release.get('label', ''), 'v': release.get('version', ''), 'c': row['component']}
        constraints = [item.strip().split('=', 1) for item in expression.split(',')]
        if not constraints or any(len(item) != 2 or item[0] not in properties for item in constraints):
            raise ValueError('unsupported APT release preference')
        return all(self.pattern(value.strip('"'), properties[key]) for key, value in constraints)

    def decision(self, rows, repos, suite, family, native_architecture, variant='default'):
        if family in {'installer', 'base'}:
            return (900 if any(repo['archive'] == suite for repo in repos) else -1, family + '-suite')
        records = self.records.get((suite, family, variant), [])
        # APT pins versions, not individual download instances. The first
        # matching specific pin wins across all sources of an identical version.
        for identifier in records:
            pin = self.pins[identifier]
            if pin['package'] != '*' and any(self.applies(pin, row, repo, native_architecture) for row, repo in zip(rows, repos)):
                return pin['priority'], identifier
        generic = []
        for row, repo in zip(rows, repos):
            for identifier in records:
                pin = self.pins[identifier]
                if pin['package'] == '*' and self.applies(pin, row, repo, native_architecture):
                    generic.append((pin['priority'], identifier))
                    break  # First matching archive default; max across files.
            else:
                release = repo.get('release', {})
                default = (100 if release.get('but_automatic_upgrades') == 'yes' else
                           1 if release.get('not_automatic') == 'yes' else
                           1 if not release and repo['archive'] == 'experimental' else 500)
                generic.append((default, 'apt-default'))
        return max(generic, key=lambda item: item[0])

    def priority(self, row, repo, suite, family, native_architecture, explicit_archive='', variant='default'):
        return self.decision([row], [repo], suite, family, native_architecture, variant)[0]


class DependencyGraph:
    def __init__(self, database: PackageDatabase, repos: list[dict], architectures: list[str],
                 budget: AcquisitionBudget | None = None, policy: AptPolicy | None = None):
        self.database, self.repos, self.architectures = database, {r['id']: r for r in repos}, architectures
        self.nodes, self.contexts, self.pending, self.sources = {}, set(), deque(), {}
        self.groups, self.source_links, self.policy_contexts, self.decisions = {}, {}, {}, {}
        self.edges = 0
        self.budget = budget or AcquisitionBudget()
        self.policy = policy or AptPolicy({})
        self.selected_contexts = set()

    @lru_cache(maxsize=8192)
    def binary(self, identifier):
        return json.loads(zlib.decompress(self.database.connection.execute(
            'SELECT data FROM binary WHERE id=?', (identifier,)).fetchone()[0]))

    def reference(self, identifier, source=False):
        row = self.sources[identifier] if source else self.binary(identifier)
        return {'catalog': 'official.json' if self.repos[row['repository']]['official'] else 'vendors.json', 'id': identifier}

    def context(self, suite, architecture, native_architecture, family, variant, archive=''):
        name = '/'.join((suite, family, architecture, variant))
        if native_architecture != architecture: name += '/native-' + native_architecture
        if archive: name += '/from-' + archive
        identifier = installer_build.sha(name.encode())[:24]
        self.policy_contexts.setdefault(identifier, {'suite': suite, 'architecture': architecture,
            'native_architecture': native_architecture, 'family': family, 'variant': variant,
            'requested_archive': archive})
        return identifier

    def select(self, identifier, suite, architecture, native_architecture=None, family='desktop',
               variant='default', archive='', mode='policy'):
        native_architecture = native_architecture or architecture
        package_architecture = self.binary(identifier)['architecture']
        if package_architecture != 'all': architecture = package_architecture
        context = (identifier, suite, architecture, native_architecture, family, variant, archive)
        self.selected_contexts.add((identifier, suite, native_architecture, family, variant))
        if context not in self.contexts:
            if len(self.contexts) >= NODE_LIMIT * 16:
                raise ValueError('dependency context count exceeds limit')
            self.contexts.add(context)
            self.pending.append(context)
        if identifier not in self.nodes:
            if len(self.nodes) >= NODE_LIMIT:
                raise ValueError('dependency package count exceeds limit')
            self.nodes[identifier] = {**self.binary(identifier), 'dependency_links': [], 'source_links': [], 'selection_links': []}
        priority, pin = self.verdict(identifier, suite, family, native_architecture, variant)
        decision = {'priority': priority, 'pin': pin, 'mode': mode}
        key = installer_build.sha(encoded(decision))[:24]
        self.decisions.setdefault(key, decision)
        selection = self.nodes[identifier]['selection_links']
        context_id = self.context(suite, architecture, native_architecture, family, variant, archive)
        for link in selection:
            if link['decision'] == key:
                if context_id not in link['contexts']: link['contexts'].append(context_id)
                break
        else:
            selection.append({'decision': key, 'contexts': [context_id]})
        return self.reference(identifier)

    @lru_cache(maxsize=32768)
    def matches(self, name, qualifier, operator, version, restriction, profile, suite, architecture, kind,
                archive='', native_architecture=''):
        restrictions = restriction.split()
        if restrictions:
            positive = [p for p in restrictions if not p.startswith('!')]
            if positive and not any(architecture_matches(p, architecture) for p in positive): return ()
            if any(architecture_matches(p[1:], architecture) for p in restrictions if p.startswith('!')): return ()
        if profile:
            raise ValueError('build-profile expressions cannot appear in binary runtime dependencies')
        identifiers = {}
        for identifier, candidate_version in self.database.connection.execute('SELECT id,version FROM binary WHERE name=? AND kind=?', (name, kind)):
            identifiers[identifier] = candidate_version
        for identifier, provided_version in self.database.connection.execute('SELECT p.id,p.version FROM provider p JOIN binary b ON b.id=p.id WHERE p.name=? AND b.kind=?', (name, kind)):
            if identifier not in identifiers or version_matches(provided_version, operator, version):
                identifiers[identifier] = provided_version
        selected = []
        for identifier, candidate_version in identifiers.items():
            row = self.binary(identifier)
            repo = self.repos[row['repository']]
            if repo.get('status') != 'available' or suite not in repo['suites'] or archive and repo['archive'] != archive:
                continue
            requested_arch = (native_architecture or architecture) if qualifier == 'native' else (
                architecture if qualifier in {'', 'any'} else qualifier)
            if row['architecture'] not in {requested_arch, 'all'}:
                if qualifier != 'any' or row['fields'].get('multi-arch') not in {'allowed', 'foreign'}:
                    continue
            if qualifier == 'any' and row['architecture'] != 'all' and row['fields'].get('multi-arch') not in {'allowed', 'foreign'}:
                continue
            if version_matches(candidate_version, operator, version):
                selected.append(identifier)
        return tuple(sorted(selected))

    @lru_cache(maxsize=65536)
    def verdict(self, identifier, suite, family, native_architecture, variant='default'):
        row = self.binary(identifier)
        instances = [self.binary(key) for key, in self.database.connection.execute(
            'SELECT id FROM binary WHERE name=? AND version=? AND arch=? AND kind=?',
            (row['name'], row['version'], row['architecture'], row['type']))]
        instances = [item for item in instances if self.policy.available(
            self.repos[item['repository']], suite, family, variant)]
        if not instances: return -1, 'repository-inactive'
        return self.policy.decision(instances, [self.repos[item['repository']] for item in instances],
                                    suite, family, native_architecture, variant)

    def priority(self, identifier, suite, family, native_architecture, archive='', variant='default'):
        return self.verdict(identifier, suite, family, native_architecture, variant)[0]

    def choose(self, identifiers, name, suite, family, native_architecture, archive='', variant='default', explicit=False):
        eligible = [key for key in identifiers if self.policy.available(self.repos[self.binary(key)['repository']], suite, family, variant)
                    and (explicit or self.priority(key, suite, family, native_architecture, variant=variant) > 0)]
        if not eligible: return None
        concrete = [key for key in eligible if self.binary(key)['name'] == name]
        if concrete: eligible = concrete

        def compare(left, right):
            a, b = self.binary(left), self.binary(right)
            ap = self.priority(left, suite, family, native_architecture, variant=variant)
            bp = self.priority(right, suite, family, native_architecture, variant=variant)
            if not explicit and ap != bp: return (ap > bp) - (ap < bp)
            if a['name'] == b['name']:
                compared = version_compare(a['version'], b['version'])
                if compared: return compared
            else:
                ae = (left, suite, native_architecture, family, variant) in self.selected_contexts
                be = (right, suite, native_architecture, family, variant) in self.selected_contexts
                if ae != be: return int(ae) - int(be)
                return (b['name'] > a['name']) - (b['name'] < a['name'])
            an = a['architecture'] in {native_architecture, 'all'}
            bn = b['architecture'] in {native_architecture, 'all'}
            if an != bn: return int(an) - int(bn)
            # Pins select a version. Identical instances follow source order,
            # even when that instance's archive has a lower generic priority.
            ao = self.policy.source_order(self.repos[a['repository']], suite, family)
            bo = self.policy.source_order(self.repos[b['repository']], suite, family)
            return (bo > ao) - (bo < ao) or (right > left) - (right < left)
        return max(eligible, key=cmp_to_key(compare))

    def root(self, request: dict):
        plain, slash, archive = request['request'].partition('/')
        plain, equal, version = plain.partition('=')
        name, colon, qualifier = plain.partition(':')
        archive = 'experimental' if archive == 'rc-buggy' else archive
        kind = 'udeb' if request['kind'] in {'anna', 'installer-hook'} else 'deb'
        matches, by_architecture, selections = {}, {}, []
        families = (['installer'] if kind == 'udeb' else ['base'] if request['kind'] in {'base-priority', 'base-installer'}
                    else request.get('families', ['desktop', 'server']))
        applicable = complete = 0
        for architecture in request['architectures']:
            identifiers = self.matches(name, qualifier, '=' if equal else '', version, '', '', request['suite'], architecture, kind, archive)
            selected = {}
            for family in families:
                for variant in self.policy.contexts(request, family, architecture):
                    applicable += 1
                    identifier = self.choose(identifiers, name, request['suite'], family, architecture, archive,
                                             variant, explicit=bool(slash or equal))
                    refs = []
                    if identifier is not None:
                        mode = 'explicit-release' if slash else 'explicit-version' if equal else 'policy'
                        ref = self.select(identifier, request['suite'], architecture, family=family,
                                          variant=variant, archive=archive, mode=mode)
                        matches[identifier] = selected[identifier] = ref
                        refs = [ref]
                        complete += 1
                    context = self.context(request['suite'], architecture, architecture, family, variant, archive)
                    for selection in selections:
                        if selection['packages'] == refs:
                            selection['contexts'].append(context)
                            break
                    else:
                        selections.append({'contexts': [context], 'packages': refs})
            if selected: by_architecture[architecture] = list(selected.values())
        identifier = installer_build.sha(encoded([request['suite'], request['kind'], request['request']]))[:24]
        return {**request, 'id': identifier, 'name': name, 'candidates': list(matches.values()), 'source_candidates': [],
                'candidates_by_architecture': by_architecture, 'selections': selections,
                'status': 'matched' if complete and complete == applicable else 'conditional-policy-coverage'
                          if matches else 'not-published-or-policy-blocked' if applicable else 'no-applicable-installation-context'}

    def link_sources(self, row):
        # Corresponding source records describe the selected installer binaries.
        # Built-Using remains an exact original control field, not a new set of
        # installation/download roots (nor a request to rebuild those binaries).
        references = [(row['source_name'], row['source_version'], 'source')]
        result = []
        for name, version, reason in references:
            matches = list(self.database.connection.execute('SELECT id,repo,data FROM source WHERE name=? AND version=?', (name, version)))
            own = [match for match in matches if match[1] == row['repository']]
            if own:
                matches = own
            elif reason == 'source':
                # Identical name/version at another vendor does not establish
                # the source provenance of this binary. The same archive root
                # may publish that exact source version in another suite.
                origin = self.repos[row['repository']]['url']
                matches = [match for match in matches if self.repos[match[1]]['url'] == origin]
            # A source version has one selected provenance record. Do not copy
            # every identical source occurrence from every configured archive.
            matches.sort(key=lambda match: (match[1] != row['repository'],
                                           not self.repos[match[1]]['official'], match[1]))
            matches = matches[:1]
            candidates = []
            for identifier, repository, data in matches:
                if self.repos[repository].get('status') != 'available': continue
                self.sources[identifier] = json.loads(zlib.decompress(data))
                candidates.append(self.reference(identifier, source=True))
            status = 'matched' if candidates else ('not-published' if self.repos[row['repository']].get('source_status') == 'not-published' else 'exact-source-version-unavailable')
            link = {'name': name, 'version': version, 'reason': reason, 'candidates': candidates, 'status': status}
            identifier = installer_build.sha(encoded(link))
            self.source_links.setdefault(identifier, link)
            result.append(identifier)
        return result

    def expand(self):
        while self.pending:
            self.budget.remaining()
            identifier, suite, architecture, native_architecture, family, variant, archive = self.pending.popleft()
            row = self.nodes[identifier]
            if not row['source_links']:
                row['source_links'] = self.link_sources(row)
            groups = []
            for field in ('depends', 'pre-depends'):
                for alternatives in relations(row['fields'].get(field, '')):
                    options, choices = [], []
                    for name, qualifier, operator, version, restriction, profile in alternatives:
                        restrictions = restriction.split()
                        positive = [p for p in restrictions if not p.startswith('!')]
                        applicable = (not positive or any(architecture_matches(p, architecture) for p in positive)) and not any(
                            architecture_matches(p[1:], architecture) for p in restrictions if p.startswith('!'))
                        matches = self.matches(name, qualifier, operator, version, restriction, profile, suite, architecture,
                                               row['type'], native_architecture=native_architecture)
                        # Retain the exact normal binary record when an udeb
                        # explicitly names a dependency absent from udeb indexes.
                        binary_fallback = row['type'] == 'udeb' and applicable and not matches
                        if binary_fallback:
                            matches = self.matches(name, qualifier, operator, version, restriction, profile, suite,
                                                   architecture, 'deb', native_architecture=native_architecture)
                        choice = self.choose(matches, name, suite, family, native_architecture, variant=variant)
                        release_fallback = False
                        if choice is None and archive:
                            same_release = [key for key in matches if self.repos[self.binary(key)['repository']]['archive'] == archive]
                            choice = self.choose(same_release, name, suite, family, native_architecture,
                                                 archive, variant, explicit=True)
                            release_fallback = choice is not None
                        choices.append(choice)
                        options.append({'name': name, 'architecture_qualifier': qualifier, 'operator': operator,
                            'version': version, 'architecture_restriction': restriction, 'applicable': applicable,
                            'candidates': [], 'selected': False})
                        if binary_fallback and choice is not None:
                            options[-1]['binary_index_fallback'] = True
                        if release_fallback:
                            options[-1]['release_dependency_override'] = archive
                    usable = [i for i, choice in enumerate(choices) if choice is not None]
                    existing = [i for i in usable if (choices[i], suite, native_architecture, family, variant) in self.selected_contexts]
                    if usable:
                        chosen = (existing or usable)[0]
                        options[chosen]['selected'] = True
                        options[chosen]['candidates'] = [self.select(choices[chosen], suite, architecture,
                                                                   native_architecture, family, variant, archive,
                                                                   'release-dependency' if options[chosen].get('release_dependency_override') else 'policy')]
                        self.edges += 1
                        if self.edges > EDGE_LIMIT:
                            raise ValueError('dependency reference count exceeds limit')
                    group = {'field': field, 'alternatives': options,
                             'status': 'matched' if any(option['candidates'] for option in options) else
                                       'not-applicable' if not any(option['applicable'] for option in options) else 'unresolved'}
                    group_id = installer_build.sha(encoded(group))
                    self.groups.setdefault(group_id, group)
                    groups.append(group_id)
            context = self.context(suite, architecture, native_architecture, family, variant, archive)
            for link in row['dependency_links']:
                if link['groups'] == groups:
                    link['contexts'].append(context)
                    break
            else:
                row['dependency_links'].append({'contexts': [context], 'groups': groups})


def package_catalogs(sources, snapshot, directory, workspace, cache=None, refresh=None):
    mirror, architectures, repos, requests, exclusions = repository_inventory(sources, snapshot)
    declared_repositories = encoded(repos)
    budget = AcquisitionBudget()
    verifier = ReleaseVerifier(workspace, directory, budget, cache)
    database = PackageDatabase(workspace / 'packages.sqlite')
    evidence = {}
    try:
        for repo in repos:
            budget.remaining()
            if not repo['url'].startswith('https://') or any(token in repo['url'] for token in ('__', '@@', '${')):
                repo.update(status='local-generated-or-template', source_status='not-applicable')
                continue
            print('offline: metadata ' + repo['url'] + ' ' + repo['archive'], flush=True)
            try:
                database.connection.execute('SAVEPOINT repository')
                evidence.update(load_repository(repo, database, verifier, directory, budget, cache))
                database.connection.execute('RELEASE repository')
            except (OSError, ValueError, KeyError, EOFError, lzma.LZMAError, subprocess.SubprocessError) as error:
                database.connection.execute('ROLLBACK TO repository')
                database.connection.execute('RELEASE repository')
                if repo['official']:
                    raise
                # Keep every declaration visible. An unavailable upstream may
                # not silently become a guessed Debian package URL.
                reason = ('http-' + str(error.code)) if isinstance(error, urllib.error.HTTPError) else type(error).__name__
                repo.update(status='unavailable', source_status='unknown', error=reason,
                            detail=str(error) if isinstance(error, ValueError) else 'metadata acquisition failed')
                print('offline: vendor metadata unavailable repository=' + repo['id'] + ' reason=' + reason, flush=True)
        database.ready()
        if refresh is not None:
            # Metadata acquisition can take minutes. Capture the final source
            # snapshot after indexing, while retaining strict publication-time
            # identity checks. Changed APT declarations require a new pass;
            # changed package requests can use these already verified indexes.
            sources, snapshot = refresh()
            current_mirror, current_arches, current_repos, requests, exclusions = repository_inventory(sources, snapshot)
            if ((current_mirror, current_arches) != (mirror, architectures)
                    or encoded(current_repos) != declared_repositories):
                raise ValueError('APT declarations changed during metadata acquisition; repeat generation')
        policy = AptPolicy(sources, snapshot)
        graph = DependencyGraph(database, repos, architectures, budget, policy)
        roots = [graph.root(row) for row in sorted(requests, key=lambda r: (r['suite'], r['kind'], r['request']))]
        installer = [row for row in roots if row['kind'] in {'anna', 'installer-hook'}]
        base_specs = {}
        for repo in repos:
            if not repo['official'] or repo.get('status') != 'available' or repo['archive'] not in SUITES:
                continue
            for identifier, data in database.connection.execute('SELECT id,data FROM binary WHERE repo=?', (repo['id'],)):
                row = json.loads(zlib.decompress(data))
                if row['architecture'] not in {*architectures, 'all'}:
                    continue
                fields = row['fields']
                reason = 'base-priority' if row['type'] == 'deb' and (
                    fields.get('priority') in {'required', 'important'} or fields.get('essential') == 'yes'
                    or fields.get('protected') == 'yes' or row['name'] == 'apt') else ''
                if not reason or reason == 'base-priority' and row['name'] in exclusions[repo['archive']]:
                    continue
                arches = architectures if row['architecture'] == 'all' else [row['architecture']]
                spec = base_specs.setdefault((repo['archive'], row['name']), {
                    'suite': repo['archive'], 'kind': reason, 'request': row['name'], 'architectures': set(), 'origins': []})
                spec['architectures'].update(arches)
                spec['origins'].append({'index': row['index'], 'priority': fields.get('priority'),
                                        'essential': fields.get('essential'), 'protected': fields.get('protected')})
        base = [graph.root({**spec, 'architectures': sorted(spec['architectures'])})
                for _, spec in sorted(base_specs.items())]
        graph.expand()
        all_roots = roots + base
        for row in all_roots:
            found = {}
            for candidate in row['candidates']:
                for source_id in graph.nodes[candidate['id']]['source_links']:
                    source = graph.source_links[source_id]
                    if source['reason'] == 'source':
                        for ref in source['candidates']: found[ref['id']] = ref
            row['source_candidates'] = list(found.values())
        def catalog(official):
            result = {'format': 3, 'architectures': architectures,
                'scope': 'only authored installation requests, required base roots and their selected Depends/Pre-Depends closure; Recommends disabled by repository policy',
                'selection_policy': {'preferences': policy.provenance, 'pins': policy.pins,
                                     'staging': [{'suite': suite, 'family': family, 'variant': variant, **value}
                                                 for (suite, family, variant), value in sorted(policy.variants.items())],
                                     'phase': 'apt-setup/pkgsel; Default-Release is staged only at finish-install',
                                     'contexts': graph.policy_contexts, 'decisions': graph.decisions, 'recommends': False,
                                     'build_time_relationships_expanded': False,
                                     'all_repository_versions_exported': False, 'all_published_udebs_exported': False},
                'reference_format': 'catalog plus id identifies an exact entry in packages or source_packages',
                'repositories': [repo for repo in repos if repo['official'] == official],
                'pkgsel': [row['id'] for row in roots if row['kind'] == 'pkgsel'],
                'requests': all_roots if official else [row for row in all_roots if any(ref['catalog'] == 'vendors.json' for ref in row['candidates']) or row['status'] != 'matched'],
                'packages': sorted([row for row in graph.nodes.values() if graph.repos[row['repository']]['official'] == official], key=lambda r: r['id']),
                'source_packages': sorted([row for row in graph.sources.values() if graph.repos[row['repository']]['official'] == official], key=lambda r: r['id'])}
            group_ids = {key for row in result['packages'] for link in row['dependency_links'] for key in link['groups']}
            source_ids = {key for row in result['packages'] for key in row['source_links']}
            result['dependency_groups'] = {key: graph.groups[key] for key in sorted(group_ids)}
            result['source_links'] = {key: graph.source_links[key] for key in sorted(source_ids)}
            result['unresolved_dependencies'] = [{'package': row['id'], 'contexts': link['contexts'],
                'field': graph.groups[key]['field'], 'dependency_group': key}
                for row in result['packages'] for link in row['dependency_links']
                for key in link['groups'] if graph.groups[key]['status'] == 'unresolved']
            result['complete'] = not result['unresolved_dependencies'] and all(repo.get('status') in {'available', 'local-generated-or-template'} for repo in result['repositories'])
            result['unavailable_sources'] = [{'package': row['id'], 'source_link': key} for row in result['packages']
                                             for key in row['source_links'] if graph.source_links[key]['status'] != 'matched']
            return result
        official, vendors = catalog(True), catalog(False)
        official.update(mirror=mirror, installer_requests=[row['id'] for row in installer],
                        base_requests=[row['id'] for row in base],
                        base_selection={'priorities': ['required', 'important'], 'essential': True, 'protected': True,
                                        'exclusions': {suite: sorted(values) for suite, values in exclusions.items()}})
        vendors['apt_declarations'] = [declaration for repo in repos if not repo['official'] for declaration in repo['declarations']]
        evidence.update(verifier.evidence)
        return official, vendors, evidence
    finally:
        if 'graph' in locals():
            graph.binary.cache_clear()
            graph.matches.cache_clear()
            graph.verdict.cache_clear()
        database.close()


def url_category(value: str) -> str:
    if value.startswith(('git@', 'git://')):
        return 'git'
    parsed = urlsplit(value)
    if parsed.scheme == 'ssh' and parsed.username == 'git' and not parsed.password:
        return 'git'
    if parsed.username or parsed.password or re.search(
            r'(?i)(?:^|&)(?:token|access_token|auth|password|api_key|x-amz-signature)=', parsed.query):
        raise ValueError('credential-bearing URL cannot enter an offline catalog')
    if parsed.hostname in GIT_HOSTS or value.endswith('.git'):
        return 'git'
    if parsed.hostname in DEBIAN_HOSTS:
        return 'official'
    return 'http'


def acquisition_inventory(snapshot: dict[str, bytes], external: list[dict], official: dict
                          ) -> tuple[dict, dict]:
    records = {'git': {}, 'http': {}, 'official': {}}

    def add(url: str, origin: dict, variable: str = '', related: dict | None = None):
        url = url.rstrip('),;')
        if not url or len(url) > 8192:
            return
        valid_url = True
        try:
            urlsplit(url) if not url.startswith('git@') else None
        except ValueError:
            if variable:
                raise
            # Source also contains URL validation regular expressions. Retain
            # those as unexpanded references rather than treating them as URLs.
            valid_url, category = False, 'http'
        else:
            category = url_category(url)
        key = (url, variable)
        item = records[category].setdefault(key, {'url': url, 'variable': variable,
                    'kind': 'configured-url' if variable else 'source-url-reference',
                    'resolved': valid_url and not any(token in url for token in ('$', '{', '}')),
                    'origins': [], 'parameters': related or {}})
        if category == 'git' and 'repository' not in item:
            parsed = urlsplit(url) if not url.startswith('git@') else None
            parts = parsed.path.strip('/').split('/') if parsed else []
            if url.startswith('git@'):
                item['repository'] = url
                item['authentication'] = 'separately supplied SSH credentials'
            elif parsed and parsed.hostname == 'api.github.com' and len(parts) >= 3 and parts[0] == 'repos':
                item['repository'] = 'https://github.com/' + '/'.join(parts[1:3]) + '.git'
                item['kind'] = 'release-metadata'
            elif parsed and parsed.hostname in GIT_HOSTS and len(parts) >= 2:
                item['repository'] = 'https://github.com/' + '/'.join(parts[:2]) + '.git' if parsed.hostname in {
                    'github.com', 'codeload.github.com', 'raw.githubusercontent.com'} else url
                if parsed.hostname == 'codeload.github.com' and len(parts) >= 4:
                    item['kind'], item['ref'] = 'source-archive', '/'.join(parts[3:])
                elif parsed.hostname == 'raw.githubusercontent.com' and len(parts) >= 3:
                    item['kind'], item['ref'] = 'source-file', parts[2]
                elif len(parts) >= 5 and parts[2:4] == ['releases', 'download']:
                    item['kind'], item['ref'] = 'release-asset', parts[4]
                elif len(parts) >= 4 and parts[2] == 'archive':
                    item['kind'], item['ref'] = 'source-archive', '/'.join(parts[3:])
            refs = {key: value for key, value in (related or {}).items()
                    if key.endswith(('_COMMIT', '_BRANCH', '_VERSION'))}
            if refs:
                item['configured_refs'] = refs
        if origin not in item['origins']:
            item['origins'].append(origin)

    for name, data in sorted(snapshot.items()):
        if (name.startswith('catalog/compiled/') and '/profiles/' in name
                and name.endswith('.env') and not name.endswith('.account.env')):
            values, provenance = {}, {}
            assignment_data(data.decode(), values, provenance, name, literals=True)
            origins = json.loads(snapshot[name.removesuffix('.env') + '.provenance.json'])
            for key, value in values.items():
                if not re.search(r'(?:https?://|git@|git://|ssh://)', value):
                    continue
                prefix = re.sub(r'_(?:REPOSITORY_)?URL(?:_(?:AMD64|ARM64))?$', '', key)
                related = {k: values[k] for k in sorted(values) if k.startswith(prefix + '_')
                           and re.search(r'_(?:VERSION|COMMIT|BRANCH|SHA256|ARCHITECTURE)$', k)}
                add(value, {'profile': name, 'source': origins.get(key, provenance.get(key))}, key, related)
        if name.startswith('catalog/compiled/'):
            continue
        if not name.endswith(('.env', '.sh', '.tmpl', '.py', '.pm', '.pl', '.json', '.toml', '.conf', '.cfg', '.yml', '.yaml')) and not data.startswith(b'#!'):
            continue
        try:
            text = data.decode('utf-8')
        except UnicodeError:
            continue
        for line_number, line in enumerate(text.splitlines(), 1):
            if line.lstrip().startswith('#'):
                continue
            for match in URL_PATTERN.finditer(line):
                # Keep unresolved runtime URL expressions explicitly as templates;
                # only compiled profile data is reported as expanded configuration.
                add(match[0], {'source': name, 'line': line_number})
    git = {'format': 2, 'scope': 'Git sources, Git-hosted archives/assets and source references',
           'entries': sorted(records['git'].values(), key=lambda row: (row['url'], row['variable']))}
    http = {'format': 2, 'scope': 'external non-Debian, non-Git acquisitions and repository declarations',
            'entries': sorted(records['http'].values(), key=lambda row: (row['url'], row['variable'])),
            'apt_catalog': 'vendors.json',
            'unmatched_pkgsel': [row['id'] for row in official['requests'] if row['kind'] == 'pkgsel' and not row['candidates']]}
    official['configured_official_urls'] = sorted(records['official'].values(), key=lambda row: (row['url'], row['variable']))
    return git, http


def local_bootstrap(source: bytes) -> bytes:
    """Adapt only the bundled copy's acquisition step to an authenticated flat tree."""
    text = source.decode()
    start = text.index('  source_transfer "$base" payload.manifest "$work/payload.manifest" || exit 1\n',
                       text.index('source_prepare_payload() ('))
    last = '  tar -xzf "$work/payload.tar.gz" -C "$work/tree" || { source_error \'cannot extract payload archive\'; exit 1; }\n'
    end = text.index(last, start) + len(last)
    replacement = r'''  case "$base" in /*) ;; *) source_error 'offline bundle requires a local file source'; exit 1 ;; esac
  candidate=${base%/}/payload.manifest
  [ -f "$candidate" ] && [ ! -L "$candidate" ] || { source_error 'missing or non-regular offline manifest'; exit 1; }
  candidate=$(readlink -f "$candidate") || exit 1
  source_root=$(readlink -f "$base") || exit 1
  case "$candidate" in "${source_root%/}/"*) ;; *) source_error 'offline manifest escapes source root'; exit 1 ;; esac
  head -c 4194305 "$candidate" >"$work/payload.manifest" || exit 1
  manifest_size=$(wc -c <"$work/payload.manifest") || exit 1
  [ "$manifest_size" -le 4194304 ] || { source_error 'offline manifest exceeds byte limit'; exit 1; }
  source_verify_sha256 "$work/payload.manifest" "$expected_manifest" 'offline manifest' || exit 1
  actual=$({ printf 'offline-tree-v1\n'; cat "$work/payload.manifest"; } | source_sha256) || exit 1
  [ "${actual%% *}" = "$expected_archive" ] || { source_error 'offline tree identity differs from preseed pin'; exit 1; }
  # The sibling Debian directory is the fixed flat offline archive layout.
  tree=${base%/*}/debian
  [ -d "$tree" ] && [ ! -L "$tree" ] || { source_error 'missing flat offline source tree'; exit 1; }
  tree=$(readlink -f "$tree") || exit 1
  awk -F '\t' 'NR==1 {if($0!="format=3") exit 1; next} NF!=3 || $1 !~ /^[0-9]+$/ || $1>16777216 || length($2)!=64 || $2 ~ /[^a-f0-9]/ {exit 1} {count++;total+=$1;if(count>10000 || total>268435456)exit 1; print $3}' "$work/payload.manifest" >"$work/expected" || { source_error 'malformed or excessive offline manifest'; exit 1; }
  sort "$work/expected" >"$work/expected.sorted" || exit 1
  sort -u "$work/expected" >"$work/expected.unique" || exit 1
  cmp -s "$work/expected.sorted" "$work/expected.unique" || { source_error 'duplicate offline manifest member'; exit 1; }
  mkdir "$work/tree" || exit 1
  while IFS="$(printf '\t')" read -r size digest path; do
    [ "$size" != format=3 ] || continue
    source_validate_relative "$path" || exit 1
    candidate=$tree/$path
    [ -f "$candidate" ] && [ ! -L "$candidate" ] || { source_error 'missing or non-regular offline source'; exit 1; }
    candidate=$(readlink -f "$candidate") || exit 1
    case "$candidate" in "$tree"/*) ;; *) source_error 'offline source escapes bundle tree'; exit 1 ;; esac
    destination=$work/tree/$path
    mkdir -p "$(dirname "$destination")" || exit 1
    # A changing input may not exceed its authenticated size plus one byte.
    head -c "$((size + 1))" "$candidate" >"$destination" || exit 1
    actual_size=$(wc -c <"$destination") || exit 1
    [ "$actual_size" -eq "$size" ] || { source_error 'offline source size differs from manifest'; exit 1; }
    # A flat tree has no authenticated archive byte stream. Validate each
    # protected copy against the trusted manifest before marking it ready.
    source_verify_sha256 "$destination" "$digest" 'offline source member' || exit 1
  done <"$work/payload.manifest"
'''
    return (text[:start] + replacement + text[end:]).encode()


class ArchiveBuffer(io.BytesIO):
    def write(self, data: bytes) -> int:
        if self.tell() + len(data) > FILE_LIMIT:
            raise ValueError('offline archive exceeds publication size limit')
        return super().write(data)


def serialize_bundle(files: dict[str, bytes]) -> bytes:
    if len(files) > 10000 or sum(map(len, files.values())) > BUNDLE_BYTE_LIMIT:
        raise ValueError('combined offline bundle exceeds member or expanded-byte limit')
    if any(len(data) > (CATALOG_BYTE_LIMIT if name in {'official.json', 'vendors.json'} else installer_build.SOURCE_FILE_LIMIT) for name, data in files.items()):
        raise ValueError('combined offline member exceeds individual byte limit')
    output = ArchiveBuffer()
    with gzip.GzipFile(fileobj=output, mode='wb', filename='', mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode='w', format=tarfile.USTAR_FORMAT) as archive:
            for name, data in sorted(files.items()):
                safe_relative(name)
                if name.lower().endswith(('payload.tar.gz', '.deb', '.udeb', '.rpm', '.appimage')):
                    raise ValueError('package or nested payload archive cannot enter the offline bundle')
                member = tarfile.TarInfo(name)
                member.size = len(data)
                member.mode = 0o644
                member.uid = member.gid = member.mtime = 0
                member.uname = member.gname = ''
                archive.addfile(member, io.BytesIO(data))
    return output.getvalue()


def work_directory(requested: Path | None) -> Path:
    """Choose ordinary owned disk space; never consult the system temp default."""
    if requested is None:
        schema = re.search(r"source_repo_supported='([^']+)'",
                           (installer_build.SEED / 'scripts/common/source.sh').read_text())
        if schema is None:
            raise ValueError('offline source lacks repository configuration vocabulary')
        values = repository_data((installer_build.SEED / 'repo.env').read_text(),
                                 SUITES[0], set(schema[1].split()))
        relative = values['DIR_OFFLINE_WORK']
        safe_relative(relative)
        requested = ROOT / relative
    path = requested.absolute()
    # These FHS locations are volatile temporary storage, not work/cache roots.
    if '..' in path.parts or any(path.is_relative_to(base) for base in
                               (Path('/tmp'), Path('/var/tmp'), Path('/dev/shm'))):
        raise ValueError('offline work directory must use ordinary disk storage outside temporary roots')
    descriptor = os.open('/', os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        for part in path.parts[1:]:
            try:
                os.mkdir(part, 0o700, dir_fd=descriptor)
            except FileExistsError:
                pass
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                            dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        info = os.fstat(descriptor)
        if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077:
            raise ValueError('offline work directory must be private (0700) and caller owned')
    finally:
        os.close(descriptor)
    free = shutil.disk_usage(path).free
    if free < 1024 * 1024 * 1024:
        raise ValueError(f'offline work directory has insufficient space: {path}; free_bytes={free}; need at least 1 GiB')
    print(f'offline: work directory {path} free_bytes={free} database_limit_bytes={DATABASE_BYTE_LIMIT}', flush=True)
    return path


def generate(directory: Path | None, cache: Path | None = None,
             work: Path | None = None) -> tuple[str, str, dict]:
    workspace = work_directory(work)
    with tempfile.TemporaryDirectory(prefix='generation-', dir=workspace) as temporary, ExitStack() as resources, OfflineCapture(ROOT) as capture:
        if cache is not None:
            if cache.is_relative_to(ROOT):
                raise ValueError('metadata cache must be outside the checkout')
            with installer_build.SourceCapture(cache.parent) as parent:
                try:
                    os.mkdir(cache.name, 0o700, dir_fd=parent.descriptor)
                except FileExistsError:
                    pass
            resources.enter_context(BuildOwnership(cache))
            if stat.S_IMODE(cache.stat().st_mode) != 0o700 or cache.stat().st_uid != os.getuid():
                raise ValueError('metadata cache must be a private directory owned by the caller')
        sources, compiler = capture.read()
        release, fingerprint, snapshot, frontends, matrix = compile_snapshot(sources, compiler)

        def refresh_capture():
            nonlocal sources, release, fingerprint, snapshot, frontends, matrix
            latest_sources, latest_compiler = capture.read()
            if latest_compiler != compiler:
                raise ValueError('offline compiler changed during metadata acquisition; repeat generation')
            sources = latest_sources
            release, fingerprint, snapshot, frontends, matrix = compile_snapshot(sources, compiler)
            return sources, snapshot

        official, vendors, evidence = package_catalogs(sources, snapshot, directory, Path(temporary), cache,
                                                      refresh_capture)
        git, http = acquisition_inventory(snapshot, vendors['apt_declarations'], official)
        files = {'d-i/debian/' + name: data for name, data in snapshot.items()}
        files.update({'d-i/' + name: data for name, data in frontends.items()})
        files.update(evidence)
        files.update({'official.json': encoded_catalog(official), 'vendors.json': encoded_catalog(vendors),
                      'git.json': encoded(git), 'http.json': encoded(http)})
        manifest = ('format=3\n' + ''.join(
            f'{len(data)}\t{installer_build.sha(data)}\t{name}\n'
            for name, data in sorted(snapshot.items()))).encode()
        tree_identity = installer_build.sha(b'offline-tree-v1\n' + manifest)
        source = local_bootstrap(snapshot['scripts/common/source.sh'])
        for suite in SUITES:
            prefix = f'd-i/{suite}/'
            products = {'source.sh': source, 'sources.sh': source, 'payload.manifest': manifest,
                        'support-matrix.json': encoded(matrix)}
            products['preseed.cfg'] = installer_build.generate_preseed(
                tree_identity, installer_build.sha(manifest),
                suite, release, source.decode(), snapshot[f'frontends/{suite}/common.cfg'].decode())
            products['receipt.json'] = encoded({'format': 2, 'transport': 'local-flat-tree',
                'release': release, 'source_fingerprint': fingerprint, 'tree_identity': tree_identity,
                'products': {name: installer_build.sha(data) for name, data in sorted(products.items())},
                'members': len(snapshot), 'packages_included': False})
            files.update({prefix + name: data for name, data in products.items()})
        summary = {'format': 3, 'release': release, 'source_fingerprint': fingerprint,
                   'compiler_inputs': {name: installer_build.sha(data) for name, data in sorted(compiler.items())},
                   'transport': 'local-flat-tree', 'packages_included': False,
                   'frontends': {suite: f'd-i/{suite}/preseed.cfg' for suite in SUITES},
                   'catalogs': ['official.json', 'vendors.json', 'git.json', 'http.json'],
                   'pkgsel_requests': len(official['pkgsel']), 'official_deb_candidates': len(official['packages']),
                   'vendor_deb_candidates': len(vendors['packages']),
                   'official_source_records': len(official['source_packages']), 'vendor_source_records': len(vendors['source_packages']),
                   'installer_requests': len(official['installer_requests']), 'base_requests': len(official['base_requests']),
                   'catalog_complete': official['complete'] and vendors['complete']
                                       and all(row['status'] == 'matched' for row in official['requests']),
                   'exact_sources_complete': not official['unavailable_sources'] and not vendors['unavailable_sources'],
                   'git_entries': len(git['entries']), 'http_entries': len(http['entries']),
                   'runtime_acceptance': 'source bundle and catalogs; full installation requires separately supplied packages and external artifacts'}
        files['bundle.json'] = encoded(summary)
        files['README.txt'] = b'''Combined installer source bundle (format 3)

The flat d-i/debian tree contains the shared installer snapshot and compiled
catalogs. Both d-i/forky and d-i/trixie provide local bootstraps and frontend
products. Select file=${EXTRACTED_ROOT}/d-i/forky/preseed.cfg or Trixie.
The bootstrap authenticates the source tree against the manifest/preseed pins.
No nested payload archive, Debian package, udeb or vendor installer is included.

The JSON catalogs use format 3 for APT metadata. A reference with catalog and
id resolves to the entry with that id in packages or source_packages. Package
records contain exact repository URLs, versions, architectures, SHA256 hashes,
sizes, original relationship fields, dependency_links and source_links.
A source record includes every SHA256-listed source file and exact URL.
Request source_candidates link directly to matching source records. requests
contains each request once; pkgsel, installer_requests and base_requests contain
request IDs resolved through official.json requests.
Within each APT catalog, package dependency_links refer to dependency_groups
by key. Context IDs resolve through selection_policy.contexts; each describes
suite, role family, package/native architecture, optional classes and any
explicit release request. selection_links resolve winning pin/priority records
through selection_policy.decisions and selection_policy.pins (source and line).
selection_policy.staging lists the exact installed filenames and source members.
Package source_links refer to the catalog's source_links table by key. Shared
groups retain full candidate references without repeating large provider or
Built-Using lists for every package and installation context.

official.json includes the codebase's pkgsel, anna, base-installer and literal
installer-helper requests and Essential/Protected/required/important base roots,
respecting base exclusions. It exports one selected version/provider for each
request context and one selected branch for each required dependency group.
Only the selected Depends/Pre-Depends closure is exported. Recommends/Suggests
are retained as metadata but not followed: this checkout disables them.
Authored suite/family APT preferences, explicit suite/version requests and Debian
version ordering choose records. Immediate preference files follow the
captured source membership and installed filename order. NVIDIA opt-out, current
and legacy NVIDIA/CUDA policy sets remain separate. Only contexts compatible
with each request's authored class architecture/family are traversed. Base and
udeb requests use their earlier native-suite phase, before target pins exist.
Explicit package/release requests and their required release dependency fallback
are marked separately from normal pin selection. Identical version instances
use authored source order; selecting a higher-priority version does not turn its
dependencies into requests for the same archive. Other repository versions, unrelated udebs, unused
providers and unselected alternative branches are never exported.
This is a union of the codebase's installation contexts, not a SAT solver or a
claim that mutually exclusive roles/hardware choices form one install transaction.
Separate binary-all indexes and published i386 records satisfy all-architecture
packages and explicit foreign-architecture dependencies. Dependency contexts
retain the package architecture and, when different, native_architecture for
:native references. An udeb dependency found only in a normal binary index is
marked binary_index_fallback; its actual deb record and URL remain explicit.
Build-Depends, Built-Using and Static-Built-Using are retained as original
control fields. They do not seed installation roots or additional source records;
every exported source record corresponds to a selected binary. Sources are not built.

vendors.json covers all other APT declarations. Vendor binaries and sources
retain the actual vendor origin URL; dependencies may link to official.json.
Absent source indexes and unavailable exact source versions are explicit.
Unavailable repositories, missing requests and unresolved dependencies remain
visible; inspect complete and bundle.json catalog_complete before preparing media.
HTTPS transport disables proxies, checks redirects and pins public DNS results.
Release signatures are verified only against each declaration's scoped public
keys. Index sizes/SHA256 are checked against that signed release before parsing.
Signing keys are acquired from authored key URLs; no ambient host keyring is used.

git.json retains configured repositories, Git-hosted assets, refs and provenance.
http.json retains other external software acquisitions, including ChatGPT,
Tuta, Filen, Bitwarden, Postman, Discord, Ledger and the other configured apps.
Runtime templates and discovery/latest endpoints remain labeled references.

Catalogs describe downloads to supply separately. GTK/USB media wiring, package
cache acquisition, enrollment credentials and full installation are separate.
SHA256SUMS covers every other archive member. Normal products are untouched.
'''
        files['SHA256SUMS'] = ''.join(f'{installer_build.sha(data)}  {name}\n'
                                     for name, data in sorted(files.items())).encode()
        archive = serialize_bundle(files)
        capture.verify()
        try:
            os.mkdir(OUTPUT_DIRECTORY.name, 0o755, dir_fd=capture.descriptor)
        except FileExistsError:
            pass
        else:
            os.fsync(capture.descriptor)
        with BuildOwnership(OUTPUT_DIRECTORY) as ownership:
            with os.scandir(ownership.parent.descriptor) as entries:
                if any(entry.name != OUTPUT_NAME for entry in entries):
                    raise ValueError('offline directory may contain only payload.tar.gz')
            capture.verify()
            atomic_write(OUTPUT_DIRECTORY / OUTPUT_NAME, archive, 0o644)
    return release, installer_build.sha(archive), summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--metadata-dir', type=Path,
                        help='read all repository metadata/keys from an explicit local snapshot; no network fallback')
    parser.add_argument('--metadata-cache', type=Path,
                        help='capture downloaded public metadata in a private directory outside the checkout')
    parser.add_argument('--work-dir', type=Path,
                        default=os.environ.get('OFFLINE_WORK_DIR'),
                        help='private ordinary-disk workspace (or OFFLINE_WORK_DIR); defaults to the repository work selector')
    args = parser.parse_args()
    directory = args.metadata_dir.absolute() if args.metadata_dir is not None else None
    cache = args.metadata_cache.absolute() if args.metadata_cache is not None else None
    if directory is not None and cache is not None:
        parser.error('--metadata-dir and --metadata-cache are mutually exclusive')
    try:
        release, digest, summary = generate(directory, cache, args.work_dir)
    except PublicationOutcomeUnknown as error:
        print('offline outcome unknown; retain the artifact and do not retry automatically: ' + str(error), file=sys.stderr)
        return 75
    except (OSError, ValueError, KeyError, EOFError, lzma.LZMAError, sqlite3.Error, subprocess.SubprocessError) as error:
        print('offline generation failed: ' + str(error), file=sys.stderr)
        if isinstance(error, sqlite3.Error) or isinstance(error, OSError) and error.errno in {28, 122}:
            print('offline: workspace storage exhausted or SQLite limit reached; select a larger ordinary disk with OFFLINE_WORK_DIR; '
                  f'database_limit_bytes={DATABASE_BYTE_LIMIT}', file=sys.stderr)
        return 1
    print(f'offline/payload.tar.gz sha256={digest} release={release} '
          f'pkgsel={summary["pkgsel_requests"]} deb_candidates={summary["official_deb_candidates"]} '
          f'vendor_debs={summary["vendor_deb_candidates"]} sources={summary["official_source_records"] + summary["vendor_source_records"]} '
          f'git={summary["git_entries"]} http={summary["http_entries"]} complete={summary["catalog_complete"]}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
