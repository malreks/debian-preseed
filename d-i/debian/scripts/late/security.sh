#!/bin/sh
# Shared late_command security helpers. This file is sourced, not executed.

nftables_normalize_env_token() {
  nftables_ws=$(printf ' \011\015\012_')
  nftables_ws=${nftables_ws%_}

  # d-i tr implementations may treat [:upper:] and [:space:] as literal sets,
  # which corrupts "default" into "dfllt". Use explicit ASCII sets here.
  printf '%s' "$1" |
    tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz' |
    tr -d "$nftables_ws"
}

late_command_nftables_requested_profile() {
  nft_profile=$(nftables_normalize_env_token "${NFT_PROFILE:-default}")
  [ -n "$nft_profile" ] || installer_fatal "NFT_PROFILE must not be empty"

  case "$nft_profile" in
    none|default|baseline|desktop|server)
      printf '%s\n' "$nft_profile"
      ;;
    *)
      installer_fatal "unsupported NFT_PROFILE: ${nft_profile}; expected none, default, baseline, server, or desktop"
      ;;
  esac
}

late_command_nftables_host_variant() {
  host_variant=${INSTALLER_HOST_VARIANT:-}
  if [ -z "$host_variant" ]; then
    host_variant=$(installer_selected_class_for_purpose host-variant 2>__INSTALLER_PATH_DIR_DEV__/null || true)
  fi

  case "$host_variant" in
    desktop|server)
      printf '%s\n' "$host_variant"
      ;;
    '')
      installer_fatal "NFT_PROFILE=default requires a selected role class (desktop or server)"
      ;;
    *)
      installer_fatal "NFT_PROFILE=default cannot resolve unsupported host variant: ${host_variant}"
      ;;
  esac
}

security_target_is_desktop() {
  [ "$(late_command_nftables_host_variant)" = desktop ]
}

late_command_nftables_profile() {
  nft_profile=${1:-$(late_command_nftables_requested_profile)}

  case "$nft_profile" in
    none|baseline|desktop)
      printf '%s\n' "$nft_profile"
      ;;
    server)
      printf '%s\n' baseline
      ;;
    default)
      case "$(late_command_nftables_host_variant)" in
        desktop) printf '%s\n' desktop ;;
        server) printf '%s\n' baseline ;;
      esac
      ;;
    *)
      installer_fatal "unsupported normalized NFT_PROFILE: ${nft_profile}; expected none, default, baseline, server, or desktop"
      ;;
  esac
}

nftables_service_assets() {
  cat <<'EOF'
backup-restic
crowdsec
cups
dhcp-client
dns-client
docker
egress
kdeconnect
lan-share
mdns
nfs-server
nfs-client
ntp-client
ollama
openvpn
podman
qemu
qbittorrent
rsync
samba
smtp-client
ssdp
ssh-client
ssh-server
syncthing
tailscale
wazuh-agent
wireguard
zerotier
EOF
}

nftables_service_asset_supported() {
  candidate=$1

  case "$candidate" in
    backup-restic|crowdsec|cups|dhcp-client|dns-client|docker|egress|kdeconnect|lan-share|mdns|nfs-server|nfs-client|ntp-client|ollama|openvpn|podman|qemu|qbittorrent|rsync|samba|smtp-client|ssdp|ssh-client|ssh-server|syncthing|tailscale|wazuh-agent|wireguard|zerotier)
      return 0
      ;;
  esac

  return 1
}

late_command_nftables_services() {
  nft_services=$(nftables_normalize_env_token "${NFT_SERVICES:-none}")
  [ -n "$nft_services" ] || installer_fatal "NFT_SERVICES must not be empty when NFT_PROFILE is not none"

  case "$nft_services" in
    none)
      return 0
      ;;
    *[!abcdefghijklmnopqrstuvwxyz0123456789,-]*)
      installer_fatal "NFT_SERVICES contains unsupported characters: ${nft_services}"
      ;;
    ,*|*,|*,,*)
      installer_fatal "NFT_SERVICES must be a comma-separated list without empty entries: ${nft_services}"
      ;;
  esac

  old_ifs=$IFS
  IFS=,
  # shellcheck disable=SC2086
  set -- $nft_services
  IFS=$old_ifs

  selected_services=
  for service_asset in "$@"; do
    [ "$service_asset" != none ] || installer_fatal "NFT_SERVICES=none cannot be combined with service names"
    nftables_service_asset_supported "$service_asset" ||
      installer_fatal "unsupported NFT_SERVICES entry: ${service_asset}"
    case " $selected_services " in
      *" $service_asset "*) ;;
      *) selected_services="${selected_services:+$selected_services }$service_asset" ;;
    esac
  done

  printf '%s\n' "$selected_services"
}

nftables_merge_selected_services() {
  selected_services=$1
  shift

  merged_services=$selected_services
  for service_asset in "$@"; do
    [ -n "$service_asset" ] || continue
    case " $merged_services " in
      *" $service_asset "*) ;;
      *) merged_services="${merged_services:+$merged_services }$service_asset" ;;
    esac
  done

  printf '%s\n' "$merged_services"
}

late_command_nftables_effective_services() {
  selected_services=$(late_command_nftables_services)
  # The global resolver always uses the rendered authenticated upstream port,
  # including when a site selects the strict egress overlay or no services.
  effective_services=$(nftables_merge_selected_services "$selected_services" \
    dns-client dhcp-client ntp-client ssh-client smtp-client)

  # Select daemon/discovery overlays from the frozen package plan, not a
  # second per-host firewall feature list. Every listener keeps its LAN ACL.
  if security_target_is_desktop; then
    # Desktop applications also discover printers, media renderers and LAN
    # peers without a separately selected local discovery daemon.
    effective_services=$(nftables_merge_selected_services "$effective_services" lan-share mdns ssdp)
    for nft_package_overlay in \
      avahi-daemon:mdns cups:cups cups-daemon:cups kdeconnect:kdeconnect \
      wsdd:ssdp samba:samba syncthing:syncthing
    do
      nft_package=${nft_package_overlay%%:*}
      if installer_plan_package_selected "$nft_package"; then
        case "$nft_package" in
          cups|cups-daemon) nft_package_services='cups mdns' ;;
          *) nft_package_services=${nft_package_overlay#*:} ;;
        esac
        # These words come only from the fixed table above.
        # shellcheck disable=SC2086
        effective_services=$(nftables_merge_selected_services "$effective_services" $nft_package_services)
      fi
    done
  fi

  if installer_any_role_class_selected 2>__INSTALLER_PATH_DIR_DEV__/null; then
    effective_services=$(nftables_merge_selected_services "$effective_services" crowdsec)
  fi

  if nftables_tailscale_selected; then
    effective_services=$(nftables_merge_selected_services "$effective_services" tailscale)
  fi

  if [ "${SSH_SERVER_ENABLED:-false}" = true ]; then
    effective_services=$(nftables_merge_selected_services "$effective_services" ssh-server)
  fi

  if [ "${NFS_SERVER_ENABLE:-false}" = true ]; then
    effective_services=$(nftables_merge_selected_services "$effective_services" nfs-server)
  fi
  if [ "${NFS_CLIENT_ENABLE:-false}" = true ]; then
    effective_services=$(nftables_merge_selected_services "$effective_services" nfs-client)
  fi

  if nftables_qemu_selected; then
    effective_services=$(nftables_merge_selected_services "$effective_services" qemu)
  fi

  if [ "$effective_services" != "$selected_services" ]; then
    installer_info "nftables service overlays adjusted from ${selected_services:-none} to $(printf '%s' "$effective_services" | tr ' ' ',')"
  fi

  printf '%s\n' "$effective_services"
}

stage_target_nftables_service_assets() {
  for service_asset in "$@"; do
    case "$service_asset" in
      dns-client) placeholder_map=app_veth_dns_placeholder_map ;;
      lan-share) placeholder_map=nftables_lan_share_service_placeholder_map ;;
      ssh-server) placeholder_map=nftables_ssh_service_placeholder_map ;;
      syncthing) placeholder_map=nftables_syncthing_service_placeholder_map ;;
      tailscale) placeholder_map=nftables_tailscale_service_placeholder_map ;;
      qemu) placeholder_map=nftables_qemu_service_placeholder_map ;;
      nfs-server|nfs-client) placeholder_map=network_sharing_nftables_placeholder_map ;;
      *) placeholder_map=nftables_interface_placeholder_map ;;
    esac
    render_target_asset_with_placeholder_map \
      "$(installer_repo_asset_path DIR_TARGET_NFTABLES_SERVICES "${service_asset}.yml")" \
      "__INSTALLER_PATH_DIR_ETC__/nftables/services/${service_asset}.yml" \
      0644 \
      "$placeholder_map"
  done
}

stage_target_nftables_profile_assets() {
  for profile_asset in baseline desktop; do
    render_target_asset_with_placeholder_map \
      "$(installer_repo_asset_path DIR_TARGET_NFTABLES_PROFILES "${profile_asset}.yml")" \
      "__INSTALLER_PATH_DIR_ETC__/nftables/profiles/${profile_asset}.yml" \
      0644 \
      nftables_app_veth_profile_placeholder_map
  done
}

nftables_app_veth_profile_placeholder_map() {
  app_veth_identity_placeholder_map || return "$?"
  proxy3_placeholder_map || return "$?"
  nftables_interface_placeholder_map
}

stage_target_nftables_all_service_assets() {
  for service_asset in $(nftables_service_assets); do
    stage_target_nftables_service_assets "$service_asset"
  done
}

nftables_service_overlay_paths() {
  selected_paths=

  for service_asset in "$@"; do
    selected_paths="${selected_paths:+$selected_paths }__INSTALLER_PATH_DIR_ETC__/nftables/services/${service_asset}.yml"
  done

  printf '%s\n' "$selected_paths"
}

nftables_runtime_cidr_pairs() {
  if [ "${MANAGED_NETWORK_IPV6_ENABLED:-false}" = true ]; then
    for cidr in ${MANAGED_NETWORK_IPV6_HOST_CIDRS:-${MANAGED_NETWORK_IPV6_HOST_CIDR:-}}; do
      printf '%s\n' "desktop_static_ipv6_host=${cidr}"
    done
    for cidr in ${MANAGED_NETWORK_IPV6_NETWORK_CIDRS:-${MANAGED_NETWORK_IPV6_NETWORK_CIDR:-}}; do
      printf '%s\n' "desktop_static_ipv6_network=${cidr}"
      printf '%s\n' "lan_ipv6=${cidr}"
    done
  fi
  if [ "${MANAGED_NETWORK_IPV4_ENABLED:-false}" = true ]; then
    for cidr in ${MANAGED_NETWORK_IPV4_NETWORK_CIDRS:-}; do
      printf '%s\n' "lan_ipv4=${cidr}"
    done
  fi
}

nftables_runtime_cidrs_env_value() {
  runtime_cidrs=
  while IFS= read -r cidr_pair || [ -n "$cidr_pair" ]; do
    [ -n "$cidr_pair" ] || continue
    runtime_cidrs="${runtime_cidrs:+$runtime_cidrs }${cidr_pair}"
  done <<EOF
$(nftables_runtime_cidr_pairs)
EOF
  printf '%s\n' "$runtime_cidrs"
}

nftables_managed_iface_value() {
  label=$1
  value=$2
  fallback=$3
  iface=${value:-$fallback}

  case "$iface" in
    ''|.|..|lo)
      installer_fatal "${label} must be a non-loopback interface name"
      ;;
  esac
  case "$iface" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-]*)
      installer_fatal "${label} contains unsupported characters: ${iface}"
      ;;
  esac
  [ "${#iface}" -le 15 ] || installer_fatal "${label} must be 15 characters or fewer: ${iface}"
  printf '%s\n' "$iface"
}

nftables_interface_placeholder_map() {
  ethernet_iface=$(nftables_managed_iface_value MANAGED_NETWORK_ETHERNET_IFACE "${MANAGED_NETWORK_ETHERNET_IFACE:-}" eth0)
  wifi_iface=$(nftables_managed_iface_value MANAGED_NETWORK_WIFI_IFACE "${MANAGED_NETWORK_WIFI_IFACE:-}" wifi0)

  [ "$ethernet_iface" != "$wifi_iface" ] ||
    installer_fatal "MANAGED_NETWORK_ETHERNET_IFACE and MANAGED_NETWORK_WIFI_IFACE must differ"

  printf 'MANAGED_NETWORK_ETHERNET_IFACE=%s\n' "$ethernet_iface"
  printf 'MANAGED_NETWORK_WIFI_IFACE=%s\n' "$wifi_iface"
}

nftables_validate_port_value() {
  label=$1
  value=$2

  case "$value" in
    ''|*[!0-9]*)
      installer_fatal "${label} must be a numeric TCP/UDP port"
      ;;
  esac
  [ "$value" -ge 1 ] && [ "$value" -le 65535 ] ||
    installer_fatal "${label} must be in range 1..65535"
}

nftables_validate_cidr_token() {
  label=$1
  value=$2

  case "$value" in
    ''|*[!0123456789abcdefABCDEF:./]*)
      installer_fatal "${label} contains unsupported CIDR characters: ${value:-unset}"
      ;;
  esac
  case "$value" in
    */*)
      ;;
    *)
      installer_fatal "${label} must be CIDR-formatted"
      ;;
  esac
}

network_sharing_nftables_placeholder_map() {
  printf 'NFS_SERVER_ENABLE=%s\n' "${NFS_SERVER_ENABLE:-false}"
  printf 'NFS_CLIENT_ENABLE=%s\n' "${NFS_CLIENT_ENABLE:-false}"
  printf 'NFS_SERVER_PORT=%s\n' "${NFS_SERVER_PORT:?}"
  # The target configurator validates the complete export grammar before the
  # firewall is staged. Derive the allowlist from that same source of truth.
  nfs_cidrs=$(printf '%s\n' "${NFS_SERVER_EXPORTS:-}" | awk '{
    for (i=2; i<=NF; i++) { peer=$i; sub(/\(.*/, "", peer); if (peer !~ /\//) peer=peer "/32"; print peer }
  }')
  # shellcheck disable=SC2086
  printf 'NFS_SERVER_ALLOW_IPV4=%s\n' "$(nftables_yaml_inline_list $nfs_cidrs)"
  if [ -n "${NFS_CLIENT_TARGET_IP:-}" ]; then
    printf 'NFS_CLIENT_ALLOW_IPV4=%s\n' "$(nftables_yaml_inline_list "${NFS_CLIENT_TARGET_IP}/32")"
  else
    printf 'NFS_CLIENT_ALLOW_IPV4=[]\n'
  fi
  # shellcheck disable=SC2086
  printf 'NFS_ALLOW_INTERFACES=%s\n' "$(nftables_yaml_inline_list ${NFS_INTERFACES:-})"
}

nftables_yaml_inline_list() {
  if [ "$#" -eq 0 ]; then
    printf '[]\n'
    return 0
  fi

  first=true
  printf '['
  for item in "$@"; do
    [ -n "$item" ] || continue
    if [ "$first" = true ]; then
      first=false
    else
      printf ', '
    fi
    printf '"%s"' "$item"
  done
  if [ "$first" = true ]; then
    printf '[]\n'
    return 0
  fi
  printf ']\n'
}

nftables_merge_unique_tokens() {
  merged=
  for token in "$@"; do
    [ -n "$token" ] || continue
    case " $merged " in
      *" $token "*) ;;
      *) merged="${merged:+$merged }$token" ;;
    esac
  done
  printf '%s\n' "$merged"
}

nftables_ipv4_to_int() {
  addr=$1
  old_ifs=${IFS}
  IFS=.
  set -- $addr
  IFS=${old_ifs}
  [ "$#" -eq 4 ] || installer_fatal "invalid IPv4 address: ${addr}"
  for octet in "$@"; do
    case "$octet" in
      ''|*[!0-9]*)
        installer_fatal "invalid IPv4 address: ${addr}"
        ;;
    esac
    [ "$octet" -ge 0 ] && [ "$octet" -le 255 ] ||
      installer_fatal "invalid IPv4 address: ${addr}"
  done
  printf '%s\n' "$((($1 << 24) + ($2 << 16) + ($3 << 8) + $4))"
}

nftables_ipv4_from_int() {
  value=$1
  printf '%s.%s.%s.%s\n' \
    "$(((value >> 24) & 255))" \
    "$(((value >> 16) & 255))" \
    "$(((value >> 8) & 255))" \
    "$((value & 255))"
}

nftables_ipv4_network_cidr() {
  addr=$1
  prefix=$2

  nftables_validate_port_value IPv4_prefix_length "$prefix"
  [ "$prefix" -le 32 ] || installer_fatal "IPv4 prefix length must be 32 or lower"
  addr_int=$(nftables_ipv4_to_int "$addr")
  if [ "$prefix" -eq 0 ]; then
    mask=0
  else
    mask=$(((0xffffffff << (32 - prefix)) & 0xffffffff))
  fi
  network_int=$((addr_int & mask))
  printf '%s/%s\n' "$(nftables_ipv4_from_int "$network_int")" "$prefix"
}

nftables_ipv6_expand() {
  addr=$1
  has_double_colon=false
  head=${addr}
  tail=

  case "$addr" in
    *::*)
      has_double_colon=true
      head=${addr%%::*}
      tail=${addr#*::}
      ;;
  esac

  head_count=0
  tail_count=0
  head_words=
  tail_words=

  if [ -n "$head" ]; then
    head_words=$(printf '%s\n' "$head" | tr ':' ' ')
    set -- $head_words
    head_count=$#
  fi
  if [ -n "$tail" ]; then
    tail_words=$(printf '%s\n' "$tail" | tr ':' ' ')
    set -- $tail_words
    tail_count=$#
  fi

  if [ "$has_double_colon" = true ]; then
    missing=$((8 - head_count - tail_count))
    [ "$missing" -ge 0 ] || installer_fatal "invalid IPv6 address: ${addr}"
  else
    missing=0
    [ $((head_count + tail_count)) -eq 8 ] || installer_fatal "invalid IPv6 address: ${addr}"
  fi

  expanded=
  for field in $head_words; do
    [ -n "$field" ] || continue
    expanded="${expanded:+$expanded }$field"
  done
  while [ "$missing" -gt 0 ]; do
    expanded="${expanded:+$expanded }0"
    missing=$((missing - 1))
  done
  for field in $tail_words; do
    [ -n "$field" ] || continue
    expanded="${expanded:+$expanded }$field"
  done

  set -- $expanded
  [ "$#" -eq 8 ] || installer_fatal "invalid IPv6 address: ${addr}"
  for field in "$@"; do
    case "$field" in
      ''|*[!0123456789abcdefABCDEF]*)
        installer_fatal "invalid IPv6 address: ${addr}"
        ;;
    esac
    [ "${#field}" -le 4 ] || installer_fatal "invalid IPv6 address: ${addr}"
  done
  printf '%s\n' "$expanded"
}

nftables_ipv6_network_cidr() {
  addr=$1
  prefix=$2

  nftables_validate_port_value IPv6_prefix_length "$prefix"
  [ "$prefix" -le 128 ] || installer_fatal "IPv6 prefix length must be 128 or lower"
  [ $((prefix % 16)) -eq 0 ] ||
    installer_fatal "IPv6 prefix length must align to 16-bit boundaries for SSH nftables rendering"
  keep_hextets=$((prefix / 16))
  expanded=$(nftables_ipv6_expand "$addr")
  index=0
  network=
  for field in $expanded; do
    if [ "$index" -lt "$keep_hextets" ]; then
      network="${network:+$network:}$field"
    else
      network="${network:+$network:}0"
    fi
    index=$((index + 1))
  done
  printf '%s/%s\n' "$network" "$prefix"
}

nftables_tailscale_selected() {
  installer_plan_package_selected tailscale
}

nftables_qemu_selected() {
  installer_tools_class_selected 2>__INSTALLER_PATH_DIR_DEV__/null || return 1
  [ "${INSTALLER_HOST_VARIANT:-}" = desktop ]
}

nftables_qemu_allow_interfaces() {
  incus_bridge=${INCUS_BRIDGE_NAME:-incusbr0}
  nftables_managed_iface_value INCUS_BRIDGE_NAME "$incus_bridge" incusbr0
}

nftables_qemu_service_placeholder_map() {
  qemu_allow_interfaces=$(nftables_qemu_allow_interfaces)
  printf 'NFTABLES_QEMU_ALLOW_INTERFACES=%s\n' "$(nftables_yaml_inline_list $qemu_allow_interfaces)"
}

nftables_tailscale_interface() {
  tailscale_iface=${TAILSCALE_INTERFACE:-tailscale0}
  nftables_managed_iface_value TAILSCALE_INTERFACE "$tailscale_iface" tailscale0
}

nftables_tailscale_allow_ipv4_cidrs() {
  printf '%s\n' '100.64.0.0/10'
}

nftables_tailscale_allow_ipv6_cidrs() {
  printf '%s\n' 'fd7a:115c:a1e0::/48'
}

nftables_ssh_allow_interfaces() {
  ethernet_iface=$(nftables_managed_iface_value MANAGED_NETWORK_ETHERNET_IFACE "${MANAGED_NETWORK_ETHERNET_IFACE:-}" eth0)
  wifi_iface=$(nftables_managed_iface_value MANAGED_NETWORK_WIFI_IFACE "${MANAGED_NETWORK_WIFI_IFACE:-}" wifi0)

  [ "$ethernet_iface" != "$wifi_iface" ] ||
    installer_fatal "MANAGED_NETWORK_ETHERNET_IFACE and MANAGED_NETWORK_WIFI_IFACE must differ"

  cat <<EOF
eth0
en*
$ethernet_iface
wlan0
wl*
$wifi_iface
wg0
EOF
}

nftables_ssh_allow_ipv4_cidrs() {
  ssh_allow_cidr=${SSH_SERVER_CIDR_ALLOW:-}
  nftables_validate_cidr_token SSH_SERVER_CIDR_ALLOW "$ssh_allow_cidr"
  printf '%s\n' "$ssh_allow_cidr"
}

nftables_ssh_allow_ipv6_cidrs() {
  if [ -n "${MANAGED_NETWORK_IPV6_NETWORK_CIDRS:-}" ]; then
    printf '%s\n' "$(nftables_merge_unique_tokens ${MANAGED_NETWORK_IPV6_NETWORK_CIDRS})"
    return 0
  fi
  cat <<'EOF'
fc00::/7
fe80::/10
EOF
}

# Never use the broad lan_ipv4/lan_ipv6 groups here. Only the networks
# calculated from this host's managed address configuration may reach a share.
# Empty families remain empty; sensitive-service validation rejects an overlay
# selected without any configured subnet instead of opening a public listener.
nftables_lan_share_service_placeholder_map() {
  lan_share_ipv4=
  lan_share_ipv6=
  if [ "${MANAGED_NETWORK_IPV4_ENABLED:-false}" = true ]; then
    lan_share_ipv4=$(nftables_merge_unique_tokens ${MANAGED_NETWORK_IPV4_NETWORK_CIDRS:-})
  fi
  if [ "${MANAGED_NETWORK_IPV6_ENABLED:-false}" = true ]; then
    lan_share_ipv6=$(nftables_merge_unique_tokens ${MANAGED_NETWORK_IPV6_NETWORK_CIDRS:-})
  fi
  for cidr in $lan_share_ipv4 $lan_share_ipv6; do
    nftables_validate_cidr_token LAN_share_subnet "$cidr"
    case "$cidr" in
      */0) installer_fatal "LAN sharing must not allow a default-route subnet" ;;
    esac
  done
  ethernet_iface=$(nftables_managed_iface_value MANAGED_NETWORK_ETHERNET_IFACE "${MANAGED_NETWORK_ETHERNET_IFACE:-}" eth0)
  wifi_iface=$(nftables_managed_iface_value MANAGED_NETWORK_WIFI_IFACE "${MANAGED_NETWORK_WIFI_IFACE:-}" wifi0)
  [ "$ethernet_iface" != "$wifi_iface" ] ||
    installer_fatal "LAN sharing requires distinct managed interface names"
  printf 'NFTABLES_LAN_SHARE_ALLOW_IPV4=%s\n' "$(nftables_yaml_inline_list $lan_share_ipv4)"
  printf 'NFTABLES_LAN_SHARE_ALLOW_IPV6=%s\n' "$(nftables_yaml_inline_list $lan_share_ipv6)"
  printf 'NFTABLES_LAN_SHARE_ALLOW_INTERFACES=%s\n' "$(nftables_yaml_inline_list "$ethernet_iface" "$wifi_iface")"
}

# Mullvad owns a separate filter table, which must not be flushed or bypassed.
# Use its supported LAN setting only for hosts selecting the LAN-share policy;
# the daemon remains demand-started by the existing application policy.
stage_target_nftables_mullvad_lan_policy() {
  case " $1 " in
    *" lan-share "*)
      if [ -x ${TARGET_ROOT}${DIR_USR_BIN}/mullvad ]; then
        stage_target_asset \
          "$(installer_repo_file_value hooks/target/usr/local/libexec/desktop/mullvad-lan-allow)" \
          __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/mullvad-lan-allow 0755
        stage_target_asset \
          "$(installer_repo_file_value hooks/target/etc/systemd/desktop/system/mullvad-daemon.service.d/25-lan-sharing.conf)" \
          __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_MULLVAD_DAEMON_DROPIN__/25-lan-sharing.conf 0644
        return 0
      fi
      ;;
  esac
  rm -f ${TARGET_ROOT}${DIR_SYSTEMD_SYSTEM_MULLVAD_DAEMON_DROPIN}/25-lan-sharing.conf \
    ${TARGET_ROOT}${DIR_USR_LOCAL_LIBEXEC}/mullvad-lan-allow
}

nftables_ssh_service_placeholder_map() {
  ssh_allow_ipv4=$(nftables_ssh_allow_ipv4_cidrs)
  ssh_allow_ipv6=$(nftables_ssh_allow_ipv6_cidrs)
  ssh_allow_interfaces=$(nftables_ssh_allow_interfaces)

  # Both active and dormant catalog entries use the profile's declared port.
  runtime_apply_ssh_from_cmdline
  nftables_validate_port_value SSH_PORT "$SSH_PORT"
  while IFS= read -r cidr || [ -n "$cidr" ]; do
    [ -n "$cidr" ] || continue
    nftables_validate_cidr_token SSH_allow_ipv4 "$cidr"
  done <<EOF
$ssh_allow_ipv4
EOF
  while IFS= read -r cidr || [ -n "$cidr" ]; do
    [ -n "$cidr" ] || continue
    nftables_validate_cidr_token SSH_allow_ipv6 "$cidr"
  done <<EOF
$ssh_allow_ipv6
EOF

  nftables_interface_placeholder_map
  printf 'SSH_PORT=%s\n' "$SSH_PORT"
  printf 'NFTABLES_SSH_ALLOW_IPV4=%s\n' "$(nftables_yaml_inline_list $ssh_allow_ipv4)"
  printf 'NFTABLES_SSH_ALLOW_IPV6=%s\n' "$(nftables_yaml_inline_list $ssh_allow_ipv6)"
  printf 'NFTABLES_SSH_ALLOW_INTERFACES=%s\n' "$(nftables_yaml_inline_list $ssh_allow_interfaces)"
}

fail2ban_jail_placeholder_map() {
  # Keep the daemon, jail and firewall on the same profile-controlled port.
  runtime_apply_ssh_from_cmdline
  nftables_validate_port_value SSH_PORT "$SSH_PORT"
  case "${SSH_SERVER_ENABLED:-}" in
    true|false) ;;
    *) installer_fatal "SSH_SERVER_ENABLED must be resolved before Fail2ban rendering" ;;
  esac
  printf 'SSH_PORT=%s\n' "$SSH_PORT"
  printf 'SSHD_JAIL_ENABLED=%s\n' "$SSH_SERVER_ENABLED"
}

nftables_syncthing_service_placeholder_map() {
  syncthing_tcp_port=${SYNCTHING_TCP_PORT:-35000}
  syncthing_iface=$(nftables_tailscale_interface)

  nftables_validate_port_value SYNCTHING_TCP_PORT "$syncthing_tcp_port"
  printf 'SYNCTHING_TCP_PORT=%s\n' "$syncthing_tcp_port"
  printf 'NFTABLES_SYNCTHING_ALLOW_IPV4=%s\n' "$(nftables_yaml_inline_list $(nftables_tailscale_allow_ipv4_cidrs))"
  printf 'NFTABLES_SYNCTHING_ALLOW_IPV6=%s\n' "$(nftables_yaml_inline_list $(nftables_tailscale_allow_ipv6_cidrs))"
  printf 'NFTABLES_SYNCTHING_ALLOW_INTERFACES=%s\n' "$(nftables_yaml_inline_list "$syncthing_iface")"
}

nftables_tailscale_service_placeholder_map() {
  tailscale_udp_port=${TAILSCALE_UDP_PORT:-41641}
  tailscale_ssh_enabled=${TAILSCALE_RUN_SSH_SERVER:-true}
  tailscale_iface=$(nftables_tailscale_interface)

  nftables_validate_port_value TAILSCALE_UDP_PORT "$tailscale_udp_port"
  case "$tailscale_ssh_enabled" in
    true|false) ;;
    *) installer_fatal "TAILSCALE_RUN_SSH_SERVER must be true or false for nftables rendering" ;;
  esac
  nftables_interface_placeholder_map
  printf 'TAILSCALE_INTERFACE=%s\n' "$tailscale_iface"
  printf 'APP_VETH_DNS_HOST_ADDRESS=%s\n' "${APP_VETH_DNS_HOST_ADDRESS:?APP_VETH_DNS_HOST_ADDRESS must be set}"
  printf 'APP_VETH_DNS_HOST_PORT=%s\n' "${APP_VETH_DNS_HOST_PORT:?APP_VETH_DNS_HOST_PORT must be set}"
  printf 'TAILSCALE_UDP_PORT=%s\n' "$tailscale_udp_port"
  printf 'TAILSCALE_RUN_SSH_SERVER=%s\n' "$tailscale_ssh_enabled"
  printf 'NFTABLES_TAILSCALE_ALLOW_IPV4=%s\n' "$(nftables_yaml_inline_list $(nftables_tailscale_allow_ipv4_cidrs))"
  printf 'NFTABLES_TAILSCALE_ALLOW_IPV6=%s\n' "$(nftables_yaml_inline_list $(nftables_tailscale_allow_ipv6_cidrs))"
  printf 'NFTABLES_TAILSCALE_ALLOW_INTERFACES=%s\n' "$(nftables_yaml_inline_list "$tailscale_iface")"
}

apparmor_managed_profile_files() {
  apparmor_managed_system_profile_files
  apparmor_managed_desktop_profile_files
}

apparmor_managed_system_profile_files() {
  cat <<'EOF'
system-wrappers
desktop-system-wrappers
network-sharing
labwc-network-sharing
crun
app-veth
usr.sbin.aa-status
usr.sbin.tailscaled
EOF
  if installer_snapshots_enabled; then printf '%s\n' timeshift; fi
}

apparmor_managed_modes_perl_modules() {
  cat <<'EOF'
AppArmor/ManagedModes/CLI.pm
AppArmor/ManagedModes/Config.pm
AppArmor/ManagedModes/Logger.pm
AppArmor/ManagedModes/TrustedPath.pm
AppArmor/ManagedModes/Tool.pm
AppArmor/ManagedModes/Transition.pm
AppArmor/ManagedModes/LocalChildren.pm
AppArmor/ManagedModes/LoadedState.pm
AppArmor/ManagedModes/Verify.pm
AppArmor/ManagedModes/Workspace.pm
EOF
}

apparmor_managed_desktop_profile_files() {
  cat <<'EOF'
desktop-wrappers
apparmor-modes
tor-browser
zoom-discord-compat
labwc-appearance
compz
debugsys
document-applications
labwc-session
tomat
waybar-menus
calendars
desktop-utilities
whisper-local-transcription
usr.bin.totem
usr.bin.qoredb
usr.bin.spotify
usr.bin.sqlitebrowser
usr.bin.retroarch
usr.bin.qbittorrent
usr.bin.telegram-desktop
usr.bin.keepassxc
usr.bin.zoom
opt.Bitwarden.bitwarden
opt.Filen.Filen
opt.postman.app.Postman
opt.ledger-live.AppRun
opt.tuta-mail.AppRun
Discord
obsidian
sleek
usr.bin.pwsh
usr.sbin.apt-cacher-ng
usr.sbin.avahi-daemon
EOF
  if installer_tools_class_selected 2>__INSTALLER_PATH_DIR_DEV__/null; then
    printf '%s\n' chatgpt gitbuild gitbuild-worker
  fi
}

apparmor_requested_desktop_state() {
  desktop_apparmor_state=${DESKTOP_APPARMOR_STATE:-}

  case "$desktop_apparmor_state" in
    enforce|complain)
      printf '%s\n' "$desktop_apparmor_state"
      ;;
    '')
      installer_fatal "DESKTOP_APPARMOR_STATE must be set by every desktop host profile"
      return 1
      ;;
    *)
      installer_fatal "DESKTOP_APPARMOR_STATE must be enforce or complain, got: ${desktop_apparmor_state}"
      return 1
      ;;
  esac
}

apparmor_apply_desktop_state() (
  set -eu
  umask 077
  mode_config=$1
  desktop_apparmor_state=$(apparmor_requested_desktop_state) || exit 1
  desktop_apparmor_work=$(mktemp -d "${mode_config%/*}/.apparmor-modes.XXXXXX") || exit 1
  trap 'rm -rf -- "$desktop_apparmor_work"' 0
  trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
  printf 'DESKTOP_APPARMOR_STATE=%s\n' "$desktop_apparmor_state" >"$desktop_apparmor_work/map"
  installer_target_perl_render "$mode_config" "$mode_config" \
    "$desktop_apparmor_work/map" apparmor-modes || {
      installer_fatal 'failed to apply the typed desktop AppArmor mode policy'; exit 1;
    }
  chmod 0644 "$mode_config"
  installer_info "managed desktop AppArmor profile state: ${desktop_apparmor_state}; hardware tuning: enforce"
)

security_nvidia_acceleration_enabled() {
  nvidia_class_selected=${NVIDIA_CLASS_SELECTED:-false}
  nvidia_gpu_detected=${NVIDIA_GPU_DETECTED:-false}

  case "$nvidia_class_selected" in
    true|false) ;;
    *)
      installer_fatal "NVIDIA_CLASS_SELECTED must be true or false, got: ${nvidia_class_selected}"
      return 1
      ;;
  esac
  case "$nvidia_gpu_detected" in
    true|false) ;;
    *)
      installer_fatal "NVIDIA_GPU_DETECTED must be true or false, got: ${nvidia_gpu_detected}"
      return 1
      ;;
  esac

  [ "$nvidia_class_selected" = true ] && [ "$nvidia_gpu_detected" = true ]
}

apparmor_managed_local_include_files() {
  cat <<'EOF'
code
vscode
chromium
microsoft-edge-stable
mullvad
mullvad-browser
vivaldi-stable
vivaldi-bin
EOF
}

apparmor_support_local_include_files() {
  cat <<'EOF'
usr.bin.freshclam
unix-chkpwd
EOF
}

apparmor_compat_desktop_local_include_files() {
  cat <<'EOF'
1password
brave
chrome
element-desktop
github-desktop
keybase
opera
qutebrowser
signal-desktop
slack
steam
EOF
}

apparmor_mode_config_has_profile() {
  profile_name=$1
  mode_config=$2

  awk -v expected_profile="$profile_name" '
    /^[[:space:]]*(#|$)/ { next }
    NF == 4 && $3 == expected_profile { matches++ }
    END { exit(matches == 1 ? 0 : 1) }
  ' "$mode_config"
}

apparmor_require_disconnected_profile_flags() {
  profile_path=$1
  profile_name=$2
  unsafe_flag_policy=${3:-reject}

  case "$profile_path" in
    ${TARGET_ROOT}${DIR_APPARMOR}/*) ;;
    *) installer_fatal "refusing to rewrite AppArmor profile outside target policy: ${profile_path}" ;;
  esac
  # Package-owned profiles are direct files in this directory. Reject nested
  # and traversal-shaped inputs before any read or temporary-file creation.
  profile_basename=${profile_path#${TARGET_ROOT}${DIR_APPARMOR}/}
  case "$profile_basename" in
    ''|*/*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+-]*)
      installer_fatal "refusing non-direct AppArmor profile source path: ${profile_path}"
      ;;
  esac
  case "$profile_name" in
    ''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+-]*)
      installer_fatal "invalid AppArmor profile label for flag normalization: ${profile_name:-unset}"
      ;;
  esac
  case "$unsafe_flag_policy" in
    reject|strip-unconfined) ;;
    *) installer_fatal "invalid AppArmor unsafe-flag policy for ${profile_name}: ${unsafe_flag_policy:-unset}" ;;
  esac
  [ -f "$profile_path" ] ||
    installer_fatal "required AppArmor profile source is missing: ${profile_path}"
  [ ! -L "$profile_path" ] ||
    installer_fatal "refusing symlinked AppArmor profile source: ${profile_path}"
  profile_size=$(wc -c <"$profile_path") ||
    installer_fatal "cannot size AppArmor profile source: ${profile_path}"
  case "$profile_size" in
    ''|*[!0-9]*) installer_fatal "invalid AppArmor profile size: ${profile_path}" ;;
  esac
  [ "$profile_size" -le 1048576 ] ||
    installer_fatal "AppArmor profile source exceeds 1048576 bytes: ${profile_path}"

  profile_tmp=$(mktemp "${profile_path}.flags.XXXXXX") ||
    installer_fatal "cannot create AppArmor profile flag workspace: ${profile_path}"
  chmod 0600 "$profile_tmp" || {
    rm -f -- "$profile_tmp"
    installer_fatal "cannot secure AppArmor profile flag workspace: ${profile_path}"
  }

  if ! awk \
    -v expected_profile="$profile_name" \
    -v unsafe_flag_policy="$unsafe_flag_policy" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    function add_flag(value) {
      if (!(value in seen)) {
        seen[value] = 1
        flags[++flag_count] = value
      }
    }
    $1 == "profile" && $2 == expected_profile {
      matches++
      if (matches != 1 || $0 !~ /[{][[:space:]]*$/) {
        exit 40
      }

      line = $0
      if (match(line, /flags=[(][^)]*[)]/)) {
        existing = substr(line, RSTART + 7, RLENGTH - 8)
        field_count = split(existing, fields, ",")
        for (field_index = 1; field_index <= field_count; field_index++) {
          flag = trim(fields[field_index])
          if (flag !~ /^[A-Za-z0-9_.+-]+$/) {
            exit 41
          }
          if (flag == "unconfined" || flag == "default_allow") {
            if (flag == "unconfined" &&
                unsafe_flag_policy == "strip-unconfined") {
              continue
            }
            exit 43
          }
          add_flag(flag)
        }
        add_flag("attach_disconnected")
        add_flag("mediate_deleted")
        rebuilt = flags[1]
        for (flag_index = 2; flag_index <= flag_count; flag_index++) {
          rebuilt = rebuilt ", " flags[flag_index]
        }
        line = substr(line, 1, RSTART - 1) "flags=(" rebuilt ")" \
          substr(line, RSTART + RLENGTH)
      } else {
        sub(/[[:space:]]*[{][[:space:]]*$/, \
          " flags=(attach_disconnected, mediate_deleted) {", line)
      }
      print line
      next
    }
    { print }
    END {
      if (matches != 1) {
        exit 42
      }
    }
  ' "$profile_path" >"$profile_tmp"; then
    rm -f -- "$profile_tmp"
    installer_fatal "cannot normalize disconnected-path flags for AppArmor profile: ${profile_name}"
  fi

  chmod 0644 "$profile_tmp" || {
    rm -f -- "$profile_tmp"
    installer_fatal "cannot set AppArmor profile mode before publishing: ${profile_name}"
  }
  mv -f -- "$profile_tmp" "$profile_path" || {
    rm -f -- "$profile_tmp"
    installer_fatal "cannot atomically publish disconnected-path flags for AppArmor profile: ${profile_name}"
  }
}

apparmor_disable_superseded_edge_profile() {
  # Keep the distribution conffile, but give the vendor's confined profile the
  # sole Edge attachment. Both the boot loader and aa-logprof skip disable/.
  edge_profile_dir=${TARGET_ROOT}${DIR_APPARMOR}
  [ -f "$edge_profile_dir/microsoft-edge-stable" ] &&
    [ ! -L "$edge_profile_dir/microsoft-edge-stable" ] ||
    installer_fatal "managed Edge AppArmor profile must be a regular non-symlink file"
  if [ ! -e "$edge_profile_dir/msedge" ] && [ ! -L "$edge_profile_dir/msedge" ]; then
    return 0
  fi
  [ -f "$edge_profile_dir/msedge" ] && [ ! -L "$edge_profile_dir/msedge" ] ||
    installer_fatal "distribution Edge AppArmor profile must be a regular non-symlink file"
  for edge_profile in microsoft-edge-stable msedge; do
    edge_profile_size=$(wc -c <"$edge_profile_dir/$edge_profile") ||
      installer_fatal "cannot size Edge AppArmor profile: $edge_profile"
    [ "$edge_profile_size" -le 1048576 ] ||
      installer_fatal "Edge AppArmor profile exceeds 1048576 bytes: $edge_profile"
    grep -Eq "^[[:space:]]*profile[[:space:]]+${edge_profile}[[:space:]]+__INSTALLER_PATH_DIR_OPT__/microsoft/msedge/msedge[[:space:]]" \
      "$edge_profile_dir/$edge_profile" ||
      installer_fatal "unexpected Edge AppArmor attachment: $edge_profile"
  done
  if [ -e "$edge_profile_dir/disable" ] || [ -L "$edge_profile_dir/disable" ]; then
    [ -d "$edge_profile_dir/disable" ] && [ ! -L "$edge_profile_dir/disable" ] ||
      installer_fatal "AppArmor disable directory must be a real directory"
  else
    install -d -m 0755 "$edge_profile_dir/disable" ||
      installer_fatal "cannot create AppArmor disable directory"
  fi
  edge_disable_link="$edge_profile_dir/disable/msedge"
  if [ -e "$edge_disable_link" ] || [ -L "$edge_disable_link" ]; then
    [ -L "$edge_disable_link" ] ||
      installer_fatal "distribution Edge AppArmor disable entry must be a symlink"
    case "$(readlink "$edge_disable_link")" in
      ../msedge|__INSTALLER_PATH_DIR_ETC__/apparmor.d/msedge) ;;
      *) installer_fatal "unexpected distribution Edge AppArmor disable link" ;;
    esac
  else
    ln -s ../msedge "$edge_disable_link" ||
      installer_fatal "cannot disable superseded distribution Edge AppArmor profile"
  fi
}

stage_target_system_apparmor_profiles() {
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/fonts.d/labwc-terminal-fonts)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/fonts.d/labwc-terminal-fonts" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/common/abstractions/wrapper-terminal)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/wrapper-terminal" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/common/abstractions/wrapper-base)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/wrapper-base" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/common/abstractions/wrapper-perl)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/wrapper-perl" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/common/abstractions/crun-runtime)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/crun-runtime" \
    0644
  if installer_snapshots_enabled; then
    stage_target_asset \
      "$(installer_repo_file_value hooks/target/etc/apparmor.d/common/abstractions/timeshift-runtime)" \
      "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/timeshift-runtime" \
      0644
  fi

  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/common/abstractions/wrapper-python)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/wrapper-python" \
    0644

  for apparmor_profile in $(apparmor_managed_system_profile_files); do
    if [ "$apparmor_profile" = app-veth ]; then
      render_target_asset_with_placeholder_map \
        "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/app-veth.tmpl)" \
        __INSTALLER_PATH_DIR_ETC__/apparmor.d/app-veth 0644 app_veth_identity_placeholder_map
      continue
    fi
    stage_target_asset \
      "$(installer_repo_asset_path DIR_TARGET_AA "${apparmor_profile}")" \
      "__INSTALLER_PATH_DIR_ETC__/apparmor.d/${apparmor_profile}" \
      0644
  done
}

apparmor_document_media_placeholder_map() {
  media_account=${ACCOUNT_USERNAME:-}
  case "$media_account" in
    ''|[!a-z_]*|*[!a-z0-9_-]*|root|nobody|nogroup)
      installer_fatal "invalid primary account for AppArmor document media policy"; return 1 ;;
  esac
  [ "${#media_account}" -le 32 ] || {
    installer_fatal "AppArmor document media account exceeds 32 characters"; return 1
  }
  printf 'ACCOUNT_USERNAME=%s\n' "$media_account"
}

stage_target_desktop_apparmor_profiles() {
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/llama-whisper-coordination)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/llama-whisper-coordination" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/devops-toolchain-data)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/devops-toolchain-data" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/user-documents)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/user-documents" \
    0644
  render_target_asset_with_placeholder_map \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/local/abstractions/desktop-user-media.tmpl)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/local/abstractions/desktop-user-media" \
    0644 \
    apparmor_document_media_placeholder_map
  render_target_asset_with_placeholder_map \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/local/abstractions/codex-user-media.tmpl)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/local/abstractions/codex-user-media" \
    0644 \
    apparmor_document_media_placeholder_map
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/document-runtime)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/document-runtime" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/session-client)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/session-client" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/wrapper-desktop)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/wrapper-desktop" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/wrapper-gui)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/wrapper-gui" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/wrapper-wayland)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/wrapper-wayland" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/audio.d/no-raw-audio)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/audio.d/no-raw-audio" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/pipewire-audio)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/pipewire-audio" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/common/abstractions/bwrap-common)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/bwrap-common" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/tor-browser-runtime)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/tor-browser-runtime" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/bwrap-compat-preparation)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/bwrap-compat-preparation" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/bwrap-desktop-runtime)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/bwrap-desktop-runtime" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/devops-toolchain-runtime)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/devops-toolchain-runtime" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/codex-runtime)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/codex-runtime" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/electron-runtime)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/electron-runtime" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/electron-application)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/electron-application" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/webkit-runtime)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/webkit-runtime" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/desktop-graphics)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/desktop-graphics" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/native-gpu-selection)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/native-gpu-selection" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/desktop-runtime)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/desktop-runtime" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/app-config)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/app-config" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/desktop-application)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/desktop-application" \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/qbittorrent-runtime)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/qbittorrent-runtime" \
    0644

  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/common/abstractions/workflow-auth)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/workflow-auth" \
    0644

  for apparmor_profile in $(apparmor_managed_desktop_profile_files); do
    stage_target_asset \
      "$(installer_repo_asset_path DIR_TARGET_AA "${apparmor_profile}")" \
      "__INSTALLER_PATH_DIR_ETC__/apparmor.d/${apparmor_profile}" \
      0644
  done

  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/local/desktop-application)" \
    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/local/desktop-application" \
    0644
  if security_nvidia_acceleration_enabled; then
    stage_target_asset \
      "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/local/desktop-native-nvidia)" \
      "__INSTALLER_PATH_DIR_ETC__/apparmor.d/local/desktop-native-nvidia" \
      0644
    stage_target_asset \
      "$(installer_hardware_asset_path gpu nvidia etc/apparmor.d/local/desktop-graphics)" \
      "__INSTALLER_PATH_DIR_ETC__/apparmor.d/local/desktop-graphics" \
      0644
    stage_target_asset \
      "$(installer_hardware_asset_path gpu nvidia etc/apparmor.d/local/desktop-wrappers-nvidia)" \
      "__INSTALLER_PATH_DIR_ETC__/apparmor.d/local/desktop-wrappers-nvidia" \
      0644
  else
    rm -f \
      ${TARGET_ROOT}${DIR_APPARMOR}/local/desktop-graphics \
      ${TARGET_ROOT}${DIR_APPARMOR}/local/desktop-wrappers-nvidia \
      ${TARGET_ROOT}${DIR_APPARMOR}/local/desktop-native-nvidia
  fi
  for apparmor_local_include in $(apparmor_managed_local_include_files); do
    stage_target_asset \
      "$(installer_repo_asset_path DIR_TARGET_AA_LOCAL "${apparmor_local_include}")" \
      "__INSTALLER_PATH_DIR_ETC__/apparmor.d/local/${apparmor_local_include}" \
      0644
  done
	for apparmor_local_include in $(apparmor_support_local_include_files); do
	  stage_target_asset \
	    "$(installer_repo_asset_path DIR_TARGET_AA_LOCAL "${apparmor_local_include}")" \
	    "__INSTALLER_PATH_DIR_ETC__/apparmor.d/local/${apparmor_local_include}" \
	    0644
	done
  # Chromium receives wlroots' anonymous/deleted shared-memory descriptors.
  # A local include cannot add attachment flags to the package outer profile.
  if [ -e ${TARGET_ROOT}${DIR_APPARMOR}/chromium ] || [ -L ${TARGET_ROOT}${DIR_APPARMOR}/chromium ]; then
    apparmor_require_disconnected_profile_flags \
      "${TARGET_ROOT}${DIR_APPARMOR}/chromium" \
      chromium \
      strip-unconfined
  fi
	# Edge's package-owned outer profile ships unconfined. Strip only that known
	# vendor flag, then attach nameless renderer paths and keep deleted objects
	# mediated by policy.
	if [ -e ${TARGET_ROOT}${DIR_APPARMOR}/microsoft-edge-stable ] || [ -L ${TARGET_ROOT}${DIR_APPARMOR}/microsoft-edge-stable ]; then
	  apparmor_require_disconnected_profile_flags \
	    "${TARGET_ROOT}${DIR_APPARMOR}/microsoft-edge-stable" \
	    microsoft-edge-stable \
	    strip-unconfined
	  apparmor_disable_superseded_edge_profile
	fi
	# Mullvad Browser's package-owned outer profile ships unconfined while the
	# tracked local include provides the managed policy. Strip only that known
	# vendor flag, then attach and mediate nameless disconnected VA-API paths.
	if [ -e ${TARGET_ROOT}${DIR_APPARMOR}/mullvad-browser ] || [ -L ${TARGET_ROOT}${DIR_APPARMOR}/mullvad-browser ]; then
	  apparmor_require_disconnected_profile_flags \
	    "${TARGET_ROOT}${DIR_APPARMOR}/mullvad-browser" \
	    mullvad-browser \
	    strip-unconfined
	fi
  # The verified VPN vendor profile also needs deleted-FD mediation. Its
  # local include supplies the confined GUI policy before this flag change.
  if [ -e ${TARGET_ROOT}${DIR_APPARMOR}/mullvad ] || [ -L ${TARGET_ROOT}${DIR_APPARMOR}/mullvad ]; then
    apparmor_require_disconnected_profile_flags \
      "${TARGET_ROOT}${DIR_APPARMOR}/mullvad" mullvad strip-unconfined
  fi
  # Debian's package attachment can also be entered directly, outside the
  # managed code label. Give both entry points the same disconnected-FD rules.
  if [ -e ${TARGET_ROOT}${DIR_APPARMOR}/vscode ] || [ -L ${TARGET_ROOT}${DIR_APPARMOR}/vscode ]; then
    apparmor_require_disconnected_profile_flags \
      "${TARGET_ROOT}${DIR_APPARMOR}/vscode" vscode strip-unconfined
  fi
	# The package's __INSTALLER_PATH_DIR_USR_BIN__/vivaldi-stable entry is an absolute symlink to this
  # wrapper. Test the direct target-root path so the installer never resolves
  # the symlink against its own root and silently skips the confined profiles.
  if [ -x ${TARGET_ROOT}${DIR_OPT}/vivaldi/vivaldi ]; then
    for apparmor_profile in vivaldi-stable vivaldi-bin; do
      stage_target_asset \
        "$(installer_repo_asset_path DIR_TARGET_AA "${apparmor_profile}")" \
        "__INSTALLER_PATH_DIR_ETC__/apparmor.d/${apparmor_profile}" \
        0644
      apparmor_require_disconnected_profile_flags \
        "${TARGET_ROOT}${DIR_APPARMOR}/${apparmor_profile}" \
        "$apparmor_profile"
    done
  fi
  for apparmor_local_include in $(apparmor_compat_desktop_local_include_files); do
    stage_target_asset \
      "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/local/desktop-application)" \
      "__INSTALLER_PATH_DIR_ETC__/apparmor.d/local/${apparmor_local_include}" \
      0644
  done

}

nftables_default_placeholder_map() {
  write_shell_config_var NFTABLES_LOG_LEVEL "${NFTABLES_LOG_LEVEL:-none}"
  write_shell_config_var NFT_PROFILE "${NFTABLES_DEFAULT_REQUESTED_PROFILE:-default}"
  write_shell_config_var NFT_SERVICES "${NFTABLES_DEFAULT_SELECTED_SERVICES_CSV:-none}"
  write_shell_config_var NFT_POLICY_PROFILE "__INSTALLER_PATH_DIR_ETC__/nftables/profiles/${NFTABLES_DEFAULT_SELECTED_PROFILE:-default}.yml"
  write_shell_config_var NFT_POLICY_RESOLVED_PROFILE "${NFTABLES_DEFAULT_SELECTED_PROFILE:-default}"
  write_shell_config_var NFT_POLICY_DEFAULT_PROFILE __INSTALLER_PATH_DIR_ETC__/nftables/profiles/default.yml
  write_shell_config_var NFT_POLICY_SERVICE_OVERLAYS "${NFTABLES_DEFAULT_SERVICE_OVERLAYS:-}"
  write_shell_config_var NFT_POLICY_RUNTIME_CIDRS "${NFTABLES_DEFAULT_RUNTIME_CIDRS:-}"
  write_shell_config_var NFT_POLICY_GENERATOR __INSTALLER_PATH_DIR_USR_LOCAL__/sbin/nft-policy-generate
}

clear_target_nftables_assets() {
  stage_target_nftables_mullvad_lan_policy ""
  if [ -r ${TARGET_ROOT}${DIR_ETC}/nftables.conf ] &&
     grep -E -q 'Managed by (unattended-installer|nft-policy-generate[.]py)' ${TARGET_ROOT}${DIR_ETC}/nftables.conf; then
    rm -f ${TARGET_ROOT}${DIR_ETC}/nftables.conf
  fi

  rm -f \
    ${TARGET_ROOT}${DIR_ETC}/nftables/policy.conf \
    ${TARGET_ROOT}${DIR_USR_LOCAL_SBIN}/nft-policy-generate \
    ${TARGET_ROOT}${DIR_SYSTEMD_SYSTEM_NFTABLES_DROPIN}/override.conf \
    ${TARGET_ROOT}${DIR_ETC}/nftables/README.md \
    ${TARGET_ROOT}${DIR_ETC}/nftables/profiles/baseline.yml \
    ${TARGET_ROOT}${DIR_ETC}/nftables/profiles/default.yml \
    ${TARGET_ROOT}${DIR_ETC}/nftables/profiles/desktop.yml \
    ${TARGET_ROOT}${DIR_ETC}/nftables/profiles/server.yml \
    ${TARGET_ROOT}${DIR_ETC}/nftables.d/00-defines.nft \
    ${TARGET_ROOT}${DIR_ETC}/nftables.d/10-base.nft \
    ${TARGET_ROOT}${DIR_ETC}/nftables.d/20-filter.nft \
    ${TARGET_ROOT}${DIR_ETC}/nftables.d/30-nat.nft \
    ${TARGET_ROOT}${DIR_ETC}/nftables.d/90-local.nft

  for service_asset in $(nftables_service_assets); do
    rm -f "${TARGET_ROOT}${DIR_ETC}/nftables/services/${service_asset}.yml"
  done

  if command -v unstage_target_systemd_unit_enabled >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
    unstage_target_systemd_unit_enabled nftables.service system
  fi
  rmdir ${TARGET_ROOT}${DIR_SYSTEMD_SYSTEM_NFTABLES_DROPIN} 2>__INSTALLER_PATH_DIR_DEV__/null || true
  rmdir ${TARGET_ROOT}${DIR_ETC}/nftables/services ${TARGET_ROOT}${DIR_ETC}/nftables/profiles ${TARGET_ROOT}${DIR_ETC}/nftables ${TARGET_ROOT}${DIR_ETC}/nftables.d 2>__INSTALLER_PATH_DIR_DEV__/null || true
}

write_target_nftables_default_config() {
  selected_profile=$1
  requested_profile=$2
  selected_services=$3
  runtime_cidrs=${4:-}

  old_ifs=$IFS
  IFS=' '
  # shellcheck disable=SC2086
  set -- $selected_services
  IFS=$old_ifs
  NFTABLES_DEFAULT_SELECTED_PROFILE=$selected_profile
  NFTABLES_DEFAULT_REQUESTED_PROFILE=$requested_profile
  NFTABLES_DEFAULT_SELECTED_SERVICES_CSV=$(printf '%s' "$selected_services" | tr ' ' ',')
  NFTABLES_DEFAULT_SERVICE_OVERLAYS=$(nftables_service_overlay_paths "$@")
  NFTABLES_DEFAULT_RUNTIME_CIDRS=$runtime_cidrs

  render_target_asset_with_placeholder_map \
    "$(installer_repo_file_value hooks/target/etc/nftables/desktop/policy.conf.tmpl)" \
    __INSTALLER_PATH_DIR_ETC__/nftables/policy.conf \
    0644 \
    nftables_default_placeholder_map

  unset \
    NFTABLES_DEFAULT_SELECTED_PROFILE \
    NFTABLES_DEFAULT_REQUESTED_PROFILE \
    NFTABLES_DEFAULT_SELECTED_SERVICES_CSV \
    NFTABLES_DEFAULT_SERVICE_OVERLAYS \
    NFTABLES_DEFAULT_RUNTIME_CIDRS
}

configure_target_nftables() {
  installer_operation_context_repo scripts/late/security.sh 1442 configure_target_nftables
  requested_profile=$(late_command_nftables_requested_profile)
  selected_profile=$(late_command_nftables_profile "$requested_profile")
  installer_info "nftables profile selection: raw=${NFT_PROFILE:-default} normalized=${requested_profile} selected=${selected_profile}"

  if [ "$selected_profile" = none ]; then
    if [ "${NFS_SERVER_ENABLE:-false}" = true ] || [ "${NFS_CLIENT_ENABLE:-false}" = true ]; then
      installer_fatal "enabled NFS roles require a managed nftables profile"
    fi
    installer_info "NFT_PROFILE=none; skipping nftables profile, service overlay, and unit staging"
    clear_target_nftables_assets
    return 0
  fi

  if command -v target_prepare_managed_network_handoff_state >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
    target_prepare_managed_network_handoff_state
  elif command -v target_prepare_managed_network_ipv6_handoff >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
    target_prepare_managed_network_ipv6_handoff
  fi

  selected_services=$(late_command_nftables_effective_services)
  runtime_cidrs=$(nftables_runtime_cidrs_env_value)

  install -d -m 0755 \
    ${TARGET_ROOT}${DIR_ETC}/default \
    ${TARGET_ROOT}${DIR_ETC}/nftables \
    ${TARGET_ROOT}${DIR_ETC}/nftables/profiles \
    ${TARGET_ROOT}${DIR_ETC}/nftables/services \
    ${TARGET_ROOT}${DIR_ETC}/nftables.d \
    ${TARGET_ROOT}${DIR_ETC}/nftables.local.d \
    ${TARGET_ROOT}${DIR_SYSTEMD_SYSTEM_NFTABLES_DROPIN} \
    ${TARGET_ROOT}${DIR_USR_LOCAL_SBIN}

  rm -f \
    ${TARGET_ROOT}${DIR_ETC}/nftables/profiles/baseline.yml \
    ${TARGET_ROOT}${DIR_ETC}/nftables/profiles/default.yml \
    ${TARGET_ROOT}${DIR_ETC}/nftables/profiles/desktop.yml \
    ${TARGET_ROOT}${DIR_ETC}/nftables/profiles/server.yml \
    ${TARGET_ROOT}${DIR_ETC}/nftables.d/00-defines.nft \
    ${TARGET_ROOT}${DIR_ETC}/nftables.d/10-base.nft \
    ${TARGET_ROOT}${DIR_ETC}/nftables.d/20-filter.nft \
    ${TARGET_ROOT}${DIR_ETC}/nftables.d/30-nat.nft \
    ${TARGET_ROOT}${DIR_ETC}/nftables.d/90-local.nft
  for service_asset in $(nftables_service_assets); do
    rm -f "${TARGET_ROOT}${DIR_ETC}/nftables/services/${service_asset}.yml"
  done

  stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/sbin/desktop/nft-policy-generate.py)" "__INSTALLER_PATH_DIR_USR_LOCAL__/sbin/nft-policy-generate" 0755
  render_target_asset_with_placeholder_map "$(installer_repo_file_value hooks/target/etc/nftables/desktop/README.md.tmpl)" "__INSTALLER_PATH_DIR_ETC__/nftables/README.md" 0644 nftables_interface_placeholder_map
  stage_target_helper_doc nft-policy-generate.md nft-policy-generate.md
  stage_target_nftables_profile_assets
  render_target_asset_with_placeholder_map \
    "$(installer_repo_asset_path DIR_TARGET_NFTABLES_PROFILES "${selected_profile}.yml")" \
    "__INSTALLER_PATH_DIR_ETC__/nftables/profiles/default.yml" \
    0644 \
    nftables_app_veth_profile_placeholder_map
  stage_target_nftables_all_service_assets
  write_target_nftables_default_config "$selected_profile" "${requested_profile:-default}" "$selected_services" "$runtime_cidrs"
  # These are administrator state, not disposable generated policy. Seed them
  # once only. A suspicious existing path fails instead of being silently erased.
  # Repository membership and installed paths have separate owners. In
  # particular, the desktop policy source lives below its physical role root.
  # Never reconstruct a source path by stripping the target path prefix.
  installer_operation_context_repo scripts/late/security.sh 1505 seed_persistent_firewall_state
  while IFS='|' read -r local_state_selector local_state; do
    if [ -e "${TARGET_ROOT}${local_state}" ] || [ -L "${TARGET_ROOT}${local_state}" ]; then
      [ -f "${TARGET_ROOT}${local_state}" ] && [ ! -L "${TARGET_ROOT}${local_state}" ] ||
        installer_fatal "unsafe persistent firewall state: $local_state"
      case "$(installer_metadata_value "${TARGET_ROOT}${local_state}" uid_gid_mode_links)" in
        0:0:600:1|0:0:640:1|0:0:644:1) ;;
        *) installer_fatal "unsafe persistent firewall state metadata: $local_state" ;;
      esac
    else
      local_state_source=$(installer_repo_file_value "$local_state_selector") || return "$?"
      stage_target_asset "$local_state_source" "$local_state" 0644 || return "$?"
    fi
  done <<'EOF'
hooks/target/etc/nftables/desktop/firewall-security.rules|__INSTALLER_PATH_DIR_ETC__/nftables/firewall-security.rules
hooks/target/etc/nftables.d/95-firewall-security.nft|__INSTALLER_PATH_DIR_ETC__/nftables.d/95-firewall-security.nft
EOF

  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/systemd/desktop/system/nftables.service.d/override.conf)" \
    "__INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_NFTABLES_DROPIN__/override.conf" \
    0644

  require_in_target "nftables policy generation"
  set -- env "NFTABLES_LOG_LEVEL=${NFTABLES_LOG_LEVEL:-none}" __INSTALLER_PATH_DIR_USR_LOCAL__/sbin/nft-policy-generate \
    --profile "__INSTALLER_PATH_DIR_ETC__/nftables/profiles/${selected_profile}.yml"
  for service_asset in $selected_services; do
    set -- "$@" --overlay "__INSTALLER_PATH_DIR_ETC__/nftables/services/${service_asset}.yml"
  done
  for runtime_pair in $runtime_cidrs; do
    set -- "$@" --add-cidr "$runtime_pair"
  done
  set -- "$@" --write --summary
  run_in_target "generate ${requested_profile} nftables policy (${selected_profile} profile)" "$@"

  stage_target_nftables_mullvad_lan_policy "$selected_services"
  stage_target_systemd_unit_enabled nftables.service system
}

security_mask_target_systemd_unit_if_available() {
  unit=$1
  scope=${2:-system}

  validate_systemd_unit_name "$unit"
  base_dir=$(target_systemd_scope_base_dir "$scope")
  mask_path="${TARGET_ROOT}${base_dir}/${unit}"

  if [ -L "$mask_path" ] && [ "$(readlink "$mask_path")" = __INSTALLER_PATH_DIR_DEV__/null ]; then
    return 0
  fi

  unit_path=$(target_systemd_unit_path "$unit" "$scope" 2>__INSTALLER_PATH_DIR_DEV__/null || true)
  if [ -z "$unit_path" ]; then
    installer_warn "target ${scope} unit is unavailable; skipping security mask: ${unit}"
    return 0
  fi

  unstage_target_systemd_unit_enabled "$unit" "$scope"
  install -d -m 0755 "${TARGET_ROOT}${base_dir}"
  ln -sfn __INSTALLER_PATH_DIR_DEV__/null "$mask_path"
  [ -L "$mask_path" ] &&
    [ "$(readlink "$mask_path")" = __INSTALLER_PATH_DIR_DEV__/null ] ||
    installer_fatal "failed to mask target ${scope} unit: ${unit}"
}

configure_target_fail2ban() {
  installer_operation_context_repo scripts/late/security.sh 1571 configure_target_fail2ban
  runtime_apply_ssh_from_classes
  # Current roles expose SSH according to profile policy. There is no web
  # service class: querying a retired selector aborts the shared class parser.
  fail2ban_has_jails=$SSH_SERVER_ENABLED
  install -d -m 0755 \
    ${TARGET_ROOT}${DIR_ETC}/fail2ban \
    ${TARGET_ROOT}${DIR_ETC}/fail2ban/action.d \
    ${TARGET_ROOT}${DIR_ETC}/fail2ban/fail2ban.d \
    ${TARGET_ROOT}${DIR_ETC}/fail2ban/filter.d \
    ${TARGET_ROOT}${DIR_ETC}/fail2ban/jail.d \
    ${TARGET_ROOT}${DIR_ETC}/logrotate.d \
    ${TARGET_ROOT}${DIR_SYSTEMD_SYSTEM_FAIL2BAN_DROPIN} \
    ${TARGET_ROOT}${DIR_ETC}/tmpfiles.d

  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/fail2ban/fail2ban.local.tmpl)" \
    __INSTALLER_PATH_DIR_ETC__/fail2ban/fail2ban.local \
    0644
  for fail2ban_managed_asset in \
    jail.local \
    action.d/nftables.local \
    fail2ban.d/10-security.local \
    filter.d/sshd.local \
    paths-overrides.local; do
    stage_target_asset \
      "$(installer_repo_asset_path DIR_TARGET_FAIL2BAN "$fail2ban_managed_asset")" \
      "__INSTALLER_PATH_DIR_ETC__/fail2ban/$fail2ban_managed_asset" \
      0644
  done
  # Create the canonical managed auth sink even before OpenSSH is installed.
  # Rsyslog reads INFO auth events with their saved trusted journal metadata.
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/tmpfiles.d/common/59-log-layout.conf.tmpl)" \
    __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/59-log-layout.conf \
    0644
  render_target_asset_with_placeholder_map \
    "$(installer_repo_file_value hooks/target/etc/fail2ban/jail.d/10-sshd.local.tmpl)" \
    __INSTALLER_PATH_DIR_ETC__/fail2ban/jail.d/10-sshd.local \
    0644 \
    fail2ban_jail_placeholder_map
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/systemd/common/system/fail2ban.service.d/40-runtime.conf)" \
    __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_FAIL2BAN_DROPIN__/40-runtime.conf \
    0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/tmpfiles.d/common/62-fail2ban.conf.tmpl)" \
    __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/62-fail2ban.conf \
    0644
  normalize_target_tmpfiles_directory_policy \
    __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/62-fail2ban.conf \
    "Fail2ban managed state"
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/etc/logrotate.d/fail2ban.tmpl)" \
    __INSTALLER_PATH_DIR_ETC__/logrotate.d/fail2ban \
    0644

  run_in_target \
    "create Fail2ban managed state" \
    __INSTALLER_PATH_DIR_USR_BIN__/systemd-tmpfiles \
    --create \
    __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/59-log-layout.conf \
    __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/62-fail2ban.conf
  if [ "$fail2ban_has_jails" = true ]; then
    stage_target_systemd_unit_enabled fail2ban.service system
  else
    # Package installation can create enablement links. Remove them and mask
    # only this target unit offline when no managed service has an active jail.
    security_mask_target_systemd_unit_if_available fail2ban.service system
  fi
}

app_veth_dns_placeholder_map() (
  app_veth_identity_map=$(app_veth_identity_placeholder_map) || return "$?"
  # Export only public DNS policy, never the full installer environment. Pass
  # values as data rather than awk arguments, so backslashes are not expanded.
  SYSTEM_NAMESERVERS_IPV4_DNS1=${SYSTEM_NAMESERVERS_IPV4_DNS1:-}
  SYSTEM_NAMESERVERS_IPV6_DNS1=${SYSTEM_NAMESERVERS_IPV6_DNS1:-}
  SYSTEM_NAMESERVERS_HOSTNAME_DNS1=${SYSTEM_NAMESERVERS_HOSTNAME_DNS1:-}
  SYSTEM_NAMESERVERS_IPV4_DNS2=${SYSTEM_NAMESERVERS_IPV4_DNS2:-}
  SYSTEM_NAMESERVERS_IPV6_DNS2=${SYSTEM_NAMESERVERS_IPV6_DNS2:-}
  SYSTEM_NAMESERVERS_HOSTNAME_DNS2=${SYSTEM_NAMESERVERS_HOSTNAME_DNS2:-}
  SYSTEM_NAMESERVERS_IPV4_DNS3=${SYSTEM_NAMESERVERS_IPV4_DNS3:-}
  SYSTEM_NAMESERVERS_IPV6_DNS3=${SYSTEM_NAMESERVERS_IPV6_DNS3:-}
  SYSTEM_NAMESERVERS_HOSTNAME_DNS3=${SYSTEM_NAMESERVERS_HOSTNAME_DNS3:-}
  SYSTEM_DNS_UPSTREAM_TLS_CA_CUSTOM_ENABLE=${SYSTEM_DNS_UPSTREAM_TLS_CA_CUSTOM_ENABLE:-false}
  SYSTEM_NAMESERVERS_TLS_SAN_CUSTOM=${SYSTEM_NAMESERVERS_TLS_SAN_CUSTOM:-}
  SYSTEM_NAMESERVERS_PORT=${SYSTEM_NAMESERVERS_PORT:-}
  SYSTEM_DNS_CACHE_SIZE=${SYSTEM_DNS_CACHE_SIZE:-}
  SYSTEM_DNS_CACHE_MIN_TTL=${SYSTEM_DNS_CACHE_MIN_TTL:-}
  export SYSTEM_NAMESERVERS_IPV4_DNS1 SYSTEM_NAMESERVERS_IPV6_DNS1 SYSTEM_NAMESERVERS_HOSTNAME_DNS1
  export SYSTEM_NAMESERVERS_IPV4_DNS2 SYSTEM_NAMESERVERS_IPV6_DNS2 SYSTEM_NAMESERVERS_HOSTNAME_DNS2
  export SYSTEM_NAMESERVERS_IPV4_DNS3 SYSTEM_NAMESERVERS_IPV6_DNS3 SYSTEM_NAMESERVERS_HOSTNAME_DNS3
  export SYSTEM_DNS_UPSTREAM_TLS_CA_CUSTOM_ENABLE SYSTEM_NAMESERVERS_TLS_SAN_CUSTOM
  export SYSTEM_NAMESERVERS_PORT
  export SYSTEM_DNS_CACHE_SIZE SYSTEM_DNS_CACHE_MIN_TTL
  app_veth_dns_map=$(LC_ALL=C awk '
    function fail(name) {
      print "fatal: invalid " name " in system DNS policy" > "__INSTALLER_PATH_DIR_DEV__/stderr"
      exit 1
    }
    function field(name, value) {
      value = ENVIRON[name]
      if (length(value) > 253 || value ~ /[^A-Za-z0-9.:-]/) fail(name)
      return value
    }
    function ipv4(value, parts, count, j) {
      count = split(value, parts, /\./)
      if (count != 4) return 0
      for (j = 1; j <= count; j++)
        if (parts[j] !~ /^[0-9]+$/ || length(parts[j]) > 3 ||
            parts[j] + 0 > 255 || (length(parts[j]) > 1 && parts[j] ~ /^0/)) return 0
      return 1
    }
    function hexgroups(value, groups, count, j) {
      if (value == "") return 0
      count = split(value, groups, /:/)
      for (j = 1; j <= count; j++)
        if (groups[j] !~ /^[0-9A-Fa-f]+$/ || length(groups[j]) > 4) return -1
      return count
    }
    function ipv6(value, position, left, right) {
      if (value !~ /^[0-9A-Fa-f:]+$/) return 0
      position = index(value, "::")
      if (!position) return hexgroups(value) == 8
      left = hexgroups(substr(value, 1, position - 1))
      right = hexgroups(substr(value, position + 2))
      return left >= 0 && right >= 0 && left + right < 8
    }
    function hostname(value, labels, count, j) {
      if (length(value) > 253) return 0
      count = split(value, labels, /\./)
      for (j = 1; j <= count; j++)
        if (length(labels[j]) > 63 || labels[j] !~ /^[A-Za-z0-9][A-Za-z0-9-]*$/ ||
            labels[j] ~ /-$/) return 0
      return count > 0
    }
    function integer(name, minimum, maximum, value) {
      value = ENVIRON[name]
      if (value !~ /^[0-9]+$/ || length(value) > 7 || value + 0 < minimum || value + 0 > maximum)
        fail(name)
      return value + 0
    }
    BEGIN {
      custom_ca = ENVIRON["SYSTEM_DNS_UPSTREAM_TLS_CA_CUSTOM_ENABLE"]
      if (custom_ca != "true" && custom_ca != "false") fail("SYSTEM_DNS_UPSTREAM_TLS_CA_CUSTOM_ENABLE")
      ca_file = "__INSTALLER_PATH_DIR_ETC__/ssl/certs/ca-certificates.crt"
      custom_name = field("SYSTEM_NAMESERVERS_TLS_SAN_CUSTOM")
      if (custom_name != "" && !hostname(custom_name)) fail("SYSTEM_NAMESERVERS_TLS_SAN_CUSTOM")
      if (custom_ca == "true") {
        ca_file = "__INSTALLER_PATH_DIR_ETC__/stubby/ca/upstream-custom.pem"
      }
      port = ENVIRON["SYSTEM_NAMESERVERS_PORT"]
      if (port !~ /^[0-9]+$/ || length(port) > 5 || port + 0 < 1 || port + 0 > 65535)
        fail("SYSTEM_NAMESERVERS_PORT")
      port += 0
      cache_size = integer("SYSTEM_DNS_CACHE_SIZE", 1, 1000000)
      cache_min_ttl = integer("SYSTEM_DNS_CACHE_MIN_TTL", 0, 3600)
      upstreams = "["
      upstreams_json = "["
      ipv4_allowlist = "["
      ipv6_allowlist = "["
      for (i = 1; i <= 3; i++) {
        key4 = "SYSTEM_NAMESERVERS_IPV4_DNS" i
        key6 = "SYSTEM_NAMESERVERS_IPV6_DNS" i
        keyname = "SYSTEM_NAMESERVERS_HOSTNAME_DNS" i
        address4 = field(key4)
        address6 = field(key6)
        name = field(keyname)
        if (i > 1 && name == "" && address4 == "" && address6 == "") continue
        if (custom_ca == "true" && custom_name != "") name = custom_name
        if (name == "" || !hostname(name)) fail(keyname)
        if (address4 == "" && address6 == "") fail("SYSTEM_NAMESERVERS addresses for DNS" i)
        for (family = 4; family <= 6; family += 2) {
          address = family == 4 ? address4 : address6
          if (address == "") continue
          if (family == 4 ? !ipv4(address) : !ipv6(address))
            fail(family == 4 ? key4 : key6)
          upstreams = upstreams separator "{address_data: \"" address "\", tls_auth_name: \"" name "\", tls_port: " port "}"
          upstreams_json = upstreams_json separator "{\"dns_index\":" i ",\"address_data\":\"" address "\",\"tls_auth_name\":\"" name "\",\"tls_port\":" port "}"
          separator = ", "
          if (family == 4) {
            ipv4_allowlist = ipv4_allowlist ipv4_separator "\"" address "\""
            ipv4_separator = ", "
          } else {
            ipv6_allowlist = ipv6_allowlist ipv6_separator "\"" address "\""
            ipv6_separator = ", "
          }
        }
      }
      print "SYSTEM_NAMESERVERS_UPSTREAMS=" upstreams "]"
      print "SYSTEM_NAMESERVERS_UPSTREAMS_JSON=" upstreams_json "]"
      print "SYSTEM_DNS_UPSTREAM_TLS_CA_CUSTOM_ENABLE=" custom_ca
      print "SYSTEM_DNS_UPSTREAM_TLS_CA_FILE=" ca_file
      print "SYSTEM_NAMESERVERS_PORT=" port
      print "SYSTEM_NAMESERVERS_IPV4_ALLOWLIST=" ipv4_allowlist "]"
      print "SYSTEM_NAMESERVERS_IPV6_ALLOWLIST=" ipv6_allowlist "]"
      print "SYSTEM_DNS_CACHE_SIZE=" cache_size
      print "SYSTEM_DNS_CACHE_MIN_TTL=" cache_min_ttl
    }
  ' <__INSTALLER_PATH_DIR_DEV__/null) || return "$?"
  printf '%s\n%s\n' "$app_veth_identity_map" "$app_veth_dns_map"
)

app_veth_placeholder_map() {
  app_veth_identity_placeholder_map || return "$?"
  apparmor_document_media_placeholder_map
}

configure_target_stubby() (
  set -eu
  set +x
  set +v
  umask 077
  require_in_target "configure authenticated DNS upstreams"
  stubby_stage=$(target_private_stage_dir stubby)
  stubby_stage_host=$(target_asset_host_path "$stubby_stage")
  trap 'rm -rf -- "$stubby_stage_host"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  stage_target_template_input "$(installer_repo_file_value scripts/late/stubby-config.py)" \
    "$stubby_stage" configure.py
  stage_target_template_input "$(installer_repo_file_value hooks/target/etc/stubby/stubby.yml.tmpl)" \
    "$stubby_stage" stubby.yml.tmpl
  app_veth_dns_placeholder_map >"$stubby_stage_host/policy.map"
  stubby_ca_input=-
  if [ "${SYSTEM_DNS_UPSTREAM_TLS_CA_CUSTOM_ENABLE:-false}" = true ]; then
    stubby_ca_name=$(installer_cmdline_value dns_upstream_tls_ca_name_custom) || {
      installer_fatal "custom DNS requires dns_upstream_tls_ca_name_custom in installer credential input"
      exit 1
    }
    case "$stubby_ca_name" in
      [A-Za-z0-9]*.*) ;;
      *) installer_fatal "custom DNS CA name must be a basename including its extension"; exit 1 ;;
    esac
    case "$stubby_ca_name" in
      *[!A-Za-z0-9._-]*|*.) installer_fatal "custom DNS CA name contains unsupported characters or an empty extension"; exit 1 ;;
    esac
    [ "${#stubby_ca_name}" -le 128 ] || { installer_fatal "custom DNS CA name is too long"; exit 1; }
    # The certificate is an initrd-root input, never a repository/HTTP fetch.
    # Reuse the private reader's ownership, link and parent checks before copy.
    preseed_env_check_file "/$stubby_ca_name" || {
      installer_fatal "custom DNS CA is missing or unsafe in the installer root"
      exit 1
    }
    stubby_ca_size=$(wc -c <"/$stubby_ca_name")
    [ "$stubby_ca_size" -gt 0 ] && [ "$stubby_ca_size" -le 262144 ] || {
      installer_fatal "custom DNS CA exceeds its size limit or is empty"
      exit 1
    }
    cat "/$stubby_ca_name" >"$stubby_stage_host/ca.input"
    stubby_ca_input="$stubby_stage/ca.input"
  fi
  run_in_target "authenticate DNS certificate identities and configure Stubby" \
    __INSTALLER_PATH_DIR_USR_BIN__/python3 -I -B "$stubby_stage/configure.py" \
    "$stubby_stage/stubby.yml.tmpl" "$stubby_stage/policy.map" "$stubby_ca_input"
  installer_target_ownership_record "$(installer_repo_file_value hooks/target/etc/stubby/stubby.yml.tmpl)" \
    "${DIR_ETC_STUBBY}/stubby.yml" template 0644
)

configure_target_app_veth() {
  installer_operation_context_repo scripts/late/security.sh 1833 configure_target_app_veth
  [ "$(late_command_nftables_profile)" != none ] ||
    installer_fatal "managed kernel namespaces require the nftables policy"
  for veth_asset in \
    etc/systemd/system/app-veth.service \
    etc/sysctl.d/91-app-veth.conf \
    etc/modules-load.d/app-veth.conf
  do
    stage_target_asset "$(installer_repo_asset_path DIR_HOOKS_TARGET "$veth_asset")" "/$veth_asset" 0644
  done
  render_target_asset_with_placeholder_map \
    "$(installer_repo_file_value hooks/target/etc/NetworkManager/conf.d/70-app-veth.conf.tmpl)" \
    __INSTALLER_PATH_DIR_ETC__/NetworkManager/conf.d/70-app-veth.conf 0644 app_veth_identity_placeholder_map
  stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/sbin/desktop/app-veth)" __INSTALLER_PATH_DIR_USR_LOCAL__/sbin/app-veth 0755
  render_target_asset_with_placeholder_map \
    "$(installer_repo_file_value hooks/target/etc/app-veth.nft.tmpl)" \
    __INSTALLER_PATH_DIR_ETC__/app-veth.nft 0644 proxy3_placeholder_map
  configure_target_stubby
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/systemd/common/system/stubby.service)" __INSTALLER_PATH_DIR_ETC__/systemd/system/stubby.service 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/systemd/desktop/system/stubby.service.d/60-app-veth.conf)" __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_STUBBY_DROPIN__/60-app-veth.conf 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/systemd/desktop/system/systemd-resolved.service.d/60-stubby.conf)" __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_SYSTEMD_RESOLVED_DROPIN__/60-stubby.conf 0644
  render_target_asset_with_placeholder_map \
    "$(installer_repo_file_value hooks/target/etc/dnsmasq-app-veth.conf.tmpl)" \
    __INSTALLER_PATH_DIR_ETC__/dnsmasq-app-veth.conf 0644 app_veth_dns_placeholder_map
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/systemd/desktop/system/dnsmasq-app-veth.service)" __INSTALLER_PATH_DIR_ETC__/systemd/system/dnsmasq-app-veth.service 0644
  stage_target_asset \
    "$(installer_repo_file_value hooks/target/usr/local/lib/desktop/python3/dist-packages/app_veth_policy.py)" \
    "${DIR_PYTHON3_SITE_PACKAGES}/app_veth_policy.py" 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/libexec/desktop/app-veth-podman)" __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/app-veth-podman 0755
  render_target_asset_with_placeholder_map \
    "$(installer_repo_file_value hooks/target/etc/systemd/desktop/resolved.conf.d/60-app-veth.conf.tmpl)" \
    __INSTALLER_PATH_DIR_ETC__/systemd/resolved.conf.d/60-app-veth.conf 0644 app_veth_dns_placeholder_map
  render_target_asset_with_placeholder_map \
    "$(installer_repo_file_value hooks/target/etc/app-veth.json.tmpl)" \
    __INSTALLER_PATH_DIR_ETC__/app-veth.json 0644 app_veth_placeholder_map
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/rsyslog.d/18-app-veth.conf.tmpl)" __INSTALLER_PATH_DIR_ETC__/rsyslog.d/18-app-veth.conf 0644
  stage_target_systemd_unit_enabled dnsmasq-app-veth.service system
  stage_target_systemd_unit_enabled app-veth.service system
}

configure_target_apparmor_auditd() {
  installer_operation_context_repo scripts/late/security.sh 1874 configure_target_apparmor_auditd
  install -d -m 0755 \
    ${TARGET_ROOT}${DIR_ETC}/apparmor \
    ${TARGET_ROOT}${DIR_APPARMOR} \
    ${TARGET_ROOT}${DIR_APPARMOR}/abstractions \
    ${TARGET_ROOT}${DIR_APPARMOR}/local \
    ${TARGET_ROOT}${DIR_ETC}/audit \
    ${TARGET_ROOT}${DIR_ETC}/audit/rules.d \
    ${TARGET_ROOT}${DIR_ETC}/audit/plugins.d \
    ${TARGET_ROOT}${DIR_ETC}/logrotate.d \
    ${TARGET_ROOT}${DIR_ETC}/rsyslog.d \
    ${TARGET_ROOT}${DIR_SYSTEMD_SYSTEM_APPARMOR_DROPIN} \
    ${TARGET_ROOT}${DIR_SYSTEMD_SYSTEM_LOGROTATE_TIMER_DROPIN} \
    ${TARGET_ROOT}${DIR_ETC}/tmpfiles.d \
    ${TARGET_ROOT}${DIR_ETC}/ssh \
    ${TARGET_ROOT}${DIR_USR_LOCAL_BIN} \
    ${TARGET_ROOT}${DIR_USR_LOCAL_SBIN}
  install -d -m 0700 ${TARGET_ROOT}${DIR_ETC}/security
  [ -e ${TARGET_ROOT}${DIR_ETC}/security/opasswd ] || : > ${TARGET_ROOT}${DIR_ETC}/security/opasswd
  chmod 0600 ${TARGET_ROOT}${DIR_ETC}/security/opasswd
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/apparmor.d/desktop/abstractions/app-veth-client)" "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/app-veth-client" 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/apparmor.d/common/abstractions/base.d/process-monitor)" "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/base.d/process-monitor" 0644
  stage_target_system_apparmor_profiles
  if security_target_is_desktop; then
    stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/lib/common/perl5/site_perl/runtime/Managed/PolicyLock.pm)" \
      "${DIR_PERL5_SITE_PERL}/runtime/Managed/PolicyLock.pm" 0644
    install -d -m 0755 \
      "${TARGET_ROOT}${DIR_PERL5_SITE_PERL}/apparmor-modes/AppArmor/ManagedModes"
    stage_target_asset "$(installer_repo_file_value hooks/target/etc/apparmor/desktop/modes.conf.tmpl)" "__INSTALLER_PATH_DIR_ETC__/apparmor/modes.conf" 0644
    apparmor_apply_desktop_state "${TARGET_ROOT}${DIR_ETC}/apparmor/modes.conf"
    stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/libexec/common/apparmor-modes-run)" "__INSTALLER_PATH_DIR_USR_LOCAL__/libexec/apparmor-modes-run" 0755
    apparmor_managed_modes_perl_modules | while IFS= read -r apparmor_managed_modes_module; do
      [ -n "$apparmor_managed_modes_module" ] || continue
      stage_target_asset \
        "$(installer_repo_asset_path DIR_TARGET_PERL_APPARMOR_MODES "${apparmor_managed_modes_module}")" \
        "${DIR_PERL5_SITE_PERL}/apparmor-modes/${apparmor_managed_modes_module}" \
        0644
    done
    stage_target_asset "$(installer_repo_file_value hooks/target/etc/systemd/common/system/apparmor-modes.service)" "__INSTALLER_PATH_DIR_ETC__/systemd/system/apparmor-modes.service" 0644
    stage_target_asset "$(installer_repo_file_value hooks/target/etc/systemd/desktop/system/labwc-apparmor-policy@.service)" "__INSTALLER_PATH_DIR_ETC__/systemd/system/labwc-apparmor-policy@.service" 0644
    stage_target_asset "$(installer_repo_file_value hooks/target/etc/systemd/desktop/system/labwc-apparmor-boot-recover.service)" "__INSTALLER_PATH_DIR_ETC__/systemd/system/labwc-apparmor-boot-recover.service" 0644
    stage_target_desktop_apparmor_profiles
    run_in_target \
      "apply managed AppArmor profile modes without touching the installer kernel" \
      __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/apparmor-modes-run \
      --no-reload
    stage_target_systemd_unit_enabled apparmor-modes.service system
  fi
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/rsyslog.d/15-audit.conf)" "__INSTALLER_PATH_DIR_ETC__/rsyslog.d/15-audit.conf" 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/rsyslog.d/99-discard.conf)" "__INSTALLER_PATH_DIR_ETC__/rsyslog.d/99-discard.conf" 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/logrotate.conf)" "__INSTALLER_PATH_DIR_ETC__/logrotate.conf" 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/logrotate.d/audit)" "__INSTALLER_PATH_DIR_ETC__/logrotate.d/audit" 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/systemd/common/system/logrotate.timer.d/override.conf.tmpl)" "__INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_LOGROTATE_TIMER_DROPIN__/override.conf" 0644
  stage_target_systemd_unit_enabled apparmor.service system
  security_mask_target_systemd_unit_if_available systemd-journald-audit.socket system
  stage_target_systemd_unit_enabled auditd.service system
  stage_target_systemd_unit_enabled rsyslog.service system
  stage_target_systemd_unit_enabled logrotate.timer system
  configure_target_nftables
  configure_target_app_veth
  configure_target_fail2ban
}
