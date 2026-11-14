#!/bin/sh

# Shared runtime helpers for storage-family installer scripts.
# This file is sourced before scripts/runtime/{btrfs,f2fs}.sh.

runtime_fatal() {
  if command -v installer_fatal >/dev/null 2>&1; then
    installer_fatal "$@"
  fi
  echo "fatal: $*" >&2
  exit 1
}

runtime_cmdline_key_is_secret() {
  if command -v preseed_env_cmdline_secret_forbidden >/dev/null 2>&1; then
    preseed_env_cmdline_secret_forbidden "$1"
    return "$?"
  fi
  if command -v preseed_env_variable_name >/dev/null 2>&1 &&
     preseed_env_variable_name "$1" >/dev/null 2>&1; then
    return 1
  fi
  case "${1:-}" in
    wifi_wep|netcfg/wireless_wpa|wireless_wpa|wifi_wpa|password|passphrase|*[._/-]password*|*[._/-]passphrase*)
      return 0 ;;
    token|secret|psk|key|credential|*[._/-]token*|*[._/-]secret*|*[._/-]psk*|*[._/-]key*|*[._/-]credential*|*authkey*)
      return 0 ;;
  esac
  return 1
}

# Compatibility name retained for callers; unknown secret-looking keys are
# silently filtered so they cannot abort installation.
runtime_cmdline_reject_credential_args() (
  set -f
  IFS=' '
  runtime_cmdline_filtered=
  for runtime_cmdline_arg in $1; do
    runtime_cmdline_key=${runtime_cmdline_arg%%=*}
    if runtime_cmdline_key_is_secret "$runtime_cmdline_key"; then
      continue
    fi
    runtime_cmdline_filtered="${runtime_cmdline_filtered:+$runtime_cmdline_filtered }$runtime_cmdline_arg"
  done
  printf '%s\n' "$runtime_cmdline_filtered"
)

runtime_cmdline() {
  if [ -n "${INSTALLER_CMDLINE:-}" ]; then
    runtime_cmdline_reject_credential_args "$INSTALLER_CMDLINE"
    return 0
  fi

  if [ "${RUNTIME_CMDLINE_CACHE_READY:-0}" -eq 1 ]; then
    runtime_cmdline_reject_credential_args "${RUNTIME_CMDLINE_CACHE:-}"
    return 0
  fi

  if [ -n "${INSTALLER_CMDLINE_FILE:-}" ] && [ -r "${INSTALLER_CMDLINE_FILE}" ]; then
    RUNTIME_CMDLINE_CACHE=$(cat "${INSTALLER_CMDLINE_FILE}" 2>/dev/null || true)
  elif [ -r /proc/cmdline ]; then
    RUNTIME_CMDLINE_CACHE=$(cat /proc/cmdline 2>/dev/null || true)
  else
    RUNTIME_CMDLINE_CACHE=
  fi

  RUNTIME_CMDLINE_CACHE_READY=1
  runtime_cmdline_reject_credential_args "$RUNTIME_CMDLINE_CACHE"
}


runtime_preseed_env_value() (
  preseed_env_read_value "$@"
)

runtime_cmdline_value() (
  set +x
  set +v
  # The first exact parameter wins, including an explicitly empty parameter.
  # Passwords are literal data, not pathname patterns or shell expressions.
  set -f
  IFS=' 	
'
  runtime_cmdline_key=$1
  runtime_cmdline_args=$(runtime_cmdline) || return "$?"
  for runtime_cmdline_arg in $runtime_cmdline_args; do
    case "$runtime_cmdline_arg" in
      "$runtime_cmdline_key")
        printf '\n'
        return 0
        ;;
      "$runtime_cmdline_key"=*)
        printf '%s\n' "${runtime_cmdline_arg#*=}"
        return 0
        ;;
    esac
  done

  runtime_preseed_env_value "$runtime_cmdline_key"
)
