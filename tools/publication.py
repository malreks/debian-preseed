"""Descriptor-relative publication of build-owned files and immutable trees.

Only local serialization is performed here. Environment files remain authored
inputs. Serving-pointer changes belong to the separate, manual operator tool.
"""
from __future__ import annotations

import fcntl
import os
from pathlib import Path
import re
import stat

MEMBER_LIMIT = 10000
ENTRY_LIMIT = 20000
BYTE_LIMIT = 256 * 1024 * 1024
FILE_LIMIT = 64 * 1024 * 1024
PATH_LIMIT = 512
DEPTH_LIMIT = 64
SAFE_NAME = re.compile(r'[A-Za-z0-9_.@+-]+\Z')


class PublicationOutcomeUnknown(ValueError):
    """A rename occurred, but its durable postcondition could not be proved."""


def _identity(info: os.stat_result) -> tuple[int, ...]:
    return (info.st_dev, info.st_ino, info.st_mode, info.st_nlink, info.st_uid,
            info.st_gid, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def _directory_identity(info: os.stat_result) -> tuple[int, ...]:
    return (info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_gid)


def _owned_directory(descriptor: int, mode: int | None = None) -> None:
    info = os.fstat(descriptor)
    if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid()
            or info.st_mode & 0o022
            or mode is not None and stat.S_IMODE(info.st_mode) != mode):
        raise ValueError('publication directory ownership or mode differs')


def _child_directory(parent: int, name: str, *, create: bool = False) -> int:
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    created = False
    try:
        descriptor = os.open(name, flags, dir_fd=parent)
    except FileNotFoundError:
        if not create:
            raise
        _owned_directory(parent)
        try:
            os.mkdir(name, 0o700, dir_fd=parent)
            created = True
        except FileExistsError:
            pass  # A cooperating creator may have won; open without following.
        descriptor = os.open(name, flags, dir_fd=parent)
    try:
        if created:
            _owned_directory(descriptor)
            os.fchmod(descriptor, 0o755)
            os.fsync(descriptor)
            os.fsync(parent)
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def _descend(descriptor: int, parts: tuple[str, ...], *, create: bool = False) -> int:
    current = os.dup(descriptor)
    try:
        for part in parts:
            child = _child_directory(current, part, create=create)
            os.close(current)
            current = child
        return current
    except BaseException:
        os.close(current)
        raise


class _Directory:
    """Pin the destination ancestry without following any pathname symlink."""

    def __init__(self, path: Path, *, create: bool = False):
        if (not path.is_absolute() or path.anchor != '/' or '..' in path.parts
                or len(path.parts) > 256):
            raise ValueError('publication requires canonical absolute ancestry')
        self.path, self.create, self.descriptor = path, create, -1

    def _open(self, *, create: bool = False) -> int:
        root = os.open('/', os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
        try:
            return _descend(root, self.path.parts[1:], create=create)
        finally:
            os.close(root)

    def __enter__(self) -> _Directory:
        if not hasattr(os, 'O_PATH'):
            raise ValueError('publication requires Linux pinned file identities')
        self.descriptor = self._open(create=self.create)
        try:
            _owned_directory(self.descriptor)
            self.identity = _directory_identity(os.fstat(self.descriptor))
            return self
        except BaseException:
            os.close(self.descriptor)
            self.descriptor = -1
            raise

    def verify(self) -> None:
        descriptor = self._open()
        try:
            if _directory_identity(os.fstat(descriptor)) != self.identity:
                raise ValueError('publication ancestry changed; retain owned evidence')
        finally:
            os.close(descriptor)

    def __exit__(self, *_error) -> None:
        os.close(self.descriptor)
        self.descriptor = -1


class BuildOwnership:
    """Hold the existing suite parent inode; create no lock file or directory."""

    def __init__(self, path: Path):
        self.parent = _Directory(path)

    def __enter__(self) -> BuildOwnership:
        self.parent.__enter__()
        try:
            fcntl.flock(self.parent.descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.parent.verify()
            return self
        except BaseException:
            self.parent.__exit__()
            raise

    def __exit__(self, error_type, error, traceback) -> None:
        try:
            if error is None:
                try:
                    self.parent.verify()
                except (OSError, ValueError) as failure:
                    raise PublicationOutcomeUnknown('suite parent changed after generation; retain all products') from failure
        finally:
            self.parent.__exit__()


def _file_identity(parent: int, name: str, mode: int | None = None) -> tuple[int, ...] | None:
    try:
        descriptor = os.open(name, os.O_PATH | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=parent)
    except FileNotFoundError:
        return None
    try:
        info = os.fstat(descriptor)
        if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1
                or info.st_uid != os.geteuid()
                or mode is not None and stat.S_IMODE(info.st_mode) != mode):
            raise ValueError('publication member must be an owned single-link regular file')
        return _identity(info)
    finally:
        os.close(descriptor)


def _verify_file(parent: int, name: str, data: bytes, mode: int) -> None:
    pinned = os.open(name, os.O_PATH | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=parent)
    try:
        info = os.fstat(pinned)
        if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1
                or info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != mode
                or info.st_size != len(data)):
            raise ValueError('publication member identity, mode or size differs')
        identity = _identity(info)
        # Linux's own descriptor link promotes this checked regular inode;
        # the source/member pathname is never reopened for its content.
        readable = os.open(f'/proc/self/fd/{pinned}', os.O_RDONLY | os.O_CLOEXEC)
        try:
            stream = os.fdopen(readable, 'rb')
        except BaseException:
            os.close(readable)
            raise
        with stream:
            if (_identity(os.fstat(stream.fileno())) != identity
                    or stream.read(len(data) + 1) != data
                    or _identity(os.fstat(stream.fileno())) != identity):
                raise ValueError('publication member bytes changed during inspection')
        if _file_identity(parent, name, mode) != identity:
            raise ValueError('publication member replaced during inspection')
    finally:
        os.close(pinned)


def _atomic_write_at(parent: int, name: str, data: bytes, mode: int) -> None:
    previous = _file_identity(parent, name)
    temporary = '.' + name + '.staged-' + os.urandom(16).hex()
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL
                         | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600, dir_fd=parent)
    try:
        temporary_identity = os.fstat(descriptor)
    except BaseException:
        os.close(descriptor)
        raise
    replaced = False
    failure = None
    try:
        try:
            stream = os.fdopen(descriptor, 'wb')
        except BaseException:
            os.close(descriptor)
            raise
        with stream:
            stream.write(data)
            os.fchmod(stream.fileno(), mode)
            stream.flush()
            os.fsync(stream.fileno())
        _verify_file(parent, temporary, data, mode)
        if _file_identity(parent, name) != previous:
            raise ValueError('artifact destination changed before replacement')
        os.replace(temporary, name, src_dir_fd=parent, dst_dir_fd=parent)
        replaced = True
        os.fsync(parent)
        _verify_file(parent, name, data, mode)
    except BaseException as error:
        failure = error
        if replaced and isinstance(error, (OSError, ValueError)):
            failure = PublicationOutcomeUnknown('artifact renamed; durable postcondition unknown: ' + name)
            raise failure from error
        raise
    finally:
        # Only this exact private inode may be removed; retain a replacement.
        try:
            current = os.stat(temporary, dir_fd=parent, follow_symlinks=False)
            if (current.st_dev, current.st_ino) == (temporary_identity.st_dev, temporary_identity.st_ino):
                os.unlink(temporary, dir_fd=parent)
        except FileNotFoundError:
            pass
        except OSError as cleanup_error:
            if failure is None:
                raise
            failure.add_note('private temporary cleanup also failed: ' + str(cleanup_error))


def atomic_write(path: Path, data: bytes, mode: int) -> None:
    """Replace one owned artifact, binding all I/O to its checked parent."""
    if (not SAFE_NAME.fullmatch(path.name) or len(path.name) > 200
            or path.name in {'.', '..'} or path.name.endswith('.env')):
        raise ValueError('unsafe artifact name or administrator-owned environment input')
    if (type(data) is not bytes or len(data) > FILE_LIMIT
            or type(mode) is not int or not 0 <= mode <= 0o777):
        raise ValueError('invalid artifact bytes, size or regular permission mode')
    with _Directory(path.parent) as parent:
        parent.verify()
        _atomic_write_at(parent.descriptor, path.name, data, mode)
        try:
            parent.verify()
        except (OSError, ValueError) as error:
            raise PublicationOutcomeUnknown('artifact parent changed after replacement: ' + str(path)) from error


def _products(products: dict[str, bytes]) -> tuple[dict[str, bytes], set[str]]:
    if not isinstance(products, dict) or not 0 < len(products) <= MEMBER_LIMIT:
        raise ValueError('invalid publication product count')
    files, directories, total = {}, set(), 0
    for name, data in products.items():
        if not isinstance(name, str) or type(data) is not bytes:
            raise ValueError('publication members require names and immutable bytes')
        parts = name.split('/')
        if (len(name) > PATH_LIMIT or len(parts) > DEPTH_LIMIT or name.endswith('.env')
                or any(part in {'', '.', '..'} or len(part) > 200
                       or SAFE_NAME.fullmatch(part) is None for part in parts)):
            raise ValueError('unsafe immutable publication member')
        total += len(data)
        if len(data) > FILE_LIMIT or total > BYTE_LIMIT:
            raise ValueError('publication exceeds byte limit')
        files[name] = data
        directories.update('/'.join(parts[:index]) for index in range(1, len(parts)))
        if len(files) + len(directories) > ENTRY_LIMIT:
            raise ValueError('publication exceeds entry limit')
    if files.keys() & directories:
        raise ValueError('publication member collides with a directory')
    return files, directories


def _verify_tree(parent: int, name: str, files: dict[str, bytes], directories: set[str]) -> None:
    root = _child_directory(parent, name)

    def inspect(descriptor: int, prefix: str, *, content: bool) -> dict[str, tuple[int, ...]]:
        found = {prefix: _identity(os.fstat(descriptor))}
        _owned_directory(descriptor, 0o755)
        # A streaming directory iterator is bounded before collecting any names.
        with os.scandir(descriptor) as iterator:
            for entry in iterator:
                relative = prefix + '/' + entry.name if prefix else entry.name
                if relative not in files and relative not in directories:
                    raise ValueError('immutable publication member set changed')
                if relative in directories:
                    child = _child_directory(descriptor, entry.name)
                    try:
                        found.update(inspect(child, relative, content=content))
                    finally:
                        os.close(child)
                else:
                    if content:
                        _verify_file(descriptor, entry.name, files[relative], 0o644)
                    found[relative] = _file_identity(descriptor, entry.name, 0o644)
                if len(found) > ENTRY_LIMIT + 1:
                    raise ValueError('immutable publication exceeds entry limit')
        if _identity(os.fstat(descriptor)) != found[prefix]:
            raise ValueError('immutable publication directory changed during inspection')
        return found

    try:
        identities = inspect(root, '', content=True)
        if identities.keys() != (files.keys() | directories | {''}):
            raise ValueError('immutable publication member set changed')
        if inspect(root, '', content=False) != identities:
            raise ValueError('immutable publication identities changed during inspection')
        current = os.stat(name, dir_fd=parent, follow_symlinks=False)
        if _identity(current) != identities['']:
            raise ValueError('immutable publication root replaced during inspection')
    finally:
        os.close(root)


def publish_immutable_tree(directory: Path, products: dict[str, bytes]) -> None:
    """Publish one complete candidate; never overwrite a completed release.

    Cooperating writers take a nonblocking lock on the pinned output parent.
    An interrupted private staging tree is retained, never broadly cleaned.
    No serving pointer or older release is changed by this operation.
    """
    if re.fullmatch(r'[0-9a-f]{64}', directory.name) is None:
        raise ValueError('immutable publication needs a content identity')
    files, directories = _products(products)
    with _Directory(directory.parent, create=True) as parent:
        try:
            fcntl.flock(parent.descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError('publication parent busy; no candidate was changed') from error
        parent.verify()
        try:
            os.stat(directory.name, dir_fd=parent.descriptor, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            _verify_tree(parent.descriptor, directory.name, files, directories)
            parent.verify()
            return
        name = '.' + directory.name + '.staged-' + os.urandom(16).hex()
        os.mkdir(name, 0o700, dir_fd=parent.descriptor)
        root = _child_directory(parent.descriptor, name)
        renamed = False
        try:
            _owned_directory(root, 0o700)
            for relative, data in sorted(files.items()):
                parts = relative.split('/')
                descriptor = _descend(root, tuple(parts[:-1]), create=True)
                try:
                    _atomic_write_at(descriptor, parts[-1], data, 0o644)
                finally:
                    os.close(descriptor)
            os.fchmod(root, 0o755)
            os.fsync(root)
            _verify_tree(parent.descriptor, name, files, directories)
            parent.verify()
            # All cooperating writers hold this parent lock. POSIX rename
            # also refuses replacing any nonempty completed immutable tree.
            try:
                os.stat(directory.name, dir_fd=parent.descriptor, follow_symlinks=False)
            except FileNotFoundError:
                pass
            else:
                raise ValueError('immutable destination appeared before publication')
            os.rename(name, directory.name, src_dir_fd=parent.descriptor, dst_dir_fd=parent.descriptor)
            renamed = True
            os.fsync(parent.descriptor)
            _verify_tree(parent.descriptor, directory.name, files, directories)
            parent.verify()
        except BaseException as error:
            if not renamed:
                error.add_note('retained private candidate: ' + str(directory.parent / name))
                try:
                    os.fchmod(root, 0o700)
                    os.fsync(root)
                    os.fsync(parent.descriptor)
                except OSError as retention_error:
                    error.add_note('private staging evidence could not be synchronized: '
                                   + str(retention_error))
            if renamed and isinstance(error, (OSError, ValueError)):
                raise PublicationOutcomeUnknown('immutable tree renamed; durable postcondition unknown: '
                                                + str(directory)) from error
            raise
        finally:
            os.close(root)
