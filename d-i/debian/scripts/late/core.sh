#!/bin/sh
# Shared late_command core helpers. This file is sourced, not executed.

late_command_bootstrap_fatal() {
  late_command_bootstrap_message=$(printf '%s' "$*" | tr '\r\n\t' '   ')
  printf '[bootstrap] fatal: %s\n' "$late_command_bootstrap_message" >&2
  if [ -c /dev/tty4 ] && [ -w /dev/tty4 ]; then
    printf '[bootstrap] fatal: %s\n' "$late_command_bootstrap_message" >/dev/tty4 || :
  fi
  if command -v logger >/dev/null 2>&1; then
    logger -t preseed-late "fatal: $late_command_bootstrap_message" 2>/dev/null || :
  fi
  exit 1
}

late_command_load_bootstrap() {
  if command -v bootstrap_source_common_lib >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
    return 0
  fi

  runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
  bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}

  [ -s "$bootstrap_lib" ] || {
    late_command_bootstrap_fatal "installer bootstrap library is unavailable: ${bootstrap_lib}"
  }

  # shellcheck disable=SC1090,SC1091
  . "$bootstrap_lib" || {
    late_command_bootstrap_fatal "failed to source installer bootstrap library: ${bootstrap_lib}"
  }
  command -v bootstrap_source_common_lib >__INSTALLER_PATH_DIR_DEV__/null 2>&1 || {
    late_command_bootstrap_fatal "installer bootstrap library did not define bootstrap_source_common_lib: ${bootstrap_lib}"
  }
}

late_command_shared_init() {
  requested_seed_base=${1:-}
  requested_host_profile=${2:-}
  hook_family=${3:-}

  [ -n "$hook_family" ] || late_command_bootstrap_fatal "late-command hook family is required"
  late_command_load_bootstrap
  bootstrap_source_common_lib "$requested_seed_base" || {
    late_command_bootstrap_fatal "failed to source installer common library"
  }
  installer_target_context_init || late_command_bootstrap_fatal 'mounted target context is unavailable'
  LOG="$(installer_runtime_log_file)"
  installer_init_log_file "$LOG" "" "${hook_family} late_command" late-command late_command
  installer_operation_context_repo scripts/late/core.sh 49 late_command_shared_init
  trap 'installer_finalize_log "$?"' EXIT
  SEED_BASE=$(installer_seed_base "$requested_seed_base")
  installer_persist_seed_source "$SEED_BASE"
  installer_ensure_context_loaded "$SEED_BASE"
  HOST_PROFILE=$(installer_resolve_host_profile "$requested_host_profile")

  TMP_ENV_DIR=${DIR_INSTALLER_LATE_ENV}
  RUNTIME_DIR=$(installer_runtime_dir)
  LATE_COMMAND_HOST_ENV=${INSTALLER_LATE_HOST_ENV:-${TMP_ENV_DIR}/host.env}
  LATE_COMMAND_ACCOUNT_ENV=${INSTALLER_LATE_ACCOUNT_ENV:-${TMP_ENV_DIR}/account.env}
  mkdir -p "$TMP_ENV_DIR" "$RUNTIME_DIR"
  bootstrap_source_common_support_libs "$SEED_BASE" "$TMP_ENV_DIR" fetch hook target ssh || {
    installer_fatal "failed to source installer late support libraries"
  }
  late_command_collect_installer_logs
}

fetch_env() {
  fetch_env_file "$1" "$2"
}

late_command_load_themes() {
  if ! command -v installer_load_themes >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
    fetch_hook_file "$(installer_repo_file_value scripts/late/themes.sh)" "$TMP_ENV_DIR/themes.sh" || return $?
    # shellcheck disable=SC1090,SC1091
    . "$TMP_ENV_DIR/themes.sh" || return $?
  fi
  installer_load_themes
}

fetch_hook() {
  fetch_hook_file "$1" "$2" || return $?
  # Paths, logging and eligible theme defaults were rendered together before
  # late_command. Registry mapping tokens intentionally remain literal.
  [ -z "${BOOTSTRAP_PREPARED_SOURCE_ROOT:-}" ] || return 0
  # Every fetched late/desktop/firstboot asset uses the same canonical
  # runtime path namespace.  Render it before the caller sources or executes
  # the fetched file; leaving a path token in an installer-side helper would
  # otherwise turn a valid target path into an empty or literal argument.
  if installer_contains_unresolved_path_placeholders "$2"; then
    # fetch_hook_file always stages this private helper with mode 0755.  Keep
    # the renderer independent of the unavailable d-i `stat` applet.
    fetch_hook_path_mode=0755
    fetch_hook_path_rendered="${2}.path-rendered"
    installer_apply_scalar_placeholders "$2" "$fetch_hook_path_rendered" || {
      rm -f -- "$fetch_hook_path_rendered"
      installer_fatal "failed to render runtime paths in fetched asset: $1"
      return 1
    }
    installer_assert_no_unresolved_path_placeholders "$fetch_hook_path_rendered" "$1" || {
      rm -f -- "$fetch_hook_path_rendered"
      return 1
    }
    chmod "$fetch_hook_path_mode" "$fetch_hook_path_rendered" || {
      rm -f -- "$fetch_hook_path_rendered"
      installer_fatal "failed to restore fetched asset mode: $1"
      return 1
    }
    mv -f -- "$fetch_hook_path_rendered" "$2" || {
      rm -f -- "$fetch_hook_path_rendered"
      installer_fatal "failed to publish rendered fetched asset: $1"
      return 1
    }
  else
    fetch_hook_path_probe_status=$?
    [ "$fetch_hook_path_probe_status" = 1 ] || {
      installer_fatal "could not inspect fetched asset for runtime paths: $1"
      return 1
    }
  fi
  case "$1" in
    *.png|*.jpg|*.jpeg|*.webp|*.gif|*.ico|*.ttf|*.otf|*.woff|*.woff2|*.gz|*.xz|*.bz2|*.zip|*.deb)
      return 0 ;;
  esac
  # Appearance Python modules are code, not themed consumer assets.  Keep
  # their bytes literal even if a diagnostic, grammar, or future test embeds
  # a token-shaped string.  The fields registry is deliberately the
  # fields.json.tmpl source asset: themes.sh selects defaults-only rendering
  # before it is installed as fields.json. Its mapping templates and token
  # lists must retain their literal markers for native value capture/editing.
  case "$1" in
    "${DIR_TARGET_PY}/labwc_appearance/"*.py) return 0 ;;
  esac
  case "$1" in
    "${DIR_HOOKS_TARGET}/"*|"${DIR_SCRIPTS_DESKTOP}/"*|"${DIR_SCRIPTS_FIRSTBOOT}/"*)
      if LC_ALL=C grep -q '__THEME_' "$2"; then
        late_command_load_themes || return $?
        installer_theme_render_file "$2" "$1" || return $?
      else
        theme_probe_status=$?
        [ "$theme_probe_status" = 1 ] || {
          installer_fatal "could not inspect fetched theme asset: $1"
          return 1
        }
      fi
      ;;
  esac
}

fatal() {
  installer_fatal "$@"
}

warn() {
  installer_warn "$@"
}

info() {
  installer_info "$@"
}

require_in_target() {
  phase_label=$1
  target_exec_available || fatal "target command execution is unavailable during ${phase_label}"
}

ensure_installer_command_logged() {
  cmd=$1
  udeb=$2

  if command -v "$cmd" >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
    return 0
  fi
  warn "${cmd} is unavailable in the installer environment; attempting anna-install ${udeb}"
  hook_ensure_installer_command "$cmd" "$udeb"
}

late_command_collect_installer_logs() {
  runtime_log_dir=$(installer_runtime_log_dir)

  if installer_logging_enabled; then
    installer_info "live installer logs are under ${runtime_log_dir}; late hooks snapshot them into ${TARGET_ROOT} before finish-install runs"
  fi
}

late_command_ensure_env_paths() {
  [ -n "${TMP_ENV_DIR:-}" ] || late_command_bootstrap_fatal "late-command environment directory is not initialized"
  : "${LATE_COMMAND_HOST_ENV:=${INSTALLER_LATE_HOST_ENV:-${TMP_ENV_DIR}/host.env}}"
  : "${LATE_COMMAND_ACCOUNT_ENV:=${INSTALLER_LATE_ACCOUNT_ENV:-${TMP_ENV_DIR}/account.env}}"
}

late_command_host_env_path() {
  late_command_ensure_env_paths || return $?
  printf '%s\n' "$LATE_COMMAND_HOST_ENV"
}

late_command_account_env_path() {
  late_command_ensure_env_paths || return $?
  printf '%s\n' "$LATE_COMMAND_ACCOUNT_ENV"
}

late_command_ensure_profile_env() {
  late_command_ensure_env_paths || return $?
  late_command_host_env=$LATE_COMMAND_HOST_ENV

  if [ ! -s "$late_command_host_env" ]; then
    # The acquisition helper owns and restores its diagnostic context.
    installer_fetch_host_env "$SEED_BASE" "$HOST_PROFILE" "$late_command_host_env" 0600 || {
      late_command_env_status=$?
      installer_fatal_status "$late_command_env_status" \
        "failed to fetch host policy environment: source=${HOST_PROFILE:-unset} destination=${late_command_host_env}"
      return "$late_command_env_status"
    }
    LATE_COMMAND_PROFILE_ENV_LOADED=0
  fi
}

late_command_load_profile_env() {
  [ "${LATE_COMMAND_PROFILE_ENV_LOADED:-0}" = 1 ] && return 0

  late_command_ensure_profile_env || return $?
  late_command_host_env=$LATE_COMMAND_HOST_ENV
  [ -r "$late_command_host_env" ] || installer_fatal "host policy env is missing: ${late_command_host_env}"
  # shellcheck disable=SC1090,SC1091
  installer_load_data_env "$late_command_host_env" || return $?
  validate_installed_log_levels || return $?
  late_command_load_themes || return $?
  LATE_COMMAND_PROFILE_ENV_LOADED=1
}

late_command_load_account_env() {
  [ "${LATE_COMMAND_ACCOUNT_ENV_LOADED:-0}" = 1 ] && return 0

  # Profile rendering and runtime fetching must not depend on account state.
  # Resolve once per caller shell after the public profile, through the same
  # atomic publisher used by the dispatcher and standalone addon fallbacks.
  late_command_load_profile_env || return $?
  late_command_account_env=$LATE_COMMAND_ACCOUNT_ENV
  # The publisher sets its own context in its subshell. A successful account
  # handoff must leave the provider's context intact for later target commands.
  installer_prepare_late_account_env "$SEED_BASE" "$late_command_account_env" || {
    late_command_env_status=$?
    installer_fatal_status "$late_command_env_status" \
      "failed to prepare resolved account environment: destination=${late_command_account_env}"
    return "$late_command_env_status"
  }
  [ -f "$late_command_account_env" ] && [ ! -L "$late_command_account_env" ] &&
    [ -s "$late_command_account_env" ] && [ -r "$late_command_account_env" ] ||
    installer_fatal "resolved account env is missing or unsafe: ${late_command_account_env}"
  unset ACCOUNT_USERNAME ACCOUNT_HOME
  # shellcheck disable=SC1090,SC1091
  installer_load_data_env "$late_command_account_env" || return $?
  [ -r "$TMP_ENV_DIR/runtime-common.sh" ] || installer_fatal "runtime common helper is missing: ${TMP_ENV_DIR}/runtime-common.sh"
  RUNTIME_COMMON_LIB="$TMP_ENV_DIR/runtime-common.sh"
  export RUNTIME_COMMON_LIB
  [ -r "$TMP_ENV_DIR/account-runtime.sh" ] || installer_fatal "runtime account helper is missing: ${TMP_ENV_DIR}/account-runtime.sh"
  # shellcheck disable=SC1090,SC1091
  . "$TMP_ENV_DIR/account-runtime.sh" || return $?
  unset RUNTIME_ACCOUNT_CREDENTIALS_READY
  runtime_apply_account_from_credentials || return $?
  # The publisher already wrote the complete snapshot. Do not truncate it
  # outside its lock when loading private credentials for this caller.
  LATE_COMMAND_ACCOUNT_ENV_LOADED=1
}

late_command_fetch_common_assets() {
  runtime_script_path=$1

  # The family runs in its own shell. Fetching host.env alone does not load
  # the target path values needed to render the first bootprofile/unit asset.
  # Load the validated profile before any fetched template reaches a renderer.
  late_command_load_profile_env || return $?
  late_command_fetch_repo_file scripts/runtime/common.sh "$TMP_ENV_DIR/runtime-common.sh" runtime-common.sh
  late_command_fetch_asset "$runtime_script_path" "$TMP_ENV_DIR/runtime.sh" "${runtime_script_path##*/}"
  late_command_fetch_repo_file scripts/runtime/account.sh "$TMP_ENV_DIR/account-runtime.sh" account.sh
  late_command_fetch_repo_file hooks/target/usr/libexec/install-tools/bootprofile-apply.tmpl "$TMP_ENV_DIR/bootprofile-apply.tmpl" bootprofile-apply.tmpl
  late_command_fetch_repo_file hooks/target/etc/systemd/common/system/bootprofile-apply.service.tmpl "$TMP_ENV_DIR/bootprofile-apply.service.tmpl" bootprofile-apply.service
  late_command_fetch_repo_file hooks/target/usr/local/libexec/common/apt-refresh-lists.tmpl "$TMP_ENV_DIR/apt-refresh-lists.tmpl" apt-refresh-lists.tmpl
  late_command_fetch_repo_file hooks/target/etc/systemd/common/system/apt-refresh-lists.service.tmpl "$TMP_ENV_DIR/apt-refresh-lists.service.tmpl" apt-refresh-lists.service
  late_command_fetch_repo_file hooks/target/etc/systemd/common/system/apt-daily.service.d/override.conf.tmpl "$TMP_ENV_DIR/apt-daily.override.conf.tmpl" apt-daily.override.conf
  late_command_fetch_repo_file hooks/target/etc/sudoers.d/account.tmpl "$TMP_ENV_DIR/account.sudoers.tmpl" account.sudoers
  late_command_fetch_repo_file hooks/target/etc/systemd/common/system/zram-setup.service.tmpl "$TMP_ENV_DIR/zram-setup.service.tmpl" zram-setup.service
  late_command_fetch_repo_file hooks/target/etc/systemd/common/system/zram-writeback.service.tmpl "$TMP_ENV_DIR/zram-writeback.service.tmpl" zram-writeback.service
  late_command_fetch_repo_file hooks/target/etc/systemd/common/system/zram-writebackd.service.tmpl "$TMP_ENV_DIR/zram-writebackd.service.tmpl" zram-writebackd.service
  late_command_fetch_repo_file hooks/target/etc/systemd/common/system/zram-idle-writeback.timer.tmpl "$TMP_ENV_DIR/zram-idle-writeback.timer.tmpl" zram-idle-writeback.timer
  late_command_fetch_repo_file hooks/target/etc/systemd/common/system/zram-cold-tier.timer.tmpl "$TMP_ENV_DIR/zram-cold-tier.timer.tmpl" zram-cold-tier.timer
  late_command_fetch_repo_file hooks/target/etc/systemd/common/system/swap-fallback.service.tmpl "$TMP_ENV_DIR/swap-fallback.service.tmpl" swap-fallback.service
  late_command_fetch_repo_file hooks/target/usr/local/libexec/common/tmpfs-pre-clean.tmpl "$TMP_ENV_DIR/tmpfs-pre-clean.tmpl" tmpfs-pre-clean.tmpl
  late_command_fetch_repo_file hooks/target/etc/systemd/common/system/tmpfs-pre-clean.service.tmpl "$TMP_ENV_DIR/tmpfs-pre-clean.service.tmpl" tmpfs-pre-clean.service
}

late_command_fetch_asset() {
  late_asset_source=$1
  late_asset_destination=$2
  late_asset_label=${3:-${late_asset_source##*/}}

  if fetch_hook "$late_asset_source" "$late_asset_destination"; then
    return 0
  else
    late_asset_status=$?
  fi
  installer_fatal_status "$late_asset_status" \
    "late-command asset fetch failed: label=${late_asset_label} source=${late_asset_source} destination=${late_asset_destination}"
}

late_command_fetch_repo_file() {
  late_asset_selector=$1
  late_asset_destination=$2
  late_asset_label=${3:-$late_asset_selector}

  late_asset_source=$(installer_repo_file_value "$late_asset_selector") || {
    late_asset_status=$?
    installer_fatal_status "$late_asset_status" \
      "late-command repository file selector resolution failed: selector=${late_asset_selector} destination=${late_asset_destination}"
    return "$late_asset_status"
  }
  late_command_fetch_asset "$late_asset_source" "$late_asset_destination" "$late_asset_label"
}

late_command_fetch_common_assets_file() {
  late_asset_selector=$1

  late_asset_source=$(installer_repo_file_value "$late_asset_selector") || {
    late_asset_status=$?
    installer_fatal_status "$late_asset_status" \
      "late-command runtime file selector resolution failed: selector=${late_asset_selector}"
    return "$late_asset_status"
  }
  late_command_fetch_common_assets "$late_asset_source"
}

late_command_load_runtime_env() {
  # Propagate each failure even under an if/OR caller (which disables errexit).

  late_command_load_profile_env || return $?
  RUNTIME_COMMON_LIB="$TMP_ENV_DIR/runtime-common.sh"
  export RUNTIME_COMMON_LIB
  # shellcheck disable=SC1090,SC1091
  . "$TMP_ENV_DIR/runtime.sh" || return $?
  late_command_runtime_state_env="$(installer_runtime_state_dir)/runtime.env" || return $?
  [ -n "${DIR_INSTALLER_ENV:-}" ] || installer_fatal 'DIR_INSTALLER_ENV is unavailable; di.env was not loaded'
  late_command_env_dir=${DIR_INSTALLER_ENV:-}
  if [ -r "${late_command_env_dir}/runtime.env" ]; then
    # shellcheck disable=SC1090,SC1091
    . "${late_command_env_dir}/runtime.env" || return $?
  elif [ -r "$late_command_runtime_state_env" ]; then
    # shellcheck disable=SC1090,SC1091
    . "$late_command_runtime_state_env" || return $?
  else
    # Re-detecting an append layout here would select space after the freshly
    # installed system. Only the frozen pre-partman identities are authoritative.
    installer_fatal 'frozen partition layout is missing; refusing late-stage disk rediscovery'
    return 1
  fi
  installer_ensure_context_loaded "${SEED_BASE:-}" || return $?
  runtime_ensure_system_identity || return $?
  validate_tmpfs_policy_env
}

runtime_log_level_canonical() {
  case "${1:-error}" in
    debug|DEBUG) printf '%s\n' debug ;;
    info|INFO) printf '%s\n' info ;;
    warn|WARN|warning|WARNING) printf '%s\n' warning ;;
    error|ERROR|fatal|FATAL) printf '%s\n' error ;;
    none|NONE) printf '%s\n' none ;;
    *) return 1 ;;
  esac
}

runtime_nftables_log_level_canonical() {
  runtime_log_level_canonical "${1:-none}"
}

validate_installed_log_levels() {
  nft_level=$(runtime_nftables_log_level_canonical "${NFTABLES_LOG_LEVEL:-none}") ||
    installer_fatal "NFTABLES_LOG_LEVEL must be debug, info, warning, error, or none"
  zram_level=$(runtime_log_level_canonical "${ZRAM_LOG_LEVEL:-info}") ||
    installer_fatal "ZRAM_LOG_LEVEL must be debug, info, warning, error, or none"
  systemd_level=$(runtime_log_level_canonical "${SYSTEMD_LOG_LEVEL:-error}") ||
    installer_fatal "SYSTEMD_LOG_LEVEL must be debug, info, warning, error, or none"

  NFTABLES_LOG_LEVEL=$nft_level
  ZRAM_LOG_LEVEL=$zram_level
  SYSTEMD_LOG_LEVEL=$systemd_level
}

late_command_load_host_env() {
  late_command_load_profile_env || return $?
  late_command_load_account_env || return $?
}

install_target_runtime_defaults() {
  : "${FILE_LOGIND_OVERRIDE_CONF:?FILE_LOGIND_OVERRIDE_CONF must be set}"

  stage_target_iocost || return $?

  validate_installed_log_levels || return $?
  render_target_asset "$(installer_repo_file_value hooks/target/etc/system-runtime.conf.tmpl)" __INSTALLER_PATH_DIR_ETC__/system-runtime.conf 0644 || return $?
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/systemd/desktop/logind.conf.d/override.conf)" \
    "${FILE_LOGIND_OVERRIDE_CONF}" \
    0644
}

install_target_wpa_supplicant_runtime_policy() {
  : "${FILE_WPA_SUPPLICANT_CONF:?FILE_WPA_SUPPLICANT_CONF must be set}"
  : "${FILE_WPA_SUPPLICANT_P2P_DEVICE_CONF:?FILE_WPA_SUPPLICANT_P2P_DEVICE_CONF must be set}"
  : "${FILE_WPA_SUPPLICANT_DBUS_SERVICE_OVERRIDE:?FILE_WPA_SUPPLICANT_DBUS_SERVICE_OVERRIDE must be set}"
  : "${FILE_WPA_SUPPLICANT_DBUS_SERVICE_ALIAS:?FILE_WPA_SUPPLICANT_DBUS_SERVICE_ALIAS must be set}"
  : "${FILE_NETWORKMANAGER_LINK_PRIVACY_CONF:?FILE_NETWORKMANAGER_LINK_PRIVACY_CONF must be set}"

  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/wpa_supplicant/wpa_supplicant.conf)" \
    "${FILE_WPA_SUPPLICANT_CONF}" \
    0644 || return $?
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/wpa_supplicant/p2p-device.conf)" \
    "${FILE_WPA_SUPPLICANT_P2P_DEVICE_CONF}" \
    0644 || return $?
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/systemd/common/system/wpa_supplicant.service.d/override.conf)" \
    "${FILE_WPA_SUPPLICANT_DBUS_SERVICE_OVERRIDE}" \
    0644 || return $?
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/NetworkManager/conf.d/80-link-privacy.conf)" \
    "${FILE_NETWORKMANAGER_LINK_PRIVACY_CONF}" \
    0644 || return $?

  [ -r "${TARGET_ROOT}${FILE_WPA_SUPPLICANT_CONF}" ] ||
    installer_fatal "staged wpa_supplicant config is missing"
  [ -r "${TARGET_ROOT}${FILE_WPA_SUPPLICANT_P2P_DEVICE_CONF}" ] ||
    installer_fatal "staged wpa_supplicant P2P device config is missing"
  [ -r "${TARGET_ROOT}${FILE_WPA_SUPPLICANT_DBUS_SERVICE_OVERRIDE}" ] ||
    installer_fatal "staged wpa_supplicant D-Bus override is missing"
  [ -r "${TARGET_ROOT}${FILE_NETWORKMANAGER_LINK_PRIVACY_CONF}" ] ||
    installer_fatal "staged NetworkManager link privacy policy is missing"
  grep -q '^p2p_disabled=1$' "${TARGET_ROOT}${FILE_WPA_SUPPLICANT_CONF}" ||
    installer_fatal "wpa_supplicant config must disable P2P"
  grep -q '^p2p_disabled=1$' "${TARGET_ROOT}${FILE_WPA_SUPPLICANT_P2P_DEVICE_CONF}" ||
    installer_fatal "wpa_supplicant P2P device config must disable P2P"
  grep -q 'ExecStart=__INSTALLER_PATH_DIR_USR_SBIN__/wpa_supplicant .* -c __INSTALLER_PATH_DIR_ETC__/wpa_supplicant/wpa_supplicant.conf ' \
    "${TARGET_ROOT}${FILE_WPA_SUPPLICANT_DBUS_SERVICE_OVERRIDE}" ||
    installer_fatal "wpa_supplicant D-Bus override must load the managed config"
  if grep -q ' -m __INSTALLER_PATH_DIR_ETC__/wpa_supplicant/p2p-device.conf ' \
    "${TARGET_ROOT}${FILE_WPA_SUPPLICANT_DBUS_SERVICE_OVERRIDE}"; then
    installer_fatal "wpa_supplicant D-Bus override must not start a dedicated P2P device config"
  fi
  grep -q '^wifi\.scan-rand-mac-address=yes$' \
    "${TARGET_ROOT}${FILE_NETWORKMANAGER_LINK_PRIVACY_CONF}" ||
    installer_fatal "NetworkManager link privacy policy must enable Wi-Fi scan MAC randomization"
  grep -q '^ethernet\.cloned-mac-address=random$' \
    "${TARGET_ROOT}${FILE_NETWORKMANAGER_LINK_PRIVACY_CONF}" ||
    installer_fatal "NetworkManager link privacy policy must randomize Ethernet MAC addresses"
  grep -q '^wifi\.cloned-mac-address=random$' \
    "${TARGET_ROOT}${FILE_NETWORKMANAGER_LINK_PRIVACY_CONF}" ||
    installer_fatal "NetworkManager link privacy policy must randomize Wi-Fi MAC addresses"
  if command -v target_systemd_unit_path >__INSTALLER_PATH_DIR_DEV__/null 2>&1 &&
    target_systemd_unit_path wpa_supplicant.service system >__INSTALLER_PATH_DIR_DEV__/null 2>&1
  then
    stage_target_systemd_unit_enabled wpa_supplicant.service system || return $?
    [ -L "${TARGET_ROOT}${FILE_WPA_SUPPLICANT_DBUS_SERVICE_ALIAS}" ] ||
      installer_fatal "wpa_supplicant D-Bus systemd alias is missing: ${FILE_WPA_SUPPLICANT_DBUS_SERVICE_ALIAS}"
  fi
  installer_append_log_category late target_customization info network \
    "staged wpa_supplicant D-Bus policy config=${FILE_WPA_SUPPLICANT_CONF} p2p_config=${FILE_WPA_SUPPLICANT_P2P_DEVICE_CONF} override=${FILE_WPA_SUPPLICANT_DBUS_SERVICE_OVERRIDE}" || true
}

configure_target_smartmontools_defaults() {
  : "${FILE_SMARTMONTOOLS_DEFAULT:?FILE_SMARTMONTOOLS_DEFAULT must be set}"

  if ! test_in_target __INSTALLER_PATH_DIR_BIN__/sh -c 'dpkg-query -s smartmontools >__INSTALLER_PATH_DIR_DEV__/null 2>&1'; then
    return 0
  fi

  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/default/smartmontools)" \
    "${FILE_SMARTMONTOOLS_DEFAULT}" \
    0644
}

late_command_set_grub_arch_policy() {
  arch_class=${INSTALLER_ARCH_CLASS:-$(installer_selected_class_for_purpose arch 2>__INSTALLER_PATH_DIR_DEV__/null || true)}

  [ -n "$arch_class" ] || installer_fatal "selected arch class is unavailable in installer context"

  # shellcheck disable=SC2034
  # Family hooks source this shared file and consume the arch-policy variables.
  case "$arch_class" in
    amd64)
      INSTALLER_GRUB_EFI_TARGET=x86_64-efi
      INSTALLER_GRUB_SHIM_EFI_PATH=/EFI/debian/shimx64.efi
      INSTALLER_GRUB_BINARY_EFI_PATH=/EFI/debian/grubx64.efi
      INSTALLER_GRUB_MOK_MANAGER_EFI_PATH=/EFI/debian/mmx64.efi
      INSTALLER_GRUB_REMOVABLE_BOOT_EFI_PATH=/EFI/BOOT/BOOTX64.EFI
      ;;
    arm64)
      INSTALLER_GRUB_EFI_TARGET=arm64-efi
      INSTALLER_GRUB_SHIM_EFI_PATH=/EFI/debian/shimaa64.efi
      INSTALLER_GRUB_BINARY_EFI_PATH=/EFI/debian/grubaa64.efi
      INSTALLER_GRUB_MOK_MANAGER_EFI_PATH=/EFI/debian/mmaa64.efi
      INSTALLER_GRUB_REMOVABLE_BOOT_EFI_PATH=/EFI/BOOT/BOOTAA64.EFI
      ;;
    *)
      installer_fatal "unsupported arch class for GRUB EFI policy: ${arch_class}"
      ;;
  esac
}

late_command_require_class_policy_env() {
  INSTALL_POLICY_ENV=$(installer_class_policy_env_path)
  [ -r "$INSTALL_POLICY_ENV" ] || installer_fatal "installer install policy env is missing: ${INSTALL_POLICY_ENV}"
  # shellcheck disable=SC1090,SC1091
  . "$INSTALL_POLICY_ENV" || return $?
  [ -n "${INSTALLER_PKGSEL_INCLUDE:-}" ] || installer_fatal "INSTALLER_PKGSEL_INCLUDE is missing from ${INSTALL_POLICY_ENV}"
  [ -n "${INSTALLER_SECURE_BOOT_BOOT_CHAIN_PACKAGES:-}" ] || installer_fatal "INSTALLER_SECURE_BOOT_BOOT_CHAIN_PACKAGES is missing from ${INSTALL_POLICY_ENV}"
  [ -n "${INSTALLER_SECURE_BOOT_TARGET_PACKAGES:-}" ] || installer_fatal "INSTALLER_SECURE_BOOT_TARGET_PACKAGES is missing from ${INSTALL_POLICY_ENV}"
  late_command_set_grub_arch_policy
}

late_command_graphics_initramfs_modules() (
  gpu_classes=${1:-}
  include_nvidia=${2:-false}
  emitted_modules=' '

  emit_unique_module() {
    module_name=$1
    case " $emitted_modules " in
      *" $module_name "*) return 0 ;;
    esac
    emitted_modules="${emitted_modules}${module_name} "
    printf '%s\n' "$module_name"
  }

  for gpu_class in $gpu_classes; do
    case "$gpu_class" in
      intel-uhd)
        emit_unique_module i915
        ;;
      amd-radeon)
        # AMD display drivers are not required for root discovery. Loading them
        # from initramfs can trip PSP TA firmware paths before the full target
        # firmware stack is available, so let udev load them after switch-root.
        ;;
      generic)
        ;;
      *)
        installer_fatal "unsupported gpu class: ${gpu_class}"
        ;;
    esac
  done

  case "$include_nvidia" in
    true)
      emit_unique_module nvidia
      emit_unique_module nvidia_modeset
      emit_unique_module nvidia_uvm
      emit_unique_module nvidia_drm
      ;;
  esac
)

install_target_firstboot_logger() {
  : "${FILE_FIRSTBOOT_HELPER:?FILE_FIRSTBOOT_HELPER must be set}"
  : "${FILE_FIRSTBOOT_SERVICE:?FILE_FIRSTBOOT_SERVICE must be set}"
  : "${FILE_SECONDBOOT_HELPER:?FILE_SECONDBOOT_HELPER must be set}"
  : "${FILE_SECONDBOOT_SERVICE:?FILE_SECONDBOOT_SERVICE must be set}"
  : "${FILE_INITRAMFS_HEALTH_COMMON:?FILE_INITRAMFS_HEALTH_COMMON must be set}"
  : "${FILE_INITRAMFS_HEALTH_INIT_TOP:?FILE_INITRAMFS_HEALTH_INIT_TOP must be set}"
  : "${FILE_INITRAMFS_HEALTH_INIT_PREMOUNT:?FILE_INITRAMFS_HEALTH_INIT_PREMOUNT must be set}"
  : "${FILE_INITRAMFS_HEALTH_LOCAL_TOP:?FILE_INITRAMFS_HEALTH_LOCAL_TOP must be set}"
  : "${FILE_INITRAMFS_HEALTH_LOCAL_BLOCK:?FILE_INITRAMFS_HEALTH_LOCAL_BLOCK must be set}"
  : "${FILE_INITRAMFS_HEALTH_LOCAL_PREMOUNT:?FILE_INITRAMFS_HEALTH_LOCAL_PREMOUNT must be set}"
  : "${FILE_INITRAMFS_HEALTH_LOCAL_BOTTOM:?FILE_INITRAMFS_HEALTH_LOCAL_BOTTOM must be set}"
  : "${FILE_INITRAMFS_HEALTH_INIT_BOTTOM:?FILE_INITRAMFS_HEALTH_INIT_BOTTOM must be set}"
  : "${DIR_INITRAMFS_SCRIPTS:?DIR_INITRAMFS_SCRIPTS must be set}"
  : "${DIR_FIRSTBOOT_LIB:?DIR_FIRSTBOOT_LIB must be set}"
  : "${DIR_FIRSTBOOT_LOG:?DIR_FIRSTBOOT_LOG must be set}"
  : "${DIR_FIRSTBOOT_STATE:?DIR_FIRSTBOOT_STATE must be set}"
  : "${DIR_INSTALL_LOG:?DIR_INSTALL_LOG must be set}"
  : "${LOG_INITRAMFS_DIR:?LOG_INITRAMFS_DIR must be set}"

  # Finish-install normalizes every active source after vendor setup.
  stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/libexec/common/apt-repo-local-normalize-sources)" \
    "${DIR_USR_LOCAL_LIBEXEC}/apt-repo-local-normalize-sources" 0755

  # Shared by system and desktop command wrappers on every storage family.
  stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/lib/common/perl5/site_perl/runtime/Managed/Process.pm)" \
    "${DIR_PERL5_SITE_PERL}/runtime/Managed/Process.pm" 0644
  # Staged across the first reboot only; secondboot removes this entire surface.
  install -d -m 0700 "${TARGET_ROOT}${DIR_FIRSTBOOT}" "${TARGET_ROOT}${DIR_FIRSTBOOT_BIN}"
  stage_target_asset "$(installer_repo_file_value scripts/firstboot/assets/etc/apparmor.d/firstboot.tmpl)" \
    __INSTALLER_PATH_DIR_ETC__/apparmor.d/firstboot 0644
  if security_target_is_desktop; then
    run_in_target "apply selected AppArmor mode to staged first-boot policy" \
      "${DIR_USR_LOCAL_LIBEXEC}/apparmor-modes-run" --no-reload
  fi
  installer_assert_class_plan
  firstboot_roles=$(installer_plan_roles | tr '\n' ' ')
  firstboot_roles=${firstboot_roles% }
  installer_asset_publish scalar "$(installer_repo_file_value scripts/firstboot/firstboot.sh)" "${FILE_FIRSTBOOT_HELPER}" 0755 \
    FIRSTBOOT_RELEASE_ID "$INSTALLER_RELEASE_ID"
  install -d -m 0755 "${TARGET_ROOT}${DIR_FIRSTBOOT_LIB}"
  stage_target_asset "$(installer_repo_file_value scripts/firstboot/logging.sh)" "${DIR_FIRSTBOOT_LIB}/logging.sh" 0644
  for firstboot_stage in \
    01-early.sh \
    02-collect.sh \
    03-network.sh \
    04-validation.sh \
    05-cleanup.sh
  do
    installer_asset_publish scalar "$(installer_repo_asset_path DIR_SCRIPTS_FIRSTBOOT "${firstboot_stage}")" "${DIR_FIRSTBOOT_LIB}/${firstboot_stage}" 0755 \
      FIRSTBOOT_RELEASE_ID "$INSTALLER_RELEASE_ID" FIRSTBOOT_ROLE_IDS "$firstboot_roles" \
      FIRSTBOOT_HOST_VARIANT "$INSTALLER_HOST_VARIANT" FIRSTBOOT_SUITE "$INSTALLER_SUITE"
  done
  unset firstboot_stage firstboot_roles
  stage_target_asset "$(installer_repo_file_value scripts/firstboot/import-initramfs.py.tmpl)" \
    "${DIR_FIRSTBOOT_LIB}/import-initramfs.py" 0644
  stage_target_asset "$(installer_repo_file_value scripts/firstboot/service-account-processes.py)" \
    "${DIR_FIRSTBOOT_LIB}/service-account-processes.py" 0644

  stage_target_asset "$(installer_repo_file_value scripts/firstboot/assets/etc/initramfs-tools/scripts/installer-health-common)" "${FILE_INITRAMFS_HEALTH_COMMON}" 0644
  stage_target_asset "$(installer_repo_file_value scripts/firstboot/assets/etc/initramfs-tools/scripts/init-top/90-installer-health)" "${FILE_INITRAMFS_HEALTH_INIT_TOP}" 0755
  stage_target_asset "$(installer_repo_file_value scripts/firstboot/assets/etc/initramfs-tools/scripts/init-premount/90-installer-health)" "${FILE_INITRAMFS_HEALTH_INIT_PREMOUNT}" 0755
  stage_target_asset "$(installer_repo_file_value scripts/firstboot/assets/etc/initramfs-tools/scripts/local-top/90-installer-health)" "${FILE_INITRAMFS_HEALTH_LOCAL_TOP}" 0755
  stage_target_asset "$(installer_repo_file_value scripts/firstboot/assets/etc/initramfs-tools/scripts/local-block/90-installer-health)" "${FILE_INITRAMFS_HEALTH_LOCAL_BLOCK}" 0755
  stage_target_asset "$(installer_repo_file_value scripts/firstboot/assets/etc/initramfs-tools/scripts/local-premount/90-installer-health)" "${FILE_INITRAMFS_HEALTH_LOCAL_PREMOUNT}" 0755
  stage_target_asset "$(installer_repo_file_value scripts/firstboot/assets/etc/initramfs-tools/scripts/local-bottom/90-installer-health)" "${FILE_INITRAMFS_HEALTH_LOCAL_BOTTOM}" 0755
  stage_target_asset "$(installer_repo_file_value scripts/firstboot/assets/etc/initramfs-tools/scripts/init-bottom/90-installer-health)" "${FILE_INITRAMFS_HEALTH_INIT_BOTTOM}" 0755
  stage_target_asset "$(installer_repo_file_value scripts/firstboot/assets/etc/systemd/system/firstboot.service)" "${FILE_FIRSTBOOT_SERVICE}" 0644
  installer_asset_publish scalar "$(installer_repo_file_value scripts/firstboot/assets/var/lib/firstboot/bin/secondboot-cleanup)" "${FILE_SECONDBOOT_HELPER}" 0755 \
    FIRSTBOOT_RELEASE_ID "$INSTALLER_RELEASE_ID"
  stage_target_asset "$(installer_repo_file_value scripts/firstboot/assets/etc/systemd/system/secondboot.service)" "${FILE_SECONDBOOT_SERVICE}" 0644
  stage_target_asset "$(installer_repo_file_value scripts/firstboot/assets/etc/systemd/system/secondboot.path)" __INSTALLER_PATH_DIR_ETC__/systemd/system/secondboot.path 0644

  install -d -m 0700 \
    "${TARGET_ROOT}${LOG_INITRAMFS_DIR}" \
    "${TARGET_ROOT}${DIR_FIRSTBOOT_LOG}" \
    "${TARGET_ROOT}${DIR_FIRSTBOOT_STATE}"
  if installer_logging_enabled; then
    install -d -m 0700 "${TARGET_ROOT}${DIR_INSTALL_LOG}"
  fi

  stage_target_systemd_unit_enabled firstboot.service system
  stage_target_systemd_unit_enabled secondboot.service system
  stage_target_systemd_unit_enabled secondboot.path system
  installer_append_log_category late target_customization info firstboot "staged target first-boot wrapper ${FILE_FIRSTBOOT_HELPER}" || true
  installer_append_log_category late target_customization info secondboot "staged target cleanup service ${FILE_SECONDBOOT_SERVICE} automatic_after_completed_enrollment=true" || true
  installer_append_log_category bootloader bootloader info initramfs "staged initramfs health hooks under ${DIR_INITRAMFS_SCRIPTS}" || true
}

# Preserve NVIDIA VRAM only together with the vendor's complete sleep protocol.
# Both Btrfs/VM and F2FS late paths call this after staging GPU configuration.
configure_target_nvidia_power_management() (
  enabled=${1:-false}
  case "$enabled" in
    true|false) ;;
    *) installer_fatal 'NVIDIA power-management selection must be boolean'; exit 1 ;;
  esac
  if [ "$enabled" != true ]; then
    # Remove only our managed target assets, never installer __INSTALLER_PATH_DIR_ETC__ or vendor units.
    for phase in suspend suspend-then-hibernate hibernate resume; do
      remove_target_asset "$(installer_systemd_dropin_dir system "nvidia-${phase}.service")/20-vram.conf"
    done
    for mode in suspend suspend-then-hibernate hibernate hybrid-sleep; do
      remove_target_asset "$(installer_systemd_dropin_dir system "systemd-${mode}.service")/20-nvidia-preserve.conf"
    done
    remove_target_asset __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/70-nvidia-vram.conf
    remove_target_asset "${DIR_USR_LOCAL_LIBEXEC}/nvidia-vram-check"
    return 0
  fi
  stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/libexec/common/nvidia-vram-check)" "${DIR_USR_LOCAL_LIBEXEC}/nvidia-vram-check" 0755
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/tmpfiles.d/desktop/70-nvidia-vram.conf)" __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/70-nvidia-vram.conf 0644
  for phase in suspend suspend-then-hibernate hibernate resume; do
    stage_target_asset "$(installer_repo_asset_path DIR_TARGET_UNIT "nvidia-${phase}.service.d/20-vram.conf")" \
      "$(installer_systemd_dropin_dir system "nvidia-${phase}.service")/20-vram.conf" 0644
  done
  for mode in suspend suspend-then-hibernate hibernate hybrid-sleep; do
    stage_target_asset "$(installer_repo_asset_path DIR_TARGET_UNIT "systemd-${mode}.service.d/20-nvidia-preserve.conf")" \
      "$(installer_systemd_dropin_dir system "systemd-${mode}.service")/20-nvidia-preserve.conf" 0644
  done
  run_in_target "enable NVIDIA video-memory preservation and prepare disk backing" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
    if [ -L __INSTALLER_PATH_DIR_VAR__/lib/nvidia-vram ] ||
       [ "$(readlink -f __INSTALLER_PATH_DIR_VAR__/lib)" != __INSTALLER_PATH_DIR_VAR__/lib ]; then
      printf "fatal: NVIDIA backing path is indirect\n" >&2
      exit 1
    fi
    install -d -m 0700 -o root -g root __INSTALLER_PATH_DIR_VAR__/lib/nvidia-vram
    # Package installation owns the vendor files. Enable them directly and
    # preserve systemctl errors instead of probing package contents again.
    # Offline enabling is intentional: do not suspend or start a bus in d-i.
    systemctl --no-reload enable nvidia-suspend.service nvidia-suspend-then-hibernate.service nvidia-hibernate.service nvidia-resume.service
  '
)

# Shared end of the family boot-policy publication sequence.
stage_target_common_boot_policy() {
  case "${1:-}" in true|false) ;;
    *) installer_fatal 'boot-policy publication requires an explicit NVIDIA selection'; return 1 ;;
  esac
  stage_target_asset_if_path "$(installer_hardware_asset_path gpu intel-uhd etc/default/grub.d/85-gpu-intel.cfg)" "${FILE_GRUB_GPU_INTEL_DROPIN:-}" "${DIR_GRUB_DEFAULT}/85-gpu-intel.cfg" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path gpu amd-radeon etc/default/grub.d/86-gpu-amd.cfg)" "${FILE_GRUB_GPU_AMD_DROPIN:-}" "${DIR_GRUB_DEFAULT}/86-gpu-amd.cfg" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path gpu nvidia etc/default/grub.d/87-gpu-nvidia.cfg)" "${FILE_GRUB_GPU_NVIDIA_DROPIN:-}" "${DIR_GRUB_DEFAULT}/87-gpu-nvidia.cfg" 0644

  configure_target_nvidia_power_management "$1"

  stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/libexec/common/swap-fallback-setup.tmpl)" "${FILE_SWAP_FALLBACK_HELPER}" 0755
  render_target_template "$TMP_ENV_DIR/swap-fallback.service.tmpl" "${TARGET_ROOT}${FILE_SWAP_FALLBACK_SERVICE}" 0644

  stage_target_common_storage_maintenance_assets
}
