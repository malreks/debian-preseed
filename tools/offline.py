#!/usr/bin/env python3
"""Create one flat installer-source bundle and download catalogs for both suites.

Only offline/payload.tar.gz is published. Package files and nested installer
payload archives are never read or included. Public Debian repository metadata
is read to obtain exact Filename/Version/Architecture/SHA256 records; no host
APT state, package manager, credentials, Git checkout or target helper is used.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import gzip
import io
import json
import lzma
import os
from pathlib import Path
import re
import shlex
import stat
import sys
import tarfile
import time
from urllib.parse import quote, urlsplit
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / 'tools'))
import build as installer_build
from class_compiler import assignment_data
from publication import BuildOwnership, FILE_LIMIT, PublicationOutcomeUnknown, atomic_write

SUITES = ('forky', 'trixie')
# The output and archive layout are the standalone interface requested by the user.
OUTPUT_DIRECTORY = ROOT / 'offline'
OUTPUT_NAME = 'payload.tar.gz'
METADATA_LIMIT = 64 * 1024 * 1024
EXPANDED_INDEX_LIMIT = 256 * 1024 * 1024
GENERATION_SECONDS = 900
URL_PATTERN = re.compile(r'(?:https?://|git://|ssh://|git@)[^\s\x00-\x20\"\'<>`\\]+')
GIT_HOSTS = {'github.com', 'api.github.com', 'codeload.github.com',
             'raw.githubusercontent.com', 'gitlab.com', 'salsa.debian.org', 'codeberg.org'}
DEBIAN_HOSTS = {'mirrors.glesys.net', 'deb.debian.org', 'security.debian.org',
                'snapshot.debian.org', 'ftp.debian.org', 'ftp-master.debian.org'}


def encoded(value: object) -> bytes:
    return (json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + '\n').encode()


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
    selectors = set()
    for name in sorted(compiled):
        token = re.sub(r'[^A-Z0-9]+', '_', name.removeprefix('catalog/compiled/').upper()).strip('_')
        selector = 'FILE_COMPILED_' + token
        if selector in selectors:
            raise ValueError('compiled selector collision')
        selectors.add(selector)
        path = ('${DIR_FRONTENDS}/' + name.removeprefix('frontends/')) if name.startswith('frontends/') else (
            '${DIR_CATALOG_COMPILED}/' + name.removeprefix('catalog/compiled/'))
        snapshot['repo.env'] += f'{selector}="{path}"\n'.encode()
    identities = [f'{installer_build.sha(data)}  source/{name}\n' for name, data in sorted(sources.items())]
    identities += [f'{installer_build.sha(data)}  compiler/{name}\n' for name, data in sorted(compiler.items())]
    fingerprint = installer_build.sha(''.join(sorted(identities)).encode())
    release = installer_build.sha((fingerprint + '\n' + ''.join(
        f'{installer_build.sha(data)}  {name}\n' for name, data in sorted(snapshot.items()))).encode())
    snapshot['catalog/compiled/release.tsv'] = f'format\t1\nrelease\t{release}\nsource\t{fingerprint}\n'.encode()
    return release, fingerprint, snapshot, {**frontends, **roles}, matrix


class MetadataReader:
    """Bounded metadata-only HTTPS, or an explicit read-only metadata fixture."""

    def __init__(self, mirror: str, directory: Path | None):
        self.mirror = mirror.rstrip('/')
        parsed = urlsplit(self.mirror)
        if parsed.scheme != 'https' or parsed.hostname != 'mirrors.glesys.net' or parsed.username or parsed.password:
            raise ValueError('official metadata requires the configured HTTPS GLESYS mirror')
        self.directory = directory
        self.deadline = time.monotonic() + GENERATION_SECONDS
        owner = self

        class Redirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, request, fp, code, msg, headers, newurl):
                parsed = urlsplit(newurl)
                if parsed.scheme != 'https' or parsed.netloc != urlsplit(owner.mirror).netloc:
                    raise ValueError('Debian metadata redirect leaves the configured HTTPS mirror')
                if getattr(request, '_offline_hops', 0) >= 5:
                    raise ValueError('metadata redirect limit exceeded')
                redirected = super().redirect_request(request, fp, code, msg, headers, newurl)
                redirected._offline_hops = getattr(request, '_offline_hops', 0) + 1
                return redirected

        self.opener = urllib.request.build_opener(Redirect(), urllib.request.ProxyHandler({}))

    def local_descriptor(self, relative: str) -> int:
        """Pin only a regular metadata leaf, with no symlink traversal."""
        safe_relative(relative)
        assert self.directory is not None
        candidates = (relative, (
            (urlsplit(self.mirror).netloc + urlsplit(self.mirror).path + '/' + relative)
            .replace('_', '%5f').replace('/', '_')))
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
                    chunks.append(chunk)
                data = b''.join(chunks)
        if len(data) > maximum:
            raise ValueError('Debian metadata exceeds byte limit')
        return data


def release_metadata(data: bytes) -> tuple[dict[str, str], dict[str, tuple[str, int]]]:
    text = data.decode('utf-8')
    if not text.startswith('-----BEGIN PGP SIGNED MESSAGE-----\n'):
        raise ValueError('Debian InRelease is not clearsigned metadata')
    body = text.split('\n\n', 1)[1].split('-----BEGIN PGP SIGNATURE-----', 1)[0]
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
    if fields.get('Origin') not in {'Debian', 'Debian Backports'} or not hashes:
        raise ValueError('metadata is not an official Debian SHA256 release')
    return fields, hashes


def package_paragraphs(data: bytes, filename: str):
    if filename.endswith('.xz'):
        stream = lzma.LZMAFile(io.BytesIO(data))
    elif filename.endswith('.gz'):
        stream = gzip.GzipFile(fileobj=io.BytesIO(data))
    else:
        stream = io.BytesIO(data)
    record, total, record_bytes, last_key = {}, 0, 0, ''
    with stream:
        while True:
            raw = stream.readline(1024 * 1024 + 1)
            if not raw:
                break
            total += len(raw)
            record_bytes += len(raw)
            if len(raw) > 1024 * 1024 or total > EXPANDED_INDEX_LIMIT:
                raise ValueError(f'expanded Debian index limit exceeded: {filename} '
                                 f'bytes={total} line_bytes={len(raw)}')
            line = raw.decode('utf-8').rstrip('\r\n')
            if record_bytes > 4 * 1024 * 1024:
                raise ValueError('Debian package paragraph exceeds byte limit')
            if not line:
                if record:
                    yield record
                record = {}
                record_bytes, last_key = 0, ''
            elif line[0] in ' \t' and last_key:
                record[last_key] += '\n' + line[1:]
            elif line[0] not in ' \t' and ': ' in line:
                key, value = line.split(': ', 1)
                if key in record:
                    raise ValueError('duplicate Debian package field')
                record[key] = value
                last_key = key
        if record:
            yield record


def repository_inventory(sources: dict[str, bytes]) -> tuple[str, dict, list[dict], dict]:
    archives, external, requests = set(SUITES), [], {}
    mirror = ''
    for name, data in sorted(sources.items()):
        if not name.startswith('frontends/') or not name.endswith('.cfg'):
            continue
        suite = name.split('/')[1]
        for line_number, line in enumerate(data.decode().splitlines(), 1):
            match = re.fullmatch(r'd-i apt-setup/[^ ]+/repository string (.+)', line)
            if match:
                fields = shlex.split(match[1])
                url, archive = fields[:2]
                if urlsplit(url).hostname == 'mirrors.glesys.net' and urlsplit(url).path.rstrip('/') == '/debian':
                    if mirror and mirror != url.rstrip('/'):
                        raise ValueError('suite Debian mirror roots disagree')
                    mirror = url.rstrip('/')
                    archives.add(archive)
                else:
                    external.append({'suite': suite, 'url': url, 'archive': archive,
                                     'components': fields[2:], 'source': name, 'line': line_number})
            match = re.fullmatch(r'd-i pkgsel/include string (.+)', line)
            if match:
                for package in match[1].split():
                    key = (suite, package)
                    requests.setdefault(key, []).append({'source': name, 'line': line_number})
    if not mirror:
        raise ValueError('no configured GLESYS Debian mirror')
    architectures = {name.rsplit('/', 1)[1].removesuffix('.cfg') for name in sources
                     if '/classes/class-auto/arch/' in name and name.endswith('.cfg')}
    if not architectures or not architectures <= {'amd64', 'arm64'}:
        raise ValueError('unknown package-index architecture set')
    # Experimental and rc-buggy are archive/codename aliases of one release.
    if 'experimental' in archives:
        archives.discard('rc-buggy')
    return mirror, {'archives': sorted(archives), 'architectures': sorted(architectures)}, external, requests


def official_inventory(sources: dict[str, bytes], reader: MetadataReader, layout: dict,
                       requests: dict) -> tuple[dict, dict[str, bytes]]:
    wanted = {request.split('/', 1)[0].split('=', 1)[0].split(':', 1)[0] for _, request in requests}
    releases, tasks, evidence = [], [], {}
    for archive in layout['archives']:
        relative = f'dists/{archive}/InRelease'
        raw = reader.read(relative, 4 * 1024 * 1024)
        fields, hashes = release_metadata(raw)
        releases.append({'archive': archive, 'origin': fields.get('Origin'),
                         'suite': fields.get('Suite'), 'codename': fields.get('Codename'),
                         'date': fields.get('Date'), 'url': reader.mirror + '/' + relative,
                         'sha256': installer_build.sha(raw),
                         'signature': 'clearsigned InRelease retained; no independent OpenPGP signature verification'})
        evidence['metadata/debian/' + relative] = raw
        for architecture in layout['architectures']:
            if architecture not in fields.get('Architectures', '').split():
                continue
            for component in fields.get('Components', '').split():
                base = f'{component}/binary-{architecture}/Packages'
                options = [base + suffix for suffix in ('.xz', '.gz', '') if base + suffix in hashes]
                if reader.directory is not None:
                    options = [option for option in options if reader.available(f'dists/{archive}/{option}')]
                if not options:
                    raise ValueError(f'no package index for {archive}/{component}/{architecture}')
                leaf = options[0]
                tasks.append((archive, component, architecture, leaf, hashes[leaf]))

    def index(task):
        archive, component, architecture, leaf, expected = task
        maximum = METADATA_LIMIT if leaf.endswith(('.xz', '.gz')) else EXPANDED_INDEX_LIMIT
        if expected[1] > maximum:
            raise ValueError('compressed index exceeds byte limit')
        relative = f'dists/{archive}/{leaf}'
        raw = reader.read(relative, maximum)
        if (installer_build.sha(raw), len(raw)) != expected:
            raise ValueError('Debian package index differs from InRelease SHA256/size')
        selected = []
        for record in package_paragraphs(raw, leaf):
            provided = {entry.strip().split(' ', 1)[0] for entry in record.get('Provides', '').split(',')}
            requested_aliases = sorted(wanted & provided)
            if record.get('Package') not in wanted and not requested_aliases:
                continue
            filename = record.get('Filename', '')
            safe_relative(filename)
            if not filename.startswith('pool/') or not filename.endswith('.deb'):
                raise ValueError('Debian binary record has an invalid pool filename')
            if re.fullmatch(r'[a-f0-9]{64}', record.get('SHA256', '')) is None:
                raise ValueError('Debian package record lacks SHA256')
            selected.append({
                'name': record['Package'], 'version': record['Version'],
                'architecture': record['Architecture'], 'archive': archive,
                'component': component, 'filename': filename,
                'url': reader.mirror + '/' + quote(filename, safe='/+~.-_'),
                'sha256': record['SHA256'], 'size': int(record['Size']),
                'source_package': record.get('Source', record['Package']),
                'depends': record.get('Depends', ''), 'pre_depends': record.get('Pre-Depends', ''),
                'recommends': record.get('Recommends', ''), 'provides': record.get('Provides', ''),
                'provides_requested_names': requested_aliases,
            })
        return {'archive': archive, 'component': component, 'architecture': architecture,
                'url': reader.mirror + '/' + relative, 'sha256': expected[0], 'size': expected[1]}, selected

    indexes, packages = [], []
    with ThreadPoolExecutor(max_workers=4) as pool:
        for metadata, records in pool.map(index, tasks):
            indexes.append(metadata)
            packages.extend(records)
    packages.sort(key=lambda item: (item['name'], item['architecture'], item['archive'], item['version']))
    by_name = {}
    for number, package in enumerate(packages):
        by_name.setdefault(package['name'], []).append(number)
        for alias in package['provides_requested_names']:
            if alias != package['name']:
                by_name.setdefault(alias, []).append(number)
    rows = []
    for (suite, request), origins in sorted(requests.items()):
        plain, _, archive = request.partition('/')
        plain, _, version = plain.partition('=')
        name, _, architecture = plain.partition(':')
        candidates = [i for i in by_name.get(name, []) if (
            not archive or packages[i]['archive'] == archive
            or archive == 'rc-buggy' and packages[i]['archive'] == 'experimental')
            and (not version or packages[i]['version'] == version)
            and (not architecture or architecture in {'any', 'native'}
                 or packages[i]['architecture'] in {architecture, 'all'})]
        rows.append({'suite': suite, 'request': request, 'name': name, 'origins': origins,
                     'official_candidates': candidates,
                     'status': 'official-debian' if candidates else 'not-in-official-indexes',
                     'external_catalog': None if candidates else 'http.json'})
    return {'format': 2, 'mirror': reader.mirror, 'architectures': layout['architectures'],
            'scope': 'all pkgsel requests and exact official Debian pool candidates; not an APT solver or dependency lock',
            'releases': releases, 'indexes': indexes, 'pkgsel': rows, 'packages': packages}, evidence


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
            'apt_repositories': external,
            'pkgsel_not_in_official_indexes': [row for row in official['pkgsel'] if not row['official_candidates']]}
    official['configured_official_urls'] = sorted(records['official'].values(), key=lambda row: (row['url'], row['variable']))
    return git, http


def local_bootstrap(source: bytes) -> bytes:
    """Adapt only the bundled copy's acquisition step to an authenticated flat tree."""
    text = source.decode()
    # Strip the leading slash before wrapping an absolute frontend for the
    # traversal guard; otherwise every file= path appears to contain '//'.
    guard = 'case "/$file/" in */../*|*//*)'
    if text.count(guard) != 1:
        raise ValueError('local frontend traversal guard changed; review the offline adapter')
    text = text.replace(guard, 'case "/${file#/}/" in */../*|*//*)')
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
  actual=$(source_hash <"$work/payload.manifest"); [ "${actual%% *}" = "$expected_manifest" ] || { source_error 'offline manifest differs from preseed pin'; exit 1; }
  actual=$({ printf 'offline-tree-v1\n'; cat "$work/payload.manifest"; } | source_hash) || exit 1
  [ "${actual%% *}" = "$expected_archive" ] || { source_error 'offline tree identity differs from preseed pin'; exit 1; }
  # The sibling Debian directory is the fixed format-2 offline archive layout.
  tree=${base%/*}/debian
  [ -d "$tree" ] && [ ! -L "$tree" ] || { source_error 'missing flat offline source tree'; exit 1; }
  tree=$(readlink -f "$tree") || exit 1
  awk -F '\t' 'NR==1 {if($0!="format=3") exit 1; next} NF!=3 || $1 !~ /^[0-9]+$/ || $1>16777216 || length($2)!=64 || $2 ~ /[^a-f0-9]/ {exit 1} {count++;total+=$1;if(count>10000 || total>268435456)exit 1; print $3}' "$work/payload.manifest" >"$work/expected" || { source_error 'malformed or excessive offline manifest'; exit 1; }
  awk -F '\t' 'NR>1 {print $2 "  " $3}' "$work/payload.manifest" >"$work/checksums" || exit 1
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
  done <"$work/payload.manifest"
'''
    return (text[:start] + replacement + text[end:]).encode()


class ArchiveBuffer(io.BytesIO):
    def write(self, data: bytes) -> int:
        if self.tell() + len(data) > FILE_LIMIT:
            raise ValueError('offline archive exceeds publication size limit')
        return super().write(data)


def serialize_bundle(files: dict[str, bytes]) -> bytes:
    if len(files) > 10000 or sum(map(len, files.values())) > installer_build.SOURCE_BYTE_LIMIT:
        raise ValueError('combined offline bundle exceeds member or expanded-byte limit')
    if any(len(data) > installer_build.SOURCE_FILE_LIMIT for data in files.values()):
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


def generate(directory: Path | None) -> tuple[str, str, dict]:
    with OfflineCapture(ROOT) as capture:
        sources, compiler = capture.read()
        release, fingerprint, snapshot, frontends, matrix = compile_snapshot(sources, compiler)
        mirror, layout, external, requests = repository_inventory(sources)
        print('offline: resolving Debian metadata for ' + ','.join(layout['archives'])
              + ' architectures=' + ','.join(layout['architectures']), flush=True)
        official, evidence = official_inventory(sources, MetadataReader(mirror, directory), layout, requests)
        git, http = acquisition_inventory(snapshot, external, official)
        files = {'d-i/debian/' + name: data for name, data in snapshot.items()}
        files.update({'d-i/' + name: data for name, data in frontends.items()})
        files.update(evidence)
        files.update({'official.json': encoded(official), 'git.json': encoded(git), 'http.json': encoded(http)})
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
                tree_identity, installer_build.sha(manifest), installer_build.sha(source),
                suite, release, source.decode(), snapshot[f'frontends/{suite}/common.cfg'].decode())
            products['receipt.json'] = encoded({'format': 2, 'transport': 'local-flat-tree',
                'release': release, 'source_fingerprint': fingerprint, 'tree_identity': tree_identity,
                'products': {name: installer_build.sha(data) for name, data in sorted(products.items())},
                'members': len(snapshot), 'packages_included': False})
            files.update({prefix + name: data for name, data in products.items()})
        summary = {'format': 2, 'release': release, 'source_fingerprint': fingerprint,
                   'compiler_inputs': {name: installer_build.sha(data) for name, data in sorted(compiler.items())},
                   'transport': 'local-flat-tree', 'packages_included': False,
                   'frontends': {suite: f'd-i/{suite}/preseed.cfg' for suite in SUITES},
                   'catalogs': ['official.json', 'git.json', 'http.json'],
                   'pkgsel_requests': len(official['pkgsel']), 'official_deb_candidates': len(official['packages']),
                   'git_entries': len(git['entries']), 'http_entries': len(http['entries']),
                   'runtime_acceptance': 'source bundle and catalogs; full installation requires separately supplied packages and external artifacts'}
        files['bundle.json'] = encoded(summary)
        files['README.txt'] = b'''Combined installer source bundle (format 2)

This archive is flat: d-i/debian contains the complete shared installer snapshot
and compiled catalogs; d-i/forky and d-i/trixie contain the suite sources and
local bootstraps. There are no nested payload archives and no package files.
Select file=${EXTRACTED_ROOT}/d-i/forky/preseed.cfg or the corresponding Trixie
preseed. The bundled bootstrap verifies and copies the sibling Debian source
tree into its private runtime snapshot using payload.manifest and preseed pins.
Normal network publications and authored installer sources are unchanged.

official.json accounts for every pkgsel request and lists exact Debian package
versions, architectures, GLESYS pool URLs, sizes, hashes and dependency fields.
It lists matching repository candidates, not a solved APT transaction or a
transitive dependency lock. Vendor-only/unavailable requests are cross-listed
in http.json. Signed InRelease files and index SHA256 identities are retained;
this generator does not independently verify OpenPGP release signatures.

git.json inventories Git repositories, Git-hosted archives/assets and source
references, including expanded .env profile URLs and their provenance.
http.json inventories other external acquisition URLs and vendor repositories.
Runtime URL templates and latest/discovery endpoints remain explicitly visible
as source references; private repositories still require separate credentials.

The catalogs describe excluded downloads. Package pools, vendor installers,
Git/source archives, model data and other third-party bytes must be supplied
separately before a complete network-free installation. This is not bootable
media and does not add GTK prompts, cache transport for external installers,
or alter suite/profile support policy. SHA256SUMS covers all other members.
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
                        help='read Debian metadata from an explicit local snapshot; never fall back to network')
    args = parser.parse_args()
    directory = args.metadata_dir.absolute() if args.metadata_dir is not None else None
    try:
        release, digest, summary = generate(directory)
    except PublicationOutcomeUnknown as error:
        print('offline outcome unknown; retain the artifact and do not retry automatically: ' + str(error), file=sys.stderr)
        return 75
    except (OSError, ValueError, KeyError, lzma.LZMAError) as error:
        print('offline generation failed: ' + str(error), file=sys.stderr)
        return 1
    print(f'offline/payload.tar.gz sha256={digest} release={release} '
          f'pkgsel={summary["pkgsel_requests"]} deb_candidates={summary["official_deb_candidates"]} '
          f'git={summary["git_entries"]} http={summary["http_entries"]}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
