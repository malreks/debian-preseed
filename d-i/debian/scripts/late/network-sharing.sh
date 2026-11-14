#!/bin/sh
# Shared, sourced late-command module. Profile data is never evaluated here.

configure_target_network_sharing() (
  set -eu
  require_in_target "configure managed network sharing"
  if [ ! -x ${TARGET_ROOT}${DIR_USR_BIN}/python3 ]; then
    installer_fatal 'the common APT Python baseline is missing before sharing configuration'
  fi
  nfs_stage=$(target_private_stage_dir network-sharing)
  cleanup_network_sharing_stage() {
    nfs_cleanup_status=$?
    trap - EXIT HUP INT TERM
    case "$nfs_cleanup_status" in 76|124|129|130|137|143) nfs_uncertain=true ;; *) nfs_uncertain=false ;; esac
    if [ -e "${TARGET_ROOT}${nfs_stage}/outcome-unknown.json" ] || [ "$nfs_uncertain" = true ]; then
      installer_warn "NFS command outcome unknown; private recovery retained at ${nfs_stage}"
      exit 76
    fi
    rm -rf -- "${TARGET_ROOT}${nfs_stage}"
    exit "$nfs_cleanup_status"
  }
  trap cleanup_network_sharing_stage EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  stage_target_asset "$(installer_repo_file_value FILE_LATE_NETWORK_SHARING_PY)" \
    "${nfs_stage}/configure.py" 0600
  for nfs_asset in \
    etc/exports.tmpl \
    etc/idmapd.conf.tmpl \
    etc/nfs.conf.d/60-network-sharing.conf.tmpl \
    etc/sysctl.d/60-network-sharing.conf.tmpl \
    etc/systemd/system/nfs-server.service.d/60-network-sharing.conf.tmpl \
    etc/systemd/system/nfs-mountd.service.d/60-network-sharing.conf \
    etc/systemd/system/nfs-idmapd.service.d/60-network-sharing.conf \
    etc/systemd/system/network-sharing-identity.service \
    etc/systemd/system/network-sharing-report.service.tmpl \
    usr/local/libexec/network-sharing-identity \
    usr/local/libexec/network-sharing-report
  do
    stage_target_asset "$(installer_repo_asset_path DIR_HOOKS_TARGET "$nfs_asset")" \
      "${nfs_stage}/assets/${nfs_asset}" 0600
  done
  run_in_target "validate and configure profile-controlled NFS sharing" \
    __INSTALLER_PATH_DIR_USR_BIN__/env \
    "ACCOUNT_USERNAME=${ACCOUNT_USERNAME:?}" "ACCOUNT_HOME=${ACCOUNT_HOME:?}" \
    "INSTALLER_ROLE_FAMILY=${INSTALLER_HOST_VARIANT:?}" \
    "SYSTEM_DOMAIN=${SYSTEM_DOMAIN:?}" \
    "NFT_PROFILE=${NFT_PROFILE:-default}" \
    "NETWORK_SHARING_ROOT_PATH=${NETWORK_SHARING_ROOT_PATH:?}" \
    "NETWORK_SHARING_HOME_BIND_PATH=${NETWORK_SHARING_HOME_BIND_PATH:?}" \
    "NFS_SERVER_ENABLE=${NFS_SERVER_ENABLE:?}" \
    "NFS_SERVER_PATH=${NFS_SERVER_PATH:?}" \
    "NFS_SERVER_APT_DEPS=${NFS_SERVER_APT_DEPS:?}" \
    "NFS_SERVER_PORT=${NFS_SERVER_PORT:?}" \
    "NFS_SERVER_THREADS=${NFS_SERVER_THREADS:?}" \
    "NFS_SERVER_RW_OPTIONS=${NFS_SERVER_RW_OPTIONS:?}" \
    "NFS_SERVER_RO_OPTIONS=${NFS_SERVER_RO_OPTIONS:?}" \
    "NFS_SERVER_EXPORTS=${NFS_SERVER_EXPORTS:?}" \
    "NFS_CLIENT_ENABLE=${NFS_CLIENT_ENABLE:?}" \
    "NFS_CLIENT_PATH=${NFS_CLIENT_PATH:?}" \
    "NFS_CLIENT_TARGET_IP=${NFS_CLIENT_TARGET_IP:?}" \
    "NFS_CLIENT_EXPORT_PATH=${NFS_CLIENT_EXPORT_PATH:?}" \
    "NFS_CLIENT_VERSION=${NFS_CLIENT_VERSION:?}" \
    "NFS_CLIENT_READ_ONLY=${NFS_CLIENT_READ_ONLY:?}" \
    "NFS_CLIENT_MOUNT_TIMEOUT=${NFS_CLIENT_MOUNT_TIMEOUT:?}" \
    "NFS_CLIENT_APT_DEPS=${NFS_CLIENT_APT_DEPS:?}" \
    "NFS_MNT_CLIENT_TARGET_SHARE_OPTS=${NFS_MNT_CLIENT_TARGET_SHARE_OPTS:?}" \
    "NFS_ACCOUNT_UID=${NFS_ACCOUNT_UID:?}" "NFS_ACCOUNT_GID=${NFS_ACCOUNT_GID:?}" \
    "NFS_SHARED_GROUP=${NFS_SHARED_GROUP:?}" "NFS_SHARED_GID=${NFS_SHARED_GID:?}" \
    "NFS_INTERFACES=${NFS_INTERFACES:?}" \
    "NFS_TCP_RMEM=${NFS_TCP_RMEM:?}" "NFS_TCP_WMEM=${NFS_TCP_WMEM:?}" \
    "NFS_SOCKET_RMEM_MAX=${NFS_SOCKET_RMEM_MAX:?}" \
    "NFS_SOCKET_WMEM_MAX=${NFS_SOCKET_WMEM_MAX:?}" \
    __INSTALLER_PATH_DIR_USR_BIN__/python3 -I -B "${nfs_stage}/configure.py" "${nfs_stage}/assets"
)
