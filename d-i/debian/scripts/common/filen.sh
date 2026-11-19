#!/bin/sh
# Profile-controlled Filen installation for every role family.

install_profile_filen() (
  set -eu
  set +x
  set +v
  case "${FILEN_CLI_PRIV_ENABLE:?}:${FILEN_CLI_OFFSEC_ENABLE:?}" in
    false:false) return 0 ;;
    true:true|true:false|false:true) ;;
    *) installer_fatal "Filen enable flags must be true or false" ;;
  esac
  filen_stage=$(target_private_stage_dir filen)
  cleanup_profile_filen_stage() {
    filen_cleanup_status=$?
    trap - EXIT HUP INT TERM
    case "$filen_cleanup_status" in 76|124|129|130|137|143) filen_uncertain=true ;; *) filen_uncertain=false ;; esac
    if [ "$filen_uncertain" = true ] || [ -e "${TARGET_ROOT}${filen_stage}/outcome-unknown.json" ]; then
      installer_warn "Filen command outcome unknown; private recovery retained at ${filen_stage}"
      exit 76
    fi
    rm -rf -- "${TARGET_ROOT}${filen_stage}"
    exit "$filen_cleanup_status"
  }
  trap cleanup_profile_filen_stage EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  stage_target_asset "$(installer_repo_file_value scripts/common/filen-install.py)" "${filen_stage}/install.py" 0600
  for filen_asset in \
    usr/local/libexec/filen-sync \
    usr/local/lib/perl5/site_perl/filen/FilenSync/Config.pm \
    usr/local/lib/perl5/site_perl/filen/FilenSync/Daemon.pm \
    etc/systemd/system/filen-sync@.service.tmpl \
    etc/apparmor.d/filen-sync.tmpl
  do
    stage_target_template_input "$(installer_repo_asset_path DIR_HOOKS_TARGET "$filen_asset")" \
      "$filen_stage" "assets/${filen_asset}"
  done
  for filen_account in priv offsec; do
    case "$filen_account" in
      priv) filen_enabled=$FILEN_CLI_PRIV_ENABLE ;;
      offsec) filen_enabled=$FILEN_CLI_OFFSEC_ENABLE ;;
    esac
    [ "$filen_enabled" = true ] || continue
    for filen_field in email password 2fa_seed; do
      if [ "$filen_field" = password ]; then
        filen_value=$(installer_cmdline_password_value "filen_${filen_account}_${filen_field}") ||
          installer_fatal "missing Filen ${filen_account} password in installer credential input"
      else
        filen_value=$(installer_cmdline_value "filen_${filen_account}_${filen_field}") ||
          installer_fatal "missing Filen ${filen_account} ${filen_field} in installer credential input"
      fi
      [ -n "$filen_value" ] || installer_fatal "empty Filen credential input"
      (umask 077; printf '%s' "$filen_value" >"${TARGET_ROOT}${filen_stage}/${filen_account}-${filen_field}")
      unset filen_value
    done
  done
  run_in_target "install pinned Filen CLI and isolated sync services" \
    __INSTALLER_PATH_DIR_USR_BIN__/env -i HOME=__INSTALLER_PATH_DIR_ROOT_HOME__ LC_ALL=C.UTF-8 PATH=__INSTALLER_PATH_DIR_USR_SBIN__:__INSTALLER_PATH_DIR_USR_BIN__:__INSTALLER_PATH_DIR_SBIN__:__INSTALLER_PATH_DIR_BIN__ \
    FILEN_CLI_VERSION="$FILEN_CLI_VERSION" FILEN_CLI_URL="$FILEN_CLI_URL" \
    FILEN_CLI_SHA256="$FILEN_CLI_SHA256" FILEN_CLI_ARCHITECTURE="$FILEN_CLI_ARCHITECTURE" \
    FILEN_CLI_PRIV_ENABLE="$FILEN_CLI_PRIV_ENABLE" FILEN_CLI_OFFSEC_ENABLE="$FILEN_CLI_OFFSEC_ENABLE" \
    FILEN_CLI_PRIV_SYNC_MODE="$FILEN_CLI_PRIV_SYNC_MODE" FILEN_CLI_OFFSEC_SYNC_MODE="$FILEN_CLI_OFFSEC_SYNC_MODE" \
    FILEN_CLI_PRIV_REMOTE_PATH="$FILEN_CLI_PRIV_REMOTE_PATH" FILEN_CLI_OFFSEC_REMOTE_PATH="$FILEN_CLI_OFFSEC_REMOTE_PATH" \
    NETWORK_SHARING_ROOT_PATH="$NETWORK_SHARING_ROOT_PATH" \
    NETWORK_SHARING_HOME_BIND_PATH="$NETWORK_SHARING_HOME_BIND_PATH" \
    INSTALLER_ROLE_FAMILY="$INSTALLER_HOST_VARIANT" \
    ACCOUNT_USERNAME="$ACCOUNT_USERNAME" ACCOUNT_HOME="$ACCOUNT_HOME" \
    __INSTALLER_PATH_DIR_USR_BIN__/timeout --signal=TERM --kill-after=5s 420s \
    __INSTALLER_PATH_DIR_USR_BIN__/python3 -I -B "${filen_stage}/install.py" "$filen_stage" \
      "${DIR_INSTALLER_TARGET_DEFAULTS}/desktop"
)
