"""Data-only checks for the versioned placeholder registry.

The repository test guard keeps this module out of development-host execution;
the checks themselves only parse source bytes and registry JSON.
"""
from __future__ import annotations

from pathlib import Path
import json
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
from isolation import require_test_isolation

require_test_isolation()

from validate_placeholder_registry import exact_tokens, build_registry, validate


class PlaceholderRegistryContractTests(unittest.TestCase):
    def test_adjacent_tokens_are_two_exact_tokens(self):
        self.assertEqual(
            exact_tokens("__INSTALLER_PATH_A____INSTALLER_PATH_B__"),
            ["__INSTALLER_PATH_A__", "__INSTALLER_PATH_B__"],
        )

    def test_checked_in_registry_covers_current_production_source(self):
        registry = json.loads((ROOT / "d-i/debian/catalog/placeholder-registry.json").read_text())
        report = validate(registry)
        self.assertEqual(report["unknown_production_tokens"], [])
        self.assertEqual(report["canonical_missing"], [])
        self.assertEqual(report["production_tokens"], report["registry_entries"])

    def test_tsv_carries_failure_diagnostic_ownership(self):
        rows = (ROOT / "d-i/debian/catalog/placeholder-registry.tsv").read_text(
            encoding="utf-8"
        ).splitlines()
        self.assertEqual(rows[0].split("\t")[:2], ["format", "2"])
        columns = rows[1].split("\t")
        self.assertEqual(columns[0], "token")
        self.assertIn("owner_module", columns)
        self.assertIn("owner_phase", columns)
        self.assertIn("source_members", columns)
        self.assertTrue(all(len(row.split("\t")) == len(columns) for row in rows[2:]))

    def test_finish_validator_uses_registry_and_rejects_unknown_markers(self):
        validator = (
            ROOT / "d-i/debian/hooks/installer/finish-install.d/94zz-99-validate-target"
        ).read_text(encoding="utf-8")
        self.assertIn("placeholder-registry.tsv", validator)
        self.assertIn("DIR_INSTALLER_TARGET_OWNERSHIP", validator)
        scanner = (ROOT / "d-i/debian/scripts/common/target-owned-scan.awk").read_text(encoding="utf-8")
        self.assertIn("owner=unknown source=%s phase=%s", scanner)
        self.assertIn("source=%s phase=%s", scanner)
        self.assertIn("installer_target_context_path", validator)

    def test_desktop_blocks_use_the_shared_batch_publication_owner(self):
        adapter = (ROOT / 'd-i/debian/scripts/desktop/components/rendering-access.sh').read_text(encoding='utf-8')
        renderer = (ROOT / 'd-i/debian/scripts/common/render.pl').read_text(encoding='utf-8')
        body = adapter.split('desktop_render_target_template_impl() {', 1)[1].split('\n}\n', 1)[0]
        for field in ('BLOCK_LABWC_WORKSPACE_NAME_LINES', 'BLOCK_LABWC_WORKSPACE_KEYBIND_LINES',
                      'BLOCK_LABWC_RECORDING_KEYBIND_LINES'):
            self.assertIn(field, body)
        self.assertIn('installer_asset_publish', body)
        self.assertNotIn('desktop_render_declared_template_blocks', adapter)
        self.assertNotIn('fetch_hook', body)
        self.assertIn('declared publication line block must occur exactly once', renderer)
        publication = renderer.split('sub publish_assets {', 1)[1].split('sub main {', 1)[0]
        self.assertLess(publication.index('publication_render('), publication.index('write_file($path,'))
        self.assertIn('primary and future publication outputs exceed batch limit', publication)

    def test_final_target_roots_and_allowlisted_application_grammar_are_declared(self):
        registry = json.loads((ROOT / "d-i/debian/catalog/placeholder-registry.json").read_text())
        entries = registry["entries"]
        members = {
            member
            for entry in entries
            for member in entry["consumer"]["source_members"]
        }
        self.assertTrue(any("perl" in member for member in members))
        self.assertTrue(any("/share/" in member for member in members))
        self.assertTrue(any("generated" in member or "state" in member for member in members))
        allowlisted = [
            entry for entry in entries
            if entry["namespace"] == "APPLICATION_GRAMMAR"
            and entry["must_be_absent_from_final_target"] is False
        ]
        self.assertIn("__PACKAGE__", [entry["token"] for entry in allowlisted])
        self.assertNotIn("__DESKTOP_APPARMOR_STATE__", [entry["token"] for entry in allowlisted])
        self.assertTrue(all(
            entry["must_be_absent_from_final_target"] is True
            for entry in entries
            if entry not in allowlisted
        ))


if __name__ == "__main__":
    raise SystemExit(unittest.main())
