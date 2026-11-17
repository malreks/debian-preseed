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
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest


RENDERER = Path(__file__).resolve().parents[1] / 'scripts/common/render.pl'
PUBLICATION = RENDERER.parent / 'modules/files-logging.sh'
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

    def test_every_canonical_runtime_map_field_is_rendered(self):
        emitter = PUBLICATION.read_text(encoding='utf-8').split(
            'installer_runtime_path_placeholder_map() {', 1)[1].split('\n}\n', 1)[0]
        names = sorted(set(re.findall(r"printf '([A-Z][A-Z0-9_]*)=%s", emitter)))
        self.assertIn('GITBUILD_DISTRIBUTION', names)
        values = {name.encode(): ('/canonical/' + name.lower()).encode() for name in names}
        self.candidate({'assets/all-runtime-fields': b''.join(
            b'__INSTALLER_' + name + b'__' for name in values)}, values)
        self.run_render()
        self.assertEqual((self.source / 'assets/all-runtime-fields').read_bytes(), b''.join(values.values()))

    def assert_gitbuild_assets_rendered(self, suite):
        target = RENDERER.parents[2] / 'hooks/target'
        assets = {name: (target / name).read_bytes() for name in (
            'usr/local/lib/common/python3/dist-packages/gitbuild/core.py',
            'usr/local/share/common/gitbuild/sbuild.conf')}
        fields = set(re.findall(rb'__INSTALLER_(PATH_[A-Z0-9_]+)__', b'\n'.join(assets.values())))
        values = {name: b'/canonical/' + name.lower() for name in fields}
        values[b'GITBUILD_DISTRIBUTION'] = suite.encode()
        self.candidate({'assets/' + name: data for name, data in assets.items()}, values)
        self.run_render()
        for name, data in assets.items():
            with self.subTest(asset=name, suite=suite):
                expected = re.sub(rb'__INSTALLER_([A-Z0-9_]+)__', lambda match: values[match[1]], data)
                actual = (self.source / 'assets' / name).read_bytes()
                self.assertEqual(actual, expected)
                self.assertNotIn(b'__INSTALLER_', actual)

    def test_forky_gitbuild_module_and_sbuild_policy_are_rendered(self):
        self.assert_gitbuild_assets_rendered('forky')

    def test_trixie_gitbuild_module_and_sbuild_policy_are_rendered(self):
        self.assert_gitbuild_assets_rendered('trixie')

    def test_missing_canonical_suite_retains_candidate_without_receipt(self):
        self.candidate({'assets/module.py': b"DISTRIBUTION = '__INSTALLER_GITBUILD_DISTRIBUTION__'\n"})
        result = self.run_render(succeeds=False)
        self.assertIn(b'missing render field: GITBUILD_DISTRIBUTION', result.stderr)

    def test_literal_plain_staging_calls_have_no_deferred_scalar_fields(self):
        seed = RENDERER.parents[2]
        selectors = {'INSTALLER_SUITE': 'forky'}
        for line in (seed / 'repo.env').read_text(encoding='utf-8').splitlines():
            if not line or line.startswith('#'):
                continue
            name, separator, raw = line.partition('=')
            self.assertTrue(separator)
            words = shlex.split(raw)
            self.assertEqual(len(words), 1)
            selectors[name] = re.sub(r'\$\{([A-Z0-9_]+)\}', lambda match: selectors[match[1]], words[0])
        emitter = PUBLICATION.read_text(encoding='utf-8').split(
            'installer_runtime_path_placeholder_map() {', 1)[1].split('\n}\n', 1)[0]
        canonical = set(re.findall(r"printf '([A-Z][A-Z0-9_]*)=%s", emitter))
        call = re.compile(r'^\s*(?:desktop_stage_role_asset\s+(FILE_[A-Z0-9_]+)|'
                          r'(?:stage_target_asset|devops_stage_target_asset)\s+"\$\('
                          r'installer_repo_file_value\s+(FILE_[A-Z0-9_]+)\))', re.M)
        count = 0
        for source in sorted((seed / 'scripts').rglob('*.sh*')):
            records = re.sub(r'\\\n[ \t]*', ' ', source.read_text(encoding='utf-8'))
            for match in call.finditer(records):
                selector = match[1] or match[2]
                asset = seed / selectors[selector]
                count += 1
                self.assertTrue(asset.is_file(), f'missing staging source: {selector} ({asset})')
                data = asset.read_bytes()
                if b'\0' in data:
                    continue
                names = {name.decode() for name in re.findall(
                    rb'__INSTALLER_([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*)__', data)}
                with self.subTest(caller=str(source.relative_to(seed)), selector=selector):
                    self.assertFalse({name for name in names - canonical if not name.startswith('LOG_')})
        self.assertGreater(count, 500)
        print(f'PLAIN_STAGING_PASS checked_sources={count}')

    def test_dynamic_plain_staging_lists_have_no_deferred_installer_fields(self):
        seed = RENDERER.parents[2]
        selectors = {'INSTALLER_SUITE': 'forky'}
        for line in (seed / 'repo.env').read_text(encoding='utf-8').splitlines():
            if not line or line.startswith('#'):
                continue
            key, _, value = line.partition('=')
            selectors[key] = re.sub(r'\$\{([A-Z0-9_]+)\}', lambda match: selectors[match[1]], shlex.split(value)[0])
        emitter = PUBLICATION.read_text(encoding='utf-8').split(
            'installer_runtime_path_placeholder_map() {', 1)[1].split('\n}\n', 1)[0]
        canonical = set(re.findall(r"printf '([A-Z][A-Z0-9_]*)=%s", emitter))
        aliases = {}
        for key, relative in selectors.items():
            if not key.startswith('FILE_') or not (seed / relative).is_file():
                continue
            logical = relative
            for group in ('DIR_TARGET_AA', 'DIR_TARGET_APPARMOR', 'DIR_TARGET_TMPFILES_D',
                          'DIR_TARGET_SYSCTL_D', 'DIR_TARGET_BIN', 'DIR_TARGET_SBIN',
                          'DIR_TARGET_LIBEXEC', 'DIR_TARGET_LIB', 'DIR_TARGET_SHARE'):
                logical = re.sub(r'^' + re.escape(selectors[group]) + r'/(?:common|desktop|server)/',
                                 selectors[group] + '/', logical)
            logical = re.sub(r'/systemd/(?:common|desktop|server)/', '/systemd/', logical)
            for name in (relative, logical):
                aliases.setdefault(name, set()).add(seed / relative)
                if name.endswith('.tmpl'):
                    aliases.setdefault(name[:-5], set()).add(seed / relative)
        checked = 0
        callers = set()
        for source in sorted((seed / 'scripts').rglob('*.sh*')):
            records = re.sub(r'\\\n[ \t]*', ' ', source.read_text(encoding='utf-8'))
            for loop in re.finditer(r'\bfor\s+([a-z_][a-z0-9_]*)\s+in\s+([^\n;]+)'
                                    r'(?:;\s*|\n\s*)do\b(.*?)\n\s*done', records, re.S):
                variable, words, body = loop.groups()
                reference = r'\$(?:' + re.escape(variable) + r'\b|\{' + re.escape(variable) + r'\})'
                assignment = re.search(r'^\s*' + re.escape(variable) + r'="(' + reference + r')([^"$\n]*)"', body, re.M)
                assigned_suffix = assignment[2] if assignment else ''
                calls = re.finditer(r'\b((?:devops_)?stage_target_asset|desktop_stage_role_asset|'
                                    r'profile_hardware_stage_asset)\s+"('
                                    r'\$\(installer_repo_asset_path\s+DIR_[A-Z0-9_]+\s+"[^"\n]+"\)'
                                    r'|[^"\n]+)"', body)
                for call in calls:
                    expression = call[2]
                    indirect = re.fullmatch(r'\$(?:([a-z_][a-z0-9_]*)|\{([a-z_][a-z0-9_]*)\})', expression)
                    if indirect and (indirect[1] or indirect[2]) != variable:
                        assigned = re.search(r'^\s*' + re.escape(indirect[1] or indirect[2]) +
                                             r'="([^"\n]*)"', body[:call.start()], re.M)
                        if assigned:
                            expression = assigned[1]
                    directory = re.fullmatch(r'\$\(installer_repo_asset_path\s+(DIR_[A-Z0-9_]+)\s+"([^"\n]+)"\)', expression)
                    if directory:
                        expression = directory[2]
                        base = selectors[directory[1]] + '/'
                    elif call[1] in ('desktop_stage_role_asset', 'profile_hardware_stage_asset'):
                        base = selectors['DIR_HOOKS_TARGET'] + '/'
                    else:
                        continue
                    if not re.search(reference, expression):
                        continue
                    prefix, suffix = re.split(reference, expression, maxsplit=1)
                    for leaf in shlex.split(words):
                        if '$' in leaf:
                            continue  # Policy-selected branches are audited separately.
                        wanted = base + prefix + leaf + assigned_suffix + suffix
                        assets = aliases.get(wanted, set())
                        self.assertTrue(assets, f'missing dynamic staging source: {source}: {wanted}')
                        for asset in assets:
                            data = asset.read_bytes()
                            if b'\0' in data:
                                continue
                            names = {name.decode() for name in re.findall(
                                rb'__INSTALLER_([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*)__', data)}
                            with self.subTest(caller=str(source.relative_to(seed)), asset=str(asset.relative_to(seed))):
                                self.assertFalse({name for name in names - canonical if not name.startswith('LOG_')})
                            callers.add(source.relative_to(seed).as_posix())
                            checked += 1
        self.assertGreater(checked, 100)
        self.assertTrue({'scripts/common/hardware-tuning.sh', 'scripts/late/devops/gitbuild.sh',
                         'scripts/late/podman.sh', 'scripts/late/security.sh'} <= callers)
        print(f'DYNAMIC_STAGING_PASS checked_sources={checked}')

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


class TypedPublicationTests(unittest.TestCase):
    """Exercise publication and its typed consumers inside the private guest."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='typed-publication-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.target = self.root / 'target'
        (self.target / 'tmp').mkdir(parents=True)
        self.seed = RENDERER.parents[2]
        self.prepared = self.root / 'prepared'
        (self.prepared / 'inputs').mkdir(parents=True)
        (self.prepared / 'source').mkdir()
        values = {}
        profile = self.seed / 'catalog/compiled/forky/profiles/desktop/btrfs-de-p15s.env'
        for line in profile.read_text(encoding='utf-8').splitlines():
            if not line or line.startswith('#'):
                continue
            key, separator, raw = line.partition('=')
            self.assertTrue(separator)
            values[key] = shlex.split(raw)[0]
        emitter = PUBLICATION.read_text(encoding='utf-8').split(
            'installer_runtime_path_placeholder_map() {', 1)[1].split('\n}\n', 1)[0]
        self.paths = {key: values[name] for key, name in re.findall(
            r"printf '([A-Z][A-Z0-9_]*)=%s\\n' \"\$([A-Z0-9_]+)\"", emitter) if values.get(name)}
        (self.prepared / 'inputs/paths.map').write_text(''.join(
            key + '=' + value + '\n' for key, value in self.paths.items()), encoding='utf-8')
        self.env = {'PATH': '/usr/bin:/bin', 'HOME': str(self.root), 'LC_ALL': 'C',
                    'TMPDIR': str(self.root), 'TMP': str(self.root), 'TEMP': str(self.root),
                    'BOOTSTRAP_PREPARED_SOURCE_ROOT': str(self.prepared / 'source')}
        self.modules = [self.prepare(name) for name in (
            'scripts/common/modules/files-logging.sh', 'scripts/common/lifecycle.sh',
            'scripts/late/target-assets.sh', 'scripts/desktop/components/appearance.sh',
            'scripts/late/security.sh')]
        self.base = '\n'.join((
            '. "$1"', '. "$2"', '. "$3"', '. "$4"', '. "$5"',
            'TARGET_ROOT=$6; SEED=$7; DIR_TMP=/tmp',
            'installer_fatal() { printf "%s\\n" "$*" >&2; exit 93; }',
            'installer_fatal_status() { exit "$1"; }',
            'installer_operation_context_repo() { :; }',
            'bootstrap_prepared_asset_published() { return 1; }',
            'target_normalize_systemd_config_parent_modes() { :; }',
            'installer_capture_primary_default() { :; }',
            'fetch_hook() { cp "$SEED/$1" "$2"; }'))

    def prepare(self, relative):
        data = (self.seed / relative).read_text(encoding='utf-8')
        data = re.sub(r'__INSTALLER_(PATH_[A-Z0-9]+(?:_[A-Z0-9]+)*|'
                      r'APPARMOR_PROFILE_[A-Z0-9]+(?:_[A-Z0-9]+)*|GITBUILD_DISTRIBUTION)__',
                      lambda match: self.paths[match[1]], data)
        output = self.prepared / 'source' / relative
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(data, encoding='utf-8')
        return output

    def shell(self, code, *arguments, shell=None):
        return subprocess.run([*(shell or ['/bin/dash']), '-eu', '-c', self.base + '\n' + code,
                               'typed-publication', *map(str, self.modules), str(self.target),
                               str(self.prepared / 'source'), *map(str, arguments)],
                              env=self.env, capture_output=True, timeout=20, check=False)

    def test_template_inputs_require_a_private_root_and_preserve_grammar_until_the_consumer(self):
        relative = 'hooks/target/etc/stubby/stubby.yml.tmpl'
        self.prepare(relative)
        code = '\n'.join((
            'stage=$(target_private_stage_dir stubby)',
            'case "$8" in public) stage=/etc ;; shared) chmod 0755 "$TARGET_ROOT$stage" ;; esac',
            'stage_target_template_input "$9" "$stage" "${10}"',
            'cat "$TARGET_ROOT$stage/${10}"'))
        shells = [['/bin/dash']]
        if shutil.which('busybox'):
            shells.append([shutil.which('busybox'), 'sh'])
        for shell in shells:
            for mode, leaf, succeeds in (('private', 'nested/stubby.yml.tmpl', True),
                                         ('public', 'input', False), ('shared', 'input', False),
                                         ('private', '../escape', False), ('private', '', False)):
                with self.subTest(shell=shell, mode=mode, leaf=leaf):
                    result = self.shell(code, mode, relative, leaf, shell=shell)
                    self.assertEqual(result.returncode == 0, succeeds, result.stderr.decode(errors='replace'))
                    if succeeds:
                        self.assertIn(b'__INSTALLER_SYSTEM_NAMESERVERS_UPSTREAMS__', result.stdout)
                        self.assertNotIn(b'__INSTALLER_PATH_', result.stdout)
                    self.assertFalse((self.target / 'etc').exists())

    def test_registry_retains_only_its_literal_mapping_grammar(self):
        relative = 'hooks/target/usr/local/share/desktop/labwc-appearance/fields.json.tmpl'
        source = self.prepare(relative)
        original = source.read_text(encoding='utf-8')
        output = self.target / 'fields.json'
        for unknown in (False, True):
            with self.subTest(unknown=unknown):
                source.write_text(original + ('\n__INSTALLER_UNKNOWN_FIELD__\n' if unknown else ''), encoding='utf-8')
                output.write_text('previous', encoding='ascii')
                result = self.shell('publish_target_asset "$8" /fields.json 0644 appearance-registry', relative)
                self.assertEqual(result.returncode == 0, not unknown, result.stderr.decode(errors='replace'))
                if unknown:
                    self.assertEqual(output.read_text(), 'previous')
                else:
                    registry = json.loads(output.read_text(encoding='utf-8'))
                    self.assertGreater(len(registry['fields']), 500)
                    self.assertIn('__INSTALLER_LABWC_WAYBAR_INTERNAL_ACTIVE_SHADOW__', output.read_text())
                self.assertFalse(list(self.target.glob('.installer-asset.*')))

    def test_actual_stubby_handoff_renders_before_publication_and_retains_previous_output_on_failure(self):
        helper = 'scripts/late/stubby-config.py'
        template = 'hooks/target/etc/stubby/stubby.yml.tmpl'
        helper_path = self.prepare(helper)
        helper_source = helper_path.read_text(encoding='utf-8')
        input_path = self.prepare(template)
        original = input_path.read_text(encoding='utf-8')
        policy = self.root / 'policy.map'
        policy.write_text('SYSTEM_DNS_UPSTREAM_TLS_CA_CUSTOM_ENABLE=false\n'
                          'SYSTEM_DNS_UPSTREAM_TLS_CA_FILE=/etc/ssl/certs/ca-certificates.crt\n'
                          'SYSTEM_NAMESERVERS_UPSTREAMS_JSON=[{"dns_index":1,"address_data":"192.0.2.53",'
                          '"tls_port":853,"tls_auth_name":"dns.fixture.invalid"}]\n'
                          'APP_VETH_TLS_HOST_ADDRESS=127.0.0.1\nAPP_VETH_TLS_HOST_PORT=53001\n', encoding='ascii')
        runner = self.root / 'target-python.py'
        runner.write_text('''from pathlib import Path
import runpy
import sys
root = Path(sys.argv[1]).resolve(strict=True)
paths = [root / value.lstrip('/') for value in sys.argv[2:5]]
assert all(path.resolve(strict=True).is_relative_to(root) for path in paths)
module = runpy.run_path(str(paths[0]), run_name='fixture_stubby')
context = module['main'].__globals__
context['OUTPUT'] = root / 'etc/stubby/stubby.yml'
def verified(upstreams):
    assert len(upstreams) == 1 and upstreams[0]['tls_auth_name'] == 'dns.fixture.invalid'
    print('fixture_tls_authentication=mocked', flush=True)
context['verify_public'] = verified
raise SystemExit(module['main']([str(paths[1]), str(paths[2]), sys.argv[5]]))
''', encoding='utf-8')
        code = '\n'.join((
            'require_in_target() { :; }',
            'installer_repo_file_value() { case "$1" in',
            ' FILE_LATE_STUBBY_CONFIG) printf "%s\\n" scripts/late/stubby-config.py ;;',
            ' FILE_TARGET_STUBBY_STUBBY_TMPL) printf "%s\\n" hooks/target/etc/stubby/stubby.yml.tmpl ;;',
            ' *) exit 94 ;; esac; }',
            'policy=$8; runner=$9; fixture_python=${10}',
            'app_veth_dns_placeholder_map() { cat "$policy"; }',
            'run_in_target() { shift; [ "$1" = /usr/bin/python3 ]; shift 3;',
            ' "$fixture_python" -I -B "$runner" "$TARGET_ROOT" "$@"; }',
            'configure_target_stubby'))
        output = self.target / 'etc/stubby/stubby.yml'
        for variant in ('reported-failure', 'rendered', 'unknown-field'):
            with self.subTest(variant=variant):
                helper_path.write_text(helper_source.replace(
                    "'  __INSTALLER_' + 'SYSTEM_NAMESERVERS_UPSTREAMS__'",
                    "'  __INSTALLER_SYSTEM_NAMESERVERS_UPSTREAMS__'")
                    if variant == 'reported-failure' else helper_source, encoding='utf-8')
                input_path.write_text(original + ('\n__INSTALLER_UNKNOWN_FIELD__\n'
                                                 if variant == 'unknown-field' else ''), encoding='utf-8')
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_text('previous', encoding='ascii')
                result = self.shell(code, policy, runner, sys.executable)
                self.assertEqual(result.returncode == 0, variant == 'rendered', result.stderr.decode(errors='replace'))
                if variant != 'rendered':
                    self.assertEqual(output.read_text(), 'previous')
                    self.assertNotIn(b'fixture_tls_authentication=mocked', result.stdout)
                    if variant == 'reported-failure':
                        self.assertIn(b'has unresolved installer placeholders', result.stderr)
                else:
                    data = output.read_text(encoding='utf-8')
                    self.assertNotIn('__INSTALLER_', data)
                    self.assertIn('  - address_data: "192.0.2.53"', data)
                    self.assertIn(b'fixture_tls_authentication=mocked', result.stdout)
                self.assertFalse(list((self.target / 'tmp').iterdir()))


class ScalarPublicationTests(unittest.TestCase):
    """The shared copy fast path must recognize canonical non-path fields too."""

    def test_suite_only_input_and_suite_in_scalar_value_render_in_dash_and_busybox(self):
        shells = [['/bin/dash']]
        if shutil.which('busybox'):
            shells.append([shutil.which('busybox'), 'sh'])
        batch = BatchRenderTests('test_unknown_path_retains_candidate_without_receipt')
        batch.setUp()
        self.addCleanup(batch.doCleanups)
        data = PUBLICATION.read_bytes()
        fields = set(re.findall(rb'__INSTALLER_(PATH_[A-Z0-9_]+|APPARMOR_PROFILE_[A-Z0-9_]+|GITBUILD_DISTRIBUTION)__', data))
        batch.candidate({'scripts/publication.sh': data},
                        {name: b'/canonical/' + name.lower() for name in fields})
        batch.run_render()
        publications = (PUBLICATION, batch.source / 'scripts/publication.sh')
        with tempfile.TemporaryDirectory(prefix='scalar-publication-') as temporary:
            root = Path(temporary)
            source = root / 'input'
            output = root / 'output'
            env = {'PATH': '/usr/bin:/bin', 'HOME': str(root), 'TMPDIR': str(root),
                   'TMP': str(root), 'TEMP': str(root), 'LC_ALL': 'C'}
            for shell, publication in ((shell, path) for shell in shells for path in publications):
                for suite in ('forky', 'trixie'):
                    for explicit in (False, True):
                        with self.subTest(shell=shell, publication=str(publication), suite=suite, explicit=explicit):
                            source.write_text('__INSTALLER_VALUE__' if explicit else
                                              '__INSTALLER_GITBUILD_DISTRIBUTION__', encoding='ascii')
                            code = '\n'.join((
                                '. "$1"', 'GITBUILD_DISTRIBUTION=$4',
                                'installer_fatal() { printf "%s\\n" "$*" >&2; exit 93; }',
                                'if [ "$5" = true ]; then',
                                '  installer_apply_scalar_placeholders "$2" "$3" VALUE __INSTALLER_GITBUILD_DISTRIBUTION__',
                                'else installer_apply_scalar_placeholders "$2" "$3"; fi',
                                'installer_assert_no_unresolved_installer_placeholders "$3"'))
                            result = subprocess.run(
                                [*shell, '-eu', '-c', code, 'publication-fixture', str(publication),
                                 str(source), str(output), suite, 'true' if explicit else 'false'],
                                env=env, capture_output=True, timeout=10, check=False)
                            self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
                            self.assertEqual(output.read_text(encoding='ascii'), suite)

    def test_plain_publication_renders_suite_and_rejects_unknown_scalar_before_replacement(self):
        publication = RENDERER.parents[1] / 'late/target-assets.sh'
        with tempfile.TemporaryDirectory(prefix='plain-publication-') as temporary:
            root = Path(temporary)
            source = root / 'input'
            target = root / 'target'
            target.mkdir()
            output = target / 'output'
            env = {'PATH': '/usr/bin:/bin', 'HOME': str(root), 'TMPDIR': str(root),
                   'TMP': str(root), 'TEMP': str(root), 'LC_ALL': 'C'}
            code = '\n'.join((
                '. "$1"', '. "$2"', 'TARGET_ROOT=$3', 'GITBUILD_DISTRIBUTION=forky',
                'installer_fatal() { printf "%s\\n" "$*" >&2; exit 93; }',
                'installer_fatal_status() { exit "$1"; }',
                'installer_operation_context_repo() { :; }',
                'bootstrap_prepared_asset_published() { return 1; }',
                'target_asset_host_path() { printf "%s%s\\n" "$TARGET_ROOT" "$1"; }',
                'ensure_target_asset_parent() { [ "$1" = /output ]; }',
                'fetch_hook() { cp "$1" "$2"; }',
                'installer_capture_primary_default() { :; }',
                'publish_target_asset "$4" /output 0644 plain'))
            for token, expected_status, expected_output in (
                    ('__INSTALLER_UNKNOWN_SCALAR__', 93, 'original'),
                    ('__INSTALLER_GITBUILD_DISTRIBUTION__', 0, 'forky')):
                with self.subTest(token=token):
                    source.write_text(token, encoding='ascii')
                    output.write_text('original', encoding='ascii')
                    result = subprocess.run(
                        ['/bin/dash', '-eu', '-c', code, 'plain-publication-fixture',
                         str(PUBLICATION), str(publication), str(target), str(source)],
                        env=env, capture_output=True, timeout=10, check=False)
                    self.assertEqual(result.returncode, expected_status, result.stderr.decode(errors='replace'))
                    self.assertEqual(output.read_text(encoding='ascii'), expected_output)
                    self.assertFalse(list(target.glob('.installer-asset.*')))

    def test_devops_shell_profile_renders_policy_with_the_cached_canonical_map(self):
        profile = RENDERER.parents[2] / 'hooks/target/etc/skel-desktop/.profile.d/71-devops-de.sh'
        with tempfile.TemporaryDirectory(prefix='devops-profile-render-') as temporary:
            root = Path(temporary)
            prepared = root / 'prepared'
            (prepared / 'source').mkdir(parents=True)
            (prepared / 'inputs').mkdir()
            fields = sorted(set(re.findall(rb'__INSTALLER_(PATH_[A-Z0-9_]+)__', profile.read_bytes())))
            (prepared / 'inputs/paths.map').write_bytes(b''.join(
                field + b'=/canonical/' + field.lower() + b'\n' for field in fields) +
                b'GITBUILD_DISTRIBUTION=forky\n')
            output = root / 'profile'
            env = {'PATH': '/usr/bin:/bin', 'HOME': str(root), 'TMPDIR': str(root),
                   'TMP': str(root), 'TEMP': str(root), 'LC_ALL': 'C',
                   'BOOTSTRAP_PREPARED_SOURCE_ROOT': str(prepared / 'source')}
            code = '\n'.join((
                '. "$1"',
                'installer_fatal() { printf "%s\\n" "$*" >&2; exit 93; }',
                'installer_apply_scalar_placeholders "$2" "$3" HARDWARE_CPU_SCHEDULER_SCX_WORKER_PERFORMANCE scx_lavd',
                'installer_assert_no_unresolved_installer_placeholders "$3"'))
            result = subprocess.run(['/bin/dash', '-eu', '-c', code, 'devops-profile-fixture',
                                     str(PUBLICATION), str(profile), str(output)],
                                    env=env, capture_output=True, timeout=10, check=False)
            self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
            data = output.read_bytes()
            self.assertNotIn(b'__INSTALLER_', data)
            self.assertIn(b'DEVOPS_DE_SCX_WORKER_PERFORMANCE="scx_lavd"', data)


if __name__ == '__main__':
    unittest.main()
