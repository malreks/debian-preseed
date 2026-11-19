# Sourced installer-only Codex provisioner shared by desktop and server.
# shellcheck shell=sh
# shellcheck disable=SC2154

devops_codex_paths() {
DEVOPS_CODEX_STANDALONE_INSTALLER_HELPER=__INSTALLER_PATH_DIR_USR_LOCAL__/bin/codex-standalone-install
DEVOPS_CODEX_INSTALLER_SESSION_HELPER="${DEVOPS_CODEX_ROOT}/.installer-codex-standalone.session.py"
DEVOPS_CODEX_PACKAGES_ROOT=${DEVOPS_CODEX_PACKAGES_ROOT:?DEVOPS_CODEX_PACKAGES_ROOT must be set by the shared profile}
DEVOPS_CODEX_SOCKETS_ROOT="${DEVOPS_CODEX_ROOT}/sockets"
DEVOPS_CODEX_CREDENTIALS_ROOT="${DEVOPS_CODEX_ROOT}/credentials"
DEVOPS_CODEX_APP_SERVER_SOCKET="${DEVOPS_CODEX_SOCKETS_ROOT}/app-server-control.sock"
DEVOPS_CODEX_APP_SERVER_BACKEND_SOCKET="${DEVOPS_CODEX_SOCKETS_ROOT}/app-server-backend.sock"
DEVOPS_CODEX_APP_SERVER_CONTROL_DIR="${DEVOPS_CODEX_HOME}/app-server-control"
DEVOPS_CODEX_APP_SERVER_STARTUP_LOCK="${DEVOPS_CODEX_APP_SERVER_CONTROL_DIR}/app-server-startup.lock"
DEVOPS_CODEX_APP_SERVER_DEFAULT_SOCKET="${DEVOPS_CODEX_APP_SERVER_CONTROL_DIR}/app-server-control.sock"
DEVOPS_CODEX_APP_SERVER_ENVIRONMENT=__INSTALLER_PATH_DIR_ETC__/codex/app-server.env
DEVOPS_CODEX_APP_SERVER_READY_HELPER="${DIR_USR_LOCAL_LIBEXEC}/codex-app-server-wait-ready"
DEVOPS_CODEX_APP_SERVER_USER_UNIT="${ACCOUNT_HOME}/.config/systemd/user/codex-app-server.service"
DEVOPS_CODEX_APP_SERVER_USER_PROXY_UNIT="${ACCOUNT_HOME}/.config/systemd/user/codex-app-server-proxy.service"
DEVOPS_CODEX_APP_SERVER_USER_SOCKET_UNIT="${ACCOUNT_HOME}/.config/systemd/user/codex-app-server.socket"
DEVOPS_CODEX_APP_SERVER_USER_SOCKET_WANTS="${ACCOUNT_HOME}/.config/systemd/user/sockets.target.wants/codex-app-server.socket"
devops_codex_archive_helper_path="${DEVOPS_CODEX_ROOT}/.installer-codex-archive.py"
devops_codex_state_helper_path="${DEVOPS_CODEX_ROOT}/.installer-codex-state.py"

}

devops_provision_codex() {
devops_render_codex_sysctl
devops_render_codex_tmpfiles
devops_render_codex_logrotate
devops_prepare_codex_layout
devops_stage_target_asset \
  "$(installer_repo_file_value "$codex_wrapper_selector")" \
  "$DEVOPS_CODEX_WRAPPER_PATH" \
  0755 \
  codex-wrapper
chown root:root "${target_root}${DEVOPS_CODEX_WRAPPER_PATH}"
devops_stage_target_asset \
  "$(installer_repo_file_value hooks/target/usr/local/libexec/common/codex-app-server-wait-ready)" \
  "$DEVOPS_CODEX_APP_SERVER_READY_HELPER" \
  0755 \
  codex-app-server-ready-helper
chown root:root "${target_root}${DEVOPS_CODEX_APP_SERVER_READY_HELPER}"
if [ "$INSTALLER_HOST_VARIANT" = desktop ]; then
devops_stage_target_asset \
  "$(installer_repo_file_value hooks/target/usr/local/bin/desktop/codex-standalone-install)" \
  "$DEVOPS_CODEX_STANDALONE_INSTALLER_HELPER" \
  0755 \
  codex-standalone-installer
chown root:root "${target_root}${DEVOPS_CODEX_STANDALONE_INSTALLER_HELPER}"
devops_stage_target_asset \
  "$(installer_repo_file_value scripts/late/codex-installer-session.py)" \
  "$DEVOPS_CODEX_INSTALLER_SESSION_HELPER" \
  0700 \
  codex-installer-session
chown root:root "${target_root}${DEVOPS_CODEX_INSTALLER_SESSION_HELPER}"
fi
devops_stage_target_asset \
  "$(installer_repo_file_value scripts/late/codex-archive.py)" \
  "$devops_codex_archive_helper_path" \
  0700 \
  codex-archive-helper
chown root:root "${target_root}${devops_codex_archive_helper_path}"
devops_stage_target_asset \
  "$(installer_repo_file_value scripts/late/codex-state.py)" \
  "$devops_codex_state_helper_path" \
  0700 \
  codex-state-verifier
chown root:root "${target_root}${devops_codex_state_helper_path}"
devops_install_pinned_codex
devops_apply_codex_tmpfiles
devops_stage_codex_app_server
}

devops_verify_codex() {
codex_binary_dir_host="${target_root}${DEVOPS_CODEX_ROOT}/share/bin"
codex_first_binary=$(find "$codex_binary_dir_host" \
  -mindepth 1 -maxdepth 1 -type f -links 1 -print)
[ -n "$codex_first_binary" ] ||
  devops_fatal "managed Codex binary directory is empty after installation"
[ -x "${target_root}${DEVOPS_CODEX_BINARY_PATH}" ] ||
  devops_fatal "managed Codex entrypoint is missing after installation"
codex_unsafe_binary=$(find "$codex_binary_dir_host" \
  -mindepth 1 -maxdepth 1 \( ! -type f -o -type l -o ! -links 1 \) -print)
[ -z "$codex_unsafe_binary" ] ||
  devops_fatal "managed Codex binary directory contains an unsafe entry"
unset codex_binary_dir_host codex_first_binary codex_unsafe_binary
[ -r "${target_root}${DEVOPS_CODEX_SCHEMA_PATH}" ] ||
  devops_fatal "pinned Codex configuration schema is missing after installation"
[ -x "${target_root}${DEVOPS_CODEX_WRAPPER_PATH}" ] ||
  devops_fatal "managed Codex wrapper is missing after installation"
[ -f "${target_root}${DEVOPS_CODEX_APP_SERVER_READY_HELPER}" ] &&
  [ ! -L "${target_root}${DEVOPS_CODEX_APP_SERVER_READY_HELPER}" ] &&
  [ -x "${target_root}${DEVOPS_CODEX_APP_SERVER_READY_HELPER}" ] ||
  devops_fatal "Codex app-server readiness helper is missing or unsafe"
if [ "$INSTALLER_HOST_VARIANT" = desktop ]; then
[ -f "${target_root}${DEVOPS_CODEX_STANDALONE_INSTALLER_HELPER}" ] &&
  [ ! -L "${target_root}${DEVOPS_CODEX_STANDALONE_INSTALLER_HELPER}" ] &&
  [ -x "${target_root}${DEVOPS_CODEX_STANDALONE_INSTALLER_HELPER}" ] ||
  devops_fatal "target Codex standalone installer is missing or unsafe"
[ "$(chroot "$target_root" __INSTALLER_PATH_DIR_USR_BIN__/find -P "${DEVOPS_CODEX_STANDALONE_INSTALLER_HELPER}" -maxdepth 0 -printf '%U:%G:%m')" = 0:0:755 ] ||
  devops_fatal "target Codex standalone installer ownership or mode is invalid"
[ -f "${target_root}${DEVOPS_CODEX_INSTALLER_SESSION_HELPER}" ] &&
  [ ! -L "${target_root}${DEVOPS_CODEX_INSTALLER_SESSION_HELPER}" ] &&
  [ -x "${target_root}${DEVOPS_CODEX_INSTALLER_SESSION_HELPER}" ] ||
  devops_fatal "temporary Codex installer supervisor is missing or unsafe"
[ "$(chroot "$target_root" __INSTALLER_PATH_DIR_USR_BIN__/find -P "${DEVOPS_CODEX_INSTALLER_SESSION_HELPER}" -maxdepth 0 -printf '%U:%G:%m')" = 0:0:700 ] ||
  devops_fatal "temporary Codex installer supervisor ownership or mode is invalid"
fi
[ -r "${target_root}${DEVOPS_CODEX_APP_SERVER_ENVIRONMENT}" ] ||
  devops_fatal "Codex app-server environment policy is missing after installation"
[ -r "${target_root}${DEVOPS_CODEX_APP_SERVER_USER_UNIT}" ] ||
  devops_fatal "Codex app-server backend unit is missing after installation"
[ -r "${target_root}${DEVOPS_CODEX_APP_SERVER_USER_PROXY_UNIT}" ] ||
  devops_fatal "Codex app-server proxy unit is missing after installation"
[ -r "${target_root}${DEVOPS_CODEX_APP_SERVER_USER_SOCKET_UNIT}" ] ||
  devops_fatal "Codex app-server activation socket is missing after installation"
[ -L "${target_root}${DEVOPS_CODEX_APP_SERVER_USER_SOCKET_WANTS}" ] &&
  [ "$(readlink -- "${target_root}${DEVOPS_CODEX_APP_SERVER_USER_SOCKET_WANTS}")" = ../codex-app-server.socket ] ||
  devops_fatal "Codex app-server socket is not enabled for the account sockets target"
[ ! -e "${target_root}${devops_codex_archive_helper_path}" ] &&
  [ ! -L "${target_root}${devops_codex_archive_helper_path}" ] ||
  devops_fatal "temporary Codex archive helper remains after installation"
[ ! -e "${target_root}${devops_codex_state_helper_path}" ] &&
  [ ! -L "${target_root}${devops_codex_state_helper_path}" ] ||
  devops_fatal "temporary Codex state helper remains after installation"
[ -d "${target_root}${DEVOPS_CODEX_USER_ROOT}/.git" ] ||
  devops_fatal "cloned Codex home repository metadata is missing after installation"
[ -d "${target_root}${DEVOPS_CODEX_SYSTEM_CONFIG_DIR}" ] ||
  devops_fatal "Codex system configuration directory is missing after installation"
[ -r "${target_root}__INSTALLER_PATH_DIR_ETC__/sysctl.d/90-codex-bwrap.conf" ] ||
  devops_fatal "Codex Bubblewrap user-namespace sysctl policy is missing after installation"
[ -r "${target_root}__INSTALLER_PATH_DIR_ETC__/tmpfiles.d/80-codex-storage.conf" ] ||
  devops_fatal "Codex ownership tmpfiles policy is missing after installation"
[ -r "${target_root}__INSTALLER_PATH_DIR_ETC__/logrotate.d/codex" ] ||
  devops_fatal "Codex log rotation policy is missing after installation"
}
