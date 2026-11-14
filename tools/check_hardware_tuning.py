#!/usr/bin/env python3
"""Guarded source-only hardware tuning wiring review; no native integration.

Do not execute this runner or create an execution environment for it. The
changed-file audit covers syntax. Native unit and AppArmor acceptance remains
unverified; this source checks only declarations and physical asset ownership.
"""
from __future__ import annotations

from pathlib import Path as _IsolationPath
import sys as _isolation_sys
_isolation_sys.path.insert(0, str(_IsolationPath(__file__).resolve().parents[1] / 'tools'))
# Copied checker/GUI fixtures still use the verified private checkout gate.
_isolation_sys.path.insert(0, '/workspace/repository/tools')
from isolation import require_test_isolation as _require_test_isolation
_isolation_sys.path.pop(0)
_require_test_isolation()


import argparse
import ast
from pathlib import Path
import sys

from source_layout import SHARED, profile_paths, profile_values, target_source


def check(seed: Path = SHARED) -> dict[str, int]:
    ast.parse((seed / 'scripts/common/hardware-tuning-config.py').read_text(encoding='utf-8'))
    module_root = seed / 'hooks/target/usr/local/lib/common/hardware_tuning'
    modules = sorted(module_root.rglob('*.py'))
    for path in modules:
        ast.parse(path.read_text(encoding='utf-8'), filename=str(path))
    profiles = profile_paths(seed)
    for profile in profiles:
        values = profile_values(seed, profile)
        if values['HARDWARE_TUNING_AUTOSTART_ENABLE'] not in {'true', 'false'}:
            raise ValueError('invalid tuning activation policy')
    for family in ('desktop', 'server'):
        for relative in ('etc/apparmor.d/hardware-tuning',
                         'etc/systemd/system/hardware-tuning.service',
                         'usr/local/libexec/hardware-tuning-policy'):
            target_source(seed, relative, family)
    return {'python_sources': len(modules) + 1, 'profile_declarations': len(profiles),
            'native_checks_executed': 0}


def main() -> int:
    argparse.ArgumentParser(description=__doc__).parse_args()
    try:
        print(check())
        return 0
    except (OSError, ValueError, SyntaxError) as error:
        print('hardware source review failed: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
