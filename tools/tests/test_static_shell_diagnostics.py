"""The static audit must retain errors and SC2154 after batching analyses."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from isolation import require_test_isolation
require_test_isolation()

import json
import unittest
import post_change_check as checker


class ShellCheckDiagnosticTests(unittest.TestCase):
    def test_one_pass_keeps_errors_and_unbound_findings(self):
        records = [
            {'level': 'error', 'code': 1073, 'line': 2, 'message': 'parse failure'},
            {'level': 'warning', 'code': 2154, 'line': 3, 'message': 'unbound'},
            {'level': 'warning', 'code': 2034, 'line': 4, 'message': 'unused'},
        ]
        self.assertEqual(checker._shellcheck_findings(json.dumps(records), unbound=True), records[:2])
        self.assertEqual(checker._shellcheck_findings(json.dumps(records), unbound=False), records[:1])

    def test_malformed_records_fail_instead_of_hiding_a_checker_error(self):
        for value in ({}, [None], [{'level': 'unknown', 'code': 1073}],
                      [{'level': 'error', 'code': '1073'}]):
            with self.subTest(value=value), self.assertRaises(ValueError):
                checker._shellcheck_findings(json.dumps(value), unbound=True)


if __name__ == '__main__':
    unittest.main()
