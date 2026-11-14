#!/bin/sh
# Profile-owned LUKS2 staging. This helper never creates a target partition.
set -eu
set +x
set +v
runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}
# shellcheck disable=SC1090
. "$bootstrap_lib"
bootstrap_source_common_lib ""
seed_base=$(installer_seed_base "")
installer_ensure_context_loaded "$seed_base"
installer_assert_class_plan
crypto_profile="${DIR_INSTALLER_LATE_ENV}/crypto-profile.env"
installer_fetch_host_env "$seed_base" "$INSTALLER_HOST_PROFILE" "$crypto_profile" 0600
installer_load_data_env "$crypto_profile"
for crypto_flag in "$CRYPTO_LUKS2_ROOT" "$CRYPTO_LUKS2_HOME"; do
  case "$crypto_flag" in true|false) ;; *) installer_fatal 'invalid profile LUKS2 boolean' ;; esac
done
[ "$CRYPTO_LUKS2_ROOT" = true ] || [ "$CRYPTO_LUKS2_HOME" = true ] || exit 0
[ "$CRYPTO_LUKS2_ROOT" = "$(installer_plan_value crypto_root)" ] &&
  [ "$CRYPTO_LUKS2_HOME" = "$(installer_plan_value crypto_home)" ] || installer_fatal 'crypto policy differs from frozen plan'
bootstrap_source_common_support_libs "$seed_base" "${DIR_INSTALLER_LATE_ENV}/crypto-support" target fetch hook
crypto_layout="${DIR_INSTALLER_ENV}/runtime.env"
[ -f "$crypto_layout" ] || crypto_layout="$(installer_runtime_state_dir)/runtime.env"
[ -f "$crypto_layout" ] && [ ! -L "$crypto_layout" ] || installer_fatal 'crypto layout state is unavailable'
# Private generated layout state, not sourced profile data.
# shellcheck disable=SC1090
. "$crypto_layout"
crypto_operator=$(installer_cmdline_value primary_user) || installer_fatal 'explicit crypto operator is missing'
case "$crypto_operator" in ''|*[!a-z0-9_-]*) installer_fatal 'invalid crypto operator identity' ;; esac
crypto_bootstrap="$(installer_runtime_state_dir)/crypto-bootstrap.key"
[ -f "$crypto_bootstrap" ] && [ ! -L "$crypto_bootstrap" ] || installer_fatal 'private bootstrap key is unavailable'
crypto_bootstrap_value=$(cat "$crypto_bootstrap")
[ "${#crypto_bootstrap_value}" -eq 64 ] || installer_fatal 'invalid bootstrap key length'
case "$crypto_bootstrap_value" in *[!0-9a-f]*) installer_fatal 'invalid bootstrap key encoding' ;; esac
unset crypto_bootstrap_value
crypto_disk_record=${FILE_INSTALLER_SELECTED_DISK_IDENTITY:?selected disk identity path must be loaded}
[ -f "$crypto_disk_record" ] && [ ! -L "$crypto_disk_record" ] || installer_fatal 'selected disk identity receipt is unavailable'
IFS= read -r crypto_disk_identity <"$crypto_disk_record" || installer_fatal 'selected disk identity receipt cannot be read'
crypto_disk_digest=${crypto_disk_identity%"  -"}
[ "${#crypto_disk_digest}" -eq 64 ] && [ "$crypto_disk_identity" = "$crypto_disk_digest  -" ] ||
  installer_fatal 'invalid selected disk identity receipt'
case "$crypto_disk_digest" in *[!0-9a-f]*) installer_fatal 'invalid selected disk identity digest' ;; esac
crypto_detector="${DIR_INSTALLER_LATE_ENV}/crypto-detect-disk.sh"
installer_fetch_file "$seed_base" "$(installer_repo_file_value FILE_PARTMAN_DETECT_DISK)" "$crypto_detector" 0700
"$crypto_detector" --verify-identity "$DEV_INSTALL_DISK" "$crypto_disk_record" ||
  installer_fatal 'selected physical disk changed before crypto enrollment'
# Keep the key and selected devices open through the target bridge. Its private
# setup program verifies disk generation, membership, slots and LUKS UUIDs again
# before every native operation; a missing/reassigned descriptor fails closed.
exec 4<"$crypto_bootstrap" 7<"$DEV_INSTALL_DISK"
crypto_root_uuid=
crypto_home_uuid=
crypto_root_slot=
crypto_home_slot=
if [ "$CRYPTO_LUKS2_ROOT" = true ]; then
  "$crypto_detector" --verify-identity "$DEV_INSTALL_DISK" "$crypto_disk_record" "$DEV_PART_ROOT" ||
    installer_fatal 'root crypto partition differs from the selected disk'
  exec 5<"$DEV_PART_ROOT"
  # /proc/self/fd is the Linux inherited-descriptor interface, not a device alias.
  crypto_root_uuid=$(capture_in_target 'read the selected root LUKS identity' \
    "${DIR_USR_BIN}/timeout" --signal=TERM --kill-after=5s 30s \
    "${DIR_USR_SBIN}/cryptsetup" luksUUID /proc/self/fd/5) || installer_fatal 'root crypto UUID cannot be read'
  crypto_root_slot=${RUNTIME_ROOT_SLOT:?frozen root partition slot must be set}
fi
if [ "$CRYPTO_LUKS2_HOME" = true ]; then
  "$crypto_detector" --verify-identity "$DEV_INSTALL_DISK" "$crypto_disk_record" "$DEV_PART_HOME" ||
    installer_fatal 'home crypto partition differs from the selected disk'
  exec 6<"$DEV_PART_HOME"
  crypto_home_uuid=$(capture_in_target 'read the selected home LUKS identity' \
    "${DIR_USR_BIN}/timeout" --signal=TERM --kill-after=5s 30s \
    "${DIR_USR_SBIN}/cryptsetup" luksUUID /proc/self/fd/6) || installer_fatal 'home crypto UUID cannot be read'
  crypto_home_slot=${RUNTIME_HOME_SLOT:?frozen home partition slot must be set}
fi
"$crypto_detector" --verify-identity "$DEV_INSTALL_DISK" "$crypto_disk_record" ||
  installer_fatal 'selected physical disk changed during crypto descriptor capture'
CRYPTO_PRIMARY_USER_VALUE=$(installer_shell_quote "$crypto_operator")
CRYPTO_ROOT_ENABLED_VALUE=$(installer_shell_quote "$CRYPTO_LUKS2_ROOT")
CRYPTO_HOME_ENABLED_VALUE=$(installer_shell_quote "$CRYPTO_LUKS2_HOME")
CRYPTO_ROOT_LUKS_UUID_VALUE=$(installer_shell_quote "$crypto_root_uuid")
CRYPTO_HOME_LUKS_UUID_VALUE=$(installer_shell_quote "$crypto_home_uuid")
CRYPTO_ROOT_CRYPT_NAME_VALUE=$(installer_shell_quote "$ROOT_CRYPT_NAME")
CRYPTO_HOME_CRYPT_NAME_VALUE=$(installer_shell_quote "$HOME_CRYPT_NAME")
CRYPTO_BOOTSTRAP_CREDENTIAL_VALUE=$(installer_shell_quote "$FILE_CRYPTO_BOOTSTRAP_CREDENTIAL")
CRYPTO_TPM2_FINAL_PCRS_VALUE=$(installer_shell_quote 7+8+9+14)
install -d -m 0700 "${TARGET_ROOT}${DIR_CRYPTO_STATE}"
installer_stage_profile_file FILE_FIRSTBOOT_ASSET_TPM_CONFIG_TMPL "$FILE_CRYPTO_STATE_CONFIG" 0600
installer_stage_profile_file FILE_TARGET_LIBEXEC_TPM2_POLICY_CHECK "${DIR_USR_LOCAL_LIBEXEC}/tpm2-policy-check" 0755
installer_run_target_setup FILE_LATE_CRYPTO_BOOTSTRAP 'verify selected-device temporary TPM enrollment and sealed recovery' \
  "$DEV_INSTALL_DISK" "$crypto_disk_digest" "$crypto_root_slot" "$crypto_home_slot"
exec 4<&- 5<&- 6<&- 7<&-

# Keep unrelated crypttab records; replace only the selected managed identities.
crypto_crypttab="${TARGET_ROOT}${DIR_ETC}/crypttab"
[ ! -L "$crypto_crypttab" ] || installer_fatal 'refusing symlinked target crypttab'
crypto_candidate=$(mktemp "${TARGET_ROOT}${DIR_ETC}/.crypttab.XXXXXX")
if [ -f "$crypto_crypttab" ]; then
  awk -v root="$ROOT_CRYPT_NAME" -v home="$HOME_CRYPT_NAME" -v ru="$crypto_root_uuid" -v hu="$crypto_home_uuid" '
    /^[[:space:]]*#/ || NF==0 {print; next}
    ru!="" && ($1==root || $2=="UUID=" ru) {next}
    hu!="" && ($1==home || $2=="UUID=" hu) {next}
    {print}
  ' "$crypto_crypttab" >"$crypto_candidate"
fi
crypto_records="${DIR_INSTALLER_LATE_ENV}/crypto-records"
install -d -m 0700 "$crypto_records"
for crypto_volume in root home; do
  case "$crypto_volume" in
    root) [ "$CRYPTO_LUKS2_ROOT" = true ] || continue
      CRYPTO_MAPPER_NAME=$ROOT_CRYPT_NAME; CRYPTO_LUKS_UUID=$crypto_root_uuid; CRYPTO_OPTIONS=luks,initramfs ;;
    home) [ "$CRYPTO_LUKS2_HOME" = true ] || continue
      CRYPTO_MAPPER_NAME=$HOME_CRYPT_NAME; CRYPTO_LUKS_UUID=$crypto_home_uuid; CRYPTO_OPTIONS=luks,tpm2-device=auto ;;
  esac
  crypto_row=$(mktemp "${DIR_INSTALLER_LATE_ENV}/crypto-row.XXXXXX")
  installer_fetch_file "$seed_base" "$(installer_repo_file_value FILE_TARGET_CRYPTTAB_TMPL)" "$crypto_row" 0600
  installer_apply_scalar_placeholders "$crypto_row" "$crypto_records/$crypto_volume" \
    CRYPTO_MAPPER_NAME "$CRYPTO_MAPPER_NAME" CRYPTO_LUKS_UUID "$CRYPTO_LUKS_UUID" CRYPTO_OPTIONS "$CRYPTO_OPTIONS"
  installer_assert_no_unresolved_installer_placeholders "$crypto_records/$crypto_volume" crypttab
  cat "$crypto_records/$crypto_volume" >>"$crypto_candidate"
  rm -f "$crypto_row"
done
chmod 0600 "$crypto_candidate"
mv "$crypto_candidate" "$crypto_crypttab"
if [ "$CRYPTO_LUKS2_ROOT" = true ]; then
  TPM2_CRYPTROOT_NAME_VALUE=$(installer_shell_quote "$ROOT_CRYPT_NAME")
  TPM2_CRYPTROOT_UUID_VALUE=$(installer_shell_quote "$crypto_root_uuid")
  installer_stage_profile_file FILE_TARGET_TPM2_CRYPTROOT_TMPL "$FILE_TPM2_CRYPTROOT_CONFIG" 0600
  installer_stage_profile_file FILE_TARGET_CRYPTSETUP_INITRAMFS_CONF_HOOK "${DIR_ETC}/cryptsetup-initramfs/conf-hook" 0644
  installer_stage_profile_file FILE_TARGET_INITRAMFS_HOOKS_TPM2_CRYPTROOT "${DIR_ETC}/initramfs-tools/hooks/tpm2-cryptroot" 0755
  installer_stage_profile_file FILE_TARGET_INITRAMFS_SCRIPTS_LOCAL_TOP_00_TPM2_CRYPTROOT "${DIR_ETC}/initramfs-tools/scripts/local-top/00-tpm2-cryptroot" 0755
fi
installer_stage_profile_file FILE_TARGET_DEFAULT_GRUB_D_45_TPM2_MEASURED_BOOT "${DIR_ETC}/default/grub.d/45-tpm2-measured-boot.cfg" 0644
installer_stage_profile_file FILE_TARGET_AA_USR_LOCAL_SBIN_TPM2_ENROLL "${DIR_APPARMOR}/usr.local.sbin.tpm2-enroll.sh" 0644
installer_stage_profile_file FILE_FIRSTBOOT_ASSET_SBIN_TPM2_ENROLL "${DIR_USR_LOCAL_SBIN}/tpm2-enroll.sh" 0755
installer_stage_profile_file FILE_TARGET_TPM2_ENROLLMENT_SERVICE "$FILE_CRYPTO_SETUP_SERVICE" 0644
installer_stage_offline_unit_link "$FILE_CRYPTO_SETUP_SERVICE"
# The console unit owns first-setup prompting for both families. Keep only the
# existing desktop launcher as a convenient explicit retry after boot cleanup.
if installer_desktop_class_selected; then
  installer_stage_profile_file FILE_FIRSTBOOT_ASSET_BIN_TPM2_ENROLL_LAUNCH "${DIR_USR_LOCAL_BIN}/tpm2-enroll-launch" 0755
  installer_stage_profile_file FILE_FIRSTBOOT_ASSET_PROFILE_TPM2_ENROLL_PROMPT "${DIR_ETC}/profile.d/tpm2-enroll-prompt.sh" 0644
fi
install -d -m 0700 "${TARGET_ROOT}${DIR_CRYPTO_STATE}"
printf '%s\n' "$crypto_operator" >"${TARGET_ROOT}${FILE_CRYPTO_PENDING}"
chmod 0600 "${TARGET_ROOT}${FILE_CRYPTO_PENDING}"
run_in_target 'enable measured boot for selected encrypted volumes' ${DIR_USR_SBIN}/update-grub
run_in_target 'build crypto-aware initramfs images' ${DIR_USR_SBIN}/update-initramfs -u -k all
# The permanent reenrollment helper owns the same bounded image/secret checks
# here and after boot. Failure leaves the private installer key for recovery.
run_in_target 'verify crypto initramfs images and native TPM dependency closure' \
  "${DIR_USR_LOCAL_LIBEXEC}/tpm2-policy-check" --initramfs
rm -f "$crypto_bootstrap" "$(installer_runtime_state_dir)/crypto.answers.cfg"
installer_info 'selected LUKS2 volumes staged; TPM2+PIN and recovery confirmation remain pending at the boot console'
