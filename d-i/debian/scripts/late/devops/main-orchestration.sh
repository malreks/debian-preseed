#!/bin/sh
# Sourced installer module; edit this file directly.

devops_main() {
target_root=${1:-${TARGET_ROOT}}
runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}
tmp_env_dir=${INSTALLER_LATE_TMP_ENV_DIR:-${DIR_INSTALLER_LATE_ENV}/devops}

seed_base=$(installer_current_seed_base 2>__INSTALLER_PATH_DIR_DEV__/null || installer_seed_base "")
bootstrap_source_common_support_libs "$seed_base" "$tmp_env_dir" target fetch ssh ||
  devops_fatal "failed to source installer target support library"
installer_ensure_context_loaded "$seed_base"

installer_tools_class_selected 2>__INSTALLER_PATH_DIR_DEV__/null || exit 0

case "${INSTALLER_HOST_VARIANT:-}" in
  desktop) DEVOPS_SKEL_DIR=$DIR_ETC_SKEL_DESKTOP ;;
  server) DEVOPS_SKEL_DIR=$DIR_ETC_SKEL_SERVER ;;
  *) devops_fatal "unregistered DevOps role family" ;;
esac

account_env=${INSTALLER_LATE_ACCOUNT_ENV:-${DIR_INSTALLER_LATE_ENV}/account.env}
[ -r "$account_env" ] ||
  installer_prepare_late_account_env "$seed_base" "$account_env"

# The entrypoint has already loaded the composite before sourcing this module.
# shellcheck disable=SC1090,SC1091
unset ACCOUNT_USERNAME ACCOUNT_HOME
installer_load_data_env "$account_env"

: "${ACCOUNT_USERNAME:?ACCOUNT_USERNAME must be set before DevOps provisioning}"
: "${ACCOUNT_HOME:?ACCOUNT_HOME must be set before DevOps provisioning}"
: "${DIR_POOL_BUILD:?DIR_POOL_BUILD must be set before DevOps provisioning}"
: "${DIR_POOL_CACHE:?DIR_POOL_CACHE must be set before DevOps provisioning}"
: "${DIR_POOL_DB:?DIR_POOL_DB must be set before DevOps provisioning}"

devops_validate_account_name "$ACCOUNT_USERNAME"
devops_validate_abs_path "ACCOUNT_HOME" "$ACCOUNT_HOME"
devops_validate_abs_path "DIR_POOL_BUILD" "$DIR_POOL_BUILD"
devops_validate_abs_path "DIR_POOL_CACHE" "$DIR_POOL_CACHE"
devops_validate_abs_path "DIR_POOL_DB" "$DIR_POOL_DB"
devops_validate_upstream_tool_policy
devops_validate_cargo_policy
devops_validate_bazel_policy
devops_validate_publishing_policy
devops_validate_codex_policy
devops_load_publishing_credentials

for pool_root in "$DIR_POOL_BUILD" "$DIR_POOL_CACHE" "$DIR_POOL_DB"; do
  [ -d "${target_root}${pool_root}" ] ||
    devops_fatal "shared runtime storage root is missing: ${target_root}${pool_root}"
done
unset pool_root

account_ids=$(devops_target_passwd_ids "$ACCOUNT_USERNAME")
[ -n "$account_ids" ] ||
  devops_fatal "target primary account is missing: $ACCOUNT_USERNAME"
case "${account_ids%%:*}" in
  ''|0|*[!0-9]*) devops_fatal "DevOps tool provisioning must use a non-root target UID" ;;
esac
case "$ACCOUNT_HOME" in
  __INSTALLER_PATH_DIR_ROOT_HOME__|__INSTALLER_PATH_DIR_ROOT_HOME__/*) devops_fatal "DevOps tool state must not use root's home" ;;
esac

devops_codex_paths
CARGO_HOME="${DIR_POOL_CACHE}/${ACCOUNT_USERNAME}/cargo"
CARGO_TARGET_DIR="${DIR_POOL_BUILD}/${ACCOUNT_USERNAME}/cargo/target"
CARGO_INSTALL_ROOT="${DIR_POOL_BUILD}/${ACCOUNT_USERNAME}/cargo/install"
RUSTUP_HOME="${DIR_POOL_DB}/${ACCOUNT_USERNAME}/rustup"
SCCACHE_DIR="${DIR_POOL_CACHE}/${ACCOUNT_USERNAME}/sccache"
GOPATH="${DIR_POOL_BUILD}/${ACCOUNT_USERNAME}/go"
GOMODCACHE="${DIR_POOL_CACHE}/${ACCOUNT_USERNAME}/go-mod"
GOCACHE="${DIR_POOL_CACHE}/${ACCOUNT_USERNAME}/go-build"
GOENV="${DIR_POOL_DB}/${ACCOUNT_USERNAME}/go/env"
GOTMPDIR="${DIR_POOL_BUILD}/${ACCOUNT_USERNAME}/go/tmp"
MISE_DATA_DIR="${DIR_POOL_DB}/${ACCOUNT_USERNAME}/mise/data"
MISE_STATE_DIR="${DIR_POOL_DB}/${ACCOUNT_USERNAME}/mise/state"
MISE_CACHE_DIR="${DIR_POOL_CACHE}/${ACCOUNT_USERNAME}/mise"
MISE_TMP_DIR="${DIR_POOL_CACHE}/${ACCOUNT_USERNAME}/mise/tmp"
BAZEL_CACHE_HOME="${DEVOPS_BAZEL_CACHE_ROOT}/${ACCOUNT_USERNAME}/${DEVOPS_BAZEL_CACHE_SUBDIR}"
BAZEL_DISK_CACHE="${BAZEL_CACHE_HOME}/${DEVOPS_BAZEL_DISK_CACHE_SUBDIR}"
BAZEL_REPOSITORY_CACHE="${BAZEL_CACHE_HOME}/${DEVOPS_BAZEL_REPOSITORY_CACHE_SUBDIR}"
BAZEL_OUTPUT_USER_ROOT="${DEVOPS_BAZEL_BUILD_ROOT}/${ACCOUNT_USERNAME}/${DEVOPS_BAZEL_OUTPUT_USER_ROOT_SUBDIR}"
BAZELISK_HOME="${DEVOPS_BAZEL_DB_ROOT}/${ACCOUNT_USERNAME}/${DEVOPS_BAZELISK_HOME_SUBDIR}"
ANSIBLE_HOME="${DIR_POOL_DB}/${ACCOUNT_USERNAME}/ansible"
ANSIBLE_GALAXY_CACHE_DIR="${DIR_POOL_CACHE}/${ACCOUNT_USERNAME}/ansible/galaxy"
HASHICORP_CACHE_ROOT="${DIR_POOL_CACHE}/${ACCOUNT_USERNAME}/hashicorp"
PACKER_CACHE_DIR="${HASHICORP_CACHE_ROOT}/packer/cache"
PACKER_CONFIG_DIR="${HASHICORP_CACHE_ROOT}/packer.d"
PACKER_CONFIG_PATH="${PACKER_CONFIG_DIR}/config.json"
PACKER_PLUGIN_PATH="${PACKER_CONFIG_DIR}/plugins"
TF_PLUGIN_CACHE_DIR="${HASHICORP_CACHE_ROOT}/terraform/plugin-cache"
APTLY_ROOT_DIR="${DIR_POOL_DB}/${ACCOUNT_USERNAME}/${DEVOPS_APTLY_ROOT_SUBDIR}"
APTLY_CONFIG="${APTLY_ROOT_DIR}/aptly.conf"
APTLY_R2_STORAGE_PREFIX=${DEVOPS_APTLY_R2_PREFIX#/}
APTLY_R2_STORAGE_PREFIX="${APTLY_R2_STORAGE_PREFIX%/}/"
OSC_STATE_DIR="${DIR_POOL_DB}/${ACCOUNT_USERNAME}/${DEVOPS_OSC_SUBDIR}"
OSC_CONFIG="${OSC_STATE_DIR}/oscrc"
OSC_MANAGED_CONFIG="${OSC_STATE_DIR}/managed.json"
OSC_COOKIE_JAR="${OSC_STATE_DIR}/cookiejar"
OSC_WORKDIR="${DIR_POOL_BUILD}/${ACCOUNT_USERNAME}/${DEVOPS_OSC_SUBDIR}"
OSC_BUILD_ROOT="${OSC_WORKDIR}/build-root"
OSC_PACKAGE_CACHE_DIR="${DIR_POOL_CACHE}/${ACCOUNT_USERNAME}/${DEVOPS_OSC_SUBDIR}/packages"

for devops_path in \
  "$BAZEL_CACHE_HOME" \
  "$BAZEL_DISK_CACHE" \
  "$BAZEL_REPOSITORY_CACHE" \
  "$BAZEL_OUTPUT_USER_ROOT" \
  "$BAZELISK_HOME" \
  "$ANSIBLE_HOME" \
  "$ANSIBLE_GALAXY_CACHE_DIR" \
  "$HASHICORP_CACHE_ROOT" \
  "$PACKER_CACHE_DIR" \
  "$PACKER_CONFIG_DIR" \
  "$PACKER_CONFIG_PATH" \
  "$PACKER_PLUGIN_PATH" \
  "$TF_PLUGIN_CACHE_DIR" \
  "$GOPATH" \
  "$GOMODCACHE" \
  "$GOCACHE" \
  "$GOENV" \
  "$GOTMPDIR" \
  "$APTLY_ROOT_DIR" \
  "$APTLY_CONFIG" \
  "$OSC_STATE_DIR" \
  "$OSC_CONFIG" \
  "$OSC_MANAGED_CONFIG" \
  "$OSC_COOKIE_JAR" \
  "$OSC_WORKDIR" \
  "$OSC_BUILD_ROOT" \
  "$OSC_PACKAGE_CACHE_DIR" \
  "$DEVOPS_CODEX_STANDALONE_INSTALLER_HELPER" \
  "$DEVOPS_CODEX_INSTALLER_SESSION_HELPER" \
  "$DEVOPS_CODEX_PACKAGES_ROOT" \
  "$DEVOPS_CODEX_SOCKETS_ROOT" \
  "$DEVOPS_CODEX_CREDENTIALS_ROOT" \
  "$DEVOPS_CODEX_APP_SERVER_SOCKET" \
  "$DEVOPS_CODEX_APP_SERVER_BACKEND_SOCKET" \
  "$DEVOPS_CODEX_APP_SERVER_CONTROL_DIR" \
  "$DEVOPS_CODEX_APP_SERVER_STARTUP_LOCK" \
  "$DEVOPS_CODEX_APP_SERVER_DEFAULT_SOCKET" \
  "$DEVOPS_CODEX_APP_SERVER_ENVIRONMENT" \
  "$DEVOPS_CODEX_APP_SERVER_READY_HELPER" \
  "$DEVOPS_CODEX_APP_SERVER_USER_UNIT" \
  "$DEVOPS_CODEX_APP_SERVER_USER_PROXY_UNIT" \
  "$DEVOPS_CODEX_APP_SERVER_USER_SOCKET_UNIT" \
  "$DEVOPS_CODEX_APP_SERVER_USER_SOCKET_WANTS"
do
  devops_validate_abs_path "derived DevOps path" "$devops_path"
done
unset devops_path

# shellcheck disable=SC2016
run_in_target "create desktop DevOps runtime directories" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
account_user=$1
build_root=$2
cache_root=$3
db_root=$4
bazel_cache_subdir=$5
bazel_disk_cache_subdir=$6
bazel_repository_cache_subdir=$7
bazel_output_user_root_subdir=$8
bazelisk_home_subdir=$9

for required_command in getent install; do
  command -v "$required_command" >__INSTALLER_PATH_DIR_DEV__/null 2>&1 || {
    printf "fatal: required DevOps target command is unavailable: %s\n" "$required_command" >&2
    exit 1
  }
done
getent group devops >__INSTALLER_PATH_DIR_DEV__/null 2>&1 || {
  printf "fatal: required target group is missing: devops\n" >&2
  exit 1
}

for runtime_path in \
  "$build_root/$account_user" \
  "$build_root/$account_user/cargo" \
  "$build_root/$account_user/cargo/target" \
  "$build_root/$account_user/cargo/install" \
  "$build_root/$account_user/deno" \
  "$build_root/$account_user/deno/bin" \
  "$build_root/$account_user/go" \
  "$build_root/$account_user/go/bin" \
  "$build_root/$account_user/go/tmp" \
  "$build_root/$account_user/npm-global" \
  "$build_root/$account_user/pnpm" \
  "$build_root/$account_user/pnpm/bin" \
  "$build_root/$account_user/pnpm/global" \
  "$build_root/$account_user/python" \
  "$build_root/$account_user/python/bin" \
  "$build_root/$account_user/uv" \
  "$build_root/$account_user/uv/bin" \
  "$build_root/$account_user/yarn-global" \
  "$build_root/$account_user/$bazel_output_user_root_subdir" \
  "$cache_root/$account_user" \
  "$cache_root/$account_user/cargo" \
  "$cache_root/$account_user/deno" \
  "$cache_root/$account_user/mise" \
  "$cache_root/$account_user/mise/tmp" \
  "$cache_root/$account_user/npm" \
  "$cache_root/$account_user/corepack" \
  "$cache_root/$account_user/go-mod" \
  "$cache_root/$account_user/go-build" \
  "$cache_root/$account_user/pnpm" \
  "$cache_root/$account_user/pnpm/cache" \
  "$cache_root/$account_user/pnpm/store" \
  "$cache_root/$account_user/pip" \
  "$cache_root/$account_user/ansible" \
  "$cache_root/$account_user/ansible/galaxy" \
  "$cache_root/$account_user/hashicorp" \
  "$cache_root/$account_user/hashicorp/packer" \
  "$cache_root/$account_user/hashicorp/packer/cache" \
  "$cache_root/$account_user/hashicorp/packer.d" \
  "$cache_root/$account_user/hashicorp/packer.d/plugins" \
  "$cache_root/$account_user/hashicorp/terraform" \
  "$cache_root/$account_user/hashicorp/terraform/plugin-cache" \
  "$cache_root/$account_user/sccache" \
  "$cache_root/$account_user/uv" \
  "$cache_root/$account_user/yarn" \
  "$cache_root/$account_user/$bazel_cache_subdir" \
  "$cache_root/$account_user/$bazel_cache_subdir/$bazel_disk_cache_subdir" \
  "$cache_root/$account_user/$bazel_cache_subdir/$bazel_repository_cache_subdir" \
  "$db_root/$account_user" \
  "$db_root/$account_user/ansible" \
  "$db_root/$account_user/deno" \
  "$db_root/$account_user/go" \
  "$db_root/$account_user/mise" \
  "$db_root/$account_user/mise/data" \
  "$db_root/$account_user/mise/state" \
  "$db_root/$account_user/node" \
  "$db_root/$account_user/pnpm" \
  "$db_root/$account_user/pnpm/state" \
  "$db_root/$account_user/python" \
  "$db_root/$account_user/rustup" \
  "$db_root/$account_user/uv" \
  "$db_root/$account_user/uv/tools" \
  "$db_root/$account_user/$bazelisk_home_subdir"
do
  install -d -m 2770 -o "$account_user" -g devops -- "$runtime_path"
done
' sh \
  "$ACCOUNT_USERNAME" \
  "$DIR_POOL_BUILD" \
  "$DIR_POOL_CACHE" \
  "$DIR_POOL_DB" \
  "$DEVOPS_BAZEL_CACHE_SUBDIR" \
  "$DEVOPS_BAZEL_DISK_CACHE_SUBDIR" \
  "$DEVOPS_BAZEL_REPOSITORY_CACHE_SUBDIR" \
  "$DEVOPS_BAZEL_OUTPUT_USER_ROOT_SUBDIR" \
  "$DEVOPS_BAZELISK_HOME_SUBDIR"

install -d -m 0700 "$tmp_env_dir"
devops_prepare_publishing_layout
devops_render_aptly_config
devops_import_aptly_signing_key
devops_render_osc_config
devops_stage_publishing_entrypoints
devops_stage_gitbuild
devops_stage_target_asset \
  "$(installer_repo_file_value hooks/target/usr/local/bin/desktop/youtube-dl)" \
  __INSTALLER_PATH_DIR_USR_LOCAL__/bin/youtube-dl \
  0755 \
  youtube-downloader
chown root:root "${target_root}__INSTALLER_PATH_DIR_USR_LOCAL__/bin/youtube-dl"
devops_stage_target_asset \
  "$(installer_repo_file_value hooks/target/usr/local/bin/desktop/yt-dlp)" \
  __INSTALLER_PATH_DIR_USR_LOCAL__/bin/yt-dlp \
  0755 \
  yt-dlp-cli
chown root:root "${target_root}__INSTALLER_PATH_DIR_USR_LOCAL__/bin/yt-dlp"
devops_install_youtube_policy
devops_stage_pending_credentials
unset \
  DEVOPS_CF_R2_ACCESS_KEY \
  DEVOPS_CF_R2_SECRET_KEY \
  DEVOPS_OBS_USERNAME \
  DEVOPS_OBS_PASSWORD
devops_render_bazelrc
devops_render_cargo_config
devops_render_packer_template
devops_write_packer_config

devops_install_pinned_node_runtimes
devops_install_upstream_tools
devops_initialize_packer_plugins
devops_initialize_aptly_repositories
devops_install_pinned_rustup
devops_install_pinned_bazelisk
if [ "$INSTALLER_HOST_VARIANT" = server ]; then
  for bazel_command in bazel bazelisk; do
    devops_stage_publishing_command_link "$bazel_command" \
      "${target_root}${DIR_USR_LOCAL_BIN}/$bazel_command" "$DEVOPS_BAZELISK_BINARY_PATH"
  done
fi
if [ "$INSTALLER_HOST_VARIANT" = desktop ]; then devops_install_llama_runtime; fi
devops_run_as_account \
  "initialize pinned Rustup with the profile-selected toolchain without changing shell startup files" \
  __INSTALLER_PATH_DIR_USR_BIN__/timeout \
    --signal=TERM \
    --kill-after=30s \
    1200s \
    "$DEVOPS_RUSTUP_BINARY_PATH" \
      -y \
      --no-modify-path \
      --default-toolchain \
      "$DEVOPS_RUSTUP_TOOLCHAIN" \
      --profile \
      minimal
devops_install_pinned_rust_cli_binaries
# shellcheck disable=SC2016
devops_run_as_account \
  "install rustfmt and source-selected pinned Rust CLI tools" \
  __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
dotslash_source_build=$1
dotslash_version=$2
dotslash_commit=$3
dotslash_repository_url=$4
uv_source_build=$5
uv_version=$6

for tool_version in "$dotslash_version" "$uv_version"; do
  printf "%s\n" "$tool_version" |
    grep -Eq "^[0-9]+\.[0-9]+\.[0-9]+$" || {
    printf "fatal: Rust CLI tool version is malformed\n" >&2
    exit 1
  }
done
unset tool_version
for source_build_flag in "$dotslash_source_build" "$uv_source_build"; do
  case "$source_build_flag" in
    0|1) ;;
    *)
      printf "fatal: Rust CLI source-build flag must be 0 or 1\n" >&2
      exit 1
      ;;
  esac
done
unset source_build_flag
[ "${#dotslash_commit}" -eq 40 ] &&
  ! printf "%s\n" "$dotslash_commit" | grep -q "[^0-9a-f]" || {
    printf "fatal: DotSlash commit is malformed\n" >&2
    exit 1
  }
case "$dotslash_repository_url" in
  https://github.com/*) ;;
  *)
    printf "fatal: DotSlash repository URL is not HTTPS GitHub\n" >&2
    exit 1
    ;;
esac

for required_command in cargo rustup; do
  command -v "$required_command" >__INSTALLER_PATH_DIR_DEV__/null 2>&1 || {
    printf "fatal: required Rust tool command is unavailable: %s\n" "$required_command" >&2
    exit 1
  }
done
[ -x __INSTALLER_PATH_DIR_USR_BIN__/timeout ] || {
  printf "fatal: required Rust tool command is unavailable: __INSTALLER_PATH_DIR_USR_BIN__/timeout\n" >&2
  exit 1
}

__INSTALLER_PATH_DIR_USR_BIN__/timeout \
  --signal=TERM \
  --kill-after=30s \
  1200s \
  rustup component add rustfmt --toolchain nightly

__INSTALLER_PATH_DIR_USR_BIN__/timeout \
  --signal=TERM \
  --kill-after=30s \
  1200s \
  rustup component add rust-src --toolchain nightly

CARGO_NET_RETRY=3 \
  __INSTALLER_PATH_DIR_USR_BIN__/timeout \
    --signal=TERM \
    --kill-after=30s \
    3600s \
    cargo binstall \
      --no-confirm \
      --locked \
      --root "$CARGO_INSTALL_ROOT" \
      bpf-linker

if [ "$dotslash_source_build" = 1 ]; then
  CARGO_NET_RETRY=3 \
    __INSTALLER_PATH_DIR_USR_BIN__/timeout \
      --signal=TERM \
      --kill-after=30s \
      3600s \
      cargo install \
        --locked \
        --root "$CARGO_INSTALL_ROOT" \
        --git "$dotslash_repository_url" \
        --rev "$dotslash_commit" \
        dotslash
fi

if [ "$uv_source_build" = 1 ]; then
  CARGO_NET_RETRY=3 \
    __INSTALLER_PATH_DIR_USR_BIN__/timeout \
      --signal=TERM \
      --kill-after=30s \
      7200s \
      cargo install \
        --locked \
        --root "$CARGO_INSTALL_ROOT" \
        --version "$uv_version" \
        uv
fi
' sh \
  "$DEVOPS_DOTSLASH_SOURCE_BUILD" \
  "$DEVOPS_DOTSLASH_VERSION" \
  "$DEVOPS_DOTSLASH_COMMIT" \
  "$DEVOPS_DOTSLASH_REPOSITORY_URL" \
  "$DEVOPS_UV_SOURCE_BUILD" \
  "$DEVOPS_UV_VERSION"

# shellcheck disable=SC2016
devops_run_as_account "link preinstalled Node runtimes into Mise" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
command -v mise >__INSTALLER_PATH_DIR_DEV__/null 2>&1
for mise_directory in \
  "$MISE_CONFIG_DIR" \
  "$MISE_DATA_DIR" \
  "$MISE_STATE_DIR" \
  "$MISE_CACHE_DIR" \
  "$MISE_TMP_DIR"
do
  [ -d "$mise_directory" ] && [ ! -L "$mise_directory" ] || {
    printf "fatal: managed Mise directory is unavailable or unsafe: %s\n" "$mise_directory" >&2
    exit 1
  }
done
while [ "$#" -gt 0 ]; do
  node_version=$1
  node_root=$2
  shift 2
  test -x "${node_root}__INSTALLER_PATH_DIR_BIN__/node"
  mise link --force "node@${node_version}" "$node_root"
done
mise reshim
' sh \
  "$DEVOPS_NODE_22_MAJOR" "$DEVOPS_NODE_22_INSTALL_ROOT" \
  "$DEVOPS_NODE_24_MAJOR" "$DEVOPS_NODE_24_INSTALL_ROOT" \
  "$DEVOPS_NODE_26_MAJOR" "$DEVOPS_NODE_26_INSTALL_ROOT"

  devops_info \
  "configured non-GUI toolchains account=${ACCOUNT_USERNAME} codex=${DEVOPS_CODEX_VERSION} sandbox=bubblewrap:network=host:isolated-network=opt-in AI=profile-selected-only node=${DEVOPS_NODE_22_MAJOR},${DEVOPS_NODE_24_MAJOR},${DEVOPS_NODE_26_MAJOR} via Mise Corepack=enabled deno=${DEVOPS_DENO_VERSION} yt-dlp=${DEVOPS_YT_DLP_VERSION}+bundled-yt-dlp-ejs ffmpeg=system rustup=${DEVOPS_RUSTUP_VERSION} toolchain=${DEVOPS_RUSTUP_TOOLCHAIN} rustfmt=enabled rust-src=nightly cargo-binstall=prebuilt@${DEVOPS_CARGO_BINSTALL_VERSION} bpf-linker=binstall dotslash=${DEVOPS_DOTSLASH_VERSION}@${DEVOPS_DOTSLASH_COMMIT}:source-build=${DEVOPS_DOTSLASH_SOURCE_BUILD} uv=${DEVOPS_UV_VERSION}:source-build=${DEVOPS_UV_SOURCE_BUILD} cargo_target_cpu=${DEVOPS_CARGO_TARGET_CPU} cargo_jobs=cargo-default llvm=21,22,24 direct bazelisk=${DEVOPS_BAZELISK_VERSION} ansible-core=${DEVOPS_ANSIBLE_CORE_VERSION} opentofu=${DEVOPS_OPENTOFU_VERSION} terraform=${DEVOPS_TERRAFORM_VERSION} packer=${DEVOPS_PACKER_VERSION} wrangler=${DEVOPS_WRANGLER_VERSION} aptly=${DEVOPS_APTLY_RELEASE_VERSION} osc=${DEVOPS_OSC_RELEASE_VERSION} obs-build=${DEVOPS_OBS_BUILD_TAG} publication=stable,testing:r2+home:cramerz:debian"
}
