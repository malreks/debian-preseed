"""Automatic partition-policy failure fixtures, executable only in isolation.

All device/tool replies below are injected data. No real disk, host package,
service, sysfs tree or management helper participates in these cases.
"""
from __future__ import annotations

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation

require_test_isolation()

import shlex
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
MODULE = ROOT / 'd-i/debian/scripts/runtime/modules/layout-policy.sh'
CLASSES = MODULE.with_name('classes.sh')

PROGRAM = r'''
set -eu
runtime_fatal() { printf '%s\n' "$*" >&2; exit 71; }
runtime_require_positive_integer() {
  case "$2" in ''|*[!0-9]*|0) runtime_fatal 'invalid positive integer' ;; esac
  [ "${#2}" -le 10 ] || runtime_fatal 'integer exceeds limit'
}
runtime_install_disk_size_mb() { printf '500000\n'; }
runtime_partition_path() { printf '/dev/fixturep%s\n' "$1"; }
runtime_any_crypto_enabled() { [ "$FIXTURE_CRYPTO" = true ]; }
runtime_probe_gpt_part_type() {
  if [ "$FIXTURE_ESP" = true ] && [ "$1" = /dev/fixturep1 ]; then
    printf 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b\n'
  else
    printf '0fc63daf-8483-4772-8e79-3d69d8477de4\n'
  fi
}
runtime_gpt_part_type_is_esp() { [ "$1" = c12a7328-f81f-11d2-ba4b-00a0c93ec93b ]; }
runtime_probe_filesystem_type() { printf 'vfat\n'; }
source_state_key() { sha256sum; }
parted() {
  [ "$1" = -sm ] && [ "$2" = /dev/fixture ] || exit 91
  printf '%s\n' "$FIXTURE_INVENTORY"
}
sfdisk() {
  [ "$1" = --dump ] && [ "$2" = /dev/fixture ] || exit 92
  printf '%s\n' "$FIXTURE_INVENTORY"
}
DEV_INSTALL_DISK=/dev/fixture
'''


def inventory(*rows: tuple[int, int, int]) -> str:
    lines = ['BYT;', '/dev/fixture:500000000000B:scsi:512:512:gpt:Fixture:;']
    lines += [f'{slot}:{start}B:{end}B:{end-start+1}B::fixture:;'
              for slot, start, end in rows]
    return '\n'.join(lines)


class PartitionPolicy(unittest.TestCase):
    def invoke(self, body: str, *, multiboot: bool = False, reuse: bool = False,
               ceiling: bool = False, ceiling_mb: str = '400000', esp: bool = True,
               crypto: bool = False, profile: str | None = None,
               data: str | None = None) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory(prefix='partition-policy-') as temporary:
            environment = {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C', 'HOME': temporary,
                'PARTMAN_CEILING_ENABLE': str(ceiling).lower(),
                'PARTMAN_CEILING_MB': ceiling_mb,
                'PARTMAN_REUSE_ENABLE': str(reuse).lower(), 'PARTMAN_REUSE_START': '5',
                'INSTALLER_HOST_PROFILE_ENV_NAME': profile or ('btrfs-de-fixture-duo' if multiboot else 'btrfs-de-fixture'),
                'FIXTURE_ESP': str(esp).lower(),
                'FIXTURE_CRYPTO': str(crypto).lower(),
                'FIXTURE_INVENTORY': data if data is not None else inventory(
                    (1, 1048576, 537919487), (3, 1048576000, 99999999999))}
            code = '. ' + shlex.quote(str(CLASSES)) + '\n' + PROGRAM
            code += '\n. ' + shlex.quote(str(MODULE)) + '\n' + body
            return subprocess.run(['/bin/sh', '-eu', '-c', code], cwd=temporary,
                env=environment, capture_output=True, text=True, timeout=10)

    def test_all_profile_suffixes_and_controls_keep_the_correct_authority(self) -> None:
        for filesystem in ('btrfs', 'f2fs'):
            for family in ('de', 'srv'):
                for suffix in ('', '-duo', '-trio'):
                    for ceiling in (False, True):
                        for reuse in (False, True):
                            identifier = f'{filesystem}-{family}-fixture{suffix}'
                            with self.subTest(profile=identifier, ceiling=ceiling, reuse=reuse):
                                result = self.invoke('''runtime_prepare_layout_policy
printf '%s %s %s %s\\n' "$RUNTIME_PARTITION_MODE" "$MULTIBOOT_ENABLED" "$RUNTIME_LAYOUT_CEILING_BYTES" "${RUNTIME_DETECTED_EFI_SLOT:-none}"
if runtime_partman_fixed_layout_required; then printf 'fixed\\n'; else printf 'native\\n'; fi
''', profile=identifier, ceiling=ceiling, reuse=reuse)
                                self.assertEqual(result.returncode, 0, result.stderr)
                                mode = 'reuse' if reuse else ('append' if suffix else 'fresh')
                                end = 400000000000 if ceiling and not reuse else 500000000000
                                esp = 'none' if mode == 'fresh' else '1'
                                fixed = mode != 'fresh' or ceiling
                                self.assertEqual(result.stdout.splitlines(), [
                                    f'{mode} {str(bool(suffix)).lower()} {end} {esp}',
                                    'fixed' if fixed else 'native'])

    def test_disabled_controls_keep_the_native_disk_method_and_root_growth(self) -> None:
        result = self.invoke('''runtime_prepare_layout_policy
DEV_PART_ROOT_MB=50000
runtime_emit_partman_driver_answers
runtime_partman_root_max_mb
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('d-i partman-auto/disk string /dev/fixture\n', result.stdout)
        self.assertIn('d-i partman-auto/method string regular\n', result.stdout)
        self.assertNotIn('installer_target_free', result.stdout)
        self.assertTrue(result.stdout.endswith('1000000000\n'))

    def test_bounded_append_and_reuse_require_the_fixed_driver(self) -> None:
        for options in ({'ceiling': True}, {'multiboot': True}, {'reuse': True}):
            with self.subTest(options=options):
                result = self.invoke('''runtime_prepare_layout_policy
DEV_PART_ROOT_MB=50000
runtime_emit_partman_driver_answers
runtime_partman_root_max_mb
''', **options)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('d-i partman-auto/disk string\n', result.stdout)
                self.assertIn('d-i partman-auto/method string\n', result.stdout)
                self.assertIn('init_automatically_partition select installer_target_free\n', result.stdout)
                self.assertNotIn('partman-auto/method string regular', result.stdout)
                self.assertTrue(result.stdout.endswith('50000\n'))

    def test_encrypted_ordinary_profile_keeps_native_free_extent_partitioning(self) -> None:
        result = self.invoke('''runtime_prepare_layout_policy
DEV_PART_ROOT_MB=50000
runtime_emit_partman_driver_answers
runtime_partman_root_max_mb
''', crypto=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('init_automatically_partition select installer_target_free\n', result.stdout)
        self.assertTrue(result.stdout.endswith('1000000000\n'))

    def test_f2fs_root_recipe_and_formatter_keep_the_actual_filesystem(self) -> None:
        shared = MODULE.parents[3]
        for name in ('f2fs-02.recipe.tmpl', 'f2fs-03.recipe.tmpl'):
            recipe = (MODULE.parents[1] / 'templates' / name).read_text()
            self.assertIn('filesystem{ f2fs }', recipe)
            self.assertIn('mountpoint{ / }', recipe)
        finish = (shared / 'hooks/installer/partman/finish.d/99-storage-layout.sh').read_text()
        self.assertIn('f2fs_ensure_f2fs_filesystem "$DEV_PART_ROOT"', finish)
        self.assertNotIn('f2fs_ensure_ext4_filesystem "$DEV_PART_ROOT"', finish)

    def test_commit_guard_rejects_an_original_partition_missing_from_partman(self) -> None:
        adapter = MODULE.parents[3] / 'hooks/installer/partman/layout-option.sh'
        source = adapter.read_text()
        guard = re.search(r'^layout_assert_configured_geometry\(\) \{.*?^\}', source, re.M | re.S)
        self.assertIsNotNone(guard)
        program = r'''
runtime_prepare_layout_policy
DUALBOOT_ENABLED=true
runtime_layout_roles() { printf '%s\n' BOOT ROOT; }
runtime_role_device() {
  case "$1" in EFI) runtime_partition_path 1 ;; BOOT) runtime_partition_path 2 ;; ROOT) runtime_partition_path 4 ;; *) return 1 ;; esac
}
layout_die() { runtime_fatal "$*"; }
layout_find_partition() {
  case "$1" in
    /dev/fixturep1) printf '1048576-537919487\n' ;;
    /dev/fixturep2) printf '100000000000-100999999999\n' ;;
    /dev/fixturep3) ORIGINAL_FOREIGN_REPLY ;;
    /dev/fixturep4) printf '101000000000-199999999999\n' ;;
    *) return 1 ;;
  esac
}
open_dialog() { :; }
read_line() { num=; id=; size=; type=; fs=; path=; name=; }
close_dialog() { :; }
'''
        for reply, succeeds in (("printf '1048576000-99999999999\\n'", True), ('return 1', False)):
            with self.subTest(original_present=succeeds):
                result = self.invoke(program.replace('ORIGINAL_FOREIGN_REPLY', reply) +
                                     '\n' + guard[0] + '\nlayout_assert_configured_geometry\n', multiboot=True)
                if succeeds:
                    self.assertEqual(result.returncode, 0, result.stderr)
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('an original partition disappeared', result.stderr)

    def test_fresh_ceiling_is_absolute_decimal_mb(self) -> None:
        result = self.invoke('runtime_prepare_layout_policy; printf "%s %s\\n" "$RUNTIME_PARTITION_MODE" "$RUNTIME_LAYOUT_CEILING_BYTES"', ceiling=True)
        self.assertEqual((result.returncode, result.stdout), (0, 'fresh 400000000000\n'), result.stderr)

    def test_append_accounts_for_gaps_and_uses_free_gpt_numbers(self) -> None:
        result = self.invoke('''runtime_prepare_layout_policy
printf '%s %s %s\n' "$RUNTIME_DETECTED_EFI_SLOT" "$RUNTIME_EXISTING_END_MB" "$RUNTIME_EXISTING_END_BYTES"
runtime_policy_slot 0
runtime_policy_slot 1
''', multiboot=True, ceiling=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['1 100000 100000000000', '2', '4'])

    def test_reuse_ignores_ceiling_and_starts_at_the_configured_number(self) -> None:
        result = self.invoke('''runtime_prepare_layout_policy
printf '%s %s\n' "$RUNTIME_PARTITION_MODE" "$RUNTIME_LAYOUT_CEILING_BYTES"
runtime_policy_slot 0
runtime_policy_slot 10
''', reuse=True, ceiling=True, ceiling_mb='1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['reuse 500000000000', '5', '15'])

    def test_missing_esp_and_malformed_geometry_fail_before_mutation(self) -> None:
        missing = self.invoke('runtime_prepare_layout_policy', multiboot=True, esp=False)
        self.assertNotEqual(missing.returncode, 0)
        malformed = self.invoke('runtime_prepare_layout_policy', reuse=True,
            data=inventory((1, 1048576, 537919487)) + '\n2:badB:999B:4B::fixture:;')
        self.assertNotEqual(malformed.returncode, 0)

    def test_invalid_ceiling_inputs_are_rejected_as_data(self) -> None:
        for value in ('0', '-1', '0400000', '2147483648', '400000;id'):
            with self.subTest(value=value):
                result = self.invoke('runtime_prepare_layout_policy', ceiling=True, ceiling_mb=value)
                self.assertNotEqual(result.returncode, 0)
