#!/bin/sh
set -eu

RUNTIME_DIR=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
BOOTSTRAP_LIB=${INSTALLER_BOOTSTRAP_LIB:-${RUNTIME_DIR}/bootstrap/bootstrap.sh}
TMP_ENV_DIR=
LOG=

prepkgsel_fatal() {
  prepkgsel_message=$(printf '%s' "$*" | tr '\r\n\t' '   ')
  if command -v installer_error >/dev/null 2>&1; then
    installer_error "secure boot pre-pkgsel: ${prepkgsel_message}"
  else
    printf '[pre-pkgsel] fatal: %s\n' "$prepkgsel_message" >&2
    if [ -c /dev/tty4 ] && [ -w /dev/tty4 ]; then
      printf '[pre-pkgsel] fatal: %s\n' "$prepkgsel_message" >/dev/tty4 || :
    fi
    if command -v logger >/dev/null 2>&1; then
      logger -t preseed-secure-boot "fatal: $prepkgsel_message" 2>/dev/null || :
    fi
  fi
  exit 1
}

[ -s "$BOOTSTRAP_LIB" ] || prepkgsel_fatal "installer bootstrap library is unavailable: ${BOOTSTRAP_LIB}"
# shellcheck disable=SC1090,SC1091
. "$BOOTSTRAP_LIB"
bootstrap_source_common_lib ""
TMP_ENV_DIR=${DIR_INSTALLER_PRE_PKGSEL_ENV}

LOG="$(installer_runtime_log_file)"
INSTALLER_DEBUG_LOGS=1
INSTALLER_LOG_LEVEL=debug
export INSTALLER_DEBUG_LOGS INSTALLER_LOG_LEVEL
installer_init_log_file "$LOG" "" "secure boot pre-pkgsel" secure-boot package_install
installer_operation_context_repo hooks/installer/pre-pkgsel.d/90secure-boot-dkms.sh 36 secure_boot_prepkgsel
trap 'installer_finalize_log "$?"' 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

SEED_BASE=$(installer_seed_base "")
installer_persist_seed_source "$SEED_BASE"
installer_ensure_context_loaded "$SEED_BASE"
HOST_PROFILE=$(installer_resolve_host_profile "")
HOOK_FAMILY=${INSTALLER_HOOK_FAMILY:-${INSTALLER_HOST_FAMILY:-}}
[ -n "$HOOK_FAMILY" ] || prepkgsel_fatal "installer hook family is unavailable"

install -d -m 0700 "$TMP_ENV_DIR"
bootstrap_source_common_support_libs "$SEED_BASE" "$TMP_ENV_DIR" fetch hook target || {
  prepkgsel_fatal "failed to source shared installer helper libraries"
}

PREPKGSEL_HOST_ENV="${TMP_ENV_DIR}/host.env"
installer_fetch_host_env "$SEED_BASE" "$HOST_PROFILE" "$PREPKGSEL_HOST_ENV" 0600 ||
  prepkgsel_fatal "failed to fetch the validated host environment"
# shellcheck disable=SC1090,SC1091
installer_load_data_env "$PREPKGSEL_HOST_ENV"

fetch_hook() {
  # The first base hook rendered these authenticated helpers as one batch.
  fetch_hook_file "$1" "$2"
}

fetch_hook "$(installer_repo_file_value scripts/late/core.sh)" "$TMP_ENV_DIR/late-core.sh"
fetch_hook "$(installer_repo_file_value scripts/late/target-assets.sh)" "$TMP_ENV_DIR/late-target-assets.sh"
fetch_hook "$(installer_repo_file_value scripts/late/templates.sh)" "$TMP_ENV_DIR/late-templates.sh"
fetch_hook "$(installer_repo_file_value scripts/late/volatile-storage.sh)" "$TMP_ENV_DIR/late-volatile-storage.sh"
fetch_hook "$(installer_repo_file_value scripts/late/storage-maintenance.sh)" "$TMP_ENV_DIR/late-storage-maintenance.sh"
fetch_hook "$(installer_repo_file_value scripts/late/grub.sh)" "$TMP_ENV_DIR/late-grub.sh"
fetch_hook "$(installer_repo_file_value scripts/runtime/common.sh)" "$TMP_ENV_DIR/runtime-common.sh"
fetch_hook "$(installer_repo_file_value scripts/runtime/account.sh)" "$TMP_ENV_DIR/account-runtime.sh"

case "$HOOK_FAMILY" in
  btrfs|vm)
    PREPKGSEL_RUNTIME_SCRIPT=$(installer_repo_file_value scripts/runtime/btrfs.sh)
    PREPKGSEL_CAPTURE_DUALBOOT=true
    ;;
  f2fs)
    PREPKGSEL_RUNTIME_SCRIPT=$(installer_repo_file_value scripts/runtime/f2fs.sh)
    PREPKGSEL_CAPTURE_DUALBOOT=false
    ;;
  *)
    prepkgsel_fatal "unsupported installer storage family: ${HOOK_FAMILY}"
    ;;
esac
fetch_hook "$PREPKGSEL_RUNTIME_SCRIPT" "$TMP_ENV_DIR/runtime.sh"

# shellcheck disable=SC1090,SC1091
. "$TMP_ENV_DIR/late-core.sh"
# shellcheck disable=SC1090,SC1091
. "$TMP_ENV_DIR/late-target-assets.sh"
# shellcheck disable=SC1090,SC1091
. "$TMP_ENV_DIR/late-templates.sh"
# shellcheck disable=SC1090,SC1091
. "$TMP_ENV_DIR/late-volatile-storage.sh"
# shellcheck disable=SC1090,SC1091
. "$TMP_ENV_DIR/late-storage-maintenance.sh"
# shellcheck disable=SC1090,SC1091
. "$TMP_ENV_DIR/late-grub.sh"

LATE_COMMAND_HOST_ENV="${TMP_ENV_DIR}/host.env"
LATE_COMMAND_ACCOUNT_ENV="${TMP_ENV_DIR}/account.env"

late_command_require_class_policy_env
late_command_load_runtime_env "$PREPKGSEL_CAPTURE_DUALBOOT"
late_command_load_host_env

# Prepare DKMS material before pkgsel. The final late stage queues the MOK
# reset after all package hooks, using the primary account username.
stage_target_secure_boot_runtime_assets
run_installer_secure_boot_install_tool prepare-dkms
