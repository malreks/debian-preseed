"""Guarded target-root publication boundary checks."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
import sys

sys.path.insert(0, str(ROOT / "tools"))
from isolation import fixture_environment, require_test_isolation

require_test_isolation()


class TargetAssetRootBoundary(unittest.TestCase):
    def test_rejected_roots_do_not_modify_fixture_destination(self) -> None:
        home = Path(os.environ["HOME"])
        environment = fixture_environment(home)
        with tempfile.TemporaryDirectory(prefix="target-root-boundary-", dir=environment["TMPDIR"]) as temporary:
            fixture_root = Path(temporary)
            result = subprocess.run(
                [
                    "/bin/sh",
                    str(ROOT / "d-i/debian/tests/fixtures/target-asset-root-boundary.sh"),
                    str(fixture_root),
                    str(ROOT / "d-i/debian/scripts/late/target-assets.sh"),
                    str(ROOT / "d-i/debian/scripts/common/modules/target-publication.sh"),
                    str(ROOT / "d-i/debian/scripts/common/lifecycle.sh"),
                ],
                cwd=ROOT,
                env=environment,
                capture_output=True,
                text=True,
                timeout=15,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(result.stdout.strip(), "target asset root boundary fixture passed")
            self.assertEqual((fixture_root / "sibling/marker").read_text(), "protected\n")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
