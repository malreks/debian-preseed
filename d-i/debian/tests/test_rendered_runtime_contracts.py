"""Source contracts for desktop staging without a second installer audit.

These fixtures inspect source data only. No target, helper, repository import,
service manager or disposable execution environment is used by the cases.
"""
from __future__ import annotations

from pathlib import Path as _IsolationPath
import sys as _isolation_sys
_isolation_sys.path.insert(0, str(_IsolationPath(__file__).resolve().parents[3] / 'tools'))
from isolation import require_test_isolation as _require_test_isolation
_require_test_isolation()

from pathlib import Path
import re
import unittest

SCRIPTS = Path(__file__).resolve().parents[1] / 'scripts/desktop'


class RenderedRuntimeContractTests(unittest.TestCase):
    def test_loader_and_catalog_have_no_desktop_audit_module(self):
        loader = (SCRIPTS.parent / 'late/desktop.sh').read_text()
        modules = re.search(r'for desktop_module in ([^;]+); do', loader).group(1).split()
        self.assertNotIn('verify', modules)
        self.assertNotIn('/verify.sh', loader)
        self.assertFalse((SCRIPTS / 'verify.sh.tmpl').exists())
        self.assertNotIn('FILE_DESKTOP_VERIFY', (SCRIPTS.parents[1] / 'repo.env').read_text())

    def test_staging_and_installation_still_precede_service_enablement(self):
        source = (SCRIPTS / 'labwc.sh').read_text().split('run_desktop_late_command() {', 1)[1]
        self.assertNotIn('desktop_verify_', source)
        activation = source.index('  desktop_enable_target_services')
        for step in ('desktop_stage_target_assets', 'desktop_install_appearance_themes',
                     'desktop_install_user_config', 'desktop_capture_appearance_defaults',
                     'desktop_install_fonts', 'desktop_install_waypaper'):
            self.assertLess(source.index('  ' + step), activation)

    def test_completed_stage_stamp_still_requires_a_successful_installer(self):
        loader = (SCRIPTS.parent / 'late/desktop.sh').read_text()
        self.assertIn('set -eu', loader)
        self.assertLess(loader.index('run_desktop_late_command "$requested_seed_base" "$requested_host_profile"'),
                        loader.index(': >"$desktop_late_stage_stamp"'))
        appearance = (SCRIPTS / 'components/appearance.sh').read_text()
        self.assertNotIn('desktop_verify_appearance_assets', appearance)
        self.assertIn('desktop_run_appearance_setup defaults', appearance)
        renderer = (SCRIPTS / 'components/rendering-access.sh').read_text()
        self.assertIn('desktop_assert_no_unresolved_template_placeholders', renderer)


if __name__ == '__main__':
    unittest.main()
