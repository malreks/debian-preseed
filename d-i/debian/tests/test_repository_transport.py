#!/usr/bin/env python3
"""Offline transport, source selection, cache and immutable snapshot tests.

HTTP and HTTPS fixtures bind only to loopback. Nothing partitions disks, starts
systemd units, installs packages, or contacts GitHub/TinyURL/the Internet.
"""
from __future__ import annotations

# Refuse host execution before importing runtime helpers or creating fixtures.
from pathlib import Path as _IsolationPath
import sys as _isolation_sys
_isolation_sys.path.insert(0, str(_IsolationPath(__file__).resolve().parents[3] / 'tools'))
# Copied checker/GUI fixtures still use the verified private checkout gate.
_isolation_sys.path.insert(0, '/workspace/repository/tools')
from isolation import require_test_isolation as _require_test_isolation
_isolation_sys.path.pop(0)
_require_test_isolation()

from payload_fixture import installed_argv as payload_installed_argv, source_exists as payload_source_exists, source_is_file as payload_source_is_file
from payload_fixture import read_bytes as payload_read_bytes, read_text as payload_read_text
import collections
import contextlib
import gzip
import hashlib
import http.server
import http.client
import io
import os
from pathlib import Path
import shlex
import shutil
import ssl
import subprocess
import tarfile
import tempfile
import threading
import unittest
from process_fixture import stop_test_tree, wait_file
from test_environment import require_loopback_inet, skip_unless_process_tree_visibility
from urllib.parse import urlsplit, unquote

FORKY = Path(__file__).resolve().parents[1]
SOURCE = FORKY / 'scripts/common/source.sh'
ROOT = FORKY.parents[1]
ROLE = 'server' if 'REPOSITORY_ROLE="server"' in payload_read_text(FORKY / 'repo.env') else 'desktop'
RAW_PREFIX = '/owner/repository/refs/heads/mcr/main/d-i/forky'

def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

class Endpoint:
    def __init__(self, root: Path, tls: ssl.SSLContext | None = None):
        self.root, self.counts = root, collections.Counter()
        self.redirects = {'/short': RAW_PREFIX + '/preseed.cfg?fixture=1',
                          '/chain/start': '../short',
                          '/relative': 'short'}
        endpoint = self
        class Handler(http.server.BaseHTTPRequestHandler):
            def handle(self):
                # Certificate-rejection tests intentionally abort the connection.
                try:
                    super().handle()
                except (BrokenPipeError, ConnectionResetError):
                    pass
            def do_GET(self):
                path = unquote(urlsplit(self.path).path)
                endpoint.counts[path] += 1
                if path in endpoint.redirects:
                    self.send_response(302)
                    self.send_header('Location', endpoint.redirects[path])
                    # HTTP/1.0 closes this connection. Explicit framing prevents
                    # Wget racing the close and reusing it for the redirect,
                    # which correctly triggers a retry but corrupts test counts.
                    self.send_header('Content-Length', '0')
                    self.send_header('Connection', 'close')
                    self.close_connection = True
                    self.end_headers()
                    return
                if not path.startswith(RAW_PREFIX + '/'):
                    self.send_error(404)
                    return
                relative = path[len(RAW_PREFIX) + 1:]
                file = endpoint.root / relative
                if '..' in Path(relative).parts or not payload_source_is_file(file):
                    self.send_error(404)
                    return
                data = payload_read_bytes(file)
                self.send_response(200)
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            def log_message(self, *args):
                pass
        self.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        if tls:
            self.server.socket = tls.wrap_socket(self.server.socket, server_side=True)
        self.url = ('https' if tls else 'http') + f'://127.0.0.1:{self.server.server_port}'
        self.base = self.url + RAW_PREFIX
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={'poll_interval': .03}, daemon=True)
        self.thread.start()
    def close(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)

class TransportFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='preseed-transport-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.runtime = self.root / 'runtime'
        self.env = {**os.environ, 'INSTALLER_RUNTIME_DIR': str(self.runtime),
                    'INSTALLER_CMDLINE': '', 'INSTALLER_FETCH_TIMEOUT': '3'}
        self.env.pop('INSTALLER_SOURCE_ROOT', None)
        # Context preparation now correctly applies selections. Never seed the
        # host database, and never inherit a live installer frontend in tests.
        for key in list(self.env):
            if key.startswith(('DEBCONF_', 'DEBIAN_')):
                self.env.pop(key)
        db = self.root / 'debconf.conf'
        db.write_text('Config: test_config\nTemplates: test_templates\n\n'
                      f'Name: test_config\nDriver: File\nMode: 600\nFilename: {self.root}/config.dat\n\n'
                      f'Name: test_templates\nDriver: File\nMode: 600\nFilename: {self.root}/templates.dat\n')
        self.env.update(DEBCONF_SYSTEMRC=str(db), DEBIAN_FRONTEND='noninteractive')
    def shell(self, script: str, *, env=None, timeout=25):
        return subprocess.run(payload_installed_argv(['/bin/sh', '-eu', '-c', f'. {shlex.quote(str(SOURCE))}\n{script}']),
            text=True, capture_output=True, env={**self.env, **(env or {})}, timeout=timeout)
    def endpoint(self, root=FORKY, tls=None):
        require_loopback_inet()
        endpoint = Endpoint(root, tls)
        self.addCleanup(endpoint.close)
        return endpoint

    def busybox_wget_mock(self, seed):
        """A private HTTP fixture with BusyBox's missing --no-config capability."""
        directory = self.root / 'busybox-http-bin'
        directory.mkdir(mode=0o700)
        scratch = self.root / 'busybox-http-tmp'
        scratch.mkdir(mode=0o700)
        calls = self.root / 'busybox-transfer-calls'
        wget = directory / 'wget'
        wget.write_text('''#!/bin/sh
set -eu
if [ "${1-}" = --help ]; then
  printf '%s\\n' 'BusyBox fixture wget: -S -T SEC -O FILE URL'
  exit 0
fi
printf 'transfer\\n' >>"$FIXTURE_WGET_CALLS"
destination=; url=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -S) shift ;;
    -T) shift 2 ;;
    -O) destination=$2; shift 2 ;;
    http://fixture.invalid/seed/*) url=$1; shift ;;
    *) exit 96 ;;
  esac
done
case "$url" in
  http://fixture.invalid/seed/payload.manifest) leaf=payload.manifest ;;
  http://fixture.invalid/seed/payload.tar.gz) leaf=payload.tar.gz ;;
  *) exit 97 ;;
esac
[ -n "$destination" ] || exit 98
printf '  HTTP/1.1 200 OK\\n' >&2
cat "$FIXTURE_WGET_SEED/$leaf" >"$destination"
''')
        wget.chmod(0o700)
        return {'PATH': str(directory) + ':' + self.env['PATH'],
                'TMPDIR': str(scratch), 'TMP': str(scratch), 'TEMP': str(scratch),
                'FIXTURE_WGET_CALLS': str(calls), 'FIXTURE_WGET_SEED': str(seed)}, calls

class TransportTests(TransportFixture):
    def test_authority_accepts_decimal_ports_without_octal_or_overflow_parsing(self):
        for url in ('http://127.0.0.1:8000/path',
                    'http://127.0.0.1:08000/path',
                    'https://example.test:443/seed'):
            with self.subTest(url=url):
                result = self.shell('source_url_authority ' + shlex.quote(url))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), url.split('://', 1)[1].split(':', 1)[0])

        for url in ('http://127.0.0.1:0/path',
                    'http://127.0.0.1:65536/path',
                    'http://127.0.0.1:123456/path'):
            with self.subTest(url=url):
                result = self.shell('source_url_authority ' + shlex.quote(url))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('invalid port', result.stderr)

    def test_source_cmdline_ignores_generic_credential_keys_without_echoing_values(self):
        for key in ('password', 'service_token', 'private_key', 'wireless_psk', 'api_secret'):
            with self.subTest(key=key):
                result = self.shell('source_cmdline', env={'INSTALLER_CMDLINE': key + '=fixture'})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, '\n')
                self.assertNotIn('fixture', result.stdout + result.stderr)

    def test_redirect_fixture_has_explicit_close_framing(self):
        web = self.endpoint()
        with contextlib.closing(http.client.HTTPConnection('127.0.0.1', web.server.server_port, timeout=3)) as connection:
            connection.request('GET', '/short')
            response = connection.getresponse()
            self.assertEqual(response.status, 302)
            self.assertEqual(response.getheader('Content-Length'), '0')
            self.assertEqual(response.getheader('Connection'), 'close')
            self.assertEqual(response.read(), b'')
        self.assertEqual(dict(web.counts), {'/short': 1})
    def test_raw_style_ref_path_is_not_truncated(self):
        web = self.endpoint()
        result = self.shell('source_resolve_seed', env={'INSTALLER_CMDLINE': f'url={web.base}/preseed.cfg'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), web.base)
    def test_seed_cross_authority_redirect_is_allowed_before_payload_authentication(self):
        shortener, web = self.endpoint(), self.endpoint()
        shortener.redirects['/chain/start'] = web.url + '/short'
        destination = self.root / 'seed.document'
        result = self.shell('source_http_get ' + shlex.quote(shortener.url + '/chain/start') + ' ' +
                            shlex.quote(str(destination)) + " '' seed")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(web.counts['/short'], 1)
        self.assertEqual(destination.read_bytes(), payload_read_bytes(FORKY / 'preseed.cfg'))
    def test_repository_cross_authority_redirect_is_followed_without_authority_gate(self):
        shortener, web = self.endpoint(), self.endpoint()
        shortener.redirects['/chain/start'] = web.url + '/short'
        destination = self.root / 'repository.document'
        result = self.shell('source_http_get ' + shlex.quote(shortener.url + '/chain/start') + ' ' +
                            shlex.quote(str(destination)) + " '' repository")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(web.counts['/short'], 1)
        self.assertEqual(destination.read_bytes(), payload_read_bytes(FORKY / 'preseed.cfg'))
    def test_persisted_effective_url_wins_without_re_download(self):
        web = self.endpoint()
        effective = web.base + '/preseed.cfg?fixture=1#selected'
        web.redirects['/short'] = effective
        env = {'INSTALLER_CMDLINE': f'url={web.url}/short'}
        first = self.shell('source_resolve_seed', env=env)
        destination = self.root / 'repo.env'
        second = self.shell('base=$(source_resolve_seed); printf "%s\\n" "$base"; '
                            'source_transfer "$base" repo.env ' + shlex.quote(str(destination)), env=env)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(second.stdout, first.stdout)
        self.assertEqual(first.stdout.strip(), web.base)
        self.assertEqual(payload_read_text(self.runtime / 'bootstrap/seed.effective-url').strip(), effective)
        self.assertEqual(payload_read_text(self.runtime / 'bootstrap/seed.url').strip(), web.base)
        self.assertEqual(destination.read_bytes(), payload_read_bytes(FORKY / 'repo.env'))
        self.assertEqual(dict(web.counts), {'/short': 1, RAW_PREFIX + '/preseed.cfg': 1,
                                            RAW_PREFIX + '/repo.env': 1})
    def test_file_and_preseed_file_aliases(self):
        for alias in ('file', 'preseed/file'):
            with self.subTest(alias=alias):
                shutil.rmtree(self.runtime, ignore_errors=True)
                result = self.shell('source_resolve_seed', env={'INSTALLER_CMDLINE': f'{alias}={FORKY}/preseed.cfg'})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), str(FORKY))
    def test_file_uri(self):
        result = self.shell('source_resolve_seed', env={'INSTALLER_CMDLINE': f'url=file://{FORKY}/preseed.cfg'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(FORKY))
    def test_real_absolute_local_frontend_is_accepted_without_network(self):
        for suite in ('forky', 'trixie'):
            seed = self.root / 'media/d-i' / suite
            seed.mkdir(parents=True)
            frontend = seed / 'preseed.cfg'
            frontend.write_text('# local frontend fixture; never evaluated\n')
            for index, argument in enumerate((f'file={frontend}', f'preseed/file={frontend}',
                                               f'url=file://{frontend}')):
                with self.subTest(suite=suite, argument=argument):
                    runtime = self.root / f'local-runtime-{suite}-{index}'
                    result = self.shell(
                        'source_http_get() { return 90; }; source_resolve_seed',
                        env={'INSTALLER_SUITE': suite, 'INSTALLER_CMDLINE': argument,
                             'INSTALLER_RUNTIME_DIR': str(runtime)})
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.strip(), str(seed))
                    self.assertEqual((runtime / 'bootstrap/seed.file').read_text(), str(seed) + '\n')
                    self.assertFalse((runtime / 'bootstrap/seed.url').exists())
    def test_local_frontend_traversal_is_still_rejected(self):
        seed = self.root / 'media/d-i/forky'
        seed.mkdir(parents=True)
        (seed / 'preseed.cfg').write_text('# local frontend fixture\n')
        for index, path in enumerate((f'{seed}//preseed.cfg', f'{seed}/../forky/preseed.cfg')):
            with self.subTest(path=path):
                runtime = self.root / f'unsafe-local-runtime-{index}'
                result = self.shell('source_resolve_seed', env={
                    'INSTALLER_SUITE': 'forky', 'INSTALLER_CMDLINE': f'file={path}',
                    'INSTALLER_RUNTIME_DIR': str(runtime)})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('local frontend path contains traversal', result.stderr)
                self.assertFalse((runtime / 'bootstrap/seed.file').exists())
    def test_conflicting_sources_fail_before_network(self):
        web = self.endpoint()
        for cmdline in (f'url={web.url}/short file={FORKY}/preseed.cfg',
                        f'url={web.url}/short preseed/url={web.url}/other'):
            with self.subTest(cmdline=cmdline):
                result = self.shell('source_resolve_seed', env={'INSTALLER_CMDLINE': cmdline})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('fatal:', result.stderr)
        self.assertEqual(sum(web.counts.values()), 0)
    def test_missing_source_and_missing_local_preseed_fail(self):
        for value in ('', 'file=/does/not/exist.cfg'):
            result = self.shell('source_resolve_seed', env={'INSTALLER_CMDLINE': value})
            self.assertNotEqual(result.returncode, 0)
    def test_url_and_relative_path_validation(self):
        for path in ('../secret', 'a/../secret', '/etc/passwd', 'a//b', 'a/./b', '$(id)', 'a b'):
            result = self.shell('source_validate_relative ' + shlex.quote(path))
            self.assertNotEqual(result.returncode, 0, path)
        self.assertNotIn('source_validate_url', payload_read_text(SOURCE))
    def test_one_cache_has_an_explicit_selected_source(self):
        boot = self.runtime / 'bootstrap'
        boot.mkdir(parents=True, exist_ok=True)
        (boot / 'payload.ready').write_text(
            'verified-v1 ' + 'a' * 64 + ' ' + 'b' * 64 + ' http://example.test/a/b\n', encoding='ascii')
        result = self.shell('source_cache_root http://example.test/a/b')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(Path(result.stdout.strip()), self.runtime / 'cache/seed')
        result = self.shell('source_cache_root http://example.test/a_b')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('differs from the selected payload', result.stderr)
    def test_library_adapters_share_one_get_and_accept_empty_profile(self):
        web = self.endpoint()
        p = shlex.quote
        script = f'''
. {p(str(FORKY / 'scripts/common/bootstrap.sh'))}
. {p(str(FORKY / 'scripts/common/lib.sh'))}
bootstrap_fetch_seed_file {p(web.base)} repo.env {p(str(self.root / 'a'))} 0600
installer_fetch_seed_path {p(web.base)} repo.env {p(str(self.root / 'b'))} 0600
installer_seed_path_exists {p(web.base)} repo.env
'''
        result = self.shell(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(web.counts[RAW_PREFIX + '/repo.env'], 1)
        profile = next((FORKY / 'classes/class-profile').glob('*.cfg')).relative_to(FORKY)
        result = self.shell(f'source_fetch {p(web.base)} {p(str(profile))} {p(str(self.root / "profile"))}')
        self.assertEqual(result.returncode, 0, result.stderr)
    def test_failed_http_fetch_preserves_existing_destination(self):
        web = self.endpoint()
        dest = self.root / 'output'
        dest.write_text('keep-me')
        result = self.shell(f'source_http_get {shlex.quote(web.base + "/missing")} {shlex.quote(str(dest))}')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(payload_read_text(dest), 'keep-me')
        self.assertFalse(list(self.root.glob('output.part.*')))
        self.assertTrue(payload_source_is_file(Path(str(dest) + '.fetch-error')))
        self.assertEqual(web.counts[RAW_PREFIX + '/missing'], 1)
    def test_local_symlink_escape_is_rejected(self):
        local = self.root / 'seed'
        local.mkdir()
        (local / 'escape').symlink_to('/etc/passwd')
        result = self.shell(f'source_transfer {shlex.quote(str(local))} escape {shlex.quote(str(self.root / "out"))}')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(payload_source_exists(self.root / 'out'))
    def test_redirect_resolution_does_not_enforce_scheme_or_authority(self):
        header = self.root / 'headers'
        for location in ('http://host/path', 'file:///etc/passwd'):
            header.write_text('  Location: ' + location + '\n')
            result = self.shell(f'source_effective_url https://host/seed.cfg {shlex.quote(str(header))}')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), location)
    def tls_endpoint(self):
        if not shutil.which('openssl'):
            self.skipTest('openssl needed to generate the private fixture certificate')
        cert, key = self.root / 'cert.pem', self.root / 'key.pem'
        configuration = self.root / 'openssl.cnf'
        configuration.write_text('[req]\ndistinguished_name=dn\n[dn]\n')
        subprocess.run(payload_installed_argv([
            'openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
            '-config', str(configuration), '-subj', '/CN=localhost',
            '-addext', 'subjectAltName=IP:127.0.0.1,DNS:localhost',
            '-keyout', str(key), '-out', str(cert)]),
            env=self.env, check=True, capture_output=True, timeout=15)
        key.chmod(0o600)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        return self.endpoint(tls=context), cert

    def gnu_tls_wget(self):
        executable = shutil.which('wget', path=self.env['PATH'])
        self.assertIsNotNone(executable)
        options = subprocess.run([executable, '--help'], env=self.env, check=True,
                                 capture_output=True, text=True, timeout=5).stdout
        if '--no-config' not in options or '--ca-certificate' not in options:
            self.skipTest('certificate fixtures require GNU wget; BusyBox HTTPS refusal has a separate mock')
        return executable

    def test_busybox_https_is_rejected_before_any_transfer(self):
        environment, calls = self.busybox_wget_mock(self.root)
        for scope in ('repository', 'seed', 'external'):
            with self.subTest(scope=scope):
                destination = self.root / ('busybox-https-' + scope)
                destination.write_bytes(b'preserve existing destination\n')
                result = self.shell(
                    'source_http_get https://fixture.invalid/seed/payload.manifest ' +
                    shlex.quote(str(destination)) + " '' " + scope, env=environment)
                self.assertEqual(result.returncode, 125, result.stdout + result.stderr)
                self.assertIn('HTTPS requires certificate-verifying GNU wget and configured CA trust', result.stderr)
                self.assertEqual(destination.read_bytes(), b'preserve existing destination\n')
                self.assertFalse(calls.exists(), 'unsupported TLS client attempted a transfer')
                self.assertEqual(list(self.root.glob(destination.name + '.part.*')), [])

    def test_https_rejects_untrusted_certificate_and_legacy_bypass_flags(self):
        self.gnu_tls_wget()
        web, _ = self.tls_endpoint()
        destination = self.root / 'tls'
        destination.write_text('preserve prior destination\n')
        command = f'source_http_get {shlex.quote(web.base + "/repo.env")} {shlex.quote(str(destination))}'
        flags = ('', 'allow_unauthenticated_ssl', 'allow_unauthenticated_ssl=true',
                 'debian-installer/allow_unauthenticated_ssl=true',
                 'd-i/allow_unathenticated_ssl=true', 'allow_unauthenticated_ssl=false')
        for flag in flags:
            with self.subTest(flag=flag):
                result = self.shell(command, env={'INSTALLER_CMDLINE': flag})
                self.assertNotEqual(result.returncode, 0, result.stderr)
                self.assertEqual(destination.read_text(), 'preserve prior destination\n')
                self.assertTrue(Path(str(destination) + '.fetch-error').is_file())
        self.assertEqual(sum(web.counts.values()), 0, 'untrusted TLS delivered a request body')

    def test_https_accepts_only_the_explicit_private_fixture_trust(self):
        executable = self.gnu_tls_wget()
        web, certificate = self.tls_endpoint()
        directory = self.root / 'trusted-bin'
        directory.mkdir(mode=0o700)
        wrapper = directory / 'wget'
        wrapper.write_text(
            '#!/bin/sh\nif [ "${1-}" = --help ]; then exec ' + shlex.quote(executable) +
            ' "$@"; fi\nexec ' + shlex.quote(executable) + ' --ca-certificate=' +
            shlex.quote(str(certificate)) + ' "$@"\n')
        wrapper.chmod(0o700)
        destination = self.root / 'trusted-tls'
        command = f'source_http_get {shlex.quote(web.base + "/repo.env")} {shlex.quote(str(destination))}'
        result = self.shell(command, env={'PATH': str(directory) + ':' + self.env['PATH']})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(payload_read_bytes(destination), payload_read_bytes(FORKY / 'repo.env'))

    def test_downloader_without_redirect_control_is_used_directly(self):
        busybox = shutil.which('busybox')
        if not busybox:
            self.skipTest('BusyBox is not installed')
        bindir = self.root / 'bin'
        bindir.mkdir()
        wget = bindir / 'wget'
        wget.write_text('#!/bin/sh\nexec ' + shlex.quote(busybox) + ' wget "$@"\n')
        wget.chmod(0o755)
        anna = bindir / 'anna-install'
        anna.write_text('#!/bin/sh\nexit 1\n')
        anna.chmod(0o755)
        web = self.endpoint()
        result = self.shell('source_resolve_seed', env={'PATH': str(bindir) + ':' + os.environ['PATH'],
                            'INSTALLER_CMDLINE': f'url={web.url}/short'})
        self.assertNotEqual(result.returncode, 125, result.stderr)
        self.assertGreater(sum(web.counts.values()), 0)

class SnapshotTests(TransportFixture):
    def make_payload(self, files=None, special=None):
        seed = self.root / 'seed'
        seed.mkdir()
        files = dict(files or {'repo.env': b'REPOSITORY_ROLE="server"\n',
                               'scripts/common/lib.sh': b'#!/bin/sh\ntrue\n',
                               'common.cfg': b'# fixture\n'})
        files.update({name: b'# fixture\n' for name in (
            'hosts/profiles/shared.env', 'hosts/profiles/desktop/shared-de.env',
            'hosts/profiles/server/shared-srv.env')})
        files['catalog/compiled/suite-qualification.tsv'] = (
            b'format\t1\n'
            b'forky\tdesktop\tsource-candidate\tfixture\tfixture\n'
            b'forky\tserver\tsource-candidate\tfixture\tfixture\n'
            b'trixie\tdesktop\tsource-candidate\tfixture\tfixture\n'
            b'trixie\tserver\tsource-candidate\tfixture\tfixture\n')
        manifest = ('format=3\n' + ''.join(
            f'{len(data)}\t{digest(data)}\t{name}\n' for name, data in files.items())).encode()
        archive = io.BytesIO()
        with tarfile.open(fileobj=archive, mode='w:gz') as tf:
            for name, data in files.items():
                p = seed / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_bytes(data)
                info = tarfile.TarInfo(name)
                info.size, info.mode = len(data), 0o644
                tf.addfile(info, io.BytesIO(data))
            if special:
                tf.addfile(special)
        (seed / 'payload.tar.gz').write_bytes(archive.getvalue())
        (seed / 'payload.manifest').write_bytes(manifest)
        return seed, digest(archive.getvalue()), digest(manifest)
    def prepare(self, seed, archive, manifest):
        return self.shell(f'source_prepare_payload {shlex.quote(str(seed))} {archive} {manifest}',
                          env={'INSTALLER_SUITE': 'forky'})

    def test_busybox_http_accepts_a_payload_only_after_trusted_pin_comparison(self):
        seed, archive, manifest = self.make_payload()
        environment, calls = self.busybox_wget_mock(seed)
        environment['INSTALLER_SUITE'] = 'forky'
        base = 'http://fixture.invalid/seed'
        result = self.shell(f'source_prepare_payload {base} {archive} {manifest}', env=environment)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(calls.read_text().splitlines(), ['transfer', 'transfer'])
        self.assertEqual((self.runtime / 'bootstrap/payload.ready').read_text(),
                         f'verified-v1 {archive} {manifest} {base}\n')
        self.assertEqual((self.runtime / 'cache/seed/common.cfg').read_bytes(), b'# fixture\n')

    def test_busybox_http_rejects_wrong_pins_before_archive_parsing(self):
        seed, archive, manifest = self.make_payload()
        environment, _ = self.busybox_wget_mock(seed)
        for field, archive_pin, manifest_pin in (
                ('archive', '0' * 64, manifest), ('manifest', archive, '0' * 64)):
            with self.subTest(field=field):
                runtime = self.root / ('rejected-' + field)
                parsed = self.root / ('parsed-' + field)
                command = ('tar() { printf called > ' + shlex.quote(str(parsed)) + '; return 99; }; ' +
                           f'source_prepare_payload http://fixture.invalid/seed {archive_pin} {manifest_pin}')
                result = self.shell(command, env={**environment, 'INSTALLER_SUITE': 'forky',
                                                  'INSTALLER_RUNTIME_DIR': str(runtime)})
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(f'payload {field} SHA-256 differs from trusted preseed pin', result.stderr)
                self.assertFalse(parsed.exists(), 'untrusted HTTP bytes reached the archive parser')
                self.assertFalse((runtime / 'bootstrap/payload.ready').exists())
                self.assertFalse((runtime / 'cache/seed').exists())

    def reject_before_archive_parser(self, seed, archive, manifest):
        called = self.root / 'archive-parser-called'
        command = ('tar() { printf called > ' + shlex.quote(str(called)) + '; return 99; }; '
                   'source_prepare_payload ' + shlex.quote(str(seed)) + ' ' + archive + ' ' + manifest)
        result = self.shell(command, env={'INSTALLER_SUITE': 'forky'})
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(called.exists(), 'untrusted bytes reached the archive parser')
        return result
    def test_manifest_pin_is_compared_before_archive_parsing(self):
        seed, archive, manifest = self.make_payload()
        self.reject_before_archive_parser(seed, archive, '0' * 64)
        self.assertFalse(payload_source_exists(self.runtime / 'bootstrap/payload.ready'))
    def test_archive_pin_is_compared_before_archive_parsing(self):
        seed, archive, manifest = self.make_payload()
        self.reject_before_archive_parser(seed, '0' * 64, manifest)
        self.assertFalse(payload_source_exists(self.runtime / 'bootstrap/payload.ready'))
    def test_legacy_receipt_cannot_authorize_unverified_bytes(self):
        seed, archive, manifest = self.make_payload()
        self.runtime.mkdir(mode=0o700, exist_ok=True)
        boot = self.runtime / 'bootstrap'
        boot.mkdir(parents=True, exist_ok=True, mode=0o700)
        marker = boot / 'payload.ready'
        marker.write_text(f'{archive} {manifest} {seed}\n')
        marker.chmod(0o600)
        (seed / 'payload.tar.gz').write_bytes(b'corrupt after old unverified receipt\n')
        self.reject_before_archive_parser(seed, archive, manifest)
    def test_protected_snapshot_hashes_each_transfer_once(self):
        seed, archive, manifest = self.make_payload()
        calls = self.root / 'hash-calls'
        command = ('source_sha256() { printf x >> ' + shlex.quote(str(calls)) +
                   '; command sha256sum; }; ' +
                   'source_prepare_payload ' + shlex.quote(str(seed)) + ' ' + archive + ' ' + manifest +
                   '; source_prepare_payload ' + shlex.quote(str(seed)) + ' ' + archive + ' ' + manifest)
        result = self.shell(command, env={'INSTALLER_SUITE': 'forky'})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(calls.read_text(), 'xx', 'archive and manifest each need one trusted-pin comparison')
    def test_loose_local_edit_does_not_replace_the_selected_archive(self):
        seed, archive, manifest = self.make_payload()
        (seed / 'common.cfg').write_text('# unpublished edit\n')
        result = self.prepare(seed, archive, manifest)
        self.assertEqual(result.returncode, 0, result.stderr)
        destination = self.root / 'selected-common.cfg'
        result = self.shell('source_fetch ' + shlex.quote(str(seed)) + ' common.cfg ' +
                            shlex.quote(str(destination)))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(destination.read_bytes(), b'# fixture\n')
    def test_symlink_member_is_rejected_before_extraction(self):
        member = tarfile.TarInfo('escape')
        member.type, member.linkname = tarfile.SYMTYPE, '/etc/passwd'
        seed, archive, manifest = self.make_payload(special=member)
        result = self.prepare(seed, archive, manifest)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('non-regular', result.stderr)
    def test_missing_snapshot_file_cannot_fall_back_to_network(self):
        seed, archive, manifest = self.make_payload()
        web = self.endpoint(seed)
        result = self.prepare(web.base, archive, manifest)
        self.assertEqual(result.returncode, 0, result.stderr)
        (seed / 'new-file').write_text('not in the pinned snapshot')
        result = self.shell(f'source_fetch {shlex.quote(web.base)} new-file {shlex.quote(str(self.root / "out"))}')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('absent from validated payload', result.stderr)
        self.assertEqual(web.counts[RAW_PREFIX + '/new-file'], 0)
    def test_duplicate_archive_member_is_rejected(self):
        member = tarfile.TarInfo('common.cfg')
        member.size = 0
        seed, archive, manifest = self.make_payload(special=member)
        result = self.prepare(seed, archive, manifest)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('duplicate', result.stderr)
    def test_archive_path_traversal_is_rejected(self):
        member = tarfile.TarInfo('../escape')
        member.size = 0
        seed, archive, manifest = self.make_payload(special=member)
        result = self.prepare(seed, archive, manifest)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('traversal', result.stderr)
        self.assertFalse(payload_source_exists(self.runtime / 'bootstrap/escape'))
    def test_extraction_does_not_repeat_the_build_time_shell_syntax_sweep(self):
        seed, archive, manifest = self.make_payload({
            'repo.env': b'REPOSITORY_ROLE="server"\n',
            'scripts/common/lib.sh': b'#!/bin/sh\nif then\n'})
        result = self.prepare(seed, archive, manifest)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('invalid shell syntax', result.stderr)
        self.assertTrue(payload_source_exists(self.runtime / 'bootstrap/payload.ready'))
    def test_snapshot_cache_reuses_archive_and_manifest(self):
        seed, archive, manifest = self.make_payload()
        web = self.endpoint(seed)
        for _ in range(2):
            result = self.prepare(web.base, archive, manifest)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(web.counts[RAW_PREFIX + '/payload.tar.gz'], 1)
        self.assertEqual(web.counts[RAW_PREFIX + '/payload.manifest'], 1)

class FlatOfflineSnapshotTests(TransportFixture):
    def make_flat_seed(self):
        # Import the pure source adapter only after the isolation gate. This
        # creates a tiny flat fixture directly; no offline compiler, network,
        # package operation or nested payload archive runs in this test.
        from offline import local_bootstrap
        seed = self.root / 'bundle/d-i/forky'
        tree = seed.parent / 'debian'
        seed.mkdir(parents=True)
        files = {
            'repo.env': b'REPOSITORY_FAMILIES="desktop server"\n',
            'scripts/common/lib.sh': b'#!/bin/sh\n# fixture definitions only\n',
            'common.cfg': b'# verified flat fixture\n',
            'hosts/profiles/shared.env': b'# shared fixture\n',
            'hosts/profiles/desktop/shared-de.env': b'# desktop fixture\n',
            'hosts/profiles/server/shared-srv.env': b'# server fixture\n',
            'catalog/compiled/suite-qualification.tsv': (
                b'format\t1\n'
                b'forky\tdesktop\tsource-candidate\tfixture\tfixture\n'
                b'forky\tserver\tsource-candidate\tfixture\tfixture\n'
                b'trixie\tdesktop\tsource-candidate\tfixture\tfixture\n'
                b'trixie\tserver\tsource-candidate\tfixture\tfixture\n'),
        }
        for name, data in files.items():
            path = tree / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        manifest = ('format=3\n' + ''.join(
            f'{len(data)}\t{digest(data)}\t{name}\n' for name, data in sorted(files.items()))).encode()
        (seed / 'payload.manifest').write_bytes(manifest)
        adapted = self.root / 'flat-source.sh'
        adapted.write_bytes(local_bootstrap(SOURCE.read_bytes()))
        return seed, tree, adapted, digest(b'offline-tree-v1\n' + manifest), digest(manifest), files

    def prepare_flat(self, seed, adapted, archive, manifest):
        return self.shell('. ' + shlex.quote(str(adapted)) + '\nsource_prepare_payload ' +
                          shlex.quote(str(seed)) + ' ' + archive + ' ' + manifest,
                          env={'INSTALLER_SUITE': 'forky'})

    def test_flat_tree_is_verified_and_copied_without_an_archive(self):
        seed, tree, adapted, archive, manifest, files = self.make_flat_seed()
        result = self.prepare_flat(seed, adapted, archive, manifest)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((seed / 'payload.tar.gz').exists())
        self.assertEqual((self.runtime / 'bootstrap/payload.ready').read_text(),
                         f'verified-v1 {archive} {manifest} {seed}\n')
        for name, data in files.items():
            self.assertEqual((self.runtime / 'cache/seed' / name).read_bytes(), data)

    def test_same_size_corrupted_flat_member_cannot_publish_a_receipt(self):
        seed, tree, adapted, archive, manifest, files = self.make_flat_seed()
        original = files['common.cfg']
        (tree / 'common.cfg').write_bytes(b'X' * len(original))
        self.assertEqual((tree / 'common.cfg').stat().st_size, len(original))
        result = self.prepare_flat(seed, adapted, archive, manifest)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('offline source member SHA-256 differs from trusted preseed pin', result.stderr)
        self.assertFalse((self.runtime / 'bootstrap/payload.ready').exists())
        self.assertFalse((self.runtime / 'cache/seed').exists())


class RealBootstrapTests(TransportFixture):
    def include(self, cmdline):
        text = payload_read_text(FORKY / 'preseed.cfg').replace('\\\n', '')
        line = next(line for line in text.splitlines() if line.startswith('d-i preseed/include_command string '))
        command = line.split(' string ', 1)[1]
        return subprocess.run(payload_installed_argv(['/bin/sh', '-c', command]), capture_output=True, text=True,
            env={**self.env, 'INSTALLER_CMDLINE': cmdline}, timeout=45)
    def test_corrupt_source_helper_is_rejected_before_shell_execution(self):
        seed = self.root / 'untrusted-helper-seed'
        seed.mkdir()
        (seed / 'preseed.cfg').write_bytes(payload_read_bytes(FORKY / 'preseed.cfg'))
        sentinel = self.root / 'untrusted-helper-executed'
        (seed / 'source.sh').write_text(
            '#!/bin/sh\nprintf unsafe > ' + shlex.quote(str(sentinel)) + '\nexit 77\n')
        result = self.include(f'file={seed}/preseed.cfg classes=prod;{ROLE};standard;dhcp;ssh')
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(sentinel.exists(), 'unpinned source helper executed before authentication')
    def test_complete_local_bootstrap_and_flat_profile(self):
        result = self.include(f'file={FORKY}/preseed.cfg classes=prod;{ROLE};standard;dhcp;ssh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(result.stdout.splitlines()), 6)
        run_controls = []
        for line in result.stdout.splitlines():
            self.assertTrue(line.startswith('file:///'))
            path = Path(line.removeprefix('file://'))
            self.assertTrue(payload_source_is_file(path))
            if path.name == 'preseed-run.cfg':
                run_controls.append(path)
        self.assertEqual(len(run_controls), 1)
        self.assertEqual(
            payload_read_text(run_controls[0]),
            f'd-i preseed/run string file://{self.runtime}/bootstrap/preseed-apply.sh\n',
        )
        self.assertTrue(payload_source_is_file(self.runtime / 'bootstrap/preflight.ok'))
        self.assertIn(f'role/{ROLE}', payload_read_text(self.runtime / 'state/context.env'))
        self.assertTrue(payload_source_is_file(self.runtime / 'state/selected-host.env'))
    def test_complete_short_url_bootstrap_fetches_snapshot_once(self):
        web = self.endpoint()
        result = self.include(f'url={web.url}/short classes=prod;{ROLE};standard;dhcp;ssh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(web.counts[RAW_PREFIX + '/scripts/common/source.sh'], 1)
        self.assertEqual(web.counts[RAW_PREFIX + '/payload.tar.gz'], 1)
        self.assertEqual(web.counts[RAW_PREFIX + '/payload.manifest'], 1)
        # Individual envs, class fragments and late assets never hit the network.
        self.assertEqual(sum(web.counts.values()), 5, dict(web.counts))
    @skip_unless_process_tree_visibility
    def test_opposite_role_fails_before_preflight_marker(self):
        other = 'desktop' if ROLE == 'server' else 'server'
        text = payload_read_text(FORKY / 'preseed.cfg').replace('\\\n', '')
        line = next(line for line in text.splitlines() if line.startswith('d-i preseed/include_command string '))
        command = line.split(' string ', 1)[1]
        process = subprocess.Popen(payload_installed_argv(['/bin/sh', '-c', command]), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, start_new_session=True,
            env={**self.env, 'INSTALLER_CMDLINE': f'file={FORKY}/preseed.cfg classes=prod;{other};standard;dhcp'})
        try:
            failure = self.runtime / 'state/first-failure'
            self.assertTrue(wait_file(failure), 'bootstrap did not retain its fatal record')
            self.assertIsNone(process.poll(), 'fatal bootstrap returned to the installer')
            self.assertFalse(payload_source_exists(self.runtime / 'bootstrap/preflight.ok'))
            self.assertIn('state=FATAL', payload_read_text(failure))
        finally:
            stop_test_tree(process)

if __name__ == '__main__':
    unittest.main()
