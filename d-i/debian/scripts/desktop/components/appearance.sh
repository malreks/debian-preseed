#!/bin/sh
# Native appearance assets; no source builds or session-policy changes.

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
  desktop_stage_role_asset FILE_TARGET_SHARE_LABWC_APPEARANCE_FIELDS_TMPL \
    __INSTALLER_PATH_DIR_USR_LOCAL__/share/labwc-appearance/fields.json 0644
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

desktop_verify_appearance_assets() {
  # Target installation boundary before consumer enablement. Inspect source
  # and assets as data, without importing or invoking a managed module.
  run_in_target "verify installed desktop theme providers and reset defaults" \
    __INSTALLER_PATH_DIR_USR_BIN__/python3 -I -S -B -c '
import ast
import configparser
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import stat
import time

deadline = time.monotonic() + 120
def require(condition, message):
    if not condition:
        raise SystemExit("fatal: desktop appearance contract: " + message)

def read(path, mode, limit):
    require(time.monotonic() < deadline, "asset inspection deadline")
    for parent in path.parents:
        info = parent.lstat()
        require(stat.S_ISDIR(info.st_mode) and info.st_uid == 0 and not info.st_mode & 0o022,
                "unsafe asset parent")
    info = path.lstat()
    modes = (mode,) if isinstance(mode, int) else mode
    require(stat.S_ISREG(info.st_mode) and info.st_uid == 0 and info.st_gid == 0
            and info.st_nlink == 1 and stat.S_IMODE(info.st_mode) in modes
            and 0 <= info.st_size <= limit, "unsafe asset metadata: " + str(path))
    with path.open("rb") as stream:
        data = stream.read(limit + 1)
    require(len(data) == info.st_size, "asset changed or exceeded read budget")
    return data

package = Path("__INSTALLER_PATH_DIR_PYTHON3_SITE_PACKAGES__/labwc_appearance")
modules = ("__init__", "catalog", "cli", "defaults", "editors", "editor", "engine", "fields", "greeter", "icon_catalog", "native",
           "service", "themes", "transaction", "wallpaper")
brands = set()
for module in modules:
    path = package / (module + ".py")
    text = read(path, 0o644, 256 * 1024).decode("utf-8")
    if module not in ("editor", "fields"):
        require(re.search(r"__[A-Z][A-Z0-9_]{2,}__", text) is None, "unresolved appearance token")
    tree = ast.parse(text, filename=str(path))
    if module == "themes":
        brands = {node.args[0].value for node in ast.walk(tree)
                  if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                  and node.func.id == "_family" and node.args and isinstance(node.args[0], ast.Constant)}
require(len(brands) == 20, "invalid desktop theme family catalog")
for helper in ("labwc-appearance-greeter",):
    path = Path("__INSTALLER_PATH_DIR_USR_LOCAL__/libexec") / helper
    ast.parse(read(path, 0o755, 16384).decode("utf-8"), filename=str(path))

registry = Path("__INSTALLER_PATH_DIR_USR_LOCAL__/share/labwc-appearance")
pending = registry / "themes-install-pending.json"
require(not pending.exists() and not pending.is_symlink(), "theme publication needs recovery")
fields = json.loads(read(registry / "fields.json", 0o644, 8 * 1024**2))
allowed_field_paths = {
    "fuzzel/base.ini", "fuzzel/fuzzel.ini", "fuzzel/menu.ini", "fuzzel/computer-management.ini",
    "waybar/style.css", "waybar/style-common.css", "waybar/config",
    "waybar/modules/app-files",
    "waybar/modules/app-notes",
    "waybar/modules/app-sleek",
    "waybar/modules/app-terminal",
    "waybar/modules/app-tuta",
    "waybar/modules/apps",
    "waybar/modules/backlight",
    "waybar/modules/battery",
    "waybar/modules/bluetooth",
    "waybar/modules/clock",
    "waybar/modules/cpu",
    "waybar/modules/disk",
    "waybar/modules/external-apps-drawer",
    "waybar/modules/external-launcher",
    "waybar/modules/external-quick-controls",
    "waybar/modules/external-taskbar",
    "waybar/modules/external-tray",
    "waybar/modules/internal-apps-drawer",
    "waybar/modules/internal-launcher",
    "waybar/modules/internal-quick-controls",
    "waybar/modules/internal-taskbar",
    "waybar/modules/internal-tray",
    "waybar/modules/keyboard",
    "waybar/modules/lock",
    "waybar/modules/memory",
    "waybar/modules/network",
    "waybar/modules/notifications",
    "waybar/modules/power",
    "waybar/modules/pulseaudio",
    "waybar/modules/screenshot",
    "waybar/modules/system",
    "waybar/modules/tomat",
    "waybar/modules/wayscriber",
    "waybar/modules/window-switcher",
    "waybar/modules/workspaces",
    "waybar/style/gtk.css",
    "waybar/style/menu.css", "waybar/style/workspaces.css", "waybar/style/tomat.css",
    "waybar/style/wayscriber.css", "waybar/style/taskview.css", "waybar/style/apps.css",
    "waybar/style/clock.css", "waybar/style/audio.css", "waybar/style/brightness.css",
    "waybar/style/battery.css", "waybar/style/storage.css", "waybar/style/cpu.css",
    "waybar/style/memory.css", "waybar/style/tray.css", "waybar/style/system.css",
    "waybar/style/notifications.css", "waybar/style/lock.css", "waybar/style/power.css",
    "waybar/icons/apps-symbolic.svg", "waybar/icons/wayscriber-symbolic.svg",
    "waycal/style.css",
    "swaylock/config",
    "crystal-dock/labwc/appearance.conf", "foot/foot.ini", "kitty/kitty.conf", "mako/config",
    "gtk-3.0/settings.ini", "gtk-4.0/settings.ini", "gtk-4.0/gtk.css",
    "qt5ct/qt5ct.conf", "qt6ct/qt6ct.conf", "qt5ct/colors/labwc-appearance.conf",
    "qt6ct/colors/labwc-appearance.conf", "Kvantum/kvantum.kvconfig",
    "labwc/themerc-override", "labwc/environment", "__INSTALLER_PATH_DIR_ETC__/greetd/gtkgreet.css",
    "__INSTALLER_PATH_DIR_ETC__/greetd/gtkgreet-power.css",
}
require(isinstance(fields, dict) and fields.get("schema") == 3
        and fields.get("captured") is True
        and isinstance(fields.get("components"), list) and fields["components"]
        and isinstance(fields.get("fields"), list) and 0 < len(fields["fields"] ) <= 1024,
        "incomplete native appearance field registry")
field_keys = set()
for field in fields["fields"]:
    require(isinstance(field, dict)
            and isinstance(field.get("key"), str)
            and re.fullmatch(r"[A-Z][A-Z0-9_]{2,127}", field["key"]) is not None
            and field["key"] not in field_keys
            and field.get("component") in ("DOCK", "FUZZEL", "WAYBAR", "TASKVIEW", "WAYCAL", "MAKO", "TERMINAL", "SWAYLOCK", "GTKGREET")
            and field.get("type") in ("hash6", "hash8", "hex6", "hex8", "swaylock-rgb", "swaylock-rgba", "rgba", "alpha", "decimal", "text-color", "mako-progress")
            and isinstance(field.get("default"), str)
            and isinstance(field.get("mappings"), list) and field["mappings"],
            "invalid native appearance field")
    field_keys.add(field["key"])
    for mapping in field["mappings"]:
        require(isinstance(mapping, dict)
                and isinstance(mapping.get("path"), str)
                and mapping["path"] in allowed_field_paths
                and type(mapping.get("line")) is int and 1 <= mapping["line"] <= 100000
                and isinstance(mapping.get("template"), str)
                and isinstance(mapping.get("tokens"), list) and mapping["tokens"]
                and all(isinstance(token, str)
                        and (token.startswith("__THEME_") or token.startswith("__INSTALLER_"))
                        and token.endswith("__") for token in mapping["tokens"])
                and mapping["tokens"] == re.findall(r"__(?:THEME|INSTALLER)_[A-Z0-9_]+__", mapping["template"])
                and type(mapping.get("target_index")) is int
                and 0 <= mapping["target_index"] < len(mapping["tokens"])
                and mapping["tokens"][mapping["target_index"]] == "__THEME_" + field["key"] + "__"
                and mapping.get("grammar") in ("gtk3-css-color", "gtk4-css-color", "pango-color",
                                                "qt-color", "mako-color", "mako-progress", "swaylock-rgb", "swaylock-rgba",
                                                "fuzzel-rgba", "foot-rgb", "kitty-color", "alpha",
                                                "decimal"),
                "invalid native appearance field mapping")
manifest = json.loads(read(registry / "themes.json", 0o644, 6 * 1024**2))
require(isinstance(manifest, dict) and manifest.get("schema") == 1
        and isinstance(manifest.get("variants"), dict) and len(manifest["variants"]) == 50
        and isinstance(manifest.get("files"), dict) and 0 < len(manifest["files"]) <= 24000,
        "incomplete theme inventory")
families = set()
for identity, directories in manifest["variants"].items():
    require(isinstance(identity, str) and re.fullmatch(r"[a-z][a-z0-9-]{0,79}", identity) is not None
            and isinstance(directories, list), "invalid theme identifier")
    family = next((name for name in brands if identity.startswith(name + "-")), None)
    require(family is not None, "unknown theme family")
    families.add(family)
    gtk = "themes/Labwc-" + identity
    kvantum = "Kvantum/Labwc-" + identity
    expected = ([] if family == "adwaita" else [gtk])
    if family not in ("adwaita", "breeze"):
        expected.append(kvantum)
    require(directories == expected, "incorrect GTK/Qt provider pairing")
    if family != "adwaita":
        for version in ("3.0", "4.0"):
            require(gtk + "/gtk-" + version + "/gtk.css" in manifest["files"], "missing GTK provider")
    if family not in ("adwaita", "breeze"):
        for extension in (".kvconfig", ".svg"):
            require(kvantum + "/Labwc-" + identity + extension in manifest["files"], "missing Qt provider")
require(families == brands, "desktop theme brands were counted as variants")
total = 0
for relative, metadata in manifest["files"].items():
    path = PurePosixPath(relative)
    require(not path.is_absolute() and str(path) == relative and len(path.parts) <= 32
            and all(part not in ("", ".", "..", "gtk-2.0") for part in path.parts)
            and path.parts[0] in ("themes", "Kvantum", "doc"), "unsafe installed asset path")
    require(isinstance(metadata, dict) and type(metadata.get("bytes")) is int
            and 0 <= metadata["bytes"] <= 16 * 1024**2
            and isinstance(metadata.get("sha256"), str)
            and re.fullmatch(r"[0-9a-f]{64}", metadata["sha256"]) is not None, "invalid asset descriptor")
    total += metadata["bytes"]
    require(total <= 512 * 1024**2, "aggregate theme asset budget")
    blob = read(Path("__INSTALLER_PATH_DIR_USR_SHARE__") / relative, 0o644, metadata["bytes"])
    require(hashlib.sha256(blob).hexdigest() == metadata["sha256"], "installed asset hash differs")
packages = manifest.get("packages", {})
require(isinstance(packages, dict) and isinstance(packages.get("plugins"), dict)
        and len(packages["plugins"]) == 7, "missing Qt5/Qt6 style and frontend plugins")
for relative, digest in packages["plugins"].items():
    require(re.fullmatch(r"lib/[A-Za-z0-9_+-]+/qt[56]/plugins/(?:styles/[A-Za-z0-9_.]+|platformthemes/libqt[56]ct.so)",
                        relative) is not None, "invalid Qt plugin path")
    require(hashlib.sha256(read(Path("__INSTALLER_PATH_DIR_USR__") / relative, (0o644, 0o755), 16 * 1024**2)).hexdigest() == digest,
            "installed Qt plugin hash differs")
try:
    defaults_bytes = read(registry / "defaults.json", 0o644, 8 * 1024**2)
except FileNotFoundError:
    require(False, "missing captured installation defaults")
try:
    defaults = json.loads(defaults_bytes)
except (UnicodeDecodeError, json.JSONDecodeError):
    require(False, "captured installation defaults are not valid UTF-8 JSON")
require(isinstance(defaults, dict), "captured installation defaults must be an object")
# defaults.main() captures schema 3, including icon and pointer reset selections.
require(type(defaults.get("schema")) is int and defaults.get("schema") == 3,
        "unsupported captured installation defaults schema (expected 3)")
require(isinstance(defaults.get("files"), dict),
        "captured installation defaults have no files mapping")
session_environment = read(Path("__INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/labwc/environment.d/10-wayland.env"),
                           0o644, 65536).decode("utf-8").splitlines()
require(session_environment.count("QT_QPA_PLATFORMTHEME=qt6ct") == 1,
        "the desktop platform theme must remain qt6ct")
for config in (Path("__INSTALLER_PATH_DIR_ETC__/xdg/qt6ct/qt6ct.conf"),
               Path("__INSTALLER_PATH_DIR_ETC__/skel-desktop/.config/qt6ct/qt6ct.conf")):
    text = read(config, 0o644, 65536).decode("utf-8")
    require(re.search(r"__[A-Z][A-Z0-9_]{2,}__", text) is None, "unresolved qt6ct token")
    parser = configparser.ConfigParser(interpolation=None, strict=True)
    parser.read_string(text)
    require(parser.get("Appearance", "style") in ("Adwaita", "Adwaita-Dark", "Breeze", "kvantum"),
            "invalid default Qt6 style")
print("Verified 20 theme families, 50 GTK3/GTK4 and Qt variants, and captured reset defaults.")
'
}
