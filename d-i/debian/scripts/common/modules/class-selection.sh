#!/bin/sh
# Sourced installer module; edit this file directly.

installer_auto_class_tokens() {
  seed_base=$1
  auto_script="${RUNTIME_DIR:-$(installer_runtime_dir)}/bootstrap/class-auto.sh"
  auto_classes="$(installer_runtime_temp_log_path class-auto.classes)"
  auto_err="$(installer_runtime_temp_log_path class-auto.err)"
  auto_report="$(installer_runtime_temp_log_path class-auto.report)"
  auto_tokens_found=false

  install -d -m 0700 "$(dirname "$auto_script")" || return "$?"
  installer_ensure_log_files || return "$?"
  installer_fetch_file "$seed_base" "$(installer_repo_file_value FILE_PRESEED_CLASS_AUTO)" "$auto_script" 0755 || return "$?"
  if command -v installer_operation_context >/dev/null 2>&1; then
    installer_operation_context_repo FILE_COMMON_MOD_CLASS_SELECTION 16 automatic_class_detection
  fi
  if "$auto_script" classes >"$auto_classes" 2>"$auto_err"; then
    :
  else
    auto_status=$?
    installer_error "automatic class detection failed with status ${auto_status}"
    if [ "${INSTALLER_LIFECYCLE_ACTIVE:-0}" = 1 ]; then
      installer_record_failure "$auto_status" class-auto "automatic class detection failed; see installer.log" || :
    fi
    if [ -s "$auto_err" ]; then
      installer_redact_log_stream <"$auto_err" | while IFS= read -r auto_error_line || [ -n "$auto_error_line" ]; do
        [ -n "$auto_error_line" ] || continue
        installer_error "class-auto: $auto_error_line"
      done
    fi
    [ -s "$auto_err" ] && sed 's/^/[class-auto] /' "$auto_err" >&2
    rm -f "$auto_err" "$auto_report" "$auto_classes"
    exit "$auto_status"
  fi

  if "$auto_script" report >"$auto_report" 2>>"$auto_err"; then
    :
  else
    {
      printf '\n=== d-i hardware detection ===\n\n'
      printf '[AUTO CLASSES]\n'
      sed 's/^/  /' "$auto_classes"
      printf '\n=== end ===\n\n'
    } >"$auto_report"
  fi
  [ -s "$auto_err" ] && sed 's/^/[class-auto] /' "$auto_err" >&2 || true
  rm -f "$auto_err"

  installer_append_log_category_file boot boot info class-auto "$auto_report" || true

  while IFS= read -r auto_token || [ -n "$auto_token" ]; do
    auto_token=$(installer_trim_whitespace "$auto_token")
    [ -n "$auto_token" ] || continue
    installer_validate_class_reference "auto-detected class" "$auto_token"
    auto_tokens_found=true
    printf '%s\n' "$auto_token"
  done <"$auto_classes"
  rm -f "$auto_report" "$auto_classes"

  [ "$auto_tokens_found" = true ] || installer_fatal "automatic class detection did not emit any class tokens"
}

installer_merge_auto_classes() {
  manual_raw=$1
  auto_words=$2
  merged_tokens=
  manual_auto_groups=' '

  for manual_token in $(printf '%s\n' "$manual_raw" | tr ';,' ' ' | sed '/^[[:space:]]*$/d'); do
    [ -n "$manual_token" ] || continue
    if manual_group=$(installer_auto_group_from_token "$manual_token" 2>/dev/null); then
      if [ "$manual_group" = kernel ]; then
        installer_class_token_parts "$manual_token" >/dev/null
        kernel_requested=$INSTALLER_CLASS_TOKEN_NAME
        kernel_detected=
        for detected_token in $auto_words; do
          case "$detected_token" in kernel/*) kernel_detected=${detected_token#kernel/} ;; esac
        done
        case "$kernel_requested:$kernel_detected" in
          x64v2:x64v2|x64v2:x64v3|x64v3:x64v3|arm64:arm64) ;;
          *) installer_fatal 'the requested kernel class exceeds the detected CPU instruction set' ;;
        esac
      fi
      case "$manual_auto_groups" in
        *" ${manual_group} "*) ;;
        *) manual_auto_groups="${manual_auto_groups}${manual_group} " ;;
      esac
    fi
    case ",${merged_tokens}," in
      *",${manual_token},"*) installer_fatal 'the same manual class must not be selected twice' ;;
      *) merged_tokens="${merged_tokens:+$merged_tokens,}${manual_token}" ;;
    esac
  done

  for auto_token in $auto_words; do
    [ -n "$auto_token" ] || continue
    auto_group=$(installer_auto_group_from_token "$auto_token")
    installer_word_list_contains "$manual_auto_groups" "$auto_group" && continue
    case ",${merged_tokens}," in
      *",${auto_token},"*) ;;
      *) merged_tokens="${merged_tokens:+$merged_tokens,}${auto_token}" ;;
    esac
  done

  printf '%s\n' "$merged_tokens"
}

installer_normalize_class_tokens() (
  # Resolve only captured registry records, never filenames supplied by input.
  # A unique class basename is a convenience spelling; persist canonical refs.
  normalize_input=$1
  normalize_output=
  normalize_count=0
  normalize_seen=' '
  case "$normalize_input" in
    ''|[\;,]*|*[\;,]|*\;\;*|*,,*|*\;,*|*,\;*) installer_fatal 'class selection contains an empty token' ;;
  esac
  normalize_records=$(installer_configured_class_records) || return "$?"
  for normalize_token in $(printf '%s\n' "$normalize_input" | tr ';,' '  '); do
    normalize_count=$((normalize_count + 1))
    [ "$normalize_count" -le 64 ] || installer_fatal 'class selection exceeds token bound'
    [ "${#normalize_token}" -le 160 ] || installer_fatal 'class token exceeds its bound'
    case "$normalize_token" in
      *[!abcdefghijklmnopqrstuvwxyz0123456789_/-]*|/*|*/|*//*|*..*) installer_fatal 'noncanonical class token' ;;
      */*) normalize_ref=$normalize_token ;;
      *)
        normalize_ref=
        for normalize_record in $normalize_records; do
          normalize_group=${normalize_record%%.*}
          normalize_name=${normalize_record#*.}
          [ "${normalize_name##*/}" = "$normalize_token" ] || continue
          [ -z "$normalize_ref" ] || installer_fatal 'ambiguous class basename; use the canonical group/name spelling'
          normalize_ref="${normalize_group}/${normalize_name}"
        done
        [ -n "$normalize_ref" ] || installer_fatal 'unregistered class basename; use a registered group/name spelling'
        ;;
    esac
    installer_class_token_parts "$normalize_ref" >/dev/null
    case "$normalize_seen" in
      *" ${normalize_ref} "*) installer_fatal 'the same class must not be selected twice' ;;
    esac
    normalize_seen="${normalize_seen}${normalize_ref} "
    normalize_output="${normalize_output:+$normalize_output,}${normalize_ref}"
  done
  printf '%s\n' "$normalize_output"
)

installer_classes_raw() {
  seed_base=${1:-}
  if [ -n "${INSTALLER_CLASSES_RAW_CACHE:-}" ]; then
    printf '%s\n' "$INSTALLER_CLASSES_RAW_CACHE"
    return 0
  fi

  cmdline_raw=$(installer_cmdline_value classes 2>/dev/null || true)
  if [ -z "$cmdline_raw" ]; then
    cmdline_raw=$(installer_cmdline_value auto-install/classes 2>/dev/null || true)
  fi
  if [ -n "$cmdline_raw" ]; then
    raw=$cmdline_raw
  else
    debconf_raw=$(installer_debconf_value auto-install/classes 2>/dev/null || true)
    if [ -z "$debconf_raw" ]; then
      debconf_raw=$(installer_debconf_value classes 2>/dev/null || true)
    fi
    raw=$debconf_raw
  fi
  raw_cache_path=$(installer_classes_raw_cache_path)
  if [ -z "$raw" ] && [ -s "$raw_cache_path" ]; then
    # Prefer current installer inputs. A persisted cache can be stale across
    # retries or runtime reuse and must not suppress fresh auto-detected groups.
    IFS= read -r raw <"$raw_cache_path" || raw=
  fi

  [ "${#raw}" -le 8192 ] || installer_fatal 'class selection exceeds byte bound'
  case "$raw" in
    *[[:space:]]*|*[![:print:]]*)
      installer_fatal 'class selection has forbidden characters'
      ;;
  esac
  # Validate class tokens without putting a literal semicolon inside a shell
  # bracket expression. BusyBox ash parses that form differently from dash.
  # Escaped separators are accepted for bootloader command lines and are
  # normalized below; every other backslash remains in the token and fails.
  class_validation_tokens=$(printf '%s\n' "$raw" | sed 's/\\\([;,]\)/ /g; s/[;,]/ /g')
  for class_validation_token in $class_validation_tokens; do
    case "$class_validation_token" in
      ''|*[!abcdefghijklmnopqrstuvwxyz0123456789_/-]*)
        installer_fatal 'class selection has forbidden characters'
        ;;
    esac
  done
  normalized_raw=$(printf '%s\n' "$raw" | sed 's/\\\([;,]\)/\1/g')
  normalized_raw=$(installer_expand_default_classes "$(installer_seed_base "$seed_base")" "$normalized_raw") || return "$?"
  normalized_raw=$(installer_normalize_class_tokens "$normalized_raw") || return "$?"
  # A command substitution inside a here-document loses the detector status.
  # Capture it as a checked assignment before consuming any class output.
  if command -v installer_operation_context_repo >/dev/null 2>&1; then
    installer_operation_context_repo FILE_COMMON_MOD_CLASS_SELECTION 204 class_auto
  fi
  auto_output=$(installer_auto_class_tokens "$(installer_seed_base "$seed_base")") || return "$?"
  auto_tokens=
  while IFS= read -r auto_token || [ -n "$auto_token" ]; do
    [ -n "$auto_token" ] || continue
    auto_tokens="${auto_tokens:+$auto_tokens }$auto_token"
  done <<EOF
$auto_output
EOF
  normalized_raw=$(installer_merge_auto_classes "$normalized_raw" "$auto_tokens") || return "$?"
  normalized_raw=$(installer_normalize_class_tokens "$normalized_raw") || return "$?"
  [ -n "$normalized_raw" ] || installer_fatal "kernel cmdline must include classes=<class>,<class>,... for class-select values; arch/cpu/gpu/disk are auto-detected"
  INSTALLER_CLASSES_RAW_CACHE=$normalized_raw
  install -d -m 0700 "$(dirname "$raw_cache_path")" || return "$?"
  raw_cache_tmp=$(mktemp "${raw_cache_path}.XXXXXX") || return "$?"
  printf '%s\n' "$normalized_raw" >"$raw_cache_tmp" || return "$?"
  chmod 0600 "$raw_cache_tmp" || return "$?"
  mv "$raw_cache_tmp" "$raw_cache_path" || return "$?"
  printf '%s\n' "$normalized_raw"
}

installer_classes_lines() {
  class_lines_raw=$(installer_classes_raw "${1:-}") || return "$?"
  printf '%s\n' "$class_lines_raw" | tr ';,' '\n' | sed '/^[[:space:]]*$/d; s/^[[:space:]]*//; s/[[:space:]]*$//'
}

installer_selected_class_records_path() {
  printf '%s/selected-classes.tsv\n' "$(installer_runtime_state_dir)"
}

installer_runtime_install_conf_path() {
  printf '%s/state/install.conf\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

installer_classes_raw_cache_path() {
  printf '%s/state/classes.raw\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

installer_resolve_class_token() {
  seed_base=$1
  class_token=$2
  installer_class_token_parts "$class_token" >/dev/null
  class_name=$INSTALLER_CLASS_TOKEN_NAME
  requested_group=${INSTALLER_CLASS_TOKEN_GROUP:-}

  installer_class_has_manifest_record "$requested_group" "$class_name" || installer_fatal 'unregistered selector'
  installer_class_exists "$seed_base" "$requested_group" "$class_name" || installer_fatal "registered class fragment is missing: $requested_group/$class_name"
  INSTALLER_RESOLVED_CLASS_GROUP=$requested_group
  INSTALLER_RESOLVED_CLASS_NAME=$class_name

}

installer_resolve_selected_class_records() {
  seed_base=$1
  records_path=$2
  seen_groups=' '
  seen_references=' '
  classes_raw=$(installer_classes_raw "$seed_base") || return "$?"
  class_lines=$(installer_classes_lines "$seed_base") || return "$?"

  install -d -m 0700 "$(dirname "$records_path")"
  : >"$records_path"

  for class_token in $class_lines; do
    installer_resolve_class_token "$seed_base" "$class_token"
    group_name=$INSTALLER_RESOLVED_CLASS_GROUP
    class_name=$INSTALLER_RESOLVED_CLASS_NAME
    case "$seen_references" in
      *" ${group_name}/${class_name} "*) installer_fatal 'the same class must not be selected twice' ;;
    esac
    seen_references="${seen_references}${group_name}/${class_name} "
    case "$seen_groups" in
      *" ${group_name} "*)
        installer_group_is_multi "$group_name" || installer_fatal "group '${group_name}' requires exactly one selected class"
        ;;
    esac
    case "$seen_groups" in
      *" ${group_name} "*) ;;
      *) seen_groups="${seen_groups}${group_name} " ;;
    esac
    printf '%s|%s|%s\n' "$group_name" "$class_name" "$(installer_class_source_path "$group_name" "$class_name")" >>"$records_path"
  done

  while IFS= read -r group_name || [ -n "$group_name" ]; do
    [ -n "$group_name" ] || continue
    case "$(installer_group_required_status "$group_name")" in
      required)
        case "$seen_groups" in
          *" ${group_name} "*) ;;
          *) installer_fatal "required class group '${group_name}' is missing from classes=${classes_raw}" ;;
        esac
        ;;
    esac
  done <<EOF
$(installer_group_names)
EOF

  sort_path="${records_path}.sort.$$"
  : >"$sort_path"
  while IFS='|' read -r group_name class_name class_relpath || [ -n "$group_name" ]; do
    [ -n "$group_name" ] || continue
    printf '%08d|%s|%s|%s\n' \
      "$(installer_group_order "$group_name")" \
      "$group_name" \
      "$class_name" \
      "$class_relpath" >>"$sort_path"
  done <"$records_path"
  sort -t'|' -k1,1n -k2,2 -k3,3 "$sort_path" | cut -d'|' -f2- >"$records_path"
  rm -f "$sort_path"
}

installer_group_selected_class_value() {
  group_name=$1
  context_var=$(installer_group_context_var "$group_name")
  eval "class_name=\${$context_var:-}"
  if [ -n "$class_name" ]; then
    printf '%s\n' "$class_name"
    return 0
  fi

  records_path=$(installer_selected_class_records_path)
  if [ -r "$records_path" ]; then
    if installer_group_is_multi "$group_name"; then
      class_name=
      while IFS='|' read -r record_group record_class _record_path || [ -n "$record_group" ]; do
        [ "$record_group" = "$group_name" ] || continue
        class_name="${class_name:+$class_name }$record_class"
      done <"$records_path"
    else
      class_name=
      while IFS='|' read -r record_group record_class _record_path || [ -n "$record_group" ]; do
        [ "$record_group" = "$group_name" ] || continue
        class_name=$record_class
        break
      done <"$records_path"
    fi
    if [ -n "$class_name" ]; then
      eval "$context_var=\$class_name"
      printf '%s\n' "$class_name"
      return 0
    fi
  fi

  return 1
}

installer_selected_group_names() {
  if [ -n "${INSTALLER_SELECTED_GROUPS:-}" ]; then
    for group_name in $INSTALLER_SELECTED_GROUPS; do
      printf '%s\n' "$group_name"
    done
    return 0
  fi

  records_path=$(installer_selected_class_records_path)
  [ -r "$records_path" ] || return 1
  while IFS='|' read -r group_name _class_name _class_path || [ -n "$group_name" ]; do
    [ -n "$group_name" ] || continue
    printf '%s\n' "$group_name"
  done <"$records_path"
}

installer_selected_class_names() {
  if [ -n "${INSTALLER_SELECTED_CLASSES:-}" ]; then
    for class_name in $INSTALLER_SELECTED_CLASSES; do
      printf '%s\n' "$class_name"
    done
    return 0
  fi

  records_path=$(installer_selected_class_records_path)
  [ -r "$records_path" ] || return 1
  while IFS='|' read -r _group_name class_name _class_path || [ -n "$class_name" ]; do
    [ -n "$class_name" ] || continue
    printf '%s\n' "$class_name"
  done <"$records_path"
}

installer_selected_class_refs() {
  if [ -n "${INSTALLER_SELECTED_CLASS_REFS:-}" ]; then
    for class_ref in $INSTALLER_SELECTED_CLASS_REFS; do
      printf '%s\n' "$class_ref"
    done
    return 0
  fi

  records_path=$(installer_selected_class_records_path)
  [ -r "$records_path" ] || return 1
  while IFS='|' read -r group_name class_name _class_path || [ -n "$group_name" ]; do
    [ -n "$group_name" ] || continue
    printf '%s/%s\n' "$group_name" "$class_name"
  done <"$records_path"
}

installer_selected_class_paths() {
  records_path=$(installer_selected_class_records_path)
  if [ -r "$records_path" ]; then
    while IFS='|' read -r record_group _class_name class_path || [ -n "$record_group" ]; do
      [ -n "$record_group" ] || continue
      [ "$record_group" = profile ] && continue
      [ -n "$class_path" ] || continue
      printf '%s\n' "$class_path"
    done <"$records_path"
    return 0
  fi

  while IFS= read -r group_name || [ -n "$group_name" ]; do
    [ -n "$group_name" ] || continue
    [ "$group_name" = profile ] && continue
    class_name=$(installer_group_selected_class_value "$group_name")
    [ -n "$class_name" ] || continue
    printf '%s\n' "$(installer_class_source_path "$group_name" "$class_name")"
  done <<EOF
$(installer_selected_group_names 2>/dev/null || true)
EOF
}

installer_selected_class_list_has() {
  class_list=$1
  needle=$2
  case " ${class_list} " in
    *" ${needle} "*) return 0 ;;
  esac
  return 1
}

installer_class_reference_matches_selected() {
  class_reference=$1
  selected_group=$2
  selected_class=$3

  installer_class_token_parts "$class_reference" >/dev/null
  [ "$INSTALLER_CLASS_TOKEN_NAME" = "$selected_class" ] || return 1
  [ -z "$INSTALLER_CLASS_TOKEN_GROUP" ] || [ "$INSTALLER_CLASS_TOKEN_GROUP" = "$selected_group" ]
}

installer_class_reference_list_matches_selected() {
  reference_list=$1
  selected_group=$2
  selected_class=$3

  for class_reference in $reference_list; do
    installer_class_reference_matches_selected "$class_reference" "$selected_group" "$selected_class" && return 0
  done
  return 1
}

installer_selected_class_reference_is_selected() {
  class_reference=$1
  records_path=$(installer_selected_class_records_path)

  [ -r "$records_path" ] || return 1
  while IFS='|' read -r selected_group selected_class _selected_relpath || [ -n "$selected_group" ]; do
    [ -n "$selected_group" ] || continue
    installer_class_reference_matches_selected "$class_reference" "$selected_group" "$selected_class" && return 0
  done <"$records_path"
  return 1
}

installer_selected_class_allowed_reference_matches() {
  allowed_references=$1

  for allowed_reference in $allowed_references; do
    installer_selected_class_reference_is_selected "$allowed_reference" && return 0
  done
  return 1
}

installer_selected_class_for_purpose() {
  group_purpose=$1
  group_name=$(installer_group_for_purpose "$group_purpose" 2>/dev/null || true)
  [ -n "$group_name" ] || return 1
  class_name=$(installer_group_selected_class_value "$group_name")
  [ -n "$class_name" ] || return 1
  printf '%s\n' "$class_name"
}

installer_clear_selected_class_state() {
  seed_base=${1:-}
  records_path=$(installer_selected_class_records_path)

  clear_groups=
  while IFS= read -r group_name || [ -n "$group_name" ]; do
    [ -n "$group_name" ] || continue
    case " ${clear_groups} " in
      *" ${group_name} "*) ;;
      *) clear_groups="${clear_groups:+$clear_groups }$group_name" ;;
    esac
  done <<EOF
$(installer_group_names "$seed_base" 2>/dev/null || true)
EOF
  if [ -r "$records_path" ]; then
    while IFS='|' read -r group_name _class_name _class_path || [ -n "$group_name" ]; do
      [ -n "$group_name" ] || continue
      case " ${clear_groups} " in
        *" ${group_name} "*) ;;
        *) clear_groups="${clear_groups:+$clear_groups }$group_name" ;;
      esac
    done <"$records_path"
  fi
  for group_name in $clear_groups; do
    context_var=$(installer_group_context_var "$group_name")
    unset "$context_var" 2>/dev/null || true
  done

  unset INSTALLER_SELECTED_GROUPS INSTALLER_SELECTED_CLASSES INSTALLER_SELECTED_CLASS_REFS \
    INSTALLER_HOST_VARIANT INSTALLER_STORAGE_HOST_PROFILE_PREFIX \
    INSTALLER_INSTALL_DISK_CANDIDATES_DEFAULT INSTALLER_DEFAULT_INSTALL_DISK \
    INSTALLER_HOST_PROFILE INSTALLER_HOST_FAMILY INSTALLER_HOOK_FAMILY \
    INSTALLER_HOST_PROFILE_ENV_DIR INSTALLER_HOST_PROFILE_ENV_NAME 2>/dev/null || true
}
