#!/bin/sh
# One offline physical-network publisher for every desktop and server role.
set -eu
set +x
set +v
umask 077
runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}
# shellcheck disable=SC1090
. "$bootstrap_lib"
bootstrap_source_common_lib ""
seed_base=$(installer_seed_base "")
installer_ensure_context_loaded "$seed_base"
u_profile="${DIR_INSTALLER_LATE_ENV}/uplinks-profile.env"
installer_fetch_host_env "$seed_base" "$INSTALLER_HOST_PROFILE" "$u_profile" 0600
installer_load_data_env "$u_profile"
installer_assert_class_plan
[ "$WIFI_ENABLE" = "$(installer_plan_value wifi_enable)" ] &&
  [ "$MANAGED_NETWORK_PRIMARY_IFACE" = "$(installer_plan_value primary_iface)" ] &&
  [ "$IPV6_ENABLE" = "$(installer_plan_value ipv6_enable)" ] || installer_fatal 'physical network policy differs from frozen plan'
bootstrap_source_common_support_libs "$seed_base" "${DIR_INSTALLER_LATE_ENV}/uplinks-support" target fetch hook
# Reuse the authenticated hardware/address reader. It defines functions only;
# canonical paths pass through the same publication renderer as other assets.
u_reader="${DIR_INSTALLER_LATE_ENV}/uplinks-reader.sh"
installer_fetch_file "$seed_base" "$(installer_repo_file_value FILE_LATE_NETWORK)" "$u_reader.source" 0600
installer_apply_scalar_placeholders "$u_reader.source" "$u_reader"
installer_assert_no_unresolved_path_placeholders "$u_reader" "$u_reader.source"
# shellcheck disable=SC1090
. "$u_reader"
u_ethernet=$(installer_network_interface_for_handoff ethernet) || installer_fatal 'installation requires a physical Ethernet interface'
u_ethernet_mac=$(installer_interface_mac_address "$u_ethernet") || installer_fatal 'cannot bind the installation Ethernet adapter'
u_wifi=
u_wifi_mac=
if u_wifi=$(installer_network_interface_for_handoff wifi); then
  u_wifi_mac=$(installer_interface_mac_address "$u_wifi") || installer_fatal 'cannot bind the selected Wi-Fi adapter'
else
  u_status=$?
  [ "$u_status" -eq 1 ] || installer_fatal 'invalid private Wi-Fi adapter selection'
fi
u_ssid=; u_security=; u_passphrase=; u_cidr=
if [ "$WIFI_ENABLE" = true ]; then
  u_ssid=$(installer_cmdline_value wifi_essid) || installer_fatal 'enabled Wi-Fi requires wifi_essid in installer credential input'
  u_security=$(installer_cmdline_value wifi_security) || installer_fatal 'enabled Wi-Fi requires private WPA2/3 policy'
  u_passphrase=$(installer_cmdline_password_value wifi_wpa) || installer_fatal 'enabled Wi-Fi requires a private AP credential'
fi
if u_cidr=$(installer_cmdline_value wifi_cidr); then :; else
  u_status=$?; [ "$u_status" -eq 1 ] || installer_fatal 'invalid private Wi-Fi address range'
fi
u_ip=$(network_answer_value netcfg/get_ipaddress ip || true)
u_netmask=$(network_answer_value netcfg/get_netmask netmask || true)
u_gateway=$(network_answer_value netcfg/get_gateway gateway || true)
u_dns=$(network_answer_value netcfg/get_nameservers nameservers dns || true)
u_dns=$(normalize_network_address_list "$u_dns")
[ -n "$u_dns" ] || u_dns=${STATIC_INSTALLER_NAMESERVER:-}
u_ipv6=; u_gateway6=; u_dns6=
u_dns_mode=link
if [ "$INSTALLER_HOST_VARIANT" = desktop ] && [ -n "${SYSTEM_NAMESERVERS_HOSTNAME_DNS1:-}" ]; then u_dns_mode=global; fi
if [ "$IPV6_ENABLE" = true ]; then
  u_ipv6=$(installer_cmdline_value ipv6_address || true)
  u_gateway6=$(installer_cmdline_value ipv6_gateway || true)
  u_dns6=$(installer_cmdline_value ipv6_nameservers || true)
  u_dns6=$(normalize_network_address_list "$u_dns6")
fi
if [ ! -d "${TARGET_ROOT}${DIR_VAR_LIB_INSTALLER_STATE}" ]; then
  install -d -m 0755 "${TARGET_ROOT}${DIR_VAR_LIB_INSTALLER_STATE}"
fi
u_input=$(mktemp "${TARGET_ROOT}${DIR_VAR_LIB_INSTALLER_STATE}/.network-input-XXXXXX")
{
  printf '%s\t%s\n' format 1 family "$INSTALLER_HOST_VARIANT" mode "$(target_managed_network_mode)" \
    primary "$MANAGED_NETWORK_PRIMARY_IFACE" wifi_enable "$WIFI_ENABLE" \
    ethernet_iface "$MANAGED_NETWORK_ETHERNET_IFACE" ethernet_mac "$u_ethernet_mac" \
    wifi_iface "$MANAGED_NETWORK_WIFI_IFACE" wifi_mac "$u_wifi_mac" \
    installer_ethernet_iface "$u_ethernet" installer_wifi_iface "$u_wifi" \
    address "$u_ip" netmask "$u_netmask" gateway "$u_gateway" dns "$u_dns" \
    ssid "$u_ssid" security "$u_security" passphrase "$u_passphrase" wifi_cidr "$u_cidr" \
    ipv6_enable "$IPV6_ENABLE" ipv6_address "$u_ipv6" ipv6_gateway "$u_gateway6" ipv6_dns "$u_dns6" dns_mode "$u_dns_mode"
} >"$u_input"
unset u_passphrase u_ssid
trap 'rm -f "$u_input"' 0
installer_run_target_setup FILE_OS_NETWORK_PROFILE_STAGE 'publish physical network policy without activating adapters' "${u_input#"$TARGET_ROOT"}"
rm -f "$u_input"
installer_stage_profile_file FILE_TARGET_LIBEXEC_NETWORK_WIFI_CONFIGURE "${DIR_USR_LOCAL_LIBEXEC}/network-wifi-configure" 0755
installer_stage_profile_file FILE_TARGET_NETWORKMANAGER_DISPATCHER_D_90_MANAGED_WIFI_PREFERENCE \
  "${DIR_NETWORKMANAGER}/dispatcher.d/90-managed-wifi-preference" 0755
installer_stage_profile_file FILE_TARGET_UNIT_WIFI_FIRSTBOOT_SERVICE "${DIR_SYSTEMD_SYSTEM}/wifi-firstboot.service" 0644
installer_stage_offline_unit_link "${DIR_SYSTEMD_SYSTEM}/wifi-firstboot.service"
# Native systemd package interface. Only create offline activation links; no
# service manager, adapter or resolver is contacted by this installer stage.
installer_stage_offline_unit_link "${DIR_USR_LIB}/systemd/system/NetworkManager.service"
installer_info 'physical adapter priority and paired Wi-Fi addressing staged; private AP enrollment follows WIFI_ENABLE'
