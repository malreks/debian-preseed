#!/bin/sh
# Desktop-only Incus login integration; the host bootstrap is shared separately.
set -eu
runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}
# shellcheck disable=SC1090
. "$bootstrap_lib"
bootstrap_source_common_lib ""
seed_base=$(installer_seed_base "")
installer_ensure_context_loaded "$seed_base"
installer_assert_class_plan
[ "$INSTALLER_HOST_VARIANT" = desktop ] || installer_fatal 'desktop virtualization requires the desktop family'
installer_tools_class_selected || installer_fatal 'desktop virtualization requires the medium or full class'
profile="${DIR_INSTALLER_LATE_ENV}/desktop-virtualization.env"
installer_fetch_host_env "$seed_base" "$INSTALLER_HOST_PROFILE" "$profile" 0600
installer_load_data_env "$profile"
bootstrap_source_common_support_libs "$seed_base" "${DIR_INSTALLER_LATE_ENV}/desktop-virtualization-support" fetch hook target
operator=$(installer_cmdline_value primary_user) || installer_fatal 'desktop virtualization operator is missing'
case "$operator" in ''|root|*[!a-z0-9_-]*) installer_fatal 'invalid desktop virtualization operator' ;; esac
case "${INCUS_WEB_UI_ENABLE:?explicit desktop Web UI policy required}" in true|false) ;; *) installer_fatal 'invalid desktop Incus Web UI policy' ;; esac
if [ "$INCUS_WEB_UI_ENABLE" = true ]; then
  # Inspect package identity and native data inside the offline target. This
  # neither opens a remote API nor starts a browser, menu or Incus daemon.
  run_in_target 'verify desktop Incus Web UI package integration' "${DIR_USR_BIN}/python3" -I -c '
from pathlib import Path
import subprocess
status = subprocess.run(["/usr/bin/dpkg-query", "-W", "-f=${db:Status-Abbrev}", "incus-ui-canonical"],
    check=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=15).stdout
if status != b"ii ":
    raise SystemExit("desktop Incus Web UI package is not configured")
if not Path("__INSTALLER_PATH_DIR_OPT__/incus/ui/index.html").is_file():
    raise SystemExit("desktop Incus Web UI package payload is missing")
if "INCUS_UI=__INSTALLER_PATH_DIR_OPT__/incus/ui/" not in Path("__INSTALLER_PATH_DIR_OPT__/incus/lib/systemd/incusd").read_text():
    raise SystemExit("Incus package wrapper does not select its packaged Web UI")
'
  installer_stage_profile_file FILE_TARGET_INCUS_DESKTOP_UI_CHECK "${DIR_USR_LOCAL_LIBEXEC}/incus-desktop-ui-check" 0755
  installer_stage_profile_file FILE_TARGET_AA_INCUS_DESKTOP_UI "${DIR_APPARMOR}/incus-desktop-ui" 0644
  installer_stage_profile_file FILE_TARGET_UNIT_INCUS_DESKTOP_UI "${DIR_SYSTEMD_SYSTEM}/incus-desktop-ui-check.service" 0644
  installer_stage_profile_file FILE_TARGET_INCUS_DESKTOP_USER_UI "${DIR_SYSTEMD_SYSTEM_INCUS_USER_DROPIN}/60-desktop-ui.conf" 0644
fi
  # Only desktop logins publish the desktop work-root selector functions.
  # Server clients use their native private HOME configuration and cache.
  installer_stage_profile_file FILE_TARGET_SKEL_PROFILE_72_INCUS_TMPL \
    "${DIR_ETC_SKEL_DESKTOP}/.profile.d/72-incus.sh" 0644
  account=$(awk -F: -v user="$operator" '$1==user {print $3 ":" $4 ":" $6; count++} END {if(count!=1) exit 1}' "${TARGET_ROOT}${DIR_ETC}/passwd") ||
    installer_fatal 'virtualization operator passwd record is ambiguous'
  account_uid=${account%%:*}; rest=${account#*:}; account_gid=${rest%%:*}; account_home=${rest#*:}
  case "$account_home" in "${DIR_HOME}/"*) ;; *) installer_fatal 'virtualization operator home is outside the configured home root' ;; esac
  case "$account_home" in *..*|*//*|*[!A-Za-z0-9_./-]*) installer_fatal 'unsafe virtualization operator home' ;; esac
  [ -d "${TARGET_ROOT}${account_home}/.profile.d" ] && [ ! -L "${TARGET_ROOT}${account_home}/.profile.d" ] ||
    installer_fatal 'desktop profile directory must already be prepared by account publication'
  destination="${TARGET_ROOT}${account_home}/.profile.d/72-incus.sh"
  [ ! -L "$destination" ] || installer_fatal 'indirect desktop Incus profile destination'
  install -o "$account_uid" -g "$account_gid" -m 0600 \
    "${TARGET_ROOT}${DIR_INSTALLER_TARGET_DEFAULTS}/desktop/.profile.d/72-incus.sh" "$destination"
installer_info 'desktop Incus client login integration and selected UI package verified; shared host API remains local-only'
