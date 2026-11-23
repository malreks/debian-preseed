"""Follow-up safety regressions; no real GPU, service, or sysfs mutation."""
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
from unittest.mock import patch

import test_hardware_tuning_20260916 as base


class MultipleGpuTemperatureTests(unittest.TestCase):
    def test_acoustic_target_uses_driver_range_without_a_software_temperature_cap(self):
        backend = object.__new__(base.nvidia.Backend)
        backend.knobs = {}
        backend.api = base.FakeNVML()
        with patch.object(backend.api, 'scalar', side_effect=lambda _name, _handle, threshold:
                          {4: 45, 5: 80, 6: 105}[threshold]), \
                patch.object(backend.api, 'has', return_value=True), \
                patch.object(backend.api, 'call') as write:
            backend.target_temperature('GPU-fixture', 0)
            knob = backend.knobs['GPU-fixture/TARGET_TEMPERATURE_C']
            self.assertEqual((knob.minimum, knob.maximum), (45, 105))
            self.assertEqual(knob.resolve('101', {}), 101)
            with self.assertRaises(base.common.TuningError):
                knob.resolve('106', {})
            knob.write(101)
            self.assertEqual(write.call_args.args[2][1], 5)
            self.assertEqual(write.call_args.args[2][2]._obj.value, 101)

    def hardware(self, readings):
        hardware = object.__new__(base.nvidia.Backend)
        hardware.handles = list(range(len(readings)))
        hardware.unavailable = []
        hardware.api = base.FakeNVML()
        def scalar(name, handle, *extra):
            self.assertEqual(name, 'nvmlDeviceGetTemperature')
            value = readings[handle]
            if value is None:
                raise base.common.TuningError('sensor unavailable')
            return value
        hardware.api.scalar = scalar
        return hardware

    def test_complete_sensor_coverage_uses_hottest_gpu(self):
        self.assertEqual(self.hardware([35, 72, 48]).temperature(), 72.0)

    def test_partial_sensor_coverage_is_unknown_not_the_other_gpu_temperature(self):
        for readings in ([35, None], [None, 35], [35, 0], [35, 150]):
            with self.subTest(readings=readings):
                self.assertIsNone(self.hardware(readings).temperature())

    def test_no_readable_gpu_temperature_remains_unknown(self):
        self.assertIsNone(self.hardware([None, None]).temperature())

    def test_missing_one_sensor_is_reported_without_blocking_opted_in_offset(self):
        backend = base.FakeBackend()
        backend.add('GPU-a/GPU_OFFSET_MHZ/P0', 'GPU_OFFSET_MHZ', 0,
                    low=-200, high=200, overclock=True)
        settings = {'GPU_OFFSET_MHZ': ('50',) * 4}
        policy = base.simple_policy(settings)
        policy['allow_overclock'] = True
        sensors = self.hardware([35, None])
        with base.private_temp() as temporary, patch.object(backend, 'temperature', sensors.temperature):
            transaction = base.engine.Engine(backend, base.Path(temporary)/'journal.json', policy)
            self.assertIsNone(transaction.apply('high', settings)['temperature_c'])
            self.assertEqual(backend.values['GPU-a/GPU_OFFSET_MHZ/P0'], 50)
            transaction.reset()
            self.assertEqual(backend.values['GPU-a/GPU_OFFSET_MHZ/P0'], 0)

    def test_sensor_loss_on_one_gpu_does_not_discard_owned_recovery(self):
        backend = base.FakeBackend()
        backend.add('GPU-a/GPU_OFFSET_MHZ/P0', 'GPU_OFFSET_MHZ', 0,
                    low=-200, high=200, overclock=True)
        settings = {'GPU_OFFSET_MHZ': ('50',) * 4}
        policy = base.simple_policy(settings)
        policy['allow_overclock'] = True
        with base.private_temp() as temporary:
            transaction = base.engine.Engine(backend, base.Path(temporary)/'journal.json', policy)
            transaction.apply('high', settings)
            with patch.object(backend, 'temperature', self.hardware([35, None]).temperature):
                self.assertEqual(transaction.health()['conflicts'], [])
                self.assertFalse(transaction.health()['temperature_available'])
            transaction.reset()
            self.assertEqual(backend.values['GPU-a/GPU_OFFSET_MHZ/P0'], 0)


if __name__ == '__main__':
    unittest.main()
