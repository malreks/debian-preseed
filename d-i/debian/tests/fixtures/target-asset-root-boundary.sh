#!/bin/sh
# Isolated fixture for target-assets.sh.  The Python test invokes this only
# after tools/isolation.py has established a disposable no-host-mount image.
set -eu

fixture_root=$1
target_assets=$2
target_publication=$3
target_lifecycle=$4
target_root=$fixture_root/target
fixture_target_root=$target_root
installer_root=$fixture_root/installer
sibling_root=$fixture_root/sibling
marker=$sibling_root/marker

mkdir -p "$target_root" "$installer_root" "$sibling_root"
printf '%s\n' protected >"$marker"

INSTALLER_ROOT=$installer_root
DIR_INSTALLER_ROOT=$installer_root
INSTALLER_TARGET_DIR=$target_root
TARGET_ROOT=$target_root
INSTALLER_MOUNTS_FILE=$fixture_root/mounts
export INSTALLER_ROOT DIR_INSTALLER_ROOT INSTALLER_TARGET_DIR TARGET_ROOT INSTALLER_MOUNTS_FILE

installer_fatal() {
  printf 'fixture fatal: %s\n' "$*" >&2
  return 1
}

installer_fatal_status() {
  status=$1
  shift
  installer_fatal "$*"
  return "$status"
}

# The real helper reads the installer mount table.  This fixture exposes the
# same success/failure boundary without touching a host mount namespace.
installer_mounts_find_record() {
  [ "${1:-}" = "$fixture_target_root" ] || return 1
  INSTALLER_MOUNT_POINT=$fixture_target_root
  return 0
}

target_normalize_systemd_config_parent_modes() {
  :
}

# shellcheck disable=SC1090
. "$target_lifecycle"
# shellcheck disable=SC1090
. "$target_publication"
# shellcheck disable=SC1090
. "$target_assets"

expect_rejected() {
  label=$1
  candidate=$2
  before=$(cat "$marker")
  for path_lookup in target_asset_host_path target_asset_entry_host_path; do
    if INSTALLER_TARGET_DIR= TARGET_ROOT="$candidate" "$path_lookup" /etc/fixture; then
      printf 'fixture failure: %s accepted invalid target root (%s)\n' "$path_lookup" "$label" >&2
      exit 1
    fi
  done
  [ "$(cat "$marker")" = "$before" ] || {
    printf 'fixture failure: destination changed after rejection (%s)\n' "$label" >&2
    exit 1
  }
}

before=$(cat "$marker")
for path_lookup in target_asset_host_path target_asset_entry_host_path; do
  if (unset TARGET_ROOT INSTALLER_TARGET_DIR; "$path_lookup" /etc/fixture); then
    printf 'fixture failure: %s accepted an unset target root\n' "$path_lookup" >&2
    exit 1
  fi
done
[ "$(cat "$marker")" = "$before" ]
expect_rejected empty ''
expect_rejected root /
ln -s "$target_root" "$fixture_root/alias"
expect_rejected symlink "$fixture_root/alias"
expect_rejected installer-root "$installer_root"
expect_rejected sibling "$sibling_root"

before=$(cat "$marker")
for path_lookup in target_asset_host_path target_asset_entry_host_path; do
  if INSTALLER_TARGET_DIR="$target_root" TARGET_ROOT="$target_root" \
      "$path_lookup" "$sibling_root/etc/fixture"; then
    printf 'fixture failure: %s accepted a destination outside the target root\n' "$path_lookup" >&2
    exit 1
  fi
done
[ "$(cat "$marker")" = "$before" ]

INSTALLER_TARGET_DIR="$target_root" TARGET_ROOT="$target_root" \
  ensure_target_asset_parent /etc/fixture
[ -d "$target_root/etc" ] && [ ! -L "$target_root/etc" ]
printf '%s\n' 'target asset root boundary fixture passed'
