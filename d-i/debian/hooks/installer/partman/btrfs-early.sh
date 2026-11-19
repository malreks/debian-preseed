#!/bin/sh
# Shared Btrfs-family partman early hook: finalize runtime partitioning and install the layout hook.
set -eu
LOG=
HOOK_FAMILY=${HOOK_FAMILY:-btrfs}

fatal() {
  installer_fatal "$@"
}

require_command() {
  partman_early_require_command "$1"
}

ensure_partition_tooling() {
  hook_ensure_partition_tooling
}

probe_partition_tools() {
  require_command parted
  require_command sfdisk
}

reinitialize_gpt_disk() {
  partman_early_reinitialize_gpt_disk "$DEV_DISK_BLOCK"
}

RUNTIME_DIR=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
BOOTSTRAP_LIB=${INSTALLER_BOOTSTRAP_LIB:-${RUNTIME_DIR}/bootstrap/bootstrap.sh}
if [ ! -s "$BOOTSTRAP_LIB" ]; then
  SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
  # Bootstrap is the one pre-repo.env fallback; use the canonical selector
  # when it is already available, otherwise retain the fixed relative entrypoint.
  BOOTSTRAP_LIB="${SELF_DIR}/../../../../${DIR_SCRIPTS_COMMON:-scripts/common}/bootstrap.sh"
fi
[ -s "$BOOTSTRAP_LIB" ] || fatal "installer bootstrap library is unavailable: ${BOOTSTRAP_LIB}"
# shellcheck disable=SC1090,SC1091
. "$BOOTSTRAP_LIB"
bootstrap_source_common_lib "${1:-}"
LOG=$(installer_runtime_log_file)
installer_init_log_file "$LOG" "" "${HOOK_FAMILY} partman early hook" partman-early partman_start
installer_operation_context_repo hooks/installer/partman/btrfs-early.sh 42 partman_btrfs_early
trap 'installer_finalize_log "$?"' EXIT
installer_load_context_if_present || true

SEED_BASE=$(installer_seed_base "${1:-}")
installer_persist_seed_source "$SEED_BASE"
HOST_PROFILE=$(installer_resolve_host_profile "${2:-}")

LAYOUT_HOOK="${DIR_INSTALLER_LIB_PARTMAN_FINISH_D}/99-storage-layout"
[ -n "${DIR_INSTALLER_ENV:-}" ] || fatal 'installer environment directory is unavailable'
TMP_ENV_DIR="${DIR_INSTALLER_ENV:-}"
RUNTIME_DIR=$(installer_runtime_dir)
STATE_DIR=$(installer_runtime_state_dir)
CACHE_DIR=$(installer_runtime_cache_dir)
RUNTIME_ENV_FILE="${STATE_DIR}/runtime.env"
RUNTIME_RECIPE_FILE="${CACHE_DIR}/expert_recipe"
RUNTIME_FRAGMENT_FILE="${STATE_DIR}/partman.answers.cfg"
mkdir -p "$TMP_ENV_DIR" "$RUNTIME_DIR"
bootstrap_source_common_support_libs "$SEED_BASE" "$TMP_ENV_DIR" fetch hook
fetch_hook_file "$(installer_repo_file_value hooks/installer/partman/early.sh)" "$TMP_ENV_DIR/partman-early-common.sh"
fetch_hook_file "$(installer_repo_file_value hooks/installer/partman/finish.d/99-storage-layout.sh)" "$TMP_ENV_DIR/partman-layout-common.sh"
# shellcheck disable=SC1090,SC1091
. "$TMP_ENV_DIR/partman-early-common.sh"

fetch_env() {
  fetch_env_file "$1" "$2"
}

fetch_hook() {
  fetch_hook_file "$1" "$2"
}

install_storage_layout_hook() {
  # The finish hook runs later from partman-base in a fresh shell.  Restore
  # the authenticated runtime contracts before writing a hook that can format
  # anything; never discover a missing helper after partition mutation.
  if [ ! -r "$RUNTIME_DIR/bootstrap/di.env" ]; then
    bootstrap_ensure_di_env "$SEED_BASE" || fatal 'cannot stage installer path environment before partman mutation'
  fi
  if [ ! -r "$RUNTIME_DIR/bootstrap/common-lib.sh" ]; then
    bootstrap_source_common_lib "$SEED_BASE" || fatal 'cannot stage installer common library before partman mutation'
  fi
  if [ ! -f "$RUNTIME_DIR/state/context.env" ] ||
     [ -L "$RUNTIME_DIR/state/context.env" ] ||
     [ ! -r "$RUNTIME_DIR/state/context.env" ]; then
    installer_ensure_context_loaded "$SEED_BASE" || fatal 'cannot stage installer class context before partman mutation'
  fi
  layout_hook_tmp_env_dir=$(installer_shell_quote "$TMP_ENV_DIR")
  layout_hook_family=$(installer_shell_quote "$HOOK_FAMILY")

  fetch_hook_file "$(installer_repo_file_value hooks/installer/partman/finish.d/99-storage-layout.sh)" "$TMP_ENV_DIR/partman-layout-common.sh"
  {
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' 'set -eu'
    printf '%s\n' "IFS=\$(printf ' \t\nX'); IFS=\${IFS%X}"
    printf '%s\n' 'umask 022'
    printf '%s\n' 'runtime=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}'
    printf '%s\n' '[ -r "$runtime/bootstrap/di.env" ] || { printf "[partman-layout] ERROR: missing installer path environment %s\n" "$runtime/bootstrap/di.env" >&2; exit 1; }'
    printf '%s\n' '. "$runtime/bootstrap/di.env"'
    printf '%s\n' 'PATH="${DIR_INSTALLER_USR_LOCAL_SBIN}:${DIR_INSTALLER_USR_LOCAL_BIN}:${DIR_INSTALLER_USR_SBIN}:${DIR_INSTALLER_USR_BIN}:${DIR_INSTALLER_SBIN}:${DIR_INSTALLER_BIN}${PATH:+:${PATH}}"'
    printf '%s\n' 'export PATH'
    printf '%s\n' '[ -f "$runtime/state/context.env" ] && [ ! -L "$runtime/state/context.env" ] && [ -r "$runtime/state/context.env" ] || { printf "[partman-layout] ERROR: missing installer context %s\n" "$runtime/state/context.env" >&2; exit 125; }'
    printf '%s\n' '. "$runtime/state/context.env"'
    printf '%s\n' '[ -f "$runtime/bootstrap/common-lib.sh" ] && [ ! -L "$runtime/bootstrap/common-lib.sh" ] && [ -r "$runtime/bootstrap/common-lib.sh" ] || { printf "[partman-layout] ERROR: missing common installer library %s\n" "$runtime/bootstrap/common-lib.sh" >&2; exit 125; }'
    printf '%s\n' '. "$runtime/bootstrap/common-lib.sh"'
    printf '%s\n' '[ -r "${DIR_INSTALLER_ENV}/runtime.env" ] || { printf "[partman-layout] ERROR: missing rendered runtime environment %s\n" "${DIR_INSTALLER_ENV}/runtime.env" >&2; exit 1; }'
    printf '%s\n' '. "${DIR_INSTALLER_ENV}/runtime.env"'
    printf 'TMP_ENV_DIR=%s\n' "$layout_hook_tmp_env_dir"
    printf 'HOOK_FAMILY=%s\n' "$layout_hook_family"
    printf '%s\n' 'LAYOUT_COMMON="${TMP_ENV_DIR}/partman-layout-common.sh"'
    printf '%s\n' '[ -r "$LAYOUT_COMMON" ] || {'
    printf '%s\n' "  printf '[partman-layout] ERROR: missing shared finish helper %s\n' \"\$LAYOUT_COMMON\" >&2"
    printf '%s\n' '  exit 1'
    printf '%s\n' '}'
    printf '%s\n' '# shellcheck disable=SC1090'
    printf '%s\n' '. "$LAYOUT_COMMON"'
    printf '%s\n' 'run_btrfs_storage_layout'
  } >"$LAYOUT_HOOK"
  chmod 0755 "$LAYOUT_HOOK"
}

installer_fetch_host_env "$SEED_BASE" "$HOST_PROFILE" "$TMP_ENV_DIR/host.env" 0600
installer_fetch_account_env "$SEED_BASE" "$TMP_ENV_DIR/account.env" 0600
  fetch_hook "$(installer_repo_file_value scripts/runtime/common.sh)" "$TMP_ENV_DIR/runtime-common.sh"
  fetch_hook "$(installer_repo_file_value scripts/runtime/btrfs.sh)" "$TMP_ENV_DIR/runtime.sh"
  fetch_hook "$(installer_repo_file_value scripts/runtime/account.sh)" "$TMP_ENV_DIR/account.sh"
  fetch_hook "$(installer_repo_file_value scripts/partman/detect-disk.sh)" "$TMP_ENV_DIR/detect-disk.sh"

# shellcheck disable=SC1090,SC1091
installer_load_data_env "$TMP_ENV_DIR/host.env"
RUNTIME_COMMON_LIB="$TMP_ENV_DIR/runtime-common.sh"
export RUNTIME_COMMON_LIB
# shellcheck disable=SC1090,SC1091
. "$TMP_ENV_DIR/runtime.sh"
# shellcheck disable=SC1090,SC1091
. "$TMP_ENV_DIR/account.sh"
# shellcheck disable=SC1090,SC1091
installer_load_data_env "$TMP_ENV_DIR/account.env"
runtime_apply_account_from_credentials
runtime_write_effective_account_env "$TMP_ENV_DIR/account.env"

hook_resolve_install_disk "$TMP_ENV_DIR/detect-disk.sh" "$HOST_PROFILE"

if [ -r "$TMP_ENV_DIR/runtime.env" ]; then
  # shellcheck disable=SC1090,SC1091
  . "$TMP_ENV_DIR/runtime.env"
else
  runtime_apply_layout_from_cmdline
  runtime_capture_dualboot_partition_sizes
  runtime_write_runtime_env "$RUNTIME_ENV_FILE"
  cp "$RUNTIME_ENV_FILE" "${TMP_ENV_DIR}/runtime.env"
  runtime_write_expert_recipe "$RUNTIME_RECIPE_FILE"
  runtime_write_partman_fragment "$RUNTIME_FRAGMENT_FILE" "$RUNTIME_RECIPE_FILE"
fi

if [ -z "${DEV_INSTALL_DISK:-}" ]; then
  fatal "DEV_INSTALL_DISK must be set by the selected host policy env"
fi
DEV_DISK_BLOCK=$DEV_INSTALL_DISK
ensure_partition_tooling
installer_info "target disk: $DEV_DISK_BLOCK"
if [ ! -b "$DEV_DISK_BLOCK" ]; then
  installer_error "disk device not found: $DEV_DISK_BLOCK (check DEV_INSTALL_DISK in the selected host policy env)"
  installer_info "available block devices under /dev:"
  for dev in /dev/*; do
    [ -b "$dev" ] || continue
    printf '%s\n' "$dev"
  done
  fatal "disk device not found: $DEV_DISK_BLOCK"
fi

partman_early_prepare_layout

if runtime_any_crypto_enabled; then
  runtime_install_crypto_skip_erase_hook
fi

install_storage_layout_hook
installer_info "partman layout hook installed"
