#!/bin/sh
# Sourced installer module; edit this file directly.

# Native btop versions share the XDG config contract. Keep one authored copy
# per profile; relative views survive fresh account copying
# and appearance updates without runtime config publication.
desktop_stage_btop_profiles() {
  for btop_profile in cpu memory; do
    btop_config_host=$(target_asset_host_path "__INSTALLER_PATH_DIR_ETC_SKEL_DESKTOP_CONFIG__/btop/btop-${btop_profile}.conf") || return $?
    [ -f "$btop_config_host" ] && [ ! -L "$btop_config_host" ] || {
      installer_fatal "btop profile config is unavailable or unsafe: $btop_profile"
      return 1
    }
    btop_target="../../../btop-${btop_profile}.conf"
    btop_destination="__INSTALLER_PATH_DIR_ETC_SKEL_DESKTOP_CONFIG__/btop/profiles/${btop_profile}/btop/btop.conf"
    # Native btop owns its theme directory; packaged/builtin themes retain
    # their normal lookup. Only regular config files are relative link targets.
    ensure_target_asset_parent "${btop_destination%/*}/themes/.installer-parent" || return $?
    btop_host=$(target_asset_entry_host_path "$btop_destination") || return $?
    if [ -L "$btop_host" ] && [ "$(readlink -- "$btop_host")" = "$btop_target" ]; then
      continue
    fi
    if [ -e "$btop_host" ] || [ -L "$btop_host" ]; then
      installer_fatal "btop profile view conflicts with a staged asset: ${btop_profile}/btop.conf"
      return 1
    fi
    ln -sT -- "$btop_target" "$btop_host" || return $?
  done
  unset btop_profile btop_target btop_destination btop_host btop_config_host
}

desktop_stage_session_repairs() {
  for public_directory in __INSTALLER_PATH_DIR_ETC__/udev __INSTALLER_PATH_DIR_ETC__/udev/hwdb.d; do
    ensure_target_asset_parent "${public_directory}/.installer-parent"
    public_host=$(target_asset_host_path "$public_directory")
    [ ! -L "$public_host" ] || installer_fatal "unsafe system configuration directory: $public_directory"
    chown root:root "$public_host"
    chmod 0755 "$public_host"
  done
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-wallpaper-control __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-wallpaper-control 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-notification-send.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-notification-send 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-configure-session-repairs __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-configure-session-repairs 0755
  desktop_stage_role_asset hooks/target/etc/security/sudo-i.conf __INSTALLER_PATH_DIR_ETC__/security/sudo-i.conf 0644
  desktop_stage_role_asset hooks/target/etc/security/cron-session.conf __INSTALLER_PATH_DIR_ETC__/security/cron-session.conf 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml 0644
  run_in_target "build target keyboard hardware database" __INSTALLER_PATH_DIR_USR_BIN__/systemd-hwdb --strict update
  run_in_target "configure managed session repairs" __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-configure-session-repairs \
    "$ACCOUNT_USERNAME"
}

desktop_stage_wlsunset() {
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/labwc-wlsunset-apply.path __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-wlsunset-apply.path 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/labwc-wlsunset-apply.service __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-wlsunset-apply.service 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/labwc-wlsunset-start.service __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-wlsunset-start.service 0644
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-wlsunset __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-wlsunset 0755
  desktop_render_role_target_template \
    hooks/target/etc/labwc/wlsunset.conf.tmpl __INSTALLER_PATH_DIR_ETC__/labwc/wlsunset.conf 0644 \
    WLSUNSET_ENABLED "$(desktop_shell_config_value "${WLSUNSET_ENABLED-true}")" \
    WLSUNSET_LATITUDE "$(desktop_shell_config_value "${WLSUNSET_LATITUDE-55.60587}")" \
    WLSUNSET_LONGITUDE "$(desktop_shell_config_value "${WLSUNSET_LONGITUDE-13.00073}")" \
    WLSUNSET_TEMPERATURE_DAY "$(desktop_shell_config_value "${WLSUNSET_TEMPERATURE_DAY-6500}")" \
    WLSUNSET_TEMPERATURE_NIGHT "$(desktop_shell_config_value "${WLSUNSET_TEMPERATURE_NIGHT-4500}")" \
    WLSUNSET_GAMMA "$(desktop_shell_config_value "${WLSUNSET_GAMMA-1.0}")" \
    WLSUNSET_SUNRISE "$(desktop_shell_config_value "${WLSUNSET_SUNRISE-}")" \
    WLSUNSET_SUNSET "$(desktop_shell_config_value "${WLSUNSET_SUNSET-}")" \
    WLSUNSET_TRANSITION_SECONDS "$(desktop_shell_config_value "${WLSUNSET_TRANSITION_SECONDS-1800}")" \
    WLSUNSET_OUTPUTS "$(desktop_shell_config_value "${WLSUNSET_OUTPUTS-}")"

}

desktop_stage_waybar_native_menus() {
  for menu_name in tomat audio notifications power calendar screenshot bluetooth system launcher wayscriber brightness battery; do
    desktop_render_waybar_asset "${menu_name}-menu.xml"
  done
  # Keep optional voice actions visible but disabled when their services are
  # not selected. IDs stay stable, so both Waybar layouts use the same mapping.
  native_menu_whisper=0
  if desktop_whisper_class_selected; then native_menu_whisper=1; fi
  run_in_target "configure optional native audio menu" __INSTALLER_PATH_DIR_USR_BIN__/python3 -I -c '
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
path = Path("__INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/waybar/gtk/audio-menu.xml")
tree = ET.parse(path)
items = [item for item in tree.iter("object") if item.get("class") == "GtkMenuItem"
         and item.find(".//object[@id=\"whisper_record\"]") is not None]
if len(items) != 1:
    raise SystemExit("native audio menu has no unique Whisper submenu")
item = items[0]
prop = item.find("./property[@name=\"sensitive\"]")
if prop is None:
    prop = ET.Element("property", {"name": "sensitive"})
    # GtkBuilder constructs the parent when it encounters its first child.
    # Properties added after that child are not reliably applied by GTK3.
    item.insert(0, prop)
prop.text = "True" if sys.argv[1] == "1" else "False"
item.find("./child/object[@class=\"GtkBox\"]/child/object[@class=\"GtkLabel\"]/property[@name=\"label\"]").text = "Whisper" if sys.argv[1] == "1" else "Whisper (not installed)"
ET.indent(tree, space="  ")
tree.write(path, encoding="utf-8", xml_declaration=True)
' "$native_menu_whisper"
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/tomat/config.toml.tmpl \
    __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/tomat/config.toml 0600
  for menu_helper in labwc-tomat labwc-tomat-hook labwc-tomat-overlay labwc-notifications; do
    desktop_stage_role_asset "usr/local/libexec/$menu_helper" "__INSTALLER_PATH_DIR_USR_LOCAL__/libexec/$menu_helper" 0755
  done
}

desktop_stage_help() (
  set -eu
  for directory in \
    "${DIR_USR_LOCAL_LIBEXEC}" \
    "${DIR_PYTHON3_LOCAL}" \
    "${DIR_PYTHON3_SITE_PACKAGES}" \
    "${DIR_PYTHON3_SITE_PACKAGES}/labwc_help" \
    "${DIR_USR_LOCAL_SHARE}" \
    "${DIR_USR_LOCAL_SHARE}/labwc-help" \
    "${DIR_USR_LOCAL_SHARE}/labwc-help/articles" \
    "${DIR_USR_LOCAL_SHARE_APPLICATIONS}"
  do
    ensure_target_asset_parent "${directory}/.installer-directory"
    help_directory_host=$(target_asset_host_path "$directory")
    [ -d "$help_directory_host" ] && [ ! -L "$help_directory_host" ] ||
      installer_fatal "Help asset directory is unsafe: ${directory}"
    chown root:root "$help_directory_host"
    chmod 0755 "$help_directory_host"
  done

  desktop_render_role_target_template \
    hooks/target/usr/local/share/desktop/labwc-help/catalog.json.tmpl \
    "${DIR_USR_LOCAL_SHARE}/labwc-help/catalog.json" 0644
  desktop_render_role_target_template \
    hooks/target/usr/local/share/desktop/labwc-help/theme.json.tmpl \
    "${DIR_USR_LOCAL_SHARE}/labwc-help/theme.json" 0644
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-help __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-help 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-help-gtk __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-help-gtk 0755
  desktop_render_role_target_template \
    hooks/target/usr/local/share/desktop/applications/labwc-help.desktop.tmpl \
    "${DIR_USR_LOCAL_SHARE_APPLICATIONS}/labwc-help.desktop" 0644
  for module in __init__ catalog navigation render search state theme window app; do
    path="usr/local/lib/python3/dist-packages/labwc_help/${module}.py"
    desktop_stage_role_asset "$path" "${DIR_PYTHON3_SITE_PACKAGES}/labwc_help/${module}.py" 0644
  done
  for article in \
    start.help start.first-login start.shortcuts desktop.labwc desktop.waybar desktop.fuzzel \
    desktop.mako desktop.dock desktop.appearance desktop.calendar desktop.tomat \
    desktop.wayscriber hardware.monitors \
    hardware.gpu hardware.nvidia hardware.peripherals hardware.power network.connections \
    network.vpn network.tailscale network.sharing network.ssh security.apparmor \
    security.firewall security.authentication storage.btrfs storage.f2fs storage.backups \
    storage.timeshift storage.recovery applications.foot applications.files applications.git \
    applications.podman applications.incus applications.development applications.wrappers applications.codex maintenance.management \
    maintenance.updates maintenance.services maintenance.logs troubleshooting.desktop \
    troubleshooting.network troubleshooting.audio troubleshooting.applications desktop.scx
  do
    article="${article}.json"
    desktop_stage_role_asset "usr/local/share/labwc-help/articles/$article" "${DIR_USR_LOCAL_SHARE}/labwc-help/articles/$article" 0644
  done
)

desktop_stage_key_manager() (
  set -eu
  for directory in "${DIR_USR_LOCAL_BIN}" "${DIR_USR_LOCAL_LIB}" "${DIR_PYTHON3_LOCAL}" \
    "${DIR_PYTHON3_SITE_PACKAGES}" "${DIR_PYTHON3_SITE_PACKAGES}/managed_workflows" \
    "${DIR_PYTHON3_SITE_PACKAGES}/key_manager" "${DIR_USR_LOCAL_SHARE}" \
    "${DIR_USR_LOCAL_SHARE}/key-manager" __INSTALLER_PATH_DIR_ETC__/key-manager; do
    ensure_target_asset_parent "${directory}/.installer-parent"
    host_directory=$(target_asset_host_path "$directory")
    [ ! -L "$host_directory" ] || installer_fatal "unsafe key-manager directory: $directory"
    chown root:root "$host_directory"
    chmod 0755 "$host_directory"
  done
  desktop_stage_role_asset hooks/target/usr/local/bin/common/key-manager __INSTALLER_PATH_DIR_USR_LOCAL__/bin/key-manager 0755
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.gnupg/gpg-agent.conf \
    "${DIR_USR_LOCAL_SHARE}/key-manager/gpg-agent.conf" 0644
  for module in __init__ fs; do
    path="usr/local/lib/python3/dist-packages/managed_workflows/${module}.py"
    desktop_stage_role_asset "$path" "${DIR_PYTHON3_SITE_PACKAGES}/managed_workflows/${module}.py" 0644
  done
  for module in __init__ core cli ssh gpg tls tls_profiles pqc; do
    path="usr/local/lib/python3/dist-packages/key_manager/${module}.py"
    desktop_stage_role_asset "$path" "${DIR_PYTHON3_SITE_PACKAGES}/key_manager/${module}.py" 0644
  done
  desktop_render_role_target_template hooks/target/etc/key-manager/settings.json.tmpl \
    __INSTALLER_PATH_DIR_ETC__/key-manager/settings.json 0644 \
    DIR_DATA_PKI "$DIR_DATA_PKI" ACCOUNT_USERNAME "$ACCOUNT_USERNAME"
  desktop_stage_role_asset hooks/target/etc/key-manager/certbot.ini __INSTALLER_PATH_DIR_ETC__/key-manager/certbot.ini 0644
  desktop_stage_role_asset hooks/target/etc/systemd/desktop/system/key-manager-acme-renew.timer \
    __INSTALLER_PATH_DIR_ETC__/systemd/system/key-manager-acme-renew.timer 0644
  desktop_render_role_target_template hooks/target/etc/systemd/desktop/system/key-manager-acme-renew.service.tmpl \
    __INSTALLER_PATH_DIR_ETC__/systemd/system/key-manager-acme-renew.service 0644 DIR_DATA_PKI "$DIR_DATA_PKI"
)

desktop_stage_fangfrisch() (
  set -eu
  installer_plan_package_selected clamav || exit 0
  set +x
  set +v
  fangfrisch_urlhaus_enable=${FANGFRISCH_URLHAUS_ENABLE:-false}
  case "$fangfrisch_urlhaus_enable" in
    true|false) ;;
    *)
      installer_fatal "FANGFRISCH_URLHAUS_ENABLE must be true or false"
      exit 1
      ;;
  esac
  fangfrisch_urlhaus_feed_base=
  fangfrisch_urlhaus_url=
  if [ "$fangfrisch_urlhaus_enable" = true ]; then
    fangfrisch_urlhaus_feed_base=${FANGFRISCH_URLHAUS_FEED_BASE:-}
    [ -n "$fangfrisch_urlhaus_feed_base" ] || {
      installer_fatal "FANGFRISCH_URLHAUS_ENABLE=true requires FANGFRISCH_URLHAUS_FEED_BASE"
      exit 1
    }
    fangfrisch_urlhaus_url="${fangfrisch_urlhaus_feed_base}/\${auth_key}/urlhaus_clamav.ndb"
  fi

  fangfrisch_stage=$(target_private_stage_dir fangfrisch)
  fangfrisch_stage_host=$(target_asset_host_path "$fangfrisch_stage")
  trap 'rm -rf -- "$fangfrisch_stage_host"' 0
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  stage_target_asset "$(installer_repo_file_value scripts/desktop/fangfrisch-configure.py)" \
    "${fangfrisch_stage}/configure.py" 0600
  desktop_render_role_target_template \
    hooks/target/etc/fangfrisch.conf.tmpl \
    "${fangfrisch_stage}/fangfrisch.conf" \
    0600 \
    FANGFRISCH_URLHAUS_URL \
    "$fangfrisch_urlhaus_url" \
    FANGFRISCH_SANESECURITY_PREFIX \
    "$FANGFRISCH_SANESECURITY_PREFIX"
  if fangfrisch_key=$(installer_cmdline_value urlhaus_authkey); then
    :
  else
    fangfrisch_credential_status=$?
    case "$fangfrisch_credential_status" in
      1) fangfrisch_key= ;;
      *) installer_fatal "unsafe URLhaus private credential input"; exit 1 ;;
    esac
  fi
  if [ "$fangfrisch_urlhaus_enable" = true ] && [ -z "$fangfrisch_key" ]; then
    installer_fatal \
      "FANGFRISCH_URLHAUS_ENABLE=true requires urlhaus_authkey in installer credential input"
    exit 1
  fi
  (umask 077; printf '%s' "$fangfrisch_key" >"${fangfrisch_stage_host}/auth-key")
  unset fangfrisch_key
  run_in_target "configure Fangfrisch privately" \
    __INSTALLER_PATH_DIR_USR_BIN__/env -i HOME=__INSTALLER_PATH_DIR_ROOT_HOME__ LC_ALL=C PATH=__INSTALLER_PATH_DIR_USR_SBIN__:__INSTALLER_PATH_DIR_USR_BIN__:__INSTALLER_PATH_DIR_SBIN__:__INSTALLER_PATH_DIR_BIN__ \
    FANGFRISCH_URLHAUS_FEED_BASE="$fangfrisch_urlhaus_feed_base" \
    FANGFRISCH_SANESECURITY_PREFIX="$FANGFRISCH_SANESECURITY_PREFIX" \
    FANGFRISCH_URLHAUS_ENABLE="$fangfrisch_urlhaus_enable" \
    __INSTALLER_PATH_DIR_USR_BIN__/python3 -I -S -B "${fangfrisch_stage}/configure.py" "$fangfrisch_stage"
)

desktop_stage_target_assets() {
  installer_asset_batch_begin desktop-assets || return $?
  desktop_stage_key_manager
  desktop_stage_appearance
  desktop_stage_help
  desktop_stage_waybar_native_menus
  desktop_stage_session_repairs
  desktop_stage_wlsunset
  desktop_normalize_system_dbus_service_directories
  desktop_stage_logging_policy
  desktop_stage_primary_account_pool_storage_policy
  desktop_stage_network_profile_storage_policy
  desktop_stage_var_cache_policy
  desktop_render_labwc_environment_assets
  desktop_stage_role_asset hooks/target/etc/pam.d/greetd __INSTALLER_PATH_DIR_ETC__/pam.d/greetd 0644
  desktop_stage_role_asset hooks/target/etc/pam.d/greetd-greeter __INSTALLER_PATH_DIR_ETC__/pam.d/greetd-greeter 0644
  desktop_stage_role_asset hooks/target/etc/security/greetd-greeter.conf __INSTALLER_PATH_DIR_ETC__/security/greetd-greeter.conf 0644
  desktop_render_role_target_template \
    hooks/target/etc/dbus-1/session.d/70-labwc-greeter-no-portals.conf.tmpl \
    __INSTALLER_PATH_DIR_ETC__/dbus-1/session.d/70-labwc-greeter-no-portals.conf 0644 \
    LABWC_GREETER_USER "$LABWC_GREETER_USER"
  desktop_stage_role_asset hooks/target/etc/pam.d/swaylock __INSTALLER_PATH_DIR_ETC__/pam.d/swaylock 0644
  desktop_stage_role_asset hooks/target/etc/systemd/desktop/logind.conf.d/70-labwc-lock.conf __INSTALLER_PATH_DIR_ETC__/systemd/logind.conf.d/70-labwc-lock.conf 0644
  desktop_stage_role_asset hooks/target/usr/share/pam-configs/wtmpdb __INSTALLER_PATH_DIR_USR_SHARE__/pam-configs/wtmpdb 0644
  desktop_reconcile_wtmpdb_common_session ${TARGET_ROOT}
  desktop_render_labwc_session_wrappers
  # systemd's dash-prefix drop-ins also cover future application names and
  # transient UUIDs. Keep session daemons outside these application families.
  for application_family in wayland electron native devops bitwarden qbittorrent compat; do
    desktop_stage_role_asset hooks/target/etc/systemd/desktop/user/labwc-native-.service.d/50-app-lifecycle.conf \
      "$(installer_systemd_dropin_dir user "labwc-${application_family}-.service")/50-app-lifecycle.conf" 0644
  done
  desktop_stage_role_asset hooks/target/etc/systemd/desktop/user/labwc-wayland-foot-.service.d/60-terminal-lifecycle.conf \
    __INSTALLER_PATH_DIR_SYSTEMD_USER_LABWC_WAYLAND_FOOT_FAMILY_DROPIN__/60-terminal-lifecycle.conf 0644
  desktop_stage_role_asset hooks/target/etc/systemd/desktop/user/labwc-devops-.service.d/60-stop-budget.conf \
    __INSTALLER_PATH_DIR_SYSTEMD_USER_LABWC_DEVOPS_FAMILY_DROPIN__/60-stop-budget.conf 0644
  desktop_configure_local_mail_delivery
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-autostart __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-autostart 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-wallpaper-save __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-wallpaper-save 0755
  desktop_render_role_target_template hooks/target/usr/local/bin/desktop/labwc-admin-action.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-admin-action 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-admin-action-root __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-admin-action-root 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-admin-action-worker __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-admin-action-worker 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-logout-root __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-logout-root 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-session-state.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-session-state 0755
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/labwc-session-state@.service __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-session-state@.service 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/labwc-session-state@prepare.service.d/retain-result.conf __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-session-state@prepare.service.d/retain-result.conf 0644
  desktop_stage_role_asset hooks/target/etc/systemd/desktop/system/labwc-admin-action@.service.tmpl __INSTALLER_PATH_DIR_ETC__/systemd/system/labwc-admin-action@.service 0644
  desktop_stage_role_asset hooks/target/etc/systemd/desktop/system/labwc-external-drives-shutdown.service __INSTALLER_PATH_DIR_ETC__/systemd/system/labwc-external-drives-shutdown.service 0644
  desktop_render_role_target_template \
    hooks/target/etc/systemd/desktop/system/labwc-package-sleep-guard.service.tmpl \
    __INSTALLER_PATH_DIR_ETC__/systemd/system/labwc-package-sleep-guard.service 0644 \
    LOG_POWER_DIR "$LOG_POWER_DIR"
  desktop_stage_role_asset hooks/target/etc/systemd/desktop/system/sleep.target.d/50-package-lock-guard.conf __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_SLEEP_TARGET_DROPIN__/50-package-lock-guard.conf 0644
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/greetd-power-action-root __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/greetd-power-action-root 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/calix-fruux-bootstrap __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/calix-fruux-bootstrap 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-waycal-control __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-waycal-control 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-waycal-popup __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-waycal-popup 0755
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/gtk-4.0/gtk.css __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/gtk-4.0/gtk.css 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/gtk-3.0/gtk.css __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/gtk-3.0/gtk.css 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/l3afpad/style.css __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/l3afpad/style.css 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/waycal/style.css __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/waycal/style.css 0644
  desktop_render_role_target_template hooks/target/usr/local/share/desktop/applications/com.ianswope.Calix.desktop.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/com.ianswope.Calix.desktop 0644
  desktop_render_role_target_template hooks/target/usr/local/share/desktop/applications/labwc-calendar-actions.desktop.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/labwc-calendar-actions.desktop 0644
  # Public commands share the managed launcher, including terminal launches.
  for calendar_alias in labwc-agenda labwc-calendar; do
    ensure_target_asset_parent "__INSTALLER_PATH_DIR_USR_LOCAL__/bin/$calendar_alias"
    calendar_alias_host=$(target_asset_entry_host_path "__INSTALLER_PATH_DIR_USR_LOCAL__/bin/$calendar_alias")
    ln -sfnT labwc-app "$calendar_alias_host"
  done
  unset calendar_alias calendar_alias_host
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-calendar-actions __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-calendar-actions 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-calendar-worker __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-calendar-worker 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-calendar-reminders-gtk __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-calendar-reminders-gtk 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-local-reminder-worker __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-local-reminder-worker 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-new-local-reminder __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-new-local-reminder 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-reminder-manager __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-reminder-manager 0755
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/labwc-local-reminders.service \
    __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-local-reminders.service 0644
  desktop_stage_role_asset hooks/target/usr/local/lib/desktop/python3/dist-packages/labwc_calendar_reminders.py __INSTALLER_PATH_DIR_PYTHON3_SITE_PACKAGES__/labwc_calendar_reminders.py 0644
  desktop_stage_role_asset hooks/target/usr/local/lib/desktop/python3/dist-packages/labwc_local_reminders.py __INSTALLER_PATH_DIR_PYTHON3_SITE_PACKAGES__/labwc_local_reminders.py 0644
  desktop_stage_role_asset hooks/target/usr/local/lib/desktop/python3/dist-packages/labwc_calendar_reminders_gtk.py __INSTALLER_PATH_DIR_PYTHON3_SITE_PACKAGES__/labwc_calendar_reminders_gtk.py 0644
  desktop_stage_role_asset hooks/target/usr/local/lib/desktop/python3/dist-packages/labwc_desktop_runtime.py __INSTALLER_PATH_DIR_PYTHON3_SITE_PACKAGES__/labwc_desktop_runtime.py 0644
  desktop_render_role_target_template hooks/target/usr/local/share/desktop/applications/com.github.dahenson.agenda.desktop.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/com.github.dahenson.agenda.desktop 0644
  desktop_stage_role_asset hooks/target/usr/local/share/desktop/agenda/schemas/90-desktop-agenda.gschema.override __INSTALLER_PATH_DIR_USR_LOCAL__/share/agenda/schemas/90-desktop-agenda.gschema.override 0644
  desktop_render_role_target_template hooks/target/etc/systemd/desktop/system/fruux-firstboot.service.tmpl \
    __INSTALLER_PATH_DIR_ETC__/systemd/system/fruux-firstboot.service 0644 \
    ACCOUNT_USERNAME "$ACCOUNT_USERNAME" ACCOUNT_HOME "$ACCOUNT_HOME"
  desktop_render_role_target_template hooks/target/var/lib/firstboot/bin/fruux-cleanup.tmpl \
    __INSTALLER_PATH_DIR_VAR__/lib/firstboot/bin/fruux-cleanup 0755 ACCOUNT_USERNAME "$ACCOUNT_USERNAME"
  desktop_stage_role_asset hooks/target/etc/systemd/desktop/system/greetd.service.d/40-fruux-firstboot.conf \
    __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_GREETD_DROPIN__/40-fruux-firstboot.conf 0644
  for calendar_unit in labwc-calendar-credentials; do
    desktop_stage_role_asset "etc/skel-desktop/.config/systemd/user/${calendar_unit}.service" "__INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/${calendar_unit}.service" 0644
  done
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-plans.pl __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-plans.pl 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-logout __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-logout 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-fuzzel.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-fuzzel 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-computer-management __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-computer-management 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-network-sharing __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-network-sharing 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/common/nfsmnt __INSTALLER_PATH_DIR_USR_LOCAL__/bin/nfsmnt 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/common/filenmnt __INSTALLER_PATH_DIR_USR_LOCAL__/bin/filenmnt 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/nmtui __INSTALLER_PATH_DIR_USR_LOCAL__/bin/nmtui 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-ai-copilots __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-ai-copilots 0755
  case "$AICOPILOTS_HUGGINGFACE_WEB_BASE_URL:$AICOPILOTS_HUGGINGFACE_API_BASE_URL" in
    https://?*:https://?*) ;;
    *) installer_fatal 'AI copilot model service endpoints must use HTTPS URLs' ;;
  esac
  desktop_render_role_target_template \
    hooks/target/usr/local/share/desktop/labwc-ai-copilots/endpoints.json.tmpl \
    __INSTALLER_PATH_DIR_USR_LOCAL__/share/labwc-ai-copilots/endpoints.json 0644 \
    AICOPILOTS_HUGGINGFACE_WEB_BASE_URL "$AICOPILOTS_HUGGINGFACE_WEB_BASE_URL" \
    AICOPILOTS_HUGGINGFACE_API_BASE_URL "$AICOPILOTS_HUGGINGFACE_API_BASE_URL"
  desktop_stage_ai_copilots_perl_modules
  desktop_stage_ai_copilots_catalogs
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-ai-copilots-action __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-ai-copilots-action 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-ai-llama-server __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-ai-llama-server 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/llama-whisper-coordinate __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/llama-whisper-coordinate 0755
  desktop_stage_role_asset hooks/target/etc/systemd/desktop/user/llama-whisper-guard.service __INSTALLER_PATH_DIR_ETC__/systemd/user/llama-whisper-guard.service 0644
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-ai-model-install-root __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-ai-model-install-root 0755
  desktop_stage_ai_copilots_python_modules
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-ai-model-info __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-ai-model-info 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-display-configuration __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-display-configuration 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-digital-assets __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-digital-assets 0755
  desktop_stage_digital_assets_perl_modules
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-digital-assets-action __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-digital-assets-action 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-users-groups-menu __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-users-groups-menu 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-adb-menu __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-adb-menu 0755
  desktop_stage_labwc_adb_perl_modules
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-adb-action __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-adb-action 0755
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/labwc-adb-server.service __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-adb-server.service 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/llama-server.service __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/llama-server.service 0644
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-samsung-firmware-extract __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-samsung-firmware-extract 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-maintenance-menu.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-maintenance-menu 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-system-menu-action __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-system-menu-action 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-podman-menu __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-podman-menu 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-external-drives.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-external-drives 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-gvfs-volume-monitor __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-gvfs-volume-monitor 0755
  desktop_stage_role_asset hooks/target/etc/systemd/desktop/user/labwc-gvfs-volume-monitor.service __INSTALLER_PATH_DIR_ETC__/systemd/user/labwc-gvfs-volume-monitor.service 0644
  desktop_stage_role_asset hooks/target/etc/systemd/desktop/user/thunar.service.d/50-labwc-session.conf __INSTALLER_PATH_DIR_SYSTEMD_USER_THUNAR_DROPIN__/50-labwc-session.conf 0644
  desktop_stage_role_asset hooks/target/usr/share/dbus-1/services/org.gtk.vfs.LabwcVolumeMonitor.service __INSTALLER_PATH_DIR_USR_SHARE__/dbus-1/services/org.gtk.vfs.LabwcVolumeMonitor.service 0644
  desktop_stage_role_asset hooks/target/usr/share/gvfs/remote-volume-monitors/labwc.monitor __INSTALLER_PATH_DIR_USR_SHARE__/gvfs/remote-volume-monitors/labwc.monitor 0644
  desktop_stage_labwc_security_action_perl_modules
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-security-action __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-security-action 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-system-action.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-system-action 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-recovery-action.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-recovery-action 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-network-control-menu __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-network-control-menu 0755
  desktop_stage_labwc_network_control_action_perl_modules
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-network-control-action __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-network-control-action 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-firewall-menu __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-firewall-menu 0755
  desktop_stage_labwc_firewall_python_modules
  desktop_stage_compz
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-firewall-action __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-firewall-action 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-network-scan-menu __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-network-scan-menu 0755
  desktop_stage_labwc_network_scan_action_perl_modules
  desktop_render_labwc_network_scan_action_perl_root_module
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-network-scan-action __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-network-scan-action 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-remote-desktop.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-remote-desktop 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-freerdp-askpass __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-freerdp-askpass 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-ocr __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-ocr 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/discord __INSTALLER_PATH_DIR_USR_LOCAL__/bin/discord 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/common/telbot __INSTALLER_PATH_DIR_USR_LOCAL__/bin/telbot 0755
  for tuta_launcher in \
    "${DIR_ETC_SKEL_DESKTOP}/.local/share/applications/tutanota-desktop.desktop" \
    "${DIR_USR_LOCAL_SHARE_APPLICATIONS}/tutanota-desktop.desktop"; do
    desktop_render_role_target_template \
      hooks/target/etc/skel-desktop/.local/share/applications/tutanota-desktop.desktop.tmpl "$tuta_launcher" 0644
  done
  desktop_stage_labwc_managed_app_python_modules
  if [ -e "${TARGET_ROOT}${DIR_OPT_VIVALDI}/vivaldi" ]; then
    (
      # The packaged updater's byte-offset pipelines can leave a partial
      # library and delete the previous codec. Read its release selection as
      # data and extract the actual ZIP member in the shared Python setup path.
      installer_operation_context_repo scripts/desktop/vivaldi-codecs-install.py 1 install_vivaldi_media_codecs
      installer_run_target_setup scripts/desktop/vivaldi-codecs-install.py \
        'install compatible Vivaldi proprietary media codecs' \
        "$DIR_OPT_VIVALDI" "${DIR_VAR}/opt/vivaldi" "${DIR_USR_BIN}/pidwait"
    )
  fi
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-proxy-session __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-proxy-session 0755
  desktop_normalize_proxy3_directories
  for proxy3_app in chromium microsoft-edge vivaldi mullvad-browser qbittorrent; do
    render_target_asset_with_placeholder_map \
      "$(installer_repo_asset_path DIR_TARGET_LABWC_3PROXY "${proxy3_app}.conf.tmpl")" \
      "__INSTALLER_PATH_DIR_ETC__/labwc/3proxy/${proxy3_app}.conf" 0644 proxy3_placeholder_map
  done
  render_target_asset_with_placeholder_map \
    "$(installer_repo_file_value hooks/target/etc/labwc/3proxy/session.json.tmpl)" \
    __INSTALLER_PATH_DIR_ETC__/labwc/3proxy/session.json 0644 proxy3_placeholder_map
  for proxy3_family in chromium opt/chrome opt/edge vivaldi; do
    # Proxy policy belongs only to managed namespaces. A vendor Exec outside
    # that namespace has no local CONNECT listener and must use normal networking.
    proxy3_policy_name=${proxy3_family##*/}
    render_target_asset_with_placeholder_map \
      "$(installer_repo_asset_path DIR_TARGET "${proxy3_family}/policies/managed/3proxy.json.tmpl")" \
      "__INSTALLER_PATH_DIR_ETC__/labwc/3proxy/${proxy3_policy_name}.json" 0644 proxy3_placeholder_map
  done
  render_target_asset_with_placeholder_map \
    "$(installer_repo_file_value hooks/target/usr/lib/mullvad-browser/distribution/policies.json.tmpl)" \
    __INSTALLER_PATH_DIR_ETC__/labwc/3proxy/mullvad-browser.json 0644 proxy3_placeholder_map
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-app __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-app 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-electron-app __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-electron-app 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-wayland-app __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-wayland-app 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/app-veth-run __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/app-veth-run 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-wrap-desktop-files __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-wrap-desktop-files 0755
  desktop_stage_role_asset "$(installer_repo_apt_file apt.conf.d/71labwc-desktop-apps)" __INSTALLER_PATH_DIR_ETC__/apt/apt.conf.d/71labwc-desktop-apps 0644
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-main-menu.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-main-menu 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-debug-session __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-debug-session 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-window-switcher __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-window-switcher 0755
  desktop_stage_waybar_theme_icons
  desktop_stage_role_asset hooks/target/etc/systemd/desktop/system/labwc-system-desktop-overrides.service __INSTALLER_PATH_DIR_ETC__/systemd/system/labwc-system-desktop-overrides.service 0644
  desktop_stage_role_asset hooks/target/etc/systemd/desktop/system/labwc-system-desktop-overrides.path __INSTALLER_PATH_DIR_ETC__/systemd/system/labwc-system-desktop-overrides.path 0644
  desktop_render_role_target_template \
    hooks/target/etc/skel-desktop/.local/share/applications/micro.desktop.tmpl \
    __INSTALLER_PATH_DIR_ETC__/skel-desktop/.local/share/applications/micro.desktop \
    0644
  desktop_render_role_target_template \
    hooks/target/etc/skel-desktop/.local/share/applications/waypaper.desktop.tmpl \
    __INSTALLER_PATH_DIR_ETC__/skel-desktop/.local/share/applications/waypaper.desktop \
    0644
  desktop_stage_role_asset hooks/target/etc/dpkg/dpkg.cfg.d/95-labwc-desktop-apps __INSTALLER_PATH_DIR_ETC__/dpkg/dpkg.cfg.d/95-labwc-desktop-apps 0644
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-chatgpt-session __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-chatgpt-session 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-wayland-compat-app __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-wayland-compat-app 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-zoom-discord-compat-runtime __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-zoom-discord-compat-runtime 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-private-xwayland __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-private-xwayland 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-compat-open-uri __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-compat-open-uri 0755
  desktop_qbittorrent_ports=$(qbittorrent_peer_port_placeholder_map) || desktop_fatal "invalid qBittorrent peer ports"
  desktop_qbittorrent_ethernet_port=$(printf '%s\n' "$desktop_qbittorrent_ports" | awk -F= '$1 == "LABWC_QBITTORRENT_ETHERNET_PORT" {print $2}')
  desktop_veth_identity=$(app_veth_identity_placeholder_map) || desktop_fatal "invalid application network identity"
  desktop_qbittorrent_enabled=$(printf "%s\n" "$desktop_veth_identity" | awk -F= '$1 == "APP_VETH_QBITTORRENT_ENABLED" { print $2 }')
  case "$desktop_qbittorrent_enabled" in
    true)
      ;;
    false)
      # An explicit APP_VETH_OVERRIDE may omit qBittorrent. Do not publish a
      # managed binding for an application that has no broker policy.
      remove_target_asset __INSTALLER_PATH_DIR_ETC__/qbittorrent/qBittorrent.conf.d/10-security.conf
      remove_target_asset __INSTALLER_PATH_DIR_ETC__/qbittorrent/qBittorrent.conf.d/20-managed-privacy.conf
      remove_target_asset __INSTALLER_PATH_DIR_ETC__/labwc/3proxy/qbittorrent.conf
      ;;
    *)
      desktop_fatal "invalid qBittorrent network policy selection"
      ;;
  esac
  desktop_qbittorrent_address=$(printf "%s\n" "$desktop_veth_identity" | awk -F= '$1 == "APP_VETH_QBITTORRENT_ADDRESS" { print $2 }')
  if [ "$desktop_qbittorrent_enabled" = true ]; then
    [ -n "$desktop_qbittorrent_address" ] || desktop_fatal "missing qBittorrent network identity"
    desktop_render_role_target_template \
      hooks/target/etc/qbittorrent/qBittorrent.conf.d/10-security.conf.tmpl \
      __INSTALLER_PATH_DIR_ETC__/qbittorrent/qBittorrent.conf.d/10-security.conf \
      0644 \
      ACCOUNT_USERNAME "$ACCOUNT_USERNAME" \
      QBITTORRENT_SAVE_ROOT "__INSTALLER_PATH_DIR_RUN__/media/$ACCOUNT_USERNAME/bittorrent" \
      LABWC_QBITTORRENT_ETHERNET_PORT "$desktop_qbittorrent_ethernet_port" \
      PROXY3_PORT_LISTEN_QBITTORRENT "${PROXY3_PORT_LISTEN_QBITTORRENT:-3128}" \
      APP_VETH_NAMESPACE_INTERFACE "$APP_VETH_NAMESPACE_INTERFACE" \
      APP_VETH_QBITTORRENT_ADDRESS "$desktop_qbittorrent_address"
    # Same native policy, rendered at install time for the disposable HOME.
    # Its address is allocated per lease, so only the interface is fixed.
    desktop_render_role_target_template \
      hooks/target/etc/qbittorrent/qBittorrent.conf.d/10-security.conf.tmpl \
      __INSTALLER_PATH_DIR_ETC__/qbittorrent/qBittorrent.conf.d/20-managed-privacy.conf 0644 \
      QBITTORRENT_SAVE_ROOT __INSTALLER_PATH_DIR_HOME__/user/Downloads \
      LABWC_QBITTORRENT_ETHERNET_PORT "$desktop_qbittorrent_ethernet_port" \
      PROXY3_PORT_LISTEN_QBITTORRENT "${PROXY3_PORT_LISTEN_QBITTORRENT:-3128}" \
      APP_VETH_NAMESPACE_INTERFACE "$APP_VETH_NAMESPACE_INTERFACE" \
      APP_VETH_QBITTORRENT_ADDRESS ""
  fi
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-qbittorrent __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-qbittorrent 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/zoom __INSTALLER_PATH_DIR_USR_LOCAL__/bin/zoom 0755
  desktop_render_role_target_template \
    hooks/target/usr/local/bin/desktop/labwc-sync-application-launchers.tmpl \
    __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-sync-application-launchers \
    0755
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/labwc-sync-application-launchers.service __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-sync-application-launchers.service 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/labwc-sync-application-launchers.path __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-sync-application-launchers.path 0644
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-greeter-output __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-greeter-output 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-greeter-power __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-greeter-power 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-greeter-client __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-greeter-client 0755
  desktop_stage_role_asset hooks/target/usr/local/share/desktop/labwc-greeter/rc.xml __INSTALLER_PATH_DIR_USR_LOCAL__/share/labwc-greeter/rc.xml 0644
  desktop_stage_role_asset hooks/target/usr/local/share/desktop/labwc-greeter/autostart __INSTALLER_PATH_DIR_USR_LOCAL__/share/labwc-greeter/autostart 0644
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-output-watch __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-output-watch 0755
  if desktop_kanshi_enabled; then
    desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-kanshi __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-kanshi 0755
  fi
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-session-check __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-session-check 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-primary-gpg __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-primary-gpg 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-waybar-exec __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-waybar-exec 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-waybar-menu __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-waybar-menu 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-waybar-run __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-waybar-run 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-waybar-state __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-waybar-state 0755
  desktop_stage_role_asset hooks/target/usr/local/lib/desktop/python3/dist-packages/labwc_waybar_state.py "${DIR_PYTHON3_SITE_PACKAGES}/labwc_waybar_state.py" 0644
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-waybar-battery __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-waybar-battery 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-waybar-events.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-waybar-events 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-panel-run __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-panel-run 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/whisper-record-timed __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/whisper-record-timed 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-swaybg.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-swaybg 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-swayidle __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-swayidle 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-mute-default-microphone __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-mute-default-microphone 0755
  desktop_stage_role_asset hooks/target/usr/local/lib/common/perl5/site_perl/whisper/WhisperMode/Audio.pm "${DIR_PERL5_SITE_PERL}/whisper/WhisperMode/Audio.pm" 0644
  desktop_stage_role_asset hooks/target/usr/local/lib/common/perl5/site_perl/whisper/WhisperMode/State.pm "${DIR_PERL5_SITE_PERL}/whisper/WhisperMode/State.pm" 0644
  desktop_stage_role_asset hooks/target/usr/local/lib/common/perl5/site_perl/whisper/WhisperMode/Systemd.pm "${DIR_PERL5_SITE_PERL}/whisper/WhisperMode/Systemd.pm" 0644
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-lock.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-lock 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-swaylock.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-swaylock 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-idle-toggle __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-idle-toggle 0755
  desktop_stage_role_asset hooks/target/etc/systemd/desktop/user/labwc-lock.service __INSTALLER_PATH_DIR_ETC__/systemd/user/labwc-lock.service 0644
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-terminal __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-terminal 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-terminal-result __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-terminal-result 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-bluetooth.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-bluetooth 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-brightness-control.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-brightness-control 0755
  desktop_stage_role_asset hooks/target/etc/udev/rules.d/81-labwc-thinkpad-backlight.rules __INSTALLER_PATH_DIR_ETC__/udev/rules.d/81-labwc-thinkpad-backlight.rules 0644
  case "${SYSTEM_HARDWARE_SPEC:-}" in
    79-thinkpad-acpi.conf)
      desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-thinkpad-hotkeys __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-thinkpad-hotkeys 0755
      desktop_stage_role_asset hooks/target/etc/systemd/desktop/system/labwc-thinkpad-hotkeys.service __INSTALLER_PATH_DIR_ETC__/systemd/system/labwc-thinkpad-hotkeys.service 0644
      remove_target_asset __INSTALLER_PATH_DIR_ETC__/udev/rules.d/82-labwc-ideapad-flex-backlight.rules
      remove_target_asset __INSTALLER_PATH_DIR_ETC__/systemd/system/multi-user.target.wants/labwc-thinkpad-hotkeys.service
      run_in_target "enable supported ThinkPad brightness events" __INSTALLER_PATH_DIR_USR_BIN__/systemctl enable labwc-thinkpad-hotkeys.service
      ;;
    79-ideapad-acpi.conf)
      desktop_stage_role_asset \
        hooks/target/etc/udev/rules.d/82-labwc-ideapad-flex-backlight.rules \
        __INSTALLER_PATH_DIR_ETC__/udev/rules.d/82-labwc-ideapad-flex-backlight.rules 0644
      remove_target_asset __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-thinkpad-hotkeys
      remove_target_asset __INSTALLER_PATH_DIR_ETC__/systemd/system/labwc-thinkpad-hotkeys.service
      remove_target_asset __INSTALLER_PATH_DIR_ETC__/systemd/system/multi-user.target.wants/labwc-thinkpad-hotkeys.service
      ;;
    ''|79-chromebook.conf)
      remove_target_asset __INSTALLER_PATH_DIR_ETC__/udev/rules.d/82-labwc-ideapad-flex-backlight.rules
      remove_target_asset __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-thinkpad-hotkeys
      remove_target_asset __INSTALLER_PATH_DIR_ETC__/systemd/system/labwc-thinkpad-hotkeys.service
      remove_target_asset __INSTALLER_PATH_DIR_ETC__/systemd/system/multi-user.target.wants/labwc-thinkpad-hotkeys.service
      ;;
    *)
      desktop_fatal "unsupported SYSTEM_HARDWARE_SPEC for keyboard backlight staging: ${SYSTEM_HARDWARE_SPEC}"
      ;;
  esac
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-power-settings __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-power-settings 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-run __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-run 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-power-menu __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-power-menu 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-keyboard-layout.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-keyboard-layout 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-capture.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-capture 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-wayscriber-toggle __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-wayscriber-toggle 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-wayscriber-config __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-wayscriber-config 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/satty __INSTALLER_PATH_DIR_USR_LOCAL__/bin/satty 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/apparmor-generate-rules __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/apparmor-generate-rules 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-security-action-root __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-security-action-root 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-apparmor-policy-worker __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-apparmor-policy-worker 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-apparmor-boot-state __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-apparmor-boot-state 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-system-action-root __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-system-action-root 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-storage-report __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-storage-report 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-recovery-action-root __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-recovery-action-root 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-network-control-action-root __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-network-control-action-root 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-firewall-action-root __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-firewall-action-root 0755
  desktop_render_role_target_template \
    hooks/target/usr/local/libexec/desktop/labwc-network-scan-action-root.tmpl \
    __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-network-scan-action-root \
    0755 \
    ACCOUNT_USERNAME "$ACCOUNT_USERNAME"
  desktop_stage_managed_nmap_scripts
  desktop_stage_role_asset hooks/target/usr/local/sbin/desktop/greetd-power-action __INSTALLER_PATH_DIR_USR_LOCAL__/sbin/greetd-power-action 0755
  desktop_stage_role_asset hooks/target/usr/local/sbin/desktop/labwc-notify.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/sbin/labwc-notify 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/clamav-signature-update __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/clamav-signature-update 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/clamav-fangfrisch __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/clamav-fangfrisch 0755

  desktop_stage_role_asset hooks/target/usr/share/wayland-sessions/labwc.desktop __INSTALLER_PATH_DIR_USR_SHARE__/wayland-sessions/labwc.desktop 0644
  desktop_stage_role_asset hooks/target/usr/local/share/desktop/applications/computer-management.desktop.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/computer-management.desktop 0644
  desktop_stage_role_asset hooks/target/usr/local/share/desktop/applications/remote-desktop-management.desktop.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/remote-desktop-management.desktop 0644
  desktop_stage_role_asset hooks/target/usr/local/share/desktop/applications/foot.desktop.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/foot.desktop 0644
  desktop_render_role_target_template hooks/target/usr/local/share/desktop/applications/code.desktop.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/code.desktop 0644
  desktop_render_role_target_template hooks/target/usr/local/share/desktop/applications/org.labwc.DesktopAppearance.desktop.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/org.labwc.DesktopAppearance.desktop 0644
  desktop_stage_role_asset hooks/target/usr/local/share/desktop/applications/labwc-notifications.desktop.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/labwc-notifications.desktop 0644
  desktop_render_gtkgreet_css
  desktop_stage_role_asset hooks/target/etc/greetd/gtkgreet-power.css.tmpl __INSTALLER_PATH_DIR_ETC__/greetd/gtkgreet-power.css 0644
  desktop_render_greeter_power_rule
  desktop_stage_fangfrisch
  desktop_stage_role_asset hooks/target/etc/cron.d/debsecan __INSTALLER_PATH_DIR_ETC__/cron.d/debsecan 0644
  desktop_stage_role_asset hooks/target/etc/systemd/common/system/clamav-signature-update.service.tmpl __INSTALLER_PATH_DIR_ETC__/systemd/system/clamav-signature-update.service 0644
  desktop_stage_role_asset hooks/target/etc/systemd/common/system/clamav-signature-update.service.d/60-resource-class.conf __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_CLAMAV_SIGNATURE_UPDATE_DROPIN__/60-resource-class.conf 0644
  desktop_stage_role_asset hooks/target/etc/systemd/common/system/clamav-signature-update.timer __INSTALLER_PATH_DIR_ETC__/systemd/system/clamav-signature-update.timer 0644
  desktop_stage_role_asset hooks/target/etc/bluetooth/main.conf __INSTALLER_PATH_DIR_ETC__/bluetooth/main.conf 0644
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/bluetooth-controller-init __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/bluetooth-controller-init 0755
  desktop_stage_role_asset hooks/target/etc/systemd/desktop/system/bluetooth-controller-init.service __INSTALLER_PATH_DIR_ETC__/systemd/system/bluetooth-controller-init.service 0644
  desktop_stage_role_asset hooks/target/etc/systemd/desktop/system/greetd.service.d/20-labwc-vt.conf __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_GREETD_DROPIN__/20-labwc-vt.conf 0644
  desktop_stage_role_asset hooks/target/etc/systemd/desktop/system/bluetooth.service.d/override.conf __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_BLUETOOTH_DROPIN__/override.conf 0644
  desktop_stage_mullvad_dns_policy
  installer_asset_batch_flush || return $?
  install -d -m 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/autostart
  desktop_stage_mullvad_application_policy
  if [ "${LABWC_NVIDIA_ACCELERATION_AVAILABLE:-false}" = true ]; then
    desktop_stage_role_asset hooks/target/etc/systemd/desktop/system/nvidia-powerd.service.d/10-device-guard.conf __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_NVIDIA_POWERD_DROPIN__/10-device-guard.conf 0644
    desktop_stage_role_asset hooks/target/etc/udev/rules.d/71-nvidia-char-links.rules __INSTALLER_PATH_DIR_ETC__/udev/rules.d/71-nvidia-char-links.rules 0644
    desktop_stage_role_asset hooks/target/usr/local/libexec/common/nvidia-char-links __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/nvidia-char-links 0755
    desktop_stage_role_asset hooks/target/etc/systemd/desktop/system/nvidia-char-links.service __INSTALLER_PATH_DIR_ETC__/systemd/system/nvidia-char-links.service 0644
  else
    installer_asset_batch_flush || return $?
    rm -f \
      ${TARGET_ROOT}${DIR_SYSTEMD_SYSTEM_NVIDIA_POWERD_DROPIN}/10-device-guard.conf \
      ${TARGET_ROOT}${DIR_ETC}/udev/rules.d/71-nvidia-char-links.rules \
      ${TARGET_ROOT}${DIR_USR_LOCAL_LIBEXEC}/nvidia-char-links \
      ${TARGET_ROOT}${DIR_SYSTEMD_SYSTEM}/nvidia-char-links.service \
      ${TARGET_ROOT}${DIR_SYSTEMD_SYSTEM}/multi-user.target.wants/nvidia-char-links.service
  fi
  # KWallet belongs to the single managed Labwc account. Keep the portal unit
  # account-local so the greeter's independent user manager cannot discover or
  # activate the desktop secret-service stack. Debian's D-Bus activation owns
  # the on-demand kwalletd6 compatibility daemon.
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/labwc-kwallet-portal.service __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-kwallet-portal.service 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/labwc-kwallet-portal.service "${DIR_USR_LOCAL_SHARE}/labwc-app/defaults/labwc-kwallet-portal.service" 0644
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-hyprpolkit-agent __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-hyprpolkit-agent 0755 || return 1
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/labwc-output-watch.service __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-output-watch.service 0644
  # The DevOps class helper renders and publishes the Codex units, environment
  # policy, and readiness helper before the desktop role runs. Do not copy the
  # source templates here: their installer placeholders must never reach the
  # target skeleton or overwrite the rendered class-owned files.
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/swaybg.service __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/swaybg.service 0644
  if desktop_kanshi_enabled; then
    desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/kanshi.service __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/kanshi.service 0644
  fi
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/swayidle.service __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/swayidle.service 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/crystal-dock.service __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/crystal-dock.service 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/labwc-mute-default-microphone.service __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-mute-default-microphone.service 0644
  if desktop_whisper_class_selected; then
    desktop_stage_role_asset hooks/target/etc/tmpfiles.d/desktop/55-whisper-runtime.conf __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/55-whisper-runtime.conf 0644
    desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/whisper-record.service __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/whisper-record.service 0644
    desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/whisper-transcribe.service __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/whisper-transcribe.service 0644
    if desktop_whisper_persistent_memory_enabled; then
      desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/whisper-server.service __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/whisper-server.service 0644
    fi
  fi
  # systemd dependency directives cannot be removed from a vendor unit with a
  # drop-in. Install the complete managed unit so no graphical-session.target
  # dependency survives Debian's Waybar unit. Labwc autostart requests it only
  # after activating the compositor session target, so LABWC_ENABLE_WAYBAR
  # remains the authoritative policy gate.
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/waybar.service __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/waybar.service 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/waybar.service.d/20-tray-compat.conf __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/waybar.service.d/20-tray-compat.conf 0644
  # The package defaults to a global preload. Scope decoration conversion to
  # Agenda through its managed profile instead of changing the whole session.
  desktop_stage_role_asset hooks/target/etc/environment.d/50-gtk-nocsd.conf __INSTALLER_PATH_DIR_ETC__/environment.d/50-gtk-nocsd.conf 0644
  if [ -x ${TARGET_ROOT}${DIR_OPT}/microsoft/msedge/msedge ]; then
    installer_asset_batch_flush || return $?
    install -d -m 0755 ${TARGET_ROOT}${DIR_OPT}/microsoft/msedge/extensions
  fi
  desktop_stage_role_asset hooks/target/etc/wireplumber/wireplumber.conf.d/10-disable-bluez-midi.conf __INSTALLER_PATH_DIR_ETC__/wireplumber/wireplumber.conf.d/10-disable-bluez-midi.conf 0644
  desktop_stage_role_asset hooks/target/etc/wireplumber/wireplumber.conf.d/20-audio-policy.conf __INSTALLER_PATH_DIR_ETC__/wireplumber/wireplumber.conf.d/20-audio-policy.conf 0644
  desktop_stage_role_asset hooks/target/etc/pipewire/client.conf.d/20-volume-ceiling.conf __INSTALLER_PATH_DIR_ETC__/pipewire/client.conf.d/20-volume-ceiling.conf 0644
  desktop_stage_role_asset hooks/target/etc/pipewire/pipewire-pulse.conf.d/20-volume-ceiling.conf __INSTALLER_PATH_DIR_ETC__/pipewire/pipewire-pulse.conf.d/20-volume-ceiling.conf 0644
  desktop_stage_role_asset "$(installer_repo_apt_file listchanges.conf)" __INSTALLER_PATH_DIR_ETC__/apt/listchanges.conf 0644
  desktop_stage_role_asset "$(installer_repo_apt_file apt.conf.d/60desktop-local-mail.conf)" __INSTALLER_PATH_DIR_ETC__/apt/apt.conf.d/60desktop-local-mail.conf 0644
  desktop_stage_role_asset hooks/target/etc/chromium/policies/managed/telemetry.json __INSTALLER_PATH_DIR_ETC__/chromium/policies/managed/telemetry.json 0644
  desktop_stage_role_asset hooks/target/etc/chromium/policies/managed/security.json __INSTALLER_PATH_DIR_ETC__/chromium/policies/managed/security.json 0644
  desktop_stage_role_asset hooks/target/etc/chromium/policies/managed/extensions.json __INSTALLER_PATH_DIR_ETC__/chromium/policies/managed/extensions.json 0644
  desktop_stage_role_asset hooks/target/etc/chromium/policies/managed/performance.json __INSTALLER_PATH_DIR_ETC__/chromium/policies/managed/performance.json 0644
  desktop_stage_role_asset hooks/target/etc/chromium/policies/recommended/defaults.json __INSTALLER_PATH_DIR_ETC__/chromium/policies/recommended/defaults.json 0644
  desktop_stage_role_asset hooks/target/etc/opt/edge/policies/managed/telemetry.json __INSTALLER_PATH_DIR_ETC__/opt/edge/policies/managed/telemetry.json 0644
  desktop_stage_role_asset hooks/target/etc/opt/edge/policies/managed/security.json __INSTALLER_PATH_DIR_ETC__/opt/edge/policies/managed/security.json 0644
  desktop_stage_role_asset hooks/target/etc/opt/edge/policies/managed/extensions.json __INSTALLER_PATH_DIR_ETC__/opt/edge/policies/managed/extensions.json 0644
  desktop_stage_role_asset hooks/target/etc/opt/edge/policies/managed/performance.json __INSTALLER_PATH_DIR_ETC__/opt/edge/policies/managed/performance.json 0644
  desktop_stage_role_asset hooks/target/etc/opt/edge/policies/recommended/defaults.json __INSTALLER_PATH_DIR_ETC__/opt/edge/policies/recommended/defaults.json 0644
  desktop_stage_role_asset hooks/target/etc/vivaldi/policies/managed/telemetry.json __INSTALLER_PATH_DIR_ETC__/vivaldi/policies/managed/telemetry.json 0644
  desktop_stage_role_asset hooks/target/etc/vivaldi/policies/managed/extensions.json __INSTALLER_PATH_DIR_ETC__/vivaldi/policies/managed/extensions.json 0644
  desktop_stage_role_asset hooks/target/etc/vivaldi/policies/managed/security.json __INSTALLER_PATH_DIR_ETC__/vivaldi/policies/managed/security.json 0644
  desktop_stage_role_asset hooks/target/etc/vivaldi/policies/managed/performance.json __INSTALLER_PATH_DIR_ETC__/vivaldi/policies/managed/performance.json 0644
  desktop_stage_role_asset hooks/target/etc/vivaldi/policies/recommended/defaults.json __INSTALLER_PATH_DIR_ETC__/vivaldi/policies/recommended/defaults.json 0644
  desktop_stage_role_asset hooks/target/etc/vivaldi/search-engines/search_engines.json.signed __INSTALLER_PATH_DIR_ETC__/vivaldi/search-engines/search_engines.json.signed 0644
  desktop_stage_role_asset hooks/target/etc/vivaldi/search-engines/search_engines_prompt.json.signed __INSTALLER_PATH_DIR_ETC__/vivaldi/search-engines/search_engines_prompt.json.signed 0644
  desktop_stage_role_asset hooks/target/etc/opt/chrome/policies/managed/security.json __INSTALLER_PATH_DIR_ETC__/opt/chrome/policies/managed/security.json 0644
  desktop_stage_role_asset hooks/target/etc/opt/chrome/policies/managed/extensions.json __INSTALLER_PATH_DIR_ETC__/opt/chrome/policies/managed/extensions.json 0644
  desktop_stage_role_asset hooks/target/etc/opt/chrome/policies/managed/telemetry.json __INSTALLER_PATH_DIR_ETC__/opt/chrome/policies/managed/telemetry.json 0644
  desktop_stage_role_asset hooks/target/etc/opt/chrome/policies/managed/performance.json __INSTALLER_PATH_DIR_ETC__/opt/chrome/policies/managed/performance.json 0644
  desktop_stage_role_asset hooks/target/etc/opt/chrome/policies/recommended/defaults.json __INSTALLER_PATH_DIR_ETC__/opt/chrome/policies/recommended/defaults.json 0644
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/browser-devtools __INSTALLER_PATH_DIR_USR_LOCAL__/bin/browser-devtools 0755
  desktop_stage_role_asset \
    hooks/target/usr/share/glib-2.0/schemas/90-desktop-wsdd.gschema.override \
    __INSTALLER_PATH_DIR_USR_SHARE__/glib-2.0/schemas/90-desktop-wsdd.gschema.override \
    0644
  desktop_stage_role_asset hooks/target/etc/xdg/xdg-desktop-portal/labwc-portals.conf __INSTALLER_PATH_DIR_ETC__/xdg/xdg-desktop-portal/labwc-portals.conf 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.gnupg/gpg-agent.conf __INSTALLER_PATH_DIR_ETC__/skel-desktop/.gnupg/gpg-agent.conf 0600
  installer_asset_batch_flush || return $?
  chmod 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.gnupg
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/obsidian-git-sync.timer __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/obsidian-git-sync.timer 0644
  desktop_render_role_target_template \
    hooks/target/etc/obsidian-git-sync.conf.tmpl __INSTALLER_PATH_DIR_ETC__/obsidian-git-sync.conf 0644 \
    OBSIDIAN_GIT_AUTO_ENABLE "$OBSIDIAN_GIT_AUTO_ENABLE" \
    OBSIDIAN_GIT_REPOSITORY_URL "$OBSIDIAN_GIT_REPOSITORY_URL" \
    OBSIDIAN_GIT_REPOSITORY_BRANCH "$OBSIDIAN_GIT_REPOSITORY_BRANCH" \
    OBSIDIAN_GIT_DIRECTORY "$OBSIDIAN_GIT_DIRECTORY"
  desktop_render_role_target_template \
    hooks/target/etc/skel-desktop/.config/systemd/user/obsidian-git-sync.service \
    __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/obsidian-git-sync.service \
    0644 \
    OBSIDIAN_GIT_DIRECTORY "$OBSIDIAN_GIT_DIRECTORY"
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/obsidian-git-sync __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/obsidian-git-sync 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/obsidian-git-sync.py __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/obsidian-git-sync.py 0755

  desktop_extract_role_wallpaper_archive
  # Publish explicit defaults after archive extraction, so an archive member
  # cannot overwrite a differently named user-selected default.
  desktop_stage_wallpaper_defaults || return $?
  desktop_normalize_background_directories
#  desktop_stage_role_asset_tree usr/share/backgrounds/other __INSTALLER_PATH_DIR_USR_SHARE__/backgrounds/other

  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/labwc/autostart __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/labwc/autostart 0755
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/labwc/shutdown __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/labwc/shutdown 0755
  desktop_stage_labwc_user_session_assets
  remove_target_asset __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/labwc/xinitrc
  remove_target_asset __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/gsimplecal/config
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/labwc/themerc-override.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/labwc/themerc-override 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/waypaper/config.ini.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/waypaper/config.ini 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/waypaper/keybindings.ini __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/waypaper/keybindings.ini 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/waypaper/style.css __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/waypaper/style.css 0644
  desktop_render_labwc_rc_xml
  desktop_render_role_target_template \
    hooks/target/etc/skel-desktop/.config/labwc/menu.xml.tmpl \
    "__INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/labwc/menu.xml" \
    0644 \
    ACCOUNT_HOME "$ACCOUNT_HOME"
  desktop_render_waybar_config
  desktop_render_waybar_style
  installer_asset_batch_flush || return $?
  installer_run_target_setup scripts/desktop/waybar-menus.py 'validate rendered native Waybar menus and fixed dispatch' \
    "${DIR_ETC_SKEL_DESKTOP}/.config/waybar" "${DIR_USR_LOCAL_LIBEXEC}/labwc-waybar-run"
  desktop_render_kanshi_config
  desktop_render_terminal_configs
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/mpv/mpv.conf.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/mpv/mpv.conf 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/mpv/input.conf __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/mpv/input.conf 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/l3afpad/l3afpadrc __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/l3afpad/l3afpadrc 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/GottCode/FocusWriter.conf.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/GottCode/FocusWriter.conf 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/zathura/zathurarc.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/zathura/zathurarc 0644
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-focuswriter-import __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-focuswriter-import 0755
  desktop_stage_role_asset hooks/target/usr/local/share/desktop/applications/labwc-focuswriter-import.desktop.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/labwc-focuswriter-import.desktop 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.local/share/GottCode/FocusWriter/Themes/word.theme.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.local/share/GottCode/FocusWriter/Themes/word.theme 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/Recoll.org/recoll.ini.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/Recoll.org/recoll.ini 0600
  installer_asset_batch_flush || return $?
  chmod 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/Recoll.org
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.recoll/recoll.conf __INSTALLER_PATH_DIR_ETC__/skel-desktop/.recoll/recoll.conf 0644
  installer_asset_batch_flush || return $?
  chmod 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.recoll
  installer_asset_batch_flush || return $?
  install -d -m 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.cache ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.cache/recoll
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/kdiff3rc __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/kdiff3rc 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/micro/settings.json __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/micro/settings.json 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/nano/nanorc __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/nano/nanorc 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/nvim/init.lua.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/nvim/init.lua 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/qalculate/qalc.cfg __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/qalculate/qalc.cfg 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/qalculate/qalculate-qt.cfg __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/qalculate/qalculate-qt.cfg 0644
  installer_asset_batch_flush || return $?
  install -d -m 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/lxqt
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/lxqt/filedialog.conf __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/lxqt/filedialog.conf 0644
  installer_asset_batch_flush || return $?
  install -d -m 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/xarchiver
  desktop_render_role_target_template \
    hooks/target/etc/skel-desktop/.config/xarchiver/xarchiverrc.tmpl \
    __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/xarchiver/xarchiverrc \
    0600 \
    ACCOUNT_USERNAME "$ACCOUNT_USERNAME" \
    DIR_HOME_DOWNLOADS "$DIR_HOME_DOWNLOADS"
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/task/taskrc.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/task/taskrc 0644
  installer_asset_batch_flush || return $?
  install -d -m 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.local/share/task ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.local/share/task/hooks
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/vim/vimrc __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/vim/vimrc 0644
  desktop_render_note_app_defaults
  desktop_compile_glib_schemas
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/xdg-terminals.list __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/xdg-terminals.list 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/mimeapps.list __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/mimeapps.list 0600
  desktop_stage_role_asset hooks/target/etc/xdg/mimeapps.list __INSTALLER_PATH_DIR_ETC__/xdg/mimeapps.list 0644
  desktop_stage_role_asset hooks/target/usr/share/mime/packages/90-desktop-filetypes.xml __INSTALLER_PATH_DIR_USR_SHARE__/mime/packages/90-desktop-filetypes.xml 0644
  run_in_target "update managed desktop MIME database" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
test -x __INSTALLER_PATH_DIR_USR_BIN__/update-mime-database
__INSTALLER_PATH_DIR_USR_BIN__/update-mime-database __INSTALLER_PATH_DIR_USR_SHARE__/mime
' sh
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/xfce4/helpers.rc __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/xfce4/helpers.rc 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/retroarch/retroarch.cfg __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/retroarch/retroarch.cfg 0644
  installer_asset_batch_flush || return $?
  install -d -m 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/sleek/userData
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/sleek/userData/colors.json.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/sleek/userData/colors.json 0600
  desktop_render_role_target_template \
    hooks/target/etc/skel-desktop/.config/sleek/userData/config.json.tmpl \
    "__INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/sleek/userData/config.json" \
    0600 \
    ACCOUNT_HOME "$ACCOUNT_HOME"
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/sleek/userData/filters.json __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/sleek/userData/filters.json 0600
  desktop_stage_role_asset hooks/target/usr/share/xfce4/helpers/foot.desktop.tmpl __INSTALLER_PATH_DIR_USR_SHARE__/xfce4/helpers/foot.desktop 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/fontconfig/conf.d/60-labwc-terminal-fonts.conf __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/fontconfig/conf.d/60-labwc-terminal-fonts.conf 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/fontconfig/conf.d/61-microsoft-fonts.conf __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/fontconfig/conf.d/61-microsoft-fonts.conf 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.profile __INSTALLER_PATH_DIR_ETC__/skel-desktop/.profile 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.bash_profile __INSTALLER_PATH_DIR_ETC__/skel-desktop/.bash_profile 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.bashrc __INSTALLER_PATH_DIR_ETC__/skel-desktop/.bashrc 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.bash_aliases __INSTALLER_PATH_DIR_ETC__/skel-desktop/.bash_aliases 0644
  installer_asset_batch_flush || return $?
  install -d -m 0755 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.profile.d
  if installer_tools_class_selected; then
  desktop_render_role_target_template \
    hooks/target/etc/skel-desktop/.profile.d/71-devops-de.sh "${DIR_ETC_SKEL_DESKTOP}/.profile.d/71-devops-de.sh" 0644 \
    HARDWARE_CPU_SCHEDULER_SCX_WORKER_PERFORMANCE "$HARDWARE_CPU_SCHEDULER_SCX_WORKER_PERFORMANCE"
  installer_asset_batch_flush || return $?
  install -d -m 0755 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/cargo
  desktop_render_cargo_config
  installer_asset_batch_flush || return $?
  install -d -m 0755 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/mise/conf.d
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/mise/config.toml __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/mise/config.toml 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/mise/config.development.toml __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/mise/config.development.toml 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/mise/config.local.toml __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/mise/config.local.toml 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/mise/config.development.local.toml __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/mise/config.development.local.toml 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/mise/conf.d/10-tools.toml __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/mise/conf.d/10-tools.toml 0644
  fi
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.zshenv __INSTALLER_PATH_DIR_ETC__/skel-desktop/.zshenv 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.zprofile __INSTALLER_PATH_DIR_ETC__/skel-desktop/.zprofile 0644
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labmgmt __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labmgmt 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/common/gitops __INSTALLER_PATH_DIR_USR_LOCAL__/bin/gitops 0755
  desktop_stage_role_asset hooks/target/usr/local/share/common/doc/git/README.md.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/share/doc/git/README.md 0644
  desktop_stage_role_asset hooks/target/etc/gitops/aliases.gitconfig __INSTALLER_PATH_DIR_ETC__/gitops/aliases.gitconfig 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/gitops/gitops.env __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/gitops/gitops.env 0600
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/git/config __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/git/config 0644
  desktop_stage_role_asset hooks/target/usr/local/libexec/common/ssh-checks __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/ssh-checks 0644
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-ssh-key-load __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-ssh-key-load 0755
  desktop_stage_role_asset hooks/target/usr/local/libexec/desktop/labwc-ssh-gpg-askpass __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-ssh-gpg-askpass 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/common/git-ssh __INSTALLER_PATH_DIR_USR_LOCAL__/bin/git-ssh 0755
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/systemd/user/labwc-ssh-key-load.service __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-ssh-key-load.service 0644
  desktop_stage_role_asset hooks/target/etc/systemd/desktop/user/ssh-agent.socket.d/10-labwc-session.conf __INSTALLER_PATH_DIR_SYSTEMD_USER_SSH_AGENT_SOCKET_DROPIN__/10-labwc-session.conf 0644
  desktop_stage_role_asset hooks/target/etc/systemd/desktop/user/ssh-agent.service.d/10-labwc-session.conf __INSTALLER_PATH_DIR_SYSTEMD_USER_SSH_AGENT_DROPIN__/10-labwc-session.conf 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.zshrc.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.zshrc 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.zlogout __INSTALLER_PATH_DIR_ETC__/skel-desktop/.zlogout 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.zsh_aliases __INSTALLER_PATH_DIR_ETC__/skel-desktop/.zsh_aliases 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/skel-desktop/.dircolors)" __INSTALLER_PATH_DIR_ETC__/skel-desktop/.dircolors 0644
  desktop_log "staged_asset source=$(installer_repo_file_value hooks/target/etc/skel-desktop/.dircolors) target=__INSTALLER_PATH_DIR_ETC__/skel-desktop/.dircolors mode=0644"
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/starship.toml.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/starship.toml 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/btop/btop.conf.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/btop/btop.conf 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/btop/btop-cpu.conf.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/btop/btop-cpu.conf 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/btop/btop-memory.conf.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/btop/btop-memory.conf 0644
  desktop_stage_btop_profiles
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/fzf/default-opts.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/fzf/default-opts 0644
  desktop_render_fuzzel_configs
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/Thunar/uca.xml __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/Thunar/uca.xml 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/tesseract/ocr-defaults.conf __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/tesseract/ocr-defaults.conf 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/tesseract/user-words/default.user-words __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/tesseract/user-words/default.user-words 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/tesseract/user-words/eng.user-words __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/tesseract/user-words/eng.user-words 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/tesseract/user-words/swe.user-words __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/tesseract/user-words/swe.user-words 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/tesseract/user-patterns/default.user-patterns __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/tesseract/user-patterns/default.user-patterns 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/tesseract/user-patterns/eng.user-patterns __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/tesseract/user-patterns/eng.user-patterns 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/tesseract/user-patterns/swe.user-patterns __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/tesseract/user-patterns/swe.user-patterns 0644
  desktop_render_crystal_dock_appearance
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/crystal-dock/labwc/panel_1.conf __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/crystal-dock/labwc/panel_1.conf 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/crystal-dock/labwc/panel_1.conf __INSTALLER_PATH_DIR_ETC__/xdg/crystal-dock/labwc/panel_1.conf 0644
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-show-desktop __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-show-desktop 0755
  desktop_stage_role_asset hooks/target/usr/local/bin/desktop/labwc-health-notify.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-health-notify 0755
  desktop_stage_role_asset hooks/target/usr/local/share/desktop/applications/show-desktop.desktop.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/show-desktop.desktop 0644
  desktop_normalize_public_desktop_directories
  desktop_stage_role_asset hooks/target/usr/local/share/desktop/applications/labwc-tweaks.desktop.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/labwc-tweaks.desktop 0644
  desktop_stage_role_asset hooks/target/usr/local/share/desktop/applications/hyprpolkitagent.desktop.tmpl __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/hyprpolkitagent.desktop 0644
  desktop_stage_role_asset hooks/target/usr/local/share/desktop/icons/hicolor/64x64/apps/show-desktop.png __INSTALLER_PATH_DIR_USR_LOCAL__/share/icons/hicolor/64x64/apps/show-desktop.png 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/mako/config.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/mako/config 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/satty/config.toml.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/satty/config.toml 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/wayscriber/config.toml.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/wayscriber/config.toml 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/satty/overrides.css.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/satty/overrides.css 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/swaylock/config.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/swaylock/config 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/wireplumber/wireplumber.conf.d/10-disable-bluez-midi.conf __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/wireplumber/wireplumber.conf.d/10-disable-bluez-midi.conf 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/wireplumber/wireplumber.conf.d/20-audio-policy.conf __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/wireplumber/wireplumber.conf.d/20-audio-policy.conf 0644
  case "${requested_host_profile:-${HOST_PROFILE:-}}" in
    btrfs-de-p15s|btrfs-de-p15s-duo)
      desktop_stage_role_asset hooks/target/usr/share/wireplumber/scripts/p15s-speaker-profile.lua __INSTALLER_PATH_DIR_USR_SHARE__/wireplumber/scripts/p15s-speaker-profile.lua 0644
      ;;
  esac
  for audio_dir in __INSTALLER_PATH_DIR_ETC__/wireplumber/wireplumber.conf.d __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/wireplumber/wireplumber.conf.d; do
    case "${requested_host_profile:-${HOST_PROFILE:-}}" in
      btrfs-de-p15s|btrfs-de-p15s-duo)
        desktop_stage_role_asset hooks/target/etc/wireplumber/wireplumber.conf.d/30-p15s-audio.conf "$audio_dir/30-p15s-audio.conf" 0644
        ;;
      *) rm -f "${TARGET_ROOT}$audio_dir/30-p15s-audio.conf" ;;
    esac
  done
  desktop_render_gtk_settings
  desktop_render_qt6ct_config
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/kwalletrc __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/kwalletrc 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/kwalletrc "${DIR_USR_LOCAL_SHARE}/labwc-app/defaults/kwalletrc" 0644
  installer_asset_batch_flush || return $?
  install -d -m 0700 \
    ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/Code/User \
    ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/chromium/Default \
    ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/microsoft-edge/Default \
    ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/obsidian \
    ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/vivaldi/Default
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/Code/User/settings.json.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/Code/User/settings.json 0600
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/chromium/Default/Preferences __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/chromium/Default/Preferences 0600
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/microsoft-edge/Default/Preferences __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/microsoft-edge/Default/Preferences 0600
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/obsidian/obsidian.json __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/obsidian/obsidian.json 0600
  desktop_stage_role_asset "hooks/target/etc/skel-desktop/.config/vivaldi/Local State" "__INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/vivaldi/Local State" 0600
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/vivaldi/Default/Preferences __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/vivaldi/Default/Preferences 0600
  # The sandbox session seeds missing Vivaldi caches from signed vendor data;
  # subsequent cache updates remain owned by the browser.
  desktop_stage_syncthing_ignore
  installer_asset_batch_flush || return $?
  install -d -m 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/keepassxc
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/keepassxc/keepassxc.ini.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/keepassxc/keepassxc.ini 0600
  # Non-secret fallback defaults for unprivileged runtime repair. The private
  # skeleton is reserved for privileged provisioning of future accounts.
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/keepassxc/keepassxc.ini.tmpl "${DIR_USR_LOCAL_SHARE}/keepassxc/keepassxc.ini" 0644
  installer_asset_batch_flush || return $?
  chmod 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/keepassxc
  installer_asset_batch_flush || return $?
  install -d -m 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/zoom
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/zoom/zoomus.conf.tmpl __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/zoom/zoomus.conf 0600
  installer_asset_batch_flush || return $?
  chmod 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/zoom
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/xdg-desktop-portal/portals.conf __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/xdg-desktop-portal/portals.conf 0644
  desktop_stage_role_asset hooks/target/etc/skel-desktop/.config/user-dirs.dirs __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/user-dirs.dirs 0644
  desktop_render_chromium_flags
  installer_asset_batch_finish
}

# Desktop boot recovery ordering is not inherited by headless services.
desktop_stage_apparmor_recovery_order() {
  desktop_stage_role_asset hooks/target/etc/systemd/desktop/system/apparmor-modes.service.d/50-desktop-recovery.conf "${DIR_SYSTEMD_SYSTEM_APPARMOR_MODES_DROPIN}/50-desktop-recovery.conf" 0644
}
