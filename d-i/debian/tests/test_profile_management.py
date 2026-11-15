"""Profile candidates and private source transactions; isolated execution only.

The compiler consumes captured data. Publication cases use a private tree and a
mock capture verifier, with real descriptor publication and injected failures.
They do not exercise native installation, partitioning or target services.
"""
from __future__ import annotations

# Check the prepared disposable-image boundary before importing the tool.
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from isolation import require_test_isolation
require_test_isolation()

from contextlib import contextmanager
import importlib.util
import json
import stat
import tempfile
import unittest
from unittest.mock import Mock, patch

SPEC = importlib.util.spec_from_file_location('preseed_profile_tool', ROOT / 'tools/profile.py')
profile = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = profile
SPEC.loader.exec_module(profile)


def apply_changes(sources, changes):
    return {**{member: data for member, data in sources.items() if member not in changes},
            **{member: data for member, data in changes.items() if data is not None}}


class ProfileManagementTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with profile.SourceCapture(ROOT) as capture:
            cls.sources, _compiler = capture.read()
            capture.verify()
        cls.paths = profile.selectors(cls.sources['repo.env'].decode(), profile.SUITES[0])
        registered = {item['id'] for item in json.loads(cls.sources[cls.paths['FILE_SELECTION_REGISTRY']])['profiles']}
        cls.hostname = next(name for name in (f'z{number:04d}' for number in range(10000)) if all(
            f'{filesystem}-{tag}-{name}{suffix}' not in registered
            for filesystem in ('btrfs', 'f2fs')
            for tag in ('de', 'srv') for suffix in ('', '-duo', '-trio')))
        additions = profile.candidate(cls.sources, 'btrfs', 'desktop', ['normal', 'duo', 'trio'], cls.hostname)
        cls.sources = apply_changes(cls.sources, additions)
        cls.base = 'btrfs-de-' + cls.hostname
        cls.group = [cls.base, cls.base + '-duo', cls.base + '-trio']

    def test_single_variant_retains_normal_other_variant_templates_and_shared_data(self):
        changes = profile.deletion_candidate(self.sources, [self.base + '-trio'])
        self.assertEqual(sum(data is None for data in changes.values()), 3)
        remaining = apply_changes(self.sources, changes)
        registry = json.loads(remaining[self.paths['FILE_SELECTION_REGISTRY']])
        registered = {item['id'] for item in registry['profiles']}
        self.assertIn(self.base, registered)
        self.assertIn(self.base + '-duo', registered)
        self.assertNotIn(self.base + '-trio', registered)
        for member, data in self.sources.items():
            if member not in changes:
                self.assertEqual(remaining[member], data)

    def test_normal_is_protected_when_either_variant_would_remain(self):
        for selected in ([self.base], [self.base, self.base + '-duo'], [self.base, self.base + '-trio']):
            with self.subTest(selected=selected), self.assertRaisesRegex(ValueError, 'variants first'):
                profile.deletion_candidate(self.sources, selected)

    def test_group_deletion_compiles_and_removes_both_suite_classes(self):
        changes = profile.deletion_candidate(self.sources, self.group)
        self.assertEqual(sum(data is None for data in changes.values()), 9)
        remaining = apply_changes(self.sources, changes)
        for suite in profile.SUITES:
            paths = profile.selectors(remaining['repo.env'].decode(), suite)
            for identifier in self.group:
                self.assertNotIn(paths['DIR_CLASSES_PROFILE_DESKTOP'] + '/' + identifier + '.cfg', remaining)

    def test_invalid_unknown_and_duplicate_ids_are_rejected(self):
        for selected in ([], ['../../repo'], ['shared'], ['btrfs-de-zzzzz'], [self.group[1], self.group[1]]):
            with self.subTest(selected=selected), self.assertRaises(ValueError):
                profile.deletion_candidate(self.sources, selected)

    def test_reserved_suffix_cannot_turn_a_new_normal_profile_into_multiboot(self):
        for hostname in ('duo', 'trio'):
            with self.subTest(hostname=hostname), self.assertRaisesRegex(ValueError, 'reserved profile suffixes'):
                profile.candidate(self.sources, 'f2fs', 'server', ['normal'], hostname)

    def test_missing_member_and_remaining_fixed_caller_fail_before_writes(self):
        selected = self.base + '-trio'
        changes = profile.deletion_candidate(self.sources, [selected])
        missing = next(member for member, data in changes.items() if data is None and member.endswith('.cfg'))
        with self.assertRaisesRegex(ValueError, 'missing or shared'):
            profile.deletion_candidate({key: value for key, value in self.sources.items() if key != missing}, [selected])
        sources = dict(self.sources)
        token = self.base.upper().replace('-', '_') + '_TRIO'
        sources['scripts/profile-reference-fixture.sh'] = (': "${FILE_HOST_PROFILE_' + token + '}"\n').encode()
        with self.assertRaisesRegex(ValueError, 'remaining source references'):
            profile.deletion_candidate(sources, [selected])

    def test_selector_aliases_for_deleted_members_are_removed_together(self):
        sources = dict(self.sources)
        token = self.base.upper().replace('-', '_') + '_TRIO'
        sources['repo.env'] += ('FILE_PROFILE_DELETE_ALIAS="${FILE_HOST_PROFILE_' + token + '}"\n').encode()
        changes = profile.deletion_candidate(sources, [self.base + '-trio'])
        self.assertNotIn(b'FILE_PROFILE_DELETE_ALIAS=', changes['repo.env'])

    @contextmanager
    def private_publication(self, changes):
        # The isolation gate proves that this default temporary root is private.
        with tempfile.TemporaryDirectory(prefix='profile-management-') as temporary:
            root = Path(temporary)
            capture = Mock(spec=['verify'])
            with patch.object(profile, 'ROOT', root):
                for member in changes:
                    path = self.fixture_path(root, member)
                    path.parent.mkdir(parents=True, exist_ok=True)
                    if member in self.sources:
                        path.write_bytes(self.sources[member])
                        path.chmod(0o640)
                with profile.BuildOwnership(root):
                    yield root, capture

    def fixture_path(self, root, member):
        if member.startswith(self.paths['DIR_FRONTENDS'] + '/'):
            return root / self.paths['DIR_REPO_DI'] / member.removeprefix(self.paths['DIR_FRONTENDS'] + '/')
        return root / self.paths['DIR_REPO_DEBIAN'] / member

    def recoveries(self, root):
        return list((root / self.paths['DIR_REPO_BUILD_STATE']).glob('profile-*'))

    def assert_original_files(self, root, changes):
        for member in changes:
            path = self.fixture_path(root, member)
            if member in self.sources:
                self.assertEqual(path.read_bytes(), self.sources[member])
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o640)
            else:
                self.assertFalse(path.exists())

    def test_delete_success_removes_variants_before_normal_and_cleans_recovery(self):
        changes = profile.deletion_candidate(self.sources, self.group)
        written = []
        real_write = profile.source_write

        def record(edit, data):
            written.append((edit.member, data))
            return real_write(edit, data)

        with self.private_publication(changes) as (root, capture), patch.object(profile, 'source_write', record):
            profile.publish(changes, self.sources, self.paths, capture)
            deleted = [Path(member).stem for member, data in written if data is None]
            self.assertEqual(deleted[-3:], [self.base] * 3)
            for member, data in changes.items():
                path = self.fixture_path(root, member)
                if data is None:
                    self.assertFalse(path.exists())
                else:
                    self.assertEqual(path.read_bytes(), data)
            self.assertFalse(self.recoveries(root))

    def test_creation_can_publish_authored_environment_and_registry(self):
        changes = profile.candidate(self.sources, 'f2fs', 'server', ['normal', 'duo', 'trio'], self.hostname)
        with self.private_publication(changes) as (root, capture):
            profile.publish(changes, self.sources, self.paths, capture)
            for member, data in changes.items():
                self.assertEqual(self.fixture_path(root, member).read_bytes(), data)
            self.assertFalse(self.recoveries(root))

    def test_known_failure_restores_prior_bytes_modes_and_absence(self):
        candidates = [profile.deletion_candidate(self.sources, self.group),
                      profile.candidate(self.sources, 'f2fs', 'server', ['normal', 'duo'], self.hostname)]
        for changes in candidates:
            with self.subTest(deletion=any(data is None for data in changes.values())):
                real_write = profile.source_write
                count = 0

                def fail_once(edit, data):
                    nonlocal count
                    count += 1
                    if count == 2:
                        raise OSError('injected failure before mutation')
                    return real_write(edit, data)

                with self.private_publication(changes) as (root, capture), patch.object(profile, 'source_write', fail_once):
                    with self.assertRaisesRegex(OSError, 'injected failure'):
                        profile.publish(changes, self.sources, self.paths, capture)
                    self.assert_original_files(root, changes)
                    self.assertFalse(self.recoveries(root))

    def test_other_writer_cannot_acquire_the_profile_lock(self):
        changes = profile.deletion_candidate(self.sources, self.group)
        with self.private_publication(changes) as (root, _capture):
            with self.assertRaises(BlockingIOError), profile.BuildOwnership(root):
                self.fail('a second writer acquired the profile lock')
            self.assert_original_files(root, changes)

    def test_symlink_member_is_refused_without_touching_its_referent(self):
        changes = profile.deletion_candidate(self.sources, self.group)
        with self.private_publication(changes) as (root, capture):
            sentinel = root / 'sentinel'
            sentinel.write_bytes(b'private fixture referent\n')
            member = next(member for member, data in changes.items() if data is None)
            path = self.fixture_path(root, member)
            path.unlink()
            path.symlink_to(sentinel)
            with self.assertRaisesRegex(ValueError, 'single-link regular file'):
                profile.publish(changes, self.sources, self.paths, capture)
            self.assertEqual(sentinel.read_bytes(), b'private fixture referent\n')

    def test_uncertain_mutation_retains_durable_evidence_without_retry(self):
        changes = profile.deletion_candidate(self.sources, self.group)
        real_write = profile.source_write
        count = 0

        def uncertain(edit, data):
            nonlocal count
            count += 1
            real_write(edit, data)
            raise profile.PublicationOutcomeUnknown('injected uncertain postcondition')

        with self.private_publication(changes) as (root, capture), patch.object(profile, 'source_write', uncertain):
            with self.assertRaisesRegex(profile.PublicationOutcomeUnknown, 'retain'):
                profile.publish(changes, self.sources, self.paths, capture)
            self.assertEqual(count, 1)
            recovery, = self.recoveries(root)
            manifest = json.loads((recovery / 'manifest.json').read_bytes())
            self.assertEqual(len(manifest['edits']), len(changes))
            originals = {str(self.fixture_path(root, member).relative_to(root)): data
                         for member, data in self.sources.items() if member in changes}
            for record in manifest['edits']:
                self.assertIsNotNone(record['backup'])
                self.assertEqual((recovery / record['backup']).read_bytes(), originals[record['path']])

    def test_replacement_during_rollback_is_preserved_with_recovery(self):
        changes = profile.deletion_candidate(self.sources, self.group)
        real_write = profile.source_write
        first = None

        def replace_before_failure(edit, data):
            nonlocal first
            if first is None:
                first = edit.path
                return real_write(edit, data)
            first.write_bytes(b'concurrent replacement\n')
            raise OSError('injected concurrent replacement')

        with self.private_publication(changes) as (root, capture), patch.object(profile, 'source_write', replace_before_failure):
            with self.assertRaisesRegex(profile.PublicationOutcomeUnknown, 'rollback could not be proved'):
                profile.publish(changes, self.sources, self.paths, capture)
            self.assertEqual(first.read_bytes(), b'concurrent replacement\n')
            self.assertEqual(len(self.recoveries(root)), 1)


if __name__ == '__main__':
    unittest.main()
