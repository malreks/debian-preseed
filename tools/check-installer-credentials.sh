#!/bin/sh
# Check trusted installer credentials without printing any values.
# Usage: sh tools/check-installer-credentials.sh [env-file [cmdline-file]]
# Unexecuted diagnostic source; the isolation guard prohibits execution. The
# preseed credential input has no chmod requirement; private asset checks retain
# their own mode policy. Never run on the development host or with -x.
set +x
set +v
set -eu
umask 077
/usr/bin/python3 -I -B /workspace/repository/tools/isolation.py
if [ "$#" -gt 2 ]; then
  printf 'usage: %s [env-file [cmdline-file]]\n' "${0##*/}" >&2
  exit 2
fi
check_repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# Load only the shared definitions this offline diagnostic needs. It does not
# initialize installer bootstrap or download a payload.
# shellcheck disable=SC1091
. "$check_repo/d-i/debian/scripts/common/credentials.sh"
# shellcheck disable=SC1091
. "$check_repo/d-i/debian/scripts/common/modules/credentials-probes.sh"
INSTALLER_PRESEED_ENV_FILE=${1:-/preseed.env}
INSTALLER_CMDLINE_FILE=${2:-/proc/cmdline}
unset INSTALLER_CMDLINE INSTALLER_CMDLINE_CACHE INSTALLER_CMDLINE_CACHE_READY
if [ ! -r "$INSTALLER_CMDLINE_FILE" ]; then
  printf '[credentials] error: command-line input file is not readable\n' >&2
  exit 2
fi
check_cmdline=$(cat "$INSTALLER_CMDLINE_FILE")

check_cmdline_value() {
  check_lookup_key=$1
  case "$check_lookup_key" in
    netcfg/wireless_wpa|wireless_wpa|wifi_wpa|wifi_wep)
      check_lookup_keys='netcfg/wireless_wpa wireless_wpa wifi_wpa wifi_wep' ;;
    *)
      check_lookup_keys=$check_lookup_key ;;
  esac
  for check_lookup_alias in $check_lookup_keys; do
    for check_arg in $check_cmdline; do
      case "$check_arg" in
        "$check_lookup_alias") check_cmdline_value=; return 0 ;;
        "$check_lookup_alias"=*) check_cmdline_value=${check_arg#*=}; return 0 ;;
      esac
    done
  done
  return 1
}

check_result=0
for check_key in root_password primary_user primary_password primary_gpg_passphrase git_ssh_passphrase shim_signed_passphrase \
  netcfg/wireless_wpa fruux_username fruux_password crowdsec_token tailscale_authkey \
  telegram_chat_id telegram_api_key cf_r2_access_key cf_r2_secret_key obs_username obs_password
do
  check_source=initrd-env
  if preseed_env_cmdline_secret_allowed "$check_key" && check_cmdline_value "$check_key"; then
    check_source=kernel-cmdline
    check_value=$check_cmdline_value
    if [ -n "$check_value" ]; then
      check_state=present
    else
      check_state=explicit-empty
    fi
  elif check_value=$(preseed_env_read_value "$check_key"); then
    if [ -n "$check_value" ]; then
      check_state=present
    else
      check_state=explicit-empty
    fi
  else
    check_status=$?
    if [ "$check_status" -eq 1 ]; then
      check_state=missing-or-empty
    else
      check_state=load-error
      check_result=2
    fi
  fi
  if [ "$check_key" = root_password ]; then
    if [ "$check_state" = present ]; then
      case "$check_value" in
        *[![:print:]]*|*[[:space:]]*) check_state=invalid-format; check_result=1 ;;
      esac
    elif [ "$check_result" -eq 0 ]; then
      check_result=1
    fi
  fi
  unset check_value
  printf '%s: %s (%s)\n' "$check_key" "$check_state" "$check_source"
done
printf 'Only presence and source are shown; optional integration requirements depend on the selected profile.\n'
exit "$check_result"
