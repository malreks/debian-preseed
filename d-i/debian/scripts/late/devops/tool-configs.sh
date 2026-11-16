#!/bin/sh
# Sourced installer module; edit this file directly.
# shellcheck disable=SC2154

devops_install_youtube_policy() (
  set -eu
  for directory in __INSTALLER_PATH_DIR_ETC__/yt-dlp __INSTALLER_PATH_DIR_ETC__/yt-dlp/plugins \
    ${DEVOPS_SKEL_DIR}/.config/yt-dlp ${DEVOPS_SKEL_DIR}/.config/yt-dlp/plugins \
    __INSTALLER_PATH_DIR_USR_LOCAL__/share/doc/yt-dlp; do
    host_directory="${target_root}${directory}"
    [ ! -L "$host_directory" ] || devops_fatal "symlinked downloader configuration directory: $directory"
    install -d -m 0755 -- "$host_directory"
    chown root:root "$host_directory"
  done
  for entry in "FILE_TARGET_YT_DLP_CONFIG|${DIR_ETC}/yt-dlp/config" \
    "FILE_TARGET_SKEL_YT_DLP_CONFIG|${DEVOPS_SKEL_DIR}/.config/yt-dlp/config" \
    "FILE_TARGET_SHARE_DOC_YT_DLP_CONFIGURATION|${DIR_USR_LOCAL_SHARE}/doc/yt-dlp/CONFIGURATION.md"; do
    selector=${entry%%|*}; path=${entry#*|}
    [ ! -e "${target_root}$path" ] && [ ! -L "${target_root}$path" ] ||
      devops_fatal "fresh-install downloader policy path already exists: $path"
    set --
    if [ "$selector" = FILE_TARGET_SKEL_YT_DLP_CONFIG ]; then
      set -- "stage downloader user configuration and plugin directory" \
        .config/yt-dlp/config 0600 .config/yt-dlp/plugins
    fi
    devops_stage_target_asset "$(installer_repo_file_value "$selector")" "$path" 0644 youtube-configuration "$@"
    chown root:root "${target_root}$path"
  done
)

devops_install_llama_runtime() {
  llama_repo_path=$(installer_repo_file_value FILE_LATE_LLAMA)
  llama_installer="${tmp_env_dir}/installer-llama-entry.$$"

  bootstrap_fetch_seed_file \
    "$seed_base" \
    "$llama_repo_path" \
    "$llama_installer" \
    0600 \
    "DevOps llama.cpp installer helper ${llama_repo_path}"
  chmod 0700 "$llama_installer"

  if ! INSTALLER_RUNTIME_DIR="$runtime_dir" \
       INSTALLER_BOOTSTRAP_LIB="$bootstrap_lib" \
       INSTALLER_LATE_HOST_ENV="$host_env" \
       INSTALLER_LLAMA_TMP_ENV_DIR="${tmp_env_dir}/llama" \
       __INSTALLER_PATH_DIR_BIN__/sh "$llama_installer" "$target_root"
  then
    rm -f -- "$llama_installer"
    devops_fatal "llama.cpp provisioning failed"
  fi
  rm -f -- "$llama_installer"
}

devops_render_cargo_config() {
  template_repo_path=$(installer_repo_file_value FILE_TARGET_SKEL_CARGO_CONFIG_TMPL)
  template_tmp="${tmp_env_dir}/cargo-config.toml.tmpl.$$"
  rendered_tmp="${tmp_env_dir}/cargo-config.toml.rendered.$$"
  target_cargo_dir="${target_root}${CARGO_HOME}"
  target_cargo_config="${target_cargo_dir}/config.toml"

  bootstrap_fetch_seed_file \
    "$seed_base" \
    "$template_repo_path" \
    "$template_tmp" \
    0600 \
    "DevOps Cargo config template ${template_repo_path}"
  installer_apply_scalar_placeholders \
    "$template_tmp" \
    "$rendered_tmp" \
    DEVOPS_CARGO_RUSTC_WRAPPER "$DEVOPS_CARGO_RUSTC_WRAPPER" \
    DEVOPS_CARGO_TARGET_TRIPLE "$DEVOPS_CARGO_TARGET_TRIPLE" \
    DEVOPS_CARGO_TARGET_LINKER "$DEVOPS_CARGO_TARGET_LINKER" \
    DEVOPS_CARGO_TARGET_CPU "$DEVOPS_CARGO_TARGET_CPU" \
    DEVOPS_CARGO_LINKER_ARGUMENT "$DEVOPS_CARGO_LINKER_ARGUMENT"
  installer_assert_no_unresolved_installer_placeholders \
    "$rendered_tmp" \
    "DevOps Cargo config template ${template_repo_path}"

  [ -d "$target_cargo_dir" ] ||
    devops_fatal "required Cargo home directory is missing: ${target_cargo_dir}"
  install -m 0644 "$rendered_tmp" "$target_cargo_config"
  chown "$account_ids" "$target_cargo_config"
  rm -f -- "$template_tmp" "$rendered_tmp"
}

devops_render_codex_sysctl() {
  template_repo_path=$(installer_repo_asset_path \
    DIR_HOOKS_TARGET \
    etc/sysctl.d/90-codex-bwrap.conf.tmpl)
  template_tmp="${tmp_env_dir}/codex-bwrap-sysctl.tmpl.$$"
  rendered_tmp="${tmp_env_dir}/codex-bwrap-sysctl.rendered.$$"
  target_sysctl_dir="${target_root}__INSTALLER_PATH_DIR_ETC__/sysctl.d"
  target_sysctl="${target_sysctl_dir}/90-codex-bwrap.conf"

  bootstrap_fetch_seed_file \
    "$seed_base" \
    "$template_repo_path" \
    "$template_tmp" \
    0600 \
    "DevOps Codex Bubblewrap sysctl template ${template_repo_path}"
  installer_apply_scalar_placeholders \
    "$template_tmp" \
    "$rendered_tmp" \
    DEVOPS_CODEX_BWRAP_USERNS_CLONE "$DEVOPS_CODEX_BWRAP_USERNS_CLONE" \
    DEVOPS_CODEX_BWRAP_MAX_USER_NAMESPACES "$DEVOPS_CODEX_BWRAP_MAX_USER_NAMESPACES"
  installer_assert_no_unresolved_installer_placeholders \
    "$rendered_tmp" \
    "DevOps Codex Bubblewrap sysctl template ${template_repo_path}"

  install -d -m 0755 "$target_sysctl_dir"
  install -m 0644 "$rendered_tmp" "$target_sysctl"
  chown root:root "$target_sysctl_dir" "$target_sysctl"
  rm -f -- "$template_tmp" "$rendered_tmp"
}

devops_render_codex_tmpfiles() {
  template_repo_path=$(installer_repo_asset_path \
    DIR_HOOKS_TARGET \
    etc/tmpfiles.d/80-codex-storage.conf.tmpl)
  template_tmp="${tmp_env_dir}/codex-storage-tmpfiles.tmpl.$$"
  rendered_tmp="${tmp_env_dir}/codex-storage-tmpfiles.rendered.$$"
  target_tmpfiles_dir="${target_root}__INSTALLER_PATH_DIR_ETC__/tmpfiles.d"
  target_tmpfiles="${target_tmpfiles_dir}/80-codex-storage.conf"

  bootstrap_fetch_seed_file \
    "$seed_base" \
    "$template_repo_path" \
    "$template_tmp" \
    0600 \
    "DevOps Codex tmpfiles template ${template_repo_path}"
  installer_apply_scalar_placeholders \
    "$template_tmp" \
    "$rendered_tmp" \
    ACCOUNT_USERNAME "$ACCOUNT_USERNAME" \
    DEVOPS_CODEX_ROOT "$DEVOPS_CODEX_ROOT" \
    DEVOPS_CODEX_BINARY_PATH "$DEVOPS_CODEX_BINARY_PATH" \
    DEVOPS_CODEX_WRAPPER_PATH "$DEVOPS_CODEX_WRAPPER_PATH" \
    DEVOPS_CODEX_USER_ROOT "$DEVOPS_CODEX_USER_ROOT" \
    DEVOPS_CODEX_SYSTEM_CONFIG_DIR "$DEVOPS_CODEX_SYSTEM_CONFIG_DIR" \
    DEVOPS_CODEX_LOG_DIR "$DEVOPS_CODEX_LOG_DIR" \
    DEVOPS_CODEX_SQLITE_HOME "$DEVOPS_CODEX_SQLITE_HOME" \
    DEVOPS_CODEX_RUNTIME_ROOT "$DEVOPS_CODEX_RUNTIME_ROOT" \
    DEVOPS_CODEX_AGENTS "$DEVOPS_CODEX_AGENTS" \
    DEVOPS_CODEX_HOME "$DEVOPS_CODEX_HOME" \
    DEVOPS_CODEX_SKILLS "$DEVOPS_CODEX_SKILLS"
  installer_assert_no_unresolved_installer_placeholders \
    "$rendered_tmp" \
    "DevOps Codex tmpfiles template ${template_repo_path}"

  install -d -m 0755 "$target_tmpfiles_dir"
  install -m 0644 "$rendered_tmp" "$target_tmpfiles"
  chown root:root "$target_tmpfiles_dir" "$target_tmpfiles"
  rm -f -- "$template_tmp" "$rendered_tmp"
}

devops_render_codex_logrotate() {
  template_repo_path=$(installer_repo_asset_path \
    DIR_HOOKS_TARGET \
    etc/logrotate.d/codex.tmpl)
  template_tmp="${tmp_env_dir}/codex-logrotate.tmpl.$$"
  rendered_tmp="${tmp_env_dir}/codex-logrotate.rendered.$$"
  target_logrotate_dir="${target_root}__INSTALLER_PATH_DIR_ETC__/logrotate.d"
  target_logrotate="${target_logrotate_dir}/codex"

  bootstrap_fetch_seed_file \
    "$seed_base" \
    "$template_repo_path" \
    "$template_tmp" \
    0600 \
    "DevOps Codex logrotate template ${template_repo_path}"
  installer_apply_scalar_placeholders \
    "$template_tmp" \
    "$rendered_tmp" \
    ACCOUNT_USERNAME "$ACCOUNT_USERNAME"
  installer_assert_no_unresolved_installer_placeholders \
    "$rendered_tmp" \
    "DevOps Codex logrotate template ${template_repo_path}"

  install -d -m 0755 "$target_logrotate_dir"
  install -m 0644 "$rendered_tmp" "$target_logrotate"
  chown root:root "$target_logrotate_dir" "$target_logrotate"
  rm -f -- "$template_tmp" "$rendered_tmp"
}

devops_render_bazelrc() {
  template_repo_path=$(installer_repo_file_value FILE_TARGET_SKEL_BAZEL_BAZELRC_TMPL)
  template_tmp="${tmp_env_dir}/bazelrc.tmpl.$$"
  rendered_tmp="${tmp_env_dir}/bazelrc.rendered.$$"
  target_bazel_dir="${target_root}${DEVOPS_SKEL_DIR}/.config/bazel"
  target_bazelrc="${target_bazel_dir}/bazelrc"

  bootstrap_fetch_seed_file \
    "$seed_base" \
    "$template_repo_path" \
    "$template_tmp" \
    0600 \
    "DevOps Bazel rc template ${template_repo_path}"
  set -- \
    DEVOPS_BAZEL_OUTPUT_USER_ROOT "$BAZEL_OUTPUT_USER_ROOT" \
    DEVOPS_BAZEL_SERVER_IDLE_SECONDS "$DEVOPS_BAZEL_SERVER_IDLE_SECONDS" \
    DEVOPS_BAZEL_DISK_CACHE "$BAZEL_DISK_CACHE" \
    DEVOPS_BAZEL_REPOSITORY_CACHE "$BAZEL_REPOSITORY_CACHE" \
    DEVOPS_BAZEL_REPOSITORY_DOWNLOADER_RETRIES "$DEVOPS_BAZEL_REPOSITORY_DOWNLOADER_RETRIES" \
    DEVOPS_BAZEL_DISK_CACHE_SIZE "$DEVOPS_BAZEL_DISK_CACHE_SIZE" \
    DEVOPS_BAZEL_DISK_CACHE_MAX_AGE "$DEVOPS_BAZEL_DISK_CACHE_MAX_AGE" \
    DEVOPS_BAZEL_DISK_CACHE_GC_IDLE_DELAY "$DEVOPS_BAZEL_DISK_CACHE_GC_IDLE_DELAY" \
    DEVOPS_BAZEL_ACTION_CACHE_MAX_AGE "$DEVOPS_BAZEL_ACTION_CACHE_MAX_AGE" \
    DEVOPS_BAZEL_ACTION_CACHE_GC_IDLE_DELAY "$DEVOPS_BAZEL_ACTION_CACHE_GC_IDLE_DELAY" \
    DEVOPS_BAZEL_ACTION_CACHE_GC_THRESHOLD "$DEVOPS_BAZEL_ACTION_CACHE_GC_THRESHOLD" \
    DEVOPS_BAZEL_INSTALL_BASE_GC_MAX_AGE "$DEVOPS_BAZEL_INSTALL_BASE_GC_MAX_AGE"
  installer_apply_scalar_placeholders "$template_tmp" "$rendered_tmp" "$@"
  installer_assert_no_unresolved_installer_placeholders \
    "$rendered_tmp" \
    "DevOps Bazel rc template ${template_repo_path}"

  # The installation account gets its concrete configured paths directly from
  # the rendered payload. Future-user defaults must not retain that identity.
  devops_publish_account_config "$rendered_tmp" \
    "publish the account Bazel cache policy" .bazelrc 0600
  devops_publish_account_config "$rendered_tmp" \
    "publish the account Bazel shell policy" .config/bazel/bazelrc 0600

  bazel_future_fields=$#
  while [ "$bazel_future_fields" -gt 0 ]; do
    bazel_future_key=$1; bazel_future_value=$2; shift 2
    bazel_future_fields=$((bazel_future_fields - 2))
    case "$bazel_future_key" in
      DEVOPS_BAZEL_OUTPUT_USER_ROOT|DEVOPS_BAZEL_DISK_CACHE|DEVOPS_BAZEL_REPOSITORY_CACHE)
        case "$bazel_future_value" in
          "$DIR_POOL_BUILD/$ACCOUNT_USERNAME/"*)
            bazel_future_value="${DIR_POOL_BUILD}/\$USER/${bazel_future_value#"$DIR_POOL_BUILD/$ACCOUNT_USERNAME/"}" ;;
          "$DIR_POOL_CACHE/$ACCOUNT_USERNAME/"*)
            bazel_future_value="${DIR_POOL_CACHE}/\$USER/${bazel_future_value#"$DIR_POOL_CACHE/$ACCOUNT_USERNAME/"}" ;;
          *) devops_fatal 'Bazel account cache path is outside its configured account root' ;;
        esac
        ;;
    esac
    set -- "$@" "$bazel_future_key" "$bazel_future_value"
  done
  installer_apply_scalar_placeholders "$template_tmp" "$rendered_tmp" "$@"
  installer_assert_no_unresolved_installer_placeholders "$rendered_tmp" 'future account Bazel defaults'
  install -d -m 0755 "$target_bazel_dir"
  for bazel_future_target in "$target_bazelrc" "${target_root}${DEVOPS_SKEL_DIR}/.bazelrc"; do
    [ ! -L "$bazel_future_target" ] || devops_fatal 'indirect future account Bazel configuration'
    install -m 0644 "$rendered_tmp" "$bazel_future_target"
    chown root:root "$bazel_future_target"
  done
  chown root:root "$target_bazel_dir"
  rm -f -- "$template_tmp" "$rendered_tmp"
}

devops_render_packer_template() {
  template_repo_path=$(installer_repo_file_value FILE_TARGET_SKEL_PACKER_TEMPLATE_PKR_HCL_TMPL)
  template_tmp="${tmp_env_dir}/packer-template.pkr.hcl.tmpl.$$"
  rendered_tmp="${tmp_env_dir}/packer-template.pkr.hcl.rendered.$$"
  target_skel_dir="${target_root}${DEVOPS_SKEL_DIR}/.config/packer"
  target_skel_template="${target_skel_dir}/template.pkr.hcl"

  bootstrap_fetch_seed_file \
    "$seed_base" \
    "$template_repo_path" \
    "$template_tmp" \
    0600 \
    "DevOps Packer template ${template_repo_path}"
  installer_apply_scalar_placeholders \
    "$template_tmp" \
    "$rendered_tmp" \
    DEVOPS_PACKER_VERSION "$DEVOPS_PACKER_VERSION"
  installer_assert_no_unresolved_installer_placeholders \
    "$rendered_tmp" \
    "DevOps Packer template ${template_repo_path}"

  install -d -m 0755 "$target_skel_dir"
  [ ! -e "$target_skel_template" ] && [ ! -L "$target_skel_template" ] ||
    devops_fatal "fresh-install Packer template path already exists: ${target_skel_template}"
  install -m 0644 "$rendered_tmp" "$target_skel_template"
  chown root:root "$target_skel_dir" "$target_skel_template"
  devops_publish_account_config "$rendered_tmp" \
    "stage managed Packer template for primary account" \
    .config/packer/template.pkr.hcl 0644 .config/mise
  rm -f -- "$template_tmp" "$rendered_tmp"
}

devops_write_packer_config() {
  target_packer_config="${target_root}${PACKER_CONFIG_PATH}"
  packer_config_tmp="${tmp_env_dir}/packer-config.json.$$"

  [ -d "$(dirname "$target_packer_config")" ] ||
    devops_fatal "required Packer config directory is missing: $(dirname "$target_packer_config")"
  [ ! -e "$target_packer_config" ] && [ ! -L "$target_packer_config" ] ||
    devops_fatal "fresh-install Packer config path already exists: ${target_packer_config}"
  printf '{}\n' >"$packer_config_tmp"
  install -m 0640 "$packer_config_tmp" "$target_packer_config"
  chown "$account_ids" "$target_packer_config"
  rm -f -- "$packer_config_tmp"
}

devops_initialize_packer_plugins() (
  set -eu
  # Fetch through the authenticated installer payload, then run without root.
  # Keep GitHub source identities in HCL; official binaries live at HashiCorp; Proxmox retains its pinned GitHub release.
  packer_helper=/tmp/installer-packer-plugins.py
  packer_helper_host="${target_root}${packer_helper}"
  [ ! -e "$packer_helper_host" ] && [ ! -L "$packer_helper_host" ] ||
    devops_fatal "temporary Packer plugin helper path already exists"
  trap 'rm -f -- "$packer_helper_host"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  bootstrap_fetch_seed_file \
    "$seed_base" \
    "$(installer_repo_file_value FILE_LATE_PACKER_PLUGINS)" \
    "$packer_helper_host" 0644 "signed Packer plugin initializer"
  chown root:root "$packer_helper_host"
  packer_init_status=0
  devops_run_as_account \
    "initialize exact-version Packer plugins from the managed HCL template" \
    __INSTALLER_PATH_DIR_USR_BIN__/timeout --signal=TERM --kill-after=30s \
      "${DEVOPS_PACKER_INIT_TIMEOUT_SECONDS}s" \
    __INSTALLER_PATH_DIR_USR_BIN__/python3 -I -B "$packer_helper" \
      "${ACCOUNT_HOME}/.config/packer/template.pkr.hcl" \
      "$DEVOPS_PACKER_BINARY_PATH" "$PACKER_PLUGIN_PATH" || packer_init_status=$?
  rm -f -- "$packer_helper_host"
  [ "$packer_init_status" -eq 0 ] ||
    devops_fatal "signed exact-version Packer plugin initialization failed (${packer_init_status})"
)
