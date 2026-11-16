#!/bin/sh
# New headless target foundation. No desktop storage/account/credential bridge.
set -eu
runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}
# shellcheck disable=SC1090
. "$bootstrap_lib"
bootstrap_source_common_lib ""
seed_base=$(installer_seed_base "")
installer_ensure_context_loaded "$seed_base"
[ "$INSTALLER_HOST_VARIANT" = server ] || installer_fatal 'server stage requires the server family'
server_env="${DIR_INSTALLER_LATE_ENV}/server.env"
installer_fetch_host_env "$seed_base" "$INSTALLER_HOST_PROFILE" "$server_env" 0600
installer_load_data_env "$server_env"
installer_load_primary_account
server_operator=$ACCOUNT_USERNAME
server_ssh_users=${SSH_SERVER_USER_ALLOW:-$server_operator}
case " $server_ssh_users " in
  *" $server_operator "*) ;;
  *) installer_fatal 'the explicit server profile SSH allow-list excludes the requested primary user' ;;
esac
bootstrap_source_common_support_libs "$seed_base" "${DIR_INSTALLER_LATE_ENV}/server-support" target fetch hook ssh
installer_assert_class_plan
installer_publish_class_receipt
if [ "$(installer_plan_value whisper_enable)" = true ] || [ "$(installer_plan_value llama_enable)" = true ]; then
  installer_stage_profile_file FILE_SERVER_SKEL_PROFILE_AI "${DIR_ETC_SKEL_SERVER}/.profile.d/73-whisper-llama-srv.sh" 0644
fi
if installer_class_selected role/server/github-actions || installer_class_selected role/server/gitlab-cicd; then
  installer_stage_profile_file FILE_TARGET_LIBEXEC_CI_RUNNERS_CONTROL "${DIR_USR_LOCAL_LIBEXEC}/server/ci-runners-control" 0755
  installer_stage_profile_file FILE_TARGET_BIN_CI_RUNNERS "${DIR_USR_LOCAL_BIN}/ci-runners" 0755
  installer_stage_profile_file FILE_SERVER_SKEL_PROFILE_CI_RUNNERS "${DIR_ETC_SKEL_SERVER}/.profile.d/72-ci-runners-srv.sh" 0644
fi
installer_stage_profile_file FILE_SERVER_CONTROL_SOURCE "$FILE_SERVER_CONTROL" 0755
server_artifacts=$(installer_repo_asset_path DIR_CATALOG_COMPILED \
  "$INSTALLER_SUITE/profiles/server/$INSTALLER_HOST_PROFILE_ENV_NAME.artifacts.json")
installer_stage_profile_asset "$server_artifacts" "$FILE_SERVER_ARTIFACTS" 0644
installer_stage_profile_file FILE_SERVER_RSYSLOG "${DIR_ETC}/rsyslog.conf" 0644
installer_stage_profile_file FILE_SERVER_RSYSLOG_SECURITY "${DIR_RSYSLOG_D}/20-server-security.conf" 0644
installer_stage_profile_file FILE_SERVER_JOURNALD "${DIR_JOURNALD_CONF_D}/70-server-logging.conf" 0644
installer_stage_profile_file FILE_SERVER_TMPFILES_LOGS "${DIR_TMPFILES_D}/59-server-logs.conf" 0644
installer_stage_profile_file FILE_TARGET_LIBEXEC_RSYSLOG_SIZE_ROTATE_TMPL "${DIR_USR_LOCAL_LIBEXEC}/rsyslog-size-rotate" 0755
run_in_target 'create private headless logging directories' /usr/bin/systemd-tmpfiles --create "${DIR_TMPFILES_D}/59-server-logs.conf"
installer_stage_profile_file FILE_SERVER_SKEL_BASHRC "${DIR_ETC_SKEL_SERVER}/.bashrc" 0644
installer_stage_profile_file FILE_SERVER_SKEL_BASH_PROFILE "${DIR_ETC_SKEL_SERVER}/.bash_profile" 0644
installer_stage_profile_file FILE_SERVER_SKEL_BASH_ALIASES "${DIR_ETC_SKEL_SERVER}/.bash_aliases" 0644
installer_stage_profile_file FILE_SERVER_SKEL_PROFILE "${DIR_ETC_SKEL_SERVER}/.profile" 0644
installer_stage_profile_file FILE_SERVER_NETWORK_IFUPDOWN "${DIR_ETC}/NetworkManager/conf.d/20-server-ifupdown.conf" 0644
installer_stage_profile_file FILE_SERVER_CI_WORKLOADS_SLICE "${DIR_SYSTEMD_SYSTEM}/ci-workloads.slice" 0644
server_roles=$(installer_plan_roles) || exit "$?"
while IFS= read -r server_role; do
  case "$server_role" in
    server/github-actions)
      installer_stage_profile_file FILE_SERVER_GITHUB_JOB_START_SOURCE "$FILE_SERVER_GITHUB_JOB_START" 0755
      installer_stage_profile_file FILE_SERVER_CI_USER_RESOURCES "${DIR_SYSTEMD_SYSTEM_CI_GITHUB_USER_DROPIN}/70-ci-workloads.conf" 0644
      installer_stage_profile_file FILE_SERVER_UNIT_GITHUB "${DIR_SYSTEMD_SYSTEM}/ci-github.service" 0644 ;;
    server/gitlab-cicd)
      installer_stage_profile_file FILE_SERVER_CI_USER_RESOURCES "${DIR_SYSTEMD_SYSTEM_CI_GITLAB_USER_DROPIN}/70-ci-workloads.conf" 0644
      installer_stage_profile_file FILE_SERVER_UNIT_GITLAB "${DIR_SYSTEMD_SYSTEM}/ci-gitlab.service" 0644 ;;
    server/technitium)
      case "$IPV6_ENABLE" in
        true) TECHNITIUM_IPV6_FORWARDING=1 ;;
        false) TECHNITIUM_IPV6_FORWARDING=0 ;;
        *) installer_fatal 'invalid DNS IPv6 profile policy' ;;
      esac
      installer_stage_profile_file FILE_SERVER_UNIT_DNS "${DIR_SYSTEMD_SYSTEM}/technitium.service" 0644
      installer_stage_profile_file FILE_SERVER_DNS_PREFLIGHT_SOURCE "$FILE_SERVER_DNS_PREFLIGHT" 0755
      installer_stage_profile_file FILE_SERVER_DNS_INCUS_SOURCE "$FILE_SERVER_DNS_INCUS" 0644
      installer_stage_profile_file FILE_SERVER_DNS_INIT_SOURCE "$FILE_SERVER_DNS_INIT" 0644
      installer_stage_profile_file FILE_SERVER_DNS_FORWARDING_SOURCE "$FILE_SERVER_DNS_FORWARDING_CANDIDATE" 0600
      installer_stage_offline_unit_link "${DIR_SYSTEMD_SYSTEM_LIB}/incus.socket"
      ;;
    server/devops)
      installer_stage_profile_file FILE_SERVER_CI_USER_RESOURCES "${DIR_SYSTEMD_SYSTEM_SERVER_DEVOPS_USER_DROPIN}/70-ci-workloads.conf" 0644
      ;;
    *) installer_fatal 'unregistered server role' ;;
  esac
done <<EOF
$server_roles
EOF
foundation_private_input=
foundation_private_target=
foundation_private_cleanup() {
  foundation_private_status=$?
  trap - 0
  if [ -n "$foundation_private_input" ]; then
    if ! rm -f "$foundation_private_input"; then
      installer_error 'private server credential staging cleanup failed'
      [ "$foundation_private_status" -ne 0 ] || foundation_private_status=1
    fi
  fi
  exit "$foundation_private_status"
}
trap foundation_private_cleanup 0
trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
if installer_class_selected role/server/technitium; then
  foundation_private_parent="${TARGET_ROOT}${DIR_VAR_LIB_INSTALLER_STATE}"
  installer_apt_safe_path "$foundation_private_parent" || installer_fatal 'unsafe dedicated DNS input ancestry'
  foundation_private_input=$(umask 077; mktemp "$foundation_private_parent/.dns-credentials.XXXXXX")
  (
    set +x
    set +v
    umask 077
    for dns_credential in technitium_username technitium_password technitium_web_username \
      technitium_web_password technitium_tls_passphrase technitium_backup_passphrase; do
      dns_value=
      if dns_value=$(installer_cmdline_value "$dns_credential"); then
        :
      else
        dns_value_status=$?
        [ "$dns_value_status" -eq 1 ] || installer_fatal 'unsafe private DNS input'
      fi
      printf '%s\0' "$dns_value"
      unset dns_value
    done
  ) >"$foundation_private_input"
  chmod 0600 "$foundation_private_input"
  foundation_private_target=${foundation_private_input#"$TARGET_ROOT"}
fi
installer_run_target_setup FILE_SERVER_SETUP 'configure headless server identities and policy' \
  foundation server \
    "$SSH_SERVER_ENABLE|$SSH_SERVER_PORT|$server_ssh_users|$CI_RUNNER_GITHUB_SUBUID|$CI_RUNNER_GITLAB_SUBUID|$DEVOPS_SUBUID|$PODMAN_GITHUB_STORAGE_DRIVER|$PODMAN_GITHUB_GRAPHROOT|$PODMAN_GITHUB_RUNROOT|$PODMAN_GITHUB_IMAGE_COPY_TMP_DIR|$PODMAN_GITLAB_STORAGE_DRIVER|$PODMAN_GITLAB_GRAPHROOT|$PODMAN_GITLAB_RUNROOT|$PODMAN_GITLAB_IMAGE_COPY_TMP_DIR|$PODMAN_DEVOPS_STORAGE_DRIVER|$PODMAN_DEVOPS_GRAPHROOT_ROOT|$PODMAN_DEVOPS_GRAPHROOT_SUBDIR|$PODMAN_DEVOPS_RUNROOT_BASE|$PODMAN_DEVOPS_IMAGE_COPY_TMP_ROOT|$PODMAN_DEVOPS_IMAGE_COPY_TMP_SUBDIR|$PODMAN_SERVICE_CPU_WEIGHT|$PODMAN_SERVICE_IO_WEIGHT|$PODMAN_SERVICE_TASKS_MAX|$PODMAN_SERVICE_MEMORY_HIGH|$PODMAN_SERVICE_MEMORY_MAX|$PODMAN_GITHUB_USER|$PODMAN_GITHUB_GROUP|$PODMAN_GITLAB_USER|$PODMAN_GITLAB_GROUP|$PODMAN_DEVOPS_USER|$PODMAN_DEVOPS_GROUP|$server_operator" \
    "$foundation_private_target"
# The role-owned firewall file is staged after identity setup. It keeps DNS
# closed until explicit private configuration and limits SSH to the profile ACL.
case "$SSH_SERVER_ENABLE" in
  true) SSH_SERVER_RULE_PREFIX='' ;;
  false) SSH_SERVER_RULE_PREFIX='# disabled by host profile: ' ;;
  *) installer_fatal 'SSH_SERVER_ENABLE must be true or false' ;;
esac
installer_stage_profile_file FILE_SERVER_NFTABLES "${DIR_ETC}/nftables.d/70-managed-server.nft" 0600
installer_stage_profile_file FILE_SERVER_NFTABLES_UNIT "${DIR_SYSTEMD_SYSTEM_NFTABLES_DROPIN}/70-managed-server.conf" 0644
installer_run_target_setup FILE_SERVER_SETUP 'install the Bash-only server account skeleton' \
  account server "$server_operator"
# Include every selected payload default, including optional login fragments.
# The private future-account template is an independent publication destination.
installer_publish_primary_defaults server "$server_operator" "$ACCOUNT_HOME"
if [ "$SSH_SERVER_ENABLE" = true ]; then
  provision_target_lan_ssh_key "$server_operator"
else
  installer_info 'SSH server disabled by the selected host profile'
fi
installer_info 'headless server foundation staged; external services remain installed-but-pending'
