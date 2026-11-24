"""NVIDIA 580 installer and package-ownership regression tests.

The Pika 580 package owns the Linux 7.2+ source compatibility. These fixtures
cover the installer-only initramfs guard and ensure no second DKMS patcher or
diversion is introduced.
"""
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

from payload_fixture import read_text as payload_read_text

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

SEED = Path(__file__).resolve().parents[1]
HOOK = SEED / 'hooks/installer/pre-pkgsel.d/92nvidia-legacy-dkms.sh'
class NvidiaInitramfsGuardTests(unittest.TestCase):
    """Real dpkg diversions in an isolated private root; update-initramfs is a stub."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='nvidia-initramfs-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.target = self.root / 'target'
        self.work = self.root / 'work'
        self.work.mkdir(mode=0o700)
        for leaf in ('bin', 'usr/sbin', 'var/lib/dpkg', 'boot', 'lib/modules'):
            (self.target / leaf).mkdir(parents=True, exist_ok=True)
        # Copy the isolated Debian image's BusyBox and declared amd64 libc
        # support into the private fixture root; never bind a system tree.
        shutil.copyfile('/bin/busybox', self.target / 'bin/busybox')
        (self.target / 'bin/busybox').chmod(0o755)
        (self.target / 'bin/sh').symlink_to('busybox')
        for name in ('/lib64/ld-linux-x86-64.so.2',
                     '/lib/x86_64-linux-gnu/libc.so.6',
                     '/lib/x86_64-linux-gnu/libm.so.6',
                     '/lib/x86_64-linux-gnu/libresolv.so.2'):
            library = Path(name)
            if library.is_file():
                output = self.target / library.relative_to('/')
                output.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(library, output)
                output.chmod(0o755)
        self.entry = self.target / 'usr/sbin/update-initramfs'
        self.preserved = self.target / 'usr/sbin/update-initramfs.installer-real'
        self.original = b'#!/bin/sh\nprintf "%s\\n" "$@" > /invocations\nexit 19\n'
        self.entry.write_bytes(self.original)
        self.entry.chmod(0o755)
        self.kernel = '6.12.107+deb13-amd64'
        pre = payload_read_text(HOOK)
        finish = payload_read_text(SEED / 'hooks/installer/finish-install.d/99-normalize-finish')
        apt = payload_read_text(SEED / 'scripts/common/apt-sources.sh')
        lifecycle = payload_read_text(SEED / 'scripts/common/lifecycle.sh')
        self.functions = '\n'.join((
            re.search(r'(?ms)^nvidia_legacy_install_initramfs_guard\(\) \{\n.*?^\}', pre)[0],
            re.search(r'(?ms)^restore_temporary_nvidia_initramfs_guard\(\) \{\n.*?^\}', finish)[0],
            re.search(r'(?ms)^installer_apt_safe_path\(\) \(\n.*?^\)', apt)[0],
            re.search(r'(?ms)^installer_metadata_value\(\) \(\n.*?^\);', lifecycle)[0],
        ))
        self.env = {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C', 'HOME': str(self.work),
                    'TMPDIR': str(self.work), 'TMP': str(self.work), 'TEMP': str(self.work)}

    def actions(self, body, **extra):
        prelude = r'''
set -eu
TARGET_ROOT=$1
TARGET=$1
TMP_ENV_DIR=$2
DIR_BOOT=/boot
DIR_LIB=/lib
FILE_INSTALLER_DPKG_DIVERT=/usr/bin/dpkg-divert
FILE_INSTALLER_UPDATE_INITRAMFS=/usr/sbin/update-initramfs
FILE_INSTALLER_UPDATE_INITRAMFS_REAL=/usr/sbin/update-initramfs.installer-real
uname() { printf '%s\n' '6.12.107+deb13-amd64'; }
nvidia_legacy_prepkgsel_fatal() { printf '%s\n' "$*" >&2; exit 1; }
installer_info() { printf '%s\n' "$*"; }
log() { printf '%s\n' "$*" >&2; }
chroot() {
  fixture_root=$1
  shift
  [ "$1" = "$FILE_INSTALLER_DPKG_DIVERT" ] || return 99
  shift
  case " $* " in
    *' --remove '*) [ "${GUARD_FIXTURE_FAIL_REMOVE:-false}" != true ] || return 73 ;;
  esac
  /usr/bin/dpkg-divert --root="$fixture_root" "$@"
}
run_in_target() { shift; chroot "$TARGET_ROOT" "$@"; }
installer_copy_path_with_mode() {
  [ "${GUARD_FIXTURE_FAIL_COPY:-false}" != true ] || return 71
  /bin/busybox cp "$1" "$2"
  /bin/busybox chmod "$3" "$2"
}
'''
        return subprocess.run(
            ['/bin/sh', '-eu', '-c', prelude + self.functions + '\n' + body,
             'guard-fixture', str(self.target), str(self.work)],
            env={**self.env, **extra}, capture_output=True, text=True, timeout=15,
        )

    def install_guard(self):
        result = self.actions('nvidia_legacy_install_initramfs_guard\n')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_guard_skips_only_vendor_request_for_absent_installer_kernel(self):
        self.install_guard()
        cases = (
            ('nvidia-kernel-common-580', ['-u', '-k', self.kernel], None, 0),
            ('nvidia-dkms-580', ['-u', '-k', self.kernel], None, 0),
            ('nvidia-kernel-dkms-580', ['-u', '-k', self.kernel], None, 0),
            ('unrelated-package', ['-u', '-k', self.kernel], None, 19),
            ('nvidia-dkms-580', ['-u'], None, 19),
            ('nvidia-dkms-580', ['-u', '-k', '7.3.1-xanmod1'], None, 19),
            ('nvidia-kernel-dkms-580', ['-u', '-k', '7.3.1-xanmod1'], None, 19),
            ('nvidia-dkms-580', ['-c', '-k', self.kernel], None, 19),
            ('nvidia-dkms-580', ['-u', '-k', self.kernel], 'modules', 19),
            ('nvidia-dkms-580', ['-u', '-k', self.kernel], 'image', 19),
        )
        for package, arguments, present, status in cases:
            with self.subTest(package=package, arguments=arguments, present=present):
                marker = self.target / 'invocations'
                marker.unlink(missing_ok=True)
                evidence = None
                if present == 'modules':
                    evidence = self.target / 'lib/modules' / self.kernel
                    evidence.mkdir()
                elif present == 'image':
                    evidence = self.target / 'boot' / ('vmlinuz-' + self.kernel)
                    evidence.write_bytes(b'fixture-kernel')
                result = subprocess.run(
                    ['/bin/busybox', 'chroot', str(self.target),
                     '/usr/sbin/update-initramfs', *arguments],
                    env={**self.env, 'DPKG_MAINTSCRIPT_PACKAGE': package},
                    capture_output=True, text=True, timeout=10,
                )
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertEqual(marker.exists(), status == 19)
                if marker.exists():
                    self.assertEqual(marker.read_text().splitlines(), arguments)
                if evidence is not None:
                    evidence.rmdir() if evidence.is_dir() else evidence.unlink()

    def test_repeatable_setup_and_restore_preserve_packaged_executable(self):
        self.install_guard()
        self.install_guard()
        self.assertEqual(self.preserved.read_bytes(), self.original)
        for _ in range(2):
            result = self.actions('restore_temporary_nvidia_initramfs_guard\n')
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.entry.read_bytes(), self.original)
        self.assertFalse(self.preserved.exists())
        self.assertEqual((self.target / 'var/lib/dpkg/diversions').read_bytes(), b'')

    def test_interrupted_setup_restores_original_and_keeps_existing_initrd(self):
        image = self.target / 'boot' / ('initrd.img-' + self.kernel)
        image.write_bytes(b'keep-existing-image')
        failed = self.actions('nvidia_legacy_install_initramfs_guard\n', GUARD_FIXTURE_FAIL_COPY='true')
        self.assertEqual(failed.returncode, 71, failed.stderr)
        self.assertEqual(self.preserved.read_bytes(), self.original)
        self.assertFalse(self.entry.exists())
        restored = self.actions('restore_temporary_nvidia_initramfs_guard\n')
        self.assertEqual(restored.returncode, 0, restored.stderr)
        self.assertEqual(self.entry.read_bytes(), self.original)
        self.assertEqual(image.read_bytes(), b'keep-existing-image')

    def test_failed_restore_retains_original_until_successful_retry(self):
        self.install_guard()
        failed = self.actions('restore_temporary_nvidia_initramfs_guard\n', GUARD_FIXTURE_FAIL_REMOVE='true')
        self.assertNotEqual(failed.returncode, 0)
        self.assertEqual(self.preserved.read_bytes(), self.original)
        self.assertFalse(self.entry.exists())
        restored = self.actions('restore_temporary_nvidia_initramfs_guard\n')
        self.assertEqual(restored.returncode, 0, restored.stderr)
        self.assertEqual(self.entry.read_bytes(), self.original)

    def test_restore_rejects_replaced_entrypoint_and_retains_original(self):
        self.install_guard()
        self.entry.write_bytes(b'foreign-entrypoint')
        failed = self.actions('restore_temporary_nvidia_initramfs_guard\n')
        self.assertNotEqual(failed.returncode, 0)
        self.assertEqual(self.entry.read_bytes(), b'foreign-entrypoint')
        self.assertEqual(self.preserved.read_bytes(), self.original)

    def test_setup_rejects_guard_without_diversion(self):
        unexpected = b'#!/bin/sh\n# INSTALLER_TEMPORARY_NVIDIA_INITRAMFS_GUARD_V1\nexit 0\n'
        self.entry.write_bytes(unexpected)
        failed = self.actions('nvidia_legacy_install_initramfs_guard\n')
        self.assertNotEqual(failed.returncode, 0)
        self.assertEqual(self.entry.read_bytes(), unexpected)
        self.assertFalse(self.preserved.exists())

    def test_restore_rejects_guard_as_preserved_package_executable(self):
        self.install_guard()
        original_guard = self.entry.read_bytes()
        self.preserved.write_bytes(original_guard)
        failed = self.actions('restore_temporary_nvidia_initramfs_guard\n')
        self.assertNotEqual(failed.returncode, 0)
        self.assertEqual(self.entry.read_bytes(), original_guard)
        self.assertEqual(self.preserved.read_bytes(), original_guard)

class Nvidia580VendorDkmsContractTests(unittest.TestCase):
    """Pika owns the Linux 7.2+ source compatibility; the installer only guards d-i."""

    def test_installer_does_not_rewrite_or_divert_dkms(self):
        text = payload_read_text(HOOK)
        self.assertIn('nvidia_legacy_install_initramfs_guard()', text)
        self.assertIn('nvidia-kernel-dkms-580', text)
        self.assertIn('PikaOS 580.196.07-101pika2', text)
        self.assertIn('no installer source patch or DKMS diversion', text)
        self.assertNotIn('dkms-wrapper', text)
        self.assertNotIn('patch_nv_', text)
        self.assertNotIn('patch_legacy_nvidia_source_tree', text)
        self.assertNotIn('dpkg-divert --quiet --local --divert /usr/sbin/dkms', text)

    def test_secure_boot_signing_remains_a_separate_dkms_framework_contract(self):
        conf = payload_read_text(SEED / 'hooks/target/etc/dkms/framework.conf.d/90-secure-boot.conf.tmpl')
        self.assertIn('mok_signing_key=', conf)
        self.assertIn('mok_certificate=', conf)
        self.assertIn('sign_file="/lib/modules/${kernelver}/build/scripts/sign-file"', conf)

    def test_finish_cleanup_only_handles_an_interrupted_old_diversion(self):
        text = payload_read_text(SEED / 'hooks/installer/finish-install.d/10-nvidia-legacy-cleanup')
        self.assertIn('if ! dpkg-divert --list /usr/sbin/dkms', text)
        self.assertIn('NV_INSTALLER_NVIDIA_LEGACY_DKMS_WRAPPER_V1', text)
        self.assertIn('obsolete installer diversion', text)


if __name__ == '__main__':
    unittest.main()
