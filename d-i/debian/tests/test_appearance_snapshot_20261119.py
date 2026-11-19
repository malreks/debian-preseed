"""Isolated fixtures for operation-local appearance inputs and preparation.

These fixtures are source-only until run inside the approved guest boundary.
Their runtime coordinators use memory trees and deny external command calls.
"""
from __future__ import annotations

from pathlib import Path as _IsolationPath
import sys as _isolation_sys
_isolation_sys.path.insert(0, str(_IsolationPath(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation as _require_test_isolation
_isolation_sys.path.pop(0)
_require_test_isolation()

import ast
from collections import Counter
import contextlib
import json
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace
import unittest
from unittest import mock

SEED = Path(__file__).resolve().parents[1]
PACKAGE = SEED / 'hooks/target/usr/local/lib/desktop/python3/dist-packages/labwc_appearance'
sys.path.insert(0, str(PACKAGE.parent))
sys.path.insert(0, str(SEED / 'hooks/target/usr/local/lib/common/python3/dist-packages'))
from labwc_appearance import engine, fields, transaction

TOKEN = 'a' * 32
HOME = Path('/fixture-account')
STYLE = '.config/waybar/style.css'


class CountedBytes(bytes):
    def __new__(cls, data):
        result = super().__new__(cls, data)
        result.decodes = 0
        return result

    def decode(self, *args, **options):
        self.decodes += 1
        return super().decode(*args, **options)


class MemoryTree:
    def __init__(self, files=None):
        self.files = {} if files is None else dict(files)
        self.reads = Counter()
        self.writes = []

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def mkdir(self, *args):
        pass

    def lock(self, name):
        return contextlib.nullcontext()

    def read(self, path, limit=8 * 1024 * 1024, *, missing=False):
        self.reads[path] += 1
        raw = self.files.get(path)
        if isinstance(raw, BaseException):
            raise raw
        if raw is None and not missing:
            raise FileNotFoundError(path)
        if raw is not None and len(raw) > limit:
            raise ValueError('fixture file exceeds the read limit')
        return raw

    def write(self, path, data, **options):
        self.writes.append(path)
        if data is None:
            self.files.pop(path, None)
        else:
            self.files[path] = data

    def json(self, path, default=None):
        raw = self.read(path, missing=True)
        return default if raw is None else json.loads(raw)

    def put_json(self, path, value):
        self.write(path, json.dumps(value).encode())


def descriptor(index, *, path='waybar/style.css', line=None, component='WAYBAR'):
    key = 'COLOR_' + str(index)
    token = '__THEME_' + key + '__'
    return {'key': key, 'component': component, 'type': 'hash6', 'default': '#112233',
            'label': key, 'category': 'Fixture', 'mappings': [
                {'path': path, 'line': index + 1 if line is None else line,
                 'template': 'color-' + str(index) + '=' + token, 'tokens': [token],
                 'target_index': 0, 'grammar': 'gtk3-css-color'}]}


def registry(count, *, path='waybar/style.css', component='WAYBAR'):
    return {'schema': 3, 'captured': True,
            'components': [{'id': component, 'label': component}],
            'fields': [descriptor(index, path=path, component=component) for index in range(count)]}


def contents(count, value='#112233'):
    return CountedBytes(''.join('color-' + str(index) + '=' + value + '\r\n'
                               for index in range(count)).encode())


class AppearanceSnapshotFixtures(unittest.TestCase):
    def setUp(self):
        self.context = contextlib.ExitStack()
        self.addCleanup(self.context.close)
        self.context.enter_context(mock.patch.object(
            subprocess, 'run', side_effect=AssertionError('external command is forbidden')))
        self.user = MemoryTree()
        self.greeter = MemoryTree()
        self.context.enter_context(mock.patch.object(fields, '_account_home', return_value=HOME))
        self.context.enter_context(mock.patch.object(
            fields, 'Tree', side_effect=lambda path, **options: self.user if path == HOME else self.greeter))

    def coordinator(self, values):
        self.context.enter_context(mock.patch.object(fields.os, 'getuid', return_value=1000))
        self.context.enter_context(mock.patch.object(fields.os, 'geteuid', return_value=1000))
        self.context.enter_context(mock.patch.object(fields.secrets, 'token_hex', return_value=TOKEN))
        self.context.enter_context(mock.patch.object(engine, 'privileged', side_effect=AssertionError('root helper')))
        self.context.enter_context(mock.patch.object(fields.service, 'active', return_value=False))
        self.refresh = self.context.enter_context(mock.patch.object(fields.service, 'refresh', return_value=[]))
        return self.context.enter_context(mock.patch.object(fields, 'load_registry', return_value=values))

    def test_many_fields_read_and_decode_one_file_once_per_refresh(self):
        values = registry(200)
        first = contents(200)
        self.user.files[STYLE] = first
        self.assertEqual(set(fields.current_values(values).values()), {'#112233'})
        self.assertEqual(self.user.reads, {STYLE: 1})
        self.assertEqual(first.decodes, 1)
        second = contents(200, '#aabbcc')
        self.user.files[STYLE] = second
        self.assertEqual(set(fields.current_values(values).values()), {'#aabbcc'})
        self.assertEqual(self.user.reads, {STYLE: 2})
        self.assertEqual(second.decodes, 1)

    def test_missing_unreadable_and_invalid_utf8_variants_are_local_to_refresh(self):
        for rejected in (b'\xff', PermissionError('fixture denied')):
            with self.subTest(rejected=type(rejected).__name__):
                self.user = MemoryTree({STYLE + '.internal': rejected,
                                        STYLE + '.external': contents(20)})
                self.assertEqual(set(fields.current_values(registry(20)).values()), {'#112233'})
                self.assertEqual(self.user.reads, {STYLE: 1, STYLE + '.internal': 1, STYLE + '.external': 1})
                self.user.files[STYLE] = contents(20, '#aabbcc')
                self.assertEqual(set(fields.current_values(registry(20)).values()), {'#aabbcc'})
                self.assertEqual(self.user.reads[STYLE], 2)
                self.assertEqual(self.user.reads[STYLE + '.external'], 1)

    def test_lru_eviction_preserves_readable_larger_working_sets(self):
        other = '.config/fuzzel/fuzzel.ini'
        first = CountedBytes(b'color-0=#112233\ncolor-2=#112233\n')
        self.user.files = {STYLE: first, other: b'color-1=#aabbcc\n'}
        values = {'fields': [descriptor(0), descriptor(1, path='fuzzel/fuzzel.ini', line=1),
                             descriptor(2, line=2)]}
        cost = 128 + 4 * len(first) + 96 * 2
        with mock.patch.object(fields, 'MAX_CURRENT_CACHE_COST', cost):
            result = fields.current_values(values)
        self.assertEqual(result, {'COLOR_0': '#112233', 'COLOR_1': '#aabbcc', 'COLOR_2': '#112233'})
        self.assertEqual(self.user.reads, {STYLE: 2, other: 1})

    def test_update_preparation_reads_each_variant_once_and_preserves_crlf(self):
        raw = contents(200)
        self.user.files[STYLE] = raw
        selected = {'COLOR_' + str(index): '#aabbcc' for index in range(200)}
        updates, expected, components = fields._prepare_user_updates(self.user, selected, registry(200))
        self.assertEqual(self.user.reads, {STYLE: 1, STYLE + '.internal': 1, STYLE + '.external': 1})
        self.assertEqual(expected, {STYLE: raw})
        self.assertEqual(updates, {STYLE: contents(200, '#aabbcc')})
        self.assertEqual(components, {'waybar'})
        self.assertEqual(raw.decodes, 1)

    def test_one_registry_load_covers_user_validation_and_publication(self):
        self.user.files[STYLE] = contents(20)
        loaded = self.coordinator(registry(20))
        selected = {'COLOR_' + str(index): '#aabbcc' for index in range(20)}
        self.assertEqual(fields.apply(selected), [])
        loaded.assert_called_once_with()
        self.refresh.assert_called_once_with({'waybar'})
        self.assertEqual(self.user.files[STYLE], contents(20, '#aabbcc'))
        self.assertNotIn(fields.USER_JOURNAL, self.user.files)

    def test_greeter_request_reuses_user_registry_without_external_read(self):
        values = registry(1, path='__INSTALLER_PATH_DIR_ETC__/greetd/gtkgreet.css', component='GTKGREET')
        with mock.patch.object(fields, 'load_registry', side_effect=AssertionError('registry reread')), \
                mock.patch.object(subprocess, 'run', return_value=SimpleNamespace(returncode=0)) as run:
            fields.apply_greeter({'COLOR_0': '#aabbcc'}, TOKEN, registry=values)
        self.assertEqual(json.loads(run.call_args.kwargs['input']), {'updates': {'COLOR_0': '#aabbcc'}})
        self.assertEqual(run.call_args.args[0][-2:], ['fields', TOKEN])

    def test_dock_shutdown_gets_fresh_inputs_without_reloading_registry(self):
        path = '.config/crystal-dock/labwc/appearance.conf'
        self.user.files[path] = contents(1)
        loaded = self.coordinator(registry(1, path=path[len('.config/'):], component='DOCK'))

        def stop():
            self.user.files[path] += b'[layout]\r\nsize=93\r\n'

        with mock.patch.object(fields.service, 'active', return_value=True), \
                mock.patch.object(fields.service, 'dock_stop', side_effect=stop) as stopped, \
                mock.patch.object(fields.service, 'dock_start') as started:
            fields.apply({'COLOR_0': '#aabbcc'})
        loaded.assert_called_once_with()
        stopped.assert_called_once_with()
        started.assert_called_once_with()
        self.assertEqual(self.user.files[path], contents(1, '#aabbcc') + b'[layout]\r\nsize=93\r\n')
        self.assertEqual(self.user.reads[path + '.internal'], 2)
        self.assertEqual(self.user.reads[path + '.external'], 2)

    def test_intervening_edit_is_rejected_before_journal_and_refresh(self):
        self.user.files[STYLE] = contents(1)
        self.coordinator(registry(1))
        original_plan = transaction.plan

        def changed(tree, updates, token, **options):
            tree.files[STYLE] = b'independent edit'
            return original_plan(tree, updates, token, **options)

        with mock.patch.object(transaction, 'plan', side_effect=changed), \
                self.assertRaisesRegex(RuntimeError, 'changed during preparation'):
            fields.apply({'COLOR_0': '#aabbcc'})
        self.assertEqual(self.user.files[STYLE], b'independent edit')
        self.assertNotIn(fields.USER_JOURNAL, self.user.writes)
        self.refresh.assert_not_called()

    def test_every_runtime_plan_binds_inputs_and_root_keeps_its_registry_owner(self):
        counts = {}
        for leaf in ('engine.py', 'fields.py', 'greeter.py', 'wallpaper.py'):
            tree = ast.parse((PACKAGE / leaf).read_text(encoding='utf-8'))
            plans = [node for node in ast.walk(tree) if isinstance(node, ast.Call)
                     and isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name)
                     and node.func.value.id == 'transaction' and node.func.attr == 'plan']
            self.assertTrue(all(any(keyword.arg == 'expected' for keyword in node.keywords) for node in plans))
            counts[leaf] = len(plans)
            if leaf == 'fields.py':
                root = next(node for node in tree.body if isinstance(node, ast.FunctionDef)
                            and node.name == 'apply_root_greeter')
                loads = [node for node in ast.walk(root) if isinstance(node, ast.Call)
                         and isinstance(node.func, ast.Name) and node.func.id == 'load_registry']
                self.assertEqual(len(loads), 1)
        self.assertEqual(counts, {'engine.py': 2, 'fields.py': 3, 'greeter.py': 1, 'wallpaper.py': 1})


if __name__ == '__main__':
    raise SystemExit(unittest.main())
