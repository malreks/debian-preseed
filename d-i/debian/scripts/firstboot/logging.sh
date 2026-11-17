#!/bin/sh
# Shared first-boot logging filter. This file is sourced.

if [ -r __INSTALLER_PATH_DIR_ETC__/system-runtime.conf ]; then
  # shellcheck disable=SC1091
  . __INSTALLER_PATH_DIR_ETC__/system-runtime.conf
fi

firstboot_log_level_canonical() {
  case "${1:-info}" in
    debug|DEBUG) printf '%s\n' debug ;;
    info|INFO) printf '%s\n' info ;;
    warn|WARN|warning|WARNING) printf '%s\n' warning ;;
    error|ERROR|fatal|FATAL) printf '%s\n' error ;;
    none|NONE) printf '%s\n' none ;;
    *) printf '%s\n' info ;;
  esac
}

firstboot_log_level_value() {
  case "${1:-info}" in
    debug|DEBUG) printf '%s\n' 10 ;;
    warn|WARN|warning|WARNING) printf '%s\n' 30 ;;
    error|ERROR|fatal|FATAL) printf '%s\n' 40 ;;
    none|NONE) printf '%s\n' 99 ;;
    *) printf '%s\n' 20 ;;
  esac
}

firstboot_log_should_emit() {
  case "${1:-info}" in error|ERROR|fatal|FATAL) return 0 ;; esac
  case "${SYSTEMD_LOG_LEVEL:-error}" in none|NONE) return 1 ;; esac
  requested_value=$(firstboot_log_level_value "${1:-info}")
  active_value=$(firstboot_log_level_value "${SYSTEMD_LOG_LEVEL:-error}")
  [ "$requested_value" -ge "$active_value" ]
}

log_line() {
  stage=$1
  level=$2
  component=$3
  shift 3
  level=$(firstboot_log_level_canonical "$level")
  firstboot_log_should_emit "$level" || return 0
  printf '%s stage=%s level=%s component=%s %s\n' \
    "$(timestamp)" "$stage" "$level" "$component" "$*" >>"$FIRSTBOOT_LOG_FILE"
}

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ' 2>__INSTALLER_PATH_DIR_DEV__/null || printf '%s\n' unknown-time
}

capture() {
  output_name=$1
  shift
  output_file="${FIRSTBOOT_DATA_DIR}/${output_name}"
  {
    printf '# command:'
    for arg in "$@"; do
      printf ' %s' "$arg"
    done
    printf '\n'
    timeout --signal=TERM --kill-after=2s 20s "$@"
  } >"$output_file" 2>&1 || printf 'status=%s\n' "$?" >>"$output_file"
  chmod 0600 "$output_file" 2>__INSTALLER_PATH_DIR_DEV__/null || true
}
