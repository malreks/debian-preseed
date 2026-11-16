#!/bin/sh

bootstrap_log() {
  printf '[bootstrap] %s\n' "$*" >&2
}

bootstrap_fatal() {
  bootstrap_message=$(printf '%s' "$*" | tr '\r\n\t' '   ')
  bootstrap_log "fatal: $bootstrap_message"
  if [ -c /dev/tty4 ] && [ -w /dev/tty4 ]; then
    printf '[bootstrap] fatal: %s\n' "$bootstrap_message" >/dev/tty4 || :
  fi
  if [ -c /dev/console ] && [ -w /dev/console ]; then
    printf '[bootstrap] fatal: %s\n' "$bootstrap_message" >/dev/console || :
  fi
  if command -v logger >/dev/null 2>&1; then
    logger -t preseed-bootstrap "fatal: $bootstrap_message" 2>/dev/null || :
  fi
  exit 1
}

bootstrap_runtime_dir() {
  printf '%s\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_runtime_log_dir() {
  bootstrap_runtime_log_path=${FILE_INSTALLER_LOG:-/tmp/installer.log}
  printf '%s\n' "${bootstrap_runtime_log_path%/*}"
}

bootstrap_runtime_log_file() {
  printf '%s\n' "${FILE_INSTALLER_LOG:-/tmp/installer.log}"
}

bootstrap_runtime_cache_dir() {
  printf '%s/cache\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_runtime_seed_cache_dir() {
  printf '%s/cache/seed\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_runtime_bootstrap_dir() {
  printf '%s/bootstrap\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_seed_url_path() {
  printf '%s/bootstrap/seed.url\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_seed_file_path() {
  printf '%s/bootstrap/seed.file\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_lib_path() {
  printf '%s/bootstrap/bootstrap.sh\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_repo_env_relpath() {
  printf '%s\n' repo.env
}

bootstrap_repo_env_path() {
  printf '%s/bootstrap/repo.env\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_di_env_path() {
  printf '%s/bootstrap/di.env\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_validate_repo_dir_value() {
  bootstrap_repo_validate_var=$1
  bootstrap_repo_validate_value=$2

  case "$bootstrap_repo_validate_value" in
    ''|/*|../*|*/..|*../*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@+-]*)
      bootstrap_fatal "${bootstrap_repo_validate_var} must be a safe repository-relative directory path: ${bootstrap_repo_validate_value:-unset}"
      ;;
  esac
}

bootstrap_validate_repo_file_value() {
  bootstrap_repo_validate_file_name=$1
  bootstrap_repo_validate_file_value=$2

  case "$bootstrap_repo_validate_file_value" in
    "${DIR_TARGET_SKEL_VIVALDI:-}/Local State") ;;
    ''|/*|../*|*/..|*../*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@+-]*)
      bootstrap_fatal "${bootstrap_repo_validate_file_name} must be a safe repository-relative file path: ${bootstrap_repo_validate_file_value:-unset}"
      ;;
  esac
}

bootstrap_repo_env_selector_vars() {
  bootstrap_repo_env_vars_path=$1
  sed -n 's/^\(DIR_[A-Z0-9_]*\|FILE_[A-Z0-9_]*\)=.*/\1/p' "$bootstrap_repo_env_vars_path"
}

bootstrap_repo_dir_input_is_var() {
  case "${1:-}" in
    DIR_[ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*)
      case "$1" in
        *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*) return 1 ;;
      esac
      return 0
      ;;
  esac
  return 1
}

bootstrap_validate_repo_env() {
  bootstrap_repo_env_path_value=$(bootstrap_repo_env_path) || return $?
  [ -r "$bootstrap_repo_env_path_value" ] ||
    bootstrap_fatal "repository path environment is not readable: $bootstrap_repo_env_path_value"
  while IFS= read -r bootstrap_repo_env_var || [ -n "$bootstrap_repo_env_var" ]; do
    [ -n "$bootstrap_repo_env_var" ] || continue
    bootstrap_repo_env_value=
    eval "bootstrap_repo_env_value=\${$bootstrap_repo_env_var:-}"
    case "$bootstrap_repo_env_var" in
      DIR_*) bootstrap_validate_repo_dir_value "$bootstrap_repo_env_var" "$bootstrap_repo_env_value" ;;
      FILE_*) bootstrap_validate_repo_file_value "$bootstrap_repo_env_var" "$bootstrap_repo_env_value" ;;
      *) bootstrap_fatal "unsupported repository selector: $bootstrap_repo_env_var" ;;
    esac
  done <<EOF
$(bootstrap_repo_env_selector_vars "$bootstrap_repo_env_path_value")
EOF
}

bootstrap_di_required_vars() {
  cat <<'EOF'
TARGET_ROOT
DIR_INSTALLER_RUNTIME
DIR_INSTALLER_ENV
DIR_INSTALLER_LATE_ENV
DIR_INSTALLER_PRE_PKGSEL_ENV
DIR_INSTALLER_RUNTIME_STATE
DIR_INSTALLER_BIN
DIR_INSTALLER_SBIN
DIR_INSTALLER_USR
DIR_INSTALLER_USR_BIN
DIR_INSTALLER_USR_SBIN
DIR_INSTALLER_USR_LOCAL
DIR_INSTALLER_USR_LOCAL_BIN
DIR_INSTALLER_USR_LOCAL_SBIN
DIR_INSTALLER_USR_LOCAL_LIBEXEC
DIR_INSTALLER_STATE
FILE_INSTALLER_LOG
FILE_INSTALLER_SELECTED_DISK_IDENTITY
FILE_INSTALLER_APT_NORMALIZE_SOURCES
FILE_INSTALLER_DPKG_DIVERT
FILE_INSTALLER_OS_PROBER
FILE_INSTALLER_OS_PROBER_REAL
FILE_INSTALLER_OS_PROBER_STATE
FILE_INSTALLER_UNSHARE
FILE_INSTALLER_UNSHARE_REAL
FILE_INSTALLER_UNSHARE_STATE
DIR_INSTALLER_BASE_INSTALLER_D
DIR_INSTALLER_POST_BASE_INSTALLER_D
DIR_INSTALLER_PRE_PKGSEL_D
DIR_INSTALLER_APT_SETUP_GENERATORS
DIR_INSTALLER_FINISH_INSTALL_D
DIR_INSTALLER_LIB_PARTMAN
DIR_INSTALLER_LIB_PARTMAN_FINISH_D
DIR_INSTALLER_VAR_LIB_PARTMAN
EOF
}

bootstrap_validate_di_source() {
  bootstrap_di_source_path=$1
  [ -r "$bootstrap_di_source_path" ] || bootstrap_fatal "installer environment is not readable: $bootstrap_di_source_path"
  /bin/sh -n "$bootstrap_di_source_path" || bootstrap_fatal "installer environment has invalid shell syntax: $bootstrap_di_source_path"
  bootstrap_di_source_names=

  while IFS= read -r bootstrap_di_source_line || [ -n "$bootstrap_di_source_line" ]; do
    case "$bootstrap_di_source_line" in
      ''|[[:space:]]*|\#*)
        case "$bootstrap_di_source_line" in
          ''|\#*) continue ;;
          *) bootstrap_fatal "installer environment contains unsupported leading whitespace: $bootstrap_di_source_path" ;;
        esac
        ;;
    esac
    case "$bootstrap_di_source_line" in
      *'$('*|*'`'*|*';'*|*'|'*|*'&'*)
        bootstrap_fatal "installer environment contains executable syntax: $bootstrap_di_source_path"
        ;;
      [A-Z_][A-Z0-9_]*=\"[A-Za-z0-9._/@+\$\{\}-]*\")
        bootstrap_di_source_name=${bootstrap_di_source_line%%=*}
        case "$bootstrap_di_source_name" in
          TARGET_ROOT|FILE_INSTALLER_*|DIR_INSTALLER_*) ;;
          *) bootstrap_fatal "installer environment contains an unsupported variable: $bootstrap_di_source_name" ;;
        esac
        case " $bootstrap_di_source_names " in
          *" $bootstrap_di_source_name "*) bootstrap_fatal "installer environment contains a duplicate variable: $bootstrap_di_source_name" ;;
        esac
        bootstrap_di_source_names="$bootstrap_di_source_names $bootstrap_di_source_name"
        ;;
      *) bootstrap_fatal "installer environment contains an invalid assignment: $bootstrap_di_source_path" ;;
    esac
  done <"$bootstrap_di_source_path"
}

bootstrap_validate_di_env() {
  bootstrap_validate_di_value=
  for bootstrap_di_env_var in $(bootstrap_di_required_vars); do
    eval "bootstrap_validate_di_value=\${$bootstrap_di_env_var:-}"
    case "$bootstrap_di_env_var:$bootstrap_validate_di_value" in
      TARGET_ROOT:/target) ;;
      TARGET_ROOT:*) bootstrap_fatal 'TARGET_ROOT must be exactly /target' ;;
      DIR_INSTALLER_*:*|FILE_INSTALLER_*:/*)
        case "$bootstrap_validate_di_value" in
          /*) ;;
          *) bootstrap_fatal "${bootstrap_di_env_var} must be absolute" ;;
        esac
        case "$bootstrap_validate_di_value" in
          *..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@+-]*)
            bootstrap_fatal "${bootstrap_di_env_var} contains an unsafe path: ${bootstrap_validate_di_value:-unset}"
            ;;
        esac
        ;;
      *) bootstrap_fatal "${bootstrap_di_env_var} is missing from installer environment" ;;
    esac
  done
}

bootstrap_ensure_di_env() {
  bootstrap_di_seed_base=${1:-}
  [ "${BOOTSTRAP_DI_ENV_READY:-0}" -eq 1 ] && return 0
  [ -n "${FILE_HOOKS_INSTALLER_DI_ENV:-}" ] || bootstrap_fatal 'FILE_HOOKS_INSTALLER_DI_ENV is unset in repo.env'
  bootstrap_validate_repo_file_value FILE_HOOKS_INSTALLER_DI_ENV "$FILE_HOOKS_INSTALLER_DI_ENV"

  bootstrap_di_env_file=$(bootstrap_di_env_path) || return $?
  if [ ! -s "$bootstrap_di_env_file" ]; then
    [ -n "$bootstrap_di_seed_base" ] || bootstrap_di_seed_base=$(bootstrap_require_seed_base "") || return $?
    bootstrap_fetch_seed_file "$bootstrap_di_seed_base" "$FILE_HOOKS_INSTALLER_DI_ENV" "$bootstrap_di_env_file" 0600 "installer path environment" || return $?
  fi
  bootstrap_validate_di_source "$bootstrap_di_env_file"
  # shellcheck disable=SC1090
  . "$bootstrap_di_env_file" || return $?
  bootstrap_validate_di_env || return $?
  BOOTSTRAP_DI_ENV_READY=1
}

bootstrap_load_persisted_suite() {
  # d-i invokes maintainer scripts and hook wrappers in fresh processes after
  # the preseed command that exported INSTALLER_SUITE has exited.  Recover only
  # the generated suite context here; an absent context is valid during the
  # initial preseed bootstrap and is handled by the caller's exported value.
  [ -n "${INSTALLER_SUITE:-}" ] && return 0
  bootstrap_context_env=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/state/context.env
  if [ ! -e "$bootstrap_context_env" ] && [ ! -L "$bootstrap_context_env" ]; then
    return 0
  fi
  [ -f "$bootstrap_context_env" ] && [ ! -L "$bootstrap_context_env" ] && [ -r "$bootstrap_context_env" ] ||
    bootstrap_fatal "installer context is not a regular readable file: $bootstrap_context_env"
  /bin/sh -n "$bootstrap_context_env" ||
    bootstrap_fatal "installer context has invalid shell syntax: $bootstrap_context_env"
  # shellcheck disable=SC1090
  . "$bootstrap_context_env" ||
    bootstrap_fatal "cannot load installer context: $bootstrap_context_env"
  # The caller may launch another d-i helper after loading this state.  Keep
  # the recovered suite in that child environment as well as this shell.
  export INSTALLER_SUITE
}

bootstrap_ensure_repo_env() {
  bootstrap_repo_seed_base=${1:-}

  if [ "${BOOTSTRAP_REPO_ENV_READY:-0}" -eq 1 ]; then
    return 0
  fi

  bootstrap_repo_seed_base=$(bootstrap_require_seed_base "$bootstrap_repo_seed_base") || return $?
  bootstrap_repo_env_file=$(bootstrap_repo_env_path) || return $?
  if [ ! -s "$bootstrap_repo_env_file" ]; then
    bootstrap_fetch_seed_file "$bootstrap_repo_seed_base" "$(bootstrap_repo_env_relpath)" "$bootstrap_repo_env_file" 0600 "repository path environment" || return $?
  fi
  # shellcheck disable=SC1090
  case "${INSTALLER_SUITE:-}" in forky|trixie) ;; *) bootstrap_fatal "pinned suite is missing or unsupported" ;; esac
  . "$bootstrap_repo_env_file" || return $?
  bootstrap_validate_repo_env || return $?
  bootstrap_ensure_di_env "$bootstrap_repo_seed_base" || return $?
  BOOTSTRAP_REPO_ENV_READY=1
}

bootstrap_repo_dir_value() {
  bootstrap_repo_dir_name=$1
  bootstrap_repo_dir_value=
  bootstrap_repo_dir_path=

  if ! bootstrap_repo_dir_input_is_var "$bootstrap_repo_dir_name"; then
    bootstrap_repo_dir_path=$bootstrap_repo_dir_name
    bootstrap_validate_repo_dir_value repository_path "$bootstrap_repo_dir_path"
    printf '%s\n' "$bootstrap_repo_dir_path"
    return 0
  fi

  eval "bootstrap_repo_dir_value=\${$bootstrap_repo_dir_name:-}"
  [ -n "$bootstrap_repo_dir_value" ] || bootstrap_fatal "repository directory variable is unset: $bootstrap_repo_dir_name"
  bootstrap_validate_repo_dir_value "$bootstrap_repo_dir_name" "$bootstrap_repo_dir_value"
  printf '%s\n' "$bootstrap_repo_dir_value"
}

bootstrap_repo_file_value() {
  bootstrap_repo_file_name=$1
  case "$bootstrap_repo_file_name" in
    FILE_[A-Z0-9_]*) ;;
    *) bootstrap_fatal "repository file selector is invalid: ${bootstrap_repo_file_name:-unset}" ;;
  esac
  case "$bootstrap_repo_file_name" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*)
      bootstrap_fatal "repository file selector is invalid: $bootstrap_repo_file_name"
      ;;
  esac

  bootstrap_repo_file_value_result=
  eval "bootstrap_repo_file_value_result=\${$bootstrap_repo_file_name:-}"
  [ -n "$bootstrap_repo_file_value_result" ] ||
    bootstrap_fatal "repository file variable is unset: $bootstrap_repo_file_name"
  bootstrap_validate_repo_file_value "$bootstrap_repo_file_name" "$bootstrap_repo_file_value_result"
  printf '%s\n' "$bootstrap_repo_file_value_result"
}

bootstrap_repo_join_var() {
  bootstrap_repo_join_dir=$1
  bootstrap_repo_join_leaf=${2:-}
  bootstrap_repo_join_base=$(bootstrap_repo_dir_value "$bootstrap_repo_join_dir") || return $?

  # Systemd template-unit paths legitimately contain "@", for example
  # etc/systemd/system/user@.service.d/50-oom-score.conf.
  case "$bootstrap_repo_join_leaf" in
    '') printf '%s\n' "$bootstrap_repo_join_base" ;;
    # Chromium-derived Vivaldi profiles require this exact space-containing
    # filename. Keep the exception limited to the managed seed asset, and
    # normalize a leading slash if an older caller supplies one.
    "etc/skel-desktop/.config/vivaldi/Local State")
      printf '%s/%s\n' "$bootstrap_repo_join_base" "$bootstrap_repo_join_leaf"
      ;;
    "/etc/skel-desktop/.config/vivaldi/Local State")
      printf '%s/etc/skel-desktop/.config/vivaldi/Local State\n' "$bootstrap_repo_join_base"
      ;;
    /*|../*|*/..|*../*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@-]*)
      bootstrap_fatal "unsafe repository path suffix for ${bootstrap_repo_join_dir}: ${bootstrap_repo_join_leaf:-unset}"
      ;;
    *) printf '%s/%s\n' "$bootstrap_repo_join_base" "$bootstrap_repo_join_leaf" ;;
  esac
}

bootstrap_repo_resolve_path() {
  bootstrap_repo_source_path=$1

  case "$bootstrap_repo_source_path" in
    "$(bootstrap_repo_env_relpath)")
      printf '%s\n' "$bootstrap_repo_source_path"
      return 0
      ;;
  esac

  bootstrap_ensure_repo_env ""
  case "$bootstrap_repo_source_path" in
    "${DIR_SCRIPTS_COMMON}/"*)
      bootstrap_repo_join_var DIR_SCRIPTS_COMMON "${bootstrap_repo_source_path#"${DIR_SCRIPTS_COMMON}"/}"
      ;;
    "${DIR_SCRIPTS_PRESEED}/"*)
      bootstrap_repo_join_var DIR_SCRIPTS_PRESEED "${bootstrap_repo_source_path#"${DIR_SCRIPTS_PRESEED}"/}"
      ;;
    "${DIR_SCRIPTS_EARLY}/"*)
      bootstrap_repo_join_var DIR_SCRIPTS_EARLY "${bootstrap_repo_source_path#"${DIR_SCRIPTS_EARLY}"/}"
      ;;
    "${DIR_SCRIPTS_PARTMAN}/"*)
      bootstrap_repo_join_var DIR_SCRIPTS_PARTMAN "${bootstrap_repo_source_path#"${DIR_SCRIPTS_PARTMAN}"/}"
      ;;
    "${DIR_SCRIPTS_LATE}/"*)
      bootstrap_repo_join_var DIR_SCRIPTS_LATE "${bootstrap_repo_source_path#"${DIR_SCRIPTS_LATE}"/}"
      ;;
    *)
      printf '%s\n' "$bootstrap_repo_source_path"
      ;;
  esac
}

bootstrap_phase_runner_path() {
  runner_name=$1
  printf '%s/bootstrap/%s\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}" "$runner_name"
}

bootstrap_seed_source_type() {
  case "${1:-}" in
    /*) printf '%s\n' file ;;
    *) printf '%s\n' url ;;
  esac
}

bootstrap_trim_seed_base() {
  seed_base=$1

  while [ "${#seed_base}" -gt 1 ]; do
    case "$seed_base" in
      */) seed_base=${seed_base%/} ;;
      *) break ;;
    esac
  done
  printf '%s\n' "$seed_base"
}

bootstrap_cmdline() {
  if [ -n "${INSTALLER_CMDLINE:-}" ]; then
    printf '%s\n' "$INSTALLER_CMDLINE"
    return 0
  fi
  if [ "${BOOTSTRAP_CMDLINE_CACHE_READY:-0}" -eq 1 ]; then
    printf '%s\n' "$BOOTSTRAP_CMDLINE_CACHE"
    return 0
  fi
  if [ -r /proc/cmdline ]; then
    BOOTSTRAP_CMDLINE_CACHE=$(cat /proc/cmdline)
  else
    BOOTSTRAP_CMDLINE_CACHE=
  fi
  BOOTSTRAP_CMDLINE_CACHE_READY=1
  printf '%s\n' "$BOOTSTRAP_CMDLINE_CACHE"
}

bootstrap_assign_normalized_seed_base() {
  output_var_name=$1
  seed_base=$2
  seed_type=$3

  seed_base=${seed_base%%\?*}
  case "$seed_base" in
    */*.cfg) seed_base=${seed_base%/*} ;;
  esac
  seed_base=$(bootstrap_trim_seed_base "$seed_base")

  case "$seed_type" in
    file)
      case "$seed_base" in
        /*) ;;
        *) bootstrap_fatal "installation file base must be an absolute path: ${seed_base:-unset}" ;;
      esac
      case "$seed_base" in
        *..*|*//*)
          bootstrap_fatal "installation file base contains unsupported traversal: $seed_base"
          ;;
      esac
      ;;
    url)
      [ -n "$seed_base" ] || bootstrap_fatal "installation URL base is empty"
      ;;
    *)
      bootstrap_fatal "unsupported installation source type: $seed_type"
      ;;
  esac

  eval "$output_var_name=\$seed_base"
}

bootstrap_normalize_seed_base() {
  normalized_seed_base=
  bootstrap_assign_normalized_seed_base normalized_seed_base "$1" "$2"
  printf '%s\n' "$normalized_seed_base"
}

bootstrap_validate_relative_seed_path() {
  seed_relative_path=$1

  case "$seed_relative_path" in
    ''|/*|../*|*/..|*../*|*//*)
      bootstrap_fatal "seed source path must stay relative to the seed base: ${seed_relative_path:-unset}"
      ;;
  esac
}

bootstrap_log_path_is_numbered() {
  bootstrap_check_log_path=$1
  bootstrap_check_log_name=${bootstrap_check_log_path##*/}

  case "$bootstrap_check_log_name" in
    [0-9]*-*) return 0 ;;
  esac
  return 1
}

bootstrap_log_sequence_file() {
  bootstrap_sequence_log_dir=$1
  printf '%s/.log-sequence\n' "$bootstrap_sequence_log_dir"
}

bootstrap_next_log_sequence() {
  bootstrap_sequence_log_dir=$1
  bootstrap_sequence_path=$(bootstrap_log_sequence_file "$bootstrap_sequence_log_dir")
  bootstrap_sequence_tmp="${bootstrap_sequence_path}.tmp.$$"
  bootstrap_current_sequence=0

  [ -d "$bootstrap_sequence_log_dir" ] || install -d -m 0700 "$bootstrap_sequence_log_dir"
  if [ -r "$bootstrap_sequence_path" ]; then
    bootstrap_current_sequence=$(cat "$bootstrap_sequence_path" 2>/dev/null || printf '0\n')
  fi
  case "$bootstrap_current_sequence" in
    ''|*[!0-9]*) bootstrap_current_sequence=0 ;;
  esac

  bootstrap_next_sequence=$((bootstrap_current_sequence + 1))
  printf '%s\n' "$bootstrap_next_sequence" >"$bootstrap_sequence_tmp"
  mv "$bootstrap_sequence_tmp" "$bootstrap_sequence_path"
  chmod 0600 "$bootstrap_sequence_path" 2>/dev/null || true
  printf '%s\n' "$bootstrap_next_sequence"
}

bootstrap_runtime_log_path_requested() {
  requested_log_path=$1
  runtime_log_dir=$(bootstrap_runtime_log_dir)

  case "$requested_log_path" in
    "${runtime_log_dir}/"*) return 0 ;;
  esac
  return 1
}

bootstrap_resolve_runtime_log_path() {
  bootstrap_runtime_log_file
}

bootstrap_file_safe_token() {
  printf '%s\n' "$(printf '%s' "${1:-seed}" | sed 's/[^A-Za-z0-9._-]/_/g')"
}

bootstrap_seed_cache_key() (
  bootstrap_load_source_library "$1" || exit 1
  normalized=$(source_normalize_base "$1") || exit 1
  key=$(printf '%s' "$normalized" | source_hash) || exit 1
  printf '%s\n' "${key%% *}"
)

bootstrap_seed_cache_path() (
  bootstrap_load_source_library "$1" || exit 1
  source_validate_relative "$2" || exit 1
  printf '%s/%s\n' "$(source_cache_root "$1")" "$2"
)

bootstrap_persist_seed_source() {
  seed_base=$1
  seed_type=$(bootstrap_seed_source_type "$seed_base") || return $?
  seed_url_path=$(bootstrap_seed_url_path) || return $?
  seed_file_path=$(bootstrap_seed_file_path) || return $?

  install -d -m 0700 "${seed_file_path%/*}" || return $?

  case "$seed_type" in
    file)
      printf '%s\n' "$seed_base" >"$seed_file_path" || return $?
      rm -f "$seed_url_path" || return $?
      ;;
    url)
      printf '%s\n' "$seed_base" >"$seed_url_path" || return $?
      rm -f "$seed_file_path" || return $?
      ;;
    *)
      bootstrap_fatal "unsupported installation source type: $seed_type"
      ;;
  esac
}

bootstrap_choose_seed_base_from_pair() {
  seed_url_base=$1
  seed_file_base=$2
  seed_label=$3

  if [ -n "$seed_url_base" ] && [ -n "$seed_file_base" ]; then
    bootstrap_fatal "${seed_label} defines both URL and file seed sources"
  fi
  if [ -n "$seed_url_base" ]; then
    bootstrap_assign_normalized_seed_base BOOTSTRAP_RESOLVED_SEED_BASE "$seed_url_base" url
    return 0
  fi
  if [ -n "$seed_file_base" ]; then
    bootstrap_assign_normalized_seed_base BOOTSTRAP_RESOLVED_SEED_BASE "$seed_file_base" file
    return 0
  fi

  BOOTSTRAP_RESOLVED_SEED_BASE=
  return 1
}

bootstrap_persisted_seed_base() {
  persisted_seed_url_base=
  persisted_seed_file_base=
  seed_url_path=$(bootstrap_seed_url_path)
  seed_file_path=$(bootstrap_seed_file_path)

  if [ -f "$seed_url_path" ]; then
    persisted_seed_url_base=$(cat "$seed_url_path")
  fi
  if [ -f "$seed_file_path" ]; then
    persisted_seed_file_base=$(cat "$seed_file_path")
  fi

  bootstrap_choose_seed_base_from_pair "$persisted_seed_url_base" "$persisted_seed_file_base" "persisted installer state"
}

bootstrap_cmdline_seed_base() {
  if [ "${BOOTSTRAP_CMDLINE_SEED_PAIR_READY:-0}" -eq 1 ]; then
    if bootstrap_choose_seed_base_from_pair "$BOOTSTRAP_CMDLINE_SEED_URL_BASE" "$BOOTSTRAP_CMDLINE_SEED_FILE_BASE" "kernel cmdline"; then
      printf '%s\n' "$BOOTSTRAP_RESOLVED_SEED_BASE"
      return 0
    fi
    return 1
  fi

  cmdline_seed_url_base=
  cmdline_seed_file_base=

  for arg in $(bootstrap_cmdline); do
    case "$arg" in
      preseed/url=*|url=*)
        [ -n "$cmdline_seed_url_base" ] || cmdline_seed_url_base=${arg#*=}
        ;;
      preseed/file=*|file=*)
        [ -n "$cmdline_seed_file_base" ] || cmdline_seed_file_base=${arg#*=}
        ;;
    esac
  done

  BOOTSTRAP_CMDLINE_SEED_URL_BASE=$cmdline_seed_url_base
  BOOTSTRAP_CMDLINE_SEED_FILE_BASE=$cmdline_seed_file_base
  BOOTSTRAP_CMDLINE_SEED_PAIR_READY=1

  if bootstrap_choose_seed_base_from_pair "$cmdline_seed_url_base" "$cmdline_seed_file_base" "kernel cmdline"; then
    printf '%s\n' "$BOOTSTRAP_RESOLVED_SEED_BASE"
    return 0
  fi
  return 1
}

bootstrap_require_seed_base() {
  # source.sh validates the selected suite while resolving a fresh preseed
  # source, so restore persisted context before any seed discovery can run.
  bootstrap_load_persisted_suite
  if [ -n "${1:-}" ]; then
    bootstrap_normalize_seed_base "$1" "$(bootstrap_seed_source_type "$1")"
    return 0
  fi
  if bootstrap_persisted_seed_base; then
    printf '%s\n' "$BOOTSTRAP_RESOLVED_SEED_BASE"
    return 0
  fi
  bootstrap_load_source_library "${INSTALLER_SOURCE_ROOT:-}" || return 1
  source_resolve_seed
}

bootstrap_require_seed_url_base() {
  bootstrap_require_seed_base "${1:-}"
}

bootstrap_fetch_seed_file() (
  bootstrap_load_source_library "$1" || exit "$?"
  # repository-apt is loaded before context-target during common bootstrap.
  # Delegate only when its source-library dependency exists. The initialized
  # publisher already owns the private fetch/render transaction.
  if command -v installer_fetch_seed_path >/dev/null 2>&1 &&
     command -v installer_load_source_library >/dev/null 2>&1; then
    installer_fetch_seed_path "$1" "$2" "$3" "${4:-0600}"
    exit "$?"
  fi
  bootstrap_path_destination=$3
  bootstrap_path_work=
  case "$2" in
    "${DIR_REPO_SCRIPTS:-}/"*|"${DIR_HOOKS_TARGET:-}/"*)
      # Keep the previous destination intact until acquisition and rendering
      # both succeed. The private sibling also bounds cleanup to this fetch.
      bootstrap_path_parent=$(dirname "$bootstrap_path_destination") || exit "$?"
      mkdir -p "$bootstrap_path_parent" || exit "$?"
      bootstrap_path_work=$(mktemp -d "$bootstrap_path_parent/.bootstrap-asset.XXXXXX") || exit "$?"
      bootstrap_path_cleanup() {
        bootstrap_cleanup_status=$?
        trap - 0
        if ! rm -rf -- "$bootstrap_path_work"; then
          [ "$bootstrap_cleanup_status" -ne 0 ] || bootstrap_cleanup_status=125
        fi
        exit "$bootstrap_cleanup_status"
      }
      trap bootstrap_path_cleanup 0
      trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
      chmod 0700 "$bootstrap_path_work" || exit "$?"
      set -- "$1" "$2" "$bootstrap_path_work/asset" "${4:-0600}"
      ;;
  esac
  source_fetch "$1" "$2" "$3" "${4:-0600}" || exit "$?"
  if command -v installer_render_logging_asset >/dev/null 2>&1; then
    installer_render_logging_asset "$1" "$2" "$3" || exit "$?"
  else
    case "$2" in
      "${DIR_HOOKS_TARGET:-}/"*|"${DIR_REPO_SCRIPTS:-}/"*)
        if LC_ALL=C grep -Eq '__INSTALLER_LOG_[A-Z0-9_]+__' "$3"; then
          bootstrap_fatal 'logging template requested before common library initialization'
        fi ;;
    esac
  fi
  case "$2" in
    "${DIR_REPO_SCRIPTS:-}/"*|"${DIR_HOOKS_TARGET:-}/"*)
      if LC_ALL=C grep -Eq '__INSTALLER_(PATH|APPARMOR_PROFILE)_[A-Z0-9_]+__' "$3"; then
        # Direct helper fetches (including Python and target re-entry scripts)
        # share the publication renderer. Early common/bootstrap modules and
        # authenticated parser data contain no concrete path tokens, so they
        # can load before the renderer and profile are initialized.
        bootstrap_path_cache=$(source_cache_root "$1") || exit "$?"
        case "$bootstrap_path_destination" in
          "$bootstrap_path_cache"|"$bootstrap_path_cache"/*)
            bootstrap_fatal 'refusing to render inside the authenticated source snapshot' ;;
        esac
        command -v installer_apply_scalar_placeholders >/dev/null 2>&1 &&
          command -v installer_assert_no_unresolved_path_placeholders >/dev/null 2>&1 ||
          bootstrap_fatal 'runtime path asset requested before common library initialization'
        # The caller supplies the protected destination mode.  Do not invoke
        # `stat`: busybox-udeb intentionally omits that applet.
        bootstrap_path_mode=${4:-0600}
        bootstrap_path_rendered="${3}.path-rendered"
        installer_apply_scalar_placeholders "$3" "$bootstrap_path_rendered" || exit "$?"
        installer_assert_no_unresolved_path_placeholders "$bootstrap_path_rendered" "$2" || exit "$?"
        chmod "$bootstrap_path_mode" "$bootstrap_path_rendered" || exit "$?"
        mv -f -- "$bootstrap_path_rendered" "$3" || exit "$?"
      else
        bootstrap_path_probe_status=$?
        [ "$bootstrap_path_probe_status" -eq 1 ] || exit 1
      fi
      ;;
  esac
  if [ -n "$bootstrap_path_work" ]; then
    mv -f -- "$3" "$bootstrap_path_destination" || exit "$?"
  fi
)

# Modules share the same source snapshot, transport and logging renderer as every
# other installer asset. Explicit callers define order; no glob, eval or PATH
# search chooses executable code. This resolver runs in a subshell so source
# transfer/rendering cannot clobber the caller's phase variables.
bootstrap_module_path() (
  set -eu
  umask 077
  [ "$#" -eq 1 ] || { bootstrap_log 'fatal: one module path is required'; exit 1; }
  # The catalog names physical template members; sourcing still receives the
  # same validated shell module after the shared renderer has run.
  case "${1%.tmpl}" in
    "${DIR_SCRIPTS_COMMON}/"*.sh|"${DIR_SCRIPTS_COMMON_MODULES}/"*.sh|"${DIR_SCRIPTS_RUNTIME_MODULES}/"*.sh|"${DIR_SCRIPTS_DESKTOP_COMPONENTS}/"*.sh|"${DIR_SCRIPTS_LATE_DEVOPS}/"*.sh) ;;
    *)
      # Account publication runs before a storage-family runtime is loaded.
      # Permit only its two definition-only entrypoints here; storage runtimes
      # and arbitrary siblings remain outside the shell-module interface.
      module_common_entry=$(bootstrap_repo_file_value FILE_RUNTIME_COMMON) || exit "$?"
      module_account_entry=$(bootstrap_repo_file_value FILE_RUNTIME_ACCOUNT) || exit "$?"
      case "$1" in
        "$module_common_entry"|"$module_account_entry") ;;
        *) bootstrap_log "fatal: unsupported module path: $1"; exit 1 ;;
      esac
      ;;
  esac
  bootstrap_load_source_library "${INSTALLER_SOURCE_ROOT:-}" || exit 1
  source_validate_relative "$1" || exit 1
  module_relative=$1
  module_seed=$(bootstrap_require_seed_base "") || exit 1
  # Remote code always requires the preseed-pinned payload. Explicit local
  # source trees remain usable by the existing developer/test bootstrap path.
  case "$module_seed" in
    /*) ;;
    *)
      [ -f "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/bootstrap/payload.ready" ] || {
        bootstrap_log 'fatal: remote module loading requires the authenticated payload'; exit 1;
      } ;;
  esac
  installer_lifecycle_paths || { bootstrap_log 'fatal: unsafe module runtime directory'; exit 1; }
  module_destination="${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/bootstrap/modules/$module_relative"
  module_parent=${module_destination%/*}
  module_probe=$module_parent
  # Refuse links and writable directories before mkdir, never repair an
  # untrusted pre-existing path into one we subsequently treat as trusted.
  while [ "$module_probe" != / ]; do
    [ ! -L "$module_probe" ] || { bootstrap_log 'fatal: symlinked module directory'; exit 1; }
    if [ -e "$module_probe" ]; then
      [ -d "$module_probe" ] || exit 1
      case "$module_probe" in
        "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"/*)
          [ "$(installer_metadata_value "$module_probe" uid)" = "$(id -u)" ] || exit 1
          case "$(installer_metadata_value "$module_probe" mode)" in
            700|500|750|550|755|555) ;;
            *) bootstrap_log 'fatal: writable or unsafe module directory'; exit 1 ;;
          esac ;;
      esac
    fi
    module_probe=${module_probe%/*}; [ -n "$module_probe" ] || module_probe=/
  done
  if [ -e "$module_destination" ] || [ -L "$module_destination" ]; then
    [ -f "$module_destination" ] && [ ! -L "$module_destination" ] || exit 1
    [ "$(installer_metadata_value "$module_destination" uid)" = "$(id -u)" ] || exit 1
    [ "$(installer_metadata_value "$module_destination" links)" = 1 ] || exit 1
  fi
  mkdir -p "$module_parent" || exit 1
  # Common and runtime modules follow the same checked publication path. The
  # bootstrap fallback handles definition-only dependencies before the higher
  # library is ready; no module may bypass path validation merely by its root.
  bootstrap_fetch_seed_file "$module_seed" "$module_relative" "$module_destination" 0600 'installer module' || exit "$?"
  [ -s "$module_destination" ] && [ ! -L "$module_destination" ] || exit 1
  [ "$(installer_metadata_value "$module_destination" mode)" = 600 ] || exit 1
  printf '%s\n' "$module_destination"
)

# Data/parser assets use a separate resolver. They are authenticated payload
# members, never shell modules: callers may pass the returned path only to the
# parser named by the exact allow-list below. Keep this list narrow until a
# future asset has its own bounded grammar and manifest contract.
bootstrap_parser_asset_path() (
  set -eu
  umask 077
  [ "$#" -eq 1 ] || { bootstrap_log 'fatal: one parser asset path is required'; exit 1; }
  parser_relative=$1
  case "$parser_relative" in
    "${DIR_SCRIPTS_COMMON}/credential-data.awk") ;;
    *) bootstrap_log "fatal: unsupported parser asset path: $parser_relative"; exit 1 ;;
  esac
  bootstrap_load_source_library "${INSTALLER_SOURCE_ROOT:-}" || exit 1
  source_validate_relative "$parser_relative" || exit 1
  parser_seed=$(bootstrap_require_seed_base "") || exit 1
  [ -f "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/bootstrap/payload.ready" ] || {
    bootstrap_log 'fatal: parser asset loading requires the authenticated payload'; exit 1;
  }
  parser_manifest=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/bootstrap/payload.manifest
  [ -f "$parser_manifest" ] && [ ! -L "$parser_manifest" ] || {
    bootstrap_log 'fatal: authenticated payload manifest is unavailable for parser asset'; exit 1;
  }
  parser_record=$(awk -F '\t' -v wanted="$parser_relative" '
    NR == 1 { if ($0 != "format=3") exit 2; next }
    NF == 3 && $3 == wanted { if (++count != 1) exit 2; print $1 "\t" $2 }
    END { if (count != 1) exit 1 }
  ' "$parser_manifest") || {
    bootstrap_log 'fatal: parser asset is absent from the authenticated payload manifest'; exit 1;
  }
  parser_size=${parser_record%%	*}
  parser_digest=${parser_record#*	}
  case "$parser_size:$parser_digest" in
    ''|*[!0-9a-f:]*) bootstrap_log 'fatal: parser asset manifest record is malformed'; exit 1 ;;
  esac
  [ "$parser_size" -le 65536 ] && [ "${#parser_digest}" -eq 64 ] || {
    bootstrap_log 'fatal: parser asset exceeds its size or digest bound'; exit 1;
  }
  installer_lifecycle_paths || { bootstrap_log 'fatal: unsafe parser runtime directory'; exit 1; }
  parser_destination="${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/bootstrap/data/$parser_relative"
  parser_parent=${parser_destination%/*}
  parser_probe=$parser_parent
  while [ "$parser_probe" != / ]; do
    [ ! -L "$parser_probe" ] || { bootstrap_log 'fatal: symlinked parser directory'; exit 1; }
    if [ -e "$parser_probe" ]; then
      [ -d "$parser_probe" ] || exit 1
      case "$parser_probe" in
        "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"/*)
          [ "$(installer_metadata_value "$parser_probe" uid)" = "$(id -u)" ] || exit 1
          case "$(installer_metadata_value "$parser_probe" mode)" in
            700|500|750|550|755|555) ;;
            *) bootstrap_log 'fatal: writable or unsafe parser directory'; exit 1 ;;
          esac
          ;;
      esac
    fi
    parser_probe=${parser_probe%/*}; [ -n "$parser_probe" ] || parser_probe=/
  done
  if [ -e "$parser_destination" ] || [ -L "$parser_destination" ]; then
    [ -f "$parser_destination" ] && [ ! -L "$parser_destination" ] || exit 1
    [ "$(installer_metadata_value "$parser_destination" uid)" = "$(id -u)" ] || exit 1
    [ "$(installer_metadata_value "$parser_destination" links)" -eq 1 ] || exit 1
    [ "$(installer_metadata_value "$parser_destination" mode)" = 600 ] || exit 1
  fi
  mkdir -p "$parser_parent" || exit 1
  bootstrap_fetch_seed_file "$parser_seed" "$parser_relative" "$parser_destination" 0600 'parser asset' || exit "$?"
  [ -f "$parser_destination" ] && [ ! -L "$parser_destination" ] || exit 1
  [ "$(installer_metadata_value "$parser_destination" uid)" = "$(id -u)" ] || exit 1
  [ "$(installer_metadata_value "$parser_destination" links)" -eq 1 ] || exit 1
  [ "$(installer_metadata_value "$parser_destination" mode)" = 600 ] || exit 1
  [ "$(wc -c <"$parser_destination")" -eq "$parser_size" ] || exit 1
  parser_actual=$(source_hash <"$parser_destination") || exit 1
  [ "${parser_actual%% *}" = "$parser_digest" ] || {
    bootstrap_log 'fatal: parser asset digest differs from the authenticated manifest'; exit 1;
  }
  printf '%s\n' "$parser_destination"
)

bootstrap_source_module() {
  # Function positional parameters are local to this call in dash and ash.
  # Modules define functions/constants only. Phase actions run in the explicit
  # entrypoint, after every dependency has loaded successfully.
  bootstrap_module_source_path=$(bootstrap_module_path "$1") || return "$?"
  set -- "$bootstrap_module_source_path"
  unset bootstrap_module_source_path
  [ -n "$1" ] || return 1
  # shellcheck disable=SC1090
  . "$1"
}

bootstrap_source_common_lib() {
  requested_seed_base=${1:-}
  common_lib_path=${2:-$(bootstrap_phase_runner_path common-lib.sh)} || return $?
  # bootstrap_module_path uses the authenticated lifecycle helpers for its
  # private staging checks. Load source.sh in this caller shell before the
  # first module is resolved; bootstrap_fetch_seed_file loads it in a
  # subshell and cannot provide those functions to common-lib.sh.
  bootstrap_load_source_library "${INSTALLER_SOURCE_ROOT:-}" || return $?
  seed_base=$(bootstrap_require_seed_base "$requested_seed_base") || return $?
  bootstrap_persist_seed_source "$seed_base" || return $?
  bootstrap_ensure_repo_env "$seed_base" || return $?

  common_lib_source=$(bootstrap_repo_file_value FILE_COMMON_LIB) || return $?
  bootstrap_fetch_seed_file "$seed_base" "$common_lib_source" "$common_lib_path" 0600 "common library" || return $?
  # shellcheck disable=SC1090,SC1091
  . "$common_lib_path" || return $?
}

bootstrap_source_common_support_libs() {
  requested_seed_base=${1:-}
  tmp_env_dir=$2
  shift 2

  seed_base=$(bootstrap_require_seed_base "$requested_seed_base") || return $?
  bootstrap_persist_seed_source "$seed_base" || return $?
  bootstrap_ensure_repo_env "$seed_base" || return $?
  install -d -m 0700 "$tmp_env_dir" || return $?

  for lib_name in "$@"; do
    case "$lib_name" in
      fetch)
        src=$(bootstrap_repo_file_value FILE_COMMON_FETCH) || return $?
        dest="${tmp_env_dir}/fetch.sh"
        ;;
      hook)
        src=$(bootstrap_repo_file_value FILE_COMMON_HOOK) || return $?
        dest="${tmp_env_dir}/hook.sh"
        ;;
      target)
        src=$(bootstrap_repo_file_value FILE_COMMON_TARGET) || return $?
        dest="${tmp_env_dir}/target-common.sh"
        ;;
      ssh)
        src=$(bootstrap_repo_file_value FILE_COMMON_SSH) || return $?
        dest="${tmp_env_dir}/ssh.sh"
        ;;
      *)
        bootstrap_fatal "unsupported installer support library: ${lib_name}"
        ;;
    esac
    bootstrap_fetch_seed_file "$seed_base" "$src" "$dest" 0600 "shared helper" || return $?
    # shellcheck disable=SC1090,SC1091
    . "$dest" || return $?
  done
}

bootstrap_run_preseed_phase() {
  phase=$1
  requested_seed_base=${2:-}
  seed_base=$(bootstrap_require_seed_base "$requested_seed_base") || return $?
  bootstrap_ensure_repo_env "$seed_base" || return $?

  case "$phase" in
    prepare-context|apply)
      runner_src=$(bootstrap_repo_file_value FILE_PRESEED_ANSWERS) || return $?
      runner=${3:-$(bootstrap_phase_runner_path preseed-answers.sh)} || return $?
      set -- "$phase" "$seed_base"
      ;;
    early)
      runner_src=$(bootstrap_repo_file_value FILE_EARLY_DISPATCH) || return $?
      runner=${3:-$(bootstrap_phase_runner_path early-dispatch.sh)} || return $?
      set -- "$seed_base"
      ;;
    partman)
      runner_src=$(bootstrap_repo_file_value FILE_PARTMAN_DISPATCH) || return $?
      runner=${3:-$(bootstrap_phase_runner_path partman-dispatch.sh)} || return $?
      set -- "$seed_base"
      ;;
    late)
      runner_src=$(bootstrap_repo_file_value FILE_LATE_DISPATCH) || return $?
      runner=${3:-$(bootstrap_phase_runner_path late-dispatch.sh)} || return $?
      set -- "$seed_base"
      ;;
    *)
      bootstrap_fatal "unsupported preseed phase: ${phase}"
      ;;
  esac

  bootstrap_persist_seed_source "$seed_base" || return $?
  bootstrap_fetch_seed_file "$seed_base" "$runner_src" "$runner" 0755 "phase runner" || return $?
  bootstrap_log "info: invoking preseed phase ${phase}"
  INSTALLER_BOOTSTRAP_LIB=${INSTALLER_BOOTSTRAP_LIB:-$(bootstrap_lib_path)} "$runner" "$@"
}

bootstrap_load_source_library() {
  command -v source_fetch >/dev/null 2>&1 && return 0
  bootstrap_source_scripts_dir=${DIR_REPO_SCRIPTS:-scripts}
  bootstrap_source_common_dir=${DIR_SCRIPTS_COMMON:-${bootstrap_source_scripts_dir}/common}
  for source_library in "${INSTALLER_SOURCE_LIBRARY:-}" \
      "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/bootstrap/source.sh" \
      "${INSTALLER_SOURCE_ROOT:-/nonexistent}/${bootstrap_source_common_dir}/source.sh" \
      "${1:-/nonexistent}/${bootstrap_source_common_dir}/source.sh"; do
    [ -n "$source_library" ] && [ -s "$source_library" ] || continue
    # shellcheck disable=SC1090
    . "$source_library" || return $?
    command -v source_fetch >/dev/null 2>&1 || return 1
    return 0
  done
  bootstrap_fatal 'repository transport is missing; start with the generated preseed.cfg'
}
