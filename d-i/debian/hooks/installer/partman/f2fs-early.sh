#!/bin/sh
# Shared F2FS-family partman early hook.
set -eu

LOG=
HOOK_FAMILY=${HOOK_FAMILY:-f2fs}

fatal() {
  installer_fatal "$@"
}

ensure_partition_tooling() {
  hook_ensure_partition_tooling
}

ensure_f2fs_tooling() {
  hook_ensure_installer_udeb f2fs-tools-udeb
  hook_ensure_installer_command mkfs.f2fs f2fs-tools-udeb
  hook_ensure_installer_command mkfs.ext4 e2fsprogs-udeb
  hook_ensure_installer_command mkfs.fat dosfstools-udeb
}

f2fs_kernel_is_available() {
  [ -r /proc/filesystems ] && grep -qw f2fs /proc/filesystems
}

ensure_f2fs_kernel_support() {
  case "$(udpkg --print-os)" in
    linux) ;;
    *) fatal "F2FS installer support requires a Linux Debian Installer runtime" ;;
  esac

  mkdir -p ${DIR_INSTALLER_VAR_LIB_PARTMAN}
  rm -f ${DIR_INSTALLER_VAR_LIB_PARTMAN}/f2fs

  if f2fs_kernel_is_available; then
    : >${DIR_INSTALLER_VAR_LIB_PARTMAN}/f2fs
    installer_info "F2FS kernel support is built into the Debian Installer kernel"
    return 0
  fi

  if command -v modprobe >/dev/null 2>&1 &&
     modprobe f2fs >/dev/null 2>&1 &&
     f2fs_kernel_is_available; then
    : >${DIR_INSTALLER_VAR_LIB_PARTMAN}/f2fs
    installer_info "loaded preinstalled Debian Installer F2FS kernel module"
    return 0
  fi

  kernel_release=$(uname -r 2>/dev/null || true)
  module_udeb_installed=false
  if [ -n "$kernel_release" ]; then
    module_udeb="f2fs-modules-${kernel_release}-di"
    installer_info "installing Debian Installer F2FS kernel udeb ${module_udeb}"
    if hook_anna_install_optional "$module_udeb"; then
      module_udeb_installed=true
    fi
  fi

  installer_info "installing Debian Installer virtual F2FS kernel udeb f2fs-modules"
  if hook_anna_install_optional f2fs-modules; then
    module_udeb_installed=true
  fi

  [ "$module_udeb_installed" = true ] || \
    fatal "unable to install Debian Installer F2FS kernel modules for ${kernel_release:-unknown kernel}"
  command -v depmod >/dev/null 2>&1 || \
    fatal "depmod is unavailable after installing Debian Installer F2FS kernel modules"
  depmod -a >/dev/null 2>&1 || \
    fatal "depmod failed after installing Debian Installer F2FS kernel modules"
  command -v modprobe >/dev/null 2>&1 || \
    fatal "modprobe is unavailable after installing Debian Installer F2FS kernel modules"
  modprobe f2fs >/dev/null 2>&1 || \
    fatal "unable to load the Debian Installer F2FS kernel module"
  f2fs_kernel_is_available || \
    fatal "Debian Installer still does not advertise F2FS after loading its kernel module"

  : >${DIR_INSTALLER_VAR_LIB_PARTMAN}/f2fs
  installer_info "loaded Debian Installer F2FS kernel support for ${kernel_release:-current kernel}"
}

ensure_partman_state_dir() {
  mkdir -p ${DIR_INSTALLER_VAR_LIB_PARTMAN}
  : >${DIR_INSTALLER_VAR_LIB_PARTMAN}/lvm
  : >${DIR_INSTALLER_VAR_LIB_PARTMAN}/md
}

append_unique_line() {
  target_file=$1
  target_line=$2

  if [ -f "$target_file" ] && grep -qxF "$target_line" "$target_file"; then
    return 0
  fi

  printf '%s\n' "$target_line" >>"$target_file"
}

install_partman_f2fs_backend() {
  backend_tmp_dir="${TMP_ENV_DIR}/partman-f2fs-backend"

  install -d -m 0755 \
    ${DIR_INSTALLER_LIB_PARTMAN}/valid_filesystems \
    ${DIR_INSTALLER_LIB_PARTMAN}/mountoptions \
    ${DIR_INSTALLER_LIB_PARTMAN}/mount.d \
    ${DIR_INSTALLER_LIB_PARTMAN}/fstab.d \
    ${DIR_INSTALLER_LIB_PARTMAN}/init.d \
    ${DIR_INSTALLER_LIB_PARTMAN}/check.d \
    ${DIR_INSTALLER_LIB_PARTMAN}/commit.d \
    "$backend_tmp_dir"

  fetch_hook "$(installer_repo_file_value FILE_INST_PARTMAN_F2FS_BACKEND_VALID_FILESYSTEMS_F2FS)" "$backend_tmp_dir/valid_filesystems.f2fs"
  fetch_hook "$(installer_repo_file_value FILE_INST_PARTMAN_F2FS_BACKEND_MOUNTOPTIONS_F2FS)" "$backend_tmp_dir/mountoptions.f2fs"
  fetch_hook "$(installer_repo_file_value FILE_INST_PARTMAN_F2FS_BACKEND_MOUNT_D_F2FS)" "$backend_tmp_dir/mount.d.f2fs"
  fetch_hook "$(installer_repo_file_value FILE_INST_PARTMAN_F2FS_BACKEND_FSTAB_D_F2FS)" "$backend_tmp_dir/fstab.d.f2fs"
  fetch_hook "$(installer_repo_file_value FILE_INST_PARTMAN_F2FS_BACKEND_INIT_D_KERNELMODULES_F2FS)" "$backend_tmp_dir/init.d.kernelmodules_f2fs"
  fetch_hook "$(installer_repo_file_value FILE_INST_PARTMAN_F2FS_BACKEND_CHECK_D_NOMOUNTPOINT_F2FS)" "$backend_tmp_dir/check.d.nomountpoint_f2fs"
  fetch_hook "$(installer_repo_file_value FILE_INST_PARTMAN_F2FS_BACKEND_COMMIT_D_FORMAT_F2FS)" "$backend_tmp_dir/commit.d.format_f2fs"

  install -m 0755 "$backend_tmp_dir/valid_filesystems.f2fs" ${DIR_INSTALLER_LIB_PARTMAN}/valid_filesystems/f2fs
  install -m 0644 "$backend_tmp_dir/mountoptions.f2fs" ${DIR_INSTALLER_LIB_PARTMAN}/mountoptions/f2fs
  install -m 0755 "$backend_tmp_dir/mount.d.f2fs" ${DIR_INSTALLER_LIB_PARTMAN}/mount.d/f2fs
  install -m 0755 "$backend_tmp_dir/fstab.d.f2fs" ${DIR_INSTALLER_LIB_PARTMAN}/fstab.d/f2fs
  install -m 0755 "$backend_tmp_dir/init.d.kernelmodules_f2fs" ${DIR_INSTALLER_LIB_PARTMAN}/init.d/kernelmodules_f2fs
  install -m 0755 "$backend_tmp_dir/check.d.nomountpoint_f2fs" ${DIR_INSTALLER_LIB_PARTMAN}/check.d/nomountpoint_f2fs
  install -m 0755 "$backend_tmp_dir/commit.d.format_f2fs" ${DIR_INSTALLER_LIB_PARTMAN}/commit.d/format_f2fs

  append_unique_line ${DIR_INSTALLER_LIB_PARTMAN}/valid_filesystems/_numbers '07 f2fs'
  append_unique_line ${DIR_INSTALLER_LIB_PARTMAN}/mount.d/_numbers '71 f2fs'
  append_unique_line ${DIR_INSTALLER_LIB_PARTMAN}/init.d/_numbers '03 kernelmodules_f2fs'
  append_unique_line ${DIR_INSTALLER_LIB_PARTMAN}/check.d/_numbers '09 nomountpoint_f2fs'
  append_unique_line ${DIR_INSTALLER_LIB_PARTMAN}/commit.d/_numbers '50 format_f2fs'

  installer_info "installed partman f2fs backend hooks"
}

device_has_any_type() {
  dev=$1
  shift

  [ -b "$dev" ] || return 1
  actual_type=$(runtime_probe_filesystem_type "$dev" 2>/dev/null || true)
  [ -n "$actual_type" ] || return 1

  for expected in "$@"; do
    [ "$actual_type" = "$expected" ] && return 0
  done

  return 1
}

validate_gpt_esp_type() {
  dev=$1
  esp_guid=$(runtime_gpt_esp_type_guid)

  [ -b "$dev" ] || fatal "existing EFI partition is missing: ${dev}"
  part_type=$(runtime_probe_gpt_part_type "$dev" 2>/dev/null || true)
  if [ -z "$part_type" ]; then
    installer_warn "unable to determine GPT partition type for ${dev}; continuing after vfat ESP filesystem validation"
    return 0
  fi

  runtime_gpt_part_type_is_esp "$part_type" || \
    fatal "expected ${dev} to have GPT ESP type ${esp_guid}, detected '${part_type}'"
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
installer_operation_context_repo FILE_INST_PARTMAN_F2FS_EARLY 407 partman_f2fs_early
trap 'installer_finalize_log "$?"' EXIT
installer_load_context_if_present || true

SEED_BASE=$(installer_seed_base "${1:-}")
installer_persist_seed_source "$SEED_BASE"
HOST_PROFILE=$(installer_resolve_host_profile "${2:-}")

LAYOUT_HOOK=${DIR_INSTALLER_LIB_PARTMAN_FINISH_D}/99-storage-layout
[ -n "${DIR_INSTALLER_ENV:-}" ] || fatal 'installer environment directory is unavailable'
TMP_ENV_DIR=${DIR_INSTALLER_ENV:-}
RUNTIME_DIR=$(installer_runtime_dir)
STATE_DIR=$(installer_runtime_state_dir)
CACHE_DIR=$(installer_runtime_cache_dir)
RUNTIME_ENV_FILE="${STATE_DIR}/runtime.env"
RUNTIME_RECIPE_FILE="${CACHE_DIR}/expert_recipe"
RUNTIME_FRAGMENT_FILE="${STATE_DIR}/partman.answers.cfg"
install -d -m 0700 "$TMP_ENV_DIR" "$RUNTIME_DIR"
bootstrap_source_common_support_libs "$SEED_BASE" "$TMP_ENV_DIR" fetch hook
fetch_hook_file "$(installer_repo_file_value FILE_INST_PARTMAN_EARLY)" "$TMP_ENV_DIR/partman-early-common.sh"
fetch_hook_file "$(installer_repo_file_value FILE_INST_PARTMAN_FINISH_D_99_STORAGE_LAYOUT)" "$TMP_ENV_DIR/partman-layout-common.sh"
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

  fetch_hook_file "$(installer_repo_file_value FILE_INST_PARTMAN_FINISH_D_99_STORAGE_LAYOUT)" "$TMP_ENV_DIR/partman-layout-common.sh"
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
    printf '%s\n' 'run_f2fs_storage_layout'
  } >"$LAYOUT_HOOK"
  chmod 0755 "$LAYOUT_HOOK"
}

install_crypto_skip_erase_hook() {
  skip_hook=${DIR_INSTALLER_LIB_PARTMAN}/init.d/51crypto-skip-erase

  cat >"$skip_hook" <<'EOF'
#!/bin/sh
set -eu

runtime=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
[ -r "$runtime/bootstrap/di.env" ] || exit 1
# shellcheck disable=SC1090
. "$runtime/bootstrap/di.env"

[ -d "${DIR_INSTALLER_VAR_LIB_PARTMAN}/devices" ] || exit 0

find "${DIR_INSTALLER_VAR_LIB_PARTMAN}/devices" -mindepth 2 -maxdepth 2 -type d | while IFS= read -r part_dir; do
  [ -r "$part_dir/method" ] || continue
  method=$(cat "$part_dir/method" 2>/dev/null || true)
  [ "$method" = crypto ] || continue
  : >"$part_dir/skip_erase"
done
EOF
  chmod 0755 "$skip_hook"
  installer_info "installed partman crypto skip-erase hook"
}

installer_fetch_host_env "$SEED_BASE" "$HOST_PROFILE" "$TMP_ENV_DIR/host.env" 0600
installer_fetch_account_env "$SEED_BASE" "$TMP_ENV_DIR/account.env" 0600
  fetch_hook "$(installer_repo_file_value FILE_RUNTIME_COMMON)" "$TMP_ENV_DIR/runtime-common.sh"
  fetch_hook "$(installer_repo_file_value FILE_RUNTIME_F2FS)" "$TMP_ENV_DIR/runtime.sh"
  fetch_hook "$(installer_repo_file_value FILE_RUNTIME_ACCOUNT)" "$TMP_ENV_DIR/account.sh"
  fetch_hook "$(installer_repo_file_value FILE_PARTMAN_DETECT_DISK)" "$TMP_ENV_DIR/detect-disk.sh"

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

ensure_partition_tooling
ensure_f2fs_tooling
ensure_f2fs_kernel_support
install_partman_f2fs_backend

if [ -r "$TMP_ENV_DIR/runtime.env" ]; then
  # shellcheck disable=SC1090,SC1091
  . "$TMP_ENV_DIR/runtime.env"
else
  runtime_apply_layout_from_cmdline
  if [ "${DUALBOOT_ENABLED:-false}" = "true" ]; then
    runtime_capture_dualboot_partition_sizes
  fi
  runtime_write_runtime_env "$RUNTIME_ENV_FILE"
  cp "$RUNTIME_ENV_FILE" "${TMP_ENV_DIR}/runtime.env"
  runtime_write_expert_recipe "$RUNTIME_RECIPE_FILE"
  runtime_write_partman_fragment "$RUNTIME_FRAGMENT_FILE" "$RUNTIME_RECIPE_FILE"
fi

[ -n "${DEV_INSTALL_DISK:-}" ] || fatal "DEV_INSTALL_DISK must be set"
[ -b "$DEV_INSTALL_DISK" ] || fatal "disk device not found: ${DEV_INSTALL_DISK}"

ensure_partman_state_dir
partman_early_prepare_layout

if runtime_any_crypto_enabled; then
  install_crypto_skip_erase_hook
fi

install_storage_layout_hook
installer_info "partman layout hook installed"
