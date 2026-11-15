#!/bin/sh
# Sourced installer module; edit this file directly.

desktop_extract_role_wallpaper_archive() {
  archive_host="${TMP_ENV_DIR}/desktop-wallpapers.$$.tar.gz"
  archive_target=/tmp/installer-desktop-wallpapers.tar.gz
  archive_target_host=$(target_asset_host_path "$archive_target")

  rm -f -- "$archive_host" "$archive_target_host"
  if ! desktop_download_release_archive \
      'desktop wallpapers' \
      "$LABWC_WALLPAPERS_TAG" \
      "$LABWC_WALLPAPERS_URL" \
      "$LABWC_WALLPAPERS_SHA256" \
      wallpapers.tar.gz \
      "$archive_host"; then
    rm -f -- "$archive_host" "$archive_target_host"
    installer_fatal "failed to fetch desktop wallpaper release archive: ${LABWC_WALLPAPERS_URL}"
  fi
  [ -f "$archive_host" ] && [ ! -L "$archive_host" ] ||
    installer_fatal "desktop wallpaper release archive is not a regular file: ${LABWC_WALLPAPERS_URL}"

  install -m 0600 "$archive_host" "$archive_target_host"
  rm -f -- "$archive_host"

  # shellcheck disable=SC2016
  if ! attempt_in_target "extract managed desktop wallpaper archive" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
archive=$1
destination=$2
__INSTALLER_PATH_DIR_USR_BIN__/install -d -m 0755 -- "$destination"
__INSTALLER_PATH_DIR_USR_BIN__/tar -xzf "$archive" -C "$destination" \
  --no-same-owner \
  --no-same-permissions
# The installer umask is deliberately restrictive. Normalize the authenticated
# public asset tree recursively so nested gallery directories and images remain
# traversable/readable by the desktop account after extraction.
__INSTALLER_PATH_DIR_USR_BIN__/find -P "$destination" -xdev -type d -exec __INSTALLER_PATH_DIR_USR_BIN__/chown root:root -- {} +
__INSTALLER_PATH_DIR_USR_BIN__/find -P "$destination" -xdev -type d -exec __INSTALLER_PATH_DIR_USR_BIN__/chmod 0755 -- {} +
__INSTALLER_PATH_DIR_USR_BIN__/find -P "$destination" -xdev -type f -exec __INSTALLER_PATH_DIR_USR_BIN__/chown root:root -- {} +
__INSTALLER_PATH_DIR_USR_BIN__/find -P "$destination" -xdev -type f -exec __INSTALLER_PATH_DIR_USR_BIN__/chmod 0644 -- {} +
__INSTALLER_PATH_DIR_USR_BIN__/rm -f -- "$archive"
' sh "$archive_target" __INSTALLER_PATH_DIR_USR_SHARE__/backgrounds/desktop
  then
    rm -f -- "$archive_target_host"
    installer_fatal "failed to extract the verified desktop wallpaper release archive"
  fi

  [ ! -e "$archive_target_host" ] && [ ! -L "$archive_target_host" ] ||
    installer_fatal "desktop wallpaper archive remained in the target after extraction"
  desktop_log \
    "extracted_wallpaper_archive source=${LABWC_WALLPAPERS_URL} tag=${LABWC_WALLPAPERS_TAG} target=__INSTALLER_PATH_DIR_USR_SHARE__/backgrounds/desktop"
}

desktop_target_tree_size_kib() {
  size_label=$1
  target_path=$2

  case "$target_path" in
    /*) ;;
    *)
      installer_fatal "desktop target size path must be absolute: ${target_path:-unset}"
      ;;
  esac
  case "$target_path" in
    /|*..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*)
      installer_fatal "desktop target size path is unsafe: ${target_path}"
      ;;
  esac

  target_size_kib=$(
    capture_in_target \
      "$size_label" \
      __INSTALLER_PATH_DIR_USR_BIN__/du -sk -- "$target_path" |
      awk 'NR == 1 { print $1; exit }'
  )
  case "$target_size_kib" in
    ''|*[!0123456789]*)
      installer_fatal \
        "desktop target size measurement returned an invalid value for ${target_path}: ${target_size_kib:-unset}"
      ;;
  esac

  printf '%s\n' "$target_size_kib"
}

desktop_double_quote_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

desktop_toml_escape() {
  desktop_double_quote_escape "$1"
}

desktop_xml_attribute_escape() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/"/\&quot;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

desktop_primary_account_ids() {
  wanted_user=${1:-${ACCOUNT_USERNAME:-}}

  [ -n "$wanted_user" ] || return 1
  awk -F: -v wanted_user="$wanted_user" '$1 == wanted_user { print $3 ":" $4; exit }' ${TARGET_ROOT}${DIR_ETC}/passwd 2>__INSTALLER_PATH_DIR_DEV__/null
}

desktop_transient_pipx_build_account_prepare() {
  build_account=$1
  build_home=$2
  shift 2

  case "$build_account" in
    ''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-]*)
      installer_fatal "transient pipx build account contains unsupported characters"
      ;;
  esac
  case "$build_home" in
    /|*..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*)
      installer_fatal "transient pipx build home contains unsupported syntax: ${build_home}"
      ;;
  esac
  [ "$#" -ge 1 ] ||
    installer_fatal "transient pipx build account requires managed writable paths"
  for build_path in "$@"; do
    case "$build_path" in
      /|*..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*)
        installer_fatal "transient pipx managed path contains unsupported syntax: ${build_path}"
        ;;
    esac
  done

  # The installer runs third-party pipx package hooks under this locked,
  # short-lived identity, with a private HOME rather than the eventual desktop
  # account's home. The installer grants managed write access only to the
  # caller-created runtime paths.
  # shellcheck disable=SC2016 # The quoted program executes inside the target.
  run_in_target "prepare transient pipx build account ${build_account}" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
account=$1
build_home=$2
shift 2

case "$account" in
  ""|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-]*)
    printf "%s\n" "transient pipx build account contains unsupported characters" >&2
    exit 1
    ;;
esac
case "$build_home" in
  /|*..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*)
    printf "%s\n" "transient pipx build home contains unsupported syntax" >&2
    exit 1
    ;;
esac
[ "$#" -ge 1 ] || {
  printf "%s\n" "transient pipx build account requires managed writable paths" >&2
  exit 1
}
for build_path; do
  case "$build_path" in
    /|*..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*)
      printf "%s\n" "transient pipx managed path contains unsupported syntax" >&2
      exit 1
      ;;
  esac
  [ -d "$build_path" ] && [ ! -L "$build_path" ] || {
    printf "%s\n" "transient pipx managed path is missing or symbolic" >&2
    exit 1
  }
done
[ -d "$build_home" ] && [ ! -L "$build_home" ] || {
  printf "%s\n" "transient pipx build home is missing or symbolic" >&2
  exit 1
}
[ -x __INSTALLER_PATH_DIR_USR_BIN__/awk ] &&
  [ -x __INSTALLER_PATH_DIR_USR_SBIN__/useradd ] &&
  [ -x __INSTALLER_PATH_DIR_USR_BIN__/chown ] &&
  [ -x __INSTALLER_PATH_DIR_USR_BIN__/chmod ] &&
  [ -x __INSTALLER_PATH_DIR_USR_BIN__/install ] ||
  {
    printf "%s\n" "transient pipx build account prerequisites are unavailable" >&2
    exit 1
  }

if __INSTALLER_PATH_DIR_USR_BIN__/awk -F: -v account="$account" '"'"'$1 == account { found = 1; exit } END { exit !found }'"'"' __INSTALLER_PATH_DIR_ETC__/passwd ||
  __INSTALLER_PATH_DIR_USR_BIN__/awk -F: -v account="$account" '"'"'$1 == account { found = 1; exit } END { exit !found }'"'"' __INSTALLER_PATH_DIR_ETC__/group
then
  printf "%s\n" "transient pipx build account or group already exists" >&2
  exit 1
fi

__INSTALLER_PATH_DIR_USR_SBIN__/useradd \
  --system \
  --no-create-home \
  --shell __INSTALLER_PATH_DIR_USR_SBIN__/nologin \
  --user-group \
  -- "$account"

for build_path; do
  __INSTALLER_PATH_DIR_USR_BIN__/chown "$account:$account" "$build_path"
  __INSTALLER_PATH_DIR_USR_BIN__/chmod 0755 "$build_path"
done
__INSTALLER_PATH_DIR_USR_BIN__/chown "$account:$account" "$build_home"
__INSTALLER_PATH_DIR_USR_BIN__/chmod 0700 "$build_home"
__INSTALLER_PATH_DIR_USR_BIN__/install -d -o "$account" -g "$account" -m 0700 "$build_home/tmp"
' sh "$build_account" "$build_home" "$@"
}

desktop_transient_pipx_build_account_destroy() {
  build_account=$1
  build_home=$2

  case "$build_account" in
    ''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-]*)
      installer_fatal "transient pipx build account contains unsupported characters"
      ;;
  esac
  case "$build_home" in
    /|*..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*)
      installer_fatal "transient pipx build home contains unsupported syntax: ${build_home}"
      ;;
  esac

  # Do not use a UID-wide kill here: in-target is chroot-based and may share
  # the installer process namespace. A non-forced userdel fails closed if the
  # transient builder cannot be removed, before root seals the runtime.
  # shellcheck disable=SC2016 # The quoted program executes inside the target.
  run_in_target "destroy transient pipx build account ${build_account}" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
account=$1
build_home=$2

case "$account" in
  ""|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-]*)
    printf "%s\n" "transient pipx build account contains unsupported characters" >&2
    exit 1
    ;;
esac
case "$build_home" in
  /|*..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*)
    printf "%s\n" "transient pipx build home contains unsupported syntax" >&2
    exit 1
    ;;
esac
[ -d "$build_home" ] && [ ! -L "$build_home" ] || {
  printf "%s\n" "transient pipx build home is missing or symbolic" >&2
  exit 1
}
[ -x __INSTALLER_PATH_DIR_USR_BIN__/awk ] &&
  [ -x __INSTALLER_PATH_DIR_USR_BIN__/find ] &&
  [ -x __INSTALLER_PATH_DIR_USR_BIN__/rmdir ] &&
  [ -x __INSTALLER_PATH_DIR_USR_SBIN__/userdel ] &&
  [ -x __INSTALLER_PATH_DIR_USR_SBIN__/groupdel ] ||
  {
    printf "%s\n" "transient pipx build account cleanup prerequisites are unavailable" >&2
    exit 1
  }
__INSTALLER_PATH_DIR_USR_SBIN__/userdel -- "$account"
if __INSTALLER_PATH_DIR_USR_BIN__/awk -F: -v account="$account" '"'"'$1 == account { found = 1; exit } END { exit !found }'"'"' __INSTALLER_PATH_DIR_ETC__/group
then
  __INSTALLER_PATH_DIR_USR_SBIN__/groupdel -- "$account"
fi
if __INSTALLER_PATH_DIR_USR_BIN__/awk -F: -v account="$account" '"'"'$1 == account { found = 1; exit } END { exit !found }'"'"' __INSTALLER_PATH_DIR_ETC__/passwd ||
  __INSTALLER_PATH_DIR_USR_BIN__/awk -F: -v account="$account" '"'"'$1 == account { found = 1; exit } END { exit !found }'"'"' __INSTALLER_PATH_DIR_ETC__/group
then
  printf "%s\n" "transient pipx build account cleanup left an identity behind" >&2
  exit 1
fi
__INSTALLER_PATH_DIR_USR_BIN__/find "$build_home" -xdev -depth -mindepth 1 -delete
__INSTALLER_PATH_DIR_USR_BIN__/rmdir -- "$build_home"
' sh "$build_account" "$build_home"
}
