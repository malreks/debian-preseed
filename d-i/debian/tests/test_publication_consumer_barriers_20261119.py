"""Queued-publication consumer regressions; approved isolated guests only.

Only the three reviewed shell consumers are loaded. Their publication and
target-execution dependencies are private fixture adapters, and every mutable
path is below one exclusive guest /var/lib/publication-consumers-* directory.
These fixtures do not execute an installer, service, package manager or target
setup program. The repository isolation guard still applies before discovery.
"""
from __future__ import annotations

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation
require_test_isolation()

import os
import re
import subprocess
import tempfile
import unittest


DEBIAN = Path(__file__).resolve().parents[1]
PATH_VALUES = {
    'DIR_ETC': '/etc',
    'DIR_SYSTEMD_SYSTEM_RSYSLOG_DROPIN': '/etc/systemd/system/rsyslog.service.d',
}


def shell_function(relative: str, name: str) -> str:
    source = (DEBIAN / relative).read_text(encoding='utf-8')
    matches = list(re.finditer(r'^' + re.escape(name) + r'\(\) \{\n.*?^\}\n',
                               source, re.MULTILINE | re.DOTALL))
    if len(matches) != 1:
        raise AssertionError('fixture requires exactly one function: ' + name)
    return re.sub(r'__INSTALLER_PATH_([A-Z0-9_]+)__',
                  lambda match: PATH_VALUES[match[1]], matches[0][0])


PRELUDE = r'''
root=$1
flush_status=$2
TARGET_ROOT=$root/target
events=$root/events
queue=$root/queue
DIR_USR_LOCAL_LIBEXEC=/usr/local/libexec
: >"$events"
: >"$queue"
installer_fatal() { printf 'fatal:%s\n' "$*" >>"$events"; return 99; }
installer_repo_file_value() { printf '%s\n' "$1"; }
installer_repo_asset_path() { printf '%s\n' "$2"; }
target_asset_host_path() { printf '%s%s\n' "$TARGET_ROOT" "$1"; }
installer_asset_batch_begin() { :; }
stage_target_asset() {
    printf '%s\t%s\n' "$2" "$3" >>"$queue"
    printf 'queued\n' >>"$events"
}
installer_asset_batch_flush() {
    printf 'flush\n' >>"$events"
    [ "$flush_status" -eq 0 ] || return "$flush_status"
    while IFS="$(printf '\t')" read -r destination mode; do
        [ -n "$destination" ] || continue
        mkdir -p -- "$TARGET_ROOT${destination%/*}"
        printf 'published fixture\n' >"$TARGET_ROOT$destination"
        chmod "$mode" "$TARGET_ROOT$destination"
    done <"$queue"
    : >"$queue"
}
installer_asset_batch_finish() {
    printf 'finish\n' >>"$events"
    installer_asset_batch_flush
}
installer_metadata_value() {
    /usr/bin/stat -c '%u:%g:%a:%h' -- "$1"
}
target_asset_assert_no_unresolved_installer_placeholders() {
    [ "$(cat "$1")" = 'published fixture' ] || return 91
    printf 'inspect\n' >>"$events"
}
desktop_assert_no_unresolved_template_placeholders() {
    target_asset_assert_no_unresolved_installer_placeholders "$@"
}
installer_run_target_setup() {
    [ "$(cat "$TARGET_ROOT$3")" = 'published fixture' ] || return 92
    printf 'setup\n' >>"$events"
}
'''


class PublicationConsumerBarrierTests(unittest.TestCase):
    def setUp(self):
        if os.geteuid() != 0:
            self.skipTest('the isolated publication fixture requires guest root ownership')
        self.temporary = tempfile.TemporaryDirectory(prefix='publication-consumers-', dir='/var/lib')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'target').mkdir(mode=0o700)
        (self.root / 'tmp').mkdir(mode=0o700)

    def run_consumer(self, functions: str, invocation: str, *, failure: int = 0,
                     argument: str = '/etc/tmpfiles.d/fixture.conf'):
        script = self.root / 'consumer.sh'
        script.write_text(PRELUDE + '\n' + functions + '\n' + invocation + '\n')
        environment = {
            'PATH': '/usr/bin:/bin', 'LC_ALL': 'C',
            'TMPDIR': str(self.root / 'tmp'), 'TMP': str(self.root / 'tmp'),
            'TEMP': str(self.root / 'tmp'),
        }
        result = subprocess.run(['/bin/sh', '-eu', str(script), str(self.root),
                                 str(failure), argument], cwd=self.root, env=environment,
                                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=15, check=False)
        return result, (self.root / 'events').read_text().splitlines()

    def tmpfiles_functions(self):
        return ''.join(shell_function('scripts/late/storage-maintenance.sh', name)
                       for name in ('validate_target_tmpfiles_policy_path',
                                    'normalize_target_tmpfiles_directory_policy'))

    def test_fresh_tmpfiles_consumers_publish_before_their_readability_check(self):
        for leaf in ('75-desktop-pool-storage.conf', '40-network-profiles.conf',
                     '50-desktop-var-cache.conf', 'man-db.conf'):
            with self.subTest(policy=leaf):
                path = '/etc/tmpfiles.d/' + leaf
                self.assertFalse((self.root / 'target' / path.lstrip('/')).exists())
                result, events = self.run_consumer(
                    self.tmpfiles_functions(),
                    'stage_target_asset fixture "$3" 0644\n'
                    'normalize_target_tmpfiles_directory_policy "$3" fixture', argument=path)
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                self.assertEqual(events, ['queued', 'flush', 'setup'])

    def test_failed_tmpfiles_publication_does_not_use_an_existing_stale_policy(self):
        path = self.root / 'target/etc/tmpfiles.d/fixture.conf'
        path.parent.mkdir(parents=True)
        path.write_text('previous policy\n')
        result, events = self.run_consumer(
            self.tmpfiles_functions(),
            'stage_target_asset fixture "$3" 0644\n'
            'normalize_target_tmpfiles_directory_policy "$3" fixture', failure=71)
        self.assertEqual(result.returncode, 71, result.stderr.decode())
        self.assertEqual(events, ['queued', 'flush'])
        self.assertEqual(path.read_text(), 'previous policy\n')

    def test_logging_foundation_publishes_before_metadata_and_token_checks(self):
        result, events = self.run_consumer(
            shell_function('scripts/late/target-assets.sh', 'stage_target_logging_foundation'),
            'stage_target_logging_foundation')
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(events, ['queued'] * 5 + ['flush'] + ['inspect'] * 5
                         + ['queued'] * 5 + ['finish', 'flush'])
        self.assertEqual(len([path for path in (self.root / 'target').rglob('*')
                              if path.is_file()]), 10)

    def test_logging_publication_failure_stops_before_any_validation(self):
        result, events = self.run_consumer(
            shell_function('scripts/late/target-assets.sh', 'stage_target_logging_foundation'),
            'stage_target_logging_foundation', failure=71)
        self.assertEqual(result.returncode, 71, result.stderr.decode())
        self.assertEqual(events, ['queued'] * 5 + ['flush'])
        self.assertFalse(any(path.is_file() for path in (self.root / 'target').rglob('*')))

    def test_deferred_desktop_assertion_checks_the_new_candidate(self):
        result, events = self.run_consumer(
            shell_function('scripts/desktop/components/devices-network.sh',
                           'desktop_assert_role_target_template_resolved'),
            'stage_target_asset fixture "$3" 0644\n'
            'desktop_assert_role_target_template_resolved fixture "$3"',
            argument='/etc/skel-desktop/.config/labwc/rc.xml')
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(events, ['queued', 'flush', 'inspect'])

    def test_deferred_desktop_assertion_propagates_publication_failure(self):
        result, events = self.run_consumer(
            shell_function('scripts/desktop/components/devices-network.sh',
                           'desktop_assert_role_target_template_resolved'),
            'stage_target_asset fixture "$3" 0644\n'
            'desktop_assert_role_target_template_resolved fixture "$3"', failure=71)
        self.assertEqual(result.returncode, 71, result.stderr.decode())
        self.assertEqual(events, ['queued', 'flush'])


if __name__ == '__main__':
    unittest.main()
