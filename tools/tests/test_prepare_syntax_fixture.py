"""Containment, artifact integrity and ownership handoff in the reviewed guest."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from isolation import require_test_isolation
require_test_isolation()

import hashlib
import io
import json
import tarfile
import tempfile
import unittest

from prepare_syntax_fixture import REPOSITORY, _capture_payload, prepare_syntax_fixture


class SyntaxFixturePreparationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='syntax-preparation-test-', dir='/workspace')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.renderer = REPOSITORY / 'd-i/debian/scripts/common/render.pl'

    def test_public_api_rejects_outputs_outside_workspace_and_inside_checkout(self):
        for output in (Path('relative-output'), Path('/workspace'),
                       Path('/tmp') / self.root.name,
                       REPOSITORY / self.root.name,
                       self.root / 'uncreated/../escaped'):
            with self.subTest(output=str(output)), self.assertRaises(ValueError):
                prepare_syntax_fixture(output, 'forky', 'desktop', ownership_runtime='posix')
        self.assertEqual(list(self.root.iterdir()), [])
        self.assertFalse((Path('/tmp') / self.root.name).exists())
        self.assertFalse((REPOSITORY / self.root.name).exists())

    def test_existing_outputs_and_symlinks_preserve_previous_entries(self):
        protected = self.root / 'protected'
        protected.mkdir(mode=0o700)
        sentinel = protected / 'sentinel'
        sentinel.write_bytes(b'previous fixture bytes\n')
        ordinary = self.root / 'ordinary-file'
        ordinary.write_bytes(b'previous ordinary bytes\n')
        link = self.root / 'output-link'
        link.symlink_to(protected, target_is_directory=True)
        dangling = self.root / 'dangling-output'
        dangling.symlink_to(self.root / 'absent', target_is_directory=True)
        for output in (ordinary, protected, link, dangling):
            before = output.lstat()
            with self.subTest(output=output.name), self.assertRaises(FileExistsError):
                prepare_syntax_fixture(output, 'forky', 'desktop', ownership_runtime='posix')
            after = output.lstat()
            self.assertEqual((after.st_ino, after.st_mode), (before.st_ino, before.st_mode))
        self.assertEqual(sentinel.read_bytes(), b'previous fixture bytes\n')
        self.assertEqual(ordinary.read_bytes(), b'previous ordinary bytes\n')
        self.assertEqual(list(protected.iterdir()), [sentinel])
        self.assertTrue(link.is_symlink())
        self.assertTrue(dangling.is_symlink())

    def test_output_ancestors_must_be_direct_and_not_group_writable(self):
        unsafe = self.root / 'writable-parent'
        unsafe.mkdir(mode=0o700)
        unsafe.chmod(0o770)
        protected = self.root / 'direct-parent'
        protected.mkdir(mode=0o700)
        alias = self.root / 'parent-alias'
        alias.symlink_to(protected, target_is_directory=True)
        for parent in (unsafe, alias):
            with self.subTest(parent=parent.name), self.assertRaisesRegex(ValueError, 'unsafe fixture output ancestor'):
                prepare_syntax_fixture(parent / 'output', 'forky', 'desktop', ownership_runtime='posix')
        self.assertEqual(list(unsafe.iterdir()), [])
        self.assertEqual(list(protected.iterdir()), [])
        self.assertTrue(alias.is_symlink())

    def captured_artifacts(self, *, damaged_member=False, damaged_manifest=False,
                          stale_renderer=False, stale_ownership=False):
        """Use actual shipped bytes/rows, with one explicit fault per fixture.

        The small archive keeps the production renderer, ownership support and
        repo.env entries. No parser, integrity check or producer is mocked; the
        positive control proves these data fixtures reach the acceptance gate.
        """
        names = ('repo.env', 'scripts/common/render.pl', 'scripts/common/lifecycle.sh',
                 'scripts/common/modules/target-publication.sh',
                 'hooks/installer/base-stage.d/00rendertarget')
        shipped = REPOSITORY / 'd-i/forky'
        manifest_lines = (shipped / 'payload.manifest').read_text(encoding='ascii').splitlines()
        self.assertEqual(manifest_lines[0], 'format=3')
        rows = {fields[2]: fields for fields in
                (line.split('\t') for line in manifest_lines[1:]) if fields[2] in names}
        self.assertEqual(set(rows), set(names))
        members = {}
        with tarfile.open(shipped / 'payload.tar.gz', 'r:gz') as archive:
            for name in names:
                info = archive.getmember(name)
                self.assertTrue(info.isfile())
                self.assertLessEqual(info.size, 16 * 1024 * 1024)
                stream = archive.extractfile(info)
                self.assertIsNotNone(stream)
                with stream:
                    members[name] = stream.read(16 * 1024 * 1024 + 1)
                self.assertEqual(rows[name][:2], [str(len(members[name])),
                                                hashlib.sha256(members[name]).hexdigest()])
        self.assertEqual(members['scripts/common/render.pl'], self.renderer.read_bytes())
        original = dict(members)
        if stale_renderer:
            members['scripts/common/render.pl'] += b'\n# Stale private fixture revision.\n'
            data = members['scripts/common/render.pl']
            rows['scripts/common/render.pl'] = [str(len(data)), hashlib.sha256(data).hexdigest(),
                                                'scripts/common/render.pl']
        if stale_ownership:
            member = 'scripts/common/modules/target-publication.sh'
            members[member] += b'\n# Stale private ownership fixture revision.\n'
            data = members[member]
            rows[member] = [str(len(data)), hashlib.sha256(data).hexdigest(), member]
        if damaged_member:
            members['repo.env'] = b'!' + members['repo.env'][1:]
        if damaged_manifest:
            rows['repo.env'][1] = '0' * 64
        artifacts = self.root / 'artifacts'
        artifacts.mkdir(mode=0o700)
        with tarfile.open(artifacts / 'payload.tar.gz', 'w:gz', format=tarfile.USTAR_FORMAT) as archive:
            for name in names:
                data = members[name]
                info = tarfile.TarInfo(name)
                info.size = len(data)
                info.mode = 0o644
                archive.addfile(info, io.BytesIO(data))
        (artifacts / 'payload.manifest').write_text(
            'format=3\n' + ''.join('\t'.join(rows[name]) + '\n' for name in names), encoding='ascii')
        destination = self.root / 'captured'
        destination.mkdir(mode=0o700)
        return artifacts, destination, original

    def test_exact_shipped_member_data_is_accepted(self):
        artifacts, destination, original = self.captured_artifacts()
        manifest, archive_hash, manifest_hash, count = _capture_payload(artifacts, destination, self.renderer)
        self.assertEqual(count, 5)
        self.assertEqual(manifest, (artifacts / 'payload.manifest').read_bytes())
        self.assertEqual(archive_hash, hashlib.sha256((artifacts / 'payload.tar.gz').read_bytes()).hexdigest())
        self.assertEqual(manifest_hash, hashlib.sha256(manifest).hexdigest())
        for name, data in original.items():
            self.assertEqual((destination / name).read_bytes(), data)

    def assert_no_producer_outputs(self):
        self.assertFalse((self.root / 'map-producers.log').exists())
        self.assertFalse((self.root / 'renderer.log').exists())
        self.assertFalse((self.root / 'perl').exists())
        self.assertFalse((self.root / 'ownership').exists())

    def test_corrupted_archive_member_is_rejected_at_capture(self):
        artifacts, destination, _original = self.captured_artifacts(damaged_member=True)
        with self.assertRaisesRegex(ValueError, 'captured member digest differs'):
            _capture_payload(artifacts, destination, self.renderer)
        self.assertEqual(list(destination.iterdir()), [])
        self.assert_no_producer_outputs()

    def test_corrupted_manifest_identity_is_rejected_at_capture(self):
        artifacts, destination, _original = self.captured_artifacts(damaged_manifest=True)
        with self.assertRaisesRegex(ValueError, 'captured member digest differs'):
            _capture_payload(artifacts, destination, self.renderer)
        self.assertEqual(list(destination.iterdir()), [])
        self.assert_no_producer_outputs()

    def test_self_consistent_stale_renderer_is_rejected_at_capture(self):
        artifacts, destination, original = self.captured_artifacts(stale_renderer=True)
        with self.assertRaisesRegex(ValueError, 'payload contains a stale renderer'):
            _capture_payload(artifacts, destination, self.renderer)
        self.assertNotEqual((destination / 'scripts/common/render.pl').read_bytes(),
                            original['scripts/common/render.pl'])
        self.assertEqual(self.renderer.read_bytes(), original['scripts/common/render.pl'])
        self.assert_no_producer_outputs()

    def test_self_consistent_stale_ownership_importer_is_rejected_at_capture(self):
        artifacts, destination, original = self.captured_artifacts(stale_ownership=True)
        with self.assertRaisesRegex(ValueError, 'payload contains stale ownership support'):
            _capture_payload(artifacts, destination, self.renderer)
        member = 'scripts/common/modules/target-publication.sh'
        self.assertNotEqual((destination / member).read_bytes(), original[member])
        self.assertEqual((REPOSITORY / 'd-i/debian' / member).read_bytes(), original[member])
        self.assert_no_producer_outputs()

    def test_complete_desktop_payload_commits_all_publications_with_explicit_posix_runtime(self):
        output = self.root / 'complete-desktop'
        result = prepare_syntax_fixture(output, 'forky', 'desktop', ownership_runtime='posix')
        self.assertEqual(json.loads((output / 'report.json').read_text(encoding='utf-8')), result)
        handoff = result['ownership']
        self.assertEqual(handoff['result'], 'passed')
        self.assertEqual(handoff['runtime']['name'], 'posix')
        self.assertEqual(handoff['runtime']['shell']['command'], ['/bin/dash'])
        self.assertEqual(handoff['runtime']['awk']['command'], ['/usr/bin/awk'])
        self.assertFalse(handoff['busybox_validation'])
        self.assertFalse(handoff['runtime']['busybox_validation'])
        published = Path(result['published_assets']).read_bytes().splitlines()
        self.assertEqual(len(published), result['receipt_data']['published_perl_files'])
        self.assertGreater(len(published), 1)
        self.assertEqual(handoff['rows'], len(published))
        expected = []
        for row in published:
            source, target, mode = row.split(b'\t')
            self.assertTrue(source.startswith(b'hooks/target/'))
            self.assertTrue(Path(target.decode('ascii')).is_relative_to(output / 'perl'))
            self.assertTrue(Path(target.decode('ascii')).is_file())
            self.assertEqual(mode, b'0644')
            expected.append(b'\t'.join((target, source, b'plain', b'hook-base-00rendertarget', mode)))
        for field in ('converted_batch', 'journal', 'snapshot'):
            path = Path(handoff[field])
            self.assertTrue(path.is_relative_to(output))
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(path.stat().st_nlink, 1)
            actual = path.read_bytes().splitlines()
            if field == 'snapshot':
                self.assertEqual(sorted(actual), sorted(expected))
            else:
                self.assertEqual(actual, expected)
        self.assertEqual(set(handoff['source_sha256']), {
            'scripts/common/lifecycle.sh', 'scripts/common/modules/target-publication.sh',
            'hooks/installer/base-stage.d/00rendertarget'})


if __name__ == '__main__':
    unittest.main()
