"""Class query regression fixtures; execute only in the reviewed private boundary."""
from __future__ import annotations

# Refuse host execution before loading repository modules or fixture code.
from pathlib import Path as _IsolationPath
import sys as _isolation_sys
_isolation_sys.path.insert(0, str(_IsolationPath(__file__).resolve().parents[1]))
from isolation import require_test_isolation as _require_test_isolation
_require_test_isolation()

import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('class_query_checker', ROOT / 'tools/post_change_check.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class ClassQueryContract(unittest.TestCase):
    def test_retired_selector_fails_in_a_predicate_and_in_a_list_wrapper(self):
        for source in (
                'if installer_selected_class_reference_is_selected service/web 2>/dev/null; then :; fi\n',
                'installer_class_selected_any role/desktop/full service/web || exit 0\n',
                'software_run_selected_app "role/desktop/full service/web" label worker result\n'):
            with self.subTest(source=source):
                errors, counts = [], {}
                checker._check_class_queries('fixture.sh', source,
                                             {'forky': {'role/desktop/full'},
                                              'trixie': {'role/desktop/full'}}, errors, counts)
                self.assertEqual(len(errors), 1)
                self.assertIn("'service/web'", errors[0])
                self.assertIn('forky, trixie', errors[0])

    def test_registered_nested_classes_and_physical_line_numbers(self):
        source = ('# installer_class_selected service/web\n'
                  'installer_class_selected_any \\\n'
                  '  role/desktop/full role/server/devops\n'
                  'installer_validate_class_reference "profile policy" profile/desktop/btrfs-de\n')
        self.assertEqual(checker._literal_class_queries(source), [
            (2, 'role/desktop/full'), (2, 'role/server/devops'),
            (4, 'profile/desktop/btrfs-de')])

    def test_dynamic_arguments_are_not_claimed_as_validated_literals(self):
        self.assertEqual(checker._literal_class_queries(
            'installer_class_selected "$reference"\n'
            'installer_class_selected_any $selected_classes\n'
            'command -v installer_class_selected >/dev/null\n'
            'installer_class_selected() { :; }\n'), [])

    def test_one_suite_missing_a_class_is_rejected(self):
        errors, counts = [], {}
        checker._check_class_queries('fixture.sh', 'runtime_class_selected optional/cuda\n',
                                     {'forky': {'optional/cuda'}, 'trixie': set()}, errors, counts)
        self.assertEqual(len(errors), 1)
        self.assertIn('(suites: trixie)', errors[0])


if __name__ == '__main__':
    unittest.main()
