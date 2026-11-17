#!/bin/sh
# Sourced installer module; edit this file directly.

installer_seed_source_type() {
  case "${1:-}" in
    /*) printf '%s\n' file ;;
    *) printf '%s\n' url ;;
  esac
}

installer_trim_seed_base() {
  seed_base=$1

  while [ "${#seed_base}" -gt 1 ]; do
    case "$seed_base" in
      */) seed_base=${seed_base%/} ;;
      *) break ;;
    esac
  done
  printf '%s\n' "$seed_base"
}

installer_assign_normalized_seed_base() {
  output_var_name=$1
  seed_base=$2
  seed_type=$3

  seed_base=${seed_base%%\?*}
  case "$seed_base" in
    */*.cfg) seed_base=${seed_base%/*} ;;
  esac
  seed_base=$(installer_trim_seed_base "$seed_base")

  case "$seed_type" in
    file)
      case "$seed_base" in
        /*) ;;
        *) installer_fatal "installation file base must be an absolute path: ${seed_base:-unset}" ;;
      esac
      case "$seed_base" in
        *..*|*//*)
          installer_fatal "installation file base contains unsupported traversal: $seed_base"
          ;;
      esac
      ;;
    url)
      [ -n "$seed_base" ] || installer_fatal "installation URL base is empty"
      ;;
    *)
      installer_fatal "unsupported installation source type: $seed_type"
      ;;
  esac

  eval "$output_var_name=\$seed_base"
}

installer_normalize_seed_base() {
  normalized_seed_base=
  installer_assign_normalized_seed_base normalized_seed_base "$1" "$2"
  printf '%s\n' "$normalized_seed_base"
}

installer_persist_seed_source() {
  seed_base=$1
  seed_type=$(installer_seed_source_type "$seed_base")
  seed_url_path=$(installer_bootstrap_seed_url_path)
  seed_file_path=$(installer_bootstrap_seed_file_path)

  install -d -m 0700 "$(installer_runtime_bootstrap_dir)"

  case "$seed_type" in
    file)
      SEED_FILE_BASE=$(installer_normalize_seed_base "$seed_base" file)
      SEED_URL_BASE=
      printf '%s\n' "$SEED_FILE_BASE" >"$seed_file_path"
      rm -f "$seed_url_path"
      ;;
    url)
      SEED_URL_BASE=$(installer_normalize_seed_base "$seed_base" url)
      SEED_FILE_BASE=
      printf '%s\n' "$SEED_URL_BASE" >"$seed_url_path"
      rm -f "$seed_file_path"
      ;;
    *)
      installer_fatal "unsupported installation source type: $seed_type"
      ;;
  esac
}

installer_choose_seed_base_from_pair() {
  url_seed_base=$1
  file_seed_base=$2
  seed_label=$3

  if [ -n "$url_seed_base" ] && [ -n "$file_seed_base" ]; then
    installer_fatal "${seed_label} defines both URL and file seed sources"
  fi
  if [ -n "$url_seed_base" ]; then
    installer_assign_normalized_seed_base INSTALLER_RESOLVED_SEED_BASE "$url_seed_base" url
    return 0
  fi
  if [ -n "$file_seed_base" ]; then
    installer_assign_normalized_seed_base INSTALLER_RESOLVED_SEED_BASE "$file_seed_base" file
    return 0
  fi

  INSTALLER_RESOLVED_SEED_BASE=
  return 1
}

installer_persisted_seed_base() {
  persisted_seed_url_base=
  persisted_seed_file_base=
  persisted_seed_url_path=$(installer_bootstrap_seed_url_path)
  persisted_seed_file_path=$(installer_bootstrap_seed_file_path)

  if [ -f "$persisted_seed_url_path" ]; then
    persisted_seed_url_base=$(cat "$persisted_seed_url_path")
  fi
  if [ -f "$persisted_seed_file_path" ]; then
    persisted_seed_file_base=$(cat "$persisted_seed_file_path")
  fi

  installer_choose_seed_base_from_pair "$persisted_seed_url_base" "$persisted_seed_file_base" "persisted installer state"
}

installer_seed_base() {
  seed_base=${1:-}
  if [ -n "$seed_base" ]; then
    seed_type=$(installer_seed_source_type "$seed_base")
    installer_normalize_seed_base "$seed_base" "$seed_type"
    return 0
  fi
  if [ "${INSTALLER_SEED_BASE_CACHE_READY:-0}" -eq 1 ]; then
    printf '%s\n' "$INSTALLER_SEED_BASE_CACHE"
    return 0
  fi

  if installer_choose_seed_base_from_pair "${SEED_URL_BASE:-}" "${SEED_FILE_BASE:-}" "runtime seed state"; then
    INSTALLER_SEED_BASE_CACHE=$INSTALLER_RESOLVED_SEED_BASE
    INSTALLER_SEED_BASE_CACHE_READY=1
    printf '%s\n' "$INSTALLER_SEED_BASE_CACHE"
    return 0
  fi
  if installer_choose_seed_base_from_pair "${INSTALLER_SEED_URL_BASE:-}" "${INSTALLER_SEED_FILE_BASE:-}" "installer context seed state"; then
    INSTALLER_SEED_BASE_CACHE=$INSTALLER_RESOLVED_SEED_BASE
    INSTALLER_SEED_BASE_CACHE_READY=1
    printf '%s\n' "$INSTALLER_SEED_BASE_CACHE"
    return 0
  fi
  if [ -n "${INSTALLER_SEED_BASE:-}" ]; then
    INSTALLER_SEED_BASE_CACHE=$(installer_normalize_seed_base "${INSTALLER_SEED_BASE}" "$(installer_seed_source_type "${INSTALLER_SEED_BASE}")")
    INSTALLER_SEED_BASE_CACHE_READY=1
    printf '%s\n' "$INSTALLER_SEED_BASE_CACHE"
    return 0
  fi
  if installer_persisted_seed_base; then
    printf '%s\n' "$INSTALLER_RESOLVED_SEED_BASE"
    return 0
  fi
  installer_load_source_library "${INSTALLER_SOURCE_ROOT:-}" || return 1
  source_resolve_seed
  return $?

installer_fatal "installation preseed URL or file path not found in kernel cmdline, installer context, runtime state, or persisted installer state"
}

installer_seed_url_base() {
  installer_seed_base "${1:-}"
}

installer_current_seed_base() {
  installer_seed_base ""
}

installer_validate_relative_seed_path() {
  seed_relative_path=$1

  case "$seed_relative_path" in
    ''|/*|../*|*/..|*../*|*//*)
      installer_fatal "seed source path must stay relative to the seed base: ${seed_relative_path:-unset}"
      ;;
  esac
}

installer_file_safe_token() {
  printf '%s\n' "$(printf '%s' "${1:-seed}" | sed 's/[^A-Za-z0-9._-]/_/g')"
}

installer_repo_env_relpath() {
  printf '%s\n' repo.env
}

installer_repo_env_path() {
  printf '%s/bootstrap/repo.env\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

installer_repo_env_dir_vars() {
  installer_repo_env_vars_path=$1
  sed -n 's/^\(DIR_[A-Z0-9_]*\)=.*/\1/p' "$installer_repo_env_vars_path"
}

installer_repo_env_selector_vars() {
  installer_repo_env_vars_path=$1
  sed -n 's/^\(DIR_[A-Z0-9_]*\|FILE_[A-Z0-9_]*\)=.*/\1/p' "$installer_repo_env_vars_path"
}

installer_validate_repo_dir_value() {
  installer_repo_validate_var=$1
  installer_repo_validate_value=$2

  case "$installer_repo_validate_value" in
    ''|/*|../*|*/..|*../*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@+-]*)
      installer_fatal "${installer_repo_validate_var} must be a safe repository-relative directory path: ${installer_repo_validate_value:-unset}"
      ;;
  esac
}

installer_validate_repo_file_value() {
  installer_repo_validate_file_name=$1
  installer_repo_validate_file_value=$2

  case "$installer_repo_validate_file_value" in
    "${DIR_TARGET_SKEL_VIVALDI:-}/Local State") ;;
    ''|/*|../*|*/..|*../*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@+-]*)
      installer_fatal "${installer_repo_validate_file_name} must be a safe repository-relative file path: ${installer_repo_validate_file_value:-unset}"
      ;;
  esac
}

installer_repo_dir_input_is_var() {
  case "${1:-}" in
    DIR_[ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*)
      case "$1" in
        *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*) return 1 ;;
      esac
      return 0
      ;;
  esac
  return 1
}

installer_loaded_repo_dir_value() {
  installer_loaded_repo_dir_name=${1:-}
  case "$installer_loaded_repo_dir_name" in
    DIR_[A-Z0-9_]*) ;;
    *) return 1 ;;
  esac
  case "$installer_loaded_repo_dir_name" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*) return 1 ;;
  esac

  # repo.env is the source of truth for repository selectors. The variable
  # name has been restricted to the uppercase DIR_* grammar above before this
  # indirect read, so newly added selectors cannot be rejected as an empty
  # value merely because this helper has not been edited in lockstep.
  installer_loaded_repo_dir_result=
  eval "installer_loaded_repo_dir_result=\${$installer_loaded_repo_dir_name:-}"
  printf '%s\n' "$installer_loaded_repo_dir_result"
}

installer_loaded_repo_file_value() {
  installer_loaded_repo_file_name=${1:-}
  case "$installer_loaded_repo_file_name" in
    FILE_[A-Z0-9_]*) ;;
    *) return 1 ;;
  esac
  case "$installer_loaded_repo_file_name" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*) return 1 ;;
  esac

  installer_loaded_repo_file_result=
  eval "installer_loaded_repo_file_result=\${$installer_loaded_repo_file_name:-}"
  printf '%s\n' "$installer_loaded_repo_file_result"
}

installer_validate_repo_env() {
  installer_repo_validate_env_path=${1:-$(installer_repo_env_path)}

  [ -r "$installer_repo_validate_env_path" ] || installer_fatal "repository path environment is not readable: $installer_repo_validate_env_path"
  # Build the reverse lookup once in this shell. Keep it out of the process
  # environment: large catalogs must not consume the child's argv/env budget.
  INSTALLER_REPO_FILE_INDEX=
  while IFS= read -r installer_repo_validate_dir_var || [ -n "$installer_repo_validate_dir_var" ]; do
    [ -n "$installer_repo_validate_dir_var" ] || continue
    installer_repo_validate_loaded_value=
    # Names come from the uppercase DIR_*/FILE_* assignment grammar below.
    # The value is read as data, never interpolated into executable shell text.
    eval "installer_repo_validate_loaded_value=\${$installer_repo_validate_dir_var:-}"
    case "$installer_repo_validate_dir_var" in
      DIR_*)
        installer_validate_repo_dir_value "$installer_repo_validate_dir_var" "$installer_repo_validate_loaded_value"
        ;;
      FILE_*)
        installer_validate_repo_file_value "$installer_repo_validate_dir_var" "$installer_repo_validate_loaded_value"
        INSTALLER_REPO_FILE_INDEX="${INSTALLER_REPO_FILE_INDEX}${installer_repo_validate_dir_var}|${installer_repo_validate_loaded_value}
"
        ;;
      *) installer_fatal "unsupported repository selector: $installer_repo_validate_dir_var" ;;
    esac
  done <<EOF
$(installer_repo_env_selector_vars "$installer_repo_validate_env_path")
EOF
}

installer_ensure_repo_env() {
  installer_repo_env_seed_base=${1:-}

  if [ "${INSTALLER_REPO_ENV_READY:-0}" -eq 1 ]; then
    return 0
  fi

  installer_repo_env_file=$(installer_repo_env_path)
  if [ -n "${INSTALLER_SOURCE_ROOT:-}" ]; then
    installer_repo_env_source="${INSTALLER_SOURCE_ROOT%/}/$(installer_repo_env_relpath)"
    [ -r "$installer_repo_env_source" ] || installer_fatal "repository path environment is not readable: ${installer_repo_env_source}"
    installer_repo_env_file=$installer_repo_env_source
  else
    [ -n "$installer_repo_env_seed_base" ] || installer_repo_env_seed_base=$(installer_current_seed_base)
    if [ ! -s "$installer_repo_env_file" ]; then
      installer_fetch_seed_path "$installer_repo_env_seed_base" "$(installer_repo_env_relpath)" "$installer_repo_env_file" 0600 || return "$?"
    fi
  fi
  # shellcheck disable=SC1090
  . "$installer_repo_env_file"
  installer_validate_repo_env "$installer_repo_env_file"
  installer_validate_relative_seed_path "${FILE_HOOKS_INSTALLER_DI_ENV:-}"
  if command -v bootstrap_ensure_di_env >/dev/null 2>&1; then
    bootstrap_ensure_di_env "$installer_repo_env_seed_base" || return $?
  fi
  INSTALLER_REPO_ENV_READY=1
}

installer_repo_dir_value() {
  installer_repo_dir_name=$1
  installer_repo_dir_value=
  installer_repo_dir_path=

  if ! installer_repo_dir_input_is_var "$installer_repo_dir_name"; then
    installer_repo_dir_path=$installer_repo_dir_name
    installer_validate_repo_dir_value repository_path "$installer_repo_dir_path"
    printf '%s\n' "$installer_repo_dir_path"
    return 0
  fi

  if [ "${INSTALLER_REPO_ENV_READY:-0}" -ne 1 ]; then
    installer_ensure_repo_env ""
  fi
  installer_repo_dir_value=$(installer_loaded_repo_dir_value "$installer_repo_dir_name" 2>/dev/null || true)
  [ -n "$installer_repo_dir_value" ] || installer_fatal "repository directory variable is unset: $installer_repo_dir_name"
  installer_validate_repo_dir_value "$installer_repo_dir_name" "$installer_repo_dir_value"
  printf '%s\n' "$installer_repo_dir_value"
}

installer_repo_file_value() {
  installer_repo_file_name=$1
  case "$installer_repo_file_name" in
    FILE_[A-Z0-9_]*) ;;
    *) installer_fatal "repository file selector is invalid: ${installer_repo_file_name:-unset}" ;;
  esac
  case "$installer_repo_file_name" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*)
      installer_fatal "repository file selector is invalid: $installer_repo_file_name"
      ;;
  esac

  if [ "${INSTALLER_REPO_ENV_READY:-0}" -ne 1 ]; then
    installer_ensure_repo_env ""
  fi
  installer_repo_file_value_result=$(installer_loaded_repo_file_value "$installer_repo_file_name" 2>/dev/null || true)
  [ -n "$installer_repo_file_value_result" ] ||
    installer_fatal "repository file variable is unset: $installer_repo_file_name"
  installer_validate_repo_file_value "$installer_repo_file_name" "$installer_repo_file_value_result"
  installer_repo_assert_asset_family "$installer_repo_file_value_result"
  printf '%s\n' "$installer_repo_file_value_result"
}

# Physical source partitions are distinct from installed paths. The validated
# role family may consume common assets and its own family only. Early bootstrap
# files lie outside these groups and do not need a target role to be loaded.
installer_repo_assert_asset_family() {
  case "${INSTALLER_HOST_VARIANT:-}" in desktop|server) ;; *) return 0 ;; esac
  for family_root in "$DIR_TARGET_AA" "$DIR_TARGET_APPARMOR" "$DIR_TARGET_TMPFILES_D" \
    "$DIR_TARGET_SYSCTL_D" "$DIR_TARGET_BIN" "$DIR_TARGET_SBIN" \
    "$DIR_TARGET_LIBEXEC" "$DIR_TARGET_LIB" "$DIR_TARGET_SHARE"; do
    case "$1" in
      "$family_root/common/"*|"$family_root/$INSTALLER_HOST_VARIANT/"*) return 0 ;;
      "$family_root/"*) installer_fatal 'source asset belongs to an incompatible or missing role family' ;;
    esac
  done
}

installer_repo_family_asset_path() {
  case "${INSTALLER_HOST_VARIANT:-}" in desktop|server) ;; *) installer_fatal 'validated asset role family is required' ;; esac
  family_asset_base=$(installer_repo_dir_value "$1") || return "$?"
  # The existing join validator rejects traversal and malformed suffixes before
  # matching the authenticated in-memory FILE catalogue; no source tree scan.
  family_asset_leaf=${2:-}
  installer_repo_join_var "$1" "$family_asset_leaf" >/dev/null || return "$?"
  case "$family_asset_leaf" in common/*|desktop/*|server/*)
    family_asset_exact="$family_asset_base/$family_asset_leaf"
    family_asset_common=$family_asset_exact; family_asset_selected=$family_asset_exact ;;
    *) family_asset_common="$family_asset_base/common/$family_asset_leaf"
       family_asset_selected="$family_asset_base/$INSTALLER_HOST_VARIANT/$family_asset_leaf" ;;
  esac
  family_asset_selector=$(printf '%s' "$INSTALLER_REPO_FILE_INDEX" |
    awk -F '|' -v common="$family_asset_common" -v selected="$family_asset_selected" '
      $2==common || $2==common ".tmpl" || $2==selected || $2==selected ".tmpl" {
        if(!seen[$2]++) {count++; selector=$1}
      }
      END {if(count!=1) exit 1; print selector}') || installer_fatal 'missing or ambiguous role source asset owner'
  installer_repo_file_value "$family_asset_selector"
}

# Resolve a policy-selected leaf through the same FILE_* catalog as fixed
# callers. The catalog is already in memory; do not scan the source tree or
# invoke metadata tools in d-i. A logical name may select its physical .tmpl
# member, matching source_fetch's existing template convention.
installer_repo_asset_path() {
  # Staging wrappers accept a FILE selector directly as their source argument.
  case "${2:-$1}" in
    FILE_*) installer_repo_file_value "${2:-$1}"; return $? ;;
  esac
  [ "${INSTALLER_REPO_ENV_READY:-0}" -eq 1 ] || installer_ensure_repo_env "" || return $?
  case "$1:${2:-}" in
    DIR_TARGET_AA:*|DIR_TARGET_APPARMOR:*|DIR_TARGET_TMPFILES_D:*|DIR_TARGET_SYSCTL_D:*|DIR_TARGET_BIN:*|DIR_TARGET_SBIN:*|DIR_TARGET_LIBEXEC:*|DIR_TARGET_LIB:*|DIR_TARGET_SHARE:*)
      installer_repo_family_asset_path "$1" "${2:-}"; return "$?" ;;
    DIR_TARGET_AA_ABSTRACTIONS:*) installer_repo_family_asset_path DIR_TARGET_AA "abstractions/${2:-}"; return "$?" ;;
    DIR_TARGET_AA_LOCAL:*) installer_repo_family_asset_path DIR_TARGET_AA "local/${2:-}"; return "$?" ;;
    DIR_TARGET_PY:*) installer_repo_family_asset_path DIR_TARGET_LIB "python3/dist-packages/${2:-}"; return "$?" ;;
    DIR_TARGET_PERL:*) installer_repo_family_asset_path DIR_TARGET_LIB "perl5/site_perl/${2:-}"; return "$?" ;;
    DIR_HOOKS_TARGET:etc/apparmor.d/*) installer_repo_family_asset_path DIR_TARGET_AA "${2#etc/apparmor.d/}"; return "$?" ;;
    DIR_HOOKS_TARGET:etc/apparmor/*) installer_repo_family_asset_path DIR_TARGET_APPARMOR "${2#etc/apparmor/}"; return "$?" ;;
    DIR_HOOKS_TARGET:etc/tmpfiles.d/*) installer_repo_family_asset_path DIR_TARGET_TMPFILES_D "${2#etc/tmpfiles.d/}"; return "$?" ;;
    DIR_HOOKS_TARGET:etc/sysctl.d/*) installer_repo_family_asset_path DIR_TARGET_SYSCTL_D "${2#etc/sysctl.d/}"; return "$?" ;;
    DIR_HOOKS_TARGET:usr/local/bin/*) installer_repo_family_asset_path DIR_TARGET_BIN "${2#usr/local/bin/}"; return "$?" ;;
    DIR_HOOKS_TARGET:usr/local/sbin/*) installer_repo_family_asset_path DIR_TARGET_SBIN "${2#usr/local/sbin/}"; return "$?" ;;
    DIR_HOOKS_TARGET:usr/local/libexec/*) installer_repo_family_asset_path DIR_TARGET_LIBEXEC "${2#usr/local/libexec/}"; return "$?" ;;
    DIR_HOOKS_TARGET:usr/local/lib/*) installer_repo_family_asset_path DIR_TARGET_LIB "${2#usr/local/lib/}"; return "$?" ;;
    DIR_HOOKS_TARGET:usr/local/share/*) installer_repo_family_asset_path DIR_TARGET_SHARE "${2#usr/local/share/}"; return "$?" ;;
    DIR_TARGET_UNIT:*) installer_repo_systemd_asset_path system "${2:-}"; return "$?" ;;
    DIR_TARGET_USER_UNIT:*) installer_repo_systemd_asset_path user "${2:-}"; return "$?" ;;
    DIR_HOOKS_TARGET:etc/systemd/system/*) installer_repo_systemd_asset_path system "${2#etc/systemd/system/}"; return "$?" ;;
    DIR_HOOKS_TARGET:etc/systemd/user/*) installer_repo_systemd_asset_path user "${2#etc/systemd/user/}"; return "$?" ;;
    DIR_HOOKS_TARGET:etc/systemd/*.conf.d/*)
      systemd_config_path=${2#etc/systemd/}
      installer_repo_systemd_asset_path "${systemd_config_path%%/*}" "${systemd_config_path#*/}"
      return "$?"
      ;;
  esac
  if [ "$1" = DIR_HOOKS_TARGET ]; then
    case "${2:-}" in
      etc/apt/apt.conf.d/*)
        installer_repo_apt_conf_asset_path "${2#etc/apt/apt.conf.d/}"
        return "$?"
        ;;
      etc/apt/*)
        case "${INSTALLER_HOST_VARIANT:-}" in desktop) apt_dir_selector=DIR_TARGET_APT_DESKTOP ;; server) apt_dir_selector=DIR_TARGET_APT_SERVER ;; *) installer_fatal 'APT family is unavailable' ;; esac
        installer_repo_asset_requested=$(installer_repo_join_var "$apt_dir_selector" "${2#etc/apt/}")
        ;;
      *) installer_repo_asset_requested=$(installer_repo_join_var "$1" "${2:-}") ;;
    esac
  else
    installer_repo_asset_requested=$(installer_repo_join_var "$1" "${2:-}")
  fi || return $?
  installer_repo_asset_selector=$(
    printf '%s' "${INSTALLER_REPO_FILE_INDEX:-}" |
      awk -F '|' -v wanted="$installer_repo_asset_requested" '
        $2 == wanted { exact = $1 }
        $2 == wanted ".tmpl" { template = $1 }
        END { if (exact != "") print exact; else if (template != "") print template }
      '
  ) || return $?
  [ -n "$installer_repo_asset_selector" ] ||
    installer_fatal "repository asset has no FILE selector in repo.env: ${installer_repo_asset_requested}"
  installer_repo_file_value "$installer_repo_asset_selector"
}

installer_repo_systemd_asset_path() {
  case "$1" in
    system|user|system.conf.d|user.conf.d|journald.conf.d|coredump.conf.d|resolved.conf.d|logind.conf.d) ;;
    *) installer_fatal 'invalid systemd asset kind' ;;
  esac
  case "${INSTALLER_HOST_VARIANT:-}" in
    desktop) systemd_family=DIR_TARGET_SYSTEMD_DESKTOP ;;
    server) systemd_family=DIR_TARGET_SYSTEMD_SERVER ;;
    *) installer_fatal 'validated systemd role family is required' ;;
  esac
  systemd_common=$(installer_repo_join_var DIR_TARGET_SYSTEMD_COMMON "$1/$2") || return "$?"
  systemd_selected=$(installer_repo_join_var "$systemd_family" "$1/$2") || return "$?"
  systemd_selector=$(printf '%s' "$INSTALLER_REPO_FILE_INDEX" |
    awk -F '|' -v common="$systemd_common" -v family="$systemd_selected" '
      $2==common || $2==common ".tmpl" || $2==family || $2==family ".tmpl" {if(!seen[$2]++) {count++; selector=$1}}
      END {if(count!=1) exit 1; print selector}') || installer_fatal 'missing or ambiguous systemd source owner'
  installer_repo_file_value "$systemd_selector"
}

installer_repo_join_var() {
  installer_repo_join_dir=$1
  installer_repo_join_leaf=${2:-}
  installer_repo_join_base=$(installer_repo_dir_value "$installer_repo_join_dir")

  # Systemd template-unit paths legitimately contain "@", for example
  # etc/systemd/system/user@.service.d/50-oom-score.conf.
  case "$installer_repo_join_leaf" in
    '') printf '%s\n' "$installer_repo_join_base" ;;
    # Chromium-derived Vivaldi profiles require this exact space-containing
    # filename. Keep the exception limited to the managed seed asset, and
    # normalize a leading slash if an older caller supplies one.
    "etc/skel-desktop/.config/vivaldi/Local State")
      printf '%s/%s\n' "$installer_repo_join_base" "$installer_repo_join_leaf"
      ;;
    "/etc/skel-desktop/.config/vivaldi/Local State")
      printf '%s/etc/skel-desktop/.config/vivaldi/Local State\n' "$installer_repo_join_base"
      ;;
    /*|../*|*/..|*../*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@-]*)
      installer_fatal "unsafe repository path suffix for ${installer_repo_join_dir}: ${installer_repo_join_leaf:-unset}"
      ;;
    *) printf '%s/%s\n' "$installer_repo_join_base" "$installer_repo_join_leaf" ;;
  esac
}

# Legacy hierarchy mapper removed; all callers use physical repository paths.

# Legacy hierarchy mapper removed; all callers use physical repository paths.

installer_repo_resolve_path() {
  installer_validate_relative_seed_path "$1"
  printf '%s\n' "$1"
}

installer_validate_apt_preference_token() {
  pref_token=$1
  pref_label=${2:-apt preferences}

  case "$pref_token" in
    *.pref) pref_name=$pref_token ;;
    *) pref_name="${pref_token}.pref" ;;
  esac
  case "$pref_name" in
    ''|.*|*/*|*..*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+-]*|*.tmp|*.bak|*.save|*.distUpgrade)
      installer_fatal "unsafe apt preference name in ${pref_label}: ${pref_token:-unset}"
      ;;
    *.pref) ;;
    *)
      installer_fatal "apt preference name in ${pref_label} must resolve to a .pref file: ${pref_token:-unset}"
      ;;
  esac
  [ "${#pref_name}" -le 128 ] || installer_fatal "apt preference name in ${pref_label} is too long: $pref_name"
  printf '%s\n' "$pref_name"
}

installer_emit_apt_preference_names() {
  pref_config=$1
  pref_label=${2:-apt preferences}
  pref_line_breaks=$(printf '%s' "$pref_config" | wc -l | tr -d '[:space:]')
  case "$pref_line_breaks" in
    0) ;;
    ''|*[!0-9]*)
      installer_fatal "unable to validate ${pref_label} line count"
      ;;
    *)
      installer_fatal "${pref_label} must be a single comma- or space-separated line"
      ;;
  esac
  pref_seen=' '

  while IFS= read -r pref_token || [ -n "$pref_token" ]; do
    [ -n "$pref_token" ] || continue
    pref_name=$(installer_validate_apt_preference_token "$pref_token" "$pref_label")
    case "$pref_seen" in
      *" $pref_name "*) continue ;;
    esac
    pref_seen="${pref_seen}${pref_name} "
    printf '%s\n' "$pref_name"
  done <<EOF
$(printf '%s' "$pref_config" | tr ',	 ' '\n\n\n')
EOF
}

installer_normalize_apt_preferences_config() {
  pref_config=$1
  pref_label=${2:-apt preferences}
  pref_normalized=

  while IFS= read -r pref_name || [ -n "$pref_name" ]; do
    [ -n "$pref_name" ] || continue
    pref_token=${pref_name%.pref}
    pref_normalized="${pref_normalized:+$pref_normalized,}$pref_token"
  done <<EOF
$(installer_emit_apt_preference_names "$pref_config" "$pref_label")
EOF
  printf '%s\n' "$pref_normalized"
}

installer_seed_cache_key() (
  installer_load_source_library "$1" || exit 1
  normalized=$(source_normalize_base "$1") || exit 1
  key=$(printf '%s' "$normalized" | source_hash) || exit 1
  printf '%s\n' "${key%% *}"
)

installer_seed_cache_path() (
  installer_load_source_library "$1" || exit 1
  source_validate_relative "$2" || exit 1
  printf '%s/%s\n' "$(source_cache_root "$1")" "$2"
)

# External vendor data; never resolve repository code from the vendor URL.
installer_fetch_url() (
  installer_load_source_library "${INSTALLER_SOURCE_ROOT:-}" || exit 1
  source_fetch_external "$1" "$2" "$3" "${4:-0600}"
)

installer_copy_seed_file() (
  installer_load_source_library "$1" || exit 1
  source_fetch "$1" "$2" "$3" "${4:-0600}"
)


# Logging is a separately validated shared data catalog. No values are obtained
# from log messages, application environments, or unverified remote fallbacks.
installer_load_logging_helpers() {
  if command -v installer_validate_logging_data >/dev/null 2>&1; then return 0; fi
  installer_load_source_library "$1" || return 1
  log_helper_root=$(source_cache_root "$1") || return 1
  log_helper_source=$(installer_repo_file_value FILE_COMMON_LOGGING) || return $?
  log_helper_path=$log_helper_root/$log_helper_source
  if [ ! -f "$log_helper_path" ]; then
    source_fetch "$1" "$log_helper_source" "$log_helper_path" 0600 || return $?
  fi
  [ -f "$log_helper_path" ] && [ ! -L "$log_helper_path" ] || {
    installer_error 'logging helpers are absent from the authenticated source'; return 1;
  }
  # shellcheck disable=SC1090,SC1091
  . "$log_helper_path"
}

installer_render_logging_asset() (
  # Transport callers retain the original mode and the suffix-free destination.
  case "$2" in "${DIR_HOOKS_TARGET}/"*|"${DIR_SCRIPTS_LATE}/"*|"${DIR_SCRIPTS_DESKTOP}/"*|"${DIR_SCRIPTS_FIRSTBOOT}/"*) ;; *) exit 0 ;; esac
  case "$2" in *.png|*.jpg|*.jpeg|*.webp|*.gif|*.ico|*.ttf|*.otf|*.gz|*.xz|*.zip|*.deb) exit 0 ;; esac
  if LC_ALL=C grep -q '__INSTALLER_LOG_' "$3"; then
    installer_load_logging_helpers "$1" || exit 1
    log_cache_root=$(source_cache_root "$1") || exit 1
    case "$3" in
      "$log_cache_root"|"$log_cache_root"/*)
        installer_error 'refusing to render inside the authenticated source snapshot'; exit 1 ;;
    esac
    installer_render_logging_file "$1" "$3" || exit 1
  else
    log_probe_status=$?
    [ "$log_probe_status" = 1 ] || exit "$log_probe_status"
  fi
)

installer_fetch_seed_path() (
  # EXIT can run inside a nested fatal helper, whose positional arguments are
  # different. Retain this acquisition's inputs for both execution and errors.
  repository_fetch_seed_base=${1:-}
  repository_fetch_source=${2:-}
  repository_fetch_destination=${3:-}
  repository_fetch_mode=${4:-0600}
  logging_fetch_work=
  repository_fetch_step=validate
  repository_fetch_status=0
  # The caller owns mandatory/optional policy. Report the original cause here
  # without publishing a terminal failure for a caller-handled fetch result.
  trap 'repository_fetch_status=$?; trap - 0; if [ -n "$logging_fetch_work" ]; then rm -rf -- "$logging_fetch_work" || :; fi; if [ "$repository_fetch_status" -ne 0 ]; then installer_error "repository asset acquisition failed: status=${repository_fetch_status} step=${repository_fetch_step} suite=${INSTALLER_SUITE:-unknown} profile=${INSTALLER_HOST_PROFILE:-unknown} phase=${INSTALLER_PHASE:-unknown} source=${repository_fetch_source} destination=${repository_fetch_destination} source_file=${INSTALLER_FAILURE_SOURCE:-unknown} line=${INSTALLER_FAILURE_LINE:-unknown} operation=${INSTALLER_FAILURE_OPERATION:-unknown}" || :; fi; exit "$repository_fetch_status"' 0
  if [ -z "$repository_fetch_source" ] || [ -z "$repository_fetch_destination" ]; then
    installer_error 'repository asset source and destination must be nonempty' || :
    exit 64
  fi
  repository_fetch_identity=$repository_fetch_seed_base
  if command -v source_normalize_base >/dev/null 2>&1; then
    repository_fetch_identity=$(source_normalize_base "$repository_fetch_seed_base") || exit 125
  fi
  if [ "${BOOTSTRAP_PREPARED_PRESENT:-0}" = 1 ] ||
     [ -n "${BOOTSTRAP_PREPARED_SOURCE_ROOT:-}" ]; then
    if [ "$repository_fetch_identity" != "${BOOTSTRAP_PREPARED_SEED_BASE:-}" ]; then
      installer_error "prepared payload identity mismatch; refusing remote fallback: source=${repository_fetch_source} prepared_identity=authenticated-receipt requested_identity=authenticated-request" || :
      exit 125
    fi
    installer_repo_assert_asset_family "$repository_fetch_source"
    bootstrap_copy_prepared_file "$repository_fetch_identity" "$repository_fetch_source" \
      "$repository_fetch_destination" "$repository_fetch_mode"
    exit "$?"
  fi
  repository_fetch_step=load_source
  installer_operation_context_repo FILE_COMMON_MOD_REPOSITORY_APT 676 load_asset_source
  installer_load_source_library "$repository_fetch_seed_base" || exit "$?"
  case "$repository_fetch_source" in
    "${DIR_HOOKS_TARGET}/"*|"${DIR_REPO_SCRIPTS}/"*)
      # Fetch and rendering form one transaction; invalid data cannot replace
      # a destination with an unrendered source template.
      mkdir -p "$(dirname "$repository_fetch_destination")" || exit "$?"
      logging_fetch_work=$(mktemp -d "${repository_fetch_destination}.fetch-render.XXXXXX") || exit "$?"
      trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
      chmod 0700 "$logging_fetch_work" || exit "$?"
      repository_fetch_step=fetch
      installer_operation_context_repo FILE_COMMON_MOD_REPOSITORY_APT 687 source_fetch
      source_fetch "$repository_fetch_seed_base" "$repository_fetch_source" "$logging_fetch_work/asset" "$repository_fetch_mode" || exit "$?"
      repository_fetch_step=render_logging
      installer_operation_context_repo FILE_COMMON_MOD_REPOSITORY_APT 690 installer_render_logging_asset
      installer_render_logging_asset "$repository_fetch_seed_base" "$repository_fetch_source" "$logging_fetch_work/asset" || exit "$?"
      repository_fetch_step=render_paths
      # This is the code/data publication boundary for every script family,
      # including common, runtime and server helpers. Keep the authenticated
      # source bytes untouched and publish only a complete rendered candidate.
      if installer_contains_unresolved_path_placeholders "$logging_fetch_work/asset"; then
        repository_path_cache=$(source_cache_root "$repository_fetch_seed_base") || exit "$?"
        case "$repository_fetch_destination" in
          "$repository_path_cache"|"$repository_path_cache"/*)
            installer_error 'refusing to render inside the authenticated source snapshot'; exit 1 ;;
        esac
        command -v installer_apply_scalar_placeholders >/dev/null 2>&1 &&
          command -v installer_assert_no_unresolved_path_placeholders >/dev/null 2>&1 ||
          installer_fatal 'runtime path asset requested before common library initialization'
        installer_operation_context_repo FILE_COMMON_MOD_REPOSITORY_APT 705 render_runtime_paths
        installer_apply_scalar_placeholders "$logging_fetch_work/asset" "$logging_fetch_work/rendered" || exit "$?"
        installer_operation_context_repo FILE_COMMON_MOD_REPOSITORY_APT 707 validate_runtime_paths
        installer_assert_no_unresolved_path_placeholders "$logging_fetch_work/rendered" "$repository_fetch_source" || exit "$?"
        chmod "$repository_fetch_mode" "$logging_fetch_work/rendered" || exit "$?"
        mv -f -- "$logging_fetch_work/rendered" "$logging_fetch_work/asset" || exit "$?"
      else
        repository_path_probe_status=$?
        [ "$repository_path_probe_status" -eq 1 ] || exit "$repository_path_probe_status"
      fi
      repository_fetch_step=publish
      installer_operation_context_repo FILE_COMMON_MOD_REPOSITORY_APT 716 publish_fetched_asset
      mv -f -- "$logging_fetch_work/asset" "$repository_fetch_destination" || exit "$?" ;;
    *)
      repository_fetch_step=fetch
      installer_operation_context_repo FILE_COMMON_MOD_REPOSITORY_APT 720 source_fetch
      source_fetch "$repository_fetch_seed_base" "$repository_fetch_source" "$repository_fetch_destination" "$repository_fetch_mode" || exit "$?" ;;
  esac
)

installer_fetch_file() {
  fetch_file_seed_base=$1
  fetch_file_source_path=$2
  fetch_file_dest_path=$3
  fetch_file_mode=${4:-0600}

  if installer_fetch_seed_path "$fetch_file_seed_base" "$fetch_file_source_path" "$fetch_file_dest_path" "$fetch_file_mode"; then
    return 0
  else
    fetch_file_status=$?
    installer_fatal_status "$fetch_file_status" "failed to fetch repository asset: source=${fetch_file_source_path} destination=${fetch_file_dest_path}"
  fi
}

# Native suites and explicitly selected vendor scopes are installed together
# before the first target APT refresh. No universal testing/stable fallback.
# Source policy is owned by each suite/family tree, never a parallel registry.
installer_repo_apt_selector() {
  case "${INSTALLER_HOST_VARIANT:-}" in desktop) apt_family=DESKTOP ;; server) apt_family=SERVER ;; *) installer_fatal 'validated APT role family is required' ;; esac
  case "${1:-}" in ''|*[!A-Z0-9_]*) installer_fatal 'invalid APT source selector' ;; esac
  # Common and role policy have distinct source owners. Reject duplicate owners
  # instead of silently selecting a stale role copy of a common drop-in.
  printf '%s' "${INSTALLER_REPO_FILE_INDEX:-}" |
    awk -F '|' -v common="FILE_TARGET_APT_$1" -v selected="FILE_TARGET_APT_${apt_family}_$1" '
      $1==common || $1==selected {count++; selector=$1}
      END {if(count!=1) exit 1; print selector}' ||
    installer_fatal "missing or ambiguous APT policy selector: $1"
}

installer_repo_apt_file() {
  installer_repo_file_value "$(installer_repo_apt_selector "$1")"
}

# Enumerate only authenticated immediate drop-ins from the suite's common and
# selected role directories. repo.env, not a filesystem glob, owns membership.
installer_repo_apt_conf_catalog() (
  set -eu
  case "${INSTALLER_HOST_VARIANT:-}" in
    desktop) apt_role_dir=DIR_TARGET_APT_DESKTOP_APT_CONF_D ;;
    server) apt_role_dir=DIR_TARGET_APT_SERVER_APT_CONF_D ;;
    *) installer_fatal 'validated APT role family is required' ;;
  esac
  apt_common=$(installer_repo_dir_value DIR_TARGET_APT_APT_CONF_D) || exit "$?"
  apt_role=$(installer_repo_dir_value "$apt_role_dir") || exit "$?"
  printf '%s' "$INSTALLER_REPO_FILE_INDEX" |
    awk -F '|' -v common="$apt_common/" -v role="$apt_role/" '
      index($2,common)==1 {leaf=substr($2,length(common)+1)}
      index($2,role)==1 {leaf=substr($2,length(role)+1)}
      index($2,common)!=1 && index($2,role)!=1 {next}
      leaf !~ /^[A-Za-z0-9][A-Za-z0-9_.-]*$/ {exit 1}
      {sub(/[.]tmpl$/, "", leaf); if(seen[leaf]++) exit 1; print leaf "|" $1; count++}
      END {if(!count) exit 1}'
)

installer_repo_apt_conf_asset_path() (
  set -eu
  apt_catalog=$(installer_repo_apt_conf_catalog) || exit "$?"
  apt_selector=$(printf '%s\n' "$apt_catalog" | awk -F '|' -v leaf="$1" '
    $1==leaf {selector=$2; count++} END {if(count!=1) exit 1; print selector}') ||
    installer_fatal 'missing or ambiguous APT drop-in source owner'
  installer_repo_file_value "$apt_selector"
)

installer_stage_suite_apt_preferences() {
  installer_assert_class_plan || return "$?"
  case "$INSTALLER_HOST_VARIANT" in
    desktop) apt_source_selector=DIR_TARGET_APT_DESKTOP ;;
    server) apt_source_selector=DIR_TARGET_APT_SERVER ;;
    *) installer_fatal 'invalid APT role family' ;;
  esac
  apt_source_root=$(installer_repo_join_var "$apt_source_selector") || return "$?"
  apt_destination="${INSTALLER_TARGET_DIR:-$TARGET_ROOT}${DIR_APT_PREFERENCES_D}"
  installer_apt_safe_path "$apt_destination" || return 1
  install -d -m 0755 "$apt_destination" || return "$?"
  # The apt-setup generator is the single staging boundary for preference
  # drop-ins.  Sort by the installed filename rather than relying on the
  # selector declaration order, so APT's lexical precedence is deterministic
  # for every suite and role family.  Optional vendor policies are appended
  # below with their explicit 30/31 filenames, matching the legacy hook's
  # configured-preferences-then-optional ordering.
  apt_preference_sources=$(
    printf '%s' "$INSTALLER_REPO_FILE_INDEX" |
      awk -F '|' -v root="$apt_source_root/preferences.d/" '
        index($2, root) == 1 {
          leaf = substr($2, length(root) + 1)
          if (leaf !~ /\// && leaf ~ /\.pref$/) print $2
        }
      ' |
      LC_ALL=C sort
  ) || return "$?"
  apt_preference_count=0
  while IFS= read -r apt_source || [ -n "$apt_source" ]; do
    [ -n "$apt_source" ] || continue
    apt_leaf=${apt_source#"$apt_source_root/preferences.d/"}
    installer_fetch_file "$(installer_seed_base "")" "$apt_source" "$apt_destination/$apt_leaf" 0644 || return "$?"
    apt_preference_count=$((apt_preference_count + 1))
  done <<EOF
$apt_preference_sources
EOF
  [ "$apt_preference_count" -gt 0 ] || installer_fatal 'selected suite has no APT preference drop-ins'
  installer_info "staged ${apt_preference_count} suite/family APT preference drop-ins before pkgsel"
  apt_optional=nvidia-opt-in
  if installer_nvidia_class_selected; then
    installer_nvidia_gpu_detected || installer_fatal 'NVIDIA/CUDA class requires compatible NVIDIA hardware'
    if installer_class_selected optional/nvidia-legacy; then apt_optional=nvidia-legacy; else apt_optional=nvidia; fi
  fi
  apt_optional_file=$(installer_repo_asset_path "$apt_source_selector" "preferences.d/optional/$apt_optional.pref") || return "$?"
  installer_fetch_file "$(installer_seed_base "")" "$apt_optional_file" "$apt_destination/30-nvidia.pref" 0644 || return "$?"
  for apt_cuda in cuda cuda-legacy; do
    if installer_class_selected "optional/$apt_cuda"; then
      apt_optional_file=$(installer_repo_asset_path "$apt_source_selector" "preferences.d/optional/$apt_cuda.pref") || return "$?"
      installer_fetch_file "$(installer_seed_base "")" "$apt_optional_file" "$apt_destination/31-cuda.pref" 0644 || return "$?"
    fi
  done
}
