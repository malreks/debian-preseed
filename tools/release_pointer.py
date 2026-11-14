#!/usr/bin/env python3
"""Manual complete-tree activation/rollback; preview unless --apply is supplied.

Never called by builds, installers, tests or CI. This operator tool is not run
as part of repository implementation or static validation.
"""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from publication import PublicationOutcomeUnknown, atomic_write, publish_immutable_tree
IDENTITY = re.compile(r'[0-9a-f]{64}\Z')
TRANSACTION = re.compile(r'[0-9]{8}T[0-9]{6}Z-[0-9a-f]{16}\.json\Z')


def trusted_directory(path: Path) -> None:
    if not path.is_absolute() or '..' in path.parts:
        raise ValueError('operator destinations require canonical absolute paths')
    for parent in reversed((path, *path.parents)):
        info = parent.lstat()
        if (not stat.S_ISDIR(info.st_mode) or info.st_uid not in (0, os.geteuid())
                or info.st_mode & 0o022):
            raise ValueError('untrusted operator destination ancestry')


def read(path: Path, maximum: int = 67108864) -> bytes:
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    with os.fdopen(fd, 'rb') as stream:
        info = os.fstat(stream.fileno())
        if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1
                or info.st_uid not in (0, os.geteuid()) or info.st_mode & 0o022
                or info.st_size > maximum):
            raise ValueError('untrusted publication file')
        data = stream.read(maximum + 1)
        if len(data) != info.st_size or len(data) > maximum:
            raise ValueError('publication changed during capture')
        return data


def selected_release(files: dict[str, bytes]) -> str:
    selected = set()
    for suite in ('forky', 'trixie'):
        found = set(re.findall(rb'INSTALLER_RELEASE_ID=([0-9a-f]{64})', files['d-i/' + suite + '/preseed.cfg']))
        if len(found) != 1:
            raise ValueError('frontend does not select one release')
        selected.update(found)
    if len(selected) != 1:
        raise ValueError('frontends select different releases')
    return selected.pop().decode()


def validate_files(files: dict[str, bytes], release: str | None = None) -> None:
    active = selected_release(files)
    if release is not None and active != release:
        raise ValueError('requested source identity differs from the flat suite products')
    product_names = {'source.sh', 'payload.tar.gz', 'payload.manifest', 'support-matrix.json'}
    receipts = []
    expected = set()
    for suite in ('forky', 'trixie'):
        prefix = 'd-i/' + suite + '/'
        receipt = json.loads(files[prefix + 'receipt.json'])
        if (receipt.get('format') != 1 or receipt.get('release') != active
                or receipt.get('suites') != ['forky', 'trixie']
                or set(receipt['products']) != product_names):
            raise ValueError('flat suite receipt identity or product vocabulary differs')
        receipts.append(receipt)
        expected.add(prefix + 'receipt.json')
        for name, digest in receipt['products'].items():
            expected.add(prefix + name)
            if hashlib.sha256(files[prefix + name]).hexdigest() != digest:
                raise ValueError('suite product differs from its receipt')
        preseed = files[prefix + 'preseed.cfg']
        if b'INSTALLER_SUITE=' + suite.encode() not in preseed:
            raise ValueError('frontend suite binding differs')
        for name in ('source.sh', 'payload.manifest', 'payload.tar.gz'):
            if receipt['products'][name].encode() not in preseed:
                raise ValueError('trusted preseed lacks a product pin')
    if receipts[0] != receipts[1]:
        raise ValueError('suite receipts differ')
    for name, digest in receipts[0]['frontends'].items():
        if (name.split('/')[0] not in ('forky', 'trixie')
                or any(part in ('', '.', '..') for part in name.split('/'))):
            raise ValueError('invalid frontend member')
        expected.add('d-i/' + name)
        if hashlib.sha256(files['d-i/' + name]).hexdigest() != digest:
            raise ValueError('frontend differs from the complete source receipt')
    if 'publication.json' in files:
        publication = json.loads(files['publication.json'])
        hashes = {name: hashlib.sha256(data).hexdigest() for name, data in sorted(files.items()) if name != 'publication.json'}
        identity = hashlib.sha256(''.join(digest + '  ' + name + '\n' for name, digest in hashes.items()).encode()).hexdigest()
        if publication != {'format': 1, 'tree_identity': identity, 'selected_release': active, 'members': hashes}:
            raise ValueError('served tree identity differs from its complete member set')
        expected.add('publication.json')
    if expected != set(files):
        raise ValueError('complete-tree member set differs')


def capture(directory: Path, release: str | None = None) -> dict[str, bytes]:
    trusted_directory(directory)
    files, total = {}, 0
    for current, directories, leaves in os.walk(directory, followlinks=False):
        for name in directories:
            trusted_directory(Path(current) / name)
        for name in leaves:
            path = Path(current) / name
            key = path.relative_to(directory).as_posix()
            if any(part in ('', '.', '..') for part in key.split('/')):
                raise ValueError('invalid publication member')
            files[key] = read(path)
            total += len(files[key])
            if len(files) > 10000 or total > 268435456:
                raise ValueError('publication exceeds capture bounds')
    validate_files(files, release)
    if 'publication.json' in files:
        if json.loads(files['publication.json'])['tree_identity'] != directory.name:
            raise ValueError('served directory differs from its content identity')
    return files


def capture_checkout(release: str) -> dict[str, bytes]:
    # The build owns only the flat suite products. Capture the receipt's exact
    # frontend set, never walk the checkout or collect private/unrelated files.
    files = {}
    for suite in ('forky', 'trixie'):
        prefix = 'd-i/' + suite + '/'
        trusted_directory(ROOT / 'd-i' / suite)
        files[prefix + 'receipt.json'] = read(ROOT / prefix / 'receipt.json')
    receipt = json.loads(files['d-i/forky/receipt.json'])
    names = {'d-i/' + name for name in receipt['frontends']}
    for suite in ('forky', 'trixie'):
        names.update('d-i/' + suite + '/' + name for name in receipt['products'])
    if len(names) > 10000:
        raise ValueError('frontend receipt exceeds member bound')
    total = sum(map(len, files.values()))
    for name in sorted(names):
        if (re.fullmatch(r'd-i/(?:forky|trixie)/[A-Za-z0-9_./@+-]+', name) is None
                or any(part in ('', '.', '..') for part in name.split('/'))):
            raise ValueError('noncanonical frontend member')
        path = ROOT / name
        trusted_directory(path.parent)
        files[name] = read(path)
        total += len(files[name])
        if total > 268435456:
            raise ValueError('complete frontend set exceeds byte bound')
    validate_files(files, release)
    return files


def compose_publication(files: dict[str, bytes]) -> tuple[str, dict[str, bytes]]:
    # Rollback retains complete external served trees. Flat suite URLs do not
    # merge files from different builds, and make build creates no tree store.
    files = {name: data for name, data in files.items() if name != 'publication.json'}
    validate_files(files)
    hashes = {name: hashlib.sha256(data).hexdigest() for name, data in sorted(files.items())}
    identity = hashlib.sha256(''.join(digest + '  ' + name + '\n' for name, digest in hashes.items()).encode()).hexdigest()
    files['publication.json'] = (json.dumps({'format': 1, 'tree_identity': identity,
        'selected_release': selected_release(files), 'members': hashes}, sort_keys=True, indent=2) + '\n').encode()
    return identity, files


def pointer(parent: Path) -> str | None:
    path = parent / 'current'
    if not path.exists() and not path.is_symlink():
        return None
    info = path.lstat()
    if not stat.S_ISLNK(info.st_mode) or info.st_uid != os.geteuid():
        raise ValueError('served pointer has a different owner or type')
    target = os.readlink(path)
    fields = target.split('/')
    if len(fields) != 2 or fields[0] != 'trees' or IDENTITY.fullmatch(fields[1]) is None:
        raise ValueError('served pointer escapes its validated release map')
    files = capture(parent / target)
    if 'publication.json' not in files:
        raise ValueError('served pointer must select a complete versioned tree')
    return fields[1]


def sync(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def journal(path: Path, value: dict) -> None:
    atomic_write(path, (json.dumps(value, sort_keys=True, indent=2) + '\n').encode(), 0o600)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('activate', 'rollback', 'reconcile'))
    parser.add_argument('served_parent', type=Path, help='existing trusted directory; HTTP document root is its current child')
    parser.add_argument('identity', help='source release SHA-256 for activate, retained tree SHA-256 for rollback, journal filename for reconcile')
    parser.add_argument('--apply', action='store_true', help='explicit operator action; default only previews')
    args = parser.parse_args()
    try:
        parent = args.served_parent
        trusted_directory(parent)
        previous = pointer(parent)
        if args.operation == 'reconcile':
            if TRANSACTION.fullmatch(args.identity) is None:
                raise ValueError('invalid retained transaction name')
            path = parent / 'transactions' / args.identity
            trusted_directory(path.parent)
            recovery_bytes = read(path, 16384)
            record = json.loads(recovery_bytes)
            if (not isinstance(record, dict) or record.get('format') != 1
                    or record.get('operation') not in ('activate', 'rollback')
                    or IDENTITY.fullmatch(str(record.get('selected', ''))) is None
                    or IDENTITY.fullmatch(str(record.get('selected_release', ''))) is None
                    or (record.get('previous') is not None and IDENTITY.fullmatch(str(record['previous'])) is None)
                    or record.get('state') not in ('prepared', 'outcome-unknown')
                    or previous not in (record.get('previous'), record.get('selected'))):
                raise ValueError('transaction cannot be reconciled from the verified current pointer')
            print('reconcile pointer=' + str(previous) + ' journal=' + args.identity)
            if not args.apply:
                return 0
        else:
            if IDENTITY.fullmatch(args.identity) is None:
                raise ValueError('invalid release identity')
            files = (capture_checkout(args.identity) if args.operation == 'activate'
                     else capture(parent / 'trees' / args.identity))
            tree_id, files = compose_publication(files)
            active_release = selected_release(files)
            print(f'{args.operation}: previous_tree={previous} selected_tree={tree_id} selected_release={active_release}; complete tree members={len(files)}')
            if not args.apply:
                print('preview only; no files or served pointer changed')
                return 0
        fd = os.open(parent / 'publication.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
        try:
            info = os.fstat(fd)
            if info.st_uid != os.geteuid() or info.st_nlink != 1 or not stat.S_ISREG(info.st_mode) or info.st_mode & 0o077:
                raise ValueError('unsafe publication ownership lock')
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            if pointer(parent) != previous:
                raise ValueError('served pointer changed before acquiring ownership')
            if args.operation == 'reconcile':
                if read(path, 16384) != recovery_bytes:
                    raise ValueError('recovery journal changed before acquiring ownership')
                record['state'] = 'committed' if previous == record['selected'] else 'aborted; previous pointer retained'
                journal(path, record)
                return 0
            tree_id, files = compose_publication(files)
            transactions = parent / 'transactions'
            transactions.mkdir(mode=0o700, exist_ok=True)
            trusted_directory(transactions)
            for index, item in enumerate(transactions.iterdir()):
                if index >= 10000 or TRANSACTION.fullmatch(item.name) is None:
                    raise ValueError('unrecognized or excessive recovery evidence')
                if json.loads(read(item, 16384)).get('state') in ('prepared', 'outcome-unknown'):
                    raise ValueError('reconcile retained publication evidence before another mutation')
            destination = parent / 'trees' / tree_id
            publish_immutable_tree(destination, files)
            capture(destination, active_release)
            name = time.strftime('%Y%m%dT%H%M%SZ', time.gmtime()) + '-' + os.urandom(8).hex() + '.json'
            path = transactions / name
            record = {'format': 1, 'state': 'prepared', 'operation': args.operation,
                      'previous': previous, 'selected': tree_id, 'selected_release': active_release,
                      'receipt_sha256': hashlib.sha256(files['d-i/forky/receipt.json']).hexdigest()}
            journal(path, record)
            temporary = parent / ('.current-' + os.urandom(8).hex())
            temporary.symlink_to('trees/' + tree_id)
            try:
                os.replace(temporary, parent / 'current')
                sync(parent)
                if pointer(parent) != tree_id:
                    raise ValueError('served pointer postcondition differs')
                record['state'] = 'committed'
                journal(path, record)
            except BaseException as error:
                record['state'] = 'outcome-unknown'
                try:
                    journal(path, record)
                except (OSError, ValueError) as journal_error:
                    error.add_note('recovery journal update also failed: ' + str(journal_error))
                print('retained recovery journal: ' + str(path), file=sys.stderr)
                raise PublicationOutcomeUnknown('served pointer transaction needs explicit reconciliation') from error
            print('complete pointer switched; previous complete trees and rollback journal retained')
            return 0
        finally:
            os.close(fd)
    except PublicationOutcomeUnknown as error:
        print('publication outcome unknown; retain evidence and do not retry automatically: ' + str(error), file=sys.stderr)
        for detail in getattr(error, '__notes__', ()):
            print(detail, file=sys.stderr)
        return 75
    except (OSError, ValueError, KeyError) as error:
        print('publication refused: ' + str(error), file=sys.stderr)
        for detail in getattr(error, '__notes__', ()):
            print(detail, file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
