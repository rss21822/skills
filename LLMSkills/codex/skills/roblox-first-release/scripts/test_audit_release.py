"""Offline gate regression in a disposable directory; no Roblox or game changes."""

import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import uuid

from audit_release import CHECKS, audit


class ReleaseAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="roblox-first-release-test-")
        self.addCleanup(self.temp.cleanup)
        directory = Path(self.temp.name)
        self.files = []
        for name in ("source.luau", "root.rbxlx", "child.rbxlx", "SKILL.md"):
            path = directory / name
            path.write_text("isolated fixture: " + name, encoding="utf-8")
            self.files.append({"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
        checks = {n: {"status": "confirmed", "evidence": "offline fixture evidence"} for n in CHECKS}
        self.data = {
            "schema": 1, "run_id": str(uuid.uuid4()),
            "target": {"owner_id": 100, "universe_id": 200, "root_place_id": 300, "environment": "production-private"},
            "observed": {"owner_id": 100, "universe_id": 200, "root_place_id": 300, "audience": "Private", "evidence": "offline fixture", "observed_at": "2026-10-10T00:00:00Z"},
            "excluded": {"universe_ids": [900], "place_ids": [901]},
            "requested": {"player": False, "public": False, "localization": True, "monetization": True},
            "inputs": [self.files[0]],
            "children": [{"name": "prepare-roblox-private-production", "path": self.files[3]["path"], "accepted_sha256": self.files[3]["sha256"], "profile": "configuration-upload", "contract_accepted": True}],
            "places": [], "checks": checks,
        }
        for pid, role, item in ((300, "root", self.files[1]), (301, "child", self.files[2])):
            self.data["places"].append({
                "place_id": pid, "universe_id": 200, "role": role, **item,
                "published": {"uploaded_sha256": item["sha256"], "response_version": 2, "observed_version": 2, "evidence": "offline independent fixture", "observed_at": "2026-10-10T00:01:00Z"},
            })

    def test_configuration_only_finishes_without_player_or_public(self):
        result = audit(self.data, "finish")
        self.assertEqual(result["errors"], [])
        self.assertTrue(result["configuration_upload_complete"])
        self.assertEqual(result["player_acceptance"], "not_requested")
        self.assertEqual(result["general_public"], "not_requested")

    def test_generation_pending_is_separate_from_registered(self):
        self.data["checks"]["translations_generated"]["status"] = "pending"
        result = audit(self.data, "finish")
        self.assertEqual(result["errors"], [])
        self.assertTrue(result["configuration_upload_complete"])
        self.assertEqual(result["translation_generation"], "incomplete")

    def test_explicit_generation_requirement_cannot_be_skipped(self):
        self.data["requested"]["require_translation_generation"] = True
        self.data["checks"]["translations_generated"]["status"] = "pending"
        self.assertTrue(audit(self.data, "finish")["errors"])

    def test_other_environment_universe_blocked(self):
        self.data["places"][1]["universe_id"] = 900
        self.assertTrue(audit(self.data, "preflight")["errors"])

    def test_excluded_place_blocked(self):
        self.data["excluded"]["place_ids"] = [301]
        self.assertTrue(audit(self.data, "preflight")["errors"])

    def test_excluded_target_blocked(self):
        self.data["excluded"]["universe_ids"] = [200]
        self.assertTrue(audit(self.data, "preflight")["errors"])

    def test_current_owner_or_target_mismatch_blocked(self):
        for name in ("owner_id", "universe_id", "root_place_id"):
            with self.subTest(name=name):
                case = copy.deepcopy(self.data)
                case["observed"][name] += 1
                self.assertTrue(audit(case, "preflight")["errors"])

    def test_uncertain_product_creation_cannot_be_complete(self):
        self.data["checks"]["monetization_ready"]["status"] = "unknown"
        self.assertFalse(audit(self.data, "finish")["configuration_upload_complete"])
        self.assertTrue(audit(self.data, "finish")["errors"])

    def test_partial_child_publish_stops_root(self):
        self.data["places"][1]["published"] = None
        self.data["places"][0]["published"] = None
        self.assertTrue(audit(self.data, "root")["errors"])

    def test_root_can_follow_confirmed_children(self):
        self.data["places"][0]["published"] = None
        self.assertEqual(audit(self.data, "root")["errors"], [])
        self.assertFalse(audit(self.data, "finish")["configuration_upload_complete"])

    def test_language_mismatch_stops_root(self):
        self.data["checks"]["source_language_consistent"]["status"] = "failed"
        self.assertTrue(audit(self.data, "root")["errors"])

    def test_other_pc_changes_source_invalidates_evidence(self):
        Path(self.files[0]["path"]).write_text("another run changed source", encoding="utf-8")
        result = audit(self.data, "finish")
        self.assertTrue(result["errors"])
        self.assertFalse(result["configuration_upload_complete"])

    def test_other_pc_changes_artifact_invalidates_evidence(self):
        Path(self.files[2]["path"]).write_text("another run changed artifact", encoding="utf-8")
        self.assertTrue(audit(self.data, "root")["errors"])

    def test_child_skill_change_requires_contract_review(self):
        Path(self.files[3]["path"]).write_text("changed Skill", encoding="utf-8")
        self.assertTrue(audit(self.data, "preflight")["errors"])

    def test_child_full_validation_cannot_leak_player(self):
        self.data["children"][0]["profile"] = "full-validation"
        self.assertTrue(audit(self.data, "preflight")["errors"])

    def test_unknown_profile_or_unaccepted_contract_blocked(self):
        self.data["children"][0]["profile"] = "skip-all"
        self.assertTrue(audit(self.data, "preflight")["errors"])
        self.data["children"][0]["profile"] = "configuration-upload"
        self.data["children"][0]["contract_accepted"] = False
        self.assertTrue(audit(self.data, "preflight")["errors"])

    def test_unrequested_public_cannot_pass_public_gate(self):
        self.assertTrue(audit(self.data, "public")["errors"])
        self.data["observed"]["audience"] = "Public"
        self.assertTrue(audit(self.data, "finish")["errors"])

    def test_public_gate_and_saved_public_are_different(self):
        self.data["requested"]["public"] = True
        self.data["checks"]["public_saved"]["status"] = "unknown"
        result = audit(self.data, "public")
        self.assertEqual(result["errors"], [])
        self.assertTrue(result["public_ready"])
        self.assertEqual(result["general_public"], "incomplete")
        self.assertTrue(audit(self.data, "finish")["errors"])
        self.data["checks"]["public_saved"]["status"] = "confirmed"
        self.data["observed"]["audience"] = "Public"
        self.assertEqual(audit(self.data, "finish")["general_public"], "complete")
        self.assertEqual(audit(self.data, "finish")["errors"], [])

    def test_skipping_player_does_not_clear_compliance_gate(self):
        self.data["requested"]["public"] = True
        self.data["checks"]["compliance"]["status"] = "pending"
        self.assertTrue(audit(self.data, "public")["errors"])

    def test_public_compliance_cannot_be_marked_not_applicable(self):
        self.data["requested"]["public"] = True
        self.data["checks"]["compliance"]["status"] = "not_applicable"
        self.assertTrue(audit(self.data, "public")["errors"])

    def test_boolean_is_not_an_observed_id(self):
        self.data["target"]["owner_id"] = 1
        self.data["observed"]["owner_id"] = True
        self.assertTrue(audit(self.data, "preflight")["errors"])

    def test_requested_player_incomplete_blocked(self):
        self.data["requested"]["player"] = True
        self.data["checks"]["player_acceptance"]["status"] = "pending"
        result = audit(self.data, "finish")
        self.assertTrue(result["errors"])
        self.assertEqual(result["player_acceptance"], "incomplete")

    def test_cleanup_missing_is_not_complete(self):
        self.data["checks"]["cleanup"]["status"] = "unknown"
        self.assertFalse(audit(self.data, "finish")["configuration_upload_complete"])

    def test_version_or_uploaded_hash_mismatch(self):
        pub = self.data["places"][1]["published"]
        pub["observed_version"] = 3
        self.assertTrue(audit(self.data, "root")["errors"])
        pub["response_version"] = 3
        pub["uploaded_sha256"] = "0" * 64
        self.assertTrue(audit(self.data, "root")["errors"])

    def test_missing_evidence_cannot_satisfy_gate(self):
        self.data["checks"]["settings_saved"]["evidence"] = ""
        self.assertFalse(audit(self.data, "finish")["configuration_upload_complete"])

    def test_duplicate_or_wrong_root_blocked(self):
        self.data["places"][1]["place_id"] = 300
        self.assertTrue(audit(self.data, "preflight")["errors"])
        self.data["places"][1]["place_id"] = 301
        self.data["places"][1]["role"] = "root"
        self.assertTrue(audit(self.data, "preflight")["errors"])

    def test_unused_features_do_not_require_products_or_translations(self):
        self.data["requested"]["localization"] = False
        self.data["requested"]["monetization"] = False
        for n in ("localization_registered", "monetization_ready"):
            self.data["checks"][n]["status"] = "not_applicable"
        self.assertEqual(audit(self.data, "finish")["errors"], [])

    def test_two_runs_do_not_mutate_or_inherit_inputs(self):
        first = copy.deepcopy(self.data)
        second = copy.deepcopy(self.data)
        second["run_id"] = str(uuid.uuid4())
        second["requested"]["player"] = True
        second["checks"]["player_acceptance"]["status"] = "pending"
        original = copy.deepcopy(first)
        self.assertTrue(audit(second, "finish")["errors"])
        self.assertEqual(audit(first, "finish")["errors"], [])
        self.assertEqual(first, original)

    def test_cli_success_and_malformed_fail_closed(self):
        manifest = Path(self.temp.name) / "release.json"
        manifest.write_text(json.dumps(self.data), encoding="utf-8")
        command = [sys.executable, "-B", str(Path(__file__).with_name("audit_release.py")), "--manifest", str(manifest), "--stage", "finish"]
        passed = subprocess.run(command, capture_output=True, text=True, check=False)
        self.assertEqual(passed.returncode, 0, passed.stdout)
        self.assertTrue(json.loads(passed.stdout)["configuration_upload_complete"])
        manifest.write_text('{"schema": 1}', encoding="utf-8")
        failed = subprocess.run(command, capture_output=True, text=True, check=False)
        self.assertEqual(failed.returncode, 1)
        self.assertTrue(json.loads(failed.stdout)["errors"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
