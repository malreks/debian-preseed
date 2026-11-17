#!/bin/sh
# F2FS/ext4 runtime layout helpers.
# shellcheck disable=SC2034

if [ "${RUNTIME_COMMON_READY:-0}" != 1 ]; then
  if [ -n "${RUNTIME_COMMON_LIB:-}" ] && [ -r "$RUNTIME_COMMON_LIB" ]; then
    # shellcheck disable=SC1090
    . "$RUNTIME_COMMON_LIB" || return "$?"
  else
    echo "fatal: runtime common helper is unavailable; set RUNTIME_COMMON_LIB before sourcing ${0##*/}" >&2
    exit 1
  fi
fi

RUNTIME_RECIPE_TEMPLATES="f2fs-01.recipe.tmpl f2fs-02.recipe.tmpl f2fs-03.recipe.tmpl f2fs-04.recipe.tmpl f2fs-05.recipe.tmpl f2fs-06.recipe.tmpl f2fs-07.recipe.tmpl f2fs-08.recipe.tmpl f2fs-09.recipe.tmpl f2fs-10.recipe.tmpl"

runtime_secure_boot_state_mode() {
  secure_boot_mode=${SECURE_BOOT_MODE:-}
  secure_boot_state_mode=${SECURE_BOOT_STATE_MODE:-}
  if [ -n "$secure_boot_mode" ] && [ -n "$secure_boot_state_mode" ] && [ "$secure_boot_mode" != "$secure_boot_state_mode" ]; then
    runtime_fatal "SECURE_BOOT_MODE and SECURE_BOOT_STATE_MODE disagree: '${secure_boot_mode}' != '${secure_boot_state_mode}'"
    return 1
  fi
  mode=${secure_boot_mode:-${secure_boot_state_mode:-direct}}
  case "$mode" in
    direct|luks)
      printf '%s\n' "$mode"
      ;;
    *)
      runtime_fatal "SECURE_BOOT_MODE/SECURE_BOOT_STATE_MODE must be 'direct' or 'luks' for F2FS profiles, got '${mode}'"
      return 1
      ;;
  esac
}

runtime_crypto_answers_required() {
  runtime_any_crypto_enabled || runtime_secure_boot_state_uses_luks
}

runtime_required_slot_from_env() {
  label=$1
  eval "value=\${$label:-}"
  runtime_require_positive_integer "$label" "$value"
  printf '%s\n' "$value"
}

runtime_optional_slot_from_env() {
  label=$1
  eval "value=\${$label:-}"
  if [ -z "$value" ]; then
    printf '\n'
    return 0
  fi
  runtime_require_positive_integer "$label" "$value"
  printf '%s\n' "$value"
}

runtime_sum_preserved_partition_sizes_mb() {
  printf '%s\n' "${RUNTIME_EXISTING_END_MB:-0}"
}

runtime_validate_layout_slots() {
  layout_seen=' '
  for layout_slot in "$RUNTIME_EFI_SLOT" "$RUNTIME_BOOT_SLOT" "$RUNTIME_ROOT_SLOT" \
    "${RUNTIME_HOME_SLOT:-}" "${RUNTIME_POOL_SLOT:-}" "${RUNTIME_VAR_LIB_SHSIGNED_SLOT:-}" \
    "$RUNTIME_VAR_LOG_JOURNAL_SLOT" "$RUNTIME_RAW_SWAP_SLOT" "$RUNTIME_RAW_ZRAM_SLOT"; do
    [ -n "$layout_slot" ] || continue
    runtime_require_positive_integer runtime_layout_slot "$layout_slot"
    [ "$layout_slot" -le 128 ] || runtime_fatal 'F2FS layout exceeds GPT partition limit'
    case "$layout_seen" in *" $layout_slot "*) runtime_fatal 'F2FS layout has overlapping partition slots' ;; esac
    layout_seen="$layout_seen$layout_slot "
  done
}

runtime_assign_default_slots() {
  DUALBOOT_ENABLED=false
  DUALBOOT_EFI_SLOT=
  DUALBOOT_DEBIAN_SLOT=
  RUNTIME_PRESERVED_SLOTS=
  RUNTIME_EFI_SLOT=$(runtime_required_slot_from_env DEFAULT_EFI_SLOT)
  RUNTIME_BOOT_SLOT=$(runtime_required_slot_from_env DEFAULT_BOOT_SLOT)
  RUNTIME_ROOT_SLOT=$(runtime_required_slot_from_env DEFAULT_ROOT_SLOT)
  RUNTIME_HOME_SLOT=$(runtime_optional_slot_from_env DEFAULT_HOME_SLOT)
  RUNTIME_POOL_SLOT=$(runtime_optional_slot_from_env DEFAULT_POOL_SLOT)
  RUNTIME_VAR_LOG_JOURNAL_SLOT=$(runtime_required_slot_from_env DEFAULT_VAR_LOG_JOURNAL_SLOT)
  RUNTIME_RAW_SWAP_SLOT=$(runtime_required_slot_from_env DEFAULT_RAW_SWAP_SLOT)
  RUNTIME_RAW_ZRAM_SLOT=$(runtime_required_slot_from_env DEFAULT_RAW_ZRAM_SLOT)
  RUNTIME_VAR_LIB_SHSIGNED_SLOT=

  if [ "${F2FS_QEMU_POOL_ENABLED:-false}" = true ] && [ -z "$RUNTIME_POOL_SLOT" ]; then
    RUNTIME_POOL_SLOT=$RUNTIME_VAR_LOG_JOURNAL_SLOT
    RUNTIME_VAR_LOG_JOURNAL_SLOT=$((RUNTIME_VAR_LOG_JOURNAL_SLOT + 1))
    RUNTIME_RAW_SWAP_SLOT=$((RUNTIME_RAW_SWAP_SLOT + 1))
    RUNTIME_RAW_ZRAM_SLOT=$((RUNTIME_RAW_ZRAM_SLOT + 1))
  fi
}

runtime_configure_qemu_pool() {
  F2FS_QEMU_POOL_ENABLED=false
  runtime_qemu_class_selected || return 0

  [ "$F2FS_LAYOUT_VARIANT" = desktop ] ||
    runtime_fatal "the selected virtualization class requires an F2FS desktop layout"

  qemu_pool_mb=${SIZE_PART_QEMU_POOL_MB:-}
  qemu_pool_min_mb=${SIZE_PART_QEMU_POOL_MIN_MB:-$qemu_pool_mb}
  runtime_require_positive_integer SIZE_PART_QEMU_POOL_MB "$qemu_pool_mb"
  runtime_require_positive_integer SIZE_PART_QEMU_POOL_MIN_MB "$qemu_pool_min_mb"
  [ "$qemu_pool_min_mb" -le "$qemu_pool_mb" ] ||
    runtime_fatal "SIZE_PART_QEMU_POOL_MIN_MB must not exceed SIZE_PART_QEMU_POOL_MB"

  F2FS_QEMU_POOL_ENABLED=true
  SIZE_PART_POOL_MB=$qemu_pool_mb
  SIZE_PART_POOL_MIN_MB=$qemu_pool_min_mb
}

runtime_assign_dualboot_slots() {
  DUALBOOT_ENABLED=true
  RUNTIME_EFI_SLOT=$RUNTIME_DETECTED_EFI_SLOT
  DUALBOOT_EFI_SLOT=$RUNTIME_EFI_SLOT
  layout_offset=0
    RUNTIME_BOOT_SLOT=$(runtime_policy_slot "$layout_offset") || runtime_fatal 'not enough GPT partition numbers for the complete layout'
    layout_offset=$((layout_offset + 1))
    RUNTIME_ROOT_SLOT=$(runtime_policy_slot "$layout_offset") || runtime_fatal 'not enough GPT partition numbers for the complete layout'
    layout_offset=$((layout_offset + 1))
  if [ -n "${DEFAULT_HOME_SLOT:-}" ]; then
    RUNTIME_HOME_SLOT=$(runtime_policy_slot "$layout_offset") || runtime_fatal 'not enough GPT partition numbers for the complete layout'
    layout_offset=$((layout_offset + 1))
  else
    RUNTIME_HOME_SLOT=
  fi
  if [ -n "${DEFAULT_POOL_SLOT:-}" ] || [ "${F2FS_QEMU_POOL_ENABLED:-false}" = true ]; then
    RUNTIME_POOL_SLOT=$(runtime_policy_slot "$layout_offset") || runtime_fatal 'not enough GPT partition numbers for the complete layout'
    layout_offset=$((layout_offset + 1))
  else
    RUNTIME_POOL_SLOT=
  fi
  if [ "$(runtime_secure_boot_state_mode)" = luks ]; then
    RUNTIME_VAR_LIB_SHSIGNED_SLOT=$(runtime_policy_slot "$layout_offset") || runtime_fatal 'not enough GPT partition numbers for the complete layout'
    layout_offset=$((layout_offset + 1))
  else
    RUNTIME_VAR_LIB_SHSIGNED_SLOT=
  fi
    RUNTIME_VAR_LOG_JOURNAL_SLOT=$(runtime_policy_slot "$layout_offset") || runtime_fatal 'not enough GPT partition numbers for the complete layout'
    layout_offset=$((layout_offset + 1))
    RUNTIME_RAW_SWAP_SLOT=$(runtime_policy_slot "$layout_offset") || runtime_fatal 'not enough GPT partition numbers for the complete layout'
    layout_offset=$((layout_offset + 1))
    RUNTIME_RAW_ZRAM_SLOT=$(runtime_policy_slot "$layout_offset") || runtime_fatal 'not enough GPT partition numbers for the complete layout'
    layout_offset=$((layout_offset + 1))
  DUALBOOT_DEBIAN_SLOT=$RUNTIME_BOOT_SLOT
  RUNTIME_PRESERVED_SLOTS=
}

runtime_apply_layout_from_cmdline() {
  installer_resolve_install_target_defaults
  : "${DEV_INSTALL_DISK:?DEV_INSTALL_DISK must be set}"
  F2FS_LAYOUT_VARIANT=${F2FS_LAYOUT_VARIANT:-custom}
  PARTMAN_RECIPE_NAME=${PARTMAN_RECIPE_NAME:-f2fs-layout}
  secure_boot_state_mode=$(runtime_secure_boot_state_mode)
  runtime_derive_part_prefix
  runtime_configure_qemu_pool

  runtime_prepare_layout_policy
  if [ "$RUNTIME_PARTITION_MODE" != fresh ]; then
    runtime_assign_dualboot_slots
  else
    runtime_assign_default_slots
  fi

  if [ "$secure_boot_state_mode" = "luks" ] && [ -z "${RUNTIME_VAR_LIB_SHSIGNED_SLOT:-}" ]; then
    RUNTIME_VAR_LIB_SHSIGNED_SLOT=$RUNTIME_VAR_LOG_JOURNAL_SLOT
    RUNTIME_VAR_LOG_JOURNAL_SLOT=$((RUNTIME_VAR_LOG_JOURNAL_SLOT + 1))
    RUNTIME_RAW_SWAP_SLOT=$((RUNTIME_RAW_SWAP_SLOT + 1))
    RUNTIME_RAW_ZRAM_SLOT=$((RUNTIME_RAW_ZRAM_SLOT + 1))
  fi
  runtime_validate_layout_slots
  RUNTIME_DEBIAN_START_SLOT=$RUNTIME_BOOT_SLOT
  RUNTIME_DEBIAN_END_SLOT=$RUNTIME_RAW_ZRAM_SLOT

  DEV_PART_EFI=$(runtime_partition_path "$RUNTIME_EFI_SLOT")
  DEV_PART_BOOT=$(runtime_partition_path "$RUNTIME_BOOT_SLOT")
  DEV_PART_ROOT=$(runtime_partition_path "$RUNTIME_ROOT_SLOT")
  if [ -n "${RUNTIME_HOME_SLOT:-}" ]; then
    DEV_PART_HOME=$(runtime_partition_path "$RUNTIME_HOME_SLOT")
  else
    DEV_PART_HOME=
  fi
  if [ -n "${RUNTIME_POOL_SLOT:-}" ]; then
    DEV_PART_POOL=$(runtime_partition_path "$RUNTIME_POOL_SLOT")
  else
    DEV_PART_POOL=
  fi
  if [ -n "${RUNTIME_VAR_LIB_SHSIGNED_SLOT:-}" ]; then
    DEV_PART_VAR_LIB_SHSIGNED=$(runtime_partition_path "$RUNTIME_VAR_LIB_SHSIGNED_SLOT")
  else
    DEV_PART_VAR_LIB_SHSIGNED=
  fi
  DEV_PART_VAR_LOG_JOURNAL=$(runtime_partition_path "$RUNTIME_VAR_LOG_JOURNAL_SLOT")
  DEV_PART_RAW_SWAP=$(runtime_partition_path "$RUNTIME_RAW_SWAP_SLOT")
  DEV_PART_RAW_ZRAM=$(runtime_partition_path "$RUNTIME_RAW_ZRAM_SLOT")
  ZRAM_BACKING_RAW_DEVICE=$DEV_PART_RAW_ZRAM
  ZRAM_BACKING_MAPPER_NAME=${ZRAM_BACKING_MAPPER_NAME:-zram-writeback}
  ZRAM_BACKING_DEVICE="/dev/mapper/${ZRAM_BACKING_MAPPER_NAME}"
  SWAP_FALLBACK_RAW_DEVICE=$DEV_PART_RAW_SWAP
  SWAP_FALLBACK_MAPPER_NAME=${SWAP_FALLBACK_MAPPER_NAME:-swap-fallback}
  SWAP_FALLBACK_MAPPER="/dev/mapper/${SWAP_FALLBACK_MAPPER_NAME}"
}

runtime_compute_layout_sizing() {
  if [ "${RUNTIME_PARTITION_MODE:-fresh}" = reuse ]; then
    DEV_PART_HOME_MB=0
    DEV_PART_POOL_MB=0
    DEV_PART_VAR_LIB_SHSIGNED_MB=0
    runtime_apply_reuse_sizing
    return "$?"
  fi
  disk_total_mb=$(runtime_policy_disk_budget_mb)
  ram_total_mib=$(runtime_total_ram_mib)
  preserved_total_mb=$(runtime_sum_preserved_partition_sizes_mb)

  runtime_require_positive_integer SIZE_LAYOUT_SAFETY_MARGIN_MB "$SIZE_LAYOUT_SAFETY_MARGIN_MB"
  usable_budget_mb=$((disk_total_mb - preserved_total_mb - SIZE_LAYOUT_SAFETY_MARGIN_MB))
  [ "$usable_budget_mb" -gt 0 ] || runtime_fatal "usable install budget on ${DEV_INSTALL_DISK} collapsed to ${usable_budget_mb} MB after preserved partitions and safety margin"

  runtime_require_positive_integer SIZE_PART_EFI_MB "$SIZE_PART_EFI_MB"
  runtime_require_positive_integer SIZE_PART_BOOT_MB "$SIZE_PART_BOOT_MB"
  runtime_require_positive_integer SIZE_PART_ROOT_MB "$SIZE_PART_ROOT_MB"
  runtime_require_nonnegative_integer SIZE_PART_HOME_MB "$SIZE_PART_HOME_MB"
  runtime_require_positive_integer SIZE_PART_VAR_LOG_JOURNAL_MB "$SIZE_PART_VAR_LOG_JOURNAL_MB"
  runtime_require_positive_integer SIZE_PART_RAW_SWAP_MB "$SIZE_PART_RAW_SWAP_MB"
  runtime_require_positive_integer SIZE_PART_RAW_ZRAM_MB "$SIZE_PART_RAW_ZRAM_MB"
  runtime_require_nonnegative_integer SIZE_PART_POOL_MB "$SIZE_PART_POOL_MB"
  runtime_require_nonnegative_integer SIZE_PART_VAR_LIB_SHSIGNED_MB "$SIZE_PART_VAR_LIB_SHSIGNED_MB"
  runtime_require_nonnegative_integer SIZE_PART_HOME_TARGET_MB "$SIZE_PART_HOME_TARGET_MB"

  DEV_PART_RAW_ZRAM_MB=$(runtime_compute_raw_zram_partition_mb "$usable_budget_mb" "$usable_budget_mb")
  SWAP_SIZE_MIB=$(runtime_compute_swap_partition_mib "$usable_budget_mb" "$ram_total_mib")
  DEV_PART_RAW_SWAP_MB=$(runtime_mib_to_recipe_mb SWAP_SIZE_MIB "$SWAP_SIZE_MIB")

  if [ "${DUALBOOT_ENABLED:-false}" = "true" ]; then
    DEV_PART_EFI_MB=$(runtime_get_partition_size_mb "$RUNTIME_EFI_SLOT") || \
      runtime_fatal "missing measured EFI partition size for dual-boot slot ${RUNTIME_EFI_SLOT}"
    efi_recipe_mb=0
  else
    DEV_PART_EFI_MB=$SIZE_PART_EFI_MB
    efi_recipe_mb=$DEV_PART_EFI_MB
  fi
  DEV_PART_BOOT_MB=$SIZE_PART_BOOT_MB
  DEV_PART_ROOT_MB=$SIZE_PART_ROOT_MB
  DEV_PART_HOME_MB=$SIZE_PART_HOME_MB
  DEV_PART_POOL_MB=$SIZE_PART_POOL_MB
  DEV_PART_VAR_LIB_SHSIGNED_MB=0
  if runtime_secure_boot_state_uses_luks; then
    runtime_require_positive_integer SIZE_PART_VAR_LIB_SHSIGNED_MB "$SIZE_PART_VAR_LIB_SHSIGNED_MB"
    DEV_PART_VAR_LIB_SHSIGNED_MB=$SIZE_PART_VAR_LIB_SHSIGNED_MB
  fi
  DEV_PART_VAR_LOG_JOURNAL_MB=$SIZE_PART_VAR_LOG_JOURNAL_MB

  base_total_mb=$((efi_recipe_mb + DEV_PART_BOOT_MB + DEV_PART_ROOT_MB + DEV_PART_HOME_MB + DEV_PART_POOL_MB + DEV_PART_VAR_LIB_SHSIGNED_MB + DEV_PART_VAR_LOG_JOURNAL_MB + DEV_PART_RAW_SWAP_MB + DEV_PART_RAW_ZRAM_MB))
  if [ "$base_total_mb" -gt "$usable_budget_mb" ]; then
    overflow_mb=$((base_total_mb - usable_budget_mb))

    pool_floor_mb=$(runtime_min "$DEV_PART_POOL_MB" "${SIZE_PART_POOL_MIN_MB:-0}")
    home_floor_mb=$(runtime_min "$DEV_PART_HOME_MB" "${SIZE_PART_HOME_MIN_MB:-0}")
    var_log_journal_floor_mb=$(runtime_min "$DEV_PART_VAR_LOG_JOURNAL_MB" "${SIZE_PART_VAR_LOG_JOURNAL_MIN_MB:-256}")
    efi_floor_mb=$(runtime_min "$DEV_PART_EFI_MB" "${SIZE_PART_EFI_MIN_MB:-256}")
    boot_floor_mb=$(runtime_min "$DEV_PART_BOOT_MB" "${SIZE_PART_BOOT_MIN_MB:-512}")
    root_floor_mb=$(runtime_min "$DEV_PART_ROOT_MB" "${SIZE_PART_ROOT_MIN_MB:-4096}")

    runtime_apply_fill_result DEV_PART_POOL_MB overflow_mb \
      "$(runtime_shrink_partition_to_floor "$DEV_PART_POOL_MB" "$pool_floor_mb" "$overflow_mb")"
    runtime_apply_fill_result DEV_PART_HOME_MB overflow_mb \
      "$(runtime_shrink_partition_to_floor "$DEV_PART_HOME_MB" "$home_floor_mb" "$overflow_mb")"
    runtime_apply_fill_result DEV_PART_VAR_LOG_JOURNAL_MB overflow_mb \
      "$(runtime_shrink_partition_to_floor "$DEV_PART_VAR_LOG_JOURNAL_MB" "$var_log_journal_floor_mb" "$overflow_mb")"
    # A reused ESP is already excluded from the install budget. Never shrink
    # it or charge it to the Debian layout again on the low-space path.
    if [ "${DUALBOOT_ENABLED:-false}" != true ]; then
      runtime_apply_fill_result DEV_PART_EFI_MB overflow_mb \
        "$(runtime_shrink_partition_to_floor "$DEV_PART_EFI_MB" "$efi_floor_mb" "$overflow_mb")"
      efi_recipe_mb=$DEV_PART_EFI_MB
    fi
    runtime_apply_fill_result DEV_PART_BOOT_MB overflow_mb \
      "$(runtime_shrink_partition_to_floor "$DEV_PART_BOOT_MB" "$boot_floor_mb" "$overflow_mb")"
    runtime_apply_fill_result DEV_PART_ROOT_MB overflow_mb \
      "$(runtime_shrink_partition_to_floor "$DEV_PART_ROOT_MB" "$root_floor_mb" "$overflow_mb")"

    base_total_mb=$((efi_recipe_mb + DEV_PART_BOOT_MB + DEV_PART_ROOT_MB + DEV_PART_HOME_MB + DEV_PART_POOL_MB + DEV_PART_VAR_LIB_SHSIGNED_MB + DEV_PART_VAR_LOG_JOURNAL_MB + DEV_PART_RAW_SWAP_MB + DEV_PART_RAW_ZRAM_MB))
  fi
  if [ "$base_total_mb" -gt "$usable_budget_mb" ]; then
    runtime_fatal "disk budget ${usable_budget_mb} MB is too small for the F2FS minimum layout (${base_total_mb} MB)"
  fi

  elastic_budget_mb=$((usable_budget_mb - base_total_mb))

  if [ "$DEV_PART_HOME_MB" -gt 0 ]; then
    runtime_apply_fill_result DEV_PART_HOME_MB elastic_budget_mb \
      "$(runtime_fill_partition_to_target "$DEV_PART_HOME_MB" "$SIZE_PART_HOME_TARGET_MB" "$elastic_budget_mb")"
  fi
  DEV_PART_ROOT_MB=$((DEV_PART_ROOT_MB + elastic_budget_mb))

  RUNTIME_DISK_TOTAL_MB=$disk_total_mb
  RUNTIME_LAYOUT_SAFETY_MARGIN_MB=$SIZE_LAYOUT_SAFETY_MARGIN_MB
  RUNTIME_PRESERVED_TOTAL_MB=$preserved_total_mb
  RUNTIME_USABLE_BUDGET_MB=$usable_budget_mb
  RUNTIME_BASE_LAYOUT_MB=$base_total_mb
  RUNTIME_INSTALL_RAM_MIB=$ram_total_mib
}

runtime_write_runtime_env() {
  dest=$1
  runtime_ensure_system_identity
  [ -n "${RUNTIME_PARTITION_MODE:-}" ] || runtime_apply_layout_from_cmdline
  runtime_compute_layout_sizing
  runtime_validate_crypto_layout
  runtime_prepare_parent_dir "$dest" 0700
  {
    runtime_write_layout_policy_env
    printf 'SYSTEM_PREFIX=%s\n' "$(runtime_shell_quote "$SYSTEM_PREFIX")"
    printf 'SYSTEM_HOSTNAME=%s\n' "$(runtime_shell_quote "$SYSTEM_HOSTNAME")"
    printf 'SYSTEM_DOMAIN=%s\n' "$(runtime_shell_quote "$SYSTEM_DOMAIN")"
    printf 'DUALBOOT_ENABLED=%s\n' "$(runtime_shell_quote "${DUALBOOT_ENABLED:-false}")"
    printf 'CRYPTO_LUKS2_ROOT=%s\n' "$(runtime_shell_quote "$CRYPTO_LUKS2_ROOT")"
    printf 'CRYPTO_LUKS2_HOME=%s\n' "$(runtime_shell_quote "$CRYPTO_LUKS2_HOME")"
    printf 'ROOT_CRYPT_NAME=%s\n' "$(runtime_shell_quote cryptroot)"
    printf 'HOME_CRYPT_NAME=%s\n' "$(runtime_shell_quote crypthome)"
    printf 'DUALBOOT_EFI_SLOT=%s\n' "$(runtime_shell_quote "${DUALBOOT_EFI_SLOT:-}")"
    printf 'DUALBOOT_DEBIAN_SLOT=%s\n' "$(runtime_shell_quote "${DUALBOOT_DEBIAN_SLOT:-}")"
    printf 'RUNTIME_PRESERVED_SLOTS=%s\n' "$(runtime_shell_quote "${RUNTIME_PRESERVED_SLOTS:-}")"
    printf 'F2FS_LAYOUT_VARIANT=%s\n' "$(runtime_shell_quote "$F2FS_LAYOUT_VARIANT")"
    printf 'F2FS_QEMU_POOL_ENABLED=%s\n' "$(runtime_shell_quote "${F2FS_QEMU_POOL_ENABLED:-false}")"
    printf 'PARTMAN_RECIPE_NAME=%s\n' "$(runtime_shell_quote "$PARTMAN_RECIPE_NAME")"
    printf 'DEV_INSTALL_DISK=%s\n' "$(runtime_shell_quote "$DEV_INSTALL_DISK")"
    printf 'DEV_PART_PREFIX=%s\n' "$(runtime_shell_quote "$DEV_PART_PREFIX")"
    printf 'RUNTIME_EFI_SLOT=%s\n' "$(runtime_shell_quote "$RUNTIME_EFI_SLOT")"
    printf 'RUNTIME_BOOT_SLOT=%s\n' "$(runtime_shell_quote "$RUNTIME_BOOT_SLOT")"
    printf 'RUNTIME_ROOT_SLOT=%s\n' "$(runtime_shell_quote "$RUNTIME_ROOT_SLOT")"
    printf 'RUNTIME_HOME_SLOT=%s\n' "$(runtime_shell_quote "${RUNTIME_HOME_SLOT:-}")"
    printf 'RUNTIME_POOL_SLOT=%s\n' "$(runtime_shell_quote "${RUNTIME_POOL_SLOT:-}")"
    printf 'RUNTIME_VAR_LOG_JOURNAL_SLOT=%s\n' "$(runtime_shell_quote "$RUNTIME_VAR_LOG_JOURNAL_SLOT")"
    printf 'RUNTIME_RAW_SWAP_SLOT=%s\n' "$(runtime_shell_quote "$RUNTIME_RAW_SWAP_SLOT")"
    printf 'RUNTIME_RAW_ZRAM_SLOT=%s\n' "$(runtime_shell_quote "$RUNTIME_RAW_ZRAM_SLOT")"
    printf 'DEV_PART_EFI=%s\n' "$(runtime_shell_quote "$DEV_PART_EFI")"
    printf 'DEV_PART_BOOT=%s\n' "$(runtime_shell_quote "$DEV_PART_BOOT")"
    printf 'DEV_PART_ROOT=%s\n' "$(runtime_shell_quote "$DEV_PART_ROOT")"
    printf 'DEV_PART_HOME=%s\n' "$(runtime_shell_quote "${DEV_PART_HOME:-}")"
    printf 'DEV_PART_POOL=%s\n' "$(runtime_shell_quote "${DEV_PART_POOL:-}")"
    printf 'RUNTIME_VAR_LIB_SHSIGNED_SLOT=%s\n' "$(runtime_shell_quote "${RUNTIME_VAR_LIB_SHSIGNED_SLOT:-}")"
    printf 'DEV_PART_VAR_LIB_SHSIGNED=%s\n' "$(runtime_shell_quote "${DEV_PART_VAR_LIB_SHSIGNED:-}")"
    printf 'DEV_PART_VAR_LOG_JOURNAL=%s\n' "$(runtime_shell_quote "$DEV_PART_VAR_LOG_JOURNAL")"
    printf 'DEV_PART_RAW_SWAP=%s\n' "$(runtime_shell_quote "$DEV_PART_RAW_SWAP")"
    printf 'DEV_PART_RAW_ZRAM=%s\n' "$(runtime_shell_quote "$DEV_PART_RAW_ZRAM")"
    printf 'DEV_PART_EFI_MB=%s\n' "$(runtime_shell_quote "$DEV_PART_EFI_MB")"
    printf 'DEV_PART_BOOT_MB=%s\n' "$(runtime_shell_quote "$DEV_PART_BOOT_MB")"
    printf 'DEV_PART_ROOT_MB=%s\n' "$(runtime_shell_quote "$DEV_PART_ROOT_MB")"
    printf 'DEV_PART_HOME_MB=%s\n' "$(runtime_shell_quote "$DEV_PART_HOME_MB")"
    printf 'DEV_PART_POOL_MB=%s\n' "$(runtime_shell_quote "$DEV_PART_POOL_MB")"
    printf 'DEV_PART_VAR_LIB_SHSIGNED_MB=%s\n' "$(runtime_shell_quote "$DEV_PART_VAR_LIB_SHSIGNED_MB")"
    printf 'DEV_PART_VAR_LOG_JOURNAL_MB=%s\n' "$(runtime_shell_quote "$DEV_PART_VAR_LOG_JOURNAL_MB")"
    printf 'DEV_PART_RAW_SWAP_MB=%s\n' "$(runtime_shell_quote "$DEV_PART_RAW_SWAP_MB")"
    printf 'DEV_PART_RAW_ZRAM_MB=%s\n' "$(runtime_shell_quote "$DEV_PART_RAW_ZRAM_MB")"
    printf 'SWAP_SIZE_MIB=%s\n' "$(runtime_shell_quote "$SWAP_SIZE_MIB")"
    printf 'RUNTIME_DISK_TOTAL_MB=%s\n' "$(runtime_shell_quote "$RUNTIME_DISK_TOTAL_MB")"
    printf 'RUNTIME_LAYOUT_SAFETY_MARGIN_MB=%s\n' "$(runtime_shell_quote "$RUNTIME_LAYOUT_SAFETY_MARGIN_MB")"
    printf 'RUNTIME_PRESERVED_TOTAL_MB=%s\n' "$(runtime_shell_quote "${RUNTIME_PRESERVED_TOTAL_MB:-0}")"
    printf 'RUNTIME_USABLE_BUDGET_MB=%s\n' "$(runtime_shell_quote "$RUNTIME_USABLE_BUDGET_MB")"
    printf 'RUNTIME_BASE_LAYOUT_MB=%s\n' "$(runtime_shell_quote "$RUNTIME_BASE_LAYOUT_MB")"
    printf 'RUNTIME_INSTALL_RAM_MIB=%s\n' "$(runtime_shell_quote "$RUNTIME_INSTALL_RAM_MIB")"
    printf 'RUNTIME_DEBIAN_START_SLOT=%s\n' "$(runtime_shell_quote "$RUNTIME_DEBIAN_START_SLOT")"
    printf 'ZRAM_BACKING_RAW_DEVICE=%s\n' "$(runtime_shell_quote "$ZRAM_BACKING_RAW_DEVICE")"
    printf 'ZRAM_BACKING_MAPPER_NAME=%s\n' "$(runtime_shell_quote "$ZRAM_BACKING_MAPPER_NAME")"
    printf 'ZRAM_BACKING_DEVICE=%s\n' "$(runtime_shell_quote "$ZRAM_BACKING_DEVICE")"
    printf 'SWAP_FALLBACK_RAW_DEVICE=%s\n' "$(runtime_shell_quote "$SWAP_FALLBACK_RAW_DEVICE")"
    printf 'SWAP_FALLBACK_MAPPER_NAME=%s\n' "$(runtime_shell_quote "$SWAP_FALLBACK_MAPPER_NAME")"
    printf 'SWAP_FALLBACK_MAPPER=%s\n' "$(runtime_shell_quote "$SWAP_FALLBACK_MAPPER")"
    if [ "$DUALBOOT_ENABLED" = true ]; then
      printf 'RUNTIME_PARTITION_%s_SIZE_MB=%s\n' "$RUNTIME_EFI_SLOT" "$(runtime_shell_quote "$DEV_PART_EFI_MB")"
    fi
  } >"$dest"
  chmod 0600 "$dest"
}

runtime_emit_debian_partition_recipe() {
  # The fourth recipe field is a libparted partition-creation token; Debian's
  # partman-auto accepts ext4 there and does not accept f2fs. It does not run
  # mkfs.ext4. filesystem{ f2fs } sets acting_filesystem for the F2FS backend,
  # which runs mkfs.f2fs for root/home; the finish hook verifies that signature.
  runtime_render_recipe f2fs-01.recipe.tmpl \
    DEV_PART_BOOT_MB "${DEV_PART_BOOT_MB}"
  if runtime_root_crypto_enabled; then
    runtime_render_recipe f2fs-02.recipe.tmpl \
      ROOT_PRIORITY "$((DEV_PART_ROOT_MB + 1))" \
      ROOT_MAX_MB "$(runtime_partman_root_max_mb)" \
      DEV_PART_ROOT_MB "${DEV_PART_ROOT_MB}"
  else
    runtime_render_recipe f2fs-03.recipe.tmpl \
      ROOT_PRIORITY "$((DEV_PART_ROOT_MB + 1))" \
      ROOT_MAX_MB "$(runtime_partman_root_max_mb)" \
      DEV_PART_ROOT_MB "${DEV_PART_ROOT_MB}"
  fi
  if [ "$DEV_PART_HOME_MB" -gt 0 ]; then
    if runtime_home_crypto_enabled; then
      runtime_render_recipe f2fs-04.recipe.tmpl \
        DEV_PART_HOME_MB "${DEV_PART_HOME_MB}"
    else
      runtime_render_recipe f2fs-05.recipe.tmpl \
        DEV_PART_HOME_MB "${DEV_PART_HOME_MB}"
    fi
  fi
  if [ "$DEV_PART_POOL_MB" -gt 0 ]; then
    runtime_render_recipe f2fs-06.recipe.tmpl \
      DEV_PART_POOL_MB "${DEV_PART_POOL_MB}"
  fi
  if [ "$DEV_PART_VAR_LIB_SHSIGNED_MB" -gt 0 ]; then
    runtime_render_recipe f2fs-07.recipe.tmpl \
      DEV_PART_VAR_LIB_SHSIGNED_MB "${DEV_PART_VAR_LIB_SHSIGNED_MB}"
  fi
  runtime_render_recipe f2fs-08.recipe.tmpl \
    DEV_PART_VAR_LOG_JOURNAL_MB "${DEV_PART_VAR_LOG_JOURNAL_MB}" \
    DEV_PART_RAW_SWAP_MB "${DEV_PART_RAW_SWAP_MB}" \
    DEV_PART_RAW_ZRAM_MB "${DEV_PART_RAW_ZRAM_MB}"
}

runtime_emit_default_recipe() {
  runtime_render_recipe f2fs-09.recipe.tmpl \
    PARTMAN_RECIPE_NAME "${PARTMAN_RECIPE_NAME}" \
    DEV_PART_EFI_MB "${DEV_PART_EFI_MB}"
  runtime_emit_debian_partition_recipe
}

runtime_emit_dualboot_recipe() {
  runtime_render_recipe f2fs-10.recipe.tmpl \
    PARTMAN_RECIPE_NAME "${PARTMAN_RECIPE_NAME}"
  runtime_emit_debian_partition_recipe
}

runtime_write_expert_recipe() {
  runtime_prepare_recipe_templates
  dest=$1
  [ -n "${RUNTIME_PARTITION_MODE:-}" ] || runtime_apply_layout_from_cmdline
  runtime_compute_layout_sizing
  runtime_prepare_parent_dir "$dest" 0700
  if [ "${DUALBOOT_ENABLED:-false}" = "true" ]; then
    runtime_emit_dualboot_recipe >"$dest"
  else
    runtime_emit_default_recipe >"$dest"
  fi
  chmod 0600 "$dest"
}

runtime_write_partman_fragment() {
  dest=$1
  recipe_file=$2
  runtime_prepare_parent_dir "$dest" 0700
  {
    printf 'd-i partman/default_filesystem string ext4\n'
    printf 'd-i partman/default_filesystem seen true\n'
    printf 'd-i partman-efi/confirm boolean true\n'
    printf 'd-i partman-efi/confirm seen true\n'
    runtime_emit_partman_driver_answers
    printf 'd-i partman-auto/choose_recipe select %s\n' "$PARTMAN_RECIPE_NAME"
    printf 'd-i partman-auto/choose_recipe seen true\n'
    printf 'd-i partman-auto/expert_recipe_file string %s\n' "$recipe_file"
    printf 'd-i partman-auto/expert_recipe_file seen true\n'
    printf 'd-i partman/choose_partition select finish\n'
    printf 'd-i partman/choose_partition seen true\n'
    printf 'd-i partman/confirm boolean true\n'
    printf 'd-i partman/confirm seen true\n'
    printf 'd-i partman/confirm_nochanges boolean true\n'
    printf 'd-i partman/confirm_nochanges seen true\n'
    printf 'd-i partman/confirm_nooverwrite boolean true\n'
    printf 'd-i partman/confirm_nooverwrite seen true\n'
    printf 'd-i partman-auto/confirm boolean true\n'
    printf 'd-i partman-auto/confirm seen true\n'
  } >"$dest"
  chmod 0644 "$dest"
}

runtime_write_identity_answers() {
  dest=$1
  runtime_ensure_system_identity
  runtime_prepare_parent_dir "$dest" 0700
  {
    printf 'd-i netcfg/get_hostname string %s\n' "$SYSTEM_HOSTNAME"
    printf 'd-i netcfg/get_hostname seen true\n'
    printf 'd-i netcfg/get_domain string %s\n' "$SYSTEM_DOMAIN"
    printf 'd-i netcfg/get_domain seen true\n'
    printf 'd-i netcfg/hostname string %s\n' "$SYSTEM_HOSTNAME"
    printf 'd-i netcfg/hostname seen true\n'
  } >"$dest"
  chmod 0600 "$dest"
}
