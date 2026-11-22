#!/bin/sh
set -eu

llama_target_mode=0
case "${1:-}" in
  --target-install)
    llama_target_mode=1
    shift
    ;;
esac

if [ "$llama_target_mode" = 0 ]; then
  target_root=${1:-${TARGET_ROOT}}
  [ -d "$target_root" ] || exit 0
fi

llama_fatal() {
  llama_message=$(printf '%s' "$*" | tr '\r\n\t' '   ')
  if command -v installer_error >/dev/null 2>&1; then
    installer_error "llama.cpp: ${llama_message}"
  else
    printf 'fatal: llama.cpp: %s\n' "$llama_message" >&2
    if [ -c /dev/tty4 ] && [ -w /dev/tty4 ]; then
      printf '[late:llama] fatal: %s\n' "$llama_message" >/dev/tty4 || :
    fi
    if command -v logger >/dev/null 2>&1; then
      logger -t preseed-llama "fatal: $llama_message" 2>/dev/null || :
    fi
  fi
  exit 1
}

llama_info() {
  if [ "$llama_target_mode" = 1 ]; then
    printf '[llama] %s\n' "$*" >&2
  else
    printf '[late:llama] %s\n' "$*" >&2
  fi
}

llama_validate_abs_path() {
  label=$1
  value=$2

  case "$value" in
    /*) ;;
    *) llama_fatal "$label must be an absolute path: ${value:-unset}" ;;
  esac
  case "$value" in
    /|*..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@%:+,-]*)
      llama_fatal "$label contains unsupported path syntax: $value"
      ;;
  esac
}

llama_validate_bool() {
  case "$2" in
    0|1) ;;
    *) llama_fatal "$1 must be 0 or 1" ;;
  esac
}

llama_validate_positive_integer() {
  label=$1
  value=$2

  case "$value" in
    ''|*[!0123456789]*|0)
      llama_fatal "$label must be a positive integer: ${value:-unset}"
      ;;
  esac
}

llama_validate_nonnegative_integer() {
  label=$1
  value=$2

  case "$value" in
    ''|*[!0123456789]*)
      llama_fatal "$label must be a non-negative integer: ${value:-unset}"
      ;;
  esac
}

llama_validate_integer_range() {
  label=$1
  value=$2
  minimum=$3
  maximum=$4

  llama_validate_nonnegative_integer "$label" "$value"
  [ "$value" -ge "$minimum" ] && [ "$value" -le "$maximum" ] ||
    llama_fatal "$label must be between $minimum and $maximum: $value"
}

llama_validate_sha256() {
  label=$1
  value=$2

  [ "${#value}" -eq 64 ] ||
    llama_fatal "$label must contain 64 lowercase hexadecimal characters"
  case "$value" in
    *[!0123456789abcdef]*)
      llama_fatal "$label must contain 64 lowercase hexadecimal characters"
      ;;
  esac
}

llama_validate_release_policy() {
  case "$LLAMA_RELEASE_URL" in
    https://*) ;;
    *) llama_fatal "LLAMA_RELEASE_URL must use HTTPS" ;;
  esac
  case "$LLAMA_RELEASE_URL" in
    *[[:space:]]*) llama_fatal "LLAMA_RELEASE_URL must not contain whitespace" ;;
  esac
  release_suffix="/${LLAMA_RELEASE_ARCHIVE_ROOT}.tar.gz"
  case "$LLAMA_RELEASE_URL" in
    *"$release_suffix") ;;
    *)
      llama_fatal \
        "LLAMA_RELEASE_URL must end with the profile-owned archive ${release_suffix}"
      ;;
  esac
  unset release_suffix

  llama_validate_sha256 LLAMA_RELEASE_SHA256 "$LLAMA_RELEASE_SHA256"
  llama_validate_integer_range \
    LLAMA_RELEASE_MAXIMUM_EXTRACTED_BYTES \
    "$LLAMA_RELEASE_MAXIMUM_EXTRACTED_BYTES" \
    1 \
    "$LLAMA_RELEASE_MAXIMUM_EXTRACTED_BYTES"
  llama_validate_integer_range \
    LLAMA_RELEASE_MAXIMUM_MEMBERS \
    "$LLAMA_RELEASE_MAXIMUM_MEMBERS" \
    8 \
    256

  case "$LLAMA_RELEASE_ARCHIVE_ROOT" in
    ''|.|..|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]*)
      llama_fatal "LLAMA_RELEASE_ARCHIVE_ROOT must be a safe archive directory name" ;;
  esac
  case "$LLAMA_RELEASE_REQUIRED_CLASS" in
    ''|optional/*) ;;
    *) llama_fatal "LLAMA_RELEASE_REQUIRED_CLASS must be empty or an addon class reference" ;;
  esac
}

llama_validate_model_policy() {
  case "$LLAMA_DEFAULT_MODEL" in
    ''|.|..|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+-]*)
      llama_fatal "LLAMA_DEFAULT_MODEL must be a safe GGUF filename"
      ;;
    *.gguf) ;;
    *) llama_fatal "LLAMA_DEFAULT_MODEL must end in .gguf" ;;
  esac

  case "$LLAMA_DOWNLOAD_URL" in
    https://*) ;;
    *) llama_fatal "LLAMA_DOWNLOAD_URL must use HTTPS" ;;
  esac
  case "$LLAMA_DOWNLOAD_URL" in
    *[[:space:]]*) llama_fatal "LLAMA_DOWNLOAD_URL must not contain whitespace" ;;
  esac

  llama_validate_sha256 LLAMA_MODEL_SHA256 "$LLAMA_MODEL_SHA256"
}

llama_validate_policy() {
  : "${LLAMA_RELEASE_URL:?missing LLAMA_RELEASE_URL}"
  : "${LLAMA_RELEASE_SHA256:?missing LLAMA_RELEASE_SHA256}"
  : "${LLAMA_RELEASE_MAXIMUM_EXTRACTED_BYTES:?missing LLAMA_RELEASE_MAXIMUM_EXTRACTED_BYTES}"
  : "${LLAMA_RELEASE_MAXIMUM_MEMBERS:?missing LLAMA_RELEASE_MAXIMUM_MEMBERS}"
  : "${LLAMA_RELEASE_ARCHIVE_ROOT:?missing LLAMA_RELEASE_ARCHIVE_ROOT}"
  [ "${LLAMA_RELEASE_REQUIRED_CLASS+x}" = x ] ||
    llama_fatal "missing LLAMA_RELEASE_REQUIRED_CLASS"
  : "${LLAMA_ROOT:?missing LLAMA_ROOT}"
  : "${LLAMA_BINARY_DIR:?missing LLAMA_BINARY_DIR}"
  : "${LLAMA_METADATA_DIR:?missing LLAMA_METADATA_DIR}"
  : "${LLAMA_SHARE_DIR:?missing LLAMA_SHARE_DIR}"
  : "${LLAMA_WRAPPER_PATH:?missing LLAMA_WRAPPER_PATH}"
  : "${LLAMA_MODEL_DIR:?missing LLAMA_MODEL_DIR}"
  : "${LLAMA_DOWNLOAD_RETRIES:?missing LLAMA_DOWNLOAD_RETRIES}"
  : "${LLAMA_DOWNLOAD_CONNECT_TIMEOUT_SECONDS:?missing LLAMA_DOWNLOAD_CONNECT_TIMEOUT_SECONDS}"
  : "${LLAMA_DOWNLOAD_MAX_TIME_SECONDS:?missing LLAMA_DOWNLOAD_MAX_TIME_SECONDS}"
  : "${LLAMA_DEFAULT_MODEL:?missing LLAMA_DEFAULT_MODEL}"
  : "${LLAMA_DOWNLOAD_URL:?missing LLAMA_DOWNLOAD_URL}"
  : "${LLAMA_MODEL_SHA256:?missing LLAMA_MODEL_SHA256}"
  : "${LLAMA_RUNTIME_CONTEXT:?missing LLAMA_RUNTIME_CONTEXT}"
  : "${LLAMA_RUNTIME_BATCH:?missing LLAMA_RUNTIME_BATCH}"
  : "${LLAMA_RUNTIME_UBATCH:?missing LLAMA_RUNTIME_UBATCH}"
  : "${LLAMA_RUNTIME_THREADS:?missing LLAMA_RUNTIME_THREADS}"
  : "${LLAMA_RUNTIME_THREADS_BATCH:?missing LLAMA_RUNTIME_THREADS_BATCH}"
  : "${LLAMA_RUNTIME_GPU_LAYERS:?missing LLAMA_RUNTIME_GPU_LAYERS}"
  : "${LLAMA_RUNTIME_KV_OFFLOAD:?missing LLAMA_RUNTIME_KV_OFFLOAD}"
  : "${LLAMA_RUNTIME_PARALLEL:?missing LLAMA_RUNTIME_PARALLEL}"
  : "${LLAMA_SERVER_HOST:?missing LLAMA_SERVER_HOST}"
  : "${LLAMA_SERVER_PORT:?missing LLAMA_SERVER_PORT}"
  : "${LLAMA_MIN_MEMORY_MIB:?missing LLAMA_MIN_MEMORY_MIB}"
  : "${LLAMA_MIN_CPU_CORES:?missing LLAMA_MIN_CPU_CORES}"

  llama_validate_release_policy
  llama_validate_model_policy

  llama_validate_abs_path LLAMA_ROOT "$LLAMA_ROOT"
  llama_validate_abs_path LLAMA_BINARY_DIR "$LLAMA_BINARY_DIR"
  llama_validate_abs_path LLAMA_METADATA_DIR "$LLAMA_METADATA_DIR"
  llama_validate_abs_path LLAMA_SHARE_DIR "$LLAMA_SHARE_DIR"
  llama_validate_abs_path LLAMA_WRAPPER_PATH "$LLAMA_WRAPPER_PATH"
  llama_validate_abs_path LLAMA_MODEL_DIR "$LLAMA_MODEL_DIR"
  [ "$LLAMA_BINARY_DIR" = "${LLAMA_ROOT}__INSTALLER_PATH_DIR_BIN__" ] ||
    llama_fatal "LLAMA_BINARY_DIR must remain ${LLAMA_ROOT}__INSTALLER_PATH_DIR_BIN__"
  [ "$LLAMA_METADATA_DIR" = "${LLAMA_ROOT}/metadata" ] ||
    llama_fatal "LLAMA_METADATA_DIR must remain ${LLAMA_ROOT}/metadata"
  [ "$LLAMA_SHARE_DIR" = "${LLAMA_ROOT}/share" ] ||
    llama_fatal "LLAMA_SHARE_DIR must remain ${LLAMA_ROOT}/share"
  [ "$LLAMA_WRAPPER_PATH" = "${LLAMA_ROOT}__INSTALLER_PATH_DIR_LIB__" ] ||
    llama_fatal "LLAMA_WRAPPER_PATH must remain ${LLAMA_ROOT}__INSTALLER_PATH_DIR_LIB__"

  llama_validate_bool LLAMA_FORCE_DOWNLOAD "${LLAMA_FORCE_DOWNLOAD-}"
  llama_validate_bool LLAMA_STRICT_RESOURCES "${LLAMA_STRICT_RESOURCES-}"
  llama_validate_bool LLAMA_RUNTIME_KV_OFFLOAD "${LLAMA_RUNTIME_KV_OFFLOAD-}"
  llama_validate_integer_range LLAMA_DOWNLOAD_RETRIES "$LLAMA_DOWNLOAD_RETRIES" 1 20
  llama_validate_integer_range \
    LLAMA_DOWNLOAD_CONNECT_TIMEOUT_SECONDS \
    "$LLAMA_DOWNLOAD_CONNECT_TIMEOUT_SECONDS" \
    5 \
    300
  llama_validate_integer_range \
    LLAMA_DOWNLOAD_MAX_TIME_SECONDS \
    "$LLAMA_DOWNLOAD_MAX_TIME_SECONDS" \
    60 \
    86400

  llama_validate_integer_range LLAMA_RUNTIME_CONTEXT "$LLAMA_RUNTIME_CONTEXT" 512 1048576
  llama_validate_integer_range LLAMA_RUNTIME_BATCH "$LLAMA_RUNTIME_BATCH" 1 32768
  llama_validate_integer_range LLAMA_RUNTIME_UBATCH "$LLAMA_RUNTIME_UBATCH" 1 32768
  [ "$LLAMA_RUNTIME_UBATCH" -le "$LLAMA_RUNTIME_BATCH" ] ||
    llama_fatal "LLAMA_RUNTIME_UBATCH must not exceed LLAMA_RUNTIME_BATCH"
  llama_validate_integer_range LLAMA_RUNTIME_THREADS "$LLAMA_RUNTIME_THREADS" 1 256
  llama_validate_integer_range LLAMA_RUNTIME_THREADS_BATCH "$LLAMA_RUNTIME_THREADS_BATCH" 1 256
  llama_validate_integer_range LLAMA_RUNTIME_GPU_LAYERS "$LLAMA_RUNTIME_GPU_LAYERS" 0 999
  llama_validate_integer_range LLAMA_RUNTIME_PARALLEL "$LLAMA_RUNTIME_PARALLEL" 1 128
  if [ "$LLAMA_RELEASE_ARCHIVE_ROOT" = llama-ram ]; then
    [ "$LLAMA_RUNTIME_GPU_LAYERS" = 0 ] ||
      llama_fatal "the RAM release requires LLAMA_RUNTIME_GPU_LAYERS=0"
  fi

  [ "$LLAMA_SERVER_HOST" = 127.0.0.1 ] ||
    llama_fatal "LLAMA_SERVER_HOST must remain 127.0.0.1"
  llama_validate_integer_range LLAMA_SERVER_PORT "$LLAMA_SERVER_PORT" 1 65535

  llama_validate_integer_range LLAMA_MIN_MEMORY_MIB "$LLAMA_MIN_MEMORY_MIB" 0 1048576
  llama_validate_integer_range LLAMA_MIN_CPU_CORES "$LLAMA_MIN_CPU_CORES" 0 256
  if [ "$LLAMA_MIN_MEMORY_MIB" = 0 ] || [ "$LLAMA_MIN_CPU_CORES" = 0 ]; then
    [ "$LLAMA_MIN_MEMORY_MIB" = 0 ] && [ "$LLAMA_MIN_CPU_CORES" = 0 ] ||
      llama_fatal "llama.cpp resource minima must both be 0 or both be positive integers"
  fi
  if [ "$LLAMA_STRICT_RESOURCES" = 1 ]; then
    [ "$LLAMA_MIN_MEMORY_MIB" -gt 0 ] && [ "$LLAMA_MIN_CPU_CORES" -gt 0 ] ||
      llama_fatal "LLAMA_STRICT_RESOURCES=1 requires positive resource minima"
  fi
}

llama_validate_release_class_selection() {
  case "$LLAMA_RELEASE_REQUIRED_CLASS" in
    '') return 0 ;;
    optional/cuda-legacy)
      installer_class_selected optional/cuda-legacy 2>__INSTALLER_PATH_DIR_DEV__/null ||
        llama_fatal \
          "${LLAMA_RELEASE_ARCHIVE_ROOT} requires the optional/cuda-legacy runtime class"
      ;;
    *)
      llama_fatal "unsupported release class requirement: $LLAMA_RELEASE_REQUIRED_CLASS"
      ;;
  esac
}

llama_target_require_command() {
  command -v "$1" >__INSTALLER_PATH_DIR_DEV__/null 2>&1 ||
    llama_fatal "required target command is unavailable: $1"
}

llama_target_managed_marker_path() {
  printf '%s/.installer-llama-managed\n' "$1"
}

llama_target_managed_dir() {
  dir_path=$1
  dir_label=$2
  marker_path=$(llama_target_managed_marker_path "$dir_path")

  [ ! -L "$dir_path" ] ||
    llama_fatal "managed ${dir_label} directory must not be a symbolic link: $dir_path"
  if [ -e "$dir_path" ] && [ ! -d "$dir_path" ]; then
    llama_fatal "managed ${dir_label} path exists but is not a directory: $dir_path"
  fi
  if [ ! -d "$dir_path" ]; then
    install -d -m 0755 "$dir_path"
  fi

  if [ -e "$marker_path" ]; then
    [ ! -L "$marker_path" ] && [ -f "$marker_path" ] ||
      llama_fatal "managed ${dir_label} marker is invalid: $marker_path"
    expected_marker="managed=llama-${dir_label}"
    [ "$(cat "$marker_path")" = "$expected_marker" ] ||
      llama_fatal "managed ${dir_label} marker does not belong to this installer: $marker_path"
    return 0
  fi

  if ! first_entry=$(find "$dir_path" -mindepth 1 -maxdepth 1 -print 2>__INSTALLER_PATH_DIR_DEV__/null); then
    llama_fatal "unable to inspect managed ${dir_label} directory: $dir_path"
  fi
  [ -z "$first_entry" ] ||
    llama_fatal "refusing to adopt non-empty unmarked ${dir_label} directory: $dir_path"

  marker_tmp="${marker_path}.tmp.$$"
  printf 'managed=llama-%s\n' "$dir_label" >"$marker_tmp"
  chmod 0600 "$marker_tmp"
  mv -f "$marker_tmp" "$marker_path"
}

llama_target_secure_model_directory() {
  model_group_record=$(getent group devops 2>__INSTALLER_PATH_DIR_DEV__/null || true)
  case "$model_group_record" in
    devops:*:*:*) ;;
    *) llama_fatal "cannot resolve the devops group for managed Llama models" ;;
  esac
  llama_model_gid=${model_group_record#*:}
  llama_model_gid=${llama_model_gid#*:}
  llama_model_gid=${llama_model_gid%%:*}
  case "$llama_model_gid" in
    ''|*[!0-9]*)
      llama_fatal "cannot resolve the devops group id for managed Llama models"
      ;;
  esac

  marker_path=$(llama_target_managed_marker_path "$LLAMA_MODEL_DIR")
  chown "0:${llama_model_gid}" "$LLAMA_MODEL_DIR" "$marker_path"
  chmod 2750 "$LLAMA_MODEL_DIR"
  chmod 0600 "$marker_path"
  unset marker_path model_group_record
}

llama_target_available_cores() {
  if command -v nproc >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
    nproc
  else
    getconf _NPROCESSORS_ONLN 2>__INSTALLER_PATH_DIR_DEV__/null || printf '1\n'
  fi
}

llama_target_validate_resource_budget() {
  [ "$LLAMA_STRICT_RESOURCES" = 1 ] || return 0

  available_memory_kib=$(awk '/^MemTotal:/ { print $2; exit }' __INSTALLER_PATH_DIR_PROC__/meminfo 2>__INSTALLER_PATH_DIR_DEV__/null || true)
  case "$available_memory_kib" in
    ''|*[!0-9]*)
      llama_fatal "cannot determine available system memory for strict llama.cpp resources"
      ;;
  esac
  available_memory_mib=$((available_memory_kib / 1024))
  available_core_count=$(llama_target_available_cores)
  case "$available_core_count" in
    ''|*[!0-9]*)
      llama_fatal "cannot determine available CPU cores for strict llama.cpp resources"
      ;;
  esac

  [ "$available_memory_mib" -ge "$LLAMA_MIN_MEMORY_MIB" ] ||
    llama_fatal "strict resources require at least ${LLAMA_MIN_MEMORY_MIB} MiB for ${LLAMA_DEFAULT_MODEL}"
  [ "$available_core_count" -ge "$LLAMA_MIN_CPU_CORES" ] ||
    llama_fatal "strict resources require at least ${LLAMA_MIN_CPU_CORES} CPU cores for ${LLAMA_DEFAULT_MODEL}"
}

llama_target_model_magic() {
  candidate=$1
  [ -f "$candidate" ] && [ ! -L "$candidate" ] || return 1
  LC_ALL=C dd if="$candidate" bs=4 count=1 2>__INSTALLER_PATH_DIR_DEV__/null |
    od -An -tx1 |
    tr -d ' \n'
}

llama_target_model_is_valid() {
  candidate=$1
  model_validation_bytes=unknown
  model_validation_magic=unavailable
  model_validation_failure=unknown

  [ -f "$candidate" ] && [ ! -L "$candidate" ] || {
    model_validation_failure=not-regular-file
    return 1
  }

  model_validation_bytes=$(wc -c <"$candidate" 2>__INSTALLER_PATH_DIR_DEV__/null | tr -d ' ')
  case "$model_validation_bytes" in
    ''|*[!0-9]*)
      model_validation_failure=unreadable-size
      return 1
      ;;
  esac

  model_validation_magic=$(llama_target_model_magic "$candidate" 2>__INSTALLER_PATH_DIR_DEV__/null || true)
  [ "$model_validation_magic" = 47475546 ] || {
    model_validation_failure=gguf-magic
    return 1
  }
  model_validation_failure=none
  return 0
}

llama_target_download_model() {
  final_model=$1
  model_tmp="${LLAMA_MODEL_DIR}/.${LLAMA_DEFAULT_MODEL}.tmp.$$"

  rm -f -- "$model_tmp"
  curl \
    --fail \
    --location \
    --silent \
    --show-error \
    --proto '=https' \
    --proto-redir '=https' \
    --retry "$LLAMA_DOWNLOAD_RETRIES" \
    --retry-all-errors \
    --retry-max-time "$LLAMA_DOWNLOAD_MAX_TIME_SECONDS" \
    --connect-timeout "$LLAMA_DOWNLOAD_CONNECT_TIMEOUT_SECONDS" \
    --max-time "$LLAMA_DOWNLOAD_MAX_TIME_SECONDS" \
    --output "$model_tmp" \
    "$LLAMA_DOWNLOAD_URL" ||
    llama_fatal "failed to download configured GGUF model: $LLAMA_DOWNLOAD_URL"

  if ! llama_target_model_is_valid "$model_tmp"; then
    llama_fatal \
      "downloaded model is invalid: ${LLAMA_DEFAULT_MODEL} (bytes=${model_validation_bytes}, magic=${model_validation_magic}, reason=${model_validation_failure})"
  fi
  actual_sha256=$(sha256sum "$model_tmp") || llama_fatal 'cannot checksum the downloaded GGUF model'
  [ "${actual_sha256%% *}" = "$LLAMA_MODEL_SHA256" ] || llama_fatal 'downloaded GGUF model SHA-256 mismatch'
  chown "0:${llama_model_gid}" "$model_tmp"
  chmod 0640 "$model_tmp"
  mv -f "$model_tmp" "$final_model"
  model_tmp=
}

llama_target_prepare_model() {
  final_model="${LLAMA_MODEL_DIR}/${LLAMA_DEFAULT_MODEL}"

  if [ -L "$final_model" ] || { [ -e "$final_model" ] && [ ! -f "$final_model" ]; }; then
    llama_fatal "refusing to replace an unmanaged model path: $final_model"
  fi
  if [ "$LLAMA_FORCE_DOWNLOAD" = 0 ] && llama_target_model_is_valid "$final_model"; then
    chown "0:${llama_model_gid}" "$final_model"
    chmod 0640 "$final_model"
    llama_info "reusing installed model ${LLAMA_DEFAULT_MODEL} without a checksum rescan"
    return 0
  fi
  llama_target_download_model "$final_model"
  chown "0:${llama_model_gid}" "$final_model"
  chmod 0640 "$final_model"
  llama_info "downloaded verified model ${LLAMA_DEFAULT_MODEL}"
}

llama_target_write_runtime_config() {
  runtime_conf_dir=__INSTALLER_PATH_DIR_ETC__/llama
  runtime_conf="${runtime_conf_dir}/llama.conf"
  runtime_conf_template=/tmp/llama.conf.tmpl
  runtime_conf_tmp="${runtime_conf}.tmp.$$"

  [ ! -L "$runtime_conf_dir" ] ||
    llama_fatal "runtime configuration directory must not be a symbolic link"
  if [ -e "$runtime_conf_dir" ] && [ ! -d "$runtime_conf_dir" ]; then
    llama_fatal "runtime configuration path exists but is not a directory"
  fi
  [ ! -L "$runtime_conf" ] ||
    llama_fatal "runtime configuration file must not be a symbolic link"
  if [ -e "$runtime_conf" ] && [ ! -f "$runtime_conf" ]; then
    llama_fatal "runtime configuration file path is not a regular file"
  fi
  [ -f "$runtime_conf_template" ] && [ ! -L "$runtime_conf_template" ] ||
    llama_fatal "runtime configuration template is unavailable"
  [ "$(find -P "$runtime_conf_template" -maxdepth 0 -printf '%U:%G:%m')" = 0:0:600 ] ||
    llama_fatal "runtime configuration template must be root:root mode 0600"

  install -d -o 0 -g 0 -m 0755 "$runtime_conf_dir"
  rm -f -- "$runtime_conf_tmp"
  # The installer supplied complete configuration through the shared Perl
  # renderer. The target helper only stages those validated bytes.
  cat "$runtime_conf_template" >"$runtime_conf_tmp"
  if grep -q '__LLAMA_' "$runtime_conf_tmp"; then
    rm -f -- "$runtime_conf_tmp"
    llama_fatal "runtime configuration template contains unresolved placeholders"
  fi
  chown 0:0 "$runtime_conf_tmp"
  chmod 0644 "$runtime_conf_tmp"
  mv -f "$runtime_conf_tmp" "$runtime_conf"
  chown 0:0 "$runtime_conf_dir" "$runtime_conf"
  chmod 0755 "$runtime_conf_dir"
  chmod 0644 "$runtime_conf"

  unset \
    runtime_conf \
    runtime_conf_dir \
    runtime_conf_template \
    runtime_conf_tmp
}

llama_target_rollback_release_publication() {
  [ "${llama_release_publish_in_progress:-0}" = 1 ] || return 0

  rm -rf -- "$LLAMA_BINARY_DIR" "$LLAMA_METADATA_DIR" "$LLAMA_SHARE_DIR" || true
  rm -f -- "${LLAMA_ROOT}/.installer-release" || true
  llama_release_publish_in_progress=0
}

llama_target_download_and_install_release() {
  target_archive_helper_path=/tmp/installer-ai-runtime-archive.py
  [ -f "$target_archive_helper_path" ] && [ ! -L "$target_archive_helper_path" ] ||
    llama_fatal "managed AI runtime archive helper is unavailable"
  [ "$(find -P "$target_archive_helper_path" -maxdepth 0 -printf '%U:%G:%m')" = 0:0:700 ] ||
    llama_fatal "managed AI runtime archive helper must be root:root mode 0700"

  release_record="${LLAMA_ROOT}/.installer-release"
  for release_target in \
    "$LLAMA_BINARY_DIR" \
    "$LLAMA_METADATA_DIR" \
    "$LLAMA_SHARE_DIR" \
    "$release_record"
  do
    [ ! -e "$release_target" ] && [ ! -L "$release_target" ] ||
      llama_fatal "refusing to replace an existing llama release path: $release_target"
  done
  unset release_target

  llama_release_staging=$(mktemp -d "${LLAMA_ROOT}/.release.XXXXXXXX") ||
    llama_fatal "unable to allocate llama release staging directory"
  chmod 0700 "$llama_release_staging"
  archive_path="${llama_release_staging}/llama.tar.gz"
  extract_dir="${llama_release_staging}/extract"

  curl \
    --fail \
    --location \
    --silent \
    --show-error \
    --proto '=https' \
    --proto-redir '=https' \
    --tlsv1.2 \
    --retry "$LLAMA_DOWNLOAD_RETRIES" \
    --retry-all-errors \
    --retry-max-time "$LLAMA_DOWNLOAD_MAX_TIME_SECONDS" \
    --connect-timeout "$LLAMA_DOWNLOAD_CONNECT_TIMEOUT_SECONDS" \
    --max-time "$LLAMA_DOWNLOAD_MAX_TIME_SECONDS" \
    --output "$archive_path" \
    "$LLAMA_RELEASE_URL" ||
    llama_fatal "failed to download pinned llama runtime: $LLAMA_RELEASE_URL"

  archive_sha256=$(sha256sum "$archive_path" | awk '{print $1}')
  [ "$archive_sha256" = "$LLAMA_RELEASE_SHA256" ] ||
    llama_fatal "downloaded llama runtime SHA-256 does not match profile policy"

  install -d -m 0700 "$extract_dir"
  python3 "$target_archive_helper_path" \
    --archive "$archive_path" \
    --output-directory "$extract_dir" \
    --archive-root "$LLAMA_RELEASE_ARCHIVE_ROOT" \
    --required-directory bin \
    --required-directory metadata \
    --required-directory share \
    --required-binary llama-bench \
    --required-binary llama-cli \
    --required-binary llama-gguf-split \
    --required-binary llama-quantize \
    --required-binary llama-server \
    --maximum-extracted-bytes "$LLAMA_RELEASE_MAXIMUM_EXTRACTED_BYTES" \
    --maximum-members "$LLAMA_RELEASE_MAXIMUM_MEMBERS" ||
    llama_fatal "llama runtime archive validation or extraction failed"

  release_record_staged="${extract_dir}/.installer-release"
  {
    printf 'url=%s\n' "$LLAMA_RELEASE_URL"
    printf 'sha256=%s\n' "$LLAMA_RELEASE_SHA256"
    printf 'archive_root=%s\n' "$LLAMA_RELEASE_ARCHIVE_ROOT"
  } >"$release_record_staged"
  chown -R 0:0 \
    "$extract_dir/bin" \
    "$extract_dir/metadata" \
    "$extract_dir/share" \
    "$release_record_staged"
  chmod 0644 "$release_record_staged"

  llama_release_publish_in_progress=1
  if mv -- "$extract_dir/bin" "$LLAMA_BINARY_DIR" &&
     mv -- "$extract_dir/metadata" "$LLAMA_METADATA_DIR" &&
     mv -- "$extract_dir/share" "$LLAMA_SHARE_DIR" &&
     mv -- "$release_record_staged" "$release_record"
  then
    llama_release_publish_in_progress=0
  else
    llama_target_rollback_release_publication
    llama_fatal "failed to publish the complete llama runtime release"
  fi

  rm -rf -- "$llama_release_staging"
  llama_release_staging=
  unset archive_bytes archive_path archive_sha256 extract_dir release_record release_record_staged
}

llama_target_install_wrapper() {
  wrapper_file="${LLAMA_WRAPPER_PATH}/llama"
  wrapper_source=/tmp/llama-launcher

  [ ! -L "$LLAMA_WRAPPER_PATH" ] ||
    llama_fatal "managed llama wrapper directory must not be a symbolic link"
  install -d -o 0 -g 0 -m 0755 "$LLAMA_WRAPPER_PATH"
  [ ! -L "$wrapper_file" ] ||
    llama_fatal "managed llama wrapper must not be a symbolic link: $wrapper_file"
  if [ -e "$wrapper_file" ] && [ ! -f "$wrapper_file" ]; then
    llama_fatal "managed llama wrapper path is not a regular file: $wrapper_file"
  fi
  [ -f "$wrapper_source" ] && [ ! -L "$wrapper_source" ] ||
    llama_fatal "managed llama launcher source is unavailable"
  [ "$(find -P "$wrapper_source" -maxdepth 0 -printf '%U:%G:%m')" = 0:0:600 ] ||
    llama_fatal "managed llama launcher source must be root:root mode 0600"

  wrapper_tmp="${wrapper_file}.tmp.$$"
  rm -f -- "$wrapper_tmp"
  install -o 0 -g 0 -m 0755 "$wrapper_source" "$wrapper_tmp"
  mv -f "$wrapper_tmp" "$wrapper_file"
  chown 0:0 "$LLAMA_ROOT" "$LLAMA_WRAPPER_PATH" "$wrapper_file"
  chmod 0755 "$LLAMA_ROOT" "$LLAMA_WRAPPER_PATH" "$wrapper_file"
  unset wrapper_file wrapper_source wrapper_tmp
}

llama_target_install() {
  # This mode runs only after llama.sh and its archive helper have been staged
  # into the target. No source checkout or compilation is performed.
  PATH=__INSTALLER_PATH_DIR_USR_LOCAL__/sbin:__INSTALLER_PATH_DIR_USR_LOCAL__/bin:__INSTALLER_PATH_DIR_USR__/sbin:__INSTALLER_PATH_DIR_USR__/bin:__INSTALLER_PATH_DIR_SBIN__:__INSTALLER_PATH_DIR_BIN__
  export PATH
  umask 077

  config_path=${1:-/tmp/llama-install.env}
  target_install_runtime_conf_template=/tmp/llama.conf.tmpl
  target_install_wrapper_source=/tmp/llama-launcher
  target_archive_helper_path=/tmp/installer-ai-runtime-archive.py
  case "$config_path" in
    /tmp/llama-install.env) ;;
    *) llama_fatal "unexpected configuration path: ${config_path:-unset}" ;;
  esac
  llama_target_require_command find
  [ -f "$config_path" ] && [ ! -L "$config_path" ] ||
    llama_fatal "temporary configuration file is unavailable"
  [ "$(find -P "$config_path" -maxdepth 0 -printf '%U:%G:%m')" = 0:0:600 ] ||
    llama_fatal "temporary configuration file must be root:root mode 0600"

  llama_release_staging=
  llama_release_publish_in_progress=0
  model_tmp=
  # shellcheck disable=SC2329
  cleanup_target_install() {
    [ -z "${model_tmp:-}" ] || rm -f -- "$model_tmp"
    llama_target_rollback_release_publication
    [ -z "${llama_release_staging:-}" ] || rm -rf -- "$llama_release_staging"
    rm -f -- "$config_path" "$target_install_runtime_conf_template" "$target_install_wrapper_source" "$target_archive_helper_path"
  }
  trap cleanup_target_install 0
  trap 'cleanup_target_install; exit 1' 1 2 15

  # shellcheck disable=SC1090
  . "$config_path"
  llama_validate_policy

  for required_command in awk cat chmod chown curl dd find getconf getent grep install mktemp mv od python3 rm sed sha256sum tr wc; do
    llama_target_require_command "$required_command"
  done
  unset required_command

  llama_target_validate_resource_budget
  llama_target_managed_dir "$LLAMA_ROOT" runtime
  llama_target_managed_dir "$LLAMA_MODEL_DIR" models
  llama_target_secure_model_directory
  llama_target_download_and_install_release
  llama_target_prepare_model
  llama_target_write_runtime_config
  llama_target_install_wrapper

  llama_info "installed five llama release binaries, metadata, shared assets, configuration, launcher, and ${LLAMA_DEFAULT_MODEL}"
}

if [ "$llama_target_mode" = 1 ]; then
  llama_target_install "$@"
  exit $?
fi

runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}

[ -s "$bootstrap_lib" ] ||
  llama_fatal "installer bootstrap library is unavailable: ${bootstrap_lib}"
# shellcheck disable=SC1090,SC1091
. "$bootstrap_lib"
bootstrap_source_common_lib "" ||
  llama_fatal "failed to source installer common library"
# Load di.env through the common bootstrap before deriving d-i state paths.
tmp_env_dir=${INSTALLER_LLAMA_TMP_ENV_DIR:-${DIR_INSTALLER_LATE_ENV}/llama}
installer_operation_context_repo scripts/late/llama.sh 705 llama
seed_base=$(installer_current_seed_base 2>__INSTALLER_PATH_DIR_DEV__/null || installer_seed_base "")
bootstrap_source_common_support_libs "$seed_base" "$tmp_env_dir" fetch hook target ||
  llama_fatal "failed to source installer target support libraries"
installer_ensure_context_loaded "$seed_base"

installer_any_role_class_selected 2>__INSTALLER_PATH_DIR_DEV__/null || exit 0
case "${INSTALLER_HOST_VARIANT:-}" in
  desktop|server) ;;
  *) llama_fatal 'the selected Llama class requires a registered desktop or server role' ;;
esac

host_env=${INSTALLER_LATE_HOST_ENV:-${DIR_INSTALLER_LATE_ENV}/host.env}
[ -r "$host_env" ] ||
  installer_fetch_host_env "$seed_base" "$(installer_resolve_host_profile "")" "$host_env" 0600
# shellcheck disable=SC1090,SC1091
installer_load_data_env "$host_env"

llama_validate_policy
llama_validate_release_class_selection

target_helper=/tmp/installer-llama
target_helper_host="${target_root}${target_helper}"
target_profile=/tmp/llama-install.env
target_profile_host="${target_root}${target_profile}"
helper_tmp="${tmp_env_dir}/installer-llama.$$"
target_archive_helper=/tmp/installer-ai-runtime-archive.py
target_archive_helper_host="${target_root}${target_archive_helper}"
archive_helper_tmp="${tmp_env_dir}/installer-ai-runtime-archive.py.$$"
target_runtime_template=/tmp/llama.conf.tmpl
target_runtime_template_host="${target_root}${target_runtime_template}"
runtime_template_tmp="${tmp_env_dir}/llama.conf.tmpl.$$"
target_wrapper_source=/tmp/llama-launcher
target_wrapper_source_host="${target_root}${target_wrapper_source}"
wrapper_source_tmp="${tmp_env_dir}/llama-launcher.$$"

install -d -m 0700 "$tmp_env_dir"
bootstrap_fetch_seed_file "$seed_base" "$(installer_repo_file_value scripts/late/llama.sh)" "$helper_tmp" 0600 "llama.cpp late helper"
install -d -m 1777 "${target_root}/tmp"
install -m 0700 "$helper_tmp" "$target_helper_host"
chown 0:0 "$target_helper_host"
rm -f -- "$helper_tmp"
bootstrap_fetch_seed_file "$seed_base" "$(installer_repo_file_value scripts/late/ai-runtime-archive.py)" "$archive_helper_tmp" 0600 "AI runtime archive validator"
install -m 0700 "$archive_helper_tmp" "$target_archive_helper_host"
chown 0:0 "$target_archive_helper_host"
rm -f -- "$archive_helper_tmp"
bootstrap_fetch_seed_file "$seed_base" "$(installer_repo_file_value hooks/target/etc/llama/llama.conf.tmpl)" "$runtime_template_tmp" 0600 "llama.cpp runtime configuration template"
installer_apply_scalar_placeholders "$runtime_template_tmp" "$runtime_template_tmp" \
  LLAMA_MODEL "${LLAMA_MODEL_DIR}/${LLAMA_DEFAULT_MODEL}" \
  LLAMA_RUNTIME_CONTEXT "$LLAMA_RUNTIME_CONTEXT" LLAMA_RUNTIME_BATCH "$LLAMA_RUNTIME_BATCH" \
  LLAMA_RUNTIME_UBATCH "$LLAMA_RUNTIME_UBATCH" LLAMA_RUNTIME_THREADS "$LLAMA_RUNTIME_THREADS" \
  LLAMA_RUNTIME_THREADS_BATCH "$LLAMA_RUNTIME_THREADS_BATCH" LLAMA_RUNTIME_GPU_LAYERS "$LLAMA_RUNTIME_GPU_LAYERS" \
  LLAMA_RUNTIME_KV_OFFLOAD "$LLAMA_RUNTIME_KV_OFFLOAD" LLAMA_RUNTIME_PARALLEL "$LLAMA_RUNTIME_PARALLEL" \
  LLAMA_SERVER_HOST "$LLAMA_SERVER_HOST" LLAMA_SERVER_PORT "$LLAMA_SERVER_PORT" ||
  llama_fatal 'cannot render Llama runtime configuration with prepared Perl'
installer_assert_no_unresolved_installer_placeholders "$runtime_template_tmp" 'Llama runtime configuration' || exit 1
install -m 0600 "$runtime_template_tmp" "$target_runtime_template_host"
chown 0:0 "$target_runtime_template_host"
rm -f -- "$runtime_template_tmp"
bootstrap_fetch_seed_file "$seed_base" "$(installer_repo_file_value hooks/target/data/llama/lib/llama)" "$wrapper_source_tmp" 0600 "llama.cpp launcher"
install -m 0600 "$wrapper_source_tmp" "$target_wrapper_source_host"
chown 0:0 "$target_wrapper_source_host"
rm -f -- "$wrapper_source_tmp"

cleanup_target_install_assets() {
  rm -f -- "$helper_tmp" "$archive_helper_tmp" "$runtime_template_tmp" "$wrapper_source_tmp" \
    "$target_helper_host" "$target_archive_helper_host" "$target_profile_host" \
    "$target_runtime_template_host" "$target_wrapper_source_host"
}
trap cleanup_target_install_assets 0
trap 'cleanup_target_install_assets; exit 1' 1 2 15

umask 077
{
  write_shell_config_var LLAMA_RELEASE_URL "$LLAMA_RELEASE_URL"
  write_shell_config_var LLAMA_RELEASE_SHA256 "$LLAMA_RELEASE_SHA256"
  write_shell_config_var LLAMA_RELEASE_MAXIMUM_EXTRACTED_BYTES "$LLAMA_RELEASE_MAXIMUM_EXTRACTED_BYTES"
  write_shell_config_var LLAMA_RELEASE_MAXIMUM_MEMBERS "$LLAMA_RELEASE_MAXIMUM_MEMBERS"
  write_shell_config_var LLAMA_RELEASE_ARCHIVE_ROOT "$LLAMA_RELEASE_ARCHIVE_ROOT"
  write_shell_config_var LLAMA_RELEASE_REQUIRED_CLASS "$LLAMA_RELEASE_REQUIRED_CLASS"
  write_shell_config_var LLAMA_ROOT "$LLAMA_ROOT"
  write_shell_config_var LLAMA_BINARY_DIR "$LLAMA_BINARY_DIR"
  write_shell_config_var LLAMA_METADATA_DIR "$LLAMA_METADATA_DIR"
  write_shell_config_var LLAMA_SHARE_DIR "$LLAMA_SHARE_DIR"
  write_shell_config_var LLAMA_WRAPPER_PATH "$LLAMA_WRAPPER_PATH"
  write_shell_config_var LLAMA_MODEL_DIR "$LLAMA_MODEL_DIR"
  write_shell_config_var LLAMA_FORCE_DOWNLOAD "$LLAMA_FORCE_DOWNLOAD"
  write_shell_config_var LLAMA_DOWNLOAD_RETRIES "$LLAMA_DOWNLOAD_RETRIES"
  write_shell_config_var LLAMA_DOWNLOAD_CONNECT_TIMEOUT_SECONDS "$LLAMA_DOWNLOAD_CONNECT_TIMEOUT_SECONDS"
  write_shell_config_var LLAMA_DOWNLOAD_MAX_TIME_SECONDS "$LLAMA_DOWNLOAD_MAX_TIME_SECONDS"
  write_shell_config_var LLAMA_DEFAULT_MODEL "$LLAMA_DEFAULT_MODEL"
  write_shell_config_var LLAMA_DOWNLOAD_URL "$LLAMA_DOWNLOAD_URL"
  write_shell_config_var LLAMA_MODEL_SHA256 "$LLAMA_MODEL_SHA256"
  write_shell_config_var LLAMA_RUNTIME_CONTEXT "$LLAMA_RUNTIME_CONTEXT"
  write_shell_config_var LLAMA_RUNTIME_BATCH "$LLAMA_RUNTIME_BATCH"
  write_shell_config_var LLAMA_RUNTIME_UBATCH "$LLAMA_RUNTIME_UBATCH"
  write_shell_config_var LLAMA_RUNTIME_THREADS "$LLAMA_RUNTIME_THREADS"
  write_shell_config_var LLAMA_RUNTIME_THREADS_BATCH "$LLAMA_RUNTIME_THREADS_BATCH"
  write_shell_config_var LLAMA_RUNTIME_GPU_LAYERS "$LLAMA_RUNTIME_GPU_LAYERS"
  write_shell_config_var LLAMA_RUNTIME_KV_OFFLOAD "$LLAMA_RUNTIME_KV_OFFLOAD"
  write_shell_config_var LLAMA_RUNTIME_PARALLEL "$LLAMA_RUNTIME_PARALLEL"
  write_shell_config_var LLAMA_SERVER_HOST "$LLAMA_SERVER_HOST"
  write_shell_config_var LLAMA_SERVER_PORT "$LLAMA_SERVER_PORT"
  write_shell_config_var LLAMA_STRICT_RESOURCES "$LLAMA_STRICT_RESOURCES"
  write_shell_config_var LLAMA_MIN_MEMORY_MIB "$LLAMA_MIN_MEMORY_MIB"
  write_shell_config_var LLAMA_MIN_CPU_CORES "$LLAMA_MIN_CPU_CORES"
} >"$target_profile_host"
chmod 0600 "$target_profile_host"
chown 0:0 "$target_profile_host"

run_in_target "download and install selected llama.cpp runtime" \
  "$target_helper" --target-install "$target_profile"

# The target helper verifies every installed artifact before returning.
rm -f -- "$target_helper_host" "$target_archive_helper_host" "$target_profile_host" \
  "$target_runtime_template_host" "$target_wrapper_source_host"
llama_info "installed profile-selected llama.cpp release for the selected DevOps class"
