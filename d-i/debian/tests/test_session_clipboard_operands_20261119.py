"""Clipboard watcher operands through the actual session owner in a private guest."""
from __future__ import annotations

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation
require_test_isolation()

from types import ModuleType, SimpleNamespace
import unittest
from unittest import mock


OWNER = (Path(__file__).resolve().parents[1]
         / 'hooks/target/usr/local/libexec/desktop/labwc-session-state.tmpl')
BIN = '__INSTALLER_PATH_DIR_USR__/bin/'


class SessionClipboardOperandTests(unittest.TestCase):
    def test_watcher_names_remain_operands_and_cleanup_keeps_its_order(self):
        # The complete unchanged owner contains only standard-library imports,
        # constants, classes and function definitions at import time. Its CLI
        # guard is inactive under this module name. No target paths are resolved
        # or replaced: the two real functions pass exact argv to recording sinks.
        owner = ModuleType('session_clipboard_operand_fixture')
        exec(compile(OWNER.read_bytes(), str(OWNER), 'exec'), owner.__dict__)
        listing = (BIN + 'systemctl', '--user', '--no-pager', 'list-units',
                   '--all', '--plain', '--no-legend', '--type=service', '*cliphist*')
        watchers = ('cliphist.service', '-Hcliphist.service', 'cliphist@wayland-0.service')
        rows = '\n'.join(name + ' loaded active running Clipboard watcher' for name in watchers)
        rows += '\n\nbad/cliphist.service loaded active running Invalid name\n'
        rows += 'cliphist.timer loaded active waiting Wrong unit type\n'
        rows += 'cliphist!.service loaded active running Invalid character\n'

        for installed in (False, True):
            with self.subTest(cliphist_installed=installed):
                expected = [(listing, {})]
                expected.extend(((BIN + 'systemctl', '--user', '--no-pager', 'stop', '--', name), {})
                                for name in watchers)
                expected.extend([
                    ((BIN + 'wl-copy', '--clear'), {'timeout': 5}),
                    ((BIN + 'wl-copy', '--primary', '--clear'), {'timeout': 5}),
                ])
                if installed:
                    expected.append(((BIN + 'cliphist', 'wipe'), {'timeout': 5}))
                calls = []
                probes = []

                def record(argv, **kwargs):
                    call = (tuple(argv), kwargs)
                    self.assertLess(len(calls), len(expected), 'unexpected command')
                    self.assertEqual(call, expected[len(calls)])
                    calls.append(call)
                    return rows if tuple(argv) == listing else ''

                def fixed_path(value):
                    self.assertEqual(value, BIN + 'cliphist')
                    probes.append(value)
                    return SimpleNamespace(is_file=lambda: installed)

                with mock.patch.object(owner, 'run', side_effect=record), \
                     mock.patch.object(owner, 'Path', side_effect=fixed_path), \
                     mock.patch.object(owner.subprocess, 'run',
                                       side_effect=AssertionError('native command is forbidden')):
                    owner.clear_clipboard()
                self.assertEqual(calls, expected)
                self.assertEqual(probes, [BIN + 'cliphist'])


if __name__ == '__main__':
    unittest.main()
