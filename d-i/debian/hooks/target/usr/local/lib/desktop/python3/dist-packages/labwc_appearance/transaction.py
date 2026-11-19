"""Durable appearance journals with bounded, allowlisted rollback records."""
from __future__ import annotations
import base64
import re
from managed_workflows.fs import Tree

MAX_IMAGE_BYTES = 2 * 1024**2
# Base64 and JSON framing stay below Tree's 8 MiB recovery read limit, even
# after the coordinator adds its small settings and service metadata.
MAX_TOTAL_IMAGE_BYTES = 4 * 1024**2


def encoded(value: bytes | None) -> str | None:
    return None if value is None else base64.b64encode(value).decode('ascii')


def decoded(value: str | None) -> bytes | None:
    if value is None:
        return None
    if not isinstance(value, str) or len(value) > 4 * ((MAX_IMAGE_BYTES + 2) // 3):
        raise ValueError('invalid transaction file image')
    raw = base64.b64decode(value, validate=True)
    if len(raw) > MAX_IMAGE_BYTES:
        raise ValueError('transaction file image exceeds the size limit')
    return raw


def plan(tree: Tree, updates: dict[str, bytes | None], token: str, *,
         expected: dict[str, bytes | None] | None = None) -> dict:
    """Capture rollback images, checking the bytes used to prepare candidates.

    Renderers pass their operation-local input snapshots. The fresh read here
    must still agree with those snapshots; it must never silently adopt an
    intervening writer's bytes as the baseline for an older candidate.
    """
    if expected is not None and set(expected) != set(updates):
        raise ValueError('appearance preparation does not cover every candidate')
    old, new = {}, {}
    size = 0
    for name, data in updates.items():
        if data is not None and (not isinstance(data, bytes) or len(data) > MAX_IMAGE_BYTES):
            raise ValueError('appearance candidate exceeds the file size limit')
        if expected is not None and expected[name] is not None and not isinstance(expected[name], bytes):
            raise ValueError('invalid appearance preparation image')
        before = tree.read(name, limit=MAX_IMAGE_BYTES, missing=True)
        if expected is not None and before != expected[name]:
            raise RuntimeError('appearance file changed during preparation: ' + name)
        if before != data:
            size += len(before or b'') + len(data or b'')
            if size > MAX_TOTAL_IMAGE_BYTES:
                raise ValueError('appearance recovery images exceed the aggregate size limit')
            old[name], new[name] = encoded(before), encoded(data)
    return {'schema': 1, 'token': token, 'phase': 'prepared', 'old': old, 'new': new}


def validate(value, allowed: set[str]) -> dict:
    if (not isinstance(value, dict) or value.get('schema') != 1 or
            not re.fullmatch(r'[0-9a-f]{32}', str(value.get('token'))) or
            value.get('phase') not in ('prepared', 'committed')):
        raise ValueError('invalid appearance transaction journal')
    old, new = value.get('old'), value.get('new')
    if not isinstance(old, dict) or not isinstance(new, dict) or set(old) != set(new) or set(old) - allowed:
        raise ValueError('appearance transaction contains an unauthorized path')
    size = 0
    for images in (old, new):
        for data in images.values():
            raw = decoded(data)
            size += len(raw or b'')
            if size > MAX_TOTAL_IMAGE_BYTES:
                raise ValueError('appearance recovery images exceed the aggregate size limit')
    return value


def check_current(tree: Tree, journal: dict, *, rollback: bool) -> None:
    for name in journal['new']:
        current = tree.read(name, missing=True)
        acceptable = (decoded(journal['new'][name]), decoded(journal['old'][name])) if rollback else (decoded(journal['old'][name]),)
        if current not in acceptable:
            raise RuntimeError('appearance file changed concurrently; journal retained: ' + name)


def check_committed(tree: Tree, journal: dict) -> None:
    """Prove a committed journal's new images are present before clearing it."""
    for name in journal['new']:
        if tree.read(name, missing=True) != decoded(journal['new'][name]):
            raise RuntimeError('committed appearance journal does not match the file: ' + name)


def apply(tree: Tree, journal: dict, *, mode: int = 0o600) -> None:
    check_current(tree, journal, rollback=False)
    for name, data in journal['new'].items():
        tree.write(name, decoded(data), mode=mode)


def rollback(tree: Tree, journal: dict, *, mode: int = 0o600) -> None:
    check_current(tree, journal, rollback=True)
    for name, data in reversed(list(journal['old'].items())):
        raw = decoded(data)
        if tree.read(name, missing=True) != raw:
            tree.write(name, raw, mode=mode)
