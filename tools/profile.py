#!/usr/bin/env python3
"""Create or delete registered host profiles for both Debian suite frontends.

With no arguments, choose an action. Creation asks for filesystem, family,
optional multiboot variants and a host name. Deletion selects exact registered
profiles and requires confirmation. Complete candidates are compiled as data
before publication; no installer code is run. --preview never writes files.
"""
from __future__ import annotations

import argparse
from contextlib import ExitStack
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from build import SourceCapture
from class_compiler import compile_classes, read_json, repository_data
from publication import (BuildOwnership, PublicationOutcomeUnknown, _Directory,
                         _atomic_write_at, _file_identity, _verify_file)

SUITES = ('forky', 'trixie')
NAME = re.compile(r'[a-z0-9]{1,5}\Z')
PROFILE_ID = re.compile(r'(?:btrfs|f2fs)-(?:de|srv)(?:-[a-z0-9]+)*\Z')


def validate_hostname(hostname: str) -> None:
    if not NAME.fullmatch(hostname):
        raise ValueError('host name must contain one to five lowercase ASCII letters/digits')
    if hostname in {'duo', 'trio'}:
        raise ValueError('duo and trio are reserved profile suffixes; choose another host name')


def prompt(label: str, choices: tuple[str, ...]) -> str:
    for _attempt in range(5):
        print(f'{label} ({"/".join(choices)}): ', end='', flush=True)
        line = sys.stdin.readline(128)
        if not line or len(line) == 128:
            raise ValueError('missing or overlong interactive input')
        value = line.strip().lower()
        if value in choices:
            return value
        print('Choose one of the listed values.', file=sys.stderr)
    raise ValueError('too many invalid answers')


def repo_paths(sources: dict[str, bytes], suite: str) -> dict[str, str]:
    schemas = re.findall(r"^  source_repo_supported='([^']+)'$",
                         sources['scripts/common/source.sh'].decode(), re.M)
    if len(schemas) != 1:
        raise ValueError('repository configuration has no unique supported vocabulary')
    names = schemas[0].split()
    if len(names) != len(set(names)) or any(name.startswith('FILE_') for name in names):
        raise ValueError('invalid repository configuration vocabulary')
    return repository_data(sources['repo.env'].decode(), suite, set(names))


def candidate(sources: dict[str, bytes], filesystem: str, family: str,
              variants: list[str], hostname: str) -> dict[str, bytes]:
    validate_hostname(hostname)
    suite_paths = {suite: repo_paths(sources, suite) for suite in SUITES}
    paths = suite_paths[SUITES[0]]
    # Registry/template leaf names are stable build interfaces. The shared
    # roots remain configurable; profile membership belongs to the registry.
    selection_path = paths['DIR_CATALOG'] + '/selection.json'
    selection = json.loads(sources[selection_path])
    changes: dict[str, bytes] = {}
    families = ('desktop', 'server') if family == 'both' else (family,)
    for selected_family in families:
        tag = 'de' if selected_family == 'desktop' else 'srv'
        parent = 'DIR_HOSTS_PROFILES_' + selected_family.upper()
        class_parent = 'DIR_CLASSES_PROFILE_' + selected_family.upper()
        for variant in variants:
            suffix = '' if variant == 'normal' else '-' + variant
            identifier = f'{filesystem}-{tag}-{hostname}{suffix}'
            if any(item['id'] == identifier for item in selection['profiles']):
                raise ValueError('registered profile already exists: ' + identifier)
            template_path = paths['DIR_HOSTS_PROFILES_TEMPLATES'] + '/' + filesystem + '-' + selected_family + suffix + '.env'
            template = sources[template_path].decode()
            # Identity is supplied by the existing installer account contract.
            # Template comments identify provenance without changing policy data.
            env = f'# Generated profile {identifier}; template {template_path}.\n' + template
            destination = paths[parent] + '/' + identifier + '.env'
            if destination in sources:
                raise ValueError('profile environment already exists: ' + destination)
            changes[destination] = env.encode()
            selection['profiles'].append({'id': identifier, 'family': selected_family,
                'filesystem': filesystem, 'mode': 'fresh' if variant == 'normal' else 'dualboot',
                'source': destination, 'identity_policy': 'explicit-profile-only'})
            for suite in SUITES:
                path = suite_paths[suite][class_parent] + '/' + identifier + '.cfg'
                if path in sources:
                    raise ValueError('profile class already exists: ' + path)
                text = f'# Explicit {selected_family} profile: {identifier}\n'
                if variant != 'normal':
                    text += 'd-i pkgsel/include string os-prober\n'
                changes[path] = text.encode()
    changes[selection_path] = (json.dumps(selection, indent=2) + '\n').encode()
    compile_classes({**sources, **changes})
    return changes


def deletion_candidate(sources: dict[str, bytes], identifiers: list[str]) -> dict[str, bytes | None]:
    """Remove only selected registrations and their exact physical members."""
    if (not identifiers or len(identifiers) > 256 or len(set(identifiers)) != len(identifiers)
            or any(len(value) > 96 or PROFILE_ID.fullmatch(value) is None for value in identifiers)):
        raise ValueError('select one or more distinct, exact registered profile IDs')
    paths = {suite: repo_paths(sources, suite) for suite in SUITES}
    selection_path = paths[SUITES[0]]['DIR_CATALOG'] + '/selection.json'
    selection = read_json(sources, selection_path)
    selected = set(identifiers)
    required = dependent_variants(selection, identifiers)
    if required:
        raise ValueError('delete the corresponding variants first or select them together: ' + ', '.join(required))
    changes: dict[str, bytes | None] = {}
    for identifier in identifiers:
        matches = [profile for profile in selection['profiles'] if profile['id'] == identifier]
        if len(matches) != 1:
            raise ValueError('profile is not uniquely registered: ' + identifier)
        profile = matches[0]
        family = profile['family']
        if family not in {'desktop', 'server'}:
            raise ValueError('invalid registered profile family: ' + identifier)
        tag = 'de' if family == 'desktop' else 'srv'
        if profile['filesystem'] not in {'btrfs', 'f2fs'} or not identifier.startswith(profile['filesystem'] + '-' + tag):
            raise ValueError('registered profile identity differs from its family/filesystem')
        host_parent = 'DIR_HOSTS_PROFILES_' + family.upper()
        class_parent = 'DIR_CLASSES_PROFILE_' + family.upper()
        environment = paths[SUITES[0]][host_parent] + '/' + identifier + '.env'
        if profile['source'] != environment:
            raise ValueError('profile environment is outside its exact owned destination')
        members = [environment] + [paths[suite][class_parent] + '/' + identifier + '.cfg' for suite in SUITES]
        for member in members:
            if member not in sources or member in changes:
                raise ValueError('missing or shared profile member: ' + member)
            changes[member] = None
    selection['profiles'] = [profile for profile in selection['profiles'] if profile['id'] not in selected]
    if any(profile['source'] in changes for profile in selection['profiles']):
        raise ValueError('a remaining profile shares the selected environment')
    # Fixed consumers now name exact members rather than global FILE aliases.
    # Reject a dangling physical-member reference before any source mutation.
    references = re.compile(rb'(?<![A-Za-z0-9_./-])(?:' + b'|'.join(
        re.escape(member.encode()) for member in sorted(changes)) + rb')(?![A-Za-z0-9_./-])')
    for member, data in sources.items():
        if member not in {'repo.env', selection_path} and member not in changes and references.search(data):
            raise ValueError('remaining source references a selected profile member: ' + member)
    changes[selection_path] = (json.dumps(selection, indent=2) + '\n').encode()
    compile_classes({**{member: data for member, data in sources.items() if member not in changes},
                     **{member: data for member, data in changes.items() if data is not None}})
    return changes


def dependent_variants(selection: dict, identifiers: list[str]) -> list[str]:
    registered = {profile['id'] for profile in selection['profiles']}
    selected = set(identifiers)
    return sorted({identifier + suffix for identifier in identifiers
                   if not identifier.endswith(('-duo', '-trio'))
                   for suffix in ('-duo', '-trio')
                   if identifier + suffix in registered and identifier + suffix not in selected})


def select_deletions(sources: dict[str, bytes]) -> list[str]:
    paths = repo_paths(sources, SUITES[0])
    profiles = sorted(profile['id'] for profile in read_json(sources, paths['DIR_CATALOG'] + '/selection.json')['profiles'])
    if not profiles:
        raise ValueError('there are no registered profiles to delete')
    print('Registered profiles (delete Duo/Trio variants before their normal profile):')
    for number, identifier in enumerate(profiles, 1):
        print(f'  {number:2d}) {identifier}')
    for _attempt in range(5):
        print('Profiles to delete (numbers or exact IDs, separated by spaces/commas): ', end='', flush=True)
        line = sys.stdin.readline(4096)
        if not line or len(line) == 4096:
            raise ValueError('missing or overlong profile selection')
        identifiers = []
        for value in re.split(r'[\s,]+', line.strip()):
            if value.isascii() and value.isdigit() and 1 <= int(value) <= len(profiles):
                value = profiles[int(value) - 1]
            if value not in profiles or value in identifiers:
                break
            identifiers.append(value)
        else:
            if identifiers:
                return identifiers
        print('Choose distinct listed numbers or exact IDs; wildcards are not accepted.', file=sys.stderr)
    raise ValueError('too many invalid profile selections')


def physical(member: str, paths: dict[str, str]) -> Path:
    if member.startswith(paths['DIR_FRONTENDS'] + '/'):
        relative = Path(paths['DIR_REPO_DI']) / member.removeprefix(paths['DIR_FRONTENDS'] + '/')
    else:
        relative = Path(paths['DIR_REPO_DEBIAN']) / member
    if relative.is_absolute() or any(part in {'', '.', '..'} for part in relative.parts):
        raise ValueError('profile destination escapes the repository')
    destination = ROOT / relative
    for parent in (destination.parent, *destination.parents):
        if parent == ROOT:
            break
        info = parent.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o022:
            raise ValueError('unsafe profile destination directory')
    return destination


@dataclass
class SourceEdit:
    member: str
    path: Path
    parent: _Directory
    before: bytes | None
    after: bytes | None
    mode: int
    identity: tuple[int, ...] | None
    published: tuple[int, ...] | None = None


def verify_edit(edit: SourceEdit, data: bytes | None, identity: tuple[int, ...] | None) -> None:
    edit.parent.verify()
    descriptor, name = edit.parent.descriptor, edit.path.name
    if (data is None and identity is not None) or _file_identity(descriptor, name) != identity:
        raise ValueError('profile source identity changed: ' + edit.member)
    if data is not None:
        _verify_file(descriptor, name, data, edit.mode)
        if _file_identity(descriptor, name) != identity:
            raise ValueError('profile source changed during verification: ' + edit.member)


def source_write(edit: SourceEdit, data: bytes | None) -> tuple[int, ...] | None:
    """Publish an approved authored edit using the shared descriptor primitives.

    The generic artifact API deliberately rejects .env inputs. This writer is
    confined to the complete profile candidate; its durable recovery copies
    exist before any authored input is replaced or removed.
    """
    edit.parent.verify()
    mutated = False
    try:
        if data is None:
            os.unlink(edit.path.name, dir_fd=edit.parent.descriptor)
            mutated = True
            os.fsync(edit.parent.descriptor)
        elif edit.identity is None:
            # New profile members must never replace a concurrent creator.
            descriptor = os.open(edit.path.name, os.O_WRONLY | os.O_CREAT | os.O_EXCL
                                 | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600, dir_fd=edit.parent.descriptor)
            mutated = True
            try:
                stream = os.fdopen(descriptor, 'wb')
            except BaseException:
                os.close(descriptor)
                raise
            with stream:
                stream.write(data)
                os.fchmod(stream.fileno(), edit.mode)
                stream.flush()
                os.fsync(stream.fileno())
            os.fsync(edit.parent.descriptor)
        else:
            _atomic_write_at(edit.parent.descriptor, edit.path.name, data, edit.mode)
            mutated = True
        result = _file_identity(edit.parent.descriptor, edit.path.name)
        verify_edit(edit, data, result)
        return result
    except BaseException as error:
        if mutated or not isinstance(error, (OSError, ValueError)):
            raise PublicationOutcomeUnknown('profile publication postcondition is uncertain: ' + edit.member) from error
        raise


class Recovery:
    """Private, durable copies; retained if publication or rollback is uncertain."""

    def __init__(self, edits: list[SourceEdit], paths: dict[str, str]):
        relative = Path(paths['DIR_REPO_BUILD_STATE'])
        if relative.is_absolute() or not relative.parts or any(part in {'.', '..'} for part in relative.parts):
            raise ValueError('unsafe profile recovery root')
        name = 'profile-' + os.urandom(16).hex()
        self.path = ROOT / relative / name
        self.files: dict[str, tuple[bytes, tuple[int, ...]]] = {}
        try:
            with _Directory(self.path.parent, create=True) as parent:
                parent.verify()
                os.mkdir(name, 0o700, dir_fd=parent.descriptor)
                os.fsync(parent.descriptor)
            with _Directory(self.path) as recovery:
                self.identity = os.fstat(recovery.descriptor)
                records = []
                for number, edit in enumerate(edits):
                    backup = str(number) + '.before' if edit.before is not None else None
                    if backup is not None:
                        self.write(recovery.descriptor, backup, edit.before)
                    records.append({'path': str(edit.path.relative_to(ROOT)), 'backup': backup, 'mode': edit.mode,
                                    'before_sha256': hashlib.sha256(edit.before).hexdigest() if edit.before is not None else None,
                                    'after_sha256': hashlib.sha256(edit.after).hexdigest() if edit.after is not None else None})
                self.write(recovery.descriptor, 'manifest.json', (json.dumps({'format': 1, 'edits': records}, indent=2) + '\n').encode())
                os.fsync(recovery.descriptor)
        except BaseException as error:
            raise PublicationOutcomeUnknown('profile recovery preparation failed; retain ' + str(self.path)) from error

    def write(self, parent: int, name: str, data: bytes) -> None:
        descriptor = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600, dir_fd=parent)
        try:
            stream = os.fdopen(descriptor, 'wb')
        except BaseException:
            os.close(descriptor)
            raise
        with stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        identity = _file_identity(parent, name, 0o600)
        _verify_file(parent, name, data, 0o600)
        self.files[name] = (data, identity)

    def remove(self) -> None:
        with _Directory(self.path) as recovery, _Directory(self.path.parent) as parent:
            current = os.fstat(recovery.descriptor)
            if (current.st_dev, current.st_ino) != (self.identity.st_dev, self.identity.st_ino):
                raise ValueError('profile recovery directory was replaced')
            for name, (data, identity) in self.files.items():
                _verify_file(recovery.descriptor, name, data, 0o600)
                if _file_identity(recovery.descriptor, name, 0o600) != identity:
                    raise ValueError('profile recovery member was replaced')
                os.unlink(name, dir_fd=recovery.descriptor)
            os.fsync(recovery.descriptor)
            recovery.verify()
            parent.verify()
            os.rmdir(self.path.name, dir_fd=parent.descriptor)
            os.fsync(parent.descriptor)


def ordered_members(changes: dict[str, bytes | None], paths: dict[str, str]) -> list[str]:
    return sorted(changes, key=lambda name: (
        name == paths['DIR_CATALOG'] + '/selection.json',
        not Path(name).stem.endswith(('-duo', '-trio')), name))


def publish(changes: dict[str, bytes | None], sources: dict[str, bytes], paths: dict[str, str],
            capture: SourceCapture) -> None:
    completed: list[SourceEdit] = []
    with ExitStack() as stack:
        parents: dict[Path, _Directory] = {}
        edits = []
        # Registry publication follows the exact owned file edits.
        for member in ordered_members(changes, paths):
            path = physical(member, paths)
            if path.parent not in parents:
                parents[path.parent] = stack.enter_context(_Directory(path.parent))
            parent = parents[path.parent]
            identity = _file_identity(parent.descriptor, path.name)
            before = sources.get(member)
            mode = identity[2] & 0o777 if identity is not None else 0o644
            edit = SourceEdit(member, path, parent, before, changes[member], mode, identity)
            if (before is None) != (identity is None):
                raise ValueError('source membership changed before profile publication: ' + member)
            verify_edit(edit, before, identity)
            edits.append(edit)
        capture.verify()
        recovery = Recovery(edits, paths)
        try:
            capture.verify()
            for edit in edits:
                verify_edit(edit, edit.before, edit.identity)
                edit.published = source_write(edit, edit.after)
                completed.append(edit)
            for edit in edits:
                verify_edit(edit, edit.after, edit.published)
        except BaseException as error:
            if isinstance(error, PublicationOutcomeUnknown) or not isinstance(error, (OSError, ValueError)):
                raise PublicationOutcomeUnknown('profile publication is uncertain; retain ' + str(recovery.path)) from error
            failed = False
            for edit in reversed(completed):
                try:
                    verify_edit(edit, edit.after, edit.published)
                    restored = source_write(edit, edit.before)
                    verify_edit(edit, edit.before, restored)
                except BaseException as rollback_error:
                    failed = True
                    if not isinstance(rollback_error, (OSError, ValueError)):
                        break
            if failed:
                raise PublicationOutcomeUnknown('profile rollback could not be proved; retain ' + str(recovery.path)) from error
            try:
                recovery.remove()
            except BaseException as cleanup_error:
                raise PublicationOutcomeUnknown('profile rollback completed; recovery cleanup uncertain; retain ' + str(recovery.path)) from cleanup_error
            raise
        try:
            recovery.remove()
        except BaseException as error:
            raise PublicationOutcomeUnknown('profile edits completed; recovery cleanup uncertain; retain ' + str(recovery.path)) from error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--action', choices=('create', 'delete'), help='choose interactively when no action-specific options are given')
    parser.add_argument('--filesystem', choices=('f2fs', 'btrfs'))
    parser.add_argument('--family', choices=('desktop', 'server', 'both'))
    parser.add_argument('--multiboot', choices=('none', 'duo', 'trio', 'both'))
    parser.add_argument('--name', help='one to five lowercase ASCII letters or digits')
    parser.add_argument('--profile', action='append', default=[], metavar='ID', help='exact registered profile to delete; repeat to select several')
    parser.add_argument('--with-variants', action='store_true', help='also delete existing Duo/Trio variants of each selected normal profile, before deleting the normal profile')
    parser.add_argument('--yes', action='store_true', help='confirm deletion of the explicitly selected profiles')
    parser.add_argument('--preview', action='store_true', help='validate the complete candidate and list paths without writing')
    args = parser.parse_args()
    create_options = any(value is not None for value in (args.filesystem, args.family, args.multiboot, args.name))
    if args.profile and (create_options or args.action == 'create'):
        parser.error('--profile cannot be combined with creation options')
    if args.action == 'delete' and create_options:
        parser.error('deletion does not accept --filesystem, --family, --multiboot or --name; select exact --profile IDs')
    if (args.yes or args.with_variants) and (args.action == 'create' or create_options):
        parser.error('--yes and --with-variants apply only to profile deletion')
    try:
        action = args.action or ('delete' if args.profile else 'create' if create_options else prompt('Profile action', ('create', 'delete')))
        if (args.yes or args.with_variants) and action != 'delete':
            parser.error('--yes and --with-variants apply only to profile deletion')
        if action == 'create':
            filesystem = args.filesystem or prompt('Root filesystem', ('f2fs', 'btrfs'))
            family = args.family or prompt('Profile family', ('desktop', 'server', 'both'))
            multiboot = args.multiboot or prompt('Additional multiboot profiles', ('none', 'duo', 'trio', 'both'))
            hostname = args.name
            if hostname is None:
                print('Host name (1-5 lowercase letters/digits): ', end='', flush=True)
                line = sys.stdin.readline(128)
                if not line or len(line) == 128:
                    raise ValueError('missing or overlong host name')
                hostname = line.strip()
            validate_hostname(hostname)
            variants = ['normal'] + (['duo', 'trio'] if multiboot == 'both' else [] if multiboot == 'none' else [multiboot])
        with BuildOwnership(ROOT), SourceCapture(ROOT) as capture:
            sources, _compiler = capture.read()
            if action == 'delete':
                identifiers = args.profile or select_deletions(sources)
                paths = repo_paths(sources, SUITES[0])
                selection = read_json(sources, paths['DIR_CATALOG'] + '/selection.json')
                required = dependent_variants(selection, identifiers)
                if required:
                    print('Corresponding variants must be deleted first: ' + ', '.join(required))
                    if not args.with_variants:
                        if args.profile and (args.preview or args.yes):
                            raise ValueError('normal profile is protected; explicitly select its variants or use --with-variants')
                        if prompt('Include and delete these variants first', ('no', 'yes')) != 'yes':
                            print('Profile deletion cancelled; no files were changed.')
                            return 0
                    identifiers = identifiers + required
                identifiers = sorted(identifiers, key=lambda name: (not name.endswith(('-duo', '-trio')), name))
                changes = deletion_candidate(sources, identifiers)
                print('Selected for deletion: ' + ', '.join(identifiers))
            else:
                changes = candidate(sources, filesystem, family, variants, hostname)
            paths = repo_paths(sources, SUITES[0])
            capture.verify()
            for member in ordered_members(changes, paths):
                verb = 'delete' if changes[member] is None else 'update' if member in sources else 'create'
                print(f'{verb}: {physical(member, paths).relative_to(ROOT)}')
            if args.preview:
                print('Profile candidate validated; preview wrote no files.')
                return 0
            if action == 'delete' and not args.yes:
                print('Type delete to remove exactly these profiles; any other answer cancels: ', end='', flush=True)
                line = sys.stdin.readline(128)
                if len(line) == 128 or line.strip() != 'delete':
                    print('Profile deletion cancelled; no files were changed.')
                    return 0
            publish(changes, sources, paths, capture)
        if action == 'delete':
            print(f'Deleted {len(identifiers)} registered profiles from both suites. Run make build to refresh the served products.')
        else:
            print(f'Created {len(variants) * (2 if family == "both" else 1)} registered profiles for both suites.')
            print('Review disk selectors and hardware policy in the new environments, then run make build.')
        return 0
    except (OSError, ValueError, KeyError) as error:
        print('profile operation failed: ' + str(error), file=sys.stderr)
        return 75 if isinstance(error, PublicationOutcomeUnknown) else 1
    except KeyboardInterrupt:
        print('Profile operation cancelled.', file=sys.stderr)
        return 130


if __name__ == '__main__':
    raise SystemExit(main())
