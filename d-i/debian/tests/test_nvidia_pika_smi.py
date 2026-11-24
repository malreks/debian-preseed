"""Exercise Debian/Pika's fixed alternatives path in a private guest only."""
from __future__ import annotations

from pathlib import Path as _IsolationPath
import sys as _isolation_sys
_isolation_sys.path.insert(0, str(_IsolationPath(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation as _require_test_isolation
_isolation_sys.path.pop(0)
_require_test_isolation()

import ast
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
import unittest


@unittest.skipUnless(os.geteuid() == 0, 'package ownership contract requires guest root')
class NvidiaPikaSmiTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='pika-smi-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        source = (Path(__file__).resolve().parents[1] /
                  'hooks/target/usr/local/lib/common/hardware_tuning/nvidia.py')
        tree = ast.parse(source.read_text(encoding='utf-8'))
        classes = [node for node in tree.body if isinstance(node, ast.ClassDef)
                   and node.name in {'NvidiaSmiFailure', 'NvidiaSmi'}]
        # Extract these two checked classes only: importing the hardware module
        # would instantiate unrelated target imports and NVML interfaces.
        scope = {'Path': Path, 'os': os, 'stat': stat, 'subprocess': subprocess,
                 're': re, 'TuningError': RuntimeError}
        exec(compile(ast.Module(body=classes, type_ignores=[]), str(source), 'exec'), scope)
        self.smi = scope['NvidiaSmi']
        self.failure = scope['NvidiaSmiFailure']
        self.entry = self.root / 'bin/nvidia-smi'
        self.binary = self.root / 'lib/nvidia/current/nvidia-smi'
        self.entry.parent.mkdir()
        self.binary.parent.mkdir(parents=True)
        self.binary.write_text('#!/bin/sh\nexit 0\n', encoding='utf-8')
        self.binary.chmod(0o755)
        self.smi.COMMAND = self.entry
        self.smi.DEBIAN_COMMAND = self.binary

    def test_exact_package_alternative_resolves_to_regular_binary(self):
        self.entry.symlink_to(self.binary)
        self.assertEqual(self.smi().command, self.binary)

    def test_regular_vendor_binary_remains_supported(self):
        self.entry.write_bytes(self.binary.read_bytes())
        self.entry.chmod(0o755)
        self.assertEqual(self.smi().command, self.entry)

    def test_foreign_alternative_is_rejected(self):
        other = self.root / 'other'
        other.write_bytes(self.binary.read_bytes())
        other.chmod(0o755)
        self.entry.symlink_to(other)
        with self.assertRaisesRegex(self.failure, 'not the package binary'):
            self.smi()

    def test_writable_package_parent_is_rejected(self):
        self.entry.symlink_to(self.binary)
        self.binary.parent.chmod(0o777)
        with self.assertRaisesRegex(self.failure, 'directory is not trusted'):
            self.smi()

    def test_writable_or_nonroot_package_binary_is_rejected(self):
        self.entry.symlink_to(self.binary)
        for owner, mode in ((0, 0o777), (65534, 0o755), (0, 0o4755)):
            with self.subTest(owner=owner, mode=oct(mode)):
                os.chown(self.binary, owner, 0)
                self.binary.chmod(mode)
                with self.assertRaisesRegex(self.failure, 'executable regular file'):
                    self.smi()

    def test_explicit_command_does_not_allow_arbitrary_symlink(self):
        self.entry.symlink_to(self.binary)
        with self.assertRaisesRegex(self.failure, 'executable regular file'):
            self.smi(command=self.entry)

    def test_missing_or_looping_alternative_is_unavailable(self):
        for target in (self.root / 'missing', self.entry):
            with self.subTest(target=target):
                self.entry.symlink_to(target)
                with self.assertRaisesRegex(self.failure, 'unavailable'):
                    self.smi()
                self.entry.unlink()


if __name__ == '__main__':
    unittest.main()
