"""Frozen-plan selection and suite dependency regressions; isolated execution only."""
from __future__ import annotations

from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation
require_test_isolation()

import itertools
import re
import subprocess
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SEED = ROOT / 'd-i/debian'


TOR_TARGET_BOUNDARY_DRIVER = r'''#!/bin/sh
set -eu
module=$1
work=$2
mode=$3
target_shell=$4
case "$work" in /*) ;; *) exit 125 ;; esac
[ -d "$work" ] && [ ! -L "$work" ] || exit 125
printf '%s\n' "$mode" >"$work/mode"
mkdir -p "$work/bin" "$work/libexec"
ln -s /usr/bin/awk "$work/bin/awk"
cat >"$work/bin/gpg" <<'MOCK'
#!/bin/sh
while [ "$#" -gt 0 ]; do
  if [ "$1" = --output ]; then : >"$2"; exit 0; fi
  shift
done
exit 125
MOCK
cat >"$work/bin/gpgv" <<'MOCK'
#!/bin/sh
root=${0%/bin/*}
mode=$(cat "$root/mode")
case "$mode" in
  signature) exit 71 ;;
  cancel) kill -TERM "$PPID"; exit 0 ;;
  fingerprint) fingerprint=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB ;;
  *) fingerprint=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA ;;
esac
printf '[GNUPG:] VALIDSIG %s\n' "$fingerprint"
MOCK
cat >"$work/bin/python3" <<'MOCK'
#!/bin/sh
root=${0%/bin/*}
printf '%s\n' "$@" >"$root/helper.argv"
if [ "$(cat "$root/mode")" = helper ]; then exit 73; fi
MOCK
chmod 0755 "$work/bin/gpg" "$work/bin/gpgv" "$work/bin/python3"
software_fatal() { printf '%s\n' "$*" >&2; exit 81; }
software_info() { :; }
software_validate_release_version() { :; }
software_validate_sha256() { :; }
installer_repo_file_value() { printf '%s\n' "$1"; }
software_stage_seed_asset() {
  case "$2" in "$work"/*) ;; *) exit 125 ;; esac
  mkdir -p "$(dirname "$2")"
  if [ "$1" = FILE_TARGET_SHARE_SOFTWARE_TOR_BROWSER_DEVELOPERS_ASC ]; then
    if [ "$mode" = key ]; then printf bad-key >"$2"; else printf fixture-key >"$2"; fi
  else
    : >"$2"
  fi
}
software_download() {
  case "$3" in "$work"/*) ;; *) exit 125 ;; esac
  if [ "$mode" = archive ]; then printf bad-archive >"$3"; else printf fixture-archive >"$3"; fi
}
run_in_target() {
  if [ "$1" != 'authenticate and install Tor Browser' ]; then return 0; fi
  shift
  [ "$1" = /bin/sh ] && [ "$2" = -eu ] && [ "$3" = -c ] || exit 125
  shift 3
  # Match the target executor's clean boundary: no DIR_*, host HOME or session.
  /usr/bin/env -i PATH=/usr/bin:/bin LC_ALL=C HOME="$work" \
    "$target_shell" -eu -c "$@" >"$work/auth.stdout" 2>"$work/auth.stderr"
}
chroot() { :; }
. "$module"
software_install_tor_media_runtime() { :; }
DIR_USR_LOCAL_LIBEXEC=$work/libexec
SOFTWARE_TOR_BROWSER_VERSION=1.2.3
SOFTWARE_TOR_BROWSER_URL=https://fixture.invalid/browser.tar.xz
SOFTWARE_TOR_BROWSER_ARCHIVE_FALLBACK_URL=https://fixture.invalid/archive.tar.xz
SOFTWARE_TOR_BROWSER_SHA256=$(printf fixture-archive | sha256sum)
SOFTWARE_TOR_BROWSER_SHA256=${SOFTWARE_TOR_BROWSER_SHA256%% *}
SOFTWARE_TOR_BROWSER_KEY_SHA256=$(printf fixture-key | sha256sum)
SOFTWARE_TOR_BROWSER_KEY_SHA256=${SOFTWARE_TOR_BROWSER_KEY_SHA256%% *}
SOFTWARE_TOR_BROWSER_SIGNING_FINGERPRINT=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
ACCOUNT_USERNAME=fixture
work_dir=$work
target_root=$work
(
  set -eu
  software_install_tor_browser
) &
worker=$!
if wait "$worker"; then actual_status=0; else actual_status=$?; fi
case "$mode" in
  success) expected_status=0 ;;
  baseline) expected_status=2 ;;
  archive|key|fingerprint) expected_status=1 ;;
  signature) expected_status=71 ;;
  helper) expected_status=73 ;;
  cancel) expected_status=143 ;;
  *) exit 125 ;;
esac
[ "$actual_status" -eq "$expected_status" ] || {
  cat "$work/auth.stderr" >&2
  printf 'unexpected status: mode=%s actual=%s expected=%s\n' "$mode" "$actual_status" "$expected_status" >&2
  exit 1
}
case "$mode" in
  success|helper)
    printf '%s\n' -I -B "$work/libexec/tor-browser-install" \
      "$work/tor-browser.tar.xz" "$SOFTWARE_TOR_BROWSER_SHA256" >"$work/expected.argv"
    cmp "$work/expected.argv" "$work/helper.argv"
    ;;
  *) [ ! -e "$work/helper.argv" ] ;;
esac
if [ "$mode" = baseline ]; then
  grep -q 'DIR_USR_LOCAL_LIBEXEC.*not set' "$work/auth.stderr"
fi
for retained in "$work"/tor-verify.*; do
  [ ! -e "$retained" ] || { printf 'verification directory retained: %s\n' "$retained" >&2; exit 1; }
done
printf 'PASS tor-target-boundary shell=%s mode=%s status=%s\n' "$target_shell" "$mode" "$actual_status"
'''


BOOTSTRAP_PATH_BOUNDARY_DRIVER = r'''#!/bin/sh
set -eu
module=$1
runtime_contract=$2
asset=$3
expected=$4
work=$5
mode=$6
transport=$7
source_path=$8
case "$work" in /*) ;; *) exit 125 ;; esac
[ -d "$work" ] && [ ! -L "$work" ] || exit 125
# The target contract derives three paths from the selected profile policy.
# Supply fixture identifiers before loading it, as the real context loader does.
BOOTPROFILE_DEFAULT=balanced
BOOTPROFILE_HARDENED=hardened
BOOTPROFILE_PERFORMANCE=performance
. "$runtime_contract"
DIR_SCRIPTS_LATE=scripts/late
DIR_SCRIPTS_DESKTOP=scripts/desktop
DIR_SCRIPTS_FIRSTBOOT=scripts/firstboot
DIR_HOOKS_TARGET=hooks/target
DIR_SCRIPTS_DESKTOP_COMPONENTS=$DIR_SCRIPTS_DESKTOP/components
DIR_SCRIPTS_LATE_DEVOPS=$DIR_SCRIPTS_LATE/devops
bootstrap_fatal() { printf '%s\n' "$*" >&2; exit 91; }
installer_fatal() { bootstrap_fatal "$@"; }
bootstrap_load_source_library() { :; }
source_fetch() {
  if [ "$mode" = fetch-failure ]; then printf partial >"$3"; return 71; fi
  cp "$asset" "$3"
  chmod "$4" "$3"
}
installer_render_logging_asset() { :; }
case "$transport" in
  common) installer_fetch_seed_path() { source_fetch "$@"; } ;;
  fallback) : ;;
  *) exit 125 ;;
esac
. "$module"
case "$mode" in
  render-failure) installer_apply_scalar_placeholders() { printf partial >"$2"; return 72; } ;;
  missing-renderer|entrypoint) unset -f installer_apply_scalar_placeholders ;;
  catalog) unset DIR_SCRIPTS_LATE DIR_SCRIPTS_DESKTOP DIR_SCRIPTS_FIRSTBOOT DIR_HOOKS_TARGET ;;
esac
destination=$work/result
printf previous >"$destination"
printf previous >"$work/previous"
(
  set -eu
  bootstrap_fetch_seed_file /fixture/source "$source_path" "$destination" 0700
) >"$work/stdout" 2>"$work/stderr" &
worker=$!
if wait "$worker"; then status=0; else status=$?; fi
case "$mode" in
  baseline|success|passthrough|concrete|entrypoint|catalog) expected_status=0 ;;
  unknown|missing-renderer) expected_status=91 ;;
  render-failure) expected_status=72 ;;
  fetch-failure) expected_status=71 ;;
  *) exit 125 ;;
esac
[ "$status" -eq "$expected_status" ] || {
  cat "$work/stderr" >&2
  printf 'unexpected bootstrap status: mode=%s actual=%s expected=%s\n' "$mode" "$status" "$expected_status" >&2
  exit 1
}
case "$mode" in
  success|concrete|entrypoint) cmp "$expected" "$destination"; [ -x "$destination" ] ;;
  baseline|passthrough|catalog) cmp "$asset" "$destination" ;;
  *) cmp "$work/previous" "$destination" ;;
esac
for retained in "$work"/.bootstrap-asset.* "$work"/*.path-rendered; do
  [ ! -e "$retained" ] || { printf 'bootstrap staging retained: %s\n' "$retained" >&2; exit 1; }
done
printf 'PASS bootstrap-path-boundary mode=%s transport=%s source=%s status=%s\n' "$mode" "$transport" "$source_path" "$status"
'''


GRUB_TARGET_BOUNDARY_DRIVER = r'''#!/bin/sh
set -eu
module=$1
work=$2
mode=$3
target_shell=$4
case "$work" in /*) ;; *) exit 125 ;; esac
[ -d "$work" ] && [ ! -L "$work" ] || exit 125
mkdir "$work/bin"
cat >"$work/bin/efibootmgr" <<'MOCK'
#!/bin/sh
root=${0%/bin/*}
printf '%s\n' "$*" >>"$root/mutations"
exit 125
MOCK
cat >"$work/bin/grep" <<'MOCK'
#!/bin/sh
root=${0%/bin/*}
printf '%s\n' "$2" >>"$root/mount-queries"
case "$(cat "$root/mode"):$2" in
  target-path:' /sys/firmware/efi/efivars ') exit 0 ;;
  installer-path:' /fixture/install-root/sys/firmware/efi/efivars ') exit 0 ;;
  *) exit 1 ;;
esac
MOCK
chmod 0755 "$work/bin/efibootmgr" "$work/bin/grep"
printf '%s\n' "$mode" >"$work/mode"
attempt_in_target() {
  shift
  # The timeout belongs to the real caller. Its child gets a clean environment.
  [ "$1" = /usr/bin/timeout ] && [ "$2" = --kill-after=2 ] && [ "$3" = 45 ] || exit 125
  shift 3
  [ "$1" = /bin/sh ] && [ "$2" = -c ] || exit 125
  shift 2
  /usr/bin/env -i PATH="$work/bin:/usr/bin:/bin" LC_ALL=C HOME="$work" \
    "$target_shell" -c "$@" >"$work/child.stdout" 2>"$work/child.stderr"
}
. "$module"
DEV_INSTALL_DISK=$work/missing-disk
DEV_PART_EFI=$work/missing-esp
INSTALLER_GRUB_SHIM_EFI_PATH=/EFI/debian/shimx64.efi
TARGET_ROOT=/fixture/install-root
DIR_SYS=/sys
(
  set -eu
  repair_target_secure_boot_nvram_entry
) &
worker=$!
if wait "$worker"; then status=0; else status=$?; fi
case "$mode" in baseline) expected_status=2 ;; *) expected_status=1 ;; esac
[ "$status" -eq "$expected_status" ] || { cat "$work/child.stderr" >&2; exit 1; }
case "$mode" in
  baseline) /bin/busybox grep -q 'TARGET_ROOT.*not set' "$work/child.stderr" ;;
  installer-path|target-path) /bin/busybox grep -q 'install disk is missing inside target' "$work/child.stderr" ;;
  absent) /bin/busybox grep -q 'target efivars are not mounted' "$work/child.stderr" ;;
  *) exit 125 ;;
esac
[ ! -e "$work/mutations" ]
printf 'PASS grub-target-boundary mode=%s status=%s\n' "$mode" "$status"
'''


CODEX_ARCHIVE_BOUNDARY_DRIVER = r'''#!/usr/bin/python3
from pathlib import Path
import importlib.util
import io
import json
import sys
import tarfile

source, work = Path(sys.argv[1]), Path(sys.argv[2])
baseline = len(sys.argv) > 3 and sys.argv[3] == 'baseline'
if not work.is_absolute() or not work.is_dir() or work.is_symlink():
    raise SystemExit('invalid private archive fixture directory')
spec = importlib.util.spec_from_file_location('private_codex_archive', source)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
for mode in ('success', 'metadata', 'aggregate', 'members', 'duplicate', 'traversal', 'symlink', 'schema'):
    case = work / mode
    case.mkdir(mode=0o700)
    archive = case / 'archive.tar.gz'
    output = case / 'output'
    output.mkdir(mode=0o700)
    with tarfile.open(archive, 'w:gz', format=tarfile.USTAR_FORMAT) as stream:
        def put(name, data=b'', kind=tarfile.REGTYPE):
            member = tarfile.TarInfo(name)
            member.type = kind
            member.mode = 0o755 if name == 'bin/codex' else 0o644
            member.size = len(data)
            if kind == tarfile.SYMTYPE:
                member.linkname = '../escape'
            stream.addfile(member, io.BytesIO(data))
        if mode == 'metadata':
            put('NOTICE', b'x' * 128)
        elif mode == 'aggregate':
            put('NOTICE1', b'x' * 20)
            put('NOTICE2', b'x' * 20)
        elif mode == 'members':
            for index in range(getattr(module, 'MAXIMUM_ARCHIVE_MEMBERS', 16384) + 1):
                put('metadata/entry-' + str(index))
        elif mode == 'traversal':
            put('../escape', b'unsafe')
        elif mode == 'symlink':
            put('bin/link', kind=tarfile.SYMTYPE)
        put('bin/codex', b'#!/bin/sh\nexit 0\n')
        if mode == 'duplicate':
            put('bin/codex', b'duplicate')
        put('config.schema.json', b'invalid' if mode == 'schema' else b'{}')
    expected_failure = mode != 'success'
    if baseline and mode in {'metadata', 'aggregate', 'members'}:
        expected_failure = False
    try:
        module.require_private_empty_directory(output)
        module.require_direct_archive(archive)
        module.extract_archive(archive, output, binary_directory='bin',
                               schema_member='config.schema.json',
                               maximum_extracted_bytes=32 if mode in {'metadata', 'aggregate'} else 1024)
    except module.ArchiveValidationError as error:
        if not expected_failure:
            raise
        if mode in {'metadata', 'aggregate', 'members'}:
            if (output / 'bin/codex').exists() or (output / 'config.schema.json').exists():
                raise AssertionError('archive exceeded its limit after payload publication')
            if not any(text in str(error) for text in ('byte limit', 'too many members')):
                raise
    else:
        if expected_failure:
            raise AssertionError('unsafe archive was accepted: ' + mode)
        if (output / 'bin/codex').read_bytes() != b'#!/bin/sh\nexit 0\n':
            raise AssertionError('valid binary changed')
        if json.loads((output / 'config.schema.json').read_text()) != {}:
            raise AssertionError('valid schema changed')
    if (work / 'escape').exists():
        raise AssertionError('archive escaped its private output')
    print('PASS codex-archive-boundary mode=' + mode + ' baseline=' + str(baseline), flush=True)
print('CODEX_ARCHIVE_RESULT PASS cases=8', flush=True)
'''


class InstallerContracts(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='installer-contract-')
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        # No inherited HOME, session bus, runtime directories or credentials.
        self.environment = {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C', 'HOME': str(self.work)}

    def run_private(self, arguments):
        return subprocess.run(arguments, cwd=self.work, env=self.environment,
                              text=True, capture_output=True, timeout=10)

    def test_codex_archive_limits_include_ignored_metadata_and_headers(self):
        driver = self.work / 'codex-archive-driver.py'
        driver.write_text(CODEX_ARCHIVE_BOUNDARY_DRIVER)
        work = self.work / 'codex-archive-cases'
        work.mkdir(mode=0o700)
        result = self.run_private([sys.executable, '-I', '-B', str(driver),
                                   str(SEED / 'scripts/late/codex-archive.py'), str(work)])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('CODEX_ARCHIVE_RESULT PASS cases=8', result.stdout)

    def test_bootstrap_helper_paths_are_rendered_before_publication(self):
        bootstrap = (SEED / 'scripts/common/bootstrap.sh').read_text()
        logging = (SEED / 'scripts/common/modules/files-logging.sh').read_text()
        bodies = []
        for source, name, closing in [
                (bootstrap, 'bootstrap_fetch_seed_file', ')'),
                *[(logging, name, '}') for name in (
                    'installer_escape_sed_replacement', 'installer_contains_unresolved_path_placeholders',
                    'installer_assert_no_unresolved_path_placeholders',
                    'installer_runtime_path_placeholder_map', 'installer_apply_scalar_placeholders')]]:
            found = re.search(r'^' + name + r'\(\) [({]\n.*?^' + re.escape(closing), source, re.M | re.S)
            self.assertIsNotNone(found, name)
            bodies.append(found[0])
        module = self.work / 'bootstrap-module.sh'
        module.write_text('\n\n'.join(bodies) + '\n')
        driver = self.work / 'bootstrap-driver.sh'
        driver.write_text(BOOTSTRAP_PATH_BOUNDARY_DRIVER)
        for mode, transport in itertools.product(
                ('success', 'unknown', 'render-failure', 'fetch-failure', 'missing-renderer',
                 'passthrough', 'concrete', 'entrypoint', 'catalog'),
                ('common', 'fallback')):
            with self.subTest(mode=mode, transport=transport):
                work = self.work / (mode + '-' + transport)
                work.mkdir(mode=0o700)
                asset, expected = work / 'asset', work / 'expected'
                token = ('__INSTALLER_PATH_UNKNOWN__' if mode == 'unknown'
                         else '__INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__')
                source = 'helper=' + token + '/fixture\n'
                if mode == 'concrete':
                    source = 'already concrete\n'
                elif mode == 'entrypoint':
                    # The pre-common dispatcher contains a literal marker
                    # prefix in its guard; it needs no path renderer yet.
                    source = '# guard prefix: __INSTALLER_PATH_\n'
                asset.write_text(source)
                expected.write_text(source.replace(token, '/usr/local/libexec'))
                source_path = ('scripts/common/credential-data.awk' if mode == 'passthrough'
                               else 'scripts/late/devops-tools.py')
                if mode == 'entrypoint':
                    source_path = 'scripts/late/dispatch.sh'
                elif mode == 'catalog':
                    source_path = 'repo.env'
                result = self.run_private(['/bin/sh', '-eu', str(driver), str(module),
                                           str(SEED / 'hosts/installer/runtime.env'), str(asset),
                                           str(expected), str(work), mode, transport, source_path])
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_grub_target_mount_lookup_receives_installer_spelling(self):
        source = (SEED / 'scripts/late/grub.sh').read_text()
        # This function contains another literal shell function. Its inner
        # closing brace must not truncate the real -c command in the fixture.
        found = re.search(r'^repair_target_secure_boot_nvram_entry\(\) \{\n.*?^\}\n'
                          r'(?=\nqueue_target_grub_mok_enrollment_boot_for_reset\(\))',
                          source, re.M | re.S)
        self.assertIsNotNone(found)
        for mode in ('installer-path', 'target-path', 'absent'):
            with self.subTest(mode=mode):
                work = self.work / mode
                work.mkdir(mode=0o700)
                # Isolated fixture directory only: no EFI devices or firmware
                # are needed to reach and verify the mount-preflight decision.
                (work / 'efivars').mkdir()
                module_source = found[0].replace('__INSTALLER_PATH_DIR_SYS__/firmware/efi/efivars', str(work / 'efivars'))
                module_source = module_source.replace('__INSTALLER_PATH_DIR_SYS__', '/sys')
                for name, value in {'DIR_BIN': '/bin', 'DIR_USR_BIN': '/usr/bin',
                                    'DIR_PROC': '/proc', 'DIR_DEV': '/dev'}.items():
                    module_source = module_source.replace('__INSTALLER_PATH_' + name + '__', value)
                # Keep grep's target mount-table spelling independent from the
                # private directory used by the -d preflight above.
                module_source = module_source.replace('grep -Fqs " ' + str(work / 'efivars') + ' "',
                                                       'grep -Fqs " /sys/firmware/efi/efivars "')
                module = work / 'grub-module.sh'
                module.write_text(module_source)
                driver = work / 'grub-driver.sh'
                driver.write_text(GRUB_TARGET_BOUNDARY_DRIVER)
                result = self.run_private(['/bin/sh', '-eu', str(driver), str(module), str(work), mode, '/bin/sh'])
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_tor_target_shell_passes_paths_and_preserves_verification_failures(self):
        driver = self.work / 'tor-boundary.sh'
        driver.write_text(TOR_TARGET_BOUNDARY_DRIVER)
        source = (SEED / 'scripts/late/tor-browser.sh').read_text()
        for mode in ('success', 'archive', 'key', 'signature', 'fingerprint', 'helper', 'cancel'):
            with self.subTest(mode=mode):
                work = self.work / mode
                work.mkdir(mode=0o700)
                # Relocate only mocked fixture endpoints. The child shell is
                # still the real image's interpreter, with an empty environment.
                module_source = source
                for name, value in {
                        'DIR_BIN': '/bin', 'DIR_USR_BIN': str(work / 'bin'),
                        'DIR_USR_LOCAL_LIBEXEC': str(work / 'libexec'),
                        'DIR_USR_LOCAL_SHARE_SOFTWARE': str(work / 'share'),
                        'DIR_USR_LOCAL_SHARE_APPLICATIONS': str(work / 'applications'),
                        'DIR_OPT_TOR_BROWSER': str(work / 'browser')}.items():
                    module_source = module_source.replace('__INSTALLER_PATH_' + name + '__', value)
                module = work / 'tor-browser.sh'
                module.write_text(module_source)
                result = self.run_private(['/bin/sh', '-eu', str(driver), str(module), str(work), mode, '/bin/sh'])
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('PASS tor-target-boundary ', result.stdout)

    def test_all_driver_toolkit_combinations_use_explicit_matching_classes(self):
        with tarfile.open(ROOT / 'd-i/forky/payload.tar.gz', 'r:gz') as archive:
            for name in ('scripts/common/resolve-plan.awk', 'catalog/compiled/class-plan.tsv'):
                member = archive.getmember(name)
                self.assertTrue(member.isfile())
                self.assertLess(member.size, 8 * 1024 * 1024)
                (self.work / Path(name).name).write_bytes(archive.extractfile(member).read())
        options = ('nvidia', 'nvidia-legacy', 'cuda', 'cuda-legacy')
        for suite, family, bits in itertools.product(('forky', 'trixie'),
                                                      ('desktop', 'server'),
                                                      itertools.product((False, True), repeat=4)):
            chosen = {name for name, enabled in zip(options, bits) if enabled}
            valid = (not {'nvidia', 'nvidia-legacy'} <= chosen
                     and ('cuda' not in chosen or 'nvidia' in chosen)
                     and ('cuda-legacy' not in chosen or 'nvidia-legacy' in chosen))
            role = 'desktop/base' if family == 'desktop' else 'server/devops'
            profile = 'btrfs-de-p15s' if family == 'desktop' else 'btrfs-srv-flex'
            refs = ['site/lab', 'role/' + role, 'arch/amd64', 'cpu/intel', 'kernel/x64v2',
                    'gpu/generic', 'network/dhcp', 'disk/nvme', 'profile/' + family + '/' + profile]
            refs += ['optional/' + name for name in sorted(chosen)]
            arguments = ['awk', '-v', 'suite=' + suite, '-v', 'family=' + family,
                         '-v', 'architecture=amd64', '-v', 'roles=' + role,
                         '-v', 'refs=' + ' '.join(refs), '-v', 'snapshots=none',
                         '-v', 'profile_codex_only=false', '-v', 'profile_whisper_enable=false',
                         '-v', 'profile_llama_enable=false', '-v', 'profile_ssh=false',
                         '-f', str(self.work / 'resolve-plan.awk'), str(self.work / 'class-plan.tsv')]
            with self.subTest(suite=suite, family=family, classes=sorted(chosen)):
                result = self.run_private(arguments)
                self.assertEqual(result.returncode == 0, valid, result.stderr)
                if valid:
                    actual = {line.split('\t')[1].removeprefix('optional/')
                              for line in result.stdout.splitlines() if line.startswith('class\toptional/')}
                    self.assertEqual(actual, chosen)
                    if not chosen & {'cuda', 'cuda-legacy'}:
                        packages = [line.split('\t')[1] for line in result.stdout.splitlines()
                                    if line.startswith('package\t')]
                        self.assertFalse(any(name.startswith('cuda-') for name in packages))
                else:
                    self.assertNotIn('package\t', result.stdout)

    def test_trixie_does_not_purge_required_public_packages(self):
        source = (SEED / 'scripts/desktop/xwayland.sh').read_text()
        functions = []
        for name in ('desktop_xwayland_suite_requires_public_runtime',
                     'desktop_xwayland_remove_public_runtime'):
            found = re.search(r'^' + name + r'\(\) \{\n.*?^\}', source, re.M | re.S)
            self.assertIsNotNone(found)
            functions.append(found[0])
        script = self.work / 'suite-policy.sh'
        script.write_text('\n'.join(functions) + '''
desktop_xwayland_fail() { exit 99; }
desktop_xwayland_assert_public_runtime_absent() { printf 'checked\n'; }
run_in_target_quiet() { printf 'purged\n'; }
TARGET_SUITE=$1
desktop_xwayland_remove_public_runtime
''')
        for suite, expected in (('trixie', 'checked\n'), ('forky', 'purged\nchecked\n')):
            result = self.run_private(['/bin/sh', '-eu', str(script), suite])
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, expected)

    def test_late_unshare_reuses_the_dispatcher_publication_path(self):
        plan = (SEED / 'scripts/common/modules/installation-plan.sh').read_text()
        function = re.search(r'^installer_pre_pkgsel_stage_path\(\) \{\n.*?^\}', plan, re.M | re.S)
        self.assertIsNotNone(function)
        script = self.work / 'stage-path.sh'
        script.write_text(function[0] + '\nDIR_INSTALLER_RUNTIME=$1\ninstaller_pre_pkgsel_stage_path "$2"\n')
        runtime = self.work / 'runtime'
        result = self.run_private(['/bin/sh', '-eu', str(script), str(runtime), 'installer.namespace'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(runtime / 'bootstrap/installer.namespace.sh'))
        for invalid in ('', '../escape', '/absolute', 'stage/escape'):
            result = self.run_private(['/bin/sh', '-eu', str(script), str(runtime), invalid])
            self.assertNotEqual(result.returncode, 0)
        dispatcher = (SEED / 'hooks/installer/pre-pkgsel.d/50-class-plan.sh').read_text()
        consumer = (SEED / 'scripts/late/software.sh.tmpl').read_text()
        self.assertIn('installer_pre_pkgsel_stage_path "$stage_id"', dispatcher)
        self.assertIn('installer_pre_pkgsel_stage_path installer.namespace', consumer)
        self.assertNotIn('/pre-pkgsel.d/89temporary-unshare', consumer)


if __name__ == '__main__':
    unittest.main()
