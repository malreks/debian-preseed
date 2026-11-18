"""Literal hardware-policy handoff regressions; isolated execution only."""
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from isolation import require_test_isolation
require_test_isolation()

import ast
import importlib.util
import re
import tarfile
import unittest


SPEC = importlib.util.spec_from_file_location(
    'hardware_policy_handoff', ROOT / 'd-i/debian/scripts/common/hardware-tuning-config.py')
assert SPEC is not None and SPEC.loader is not None
INSTALLER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INSTALLER)


class HardwarePolicyHandoffTests(unittest.TestCase):
    def test_authored_compiled_and_mixed_literal_quote_styles_have_equal_values(self):
        expected = {'HARDWARE_TUNING_IDLE_AC': 'balanced',
                    'HARDWARE_INTEL_CPU_TUNING_ENABLE': 'true'}
        for first, second in (("'", "'"), ('"', '"'), ("'", '"'), ('"', "'")):
            with self.subTest(quotes=(first, second)):
                text = (f'HARDWARE_TUNING_IDLE_AC={first}balanced{first}\n'
                        f'HARDWARE_INTEL_CPU_TUNING_ENABLE={second}true{second}\n')
                self.assertEqual(INSTALLER.parse_environment(text), expected)

    def test_duplicate_keys_are_rejected_across_quote_styles(self):
        for first, second in (("'", "'"), ('"', '"'), ("'", '"'), ('"', "'")):
            with self.subTest(quotes=(first, second)), self.assertRaises(ValueError):
                INSTALLER.parse_environment(
                    f'HARDWARE_TUNING_IDLE_AC={first}balanced{first}\n'
                    f'HARDWARE_TUNING_IDLE_AC={second}silent{second}\n')

    def test_malformed_quotes_expressions_and_out_of_contract_values_are_rejected(self):
        bad = ("HARDWARE_TUNING_IDLE_AC='balanced\"",
               'HARDWARE_TUNING_IDLE_AC="balanced\'',
               'HARDWARE_TUNING_IDLE_AC=balanced',
               "HARDWARE_TUNING_IDLE_AC='balanced'; true",
               "HARDWARE_TUNING_IDLE_AC='$(unexpected)'",
               "HARDWARE_TUNING_IDLE_AC='`unexpected`'",
               "HARDWARE_TUNING_IDLE_AC='${unexpected}'",
               "HARDWARE_TUNING_IDLE_AC='two words'",
               "HARDWARE_TUNING_IDLE_AC=''",
               "HARDWARE_TUNING_IDLE_AC='" + 'a' * 101 + "'",
               "UNRELATED_FIELD='true'")
        for text in bad:
            with self.subTest(text=text), self.assertRaises(ValueError):
                INSTALLER.parse_environment(text)

    def test_every_compiled_suite_and_family_hardware_snapshot_matches_its_literals(self):
        suites, profiles = set(), 0
        with tarfile.open(ROOT / 'd-i/forky/payload.tar.gz', 'r:gz') as archive:
            for member in archive:
                match = re.fullmatch(
                    r'catalog/compiled/(forky|trixie)/profiles/(desktop|server)/[^/]+\.env',
                    member.name)
                if match is None or member.name.endswith('.account.env'):
                    continue
                stream = archive.extractfile(member)
                self.assertIsNotNone(stream)
                with stream:
                    lines = [line for line in stream.read().decode('utf-8').splitlines()
                             if re.match(r'^HARDWARE_(INTEL_CPU_TUNING|NVIDIA_GPU_TUNING|TUNING)_[A-Z0-9_]+=', line)]
                if not lines:
                    continue
                expected = {key: ast.literal_eval(value)
                            for key, value in (line.split('=', 1) for line in lines)}
                self.assertEqual(INSTALLER.parse_environment('\n'.join(lines)), expected)
                suites.add(match[1])
                profiles += 1
        self.assertGreater(profiles, 0)
        self.assertEqual(suites, {'forky', 'trixie'})
