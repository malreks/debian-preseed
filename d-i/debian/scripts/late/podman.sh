#!/bin/sh
# Rootless Podman target staging; sourced by the shared late-command loader.
# All privileged account/storage work runs under the target Python interpreter,
# not missing BusyBox applets. Ordinary desktop commands never call this helper.

podman_fatal() {
  installer_fatal "$@"
}

podman_class_is_selected() {
  case "${PODMAN_CLASS_SELECTED:-}" in
    true) return 0 ;;
    false) return 1 ;;
  esac
  installer_tools_class_selected 2>__INSTALLER_PATH_DIR_DEV__/null
}

podman_class_selection_state() {
  if podman_class_is_selected; then printf '%s\n' true; else printf '%s\n' false; fi
}

# Kept as a small target-boundary helper for callers/tests. The target
# provisioner independently enforces the same approved-filesystem policy.
podman_resolve_native_storage_driver() (
  requested=$1
  storage=$2
  target=${INSTALLER_TARGET_DIR:-${TARGET_ROOT}}
  target=${target%/}
  case "$storage" in
    "$target"/*) relative=${storage#"$target"} ;;
    *) podman_fatal 'Podman storage path is outside the installation target' ;;
  esac
  case "$relative" in
    *..*|*//*|*[!A-Za-z0-9_./-]*) podman_fatal 'unsafe Podman storage path' ;;
  esac
  # The native filesystem-name lookup reads the target mount table. Use the
  # shared executor so d-i's in-target performs its normal proc/chroot setup.
  filesystem=$(target_exec __INSTALLER_PATH_DIR_USR_BIN__/find -P "$relative" -maxdepth 0 -printf '%F') ||
    podman_fatal 'target findutils could not inspect the Podman storage filesystem'
  case "$filesystem" in
    btrfs|ext2|ext3|ext4|xfs|f2fs) ;;
    *) podman_fatal "unsupported Podman storage filesystem: $filesystem" ;;
  esac
  case "$requested" in
    auto|overlay) printf '%s\n' overlay ;;
    btrfs)
      [ "$filesystem" = btrfs ] || podman_fatal 'btrfs storage requires Btrfs'
      printf '%s\n' btrfs
      ;;
    *) podman_fatal "unsupported Podman storage driver: $requested" ;;
  esac
)

configure_target_rootless_podman_if_selected() {
  podman_class_is_selected || return 0
  # Server roles own their provider stores and locked identities in
  # server/foundation.sh and server/devops.sh. Never run the desktop
  # podman-devops host provisioner for a headless role.
  [ "${INSTALLER_HOST_VARIANT:-desktop}" = server ] && return 0
  configure_target_rootless_podman
}

configure_target_rootless_podman() (
  : "${ACCOUNT_USERNAME:?ACCOUNT_USERNAME must be set}"
  # Fixed identities/paths are security invariants, not install-time aliases.
  [ "${PODMAN_USER:-devops}" = devops ] || podman_fatal 'PODMAN_USER must be devops'
  [ "${PODMAN_USER_HOME:-/nonexistent}" = /nonexistent ] ||
    podman_fatal 'PODMAN_USER_HOME must be /nonexistent for the no-home service account'
  [ "${PODMAN_ROOTLESS_STATE_BASE:-__INSTALLER_PATH_DIR_POOL__/podman}" = __INSTALLER_PATH_DIR_POOL__/podman ] ||
    podman_fatal 'PODMAN_ROOTLESS_STATE_BASE must be __INSTALLER_PATH_DIR_POOL__/podman'

  for asset in \
    containers.conf.tmpl storage.conf.tmpl registries.conf client.conf \
    podman-devops.service.tmpl podman-devops.socket \
    podman-devops-restart.service.tmpl
  do
    stage_target_asset \
      "$(installer_repo_asset_path DIR_TARGET_CONFIG_PODMAN_TEMPLATES_DEVOPS "$asset")" \
      "__INSTALLER_PATH_DIR_USR_LOCAL__/share/podman-devops/$asset" 0644
  done
  stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/libexec/desktop/podman-devops-host)" __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/podman-devops-host 0755
  stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/libexec/desktop/podman-devops-client)" __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/podman-devops-client 0755
  # The desktop role publishes the complete managed-app package later in its
  # own atomic staging step. Server-only Podman targets still need the small
  # network-client import surface here because they do not run that role.
  stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/libexec/desktop/app-veth-podman)" __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/app-veth-podman 0755
  podman_target_host_variant=${INSTALLER_HOST_VARIANT:-}
  if [ -z "$podman_target_host_variant" ]; then
    podman_target_host_variant=$(installer_selected_class_for_purpose host-variant 2>__INSTALLER_PATH_DIR_DEV__/null || printf '%s\n' server)
  fi
  if [ "$podman_target_host_variant" != desktop ]; then
    stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/lib/desktop/python3/dist-packages/labwc_managed_app/__init__.py)" "${DIR_PYTHON3_SITE_PACKAGES}/labwc_managed_app/__init__.py" 0644
    stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/lib/desktop/python3/dist-packages/labwc_managed_app/integrity.py)" "${DIR_PYTHON3_SITE_PACKAGES}/labwc_managed_app/integrity.py" 0644
    stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/lib/desktop/python3/dist-packages/labwc_managed_app/network_client.py)" "${DIR_PYTHON3_SITE_PACKAGES}/labwc_managed_app/network_client.py" 0644
  fi
  unset podman_target_host_variant
  for client in podman docker docker-compose; do
    stage_target_asset "$(installer_repo_asset_path DIR_TARGET_BIN "$client")" "__INSTALLER_PATH_DIR_USR_LOCAL__/bin/$client" 0755
  done
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/systemd/desktop/system/podman-devops-bootstrap.service)" __INSTALLER_PATH_DIR_ETC__/systemd/system/podman-devops-bootstrap.service 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/tmpfiles.d/desktop/55-podman-devops.conf)" __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/55-podman-devops.conf 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/ssh/sshd_config.d/00-devops-nologin.conf)" __INSTALLER_PATH_DIR_ETC__/ssh/sshd_config.d/00-devops-nologin.conf 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/sysctl.d/common/90-podman-rootless.conf)" __INSTALLER_PATH_DIR_ETC__/sysctl.d/90-podman-rootless.conf 0644
  installer_stage_profile_file hooks/target/etc/skel-desktop/.profile.d/71-devops-de.sh \
    "${DIR_ETC_SKEL_DESKTOP}/.profile.d/71-devops-de.sh" 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/bin/desktop/labwc-podman-menu)" __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-podman-menu 0755
  stage_target_helper_docs podman-devops.md podbin.md podbin-service-bridge.md

  run_in_target 'provision locked devops rootless engine' \
    __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/podman-devops-host setup \
      --desktop-user "$ACCOUNT_USERNAME" \
      --storage-driver "${PODMAN_STORAGE_DRIVER:-auto}" \
      --cpu-weight "${PODMAN_SERVICE_SLICE_CPU_WEIGHT:-100}" \
      --io-weight "${PODMAN_SERVICE_SLICE_IO_WEIGHT:-100}" \
      --tasks-max "${PODMAN_SERVICE_SLICE_TASKS_MAX:-8192}" \
      --memory-high "${PODMAN_SERVICE_SLICE_MEMORY_HIGH:-70%}" \
      --memory-max "${PODMAN_SERVICE_SLICE_MEMORY_MAX:-85%}"
  # Account shell assets were initially copied before this addon. Refresh them
  # from the same source so the selected Podman class does not require the selected DevOps class.
  install_target_account_shell_assets
  installer_info 'staged devops rootless Podman/Docker clients; socket activation and readiness validation run on every boot'
)
