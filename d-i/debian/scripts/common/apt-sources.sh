#!/bin/sh
# APT source publication shared by early bootstrap and apt-setup. No APT update
# is safe until this has run; a Pre-Invoke hook would be too late for source parsing.
installer_apt_load_runtime_paths() {
  [ "${INSTALLER_APT_RUNTIME_PATHS_READY:-0}" = 1 ] && return 0
  # The network adapter is invoked after d-i early has already loaded the
  # authenticated host snapshot. Reuse that validated path contract instead of
  # parsing host.env again in the APT child, which otherwise obscures a parser
  # failure as a generic apt-stage status.
  if [ -n "${DIR_APT:-}" ] &&
     [ -n "${DIR_APT_CONF_D:-}" ] &&
     [ -n "${DIR_APT_SOURCES_LIST_D:-}" ] &&
     [ -n "${FILE_APT_DEBIAN_ARCHIVE_KEYRING:-}" ]; then
    INSTALLER_APT_RUNTIME_PATHS_READY=1
    export INSTALLER_APT_RUNTIME_PATHS_READY
    return 0
  fi
  installer_apt_host_env="${DIR_INSTALLER_ENV:-}/host.env"
  if [ -n "${DIR_INSTALLER_ENV:-}" ] && [ -r "$installer_apt_host_env" ]; then
    # shellcheck disable=SC1090,SC1091
    installer_load_data_env "$installer_apt_host_env"
  fi
  [ -n "${DIR_APT:-}" ] &&
    [ -n "${DIR_APT_CONF_D:-}" ] &&
    [ -n "${DIR_APT_SOURCES_LIST_D:-}" ] &&
    [ -n "${FILE_APT_DEBIAN_ARCHIVE_KEYRING:-}" ] || return 1
  INSTALLER_APT_RUNTIME_PATHS_READY=1
}

installer_apt_safe_path() (
  set -eu
  p=$1
  case "$p" in /*) ;; *) exit 1 ;; esac
  case "/${p#/}/" in *'/../'*|*'/./'*|*'//'*) exit 1 ;; esac
  while [ "$p" != / ]; do
    [ ! -L "$p" ] || exit 1
    if [ -e "$p" ]; then
      [ "$(installer_metadata_value "$p" uid)" = "$(id -u)" ] || exit 1
      mode=$(installer_metadata_value "$p" mode) || exit 1
      [ "$((0$mode & 0022))" -eq 0 ] || { [ -d "$p" ] && [ "$((0$mode & 01000))" -ne 0 ]; } || exit 1
    fi
    p=${p%/*}; [ -n "$p" ] || p=/
  done
)

installer_apt_strip_cdrom() (
  set -eu
  umask 077
  if command -v installer_operation_context_repo >/dev/null 2>&1; then
    installer_operation_context_repo FILE_COMMON_APT_SOURCES 30 apt_strip_cdrom
  fi
  target=$1
  installer_apt_load_runtime_paths
  apt_dir=${DIR_APT:?DIR_APT is unavailable}
  apt_sources_dir=${DIR_APT_SOURCES_LIST_D:?DIR_APT_SOURCES_LIST_D is unavailable}
  installer_apt_safe_path "$target${apt_sources_dir}" || exit 1
  for src in "$target${apt_dir}/sources.list" "$target${apt_sources_dir}/"*; do
    [ -e "$src" ] || [ -L "$src" ] || continue
    case "$src" in *.list|*.list.*|*.sources|*.sources.*) ;; *) continue ;; esac
    installer_apt_safe_path "$src" || exit 1
    [ -f "$src" ] && [ "$(installer_metadata_value "$src" links)" = 1 ] || exit 1
    if grep -Fq 'cdrom:' "$src"; then
      :
    else
      source_status=$?
      [ "$source_status" -eq 1 ] && continue
      exit 1
    fi
    tmp=$(mktemp "${src%/*}/.installer-source.XXXXXX") || exit 1
    trap 'rm -f "$tmp"' 0
    case "$src" in
      *.sources|*.sources.*)
        awk 'BEGIN {RS=""; ORS="\n\n"} index($0,"cdrom:")==0 {print}' "$src" >"$tmp" || exit 1 ;;
      *) awk 'index($0,"cdrom:")==0 {print}' "$src" >"$tmp" || exit 1 ;;
    esac
    source_mode=$(installer_metadata_value "$src" mode) || exit 1
    chmod "$source_mode" "$tmp" || exit 1
    mv -fT -- "$tmp" "$src" || exit 1
  done
)

# apt-setup accumulates generator output in sources.list.new. Keep the first
# record for each deb/deb-src target and remove later records for the same URI,
# suite, components, and optional architecture restriction before APT parses
# the completed source list.
installer_apt_dedupe_source_list() (
  set -eu
  umask 077
  source=$1
  [ -f "$source" ] || exit 0
  installer_apt_safe_path "$source" || exit 1
  [ "$(installer_metadata_value "$source" links)" = 1 ] || exit 1
  work=$(mktemp "${source}.dedupe.XXXXXX") || exit 1
  cleanup_source_dedupe() {
    status=$?
    trap - 0 HUP INT TERM
    rm -f "$work"
    exit "$status"
  }
  trap cleanup_source_dedupe 0
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  awk '
    function source_key(raw, words, count, position, option, architecture, key, field) {
      line = raw
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+#.*/, "", line)
      sub(/[[:space:]]+$/, "", line)
      count = split(line, words, /[[:space:]]+/)
      if (count < 4 || (words[1] != "deb" && words[1] != "deb-src")) return ""
      position = 2
      architecture = ""
      if (substr(words[position], 1, 1) == "[") {
        while (position <= count) {
          option = words[position]
          if (option ~ /^\[?arch=/) {
            architecture = option
            sub(/^\[/, "", architecture)
            sub(/]$/, "", architecture)
          }
          if (option ~ /]$/) { position++; break }
          position++
        }
      }
      if (position + 2 > count) return ""
      key = words[1] SUBSEP architecture SUBSEP words[position] SUBSEP words[position + 1]
      for (field = position + 2; field <= count; field++) key = key SUBSEP words[field]
      return key
    }
    {
      key = source_key($0, words, count, position, option, architecture, key, field)
      if (key != "" && seen[key]++) next
      print
    }
  ' "$source" >"$work" || exit 1
  source_mode=$(installer_metadata_value "$source" mode) || exit 1
  chmod "$source_mode" "$work" || exit 1
  mv -fT -- "$work" "$source" || exit 1
  trap - 0 HUP INT TERM
)

installer_apt_bootstrap_source() (
  set -eu
  umask 077
  if command -v installer_operation_context_repo >/dev/null 2>&1; then
    installer_operation_context_repo FILE_COMMON_APT_SOURCES 66 apt_bootstrap_source
  fi
  target=$1; protocol=$2; host=$3; directory=$4; suite=$5
  installer_apt_load_runtime_paths
  apt_dir=${DIR_APT:?DIR_APT is unavailable}
  apt_conf_dir=${DIR_APT_CONF_D:?DIR_APT_CONF_D is unavailable}
  apt_sources_dir=${DIR_APT_SOURCES_LIST_D:?DIR_APT_SOURCES_LIST_D is unavailable}
  archive_keyring=${FILE_APT_DEBIAN_ARCHIVE_KEYRING:?FILE_APT_DEBIAN_ARCHIVE_KEYRING is unavailable}
  case "$protocol" in http|https) ;; *) exit 1 ;; esac
  case "$host" in ''|*[!A-Za-z0-9.:-]*) exit 1 ;; esac
  case "$directory" in /*) ;; *) exit 1 ;; esac
  case "$directory" in *[!A-Za-z0-9/_-]*|*..*|*//*) exit 1 ;; esac
  case "$suite" in ''|*[!A-Za-z0-9_-]*) exit 1 ;; esac
  installer_apt_safe_path "$target${apt_dir}/sources.list" || exit 1
  installer_apt_safe_path "$target${apt_conf_dir}" || exit 1
  [ -s "$target${archive_keyring}" ] || exit 1
  mkdir -p "$target${apt_sources_dir}" "$target${apt_conf_dir}" || exit 1
  installer_apt_strip_cdrom "$target" || exit 1
  tmp=$(mktemp "$target${apt_dir}/.installer-bootstrap.XXXXXX") || exit 1
  trap 'rm -f "$tmp"' 0
  printf 'deb [signed-by=%s] %s://%s%s %s main contrib non-free non-free-firmware\n' \
    "$archive_keyring" "$protocol" "$host" "$directory" "$suite" >"$tmp" || exit 1
  if [ -f "$target${apt_dir}/sources.list" ]; then
    if cmp -s "$tmp" "$target${apt_dir}/sources.list"; then
      source_mode=$(installer_metadata_value "$target${apt_dir}/sources.list" mode) || exit 1
      [ "$source_mode" != 644 ] || exit 0
    else
      source_status=$?
      [ "$source_status" -eq 1 ] || exit 1
    fi
  fi
  chmod 0644 "$tmp" || exit 1
  mv -fT -- "$tmp" "$target${apt_dir}/sources.list" || exit 1
  installer_apt_dedupe_source_list "$target${apt_dir}/sources.list" || exit 1
  # Bootstrap retries/timeouts are command options, never permanent target policy.
)
