#!/bin/sh
# Shared CH341A, UART and verified SNANDer CLI installation. No device is opened.
set -eu
runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}
# shellcheck disable=SC1090
. "$bootstrap_lib"
bootstrap_source_common_lib ""
seed_base=$(installer_seed_base "")
installer_ensure_context_loaded "$seed_base"
installer_assert_class_plan
case "$INSTALLER_HOST_VARIANT" in
  desktop) installer_tools_class_selected || installer_fatal 'firmware installation requires medium/full desktop' ;;
  server) installer_class_selected role/server/devops || installer_fatal 'firmware installation requires server DevOps' ;;
  *) installer_fatal 'unknown firmware role family' ;;
esac
profile="${DIR_INSTALLER_LATE_ENV}/firmware.env"
installer_fetch_host_env "$seed_base" "$INSTALLER_HOST_PROFILE" "$profile" 0600
installer_load_data_env "$profile"
bootstrap_source_common_support_libs "$seed_base" "${DIR_INSTALLER_LATE_ENV}/firmware-support" fetch hook target
installer_load_primary_account
printf '%s\n' "$ACCOUNT_USERNAME" | LC_ALL=C grep -Eq '^[a-z_][a-z0-9_-]{0,31}$' || installer_fatal 'invalid firmware operator identity'
case "$ACCOUNT_USERNAME" in root|ci-github|ci-gitlab|srv-devops|technitium) installer_fatal 'firmware access requires a human operator' ;; esac
# shellcheck disable=SC2016
run_in_target 'prepare firmware authorization groups for the explicit human operator' "${DIR_BIN}/sh" -eu -c '
  [ "$(id -u "$1")" -ge 1000 ] || exit 1
  getent group usbadmin >/dev/null || groupadd --system usbadmin
  getent group dialout >/dev/null
  usermod -a -G usbadmin,dialout -- "$1"
' sh "$ACCOUNT_USERNAME"
installer_stage_profile_file hooks/target/etc/udev/rules.d/61-ch341a-programmers.rules "${DIR_ETC}/udev/rules.d/61-ch341a-programmers.rules" 0644
installer_stage_profile_file hooks/target/usr/local/sbin/common/fwops-mode "${DIR_USR_LOCAL_SBIN}/fwops-mode" 0755
installer_stage_profile_file hooks/target/etc/tmpfiles.d/common/86-firmware-workspace.conf.tmpl "${DIR_TMPFILES_D}/86-firmware-workspace.conf" 0644
installer_stage_profile_file hooks/target/etc/snander/install.json.tmpl "$FILE_SNANDER_POLICY" 0644
run_in_target 'create selected operator firmware workspaces' "${DIR_USR_BIN}/systemd-tmpfiles" --create "${DIR_TMPFILES_D}/86-firmware-workspace.conf"
installer_run_target_setup scripts/common/snander-install.py.tmpl 'install verified SNANDer artifact as data without running it'
installer_info 'shared firmware CLI and workspace staged; no programmer or firmware device was accessed'
