#!/usr/bin/env python3
"""Capture one shared installer source and serialize both suite publications.

Normal builds execute no test, shell, policy validator or browser generator and
never rewrite source inputs. Explicit validation belongs to check_build.py.
"""
from __future__ import annotations

import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shlex
import stat
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[1]
SEED = ROOT / 'd-i/debian'
GENERATED = {'preseed.cfg', 'payload.tar.gz', 'payload.manifest'}
EXCLUDED_DIRS = {'tests', '__pycache__', '.git', '.pytest_cache', 'releases', 'publications'}
PRIVATE_INPUT_NAMES = {'preseed.env', 'git_ed25519', 'git_ed25519.pub', 'id_git_ed25519'}
PRIVATE_KEY_HEADER = re.compile(rb'-----BEGIN (?:OPENSSH |RSA |EC |DSA |ENCRYPTED )?PRIVATE KEY-----')
SAFE_PATH = re.compile(r'[A-Za-z0-9_./@+-]+\Z')
ALLOWED_PAYLOAD_PATHS = {
    'hooks/target/etc/skel-desktop/.config/vivaldi/Local State',
}
# cdebconf accepts continued values, but its installer-side line reader is
# deliberately small. Keep each physical serialization line below that
# reader boundary while preserving the exact debconf value after unfolding.
# This is a wire-format width, never an input or runtime restriction.
PRESEED_CONTINUATION_WIDTH = 1800
SOURCE_MEMBER_LIMIT = 10000
SOURCE_ENTRY_LIMIT = 20000
SOURCE_BYTE_LIMIT = 256 * 1024 * 1024
SOURCE_FILE_LIMIT = 16 * 1024 * 1024
COMPILER_INPUTS = ('Makefile', 'tools/build.py', 'tools/class_compiler.py', 'tools/publication.py')

# The publication helper atomically replaces the flat suite products.
sys.path.insert(0, str(ROOT / 'tools'))
from publication import BuildOwnership, PublicationOutcomeUnknown, atomic_write
from class_compiler import compile_classes

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def source_identity(info: os.stat_result) -> tuple[int, ...]:
    return (info.st_dev, info.st_ino, info.st_mode, info.st_nlink, info.st_uid,
            info.st_gid, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def directory_identity(info: os.stat_result) -> tuple[int, ...]:
    # Ignored generated/private leaves may change a directory's timestamps.
    # Selected membership is checked separately, including empty directories.
    return (info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_gid)


class SourceCapture:
    """One bounded, descriptor-relative capture for every authored build input.

    Linux O_PATH pins a leaf without opening a substituted device or FIFO.
    Reads promote only a checked regular-file descriptor through the kernel's
    /proc/self/fd interface, never by reopening its source pathname. No source
    descriptors survive the capture context and no input is executed here.
    """

    def __init__(self, root: Path):
        self.root = root
        self.descriptor = -1
        self.files: dict[str, tuple[str | None, tuple[int, ...]]] = {}
        self.directories: dict[str, tuple[int, ...]] = {}

    def _open_root(self) -> int:
        if not self.root.is_absolute() or '..' in self.root.parts:
            raise ValueError('source capture requires an absolute checkout root')
        descriptor = os.open('/', os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
        try:
            for part in self.root.parts[1:]:
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                                dir_fd=descriptor)
                os.close(descriptor)
                descriptor = child
            return descriptor
        except BaseException:
            os.close(descriptor)
            raise

    def __enter__(self) -> SourceCapture:
        if not hasattr(os, 'O_PATH'):
            raise ValueError('source capture requires the Linux O_PATH file identity interface')
        self.descriptor = self._open_root()
        try:
            self.root_identity = directory_identity(os.fstat(self.descriptor))
        except BaseException:
            os.close(self.descriptor)
            self.descriptor = -1
            raise
        return self

    def __exit__(self, *_error) -> None:
        os.close(self.descriptor)
        self.descriptor = -1

    def _directory(self, relative: str, directories: dict) -> int:
        descriptor = os.dup(self.descriptor)
        try:
            current = ''
            for part in relative.split('/') if relative else ():
                child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                                dir_fd=descriptor)
                os.close(descriptor)
                descriptor = child
                current = current + '/' + part if current else part
                value = directory_identity(os.fstat(descriptor))
                if current in directories and directories[current] != value:
                    raise ValueError('source directory changed during discovery')
                directories[current] = value
            return descriptor
        except BaseException:
            os.close(descriptor)
            raise

    def _discover(self) -> tuple[dict, dict]:
        files, directories = {}, {'': self.root_identity}
        entries = total = 0

        def add(relative: str, member: str | None, info: os.stat_result) -> None:
            nonlocal total
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                raise ValueError('source must be a single-link regular file: ' + relative)
            if info.st_mode & 0o111:
                raise ValueError('source file must not be executable: ' + relative)
            if info.st_size < 0 or info.st_size > SOURCE_FILE_LIMIT:
                raise ValueError('source member exceeds byte limit: ' + relative)
            name = member if member is not None else relative
            allowed = name in ALLOWED_PAYLOAD_PATHS
            if (len(name) > 240 or any(part in {'', '.', '..'} for part in name.split('/'))
                    or (not SAFE_PATH.fullmatch(name) and not allowed)):
                raise ValueError('unsupported source member path: ' + relative)
            if relative in files:
                raise ValueError('source input selected more than once')
            total += info.st_size
            if len(files) >= SOURCE_MEMBER_LIMIT or total > SOURCE_BYTE_LIMIT:
                raise ValueError('aggregate source capture limits exceeded')
            files[relative] = (member, source_identity(info))

        def walk(relative: str, prefix: str, shared: bool, depth: int = 0) -> None:
            nonlocal entries
            if depth > 64:
                raise ValueError('source directory depth exceeds capture limit')
            if prefix and (len(prefix) > 240 or not SAFE_PATH.fullmatch(prefix)):
                raise ValueError('unsupported source directory path')
            descriptor = self._directory(relative, directories)
            try:
                names = []
                # Bound discovery before allocating or sorting an entire directory.
                with os.scandir(descriptor) as iterator:
                    for entry in iterator:
                        entries += 1
                        if entries > SOURCE_ENTRY_LIMIT:
                            raise ValueError('source discovery exceeds entry limit')
                        if entry.name in {'AGENTS.md', 'AGENTS.override.md', *PRIVATE_INPUT_NAMES}:
                            continue
                        if entry.name in EXCLUDED_DIRS:
                            continue
                        names.append(entry.name)
                for name in sorted(names):
                    child = relative + '/' + name
                    member = prefix + '/' + name if prefix else name
                    if shared and member in GENERATED:
                        continue
                    pinned = os.open(name, os.O_PATH | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=descriptor)
                    try:
                        info = os.fstat(pinned)
                        if stat.S_ISDIR(info.st_mode):
                            # The next open is directory-only and no-follow; a
                            # replaced component cannot open a device or escape.
                            identity = directory_identity(info)
                            directories[child] = identity
                            walk(child, member, shared, depth + 1)
                            if directories[child] != identity:
                                raise ValueError('source directory replaced during discovery')
                        else:
                            add(child, member, info)
                    finally:
                        os.close(pinned)
            finally:
                os.close(descriptor)

        def fixed(relative: str, member: str | None) -> None:
            parent, leaf = relative.rsplit('/', 1) if '/' in relative else ('', relative)
            descriptor = self._directory(parent, directories)
            try:
                pinned = os.open(leaf, os.O_PATH | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=descriptor)
                try:
                    add(relative, member, os.fstat(pinned))
                finally:
                    os.close(pinned)
            finally:
                os.close(descriptor)

        walk('d-i/debian', '', True)
        for suite in ('forky', 'trixie'):
            fixed(f'd-i/{suite}/common.cfg', f'frontends/{suite}/common.cfg')
            for tree in ('classes', 'fragments', 'hooks/target/etc/apt'):
                walk(f'd-i/{suite}/{tree}', f'frontends/{suite}/{tree}', False)
        for name in COMPILER_INPUTS:
            fixed(name, None)
        if not files:
            raise ValueError('empty source capture')
        return files, directories

    def read(self) -> tuple[dict[str, bytes], dict[str, bytes]]:
        self.files, self.directories = self._discover()
        contents, compiler = {}, {}
        for relative, (member, identity) in sorted(self.files.items()):
            parent, leaf = relative.rsplit('/', 1) if '/' in relative else ('', relative)
            descriptor = self._directory(parent, dict(self.directories))
            try:
                pinned = os.open(leaf, os.O_PATH | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=descriptor)
                try:
                    if source_identity(os.fstat(pinned)) != identity:
                        raise ValueError('source replaced before capture: ' + relative)
                    # This Linux interface reopens our pinned regular inode;
                    # O_NOFOLLOW would reject its required kernel magic link.
                    readable = os.open(f'/proc/self/fd/{pinned}', os.O_RDONLY | os.O_CLOEXEC)
                    try:
                        stream = os.fdopen(readable, 'rb')
                    except BaseException:
                        os.close(readable)
                        raise
                    with stream:
                        if source_identity(os.fstat(stream.fileno())) != identity:
                            raise ValueError('pinned source identity changed')
                        data = stream.read(identity[6] + 1)
                        if (len(data) != identity[6]
                                or source_identity(os.fstat(stream.fileno())) != identity):
                            raise ValueError('source changed during capture: ' + relative)
                finally:
                    os.close(pinned)
            finally:
                os.close(descriptor)
            if PRIVATE_KEY_HEADER.match(data[:128].lstrip()):
                raise ValueError('private key cannot be packaged: ' + relative)
            if member is None:
                compiler[relative] = data
            else:
                contents[member] = data
        return contents, compiler

    def verify(self) -> None:
        descriptor = self._open_root()
        try:
            if directory_identity(os.fstat(descriptor)) != self.root_identity:
                raise ValueError('checkout root changed during capture')
        finally:
            os.close(descriptor)
        if self._discover() != (self.files, self.directories):
            raise ValueError('source membership or identity changed before publication; repeat generation')

def preseed_command(question: str, value: str) -> str:
    """Fold one shell value into bounded debconf continuation lines."""
    prefix = f'd-i {question} string '
    remaining = value
    lines = []
    while len(prefix) + len(remaining) > PRESEED_CONTINUATION_WIDTH:
        # Reserve one space and the continuation backslash. The debconf
        # reader removes that marker and restores one separator space.
        limit = PRESEED_CONTINUATION_WIDTH - len(prefix) - 2
        split = remaining.rfind(' ', 0, limit + 1)
        if split <= 0:
            raise ValueError(f'cannot fold generated preseed command: {question}')
        lines.append(prefix + remaining[:split] + ' \\')
        remaining = remaining[split + 1:]
        prefix = ''
    lines.append(prefix + remaining)
    return '\n'.join(lines) + '\n'

def generate_preseed(archive_sha: str, manifest_sha: str,
                     suite: str, release_id: str,
                     source: str, common: str) -> bytes:
    core = source.split('# BEGIN BOOTSTRAP CORE\n', 1)[1].split('# END BOOTSTRAP CORE', 1)[0]
    # Every core shell statement has an explicit delimiter; newlines are layout
    # only. Syntax validation is performed by the separate check command.
    core = ' '.join(line.strip() for line in core.splitlines() if line.strip() and not line.lstrip().startswith('#'))
    # The debconf RFC822 backend decodes literal \n when reloading a value;
    # GET then truncates multiline replies. Octal LF escapes preserve identical
    # printf/awk/tr behavior without corrupting a generated command on reload.
    # The source files keep readable escapes; only the embedded copy is encoded.
    core = core.replace(r'\n', r'\012')
    identity = f'INSTALLER_SUITE={suite}; INSTALLER_RELEASE_ID={release_id}; export INSTALLER_SUITE INSTALLER_RELEASE_ID; '
    command = ('set -eu; umask 077; ' + identity + core +
        ' installer_lifecycle_arm preflight; base=$(source_resolve_seed) || exit "$?"; '
        'boot=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/bootstrap; '
        '[ ! -L "$boot/source.release" ] || { source_error "indirect transport release marker"; exit 1; }; '
        'if [ ! -f "$boot/source.sh" ] || [ -L "$boot/source.sh" ] || '
        '[ ! -f "$boot/source.release" ] || '
        '[ "$(cat "$boot/source.release")" != "$INSTALLER_RELEASE_ID" ]; then '
        'source_transfer "$base" source.sh "$boot/source.sh" || exit 1; '
        'printf "%s\\012" "$INSTALLER_RELEASE_ID" >"$boot/source.release"; fi; '
        '. "$boot/source.sh"; '
        f'source_bootstrap "$base" {archive_sha} {manifest_sha} {suite}; '
        'installer_lifecycle_complete')
    # Generate one logical command. The readable implementation lives in
    # scripts/common/source.sh; never hand-maintain its quoted bootstrap copy.
    quoted = shlex.quote(command)
    # Publish the authored locale, keyboard and anna component answers in the
    # first fetched document as well as the later include.  The installer
    # consumes anna/choose_modules before preseed/early_command, so delaying
    # that record until the generated class plan leaves the early dispatcher
    # without partman and storage components.  Keep common.cfg as the single
    # source of these values and add the corresponding seen marker when the
    # authored common file omits it.
    initial_answer = re.compile(
        r'd-i (?:anna/(?:standard_modules|no_kernel_modules|choose_modules)'
        r'|debian-installer/(?:language|country|locale)|'
        r'debconf/language|localechooser/\S+|'
        r'keyboard-configuration/\S+|console-setup/\S+)\s'
    )
    initial_answers_lines = [line for line in common.splitlines()
                             if initial_answer.match(line)]
    if any(line.startswith('d-i anna/choose_modules multiselect ')
           for line in initial_answers_lines) and not any(
               line.startswith('d-i anna/choose_modules seen ')
               for line in initial_answers_lines):
        initial_answers_lines.append('d-i anna/choose_modules seen true')
    initial_answers = '\n'.join(initial_answers_lines)
    text = '''# Generated by tools/build.py. Edit sources, then rebuild before publishing.
# Repository execution is privileged: only boot from a trusted preseed source.
d-i debconf/priority select critical
d-i debconf/priority seen true
d-i debconf/frontend select noninteractive
d-i debconf/frontend seen true
d-i auto-install/enable boolean true
d-i auto-install/enable seen true
d-i clock-setup/utc boolean true
d-i clock-setup/utc seen true
d-i clock-setup/ntp boolean false
d-i clock-setup/ntp seen true

'''
    text += '# Initial localization and keyboard answers from shared configuration.\n'
    text += initial_answers + '\n\n'
    text += '''
# Resolve the effective URL, validate the complete payload, then include local files.
# The bootstrap include emits the preseed/run control file only after the
# authenticated payload has created and checked preseed-apply.sh.
'''
    # Preserve the exact command value while using debconf continuation lines.
    # cdebconf's small installer reader can silently discard an oversized
    # physical line; this is transport encoding, not an input or runtime cap.
    text += preseed_command('preseed/include_command', '/bin/sh -c ' + quoted) + '\n'
    for question, phase in [('preseed/early_command', 'early'), ('partman/early_command', 'partman'), ('preseed/late_command', 'late')]:
        runner = ('set -eu; ' + identity + core + f' installer_lifecycle_arm entry-{phase}; boot=${{INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}}/bootstrap; '
                  '[ -f "$boot/preflight.ok" ] && [ -x "$boot/preseed-bootstrap-entry.sh" ] || '
                  '{ echo "fatal: installer repository preflight did not complete" >&2; exit 1; }; '
                  f'installer_run_supervised "$boot/preseed-bootstrap-entry.sh" {phase} /tmp/installer.log; installer_lifecycle_complete')
        text += preseed_command(question, '/bin/sh -c ' + shlex.quote(runner))
    return text.encode()

def build() -> tuple[str, dict[str, bytes], dict[str, bytes]]:
    with SourceCapture(ROOT) as capture:
        contents, compiler_inputs = capture.read()
        result = serialize(contents, compiler_inputs)
        capture.verify()
        return result


def serialize(contents: dict[str, bytes], compiler_inputs: dict[str, bytes]
              ) -> tuple[str, dict[str, bytes], dict[str, bytes]]:
    # Compilation and serialization consume only this captured byte mapping.
    authored_frontends = {name.removeprefix('frontends/'): data for name, data in contents.items()
                          if name.startswith('frontends/')}
    captured = dict(contents)
    compiled, frontend_roles, matrix = compile_classes(captured)
    for name, data in compiled.items():
        if name in contents:
            raise ValueError('generated catalog collides with authored source')
        contents[name] = data
    # Generated leaves receive one catalog selector, consumed by the cached
    # existing FILE index. They never become executable role/profile input.
    selector_lines = []
    selector_names = set()
    for name in sorted(compiled):
        token = re.sub(r'[^A-Z0-9]+', '_', name.removeprefix('catalog/compiled/').upper()).strip('_')
        selector = 'FILE_COMPILED_' + token
        if selector in selector_names:
            raise ValueError('compiled selector collision')
        selector_names.add(selector)
        selector_path = ('${DIR_FRONTENDS}/' + name.removeprefix('frontends/')) if name.startswith('frontends/') else ('${DIR_CATALOG_COMPILED}/' + name.removeprefix('catalog/compiled/'))
        selector_lines.append(f'{selector}="{selector_path}"\n')
    contents['repo.env'] += ''.join(selector_lines).encode()
    identity_lines = [f'{sha(data)}  source/{name}\n' for name, data in sorted(captured.items())]
    identity_lines += [f'{sha(data)}  compiler/{name}\n' for name, data in sorted(compiler_inputs.items())]
    input_fingerprint = sha(''.join(sorted(identity_lines)).encode())
    release_id = sha((input_fingerprint + '\n' + ''.join(f'{sha(data)}  {name}\n' for name, data in sorted(contents.items()))).encode())
    contents['catalog/compiled/release.tsv'] = f'format\t1\nrelease\t{release_id}\nsource\t{input_fingerprint}\n'.encode()
    contents = dict(sorted(contents.items()))
    if len(contents) > 10000 or sum(map(len, contents.values())) > 256 * 1024 * 1024:
        raise ValueError('aggregate payload limits exceeded')
    manifest = ('format=3\n' + ''.join(f'{len(data)}\t{sha(data)}\t{name}\n' for name, data in contents.items())).encode()
    archive = io.BytesIO()
    with gzip.GzipFile(fileobj=archive, mode='wb', filename='', mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode='w', format=tarfile.USTAR_FORMAT) as tf:
            for name, data in contents.items():
                info = tarfile.TarInfo(name)
                info.size = len(data)
                info.mode = 0o644
                info.uid = info.gid = info.mtime = 0
                info.uname = info.gname = ''
                tf.addfile(info, io.BytesIO(data))
    payload = archive.getvalue()
    source = contents['scripts/common/source.sh']
    frontends = {**authored_frontends, **frontend_roles}
    for suite in ('forky', 'trixie'):
        common = contents[f'frontends/{suite}/common.cfg']
        frontends[f'{suite}/preseed.cfg'] = generate_preseed(
            sha(payload), sha(manifest), suite, release_id,
            source.decode(), common.decode())
    products = {'payload.tar.gz': payload, 'payload.manifest': manifest, 'source.sh': source,
                'support-matrix.json': json.dumps(matrix, sort_keys=True, indent=2).encode() + b'\n'}
    receipt = {'format': 1, 'release': release_id, 'source_fingerprint': input_fingerprint,
               'members': len(contents), 'suites': ['forky', 'trixie'],
               'products': {name: sha(data) for name, data in products.items()},
               'frontends': {name: sha(data) for name, data in sorted(frontends.items())},
               'source_inputs': {name: sha(data) for name, data in sorted(captured.items())},
               'compiler_inputs': {name: sha(data) for name, data in compiler_inputs.items()},
               'runtime_acceptance': 'unverified; no installer, native checks or tests executed'}
    products['receipt.json'] = (json.dumps(receipt, sort_keys=True, indent=2) + '\n').encode()
    return release_id, products, frontends

def main() -> int:
    if len(sys.argv) != 1:
        print('build accepts no validation/execution flags; generation only', file=sys.stderr)
        return 2
    try:
        with BuildOwnership(ROOT / 'd-i'):
            release_id, products, frontends = build()
            # Overwrite the same flat regular files on every build. These are
            # checkout products; serving changes remain an explicit operator task.
            for suite in ('forky', 'trixie'):
                for name, data in sorted(products.items()):
                    atomic_write(ROOT / 'd-i' / suite / name, data, 0o644)
            for name, data in sorted(frontends.items()):
                if name not in {'forky/preseed.cfg', 'trixie/preseed.cfg'}:
                    continue
                target = ROOT / 'd-i' / name
                atomic_write(target, data, 0o644)
        print(f'built source identity {release_id} members={len(products["payload.manifest"].splitlines()) - 1}')
        print('suite products: d-i/{forky,trixie}/{payload.tar.gz,payload.manifest,source.sh,receipt.json,support-matrix.json}')
        return 0
    except PublicationOutcomeUnknown as error:
        print('build outcome unknown; retain artifacts and do not retry automatically: ' + str(error), file=sys.stderr)
        for detail in getattr(error, '__notes__', ()):
            print(detail, file=sys.stderr)
        return 75
    except (OSError, ValueError) as error:
        print('build failed: ' + str(error), file=sys.stderr)
        for detail in getattr(error, '__notes__', ()):
            print(detail, file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
