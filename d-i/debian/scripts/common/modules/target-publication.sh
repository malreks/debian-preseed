#!/bin/sh
# Role-independent target publication, using the one placeholder renderer.
# The target must be offline, root-owned and private from account processes.
unset INSTALLER_TARGET_CONTEXT_READY INSTALLER_TARGET_CONTEXT_ROOT \
  INSTALLER_TARGET_CONTEXT_INODE INSTALLER_TARGET_CONTEXT_MOUNT
installer_target_context_init() {
  target_context_root=${TARGET_ROOT:-}
  case "$target_context_root" in /*) ;; *) installer_fatal 'target context requires the authenticated di.env target root'; return 1 ;; esac
  case "$target_context_root" in /|*//*|*/../*|*/..|*/./*|*/.|*/|*[!A-Za-z0-9_./@+-]*)
    installer_fatal 'target context root is not normalized'; return 1 ;; esac
  [ -z "${INSTALLER_TARGET_DIR:-}" ] || [ "$INSTALLER_TARGET_DIR" = "$target_context_root" ] || {
    installer_fatal 'target context disagrees with the mounted target contract'; return 1;
  }
  for target_context_forbidden in "${INSTALLER_ROOT:-}" "${DIR_INSTALLER_ROOT:-}"; do
    [ -z "$target_context_forbidden" ] || [ "$target_context_root" != "$target_context_forbidden" ] || {
      installer_fatal 'target context aliases the installer root'; return 1;
    }
  done
  [ -d "$target_context_root" ] && [ ! -L "$target_context_root" ] &&
    [ "$(readlink -f -- "$target_context_root")" = "$target_context_root" ] || {
      installer_fatal 'target context root is absent or a symlink alias'; return 1;
    }
  command -v installer_mounts_find_record >/dev/null 2>&1 &&
    installer_mounts_find_record "$target_context_root" "${INSTALLER_MOUNTS_FILE:-/proc/mounts}" &&
    [ "$INSTALLER_MOUNT_POINT" = "$target_context_root" ] || {
      installer_fatal 'target context is not the mounted d-i target'; return 1;
    }
  target_context_listing=$(LC_ALL=C ls -id -- "$target_context_root") || return 1
  IFS=' ' read -r target_context_inode target_context_ignored <<EOF
$target_context_listing
EOF
  case "$target_context_inode" in ''|*[!0-9]*) return 1 ;; esac
  target_context_mount="${INSTALLER_MOUNT_SOURCE:-}:${INSTALLER_MOUNT_FSTYPE:-}:${INSTALLER_MOUNT_OPTIONS:-}"
  if [ "${INSTALLER_TARGET_CONTEXT_READY:-0}" = 1 ]; then
    [ "$INSTALLER_TARGET_CONTEXT_ROOT" = "$target_context_root" ] &&
      [ "$INSTALLER_TARGET_CONTEXT_INODE" = "$target_context_inode" ] &&
      [ "$INSTALLER_TARGET_CONTEXT_MOUNT" = "$target_context_mount" ] || {
        installer_fatal 'validated target context identity changed'; return 1;
      }
    return 0
  fi
  [ "$(installer_metadata_value "$target_context_root" uid)" = 0 ] || {
    installer_fatal 'target context must be root-owned'; return 1;
  }
  case "$(installer_metadata_value "$target_context_root" mode)" in 700|750|755) ;;
    *) installer_fatal 'target context has unsafe permissions'; return 1 ;;
  esac
  INSTALLER_TARGET_CONTEXT_ROOT=$target_context_root
  INSTALLER_TARGET_CONTEXT_INODE=$target_context_inode
  INSTALLER_TARGET_CONTEXT_MOUNT=$target_context_mount
  INSTALLER_TARGET_CONTEXT_READY=1
}

installer_target_context_path() {
  installer_target_context_init || return 1
  printf '%s\n' "$INSTALLER_TARGET_CONTEXT_ROOT"
}

# Publication state has one serial owner: installer phase dispatch. Records
# are an append-only private journal keyed by the exact destination string,
# not path hashes. A last-record-wins snapshot removes updates/tombstones in one
# AWK pass at finish-install. A partial row after interruption is rejected.
installer_target_ownership_prepare() {
  ownership_root=${DIR_INSTALLER_TARGET_OWNERSHIP:?installer ownership contract is unavailable}
  installer_lifecycle_parent_safe "$ownership_root" || installer_fatal 'unsafe target ownership ancestry'
  [ -d "$ownership_root" ] || mkdir -m 0700 "$ownership_root" || return 1
  [ ! -L "$ownership_root" ] &&
    [ "$(installer_metadata_value "$ownership_root" uid_gid_mode)" = '0:0:700' ] ||
    installer_fatal 'target ownership directory is not private'
  ownership_journal=$ownership_root/journal.tsv
  if [ ! -e "$ownership_journal" ] && [ ! -L "$ownership_journal" ]; then
    (umask 077; set -C; : >"$ownership_journal") || return 1
  fi
  [ -f "$ownership_journal" ] && [ ! -L "$ownership_journal" ] &&
    [ "$(installer_metadata_value "$ownership_journal" uid_gid_mode_links)" = '0:0:600:1' ] ||
    installer_fatal 'unsafe target ownership journal'
}

installer_target_ownership_record() (
  set -eu
  umask 077
  ownership_source=$1; ownership_target=$2; ownership_kind=$3; ownership_mode=$4
  case "$ownership_target" in
    "${DIR_TMP:-}/installer-"*|"${DIR_TMP:-}/install-"*/*) ownership_kind=template-input ;;
  esac
  ownership_phase=${INSTALLER_PHASE:-late-command}
  case "$ownership_source" in -) ownership_source=generated ;; esac
  case "$ownership_source" in
    *[!A-Za-z0-9_./@+:\ -]*|'') installer_fatal 'invalid target ownership source'; exit 1 ;;
  esac
  for ownership_context in "$ownership_phase" "$ownership_kind"; do
    case "$ownership_context" in *[!A-Za-z0-9_./@+:-]*|'') installer_fatal 'invalid target ownership context'; exit 1 ;; esac
  done
  case "$ownership_target" in /*) ;; *) installer_fatal 'target ownership path is not absolute'; exit 1 ;; esac
  case "$ownership_target" in
    /|*//*|*/../*|*/..|*/./*|*/.|*[!A-Za-z0-9_./@+\ -]*) installer_fatal 'target ownership path is not normalized'; exit 1 ;;
  esac
  case "$ownership_mode" in [0-7][0-7][0-7]|0[0-7][0-7][0-7]) ;; *) exit 1 ;; esac
  installer_target_ownership_prepare
  printf '%s\t%s\t%s\t%s\t%s\n' "$ownership_target" "$ownership_source" \
    "$ownership_kind" "$ownership_phase" "$ownership_mode" >>"$ownership_journal"
)

installer_target_ownership_forget() {
  installer_target_ownership_record generated "$1" deleted 0000
}

# One grammar owns imported batches and journal snapshots. BusyBox AWK ends
# slash-delimited expressions even inside character classes, so every literal
# slash is escaped. Import validation does not retain rows or build arrays.
installer_target_ownership_filter() {
  case "$1" in validate|snapshot) ;; *) return 1 ;; esac
  LC_ALL=C awk -F '\t' -v ownership_action="$1" '
    NF != 5 || length($0) > 16384 || ++count > 20000 { bad=1; exit }
    $1 !~ /^\// || $1 ~ /(^\/$|\/\/|\/(\.\.?)(\/|$))/ { bad=1; exit }
    $1 ~ /[^A-Za-z0-9_.\/@+ -]/ || $2 !~ /^[A-Za-z0-9_.\/@+: -]+$/ { bad=1; exit }
    $3 !~ /^[A-Za-z0-9_.\/@+:-]+$/ || $4 !~ /^[A-Za-z0-9_.\/@+:-]+$/ { bad=1; exit }
    $5 !~ /^0?[0-7][0-7][0-7]$/ { bad=1; exit }
    ownership_action == "snapshot" { rows[$1]=$0; kinds[$1]=$3 }
    END {
      if (bad || !count) exit 1
      if (ownership_action == "snapshot")
        for (path in rows) if (kinds[path] != "deleted") print rows[path]
    }
  ' "$2"
}

# Import a complete batch after its last successful atomic publication. The
# private source is produced by the shared renderer, never a target program.
installer_target_ownership_import() (
  set -eu
  ownership_input=$1
  [ -f "$ownership_input" ] && [ ! -L "$ownership_input" ] &&
    [ "$(installer_metadata_value "$ownership_input" uid_gid_mode_links)" = '0:0:600:1' ] ||
    installer_fatal 'unsafe target ownership batch'
  installer_target_ownership_prepare
  installer_target_ownership_filter validate "$ownership_input" ||
    installer_fatal 'malformed target ownership batch'
  cat "$ownership_input" >>"$ownership_journal"
)

installer_target_ownership_snapshot() (
  set -eu
  installer_target_ownership_prepare
  [ "$(wc -c <"$ownership_journal")" -le 16777216 ] || installer_fatal 'excessive target ownership journal'
  installer_target_ownership_filter snapshot "$ownership_journal"
)

# Plans and candidates stay in the already authenticated target workspace.
# Each flush is a dependency barrier: only then may a target program or a
# shell-side reader observe the files. No Perl is required in early d-i.
installer_asset_batch_begin() {
  [ -n "${BOOTSTRAP_PREPARED_SOURCE_ROOT:-}" ] || {
    installer_fatal 'asset publication requires the prepared base-stage payload'; return 1;
  }
  if [ -n "${INSTALLER_ASSET_BATCH_WORK:-}" ]; then
    INSTALLER_ASSET_BATCH_DEPTH=$((INSTALLER_ASSET_BATCH_DEPTH + 1))
    export INSTALLER_ASSET_BATCH_DEPTH
    return 0
  fi
  installer_target_context_init || return 1
  installer_asset_group=$1
  case "$installer_asset_group" in ''|*[!a-z0-9-]*) installer_fatal 'invalid publication group'; return 1 ;; esac
  installer_asset_stage=${BOOTSTRAP_PREPARED_SOURCE_ROOT%/source}
  installer_apt_safe_path "$installer_asset_stage/inputs" || return 1
  INSTALLER_ASSET_BATCH_WORK=$(umask 077; mktemp -d "$installer_asset_stage/inputs/publish.XXXXXX") || return 1
  INSTALLER_ASSET_BATCH_DEPTH=1
  INSTALLER_ASSET_BATCH_GROUP=$installer_asset_group
  export INSTALLER_ASSET_BATCH_WORK INSTALLER_ASSET_BATCH_DEPTH INSTALLER_ASSET_BATCH_GROUP
  (umask 077
    : >"$INSTALLER_ASSET_BATCH_WORK/plan"
    printf 'FORMAT=1\nSUITE=%s\nFAMILY=%s\nPHASE=%s\nGROUP=%s\nDEFAULTS_ROOT=%s\nTEMP_ROOT=%s\nSKELETON_BASE=%s\nSKELETON_DESKTOP=%s\nSKELETON_SERVER=%s\nACCOUNT_HOME=%s\nSOURCE_ARCHIVE_SHA256=%s\nSOURCE_TARGET_ROOT=%s\n' \
      "$INSTALLER_SUITE" "$INSTALLER_HOST_VARIANT" "${INSTALLER_PHASE:-late-command}" \
      "$installer_asset_group" "$DIR_INSTALLER_TARGET_DEFAULTS" "$DIR_TMP" \
      "$DIR_ETC_SKEL_BASE" "$DIR_ETC_SKEL_DESKTOP" "$DIR_ETC_SKEL_SERVER" \
      "${ACCOUNT_HOME:-$DIR_ROOT_HOME}" "$BOOTSTRAP_PREPARED_ARCHIVE_SHA256" "$DIR_HOOKS_TARGET" \
      >"$INSTALLER_ASSET_BATCH_WORK/context"
    printf 'SOURCE_AA_ROOT=%s\nSOURCE_APPARMOR_ROOT=%s\nSOURCE_TMPFILES_ROOT=%s\nSOURCE_SYSCTL_ROOT=%s\nSOURCE_BIN_ROOT=%s\nSOURCE_SBIN_ROOT=%s\nSOURCE_LIBEXEC_ROOT=%s\nSOURCE_LIB_ROOT=%s\nSOURCE_SHARE_ROOT=%s\nSOURCE_SYSTEMD_ROOT=%s\nSOURCE_SYSTEMD_COMMON=%s\nSOURCE_SYSTEMD_DESKTOP=%s\nSOURCE_SYSTEMD_SERVER=%s\nSOURCE_APT_ROOT=%s\nSOURCE_APT_DESKTOP=%s\nSOURCE_APT_SERVER=%s\nSOURCE_FRONTEND_ROOT=%s\n' \
      "$DIR_TARGET_AA" "$DIR_TARGET_APPARMOR" "$DIR_TARGET_TMPFILES_D" "$DIR_TARGET_SYSCTL_D" \
      "$DIR_TARGET_BIN" "$DIR_TARGET_SBIN" "$DIR_TARGET_LIBEXEC" "$DIR_TARGET_LIB" "$DIR_TARGET_SHARE" \
      "$DIR_TARGET_SYSTEMD" "$DIR_TARGET_SYSTEMD_COMMON" "$DIR_TARGET_SYSTEMD_DESKTOP" "$DIR_TARGET_SYSTEMD_SERVER" \
      "$DIR_TARGET_APT" "$DIR_TARGET_APT_DESKTOP" "$DIR_TARGET_APT_SERVER" "$DIR_FRONTEND" \
      >>"$INSTALLER_ASSET_BATCH_WORK/context"
  )
}

installer_asset_plan_fields() {
  for installer_asset_field do
    [ "${#installer_asset_field}" -le 1048576 ] || return 1
    printf '%s:%s,' "${#installer_asset_field}" "$installer_asset_field" || return 1
  done
}

installer_asset_batch_add() {
  [ -n "${INSTALLER_ASSET_BATCH_WORK:-}" ] && [ ! -e "$INSTALLER_ASSET_BATCH_WORK/failed" ] || return 1
  installer_asset_kind=$1; installer_asset_source=$2; installer_asset_target=$3; installer_asset_mode=$4
  case "$installer_asset_target" in
    "$TARGET_ROOT"/*) installer_asset_target=${installer_asset_target#"$TARGET_ROOT"} ;;
  esac
  shift 4
  [ "$#" -le 1024 ] && [ $(( $# % 2 )) -eq 0 ] || return 1
  # POSIX parameter length must count bytes, including under UTF-8 locales.
  installer_asset_lc_set=${LC_ALL+x}; installer_asset_lc=${LC_ALL-}
  LC_ALL=C
  {
    [ -s "$INSTALLER_ASSET_BATCH_WORK/plan" ] || printf 'publication-plan-v1\n'
    printf '%s\n' "$((9 + $#))"
    installer_asset_plan_fields "$installer_asset_kind" "$installer_asset_source" \
      "$installer_asset_target" "$installer_asset_mode" 0:0 "$INSTALLER_HOST_VARIANT" \
      "$INSTALLER_SUITE" "${INSTALLER_PHASE:-late-command}" "$INSTALLER_ASSET_BATCH_GROUP" "$@"
  } >>"$INSTALLER_ASSET_BATCH_WORK/plan"
  installer_asset_plan_status=$?
  if [ "$installer_asset_lc_set" = x ]; then LC_ALL=$installer_asset_lc; else unset LC_ALL; fi
  return "$installer_asset_plan_status"
}

installer_asset_batch_flush() {
  [ -n "${INSTALLER_ASSET_BATCH_WORK:-}" ] || return 0
  [ ! -e "$INSTALLER_ASSET_BATCH_WORK/failed" ] || return 1
  [ -s "$INSTALLER_ASSET_BATCH_WORK/plan" ] || return 0
  installer_target_context_init || return 1
  installer_asset_stage=${BOOTSTRAP_PREPARED_SOURCE_ROOT%/source}
  if installer_run_bounded 120 chroot "$TARGET_ROOT" "${DIR_USR_BIN}/env" -i \
      HOME="$DIR_ROOT_HOME" PATH="${DIR_USR_BIN}:${DIR_BIN}" LC_ALL=C \
      "${DIR_USR_BIN}/perl" -f "${installer_asset_stage#"$TARGET_ROOT"}/render.pl" \
      --publish "${INSTALLER_ASSET_BATCH_WORK#"$TARGET_ROOT"}" "${installer_asset_stage#"$TARGET_ROOT"}" \
      >"$INSTALLER_ASSET_BATCH_WORK/log" 2>&1; then
    :
  else
    installer_asset_status=$?
    : >"$INSTALLER_ASSET_BATCH_WORK/failed"
    cat "$INSTALLER_ASSET_BATCH_WORK/log" >&2
    installer_error "asset publication failed; private plan and recovery evidence retained: ${INSTALLER_ASSET_BATCH_WORK#"$TARGET_ROOT"}"
    return "$installer_asset_status"
  fi
  if ! installer_target_ownership_import "$INSTALLER_ASSET_BATCH_WORK/ownership.tsv"; then
    : >"$INSTALLER_ASSET_BATCH_WORK/failed"
    installer_error 'asset publication completed but ownership import failed; private plan retained'
    return 1
  fi
  cat "$INSTALLER_ASSET_BATCH_WORK/log" >&2
  if ! rm -f -- "$INSTALLER_ASSET_BATCH_WORK/ownership.tsv" "$INSTALLER_ASSET_BATCH_WORK/report" \
      "$INSTALLER_ASSET_BATCH_WORK/log" "$INSTALLER_ASSET_BATCH_WORK"/input.*; then
    : >"$INSTALLER_ASSET_BATCH_WORK/failed"
    installer_error 'published asset batch cleanup failed; retained plan must not be replayed'
    return 1
  fi
  : >"$INSTALLER_ASSET_BATCH_WORK/plan" || {
    : >"$INSTALLER_ASSET_BATCH_WORK/failed"
    return 1
  }
}

installer_asset_batch_finish() {
  [ -n "${INSTALLER_ASSET_BATCH_WORK:-}" ] || return 0
  if [ "$INSTALLER_ASSET_BATCH_DEPTH" -gt 1 ]; then
    INSTALLER_ASSET_BATCH_DEPTH=$((INSTALLER_ASSET_BATCH_DEPTH - 1))
    return 0
  fi
  installer_asset_batch_flush || return $?
  rm -f -- "$INSTALLER_ASSET_BATCH_WORK/plan" "$INSTALLER_ASSET_BATCH_WORK/context" || return 1
  rmdir "$INSTALLER_ASSET_BATCH_WORK" || return 1
  unset INSTALLER_ASSET_BATCH_WORK INSTALLER_ASSET_BATCH_DEPTH INSTALLER_ASSET_BATCH_GROUP
}

installer_asset_publish() {
  if [ -n "${INSTALLER_ASSET_BATCH_WORK:-}" ]; then
    installer_asset_batch_add "$@"
  else
    (set -eu; installer_asset_batch_begin single-asset; installer_asset_batch_add "$@"; installer_asset_batch_finish)
  fi
}

installer_primary_default_path() (
  case "$1" in
    "${DIR_ETC_SKEL_DESKTOP}/"*) default_family=desktop; default_relative=${1#"${DIR_ETC_SKEL_DESKTOP}/"} ;;
    "${DIR_ETC_SKEL_SERVER}/"*) default_family=server; default_relative=${1#"${DIR_ETC_SKEL_SERVER}/"} ;;
    *) exit 1 ;;
  esac
  printf '%s/%s/%s\n' "$DIR_INSTALLER_TARGET_DEFAULTS" "$default_family" "$default_relative"
)

installer_capture_primary_default() (
  set -eu
  umask 077
  default_input=$1; default_target=$2; default_mode=$3
  default_output=$(installer_primary_default_path "$default_target") || exit 0
  default_output="${TARGET_ROOT}${default_output}"
  installer_apt_safe_path "$default_output" || installer_fatal 'unsafe primary payload default ancestry'
  default_family=${default_output#"${TARGET_ROOT}${DIR_INSTALLER_TARGET_DEFAULTS}/"}
  default_family=${default_family%%/*}
  install -d -m 0700 -- "${TARGET_ROOT}${DIR_INSTALLER_TARGET_DEFAULTS}" \
    "${TARGET_ROOT}${DIR_INSTALLER_TARGET_DEFAULTS}/${default_family}"
  install -d -m 0700 -- "${default_output%/*}"
  default_work=$(mktemp "${default_output%/*}/.payload-default.XXXXXX")
  trap 'rm -f -- "$default_work"' 0
  trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
  install -m "$default_mode" -- "$default_input" "$default_work"
  chown root:root "$default_work"
  mv -fT -- "$default_work" "$default_output"
)

installer_publish_primary_defaults() {
  case "$#" in
    3)
      installer_run_target_setup scripts/common/primary-defaults.py 'publish rendered payload defaults for the primary account' \
        publish "${DIR_INSTALLER_TARGET_DEFAULTS}/$1" "$2" "$3"
      ;;
    4)
      installer_run_target_setup scripts/common/primary-defaults.py 'publish one rendered payload default for the primary account' \
        publish "${DIR_INSTALLER_TARGET_DEFAULTS}/$1" "$2" "$3" --relative "$4"
      ;;
    *) installer_fatal 'primary payload publication requires a family, account, home and optional relative file'; return 1 ;;
  esac
}

installer_stage_account_creation() {
  # This is the only installed helper permitted to read private templates:
  # an administrator explicitly creates an account and selects its type.
  installer_apt_safe_path "${TARGET_ROOT}${DIR_USR_LOCAL_SBIN}" || installer_fatal 'unsafe account helper ancestry'
  install -d -m 0755 -- "${TARGET_ROOT}${DIR_USR_LOCAL_SBIN}"
  installer_stage_profile_file hooks/target/usr/local/sbin/common/account-create "$FILE_ACCOUNT_CREATE" 0755
  installer_stage_profile_file hooks/target/etc/skel-base/.profile \
    "${DIR_ETC_SKEL_BASE}/.profile" 0644
  installer_stage_profile_file hooks/target/etc/skel-base/.bash_profile \
    "${DIR_ETC_SKEL_BASE}/.bash_profile" 0644
  installer_stage_profile_file hooks/target/etc/skel-base/.bashrc \
    "${DIR_ETC_SKEL_BASE}/.bashrc" 0644
  installer_stage_profile_file hooks/target/etc/skel-base/.bash_logout \
    "${DIR_ETC_SKEL_BASE}/.bash_logout" 0644
}

installer_stage_profile_asset() (
  set -eu
  [ -z "${INSTALLER_ASSET_BATCH_WORK:-}" ] || installer_asset_batch_flush || exit $?
  installer_target_context_init || exit 1
  source_path=$1; target_path=$2; asset_mode=$3
  if command -v installer_operation_context >/dev/null 2>&1; then
    installer_operation_context "$source_path" 1 stage_profile_asset
  fi
  installer_repo_assert_asset_family "$source_path"
  case "$target_path" in /*) ;; *) installer_fatal 'target path must be absolute' ;; esac
  case "$asset_mode" in 0[0-7][0-7][0-7]) ;; *) installer_fatal 'invalid target asset mode' ;; esac
  if bootstrap_prepared_asset_published "$source_path" "$target_path" "$asset_mode"; then
    exit 0
  fi
  installer_apt_safe_path "${TARGET_ROOT}${target_path}" || installer_fatal 'untrusted target asset ancestry'
  # Skeletons are private defaults for privileged account provisioning. Target
  # users consume their own published files, never the root-owned defaults.
  for skeleton in "${DIR_ETC_SKEL_BASE:-}" "${DIR_ETC_SKEL_DESKTOP:-}" "${DIR_ETC_SKEL_SERVER:-}"; do
    [ -n "$skeleton" ] || continue
    case "$target_path" in
      "$skeleton"|"$skeleton/"*)
        install -d -m 0700 -- "${TARGET_ROOT}${skeleton}"
        chown root:root "${TARGET_ROOT}${skeleton}"
        chmod 0700 "${TARGET_ROOT}${skeleton}"
        ;;
    esac
  done
  parent="${TARGET_ROOT}${target_path%/*}"
  if [ ! -d "$parent" ]; then install -d -m 0755 "$parent"; fi
  installer_apt_safe_path "$parent" || installer_fatal 'target ancestry changed before publication'
  input=$(mktemp "${DIR_INSTALLER_LATE_ENV}/profile-asset.XXXXXX")
  output=$(mktemp "$parent/.profile-asset.XXXXXX")
  trap 'rm -f "$input" "$output"' 0
  trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
  if command -v installer_info >/dev/null 2>&1; then
    installer_info "staging target asset source=${source_path} destination=${target_path}"
  fi
  installer_fetch_file "$(installer_seed_base "")" "$source_path" "$input" 0600
  # An identifier segment cannot consume the closing delimiter and an adjacent
  # token. Greedy underscore matching turns two required fields into one name.
  case "$source_path" in
    *.tmpl) profile_token_pattern='__(INSTALLER_)?[A-Z][A-Z0-9]*(_[A-Z0-9]+)*__' ;;
    *) profile_token_pattern='__INSTALLER_[A-Z][A-Z0-9]*(_[A-Z0-9]+)*__' ;;
  esac
  names=$(LC_ALL=C grep -oE "$profile_token_pattern" "$input" | sort -u || true)
  set --
  for token in $names; do
    name=${token#__}; name=${name%__}; name=${name#INSTALLER_}
    # Perl's package pseudo-constant is language syntax, not template data.
    case "$name" in PATH_*|PACKAGE) continue ;; *[!A-Z0-9_]*|'') installer_fatal 'invalid placeholder name' ;; esac
    # Only a validated identifier enters indirection. Profile bytes are data.
    present=; value=
    eval "present=\${$name+x}; value=\${$name-}"
    [ "$present" = x ] || installer_fatal "profile asset lacks required field: $name (asset=$source_path)"
    set -- "$@" "$name" "$value"
  done
  if [ "$#" -eq 0 ] && [ -n "${BOOTSTRAP_PREPARED_SOURCE_ROOT:-}" ]; then
    cat "$input" >"$output"
  else
    installer_apply_scalar_placeholders "$input" "$output" "$@"
  fi
  installer_assert_no_unresolved_installer_placeholders "$output" "$source_path"
  remaining=$(LC_ALL=C grep -oE "$profile_token_pattern" "$output" | sort -u || true)
  for token in $remaining; do
    case "$token" in __PACKAGE__) ;; *) installer_fatal "unresolved target asset field: $token (asset=$source_path)" ;; esac
  done
  installer_capture_primary_default "$output" "$target_path" "$asset_mode"
  installer_apt_safe_path "${TARGET_ROOT}${target_path}" || installer_fatal 'target identity changed before publication'
  chmod "$asset_mode" "$output"
  installer_target_ownership_record "$source_path" "$target_path" plain "$asset_mode"
  mv -f "$output" "${TARGET_ROOT}${target_path}"
)

installer_stage_profile_file() {
  installer_stage_profile_asset "$(installer_repo_file_value "$1")" "$2" "$3"
}

# Installation-only Python programs run in a private temporary target directory.
# Always remove the program, including on failure; recovery data has its own
# explicit owner and is never removed here. This publishes no runtime wrapper.
installer_run_target_setup() (
  set -eu
  setup_selector=$1
  setup_context=$2
  shift 2
  setup_parent="${TARGET_ROOT}${DIR_TMP}"
  installer_apt_safe_path "$setup_parent" || installer_fatal 'unsafe installer setup staging ancestry'
  setup_stage=$(mktemp -d "$setup_parent/install-setup.XXXXXX") || exit "$?"
  chmod 0700 "$setup_stage"
  setup_program="${setup_stage#"$TARGET_ROOT"}/setup.py"
  setup_cleanup() {
    setup_status=$?
    trap - 0
    if ! rm -f "$setup_stage/setup.py" || ! rmdir "$setup_stage"; then
      installer_error 'temporary installer program cleanup failed'
      [ "$setup_status" -ne 0 ] || setup_status=1
    fi
    installer_target_ownership_forget "$setup_program" || setup_status=1
    exit "$setup_status"
  }
  trap setup_cleanup 0
  trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
  if [ "$setup_selector" = scripts/server/setup.py.tmpl ]; then
    SERVER_SELECTED_ROLES=$INSTALLER_ROLE_IDS
    SERVER_CODEX_ENABLE=$(installer_plan_value codex_enable) || exit "$?"
    set -- --defaults-root "${DIR_INSTALLER_TARGET_DEFAULTS}/server" "$@"
  fi
  installer_stage_profile_file "$setup_selector" "$setup_program" 0600
  run_in_target "$setup_context" "${DIR_USR_BIN}/python3" -I -B "$setup_program" "$@"
)

installer_stage_offline_unit_link() (
  set -eu
  unit_path=$1
  case "$unit_path" in
    "${DIR_SYSTEMD_SYSTEM}/"*|"${DIR_USR_LIB}/systemd/system/"*) ;;
    *) installer_fatal 'unit is outside the managed/native systemd unit roots' ;;
  esac
  case "${unit_path##*/}" in
    *[!A-Za-z0-9_.@-]*|'') installer_fatal 'invalid offline unit name' ;;
    *.service|*.timer|*.path|*.socket) ;;
    *) installer_fatal 'invalid offline unit type' ;;
  esac
  [ -f "${TARGET_ROOT}${unit_path}" ] && [ ! -L "${TARGET_ROOT}${unit_path}" ] || installer_fatal 'offline unit file is missing or indirect'
  # The native Install section owns activation: suffix guessing puts early
  # services and path watchers under the wrong target.
  entries=$(awk '
    /^[[:space:]]*[#;]/ { next }
    /^[[:space:]]*\[/ { section=$0; gsub(/[[:space:]]/, "", section); next }
    section=="[Install]" && /^[[:space:]]*(WantedBy|RequiredBy|Alias)[[:space:]]*=/ {
      key=$0; sub(/=.*/, "", key); gsub(/[[:space:]]/, "", key)
      value=$0; sub(/^[^=]*=/, "", value)
      n=split(value, words, /[[:space:]]+/)
      for(i=1;i<=n;i++) if(words[i]!="") print key "|" words[i]
    }' "${TARGET_ROOT}${unit_path}")
  [ -n "$entries" ] || installer_fatal 'offline activation requires an explicit unit Install section'
  # Validate every entry before writing any activation link.
  while IFS='|' read -r kind name; do
    case "$name" in ''|*[!A-Za-z0-9_.@-]*|.*|*..*) installer_fatal 'invalid offline activation name' ;; esac
    case "$kind:$name" in
      WantedBy:*.target|WantedBy:*.service|RequiredBy:*.target|RequiredBy:*.service|Alias:*.service|Alias:*.socket) ;;
      *) installer_fatal 'unsupported offline activation entry' ;;
    esac
  done <<EOF
$entries
EOF
  while IFS='|' read -r kind name; do
    case "$kind" in
      WantedBy) relative="$name.wants/${unit_path##*/}" ;;
      RequiredBy) relative="$name.requires/${unit_path##*/}" ;;
      Alias) relative=$name ;;
    esac
    link="${TARGET_ROOT}${DIR_SYSTEMD_SYSTEM}/$relative"
    parent=${link%/*}
    installer_apt_safe_path "$parent" || installer_fatal 'unsafe unit activation ancestry'
    install -d -m 0755 "$parent"
    if [ -L "$link" ]; then [ "$(readlink "$link")" = "$unit_path" ] || installer_fatal 'competing unit owner'
    elif [ -e "$link" ]; then installer_fatal 'unit activation is not a link'
    else ln -s "$unit_path" "$link"; fi
  done <<EOF
$entries
EOF
)
