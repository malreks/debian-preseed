#!/bin/sh
# Shared late_command Mullvad package helper. This file is sourced, not executed.

MULLVAD_RESOLVER_SOURCE=/tmp/installer-mullvad-resolv.conf
MULLVAD_RESOLVER_MAXIMUM_BYTES=65536
MULLVAD_RESOLVER_HOST=mullvad.net
MULLVAD_BITWARDEN_RESOLVER_HOST=bitwarden.com
MULLVAD_GITHUB_RESOLVER_HOST=github.com
MULLVAD_DNS_ATTEMPTS=5
MULLVAD_DNS_TIMEOUT_SECONDS=15
MULLVAD_DNS_RETRY_DELAY_SECONDS=2

mullvad_vpn_selected() {
  installer_class_selected role/desktop/full 2>__INSTALLER_PATH_DIR_DEV__/null && return 0
  installer_class_selected_any role/desktop/medium role/desktop/full 2>__INSTALLER_PATH_DIR_DEV__/null
}

mullvad_validate_target_path() {
  mullvad_path_label=$1
  mullvad_path_value=$2

  case "$mullvad_path_value" in
    /*) ;;
    *) installer_fatal "${mullvad_path_label} must be an absolute target path: ${mullvad_path_value:-unset}" ;;
  esac
  case "$mullvad_path_value" in
    /|*..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@%:+,-]*)
      installer_fatal "${mullvad_path_label} contains unsupported path syntax: $mullvad_path_value"
      ;;
  esac
}

mullvad_https_url_host() {
  mullvad_url=$1

  case "$mullvad_url" in
    https://*) mullvad_authority=${mullvad_url#https://} ;;
    *) return 1 ;;
  esac
  mullvad_authority=${mullvad_authority%%/*}
  case "$mullvad_authority" in
    ''|*@*|*\?*|*\#*|*\[*|*\]*) return 1 ;;
  esac

  mullvad_host=${mullvad_authority%%:*}
  if [ "$mullvad_authority" != "$mullvad_host" ]; then
    mullvad_port=${mullvad_authority#*:}
    [ "$mullvad_port" = 443 ] || return 1
  fi
  mullvad_host=$(printf '%s' "$mullvad_host" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
  case "$mullvad_host" in
    ''|.*|*.|*..*|*[!abcdefghijklmnopqrstuvwxyz0123456789.-]*) return 1 ;;
  esac
  printf '%s\n' "$mullvad_host"
}

mullvad_require_https_url() {
  mullvad_url_label=$1
  mullvad_url_value=$2
  mullvad_url_host=$(mullvad_https_url_host "$mullvad_url_value" 2>__INSTALLER_PATH_DIR_DEV__/null || true)

  [ -n "$mullvad_url_host" ] ||
    installer_fatal "${mullvad_url_label} is not a supported HTTPS URL: ${mullvad_url_value:-unset}"
}

mullvad_download_target_file() {
  mullvad_download_label=$1
  mullvad_download_url=$2
  mullvad_download_path=$3
  mullvad_download_partial="${mullvad_download_path}.part"
  mullvad_download_host_path="${TARGET_ROOT}${mullvad_download_path}"
  mullvad_download_partial_host_path="${TARGET_ROOT}${mullvad_download_partial}"

  mullvad_require_https_url "$mullvad_download_label URL" "$mullvad_download_url"
  mullvad_validate_target_path "$mullvad_download_label destination" "$mullvad_download_path"
  mullvad_validate_target_path "$mullvad_download_label partial destination" "$mullvad_download_partial"
  rm -f -- "$mullvad_download_host_path" "$mullvad_download_partial_host_path"

  mullvad_transfer_metadata=$(
    capture_in_target \
      "download ${mullvad_download_label}" \
      __INSTALLER_PATH_DIR_USR_BIN__/env -i \
        HOME=__INSTALLER_PATH_DIR_ROOT_HOME__ \
        LC_ALL=C \
        PATH=__INSTALLER_PATH_DIR_USR_LOCAL__/sbin:__INSTALLER_PATH_DIR_USR_LOCAL__/bin:__INSTALLER_PATH_DIR_USR__/sbin:__INSTALLER_PATH_DIR_USR__/bin:__INSTALLER_PATH_DIR_SBIN__:__INSTALLER_PATH_DIR_BIN__ \
        __INSTALLER_PATH_DIR_USR_BIN__/curl \
          --fail \
          --silent \
          --show-error \
          --location \
          --proto '=https' \
          --proto-redir '=https' \
          --connect-timeout 15 \
          --max-time 600 \
          --max-redirs 8 \
          --retry 5 \
          --retry-delay 2 \
          --retry-all-errors \
          --user-agent 'unattended-installer-mullvad/1.0' \
          --header 'Accept: application/octet-stream, application/vnd.debian.binary-package;q=0.9, application/pgp-signature;q=0.8, */*;q=0.1' \
          --output "$mullvad_download_partial" \
          --write-out '%{http_code}\n%{url_effective}' \
          --url "$mullvad_download_url"
  )

  mullvad_http_status=$(printf '%s\n' "$mullvad_transfer_metadata" | sed -n '1p')
  mullvad_effective_url=$(printf '%s\n' "$mullvad_transfer_metadata" | sed -n '2p')
  case "$mullvad_http_status" in
    200|206) ;;
    *)
      installer_fatal "${mullvad_download_label} returned unexpected HTTP status: ${mullvad_http_status:-unset}"
      ;;
  esac
  mullvad_require_https_url "$mullvad_download_label effective URL" "$mullvad_effective_url"

  [ -f "$mullvad_download_partial_host_path" ] && [ ! -L "$mullvad_download_partial_host_path" ] ||
    installer_fatal "${mullvad_download_label} download is not a regular file"
  run_in_target_quiet \
    "publish ${mullvad_download_label}" \
    __INSTALLER_PATH_DIR_BIN__/mv -f -- "$mullvad_download_partial" "$mullvad_download_path"
  installer_info \
    "downloaded ${mullvad_download_label} effective_url=${mullvad_effective_url}"
}

mullvad_installed_package_status() {
  mullvad_status_package=$1
  # The in-target dpkg-query expands the format token; pass it literally.
  # shellcheck disable=SC2016
  capture_in_target "inspect installed ${mullvad_status_package} package status" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
package_name=$1
status_format=$2
dpkg-query -W -f="$status_format" "$package_name" 2>__INSTALLER_PATH_DIR_DEV__/null || true
' sh "$mullvad_status_package" "\${Status}"
}

mullvad_capture_target_resolver() {
  run_in_target_quiet "capture installer DNS before systemd-resolved installation" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
resolver_path=__INSTALLER_PATH_DIR_ETC__/resolv.conf
resolver_snapshot=$1
resolver_maximum_bytes=$2

[ "$resolver_snapshot" = /tmp/installer-mullvad-resolv.conf ]
case "$resolver_maximum_bytes" in ""|*[!0-9]*) exit 1 ;; esac
[ "$resolver_maximum_bytes" -ge 1 ]
[ "$resolver_maximum_bytes" -le 1048576 ]
[ -r "$resolver_path" ]
[ -f "$resolver_path" ]
resolver_size=$(__INSTALLER_PATH_DIR_USR_BIN__/find -H "$resolver_path" -maxdepth 0 -printf %s)
case "$resolver_size" in
  ""|*[!0-9]*) exit 1 ;;
esac
[ "$resolver_size" -ge 1 ]
[ "$resolver_size" -le "$resolver_maximum_bytes" ]
LC_ALL=C __INSTALLER_PATH_DIR_USR_BIN__/grep -Eq \
  "^[[:space:]]*nameserver[[:space:]]+[^#[:space:]]+" \
  "$resolver_path"

resolver_snapshot_tmp=$(mktemp "${resolver_snapshot}.XXXXXX")
cleanup_resolver_snapshot() {
  [ -z "$resolver_snapshot_tmp" ] || __INSTALLER_PATH_DIR_BIN__/rm -f -- "$resolver_snapshot_tmp"
}
trap cleanup_resolver_snapshot 0
trap "exit 129" 1
trap "exit 130" 2
trap "exit 143" 15
umask 077
__INSTALLER_PATH_DIR_BIN__/cat -- "$resolver_path" >"$resolver_snapshot_tmp"
__INSTALLER_PATH_DIR_BIN__/chown 0:0 "$resolver_snapshot_tmp"
__INSTALLER_PATH_DIR_BIN__/chmod 0600 "$resolver_snapshot_tmp"
__INSTALLER_PATH_DIR_BIN__/mv -f -- "$resolver_snapshot_tmp" "$resolver_snapshot"
resolver_snapshot_tmp=

[ -f "$resolver_snapshot" ]
[ ! -L "$resolver_snapshot" ]
[ "$(__INSTALLER_PATH_DIR_USR_BIN__/find -P "$resolver_snapshot" -maxdepth 0 -printf %U:%G)" = 0:0 ]
[ "$(__INSTALLER_PATH_DIR_USR_BIN__/find -P "$resolver_snapshot" -maxdepth 0 -printf %m)" = 600 ]
' sh "$MULLVAD_RESOLVER_SOURCE" "$MULLVAD_RESOLVER_MAXIMUM_BYTES"
}

mullvad_seed_target_resolved_stub() {
  mullvad_resolver_phase=$1
  MULLVAD_RESOLVED_STUB="${DIR_RUN}/systemd/resolve/stub-resolv.conf"
  case "$mullvad_resolver_phase" in
    systemd-resolved-installation|mullvad-vpn-installation) ;;
    *) installer_fatal "unsupported Mullvad resolver refresh phase: ${mullvad_resolver_phase:-unset}" ;;
  esac

  mullvad_target_root=$(target_root_dir)
  mullvad_validate_target_path "Mullvad target root" "$mullvad_target_root"
  [ -d "$mullvad_target_root" ] ||
    installer_fatal "Mullvad target root is unavailable: $mullvad_target_root"
  command -v chroot >__INSTALLER_PATH_DIR_DEV__/null 2>&1 ||
    installer_fatal "chroot is unavailable for persistent target resolver refresh"

  mullvad_target_run="${mullvad_target_root%/}__INSTALLER_PATH_DIR_RUN__"
  if mullvad_target_run_source=$(target_mount_source "$mullvad_target_run" 2>__INSTALLER_PATH_DIR_DEV__/null); then
    installer_fatal \
      "refusing to refresh the persistent target resolver while ${mullvad_target_run} is mounted from ${mullvad_target_run_source}"
  fi

  # debian-installer-utils in-target bind-mounts the installer __INSTALLER_PATH_DIR_RUN__ over
  # the target runtime. Seed systemd-resolved's target-side stub only after that bind
  # is gone, otherwise the file disappears when in-target cleans up and later
  # direct-chroot helpers see a dangling __INSTALLER_PATH_DIR_ETC__/resolv.conf.
  installer_info \
    "direct-chroot: seed and verify systemd-resolved stub after ${mullvad_resolver_phase}"
  # shellcheck disable=SC2016
  if ! chroot "$mullvad_target_root" __INSTALLER_PATH_DIR_USR_BIN__/env -i \
    HOME=__INSTALLER_PATH_DIR_ROOT_HOME__ \
    LC_ALL=C \
    PATH=__INSTALLER_PATH_DIR_USR_LOCAL__/sbin:__INSTALLER_PATH_DIR_USR_LOCAL__/bin:__INSTALLER_PATH_DIR_USR__/sbin:__INSTALLER_PATH_DIR_USR__/bin:__INSTALLER_PATH_DIR_SBIN__:__INSTALLER_PATH_DIR_BIN__ \
    __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
resolver_source=$1
resolved_stub=$2
resolver_maximum_bytes=$3
attempts=$4
timeout_seconds=$5
retry_delay_seconds=$6
shift 6

[ "$resolver_source" = /tmp/installer-mullvad-resolv.conf ]
[ "$resolved_stub" = __INSTALLER_PATH_DIR_RUN__/systemd/resolve/stub-resolv.conf ]
case "$resolver_maximum_bytes" in ""|*[!0-9]*) exit 1 ;; esac
case "$attempts" in ""|*[!0-9]*) exit 1 ;; esac
case "$timeout_seconds" in ""|*[!0-9]*) exit 1 ;; esac
case "$retry_delay_seconds" in ""|*[!0-9]*) exit 1 ;; esac
[ "$resolver_maximum_bytes" -ge 1 ]
[ "$resolver_maximum_bytes" -le 1048576 ]
[ "$attempts" -ge 1 ]
[ "$attempts" -le 10 ]
[ "$timeout_seconds" -ge 1 ]
[ "$timeout_seconds" -le 60 ]
[ "$retry_delay_seconds" -le 30 ]
[ "$#" -ge 1 ]

[ -x __INSTALLER_PATH_DIR_USR_LIB__/systemd/systemd-resolved ]
[ -x __INSTALLER_PATH_DIR_USR_BIN__/resolvectl ]
[ -L __INSTALLER_PATH_DIR_USR_SBIN__/resolvconf ]
[ "$(__INSTALLER_PATH_DIR_USR_BIN__/readlink -f __INSTALLER_PATH_DIR_USR_SBIN__/resolvconf)" = __INSTALLER_PATH_DIR_USR_BIN__/resolvectl ]
[ -f "$resolver_source" ]
[ ! -L "$resolver_source" ]
resolver_owner_group=$(__INSTALLER_PATH_DIR_USR_BIN__/find -P "$resolver_source" -maxdepth 0 -printf %U:%G)
[ "$resolver_owner_group" = 0:0 ]
resolver_size=$(__INSTALLER_PATH_DIR_USR_BIN__/find -P "$resolver_source" -maxdepth 0 -printf %s)
case "$resolver_size" in
  ""|*[!0-9]*) exit 1 ;;
esac
[ "$resolver_size" -ge 1 ]
[ "$resolver_size" -le "$resolver_maximum_bytes" ]
[ -L __INSTALLER_PATH_DIR_ETC__/resolv.conf ]
resolver_path=$(__INSTALLER_PATH_DIR_USR_BIN__/readlink -m __INSTALLER_PATH_DIR_ETC__/resolv.conf)
[ "$resolver_path" = "$resolved_stub" ]
[ ! -L "$resolved_stub" ]

__INSTALLER_PATH_DIR_USR_BIN__/install -d -o 0 -g 0 -m 0755 -- "$(__INSTALLER_PATH_DIR_USR_BIN__/dirname "$resolved_stub")"
resolved_stub_tmp=$(mktemp "${resolved_stub}.XXXXXX")
cleanup_resolved_stub() {
  [ -z "$resolved_stub_tmp" ] || __INSTALLER_PATH_DIR_BIN__/rm -f -- "$resolved_stub_tmp"
}
trap cleanup_resolved_stub 0
trap "exit 129" 1
trap "exit 130" 2
trap "exit 143" 15
__INSTALLER_PATH_DIR_BIN__/cat -- "$resolver_source" >"$resolved_stub_tmp"
__INSTALLER_PATH_DIR_BIN__/chown 0:0 "$resolved_stub_tmp"
__INSTALLER_PATH_DIR_BIN__/chmod 0644 "$resolved_stub_tmp"
__INSTALLER_PATH_DIR_BIN__/mv -f -- "$resolved_stub_tmp" "$resolved_stub"
resolved_stub_tmp=

[ -f "$resolved_stub" ]
[ ! -L "$resolved_stub" ]
[ -s "$resolved_stub" ]
[ "$(__INSTALLER_PATH_DIR_USR_BIN__/find -P "$resolved_stub" -maxdepth 0 -printf %U:%G)" = 0:0 ]
[ "$(__INSTALLER_PATH_DIR_USR_BIN__/find -P "$resolved_stub" -maxdepth 0 -printf %m)" = 644 ]
LC_ALL=C __INSTALLER_PATH_DIR_USR_BIN__/grep -Eq \
  "^[[:space:]]*nameserver[[:space:]]+[^#[:space:]]+" \
  "$resolved_stub"

for resolver_host in "$@"; do
  case "$resolver_host" in
    ""|.*|*.|*..*|*[!abcdefghijklmnopqrstuvwxyz0123456789.-]*) exit 1 ;;
  esac
done

attempt=1
while [ "$attempt" -le "$attempts" ]; do
  failed_hosts=
  for resolver_host in "$@"; do
    if __INSTALLER_PATH_DIR_USR_BIN__/timeout "$timeout_seconds" \
        __INSTALLER_PATH_DIR_USR_BIN__/getent ahosts "$resolver_host" >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
      :
    else
      failed_hosts="${failed_hosts} ${resolver_host}"
    fi
  done
  [ -z "$failed_hosts" ] && exit 0
  [ "$attempt" -lt "$attempts" ] || break
  __INSTALLER_PATH_DIR_BIN__/sleep "$retry_delay_seconds"
  attempt=$((attempt + 1))
done

printf "resolver probes failed after %s attempt(s):%s\n" \
  "$attempts" "$failed_hosts" >&2
exit 1
' sh \
    "$MULLVAD_RESOLVER_SOURCE" \
    "$MULLVAD_RESOLVED_STUB" \
    "$MULLVAD_RESOLVER_MAXIMUM_BYTES" \
    "$MULLVAD_DNS_ATTEMPTS" \
    "$MULLVAD_DNS_TIMEOUT_SECONDS" \
    "$MULLVAD_DNS_RETRY_DELAY_SECONDS" \
    "$MULLVAD_RESOLVER_HOST" \
    "$MULLVAD_BITWARDEN_RESOLVER_HOST" \
    "$MULLVAD_GITHUB_RESOLVER_HOST"
  then
    installer_fatal \
      "persistent target resolver refresh failed after ${mullvad_resolver_phase}"
  fi

  installer_info \
    "seeded persistent target systemd-resolved stub phase=${mullvad_resolver_phase} source=${MULLVAD_RESOLVER_SOURCE} stub=${MULLVAD_RESOLVED_STUB} dns_hosts=${MULLVAD_RESOLVER_HOST},${MULLVAD_BITWARDEN_RESOLVER_HOST},${MULLVAD_GITHUB_RESOLVER_HOST}"
}

install_target_systemd_resolved_for_mullvad() {
  mullvad_capture_target_resolver

  mullvad_resolved_status=$(mullvad_installed_package_status systemd-resolved)
  if [ "$mullvad_resolved_status" != "install ok installed" ]; then
    run_in_target \
      "install systemd-resolved for Mullvad DNS integration" \
      __INSTALLER_PATH_DIR_USR_BIN__/env \
        DEBIAN_FRONTEND=noninteractive \
        DEBCONF_NONINTERACTIVE_SEEN=true \
        NEEDRESTART_SUSPEND=1 \
        __INSTALLER_PATH_DIR_USR_BIN__/apt-get \
          -o Acquire::Retries=5 \
          -o Acquire::http::Timeout=45 \
          -o Acquire::https::Timeout=45 \
          -o Binary::apt::APT::Keep-Downloaded-Packages=false \
          -o DPkg::Lock::Timeout=60 \
          -o DPkg::Use-Pty=0 \
          -y \
          --no-install-recommends \
          --no-install-suggests \
          install systemd-resolved
  fi

  mullvad_resolved_status=$(mullvad_installed_package_status systemd-resolved)
  [ "$mullvad_resolved_status" = "install ok installed" ] ||
    installer_fatal "systemd-resolved is not fully installed: ${mullvad_resolved_status:-missing}"
  mullvad_legacy_resolvconf_status=$(mullvad_installed_package_status resolvconf)
  [ "$mullvad_legacy_resolvconf_status" != "install ok installed" ] ||
    installer_fatal "legacy resolvconf must not remain installed with systemd-resolved"

  mullvad_seed_target_resolved_stub systemd-resolved-installation
}

mullvad_validate_and_defer_apparmor() {
  # The package always supplies its resource, but profile installation depends
  # on the vendor postinst environment. Publish it explicitly when absent.
  # Compilation is mandatory now; kernel activation remains boot-only.
  installer_operation_context_repo FILE_LATE_MULLVAD 381 validate_mullvad_apparmor
  run_in_target_quiet "validate Mullvad AppArmor profile without loading installer policy" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
umask 077
policy_dir=__INSTALLER_PATH_DIR_APPARMOR__
profile="$policy_dir/mullvad"
vendor="__INSTALLER_PATH_DIR_OPT__/Mullvad VPN/resources/apparmor_mullvad"
abi="$policy_dir/abi/4.0"
policy_failure() { printf "Mullvad AppArmor: %s\n" "$*" >&2; exit 1; }
policy_identity() { __INSTALLER_PATH_DIR_USR_BIN__/find -P "$1" -maxdepth 0 -printf %D:%i:%s:%T@:%C@:%U:%G:%m:%n; }
require_policy_file() {
  [ -f "$1" ] && [ ! -L "$1" ] && [ -r "$1" ] || policy_failure "missing or indirect $2"
  [ "$(__INSTALLER_PATH_DIR_USR_BIN__/find -P "$1" -maxdepth 0 -printf %U:%G:%n)" = 0:0:1 ] ||
    policy_failure "unsafe ownership or link count for $2"
  policy_mode=$(__INSTALLER_PATH_DIR_USR_BIN__/find -P "$1" -maxdepth 0 -printf %m) || policy_failure "cannot inspect $2"
  case "$policy_mode" in ""|*[!0-7]*) policy_failure "invalid permissions for $2" ;; esac
  # This is read-only policy data. Vendor executable bits do not grant write
  # authority; reject special bits and every group/other-writable spelling.
  [ "$((0$policy_mode & 07022))" -eq 0 ] && [ "$((0$policy_mode & 0400))" -ne 0 ] ||
    policy_failure "unsafe permissions for $2"
  policy_size=$(__INSTALLER_PATH_DIR_USR_BIN__/wc -c <"$1") || policy_failure "cannot measure $2"
  [ "$policy_size" -gt 0 ] && [ "$policy_size" -le 65536 ] || policy_failure "invalid size for $2"
}
require_policy_directory() {
  policy_probe=$1
  while [ "$policy_probe" != / ]; do
    [ -d "$policy_probe" ] && [ ! -L "$policy_probe" ] || policy_failure "indirect policy directory"
    case "$(__INSTALLER_PATH_DIR_USR_BIN__/find -P "$policy_probe" -maxdepth 0 -printf %U:%G:%m)" in
      0:0:700|0:0:750|0:0:755) ;; *) policy_failure "unsafe policy directory ownership or permissions" ;;
    esac
    policy_probe=${policy_probe%/*}
    [ -n "$policy_probe" ] || policy_probe=/
  done
}
require_policy_directory "$policy_dir"
require_policy_directory "${vendor%/*}"
require_policy_directory "${abi%/*}"
require_policy_file "$vendor" "packaged vendor policy"
require_policy_file "$abi" "packaged ABI 4.0"
vendor_identity=$(policy_identity "$vendor") || policy_failure "cannot identify packaged policy"
policy_lock="$policy_dir/.mullvad-installer.lock"
__INSTALLER_PATH_DIR_USR_BIN__/mkdir -m 0700 -- "$policy_lock" || policy_failure "another policy publisher owns the target"
policy_check_dir=
policy_keep=false
policy_published=false
cleanup_policy_check() {
  policy_status=$?
  trap - 0 HUP INT TERM
  if [ "$policy_status" -ne 0 ] && [ "$policy_published" = true ]; then policy_keep=true; fi
  if [ "$policy_keep" = true ]; then
    printf "Mullvad AppArmor: outcome unknown; evidence and lock retained: %s\n" "$policy_check_dir" >&2
    exit 125
  fi
  if [ -n "$policy_check_dir" ]; then
    if ! { __INSTALLER_PATH_DIR_USR_BIN__/rm -f -- "$policy_check_dir/current" "$policy_check_dir/vendor" \
             "$policy_check_dir/candidate" "$policy_check_dir/parser.conf" &&
           __INSTALLER_PATH_DIR_USR_BIN__/rmdir -- "$policy_check_dir"; }; then
      printf "Mullvad AppArmor: cleanup failed; evidence and lock retained: %s\n" "$policy_check_dir" >&2
      exit 125
    fi
  fi
  __INSTALLER_PATH_DIR_USR_BIN__/rmdir -- "$policy_lock" || policy_status=125
  exit "$policy_status"
}
trap cleanup_policy_check 0
trap "exit 129" HUP
trap "exit 130" INT
trap "exit 143" TERM
policy_check_dir=$(__INSTALLER_PATH_DIR_USR_BIN__/mktemp -d "$policy_dir/.mullvad-installer.XXXXXXXXXX") || exit "$?"
profile_identity=
# A resumed late phase may see only the managed flag normalization. Compare
# every other byte against the vendor resource; arbitrary policy edits fail.
normalize_header="s#^profile mullvad \"__INSTALLER_PATH_DIR_OPT__/Mullvad VPN/mullvad-gui\" flags=\((unconfined|attach_disconnected|mediate_deleted|complain|audit|[ ,])+\) [{]$#profile mullvad verified-header {#"
if [ -e "$profile" ] || [ -L "$profile" ]; then
  require_policy_file "$profile" "existing target policy"
  profile_identity=$(policy_identity "$profile") || policy_failure "cannot identify existing policy"
  __INSTALLER_PATH_DIR_USR_BIN__/sed -E "$normalize_header" "$profile" >"$policy_check_dir/current" || exit "$?"
  __INSTALLER_PATH_DIR_USR_BIN__/sed -E "$normalize_header" "$vendor" >"$policy_check_dir/vendor" || exit "$?"
  __INSTALLER_PATH_DIR_USR_BIN__/cmp -s "$policy_check_dir/current" "$policy_check_dir/vendor" ||
    policy_failure "existing policy differs from packaged vendor policy; original retained"
  __INSTALLER_PATH_DIR_USR_BIN__/cp -- "$profile" "$policy_check_dir/candidate" || exit "$?"
else
  __INSTALLER_PATH_DIR_USR_BIN__/cp -- "$vendor" "$policy_check_dir/candidate" || exit "$?"
fi
: >"$policy_check_dir/parser.conf"
if __INSTALLER_PATH_DIR_USR_SBIN__/apparmor_parser --config-file "$policy_check_dir/parser.conf" \
     --base "$policy_dir" --Include "$policy_dir" --features-file "$abi" --jobs=1 \
     --skip-kernel-load --skip-cache "$policy_check_dir/candidate"; then
  :
else
  policy_status=$?
  printf "Mullvad AppArmor: offline compilation failed (status=%s); previous policy retained\n" "$policy_status" >&2
  exit "$policy_status"
fi
[ "$(policy_identity "$vendor")" = "$vendor_identity" ] || policy_failure "packaged policy changed during validation"
if [ -n "$profile_identity" ]; then
  [ ! -L "$profile" ] && [ "$(policy_identity "$profile")" = "$profile_identity" ] ||
    policy_failure "existing policy changed during validation; original retained"
  printf "Mullvad AppArmor: verified existing policy; kernel activation deferred\n"
else
  __INSTALLER_PATH_DIR_USR_BIN__/chown 0:0 "$policy_check_dir/candidate" || exit "$?"
  __INSTALLER_PATH_DIR_USR_BIN__/chmod 0644 "$policy_check_dir/candidate" || exit "$?"
  __INSTALLER_PATH_DIR_USR_BIN__/sync -f "$policy_check_dir/candidate" || exit "$?"
  published_identity=$(__INSTALLER_PATH_DIR_USR_BIN__/find -P "$policy_check_dir/candidate" -maxdepth 0 -printf %D:%i:%s:%U:%G:%m:%n) || exit "$?"
  # link publishes complete bytes atomically and refuses a concurrent leaf;
  # never overwrite a new file or symlink placed at the destination.
  if __INSTALLER_PATH_DIR_USR_BIN__/ln -T -- "$policy_check_dir/candidate" "$profile"; then
    :
  else
    policy_status=$?
    printf "Mullvad AppArmor: publication failed (status=%s); destination retained\n" "$policy_status" >&2
    exit "$policy_status"
  fi
  policy_published=true
  if ! { __INSTALLER_PATH_DIR_USR_BIN__/rm -- "$policy_check_dir/candidate" &&
         __INSTALLER_PATH_DIR_USR_BIN__/sync -f "$profile" &&
         __INSTALLER_PATH_DIR_USR_BIN__/sync -f "$policy_dir"; }; then
    policy_keep=true
    exit 125
  fi
  require_policy_file "$profile" "published target policy"
  [ "$(__INSTALLER_PATH_DIR_USR_BIN__/find -P "$profile" -maxdepth 0 -printf %D:%i:%s:%U:%G:%m:%n)" = "$published_identity" ] ||
    policy_failure "published policy identity changed; evidence retained"
  printf "Mullvad AppArmor: installed validated packaged policy; kernel activation deferred\n"
fi
' sh || return $?
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_UNIT_MULLVAD_APPARMOR_SERVICE)" \
    __INSTALLER_PATH_DIR_ETC__/systemd/system/mullvad-apparmor.service 0644 || return $?
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_UNIT_MULLVAD_DAEMON_SERVICE_D_10_APPARMOR)" \
    __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_MULLVAD_DAEMON_DROPIN__/10-apparmor.conf 0644 || return $?
  # The logging-only override must never discard new vendor launch options.
  # Fail closed if a future package changes its ExecStart contract or flags.
  installer_operation_context_repo FILE_LATE_MULLVAD 512 validate_mullvad_journal
  run_in_target_quiet "validate Mullvad native journal logging contract" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
unit=__INSTALLER_PATH_DIR_USR_LIB__/systemd/system/mullvad-daemon.service
[ -f "$unit" ] || unit=__INSTALLER_PATH_DIR_LIB__/systemd/system/mullvad-daemon.service
[ "$(grep -E "^[[:space:]]*ExecStart=" "$unit")" = "ExecStart=__INSTALLER_PATH_DIR_USR_BIN__/mullvad-daemon -vv --disable-stdout-timestamps" ]
help=$(__INSTALLER_PATH_DIR_USR_BIN__/mullvad-daemon --help)
printf "%s\n" "$help" | grep -F -q -- --disable-log-to-file
printf "%s\n" "$help" | grep -F -q -- --disable-stdout-timestamps
' sh || return $?
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_UNIT_MULLVAD_DAEMON_SERVICE_D_40_LOGGING)" \
    __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_MULLVAD_DAEMON_DROPIN__/40-logging.conf 0644 || return $?
  run_in_target_quiet "enable checked Mullvad AppArmor activation at first boot" \
    systemctl --root=/ enable mullvad-apparmor.service || return $?
  installer_info "Mullvad AppArmor policy compiled; kernel activation deferred to mullvad-apparmor.service"
}

install_target_mullvad_vpn_if_selected() (
  set -eu

  mullvad_vpn_selected || exit 0
  require_in_target "Mullvad VPN package installation"
  prepare_target_volatile_dirs_for_apt
  mullvad_work_host_path=
  mullvad_resolver_host_path="${TARGET_ROOT}${MULLVAD_RESOLVER_SOURCE}"
  case "$mullvad_resolver_host_path" in
    ${TARGET_ROOT}${DIR_TMP}/installer-mullvad-resolv.conf) ;;
    *) installer_fatal "refusing unsafe Mullvad resolver snapshot path: $mullvad_resolver_host_path" ;;
  esac
  mullvad_cleanup() {
    case "${mullvad_work_host_path:-}" in
      '') ;;
      ${TARGET_ROOT}${DIR_TMP}/installer-mullvad-vpn) rm -rf -- "$mullvad_work_host_path" ;;
    esac
    rm -f -- "$mullvad_resolver_host_path"
  }
  mullvad_status=0
  trap 'mullvad_status=$?; trap - 0; mullvad_cleanup; exit "$mullvad_status"' 0
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  install_target_systemd_resolved_for_mullvad

  mullvad_existing_status=$(mullvad_installed_package_status mullvad-vpn)
  if [ "$mullvad_existing_status" = "install ok installed" ]; then
    mullvad_existing_version=$(
      capture_in_target \
        "inspect installed Mullvad VPN package version" \
        __INSTALLER_PATH_DIR_USR_BIN__/dpkg-query -W -f="\${Version}" mullvad-vpn
    )
    mullvad_existing_unit=$(target_systemd_unit_path mullvad-daemon.service system 2>__INSTALLER_PATH_DIR_DEV__/null || true)
    [ -n "$mullvad_existing_unit" ] ||
      installer_fatal "installed mullvad-vpn package does not provide mullvad-daemon.service"
    installer_info \
      "Mullvad VPN is already installed version=${mullvad_existing_version} unit=${mullvad_existing_unit}"
    mullvad_validate_and_defer_apparmor
    exit 0
  fi

  mullvad_target_arch=$(
    capture_in_target \
      "resolve Mullvad VPN target architecture" \
      __INSTALLER_PATH_DIR_USR_BIN__/dpkg --print-architecture
  )
  case "$mullvad_target_arch" in
    amd64)
      mullvad_deb_url=$MULLVAD_AMD64_DEB_URL
      ;;
    arm64)
      mullvad_deb_url=$MULLVAD_ARM64_DEB_URL
      ;;
    *)
      installer_fatal "Mullvad VPN is unsupported for target architecture: ${mullvad_target_arch:-unset}"
      ;;
  esac
  mullvad_signature_url="${mullvad_deb_url}/signature"

  mullvad_work_dir=/tmp/installer-mullvad-vpn
  mullvad_key_path="${mullvad_work_dir}/mullvad-code-signing.asc"
  mullvad_signature_path="${mullvad_work_dir}/mullvad-vpn.deb.asc"
  mullvad_deb_path="${mullvad_work_dir}/mullvad-vpn.deb"
  mullvad_gnupg_home="${mullvad_work_dir}/gnupg"
  mullvad_work_host_path="${TARGET_ROOT}${mullvad_work_dir}"

  case "$mullvad_work_host_path" in
    ${TARGET_ROOT}${DIR_TMP}/installer-mullvad-vpn) ;;
    *) installer_fatal "refusing unsafe Mullvad work directory: $mullvad_work_host_path" ;;
  esac
  rm -rf -- "$mullvad_work_host_path"
  run_in_target_quiet \
    "prepare Mullvad VPN verification workspace" \
    __INSTALLER_PATH_DIR_USR_BIN__/install -d -m 0700 -- "$mullvad_work_dir" "$mullvad_gnupg_home"

  mullvad_download_target_file \
    "Mullvad code signing key" \
    "$MULLVAD_CODE_SIGNING_KEY_URL" \
    "$mullvad_key_path"
  mullvad_download_target_file \
    "Mullvad VPN Debian package" \
    "$mullvad_deb_url" \
    "$mullvad_deb_path"
  mullvad_download_target_file \
    "Mullvad VPN detached signature" \
    "$mullvad_signature_url" \
    "$mullvad_signature_path"

  mullvad_key_listing=$(
    capture_in_target \
      "inspect Mullvad code signing key" \
      __INSTALLER_PATH_DIR_USR_BIN__/gpg \
        --batch \
        --no-options \
        --homedir "$mullvad_gnupg_home" \
        --with-colons \
        --import-options show-only \
        --import "$mullvad_key_path"
  )
  mullvad_primary_fingerprints=$(
    printf '%s\n' "$mullvad_key_listing" |
      awk -F: '
        $1 == "pub" {
          want_fingerprint = 1
          next
        }
        want_fingerprint && $1 == "fpr" {
          print $10
          want_fingerprint = 0
        }
      '
  )
  [ "$mullvad_primary_fingerprints" = "$MULLVAD_CODE_SIGNING_FINGERPRINT" ] ||
    installer_fatal "Mullvad code signing key fingerprint mismatch"

  run_in_target_quiet \
    "import pinned Mullvad code signing key" \
    __INSTALLER_PATH_DIR_USR_BIN__/gpg \
      --batch \
      --no-options \
      --homedir "$mullvad_gnupg_home" \
      --import "$mullvad_key_path"

  mullvad_signature_status=$(
    capture_in_target \
      "verify Mullvad VPN detached signature" \
      __INSTALLER_PATH_DIR_USR_BIN__/gpg \
        --batch \
        --no-options \
        --homedir "$mullvad_gnupg_home" \
        --status-fd 1 \
        --verify "$mullvad_signature_path" "$mullvad_deb_path"
  )
  mullvad_valid_signature_count=$(
    printf '%s\n' "$mullvad_signature_status" |
      awk -v expected="$MULLVAD_CODE_SIGNING_FINGERPRINT" '
        $1 == "[GNUPG:]" && $2 == "VALIDSIG" {
          total++
          if ($3 == expected || $NF == expected) {
            expected_total++
          }
        }
        END {
          printf "%d:%d\n", total + 0, expected_total + 0
        }
      '
  )
  [ "$mullvad_valid_signature_count" = "1:1" ] ||
    installer_fatal "Mullvad VPN package does not have exactly one valid signature from the pinned key"

  mullvad_deb_magic=$(head -c 8 "$mullvad_work_host_path/mullvad-vpn.deb" 2>__INSTALLER_PATH_DIR_DEV__/null || true)
  [ "$mullvad_deb_magic" = '!<arch>' ] ||
    installer_fatal "Mullvad VPN download does not have Debian archive framing"
  run_in_target_quiet \
    "validate Mullvad VPN Debian package" \
    __INSTALLER_PATH_DIR_USR_BIN__/dpkg-deb --info "$mullvad_deb_path"

  mullvad_package_name=$(
    capture_in_target \
      "read Mullvad VPN package name" \
      __INSTALLER_PATH_DIR_USR_BIN__/dpkg-deb -f "$mullvad_deb_path" Package
  )
  mullvad_package_version=$(
    capture_in_target \
      "read Mullvad VPN package version" \
      __INSTALLER_PATH_DIR_USR_BIN__/dpkg-deb -f "$mullvad_deb_path" Version
  )
  mullvad_package_arch=$(
    capture_in_target \
      "read Mullvad VPN package architecture" \
      __INSTALLER_PATH_DIR_USR_BIN__/dpkg-deb -f "$mullvad_deb_path" Architecture
  )
  [ "$mullvad_package_name" = mullvad-vpn ] ||
    installer_fatal "Mullvad VPN artifact has unexpected Package field: ${mullvad_package_name:-unset}"
  [ "$mullvad_package_arch" = "$mullvad_target_arch" ] ||
    installer_fatal "Mullvad VPN artifact architecture mismatch: ${mullvad_package_arch:-unset}"
  [ -n "$mullvad_package_version" ] ||
    installer_fatal "Mullvad VPN artifact has no Version field"
  [ "${#mullvad_package_version}" -le 128 ] ||
    installer_fatal "Mullvad VPN artifact Version field exceeds 128 characters"
  test_in_target __INSTALLER_PATH_DIR_USR_BIN__/dpkg --validate-version "$mullvad_package_version" ||
    installer_fatal "Mullvad VPN artifact Version field is invalid: $mullvad_package_version"

  mullvad_install_deb_path=$mullvad_deb_path
  if installer_class_selected role/desktop/full 2>__INSTALLER_PATH_DIR_DEV__/null; then
    case "$mullvad_package_version" in
      ''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.+:~_-]*)
        installer_fatal "Mullvad VPN artifact Version field is unsafe for local repository retention"
        ;;
    esac
    mullvad_repository_dir=__INSTALLER_PATH_DIR_VAR_LIB_SOFTWARE_INBOX__
    mullvad_repository_deb="${mullvad_repository_dir}/${mullvad_package_name}_${mullvad_package_version}_${mullvad_package_arch}.deb"
    mullvad_repository_tmp="${mullvad_repository_deb}.tmp.$$"
    mullvad_validate_target_path "Mullvad local repository directory" "$mullvad_repository_dir"
    mullvad_validate_target_path "Mullvad retained Debian package" "$mullvad_repository_deb"
    mullvad_validate_target_path "Mullvad retained Debian package temporary path" "$mullvad_repository_tmp"
    run_in_target_quiet \
      "retain verified Mullvad VPN package for the managed local repository" \
      __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
source_path=$1
repository_dir=$2
destination=$3
temporary=$4

install -d -m 0755 -- __INSTALLER_PATH_DIR_VAR__/lib/software
install -d -m 0700 -- "$repository_dir"
[ ! -L "$repository_dir" ]
if [ -e "$destination" ] || [ -L "$destination" ]; then
  [ -f "$destination" ] && [ ! -L "$destination" ]
fi
install -m 0644 -- "$source_path" "$temporary"
[ "$(sha256sum "$source_path" | awk "{print \$1}")" = "$(sha256sum "$temporary" | awk "{print \$1}")" ]
mv -f -- "$temporary" "$destination"
' sh "$mullvad_deb_path" "$mullvad_repository_dir" "$mullvad_repository_deb" "$mullvad_repository_tmp"
    # Install the original verified path: the inbox consumer may remove its copy.
    mullvad_install_deb_path=$mullvad_deb_path
  fi

  run_in_target \
    "install verified Mullvad VPN package" \
    __INSTALLER_PATH_DIR_USR_BIN__/env \
      DEBIAN_FRONTEND=noninteractive \
      DEBCONF_NONINTERACTIVE_SEEN=true \
      NEEDRESTART_SUSPEND=1 \
      __INSTALLER_PATH_DIR_USR_BIN__/apt-get \
        -o Acquire::Retries=5 \
        -o Acquire::http::Timeout=45 \
        -o Acquire::https::Timeout=45 \
        -o DPkg::Lock::Timeout=60 \
        -o DPkg::Use-Pty=0 \
        -y \
        --no-install-recommends \
        --no-install-suggests \
        install "$mullvad_install_deb_path"

  mullvad_seed_target_resolved_stub mullvad-vpn-installation

  mullvad_installed_status=$(mullvad_installed_package_status mullvad-vpn)
  [ "$mullvad_installed_status" = "install ok installed" ] ||
    installer_fatal "mullvad-vpn is not fully installed: ${mullvad_installed_status:-missing}"
  mullvad_installed_version=$(
    capture_in_target \
      "verify installed Mullvad VPN version" \
      __INSTALLER_PATH_DIR_USR_BIN__/dpkg-query -W -f="\${Version}" mullvad-vpn
  )
  [ "$mullvad_installed_version" = "$mullvad_package_version" ] ||
    installer_fatal "installed Mullvad VPN version does not match the verified artifact"
  mullvad_daemon_unit=$(target_systemd_unit_path mullvad-daemon.service system 2>__INSTALLER_PATH_DIR_DEV__/null || true)
  [ -n "$mullvad_daemon_unit" ] ||
    installer_fatal "verified mullvad-vpn package did not install mullvad-daemon.service"
  mullvad_package_sha256=$(
    capture_in_target \
      "record Mullvad VPN package SHA-256" \
      __INSTALLER_PATH_DIR_USR_BIN__/sha256sum "$mullvad_deb_path" |
      awk '{print $1}'
  )
  case "$mullvad_package_sha256" in
    *[!0-9a-f]*|'') installer_fatal "Mullvad VPN package SHA-256 is invalid" ;;
  esac
  [ "${#mullvad_package_sha256}" -eq 64 ] ||
    installer_fatal "Mullvad VPN package SHA-256 has an invalid length"

  installer_info \
    "installed verified Mullvad VPN package version=${mullvad_installed_version} architecture=${mullvad_target_arch} sha256=${mullvad_package_sha256} unit=${mullvad_daemon_unit}"
  mullvad_validate_and_defer_apparmor
)
