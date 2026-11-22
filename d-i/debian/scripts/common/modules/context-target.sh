#!/bin/sh
# Sourced installer module; edit this file directly.

installer_populate_selected_class_state() {
  seed_base=${1:-}
  records_path=$(installer_selected_class_records_path)
  selected_groups=
  selected_classes=
  selected_class_refs=

  installer_resolve_selected_class_records "$seed_base" "$records_path"
  installer_clear_selected_class_state "$seed_base"

  while IFS='|' read -r group_name class_name class_relpath || [ -n "$group_name" ]; do
    [ -n "$group_name" ] || continue
    context_var=$(installer_group_context_var "$group_name")
    if installer_group_is_multi "$group_name"; then
      eval "context_current=\${$context_var:-}"
      context_current="${context_current:+$context_current }$class_name"
      eval "$context_var=\$context_current"
    else
      eval "$context_var=\$class_name"
    fi
    case " ${selected_groups} " in
      *" ${group_name} "*) ;;
      *) selected_groups="${selected_groups:+$selected_groups }$group_name" ;;
    esac
    selected_classes="${selected_classes:+$selected_classes }$class_name"
    selected_class_refs="${selected_class_refs:+$selected_class_refs }${group_name}/${class_name}"
  done <"$records_path"

  INSTALLER_SELECTED_GROUPS=$selected_groups
  INSTALLER_SELECTED_CLASSES=$selected_classes
  INSTALLER_SELECTED_CLASS_REFS=$selected_class_refs

  base_role_group=$(installer_group_for_purpose host-variant)
  storage_group=$(installer_group_for_purpose storage)
  [ -n "$base_role_group" ] || installer_fatal "classes config must define a host-variant group purpose"
  [ -n "$storage_group" ] || installer_fatal "classes config must define a storage group purpose"

  role_classes=$(installer_group_selected_class_value "$base_role_group")
  storage_class=$(installer_group_selected_class_value "$storage_group")

  host_variant=
  role_count=0
  desktop_role=
  for role_class in $role_classes; do
    role_variant=$(installer_class_meta_value "$seed_base" "$base_role_group" "$role_class" host_variant)
    case "$role_variant:$role_class" in desktop:desktop/*|server:server/*) ;; *) installer_fatal 'role class has no matching registered family' ;; esac
    if [ -n "$host_variant" ] && [ "$host_variant" != "$role_variant" ]; then
      installer_fatal 'desktop and server role classes cannot be combined'
    fi
    host_variant=$role_variant
    role_count=$((role_count + 1))
    if [ "$host_variant" = desktop ]; then desktop_role=$role_class; fi
  done
  [ "$role_count" -gt 0 ] || installer_fatal 'at least one registered role class is required'
  if [ "$host_variant" = desktop ] && [ "$role_count" -ne 1 ]; then
    installer_fatal 'select exactly one desktop role: base, medium or full'
  fi
  host_profile_prefix=$(installer_class_meta_value "$seed_base" "$storage_group" "$storage_class" host_profile_prefix)
  host_family=$(installer_class_meta_value "$seed_base" "$storage_group" "$storage_class" host_family)
  hook_family=$(installer_class_meta_value "$seed_base" "$storage_group" "$storage_class" hook_family)
  install_disk_candidates_default=$(installer_class_meta_value "$seed_base" "$storage_group" "$storage_class" install_disk_candidates)
  default_install_disk=$(installer_class_meta_value "$seed_base" "$storage_group" "$storage_class" default_install_disk)
  host_profile_env_dir=$host_variant
  host_profile_env_name=

  case "$host_variant" in desktop|server) ;; *) installer_fatal "unsupported role family" ;; esac
  [ -n "$host_profile_prefix" ] || installer_fatal "selected class ${storage_group}/${storage_class} must define HostProfilePrefix in ${DIR_CATALOG_COMPILED}/storage.cfg"
  [ -n "$host_family" ] || installer_fatal "selected class ${storage_group}/${storage_class} must define HostFamily in ${DIR_CATALOG_COMPILED}/storage.cfg"
  [ -n "$hook_family" ] || installer_fatal "selected class ${storage_group}/${storage_class} must define HookFamily in ${DIR_CATALOG_COMPILED}/storage.cfg"
  [ -n "$install_disk_candidates_default" ] || installer_fatal "selected class ${storage_group}/${storage_class} must define InstallDiskCandidates in ${DIR_CATALOG_COMPILED}/storage.cfg"
  [ -n "$default_install_disk" ] || installer_fatal "selected class ${storage_group}/${storage_class} must define DefaultInstallDisk in ${DIR_CATALOG_COMPILED}/storage.cfg"

  profile_group=$(installer_group_for_purpose host-profile-override 2>/dev/null || true)
  profile_class=
  if [ -n "$profile_group" ]; then
    profile_class=$(installer_group_selected_class_value "$profile_group" 2>/dev/null || true)
  fi
  if [ -n "$profile_class" ]; then
    profile_env_dir=$(installer_class_meta_value "$seed_base" "$profile_group" "$profile_class" host_profile_prefix)
    profile_host_family=$(installer_class_meta_value "$seed_base" "$profile_group" "$profile_class" host_family)
    profile_hook_family=$(installer_class_meta_value "$seed_base" "$profile_group" "$profile_class" hook_family)
    [ -n "$profile_env_dir" ] || installer_fatal "selected class ${profile_group}/${profile_class} must define HostProfilePrefix in ${DIR_CATALOG_COMPILED}/profile.cfg"
    [ -n "$profile_host_family" ] || installer_fatal "selected class ${profile_group}/${profile_class} must define HostFamily in ${DIR_CATALOG_COMPILED}/profile.cfg"
    [ -n "$profile_hook_family" ] || installer_fatal "selected class ${profile_group}/${profile_class} must define HookFamily in ${DIR_CATALOG_COMPILED}/profile.cfg"
    [ "$profile_env_dir" = "$host_variant" ] || installer_fatal "role/profile family mismatch"
    host_profile_env_dir=$profile_env_dir
    case "$profile_class" in
      "$host_variant"/*) host_profile_env_name=${profile_class#*/} ;;
      *) installer_fatal 'profile class directory differs from selected role family' ;;
    esac
    host_family=$profile_host_family
    hook_family=$profile_hook_family
  fi

  while IFS='|' read -r group_name class_name class_relpath || [ -n "$group_name" ]; do
    [ -n "$group_name" ] || continue
    required_classes=$(installer_class_meta_value "$seed_base" "$group_name" "$class_name" requires_classes)
    allowed_hardware_classes=$(installer_class_meta_value "$seed_base" "$group_name" "$class_name" allowed_hardware_classes)
    rejected_classes=$(installer_class_meta_value "$seed_base" "$group_name" "$class_name" rejected_classes)
    for required_class in $required_classes; do
      installer_selected_class_reference_is_selected "$required_class" || \
        installer_fatal "selected class ${group_name}/${class_name} requires class ${required_class}"
    done
    if [ -n "$allowed_hardware_classes" ]; then
      installer_selected_class_allowed_reference_matches "$allowed_hardware_classes" || \
        installer_fatal "selected class ${group_name}/${class_name} is only allowed with one of: ${allowed_hardware_classes}"
    fi
    for rejected_class in $rejected_classes; do
      installer_selected_class_reference_is_selected "$rejected_class" && \
        installer_fatal "selected class ${group_name}/${class_name} rejects class ${rejected_class}"
    done
  done <"$records_path"

  [ -n "$profile_class" ] || installer_fatal "an explicit registered profile is required before partitioning"
  INSTALLER_ROLE_IDS=$role_classes
  INSTALLER_DESKTOP_ROLE=$desktop_role
  INSTALLER_HOST_VARIANT=$host_variant
  INSTALLER_STORAGE_HOST_PROFILE_PREFIX=$host_profile_prefix
  INSTALLER_INSTALL_DISK_CANDIDATES_DEFAULT=$install_disk_candidates_default
  INSTALLER_DEFAULT_INSTALL_DISK=$default_install_disk
  INSTALLER_HOST_PROFILE_ENV_DIR=$host_profile_env_dir
  INSTALLER_HOST_PROFILE_ENV_NAME=$host_profile_env_name
  INSTALLER_HOST_PROFILE="${host_profile_env_dir}-${host_profile_env_name}"
  INSTALLER_HOST_FAMILY=$host_family
  INSTALLER_HOOK_FAMILY=$hook_family
}

installer_write_runtime_install_conf() {
  runtime_conf_path=$1
  storage_group=$(installer_group_for_purpose storage 2>/dev/null || true)
  storage_class_value=
  if [ -n "$storage_group" ]; then
    storage_class_value=$(installer_group_selected_class_value "$storage_group" 2>/dev/null || true)
  fi

  {
    printf '# Generated runtime installer class config\n'
    printf '[selected]\n'
    printf 'classes_raw=%s\n' "$INSTALLER_CLASSES_RAW"
    printf 'selected_groups=%s\n' "$INSTALLER_SELECTED_GROUPS"
    printf 'selected_classes=%s\n' "$INSTALLER_SELECTED_CLASSES"
    printf 'selected_class_refs=%s\n' "$INSTALLER_SELECTED_CLASS_REFS"
    printf 'roles=%s\n' "$INSTALLER_ROLE_IDS"
    printf 'debug_logs=%s\n' "${INSTALLER_DEBUG_LOGS:-0}"
    printf 'host_variant=%s\n' "$INSTALLER_HOST_VARIANT"
    printf 'host_profile=%s\n' "$INSTALLER_HOST_PROFILE"
    printf 'host_family=%s\n' "$INSTALLER_HOST_FAMILY"
    printf 'hook_family=%s\n' "$INSTALLER_HOOK_FAMILY"
    printf 'host_profile_env_dir=%s\n' "$INSTALLER_HOST_PROFILE_ENV_DIR"
    printf 'host_profile_env_name=%s\n' "$INSTALLER_HOST_PROFILE_ENV_NAME"
    printf 'storage_host_profile_prefix=%s\n' "$INSTALLER_STORAGE_HOST_PROFILE_PREFIX"
    printf 'storage_class=%s\n' "${INSTALLER_DISK_CLASS:-$storage_class_value}"
    printf 'install_disk_candidates_default=%s\n' "$INSTALLER_INSTALL_DISK_CANDIDATES_DEFAULT"
    printf 'default_install_disk=%s\n' "$INSTALLER_DEFAULT_INSTALL_DISK"

    while IFS= read -r group_name || [ -n "$group_name" ]; do
      [ -n "$group_name" ] || continue
      class_name=$(installer_group_selected_class_value "$group_name")
      [ -n "$class_name" ] || continue
      printf '\n[group.%s]\n' "$group_name"
      printf 'class=%s\n' "$class_name"
      printf 'required=%s\n' "$(installer_group_required_status "$group_name")"
      printf 'purpose=%s\n' "$(installer_group_purpose "$group_name")"
    done <<EOF
$(installer_selected_group_names 2>/dev/null || true)
EOF
  } >"$runtime_conf_path"
  chmod 0600 "$runtime_conf_path"
}

installer_validate_class_set() {
  if [ -z "${INSTALLER_CLASSES_RAW_CACHE:-}" ]; then
    INSTALLER_CLASSES_RAW_CACHE=$(installer_classes_raw "${1:-}")
  fi
  installer_validate_class_manifest
  installer_resolve_selected_class_records "${1:-}" "$(installer_selected_class_records_path)"
}

installer_resolve_install_target_defaults() {
  if [ -z "${INSTALLER_INSTALL_DISK_CANDIDATES_DEFAULT:-}" ] || [ -z "${INSTALLER_DEFAULT_INSTALL_DISK:-}" ]; then
    installer_load_context_if_present || true
  fi

  [ -n "${INSTALLER_INSTALL_DISK_CANDIDATES_DEFAULT:-}" ] || installer_fatal "installer storage defaults are unavailable; context generation did not populate INSTALLER_INSTALL_DISK_CANDIDATES_DEFAULT"
  [ -n "${INSTALLER_DEFAULT_INSTALL_DISK:-}" ] || installer_fatal "installer storage defaults are unavailable; context generation did not populate INSTALLER_DEFAULT_INSTALL_DISK"

  if [ -z "${INSTALL_DISK_CANDIDATES:-}" ]; then
    INSTALL_DISK_CANDIDATES=$INSTALLER_INSTALL_DISK_CANDIDATES_DEFAULT
  fi
  if [ -z "${DEV_INSTALL_DISK:-}" ]; then
    DEV_INSTALL_DISK=$INSTALLER_DEFAULT_INSTALL_DISK
  fi
}

installer_resolve_host_profile() {
  requested_host_profile=${1:-}

  if [ -n "$requested_host_profile" ]; then
    printf '%s\n' "$requested_host_profile"
    return 0
  fi

  installer_load_context_if_present || true
  [ -n "${INSTALLER_HOST_PROFILE:-}" ] || installer_fatal "HOST_PROFILE is required for installer hook dispatch"
  printf '%s\n' "$INSTALLER_HOST_PROFILE"
}

installer_seed_class_answers() {
  classes_raw=$1

  installer_seed_debconf_value d-i auto-install/classes string "$classes_raw" || return "$?"
  installer_seed_debconf_value d-i classes string "$classes_raw" || return "$?"
}

installer_write_context() {
  seed_base=$1
  runtime_dir=$(installer_runtime_dir)
  context_env=$(installer_context_env_path)
  runtime_install_conf=$(installer_runtime_install_conf_path)

  install -d -m 0700 \
    "$runtime_dir" \
    "$(installer_runtime_state_dir)" \
    "$(installer_runtime_cache_dir)" \
    "$(installer_runtime_bootstrap_dir)"
  installer_ensure_log_files

  seed_base=$(installer_seed_base "$seed_base")
  installer_persist_seed_source "$seed_base"
  installer_ensure_repo_env "$seed_base"
  if command -v installer_operation_context_repo >/dev/null 2>&1; then
    installer_operation_context_repo scripts/common/modules/class-selection.sh 238 class_selection
  fi
  classes_raw=$(installer_classes_raw "$seed_base") || return "$?"
  INSTALLER_CLASSES_RAW_CACHE=$classes_raw
  installer_validate_class_manifest
  installer_populate_selected_class_state "$seed_base"
  if command -v installer_operation_context_repo >/dev/null 2>&1; then
    installer_operation_context_repo scripts/common/modules/profiles.sh 245 profile_policy
  fi
  profile_plan_policy=$(installer_profile_plan_policy "$seed_base") ||
    installer_fatal 'cannot resolve frozen profile policy'
  INSTALLER_PROFILE_SSH_SERVER_ENABLE=${profile_plan_policy%%|*}
  profile_policy_tail=${profile_plan_policy#*|}
  INSTALLER_PROFILE_SSH_SERVER_PORT=${profile_policy_tail%%|*}
  profile_policy_tail=${profile_policy_tail#*|}
  INSTALLER_PROFILE_SNAPSHOTS_POLICY=${profile_policy_tail%%|*}
  profile_policy_tail=${profile_policy_tail#*|}
  INSTALLER_PROFILE_CRYPTO_LUKS2_ROOT=${profile_policy_tail%%|*}
  profile_policy_tail=${profile_policy_tail#*|}
  INSTALLER_PROFILE_CRYPTO_LUKS2_HOME=${profile_policy_tail%%|*}
  profile_policy_tail=${profile_policy_tail#*|}
  INSTALLER_PROFILE_WIFI_ENABLE=${profile_policy_tail%%|*}
  profile_policy_tail=${profile_policy_tail#*|}
  INSTALLER_PROFILE_NETWORK_PRIMARY_IFACE=${profile_policy_tail%%|*}
  profile_policy_tail=${profile_policy_tail#*|}
  INSTALLER_PROFILE_IPV6_ENABLE=${profile_policy_tail%%|*}
  profile_policy_tail=${profile_policy_tail#*|}
  INSTALLER_PROFILE_CODEX_ONLY_ENABLE=${profile_policy_tail%%|*}
  profile_policy_tail=${profile_policy_tail#*|}
  INSTALLER_PROFILE_WHISPER_ENABLE=${profile_policy_tail%%|*}
  profile_policy_tail=${profile_policy_tail#*|}
  INSTALLER_PROFILE_LLAMA_ENABLE=${profile_policy_tail%%|*}
  profile_policy_tail=${profile_policy_tail#*|}
  INSTALLER_PROFILE_PARTMAN_CEILING_ENABLE=${profile_policy_tail%%|*}
  profile_policy_tail=${profile_policy_tail#*|}
  INSTALLER_PROFILE_PARTMAN_CEILING_MB=${profile_policy_tail%%|*}
  profile_policy_tail=${profile_policy_tail#*|}
  INSTALLER_PROFILE_PARTMAN_REUSE_ENABLE=${profile_policy_tail%%|*}
  INSTALLER_PROFILE_PARTMAN_REUSE_START=${profile_policy_tail#*|}
  if command -v installer_operation_context_repo >/dev/null 2>&1; then
    installer_operation_context_repo scripts/common/modules/installation-plan.sh 269 class_plan
  fi
  installer_prepare_class_plan "$seed_base" || return "$?"
  installer_export_logging_policy
  installer_seed_class_answers "$classes_raw"
  INSTALLER_CLASSES_RAW=$classes_raw
  installer_write_runtime_install_conf "$runtime_install_conf"
  installer_info "selected installer classes raw: ${classes_raw}"
  installer_info "selected installer class refs: ${INSTALLER_SELECTED_CLASS_REFS:-}"
  installer_info "selected installer host profile: ${INSTALLER_HOST_PROFILE:-}"
  installer_log_boot_context

  {
    printf 'INSTALLER_SEED_URL_BASE=%s\n' "$(installer_shell_quote "${SEED_URL_BASE:-}")"
    printf 'INSTALLER_SEED_FILE_BASE=%s\n' "$(installer_shell_quote "${SEED_FILE_BASE:-}")"
    printf 'INSTALLER_SEED_BASE=%s\n' "$(installer_shell_quote "$seed_base")"
    printf 'INSTALLER_SEED_SOURCE_TYPE=%s\n' "$(installer_shell_quote "$(installer_seed_source_type "$seed_base")")"
    printf 'INSTALLER_CLASSES_RAW=%s\n' "$(installer_shell_quote "$classes_raw")"
    printf 'CLASSES=%s\n' "$(installer_shell_quote "$classes_raw")"
    printf 'INSTALLER_SELECTED_GROUPS=%s\n' "$(installer_shell_quote "${INSTALLER_SELECTED_GROUPS:-}")"
    printf 'INSTALLER_SELECTED_CLASSES=%s\n' "$(installer_shell_quote "${INSTALLER_SELECTED_CLASSES:-}")"
    printf 'INSTALLER_SELECTED_CLASS_REFS=%s\n' "$(installer_shell_quote "${INSTALLER_SELECTED_CLASS_REFS:-}")"
    printf 'INSTALLER_DEBUG_LOGS=%s\n' "$(installer_shell_quote "${INSTALLER_DEBUG_LOGS:-0}")"
    printf 'INSTALLER_ROLE_IDS=%s\n' "$(installer_shell_quote "$INSTALLER_ROLE_IDS")"
    printf 'INSTALLER_DESKTOP_ROLE=%s\n' "$(installer_shell_quote "$INSTALLER_DESKTOP_ROLE")"
    printf 'INSTALLER_RELEASE_ID=%s\n' "$(installer_shell_quote "$INSTALLER_RELEASE_ID")"
    printf 'INSTALLER_SUITE=%s\n' "$(installer_shell_quote "$INSTALLER_SUITE")"
    printf 'INSTALLER_HOST_VARIANT=%s\n' "$(installer_shell_quote "${INSTALLER_HOST_VARIANT:-}")"
    printf 'INSTALLER_HOST_PROFILE=%s\n' "$(installer_shell_quote "${INSTALLER_HOST_PROFILE:-}")"
    printf 'INSTALLER_PROFILE_SSH_SERVER_ENABLE=%s\n' "$(installer_shell_quote "$INSTALLER_PROFILE_SSH_SERVER_ENABLE")"
    printf 'INSTALLER_PROFILE_SSH_SERVER_PORT=%s\n' "$(installer_shell_quote "$INSTALLER_PROFILE_SSH_SERVER_PORT")"
    printf 'INSTALLER_PROFILE_SNAPSHOTS_POLICY=%s\n' "$(installer_shell_quote "$INSTALLER_PROFILE_SNAPSHOTS_POLICY")"
    printf 'INSTALLER_PROFILE_CRYPTO_LUKS2_ROOT=%s\n' "$(installer_shell_quote "$INSTALLER_PROFILE_CRYPTO_LUKS2_ROOT")"
    printf 'INSTALLER_PROFILE_CRYPTO_LUKS2_HOME=%s\n' "$(installer_shell_quote "$INSTALLER_PROFILE_CRYPTO_LUKS2_HOME")"
    printf 'INSTALLER_PROFILE_WIFI_ENABLE=%s\n' "$(installer_shell_quote "$INSTALLER_PROFILE_WIFI_ENABLE")"
    printf 'INSTALLER_PROFILE_NETWORK_PRIMARY_IFACE=%s\n' "$(installer_shell_quote "$INSTALLER_PROFILE_NETWORK_PRIMARY_IFACE")"
    printf 'INSTALLER_PROFILE_IPV6_ENABLE=%s\n' "$(installer_shell_quote "$INSTALLER_PROFILE_IPV6_ENABLE")"
    printf 'INSTALLER_PROFILE_CODEX_ONLY_ENABLE=%s\n' "$(installer_shell_quote "$INSTALLER_PROFILE_CODEX_ONLY_ENABLE")"
    printf 'INSTALLER_PROFILE_WHISPER_ENABLE=%s\n' "$(installer_shell_quote "$INSTALLER_PROFILE_WHISPER_ENABLE")"
    printf 'INSTALLER_PROFILE_LLAMA_ENABLE=%s\n' "$(installer_shell_quote "$INSTALLER_PROFILE_LLAMA_ENABLE")"
    printf 'INSTALLER_PROFILE_PARTMAN_CEILING_ENABLE=%s\n' "$(installer_shell_quote "$INSTALLER_PROFILE_PARTMAN_CEILING_ENABLE")"
    printf 'INSTALLER_PROFILE_PARTMAN_CEILING_MB=%s\n' "$(installer_shell_quote "$INSTALLER_PROFILE_PARTMAN_CEILING_MB")"
    printf 'INSTALLER_PROFILE_PARTMAN_REUSE_ENABLE=%s\n' "$(installer_shell_quote "$INSTALLER_PROFILE_PARTMAN_REUSE_ENABLE")"
    printf 'INSTALLER_PROFILE_PARTMAN_REUSE_START=%s\n' "$(installer_shell_quote "$INSTALLER_PROFILE_PARTMAN_REUSE_START")"
    printf 'INSTALLER_HOST_FAMILY=%s\n' "$(installer_shell_quote "${INSTALLER_HOST_FAMILY:-}")"
    printf 'INSTALLER_HOOK_FAMILY=%s\n' "$(installer_shell_quote "${INSTALLER_HOOK_FAMILY:-}")"
    printf 'INSTALLER_HOST_PROFILE_ENV_DIR=%s\n' "$(installer_shell_quote "${INSTALLER_HOST_PROFILE_ENV_DIR:-}")"
    printf 'INSTALLER_HOST_PROFILE_ENV_NAME=%s\n' "$(installer_shell_quote "${INSTALLER_HOST_PROFILE_ENV_NAME:-}")"
    printf 'INSTALLER_STORAGE_HOST_PROFILE_PREFIX=%s\n' "$(installer_shell_quote "${INSTALLER_STORAGE_HOST_PROFILE_PREFIX:-}")"
    printf 'INSTALLER_INSTALL_DISK_CANDIDATES_DEFAULT=%s\n' "$(installer_shell_quote "${INSTALLER_INSTALL_DISK_CANDIDATES_DEFAULT:-}")"
    printf 'INSTALLER_DEFAULT_INSTALL_DISK=%s\n' "$(installer_shell_quote "${INSTALLER_DEFAULT_INSTALL_DISK:-}")"
    while IFS= read -r group_name || [ -n "$group_name" ]; do
      [ -n "$group_name" ] || continue
      context_var=$(installer_group_context_var "$group_name")
      class_name=$(installer_group_selected_class_value "$group_name")
      [ -n "$class_name" ] || continue
      printf '%s=%s\n' "$context_var" "$(installer_shell_quote "$class_name")"
    done <<EOF
$(installer_selected_group_names 2>/dev/null || true)
EOF
  } >"$context_env"
  chmod 0600 "$context_env"
  printf '%s\n' "$INSTALLER_HOST_PROFILE"
}

installer_load_context() {
  context_env=$(installer_context_env_path)
  [ -r "$context_env" ] || installer_fatal "context env is missing: ${context_env}"
  # shellcheck disable=SC1090
  . "$context_env"
}

installer_context_has_selected_class_state() {
  [ -n "${INSTALLER_SELECTED_GROUPS:-}" ] || return 1
  [ -n "${INSTALLER_SELECTED_CLASSES:-}" ] || return 1
  [ -n "${INSTALLER_SELECTED_CLASS_REFS:-}" ] || return 1
  [ -n "${INSTALLER_ROLE_IDS:-}" ] || return 1
  [ -n "${INSTALLER_HOST_VARIANT:-}" ] || return 1
  [ -n "${INSTALLER_HOST_PROFILE:-}" ] || return 1
  [ -n "${INSTALLER_HOST_FAMILY:-}" ] || return 1
  [ -n "${INSTALLER_HOOK_FAMILY:-}" ] || return 1
  [ -n "${INSTALLER_HOST_PROFILE_ENV_DIR:-}" ] || return 1
  [ -n "${INSTALLER_HOST_PROFILE_ENV_NAME:-}" ] || return 1
  [ -n "${INSTALLER_STORAGE_HOST_PROFILE_PREFIX:-}" ] || return 1
  [ -n "${INSTALLER_INSTALL_DISK_CANDIDATES_DEFAULT:-}" ] || return 1
  [ -n "${INSTALLER_DEFAULT_INSTALL_DISK:-}" ] || return 1

  for installer_context_group in $INSTALLER_SELECTED_GROUPS; do
    installer_context_value=$(installer_group_selected_class_value "$installer_context_group" 2>/dev/null || true)
    [ -n "$installer_context_value" ] || return 1
  done

  while IFS= read -r installer_context_group || [ -n "$installer_context_group" ]; do
    [ -n "$installer_context_group" ] || continue
    case "$(installer_group_required_status "$installer_context_group")" in
      required)
        installer_context_value=$(installer_group_selected_class_value "$installer_context_group" 2>/dev/null || true)
        [ -n "$installer_context_value" ] || return 1
        ;;
    esac
  done <<EOF
$(installer_group_names)
EOF

  return 0
}

installer_ensure_context_loaded() {
  seed_base=${1:-}

  installer_load_context_if_present || true
  if installer_context_has_selected_class_state; then
    return 0
  fi

  resolved_seed_base=$(installer_seed_base "$seed_base")
  installer_warn "installer class context is missing or incomplete; regenerating from ${resolved_seed_base}"
  installer_write_context "$resolved_seed_base" >/dev/null
  installer_load_context
}

installer_prepare_context() {
  seed_base=$(installer_seed_base "${1:-}")
  installer_write_context "$seed_base" >/dev/null
  installer_load_context
}

# Flat profile storage; canonical class identifiers are validated by the resolver.
installer_profile_env_path() {
  installer_validate_profile_component "profile family" "$1"
  installer_validate_profile_component "profile name" "$2"
  case "$1" in
    desktop) installer_repo_asset_path DIR_HOSTS_PROFILES_DESKTOP "$2.env" ;;
    server) installer_repo_asset_path DIR_HOSTS_PROFILES_SERVER "$2.env" ;;
    *) installer_fatal "unsupported profile family: $1" ;;
  esac
}

# Hardware selection is separate from physical payload storage. Unknown optional
# assets return a non-existent path; their existing FILE_* gate still controls
# whether staging is attempted. Required assets fail through the fetch API.
installer_hardware_asset_path() (
  group=$1; class=$2; leaf=$3
  installer_validate_profile_component "hardware group" "$group"
  installer_validate_profile_component "hardware class" "$class"
  installer_validate_relative_seed_path "$leaf"
  manifest=$(installer_class_metadata_read_path "$(installer_repo_file_value catalog/target-assets.tsv)")
  selected=$(awk -F '\t' -v g="$group" -v c="$class" -v p="$leaf" '$1==g && $2==c && $3==p {print $4; exit}' "$manifest")
  if [ -z "$selected" ]; then
    printf '%s\n' "${DIR_HOOKS_TARGET}/.unavailable/$group/$class/$leaf"
  else
    installer_repo_asset_path DIR_HOOKS_TARGET "$selected"
  fi
)

installer_load_source_library() {
  command -v source_fetch >/dev/null 2>&1 && return 0
  for source_library in "${INSTALLER_SOURCE_LIBRARY:-}" \
      "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/bootstrap/source.sh" \
      "${INSTALLER_SOURCE_ROOT:-/nonexistent}/${DIR_SCRIPTS_COMMON}/source.sh" \
      "${1:-/nonexistent}/${DIR_SCRIPTS_COMMON}/source.sh"; do
    [ -n "$source_library" ] && [ -s "$source_library" ] || continue
    # shellcheck disable=SC1090
    . "$source_library"
    return 0
  done
  installer_fatal 'repository transport is missing; start with the generated preseed.cfg'
}

# Explicit optional/cuda-legacy selection authorizes this single archive's
# authentication/freshness exception. SHA-1 signatures (including certificate
# self-signatures) can be rejected by modern APT. Keep the approved archive key
# URL fixed and stage it for APT, without a separate key-identity comparison.
# Never move these options into apt.conf or a global crypto policy. Normal CUDA
# and all other repositories keep their own policy.
installer_cuda_repository_url() (
  set -eu
  repository=${CUDA_LEGACY_REPOSITORY_URL:-}
  [ -n "$repository" ] || {
    installer_fatal 'CUDA_LEGACY_REPOSITORY_URL is missing from the shared host profile policy'
    exit 1
  }
  case "$repository" in
    https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/) ;;
    *)
      installer_fatal 'CUDA_LEGACY_REPOSITORY_URL must be the approved Debian 12 NVIDIA CUDA archive URL'
      exit 1
      ;;
  esac
  printf '%s\n' "$repository"
)

installer_cuda_repository_key_url() (
  set -eu
  key_url=${CUDA_LEGACY_REPOSITORY_KEY:-}
  case "$key_url" in
    https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/3bf863cc.pub) ;;
    *) installer_fatal 'CUDA_LEGACY_REPOSITORY_KEY must be the approved NVIDIA CUDA archive key URL'; exit 1 ;;
  esac
  printf '%s\n' "$key_url"
)

installer_cuda_runtime_paths() (
  set -eu
  target=${INSTALLER_TARGET_DIR:-${TARGET_ROOT:-}}
  [ -n "$target" ] || {
    installer_fatal 'CUDA target root is unavailable; load the installer di.env contract first'
    exit 1
  }
  case "$target" in
    /*) ;;
    *) installer_fatal "CUDA target root must be absolute: ${target}"; exit 1 ;;
  esac
  for path_value in \
    "${DIR_APT:-}" \
    "${DIR_APT_SOURCES_LIST_D:-}" \
    "${DIR_VAR:-}" \
    "${DIR_VAR_CACHE:-}" \
    "${DIR_TMP:-}"; do
    case "$path_value" in
      /*) ;;
      *) installer_fatal "CUDA runtime path contract contains a non-absolute path: ${path_value:-unset}"; exit 1 ;;
    esac
    case "/${path_value#/}/" in
      *'/../'*|*'/./'*|*'//'*) installer_fatal "CUDA runtime path contract contains an unsafe path: ${path_value}"; exit 1 ;;
    esac
  done
)

installer_cuda_source_line() (
  set -eu
  repository=$1; suite=$2; components=${3:-}
  expected_repository=$(installer_cuda_repository_url)
  keyring=${FILE_APT_CUDA_LEGACY_ARCHIVE_KEY:-}
  case "$keyring" in
    /*) ;;
    *) installer_fatal 'FILE_APT_CUDA_LEGACY_ARCHIVE_KEY must be an absolute target keyring path'; exit 1 ;;
  esac
  case "/${keyring#/}/" in
    *'/../'*|*'/./'*|*'//'*) installer_fatal 'FILE_APT_CUDA_LEGACY_ARCHIVE_KEY contains an unsafe path'; exit 1 ;;
  esac
  [ "$repository" = "$expected_repository" ] || {
    installer_fatal 'legacy CUDA repository does not match CUDA_LEGACY_REPOSITORY_URL'; exit 1;
  }
  [ "$suite" = / ] && [ -z "$components" ] || {
    installer_fatal 'legacy CUDA must use a flat archive with no components'; exit 1;
  }
  case "${4:-installer}" in
    installer)
      printf 'deb [arch=amd64 signed-by=%s trusted=yes allow-insecure=yes allow-weak=yes allow-downgrade-to-insecure=yes check-valid-until=no check-date=no pdiffs=no lang=en] %s /\n' "$keyring" "$repository"
      ;;
    persistent)
      # The installer-only legacy exception never becomes an upgrade policy.
      printf 'deb [arch=amd64 signed-by=%s pdiffs=no lang=en] %s /\n' "$keyring" "$repository"
      ;;
    *) installer_fatal 'unsupported legacy NVIDIA source lifetime'; exit 1 ;;
  esac
)

installer_cuda_stage_target_key() (
  set -eu
  umask 077
  installer_cuda_runtime_paths
  target=${INSTALLER_TARGET_DIR:-${TARGET_ROOT}}
  case "$target" in
    /) ;;
    /*) target=${target%/} ;;
    *) installer_fatal "CUDA target root must be absolute: ${target}"; exit 1 ;;
  esac
  key_url=$(installer_cuda_repository_key_url)
  key_base=${key_url%/*}
  key_name=${key_url##*/}
  [ -n "$key_base" ] && [ -n "$key_name" ] || {
    installer_fatal 'CUDA legacy key URL has no filename'; exit 1;
  }
  key_path="$target${FILE_APT_CUDA_LEGACY_ARCHIVE_KEY}"
  case "$key_path" in
    /*) ;;
    *) installer_fatal 'CUDA legacy key path must be absolute'; exit 1 ;;
  esac
  case "/${key_path#/}/" in
    *'/../'*|*'/./'*|*'//'*) installer_fatal 'CUDA legacy key path contains an unsafe path'; exit 1 ;;
  esac
  install -d -m 0755 "${key_path%/*}"
  installer_fetch_url "$key_base" "$key_name" "$key_path" 0644
  [ -s "$key_path" ] && [ ! -L "$key_path" ] || {
    installer_fatal "CUDA legacy key was not staged: ${key_path}"; exit 1;
  }
)

installer_cuda_stage_target_source() (
  set -eu
  umask 077
  installer_cuda_runtime_paths
  # Explicit statuses also protect callers that invoke this function in an
  # if/|| list, where shells disable errexit even inside a function's subshell.
  repository=$1
  line=$(installer_cuda_source_line "$@") || exit "$?"
  target=${INSTALLER_TARGET_DIR:-${TARGET_ROOT}}
  case "$target" in
    /) ;;
    /*) target=${target%/} ;;
    *) installer_fatal "CUDA target root must be absolute: ${target}"; exit 1 ;;
  esac
  source_dir="$target${DIR_APT}"
  source="$source_dir/sources.list"
  installer_apt_safe_path "$source" || exit "$?"
  install -d -m 0755 "$source_dir" || exit "$?"
  work=$(mktemp "$source_dir/.cuda-legacy.XXXXXX") || exit "$?"
  cleanup_cuda_source() {
    original=$?
    trap - 0 HUP INT TERM
    if rm -f "$work"; then
      :
    else
      cleanup=$?
      [ "$original" -ne 0 ] || original=$cleanup
    fi
    exit "$original"
  }
  trap cleanup_cuda_source 0
  trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
  if [ -f "$source" ]; then
    [ "$(installer_metadata_value "$source" links)" = 1 ] || exit 1
    awk -v repository="$repository" 'index($0, repository) == 0 {print}' "$source" >"$work" || exit "$?"
  fi
  printf '%s\n' "$line" >>"$work" || exit "$?"
  chmod 0644 "$work" || exit "$?"
  mv -f "$work" "$source" || exit "$?"
)

installer_cuda_remove_target_source() (
  set -eu
  umask 077
  installer_cuda_runtime_paths || exit "$?"
  repository=$(installer_cuda_repository_url) || exit "$?"
  origin=${repository#https://}
  origin=${origin%/}
  target=${INSTALLER_TARGET_DIR:-${TARGET_ROOT}}
  case "$target" in
    /) installer_fatal 'refusing to retire CUDA sources in the installer root'; exit 1 ;;
    /*) target=${target%/} ;;
    *) installer_fatal "CUDA target root must be absolute: ${target}"; exit 1 ;;
  esac
  source_dir="$target${DIR_APT}"
  parts_dir="$target${DIR_APT_SOURCES_LIST_D}"
  installer_apt_safe_path "$source_dir" || exit "$?"
  installer_apt_safe_path "$parts_dir" || exit "$?"
  work=
  marker=
  cleanup_cuda_source() {
    original=$?
    trap - 0 HUP INT TERM
    for artifact in "$work" "$marker"; do
      [ -n "$artifact" ] || continue
      if rm -f "$artifact"; then :; else
        cleanup=$?
        [ "$original" -ne 0 ] || original=$cleanup
      fi
    done
    exit "$original"
  }
  trap cleanup_cuda_source 0
  trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
  # apt-setup, modernize-sources and interrupted source suspension can leave
  # the same archive in different files. Retire active entries and their source
  # backups together, independently of the current driver/toolkit selection.
  for source in "$source_dir/sources.list" "$source_dir/sources.list".* "$parts_dir/"*; do
    # sources.list.d is the canonical directory, not a sources.list backup.
    [ "$source" != "$parts_dir" ] || continue
    [ -e "$source" ] || [ -L "$source" ] || continue
    case "${source##*/}" in
      *.sources) deb822=1 ;;
      *.list) deb822=0 ;;
      *.sources.*) deb822=1 ;;
      *.list.*|cuda-legacy-temp.*) deb822=0 ;;
      *) continue ;;
    esac
    installer_apt_safe_path "$source" || exit "$?"
    [ -f "$source" ] && [ "$(installer_metadata_value "$source" links)" = 1 ] || exit 1
    if grep -Fq "$origin" "$source"; then :; else
      source_status=$?
      [ "$source_status" -eq 1 ] && continue
      exit "$source_status"
    fi
    work=$(mktemp "${source%/*}/.cuda-retire.XXXXXX") || exit "$?"
    marker=$(mktemp "${source%/*}/.cuda-retire-state.XXXXXX") || exit "$?"
    awk -v origin="$origin" -v deb822="$deb822" -v marker="$marker" '
      function legacy(uri) {
        sub(/\r$/, "", uri)
        if (uri !~ /^https?:\/\//) return 0
        sub(/^https?:\/\//, "", uri); sub(/\/$/, "", uri)
        return uri == origin
      }
      function flush(    count,i,value,end,tokens,j,kept,removed,drop,stanza) {
        count=stanza_count; stanza_count=0; drop=0
        if (!count) return
        for (i=1; i<=count; i++) {
          if (tolower(lines[i]) !~ /^uris[ \t]*:/) continue
          value=lines[i]; sub(/^[^:]*:[ \t]*/, "", value)
          end=i
          while (end<count && lines[end+1] ~ /^[ \t#]/) {
            end++
            if (lines[end] !~ /^[ \t]*#/) value=value " " lines[end]
          }
          tokens=split(value, urls, /[ \t\r\n]+/); kept=""; removed=0
          for (j=1; j<=tokens; j++) {
            if (legacy(urls[j])) removed=1
            else if (urls[j]!="") kept=kept (kept=="" ? "" : " ") urls[j]
          }
          if (removed) {
            changed=1
            if (kept=="") { drop=1; break }
            lines[i]="URIs: " kept
            for (j=i+1; j<=end; j++) lines[j]=""
          }
          i=end
        }
        if (!drop) {
          stanza=""
          for (i=1; i<=count; i++) if (lines[i]!="") stanza=stanza (stanza=="" ? "" : "\n") lines[i]
          print stanza; print ""
        }
      }
      !deb822 {
        for (i=1; i<=NF; i++) if (legacy($i)) { changed=1; next }
        print; next
      }
      {
        sub(/\r$/, "", $0)
        if ($0 ~ /^[ \t]*$/) flush()
        else lines[++stanza_count]=$0
      }
      # Do not override awk I/O errors with an END exit status. The private
      # marker distinguishes unchanged input from a successful rewrite.
      END { if (deb822) flush(); if (changed) print "changed" >marker }
    ' "$source" >"$work" || exit "$?"
    if [ -s "$marker" ]; then
      rm -f "$marker" || exit "$?"
      marker=
      source_mode=$(installer_metadata_value "$source" mode) || exit "$?"
      chmod "$source_mode" "$work" || exit "$?"
      mv -fT -- "$work" "$source" || exit "$?"
    else
      rm -f "$marker" "$work" || exit "$?"
      marker=
    fi
    work=
  done
)

installer_cuda_refresh_target_apt() (
  set -eu
  installer_cuda_runtime_paths
  target=${INSTALLER_TARGET_DIR:-${TARGET_ROOT}}
  case "$target" in
    /) ;;
    /*) target=${target%/} ;;
    *) installer_fatal "CUDA target root must be absolute: ${target}"; exit 1 ;;
  esac
  command -v installer_apt_strip_cdrom >/dev/null 2>&1 || {
    installer_fatal 'APT source cleanup helper is unavailable before the CUDA refresh'
    exit 1
  }
  # apt-setup may recreate the installer CD-ROM source during base-install.
  # Remove it at the same boundary as the scoped refresh so pkgsel does not
  # inherit a stale media source or its missing-Release warning.
  installer_apt_strip_cdrom "$target" || exit "$?"
  source_dir="$target${DIR_APT}"
  installer_apt_safe_path "$source_dir" || exit "$?"
  install -d -m 0755 "$source_dir" || exit "$?"
  repository=$(installer_cuda_repository_url)
  line=$(installer_cuda_source_line "$repository" / "") || exit "$?"
  refresh_source=$(mktemp "$source_dir/.cuda-legacy-refresh.XXXXXX") || exit "$?"
  refresh_source_path=${refresh_source#"$target"}
  cleanup_cuda_refresh() {
    status=$?
    trap - 0 HUP INT TERM
    rm -f "$refresh_source"
    exit "$status"
  }
  trap cleanup_cuda_refresh 0 HUP INT TERM
  printf '%s\n' "$line" >"$refresh_source" || exit "$?"
  chmod 0644 "$refresh_source" || exit "$?"
  installer_warn 'CUDA-legacy ONLY: archive authentication and metadata-date checks are disabled by explicit class selection; HTTPS and package checksums remain enabled'
  # Keep APT's insecure-repository gates on this one source-list invocation.
  # The per-source flags above describe the repository, while these options
  # override fail-closed defaults in the target APT configuration. With
  # the main configuration and source parts disabled, no ordinary
  # Debian/vendor source receives them and the command cannot silently fall
  # back to the target's regular source list.
  # Disabling parts also bypasses 25no-pdiffs: repeat its acquisition controls
  # explicitly for this isolated source-list refresh.
  run_in_target 'refresh explicitly trusted legacy CUDA metadata' \
    env -u APT_SEQUOIA_CRYPTO_POLICY -u SEQUOIA_CRYPTO_POLICY \
    LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get \
    "-o Dir::Etc::main=/dev/null" -o Dir::Etc::parts=- \
    "-o Dir::Etc::sourcelist=${refresh_source_path}" \
    -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0 \
    -o Acquire::AllowInsecureRepositories=true \
    -o Acquire::AllowWeakRepositories=true \
    -o Acquire::AllowDowngradeToInsecureRepositories=true \
    -o APT::Get::AllowUnauthenticated=true \
    -o Acquire::PDiffs=false -o Acquire::Languages=en \
    -o Acquire::IndexTargets::deb::Translations::DefaultEnabled=true \
    -o APT::Update::Error-Mode=any \
    -o Acquire::Retries=3 -o Acquire::http::Timeout=45 \
    -o Acquire::https::Timeout=45 -o DPkg::Use-Pty=0 update
)
