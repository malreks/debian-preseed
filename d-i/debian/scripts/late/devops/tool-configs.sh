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
    devops_stage_target_asset "$(installer_repo_file_value "$selector")" "$path" 0644 youtube-configuration
    chown root:root "${target_root}$path"
  done
  # The account creates its own config and plugin directories. No privileged
  # writer follows same-UID desktop state, and no plugin is imported here.
  # shellcheck disable=SC2016
  devops_run_as_account "stage downloader user configuration and plugin directory" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
source_config=$1
config_root="${HOME}/.config"
downloader_config="${config_root}/yt-dlp"
ensure_directory() {
  directory=$1
  mode=$2
  [ ! -L "$directory" ] || { printf "fatal: symlinked downloader user directory\n" >&2; exit 1; }
  if [ -e "$directory" ]; then
    [ -d "$directory" ] || { printf "fatal: downloader path is not a directory\n" >&2; exit 1; }
  else
    __INSTALLER_PATH_DIR_USR_BIN__/mkdir -m "$mode" -- "$directory"
  fi
  metadata=$(__INSTALLER_PATH_DIR_USR_BIN__/find -P "$directory" -maxdepth 0 -printf "%U") || {
    printf "fatal: unable to inspect downloader user directory\n" >&2; exit 1;
  }
  set -- $metadata
  [ "$#" -eq 1 ] && [ "$1" = "$(__INSTALLER_PATH_DIR_USR_BIN__/id -u)" ] || {
    printf "fatal: downloader user directory is not privately owned\n" >&2; exit 1;
  }
  __INSTALLER_PATH_DIR_USR_BIN__/chmod "$mode" -- "$directory"
}
ensure_directory "$config_root" 0700
ensure_directory "$downloader_config" 0700
ensure_directory "$downloader_config/plugins" 0700
config_file="$downloader_config/config"
if [ -e "$config_file" ] || [ -L "$config_file" ]; then
  [ -f "$config_file" ] && [ ! -L "$config_file" ] || {
    printf "fatal: downloader user config is not a regular file\n" >&2; exit 1;
  }
  metadata=$(__INSTALLER_PATH_DIR_USR_BIN__/find -P "$config_file" -maxdepth 0 -printf "%U %n") || {
    printf "fatal: unable to inspect downloader user config\n" >&2; exit 1;
  }
  set -- $metadata
  [ "$#" -eq 2 ] && [ "$1" = "$(__INSTALLER_PATH_DIR_USR_BIN__/id -u)" ] && [ "$2" = 1 ] || {
    printf "fatal: downloader user config is not privately owned\n" >&2; exit 1;
  }
  printf "fatal: fresh-install downloader user config already exists\n" >&2
  exit 1
fi
__INSTALLER_PATH_DIR_USR_BIN__/install -m 0600 -- "$source_config" "$downloader_config/config"
' sh "${DEVOPS_SKEL_DIR}/.config/yt-dlp/config"
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
  installer_apply_scalar_placeholders \
    "$template_tmp" \
    "$rendered_tmp" \
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
  installer_assert_no_unresolved_installer_placeholders \
    "$rendered_tmp" \
    "DevOps Bazel rc template ${template_repo_path}"

  install -d -m 0755 "$target_bazel_dir"
  install -m 0644 "$rendered_tmp" "$target_bazelrc"
  chown root:root "$target_bazel_dir" "$target_bazelrc"
  rm -f -- "$template_tmp" "$rendered_tmp"

  # Bazel reads ~/.bazelrc without a desktop shell function. Publish the same
  # rendered policy for the human account; never overwrite existing settings.
  # The writer runs as that account, with a pinned home and no-replace create.
  # shellcheck disable=SC2016
  devops_run_as_account "publish the account Bazel cache policy" "${DIR_USR_BIN}/python3" -I -c '
import os, pathlib, stat, sys
source=pathlib.Path(sys.argv[1])
if source.resolve(strict=True)!=source:
    raise SystemExit("indirect Bazel policy source")
fd=os.open(source,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK|os.O_CLOEXEC)
try:
    info=os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_nlink!=1 or info.st_uid or info.st_mode&0o022 or info.st_size>16384:
        raise SystemExit("unsafe Bazel policy source")
    data=os.read(fd,16385)
    if len(data)>16384:
        raise SystemExit("oversized Bazel policy source")
finally: os.close(fd)
home=os.open(os.environ["HOME"],os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|os.O_CLOEXEC)
try:
    info=os.fstat(home)
    if info.st_uid!=os.getuid() or info.st_mode&0o022:
        raise SystemExit("unsafe Bazel account home")
    try:
        fd=os.open(".bazelrc",os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW|os.O_CLOEXEC,0o600,dir_fd=home)
    except FileExistsError:
        fd=os.open(".bazelrc",os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK|os.O_CLOEXEC,dir_fd=home)
        try:
            info=os.fstat(fd)
            if (not stat.S_ISREG(info.st_mode) or info.st_nlink!=1 or info.st_uid!=os.getuid()
                    or stat.S_IMODE(info.st_mode)!=0o600 or info.st_size!=len(data)
                    or os.read(fd,len(data)+1)!=data):
                raise SystemExit("existing Bazel account policy differs; preserve it for review")
        finally: os.close(fd)
    else:
        with os.fdopen(fd,"wb") as stream:
            stream.write(data); stream.flush(); os.fsync(stream.fileno())
        os.fsync(home)
finally: os.close(home)
' "${DEVOPS_SKEL_DIR}/.config/bazel/bazelrc"
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
  rm -f -- "$template_tmp" "$rendered_tmp"

  # Stage the account copy from inside the target namespace. This guarantees
  # that the path validated below is the same path later seen by runuser.
  # shellcheck disable=SC2016
  run_in_target "stage managed Packer template for primary account" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
packer_fatal() {
  printf "fatal: %s\n" "$*" >&2
  exit 1
}

account_user=$1
account_home=$2
source_template=$3
config_dir="${account_home}/.config"
template_dir="${config_dir}/packer"
target_template="${template_dir}/template.pkr.hcl"
mise_config_dir="${config_dir}/mise"

for required_command in awk chmod chown getent id install runuser find; do
  command -v "$required_command" >__INSTALLER_PATH_DIR_DEV__/null 2>&1 ||
    packer_fatal "required Packer template staging command is unavailable: $required_command"
done
[ -x __INSTALLER_PATH_DIR_USR_BIN__/test ] ||
  packer_fatal "required Packer template access test is unavailable: __INSTALLER_PATH_DIR_USR_BIN__/test"

account_record=$(getent passwd "$account_user") ||
  packer_fatal "primary account is unavailable while staging Packer policy: $account_user"
resolved_home=$(printf "%s\n" "$account_record" | awk -F: "{ print \$6; exit }")
[ "$resolved_home" = "$account_home" ] ||
  packer_fatal "primary account home does not match Packer policy: expected $account_home, found ${resolved_home:-unset}"
account_uid=$(id -u "$account_user")
account_gid=$(id -g "$account_user")
case "$account_uid:$account_gid" in
  0:*|65534:*|*:65534|*[!0123456789:]*)
    packer_fatal "unsafe primary account identity for Packer policy: $account_uid:$account_gid"
    ;;
esac

[ -d "$account_home" ] && [ ! -L "$account_home" ] ||
  packer_fatal "primary account home is unavailable or unsafe: $account_home"
[ -f "$source_template" ] && [ ! -L "$source_template" ] ||
  packer_fatal "managed Packer skeleton template is unavailable or unsafe: $source_template"
for managed_path in \
  "$config_dir" \
  "$template_dir" \
  "$target_template" \
  "$mise_config_dir"
do
  [ ! -L "$managed_path" ] ||
    packer_fatal "managed Packer account path must not be a symlink: $managed_path"
done

install -d -m 0755 "$config_dir"
install -d -m 0700 "$template_dir"
install -d -m 0755 "$mise_config_dir"
[ ! -e "$target_template" ] ||
  packer_fatal "fresh-install Packer account template already exists: $target_template"
install -m 0644 "$source_template" "$target_template"
chown "$account_uid:$account_gid" \
  "$config_dir" \
  "$template_dir" \
  "$target_template" \
  "$mise_config_dir"
chmod 0755 "$config_dir"
chmod 0700 "$template_dir"
chmod 0644 "$target_template"
chmod 0755 "$mise_config_dir"

[ "$(find -P "$config_dir" -maxdepth 0 -printf "%U:%G:%m")" = "$account_uid:$account_gid:755" ] ||
  packer_fatal "Packer account config directory ownership or mode is invalid: $config_dir"
[ "$(find -P "$template_dir" -maxdepth 0 -printf "%U:%G:%m")" = "$account_uid:$account_gid:700" ] ||
  packer_fatal "Packer template directory ownership or mode is invalid: $template_dir"
[ "$(find -P "$target_template" -maxdepth 0 -printf "%U:%G:%m")" = "$account_uid:$account_gid:644" ] ||
  packer_fatal "Packer account template ownership or mode is invalid: $target_template"
[ "$(find -P "$mise_config_dir" -maxdepth 0 -printf "%U:%G:%m")" = "$account_uid:$account_gid:755" ] ||
  packer_fatal "Mise account config directory ownership or mode is invalid: $mise_config_dir"
__INSTALLER_PATH_DIR_USR_SBIN__/runuser -u "$account_user" -- __INSTALLER_PATH_DIR_USR_BIN__/test -x "$template_dir" ||
  packer_fatal "primary account cannot traverse the managed Packer template directory"
__INSTALLER_PATH_DIR_USR_SBIN__/runuser -u "$account_user" -- __INSTALLER_PATH_DIR_USR_BIN__/test -r "$target_template" ||
  packer_fatal "primary account cannot read the managed Packer template"
__INSTALLER_PATH_DIR_USR_SBIN__/runuser -u "$account_user" -- __INSTALLER_PATH_DIR_USR_BIN__/test -x "$mise_config_dir" ||
  packer_fatal "primary account cannot traverse the managed Mise config directory"
' sh "$ACCOUNT_USERNAME" "$ACCOUNT_HOME" "${DEVOPS_SKEL_DIR}/.config/packer/template.pkr.hcl"
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
