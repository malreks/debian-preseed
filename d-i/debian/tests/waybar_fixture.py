"""Render the real output-class assets; stub transport/publishing, not policy."""

# Refuse host execution before importing runtime helpers or creating fixtures.
from pathlib import Path as _IsolationPath
import sys as _isolation_sys
_isolation_sys.path.insert(0, str(_IsolationPath(__file__).resolve().parents[3] / 'tools'))
# Copied checker/GUI fixtures still use the verified private checkout gate.
_isolation_sys.path.insert(0, '/workspace/repository/tools')
from isolation import require_test_isolation as _require_test_isolation
_isolation_sys.path.pop(0)
_require_test_isolation()

from functools import lru_cache
from pathlib import Path
import atexit
import os
import json
import re
import shlex
import subprocess
import tarfile
import tempfile
from payload_fixture import read_text, source_path
from fixture_render import compiled_profile_values, render_scalar_fixture
from theme_fixture import render_theme_defaults

FORKY = Path(__file__).resolve().parents[1]
TARGET = FORKY / 'hooks/target'


def profile_values(profile):
    """Read a private literal snapshot; never source supplied fixture text."""
    profile = Path(profile)
    if not profile.is_file() or profile.is_relative_to(FORKY / 'hosts/profiles'):
        return compiled_profile_values(profile.name)
    if profile.is_symlink() or profile.stat().st_size > 1024 * 1024:
        raise ValueError('unsafe fixture profile')
    result = {}
    for line in profile.read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        key, separator, raw = line.partition('=')
        words = shlex.split(raw)
        if not separator or not re.fullmatch(r'[A-Z][A-Z0-9_]*', key) or len(words) != 1:
            raise ValueError('invalid literal fixture profile')
        # Tests may deliberately append a field override. Serialize it again
        # as literal data before the production shell renderer consumes it.
        result[key] = words[0]
    return result


@lru_cache(maxsize=32)
def native_assets(profile, count=None, theme_items=()):
    """Return the rendered files at their real paths relative to waybar/."""
    profile = Path(profile)
    script = r'''
. "$1"
. "$2"
fixture_source_root=$4
if [ "$3" != profile ]; then
  LABWC_WORKSPACE_COUNT_INTERNAL=$3
  LABWC_WORKSPACE_COUNT_EXTERNAL=$3
fi
installer_repo_file_value() { printf '%s/%s\n' "$fixture_source_root" "$1"; }
fetch_hook() { cp "$1" "$2"; }
target_private_stage_dir() { mktemp -d "$TMP_ENV_DIR/geometry.XXXXXX"; }
target_asset_host_path() { printf '%s\n' "$1"; }
stage_target_asset() { cp "$1" "$2"; chmod "$3" "$2"; }
write_target_file() { cat >"$1"; chmod "$2" "$1"; }
run_in_target() { shift; "$@"; }
desktop_fatal() { printf '%s\n' "$*" >&2; exit 1; }
desktop_render_role_target_template() { printf '%s\0' "$@"; printf '\0'; }
desktop_render_role_target_template_deferred() { desktop_render_role_target_template "$@"; }
desktop_assert_role_target_template_resolved() { :; }
desktop_log() { :; }
installer_warn() { :; }
desktop_render_waybar_config
desktop_render_waybar_style
for menu in audio battery bluetooth brightness calendar launcher notifications power screenshot system tomat wayscriber; do
    desktop_render_waybar_asset "${menu}-menu.xml"
done
'''
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        values = profile_values(profile)
        assignments = work / 'profile.env'
        assignments.write_text(''.join(key + '=' + shlex.quote(value) + '\n'
                                       for key, value in values.items()), encoding='utf-8')
        definitions = work / 'components.sh'
        raw_definitions = work / 'components-source'
        raw_definitions.write_text(read_text(FORKY / 'scripts/desktop/detect.sh') + '\n' +
                                   read_text(FORKY / 'scripts/desktop/components.sh'), encoding='utf-8')
        definitions.write_bytes(render_scalar_fixture(raw_definitions, work, values))
        # Only staging/transport is adapted. The actual shell renderer and its
        # target Python geometry validator run inside the reviewed test guest.
        response = subprocess.run([
            '/bin/sh','-eu','-c',script,'output-class-render',str(assignments),
            str(definitions),'profile' if count is None else str(count), str(FORKY)],
            env={'PATH':'/usr/bin:/bin','HOME':tmp,'TMP_ENV_DIR':tmp,
                 'TMPDIR':tmp,'TMP':tmp,'TEMP':tmp,'LC_ALL':'C.UTF-8'},
            capture_output=True,check=True,timeout=15)
        result = {}
        for record in response.stdout.decode().split('\0\0'):
            if not record: continue
            fields=record.split('\0')
            source,dest,mode,*pairs=fields
            if len(pairs)%2: raise AssertionError('incomplete renderer record')
            fields=dict(zip(pairs[::2],pairs[1::2]))
            text=render_scalar_fixture(source_path(TARGET/source), work,
                                       {**values, **fields}).decode('utf-8')
            text=render_theme_defaults(text, dict(theme_items))
            if '__INSTALLER_' in text or '__THEME_' in text:
                raise AssertionError('unresolved source '+source)
            relative = Path(dest).relative_to('/etc/skel-desktop/.config/waybar').as_posix()
            if relative == 'config' or relative.startswith('modules/'):
                def unique_keys(pairs):
                    fields = {}
                    for key, value in pairs:
                        if key in fields: raise AssertionError('duplicate Waybar key: ' + key)
                        fields[key] = value
                    return fields
                json.loads(text, object_pairs_hook=unique_keys)
            if relative in result:
                raise AssertionError('duplicate rendered Waybar destination: ' + relative)
            result[relative]=text
    return result


def resolved_config(assets):
    """Apply Waybar's first-value-wins object merge to managed includes."""
    bars = json.loads(assets['config'])

    def merge(base, fragment):
        if not isinstance(base, dict) or not isinstance(fragment, dict):
            raise AssertionError('Waybar include must contain an object')
        for key, value in fragment.items():
            if key not in base:
                base[key] = value
            elif isinstance(base[key], dict) and isinstance(value, dict):
                merge(base[key], value)

    for bar in bars:
        for include in bar.pop('include', []):
            prefix = '~/.config/waybar/'
            if not include.startswith(prefix):
                raise AssertionError('unexpected Waybar include root')
            relative = include[len(prefix):]
            if not re.fullmatch(r'modules/[a-z-]+', relative):
                raise AssertionError('unsafe Waybar include')
            merge(bar, json.loads(assets[relative]))
    return bars


def rendered_assets(profile, count=None, theme_items=()):
    """Resolved fixture view; native_assets retains the actual file boundary."""
    assets = dict(native_assets(profile, count, theme_items))
    assets['config'] = json.dumps(resolved_config(assets), ensure_ascii=False)
    expression = re.compile(r'@import url\("([^"\n]+)"\);')

    def stylesheet(relative, active=()):
        if relative in active or len(active) > 8:
            raise AssertionError('recursive Waybar stylesheet import')
        def include(match):
            name = match[1]
            if not re.fullmatch(r'(?:style-common|(?:style|gtk)/[a-z-]+)\.css', name):
                raise AssertionError('unsafe Waybar stylesheet import')
            return stylesheet(name, (*active, relative))
        return expression.sub(include, assets[relative])

    assets['style.css'] = stylesheet('style.css')
    return assets

@lru_cache(maxsize=1)
def profiles():
    """Materialize generated desktop profiles, including inherited defaults."""
    temporary = tempfile.TemporaryDirectory(prefix='waybar-compiled-profiles-')
    atexit.register(temporary.cleanup)
    directory = Path(temporary.name)
    prefix = 'catalog/compiled/forky/profiles/desktop/'
    with tarfile.open(FORKY.parent / 'forky/payload.tar.gz', 'r:gz') as archive:
        names = [member.name.removeprefix(prefix) for member in archive
                 if member.name.startswith(prefix) and member.name.endswith('.env')
                 and not member.name.endswith('.account.env')]
    if len(names) != len(set(names)) or not 0 < len(names) <= 32:
        raise ValueError('invalid compiled desktop profile inventory')
    result = []
    for name in sorted(names):
        values = compiled_profile_values(name)
        path = directory / name
        path.write_text(''.join(key + '=' + shlex.quote(value) + '\n'
                                for key, value in values.items()), encoding='utf-8')
        result.append(path)
    return result

def style(profile, output_class):
    assets=rendered_assets(profile)
    return assets['style.css']
