#!/bin/sh
# Profile-pinned font data. Only the repository helper runs as root; archive
# contents are never executed. User publication/cache explicitly drops uid.
desktop_install_fonts() (
  set -eu
  : "${ACCOUNT_USERNAME:?ACCOUNT_USERNAME must be set}"
  : "${ACCOUNT_HOME:?ACCOUNT_HOME must be set}"
  : "${LABWC_FONT_FIRACODE_URL:?font URL must be set}"
  : "${LABWC_FONT_FIRACODE_SHA256:?font SHA-256 must be set}"
  : "${LABWC_FONT_SYMBOLS_URL:?font URL must be set}"
  : "${LABWC_FONT_SYMBOLS_SHA256:?font SHA-256 must be set}"
  : "${LABWC_FONT_PROFONT_URL:?font URL must be set}"
  : "${LABWC_FONT_PROFONT_SHA256:?font SHA-256 must be set}"
  : "${LABWC_FONT_APTOS_URL:?font URL must be set}"
  : "${LABWC_FONT_APTOS_SHA256:?font SHA-256 must be set}"
  : "${LABWC_FONT_MICROSOFT_URL:?font URL must be set}"
  : "${LABWC_FONT_MICROSOFT_SHA256:?font SHA-256 must be set}"
  helper="${DIR_USR_LOCAL_LIBEXEC}/installer-desktop-fonts"
  helper_host=$(target_asset_host_path "$helper")
  trap 'rm -f -- "$helper_host"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  stage_target_asset \
    "$(installer_repo_file_value FILE_DESKTOP_FONTS_INSTALL)" "$helper" 0700
  run_in_target "install pinned desktop fonts and refresh user font caches" \
    __INSTALLER_PATH_DIR_USR_BIN__/env -i HOME=__INSTALLER_PATH_DIR_ROOT_HOME__ LC_ALL=C PATH=__INSTALLER_PATH_DIR_USR_SBIN__:__INSTALLER_PATH_DIR_USR_BIN__:__INSTALLER_PATH_DIR_SBIN__:__INSTALLER_PATH_DIR_BIN__ \
    LABWC_FONTS_MAXIMUM_EXPANDED_BYTES="$LABWC_FONTS_MAXIMUM_EXPANDED_BYTES" \
    LABWC_FONTS_MAXIMUM_MEMBER_BYTES="$LABWC_FONTS_MAXIMUM_MEMBER_BYTES" \
    LABWC_FONTS_MAXIMUM_MEMBERS="$LABWC_FONTS_MAXIMUM_MEMBERS" \
    __INSTALLER_PATH_DIR_USR_BIN__/timeout --signal=TERM --kill-after=5s 1800s \
    __INSTALLER_PATH_DIR_USR_BIN__/python3 -I "$helper" \
    --account "$ACCOUNT_USERNAME" --home "$ACCOUNT_HOME" \
    --archive FiraCode "$LABWC_FONT_FIRACODE_URL" "$LABWC_FONT_FIRACODE_SHA256" \
    --archive NerdFontsSymbolsOnly "$LABWC_FONT_SYMBOLS_URL" "$LABWC_FONT_SYMBOLS_SHA256" \
    --archive ProFont "$LABWC_FONT_PROFONT_URL" "$LABWC_FONT_PROFONT_SHA256" \
    --archive MicrosoftAptosFonts "$LABWC_FONT_APTOS_URL" "$LABWC_FONT_APTOS_SHA256" \
    --archive MicrosoftLocalFonts "$LABWC_FONT_MICROSOFT_URL" "$LABWC_FONT_MICROSOFT_SHA256"
  desktop_log "installed_pinned_fonts user=${ACCOUNT_USERNAME} terminal=.local/share/icons/terminal-fonts microsoft=.local/share/fonts/microsoft-fonts"
)
