#!/bin/sh
# Headless boot-profile publication with the shared XanMod signing lifecycle.
# Debian owns EFI shim/GRUB; MOK certificate enrollment stays explicit.
set -eu
runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}
# shellcheck disable=SC1090
. "$bootstrap_lib"
bootstrap_source_common_lib ""
SEED_BASE=$(installer_seed_base "")
installer_ensure_context_loaded "$SEED_BASE"
[ "$INSTALLER_HOST_VARIANT" = server ] || installer_fatal 'headless boot stage requires server roles'
TMP_ENV_DIR=$DIR_INSTALLER_LATE_ENV
profile="${TMP_ENV_DIR}/server-boot.env"
installer_fetch_host_env "$SEED_BASE" "$INSTALLER_HOST_PROFILE" "$profile" 0600
installer_load_data_env "$profile"
installer_load_primary_account
installer_assert_class_plan
bootstrap_source_common_support_libs "$SEED_BASE" "${TMP_ENV_DIR}/server-boot-support" fetch hook target
for module in scripts/late/core.sh scripts/late/target-assets.sh scripts/late/grub.sh; do
  module_file="${TMP_ENV_DIR}/server-boot-${module}.sh"
  installer_fetch_file "$SEED_BASE" "$(installer_repo_file_value "$module")" "$module_file.source" 0600
  installer_apply_scalar_placeholders "$module_file.source" "$module_file"
  installer_assert_no_unresolved_path_placeholders "$module_file" "$module"
  # Verified implementation functions, never profile data as shell code.
  # shellcheck disable=SC1090
  . "$module_file"
done
layout_env="$(installer_runtime_state_dir)/runtime.env"
if [ -f "${DIR_INSTALLER_ENV}/runtime.env" ]; then layout_env="${DIR_INSTALLER_ENV}/runtime.env"; fi
[ -f "$layout_env" ] && [ ! -L "$layout_env" ] || installer_fatal 'frozen boot partition identities unavailable'
# Private installer-produced state, owned by the frozen partman plan.
# shellcheck disable=SC1090
. "$layout_env"
late_command_require_class_policy_env
: "${DEV_PART_BOOT:?missing boot partition}"
: "${DEV_PART_EFI:?missing EFI partition}"
: "${DEV_PART_ROOT:?missing root partition}"
grub_root_device=$DEV_PART_ROOT
if [ "$CRYPTO_LUKS2_ROOT" = true ]; then grub_root_device="${DIR_DEV}/mapper/${ROOT_CRYPT_NAME:?missing root mapper}"; fi
# Do not inherit an old desktop's removable rescue identity on new servers.
grub_rescue_uuid=
MULTIBOOT_ENABLED=false
if installer_multiboot_profile_selected; then MULTIBOOT_ENABLED=true; fi

# d-i has already mounted and populated the selected boot/EFI partitions.
# Validate those exact existing mounts; do not discover or mount another disk.
[ "$(target_mount_source "${TARGET_ROOT}${DIR_BOOT}")" = "$DEV_PART_BOOT" ] || installer_fatal 'headless boot mount differs from the frozen partition'
[ "$(target_mount_source "${TARGET_ROOT}${DIR_BOOT_EFI}")" = "$DEV_PART_EFI" ] || installer_fatal 'headless EFI mount differs from the frozen partition'
# The selected server profile already owns signing-state mode and its exact
# partition. Reuse the common signing backend, without a desktop bridge or
# firmware key reset. Keep private signing state out of public publications.
server_boot_signing_active=false
profile_work=
server_boot_cleanup() {
  server_boot_status=$?
  trap - 0
  if [ "$server_boot_signing_active" = true ]; then
    if ! close_target_secure_boot_state; then
      installer_warn 'server signing-state cleanup is uncertain; retain installer evidence'
      [ "$server_boot_status" -ne 0 ] || server_boot_status=1
    fi
  fi
  if [ -n "$profile_work" ]; then
    rm -f "$profile_work/source" "$profile_work/config" "$profile_work/map"
    rmdir "$profile_work" || { [ "$server_boot_status" -ne 0 ] || server_boot_status=1; }
  fi
  exit "$server_boot_status"
}
trap server_boot_cleanup 0
trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
server_boot_signing_active=true
stage_target_secure_boot_runtime_assets
prepare_target_secure_boot_runtime
sign_target_installed_kernel_modules
repair_target_installed_kernels
profile_work=$(mktemp -d "${TMP_ENV_DIR}/server-grub.XXXXXX")
render_grub_profile_config_map >"$profile_work/map"
# The map's values already contain literal shell quoting for the native data
# file. Assign validated variable names with read; never source/evaluate them.
while IFS= read -r record; do
  key=${record%%=*}; value=${record#*=}
  case "$key" in GRUB_CONFIG_*) ;; *) installer_fatal 'invalid GRUB profile map key' ;; esac
  case "$key" in *[!A-Z0-9_]*) installer_fatal 'unsafe GRUB profile map key' ;; esac
  IFS= read -r "$key" <<EOF
$value
EOF
done <"$profile_work/map"
installer_stage_profile_file hooks/target/etc/default/grub-profiles.tmpl "${DIR_ETC_DEFAULT}/grub-profiles" 0600
installer_stage_profile_file hooks/target/etc/default/grub.d/server/05-bootprofiles.cfg.tmpl "${DIR_GRUB_DEFAULT}/05-bootprofiles.cfg" 0644
GRUB_DISABLE_OS_PROBER=true
if [ "$MULTIBOOT_ENABLED" = true ]; then GRUB_DISABLE_OS_PROBER=false; fi
GRUB_MOK_MANAGER_EFI_PATH=$INSTALLER_GRUB_MOK_MANAGER_EFI_PATH
GRUB_REMOVABLE_BOOT_EFI_PATH=$INSTALLER_GRUB_REMOVABLE_BOOT_EFI_PATH
: "${GRUB_NVME_FLAGS:=}" "${GRUB_SYSTEMD_MASK_FLAGS:=}" "${GRUB_BLACKLIST_FLAGS:=}" "${GRUB_VFIO_FLAGS:=}" "${GRUB_ASPM_FLAGS:=}"
for fragment in 10-rootfs 15-initramfs 20-nvme 25-systemd-mask 30-cgroup 35-security-core 40-blacklist 42-vfio 45-memory-core 50-os-prober 60-hardening 70-aspm; do
  installer_stage_profile_asset "$(installer_repo_asset_path DIR_TARGET_DEFAULT_GRUB_D "${fragment}.cfg.tmpl")" \
    "${DIR_GRUB_DEFAULT}/${fragment}.cfg" 0644
done

for fragment in display-1.cfg.in display-2.cfg.in snapshots.cfg.in submenu.cfg.in entry.cfg.in mokmenu.cfg.in header.cfg.in rescue.cfg.in firmware.cfg.in; do
  installer_stage_profile_asset "$(installer_repo_asset_path DIR_TARGET_SHARE_GRUB_PROFILES "${fragment}.tmpl")" \
    "${DIR_USR_LOCAL_SHARE}/grub-profiles/$fragment" 0644
done
installer_stage_profile_file hooks/target/etc/grub.d/40_custom.tmpl "${DIR_ETC}/grub.d/40_custom" 0755
run_in_target 'publish headless GRUB profile entries without firmware enrollment' \
  "${DIR_USR_BIN}/timeout" --signal=TERM --kill-after=15 180 "${DIR_ETC}/grub.d/40_custom" --install
require_target_dualboot_os_prober_package
run_target_grub_config_update
installer_info 'headless XanMod EDGE signatures and boot profiles staged; MOK certificate enrollment remains explicit'
