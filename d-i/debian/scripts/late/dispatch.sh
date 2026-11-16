#!/bin/sh
set -eu

RUNTIME_DIR=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
BOOTSTRAP_LIB=${INSTALLER_BOOTSTRAP_LIB:-${RUNTIME_DIR}/bootstrap/bootstrap.sh}
if [ ! -s "$BOOTSTRAP_LIB" ]; then
  SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
  BOOTSTRAP_LIB="${SELF_DIR}/../common/bootstrap.sh"
fi
[ -s "$BOOTSTRAP_LIB" ] || {
  dispatch_message="installer bootstrap library is unavailable: ${BOOTSTRAP_LIB}"
  printf 'fatal: %s\n' "$dispatch_message" >&2
  if [ -c /dev/tty4 ] && [ -w /dev/tty4 ]; then
    printf '[late-dispatch] fatal: %s\n' "$dispatch_message" >/dev/tty4 || :
  fi
  if command -v logger >/dev/null 2>&1; then
    logger -t preseed-late-dispatch "fatal: $dispatch_message" 2>/dev/null || :
  fi
  exit 1
}
# shellcheck disable=SC1090,SC1091
. "$BOOTSTRAP_LIB"
bootstrap_source_common_lib "${1:-}"
installer_init_log_file "$(installer_runtime_log_file)" "" "late dispatch" late-dispatch late_command
installer_operation_context_repo FILE_LATE_DISPATCH 25 late_dispatch
trap 'installer_finalize_log "$?"' EXIT

seed_base=$(installer_seed_base "${1:-}")
installer_ensure_context_loaded "$seed_base"
host_profile=$(installer_resolve_host_profile "")
hook_family=${INSTALLER_HOOK_FAMILY:-${INSTALLER_HOST_FAMILY}}
shared_hook_path=$(installer_repo_file_value FILE_INST_LATE_COMMAND)
shared_hook_dest="${RUNTIME_DIR}/bootstrap/shared-late.sh"
helper_dir="${RUNTIME_DIR}/bootstrap/late-helpers"
shared_module_dir="${RUNTIME_DIR}/bootstrap/late-modules"
shared_modules="core target-assets iocost volatile-storage storage-maintenance mullvad templates network network-sharing grub security dbus-broker podman zram-swap btrfs-family f2fs-family account"
if installer_class_selected optional/cuda-legacy 2>/dev/null; then
  shared_modules="${shared_modules} cuda-legacy"
fi

# Load the validated composite host environment before any late module is
# fetched. Shared modules are sourced directly by the storage-family child
# shell, so their canonical path tokens must be rendered while they are still
# private installer files rather than after a function has already been
# defined with literal placeholder words.
dispatch_host_env="${RUNTIME_DIR}/bootstrap/dispatch-host.env"
installer_fetch_host_env "$seed_base" "$host_profile" "$dispatch_host_env" 0600
# shellcheck disable=SC1090,SC1091
installer_load_data_env "$dispatch_host_env"

render_dispatch_asset() {
  dispatch_asset=$1
  dispatch_asset_mode=$2
  if LC_ALL=C grep -q '__INSTALLER_PATH_' "$dispatch_asset"; then
    # The caller supplies the fixed mode used by installer_fetch_file.  Do
    # not probe metadata with the unavailable d-i `stat` applet.
    dispatch_asset_rendered="${dispatch_asset}.path-rendered"
    installer_apply_scalar_placeholders "$dispatch_asset" "$dispatch_asset_rendered" || return 1
    installer_assert_no_unresolved_path_placeholders "$dispatch_asset_rendered" "$dispatch_asset" || return 1
    chmod "$dispatch_asset_mode" "$dispatch_asset_rendered" || return 1
    mv -f -- "$dispatch_asset_rendered" "$dispatch_asset" || return 1
  else
    dispatch_asset_probe_status=$?
    [ "$dispatch_asset_probe_status" = 1 ] || return 1
  fi
}

late_dispatch_module_source() {
  case "$1" in
    core) late_dispatch_selector=FILE_LATE_CORE ;;
    target-assets) late_dispatch_selector=FILE_LATE_TARGET_ASSETS ;;
    iocost) late_dispatch_selector=FILE_LATE_IOCOST ;;
    volatile-storage) late_dispatch_selector=FILE_LATE_VOLATILE_STORAGE ;;
    storage-maintenance) late_dispatch_selector=FILE_LATE_STORAGE_MAINTENANCE ;;
    mullvad) late_dispatch_selector=FILE_LATE_MULLVAD ;;
    templates) late_dispatch_selector=FILE_LATE_TEMPLATES ;;
    network) late_dispatch_selector=FILE_LATE_NETWORK ;;
    network-sharing) late_dispatch_selector=FILE_LATE_NETWORK_SHARING_SH ;;
    grub) late_dispatch_selector=FILE_LATE_GRUB ;;
    security) late_dispatch_selector=FILE_LATE_SECURITY ;;
    dbus-broker) late_dispatch_selector=FILE_LATE_DBUS_BROKER ;;
    podman) late_dispatch_selector=FILE_LATE_PODMAN ;;
    zram-swap) late_dispatch_selector=FILE_LATE_ZRAM_SWAP ;;
    btrfs-family) late_dispatch_selector=FILE_LATE_BTRFS_FAMILY ;;
    f2fs-family) late_dispatch_selector=FILE_LATE_F2FS_FAMILY ;;
    account) late_dispatch_selector=FILE_LATE_ACCOUNT ;;
    cuda-legacy) late_dispatch_selector=FILE_LATE_CUDA_LEGACY ;;
    *) installer_fatal "unsupported shared late module: ${1:-unset}" ;;
  esac
  installer_repo_file_value "$late_dispatch_selector"
}

installer_fetch_file "$seed_base" "$shared_hook_path" "$shared_hook_dest" 0644
install -d -m 0700 "$shared_module_dir"
for shared_module in $shared_modules; do
  installer_operation_context_repo FILE_LATE_DISPATCH 96 "fetch_shared_module:${shared_module}"
  shared_module_source=$(late_dispatch_module_source "$shared_module") || {
    late_dispatch_status=$?
    installer_fatal_status "$late_dispatch_status" \
      "late-dispatch shared module selector resolution failed: module=${shared_module}"
  }
  installer_fetch_file \
    "$seed_base" \
    "$shared_module_source" \
    "${shared_module_dir}/${shared_module}.sh" \
    0644
  render_dispatch_asset "${shared_module_dir}/${shared_module}.sh" 0644
done
install -d -m 0700 "$helper_dir"
dispatch_storage_foundation() {
case "$hook_family" in
  btrfs|vm)
    installer_operation_context_repo FILE_LATE_DISPATCH 113 "run_btrfs_family_late_command:${hook_family}"
    if INSTALLER_BOOTSTRAP_LIB=$BOOTSTRAP_LIB \
       INSTALLER_LATE_MODULE_DIR=$shared_module_dir \
       SHARED_LATE_COMMAND=$shared_hook_dest \
         /bin/sh -eu -c '. "$SHARED_LATE_COMMAND"; run_btrfs_family_late_command "$@"' sh \
         "$hook_family" "$seed_base" "$host_profile"
    then
      :
    else
      late_dispatch_status=$?
      installer_fatal_status "$late_dispatch_status" \
        "Btrfs-family late command failed: family=${hook_family} profile=${host_profile:-unset}"
    fi
    ;;
  f2fs)
    installer_operation_context_repo FILE_LATE_DISPATCH 128 run_f2fs_family_late_command
    if INSTALLER_BOOTSTRAP_LIB=$BOOTSTRAP_LIB \
       INSTALLER_LATE_MODULE_DIR=$shared_module_dir \
       SHARED_LATE_COMMAND=$shared_hook_dest \
         /bin/sh -eu -c '. "$SHARED_LATE_COMMAND"; run_f2fs_family_late_command "$@"' sh \
         "$seed_base" "$host_profile"
    then
      :
    else
      late_dispatch_status=$?
      installer_fatal_status "$late_dispatch_status" \
        "F2FS-family late command failed: profile=${host_profile:-unset}"
    fi
    ;;
  *)
    installer_fatal "unsupported shared late storage family: ${hook_family}"
    ;;
esac
}

run_helper_script() {
  helper_path=$1
  helper_dest=$2
  shift 2

  installer_fetch_file "$seed_base" "$helper_path" "$helper_dest" 0755
  render_dispatch_asset "$helper_dest" 0755
  installer_operation_context_repo FILE_LATE_DISPATCH 155 "late_helper:${helper_path}"
  "$helper_dest" "$@" </dev/null
}

# Every late provider is selected, ordered and deduplicated by the frozen plan.
installer_assert_class_plan
installer_publish_class_receipt
# Every provider, including CrowdSec and server Whisper, needs the resolved
# identity independently of the optional desktop storage stage's execution.
INSTALLER_LATE_ACCOUNT_ENV=${INSTALLER_LATE_ACCOUNT_ENV:-${DIR_INSTALLER_LATE_ENV}/account.env}
export INSTALLER_LATE_ACCOUNT_ENV
installer_operation_context_repo FILE_LATE_DISPATCH 166 prepare_late_account_env
installer_prepare_late_account_env "$seed_base" "$INSTALLER_LATE_ACCOUNT_ENV"
bootstrap_source_common_support_libs "$seed_base" "${DIR_INSTALLER_LATE_ENV}/account-provisioning" target
installer_stage_account_creation
plan_stages="${RUNTIME_DIR}/state/late-stages.tsv"
awk -F '\t' '$1=="stage" {split($2, fields, "|"); if(fields[2]=="late") print $2}' \
  "$(installer_class_plan_path)" >"$plan_stages"
while IFS='|' read -r stage_id stage_phase stage_selector || [ -n "$stage_id" ]; do
  case "$stage_id" in ''|*[!a-z0-9.-]*) installer_fatal 'invalid stage ID' ;; esac
  if installer_phase_stage_begin "$stage_phase" "$stage_id"; then
    :
  else
    stage_status=$?
    [ "$stage_status" = 1 ] && continue
    installer_fatal_status "$stage_status" 'cannot claim late phase stage ownership'
  fi
  INSTALLER_LOG_STAGE=late_command
  INSTALLER_LOG_TAG=$stage_id
  export INSTALLER_LOG_STAGE INSTALLER_LOG_TAG
  installer_info "starting selected stage ${stage_id}"
  case "$stage_id:$INSTALLER_HOST_VARIANT" in
    desktop.storage:desktop) dispatch_storage_foundation ;;
    *)
      stage_source=$(installer_repo_file_value "$stage_selector")
      stage_destination="${helper_dir}/${stage_id}.sh"
      case "$stage_id" in
        desktop.session)
          installer_fetch_file "$seed_base" "$stage_source" "$stage_destination" 0755
          render_dispatch_asset "$stage_destination" 0755
          INSTALLER_LATE_MODULE_DIR=$shared_module_dir "$stage_destination" "$seed_base" "$host_profile"
          ;;
        *) run_helper_script "$stage_source" "$stage_destination" "$TARGET_ROOT" ;;
      esac
      ;;
  esac
  installer_phase_stage_finish "$stage_phase" "$stage_id"
  installer_info "completed selected stage ${stage_id}"
done <"$plan_stages"

# All selected stages have consumed their private rendered payload inputs.
# Keep them on failure for diagnosis; no installed application consumes them.
if [ -d "${TARGET_ROOT}${DIR_INSTALLER_TARGET_DEFAULTS}" ]; then
  bootstrap_source_common_support_libs "$seed_base" "${DIR_INSTALLER_LATE_ENV}/defaults-cleanup" target
  installer_run_target_setup FILE_COMMON_PRIMARY_DEFAULTS 'remove private primary-account payload staging' \
    cleanup "$DIR_INSTALLER_TARGET_DEFAULTS"
fi
