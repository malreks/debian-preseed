"""Live, redacted target output must preserve status and finish its readers."""
from __future__ import annotations

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation

require_test_isolation()

import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1]

STREAM_SETUP = r'''
set -eu
if command -v tee >/dev/null 2>&1; then exit 95; fi
. "$FIXTURE_SOURCE/scripts/common/modules/runtime-console.sh"
. "$FIXTURE_SOURCE/scripts/common/modules/observability.sh"
. "$FIXTURE_SOURCE/scripts/common/target.sh"
fixture_command() {
  printf 'TTY4_STREAM_READY\n'
  printf 'token=REDACTION_CANARY\n' >&2
  for tick in 1 2 3 4 5; do
    if [ -f "$FIXTURE_ROOT/ack" ]; then
      printf 'TTY4_STREAM_FINISHED\n'
      return 37
    fi
    sleep 1
  done
  return 89
}
target_exec() { fixture_command; }
fixture_run_stream_case() {
  (
    for tick in 1 2 3 4 5; do
      if fixture_console_snapshot | grep -Fq TTY4_STREAM_READY; then
        : >"$FIXTURE_ROOT/ack"
        exit 0
      fi
      sleep 1
    done
    exit 1
  ) &
  fixture_observer=$!
  if target_exec_logged "$FIXTURE_ROOT/output" fixture; then code=0; else code=$?; fi
  wait "$fixture_observer"
  [ "$code" = 37 ]
  grep -Fq TTY4_STREAM_FINISHED "$FIXTURE_ROOT/output"
  grep -Fq token=REDACTION_CANARY "$FIXTURE_ROOT/output"
  fixture_console_snapshot >"$FIXTURE_ROOT/console-snapshot"
  grep -Fq token=REDACTED "$FIXTURE_ROOT/console-snapshot"
  if grep -Fq REDACTION_CANARY "$FIXTURE_ROOT/console-snapshot"; then return 96; fi
  [ -f "$FIXTURE_ROOT/ack" ]
  target_exec() { printf 'capture failure fixture\n'; }
  mkdir "$FIXTURE_ROOT/unwritable-output"
  if target_exec_logged "$FIXTURE_ROOT/unwritable-output" fixture; then code=0; else code=$?; fi
  [ "$code" = 125 ]
  target_exec() { printf 'capture failure with primary command failure\n'; return 37; }
  if target_exec_logged "$FIXTURE_ROOT/unwritable-output" fixture; then code=0; else code=$?; fi
  [ "$code" = 37 ]
  [ -z "$(find "$FIXTURE_ROOT" -type d -name '*.stream.*' -print)" ]
  printf 'STREAM_CONTRACT_PASS status=37 capture_failure=125 live_ack=true redacted=true\n'
}
'''

CONTEXT_SETUP = r'''
set -eu
. "$FIXTURE_SOURCE/scripts/common/modules/runtime-console.sh"
. "$FIXTURE_SOURCE/scripts/common/modules/profiles.sh"
installer_error() { printf '%s\n' "$*" >&2; }
installer_loaded_repo_file_value() {
  case "$1" in
    FILE_COMMON_MOD_PROFILES) printf '%s\n' scripts/common/modules/profiles.sh ;;
    *) return 90 ;;
  esac
}
bootstrap_repo_file_value() {
  [ "$1" = FILE_COMMON_CREDENTIAL_DATA ] || return 90
  printf '%s/scripts/common/credential-data.awk\n' "$FIXTURE_SOURCE"
}
bootstrap_parser_asset_path() { printf '%s\n' "$1"; }
installer_repo_asset_path() {
  [ "$1" = DIR_CATALOG_COMPILED ] || return 90
  printf '%s/profile.env\n' "$FIXTURE_ROOT"
}
installer_fetch_seed_path() {
  [ "$2" = "$FIXTURE_ROOT/profile.env" ] || return 91
  case "$3" in "$FIXTURE_ROOT"/fetched*.env) ;; *) return 91 ;; esac
  cp "$2" "$3" && chmod "$4" "$3"
}
INSTALLER_SUITE=forky
INSTALLER_HOST_VARIANT=desktop
INSTALLER_HOST_PROFILE_ENV_NAME=fixture
installer_operation_context fixture-caller.sh 73 caller_operation
installer_fetch_host_env fixture fixture "$FIXTURE_ROOT/fetched.env" 0600
[ "$INSTALLER_FAILURE_SOURCE:$INSTALLER_FAILURE_LINE:$INSTALLER_FAILURE_OPERATION" = fixture-caller.sh:73:caller_operation ]
installer_load_data_env "$FIXTURE_ROOT/fetched.env"
[ "$INSTALLER_FAILURE_SOURCE:$INSTALLER_FAILURE_LINE:$INSTALLER_FAILURE_OPERATION" = fixture-caller.sh:73:caller_operation ]
[ "$PROBE_VALUE" = fixture ]
unset INSTALLER_FAILURE_SOURCE INSTALLER_FAILURE_LINE INSTALLER_FAILURE_OPERATION
installer_fetch_host_env fixture fixture "$FIXTURE_ROOT/fetched-empty.env" 0600
[ "${INSTALLER_FAILURE_SOURCE+x}${INSTALLER_FAILURE_LINE+x}${INSTALLER_FAILURE_OPERATION+x}" = '' ]
installer_load_data_env "$FIXTURE_ROOT/fetched-empty.env"
[ "${INSTALLER_FAILURE_SOURCE+x}${INSTALLER_FAILURE_LINE+x}${INSTALLER_FAILURE_OPERATION+x}" = '' ]
printf '%s\n' 'PROBE_VALUE=$(false)' >"$FIXTURE_ROOT/invalid.env"
if installer_load_data_env "$FIXTURE_ROOT/invalid.env"; then exit 94; fi
[ "$INSTALLER_FAILURE_SOURCE" = scripts/common/modules/profiles.sh ]
[ "$INSTALLER_FAILURE_OPERATION" = load_data_env ]
printf 'CONTEXT_CONTRACT_PASS restored=true absent_preserved=true parser_failure_context=true\n'
'''


class InstallerProgress(unittest.TestCase):
    def fixture_environment(self, root: Path) -> dict[str, str]:
        # These links resolve only within the isolated test image. Deliberately
        # omit tee so a normal full-system PATH cannot hide installer regressions.
        tools = root / 'tools'
        tools.mkdir(mode=0o700)
        for name in ('awk', 'cat', 'chmod', 'cp', 'find', 'grep', 'mkdir',
                     'mktemp', 'rm', 'rmdir', 'sleep', 'wc'):
            executable = shutil.which(name, path='/usr/bin:/bin')
            if executable is None:
                self.skipTest(f'isolated fixture image lacks required tool: {name}')
            (tools / name).symlink_to(executable)
        return {'PATH': str(tools), 'LC_ALL': 'C', 'HOME': str(root),
                'FIXTURE_SOURCE': str(SOURCE), 'FIXTURE_ROOT': str(root)}

    def test_progress_is_live_redacted_and_preserves_command_failure(self) -> None:
        with tempfile.TemporaryDirectory(prefix='installer-progress-') as temporary:
            root = Path(temporary)
            (root / 'console').write_text('', encoding='ascii')
            code = STREAM_SETUP + r'''
# This isolated case uses a private regular-file console transport.
# Native tty4 behavior requires separately authorized integration evidence.
installer_stream_tty4() { installer_redact_log_stream >"$FIXTURE_ROOT/console"; }
fixture_console_snapshot() { cat "$FIXTURE_ROOT/console"; }
fixture_run_stream_case
'''
            result = subprocess.run(['/bin/sh', '-eu', '-c', code], cwd=root,
                env=self.fixture_environment(root),
                capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('STREAM_CONTRACT_PASS', result.stdout)

    def test_relay_keeps_text_bytes_and_command_status_without_tee(self) -> None:
        for status in (0, 37):
            with self.subTest(status=status), tempfile.TemporaryDirectory(prefix='installer-text-') as temporary:
                root = Path(temporary)
                environment = self.fixture_environment(root)
                environment['FIXTURE_STATUS'] = str(status)
                code = STREAM_SETUP + r'''
target_exec() {
  printf '%s\n' '  leading\path  ' ''
  printf '%s' 'unterminated\tail'
  return "$FIXTURE_STATUS"
}
installer_stream_tty4() { cat >/dev/null; }
if target_exec_logged "$FIXTURE_ROOT/output" fixture; then code=0; else code=$?; fi
[ "$code" = "$FIXTURE_STATUS" ]
'''
                result = subprocess.run(['/bin/sh', '-eu', '-c', code], cwd=root,
                    env=environment, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual((root / 'output').read_bytes(), b'  leading\\path  \n\nunterminated\\tail')
                self.assertFalse(list(root.glob('*.stream.*')))

    def test_closed_console_does_not_truncate_capture_or_change_command_status(self) -> None:
        with tempfile.TemporaryDirectory(prefix='installer-console-') as temporary:
            root = Path(temporary)
            code = STREAM_SETUP + r'''
target_exec() {
  line=0
  while [ "$line" -lt 2048 ]; do
    printf '%s\n' 'complete capture must survive the diagnostic console reader closing its pipe'
    line=$((line + 1))
  done
  return 37
}
installer_stream_tty4() { IFS= read -r first_line || :; }
if target_exec_logged "$FIXTURE_ROOT/output" fixture; then code=0; else code=$?; fi
[ "$code" = 37 ]
'''
            result = subprocess.run(['/bin/sh', '-eu', '-c', code], cwd=root,
                env=self.fixture_environment(root), capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len((root / 'output').read_bytes().splitlines()), 2048)
            self.assertFalse(list(root.glob('*.stream.*')))

    def test_successful_profile_operations_restore_the_callers_failure_context(self) -> None:
        with tempfile.TemporaryDirectory(prefix='installer-context-') as temporary:
            root = Path(temporary)
            (root / 'profile.env').write_text("PROBE_VALUE='fixture'\n", encoding='ascii')
            result = subprocess.run(['/bin/sh', '-eu', '-c', CONTEXT_SETUP], cwd=root,
                env=self.fixture_environment(root), capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('CONTEXT_CONTRACT_PASS', result.stdout)
