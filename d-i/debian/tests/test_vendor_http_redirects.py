"""Per-hop download policy with explicit capture fixtures; no network access."""
from __future__ import annotations

from pathlib import Path as _IsolationPath
import sys as _isolation_sys
_isolation_sys.path.insert(0, str(_IsolationPath(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation as _require_test_isolation
_require_test_isolation()

from payload_fixture import installed_argv

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

LIB = Path(__file__).resolve().parents[1] / 'hooks/target/usr/local/lib/perl5/site_perl'
ENV = {'PATH': '/usr/bin:/bin', 'HOME': '/nonexistent', 'LC_ALL': 'C'}
DRIVER = r'''
use strict; use warnings;
use APTRepoLocal::Servicing::HTTP;
use Managed::Process;
use JSON::PP;
my ($destination, $redirect, $policy, $content_type) = @ARGV;
my @calls;
{
    no warnings 'redefine';
    *Managed::Process::capture_command = sub {
        my %request = @_;
        my @argv = @{$request{argv}};
        push @calls, \@argv;
        die "unexpected automatic redirect\n" if grep { $_ eq '--location' } @argv;
        die "missing curl configuration isolation\n" if $argv[1] ne '--disable';
        die "curl URL expansion is enabled\n" unless grep { $_ eq '--globoff' } @argv;
        die "missing curl URL credential guard\n" unless grep { $_ eq '--disallow-username-in-url' } @argv;
        die "unbounded inactivity window\n" if $request{timeout} > 1500;
        die "missing artifact progress owner\n" if ref($request{progress}) ne 'CODE';
        my ($url, $partial);
        for my $index (0 .. $#argv - 1) {
            $url = $argv[$index + 1] if $argv[$index] eq '--url';
            $partial = $argv[$index + 1] if $argv[$index] eq '--output';
        }
        open my $fh, '>', $partial or die 'fixture output';
        print {$fh} 'fixture-artifact'; close $fh;
        return {status => 0, stdout => "302\n$url\ntext/html\n$redirect"}
            if @calls == 1 || $redirect eq 'https://api.example/loop';
        my $response = "200\n$url";
        $response .= "\n$content_type\n" if defined $content_type;
        return {status => 0, stdout => $response};
    };
}
local $SIG{__WARN__} = sub { die @_ };
my %metadata;
my $ok = eval {
    APTRepoLocal::Servicing::HTTP->new->download(
        label => 'fixture', url => 'https://api.example/start', destination => $destination,
        allowed_hosts => ['api.example', 'cdn.example'],
        content_policy => $policy, response_metadata => \%metadata);
    1;
};
print encode_json({ok => $ok ? 1 : 0, error => $@, calls => \@calls, metadata => \%metadata});
'''


class VendorHTTPTests(unittest.TestCase):
    def setUp(self):
        if not shutil.which('perl'):
            self.skipTest('Perl unavailable')
        probe = subprocess.run(['/usr/bin/perl', '-MMoo', '-MMooX::StrictConstructor', '-e', '1'],
                               env=ENV, capture_output=True, timeout=5)
        if probe.returncode:
            self.skipTest('packaged Moo dependencies unavailable')
        temporary = tempfile.TemporaryDirectory(prefix='vendor-http-')
        self.addCleanup(temporary.cleanup)
        self.destination = Path(temporary.name) / 'artifact'

    def request(self, redirect, *, policy='artifact', content_type='application/octet-stream'):
        arguments = [str(self.destination), redirect, policy]
        if content_type is not None:
            arguments.append(content_type)
        result = subprocess.run(installed_argv([
            '/usr/bin/perl', '-I' + str(LIB / 'apt-repo-local'), '-I' + str(LIB / 'runtime'),
            '-e', DRIVER, '--', *arguments]),
                                env=ENV, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, '')
        return json.loads(result.stdout)

    def test_approved_redirect_contacts_only_validated_hosts_then_publishes(self):
        result = self.request('https://cdn.example/artifact')
        self.assertEqual(result['ok'], 1, result['error'])
        self.assertEqual([argv[-1] for argv in result['calls']],
                         ['https://api.example/start', 'https://cdn.example/artifact'])
        self.assertEqual(self.destination.read_bytes(), b'fixture-artifact')
        self.assertFalse(Path(str(self.destination) + '.part').exists())

    def test_disallowed_intermediate_hop_never_gets_contacted(self):
        for redirect in ('https://unapproved.example/hop', 'http://api.example/downgrade',
                         'https://user:password@cdn.example/artifact', 'https://cdn.example/bad\npath'):
            with self.subTest(redirect=redirect):
                result = self.request(redirect)
                self.assertEqual(result['ok'], 0)
                self.assertEqual(len(result['calls']), 1)
                self.assertFalse(self.destination.exists())
                self.assertFalse(Path(str(self.destination) + '.part').exists())
                self.assertNotIn('password', result['error'])

    def test_redirect_loop_has_a_bounded_request_count_and_no_publication(self):
        result = self.request('https://api.example/loop')
        self.assertEqual(result['ok'], 0)
        self.assertEqual(len(result['calls']), 9)
        self.assertFalse(self.destination.exists())
        self.assertFalse(Path(str(self.destination) + '.part').exists())

    def test_missing_and_empty_content_types_are_accepted_without_warnings(self):
        for policy in ('artifact', 'metadata'):
            for content_type in (None, ''):
                with self.subTest(policy=policy, content_type=content_type):
                    result = self.request('https://cdn.example/artifact', policy=policy,
                                          content_type=content_type)
                    self.assertEqual(result['ok'], 1, result['error'])
                    self.assertEqual(result['metadata']['content_type'], '')
                    self.assertEqual(self.destination.read_bytes(), b'fixture-artifact')
                    self.assertFalse(Path(str(self.destination) + '.part').exists())

    def test_content_type_case_and_parameters_are_normalized(self):
        for policy, content_type, expected in (
                ('artifact', 'Application/Octet-Stream; charset=binary', 'application/octet-stream'),
                ('metadata', 'Application/JSON; charset=UTF-8', 'application/json'),
                ('signature', 'Application/PGP-Signature; charset=us-ascii', 'application/pgp-signature')):
            with self.subTest(policy=policy, content_type=content_type):
                result = self.request('https://cdn.example/artifact', policy=policy,
                                      content_type=content_type)
                self.assertEqual(result['ok'], 1, result['error'])
                self.assertEqual(result['metadata']['content_type'], expected)

    def test_content_type_policy_rejections_remove_partial_downloads(self):
        for policy, content_type, reason in (
                ('artifact', 'Text/HTML; charset=UTF-8', 'non-artifact content type'),
                ('metadata', 'Text/HTML; charset=UTF-8', 'unsupported metadata content type'),
                ('signature', None, 'unsupported signature content type'),
                ('signature', '', 'unsupported signature content type')):
            with self.subTest(policy=policy, content_type=content_type):
                result = self.request('https://cdn.example/artifact', policy=policy,
                                      content_type=content_type)
                self.assertEqual(result['ok'], 0)
                self.assertIn(reason, result['error'])
                self.assertEqual(result['metadata'], {})
                self.assertFalse(self.destination.exists())
                self.assertFalse(Path(str(self.destination) + '.part').exists())

    def test_transport_diagnostics_preserve_status_without_exposing_response_urls(self):
        driver = r'''
use strict; use warnings;
use APTRepoLocal::Servicing::HTTP;
use JSON::PP;
my $http = APTRepoLocal::Servicing::HTTP->new();
my @errors;
for my $result (
    {status => 22 << 8, stdout => "404\nhttps://user:password\@cdn.example/file?token=secret\n"},
    {status => 6 << 8}, {status => 23 << 8}, {status => 60 << 8},
    {status => 124 << 8, error => 'timeout'}, {status => 9},
) {
    $result->{stderr} = "curl: raw-hostile-output https://cdn.example/?token=secret\n";
    push @errors, $http->_transport_failure($result);
}
print encode_json(\@errors);
'''
        result = subprocess.run(installed_argv([
            '/usr/bin/perl', '-I' + str(LIB / 'apt-repo-local'), '-I' + str(LIB / 'runtime'),
            '-e', driver]), env=ENV, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        errors = json.loads(result.stdout)
        self.assertIn('curl exit 22; HTTP 404', errors[0])
        self.assertIn('server name resolution failed', errors[1])
        self.assertIn('writing the downloaded artifact failed', errors[2])
        self.assertIn('TLS certificate verification failed', errors[3])
        self.assertEqual(errors[4], 'HTTP operation deadline exhausted')
        self.assertEqual(errors[5], 'curl terminated by signal 9')
        for secret in ('password', 'token=', 'secret', 'raw-hostile-output'):
            self.assertNotIn(secret, result.stdout)
