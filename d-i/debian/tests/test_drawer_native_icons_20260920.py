"""Native application artwork contract and GTK painting; no application launch."""
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

from payload_fixture import waybar_style_text
from payload_fixture import installed_argv as payload_installed_argv
from payload_fixture import read_text as payload_read_text
from theme_fixture import render_theme_defaults, render_theme_bytes, theme_values
import ctypes.util
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib

from test_native_tomat_20260920 import FORKY, SKEL, bars
from test_notifications_followup_20260920 import rendered_profile_styles

ICONS={'custom/app-terminal':('foot','Foot',(23,217,71)),
       'custom/app-files':('org.xfce.thunar','Thunar',(35,145,247)),
       'custom/app-tuta':('tuta-mail','Tuta Mail',(179,27,198)),
       'custom/app-notes':('l3afpad','L3afpad',(47,226,211)),
       'custom/app-sleek':('sleek','Sleek',(230,72,174))}


ICON_PATHS = {
    'foot': '/usr/share/icons/Papirus/24x24/apps/foot.svg',
    'org.xfce.thunar': '/usr/share/icons/Papirus/24x24/apps/org.xfce.thunar.svg',
    'tuta-mail': '/usr/share/icons/hicolor/512x512/apps/tuta-mail.png',
    'l3afpad': '/usr/share/icons/Papirus/24x24/apps/l3afpad.svg',
    'sleek': '/usr/share/icons/hicolor/512x512/apps/sleek.png',
}


def png(color, size=32):
    def chunk(name,data):
        return struct.pack('!I',len(data))+name+data+struct.pack('!I',zlib.crc32(name+data))
    raw=(b'\0'+bytes(color)*size)*size
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',size,size,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'')


class NativeDrawerTests(unittest.TestCase):
    def test_both_drawers_keep_tooltips_and_owned_launch_paths_not_font_glyphs(self):
        for bar in bars():
            for module,(_,tooltip,_) in ICONS.items():
                entry=bar[module]
                self.assertEqual(entry['format'],' ')
                self.assertEqual(entry['tooltip-format'],tooltip)
                click = entry['on-click-release'] if module == 'custom/wayscriber' else entry['on-click']
                self.assertIn('--property=PartOf=labwc-session.target',click)
                self.assertIn('--property=KillMode=control-group',click)
                self.assertEqual(entry['align'],0.5)
                self.assertIn(module,bar['group/apps']['modules'])

    def test_all_seven_icons_have_18px_bounds_for_every_profile_and_state(self):
        for profile, css in rendered_profile_styles().items():
            rules = re.findall(r'([^{}]+)\{([^{}]*)\}',
                               re.sub(r'/\*.*?\*/', '', css, flags=re.S))
            for module in ('custom/apps', 'custom/wayscriber', *ICONS):
                for suffix in ('', ':hover'):
                    selector = 'window#waybar.external #' + module.replace('/', '-') + suffix
                    with self.subTest(profile=profile, selector=selector):
                        sizes = [value.strip() for selectors, body in rules
                                 if selector in {part.strip() for part in selectors.split(',')}
                                 for value in re.findall(r'background-size:\s*([^;]+);', body)]
                        self.assertTrue(sizes)
                        self.assertEqual(sizes[-1], '18px 18px, 100% 100%')

    def test_native_artwork_is_retained_above_violet_hover_color(self):
        css=render_theme_defaults(waybar_style_text(SKEL/'waybar'))
        rules=re.findall(r'([^{}]+)\{([^{}]*)\}', re.sub(r'/\*.*?\*/','',css,flags=re.S))
        for module,(icon,_,_) in ICONS.items():
            selector='#'+module.replace('/','-')
            normal=[body for selectors,body in rules if selectors.strip()==selector]
            hovered=[body for selectors,body in rules
                     if selector+':hover' in {x.strip() for x in selectors.split(',')}]
            self.assertTrue(normal)
            self.assertIn('url("'+ICON_PATHS[icon]+'")', "\n".join(normal))
            self.assertTrue(hovered)
            self.assertTrue(any('background-color: rgba(44, 39, 62, 0.96)' in body for body in hovered))
            for body in hovered:
                self.assertIsNone(re.search(r'(?:^|;)\s*background(?:-image)?\s*:',body))
            self.assertEqual(css.count('url("'+ICON_PATHS[icon]+'")'),1)


    def test_drawer_audit_is_not_an_installer_gate(self):
        role=render_theme_defaults(payload_read_text(FORKY/'scripts/desktop/labwc.sh')).split('run_desktop_late_command() {',1)[1]
        self.assertNotIn('desktop_verify_',role)

    def test_notification_lock_and_power_palette_is_explicit(self):
        css=render_theme_defaults(waybar_style_text(SKEL/'waybar'))
        for selector,rgba in (('notifications','236, 184, 96, 0.14'),('lock','203, 213, 225, 0.14'),('power','248, 113, 113, 0.16')):
            self.assertIn('#custom-'+selector+' {\n  background: rgba('+rgba+');',css)
        self.assertIn('#custom-notifications:hover {\n  background: ' + theme_values()['WAYBAR_BUTTON_NOTIFICATIONS_HOVER_BACKGROUND_COLOR'] + ';',css)
        self.assertIn('#custom-lock:hover {\n  background: linear-gradient(135deg, rgba(226, 232, 240, 0.84), rgba(148, 163, 184, 0.84));',css)
        self.assertIn('#custom-power:hover {\n  background: linear-gradient(135deg, rgba(236, 184, 96, 0.92), rgba(242, 159, 103, 0.92), rgba(248, 113, 113, 0.92));',css)

    def test_gtk_package_urls_and_hover_paint_at_two_scales(self):
        if not shutil.which('xvfb-run') or not ctypes.util.find_library('gtk-3'):
            self.skipTest('native GTK3 / Xvfb unavailable')
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            for icon,_,color in ICONS.values():
                image=root/ICON_PATHS[icon].lstrip('/')
                image.parent.mkdir(parents=True,exist_ok=True)
                if image.suffix=='.svg':
                    image.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
                                     'viewBox="0 0 24 24"><path fill="rgb(%s)" d="M0 0h24v24H0z"/></svg>'
                                     % ','.join(map(str,color)))
                else:
                    image.write_bytes(png(color,512))
            # The outdated hicolor icon must never override the Papirus URL.
            fallback=root/'usr/share/icons/hicolor/24x24/apps/org.xfce.thunar.png'
            fallback.parent.mkdir(parents=True,exist_ok=True)
            fallback.write_bytes(png((255,0,0)))
            css=root/'style.css'
            css.write_text(next(iter(rendered_profile_styles().values())).replace(
                '/usr/share/icons/',str(root/'usr/share/icons')+'/'))
            for scale in (1,2):
                result=subprocess.run(payload_installed_argv(['xvfb-run','-a','/usr/bin/python3','-I','-B',
                    str(FORKY/'tests/fixtures/waybar-native-icons-gtk.py'),str(css),str(scale)]),
                    env={**os.environ,'GDK_BACKEND':'x11','NO_AT_BRIDGE':'1','GDK_SCALE':str(scale)},
                    text=True,capture_output=True,timeout=20)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertEqual(json.loads(result.stdout)['native_icon_paint_cases'],20)





if __name__=='__main__':unittest.main()
