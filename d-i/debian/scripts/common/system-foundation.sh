#!/bin/sh
# Universal target support: Perl modules and zram; no desktop or enrollment.
set -eu
runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}
# shellcheck disable=SC1090
. "$bootstrap_lib"
bootstrap_source_common_lib ""
seed_base=$(installer_seed_base "")
installer_ensure_context_loaded "$seed_base"
profile_env="${DIR_INSTALLER_LATE_ENV}/foundation-profile.env"
installer_fetch_host_env "$seed_base" "$INSTALLER_HOST_PROFILE" "$profile_env" 0600
installer_load_data_env "$profile_env"
installer_load_primary_account
installer_assert_class_plan
bootstrap_source_common_support_libs "$seed_base" "${DIR_INSTALLER_LATE_ENV}/foundation-support" fetch target
layout_env="$(installer_runtime_state_dir)/runtime.env"
if [ -f "${DIR_INSTALLER_ENV}/runtime.env" ]; then layout_env="${DIR_INSTALLER_ENV}/runtime.env"; fi
[ -f "$layout_env" ] && [ ! -L "$layout_env" ] || installer_fatal 'frozen partman layout is unavailable'
# Installer-generated private layout state, never sourced profile data.
# shellcheck disable=SC1090
. "$layout_env"
: "${ZRAM_BACKING_RAW_DEVICE:?partman did not bind the raw zram partition}"
ZRAM_BACKING_RAW_PARTUUID=$(blkid -s PARTUUID -o value "$ZRAM_BACKING_RAW_DEVICE")
case "$ZRAM_BACKING_RAW_PARTUUID" in ''|*[!a-fA-F0-9-]*) installer_fatal 'invalid raw zram PARTUUID' ;; esac
ZRAM_ENABLE=1
# Unit dependencies and sysfs names are derived from the canonical layout,
# rather than requiring redundant fields in every host profile.
ZRAM_SETUP_UNIT=${FILE_ZRAM_SETUP_SERVICE##*/}
ZRAM_SWAP_DEVICE_NAME=${ZRAM_SWAP_DEVICE##*/}
ZRAM_SYSFS="${DIR_SYS}/block/${ZRAM_SWAP_DEVICE##*/}"
ZRAM_RUNTIME_DIR="${DIR_RUN}/zram"
ZRAM_LOCK_FILE="${ZRAM_RUNTIME_DIR}/zram-writeback.lock"
: "${ZRAM_BACKING_RESERVE_MIB:=128}"
ZRAM_POLICY_CONFIG=$FILE_ZRAM_CONFIG

if [ -z "${BOOTSTRAP_PREPARED_SOURCE_ROOT:-}" ]; then
perl_assets=$(installer_class_metadata_read_path catalog/compiled/shared-perl-assets.tsv)
while IFS="$(printf '\t')" read -r source_path relative_path source_family || [ -n "$source_path" ]; do
  [ -n "$source_path" ] || continue
  case "$source_family" in common|"$INSTALLER_HOST_VARIANT") ;; desktop|server) continue ;; *) installer_fatal 'invalid Perl source family' ;; esac
  case "$relative_path" in timeshift/*) installer_snapshots_enabled || continue ;; esac
  installer_stage_profile_asset "$source_path" "${DIR_PERL5_SITE_PERL}/${relative_path}" 0644
done <"$perl_assets"
fi
install -d -m 0755 "${TARGET_ROOT}${DIR_PYTHON3_SITE_PACKAGES}"
# Debian's unversioned system dist-packages interface loads this data-only
# path entry even with -I. Managed modules do not depend on a minor ABI path.
installer_stage_profile_file hooks/target/usr/lib/python3/dist-packages/installer-managed.pth \
  "${DIR_PYTHON3_SYSTEM_PACKAGES}/installer-managed.pth" 0644
installer_stage_profile_file hooks/target/usr/local/libexec/common/installer-artifact-fetch \
  "${DIR_USR_LOCAL_LIBEXEC}/installer-artifact-fetch" 0755

# The shared mode writer and its confinement precede every role-specific policy.
# Only offline files/activation links are published; policy is loaded at boot.
for abstraction in wrapper-base wrapper-perl wrapper-python wrapper-terminal; do
  installer_stage_profile_asset "$(installer_repo_asset_path DIR_TARGET_AA_ABSTRACTIONS "$abstraction")" \
    "${DIR_APPARMOR}/abstractions/$abstraction" 0644
done
installer_stage_profile_file hooks/target/etc/apparmor.d/common/system-wrappers.tmpl "${DIR_APPARMOR}/system-wrappers" 0644
installer_stage_profile_file hooks/target/etc/apparmor.d/common/apparmor-modes "${DIR_APPARMOR}/apparmor-modes" 0644
installer_stage_profile_file hooks/target/usr/local/libexec/common/apparmor-modes-run "${DIR_USR_LOCAL_LIBEXEC}/apparmor-modes-run" 0755
installer_stage_profile_file hooks/target/etc/systemd/common/system/apparmor-modes.service "${DIR_SYSTEMD_SYSTEM}/apparmor-modes.service" 0644
installer_stage_profile_file hooks/target/etc/apparmor/common/modes-common.conf "${DIR_ETC}/apparmor/modes.conf" 0644
installer_stage_offline_unit_link "${DIR_SYSTEMD_SYSTEM}/apparmor-modes.service"

installer_apt_install_target_policy "$TARGET_ROOT" install
# The raw fallback is distinct from the writeback device; both identities come
# from the frozen partman layout. Never activate swap in the installer here.
: "${SWAP_FALLBACK_RAW_DEVICE:?missing raw swap partition}"
[ "$SWAP_FALLBACK_RAW_DEVICE" = "$DEV_PART_RAW_SWAP" ] || installer_fatal 'swap fallback differs from frozen raw partition'
validate_raw_storage_partition "$SWAP_FALLBACK_RAW_DEVICE" "$DEV_PART_RAW_SWAP_MB"
SWAP_FALLBACK_RAW_DEVICE=$(stable_raw_partition_path "$SWAP_FALLBACK_RAW_DEVICE")
# Bind both rendered fields to the same verified identity, without a second
# blkid lookup that could disagree if the device identity changed in between.
SWAP_FALLBACK_RAW_PARTUUID=${SWAP_FALLBACK_RAW_DEVICE##*/}
SWAP_FALLBACK_MAPPER="${DIR_DEV}/mapper/${SWAP_FALLBACK_MAPPER_NAME}"
installer_stage_profile_file hooks/target/etc/swap-fallback.conf.tmpl "$FILE_SWAP_FALLBACK_CONFIG" 0600
installer_stage_profile_file hooks/target/usr/local/libexec/common/swap-fallback-setup.tmpl "$FILE_SWAP_FALLBACK_HELPER" 0755
installer_stage_profile_file hooks/target/etc/systemd/common/system/swap-fallback.service.tmpl "$FILE_SWAP_FALLBACK_SERVICE" 0644
installer_stage_profile_file hooks/target/etc/modprobe.d/90-zram.conf "$FILE_MODPROBE_ZRAM" 0644
installer_stage_profile_file hooks/target/etc/modules-load.d/40-zram.conf "$FILE_MODULES_LOAD_ZRAM" 0644
installer_stage_profile_file hooks/target/etc/zram-writeback/setup.conf.tmpl "$FILE_ZRAM_DEFAULT" 0644
installer_stage_profile_file hooks/target/etc/zram-writeback/policy.conf.tmpl "$FILE_ZRAM_CONFIG" 0644
installer_stage_profile_file hooks/target/etc/tmpfiles.d/common/60-zram-writeback.conf.tmpl "$FILE_ZRAM_TMPFILES" 0644
installer_stage_profile_file hooks/target/etc/rsyslog.d/36-zram.conf.tmpl "$FILE_ZRAM_RSYSLOG" 0644
installer_stage_profile_file hooks/target/etc/logrotate.d/zram.tmpl "$FILE_ZRAM_LOGROTATE" 0644
installer_stage_profile_file hooks/target/usr/local/libexec/common/zram-device-setup.tmpl "$FILE_ZRAM_SETUP_HELPER" 0755
installer_stage_profile_file hooks/target/usr/local/libexec/common/zram-writeback.tmpl "$FILE_ZRAM_WRITEBACK_HELPER" 0755
installer_stage_profile_file hooks/target/etc/systemd/common/system/zram-setup.service.tmpl "$FILE_ZRAM_SETUP_SERVICE" 0644
installer_stage_profile_file hooks/target/etc/systemd/common/system/zram-writeback.service.tmpl "$FILE_ZRAM_WRITEBACK_SERVICE" 0644
installer_stage_profile_file hooks/target/etc/systemd/common/system/zram-writebackd.service.tmpl "$FILE_ZRAM_WRITEBACKD_SERVICE" 0644
installer_stage_profile_file hooks/target/etc/systemd/common/system/zram-idle-writeback.timer.tmpl "$FILE_ZRAM_IDLE_WRITEBACK_TIMER" 0644
installer_stage_profile_file hooks/target/etc/systemd/common/system/zram-cold-tier.timer.tmpl "$FILE_ZRAM_COLD_TIER_TIMER" 0644
# Existing delegates retain raw wait status, backing-device identity, locks,
# bounded cleanup and uncertain-outcome recovery.
for unit_path in "$FILE_ZRAM_SETUP_SERVICE" "$FILE_ZRAM_WRITEBACKD_SERVICE" "$FILE_ZRAM_IDLE_WRITEBACK_TIMER" "$FILE_ZRAM_COLD_TIER_TIMER" "$FILE_SWAP_FALLBACK_SERVICE"; do
  installer_stage_offline_unit_link "$unit_path"
done
installer_info 'universal Perl runtime and zram staged for the selected role family'
