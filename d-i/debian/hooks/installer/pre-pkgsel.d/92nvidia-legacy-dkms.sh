#!/bin/sh
set -eu

RUNTIME_DIR=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
BOOTSTRAP_LIB=${INSTALLER_BOOTSTRAP_LIB:-${RUNTIME_DIR}/bootstrap/bootstrap.sh}
TMP_ENV_DIR=
LOG=

nvidia_legacy_prepkgsel_fatal() {
  nvidia_legacy_prepkgsel_message=$(printf '%s' "$*" | tr '\r\n\t' '   ')
  if command -v installer_error >/dev/null 2>&1; then
    installer_error "NVIDIA legacy pre-pkgsel: ${nvidia_legacy_prepkgsel_message}"
  else
    printf '[pre-pkgsel:nvidia-legacy] fatal: %s\n' "$nvidia_legacy_prepkgsel_message" >&2
    if [ -c /dev/tty4 ] && [ -w /dev/tty4 ]; then
      printf '[pre-pkgsel:nvidia-legacy] fatal: %s\n' "$nvidia_legacy_prepkgsel_message" >/dev/tty4 || :
    fi
    if command -v logger >/dev/null 2>&1; then
      logger -t preseed-nvidia-legacy "fatal: $nvidia_legacy_prepkgsel_message" 2>/dev/null || :
    fi
  fi
  exit 1
}

[ -s "$BOOTSTRAP_LIB" ] || nvidia_legacy_prepkgsel_fatal "installer bootstrap library is unavailable: ${BOOTSTRAP_LIB}"
# shellcheck disable=SC1090,SC1091
. "$BOOTSTRAP_LIB"
bootstrap_source_common_lib ""
TMP_ENV_DIR=${INSTALLER_NVIDIA_PREPKGSEL_ENV_DIR:-${DIR_INSTALLER_PRE_PKGSEL_ENV}/nvidia-legacy}

LOG="$(installer_runtime_log_file)"
INSTALLER_DEBUG_LOGS=1
INSTALLER_LOG_LEVEL=debug
export INSTALLER_DEBUG_LOGS INSTALLER_LOG_LEVEL
installer_init_log_file "$LOG" "" "nvidia legacy pre-pkgsel" nvidia-legacy package_install
installer_operation_context_repo hooks/installer/pre-pkgsel.d/92nvidia-legacy-dkms.sh 36 nvidia_legacy_prepkgsel
trap 'installer_finalize_log "$?"' 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

SEED_BASE=$(installer_seed_base "")
installer_persist_seed_source "$SEED_BASE"
installer_ensure_context_loaded "$SEED_BASE"

if ! installer_nvidia_legacy_selected 2>/dev/null; then
  installer_info "skipping NVIDIA legacy DKMS bootstrap because optional/nvidia-legacy is not selected"
  exit 0
fi

if ! installer_nvidia_legacy_gpu_detected 2>/dev/null; then
  nvidia_legacy_prepkgsel_fatal "legacy NVIDIA requires exactly one approved Quadro P520 display adapter (10de:1d34)"
fi

install -d -m 0700 "$TMP_ENV_DIR"
bootstrap_source_common_support_libs "$SEED_BASE" "$TMP_ENV_DIR" fetch hook target || {
  nvidia_legacy_prepkgsel_fatal "failed to source shared installer helper libraries"
}

# Target filesystem roots belong to the composed host environment; the
# installer di.env above owns only installer paths such as TARGET_ROOT.
HOST_PROFILE=$(installer_resolve_host_profile "")
[ -n "$HOST_PROFILE" ] ||
  nvidia_legacy_prepkgsel_fatal "selected host profile is unavailable"
PREPKGSEL_HOST_ENV="${TMP_ENV_DIR}/host.env"
installer_fetch_host_env "$SEED_BASE" "$HOST_PROFILE" "$PREPKGSEL_HOST_ENV" 0600 ||
  nvidia_legacy_prepkgsel_fatal "failed to fetch the validated host environment"
# shellcheck disable=SC1090,SC1091
installer_load_data_env "$PREPKGSEL_HOST_ENV" ||
  nvidia_legacy_prepkgsel_fatal "failed to load the validated host environment"

[ -n "${TARGET_ROOT:-}" ] ||
  nvidia_legacy_prepkgsel_fatal "installer target root is unavailable"
[ -n "${DIR_USR_SBIN:-}" ] ||
  nvidia_legacy_prepkgsel_fatal "target runtime path DIR_USR_SBIN is unavailable"

nvidia_legacy_install_initramfs_guard() {
  [ -n "${DIR_BOOT:-}" ] && [ -n "${DIR_LIB:-}" ] ||
    nvidia_legacy_prepkgsel_fatal "target boot and library paths are unavailable"
  nvidia_installer_kernel=$(uname -r 2>/dev/null || true)
  case "$nvidia_installer_kernel" in
    ''|*[!A-Za-z0-9.+_-]*)
      nvidia_legacy_prepkgsel_fatal "installer kernel release is unavailable or invalid" ;;
  esac
  nvidia_initramfs_path="${TARGET_ROOT}${FILE_INSTALLER_UPDATE_INITRAMFS}"
  nvidia_initramfs_real="${TARGET_ROOT}${FILE_INSTALLER_UPDATE_INITRAMFS_REAL}"
  installer_apt_safe_path "$nvidia_initramfs_path" &&
    installer_apt_safe_path "$nvidia_initramfs_real" ||
    nvidia_legacy_prepkgsel_fatal "target initramfs entrypoint ancestry is unsafe"
  nvidia_initramfs_diversion=$(
    chroot "$TARGET_ROOT" "$FILE_INSTALLER_DPKG_DIVERT" --truename "$FILE_INSTALLER_UPDATE_INITRAMFS"
  ) || nvidia_legacy_prepkgsel_fatal "cannot inspect the target initramfs diversion"
  case "$nvidia_initramfs_diversion" in
    "$FILE_INSTALLER_UPDATE_INITRAMFS")
      [ -f "$nvidia_initramfs_path" ] && [ -x "$nvidia_initramfs_path" ] &&
        [ ! -L "$nvidia_initramfs_path" ] &&
        [ ! -e "$nvidia_initramfs_real" ] && [ ! -L "$nvidia_initramfs_real" ] ||
        nvidia_legacy_prepkgsel_fatal "target initramfs executable or diversion destination is unsafe"
      if grep -Fqx '# INSTALLER_TEMPORARY_NVIDIA_INITRAMFS_GUARD_V1' "$nvidia_initramfs_path"; then
        nvidia_legacy_prepkgsel_fatal "initramfs guard exists without its expected diversion"
      fi
      run_in_target "reserve temporary NVIDIA initramfs guard" \
        "$FILE_INSTALLER_DPKG_DIVERT" --quiet --local --rename \
        --divert "$FILE_INSTALLER_UPDATE_INITRAMFS_REAL" --add "$FILE_INSTALLER_UPDATE_INITRAMFS"
      ;;
    "$FILE_INSTALLER_UPDATE_INITRAMFS_REAL")
      if [ -e "$nvidia_initramfs_path" ] || [ -L "$nvidia_initramfs_path" ]; then
        [ -f "$nvidia_initramfs_path" ] && [ ! -L "$nvidia_initramfs_path" ] &&
          grep -Fqx '# INSTALLER_TEMPORARY_NVIDIA_INITRAMFS_GUARD_V1' "$nvidia_initramfs_path" ||
          nvidia_legacy_prepkgsel_fatal "refusing to replace an unexpected initramfs guard"
      fi
      ;;
    *) nvidia_legacy_prepkgsel_fatal "target initramfs entrypoint has an unexpected diversion" ;;
  esac
  [ -f "$nvidia_initramfs_real" ] && [ -x "$nvidia_initramfs_real" ] &&
    [ ! -L "$nvidia_initramfs_real" ] ||
    nvidia_legacy_prepkgsel_fatal "preserved target initramfs executable is unavailable"
  if grep -Fqx '# INSTALLER_TEMPORARY_NVIDIA_INITRAMFS_GUARD_V1' "$nvidia_initramfs_real"; then
    nvidia_legacy_prepkgsel_fatal "preserved target initramfs executable unexpectedly contains the guard"
  fi
  # NVIDIA's Ubuntu-derived maintainer scripts explicitly update uname -r in
  # a chroot. That is the d-i kernel, which has no target modules. Keep normal
  # updates and target-kernel requests intact; finish-install removes this guard.
  cat >"$TMP_ENV_DIR/initramfs-guard" <<EOF_INITRAMFS_GUARD
#!/bin/sh
# INSTALLER_TEMPORARY_NVIDIA_INITRAMFS_GUARD_V1
set -eu
case "\${DPKG_MAINTSCRIPT_PACKAGE:-}" in
  nvidia-kernel-common-580|nvidia-kernel-dkms-580|nvidia-dkms-580)
    if [ "\$#" -eq 3 ] && [ "\$1" = -u ] && [ "\$2" = -k ] &&
       [ "\$3" = '$nvidia_installer_kernel' ] &&
       [ ! -e '${DIR_LIB}/modules/'"\$3" ] && [ ! -L '${DIR_LIB}/modules/'"\$3" ] &&
       [ ! -e '${DIR_BOOT}/vmlinuz-'"\$3" ] && [ ! -L '${DIR_BOOT}/vmlinuz-'"\$3" ]; then
      printf 'update-initramfs: skipping NVIDIA request for installer-only kernel %s\n' "\$3" >&2
      exit 0
    fi
    ;;
esac
exec '$FILE_INSTALLER_UPDATE_INITRAMFS_REAL' "\$@"
EOF_INITRAMFS_GUARD
  installer_copy_path_with_mode "$TMP_ENV_DIR/initramfs-guard" "$nvidia_initramfs_path" 0755 \
    "temporary NVIDIA initramfs guard"
  installer_info "installed temporary NVIDIA initramfs guard for installer kernel ${nvidia_installer_kernel}"
  unset nvidia_installer_kernel nvidia_initramfs_path nvidia_initramfs_real nvidia_initramfs_diversion
}

nvidia_legacy_install_initramfs_guard

# PikaOS 580.196.07-101pika2 already carries the Linux 7.2+ compatibility
# implementation in its DKMS source: the process-name conversion uses the
# full-size strscpy API, and nvidia-drm selects the native drm_atomic_commit
# type/lifetime/callback interface through its conftest.  Do not rewrite the
# vendor source tree or divert /usr/sbin/dkms here.  The package's normal DKMS
# maintainer hooks build the source against each installed kernel; the persistent
# Secure Boot framework signs the resulting out-of-tree modules separately.
installer_info 'using Pika NVIDIA 580 native Linux 7.2+ DKMS compatibility; no installer source patch or DKMS diversion'
