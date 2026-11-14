"""Live, redacted target output must preserve status and finish its readers."""
from __future__ import annotations

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation

require_test_isolation()

import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1]

STREAM_SETUP = r'''
set -eu
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
  [ -z "$(find "$FIXTURE_ROOT" -type d -name '*.stream.*' -print)" ]
  printf 'STREAM_CONTRACT_PASS status=37 capture_failure=125 live_ack=true redacted=true\n'
}
'''


class InstallerProgress(unittest.TestCase):
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
                env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C', 'HOME': temporary,
                     'FIXTURE_SOURCE': str(SOURCE), 'FIXTURE_ROOT': temporary},
                capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('STREAM_CONTRACT_PASS', result.stdout)
