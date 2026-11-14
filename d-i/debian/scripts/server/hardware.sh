#!/bin/sh
# Headless caller of the same profile-gated tuning backend used by desktops.
set -eu
runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}
# shellcheck disable=SC1090
. "$bootstrap_lib"
bootstrap_source_common_lib ""
SEED_BASE=$(installer_seed_base "")
installer_ensure_context_loaded "$SEED_BASE"
[ "$INSTALLER_HOST_VARIANT" = server ] || installer_fatal 'headless hardware stage requires a server role'
TMP_ENV_DIR=${DIR_INSTALLER_LATE_ENV}
LATE_COMMAND_HOST_ENV="${TMP_ENV_DIR}/hardware-profile.env"
installer_fetch_host_env "$SEED_BASE" "$INSTALLER_HOST_PROFILE" "$LATE_COMMAND_HOST_ENV" 0600
installer_load_data_env "$LATE_COMMAND_HOST_ENV"
installer_assert_class_plan
bootstrap_source_common_support_libs "$SEED_BASE" "${TMP_ENV_DIR}/hardware-support" fetch hook target
for module in FILE_LATE_CORE FILE_LATE_TARGET_ASSETS FILE_OS_HARDWARE_TUNING FILE_OS_SCX_SCHEDS; do
  module_file="${TMP_ENV_DIR}/${module}.sh"
  installer_fetch_file "$SEED_BASE" "$(installer_repo_file_value "$module")" "$module_file.source" 0600
  installer_apply_scalar_placeholders "$module_file.source" "$module_file"
  installer_assert_no_unresolved_path_placeholders "$module_file" "$module"
  # shellcheck disable=SC1090
  . "$module_file"
done
ACCOUNT_USERNAME=$(installer_cmdline_value primary_user) || installer_fatal 'hardware policy requires the private operator identity'
installer_run_target_setup FILE_SERVER_SETUP 'install profile-controlled pinned scheduler packages without starting services' \
  profile-packages server "$INSTALLER_ARCH_CLASS"
profile_install_scx_scheduler
install_profile_hardware_tuning
