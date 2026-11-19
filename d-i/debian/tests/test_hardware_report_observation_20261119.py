"""Guest-only report snapshots; all controls are in-memory fixture callables."""
from __future__ import annotations

# Refuse host execution before importing runtime helpers or creating fixtures.
from pathlib import Path as _IsolationPath
import sys as _isolation_sys
_isolation_sys.path.insert(0, str(_IsolationPath(__file__).resolve().parents[3] / 'tools'))
# Copied checker/GUI fixtures still use the verified private checkout gate.
_isolation_sys.path.insert(0, '/workspace/repository/tools')
from isolation import require_test_isolation as _require_test_isolation
_isolation_sys.path.pop(0)
_require_test_isolation()

import unittest
from unittest.mock import Mock, patch

import test_hardware_tuning_20260916 as base


class HardwareReportObservationTests(unittest.TestCase):
    def setUp(self):
        self.backend = base.FakeBackend()
        self.knob = self.backend.add('X', 'X', 20)
        self.settings = {'X': ('30',) * 4}
        # Report/plan do not need a journal file or a native driver inventory.
        self.work = object.__new__(base.engine.Engine)
        self.work.backend = self.backend
        self.work.policy = base.simple_policy(self.settings)
        self.work.journal = {'version': 1, 'entries': [], 'profile': None}

    def test_count_and_display_share_one_read_and_later_report_is_fresh(self):
        with patch.object(self.knob, 'read', side_effect=[20, 30]) as reads:
            first = self.work.report(self.settings)
            reads.assert_called_once_with()
            self.assertEqual(first['controls'][0]['current'], 20)
            self.assertTrue(all(item['valid'] and item['planned_changes'] == 1
                                for item in first['profile_preflight'].values()))
            second = self.work.report(self.settings)
            self.assertEqual(reads.call_count, 2)
        self.assertEqual(second['controls'][0]['current'], 30)
        self.assertTrue(all(item['valid'] and item['planned_changes'] == 0
                            for item in second['profile_preflight'].values()))
        self.assertEqual(self.backend.writes, [])

    def test_unavailable_observation_stays_an_error_until_next_report(self):
        with patch.object(self.knob, 'read', side_effect=[OSError('fixture unavailable'), 20]) as reads:
            first = self.work.report(self.settings)
            reads.assert_called_once_with()
            self.assertTrue(all(not item['valid'] and 'fixture unavailable' in item['error']
                                for item in first['profile_preflight'].values()))
            self.assertIsNone(first['controls'][0]['current'])
            self.assertEqual(first['controls'][0]['read_error'], 'fixture unavailable')
            second = self.work.report(self.settings)
            self.assertEqual(reads.call_count, 2)
        self.assertIsNone(second['controls'][0]['read_error'])
        self.assertEqual(second['controls'][0]['current'], 20)
        self.assertEqual(self.backend.writes, [])

    def test_unqueryable_control_never_uses_a_current_value_reader(self):
        self.knob.restorable = False
        self.work.policy['exclusive_clock_control'] = True
        with patch.object(self.knob, 'read', side_effect=AssertionError('unqueryable read')) as reads:
            result = self.work.report(self.settings)
            reads.assert_not_called()
        self.assertIsNone(result['controls'][0]['current'])
        self.assertIn('not queryable', result['controls'][0]['read_error'])
        self.assertTrue(all(item['valid'] and item['planned_changes'] == 1
                            for item in result['profile_preflight'].values()))

    def test_planning_pair_and_ownership_checks_still_observe_fresh_state(self):
        self.backend.knobs.clear()
        low = self.backend.add('low', 'MIN', 10, pair='limits', side='min')
        high = self.backend.add('high', 'MAX', 50, pair='limits', side='max')
        settings = {'MIN': ('20',) * 4, 'MAX': ('keep',) * 4}
        self.work.policy = base.simple_policy(settings)
        self.backend.check_ownership = Mock()
        with patch.object(low, 'read', wraps=low.read) as lows, patch.object(
                high, 'read', side_effect=[50, 15, 50, 50, 50]) as highs:
            result = self.work.report(settings)
        # The unrequested maximum is read anew by every plan; a changed bound
        # invalidates the second profile even though report evidence is shared.
        self.assertFalse(result['profile_preflight']['high']['valid'])
        self.assertIn('inverted min/max', result['profile_preflight']['high']['error'])
        self.assertEqual(highs.call_count, 5)  # Four planning checks plus display.
        lows.assert_called_once_with()
        self.assertEqual(self.backend.check_ownership.call_count, 3)
        self.assertEqual(self.backend.writes, [])

    def test_health_reads_again_after_report_and_detects_external_change(self):
        with patch.object(self.knob, 'read', wraps=self.knob.read) as reads:
            self.work.report(self.settings)
            self.work.journal['entries'] = [{'id': 'X', 'before': 20, 'last': 20,
                                            'pending': False, 'requested': 30}]
            self.backend.values['X'] = 35
            health = self.work.health()
            self.assertEqual(reads.call_count, 2)
        self.assertTrue(any('changed by firmware/another power manager' in item
                            for item in health['conflicts']))

    def test_standalone_knob_report_retains_its_fresh_reader(self):
        policy = self.work.policy
        with patch.object(self.knob, 'read', side_effect=[20, 30]) as reads:
            self.assertEqual(self.knob.report(policy['profiles'], policy)['current'], 20)
            self.assertEqual(self.knob.report(policy['profiles'], policy)['current'], 30)
            self.assertEqual(reads.call_count, 2)

    def test_unhandled_value_error_remains_a_fatal_control_report_error(self):
        with patch.object(self.knob, 'read', side_effect=ValueError('invalid driver scalar')) as reads:
            with self.assertRaisesRegex(ValueError, 'invalid driver scalar'):
                self.work.report(self.settings)
            reads.assert_called_once_with()
        self.assertEqual(self.backend.writes, [])


if __name__ == '__main__':
    unittest.main()
