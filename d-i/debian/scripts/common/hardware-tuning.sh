#!/bin/sh
# Profile-gated shared backend. No tuning operation is performed in d-i.

profile_hardware_stage_asset() {
  case "$1" in
    FILE_*) hardware_source=$(installer_repo_file_value "$1") ;;
    *) hardware_source=$(installer_repo_asset_path DIR_HOOKS_TARGET "$1") ;;
  esac
  stage_target_asset "$hardware_source" "$2" "$3"
}

profile_hardware_intel_detected() {
  awk '$1 == "vendor_id" { seen=1; if ($3 != "GenuineIntel") bad=1 }
       END { exit !(seen && !bad) }' __INSTALLER_PATH_DIR_PROC__/cpuinfo
}

install_profile_hardware_tuning() (
  set -eu
  umask 077
  if command -v installer_operation_context_repo >/dev/null 2>&1; then
    installer_operation_context_repo scripts/common/hardware-tuning.sh 17 install_profile_hardware_tuning
  fi
  for hardware_flag in "${HARDWARE_INTEL_CPU_TUNING_ENABLE:-false}" "${HARDWARE_NVIDIA_GPU_TUNING_ENABLE:-false}"; do
    case "$hardware_flag" in true|false) ;; *) installer_fatal "hardware tuning enable flags must be literal true or false"; exit 1 ;; esac
  done
  hardware_vendors=
  if [ "${HARDWARE_INTEL_CPU_TUNING_ENABLE:-false}" = true ] && profile_hardware_intel_detected; then
    hardware_vendors=intel
  fi
  if [ "${HARDWARE_NVIDIA_GPU_TUNING_ENABLE:-false}" = true ] &&
      installer_nvidia_class_selected && installer_nvidia_selected_gpu_detected; then
    hardware_vendors="${hardware_vendors:+${hardware_vendors} }nvidia"
  fi
  if [ -z "$hardware_vendors" ]; then
    installer_info "hardware tuning not installed: disabled or hardware/class gates not satisfied"
    return 0
  fi

  for hardware_module in common engine broker client policy_owner system_state power_profiles $hardware_vendors; do
    profile_hardware_stage_asset "usr/local/lib/hardware_tuning/${hardware_module}.py" "${DIR_HARDWARE_TUNING}/${hardware_module}.py" 0644 || exit 1
  done
  profile_hardware_stage_asset hooks/target/usr/local/bin/common/labwc-hardware-tuning __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-hardware-tuning 0755 || exit 1
  profile_hardware_stage_asset hooks/target/usr/local/libexec/common/hardware-tuningd __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/hardware-tuningd 0755 || exit 1
  profile_hardware_stage_asset hooks/target/usr/local/libexec/common/hardware-tuning-worker __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/hardware-tuning-worker 0755 || exit 1
  profile_hardware_stage_asset hooks/target/usr/local/libexec/common/hardware-tuning-policy __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/hardware-tuning-policy 0755 || exit 1
  profile_hardware_stage_asset hooks/target/usr/local/libexec/common/hardware-tuning-power-profiles __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/hardware-tuning-power-profiles 0755 || exit 1
  profile_hardware_stage_asset hooks/target/etc/apparmor.d/common/hardware-tuning __INSTALLER_PATH_DIR_ETC__/apparmor.d/hardware-tuning 0644 || exit 1
  hardware_bridges=
  if [ "$INSTALLER_HOST_VARIANT" = desktop ]; then hardware_bridges="desktop-parent fuzzel-parent management-parent"; fi
  for hardware_bridge in $hardware_bridges; do
    profile_hardware_stage_asset "etc/apparmor.d/abstractions/hardware-tuning-${hardware_bridge}" "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/hardware-tuning-${hardware_bridge}" 0644 || exit 1
  done
  for hardware_vendor in $hardware_vendors; do
    profile_hardware_stage_asset "etc/apparmor.d/abstractions/hardware-tuning-${hardware_vendor}" "__INSTALLER_PATH_DIR_ETC__/apparmor.d/abstractions/hardware-tuning-${hardware_vendor}" 0644 || exit 1
  done
  run_in_target "apply selected AppArmor mode to staged hardware tuning policy" \
    __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/apparmor-modes-run --no-reload || exit 1

  : "${LATE_COMMAND_HOST_ENV:?hardware tuning requires the loaded host profile}"
  : "${ACCOUNT_USERNAME:?hardware tuning requires the configured operator}"
  hardware_stage=$(target_private_stage_dir hardware-tuning) || exit 1
  hardware_stage_host=$(target_asset_host_path "$hardware_stage") || exit 1
  trap 'rm -rf -- "$hardware_stage_host"' 0
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  # Never copy the account file or unrelated (potentially secret) profile data.
  # The Python installer parses these as literals; it never sources/evals them.
  (umask 077; awk '/^HARDWARE_(INTEL_CPU_TUNING|NVIDIA_GPU_TUNING|TUNING)_[A-Z0-9_]+=/ {print}' \
      "$LATE_COMMAND_HOST_ENV" >"${hardware_stage_host}/policy.env") || exit 1
  fetch_hook "$(installer_repo_file_value scripts/common/hardware-tuning-config.py)" "${hardware_stage_host}/config.py" || exit 1
  hardware_config_rendered="${hardware_stage_host}/config.py.rendered"
  installer_apply_scalar_placeholders \
    "${hardware_stage_host}/config.py" "$hardware_config_rendered" || exit 1
  mv -f "$hardware_config_rendered" "${hardware_stage_host}/config.py" || exit 1
  installer_assert_no_unresolved_installer_placeholders \
    "${hardware_stage_host}/config.py" hardware-tuning-config.py || exit 1
  chmod 0700 "${hardware_stage_host}/config.py" || exit 1
  fetch_hook "$(installer_repo_file_value scripts/common/hardware-tuning-assets.list)" "${hardware_stage_host}/assets.list" || exit 1
  while IFS= read -r hardware_asset; do
    case "$hardware_asset" in etc/systemd/*|etc/hardware-tuning/*|etc/dbus-1/system.d/*) ;; *) exit 1 ;; esac
    if [ "$INSTALLER_HOST_VARIANT" = server ]; then case "$hardware_asset" in etc/systemd/user/*) continue ;; esac; fi
    case "$hardware_asset" in *..*|*//*|*[!A-Za-z0-9_./-]*) exit 1 ;; esac
    install -d -m 0700 "${hardware_stage_host}/templates/${hardware_asset%/*}" || exit 1
    hardware_template_path="${hardware_stage_host}/templates/${hardware_asset}"
    fetch_hook "$(installer_repo_asset_path DIR_HOOKS_TARGET "$hardware_asset")" "$hardware_template_path" || exit 1
    hardware_template_rendered="${hardware_template_path}.rendered"
    installer_apply_scalar_placeholders "$hardware_template_path" "$hardware_template_rendered" || exit 1
    mv -f "$hardware_template_rendered" "$hardware_template_path" || exit 1
  done < "${hardware_stage_host}/assets.list" || exit 1
  # Intentional split: hardware_vendors is assembled ONLY from literal names.
  # shellcheck disable=SC2086
  run_in_target "install gated hardware tuning profiles and lifecycle units" \
    __INSTALLER_PATH_DIR_USR_BIN__/python3 -I "${hardware_stage}/config.py" "${hardware_stage}/policy.env" "$ACCOUNT_USERNAME" "${hardware_stage}/templates" "$INSTALLER_HOST_VARIANT" \
    "${DIR_INSTALLER_TARGET_DEFAULTS}/desktop" $hardware_vendors || exit 1
  run_in_target "validate hardware tuning AppArmor policy without loading into the installer kernel" \
    __INSTALLER_PATH_DIR_USR_SBIN__/apparmor_parser --skip-kernel-load --skip-cache __INSTALLER_PATH_DIR_ETC__/apparmor.d/hardware-tuning || exit 1
  installer_info "installed hardware tuning vendors=${hardware_vendors} autostart=${HARDWARE_TUNING_AUTOSTART_ENABLE:-false}"
)
