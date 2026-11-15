#!/bin/sh
set -eu

RUNTIME_DIR=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
BOOTSTRAP_LIB=${INSTALLER_BOOTSTRAP_LIB:-${RUNTIME_DIR}/bootstrap/bootstrap.sh}
OS_PROBER_MARKER=INSTALLER_TEMPORARY_FAKE_OS_PROBER_V1

temporary_os_prober_fatal() {
  temporary_os_prober_message=$(printf '%s' "$*" | tr '\r\n\t' '   ')
  if command -v installer_error >/dev/null 2>&1; then
    installer_error "temporary os-prober: ${temporary_os_prober_message}"
  else
    printf '[pre-pkgsel:temporary-os-prober] fatal: %s\n' "$temporary_os_prober_message" >&2
    if [ -c /dev/tty4 ] && [ -w /dev/tty4 ]; then
      printf '[pre-pkgsel:temporary-os-prober] fatal: %s\n' "$temporary_os_prober_message" >/dev/tty4 || :
    fi
    if command -v logger >/dev/null 2>&1; then
      logger -t preseed-temporary-os-prober "fatal: $temporary_os_prober_message" 2>/dev/null || :
    fi
  fi
  exit 1
}

[ -s "$BOOTSTRAP_LIB" ] ||
  temporary_os_prober_fatal "installer bootstrap library is unavailable: ${BOOTSTRAP_LIB}"
# shellcheck disable=SC1090,SC1091
. "$BOOTSTRAP_LIB"
bootstrap_source_common_lib ""
installer_operation_context_repo FILE_INST_PREPKG_88TEMPORARY_OS_PROBER 29 temporary_os_prober
SEED_BASE=$(installer_seed_base "")
installer_persist_seed_source "$SEED_BASE"
installer_ensure_context_loaded "$SEED_BASE"

if ! installer_multiboot_profile_selected; then
  installer_info "skipping temporary installer os-prober shim for a single-system profile"
  exit 0
fi

[ -d "$DIR_INSTALLER_USR_BIN" ] ||
  temporary_os_prober_fatal "installer /usr/bin is unavailable"
install -d -m 0700 "$(dirname "$FILE_INSTALLER_OS_PROBER_STATE")"

if [ -e "$FILE_INSTALLER_OS_PROBER_STATE" ]; then
  [ -f "$FILE_INSTALLER_OS_PROBER_STATE" ] ||
    temporary_os_prober_fatal "temporary os-prober state is not a regular file"
  state_marker=$(cat "$FILE_INSTALLER_OS_PROBER_STATE" 2>/dev/null || true)
  [ "$state_marker" = "$OS_PROBER_MARKER" ] ||
    temporary_os_prober_fatal "temporary os-prober state marker is invalid"
fi

if [ -e "$FILE_INSTALLER_OS_PROBER_REAL" ]; then
  [ -f "$FILE_INSTALLER_OS_PROBER_REAL" ] && [ -x "$FILE_INSTALLER_OS_PROBER_REAL" ] ||
    temporary_os_prober_fatal "preserved installer os-prober is not an executable regular file"
  if grep -Fqx "# ${OS_PROBER_MARKER}" "$FILE_INSTALLER_OS_PROBER_REAL"; then
    temporary_os_prober_fatal "preserved installer os-prober unexpectedly contains the shim marker"
  fi
else
  [ -f "$FILE_INSTALLER_OS_PROBER" ] && [ -x "$FILE_INSTALLER_OS_PROBER" ] ||
    temporary_os_prober_fatal "installer os-prober executable is unavailable: ${FILE_INSTALLER_OS_PROBER}"
  if grep -Fqx "# ${OS_PROBER_MARKER}" "$FILE_INSTALLER_OS_PROBER"; then
    temporary_os_prober_fatal "temporary os-prober shim exists without a preserved real executable"
  fi
  mv "$FILE_INSTALLER_OS_PROBER" "$FILE_INSTALLER_OS_PROBER_REAL"
fi

if [ -e "$FILE_INSTALLER_OS_PROBER" ]; then
  if [ ! -f "$FILE_INSTALLER_OS_PROBER" ] ||
     ! grep -Fqx "# ${OS_PROBER_MARKER}" "$FILE_INSTALLER_OS_PROBER"; then
    temporary_os_prober_fatal "refusing to replace an unexpected installer os-prober file"
  fi
fi

shim_tmp="${FILE_INSTALLER_OS_PROBER}.tmp.$$"
state_tmp="${FILE_INSTALLER_OS_PROBER_STATE}.tmp.$$"
cleanup_temporary_os_prober_files() {
  rm -f "$shim_tmp" "$state_tmp"
}
trap cleanup_temporary_os_prober_files EXIT HUP INT TERM

cat >"$shim_tmp" <<EOF_SHIM
#!/bin/sh
# ${OS_PROBER_MARKER}
# Debian Installer probing is deferred to the controlled target-side
# dual-boot GRUB pass in preseed/late_command.
exit 0
EOF_SHIM
chmod 0755 "$shim_tmp"
mv "$shim_tmp" "$FILE_INSTALLER_OS_PROBER"

printf '%s\n' "$OS_PROBER_MARKER" >"$state_tmp"
chmod 0600 "$state_tmp"
mv "$state_tmp" "$FILE_INSTALLER_OS_PROBER_STATE"

trap - EXIT HUP INT TERM
installer_info "installed temporary success-only installer os-prober shim; target os-prober remains unchanged"
