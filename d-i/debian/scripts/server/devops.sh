#!/bin/sh
# Headless DevOps policy. This stage never imports the desktop installation.
set -eu
runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}
# shellcheck disable=SC1090
. "$bootstrap_lib"
bootstrap_source_common_lib ""
seed_base=$(installer_seed_base "")
installer_ensure_context_loaded "$seed_base"
installer_assert_class_plan
installer_class_selected role/server/devops || installer_fatal 'server DevOps stage requires its exact role class'
installer_load_data_env "${DIR_INSTALLER_LATE_ENV}/server.env"
bootstrap_source_common_support_libs "$seed_base" "${DIR_INSTALLER_LATE_ENV}/server-support" target
installer_stage_profile_file hooks/target/etc/skel-server/.profile.d/71-devops-srv.sh "${DIR_ETC_SKEL_SERVER}/.profile.d/71-devops-srv.sh" 0644
installer_stage_profile_file hooks/target/etc/systemd/server/system/managed-buildbuddy.service.tmpl "${DIR_SYSTEMD_SYSTEM}/managed-buildbuddy.service" 0644
installer_load_primary_account
server_operator=$ACCOUNT_USERNAME
installer_run_target_setup scripts/server/setup.py.tmpl 'configure isolated headless DevOps stores' \
  devops-account server/devops "$server_operator|$PODMAN_DEVOPS_STORAGE_DRIVER|$PODMAN_DEVOPS_GRAPHROOT_ROOT|$PODMAN_DEVOPS_GRAPHROOT_SUBDIR|$PODMAN_DEVOPS_RUNROOT_BASE|$PODMAN_DEVOPS_IMAGE_COPY_TMP_ROOT|$PODMAN_DEVOPS_IMAGE_COPY_TMP_SUBDIR|$PODMAN_SERVICE_CPU_WEIGHT|$PODMAN_SERVICE_IO_WEIGHT|$PODMAN_SERVICE_TASKS_MAX|$PODMAN_SERVICE_MEMORY_HIGH|$PODMAN_SERVICE_MEMORY_MAX"
installer_run_target_setup scripts/server/setup.py.tmpl 'install pinned headless DevOps artifacts without activation' \
  install server/devops "$INSTALLER_ARCH_CLASS"
