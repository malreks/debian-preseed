#!/bin/sh
set -eu

PHASE=${1:-}
REQUESTED_SEED_BASE=${2:-}
RUNTIME_DIR=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
BOOTSTRAP_DIR=${RUNTIME_DIR}/bootstrap
LOG_FILE=${FILE_INSTALLER_LOG:-/tmp/installer.log}
BOOTSTRAP_HELPER=${BOOTSTRAP_DIR}/preseed-bootstrap-entry.sh
BOOTSTRAP_LIB=${INSTALLER_BOOTSTRAP_LIB:-${BOOTSTRAP_DIR}/bootstrap.sh}

phase_default_log() {
  case "${1:-}" in
    prepare-context|apply|early|partman|late) printf '%s\n' "$LOG_FILE" ;;
    *) return 1 ;;
  esac
}

usage() {
  printf 'usage: %s {prepare-context|apply|early|partman|late} [seed-base]\n' "${0##*/}" >&2
  exit 1
}

PHASE_LOG_PATH=$(phase_default_log "$PHASE" 2>/dev/null || true)
[ -n "$PHASE_LOG_PATH" ] || usage

if [ -x "$BOOTSTRAP_HELPER" ]; then
  exec "$BOOTSTRAP_HELPER" "$PHASE" "$PHASE_LOG_PATH" "$REQUESTED_SEED_BASE"
fi

if [ -s "$BOOTSTRAP_LIB" ]; then
  # shellcheck disable=SC1090,SC1091
  . "$BOOTSTRAP_LIB"
  bootstrap_run_preseed_phase "$PHASE" "$REQUESTED_SEED_BASE"
  exit $?
fi

dispatch_message=$(printf '%s' "local bootstrap entry helper is missing before preseed dispatch: ${BOOTSTRAP_HELPER}" | tr '\r\n\t' '   ')
printf '[preseed-dispatch] fatal: %s\n' "$dispatch_message" >&2
if [ -c /dev/tty4 ] && [ -w /dev/tty4 ]; then
  printf '[preseed-dispatch] fatal: %s\n' "$dispatch_message" >/dev/tty4 || :
fi
if [ -c /dev/console ] && [ -w /dev/console ]; then
  printf '[preseed-dispatch] fatal: %s\n' "$dispatch_message" >/dev/console || :
fi
if command -v logger >/dev/null 2>&1; then
  logger -t preseed-dispatch "fatal: $dispatch_message" 2>/dev/null || :
fi
exit 1
