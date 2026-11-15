#!/bin/sh
# Shared installer-only partition policy. Linux sysfs and GNU parted are the
# immutable kernel/package interfaces used here; no target paths are inferred.

runtime_validate_partman_policy() {
  for layout_bool in "${PARTMAN_CEILING_ENABLE:-}" "${PARTMAN_REUSE_ENABLE:-}"; do
    case "$layout_bool" in true|false) ;; *) runtime_fatal 'partition policy requires explicit booleans' ;; esac
  done
  runtime_require_positive_integer PARTMAN_CEILING_MB "${PARTMAN_CEILING_MB:-}"
  runtime_require_positive_integer PARTMAN_REUSE_START "${PARTMAN_REUSE_START:-}"
  case "$PARTMAN_CEILING_MB:$PARTMAN_REUSE_START" in
    0*|*:0*) runtime_fatal 'partition policy cannot contain leading zeroes' ;;
  esac
  [ "$PARTMAN_CEILING_MB" -le 2147483647 ] && [ "$PARTMAN_REUSE_START" -le 128 ] ||
    runtime_fatal 'partition policy exceeds the supported GPT/MB limits'
}

runtime_partman_fixed_layout_required() {
  case "${RUNTIME_PARTITION_MODE:-fresh}" in
    append|reuse) return 0 ;;
    fresh) [ "${PARTMAN_CEILING_ENABLE:-false}" = true ] ;;
    *) runtime_fatal 'invalid partition mode for partman driver selection'; return 1 ;;
  esac
}

runtime_partman_root_max_mb() {
  if runtime_partman_fixed_layout_required; then
    printf '%s\n' "$DEV_PART_ROOT_MB"
  else
    # Restore partman-auto's established root-growth policy for ordinary
    # fresh installs; only bounded/preserved layouts require an exact maximum.
    printf '%s\n' 1000000000
  fi
}

runtime_emit_partman_driver_answers() {
  if runtime_partman_fixed_layout_required || runtime_any_crypto_enabled; then
    # Native disk/method answers take precedence over the menu in partman-auto.
    # Clear inherited answers so preserved layouts cannot enter whole-disk mode.
    printf 'd-i partman-auto/disk string\n'
    printf 'd-i partman-auto/disk seen true\n'
    printf 'd-i partman-auto/method string\n'
    printf 'd-i partman-auto/method seen true\n'
    printf 'd-i partman-auto/init_automatically_partition select installer_target_free\n'
    printf 'd-i partman-auto/init_automatically_partition seen true\n'
    printf 'd-i partman-basicmethods/method_only boolean false\n'
    printf 'd-i partman-basicmethods/method_only seen true\n'
  else
    printf 'd-i partman-auto/disk string %s\n' "$DEV_INSTALL_DISK"
    printf 'd-i partman-auto/disk seen true\n'
    printf 'd-i partman-auto/method string regular\n'
    printf 'd-i partman-auto/method seen true\n'
    printf 'd-i partman-partitioning/choose_label select gpt\n'
    printf 'd-i partman-partitioning/choose_label seen true\n'
    printf 'd-i partman-partitioning/default_label string gpt\n'
    printf 'd-i partman-partitioning/default_label seen true\n'
    printf 'd-i partman-partitioning/confirm_new_label boolean true\n'
    printf 'd-i partman-partitioning/confirm_new_label seen true\n'
    printf 'd-i partman-partitioning/confirm_write_new_label boolean true\n'
    printf 'd-i partman-partitioning/confirm_write_new_label seen true\n'
    printf 'd-i partman/confirm_write_new_label boolean true\n'
    printf 'd-i partman/confirm_write_new_label seen true\n'
  fi
}

runtime_partition_inventory() (
  set -eu
  # Do not include filesystem/partition names: they are untrusted display data.
  # Bound the package output before parsing and require exact decimal bytes.
  inventory_raw=$(parted -sm "$DEV_INSTALL_DISK" unit B print) || exit 1
  [ "${#inventory_raw}" -le 65536 ] || exit 1
  printf '%s\n' "$inventory_raw" | LC_ALL=C awk -F : '
    NR==1 {if($0!="BYT;") exit 1; next}
    NR==2 {if($6!="gpt") exit 1; next}
    /^[0-9]+:/ {
      if(++count>128 || $1<1 || $1>128 || seen[$1]++ ||
         $2!~/^[0-9]+B$/ || $3!~/^[0-9]+B$/ || $4!~/^[0-9]+B$/) exit 1
      sub(/B$/, "", $2); sub(/B$/, "", $3); sub(/B$/, "", $4)
      start=$2+0; end=$3+0; bytes=$4+0
      if(start<1048576 || end<start || bytes!=end-start+1 || end>2147483647000000) exit 1
      for(i=1;i<count;i++) if(!(end<starts[i] || start>ends[i])) exit 1
      starts[count]=start; ends[count]=end
      printf "%d|%.0f|%.0f|%.0f\n", $1,start,end,bytes
    }
    END {if(NR<2) exit 1}
  '
)

runtime_partition_identity_hash() {
  # sfdisk's GPT dump includes disk/partition UUIDs and types as well as
  # extents. Hash raw bounded bytes; never evaluate names or display them.
  layout_dump=$(sfdisk --dump "$DEV_INSTALL_DISK") || return 1
  [ "${#layout_dump}" -le 65536 ] || return 1
  printf '%s\n' "$layout_dump" | source_hash
}

runtime_inventory_value() {
  printf '%s\n' "${RUNTIME_PARTITION_INVENTORY:-}" |
    awk -F '|' -v slot="$1" -v column="$2" '$1==slot {print $column; found=1} END {if(!found) exit 1}'
}

runtime_prepare_layout_policy() {
  runtime_validate_partman_policy
  if [ -n "${INSTALLER_PROFILE_PARTMAN_REUSE_ENABLE:-}" ]; then
    [ "$PARTMAN_REUSE_ENABLE" = "$INSTALLER_PROFILE_PARTMAN_REUSE_ENABLE" ] &&
      [ "$PARTMAN_REUSE_START" = "$INSTALLER_PROFILE_PARTMAN_REUSE_START" ] &&
      [ "$PARTMAN_CEILING_ENABLE" = "$INSTALLER_PROFILE_PARTMAN_CEILING_ENABLE" ] &&
      [ "$PARTMAN_CEILING_MB" = "$INSTALLER_PROFILE_PARTMAN_CEILING_MB" ] ||
      runtime_fatal 'partition policy differs from the frozen installation context'
  fi
  RUNTIME_PARTITION_MODE=fresh
  MULTIBOOT_ENABLED=false
  if runtime_dualboot_class_selected; then MULTIBOOT_ENABLED=true; fi
  if [ "$PARTMAN_REUSE_ENABLE" = true ]; then
    RUNTIME_PARTITION_MODE=reuse
  elif runtime_dualboot_class_selected; then
    RUNTIME_PARTITION_MODE=append
  fi
  RUNTIME_PARTITION_INVENTORY=
  RUNTIME_EXISTING_END_MB=0
  RUNTIME_EXISTING_END_BYTES=0
  RUNTIME_DETECTED_EFI_SLOT=
  RUNTIME_LAYOUT_CEILING_BYTES=$(( $(runtime_install_disk_size_mb) * 1000000 ))
  if [ "$RUNTIME_PARTITION_MODE" != reuse ] && [ "$PARTMAN_CEILING_ENABLE" = true ] &&
     [ "$((PARTMAN_CEILING_MB * 1000000))" -lt "$RUNTIME_LAYOUT_CEILING_BYTES" ]; then
    RUNTIME_LAYOUT_CEILING_BYTES=$((PARTMAN_CEILING_MB * 1000000))
  fi
  if [ "$RUNTIME_PARTITION_MODE" != fresh ]; then
    RUNTIME_PARTITION_INVENTORY=$(runtime_partition_inventory) || runtime_fatal 'cannot read a complete GPT inventory for preservation'
    [ -n "$RUNTIME_PARTITION_INVENTORY" ] || runtime_fatal 'preservation requires an existing GPT layout and EFI partition'
    RUNTIME_EXISTING_END_MB=$(printf '%s\n' "$RUNTIME_PARTITION_INVENTORY" |
      awk -F '|' '$3>last {last=$3} END {printf "%.0f\n", int((last+1000000)/1000000)}')
    RUNTIME_EXISTING_END_BYTES=$(printf '%s\n' "$RUNTIME_PARTITION_INVENTORY" |
      awk -F '|' '$3>last {last=$3} END {printf "%.0f\n", last+1}')
    layout_efi_start=
    while IFS='|' read -r layout_slot layout_start layout_end layout_bytes; do
      layout_device=$(runtime_partition_path "$layout_slot")
      layout_type=$(runtime_probe_gpt_part_type "$layout_device") || runtime_fatal 'cannot establish a preserved partition type'
      if runtime_gpt_part_type_is_esp "$layout_type"; then
        case "$(runtime_probe_filesystem_type "$layout_device")" in
          vfat|fat|fat12|fat16|fat32) ;;
          *) runtime_fatal 'an existing ESP does not contain a supported FAT filesystem' ;;
        esac
        if [ -z "$layout_efi_start" ] || [ "$layout_start" -lt "$layout_efi_start" ]; then
          RUNTIME_DETECTED_EFI_SLOT=$layout_slot
          layout_efi_start=$layout_start
        fi
      fi
    done <<EOF
$RUNTIME_PARTITION_INVENTORY
EOF
    [ -n "$RUNTIME_DETECTED_EFI_SLOT" ] || runtime_fatal 'no existing GPT EFI System Partition was found'
  fi
  RUNTIME_PARTITION_INVENTORY_HASH=$(printf '%s\n' "$RUNTIME_PARTITION_INVENTORY" | source_hash)
  RUNTIME_PARTITION_INVENTORY_HASH=${RUNTIME_PARTITION_INVENTORY_HASH%% *}
  RUNTIME_PARTITION_IDENTITY_HASH=
  if [ "$RUNTIME_PARTITION_MODE" != fresh ]; then
    RUNTIME_PARTITION_IDENTITY_HASH=$(runtime_partition_identity_hash) || runtime_fatal 'cannot bind preserved GPT identities'
    RUNTIME_PARTITION_IDENTITY_HASH=${RUNTIME_PARTITION_IDENTITY_HASH%% *}
  fi
}

runtime_policy_slot() {
  # GPT allocates the lowest unused number, including holes. Simulate it from
  # the complete inventory, while physical placement always uses the tail.
  if [ "$RUNTIME_PARTITION_MODE" = reuse ]; then
    printf '%s\n' "$((PARTMAN_REUSE_START + $1))"
  else
    printf '%s\n' "$RUNTIME_PARTITION_INVENTORY" | awk -F '|' -v offset="$1" '
      NF==4 {used[$1]=1}
      END {for(n=1;n<=128;n++) if(!(n in used)) {if(offset--==0) {print n; exit}}; exit 1}'
  fi
}

runtime_policy_disk_budget_mb() {
  printf '%s\n' "$((RUNTIME_LAYOUT_CEILING_BYTES / 1000000))"
}

runtime_layout_roles() {
  # The role order is also the authenticated expert-recipe order.
  printf '%s\n' BOOT ROOT
  [ -z "${RUNTIME_HOME_SLOT:-}" ] || printf '%s\n' HOME
  if [ "${INSTALLER_HOST_FAMILY:-${HOOK_FAMILY:-}}" != f2fs ]; then
    printf '%s\n' OPT DATA POOL VAR_TMP VAR_LIB_SHSIGNED
  else
    [ -z "${RUNTIME_POOL_SLOT:-}" ] || printf '%s\n' POOL
    [ -z "${RUNTIME_VAR_LIB_SHSIGNED_SLOT:-}" ] || printf '%s\n' VAR_LIB_SHSIGNED
  fi
  printf '%s\n' VAR_LOG_JOURNAL RAW_SWAP RAW_ZRAM
}

runtime_role_device() {
  case "$1" in
    EFI) printf '%s\n' "$DEV_PART_EFI" ;;
    BOOT) printf '%s\n' "$DEV_PART_BOOT" ;;
    ROOT) printf '%s\n' "$DEV_PART_ROOT" ;;
    HOME) printf '%s\n' "$DEV_PART_HOME" ;;
    OPT) printf '%s\n' "$DEV_PART_OPT" ;;
    DATA) printf '%s\n' "$DEV_PART_DATA" ;;
    POOL) printf '%s\n' "$DEV_PART_POOL" ;;
    VAR_TMP) printf '%s\n' "$DEV_PART_VAR_TMP" ;;
    VAR_LIB_SHSIGNED) printf '%s\n' "$DEV_PART_VAR_LIB_SHSIGNED" ;;
    VAR_LOG_JOURNAL) printf '%s\n' "$DEV_PART_VAR_LOG_JOURNAL" ;;
    RAW_SWAP) printf '%s\n' "$DEV_PART_RAW_SWAP" ;;
    RAW_ZRAM) printf '%s\n' "$DEV_PART_RAW_ZRAM" ;;
    *) return 1 ;;
  esac
}

runtime_apply_reuse_sizing() {
  reuse_total=0
  for reuse_role in EFI $(runtime_layout_roles); do
    reuse_device=$(runtime_role_device "$reuse_role") || return 1
    reuse_slot=$(runtime_partition_slot_from_path "$reuse_role" "$reuse_device") || return 1
    [ "$reuse_slot" -le 128 ] || runtime_fatal 'reuse range exceeds the GPT partition limit'
    if [ "$reuse_role" != EFI ] && [ "$reuse_slot" = "$RUNTIME_EFI_SLOT" ]; then
      runtime_fatal 'reuse range overlaps the preserved EFI partition'
    fi
    reuse_bytes=$(runtime_inventory_value "$reuse_slot" 4) || runtime_fatal "missing existing reuse partition: $reuse_device"
    if [ "$reuse_role" != EFI ]; then
      reuse_type=$(runtime_probe_gpt_part_type "$reuse_device") || runtime_fatal 'cannot verify a reuse partition type'
      if runtime_gpt_part_type_is_esp "$reuse_type"; then
        runtime_fatal 'reuse range includes an EFI System Partition'
      fi
    fi
    reuse_mb=$((reuse_bytes / 1000000))
    [ "$reuse_mb" -gt 0 ] || runtime_fatal 'reuse partition is smaller than one MB'
    # Exact geometry remains in parted_server. MB values only size metadata
    # and the recipe, which is never expanded/resized in reuse mode.
    case "$reuse_role" in
      EFI) DEV_PART_EFI_MB=$reuse_mb ;;
      BOOT) DEV_PART_BOOT_MB=$reuse_mb ;;
      ROOT) DEV_PART_ROOT_MB=$reuse_mb ;;
      HOME) DEV_PART_HOME_MB=$reuse_mb ;;
      OPT) DEV_PART_OPT_MB=$reuse_mb ;;
      DATA) DEV_PART_DATA_MB=$reuse_mb ;;
      POOL) DEV_PART_POOL_MB=$reuse_mb ;;
      VAR_TMP) DEV_PART_VAR_TMP_MB=$reuse_mb ;;
      VAR_LIB_SHSIGNED) DEV_PART_VAR_LIB_SHSIGNED_MB=$reuse_mb ;;
      VAR_LOG_JOURNAL) DEV_PART_VAR_LOG_JOURNAL_MB=$reuse_mb ;;
      RAW_SWAP) DEV_PART_RAW_SWAP_MB=$reuse_mb ;;
      RAW_ZRAM) DEV_PART_RAW_ZRAM_MB=$reuse_mb ;;
    esac
    [ "$reuse_role" = EFI ] || reuse_total=$((reuse_total + reuse_mb))
  done
  SWAP_SIZE_MIB=$((DEV_PART_RAW_SWAP_MB * 1000000 / 1048576))
  RUNTIME_DISK_TOTAL_MB=$(runtime_install_disk_size_mb)
  RUNTIME_LAYOUT_SAFETY_MARGIN_MB=0
  RUNTIME_PRESERVED_TOTAL_MB=$((RUNTIME_DISK_TOTAL_MB - reuse_total))
  RUNTIME_USABLE_BUDGET_MB=$reuse_total
  RUNTIME_BASE_LAYOUT_MB=$reuse_total
  RUNTIME_INSTALL_RAM_MIB=$(runtime_total_ram_mib)
}

runtime_write_layout_policy_env() {
  printf 'MULTIBOOT_ENABLED=%s\n' "$(runtime_shell_quote "$MULTIBOOT_ENABLED")"
  printf 'RUNTIME_PARTITION_MODE=%s\n' "$(runtime_shell_quote "$RUNTIME_PARTITION_MODE")"
  printf 'RUNTIME_LAYOUT_CEILING_BYTES=%s\n' "$(runtime_shell_quote "$RUNTIME_LAYOUT_CEILING_BYTES")"
  printf 'RUNTIME_EXISTING_END_MB=%s\n' "$(runtime_shell_quote "$RUNTIME_EXISTING_END_MB")"
  printf 'RUNTIME_EXISTING_END_BYTES=%s\n' "$(runtime_shell_quote "$RUNTIME_EXISTING_END_BYTES")"
  printf 'RUNTIME_PARTITION_INVENTORY_HASH=%s\n' "$(runtime_shell_quote "$RUNTIME_PARTITION_INVENTORY_HASH")"
  printf 'RUNTIME_PARTITION_IDENTITY_HASH=%s\n' "$(runtime_shell_quote "$RUNTIME_PARTITION_IDENTITY_HASH")"
}
