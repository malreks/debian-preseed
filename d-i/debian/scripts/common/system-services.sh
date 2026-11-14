#!/bin/sh
# Shared system policy; native services retain their own activation contracts.
set -eu
runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}
# shellcheck disable=SC1090
. "$bootstrap_lib"
bootstrap_source_common_lib ""
SEED_BASE=$(installer_seed_base "")
installer_ensure_context_loaded "$SEED_BASE"
TMP_ENV_DIR=$DIR_INSTALLER_LATE_ENV
LATE_COMMAND_HOST_ENV="${TMP_ENV_DIR}/system-services.env"
installer_fetch_host_env "$SEED_BASE" "$INSTALLER_HOST_PROFILE" "$LATE_COMMAND_HOST_ENV" 0600
installer_load_data_env "$LATE_COMMAND_HOST_ENV"
installer_assert_class_plan
bootstrap_source_common_support_libs "$SEED_BASE" "${TMP_ENV_DIR}/system-service-support" fetch hook target
for module in FILE_LATE_CORE FILE_LATE_TARGET_ASSETS FILE_LATE_TEMPLATES FILE_LATE_STORAGE_MAINTENANCE FILE_LATE_VOLATILE_STORAGE; do
  module_file="${TMP_ENV_DIR}/${module}.sh"
  installer_fetch_file "$SEED_BASE" "$(installer_repo_file_value "$module")" "$module_file.source" 0600
  installer_apply_scalar_placeholders "$module_file.source" "$module_file"
  installer_assert_no_unresolved_path_placeholders "$module_file" "$module"
  # Authenticated implementation, never profile data as shell code.
  # shellcheck disable=SC1090
  . "$module_file"
done

validate_tmpfs_policy_env
installer_stage_profile_file FILE_TARGET_LIBEXEC_NETWORK_ONLINE_CHECK "${DIR_USR_LOCAL_LIBEXEC}/network-online-check" 0755
installer_stage_profile_file FILE_TARGET_INSTALL_TOOLS_SYSTEM_LOG "${DIR_LIBEXEC_INSTALL_TOOLS}/system-log.sh" 0644
install_target_tmpfs_pre_clean_assets
install_target_tmpfs_tmpfiles_assets
if tmpfs_policy_enabled TMPFS_VAR_LIB_APT_LISTS; then
  installer_stage_profile_file FILE_TARGET_LIBEXEC_APT_REFRESH_LISTS_TMPL "$FILE_APT_REFRESH_LISTS_HELPER" 0755
  installer_stage_profile_file FILE_TARGET_UNIT_APT_REFRESH_LISTS_SERVICE_TMPL "$FILE_APT_REFRESH_LISTS_SERVICE" 0644
  installer_stage_offline_unit_link "$FILE_APT_REFRESH_LISTS_SERVICE"
fi

stage_target_systemd_resource_policy_assets
installer_stage_profile_file FILE_TARGET_UNIT_USER_INSTANCE_SERVICE_D_50_OOM_SCORE \
  "${DIR_SYSTEMD_SYSTEM_USER_MANAGER_DROPIN}/50-oom-score.conf" 0644
installer_stage_profile_file FILE_TARGET_UNIT_SYSTEMD_CREDS_SOCKET_D_10_ENCRYPTED_ONLY \
  "${DIR_SYSTEMD_SYSTEM_SYSTEMD_CREDS_SOCKET_DROPIN}/10-encrypted-only.conf" 0644
installer_stage_profile_file FILE_TARGET_UNIT_APPARMOR_SERVICE_D_20_CACHE \
  "${DIR_SYSTEMD_SYSTEM_APPARMOR_DROPIN}/20-cache.conf" 0644

# Audit and AppArmor are a universal installation baseline. Packages belong
# to the suite APT fragment; no selectable class chooses whether to protect a
# server or desktop. Keep native auditd as the sole audit-netlink/file owner.
installer_stage_profile_file FILE_TARGET_APPARMOR_PARSER "${DIR_ETC}/apparmor/parser.conf" 0644
installer_stage_profile_file FILE_TARGET_APPARMOR_EASYPROF "${DIR_ETC}/apparmor/easyprof.conf" 0644
installer_stage_profile_file FILE_TARGET_APPARMOR_LOGPROF_TMPL "${DIR_ETC}/apparmor/logprof.conf" 0644
installer_stage_profile_file FILE_TARGET_AUDIT_CONFIG "${DIR_ETC_AUDIT}/auditd.conf" 0640
installer_stage_profile_file FILE_TARGET_AUDIT_RULES "${DIR_ETC_AUDIT_RULES}/zz-managed.rules" 0640
# Debian auditd's default file sets -b 8192. The managed kernel boot policy
# owns the backlog instead; remove only that package default in this target.
audit_package_rules="${TARGET_ROOT}${DIR_ETC_AUDIT_RULES}/audit.rules"
installer_apt_safe_path "$audit_package_rules" || installer_fatal 'unsafe target audit rules ancestry'
[ ! -L "$audit_package_rules" ] || installer_fatal 'indirect target audit package rules'
rm -f "$audit_package_rules"
installer_stage_profile_file FILE_TARGET_AUDIT_PLUGINS_D_AF_UNIX "${DIR_ETC}/audit/plugins.d/af_unix.conf" 0640
installer_stage_profile_file FILE_TARGET_AUDIT_PLUGINS_D_SYSLOG "${DIR_ETC}/audit/plugins.d/syslog.conf" 0640
installer_stage_profile_file FILE_TARGET_TMPFILES_D_75_AUDITD_STORAGE_TMPL "${DIR_TMPFILES_D}/75-auditd-storage.conf" 0644
normalize_target_tmpfiles_directory_policy "${DIR_TMPFILES_D}/75-auditd-storage.conf" 'auditd storage'
installer_stage_profile_file FILE_TARGET_TMPFILES_D_65_AUDIT_SYSLOG "${DIR_TMPFILES_D}/65-audit-syslog.conf" 0644
normalize_target_tmpfiles_directory_policy "${DIR_TMPFILES_D}/65-audit-syslog.conf" 'audit syslog storage'
installer_stage_profile_file FILE_TARGET_UNIT_AUDITD_SERVICE_D_40_LOGGING_TMPL \
  "${DIR_SYSTEMD_SYSTEM_AUDITD_DROPIN}/40-logging.conf" 0644
installer_stage_profile_file FILE_TARGET_LIBEXEC_AUGENRULES_QUIET "${DIR_USR_LOCAL_LIBEXEC}/augenrules-quiet" 0755
installer_stage_profile_file FILE_TARGET_UNIT_AUDIT_RULES_SERVICE_D_OVERRIDE \
  "${DIR_SYSTEMD_SYSTEM_AUDIT_RULES_DROPIN}/override.conf" 0644
run_in_target 'create native audit log paths without loading audit rules' \
  "${DIR_USR_BIN}/systemd-tmpfiles" --create "${DIR_TMPFILES_D}/75-auditd-storage.conf" "${DIR_TMPFILES_D}/65-audit-syslog.conf"

# Diagnostics remain explicitly operator-armed. Installing the CLI/unit does
# not create its armed marker, collect inventory, or rebuild an initramfs.
installer_stage_profile_file FILE_TARGET_BIN_DEBUGSYS "${DIR_USR_LOCAL_BIN}/debugsys" 0755
installer_stage_profile_file FILE_TARGET_LIBEXEC_DEBUGSYS_TMPL "${DIR_USR_LOCAL_LIBEXEC}/debugsys.py" 0755
installer_stage_profile_file FILE_TARGET_LIBEXEC_DEBUGSYS_INITRAMFS "${DIR_USR_LOCAL_LIBEXEC}/debugsys-initramfs" 0755
installer_stage_profile_file FILE_TARGET_SHARE_DEBUGSYS_INITRAMFS_HOOK "${DIR_USR_LOCAL_SHARE_DEBUGSYS_INITRAMFS}/hook" 0755
installer_stage_profile_file FILE_TARGET_AA_DEBUGSYS "${DIR_APPARMOR}/debugsys" 0644
installer_stage_profile_file FILE_TARGET_UNIT_DEBUGSYS_BOOT_REPORT_SERVICE_TMPL \
  "${DIR_SYSTEMD_SYSTEM}/debugsys-boot-report.service" 0644
installer_stage_offline_unit_link "${DIR_SYSTEMD_SYSTEM}/debugsys-boot-report.service"

# Boot profiles are kernel/sysctl policy, independent of a graphical session.
installer_stage_profile_file FILE_TARGET_INSTALL_TOOLS_BOOTPROFILE_APPLY_TMPL "$FILE_BOOTPROFILE_APPLY" 0755
installer_stage_profile_file FILE_TARGET_UNIT_BOOTPROFILE_APPLY_SERVICE_TMPL "$FILE_BOOTPROFILE_SERVICE" 0644
installer_stage_profile_file FILE_TARGET_SYSCTL_D_PROFILES_BALANCED_40_BALANCED_TMPL "$FILE_SYSCTL_PROFILE_DEFAULT" 0644
installer_stage_profile_file FILE_TARGET_SYSCTL_D_PROFILES_HARDENED_40_HARDENED_TMPL "$FILE_SYSCTL_PROFILE_HARDENED" 0644
installer_stage_profile_file FILE_TARGET_SYSCTL_D_PROFILES_PERFORMANCE_40_PERFORMANCE_TMPL "$FILE_SYSCTL_PROFILE_PERFORMANCE" 0644
installer_stage_offline_unit_link "$FILE_BOOTPROFILE_SERVICE"

# One journald storage owner honors each profile's retention and volatile flag.
# Forwarding is enabled only after rsyslog reports readiness, for both families.
render_target_resource_asset "$(installer_repo_file_value FILE_TARGET_SYSTEMD_JOURNALD_CONF_D_10_STORAGE_TMPL)" \
  "$FILE_JOURNALD_STORAGE_CONF" 0644
validate_target_journal_storage_policy
installer_stage_profile_file FILE_TARGET_SYSTEMD_JOURNALD_CONF_D_SYSLOG \
  "${DIR_JOURNALD_CONF_D}/syslog.conf" 0644
installer_stage_profile_file FILE_TARGET_LIBEXEC_JOURNAL_CHECK "${DIR_USR_LOCAL_LIBEXEC}/journal-check" 0755
installer_stage_profile_file FILE_TARGET_LIBEXEC_JOURNAL_SEALING "${DIR_USR_LOCAL_LIBEXEC}/journal-sealing" 0755
installer_stage_profile_file FILE_TARGET_UNIT_JOURNAL_SEALING_SERVICE "${DIR_SYSTEMD_SYSTEM}/journal-sealing.service" 0644
installer_stage_profile_file FILE_TARGET_LIBEXEC_JOURNAL_SNAPSHOT_TMPL "${DIR_USR_LOCAL_LIBEXEC}/journal-snapshot" 0755
installer_stage_profile_file FILE_TARGET_UNIT_BOOT_LOG_SERVICE_TMPL "${DIR_SYSTEMD_SYSTEM}/boot-log.service" 0644
installer_stage_profile_file FILE_TARGET_UNIT_BOOT_LOG_TIMER_TMPL "${DIR_SYSTEMD_SYSTEM}/boot-log.timer" 0644
installer_stage_profile_file FILE_TARGET_LIBEXEC_JOURNAL_FORWARDING "${DIR_USR_LOCAL_LIBEXEC}/journal-forwarding" 0755
installer_stage_profile_file FILE_TARGET_UNIT_RSYSLOG_JOURNAL_FORWARDING_SERVICE \
  "${DIR_SYSTEMD_SYSTEM}/rsyslog-journal-forwarding.service" 0644
installer_stage_profile_file FILE_TARGET_UNIT_RSYSLOG_SERVICE_D_40_JOURNAL_FORWARDING \
  "${DIR_SYSTEMD_SYSTEM_RSYSLOG_DROPIN}/40-journal-forwarding.conf" 0644
installer_stage_offline_unit_link "${DIR_SYSTEMD_SYSTEM}/boot-log.timer"
installer_stage_offline_unit_link "${DIR_SYSTEMD_SYSTEM}/journal-sealing.service"
run_in_target 'prepare persistent boot journal directory without reading journals' \
  "${DIR_USR_LOCAL_LIBEXEC}/journal-snapshot" --prepare

# Package-owned scanners share logging policy. Installing a timer/drop-in for
# an absent scanner is forbidden; the selected class package set is authority.
installer_stage_profile_file FILE_TARGET_LIBEXEC_NATIVE_LOGGING_TMPL "${DIR_USR_LOCAL_LIBEXEC}/native-logging" 0755
installer_stage_profile_file FILE_TARGET_TMPFILES_D_58_NATIVE_LOGS_TMPL "${DIR_TMPFILES_D}/58-native-logs.conf" 0644
for scanner in clamav-freshclam clamav-daemon lynis; do
  installer_plan_package_selected "$scanner" || continue
  installer_stage_profile_asset "$(installer_repo_asset_path DIR_TARGET_UNIT "${scanner}.service.d/40-logging.conf")" \
    "$(installer_systemd_dropin_dir system "${scanner}.service")/40-logging.conf" 0644
done
if installer_plan_package_selected rkhunter; then
  installer_stage_profile_file FILE_TARGET_RKHUNTER_D_99_LOGGING_TMPL "${DIR_ETC}/rkhunter.d/99-logging.conf" 0644
fi
run_in_target 'create native scanner evidence paths without running a scanner' \
  "${DIR_USR_BIN}/systemd-tmpfiles" --create "${DIR_TMPFILES_D}/58-native-logs.conf"
run_in_target 'publish native package logging settings without starting a service' \
  "${DIR_USR_LOCAL_LIBEXEC}/native-logging" --configure

if [ "$INSTALLER_HOST_VARIANT" = server ]; then
  # The server uses the same NetworkManager physical-uplink implementation.
  # Neither Stubby nor the desktop app-veth DNS stack is activated here.
  installer_stage_profile_file FILE_TARGET_UNIT_NETWORKMANAGER_SERVICE_D_20_DISPATCHER \
    "${DIR_SYSTEMD_SYSTEM_NETWORKMANAGER_DROPIN}/20-dispatcher.conf" 0644
  installer_stage_profile_file FILE_TARGET_UNIT_NETWORKMANAGER_DISPATCHER_SERVICE_D_20_PERSISTENT \
    "${DIR_SYSTEMD_SYSTEM_NETWORKMANAGER_DISPATCHER_DROPIN}/20-persistent.conf" 0644
  installer_stage_profile_file FILE_TARGET_LIBEXEC_NETWORK_IFUP_HOTPLUG \
    "${DIR_USR_LOCAL_LIBEXEC}/network-ifup-hotplug" 0755
  installer_stage_profile_file FILE_TARGET_UNIT_IFUP_INSTANCE_SERVICE_D_40_DEVICE_LIFECYCLE \
    "${DIR_SYSTEMD_SYSTEM_IFUP_TEMPLATE_DROPIN}/40-device-lifecycle.conf" 0644
  installer_stage_profile_file FILE_TARGET_WPA_SUPPLICANT \
    "${DIR_ETC}/wpa_supplicant/wpa_supplicant.conf" 0644
  installer_stage_profile_file FILE_TARGET_UNIT_WPA_SUPPLICANT_SERVICE_D_OVERRIDE \
    "${DIR_SYSTEMD_SYSTEM_WPA_SUPPLICANT_DROPIN}/override.conf" 0644
fi
installer_info 'shared systemd, AppArmor startup, boot profile, journal and resource policy staged offline'
