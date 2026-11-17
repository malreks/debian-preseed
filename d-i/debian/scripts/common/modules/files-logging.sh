#!/bin/sh
# Sourced installer module; edit this file directly.
unset INSTALLER_RUNTIME_PATH_SCHEMA

installer_mounts_find_record() {
  installer_mountpoint=$1
  installer_mounts_file=${2:-/proc/mounts}
  INSTALLER_MOUNT_SOURCE=
  INSTALLER_MOUNT_POINT=
  INSTALLER_MOUNT_FSTYPE=
  INSTALLER_MOUNT_OPTIONS=

  [ -r "$installer_mounts_file" ] || return 1
	  while IFS=' ' read -r mount_source mount_point mount_fstype mount_options _mount_rest || [ -n "${mount_source:-}" ]; do
	    [ "$mount_point" = "$installer_mountpoint" ] || continue
	    INSTALLER_MOUNT_SOURCE=$mount_source
	    INSTALLER_MOUNT_POINT=$mount_point
	    INSTALLER_MOUNT_FSTYPE=$mount_fstype
    INSTALLER_MOUNT_OPTIONS=$mount_options
    return 0
  done <"$installer_mounts_file"
  return 1
}

installer_mounts_has_mountpoint() {
  installer_mounts_find_record "$1" "${2:-/proc/mounts}" >/dev/null 2>&1
}

installer_mount_source_for_mountpoint() {
  installer_mounts_find_record "$1" "${2:-/proc/mounts}" || return 1
  printf '%s\n' "$INSTALLER_MOUNT_SOURCE"
}

installer_target_is_mounted() {
  [ -d ${TARGET_ROOT} ] || return 1
  installer_mounts_has_mountpoint ${TARGET_ROOT} /proc/mounts
}

installer_contains_unresolved_installer_placeholders() {
  installer_placeholder_path=$1

  [ -f "$installer_placeholder_path" ] && [ -r "$installer_placeholder_path" ] || return 2
  # Runtime helpers deliberately contain the bare prefix as a data guard.
  # Require a name character; still reject named markers with a missing suffix
  # or invalid lowercase names instead of accepting a partially rendered file.
  LC_ALL=C grep -Eq '__INSTALLER_[[:alnum:]_]' "$installer_placeholder_path"
}

installer_assert_no_unresolved_installer_placeholders() {
  installer_placeholder_path=$1
  installer_placeholder_label=${2:-$installer_placeholder_path}

  if installer_contains_unresolved_installer_placeholders "$installer_placeholder_path"; then
    :
  else
    installer_placeholder_status=$?
    [ "$installer_placeholder_status" -eq 1 ] && return 0
    installer_fatal "cannot inspect installer placeholders: ${installer_placeholder_label}"
    return 1
  fi

  installer_unresolved_tokens=$(
    LC_ALL=C grep -o '__INSTALLER_[A-Z0-9_]\+__' "$installer_placeholder_path" 2>/dev/null |
      sort -u |
      tr '\n' ' '
  )
  installer_unresolved_tokens=${installer_unresolved_tokens%" "}
  if [ -z "$installer_unresolved_tokens" ]; then
    installer_unresolved_tokens=$(
      LC_ALL=C grep -oE '__INSTALLER_[[:alnum:]_]+' "$installer_placeholder_path" 2>/dev/null |
        sort -u |
        tr '\n' ' '
    )
    installer_unresolved_tokens=${installer_unresolved_tokens%" "}
  fi
  [ -n "$installer_unresolved_tokens" ] || installer_unresolved_tokens="unknown placeholder(s)"
  installer_fatal "${installer_placeholder_label} has unresolved installer placeholders: ${installer_unresolved_tokens}"
}

installer_contains_unresolved_path_placeholders() {
  installer_placeholder_path=$1

  [ -f "$installer_placeholder_path" ] && [ -r "$installer_placeholder_path" ] || return 2
  # Include every canonical runtime-map namespace, including suite policy.
  LC_ALL=C grep -Eq '__INSTALLER_(PATH_[A-Z0-9_]+|APPARMOR_PROFILE_[A-Z0-9_]+|GITBUILD_DISTRIBUTION)__' \
    "$installer_placeholder_path"
}

installer_assert_no_unresolved_path_placeholders() {
  installer_placeholder_path=$1
  installer_placeholder_label=${2:-$installer_placeholder_path}

  if installer_contains_unresolved_path_placeholders "$installer_placeholder_path"; then
    installer_unresolved_tokens=$(
      LC_ALL=C grep -oE '__INSTALLER_(PATH_[A-Z0-9_]+|APPARMOR_PROFILE_[A-Z0-9_]+|GITBUILD_DISTRIBUTION)__' \
        "$installer_placeholder_path" 2>/dev/null |
        sort -u |
        tr '\n' ' '
    )
    installer_unresolved_tokens=${installer_unresolved_tokens%" "}
    [ -n "$installer_unresolved_tokens" ] || installer_unresolved_tokens="unknown path placeholder(s)"
    installer_fatal "${installer_placeholder_label} has unresolved installer path placeholders: ${installer_unresolved_tokens}"
    return 1
  else
    installer_placeholder_status=$?
    [ "$installer_placeholder_status" -eq 1 ] && return 0
    installer_fatal "cannot inspect installer path placeholders: ${installer_placeholder_label}"
    return 1
  fi
}

installer_replace_placeholder_in_file() (
  set -eu
  umask 077
  [ -n "${BOOTSTRAP_PREPARED_SOURCE_ROOT:-}" ] || {
    installer_fatal 'block publication requires base-stage rendering'; exit 1;
  }
  installer_literal_work=$(mktemp -d "${1}.literal.XXXXXX") || exit 1
  trap 'rm -rf -- "$installer_literal_work"' 0
  printf '%s' "$2" >"$installer_literal_work/map"
  printf '%s' "$3" >"$installer_literal_work/value"
  installer_target_perl_render "$1" "$1" "$installer_literal_work/map" \
    "${4:-literal}" "$installer_literal_work/value"
)

installer_validate_placeholder_map() {
  installer_placeholder_map=$1
  [ -f "$installer_placeholder_map" ] && [ ! -L "$installer_placeholder_map" ] || return 1
  # Map rows are data, not shell assignments.  Reject duplicate names before
  # any renderer consumes them, and validate the canonical path namespaces
  # before a value can enter a target file or executable.
  LC_ALL=C awk '
    # /dev/stderr is the immutable BusyBox/POSIX diagnostic interface; this
    # validator runs before the target path map is available.
    function invalid(message) { print "fatal: " message > "/dev/stderr"; status = 1 }
    {
      separator = index($0, "=")
      if (separator < 2) { invalid("malformed placeholder map row"); next }
      name = substr($0, 1, separator - 1)
      value = substr($0, separator + 1)
      if (name !~ /^[A-Z][A-Z0-9]*(_[A-Z0-9]+)*$/) invalid("invalid placeholder map key")
      if (name in seen) invalid("duplicate placeholder map key: " name)
      seen[name] = 1
      if (value ~ /[\r\n]/) invalid("multiline placeholder map value: " name)
      if (name ~ /^PATH_(DIR_|FILE_)/) {
        if (value !~ /^\// || value ~ /[^A-Za-z0-9_.\/@+ -]/ || value ~ /(^|\/)\.\.?($|\/)|\/\// || (value != "/" && value ~ /\/$/))
          invalid("non-normalized path placeholder value: " name)
      } else if (name ~ /^APPARMOR_PROFILE_/) {
        if (value !~ /^[A-Za-z0-9_.-]+$/) invalid("invalid AppArmor profile value: " name)
      } else if (name == "GITBUILD_DISTRIBUTION") {
        if (value !~ /^[a-z][a-z0-9.-]*$/) invalid("invalid distribution value")
      }
    }
    END { exit status }
  ' "$installer_placeholder_map"
}

# After base-stage, the same reviewed Perl program owns all scalar/block
# substitution. Shell callers only transport private inputs and publish output.
# No target interpreter is executed before the prepared receipt is adopted.
installer_target_perl_render() (
  set -eu
  umask 077
  render_input=$1; render_destination=$2; render_map=$3
  render_kind=${4:-scalar}; render_value=${5:-}
  [ -n "${BOOTSTRAP_PREPARED_SOURCE_ROOT:-}" ] || exit 125
  installer_target_context_init || exit 1
  for render_source in "$render_input" "$render_map"; do
    [ -f "$render_source" ] && [ ! -L "$render_source" ] &&
      [ "$(installer_metadata_value "$render_source" links)" = 1 ] || exit 1
  done
  render_stage=${BOOTSTRAP_PREPARED_SOURCE_ROOT%/source}
  installer_apt_safe_path "$render_stage/inputs" || exit 1
  render_work=$(mktemp -d "$render_stage/inputs/render.XXXXXX") || exit 1
  render_temporary=
  render_cleanup() {
    render_status=$?
    trap - 0
    [ -z "$render_temporary" ] || rm -f -- "$render_temporary"
    if [ "$render_status" -eq 0 ]; then
      rm -rf -- "$render_work" || render_status=1
    else
      installer_error "Perl render failed; private inputs retained: ${render_work#"$TARGET_ROOT"}" || :
    fi
    exit "$render_status"
  }
  trap render_cleanup 0
  trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
  install -m 0600 "$render_input" "$render_work/input" || exit 1
  install -m 0600 "$render_map" "$render_work/map" || exit 1
  case "$render_kind" in
    scalar|resources|modules|fstab|apparmor-modes) ;;
    literal|line|line-optional) install -m 0600 "$render_value" "$render_work/value" || exit 1 ;;
    theme|appearance) printf '%s' "$DIR_HOOKS_TARGET" >"$render_work/target" || exit 1 ;;
    *) exit 64 ;;
  esac
  if installer_run_bounded 60 chroot "$TARGET_ROOT" "${DIR_USR_BIN}/env" -i \
      HOME="$DIR_ROOT_HOME" PATH="${DIR_USR_BIN}:${DIR_BIN}" LC_ALL=C \
      "${DIR_USR_BIN}/perl" -f "${render_stage#"$TARGET_ROOT"}/render.pl" \
      --file "${render_work#"$TARGET_ROOT"}" "$render_kind" >"$render_work/log" 2>&1; then
    :
  else
    render_status=$?
    cat "$render_work/log" >&2
    exit "$render_status"
  fi
  render_parent=${render_destination%/*}
  [ "$render_parent" != "$render_destination" ] || render_parent=.
  [ -d "$render_parent" ] && [ ! -L "$render_parent" ] && [ ! -L "$render_destination" ] || exit 1
  render_temporary=$(mktemp "$render_parent/.perl-render.XXXXXX") || exit 1
  if [ -e "$render_destination" ]; then
    [ -f "$render_destination" ] &&
      [ "$(installer_metadata_value "$render_destination" links)" = 1 ] || exit 1
    cp -p -- "$render_destination" "$render_temporary" || exit 1
  fi
  cat "$render_work/output" >"$render_temporary" || exit 1
  [ ! -L "$render_parent" ] && [ ! -L "$render_destination" ] || exit 1
  mv -fT -- "$render_temporary" "$render_destination"
)

installer_runtime_path_placeholder_schema() {
  [ -z "${INSTALLER_RUNTIME_PATH_SCHEMA:-}" ] || return 0
  if [ -n "${BOOTSTRAP_PREPARED_SOURCE_ROOT:-}" ]; then
    installer_schema_path="$BOOTSTRAP_PREPARED_SOURCE_ROOT/$(installer_repo_file_value FILE_COMMON_RUNTIME_PATHS)" || return "$?"
  else
    installer_schema_path=$(installer_class_metadata_read_path FILE_COMMON_RUNTIME_PATHS) || return "$?"
  fi
  [ -f "$installer_schema_path" ] && [ ! -L "$installer_schema_path" ] || return 1
  INSTALLER_RUNTIME_PATH_SCHEMA=$(cat "$installer_schema_path") || return "$?"
}

installer_runtime_path_placeholder_map() {
  installer_runtime_path_placeholder_schema || return "$?"
  installer_map_tab=$(printf '\t')
  while IFS="$installer_map_tab" read -r installer_map_key installer_map_variable installer_map_extra; do
    case "$installer_map_key" in ''|'#'*) continue ;; esac
    case "$installer_map_variable" in
      DIR_*|FILE_*) [ "$installer_map_key" = "PATH_$installer_map_variable" ] || return 1 ;;
      APPARMOR_PROFILE_*|GITBUILD_DISTRIBUTION) [ "$installer_map_key" = "$installer_map_variable" ] || return 1 ;;
      *) installer_fatal 'invalid canonical runtime field'; return 1 ;;
    esac
    case "$installer_map_variable" in *[!A-Z0-9_]*) return 1 ;; esac
    [ -z "$installer_map_extra" ] || return 1
    installer_map_value=
    eval "installer_map_value=\${$installer_map_variable-}"
    [ -z "$installer_map_value" ] || printf '%s=%s\n' "$installer_map_key" "$installer_map_value"
  done <<EOF
$INSTALLER_RUNTIME_PATH_SCHEMA
EOF
  return 0
}

installer_runtime_path_placeholder_value() (
  installer_lookup_key=$1
  case "$installer_lookup_key" in ''|*[!A-Z0-9_]*) exit 1 ;; esac
  if [ -n "${BOOTSTRAP_PREPARED_PATH_VALUES:-}" ]; then
    installer_lookup_map=$BOOTSTRAP_PREPARED_PATH_VALUES
  else
    installer_lookup_map=$(installer_runtime_path_placeholder_map) || exit 1
  fi
  installer_lookup_count=0
  installer_lookup_value=
  while IFS= read -r installer_lookup_row; do
    [ "${installer_lookup_row%%=*}" = "$installer_lookup_key" ] || continue
    installer_lookup_count=$((installer_lookup_count + 1))
    installer_lookup_value=${installer_lookup_row#*=}
  done <<EOF
$installer_lookup_map
EOF
  [ "$installer_lookup_count" -eq 1 ] && [ -n "$installer_lookup_value" ] || exit 1
  printf '%s\n' "$installer_lookup_value"
)

installer_apply_scalar_placeholders() (
  set -eu
  umask 077
  installer_placeholder_src=$1
  installer_placeholder_final=$2
  [ -f "$installer_placeholder_src" ] && [ ! -L "$installer_placeholder_src" ] || return 1
  installer_placeholder_parent=${installer_placeholder_final%/*}
  [ "$installer_placeholder_parent" != "$installer_placeholder_final" ] || installer_placeholder_parent=.
  [ -d "$installer_placeholder_parent" ] && [ ! -L "$installer_placeholder_parent" ] || return 1
  installer_placeholder_work=$(mktemp -d "$installer_placeholder_parent/.installer-scalars.XXXXXX") || return 1
  trap 'rm -rf -- "$installer_placeholder_work"' 0
  trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
  installer_placeholder_dest=$installer_placeholder_work/payload
  if [ -e "$installer_placeholder_final" ] || [ -L "$installer_placeholder_final" ]; then
    [ -f "$installer_placeholder_final" ] && [ ! -L "$installer_placeholder_final" ] || return 1
    installer_placeholder_listing=$(LC_ALL=C ls -ln -- "$installer_placeholder_final") || return 1
    IFS=' ' read -r installer_placeholder_permissions installer_placeholder_links installer_placeholder_rest <<EOF
$installer_placeholder_listing
EOF
    [ "$installer_placeholder_links" = 1 ] || return 1
    # Preserve candidate metadata; publish only after a complete render.
    cp -p -- "$installer_placeholder_final" "$installer_placeholder_dest" || return 1
  fi
  installer_placeholder_script="$installer_placeholder_work/replacements.sed"
  installer_path_placeholder_map="${installer_placeholder_script}.paths"
  installer_scalar_placeholder_map="$installer_placeholder_work/scalars.map"
  : >"$installer_scalar_placeholder_map"
  shift 2

  [ $(( $# % 2 )) -eq 0 ] || installer_fatal "placeholder replacement arguments must be name/value pairs"
  # The pre-late batch has already resolved canonical paths. Most published
  # assets now need only a copy; template adapters supply their own few scalar
  # fields without rebuilding the complete runtime map for each file.
  installer_placeholder_needs_paths=false
  if installer_contains_unresolved_path_placeholders "$installer_placeholder_src"; then
    installer_placeholder_needs_paths=true
  else
    installer_placeholder_probe=$?
    [ "$installer_placeholder_probe" -eq 1 ] || return "$installer_placeholder_probe"
  fi
  if [ "$#" -eq 0 ] && [ "$installer_placeholder_needs_paths" = false ]; then
    cat "$installer_placeholder_src" >"$installer_placeholder_dest" || return 1
    mv -fT -- "$installer_placeholder_dest" "$installer_placeholder_final"
    return
  fi
  while [ "$#" -gt 1 ]; do
    installer_placeholder_name=$1
    installer_placeholder_value=$2
    shift 2
    case "$installer_placeholder_name" in
      ''|*[!A-Z0-9_]*) installer_fatal 'invalid scalar placeholder name' ;;
    esac
    case "$installer_placeholder_name" in
      [A-Z]*) ;; *) installer_fatal 'scalar placeholder name must start with a letter' ;;
    esac
    case "$installer_placeholder_value" in
      *"
"*|*"$(printf '\r')"*) installer_fatal 'scalar placeholder value must be a single line' ;;
    esac
    case "$installer_placeholder_value" in
      # Keep prefix probes incomplete so the early batch cannot render the
      # renderer's own token detector into a suite-specific string.
      *__INSTALLER_PATH_*|*__INSTALLER_APPARMOR_PROFILE_*|*__INSTALLER_GITBUILD_DISTRIBUTION_*) installer_placeholder_needs_paths=true ;;
    esac
    printf '%s=%s\n' "$installer_placeholder_name" "$installer_placeholder_value" \
      >>"$installer_scalar_placeholder_map" || return 1
  done
  if [ "$installer_placeholder_needs_paths" = false ]; then
    : >"$installer_path_placeholder_map"
  elif [ -n "${BOOTSTRAP_PREPARED_SOURCE_ROOT:-}" ]; then
    cp "${BOOTSTRAP_PREPARED_SOURCE_ROOT%/source}/inputs/paths.map" "$installer_path_placeholder_map" || return "$?"
  elif ! installer_runtime_path_placeholder_map >"$installer_path_placeholder_map"; then
    rm -f "$installer_placeholder_script" "$installer_path_placeholder_map"
    return 1
  fi
  cat "$installer_path_placeholder_map" >>"$installer_scalar_placeholder_map" || return 1
  if [ -n "${BOOTSTRAP_PREPARED_SOURCE_ROOT:-}" ]; then
    installer_target_perl_render "$installer_placeholder_src" "$installer_placeholder_dest" \
      "$installer_scalar_placeholder_map" || return "$?"
    mv -fT -- "$installer_placeholder_dest" "$installer_placeholder_final"
    return
  fi
  installer_validate_placeholder_map "$installer_scalar_placeholder_map" || return 1
  : >"$installer_placeholder_script" || return 1
  # The canonical path map is single-line NAME=value data. Escape all of it
  # in one process, rather than launching sed for every path on every asset.
  # Keep the same sed renderer and scalar/block replacement semantics.
  if ! LC_ALL=C awk '
    function replacement(value, output, position, character) {
      output = ""
      for (position = 1; position <= length(value); position++) {
        character = substr(value, position, 1)
        if (character == "\\" || character == "&" || character == "|") output = output "\\"
        output = output character
      }
      return output
    }
    NF {
      separator = index($0, "=")
      name = substr($0, 1, separator - 1)
      if (separator < 2 || name !~ /^[A-Z][A-Z0-9_]*$/) exit 1
      if (name in seen) exit 1
      seen[name] = 1
      print "s|__INSTALLER_" name "__|" replacement(substr($0, separator + 1)) "|g"
    }
  ' "$installer_scalar_placeholder_map" >>"$installer_placeholder_script"; then
    rm -f "$installer_placeholder_script" "$installer_path_placeholder_map"
    return 1
  fi
  rm -f "$installer_path_placeholder_map"
  sed -f "$installer_placeholder_script" "$installer_placeholder_src" >"$installer_placeholder_dest" || {
    rm -f "$installer_placeholder_script" "$installer_placeholder_dest" "$installer_path_placeholder_map"
    return 1
  }
  rm -f "$installer_placeholder_script"
  [ ! -L "$installer_placeholder_parent" ] && [ ! -L "$installer_placeholder_final" ] || return 1
  mv -fT -- "$installer_placeholder_dest" "$installer_placeholder_final"
)

installer_copy_path_with_mode() (
  umask 077
  copy_src_path=$1
  copy_dest_path=$2
  copy_mode=$3
  copy_label=${4:-file}
  case "$copy_mode" in
    [0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) ;;
    *) installer_error "invalid copy mode for ${copy_label}"; exit 1 ;;
  esac

  if [ "$copy_src_path" = "$copy_dest_path" ]; then
    [ -f "$copy_dest_path" ] && [ ! -L "$copy_dest_path" ] || exit 1
    chmod "$copy_mode" "$copy_dest_path"
    exit $?
  fi

  copy_parent_dir=$(dirname "$copy_dest_path") || exit 1
  [ -d "$copy_parent_dir" ] || install -d -m 0700 "$copy_parent_dir" || exit 1
  [ ! -d "$copy_dest_path" ] || {
    installer_error "copy destination is a directory: ${copy_dest_path}"
    exit 1
  }
  copy_work=$(mktemp -d "$copy_parent_dir/.installer-copy.XXXXXX") || exit 1
  trap 'rm -rf -- "$copy_work"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  copy_tmp_path="$copy_work/payload"
  copy_err_path="$copy_work/copy.err"
  if cp -- "$copy_src_path" "$copy_tmp_path" >"$copy_err_path" 2>&1; then
    copy_status=0
  else
    copy_status=$?
  fi
  if [ "$copy_status" -ne 0 ]; then
    installer_error "failed to copy ${copy_label} from ${copy_src_path} to ${copy_dest_path} (status ${copy_status})"
    [ ! -s "$copy_err_path" ] || sed -n '1,40s/^/[cp] /p' "$copy_err_path" >&2
    exit 1
  fi
  [ -s "$copy_tmp_path" ] || {
    installer_fatal "copied ${copy_label} is empty: ${copy_src_path}"
    exit 1
  }
  chmod "$copy_mode" "$copy_tmp_path" || exit 1
  mv -fT -- "$copy_tmp_path" "$copy_dest_path" || exit 1
)

installer_log_path_is_numbered() {
  installer_check_log_path=$1
  installer_check_log_name=${installer_check_log_path##*/}

  case "$installer_check_log_name" in
    [0-9]*-*) return 0 ;;
  esac
  return 1
}

installer_log_sequence_file() {
  installer_sequence_log_dir=$1
  printf '%s/.log-sequence\n' "$installer_sequence_log_dir"
}

installer_next_log_sequence() {
  installer_sequence_log_dir=$1
  installer_sequence_path=$(installer_log_sequence_file "$installer_sequence_log_dir")
  installer_sequence_tmp="${installer_sequence_path}.tmp.$$"
  installer_current_sequence=0

  [ -d "$installer_sequence_log_dir" ] || install -d -m 0700 "$installer_sequence_log_dir"
  if [ -r "$installer_sequence_path" ]; then
    installer_current_sequence=$(cat "$installer_sequence_path" 2>/dev/null || printf '0\n')
  fi
  case "$installer_current_sequence" in
    ''|*[!0-9]*) installer_current_sequence=0 ;;
  esac

  installer_next_sequence=$((installer_current_sequence + 1))
  printf '%s\n' "$installer_next_sequence" >"$installer_sequence_tmp"
  mv "$installer_sequence_tmp" "$installer_sequence_path"
  chmod 0600 "$installer_sequence_path" 2>/dev/null || true
  printf '%s\n' "$installer_next_sequence"
}

installer_log_dir_for_path() {
  installer_dir_path=$1
  printf '%s\n' "$(dirname "$installer_dir_path")"
}

installer_basename_for_path() {
  installer_base_path=$1
  printf '%s\n' "${installer_base_path##*/}"
}

installer_runtime_log_path_requested() {
  requested_log_path=$1
  runtime_log_dir=$(installer_runtime_log_dir)

  case "$requested_log_path" in
    "${runtime_log_dir}/"*) return 0 ;;
  esac
  return 1
}

installer_resolve_runtime_log_path() {
  requested_log_path=$1
  printf '%s\n' "$requested_log_path"
}

installer_runtime_temp_log_path() {
  temp_log_name=$1
  temp_log_dir=$(installer_runtime_temp_log_dir)
  temp_log_name=${temp_log_name%.log}
  install -d -m 0700 "$temp_log_dir" 2>/dev/null || true
  printf '%s/%s-%s.err\n' "$temp_log_dir" "$$" "$temp_log_name"
}

installer_resolve_target_log_path() {
  requested_target_log_path=$1
  INSTALLER_RESOLVED_TARGET_LOG_PATH=

  [ -n "$requested_target_log_path" ] || return 1
  if installer_log_path_is_numbered "$requested_target_log_path"; then
    INSTALLER_RESOLVED_TARGET_LOG_PATH=$requested_target_log_path
    return 0
  fi

  if [ -n "${INSTALLER_LOG_TARGET_FILE_RESOLVED:-}" ] && \
     [ "${INSTALLER_LOG_TARGET_FILE:-}" = "$requested_target_log_path" ]
  then
    INSTALLER_RESOLVED_TARGET_LOG_PATH=$INSTALLER_LOG_TARGET_FILE_RESOLVED
    return 0
  fi

  target_log_dir=$(installer_log_dir_for_path "$requested_target_log_path")
  target_log_name=$(installer_basename_for_path "$requested_target_log_path")
  target_log_seq=$(installer_next_log_sequence "$target_log_dir")
  resolved_target_log_path="${target_log_dir}/${target_log_seq}-${target_log_name}"

  if [ "${INSTALLER_LOG_TARGET_FILE:-}" = "$requested_target_log_path" ]; then
    INSTALLER_LOG_TARGET_FILE_RESOLVED=$resolved_target_log_path
  fi

  INSTALLER_RESOLVED_TARGET_LOG_PATH=$resolved_target_log_path
  return 0
}

installer_copy_log_to_target() {
  log_path=$1
  target_log_file=$2

  installer_logging_enabled || return 0
  [ -s "$log_path" ] || return 0
  [ -n "$target_log_file" ] || return 0
  installer_target_is_mounted || return 0

  if installer_log_path_is_numbered "$log_path" && \
     ! installer_log_path_is_numbered "$target_log_file"
  then
    resolved_target_log_file="$(installer_log_dir_for_path "$target_log_file")/$(installer_basename_for_path "$log_path")"
  else
    installer_resolve_target_log_path "$target_log_file" || return 0
    resolved_target_log_file=$INSTALLER_RESOLVED_TARGET_LOG_PATH
  fi
  install -d -m 0700 "$(dirname "$resolved_target_log_file")"
  resolved_target_log_tmp="${resolved_target_log_file}.tmp.$$"
  if installer_redact_log_stream <"$log_path" >"$resolved_target_log_tmp" 2>/dev/null; then
    chmod 0600 "$resolved_target_log_tmp" 2>/dev/null || true
    mv -f "$resolved_target_log_tmp" "$resolved_target_log_file"
  else
    rm -f "$resolved_target_log_tmp" 2>/dev/null || true
    installer_warn "failed to sanitize installer log ${log_path}"
  fi
}

installer_persist_log_file() {
  log_path=$1
  target_log_file=$2

  # Runtime logs are archived once at the end of the installer flow.  Keep this
  # compatibility entrypoint as a no-op so phase hooks do not create partial
  # target-side log copies before finish-install runs.
  [ -n "$log_path" ] || return 0
  [ -n "$target_log_file" ] || return 0
  return 0
}

installer_init_log_file() {
  log_path=$1
  target_log_file=${2:-}
  log_context=${3:-${0##*/}}
  log_tag=${4:-}
  log_stage=${5:-}
  log_path=$(installer_resolve_runtime_log_path "$log_path")

  if command -v installer_operation_context_repo >/dev/null 2>&1 &&
     [ -z "${INSTALLER_FAILURE_SOURCE:-}" ]; then
    installer_operation_context_repo FILE_COMMON_MOD_FILES_LOGGING 936 "$log_context"
  fi

  installer_export_logging_policy
  if ! installer_logging_enabled; then
    INSTALLER_LOG_PATH=
    INSTALLER_LOG_TARGET_FILE=
    INSTALLER_LOG_TARGET_FILE_RESOLVED=
    INSTALLER_LOG_CONTEXT=$log_context
    INSTALLER_LOG_FINALIZED=0
    INSTALLER_LOG_START_EPOCH=$(installer_log_epoch)
    [ -n "$log_tag" ] && INSTALLER_LOG_TAG=$log_tag
    if [ -n "$log_stage" ]; then
      INSTALLER_LOG_STAGE=$log_stage
    else
      INSTALLER_LOG_STAGE=$(installer_stage_from_tag "$(installer_log_tag)")
    fi
    return 0
  fi

  log_dir=$(dirname "$log_path")

  [ -d "$log_dir" ] || install -d -m 0700 "$log_dir" 2>/dev/null || true
  : >>"$log_path" || installer_fatal "unable to initialize log file: ${log_path}"
  chmod 0600 "$log_path" 2>/dev/null || true

  # shellcheck disable=SC2034 # Exposed for phase hooks sourced after logging setup.
  INSTALLER_LOG_PATH=$log_path
  INSTALLER_LOG_TARGET_FILE=$target_log_file
  INSTALLER_LOG_TARGET_FILE_RESOLVED=
  INSTALLER_LOG_CONTEXT=$log_context
  INSTALLER_LOG_FINALIZED=0
  INSTALLER_LOG_START_EPOCH=$(installer_log_epoch)
  if [ -n "$log_tag" ]; then
    INSTALLER_LOG_TAG=$log_tag
  fi
  if [ -n "$log_stage" ]; then
    INSTALLER_LOG_STAGE=$log_stage
  else
    INSTALLER_LOG_STAGE=$(installer_stage_from_tag "$(installer_log_tag)")
  fi

  exec >>"$log_path" 2>&1
  installer_info "starting ${INSTALLER_LOG_CONTEXT}"
  return 0
}

installer_init_stderr_log_file() {
  log_path=$1
  target_log_file=${2:-}
  log_context=${3:-${0##*/}}
  log_tag=${4:-}
  log_stage=${5:-}
  log_path=$(installer_resolve_runtime_log_path "$log_path")

  if command -v installer_operation_context_repo >/dev/null 2>&1 &&
     [ -z "${INSTALLER_FAILURE_SOURCE:-}" ]; then
    installer_operation_context_repo FILE_COMMON_MOD_FILES_LOGGING 993 "$log_context"
  fi

  installer_export_logging_policy
  if ! installer_logging_enabled; then
    INSTALLER_LOG_PATH=
    INSTALLER_LOG_TARGET_FILE=
    INSTALLER_LOG_TARGET_FILE_RESOLVED=
    INSTALLER_LOG_CONTEXT=$log_context
    INSTALLER_LOG_FINALIZED=0
    INSTALLER_LOG_START_EPOCH=$(installer_log_epoch)
    [ -n "$log_tag" ] && INSTALLER_LOG_TAG=$log_tag
    if [ -n "$log_stage" ]; then
      INSTALLER_LOG_STAGE=$log_stage
    else
      INSTALLER_LOG_STAGE=$(installer_stage_from_tag "$(installer_log_tag)")
    fi
    return 0
  fi

  log_dir=$(dirname "$log_path")

  [ -d "$log_dir" ] || install -d -m 0700 "$log_dir" 2>/dev/null || true
  : >>"$log_path" || installer_fatal "unable to initialize log file: ${log_path}"
  chmod 0600 "$log_path" 2>/dev/null || true

  # shellcheck disable=SC2034 # Exposed for phase hooks sourced after logging setup.
  INSTALLER_LOG_PATH=$log_path
  INSTALLER_LOG_TARGET_FILE=$target_log_file
  INSTALLER_LOG_TARGET_FILE_RESOLVED=
  INSTALLER_LOG_CONTEXT=$log_context
  INSTALLER_LOG_FINALIZED=0
  INSTALLER_LOG_START_EPOCH=$(installer_log_epoch)
  if [ -n "$log_tag" ]; then
    INSTALLER_LOG_TAG=$log_tag
  fi
  if [ -n "$log_stage" ]; then
    INSTALLER_LOG_STAGE=$log_stage
  else
    INSTALLER_LOG_STAGE=$(installer_stage_from_tag "$(installer_log_tag)")
  fi

  exec 2>>"$log_path"
  installer_info "starting ${INSTALLER_LOG_CONTEXT}"
  return 0
}

installer_finalize_log() {
  exit_code=${1:-0}

  if [ "${INSTALLER_LOG_FINALIZED:-0}" -eq 1 ]; then
    return 0
  fi
  INSTALLER_LOG_FINALIZED=1

  log_context=${INSTALLER_LOG_CONTEXT:-${0##*/}}
  log_duration=
  if [ -n "${INSTALLER_LOG_START_EPOCH:-}" ]; then
    log_end_epoch=$(installer_log_epoch)
    case "$log_end_epoch:${INSTALLER_LOG_START_EPOCH:-}" in
      [0-9]*:[0-9]*)
        log_duration=" duration_seconds=$((log_end_epoch - INSTALLER_LOG_START_EPOCH))"
        ;;
    esac
  fi
  if [ "$exit_code" -eq 0 ]; then
    installer_info "completed ${log_context}${log_duration}"
  else
    log_failure_context=unknown
    if command -v installer_failure_context >/dev/null 2>&1; then
      log_failure_context=$(installer_failure_context 2>/dev/null || printf '%s' unknown)
    fi
    installer_error "${log_context} exited with status ${exit_code}${log_duration}; ${log_failure_context}; inspect the preceding diagnostic for the failed operation"
    if [ "${INSTALLER_LIFECYCLE_ACTIVE:-0}" = 1 ]; then
      installer_record_failure "$exit_code" "$log_context" "operation failed: status=${exit_code}; ${log_failure_context}; see the preceding diagnostic for command output" || :
    fi
  fi

  if installer_bool_is_true "${INSTALLER_ARCHIVE_LOGS_ON_FINALIZE:-false}"; then
    installer_archive_logs_to_target || true
  fi
}

installer_fatal_status() {
  fatal_status=${1:-1}
  shift || :
  case "$fatal_status" in
    ''|*[!0-9]*|0) fatal_status=1 ;;
  esac
  fatal_context=unknown
  if command -v installer_failure_context >/dev/null 2>&1; then
    fatal_context=$(installer_failure_context 2>/dev/null || printf '%s' unknown)
  fi
  installer_error "$* (status=${fatal_status}; ${fatal_context})"
  if [ "${INSTALLER_LIFECYCLE_ACTIVE:-0}" = 1 ]; then
    installer_record_failure "$fatal_status" "${INSTALLER_LOG_CONTEXT:-unknown}" "$* (status=${fatal_status}; ${fatal_context})" || :
  fi
  exit "$fatal_status"
}

installer_fatal() {
  installer_fatal_status 1 "$@"
}

installer_shell_quote() {
  printf "'%s'" "$(printf '%s' "${1-}" | sed "s/'/'\\\\''/g")"
}

# Quote the VALUE inside a double-quoted Environment="KEY=value" unit entry.
# Reject controls; escape unit syntax and literal percent specifiers. Never eval.
installer_systemd_environment_value() (
  [ "$#" -eq 1 ] || exit 64
  LC_ALL=C; export LC_ALL
  # case sees embedded/trailing newlines, unlike a line-oriented grep. These
  # bootstrap values are bounded ASCII identifiers, paths and command flags.
  case "$1" in *[![:print:]]*)
    printf '%s\n' 'fatal: non-printable systemd environment value' >&2; exit 1 ;;
  esac
  [ "${#1}" -le 4096 ] || exit 1
  printf '%s' "$1" | sed 's/[\\"]/\\&/g; s/%/%%/g'
)

# Validate and escape before substitution, propagating failures instead of
# hiding them inside nested command-substitution arguments to a renderer.
installer_apply_systemd_environment_placeholders() (
  set -eu
  environment_input=$1
  environment_output=$2
  shift 2
  remaining=$#
  [ $((remaining % 2)) -eq 0 ] || exit 64
  while [ "$remaining" -gt 0 ]; do
    environment_name=$1
    environment_value=$(installer_systemd_environment_value "$2") || exit 1
    shift 2
    set -- "$@" "$environment_name" "$environment_value"
    remaining=$((remaining - 2))
  done
  installer_apply_scalar_placeholders "$environment_input" "$environment_output" "$@"
)

# A unit identity is data; only registered unit paths can reach staging.
installer_systemd_dropin_dir() {
  [ "$#" -eq 2 ] || return 64
  case "$1/$2" in
    system/apparmor-modes.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_APPARMOR_MODES_DROPIN" ;;
    system/NetworkManager-dispatcher.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NETWORKMANAGER_DISPATCHER_DROPIN" ;;
    system/NetworkManager.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NETWORKMANAGER_DROPIN" ;;
    system/apparmor.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_APPARMOR_DROPIN" ;;
    system/apt-daily-upgrade.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_APT_DAILY_UPGRADE_DROPIN" ;;
    system/apt-daily.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_APT_DAILY_DROPIN" ;;
    system/apt-repo-local-.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_APT_REPO_LOCAL_FAMILY_DROPIN" ;;
    system/apt-repo-local-refresh.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_APT_REPO_LOCAL_REFRESH_DROPIN" ;;
    system/audit-rules.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_AUDIT_RULES_DROPIN" ;;
    system/auditd.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_AUDITD_DROPIN" ;;
    system/bluetooth.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_BLUETOOTH_DROPIN" ;;
    system/clamav-daemon.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_CLAMAV_DAEMON_DROPIN" ;;
    system/clamav-freshclam.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_CLAMAV_FRESHCLAM_DROPIN" ;;
    system/clamav-signature-update.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_CLAMAV_SIGNATURE_UPDATE_DROPIN" ;;
    system/crowdsec-firewall-bouncer.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_CROWDSEC_FIREWALL_BOUNCER_DROPIN" ;;
    system/crowdsec.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_CROWDSEC_DROPIN" ;;
    system/data-run.mount) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_DATA_RUN_MOUNT_DROPIN" ;;
    system/dbus-broker.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_DBUS_BROKER_DROPIN" ;;
    system/dev-shm.mount) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_DEV_SHM_MOUNT_DROPIN" ;;
    system/fail2ban.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_FAIL2BAN_DROPIN" ;;
    system/fstrim.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_FSTRIM_DROPIN" ;;
    system/fstrim.timer) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_FSTRIM_TIMER_DROPIN" ;;
    system/fwupd.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_FWUPD_DROPIN" ;;
    system/greetd.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_GREETD_DROPIN" ;;
    system/home-mcramer-Sharing.mount) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_HOME_MCRAMER_SHARING_MOUNT_DROPIN" ;;
    system/ifup@.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_IFUP_TEMPLATE_DROPIN" ;;
    system/incus-user.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_INCUS_USER_DROPIN" ;;
    system/logrotate.timer) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_LOGROTATE_TIMER_DROPIN" ;;
    system/lynis.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_LYNIS_DROPIN" ;;
    system/mullvad-daemon.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_MULLVAD_DAEMON_DROPIN" ;;
    system/networking.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NETWORKING_DROPIN" ;;
    system/nfs-idmapd.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NFS_IDMAPD_DROPIN" ;;
    system/nfs-mountd.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NFS_MOUNTD_DROPIN" ;;
    system/nfs-server.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NFS_SERVER_DROPIN" ;;
    system/nftables.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NFTABLES_DROPIN" ;;
    system/technitium.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_TECHNITIUM_DROPIN" ;;
    system/nvidia-hibernate.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NVIDIA_HIBERNATE_DROPIN" ;;
    system/nvidia-powerd.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NVIDIA_POWERD_DROPIN" ;;
    system/nvidia-resume.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NVIDIA_RESUME_DROPIN" ;;
    system/nvidia-suspend-then-hibernate.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NVIDIA_SUSPEND_THEN_HIBERNATE_DROPIN" ;;
    system/nvidia-suspend.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NVIDIA_SUSPEND_DROPIN" ;;
    system/power-profiles-daemon.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_POWER_PROFILES_DAEMON_DROPIN" ;;
    system/rsyslog.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_RSYSLOG_DROPIN" ;;
    system/scx.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SCX_DROPIN" ;;
    system/scx_loader.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SCX_LOADER_DROPIN" ;;
    system/sleep.target) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SLEEP_TARGET_DROPIN" ;;
    system/ssh.socket) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SSH_SOCKET_DROPIN" ;;
    system/stubby.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_STUBBY_DROPIN" ;;
    system/syncthing.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SYNCTHING_DROPIN" ;;
    system/system-background.slice) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEM_BACKGROUND_SLICE_DROPIN" ;;
    system/system-maintenance.slice) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEM_MAINTENANCE_SLICE_DROPIN" ;;
    system/systemd-coredump.socket) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEMD_COREDUMP_SOCKET_DROPIN" ;;
    system/systemd-creds.socket) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEMD_CREDS_SOCKET_DROPIN" ;;
    system/systemd-hibernate.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEMD_HIBERNATE_DROPIN" ;;
    system/systemd-hybrid-sleep.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEMD_HYBRID_SLEEP_DROPIN" ;;
    system/systemd-resolved.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEMD_RESOLVED_DROPIN" ;;
    system/systemd-suspend-then-hibernate.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEMD_SUSPEND_THEN_HIBERNATE_DROPIN" ;;
    system/systemd-suspend.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEMD_SUSPEND_DROPIN" ;;
    system/tailscaled.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_TAILSCALED_DROPIN" ;;
    system/test.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_TEST_DROPIN" ;;
    system/timeshift-.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_TIMESHIFT_FAMILY_DROPIN" ;;
    system/tmp.mount) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_TMP_MOUNT_DROPIN" ;;
    system/unattended-upgrades.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_UNATTENDED_UPGRADES_DROPIN" ;;
    system/user-1000.slice) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_USER_1000_SLICE_DROPIN" ;;
    system/user@.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_USER_MANAGER_DROPIN" ;;
    system/var-cache.mount) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_VAR_CACHE_MOUNT_DROPIN" ;;
    system/var-lib-apt-lists.mount) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_VAR_LIB_APT_LISTS_MOUNT_DROPIN" ;;
    system/var-lib-systemd-coredump.mount) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_VAR_LIB_SYSTEMD_COREDUMP_MOUNT_DROPIN" ;;
    system/var-log.mount) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_VAR_LOG_MOUNT_DROPIN" ;;
    system/var-spool-rsyslog.mount) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_VAR_SPOOL_RSYSLOG_MOUNT_DROPIN" ;;
    system/wpa_supplicant.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_WPA_SUPPLICANT_DROPIN" ;;
    system/x-clamav-signature-update.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_X_CLAMAV_SIGNATURE_UPDATE_DROPIN" ;;
    system/x-syncthing.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_X_SYNCTHING_DROPIN" ;;
    system/xfs_healer_start.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_XFS_HEALER_START_DROPIN" ;;
    system/zram-writeback.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_ZRAM_DROPIN" ;;
    user/app-.scope) printf '%s\n' "$DIR_SYSTEMD_USER_APP_FAMILY_SCOPE_DROPIN" ;;
    user/app.slice) printf '%s\n' "$DIR_SYSTEMD_USER_APP_SLICE_DROPIN" ;;
    system/user-.slice) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_USER_FAMILY_SLICE_DROPIN" ;;
    system/user.slice) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_USER_SLICE_DROPIN" ;;
    user/background.slice) printf '%s\n' "$DIR_SYSTEMD_USER_BACKGROUND_SLICE_DROPIN" ;;
    user/crystal-dock.service) printf '%s\n' "$DIR_SYSTEMD_USER_CRYSTAL_DOCK_DROPIN" ;;
    user/dbus-broker.service) printf '%s\n' "$DIR_SYSTEMD_USER_DBUS_BROKER_DROPIN" ;;
    user/filter-chain.service) printf '%s\n' "$DIR_SYSTEMD_USER_FILTER_CHAIN_DROPIN" ;;
    user/foot-server.service) printf '%s\n' "$DIR_SYSTEMD_USER_FOOT_SERVER_DROPIN" ;;
    user/foot-server.socket) printf '%s\n' "$DIR_SYSTEMD_USER_FOOT_SERVER_SOCKET_DROPIN" ;;
    user/gvfs-daemon.service) printf '%s\n' "$DIR_SYSTEMD_USER_GVFS_DAEMON_DROPIN" ;;
    user/gvfs-udisks2-volume-monitor.service) printf '%s\n' "$DIR_SYSTEMD_USER_GVFS_UDISKS2_VOLUME_MONITOR_DROPIN" ;;
    user/hyprpolkitagent.service) printf '%s\n' "$DIR_SYSTEMD_USER_HYPRPOLKITAGENT_DROPIN" ;;
    user/kanshi.service) printf '%s\n' "$DIR_SYSTEMD_USER_KANSHI_DROPIN" ;;
    user/labwc-bitwarden-.service) printf '%s\n' "$DIR_SYSTEMD_USER_LABWC_BITWARDEN_FAMILY_DROPIN" ;;
    user/labwc-compat-.service) printf '%s\n' "$DIR_SYSTEMD_USER_LABWC_COMPAT_FAMILY_DROPIN" ;;
    user/labwc-devops-.service) printf '%s\n' "$DIR_SYSTEMD_USER_LABWC_DEVOPS_FAMILY_DROPIN" ;;
    user/labwc-electron-.service) printf '%s\n' "$DIR_SYSTEMD_USER_LABWC_ELECTRON_FAMILY_DROPIN" ;;
    user/labwc-native-.service) printf '%s\n' "$DIR_SYSTEMD_USER_LABWC_NATIVE_FAMILY_DROPIN" ;;
    user/labwc-qbittorrent-.service) printf '%s\n' "$DIR_SYSTEMD_USER_LABWC_QBITTORRENT_FAMILY_DROPIN" ;;
    user/labwc-session-state@prepare.service) printf '%s\n' "$DIR_SYSTEMD_USER_LABWC_SESSION_STATE_PREPARE_DROPIN" ;;
    user/labwc-wayland-.service) printf '%s\n' "$DIR_SYSTEMD_USER_LABWC_WAYLAND_FAMILY_DROPIN" ;;
    user/labwc-wayland-foot-.service) printf '%s\n' "$DIR_SYSTEMD_USER_LABWC_WAYLAND_FOOT_FAMILY_DROPIN" ;;
    user/llama-server.service) printf '%s\n' "$DIR_SYSTEMD_USER_LLAMA_SERVER_DROPIN" ;;
    user/mako.service) printf '%s\n' "$DIR_SYSTEMD_USER_MAKO_DROPIN" ;;
    user/pipewire-pulse.service) printf '%s\n' "$DIR_SYSTEMD_USER_PIPEWIRE_PULSE_DROPIN" ;;
    user/pipewire-pulse.socket) printf '%s\n' "$DIR_SYSTEMD_USER_PIPEWIRE_PULSE_SOCKET_DROPIN" ;;
    user/pipewire.service) printf '%s\n' "$DIR_SYSTEMD_USER_PIPEWIRE_DROPIN" ;;
    user/pipewire.socket) printf '%s\n' "$DIR_SYSTEMD_USER_PIPEWIRE_SOCKET_DROPIN" ;;
    user/session.slice) printf '%s\n' "$DIR_SYSTEMD_USER_SESSION_SLICE_DROPIN" ;;
    user/ssh-agent.service) printf '%s\n' "$DIR_SYSTEMD_USER_SSH_AGENT_DROPIN" ;;
    user/ssh-agent.socket) printf '%s\n' "$DIR_SYSTEMD_USER_SSH_AGENT_SOCKET_DROPIN" ;;
    user/thunar.service) printf '%s\n' "$DIR_SYSTEMD_USER_THUNAR_DROPIN" ;;
    user/waybar.service) printf '%s\n' "$DIR_SYSTEMD_USER_WAYBAR_DROPIN" ;;
    user/wayscriber.service) printf '%s\n' "$DIR_SYSTEMD_USER_WAYSCRIBER_DROPIN" ;;
    user/wireplumber.service) printf '%s\n' "$DIR_SYSTEMD_USER_WIREPLUMBER_DROPIN" ;;
    user/xdg-desktop-portal-.service) printf '%s\n' "$DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_FAMILY_DROPIN" ;;
    user/xdg-desktop-portal-gtk.service) printf '%s\n' "$DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_GTK_DROPIN" ;;
    user/xdg-desktop-portal-lxqt.service) printf '%s\n' "$DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_LXQT_DROPIN" ;;
    user/xdg-desktop-portal-wlr.service) printf '%s\n' "$DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_WLR_DROPIN" ;;
    user/xdg-desktop-portal-xapp.service) printf '%s\n' "$DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_XAPP_DROPIN" ;;
    user/xdg-desktop-portal.service) printf '%s\n' "$DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_DROPIN" ;;
    *) installer_fatal "unregistered systemd drop-in unit"; return 1 ;;
  esac
}
