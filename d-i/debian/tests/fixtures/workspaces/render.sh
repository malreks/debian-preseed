#!/bin/sh
# Test-only transport fixture; renderer and replacement functions are production.
set -eu
repo=$1
/usr/bin/python3 -I -B /workspace/repository/tools/isolation.py
destination=$2
LABWC_WORKSPACE_COUNT_INTERNAL=${3:-4}
LABWC_WORKSPACE_COUNT_EXTERNAL=${5:-${3:-4}}
LABWC_WINDOW_SWITCHER_STYLE=${4:-thumbnail}
# This fixture stubs transport, not rendering or the ordered module lists.
# The real authenticated loader is exercised by test_modular_installer.py.
# shellcheck disable=SC1090
. "$repo/d-i/debian/repo.env"
bootstrap_source_module() {
  case "${1%.tmpl}" in scripts/common/*.sh|scripts/desktop/components/*.sh) ;; *) return 1 ;; esac
  set -- "$repo/d-i/debian/$1"
  [ -f "$1" ] || set -- "$1.tmpl"
  . "$1"
}
bootstrap_repo_join_var() {
  case "$1" in
    DIR_SCRIPTS_COMMON) printf 'scripts/common/%s\n' "$2" ;;
    DIR_SCRIPTS_COMMON_MODULES) printf 'scripts/common/modules/%s\n' "$2" ;;
    *) return 1 ;;
  esac
}
bootstrap_repo_file_value() {
  case "$1" in FILE_[A-Z0-9_]*) ;; *) return 1 ;; esac
  case "$1" in *[!A-Z0-9_]*) return 1 ;; esac
  eval "fixture_selector_value=\${$1:-}"
  [ -n "$fixture_selector_value" ] || return 1
  printf '%s\n' "$fixture_selector_value"
}
bootstrap_load_source_library() { :; }
bootstrap_ensure_repo_env() { INSTALLER_REPO_ENV_READY=1; }
. "$repo/d-i/debian/scripts/common/lib.sh"
. "$repo/d-i/debian/scripts/common/target.sh"
. "$repo/d-i/debian/scripts/late/target-assets.sh"
. "$repo/d-i/debian/scripts/desktop/detect.sh.tmpl"
. "$repo/d-i/debian/scripts/desktop/components.sh"
INSTALLER_TARGET_DIR=$destination
TMP_ENV_DIR=$destination/tmp
mkdir -p "$TMP_ENV_DIR"
installer_repo_join_var() {
  fixture_relative_dir=$(installer_loaded_repo_dir_value "$1") || return $?
  [ -n "$fixture_relative_dir" ] || return 1
  printf '%s/d-i/debian/%s/%s\n' "$repo" "$fixture_relative_dir" "${2:-}"
}
installer_repo_file_value() {
  fixture_relative=$(bootstrap_repo_file_value "$1") || return $?
  printf '%s/d-i/debian/%s\n' "$repo" "$fixture_relative"
}
installer_repo_asset_path() {
  case "${2:-$1}" in
    FILE_*) installer_repo_file_value "${2:-$1}" ;;
    *) installer_repo_join_var "$1" "${2:-}" ;;
  esac
}
fetch_hook() { cp "$1" "$2"; }
desktop_log() { :; }
installer_log() { :; }
installer_warn() { printf "%s\n" "$*" >&2; }
installer_fatal() { printf '%s\n' "$*" >&2; exit 1; }
installer_fatal_status() { fixture_status=$1; shift; printf '%s\n' "$*" >&2; exit "$fixture_status"; }
installer_operation_context_repo() { :; }
# Load only output-class geometry from a real profile; unrelated fixture
# overrides for the workspace switcher remain explicit test inputs.
while IFS= read -r assignment; do
  case "$assignment" in LABWC_OUTPUT_INTERNAL_PREFIXES=*|LABWC_WAYBAR_INTERNAL_*=*|LABWC_WAYBAR_EXTERNAL_*=*) eval "$assignment" ;; esac
done < "$repo/d-i/debian/hosts/profiles/desktop/btrfs-de.env"
LABWC_DESKTOP_GTK_ICON_THEME=Papirus-Dark
LABWC_MANAGED_APP_DEFAULT_EXEC=foot
# A feature selector is transport context, not part of rendering itself.
installer_selected_class_reference_is_selected() { return 1; }
desktop_render_labwc_rc_xml
desktop_render_waybar_config
desktop_render_waybar_style
