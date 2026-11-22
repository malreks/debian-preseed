#!/bin/sh
# Sourced installer module; edit this file directly.

devops_install_pinned_bazelisk() {
  # The payload runs inside the target during the installer late command. It is
  # deliberately not staged as a persistent target-side installer helper.
  # shellcheck disable=SC2016
  run_in_target "download and install pinned Bazelisk" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
umask 022

bazelisk_fatal() {
  printf "fatal: %s\n" "$*" >&2
  exit 1
}

[ "$#" -eq 5 ] || bazelisk_fatal "Bazelisk argument contract requires 5 values (received $#)"

bazelisk_validate_positive_integer() {
  label=$1
  value=$2

  case "$value" in
    ""|*[!0123456789]*) bazelisk_fatal "${label} must be a positive integer" ;;
  esac
  [ "$value" -gt 0 ] || bazelisk_fatal "${label} must be greater than zero"
}

bazelisk_require_command() {
  command -v "$1" >__INSTALLER_PATH_DIR_DEV__/null 2>&1 ||
    bazelisk_fatal "required command is unavailable: $1"
}

bazelisk_version=$1
bazelisk_url=$2
expected_sha256=$3
install_dir=$4
binary_path=$5
bazelisk_archive_filename=${bazelisk_url##*/}
install_parent=${install_dir%/*}

case "$bazelisk_url" in
  https://*/*)
    ;;
  *)
    bazelisk_fatal "release URL must be an HTTPS URL with a release filename"
    ;;
esac
[ -n "$bazelisk_archive_filename" ] ||
  bazelisk_fatal "release URL has no release filename"
case "$bazelisk_archive_filename" in
  */*) bazelisk_fatal "release URL filename must not contain a slash" ;;
esac
case "$expected_sha256" in
  *[!0123456789abcdef]*|"") bazelisk_fatal "expected SHA-256 is malformed" ;;
esac
[ "${#expected_sha256}" -eq 64 ] ||
  bazelisk_fatal "expected SHA-256 must have 64 hexadecimal characters"
case "$install_dir" in
  /*|/*/*) ;;
  *) bazelisk_fatal "Bazelisk install directory must be absolute: $install_dir" ;;
esac
case "$binary_path" in
  "$install_dir"/*) ;;
  *) bazelisk_fatal "Bazelisk binary path must be below its install directory: $binary_path" ;;
esac

for required_command in awk chmod chown curl install mktemp rm sha256sum tr wc; do
  bazelisk_require_command "$required_command"
done
unset required_command

[ -d "$install_parent" ] || install -d -m 0755 "$install_parent"
[ ! -L "$install_parent" ] ||
  bazelisk_fatal "${install_parent} must not be a symlink"
[ ! -e "$install_dir" ] && [ ! -L "$install_dir" ] ||
  bazelisk_fatal "Bazelisk install path already exists; this fresh-install helper will not replace it: $install_dir"

staging_dir=$(mktemp -d "${install_parent}/.devops-bazelisk.XXXXXXXX") ||
  bazelisk_fatal "unable to allocate Bazelisk staging directory"
cleanup() {
  rm -rf -- "$staging_dir"
}
trap cleanup EXIT HUP INT TERM

payload_path="${staging_dir}/${bazelisk_archive_filename}"
curl \
  --fail \
  --silent \
  --show-error \
  --location \
  --proto "=https" \
  --tlsv1.2 \
  --retry 3 \
  --retry-delay 2 \
  --connect-timeout 15 \
  --max-time 300 \
  --output "$payload_path" \
  "$bazelisk_url" ||
  bazelisk_fatal "failed to download pinned Bazelisk release: $bazelisk_url"

actual_sha256=$(sha256sum "$payload_path" | awk "{print \$1}")
[ "$actual_sha256" = "$expected_sha256" ] ||
  bazelisk_fatal "Bazelisk SHA-256 mismatch for ${bazelisk_url}"

install -d -m 0755 "$install_dir"
install -m 0755 "$payload_path" "$binary_path"
chown root:root "$install_dir" "$binary_path"
{
  printf "version=%s\n" "$bazelisk_version"
  printf "url=%s\n" "$bazelisk_url"
  printf "sha256=%s\n" "$expected_sha256"
  printf "architecture=linux-amd64\n"
} >"${install_dir}/.bazelisk-release"
chmod 0644 "${install_dir}/.bazelisk-release"
chown root:root "${install_dir}/.bazelisk-release"

printf "installed Bazelisk %s at %s\n" "$bazelisk_version" "$binary_path"
' sh \
    "$DEVOPS_BAZELISK_VERSION" \
    "$DEVOPS_BAZELISK_URL" \
    "$DEVOPS_BAZELISK_SHA256" \
    "$DEVOPS_BAZELISK_INSTALL_DIR" \
    "$DEVOPS_BAZELISK_BINARY_PATH"
}

devops_install_pinned_node_runtimes() {
  # The payload runs inside the target during the installer late command. It is
  # deliberately not staged as a persistent target-side helper.
  # shellcheck disable=SC2016
  run_in_target "download and install pinned Node runtimes for Mise" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
umask 022

node_fatal() {
  printf "fatal: %s\n" "$*" >&2
  exit 1
}

[ "$#" -eq 27 ] || node_fatal "Node runtime argument contract requires 27 values (received $#)"

node_require_command() {
  command -v "$1" >__INSTALLER_PATH_DIR_DEV__/null 2>&1 ||
    node_fatal "required command is unavailable: $1"
}

node_validate_positive_integer() {
  label=$1
  value=$2

  case "$value" in
    ""|*[!0123456789]*) node_fatal "${label} must be a positive integer" ;;
  esac
  [ "$value" -gt 0 ] || node_fatal "${label} must be greater than zero"
}

node_validate_archive() {
  archive=$1
  archive_root=$2
  archive_listing=$3

  tar -tJf "$archive" >"$archive_listing" ||
    node_fatal "unable to list Node archive: $archive"
  while IFS= read -r archive_entry || [ -n "$archive_entry" ]; do
    [ -n "$archive_entry" ] ||
      node_fatal "Node archive contains an empty path: $archive"
    case "$archive_entry" in
      "$archive_root"/*) ;;
      *) node_fatal "Node archive contains an unexpected path: $archive" ;;
    esac
    case "$archive_entry" in
      /*|../*|*/../*|*/..|..)
        node_fatal "Node archive contains an unsafe path: $archive"
        ;;
      esac
  done <"$archive_listing"
  archive_member_count=$(wc -l <"$archive_listing" | tr -d "[[:space:]]")
  node_validate_positive_integer "Node archive member count" "$archive_member_count"
  [ "$archive_member_count" -le "$max_archive_members" ] ||
    node_fatal "Node archive exceeds the configured member ceiling (${archive_member_count} > ${max_archive_members}): $archive"

  archive_expanded_bytes=$(xz --robot --list "$archive" |
    awk -F "\t" "\$1 == \"totals\" { print \$5; exit }")
  node_validate_positive_integer "Node archive expanded bytes" "$archive_expanded_bytes"
  [ "$archive_expanded_bytes" -le "$max_extracted_bytes" ] ||
    node_fatal "Node archive exceeds the configured expanded-byte ceiling: $archive"
}

node_install() {
  major_version=$1
  release_version=$2
  archive_url=$3
  expected_sha256=$4
  archive_name=$5
  archive_root=$6
  install_dir=$7
  binary_path=$8

  case "$major_version" in
    22|24|26) ;;
    *) node_fatal "unsupported managed Node major version: $major_version" ;;
  esac
  printf "%s\n" "$release_version" |
    grep -Eq "^v${major_version}\.[0-9]+\.[0-9]+$" ||
    node_fatal "Node release version does not match its managed major: $release_version"
  [ "$archive_name" = "node-${release_version}-linux-x64.tar.xz" ] ||
    node_fatal "Node archive filename does not match its managed release"
  [ "$archive_root" = "node-${release_version}-linux-x64" ] ||
    node_fatal "Node archive root does not match its managed release"
  case "$archive_url" in https://*/"$archive_name") ;; *) node_fatal "Node release URL does not match its configured archive" ;; esac
  case "$install_dir" in
    /*|/*/*) ;;
    *) node_fatal "Node install root must be absolute" ;;
  esac
  case "$binary_path" in
    "$install_dir"/*) ;;
    *) node_fatal "Node binary path must be below its managed install root" ;;
  esac
  [ "${#expected_sha256}" -eq 64 ] ||
    node_fatal "Node SHA-256 must contain 64 lowercase hexadecimal characters"
  case "$expected_sha256" in
    *[!0123456789abcdef]*)
      node_fatal "Node SHA-256 must contain 64 lowercase hexadecimal characters"
      ;;
  esac
  [ ! -e "$install_dir" ] ||
    node_fatal "Node install path already exists; this fresh-install helper will not replace it: $install_dir"

  node_install_parent=${install_dir%/*}
  [ -d "$node_install_parent" ] || install -d -m 0755 "$node_install_parent"
  [ ! -L "$node_install_parent" ] ||
    node_fatal "Node install parent must not be a symlink: $node_install_parent"

  staging_dir=$(mktemp -d "${node_install_parent}/.devops-node.XXXXXXXX") ||
    node_fatal "unable to allocate Node staging directory"
  trap "rm -rf -- \"\$staging_dir\"" EXIT HUP INT TERM

  archive_path="${staging_dir}/${archive_name}"
  archive_listing="${staging_dir}/archive.list"
  curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --proto "=https" \
    --tlsv1.2 \
    --retry 3 \
    --retry-delay 2 \
    --connect-timeout 15 \
    --max-time "$download_timeout" \
    --output "$archive_path" \
    "$archive_url" ||
    node_fatal "failed to download pinned Node archive: $archive_url"

  actual_sha256=$(sha256sum "$archive_path" | awk "{print \$1}")
  [ "$actual_sha256" = "$expected_sha256" ] ||
    node_fatal "Node archive SHA-256 mismatch for ${archive_name}"

  node_validate_archive "$archive_path" "$archive_root" "$archive_listing"
  tar -xJf "$archive_path" \
    --no-same-owner \
    --no-same-permissions \
    -C "$staging_dir" ||
    node_fatal "failed to extract Node archive: $archive_name"

  extracted_dir="${staging_dir}/${archive_root}"
  [ -d "$extracted_dir" ] ||
    node_fatal "Node archive root is missing after extraction: $archive_root"
  [ -x "${extracted_dir}__INSTALLER_PATH_DIR_BIN__/node" ] ||
    node_fatal "Node executable is missing after extraction: $archive_root"
  [ -x "${extracted_dir}__INSTALLER_PATH_DIR_BIN__/npm" ] ||
    node_fatal "npm executable is missing after extraction: $archive_root"
  [ -x "${extracted_dir}__INSTALLER_PATH_DIR_BIN__/npx" ] ||
    node_fatal "npx executable is missing after extraction: $archive_root"

  chown -R root:root "$extracted_dir"
  find "$extracted_dir" -xdev -type d -exec chmod 0755 {} +
  find "$extracted_dir" -xdev -type f -exec chmod a-s,go-w {} +
  printf "%s\n" \
    "version=${release_version}" \
    "url=${archive_url}" \
    "sha256=${expected_sha256}" \
    "architecture=linux-x64" \
    >"${extracted_dir}/.node-release"
  chmod 0644 "${extracted_dir}/.node-release"

  mv "$extracted_dir" "$install_dir"
  rm -f -- "$archive_path" "$archive_listing"
  rmdir -- "$staging_dir" 2>__INSTALLER_PATH_DIR_DEV__/null || true
  trap - EXIT HUP INT TERM
  printf "installed Node %s at %s\n" "$release_version" "$install_dir"
}

node_enable_corepack() {
  node_major_version=$1
  node_root=$2
  compatibility_root=${3:-}
  node_bin_dir="${node_root}__INSTALLER_PATH_DIR_BIN__"
  corepack_binary="${node_bin_dir}/corepack"

  [ -x "${node_bin_dir}/node" ] ||
    node_fatal "Node runtime is missing before Corepack configuration: ${node_bin_dir}/node"
  if [ ! -x "$corepack_binary" ]; then
    [ "$node_major_version" = 26 ] ||
      node_fatal "bundled Corepack is missing from Node ${node_major_version}"
    [ -n "$compatibility_root" ] ||
      node_fatal "Node 26 requires a managed Corepack compatibility root"
    corepack_binary="${compatibility_root}__INSTALLER_PATH_DIR_BIN__/corepack"
    [ -x "$corepack_binary" ] ||
      node_fatal "Node 24 bundled Corepack is unavailable for Node 26 compatibility"
    [ ! -e "${node_bin_dir}/corepack" ] &&
      [ ! -L "${node_bin_dir}/corepack" ] ||
      node_fatal "Node 26 Corepack compatibility path already exists"
    relative_compatibility_root=${compatibility_root#__INSTALLER_PATH_DIR_USR_LOCAL__/lib/}
    ln -s "../../${relative_compatibility_root}__INSTALLER_PATH_DIR_BIN__/corepack" "${node_bin_dir}/corepack" ||
      node_fatal "failed to install the Node 26 Corepack compatibility link"
  fi

  PATH="${node_bin_dir}:${PATH:-__INSTALLER_PATH_DIR_USR_LOCAL__/sbin:__INSTALLER_PATH_DIR_USR_LOCAL__/bin:__INSTALLER_PATH_DIR_USR__/sbin:__INSTALLER_PATH_DIR_USR__/bin:__INSTALLER_PATH_DIR_SBIN__:__INSTALLER_PATH_DIR_BIN__}" \
    "$corepack_binary" enable --install-directory "$node_bin_dir" ||
    node_fatal "failed to enable Corepack package-manager shims for Node ${node_major_version}"
  for corepack_command in pnpm yarn; do
    [ -x "${node_bin_dir}/${corepack_command}" ] ||
      node_fatal "Corepack did not install ${corepack_command} for Node ${node_major_version}"
  done
  unset corepack_command
}

for required_command in awk chown curl find install ln mktemp mv rmdir sha256sum tar tr wc xz; do
  node_require_command "$required_command"
done
unset required_command

# Three runtimes have eight fields each; their shared policy follows at 25–27.
download_timeout=${25}
max_archive_members=${26}
max_extracted_bytes=${27}
node_validate_positive_integer "Node download timeout" "$download_timeout"
node_validate_positive_integer "Node archive member ceiling" "$max_archive_members"
node_validate_positive_integer "Node expanded-byte ceiling" "$max_extracted_bytes"

node_install "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8"
node_install "$9" "${10}" "${11}" "${12}" "${13}" "${14}" "${15}" "${16}"
node_install "${17}" "${18}" "${19}" "${20}" "${21}" "${22}" "${23}" "${24}"
node_enable_corepack "$1" "$7"
node_enable_corepack "$9" "${15}"
# Corepack stopped shipping with Node 25.  Node 26 receives package-manager
# shims from the verified Node 24 Corepack payload while retaining Node 26 as
# the runtime selected by Mise.
node_enable_corepack "${17}" "${23}" "${15}"
' sh \
    "$DEVOPS_NODE_22_MAJOR" \
    "$DEVOPS_NODE_22_VERSION" \
    "$DEVOPS_NODE_22_URL" \
    "$DEVOPS_NODE_22_SHA256" \
    "$DEVOPS_NODE_22_ARCHIVE_FILENAME" \
    "$DEVOPS_NODE_22_ARCHIVE_ROOT" \
    "$DEVOPS_NODE_22_INSTALL_ROOT" \
    "$DEVOPS_NODE_22_BINARY_PATH" \
    "$DEVOPS_NODE_24_MAJOR" \
    "$DEVOPS_NODE_24_VERSION" \
    "$DEVOPS_NODE_24_URL" \
    "$DEVOPS_NODE_24_SHA256" \
    "$DEVOPS_NODE_24_ARCHIVE_FILENAME" \
    "$DEVOPS_NODE_24_ARCHIVE_ROOT" \
    "$DEVOPS_NODE_24_INSTALL_ROOT" \
    "$DEVOPS_NODE_24_BINARY_PATH" \
    "$DEVOPS_NODE_26_MAJOR" \
    "$DEVOPS_NODE_26_VERSION" \
    "$DEVOPS_NODE_26_URL" \
    "$DEVOPS_NODE_26_SHA256" \
    "$DEVOPS_NODE_26_ARCHIVE_FILENAME" \
    "$DEVOPS_NODE_26_ARCHIVE_ROOT" \
    "$DEVOPS_NODE_26_INSTALL_ROOT" \
    "$DEVOPS_NODE_26_BINARY_PATH" \
    "$DEVOPS_UPSTREAM_DOWNLOAD_TIMEOUT_SECONDS" \
    "$DEVOPS_UPSTREAM_MAX_ARCHIVE_MEMBERS" \
    "$DEVOPS_UPSTREAM_MAX_EXTRACTED_BYTES"
}
