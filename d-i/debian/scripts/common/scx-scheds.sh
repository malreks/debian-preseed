#!/bin/sh
# Configure the profile-pinned sched_ext userspace packages without building them.

profile_validate_scx_scheduler_policy() {
  profile_scx_enabled=${HARDWARE_CPU_SCHEDULER_SCX_ENABLE:-false}
  case "$profile_scx_enabled" in
    true|false) ;;
    *) installer_fatal "HARDWARE_CPU_SCHEDULER_SCX_ENABLE must be true or false" ;;
  esac

  profile_scx_mode=${HARDWARE_CPU_SCHEDULER_SCX_MODE:-on-demand}
  case "$profile_scx_mode" in
    direct|on-demand) ;;
    *) installer_fatal "HARDWARE_CPU_SCHEDULER_SCX_MODE must be direct or on-demand" ;;
  esac

  profile_scx_worker_normal=${HARDWARE_CPU_SCHEDULER_SCX_WORKER_NORMAL:-}
  profile_scx_worker_performance=${HARDWARE_CPU_SCHEDULER_SCX_WORKER_PERFORMANCE:-}
  case "$profile_scx_worker_normal:$profile_scx_worker_performance" in
    scx_[a-z0-9_]*:scx_[a-z0-9_]*) ;;
    *) installer_fatal "sched_ext worker names must be registered scx workers" ;;
  esac
  [ "$profile_scx_worker_normal" != "$profile_scx_worker_performance" ] ||
    installer_fatal "sched_ext normal and performance workers must differ"
}

profile_require_scx_file() {
  scx_path=$1
  scx_host_path=$(target_asset_host_path "$scx_path") || exit 1
  [ -f "$scx_host_path" ] && [ ! -L "$scx_host_path" ] ||
    installer_fatal "scx-scheds package asset is missing or unsafe: ${scx_path}"
}

profile_install_scx_scheduler() (
  set -eu
  profile_validate_scx_scheduler_policy

  if [ "$profile_scx_enabled" = false ]; then
    installer_info "scx-scheds disabled by host profile; package assets and units remain absent"
    return 0
  fi

  # The profile-controlled packages are imported and installed by the software
  # late helper. Require both the long-running default and the interactive
  # DevOps handoff scheduler before publishing managed config.
  for scx_unit in scx.service scx_loader.service; do
    scx_unit_path=$(target_systemd_unit_path "$scx_unit" system 2>__INSTALLER_PATH_DIR_DEV__/null || true)
    [ -n "$scx_unit_path" ] ||
      installer_fatal "scx-scheds package unit is unavailable: ${scx_unit}"
  done
  for scx_asset in \
    __INSTALLER_PATH_DIR_USR_BIN__/scx_rusty \
    __INSTALLER_PATH_DIR_USR_BIN__/scx_flash \
    __INSTALLER_PATH_DIR_USR_BIN__/scx_loader \
    __INSTALLER_PATH_DIR_USR_BIN__/scxctl \
    __INSTALLER_PATH_DIR_USR_SHARE__/dbus-1/system-services/org.scx.Loader.service \
    __INSTALLER_PATH_DIR_USR_SHARE__/dbus-1/system.d/org.scx.Loader.conf \
    __INSTALLER_PATH_DIR_USR_SHARE__/dbus-1/interfaces/org.scx.Loader.xml \
    __INSTALLER_PATH_DIR_USR_SHARE__/polkit-1/actions/org.scx.Loader.policy
  do
    profile_require_scx_file "$scx_asset"
  done

  installer_stage_profile_file hooks/target/etc/default/scx.tmpl __INSTALLER_PATH_DIR_ETC__/default/scx 0644
  installer_stage_profile_file hooks/target/etc/scx_loader/config.toml.tmpl __INSTALLER_PATH_DIR_ETC__/scx_loader/config.toml 0644
  installer_stage_profile_file \
    hooks/target/etc/systemd/common/system/scx.service.d/50-sched-ext.conf \
    __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_SCX_DROPIN__/50-sched-ext.conf 0644
  installer_stage_profile_file \
    hooks/target/etc/systemd/common/system/scx_loader.service.d/50-sched-ext.conf \
    __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_SCX_LOADER_DROPIN__/50-sched-ext.conf 0644

  # Never enable both package backends: each can load a sched_ext scheduler.
  # Keeping both installed preserves the packaged manual fallback interfaces.
  case "$profile_scx_mode" in
    direct)
      unstage_target_systemd_unit_enabled scx_loader.service system
      # Direct mode owns the long-running scheduler at boot. The loader remains
      # installed for diagnostics/manual recovery but cannot race this unit.
      stage_target_systemd_unit_enabled scx.service system
      installer_info "configured scx-scheds scheduler=${profile_scx_worker_normal} activation=boot mode=direct enabled=${profile_scx_enabled}"
      ;;
    on-demand)
      # The loader is the sole boot owner. Its packaged Type=dbus service
      # starts the configured default scheduler when it registers the bus name;
      # enabling it through multi-user.target makes that startup automatic.
      unstage_target_systemd_unit_enabled scx.service system
      stage_target_systemd_unit_enabled scx_loader.service system
      installer_info "configured scx-scheds scheduler=${profile_scx_worker_normal} loader=scx_loader.service activation=boot mode=on-demand performance_worker=${profile_scx_worker_performance} enabled=${profile_scx_enabled}"
      ;;
  esac
)
