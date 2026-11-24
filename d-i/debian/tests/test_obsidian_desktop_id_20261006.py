"""Current Obsidian desktop ID across installer, update worker and launcher sync.

Debian archives are synthetic fixtures. Native package inspection is real;
APT/chroot installation, prevalidated release metadata, HTTP transport and
vendor-root ownership are explicit test doubles.
No vendor executable, maintainer script, host service or network request runs.
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

import configparser
import hashlib
import contextlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import types
import unittest
from unittest import mock

from payload_fixture import logging_text
from fixture_render import rendered_path_text
from test_installer_package_batch_20261119 import publisher_module, compiled_package_fixture_values

SEED = Path(__file__).resolve().parents[1]
TARGET = SEED / 'hooks/target'
DESKTOP_ID = 'md.obsidian.Obsidian.desktop'
DESKTOP_PATH = '/usr/share/applications/' + DESKTOP_ID
DESKTOP_TEXT = '''[Desktop Entry]
Type=Application
Name=Obsidian
Exec=/opt/Obsidian/obsidian %U
Icon=obsidian
Terminal=false
StartupWMClass=md.obsidian.Obsidian
MimeType=text/markdown;x-scheme-handler/obsidian;
Categories=Office;
'''


@unittest.skipUnless(shutil.which('dpkg-deb'), 'native dpkg-deb unavailable')
class ObsidianPackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.publisher = publisher_module()
        cls.library_temporary = tempfile.TemporaryDirectory(prefix='obsidian-perl-')
        cls.addClassCleanup(cls.library_temporary.cleanup)
        cls.library = Path(cls.library_temporary.name)
        perl_source = TARGET / 'usr/local/lib/common/perl5/site_perl'
        for name in ('apt-repo-local', 'runtime'):
            shutil.copytree(perl_source / name, cls.library / name, symlinks=True)
        values = compiled_package_fixture_values()
        for template in sorted(cls.library.rglob('*')):
            if not template.is_file() or not template.name.endswith(('.pm', '.pm.tmpl')):
                continue
            destination = template.with_name(template.name[:-5]) if template.name.endswith('.tmpl') else template
            if destination != template and destination.exists():
                raise AssertionError('ambiguous copied Perl template')
            text = rendered_path_text(logging_text(template.read_text(encoding='utf-8')))
            text = re.sub(r'__INSTALLER_(SOFTWARE_[A-Z0-9_]+)__', lambda match: values[match[1]], text)
            destination.write_text(text, encoding='utf-8')
            if destination != template:
                template.unlink()

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='obsidian-deb-layout-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.target = self.root / 'target'
        self.target.mkdir()
        self.tree = self.root / 'package'
        (self.tree / 'DEBIAN').mkdir(parents=True)
        (self.tree / 'DEBIAN').chmod(0o755)
        (self.tree / 'DEBIAN/control').write_text(
            'Package: obsidian\nVersion: 1.14.4\nArchitecture: amd64\n'
            'Maintainer: Fixture <fixture@example.invalid>\nDescription: layout fixture\n', encoding='utf-8')
        (self.tree / 'DEBIAN/control').chmod(0o644)
        for name, content, mode in (
            ('opt/Obsidian/obsidian', '#!/bin/sh\nexit 94\n', 0o755),
            ('opt/Obsidian/libffmpeg.so', 'fixture library; never loaded\n', 0o644),
            (DESKTOP_PATH.lstrip('/'), DESKTOP_TEXT, 0o644),
        ):
            path = self.tree / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding='utf-8')
            path.chmod(mode)
        self.archive = self.target / 'fixture.deb'
        self.marker = self.root / 'apt-called'
        self.software = (SEED / 'scripts/late/software.sh.tmpl').read_text(encoding='utf-8')

    def build_archive(self):
        result = subprocess.run(['dpkg-deb', '--build', '--root-owner-group', str(self.tree), str(self.archive)],
                                capture_output=True, text=True, encoding='utf-8', timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    def run_installer(self, source=None):
        source = rendered_path_text(self.software if source is None else source)
        definitions = source[:source.index('software_validate_abs_path "target root"')]
        for name in ('software_begin_deb_batch', 'software_queue_deb', 'software_prepare_obsidian_app'):
            start = source.index(name + '() {')
            definitions += '\n' + source[start:source.index('\n}\n', start) + 2]
        # The production shell writes its declarative plan. The importer owns
        # package/member inspection now; index signing and APT are explicit
        # doubles, as they were in the former per-package shell fixture.
        fixture = r'''
software_download() { :; }
target_root=$FIXTURE_ROOT
work_dir=/fixture-work
obsidian_deb=/fixture.deb
obsidian_url=https://example.invalid/fixture.deb
obsidian_version=1.14.4
obsidian_sha256=$FIXTURE_SHA256
software_begin_deb_batch desktop
software_prepare_obsidian_app
'''
        (self.target / 'fixture-work').mkdir(mode=0o700, exist_ok=True)
        script = definitions + '\n' + fixture
        result = subprocess.run(['/bin/sh', '-eu', '-c', script, 'fixture', str(self.target)],
                                text=True, encoding='utf-8', capture_output=True, timeout=15,
                                env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C',
                                     'TMPDIR': str(self.root), 'TMP': str(self.root), 'TEMP': str(self.root),
                                     'FIXTURE_ROOT': str(self.target),
                                     'FIXTURE_SHA256': hashlib.sha256(self.archive.read_bytes()).hexdigest()})
        if result.returncode:
            return result
        self.publisher.installer_plan(self.target / 'fixture-work/deb-desktop.tsv')
        try:
            self.publisher.inspect_deb(self.archive, {'amd64'})
        except self.publisher.Error as error:
            return subprocess.CompletedProcess(['fixture-import'], 1, '', str(error))
        # No maintainer script or vendor executable is run: APT is represented
        # by extraction of this test's tiny fixture only, after acceptance.
        self.marker.write_text('fixture APT\n')
        for command in (
            ['/usr/bin/dpkg-deb', '--extract', str(self.archive), str(self.target)],
            ['/usr/bin/update-desktop-database', str(self.target / 'usr/share/applications')],
        ):
            result = subprocess.run(command, capture_output=True, text=True, timeout=15,
                                    env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C',
                                         'TMPDIR': str(self.root), 'TMP': str(self.root), 'TEMP': str(self.root)})
            if result.returncode:
                return result
        return result

    def validate_worker_spec(self):
        code = r'''
use strict; use warnings;
use JSON::PP qw(encode_json);
use APTRepoLocal::Servicing::CLI;
use APTRepoLocal::Servicing::Deb;
my ($spec) = grep { $_->{name} eq 'obsidian' } APTRepoLocal::Servicing::CLI->_release_deb_specs();
defined $spec or die "missing Obsidian package specification\n";
my $deb = APTRepoLocal::Servicing::Deb->new(repository => bless({}, 'FixtureUnused'));
print encode_json($deb->validate_spec($ARGV[0], $spec)), "\n";
'''
        return subprocess.run(['perl', '-I', str(self.library / 'apt-repo-local'),
                               '-I', str(self.library / 'runtime'), '-e', code, str(self.archive)],
                              text=True, encoding='utf-8', capture_output=True, timeout=15,
                              env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'})

    def validate_download_adapter(self):
        # The unchanged GitHub metadata size floor is not the contract under
        # test. Supply prevalidated fixture metadata, then run the actual
        # adapter's digest/size handling and Debian control metadata reader.
        code = r'''
use strict; use warnings;
use JSON::PP qw(encode_json);
use Digest::SHA;
use APTRepoLocal::Servicing::Obsidian;
use APTRepoLocal::Servicing::Deb;
{
    package FixtureHTTP;
    use File::Copy qw(copy);
    sub download {
        my ($self, %args) = @_;
        if ($args{label} eq 'Obsidian release metadata') {
            open my $file, '>', $args{destination} or die "fixture metadata open: $!\n";
            print {$file} "{}\n" or die "fixture metadata write: $!\n";
            close $file or die "fixture metadata close: $!\n";
        } elsif ($args{label} eq 'Obsidian' && $args{url} eq $self->{release}{url}) {
            copy($self->{archive}, $args{destination}) or die "fixture archive copy: $!\n";
        } else {
            die "unexpected fixture HTTP request\n";
        }
    }
    package FixtureObsidian;
    use parent 'APTRepoLocal::Servicing::Obsidian';
    sub _release { return $_[0]->http()->{release}; }
}
my ($archive, $work) = @ARGV;
open my $file, '<:raw', $archive or die "fixture archive open: $!\n";
my $sha256 = Digest::SHA->new(256)->addfile($file)->hexdigest;
close $file or die "fixture archive close: $!\n";
my $http = bless {archive => $archive, release => {
    version => '1.14.4', size => -s $archive, sha256 => $sha256,
    url => 'https://github.com/obsidianmd/obsidian-releases/releases/download/v1.14.4/obsidian_1.14.4_amd64.deb',
}}, 'FixtureHTTP';
my $deb = APTRepoLocal::Servicing::Deb->new(repository => bless({}, 'FixtureUnused'));
my $result = FixtureObsidian->new(http => $http, deb => $deb)->download($work);
print encode_json($result->{metadata}), "\n";
'''
        work = self.root / 'download-work'
        work.mkdir()
        return subprocess.run(['perl', '-I', str(self.library / 'apt-repo-local'),
                               '-I', str(self.library / 'runtime'), '-e', code,
                               str(self.archive), str(work)], text=True, encoding='utf-8',
                              capture_output=True, timeout=15,
                              env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'})

    @unittest.skipUnless(shutil.which('desktop-file-validate') and shutil.which('update-desktop-database'),
                         'native desktop-file-utils unavailable')
    def test_current_desktop_id_passes_installer_and_post_install_checks(self):
        self.build_archive()
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.marker.exists())
        self.assertTrue((self.target / DESKTOP_PATH.lstrip('/')).is_file())

    def test_update_worker_spec_accepts_current_package_layout(self):
        self.build_archive()
        result = self.validate_worker_spec()
        self.assertEqual(result.returncode, 0, result.stderr)
        metadata = json.loads(result.stdout.splitlines()[-1])
        self.assertEqual(metadata, {'package': 'obsidian', 'version': '1.14.4', 'architecture': 'amd64'})

    def test_download_adapter_accepts_current_payload_after_digest_validation(self):
        self.build_archive()
        result = self.validate_download_adapter()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout.splitlines()[-1]),
                         {'package': 'obsidian', 'version': '1.14.4', 'architecture': 'amd64'})


class ObsidianLauncherTests(unittest.TestCase):
    def setUp(self):
        original_umask = os.umask(0o077)
        os.umask(original_umask)
        self.addCleanup(os.umask, original_umask)
        temporary = tempfile.TemporaryDirectory(prefix='obsidian-launcher-layout-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.vendor = self.root / 'vendor'
        self.local = self.root / 'local'
        self.home = self.root / 'home'
        for directory in (self.vendor, self.local, self.home):
            directory.mkdir()
        path = TARGET / 'usr/local/bin/labwc-sync-application-launchers.tmpl'
        self.sync = types.ModuleType('obsidian_launcher_fixture')
        self.sync.__file__ = str(path)
        source = path.read_text(encoding='utf-8').replace(
            '__INSTALLER_LABWC_MANAGED_APP_DEFAULT_EXEC__', '/usr/local/bin/labwc-app auto')
        exec(compile(source, str(path), 'exec'), self.sync.__dict__)
        self.sync.SYSTEM_APPLICATION_DIR = str(self.vendor)
        self.sync.LOCAL_APPLICATION_DIR = str(self.local)
        self.config = next(value for value in self.sync.APP_CONFIG if value['action_app'] == 'obsidian')

    def test_current_id_is_preferred_and_legacy_vendor_entry_is_discoverable(self):
        (self.vendor / 'obsidian.desktop').write_text(DESKTOP_TEXT, encoding='utf-8')
        self.assertEqual(self.sync.find_desktop_file(self.config['desktop_names'])[0], 'obsidian.desktop')
        (self.vendor / DESKTOP_ID).write_text(DESKTOP_TEXT, encoding='utf-8')
        self.assertEqual(self.sync.find_desktop_file(self.config['desktop_names'])[0], DESKTOP_ID)

    def test_sync_preserves_native_id_mime_and_window_class_under_managed_wrapper(self):
        (self.vendor / DESKTOP_ID).write_text(DESKTOP_TEXT, encoding='utf-8')
        uid, gid = os.getuid(), os.getgid()
        with mock.patch.object(self.sync, 'APP_CONFIG', (self.config,)), \
             mock.patch.object(self.sync, 'validate_account_context', return_value=(uid, gid)), \
             mock.patch.object(self.sync, 'load_acceleration_availability', return_value={'intel': True, 'nvidia': True}), \
             mock.patch.object(self.sync, 'read_system_desktop_text',
                               side_effect=lambda path: self.sync.read_regular_text(path, {uid})), \
             mock.patch.object(self.sync, 'remove_unmanaged_tuta_launchers', return_value=0), \
             mock.patch.object(self.sync, 'synchronize_bitwarden_autostart', return_value=False), \
             mock.patch.object(self.sync.sys, 'argv', ['sync', 'fixture', str(self.home)]), \
             mock.patch.dict(os.environ, {'XDG_DATA_HOME': str(self.home / '.local/share')}), \
             contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.sync.main(), 0)
        destination = self.home / '.local/share/applications' / DESKTOP_ID
        self.assertTrue(destination.is_file())
        self.assertEqual(destination.stat().st_mode & 0o777, 0o600)
        settings = configparser.ConfigParser(interpolation=None)
        settings.optionxform = str
        settings.read(destination, encoding='utf-8')
        entry = settings['Desktop Entry']
        self.assertEqual(entry['Exec'], '/usr/local/bin/labwc-app auto obsidian %U')
        self.assertEqual(entry['StartupWMClass'], 'md.obsidian.Obsidian')
        self.assertEqual(entry['MimeType'], 'text/markdown;x-scheme-handler/obsidian;')
        self.assertEqual(entry['Icon'], 'obsidian')
        self.assertEqual(settings['Desktop Action IntelAccelerated']['Exec'],
                         '/usr/local/bin/labwc-app intel obsidian %U')
        self.assertFalse((destination.parent / 'obsidian.desktop').exists())


if __name__ == '__main__':
    unittest.main()
