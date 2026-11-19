#!/bin/sh
set -eu

RUNTIME_DIR=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
BOOTSTRAP_LIB=${INSTALLER_BOOTSTRAP_LIB:-${RUNTIME_DIR}/bootstrap/bootstrap.sh}
if [ ! -s "$BOOTSTRAP_LIB" ]; then
  SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
  BOOTSTRAP_LIB="${SELF_DIR}/../common/bootstrap.sh"
fi
[ -s "$BOOTSTRAP_LIB" ] || {
  dispatch_message=$(printf '%s' "installer bootstrap library is unavailable: ${BOOTSTRAP_LIB}" | tr '\r\n\t' '   ')
  printf '[early-dispatch] fatal: %s\n' "$dispatch_message" >&2
  if [ -c /dev/tty4 ] && [ -w /dev/tty4 ]; then
    printf '[early-dispatch] fatal: %s\n' "$dispatch_message" >/dev/tty4 || :
  fi
  if [ -c /dev/console ] && [ -w /dev/console ]; then
    printf '[early-dispatch] fatal: %s\n' "$dispatch_message" >/dev/console || :
  fi
  if command -v logger >/dev/null 2>&1; then
    logger -t preseed-early-dispatch "fatal: $dispatch_message" 2>/dev/null || :
  fi
  exit 1
}
# shellcheck disable=SC1090,SC1091
. "$BOOTSTRAP_LIB"
bootstrap_source_common_lib "${1:-}"
installer_init_log_file "$(installer_runtime_log_file)" "" "early dispatch" early-dispatch boot
installer_operation_context_repo scripts/early/dispatch.sh 28 early_dispatch
installer_ensure_log_files
trap 'installer_finalize_log "$?"' EXIT

seed_base=$(installer_seed_base "${1:-}")
installer_ensure_context_loaded "$seed_base"
if installer_phase_stage_begin early installer.early; then :; else
  stage_status=$?
  [ "$stage_status" -eq 1 ] && exit 0
  installer_fatal_status "$stage_status" 'cannot claim early phase ownership'
fi
host_profile=$(installer_resolve_host_profile "")
hook_family=${INSTALLER_HOOK_FAMILY:-${INSTALLER_HOST_FAMILY}}
shared_hook_path=$(installer_repo_file_value hooks/installer/d-i/early.sh)
shared_hook_dest="${RUNTIME_DIR}/bootstrap/shared-d-i-early.sh"

installer_fetch_file "$seed_base" "$shared_hook_path" "$shared_hook_dest" 0755


case "$hook_family" in
  btrfs|vm)
    runtime_script_path=$(installer_repo_file_value scripts/runtime/btrfs.sh)
    capture_dualboot_sizes=true
    preload_f2fs=false
    ;;
  f2fs)
    runtime_script_path=$(installer_repo_file_value scripts/runtime/f2fs.sh)
    capture_dualboot_sizes=false
    preload_f2fs=true
    ;;
  *)
    installer_fatal "unsupported shared d-i early storage family: ${hook_family}"
    ;;
esac

INSTALLER_BOOTSTRAP_LIB=$BOOTSTRAP_LIB \
SHARED_D_I_EARLY=$shared_hook_dest \
  /bin/sh -c '. "$SHARED_D_I_EARLY"; family_d_i_early_main "$@"' sh \
  "$seed_base" \
  "$host_profile" \
  "$hook_family" \
  "$runtime_script_path" \
  "$capture_dualboot_sizes" \
  "$preload_f2fs"

installer_phase_stage_finish early installer.early
