"""Guest-only runtime observation fixtures; no real service, key or device access.

The server command boundary is mocked. SSH metadata commands inspect only this
fixture's private tree and model the account identity, so these cases test the
production parser and call counts without contacting NSS or an SSH agent.
"""
from __future__ import annotations

# Refuse host execution before importing runtime helpers or creating fixtures.
from pathlib import Path as _IsolationPath
import sys as _isolation_sys
_isolation_sys.path.insert(0, str(_IsolationPath(__file__).resolve().parents[3] / 'tools'))
# Copied checker/GUI fixtures still use the verified private checkout gate.
_isolation_sys.path.insert(0, '/workspace/repository/tools')
from isolation import require_test_isolation as _require_test_isolation
_isolation_sys.path.pop(0)
_require_test_isolation()

import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import types
import unittest
from unittest.mock import Mock, patch

TARGET = Path(__file__).resolve().parents[1] / 'hooks/target'
SERVER = TARGET / 'usr/local/libexec/server/installer-serverctl.py.tmpl'
SSH_CHECKS = TARGET / 'usr/local/libexec/common/ssh-checks'


class ServerStoppedObservationTests(unittest.TestCase):
    def setUp(self):
        self.module = types.ModuleType('server_observation_fixture')
        exec(compile(SERVER.read_bytes(), str(SERVER), 'exec'), self.module.__dict__)
        self.command = Mock(return_value=b'ActiveState=inactive\nMainPID=0\n')
        self.workload = Mock()
        for name, replacement in (('command', self.command),
                                  ('dns_workload', Mock(return_value=self.workload))):
            replacement_patch = patch.object(self.module, name, replacement)
            replacement_patch.start()
            self.addCleanup(replacement_patch.stop)

    def test_one_named_query_accepts_both_stopped_states_in_either_order(self):
        for state in ('inactive', 'failed'):
            for value in (f'ActiveState={state}\nMainPID=0\n',
                          f'MainPID=0\nActiveState={state}\n'):
                with self.subTest(value=value):
                    self.command.reset_mock()
                    self.workload.reset_mock()
                    self.command.return_value = value.encode('ascii')
                    self.module.require_stopped('server/technitium')
                    self.command.assert_called_once_with(
                        ['/usr/bin/systemctl', 'show', 'technitium.service',
                         '--property=ActiveState,MainPID'], timeout=15)
                    self.workload.stopped.assert_called_once_with()

    def test_running_state_and_unknown_leader_never_reach_guest_check(self):
        for state in ('active', 'activating', 'deactivating', 'reloading', '', 'unknown'):
            with self.subTest(state=state):
                self.command.return_value = f'ActiveState={state}\nMainPID=0\n'.encode('ascii')
                with self.assertRaisesRegex(ValueError, 'stop the selected service'):
                    self.module.require_stopped('server/technitium')
        for pid in ('7', '', '-1', 'not-a-pid', '0 '):
            with self.subTest(pid=pid):
                self.command.return_value = f'ActiveState=inactive\nMainPID={pid}\n'.encode('ascii')
                with self.assertRaises(self.module.OutcomeUnknown):
                    self.module.require_stopped('server/technitium')
        self.workload.stopped.assert_not_called()

    def test_missing_duplicate_unknown_and_malformed_properties_fail_closed(self):
        for value in (b'', b'ActiveState=inactive\n', b'MainPID=0\n',
                      b'ActiveState=inactive\nMainPID=0\nMainPID=0\n',
                      b'ActiveState=inactive\nActiveState=active\nMainPID=0\n',
                      b'ActiveState=inactive\nMainPID=0\nLoadState=loaded\n',
                      b'ActiveState=inactive\nMainPID=0\n\n',
                      b'ActiveState inactive\nMainPID=0\n'):
            with self.subTest(value=value):
                self.command.return_value = value
                with self.assertRaisesRegex(ValueError, 'state response'):
                    self.module.require_stopped('server/technitium')
        self.workload.stopped.assert_not_called()

    def test_later_operation_queries_again_and_observes_changed_service_state(self):
        self.command.side_effect = [b'ActiveState=inactive\nMainPID=0\n',
                                    b'MainPID=41\nActiveState=active\n']
        self.module.require_stopped('server/technitium')
        with self.assertRaisesRegex(ValueError, 'stop the selected service'):
            self.module.require_stopped('server/technitium')
        self.assertEqual(self.command.call_count, 2)
        self.workload.stopped.assert_called_once_with()

    def test_command_and_guest_failures_propagate(self):
        self.command.side_effect = TimeoutError('fixture command deadline')
        with self.assertRaisesRegex(TimeoutError, 'fixture command deadline'):
            self.module.require_stopped('server/technitium')
        self.workload.stopped.assert_not_called()
        self.command.side_effect = None
        self.workload.stopped.side_effect = self.module.OutcomeUnknown('fixture guest process remains')
        with self.assertRaisesRegex(self.module.OutcomeUnknown, 'fixture guest process remains'):
            self.module.require_stopped('server/technitium')

    def test_role_without_service_is_rejected_before_query(self):
        with self.assertRaisesRegex(ValueError, 'no maintained DNS service'):
            self.module.require_stopped('server/devops')
        self.command.assert_not_called()
        self.workload.stopped.assert_not_called()

    def test_other_maintained_service_keeps_its_host_check_only(self):
        self.module.require_stopped('server/github-actions')
        self.command.assert_called_once_with(
            ['/usr/bin/systemctl', 'show', 'ci-github.service',
             '--property=ActiveState,MainPID'], timeout=15)
        self.workload.stopped.assert_not_called()


class SSHContextObservationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='ssh-observation-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.home = self.root / 'home/fixture'
        self.directories = [self.home, self.home / '.local', self.home / '.local/share',
                            self.home / '.local/share/ssh', self.home / '.local/share/ssh/private',
                            self.home / '.ssh', self.home / '.gnupg']
        for index, directory in enumerate(self.directories):
            directory.mkdir(parents=True, exist_ok=True)
            directory.chmod(0o750 if index < 3 else 0o700)
        self.private = self.home / '.local/share/ssh/private/id_git_ed25519'
        self.public = self.home / '.ssh/id_git_ed25519.pub'
        self.blob = self.home / '.local/share/ssh/git-key-passphrase.gpg'
        for path in (self.private, self.public, self.blob):
            path.write_text('inert fixture data\n')
            path.chmod(0o644 if path == self.public else 0o600)
        self.calls = self.root / 'metadata-calls.jsonl'
        self.overrides = self.root / 'metadata-overrides.json'
        self.overrides.write_text('{}')
        binary = self.root / 'usr/bin'
        binary.mkdir(parents=True)
        identity = 1000
        scripts = {
            'id': "#!/bin/sh\nprintf '%s\\n' 1000\n",
            'getent': "#!/bin/sh\nprintf '%s\\n' " + shlex.quote(
                f'fixture:x:{identity}:{identity}:fixture:{self.home}:/bin/sh') + '\n',
            'find': f'''#!/usr/bin/python3 -IB
import json
import os
from pathlib import Path
import stat
import sys

args = sys.argv[1:]
if len(args) != 6 or args[0] != '-P' or args[2:5] != ['-maxdepth', '0', '-printf']:
    raise SystemExit(64)
path, form = args[1], args[5]
with open({str(self.calls)!r}, 'a', encoding='utf-8') as stream:
    stream.write(json.dumps([path, form]) + '\\n')
change = json.loads(Path({str(self.overrides)!r}).read_text()).get(path, {{}})
info = os.lstat(path)
uid = str(change.get('uid', {identity} if info.st_uid == {os.geteuid()} else info.st_uid))
mode = format(stat.S_IMODE(info.st_mode), 'o')
values = {{'%U': uid, '%m': mode, '%U:%m': uid + ':' + mode,
          '%U:%n:%m': uid + ':' + str(info.st_nlink) + ':' + mode}}
if form not in values:
    raise SystemExit(64)
sys.stdout.write(change.get('raw', values[form]))
raise SystemExit(change.get('status', 0))
''',
        }
        for name, script in scripts.items():
            path = binary / name
            path.write_text(script)
            path.chmod(0o700)
        # Only the guest's cut reads fixture stdin. NSS, find and id are all
        # private recording adapters; none can inspect a real account or key.
        (binary / 'cut').symlink_to('/usr/bin/cut')
        self.helper = self.root / 'ssh-checks'
        self.helper.write_text(SSH_CHECKS.read_text().replace(
            '__INSTALLER_PATH_DIR_USR__', str(self.root / 'usr')).replace(
            '__INSTALLER_PATH_DIR_HOME__', str(self.root / 'home')).replace(
            '__INSTALLER_PATH_DIR_RUN_USER__', str(self.root / 'run/user')))

    def context(self):
        return subprocess.run(['/bin/sh', '-c',
                               '. "$1"\nmanaged_ssh_context && printf "%s\\n" '
                               '"$private" "$public" "$blob" "$GNUPGHOME"',
                               'ssh-context-fixture', str(self.helper)],
                              env={'PATH': '/usr/bin:/bin', 'HOME': str(self.home),
                                   'TMPDIR': str(self.root), 'TMP': str(self.root), 'TEMP': str(self.root)},
                              cwd=self.root, capture_output=True, text=True, timeout=10)

    def test_one_owner_mode_observation_per_directory_preserves_identity_exports(self):
        result = self.context()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [str(self.private), str(self.public),
                                                     str(self.blob), str(self.home / '.gnupg')])
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual(calls[:7], [[str(path), '%U:%m'] for path in self.directories])
        self.assertEqual(calls[7:], [[str(path), '%U:%n:%m']
                                    for path in (self.private, self.blob, self.public)])

    def test_foreign_owner_unsafe_mode_and_private_directory_mode_are_rejected(self):
        for change in ({'uid': 0}, {'uid': 2000}):
            with self.subTest(change=change):
                self.overrides.write_text(json.dumps({str(self.directories[2]): change}))
                self.assertNotEqual(self.context().returncode, 0)
        self.overrides.write_text('{}')
        for directory, mode in ((self.home, 0o777), (self.directories[3], 0o750)):
            before = directory.stat().st_mode & 0o7777
            try:
                directory.chmod(mode)
                self.assertNotEqual(self.context().returncode, 0)
            finally:
                directory.chmod(before)

    def test_ambiguous_metadata_and_nonzero_command_status_fail_closed(self):
        for change in ({'raw': '1000:700:extra'}, {'raw': '1000:700\n1000:700'},
                       {'raw': ''}, {'raw': '1000:0700'}, {'status': 7}):
            with self.subTest(change=change):
                self.overrides.write_text(json.dumps({str(self.directories[-1]): change}))
                self.assertNotEqual(self.context().returncode, 0)

    def test_symlink_directory_and_hardlinked_key_are_rejected(self):
        original = self.root / 'saved-ssh'
        self.public.parent.rename(original)
        self.public.parent.symlink_to(original, target_is_directory=True)
        self.assertNotEqual(self.context().returncode, 0)
        self.public.parent.unlink()
        original.rename(self.public.parent)
        os.link(self.private, self.root / 'private-link')
        self.assertNotEqual(self.context().returncode, 0)

    def test_next_context_rechecks_changed_permissions(self):
        self.assertEqual(self.context().returncode, 0)
        self.directories[-1].chmod(0o755)
        self.assertNotEqual(self.context().returncode, 0)


class SharedHardwareEntrypointTests(unittest.TestCase):
    def family_member(self, family, member):
        seed = Path(__file__).resolve().parents[1]
        script = r'''
set -eu
. "$1/scripts/common/source.sh"
. "$1/scripts/common/modules/repository-apt.sh"
installer_fatal() { printf '%s\n' "$*" >&2; exit 1; }
INSTALLER_SUITE=forky
source_load_repo_env "$1/repo.env"
INSTALLER_REPO_ENV_READY=1
INSTALLER_HOST_VARIANT=$2
installer_repo_assert_asset_family "$3"
[ -f "$1/$3" ] && [ ! -L "$1/$3" ]
'''
        return subprocess.run(['/bin/sh', '-c', script, 'hardware-family-fixture',
                               str(seed), family, member],
                              capture_output=True, text=True, timeout=10)

    def test_shared_cli_has_one_common_owner_and_both_roles_accept_it(self):
        member = 'hooks/target/usr/local/bin/common/labwc-hardware-tuning'
        self.assertFalse((TARGET / 'usr/local/bin/desktop/labwc-hardware-tuning').exists())
        for family in ('desktop', 'server'):
            with self.subTest(family=family):
                result = self.family_member(family, member)
                self.assertEqual(result.returncode, 0, result.stderr)
        stage = (TARGET.parents[1] / 'scripts/common/hardware-tuning.sh').read_text()
        self.assertIn('profile_hardware_stage_asset ' + member +
                      ' __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-hardware-tuning 0755', stage)

    def test_server_still_rejects_desktop_only_management_entrypoint(self):
        result = self.family_member('server',
                                    'hooks/target/usr/local/bin/desktop/labwc-computer-management')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('incompatible or missing role family', result.stderr)


if __name__ == '__main__':
    unittest.main()
