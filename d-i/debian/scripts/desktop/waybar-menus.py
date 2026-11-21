#!/usr/bin/python3
"""Validate rendered native menus during installation; never install this tool."""
import json
import os
from pathlib import Path
import re
import shlex
import stat
import sys
import types
import xml.etree.ElementTree as ET


def read(path, limit):
    for parent in path.parents:
        info = parent.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid or info.st_mode & 0o022:
            raise ValueError('unsafe rendered menu ancestry')
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    with os.fdopen(descriptor, 'rb') as stream:
        before = os.fstat(stream.fileno())
        if (not stat.S_ISREG(before.st_mode) or before.st_uid or before.st_nlink != 1
                or before.st_mode & 0o022 or before.st_size > limit):
            raise ValueError('unsafe rendered menu file')
        data = stream.read(limit + 1)
        after = os.fstat(stream.fileno())
    identity = lambda value: (value.st_dev, value.st_ino, value.st_size, value.st_nlink,
                              value.st_mtime_ns, value.st_ctime_ns)
    if len(data) != before.st_size or not identity(before) == identity(after) == identity(path.lstat()):
        raise ValueError('rendered menu changed during validation')
    if b'__INSTALLER_' in data or b'__THEME_' in data or b'\0' in data:
        raise ValueError('rendered menu has unresolved or invalid data')
    return data


def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate native menu configuration key')
        result[key] = value
    return result


POPUP_MENU_BUTTONS = {
    'custom/wayscriber': 'wayscriber',
}


def validate_popup_owner(module_name, value, runner, dispatcher):
    """Validate the explicitly owned release-event popup contract.

    Waybar's native ``menu`` property is a press-event owner.  Wayscriber is
    the one custom module whose menu is owned by ``labwc-waybar-menu`` so its
    active marker can follow GTK menu destruction; accepting it as a native
    menu would register a second owner and make installation non-deterministic.
    """
    button = POPUP_MENU_BUTTONS.get(module_name)
    if button is None:
        return False
    if (value.get('menu') is not None
            or any(event in value for event in ('on-click', 'on-click-right', 'on-click-middle'))
            or 'actions' in value):
        raise ValueError('popup menu must have exactly one registered release-event owner')
    command = value.get('on-click-release')
    try:
        arguments = shlex.split(command) if isinstance(command, str) else []
    except ValueError as error:
        raise ValueError('popup menu owner has invalid command quoting') from error
    expected = [str(runner), '--menu=' + button]
    if arguments != expected:
        raise ValueError('popup menu must have exactly one registered release-event owner')
    dispatcher.normalize_command(arguments[1:])
    secondary = value.get('on-click-right-release')
    if secondary is None:
        raise ValueError('popup menu must retain its fixed secondary release action')
    try:
        secondary_arguments = shlex.split(secondary)
    except ValueError as error:
        raise ValueError('popup menu secondary action has invalid command quoting') from error
    if not secondary_arguments or secondary_arguments.pop(0) != str(runner):
        raise ValueError('popup menu secondary action bypasses the fixed dispatcher')
    dispatcher.normalize_command(secondary_arguments)
    return True


def validate_entries(root, runner, dispatcher, module, used_menus):
    menus = 0
    # Some authored fragments contain related modules, such as system/settings.
    if not isinstance(module, dict) or not 1 <= len(module) <= 16:
        raise ValueError('invalid rendered module identity')
    for module_name, value in module.items():
        if not isinstance(value, dict):
            raise ValueError('invalid rendered module configuration')
        if 'menu-actions' not in value:
            continue
        event, actions, filename = value.get('menu'), value['menu-actions'], value.get('menu-file')
        popup_owner = validate_popup_owner(module_name, value, runner, dispatcher)
        if not popup_owner and (event not in ('on-click', 'on-click-right', 'on-click-middle')
                                or event in value or event + '-release' in value
                                or event in value.get('actions', {})):
            raise ValueError('native menu must have exactly one registered press-event owner')
        if (not isinstance(actions, dict) or not actions or len(actions) > 128
                or not isinstance(filename, str)
                or re.fullmatch(r'~/.config/waybar/gtk/[a-z][a-z-]*-menu\.xml', filename) is None):
            raise ValueError('invalid canonical menu contract')
        data = read(root / 'gtk' / filename.rsplit('/', 1)[1], 524288)
        used_menus.add(filename.rsplit('/', 1)[1])
        if b'<!DOCTYPE' in data or b'<!ENTITY' in data:
            raise ValueError('native menu cannot declare entities')
        tree = ET.fromstring(data)
        identifiers = [node.get('id') for node in tree.iter('object') if node.get('id')]
        roots = tree.findall('./object[@class="GtkMenu"][@id="menu"]')
        if (len(roots) != 1 or len(identifiers) != len(set(identifiers))
                or any(node is not roots[0] and node.get('class') != 'GtkAccelGroup'
                       for node in tree.findall('./object'))):
            raise ValueError('duplicate GtkBuilder identity or invalid menu root')
        leaves = [node for node in roots[0].iter('object') if node.get('class') == 'GtkMenuItem'
                  and node.find('./child[@type="submenu"]') is None]
        leaf_ids = [node.get('id') for node in leaves]
        if not all(leaf_ids) or set(leaf_ids) != set(actions):
            raise ValueError('missing, unknown, wrong-type or unused native menu action')
        for action_id, command in actions.items():
            if (re.fullmatch(r'[a-z][a-z0-9_]{0,63}', action_id) is None
                    or not isinstance(command, str) or len(command) > 512):
                raise ValueError('invalid native menu action identity')
            arguments = shlex.split(command)
            if not arguments or arguments.pop(0) != str(runner):
                raise ValueError('native menu action bypasses the fixed dispatcher')
            dispatcher.normalize_command(arguments)
        menus += 1
    return menus


def validate(root, runner):
    # The same root-owned fixed argv allowlist used at runtime is the authority.
    source = read(runner, 65536)
    dispatcher = types.ModuleType('installer_waybar_runner')
    dispatcher.__file__ = str(runner)
    exec(compile(source, str(runner), 'exec'), vars(dispatcher))
    menus = 0
    used_menus = set()
    for index, path in enumerate(sorted((root / 'modules').iterdir())):
        if index >= 128:
            raise ValueError('native menu module count exceeds bound')
        module = json.loads(read(path, 262144), object_pairs_hook=unique)
        menus += validate_entries(root, runner, dispatcher, module, used_menus)
    available = list((root / 'gtk').iterdir())
    if len(available) > 128 or not menus or used_menus != {path.name for path in available}:
        raise ValueError('missing or unused canonical native menu assets')
    return menus


if __name__ == '__main__':
    try:
        if len(sys.argv) != 3:
            raise ValueError('expected rendered Waybar root and fixed runner')
        print('native_menu_contracts=' + str(validate(Path(sys.argv[1]), Path(sys.argv[2]))))
    except (OSError, ValueError, TypeError, ET.ParseError) as error:
        print('native menu validation failed: ' + str(error)[:192], file=sys.stderr)
        raise SystemExit(1)
