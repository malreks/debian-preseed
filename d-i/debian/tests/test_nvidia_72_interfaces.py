"""Static contract checks for the split Pika NVIDIA 580 Wayland set."""
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
    def test_split_wayland_packages_are_selected_without_meta_or_xorg(self):
        for suite in ("forky", "trixie"):
            text = payload_read_text(SEED.parent / suite / "classes/class-select/optional/nvidia-legacy.cfg")
            self.assertIn("nvidia-alternative-580", text)
            self.assertIn("nvidia-kernel-dkms-580", text)
            self.assertIn("nvidia-kernel-source-580", text)
            self.assertIn("nvidia-egl-icd-580", text)
            self.assertIn("libnvidia-glvkspirv-580", text)
            self.assertIn("libcuda1-580", text)
            self.assertIn("libnvidia-ml1-580", text)
            self.assertNotIn("d-i pkgsel/include string firmware-misc-nonfree", text)
            self.assertNotIn("nvidia-driver-580 nvidia-kernel", text)
            self.assertNotIn("nvidia-driver-bin-580", text)
            self.assertNotIn("xserver-xorg-video-nvidia-580", text)
            self.assertNotIn("libglx-nvidia0-580", text)
            self.assertNotIn("libnvidia-glcore-580", text)
            self.assertNotIn("nvidia-vulkan-icd-580", text)
            self.assertNotIn("nvidia-dkms-580", text)
            self.assertNotIn("nvidia-persistenced-580", text)
            self.assertNotIn("nvidia-powerd-580", text)

            preference = payload_read_text(
                SEED.parent / suite / "hooks/target/etc/apt/desktop/preferences.d/optional/nvidia-legacy.pref"
            )
            self.assertIn("Package: nvidia-alternative-580:any", preference)
            self.assertIn("Pin: version *580.196.07-101pika2", preference)
            self.assertIn("Package: libnvidia-egl-wayland1:any", preference)
            self.assertIn("Pin: version 1:1.1.24-101pika1", preference)
            self.assertIn(
                "Package: libgbm1:any libgl1-mesa-dri:any libegl-mesa0:any "
                "libglx-mesa0:any mesa-libgallium:any libmesa-stable:any",
                preference,
            )
            self.assertIn("Pin: version 26.3.1-101pika1", preference)
            self.assertIn(
                "Package: src:glibc:any src:libdrm:any src:wayland:any libllvm21",
                preference,
            )
            self.assertIn("Pin: release o=Debian,n=forky", preference)
            self.assertIn("Package: nvidia-vaapi-driver:any", preference)
            self.assertIn("xserver-xorg-video-nvidia-580:any", preference)
            self.assertIn("libnvidia-glcore-580:any", preference)
            self.assertIn("Pin-Priority: -1", preference)

    def test_open_kernel_wayland_packages_are_concrete_and_exact_pinned(self):
        for suite, vaapi_version in (("forky", "0.0.18-1"), ("trixie", "0.0.13-1")):
            text = payload_read_text(SEED.parent / suite / "classes/class-select/optional/nvidia.cfg")
            self.assertIn("nvidia-kernel-open-dkms", text)
            self.assertIn("nvidia-kernel-support", text)
            self.assertIn("nvidia-smi", text)
            self.assertIn("libnvidia-egl-wayland21", text)
            self.assertIn("libcuda1", text)
            self.assertNotIn("nvidia-driver-cuda", text)
            self.assertNotIn("nvidia-driver-libs", text)
            self.assertNotIn("xserver-xorg-video-nvidia", text)
            self.assertNotIn("nvidia-vulkan-icd", text)
            self.assertNotIn("libglx-nvidia0", text)
            self.assertNotIn("libnvidia-glcore", text)

            for family in ("desktop", "server"):
                preference = payload_read_text(
                    SEED.parent / suite / f"hooks/target/etc/apt/{family}/preferences.d/optional/nvidia.pref"
                )
                self.assertIn("Package: firmware-nvidia-gsp:any", preference)
                self.assertIn("Pin: version 620.70.10-1", preference)
                self.assertIn("Package: libnvidia-egl-wayland21:any", preference)
                self.assertIn("Pin: version 1.0.2-1", preference)
                self.assertIn("Package: libnvidia-egl-gbm1:any", preference)
                self.assertIn("Pin: version 1.1.4-2", preference)
                self.assertIn(f"Pin: version {vaapi_version}", preference)
                self.assertIn("Package: nvidia-driver:any nvidia-driver-cuda:any", preference)
                self.assertIn("xserver-xorg-video-nvidia:any", preference)
                self.assertIn("Pin-Priority: -1", preference)

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
