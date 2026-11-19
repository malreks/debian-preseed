"""Late provider schemas and complete foundation publication regressions.

Executable cases require the reviewed disposable image. Source-only audits can
inspect the literal fixture data without importing or executing this module.
"""
from __future__ import annotations

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation

require_test_isolation()

import re
import shlex
import subprocess
import tarfile
import tempfile
import unittest

from class_compiler import repository_data

ROOT = Path(__file__).resolve().parents[3]
TOKEN = re.compile(r'__INSTALLER_([A-Z][A-Z0-9_]*?)__')

FOUNDATION_ALL = r'''
set -eu
case "$FIXTURE_ROOT" in "$FIXTURE_BOUNDARY"/*) ;; *) exit 90 ;; esac
case "$FIXTURE_ROOT" in */../*|*/./*|*//*) exit 90 ;; esac
. "$FIXTURE_SOURCE/scripts/common/source.sh"
. "$FIXTURE_SOURCE/scripts/common/credentials.sh"
. "$FIXTURE_SOURCE/scripts/common/modules/credentials-probes.sh"
. "$FIXTURE_SOURCE/scripts/common/modules/files-logging.sh"
. "$FIXTURE_SOURCE/scripts/common/modules/profiles.sh"
. "$FIXTURE_SOURCE/scripts/common/modules/target-publication.sh"
. "$FIXTURE_SOURCE/scripts/common/modules/repository-apt.sh"
. "$FIXTURE_SOURCE/scripts/common/apt-sources.sh"
installer_fatal() { printf '%s\n' "$*" >&2; exit 1; }
installer_fatal_status() { status=$1; shift; installer_fatal "$@ (status=$status)"; }
installer_info() { printf '%s\n' "$*"; }
installer_error() { printf '%s\n' "$*" >&2; }
installer_apt_safe_path() {
  case "$1" in "$FIXTURE_ROOT"/*) ;; *) return 1 ;; esac
  case "$1" in */../*|*/./*|*//*) return 1 ;; esac
  [ ! -L "$1" ]
}
# Configuration, member validation and dynamic family selection use the real
# implementations. Acquisition alone maps exact members into this private copy.
source_load_repo_env "$FIXTURE_SOURCE/repo.env"
INSTALLER_REPO_ENV_READY=1
INSTALLER_REPO_SOURCE_ROOT=$FIXTURE_SOURCE
installer_seed_base() { printf '%s\n' "$FIXTURE_SOURCE"; }
bootstrap_repo_file_value() { installer_repo_file_value "$@"; }
bootstrap_parser_asset_path() { printf '%s/%s\n' "$FIXTURE_SOURCE" "$(installer_repo_file_value "$1")"; }
bootstrap_prepared_asset_published() { return 1; }
installer_fetch_file() {
  installer_validate_repo_file_value fixture_member "$2"
  installer_repo_assert_asset_family "$2"
  installer_apt_safe_path "$3" || exit 92
  fixture_input=$FIXTURE_SOURCE/$2
  [ -f "$fixture_input" ] && [ ! -L "$fixture_input" ] || exit 91
  cp "$fixture_input" "$3"; chmod "$4" "$3"
}
# The real target-context code checks the private directory and its ancestry.
# This exact fixture record replaces only the unavailable installation mount.
installer_mounts_find_record() {
  [ "$1" = "$FIXTURE_ROOT/target" ] || return 1
  INSTALLER_MOUNT_POINT=$1
  INSTALLER_MOUNT_SOURCE=private-fixture
  INSTALLER_MOUNT_FSTYPE=fixture
  INSTALLER_MOUNT_OPTIONS=rw
}
bootstrap_source_common_lib() { :; }
bootstrap_source_common_support_libs() { :; }
installer_ensure_context_loaded() { :; }
installer_fetch_host_env() { cp "$FIXTURE_ROOT/profile.env" "$3"; }
installer_assert_class_plan() { :; }
installer_runtime_state_dir() { printf '%s/state\n' "$FIXTURE_ROOT"; }
installer_class_metadata_read_path() {
  printf '%s/%s\n' "$FIXTURE_SOURCE" "$(installer_repo_file_value "$1")"
}
installer_snapshots_enabled() { [ "$TIMESHIFT_ENABLE" = true ]; }
installer_publish_class_receipt() { : >"$FIXTURE_ROOT/receipt-published"; }
sync() { :; } # The isolated fixture checks publication, not storage durability.
# Device identity and the mount record are private fixture data. No actual
# device discovery or target management command is used by this fixture.
blkid() { printf '%s\n' 00000000-0000-0000-0000-000000000001; }
. "$FIXTURE_SOURCE/scripts/common/system-foundation.sh"
[ -f "$FIXTURE_ROOT/receipt-published" ]
for unit in "$FILE_ZRAM_WRITEBACK_SERVICE" "$FILE_ZRAM_WRITEBACKD_SERVICE" \
  "$FILE_ZRAM_IDLE_WRITEBACK_TIMER" "$FILE_ZRAM_COLD_TIER_TIMER"; do
  grep -Fq "After=${FILE_ZRAM_SETUP_SERVICE##*/}" "$TARGET_ROOT$unit"
done
grep -Fq "ZRAM_SWAP_DEVICE=\"$ZRAM_SWAP_DEVICE\"" "$TARGET_ROOT$FILE_ZRAM_DEFAULT"
grep -Fq "/disk/by-partuuid/$ZRAM_BACKING_RAW_PARTUUID" "$TARGET_ROOT$FILE_ZRAM_DEFAULT"
printf 'FOUNDATION_COMPLETE family=%s account=%s\n' "$INSTALLER_HOST_VARIANT" "$ACCOUNT_USERNAME"
'''

BOOT_ASSETS = r'''
# Replay the actual headless provider through its complete publication loops.
# Signing, device mounts and in-target execution remain explicit fixture seams.
. "$FIXTURE_SOURCE/scripts/common/target.sh"
installer_fetch_file() {
  installer_validate_repo_file_value fixture_member "$2"
  installer_repo_assert_asset_family "$2"
  installer_apt_safe_path "$3" || exit 92
  [ -f "$FIXTURE_SOURCE/$2" ] && [ ! -L "$FIXTURE_SOURCE/$2" ] || exit 91
  cp "$FIXTURE_SOURCE/$2" "$3"; chmod "$4" "$3"
  if [ "$2" = scripts/late/grub.sh ]; then
    cat >>"$3" <<'FIXTURE_SEAMS'
stage_target_secure_boot_runtime_assets() { :; }
prepare_target_secure_boot_runtime() { :; }
sign_target_installed_kernel_modules() { :; }
repair_target_installed_kernels() { :; }
close_target_secure_boot_state() { :; }
late_command_require_class_policy_env() { late_command_set_grub_arch_policy; }
FIXTURE_SEAMS
  fi
}
target_mount_source() {
  case "$1" in
    "$TARGET_ROOT$DIR_BOOT") printf '%s\n' "$DEV_PART_BOOT" ;;
    "$TARGET_ROOT$DIR_BOOT_EFI") printf '%s\n' "$DEV_PART_EFI" ;;
    *) return 1 ;;
  esac
}
run_in_target() { :; }
installer_runtime_state_dir() { printf '%s/state\n' "$FIXTURE_ROOT"; }
. "$FIXTURE_SOURCE/scripts/server/boot.sh"
printf 'BOOT_ASSETS_COMPLETE arch=%s\n' "$INSTALLER_ARCH_CLASS"
'''

RENDER_EDGE_CASE = r'''
set -eu
. "$FIXTURE_SOURCE/scripts/common/modules/files-logging.sh"
fixture_etc="$FIXTURE_ROOT/a&b|c\\d=e"
fixture_tmp="$FIXTURE_ROOT/tmp"
installer_fatal() { printf '%s\n' "$*" >&2; exit 1; }
installer_runtime_path_placeholder_map() {
  printf 'PATH_DIR_ETC=%s\nPATH_DIR_TMP=%s\n' "$fixture_etc" "$fixture_tmp"
}
printf '%s\n' '__INSTALLER_PATH_DIR_ETC____INSTALLER_PATH_DIR_TMP__|__INSTALLER_SCALAR__' >"$FIXTURE_ROOT/input"
installer_apply_scalar_placeholders "$FIXTURE_ROOT/input" "$FIXTURE_ROOT/output" SCALAR 'literal&|\value'
printf '%s%s|%s\n' "$fixture_etc" "$fixture_tmp" 'literal&|\value' >"$FIXTURE_ROOT/expected"
cmp "$FIXTURE_ROOT/output" "$FIXTURE_ROOT/expected"
installer_runtime_path_placeholder_map() { printf '%s\n' 'UNSAFE|name=/value'; }
if installer_apply_scalar_placeholders "$FIXTURE_ROOT/input" "$FIXTURE_ROOT/output"; then exit 97; fi
cmp "$FIXTURE_ROOT/output" "$FIXTURE_ROOT/expected"
[ -z "$(find "$FIXTURE_ROOT" -name '*.sed.*' -print)" ]
printf 'RENDER_EDGE_CASE_PASS literal=true adjacent=true invalid_map_rejected=true\n'
'''


def repository_values(members: dict[str, bytes], suite: str) -> dict[str, str]:
    """Use the build parser and the vocabulary from this exact captured source."""
    schemas = re.findall(r"^  source_repo_supported='([^']+)'$",
                         members['scripts/common/source.sh'].decode(), re.M)
    if len(schemas) != 1:
        raise ValueError('fixture has no unique repository configuration schema')
    return repository_data(members['repo.env'].decode(), suite, set(schemas[0].split()))


def profile_assets(source: str, catalog: dict[str, str], members: dict[str, bytes],
                   family: str) -> set[str]:
    def locate(directory: str, leaf: str) -> str:
        roots = [catalog[directory]]
        if directory == 'DIR_TARGET_UNIT':
            roots = [catalog['DIR_TARGET_COMMON_UNIT'],
                     catalog[f'DIR_TARGET_SYSTEMD_{family.upper()}'] + '/system']
        candidates = set()
        for base in roots:
            path = base + '/' + leaf
            if path in members:
                candidates.add(path)
            elif path + '.tmpl' in members:
                candidates.add(path + '.tmpl')
        if len(candidates) != 1:
            raise AssertionError(f'missing or ambiguous asset owner: {directory}/{leaf}')
        return candidates.pop()

    text = source.replace('\\\n', ' ')
    result = set(re.findall(
        r'installer_stage_profile_file\s+["\']?([A-Za-z0-9_./@+-]+)', text))
    for member in result:
        if member not in members:
            raise AssertionError('fixed profile source is absent: ' + member)
    if 'installer_apt_install_target_policy' in source:
        roots = (catalog['DIR_TARGET_APT_APT_CONF_D'],
                 catalog[f'DIR_TARGET_APT_{family.upper()}_APT_CONF_D'])
        result.update(name for name in members if any(name.startswith(base + '/')
                      and '/' not in name[len(base) + 1:] for base in roots))
    # Resolve fixed literal loop inventories through their actual DIR selectors.
    for loop in re.finditer(r'for ([a-z_]+) in ([^;\n]+); do(.*?)\bdone\b', text, re.S):
        variable, inventory, body = loop.groups()
        if 'installer_stage_profile_asset' not in body:
            continue
        for directory, leaf in re.findall(r'installer_repo_asset_path (DIR_[A-Z0-9_]+) "([^"\n]+)"', body):
            if '${' + variable + '}' not in leaf and '$' + variable not in leaf:
                continue
            for value in shlex.split(inventory):
                if '$' in value:
                    raise AssertionError('dynamic loop requires an explicit asset contract')
                resolved = leaf.replace('${' + variable + '}', value).replace('$' + variable, value)
                result.add(locate(directory, resolved))
    if 'catalog/compiled/shared-perl-assets.tsv' in source:
        for line in members['catalog/compiled/shared-perl-assets.tsv'].decode().splitlines():
            fields = line.split('\t')
            if len(fields) == 3 and fields[2] in {'common', family}:
                result.add(fields[0])
    return result


class LateProfileAssets(unittest.TestCase):
    def test_family_child_initializes_logging_before_first_operation(self) -> None:
        # Execute only inside the guarded disposable test image. Stop at the
        # first asset fetch, before any target, device or service operation.
        program = r'''
set -eu
. "$FIXTURE_MODULE"
late_command_shared_init() {
  [ "$3" = "$FIXTURE_FAMILY" ] || exit 91
  fixture_initialized=true
  installer_info() { [ "$fixture_initialized" = true ]; }
}
late_command_fetch_common_assets_file() {
  [ "$fixture_initialized" = true ] || exit 92
  printf 'CHILD_INITIALIZED\n'
  exit 0
}
case "$FIXTURE_FAMILY" in
  btrfs|vm) run_btrfs_family_late_command "$FIXTURE_FAMILY" fixture fixture ;;
  f2fs) run_f2fs_family_late_command fixture fixture ;;
esac
'''
        for family in ('btrfs', 'vm', 'f2fs'):
            module = 'f2fs' if family == 'f2fs' else 'btrfs'
            with tempfile.TemporaryDirectory(prefix='late-child-') as temporary:
                result = subprocess.run(['/bin/sh', '-eu', '-c', program],
                    cwd=temporary, env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C',
                        'HOME': temporary, 'FIXTURE_FAMILY': family,
                        'FIXTURE_MODULE': str(ROOT / 'd-i/debian/scripts/late' /
                                              f'{module}-family.sh')},
                    capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('CHILD_INITIALIZED', result.stdout)

    def test_batched_path_map_keeps_literal_replacements_and_rejects_invalid_names(self) -> None:
        with tempfile.TemporaryDirectory(prefix='renderer-edge-') as temporary:
            result = subprocess.run(['/bin/sh', '-eu', '-c', RENDER_EDGE_CASE],
                cwd=temporary, env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C',
                    'HOME': temporary, 'FIXTURE_ROOT': temporary,
                    'FIXTURE_SOURCE': str(ROOT / 'd-i/debian')},
                capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('RENDER_EDGE_CASE_PASS', result.stdout)

    def test_every_late_provider_has_a_producer_for_each_profile_asset_field(self) -> None:
        for suite in ('forky', 'trixie'):
            with tarfile.open(ROOT / f'd-i/{suite}/payload.tar.gz') as archive:
                members = {item.name: archive.extractfile(item).read() for item in archive
                           if item.isfile() and item.size <= 16 * 1024 * 1024}
            catalog = repository_values(members, suite)
            layout = '\n'.join(members[f'scripts/runtime/{kind}.sh'].decode()
                               for kind in ('btrfs', 'f2fs'))
            layout_fields = set(re.findall(r"printf '([A-Z][A-Z0-9_]*)=", layout))
            account = members['scripts/common/modules/credentials-probes.sh'].decode()
            account_fields = set(re.findall(r'^  (ACCOUNT_[A-Z0-9_]+)=', account, re.M))
            grub = members['scripts/late/grub.sh'].decode()
            grub_fields = set(re.findall(r'grub_profile_config_value (GRUB_CONFIG_[A-Z0-9_]+)', grub))
            rows = [line.split('\t') for line in members['hooks/installer/class-dispatch.tsv'].decode().splitlines()]
            providers = [row for row in rows if row[0] == 'stage' and row[3] == 'late']
            profiles = {name: data for name, data in members.items()
                        if name.startswith(f'catalog/compiled/{suite}/profiles/')
                        and re.search(r'/profiles/(desktop|server)/[^/]+\.env$', name)
                        and not name.endswith('.account.env')}
            self.assertTrue(profiles)
            for name, data in profiles.items():
                family = name.split('/profiles/')[1].split('/')[0]
                configured = set(re.findall(rb'^([A-Z][A-Z0-9_]*)=', data, re.M))
                configured = {field.decode() for field in configured}
                for row in providers:
                    stage = row[2]
                    if stage.startswith(('desktop.', 'server.')) and not stage.startswith(family + '.'):
                        continue
                    if stage == 'os.timeshift' and b"TIMESHIFT_ENABLE='true'\n" not in data:
                        continue
                    self.assertIn(row[4], members, 'phase provider must name a physical member')
                    source = members[row[4]].decode()
                    produced = set(re.findall(r'\b([A-Z][A-Z0-9_]*)(?::)?=', source))
                    if 'installer_load_primary_account' in source:
                        produced |= account_fields
                    if re.search(r'^\. "\$(?:layout_env|crypto_layout)"$', source, re.M):
                        produced |= layout_fields
                    if 'render_grub_profile_config_map' in source:
                        produced |= grub_fields
                    for asset in sorted(profile_assets(source, catalog, members, family)):
                        fields = {field for field in TOKEN.findall(members[asset].decode())
                                  if not field.startswith('PATH_')}
                        with self.subTest(suite=suite, profile=name, stage=stage, asset=asset):
                            self.assertFalse(fields - configured - produced,
                                             f'{stage}: {asset}: {sorted(fields - configured - produced)}')

    def test_foundation_reaches_its_receipt_after_all_assets_and_links(self) -> None:
        for family, profile in (('desktop', 'btrfs-de'), ('server', 'btrfs-srv-flex')):
            with tempfile.TemporaryDirectory(prefix='late-foundation-') as temporary:
                boundary = Path(temporary)
                root = boundary / 'fixture'
                root.mkdir(mode=0o700)
                for leaf in ('target', 'state', 'env', 'late', 'home', 'ownership'):
                    (root / leaf).mkdir(mode=0o700)
                (root / 'target/etc/apt').mkdir(parents=True, mode=0o755)
                source = root / 'source'
                source.mkdir(mode=0o700)
                with tarfile.open(ROOT / 'd-i/forky/payload.tar.gz') as archive:
                    count = total = 0
                    for member in archive:
                        count += 1
                        total += member.size
                        if (count > 10000 or total > 256 * 1024 * 1024 or not member.isfile()
                                or member.name.startswith('/') or '..' in member.name.split('/')):
                            self.fail('unsafe foundation fixture input')
                        destination = source / member.name
                        destination.parent.mkdir(parents=True, exist_ok=True)
                        destination.write_bytes(archive.extractfile(member).read())
                (root / 'profile.env').write_bytes((source / f'catalog/compiled/forky/profiles/{family}/{profile}.env').read_bytes())
                (root / 'bootstrap.sh').write_text('# fixture bootstrap\n', encoding='ascii')
                (root / 'state/runtime.env').write_text(
                    "ZRAM_BACKING_RAW_DEVICE='/dev/fixture-zram'\nZRAM_SWAP_DEVICE='/dev/zram0'\n"
                    "ZRAM_BACKING_DEVICE='/dev/mapper/fixture-zram'\n"
                    "ZRAM_BACKING_MAPPER_NAME='fixture-zram'\nSWAP_FALLBACK_RAW_DEVICE='/dev/fixture-swap'\n"
                    "SWAP_FALLBACK_MAPPER_NAME='fixture-swap'\nROOT_CRYPT_NAME='fixture-root'\n"
                    "DEV_PART_ROOT='/dev/fixture-root'\nDEV_PART_BOOT='/dev/fixture-boot'\n"
                    "DEV_PART_EFI='/dev/fixture-efi'\n", encoding='ascii')
                (root / 'preseed.env').write_text("PRESEED_PRIMARY_USERNAME='fixtureuser'\n", encoding='ascii')
                (root / 'preseed.env').chmod(0o600)
                environment = {'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'LC_ALL': 'C',
                    'HOME': str(root / 'home'), 'FIXTURE_BOUNDARY': str(boundary),
                    'FIXTURE_ROOT': str(root), 'FIXTURE_SOURCE': str(source),
                    'FIXTURE_FAMILY_UPPER': family.upper(), 'INSTALLER_HOST_VARIANT': family,
                    'INSTALLER_ARCH_CLASS': 'amd64', 'INSTALLER_SUITE': 'forky',
                    'TMPDIR': str(root), 'TMP': str(root), 'TEMP': str(root),
                    'DIR_INSTALLER_TARGET_OWNERSHIP': str(root / 'ownership'),
                    'INSTALLER_HOST_PROFILE': profile, 'INSTALLER_CMDLINE': 'quiet',
                    'INSTALLER_PRESEED_ENV_FILE': str(root / 'preseed.env'),
                    'INSTALLER_BOOTSTRAP_LIB': str(root / 'bootstrap.sh'),
                    'DIR_INSTALLER_ENV': str(root / 'env'), 'DIR_INSTALLER_LATE_ENV': str(root / 'late'),
                    'TARGET_ROOT': str(root / 'target')}
                program = FOUNDATION_ALL + (BOOT_ASSETS if family == 'server' else '')
                result = subprocess.run(['/bin/sh', '-eu', '-c', program],
                    cwd=root, env=environment, capture_output=True, text=True, timeout=120)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f'FOUNDATION_COMPLETE family={family} account=fixtureuser', result.stdout)
                if family == 'server':
                    self.assertIn('BOOT_ASSETS_COMPLETE arch=amd64', result.stdout)
