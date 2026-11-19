#!/usr/bin/python3
"""Prepare canonical rendered inputs for syntax audits in a disposable image.

This invokes the production data validators, map producers, renderer, Perl
publisher and ownership handoff. Account identity, architecture and frozen
storage identities are explicit synthetic fixture inputs. Only the captured
base hook's ownership conversion is executed; no complete installer hook,
package operation, service manager, device discovery or hardware command runs.
"""
from __future__ import annotations

# Refuse ordinary checkouts before repository imports or fixture side effects.
from pathlib import Path as _IsolationPath
import sys as _isolation_sys
_isolation_sys.path.insert(0, str(_IsolationPath(__file__).resolve().parents[1] / 'tools'))
_isolation_sys.path.insert(0, '/workspace/repository/tools')
from isolation import require_test_isolation as _require_test_isolation
_isolation_sys.path.pop(0)
_require_test_isolation()

import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import sys
import tarfile

from stage_process import CleanupUnknown, run_stage

REPOSITORY = Path('/workspace/repository')
WORKSPACE = Path('/workspace')
MAX_FILE = 16 * 1024 * 1024
MAX_TREE = 256 * 1024 * 1024
MAX_MEMBERS = 10000
MAX_DIAGNOSTIC = 8192
PROFILES = {'desktop': 'btrfs-de-p15s', 'server': 'btrfs-srv-flex'}
SAFE_MEMBER = re.compile(r'[A-Za-z0-9_./@+ -]+\Z')
OWNERSHIP_MEMBERS = ('scripts/common/lifecycle.sh',
                     'scripts/common/modules/target-publication.sh',
                     'hooks/installer/base-stage.d/00rendertarget')
OWNERSHIP_PHASE = 'hook-base-00rendertarget'
# The shared stage owner controls elapsed time and the process session. This
# child setup additionally bounds CPU, address space, descriptors and each
# output file before executing the actual reviewed program unchanged.
LIMITED_EXEC = '''import os, resource, sys
seconds = int(sys.argv[1])
def bound(kind, soft, hard):
    outer_soft, outer_hard = resource.getrlimit(kind)
    if outer_soft != resource.RLIM_INFINITY:
        soft = min(soft, outer_soft)
    if outer_hard != resource.RLIM_INFINITY:
        hard = min(hard, outer_hard)
    resource.setrlimit(kind, (min(soft, hard), hard))
bound(resource.RLIMIT_CORE, 0, 0)
bound(resource.RLIMIT_CPU, seconds, seconds + 1)
bound(resource.RLIMIT_FSIZE, 16 * 1024 * 1024, 16 * 1024 * 1024)
bound(resource.RLIMIT_AS, 512 * 1024 * 1024, 512 * 1024 * 1024)
bound(resource.RLIMIT_NOFILE, 128, 128)
os.execv(sys.argv[2], sys.argv[2:])
'''
MAP_PRODUCERS = r'''set -eu
umask 077
captured=$1
inputs=$2
. "$captured/scripts/common/source.sh"
source_load_repo_env "$captured/repo.env"
. "$captured/scripts/common/modules/files-logging.sh"
. "$captured/scripts/late/core.sh"
. "$captured/scripts/late/templates.sh"
# Only the error transport is fixture-local; every producer validation still
# terminates the shell with a nonzero status before rendering can begin.
installer_fatal() { printf 'fixture map producer rejected input: %s\n' "$*" >&2; exit 93; }
# This is the production cache of the exact captured schema, followed by the
# production mapper's key/type/field checks and the renderer's duplicate gate.
INSTALLER_RUNTIME_PATH_SCHEMA=$(cat "$captured/catalog/runtime-paths.tsv")
installer_runtime_path_placeholder_map >"$inputs/paths.map"
late_command_set_grub_arch_policy
render_target_template_placeholder_map >"$inputs/templates.map"
systemd_resource_placeholder_map >"$inputs/resources.map"
printf 'SYSTEMD_IOWEIGHT_ENABLE=%s\nSYSTEMD_CPUWEIGHT_ENABLE=%s\n' \
  "$SYSTEMD_IOWEIGHT_ENABLE" "$SYSTEMD_CPUWEIGHT_ENABLE" >>"$inputs/resources.map"
# Hardware module discovery belongs to a later stage and is deliberately absent.
: >"$inputs/modules.map"
printf 'ACCOUNT_USERNAME=%s\nSOFTWARE_APT_REPO_LOCAL_DEB_MAXIMUM_BYTES=%s\n' \
  "$ACCOUNT_USERNAME" "$SOFTWARE_APT_REPO_LOCAL_DEB_MAXIMUM_BYTES" >"$inputs/perl.map"
printf 'scripts=%s\ntarget=%s\ninstaller=%s\nlate=%s\ndesktop=%s\nfirstboot=%s\nappearance-python=%s\nappearance-registry=%s\n' \
  "$DIR_REPO_SCRIPTS" "$DIR_HOOKS_TARGET" "$DIR_HOOKS_INSTALLER" \
  "$DIR_SCRIPTS_LATE" "$DIR_SCRIPTS_DESKTOP" "$DIR_SCRIPTS_FIRSTBOOT" \
  "$DIR_TARGET_PY/labwc_appearance" "$DIR_TARGET_SHARE_LABWC_APPEARANCE/fields.json.tmpl" \
  >"$inputs/selectors.map"
'''
OWNERSHIP_HANDOFF = r'''set -eu
umask 077
syntax_ownership_source=$1
work=$2
syntax_ownership_output=$3
syntax_ownership_mode=$4
syntax_ownership_awk=$5
# The selected dialect is explicit. A missing BusyBox never selects another
# interpreter. Its applets also exercise the real metadata/ancestry helpers.
case "$syntax_ownership_mode" in
  busybox)
    awk() { "$syntax_ownership_awk" awk "$@"; }
    ls() { "$syntax_ownership_awk" ls "$@"; }
    id() { "$syntax_ownership_awk" id "$@"; }
    mkdir() { "$syntax_ownership_awk" mkdir "$@"; }
    cat() { "$syntax_ownership_awk" cat "$@"; }
    wc() { "$syntax_ownership_awk" wc "$@"; }
    chmod() { "$syntax_ownership_awk" chmod "$@"; }
    ;;
  posix) awk() { "$syntax_ownership_awk" "$@"; } ;;
  *) exit 92 ;;
esac
. "$syntax_ownership_source/scripts/common/lifecycle.sh"
. "$syntax_ownership_source/scripts/common/modules/target-publication.sh"
# Keep production rejection and metadata checks. Only the terminal installer
# error transport is replaced, so failure cannot enter a frontend hold loop.
installer_fatal() { printf 'fixture ownership handoff rejected input: %s\n' "$*" >&2; exit 93; }
: "${INSTALLER_PHASE:?fixture ownership phase is unavailable}"
DIR_INSTALLER_TARGET_OWNERSHIP=$syntax_ownership_output/target-assets
. "$syntax_ownership_output/base-conversion.sh"
installer_target_ownership_import "$work/inputs/published-ownership.tsv"
installer_target_ownership_snapshot >"$syntax_ownership_output/snapshot.tsv"
'''


def direct_file(path: Path, limit: int = MAX_FILE) -> bytes:
    descriptor = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, 'rb') as stream:
        before = os.fstat(stream.fileno())
        if (not stat.S_ISREG(before.st_mode) or before.st_nlink != 1
                or before.st_uid != os.geteuid() or before.st_mode & 0o022
                or before.st_size < 0 or before.st_size > limit):
            raise ValueError('unsafe fixture input: ' + str(path))
        data = stream.read(limit + 1)
        after = os.fstat(stream.fileno())
        identity = ('st_dev', 'st_ino', 'st_mode', 'st_nlink', 'st_uid', 'st_gid',
                    'st_size', 'st_mtime_ns', 'st_ctime_ns')
        if len(data) != before.st_size or any(getattr(before, key) != getattr(after, key)
                                               for key in identity):
            raise ValueError('fixture input changed while reading: ' + str(path))
    return data


def write(path: Path, data: bytes, mode: int = 0o600) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, 'wb') as stream:
        stream.write(data)
    path.chmod(mode)


def create_output(output: Path) -> Path:
    if (not output.is_absolute() or not output.is_relative_to(WORKSPACE)
            or output == WORKSPACE or output.is_relative_to(REPOSITORY)
            or len(str(output)) > 4096 or '..' in output.parts):
        raise ValueError('output must be a new absolute directory below /workspace, outside the checkout')
    member_name(output.relative_to(WORKSPACE).as_posix())
    parent = WORKSPACE
    for part in output.relative_to(WORKSPACE).parts[:-1]:
        info = parent.lstat()
        if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid()
                or info.st_mode & 0o022):
            raise ValueError('unsafe fixture output ancestor: ' + str(parent))
        parent /= part
        try:
            parent.mkdir(mode=0o700)
        except FileExistsError:
            pass
    info = parent.lstat()
    if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid()
            or info.st_mode & 0o022):
        raise ValueError('unsafe fixture output ancestor: ' + str(parent))
    # mkdir's exclusive creation rejects ordinary entries and dangling links.
    output.mkdir(mode=0o700)
    return output


def environment(home: Path) -> dict[str, str]:
    return {'PATH': '/usr/bin:/bin', 'HOME': str(home), 'LC_ALL': 'C', 'LANG': 'C',
            'TMPDIR': str(home), 'TMP': str(home), 'TEMP': str(home),
            'PYTHONDONTWRITEBYTECODE': '1'}


def run(command: list[str], *, env: dict[str, str], cwd: Path,
        output: Path, timeout: int = 30) -> None:
    if timeout <= 0 or not command or not command[0].startswith('/'):
        raise ValueError('a bounded absolute fixture command is required')
    diagnostic_path = output.with_suffix(output.suffix + '.stderr')
    write(output, b'')
    write(diagnostic_path, b'')
    with output.open('r+b') as stream, diagnostic_path.open('r+b') as errors:
        result = run_stage(['/usr/bin/python3', '-I', '-B', '-c', LIMITED_EXEC,
                            str(timeout), *command], cwd=cwd, env=env,
                           stdout=stream, stderr=errors, timeout=timeout)
    if result.returncode:
        with diagnostic_path.open('rb') as errors:
            diagnostic = errors.read(MAX_DIAGNOSTIC + 1)
        sys.stderr.buffer.write(diagnostic[:MAX_DIAGNOSTIC])
        if len(diagnostic) > MAX_DIAGNOSTIC:
            print('\n[diagnostic truncated; complete bounded log retained in fixture]', file=sys.stderr)
        raise RuntimeError('fixture command failed with status ' + str(result.returncode) + ': ' + command[0])


def _ownership_runtime(mode: str) -> dict:
    """Select one explicit guest runtime; never infer a dialect fallback."""
    if mode == 'busybox':
        executable = shutil.which('busybox', path='/usr/bin:/bin')
        if executable is None:
            raise RuntimeError('BusyBox is required for ownership validation; no runtime fallback is permitted')
        shell_command = [executable, 'ash']
        awk_command = [executable, 'awk']
    elif mode == 'posix':
        shell_command = ['/bin/dash']
        awk_command = ['/usr/bin/awk']
    else:
        raise ValueError('unsupported ownership runtime')
    identities = {}
    for role, command in (('shell', shell_command), ('awk', awk_command)):
        executable = Path(command[0])
        if not os.access(executable, os.X_OK):
            raise RuntimeError('required ownership runtime is unavailable: ' + str(executable))
        resolved = executable.resolve(strict=True)
        identities[role] = {'command': command, 'resolved_path': str(resolved),
                            'sha256': hashlib.sha256(direct_file(resolved)).hexdigest()}
    return {'name': mode, 'busybox_validation': mode == 'busybox', **identities}


def member_name(name: str) -> str:
    path = PurePosixPath(name)
    if (not name or len(name) > 4096 or not SAFE_MEMBER.fullmatch(name)
            or path.is_absolute() or any(part in ('', '.', '..') for part in name.split('/'))):
        raise ValueError('invalid captured source member')
    return name


def _capture_payload(artifacts: Path, destination: Path,
                     current_renderer: Path) -> tuple[bytes, str, str, int]:
    """Validate and copy artifact data before any map producer can be started."""
    manifest = direct_file(artifacts / 'payload.manifest', 4 * 1024 * 1024)
    lines = manifest.decode('ascii').splitlines()
    if not lines or lines.pop(0) != 'format=3':
        raise ValueError('unsupported captured manifest')
    expected = {}
    total = 0
    for line in lines:
        size, digest, name = line.split('\t')
        member_name(name)
        if (name in expected or not re.fullmatch(r'[0-9]+', size)
                or not re.fullmatch(r'[a-f0-9]{64}', digest)):
            raise ValueError('invalid captured manifest row')
        count = int(size)
        total += count
        if count > MAX_FILE or total > MAX_TREE or len(expected) >= MAX_MEMBERS:
            raise ValueError('captured payload exceeds renderer bounds')
        expected[name] = (count, digest)
    archive_path = artifacts / 'payload.tar.gz'
    archive_bytes = direct_file(archive_path, MAX_TREE)
    seen = set()
    with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode='r:gz') as archive:
        for entry_count, info in enumerate(archive, 1):
            if entry_count > 20000:
                raise ValueError('captured archive exceeds the entry limit')
            name = info.name.rstrip('/') if info.isdir() else info.name
            member_name(name)
            if info.isdir():
                continue
            if not info.isfile() or name not in expected or name in seen:
                raise ValueError('unlisted, linked or duplicate captured member')
            size, digest = expected[name]
            if info.size != size or info.mode & 0o6022:
                raise ValueError('captured member size or mode differs')
            stream = archive.extractfile(info)
            if stream is None:
                raise ValueError('cannot read captured member')
            with stream:
                data = stream.read(MAX_FILE + 1)
            if len(data) != size or hashlib.sha256(data).hexdigest() != digest:
                raise ValueError('captured member digest differs')
            write(destination / name, data, info.mode & 0o777)
            seen.add(name)
    if seen != expected.keys():
        raise ValueError('captured archive is missing manifest members')
    renderer = Path('scripts/common/render.pl')
    if direct_file(destination / renderer) != direct_file(current_renderer):
        raise ValueError('payload contains a stale renderer; regenerate before replay')
    for member in OWNERSHIP_MEMBERS:
        if direct_file(destination / member) != direct_file(current_renderer.parents[2] / member):
            raise ValueError('payload contains stale ownership support: ' + member + '; regenerate before replay')
    return manifest, hashlib.sha256(archive_bytes).hexdigest(), hashlib.sha256(manifest).hexdigest(), len(seen)


def _base_ownership_conversion(data: bytes) -> bytes:
    """Take the actual hook conversion, with no alternate TSV producer."""
    start = b"LC_ALL=C awk -F '\\t' -v phase=\"${INSTALLER_PHASE:-base-stage}\" '\n"
    end = (b"' \"$work/inputs/published-assets.tsv\" >\"$work/inputs/published-ownership.tsv\"\n"
           b'chmod 0600 "$work/inputs/published-ownership.tsv"\n')
    if data.count(start) != 1 or data.count(end) != 1:
        raise ValueError('base ownership conversion has no unique reviewed boundary')
    first = data.index(start)
    last = data.index(end) + len(end)
    if last <= first or last - first > 4096:
        raise ValueError('base ownership conversion exceeds its reviewed boundary')
    return data[first:last]


def _commit_target_ownership(scenario: Path, source: Path, prepared: Path,
                            receipt: dict, source_hashes: dict[str, str],
                            runtime: dict) -> dict:
    """Exercise the prepared publication's real installer-side handoff."""
    owners = {member: direct_file(source / member) for member in OWNERSHIP_MEMBERS}
    if {member: hashlib.sha256(data).hexdigest() for member, data in owners.items()} != source_hashes:
        raise ValueError('ownership support changed after verified source capture')
    conversion = _base_ownership_conversion(owners[OWNERSHIP_MEMBERS[2]])
    ownership = scenario / 'ownership'
    ownership.mkdir(mode=0o700)
    write(ownership / 'base-conversion.sh', conversion)
    run([*runtime['shell']['command'], '-eu', '-c', OWNERSHIP_HANDOFF,
         'full-payload-ownership-fixture', str(source), str(prepared), str(ownership),
         runtime['name'], runtime['awk']['command'][0]],
        env={**environment(scenario), 'INSTALLER_PHASE': OWNERSHIP_PHASE},
        cwd=scenario, output=ownership / 'handoff.log', timeout=30)
    published_path = prepared / 'inputs/published-assets.tsv'
    converted_path = prepared / 'inputs/published-ownership.tsv'
    journal_path = ownership / 'target-assets/journal.tsv'
    snapshot_path = ownership / 'snapshot.tsv'
    published = direct_file(published_path)
    if not published.endswith(b'\n'):
        raise ValueError('published ownership input is incomplete')
    rows = [line.split(b'\t') for line in published.splitlines()]
    if (not rows or len(rows) != receipt['published_perl_files']
            or any(len(row) != 3 for row in rows)):
        raise ValueError('published ownership row count differs from the completed receipt')
    expected = b''.join(target + b'\t' + member + b'\tplain\t' + OWNERSHIP_PHASE.encode('ascii')
                        + b'\t' + mode + b'\n' for member, target, mode in rows)
    if direct_file(converted_path) != expected or direct_file(journal_path) != expected:
        raise ValueError('ownership handoff changed or lost a renderer publication')
    snapshot_data = direct_file(snapshot_path)
    if (not snapshot_data.endswith(b'\n')
            or sorted(snapshot_data.splitlines()) != sorted(expected.splitlines())):
        raise ValueError('ownership snapshot differs from the complete committed publication')
    # AWK array order is deliberately unspecified. Compare all rows and report
    # the digest of their sorted representation without altering real output.
    canonical_snapshot = b''.join(line + b'\n' for line in sorted(snapshot_data.splitlines()))
    return {'result': 'passed', 'runtime': runtime,
            'busybox_validation': runtime['busybox_validation'], 'phase': OWNERSHIP_PHASE,
            'rows': len(rows), 'source_sha256': source_hashes,
            'conversion_sha256': hashlib.sha256(conversion).hexdigest(),
            'published_assets': str(published_path),
            'published_assets_sha256': hashlib.sha256(published).hexdigest(),
            'converted_batch': str(converted_path), 'journal': str(journal_path),
            'journal_sha256': hashlib.sha256(expected).hexdigest(),
            'snapshot': str(snapshot_path),
            'snapshot_records_sha256': hashlib.sha256(canonical_snapshot).hexdigest()}


def snapshot(values: dict[str, str]) -> bytes:
    rows = []
    for key, value in sorted(values.items()):
        if not re.fullmatch(r'[A-Z][A-Z0-9_]*', key) or any(c in value for c in '\0\r\n'):
            raise ValueError('invalid synthetic snapshot field')
        rows.append(key + "='" + value.replace("'", "'\\''") + "'\n")
    return ''.join(rows).encode('utf-8')


def records(path: Path) -> dict[str, str]:
    rows = direct_file(path, 1024 * 1024).decode('utf-8').splitlines()
    if not rows or rows.pop() != '__INSTALLER_DATA_END__' or len(rows) % 2:
        raise ValueError('incomplete production snapshot records')
    result = {}
    for key, value in zip(rows[::2], rows[1::2]):
        if key in result:
            raise ValueError('duplicate production snapshot field')
        result[key] = value
    return result


def prepare_syntax_fixture(output: Path, suite: str, family: str, *,
                           ownership_runtime: str = 'busybox') -> dict:
    """Prepare a shipped suite/family with explicit ownership-runtime evidence."""
    _require_test_isolation()
    if suite not in ('forky', 'trixie') or family not in PROFILES:
        raise ValueError('unsupported fixture suite or family')
    selected_ownership_runtime = _ownership_runtime(ownership_runtime)
    scenario = create_output(Path(output))
    prepared = scenario / 'prepared'
    source = prepared / 'source'
    inputs = prepared / 'inputs'
    prepared.mkdir(mode=0o700)
    source.mkdir(mode=0o700)
    inputs.mkdir(mode=0o700)
    base_env = environment(scenario)
    manifest, archive_hash, manifest_hash, member_count = _capture_payload(
        REPOSITORY / 'd-i' / suite, source,
        REPOSITORY / 'd-i/debian/scripts/common/render.pl')
    ownership_source_hashes = {member: hashlib.sha256(direct_file(source / member)).hexdigest()
                              for member in OWNERSHIP_MEMBERS}
    write(inputs / 'payload.manifest', manifest)
    write(prepared / 'identity', f'verified-v1 {archive_hash} {manifest_hash} /fixture-seed-{suite}\n'.encode())
    write(prepared / 'render.pl', direct_file(source / 'scripts/common/render.pl'))
    profile_member = f'catalog/compiled/{suite}/profiles/{family}/{PROFILES[family]}.env'
    write(inputs / 'host.env', direct_file(source / profile_member, 1024 * 1024))
    account = {'ACCOUNT_USERNAME': 'fixtureuser', 'ACCOUNT_FULLNAME': 'Fixture User',
               'ACCOUNT_UID': '1000', 'ACCOUNT_GID': '1000', 'ACCOUNT_HOME': '/home/fixtureuser'}
    layout = {'ZRAM_BACKING_RAW_PARTUUID': '00000000-0000-4000-8000-000000000001',
              'ZRAM_BACKING_RAW_DEVICE': '/dev/fixture-zram-backing',
              'ZRAM_BACKING_DEVICE': '/dev/mapper/zram-writeback'}
    context = {'INSTALLER_SUITE': suite, 'INSTALLER_HOST_VARIANT': family,
               'INSTALLER_ARCH_CLASS': 'amd64', 'SYSTEM_HOSTNAME': 'fixture-' + family}
    write(inputs / 'account.env', snapshot(account))
    write(inputs / 'layout.env', snapshot(layout))
    write(inputs / 'context.env', snapshot(context))
    values = {}
    for name in ('host', 'layout', 'account', 'context'):
        run(['/usr/bin/awk', '-v', 'mode=snapshot', '-f',
             str(source / 'scripts/common/credential-data.awk'), str(inputs / (name + '.env'))],
            env=base_env, cwd=scenario, output=inputs / (name + '.records'))
        values.update(records(inputs / (name + '.records')))
    if any(key in base_env for key in values):
        raise ValueError('snapshot attempts to replace the private process environment')
    producer_env = {**base_env, **values}
    run(['/bin/dash', '-eu', '-c', MAP_PRODUCERS, 'full-payload-map-fixture', str(source), str(inputs)],
        env=producer_env, cwd=scenario, output=scenario / 'map-producers.log')
    run(['/usr/bin/awk', '-f', str(source / 'scripts/common/logging-validate.awk'),
         str(source / 'hosts/logging/observability-schema.tsv'),
         str(source / 'hosts/logging/observability.env')],
        env=base_env, cwd=scenario, output=inputs / 'logging.map')
    run(['/usr/bin/awk', '-f', str(source / 'scripts/late/theme-validate.awk'),
         str(source / 'hosts/themes/theme-schema.tsv'),
         *(str(source / 'hosts/themes' / (group + '.env')) for group in ('base', 'apps', 'office'))],
        env=base_env, cwd=scenario, output=inputs / 'themes.map')
    selectors = {}
    for line in direct_file(inputs / 'selectors.map').decode('ascii').splitlines():
        key, value = line.split('=', 1)
        if key in selectors:
            raise ValueError('duplicate captured renderer selector')
        selectors[key] = member_name(value)
    if (values.get('TIMESHIFT_ENABLE'), values.get('SNAPSHOTS_POLICY')) not in (
            ('true', 'timeshift-btrfs'), ('false', 'none')):
        raise ValueError('selected profile has inconsistent snapshot policy')
    selectors.update({'perl-assets': 'catalog/compiled/shared-perl-assets.tsv',
                      'profile-assets': 'catalog/compiled/profile-assets.tsv',
                      'perl-root': str(scenario / 'perl'), 'family': family,
                      'snapshots': values['TIMESHIFT_ENABLE']})
    command = ['/usr/bin/perl', '-f', str(prepared / 'render.pl'), str(prepared)]
    for key, value in selectors.items():
        command.extend(['--' + key, value])
    run(command, env=base_env, cwd=scenario, output=scenario / 'renderer.log', timeout=180)
    receipt = json.loads(direct_file(prepared / 'receipt.json'))
    if (receipt['members'] != member_count or receipt['source_archive_sha256'] != archive_hash
            or receipt['source_manifest_sha256'] != manifest_hash):
        raise ValueError('completed receipt differs from captured source identity')
    ownership = _commit_target_ownership(scenario, source, prepared, receipt,
                                        ownership_source_hashes, selected_ownership_runtime)
    result = {'format': 1, 'suite': suite, 'family': family, 'profile': profile_member,
              'scenario': str(scenario), 'rendered_root': str(source),
              'published_assets': str(inputs / 'published-assets.tsv'),
              'renderer_sha256': hashlib.sha256(direct_file(prepared / 'render.pl')).hexdigest(),
              'archive_sha256': archive_hash, 'manifest_sha256': manifest_hash,
              'synthetic_inputs': {'account': account, 'layout': layout, 'context': context},
              'source_manifest': str(inputs / 'payload.manifest'),
              'receipt': str(prepared / 'receipt.json'),
              'identity': str(prepared / 'identity'),
              'receipt_data': receipt, 'ownership': ownership, 'result': 'passed',
              'scope': 'Full captured source preparation, shared Perl publication and real ownership handoff; no installation or hardware execution.'}
    write(scenario / 'report.json', (json.dumps(result, indent=2, sort_keys=True) + '\n').encode())
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True,
                        help='new private absolute directory below /workspace, outside the checkout')
    parser.add_argument('--suite', choices=('forky', 'trixie'), required=True)
    parser.add_argument('--family', choices=('desktop', 'server'), required=True)
    parser.add_argument('--ownership-runtime', choices=('busybox', 'posix'), default='busybox',
                        help='BusyBox is mandatory by default; posix is explicit reduced-dialect evidence only')
    args = parser.parse_args()
    try:
        result = prepare_syntax_fixture(args.output, args.suite, args.family,
                                       ownership_runtime=args.ownership_runtime)
    except CleanupUnknown as error:
        print('TEST OUTCOME UNKNOWN: ' + str(error), file=sys.stderr)
        return 75
    except (OSError, ValueError, RuntimeError) as error:
        print('Syntax fixture preparation failed: ' + str(error), file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True), flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
