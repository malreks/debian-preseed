#!/bin/sh
# Shared Btrfs-family late_command implementation. This file is sourced.
# shellcheck disable=SC2034

btrfs_family_fstab_record_for_mount() {
  bffrm_fstab_file=$1
  bffrm_mount_target=$2

  [ -r "$bffrm_fstab_file" ] || return 1
  case "$bffrm_mount_target" in
    /*) ;;
    *) return 1 ;;
  esac

  awk -v target="$bffrm_mount_target" '
    /^[[:space:]]*#/ {
      next
    }
    NF >= 4 && $2 == target {
      filesystem_type = $3
      mount_options = $4
    }
    END {
      if (filesystem_type != "") {
        print filesystem_type " " mount_options
      }
    }
  ' "$bffrm_fstab_file"
}

# Select paths once; staging and initramfs rendering consume the same policy.
select_btrfs_hardware_policy() {
default_file_modprobe_snd_hda_intel=$FILE_MODPROBE_SND_HDA_INTEL
default_file_modprobe_iwlwifi=$FILE_MODPROBE_IWLWIFI
default_file_modprobe_e1000e=$FILE_MODPROBE_E1000E
default_file_modprobe_vfio=$FILE_MODPROBE_VFIO
default_file_modprobe_i915=$FILE_MODPROBE_I915
default_file_modprobe_amdgpu=$FILE_MODPROBE_AMDGPU
default_file_modprobe_nvidia=$FILE_MODPROBE_NVIDIA
default_file_modprobe_thunderbolt=$FILE_MODPROBE_THUNDERBOLT
default_file_modprobe_usbcore=$FILE_MODPROBE_USBCORE
default_file_modprobe_cfg80211=$FILE_MODPROBE_CFG80211
default_file_modprobe_nvme_blacklist=$FILE_MODPROBE_NVME_BLACKLIST
default_file_modprobe_mei_blacklist=$FILE_MODPROBE_MEI_BLACKLIST
default_file_modprobe_nvme_opts=$FILE_MODPROBE_NVME_OPTS
default_file_udev_regdom_rule=$FILE_UDEV_REGDOM_RULE
default_file_modules_load_vfio=$FILE_MODULES_LOAD_VFIO
default_file_modules_load_virt_host=$FILE_MODULES_LOAD_VIRT_HOST
default_file_modules_load_kvm_guest=$FILE_MODULES_LOAD_KVM_GUEST
default_file_modules_load_bridge="${DIR_MODULES_LOAD}/20-bridge.conf"
default_file_grub_nvme_dropin="${DIR_GRUB_DEFAULT}/72-nvme-platform.cfg"
default_file_grub_pcie_power_dropin="${DIR_GRUB_DEFAULT}/73-pcie-power.cfg"
default_file_grub_mei_blacklist_dropin="${DIR_GRUB_DEFAULT}/74-intel-mei-blacklist.cfg"
default_file_grub_vfio_dropin="${DIR_GRUB_DEFAULT}/75-intel-vfio.cfg"
default_file_grub_cpu_profile_dropin="${DIR_GRUB_DEFAULT}/80-cpu-profile-flags.cfg"
default_file_grub_gpu_intel_dropin="${DIR_GRUB_DEFAULT}/85-gpu-intel.cfg"
default_file_grub_gpu_amd_dropin="${DIR_GRUB_DEFAULT}/86-gpu-amd.cfg"
default_file_grub_gpu_nvidia_dropin="${DIR_GRUB_DEFAULT}/87-gpu-nvidia.cfg"

target_enable_baremetal_intel=false
target_enable_intel_gpu=false
target_enable_amd_gpu=false
target_enable_nvidia=false
target_enable_nvme_tunables=false
target_enable_vfio=false
target_enable_virt_host=false
target_enable_kvm_guest=false
target_enable_bridge=false
INITRAMFS_PLATFORM_MODULES=
GRAPHICS_INITRAMFS_MODULES=

case "${CPU_CLASS:-}" in
  generic-arm64)
    # arm64 KVM has no vendor-specific kvm_intel/kvm_amd module.
    CPU_KVM_MODULE=""
    CPU_CRC32C_MODULE="crc32c_generic"
    ;;
  amd)
    CPU_KVM_MODULE="kvm_amd"
    CPU_CRC32C_MODULE="crc32c_generic"
    ;;
  intel)
    CPU_KVM_MODULE="kvm_intel"
    CPU_CRC32C_MODULE="crc32c_intel"
    ;;
  *)
    fatal "unsupported CPU class: ${CPU_CLASS:-unset}"
    ;;
esac

case "${HOOK_FAMILY}:${DISK_CLASS:-}" in
  btrfs:nvme)
    target_enable_nvme_tunables=true
    target_enable_virt_host=true
    target_enable_bridge=true
    if [ "${CPU_CLASS:-}" = intel ]; then
      target_enable_baremetal_intel=true
      # Restore the deployed Intel platform reservation, including early VFIO.
      target_enable_vfio=true
      INITRAMFS_PLATFORM_MODULES=$(cat <<'EOF'
intel_wmi_thunderbolt
EOF
)
    fi
    ;;
  btrfs:vm|vm:vm)
    target_enable_kvm_guest=true
    ;;
  vm:*)
    fatal "unsupported VM disk class: ${DISK_CLASS:-unset}"
    ;;
  *)
    fatal "unsupported Btrfs disk class: ${DISK_CLASS:-unset}"
    ;;
esac

if [ "$NVIDIA_CLASS_SELECTED" = true ] && [ "$NVIDIA_GPU_DETECTED" = true ]; then
  target_enable_nvidia=true
fi

# Hardware policy does not implicitly activate virtualization for the base
# desktop. The medium/full physical classes own those packages and stages.
if ! installer_tools_class_selected; then
  target_enable_virt_host=false
  target_enable_bridge=false
  target_enable_vfio=false
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

set_optional_path FILE_MODPROBE_SND_HDA_INTEL "$target_enable_baremetal_intel" "$default_file_modprobe_snd_hda_intel"
set_optional_path FILE_MODPROBE_IWLWIFI "$target_enable_baremetal_intel" "$default_file_modprobe_iwlwifi"
set_optional_path FILE_MODPROBE_E1000E "$target_enable_baremetal_intel" "$default_file_modprobe_e1000e"
set_optional_path FILE_MODPROBE_VFIO "$target_enable_vfio" "$default_file_modprobe_vfio"
set_optional_path FILE_MODPROBE_I915 "$target_enable_intel_gpu" "$default_file_modprobe_i915"
set_optional_path FILE_MODPROBE_AMDGPU "$target_enable_amd_gpu" "$default_file_modprobe_amdgpu"
set_optional_path FILE_MODPROBE_NVIDIA "$target_enable_nvidia" "$default_file_modprobe_nvidia"
set_optional_path FILE_MODPROBE_THUNDERBOLT "$target_enable_baremetal_intel" "$default_file_modprobe_thunderbolt"
set_optional_path FILE_MODPROBE_USBCORE "$target_enable_nvme_tunables" "$default_file_modprobe_usbcore"
set_optional_path FILE_MODPROBE_CFG80211 "$target_enable_baremetal_intel" "$default_file_modprobe_cfg80211"
set_optional_path FILE_MODPROBE_NVME_BLACKLIST "$target_enable_nvme_tunables" "$default_file_modprobe_nvme_blacklist"
set_optional_path FILE_MODPROBE_MEI_BLACKLIST "$target_enable_baremetal_intel" "$default_file_modprobe_mei_blacklist"
set_optional_path FILE_MODPROBE_NVME_OPTS "$target_enable_nvme_tunables" "$default_file_modprobe_nvme_opts"
set_optional_path FILE_UDEV_REGDOM_RULE "$target_enable_baremetal_intel" "$default_file_udev_regdom_rule"
set_optional_path FILE_MODULES_LOAD_VFIO "$target_enable_vfio" "$default_file_modules_load_vfio"
set_optional_path FILE_MODULES_LOAD_VIRT_HOST "$target_enable_virt_host" "$default_file_modules_load_virt_host"
set_optional_path FILE_MODULES_LOAD_KVM_GUEST "$target_enable_kvm_guest" "$default_file_modules_load_kvm_guest"
set_optional_path FILE_MODULES_LOAD_BRIDGE "$target_enable_bridge" "$default_file_modules_load_bridge"
set_optional_path FILE_GRUB_NVME_DROPIN "$target_enable_nvme_tunables" "$default_file_grub_nvme_dropin"
set_optional_path FILE_GRUB_PCIE_POWER_DROPIN "$target_enable_nvme_tunables" "$default_file_grub_pcie_power_dropin"
set_optional_path FILE_GRUB_MEI_BLACKLIST_DROPIN "$target_enable_baremetal_intel" "$default_file_grub_mei_blacklist_dropin"
set_optional_path FILE_GRUB_VFIO_DROPIN "$target_enable_vfio" "$default_file_grub_vfio_dropin"
set_optional_path FILE_GRUB_CPU_PROFILE_DROPIN true "$default_file_grub_cpu_profile_dropin"
set_optional_path FILE_GRUB_GPU_INTEL_DROPIN "$target_enable_intel_gpu" "$default_file_grub_gpu_intel_dropin"
set_optional_path FILE_GRUB_GPU_AMD_DROPIN "$target_enable_amd_gpu" "$default_file_grub_gpu_amd_dropin"
set_optional_path FILE_GRUB_GPU_NVIDIA_DROPIN "$target_enable_nvidia" "$default_file_grub_gpu_nvidia_dropin"

INITRAMFS_PLATFORM_MODULES=$(module_value_to_lines "${INITRAMFS_PLATFORM_MODULES:-}")
GRAPHICS_INITRAMFS_MODULES=$(module_value_to_lines "${GRAPHICS_INITRAMFS_MODULES:-}")
VFIO_INITRAMFS_MODULES=
if [ -n "${FILE_MODULES_LOAD_VFIO:-}" ]; then
  VFIO_INITRAMFS_MODULES=$(cat <<'EOF'
vfio
vfio_pci
vfio_iommu_type1
EOF
)
fi
VIRT_HOST_INITRAMFS_MODULES=
if [ -n "${FILE_MODULES_LOAD_VIRT_HOST:-}" ]; then
  VIRT_HOST_INITRAMFS_MODULES=$(cat <<EOF
kvm
${CPU_KVM_MODULE}
vhost
vhost_net
vhost_vsock
EOF
)
fi

}

run_btrfs_family_late_command() {
HOOK_FAMILY=${1:-}
requested_seed_base=${2:-}
requested_host_profile=${3:-}

btrfs_late_command_mark() {
  if command -v installer_operation_context_repo >/dev/null 2>&1; then
    installer_operation_context_repo FILE_LATE_BTRFS_FAMILY "$1" "$2"
  elif command -v installer_operation_context >/dev/null 2>&1; then
    installer_operation_context unknown "$1" "$2"
  fi
}

btrfs_late_command_mark 187 run_btrfs_family_late_command

case "$HOOK_FAMILY" in
  btrfs|vm) ;;
  *) fatal "unsupported Btrfs-family late_command family: ${HOOK_FAMILY:-unset}" ;;
esac

late_command_shared_init "$requested_seed_base" "$requested_host_profile" "$HOOK_FAMILY"
btrfs_late_command_mark 207 run_btrfs_family_late_command

btrfs_late_command_mark 211 late_command_fetch_common_assets
late_command_fetch_common_assets_file FILE_RUNTIME_BTRFS
btrfs_late_command_mark 213 late_command_load_runtime_env
late_command_load_runtime_env true
btrfs_late_command_mark 215 fetch_grub_profiles_template
late_command_fetch_repo_file FILE_TARGET_DEFAULT_GRUB_PROFILES_TMPL "$TMP_ENV_DIR/grub-profiles" grub-profiles.tmpl
btrfs_late_command_mark 217 fetch_grub_profile_generator
late_command_fetch_repo_file FILE_TARGET_GRUB_D_40_CUSTOM_TMPL "$TMP_ENV_DIR/grub-profile-generator" grub-profile-generator.tmpl
btrfs_late_command_mark 219 late_command_load_host_env
late_command_load_host_env || return $?
# Architecture policy owns the required EFI placeholders and must exist before
# *any* renderer (including the unrelated runtime defaults) is called.
btrfs_late_command_mark 223 late_command_require_class_policy_env
late_command_require_class_policy_env || return $?
btrfs_late_command_mark 225 install_target_runtime_defaults
install_target_runtime_defaults || return $?
btrfs_late_command_mark 227 install_target_wpa_supplicant_runtime_policy
install_target_wpa_supplicant_runtime_policy || return $?
btrfs_late_command_mark 229 installer_ensure_context_loaded
installer_ensure_context_loaded "${SEED_BASE:-}"
CPU_CLASS=$(installer_selected_class_for_purpose cpu 2>__INSTALLER_PATH_DIR_DEV__/null || printf '%s' "${INSTALLER_CPU_CLASS:-}")
DISK_CLASS=$(installer_selected_class_for_purpose storage 2>__INSTALLER_PATH_DIR_DEV__/null || printf '%s' "${INSTALLER_DISK_CLASS:-}")
GPU_CLASSES=$(installer_selected_class_for_purpose gpu 2>__INSTALLER_PATH_DIR_DEV__/null || printf '%s' "${INSTALLER_GPU_CLASS:-}")
BTRFS_SHARED_TARGET_ROOT=$(installer_repo_join_var DIR_HOOKS_TARGET)
NVIDIA_CLASS_SELECTED=false
NVIDIA_GPU_DETECTED=false
TIMESHIFT_PROFILE_ENABLED=false
if installer_class_selected optional/nvidia; then
  NVIDIA_CLASS_SELECTED=true
fi
if installer_class_selected optional/nvidia-legacy; then
  NVIDIA_CLASS_SELECTED=true
fi
if installer_snapshots_enabled; then
  TIMESHIFT_PROFILE_ENABLED=true
fi
PODMAN_CLASS_SELECTED=$(podman_class_selection_state)
if installer_nvidia_gpu_detected; then
  NVIDIA_GPU_DETECTED=true
fi
if [ "$NVIDIA_CLASS_SELECTED" = true ] && [ "$NVIDIA_GPU_DETECTED" != true ]; then
  warn "an NVIDIA addon was selected but no NVIDIA PCI display adapter was detected; NVIDIA target packages and modprobe config stay disabled"
fi
info "late installer context: host_profile=${INSTALLER_HOST_PROFILE:-unset} selected_groups=${INSTALLER_SELECTED_GROUPS:-unset} selected_classes=${INSTALLER_SELECTED_CLASSES:-unset} cpu=${CPU_CLASS:-unset} disk=${DISK_CLASS:-unset} gpu=${GPU_CLASSES:-none} nvidia_class=${NVIDIA_CLASS_SELECTED} nvidia_gpu=${NVIDIA_GPU_DETECTED} timeshift_enabled=${TIMESHIFT_PROFILE_ENABLED} podman_class=${PODMAN_CLASS_SELECTED}"

btrfs_late_command_mark 256 select_btrfs_hardware_policy
select_btrfs_hardware_policy

btrfs_late_command_mark 259 runtime_apply_ssh_from_classes
runtime_apply_ssh_from_classes

ensure_target_volatile_runtime_dirs() {
  prepare_target_volatile_dirs_for_apt
}

ensure_target_boot_mounts() {
  target_is_mounted || fatal "${TARGET_ROOT} is not mounted before GRUB profile installation"

  if ! target_mount_source "${TARGET_ROOT}${DIR_BOOT}" >__INSTALLER_PATH_DIR_DEV__/null 2>&1 &&
    target_mount_source "${TARGET_ROOT}${DIR_BOOT_EFI}" >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
    info "unmounting __INSTALLER_PATH_DIR_BOOT__/efi before restoring __INSTALLER_PATH_DIR_BOOT__ mount"
    if ! umount "${TARGET_ROOT}${DIR_BOOT_EFI}"; then
      fatal "failed to unmount ${TARGET_ROOT}${DIR_BOOT_EFI} before restoring ${TARGET_ROOT}${DIR_BOOT}"
    fi
  fi

  ensure_target_mount "${DEV_PART_BOOT}" "${TARGET_ROOT}${DIR_BOOT}" ext4 "${MNT_BOOT_OPTS}" "__INSTALLER_PATH_DIR_BOOT__"
  ensure_target_mount "${DEV_PART_EFI}" "${TARGET_ROOT}${DIR_BOOT_EFI}" vfat "${MNT_EFI_OPTS}" "__INSTALLER_PATH_DIR_BOOT__/efi"
}

ensure_target_data_mounts() {
  target_is_mounted || fatal "${TARGET_ROOT} is not mounted before data mount restoration"

  if ! target_mount_source "${TARGET_ROOT}${DIR_DATA}" >__INSTALLER_PATH_DIR_DEV__/null 2>&1 &&
    target_mount_source "${TARGET_ROOT}${DIR_DATA_RUN}" >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
    info "unmounting __INSTALLER_PATH_DIR_DATA__/run before restoring __INSTALLER_PATH_DIR_DATA__ mount"
    if ! umount "${TARGET_ROOT}${DIR_DATA_RUN}"; then
      fatal "failed to unmount ${TARGET_ROOT}${DIR_DATA_RUN} before restoring ${TARGET_ROOT}${DIR_DATA}"
    fi
  fi

  ensure_target_mount "${DEV_PART_DATA}" "${TARGET_ROOT}${DIR_DATA}" xfs "${MNT_XFS_DATA_OPTS}" "__INSTALLER_PATH_DIR_DATA__"
}

ensure_target_volatile_backing_mounts() {
  target_is_mounted || fatal "${TARGET_ROOT} is not mounted before volatile backing mount restoration"

  if tmpfs_policy_enabled TMPFS_VAR_LOG &&
    ! target_mount_source "${TARGET_ROOT}${DIR_VAR_LOG}" >__INSTALLER_PATH_DIR_DEV__/null 2>&1 &&
    target_mount_source "${TARGET_ROOT}${DIR_VAR_LOG_JOURNAL}" >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
    info "unmounting ${DIR_VAR_LOG_JOURNAL} before restoring ${DIR_VAR_LOG} backing directories"
    if ! umount "${TARGET_ROOT}${DIR_VAR_LOG_JOURNAL}"; then
      fatal "failed to unmount ${TARGET_ROOT}${DIR_VAR_LOG_JOURNAL} before restoring ${TARGET_ROOT}${DIR_VAR_LOG}"
    fi
  fi

  ensure_target_data_mounts
  ensure_target_mount "${DEV_PART_VAR_LOG_JOURNAL}" "${TARGET_ROOT}${DIR_VAR_LOG_JOURNAL}" ext4 "${MNT_VAR_LOG_JOURNAL_OPTS}" "${DIR_VAR_LOG_JOURNAL}"
  ensure_target_mount "${DEV_PART_VAR_TMP}" "${TARGET_ROOT}${DIR_VAR_TMP}" ext4 "${MNT_VAR_TMP_OPTS}" "${DIR_VAR_TMP}"
  ensure_target_volatile_runtime_dirs
}

write_target_fstab() {
  root_src=$(device_source "${DEV_PART_ROOT}")
  home_src=$(device_source "${DEV_PART_HOME}")
  opt_src=$(device_source "${DEV_PART_OPT}")
  data_src=$(device_source "${DEV_PART_DATA}")
  pool_src=$(device_source "${DEV_PART_POOL}")
  boot_src=$(device_source "${DEV_PART_BOOT}")
  efi_src=$(device_source "${DEV_PART_EFI}")
  vtmp_src=$(device_source "${DEV_PART_VAR_TMP}")
  vjournal_src=$(device_source "${DEV_PART_VAR_LOG_JOURNAL}")

  {
    printf '%s\n' '# Kernel and boot filesystems'
    fstab_entry "proc" "__INSTALLER_PATH_DIR_PROC__" "proc" "defaults" 0 0
    fstab_entry "${boot_src}" "${DIR_BOOT}" "ext4" "${MNT_BOOT_OPTS}" 0 2
    fstab_entry "${efi_src}" "${DIR_BOOT_EFI}" "vfat" "${MNT_EFI_OPTS}" 0 2
    printf '%s\n' '# System subvolumes'
    fstab_entry "${root_src}" "/" "btrfs" "${MNT_BTRFS_ROOT_OPTS}" 0 0
    fstab_entry "${root_src}" "${DIR_ROOT_HOME}" "btrfs" "${MNT_ROOT_HOME_OPTS}" 0 0
    fstab_entry "${root_src}" "${DIR_SRV}" "btrfs" "${MNT_SRV_OPTS}" 0 0
    fstab_entry "${root_src}" "${DIR_USR_LOCAL}" "btrfs" "${MNT_USR_LOCAL_OPTS}" 0 0
    fstab_entry "${root_src}" "${DIR_VAR_SPOOL}" "btrfs" "${MNT_VAR_SPOOL_OPTS}" 0 0
    printf '%s\n' '# Home subvolumes'
    fstab_entry "${home_src}" "${DIR_HOME}" "btrfs" "${MNT_BTRFS_HOME_OPTS}" 0 0
    fstab_entry "${home_src}" "${DIR_HOME_DOCUMENTS}" "btrfs" "${MNT_HOME_DOCUMENTS_OPTS}" 0 0
    fstab_entry "${home_src}" "${DIR_HOME_DOWNLOADS}" "btrfs" "${MNT_HOME_DOWNLOADS_OPTS}" 0 0
    fstab_entry "${home_src}" "${DIR_HOME_PUBLIC}" "btrfs" "${MNT_HOME_PUBLIC_OPTS}" 0 0
    fstab_entry "${home_src}" "${DIR_HOME_PICTURES}" "btrfs" "${MNT_HOME_PICTURES_OPTS}" 0 0
    fstab_entry "${home_src}" "${DIR_HOME_WORKSPACE}" "btrfs" "${MNT_HOME_WORKSPACE_OPTS}" 0 0
    fstab_entry "${home_src}" "${DIR_HOME_SYNCTHING}" "btrfs" "${MNT_HOME_SYNCTHING_OPTS}" 0 0
    printf '%s\n' '# Application and data mounts'
    fstab_entry "${opt_src}" "${DIR_OPT}" "btrfs" "${MNT_OPT_OPTS}" 0 0
    fstab_entry "${data_src}" "${DIR_DATA}" "xfs" "${MNT_XFS_DATA_OPTS}" 0 0
    fstab_entry "${pool_src}" "${DIR_POOL}" "xfs" "${MNT_XFS_POOL_OPTS}" 0 0
    if tmpfs_policy_enabled TMPFS_DATA_RUN; then
        fstab_entry "tmpfs" "${DIR_DATA_RUN}" "tmpfs" "${MNT_DATA_RUN_TMPFS_OPTS}" 0 0
      fi
    printf '%s\n' '# Temporary storage and logs'
    fstab_entry "${vtmp_src}" "${DIR_VAR_TMP}" "ext4" "${MNT_VAR_TMP_OPTS}" 0 2
    write_rsyslog_spool_fstab
    if tmpfs_policy_enabled TMPFS_VAR_LOG; then
        fstab_entry "tmpfs" "${DIR_VAR_LOG}" "tmpfs" "${MNT_VAR_LOG_TMPFS_OPTS}" 0 0
      fi
    if tmpfs_policy_enabled TMPFS_VAR_CACHE; then
        fstab_entry "tmpfs" "${DIR_VAR_CACHE}" "tmpfs" "${MNT_VAR_CACHE_TMPFS_OPTS}" 0 0
      fi
    if tmpfs_policy_enabled TMPFS_VAR_LIB_APT_LISTS; then
        fstab_entry "tmpfs" "${DIR_APT_LISTS}" "tmpfs" "${MNT_APT_LISTS_TMPFS_OPTS}" 0 0
      fi
    if tmpfs_policy_enabled TMPFS_SYSTEMD_COREDUMP; then
        fstab_entry "tmpfs" "${DIR_SYSTEMD_COREDUMP}" "tmpfs" "${MNT_COREDUMP_TMPFS_OPTS}" 0 0
      fi
    fstab_entry "tmpfs" "${DIR_TMP}" "tmpfs" "${MNT_TMP_OPTS}" 0 0
    if tmpfs_policy_enabled TMPFS_DEV_SHM; then
        fstab_entry "tmpfs" "${DIR_DEV_SHM}" "tmpfs" "${MNT_DEV_SHM_OPTS}" 0 0
      fi
    printf '%s\n' '# Persistent journal'
    fstab_entry "${vjournal_src}" "${DIR_VAR_LOG_JOURNAL}" "ext4" "${MNT_VAR_LOG_JOURNAL_OPTS}" 0 2
  } | write_target_fstab_records
  cp "${TARGET_ROOT}${DIR_ETC}/fstab" "${TARGET_ROOT}${DIR_ETC}/fstab.layout-cache" 2>__INSTALLER_PATH_DIR_DEV__/null || true
  cp "${TARGET_ROOT}${DIR_ETC}/fstab" "${TARGET_ROOT}${DIR_ETC}/fstab.orig" 2>__INSTALLER_PATH_DIR_DEV__/null || true
}

target_has_btrfs_filesystems() {
  if [ "${TARGET_HAS_BTRFS_FILESYSTEMS_READY:-0}" = 1 ]; then
    [ "${TARGET_HAS_BTRFS_FILESYSTEMS:-false}" = true ]
    return
  fi

  if [ -r ${TARGET_ROOT}${DIR_ETC}/fstab ]; then
    while IFS=' ' read -r fstab_source _fstab_mount fstab_type _fstab_rest || [ -n "${fstab_source:-}" ]; do
      case "$fstab_source" in
        ''|'#'*)
          continue
          ;;
      esac
      if [ "$fstab_type" = "btrfs" ]; then
        TARGET_HAS_BTRFS_FILESYSTEMS=true
        TARGET_HAS_BTRFS_FILESYSTEMS_READY=1
        return 0
      fi
    done <${TARGET_ROOT}${DIR_ETC}/fstab
  fi

  for dev in "${DEV_PART_ROOT:-}" "${DEV_PART_HOME:-}" "${DEV_PART_OPT:-}"; do
    [ -n "$dev" ] || continue
    [ -b "$dev" ] || continue
    fs_type=$(blkid -s TYPE -o value "$dev" 2>__INSTALLER_PATH_DIR_DEV__/null || true)
    if [ "$fs_type" = "btrfs" ]; then
      TARGET_HAS_BTRFS_FILESYSTEMS=true
      TARGET_HAS_BTRFS_FILESYSTEMS_READY=1
      return 0
    fi
  done

  TARGET_HAS_BTRFS_FILESYSTEMS=false
  TARGET_HAS_BTRFS_FILESYSTEMS_READY=1
  return 1
}

load_target_btrfs_optional_package_state() {
  if [ "${TARGET_BTRFS_OPTIONAL_PACKAGE_STATE_LOADED:-0}" = 1 ]; then
    return 0
  fi

  require_in_target "Btrfs optional package detection"
  TARGET_HAS_BTRFSMAINTENANCE_PACKAGE=0

  target_btrfs_package_state=$(
    capture_in_target "detect target Btrfs optional packages" __INSTALLER_PATH_DIR_BIN__/sh -c '
set -eu

check_payload_paths() {
  for payload_path in "$@"; do
    [ -n "$payload_path" ] || continue
    if [ -x "$payload_path" ] || [ -e "$payload_path" ]; then
      printf "1\n"
      return 0
    fi
  done

  printf "0\n"
}

printf "TARGET_HAS_BTRFSMAINTENANCE_PACKAGE=%s\n" "$(
  check_payload_paths \
    __INSTALLER_PATH_DIR_ETC__/default/btrfsmaintenance \
    __INSTALLER_PATH_DIR_USR_LIB__/systemd/system/btrfs-scrub.timer \
    __INSTALLER_PATH_DIR_USR_SHARE__/btrfsmaintenance/btrfs-scrub.sh
)"
' sh
  )

  while IFS='=' read -r state_name state_value || [ -n "${state_name:-}" ]; do
    [ -n "${state_name:-}" ] || continue
    case "$state_name:$state_value" in
      TARGET_HAS_BTRFSMAINTENANCE_PACKAGE:0|TARGET_HAS_BTRFSMAINTENANCE_PACKAGE:1)
        eval "$state_name=$state_value"
        ;;
      *)
        installer_fatal "invalid target Btrfs optional package state: ${state_name}=${state_value}"
        ;;
    esac
  done <<EOF
$target_btrfs_package_state
EOF

  TARGET_BTRFS_OPTIONAL_PACKAGE_STATE_LOADED=1
}


configure_target_btrfsmaintenance() {
  if ! target_has_btrfs_filesystems; then
    info "target has no Btrfs filesystems; skipping btrfsmaintenance"
    return 0
  fi

  load_target_btrfs_optional_package_state
  if [ "${TARGET_HAS_BTRFSMAINTENANCE_PACKAGE}" != 1 ]; then
    installer_warn "btrfsmaintenance is not installed; skipping optional Btrfs maintenance timers"
    return 0
  fi
  ensure_target_volatile_runtime_dirs

  stage_target_asset "$(installer_hardware_asset_path disk "${DISK_CLASS}" "etc/default/btrfsmaintenance")" "${FILE_BTRFSMAINTENANCE_DEFAULT}" 0644
  stage_target_systemd_unit_enabled btrfs-scrub.timer system
  stage_target_systemd_unit_enabled btrfs-balance.timer system
  unstage_target_systemd_unit_enabled btrfs-trim.timer system
}

prepare_target_deferred_tmpfs_roots() {
  journal_mount="${TARGET_ROOT}${DIR_VAR_LOG_JOURNAL}"

  if tmpfs_policy_enabled TMPFS_VAR_LOG &&
    target_mount_source "$journal_mount" >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
    info "unmounting ${journal_mount} so the installed system remounts the persistent journal cleanly on reboot"
    umount "$journal_mount" || {
      fatal "failed to unmount ${journal_mount} while preparing deferred tmpfs roots"
    }
  fi

  rmdir "$journal_mount" 2>__INSTALLER_PATH_DIR_DEV__/null || true
}

write_target_kernel_tunables() {
  stage_target_asset_if_path "$(installer_hardware_asset_path cpu "${CPU_CLASS}" "etc/modprobe.d/78-snd-hda-intel.conf")" "${FILE_MODPROBE_SND_HDA_INTEL:-}" "${DIR_MODPROBE_D}/78-snd-hda-intel.conf" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path cpu "${CPU_CLASS}" "etc/modprobe.d/76-iwlwifi.conf")" "${FILE_MODPROBE_IWLWIFI:-}" "${DIR_MODPROBE_D}/76-iwlwifi.conf" 0644
  stage_target_hardware_spec
  stage_target_asset_if_path "$(installer_hardware_asset_path cpu "${CPU_CLASS}" "etc/modprobe.d/77-e1000e.conf")" "${FILE_MODPROBE_E1000E:-}" "${DIR_MODPROBE_D}/77-e1000e.conf" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path cpu "${CPU_CLASS}" "etc/modprobe.d/70-vfio-pci.conf")" "${FILE_MODPROBE_VFIO:-}" "${DIR_MODPROBE_D}/70-vfio-pci.conf" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path gpu intel-uhd etc/modprobe.d/80-i915.conf)" "${FILE_MODPROBE_I915:-}" "${DIR_MODPROBE_D}/80-i915.conf" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path gpu amd-radeon etc/modprobe.d/81-amdgpu.conf)" "${FILE_MODPROBE_AMDGPU:-}" "${DIR_MODPROBE_D}/81-amdgpu.conf" 0644
  if [ "$target_enable_nvidia" = true ]; then
    stage_target_asset "$(installer_repo_file_value FILE_TARGET_MODPROBE_D_50_NOUVEAU_BLACKLIST)" "${DIR_MODPROBE_D}/50-nouveau-blacklist.conf" 0644
    stage_target_asset "$(installer_hardware_asset_path gpu nvidia etc/modprobe.d/82-nvidia.conf)" "${FILE_MODPROBE_NVIDIA}" 0644
  else
    remove_target_asset "${DIR_MODPROBE_D}/50-nouveau-blacklist.conf"
    remove_target_asset "${DIR_MODPROBE_D}/82-nvidia.conf"
  fi
  stage_target_asset_if_path "$(installer_hardware_asset_path cpu "${CPU_CLASS}" "etc/modprobe.d/71-thunderbolt.conf")" "${FILE_MODPROBE_THUNDERBOLT:-}" "${DIR_MODPROBE_D}/71-thunderbolt.conf" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path disk "${DISK_CLASS}" "etc/modprobe.d/74-usbcore.conf")" "${FILE_MODPROBE_USBCORE:-}" "${DIR_MODPROBE_D}/74-usbcore.conf" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path cpu "${CPU_CLASS}" "etc/modprobe.d/75-cfg80211.conf")" "${FILE_MODPROBE_CFG80211:-}" "${DIR_MODPROBE_D}/75-cfg80211.conf" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path disk "${DISK_CLASS}" "etc/modprobe.d/72-nvme-blacklist.conf")" "${FILE_MODPROBE_NVME_BLACKLIST:-}" "${DIR_MODPROBE_D}/72-nvme-blacklist.conf" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path cpu "${CPU_CLASS}" "etc/modprobe.d/05-mei-blacklist.conf")" "${FILE_MODPROBE_MEI_BLACKLIST:-}" "${DIR_MODPROBE_D}/05-mei-blacklist.conf" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path disk "${DISK_CLASS}" "etc/modprobe.d/73-nvme.conf")" "${FILE_MODPROBE_NVME_OPTS:-}" "${DIR_MODPROBE_D}/73-nvme.conf" 0644
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_MODPROBE_D_20_VIRTUALIZATION_BLACKLIST)" "${FILE_MODPROBE_VM_BLACKLIST}" 0644
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_MODPROBE_D_30_LEGACY_BUS_BLACKLIST)" "${FILE_MODPROBE_LEGACY_BLACKLIST}" 0644
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_MODPROBE_D_40_FILESYSTEM_BLACKLIST)" "${FILE_MODPROBE_FILESYSTEM_BLACKLIST}" 0644
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_MODPROBE_D_60_SES_BLACKLIST)" "${FILE_MODPROBE_SES_BLACKLIST}" 0644
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_MODPROBE_D_10_NET_PROTO_BLACKLIST)" "${FILE_MODPROBE_NETPROTO_BLACKLIST}" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path cpu "${CPU_CLASS}" "etc/udev/rules.d/85-wifi-regdom.rules")" "${FILE_UDEV_REGDOM_RULE:-}" "${DIR_UDEV_RULES}/85-wifi-regdom.rules" 0644

  stage_target_asset "$(installer_hardware_asset_path disk "${DISK_CLASS}" "etc/modules-load.d/10-btrfs.conf")" "${FILE_MODULES_LOAD_BTRFS}" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path disk "${DISK_CLASS}" "etc/modules-load.d/20-bridge.conf")" "${FILE_MODULES_LOAD_BRIDGE:-}" "${DIR_MODULES_LOAD}/20-bridge.conf" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path disk "${DISK_CLASS}" "etc/modules-load.d/25-kvm-guest.conf")" "${FILE_MODULES_LOAD_KVM_GUEST:-}" "${DIR_MODULES_LOAD}/25-kvm-guest.conf" 0644
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_MODULES_LOAD_D_30_STORAGE_MEMORY)" "${FILE_MODULES_LOAD_STORAGE_MEMORY}" 0644
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_MODULES_LOAD_D_32_TPM)" "${FILE_MODULES_LOAD_TPM}" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path cpu "${CPU_CLASS}" "etc/modules-load.d/35-vfio.conf")" "${FILE_MODULES_LOAD_VFIO:-}" "${DIR_MODULES_LOAD}/35-vfio.conf" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path cpu "${CPU_CLASS}" "etc/modules-load.d/37-virt-host.conf")" "${FILE_MODULES_LOAD_VIRT_HOST:-}" "${DIR_MODULES_LOAD}/37-virt-host.conf" 0644
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_SYSCTL_D_10_BASELINE)" "${FILE_SYSCTL_BASELINE}" 0644
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_SYSCTL_D_20_STORAGE_MEMORY)" "${FILE_SYSCTL_STORAGE_MEMORY}" 0644
  render_target_asset "$(installer_repo_file_value FILE_TARGET_SYSCTL_D_25_STORAGE_STATIC_TMPL)" "${FILE_SYSCTL_FAMILY_OVERRIDE}" 0644
  render_target_asset "$(installer_repo_file_value FILE_TARGET_SYSCTL_D_PROFILES_BALANCED_40_BALANCED_TMPL)" "${FILE_SYSCTL_PROFILE_DEFAULT}" 0644
  render_target_asset "$(installer_repo_file_value FILE_TARGET_SYSCTL_D_PROFILES_HARDENED_40_HARDENED_TMPL)" "${FILE_SYSCTL_PROFILE_HARDENED}" 0644
  render_target_asset "$(installer_repo_file_value FILE_TARGET_SYSCTL_D_PROFILES_PERFORMANCE_40_PERFORMANCE_TMPL)" "${FILE_SYSCTL_PROFILE_PERFORMANCE}" 0644

  stage_target_asset "$(installer_repo_file_value FILE_TARGET_INITRAMFS_CONF_D_99_COMPRESS)" "${FILE_INITRAMFS_CUSTOM_CONF}" 0644
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_INITRAMFS_CONF_D_RESUME)" "${FILE_INITRAMFS_RESUME}" 0644
  render_target_asset "$(installer_hardware_asset_path disk "${DISK_CLASS}" "etc/initramfs-tools/modules.tmpl")" "${FILE_INITRAMFS_MODULES}" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path disk "${DISK_CLASS}" "etc/default/grub.d/72-nvme-platform.cfg")" "${FILE_GRUB_NVME_DROPIN:-}" "${DIR_GRUB_DEFAULT}/72-nvme-platform.cfg" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path disk "${DISK_CLASS}" "etc/default/grub.d/73-pcie-power.cfg")" "${FILE_GRUB_PCIE_POWER_DROPIN:-}" "${DIR_GRUB_DEFAULT}/73-pcie-power.cfg" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path cpu "${CPU_CLASS}" "etc/default/grub.d/74-intel-mei-blacklist.cfg")" "${FILE_GRUB_MEI_BLACKLIST_DROPIN:-}" "${DIR_GRUB_DEFAULT}/74-intel-mei-blacklist.cfg" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path cpu "${CPU_CLASS}" "etc/default/grub.d/75-intel-vfio.cfg")" "${FILE_GRUB_VFIO_DROPIN:-}" "${DIR_GRUB_DEFAULT}/75-intel-vfio.cfg" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path cpu "${CPU_CLASS}" "etc/default/grub.d/80-cpu-profile-flags.cfg")" "${FILE_GRUB_CPU_PROFILE_DROPIN:-}" "${DIR_GRUB_DEFAULT}/80-cpu-profile-flags.cfg" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path gpu intel-uhd etc/default/grub.d/85-gpu-intel.cfg)" "${FILE_GRUB_GPU_INTEL_DROPIN:-}" "${DIR_GRUB_DEFAULT}/85-gpu-intel.cfg" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path gpu amd-radeon etc/default/grub.d/86-gpu-amd.cfg)" "${FILE_GRUB_GPU_AMD_DROPIN:-}" "${DIR_GRUB_DEFAULT}/86-gpu-amd.cfg" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path gpu nvidia etc/default/grub.d/87-gpu-nvidia.cfg)" "${FILE_GRUB_GPU_NVIDIA_DROPIN:-}" "${DIR_GRUB_DEFAULT}/87-gpu-nvidia.cfg" 0644

  configure_target_nvidia_power_management "$target_enable_nvidia"

  stage_target_asset "$(installer_repo_file_value FILE_TARGET_LIBEXEC_SWAP_FALLBACK_SETUP_TMPL)" "${FILE_SWAP_FALLBACK_HELPER}" 0755
  render_target_template "$TMP_ENV_DIR/swap-fallback.service.tmpl" "${TARGET_ROOT}${FILE_SWAP_FALLBACK_SERVICE}" 0644

  stage_target_common_storage_maintenance_assets
}








btrfs_late_command_mark 722 write_target_fstab
write_target_fstab
btrfs_late_command_mark 724 ensure_target_boot_mounts
ensure_target_boot_mounts
btrfs_late_command_mark 726 ensure_target_volatile_backing_mounts
ensure_target_volatile_backing_mounts
btrfs_late_command_mark 728 ensure_target_managed_runtime_storage_roots
ensure_target_managed_runtime_storage_roots
btrfs_late_command_mark 730 provision_target_identity
provision_target_identity
btrfs_late_command_mark 732 stage_target_docs_index
stage_target_docs_index
btrfs_late_command_mark 734 stage_target_account_shell_assets
stage_target_account_shell_assets
btrfs_late_command_mark 736 ensure_target_account_home_ownership
ensure_target_account_home_ownership
btrfs_late_command_mark 738 install_target_account_shell_assets
install_target_account_shell_assets
btrfs_late_command_mark 740 install_target_account_sudoers
install_target_account_sudoers
btrfs_late_command_mark 742 configure_target_shared_account_access
configure_target_shared_account_access
btrfs_late_command_mark 744 repair_target_pkgsel_include_packages
repair_target_pkgsel_include_packages
btrfs_late_command_mark 750 install_target_mullvad_vpn_if_selected
install_target_mullvad_vpn_if_selected
btrfs_late_command_mark 752 stage_target_secure_boot_runtime_assets
stage_target_secure_boot_runtime_assets
btrfs_late_command_mark 754 stage_target_xssh_helpers
stage_target_xssh_helpers
btrfs_late_command_mark 756 provision_target_ssh_client
provision_target_ssh_client
btrfs_late_command_mark 758 provision_target_git_ssh_identity
provision_target_git_ssh_identity
btrfs_late_command_mark 760 configure_target_rootless_podman_if_selected
configure_target_rootless_podman_if_selected
btrfs_late_command_mark 762 sanitize_target_xfs_scrub_systemd_units
sanitize_target_xfs_scrub_systemd_units
btrfs_late_command_mark 764 install_target_wpa_supplicant_runtime_policy
install_target_wpa_supplicant_runtime_policy
btrfs_late_command_mark 766 configure_target_smartmontools_defaults
configure_target_smartmontools_defaults
btrfs_late_command_mark 768 ensure_target_secure_boot_packages
ensure_target_secure_boot_packages
btrfs_late_command_mark 770 configure_target_btrfsmaintenance
configure_target_btrfsmaintenance
btrfs_late_command_mark 774 provision_target_ssh_server
provision_target_ssh_server
btrfs_late_command_mark 776 install_target_managed_network_handoff
install_target_managed_network_handoff
btrfs_late_command_mark 778 configure_target_apparmor_auditd
configure_target_apparmor_auditd
btrfs_late_command_mark 780 install_target_firstboot_logger
install_target_firstboot_logger
btrfs_late_command_mark 782 write_target_grub_dropins
write_target_grub_dropins
btrfs_late_command_mark 784 set_target_grub_default_entry
set_target_grub_default_entry
btrfs_late_command_mark 786 write_target_kernel_tunables
write_target_kernel_tunables
btrfs_late_command_mark 788 prepare_target_secure_boot_runtime
prepare_target_secure_boot_runtime
btrfs_late_command_mark 790 sign_target_installed_kernel_modules
sign_target_installed_kernel_modules
btrfs_late_command_mark 792 dedupe_target_tmpfiles_legacy_lock
dedupe_target_tmpfiles_legacy_lock
btrfs_late_command_mark 794 enable_target_storage_units
enable_target_storage_units
btrfs_late_command_mark 796 set_target_default_unit
set_target_default_unit
btrfs_late_command_mark 798 disable_stock_kernel_menu
disable_stock_kernel_menu

if target_exec_available; then
  # Regenerate signed kernels/initrds BEFORE discovering boot menu entries.
  btrfs_late_command_mark 803 repair_target_installed_kernels
  repair_target_installed_kernels
  btrfs_late_command_mark 805 require_target_grub_installed
  require_target_grub_installed
  btrfs_late_command_mark 807 install_target_grub_profiles
  install_target_grub_profiles
  btrfs_late_command_mark 813 require_target_dualboot_os_prober_package
  require_target_dualboot_os_prober_package
  btrfs_late_command_mark 815 run_target_grub_config_update
  run_target_grub_config_update
  # This is the unconditional d-i late reset point: GRUB, shim, MokManager,
  # kernel/initrd and grub.cfg are complete before mokutil is called. Reset
  # failures remain warnings so installation can finish.
  if (finalize_target_secure_boot_mok_reset); then
    :
  else
    installer_warn "MOK reset/boot preparation failed after GRUB installation; continuing installation"
  fi
  btrfs_late_command_mark 825 sync_target_secure_boot_bundle_to_installer_usb
  sync_target_secure_boot_bundle_to_installer_usb
  btrfs_late_command_mark 827 close_target_secure_boot_state
  close_target_secure_boot_state
fi

  btrfs_late_command_mark 831 configure_target_dbus_broker
configure_target_dbus_broker
  btrfs_late_command_mark 833 prepare_target_deferred_tmpfs_roots
prepare_target_deferred_tmpfs_roots
  btrfs_late_command_mark 835 prepare_target_volatile_mountpoints_for_first_boot
prepare_target_volatile_mountpoints_for_first_boot
  btrfs_late_command_mark 837 stage_target_logging_foundation
stage_target_logging_foundation || return $?
  btrfs_late_command_mark 839 installer_archive_logs_to_target
installer_archive_logs_to_target copy || true
}
