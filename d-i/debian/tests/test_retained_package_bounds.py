#!/usr/bin/env python3
"""Offline retained-package boundary regressions; never install a package.

The Perl harness evaluates the exact production method bodies with core Perl
imports and explicit fixture objects. It deliberately does not replace Moo or
claim constructor/module-load coverage. This keeps the archive and filesystem
checks executable even on a publishing host without the target's Moo packages.
Full module loading requires the managed external-software tests inside the
reviewed guest. The Python publisher and dpkg-deb run only behind that same gate.
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

from payload_fixture import copyfile as payload_copyfile, installed_argv as payload_installed_argv, source_is_file as payload_source_is_file, source_stat as payload_source_stat
from payload_fixture import read_text as payload_read_text

import atexit
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import re
import resource
import shutil
import stat
import subprocess
import tarfile
import tempfile
import unittest
from functools import lru_cache
from fixture_render import rendered_path_text
from test_installer_package_batch_20261119 import compiled_package_fixture_values, publisher_module

FORKY = Path(__file__).resolve().parents[1]
PERL_LIB = FORKY / 'hooks/target/usr/local/lib/common/perl5/site_perl/apt-repo-local'
SERVICING = PERL_LIB / 'APTRepoLocal/Servicing'
MAX_DEB = int(compiled_package_fixture_values()['SOFTWARE_APT_REPO_LOCAL_DEB_MAXIMUM_BYTES'])
OLD_BOUND = 1 << 29


@lru_cache(maxsize=1)
def fixture_library() -> Path:
    """Materialize only core-based imports inside this already-guarded guest."""
    temporary = tempfile.TemporaryDirectory(prefix='retained-perl-library-', dir='/workspace')
    atexit.register(temporary.cleanup)
    root = Path(temporary.name)
    values = compiled_package_fixture_values()
    sources = {
        'APTRepoLocal/Servicing/ArtifactLimits.pm': SERVICING / 'ArtifactLimits.pm.tmpl',
        'Managed/Process.pm': PERL_LIB.parent / 'runtime/Managed/Process.pm',
    }
    for relative, source in sources.items():
        text = rendered_path_text(source.read_text())
        text = re.sub(r'__INSTALLER_(SOFTWARE_[A-Z0-9_]+)__',
                      lambda match: values[match[1]], text)
        if '__INSTALLER_' in text:
            raise ValueError('unrendered retained-package fixture import')
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
    return root


def method(filename: str, name: str) -> str:
    """Take a complete top-level method verbatim, without rewriting its body."""
    text = rendered_path_text(payload_read_text(SERVICING / filename))
    match = re.search(rf'^sub {re.escape(name)}\s*\{{.*?(?=^sub [A-Za-z_]|^1;\s*$)',
                      text, re.M | re.S)
    if match is None:
        raise AssertionError(f'production method missing: {filename}:{name}')
    return match.group(0)


def perl_program() -> str:
    # Only the catalogue transport and Moo constructors are fixture boundaries.
    # The validation, path policy, hashing, spec and selection methods are the
    # actual production source. No command, file-size or dpkg result is faked.
    common = '''use strict; use warnings;
use Fcntl qw(:DEFAULT O_NOFOLLOW O_NONBLOCK S_IFMT S_IFREG);
use Errno qw(EINTR); use Digest::SHA; use JSON::PP;
use APTRepoLocal::Servicing::ArtifactLimits qw(MAX_DEB_BYTES);
use Managed::Process qw(capture_command);
'''
    constants = '\n'.join(re.findall(r'^use constant\s+.*?;',
                                     rendered_path_text(payload_read_text(SERVICING / 'ChatGPT.pm')), re.M | re.S))
    return ('package APTRepoLocal::Servicing::Atomic;\n' + common
            + method('Atomic.pm', 'assert_absolute_path')
            + method('Atomic.pm', 'read_limited') + method('Atomic.pm', 'sha256_file')
            + 'package APTRepoLocal::Servicing::ChatGPT;\n' + common + constants + '\n'
            + method('ChatGPT.pm', 'spec')
            + 'package APTRepoLocal::Servicing::Deb;\n' + common
            + ''.join(method('Deb.pm', name) for name in (
                '_capture', '_capture_limited', '_capture_quiet', 'control', 'control_fields',
                '_sandbox_presence', 'installed_version'))
            + method('Deb.pm', 'validate') + method('Deb.pm', 'validate_spec')
            + 'package APTRepoLocal::Servicing::Repository;\n' + common
            + "use constant HELPER => '/fixture/catalogue-transport';\n"
            + 'sub directory { return $_[0]->{directory}; }\n'
            + 'sub _capture { return $_[0]->{catalogue}; }\n'
            + method('Repository.pm', 'latest')
            + '''package main;
use strict; use warnings; use JSON::PP;
my ($action, $path, $extra) = @ARGV;
my $deb = bless {}, 'APTRepoLocal::Servicing::Deb';
my $spec = APTRepoLocal::Servicing::ChatGPT->spec();
my $result;
if ($action eq 'limit') {
    $result = APTRepoLocal::Servicing::ArtifactLimits::MAX_DEB_BYTES();
} elsif ($action eq 'spec-limit') {
    $result = $spec->{maximum};
} elsif ($action eq 'path') {
    $result = APTRepoLocal::Servicing::Atomic->assert_absolute_path('fixture', $path);
} elsif ($action eq 'digest') {
    my ($size, $sha256) = APTRepoLocal::Servicing::Atomic->sha256_file($path, $extra);
    $result = { size => $size, sha256 => $sha256 };
} elsif ($action eq 'validate') {
    $result = $deb->validate_spec($path, $spec, "$spec->{label} retained archive");
} elsif ($action eq 'changed') {
    my $original = \\&APTRepoLocal::Servicing::Deb::control_fields;
    no warnings 'redefine';
    local *APTRepoLocal::Servicing::Deb::control_fields = sub {
        my $value = $original->(@_);
        open my $out, '>>', $_[1] or die "fixture append: $!";
        print {$out} "changed"; close $out or die "fixture close: $!";
        return $value;
    };
    $result = $deb->validate_spec($path, $spec);
} elsif ($action eq 'inspection') {
    my $fixture = decode_json($extra);
    my (@commands, @records);
    my $listing_index = 0;
    no warnings 'redefine';
    local *APTRepoLocal::Servicing::Deb::_capture = sub {
        my ($self, @argv) = @_;
        push @commands, { kind => 'control', argv => \\@argv };
        return 'X' x 1_048_577 if $fixture->{oversize_control};
        return $fixture->{control};
    };
    local *APTRepoLocal::Servicing::Deb::_capture_limited = sub {
        my ($self, $limit, @argv) = @_;
        push @commands, { kind => 'listing', limit => $limit, argv => \\@argv };
        return $fixture->{listings}->[$listing_index++];
    };
    local *APTRepoLocal::Servicing::Deb::_capture_quiet = sub {
        my ($self, @argv) = @_;
        push @commands, { kind => 'query', argv => \\@argv };
        return $fixture->{query};
    };
    for (1 .. ($fixture->{runs} // 1)) {
        my $value = eval {
            my $operation = $fixture->{operation} // 'validate';
            if ($operation eq 'validate') {
                $deb->validate_spec($path, $fixture->{spec});
            } elsif ($operation eq 'version') {
                $deb->installed_version('fixture');
            } else {
                die "unknown inspection fixture operation";
            }
        };
        push @records, { value => $value, error => "$@" };
    }
    $result = { records => \\@records, commands => \\@commands };
} elsif ($action eq 'latest') {
    my $repository = bless { directory => $path, catalogue => $extra },
        'APTRepoLocal::Servicing::Repository';
    $result = $repository->latest($deb, $spec);
} elsif ($action eq 'latest-bitwarden') {
    my $repository = bless { directory => $path, catalogue => $extra },
        'APTRepoLocal::Servicing::Repository';
    $spec = { %$spec, name => 'bitwarden', packages => ['bitwarden'], label => 'Bitwarden' };
    $result = $repository->latest($deb, $spec);
} else {
    die "unknown fixture action\\n";
}
print 'RESULT:' . JSON::PP->new->canonical->encode($result) . "\\n";
''')


def ar_header(name: str, size: int) -> bytes:
    return (f'{name + "/":<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{size:<10}`\n').encode('ascii')


def sparse_deb(path: Path, size: int = 8192, *, package: str = 'chatgpt',
               version: str = '1.0+localrepo1', architecture: str = 'amd64') -> None:
    """Create a real ar/control/data Debian archive with a sparse zero payload."""
    control = (f'Package: {package}\nVersion: {version}\nArchitecture: {architecture}\n'
               'Maintainer: Fixture <fixture@localhost>\nDescription: Offline boundary fixture\n').encode()
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode='w', format=tarfile.USTAR_FORMAT) as archive:
        member = tarfile.TarInfo('./control')
        member.mode, member.size = 0o644, len(control)
        archive.addfile(member, io.BytesIO(control))
    control_archive = gzip.compress(stream.getvalue(), mtime=0)
    with path.open('wb') as output:
        output.write(b'!<arch>\n')
        for name, data in (('debian-binary', b'2.0\n'), ('control.tar.gz', control_archive)):
            output.write(ar_header(name, len(data)))
            output.write(data)
            if len(data) % 2:
                output.write(b'\n')
        data_size = size - output.tell() - 60
        if data_size < 2048 or data_size % 2:
            raise ValueError('fixture size must leave an even, complete data archive')
        output.write(ar_header('data.tar', data_size))
        member = tarfile.TarInfo('./usr/share/fixture/padding')
        member.mode = 0o644
        member.size = ((data_size - 1536) // 512) * 512
        output.write(member.tobuf(format=tarfile.USTAR_FORMAT))
        output.seek(member.size, os.SEEK_CUR)
        output.write(b'\0' * (data_size - 512 - member.size))
    path.chmod(0o600)
    if payload_source_stat(path).st_size != size:
        raise AssertionError('fixture size mismatch')


def run_perl(action: str, path: object = '', extra: object = '', *, memory_limit: bool = False):
    def limit_memory():
        resource.setrlimit(resource.RLIMIT_AS, (128 << 20, 128 << 20))
    library = fixture_library()
    environment = {'LC_ALL': 'C.UTF-8', 'PATH': '/usr/bin:/bin', 'PERL5OPT': '',
                   'HOME': str(library), 'TMPDIR': str(library), 'TMP': str(library), 'TEMP': str(library)}
    return subprocess.run(payload_installed_argv(['/usr/bin/perl', '-f', '-I', str(library), '-e', perl_program(),
                           action, str(path), str(extra)]), text=True, capture_output=True,
                          env=environment, timeout=45,
                          preexec_fn=limit_memory if memory_limit else None)


def result_value(result):
    if result.returncode:
        raise AssertionError(result.stderr)
    records = [line.removeprefix('RESULT:') for line in result.stdout.splitlines()
               if line.startswith('RESULT:')]
    if len(records) != 1:
        raise AssertionError(result.stdout)
    return json.loads(records[0])


class RetainedPackageBoundsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='retained-package-bounds-', dir='/workspace')
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.directory = Path(cls.temporary.name)
        cls.small = cls.directory / 'chatgpt-small.deb'
        cls.large = cls.directory / 'chatgpt-large.deb'
        cls.at_limit = cls.directory / 'chatgpt-at-limit.deb'
        sparse_deb(cls.small)
        sparse_deb(cls.large, OLD_BOUND + 4096)
        sparse_deb(cls.at_limit, MAX_DEB)
        cls.publisher = publisher_module().__dict__

    def assert_rejected(self, path, reason: str, *, action='validate', extra=''):
        result = run_perl(action, path, extra)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(reason, result.stderr)
        return result

    def test_publisher_and_retained_archive_share_the_configured_package_ceiling(self):
        self.assertEqual(result_value(run_perl('limit')), MAX_DEB)
        self.assertEqual(self.publisher['MAX_DEB'], MAX_DEB)

    def test_chatgpt_transport_has_no_byte_ceiling(self):
        self.assertIsNone(result_value(run_perl('spec-limit')))

    def test_limit_module_is_in_the_installer_staging_inventory(self):
        script = payload_read_text(FORKY / 'scripts/late/software.sh')
        inventory = re.search(r"software_perl_modules\(\) \{\s*cat <<'EOF'\n(.*?)\nEOF", script, re.S)
        self.assertIsNotNone(inventory)
        entries = inventory[1].splitlines()
        self.assertEqual(entries.count('APTRepoLocal/Servicing/ArtifactLimits.pm'), 1)
        for entry in entries:
            self.assertTrue(payload_source_is_file(PERL_LIB / entry), entry)

    def test_small_valid_debian_archive_still_passes(self):
        self.assertEqual(result_value(run_perl('validate', self.small)),
                         {'package': 'chatgpt', 'version': '1.0+localrepo1', 'architecture': 'amd64'})

    def test_real_archive_above_old_512_mib_limit_passes_both_readers(self):
        fields = self.publisher['inspect_deb'](self.large, {'amd64'})
        self.assertEqual(fields['Package'], 'chatgpt')
        self.assertEqual(result_value(run_perl('validate', self.large))['version'], fields['Version'])
        self.assertGreater(payload_source_stat(self.large).st_size, OLD_BOUND)

    def test_real_archive_exactly_at_the_configured_limit_is_accepted(self):
        self.assertEqual(result_value(run_perl('validate', self.at_limit))['package'], 'chatgpt')
        self.assertEqual(payload_source_stat(self.at_limit).st_size, MAX_DEB)

    def test_one_byte_over_limit_reports_actual_size_path_and_ceiling(self):
        path = self.directory / 'oversized.deb'
        with path.open('wb') as output:
            output.write(b'!<arch>\n')
            output.truncate(MAX_DEB + 1)
        result = self.assert_rejected(path, 'not a bounded regular file')
        for text in (str(path), f'size={MAX_DEB + 1}', f'permitted=8..{MAX_DEB}'):
            self.assertIn(text, result.stderr)
        with self.assertRaises(self.publisher['Error']):
            fd = self.publisher['checked_file'](path)
            os.close(fd)

    def test_publisher_accepts_exactly_the_configured_limit_and_rejects_one_byte_more(self):
        path = self.directory / 'publisher-boundary.deb'
        sparse_deb(path, MAX_DEB)
        os.chmod(path, 0o600)
        fd = self.publisher['checked_file'](path)
        os.close(fd)
        with path.open('ab') as stream:
            stream.write(b'x')
        with self.assertRaises(self.publisher['Error']):
            self.publisher['checked_file'](path)
        path.unlink()

    def test_retained_archive_above_the_shared_package_budget_is_rejected(self):
        path = self.directory / 'retained-expanded.deb'
        sparse_deb(path, MAX_DEB + 4096)
        self.assert_rejected(path, 'not a bounded regular file')
        with self.assertRaises(self.publisher['Error']):
            self.publisher['checked_file'](path, private=False)
        path.unlink()

    def test_empty_and_short_archives_are_rejected(self):
        for size in range(8):
            with self.subTest(size=size):
                path = self.directory / f'truncated-{size}.deb'
                path.write_bytes(b'!<arch>\n'[:size])
                self.assert_rejected(path, f'size={size}')

    def test_missing_file_is_distinguished_from_excess_size(self):
        self.assert_rejected(self.directory / 'missing.deb', 'cannot be inspected')

    def test_regular_and_dangling_symlinks_are_rejected(self):
        for name, target in (('linked.deb', self.small), ('dangling.deb', self.directory / 'absent')):
            with self.subTest(name=name):
                path = self.directory / name
                path.symlink_to(target)
                self.assert_rejected(path, 'symlinks and special files are forbidden')

    def test_directory_and_fifo_are_rejected_without_blocking(self):
        path = self.directory / 'fifo.deb'
        os.mkfifo(path, 0o600)
        for candidate in (self.directory, path):
            self.assert_rejected(candidate, 'symlinks and special files are forbidden')

    def test_non_debian_header_is_rejected(self):
        path = self.directory / 'html.deb'
        path.write_bytes(b'<html>not a Debian archive</html>')
        self.assert_rejected(path, 'not a valid Debian package')

    def test_framing_alone_does_not_bypass_dpkg_validation(self):
        path = self.directory / 'magic-only.deb'
        path.write_bytes(b'!<arch>\n')
        self.assert_rejected(path, 'is not a valid Debian package')

    def test_wrong_identity_and_architecture_are_still_rejected(self):
        for name, architecture, reason in (
                ('unapproved', 'amd64', 'package name is unapproved'),
                ('chatgpt', 'arm64', 'package architecture is not amd64')):
            with self.subTest(name=name, architecture=architecture):
                path = self.directory / f'{name}-{architecture}.deb'
                sparse_deb(path, package=name, architecture=architecture)
                self.assert_rejected(path, reason)

    def test_modification_during_metadata_validation_is_rejected(self):
        path = self.directory / 'changing.deb'
        payload_copyfile(self.small, path)
        self.assert_rejected(path, 'package changed during validation', action='changed')

    def test_valid_tilde_version_filename_is_accepted(self):
        path = self.directory / 'chatgpt_1.0~rc1+localrepo1_amd64.deb'
        sparse_deb(path, version='1.0~rc1+localrepo1')
        self.assertEqual(result_value(run_perl('validate', path))['version'], '1.0~rc1+localrepo1')

    def test_unsafe_path_characters_and_traversal_remain_rejected(self):
        for path in ('relative.deb', '/tmp/../file.deb', '/tmp/./file.deb',
                     '/tmp/file;touch.deb', '/tmp/file\n.deb', '/tmp/file with space.deb'):
            with self.subTest(path=path):
                result = run_perl('path', path)
                self.assertNotEqual(result.returncode, 0)

    def test_streaming_digest_accepts_large_retained_file_under_memory_cap(self):
        with self.large.open('rb') as source:
            expected = hashlib.file_digest(source, 'sha256').hexdigest()
        self.assertEqual(result_value(run_perl('digest', self.large, MAX_DEB, memory_limit=True)),
                         {'size': payload_source_stat(self.large).st_size, 'sha256': expected})

    def test_digest_keeps_explicit_smaller_transport_limits(self):
        self.assert_rejected(self.large, 'not a bounded regular file', action='digest', extra=OLD_BOUND)

    def test_digest_rejects_unbounded_or_invalid_limits(self):
        for limit in (0, -1, MAX_DEB + 1, 'unlimited', '1.5', '1e9', '01'):
            with self.subTest(limit=limit):
                self.assert_rejected(self.small, 'invalid digest input limit', action='digest', extra=limit)

    def test_digest_does_not_follow_symlinks(self):
        path = self.directory / 'digest-link.deb'
        path.symlink_to(self.small)
        self.assert_rejected(path, 'not a bounded regular file', action='digest', extra=MAX_DEB)

    def test_latest_reads_a_large_retained_catalogue_candidate(self):
        root = self.directory / 'catalogue'
        pool = root / 'pool/chatgpt' / ('a' * 64)
        pool.mkdir(parents=True)
        path = pool / 'chatgpt_1.0+localrepo1_amd64.deb'
        sparse_deb(path, OLD_BOUND + 4096)
        # Only the list transport is fixture-provided; selection and validation
        # use the production methods and actual on-disk Debian archive.
        catalogue = json.dumps({'packages': {'chatgpt:amd64': {
            'package': 'chatgpt', 'filename': str(path.relative_to(root))}}})
        record = result_value(run_perl('latest', root, catalogue))
        self.assertEqual(record['path'], str(path))
        self.assertEqual(record['metadata']['package'], 'chatgpt')

    def test_bitwarden_retained_candidate_uses_package_metadata_without_rehashing(self):
        root = self.directory / 'bitwarden-catalogue'
        pool = root / 'pool/bitwarden' / ('b' * 64)
        pool.mkdir(parents=True)
        path = pool / 'bitwarden_1.0+localrepo1_amd64.deb'
        sparse_deb(path, OLD_BOUND + 4096, package='bitwarden')
        catalogue = json.dumps({'packages': {'bitwarden:amd64': {
            'package': 'bitwarden', 'filename': str(path.relative_to(root))}}})
        record = result_value(run_perl('latest-bitwarden', root, catalogue))
        self.assertEqual(record['metadata']['package'], 'bitwarden')
        self.assertNotIn('vendor_sha256', record)


class ServicingInspectionTests(unittest.TestCase):
    """Bounded command doubles exercise the production parser/validator bodies."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='servicing-inspection-', dir='/workspace')
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name) / 'fixture.deb'
        self.path.write_bytes(b'!<arch>\n')
        self.path.chmod(0o600)
        self.control = ('Description: fixture metadata\n continued description\nArchitecture: amd64\n'
                        'Version: 1.0\nPackage: fixture\n')
        self.spec = {
            'label': 'Fixture', 'packages': ['fixture'], 'executable': '/usr/bin/fixture',
            'desktop': '/usr/share/applications/fixture.desktop', 'library': '/opt/Fixture/lib.so',
            'required_paths': ['/opt/Fixture/resources/app.asar'],
            'required_executables': ['/opt/Fixture/helper'],
            'sandbox': '/opt/Fixture/chrome-sandbox', 'sandbox_presence': 'required',
        }
        members = (
            ('-rwxr-xr-x', '/usr/bin/fixture'),
            ('-rw-r--r--', '/usr/share/applications/fixture.desktop'),
            ('-rw-r--r--', '/opt/Fixture/lib.so'),
            ('-rw-r--r--', '/opt/Fixture/resources/app.asar'),
            ('lrwxrwxrwx', '/opt/Fixture/helper -> helper-runtime'),
            ('-rwsr-xr-x', '/opt/Fixture/chrome-sandbox'),
        )
        self.listing = ''.join(f'{mode} root/root 1 2026-11-19 00:00 .{name}\n'
                               for mode, name in members)

    def inspect(self, **changes):
        fixture = {'control': self.control, 'spec': self.spec, 'listings': [self.listing]}
        fixture.update(changes)
        return result_value(run_perl('inspection', self.path, json.dumps(fixture)))

    def test_control_metadata_is_read_without_a_payload_listing(self):
        result = self.inspect()
        self.assertEqual(result['records'], [{'value': {
            'package': 'fixture', 'version': '1.0', 'architecture': 'amd64'}, 'error': ''}])
        self.assertEqual([command['kind'] for command in result['commands']], ['control'])
        control, = result['commands']
        self.assertEqual(control['argv'][1:], ['-f', str(self.path)])

    def test_missing_duplicate_malformed_and_unbounded_control_are_rejected(self):
        cases = (
            {'control': self.control.replace('Version: 1.0\n', '')},
            {'control': self.control + 'pAcKaGe: fixture\n'},
            {'control': ' orphaned continuation\n' + self.control},
            {'control': self.control + '\0'},
            {'control': self.control.replace('Package: fixture', 'Package fixture')},
            {'control': None},
            {'oversize_control': True},
        )
        for changes in cases:
            with self.subTest(changes=changes):
                self.assertTrue(self.inspect(**changes)['records'][0]['error'])

    def test_installed_status_and_version_come_from_one_query(self):
        result = self.inspect(operation='version', query='install ok installed\t1.0')
        self.assertEqual(result['records'], [{'value': '1.0', 'error': ''}])
        self.assertEqual(len(result['commands']), 1)
        self.assertEqual(result['commands'][0]['kind'], 'query')
        self.assertEqual(result['commands'][0]['argv'][2], '-f=${Status}\\t${Version}')

    def test_partial_or_ambiguous_installed_state_cannot_supply_a_version(self):
        for query in (None, 'install ok unpacked\t1.0', 'install ok installed',
                      'install ok installed\t1.0\ninstall ok installed\t2.0'):
            with self.subTest(query=query):
                result = self.inspect(operation='version', query=query)
                self.assertIsNone(result['records'][0]['value'])
                self.assertEqual(len(result['commands']), 1)


if __name__ == '__main__':
    unittest.main()
