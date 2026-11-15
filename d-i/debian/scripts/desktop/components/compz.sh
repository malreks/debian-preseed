#!/bin/sh
# Authenticated desktop archive tooling and its pinned prebuilt FLZMA2 codec.

desktop_stage_compz() (
  set -eu
  for directory in \
    "${DIR_USR_LOCAL_LIB}" \
    "${DIR_PYTHON3_LOCAL}" \
    "${DIR_PYTHON3_SITE_PACKAGES}" \
    "${DIR_PYTHON3_SITE_PACKAGES}/labwc_compz" \
    "${DIR_USR_LOCAL_LIBEXEC}"
  do
    ensure_target_asset_parent "${directory}/.installer-directory"
    directory_host=$(target_asset_host_path "$directory")
    [ -d "$directory_host" ] && [ ! -L "$directory_host" ] ||
      installer_fatal "unsafe compz module directory: ${directory}"
    chown root:root "$directory_host"
    chmod 0755 "$directory_host"
  done
  desktop_stage_role_asset FILE_TARGET_BIN_COMPZ __INSTALLER_PATH_DIR_USR_LOCAL__/bin/compz 0755
  for helper in compz-worker compz-sandbox compz-pipeline; do
    desktop_stage_role_asset "usr/local/libexec/${helper}" "${DIR_USR_LOCAL_LIBEXEC}/${helper}" 0755
  done
  for module in __init__ cli formats isolation safeio volumes worker; do
    module_path="usr/local/lib/python3/dist-packages/labwc_compz/${module}.py"
    desktop_stage_role_asset "$module_path" "${DIR_PYTHON3_SITE_PACKAGES}/labwc_compz/${module}.py" 0644
  done
  desktop_stage_role_asset \
    FILE_TARGET_PERL_LABWC_COMPZ_COMPZARCHIVES_PIPELINE \
    "${DIR_PERL5_SITE_PERL}/labwc-compz/CompzArchives/Pipeline.pm" 0644
  helper="${DIR_USR_LOCAL_LIBEXEC}/installer-compz-codecs"
  helper_host=$(target_asset_host_path "$helper")
  trap 'rm -f -- "$helper_host"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  stage_target_asset \
    "$(installer_repo_file_value FILE_DESKTOP_COMPZ_CODECS_INSTALL)" \
    "$helper" 0700
  run_in_target "install pinned compz FLZMA2 codec" \
    __INSTALLER_PATH_DIR_USR_BIN__/env -i HOME=__INSTALLER_PATH_DIR_ROOT_HOME__ LC_ALL=C PATH=__INSTALLER_PATH_DIR_USR_SBIN__:__INSTALLER_PATH_DIR_USR_BIN__:__INSTALLER_PATH_DIR_SBIN__:__INSTALLER_PATH_DIR_BIN__ \
    LABWC_7ZIP_ZSTD_TAG="$LABWC_7ZIP_ZSTD_TAG" \
    LABWC_7ZIP_ZSTD_AMD64_URL="$LABWC_7ZIP_ZSTD_AMD64_URL" \
    LABWC_7ZIP_ZSTD_AMD64_SHA256="$LABWC_7ZIP_ZSTD_AMD64_SHA256" \
    LABWC_7ZIP_ZSTD_ARM64_URL="$LABWC_7ZIP_ZSTD_ARM64_URL" \
    LABWC_7ZIP_ZSTD_ARM64_SHA256="$LABWC_7ZIP_ZSTD_ARM64_SHA256" \
    LABWC_7ZIP_ZSTD_MAXIMUM_EXTRACTED_BYTES="$LABWC_7ZIP_ZSTD_MAXIMUM_EXTRACTED_BYTES" \
    LABWC_7ZIP_ZSTD_MAXIMUM_MEMBERS="$LABWC_7ZIP_ZSTD_MAXIMUM_MEMBERS" \
    __INSTALLER_PATH_DIR_USR_BIN__/timeout --signal=TERM --kill-after=10s 600s \
    __INSTALLER_PATH_DIR_USR_BIN__/python3 -I -B "$helper"
  desktop_log "staged_compz isolated_archive_tools=yes flzma2=pinned_prebuilt"
)
