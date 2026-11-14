#!/bin/sh
# Sourced installer module; edit this file directly.

installer_profile_plan_policy() (
  set -eu
  policy_seed=$1
  if command -v installer_operation_context_repo >/dev/null 2>&1; then
    installer_operation_context_repo FILE_COMMON_MOD_PROFILES 8 profile_policy
  fi
  policy_file=$(mktemp "$(installer_runtime_state_dir)/profile-policy.XXXXXX") || exit "$?"
  trap 'rm -f "$policy_file"' 0
  trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
  installer_fetch_host_env "$policy_seed" "$INSTALLER_HOST_PROFILE" "$policy_file" 0600 || exit "$?"
  if installer_load_data_env "$policy_file"; then
    :
  else
    policy_data_status=$?
    installer_fatal_status "$policy_data_status" 'invalid compiled profile policy'
  fi
  policy_codex_only=false
  if [ "$INSTALLER_HOST_VARIANT" = server ]; then
    policy_codex_only=${CODEX_ONLY_ENABLE:?explicit server Codex boolean required}
    case "$policy_codex_only" in true|false) ;; *) installer_fatal 'invalid server Codex enable policy' ;; esac
  fi
  case "${SSH_SERVER_ENABLE:-}" in true|false) ;; *) installer_fatal 'invalid SSH enable policy' ;; esac
  policy_port=${SSH_SERVER_PORT:?explicit SSH port required}
  case "$policy_port" in ''|*[!0-9]*) installer_fatal 'invalid SSH port' ;; esac
  [ "$policy_port" -ge 30000 ] && [ "$policy_port" -le 40000 ] || installer_fatal 'SSH port must be 30000..40000'
  case "${SNAPSHOTS_POLICY:-}" in timeshift-btrfs|none) ;; *) installer_fatal 'invalid profile snapshot policy' ;; esac
  case "${TIMESHIFT_ENABLE:-}:$SNAPSHOTS_POLICY" in
    true:timeshift-btrfs|false:none) ;;
    *) installer_fatal 'Timeshift boolean and derived snapshot policy disagree' ;;
  esac
  for policy_boolean in "${CRYPTO_LUKS2_ROOT:-}" "${CRYPTO_LUKS2_HOME:-}" "${WIFI_ENABLE:-}" "${IPV6_ENABLE:-}"; do
    case "$policy_boolean" in true|false) ;; *) installer_fatal 'crypto and Wi-Fi profile values require explicit true/false' ;; esac
  done
  if [ "$INSTALLER_HOST_VARIANT" = server ]; then
    for policy_boolean in "${WHISPER_ENABLE:-}" "${LLAMA_ENABLE:-}"; do
      case "$policy_boolean" in true|false) ;; *) installer_fatal 'server AI profile values require explicit true/false' ;; esac
    done
  else
    WHISPER_ENABLE=false
    LLAMA_ENABLE=false
  fi
  case "${MANAGED_NETWORK_PRIMARY_IFACE:-}" in
    "${MANAGED_NETWORK_ETHERNET_IFACE:-eth0}"|"${MANAGED_NETWORK_WIFI_IFACE:-wifi0}") ;;
    *) installer_fatal 'primary interface differs from the managed Ethernet/Wi-Fi pair' ;;
  esac
  printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "${SSH_SERVER_ENABLE:-}" "$policy_port" "$SNAPSHOTS_POLICY" \
    "$CRYPTO_LUKS2_ROOT" "$CRYPTO_LUKS2_HOME" "$WIFI_ENABLE" "$MANAGED_NETWORK_PRIMARY_IFACE" "$IPV6_ENABLE" \
    "$policy_codex_only" "$WHISPER_ENABLE" "$LLAMA_ENABLE"
)

installer_profile_shared_family() {
  profile_name=$1

  if [ -n "${INSTALLER_HOST_PROFILE:-}" ] && [ "$profile_name" = "${INSTALLER_HOST_PROFILE}" ] && [ -n "${INSTALLER_HOST_FAMILY:-}" ]; then
    printf '%s\n' "${INSTALLER_HOST_FAMILY}"
    return 0
  fi

  case "$profile_name" in
    *-*) printf '%s\n' "${profile_name%%-*}" ;;
    *) return 1 ;;
  esac
}

installer_profile_shared_families() {
  profile_name=$1
  installer_profile_shared_family "$profile_name"
}

installer_profile_variant() {
  profile_name=$1

  case "$profile_name" in
    *-*) printf '%s\n' "${profile_name#*-}" ;;
    *) return 1 ;;
  esac
}

installer_validate_profile_component() {
  component_label=$1
  component_value=$2

  case "$component_value" in
    ''|*[!A-Za-z0-9_-]*)
      installer_fatal "${component_label} contains an invalid profile path component: ${component_value:-unset}"
      ;;
  esac
}

installer_profile_layout_family() {
  profile_name=$1
  profile_family=${2:-}

  if [ -z "$profile_family" ]; then
    profile_family=$(installer_profile_shared_family "$profile_name" 2>/dev/null || true)
  fi

  if [ -n "${INSTALLER_HOST_PROFILE:-}" ] &&
    [ "$profile_name" = "${INSTALLER_HOST_PROFILE}" ] &&
    [ -n "${INSTALLER_HOOK_FAMILY:-}" ]; then
    profile_family=$INSTALLER_HOOK_FAMILY
  fi

  case "$profile_family" in
    btrfs|vm) printf 'btrfs\n' ;;
    f2fs) printf 'f2fs\n' ;;
    *) return 1 ;;
  esac
}

# Compiled profiles are literal, single-quoted assignments emitted by the
# reviewed data serializer. Load them as data, without source or eval.
installer_load_data_env() {
  set +x
  set +v
  installer_data_had_context=0
  installer_data_previous_source=${INSTALLER_FAILURE_SOURCE:-}
  installer_data_previous_line=${INSTALLER_FAILURE_LINE:-}
  installer_data_previous_operation=${INSTALLER_FAILURE_OPERATION:-}
  if [ "${INSTALLER_FAILURE_SOURCE+x}" = x ] ||
     [ "${INSTALLER_FAILURE_LINE+x}" = x ] ||
     [ "${INSTALLER_FAILURE_OPERATION+x}" = x ]; then
    installer_data_had_context=1
  fi
  if command -v installer_operation_context_repo >/dev/null 2>&1; then
    installer_operation_context_repo FILE_COMMON_MOD_PROFILES 129 load_data_env
  fi
  installer_data_path=$1
  [ -f "$installer_data_path" ] && [ ! -L "$installer_data_path" ] || return 1
  installer_data_size=$(wc -c <"$installer_data_path") || return 1
  [ "$installer_data_size" -le 1048576 ] || return 1
  if installer_data_parser=$(bootstrap_parser_asset_path "$(bootstrap_repo_file_value FILE_COMMON_CREDENTIAL_DATA)"); then
    :
  else
    installer_data_parser_status=$?
    installer_error "compiled data parser asset could not be resolved from the authenticated payload (status=${installer_data_parser_status})"
    return "$installer_data_parser_status"
  fi
  # Validate the entire bounded snapshot before changing any caller variable.
  # No source/eval, process environment expansion or shell expression parsing.
  if installer_data_records=$(LC_ALL=C awk -v mode=snapshot -f "$installer_data_parser" "$installer_data_path"); then
    :
  else
    installer_data_parser_status=$?
    installer_error "compiled data snapshot was rejected by the restricted data parser (status=${installer_data_parser_status}; path=${installer_data_path})"
    return "$installer_data_parser_status"
  fi
  installer_data_complete=false
  while IFS= read -r installer_data_key; do
    if [ "$installer_data_key" = __INSTALLER_DATA_END__ ]; then
      installer_data_complete=true
      break
    fi
    IFS= read -r installer_data_value || return 1
    IFS= read -r "$installer_data_key" <<EOF
$installer_data_value
EOF
  done <<EOF
$installer_data_records
EOF
  if [ "$installer_data_complete" != true ]; then
    installer_error 'compiled data snapshot ended without its completion marker'
    return 1
  fi
  unset installer_data_records installer_data_value

  # A successful data load must not leave every later failure attributed to
  # this parser. Preserve the caller's operation context; parser failures
  # return before this restoration and retain the precise parser location.
  if [ "$installer_data_had_context" -eq 1 ] &&
     command -v installer_operation_context >/dev/null 2>&1; then
    installer_operation_context "$installer_data_previous_source" \
      "$installer_data_previous_line" "$installer_data_previous_operation"
  elif [ "$installer_data_had_context" -eq 0 ]; then
    unset INSTALLER_FAILURE_SOURCE INSTALLER_FAILURE_LINE INSTALLER_FAILURE_OPERATION
  fi
  unset installer_data_had_context installer_data_previous_source \
    installer_data_previous_line installer_data_previous_operation

}

installer_fetch_host_env() {
  host_fetch_had_context=0
  host_fetch_previous_source=${INSTALLER_FAILURE_SOURCE:-}
  host_fetch_previous_line=${INSTALLER_FAILURE_LINE:-}
  host_fetch_previous_operation=${INSTALLER_FAILURE_OPERATION:-}
  if [ "${INSTALLER_FAILURE_SOURCE+x}" = x ] ||
     [ "${INSTALLER_FAILURE_LINE+x}" = x ] ||
     [ "${INSTALLER_FAILURE_OPERATION+x}" = x ]; then
    host_fetch_had_context=1
  fi
  if command -v installer_operation_context_repo >/dev/null 2>&1; then
    installer_operation_context_repo FILE_COMMON_MOD_PROFILES 196 fetch_host_env
  fi
  host_seed_base=$1
  host_profile=$2
  host_dest_path=$3
  host_mode=${4:-0600}
  case "${INSTALLER_SUITE:-}" in forky|trixie) ;; *) installer_fatal 'suite identity is missing' ;; esac
  host_family=${INSTALLER_HOST_VARIANT:?validated role family is required}
  host_name=${INSTALLER_HOST_PROFILE_ENV_NAME:?validated profile is required}
  installer_validate_profile_component 'profile family' "$host_family"
  installer_validate_profile_component 'profile name' "$host_name"
  host_source=$(installer_repo_asset_path DIR_CATALOG_COMPILED \
    "$INSTALLER_SUITE/profiles/$host_family/$host_name.env") || return "$?"
  installer_fetch_seed_path "$host_seed_base" "$host_source" "$host_dest_path" "$host_mode" || return "$?"
  # Validation occurs in a subshell so a probe cannot change caller policy,
  # while preserving the parser's status for the phase supervisor.
  if (installer_load_data_env "$host_dest_path"); then
    :
  else
    host_data_status=$?
    installer_fatal_status "$host_data_status" "invalid compiled profile data for ${host_profile}"
  fi
  # Acquisition/validation failures retain their own context. Successful
  # acquisition must not label later target commands as fetch_host_env errors.
  if [ "$host_fetch_had_context" -eq 1 ] &&
     command -v installer_operation_context >/dev/null 2>&1; then
    installer_operation_context "$host_fetch_previous_source" \
      "$host_fetch_previous_line" "$host_fetch_previous_operation"
  elif [ "$host_fetch_had_context" -eq 0 ]; then
    unset INSTALLER_FAILURE_SOURCE INSTALLER_FAILURE_LINE INSTALLER_FAILURE_OPERATION
  fi
  unset host_fetch_had_context host_fetch_previous_source \
    host_fetch_previous_line host_fetch_previous_operation
}

installer_fetch_account_env() {
  account_seed_base=$1
  account_dest_path=$2
  account_mode=${3:-0600}

  # Account policy is a generated restricted-data view for this exact suite
  # and host profile. The authored account.env is never fetched as shell code.
  account_family=${INSTALLER_HOST_VARIANT:?validated role family is required}
  account_profile=${INSTALLER_HOST_PROFILE_ENV_NAME:?validated profile is required}
  installer_validate_profile_component 'account profile family' "$account_family"
  installer_validate_profile_component 'account profile name' "$account_profile"
  case "${INSTALLER_SUITE:-}" in forky|trixie) ;; *) installer_fatal 'account suite identity is missing' ;; esac
  account_source=$(installer_repo_asset_path DIR_CATALOG_COMPILED \
    "$INSTALLER_SUITE/profiles/$account_family/$account_profile.account.env") || return "$?"
  installer_fetch_seed_path "$account_seed_base" "$account_source" "$account_dest_path" "$account_mode" || return "$?"
  if (installer_load_data_env "$account_dest_path"); then
    :
  else
    account_data_status=$?
    installer_fatal_status "$account_data_status" 'invalid compiled account policy data'
  fi

}

# Public account policy has no resolved human identity. Publish one private
# snapshot for pre-pkgsel and before late providers enter their separate shells.
# Keep credential values and runtime helper scratch variables in this subshell.
installer_prepare_late_account_env() (
  set -eu
  set +x
  set +v
  umask 077
  late_account_seed=$1
  late_account_destination=$2
  installer_operation_context_repo FILE_COMMON_MOD_PROFILES 265 prepare_late_account_env
  installer_apt_safe_path "$late_account_destination" ||
    installer_fatal 'unsafe resolved account snapshot destination'
  if [ -e "$late_account_destination" ] || [ -L "$late_account_destination" ]; then
    [ -f "$late_account_destination" ] && [ ! -L "$late_account_destination" ] ||
      installer_fatal 'resolved account snapshot destination is not a regular file'
  fi
  late_account_parent=${late_account_destination%/*}
  install -d -m 0700 "$late_account_parent" || exit "$?"
  late_account_lock="${late_account_parent}/.account-env.lock"
  mkdir -m 0700 "$late_account_lock" ||
    installer_fatal 'another publisher owns the resolved account snapshot'
  late_account_work=
  late_account_cleanup() {
    late_account_status=$?
    trap - 0 HUP INT TERM
    if [ -n "$late_account_work" ]; then
      if ! { rm -f "$late_account_work/profile.env" "$late_account_work/policy.env" "$late_account_work/account.env" &&
             rmdir "$late_account_work"; }; then
        installer_error "account snapshot cleanup failed; private evidence and lock retained: ${late_account_work}"
        exit 125
      fi
    fi
    rmdir "$late_account_lock" || late_account_status=125
    exit "$late_account_status"
  }
  trap late_account_cleanup 0
  trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
  late_account_work=$(mktemp -d "${late_account_parent}/.account-env.XXXXXX") || exit "$?"
  # Standalone pre-pkgsel/late callers need not have loaded the target roots.
  # Resolve them from this exact compiled profile, never an inherited DIR_HOME.
  installer_fetch_host_env "$late_account_seed" "${INSTALLER_HOST_PROFILE:?validated host profile is required}" \
    "$late_account_work/profile.env" 0600 || exit "$?"
  installer_load_data_env "$late_account_work/profile.env" || exit "$?"
  installer_fetch_account_env "$late_account_seed" "$late_account_work/policy.env" 0600 || exit "$?"
  installer_load_data_env "$late_account_work/policy.env" || exit "$?"
  for late_account_selector in FILE_RUNTIME_COMMON FILE_RUNTIME_ACCOUNT; do
    late_account_module=$(installer_repo_file_value "$late_account_selector") || exit "$?"
    if bootstrap_source_module "$late_account_module"; then
      :
    else
      late_account_module_status=$?
      installer_fatal_status "$late_account_module_status" \
        "resolved account runtime could not be loaded: selector=${late_account_selector} source=${late_account_module}"
    fi
  done
  # A parent's cache flag or inherited account must never substitute for the
  # current installer's validated cmdline/protected credential inputs.
  unset RUNTIME_ACCOUNT_CREDENTIALS_READY
  runtime_write_effective_account_env "$late_account_work/account.env" || exit "$?"
  # Validate the whole candidate before replacing a previous complete snapshot.
  (installer_load_data_env "$late_account_work/account.env") || exit "$?"
  installer_apt_safe_path "$late_account_destination" ||
    installer_fatal 'resolved account snapshot ancestry changed before publication'
  if [ -e "$late_account_destination" ] || [ -L "$late_account_destination" ]; then
    [ -f "$late_account_destination" ] && [ ! -L "$late_account_destination" ] ||
      installer_fatal 'resolved account snapshot destination changed before publication'
  fi
  chmod 0600 "$late_account_work/account.env" || exit "$?"
  mv -fT -- "$late_account_work/account.env" "$late_account_destination" || exit "$?"
)
