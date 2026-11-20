#!/bin/sh
# Shared frozen-layout identity and recipe-size validation; definitions only.

raw_partition_partuuid() {
  raw_device=$1

  case "$raw_device" in
    ${DIR_DEV}/*) ;;
    *) installer_fatal "raw partition device must be an absolute ${DIR_DEV} path: ${raw_device:-unset}" ;;
  esac
  command -v blkid >${DIR_DEV}/null 2>&1 ||
    installer_fatal "blkid is required to determine the stable raw partition path"
  raw_partuuid=$(blkid -s PARTUUID -o value "$raw_device" 2>${DIR_DEV}/null) || {
    installer_fatal "unable to read PARTUUID for raw partition ${raw_device}"
    return 1
  }
  case "$raw_partuuid" in
    ''|*[!A-Fa-f0-9-]*)
      installer_fatal "unable to determine a valid PARTUUID for raw partition ${raw_device}"
      ;;
  esac
  printf '%s\n' "$raw_partuuid"
}

stable_raw_partition_path() {
  raw_partuuid=$(raw_partition_partuuid "$1") || return 1
  stable_path="${DIR_DEV}/disk/by-partuuid/${raw_partuuid}"
  [ -b "$stable_path" ] || installer_fatal 'stable raw partition identity is missing'
  raw_real=$(readlink -f "$1") || installer_fatal 'cannot resolve raw partition'
  stable_real=$(readlink -f "$stable_path") || installer_fatal 'cannot resolve PARTUUID identity'
  [ "$raw_real" = "$stable_real" ] || installer_fatal 'PARTUUID identifies a different device'
  printf '%s\n' "$stable_path"
}

raw_storage_partition_alignment_tolerance_bytes() {
  # The fixed handler creates every partition with position=beginning; reuse
  # preserves exact extents. No final partition absorbs the free-space tail.
  case "${RUNTIME_PARTITION_MODE:-}" in
    append|reuse) printf '%s\n' 2097152; return 0 ;;
    fresh)
      if [ "${PARTMAN_CEILING_ENABLE:-false}" = true ]; then
        printf '%s\n' 2097152
        return 0
      fi
      ;;
  esac
  # Fixed-size partitions can lose at most their two aligned boundaries.
  # partman-auto creates its final partition with position=full: it gets the
  # remaining extent, including rounding accumulated by the preceding recipe.
  # Only that verified tail gets a per-partition budget, never a disk percentage.
  if [ -z "${1:-}" ] || [ "${1:-}" != "${DEV_PART_RAW_ZRAM:-}" ]; then
    printf '%s\n' 2097152
    return 0
  fi
  for ratb_slot in "${RUNTIME_DEBIAN_START_SLOT:-}" "${RUNTIME_DEBIAN_END_SLOT:-}" "${RUNTIME_RAW_ZRAM_SLOT:-}"; do
    case "$ratb_slot" in ''|*[!0-9]*|0*) return 1 ;; esac
    [ "${#ratb_slot}" -le 3 ] && [ "$ratb_slot" -le 128 ] || return 1
  done
  [ "$RUNTIME_DEBIAN_END_SLOT" = "$RUNTIME_RAW_ZRAM_SLOT" ] || return 1
  [ "$RUNTIME_DEBIAN_START_SLOT" -le "$RUNTIME_DEBIAN_END_SLOT" ] || return 1
  ratb_count=$((RUNTIME_DEBIAN_END_SLOT - RUNTIME_DEBIAN_START_SLOT + 1))
  case "${DUALBOOT_ENABLED:-}" in
    false) ratb_count=$((ratb_count + 1)) ;; # newly created ESP
    true) ;; # reused ESP and preserved slots do not accumulate new rounding
    *) return 1 ;;
  esac
  [ "$ratb_count" -le 32 ] || return 1
  # One MiB per newly created partition plus two boundary/decimal-rounding MiB.
  # This is bounded to 34 MiB even for the largest supported recipe, and is
  # independent of disk capacity. Actual mapper capacity still limits zram.
  printf '%s\n' "$(((ratb_count + 2) * 1048576))"
}

raw_storage_partition_size_is_acceptable() {
  sfps_configured_size_mb=$1
  sfps_actual_size_bytes=$2
  sfps_alignment_tolerance_bytes=$(raw_storage_partition_alignment_tolerance_bytes "${3:-}") || return 1

  case "$sfps_configured_size_mb" in
    ''|*[!0-9]*|0*) return 1 ;;
  esac
  case "$sfps_actual_size_bytes" in
    ''|*[!0-9]*) return 1 ;;
  esac

  [ "$sfps_configured_size_mb" -le 2147483647 ] || return 1
  [ "${#sfps_actual_size_bytes}" -le 18 ] || return 1
  sfps_expected_size_bytes=$((sfps_configured_size_mb * 1000000))
  # Reject both undersized and oversized devices beyond the bounded recipe
  # alignment budget; the tail must not silently consume arbitrary free space.
  [ "$sfps_actual_size_bytes" -le "$((sfps_expected_size_bytes + sfps_alignment_tolerance_bytes))" ] || return 1

  sfps_shortfall_bytes=$((sfps_expected_size_bytes - sfps_actual_size_bytes))
  [ "$sfps_shortfall_bytes" -le "$sfps_alignment_tolerance_bytes" ]
}

validate_raw_storage_partition() {
  raw_device=$1
  configured_size_mb=$2

  case "$raw_device" in
    ${DIR_DEV}/*) ;;
    *) installer_fatal "raw storage device must be an absolute ${DIR_DEV} path: ${raw_device:-unset}" ;;
  esac
  case "$configured_size_mb" in
    ''|*[!0-9]*|0*) installer_fatal "configured raw storage size must be a canonical positive MB integer: ${configured_size_mb:-unset}" ;;
  esac
  [ "$configured_size_mb" -le 2147483647 ] || installer_fatal "raw storage size is too large"
  [ -b "$raw_device" ] || installer_fatal "raw storage partition was not created: ${raw_device}"
  command -v blockdev >${DIR_DEV}/null 2>&1 || installer_fatal "blockdev is required to verify raw storage partition size"
  actual_size_bytes=$(blockdev --getsize64 "$raw_device" 2>${DIR_DEV}/null) ||
    installer_fatal "unable to read raw storage partition size: ${raw_device}"
  case "$actual_size_bytes" in
    ''|*[!0-9]*) installer_fatal "invalid raw storage partition size for ${raw_device}: ${actual_size_bytes:-unset}" ;;
  esac
  [ "${#actual_size_bytes}" -le 18 ] || installer_fatal "raw storage byte count is too large"
  alignment_tolerance_bytes=$(raw_storage_partition_alignment_tolerance_bytes "$raw_device") ||
    installer_fatal "invalid runtime partition context for raw storage alignment: ${raw_device}"
  expected_size_bytes=$((configured_size_mb * 1000000))
  actual_size_mb=$((actual_size_bytes / 1000000))
  if ! raw_storage_partition_size_is_acceptable "$configured_size_mb" "$actual_size_bytes" "$raw_device"; then
    installer_fatal "raw storage partition ${raw_device} is ${actual_size_mb} MB (${actual_size_bytes} bytes), expected ${configured_size_mb} MB (${expected_size_bytes} bytes) within the ${alignment_tolerance_bytes}-byte partman alignment tolerance"
  fi
  if [ "$actual_size_bytes" -lt "$expected_size_bytes" ]; then
    shortfall_bytes=$((expected_size_bytes - actual_size_bytes))
    installer_warn "raw storage partition ${raw_device} is ${shortfall_bytes} bytes below the nominal recipe size; accepting within the ${alignment_tolerance_bytes}-byte partman alignment tolerance"
  fi
}
