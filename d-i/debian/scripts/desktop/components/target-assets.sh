#!/bin/sh
# Sourced installer module; edit this file directly.

desktop_stage_session_repairs() {
  for public_directory in __INSTALLER_PATH_DIR_ETC__/udev __INSTALLER_PATH_DIR_ETC__/udev/hwdb.d; do
    ensure_target_asset_parent "${public_directory}/.installer-parent"
    public_host=$(target_asset_host_path "$public_directory")
    [ ! -L "$public_host" ] || installer_fatal "unsafe system configuration directory: $public_directory"
    chown root:root "$public_host"
    chmod 0755 "$public_host"
  done
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_WALLPAPER_CONTROL __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-wallpaper-control 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_NOTIFICATION_SEND_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-notification-send 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_CONFIGURE_SESSION_REPAIRS __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-configure-session-repairs 0755
  desktop_stage_role_asset FILE_TARGET_SECURITY_SUDO_I __INSTALLER_PATH_DIR_ETC__/security/sudo-i.conf 0644
  desktop_stage_role_asset FILE_TARGET_SECURITY_CRON_SESSION __INSTALLER_PATH_DIR_ETC__/security/cron-session.conf 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_XFCE4_XFCONF_XFCE_PERCHANNEL_XML_XSETTINGS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml 0644
  run_in_target "build target keyboard hardware database" __INSTALLER_PATH_DIR_USR_BIN__/systemd-hwdb --strict update
  run_in_target "configure managed session repairs" __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-configure-session-repairs \
    "$ACCOUNT_USERNAME"
}

desktop_stage_wlsunset() {
  desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_LABWC_WLSUNSET_START_SERVICE __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-wlsunset-start.service 0644
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_WLSUNSET __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-wlsunset 0755
  desktop_render_role_target_template \
    FILE_TARGET_LABWC_WLSUNSET_TMPL __INSTALLER_PATH_DIR_ETC__/labwc/wlsunset.conf 0644 \
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

  run_in_target "validate managed wlsunset configuration" __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-wlsunset check
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
  desktop_stage_role_asset FILE_TARGET_SKEL_TOMAT_CONFIG_TMPL \
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
    FILE_TARGET_SHARE_LABWC_HELP_CATALOG_TMPL \
    "${DIR_USR_LOCAL_SHARE}/labwc-help/catalog.json" 0644
  desktop_render_role_target_template \
    FILE_TARGET_SHARE_LABWC_HELP_THEME_TMPL \
    "${DIR_USR_LOCAL_SHARE}/labwc-help/theme.json" 0644
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_HELP __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-help 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_HELP_GTK __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-help-gtk 0755
  desktop_render_role_target_template \
    FILE_TARGET_APPS_LABWC_HELP_TMPL \
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
  desktop_stage_role_asset FILE_TARGET_BIN_KEY_MANAGER __INSTALLER_PATH_DIR_USR_LOCAL__/bin/key-manager 0755
  desktop_stage_role_asset FILE_TARGET_SKEL_GNUPG_GPG_AGENT \
    "${DIR_USR_LOCAL_SHARE}/key-manager/gpg-agent.conf" 0644
  for module in __init__ fs; do
    path="usr/local/lib/python3/dist-packages/managed_workflows/${module}.py"
    desktop_stage_role_asset "$path" "${DIR_PYTHON3_SITE_PACKAGES}/managed_workflows/${module}.py" 0644
  done
  for module in __init__ core cli ssh gpg tls tls_profiles pqc; do
    path="usr/local/lib/python3/dist-packages/key_manager/${module}.py"
    desktop_stage_role_asset "$path" "${DIR_PYTHON3_SITE_PACKAGES}/key_manager/${module}.py" 0644
  done
  desktop_render_role_target_template FILE_TARGET_KEY_MANAGER_SETTINGS_TMPL \
    __INSTALLER_PATH_DIR_ETC__/key-manager/settings.json 0644 \
    DIR_DATA_PKI "$DIR_DATA_PKI" ACCOUNT_USERNAME "$ACCOUNT_USERNAME"
  desktop_stage_role_asset FILE_TARGET_KEY_MANAGER_CERTBOT __INSTALLER_PATH_DIR_ETC__/key-manager/certbot.ini 0644
  desktop_stage_role_asset FILE_TARGET_UNIT_KEY_MANAGER_ACME_RENEW_TIMER \
    __INSTALLER_PATH_DIR_ETC__/systemd/system/key-manager-acme-renew.timer 0644
  desktop_render_role_target_template FILE_TARGET_UNIT_KEY_MANAGER_ACME_RENEW_SERVICE_TMPL \
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
  stage_target_asset "$(installer_repo_file_value FILE_DESKTOP_FANGFRISCH_CONFIGURE)" \
    "${fangfrisch_stage}/configure.py" 0600
  desktop_render_role_target_template \
    FILE_TARGET_FANGFRISCH_TMPL \
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
  desktop_stage_role_asset FILE_TARGET_PAM_D_GREETD __INSTALLER_PATH_DIR_ETC__/pam.d/greetd 0644
  desktop_stage_role_asset FILE_TARGET_PAM_D_GREETD_GREETER __INSTALLER_PATH_DIR_ETC__/pam.d/greetd-greeter 0644
  desktop_stage_role_asset FILE_TARGET_SECURITY_GREETD_GREETER __INSTALLER_PATH_DIR_ETC__/security/greetd-greeter.conf 0644
  desktop_render_role_target_template \
    FILE_TARGET_DBUS_1_SESSION_D_70_LABWC_GREETER_NO_PORTALS_TMPL \
    __INSTALLER_PATH_DIR_ETC__/dbus-1/session.d/70-labwc-greeter-no-portals.conf 0644 \
    LABWC_GREETER_USER "$LABWC_GREETER_USER"
  desktop_stage_role_asset FILE_TARGET_PAM_D_SWAYLOCK __INSTALLER_PATH_DIR_ETC__/pam.d/swaylock 0644
  desktop_stage_role_asset FILE_TARGET_SYSTEMD_LOGIND_CONF_D_70_LABWC_LOCK __INSTALLER_PATH_DIR_ETC__/systemd/logind.conf.d/70-labwc-lock.conf 0644
  desktop_stage_role_asset FILE_TARGET_USR_SHARE_PAM_CONFIGS_WTMPDB __INSTALLER_PATH_DIR_USR_SHARE__/pam-configs/wtmpdb 0644
  desktop_reconcile_wtmpdb_common_session ${TARGET_ROOT}
  desktop_render_labwc_session_wrappers
  # systemd's dash-prefix drop-ins also cover future application names and
  # transient UUIDs. Keep session daemons outside these application families.
  for application_family in wayland electron native devops bitwarden qbittorrent compat; do
    desktop_stage_role_asset FILE_TARGET_USER_UNIT_LABWC_NATIVE_FAMILY_SERVICE_D_50_APP_LIFECYCLE \
      "$(installer_systemd_dropin_dir user "labwc-${application_family}-.service")/50-app-lifecycle.conf" 0644
  done
  desktop_stage_role_asset FILE_TARGET_USER_UNIT_LABWC_WAYLAND_FOOT_FAMILY_SERVICE_D_60_TERMINAL_LIFECYCLE \
    __INSTALLER_PATH_DIR_SYSTEMD_USER_LABWC_WAYLAND_FOOT_FAMILY_DROPIN__/60-terminal-lifecycle.conf 0644
  desktop_stage_role_asset FILE_TARGET_USER_UNIT_LABWC_DEVOPS_FAMILY_SERVICE_D_60_STOP_BUDGET \
    __INSTALLER_PATH_DIR_SYSTEMD_USER_LABWC_DEVOPS_FAMILY_DROPIN__/60-stop-budget.conf 0644
  desktop_configure_local_mail_delivery
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_AUTOSTART __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-autostart 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_WALLPAPER_SAVE __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-wallpaper-save 0755
  desktop_render_role_target_template FILE_TARGET_BIN_LABWC_ADMIN_ACTION_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-admin-action 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_ADMIN_ACTION_ROOT __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-admin-action-root 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_ADMIN_ACTION_WORKER __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-admin-action-worker 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_LOGOUT_ROOT __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-logout-root 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_SESSION_STATE_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-session-state 0755
  desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_LABWC_SESSION_STATE_INSTANCE_SERVICE __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-session-state@.service 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_LABWC_SESSION_STATE_INSTANCE_PREPARE_SERVICE_D_RETAIN_RESULT __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-session-state@prepare.service.d/retain-result.conf 0644
  desktop_stage_role_asset FILE_TARGET_UNIT_LABWC_ADMIN_ACTION_INSTANCE_SERVICE_TMPL __INSTALLER_PATH_DIR_ETC__/systemd/system/labwc-admin-action@.service 0644
  desktop_stage_role_asset FILE_TARGET_UNIT_LABWC_EXTERNAL_DRIVES_SHUTDOWN_SERVICE __INSTALLER_PATH_DIR_ETC__/systemd/system/labwc-external-drives-shutdown.service 0644
  desktop_render_role_target_template \
    FILE_TARGET_UNIT_LABWC_PACKAGE_SLEEP_GUARD_SERVICE_TMPL \
    __INSTALLER_PATH_DIR_ETC__/systemd/system/labwc-package-sleep-guard.service 0644 \
    LOG_POWER_DIR "$LOG_POWER_DIR"
  desktop_stage_role_asset FILE_TARGET_UNIT_SLEEP_TARGET_D_50_PACKAGE_LOCK_GUARD __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_SLEEP_TARGET_DROPIN__/50-package-lock-guard.conf 0644
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_GREETD_POWER_ACTION_ROOT __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/greetd-power-action-root 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_CALIX_FRUUX_BOOTSTRAP __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/calix-fruux-bootstrap 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_WAYCAL_CONTROL __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-waycal-control 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_WAYCAL_POPUP __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-waycal-popup 0755
  desktop_stage_role_asset FILE_TARGET_SKEL_GTK_4_0_GTK_CSS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/gtk-4.0/gtk.css 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_GTK_3_0_GTK_CSS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/gtk-3.0/gtk.css 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_L3AFPAD_STYLE_CSS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/l3afpad/style.css 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_WAYCAL_STYLE_CSS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/waycal/style.css 0644
  desktop_render_role_target_template FILE_TARGET_APPS_COM_IANSWOPE_CALIX_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/com.ianswope.Calix.desktop 0644
  desktop_render_role_target_template FILE_TARGET_APPS_LABWC_CALENDAR_ACTIONS_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/labwc-calendar-actions.desktop 0644
  # Public commands share the managed launcher, including terminal launches.
  for calendar_alias in labwc-agenda labwc-calendar; do
    ensure_target_asset_parent "__INSTALLER_PATH_DIR_USR_LOCAL__/bin/$calendar_alias"
    calendar_alias_host=$(target_asset_host_path "__INSTALLER_PATH_DIR_USR_LOCAL__/bin/$calendar_alias")
    ln -sfnT labwc-app "$calendar_alias_host"
  done
  unset calendar_alias calendar_alias_host
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_CALENDAR_ACTIONS __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-calendar-actions 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_CALENDAR_WORKER __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-calendar-worker 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_CALENDAR_REMINDERS_GTK __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-calendar-reminders-gtk 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_LOCAL_REMINDER_WORKER __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-local-reminder-worker 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_NEW_LOCAL_REMINDER __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-new-local-reminder 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_REMINDER_MANAGER __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-reminder-manager 0755
  desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_LABWC_LOCAL_REMINDERS_SERVICE \
    __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-local-reminders.service 0644
  desktop_stage_role_asset FILE_TARGET_PY_LABWC_CALENDAR_REMINDERS __INSTALLER_PATH_DIR_PYTHON3_SITE_PACKAGES__/labwc_calendar_reminders.py 0644
  desktop_stage_role_asset FILE_TARGET_PY_LABWC_LOCAL_REMINDERS __INSTALLER_PATH_DIR_PYTHON3_SITE_PACKAGES__/labwc_local_reminders.py 0644
  desktop_stage_role_asset FILE_TARGET_PY_LABWC_CALENDAR_REMINDERS_GTK __INSTALLER_PATH_DIR_PYTHON3_SITE_PACKAGES__/labwc_calendar_reminders_gtk.py 0644
  desktop_stage_role_asset FILE_TARGET_PY_LABWC_DESKTOP_RUNTIME __INSTALLER_PATH_DIR_PYTHON3_SITE_PACKAGES__/labwc_desktop_runtime.py 0644
  desktop_render_role_target_template FILE_TARGET_APPS_COM_GITHUB_DAHENSON_AGENDA_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/com.github.dahenson.agenda.desktop 0644
  desktop_stage_role_asset FILE_TARGET_SHARE_AGENDA_SCHEMAS_90_DESKTOP_AGENDA_GSCHEMA_OVERRIDE __INSTALLER_PATH_DIR_USR_LOCAL__/share/agenda/schemas/90-desktop-agenda.gschema.override 0644
  desktop_render_role_target_template FILE_TARGET_UNIT_FRUUX_FIRSTBOOT_SERVICE_TMPL \
    __INSTALLER_PATH_DIR_ETC__/systemd/system/fruux-firstboot.service 0644 \
    ACCOUNT_USERNAME "$ACCOUNT_USERNAME" ACCOUNT_HOME "$ACCOUNT_HOME"
  desktop_render_role_target_template FILE_TARGET_VAR_LIB_FIRSTBOOT_BIN_FRUUX_CLEANUP_TMPL \
    __INSTALLER_PATH_DIR_VAR__/lib/firstboot/bin/fruux-cleanup 0755 ACCOUNT_USERNAME "$ACCOUNT_USERNAME"
  desktop_stage_role_asset FILE_TARGET_UNIT_GREETD_SERVICE_D_40_FRUUX_FIRSTBOOT \
    __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_GREETD_DROPIN__/40-fruux-firstboot.conf 0644
  for calendar_unit in labwc-calendar-credentials; do
    desktop_stage_role_asset "etc/skel-desktop/.config/systemd/user/${calendar_unit}.service" "__INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/${calendar_unit}.service" 0644
  done
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_PLANS __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-plans.pl 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_LOGOUT __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-logout 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_FUZZEL_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-fuzzel 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_COMPUTER_MANAGEMENT __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-computer-management 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_NETWORK_SHARING __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-network-sharing 0755
  desktop_stage_role_asset FILE_TARGET_BIN_NFSMNT __INSTALLER_PATH_DIR_USR_LOCAL__/bin/nfsmnt 0755
  desktop_stage_role_asset FILE_TARGET_BIN_FILENMNT __INSTALLER_PATH_DIR_USR_LOCAL__/bin/filenmnt 0755
  desktop_stage_role_asset FILE_TARGET_BIN_NMTUI __INSTALLER_PATH_DIR_USR_LOCAL__/bin/nmtui 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_AI_COPILOTS __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-ai-copilots 0755
  case "$AICOPILOTS_HUGGINGFACE_WEB_BASE_URL:$AICOPILOTS_HUGGINGFACE_API_BASE_URL" in
    https://?*:https://?*) ;;
    *) installer_fatal 'AI copilot model service endpoints must use HTTPS URLs' ;;
  esac
  desktop_render_role_target_template \
    FILE_TARGET_SHARE_LABWC_AI_COPILOTS_ENDPOINTS_TMPL \
    __INSTALLER_PATH_DIR_USR_LOCAL__/share/labwc-ai-copilots/endpoints.json 0644 \
    AICOPILOTS_HUGGINGFACE_WEB_BASE_URL "$AICOPILOTS_HUGGINGFACE_WEB_BASE_URL" \
    AICOPILOTS_HUGGINGFACE_API_BASE_URL "$AICOPILOTS_HUGGINGFACE_API_BASE_URL"
  desktop_stage_ai_copilots_perl_modules
  desktop_stage_ai_copilots_catalogs
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_AI_COPILOTS_ACTION __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-ai-copilots-action 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_AI_LLAMA_SERVER __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-ai-llama-server 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LLAMA_WHISPER_COORDINATE __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/llama-whisper-coordinate 0755
  desktop_stage_role_asset FILE_TARGET_USER_UNIT_LLAMA_WHISPER_GUARD_SERVICE __INSTALLER_PATH_DIR_ETC__/systemd/user/llama-whisper-guard.service 0644
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_AI_MODEL_INSTALL_ROOT __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-ai-model-install-root 0755
  desktop_stage_ai_copilots_python_modules
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_AI_MODEL_INFO __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-ai-model-info 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_DISPLAY_CONFIGURATION __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-display-configuration 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_DIGITAL_ASSETS __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-digital-assets 0755
  desktop_stage_digital_assets_perl_modules
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_DIGITAL_ASSETS_ACTION __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-digital-assets-action 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_USERS_GROUPS_MENU __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-users-groups-menu 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_ADB_MENU __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-adb-menu 0755
  desktop_stage_labwc_adb_perl_modules
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_ADB_ACTION __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-adb-action 0755
  desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_LABWC_ADB_SERVER_SERVICE __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-adb-server.service 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_LLAMA_SERVER_SERVICE __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/llama-server.service 0644
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_SAMSUNG_FIRMWARE_EXTRACT __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-samsung-firmware-extract 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_MAINTENANCE_MENU_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-maintenance-menu 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_SYSTEM_MENU_ACTION __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-system-menu-action 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_PODMAN_MENU __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-podman-menu 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_EXTERNAL_DRIVES_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-external-drives 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_GVFS_VOLUME_MONITOR __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-gvfs-volume-monitor 0755
  desktop_stage_role_asset FILE_TARGET_USER_UNIT_LABWC_GVFS_VOLUME_MONITOR_SERVICE __INSTALLER_PATH_DIR_ETC__/systemd/user/labwc-gvfs-volume-monitor.service 0644
  desktop_stage_role_asset FILE_TARGET_USER_UNIT_THUNAR_SERVICE_D_50_LABWC_SESSION __INSTALLER_PATH_DIR_SYSTEMD_USER_THUNAR_DROPIN__/50-labwc-session.conf 0644
  desktop_stage_role_asset FILE_TARGET_USR_SHARE_DBUS_1_SERVICES_ORG_GTK_VFS_LABWCVOLUMEMONITOR_SERVICE __INSTALLER_PATH_DIR_USR_SHARE__/dbus-1/services/org.gtk.vfs.LabwcVolumeMonitor.service 0644
  desktop_stage_role_asset FILE_TARGET_USR_SHARE_GVFS_REMOTE_VOLUME_MONITORS_LABWC_MONITOR __INSTALLER_PATH_DIR_USR_SHARE__/gvfs/remote-volume-monitors/labwc.monitor 0644
  desktop_stage_labwc_security_action_perl_modules
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_SECURITY_ACTION __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-security-action 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_SYSTEM_ACTION_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-system-action 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_RECOVERY_ACTION_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-recovery-action 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_NETWORK_CONTROL_MENU __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-network-control-menu 0755
  desktop_stage_labwc_network_control_action_perl_modules
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_NETWORK_CONTROL_ACTION __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-network-control-action 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_FIREWALL_MENU __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-firewall-menu 0755
  desktop_stage_labwc_firewall_python_modules
  desktop_stage_compz
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_FIREWALL_ACTION __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-firewall-action 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_NETWORK_SCAN_MENU __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-network-scan-menu 0755
  desktop_stage_labwc_network_scan_action_perl_modules
  desktop_render_labwc_network_scan_action_perl_root_module
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_NETWORK_SCAN_ACTION __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-network-scan-action 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_REMOTE_DESKTOP_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-remote-desktop 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_FREERDP_ASKPASS __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-freerdp-askpass 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_OCR __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-ocr 0755
  desktop_stage_role_asset FILE_TARGET_BIN_DISCORD __INSTALLER_PATH_DIR_USR_LOCAL__/bin/discord 0755
  desktop_stage_role_asset FILE_TARGET_BIN_TELBOT __INSTALLER_PATH_DIR_USR_LOCAL__/bin/telbot 0755
  for tuta_launcher in \
    "${DIR_ETC_SKEL_DESKTOP}/.local/share/applications/tutanota-desktop.desktop" \
    "${DIR_USR_LOCAL_SHARE_APPLICATIONS}/tutanota-desktop.desktop"; do
    desktop_render_role_target_template \
      FILE_TARGET_SKEL_APPS_TUTANOTA_DESKTOP_TMPL "$tuta_launcher" 0644 \
      LABWC_MANAGED_APP_DEFAULT_EXEC "$LABWC_MANAGED_APP_DEFAULT_EXEC"
  done
  desktop_stage_labwc_managed_app_python_modules
  if [ -e "${TARGET_ROOT}${DIR_OPT_VIVALDI}/vivaldi" ]; then
    (
      # The packaged updater's byte-offset pipelines can leave a partial
      # library and delete the previous codec. Read its release selection as
      # data and extract the actual ZIP member in the shared Python setup path.
      installer_operation_context_repo FILE_DESKTOP_VIVALDI_CODECS_INSTALL 1 install_vivaldi_media_codecs
      installer_run_target_setup FILE_DESKTOP_VIVALDI_CODECS_INSTALL \
        'install compatible Vivaldi proprietary media codecs' \
        "$DIR_OPT_VIVALDI" "${DIR_VAR}/opt/vivaldi" "${DIR_USR_BIN}/pidwait"
    )
  fi
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_PROXY_SESSION __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-proxy-session 0755
  desktop_normalize_proxy3_directories
  for proxy3_app in chromium microsoft-edge vivaldi mullvad-browser qbittorrent; do
    render_target_asset_with_placeholder_map \
      "$(installer_repo_asset_path DIR_TARGET_LABWC_3PROXY "${proxy3_app}.conf.tmpl")" \
      "__INSTALLER_PATH_DIR_ETC__/labwc/3proxy/${proxy3_app}.conf" 0644 proxy3_placeholder_map
  done
  render_target_asset_with_placeholder_map \
    "$(installer_repo_file_value FILE_TARGET_LABWC_3PROXY_SESSION_TMPL)" \
    __INSTALLER_PATH_DIR_ETC__/labwc/3proxy/session.json 0644 proxy3_placeholder_map
  for proxy3_family in chromium opt/chrome opt/edge vivaldi; do
    render_target_asset_with_placeholder_map \
      "$(installer_repo_asset_path DIR_TARGET "${proxy3_family}/policies/managed/3proxy.json.tmpl")" \
      "__INSTALLER_PATH_DIR_ETC__/${proxy3_family}/policies/managed/3proxy.json" 0644 proxy3_placeholder_map
  done
  render_target_asset_with_placeholder_map \
    "$(installer_repo_file_value FILE_TARGET_USR_LIB_MULLVAD_BROWSER_DISTRIBUTION_POLICIES_TMPL)" \
    __INSTALLER_PATH_DIR_USR_LIB__/mullvad-browser/distribution/policies.json 0644 proxy3_placeholder_map
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_APP __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-app 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_ELECTRON_APP __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-electron-app 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_WAYLAND_APP __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-wayland-app 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_APP_VETH_RUN __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/app-veth-run 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_WRAP_DESKTOP_FILES __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-wrap-desktop-files 0755
  desktop_stage_role_asset "$(installer_repo_apt_selector APT_CONF_D_71LABWC_DESKTOP_APPS)" __INSTALLER_PATH_DIR_ETC__/apt/apt.conf.d/71labwc-desktop-apps 0644
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_MAIN_MENU_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-main-menu 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_DEBUG_SESSION __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-debug-session 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_WINDOW_SWITCHER __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-window-switcher 0755
  desktop_stage_waybar_theme_icons
  desktop_stage_role_asset FILE_TARGET_UNIT_LABWC_SYSTEM_DESKTOP_OVERRIDES_SERVICE __INSTALLER_PATH_DIR_ETC__/systemd/system/labwc-system-desktop-overrides.service 0644
  desktop_stage_role_asset FILE_TARGET_UNIT_LABWC_SYSTEM_DESKTOP_OVERRIDES_PATH __INSTALLER_PATH_DIR_ETC__/systemd/system/labwc-system-desktop-overrides.path 0644
  desktop_render_role_target_template \
    FILE_TARGET_SKEL_APPS_MICRO_TMPL \
    __INSTALLER_PATH_DIR_ETC__/skel-desktop/.local/share/applications/micro.desktop \
    0644 \
    LABWC_WAYLAND_APP_DEFAULT_EXEC "$LABWC_WAYLAND_APP_DEFAULT_EXEC"
  desktop_render_role_target_template \
    FILE_TARGET_SKEL_APPS_WAYPAPER_TMPL \
    __INSTALLER_PATH_DIR_ETC__/skel-desktop/.local/share/applications/waypaper.desktop \
    0644 \
    LABWC_WAYLAND_APP_DEFAULT_EXEC "$LABWC_WAYLAND_APP_DEFAULT_EXEC"
  desktop_stage_role_asset FILE_TARGET_DPKG_DPKG_CFG_D_95_LABWC_DESKTOP_APPS __INSTALLER_PATH_DIR_ETC__/dpkg/dpkg.cfg.d/95-labwc-desktop-apps 0644
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_CHATGPT_SESSION __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-chatgpt-session 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_WAYLAND_COMPAT_APP __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-wayland-compat-app 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_ZOOM_DISCORD_COMPAT_RUNTIME __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-zoom-discord-compat-runtime 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_PRIVATE_XWAYLAND __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-private-xwayland 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_COMPAT_OPEN_URI __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-compat-open-uri 0755
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
      FILE_TARGET_QBITTORRENT_QBITTORRENT_CONF_D_10_SECURITY_TMPL \
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
      FILE_TARGET_QBITTORRENT_QBITTORRENT_CONF_D_10_SECURITY_TMPL \
      __INSTALLER_PATH_DIR_ETC__/qbittorrent/qBittorrent.conf.d/20-managed-privacy.conf 0644 \
      QBITTORRENT_SAVE_ROOT __INSTALLER_PATH_DIR_HOME__/user/Downloads \
      LABWC_QBITTORRENT_ETHERNET_PORT "$desktop_qbittorrent_ethernet_port" \
      PROXY3_PORT_LISTEN_QBITTORRENT "${PROXY3_PORT_LISTEN_QBITTORRENT:-3128}" \
      APP_VETH_NAMESPACE_INTERFACE "$APP_VETH_NAMESPACE_INTERFACE" \
      APP_VETH_QBITTORRENT_ADDRESS ""
  fi
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_QBITTORRENT __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-qbittorrent 0755
  desktop_stage_role_asset FILE_TARGET_BIN_ZOOM __INSTALLER_PATH_DIR_USR_LOCAL__/bin/zoom 0755
  desktop_render_role_target_template \
    FILE_TARGET_BIN_LABWC_SYNC_APPLICATION_LAUNCHERS_TMPL \
    __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-sync-application-launchers \
    0755 \
    LABWC_MANAGED_APP_DEFAULT_EXEC "$LABWC_MANAGED_APP_DEFAULT_EXEC"
  desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_LABWC_SYNC_APPLICATION_LAUNCHERS_SERVICE __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-sync-application-launchers.service 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_LABWC_SYNC_APPLICATION_LAUNCHERS_PATH __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-sync-application-launchers.path 0644
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_GREETER_OUTPUT __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-greeter-output 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_GREETER_POWER __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-greeter-power 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_GREETER_CLIENT __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-greeter-client 0755
  desktop_stage_role_asset FILE_TARGET_SHARE_LABWC_GREETER_RC __INSTALLER_PATH_DIR_USR_LOCAL__/share/labwc-greeter/rc.xml 0644
  desktop_stage_role_asset FILE_TARGET_SHARE_LABWC_GREETER_AUTOSTART __INSTALLER_PATH_DIR_USR_LOCAL__/share/labwc-greeter/autostart 0644
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_OUTPUT_WATCH __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-output-watch 0755
  if desktop_kanshi_enabled; then
    desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_KANSHI __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-kanshi 0755
  fi
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_SESSION_CHECK __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-session-check 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_PRIMARY_GPG __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-primary-gpg 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_WAYBAR_EXEC __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-waybar-exec 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_WAYBAR_MENU __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-waybar-menu 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_WAYBAR_RUN __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-waybar-run 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_WAYBAR_STATE __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-waybar-state 0755
  desktop_stage_role_asset FILE_TARGET_PY_LABWC_WAYBAR_STATE "${DIR_PYTHON3_SITE_PACKAGES}/labwc_waybar_state.py" 0644
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_WAYBAR_BATTERY __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-waybar-battery 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_WAYBAR_EVENTS_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-waybar-events 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_PANEL_RUN __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-panel-run 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_WHISPER_RECORD_TIMED __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/whisper-record-timed 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_SWAYBG_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-swaybg 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_SWAYIDLE __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-swayidle 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_MUTE_DEFAULT_MICROPHONE __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-mute-default-microphone 0755
  desktop_stage_role_asset FILE_TARGET_PERL_WHISPER_WHISPERMODE_AUDIO "${DIR_PERL5_SITE_PERL}/whisper/WhisperMode/Audio.pm" 0644
  desktop_stage_role_asset FILE_TARGET_PERL_WHISPER_WHISPERMODE_STATE "${DIR_PERL5_SITE_PERL}/whisper/WhisperMode/State.pm" 0644
  desktop_stage_role_asset FILE_TARGET_PERL_WHISPER_WHISPERMODE_SYSTEMD "${DIR_PERL5_SITE_PERL}/whisper/WhisperMode/Systemd.pm" 0644
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_LOCK_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-lock 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_SWAYLOCK_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-swaylock 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_IDLE_TOGGLE __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-idle-toggle 0755
  desktop_stage_role_asset FILE_TARGET_USER_UNIT_LABWC_LOCK_SERVICE __INSTALLER_PATH_DIR_ETC__/systemd/user/labwc-lock.service 0644
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_TERMINAL __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-terminal 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_TERMINAL_RESULT __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-terminal-result 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_BLUETOOTH_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-bluetooth 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_BRIGHTNESS_CONTROL_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-brightness-control 0755
  desktop_stage_role_asset FILE_TARGET_UDEV_RULES_D_81_LABWC_THINKPAD_BACKLIGHT __INSTALLER_PATH_DIR_ETC__/udev/rules.d/81-labwc-thinkpad-backlight.rules 0644
  case "${SYSTEM_HARDWARE_SPEC:-}" in
    79-thinkpad-acpi.conf)
      desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_THINKPAD_HOTKEYS __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-thinkpad-hotkeys 0755
      desktop_stage_role_asset FILE_TARGET_UNIT_LABWC_THINKPAD_HOTKEYS_SERVICE __INSTALLER_PATH_DIR_ETC__/systemd/system/labwc-thinkpad-hotkeys.service 0644
      remove_target_asset __INSTALLER_PATH_DIR_ETC__/udev/rules.d/82-labwc-ideapad-flex-backlight.rules
      remove_target_asset __INSTALLER_PATH_DIR_ETC__/systemd/system/multi-user.target.wants/labwc-thinkpad-hotkeys.service
      run_in_target "enable supported ThinkPad brightness events" __INSTALLER_PATH_DIR_USR_BIN__/systemctl enable labwc-thinkpad-hotkeys.service
      ;;
    79-ideapad-acpi.conf)
      desktop_stage_role_asset \
        FILE_TARGET_UDEV_RULES_D_82_LABWC_IDEAPAD_FLEX_BACKLIGHT \
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
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_POWER_SETTINGS __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-power-settings 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_RUN __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-run 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_POWER_MENU __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-power-menu 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_KEYBOARD_LAYOUT_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-keyboard-layout 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_CAPTURE_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-capture 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_WAYSCRIBER_TOGGLE __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-wayscriber-toggle 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_WAYSCRIBER_CONFIG __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-wayscriber-config 0755
  desktop_stage_role_asset FILE_TARGET_BIN_SATTY __INSTALLER_PATH_DIR_USR_LOCAL__/bin/satty 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_APPARMOR_GENERATE_RULES __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/apparmor-generate-rules 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_SECURITY_ACTION_ROOT __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-security-action-root 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_APPARMOR_POLICY_WORKER __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-apparmor-policy-worker 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_APPARMOR_BOOT_STATE __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-apparmor-boot-state 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_SYSTEM_ACTION_ROOT __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-system-action-root 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_STORAGE_REPORT __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-storage-report 0755
  # Inspect code and command metadata as data before desktop service enablement.
  # Never invoke the report or query a filesystem while staging the installer.
  run_in_target "verify staged storage report contract" __INSTALLER_PATH_DIR_USR_BIN__/python3 -I -S -B -c '
import re
import stat
from pathlib import Path

report = Path("__INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-storage-report")
for path in (report, Path("__INSTALLER_PATH_DIR_USR_BIN__/df"), Path("__INSTALLER_PATH_DIR_USR_BIN__/findmnt"),
             Path("__INSTALLER_PATH_DIR_USR_BIN__/lsblk"), Path("__INSTALLER_PATH_DIR_USR_BIN__/timeout")):
    for parent in reversed(path.parents):
        meta = parent.lstat()
        if not stat.S_ISDIR(meta.st_mode) or meta.st_uid != 0 or meta.st_mode & 0o022:
            raise SystemExit("fatal: untrusted storage command parent: " + str(parent))
    meta = path.lstat()
    if (not stat.S_ISREG(meta.st_mode) or meta.st_uid != 0 or meta.st_gid != 0
            or meta.st_mode & 0o022 or not meta.st_mode & 0o111):
        raise SystemExit("fatal: unsafe or unavailable storage command: " + str(path))
    if path == report and (meta.st_nlink != 1 or stat.S_IMODE(meta.st_mode) != 0o755
                           or not 0 < meta.st_size <= 16384):
        raise SystemExit("fatal: invalid storage report metadata")
with report.open("rb") as stream:
    source = stream.read(16385)
if len(source) > 16384 or re.search(rb"__[A-Z][A-Z0-9_]{2,}__", source):
    raise SystemExit("fatal: oversized or unresolved storage report")
'
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_RECOVERY_ACTION_ROOT __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-recovery-action-root 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_NETWORK_CONTROL_ACTION_ROOT __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-network-control-action-root 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_FIREWALL_ACTION_ROOT __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-firewall-action-root 0755
  desktop_render_role_target_template \
    FILE_TARGET_LIBEXEC_LABWC_NETWORK_SCAN_ACTION_ROOT_TMPL \
    __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-network-scan-action-root \
    0755 \
    ACCOUNT_USERNAME "$ACCOUNT_USERNAME"
  desktop_stage_managed_nmap_scripts
  desktop_stage_role_asset FILE_TARGET_SBIN_GREETD_POWER_ACTION __INSTALLER_PATH_DIR_USR_LOCAL__/sbin/greetd-power-action 0755
  desktop_stage_role_asset FILE_TARGET_SBIN_LABWC_NOTIFY_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/sbin/labwc-notify 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_CLAMAV_SIGNATURE_UPDATE __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/clamav-signature-update 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_CLAMAV_FANGFRISCH __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/clamav-fangfrisch 0755

  desktop_stage_role_asset FILE_TARGET_USR_SHARE_WAYLAND_SESSIONS_LABWC __INSTALLER_PATH_DIR_USR_SHARE__/wayland-sessions/labwc.desktop 0644
  desktop_stage_role_asset FILE_TARGET_APPS_COMPUTER_MANAGEMENT_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/computer-management.desktop 0644
  desktop_stage_role_asset FILE_TARGET_APPS_REMOTE_DESKTOP_MANAGEMENT_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/remote-desktop-management.desktop 0644
  desktop_stage_role_asset FILE_TARGET_APPS_FOOT_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/foot.desktop 0644
  desktop_render_role_target_template FILE_TARGET_APPS_CODE_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/code.desktop 0644
  desktop_render_role_target_template FILE_TARGET_APPS_ORG_LABWC_DESKTOPAPPEARANCE_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/org.labwc.DesktopAppearance.desktop 0644
  desktop_stage_role_asset FILE_TARGET_APPS_LABWC_NOTIFICATIONS_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/labwc-notifications.desktop 0644
  desktop_render_gtkgreet_css
  desktop_stage_role_asset FILE_TARGET_GREETD_GTKGREET_POWER_CSS_TMPL __INSTALLER_PATH_DIR_ETC__/greetd/gtkgreet-power.css 0644
  desktop_render_greeter_power_rule
  desktop_stage_fangfrisch
  desktop_stage_role_asset FILE_TARGET_CRON_D_DEBSECAN __INSTALLER_PATH_DIR_ETC__/cron.d/debsecan 0644
  desktop_stage_role_asset FILE_TARGET_UNIT_CLAMAV_SIGNATURE_UPDATE_SERVICE_TMPL __INSTALLER_PATH_DIR_ETC__/systemd/system/clamav-signature-update.service 0644
  desktop_stage_role_asset FILE_TARGET_UNIT_CLAMAV_SIGNATURE_UPDATE_SERVICE_D_60_RESOURCE_CLASS __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_CLAMAV_SIGNATURE_UPDATE_DROPIN__/60-resource-class.conf 0644
  desktop_stage_role_asset FILE_TARGET_UNIT_CLAMAV_SIGNATURE_UPDATE_TIMER __INSTALLER_PATH_DIR_ETC__/systemd/system/clamav-signature-update.timer 0644
  desktop_stage_role_asset FILE_TARGET_BLUETOOTH_MAIN __INSTALLER_PATH_DIR_ETC__/bluetooth/main.conf 0644
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_BLUETOOTH_CONTROLLER_INIT __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/bluetooth-controller-init 0755
  desktop_stage_role_asset FILE_TARGET_UNIT_BLUETOOTH_CONTROLLER_INIT_SERVICE __INSTALLER_PATH_DIR_ETC__/systemd/system/bluetooth-controller-init.service 0644
  desktop_stage_role_asset FILE_TARGET_UNIT_GREETD_SERVICE_D_20_LABWC_VT __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_GREETD_DROPIN__/20-labwc-vt.conf 0644
  desktop_stage_role_asset FILE_TARGET_UNIT_BLUETOOTH_SERVICE_D_OVERRIDE __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_BLUETOOTH_DROPIN__/override.conf 0644
  desktop_stage_mullvad_dns_policy
  install -d -m 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/autostart
  desktop_stage_mullvad_application_policy
  if [ "${LABWC_NVIDIA_ACCELERATION_AVAILABLE:-false}" = true ]; then
    desktop_stage_role_asset FILE_TARGET_UNIT_NVIDIA_POWERD_SERVICE_D_10_DEVICE_GUARD __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_NVIDIA_POWERD_DROPIN__/10-device-guard.conf 0644
    desktop_stage_role_asset FILE_TARGET_UDEV_RULES_D_71_NVIDIA_CHAR_LINKS __INSTALLER_PATH_DIR_ETC__/udev/rules.d/71-nvidia-char-links.rules 0644
    desktop_stage_role_asset FILE_TARGET_LIBEXEC_NVIDIA_CHAR_LINKS __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/nvidia-char-links 0755
    desktop_stage_role_asset FILE_TARGET_UNIT_NVIDIA_CHAR_LINKS_SERVICE __INSTALLER_PATH_DIR_ETC__/systemd/system/nvidia-char-links.service 0644
  else
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
  desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_LABWC_KWALLET_PORTAL_SERVICE __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-kwallet-portal.service 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_LABWC_KWALLET_PORTAL_SERVICE "${DIR_USR_LOCAL_SHARE}/labwc-app/defaults/labwc-kwallet-portal.service" 0644
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_HYPRPOLKIT_AGENT __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-hyprpolkit-agent 0755 || return 1
  desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_LABWC_OUTPUT_WATCH_SERVICE __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-output-watch.service 0644
  # The DevOps class helper renders and publishes the Codex units, environment
  # policy, and readiness helper before the desktop role runs. Do not copy the
  # source templates here: their installer placeholders must never reach the
  # target skeleton or overwrite the rendered class-owned files.
  desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_SWAYBG_SERVICE __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/swaybg.service 0644
  if desktop_kanshi_enabled; then
    desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_KANSHI_SERVICE __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/kanshi.service 0644
  fi
  desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_SWAYIDLE_SERVICE __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/swayidle.service 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_CRYSTAL_DOCK_SERVICE __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/crystal-dock.service 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_LABWC_MUTE_DEFAULT_MICROPHONE_SERVICE __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-mute-default-microphone.service 0644
  if desktop_whisper_class_selected; then
    desktop_stage_role_asset FILE_TARGET_TMPFILES_D_55_WHISPER_RUNTIME __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/55-whisper-runtime.conf 0644
    desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_WHISPER_RECORD_SERVICE __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/whisper-record.service 0644
    desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_WHISPER_TRANSCRIBE_SERVICE __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/whisper-transcribe.service 0644
    if desktop_whisper_persistent_memory_enabled; then
      desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_WHISPER_SERVER_SERVICE __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/whisper-server.service 0644
    fi
  fi
  # systemd dependency directives cannot be removed from a vendor unit with a
  # drop-in. Install the complete managed unit so no graphical-session.target
  # dependency survives Debian's Waybar unit. Labwc autostart requests it only
  # after activating the compositor session target, so LABWC_ENABLE_WAYBAR
  # remains the authoritative policy gate.
  desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_WAYBAR_SERVICE __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/waybar.service 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_WAYBAR_SERVICE_D_20_TRAY_COMPAT __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/waybar.service.d/20-tray-compat.conf 0644
  # The package defaults to a global preload. Scope decoration conversion to
  # Agenda through its managed profile instead of changing the whole session.
  desktop_stage_role_asset FILE_TARGET_ENVIRONMENT_D_50_GTK_NOCSD __INSTALLER_PATH_DIR_ETC__/environment.d/50-gtk-nocsd.conf 0644
  if [ -x ${TARGET_ROOT}${DIR_OPT}/microsoft/msedge/msedge ]; then
    install -d -m 0755 ${TARGET_ROOT}${DIR_OPT}/microsoft/msedge/extensions
  fi
  desktop_stage_role_asset FILE_TARGET_WIREPLUMBER_WIREPLUMBER_CONF_D_10_DISABLE_BLUEZ_MIDI __INSTALLER_PATH_DIR_ETC__/wireplumber/wireplumber.conf.d/10-disable-bluez-midi.conf 0644
  desktop_stage_role_asset FILE_TARGET_WIREPLUMBER_WIREPLUMBER_CONF_D_20_AUDIO_POLICY __INSTALLER_PATH_DIR_ETC__/wireplumber/wireplumber.conf.d/20-audio-policy.conf 0644
  desktop_stage_role_asset FILE_TARGET_PIPEWIRE_CLIENT_CONF_D_20_VOLUME_CEILING __INSTALLER_PATH_DIR_ETC__/pipewire/client.conf.d/20-volume-ceiling.conf 0644
  desktop_stage_role_asset FILE_TARGET_PIPEWIRE_PIPEWIRE_PULSE_CONF_D_20_VOLUME_CEILING __INSTALLER_PATH_DIR_ETC__/pipewire/pipewire-pulse.conf.d/20-volume-ceiling.conf 0644
  desktop_stage_role_asset "$(installer_repo_apt_selector LISTCHANGES)" __INSTALLER_PATH_DIR_ETC__/apt/listchanges.conf 0644
  desktop_stage_role_asset "$(installer_repo_apt_selector APT_CONF_D_60DESKTOP_LOCAL_MAIL)" __INSTALLER_PATH_DIR_ETC__/apt/apt.conf.d/60desktop-local-mail.conf 0644
  desktop_stage_role_asset FILE_TARGET_CHROMIUM_POLICIES_MANAGED_TELEMETRY __INSTALLER_PATH_DIR_ETC__/chromium/policies/managed/telemetry.json 0644
  desktop_stage_role_asset FILE_TARGET_CHROMIUM_POLICIES_MANAGED_SECURITY __INSTALLER_PATH_DIR_ETC__/chromium/policies/managed/security.json 0644
  desktop_stage_role_asset FILE_TARGET_CHROMIUM_POLICIES_MANAGED_EXTENSIONS __INSTALLER_PATH_DIR_ETC__/chromium/policies/managed/extensions.json 0644
  desktop_stage_role_asset FILE_TARGET_CHROMIUM_POLICIES_MANAGED_PERFORMANCE __INSTALLER_PATH_DIR_ETC__/chromium/policies/managed/performance.json 0644
  desktop_stage_role_asset FILE_TARGET_CHROMIUM_POLICIES_RECOMMENDED_DEFAULTS __INSTALLER_PATH_DIR_ETC__/chromium/policies/recommended/defaults.json 0644
  desktop_stage_role_asset FILE_TARGET_ETC_OPT_EDGE_POLICIES_MANAGED_TELEMETRY __INSTALLER_PATH_DIR_ETC__/opt/edge/policies/managed/telemetry.json 0644
  desktop_stage_role_asset FILE_TARGET_ETC_OPT_EDGE_POLICIES_MANAGED_SECURITY __INSTALLER_PATH_DIR_ETC__/opt/edge/policies/managed/security.json 0644
  desktop_stage_role_asset FILE_TARGET_ETC_OPT_EDGE_POLICIES_MANAGED_EXTENSIONS __INSTALLER_PATH_DIR_ETC__/opt/edge/policies/managed/extensions.json 0644
  desktop_stage_role_asset FILE_TARGET_ETC_OPT_EDGE_POLICIES_MANAGED_PERFORMANCE __INSTALLER_PATH_DIR_ETC__/opt/edge/policies/managed/performance.json 0644
  desktop_stage_role_asset FILE_TARGET_ETC_OPT_EDGE_POLICIES_RECOMMENDED_DEFAULTS __INSTALLER_PATH_DIR_ETC__/opt/edge/policies/recommended/defaults.json 0644
  desktop_stage_role_asset FILE_TARGET_VIVALDI_POLICIES_MANAGED_TELEMETRY __INSTALLER_PATH_DIR_ETC__/vivaldi/policies/managed/telemetry.json 0644
  desktop_stage_role_asset FILE_TARGET_VIVALDI_POLICIES_MANAGED_EXTENSIONS __INSTALLER_PATH_DIR_ETC__/vivaldi/policies/managed/extensions.json 0644
  desktop_stage_role_asset FILE_TARGET_VIVALDI_POLICIES_MANAGED_SECURITY __INSTALLER_PATH_DIR_ETC__/vivaldi/policies/managed/security.json 0644
  desktop_stage_role_asset FILE_TARGET_VIVALDI_POLICIES_MANAGED_PERFORMANCE __INSTALLER_PATH_DIR_ETC__/vivaldi/policies/managed/performance.json 0644
  desktop_stage_role_asset FILE_TARGET_VIVALDI_POLICIES_RECOMMENDED_DEFAULTS __INSTALLER_PATH_DIR_ETC__/vivaldi/policies/recommended/defaults.json 0644
  desktop_stage_role_asset FILE_TARGET_VIVALDI_SEARCH_ENGINES_SEARCH_ENGINES_JSON_SIGNED __INSTALLER_PATH_DIR_ETC__/vivaldi/search-engines/search_engines.json.signed 0644
  desktop_stage_role_asset FILE_TARGET_VIVALDI_SEARCH_ENGINES_SEARCH_ENGINES_PROMPT_JSON_SIGNED __INSTALLER_PATH_DIR_ETC__/vivaldi/search-engines/search_engines_prompt.json.signed 0644
  desktop_stage_role_asset FILE_TARGET_ETC_OPT_CHROME_POLICIES_MANAGED_SECURITY __INSTALLER_PATH_DIR_ETC__/opt/chrome/policies/managed/security.json 0644
  desktop_stage_role_asset FILE_TARGET_ETC_OPT_CHROME_POLICIES_MANAGED_EXTENSIONS __INSTALLER_PATH_DIR_ETC__/opt/chrome/policies/managed/extensions.json 0644
  desktop_stage_role_asset FILE_TARGET_ETC_OPT_CHROME_POLICIES_MANAGED_TELEMETRY __INSTALLER_PATH_DIR_ETC__/opt/chrome/policies/managed/telemetry.json 0644
  desktop_stage_role_asset FILE_TARGET_ETC_OPT_CHROME_POLICIES_MANAGED_PERFORMANCE __INSTALLER_PATH_DIR_ETC__/opt/chrome/policies/managed/performance.json 0644
  desktop_stage_role_asset FILE_TARGET_ETC_OPT_CHROME_POLICIES_RECOMMENDED_DEFAULTS __INSTALLER_PATH_DIR_ETC__/opt/chrome/policies/recommended/defaults.json 0644
  desktop_stage_role_asset FILE_TARGET_BIN_BROWSER_DEVTOOLS __INSTALLER_PATH_DIR_USR_LOCAL__/bin/browser-devtools 0755
  desktop_stage_role_asset \
    FILE_TARGET_USR_SHARE_GLIB_2_0_SCHEMAS_90_DESKTOP_WSDD_GSCHEMA_OVERRIDE \
    __INSTALLER_PATH_DIR_USR_SHARE__/glib-2.0/schemas/90-desktop-wsdd.gschema.override \
    0644
  desktop_stage_role_asset FILE_TARGET_XDG_XDG_DESKTOP_PORTAL_LABWC_PORTALS __INSTALLER_PATH_DIR_ETC__/xdg/xdg-desktop-portal/labwc-portals.conf 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_GNUPG_GPG_AGENT __INSTALLER_PATH_DIR_ETC__/skel-desktop/.gnupg/gpg-agent.conf 0600
  chmod 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.gnupg
  desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_OBSIDIAN_GIT_SYNC_TIMER __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/obsidian-git-sync.timer 0644
  desktop_render_role_target_template \
    FILE_TARGET_OBSIDIAN_GIT_SYNC_TMPL __INSTALLER_PATH_DIR_ETC__/obsidian-git-sync.conf 0644 \
    OBSIDIAN_GIT_AUTO_ENABLE "$OBSIDIAN_GIT_AUTO_ENABLE" \
    OBSIDIAN_GIT_REPOSITORY_URL "$OBSIDIAN_GIT_REPOSITORY_URL" \
    OBSIDIAN_GIT_REPOSITORY_BRANCH "$OBSIDIAN_GIT_REPOSITORY_BRANCH" \
    OBSIDIAN_GIT_DIRECTORY "$OBSIDIAN_GIT_DIRECTORY"
  desktop_render_role_target_template \
    FILE_TARGET_SKEL_USER_UNIT_OBSIDIAN_GIT_SYNC_SERVICE \
    __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/obsidian-git-sync.service \
    0644 \
    OBSIDIAN_GIT_DIRECTORY "$OBSIDIAN_GIT_DIRECTORY"
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_OBSIDIAN_GIT_SYNC_FILE __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/obsidian-git-sync 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_OBSIDIAN_GIT_SYNC_PY __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/obsidian-git-sync.py 0755

  desktop_extract_role_wallpaper_archive
  # Publish explicit defaults after archive extraction, so an archive member
  # cannot overwrite a differently named user-selected default.
  desktop_stage_role_asset "${LABWC_WALLPAPER_DESKTOP_SWAYBG#"${DIR_HOOKS_TARGET}"/}" "$LABWC_WALLPAPER_PATH" 0644
  desktop_stage_role_asset "${LABWC_WALLPAPER_LOCKSCREEN_SWAYLOCK#"${DIR_HOOKS_TARGET}"/}" "$LABWC_LOCK_BACKGROUND_PATH" 0644
  desktop_stage_role_asset "${LABWC_WALLPAPER_LOGIN_GTKGREET#"${DIR_HOOKS_TARGET}"/}" "$LABWC_GREETER_BACKGROUND_PATH" 0644
  desktop_normalize_background_directories
#  desktop_stage_role_asset_tree usr/share/backgrounds/other __INSTALLER_PATH_DIR_USR_SHARE__/backgrounds/other

  desktop_stage_role_asset FILE_TARGET_SKEL_LABWC_AUTOSTART __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/labwc/autostart 0755
  desktop_stage_role_asset FILE_TARGET_SKEL_LABWC_SHUTDOWN __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/labwc/shutdown 0755
  desktop_stage_labwc_user_session_assets
  remove_target_asset __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/labwc/xinitrc
  remove_target_asset __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/gsimplecal/config
  desktop_stage_role_asset FILE_TARGET_SKEL_LABWC_THEMERC_OVERRIDE_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/labwc/themerc-override 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_WAYPAPER_CONFIG_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/waypaper/config.ini 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_WAYPAPER_KEYBINDINGS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/waypaper/keybindings.ini 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_WAYPAPER_STYLE_CSS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/waypaper/style.css 0644
  desktop_render_labwc_rc_xml
  desktop_render_role_target_template \
    FILE_TARGET_SKEL_LABWC_MENU_TMPL \
    "__INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/labwc/menu.xml" \
    0644 \
    ACCOUNT_HOME "$ACCOUNT_HOME"
  desktop_render_waybar_config
  desktop_render_waybar_style
  desktop_render_kanshi_config
  desktop_render_terminal_configs
  desktop_stage_role_asset FILE_TARGET_SKEL_MPV_MPV_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/mpv/mpv.conf 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_MPV_INPUT __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/mpv/input.conf 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_L3AFPAD_L3AFPADRC __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/l3afpad/l3afpadrc 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_GOTTCODE_FOCUSWRITER_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/GottCode/FocusWriter.conf 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_ZATHURA_ZATHURARC_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/zathura/zathurarc 0644
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_FOCUSWRITER_IMPORT __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-focuswriter-import 0755
  desktop_stage_role_asset FILE_TARGET_APPS_LABWC_FOCUSWRITER_IMPORT_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/labwc-focuswriter-import.desktop 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_LOCAL_SHARE_GOTTCODE_FOCUSWRITER_THEMES_WORD_THEME_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.local/share/GottCode/FocusWriter/Themes/word.theme 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_RECOLL_ORG_RECOLL_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/Recoll.org/recoll.ini 0600
  chmod 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/Recoll.org
  desktop_stage_role_asset FILE_TARGET_SKEL_RECOLL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.recoll/recoll.conf 0644
  chmod 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.recoll
  install -d -m 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.cache ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.cache/recoll
  desktop_stage_role_asset FILE_TARGET_SKEL_KDIFF3RC __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/kdiff3rc 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_MICRO_SETTINGS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/micro/settings.json 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_NANO_NANORC __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/nano/nanorc 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_NVIM_INIT_LUA_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/nvim/init.lua 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_QALCULATE_QALC __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/qalculate/qalc.cfg 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_QALCULATE_QALCULATE_QT __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/qalculate/qalculate-qt.cfg 0644
  install -d -m 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/lxqt
  desktop_stage_role_asset FILE_TARGET_SKEL_LXQT_FILEDIALOG __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/lxqt/filedialog.conf 0644
  install -d -m 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/xarchiver
  desktop_render_role_target_template \
    FILE_TARGET_SKEL_XARCHIVER_XARCHIVERRC_TMPL \
    __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/xarchiver/xarchiverrc \
    0600 \
    ACCOUNT_USERNAME "$ACCOUNT_USERNAME" \
    DIR_HOME_DOWNLOADS "$DIR_HOME_DOWNLOADS"
  desktop_stage_role_asset FILE_TARGET_SKEL_TASK_TASKRC_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/task/taskrc 0644
  install -d -m 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.local/share/task ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.local/share/task/hooks
  desktop_stage_role_asset FILE_TARGET_SKEL_VIM_VIMRC __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/vim/vimrc 0644
  desktop_render_note_app_defaults
  desktop_compile_glib_schemas
  desktop_stage_role_asset FILE_TARGET_SKEL_XDG_TERMINALS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/xdg-terminals.list 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_MIMEAPPS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/mimeapps.list 0600
  desktop_stage_role_asset FILE_TARGET_XDG_MIMEAPPS __INSTALLER_PATH_DIR_ETC__/xdg/mimeapps.list 0644
  desktop_stage_role_asset FILE_TARGET_USR_SHARE_MIME_PACKAGES_90_DESKTOP_FILETYPES __INSTALLER_PATH_DIR_USR_SHARE__/mime/packages/90-desktop-filetypes.xml 0644
  run_in_target "update managed desktop MIME database" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
test -x __INSTALLER_PATH_DIR_USR_BIN__/update-mime-database
__INSTALLER_PATH_DIR_USR_BIN__/update-mime-database __INSTALLER_PATH_DIR_USR_SHARE__/mime
' sh
  desktop_stage_role_asset FILE_TARGET_SKEL_XFCE4_HELPERS_RC __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/xfce4/helpers.rc 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_XFCE4_XFCONF_XFCE_PERCHANNEL_XML_THUNAR __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_RETROARCH __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/retroarch/retroarch.cfg 0644
  install -d -m 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/sleek/userData
  desktop_stage_role_asset FILE_TARGET_SKEL_SLEEK_USERDATA_COLORS_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/sleek/userData/colors.json 0600
  desktop_render_role_target_template \
    FILE_TARGET_SKEL_SLEEK_USERDATA_CONFIG_TMPL \
    "__INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/sleek/userData/config.json" \
    0600 \
    ACCOUNT_HOME "$ACCOUNT_HOME"
  desktop_stage_role_asset FILE_TARGET_SKEL_SLEEK_USERDATA_FILTERS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/sleek/userData/filters.json 0600
  desktop_stage_role_asset FILE_TARGET_USR_SHARE_XFCE4_HELPERS_FOOT_TMPL __INSTALLER_PATH_DIR_USR_SHARE__/xfce4/helpers/foot.desktop 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_FONTCONFIG_CONF_D_60_LABWC_TERMINAL_FONTS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/fontconfig/conf.d/60-labwc-terminal-fonts.conf 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_FONTCONFIG_CONF_D_61_MICROSOFT_FONTS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/fontconfig/conf.d/61-microsoft-fonts.conf 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_PROFILE __INSTALLER_PATH_DIR_ETC__/skel-desktop/.profile 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_BASH_PROFILE __INSTALLER_PATH_DIR_ETC__/skel-desktop/.bash_profile 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_BASHRC __INSTALLER_PATH_DIR_ETC__/skel-desktop/.bashrc 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_BASH_ALIASES __INSTALLER_PATH_DIR_ETC__/skel-desktop/.bash_aliases 0644
  install -d -m 0755 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.profile.d
  if installer_tools_class_selected; then
  desktop_render_role_target_template \
    FILE_TARGET_SKEL_PROFILE_71_DEVOPS_DE "${DIR_ETC_SKEL_DESKTOP}/.profile.d/71-devops-de.sh" 0644 \
    HARDWARE_CPU_SCHEDULER_SCX_WORKER_PERFORMANCE "$HARDWARE_CPU_SCHEDULER_SCX_WORKER_PERFORMANCE"
  install -d -m 0755 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/cargo
  desktop_render_cargo_config
  install -d -m 0755 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/mise/conf.d
  desktop_stage_role_asset FILE_TARGET_SKEL_MISE_CONFIG __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/mise/config.toml 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_MISE_CONFIG_DEVELOPMENT __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/mise/config.development.toml 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_MISE_CONFIG_LOCAL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/mise/config.local.toml 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_MISE_CONFIG_DEVELOPMENT_LOCAL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/mise/config.development.local.toml 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_MISE_CONF_D_10_TOOLS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/mise/conf.d/10-tools.toml 0644
  fi
  desktop_stage_role_asset FILE_TARGET_SKEL_ZSHENV __INSTALLER_PATH_DIR_ETC__/skel-desktop/.zshenv 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_ZPROFILE __INSTALLER_PATH_DIR_ETC__/skel-desktop/.zprofile 0644
  desktop_stage_role_asset FILE_TARGET_BIN_LABMGMT __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labmgmt 0755
  desktop_stage_role_asset FILE_TARGET_BIN_GITOPS __INSTALLER_PATH_DIR_USR_LOCAL__/bin/gitops 0755
  desktop_stage_role_asset FILE_TARGET_SHARE_DOC_GIT_README_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/share/doc/git/README.md 0644
  desktop_stage_role_asset FILE_TARGET_GITOPS_ALIASES_GITCONFIG __INSTALLER_PATH_DIR_ETC__/gitops/aliases.gitconfig 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_GITOPS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/gitops/gitops.env 0600
  desktop_stage_role_asset FILE_TARGET_SKEL_GIT_CONFIG __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/git/config 0644
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_SSH_CHECKS __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/ssh-checks 0644
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_SSH_KEY_LOAD __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-ssh-key-load 0755
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_SSH_GPG_ASKPASS __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/labwc-ssh-gpg-askpass 0755
  desktop_stage_role_asset FILE_TARGET_BIN_GIT_SSH __INSTALLER_PATH_DIR_USR_LOCAL__/bin/git-ssh 0755
  desktop_stage_role_asset FILE_TARGET_SKEL_USER_UNIT_LABWC_SSH_KEY_LOAD_SERVICE __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/systemd/user/labwc-ssh-key-load.service 0644
  desktop_stage_role_asset FILE_TARGET_USER_UNIT_SSH_AGENT_SOCKET_D_10_LABWC_SESSION __INSTALLER_PATH_DIR_SYSTEMD_USER_SSH_AGENT_SOCKET_DROPIN__/10-labwc-session.conf 0644
  desktop_stage_role_asset FILE_TARGET_USER_UNIT_SSH_AGENT_SERVICE_D_10_LABWC_SESSION __INSTALLER_PATH_DIR_SYSTEMD_USER_SSH_AGENT_DROPIN__/10-labwc-session.conf 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_ZSHRC_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.zshrc 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_ZLOGOUT __INSTALLER_PATH_DIR_ETC__/skel-desktop/.zlogout 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_ZSH_ALIASES __INSTALLER_PATH_DIR_ETC__/skel-desktop/.zsh_aliases 0644
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_SKEL_DIRCOLORS)" __INSTALLER_PATH_DIR_ETC__/skel-desktop/.dircolors 0644
  desktop_log "staged_asset source=$(installer_repo_file_value FILE_TARGET_SKEL_DIRCOLORS) target=__INSTALLER_PATH_DIR_ETC__/skel-desktop/.dircolors mode=0644"
  desktop_stage_role_asset FILE_TARGET_SKEL_STARSHIP_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/starship.toml 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_BTOP_BTOP_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/btop/btop.conf 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_BTOP_BTOP_CPU_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/btop/btop-cpu.conf 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_BTOP_BTOP_MEMORY_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/btop/btop-memory.conf 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_FZF_DEFAULT_OPTS_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/fzf/default-opts 0644
  desktop_render_fuzzel_configs
  desktop_stage_role_asset FILE_TARGET_SKEL_THUNAR_UCA __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/Thunar/uca.xml 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_TESSERACT_OCR_DEFAULTS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/tesseract/ocr-defaults.conf 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_TESSERACT_USER_WORDS_DEFAULT_USER_WORDS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/tesseract/user-words/default.user-words 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_TESSERACT_USER_WORDS_ENG_USER_WORDS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/tesseract/user-words/eng.user-words 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_TESSERACT_USER_WORDS_SWE_USER_WORDS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/tesseract/user-words/swe.user-words 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_TESSERACT_USER_PATTERNS_DEFAULT_USER_PATTERNS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/tesseract/user-patterns/default.user-patterns 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_TESSERACT_USER_PATTERNS_ENG_USER_PATTERNS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/tesseract/user-patterns/eng.user-patterns 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_TESSERACT_USER_PATTERNS_SWE_USER_PATTERNS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/tesseract/user-patterns/swe.user-patterns 0644
  desktop_render_crystal_dock_appearance
  desktop_stage_role_asset FILE_TARGET_SKEL_CRYSTAL_DOCK_LABWC_PANEL_1 __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/crystal-dock/labwc/panel_1.conf 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_CRYSTAL_DOCK_LABWC_PANEL_1 __INSTALLER_PATH_DIR_ETC__/xdg/crystal-dock/labwc/panel_1.conf 0644
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_SHOW_DESKTOP __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-show-desktop 0755
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_HEALTH_NOTIFY_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-health-notify 0755
  desktop_stage_role_asset FILE_TARGET_APPS_SHOW_DESKTOP_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/show-desktop.desktop 0644
  desktop_normalize_public_desktop_directories
  desktop_stage_role_asset FILE_TARGET_APPS_LABWC_TWEAKS_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/labwc-tweaks.desktop 0644
  desktop_stage_role_asset FILE_TARGET_APPS_HYPRPOLKITAGENT_TMPL __INSTALLER_PATH_DIR_USR_LOCAL__/share/applications/hyprpolkitagent.desktop 0644
  desktop_stage_role_asset FILE_TARGET_SHARE_ICONS_HICOLOR_64X64_APPS_SHOW_DESKTOP_PNG __INSTALLER_PATH_DIR_USR_LOCAL__/share/icons/hicolor/64x64/apps/show-desktop.png 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_MAKO_CONFIG_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/mako/config 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_SATTY_CONFIG_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/satty/config.toml 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_WAYSCRIBER_CONFIG_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/wayscriber/config.toml 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_SATTY_OVERRIDES_CSS_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/satty/overrides.css 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_SWAYLOCK_CONFIG_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/swaylock/config 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_WIREPLUMBER_WIREPLUMBER_CONF_D_10_DISABLE_BLUEZ_MIDI __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/wireplumber/wireplumber.conf.d/10-disable-bluez-midi.conf 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_WIREPLUMBER_WIREPLUMBER_CONF_D_20_AUDIO_POLICY __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/wireplumber/wireplumber.conf.d/20-audio-policy.conf 0644
  case "${requested_host_profile:-${HOST_PROFILE:-}}" in
    btrfs-de-p15s|btrfs-de-p15s-duo)
      desktop_stage_role_asset FILE_TARGET_USR_SHARE_WIREPLUMBER_SCRIPTS_P15S_SPEAKER_PROFILE_LUA __INSTALLER_PATH_DIR_USR_SHARE__/wireplumber/scripts/p15s-speaker-profile.lua 0644
      ;;
  esac
  for audio_dir in __INSTALLER_PATH_DIR_ETC__/wireplumber/wireplumber.conf.d __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/wireplumber/wireplumber.conf.d; do
    case "${requested_host_profile:-${HOST_PROFILE:-}}" in
      btrfs-de-p15s|btrfs-de-p15s-duo)
        desktop_stage_role_asset FILE_TARGET_WIREPLUMBER_WIREPLUMBER_CONF_D_30_P15S_AUDIO "$audio_dir/30-p15s-audio.conf" 0644
        ;;
      *) rm -f "${TARGET_ROOT}$audio_dir/30-p15s-audio.conf" ;;
    esac
  done
  desktop_render_gtk_settings
  desktop_render_qt6ct_config
  desktop_stage_role_asset FILE_TARGET_SKEL_KWALLETRC __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/kwalletrc 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_KWALLETRC "${DIR_USR_LOCAL_SHARE}/labwc-app/defaults/kwalletrc" 0644
  install -d -m 0700 \
    ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/Code/User \
    ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/chromium/Default \
    ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/microsoft-edge/Default \
    ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/obsidian \
    ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/vivaldi/Default
  desktop_stage_role_asset FILE_TARGET_SKEL_CODE_USER_SETTINGS_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/Code/User/settings.json 0600
  desktop_stage_role_asset FILE_TARGET_SKEL_CHROMIUM_DEFAULT_PREFERENCES __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/chromium/Default/Preferences 0600
  desktop_stage_role_asset FILE_TARGET_SKEL_MICROSOFT_EDGE_DEFAULT_PREFERENCES __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/microsoft-edge/Default/Preferences 0600
  desktop_stage_role_asset FILE_TARGET_SKEL_OBSIDIAN __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/obsidian/obsidian.json 0600
  desktop_stage_role_asset FILE_TARGET_SKEL_VIVALDI_LOCAL_STATE "__INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/vivaldi/Local State" 0600
  desktop_stage_role_asset FILE_TARGET_SKEL_VIVALDI_DEFAULT_PREFERENCES __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/vivaldi/Default/Preferences 0600
  # The sandbox session seeds missing Vivaldi caches from signed vendor data;
  # subsequent cache updates remain owned by the browser.
  desktop_stage_syncthing_ignore
  install -d -m 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/keepassxc
  desktop_stage_role_asset FILE_TARGET_SKEL_KEEPASSXC_KEEPASSXC_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/keepassxc/keepassxc.ini 0600
  # Non-secret fallback defaults for unprivileged runtime repair. The private
  # skeleton is reserved for privileged provisioning of future accounts.
  desktop_stage_role_asset FILE_TARGET_SKEL_KEEPASSXC_KEEPASSXC_TMPL "${DIR_USR_LOCAL_SHARE}/keepassxc/keepassxc.ini" 0644
  chmod 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/keepassxc
  install -d -m 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/zoom
  desktop_stage_role_asset FILE_TARGET_SKEL_ZOOM_ZOOMUS_TMPL __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/zoom/zoomus.conf 0600
  chmod 0700 ${TARGET_ROOT}${DIR_ETC_SKEL_DESKTOP}/.config/zoom
  desktop_stage_role_asset FILE_TARGET_SKEL_XDG_DESKTOP_PORTAL_PORTALS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/xdg-desktop-portal/portals.conf 0644
  desktop_stage_role_asset FILE_TARGET_SKEL_USER_DIRS_DIRS __INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/user-dirs.dirs 0644
  desktop_render_chromium_flags
}

# Desktop boot recovery ordering is not inherited by headless services.
desktop_stage_apparmor_recovery_order() {
  desktop_stage_role_asset FILE_TARGET_UNIT_APPARMOR_DESKTOP_RECOVERY "${DIR_SYSTEMD_SYSTEM_APPARMOR_MODES_DROPIN}/50-desktop-recovery.conf" 0644
}
