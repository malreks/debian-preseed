#!/bin/sh
# samloader-rs installation for managed Samsung firmware actions.

desktop_samloader_fail() {
  installer_fatal "samloader-rs: $*"
}

desktop_samloader_validate_unsigned_integer() {
  value_name=$1
  value=$2

  case "$value" in
    ''|*[!0123456789]*)
      desktop_samloader_fail "${value_name} must be an unsigned integer"
      ;;
  esac
}

desktop_samloader_validate_sha256() {
  value_name=$1
  value=$2

  case "$value" in
    ''|*[!0123456789abcdef]*)
      desktop_samloader_fail "${value_name} must contain lowercase hexadecimal characters"
      ;;
  esac
  [ "${#value}" -eq 64 ] ||
    desktop_samloader_fail "${value_name} must contain 64 characters"
}

desktop_samloader_validate_policy() {
  : "${SAMLOADER_VERSION:?SAMLOADER_VERSION must be set}"
  : "${SAMLOADER_ARCHITECTURE:?SAMLOADER_ARCHITECTURE must be set}"
  : "${SAMLOADER_URL:?SAMLOADER_URL must be set}"
  : "${SAMLOADER_SHA256:?SAMLOADER_SHA256 must be set}"
  : "${SAMLOADER_MAXIMUM_EXTRACTED_BYTES:?SAMLOADER_MAXIMUM_EXTRACTED_BYTES must be set}"
  : "${SAMLOADER_MAXIMUM_MEMBERS:?SAMLOADER_MAXIMUM_MEMBERS must be set}"

  printf '%s\n' "$SAMLOADER_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' ||
    desktop_samloader_fail "version must be semantic"
  [ "$SAMLOADER_ARCHITECTURE" = amd64 ] ||
    desktop_samloader_fail "the managed Linux x86-64 release is unsupported for ${SAMLOADER_ARCHITECTURE}"
  case "$SAMLOADER_URL" in
    https://*/*) ;;
    *) desktop_samloader_fail "download URL must match the configured Linux x86-64 release" ;;
  esac
  desktop_samloader_validate_sha256 SAMLOADER_SHA256 "$SAMLOADER_SHA256"

  desktop_samloader_validate_unsigned_integer \
    SAMLOADER_MAXIMUM_EXTRACTED_BYTES \
    "$SAMLOADER_MAXIMUM_EXTRACTED_BYTES"
  desktop_samloader_validate_unsigned_integer \
    SAMLOADER_MAXIMUM_MEMBERS \
    "$SAMLOADER_MAXIMUM_MEMBERS"

  [ "$SAMLOADER_MAXIMUM_MEMBERS" -ge 1 ] ||
    desktop_samloader_fail "archive member ceiling is too small"
}

desktop_samloader_preflight_target_architecture() {
  desktop_samloader_validate_policy

  SAMLOADER_TARGET_ARCHITECTURE=$(
    capture_in_target \
      "detect target architecture for samloader-rs" \
      __INSTALLER_PATH_DIR_USR_BIN__/dpkg --print-architecture
  )
  [ -n "$SAMLOADER_TARGET_ARCHITECTURE" ] ||
    desktop_samloader_fail "target architecture detection returned no output"
  [ "$SAMLOADER_TARGET_ARCHITECTURE" = "$SAMLOADER_ARCHITECTURE" ] ||
    desktop_samloader_fail \
      "samloader-rs Linux x86-64 requires ${SAMLOADER_ARCHITECTURE}, but the target architecture is ${SAMLOADER_TARGET_ARCHITECTURE}"
}

desktop_install_samloader() {
  [ -n "${SAMLOADER_TARGET_ARCHITECTURE:-}" ] ||
    desktop_samloader_preflight_target_architecture

  samloader_work_dir="/tmp/samloader-install.$$"
  samloader_archive="${samloader_work_dir}/samloader.zip"
  samloader_extract_dir="${samloader_work_dir}/extract"
  samloader_archive_host="${TARGET_ROOT}${samloader_archive}"
  samloader_extract_host="${TARGET_ROOT}${samloader_extract_dir}"
  samloader_binary_host="${samloader_extract_host}/samloader"
  samloader_install_parent_host=${TARGET_ROOT}${DIR_USR_LOCAL_LIB}
  samloader_install_host="${samloader_install_parent_host}/samloader"
  samloader_staged_host="${samloader_install_parent_host}/.samloader.new.$$"

  rm -rf -- "${TARGET_ROOT}${samloader_work_dir}" "$samloader_staged_host"
  install -d -m 0700 "$samloader_extract_host"

  if ! attempt_in_target "download pinned samloader-rs release" \
    __INSTALLER_PATH_DIR_USR_BIN__/env -i \
      HOME=__INSTALLER_PATH_DIR_ROOT_HOME__ \
      LC_ALL=C \
      PATH=__INSTALLER_PATH_DIR_USR_LOCAL__/sbin:__INSTALLER_PATH_DIR_USR_LOCAL__/bin:__INSTALLER_PATH_DIR_USR_SBIN__:__INSTALLER_PATH_DIR_USR_BIN__:__INSTALLER_PATH_DIR_SBIN__:__INSTALLER_PATH_DIR_BIN__ \
      __INSTALLER_PATH_DIR_USR_BIN__/curl \
        --disable \
        --fail \
        --silent \
        --show-error \
        --location \
        --proto '=https' \
        --proto-redir '=https' \
        --connect-timeout 15 \
        --max-time 300 \
        --max-redirs 4 \
        --retry 3 \
        --retry-all-errors \
        --user-agent 'unattended-installer-samloader/1.0' \
        --header 'Accept: application/zip, application/octet-stream;q=0.9, */*;q=0.1' \
        --output "$samloader_archive" \
        --url "$SAMLOADER_URL"
  then
    desktop_samloader_fail "official release archive download failed"
  fi

  [ -f "$samloader_archive_host" ] && [ ! -L "$samloader_archive_host" ] ||
    desktop_samloader_fail "downloaded archive is not a regular file"
  samloader_archive_sha256=$(
    capture_in_target \
      "hash downloaded samloader-rs archive" \
      __INSTALLER_PATH_DIR_USR_BIN__/sha256sum "$samloader_archive"
  )
  samloader_archive_sha256=${samloader_archive_sha256%% *}
  [ "$samloader_archive_sha256" = "$SAMLOADER_SHA256" ] ||
    desktop_samloader_fail \
      "downloaded archive SHA-256 does not match the pinned release digest"

  # Upstream ships one flat ZIP member. Extract only that authenticated regular
  # file, with exclusive creation and a streaming ceiling; never trust ZIP paths
  # or restore archive ownership, links or permissions.
  if ! attempt_in_target "extract pinned samloader-rs release archive" \
    __INSTALLER_PATH_DIR_USR_BIN__/python3 -I -c '
import stat
import sys
import zipfile

archive_path, destination = sys.argv[1:3]
maximum_bytes, maximum_members = map(int, sys.argv[3:5])
try:
    with zipfile.ZipFile(archive_path) as archive:
        members = archive.infolist()
        if len(members) != 1 or len(members) > maximum_members:
            raise ValueError("expected exactly one archive member")
        member = members[0]
        kind = stat.S_IFMT(member.external_attr >> 16)
        if (member.filename != "samloader" or member.is_dir()
                or kind not in (0, stat.S_IFREG) or member.flag_bits & 1):
            raise ValueError("archive member must be an unencrypted regular samloader file")
        if not 0 < member.file_size <= maximum_bytes:
            raise ValueError("archive member exceeds the extracted size ceiling")
        written = 0
        with archive.open(member) as source, open(destination, "xb") as output:
            while True:
                chunk = source.read(min(65536, maximum_bytes - written + 1))
                if not chunk:
                    break
                written += len(chunk)
                if written > maximum_bytes or written > member.file_size:
                    raise ValueError("archive member expanded beyond its declared size")
                if output.write(chunk) != len(chunk):
                    raise OSError("incomplete archive member write")
        if written != member.file_size:
            raise ValueError("archive member size does not match its declaration")
except (OSError, ValueError, RuntimeError, zipfile.BadZipFile, NotImplementedError) as error:
    sys.exit(f"samloader archive refused: {error}")
' \
      "$samloader_archive" \
      "${samloader_extract_dir}/samloader" \
      "$SAMLOADER_MAXIMUM_EXTRACTED_BYTES" \
      "$SAMLOADER_MAXIMUM_MEMBERS"
  then
    desktop_samloader_fail "failed to extract the downloaded release archive"
  fi

  unsupported_samloader_node=$(
    find "$samloader_extract_host" \
      -mindepth 1 \
      ! -type f \
      ! -type d \
      -print |
      sed -n '1p'
  )
  [ -z "$unsupported_samloader_node" ] ||
    desktop_samloader_fail \
      "downloaded archive extracted an unsupported node: ${unsupported_samloader_node}"
  [ -f "$samloader_binary_host" ] && [ ! -L "$samloader_binary_host" ] ||
    desktop_samloader_fail "extracted samloader binary is invalid"

  samloader_extracted_kib=$(
    desktop_target_tree_size_kib \
      "measure extracted samloader-rs release size" \
      "$samloader_extract_dir"
  )
  desktop_samloader_validate_unsigned_integer \
    "extracted archive size" \
    "$samloader_extracted_kib"
  samloader_extracted_bytes=$((samloader_extracted_kib * 1024))
  [ "$samloader_extracted_bytes" -le "$SAMLOADER_MAXIMUM_EXTRACTED_BYTES" ] ||
    desktop_samloader_fail \
      "downloaded archive expands beyond the managed size ceiling: ${samloader_extracted_bytes} bytes"

  samloader_file_type=$(
    capture_in_target \
      "inspect extracted samloader-rs binary" \
      __INSTALLER_PATH_DIR_USR_BIN__/file -b "${samloader_extract_dir}/samloader"
  )
  case "$samloader_file_type" in
    *"ELF 64-bit"*"x86-64"*) ;;
    *)
      desktop_samloader_fail \
        "extracted samloader has an unexpected file type: ${samloader_file_type:-unset}"
      ;;
  esac

  install -d -m 0755 "$samloader_install_parent_host" ${TARGET_ROOT}${DIR_USR_LOCAL_BIN}
  install -d -m 0755 "$samloader_staged_host"
  install -m 0755 "$samloader_binary_host" "${samloader_staged_host}/samloader"
  cat >"${samloader_staged_host}/.release" <<EOF
version=${SAMLOADER_VERSION}
url=${SAMLOADER_URL}
archive_sha256=${SAMLOADER_SHA256}
architecture=${SAMLOADER_TARGET_ARCHITECTURE}
EOF
  chmod 0644 "${samloader_staged_host}/.release"
  chown -R root:root "$samloader_staged_host"

  [ ! -L "$samloader_install_host" ] ||
    desktop_samloader_fail "managed installation path must not be a symlink"
  rm -rf -- "$samloader_install_host"
  mv "$samloader_staged_host" "$samloader_install_host"
  ln -sfn ..__INSTALLER_PATH_DIR_LIB__/samloader/samloader ${TARGET_ROOT}${DIR_USR_LOCAL_BIN}/samloader

  rm -rf -- "${TARGET_ROOT}${samloader_work_dir}"
  desktop_log \
    "installed_samloader version=${SAMLOADER_VERSION} architecture=${SAMLOADER_TARGET_ARCHITECTURE} archive_sha256=${SAMLOADER_SHA256}"
}
