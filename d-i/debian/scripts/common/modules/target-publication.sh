#!/bin/sh
# Role-independent target publication, using the one placeholder renderer.
# The target must be offline, root-owned and private from account processes.
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
  names=$(LC_ALL=C grep -oE '__INSTALLER_[A-Z][A-Z0-9]*(_[A-Z0-9]+)*__' "$input" | sort -u || true)
  set --
  for token in $names; do
    name=${token#__INSTALLER_}; name=${name%__}
    case "$name" in PATH_*) continue ;; *[!A-Z0-9_]*|'') installer_fatal 'invalid placeholder name' ;; esac
    # Only a validated identifier enters indirection. Profile bytes are data.
    present=; value=
    eval "present=\${$name+x}; value=\${$name-}"
    [ "$present" = x ] || installer_fatal "profile asset lacks required field: $name (asset=$source_path)"
    set -- "$@" "$name" "$value"
  done
  installer_apply_scalar_placeholders "$input" "$output" "$@"
  if LC_ALL=C grep -qE '__INSTALLER_[A-Z0-9_]+__' "$output"; then installer_fatal 'unresolved target asset placeholder'; fi
  installer_capture_primary_default "$output" "$target_path" "$asset_mode"
  installer_apt_safe_path "${TARGET_ROOT}${target_path}" || installer_fatal 'target identity changed before publication'
  chmod "$asset_mode" "$output"
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
