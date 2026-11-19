#!/bin/sh
# Native appearance assets; no source builds or session-policy changes.

# Mapping templates describe already-rendered native lines. Their six shadow
# markers remain literal grammar for value capture/editing, never runtime
# configuration. Every other installer marker is an unresolved input.
desktop_assert_appearance_registry_placeholders() {
  if ! LC_ALL=C awk '
    {
      gsub(/__INSTALLER_LABWC_WAYBAR_((INTERNAL|EXTERNAL)_(ACTIVE|PANEL)|SHARED_MENU(_HOVER)?)_SHADOW__/, "")
      if ($0 ~ /__INSTALLER_[[:alnum:]_]/) exit 1
    }
  ' "$1"; then
    installer_fatal 'appearance registry has unresolved installer fields outside its literal mapping grammar'
    return 1
  fi
}

desktop_stage_appearance() (
  set -eu
  for directory in \
    "${DIR_USR_LOCAL_LIB}" \
    "${DIR_PYTHON3_LOCAL}" \
    "${DIR_PYTHON3_SITE_PACKAGES}" \
    "${DIR_PYTHON3_SITE_MANAGED_WORKFLOWS}" \
    "${DIR_PYTHON3_SITE_LABWC_APPEARANCE}" \
    "${DIR_USR_LOCAL_LIBEXEC}" \
    "${DIR_USR_LOCAL_SHARE}" \
    "${DIR_USR_LOCAL_SHARE_LABWC_APPEARANCE}" \
    "${DIR_VAR_LIB}/labwc-appearance" \
    __INSTALLER_PATH_DIR_USR_SHARE__/polkit-1/actions
  do
    ensure_target_asset_parent "${directory}/.installer-directory"
    directory_host=$(target_asset_host_path "$directory")
    [ -d "$directory_host" ] && [ ! -L "$directory_host" ] ||
      installer_fatal "unsafe appearance asset directory: ${directory}"
    chown root:root "$directory_host"
    chmod 0755 "$directory_host"
  done
  state_host=$(target_asset_host_path "${DIR_VAR_LIB}/labwc-appearance")
  chmod 0700 "$state_host"
  desktop_stage_role_asset FILE_TARGET_BIN_LABWC_DESKTOP_APPEARANCE "${DIR_USR_LOCAL_BIN}/labwc-desktop-appearance" 0755
  desktop_render_role_target_template \
    FILE_TARGET_SHARE_LABWC_APPEARANCE_MENU_ICONS_TMPL \
    "${DIR_USR_LOCAL_SHARE_LABWC_APPEARANCE}/menu-icons.json" 0644
  desktop_stage_role_asset FILE_TARGET_LIBEXEC_LABWC_APPEARANCE_GREETER \
    "${DIR_USR_LOCAL_LIBEXEC}/labwc-appearance-greeter" 0755
  for path in \
    usr/local/lib/python3/dist-packages/managed_workflows/__init__.py \
    usr/local/lib/python3/dist-packages/managed_workflows/fs.py \
    usr/local/lib/python3/dist-packages/managed_workflows/process.py \
    usr/local/lib/python3/dist-packages/labwc_appearance/__init__.py \
    usr/local/lib/python3/dist-packages/labwc_appearance/catalog.py \
    usr/local/lib/python3/dist-packages/labwc_appearance/cli.py \
    usr/local/lib/python3/dist-packages/labwc_appearance/defaults.py \
    usr/local/lib/python3/dist-packages/labwc_appearance/editor.py \
    usr/local/lib/python3/dist-packages/labwc_appearance/editors.py \
    usr/local/lib/python3/dist-packages/labwc_appearance/engine.py \
    usr/local/lib/python3/dist-packages/labwc_appearance/fields.py \
    usr/local/lib/python3/dist-packages/labwc_appearance/greeter.py \
    usr/local/lib/python3/dist-packages/labwc_appearance/icon_catalog.py \
    usr/local/lib/python3/dist-packages/labwc_appearance/native.py \
    usr/local/lib/python3/dist-packages/labwc_appearance/service.py \
    usr/local/lib/python3/dist-packages/labwc_appearance/themes.py \
    usr/local/lib/python3/dist-packages/labwc_appearance/transaction.py \
    usr/local/lib/python3/dist-packages/labwc_appearance/wallpaper.py
  do
    desktop_stage_role_asset "$path" "/$path" 0644
  done
  # fetch_hook renders only field defaults before atomic publication. Keep
  # the mapping markers literal for the later native-defaults capture.
  if desktop_role_owns_target "${DIR_USR_LOCAL_SHARE_LABWC_APPEARANCE}/fields.json"; then
    publish_target_asset "$(installer_repo_file_value FILE_TARGET_SHARE_LABWC_APPEARANCE_FIELDS_TMPL)" \
      "${DIR_USR_LOCAL_SHARE_LABWC_APPEARANCE}/fields.json" 0644 appearance-registry
  fi
  desktop_stage_role_asset FILE_TARGET_USR_SHARE_POLKIT_1_ACTIONS_ORG_LABWC_DESKTOP_APPEARANCE_POLICY \
    __INSTALLER_PATH_DIR_USR_SHARE__/polkit-1/actions/org.labwc.desktop-appearance.policy 0644
)

# Installation code has a private, temporary target import root. Runtime modules
# remain under their canonical root; no setup program survives this invocation.
desktop_run_appearance_setup() (
  set -eu
  setup_action=$1
  shift
  case "$setup_action:$#" in themes:0|defaults:1|extract:2) ;; *) installer_fatal 'invalid appearance setup action' ;; esac
  setup_parent="${TARGET_ROOT}${DIR_TMP}"
  installer_apt_safe_path "$setup_parent" || installer_fatal 'unsafe appearance setup ancestry'
  setup_stage=$(mktemp -d "$setup_parent/install-appearance.XXXXXX")
  chmod 0700 "$setup_stage"
  setup_target=${setup_stage#"$TARGET_ROOT"}
  setup_package="$setup_stage/appearance_setup"
  setup_cleanup() {
    setup_status=$?
    trap - 0
    if ! rm -f "$setup_stage/setup.py" "$setup_package/__init__.py" \
        "$setup_package/defaults.py" "$setup_package/release.py" "$setup_package/theme_archive.py" \
        "$setup_package/theme_assets.py" "$setup_package/theme_resources.py" \
        "$setup_package/theme_install.py" ||
        ! rmdir "$setup_package" "$setup_stage"; then
      installer_error 'private appearance setup cleanup failed'
      [ "$setup_status" -ne 0 ] || setup_status=1
    fi
    exit "$setup_status"
  }
  trap setup_cleanup 0
  trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
  install -d -m 0700 "$setup_package"
  installer_stage_profile_file FILE_DESKTOP_APPEARANCE_SETUP "$setup_target/setup.py" 0600
  while IFS='|' read -r selector leaf; do
    installer_stage_profile_file "$selector" "$setup_target/appearance_setup/$leaf" 0600
  done <<'EOF'
FILE_DESKTOP_APPEARANCE_INIT|__init__.py
FILE_DESKTOP_APPEARANCE_DEFAULTS|defaults.py
FILE_DESKTOP_APPEARANCE_RELEASE|release.py
FILE_DESKTOP_APPEARANCE_THEME_ARCHIVE|theme_archive.py
FILE_DESKTOP_APPEARANCE_THEME_ASSETS|theme_assets.py
FILE_DESKTOP_APPEARANCE_THEME_RESOURCES|theme_resources.py
FILE_DESKTOP_APPEARANCE_THEME_INSTALL|theme_install.py
EOF
  run_in_target "prepare native desktop appearance: $setup_action" \
    "${DIR_USR_BIN}/python3" -I -B "$setup_target/setup.py" "$setup_action" "$@"
)

desktop_extract_theme_release() (
  set -eu
  source_root=$1
  archive_host="${TMP_ENV_DIR}/desktop-themes.tar.gz"
  archive_target="${DIR_TMP}/installer-desktop-themes.tar.gz"
  archive_target_host=$(target_asset_host_path "$archive_target")
  trap 'rm -f -- "$archive_host" "$archive_target_host"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  desktop_download_release_archive \
    'desktop themes' \
    "$LABWC_DESKTOP_THEMES_TAG" \
    "$LABWC_DESKTOP_THEMES_URL" \
    "$LABWC_DESKTOP_THEMES_SHA256" \
    desktop-themes.tar.gz \
    "$archive_host"

  install -m 0600 "$archive_host" "$archive_target_host"
  rm -f -- "$archive_host"

  desktop_run_appearance_setup extract "$archive_target" "$source_root"
  rm -f -- "$archive_target_host"
  desktop_log "extracted_verified_release label=desktop-themes tag=${LABWC_DESKTOP_THEMES_TAG}"
)

desktop_install_appearance_themes() (
  set -eu
  source_root="${DIR_USR_LOCAL_SHARE_LABWC_APPEARANCE}/.installer-themes"
  source_host=$(target_asset_host_path "$source_root")
  [ ! -e "$source_host" ] && [ ! -L "$source_host" ] ||
    installer_fatal "theme installation staging already exists; retained evidence: ${source_root}"
  ensure_target_asset_parent "${source_root}/.anchor"
  [ -d "$source_host" ] && [ ! -L "$source_host" ] ||
    installer_fatal 'unsafe desktop theme staging directory'
  chown root:root "$source_host"
  chmod 0700 "$source_host"
  desktop_extract_theme_release "$source_root"
  desktop_run_appearance_setup themes
)

desktop_capture_appearance_defaults() {
  desktop_run_appearance_setup defaults "${DIR_INSTALLER_TARGET_DEFAULTS}/desktop"
}
