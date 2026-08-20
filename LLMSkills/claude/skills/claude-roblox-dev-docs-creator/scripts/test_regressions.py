#!/usr/bin/env python3
"""gen_index.py / lint_docs.py の再発防止テスト。標準ライブラリのみ。"""
from __future__ import annotations

import importlib.util
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent


def load_module(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPT_DIR / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


gen_index = load_module("gen_index")
lint_docs = load_module("lint_docs")
check_skill_seams = load_module("check_skill_seams")
detect_triggers = load_module("detect_triggers")
validate_d5 = load_module("validate_d5_acceptance")
validate_docs_module = load_module("validate_docs")


def write(path: Path, text: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


def run_cli(args: list[str]) -> subprocess.CompletedProcess[str]:
    """Decode child output deterministically on Windows (never locale/cp932)."""
    return subprocess.run(
        args, text=True, encoding="utf-8", errors="replace", capture_output=True)


def approved_intake(project: str, prefix: str, marker: str = "v1") -> dict:
    template = (SCRIPT_DIR.parent / "templates" / "intake.json").read_text(encoding="utf-8")
    data = json.loads(template.replace("{{PROJECT}}", project).replace("{{PREFIX}}", prefix))
    for answer_id, answer in data["answers"].items():
        answer.update({
            "value": f"approved {answer_id} {marker}",
            "status": "approved",
            "source": "U",
            "evidence": [f"conversation:{marker}:{answer_id}"],
            "approvedBy": "Project Owner",
            "approvedAt": "2026-08-20T12:00:00+09:00",
        })
    data["state"].update({
        "approved": True,
        "approved_by": "Project Owner",
        "approved_at": "2026-08-20T12:00:00+09:00",
        "approval_evidence": f"conversation:{marker}:approval",
    })
    data["product"].update({
        "one_sentence": "Test game", "primary_action": "build",
        "reference_games": ["Reference A", "Reference B"],
        "unique_axes": ["Axis A"], "round_minutes": 5,
        "session_minutes": 20, "meta_loop": "unlock",
        "mvp_questions": ["Q1", "Q2", "Q3"],
    })
    data["technical"]["toolchain"] = "Rojo"
    return data


def sha_path(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def json_file(path: Path, value: object) -> Path:
    return write(path, json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def inventory_item(path: str, doc_id: str, domain: str) -> dict:
    return {
        "id": doc_id, "path": path, "version": "1.0.0", "domain": domain,
        "required": True, "status": "draft", "phase": "D3", "trigger": None,
    }


def formal_doc(
        doc_id: str, domain: str, status: str, approved_at: str,
        body: str, history: str) -> str:
    return (
        f"# {doc_id}\n\n"
        "| Field | Value |\n|---|---|\n"
        f"| Document ID | {doc_id} |\n"
        "| Version | 1.0.0 |\n"
        f"| Status | {status} |\n"
        f"| Canonical domain | {domain} |\n"
        f"| Last approved | {approved_at} |\n\n"
        f"{body.rstrip()}\n\n"
        "## Change History\n\n"
        "| Version | Date | Change |\n|---|---|---|\n"
        f"{history.rstrip()}\n"
    )


def file_records(contents: dict[str, bytes], status: str) -> list[dict]:
    return [{
        "path": rel, "bytes": len(contents[rel]),
        "sha256": hashlib.sha256(contents[rel]).hexdigest(),
        "version": "1.0.0", "status": status,
    } for rel in sorted(contents)]


def snapshot_files(root: Path, snapshot_rel: str, contents: dict[str, bytes]) -> None:
    for rel, payload in contents.items():
        target = root / snapshot_rel / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)


def d4_record_text(record_id: str, track: str, candidate: dict) -> str:
    return (
        "# D4 Findings Record\n\n"
        "| Field | Value |\n|---|---|\n"
        f"| Record ID | {record_id} |\n"
        f"| Audit track | {track} |\n"
        f"| Candidate baseline ID | {candidate['id']} |\n"
        f"| Candidate manifest | {candidate['path']} |\n"
        f"| Candidate manifest SHA-256 | {candidate['sha256']} |\n"
        f"| Candidate fileSetSha256 | {candidate['fileSetSha256']} |\n"
        "| Verdict | pass |\n\n"
        "## Summary\n\n- Critical: 0\n- Major: 0\n- Minor: 0\n- Verdict: pass\n"
    )


def make_baseline(
        root: Path, baseline_id: str, stage: str, contents: dict[str, bytes],
        parent: str | None, promoted: str | None, approval: str | None,
        audits: list[dict], status: str) -> tuple[dict, dict, Path]:
    snapshot_rel = f"docs/evidence/baselines/{baseline_id}/snapshot"
    evidence_rel = f"docs/evidence/baselines/{baseline_id}/git-status.txt"
    snapshot_files(root, snapshot_rel, contents)
    write(root / evidence_rel, "snapshot evidence: clean\n")
    files = file_records(contents, status)
    manifest = {
        "schemaVersion": "1.0.0", "baselineId": baseline_id, "stage": stage,
        "project": "D5 Test", "prefix": "DVT",
        "createdAt": "2026-08-20T12:00:00+09:00",
        "revision": {
            "kind": "snapshot", "value": f"SNAP-{baseline_id}",
            "snapshotRoot": snapshot_rel, "gitStatusEvidence": evidence_rel,
        },
        "parentBaselineId": parent, "promotedFrom": promoted,
        "approvalId": approval,
        "fileSetSha256": validate_d5.canonical_file_set_hash(files),
        "files": files, "auditRecords": audits,
    }
    path = json_file(root / "docs" / "evidence" / "baselines" / f"{baseline_id}.json", manifest)
    ref = {
        "id": baseline_id, "path": path.relative_to(root).as_posix(),
        "sha256": sha_path(path), "fileSetSha256": manifest["fileSetSha256"],
    }
    return manifest, ref, path


def make_audits(root: Path, label: str, candidate: dict) -> list[dict]:
    records = []
    for track in ("consistency", "roblox-readiness", "clean-room"):
        record_id = f"D4-{label}-{track.upper()}"
        path = write(
            root / "docs" / "evidence" / "audits" / f"{record_id}.md",
            d4_record_text(record_id, track, candidate))
        records.append({
            "id": record_id, "auditTrack": track,
            "path": path.relative_to(root).as_posix(), "sha256": sha_path(path),
            "candidateBaseline": candidate,
            "criticalCount": 0, "majorCount": 0, "verdict": "pass",
        })
    return records


def gate_record(
        root: Path, record_id: str, record_type: str, baseline_ref: dict,
        baseline: dict, first_wp: str | None, approved_at: str) -> tuple[str, str]:
    source = write(
        root / "docs" / "evidence" / "approvals" / f"{record_id}.txt",
        f"Project Owner directly approved {record_id} at {approved_at}\n")
    record = {
        "schemaVersion": "1.0.0", "id": record_id, "type": record_type,
        "approvalKind": "human-direct", "approver": "Project Owner",
        "approvedAt": approved_at, "scope": f"exact {record_type} scope",
        "baseline": {
            "id": baseline_ref["id"], "path": baseline_ref["path"],
            "sha256": baseline_ref["sha256"],
            "fileSetSha256": baseline_ref["fileSetSha256"],
            "revision": baseline["revision"]["value"],
        },
        "firstAuthorizedWpId": first_wp,
        "sourceEvidence": {
            "path": source.relative_to(root).as_posix(), "sha256": sha_path(source),
        },
    }
    path = json_file(
        root / "docs" / "evidence" / "approvals" / f"{record_id}.json", record)
    return path.relative_to(root).as_posix(), sha_path(path)


def build_d5_fixture(root: Path) -> dict[str, Path]:
    """Create the smallest semantically complete snapshot-backed D5 capsule."""
    approved_at = "2026-08-20T12:00:00+09:00"
    d5_id, start_id, contract_id = "D5-APP-001", "P0-START-001", "P0-CONTRACT-001"
    package_rel = f"docs/evidence/d5/{d5_id}_w0_handoff_package.json"
    post_rel = f"docs/evidence/d5/{d5_id}_post_sync_manifest.json"
    manifest_rel = "docs/DVT_docs_manifest.json"
    index_rel = "docs/DVT_docs_index.md"
    wp_rel = "docs/DVT_work_packages.md"
    machine_rel = "docs/schemas/DVT_machine.json"

    docs = [
        inventory_item(index_rel, "DVT-INDEX", "navigation"),
        inventory_item(wp_rel, "DVT-WORK-PACKAGES", "implementation scope"),
        inventory_item(manifest_rel, "DVT-MANIFEST", "machine inventory"),
        inventory_item(machine_rel, "DVT-MACHINE", "machine contract"),
        inventory_item("DECISIONS.md", "DVT-DECISIONS", "operating log"),
        inventory_item("PROGRESS.md", "DVT-PROGRESS", "operating log"),
        inventory_item("CHANGELOG.md", "DVT-CHANGELOG", "operating log"),
    ]
    old_manifest = {
        "schemaVersion": "1.0.0", "generatedAt": "2026-08-19T12:00:00+09:00",
        "baselineId": None, "project": "D5 Test", "prefix": "DVT", "documents": docs,
    }
    old_index_table = gen_index.make_index_from_manifest(old_manifest)
    old_index = formal_doc(
        "DVT-INDEX", "navigation", "Review", "—",
        "## Generated Inventory\n\n" + gen_index.INDEX_BEGIN + "\n" +
        old_index_table + "\n" + gen_index.INDEX_END,
        "| 0.9.0 | 2026-08-19 | pre-D5 review |")
    old_wp = formal_doc(
        "DVT-WORK-PACKAGES", "implementation scope", "Review", "—",
        "## WP-DVT-001\n\n"
        "- Status: Proposed\n- Authorized by: —\n"
        "- Authorization baseline: —\n- Authorization evidence: —\n\n"
        "| WP ID | Status |\n|---|---|\n| WP-DVT-001 | Proposed |",
        "| 0.9.0 | 2026-08-19 | pre-D5 review |")
    old_contents = {
        index_rel: old_index.encode(), wp_rel: old_wp.encode(),
        manifest_rel: (json.dumps(old_manifest, ensure_ascii=False, indent=2) + "\n").encode(),
        machine_rel: b'{"schemaVersion":"1.0.0","value":"stable"}\n',
        "DECISIONS.md": b"# Decisions\n", "PROGRESS.md": b"# Progress\n",
        "CHANGELOG.md": b"# Changelog\n",
    }

    pre_contents = {"docs/preflight.txt": b"D4 candidate bytes\n"}
    d4_candidate, d4_ref, _ = make_baseline(
        root, "D4-CAND-DVT-001", "D4-CANDIDATE", pre_contents,
        None, None, None, [], "review")
    b0_audits = make_audits(root, "INITIAL", d4_ref)
    b0, b0_ref, _ = make_baseline(
        root, "B0-DVT-001", "B0", pre_contents,
        None, d4_candidate["baselineId"], None, b0_audits, "review")

    p0_candidate, p0_ref, _ = make_baseline(
        root, "P0-CAND-DVT-001", "P0-CANDIDATE", old_contents,
        b0["baselineId"], None, None, [], "review")
    post_audits = make_audits(root, "POSTP0", p0_ref)
    b1, b1_ref, _ = make_baseline(
        root, "B1-DVT-001", "B1", old_contents,
        b0["baselineId"], p0_candidate["baselineId"], None,
        post_audits, "review")

    current_docs = [dict(item, status="approved") for item in docs]
    current_manifest = {
        "schemaVersion": "1.0.0", "generatedAt": approved_at,
        "baselineId": "B2-DVT-001", "project": "D5 Test", "prefix": "DVT",
        "documents": current_docs,
    }
    current_table = gen_index.make_index_from_manifest(current_manifest)
    current_index = formal_doc(
        "DVT-INDEX", "navigation", "Approved", approved_at,
        "## Generated Inventory\n\n" + gen_index.INDEX_BEGIN + "\n" +
        current_table + "\n" + gen_index.INDEX_END,
        "| 0.9.0 | 2026-08-19 | pre-D5 review |\n"
        f"| 1.0.0 | {approved_at} | {d5_id} approval |")
    current_wp = formal_doc(
        "DVT-WORK-PACKAGES", "implementation scope", "Approved", approved_at,
        "## WP-DVT-001\n\n"
        "- Status: Approved\n"
        f"- Authorized by: Project Owner / {d5_id}\n"
        "- Authorization baseline: B2-DVT-001\n"
        f"- Authorization evidence: {package_rel}\n\n"
        "| WP ID | Status |\n|---|---|\n| WP-DVT-001 | Approved |",
        "| 0.9.0 | 2026-08-19 | pre-D5 review |\n"
        f"| 1.0.0 | {approved_at} | {d5_id} approval |")
    current_contents = dict(old_contents)
    current_contents.update({
        index_rel: current_index.encode(), wp_rel: current_wp.encode(),
        manifest_rel: (json.dumps(current_manifest, ensure_ascii=False, indent=2) + "\n").encode(),
    })
    current_contents["DECISIONS.md"] = old_contents["DECISIONS.md"] + (
        f"\n[DECISION] {d5_id} human-direct {approved_at} approved "
        f"{b1['baselineId']} fileSetSha256 {b1['fileSetSha256']} "
        f"docs/evidence/approvals/{d5_id}.json\n").encode()
    for rel in ("PROGRESS.md", "CHANGELOG.md"):
        current_contents[rel] = old_contents[rel] + f"\n{d5_id} {approved_at}\n".encode()
    for rel, payload in current_contents.items():
        target = root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)

    synchronized = [
        index_rel, wp_rel, manifest_rel, "DECISIONS.md", "PROGRESS.md", "CHANGELOG.md",
    ]
    post_files = [{
        "path": rel, "bytes": (root / rel).stat().st_size, "sha256": sha_path(root / rel),
    } for rel in sorted(synchronized)]
    post = {
        "schemaVersion": "1.0.0", "transactionId": d5_id,
        "baselineId": "B2-DVT-001", "generatedAt": approved_at,
        "selfIncluded": False, "files": post_files,
    }
    post_path = json_file(root / post_rel, post)
    b2_contents = dict(current_contents)
    b2_contents[post_rel] = post_path.read_bytes()
    b2, b2_ref, _ = make_baseline(
        root, "B2-DVT-001", "B2", b2_contents,
        b1["baselineId"], None, d5_id, post_audits, "approved")

    start_path, start_hash = gate_record(
        root, start_id, "p0-start", b0_ref, b0, None, approved_at)
    contract_path, contract_hash = gate_record(
        root, contract_id, "p0-contract", p0_ref, p0_candidate, None, approved_at)
    d5_path, d5_hash = gate_record(
        root, d5_id, "d5", b1_ref, b1, "WP-DVT-001", approved_at)
    package = {
        "schemaVersion": "1.0.0", "packageId": "W0-DVT-001",
        "project": "D5 Test", "prefix": "DVT", "createdAt": approved_at,
        "d5Approval": {
            "id": d5_id, "approvedAt": approved_at, "approver": "Project Owner",
            "recordPath": d5_path, "recordSha256": d5_hash,
        },
        "p0": {
            "startApprovalId": start_id, "startApprovalRecordPath": start_path,
            "startApprovalRecordSha256": start_hash,
            "contractApprovalId": contract_id,
            "contractApprovalRecordPath": contract_path,
            "contractApprovalRecordSha256": contract_hash,
        },
        "baselines": {"b0": b0_ref, "b1": b1_ref, "b2": b2_ref},
        "postSyncManifest": {
            "path": post_rel, "sha256": sha_path(post_path),
        },
        "firstAuthorizedWp": {
            "id": "WP-DVT-001", "path": wp_rel, "sha256": sha_path(root / wp_rel),
        },
        "postP0D4Records": post_audits,
    }
    package_path = json_file(root / package_rel, package)
    return {
        "package": package_path,
        "b1_snapshot_machine": root / b1["revision"]["snapshotRoot"] / machine_rel,
        "current_machine": root / machine_rel,
    }


class GenIndexTests(unittest.TestCase):
    def test_d5_non_formal_promotion_changes_only_draft_or_review_status(self):
        existing = {
            "schemaVersion": "1.0.0", "generatedAt": "2026-08-19T00:00:00Z",
            "baselineId": None, "project": "Game", "prefix": "ABC", "documents": [
                inventory_item("machine.json", "ABC-MACHINE", "machine"),
                dict(inventory_item("old.json", "ABC-OLD", "machine"),
                     status="superseded"),
            ],
        }
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            write(root / "machine.json", "{}\n")
            write(root / "old.json", "{}\n")
            result = gen_index.make_manifest(
                root, [], existing, False, None, None,
                "B2-ABC-001", approve_non_formal=True)
            by_path = {item["path"]: item for item in result["documents"]}
            self.assertEqual(by_path["machine.json"]["status"], "approved")
            self.assertEqual(by_path["old.json"]["status"], "superseded")

            errors: list[str] = []
            before = json.dumps(existing).encode()
            validate_d5.validate_manifest_transition(
                before, result, "B2-ABC-001", {}, errors)
            self.assertFalse(any("machine.json" in error for error in errors), errors)
            self.assertFalse(any("old.json" in error for error in errors), errors)
            invalid = json.loads(json.dumps(result))
            next(item for item in invalid["documents"]
                 if item["path"] == "old.json")["status"] = "approved"
            errors = []
            validate_d5.validate_manifest_transition(
                before, invalid, "B2-ABC-001", {}, errors)
            self.assertTrue(any("old.json" in error for error in errors), errors)

    def test_manifest_is_closed_schema_shaped_and_preserves_known_metadata(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            path = write(root / "docs" / "ABC_gdd.md", "ignored")
            docs = [(path, {
                "Document ID": "ABC-GDD",
                "Status": "Approved（Gate 1）",
                "Canonical domain": "product intent",
            })]
            existing = {
                "project": "Game",
                "prefix": "ABC",
                "documents": [{
                    "path": "docs/ABC_gdd.md",
                    "domain": "old domain",
                    "required": False,
                    "status": "draft",
                    "phase": "D1",
                    "trigger": "product concept exists",
                    "custom": "keep-me",
                }],
            }
            result = gen_index.make_manifest(
                root, docs, existing, False, None, None)
            self.assertEqual(result["project"], "Game")
            self.assertEqual(result["prefix"], "ABC")
            item = result["documents"][0]
            self.assertEqual(item["domain"], "product intent")
            self.assertEqual(item["status"], "approved")
            self.assertFalse(item["required"])
            self.assertEqual(item["trigger"], "product concept exists")
            self.assertNotIn("custom", item)
            self.assertEqual(result["schemaVersion"], "1.0.0")
            for key in ("id", "path", "version", "domain", "required",
                        "status", "phase", "trigger"):
                self.assertIn(key, item)

    def test_manifest_missing_project_or_prefix_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            path = write(root / "docs" / "ABC_gdd.md", "ignored")
            docs = [(path, {
                "Document ID": "ABC-GDD",
                "Status": "Draft",
                "Canonical domain": "product intent",
            })]
            with self.assertRaises(SystemExit):
                gen_index.make_manifest(root, docs, None, False, None, None)

    def test_manifest_legacy_preserved_document_is_normalized_to_closed_schema(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            write(root / "records" / "legacy.md", "legacy\n")
            existing = {
                "project": "Game",
                "prefix": "ABC",
                "documents": [{
                    "path": "records/legacy.md",
                    "required": True,
                    "status": "approved",
                }],
            }
            result = gen_index.make_manifest(
                root, [], existing, False, None, None)
            item = result["documents"][0]
            self.assertEqual(item["domain"], "user-managed artifact")
            self.assertEqual(item["id"], "records/legacy.md")
            self.assertEqual(item["version"], "0.1.0")

    def test_reset_preserves_machine_inventory_and_stale_rows_fail(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            formal = write(root / "docs" / "ABC_gdd.md", "ignored")
            machine = write(root / "docs" / "schemas" / "ABC_data.json", "{}\n")
            existing = {
                "schemaVersion": "1.0.0", "generatedAt": "2026-08-19T00:00:00Z",
                "baselineId": None, "project": "Game", "prefix": "ABC",
                "documents": [
                    inventory_item("docs/ABC_gdd.md", "ABC-GDD", "product"),
                    inventory_item("docs/schemas/ABC_data.json", "ABC-DATA", "machine"),
                ],
            }
            result = gen_index.make_manifest(
                root, [(formal, {
                    "Document ID": "ABC-GDD", "Version": "1.0.0",
                    "Status": "Draft", "Canonical domain": "product",
                })], existing, True, None, None)
            self.assertIn(machine.relative_to(root).as_posix(),
                          {item["path"] for item in result["documents"]})

            machine.unlink()
            with self.assertRaises(SystemExit) as raised:
                gen_index.make_manifest(root, [], existing, False, None, None)
            self.assertIn("存在しない", str(raised.exception))

    def test_cli_output_validates_against_architect_schema(self):
        try:
            import jsonschema
        except ImportError:
            self.skipTest("optional jsonschema package is not installed")

        skill_root = SCRIPT_DIR.parent
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            scaffolded = run_cli(
                [sys.executable, str(SCRIPT_DIR / "scaffold_project.py"),
                 "--project-name", "Schema Test", "--prefix", "TST",
                 "--project-root", str(root)])
            self.assertEqual(scaffolded.returncode, 0, scaffolded.stderr)

            output = root / "docs" / "TST_docs_manifest.json"
            generated = run_cli(
                [sys.executable, str(SCRIPT_DIR / "gen_index.py"),
                 "--project-root", str(root), "--emit", "manifest",
                 "--output", str(output), "--baseline-id", "B2-TST-001"])
            self.assertEqual(generated.returncode, 0, generated.stderr)

            manifest = json.loads(output.read_text(encoding="utf-8"))
            schema = json.loads(
                (skill_root / "schemas" / "docs_manifest.schema.json").read_text(encoding="utf-8"))
            jsonschema.validate(manifest, schema)
            self.assertEqual(manifest["baselineId"], "B2-TST-001")
            self.assertTrue(all("trigger" in item for item in manifest["documents"]))

    def test_index_output_updates_only_marked_region_or_explicit_full_file(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "index.md"
            write(path, "# Authored\n\n" + gen_index.INDEX_BEGIN +
                  "\nold\n" + gen_index.INDEX_END + "\n\nkeep\n")
            gen_index.write_index(path, "| A |\n|---|", "markers")
            text = path.read_text(encoding="utf-8")
            self.assertIn("# Authored", text)
            self.assertIn("keep", text)
            self.assertNotIn("old", text)
            self.assertIn("| A |", text)

            unmarked = write(Path(td) / "unmarked.md", "owned content\n")
            with self.assertRaises(ValueError):
                gen_index.write_index(unmarked, "generated", "markers")
            gen_index.write_index(unmarked, "generated", "full")
            self.assertEqual(unmarked.read_text(encoding="utf-8"), "generated\n")


class LifecycleScriptTests(unittest.TestCase):
    def test_file_set_hash_python_canonical_vector(self):
        files = [
            {"path": "a/é.json", "bytes": 2, "sha256": "0" * 64,
             "version": None, "status": "draft"},
            {"path": "z.txt", "bytes": 1, "sha256": "f" * 64,
             "version": "1.0.0", "status": "approved"},
        ]
        self.assertEqual(
            validate_d5.canonical_file_set_hash(files),
            "d0df7d935ecc939ff118593a38f6242b266f147357ff1daa40e451a3abe16be7")

    def test_detect_triggers_supports_option_and_positional_and_rejects_unapproved(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            intake = approved_intake("Alias Test", "ALS")
            path = write(root / "intake.json", json.dumps(intake, ensure_ascii=False))
            positional = run_cli([
                sys.executable, str(SCRIPT_DIR / "detect_triggers.py"), str(path)])
            option = run_cli([
                sys.executable, str(SCRIPT_DIR / "detect_triggers.py"),
                "--intake", str(path)])
            self.assertEqual(positional.returncode, 0, positional.stderr)
            self.assertEqual(option.returncode, 0, option.stderr)
            self.assertEqual(json.loads(positional.stdout), json.loads(option.stdout))

            intake["answers"]["D0-A01"]["status"] = "proposed"
            intake["answers"]["D0-A01"]["approvedBy"] = None
            intake["answers"]["D0-A01"]["approvedAt"] = None
            path.write_text(json.dumps(intake, ensure_ascii=False), encoding="utf-8")
            rejected = run_cli([
                sys.executable, str(SCRIPT_DIR / "detect_triggers.py"), "--intake", str(path)])
            self.assertEqual(rejected.returncode, 2)
            self.assertIn("must be fact or approved", rejected.stderr)

            blank = approved_intake("Alias Test", "ALS")
            blank["answers"]["D0-A01"].update({
                "value": None, "status": "unanswered", "source": None,
                "evidence": [], "approvedBy": None, "approvedAt": None})
            blank["state"].update({
                "approved": False, "approved_by": None,
                "approved_at": None, "approval_evidence": None})
            self.assertEqual(detect_triggers.validate_intake(blank, require_approved=False), [])

            semantic = approved_intake("Alias Test", "ALS")
            semantic["product"]["one_sentence"] = "  "
            semantic["technical"]["toolchain"] = "UNKNOWN"
            errors = detect_triggers.validate_intake(semantic)
            self.assertTrue(any("one_sentence" in error for error in errors), errors)
            self.assertTrue(any("toolchain" in error for error in errors), errors)

            provenance = approved_intake("Alias Test", "ALS")
            del provenance["fieldSources"]["technical.analytics"]
            provenance["fieldSources"]["technical.mobile"] = ["D0-B05", "D0-B05"]
            errors = detect_triggers.validate_intake(provenance)
            self.assertTrue(any("fieldSources is missing" in error for error in errors), errors)
            self.assertTrue(any("technical.mobile" in error for error in errors), errors)

    def test_scaffold_late_intake_reconcile_is_safe_and_registers_machine_artifacts(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            initial = run_cli([
                sys.executable, str(SCRIPT_DIR / "scaffold_project.py"),
                "--project-name", "Reconcile", "--prefix", "REC",
                "--project-root", str(root)])
            self.assertEqual(initial.returncode, 0, initial.stderr)
            gdd = root / "docs" / "REC_gdd.md"
            authored = gdd.read_text(encoding="utf-8") + "\nUSER CANONICAL EDIT\n"
            gdd.write_text(authored, encoding="utf-8")

            intake_path = write(
                root / "approved.json",
                json.dumps(approved_intake("Reconcile", "REC"), ensure_ascii=False))
            reconciled = run_cli([
                sys.executable, str(SCRIPT_DIR / "scaffold_project.py"),
                "--project-name", "Reconcile", "--prefix", "REC",
                "--project-root", str(root), "--intake", str(intake_path)])
            self.assertEqual(reconciled.returncode, 0, reconciled.stderr)
            self.assertEqual(gdd.read_text(encoding="utf-8"), authored)
            canonical_intake = json.loads(
                (root / "docs" / "REC_intake.json").read_text(encoding="utf-8"))
            self.assertTrue(canonical_intake["state"]["approved"])
            manifest_path = root / "docs" / "REC_docs_manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            paths = {item["path"] for item in manifest["documents"]}
            schema_names = {path.name for path in (SCRIPT_DIR.parent / "schemas").glob("*.schema.json")}
            self.assertTrue({f"docs/schemas/{name}" for name in schema_names} <= paths)
            instance_names = {path.name for path in (SCRIPT_DIR.parent / "schemas").glob("*.json")
                              if not path.name.endswith(".schema.json")}
            self.assertTrue({f"docs/schemas/REC_{name}" for name in instance_names} <= paths)
            self.assertIn(".claude/p0-check.json", paths)
            p0_config = json.loads(
                (root / ".claude" / "p0-check.json").read_text(encoding="utf-8"))
            for key in ("open_docs", "decision_ref_docs"):
                self.assertIn(
                    "docs/specs/REC_analytics_observability_spec.md", p0_config[key])
                self.assertIn(
                    "docs/specs/REC_asset_content_pipeline_spec.md", p0_config[key])
            self.assertFalse(p0_config["rules"]["git-current-facts"])

            req_before = (root / "docs" / "REC_required_specs.json").read_bytes()
            rerun = run_cli([
                sys.executable, str(SCRIPT_DIR / "scaffold_project.py"),
                "--project-name", "Reconcile", "--prefix", "REC",
                "--project-root", str(root)])
            self.assertEqual(rerun.returncode, 0, rerun.stderr)
            self.assertEqual((root / "docs" / "REC_required_specs.json").read_bytes(), req_before)
            manifest_before = manifest_path.read_bytes()
            other_path = write(
                root / "other.json",
                json.dumps(approved_intake("Reconcile", "REC", "v2"), ensure_ascii=False))
            refused = run_cli([
                sys.executable, str(SCRIPT_DIR / "scaffold_project.py"),
                "--project-name", "Reconcile", "--prefix", "REC",
                "--project-root", str(root), "--intake", str(other_path)])
            self.assertEqual(refused.returncode, 2)
            self.assertIn("refusing to overwrite", refused.stderr)
            self.assertEqual((root / "docs" / "REC_required_specs.json").read_bytes(), req_before)
            self.assertEqual(manifest_path.read_bytes(), manifest_before)
            self.assertEqual(gdd.read_text(encoding="utf-8"), authored)

    def test_empty_d3_traceability_fails_and_p0_strict_rejects_unchecked_note(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            trace = write(root / "requirements.csv",
                          (SCRIPT_DIR.parent / "schemas" / "requirements.csv").read_text(encoding="utf-8"))
            traced = run_cli([
                sys.executable, str(SCRIPT_DIR / "validate_traceability.py"),
                str(trace), "--gate", "D3"])
            self.assertEqual(traced.returncode, 1)
            self.assertIn("D3 requires at least one", traced.stdout)

            warned = run_cli([
                sys.executable, str(SCRIPT_DIR / "validate_traceability.py"),
                str(trace), "--gate", "D2"])
            self.assertEqual(warned.returncode, 1)
            self.assertIn("FAIL", warned.stdout)

            p0 = run_cli([
                sys.executable, str(SCRIPT_DIR / "check_p0_state.py"),
                "--project-root", str(root), "--strict", "--only", "open-evidence"])
            self.assertEqual(p0.returncode, 1, p0.stderr)
            self.assertIn("note", p0.stdout)
            self.assertIn("FAIL", p0.stdout)

    def test_d2_machine_contracts_reject_empty_and_identity_drift_then_pass(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            intake_path = write(
                root / "approved.json",
                json.dumps(approved_intake("Machine", "MAC"), ensure_ascii=False))
            made = run_cli([
                sys.executable, str(SCRIPT_DIR / "scaffold_project.py"),
                "--project-name", "Machine", "--prefix", "MAC",
                "--project-root", str(root), "--intake", str(intake_path)])
            self.assertEqual(made.returncode, 0, made.stderr)
            manifest = json.loads(
                (root / "docs" / "MAC_docs_manifest.json").read_text(encoding="utf-8"))
            errors: list[str] = []
            validate_docs_module.validate_d2_machine_contracts(
                root, "MAC", manifest, errors, [])
            self.assertTrue(any("is empty" in error for error in errors), errors)

            analytics_path = root / "docs" / "schemas" / "MAC_analytics_events.json"
            analytics = json.loads(analytics_path.read_text(encoding="utf-8"))
            analytics["events"] = [{
                "id": "AN-MAC-001", "name": "session_start", "source": "server",
                "trigger": "session starts", "fields": {}, "sampling": 1,
                "expectedVolumePerDau": 1, "kpis": ["sessions"],
                "privacyNotes": "none", "test": "emit once", "status": "approved",
            }]
            analytics_path.write_text(json.dumps(analytics), encoding="utf-8")
            asset_path = root / "docs" / "schemas" / "MAC_asset_ledger.json"
            assets = json.loads(asset_path.read_text(encoding="utf-8"))
            assets["assets"] = [{
                "id": "ASSET-MAC-001", "type": "model", "purpose": "test fixture",
                "source": "project-owned", "rightsStatus": "approved",
                "rightsEvidence": "DECISIONS.md", "owner": "Project Owner",
                "polycount": 1, "textureBudget": None, "lod": None,
                "collision": "box", "moderationStatus": "approved",
                "blockingWorkPackage": None, "status": "ready", "fallback": None,
            }]
            asset_path.write_text(json.dumps(assets), encoding="utf-8")
            errors = []
            validate_docs_module.validate_d2_machine_contracts(
                root, "MAC", manifest, errors, [])
            self.assertEqual(errors, [])

            analytics["events"][0]["sampling"] = 2
            analytics_path.write_text(json.dumps(analytics), encoding="utf-8")
            errors = []
            validate_docs_module.validate_d2_machine_contracts(
                root, "MAC", manifest, errors, [])
            self.assertTrue(any("above maximum" in error for error in errors), errors)
            analytics["events"][0]["sampling"] = 1

            d5_errors: list[str] = []
            analytics["events"][0]["status"] = "proposed"
            analytics_path.write_text(json.dumps(analytics), encoding="utf-8")
            validate_docs_module.validate_d2_machine_contracts(
                root, "MAC", manifest, d5_errors, [], "D5")
            self.assertTrue(any("remains proposed" in error for error in d5_errors), d5_errors)
            analytics["events"][0]["status"] = "approved"
            analytics_path.write_text(json.dumps(analytics), encoding="utf-8")

            unregistered = json.loads(json.dumps(manifest))
            unregistered["documents"] = [
                item for item in unregistered["documents"]
                if item["path"] != "docs/schemas/MAC_analytics_events.json"]
            errors = []
            validate_docs_module.validate_d2_machine_contracts(
                root, "MAC", unregistered, errors, [])
            self.assertTrue(any("exactly one manifest row" in error for error in errors), errors)

            analytics["prefix"] = "BAD"
            analytics_path.write_text(json.dumps(analytics), encoding="utf-8")
            errors = []
            validate_docs_module.validate_d2_machine_contracts(
                root, "MAC", manifest, errors, [])
            self.assertTrue(any("identity mismatch" in error for error in errors), errors)

            remote_schema = json.loads(
                (SCRIPT_DIR.parent / "schemas" / "remote_contract.schema.json").read_text(
                    encoding="utf-8"))
            refill_schema = remote_schema["$defs"]["contract"]["properties"][
                "rateLimit"]["properties"]["refillPerSecond"]
            errors = validate_docs_module.structural_schema_errors(
                0, refill_schema, remote_schema, "$.refillPerSecond")
            self.assertTrue(any("exclusiveMinimum" in error for error in errors), errors)

    def test_d5_acceptance_positive_snapshot_then_tamper_failures(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td).resolve()
            fixture = build_d5_fixture(root)
            source = root / "source-project"
            source.mkdir()
            package_rel = fixture["package"].relative_to(root)
            accepted = run_cli([
                sys.executable, str(SCRIPT_DIR / "validate_d5_acceptance.py"),
                "--project-root", str(root), "--source-project-root", str(source),
                "--prefix", "DVT", "--package", str(package_rel), "--json"])
            self.assertEqual(accepted.returncode, 0, accepted.stdout + accepted.stderr)
            self.assertTrue(json.loads(accepted.stdout)["pass"])

            snapshot = fixture["b1_snapshot_machine"]
            snapshot_original = snapshot.read_bytes()
            snapshot.write_bytes(snapshot_original + b"tampered")
            rejected = validate_d5.validate(root, "DVT", fixture["package"], source)
            self.assertFalse(rejected["pass"])
            self.assertTrue(any("historical" in error for error in rejected["errors"]),
                            rejected["errors"])
            snapshot.write_bytes(snapshot_original)

            current = fixture["current_machine"]
            current.write_bytes(current.read_bytes() + b"unauthorized")
            rejected = validate_d5.validate(root, "DVT", fixture["package"], source)
            self.assertFalse(rejected["pass"])
            self.assertTrue(any("unauthorized artifact" in error for error in rejected["errors"]),
                            rejected["errors"])

    def test_d5_missing_commit_object_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td).resolve()
            errors: list[str] = []
            value = validate_d5.historical_bytes(
                root, root,
                {"kind": "commit", "value": "0" * 40,
                 "snapshotRoot": None, "gitStatusEvidence": None},
                "docs/missing.md", errors, "commit fixture")
            self.assertIsNone(value)
            self.assertTrue(any("unavailable" in error for error in errors), errors)

    def test_d5_rejects_unresolved_inventory_and_weak_decision_binding(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td).resolve()
            fixture = build_d5_fixture(root)
            source = root / "source"
            source.mkdir()

            machine = fixture["current_machine"]
            machine_before = machine.read_bytes()
            machine.write_bytes(machine_before + b"[OPEN blocking: yes]")
            result = validate_d5.validate(root, "DVT", fixture["package"], source)
            self.assertTrue(any("unresolved D5 state token" in error
                                for error in result["errors"]), result["errors"])
            machine.write_bytes(machine_before)

            decisions = root / "DECISIONS.md"
            decisions_before = decisions.read_bytes()
            decisions.write_bytes(
                decisions_before.replace(b"human-direct", b"inspection-only"))
            result = validate_d5.validate(root, "DVT", fixture["package"], source)
            self.assertTrue(any("human-direct approval kind" in error
                                for error in result["errors"]), result["errors"])

    def test_d5_rejects_preapproved_b1_weak_history_and_inventory_drift(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td).resolve()
            fixture = build_d5_fixture(root)
            source = root / "source"
            source.mkdir()

            # Snapshot layout is <snapshot>/docs/schemas/file; address the formal file from root.
            snapshot_root = fixture["b1_snapshot_machine"].parents[2]
            old_index = snapshot_root / "docs" / "DVT_docs_index.md"
            old_bytes = old_index.read_bytes()
            old_index.write_bytes(old_bytes.replace(b"| Status | Review |", b"| Status | Approved |"))
            result = validate_d5.validate(root, "DVT", fixture["package"], source)
            self.assertTrue(any("historical B1 formal Status" in error
                                for error in result["errors"]), result["errors"])
            old_index.write_bytes(old_bytes)

            current_index = root / "docs" / "DVT_docs_index.md"
            current_bytes = current_index.read_bytes()
            current_index.write_bytes(current_bytes.replace(
                b"D5-APP-001 approval", b"D5 approval"))
            result = validate_d5.validate(root, "DVT", fixture["package"], source)
            self.assertTrue(any("exactly one change-history row" in error
                                for error in result["errors"]), result["errors"])
            current_index.write_bytes(current_bytes)

            manifest_path = root / "docs" / "DVT_docs_manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["documents"] = [
                item for item in manifest["documents"]
                if item["path"] != "docs/schemas/DVT_machine.json"]
            json_file(manifest_path, manifest)
            result = validate_d5.validate(root, "DVT", fixture["package"], source)
            self.assertTrue(any("canonical file set mismatch" in error
                                for error in result["errors"]), result["errors"])


class LintRuleTests(unittest.TestCase):
    def test_home_heading_is_definition_but_bare_reference_is_not(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            path = write(
                root / "DECISIONS.md",
                "### D-001: Approved title\n\nSee D-002 for the other choice.\n")
            doc = lint_docs.Doc(root, path)
            cfg = dict(lint_docs.DEFAULT_CONFIG)
            cfg["decision_id_home_docs"] = ["DECISIONS.md"]
            findings = []
            lint_docs.rule_bare_decision_id(root, [doc], cfg, findings)
            self.assertEqual([(f.line, f.rule) for f in findings], [(3, "bare-decision-id")])

    def test_h_id_table_row_requires_exec_without_human_tag(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            path = write(
                root / "HUMAN_ACTIONS.md",
                "| ID | Action | Status |\n|---|---|---|\n| H-001 | Confirm IDs | Open |\n")
            doc = lint_docs.Doc(root, path)
            cfg = dict(lint_docs.DEFAULT_CONFIG)
            cfg["human_action_ledgers"] = ["HUMAN_ACTIONS.md"]
            findings = []
            lint_docs.rule_human_action_exec_class(root, [doc], cfg, findings)
            self.assertEqual(len(findings), 1)
            self.assertEqual(findings[0].line, 3)

            write(
                path,
                "| ID | Action | Exec | Status |\n|---|---|---|---|\n"
                "| H-001 | Confirm IDs | `human-only` | Open |\n")
            doc = lint_docs.Doc(root, path)
            findings = []
            lint_docs.rule_human_action_exec_class(root, [doc], cfg, findings)
            self.assertEqual(findings, [])

            write(
                path,
                "| ID | Action | Exec | Status |\n|---|---|---|---|\n"
                "| H-001 | Confirm IDs | `ai-studio` | Open |\n")
            doc = lint_docs.Doc(root, path)
            findings = []
            lint_docs.rule_human_action_exec_class(root, [doc], cfg, findings)
            self.assertEqual(len(findings), 1)

    def test_completed_human_action_requires_actual_evidence_and_timezone(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            path = write(
                root / "HUMAN_ACTIONS.md",
                "| ID | Action | Exec | Status | Actual evidence | Completed at |\n"
                "|---|---|---|---|---|---|\n"
                "| H-001 | Approve | `human-only` | Completed | — | — |\n")
            cfg = dict(lint_docs.DEFAULT_CONFIG)
            cfg["human_action_ledgers"] = ["HUMAN_ACTIONS.md"]
            findings = []
            lint_docs.rule_human_action_exec_class(
                root, [lint_docs.Doc(root, path)], cfg, findings)
            self.assertEqual(len(findings), 2)
            write(
                path,
                "| ID | Action | Exec | Status | Actual evidence | Completed at |\n"
                "|---|---|---|---|---|---|\n"
                "| H-001 | Approve | `human-only` | Completed | `records/H-001.json` | 2026-08-20T12:00:00+09:00 |\n")
            findings = []
            lint_docs.rule_human_action_exec_class(
                root, [lint_docs.Doc(root, path)], cfg, findings)
            self.assertEqual(findings, [])

    def test_ai_action_requires_ai_exec_class(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            path = write(
                root / "AI_ACTIONS.md",
                "| ID | Action | Status |\n|---|---|---|\n"
                "| AI-001 | Capture Studio metrics | Open |\n")
            doc = lint_docs.Doc(root, path)
            cfg = dict(lint_docs.DEFAULT_CONFIG)
            cfg["ai_action_ledgers"] = ["AI_ACTIONS.md"]
            findings = []
            lint_docs.rule_ai_action_exec_class(root, [doc], cfg, findings)
            self.assertEqual(len(findings), 1)
            self.assertEqual(findings[0].line, 3)

            write(
                path,
                "| ID | Action | Exec | Status |\n|---|---|---|---|\n"
                "| AI-001 | Capture Studio metrics | `ai-studio` | Open |\n")
            doc = lint_docs.Doc(root, path)
            findings = []
            lint_docs.rule_ai_action_exec_class(root, [doc], cfg, findings)
            self.assertEqual(findings, [])

    def test_action_tag_explanation_is_not_an_entry(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            human = write(
                root / "HUMAN_ACTIONS.md",
                "[HUMAN] means a person performs the action.\n")
            ai = write(
                root / "AI_ACTIONS.md",
                "[AI-ACTION] means a bounded machine action.\n")
            cfg = dict(lint_docs.DEFAULT_CONFIG)
            cfg["human_action_ledgers"] = ["HUMAN_ACTIONS.md"]
            cfg["ai_action_ledgers"] = ["AI_ACTIONS.md"]
            findings = []
            lint_docs.rule_human_action_exec_class(
                root, [lint_docs.Doc(root, human)], cfg, findings)
            lint_docs.rule_ai_action_exec_class(
                root, [lint_docs.Doc(root, ai)], cfg, findings)
            self.assertEqual(findings, [])


class RelatedSkillIntegrationTests(unittest.TestCase):
    def test_semantic_pipeline_scaffold_reconcile_detect_gen_and_fail_closed_gates(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            intake_path = write(
                root / "approved.json",
                json.dumps(approved_intake("Pipeline", "PIP"), ensure_ascii=False))
            made = run_cli([
                sys.executable, str(SCRIPT_DIR / "scaffold_project.py"),
                "--project-name", "Pipeline", "--prefix", "PIP",
                "--project-root", str(root)])
            self.assertEqual(made.returncode, 0, made.stdout + made.stderr)
            reconciled = run_cli([
                sys.executable, str(SCRIPT_DIR / "scaffold_project.py"),
                "--project-name", "Pipeline", "--prefix", "PIP",
                "--project-root", str(root), "--intake", str(intake_path)])
            self.assertEqual(reconciled.returncode, 0, reconciled.stdout + reconciled.stderr)

            detected = run_cli([
                sys.executable, str(SCRIPT_DIR / "detect_triggers.py"),
                "--intake", str(root / "docs" / "PIP_intake.json")])
            self.assertEqual(detected.returncode, 0, detected.stderr)
            required = json.loads(
                (root / "docs" / "PIP_required_specs.json").read_text(encoding="utf-8"))
            self.assertEqual(json.loads(detected.stdout)["required_specs"],
                             required["required_specs"])

            generated = run_cli([
                sys.executable, str(SCRIPT_DIR / "gen_index.py"),
                "--project-root", str(root), "--emit", "both",
                "--output", "docs/PIP_docs_manifest.json",
                "--index-output", "docs/PIP_docs_index.md"])
            self.assertEqual(generated.returncode, 0, generated.stdout + generated.stderr)
            manifest = json.loads(
                (root / "docs" / "PIP_docs_manifest.json").read_text(encoding="utf-8"))
            index_rows = validate_d5.parse_index(root / "docs" / "PIP_docs_index.md", [])
            self.assertEqual(set(index_rows), {item["path"] for item in manifest["documents"]})

            linted = run_cli([
                sys.executable, str(SCRIPT_DIR / "lint_docs.py"),
                "--project-root", str(root), "--config", ".claude/doc-lint.json",
                "--files", "HUMAN_ACTIONS.md", "AI_ACTIONS.md", "--only",
                "human-action-exec-class", "ai-action-exec-class"])
            self.assertEqual(linted.returncode, 0, linted.stdout + linted.stderr)
            d0 = run_cli([
                sys.executable, str(SCRIPT_DIR / "validate_docs.py"),
                "--project-root", str(root), "--prefix", "PIP", "--gate", "D0"])
            self.assertEqual(d0.returncode, 0, d0.stdout + d0.stderr)

            # Generated P0 config does not require Git, but unresolved D0-D3
            # state still blocks P0; a missing W0 package likewise blocks D5.
            p0 = run_cli([
                sys.executable, str(SCRIPT_DIR / "check_p0_state.py"),
                "--project-root", str(root), "--prefix", "PIP", "--strict"])
            self.assertEqual(p0.returncode, 1, p0.stdout + p0.stderr)
            self.assertNotIn("[git-current-facts]", p0.stdout)
            d5 = run_cli([
                sys.executable, str(SCRIPT_DIR / "validate_d5_acceptance.py"),
                "--project-root", str(root), "--prefix", "PIP",
                "--package", "docs/evidence/d5/missing.json"])
            self.assertEqual(d5.returncode, 1, d5.stdout + d5.stderr)

    def test_cross_skill_seams(self):
        passed = check_skill_seams.run_checks()
        self.assertGreaterEqual(len(passed), 20)

    def test_architect_scaffold_action_ledgers_match_lint_contract(self):
        scaffold = SCRIPT_DIR / "scaffold_project.py"
        validator = SCRIPT_DIR / "validate_docs.py"
        config = SCRIPT_DIR.parent / "templates" / "doc-lint.json"
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            made = run_cli(
                [sys.executable, str(scaffold), "--project-name", "Verify",
                 "--prefix", "VFY", "--project-root", str(root)])
            self.assertEqual(made.returncode, 0, made.stdout + made.stderr)
            self.assertTrue((root / "HUMAN_ACTIONS.md").is_file())
            self.assertTrue((root / "AI_ACTIONS.md").is_file())

            linted = run_cli(
                [sys.executable, str(SCRIPT_DIR / "lint_docs.py"),
                 "--project-root", str(root), "--config", str(config),
                 "--files", "HUMAN_ACTIONS.md", "AI_ACTIONS.md", "--only",
                 "human-action-exec-class", "ai-action-exec-class"])
            self.assertEqual(linted.returncode, 0, linted.stdout + linted.stderr)

            checked = run_cli(
                [sys.executable, str(validator), "--project-root", str(root),
                 "--prefix", "VFY", "--gate", "D0", "--json"])
            self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)

    def test_decision_requires_human_approval_record_separately_from_source(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            path = write(
                root / "docs" / "gdd.md",
                "[DECISION] Keep the loop. src: U\n")
            doc = lint_docs.Doc(root, path)
            cfg = dict(lint_docs.DEFAULT_CONFIG)
            findings = []
            lint_docs.rule_decision_approval_record(root, [doc], cfg, findings)
            self.assertEqual(len(findings), 1)

            write(
                path,
                "[DECISION] Keep the loop. src: U\n"
                "- approver: Project Owner\n"
                "- approval_record: DECISIONS.md D-001\n")
            doc = lint_docs.Doc(root, path)
            findings = []
            lint_docs.rule_decision_approval_record(root, [doc], cfg, findings)
            self.assertEqual(findings, [])

    def test_status_config_outside_explicit_file_scope_is_skipped(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            path = write(root / "docs" / "one.md", "# One\n")
            doc = lint_docs.Doc(root, path)
            cfg = dict(lint_docs.DEFAULT_CONFIG)
            cfg["status_consistency"] = [{
                "file": "docs/work_packages.md",
                "id_pattern": r"WP-\d+",
                "field": "Status",
            }]
            cfg["_files_explicit"] = True
            findings = []
            lint_docs.rule_status_index_drift(root, [doc], cfg, findings)
            self.assertEqual(findings, [])

    def test_cli_files_scope_skips_other_status_target(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            write(root / "docs" / "one.md", "# One\n")
            write(
                root / "docs" / "work_packages.md",
                "| ID | Status |\n|---|---|\n| WP-1 | Draft |\n\n"
                "## WP-1\n- Status: Draft\n")
            config = {
                "doc_globs": ["docs/*.md"],
                "exclude_globs": [],
                "status_consistency": [{
                    "file": "docs/work_packages.md",
                    "id_pattern": "WP-[0-9]+",
                    "field": "Status",
                    "blanket_phrases": [],
                    "index_only_ids": [],
                }],
            }
            config_path = write(
                root / ".claude" / "doc-lint.json",
                json.dumps(config, ensure_ascii=False))
            result = run_cli(
                [sys.executable, str(SCRIPT_DIR / "lint_docs.py"),
                 "--project-root", str(root), "--config", str(config_path),
                 "--files", "docs/one.md", "--only", "status-index-drift"])
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("PASS", result.stdout)

    def test_warning_and_unverified_note_fail_the_gate(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            write(root / "docs" / "one.md", "Latency is 10 ms.\n")
            config = {
                "doc_globs": ["docs/*.md"],
                "exclude_globs": [],
                "value_owner_docs": ["docs/owner.md"],
                "rules": {},
            }
            config_path = write(
                root / ".claude" / "doc-lint.json",
                json.dumps(config, ensure_ascii=False))

            warned = run_cli(
                [sys.executable, str(SCRIPT_DIR / "lint_docs.py"),
                 "--project-root", str(root), "--config", str(config_path),
                 "--only", "unreferenced-value"])
            self.assertEqual(warned.returncode, 1)
            self.assertIn("FAIL", warned.stdout)

            config["value_owner_docs"] = []
            config_path.write_text(json.dumps(config, ensure_ascii=False), encoding="utf-8")
            noted = run_cli(
                [sys.executable, str(SCRIPT_DIR / "lint_docs.py"),
                 "--project-root", str(root), "--config", str(config_path),
                 "--only", "unreferenced-value"])
            self.assertEqual(noted.returncode, 1)
            self.assertIn("unverified 1", noted.stdout)

    def test_template_does_not_enable_nonexistent_status_target(self):
        template = json.loads(
            (SCRIPT_DIR.parent / "templates" / "doc-lint.json").read_text(encoding="utf-8"))
        self.assertEqual(template["status_consistency"], [])


if __name__ == "__main__":
    unittest.main()
