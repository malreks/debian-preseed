"""AWK regexp delimiters are checked as source, independently of Mawk syntax."""
from __future__ import annotations

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from isolation import require_test_isolation
require_test_isolation()

import runpy
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
CHECKER = ROOT / 'tools/post_change_check.py'
PUBLICATION = ROOT / 'd-i/debian/scripts/common/modules/target-publication.sh'
CROWDSEC = ROOT / 'd-i/debian/scripts/late/crowdsec.sh'
PLAN = ROOT / 'd-i/debian/scripts/common/modules/installation-plan.sh'


class AwkLiteralPortabilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # The checker module has imports, data declarations, and definitions.
        # Its main guard is inactive; no subprocess or repository helper runs.
        # Every checked program below remains data.
        cls.checker = runpy.run_path(str(CHECKER))

    def test_real_owners_have_checked_literal_grammars(self):
        errors, counts = [], {}
        with mock.patch.object(self.checker['subprocess'], 'run',
                               side_effect=AssertionError('native execution is forbidden')):
            self.checker['check_awk_literal_portability']([PUBLICATION, CROWDSEC, PLAN], errors, counts)
        self.assertEqual(errors, [])
        self.assertEqual(counts, {'awk_portable_owner_literals': 3})

    def test_known_raw_class_spellings_fail_before_native_execution(self):
        for path, name, expected in (
                (PUBLICATION, 'installer_target_ownership_filter', 4),
                (CROWDSEC, 'crowdsec_stage_logging_overlay', 1),
                (PLAN, 'installer_plan_stage_records', 1)):
            with self.subTest(owner=name):
                body, _ = self.checker['_function_awk_literal'](path.read_text(), name)
                self.assertEqual(self.checker['_awk_regex_slash_issues'](body), [])
                # Reintroduce the historical raw-slash spelling: four now
                # shared ownership classes, plus the one CrowdSec class.
                old = body.replace(r'A-Za-z0-9_.\/', 'A-Za-z0-9_./')
                self.assertNotEqual(old, body)
                self.assertEqual(len(self.checker['_awk_regex_slash_issues'](old)), expected)

    def test_strings_comments_division_and_escaped_classes_remain_distinct(self):
        safe = r'''
          # /[A-Za-z0-9_./]/ is comment text, not an AWK regexp.
          BEGIN { x = "/[raw/slash]/"; y = 9 / 3; y /= 2; z = (y + 1) / 2 }
          $0 ~ /^[A-Za-z0-9_.\/@+:-]+$/ { print "http://example.invalid/" }
          $0 ~ /[]\/]/ || $0 ~ /[[:alnum:]\/]/ || $0 ~ /[^^]/ { print $0 }
        '''
        self.assertEqual(self.checker['_awk_regex_slash_issues'](safe), [])
        unsafe = r'''
          /[a/b]/ { print }
          { if ($1) /[^]/]/; while ($2) /[[:alnum:]/]/; print /[\\/]/ }
        '''
        self.assertEqual(len(self.checker['_awk_regex_slash_issues'](unsafe)), 4)

    def test_missing_or_dynamic_owner_literal_is_not_silently_accepted(self):
        for source in ('', 'owner() {\n  LC_ALL=C awk "$program" "$input"\n}\n'):
            with self.subTest(source=source), self.assertRaises(ValueError):
                self.checker['_function_awk_literal'](source, 'owner')


if __name__ == '__main__':
    unittest.main()
