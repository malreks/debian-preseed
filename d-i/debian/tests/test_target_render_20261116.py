"""Batch publication regressions; execute only in the reviewed private image."""
from __future__ import annotations

from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation
require_test_isolation()

import hashlib
import importlib.util
import json
import os
import tempfile
import unittest
from unittest import mock


SEED = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('installer_target_render', SEED / 'scripts/common/render.py')
render = importlib.util.module_from_spec(spec)
spec.loader.exec_module(render)
SELECTORS = {'scripts': 'scripts', 'target': 'assets', 'late': 'scripts/late',
             'desktop': 'scripts/desktop', 'firstboot': 'scripts/firstboot',
             'appearance-python': 'assets/python/labwc_appearance',
             'appearance-registry': 'assets/appearance/fields.json.tmpl'}


class BatchRenderTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='target-render-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / 'source'
        self.source.mkdir()
        (self.root / 'inputs').mkdir()

    def candidate(self, assets):
        rows = ['format=3\n']
        for name, data in assets.items():
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            rows.append(f'{len(data)}\t{hashlib.sha256(data).hexdigest()}\t{name}\n')
        (self.root / 'inputs/payload.manifest').write_text(''.join(rows))

    def run_render(self, paths=None, logging=None, themes=None):
        return render.render_tree(self.root, paths or {}, logging or {}, themes or {}, SELECTORS)

    def test_one_pass_resolves_paths_logging_and_theme_without_consuming_typed_scalars(self):
        self.candidate({'assets/config.tmpl': b'__INSTALLER_PATH_A____INSTALLER_PATH_B__\n'
                        b'__INSTALLER_LOG_ROOT__ __THEME_COLOR__ __INSTALLER_ACCOUNT_USERNAME__\n'})
        report = self.run_render({b'PATH_A': b'/usr', b'PATH_B': b'/bin'},
                                 {b'LOG_ROOT': b'/logs'}, {b'COLOR': b'#123456'})
        self.assertEqual((self.source / 'assets/config.tmpl').read_bytes(),
                         b'/usr/bin\n/logs #123456 __INSTALLER_ACCOUNT_USERNAME__\n')
        self.assertEqual(report['rendered_files'], 1)

    def test_replacement_characters_are_literal(self):
        data = render.substitute(b'__INSTALLER_PATH_A__', render.PATH_TOKEN, {b'PATH_A': b'/a&|\\b'})
        self.assertEqual(data, b'/a&|\\b')

    def test_unknown_path_retains_private_candidate_without_receipt(self):
        self.candidate({'scripts/helper': b'__INSTALLER_PATH_UNKNOWN__'})
        with self.assertRaisesRegex(ValueError, 'missing render field'):
            self.run_render()
        self.assertTrue(self.source.is_dir())
        self.assertFalse((self.root / 'receipt.json').exists())

    def test_modified_copy_is_rejected_against_authenticated_manifest(self):
        self.candidate({'assets/data': b'original'})
        (self.source / 'assets/data').write_bytes(b'replaced')
        with self.assertRaisesRegex(ValueError, 'differs from authenticated manifest'):
            self.run_render()

    def test_missing_copy_is_rejected(self):
        self.candidate({'assets/data': b'original'})
        (self.source / 'assets/data').unlink()
        with self.assertRaisesRegex(ValueError, 'missing manifest members'):
            self.run_render()

    def test_symlink_and_hardlink_inputs_are_rejected(self):
        self.candidate({'scripts/helper': b'fixture'})
        helper = self.source / 'scripts/helper'
        helper.unlink()
        helper.symlink_to(self.root / 'unpublished')
        with self.assertRaises(ValueError):
            self.run_render()
        helper.unlink()
        helper.write_bytes(b'fixture')
        os.link(helper, self.source / 'scripts/other')
        with self.assertRaises(ValueError):
            self.run_render()

    def test_aggregate_input_limit_applies_before_rendering(self):
        self.candidate({'assets/data': b'12345'})
        with mock.patch.object(render, 'BYTE_LIMIT', 4), self.assertRaises(ValueError):
            self.run_render()

    def test_registry_only_consumes_defaults_and_leaves_editor_mappings_literal(self):
        data = b'"key": "COLOR",\n"default": "__THEME_COLOR__",\n"tokens": ["__THEME_COLOR__"]\n'
        result = render.theme_bytes(data, {b'COLOR': b'#abcdef'}, 'assets', defaults_only=True)
        self.assertIn(b'"default": "#abcdef"', result)
        self.assertIn(b'"tokens": ["__THEME_COLOR__"]', result)

    def test_python_editor_and_shell_grammar_stay_literal(self):
        assets = {'assets/python/labwc_appearance/fields.py': b'TOKEN = "__THEME_COLOR__"\n',
                  'scripts/desktop/components/appearance.sh': b'prefix="__THEME_"\n'}
        self.candidate(assets)
        self.run_render(themes={b'COLOR': b'#abcdef'})
        for name, data in assets.items():
            self.assertEqual((self.source / name).read_bytes(), data)

    def test_binary_files_are_byte_identical(self):
        self.candidate({'assets/icon.png': b'\x89PNG\0__THEME_COLOR__'})
        self.run_render()
        self.assertEqual((self.source / 'assets/icon.png').read_bytes(), b'\x89PNG\0__THEME_COLOR__')

    def test_cleanup_refuses_incomplete_candidate(self):
        self.candidate({'assets/data': b'fixture'})
        with self.assertRaises(ValueError):
            render.cleanup_workspace(self.root)
        self.assertTrue(self.source.is_dir())

    def test_cleanup_removes_only_a_completed_exact_workspace(self):
        self.candidate({'assets/data': b'fixture'})
        report = self.run_render()
        (self.root / 'receipt.json').write_text(json.dumps(report))
        (self.root / 'identity').write_text('fixture identity\n')
        (self.root / 'render.py').write_text('# fixture renderer\n')
        retained = self.root.parent / (self.root.name + '-unrelated')
        retained.write_bytes(b'preserve')
        self.addCleanup(retained.unlink)
        render.cleanup_workspace(self.root)
        self.assertFalse(self.root.exists())
        self.assertEqual(retained.read_bytes(), b'preserve')


if __name__ == '__main__':
    unittest.main()
