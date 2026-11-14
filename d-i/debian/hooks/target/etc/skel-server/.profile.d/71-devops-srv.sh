# Headless server DevOps account environment; installed only by role/server/devops.
# Login never starts a service or an engine. Installer-created account roots
# are private; never create a fallback store in HOME or on the root filesystem.
server_devops_user=$(__INSTALLER_PATH_DIR_USR_BIN__/id -un) || return 1
case "$server_devops_user" in ''|*[!a-z0-9_-]*) return 1 ;; esac
__INSTALLER_PATH_DIR_USR_BIN__/mountpoint -q -- __INSTALLER_PATH_DIR_POOL__ || {
  printf '%s\n' 'server DevOps: the data pool is not mounted' >&2
  return 1
}
server_devops_build=__INSTALLER_PATH_DIR_POOL_BUILD__/$server_devops_user
server_devops_cache=__INSTALLER_PATH_DIR_POOL_CACHE__/$server_devops_user
server_devops_db=__INSTALLER_PATH_DIR_POOL_DB__/$server_devops_user
server_devops_podman=__INSTALLER_PATH_DIR_POOL_PODMAN__/devops/$server_devops_user
for server_devops_root in "$server_devops_build" "$server_devops_cache" "$server_devops_db" "$server_devops_podman"; do
  [ -d "$server_devops_root" ] && [ ! -L "$server_devops_root" ] && [ -O "$server_devops_root" ] || return 1
done

# Compilation outputs, temporary files, language caches and toolchain state.
TMPDIR=$server_devops_build/tmp
CARGO_HOME=$server_devops_cache/cargo
CARGO_TARGET_DIR=$server_devops_build/cargo/target
CARGO_INSTALL_ROOT=$server_devops_build/cargo/install
RUSTUP_HOME=$server_devops_db/rustup
SCCACHE_DIR=$server_devops_cache/sccache
GOCACHE=$server_devops_cache/go-build
GOPATH=$server_devops_build/go
GOMODCACHE=$server_devops_cache/go-mod
GOTMPDIR=$server_devops_build/go/tmp
GOTOOLCHAIN=local
GOBIN=$GOPATH/bin
GOENV=$server_devops_db/go/env
DENO_DIR=$server_devops_cache/deno
DENO_INSTALL=$server_devops_build/deno
UV_TOOL_DIR=$server_devops_db/uv/tools
UV_TOOL_BIN_DIR=$server_devops_build/uv/bin
NPM_CONFIG_CACHE=$server_devops_cache/npm
NPM_CONFIG_PREFIX=$server_devops_build/npm-global
COREPACK_HOME=$server_devops_cache/corepack
ANSIBLE_HOME=$server_devops_db/ansible
ANSIBLE_GALAXY_CACHE_DIR=$server_devops_cache/ansible/galaxy
PACKER_CACHE_DIR=$server_devops_cache/hashicorp/packer/cache
PACKER_CONFIG=$server_devops_cache/hashicorp/packer.d/config.json
PACKER_PLUGIN_PATH=$server_devops_cache/hashicorp/packer.d/plugins
TF_PLUGIN_CACHE_DIR=$server_devops_cache/hashicorp/terraform/plugin-cache
PIP_CACHE_DIR=$server_devops_cache/pip
UV_CACHE_DIR=$server_devops_cache/uv
MISE_DATA_DIR=$server_devops_db/mise/data
MISE_STATE_DIR=$server_devops_db/mise/state
MISE_TMP_DIR=$server_devops_cache/mise/tmp
MISE_CACHE_DIR=$server_devops_cache/mise
BAZELISK_HOME=$server_devops_db/bazelisk
USE_BAZEL_FALLBACK_VERSION='error:select a reviewed project Bazel version and digest'

# Direct rootless Podman and Buildah keep all container state below /pool/podman.
CONTAINERS_STORAGE_CONF=$server_devops_podman/config/storage.conf
CONTAINERS_CONF=$server_devops_podman/config/containers.conf
BUILDAH_ISOLATION=rootless
export TMPDIR CARGO_HOME CARGO_TARGET_DIR CARGO_INSTALL_ROOT RUSTUP_HOME SCCACHE_DIR
export GOCACHE GOPATH GOMODCACHE GOTMPDIR GOTOOLCHAIN PIP_CACHE_DIR UV_CACHE_DIR
export MISE_DATA_DIR MISE_STATE_DIR MISE_TMP_DIR MISE_CACHE_DIR BAZELISK_HOME USE_BAZEL_FALLBACK_VERSION
export GOBIN GOENV DENO_DIR DENO_INSTALL UV_TOOL_DIR UV_TOOL_BIN_DIR NPM_CONFIG_CACHE NPM_CONFIG_PREFIX
export COREPACK_HOME ANSIBLE_HOME ANSIBLE_GALAXY_CACHE_DIR PACKER_CACHE_DIR PACKER_CONFIG PACKER_PLUGIN_PATH TF_PLUGIN_CACHE_DIR
export CONTAINERS_STORAGE_CONF CONTAINERS_CONF BUILDAH_ISOLATION
for server_devops_bin in "$CARGO_INSTALL_ROOT/bin" "$CARGO_HOME/bin" "$GOPATH/bin" "$MISE_DATA_DIR/shims" "__INSTALLER_DEVOPS_BAZELISK_INSTALL_DIR__"; do
  case :$PATH: in *:"$server_devops_bin":*) ;; *) PATH=$PATH:$server_devops_bin ;; esac
done
export PATH
unset server_devops_bin server_devops_user server_devops_build server_devops_cache server_devops_db server_devops_podman server_devops_root
