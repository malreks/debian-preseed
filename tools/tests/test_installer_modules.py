"""Direct editable input, runtime module inventory and publication contracts."""

# Refuse host execution before importing runtime helpers or creating fixtures.
from pathlib import Path as _IsolationPath
import sys as _isolation_sys
_isolation_sys.path.insert(0, str(_IsolationPath(__file__).resolve().parents[2] / 'tools'))
# Copied checker/GUI fixtures still use the verified private checkout gate.
_isolation_sys.path.insert(0, '/workspace/repository/tools')
from isolation import require_test_isolation as _require_test_isolation
_isolation_sys.path.pop(0)
_require_test_isolation()

from pathlib import Path
import importlib.util
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]

def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'tools' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

checker = load('check_modules')
publisher = load('publication')
builder = load('build')
build_checks = load('check_build')

class RepositoryFileModes(unittest.TestCase):
    def test_builder_serializes_without_commands_or_source_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('debian', 'forky', 'trixie'):
                shutil.copytree(ROOT / 'd-i' / name, root / 'd-i' / name,
                                ignore=shutil.ignore_patterns('releases', 'publications', 'tests', '__pycache__'))
            for name in builder.COMPILER_INPUTS:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / name, path)
            seed = root / 'd-i/debian'
            malformed = seed / 'scripts/not-a-valid-shell.sh'
            malformed.write_text('if then\n')
            private = seed / 'preseed.env'
            private.write_text('PRIVATE_FIXTURE=never-package-this\n')
            before = {path: path.read_bytes() for path in root.rglob('*') if path.is_file()}
            with mock.patch.object(builder, 'ROOT', root), \
                 mock.patch.object(subprocess, 'Popen', side_effect=AssertionError('build executed a command')):
                release_id, products, frontends = builder.build()
            self.assertEqual(len(release_id), 64)
            self.assertEqual(set(products), {'payload.tar.gz', 'payload.manifest', 'source.sh',
                                             'support-matrix.json', 'receipt.json'})
            self.assertIn('forky/preseed.cfg', frontends)
            self.assertIn('trixie/preseed.cfg', frontends)
            self.assertIn(b'scripts/not-a-valid-shell.sh', products['payload.manifest'])
            self.assertNotIn(b'preseed.env', products['payload.manifest'])
            self.assertNotIn(b'catalog/placeholder-registry.json', products['payload.manifest'])
            self.assertIn(b'catalog/placeholder-registry.tsv', products['payload.manifest'])
            source_inputs = json.loads(products['receipt.json'])['source_inputs']
            self.assertNotIn('catalog/placeholder-registry.json', source_inputs)
            self.assertIn('catalog/placeholder-registry.tsv', source_inputs)
            self.assertEqual(before, {path: path.read_bytes() for path in before})

    def test_every_python_test_and_fixture_checks_isolation_before_runtime_imports(self):
        import ast
        paths = sorted((ROOT / 'd-i/debian/tests').rglob('*.py')) + sorted((ROOT / 'tools/tests').rglob('*.py'))
        for path in paths:
            with self.subTest(path=path.relative_to(ROOT)):
                tree = ast.parse(path.read_text(), filename=str(path))
                calls = [index for index, node in enumerate(tree.body)
                         if isinstance(node, ast.Expr) and isinstance(node.value, ast.Call)
                         and isinstance(node.value.func, ast.Name)
                         and node.value.func.id == '_require_test_isolation']
                self.assertEqual(len(calls), 1, 'missing mandatory host-isolation gate')
                prefix = tree.body[:calls[0]]
                for node in prefix:
                    if isinstance(node, ast.Import):
                        self.assertEqual([alias.name for alias in node.names], ['sys'])
                    elif isinstance(node, ast.ImportFrom):
                        self.assertIn(node.module, ('__future__', 'pathlib', 'isolation'))
                    elif isinstance(node, ast.Expr) and isinstance(node.value, ast.Call):
                        self.assertIsInstance(node.value.func, ast.Attribute)
                        self.assertIn(node.value.func.attr, ('insert', 'pop'))
                    else:
                        self.assertIsInstance(node, ast.Expr)
                        self.assertIsInstance(node.value, ast.Constant)
                        self.assertIsInstance(node.value.value, str)

    def test_all_repository_source_files_are_nonexecutable(self):
        paths = [path for path in ROOT.iterdir() if path.is_file()]
        for name in ('d-i', 'docs', 'tools'):
            paths.extend(path for path in (ROOT / name).rglob('*') if path.is_file())
        self.assertTrue(paths)
        self.assertEqual([str(path.relative_to(ROOT)) for path in paths
                          if path.stat().st_mode & 0o111], [])

    def test_builder_rejects_undeclared_apparmor_policy(self):
        with tempfile.TemporaryDirectory() as directory:
            seed = Path(directory)
            policy_dir = seed / 'hooks/target/etc/apparmor.d/desktop'
            policy_dir.mkdir(parents=True)
            (policy_dir / 'new-policy').write_text('profile new-policy {\n}\n')
            config = seed / 'hooks/target/etc/apparmor/desktop/modes.conf.tmpl'
            config.parent.mkdir(parents=True)
            config.write_text('__DESKTOP_APPARMOR_STATE__ optional firstboot -\n')
            server_modes = seed / 'hooks/target/etc/apparmor/server/modes.conf.tmpl'
            server_modes.parent.mkdir(parents=True)
            server_modes.write_text('# No server fixture policies.\n')
            with mock.patch.object(build_checks, 'SEED', seed):
                with self.assertRaisesRegex(ValueError, 'unmanaged repository AppArmor profile'):
                    build_checks.validate_apparmor_modes()
                config.write_text(config.read_text() +
                                  '__DESKTOP_APPARMOR_STATE__ required new-policy -\n')
                build_checks.validate_apparmor_modes()

class SourceMembershipContracts(unittest.TestCase):
    """A compiled member index must remain complete, unique and suite-correct."""

    def members(self, rows=None):
        table = 'catalog/compiled/source-members.tsv'
        payload = {'scripts/fixture.sh': b'# source fixture\n',
                   'frontends/forky/common.cfg': b'# frontend fixture\n', table: b''}
        if rows is None:
            rows = [(table, 'any', 'any'),
                    ('frontends/forky/common.cfg', 'any', 'forky'),
                    ('scripts/fixture.sh', 'any', 'any')]
        payload[table] = ('format\t1\n' + ''.join('\t'.join(row) + '\n' for row in rows)).encode()
        return payload

    def test_inventory_matches_every_payload_member(self):
        build_checks.validate_source_members(self.members())

    def test_missing_duplicate_and_nonexistent_members_are_rejected(self):
        table = 'catalog/compiled/source-members.tsv'
        valid = [(table, 'any', 'any'),
                 ('frontends/forky/common.cfg', 'any', 'forky'),
                 ('scripts/fixture.sh', 'any', 'any')]
        for rows in (valid[:-1], valid + [valid[-1]],
                     valid + [('scripts/absent.sh', 'any', 'any')]):
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                build_checks.validate_source_members(self.members(rows))

    def test_wrong_suite_and_noncanonical_members_are_rejected(self):
        for row in (('frontends/forky/common.cfg', 'any', 'trixie'),
                    ('scripts/fixture.sh', 'unknown', 'any'),
                    ('../scripts/fixture.sh', 'any', 'any')):
            rows = [('catalog/compiled/source-members.tsv', 'any', 'any'),
                    ('frontends/forky/common.cfg', 'any', 'forky'),
                    ('scripts/fixture.sh', 'any', 'any')]
            rows[1 if row[0].startswith('frontends/') else 2] = row
            with self.subTest(row=row), self.assertRaises(ValueError):
                build_checks.validate_source_members(self.members(rows))


class SourceCaptureContracts(unittest.TestCase):
    """Unexecuted failure fixtures; every mutation stays in the owned tree."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / 'd-i/debian/source.txt'
        self.source.parent.mkdir(parents=True)
        self.source.write_bytes(b'captured source\n')
        for suite in ('forky', 'trixie'):
            frontend = self.root / 'd-i' / suite
            for tree in ('classes', 'fragments', 'hooks/target/etc/apt'):
                (frontend / tree).mkdir(parents=True)
            (frontend / 'common.cfg').write_bytes(b'# fixture common\n')
        for name in builder.COMPILER_INPUTS:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'# fixture compiler input\n')

    def test_capture_is_data_only_and_excludes_private_and_generated_leaves(self):
        private = self.source.parent / 'preseed.env'
        private.write_bytes(b'PRIVATE_FIXTURE=never-package-this\n')
        generated = self.source.parent / 'releases'
        generated.mkdir()
        (generated / 'ignore').write_bytes(b'not authored source\n')
        with builder.SourceCapture(self.root) as capture:
            contents, compiler = capture.read()
            capture.verify()
        self.assertEqual(contents['source.txt'], b'captured source\n')
        self.assertEqual(set(compiler), set(builder.COMPILER_INPUTS))
        self.assertNotIn('preseed.env', contents)
        self.assertFalse(any(name.startswith('releases/') for name in contents))

    def test_only_developer_placeholder_json_is_excluded_from_runtime_capture(self):
        seed = self.source.parent
        developer = seed / 'catalog/placeholder-registry.json'
        runtime = seed / 'catalog/placeholder-registry.tsv'
        other_json = seed / 'catalog/selection-fixture.json'
        same_leaf = seed / 'hooks/target/usr/local/share/placeholder-registry.json'
        fixtures = {developer: b'{"developer_metadata": true}\n',
                    runtime: b'format\t2\tfixture\n',
                    other_json: b'{"runtime_catalog": true}\n',
                    same_leaf: b'{"runtime_asset": true}\n'}
        for path, data in fixtures.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        with builder.SourceCapture(self.root) as capture:
            contents, compiler = capture.read()
            capture.verify()
        self.assertEqual(set(contents), {
            'source.txt', 'frontends/forky/common.cfg', 'frontends/trixie/common.cfg',
            runtime.relative_to(seed).as_posix(), other_json.relative_to(seed).as_posix(),
            same_leaf.relative_to(seed).as_posix(),
        })
        self.assertEqual(set(compiler), set(builder.COMPILER_INPUTS))
        for path, data in fixtures.items():
            self.assertEqual(path.read_bytes(), data, 'capture modified authored metadata')
            if path != developer:
                self.assertEqual(contents[path.relative_to(seed).as_posix()], data)

    def test_symlink_hardlink_fifo_and_executable_sources_are_rejected(self):
        safe = self.root / 'owned-other-file'
        safe.write_bytes(b'outside selected inputs\n')
        for kind in ('symlink', 'hardlink', 'fifo', 'executable'):
            with self.subTest(kind=kind):
                self.source.unlink()
                if kind == 'symlink':
                    self.source.symlink_to(safe)
                elif kind == 'hardlink':
                    os.link(safe, self.source)
                elif kind == 'fifo':
                    os.mkfifo(self.source)
                else:
                    self.source.write_bytes(b'executable source\n')
                    self.source.chmod(0o755)
                with builder.SourceCapture(self.root) as capture:
                    with self.assertRaises(ValueError):
                        capture.read()
                self.assertEqual(safe.read_bytes(), b'outside selected inputs\n')

    def test_replaced_leaf_after_pin_cannot_redirect_the_read(self):
        other = self.root / 'owned-other-file'
        other.write_bytes(b'must never be captured\n')
        original = self.source.stat()
        real_open = os.open
        replaced = False

        def replace_before_promotion(path, flags, *args, **kwargs):
            nonlocal replaced
            if (str(path).startswith('/proc/self/fd/') and not replaced
                    and os.fstat(int(str(path).rsplit('/', 1)[1])).st_ino == original.st_ino):
                self.source.rename(self.source.with_name('previous-source.txt'))
                self.source.symlink_to(other)
                replaced = True
            return real_open(path, flags, *args, **kwargs)

        with builder.SourceCapture(self.root) as capture:
            with mock.patch.object(builder.os, 'open', side_effect=replace_before_promotion):
                with self.assertRaises(ValueError):
                    capture.read()
        self.assertTrue(replaced)
        self.assertEqual(other.read_bytes(), b'must never be captured\n')

    def test_new_deleted_replaced_and_compiler_inputs_invalidate_capture(self):
        for mutation in ('added', 'deleted', 'replaced', 'compiler'):
            with self.subTest(mutation=mutation):
                with builder.SourceCapture(self.root) as capture:
                    capture.read()
                    before = self.source.read_bytes()
                    if mutation == 'added':
                        changed = self.source.with_name('new-source.txt')
                        changed.write_bytes(b'new\n')
                    elif mutation == 'deleted':
                        self.source.unlink()
                    elif mutation == 'replaced':
                        self.source.unlink()
                        self.source.write_bytes(before)
                    else:
                        changed = self.root / 'tools/class_compiler.py'
                        changed.write_bytes(b'# changed compiler\n')
                    with self.assertRaises((ValueError, OSError)):
                        capture.verify()
                if mutation == 'added':
                    changed.unlink()
                self.source.write_bytes(before)

    def test_replaced_directory_ancestry_is_not_followed(self):
        with builder.SourceCapture(self.root) as capture:
            capture.read()
            original = self.source.parent
            previous = original.with_name('previous-source')
            original.rename(previous)
            original.symlink_to(previous, target_is_directory=True)
            with self.assertRaises((ValueError, OSError)):
                capture.verify()

    def test_aggregate_and_discovery_limits_precede_content_reads(self):
        for variable in ('SOURCE_BYTE_LIMIT', 'SOURCE_ENTRY_LIMIT', 'SOURCE_MEMBER_LIMIT'):
            with self.subTest(limit=variable), builder.SourceCapture(self.root) as capture:
                with mock.patch.object(builder, variable, 1), \
                     mock.patch.object(builder.os, 'fdopen', side_effect=AssertionError('content read before bounds')):
                    with self.assertRaises(ValueError):
                        capture.read()


class ModuleContracts(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.seed = self.root / 'd-i/debian'
        shutil.copytree(ROOT / 'd-i/debian/scripts', self.seed / 'scripts')
        for name in ('hosts', 'suites'):
            shutil.copytree(ROOT / 'd-i/debian' / name, self.seed / name, dirs_exist_ok=True)
        shutil.copyfile(ROOT / 'd-i/debian/repo.env', self.seed / 'repo.env')

    def test_inventory_is_explicit_complete_and_read_only(self):
        before = {p: p.read_bytes() for p in self.seed.rglob('*') if p.is_file()}
        self.assertGreater(checker.check(self.seed), 0)
        self.assertEqual(before, {p: p.read_bytes() for p in before})
        self.assertFalse((ROOT / 'src').exists())
        self.assertFalse((ROOT / 'tools/generate_installer.py').exists())

    def test_typed_parser_inventory_keeps_awk_out_of_shell_loader(self):
        self.assertEqual(checker.check_data_assets(self.seed), 2)
        bootstrap = (self.seed / 'scripts/common/bootstrap.sh').read_text()
        profiles = (self.seed / 'scripts/common/modules/profiles.sh').read_text()
        credentials = (self.seed / 'scripts/common/credentials.sh').read_text()
        self.assertIn('bootstrap_parser_asset_path', bootstrap)
        self.assertIn('bootstrap_parser_asset_path', profiles)
        self.assertIn('bootstrap_parser_asset_path', credentials)
        self.assertNotIn('bootstrap_module_path "$(bootstrap_repo_file_value scripts/common/credential-data.awk)"', profiles + credentials)

    def test_module_edit_remains_authoritative_and_is_not_repaired(self):
        path = self.seed / 'scripts/common/modules/files-logging.sh'
        path.write_text(path.read_text() + '\n# local administrator edit\n')
        before = path.read_bytes()
        checker.check(self.seed)
        self.assertEqual(path.read_bytes(), before)

    def test_profile_edit_is_read_directly_and_does_not_change_other_hosts(self):
        files = sorted((self.seed / 'hosts/profiles/desktop').glob('*.env'))
        before = {p: p.read_bytes() for p in files}
        path = files[0]
        path.write_text(path.read_text().replace('SIZE_TMPFS_VAR_SPOOL_RSYSLOG_MIB="256"',
                                                'SIZE_TMPFS_VAR_SPOOL_RSYSLOG_MIB="512"'))
        edited = path.read_bytes()
        checker.check(self.seed)
        self.assertEqual(path.read_bytes(), edited)
        self.assertEqual([p for p in files if p.read_bytes() != before[p]], [path])

    def test_invalid_flags_sizes_and_duplicates_are_rejected_without_writes(self):
        path = next((self.seed / 'hosts/profiles/desktop').glob('*.env'))
        original = path.read_text()
        bad = [original.replace('TMPFS_VAR_SPOOL_RSYSLOG="true"', 'TMPFS_VAR_SPOOL_RSYSLOG="maybe"'),
               original.replace('SIZE_TMPFS_VAR_SPOOL_RSYSLOG_MIB="256"', 'SIZE_TMPFS_VAR_SPOOL_RSYSLOG_MIB="0"'),
               original + 'TMPFS_VAR_SPOOL_RSYSLOG="false"\n',
               original.replace('SIZE_TMPFS_VAR_SPOOL_RSYSLOG_MIB="256"', 'SIZE_TMPFS_VAR_SPOOL_RSYSLOG_MIB="$(false)"')]
        for text in bad:
            with self.subTest(text=text[-90:]):
                path.write_text(text)
                with self.assertRaises(ValueError):
                    checker.check(self.seed)
                self.assertEqual(path.read_text(), text)

    def test_orphan_duplicate_and_missing_modules_are_rejected(self):
        orphan = self.seed / 'scripts/common/modules/orphan.sh'
        orphan.write_text('#!/bin/sh\n')
        with self.assertRaises(ValueError): checker.check(self.seed)
        orphan.unlink()
        entry = self.seed / 'scripts/common/lib.sh'
        text = entry.read_text()
        line = next(line for line in text.splitlines() if line.startswith('bootstrap_source_module '))
        entry.write_text(text + line + '\n')
        with self.assertRaises(ValueError): checker.check(self.seed)
        entry.write_text(text)
        (self.seed / 'scripts/common/modules/files-logging.sh').unlink()
        with self.assertRaises(ValueError): checker.check(self.seed)

    def test_symlink_hardlink_and_path_traversal_are_rejected(self):
        path = self.seed / 'scripts/common/modules/files-logging.sh'
        path.unlink()
        path.symlink_to('/etc/passwd')
        with self.assertRaises(ValueError): checker.check(self.seed)
        path.unlink()
        os.link(self.seed / 'scripts/common/credentials.sh', path)
        with self.assertRaises(ValueError): checker.check(self.seed)
        for name in ('../outside.sh', '/etc/passwd', 'scripts/common/../x.sh'):
            with self.assertRaises(ValueError): checker.module_file(self.seed, name)

    def test_invalid_module_syntax_is_rejected(self):
        (self.seed / 'scripts/common/modules/files-logging.sh').write_text('if then\n')
        with self.assertRaises(ValueError): checker.check(self.seed)

    def test_build_and_check_preserve_every_edited_environment_file(self):
        # A full repository copy: edits exist in the actual served files only.
        for name in ('tools', 'd-i'):
            shutil.copytree(ROOT / name, self.root / name, dirs_exist_ok=True,
                            ignore=shutil.ignore_patterns('tests', '__pycache__'))
        files = list(self.seed.rglob('*.env'))
        for path in files:
            path.write_bytes(path.read_bytes() + b'\n# administrator edit must survive publication\n')
        before = {p: (p.read_bytes(), p.stat().st_mode) for p in files}
        generated = {self.seed / name for name in builder.GENERATED}
        source_before = {path.relative_to(self.root): (path.read_bytes(), path.stat().st_mode)
                         for path in self.root.rglob('*') if path.is_file() and path not in generated}
        for args in ([], ['--check']):
            result = subprocess.run([sys.executable, '-B', str(self.root / 'tools/build.py'), *args],
                                    capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(before, {p: (p.read_bytes(), p.stat().st_mode) for p in files})
            self.assertEqual(source_before,
                             {path.relative_to(self.root): (path.read_bytes(), path.stat().st_mode)
                              for path in self.root.rglob('*') if path.is_file() and path not in generated})

class PhaseDispatchContracts(unittest.TestCase):
    """Dispatch only fixture runners; never enter an installer phase."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='phase-dispatch-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.output = self.root / 'arguments'
        self.runner = self.root / 'fixture runner'
        self.runner.write_text('#!/bin/sh\nprintf "%s\\n" "$#" "$@" >"$PHASE_OUTPUT"\nexit "${PHASE_RUNNER_STATUS:-0}"\n')
        self.runner.chmod(0o700)
        (self.root / 'sourcea').mkdir()
        self.state = self.root / 'runtime/bootstrap'
        self.state.mkdir(parents=True)
        self.trace = self.root / 'operations'
        self.shells = [['/bin/dash']]
        if busybox := shutil.which('busybox'):
            self.shells.append([busybox, 'sh'])

    def dispatch(self, shell, phase, source, *, explicit_runner=False, **values):
        self.output.unlink(missing_ok=True)
        bootstrap = ROOT / 'd-i/debian/scripts/common/bootstrap.sh'
        code = '. ' + shlex.quote(str(bootstrap)) + '''
bootstrap_require_seed_base() { printf '%s\\n' "$1"; return "${PHASE_RESOLVE_STATUS:-0}"; }
bootstrap_ensure_repo_env() { return "${PHASE_ENV_STATUS:-0}"; }
bootstrap_repo_join_var() { printf '%s/%s\\n' "$1" "$2"; return "${PHASE_PATH_STATUS:-0}"; }
bootstrap_phase_runner_path() { printf '%s\\n' "$PHASE_RUNNER"; return "${PHASE_RUNNER_PATH_STATUS:-0}"; }
bootstrap_persist_seed_source() { return "${PHASE_PERSIST_STATUS:-0}"; }
bootstrap_fetch_seed_file() { return "${PHASE_FETCH_STATUS:-0}"; }
if bootstrap_run_preseed_phase "$@"; then exit 0; else exit "$?"; fi
'''
        env = {'PATH': '/usr/bin:/bin', 'HOME': str(self.root), 'LC_ALL': 'C',
               'PHASE_OUTPUT': str(self.output), 'PHASE_RUNNER': str(self.runner),
               'INSTALLER_BOOTSTRAP_LIB': str(bootstrap), **values}
        return subprocess.run([*shell, '-eu', '-c', code, 'phase-fixture', phase, source,
                               *([str(self.runner)] if explicit_runner else [])],
                              cwd=self.root, env=env, text=True, capture_output=True, timeout=10)

    def persist(self, shell, source, **values):
        self.trace.unlink(missing_ok=True)
        bootstrap = ROOT / 'd-i/debian/scripts/common/bootstrap.sh'
        code = '. ' + shlex.quote(str(bootstrap)) + '''
install() { printf 'install\\n' >>"$PERSIST_TRACE"; return "${PERSIST_INSTALL_STATUS:-0}"; }
rm() { printf 'cleanup\\n' >>"$PERSIST_TRACE"; return "${PERSIST_CLEANUP_STATUS:-0}"; }
if bootstrap_persist_seed_source "$1"; then exit 0; else exit "$?"; fi
'''
        env = {'PATH': '/usr/bin:/bin', 'HOME': str(self.root), 'LC_ALL': 'C',
               'INSTALLER_RUNTIME_DIR': str(self.state.parent),
               'PERSIST_TRACE': str(self.trace), **values}
        return subprocess.run([*shell, '-eu', '-c', code, 'persistence-fixture', source],
                              cwd=self.root, env=env, text=True, capture_output=True, timeout=10)

    def test_all_phase_arguments_preserve_spaces_and_globs(self):
        for shell in self.shells:
            for phase in ('prepare-context', 'apply', 'early', 'partman', 'late'):
                for source in ('/fixture/source with spaces', str(self.root / 'source[ab]*'),
                               'https://fixture.invalid/repo[ab]*'):
                    with self.subTest(shell=shell, phase=phase, source=source):
                        result = self.dispatch(shell, phase, source)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        arguments = [phase, source] if phase in ('prepare-context', 'apply') else [source]
                        self.assertEqual(self.output.read_text().splitlines(), [str(len(arguments)), *arguments])

    def test_preparation_failure_never_executes_a_stale_runner(self):
        for shell in self.shells:
            for name in ('RESOLVE', 'ENV', 'PATH', 'RUNNER_PATH', 'PERSIST', 'FETCH'):
                with self.subTest(shell=shell, failure=name):
                    result = self.dispatch(shell, 'late', '/fixture/source', **{'PHASE_' + name + '_STATUS': '37'})
                    self.assertEqual(result.returncode, 37, result.stderr)
                    self.assertFalse(self.output.exists())

    def test_runner_status_is_preserved(self):
        for shell in self.shells:
            with self.subTest(shell=shell):
                result = self.dispatch(shell, 'early', '/fixture/source', PHASE_RUNNER_STATUS='23')
                self.assertEqual(result.returncode, 23, result.stderr)

    def test_explicit_runner_skips_default_runner_path_resolution(self):
        for shell in self.shells:
            with self.subTest(shell=shell):
                result = self.dispatch(shell, 'early', '/fixture/source', explicit_runner=True,
                                       PHASE_RUNNER_PATH_STATUS='37')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.output.read_text().splitlines(), ['1', '/fixture/source'])

    def test_real_persistence_setup_failure_never_writes_or_cleans_state(self):
        for shell in self.shells:
            for source in ('/fixture/source', 'https://fixture.invalid/repo'):
                with self.subTest(shell=shell, source=source):
                    result = self.persist(shell, source, PERSIST_INSTALL_STATUS='37')
                    self.assertEqual(result.returncode, 37, result.stderr)
                    self.assertEqual(list(self.state.iterdir()), [])
                    self.assertEqual(self.trace.read_text().splitlines(), ['install'])

    def test_real_persistence_write_failure_keeps_the_other_source(self):
        for shell in self.shells:
            for source, kind, other in (('/fixture/source', 'file', 'url'),
                                        ('https://fixture.invalid/repo', 'url', 'file')):
                with self.subTest(shell=shell, source=source):
                    destination = self.state / ('seed.' + kind)
                    previous = self.state / ('seed.' + other)
                    destination.mkdir()  # Redirection fails even as image root.
                    previous.write_text('retained source\n')
                    try:
                        result = self.persist(shell, source)
                        self.assertNotEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(previous.read_text(), 'retained source\n')
                        self.assertEqual(self.trace.read_text().splitlines(), ['install'])
                    finally:
                        destination.rmdir()
                        previous.unlink()

    def test_real_persistence_cleanup_failure_keeps_its_status(self):
        for shell in self.shells:
            for source, kind in (('/fixture/source', 'file'), ('https://fixture.invalid/repo', 'url')):
                with self.subTest(shell=shell, source=source):
                    result = self.persist(shell, source, PERSIST_CLEANUP_STATUS='41')
                    self.assertEqual(result.returncode, 41, result.stderr)
                    self.assertEqual((self.state / ('seed.' + kind)).read_text(), source + '\n')
                    self.assertEqual(self.trace.read_text().splitlines(), ['install', 'cleanup'])

class PublicationContracts(unittest.TestCase):
    """Unexecuted immutable-candidate fixtures; no serving pointer is touched."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.destination = self.root / ('a' * 64)
        self.products = {'payload.tar.gz': b'fixture archive bytes',
                         'payload.manifest': b'fixture manifest bytes',
                         'frontends/forky.cfg': b'fixture frontend bytes'}

    def test_immutable_publication_is_idempotent_and_rejects_changed_bytes(self):
        publisher.publish_immutable_tree(self.destination, self.products)
        before = {p.relative_to(self.destination): p.read_bytes()
                  for p in self.destination.rglob('*') if p.is_file()}
        publisher.publish_immutable_tree(self.destination, self.products)
        with self.assertRaises(ValueError):
            publisher.publish_immutable_tree(self.destination, {**self.products, 'payload.manifest': b'changed'})
        self.assertEqual(before, {p.relative_to(self.destination): p.read_bytes()
                                  for p in self.destination.rglob('*') if p.is_file()})

    def test_failed_staging_retains_old_release_and_owned_evidence(self):
        publisher.publish_immutable_tree(self.destination, self.products)
        next_destination = self.root / ('b' * 64)
        real_write = publisher._atomic_write_at
        calls = 0

        def fail_second_file(*args):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError('injected publication failure')
            return real_write(*args)

        with mock.patch.object(publisher, '_atomic_write_at', side_effect=fail_second_file):
            with self.assertRaisesRegex(OSError, 'injected publication failure') as failure:
                publisher.publish_immutable_tree(next_destination, self.products)
        self.assertFalse(next_destination.exists())
        retained = list(self.root.glob('.' + next_destination.name + '.staged-*'))
        self.assertEqual(len(retained), 1)
        self.assertEqual(publisher.stat.S_IMODE(retained[0].stat().st_mode), 0o700)
        self.assertIn('retained private candidate: ' + str(retained[0]), failure.exception.__notes__)
        publisher.publish_immutable_tree(self.destination, self.products)

    def test_unsafe_member_and_environment_output_are_rejected(self):
        env = self.root / 'profile.env'
        env.write_bytes(b'KEEP="true"\n')
        with self.assertRaises(ValueError):
            publisher.atomic_write(env, b'bad', 0o644)
        for name in ('../escape', '/escape', 'a/./escape', 'a//escape', 'profile.env'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                publisher.publish_immutable_tree(self.destination, {name: b'bad'})
            self.assertFalse(self.destination.exists())
        self.assertEqual(env.read_bytes(), b'KEEP="true"\n')

    def test_linked_existing_member_is_rejected_without_following_it(self):
        publisher.publish_immutable_tree(self.destination, self.products)
        other = self.root / 'owned-other-file'
        other.write_bytes(b'untouched fixture data')
        path = self.destination / 'payload.manifest'
        path.unlink()
        path.symlink_to(other)
        with self.assertRaises(ValueError):
            publisher.publish_immutable_tree(self.destination, self.products)
        self.assertEqual(other.read_bytes(), b'untouched fixture data')

    def test_symlinked_parent_never_creates_an_outside_directory(self):
        outside = self.root / 'other-owned-tree'
        outside.mkdir()
        alias = self.root / 'alias'
        alias.symlink_to(outside, target_is_directory=True)
        with self.assertRaises((OSError, ValueError)):
            publisher.publish_immutable_tree(alias / 'must-not-exist' / self.destination.name, self.products)
        self.assertEqual(list(outside.iterdir()), [])

    def test_strict_creation_mask_does_not_make_served_children_private(self):
        real_mkdir = publisher.os.mkdir

        def restrictive_mkdir(path, mode=0o777, **kwargs):
            return real_mkdir(path, mode & 0o700, **kwargs)

        with mock.patch.object(publisher.os, 'mkdir', side_effect=restrictive_mkdir):
            publisher.publish_immutable_tree(self.destination, self.products)
        for path in (self.destination, *self.destination.rglob('*')):
            expected = 0o755 if path.is_dir() else 0o644
            self.assertEqual(publisher.stat.S_IMODE(path.stat().st_mode), expected)

    def test_limits_and_prefix_conflicts_fail_before_any_staging(self):
        for limit, value, products in (
                ('MEMBER_LIMIT', 1, self.products),
                ('ENTRY_LIMIT', 2, self.products),
                ('FILE_LIMIT', 1, {'a': b'xx'}),
                ('BYTE_LIMIT', 3, {'a': b'xx', 'b': b'xx'}),
                ('PATH_LIMIT', 2, {'abc': b'x'}),
                ('DEPTH_LIMIT', 1, {'a/b': b'x'})):
            with self.subTest(limit=limit), mock.patch.object(publisher, limit, value):
                with self.assertRaises(ValueError):
                    publisher.publish_immutable_tree(self.destination, products)
            self.assertEqual(list(self.root.iterdir()), [])
        for products in ({'a': b'x', 'a/b': b'y'}, {'a\nb': b'x'}, {'a\\b': b'x'}):
            with self.subTest(products=products), self.assertRaises(ValueError):
                publisher.publish_immutable_tree(self.destination, products)
            self.assertEqual(list(self.root.iterdir()), [])

    def test_unexpected_empty_directory_is_not_part_of_a_completed_candidate(self):
        publisher.publish_immutable_tree(self.destination, self.products)
        (self.destination / 'unexpected-empty-directory').mkdir()
        with self.assertRaises(ValueError):
            publisher.publish_immutable_tree(self.destination, self.products)

    def test_busy_parent_fails_without_waiting_or_creating_a_candidate(self):
        with mock.patch.object(publisher.fcntl, 'flock', side_effect=BlockingIOError('fixture busy')):
            with self.assertRaisesRegex(ValueError, 'parent busy'):
                publisher.publish_immutable_tree(self.destination, self.products)
        self.assertEqual(list(self.root.iterdir()), [])

    def test_preexisting_empty_destination_is_never_replaced(self):
        self.destination.mkdir(mode=0o755)
        identity = self.destination.stat().st_ino
        with self.assertRaises(ValueError):
            publisher.publish_immutable_tree(self.destination, self.products)
        self.assertEqual(self.destination.stat().st_ino, identity)
        self.assertEqual(list(self.destination.iterdir()), [])

    def test_fifo_member_is_pinned_and_rejected_before_content_open(self):
        publisher.publish_immutable_tree(self.destination, self.products)
        member = self.destination / 'payload.manifest'
        member.unlink()
        os.mkfifo(member, 0o600)
        real_open = publisher.os.open

        def refuse_fifo_content(path, flags, *args, **kwargs):
            if path == 'payload.manifest' and not flags & os.O_PATH:
                raise AssertionError('FIFO was opened for content')
            return real_open(path, flags, *args, **kwargs)

        with mock.patch.object(publisher.os, 'open', side_effect=refuse_fifo_content):
            with self.assertRaises(ValueError):
                publisher.publish_immutable_tree(self.destination, self.products)

    def test_atomic_writer_preserves_a_concurrent_destination_edit(self):
        path = self.root / 'preseed.cfg'
        path.write_bytes(b'previous')
        real_verify = publisher._verify_file
        changed = False

        def edit_before_commit(parent, name, data, mode):
            nonlocal changed
            result = real_verify(parent, name, data, mode)
            if name.startswith('.preseed.cfg.staged-') and not changed:
                changed = True
                path.write_bytes(b'concurrent owner edit')
            return result

        with mock.patch.object(publisher, '_verify_file', side_effect=edit_before_commit):
            with self.assertRaisesRegex(ValueError, 'changed before replacement'):
                publisher.atomic_write(path, b'candidate', 0o644)
        self.assertEqual(path.read_bytes(), b'concurrent owner edit')

    def test_atomic_writer_binds_parent_after_ancestry_replacement(self):
        slot = self.root / 'slot'
        slot.mkdir()
        retained = self.root / 'retained-parent'
        outside = self.root / 'outside-owned-fixture'
        outside.mkdir()
        real_write = publisher._atomic_write_at

        def replace_parent(parent, name, data, mode):
            slot.rename(retained)
            slot.symlink_to(outside, target_is_directory=True)
            return real_write(parent, name, data, mode)

        with mock.patch.object(publisher, '_atomic_write_at', side_effect=replace_parent):
            with self.assertRaises(publisher.PublicationOutcomeUnknown):
                publisher.atomic_write(slot / 'preseed.cfg', b'pinned candidate', 0o644)
        self.assertEqual(list(outside.iterdir()), [])
        self.assertEqual((retained / 'preseed.cfg').read_bytes(), b'pinned candidate')

    def test_file_rename_with_failed_parent_sync_has_an_uncertain_result(self):
        path = self.root / 'preseed.cfg'
        path.write_bytes(b'previous')
        real_replace, real_sync = publisher.os.replace, publisher.os.fsync
        replaced = False

        def replace(*args, **kwargs):
            nonlocal replaced
            result = real_replace(*args, **kwargs)
            replaced = True
            return result

        def sync(descriptor):
            if replaced:
                raise OSError('injected post-rename sync failure')
            return real_sync(descriptor)

        with mock.patch.object(publisher.os, 'replace', side_effect=replace), \
                mock.patch.object(publisher.os, 'fsync', side_effect=sync):
            with self.assertRaises(publisher.PublicationOutcomeUnknown):
                publisher.atomic_write(path, b'new candidate', 0o644)
        self.assertEqual(path.read_bytes(), b'new candidate')

    def test_tree_rename_sync_failure_retains_complete_candidate(self):
        real_rename, real_sync = publisher.os.rename, publisher.os.fsync
        renamed = False

        def rename(*args, **kwargs):
            nonlocal renamed
            result = real_rename(*args, **kwargs)
            renamed = True
            return result

        def sync(descriptor):
            if renamed:
                raise OSError('injected post-rename tree sync failure')
            return real_sync(descriptor)

        with mock.patch.object(publisher.os, 'rename', side_effect=rename), \
                mock.patch.object(publisher.os, 'fsync', side_effect=sync):
            with self.assertRaises(publisher.PublicationOutcomeUnknown):
                publisher.publish_immutable_tree(self.destination, self.products)
        self.assertEqual(publisher.stat.S_IMODE(self.destination.stat().st_mode), 0o755)
        self.assertEqual(self.products, {p.relative_to(self.destination).as_posix(): p.read_bytes()
                                       for p in self.destination.rglob('*') if p.is_file()})

    def test_generation_cli_preserves_unknown_outcome_as_a_separate_result(self):
        import io
        diagnostic = io.StringIO()
        with mock.patch.object(builder.sys, 'argv', ['build.py']), \
                mock.patch.object(builder.sys, 'stderr', diagnostic), \
                mock.patch.object(builder, 'build', return_value=(self.destination.name, self.products, {})), \
                mock.patch.object(builder, 'publish_immutable_tree',
                                  side_effect=builder.PublicationOutcomeUnknown('fixture uncertainty')):
            self.assertEqual(builder.main(), 75)
        self.assertIn('do not retry automatically', diagnostic.getvalue())

    def test_generation_cli_keeps_ordinary_failure_distinct(self):
        import io
        diagnostic = io.StringIO()
        with mock.patch.object(builder.sys, 'argv', ['build.py']), \
                mock.patch.object(builder.sys, 'stderr', diagnostic), \
                mock.patch.object(builder, 'build', side_effect=ValueError('fixture invalid data')):
            self.assertEqual(builder.main(), 1)
        self.assertNotIn('outcome unknown', diagnostic.getvalue())

if __name__ == '__main__': unittest.main()
