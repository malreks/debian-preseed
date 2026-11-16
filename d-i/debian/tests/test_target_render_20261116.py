"""Minimal-Perl batch regressions; execute only in the reviewed private image."""
from __future__ import annotations

from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation
require_test_isolation()

import hashlib
import json
import os
import shlex
import shutil
import subprocess
import tempfile
import unittest


RENDERER = Path(__file__).resolve().parents[1] / 'scripts/common/render.pl'
SELECTORS = {'scripts': 'scripts', 'target': 'assets', 'installer': 'hooks/installer',
             'late': 'scripts/late', 'desktop': 'scripts/desktop', 'firstboot': 'scripts/firstboot',
             'appearance-python': 'assets/python/labwc_appearance',
             'appearance-registry': 'assets/appearance/fields.json.tmpl',
             'perl-assets': 'catalog/perl.tsv'}


class PreparedBootstrapTests(unittest.TestCase):
    """Adoption starts from bootstrap.sh alone, as the supervised late shell does."""

    def test_fresh_shell_loads_lifecycle_before_prepared_payload_checks(self):
        common = RENDERER.parent
        with tempfile.TemporaryDirectory(prefix='prepared-bootstrap-') as temporary:
            root = Path(temporary)
            runtime = root / 'runtime'
            stage = root / 'target/stage'
            (runtime / 'bootstrap').mkdir(parents=True)
            (stage / 'inputs').mkdir(parents=True)
            (stage / 'source').mkdir()
            stage.chmod(0o700)
            marker = runtime / 'ready'
            for path in (marker, stage / 'identity', runtime / 'bootstrap/payload.ready',
                         stage / 'receipt.json', stage / 'inputs/published-assets.tsv'):
                path.write_text('fixture\n', encoding='ascii')
                path.chmod(0o600)
            shells = [['/bin/dash']]
            if shutil.which('busybox'):
                shells.append([shutil.which('busybox'), 'sh'])
            env = {'PATH': '/usr/bin:/bin', 'HOME': str(root), 'TMPDIR': str(root),
                   'TMP': str(root), 'TEMP': str(root), 'LC_ALL': 'C',
                   'INSTALLER_SOURCE_LIBRARY': str(common / 'source.sh'),
                   'INSTALLER_RUNTIME_DIR': str(runtime), 'DIR_INSTALLER_RUNTIME': str(runtime),
                   'TARGET_ROOT': str(root / 'target'), 'DIR_INSTALLER_TARGET_STAGE': '/stage',
                   'FILE_INSTALLER_TARGET_RENDER_READY': str(marker)}
            code = '\n'.join((
                '. ' + shlex.quote(str(common / 'bootstrap.sh')),
                'if command -v installer_lifecycle_parent_safe >/dev/null 2>&1; then exit 98; fi',
                'bootstrap_load_prepared_source /fixture-seed',
                'command -v installer_lifecycle_parent_safe >/dev/null',
                '[ "$BOOTSTRAP_PREPARED_SOURCE_ROOT" = "$TARGET_ROOT/stage/source" ]',
                '[ "$BOOTSTRAP_PREPARED_SEED_BASE" = /fixture-seed ]'))
            for shell in shells:
                with self.subTest(shell=shell):
                    result = subprocess.run([*shell, '-eu', '-c', code], env=env,
                                            capture_output=True, timeout=15, check=False)
                    self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))


class BatchRenderTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='target-render-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / 'work'
        self.root.mkdir(mode=0o700)
        self.source = self.root / 'source'
        self.source.mkdir()
        (self.root / 'inputs').mkdir()
        self.destination = self.root.parent / 'published'
        self.env = {'PATH': '/usr/bin:/bin', 'HOME': str(self.root),
                    'TMPDIR': str(self.root), 'TMP': str(self.root), 'TEMP': str(self.root), 'LC_ALL': 'C'}

    def candidate(self, assets, paths=None, logging=None, themes=None):
        assets = dict(assets)
        assets['catalog/perl.tsv'] = b'assets/Fixture.pm\tfixture/Fixture.pm\tcommon\n'
        assets['assets/Fixture.pm'] = b'package Fixture; 1;\n'
        rows = ['format=3\n']
        for name, data in assets.items():
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            rows.append(f'{len(data)}\t{hashlib.sha256(data).hexdigest()}\t{name}\n')
        (self.root / 'inputs/payload.manifest').write_text(''.join(rows), encoding='ascii')
        for name, values in (('paths', paths), ('logging', logging), ('themes', themes), ('perl', {})):
            (self.root / ('inputs/' + name + '.map')).write_bytes(
                b''.join(key + b'=' + value + b'\n' for key, value in (values or {}).items()))

    def run_render(self, *, succeeds=True):
        argv = ['/usr/bin/perl', '-f', str(RENDERER), str(self.root)]
        options = dict(SELECTORS, **{'perl-root': str(self.destination), 'family': 'desktop',
                                   'snapshots': 'false', 'sha256': '/usr/bin/sha256sum'})
        for key, value in options.items():
            argv += ['--' + key, value]
        result = subprocess.run(argv, capture_output=True, env=self.env, timeout=30, check=False)
        self.assertEqual(result.returncode == 0, succeeds, result.stderr.decode(errors='replace'))
        if succeeds:
            return json.loads((self.root / 'receipt.json').read_text(encoding='ascii'))
        self.assertFalse((self.root / 'receipt.json').exists())
        self.assertTrue(self.root.is_dir())
        return result

    def test_paths_logging_theme_and_literal_replacements_preserve_typed_inputs(self):
        self.candidate({'assets/config.tmpl': b'__INSTALLER_PATH_A____INSTALLER_PATH_B__\n'
                        b'__INSTALLER_LOG_ROOT__ __THEME_COLOR__ __INSTALLER_ACCOUNT_USERNAME__\n'},
                       {b'PATH_A': b'/a&|\\b', b'PATH_B': b'/bin'},
                       {b'LOG_ROOT': b'/logs'}, {b'COLOR': b'#123456'})
        report = self.run_render()
        self.assertEqual((self.source / 'assets/config.tmpl').read_bytes(),
                         b'/a&|\\b/bin\n/logs #123456 __INSTALLER_ACCOUNT_USERNAME__\n')
        self.assertEqual(report['rendered_files'], 1)
        self.assertEqual((self.destination / 'fixture/Fixture.pm').stat().st_mode & 0o777, 0o644)

    def test_installer_dkms_helpers_are_rendered_in_the_same_batch(self):
        self.candidate({'hooks/installer/pre-pkgsel.d/dkms.sh': b'__INSTALLER_PATH_A__/dkms\n'},
                       {b'PATH_A': b'/etc'})
        self.run_render()
        self.assertEqual((self.source / 'hooks/installer/pre-pkgsel.d/dkms.sh').read_bytes(), b'/etc/dkms\n')

    def test_unknown_path_retains_candidate_without_receipt(self):
        self.candidate({'scripts/helper': b'__INSTALLER_PATH_UNKNOWN__'})
        self.run_render(succeeds=False)

    def test_modified_copy_is_rejected_against_authenticated_manifest(self):
        self.candidate({'assets/data': b'original'})
        (self.source / 'assets/data').write_bytes(b'replaced')
        self.run_render(succeeds=False)

    def test_missing_copy_is_rejected(self):
        self.candidate({'assets/data': b'original'})
        (self.source / 'assets/data').unlink()
        self.run_render(succeeds=False)

    def test_indirect_copy_is_rejected(self):
        self.candidate({'scripts/helper': b'fixture'})
        helper = self.source / 'scripts/helper'
        helper.unlink()
        helper.symlink_to(self.root / 'unpublished')
        self.run_render(succeeds=False)

    def test_hardlinked_copy_is_rejected(self):
        self.candidate({'scripts/helper': b'fixture'})
        os.link(self.source / 'scripts/helper', self.source / 'scripts/other')
        self.run_render(succeeds=False)

    def test_manifest_budget_is_rejected_before_publication(self):
        self.candidate({'assets/data': b'12345'})
        manifest = self.root / 'inputs/payload.manifest'
        data = manifest.read_text(encoding='ascii').replace('5\t', '268435457\t', 1)
        manifest.write_text(data, encoding='ascii')
        self.run_render(succeeds=False)

    def test_registry_defaults_preserve_mapping_metadata_and_editor_grammar(self):
        self.candidate({'assets/appearance/fields.json.tmpl':
                        b'"key": "COLOR",\n"default": "__THEME_COLOR__",\n"tokens": ["__THEME_COLOR__"]\n',
                        'assets/python/labwc_appearance/fields.py': b'TOKEN = "__THEME_COLOR__"\n',
                        'scripts/desktop/components/appearance.sh': b'prefix="__THEME_"\n'},
                       themes={b'COLOR': b'#abcdef'})
        self.run_render()
        registry = (self.source / 'assets/appearance/fields.json.tmpl').read_bytes()
        self.assertIn(b'"default": "#abcdef"', registry)
        self.assertIn(b'"tokens": ["__THEME_COLOR__"]', registry)
        self.assertEqual((self.source / 'assets/python/labwc_appearance/fields.py').read_bytes(),
                         b'TOKEN = "__THEME_COLOR__"\n')

    def test_binary_files_are_byte_identical(self):
        self.candidate({'assets/icon.png': b'\x89PNG\0__THEME_COLOR__'})
        self.run_render()
        self.assertEqual((self.source / 'assets/icon.png').read_bytes(), b'\x89PNG\0__THEME_COLOR__')

    def test_cleanup_retains_incomplete_candidate(self):
        self.candidate({'assets/data': b'fixture'})
        result = subprocess.run(['/usr/bin/perl', '-f', str(RENDERER), str(self.root), '--cleanup'],
                                capture_output=True, env=self.env, timeout=10, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.root.is_dir())

    def test_cleanup_preserves_unrelated_files_and_published_modules(self):
        self.candidate({'assets/data': b'fixture'})
        self.run_render()
        (self.root / 'identity').write_bytes(b'fixture identity\n')
        shutil.copyfile(RENDERER, self.root / 'render.pl')
        retained = self.root.parent / 'unrelated'
        retained.write_bytes(b'preserve')
        result = subprocess.run(['/usr/bin/perl', '-f', str(RENDERER), str(self.root), '--cleanup'],
                                capture_output=True, env=self.env, timeout=10, check=False)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        self.assertFalse(self.root.exists())
        self.assertEqual(retained.read_bytes(), b'preserve')
        self.assertTrue((self.destination / 'fixture/Fixture.pm').is_file())


if __name__ == '__main__':
    unittest.main()
