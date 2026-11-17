#!/bin/sh
set -u

PATH=__INSTALLER_PATH_DIR_USR_LOCAL_SBIN__:__INSTALLER_PATH_DIR_USR_LOCAL_BIN__:__INSTALLER_PATH_DIR_USR_SBIN__:__INSTALLER_PATH_DIR_USR_BIN__:__INSTALLER_PATH_DIR_SBIN__:__INSTALLER_PATH_DIR_BIN__
export PATH
umask 077

FIRSTBOOT_LOG_DIR=${FIRSTBOOT_LOG_DIR:-__INSTALLER_PATH_DIR_FIRSTBOOT_LOG__}
FIRSTBOOT_DATA_DIR=${FIRSTBOOT_DATA_DIR:-${FIRSTBOOT_LOG_DIR}__INSTALLER_PATH_DIR_DATA__}
FIRSTBOOT_STATE_DIR=${FIRSTBOOT_STATE_DIR:-__INSTALLER_PATH_DIR_FIRSTBOOT_STATE__}
FIRSTBOOT_LOG_FILE=${FIRSTBOOT_LOG_FILE:-${FIRSTBOOT_LOG_DIR}/20-firstboot.log}
FIRSTBOOT_COMPLETE_FILE=${FIRSTBOOT_COMPLETE_FILE:-${FIRSTBOOT_STATE_DIR}/complete}
CLEANUP_LOG=${FIRSTBOOT_DATA_DIR}/cleanup.txt

mkdir -p "$FIRSTBOOT_LOG_DIR" "$FIRSTBOOT_DATA_DIR" "$FIRSTBOOT_STATE_DIR" 2>__INSTALLER_PATH_DIR_DEV__/null || exit 1
: >>"$FIRSTBOOT_LOG_FILE" 2>__INSTALLER_PATH_DIR_DEV__/null || exit 1
: >"$CLEANUP_LOG" 2>__INSTALLER_PATH_DIR_DEV__/null || exit 1
chmod 0600 "$CLEANUP_LOG" 2>__INSTALLER_PATH_DIR_DEV__/null || true

# The published shared library owns logging and bounded capture in every stage.
firstboot_logging="${FIRSTBOOT_SCRIPT_DIR:-__INSTALLER_PATH_DIR_FIRSTBOOT_LIB__}/logging.sh"
[ -f "$firstboot_logging" ] && [ ! -L "$firstboot_logging" ] || {
  printf '%s\n' 'fatal: shared firstboot logging library is unavailable' >&2
  exit 1
}
# shellcheck disable=SC1090
. "$firstboot_logging" || exit 1
unset firstboot_logging

write_complete_marker() {
  # Missing status is not proof of successful provisioning.
  [ "${FIRSTBOOT_OVERALL_STATUS:-unknown}" = 0 ] || return 1
  tmp_complete=$(mktemp "${FIRSTBOOT_COMPLETE_FILE}.tmp.XXXXXX") || return 1
  {
    printf 'timestamp=%s\n' "$(timestamp)"
    printf 'status=%s\n' "${FIRSTBOOT_OVERALL_STATUS:-unknown}"
    printf 'log_dir=%s\n' "$FIRSTBOOT_LOG_DIR"
  } >"$tmp_complete" 2>__INSTALLER_PATH_DIR_DEV__/null || return 1
  chmod 0600 "$tmp_complete" || return 1
  mv -fT -- "$tmp_complete" "$FIRSTBOOT_COMPLETE_FILE" 2>__INSTALLER_PATH_DIR_DEV__/null || {
    rm -f "$tmp_complete" 2>__INSTALLER_PATH_DIR_DEV__/null || true
    return 1
  }
}

tmp_complete=
trap '[ -z "$tmp_complete" ] || rm -f -- "$tmp_complete"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
log_line cleanup info cleanup "cleanup_start=true"

if ! write_complete_marker; then
  log_line cleanup error cleanup "complete_marker_write_failed=${FIRSTBOOT_COMPLETE_FILE}"
  exit 1
fi

{
  printf 'firstboot_status=%s\n' "${FIRSTBOOT_OVERALL_STATUS:-unknown}"
  printf 'complete_marker=%s\n' "$FIRSTBOOT_COMPLETE_FILE"
  printf 'automatic_cleanup_service=secondboot.service\n'
} >>"$CLEANUP_LOG"

log_line cleanup info cleanup "complete_marker=${FIRSTBOOT_COMPLETE_FILE} automatic_cleanup=secondboot.service"
exit 0
