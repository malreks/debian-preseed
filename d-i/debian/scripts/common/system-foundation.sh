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
ZRAM_SYSFS="${DIR_SYS}/block/${ZRAM_SWAP_DEVICE##*/}"
ZRAM_RUNTIME_DIR="${DIR_RUN}/zram"
ZRAM_LOCK_FILE="${ZRAM_RUNTIME_DIR}/zram-writeback.lock"
: "${ZRAM_BACKING_RESERVE_MIB:=128}"
ZRAM_POLICY_CONFIG=$FILE_ZRAM_CONFIG

perl_assets=$(installer_class_metadata_read_path FILE_SHARED_PERL_ASSETS)
while IFS="$(printf '\t')" read -r source_path relative_path source_family || [ -n "$source_path" ]; do
  [ -n "$source_path" ] || continue
  case "$source_family" in common|"$INSTALLER_HOST_VARIANT") ;; desktop|server) continue ;; *) installer_fatal 'invalid Perl source family' ;; esac
  case "$relative_path" in timeshift/*) installer_snapshots_enabled || continue ;; esac
  installer_stage_profile_asset "$source_path" "${DIR_PERL5_SITE_PERL}/${relative_path}" 0644
done <"$perl_assets"
install -d -m 0755 "${TARGET_ROOT}${DIR_PYTHON3_SITE_PACKAGES}"
# Debian's unversioned system dist-packages interface loads this data-only
# path entry even with -I. Managed modules do not depend on a minor ABI path.
installer_stage_profile_file FILE_TARGET_PYTHON_SITE_BRIDGE \
  "${DIR_PYTHON3_SYSTEM_PACKAGES}/installer-managed.pth" 0644
installer_stage_profile_file FILE_TARGET_LIBEXEC_INSTALLER_ARTIFACT_FETCH \
  "${DIR_USR_LOCAL_LIBEXEC}/installer-artifact-fetch" 0755

# The shared mode writer and its confinement precede every role-specific policy.
# Only offline files/activation links are published; policy is loaded at boot.
for abstraction in wrapper-base wrapper-perl wrapper-python wrapper-terminal; do
  installer_stage_profile_asset "$(installer_repo_asset_path DIR_TARGET_AA_ABSTRACTIONS "$abstraction")" \
    "${DIR_APPARMOR}/abstractions/$abstraction" 0644
done
installer_stage_profile_file FILE_TARGET_AA_SYSTEM_WRAPPERS_TMPL "${DIR_APPARMOR}/system-wrappers" 0644
installer_stage_profile_file FILE_TARGET_AA_APPARMOR_MODES "${DIR_APPARMOR}/apparmor-modes" 0644
installer_stage_profile_file FILE_TARGET_LIBEXEC_APPARMOR_MODES_RUN "${DIR_USR_LOCAL_LIBEXEC}/apparmor-modes-run" 0755
installer_stage_profile_file FILE_TARGET_UNIT_APPARMOR_MODES_SERVICE "${DIR_SYSTEMD_SYSTEM}/apparmor-modes.service" 0644
installer_stage_profile_file FILE_TARGET_APPARMOR_COMMON_MODES "${DIR_ETC}/apparmor/modes.conf" 0644
installer_stage_offline_unit_link "${DIR_SYSTEMD_SYSTEM}/apparmor-modes.service"

installer_stage_profile_file "$(installer_repo_apt_selector APT_CONF_D_20AUTO_UPGRADES)" "${DIR_APT_CONF_D}/20auto-upgrades" 0644
installer_stage_profile_file "$(installer_repo_apt_selector APT_CONF_D_25NO_PDIFFS)" "${DIR_APT_CONF_D}/25no-pdiffs" 0644
installer_stage_profile_file "$(installer_repo_apt_selector APT_CONF_D_52UNATTENDED_UPGRADES)" "${DIR_APT_CONF_D}/52unattended-upgrades" 0644
installer_stage_profile_file "$(installer_repo_apt_selector APT_CONF_D_99NOINSTALL_RECOMMENDS)" "${DIR_APT_CONF_D}/99noinstall-recommends" 0644
# The raw fallback is distinct from the writeback device; both identities come
# from the frozen partman layout. Never activate swap in the installer here.
: "${SWAP_FALLBACK_RAW_DEVICE:?missing raw swap partition}"
SWAP_FALLBACK_RAW_PARTUUID=$(blkid -s PARTUUID -o value "$SWAP_FALLBACK_RAW_DEVICE")
case "$SWAP_FALLBACK_RAW_PARTUUID" in ''|*[!a-fA-F0-9-]*) installer_fatal 'invalid raw swap PARTUUID' ;; esac
SWAP_FALLBACK_MAPPER="${DIR_DEV}/mapper/${SWAP_FALLBACK_MAPPER_NAME}"
installer_stage_profile_file FILE_TARGET_SWAP_FALLBACK_TMPL "$FILE_SWAP_FALLBACK_CONFIG" 0600
installer_stage_profile_file FILE_TARGET_LIBEXEC_SWAP_FALLBACK_SETUP_TMPL "$FILE_SWAP_FALLBACK_HELPER" 0755
installer_stage_profile_file FILE_TARGET_UNIT_SWAP_FALLBACK_SERVICE_TMPL "$FILE_SWAP_FALLBACK_SERVICE" 0644
installer_stage_profile_file FILE_TARGET_MODPROBE_D_90_ZRAM "$FILE_MODPROBE_ZRAM" 0644
installer_stage_profile_file FILE_TARGET_MODULES_LOAD_D_40_ZRAM "$FILE_MODULES_LOAD_ZRAM" 0644
installer_stage_profile_file FILE_TARGET_ZRAM_WRITEBACK_SETUP_TMPL "$FILE_ZRAM_DEFAULT" 0644
installer_stage_profile_file FILE_TARGET_ZRAM_WRITEBACK_POLICY_TMPL "$FILE_ZRAM_CONFIG" 0644
installer_stage_profile_file FILE_TARGET_TMPFILES_D_60_ZRAM_WRITEBACK_TMPL "$FILE_ZRAM_TMPFILES" 0644
installer_stage_profile_file FILE_TARGET_RSYSLOG_D_36_ZRAM_TMPL "$FILE_ZRAM_RSYSLOG" 0644
installer_stage_profile_file FILE_TARGET_LOGROTATE_D_ZRAM_TMPL "$FILE_ZRAM_LOGROTATE" 0644
installer_stage_profile_file FILE_TARGET_LIBEXEC_ZRAM_DEVICE_SETUP_TMPL "$FILE_ZRAM_SETUP_HELPER" 0755
installer_stage_profile_file FILE_TARGET_LIBEXEC_ZRAM_WRITEBACK_TMPL "$FILE_ZRAM_WRITEBACK_HELPER" 0755
installer_stage_profile_file FILE_TARGET_UNIT_ZRAM_SETUP_SERVICE_TMPL "$FILE_ZRAM_SETUP_SERVICE" 0644
installer_stage_profile_file FILE_TARGET_UNIT_ZRAM_WRITEBACK_SERVICE_TMPL "$FILE_ZRAM_WRITEBACK_SERVICE" 0644
installer_stage_profile_file FILE_TARGET_UNIT_ZRAM_WRITEBACKD_SERVICE_TMPL "$FILE_ZRAM_WRITEBACKD_SERVICE" 0644
installer_stage_profile_file FILE_TARGET_UNIT_ZRAM_IDLE_WRITEBACK_TIMER_TMPL "$FILE_ZRAM_IDLE_WRITEBACK_TIMER" 0644
installer_stage_profile_file FILE_TARGET_UNIT_ZRAM_COLD_TIER_TIMER_TMPL "$FILE_ZRAM_COLD_TIER_TIMER" 0644
# Existing delegates retain raw wait status, backing-device identity, locks,
# bounded cleanup and uncertain-outcome recovery.
for unit_path in "$FILE_ZRAM_SETUP_SERVICE" "$FILE_ZRAM_WRITEBACKD_SERVICE" "$FILE_ZRAM_IDLE_WRITEBACK_TIMER" "$FILE_ZRAM_COLD_TIER_TIMER" "$FILE_SWAP_FALLBACK_SERVICE"; do
  installer_stage_offline_unit_link "$unit_path"
done
installer_publish_class_receipt
installer_info 'universal Perl runtime and zram staged for the selected role family'
