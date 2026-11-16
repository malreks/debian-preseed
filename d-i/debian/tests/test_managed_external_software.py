#!/usr/bin/env python3
'''Managed external Debian repository and package-policy regressions.'''
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

from payload_fixture import installed_argv as payload_installed_argv, source_is_file as payload_source_is_file
from payload_fixture import read_text as payload_read_text

import hashlib
import io
import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import tarfile
import tempfile
import unittest
from unittest import mock

FORKY = Path(__file__).resolve().parents[1]
PERL_LIB = FORKY / (
    'hooks/target/usr/local/lib/perl5/site_perl/apt-repo-local'
)
SERVICING = PERL_LIB / 'APTRepoLocal/Servicing'
DISCORD_ARCHIVE_HELPER = FORKY / 'hooks/target/usr/local/libexec/desktop/discord-distro'
SYSTEM_PATH = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'


class SoftwareDownloadLoggingTests(unittest.TestCase):
    def test_download_logging_omits_redirect_credentials_and_preserves_transport_url(self):
        source = payload_read_text(FORKY / 'scripts/late/software.sh')
        match = re.search(
            r'(?ms)^  download_log_host=\$\{effective_url#https://\}.*?^  software_info [^\n]+$', source)
        self.assertIsNotNone(match)
        script = ('effective_url=$1\nlabel=Fixture\nhttp_status=200\n'
                  'normalized_content_type=application/octet-stream\ndestination_size=64\n'
                  'software_info() { printf "%s\\n" "$*"; }\n' + match[0] +
                  '\n[ "$effective_url" = "$1" ]\n')
        for url in (
            'https://cdn.example/package.deb?sig=fixture-signature&jwt=fixture-token',
            'https://fixture-user:fixture-secret@cdn.example/package.deb?token=fixture-token',
            'https://cdn.example?sig=fixture-signature',
            'https://cdn.example#fixture-secret',
            'https://cdn.example/package.deb',
        ):
            with self.subTest(url=url):
                result = subprocess.run(payload_installed_argv(['/bin/sh', '-eu', '-c', script, 'fixture', url]),
                                        env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'},
                                        text=True, capture_output=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, 'resolved Fixture download effective_host=cdn.example '
                                 'http_status=200 content_type=application/octet-stream bytes=64\n')


class ProxyAPTSourceTests(unittest.TestCase):
    def test_3proxy_archive_is_grouped_without_changing_its_scoped_key(self):
        normalizer = runpy.run_path(str(FORKY / 'hooks/target/usr/local/libexec/common/apt-repo-local-normalize-sources'))
        self.assertEqual(normalizer['vendor']('https://3proxy.org/repo/deb'), '3proxy')
        for uri in ('https://3proxy.org/other', 'https://3proxy.org.example/repo/deb'):
            self.assertNotEqual(normalizer['vendor'](uri), '3proxy')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            parts = root / 'etc/apt/sources.list.d'
            parts.mkdir(parents=True)
            key = '/etc/apt/keyrings/local11.asc'
            (parts / 'local11.list').write_text(
                f'deb [signed-by={key}] https://3proxy.org/repo/deb current main\n', encoding='utf-8')
            # Root ownership is modeled; parsing, publication and idempotence
            # use real temporary files, never the development host APT tree.
            globals_ = normalizer['normalize'].__globals__
            with mock.patch.dict(globals_, directory=lambda p: p.mkdir(parents=True, exist_ok=True),
                                 regular=lambda p: p.read_bytes(), keyring_bytes=lambda *a: None):
                self.assertEqual(normalizer['normalize'](root), ['3proxy.sources'])
                published = (parts / '3proxy.sources').read_bytes()
                normalizer['normalize'](root)
                self.assertEqual((parts / '3proxy.sources').read_bytes(), published)
            self.assertIn(('Signed-By: ' + key).encode(), published)
            self.assertIn(b'Suites: current\nComponents: main\n', published)
            self.assertFalse((parts / 'local11.list').exists())
        software = (FORKY / 'classes/class-addon/software.cfg').read_text(encoding='utf-8')
        for row in ('local11/repository string https://3proxy.org/repo/deb current main',
                    'local11/key string https://3proxy.org/repo/3proxy-release-key.asc',
                    'local11/source boolean false'):
            self.assertIn(row, software)


class ManagedAPTRepoLocalTests(unittest.TestCase):
    def run_perl(self, source: str, *arguments: object) -> subprocess.CompletedProcess[str]:
        # A missing validation dependency is not a production assertion failure.
        # Probe file presence only: installed-but-broken modules must still fail.
        probe = subprocess.run(
            payload_installed_argv(['/usr/bin/perl', '-e',
             'for my $m (qw(Moo.pm MooX/StrictConstructor.pm MooX/Types/MooseLike/Base.pm)) '
             '{ unless (grep { -f "$_/$m" } @INC) { print "$m\\n"; exit 77; } }']),
            text=True, capture_output=True, timeout=10,
        )
        if probe.returncode == 77:
            self.skipTest('Perl validation dependency unavailable: ' + probe.stdout.strip()
                          + '; install libmoo-perl libmoox-strictconstructor-perl libmoox-types-mooselike-perl')
        self.assertEqual(probe.returncode, 0, probe.stderr)
        return subprocess.run(
            payload_installed_argv(['/usr/bin/perl', '-I', str(PERL_LIB), '-I', str(PERL_LIB.parent / 'runtime'), '-e', source,
             *(str(argument) for argument in arguments)]),
            env={'LC_ALL': 'C.UTF-8', 'PATH': SYSTEM_PATH},
            text=True,
            capture_output=True,
            timeout=30,
        )

    def run_discord_archive_helper(
        self,
        *arguments: object,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            payload_installed_argv(['/usr/bin/python3', '-I', str(DISCORD_ARCHIVE_HELPER),
             *(str(argument) for argument in arguments)]),
            env={**os.environ, 'LC_ALL': 'C.UTF-8', 'PATH': SYSTEM_PATH},
            text=True,
            capture_output=True,
            timeout=30,
        )

    def write_discord_module_archive(
        self,
        path: Path,
        *,
        link_name: str = 'files/node_modules/.bin/proto-loader-gen-types',
        link_target: str = '../@grpc/proto-loader/build/bin/proto-loader-gen-types.js',
        target_mode: int = 0o755,
    ) -> bytes:
        payload = b'#!/usr/bin/env node\n'
        target_name = (
            'files/node_modules/@grpc/proto-loader/build/bin/'
            'proto-loader-gen-types.js'
        )
        with tarfile.open(path, 'w', format=tarfile.USTAR_FORMAT) as archive:
            target = tarfile.TarInfo(target_name)
            target.mode = target_mode
            target.size = len(payload)
            archive.addfile(target, io.BytesIO(payload))

            link = tarfile.TarInfo(link_name)
            link.type = tarfile.SYMTYPE
            link.linkname = link_target
            archive.addfile(link)
        return payload

    def discord_manifest(self, *, package_sizes: bool = True) -> dict:
        required = ['discord_desktop_core', 'discord_erlpack', 'discord_spellcheck',
                    'discord_utils', 'discord_voice']
        base = 'https://stable.dl2.discordapp.net/distro/app/stable/linux/x64/1.0.170'

        def package(url: str, *, module: bool = False, delta: bool = False) -> dict:
            value = {'host_version': [1, 0, 169 if delta else 170],
                     'package_sha256': 'a' * 64, 'url': base + url}
            if module:
                value['module_version'] = 1
            if package_sizes:
                value['package_size'] = 1024
            return value

        return {
            'full': package('/full.distro'),
            'deltas': [package('/from/1.0.169', delta=True)],
            'modules': {
                name: {'full': package(f'/{name}/1/full.distro', module=True),
                       'deltas': [package(f'/{name}/1/from/1.0.169/1',
                                          module=True, delta=True)]}
                for name in required
            },
            'required_modules': required, 'metadata_version': 1, 'required_update': False,
        }

    def test_discord_manifest_accepts_optional_package_sizes_without_changing_adapter_schema(self):
        with tempfile.TemporaryDirectory(prefix='discord-manifest-') as temporary:
            path = Path(temporary) / 'manifest.json'
            normalized = []
            for package_sizes in (False, True):
                path.write_text(json.dumps(self.discord_manifest(package_sizes=package_sizes)),
                                encoding='utf-8')
                result = self.run_discord_archive_helper('manifest', '--path', path)
                self.assertEqual(result.returncode, 0, result.stderr)
                release = json.loads(result.stdout)
                self.assertEqual(set(release), {'host', 'modules', 'required_modules', 'version'})
                self.assertEqual(set(release['host']), {'sha256', 'url'})
                for module in release['modules'].values():
                    self.assertEqual(set(module), {'sha256', 'url', 'version', 'required'})
                normalized.append(release)
            self.assertEqual(normalized[0], normalized[1])

    def test_discord_manifest_rejects_invalid_package_sizes_and_unknown_fields_in_all_records(self):
        with tempfile.TemporaryDirectory(prefix='discord-manifest-invalid-') as temporary:
            path = Path(temporary) / 'manifest.json'
            for location in ('host-full', 'host-delta', 'module-full', 'module-delta'):
                for value in (None, True, 0, -1, '1024', 1.5, 2**40, 'unknown-field'):
                    with self.subTest(location=location, value=value):
                        manifest = self.discord_manifest()
                        package = {
                            'host-full': manifest['full'],
                            'host-delta': manifest['deltas'][0],
                            'module-full': manifest['modules']['discord_voice']['full'],
                            'module-delta': manifest['modules']['discord_voice']['deltas'][0],
                        }[location]
                        if value == 'unknown-field':
                            package['unexpected'] = 1024
                        else:
                            package['package_size'] = value
                        path.write_text(json.dumps(manifest), encoding='utf-8')
                        result = self.run_discord_archive_helper('manifest', '--path', path)
                        self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_managed_bootstrap_uses_transport_retries_without_repeating_publication(self):
        source = payload_read_text(FORKY / 'scripts/late/software.sh')
        for component in ('discord', 'tomat'):
            with self.subTest(component=component):
                match = re.search(r'(?ms)^software_install_' + component +
                                  r'_app\(\) \{\n.*?^\}', source)
                self.assertIsNotNone(match)
                # Exercise the real worker under errexit. Only the target
                # executor fails; no download or target command is executed.
                script = '''
target_root=/fixture-target
discord_desktop_file=/fixture.desktop
software_update_helper=/fixture-updater
DIR_PERL5_SITE_PERL=/fixture-perl
work_dir=/fixture-work
SOFTWARE_TOMAT_TAG=v1.2.3
SOFTWARE_TOMAT_URL=https://example.invalid/pinned.deb
SOFTWARE_TOMAT_SHA256=fixture-digest
software_stage_seed_asset() { :; }
installer_repo_file_value() { printf fixture; }
chroot() { :; }
run_in_target() { printf 'TARGET_ATTEMPT\\n'; return 37; }
attempt_in_target() { run_in_target "$@"; }
'''
                script += match[0] + '\nsoftware_install_' + component + '_app\n'
                script += "printf 'INCORRECT_SUCCESS\\n'\n"
                result = subprocess.run(
                    payload_installed_argv(['/bin/sh', '-eu', '-c', script]),
                    env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'},
                    text=True, capture_output=True, timeout=10,
                )
                self.assertEqual(result.returncode, 37, result.stderr)
                self.assertEqual(result.stdout, 'TARGET_ATTEMPT\n')

    def test_discord_module_npm_bin_symlink_is_materialized_as_a_regular_file(self):
        with tempfile.TemporaryDirectory(prefix='discord-module-symlink-') as temporary:
            archive_path = Path(temporary) / 'discord_voice.tar'
            payload = self.write_discord_module_archive(archive_path)
            arguments = (
                'inspect', '--path', archive_path, '--kind', 'module',
                '--version', '1.0.158', '--module-name', 'discord_voice',
                '--module-version', 1,
            )
            result = self.run_discord_archive_helper(*arguments)
            self.assertEqual(result.returncode, 0, result.stderr)
            metadata = json.loads(result.stdout)
            self.assertEqual(metadata['members'], 2)
            self.assertEqual(metadata['regular_files'], 2)
            self.assertEqual(metadata['unpacked_bytes'], len(payload) * 2)

            helper = runpy.run_path(
                str(DISCORD_ARCHIVE_HELPER),
                run_name='managed_discord_distro_test',
            )
            archive, members, _ = helper['inspect_archive'](
                str(archive_path),
                kind='module',
                version='1.0.158',
                module_name='discord_voice',
                module_version=1,
            )
            try:
                materialized = dict((canonical, member) for member, canonical in members)[
                    'files/node_modules/.bin/proto-loader-gen-types'
                ]
                self.assertTrue(materialized.isreg())
                self.assertFalse(materialized.issym())
                self.assertEqual(materialized.mode & 0o777, 0o755)
                with archive.extractfile(materialized) as stream:
                    self.assertEqual(stream.read(), payload)
            finally:
                archive.close()

    def test_discord_module_rejects_unsafe_or_dangling_symlinks(self):
        cases = (
            (
                'escaping target',
                'files/node_modules/.bin/proto-loader-gen-types',
                '../../../outside',
                0o755,
            ),
            (
                'outside npm bin',
                'files/node_modules/proto-loader-gen-types',
                '@grpc/proto-loader/build/bin/proto-loader-gen-types.js',
                0o755,
            ),
            (
                'dangling target',
                'files/node_modules/.bin/proto-loader-gen-types',
                '../missing.js',
                0o755,
            ),
            (
                'non-executable target',
                'files/node_modules/.bin/proto-loader-gen-types',
                '../@grpc/proto-loader/build/bin/proto-loader-gen-types.js',
                0o644,
            ),
        )
        with tempfile.TemporaryDirectory(prefix='discord-module-unsafe-link-') as temporary:
            for index, (label, link_name, link_target, target_mode) in enumerate(cases):
                with self.subTest(label=label):
                    archive_path = Path(temporary) / f'fixture-{index}.tar'
                    self.write_discord_module_archive(
                        archive_path,
                        link_name=link_name,
                        link_target=link_target,
                        target_mode=target_mode,
                    )
                    result = self.run_discord_archive_helper(
                        'inspect', '--path', archive_path, '--kind', 'module',
                        '--version', '1.0.158', '--module-name', 'discord_voice',
                        '--module-version', 1,
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('fatal: Discord module tar ', result.stderr)

    def test_repository_package_digest_uses_the_512_mib_streaming_bound(self):
        repository = payload_read_text(SERVICING / 'Repository.pm')
        self.assertIn('APTRepoLocal::Servicing::Atomic->sha256_file(', repository)
        self.assertNotIn('read_limited($path, 536_870_912)', repository)

        with tempfile.TemporaryDirectory(prefix='x-package-digest-') as temporary:
            path = Path(temporary) / 'archive.deb'
            size = 64 * 1024 * 1024 + 1
            with path.open('wb') as stream:
                stream.write(b'x-package-digest\0')
                stream.seek(size - 1)
                stream.write(b'\0')
            with path.open('rb') as stream:
                expected_sha256 = hashlib.file_digest(stream, 'sha256').hexdigest()
            source = r'''
use strict;
use warnings;
use APTRepoLocal::Servicing::Atomic;
my ($size, $sha256) = APTRepoLocal::Servicing::Atomic->sha256_file(
    $ARGV[0],
    $ARGV[1],
);
print "$size|$sha256\n";
'''
            result = self.run_perl(source, path, 536_870_912)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                result.stdout,
                f'{size}|{expected_sha256}\n',
            )

            too_small = self.run_perl(source, path, size - 1)
            self.assertNotEqual(too_small.returncode, 0)
            self.assertIn('bounded regular file', too_small.stderr)

            symlink = Path(temporary) / 'archive-link.deb'
            symlink.symlink_to(path)
            indirect = self.run_perl(source, symlink, 536_870_912)
            self.assertNotEqual(indirect.returncode, 0)
            self.assertIn('bounded regular file', indirect.stderr)

    def test_chatgpt_repacked_depends_excludes_x11_xwayland_and_nvidia(self):
        dependencies = [
            'libgtk-3-0',
            'libnotify4',
            'libx11-6 (>= 2:1.4.99.1)',
            'libx11-xcb1',
            'libxcb-dri3-0',
            'libxcb1',
            'libxcursor1',
            'libxcomposite1',
            'libxdamage1',
            'libxext6',
            'libxfixes3',
            'libxi6',
            'libxinerama1',
            'libxkbfile1',
            'libxmu6',
            'libxpm4',
            'libxrandr2',
            'libxrender1',
            'libxres1',
            'libxss1',
            'libxt6',
            'libxtst6',
            'libxv1',
            'libxvmc1',
            'libxxf86vm1',
            'x11-utils',
            'xauth',
            'xfonts-base',
            'xorg',
            'xserver-xorg-core',
            'xwayland',
            'xwayland-dev',
            'nvidia-driver',
            'libnvidia-gl-580',
            'firmware-nvidia-gsp',
            'xserver-xorg-video-nvidia',
            'cuda-toolkit-13',
            'libcuda1',
            'mesa-vulkan-drivers | vulkan-icd',
            'nvidia-driver | mesa-utils',
            'libwayland-client0',
            'libxkbcommon0',
            'libglib2.0-bin | kde-cli-tools',
        ]
        expected = (
            'libgtk-3-0, libnotify4, mesa-utils, libwayland-client0, '
            'libxkbcommon0, libglib2.0-bin | kde-cli-tools'
        )
        with tempfile.TemporaryDirectory(prefix='chatgpt-control-rewrite-') as temporary:
            work = Path(temporary)
            package_root = work / 'package'
            control_dir = package_root / 'DEBIAN'
            executable = package_root / 'usr/lib/chatgpt/ChatGPT'
            control_dir.mkdir(parents=True)
            control_dir.chmod(0o755)
            executable.parent.mkdir(parents=True)
            executable.write_text('#!/bin/sh\nexit 0\n')
            executable.chmod(0o755)
            (control_dir / 'control').write_text(
                'Package: chatgpt\n'
                'Version: 1.0\n'
                'Architecture: amd64\n'
                'Maintainer: Test <test@example.invalid>\n'
                f'Depends: {", ".join(dependencies)}\n'
                'Description: managed ChatGPT dependency policy fixture\n'
            )
            package = work / 'source.deb'
            built = subprocess.run(
                payload_installed_argv(['/usr/bin/dpkg-deb', '--build', '--root-owner-group',
                 str(package_root), str(package)]),
                env={**os.environ, 'LC_ALL': 'C.UTF-8', 'PATH': SYSTEM_PATH},
                text=True,
                capture_output=True,
                timeout=30,
            )
            self.assertEqual(built.returncode, 0, built.stderr)

            source = r'''
use strict;
use warnings;
use APTRepoLocal::Servicing::ChatGPT;
use APTRepoLocal::Servicing::Deb;
my $deb = APTRepoLocal::Servicing::Deb->new(
    repository => bless({}, 'TestRepository'),
);
my $chatgpt = APTRepoLocal::Servicing::ChatGPT->new(
    state => bless({}, 'TestState'),
    release_policy => {
        generic_deb => {
            chatgpt => {
                url => 'https://fixture.invalid/chatgpt.deb',
            },
        },
    },
);
my $spec = $chatgpt->spec();
my $output = $deb->repack_without_dependencies(
    label        => $spec->{label},
    path         => $ARGV[0],
    work         => $ARGV[1],
    name         => $spec->{name},
    dependencies => $spec->{remove_dependencies},
);
print "$output\n";
'''
            repacked = self.run_perl(source, package, work)
            self.assertEqual(repacked.returncode, 0, repacked.stderr)
            output = Path(repacked.stdout.strip())
            self.assertTrue(payload_source_is_file(output))
            depends = subprocess.check_output(
                payload_installed_argv(['/usr/bin/dpkg-deb', '-f', str(output), 'Depends']),
                env={**os.environ, 'LC_ALL': 'C.UTF-8', 'PATH': SYSTEM_PATH},
                text=True,
                timeout=30,
            ).strip()
            self.assertEqual(depends, expected)
            for forbidden in (
                'x11', 'xcb', 'xcomposite', 'xdamage', 'xext', 'xfixes',
                'xrandr', 'xwayland', 'xorg', 'xserver', 'nvidia', 'cuda',
                'mesa-vulkan-drivers', 'vulkan-icd',
            ):
                with self.subTest(forbidden=forbidden):
                    self.assertNotIn(forbidden, depends.lower())
            self.assertIn('libwayland-client0', depends)
            self.assertIn('libxkbcommon0', depends)

    def test_repository_failure_is_reported_for_every_managed_deb(self):
        source = r'''
use strict;
use warnings;
use APTRepoLocal::Servicing::CLI;
{
    package TestDeb;
    sub installed_version { return undef; }
}
{
    package TestRepository;
    sub retain { die "synthetic repository failure\n"; }
}
{
    package TestEvent;
}
no warnings 'redefine';
local *APTRepoLocal::Servicing::CLI::_log = sub { return 1; };
my $cli = APTRepoLocal::Servicing::CLI->new();
my ($result, $reason) = $cli->_stage_deb(
    bless({}, 'TestDeb'),
    bless({}, 'TestEvent'),
    bless({}, 'TestRepository'),
    {name => 'synthetic', label => 'Synthetic managed package'},
    '/tmp/synthetic.deb',
    {package => 'synthetic', version => '1.0', architecture => 'amd64'},
);
print join('|', $result, $reason, $cli->apply_failure_detail()), "\n";
'''
        result = self.run_perl(source)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            '1|validation|repository: synthetic repository failure\n',
        )

    def test_release_module_failure_is_reported_for_every_release_managed_deb(self):
        source = r'''
use strict;
use warnings;
use APTRepoLocal::Servicing::CLI;
{
    package TestRelease;
    sub download { die "synthetic release validation failure\n"; }
}
no warnings 'redefine';
local *APTRepoLocal::Servicing::CLI::_log = sub { return 1; };
my $cli = APTRepoLocal::Servicing::CLI->new();
my ($result, $reason) = $cli->_fetch_release_deb(
    bless({}, 'TestRelease'), undef, undef, undef, '/fixture',
    {name => 'synthetic', label => 'Synthetic release package'},
);
print join('|', $result, $reason, $cli->apply_failure_detail()), "\n";
'''
        result = self.run_perl(source)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            '1|validation|release-download: synthetic release validation failure\n',
        )

    def test_repository_import_has_no_transfer_deadline_and_retains_exact_path(self):
        source = r'''
use strict;
use warnings;
use APTRepoLocal::Servicing::Repository;
my @deadlines;
no warnings 'redefine';
local *APTRepoLocal::Servicing::Repository::capture_command = sub {
    my %args = @_;
    push @deadlines, $args{timeout};
        if ($args{argv}[1] eq 'import') {
        die 'package import must not have a wall-clock timeout' if defined $args{timeout};
        return {status => 0, stdout => '/fixture/repo/pool/chatgpt/' . ('a' x 64)
                . "/chatgpt_1.0+localrepo1_amd64.deb\n"};
    }
    return {status => 0, stdout => "catalogue\n"};
};
my $repository = APTRepoLocal::Servicing::Repository->new(directory => '/fixture/repo');
my ($path, $created) = $repository->retain('/fixture/download.deb', {package => 'chatgpt'});
die 'missing import result' unless $created == 1;
print "$path\n";
$repository->_capture(APTRepoLocal::Servicing::Repository::HELPER(), 'list');
print join('|', map { defined $_ ? $_ : 'undef' } @deadlines), "\n";
'''
        result = self.run_perl(source)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(lines[0], '/fixture/repo/pool/chatgpt/' + 'a' * 64
                         + '/chatgpt_1.0+localrepo1_amd64.deb')
        imported, queried = lines[1].split('|')
        self.assertEqual(imported, 'undef')
        self.assertEqual(queried, '120')

    def test_repository_import_failure_preserves_managed_diagnostic_and_redacts_url(self):
        source = r'''
use strict;
use warnings;
use APTRepoLocal::Servicing::Repository;
no warnings 'redefine';
local *APTRepoLocal::Servicing::Repository::capture_command = sub {
    return {status => 2 << 8, stdout => q{}, stderr =>
        "unmanaged-secret-line\napt-repo-local: package validation failed https://user:password\@vendor.invalid/file?token=secret\nraw-hostile-payload\n"};
};
my $repository = APTRepoLocal::Servicing::Repository->new();
eval { $repository->retain('/fixture/package.deb', {package => 'chatgpt'}); };
print $@;
'''
        result = self.run_perl(source)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('managed repository import failed (exit 2: package validation failed [redacted-url])', result.stdout)
        for value in ('password', 'token=', 'unmanaged-secret-line', 'raw-hostile-payload'):
            self.assertNotIn(value, result.stdout + result.stderr)

    def test_repository_failure_distinguishes_timeout_and_signal_status(self):
        source = r'''
use strict;
use warnings;
use APTRepoLocal::Servicing::Repository;
no warnings 'redefine';
for my $result ({status => 124 << 8, error => 'timeout'}, {status => 9}) {
    local *APTRepoLocal::Servicing::Repository::capture_command = sub { return $result; };
    my $repository = APTRepoLocal::Servicing::Repository->new();
    eval { $repository->retain('/fixture/package.deb', {package => 'chatgpt'}); };
    print $@;
}
'''
        result = self.run_perl(source)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('operation returned an unexpected timeout status; outcome may be unknown', result.stdout)
        self.assertIn('managed repository import failed (signal 9)', result.stdout)
        self.assertNotIn('exit 124', result.stdout)

    def test_all_servicing_modules_load_before_any_application_transaction(self):
        source = r'''
use strict; use warnings;
my @modules = qw(Atomic ArtifactLimits Bitwarden ChatGPT CLI Deb Discord Event HTTP Ledger
                 Logger Notifier Obsidian Postman Process Repository Sleek State Tomat Tuta);
for my $name (@modules) {
    my $module = "APTRepoLocal/Servicing/$name.pm";
    require $module;
}
print scalar(@modules), " servicing modules loaded\n";
'''
        result = self.run_perl(source)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '20 servicing modules loaded\n')

    def test_chatgpt_configure_does_not_load_postman(self):
        if os.geteuid() != 0:
            self.skipTest('vendor entrypoint requires root in the isolated fixture')
        source = r'''
use strict; use warnings;
use APTRepoLocal::Servicing::State;
use APTRepoLocal::Servicing::CLI;
use APTRepoLocal::Servicing::ChatGPT;
no warnings 'redefine';
local *APTRepoLocal::Servicing::State::new = sub { bless {}, 'FixtureState' };
local *APTRepoLocal::Servicing::CLI::_software_release_policy = sub { {} };
local *APTRepoLocal::Servicing::ChatGPT::new = sub { bless {}, 'FixtureChatGPT' };
delete $INC{'APTRepoLocal/Servicing/Postman.pm'};
unshift @INC, sub {
    die "unrelated Postman module loaded during ChatGPT configure\n"
        if $_[1] eq 'APTRepoLocal/Servicing/Postman.pm';
    return;
};
my $vendor = shift @ARGV;
@ARGV = ('configure-chatgpt');
$ENV{DPKG_ROOT} = '/fixture/offline-target';
do $vendor;
die $@ || "vendor entrypoint did not exit\n";
'''
        result = self.run_perl(source, FORKY / 'hooks/target/usr/local/libexec/apt-repo-local-vendor')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('unrelated Postman module', result.stdout + result.stderr)

    def test_chatgpt_import_failure_is_not_labelled_as_download_failure(self):
        source = r'''
use strict;
use warnings;
use APTRepoLocal::Servicing::CLI;
{
    package FixtureChatGPT;
    sub enabled { 1 }
    sub spec { {name => 'chatgpt'} }
    package FixtureState;
    sub deb_dir { '/fixture/repo' }
}
no warnings 'redefine';
local *APTRepoLocal::Servicing::ChatGPT::new = sub { bless {}, 'FixtureChatGPT' };
local *APTRepoLocal::Servicing::HTTP::new = sub { bless {}, 'FixtureHTTP' };
local *APTRepoLocal::Servicing::Repository::new = sub { bless {}, 'FixtureRepository' };
local *APTRepoLocal::Servicing::Deb::new = sub { bless {}, 'FixtureDeb' };
local *APTRepoLocal::Servicing::CLI::_software_release_policy = sub { {} };
local *APTRepoLocal::Servicing::CLI::_fetch_generic_deb = sub {
    $_[0]->{apply_failure_detail} = 'repository: managed repository import failed (exit 2)';
    return (1, 'validation');
};
my $cli = APTRepoLocal::Servicing::CLI->new();
eval { $cli->_run_bootstrap_chatgpt(bless({}, 'FixtureState'), undef, '/fixture'); };
print $@;
'''
        result = self.run_perl(source)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('ChatGPT bootstrap repository import failed:', result.stdout)
        self.assertNotIn('ChatGPT bootstrap download failed:', result.stdout)

    def test_chatgpt_forbidden_installed_dependencies_fail_postinstall(self):
        source = r'''
use strict;
use warnings;
use APTRepoLocal::Servicing::CLI;
{
    package TestDeb;
    sub new { return bless {install_calls => 0, reinstall => 0}, shift; }
    sub installed_version { return '1.0'; }
    sub installed_payload_valid { return 1; }
    sub installed_dependencies_allowed { return 0; }
    sub install {
        my ($self, undef, $reinstall) = @_;
        $self->{install_calls}++;
        $self->{reinstall} = $reinstall;
        return 1;
    }
}
{
    package TestRepository;
    sub latest {
        return {
            path => '/tmp/chatgpt-repacked.deb',
            metadata => {
                package => 'chatgpt',
                version => '1.0',
                architecture => 'amd64',
            },
        };
    }
}
{
    package TestEvent;
    sub emit { return 1; }
}
{
    package TestChatGPT;
    sub prepare_install { return 1; }
    sub finalize_install { return 1; }
    sub commit_install { return 1; }
    sub package_install { return $_[1]->(); }
    sub abort_install { return 1; }
    sub policy_valid { return 1; }
}
no warnings 'redefine';
local *APTRepoLocal::Servicing::CLI::_log = sub { return 1; };
local *APTRepoLocal::Servicing::Process::application_running = sub { return 0; };
my $deb = TestDeb->new();
my ($result, $reason) = APTRepoLocal::Servicing::CLI->new()->_apply_deb(
    $deb,
    bless({}, 'TestEvent'),
    bless({}, 'TestRepository'),
    {
        name => 'chatgpt',
        label => 'ChatGPT/Codex Desktop',
        packages => ['chatgpt'],
        executable => '/usr/lib/chatgpt/ChatGPT',
        remove_dependencies => ['*x11*', 'xwayland*', '*nvidia*'],
    },
    bless({}, 'TestChatGPT'),
    'installer',
);
print join(
    '|',
    $result,
    $reason,
    $deb->{install_calls},
    $deb->{reinstall},
), "\n";
'''
        result = self.run_perl(source)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '1|postinstall|1|1\n')


if __name__ == '__main__':
    unittest.main()
