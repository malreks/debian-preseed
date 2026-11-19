"""The canonical audit includes shared Perl and fails incomplete compilation."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, '/workspace/repository/tools')
from isolation import require_test_isolation
require_test_isolation()

from contextlib import redirect_stdout, redirect_stderr
import hashlib
import io
import json
import runpy
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
AUDITOR = ROOT / 'd-i/debian/tests/audit_codebase.py'


class PerlAuditContractTests(unittest.TestCase):
    def setUp(self):
        self.audit = runpy.run_path(str(AUDITOR))
        self.directory = tempfile.TemporaryDirectory(prefix='perl-audit-fixture-', dir='/workspace')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def checkout(self, source: str) -> Path:
        for name in self.audit['REQUIRED_SCOPES']:
            folder = self.root / name
            folder.mkdir(parents=True)
            (folder / 'fixture-data').write_text('owned fixture data\n', encoding='utf-8')
        renderer = self.root / 'd-i/debian/scripts/common/render.pl'
        renderer.parent.mkdir()
        renderer.write_text(source, encoding='utf-8')
        return renderer

    def run_audit(self, mode: list[str] | None = None) -> tuple[int, dict]:
        report = self.root / 'audit.json'
        globals_ = self.audit['main'].__globals__
        errors = io.StringIO()
        with mock.patch.dict(globals_, {'ROOT': self.root}), mock.patch.object(
                sys, 'argv', [str(AUDITOR), '--perl-only', *(mode or ['--source-only']), '--output', str(report)]), \
                redirect_stdout(io.StringIO()), redirect_stderr(errors):
            status = self.audit['main']()
        self.last_stderr = errors.getvalue()
        return status, json.loads(report.read_text(encoding='utf-8')) if report.is_file() else {}

    def prepared_inputs(self, *, unavailable_import: bool = False) -> tuple[list[str], Path, Path, bytes]:
        """Data fixture for provenance/staging; no alternate rendering routine."""
        renderer = self.checkout('use strict; use warnings; use AuditFixture::Typed; 1;\n')
        module = self.root / 'd-i/debian/hooks/target/usr/local/lib/common/perl5/site_perl/audit/AuditFixture/Typed.pm.tmpl'
        module.parent.mkdir(parents=True)
        imports = 'use AuditSyntaxFixture::AbsentDependency20261119; ' if unavailable_import else ''
        module.write_text('package AuditFixture::Typed; use strict; use warnings; ' + imports
                          + 'use constant LIMIT => __INSTALLER_SOFTWARE_APT_REPO_LOCAL_DEB_MAXIMUM_BYTES__; 1;\n')
        # These are explicit test bytes for two separately supplied products;
        # production products are created only by prepare_syntax_fixture.
        published_bytes = ('package AuditFixture::Typed; use strict; use warnings; ' + imports
                           + 'use constant LIMIT => 12; 1;\n').encode()
        directory = tempfile.TemporaryDirectory(prefix='perl-audit-products-', dir='/workspace')
        self.addCleanup(directory.cleanup)
        fixture = Path(directory.name)
        prepared = fixture / 'prepared'
        source = prepared / 'source'
        inputs = prepared / 'inputs'
        inputs.mkdir(parents=True)
        manifest_rows = []
        total = 0
        for path in (renderer, module):
            member = path.relative_to(self.root / 'd-i/debian').as_posix()
            data = path.read_bytes()
            target = source / member
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            total += len(data)
            manifest_rows.append(f'{len(data)}\t{hashlib.sha256(data).hexdigest()}\t{member}\n')
        (prepared / 'render.pl').write_bytes(renderer.read_bytes())
        manifest = ('format=3\n' + ''.join(manifest_rows)).encode('ascii')
        (inputs / 'payload.manifest').write_bytes(manifest)
        archive = b'owned provenance fixture bytes; actual replay is tested separately\n'
        frontend = self.root / 'd-i/forky'
        (frontend / 'payload.manifest').write_bytes(manifest)
        (frontend / 'payload.tar.gz').write_bytes(archive)
        archive_hash = hashlib.sha256(archive).hexdigest()
        manifest_hash = hashlib.sha256(manifest).hexdigest()
        identity = '/owned-perl-audit-fixture'
        (prepared / 'identity').write_text(f'verified-v1 {archive_hash} {manifest_hash} {identity}\n')
        published = fixture / 'perl/audit/AuditFixture/Typed.pm'
        published.parent.mkdir(parents=True)
        published.write_bytes(published_bytes)
        source_member = module.relative_to(self.root / 'd-i/debian').as_posix()
        (inputs / 'published-assets.tsv').write_text(f'{source_member}\t{published}\t0644\n')
        (prepared / 'receipt.json').write_text(json.dumps({
            'format': 2, 'members': 2, 'input_bytes': total, 'rendered_files': 0,
            'rendered_bytes': 0, 'published_perl_files': 1,
            'source_archive_sha256': archive_hash, 'source_manifest_sha256': manifest_hash,
            'source_identity': identity,
        }) + '\n')
        mode = ['--rendered-root', str(source), '--published-assets', str(inputs / 'published-assets.tsv'),
                '--source-manifest', str(inputs / 'payload.manifest')]
        return mode, module, published, published_bytes

    def test_real_shared_renderer_and_role_owned_modules_are_in_scope(self):
        scopes = self.audit['source_scopes'](ROOT)
        renderer = ROOT / 'd-i/debian/scripts/common/render.pl'
        self.assertIn(renderer, scopes['d-i/debian/scripts'])
        for suite in ('forky', 'trixie'):
            self.assertTrue(scopes[f'd-i/{suite}/hooks/target'])
        roots = self.audit['perl_library_paths'](ROOT)
        self.assertIn(ROOT / 'd-i/debian/hooks/target/usr/local/lib/common/perl5/site_perl/runtime', roots)
        self.assertIn(ROOT / 'd-i/debian/hooks/target/usr/local/lib/desktop/perl5/site_perl/labwc-security-action', roots)

    def test_missing_or_empty_scope_cannot_produce_an_empty_success(self):
        with self.assertRaisesRegex(ValueError, 'expected source scope'):
            self.audit['source_scopes'](self.root)
        self.checkout('use strict; use warnings; 1;\n')
        for path in (self.root / 'd-i/trixie/hooks/target').iterdir():
            path.unlink()
        with self.assertRaisesRegex(ValueError, 'empty expected source scope'):
            self.audit['source_scopes'](self.root)

    def test_regular_input_rejects_fifo_without_waiting_for_a_writer(self):
        path = self.root / 'not-a-regular-source'
        self.audit['os'].mkfifo(path, 0o600)
        with self.assertRaisesRegex(ValueError, 'unsafe or oversized'):
            self.audit['read_regular'](path)

    def test_missing_compiler_is_nonzero_and_not_a_pass(self):
        self.checkout('use strict; use warnings; 1;\n')
        with mock.patch.object(self.audit['os'], 'access', return_value=False):
            status, report = self.run_audit()
        self.assertEqual(status, 1)
        self.assertFalse(report['success'])
        self.assertEqual(report['check_counts'], {'blocked-tool': 1})

    def test_missing_real_dependency_is_nonzero_and_not_a_syntax_pass(self):
        self.checkout('use strict; use warnings; use AuditSyntaxFixture::AbsentDependency20261119; 1;\n')
        status, report = self.run_audit()
        self.assertEqual(status, 1)
        self.assertFalse(report['success'])
        self.assertEqual(report['check_counts'], {'blocked-dependency': 1})
        self.assertIn('AuditSyntaxFixture/AbsentDependency20261119.pm', report['files'][0]['detail'])

    def test_full_program_regex_error_is_not_hidden_by_an_unrelated_placeholder(self):
        self.checkout("use strict; use warnings;\n"
                      "my $unused = '__INSTALLER_PATH_DIR_USR__';\n"
                      "my $name = 'sample';\n"
                      r"$name =~ /\A[A-Za-z0-9_./@+ -]+\z/;" + '\n')
        status, report = self.run_audit()
        self.assertEqual(status, 1)
        self.assertEqual(report['check_counts'], {'fail': 1})
        self.assertIn('Unmatched [', report['files'][0]['detail'])

    def test_taint_shebang_is_preserved_by_native_compilation(self):
        self.checkout('#!/usr/bin/perl -T\nuse strict; use warnings; 1;\n')
        status, report = self.run_audit()
        self.assertEqual(status, 0, report)
        self.assertTrue(report['success'])
        self.assertEqual(report['check_counts'], {'pass': 1})
        self.assertEqual(self.audit['perl_shebang_flags']('#!__INSTALLER_PATH_DIR_USR__/bin/perl -T'), ['-T'])
        with self.assertRaisesRegex(ValueError, 'unsupported Perl shebang'):
            self.audit['perl_shebang_flags']('#!/usr/bin/perl -MUnexpected')

    def test_rendered_gate_uses_exact_published_module_bytes_and_real_imports(self):
        mode, module, published, data = self.prepared_inputs()
        status, report = self.run_audit(mode)
        self.assertEqual(status, 0, self.last_stderr)
        self.assertEqual(report['check_counts'], {'pass': 2})
        self.assertEqual(report['perl_source_count'], 2)
        self.assertEqual(report['perl_provenance']['mode'], 'canonical-rendered')
        record = next(item for item in report['files'] if item['path'].endswith('Typed.pm.tmpl'))
        self.assertEqual(record['perl_source']['selected_sha256'], hashlib.sha256(data).hexdigest())
        self.assertEqual(record['perl_source']['source_sha256'], hashlib.sha256(module.read_bytes()).hexdigest())
        self.assertTrue(record['perl_source']['compile_path'].endswith('/AuditFixture/Typed.pm'))

    def test_source_only_mode_keeps_required_rendering_a_failure(self):
        self.prepared_inputs()
        status, report = self.run_audit()
        self.assertEqual(status, 1)
        self.assertFalse(report['success'])
        self.assertEqual(report['perl_provenance']['mode'], 'strict-source-diagnostic')
        self.assertEqual(report['check_counts'], {'template-needs-render': 2})

    def test_rendered_gate_rejects_stale_original_source_before_compiling(self):
        mode, module, _published, _data = self.prepared_inputs()
        module.write_bytes(module.read_bytes() + b'# changed after payload capture\n')
        compiler = mock.Mock(side_effect=AssertionError('stale input reached the compiler'))
        with mock.patch.dict(self.audit['main'].__globals__, {'native_syntax': compiler}):
            status, report = self.run_audit(mode)
        self.assertEqual(status, 1)
        self.assertFalse(report)
        compiler.assert_not_called()
        self.assertIn('stale or missing Perl source', self.last_stderr)

    def test_rendered_gate_rejects_an_altered_renderer_before_compiling(self):
        mode, _module, _published, _data = self.prepared_inputs()
        (Path(mode[1]).parent / 'render.pl').write_text('use strict; 1;\n')
        compiler = mock.Mock(side_effect=AssertionError('altered renderer reached the compiler'))
        with mock.patch.dict(self.audit['main'].__globals__, {'native_syntax': compiler}):
            status, report = self.run_audit(mode)
        self.assertEqual(status, 1)
        self.assertFalse(report)
        compiler.assert_not_called()
        self.assertIn('stale or altered installer renderer', self.last_stderr)

    def test_rendered_gate_rejects_unresolved_published_tokens_before_compiling(self):
        mode, module, published, _data = self.prepared_inputs()
        published.write_bytes(module.read_bytes())
        compiler = mock.Mock(side_effect=AssertionError('unrendered token reached the compiler'))
        with mock.patch.dict(self.audit['main'].__globals__, {'native_syntax': compiler}):
            status, report = self.run_audit(mode)
        self.assertEqual(status, 1)
        self.assertFalse(report)
        compiler.assert_not_called()
        self.assertIn('unresolved installer token', self.last_stderr)

    def test_rendered_gate_keeps_missing_real_dependency_nonzero(self):
        mode, _module, _published, _data = self.prepared_inputs(unavailable_import=True)
        status, report = self.run_audit(mode)
        self.assertEqual(status, 1, self.last_stderr)
        self.assertFalse(report['success'])
        self.assertEqual(report['check_counts'], {'blocked-dependency': 2})


if __name__ == '__main__':
    unittest.main()
