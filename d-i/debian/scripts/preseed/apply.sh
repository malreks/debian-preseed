#!/bin/sh
set -eu
boot=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/bootstrap
[ -f "$boot/preflight.ok" ] && [ -x "$boot/preseed-bootstrap-entry.sh" ] || {
  apply_message='repository preflight incomplete before applying answers'
  printf '[preseed-apply] fatal: %s\n' "$apply_message" >&2
  if [ -c /dev/tty4 ] && [ -w /dev/tty4 ]; then
    printf '[preseed-apply] fatal: %s\n' "$apply_message" >/dev/tty4 || :
  fi
  if [ -c /dev/console ] && [ -w /dev/console ]; then
    printf '[preseed-apply] fatal: %s\n' "$apply_message" >/dev/console || :
  fi
  if command -v logger >/dev/null 2>&1; then
    logger -t preseed-apply "fatal: $apply_message" 2>/dev/null || :
  fi
  exit 1
}
exec "$boot/preseed-bootstrap-entry.sh" apply
