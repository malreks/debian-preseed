#!/bin/sh
# shellcheck disable=SC2154
# Packaged Debian builders and managed gitbuild entrypoints only.

devops_stage_gitbuild() (
  set -eu
  case "$DEVOPS_GITBUILD_BOOTSTRAP_MIRROR_URL" in
    https://*/*) ;;
    *) devops_fatal "DEVOPS_GITBUILD_BOOTSTRAP_MIRROR_URL must be an HTTPS Debian mirror URL" ;;
  esac
  for directory in \
    "${DIR_USR_LOCAL_BIN}" \
    "${DIR_USR_LOCAL_LIB}" \
    "${DIR_USR_LOCAL_LIBEXEC}" \
    "${DIR_PYTHON3_LOCAL}" \
    "${DIR_PYTHON3_SITE_PACKAGES}" \
    "${DIR_PYTHON3_SITE_PACKAGES}/managed_workflows" \
    "${DIR_PYTHON3_SITE_PACKAGES}/gitbuild" \
    "${DIR_USR_LOCAL_SHARE}" \
    "${DIR_USR_LOCAL_SHARE}/gitbuild" \
    __INSTALLER_PATH_DIR_USR_SHARE__/polkit-1/actions
  do
    target_directory="${target_root}${directory}"
    [ ! -L "$target_directory" ] || devops_fatal "symlinked gitbuild directory: $directory"
    install -d -m 0755 "$target_directory"
    chown root:root "$target_directory"
    chmod 0755 "$target_directory"
  done
  for executable in bin/gitbuild libexec/gitbuild-worker libexec/gitbuild-publish libexec/gitbuild-import-local; do
    path="usr/local/$executable"
    devops_stage_target_asset "$(installer_repo_asset_path DIR_HOOKS_TARGET "$path")" "/$path" 0755 gitbuild-executable
    chown root:root "${target_root}/$path"
  done
  for module in __init__ fs process; do
    path="usr/local/lib/python3/dist-packages/managed_workflows/$module.py"
    devops_stage_target_asset "$(installer_repo_asset_path DIR_HOOKS_TARGET "$path")" "/$path" 0644 gitbuild-shared-module
    chown root:root "${target_root}/$path"
  done
  for module in __init__ cli core import_local publish safe_rename; do
    path="usr/local/lib/python3/dist-packages/gitbuild/$module.py"
    devops_stage_target_asset "$(installer_repo_asset_path DIR_HOOKS_TARGET "$path")" "/$path" 0644 gitbuild-module
    chown root:root "${target_root}/$path"
  done
  worker_path=usr/local/lib/python3/dist-packages/gitbuild/worker.py
  worker_source_path=${worker_path}.tmpl
  worker_source=$(installer_repo_asset_path DIR_HOOKS_TARGET "$worker_source_path")
  worker_tmp="${tmp_env_dir}/gitbuild-worker.py.$$"
  worker_rendered="${tmp_env_dir}/gitbuild-worker.rendered.py.$$"
  bootstrap_fetch_seed_file "$seed_base" "$worker_source" "$worker_tmp" 0600 \
    "Gitbuild worker template ${worker_source}"
  installer_apply_scalar_placeholders \
    "$worker_tmp" "$worker_rendered" \
    DEVOPS_GITBUILD_BOOTSTRAP_MIRROR_URL "$DEVOPS_GITBUILD_BOOTSTRAP_MIRROR_URL"
  installer_assert_no_unresolved_installer_placeholders "$worker_rendered" \
    "Gitbuild worker template ${worker_source}"
  install -m 0644 "$worker_rendered" "${target_root}/$worker_path"
  chown root:root "${target_root}/$worker_path"
  rm -f -- "$worker_tmp" "$worker_rendered"
  for path in usr/local/share/gitbuild/sbuild.conf usr/share/polkit-1/actions/org.labwc.gitbuild-import.policy; do
    devops_stage_target_asset "$(installer_repo_asset_path DIR_HOOKS_TARGET "$path")" "/$path" 0644 gitbuild-policy
    chown root:root "${target_root}/$path"
  done
  if [ "$INSTALLER_HOST_VARIANT" = server ]; then
    # os.codex already owns the shared bwrap mechanics for server DevOps.
    installer_stage_profile_file hooks/target/etc/apparmor.d/common/abstractions/workflow-auth "${DIR_APPARMOR}/abstractions/workflow-auth" 0644
    installer_stage_profile_file hooks/target/etc/apparmor.d/common/gitbuild-worker "${DIR_APPARMOR}/gitbuild-worker" 0644
    installer_stage_profile_file hooks/target/etc/apparmor.d/server/gitbuild "${DIR_APPARMOR}/gitbuild" 0644
  fi
  helper="${DIR_USR_LOCAL_LIBEXEC}/installer-gitbuild-policy"
  devops_stage_target_asset "$(installer_repo_file_value hooks/target/etc/tmpfiles.d/common/11-build-pool-tmp.conf.tmpl)" \
    "${DIR_TMPFILES_D}/11-build-pool-tmp.conf" 0644 gitbuild-temporary-pool-policy
  trap 'rm -f -- "${target_root}${helper}"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  devops_stage_target_asset \
    "$(installer_repo_file_value scripts/late/gitbuild-policy.py)" "$helper" 0700 gitbuild-installer-policy
  run_in_target "configure private gitbuild storage and subordinate IDs" \
    __INSTALLER_PATH_DIR_USR_BIN__/python3 -I -B "$helper" "$ACCOUNT_USERNAME"
  run_in_target "apply selected AppArmor mode to staged gitbuild workers" \
    "${DIR_USR_LOCAL_LIBEXEC}/apparmor-modes-run" --no-reload
)
