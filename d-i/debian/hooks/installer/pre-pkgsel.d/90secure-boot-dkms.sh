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
installer_operation_context_repo FILE_INST_PREPKG_90SECURE_BOOT_DKMS 36 secure_boot_prepkgsel
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

render_pre_pkgsel_asset() {
  prepkgsel_asset=$1
  if LC_ALL=C grep -q '__INSTALLER_PATH_' "$prepkgsel_asset"; then
    # fetch_hook_file installs pre-pkgsel helpers with this fixed mode.  The
    # d-i BusyBox image deliberately has no `stat` applet, so preserve the
    # contract directly instead of probing metadata with an unavailable tool.
    prepkgsel_mode=755
    prepkgsel_rendered="${prepkgsel_asset}.path-rendered"
    installer_apply_scalar_placeholders "$prepkgsel_asset" "$prepkgsel_rendered" || return 1
    installer_assert_no_unresolved_path_placeholders "$prepkgsel_rendered" "$prepkgsel_asset" || return 1
    chmod "$prepkgsel_mode" "$prepkgsel_rendered" || return 1
    mv -f -- "$prepkgsel_rendered" "$prepkgsel_asset" || return 1
  else
    prepkgsel_probe_status=$?
    [ "$prepkgsel_probe_status" = 1 ] || return 1
  fi
}

fetch_hook() {
  fetch_hook_file "$1" "$2"
  render_pre_pkgsel_asset "$2"
}

fetch_hook "$(installer_repo_file_value FILE_LATE_CORE)" "$TMP_ENV_DIR/late-core.sh"
fetch_hook "$(installer_repo_file_value FILE_LATE_TARGET_ASSETS)" "$TMP_ENV_DIR/late-target-assets.sh"
fetch_hook "$(installer_repo_file_value FILE_LATE_TEMPLATES)" "$TMP_ENV_DIR/late-templates.sh"
fetch_hook "$(installer_repo_file_value FILE_LATE_VOLATILE_STORAGE)" "$TMP_ENV_DIR/late-volatile-storage.sh"
fetch_hook "$(installer_repo_file_value FILE_LATE_STORAGE_MAINTENANCE)" "$TMP_ENV_DIR/late-storage-maintenance.sh"
fetch_hook "$(installer_repo_file_value FILE_LATE_GRUB)" "$TMP_ENV_DIR/late-grub.sh"
fetch_hook "$(installer_repo_file_value FILE_RUNTIME_COMMON)" "$TMP_ENV_DIR/runtime-common.sh"
fetch_hook "$(installer_repo_file_value FILE_RUNTIME_ACCOUNT)" "$TMP_ENV_DIR/account-runtime.sh"

case "$HOOK_FAMILY" in
  btrfs|vm)
    PREPKGSEL_RUNTIME_SCRIPT=$(installer_repo_file_value FILE_RUNTIME_BTRFS)
    PREPKGSEL_CAPTURE_DUALBOOT=true
    ;;
  f2fs)
    PREPKGSEL_RUNTIME_SCRIPT=$(installer_repo_file_value FILE_RUNTIME_F2FS)
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
