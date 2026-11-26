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

# Capture a machine-readable JSON result without adding human diagnostics to
# its byte stream.  The candidate is validated before publication and both the
# JSON result and any stderr/status record are published with atomic renames.
capture_json() {
  output_name=$1
  shift
  output_file="${FIRSTBOOT_DATA_DIR}/${output_name}"
  diagnostic_file="${output_file}.diagnostic"
  # Invalidate a prior result before the fallible capture so a failed retry
  # cannot leave stale machine-readable evidence looking current.
  rm -f -- "$output_file" "$diagnostic_file" || return 1
  candidate=$(mktemp "${output_file}.tmp.XXXXXX") || return 1
  diagnostic_candidate=$(mktemp "${diagnostic_file}.tmp.XXXXXX") || {
    rm -f -- "$candidate"
    return 1
  }

  capture_status=0
  if timeout --signal=TERM --kill-after=2s 20s "$@" \
      >"$candidate" 2>"$diagnostic_candidate"; then
    capture_status=0
  else
    capture_status=$?
  fi

  valid_json=0
  if [ "$capture_status" -eq 0 ] &&
      __INSTALLER_PATH_DIR_USR_BIN__/python3 -I -B - "$candidate" \
        >__INSTALLER_PATH_DIR_DEV__/null 2>&1 <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
if not isinstance(value, (dict, list)):
    raise ValueError("JSON document must contain an object or array")
PY
  then
    valid_json=1
  fi

  if [ "$valid_json" -eq 1 ]; then
    chmod 0600 "$candidate" || {
      rm -f -- "$candidate" "$diagnostic_candidate"
      return 1
    }
    mv -fT -- "$candidate" "$output_file" || {
      rm -f -- "$candidate" "$diagnostic_candidate"
      return 1
    }
    if [ -s "$diagnostic_candidate" ]; then
      printf 'status=0\n' >>"$diagnostic_candidate" || {
        rm -f -- "$diagnostic_candidate"
        return 1
      }
      chmod 0600 "$diagnostic_candidate" &&
        mv -fT -- "$diagnostic_candidate" "$diagnostic_file" || {
          rm -f -- "$diagnostic_candidate"
          return 1
        }
    else
      rm -f -- "$diagnostic_candidate" "$diagnostic_file"
    fi
    log_line capture info firstboot \
      "output=${output_name} command=${1:-unknown} status=0 json=valid"
    return 0
  fi

  printf 'status=%s\n' "$capture_status" >>"$diagnostic_candidate" || {
    rm -f -- "$candidate" "$diagnostic_candidate"
    return 1
  }
  rm -f -- "$candidate"
  chmod 0600 "$diagnostic_candidate" &&
    mv -fT -- "$diagnostic_candidate" "$diagnostic_file" || {
      rm -f -- "$diagnostic_candidate"
      return 1
    }
  log_line capture error firstboot \
    "output=${output_name} command=${1:-unknown} status=${capture_status} json=invalid"
  return 1
}
