#!/bin/sh
set -eu

PATH=__INSTALLER_PATH_DIR_USR_LOCAL_SBIN__:__INSTALLER_PATH_DIR_USR_LOCAL_BIN__:__INSTALLER_PATH_DIR_USR_SBIN__:__INSTALLER_PATH_DIR_USR_BIN__:__INSTALLER_PATH_DIR_SBIN__:__INSTALLER_PATH_DIR_BIN__
export PATH
umask 077

CONFIG_FILE=__INSTALLER_PATH_FILE_CRYPTO_STATE_CONFIG__
STATE_DIR=__INSTALLER_PATH_DIR_CRYPTO_STATE__
PENDING_FILE=${STATE_DIR}/tpm2-enroll.pending
COMPLETE_FILE=${STATE_DIR}/tpm2-enroll.complete
LOCK_FILE=${STATE_DIR}/enrollment.lock
POLICY_CHECK=__INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/tpm2-policy-check
TTY_STATE=
SECRET_DIR=
SECRET_VALUE=

fatal() {
  printf 'tpm2-enroll: fatal: %s\n' "$*" >&2
  exit 1
}

info() {
  printf 'tpm2-enroll: %s\n' "$*" >&2
}

crypto_policy_require() {
  crypto_policy_failure=$1
  shift
  if "$POLICY_CHECK" "$@"; then
    return 0
  else
    crypto_status=$?
    [ "$crypto_status" -ne 76 ] || exit 76
    fatal "$crypto_policy_failure"
  fi
}

require_command() {
  command -v "$1" >__INSTALLER_PATH_DIR_DEV__/null 2>&1 || fatal "required command is unavailable: $1"
}

validate_uuid() {
  printf '%s\n' "$2" |
    grep -Eq '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' ||
    fatal "$1 is not a valid LUKS UUID"
}

read_secret() {
  prompt=$1
  printf '%s' "$prompt" >__INSTALLER_PATH_DIR_DEV__/tty
  TTY_STATE=$(stty -g <__INSTALLER_PATH_DIR_DEV__/tty) || fatal "unable to read terminal state"
  stty -echo <__INSTALLER_PATH_DIR_DEV__/tty
  IFS= read -r secret_value <__INSTALLER_PATH_DIR_DEV__/tty || {
    stty "$TTY_STATE" <__INSTALLER_PATH_DIR_DEV__/tty
    TTY_STATE=
    printf '\n' >__INSTALLER_PATH_DIR_DEV__/tty
    fatal "secret input was interrupted"
  }
  stty "$TTY_STATE" <__INSTALLER_PATH_DIR_DEV__/tty
  TTY_STATE=
  printf '\n' >__INSTALLER_PATH_DIR_DEV__/tty
  SECRET_VALUE=$secret_value
}

crypto_device_call() {
  if "$POLICY_CHECK" --device-op "$device" "$@"; then
    return 0
  else
    crypto_status=$?
    case "$crypto_status" in
      2) return 1 ;;
      76) exit 76 ;;
      *) fatal 'descriptor-bound crypto operation failed; native output is private' ;;
    esac
  fi
}

passphrase_works() {
  device=$1
  crypto_device_call test "$2"
}

matching_passphrase_slots() {
  device=$1; key_file=$2
  slots=$(crypto_device_call keyslots) || exit "$?"
  for slot in $slots; do
    if crypto_device_call test-slot "$key_file" "$slot"; then
      printf '%s\n' "$slot"
    fi
  done
}

keyslot_pbkdf() {
  device=$1
  crypto_device_call pbkdf "$2"
}

verify_fallback_pbkdf() {
  device=$1
  fallback_key=$2
  matching_slots=$(matching_passphrase_slots "$device" "$fallback_key")
  [ -n "$matching_slots" ] || fatal "unable to identify the recovery keyslot on $device"

  for slot in $matching_slots; do
    pbkdf=$(keyslot_pbkdf "$device" "$slot")
    [ "$pbkdf" = argon2id ] ||
      fatal "recovery keyslot ${slot} on $device does not use Argon2id"
  done
}

add_fallback_passphrase() {
  device=$1
  current_key=$2
  fallback_key=$3

  if passphrase_works "$device" "$fallback_key"; then
    info "recovery passphrase is already enrolled on $device"
    verify_fallback_pbkdf "$device" "$fallback_key"
    return 0
  fi

  if [ -z "$current_key" ] || ! passphrase_works "$device" "$current_key"; then
    fatal "recovery passphrase is not enrolled and the installer passphrase no longer unlocks $device"
  fi

  crypto_device_call add-recovery "$current_key" "$fallback_key"
  passphrase_works "$device" "$fallback_key" || fatal "recovery passphrase verification failed for $device"
  verify_fallback_pbkdf "$device" "$fallback_key"
}

enroll_tpm2_pin() {
  device=$1
  credential_dir=$2
  fallback_key=$3
  pcrs=$4

  crypto_device_call enroll-tpm "$credential_dir" "$fallback_key"

}

verify_tpm2_pin_unlock() {
  device=$1
  credential_dir=$2
  # This opens no mapping, creates no replacement token and permits no recovery
  # fallback. Compare LUKS metadata before/after the exact final token test.
  if "$POLICY_CHECK" --verify "$device" <"${credential_dir}/cryptenroll.tpm2-pin"; then
    return 0
  else
    crypto_status=$?
    [ "$crypto_status" -ne 76 ] || exit 76
    fatal "read-only TPM2+PIN verification failed for $device"
  fi
}

remove_install_passphrase_slots() {
  device=$1
  install_key=$2
  fallback_key=$3

  [ -n "$install_key" ] || return 0
  if ! passphrase_works "$device" "$install_key"; then
    info "temporary installer passphrase is already absent from $device"
    return 0
  fi

  matching_slots=$(matching_passphrase_slots "$device" "$install_key")

  for slot in $matching_slots; do
    crypto_device_call kill-install "$fallback_key" "$slot"
  done

  if passphrase_works "$device" "$install_key"; then
    fatal "temporary installer passphrase is still active on $device"
  fi
}

cleanup() {
  cleanup_status=$?
  if [ -n "$TTY_STATE" ]; then
    stty "$TTY_STATE" <__INSTALLER_PATH_DIR_DEV__/tty 2>__INSTALLER_PATH_DIR_DEV__/null || true
    TTY_STATE=
  fi
  if [ -n "$SECRET_DIR" ]; then
    if [ "$cleanup_status" -eq 76 ] || [ -e __INSTALLER_PATH_FILE_CRYPTO_MUTATION__ ] || [ -L __INSTALLER_PATH_FILE_CRYPTO_MUTATION__ ]; then
      info "outcome unknown: retained private RAM workspace $SECRET_DIR; run --recover-mutation before retrying"
    else
      rm -rf "$SECRET_DIR"
    fi
  fi
  unset SECRET_VALUE fallback_passphrase fallback_confirm tpm_pin tpm_pin_confirm 2>__INSTALLER_PATH_DIR_DEV__/null || true
}

[ "$(id -u)" -eq 0 ] || fatal "this enrollment helper requires the local administrator"
[ -r "$CONFIG_FILE" ] || fatal "missing crypto configuration: $CONFIG_FILE"
[ -r __INSTALLER_PATH_DIR_DEV__/tty ] || fatal "an interactive terminal is required"
crypto_policy_require "unsafe crypto configuration metadata or installer handoff" --check-config
case "${1:-}" in
  '') [ "$#" -eq 0 ] || fatal "unexpected argument" ;;
  --reenroll|--recover-mutation) [ "$#" -eq 1 ] || fatal "unexpected argument" ;;
  *) fatal "usage: tpm2-enroll.sh [--reenroll|--recover-mutation]" ;;
esac

require_command awk
require_command cmp
require_command cryptsetup
require_command flock
require_command grep
require_command mktemp
require_command mokutil
require_command readlink
require_command stty
require_command systemd-cryptenroll
require_command systemd-creds

# State is root-owned and not writable by the desktop user. Do not create a
# predictable lock beneath a world-writable __INSTALLER_PATH_DIR_RUN_LOCK__ directory.
[ ! -L "$LOCK_FILE" ] || fatal "unsafe enrollment lock"
exec 9>"$LOCK_FILE"
flock -n 9 || fatal "another TPM2 enrollment process is already running"
if [ "${1:-}" = --reenroll ]; then
  crypto_policy_require "cannot start a new enrollment generation" --begin
fi
# Read restricted generated data; no profile or credential is sourced as code.
if crypto_config_data=$("$POLICY_CHECK" --config-data); then :; else
  crypto_status=$?
  [ "$crypto_status" -ne 76 ] || exit 76
  fatal 'cannot read restricted crypto configuration data'
fi
while IFS='=' read -r crypto_name crypto_value; do
  case "$crypto_name" in
    PRIMARY_USER) PRIMARY_USER=$crypto_value ;;
    CRYPTO_LUKS2_ROOT) CRYPTO_LUKS2_ROOT=$crypto_value ;;
    CRYPTO_LUKS2_HOME) CRYPTO_LUKS2_HOME=$crypto_value ;;
    ROOT_LUKS_UUID) ROOT_LUKS_UUID=$crypto_value ;;
    HOME_LUKS_UUID) HOME_LUKS_UUID=$crypto_value ;;
    ROOT_CRYPT_NAME) ROOT_CRYPT_NAME=$crypto_value ;;
    HOME_CRYPT_NAME) HOME_CRYPT_NAME=$crypto_value ;;
    BOOTSTRAP_CREDENTIAL_FILE) BOOTSTRAP_CREDENTIAL_FILE=$crypto_value ;;
    TPM2_FINAL_PCRS) TPM2_FINAL_PCRS=$crypto_value ;;
    *) fatal 'unknown generated crypto data field' ;;
  esac
done <<EOF
$crypto_config_data
EOF
unset crypto_config_data

: "${PRIMARY_USER:?PRIMARY_USER must be configured}"
: "${CRYPTO_LUKS2_ROOT:?root encryption policy must be configured}"
: "${CRYPTO_LUKS2_HOME:?home encryption policy must be configured}"
: "${BOOTSTRAP_CREDENTIAL_FILE:?sealed bootstrap credential path must be configured}"
: "${TPM2_FINAL_PCRS:?TPM2_FINAL_PCRS must be configured}"
[ "$TPM2_FINAL_PCRS" = 7+8+9+14 ] || fatal "TPM2_FINAL_PCRS must be 7+8+9+14"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "$PRIMARY_USER" ]; then
  fatal "TPM2 enrollment must be run by ${PRIMARY_USER}, not ${SUDO_USER}"
fi

crypto_devices=
if [ "$CRYPTO_LUKS2_ROOT" = true ]; then
  validate_uuid ROOT_LUKS_UUID "$ROOT_LUKS_UUID"
  exec 5<"__INSTALLER_PATH_DIR_DEV__/disk/by-uuid/$ROOT_LUKS_UUID"
  root_device="__INSTALLER_PATH_DIR_PROC__/self/fd/5"
  crypto_devices=$root_device
fi
if [ "$CRYPTO_LUKS2_HOME" = true ]; then
  validate_uuid HOME_LUKS_UUID "$HOME_LUKS_UUID"
  exec 6<"__INSTALLER_PATH_DIR_DEV__/disk/by-uuid/$HOME_LUKS_UUID"
  home_device="__INSTALLER_PATH_DIR_PROC__/self/fd/6"
  crypto_devices="${crypto_devices:+$crypto_devices }$home_device"
fi
[ -n "$crypto_devices" ] || fatal 'no encrypted volume is selected'
if [ "${1:-}" = --recover-mutation ]; then
  "$POLICY_CHECK" --recover-mutation
  exit "$?"
fi
"$POLICY_CHECK" --pin-devices || exit "$?"
enrollment_phase=$("$POLICY_CHECK" --phase) || exit "$?"
case "$enrollment_phase" in
  complete) info 'enrollment is complete; use --reenroll after a boot-policy update'; exit 0 ;;
  reboot) info 'enrollment is verified in this boot; reboot and confirm it'; exit 0 ;;
  pending|confirm) ;;
  *) fatal 'invalid enrollment phase' ;;
esac
install_key=

"$POLICY_CHECK" --platform || exit "$?"

if "$POLICY_CHECK" --boot-evidence; then :; else
  crypto_status=$?
  [ "$crypto_status" -ne 76 ] || exit 76
  fatal 'measured-boot evidence is incomplete; enrollment remains pending'
fi
if "$POLICY_CHECK" --initramfs; then :; else
  crypto_status=$?
  [ "$crypto_status" -ne 76 ] || exit 76
  fatal 'initramfs image verification failed; enrollment remains pending'
fi

trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ "$enrollment_phase" = confirm ]; then
  info "Confirming the existing enrollment after reboot; no token or keyslot will be changed"
fi
[ ! -L "$BOOTSTRAP_CREDENTIAL_FILE" ] || fatal 'unsafe sealed bootstrap credential'
if [ "$enrollment_phase" = confirm ] || [ ! -e "$BOOTSTRAP_CREDENTIAL_FILE" ]; then
  read_secret 'Existing recovery passphrase (minimum 20 characters): '
else
  read_secret 'New recovery passphrase (minimum 20 characters): '
fi
fallback_passphrase=$SECRET_VALUE
SECRET_VALUE=
[ "${#fallback_passphrase}" -ge 20 ] || fatal "recovery passphrase must be at least 20 characters"
[ "$fallback_passphrase" != "$PRIMARY_USER" ] || fatal "recovery passphrase must differ from the primary account name"
if printf '%s' "$fallback_passphrase" | LC_ALL=C.UTF-8 grep -q '[[:cntrl:]]'; then
  fatal "recovery passphrase must not contain control characters"
fi
read_secret 'Confirm recovery passphrase: '
fallback_confirm=$SECRET_VALUE
SECRET_VALUE=
[ "$fallback_passphrase" = "$fallback_confirm" ] || fatal "recovery passphrases do not match"

read_secret 'TPM2 PIN (existing when confirming; otherwise new; 6-32 digits): '
tpm_pin=$SECRET_VALUE
SECRET_VALUE=
case "$tpm_pin" in
  *[!0-9]*) fatal "TPM2 PIN must contain digits only" ;;
esac
[ "${#tpm_pin}" -ge 6 ] && [ "${#tpm_pin}" -le 32 ] ||
  fatal "TPM2 PIN must contain 6-32 digits"
read_secret 'Confirm TPM2 PIN: '
tpm_pin_confirm=$SECRET_VALUE
SECRET_VALUE=
[ "$tpm_pin" = "$tpm_pin_confirm" ] || fatal "TPM2 PIN values do not match"

SECRET_DIR=$(mktemp -d __INSTALLER_PATH_DIR_RUN__/tpm2-enroll.XXXXXX) || fatal "unable to create credential directory"
if [ -e "$BOOTSTRAP_CREDENTIAL_FILE" ]; then
  [ -f "$BOOTSTRAP_CREDENTIAL_FILE" ] && [ ! -L "$BOOTSTRAP_CREDENTIAL_FILE" ] || fatal 'unsafe sealed bootstrap credential'
  install_key="${SECRET_DIR}/install-passphrase"
  if "$POLICY_CHECK" --decrypt-bootstrap "$install_key"; then
    :
  else
    crypto_status=$?
    [ "$crypto_status" -ne 76 ] || exit 76
    fatal 'TPM bootstrap credential could not be unsealed; retain it and use the existing recovery key'
  fi
  chmod 0400 "$install_key"
else
  info 'bootstrap credential is absent; recovery requires the existing recovery passphrase'
fi

fallback_key="${SECRET_DIR}/fallback-passphrase"
credential_dir="${SECRET_DIR}/credentials"
install -d -m 0700 "$credential_dir"
printf '%s' "$fallback_passphrase" >"$fallback_key"
printf '%s' "$tpm_pin" >"${credential_dir}/cryptenroll.tpm2-pin"
printf '%s' "$tpm_pin" >"${credential_dir}/cryptenroll.new-tpm2-pin"
chmod 0400 "$fallback_key" "${credential_dir}/cryptenroll.tpm2-pin" "${credential_dir}/cryptenroll.new-tpm2-pin"
if [ -n "$install_key" ] && cmp -s "$install_key" "$fallback_key"; then
  fatal "recovery passphrase must differ from the temporary installer passphrase"
fi

if [ "$enrollment_phase" = pending ]; then
  for device in $crypto_devices; do
    add_fallback_passphrase "$device" "$install_key" "$fallback_key"
  done

  for device in $crypto_devices; do
    enroll_tpm2_pin "$device" "$credential_dir" "$fallback_key" "$TPM2_FINAL_PCRS"
  done
fi

for device in $crypto_devices; do
  verify_tpm2_pin_unlock "$device" "$credential_dir" "$TPM2_FINAL_PCRS"
done

for device in $crypto_devices; do
  if [ "$enrollment_phase" = pending ]; then
    remove_install_passphrase_slots "$device" "$install_key" "$fallback_key"
  fi
  passphrase_works "$device" "$fallback_key" || fatal "recovery passphrase stopped working for $device"
  verify_fallback_pbkdf "$device" "$fallback_key"
done

if [ "$enrollment_phase" = pending ]; then
  rm -f "$BOOTSTRAP_CREDENTIAL_FILE"
  crypto_policy_require "could not durably record the enrollment generation" --record enrolled
  info "TPM2+PIN enrollment verified; release remains pending until confirmation after a reboot"
  info "Reboot and run this helper again with the SAME recovery passphrase and PIN"
else
  crypto_policy_require "post-reboot release confirmation failed" --record complete
  crypto_policy_require "TPM release gate failed" --release-check
  if command -v systemctl >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
    systemctl start --no-block secondboot.service >__INSTALLER_PATH_DIR_DEV__/null 2>&1 ||
      info "warning: could not queue completed bootstrap cleanup"
  fi
  info 'TPM2+PIN enrollment confirmed after reboot for every selected encrypted volume'
fi
info "Keep the recovery passphrase offline; measured boot changes require recovery and --reenroll"
