#!/bin/sh
# Shared Btrfs snapshot policy. The selected host profile owns schedule/retention.
set -eu
runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}
# shellcheck disable=SC1090
. "$bootstrap_lib"
bootstrap_source_common_lib ""
seed_base=$(installer_seed_base "")
installer_ensure_context_loaded "$seed_base"
# Late providers run in fresh shells; the dispatcher cannot pass its functions.
bootstrap_source_common_support_libs "$seed_base" "${DIR_INSTALLER_LATE_ENV}/timeshift-support" target || exit "$?"
installer_assert_class_plan
installer_snapshots_enabled || installer_fatal 'Timeshift stage requires TIMESHIFT_ENABLE=true in the selected host profile'
profile_env="${DIR_INSTALLER_LATE_ENV}/timeshift-profile.env"
installer_fetch_host_env "$seed_base" "$INSTALLER_HOST_PROFILE" "$profile_env" 0600
installer_load_data_env "$profile_env"
[ "$TIMESHIFT_ENABLE" = true ] && [ "$SNAPSHOTS_POLICY" = timeshift-btrfs ] || installer_fatal 'Timeshift requires an explicit Btrfs profile policy'
layout_env="${DIR_INSTALLER_ENV}/runtime.env"
[ -f "$layout_env" ] || layout_env="$(installer_runtime_state_dir)/runtime.env"
[ -f "$layout_env" ] && [ ! -L "$layout_env" ] || installer_fatal 'frozen partition identities unavailable'
# This is private installer-generated layout data, not a sourced profile.
# shellcheck disable=SC1090
. "$layout_env"
root_device=${DEV_PART_ROOT:?missing installed root identity}
if [ "$CRYPTO_LUKS2_ROOT" = true ]; then root_device="${DIR_DEV}/mapper/${ROOT_CRYPT_NAME:?missing frozen root mapper identity}"; fi
[ -b "$root_device" ] || installer_fatal 'Timeshift root device is unavailable'
[ "$(blkid -s TYPE -o value "$root_device")" = btrfs ] || installer_fatal 'Timeshift root identity is not Btrfs'
root_options=$(awk '$1 !~ /^#/ && $2=="/" && $3=="btrfs" {if(++count>1) exit 2; options=$4} END {if(count!=1) exit 1; print options}' "${TARGET_ROOT}${DIR_ETC}/fstab")
case ",$root_options," in *,subvol=@,*|*,subvol=/@,*) ;; *) installer_fatal 'Timeshift requires root subvolume @' ;; esac
root_default=$(btrfs subvolume get-default "$TARGET_ROOT")
case "$root_default" in 'ID 5 '*) ;; *) installer_fatal 'Timeshift requires Btrfs default subvolume ID 5; no implicit subvolume conversion' ;; esac
TIMESHIFT_BACKUP_DEVICE_UUID=$(blkid -s UUID -o value "$root_device")
TIMESHIFT_PARENT_DEVICE_UUID=
if [ "$CRYPTO_LUKS2_ROOT" = true ]; then TIMESHIFT_PARENT_DEVICE_UUID=$(blkid -s UUID -o value "$DEV_PART_ROOT"); fi
case "$TIMESHIFT_BACKUP_DEVICE_UUID" in ''|*[!a-fA-F0-9-]*) installer_fatal 'invalid snapshot device UUID' ;; esac
installer_stage_profile_file hooks/target/etc/apparmor.d/common/abstractions/timeshift-runtime "${DIR_APPARMOR}/abstractions/timeshift-runtime" 0644
installer_stage_profile_file hooks/target/etc/apparmor.d/common/timeshift "${DIR_APPARMOR}/timeshift" 0644
if [ "$INSTALLER_HOST_VARIANT" = server ]; then
  timeshift_modes="${TARGET_ROOT}${DIR_ETC}/apparmor/modes.conf"
  installer_apt_safe_path "$timeshift_modes" || installer_fatal 'unsafe Timeshift mode policy ancestry'
  [ -f "$timeshift_modes" ] && [ ! -L "$timeshift_modes" ] || installer_fatal 'shared AppArmor mode policy is missing'
  printf 'enforce required timeshift -\n' >>"$timeshift_modes"
fi
installer_stage_profile_file hooks/target/etc/timeshift/timeshift.json.tmpl "$FILE_TIMESHIFT_CONFIG" 0600
installer_stage_profile_file hooks/target/usr/local/libexec/common/timeshift-snapshot "$FILE_TIMESHIFT_SNAPSHOT_HELPER" 0755
installer_stage_profile_file hooks/target/usr/local/libexec/common/timeshift/notify-send "$FILE_TIMESHIFT_NOTIFY_SHIM" 0755
installer_stage_profile_file hooks/target/etc/rsyslog.d/38-timeshift.conf.tmpl "${DIR_RSYSLOG_D}/38-timeshift.conf" 0644
installer_stage_profile_file hooks/target/etc/logrotate.d/timeshift.tmpl "${DIR_LOGROTATE_D}/timeshift" 0644
installer_stage_profile_file hooks/target/etc/tmpfiles.d/common/61-timeshift.conf.tmpl "${DIR_TMPFILES_D}/61-timeshift.conf" 0644
installer_stage_profile_file hooks/target/etc/systemd/common/system/timeshift-daily.service "$FILE_TIMESHIFT_DAILY_SERVICE" 0644
installer_stage_profile_file hooks/target/etc/systemd/common/system/timeshift-daily.timer "$FILE_TIMESHIFT_DAILY_TIMER" 0644
installer_stage_profile_file hooks/target/etc/systemd/common/system/timeshift-weekly.service "$FILE_TIMESHIFT_WEEKLY_SERVICE" 0644
installer_stage_profile_file hooks/target/etc/systemd/common/system/timeshift-weekly.timer "$FILE_TIMESHIFT_WEEKLY_TIMER" 0644
installer_stage_profile_file hooks/target/etc/systemd/common/system/timeshift-monthly.service "$FILE_TIMESHIFT_MONTHLY_SERVICE" 0644
installer_stage_profile_file hooks/target/etc/systemd/common/system/timeshift-monthly.timer "$FILE_TIMESHIFT_MONTHLY_TIMER" 0644
installer_stage_profile_file hooks/target/etc/systemd/common/system/timeshift-.service.d/60-resource-class.conf \
  "${DIR_SYSTEMD_SYSTEM_TIMESHIFT_FAMILY_DROPIN}/60-resource-class.conf" 0644
# One profile switch owns snapshots and the managed GRUB Btrfs menu.
installer_stage_profile_file hooks/target/etc/default/grub-btrfs/config.tmpl "$FILE_GRUB_BTRFS_CONFIG" 0644
installer_stage_profile_file hooks/target/usr/local/libexec/common/grub-btrfs-refresh "$FILE_GRUB_BTRFS_REFRESH_HELPER" 0755
installer_stage_profile_file hooks/target/etc/timeshift/backup-hooks.d/90-grub-btrfs-refresh "$FILE_TIMESHIFT_GRUB_REFRESH_HOOK" 0755
installer_stage_profile_file hooks/target/etc/systemd/common/system/grub-btrfs-refresh.service "$FILE_GRUB_BTRFS_REFRESH_SERVICE" 0644
installer_stage_profile_file hooks/target/etc/systemd/common/system/grub-btrfs-refresh.path "$FILE_GRUB_BTRFS_REFRESH_PATH" 0644
installer_stage_profile_file hooks/target/etc/systemd/common/system/grub-btrfs-refresh.timer "$FILE_GRUB_BTRFS_REFRESH_TIMER" 0644
installer_stage_offline_unit_link "$FILE_GRUB_BTRFS_REFRESH_PATH"
installer_stage_offline_unit_link "$FILE_GRUB_BTRFS_REFRESH_TIMER"
# Storage/GRUB stages have completed, and the helper now exists in target.
run_in_target 'prime managed GRUB Btrfs snapshot menu' "$FILE_GRUB_BTRFS_REFRESH_HELPER"
for kind in DAILY WEEKLY MONTHLY; do
  case "$kind" in
    DAILY) count=$TIMESHIFT_COUNT_DAILY; timer=$FILE_TIMESHIFT_DAILY_TIMER ;;
    WEEKLY) count=$TIMESHIFT_COUNT_WEEKLY; timer=$FILE_TIMESHIFT_WEEKLY_TIMER ;;
    MONTHLY) count=$TIMESHIFT_COUNT_MONTHLY; timer=$FILE_TIMESHIFT_MONTHLY_TIMER ;;
  esac
  case "$count" in ''|*[!0-9]*) installer_fatal 'invalid snapshot retention' ;; esac
  if [ "$count" -gt 0 ]; then installer_stage_offline_unit_link "$timer"; fi
done
installer_info 'Timeshift staged using selected profile retention; no snapshots taken during installation'
