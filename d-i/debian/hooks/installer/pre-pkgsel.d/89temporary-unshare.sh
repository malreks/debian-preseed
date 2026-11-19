#!/bin/sh
set -eu

RUNTIME_DIR=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
BOOTSTRAP_LIB=${INSTALLER_BOOTSTRAP_LIB:-${RUNTIME_DIR}/bootstrap/bootstrap.sh}
TARGET=
UNSHARE_MARKER=INSTALLER_TEMPORARY_FAKE_UNSHARE_V1

temporary_unshare_fatal() {
  temporary_unshare_message=$(printf '%s' "$*" | tr '\r\n\t' '   ')
  if command -v installer_error >/dev/null 2>&1; then
    installer_error "temporary unshare: ${temporary_unshare_message}"
  else
    printf '[pre-pkgsel:temporary-unshare] fatal: %s\n' "$temporary_unshare_message" >&2
    if [ -c /dev/tty4 ] && [ -w /dev/tty4 ]; then
      printf '[pre-pkgsel:temporary-unshare] fatal: %s\n' "$temporary_unshare_message" >/dev/tty4 || :
    fi
    if command -v logger >/dev/null 2>&1; then
      logger -t preseed-temporary-unshare "fatal: $temporary_unshare_message" 2>/dev/null || :
    fi
  fi
  exit 1
}

[ -s "$BOOTSTRAP_LIB" ] ||
  temporary_unshare_fatal "installer bootstrap library is unavailable: ${BOOTSTRAP_LIB}"
# shellcheck disable=SC1090,SC1091
. "$BOOTSTRAP_LIB"
bootstrap_source_common_lib ""
installer_operation_context_repo hooks/installer/pre-pkgsel.d/89temporary-unshare.sh 30 temporary_unshare
TARGET=${INSTALLER_TARGET_DIR:-${TARGET_ROOT:-}}
case "$TARGET" in
  /*) ;;
  *) temporary_unshare_fatal "installer target must be an absolute path: ${TARGET:-unset}" ;;
esac
[ "$TARGET" != / ] || temporary_unshare_fatal "refusing to modify the installer root filesystem"

target_unshare="${TARGET}${FILE_INSTALLER_UNSHARE}"
target_divert="${TARGET}${FILE_INSTALLER_UNSHARE_REAL}"
target_state="${TARGET}${FILE_INSTALLER_UNSHARE_STATE}"
target_dpkg_divert="${TARGET}${FILE_INSTALLER_DPKG_DIVERT}"

[ -d "${TARGET}${DIR_INSTALLER_USR_BIN}" ] ||
  temporary_unshare_fatal "target /usr/bin is unavailable"
[ -x "$target_dpkg_divert" ] ||
  temporary_unshare_fatal "target dpkg-divert is unavailable: /usr/bin/dpkg-divert"
command -v chroot >/dev/null 2>&1 ||
  temporary_unshare_fatal "installer chroot command is unavailable"

install -d -m 0700 "$(dirname "$target_state")"

if [ -e "$target_state" ]; then
  [ -f "$target_state" ] ||
    temporary_unshare_fatal "temporary unshare state is not a regular file"
  state_marker=$(cat "$target_state" 2>/dev/null || true)
  [ "$state_marker" = "$UNSHARE_MARKER" ] ||
    temporary_unshare_fatal "temporary unshare state marker is invalid"
fi

diversion_listing=$(
  chroot "$TARGET" "$FILE_INSTALLER_DPKG_DIVERT" --list "$FILE_INSTALLER_UNSHARE" 2>/dev/null || true
)
case "$diversion_listing" in
  '')
    [ -x "$target_unshare" ] ||
      temporary_unshare_fatal "target unshare executable is unavailable: ${FILE_INSTALLER_UNSHARE}"
    chroot "$TARGET" "$FILE_INSTALLER_DPKG_DIVERT" \
      --quiet \
      --local \
      --rename \
      --divert "$FILE_INSTALLER_UNSHARE_REAL" \
      --add "$FILE_INSTALLER_UNSHARE" ||
      temporary_unshare_fatal "failed to divert the target unshare executable"
    ;;
  *"$FILE_INSTALLER_UNSHARE_REAL"*)
    ;;
  *)
    temporary_unshare_fatal "target unshare already has an unexpected diversion: $diversion_listing"
    ;;
esac

[ -x "$target_divert" ] ||
    temporary_unshare_fatal "diverted target unshare executable is unavailable: ${FILE_INSTALLER_UNSHARE_REAL}"

if [ -e "$target_unshare" ]; then
  if [ ! -f "$target_unshare" ] ||
     ! grep -Fqx "# ${UNSHARE_MARKER}" "$target_unshare"; then
    temporary_unshare_fatal "refusing to replace an unexpected target unshare file"
  fi
fi

shim_tmp="${target_unshare}.tmp.$$"
state_tmp="${target_state}.tmp.$$"
cleanup_temporary_unshare_files() {
  rm -f "$shim_tmp" "$state_tmp"
}
trap cleanup_temporary_unshare_files EXIT HUP INT TERM

cat >"$shim_tmp" <<EOF_SHIM
#!/bin/sh
# ${UNSHARE_MARKER}
exit 0
EOF_SHIM
chmod 0755 "$shim_tmp"
mv "$shim_tmp" "$target_unshare"

printf '%s\n' "$UNSHARE_MARKER" >"$state_tmp"
chmod 0600 "$state_tmp"
mv "$state_tmp" "$target_state"

trap - EXIT HUP INT TERM
printf '[pre-pkgsel:temporary-unshare] installed temporary success-only unshare shim at %s\n' \
  "$FILE_INSTALLER_UNSHARE" >&2
