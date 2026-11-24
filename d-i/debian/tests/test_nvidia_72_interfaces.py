"""Static contract checks for the Pika NVIDIA 580 DKMS ownership boundary."""
from __future__ import annotations

from pathlib import Path as _IsolationPath
import sys as _isolation_sys
_isolation_sys.path.insert(0, str(_IsolationPath(__file__).resolve().parents[3] / "tools"))
_isolation_sys.path.insert(0, "/workspace/repository/tools")
from isolation import require_test_isolation as _require_test_isolation
_isolation_sys.path.pop(0)
_require_test_isolation()

from payload_fixture import read_text as payload_read_text
import unittest

SEED = _IsolationPath(__file__).resolve().parents[1]


class Nvidia580VendorSourceTests(unittest.TestCase):
    def test_pika_driver_and_source_packages_are_selected(self):
        for suite in ("forky", "trixie"):
            text = payload_read_text(SEED.parent / suite / "classes/class-select/optional/nvidia-legacy.cfg")
            self.assertIn("nvidia-kernel-dkms-580", text)
            self.assertIn("nvidia-kernel-source-580", text)
            self.assertNotIn("nvidia-dkms-580", text)

    def test_installer_leaves_pika_native_kernel_compatibility_untouched(self):
        text = payload_read_text(SEED / "hooks/installer/pre-pkgsel.d/92nvidia-legacy-dkms.sh")
        self.assertIn("drm_atomic_commit", text)
        self.assertIn("strscpy", text)
        self.assertNotIn("NV_INSTALLER_NVIDIA_LEGACY_DRM_PROBE", text)
        self.assertNotIn("NV_INSTALLER_NVIDIA_LEGACY_BOUNDED_COPY", text)
        self.assertNotIn("NV_INSTALLER_NVIDIA_LEGACY_STRNCPY_COMPAT", text)

    def test_dkms_source_is_built_by_normal_package_hooks(self):
        text = payload_read_text(SEED / "hooks/installer/pre-pkgsel.d/92nvidia-legacy-dkms.sh")
        self.assertIn("package's normal DKMS", text)
        self.assertIn("Secure Boot framework signs", text)


if __name__ == "__main__":
    unittest.main()
