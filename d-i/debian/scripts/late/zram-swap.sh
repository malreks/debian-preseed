#!/bin/sh
# Shared late_command zram, swap, and storage-unit helpers. This file is sourced, not executed.

fstab_entry() {
  printf '%-28s %-36s %-8s %-72s %s %s\n' "$1" "$2" "$3" "$4" "$5" "$6"
}

installer_mapper_for_raw_device() {
  raw_device=$1
  raw_real=$(readlink -f "$raw_device" 2>__INSTALLER_PATH_DIR_DEV__/null || true)
  [ -n "$raw_real" ] || installer_fatal "unable to resolve encrypted raw device ${raw_device}"

  mapper_path=
  for dm_sysfs in __INSTALLER_PATH_DIR_SYS__/class/block/dm-*; do
    [ -d "$dm_sysfs" ] || continue
    [ -r "$dm_sysfs/dm/name" ] || continue
    for slave_sysfs in "$dm_sysfs"/slaves/*; do
      [ -e "$slave_sysfs" ] || continue
      slave_name=${slave_sysfs##*/}
      slave_real=$(readlink -f "__INSTALLER_PATH_DIR_DEV__/${slave_name}" 2>__INSTALLER_PATH_DIR_DEV__/null || true)
      [ "$slave_real" = "$raw_real" ] || continue
      dm_name=$(cat "$dm_sysfs/dm/name" 2>__INSTALLER_PATH_DIR_DEV__/null || true)
      [ -n "$dm_name" ] || continue
      candidate="__INSTALLER_PATH_DIR_DEV__/mapper/${dm_name}"
      [ -b "$candidate" ] || continue
      if [ -n "$mapper_path" ] && [ "$mapper_path" != "$candidate" ]; then
        installer_fatal "multiple active dm-crypt mappings reference ${raw_device}"
      fi
      mapper_path=$candidate
    done
  done

  [ -n "$mapper_path" ] || installer_fatal "unable to locate active dm-crypt mapping for ${raw_device}"
  printf '%s\n' "$mapper_path"
}

installer_filesystem_device() {
  requested_device=$1
  case "${CRYPTO_LUKS2_ROOT:-false}:${CRYPTO_LUKS2_HOME:-false}:${requested_device}" in
    true:*:"${DEV_PART_ROOT:-}"|*:true:"${DEV_PART_HOME:-}")
      installer_mapper_for_raw_device "$requested_device"
      ;;
    *)
      printf '%s\n' "$requested_device"
      ;;
  esac
}

device_source() {
  dev=$1
  if [ "$dev" = "tmpfs" ]; then
    printf 'tmpfs\n'
    return 0
  fi
  dev=$(installer_filesystem_device "$dev")
  if command -v blkid >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
    uuid=$(blkid -s UUID -o value "$dev" 2>__INSTALLER_PATH_DIR_DEV__/null || true)
    if [ -n "$uuid" ]; then
      printf 'UUID=%s\n' "$uuid"
      return 0
    fi
  fi
  printf '%s\n' "$dev"
}

# Raw partition identity/size helpers are shared through common/lib.sh.

swap_fallback_placeholder_map() {
  write_shell_config_var SWAP_FALLBACK_RAW_PARTUUID "${SWAP_FALLBACK_RAW_PARTUUID}"
  write_shell_config_var SWAP_FALLBACK_RAW_DEVICE "${SWAP_FALLBACK_RAW_DEVICE}"
  write_shell_config_var SWAP_FALLBACK_MAPPER_NAME "${SWAP_FALLBACK_MAPPER_NAME}"
  write_shell_config_var SWAP_FALLBACK_MAPPER "${SWAP_FALLBACK_MAPPER}"
  write_shell_config_var SWAP_FALLBACK_PRIORITY "${SWAP_FALLBACK_PRIORITY}"
  write_shell_config_var DMCRYPT_EPHEMERAL_CIPHER "${DMCRYPT_EPHEMERAL_CIPHER}"
  write_shell_config_var DMCRYPT_EPHEMERAL_KEY_SIZE "${DMCRYPT_EPHEMERAL_KEY_SIZE}"
  write_shell_config_var DMCRYPT_EPHEMERAL_HASH "${DMCRYPT_EPHEMERAL_HASH}"
  write_shell_config_var DMCRYPT_RANDOM_KEY_FILE "${DMCRYPT_RANDOM_KEY_FILE}"
}

write_target_swap_fallback_config() {
  validate_raw_storage_partition "$SWAP_FALLBACK_RAW_DEVICE" "$DEV_PART_RAW_SWAP_MB"
  SWAP_FALLBACK_RAW_DEVICE=$(stable_raw_partition_path "$SWAP_FALLBACK_RAW_DEVICE")
  SWAP_FALLBACK_RAW_PARTUUID=${SWAP_FALLBACK_RAW_DEVICE##*/}
  render_target_asset_with_placeholder_map \
    "$(installer_repo_file_value hooks/target/etc/swap-fallback.conf.tmpl)" \
    "$FILE_SWAP_FALLBACK_CONFIG" 0600 swap_fallback_placeholder_map
}

zram_perl_modules() {
  cat <<'EOF'
Zram.pm
Zram/AtomicFile.pm
Zram/BackingDevice.pm
Zram/Budget.pm
Zram/CLI.pm
Zram/Command.pm
Zram/Command/Apply.pm
Zram/Command/Metrics.pm
Zram/Command/Reset.pm
Zram/Command/Status.pm
Zram/Command/Writeback.pm
Zram/Config.pm
Zram/Config/Parser.pm
Zram/Config/Schema.pm
Zram/Config/Validator.pm
Zram/Daemon.pm
Zram/Daemon/Controller.pm
Zram/Debugfs.pm
Zram/Device.pm
Zram/Error.pm
Zram/IOPressure.pm
Zram/Lock.pm
Zram/Logger.pm
Zram/Metrics.pm
Zram/Path.pm
Zram/Policy.pm
Zram/Pressure.pm
Zram/Pressure/Evaluator.pm
Zram/Procfs.pm
Zram/Procfs/Reader.pm
Zram/Runtime.pm
Zram/Setup/BackingDevice.pm
Zram/Setup/CLI.pm
Zram/Setup/Config.pm
Zram/Setup/Device.pm
Zram/Setup/Lifecycle.pm
Zram/Setup/Lock.pm
Zram/Setup/Mapper.pm
Zram/Setup/Sysfs.pm
Zram/Sizing.pm
Zram/Swap.pm
Zram/Stats.pm
Zram/Sysfs.pm
Zram/Tuning.pm
Zram/Types.pm
EOF
}

stage_target_zram_perl_modules() {
  zram_perl_modules | while IFS= read -r zram_module; do
    [ -n "$zram_module" ] || continue
    stage_target_asset \
      "$(installer_repo_asset_path DIR_TARGET_PERL_ZRAM_WRITEBACK "${zram_module}")" \
      "${DIR_ZRAM_PERL_MODULES}/${zram_module}" \
      0644
  done
}

stage_target_zram_assets() {
  validate_raw_storage_partition "$ZRAM_BACKING_RAW_DEVICE" "$DEV_PART_RAW_ZRAM_MB"
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/modprobe.d/90-zram.conf)" "${FILE_MODPROBE_ZRAM}" 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/modules-load.d/40-zram.conf)" "${FILE_MODULES_LOAD_ZRAM}" 0644
  render_target_asset "$(installer_repo_file_value hooks/target/etc/zram-writeback/setup.conf.tmpl)" "${FILE_ZRAM_DEFAULT}" 0644
  render_target_asset "$(installer_repo_file_value hooks/target/etc/zram-writeback/policy.conf.tmpl)" "${FILE_ZRAM_CONFIG}" 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/tmpfiles.d/common/60-zram-writeback.conf.tmpl)" "${FILE_ZRAM_TMPFILES}" 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/rsyslog.d/36-zram.conf.tmpl)" "${FILE_ZRAM_RSYSLOG}" 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/logrotate.d/zram.tmpl)" "${FILE_ZRAM_LOGROTATE}" 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/libexec/common/zram-device-setup.tmpl)" "${FILE_ZRAM_SETUP_HELPER}" 0755
  stage_target_zram_perl_modules
  stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/libexec/common/zram-writeback.tmpl)" "${FILE_ZRAM_WRITEBACK_HELPER}" 0755
  render_target_template "$TMP_ENV_DIR/zram-setup.service.tmpl" "${TARGET_ROOT}${FILE_ZRAM_SETUP_SERVICE}" 0644
  render_target_template "$TMP_ENV_DIR/zram-writeback.service.tmpl" "${TARGET_ROOT}${FILE_ZRAM_WRITEBACK_SERVICE}" 0644
  render_target_template "$TMP_ENV_DIR/zram-writebackd.service.tmpl" "${TARGET_ROOT}${FILE_ZRAM_WRITEBACKD_SERVICE}" 0644
  render_target_template "$TMP_ENV_DIR/zram-idle-writeback.timer.tmpl" "${TARGET_ROOT}${FILE_ZRAM_IDLE_WRITEBACK_TIMER}" 0644
  render_target_template "$TMP_ENV_DIR/zram-cold-tier.timer.tmpl" "${TARGET_ROOT}${FILE_ZRAM_COLD_TIER_TIMER}" 0644

  verify_target_zram_staging
}

verify_target_zram_staging() {
  for zram_path in \
    "${FILE_ZRAM_TMPFILES}" \
    "${FILE_ZRAM_RSYSLOG}" \
    "${FILE_ZRAM_LOGROTATE}" \
    "${FILE_ZRAM_SETUP_HELPER}" \
    "${FILE_ZRAM_WRITEBACK_HELPER}" \
    "${FILE_ZRAM_SETUP_SERVICE}" \
    "${FILE_ZRAM_WRITEBACK_SERVICE}" \
    "${FILE_ZRAM_WRITEBACKD_SERVICE}" \
    "${FILE_ZRAM_IDLE_WRITEBACK_TIMER}" \
    "${FILE_ZRAM_COLD_TIER_TIMER}"
  do
    [ -e "${TARGET_ROOT}${zram_path}" ] ||
      installer_fatal "staged zram asset is missing: ${zram_path}"
  done

  normalize_target_tmpfiles_directory_policy \
    "${FILE_ZRAM_TMPFILES}" \
    "zram runtime and managed log state"
  run_in_target \
    "create zram runtime and managed log state" \
    __INSTALLER_PATH_DIR_USR_BIN__/systemd-tmpfiles \
    --create \
    "${FILE_ZRAM_TMPFILES}"
  run_in_target \
    "validate zram rsyslog configuration" \
    __INSTALLER_PATH_DIR_USR_SBIN__/rsyslogd \
    -N1 \
    -f \
    __INSTALLER_PATH_DIR_ETC__/rsyslog.conf
}


set_target_default_unit() {
  stage_target_default_systemd_unit multi-user.target
}

target_unit_exists() {
  unit=$1

  target_systemd_unit_path "$unit" system >__INSTALLER_PATH_DIR_DEV__/null 2>&1
}

enable_target_required_unit() {
  unit=$1
  target_unit_exists "$unit" || installer_fatal "expected target unit is missing: ${unit}"
  stage_target_systemd_unit_enabled "$unit" system
}

enable_target_storage_units() {
  enable_target_required_unit "swap-fallback.service"
  if tmpfs_policy_enabled TMPFS_VAR_LIB_APT_LISTS; then
    enable_target_required_unit "apt-refresh-lists.service"
  fi
  enable_target_required_unit "fstrim.timer"
}
