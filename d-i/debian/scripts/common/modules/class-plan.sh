#!/bin/sh
# Sourced installer module; edit this file directly.

installer_classes_conf_cache_path() {
  printf '%s/cache/classes.state.conf\n' "${DIR_INSTALLER_RUNTIME:-${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}}"
}

installer_classes_plan_path() {
  printf '%s/state/class-registry.tsv\n' "${DIR_INSTALLER_RUNTIME:-${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}}"
}

installer_ensure_classes_conf_path() {
  if [ -n "${INSTALLER_CLASSES_CONF_PATH_CACHE:-}" ]; then
    return 0
  fi
  INSTALLER_CLASSES_CONF_PATH_CACHE=$(installer_classes_conf_cache_path)
}

installer_classes_conf_path() {
  installer_ensure_classes_conf_path
  printf '%s\n' "$INSTALLER_CLASSES_CONF_PATH_CACHE"
}

installer_class_metadata_read_path() {
  metadata_relpath=$(installer_repo_asset_path "$1") || return $?
  installer_validate_relative_seed_path "$metadata_relpath"

  if [ -n "${INSTALLER_SOURCE_ROOT:-}" ]; then
    metadata_path="${INSTALLER_SOURCE_ROOT%/}/${metadata_relpath}"
    [ -r "$metadata_path" ] || installer_fatal "installer class metadata is not readable: ${metadata_path}"
    printf '%s\n' "$metadata_path"
    return 0
  fi

  metadata_path="$(installer_runtime_cache_dir)/${metadata_relpath}"
  if [ ! -s "$metadata_path" ]; then
    seed_base=$(installer_seed_base "")
    install -d -m 0700 "$(dirname "$metadata_path")"
    installer_fetch_file "$seed_base" "$metadata_relpath" "$metadata_path" 0600
  fi
  printf '%s\n' "$metadata_path"
}

installer_classes_cache_name_token() {
  printf '%s' "$1" | tr -c 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789' '_'
}

installer_classes_section_var_name() {
  printf 'INSTALLER_CLASSES_SECTION__%s\n' "$(installer_classes_cache_name_token "$1")"
}

installer_classes_value_var_name() {
  printf 'INSTALLER_CLASSES_VALUE__%s__%s\n' \
    "$(installer_classes_cache_name_token "$1")" \
    "$(installer_classes_cache_name_token "$2")"
}

installer_classes_cache_add_section() {
  section_name=$1
  INSTALLER_CLASSES_SECTION_NAMES="${INSTALLER_CLASSES_SECTION_NAMES:+$INSTALLER_CLASSES_SECTION_NAMES }$section_name"
  section_var=$(installer_classes_section_var_name "$section_name")
  eval "$section_var=1"
}

installer_classes_cache_set_value() {
  section_name=$1
  key_name=$2
  key_value=$3
  value_var=$(installer_classes_value_var_name "$section_name" "$key_name")
  eval "$value_var=$(installer_shell_quote "$key_value")"
}

installer_classes_cache_maybe_set_value() {
  section_name=$1
  key_name=$2
  key_value=${3:-}
  [ -n "$key_value" ] || return 0
  installer_classes_cache_set_value "$section_name" "$key_name" "$key_value"
}

installer_classes_plan_field_value() {
  case "${1:-}" in
    __EMPTY__) printf '%s\n' "" ;;
    *) printf '%s\n' "${1:-}" ;;
  esac
}

# Rich dependency and selection metadata are compiled once with the release.
# d-i reads that authenticated data; it does not recompile mutable class files.
installer_generate_class_plan() {
  plan_path=$(installer_classes_plan_path)
  state_path=$(installer_classes_conf_cache_path)
  registry_source=$(installer_class_metadata_read_path FILE_CLASS_REGISTRY) || return "$?"
  state_source=$(installer_class_metadata_read_path FILE_CLASS_STATE) || return "$?"
  install -d -m 0700 "$(dirname "$plan_path")" "$(dirname "$state_path")" || return "$?"
  cp "$registry_source" "$plan_path" && cp "$state_source" "$state_path" || return "$?"
  chmod 0600 "$plan_path" "$state_path"
}
