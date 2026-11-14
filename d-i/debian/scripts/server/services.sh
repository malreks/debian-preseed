#!/bin/sh
set -eu
runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}
# shellcheck disable=SC1090
. "$bootstrap_lib"
bootstrap_source_common_lib ""
seed_base=$(installer_seed_base "")
installer_ensure_context_loaded "$seed_base"
server_env="${DIR_INSTALLER_LATE_ENV}/server.env"
installer_load_data_env "$server_env"
bootstrap_source_common_support_libs "$seed_base" "${DIR_INSTALLER_LATE_ENV}/server-support" target
installer_assert_class_plan
configure_private_runner() (
  set -eu
  set +x
  set +v
  umask 077
  private_role=$1
  case "$private_role" in
    server/github-actions) private_name=ci_github_token ;;
    server/gitlab-cicd) private_name=ci_gitlab_token ;;
    *) installer_fatal 'private runner input requires a registered provider' ;;
  esac
  private_token=
  if private_token=$(installer_cmdline_value "$private_name"); then
    :
  else
    private_status=$?
    [ "$private_status" -eq 1 ] || installer_fatal 'unsafe initrd runner credential input'
  fi
  private_parent="${TARGET_ROOT}${DIR_VAR_LIB_INSTALLER_STATE}"
  installer_apt_safe_path "$private_parent" || installer_fatal 'unsafe runner input staging ancestry'
  private_input=$(mktemp "$private_parent/.runner-enrollment.XXXXXX") || exit "$?"
  trap 'rm -f "$private_input"' 0
  trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
  printf '%s' "$private_token" >"$private_input"
  unset private_token
  chmod 0600 "$private_input"
  installer_run_target_setup FILE_SERVER_SETUP 'configure the selected runner from private initrd credentials' \
    configure-runner "$private_role" "${private_input#"$TARGET_ROOT"}"
)
server_roles=$(installer_plan_roles) || exit "$?"
while IFS= read -r server_role; do
  case "$server_role" in
    server/github-actions|server/gitlab-cicd|server/technitium)
      installer_run_target_setup FILE_SERVER_SETUP 'install pinned headless service artifacts' \
        install "$server_role" "$INSTALLER_ARCH_CLASS"
      case "$server_role" in
        server/github-actions|server/gitlab-cicd) configure_private_runner "$server_role" ;;
      esac
      ;;
    server/devops) ;; # Its own selected class owns the distinct DevOps stage.
    *) installer_fatal 'unregistered server role in service plan' ;;
  esac
done <<EOF
$server_roles
EOF
