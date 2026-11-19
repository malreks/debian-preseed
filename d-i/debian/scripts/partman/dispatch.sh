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
  printf '[partman-dispatch] fatal: %s\n' "$dispatch_message" >&2
  if [ -c /dev/tty4 ] && [ -w /dev/tty4 ]; then
    printf '[partman-dispatch] fatal: %s\n' "$dispatch_message" >/dev/tty4 || :
  fi
  if [ -c /dev/console ] && [ -w /dev/console ]; then
    printf '[partman-dispatch] fatal: %s\n' "$dispatch_message" >/dev/console || :
  fi
  if command -v logger >/dev/null 2>&1; then
    logger -t preseed-partman-dispatch "fatal: $dispatch_message" 2>/dev/null || :
  fi
  exit 1
}
# shellcheck disable=SC1090,SC1091
. "$BOOTSTRAP_LIB"
bootstrap_source_common_lib "${1:-}"
installer_init_log_file "$(installer_runtime_log_file)" "" "partman dispatch" partman-dispatch partman_start
installer_operation_context_repo scripts/partman/dispatch.sh 28 partman_dispatch
trap 'installer_finalize_log "$?"' EXIT

seed_base=$(installer_seed_base "${1:-}")
installer_ensure_context_loaded "$seed_base"
if installer_phase_stage_begin partman installer.partman; then :; else
  stage_status=$?
  [ "$stage_status" -eq 1 ] && exit 0
  installer_fatal_status "$stage_status" 'cannot claim partman phase ownership'
fi
host_profile=$(installer_resolve_host_profile "")
hook_family=${INSTALLER_HOOK_FAMILY:-${INSTALLER_HOST_FAMILY}}
case "$hook_family" in
  btrfs|vm)
    shared_family_hook_path=$(installer_repo_file_value hooks/installer/partman/btrfs-early.sh)
    shared_family_hook_dest="${RUNTIME_DIR}/bootstrap/shared-partman-btrfs-early.sh"
    ;;
  f2fs)
    shared_family_hook_path=$(installer_repo_file_value hooks/installer/partman/f2fs-early.sh)
    shared_family_hook_dest="${RUNTIME_DIR}/bootstrap/shared-f2fs-tools-udeb-early.sh"
    ;;
  *)
    installer_fatal "unsupported partman hook family: ${hook_family}"
    ;;
esac

installer_fetch_file "$seed_base" "$shared_family_hook_path" "$shared_family_hook_dest" 0755


HOOK_FAMILY=$hook_family \
INSTALLER_BOOTSTRAP_LIB=$BOOTSTRAP_LIB \
  "$shared_family_hook_dest" "$seed_base" "$host_profile"

installer_phase_stage_finish partman installer.partman
