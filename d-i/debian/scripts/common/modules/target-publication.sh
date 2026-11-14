#!/bin/sh
# Role-independent target publication, using the one placeholder renderer.
# The target must be offline, root-owned and private from account processes.
installer_stage_profile_asset() (
  set -eu
  source_path=$1; target_path=$2; asset_mode=$3
  installer_repo_assert_asset_family "$source_path"
  case "$target_path" in /*) ;; *) installer_fatal 'target path must be absolute' ;; esac
  case "$asset_mode" in 0[0-7][0-7][0-7]) ;; *) installer_fatal 'invalid target asset mode' ;; esac
  installer_apt_safe_path "${TARGET_ROOT}${target_path}" || installer_fatal 'untrusted target asset ancestry'
  parent="${TARGET_ROOT}${target_path%/*}"
  if [ ! -d "$parent" ]; then install -d -m 0755 "$parent"; fi
  installer_apt_safe_path "$parent" || installer_fatal 'target ancestry changed before publication'
  input=$(mktemp "${DIR_INSTALLER_LATE_ENV}/profile-asset.XXXXXX")
  output=$(mktemp "$parent/.profile-asset.XXXXXX")
  trap 'rm -f "$input" "$output"' 0
  trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
  installer_fetch_file "$(installer_seed_base "")" "$source_path" "$input" 0600
  names=$(LC_ALL=C grep -oE '__INSTALLER_[A-Z][A-Z0-9_]*__' "$input" | sort -u || true)
  set --
  for token in $names; do
    name=${token#__INSTALLER_}; name=${name%__}
    case "$name" in PATH_*) continue ;; *[!A-Z0-9_]*|'') installer_fatal 'invalid placeholder name' ;; esac
    # Only a validated identifier enters indirection. Profile bytes are data.
    present=; value=
    eval "present=\${$name+x}; value=\${$name-}"
    [ "$present" = x ] || installer_fatal "profile asset lacks required field: $name"
    set -- "$@" "$name" "$value"
  done
  installer_apply_scalar_placeholders "$input" "$output" "$@"
  if LC_ALL=C grep -qE '__INSTALLER_[A-Z0-9_]+__' "$output"; then installer_fatal 'unresolved target asset placeholder'; fi
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
