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

# Publish the same authenticated metadata policy in d-i and in the mounted
# target. Callers supply the destination from the owning path contract.
installer_apt_publish_metadata_policy() (
  set -eu
  umask 077
  metadata_source=$1
  metadata_destination=$2
  [ -f "$metadata_source" ] && [ ! -L "$metadata_source" ] ||
    installer_fatal 'APT metadata policy is missing or indirect'
  grep -Fqx 'Acquire::PDiffs "false";' "$metadata_source" &&
    grep -Fqx '#clear Acquire::Languages;' "$metadata_source" &&
    grep -Fqx 'Acquire::Languages "en";' "$metadata_source" &&
    grep -Fqx 'Acquire::IndexTargets::deb::Translations::DefaultEnabled "true";' "$metadata_source" ||
    installer_fatal 'APT metadata policy must disable PDiffs and select only English Translation indexes'
  installer_apt_safe_path "$metadata_destination" ||
    installer_fatal 'unsafe APT metadata policy destination'
  install -d -m 0755 "${metadata_destination%/*}" || exit "$?"
  metadata_work=$(mktemp "${metadata_destination%/*}/.installer-metadata.XXXXXX") || exit "$?"
  trap 'rm -f "$metadata_work"' 0
  trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
  cat "$metadata_source" >"$metadata_work" || exit "$?"
  chmod 0644 "$metadata_work" || exit "$?"
  installer_apt_safe_path "$metadata_destination" ||
    installer_fatal 'APT metadata policy ancestry changed before publication'
  mv -fT -- "$metadata_work" "$metadata_destination"
)

# During bootstrap, overlay only acquisition/dependency limits. The running
# d-i frontend owns debconf and its descriptors; retain its native 70debconf
# without adding a preconfiguration hook or keeping only its writer open.
# dpkg-preconfigure --apt repurposes stdin, so that partial passthrough setup
# can wait for a reply from the wrong stream. Retain d-i's
# media, NoMount and temporary verification configuration through apt-setup and
# pkgsel. Full replacement starts in late_command, after those consumers finish.
# Preserve the first bytes of each backup leaf; later passes also archive new
# package defaults. Backup contents are never inputs to the managed policy.
installer_apt_install_target_policy() (
  set -eu
  umask 077
  apt_policy_target=$1
  apt_policy_phase=${2:-install}
  case "$apt_policy_target" in ''|/) installer_fatal 'refusing APT directory replacement in the installer root' ;; /*) ;; *) installer_fatal 'APT target must be absolute' ;; esac
  case "$apt_policy_phase" in bootstrap|install|final) ;; *) installer_fatal 'invalid APT publication phase' ;; esac
  installer_apt_load_runtime_paths || installer_fatal 'target APT runtime paths are unavailable'
  apt_policy_active="${apt_policy_target}${DIR_APT_CONF_D}"
  apt_policy_backup="${apt_policy_target}${DIR_APT_CONF_D_BACKUP:?missing APT backup path}"
  installer_apt_safe_path "$apt_policy_active" && installer_apt_safe_path "$apt_policy_backup" ||
    installer_fatal 'unsafe APT directory or backup ancestry'
  [ -d "$apt_policy_target" ] && [ -d "${apt_policy_active%/*}" ] ||
    installer_fatal 'offline target APT directory is unavailable'
  apt_policy_lock="${apt_policy_active%/*}/.installer-apt-policy.lock"
  mkdir -m 0700 "$apt_policy_lock" || installer_fatal 'another APT policy publisher owns the offline target'
  apt_policy_work=
  apt_policy_moved=false
  apt_policy_keep=false
  apt_policy_cleanup() {
    apt_policy_status=$?
    trap - 0 HUP INT TERM
    if [ "$apt_policy_moved" = true ]; then
      # Never discard the previous directory if restoration cannot be proven.
      if [ ! -e "$apt_policy_active" ] && [ ! -L "$apt_policy_active" ] &&
         mv -T -- "$apt_policy_work/previous" "$apt_policy_active" && sync; then
        apt_policy_moved=false
      else
        apt_policy_keep=true
        installer_error "APT policy restoration is outcome-unknown; recovery retained at $apt_policy_work"
        apt_policy_status=125
      fi
    fi
    if [ "$apt_policy_keep" = false ] && [ -n "$apt_policy_work" ]; then
      # These are flat, validated directories created/renamed by this run only.
      for apt_policy_private in new previous backup; do
        if [ -d "$apt_policy_work/$apt_policy_private" ]; then
          rm -f -- "$apt_policy_work/$apt_policy_private/"* \
            "$apt_policy_work/$apt_policy_private/".[!.]* "$apt_policy_work/$apt_policy_private/"..?* &&
            rmdir "$apt_policy_work/$apt_policy_private" || apt_policy_keep=true
        fi
      done
      rm -f -- "$apt_policy_work/input" "$apt_policy_work/catalog" "$apt_policy_work/saved"
      if [ "$apt_policy_keep" = false ]; then rmdir "$apt_policy_work" || apt_policy_keep=true; fi
    fi
    if [ "$apt_policy_keep" = false ]; then
      rmdir "$apt_policy_lock" || apt_policy_status=125
    else
      installer_error "APT policy evidence and lock retained at $apt_policy_work"
      apt_policy_status=125
    fi
    exit "$apt_policy_status"
  }
  trap apt_policy_cleanup 0
  trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
  apt_policy_work=$(mktemp -d "${apt_policy_active%/*}/.installer-apt-policy.XXXXXX") || exit "$?"
  mkdir -m 0755 "$apt_policy_work/new" || exit "$?"
  installer_repo_apt_conf_catalog >"$apt_policy_work/catalog" || exit "$?"
  while IFS='|' read -r apt_policy_leaf apt_policy_selector; do
    if [ "$apt_policy_phase" = bootstrap ]; then
      case "$apt_policy_leaf" in 25no-pdiffs|99noinstall-recommends) ;; *) continue ;; esac
    fi
    case "$apt_policy_leaf" in
      00suite-default-release) [ "$apt_policy_phase" = final ] || continue ;;
      01mok-maintenance-cleanup|99mok-maintenance)
        [ -x "${apt_policy_target}${DIR_USR_LOCAL_LIBEXEC}/apt-mok-prehook" ] &&
          [ -f "${apt_policy_target}${FILE_SECURE_BOOT_CONFIG}" ] || continue ;;
      71labwc-desktop-apps)
        [ -x "${apt_policy_target}${DIR_USR_LOCAL_LIBEXEC}/labwc-wrap-desktop-files" ] || continue ;;
      20listchanges)
        [ -x "${apt_policy_target}${DIR_USR_BIN}/apt-listchanges" ] || continue ;;
      70debconf)
        [ -x "${apt_policy_target}${DIR_USR_SBIN}/dpkg-preconfigure" ] || continue ;;
    esac
    installer_fetch_file "$(installer_seed_base "")" \
      "$(installer_repo_file_value "$apt_policy_selector")" "$apt_policy_work/input" 0600 || exit "$?"
    installer_apply_scalar_placeholders "$apt_policy_work/input" "$apt_policy_work/new/$apt_policy_leaf" || exit "$?"
    if LC_ALL=C grep -qE '__INSTALLER_[A-Z0-9_]+__' "$apt_policy_work/new/$apt_policy_leaf"; then
      installer_fatal "unresolved APT policy placeholder: $apt_policy_leaf"
    fi
    chmod 0644 "$apt_policy_work/new/$apt_policy_leaf" || exit "$?"
  done <"$apt_policy_work/catalog"
  apt_policy_required_files='25no-pdiffs 99noinstall-recommends'
  if [ "$apt_policy_phase" != bootstrap ]; then
    apt_policy_required_files="00CDMountPoint 00installer-policy 00trustcdrom 01autoremove 20auto-upgrades 52unattended-upgrades $apt_policy_required_files"
  fi
  for apt_policy_required in $apt_policy_required_files; do
    [ -f "$apt_policy_work/new/$apt_policy_required" ] ||
      installer_fatal "required managed APT drop-in is unavailable: $apt_policy_required"
  done
  # Reuse the same fail-closed acquisition check used in the d-i root.
  installer_apt_publish_metadata_policy "$apt_policy_work/new/25no-pdiffs" "$apt_policy_work/new/25no-pdiffs" || exit "$?"
  grep -Fqx 'APT::Install-Recommends "false";' "$apt_policy_work/new/99noinstall-recommends" &&
    grep -Fqx 'APT::Install-Suggests "false";' "$apt_policy_work/new/99noinstall-recommends" ||
    installer_fatal 'managed APT install policy must disable Recommends and Suggests'
  if [ -e "$apt_policy_active" ]; then
    [ -d "$apt_policy_active" ] || installer_fatal 'active APT parts path is not a directory'
    # Check every entry before copying or moving anything; never follow links,
    # special files, or package-created directories out of the offline target.
    for apt_policy_old in "$apt_policy_active/"* "$apt_policy_active/".[!.]* "$apt_policy_active/"..?*; do
      [ -e "$apt_policy_old" ] || [ -L "$apt_policy_old" ] || continue
      installer_apt_safe_path "$apt_policy_old" && [ -f "$apt_policy_old" ] &&
        [ "$(installer_metadata_value "$apt_policy_old" links)" = 1 ] ||
        installer_fatal 'APT parts contains an indirect or nonregular entry; original retained'
    done
  fi
  if [ "$apt_policy_phase" = bootstrap ] && [ -d "$apt_policy_active" ]; then
    # In particular, never recreate 00NoMountCDROM after apt-setup/40cdrom has
    # deliberately removed it for physical media. Preserve current d-i bytes
    # and modes, not a hard-coded media type or files recovered from the backup.
    for apt_policy_old in "$apt_policy_active/"* "$apt_policy_active/".[!.]* "$apt_policy_active/"..?*; do
      [ -e "$apt_policy_old" ] || continue
      [ ! -e "$apt_policy_work/new/${apt_policy_old##*/}" ] || continue
      cp -p "$apt_policy_old" "$apt_policy_work/new/${apt_policy_old##*/}" || exit "$?"
    done
  fi
  if [ -e "$apt_policy_backup" ]; then
    [ -d "$apt_policy_backup" ] || installer_fatal 'APT policy backup is not a directory'
    apt_policy_same=false
    if [ -d "$apt_policy_active" ] && [ "$(installer_metadata_value "$apt_policy_active" mode)" = 755 ]; then
      apt_policy_same=true
      for apt_policy_old in "$apt_policy_active/"* "$apt_policy_active/".[!.]* "$apt_policy_active/"..?*; do
        [ -e "$apt_policy_old" ] || continue
        if [ ! -f "$apt_policy_work/new/${apt_policy_old##*/}" ] ||
           [ "$(installer_metadata_value "$apt_policy_old" mode)" != "$(installer_metadata_value "$apt_policy_work/new/${apt_policy_old##*/}" mode)" ] ||
           ! cmp -s "$apt_policy_old" "$apt_policy_work/new/${apt_policy_old##*/}"; then
          apt_policy_same=false
        fi
      done
      for apt_policy_new in "$apt_policy_work/new/"*; do
        [ -f "$apt_policy_active/${apt_policy_new##*/}" ] || apt_policy_same=false
      done
    fi
    if [ "$apt_policy_same" = true ]; then
      installer_info "APT policy already current phase=$apt_policy_phase family=$INSTALLER_HOST_VARIANT"
      exit 0
    fi
  else
    if [ -d "$apt_policy_active" ]; then
      cp -a "$apt_policy_active" "$apt_policy_work/backup" || exit "$?"
    else
      mkdir -m 0700 "$apt_policy_work/backup" || exit "$?"
    fi
    chmod 0700 "$apt_policy_work/backup" || exit "$?"
    sync || exit "$?"
    mv -T -- "$apt_policy_work/backup" "$apt_policy_backup" || exit "$?"
  fi
  # Append only previously unseen names. This captures defaults installed after
  # the base phase while keeping each original backup leaf byte-for-byte.
  if [ -d "$apt_policy_active" ]; then
    for apt_policy_old in "$apt_policy_active/"* "$apt_policy_active/".[!.]* "$apt_policy_active/"..?*; do
      [ -e "$apt_policy_old" ] || continue
      apt_policy_saved="$apt_policy_backup/${apt_policy_old##*/}"
      if [ -e "$apt_policy_saved" ] || [ -L "$apt_policy_saved" ]; then continue; fi
      cp -p "$apt_policy_old" "$apt_policy_work/saved" || exit "$?"
      mv -T -- "$apt_policy_work/saved" "$apt_policy_saved" || exit "$?"
    done
  fi
  sync || exit "$?"
  installer_apt_safe_path "$apt_policy_active" && installer_apt_safe_path "$apt_policy_backup" ||
    installer_fatal 'APT directory ancestry changed before publication'
  if [ -d "$apt_policy_active" ]; then
    mv -T -- "$apt_policy_active" "$apt_policy_work/previous" || exit "$?"
    apt_policy_moved=true
  fi
  mv -T -- "$apt_policy_work/new" "$apt_policy_active" || exit "$?"
  # A failed final sync retains both directories as recovery evidence.
  if ! sync; then apt_policy_keep=true; apt_policy_moved=false; exit 125; fi
  apt_policy_moved=false
  installer_info "published APT policy phase=$apt_policy_phase family=$INSTALLER_HOST_VARIANT backup=$DIR_APT_CONF_D_BACKUP"
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
