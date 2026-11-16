"""Installation-only capture of native appearance fields and reset defaults."""
from __future__ import annotations
import json
import os
from pathlib import Path
import re
import subprocess
from managed_workflows.fs import Tree
from labwc_appearance.defaults import DIRECTORY, validate
from labwc_appearance.editors import ini_values
from labwc_appearance.fields import (REGISTRY, load_registry, validate_value,
                                    _registry_token_validator, _locate_line_parts)
from labwc_appearance.icon_catalog import ICON_NAMES, POINTER_NAMES
from labwc_appearance.native import FILES, GREETER_FILES, VARIANTS, OPTIONAL_FILES


def capture_registry(payload_defaults: Path) -> None:
    """Bind every field and its reset value to the fully staged native configs."""
    if os.getuid() != 0 or os.geteuid() != 0:
        raise ValueError('appearance field capture is installation-only')
    registry = load_registry(require_captured=False)
    token_validator = _registry_token_validator(registry)
    with Tree(payload_defaults, uid=0, private=True) as skeleton, \
            Tree(Path('__INSTALLER_PATH_DIR_ETC__/greetd'), uid=0) as greeter:
        contents: dict[str, list[str]] = {}
        for field in registry['fields']:
            values = []
            for mapping in field['mappings']:
                path = mapping['path']
                if path not in contents:
                    raw = (greeter.read(path[len('__INSTALLER_PATH_DIR_ETC__/greetd/'):]) if path.startswith('/')
                           else skeleton.read('.config/' + path))
                    text = raw.decode('utf-8')
                    if re.search(r'__[A-Z][A-Z0-9_]+__', text):
                        raise ValueError('unrendered native appearance config: ' + path)
                    contents[path] = text.splitlines()
                lines = contents[path]
                located = _locate_line_parts(lines, mapping, token_validator)
                if located is None:
                    raise ValueError('staged appearance mapping is unavailable: ' + field['key'])
                _, parsed = located
                values.append(validate_value(field, parsed[1][mapping['target_index']], mapping))
            if not values or any(value != values[0] for value in values[1:]):
                raise ValueError('staged appearance mappings disagree: ' + field['key'])
            field['default'] = values[0]
    registry['captured'] = True
    with Tree(REGISTRY.parent, uid=0) as output:
        output.write(REGISTRY.name, (json.dumps(registry, indent=2) + '\n').encode(), mode=0o644)



def main(argv):
    if len(argv) != 2 or argv[0] != '--capture' or os.getuid() != 0:
        raise ValueError('native appearance defaults capture is installation-only')
    payload_defaults = Path(argv[1])
    capture_registry(payload_defaults)
    DIRECTORY.mkdir(mode=0o755, parents=True, exist_ok=True)
    with Tree(DIRECTORY, uid=0) as output:
        existing = output.json('defaults.json')
        if existing is not None:
            validate(existing)
            return 0
        files = {}
        with Tree(payload_defaults, uid=0, private=True) as skeleton:
            for paths in FILES.values():
                for path in paths:
                    for suffix in VARIANTS:
                        if path in OPTIONAL_FILES and suffix:
                            continue
                        relative = '.config/' + path + suffix
                        raw = skeleton.read(relative, missing=bool(suffix) or path in OPTIONAL_FILES)
                        if raw is not None or not suffix:
                            files[relative] = None if raw is None else raw.decode('utf-8')
        with Tree(Path('__INSTALLER_PATH_DIR_ETC__/greetd'), uid=0) as greetd:
            greeter = {name: greetd.read(name).decode('utf-8') for name in GREETER_FILES}
        gtk = ini_values(files['.config/gtk-3.0/settings.ini'])
        mode = 'dark' if gtk.get(('Settings', 'gtk-application-prefer-dark-theme')) in ('1', 'true') else 'light'
        # Read the installed, compiled schema overrides, without opening root's
        # dconf or starting a session bus. This includes the installed prefer-light
        # override; hard-coding 'default' would not restore the installed system.
        settings = {}
        for key in ('color-scheme', 'gtk-theme'):
            settings[key] = subprocess.run(
                ['__INSTALLER_PATH_DIR_USR__/bin/gsettings', 'get', 'org.gnome.desktop.interface', key],
                env={'PATH': '__INSTALLER_PATH_DIR_USR__/bin:/bin', 'LANG': 'C.UTF-8',
                     'GSETTINGS_BACKEND': 'memory'},
                text=True, capture_output=True, check=True, timeout=15).stdout.strip()
        gtk_values = ini_values(files['.config/gtk-3.0/settings.ini'])
        icon_theme = gtk_values.get(('Settings', 'gtk-icon-theme-name'))
        pointer_theme = gtk_values.get(('Settings', 'gtk-cursor-theme-name'))
        if icon_theme not in ICON_NAMES or pointer_theme not in POINTER_NAMES:
            raise ValueError('installed icon or pointer default is not in the managed catalog')
        result = {'schema': 3, 'files': files, 'greeter': greeter, 'mode': mode,
                  'icon_theme': icon_theme, 'pointer_theme': pointer_theme,
                  'settings': settings}
        validate(result)
        output.write('defaults.json', (json.dumps(result, sort_keys=True, indent=2) + '\n').encode(), mode=0o644)
    return 0
