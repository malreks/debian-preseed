#!/usr/bin/python3
"""Native contract fixture; run only in the reviewed disconnected QEMU image.

The real renderer, policy-map producers, runtime configuration reader and final
ownership scanner run together. No network, service or firewall operation runs.
All absolute target files below belong to this disposable guest, never the host.
"""
from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


SOURCE = Path('/snapshot/source')
WORK = Path('/cases/app-veth')
RULESET_SOURCE = 'hooks/target/etc/app-veth.nft.tmpl'
PROGRAM_SOURCE = 'hooks/target/usr/local/sbin/desktop/app-veth'
POLICY_SOURCE = 'hooks/target/usr/local/lib/desktop/python3/dist-packages/app_veth_policy.py'
RUNTIME_FIELDS = ('APP_INTERFACES', 'DNS_ADDRESS', 'DNS_HOST_ADDRESS', 'DNS_HOST_PORT')


def run(argv: list[str], *, env: dict | None = None) -> subprocess.CompletedProcess:
    result = subprocess.run(argv, env=ENV if env is None else env, stdin=subprocess.DEVNULL,
                            capture_output=True, timeout=30, check=False)
    assert len(result.stdout) + len(result.stderr) < 1048576, 'excessive fixture output'
    return result


def profile_values(path: Path) -> dict[str, str]:
    values = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        match = re.fullmatch(r"([A-Z][A-Z0-9_]*)='([^']*)'", line)
        assert match and match[1] not in values, 'unsupported compiled data row'
        values[match[1]] = match[2]
    return values


def render(source: str, destination: Path, values: dict[str, str]) -> str:
    private = WORK / ('render-' + str(len(list(WORK.glob('render-*')))))
    private.mkdir(mode=0o700)
    (private / 'input').write_bytes((SOURCE / source).read_bytes())
    (private / 'map').write_text(''.join(f'{key}={value}\n' for key, value in values.items()),
                                encoding='utf-8')
    result = run(['/usr/bin/perl', str(WORK / 'renderer/render.pl'), '--file', str(private), 'scalar'])
    assert result.returncode == 0, result.stderr
    data = (private / 'output').read_text(encoding='utf-8')
    assert not re.search(r'__INSTALLER_[A-Za-z0-9_]+__', data), source
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(data, encoding='utf-8')
    destination.chmod(0o644)
    return data


def scan(awk: list[str], rows: list[tuple[str, str]], *, registry: Path | None = None):
    inventory = WORK / 'owned.tsv'
    inventory.write_text(''.join(f'{dest}\t{source}\ttemplate\tlate\t0644\n'
                                 for dest, source in rows), encoding='utf-8')
    return run([*awk, '-v', 'target_root=', '-v', 'registry=' + str(
        registry or SOURCE / 'catalog/placeholder-registry.tsv'), '-f',
        str(SOURCE / 'scripts/common/target-owned-scan.awk'), str(inventory)])


assert Path('/snapshot/installer-stage-review-image').read_text(encoding='ascii') == 'disconnected-qemu-v1\n'
assert not WORK.exists(), 'retain previous evidence instead of replacing it'
os.umask(0o077)
WORK.mkdir(mode=0o700)
ENV = {'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'HOME': str(WORK),
       'TMPDIR': str(WORK), 'TMP': str(WORK), 'TEMP': str(WORK), 'LC_ALL': 'C', 'LANG': 'C'}
(WORK / 'renderer/inputs').mkdir(parents=True)
shutil.copyfile(SOURCE / 'scripts/common/render.pl', WORK / 'renderer/render.pl')
path_rows = [line.split('\t') for line in (SOURCE / 'catalog/runtime-paths.tsv').read_text(
    encoding='utf-8').splitlines() if line and not line.startswith('#')]
with Path('/etc/passwd').open('a', encoding='ascii') as stream:
    stream.write('fixture:x:1000:1000:Fixture:/cases/app-veth:/bin/sh\n')
checks = 0
baseline = False
module = None
for suite, profile in (('forky', 'desktop/btrfs-de-p15s'), ('trixie', 'desktop/f2fs-de-hp14')):
    values = profile_values(SOURCE / f'catalog/compiled/{suite}/profiles/{profile}.env')
    paths = {key: values[variable] for key, variable in path_rows}
    (WORK / 'renderer/inputs/paths.map').write_text(''.join(
        f'{key}={value}\n' for key, value in paths.items()), encoding='utf-8')
    for shell in (['/bin/dash'], ['/bin/busybox', 'sh']):
        for role in ('base', 'medium', 'full'):
            child_env = {**ENV, **{k: v for k, v in values.items()
                         if k.startswith(('APP_VETH_', 'PROXY3_')) or k == 'LABWC_QBITTORRENT_PORT'},
                         'INSTALLER_DESKTOP_ROLE': 'desktop/' + role}
            maps = {}
            for function in ('app_veth_identity_placeholder_map', 'proxy3_placeholder_map'):
                result = run([*shell, '-eu', '-c', '. "$1"; ' + function, 'fixture-map',
                              str(SOURCE / 'scripts/common/modules/app-veth-identity.sh')], env=child_env)
                assert result.returncode == 0, result.stderr
                for line in result.stdout.decode('ascii').splitlines():
                    key, value = line.split('=', 1)
                    assert key not in maps
                    maps[key] = value
            rules = render(RULESET_SOURCE, Path('/etc/app-veth.nft'), maps)
            render(PROGRAM_SOURCE, Path('/usr/local/sbin/app-veth'), {})
            render(POLICY_SOURCE, WORK / 'app_veth_policy.py', {})
            maps['ACCOUNT_USERNAME'] = 'fixture'
            render('hooks/target/etc/app-veth.json.tmpl', Path('/etc/app-veth.json'), maps)
            if module is None:
                sys.path.insert(0, str(WORK))
                loader = importlib.machinery.SourceFileLoader('fixture_app_veth', '/usr/local/sbin/app-veth')
                spec = importlib.util.spec_from_loader(loader.name, loader)
                module = importlib.util.module_from_spec(spec)
                loader.exec_module(module)
                def forbidden(*_args, **_kwargs):
                    raise AssertionError('configuration validation attempted a mutation')
                module.run = forbidden
            uid, policies = module.configuration(activate=True)
            assert uid == 1000 and policies
            assert not re.search(r'__[A-Z][A-Z0-9_]*__', module.RULESET)
            assert '__INSTALLER_' not in module.RULESET
            assert module.NETWORK_SETTINGS['dns_address'] in module.RULESET
            assert str(module.NETWORK_SETTINGS['dns_host_port']) in module.RULESET
            rows = [('/etc/app-veth.nft', RULESET_SOURCE),
                    ('/usr/local/sbin/app-veth', PROGRAM_SOURCE),
                    ('/etc/app-veth.json', 'hooks/target/etc/app-veth.json.tmpl'),
                    (str(WORK / 'app_veth_policy.py'), POLICY_SOURCE)]
            for awk in (['/usr/bin/mawk'], ['/bin/busybox', 'awk']):
                result = scan(awk, rows)
                assert result.returncode == 0, result.stdout + result.stderr
                if not baseline:
                    old = scan(awk, rows[:1], registry=Path('/snapshot/before/placeholder-registry.tsv'))
                    assert old.returncode != 0 and old.stdout.count(b'unresolved target marker') == 12
                    print('BASELINE_REPRODUCED app-veth runtime markers rejected=12', flush=True)
                    baseline = True
                checks += 1
            print(f'PASS runtime suite={suite} profile={profile} shell={shell[0]} role={role} apps={len(policies)}',
                  flush=True)

Path('/snapshot/rendered-app-veth.nft').write_text(rules, encoding='ascii')
probe = WORK / 'unrelated.nft'
for field in RUNTIME_FIELDS:
    probe.write_text('__' + field + '__\n', encoding='ascii')
    for awk in (['/usr/bin/mawk'], ['/bin/busybox', 'awk']):
        result = scan(awk, [(str(probe), 'generated')])
        assert result.returncode != 0 and b'unresolved target marker' in result.stdout
        checks += 1
for marker in ('__UNKNOWN_FIXTURE__', '__INSTALLER_PATH_DIR_ETC__',
               '__INSTALLER_PROXY3_PORTS_ALLOW_WEB_BROWSER__'):
    Path('/etc/app-veth.nft').write_text(rules + marker + '\n', encoding='ascii')
    for awk in (['/usr/bin/mawk'], ['/bin/busybox', 'awk']):
        result = scan(awk, [('/etc/app-veth.nft', RULESET_SOURCE)])
        assert result.returncode != 0 and b'target marker' in result.stdout
        checks += 1
    try:
        module.configuration(activate=True)
    except ValueError:
        checks += 1
    else:
        raise AssertionError('runtime accepted an unresolved ruleset marker')
Path('/etc/app-veth.nft').write_text(rules, encoding='ascii')
print(f'APP_VETH_PLACEHOLDER_CHECKS_PASSED={checks}', flush=True)
