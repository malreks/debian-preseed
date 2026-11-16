#!/bin/sh
# shellcheck disable=SC2154
# Sourced installer module; edit this file directly.

devops_run_as_account() {
  devops_execute_as_account '' "$@"
}

devops_run_as_account_from_payload() (
  set -eu
  payload_input=$1
  shift
  [ -f "$payload_input" ] && [ ! -L "$payload_input" ] ||
    devops_fatal "rendered account payload input is missing or indirect"
  input_parent="${target_root}${DIR_VAR_LIB_INSTALLER_STATE}"
  installer_apt_safe_path "$input_parent" ||
    devops_fatal "unsafe private account payload staging ancestry"
  [ -d "$input_parent" ] || install -d -m 0700 -- "$input_parent"
  input_stage=$(umask 077; mktemp -d "$input_parent/.devops-account.XXXXXX") ||
    devops_fatal "cannot create private account payload staging"
  cleanup_account_input() {
    input_status=$?
    trap - 0
    if ! rm -f -- "$input_stage/input" || ! rmdir -- "$input_stage"; then
      installer_error "private account payload cleanup failed: $input_stage"
      [ "$input_status" -ne 0 ] || input_status=1
    fi
    exit "$input_status"
  }
  trap cleanup_account_input 0
  trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
  install -m 0600 -- "$payload_input" "$input_stage/input"
  chown root:root "$input_stage" "$input_stage/input"
  devops_execute_as_account "${input_stage#"$target_root"}/input" "$@"
)

devops_execute_as_account() (
  account_input=$1
  run_label=$2
  shift 2
  devops_validate_account_name "$ACCOUNT_USERNAME"
  case "${account_ids%%:*}" in
    ''|0|*[!0-9]*) devops_fatal "tool execution requires a non-root target UID" ;;
  esac
  case "$ACCOUNT_HOME" in
    __INSTALLER_PATH_DIR_ROOT_HOME__|__INSTALLER_PATH_DIR_ROOT_HOME__/*) devops_fatal "tool execution must not use root's home" ;;
  esac

  set -- __INSTALLER_PATH_DIR_USR_SBIN__/runuser \
      -u "$ACCOUNT_USERNAME" \
      -- \
      __INSTALLER_PATH_DIR_USR_BIN__/env -i \
        HOME="$ACCOUNT_HOME" \
        USER="$ACCOUNT_USERNAME" \
        LOGNAME="$ACCOUNT_USERNAME" \
        PATH="${DEVOPS_RUSTUP_INSTALL_ROOT}__INSTALLER_PATH_DIR_BIN__:${CARGO_INSTALL_ROOT}__INSTALLER_PATH_DIR_BIN__:${CARGO_HOME}__INSTALLER_PATH_DIR_BIN__:__INSTALLER_PATH_DIR_USR_LOCAL__/sbin:__INSTALLER_PATH_DIR_USR_LOCAL__/bin:__INSTALLER_PATH_DIR_USR__/sbin:__INSTALLER_PATH_DIR_USR__/bin:__INSTALLER_PATH_DIR_SBIN__:__INSTALLER_PATH_DIR_BIN__" \
        XDG_CONFIG_HOME="${ACCOUNT_HOME}/.config" \
        XDG_CACHE_HOME="${ACCOUNT_HOME}/.cache" \
        XDG_DATA_HOME="${ACCOUNT_HOME}/.local/share" \
        XDG_STATE_HOME="${ACCOUNT_HOME}/.local/state" \
        CODEX_HOME="$DEVOPS_CODEX_HOME" \
        CARGO_HOME="$CARGO_HOME" \
        CARGO_TARGET_DIR="$CARGO_TARGET_DIR" \
        CARGO_INSTALL_ROOT="$CARGO_INSTALL_ROOT" \
        RUSTUP_HOME="$RUSTUP_HOME" \
        RUSTUP_TOOLCHAIN="$DEVOPS_RUSTUP_TOOLCHAIN" \
        SCCACHE_DIR="$SCCACHE_DIR" \
        GOPATH="$GOPATH" \
        GOBIN="${GOPATH}__INSTALLER_PATH_DIR_BIN__" \
        GOMODCACHE="$GOMODCACHE" \
        GOCACHE="$GOCACHE" \
        GOENV="$GOENV" \
        GOTMPDIR="$GOTMPDIR" \
        GOTOOLCHAIN=local \
        MISE_CONFIG_DIR="${ACCOUNT_HOME}/.config/mise" \
        MISE_DATA_DIR="$MISE_DATA_DIR" \
        MISE_STATE_DIR="$MISE_STATE_DIR" \
        MISE_CACHE_DIR="$MISE_CACHE_DIR" \
        MISE_TMP_DIR="$MISE_TMP_DIR" \
        BAZELISK_HOME="$BAZELISK_HOME" \
        ANSIBLE_HOME="$ANSIBLE_HOME" \
        ANSIBLE_GALAXY_CACHE_DIR="$ANSIBLE_GALAXY_CACHE_DIR" \
        CHECKPOINT_DISABLE=1 \
        PACKER_CACHE_DIR="$PACKER_CACHE_DIR" \
        PACKER_CONFIG="$PACKER_CONFIG_PATH" \
        PACKER_CONFIG_DIR="$PACKER_CONFIG_DIR" \
        PACKER_CONFIG_PATH="$PACKER_CONFIG_PATH" \
        PACKER_PLUGIN_PATH="$PACKER_PLUGIN_PATH" \
        DEVOPS_PACKER_RELEASE_ORIGIN="$DEVOPS_PACKER_RELEASE_ORIGIN" \
        DEVOPS_PACKER_PROXMOX_RELEASE_ORIGIN="$DEVOPS_PACKER_PROXMOX_RELEASE_ORIGIN" \
        DEVOPS_PACKER_SIGNING_KEY_URL="$DEVOPS_PACKER_SIGNING_KEY_URL" \
        DEVOPS_PACKER_SIGNING_KEY_FINGERPRINT="$DEVOPS_PACKER_SIGNING_KEY_FINGERPRINT" \
        DEVOPS_PACKER_PROXMOX_VERSION="$DEVOPS_PACKER_PROXMOX_VERSION" \
        DEVOPS_PACKER_PROXMOX_AMD64_SHA256="$DEVOPS_PACKER_PROXMOX_AMD64_SHA256" \
        DEVOPS_PACKER_PROXMOX_ARM64_SHA256="$DEVOPS_PACKER_PROXMOX_ARM64_SHA256" \
        DEVOPS_PACKER_ARCHIVE_MAXIMUM_EXTRACTED_BYTES="$DEVOPS_PACKER_ARCHIVE_MAXIMUM_EXTRACTED_BYTES" \
        DEVOPS_PACKER_ARCHIVE_MAXIMUM_MEMBERS="$DEVOPS_PACKER_ARCHIVE_MAXIMUM_MEMBERS" \
        DEVOPS_PACKER_TEMPLATE_MAXIMUM_BYTES="$DEVOPS_PACKER_TEMPLATE_MAXIMUM_BYTES" \
        TF_PLUGIN_CACHE_DIR="$TF_PLUGIN_CACHE_DIR" \
        "$@"

  if [ -n "$account_input" ]; then
    case "$account_input" in
      "${DIR_VAR_LIB_INSTALLER_STATE}/".devops-account.*/input) ;;
      *) devops_fatal "account configuration input must belong to private payload staging" ;;
    esac
    # run_in_target deliberately starts with /dev/null on stdin. Open this
    # root-owned rendered payload INSIDE the target before dropping privileges.
    # The account inherits only its read descriptor. It cannot traverse private
    # installer state or either skeleton. Keep the normal env -i account API.
    # shellcheck disable=SC2016
    set -- "${DIR_USR_BIN}/python3" -I -c '
import os, pathlib, stat, sys
root, source = map(pathlib.Path, sys.argv[1:3])
if (os.geteuid() != 0 or not root.is_absolute() or not source.is_relative_to(root)
        or root.resolve(strict=True) != root or source.resolve(strict=True) != source):
    raise SystemExit("unsafe rendered account payload source")
for directory in (source.parent, *source.parent.parents):
    info = directory.stat()
    if info.st_uid or info.st_gid or info.st_mode & 0o022:
        raise SystemExit("account payload ancestor is not root controlled")
fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
try:
    info = os.fstat(fd)
    if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1
            or info.st_uid or info.st_gid or info.st_mode & 0o022):
        raise SystemExit("unsafe rendered account payload file")
    os.dup2(fd, 0, inheritable=True)
finally:
    if fd != 0:
        os.close(fd)
os.execv(sys.argv[3], sys.argv[3:])
' "${account_input%/*}" "$account_input" "$@"
  fi
  run_in_target "$run_label" "$@"
)

devops_publish_account_config() (
  config_source=$1
  config_label=$2
  config_relative=$3
  config_mode=$4
  shift 4
  # Publish directly from the authenticated, rendered payload input. The
  # primary account never reads the separately published skeleton copy. Use
  # account-owned directory FDs and atomic no-replace publication.
  # Extra arguments name empty account directories, e.g. yt-dlp/plugins.
  # shellcheck disable=SC2016
  devops_run_as_account_from_payload "$config_source" "$config_label" \
    "${DIR_USR_BIN}/python3" -I -c '
import os, pathlib, secrets, stat, sys

def parts(relative):
    names = relative.split("/")
    if any(not name or name in (".", "..") or "\x00" in name for name in names):
        raise SystemExit("unsafe account configuration path")
    return names

mode = int(sys.argv[2], 8)
if mode not in (0o600, 0o644):
    raise SystemExit("unsafe account configuration mode")
source = os.fstat(0)
if (not stat.S_ISREG(source.st_mode) or source.st_uid or source.st_gid
        or source.st_nlink != 1 or source.st_mode & 0o022):
    raise SystemExit("account configuration input is not a root-owned snapshot")
data = sys.stdin.buffer.read(16385)
if not data or len(data) > 16384 or len(data) != source.st_size:
    raise SystemExit("invalid account configuration snapshot")
home_path = pathlib.Path(os.environ["HOME"])
if not home_path.is_absolute() or home_path.resolve(strict=True) != home_path:
    raise SystemExit("unsafe account configuration home")
home = os.open(home_path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)

def owned_directory(fd):
    info = os.fstat(fd)
    if info.st_uid != os.getuid() or info.st_gid != os.getgid() or info.st_mode & 0o022:
        raise SystemExit("account configuration directory is not privately owned")

def directory(names):
    parent = os.dup(home)
    try:
        for name in names:
            try:
                os.mkdir(name, 0o700, dir_fd=parent)
                os.fsync(parent)
            except FileExistsError:
                pass
            child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                            dir_fd=parent)
            os.close(parent)
            parent = child
            owned_directory(parent)
        return parent
    except BaseException:
        os.close(parent)
        raise

try:
    owned_directory(home)
    for extra in sys.argv[3:]:
        os.close(directory(parts(extra)))
    names = parts(sys.argv[1])
    parent = directory(names[:-1])
    try:
        candidate = ".installer-config-" + secrets.token_hex(16)
        fd = os.open(candidate, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                     0o600, dir_fd=parent)
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(data)
                stream.flush()
                os.fchmod(stream.fileno(), mode)
                os.fsync(stream.fileno())
            try:
                os.link(candidate, names[-1], src_dir_fd=parent, dst_dir_fd=parent,
                        follow_symlinks=False)
            except FileExistsError:
                fd = os.open(names[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
                             dir_fd=parent)
                try:
                    info = os.fstat(fd)
                    if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1
                            or info.st_uid != os.getuid() or info.st_gid != os.getgid()
                            or stat.S_IMODE(info.st_mode) != mode
                            or info.st_size != len(data) or os.read(fd, len(data) + 1) != data):
                        raise SystemExit("existing account configuration differs; preserve it for review")
                finally:
                    os.close(fd)
        finally:
            os.unlink(candidate, dir_fd=parent)
            os.fsync(parent)
    finally:
        os.close(parent)
finally:
    os.close(home)
' "$config_relative" "$config_mode" "$@"
)
