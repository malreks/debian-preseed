#!/bin/sh
# Shared F2FS-family late_command implementation. This file is sourced.

run_f2fs_family_late_command() {
requested_seed_base=${1:-}
requested_host_profile=${2:-}
HOOK_FAMILY=f2fs

f2fs_late_command_mark() {
  if command -v installer_operation_context_repo >/dev/null 2>&1; then
    installer_operation_context_repo scripts/late/f2fs-family.sh "$1" "$2"
  elif command -v installer_operation_context >/dev/null 2>&1; then
    installer_operation_context unknown "$1" "$2"
  fi
  installer_info "F2FS-family late operation: $2"
}

late_command_shared_init "$requested_seed_base" "$requested_host_profile" "$HOOK_FAMILY"
# This is a new child shell; shared initialization defines the log functions.
f2fs_late_command_mark 22 run_f2fs_family_late_command

f2fs_late_command_mark 23 late_command_fetch_common_assets
late_command_fetch_common_assets_file scripts/runtime/f2fs.sh
f2fs_late_command_mark 25 late_command_load_runtime_env
late_command_load_runtime_env false
f2fs_late_command_mark 27 fetch_grub_profiles_template
late_command_fetch_repo_file hooks/target/etc/default/grub-profiles.tmpl "$TMP_ENV_DIR/grub-profiles" grub-profiles.tmpl
f2fs_late_command_mark 29 fetch_grub_profile_generator
late_command_fetch_repo_file hooks/target/etc/grub.d/40_custom.tmpl "$TMP_ENV_DIR/grub-profile-generator" grub-profile-generator.tmpl
f2fs_late_command_mark 31 late_command_load_host_env
late_command_load_host_env || return $?
# Architecture policy owns the required EFI placeholders and must exist before
# *any* renderer (including the unrelated runtime defaults) is called.
f2fs_late_command_mark 35 late_command_require_class_policy_env
late_command_require_class_policy_env || return $?
f2fs_late_command_mark 37 install_target_runtime_defaults
install_target_runtime_defaults || return $?
f2fs_late_command_mark 39 install_target_wpa_supplicant_runtime_policy
install_target_wpa_supplicant_runtime_policy || return $?
f2fs_late_command_mark 41 installer_ensure_context_loaded
installer_ensure_context_loaded "${SEED_BASE:-}"
CPU_CLASS=$(installer_selected_class_for_purpose cpu 2>__INSTALLER_PATH_DIR_DEV__/null || printf '%s' "${INSTALLER_CPU_CLASS:-}")
DISK_CLASS=$(installer_selected_class_for_purpose storage 2>__INSTALLER_PATH_DIR_DEV__/null || printf '%s' "${INSTALLER_DISK_CLASS:-}")
GPU_CLASSES=$(installer_selected_class_for_purpose gpu 2>__INSTALLER_PATH_DIR_DEV__/null || printf '%s' "${INSTALLER_GPU_CLASS:-}")
NVIDIA_CLASS_SELECTED=false
NVIDIA_GPU_DETECTED=false
if installer_class_selected optional/nvidia; then
  NVIDIA_CLASS_SELECTED=true
fi
if installer_class_selected optional/nvidia-legacy; then
  NVIDIA_CLASS_SELECTED=true
fi
PODMAN_CLASS_SELECTED=$(podman_class_selection_state)
if installer_nvidia_gpu_detected; then
  NVIDIA_GPU_DETECTED=true
fi
if [ "$NVIDIA_CLASS_SELECTED" = true ] && [ "$NVIDIA_GPU_DETECTED" != true ]; then
  warn "an NVIDIA addon was selected but no NVIDIA PCI display adapter was detected; NVIDIA target packages and modprobe config stay disabled"
fi
info "late installer context: host_profile=${INSTALLER_HOST_PROFILE:-unset} selected_groups=${INSTALLER_SELECTED_GROUPS:-unset} selected_classes=${INSTALLER_SELECTED_CLASSES:-unset} cpu=${CPU_CLASS:-unset} disk=${DISK_CLASS:-unset} gpu=${GPU_CLASSES:-none} nvidia_class=${NVIDIA_CLASS_SELECTED} nvidia_gpu=${NVIDIA_GPU_DETECTED} podman_class=${PODMAN_CLASS_SELECTED}"

default_file_modprobe_mei_blacklist=$FILE_MODPROBE_MEI_BLACKLIST
default_file_modprobe_i915=$FILE_MODPROBE_I915
default_file_modprobe_amdgpu=$FILE_MODPROBE_AMDGPU
default_file_modprobe_nvidia=$FILE_MODPROBE_NVIDIA
default_file_modprobe_usbcore=$FILE_MODPROBE_USBCORE
default_file_modprobe_cfg80211=$FILE_MODPROBE_CFG80211
default_file_modprobe_nvme_blacklist=$FILE_MODPROBE_NVME_BLACKLIST
default_file_modules_load_emmc_storage=$FILE_MODULES_LOAD_EMMC_STORAGE
default_file_grub_cpu_profile_dropin="${DIR_GRUB_DEFAULT}/80-cpu-profile-flags.cfg"
default_file_grub_gpu_intel_dropin="${DIR_GRUB_DEFAULT}/85-gpu-intel.cfg"
default_file_grub_gpu_amd_dropin="${DIR_GRUB_DEFAULT}/86-gpu-amd.cfg"
default_file_grub_gpu_nvidia_dropin="${DIR_GRUB_DEFAULT}/87-gpu-nvidia.cfg"

target_enable_intel_platform=false
target_enable_intel_gpu=false
target_enable_amd_gpu=false
target_enable_nvidia=false
target_enable_nvme_tunables=false
target_enable_emmc_storage=false

case "${CPU_CLASS:-}" in
  generic-arm64|amd) ;;
  intel)
    target_enable_intel_platform=true
    ;;
  *)
    fatal "unsupported CPU class: ${CPU_CLASS:-unset}"
    ;;
esac

case "${DISK_CLASS:-emmc}" in
  emmc)
    target_enable_emmc_storage=true
    ;;
  *)
    fatal "unsupported F2FS disk class: ${DISK_CLASS:-unset}"
    ;;
esac

if [ "$NVIDIA_CLASS_SELECTED" = true ] && [ "$NVIDIA_GPU_DETECTED" = true ]; then
  target_enable_nvidia=true
fi

for gpu_class in $GPU_CLASSES; do
  case "$gpu_class" in
    intel-uhd) target_enable_intel_gpu=true ;;
    amd-radeon) target_enable_amd_gpu=true ;;
    generic|'')
      ;;
    *)
      fatal "unsupported gpu class: ${gpu_class}"
      ;;
  esac
done

GRAPHICS_INITRAMFS_MODULES=$(late_command_graphics_initramfs_modules "$GPU_CLASSES" "$target_enable_nvidia")

set_optional_path FILE_MODPROBE_MEI_BLACKLIST false "$default_file_modprobe_mei_blacklist"
set_optional_path FILE_MODPROBE_I915 "$target_enable_intel_gpu" "$default_file_modprobe_i915"
set_optional_path FILE_MODPROBE_AMDGPU "$target_enable_amd_gpu" "$default_file_modprobe_amdgpu"
set_optional_path FILE_MODPROBE_NVIDIA "$target_enable_nvidia" "$default_file_modprobe_nvidia"
set_optional_path FILE_MODPROBE_USBCORE "$target_enable_nvme_tunables" "$default_file_modprobe_usbcore"
set_optional_path FILE_MODPROBE_CFG80211 false "$default_file_modprobe_cfg80211"
set_optional_path FILE_MODPROBE_NVME_BLACKLIST "$target_enable_nvme_tunables" "$default_file_modprobe_nvme_blacklist"
set_optional_path FILE_MODULES_LOAD_EMMC_STORAGE "$target_enable_emmc_storage" "$default_file_modules_load_emmc_storage"
set_optional_path FILE_GRUB_CPU_PROFILE_DROPIN true "$default_file_grub_cpu_profile_dropin"
set_optional_path FILE_GRUB_GPU_INTEL_DROPIN "$target_enable_intel_gpu" "$default_file_grub_gpu_intel_dropin"
set_optional_path FILE_GRUB_GPU_AMD_DROPIN "$target_enable_amd_gpu" "$default_file_grub_gpu_amd_dropin"
set_optional_path FILE_GRUB_GPU_NVIDIA_DROPIN "$target_enable_nvidia" "$default_file_grub_gpu_nvidia_dropin"

GRAPHICS_INITRAMFS_MODULES=$(module_value_to_lines "${GRAPHICS_INITRAMFS_MODULES:-}")

f2fs_late_command_mark 135 runtime_apply_ssh_from_classes
runtime_apply_ssh_from_classes

write_target_fstab() {
  # Runtime layout env fragments provide the device paths and mount options used here.
  # shellcheck disable=SC2153
  root_src=$(device_source "${DEV_PART_ROOT}")
  # shellcheck disable=SC2153
  boot_src=$(device_source "${DEV_PART_BOOT}")
  efi_src=$(device_source "${DEV_PART_EFI}")
  journal_src=$(device_source "${DEV_PART_VAR_LOG_JOURNAL}")

  {
    printf '%s\n' '# Kernel and boot filesystems'
    fstab_entry proc __INSTALLER_PATH_DIR_PROC__ proc defaults 0 0
    # shellcheck disable=SC2153
    fstab_entry "$boot_src" "$DIR_BOOT" ext4 "$MNT_BOOT_OPTS" 0 2
    fstab_entry "$efi_src" "$DIR_BOOT_EFI" vfat "$MNT_EFI_OPTS" 0 2
    printf '%s\n' '# Local filesystems'
    # shellcheck disable=SC2153
    fstab_entry "$root_src" / f2fs "$MNT_F2FS_ROOT_OPTS" 0 0
    if [ -n "${DEV_PART_HOME:-}" ] && [ "${DEV_PART_HOME_MB:-0}" -gt 0 ]; then
      home_src=$(device_source "$DEV_PART_HOME")
      fstab_entry "$home_src" "$DIR_HOME" f2fs "$MNT_F2FS_HOME_OPTS" 0 0
    fi
    if [ -n "${DEV_PART_POOL:-}" ] && [ "$DEV_PART_POOL_MB" -gt 0 ]; then
      pool_src=$(device_source "$DEV_PART_POOL")
      fstab_entry "$pool_src" "$DIR_POOL" ext4 "$MNT_EXT4_POOL_OPTS" 0 2
    fi
    printf '%s\n' '# Temporary storage and logs'
    if tmpfs_policy_enabled TMPFS_DATA_RUN; then
      fstab_entry tmpfs "$DIR_DATA_RUN" tmpfs "$MNT_DATA_RUN_TMPFS_OPTS" 0 0
    fi
    write_rsyslog_spool_fstab
    if tmpfs_policy_enabled TMPFS_VAR_LOG; then
      fstab_entry tmpfs "$DIR_VAR_LOG" tmpfs "$MNT_VAR_LOG_TMPFS_OPTS" 0 0
    fi
    if tmpfs_policy_enabled TMPFS_VAR_CACHE; then
      fstab_entry tmpfs "$DIR_VAR_CACHE" tmpfs "$MNT_VAR_CACHE_TMPFS_OPTS" 0 0
    fi
    if tmpfs_policy_enabled TMPFS_VAR_LIB_APT_LISTS; then
      fstab_entry tmpfs "$DIR_APT_LISTS" tmpfs "$MNT_APT_LISTS_TMPFS_OPTS" 0 0
    fi
    if tmpfs_policy_enabled TMPFS_SYSTEMD_COREDUMP; then
      fstab_entry tmpfs "$DIR_SYSTEMD_COREDUMP" tmpfs "$MNT_COREDUMP_TMPFS_OPTS" 0 0
    fi
    fstab_entry tmpfs "$DIR_TMP" tmpfs "$MNT_TMP_OPTS" 0 0
    if tmpfs_policy_enabled TMPFS_DEV_SHM; then
      fstab_entry tmpfs "$DIR_DEV_SHM" tmpfs "$MNT_DEV_SHM_OPTS" 0 0
    fi
    printf '%s\n' '# Persistent journal'
    fstab_entry "$journal_src" "$DIR_VAR_LOG_JOURNAL" ext4 "$MNT_VAR_LOG_JOURNAL_OPTS" 0 2
  } | write_target_fstab_records
  cp ${TARGET_ROOT}${DIR_ETC}/fstab ${TARGET_ROOT}${DIR_ETC}/fstab.layout-cache 2>__INSTALLER_PATH_DIR_DEV__/null || true
  cp ${TARGET_ROOT}${DIR_ETC}/fstab ${TARGET_ROOT}${DIR_ETC}/fstab.orig 2>__INSTALLER_PATH_DIR_DEV__/null || true
}

write_target_kernel_tunables() {
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/modprobe.d/60-ses-blacklist.conf)" "${FILE_MODPROBE_SES_BLACKLIST}" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path disk "${DISK_CLASS}" "etc/modprobe.d/72-nvme-blacklist.conf")" "${FILE_MODPROBE_NVME_BLACKLIST:-}" "${DIR_MODPROBE_D}/72-nvme-blacklist.conf" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path cpu "${CPU_CLASS}" "etc/modprobe.d/05-mei-blacklist.conf")" "${FILE_MODPROBE_MEI_BLACKLIST:-}" "${DIR_MODPROBE_D}/05-mei-blacklist.conf" 0644
  stage_target_hardware_spec
  stage_target_graphics_kernel_tunables "$target_enable_nvidia"
  stage_target_asset_if_path "$(installer_hardware_asset_path disk "${DISK_CLASS}" "etc/modprobe.d/74-usbcore.conf")" "${FILE_MODPROBE_USBCORE:-}" "${DIR_MODPROBE_D}/74-usbcore.conf" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path cpu "${CPU_CLASS}" "etc/modprobe.d/75-cfg80211.conf")" "${FILE_MODPROBE_CFG80211:-}" "${DIR_MODPROBE_D}/75-cfg80211.conf" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path disk "${DISK_CLASS}" "etc/modules-load.d/20-emmc-storage.conf")" "${FILE_MODULES_LOAD_EMMC_STORAGE:-}" "${DIR_MODULES_LOAD}/20-emmc-storage.conf" 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/modules-load.d/30-storage-memory.conf)" "${FILE_MODULES_LOAD_STORAGE_MEMORY}" 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/modules-load.d/32-tpm.conf)" "${FILE_MODULES_LOAD_TPM}" 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/sysctl.d/common/10-baseline.conf)" "${FILE_SYSCTL_BASELINE}" 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/sysctl.d/common/20-storage-memory.conf)" "${FILE_SYSCTL_STORAGE_MEMORY}" 0644
  render_target_asset "$(installer_repo_file_value hooks/target/etc/sysctl.d/common/25-storage-static.conf.tmpl)" "${FILE_SYSCTL_FAMILY_OVERRIDE}" 0644
  render_target_asset "$(installer_repo_file_value hooks/target/etc/sysctl.d/common/profiles/balanced/40-balanced.conf.tmpl)" "${FILE_SYSCTL_PROFILE_DEFAULT}" 0644
  render_target_asset "$(installer_repo_file_value hooks/target/etc/sysctl.d/common/profiles/hardened/40-hardened.conf.tmpl)" "${FILE_SYSCTL_PROFILE_HARDENED}" 0644
  render_target_asset "$(installer_repo_file_value hooks/target/etc/sysctl.d/common/profiles/performance/40-performance.conf.tmpl)" "${FILE_SYSCTL_PROFILE_PERFORMANCE}" 0644

  stage_target_asset "$(installer_repo_file_value hooks/target/etc/initramfs-tools/conf.d/99-compress.conf)" "${FILE_INITRAMFS_CUSTOM_CONF}" 0644
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/initramfs-tools/conf.d/resume)" "${FILE_INITRAMFS_RESUME}" 0644
  render_target_asset "$(installer_hardware_asset_path disk "${DISK_CLASS}" "etc/initramfs-tools/modules.tmpl")" "${FILE_INITRAMFS_MODULES}" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path cpu "${CPU_CLASS}" "etc/default/grub.d/80-cpu-profile-flags.cfg")" "${FILE_GRUB_CPU_PROFILE_DROPIN:-}" "${DIR_GRUB_DEFAULT}/80-cpu-profile-flags.cfg" 0644
  stage_target_common_boot_policy "$target_enable_nvidia"
}

f2fs_late_command_mark 217 write_target_fstab
write_target_fstab
f2fs_late_command_mark 219 ensure_target_managed_runtime_storage_roots
ensure_target_managed_runtime_storage_roots
f2fs_late_command_mark 221 provision_target_identity
provision_target_identity
f2fs_late_command_mark 223 stage_target_docs_index
stage_target_docs_index
f2fs_late_command_mark 225 stage_target_account_shell_assets
stage_target_account_shell_assets
f2fs_late_command_mark 227 ensure_target_account_home_ownership
ensure_target_account_home_ownership
f2fs_late_command_mark 229 install_target_account_shell_assets
install_target_account_shell_assets
f2fs_late_command_mark 231 install_target_account_sudoers
install_target_account_sudoers
f2fs_late_command_mark 233 configure_target_shared_account_access
configure_target_shared_account_access
f2fs_late_command_mark 235 write_target_grub_dropins
write_target_grub_dropins
f2fs_late_command_mark 237 set_target_grub_default_entry
set_target_grub_default_entry
f2fs_late_command_mark 239 finish_target_pkgsel_apt_state
finish_target_pkgsel_apt_state
f2fs_late_command_mark 241 install_target_mullvad_vpn_if_selected
install_target_mullvad_vpn_if_selected
f2fs_late_command_mark 243 stage_target_secure_boot_runtime_assets
stage_target_secure_boot_runtime_assets
f2fs_late_command_mark 245 stage_target_xssh_helpers
stage_target_xssh_helpers
f2fs_late_command_mark 247 provision_target_ssh_client
provision_target_ssh_client
f2fs_late_command_mark 249 provision_target_git_ssh_identity
provision_target_git_ssh_identity
f2fs_late_command_mark 251 configure_target_rootless_podman_if_selected
configure_target_rootless_podman_if_selected
f2fs_late_command_mark 253 sanitize_target_xfs_scrub_systemd_units
sanitize_target_xfs_scrub_systemd_units
f2fs_late_command_mark 255 install_target_wpa_supplicant_runtime_policy
install_target_wpa_supplicant_runtime_policy
f2fs_late_command_mark 257 write_target_kernel_tunables
write_target_kernel_tunables
f2fs_late_command_mark 259 ensure_target_secure_boot_packages
ensure_target_secure_boot_packages
f2fs_late_command_mark 261 provision_target_ssh_server
provision_target_ssh_server
f2fs_late_command_mark 263 install_target_managed_network_handoff
install_target_managed_network_handoff
f2fs_late_command_mark 265 configure_target_apparmor_auditd
configure_target_apparmor_auditd
f2fs_late_command_mark 267 dedupe_target_tmpfiles_legacy_lock
dedupe_target_tmpfiles_legacy_lock
f2fs_late_command_mark 269 prepare_target_secure_boot_runtime
prepare_target_secure_boot_runtime
f2fs_late_command_mark 271 install_target_firstboot_logger
install_target_firstboot_logger
f2fs_late_command_mark 273 enable_target_storage_units
enable_target_storage_units
f2fs_late_command_mark 275 set_target_default_unit
set_target_default_unit
f2fs_late_command_mark 277 disable_stock_kernel_menu
disable_stock_kernel_menu

if target_exec_available; then
  f2fs_late_command_mark 281 sign_target_installed_kernel_modules
  sign_target_installed_kernel_modules
  # Regenerate signed kernels/initrds BEFORE discovering boot menu entries.
  f2fs_late_command_mark 284 repair_target_installed_kernels
  repair_target_installed_kernels
  f2fs_late_command_mark 286 require_target_grub_installed
  require_target_grub_installed
  f2fs_late_command_mark 288 install_target_grub_profiles
  install_target_grub_profiles
  f2fs_late_command_mark 290 require_target_dualboot_os_prober_package
  require_target_dualboot_os_prober_package
  f2fs_late_command_mark 292 run_target_grub_config_update
  run_target_grub_config_update
  # This is the unconditional d-i late reset point: GRUB, shim, MokManager,
  # kernel/initrd and grub.cfg are complete before mokutil is called. Reset
  # failures remain warnings so installation can finish.
  if (finalize_target_secure_boot_mok_reset); then
    :
  else
    installer_warn "MOK reset/boot preparation failed after GRUB installation; continuing installation"
  fi
  f2fs_late_command_mark 302 sync_target_secure_boot_bundle_to_installer_usb
  sync_target_secure_boot_bundle_to_installer_usb
  f2fs_late_command_mark 304 close_target_secure_boot_state
  close_target_secure_boot_state
fi

f2fs_late_command_mark 308 configure_target_dbus_broker
configure_target_dbus_broker
f2fs_late_command_mark 310 prepare_target_deferred_tmpfs_roots
prepare_target_deferred_tmpfs_roots
f2fs_late_command_mark 312 prepare_target_volatile_mountpoints_for_first_boot
prepare_target_volatile_mountpoints_for_first_boot
f2fs_late_command_mark 314 stage_target_logging_foundation
stage_target_logging_foundation || return $?
f2fs_late_command_mark 316 installer_archive_logs_to_target
installer_archive_logs_to_target copy || true
}
