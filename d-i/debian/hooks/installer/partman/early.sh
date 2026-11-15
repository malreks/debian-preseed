#!/bin/sh

partman_early_require_command() {
  command -v "$1" >/dev/null 2>&1 || installer_fatal "required command is unavailable: $1"
}

PARTMAN_EARLY_WIPEFS_WARNED=${PARTMAN_EARLY_WIPEFS_WARNED:-false}

partman_early_assert_selected_disk() (
  if command -v installer_operation_context >/dev/null 2>&1; then
    installer_operation_context_repo FILE_INST_PARTMAN_EARLY 11 partman_early_assert_selected_disk
  fi
  "${TMP_ENV_DIR:?TMP_ENV_DIR must be set}/detect-disk.sh" --verify-identity \
    "${DEV_INSTALL_DISK:?DEV_INSTALL_DISK must be set}" \
    "${FILE_INSTALLER_SELECTED_DISK_IDENTITY:?selected disk identity path must be loaded}" \
    "${1:-$DEV_INSTALL_DISK}" || {
      installer_fatal 'selected physical disk identity changed before storage mutation'
      return 1
    }
)

partman_early_clear_signatures() {
  dev=$1

  if command -v wipefs >/dev/null 2>&1; then
    partman_early_assert_selected_disk "$dev" || return 1
    wipefs -a -f "$dev" || {
      installer_fatal "failed to clear storage signatures from ${dev}"
      return 1
    }
    return 0
  fi

  if [ "$PARTMAN_EARLY_WIPEFS_WARNED" != true ]; then
    installer_warn "wipefs is not shipped in the Debian Installer udebs; continuing with validated partition deletion and GPT reinitialization"
    PARTMAN_EARLY_WIPEFS_WARNED=true
  fi
}

partman_early_settle_block_devices() {
  disk=${1:-${DEV_DISK_BLOCK:-}}

  [ -n "$disk" ] || installer_fatal "partman_early_settle_block_devices requires a disk path"
  if command -v partprobe >/dev/null 2>&1; then
    partprobe "$disk" || installer_warn "partprobe failed for ${disk}"
  fi
  if command -v udevadm >/dev/null 2>&1; then
    udevadm settle || installer_warn "udevadm settle failed for ${disk}"
  fi
}

partman_early_log_partition_state() {
  label=$1
  disk=${2:-${DEV_DISK_BLOCK:-}}

  [ -n "$disk" ] || installer_fatal "partman_early_log_partition_state requires a disk path"
  installer_info "${label}: sfdisk --json ${disk}"
  sfdisk --json "$disk" 2>/dev/null || installer_warn "sfdisk --json failed during ${label} for ${disk}"
  installer_info "${label}: parted -sm ${disk} unit MiB print free"
  parted -sm "$disk" unit MiB print free 2>/dev/null || installer_warn "parted print free failed during ${label} for ${disk}"
}

partman_early_reinitialize_gpt_disk() {
  disk=${1:-${DEV_DISK_BLOCK:-}}

  [ -n "$disk" ] || installer_fatal "partman_early_reinitialize_gpt_disk requires a disk path"
  installer_info "reinitializing GPT label on ${disk} using sfdisk + parted"
  partman_early_assert_selected_disk "$disk" || return 1
  sfdisk --delete "$disk" >/dev/null 2>&1 || true
  partman_early_assert_selected_disk "$disk" || return 1
  parted -s "$disk" mklabel gpt || installer_fatal "failed to create GPT label on ${disk} with parted"
  partman_early_settle_block_devices "$disk"
  partman_early_log_partition_state "after-gpt-label" "$disk"
}

partman_early_sanitize_install_disk() {
  disk=${1:-${DEV_DISK_BLOCK:-}}

  [ -n "$disk" ] || installer_fatal "partman_early_sanitize_install_disk requires a disk path"
  case "$disk" in
    /dev/*) ;;
    *) installer_fatal "install disk must be an absolute /dev path: ${disk}" ;;
  esac
  [ -b "$disk" ] || installer_fatal "install disk is not a block device: ${disk}"

  disk_discarded=false
  if command -v blkdiscard >/dev/null 2>&1; then
    partman_early_assert_selected_disk "$disk" || return 1
    if blkdiscard -f "$disk" >/dev/null 2>&1; then
      disk_discarded=true
    else
      installer_warn "blkdiscard failed for ${disk}; continuing with partition metadata cleanup"
    fi
  fi

  if [ "$disk_discarded" != true ]; then
    # Enumerate only actual children of this disk. A /dev/sda* glob can also
    # match an unrelated /dev/sdaa disk and its partitions.
    for partition_sys in "/sys/class/block/${disk##*/}/"*; do
      [ -f "$partition_sys/partition" ] || continue
      dev="/dev/${partition_sys##*/}"
      [ -b "$dev" ] || continue
      partman_early_clear_signatures "$dev"
    done
    partman_early_clear_signatures "$disk"
  fi

  partman_early_reinitialize_gpt_disk "$disk"
}

partman_early_prepare_layout() {
  partman_early_require_command parted
  partman_early_require_command sfdisk
  partman_early_assert_selected_disk "$DEV_INSTALL_DISK" || return 1
  prep_state="$(installer_runtime_state_dir)/partition-preparation"
  [ ! -e "$prep_state" ] && [ ! -L "$prep_state" ] ||
    installer_fatal 'partition preparation already started; retain installer state and do not repeat a possibly partial mutation'
  # Claim the operation before mutation. Failure retains this evidence and the
  # partman state; it must not trigger another whole-disk wipe on re-entry.
  (set -C; umask 077; printf '%s\n' running >"$prep_state") || return 1
  case "${RUNTIME_PARTITION_MODE:?validated partition mode required}" in
    fresh)
      partman_early_sanitize_install_disk "$DEV_INSTALL_DISK" || return 1
      # Preserve the established fresh-install partman state initialization.
      # These are Debian partman discovery markers, not target LVM metadata.
      install -d -m 0755 "$DIR_INSTALLER_VAR_LIB_PARTMAN" || return 1
      : >"$DIR_INSTALLER_VAR_LIB_PARTMAN/lvm" || return 1
      : >"$DIR_INSTALLER_VAR_LIB_PARTMAN/md" || return 1
      ;;
    append|reuse)
      prep_inventory=$(runtime_partition_inventory) || installer_fatal 'cannot revalidate the preserved partition inventory'
      prep_hash=$(printf '%s\n' "$prep_inventory" | source_hash) || return 1
      [ "${prep_hash%% *}" = "$RUNTIME_PARTITION_INVENTORY_HASH" ] ||
        installer_fatal 'partition geometry changed after the layout was planned'
      prep_identity=$(runtime_partition_identity_hash) || return 1
      [ "${prep_identity%% *}" = "$RUNTIME_PARTITION_IDENTITY_HASH" ] ||
        installer_fatal 'preserved GPT identities changed after the layout was planned'
      ;;
    *) installer_fatal 'invalid partition preparation mode' ;;
  esac
  if ! runtime_partman_fixed_layout_required && ! runtime_any_crypto_enabled; then
    # Ordinary profiles retain the native partman-auto disk/method contract.
    # Do not install a fixed-layout commit guard for a native recipe.
    printf '%s\n' prepared >"$prep_state" || return 1
    installer_info 'prepared ordinary fresh layout using native partman-auto'
    return 0
  fi
  option_source=$(installer_repo_file_value FILE_INST_PARTMAN_LAYOUT_OPTION) || return 1
  option_program="$TMP_ENV_DIR/partman-layout-option.sh"
  fetch_hook_file "$option_source" "$option_program" || return 1
  option_dir="${DIR_INSTALLER_LIB_PARTMAN}/automatically_partition/installer_target_free"
  install -d -m 0755 "$option_dir" || return 1
  for option_action in choices do_option; do
    {
      printf '%s\n' '#!/bin/sh'
      printf 'INSTALLER_RUNTIME_DIR=%s\nexport INSTALLER_RUNTIME_DIR\n' "$(installer_shell_quote "$(installer_runtime_dir)")"
      printf 'exec /bin/sh %s %s "$@"\n' "$(installer_shell_quote "$option_program")" "$option_action"
    } >"$option_dir/$option_action" || return 1
    chmod 0755 "$option_dir/$option_action" || return 1
  done
  if runtime_partman_fixed_layout_required; then
    # A partial bounded/reuse application must never reach formatting commits.
    check_hook="${DIR_INSTALLER_LIB_PARTMAN}/check.d/05-installer-layout"
    {
      printf '%s\n' '#!/bin/sh' 'set -eu'
      printf 'INSTALLER_RUNTIME_DIR=%s\nexport INSTALLER_RUNTIME_DIR\n' "$(installer_shell_quote "$(installer_runtime_dir)")"
      printf 'exec /bin/sh %s check\n' "$(installer_shell_quote "$option_program")"
    } >"$check_hook" || return 1
    chmod 0755 "$check_hook" || return 1
  fi
  printf '%s\n' prepared >"$prep_state" || return 1
  installer_info "prepared selected-disk partition handler: mode=$RUNTIME_PARTITION_MODE; ceiling_enabled=$PARTMAN_CEILING_ENABLE; ceiling_bytes=$RUNTIME_LAYOUT_CEILING_BYTES"
}
