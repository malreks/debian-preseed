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

# Publication records remain in the installer. They identify only project-owned
# final files; the final validator must never recursively scan package trees.
installer_target_ownership_record() (
  set -eu
  umask 077
  ownership_source=$1; ownership_target=$2; ownership_kind=$3; ownership_mode=$4
  case "$ownership_target" in
    "${DIR_TMP:-}/installer-"*|"${DIR_TMP:-}/install-"*/*)
      ownership_kind=template-input ;;
  esac
  ownership_phase=${INSTALLER_PHASE:-late-command}
  case "$ownership_source" in -) ownership_source=generated ;; esac
  case "$ownership_source:$ownership_phase:$ownership_kind" in
    *[!A-Za-z0-9_./@+:-]*|'') installer_fatal 'invalid target ownership context'; exit 1 ;;
  esac
  case "$ownership_target" in /*) ;; *) installer_fatal 'target ownership path is not absolute'; exit 1 ;; esac
  case "$ownership_target" in
    /|*//*|*/../*|*/..|*/./*|*/.|*[!A-Za-z0-9_./@+\ -]*)
      installer_fatal 'target ownership path is not normalized'; exit 1 ;;
  esac
  case "$ownership_mode" in [0-7][0-7][0-7]|0[0-7][0-7][0-7]) ;; *) exit 1 ;; esac
  ownership_root=${DIR_INSTALLER_TARGET_OWNERSHIP:?installer ownership contract is unavailable}
  installer_lifecycle_parent_safe "$ownership_root" || installer_fatal 'unsafe target ownership ancestry'
  [ -d "$ownership_root" ] || mkdir -m 0700 "$ownership_root"
  [ "$(installer_metadata_value "$ownership_root" uid_gid_mode)" = '0:0:700' ] ||
    installer_fatal 'target ownership directory is not private'
  ownership_digest=$(printf '%s' "$ownership_target" | sha256sum) || exit 1
  ownership_digest=${ownership_digest%% *}
  case "$ownership_digest" in ''|*[!a-f0-9]*) exit 1 ;; esac
  [ "${#ownership_digest}" -eq 64 ] || exit 1
  ownership_final=$ownership_root/$ownership_digest.tsv
  if [ -e "$ownership_final" ] || [ -L "$ownership_final" ]; then
    [ -f "$ownership_final" ] && [ ! -L "$ownership_final" ] &&
      [ "$(installer_metadata_value "$ownership_final" uid_gid_mode_links)" = '0:0:600:1' ] ||
      installer_fatal 'unsafe target ownership record'
  fi
  ownership_work=$(mktemp "$ownership_root/.record.XXXXXX") || exit 1
  trap 'rm -f -- "$ownership_work"' 0
  trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
  printf '%s\t%s\t%s\t%s\t%s\n' "$ownership_target" "$ownership_source" \
    "$ownership_kind" "$ownership_phase" "$ownership_mode" >"$ownership_work"
  chmod 0600 "$ownership_work"
  mv -fT -- "$ownership_work" "$ownership_final"
)

installer_target_ownership_forget() (
  set -eu
  ownership_digest=$(printf '%s' "$1" | sha256sum) || exit 1
  ownership_digest=${ownership_digest%% *}
  case "$ownership_digest" in ''|*[!a-f0-9]*) exit 1 ;; esac
  [ "${#ownership_digest}" -eq 64 ] || exit 1
  ownership_root=${DIR_INSTALLER_TARGET_OWNERSHIP:?installer ownership contract is unavailable}
  installer_lifecycle_parent_safe "$ownership_root" || exit 1
  rm -f -- "$ownership_root/$ownership_digest.tsv"
)

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
  installer_run_target_setup FILE_COMMON_PRIMARY_DEFAULTS 'publish rendered payload defaults for the primary account' \
    publish "${DIR_INSTALLER_TARGET_DEFAULTS}/$1" "$2" "$3"
}

installer_stage_account_creation() {
  # This is the only installed helper permitted to read private templates:
  # an administrator explicitly creates an account and selects its type.
  installer_apt_safe_path "${TARGET_ROOT}${DIR_USR_LOCAL_SBIN}" || installer_fatal 'unsafe account helper ancestry'
  install -d -m 0755 -- "${TARGET_ROOT}${DIR_USR_LOCAL_SBIN}"
  installer_stage_profile_file FILE_TARGET_SBIN_ACCOUNT_CREATE "$FILE_ACCOUNT_CREATE" 0755
  installer_stage_profile_file FILE_TARGET_SKEL_BASE_PROFILE \
    "${DIR_ETC_SKEL_BASE}/.profile" 0644
  installer_stage_profile_file FILE_TARGET_SKEL_BASE_BASH_PROFILE \
    "${DIR_ETC_SKEL_BASE}/.bash_profile" 0644
  installer_stage_profile_file FILE_TARGET_SKEL_BASE_BASHRC \
    "${DIR_ETC_SKEL_BASE}/.bashrc" 0644
  installer_stage_profile_file FILE_TARGET_SKEL_BASE_BASH_LOGOUT \
    "${DIR_ETC_SKEL_BASE}/.bash_logout" 0644
}

installer_stage_profile_asset() (
  set -eu
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
  installer_stage_profile_file "$setup_selector" "$setup_program" 0600
  if [ "$setup_selector" = FILE_SERVER_SETUP ]; then
    set -- --defaults-root "${DIR_INSTALLER_TARGET_DEFAULTS}/server" "$@"
  fi
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
