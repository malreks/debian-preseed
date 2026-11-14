#!/bin/sh
set -eu

RUNTIME_DIR=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
BOOTSTRAP_LIB=${INSTALLER_BOOTSTRAP_LIB:-${RUNTIME_DIR}/bootstrap/bootstrap.sh}
TMP_ENV_DIR=
LOG=

CUDA_FRAGMENT_REL=
cuda_prepkgsel_fatal() {
  cuda_prepkgsel_message=$(printf '%s' "$*" | tr '\r\n\t' '   ')
  if command -v installer_error >/dev/null 2>&1; then
    installer_error "CUDA legacy pre-pkgsel: ${cuda_prepkgsel_message}"
  else
    printf '[pre-pkgsel:cuda-legacy] fatal: %s\n' "$cuda_prepkgsel_message" >&2
    if [ -c /dev/tty4 ] && [ -w /dev/tty4 ]; then
      printf '[pre-pkgsel:cuda-legacy] fatal: %s\n' "$cuda_prepkgsel_message" >/dev/tty4 || :
    fi
    if command -v logger >/dev/null 2>&1; then
      logger -t preseed-cuda-legacy "fatal: $cuda_prepkgsel_message" 2>/dev/null || :
    fi
  fi
  exit 1
}

[ -s "$BOOTSTRAP_LIB" ] || cuda_prepkgsel_fatal "installer bootstrap library is unavailable: ${BOOTSTRAP_LIB}"
# shellcheck disable=SC1090,SC1091
. "$BOOTSTRAP_LIB"
bootstrap_source_common_lib ""
TMP_ENV_DIR=${INSTALLER_CUDA_PREPKGSEL_ENV_DIR:-${DIR_INSTALLER_PRE_PKGSEL_ENV}/cuda-legacy}
CUDA_FRAGMENT_REL=$(installer_repo_file_value FILE_CLASS_OPTIONAL_CUDA_LEGACY)

LOG="$(installer_runtime_log_file)"
INSTALLER_DEBUG_LOGS=1
INSTALLER_LOG_LEVEL=debug
export INSTALLER_DEBUG_LOGS INSTALLER_LOG_LEVEL
installer_init_log_file "$LOG" "" "cuda legacy pre-pkgsel" cuda-legacy package_install
installer_operation_context_repo FILE_INST_PREPKG_91CUDA_LEGACY_APT 38 cuda_legacy_prepkgsel
trap 'installer_finalize_log "$?"' 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

SEED_BASE=$(installer_seed_base "")
installer_persist_seed_source "$SEED_BASE"
installer_ensure_context_loaded "$SEED_BASE"

if ! installer_cuda_legacy_selected 2>/dev/null; then
  installer_info "skipping CUDA legacy pre-pkgsel bootstrap because optional/cuda-legacy is not selected"
  exit 0
fi

# CUDA userspace/compiler packages are useful on build hosts without a GPU.
# Explicit class selection is authoritative; PCI detection must not skip them.

install -d -m 0700 "$TMP_ENV_DIR"
bootstrap_source_common_support_libs "$SEED_BASE" "$TMP_ENV_DIR" fetch hook target || {
  cuda_prepkgsel_fatal "failed to source shared installer helper libraries"
}

cuda_load_shared_repository_policy() {
  shared_policy_path="${TMP_ENV_DIR}/host.env"
  installer_fetch_host_env "$SEED_BASE" "$INSTALLER_HOST_PROFILE" "$shared_policy_path" 0600 ||
    cuda_prepkgsel_fatal "failed to fetch validated host policy"
  installer_load_data_env "$shared_policy_path" ||
    cuda_prepkgsel_fatal "failed to parse validated host policy"
  [ -n "${CUDA_LEGACY_REPOSITORY_URL:-}" ] ||
    cuda_prepkgsel_fatal "shared host profile policy does not define CUDA_LEGACY_REPOSITORY_URL"
  installer_cuda_repository_url >/dev/null ||
    cuda_prepkgsel_fatal "shared host profile policy defines an unsupported CUDA repository"
}

cuda_load_shared_repository_policy

cuda_fragment_path() {
  printf '%s/cuda-legacy.fragment.cfg\n' "$TMP_ENV_DIR"
}

cuda_fetch_fragment() {
  fragment_path=$(cuda_fragment_path)
  if [ ! -s "$fragment_path" ]; then
    installer_fetch_file "$SEED_BASE" "$CUDA_FRAGMENT_REL" "$fragment_path" 0644
  fi
  [ -s "$fragment_path" ] || cuda_prepkgsel_fatal "legacy CUDA fragment is missing: ${CUDA_FRAGMENT_REL}"
  printf '%s\n' "$fragment_path"
}

cuda_fragment_field_value() {
  field_name=$1
  fragment_path=$(cuda_fetch_fragment)
  field_value=$(sed -n "s/^d-i[[:space:]]\\+apt-setup\\/local[0-9][0-9]*\\/${field_name}[[:space:]]\\+string[[:space:]]\\+//p" "$fragment_path" | sed -n '1p')
  [ -n "$field_value" ] || cuda_prepkgsel_fatal "legacy CUDA fragment is missing apt-setup/${field_name}"
  printf '%s\n' "$field_value"
}

cuda_repository_value() {
  cuda_fragment_field_value repository
}

cuda_fragment_repository_url() {
  repo_value=$(cuda_repository_value)
  set -- $repo_value
  [ "$#" -ge 1 ] || cuda_prepkgsel_fatal "legacy CUDA repository value is empty"
  printf '%s\n' "$1"
}

cuda_repository_url() {
  fragment_url=$(cuda_fragment_repository_url)
  policy_url=$(installer_cuda_repository_url) ||
    cuda_prepkgsel_fatal "shared host profile policy defines an unsupported CUDA repository"
  [ "$fragment_url" = "$policy_url" ] ||
    cuda_prepkgsel_fatal "legacy CUDA fragment repository does not match CUDA_LEGACY_REPOSITORY_URL"
  printf '%s\n' "$policy_url"
}

cuda_repository_suite() {
  repo_value=$(cuda_repository_value)
  set -- $repo_value
  [ "$#" -ge 2 ] || cuda_prepkgsel_fatal "legacy CUDA repository suite is missing"
  printf '%s\n' "$2"
}

cuda_repository_components() {
  repo_value=$(cuda_repository_value)
  set -- $repo_value
  shift 2
  printf '%s\n' "$*"
}

stage_cuda_legacy_source() {
  installer_cuda_stage_target_source \
    "$(cuda_repository_url)" "$(cuda_repository_suite)" "$(cuda_repository_components)"
}

prepare_cuda_legacy_target_apt_dirs() {
  run_in_target "repair legacy CUDA target apt directories" /bin/sh -eu -c '
var_root=$1
cache_root=$2
tmp_root=$3
install -d -m 0755 "$var_root/lib/apt" "$var_root/lib/apt/lists" "$cache_root" "$cache_root/apt" "$cache_root/apt/archives"
install -d -m 0700 "$var_root/lib/apt/lists/partial" "$cache_root/apt/archives/partial"
if id -u _apt >/dev/null 2>&1; then
  chown _apt:root "$var_root/lib/apt/lists/partial" "$cache_root/apt/archives/partial"
fi
install -d -m 1777 "$tmp_root" "$var_root/tmp"
' sh "$DIR_VAR" "$DIR_VAR_CACHE" "$DIR_TMP"
}

refresh_cuda_legacy_target_apt_metadata() {
  installer_cuda_refresh_target_apt
}

stage_cuda_legacy_source
prepare_cuda_legacy_target_apt_dirs
refresh_cuda_legacy_target_apt_metadata
