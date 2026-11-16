"""NVIDIA 580/Linux 7.2 regression tests; no driver installation or GPU access.

The failing function is the one in the supplied 580.142 make.log and NVIDIA's
580.142 kernel-open/nvidia/os-interface.c. The installed proprietary layout is
covered separately. Test the actual generated DKMS wrapper, not a second patch.
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

from payload_fixture import installed_argv as payload_installed_argv, source_exists as payload_source_exists, source_stat as payload_source_stat
from payload_fixture import read_bytes as payload_read_bytes, read_text as payload_read_text

import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import unittest

SEED = Path(__file__).resolve().parents[1]
HOOK = SEED / 'hooks/installer/pre-pkgsel.d/92nvidia-legacy-dkms.sh'
MARKER = 'NV_INSTALLER_NVIDIA_LEGACY_STRNCPY_COMPAT'
OLD = r'''void NV_API_CALL os_get_current_process_name(char *buf, NvU32 len)
{
    task_lock(current);
    strncpy(buf, current->comm, len - 1);
    buf[len - 1] = '\0';
    task_unlock(current);
}
'''
NEW = OLD.replace(
    "    strncpy(buf, current->comm, len - 1);\n    buf[len - 1] = '\\0';\n",
    f'    /* {MARKER} */\n    strscpy_pad(buf, current->comm, len);\n',
)
HEADER = '#include "conftest.h"\n#include <linux/string.h>\n'


def wrapper_text() -> str:
    return payload_read_text(HOOK).split("<<'EOF'\n", 1)[1].split('\nEOF', 1)[0]


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
            ('unrelated-package', ['-u', '-k', self.kernel], None, 19),
            ('nvidia-dkms-580', ['-u'], None, 19),
            ('nvidia-dkms-580', ['-u', '-k', '7.3.1-xanmod1'], None, 19),
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


class NvidiaLegacyDkmsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='nvidia-580-regression-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.patch_functions = wrapper_text().split('\npatch_legacy_nvidia_source_tree()', 1)[0]
        self.env = {**os.environ, 'LC_ALL': 'C'}

    def test_hook_loads_target_runtime_contract_before_dkms_path_use(self):
        text = payload_read_text(HOOK)
        host_loader = 'installer_fetch_host_env "$SEED_BASE" "$HOST_PROFILE" "$PREPKGSEL_HOST_ENV" 0600'
        self.assertIn('HOST_PROFILE=$(installer_resolve_host_profile "")', text)
        self.assertIn(host_loader, text)
        self.assertLess(text.index(host_loader), text.index('wrapper_path='))
        self.assertIn('${DIR_USR_SBIN:-}', text)
        self.assertIn('nvidia_legacy_install_initramfs_guard()', text)
        self.assertIn('INSTALLER_TEMPORARY_NVIDIA_INITRAMFS_GUARD_V1', text)
        self.assertLess(
            text.index('nvidia_legacy_install_initramfs_guard'),
            text.index('wrapper_path='),
        )
        self.assertIn('install -d -m 0755 "${TARGET_ROOT}${DIR_USR_SBIN}"', text)

    def run_patch(self, path: Path, shell=None, env=None):
        return subprocess.run(
            payload_installed_argv([*(shell or ['/bin/sh']), '-eu', '-c',
             self.patch_functions + '\npatch_nv_os_interface "$1"\n', 'sh', str(path)]),
            capture_output=True, text=True, timeout=10, env=env or self.env,
        )

    def source(self, relative='os-interface.c', content=OLD):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def sandbox_wrapper(self, real_body='exit 0\n'):
        text = wrapper_text()
        # Relocate only filesystem constants, preserving the production shell
        # control flow and every argument passed to the real DKMS executable.
        text = text.replace('/usr/src/', str(self.root / 'usr/src') + '/')
        text = text.replace('/var/lib/dkms/', str(self.root / 'var/lib/dkms') + '/')
        real = self.root / 'dkms.distrib'
        text = text.replace('/usr/sbin/dkms.distrib', str(real))
        real.write_text('#!/bin/sh\nset -eu\n' + real_body)
        real.chmod(0o755)
        script = self.root / 'dkms'
        script.write_text(text + '\n')
        script.chmod(0o755)
        return script

    def test_rewrites_only_known_function_and_preserves_metadata(self):
        prefix = '/* unrelated code before */\nvoid untouched(void) { strncpy(a, b, n); }\n'
        suffix = '\n/* unrelated code after */\n'
        path = self.source(content=prefix + OLD + suffix)
        path.chmod(0o640)
        before = payload_source_stat(path)
        result = self.run_patch(path)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(payload_read_text(path), prefix + NEW + suffix)
        self.assertIn('Applied NVIDIA 580 Linux 7.2', result.stderr)
        after = payload_source_stat(path)
        self.assertEqual(stat.S_IMODE(after.st_mode), 0o640)
        self.assertEqual((after.st_uid, after.st_gid), (before.st_uid, before.st_gid))
        self.assertEqual(list(self.root.glob('*.tmp.*')), [])

    def test_idempotent_without_touching_mtime_or_inode(self):
        path = self.source()
        self.assertEqual(self.run_patch(path).returncode, 0)
        before = payload_source_stat(path)
        again = self.run_patch(path)
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertEqual(payload_read_text(path), NEW)
        self.assertEqual(payload_source_stat(path).st_ino, before.st_ino)
        self.assertEqual(payload_source_stat(path).st_mtime_ns, before.st_mtime_ns)
        self.assertEqual(again.stderr, '')

    def test_already_fixed_source_does_not_need_write_access(self):
        # In particular, an unprivileged `dkms status` must not need mktemp
        # write access to /usr/src after the installation has patched it.
        bindir = self.root / 'no-writes'
        bindir.mkdir()
        stub = bindir / 'mktemp'
        stub.write_text('#!/bin/sh\necho unexpected-write >&2\nexit 1\n')
        stub.chmod(0o755)
        path = self.source(content=NEW)
        result = self.run_patch(path, env={**self.env, 'PATH': str(bindir) + ':' + self.env['PATH']})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, '')
        self.assertEqual(payload_read_text(path), NEW)

    def test_accepts_equivalent_vendor_fix_without_marker(self):
        content = NEW.replace(f'    /* {MARKER} */\n', '')
        path = self.source(content=content)
        inode = payload_source_stat(path).st_ino
        result = self.run_patch(path)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(payload_read_text(path), content)
        self.assertEqual(payload_source_stat(path).st_ino, inode)

    def test_handles_tabs_and_crlf_in_known_function(self):
        path = self.source(content=OLD.replace('    ', '\t').replace('\n', '\r\n'))
        result = self.run_patch(path)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(payload_read_text(path), NEW)

    def test_unknown_duplicate_or_partial_function_fails_without_edit(self):
        cases = {
            'missing function': '/* no recognized function */\n',
            'duplicate function': OLD + '\n' + OLD,
            'wrong copy size': OLD.replace('len - 1);', 'len);'),
            'missing terminator': OLD.replace("    buf[len - 1] = '\\0';\n", ''),
            'missing lock': OLD.replace('    task_lock(current);\n', ''),
            'missing unlock': OLD.replace('    task_unlock(current);\n', ''),
            'unterminated function': OLD.rsplit('}', 1)[0],
            'stale marker': OLD.replace('    strncpy', f'    /* {MARKER} */\n    strncpy'),
            'incorrect safe size': NEW.replace('comm, len);', 'comm, len - 1);'),
            'partial new function': NEW.replace('    task_unlock',
                "    buf[len - 1] = '\\0';\n    task_unlock"),
            'duplicate marker': NEW.replace(f'/* {MARKER} */', f'/* {MARKER} */ /* {MARKER} */'),
        }
        for label, content in cases.items():
            with self.subTest(label=label):
                path = self.source(content=content)
                original = payload_read_bytes(path)
                inode = payload_source_stat(path).st_ino
                result = self.run_patch(path)
                self.assertNotEqual(result.returncode, 0, result.stderr)
                self.assertIn('unrecognized NVIDIA 580 os_get_current_process_name', result.stderr)
                self.assertEqual(payload_read_bytes(path), original)
                self.assertEqual(payload_source_stat(path).st_ino, inode)
                self.assertEqual(list(self.root.glob('*.tmp.*')), [])

    def test_unreadable_missing_source_fails(self):
        result = self.run_patch(self.root / 'missing.c')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('not readable', result.stderr)

    def test_temp_copy_and_publish_failures_leave_original_intact(self):
        for command in ('mktemp', 'cp', 'mv'):
            with self.subTest(command=command):
                bindir = self.root / command
                bindir.mkdir()
                stub = bindir / command
                stub.write_text('#!/bin/sh\nexit 1\n')
                stub.chmod(0o755)
                path = self.source()
                result = self.run_patch(path, env={**self.env, 'PATH': str(bindir) + ':' + self.env['PATH']})
                self.assertNotEqual(result.returncode, 0, result.stderr)
                self.assertEqual(payload_read_text(path), OLD)
                self.assertEqual(list(self.root.glob('*.tmp.*')), [])

    @unittest.skipUnless(shutil.which('busybox'), 'BusyBox not installed')
    def test_busybox_ash_and_awk_execute_the_patcher(self):
        bindir = self.root / 'bin'
        bindir.mkdir()
        (bindir / 'awk').symlink_to(shutil.which('busybox'))
        path = self.source()
        result = self.run_patch(path, shell=[shutil.which('busybox'), 'sh'],
                                env={**self.env, 'PATH': str(bindir) + ':' + self.env['PATH']})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(payload_read_text(path), NEW)

    def test_wrapper_covers_source_build_symlink_and_nested_layout(self):
        roots = ['usr/src/nvidia-580.142', 'usr/src/nvidia-current-580.142',
                 'var/lib/dkms/nvidia/580.142/build']
        paths = []
        for root in roots:
            for layout in ('', 'kernel-open/'):
                self.source(f'{root}/{layout}common/inc/nv-linux.h', HEADER)
                paths.append(self.source(f'{root}/{layout}nvidia/os-interface.c'))
        link = self.root / 'var/lib/dkms/nvidia/580.142/source'
        link.symlink_to(self.root / roots[0], target_is_directory=True)
        other = self.source('usr/src/nvidia-590.48.01/nvidia/os-interface.c')
        other_dkms = self.source('var/lib/dkms/nvidia/570.86/build/nvidia/os-interface.c')
        script = self.sandbox_wrapper('printf "<%s>\\n" "$@"\nexit 23\n')
        result = subprocess.run(payload_installed_argv([str(script), 'build', '-m', 'nvidia', 'space in argument']),
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertEqual(result.stdout, '<build>\n<-m>\n<nvidia>\n<space in argument>\n')
        for path in paths:
            self.assertEqual(payload_read_text(path), NEW)
        self.assertEqual(link.resolve(), (self.root / roots[0]).resolve())
        self.assertTrue(link.is_symlink())
        self.assertEqual(payload_read_text(other), OLD)
        self.assertEqual(payload_read_text(other_dkms), OLD)

    def test_wrapper_patches_before_dkms_source_copy_and_after_reunpack(self):
        path = self.source('usr/src/nvidia-580.142/nvidia/os-interface.c')
        copy = self.root / 'fresh-build.c'
        script = self.sandbox_wrapper(f'grep -q {MARKER} "{path}"\ncp "{path}" "{copy}"\n')
        for operation in ('add', 'build', 'install', 'autoinstall'):
            with self.subTest(operation=operation):
                # A package reinstall overwrites /usr/src: no stamp may cause
                # a future DKMS invocation to skip the compatibility repair.
                path.write_text(OLD)
                result = subprocess.run(payload_installed_argv([str(script), operation]), capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(payload_read_text(copy), NEW)

    def test_wrapper_does_not_invoke_real_dkms_on_patch_failure(self):
        path = self.source('usr/src/nvidia-580.142/nvidia/os-interface.c', OLD + OLD)
        called = self.root / 'called'
        script = self.sandbox_wrapper(f'touch "{called}"\n')
        result = subprocess.run(payload_installed_argv([str(script), 'build']), capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('failed to patch NVIDIA 580 OS interface', result.stderr)
        self.assertFalse(payload_source_exists(called))
        self.assertEqual(payload_read_text(path), OLD + OLD)

    def test_wrapper_passes_through_when_no_580_sources_exist(self):
        script = self.sandbox_wrapper('printf "%s\\n" "$1"\n')
        result = subprocess.run(payload_installed_argv([str(script), 'status']), capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'status\n')

    @unittest.skipUnless(shutil.which('cc'), 'C compiler not installed')
    def test_compiled_function_buffer_bounds_padding_and_locking(self):
        # This is an executable API-contract fixture, not a full NVIDIA build.
        # Poisoning strncpy models the API removal even on older build hosts.
        prelude = r'''
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#define NV_API_CALL
#define NvU32 uint32_t
struct task { char comm[16]; } task;
#define current (&task)
static unsigned locks, unlocks, locked;
static void task_lock(struct task *p) { assert(p == current && !locked); locked = 1; locks++; }
static void task_unlock(struct task *p) { assert(p == current && locked); locked = 0; unlocks++; }
/* Model the documented strscpy_pad contract without depending on libc strncpy. */
static long strscpy_pad(char *dst, const char *src, size_t size) {
    size_t i = 0;
    if (!size) return -7;
    while (i + 1 < size && src[i]) { dst[i] = src[i]; i++; }
    dst[i] = 0;
    if (src[i]) return -7;
    memset(dst + i + 1, 0, size - i - 1);
    return (long)i;
}
#pragma GCC poison strncpy
'''
        main = r'''
int main(void) {
    unsigned cases = 0;
    for (size_t source_len = 0; source_len < sizeof(task.comm); source_len++) {
        memset(task.comm, 'x', sizeof(task.comm));
        task.comm[source_len] = 0;
        for (uint32_t capacity = 0; capacity <= 64; capacity++) {
            unsigned char actual[80], expected[80];
            memset(actual, 0xa5, sizeof(actual));
            memset(expected, 0xa5, sizeof(expected));
            if (capacity) {
                /* Reference: old bounded copy, padding, then last-byte NUL. */
                for (uint32_t i = 0; i + 1 < capacity; i++)
                    expected[8+i] = i < source_len ? (unsigned char)task.comm[i] : 0;
                expected[8+capacity-1] = 0;
            }
            os_get_current_process_name((char *)actual + 8, capacity);
            assert(memcmp(actual, expected, sizeof(actual)) == 0);
            assert(!locked && locks == unlocks);
            cases++;
        }
    }
    os_get_current_process_name(NULL, 0);
    assert(!locked && locks == unlocks);
    printf("%u buffer cases plus NULL/zero length: PASS\n", cases);
    return 0;
}
'''
        compiler = shutil.which('cc')
        path = self.source()
        result = self.run_patch(path)
        self.assertEqual(result.returncode, 0, result.stderr)
        fixture = self.root / 'contract.c'
        binary = self.root / 'contract'
        fixture.write_text(prelude + payload_read_text(path) + main)
        result = subprocess.run(payload_installed_argv([compiler, '-std=c11', '-Wall', '-Wextra', '-Werror',
                                 '-fsanitize=undefined', '-fno-sanitize-recover=all',
                                 str(fixture), '-o', str(binary)]), capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = subprocess.run(payload_installed_argv([str(binary)]), capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('1040 buffer cases', result.stdout)
        # Prove the same compiler fixture rejects the original failing call.
        fixture.write_text(prelude + OLD + main)
        result = subprocess.run(payload_installed_argv([compiler, '-std=c11', '-Werror', '-c', str(fixture),
                                 '-o', str(self.root / 'bad.o')]), capture_output=True, text=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('strncpy', result.stderr)


if __name__ == '__main__':
    unittest.main()
