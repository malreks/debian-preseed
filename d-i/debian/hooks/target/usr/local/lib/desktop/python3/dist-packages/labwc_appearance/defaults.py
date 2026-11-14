"""Validate and read the captured native desktop appearance defaults."""
from __future__ import annotations
from pathlib import Path
import re
from managed_workflows.fs import Tree
from .native import FILES, GREETER_FILES, OPTIONAL_FILES, user_paths
from .icon_catalog import ICON_NAMES, POINTER_NAMES

DIRECTORY = Path('__INSTALLER_PATH_DIR_USR_LOCAL_SHARE__/labwc-appearance')


def validate(value):
    if not isinstance(value, dict) or value.get('schema') != 3:
        raise ValueError('unsupported installed appearance defaults')
    files, greeter = value.get('files'), value.get('greeter')
    if not isinstance(files, dict) or not isinstance(greeter, dict):
        raise ValueError('invalid installed appearance defaults')
    if set(files) - user_paths() or set(greeter) != set(GREETER_FILES):
        raise ValueError('unexpected default configuration path')
    required = {'.config/' + p for paths in FILES.values() for p in paths}
    if not required <= set(files):
        raise ValueError('installation did not capture all appearance defaults')
    for path, text in {**files, **greeter}.items():
        if text is None and path in {'.config/' + p for p in OPTIONAL_FILES}:
            continue
        if not isinstance(text, str) or len(text) > 2 * 1024**2 or re.search(r'__[A-Z0-9_]+__', text):
            raise ValueError('unrendered or invalid installed appearance default')
    if value.get('mode') not in ('dark', 'light'):
        raise ValueError('invalid installed color mode')
    for key, allowed in (('icon_theme', ICON_NAMES), ('pointer_theme', POINTER_NAMES)):
        if not isinstance(value.get(key), str) or value[key] not in allowed:
            raise ValueError('invalid installed ' + key)
    settings = value.get('settings')
    if (not isinstance(settings, dict) or set(settings) != {'color-scheme', 'gtk-theme'} or
            any(not isinstance(v, str) or not re.fullmatch(r"'[A-Za-z0-9_. +:-]{1,100}'", v)
                for v in settings.values()) or
            settings['color-scheme'] not in ("'default'", "'prefer-dark'", "'prefer-light'")):
        raise ValueError('invalid installed desktop settings defaults')
    return value


def load():
    with Tree(DIRECTORY, uid=0) as tree:
        return validate(tree.json('defaults.json'))
