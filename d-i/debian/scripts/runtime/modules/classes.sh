#!/bin/sh
# Shared storage runtime module.

runtime_class_selected() {
  runtime_class=$1
  case "$runtime_class" in ''|*[!a-z0-9/-]*|*../*|*/..|*//*|/*) return 1 ;; esac
  if command -v installer_class_selected >/dev/null 2>&1; then
    installer_class_selected "$runtime_class"
    return "$?"
  fi
  runtime_receipt="__INSTALLER_PATH_FILE_INSTALLER_CLASSES__"
  [ -f "$runtime_receipt" ] && [ ! -L "$runtime_receipt" ] || return 1
  awk -F '\t' -v ref="$runtime_class" '$1=="format" {if($2!="2" || ++formats!=1) bad=1} $1=="class" && $2==ref {found=1} END {exit bad || formats!=1 || !found}' "$runtime_receipt"
}

runtime_dualboot_class_selected() {
  case "${INSTALLER_HOST_PROFILE_ENV_NAME:-${HOST_PROFILE:-}}" in
    *-duo|*-trio) return 0 ;;
  esac
  return 1
}
runtime_qemu_class_selected() {
  for ref in role/desktop/medium role/desktop/full role/server/devops; do
    if runtime_class_selected "$ref"; then return 0; fi
  done
  return 1
}
runtime_root_crypto_enabled() { [ "${CRYPTO_LUKS2_ROOT:?root crypto policy required}" = true ]; }
runtime_home_crypto_enabled() { [ "${CRYPTO_LUKS2_HOME:?home crypto policy required}" = true ]; }
runtime_any_crypto_enabled() { runtime_root_crypto_enabled || runtime_home_crypto_enabled; }

runtime_validate_crypto_layout() {
  for crypto_boolean in "${CRYPTO_LUKS2_ROOT:-}" "${CRYPTO_LUKS2_HOME:-}"; do
    case "$crypto_boolean" in true|false) ;; *) runtime_fatal 'LUKS2 profile policy requires explicit booleans' ;; esac
  done
  if [ -n "${INSTALLER_PROFILE_CRYPTO_LUKS2_ROOT:-}" ]; then
    [ "$CRYPTO_LUKS2_ROOT" = "$INSTALLER_PROFILE_CRYPTO_LUKS2_ROOT" ] &&
      [ "$CRYPTO_LUKS2_HOME" = "$INSTALLER_PROFILE_CRYPTO_LUKS2_HOME" ] ||
      runtime_fatal 'crypto profile differs from the frozen installation plan'
  fi
  if runtime_any_crypto_enabled; then
    # Linux EFI and TPM sysfs are kernel interfaces available before partman;
    # do not infer TPM ownership from installed target packages.
    [ -r /sys/class/tpm/tpm0/tpm_version_major ] || runtime_fatal 'TPM2 is unavailable in the installer; refusing encrypted partitioning'
    IFS= read -r crypto_tpm_version </sys/class/tpm/tpm0/tpm_version_major || runtime_fatal 'cannot read TPM version'
    [ "$crypto_tpm_version" = 2 ] || runtime_fatal 'encrypted profiles require TPM2'
    crypto_secureboot=/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c
    [ -r "$crypto_secureboot" ] && command -v od >/dev/null 2>&1 ||
      runtime_fatal 'cannot establish Secure Boot before encrypted partitioning'
    crypto_secureboot_byte=$(od -An -j4 -N1 -tu1 "$crypto_secureboot" | tr -d ' \n')
    [ "$crypto_secureboot_byte" = 1 ] || runtime_fatal 'encrypted profiles require enabled UEFI Secure Boot'
  fi
  if runtime_root_crypto_enabled; then
    [ -n "${DEV_PART_ROOT:-}" ] || runtime_fatal 'encrypted root requires a dedicated root partition'
  fi
  if runtime_home_crypto_enabled; then
    [ -n "${DEV_PART_HOME:-}" ] || runtime_fatal 'encrypted home requires a dedicated home partition'
    case "${DEV_PART_HOME_MB:-}" in
      ''|*[!0-9]*|0) runtime_fatal 'encrypted home requires a non-zero dedicated home partition' ;;
    esac
  fi
}

runtime_bool_is_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
  esac
  return 1
}

runtime_bool_is_false() {
  case "${1:-}" in
    0|false|FALSE|no|NO|off|OFF) return 0 ;;
  esac
  return 1
}

runtime_apply_ssh_from_classes() {
  case "${SSH_SERVER_ENABLE:-}" in
    true|false) ;;
    *) runtime_fatal 'SSH_SERVER_ENABLE must be true or false in the host profile' ;;
  esac
  if [ -n "${INSTALLER_PROFILE_SSH_SERVER_ENABLE:-}" ] &&
     [ "$SSH_SERVER_ENABLE" != "$INSTALLER_PROFILE_SSH_SERVER_ENABLE" ]; then
    runtime_fatal 'SSH server enablement differs from the selected installer profile policy'
  fi
  [ "$SSH_SERVER_ENABLE" = false ] || installer_plan_package_selected openssh-server ||
    runtime_fatal 'enabled SSH server is missing its package in the frozen plan'
  SSH_SERVER_ENABLED=$SSH_SERVER_ENABLE
  runtime_apply_ssh_from_cmdline
}

runtime_apply_ssh_from_cmdline() {
  ssh_profile_port=${SSH_SERVER_PORT:-}
  case "$ssh_profile_port" in
    [0-9][0-9][0-9][0-9][0-9]) ;;
    *) runtime_fatal 'SSH_SERVER_PORT must be a five-digit profile port' ;;
  esac
  [ "$ssh_profile_port" -ge 30000 ] && [ "$ssh_profile_port" -le 40000 ] ||
    runtime_fatal 'SSH_SERVER_PORT must be in 30000..40000'
  if [ -n "${INSTALLER_PROFILE_SSH_SERVER_PORT:-}" ] &&
     [ "$ssh_profile_port" != "$INSTALLER_PROFILE_SSH_SERVER_PORT" ]; then
    runtime_fatal 'SSH server port differs from the selected installer profile policy'
  fi
  if [ "${RUNTIME_SSH_CMDLINE_READY:-0}" = 1 ]; then
    [ "${SSH_PORT:-}" = "$ssh_profile_port" ] || runtime_fatal 'resolved SSH port no longer matches its profile'
    return 0
  fi
  SSH_PORT=$ssh_profile_port
  RUNTIME_SSH_CMDLINE_READY=1
}
