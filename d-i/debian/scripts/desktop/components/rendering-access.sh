#!/bin/sh
# Sourced installer module; edit this file directly.

desktop_account_relative_home_path() (
  # Retain the selected directory layout without binding shared defaults to
  # the primary account. Account provisioning resolves this typed field in
  # the HOME copy before the UI application can consume it.
  case "$1" in
    "$ACCOUNT_HOME"/*) account_relative=${1#"$ACCOUNT_HOME"/} ;;
    *) installer_fatal 'desktop default directory is outside the selected account HOME'; exit 1 ;;
  esac
  case "$account_relative" in
    ''|.|..|/*|*/../*|../*|*/..|*//*|*[!A-Za-z0-9_./-]*)
      installer_fatal 'unsafe account-relative desktop directory'; exit 1 ;;
  esac
  printf '$HOME/%s\n' "$account_relative"
)

desktop_target_hostname() {
  target_hostname=

  if [ -r ${TARGET_ROOT}${DIR_ETC}/hostname ]; then
    target_hostname=$(sed -n '1{s/[[:space:]]*$//;p;q;}' ${TARGET_ROOT}${DIR_ETC}/hostname)
  fi
  if [ -z "$target_hostname" ] && [ -n "${SYSTEM_HOSTNAME:-}" ]; then
    target_hostname=$SYSTEM_HOSTNAME
  fi

  case "$target_hostname" in
    ''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-]*)
      installer_fatal "target hostname is unavailable or invalid for desktop local mail delivery"
      ;;
  esac

  printf '%s\n' "$target_hostname"
}

desktop_mailname_value() {
  target_hostname=$(desktop_target_hostname)

  if [ -z "${SYSTEM_DOMAIN:-}" ]; then
    printf '%s\n' "$target_hostname"
    return 0
  fi

  case "$SYSTEM_DOMAIN" in
    ''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-]*|.*|*.|*..*)
      installer_fatal "SYSTEM_DOMAIN is invalid for desktop local mail delivery"
      ;;
  esac

  printf '%s.%s\n' "$target_hostname" "$SYSTEM_DOMAIN"
}

desktop_optional_env_assignment_line() {
  key=$1
  value=$2

  [ -n "$value" ] || return 0
  printf '%s=%s\n' "$key" "$value"
}

desktop_shell_config_value() {
  shell_single_quote "$1"
}

desktop_assert_no_unresolved_template_placeholders() {
  rendered_path=$1
  label=$2

  target_asset_assert_no_unresolved_installer_placeholders "$rendered_path" "$label"
}

# Only Labwc's three declared XML line blocks are deferred past scalar
# replacement. Complete them in the private candidate, before publication.
desktop_render_declared_template_blocks() (
  block_source=$1; block_candidate=$2
  [ "$block_source" = "$(installer_repo_file_value FILE_TARGET_SKEL_LABWC_RC_TMPL)" ] || {
    installer_fatal 'desktop template has no declared deferred consumer'; return 1;
  }
  replace_placeholder_line_block "$block_candidate" \
    '__INSTALLER_LABWC_WORKSPACE_NAME_LINES__' "$(desktop_labwc_workspace_name_lines)" required || return 1
  replace_placeholder_line_block "$block_candidate" \
    '__INSTALLER_LABWC_WORKSPACE_KEYBIND_LINES__' "$(desktop_labwc_workspace_keybind_lines)" required || return 1
  replace_placeholder_line_block "$block_candidate" \
    '__INSTALLER_LABWC_RECORDING_KEYBIND_LINES__' "$(desktop_labwc_recording_keybind_lines)" required
)

desktop_render_target_template_impl() {
  source_path=$1
  target_path=$2
  mode=$3
  allow_deferred_placeholders=$4
  shift 4
  tmp_source="${TMP_ENV_DIR}/desktop-template.$$.src"
  tmp_rendered="${TMP_ENV_DIR}/desktop-template.$$.dst"

  [ $(( $# % 2 )) -eq 0 ] || installer_fatal "desktop template placeholders must be name/value pairs: ${source_path}"
  if ! fetch_hook "$source_path" "$tmp_source"; then
    rm -f "$tmp_source" "$tmp_rendered"
    return 1
  fi
  if ! installer_apply_scalar_placeholders "$tmp_source" "$tmp_rendered" "$@"; then
    rm -f "$tmp_source" "$tmp_rendered"
    installer_fatal "failed to render desktop template ${source_path}"
  fi

  if [ "$allow_deferred_placeholders" = true ]; then
    desktop_render_declared_template_blocks "$source_path" "$tmp_rendered" || return 1
  fi
  desktop_assert_no_unresolved_template_placeholders "$tmp_rendered" "desktop template ${source_path}"
  ensure_target_asset_parent "$target_path"
  rendered_target=$(target_asset_host_path "$target_path")
  # The primary user's fully configured input is retained independently from
  # the private future-user template. Both are rendered from tmp_source with
  # the same shared renderer; neither reads the installed template as input.
  installer_capture_primary_default "$tmp_rendered" "$target_path" "$mode"
  case "$rendered_target" in
    "${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/"*)
      future_fields=$#
      future_changed=false
      while [ "$future_fields" -gt 0 ]; do
        future_key=$1; future_value=$2; shift 2
        future_fields=$((future_fields - 2))
        case "$future_key" in
          ACCOUNT_HOME) future_value='$HOME'; future_changed=true ;;
          ACCOUNT_USERNAME) future_value='$USER'; future_changed=true ;;
          DIR_HOME_*)
            future_value=$(desktop_account_relative_home_path "$future_value") || return 1
            future_changed=true
            ;;
        esac
        set -- "$@" "$future_key" "$future_value"
      done
      if [ "$future_changed" = true ]; then
        if ! installer_apply_scalar_placeholders "$tmp_source" "$tmp_rendered" "$@"; then
          rm -f "$tmp_source" "$tmp_rendered"
          installer_fatal "failed to render reusable account template ${source_path}"
        fi
        desktop_assert_no_unresolved_template_placeholders "$tmp_rendered" "future account template ${source_path}"
      fi
      ;;
  esac
  # A named stdin source is an authenticated, completely rendered candidate.
  # The shared boundary owns its atomic rename and final ownership record;
  # the primary/future-account split above has already captured its default.
  publish_target_asset "$source_path" "$target_path" "$mode" stdin <"$tmp_rendered" || return 1
  rm -f "$tmp_source" "$tmp_rendered"
  desktop_log "rendered_template source=${source_path} target=${target_path} mode=${mode}"
}

desktop_render_target_template() {
  source_path=$1
  target_path=$2
  mode=$3
  shift 3

  desktop_render_target_template_impl "$source_path" "$target_path" "$mode" false "$@"
}

desktop_render_target_template_deferred() {
  source_path=$1
  target_path=$2
  mode=$3
  shift 3

  desktop_render_target_template_impl "$source_path" "$target_path" "$mode" true "$@"
}

desktop_render_role_target_template() {
  role_relpath=$1
  target_path=$2
  mode=$3
  desktop_role_owns_target "$target_path" || return 0
  shift 3
  source_path=$(installer_repo_asset_path DIR_HOOKS_TARGET "$role_relpath")

  desktop_render_target_template "$source_path" "$target_path" "$mode" "$@"
}

desktop_render_role_target_template_deferred() {
  role_relpath=$1
  target_path=$2
  mode=$3
  desktop_role_owns_target "$target_path" || return 0
  shift 3
  source_path=$(installer_repo_asset_path DIR_HOOKS_TARGET "$role_relpath")

  desktop_render_target_template_deferred "$source_path" "$target_path" "$mode" "$@"
}

desktop_render_shared_target_template() {
  shared_relpath=$1
  target_path=$2
  mode=$3
  shift 3
  source_path=$(installer_repo_asset_path DIR_HOOKS_TARGET "$shared_relpath")

  desktop_render_target_template "$source_path" "$target_path" "$mode" "$@"
}

desktop_polkit_managed_rule_files() {
  cat <<'EOF'
00-admin-identities.rules
03-labwc-power.rules
05-active-local-gate.rules
10-pkexec.rules
20-login1-power.rules
40-networkmanager.rules
50-usb-policy.rules
55-software-management.rules
60-system-services-identity.rules
70-hardware-peripherals.rules
EOF
}

desktop_managed_nmap_script_files() {
  cat <<'EOF'
admin-surface-policy.nse
approved-services.nse
database-exposure-policy.nse
http-security-headers.nse
name-resolution-policy.nse
plaintext-service-policy.nse
service-inventory.nse
tls-service-policy.nse
EOF
}

desktop_stage_managed_nmap_scripts() {
  managed_nmap_scripts=$(desktop_managed_nmap_script_files)
  [ -n "$managed_nmap_scripts" ] || installer_fatal "desktop managed Nmap script set is empty"

  for managed_nmap_script in $managed_nmap_scripts; do
    case "$managed_nmap_script" in
      admin-surface-policy.nse|approved-services.nse|database-exposure-policy.nse|http-security-headers.nse|name-resolution-policy.nse|plaintext-service-policy.nse|service-inventory.nse|tls-service-policy.nse) ;;
      *)
        installer_fatal "unsafe desktop managed Nmap script name: ${managed_nmap_script:-unset}"
        ;;
    esac
    case "$managed_nmap_script" in
      *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]*|*..*|.*|*/*)
        installer_fatal "unsafe desktop managed Nmap script name: ${managed_nmap_script}"
        ;;
    esac
    desktop_stage_role_asset \
      "usr/local/share/nmap/scripts/${managed_nmap_script}" \
      "__INSTALLER_PATH_DIR_USR_LOCAL__/share/nmap/scripts/${managed_nmap_script}" \
      0644
  done
  unset managed_nmap_script managed_nmap_scripts
}

desktop_validate_managed_polkit_rule_name() {
  rule_name=$1

  case "$rule_name" in
    [0123456789][0123456789]-*.rules) ;;
    *)
      installer_fatal "unsafe desktop polkit rule name: ${rule_name:-unset}"
      ;;
  esac
  case "$rule_name" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+-]*|*..*|.*|*/*)
      installer_fatal "unsafe desktop polkit rule name: ${rule_name}"
      ;;
  esac
}

desktop_require_safe_thunar_eject_version() {
  desktop_thunar_minimum_version=4.20.9

  desktop_thunar_installed_status=$(
    capture_in_target \
      "read installed Thunar package status" \
      __INSTALLER_PATH_DIR_USR_BIN__/dpkg-query \
      -W \
      -f='${Status}' \
      thunar
  ) || return 1
  [ "$desktop_thunar_installed_status" = "install ok installed" ] || {
    installer_fatal "Thunar is not fully installed for external-drive handling"
    return 1
  }

  desktop_thunar_installed_version=$(
    capture_in_target \
      "read installed Thunar package version" \
      __INSTALLER_PATH_DIR_USR_BIN__/dpkg-query \
      -W \
      -f='${Version}' \
      thunar
  ) || return 1
  [ -n "$desktop_thunar_installed_version" ] &&
    [ "${#desktop_thunar_installed_version}" -le 128 ] || {
    installer_fatal "installed Thunar package has an invalid version field"
    return 1
  }
  test_in_target \
    __INSTALLER_PATH_DIR_USR_BIN__/dpkg \
    --validate-version \
    "$desktop_thunar_installed_version" || {
    installer_fatal \
      "installed Thunar package version is invalid: $desktop_thunar_installed_version"
    return 1
  }
  if ! test_in_target \
    __INSTALLER_PATH_DIR_USR_BIN__/dpkg \
    --compare-versions \
    "$desktop_thunar_installed_version" \
    ge \
    "$desktop_thunar_minimum_version"
  then
    # Thunar 4.19.3 fixed the ext4 eject crash (Xfce #1347). Requiring
    # 4.20.9 also includes the later asynchronous drive-operation fix (#1816).
    installer_fatal \
      "Thunar ${desktop_thunar_installed_version} is older than the safe external-drive minimum ${desktop_thunar_minimum_version}"
    return 1
  fi

  desktop_log \
    "validated Thunar external-drive runtime version=${desktop_thunar_installed_version} minimum=${desktop_thunar_minimum_version}"
  unset \
    desktop_thunar_installed_status \
    desktop_thunar_installed_version \
    desktop_thunar_minimum_version
}

desktop_configure_usb_media_access() {
  : "${ACCOUNT_USERNAME:?ACCOUNT_USERNAME must be set}"
  : "${ACCOUNT_DEFAULT_GROUPS:?ACCOUNT_DEFAULT_GROUPS must be set}"
  : "${DIR_UDISKS2:?DIR_UDISKS2 must be set}"
  : "${DIR_UDEV_RULES:?DIR_UDEV_RULES must be set}"
  : "${DIR_POLKIT_RULES_D:?DIR_POLKIT_RULES_D must be set}"
  : "${DIR_POLKIT_LOCAL_RULES_D:?DIR_POLKIT_LOCAL_RULES_D must be set}"
  : "${DIR_POLKIT_RUNTIME_RULES_D:?DIR_POLKIT_RUNTIME_RULES_D must be set}"
  : "${DIR_RUN_MEDIA:?DIR_RUN_MEDIA must be set}"
  : "${DIR_DATA_RUN_MNT:?DIR_DATA_RUN_MNT must be set}"
  : "${FILE_UDISKS2_CONF:?FILE_UDISKS2_CONF must be set}"
  : "${FILE_UDISKS2_MOUNT_OPTIONS_CONF:?FILE_UDISKS2_MOUNT_OPTIONS_CONF must be set}"
  : "${FILE_UDEV_UDISKS_BEHAVIOR_RULES:?FILE_UDEV_UDISKS_BEHAVIOR_RULES must be set}"
  : "${FILE_POLKIT_RUNTIME_TMPFILES:?FILE_POLKIT_RUNTIME_TMPFILES must be set}"

  desktop_require_safe_thunar_eject_version

  case "$ACCOUNT_USERNAME" in
    [abcdefghijklmnopqrstuvwxyz_]*) ;;
    *)
      installer_fatal "ACCOUNT_USERNAME must start with a lowercase letter or underscore"
      ;;
  esac
  case "$ACCOUNT_USERNAME" in
    *[!abcdefghijklmnopqrstuvwxyz0123456789_-]*)
      installer_fatal "ACCOUNT_USERNAME contains unsupported characters for desktop USB media policy"
      ;;
  esac
  case " $ACCOUNT_DEFAULT_GROUPS " in
    *" usbadmin "*)
      installer_fatal "ACCOUNT_DEFAULT_GROUPS must not include usbadmin; add users to usbadmin through an explicit hardware addon"
      ;;
  esac

  # shellcheck disable=SC2016
  run_in_target "configure desktop USB media authorization groups" __INSTALLER_PATH_DIR_BIN__/sh -c '
set -eu
account_user=$1

for group_name in usbmedia usbadmin; do
  getent group "$group_name" >__INSTALLER_PATH_DIR_DEV__/null 2>&1 || groupadd --system "$group_name"
done
usermod -a -G usbmedia "$account_user"
' sh "$ACCOUNT_USERNAME"

  install -d -m 0755 \
    "${TARGET_ROOT}${DIR_UDISKS2}" \
    "${TARGET_ROOT}${DIR_UDEV_RULES}" \
    "${TARGET_ROOT}${DIR_POLKIT_RULES_D}" \
    "${TARGET_ROOT}${DIR_POLKIT_LOCAL_RULES_D}"

  desktop_stage_role_asset FILE_TARGET_UDISKS2 "$FILE_UDISKS2_CONF" 0644
  desktop_stage_role_asset FILE_TARGET_UDISKS2_MOUNT_OPTIONS "$FILE_UDISKS2_MOUNT_OPTIONS_CONF" 0644
  desktop_stage_role_asset FILE_TARGET_UDEV_RULES_D_90_UDISKS_BEHAVIOR "$FILE_UDEV_UDISKS_BEHAVIOR_RULES" 0644
  desktop_render_role_target_template \
    FILE_TARGET_TMPFILES_D_70_POLKIT_RUNTIME_TMPL \
    "$FILE_POLKIT_RUNTIME_TMPFILES" \
    0644 \
    DIR_POLKIT_RUNTIME_RULES_D "$DIR_POLKIT_RUNTIME_RULES_D" \
    DIR_POLKIT_LOCAL_RULES_D "$DIR_POLKIT_LOCAL_RULES_D"
  desktop_render_role_target_template \
    FILE_TARGET_TMPFILES_D_25_DESKTOP_MEDIA_RUNTIME_TMPL \
    __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/25-desktop-media-runtime.conf \
    0644 \
    DIR_RUN_MEDIA "$DIR_RUN_MEDIA" \
    DIR_DATA_RUN_MNT "$DIR_DATA_RUN_MNT" \
    ACCOUNT_USERNAME "$ACCOUNT_USERNAME"
  polkit_managed_rule_files=$(desktop_polkit_managed_rule_files)
  [ -n "$polkit_managed_rule_files" ] || installer_fatal "desktop managed polkit rule set is empty"
  for polkit_rule in $polkit_managed_rule_files; do
    desktop_validate_managed_polkit_rule_name "$polkit_rule"
    desktop_stage_role_asset \
      "etc/polkit-1/rules.d/${polkit_rule}" \
      "${DIR_POLKIT_RULES_D}/${polkit_rule}" \
      0644
  done
  unset polkit_rule polkit_managed_rule_files
  desktop_log "configured desktop USB media and polkit policy user=${ACCOUNT_USERNAME}"
}

desktop_stage_primary_account_pool_storage_policy() {
  : "${ACCOUNT_USERNAME:?ACCOUNT_USERNAME must be set}"
  : "${DIR_POOL_BUILD:?DIR_POOL_BUILD must be set}"
  : "${DIR_POOL_CACHE:?DIR_POOL_CACHE must be set}"
  : "${DIR_POOL_DB:?DIR_POOL_DB must be set}"

  command -v normalize_target_tmpfiles_directory_policy >__INSTALLER_PATH_DIR_DEV__/null 2>&1 ||
    installer_fatal "desktop account pool storage requires the shared tmpfiles normalizer"

  desktop_render_role_target_template \
    FILE_TARGET_TMPFILES_D_75_DESKTOP_POOL_STORAGE_TMPL \
    __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/75-desktop-pool-storage.conf \
    0644 \
    ACCOUNT_USERNAME "$ACCOUNT_USERNAME" \
    DIR_POOL_BUILD "$DIR_POOL_BUILD" \
    DIR_POOL_CACHE "$DIR_POOL_CACHE" \
    DIR_POOL_DB "$DIR_POOL_DB"
  normalize_target_tmpfiles_directory_policy \
    __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/75-desktop-pool-storage.conf \
    "desktop primary-account pool storage"
  desktop_log \
    "staged_desktop_pool_storage policy=__INSTALLER_PATH_DIR_ETC__/tmpfiles.d/75-desktop-pool-storage.conf account=${ACCOUNT_USERNAME} group=devops shared_mode=2770 build_tmp=${DIR_POOL_BUILD}/${ACCOUNT_USERNAME}/tmp cache_tmp=${DIR_POOL_CACHE}/${ACCOUNT_USERNAME}/tmp private_tmp_mode=0700"
}

desktop_stage_network_profile_storage_policy() {
  command -v normalize_target_tmpfiles_directory_policy >__INSTALLER_PATH_DIR_DEV__/null 2>&1 ||
    installer_fatal "desktop network profile storage requires the shared tmpfiles normalizer"

  desktop_stage_role_asset \
    FILE_TARGET_TMPFILES_D_40_NETWORK_PROFILES \
    __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/40-network-profiles.conf \
    0644
  normalize_target_tmpfiles_directory_policy \
    __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/40-network-profiles.conf \
    "desktop network profile storage"
  desktop_log \
    "staged_network_profile_storage wireguard_root=__INSTALLER_PATH_DIR_DATA__/config/network/wireguard owner=root group=devops mode=0750"
}

desktop_stage_var_cache_policy() {
  command -v normalize_target_tmpfiles_directory_policy >__INSTALLER_PATH_DIR_DEV__/null 2>&1 ||
    installer_fatal "desktop var-cache policy requires the shared tmpfiles normalizer"

  # Package installation must create these accounts before the desktop role
  # applies the cache policy. Fail closed rather than leaving named tmpfiles
  # ownership unresolved on the fresh target.
  # shellcheck disable=SC2016
  run_in_target_quiet "validate desktop var-cache owners" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
for account_name in man fwupd-refresh; do
  getent passwd "$account_name" >__INSTALLER_PATH_DIR_DEV__/null 2>&1 || {
    printf "fatal: desktop var-cache owner account is missing: %s\n" "$account_name" >&2
    exit 1
  }
  getent group "$account_name" >__INSTALLER_PATH_DIR_DEV__/null 2>&1 || {
    printf "fatal: desktop var-cache owner group is missing: %s\n" "$account_name" >&2
    exit 1
  }
done
' sh

  desktop_stage_role_asset \
    FILE_TARGET_TMPFILES_D_50_DESKTOP_VAR_CACHE \
    __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/50-desktop-var-cache.conf \
    0644
  desktop_stage_role_asset \
    FILE_TARGET_TMPFILES_D_MAN_DB \
    __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/man-db.conf \
    0644
  normalize_target_tmpfiles_directory_policy \
    __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/50-desktop-var-cache.conf \
    "desktop var-cache directories"
  normalize_target_tmpfiles_directory_policy \
    __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/man-db.conf \
    "desktop man-db cache directory"
  desktop_log "staged_desktop_var_cache policy=__INSTALLER_PATH_DIR_ETC__/tmpfiles.d/50-desktop-var-cache.conf man_policy=__INSTALLER_PATH_DIR_ETC__/tmpfiles.d/man-db.conf"
}
