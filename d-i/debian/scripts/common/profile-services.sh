#!/bin/sh
# One profile-controlled sharing stage for every desktop and server role.
set -eu
set +x
set +v
umask 077
runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}
# shellcheck disable=SC1090
. "$bootstrap_lib"
bootstrap_source_common_lib ""
SEED_BASE=$(installer_seed_base "")
installer_ensure_context_loaded "$SEED_BASE"
TMP_ENV_DIR=${DIR_INSTALLER_LATE_ENV}
LATE_COMMAND_HOST_ENV="${TMP_ENV_DIR}/profile-services.env"
installer_fetch_host_env "$SEED_BASE" "$INSTALLER_HOST_PROFILE" "$LATE_COMMAND_HOST_ENV" 0600
installer_load_data_env "$LATE_COMMAND_HOST_ENV"
installer_assert_class_plan
bootstrap_source_common_support_libs "$SEED_BASE" "${TMP_ENV_DIR}/profile-service-support" fetch hook target
for module in scripts/late/core.sh scripts/late/target-assets.sh scripts/late/network-sharing.sh scripts/common/filen.sh; do
  module_file="${TMP_ENV_DIR}/${module}.sh"
  installer_fetch_file "$SEED_BASE" "$(installer_repo_file_value "$module")" "$module_file.source" 0600
  installer_apply_scalar_placeholders "$module_file.source" "$module_file"
  installer_assert_no_unresolved_path_placeholders "$module_file" "$module"
  # Authenticated implementation code; never source the profile/credential input.
  # shellcheck disable=SC1090
  . "$module_file"
done
installer_load_primary_account
printf '%s\n' "$ACCOUNT_USERNAME" | LC_ALL=C grep -Eq '^[a-z_][a-z0-9_-]{0,31}$' || installer_fatal 'invalid sharing operator identity'
case "$ACCOUNT_USERNAME" in root|nobody|nogroup) installer_fatal 'sharing requires a human operator' ;; esac
ACCOUNT_HOME="${DIR_HOME}/$ACCOUNT_USERNAME"
installer_stage_profile_file hooks/target/usr/local/lib/common/python3/dist-packages/managed_network_sharing.py "${DIR_PYTHON3_SITE_PACKAGES}/managed_network_sharing.py" 0644
installer_stage_profile_file hooks/target/usr/local/bin/common/network-sharing "${DIR_USR_LOCAL_BIN}/network-sharing" 0755
installer_stage_profile_file hooks/target/usr/local/bin/common/nfsmnt "${DIR_USR_LOCAL_BIN}/nfsmnt" 0755
installer_stage_profile_file hooks/target/usr/local/bin/common/filenmnt "${DIR_USR_LOCAL_BIN}/filenmnt" 0755
installer_stage_profile_file hooks/target/etc/apparmor.d/common/network-sharing "${DIR_APPARMOR}/network-sharing" 0644
configure_target_network_sharing
install_profile_filen
if [ "$INSTALLER_HOST_VARIANT" = server ]; then
  # The server installs no desktop mode catalogue or menu/picker policy.
  modes_input="${TMP_ENV_DIR}/server-apparmor-modes.conf"
  {
    printf '%s\n' '# Shared headless policy; only installed services are required.' \
      'enforce required apparmor-modes -' 'enforce required system-wrappers -' 'enforce required network-sharing -' \
      'enforce optional hardware-tuning -' 'enforce optional incus-host -'
    [ "$(installer_plan_value codex_enable)" != true ] || printf '%s\n' 'enforce required codex-server -'
    if installer_class_selected role/server/devops; then
      printf '%s\n' 'enforce required gitbuild -' 'enforce required gitbuild-worker -'
    fi
    [ "$FILEN_CLI_PRIV_ENABLE" != true ] || printf '%s\n' 'enforce required filen-sync-private -'
    [ "$FILEN_CLI_OFFSEC_ENABLE" != true ] || printf '%s\n' 'enforce required filen-sync-offsec -'
  } >"$modes_input"
  # Publish through the existing trusted target writer, with no kernel access.
  write_target_file "${DIR_ETC}/apparmor/modes.conf" 0644 <"$modes_input"
fi
installer_info 'profile-controlled NFS, sharing clients and selected Filen accounts staged without starting services'
