#!/usr/bin/env python3
"""gen_index.py / lint_docs.py の再発防止テスト。標準ライブラリのみ。"""
from __future__ import annotations

import importlib.util
import datetime as dt
import hashlib
import json
import os
import shutil
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
state_readiness = load_module("state_readiness")

_PINNED_RUNTIME_TEMP = None
_PINNED_RUNTIME: tuple[dict, dict] | None = None
_PINNED_PWSH_TEMP = None
_PINNED_PWSH: tuple[dict, dict, str] | None = None


def write(path: Path, text: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


def run_cli(args: list[str]) -> subprocess.CompletedProcess[str]:
    """Decode child output deterministically on Windows (never locale/cp932)."""
    return subprocess.run(
        args, text=True, encoding="utf-8", errors="replace", capture_output=True)


def run_w0_cli(args: list[str]) -> subprocess.CompletedProcess[str]:
    """Launch the validator from a fresh exact pinned-copy capsule."""
    try:
        config_arg = args[args.index("--provenance-config") + 1]
        config = json.loads(Path(config_arg).read_text(encoding="utf-8"))
        python_path = config["w0ValidatorRuntime"]["pythonExecutable"]["path"]
        fixed_args = config["w0ValidatorRuntime"]["pythonExecutable"]["fixedArgs"]
    except (ValueError, IndexError, KeyError, OSError, json.JSONDecodeError) as exc:
        raise AssertionError("run_w0_cli requires a valid --provenance-config") from exc
    with tempfile.TemporaryDirectory(prefix="w0-test-launch-") as td:
        root = Path(td)
        scripts = root / "scripts"
        scripts.mkdir()
        for name in (
                "validate_d5_acceptance.py", "gen_index.py",
                "state_readiness.py", "strict_json.py"):
            shutil.copy2(SCRIPT_DIR / name, scripts / name)
        return run_cli([
            python_path, *fixed_args,
            str(scripts / "validate_d5_acceptance.py"),
            "--installed-skill-root", str(SCRIPT_DIR.parent.resolve()), *args,
        ])


def validate_fixture(
        root: Path, fixture: dict[str, Path], source: Path) -> dict:
    return validate_d5.validate(
        root, "DVT", fixture["package"], source,
        fixture["provenance_config"], SCRIPT_DIR.parent.resolve())


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


def pinned_test_runtime() -> tuple[dict, dict]:
    """Build one isolated, fully manifested stdlib runtime for W0 subprocesses."""
    global _PINNED_RUNTIME_TEMP, _PINNED_RUNTIME
    if _PINNED_RUNTIME is not None:
        return _PINNED_RUNTIME
    _PINNED_RUNTIME_TEMP = tempfile.TemporaryDirectory(prefix="docs-pinned-python-")
    operator = Path(_PINNED_RUNTIME_TEMP.name)
    runtime = operator / "runtime"
    runtime.mkdir()
    source_root = Path(sys.executable).resolve().parent
    for name in ("python.exe", "python3.dll", "python310.dll",
                 "vcruntime140.dll", "vcruntime140_1.dll"):
        source = source_root / name
        if source.is_file():
            shutil.copy2(source, runtime / name)

    excluded = {"site-packages", "test", "tests", "tkinter", "idlelib", "ensurepip"}

    def ignore(_directory: str, names: list[str]) -> set[str]:
        return {name for name in names if name.lower() in excluded or name == "__pycache__"}

    for directory in ("DLLs", "Lib"):
        shutil.copytree(
            source_root / directory, runtime / directory,
            ignore=ignore, copy_function=shutil.copy2)
    files = [{
        "path": path.relative_to(runtime).as_posix(),
        "bytes": path.stat().st_size,
        "sha256": sha_path(path),
    } for path in sorted(runtime.rglob("*"), key=lambda item: item.as_posix())
        if path.is_file()]
    manifest_bytes = json.dumps(
        {"files": files}, ensure_ascii=False, sort_keys=True,
        separators=(",", ":"))
    manifest = write(operator / "library-manifest.json", manifest_bytes)
    python_path = (runtime / "python.exe").resolve()
    version_result = run_cli([
        str(python_path), "-B", "-S", "-E", "-X", "utf8", "--version"])
    version = version_result.stdout.strip() or version_result.stderr.strip()
    if version_result.returncode != 0:
        raise RuntimeError(version_result.stdout + version_result.stderr)
    python_pin = {
        "path": str(python_path), "bytes": python_path.stat().st_size,
        "sha256": sha_path(python_path), "version": version,
        "fixedArgs": ["-B", "-S", "-E", "-X", "utf8"],
    }
    library_pin = {
        "path": str(runtime.resolve()),
        "manifestFormat": "canonical-library-tree-v1",
        "manifestPath": str(manifest.resolve()),
        "manifestSha256": sha_path(manifest),
        "treeSha256": validate_d5.canonical_json_sha256(files),
    }
    _PINNED_RUNTIME = python_pin, library_pin
    return _PINNED_RUNTIME


def pinned_test_powershell() -> tuple[dict, dict, str]:
    global _PINNED_PWSH_TEMP, _PINNED_PWSH
    if _PINNED_PWSH is not None:
        return _PINNED_PWSH
    executable_raw = shutil.which("pwsh")
    if executable_raw is None:
        raise unittest.SkipTest("PowerShell 7 is unavailable")
    executable = Path(executable_raw).resolve()
    runtime = executable.parent
    files = [{
        "path": path.relative_to(runtime).as_posix(),
        "bytes": path.stat().st_size, "sha256": sha_path(path),
    } for path in sorted(runtime.rglob("*"), key=lambda item: item.as_posix())
        if path.is_file()]
    _PINNED_PWSH_TEMP = tempfile.TemporaryDirectory(prefix="docs-pinned-pwsh-")
    manifest = write(
        Path(_PINNED_PWSH_TEMP.name) / "pwsh-runtime-manifest.json",
        json.dumps({"files": files}, ensure_ascii=False, sort_keys=True,
                   separators=(",", ":")))
    binary = {
        "path": str(executable), "bytes": executable.stat().st_size,
        "sha256": sha_path(executable),
    }
    tree = {
        "path": str(runtime), "manifestFormat": "canonical-library-tree-v1",
        "manifestPath": str(manifest.resolve()), "manifestSha256": sha_path(manifest),
        "treeSha256": validate_d5.canonical_json_sha256(files),
    }
    version_result = run_cli([
        str(executable), "-NoLogo", "-NoProfile", "-NonInteractive", "-Command",
        "$PSVersionTable.PSVersion.ToString()"])
    if version_result.returncode != 0:
        raise RuntimeError(version_result.stdout + version_result.stderr)
    _PINNED_PWSH = binary, tree, version_result.stdout.strip()
    return _PINNED_PWSH


def make_provenance_config(root: Path) -> Path:
    operator = root.parent / f"{root.name}-operator"
    operator.mkdir(parents=True, exist_ok=True)
    adapter_source = (
        "import datetime as dt,hashlib,json,pathlib,sys\n"
        "q=json.loads(sys.stdin.buffer.read().decode('utf-8'))\n"
        "out=pathlib.Path(q['outputDirectory']); out.mkdir(parents=True,exist_ok=True)\n"
        "raw=out/'fresh.json'; raw.write_bytes(b'{}')\n"
        "r={'schemaVersion':'1.0.0','id':'TRQ-FRESH-'+q['nonce'][:16].upper(),"
        "'authority':q['authority'],'adapter':'test-adapter','adapterVersion':'1.0.0',"
        "'nonce':q['nonce'],'queriedAt':dt.datetime.now(dt.timezone.utc).isoformat(),"
        "'requestId':'REQ-'+q['nonce'][:16],'responseId':'RESP-'+q['nonce'][:16],"
        "'subjectType':q['subjectType'],'subjectId':q['subjectId'],"
        "'claimsSha256':q['claimsSha256'],'rawResponseArtifact':"
        "{'path':str(raw),'sha256':hashlib.sha256(raw.read_bytes()).hexdigest()}}\n"
        "sys.stdout.buffer.write(json.dumps(r,ensure_ascii=False,sort_keys=True,"
        "separators=(',',':')).encode('utf-8'))\n")
    adapter = write(operator / "adapter.py", adapter_source)
    signature_source = (
        "import json,sys\n"
        "q=json.loads(sys.stdin.buffer.read().decode('utf-8'))\n"
        "r={'verified':True,'authority':q['authority'],'algorithm':q['algorithm'],"
        "'keyId':q['keyId'],'claimsSha256':q['claimsSha256']}\n"
        "sys.stdout.buffer.write(json.dumps(r,ensure_ascii=False,sort_keys=True,"
        "separators=(',',':')).encode('utf-8'))\n")
    signature_adapter = write(operator / "signature-verifier.py", signature_source)
    trust_anchor = write(operator / "test-trust-anchor.der", "test pinned anchor\n")
    python_pin, library_pin = pinned_test_runtime()
    python_path = Path(python_pin["path"])
    skill_root = SCRIPT_DIR.parent.resolve()
    skill_files = [{
        "path": path.relative_to(skill_root).as_posix(),
        "bytes": path.stat().st_size, "sha256": sha_path(path),
    } for path in sorted(skill_root.rglob("*"), key=lambda item: item.as_posix())
        if path.is_file()]
    skill_manifest = write(
        operator / "installed-skill-manifest.json",
        json.dumps({"files": skill_files}, ensure_ascii=False, sort_keys=True,
                   separators=(",", ":")))
    skill_closure = {
        "path": str(skill_root), "manifestFormat": "canonical-library-tree-v1",
        "manifestPath": str(skill_manifest.resolve()),
        "manifestSha256": sha_path(skill_manifest),
        "treeSha256": validate_d5.canonical_json_sha256(skill_files),
    }
    authority_constants = {
        "authority": "test-runtime-authority",
        "verificationMode": "receiver-native-rsa-pss-sha256",
        "keyId": "TEST-RUNTIME-KEY-001",
        "trustAnchor": {"path": str(trust_anchor.resolve()),
                        "sha256": sha_path(trust_anchor)},
        "trustAnchorFormat": "x509-der",
        "prepareExecutionSchemaId": "https://example.invalid/roblox-ai-development-os/w0-runtime-prepare-execution-attestation.schema.json",
        "prelaunchSchemaId": "https://example.invalid/roblox-ai-development-os/w0-runtime-prelaunch-assertion.schema.json",
        "postexecutionSchemaId": "https://example.invalid/roblox-ai-development-os/w0-runtime-postexecution-attestation.schema.json",
        "runAuthorizationSchemaId": "https://example.invalid/roblox-ai-development-os/w0-run-authorization.schema.json",
        "runAdmissionSchemaId": "https://example.invalid/roblox-ai-development-os/w0-run-admission-attestation.schema.json",
        "admitExecutionSchemaId": "https://example.invalid/roblox-ai-development-os/w0-runtime-admit-execution-attestation.schema.json",
        "detachedSignatureProtocol": "raw-fixed-order-json-detached-rsa-pss-sha256-v1",
        "signedBytesSerialization": "fixed-property-order-minified-utf8-no-bom-no-newline-v1",
        "signatureEncoding": "base64-text-no-whitespace",
        "rsaPssSaltLength": "hash-length",
        "argvDigestProtocol": "utf8-nul-joined-no-trailing-nul-v1",
        "cwdDigestProtocol": "normalized-absolute-path-utf8-v1",
        "envDigestProtocol": "ordinal-name-equals-value-utf8-nul-joined-no-trailing-nul-v1",
        "projectTreeDigestProtocol": "all-regular-project-files-canonical-json-v1",
        "readInputDigestProtocol": "sorted-read-input-records-canonical-json-v1",
        "readInputIdentityDigestProtocol": "authority-observed-read-input-identities-canonical-json-v1",
        "assertionInputs": {
            "pathSource": "validate-challenge-plus-six-and-admit-external-input-set-absolute-cli-paths-only",
            "expectedConfigHashSource": "operator-authority-or-user-out-of-band-lower64hex-never-config-project-package",
            "challengeSource": "pinned-bootstrap-cryptographic-rng-before-authority-issuance",
            "challengeInputs": "schema-valid-launch-challenge-with-run-id-nonce-temp-and-digests",
            "prepareExecutionAvailability": "prepare-attestation-and-signature-created-by-authority-after-monitored-prepare-before-prelaunch",
            "prelaunchAvailability": "assertion-and-signature-exist-before-launch-and-remain-byte-identical",
            "postexecutionAvailability": "attestation-and-signature-absent-before-validate-created-by-authority-after-validator-exit",
            "runAuthorizationAvailability": "external-human-chain-and-authorization-created-after-post-pass-under-continuous-lock-before-admit",
            "runAdmissionAvailability": "admission-attestation-and-signature-created-after-run-authorization-before-admit-invocation",
            "admitExecutionAvailability": "receipt-and-signature-paths-predeclared-and-absent-before-admit-created-by-authority-after-semantic-pass-token-consumption-and-suspended-worker-observation",
            "admitPathSet": ["presentation", "challenge", "transcript", "statement",
                             "capture", "capture-provenance", "run-authorization",
                             "run-admission-attestation", "run-admission-signature",
                             "admit-execution-attestation", "admit-execution-signature"],
        },
        "maxPrelaunchAgeSeconds": 60,
        "maxAdmissionLifetimeSeconds": 30,
        "maxWorkerReadyLifetimeSeconds": 30,
        "maxClockSkewSeconds": 5,
    }
    config = {
        "schemaVersion": "1.0.0",
        "d4RuntimePins": [{
            "id": "D4-RUNTIME-PIN-TEST", "pythonExecutable": python_pin,
            "readOnlyLibraryRoots": [library_pin], "gitExecutable": None,
            "gitRuntimeRoots": [],
        }],
        "w0ValidatorRuntime": {
            "id": "W0-RUNTIME-PIN-TEST", "installedSkillRoot": str(skill_root),
            "installedSkillReadClosure": skill_closure,
            "pythonExecutable": python_pin,
            "validatorEntrypoint": {
                "path": str((SCRIPT_DIR / "validate_d5_acceptance.py").resolve()),
                "sha256": sha_path(SCRIPT_DIR / "validate_d5_acceptance.py"),
                "copyPath": "scripts/validate_d5_acceptance.py",
            },
            "supportArtifacts": [{
                "path": str((SCRIPT_DIR / name).resolve()),
                "sha256": sha_path(SCRIPT_DIR / name), "copyPath": f"scripts/{name}",
            } for name in ("gen_index.py", "state_readiness.py", "strict_json.py")],
            "readOnlyLibraryRoots": [library_pin], "gitExecutable": None,
            "gitRuntimeRoots": [],
            "receiverBootstrap": {
                "script": {
                    "path": str((SCRIPT_DIR / "w0_receiver_bootstrap.ps1").resolve()),
                    "sha256": sha_path(SCRIPT_DIR / "w0_receiver_bootstrap.ps1")},
                "hostExecutable": {
                    "path": str(python_path), "bytes": python_path.stat().st_size,
                    "sha256": sha_path(python_path)},
                "hostVersion": python_pin["version"],
                "hostFixedArgs": ["-NoLogo", "-NoProfile", "-NonInteractive",
                                  "-ExecutionPolicy", "Bypass", "-File"],
                "hostRuntimeRoots": [library_pin],
                "trustBoundary": "operator-pinned-powershell-os-host-and-bootstrap-v1",
                "threePhaseProtocol": "prepare-validate-admit-continuous-lock-v1",
                "phaseFlag": "-Phase", "phaseValues": ["PREPARE", "VALIDATE", "ADMIT"],
                "phaseInvocationProtocol": "host-fixed-args-script-phase-first-absolute-named-paths-v1",
                "phaseArgvTailGrammar": {
                    "PREPARE": ["-ConfigPath", "<ABS>", "-ExpectedConfigSha256", "<LOWER64HEX>", "-PackagePath", "<ABS>",
                                "-ProjectRoot", "<ABS>", "-LaunchChallengeOutputPath", "<ABS>",
                                "-AuthorizationEvidenceRoot", "<ABS>"],
                    "VALIDATE": ["-ConfigPath", "<ABS>", "-ExpectedConfigSha256", "<LOWER64HEX>", "-PackagePath", "<ABS>",
                                 "-ProjectRoot", "<ABS>", "-LaunchChallengePath", "<ABS>",
                                 "-PrepareAttestationPath", "<ABS>", "-PrepareSignaturePath", "<ABS>",
                                 "-PrelaunchAssertionPath", "<ABS>", "-PrelaunchSignaturePath", "<ABS>",
                                 "-PostexecutionAttestationPath", "<ABS>",
                                 "-PostexecutionSignaturePath", "<ABS>"],
                    "ADMIT": ["-ConfigPath", "<ABS>", "-ExpectedConfigSha256", "<LOWER64HEX>", "-PackagePath", "<ABS>",
                              "-ProjectRoot", "<ABS>", "-LaunchChallengePath", "<ABS>",
                              "-PresentationPath", "<ABS>", "-HumanChallengePath", "<ABS>",
                              "-TranscriptPath", "<ABS>", "-StatementPath", "<ABS>",
                              "-CapturePath", "<ABS>", "-CaptureProvenancePath", "<ABS>",
                              "-RunAuthorizationPath", "<ABS>",
                              "-RunAdmissionAttestationPath", "<ABS>",
                              "-RunAdmissionSignaturePath", "<ABS>",
                              "-AdmitExecutionAttestationPath", "<ABS>",
                              "-AdmitExecutionSignaturePath", "<ABS>"],
                },
            },
            "immutableRuntimeAuthority": authority_constants,
        },
        "trustedRuntimeAdapters": [{
            "id": "RUNNER-TEST", "authority": "test-authority",
            "adapter": "test-adapter", "adapterVersion": "1.0.0",
            "launchMode": "host-with-adapter-arg",
            "executable": {"path": str(python_path), "sha256": sha_path(python_path)},
            "adapterArtifact": {
                "path": str(adapter.resolve()), "sha256": sha_path(adapter),
                "copyPath": "adapter.py",
            },
            "supportArtifacts": [], "runtimeLibraryRoots": [library_pin],
            "staticArgs": ["-B", "-S", "-E", "-X", "utf8"],
            "inputProtocol": "json-stdin-v1", "allowedEnvNames": [],
            "timeoutSeconds": 20, "maxOutputBytes": 1048576,
        }],
        "signatureVerifiers": [{
            "id": "SIGNATURE-TEST", "authority": "test-authority",
            "algorithm": "rsa-pss-sha256", "keyId": "TEST-KEY-001",
            "trustAnchor": {
                "path": str(trust_anchor.resolve()), "sha256": sha_path(trust_anchor),
                "copyPath": "test-trust-anchor.der"},
            "launchMode": "host-with-adapter-arg",
            "executable": {"path": str(python_path), "sha256": sha_path(python_path)},
            "adapterArtifact": {
                "path": str(signature_adapter.resolve()),
                "sha256": sha_path(signature_adapter), "copyPath": "signature-verifier.py",
            },
            "supportArtifacts": [], "runtimeLibraryRoots": [library_pin],
            "staticArgs": ["-B", "-S", "-E", "-X", "utf8"],
            "inputProtocol": "json-stdin-v1", "allowedEnvNames": [],
            "timeoutSeconds": 20, "maxOutputBytes": 1048576,
        }],
    }
    return json_file(operator / "provenance-config.json", config)


def make_provenance_verification(
        root: Path, subject_type: str, subject: dict, claims: dict, slug: str) -> dict:
    claims_hash = validate_d5.canonical_json_sha256(claims)
    subject_time_value = (
        claims.get("sentAt") if subject_type == "human-approval-capture" else
        claims.get("assembledAt") if subject_type == "d4-capsule-assembly-attestation" else
        claims.get("completedAt") if subject_type in {
            "d4-auditor-attestation", "d1.5-measurement-evidence"} else
        claims.get("actual", {}).get("completedAt")
        if subject_type == "lifecycle-transition-attestation"
        and isinstance(claims.get("actual"), dict) else None)
    if not isinstance(subject_time_value, str):
        raise AssertionError(f"missing authoritative subject time for {subject_type}")
    subject_time = dt.datetime.fromisoformat(subject_time_value)
    queried_at = (subject_time + dt.timedelta(seconds=10)).isoformat()
    verified_at = (subject_time + dt.timedelta(seconds=20)).isoformat()
    payload = write(
        root / "docs" / "evidence" / "provenance" / f"{slug}-payload.json",
        validate_d5.canonical_json_bytes(claims).decode("utf-8"))
    signature = write(
        root / "docs" / "evidence" / "provenance" / f"{slug}-signature.bin",
        f"test signature {slug}\n")
    anchor_copy = write(
        root / "docs" / "evidence" / "provenance" / f"{slug}-anchor.der",
        "test pinned anchor\n")
    source = {
        "schemaVersion": "1.0.0", "id": f"PSE-{slug.upper()}",
        "authority": "test-authority", "algorithm": "rsa-pss-sha256",
        "keyId": "TEST-KEY-001", "verifiedAt": queried_at,
        "claimsSha256": claims_hash,
        "trustAnchorArtifact": {
            "path": anchor_copy.relative_to(root).as_posix(),
            "sha256": sha_path(anchor_copy)},
        "signedPayloadArtifact": {
            "path": payload.relative_to(root).as_posix(), "sha256": sha_path(payload)},
        "signatureArtifact": {
            "path": signature.relative_to(root).as_posix(),
            "sha256": sha_path(signature)},
    }
    source_path = json_file(
        root / "docs" / "evidence" / "provenance" / f"{slug}-source.json", source)
    pv = {
        "schemaVersion": "1.0.0", "id": f"PV-{slug.upper()}",
        "subjectType": subject_type, "subject": subject,
        "verificationMode": "pinned-signature",
        "verifier": {
            "id": "VERIFIER-TEST", "authority": "test-authority",
            "adapter": "signature-verifier", "adapterVersion": "1.0.0",
        },
        "sourceArtifact": {
            "path": source_path.relative_to(root).as_posix(),
            "sha256": sha_path(source_path),
        },
        "verificationContext": {
            "kind": "pinned-signature-v1", "algorithm": "rsa-pss-sha256",
            "keyId": "TEST-KEY-001", "trustAnchorSha256": sha_path(anchor_copy),
        },
        "verifiedAt": verified_at,
        "claims": claims, "claimsSha256": claims_hash, "verdict": "verified",
    }
    path = json_file(
        root / "docs" / "evidence" / "provenance" / f"{slug}-pv.json", pv)
    return {"path": path.relative_to(root).as_posix(), "sha256": sha_path(path)}


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


def d4_record_text(
        record_id: str, track: str, candidate: dict, capsule: dict,
        request: dict, raw_path: str, commands: list[dict], inspected: list[dict],
        policy: dict, runtime: dict, prompt: dict, lane_run_id: str,
        execution_id: str, session_id: str, provider_policy: dict,
        request_core_sha256: str) -> str:
    is_post = str(candidate["id"]).startswith("P0-CAND-")
    inspected_text = "; ".join(
        f"{item['path']} / {item['sha256']}" for item in inspected)
    initial_inventory = "not-applicable" if is_post else "PROGRESS.md / verified inventory"
    post_inventory = "B0 historical PROGRESS.md / verified inventory" if is_post else "not-applicable"
    post_state = "P0-CAND PROGRESS.md / proposed rows 0" if is_post else "not-applicable"
    remaining = "none" if is_post else "DVT-OPEN-001"
    closure = "DVT-OPEN-001 evidence and hashes verified" if is_post else "not-applicable"
    command_rows = "\n".join(
        "| " + json.dumps(command["argv"], ensure_ascii=False,
                           separators=(",", ":")).replace("\\", "\\\\") +
        f" | {command['cwd'].replace(chr(92), chr(92) * 2)} | "
        f"{command['exitCode']} | "
        f"{command['outputPath']} | {command['outputSha256']} |"
        for command in commands)
    return (
        "# D4 Findings Record\n\n"
        "| Field | Value |\n|---|---|\n"
        f"| Record ID | {record_id} |\n"
        f"| Audit track | {track} |\n"
        f"| Candidate baseline ID | {candidate['id']} |\n"
        f"| Candidate manifest | {candidate['path']} |\n"
        f"| Candidate manifest SHA-256 | {candidate['sha256']} |\n"
        f"| Candidate fileSetSha256 | {candidate['fileSetSha256']} |\n"
        f"| Audit capsule path | {capsule['path']} |\n"
        f"| Audit capsule SHA-256 | {capsule['sha256']} |\n"
        f"| Installed-policy manifest path / SHA-256 / compiledPolicySha256 | "
        f"{policy['path']} / {policy['sha256']} / {policy['compiledPolicySha256']} |\n"
        f"| Runtime allowlist path / SHA-256 / digestSha256 | "
        f"{runtime['path']} / {runtime['sha256']} / {runtime['digestSha256']} |\n"
        f"| Audit request ID | {request['id']} |\n"
        f"| Audit request artifact path | {request['path']} |\n"
        f"| Audit request artifact SHA-256 | {request['sha256']} |\n"
        f"| Canonical requestCore SHA-256 | {request_core_sha256} |\n"
        f"| Exact orchestrator-submitted payload path / SHA-256 | "
        f"{prompt['path']} / {prompt['sha256']} |\n"
        f"| Lane run ID | {lane_run_id} |\n"
        f"| Storage path | {raw_path} |\n"
        "| Position | Unedited worker response |\n"
        "| Verdict | pass |\n\n"
        "## Summary\n\n- Critical: 0\n- Major: 0\n- Minor: 0\n"
        "- Observation: 0\n- Verdict rule: Critical 0 and Major 0 only -> pass\n\n"
        "## Findings\n\nNo findings.\n\n"
        "## Coverage\n\n"
        f"- Canonical allowlist received: {candidate['path']}\n"
        f"- Sanitized evidence manifest received: {capsule['path']} / {capsule['sha256']}\n"
        "- GDD Gate 1 chain checked: exact record/capture/provenance chain verified\n"
        f"- Initial-D4 inventory source: {initial_inventory}\n"
        f"- post-P0 inventory source: {post_inventory}\n"
        f"- post-P0 candidate state: {post_state}\n"
        f"- Remaining proposal/open/assumption IDs found: {remaining}\n"
        "- Inventory coverage verdict: complete\n"
        f"- post-P0 closure evidence checked: {closure}\n"
        f"- Files inspected: {', '.join(item['path'] for item in inspected)}\n"
        "- Required files not received: none\n\n"
        "## Commands run and outputs\n\n"
        "| Argv (exact minified JSON array; shell=false) | CWD | Exit code | Output path | Output SHA-256 |\n"
        "|---|---|---:|---|---|\n"
        f"{command_rows}\n\n"
        "## Execution facts in this worker response\n\n"
        f"- lane run / execution / session IDs: {lane_run_id} / {execution_id} / {session_id}\n"
        f"- worker / class: auditor-{track} / A\n"
        "- requested and resolved model/version: audit-model / audit-model-resolved\n"
        "- tool version: audit-tool-1.0\n"
        "- context mode: clean\n"
        f"- filesystem access: {validate_d5.D4_FILESYSTEM_ACCESS}\n"
        f"- provider policy ID / SHA-256: {provider_policy['id']} / {provider_policy['sha256']}\n"
        f"- capsule path / SHA-256: {capsule['path']} / {capsule['sha256']}\n"
        f"- installed-policy manifest path / SHA-256 / compiledPolicySha256: "
        f"{policy['path']} / {policy['sha256']} / {policy['compiledPolicySha256']}\n"
        f"- runtime allowlist path / SHA-256 / digestSha256: "
        f"{runtime['path']} / {runtime['sha256']} / {runtime['digestSha256']}\n"
        f"- inspected input paths / SHA-256: {inspected_text}\n"
        f"- request artifact path / SHA-256 / requestCore SHA-256: "
        f"{request['path']} / {request['sha256']} / {request_core_sha256}\n"
        f"- exact orchestrator-submitted payload path / SHA-256: "
        f"{prompt['path']} / {prompt['sha256']}\n"
        f"- raw response output path: {raw_path}\n"
        "- read-only sandbox / network: read-only / disabled\n"
        "- finish reason / exit code: stop / 0\n"
        "- started at / completed at: 2026-08-20T10:00:00+09:00 / "
        "2026-08-20T10:05:00+09:00\n"
    )


def make_baseline(
        root: Path, baseline_id: str, stage: str, contents: dict[str, bytes],
        parent: str | None, promoted: str | None, approval: str | None,
        audits: list[dict], status: str, gate1_ref: dict,
        created_at: str = "2026-08-20T12:00:00+09:00",
        p0_transition: dict | None = None) -> tuple[dict, dict, Path]:
    snapshot_rel = f"docs/evidence/baselines/{baseline_id}/snapshot"
    evidence_rel = f"docs/evidence/baselines/{baseline_id}/git-status.txt"
    snapshot_files(root, snapshot_rel, contents)
    write(root / evidence_rel, "snapshot evidence: clean\n")
    files = file_records(contents, status)
    required_specs_path = root / "docs" / "DVT_required_specs.json"
    if not required_specs_path.is_file():
        json_file(required_specs_path, {
            "schemaVersion": "1.0.0", "project": "D5 Test", "prefix": "DVT",
            "required_specs": [],
        })
    admission = {
        "status": "complete",
        "d15TriggerRegistry": {
            "path": required_specs_path.relative_to(root).as_posix(),
            "sha256": sha_path(required_specs_path),
            "applicableMeasurementCount": 0,
        },
        "deficiencies": [],
    }
    manifest = {
        "schemaVersion": "1.0.0", "baselineId": baseline_id, "stage": stage,
        "project": "D5 Test", "prefix": "DVT",
        "createdAt": created_at,
        "revision": {
            "kind": "snapshot", "value": f"SNAP-{baseline_id}",
            "snapshotRoot": snapshot_rel, "gitStatusEvidence": evidence_rel,
        },
        "admission": admission, "gddGate1": gate1_ref, "d15Measurements": [],
        "p0Transition": p0_transition,
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


def make_audits(
        root: Path, label: str, candidate: dict, provenance_config: Path,
        source_baseline: dict | None = None,
        p0_transition: dict | None = None) -> list[dict]:
    """Build a fully bound, snapshot-backed three-lane D4 evidence capsule."""
    validate_d5.INSTALLED_SKILL_ROOT = SCRIPT_DIR.parent.resolve()
    skill_root = SCRIPT_DIR.parent.resolve()
    candidate_path = root / candidate["path"]
    candidate_manifest = json.loads(candidate_path.read_text(encoding="utf-8"))
    candidate_with_revision = {**candidate, "revision": candidate_manifest["revision"]}
    snapshot_root = root / candidate_manifest["revision"]["snapshotRoot"]
    sanitized_rel = f"docs/evidence/audits/{label.lower()}-capsule/sanitized"
    sanitized_root = root / sanitized_rel
    sanitized_root.mkdir(parents=True, exist_ok=True)

    inputs: list[dict] = []
    for item in candidate_manifest["files"]:
        source = snapshot_root / item["path"]
        capsule_rel = f"{sanitized_rel}/candidate/{item['path']}"
        target = root / capsule_rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(source.read_bytes())
        inputs.append({
            "sourcePath": item["path"], "capsulePath": capsule_rel,
            "bytes": target.stat().st_size, "sha256": sha_path(target),
            "role": "canonical",
        })

    source_ref = None
    if source_baseline is not None:
        source_manifest = json.loads((root / source_baseline["path"]).read_text(encoding="utf-8"))
        source_snapshot = root / source_manifest["revision"]["snapshotRoot"]
        source_ref = source_baseline
        for item in source_manifest["files"]:
            source = source_snapshot / item["path"]
            capsule_rel = f"{sanitized_rel}/baseline/{item['path']}"
            target = root / capsule_rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
            inputs.append({
                "sourcePath": item["path"], "capsulePath": capsule_rel,
                "bytes": target.stat().st_size, "sha256": sha_path(target),
                "role": "baseline-canonical",
            })

    dependency_path = json_file(
        sanitized_root / "evidence" / "dependency-closure.json",
        {"schemaVersion": "1.0.0", "candidateId": candidate["id"],
         "runtimeSources": sorted(validate_d5.D4_RUNTIME_FILES)})
    dependency_ref = {
        "path": dependency_path.relative_to(root).as_posix(),
        "sha256": sha_path(dependency_path),
    }
    inputs.append({
        "sourcePath": "d4/dependency-closure.json",
        "capsulePath": dependency_ref["path"], "bytes": dependency_path.stat().st_size,
        "sha256": dependency_ref["sha256"], "role": "dependency",
    })
    machine_diff_ref = None
    if source_baseline is not None:
        machine_diff_path = json_file(
            sanitized_root / "evidence" / "machine-diff.json",
            {"schemaVersion": "1.0.0", "from": source_baseline["id"],
             "to": candidate["id"], "candidateFileSetSha256": candidate["fileSetSha256"]})
        machine_diff_ref = {
            "path": machine_diff_path.relative_to(root).as_posix(),
            "sha256": sha_path(machine_diff_path),
        }
        inputs.append({
            "sourcePath": "d4/machine-diff.json", "capsulePath": machine_diff_ref["path"],
            "bytes": machine_diff_path.stat().st_size,
            "sha256": machine_diff_ref["sha256"], "role": "machine-diff",
        })
    inputs.sort(key=lambda item: (item["role"], item["sourcePath"], item["capsulePath"]))
    input_set_sha = validate_d5.canonical_json_sha256(inputs)

    config = json.loads(provenance_config.read_text(encoding="utf-8"))
    runtime_pin = config["d4RuntimePins"][0]
    runtime_rel = f"docs/evidence/audits/{label.lower()}-runtime.json"
    runtime_root = sanitized_root / "_policy_runtime"
    runtime_files = []
    for source_rel, role in validate_d5.D4_RUNTIME_FILES.items():
        source = skill_root / source_rel
        capsule_path = runtime_root / source_rel
        capsule_path.parent.mkdir(parents=True, exist_ok=True)
        capsule_path.write_bytes(source.read_bytes())
        runtime_files.append({
            "sourcePath": source_rel,
            "capsulePath": capsule_path.relative_to(root).as_posix(),
            "bytes": source.stat().st_size, "sha256": sha_path(source), "role": role,
        })
    runtime_files.sort(key=lambda item: item["capsulePath"])
    runtime_data = {
        "schemaVersion": "1.0.0", "id": f"D4-RUNTIME-DVT-{label}",
        "createdAt": "2026-08-20T09:50:00+09:00",
        "operatorRuntimePinId": runtime_pin["id"],
        "pythonExecutable": runtime_pin["pythonExecutable"],
        "gitExecutable": runtime_pin["gitExecutable"],
        "readOnlyLibraryRoots": runtime_pin["readOnlyLibraryRoots"],
        "policyRuntimeRoot": runtime_root.relative_to(root).as_posix(),
        "policyRuntimeFiles": runtime_files,
    }
    runtime_digest_payload = {
        "operatorRuntimePinId": runtime_data["operatorRuntimePinId"],
        "pythonExecutable": runtime_data["pythonExecutable"],
        "gitExecutable": runtime_data["gitExecutable"],
        "readOnlyLibraryRoots": sorted(
            runtime_data["readOnlyLibraryRoots"], key=lambda item: item["path"]),
        "policyRuntimeRoot": runtime_data["policyRuntimeRoot"],
        "policyRuntimeFiles": runtime_files,
    }
    runtime_data["digestSha256"] = validate_d5.canonical_json_sha256(
        runtime_digest_payload)
    runtime_path = json_file(root / runtime_rel, runtime_data)
    runtime_ref = {
        "path": runtime_rel, "sha256": sha_path(runtime_path),
        "digestSha256": runtime_data["digestSha256"],
    }

    policy_components = [{
        "role": role, "auditTrack": track, "path": rel,
        "sha256": sha_path(skill_root / rel),
    } for role, track, rel in validate_d5.D4_POLICY_COMPONENTS]
    policy_components.sort(key=lambda item: item["path"])
    policy_errors: list[str] = []
    python_path = runtime_data["pythonExecutable"]["path"]
    git_pin = runtime_data["gitExecutable"]
    git_path = git_pin["path"] if isinstance(git_pin, dict) else None
    preflight_commands = validate_d5._d4_preflight_commands(
        root, candidate, candidate_manifest, python_path, runtime_root,
        sanitized_root, git_path, policy_errors, "fixture preflight")
    lane_policies = []
    planned_capsule_path = (
        root / "docs" / "evidence" / "audits" / f"{label.lower()}-capsule.json")
    for track in ("consistency", "roblox-readiness", "clean-room"):
        commands = validate_d5._d4_runtime_commands(
            track, python_path, runtime_root, sanitized_root, "DVT", policy_errors,
            git_path, planned_capsule_path.resolve(), provenance_config.resolve())
        checklist = validate_d5.D4_CHECKLIST_PATHS[track]
        lane_policies.append({
            "auditTrack": track,
            "checklist": {"path": checklist, "sha256": sha_path(skill_root / checklist)},
            "requiredCheckIds": [item["checkId"] for item in commands],
            "requiredCommands": commands,
        })
    if policy_errors:
        raise AssertionError(policy_errors)
    policy_data = {
        "schemaVersion": "1.0.0", "id": f"D4-POLICY-DVT-{label}",
        "policyVersion": "d4-audit-policy-v1",
        "createdAt": "2026-08-20T09:51:00+09:00",
        "installedSkillRoot": str(skill_root),
        "sourceComponents": policy_components,
        "promptCompilation": validate_d5.D4_PROMPT_COMPILATION,
        "sourceTreePolicy": validate_d5.D4_SOURCE_TREE_POLICY,
        "preflightCommands": preflight_commands,
        "lanePolicies": lane_policies,
        "denyCategories": validate_d5.D4_DENY_CATEGORIES,
    }
    policy_payload = {
        "policyVersion": policy_data["policyVersion"],
        "sourceComponents": policy_components,
        "promptCompilation": policy_data["promptCompilation"],
        "sourceTreePolicy": policy_data["sourceTreePolicy"],
        "preflightCommands": sorted(preflight_commands, key=lambda item: item["checkId"]),
        "lanePolicies": sorted(lane_policies, key=lambda item: item["auditTrack"]),
        "denyCategories": policy_data["denyCategories"],
    }
    policy_data["compiledPolicySha256"] = validate_d5.canonical_json_sha256(policy_payload)
    policy_rel = f"docs/evidence/audits/{label.lower()}-policy.json"
    policy_path = json_file(root / policy_rel, policy_data)
    policy_ref = {
        "id": policy_data["id"], "path": policy_rel, "sha256": sha_path(policy_path),
        "compiledPolicySha256": policy_data["compiledPolicySha256"],
    }

    preflight = []
    for command in preflight_commands:
        result = subprocess.run(
            command["argv"], cwd=command["cwd"], shell=False,
            stdin=subprocess.DEVNULL, capture_output=True)
        if result.returncode != 0:
            raise AssertionError(result.stderr.decode("utf-8", errors="replace"))
        output = root / "docs" / "evidence" / "audits" / (
            f"{label.lower()}-{command['checkId'].lower()}.json")
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(result.stdout)
        preflight.append({
            **command, "actualExitCode": result.returncode,
            "outputPath": output.relative_to(root).as_posix(),
            "outputSha256": sha_path(output),
        })
    preflight.sort(key=lambda item: item["checkId"])
    tree_row = next(item for item in preflight
                    if item["checkId"] == "D4-PREFLIGHT-TREE-001")
    source_state_row = next(item for item in preflight
                            if item["checkId"] == "D4-PREFLIGHT-SOURCE-STATE-001")
    tree_entries = json.loads((root / tree_row["outputPath"]).read_text(encoding="utf-8"))
    source_tree = {
        "entryCount": len(tree_entries),
        "entriesSha256": validate_d5.canonical_json_sha256(tree_entries),
        "outputPath": tree_row["outputPath"], "outputSha256": tree_row["outputSha256"],
    }
    assembly = {
        "schemaVersion": "1.0.0",
        "id": f"D4-CAPSULE-ASSEMBLY-DVT-{label}",
        "candidate": candidate_with_revision, "auditPolicy": policy_ref,
        "runtimeAllowlist": runtime_ref,
        "sourceTreePolicySha256": validate_d5.canonical_json_sha256(
            validate_d5.D4_SOURCE_TREE_POLICY),
        "resolvedSource": {
            "kind": "immutable-snapshot", "path": str(snapshot_root.resolve()),
            "revisionValue": candidate_manifest["revision"]["value"],
            "treeEntriesSha256": validate_d5.canonical_json_sha256(tree_entries),
        },
        "sourceStateEvidence": {
            "path": source_state_row["outputPath"],
            "sha256": source_state_row["outputSha256"],
        },
        "sourceTree": source_tree, "inputSetSha256": input_set_sha,
        "inputCount": len(inputs), "dependencyClosure": dependency_ref,
        "preflight": preflight, "assembledAt": "2026-08-20T09:54:00+09:00",
    }
    assembly_rel = f"docs/evidence/audits/{label.lower()}-assembly.json"
    assembly_path = json_file(root / assembly_rel, assembly)
    assembly_ref = {
        "id": assembly["id"], "path": assembly_rel, "sha256": sha_path(assembly_path),
    }
    assembly_claims = {
        "kind": "d4-capsule-assembly-v1", "attestationId": assembly["id"],
        **{key: assembly[key] for key in (
            "candidate", "auditPolicy", "runtimeAllowlist", "sourceTreePolicySha256",
            "resolvedSource", "sourceStateEvidence", "sourceTree", "inputSetSha256",
            "inputCount", "dependencyClosure", "preflight", "assembledAt")},
    }
    assembly_pv = make_provenance_verification(
        root, "d4-capsule-assembly-attestation", assembly_ref,
        assembly_claims, f"d4-assembly-{label.lower()}")

    scope = {
        "kind": "initial-d4-v1" if source_baseline is None else "post-p0-d4-v1",
        "mode": "full" if source_baseline is None else "delta",
        "sourceBaseline": source_ref, "machineDiff": machine_diff_ref,
        "dependencyClosure": dependency_ref,
    }
    applicability = {"all", "initial" if source_baseline is None else "post-p0"}
    required_commands = [{
        "auditTrack": lane["auditTrack"], "checkId": command["checkId"],
        "argv": command["argv"], "cwd": command["cwd"],
        "expectedExitCode": command["expectedExitCode"],
    } for lane in lane_policies for command in lane["requiredCommands"]
        if command["applicability"] in applicability]
    capsule_data = {
        "schemaVersion": "1.0.0", "id": f"D4-CAPSULE-DVT-{label}",
        "candidate": candidate_with_revision, "auditScope": scope,
        "auditPolicy": policy_ref, "runtimeAllowlist": runtime_ref,
        "assemblyAttestation": assembly_ref,
        "capsuleAssemblyProvenance": assembly_pv,
        "p0LifecycleTransition": p0_transition,
        "createdAt": "2026-08-20T09:55:00+09:00",
        "sanitizedRoot": sanitized_rel, "inputs": inputs,
        "inputSetSha256": input_set_sha, "preflight": preflight,
        "requiredAuditCommands": required_commands,
        "denyCategories": validate_d5.D4_DENY_CATEGORIES,
    }
    capsule_path = json_file(
        root / "docs" / "evidence" / "audits" / f"{label.lower()}-capsule.json",
        capsule_data)
    capsule_ref = {
        "path": capsule_path.relative_to(root).as_posix(), "sha256": sha_path(capsule_path),
    }
    inspected = sorted(({
        "path": item["capsulePath"], "sha256": item["sha256"]} for item in inputs),
        key=validate_d5.identity_key)
    records = []
    provider_policy = {"id": "TEST-PROVIDER-POLICY", "sha256": "f" * 64}
    for track in ("consistency", "roblox-readiness", "clean-room"):
        track_token = track.upper()
        record_id = f"D4-{label}-{track_token}"
        lane_run_id = f"D4-RUN-DVT-{label}-{track_token}"
        selected = [item for item in required_commands if item["auditTrack"] == track]
        request_core = {
            "laneRunId": lane_run_id, "auditTrack": track, "mode": scope["mode"],
            "candidate": candidate, "capsule": capsule_ref, "auditPolicy": policy_ref,
            "runtimeAllowlist": runtime_ref, "purpose": "findings-only",
            "writePolicy": "read-only", "contextMode": "clean",
            "denyCategories": validate_d5.D4_DENY_CATEGORIES,
            "requiredCheckIds": [item["checkId"] for item in selected],
        }
        prompt_bytes = validate_d5.compile_d4_prompt(
            request_core, track, [], "fixture prompt")
        assert prompt_bytes is not None
        prompt_path = root / "docs" / "evidence" / "audits" / f"{record_id}-prompt.txt"
        prompt_path.write_bytes(prompt_bytes)
        prompt_ref = {
            "path": prompt_path.relative_to(root).as_posix(), "sha256": sha_path(prompt_path),
        }
        request_data = {
            "schemaVersion": "1.0.0", "id": f"D4-REQUEST-DVT-{label}-{track_token}",
            "requestCore": request_core,
            "requestCoreSha256": validate_d5.canonical_json_sha256(request_core),
            "fullPromptArtifact": prompt_ref,
        }
        request_path = json_file(
            root / "docs" / "evidence" / "audits" / f"{record_id}-request.json",
            request_data)
        request_ref = {
            "path": request_path.relative_to(root).as_posix(), "sha256": sha_path(request_path),
        }
        executed = []
        for command in selected:
            command_output = write(
                root / "docs" / "evidence" / "audits" /
                f"{record_id}-{command['checkId'].lower()}.txt",
                f"{command['checkId']}: pass\n")
            executed.append({
                "checkId": command["checkId"], "argv": command["argv"],
                "cwd": command["cwd"], "exitCode": command["expectedExitCode"],
                "outputPath": command_output.relative_to(root).as_posix(),
                "outputSha256": sha_path(command_output),
            })
        execution_id = f"EXEC-{label}-{track_token}"
        session_id = f"SESSION-{label}-{track_token}"
        raw_rel = f"docs/evidence/audits/{record_id}.md"
        request_view = {"id": request_data["id"], **request_ref}
        path = write(
            root / raw_rel,
            d4_record_text(
                record_id, track, candidate, capsule_ref, request_view, raw_rel,
                executed, inspected, policy_ref, runtime_ref, prompt_ref, lane_run_id,
                execution_id, session_id, provider_policy,
                request_data["requestCoreSha256"]))
        raw_ref = {"path": raw_rel, "sha256": sha_path(path)}
        attestation = {
            "schemaVersion": "1.0.0", "id": f"D4-ATTEST-DVT-{label}-{track_token}",
            "laneRunId": lane_run_id, "executionId": execution_id,
            "sessionId": session_id, "auditTrack": track, "auditorClass": "A",
            "worker": f"auditor-{track}", "requestedModel": "audit-model",
            "resolvedModel": "audit-model-resolved", "toolVersion": "audit-tool-1.0",
            "contextMode": "clean", "filesystemAccess": validate_d5.D4_FILESYSTEM_ACCESS,
            "capsule": capsule_ref, "auditPolicy": policy_ref,
            "runtimeAllowlist": runtime_ref, "fullPromptArtifact": prompt_ref,
            "requestCoreSha256": request_data["requestCoreSha256"],
            "inspectedInputs": inspected, "commands": executed,
            "requestArtifact": request_ref, "responseArtifact": raw_ref,
            "finishReason": "stop", "startedAt": "2026-08-20T10:00:00+09:00",
            "completedAt": "2026-08-20T10:05:00+09:00",
        }
        attestation_path = json_file(
            root / "docs" / "evidence" / "audits" / f"{record_id}-attestation.json",
            attestation)
        attestation_ref = {
            "path": attestation_path.relative_to(root).as_posix(),
            "sha256": sha_path(attestation_path),
        }
        claims = {
            "kind": "d4-runtime-v1", "attestationId": attestation["id"],
            "laneRunId": lane_run_id, "executionId": execution_id,
            "sessionId": session_id, "auditTrack": track, "auditorClass": "A",
            "worker": attestation["worker"], "requestedModel": "audit-model",
            "resolvedModel": "audit-model-resolved", "toolVersion": "audit-tool-1.0",
            "contextMode": "clean", "filesystemAccess": validate_d5.D4_FILESYSTEM_ACCESS,
            "providerPolicy": provider_policy, "capsule": capsule_ref,
            "auditPolicy": policy_ref, "runtimeAllowlist": runtime_ref,
            "fullPromptSha256": prompt_ref["sha256"], "inspectedInputs": inspected,
            "inspectedInputsSha256": validate_d5.canonical_json_sha256(inspected),
            "requestId": request_data["id"],
            "requestCoreSha256": request_data["requestCoreSha256"],
            "requestSha256": request_ref["sha256"],
            "requiredCheckIds": request_core["requiredCheckIds"],
            "commands": [{
                "checkId": command["checkId"], "argv": command["argv"],
                "cwd": command["cwd"], "expectedExitCode": command["exitCode"],
                "actualExitCode": command["exitCode"],
                "outputPath": command["outputPath"],
                "outputSha256": command["outputSha256"],
            } for command in executed],
            "responseSha256": raw_ref["sha256"], "finishReason": "stop",
            "startedAt": attestation["startedAt"], "completedAt": attestation["completedAt"],
        }
        pv_ref = make_provenance_verification(
            root, "d4-auditor-attestation",
            {"id": attestation["id"], **attestation_ref}, claims,
            f"d4-{label.lower()}-{track}")
        records.append({
            "id": record_id, "auditTrack": track,
            "path": path.relative_to(root).as_posix(), "sha256": sha_path(path),
            "auditCapsule": capsule_ref, "auditRequest": request_ref,
            "auditorAttestation": attestation_ref,
            "provenanceVerification": pv_ref, "candidateBaseline": candidate,
            "criticalCount": 0, "majorCount": 0, "verdict": "pass",
        })
    return records


def human_capture(
        root: Path, record_id: str, record_type: str, target_key: str,
        target: dict, scope: dict, approved_at: str) -> tuple[dict, dict, dict]:
    slug = record_id.lower()
    issued = (dt.datetime.fromisoformat(approved_at) - dt.timedelta(minutes=5)).isoformat()
    challenge_id = f"HCH-{record_id}"
    digest = validate_d5.canonical_challenge_digest(
        record_type, target_key, target, scope)
    response = f"APPROVE {challenge_id} {digest}"
    target_kind = {
        "targetArtifact": "artifact", "targetBaseline": "baseline",
        "plannedCandidate": "planned-candidate",
    }[target_key]
    presentation = {
        "schemaVersion": "1.0.0", "challengeId": challenge_id,
        "gateType": record_type, "issuedAt": issued,
        "target": {"kind": target_kind, **target}, "scope": scope,
        "targetScopeSha256": digest, "canonicalResponse": response,
    }
    presentation_path = root / "docs" / "evidence" / "approvals" / "presentations" / f"{slug}.json"
    presentation_path.parent.mkdir(parents=True, exist_ok=True)
    presentation_path.write_bytes(validate_d5.canonical_json_bytes(presentation))
    challenge = {
        "schemaVersion": "1.0.0", "id": challenge_id, "gateType": record_type,
        "issuedAt": issued, "targetScopeSha256": digest,
        "canonicalResponse": response,
        "presentationArtifact": {
            "path": presentation_path.relative_to(root).as_posix(),
            "sha256": sha_path(presentation_path),
        },
    }
    challenge_path = json_file(
        root / "docs" / "evidence" / "approvals" / "challenges" / f"{slug}.json",
        challenge)
    statement = write(
        root / "docs" / "evidence" / "approvals" / "statements" / f"{slug}.txt",
        response)
    transcript = {
        "schemaVersion": "1.0.0", "id": f"HIT-{record_id}",
        "channel": "trusted-codex-dialogue", "interactionId": f"INT-{record_id}",
        "capturedAt": approved_at,
        "messages": [{
            "messageId": f"MSG-PRESENT-{record_id}", "role": "assistant",
            "actorId": "approval-system", "occurredAt": issued,
            "content": presentation_path.read_text(encoding="utf-8"),
        }, {
            "messageId": f"MSG-{record_id}", "role": "human",
            "actorId": "Project Owner", "occurredAt": approved_at,
            "content": response,
        }],
    }
    transcript_path = json_file(
        root / "docs" / "evidence" / "approvals" / "transcripts" / f"{slug}.json",
        transcript)
    capture = {
        "schemaVersion": "1.0.0", "id": f"HAC-{record_id}",
        "gateType": record_type, "approvalMethod": "human-direct", "approved": True,
        "approver": "Project Owner", "occurredAt": approved_at,
        "sourceInteractionRef": {
            "channel": transcript["channel"], "interactionId": transcript["interactionId"],
            "presentationMessageId": transcript["messages"][0]["messageId"],
            "messageId": transcript["messages"][1]["messageId"],
            "transcriptArtifact": {
                "path": transcript_path.relative_to(root).as_posix(),
                "sha256": sha_path(transcript_path),
            },
        },
        target_key: target, "scope": scope,
        "challengeArtifact": {
            "path": challenge_path.relative_to(root).as_posix(),
            "sha256": sha_path(challenge_path),
        },
        "statementArtifact": {
            "path": statement.relative_to(root).as_posix(), "sha256": sha_path(statement),
        },
        "statementSha256": sha_path(statement),
    }
    path = json_file(
        root / "docs" / "evidence" / "approvals" / "captures" / f"{slug}.json",
        capture)
    capture_ref = {"id": capture["id"], "path": path.relative_to(root).as_posix(),
                   "sha256": sha_path(path)}
    claims = {
        "kind": "human-approval-v1", "captureId": capture["id"],
        "gateType": record_type, "approver": capture["approver"],
        "challengeId": challenge_id, "challengeIssuedAt": issued,
        "targetScopeSha256": digest, "channel": transcript["channel"],
        "interactionId": transcript["interactionId"],
        "presentationMessageId": transcript["messages"][0]["messageId"],
        "presentationRole": "assistant", "presentationSentAt": issued,
        "presentationContentSha256": sha_path(presentation_path),
        "messageId": transcript["messages"][1]["messageId"],
        "messageRole": "human", "actorId": "Project Owner",
        "sentAt": approved_at,
        "messageContentSha256": hashlib.sha256(response.encode()).hexdigest(),
        "statementSha256": sha_path(statement),
    }
    pv_ref = make_provenance_verification(
        root, "human-approval-capture", capture_ref, claims, f"hac-{slug}")
    return capture_ref, capture, pv_ref


def approval_record(
        root: Path, record_id: str, record_type: str, target_field: str,
        target: dict, first_wp: str | None, approved_at: str,
        scope: dict, capture_ref: dict, verification_ref: dict) -> dict:
    record = {
        "schemaVersion": "1.0.0", "id": record_id, "type": record_type,
        "approvalKind": "human-direct", "approver": "Project Owner",
        "approvedAt": approved_at, "scope": scope,
        target_field: target,
        "firstAuthorizedWpId": first_wp,
        "sourceEvidence": {"path": capture_ref["path"], "sha256": capture_ref["sha256"]},
        "sourceVerification": verification_ref,
    }
    path = json_file(
        root / "docs" / "evidence" / "approvals" / f"{record_id}.json", record)
    return {"id": record_id, "recordPath": path.relative_to(root).as_posix(),
            "recordSha256": sha_path(path)}


def p0_preapproval_digest(
        contents: dict[str, bytes], management_wp: dict, approval_id: str,
        candidate_id: str, capture_path: str) -> str:
    normalized: dict[str, bytes] = {}
    findings: list[str] = []
    for rel, payload in contents.items():
        try:
            text = payload.decode("utf-8").replace("\r\n", "\n").replace("\r", "\n")
        except UnicodeDecodeError:
            normalized[rel] = payload
            continue
        if rel == management_wp["path"]:
            text = validate_d5.normalize_p0_candidate_wp(
                text, management_wp, approval_id, candidate_id, capture_path, findings)
        normalized[rel] = text.encode("utf-8")
    if findings:
        raise AssertionError(findings)
    entries = [{
        "path": rel, "bytes": len(normalized[rel]),
        "sha256": hashlib.sha256(normalized[rel]).hexdigest(),
    } for rel in sorted(normalized)]
    encoded = json.dumps(entries, ensure_ascii=False, sort_keys=True,
                         separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def transition_state(payload: bytes | None) -> dict:
    if payload is None:
        return {"exists": False, "bytes": None, "sha256": None}
    return {
        "exists": True, "bytes": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
    }


def transition_event(
        sequence: int, event_id: str, root_role: str | None, path: str | None,
        before: bytes | None, after: bytes | None, occurred_at: str,
        phase: str, classification: str, rule_id: str,
        source_inventory_id: str | None = None,
        copy_source: dict | None = None, *, monitor_seal: bool = False) -> dict:
    operation = ("monitor-seal" if monitor_seal else
                 "create" if before is None else "delete" if after is None else
                 "append" if after.startswith(before) else "replace")
    return {
        "sequence": sequence, "eventId": event_id, "operation": operation,
        "rootRole": root_role, "path": path,
        "before": None if monitor_seal else transition_state(before),
        "after": None if monitor_seal else transition_state(after),
        "occurredAt": occurred_at, "phase": phase,
        "classification": classification, "ruleId": rule_id,
        "sourceInventoryId": source_inventory_id,
        "copySource": copy_source,
    }


def make_lifecycle_transition(
        root: Path, transition_type: str, slug: str,
        source_ref: dict, source_manifest: dict, result_ref: dict,
        result_manifest: dict, entries: list[dict], approvals: dict,
        staging_root: Path, started_at: str, observed_at: str,
        completed_at: str, claim_extras: dict) -> tuple[dict, dict]:
    """Create a closed LTA/log/PV proof around an explicit event sequence."""
    prefix = transition_type.upper()
    entries = [dict(item, sequence=index + 1) for index, item in enumerate(entries)]
    result_only_artifacts = {
        item["path"] for item in entries
        if item.get("rootRole") == "result-artifacts"
        and item.get("phase") in {"d5-allowed-diff", "d5-post-sync-manifest"}
        and isinstance(item.get("path"), str)
    }
    canonical_paths = sorted(
        ({item["path"] for item in source_manifest["files"]}
         | {item["path"] for item in result_manifest["files"]})
        - result_only_artifacts)
    private_paths = sorted(
        {item["path"] for item in entries
         if item.get("rootRole") == "private-staging"
         and isinstance(item.get("path"), str)} |
        {item["copySource"]["path"] for item in entries
         if isinstance(item.get("copySource"), dict)
         and item["copySource"].get("rootRole") == "private-staging"
         and isinstance(item["copySource"].get("path"), str)})
    result_paths = sorted({item["path"] for item in entries
                           if item.get("rootRole") == "result-artifacts"
                           and isinstance(item.get("path"), str)})
    include_targets = sorted(
        ([{"rootRole": "canonical-project", "path": path}
          for path in canonical_paths]
         + [{"rootRole": "private-staging", "path": path}
            for path in private_paths]
         + [{"rootRole": "result-artifacts", "path": path}
            for path in result_paths]),
        key=lambda item: (item["rootRole"], item["path"]))
    include_rel = f"docs/evidence/transitions/{slug}-include-set.json"
    include_path = write(
        root / include_rel,
        validate_d5.canonical_json_bytes({"targets": include_targets}).decode("utf-8"))
    include_ref = {"path": include_rel, "sha256": sha_path(include_path)}
    source_rows = {item["path"]: item for item in source_manifest["files"]}
    first_by_target: dict[tuple[str, str], dict] = {}
    for item in entries:
        first_by_target.setdefault((item["rootRole"], item["path"]), item)
    target_start_states = []
    for role in ("canonical-project", "private-staging", "result-artifacts"):
        states = []
        for target in (item for item in include_targets if item["rootRole"] == role):
            path = target["path"]
            first = first_by_target.get((role, path))
            if first is not None:
                state = first["before"]
            elif role == "canonical-project" and path in source_rows:
                row = source_rows[path]
                state = {"exists": True, "bytes": row["bytes"], "sha256": row["sha256"]}
            else:
                state = transition_state(None)
            states.append({"path": path, **state})
        target_start_states.append({
            "role": role,
            "stateSetSha256": validate_d5.canonical_json_sha256(states),
        })
    target_start_states.sort(key=lambda item: item["role"])
    event_hash = validate_d5.lifecycle_event_sequence_sha256(entries)
    log = {
        "schemaVersion": "1.0.0", "id": f"LTWL-{prefix}-{slug.upper()}",
        "transitionType": transition_type, "startedAt": started_at,
        "completedAt": completed_at, "entries": entries,
        "entrySetSha256": validate_d5.canonical_json_sha256(entries),
        "eventSequenceSha256": event_hash, "noUnloggedWrites": True,
    }
    log_path = json_file(
        root / "docs" / "evidence" / "transitions" / f"{slug}-write-log.json", log)
    log_ref = {"path": log_path.relative_to(root).as_posix(), "sha256": sha_path(log_path)}
    source_records = {item["path"]: item for item in source_manifest["files"]}
    monitoring = {
        "sessionId": f"MONITOR-{prefix}-{slug.upper()}",
        "providerId": "test-authority", "startEventId": f"START-{prefix}-{slug.upper()}",
        "startedAt": started_at,
        "targets": [
            {"role": "canonical-project", "resolvedRoot": str(root.resolve()),
             "immutableTargetId": source_manifest["baselineId"]},
            {"role": "private-staging", "resolvedRoot": str(staging_root.resolve()),
             "immutableTargetId": (
                 f"{source_manifest['baselineId']}->{result_manifest['baselineId']}"
                 ":private-staging")},
            {"role": "result-artifacts", "resolvedRoot": str(root.resolve()),
             "immutableTargetId": result_manifest["baselineId"]},
        ],
        "startState": {
            "observedAt": observed_at,
            "sourceBaselineTreeSha256": validate_d5.transition_source_tree_sha256(
                source_records),
            "fileSetSha256": source_manifest["fileSetSha256"],
            "targetStartStates": target_start_states,
        },
        "scope": {
            "kind": "in-scope-transition-mutations-v1",
            "coverage": "all-product-ledger-staging-and-result-mutations",
            "includeSetArtifact": include_ref,
            "includeSetSha256": validate_d5.canonical_json_sha256(include_targets),
            "evidenceAcquisitionPolicy": (
                "approval-evidence-outside-transition-mutation-scope"),
            "postMonitorExclusions": [
                "lifecycle-write-log", "lifecycle-transition-attestation",
                "lifecycle-transition-provenance", "w0-handoff-package"],
        },
    }
    source_binding = validate_d5.transition_baseline_reference(source_ref, source_manifest)
    result_binding = validate_d5.transition_baseline_reference(result_ref, result_manifest)
    claims = {
        "kind": f"{transition_type}-transition-v1",
        "sourceBaseline": source_binding, **approvals,
        "monitoring": monitoring,
        "writeLog": {
            **log_ref, "entryCount": len(entries),
            "entrySetSha256": log["entrySetSha256"],
            "eventSequenceSha256": event_hash, "complete": True,
        },
        "noUnloggedWrites": True, **claim_extras,
        ("resultCandidate" if transition_type == "p0" else "resultBaseline"):
            result_binding,
        "eventSequenceSha256": event_hash, "completedAt": completed_at,
    }
    copy_phase = "p0-freeze-copy" if transition_type == "p0" else "d5-snapshot-copy"
    manifest_phase = ("p0-freeze-manifest" if transition_type == "p0"
                      else "d5-snapshot-manifest")
    seal_phase = "p0-freeze" if transition_type == "p0" else "d5-seal"
    copy_events = [item for item in entries if item.get("phase") == copy_phase]
    manifest_events = [item for item in entries if item.get("phase") == manifest_phase]
    seal_events = [item for item in entries if item.get("phase") == seal_phase]
    copy_map = [{
        "sourceRootRole": item["copySource"]["rootRole"],
        "sourcePath": item["copySource"]["path"],
        "sourceSha256": item["copySource"]["sha256"],
        "snapshotPath": item["path"],
        "snapshotSha256": item["after"]["sha256"],
    } for item in sorted(copy_events, key=lambda row: row["path"])]
    snapshot_binding = {
        "sourceFileSetSha256": result_manifest["fileSetSha256"],
        "snapshotRoot": result_manifest["revision"]["snapshotRoot"],
        "copiedFileCount": len(copy_events),
        "copyMapSha256": validate_d5.canonical_json_sha256(copy_map),
        "copyStartedAt": min(item["occurredAt"] for item in copy_events),
        "copyCompletedAt": max(item["occurredAt"] for item in copy_events),
        "manifestCreatedAt": manifest_events[0]["occurredAt"],
        "manifest": {"path": result_ref["path"], "sha256": result_ref["sha256"]},
        "sealEventId": seal_events[0]["eventId"],
    }
    claims["candidateSnapshot" if transition_type == "p0" else "resultSnapshot"] = (
        snapshot_binding)
    created_at = (dt.datetime.fromisoformat(completed_at)
                  + dt.timedelta(seconds=1)).isoformat()
    attestation = {
        "schemaVersion": "1.0.0", "id": f"LTA-{prefix}-{slug.upper()}",
        "transitionType": transition_type, "createdAt": created_at, "claims": claims,
    }
    attestation_path = json_file(
        root / "docs" / "evidence" / "transitions" / f"{slug}-attestation.json",
        attestation)
    attestation_ref = {
        "id": attestation["id"], "path": attestation_path.relative_to(root).as_posix(),
        "sha256": sha_path(attestation_path),
    }
    pv_claims = {
        "kind": "lifecycle-transition-external-v1",
        "transitionType": transition_type, "attestationId": attestation["id"],
        "attestationPath": attestation_ref["path"],
        "attestationSha256": attestation_ref["sha256"], "actual": claims,
    }
    raw_pv_ref = make_provenance_verification(
        root, "lifecycle-transition-attestation", attestation_ref, pv_claims,
        f"{transition_type}-transition-{slug}")
    pv_path = root / raw_pv_ref["path"]
    pv = json.loads(pv_path.read_text(encoding="utf-8"))
    pv["id"] = f"PV-{prefix}-TRANSITION-{slug.upper()}"
    json_file(pv_path, pv)
    pv_ref = {"id": pv["id"], "path": raw_pv_ref["path"], "sha256": sha_path(pv_path)}
    outer = {
        "transitionType": transition_type, "attestation": attestation_ref,
        "provenanceVerification": pv_ref, "writeLog": log_ref,
    }
    inner = {key: outer[key] for key in (
        "attestation", "writeLog", "provenanceVerification")}
    return outer, inner


def fixture_approval_binding(
        root: Path, approval_id: str, verification_ref: dict,
        human_response_at: str) -> dict:
    verified = json.loads((root / verification_ref["path"]).read_text(encoding="utf-8"))
    presentation = (dt.datetime.fromisoformat(human_response_at)
                    - dt.timedelta(minutes=5)).isoformat()
    return {
        "approvalId": approval_id, "verification": verification_ref,
        "presentationAt": presentation, "humanResponseAt": human_response_at,
        "verificationCompletedAt": verified["verifiedAt"],
    }


def build_d5_fixture(root: Path) -> dict[str, Path]:
    """Create the smallest semantically complete snapshot-backed D5 capsule."""
    approved_at = "2026-08-20T12:00:00+09:00"
    gate1_at = "2026-08-19T08:00:00+09:00"
    start_at = "2026-08-20T10:00:00+09:00"
    contract_at = "2026-08-20T11:45:00+09:00"
    gate1_id = "GDD-GATE1-001"
    d5_id, start_id, contract_id = "D5-APP-001", "P0-START-001", "P0-CONTRACT-001"
    package_rel = f"docs/evidence/d5/{d5_id}_w0_handoff_package.json"
    post_rel = f"docs/evidence/d5/{d5_id}_post_sync_manifest.json"
    contract_capture_rel = (
        "docs/evidence/approvals/captures/p0-contract-001.json")
    manifest_rel = "docs/DVT_docs_manifest.json"
    index_rel = "docs/DVT_docs_index.md"
    gdd_rel = "docs/DVT_gdd.md"
    wp_rel = "docs/DVT_work_packages.md"
    machine_rel = "docs/schemas/DVT_machine.json"
    preflight_rel = "docs/preflight.txt"

    intake = approved_intake("D5 Test", "DVT", "d5-fixture")
    intake_path = json_file(root / "docs" / "DVT_intake.json", intake)
    required_specs = {
        "schemaVersion": "1.0.0", "project": "D5 Test", "prefix": "DVT",
        "required_specs": detect_triggers.detect(intake),
    }
    required_specs_path = json_file(
        root / "docs" / "DVT_required_specs.json", required_specs)
    provenance_config = make_provenance_config(root)

    gdd_doc = formal_doc(
        "DVT-GDD", "product intent", "Draft", "—",
        "## Product intent\n\nGate1-approved immutable product intent.",
        "| 0.9.0 | 2026-08-19 | Gate1-approved Draft bytes | — |")
    gdd_doc = gdd_doc.replace(
        "| Version | Date | Change |\n|---|---|---|\n",
        "| Version | Date | Change | Approver |\n|---|---|---|---|\n")
    gdd_target = {
        "path": gdd_rel, "sha256": hashlib.sha256(gdd_doc.encode()).hexdigest(),
        "revision": "1.0.0",
    }
    gate1_scope = {
        "kind": "gdd-gate1-v1", "decision": "approve-gdd-for-d1.5-and-d2",
        "approvedIntake": {
            "path": intake_path.relative_to(root).as_posix(),
            "sha256": sha_path(intake_path),
        },
        "requiredSpecs": {
            "path": required_specs_path.relative_to(root).as_posix(),
            "sha256": sha_path(required_specs_path),
        },
        "additionalScope": False,
    }
    gate1_capture_ref, _, gate1_pv_ref = human_capture(
        root, gate1_id, "gdd-gate1", "targetArtifact", gdd_target,
        gate1_scope, gate1_at)
    gate1_record_ref = approval_record(
        root, gate1_id, "gdd-gate1", "targetArtifact", gdd_target,
        None, gate1_at, gate1_scope, gate1_capture_ref, gate1_pv_ref)
    baseline_gate1_ref = {
        "id": gate1_id, "path": gate1_record_ref["recordPath"],
        "sha256": gate1_record_ref["recordSha256"],
    }

    docs = [
        inventory_item(index_rel, "DVT-INDEX", "navigation"),
        dict(inventory_item(gdd_rel, "DVT-GDD", "product intent"),
             phase="D1", status="review"),
        inventory_item(wp_rel, "DVT-WORK-PACKAGES", "implementation scope"),
        inventory_item(manifest_rel, "DVT-MANIFEST", "machine inventory"),
        inventory_item(machine_rel, "DVT-MACHINE", "machine contract"),
        inventory_item(preflight_rel, "DVT-PREFLIGHT", "preflight contract"),
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
        "## WP-DVT-000\n\n"
        "- Status: Verified\n"
        f"- Authorized by: {contract_id}\n"
        "- Authorization baseline: P0-CAND-DVT-001\n"
        f"- Authorization evidence: {contract_capture_rel}\n\n"
        "## WP-DVT-001\n\n"
        "- Status: Proposed\n- Authorized by: —\n"
        "- Authorization baseline: —\n- Authorization evidence: —\n\n"
        "| WP ID | Status |\n|---|---|\n"
        "| WP-DVT-000 | Verified |\n| WP-DVT-001 | Proposed |",
        "| 0.9.0 | 2026-08-19 | pre-D5 review |")
    inventory_id = "INV-DVT-B0-001"
    source_id = "DVT-OPEN-001"
    b0_progress = (
        "# Progress\n\n"
        "- Current phase: D4\n"
        "- Current Work Package: None\n"
        "- Status: Awaiting P0 start approval\n"
        "- Last known good baseline: B0-DVT-001\n"
        "- Next authorized action: Obtain P0 start approval\n\n"
        "## Proposed P0 closure inventory\n\n"
        f"- Inventory ID: `{inventory_id}`\n\n"
        "| Source item ID | Source path / section | Type (proposal/open/assumption) | Exact bounded P0 closure question / scope | Owner | Required closure evidence / pass rule | Affected canonical docs |\n"
        "|---|---|---|---|---|---|---|\n"
        f"| {source_id} | {preflight_rel} § Constraint | open | Select the exact preflight rule | P0 Owner | evidence/p0-result.json must report pass | {preflight_rel}, {index_rel} |\n\n"
        "## Completed\n\n"
        "### P0 closure records\n\n"
        "| Source item ID | Inventory ID / B0 historical PROGRESS.md SHA-256 | Decision ID | Actual closure evidence / pass result | Affected canonical docs / post-change hashes | Completed at |\n"
        "|---|---|---|---|---|---|\n"
    ).encode()
    b0_progress_hash = hashlib.sha256(b0_progress).hexdigest()
    old_index_hash = hashlib.sha256(old_index.encode()).hexdigest()
    selected_preflight = b"Selected preflight rule: exact-server-check\n"
    selected_preflight_hash = hashlib.sha256(selected_preflight).hexdigest()
    closure_evidence = write(
        root / "evidence" / "p0-result.json", '{"result":"pass"}\n')
    closure_evidence_hash = sha_path(closure_evidence)
    b1_progress = (
        "# Progress\n\n"
        "- Current phase: D5\n"
        "- Current Work Package: None\n"
        "- Status: Awaiting D5 approval\n"
        "- Last known good baseline: B1-DVT-001\n"
        "- Next authorized action: Obtain D5 approval\n\n"
        "## Proposed P0 closure inventory\n\n"
        f"- Inventory ID: `{inventory_id}`\n\n"
        "| Source item ID | Source path / section | Type (proposal/open/assumption) | Exact bounded P0 closure question / scope | Owner | Required closure evidence / pass rule | Affected canonical docs |\n"
        "|---|---|---|---|---|---|---|\n\n"
        "## Completed\n\n"
        "### P0 closure records\n\n"
        "| Source item ID | Inventory ID / B0 historical PROGRESS.md SHA-256 | Decision ID | Actual closure evidence / pass result | Affected canonical docs / post-change hashes | Completed at |\n"
        "|---|---|---|---|---|---|\n"
        f"| {source_id} | {inventory_id} / {b0_progress_hash} | GDD D-12 | evidence/p0-result.json / {closure_evidence_hash} / pass | {preflight_rel} / {selected_preflight_hash}; {index_rel} / {old_index_hash} | 2026-08-20T11:45:00+09:00 |\n"
    ).encode()
    old_contents = {
        index_rel: old_index.encode(), gdd_rel: gdd_doc.encode(), wp_rel: old_wp.encode(),
        manifest_rel: (json.dumps(old_manifest, ensure_ascii=False, indent=2) + "\n").encode(),
        machine_rel: b'{"schemaVersion":"1.0.0","value":"stable"}\n',
        preflight_rel: selected_preflight,
        "DECISIONS.md": b"# Decisions\n\n### GDD D-12: Preflight rule selected\n\nApproved.\n",
        "PROGRESS.md": b1_progress,
        "CHANGELOG.md": b"# Changelog\n",
    }

    pre_contents = dict(old_contents)
    pre_contents.update({
        index_rel: old_index.replace(
            "## Generated Inventory", "Pre-P0 selection: open\n\n## Generated Inventory").encode(),
        wp_rel: old_wp.replace(
            "- Status: Verified", "- Status: Proposed").replace(
                f"- Authorized by: {contract_id}", "- Authorized by: —").replace(
                "- Authorization baseline: P0-CAND-DVT-001",
                "- Authorization baseline: —").replace(
                f"- Authorization evidence: {contract_capture_rel}",
                "- Authorization evidence: —").replace(
                "| WP-DVT-000 | Verified |", "| WP-DVT-000 | Proposed |").encode(),
        preflight_rel: b"Preflight rule awaiting P0 selection\n",
        "DECISIONS.md": b"# Decisions\n",
        "PROGRESS.md": b0_progress,
    })
    d4_candidate, d4_ref, _ = make_baseline(
        root, "D4-CAND-DVT-001", "D4-CANDIDATE", pre_contents,
        None, None, None, [], "review", baseline_gate1_ref,
        "2026-08-19T10:00:00+09:00")
    b0_audits = make_audits(root, "INITIAL", d4_ref, provenance_config)
    b0, b0_ref, _ = make_baseline(
        root, "B0-DVT-001", "B0", pre_contents,
        None, d4_candidate["baselineId"], None, b0_audits, "review",
        baseline_gate1_ref, "2026-08-19T12:00:00+09:00")

    management_wp = {"id": "WP-DVT-000", "path": wp_rel}
    start_scope = {
        "kind": "p0-start-v1",
        "inventory": {
            "path": "PROGRESS.md",
            "section": "Proposed P0 closure inventory",
            "fileSha256": b0_progress_hash,
            "inventoryId": inventory_id,
            "sourceItemIds": [source_id],
        },
        "p0ManagementWp": management_wp,
        "productContentMutation": "inventory-rows-only",
        "fixedProcedure": "p0-standard-six-step-v1",
        "additionalScope": False,
    }
    start_target = validate_d5.baseline_approval_target(b0_ref, b0)
    start_capture_ref, _, start_pv_ref = human_capture(
        root, start_id, "p0-start", "targetBaseline", start_target,
        start_scope, start_at)
    start_record_ref = approval_record(
        root, start_id, "p0-start", "baseline", start_target,
        None, start_at, start_scope, start_capture_ref, start_pv_ref)

    contract_scope = {
        "kind": "p0-contract-v1", "p0StartApprovalId": start_id,
        "inventoryId": inventory_id, "closedSourceItemIds": [source_id],
        "p0ManagementWp": management_wp, "approvalOutcome": "contract-approved",
        "additionalScope": False,
    }
    approved_digest = p0_preapproval_digest(
        old_contents, management_wp, contract_id, "P0-CAND-DVT-001",
        contract_capture_rel)
    planned_candidate = {
        "id": "P0-CAND-DVT-001",
        "approvedContentFileSetSha256": approved_digest,
        "sourceBaselineRevision": b0["revision"],
        "normalizationRule": "strip-fixed-p0-approval-procedure-v1",
    }
    contract_capture_ref, _, contract_pv_ref = human_capture(
        root, contract_id, "p0-contract", "plannedCandidate",
        planned_candidate, contract_scope, contract_at)
    self_capture_rel = contract_capture_ref["path"]
    assert self_capture_rel == contract_capture_rel
    p0_preapproval_contents = dict(old_contents)
    p0_preapproval_contents[wp_rel] = (
        old_contents[wp_rel].decode()
        .replace(f"- Authorized by: {contract_id}", "- Authorized by: —")
        .replace("- Authorization baseline: P0-CAND-DVT-001",
                 "- Authorization baseline: —")
        .replace(f"- Authorization evidence: {contract_capture_rel}",
                 "- Authorization evidence: —").encode())
    for rel, kind in (("DECISIONS.md", "DECISIONS"),
                      ("PROGRESS.md", "PROGRESS"),
                      ("CHANGELOG.md", "CHANGELOG")):
        base = old_contents[rel].decode()
        assert base.endswith("\n") and not base.endswith("\n\n")
        block = validate_d5.p0_contract_block(
            kind, contract_id, "Project Owner", contract_at, contract_capture_rel,
            start_id, inventory_id, [source_id], management_wp,
            "P0-CAND-DVT-001", approved_digest)
        old_contents[rel] = (base + "\n" + block).encode()

    p0_candidate, p0_ref, _ = make_baseline(
        root, "P0-CAND-DVT-001", "P0-CANDIDATE", old_contents,
        b0["baselineId"], None, None, [], "review", baseline_gate1_ref,
        "2026-08-20T11:55:00+09:00")
    contract_target = validate_d5.baseline_approval_target(p0_ref, p0_candidate)
    contract_record_ref = approval_record(
        root, contract_id, "p0-contract", "baseline", contract_target,
        None, contract_at, contract_scope, contract_capture_ref, contract_pv_ref)
    p0_staging_root = root / "docs" / "evidence" / "transitions" / "p0-staging"
    p0_staging_root.mkdir(parents=True, exist_ok=True)
    for rel, payload in pre_contents.items():
        target = p0_staging_root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)
    p0_events: list[dict] = []
    p0_sequence = 0

    def add_p0_event(
            event_id: str, role: str | None, rel: str | None, before: bytes | None,
            after: bytes | None, occurred: str, phase: str, classification: str,
            rule: str, inventory: str | None = None,
            copy_source: dict | None = None, *, monitor_seal: bool = False) -> None:
        nonlocal p0_sequence
        p0_sequence += 1
        p0_events.append(transition_event(
            p0_sequence, event_id, role, rel, before, after, occurred,
            phase, classification, rule, inventory, copy_source,
            monitor_seal=monitor_seal))

    p0_affected = {preflight_rel, index_rel}
    p0_changed = sorted(
        rel for rel in set(pre_contents) | set(old_contents)
        if pre_contents.get(rel) != old_contents.get(rel))
    pre_time = dt.datetime.fromisoformat("2026-08-20T10:05:00+09:00")
    metadata_time = dt.datetime.fromisoformat("2026-08-20T11:46:00+09:00")
    for rel in p0_changed:
        before = pre_contents.get(rel)
        intermediate = p0_preapproval_contents.get(rel, before)
        after = old_contents.get(rel)
        if before != intermediate:
            is_inventory = rel in p0_affected
            phase = "p0-inventory-content" if is_inventory else "p0-preapproval-procedure"
            classification = "inventory-content" if is_inventory else "preapproval-procedural"
            rule = ("p0-inventory-row-affected-doc-v1" if is_inventory else
                    "p0-fixed-preapproval-procedure-v1")
            source_inventory = source_id if is_inventory else None
            occurred = pre_time.isoformat()
            add_p0_event(
                f"P0-STAGING-PRE-{p0_sequence + 1:03d}", "private-staging", rel,
                before, intermediate, occurred, phase, classification, rule,
                source_inventory)
            pre_time += dt.timedelta(seconds=1)
        if intermediate != after:
            occurred = metadata_time.isoformat()
            add_p0_event(
                f"P0-STAGING-META-{p0_sequence + 1:03d}", "private-staging", rel,
                intermediate, after, occurred, "p0-postapproval-metadata",
                "postapproval-metadata", "p0-fixed-postapproval-metadata-v1")
            metadata_time += dt.timedelta(seconds=1)
        stage_target = p0_staging_root / rel
        stage_target.parent.mkdir(parents=True, exist_ok=True)
        if after is not None:
            stage_target.write_bytes(after)

    p0_events.sort(key=lambda item: item["occurredAt"])
    p0_sequence = len(p0_events)
    copy_time = dt.datetime.fromisoformat("2026-08-20T11:47:00+09:00")
    snapshot_root = p0_candidate["revision"]["snapshotRoot"]
    for rel, payload in sorted(old_contents.items()):
        destination = f"{snapshot_root}/{rel}"
        add_p0_event(
            f"P0-SNAPSHOT-COPY-{p0_sequence + 1:03d}", "result-artifacts",
            destination, None, payload, copy_time.isoformat(), "p0-freeze-copy",
            "snapshot-copy", "p0-snapshot-file-copy-v1", None,
            {"rootRole": "private-staging", "path": rel,
             "sha256": hashlib.sha256(payload).hexdigest()})
        copy_time += dt.timedelta(seconds=1)
    add_p0_event(
        f"P0-SNAPSHOT-MANIFEST-{p0_sequence + 1:03d}", "result-artifacts",
        p0_ref["path"], None, (root / p0_ref["path"]).read_bytes(),
        copy_time.isoformat(), "p0-freeze-manifest", "snapshot-manifest",
        "p0-snapshot-manifest-v1")
    copy_time += dt.timedelta(seconds=1)
    add_p0_event(
        f"P0-FREEZE-{p0_sequence + 1:03d}", None, None, None, None,
        copy_time.isoformat(), "p0-freeze", "candidate-freeze",
        "p0-candidate-freeze-v1", monitor_seal=True)
    freeze_time = copy_time
    copy_time += dt.timedelta(seconds=1)
    add_p0_event(
        f"P0-RECORD-{p0_sequence + 1:03d}", "result-artifacts",
        contract_record_ref["recordPath"], None,
        (root / contract_record_ref["recordPath"]).read_bytes(),
        copy_time.isoformat(), "p0-postfreeze-record", "postfreeze-record",
        "p0-contract-machine-record-v1")
    record_time = copy_time
    copy_time += dt.timedelta(seconds=1)
    apply_times: list[str] = []
    for rel in p0_changed:
        before, after = pre_contents.get(rel), old_contents.get(rel)
        destination = f"{snapshot_root}/{rel}"
        occurred = copy_time.isoformat()
        add_p0_event(
            f"P0-APPLY-{p0_sequence + 1:03d}", "canonical-project", rel,
            before, after, occurred, "p0-apply", "canonical-apply",
            "p0-candidate-exact-atomic-apply-v1", None,
            {"rootRole": "result-artifacts", "path": destination,
             "sha256": hashlib.sha256(after or b"").hexdigest()})
        apply_times.append(occurred)
        copy_time += dt.timedelta(seconds=1)
    add_p0_event(
        f"P0-SEAL-{p0_sequence + 1:03d}", None, None, None, None,
        copy_time.isoformat(), "p0-seal", "transition-seal",
        "p0-single-transition-seal-v1", monitor_seal=True)
    seal_time = copy_time
    inventory_event_times = [item["occurredAt"] for item in p0_events
                             if item["classification"] == "inventory-content"]
    preapproval_event_times = [item["occurredAt"] for item in p0_events
                               if item["classification"] in {
                                   "inventory-content", "preapproval-procedural"}]
    p0_transition, p0_transition_inner = make_lifecycle_transition(
        root, "p0", "p0-dvt-001", b0_ref, b0, p0_ref, p0_candidate, p0_events,
        {
            "p0Start": fixture_approval_binding(root, start_id, start_pv_ref, start_at),
            "p0Contract": fixture_approval_binding(
                root, contract_id, contract_pv_ref, contract_at),
        }, p0_staging_root, "2026-08-20T09:50:00+09:00",
        "2026-08-20T09:51:00+09:00",
        (seal_time + dt.timedelta(seconds=1)).isoformat(), {
            "inventoryMutationCount": len(inventory_event_times),
            "firstInventoryMutationAt": min(inventory_event_times)
            if inventory_event_times else None,
            "inventoryMutationCompletedAt": max(inventory_event_times)
            if inventory_event_times else None,
            "preApprovalWriteCount": len(preapproval_event_times),
            "firstPreApprovalWriteAt": min(preapproval_event_times)
            if preapproval_event_times else None,
            "lastPreApprovalWriteAt": max(preapproval_event_times)
            if preapproval_event_times else None,
            "approvedContentFileSetSha256": approved_digest,
            "normalizationRule": "strip-fixed-p0-approval-procedure-v1",
            "approvalPayloadPreparedAt": "2026-08-20T11:35:00+09:00",
            "fixedMetadataWriteAt": min(
                item["occurredAt"] for item in p0_events
                if item["phase"] == "p0-postapproval-metadata"),
            "freezeCompletedAt": freeze_time.isoformat(),
            "p0ContractRecord": {
                "path": contract_record_ref["recordPath"],
                "sha256": contract_record_ref["recordSha256"],
            },
            "postFreezeRecordWriteAt": record_time.isoformat(),
            "firstApplyWriteAt": min(apply_times),
            "lastApplyWriteAt": max(apply_times),
            "sealCompletedAt": seal_time.isoformat(),
        })
    post_audits = make_audits(
        root, "POSTP0", p0_ref, provenance_config, b0_ref,
        p0_transition_inner)
    b1, b1_ref, _ = make_baseline(
        root, "B1-DVT-001", "B1", old_contents,
        b0["baselineId"], p0_candidate["baselineId"], None,
        post_audits, "review", baseline_gate1_ref,
        "2026-08-20T11:59:00+09:00", p0_transition_inner)
    d5_scope = {
        "kind": "d5-v1", "firstWp": {"id": "WP-DVT-001", "path": wp_rel},
        "authorization": "w0-handoff-only", "additionalScope": False,
    }
    d5_target = validate_d5.baseline_approval_target(b1_ref, b1)
    d5_capture_ref, _, d5_pv_ref = human_capture(
        root, d5_id, "d5", "targetBaseline", d5_target, d5_scope, approved_at)
    d5_record_ref = approval_record(
        root, d5_id, "d5", "baseline", d5_target,
        "WP-DVT-001", approved_at, d5_scope, d5_capture_ref, d5_pv_ref)

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
    current_gdd = gdd_doc.replace(
        "| Status | Draft |", "| Status | Approved |", 1).replace(
            "| Last approved | — |", f"| Last approved | {approved_at} |", 1)
    current_gdd += (
        f"| 1.0.0 | {approved_at} | D5 metadata promotion {d5_id} | "
        "Project Owner |\n")
    current_wp = formal_doc(
        "DVT-WORK-PACKAGES", "implementation scope", "Approved", approved_at,
        "## WP-DVT-000\n\n"
        "- Status: Verified\n"
        f"- Authorized by: {contract_id}\n"
        "- Authorization baseline: P0-CAND-DVT-001\n"
        f"- Authorization evidence: {contract_capture_rel}\n\n"
        "## WP-DVT-001\n\n"
        "- Status: Approved\n"
        f"- Authorized by: {d5_id}\n"
        "- Authorization baseline: B2-DVT-001\n"
        f"- Authorization evidence: {package_rel}\n\n"
        "| WP ID | Status |\n|---|---|\n"
        "| WP-DVT-000 | Verified |\n| WP-DVT-001 | Approved |",
        "| 0.9.0 | 2026-08-19 | pre-D5 review |\n"
        f"| 1.0.0 | {approved_at} | {d5_id} approval |")
    current_contents = dict(old_contents)
    current_contents.update({
        index_rel: current_index.encode(), gdd_rel: current_gdd.encode(),
        wp_rel: current_wp.encode(),
        manifest_rel: (json.dumps(current_manifest, ensure_ascii=False, indent=2) + "\n").encode(),
    })
    d5_record_rel = d5_record_ref["recordPath"]
    for rel, kind in (("DECISIONS.md", "DECISIONS"),
                      ("PROGRESS.md", "PROGRESS"),
                      ("CHANGELOG.md", "CHANGELOG")):
        old_text = old_contents[rel].decode()
        if rel == "PROGRESS.md":
            for before, after in (
                    ("- Current phase: D5", "- Current phase: W0"),
                    ("- Current Work Package: None", "- Current Work Package: WP-DVT-001"),
                    ("- Status: Awaiting D5 approval", "- Status: W0 handoff authorized"),
                    ("- Last known good baseline: B1-DVT-001",
                     "- Last known good baseline: B2-DVT-001"),
                    ("- Next authorized action: Obtain D5 approval",
                     "- Next authorized action: Validate W0 handoff and reacquire runtime permissions")):
                old_text = old_text.replace(before, after)
        block = validate_d5.d5_history_block(
            kind, d5_id, "Project Owner", approved_at, d5_record_rel,
            b1["baselineId"], b1["fileSetSha256"], "B2-DVT-001",
            "WP-DVT-001", wp_rel, "\n")
        old_text += validate_d5.append_separator(old_text, "\n") + block
        current_contents[rel] = old_text.encode()
    for rel, payload in current_contents.items():
        target = root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)

    synchronized = [
        index_rel, gdd_rel, wp_rel, manifest_rel,
        "DECISIONS.md", "PROGRESS.md", "CHANGELOG.md",
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
        b1["baselineId"], None, d5_id, post_audits, "approved",
        baseline_gate1_ref, "2026-08-20T12:05:00+09:00",
        p0_transition_inner)

    d5_staging_root = root / "docs" / "evidence" / "transitions" / "d5-staging"
    d5_staging_root.mkdir(parents=True, exist_ok=True)
    for rel, payload in old_contents.items():
        target = d5_staging_root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)
    d5_events: list[dict] = []
    d5_sequence = 0

    def add_d5_event(
            event_id: str, role: str | None, rel: str | None,
            before: bytes | None, after: bytes | None, occurred: str,
            phase: str, classification: str, rule: str,
            copy_source: dict | None = None, *, monitor_seal: bool = False) -> None:
        nonlocal d5_sequence
        d5_sequence += 1
        d5_events.append(transition_event(
            d5_sequence, event_id, role, rel, before, after, occurred,
            phase, classification, rule, None, copy_source,
            monitor_seal=monitor_seal))

    changed_d5 = sorted(
        rel for rel in set(old_contents) | set(current_contents)
        if old_contents.get(rel) != current_contents.get(rel))
    stage_time = dt.datetime.fromisoformat("2026-08-20T12:01:00+09:00")
    formal_paths = {index_rel, gdd_rel, wp_rel}
    for rel in changed_d5:
        before, after = old_contents.get(rel), current_contents.get(rel)
        rule = validate_d5._expected_d5_rule_id(
            rel, manifest_rel, post_rel, formal_paths, wp_rel)
        assert rule is not None and after is not None
        add_d5_event(
            f"D5-STAGE-{d5_sequence + 1:03d}", "private-staging", rel,
            before, after, stage_time.isoformat(), "d5-staging", "d5-staging", rule)
        target = d5_staging_root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(after)
        stage_time += dt.timedelta(seconds=1)
    sync_time = dt.datetime.fromisoformat("2026-08-20T12:02:00+09:00")
    for rel in changed_d5:
        before, after = old_contents.get(rel), current_contents.get(rel)
        rule = validate_d5._expected_d5_rule_id(
            rel, manifest_rel, post_rel, formal_paths, wp_rel)
        assert rule is not None and after is not None
        add_d5_event(
            f"D5-SYNC-{d5_sequence + 1:03d}", "canonical-project", rel,
            before, after, sync_time.isoformat(), "d5-sync", "d5-allowed-sync", rule,
            {"rootRole": "private-staging", "path": rel,
             "sha256": hashlib.sha256(after).hexdigest()})
        sync_time += dt.timedelta(seconds=1)
    allowed_changes = []
    old_states = {rel: transition_state(payload) for rel, payload in old_contents.items()}
    b2_states = {rel: transition_state(payload) for rel, payload in b2_contents.items()}
    for rel in sorted(set(old_states) | set(b2_states)):
        before, after = old_states.get(rel, transition_state(None)), b2_states.get(
            rel, transition_state(None))
        if before == after:
            continue
        rule = validate_d5._expected_d5_rule_id(
            rel, manifest_rel, post_rel, formal_paths, wp_rel)
        assert rule is not None
        allowed_changes.append({
            "path": rel, "beforeSha256": before["sha256"],
            "afterSha256": after["sha256"], "ruleId": rule,
        })
    allowed_rel = "docs/evidence/transitions/d5-allowed-diff.json"
    allowed_path = write(
        root / allowed_rel,
        validate_d5.canonical_json_bytes({"changes": allowed_changes}).decode("utf-8"))
    allowed_ref = {"path": allowed_rel, "sha256": sha_path(allowed_path)}
    allowed_at = dt.datetime.fromisoformat("2026-08-20T12:03:00+09:00")
    add_d5_event(
        f"D5-ALLOWED-{d5_sequence + 1:03d}", "result-artifacts", allowed_rel,
        None, allowed_path.read_bytes(), allowed_at.isoformat(), "d5-allowed-diff",
        "d5-result-artifact", "d5-allowed-diff-artifact-v1")
    post_at = allowed_at + dt.timedelta(seconds=1)
    add_d5_event(
        f"D5-POST-SYNC-{d5_sequence + 1:03d}", "result-artifacts", post_rel,
        None, post_path.read_bytes(), post_at.isoformat(), "d5-post-sync-manifest",
        "d5-result-artifact", "d5-post-sync-manifest-v1")
    snapshot_time = post_at + dt.timedelta(seconds=1)
    b2_snapshot_root = b2["revision"]["snapshotRoot"]
    for rel, payload in sorted(b2_contents.items()):
        source_role = "result-artifacts" if rel == post_rel else "canonical-project"
        add_d5_event(
            f"D5-SNAPSHOT-COPY-{d5_sequence + 1:03d}", "result-artifacts",
            f"{b2_snapshot_root}/{rel}", None, payload, snapshot_time.isoformat(),
            "d5-snapshot-copy", "snapshot-copy", "d5-snapshot-file-copy-v1",
            {"rootRole": source_role, "path": rel,
             "sha256": hashlib.sha256(payload).hexdigest()})
        snapshot_time += dt.timedelta(seconds=1)
    add_d5_event(
        f"D5-SNAPSHOT-MANIFEST-{d5_sequence + 1:03d}", "result-artifacts",
        b2_ref["path"], None, (root / b2_ref["path"]).read_bytes(),
        snapshot_time.isoformat(), "d5-snapshot-manifest", "snapshot-manifest",
        "d5-b2-baseline-manifest-v1")
    snapshot_time += dt.timedelta(seconds=1)
    add_d5_event(
        f"D5-SEAL-{d5_sequence + 1:03d}", None, None, None, None,
        snapshot_time.isoformat(), "d5-seal", "transition-seal",
        "d5-snapshot-immutability-seal-v1", monitor_seal=True)
    d5_transition, _ = make_lifecycle_transition(
        root, "d5", "d5-dvt-001", b1_ref, b1, b2_ref, b2, d5_events,
        {"d5Approval": fixture_approval_binding(root, d5_id, d5_pv_ref, approved_at)},
        d5_staging_root, "2026-08-20T11:50:00+09:00",
        "2026-08-20T11:51:00+09:00",
        (snapshot_time + dt.timedelta(seconds=1)).isoformat(), {
            "firstSyncWriteAt": min(
                item["occurredAt"] for item in d5_events if item["phase"] == "d5-sync"),
            "lastSyncWriteAt": max(
                item["occurredAt"] for item in d5_events if item["phase"] == "d5-sync"),
            "allowedDiffRule": "d5-fixed-allowlist-v1",
            "allowedDiffArtifact": allowed_ref,
            "allowedDiffSha256": validate_d5.canonical_json_sha256(allowed_changes),
            "allowedDiffArtifactCreatedAt": allowed_at.isoformat(),
            "postSyncManifest": {"path": post_rel, "sha256": sha_path(post_path)},
            "postSyncManifestCreatedAt": post_at.isoformat(),
            "sealCompletedAt": snapshot_time.isoformat(),
        })

    gdd_normalize_errors: list[str] = []
    normalized_gdd, normalized_current_gdd = validate_d5.normalize_formal_transition(
        gdd_doc, current_gdd, gdd_rel, d5_id, approved_at,
        gdd_normalize_errors, index=False, wp_id=None)
    assert not gdd_normalize_errors and normalized_gdd == normalized_current_gdd
    gdd_transform = {
        "path": gdd_rel, "gate1DraftSha256": gdd_target["sha256"],
        "b1Sha256": hashlib.sha256(gdd_doc.encode()).hexdigest(),
        "b2Sha256": hashlib.sha256(current_gdd.encode()).hexdigest(),
        "normalizedBodySha256": hashlib.sha256(gdd_doc.encode()).hexdigest(),
        "rule": "d5-formal-metadata-only-v1", "d5ApprovedAt": approved_at,
    }

    package = {
        "schemaVersion": "1.0.0", "packageId": "W0-DVT-001",
        "project": "D5 Test", "prefix": "DVT", "createdAt": approved_at,
        "acceptanceProvenanceMode": "offline-pinned-signature-only-v1",
        "gddGate1": gate1_record_ref,
        "gddD5Transformation": gdd_transform,
        "d15Measurements": [],
        "d5Approval": {
            "id": d5_id, "approvedAt": approved_at, "approver": "Project Owner",
            "recordPath": d5_record_ref["recordPath"],
            "recordSha256": d5_record_ref["recordSha256"],
        },
        "p0": {
            "startApprovalId": start_id,
            "startApprovalRecordPath": start_record_ref["recordPath"],
            "startApprovalRecordSha256": start_record_ref["recordSha256"],
            "contractApprovalId": contract_id,
            "contractApprovalRecordPath": contract_record_ref["recordPath"],
            "contractApprovalRecordSha256": contract_record_ref["recordSha256"],
        },
        "approvalCaptures": {
            "gddGate1": gate1_capture_ref, "p0Start": start_capture_ref,
            "p0Contract": contract_capture_ref, "d5": d5_capture_ref,
        },
        "approvalVerifications": {
            "gddGate1": gate1_pv_ref, "p0Start": start_pv_ref,
            "p0Contract": contract_pv_ref, "d5": d5_pv_ref,
        },
        "lifecycleTransitions": {"p0": p0_transition, "d5": d5_transition},
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
        "post_p0_capsule": root / post_audits[0]["auditCapsule"]["path"],
        "b0_snapshot_progress": root / b0["revision"]["snapshotRoot"] / "PROGRESS.md",
        "b1_snapshot_progress": root / b1["revision"]["snapshotRoot"] / "PROGRESS.md",
        "b1_snapshot_gdd": root / b1["revision"]["snapshotRoot"] / gdd_rel,
        "b1_snapshot_machine": root / b1["revision"]["snapshotRoot"] / machine_rel,
        "current_machine": root / machine_rel,
        "p0_start_record": root / start_record_ref["recordPath"],
        "provenance_config": provenance_config,
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

    def test_d4_snapshot_tree_must_exact_manifest_and_reject_hardlinks(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td).resolve()
            snapshot = root / "snapshot"
            snapshot.mkdir()
            first = write(snapshot / "a.txt", "a")
            extra = write(snapshot / ".git" / "extra", "extra")
            manifest = json_file(root / "candidate.json", {
                "baselineId": "D4-CAND-EXACT-001",
                "revision": {"kind": "snapshot", "value": "SNAP-EXACT-001",
                             "snapshotRoot": "snapshot", "gitStatusEvidence": None},
                "files": [{"path": "a.txt", "bytes": first.stat().st_size,
                           "sha256": sha_path(first)}],
            })
            command = [sys.executable, "-B", str(SCRIPT_DIR / "d4_preflight.py"),
                       "--operation", "tree", "--source-root", str(snapshot),
                       "--candidate-manifest", str(manifest), "--git-executable", "disabled"]
            omitted = run_cli(command)
            self.assertNotEqual(omitted.returncode, 0)
            self.assertIn("exact-cover", omitted.stderr)

            extra.unlink()
            extra.parent.rmdir()
            hardlink = snapshot / "b.txt"
            try:
                os.link(first, hardlink)
            except OSError:
                self.skipTest("filesystem does not support hardlinks")
            data = json.loads(manifest.read_text(encoding="utf-8"))
            data["files"].append({"path": "b.txt", "bytes": hardlink.stat().st_size,
                                  "sha256": sha_path(hardlink)})
            json_file(manifest, data)
            linked = run_cli(command)
            self.assertNotEqual(linked.returncode, 0)
            self.assertIn("hardlinked", linked.stderr)

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

            fast = approved_intake("Alias Test", "ALS")
            fast["technical"]["high_frequency_projectiles_or_fast_pvp"] = True
            specs = {item["id"]: item for item in detect_triggers.detect(fast)}
            self.assertIn("feasibility_report", specs)
            required = specs["feasibility_report"]["measurementContract"][
                "requiredSubchecks"]
            self.assertEqual(
                [item["id"] for item in required],
                ["technical.high_frequency_projectiles_or_fast_pvp"])

            contradictory = approved_intake("Alias Test", "ALS")
            source_id = contradictory["fieldSources"][
                "technical.high_frequency_projectiles_or_fast_pvp"][0]
            contradictory["answers"][source_id]["value"] = (
                "Fast PvP with high-frequency projectiles is a core mechanic")
            errors = detect_triggers.validate_intake(contradictory)
            self.assertTrue(any("contradicts explicit positive risk fact" in error
                                for error in errors), errors)

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
            self.assertIn("docs/REC_docs_manifest.json", paths)
            schema_names = {
                path.name for path in (SCRIPT_DIR.parent / "schemas").glob("*.schema.json")
                if path.name not in {
                    "provenance_verifier_config.schema.json",
                    "w0_runtime_launch_challenge.schema.json",
                    "w0_runtime_prepare_execution_attestation.schema.json",
                    "w0_runtime_prelaunch_assertion.schema.json",
                    "w0_runtime_postexecution_attestation.schema.json",
                    "w0_runtime_admit_execution_attestation.schema.json",
                }}
            self.assertTrue({f"docs/schemas/{name}" for name in schema_names} <= paths)
            instance_names = {path.name for path in (SCRIPT_DIR.parent / "schemas").glob("*.json")
                              if not path.name.endswith(".schema.json")}
            self.assertTrue({f"docs/schemas/REC_{name}" for name in instance_names} <= paths)
            by_path = {item["path"]: item for item in manifest["documents"]}
            expected_phases = {
                "docs/schemas/intake.schema.json": "D0",
                "docs/schemas/remote_contract.schema.json": "D2",
                "docs/schemas/save_schema.schema.json": "D2",
                "docs/schemas/analytics_event.schema.json": "D2",
                "docs/schemas/asset_ledger.schema.json": "D2",
                "docs/schemas/commerce_ledger.schema.json": "D2",
                "docs/schemas/work_package.schema.json": "D3",
                "docs/schemas/docs_manifest.schema.json": "D3",
                "docs/traceability/REC_requirements.csv": "D3",
                "docs/REC_docs_manifest.json": "D3",
                "docs/schemas/baseline_manifest.schema.json": "D4",
                "docs/schemas/d4_audit_capsule.schema.json": "D4",
                "docs/schemas/d4_audit_policy_manifest.schema.json": "D4",
                "docs/schemas/d4_runtime_allowlist.schema.json": "D4",
                "docs/schemas/d4_audit_request.schema.json": "D4",
                "docs/schemas/d4_auditor_attestation.schema.json": "D4",
                "docs/schemas/pinned_signature_evidence.schema.json": "D1",
                "docs/schemas/provenance_verification.schema.json": "D1",
                "docs/schemas/trusted_runtime_query_result.schema.json": "D1",
                "docs/schemas/gate_approval_record.schema.json": "D1",
                "docs/schemas/human_approval_capture.schema.json": "D1",
                "docs/schemas/human_approval_challenge.schema.json": "D1",
                "docs/schemas/human_interaction_transcript.schema.json": "D1",
                "docs/schemas/d15_measurement_evidence.schema.json": "D1.5",
                "docs/schemas/post_sync_manifest.schema.json": "D5",
                "docs/schemas/w0_handoff_package.schema.json": "D5",
            }
            for path, phase in expected_phases.items():
                self.assertEqual(by_path[path]["phase"], phase, path)
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
            accepted = run_w0_cli([
                "--project-root", str(root), "--source-project-root", str(source),
                "--prefix", "DVT", "--package", str(package_rel),
                "--provenance-config", str(fixture["provenance_config"]), "--json"])
            self.assertEqual(accepted.returncode, 0, accepted.stdout + accepted.stderr)
            self.assertTrue(json.loads(accepted.stdout)["pass"])

            snapshot = fixture["b1_snapshot_machine"]
            snapshot_original = snapshot.read_bytes()
            snapshot.write_bytes(snapshot_original + b"tampered")
            rejected = validate_fixture(root, fixture, source)
            self.assertFalse(rejected["pass"])
            self.assertTrue(any("historical" in error for error in rejected["errors"]),
                            rejected["errors"])
            snapshot.write_bytes(snapshot_original)

            b1_gdd = fixture["b1_snapshot_gdd"]
            b1_gdd_original = b1_gdd.read_text(encoding="utf-8")
            b1_gdd.write_text(
                b1_gdd_original.replace("| Status | Draft |", "| Status | Review |", 1),
                encoding="utf-8")
            rejected = validate_fixture(root, fixture, source)
            self.assertTrue(any(
                "Gate1 GDD historical B1 Status must be exactly Draft" in error
                for error in rejected["errors"]), rejected["errors"])
            b1_gdd.write_text(b1_gdd_original, encoding="utf-8")

            current = fixture["current_machine"]
            current.write_bytes(current.read_bytes() + b"unauthorized")
            rejected = validate_fixture(root, fixture, source)
            self.assertFalse(rejected["pass"])
            self.assertTrue(any("unauthorized artifact" in error for error in rejected["errors"]),
                            rejected["errors"])

    def test_standalone_p0_lifecycle_validator_rejects_initial_and_accepts_bound_post_p0(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td).resolve()
            fixture = build_d5_fixture(root)
            command = [
                sys.executable, str(SCRIPT_DIR / "validate_lifecycle_transition.py"),
                "--project-root", str(root), "--capsule",
                str(fixture["post_p0_capsule"]), "--transition-type", "p0",
                "--provenance-config", str(fixture["provenance_config"]),
                "--fresh-authenticate", "--json",
            ]
            accepted = run_cli(command)
            self.assertEqual(accepted.returncode, 0, accepted.stdout + accepted.stderr)
            self.assertTrue(json.loads(accepted.stdout)["pass"])

            capsule_path = fixture["post_p0_capsule"]
            capsule = json.loads(capsule_path.read_text(encoding="utf-8"))
            capsule["auditScope"]["kind"] = "initial-d4-v1"
            json_file(capsule_path, capsule)
            rejected = run_cli(command)
            self.assertNotEqual(rejected.returncode, 0)
            result = json.loads(rejected.stdout)
            self.assertTrue(any("only post-p0-d4-v1" in error
                                for error in result["errors"]), result["errors"])

    def test_w0_query_mode_is_rejected_before_any_external_runner(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td).resolve()
            fixture = build_d5_fixture(root)
            package = json.loads(fixture["package"].read_text(encoding="utf-8"))
            pv_ref = package["approvalVerifications"]["d5"]
            pv_path = root / pv_ref["path"]
            pv = json.loads(pv_path.read_text(encoding="utf-8"))
            pv["verificationMode"] = "trusted-runtime-query"
            json_file(pv_path, pv)

            sentinel = root.parent / f"{root.name}-operator" / "adapter-invoked.txt"
            config = json.loads(fixture["provenance_config"].read_text(encoding="utf-8"))
            adapter_path = Path(config["trustedRuntimeAdapters"][0]["adapterArtifact"]["path"])
            adapter_path.write_text(
                f"from pathlib import Path\nPath({str(sentinel)!r}).write_text('invoked')\n",
                encoding="utf-8")
            config["trustedRuntimeAdapters"][0]["adapterArtifact"]["sha256"] = sha_path(
                adapter_path)
            json_file(fixture["provenance_config"], config)

            rejected = run_w0_cli([
                "--project-root", str(root), "--source-project-root", str(root),
                "--prefix", "DVT", "--package",
                str(fixture["package"].relative_to(root)),
                "--provenance-config", str(fixture["provenance_config"]), "--json"])
            self.assertNotEqual(rejected.returncode, 0)
            result = json.loads(rejected.stdout)
            self.assertTrue(any("no external runner was invoked" in error
                                for error in result["errors"]), result["errors"])
            self.assertFalse(sentinel.exists(), "query adapter was invoked before offline rejection")

    def test_w0_receiver_bootstrap_prepare_copies_exact_closure_without_python(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td).resolve()
            package = json_file(root / "docs" / "w0.json", {
                "schemaVersion": "1.0.0", "packageId": "W0-PREPARE-001",
                "prefix": "DVT",
                "acceptanceProvenanceMode": "offline-pinned-signature-only-v1",
            })
            config_path = make_provenance_config(root)
            config = json.loads(config_path.read_text(encoding="utf-8"))
            pwsh_pin, pwsh_root, pwsh_version = pinned_test_powershell()
            bootstrap = config["w0ValidatorRuntime"]["receiverBootstrap"]
            bootstrap["hostExecutable"] = pwsh_pin
            bootstrap["hostRuntimeRoots"] = [pwsh_root]
            bootstrap["hostVersion"] = pwsh_version
            json_file(config_path, config)
            auth_root = config_path.parent / "authorization"
            auth_root.mkdir()
            challenge = config_path.parent / "launch-challenge.json"
            command = [
                pwsh_pin["path"], *bootstrap["hostFixedArgs"],
                bootstrap["script"]["path"], "-Phase", "PREPARE",
                "-ConfigPath", str(config_path),
                "-ExpectedConfigSha256", sha_path(config_path),
                "-PackagePath", str(package),
                "-ProjectRoot", str(root), "-LaunchChallengeOutputPath", str(challenge),
                "-AuthorizationEvidenceRoot", str(auth_root),
            ]
            result = run_cli(command)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            value = json.loads(challenge.read_text(encoding="utf-8"))
            self.assertFalse(value["pythonStarted"])
            self.assertEqual(value["status"], "prepared-awaiting-authority")
            self.assertEqual(value["resolvedProjectRoot"], root.as_posix())
            self.assertIn("\\", str(root), "fixture must exercise ordinary Windows path spelling")
            temp_root = Path(value["resolvedTempRoot"])
            self.assertEqual(
                {path.relative_to(temp_root).as_posix()
                 for path in temp_root.rglob("*") if path.is_file()},
                {"scripts/validate_d5_acceptance.py", "scripts/gen_index.py",
                 "scripts/state_readiness.py", "scripts/strict_json.py"})
            shutil.rmtree(temp_root)

    def test_w0_bootstrap_security_primitives_reject_coercion_and_reordering(self):
        pwsh = shutil.which("pwsh")
        if pwsh is None:
            self.skipTest("PowerShell 7 is unavailable")
        bootstrap = (SCRIPT_DIR / "w0_receiver_bootstrap.ps1").resolve()
        probe = "$bootstrapPath=" + json.dumps(str(bootstrap)) + ";\n" + r'''
$source=[IO.File]::ReadAllText($bootstrapPath)
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'bootstrap parse failed'}
$names=@('Stop-W0','Compare-CodePointString','Sort-RecordsByCodePoint',
         'Assert-JsonBoolean','Assert-JsonInteger','Assert-JsonIntegerRange',
         'Assert-JsonStringMinimum','Assert-JsonFramedStringMinimum',
         'ConvertTo-Time','Assert-ExactKeyOrder',
         'Assert-UniqueTreeRoots','Assert-AdmissionSemanticOrder',
         'Assert-ReceiptFreshIdentifiers','Assert-ReceiptChronology',
         'Get-CanonicalHostArgv')
foreach($name in $names){
  $node=$ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true)|Select-Object -First 1
  if($null -eq $node){throw "missing function $name"}
  Invoke-Expression $node.Extent.Text
}
$bad=@(
  {Assert-JsonBoolean 'False' $false 'bool'},
  {Assert-JsonInteger '0' 0 'int-string'},
  {Assert-JsonIntegerRange ([double]0.0) 0 1 'int-float'},
  {Assert-JsonStringMinimum 123 1 'string'},
  {Assert-JsonFramedStringMinimum (('n'*31)+[char]0) 32 'framed-string'},
  {ConvertTo-Time '2026-08-20T12:00:00' 'time'},
  {ConvertTo-Time '2026-08-20T12:00:00.12345678Z' 'precision'},
  {Assert-ExactKeyOrder ([ordered]@{b=1;a=2}) @('a','b') 'order'},
  {Assert-UniqueTreeRoots @([ordered]@{root='C:/runtime'},[ordered]@{root='c:/RUNTIME'}) 'roots'},
  {Assert-AdmissionSemanticOrder '2026-08-20T00:00:02Z' ([DateTimeOffset]'2026-08-20T00:00:01Z')}
)
foreach($case in $bad){
  $rejected=$false
  try{& $case}catch{$rejected=$true}
  if(-not $rejected){throw 'security primitive accepted malformed input'}
}
$challenge=[ordered]@{receiverNonce=('r'*32)}
$admissionToken=[ordered]@{eventId='ADMISSION-EVENT';nonce=('a'*32)}
$consumption=[ordered]@{consumptionEventId='CONSUMPTION-EVENT';consumedAt='2026-08-20T00:00:01Z'}
$capability=[ordered]@{eventId='CAPABILITY-EVENT';nonce=('c'*32);issuedAt='2026-08-20T00:00:04Z';expiresAt='2026-08-20T00:00:09Z';lifetimeSeconds=[int64]5}
$worker=[ordered]@{launchedAt='2026-08-20T00:00:02Z';observedAt='2026-08-20T00:00:03Z'}
Assert-ReceiptFreshIdentifiers $capability $consumption $admissionToken $challenge
Assert-UniqueTreeRoots @([ordered]@{root='C:/runtime-a'},[ordered]@{root='C:/runtime-b'}) 'roots'
Assert-AdmissionSemanticOrder '2026-08-20T00:00:00Z' ([DateTimeOffset]'2026-08-20T00:00:01Z')
$hostContext=[pscustomobject]@{
  HostBinary='C:/pinned/pwsh.exe';BootstrapScript='C:/skill/bootstrap.ps1'
  Bootstrap=[ordered]@{hostFixedArgs=@('-NoLogo','-File')}
}
$canonicalArgv=@(Get-CanonicalHostArgv $hostContext @('-Phase','ADMIT','-ProjectRoot','C:/project'))
if(($canonicalArgv -join "`0") -cne
   (@('C:/pinned/pwsh.exe','-NoLogo','-File','C:/skill/bootstrap.ps1',
      '-Phase','ADMIT','-ProjectRoot','C:/project') -join "`0")) {
  throw 'canonical host argv does not start with pinned executable/protocol vector'
}
$wrongArgv=@(Get-CanonicalHostArgv $hostContext @('-Phase','ADMIT','-ProjectRoot','C:/other'))
if(($wrongArgv -join "`0") -ceq ($canonicalArgv -join "`0")) {
  throw 'different resolved protocol path did not change canonical argv'
}
Assert-ReceiptChronology ([DateTimeOffset]'2026-08-20T00:00:00Z') $consumption $worker $capability `
  '2026-08-20T00:00:05Z' '2026-08-20T00:00:10Z' '2026-08-20T00:00:11Z' `
  '2026-08-20T00:00:12Z' ([DateTimeOffset]'2026-08-20T00:00:05Z') 30 5 | Out-Null
$receiptBad=@(
  {Assert-ReceiptFreshIdentifiers $capability $consumption ([ordered]@{eventId='ADMISSION-EVENT';nonce=('a'*31)}) $challenge},
  {Assert-ReceiptFreshIdentifiers $capability $consumption ([ordered]@{eventId='ADMISSION-EVENT';nonce=('r'*32)}) $challenge},
  {Assert-ReceiptFreshIdentifiers ([ordered]@{eventId='ADMISSION-EVENT';nonce=('c'*32)}) $consumption $admissionToken $challenge},
  {Assert-ReceiptFreshIdentifiers ([ordered]@{eventId='CONSUMPTION-EVENT';nonce=('c'*32)}) $consumption $admissionToken $challenge},
  {Assert-ReceiptFreshIdentifiers ([ordered]@{eventId='CAP';nonce=('a'*32)}) $consumption $admissionToken $challenge},
  {Assert-ReceiptFreshIdentifiers ([ordered]@{eventId='CAP';nonce=('r'*32)}) $consumption $admissionToken $challenge},
  {Assert-ReceiptFreshIdentifiers ([ordered]@{eventId='CAP';nonce=('c'*31)}) $consumption $admissionToken $challenge},
  {Assert-ReceiptChronology ([DateTimeOffset]'2026-08-20T00:00:00Z') $consumption $worker $capability '2026-08-20T00:00:05Z' '2026-08-20T00:00:01Z' '2026-08-20T00:00:11Z' '2026-08-20T00:00:12Z' ([DateTimeOffset]'2026-08-20T00:00:05Z') 30 5},
  {Assert-ReceiptChronology ([DateTimeOffset]'2026-08-20T00:00:00Z') $consumption $worker $capability '2026-08-20T00:00:05Z' '2026-08-20T00:00:10Z' '2026-08-20T00:00:08Z' '2026-08-20T00:00:12Z' ([DateTimeOffset]'2026-08-20T00:00:05Z') 30 5},
  {Assert-ReceiptChronology ([DateTimeOffset]'2026-08-20T00:00:00Z') $consumption $worker $capability '2026-08-20T00:00:09Z' '2026-08-20T00:00:10Z' '2026-08-20T00:00:11Z' '2026-08-20T00:00:12Z' ([DateTimeOffset]'2026-08-20T00:00:05Z') 30 5},
  {Assert-ReceiptChronology ([DateTimeOffset]'2026-08-20T00:00:00Z') $consumption $worker $capability '2026-08-20T00:00:05Z' '2026-08-20T00:00:10Z' '2026-08-20T00:00:11Z' '2026-08-20T00:00:12Z' ([DateTimeOffset]'2026-08-20T00:00:09Z') 30 5}
)
foreach($case in $receiptBad){
  $rejected=$false
  try{& $case | Out-Null}catch{$rejected=$true}
  if(-not $rejected){throw 'receipt replay/expiry guard accepted malformed chain'}
}
$rows=@([ordered]@{path=[string][char]0xE000},[ordered]@{path=[char]::ConvertFromUtf32(0x1F600)})
$sorted=@(Sort-RecordsByCodePoint $rows 'path')
if([int][char]$sorted[0].path[0] -ne 0xE000){throw 'sort is not Unicode code-point order'}
'security-primitives-ok'
'''
        result = run_cli([
            pwsh, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command",
            probe,
        ])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("security-primitives-ok", result.stdout)
        source = bootstrap.read_text(encoding="utf-8")
        self.assertIn("status='validated-awaiting-admit'", source)
        self.assertNotIn("pass=$true;phase='VALIDATE'", source)
        self.assertIn("Assert-AdmitExecutionReceipt", source)
        self.assertIn("$Capability.eventId -ceq $AdmissionToken.eventId", source)
        self.assertIn("$Capability.nonce -ceq $Challenge.receiverNonce", source)
        self.assertIn("authority did not provide signed ADMIT execution/worker-ready receipt", source)
        self.assertIn("Get-AbsoluteTreeReadRecords $receiverRoot", source)
        self.assertIn("retained postexecution attestation path/hash/identity scope mismatch", source)
        self.assertNotIn("ActualProcessArgv", source)
        self.assertIn("Get-CanonicalHostArgv $context", source)
        self.assertTrue(validate_d5.timezone_datetime(
            "2026-08-20T12:00:00.1234567Z"))
        self.assertLess(
            validate_d5.parsed_timestamp("2026-08-20T12:00:00.1234567Z"),
            validate_d5.parsed_timestamp("2026-08-20T12:00:00.1234568Z"))
        self.assertFalse(validate_d5.timezone_datetime(
            "2026-08-20T12:00:00.12345678Z"))
        self.assertFalse(validate_d5.timezone_datetime(
            " 2026-08-20T12:00:00Z"))
        self.assertFalse(validate_d5.timezone_datetime(
            "٢٠٢٦-٠٨-٢٠T١٢:٠٠:٠٠Z"))
        self.assertTrue(validate_d5.timezone_datetime(
            "2026-08-20T12:00:00+14:00"))
        self.assertFalse(validate_d5.timezone_datetime(
            "2026-08-20T12:00:60Z"))
        self.assertFalse(validate_d5.timezone_datetime(
            "2026-08-20T12:00:00+14:01"))
        self.assertFalse(validate_d5.timezone_datetime(
            "2026-08-20T12:00:00+23:59"))
        self.assertFalse(validate_d5._framed_string(("r" * 16) + "\0", 16))
        self.assertFalse(validate_d5._framed_string(("n" * 32) + "\0", 32))

    def test_w0_signed_admission_receipt_actual_verifier_and_negatives(self):
        pwsh = shutil.which("pwsh")
        if pwsh is None:
            self.skipTest("PowerShell 7 is unavailable")
        with tempfile.TemporaryDirectory() as td:
            fixture_root = Path(td).resolve()
            bootstrap = (SCRIPT_DIR / "w0_receiver_bootstrap.ps1").resolve()
            probe = (
                "$bootstrapPath=" + json.dumps(str(bootstrap)) + ";\n" +
                "$fixtureRoot=" + json.dumps(str(fixture_root)) + ";\n" + r'''
$source=[IO.File]::ReadAllText($bootstrapPath)
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'bootstrap parse failed'}
$native=$ast.FindAll({param($n)
  $n -is [Management.Automation.Language.IfStatementAst] -and
  $n.Extent.Text.Contains('W0NativeFileIdentity') -and
  $n.Extent.Text.Contains('Add-Type -TypeDefinition')},$true)|Select-Object -First 1
if($null -eq $native){throw 'native identity block missing'}
Invoke-Expression $native.Extent.Text
$names=@(
  'Stop-W0','Assert-JsonBoolean','Assert-JsonInteger','Assert-JsonIntegerRange',
  'Assert-JsonStringMinimum','Assert-JsonFramedStringMinimum',
  'Compare-CodePointString','Sort-RecordsByCodePoint','Get-Sha256Bytes','Get-Sha256File',
  'ConvertTo-NormalizedPath','Test-Within','Assert-ExternalPath','Assert-NoDuplicateJson',
  'Read-StrictJson','ConvertTo-CanonicalJson','ConvertTo-OrderedMinifiedJson',
  'Get-CanonicalBytes','Get-CanonicalSha256','Assert-ExactKeys','Assert-ExactKeyOrder',
  'Get-PathIdentity','Get-JoinedSha256','Get-ClosedEnvironment','Get-EnvironmentSha256',
  'ConvertFrom-DetachedSignatureBytes','Read-VerifiedSignedJson','ConvertTo-Time',
  'Assert-Value','Get-CanonicalHostArgv','Get-AdmitHostArgv',
  'Assert-AdmissionSemanticOrder','Assert-ReceiptFreshIdentifiers',
  'Assert-ReceiptChronology','Assert-AdmitExecutionReceipt')
foreach($name in $names){
  $node=$ast.FindAll({param($n)
    $n -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $n.Name -ceq $name},$true)|Select-Object -First 1
  if($null -eq $node){throw "missing function $name"}
  Invoke-Expression $node.Extent.Text
}
$script:Utf8=[Text.UTF8Encoding]::new($false,$true)
$script:JsonStringOptions=[Text.Json.JsonSerializerOptions]::new()
$script:JsonStringOptions.Encoder=[Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
[IO.Directory]::CreateDirectory($fixtureRoot)|Out-Null
function Write-Bytes([string]$Path,[string]$Text){
  [IO.File]::WriteAllBytes($Path,$script:Utf8.GetBytes($Text))
}
function New-OrderedRecord([string[]]$Keys){
  $value=[ordered]@{};foreach($key in $Keys){$value[$key]=$null};return $value
}
function Write-SignedRecord([Collections.IDictionary]$Value,[string]$JsonPath,[string]$SigPath){
  $raw=$script:Utf8.GetBytes((ConvertTo-OrderedMinifiedJson $Value))
  [IO.File]::WriteAllBytes($JsonPath,$raw)
  $signature=$script:TestRsa.SignData(
    $raw,[Security.Cryptography.HashAlgorithmName]::SHA256,
    [Security.Cryptography.RSASignaturePadding]::Pss)
  [IO.File]::WriteAllBytes($SigPath,$script:Utf8.GetBytes([Convert]::ToBase64String($signature)))
}
function Assert-Rejected([scriptblock]$Case,[string]$Label){
  try{& $Case|Out-Null}catch{return}
  throw "$Label was accepted"
}
function Stamp([DateTimeOffset]$Value){return $Value.ToString("yyyy-MM-ddTHH:mm:ss'Z'")}
Assert-Rejected {ConvertTo-NormalizedPath '/tmp/w0.json' $false} 'POSIX operator path'

$script:TestRsa=[Security.Cryptography.RSA]::Create(2048)
$request=[Security.Cryptography.X509Certificates.CertificateRequest]::new(
  'CN=W0 signed receipt regression',$script:TestRsa,
  [Security.Cryptography.HashAlgorithmName]::SHA256,
  [Security.Cryptography.RSASignaturePadding]::Pkcs1)
$certificate=$request.CreateSelfSigned(
  [DateTimeOffset]::UtcNow.AddMinutes(-1),[DateTimeOffset]::UtcNow.AddMinutes(10))
$anchor=Join-Path $fixtureRoot 'authority.cer'
[IO.File]::WriteAllBytes($anchor,$certificate.Export(
  [Security.Cryptography.X509Certificates.X509ContentType]::Cert))
$certificate.Dispose()

$dummy=Join-Path $fixtureRoot 'dummy.bin';Write-Bytes $dummy 'pinned'
$bootstrapFile=Join-Path $fixtureRoot 'bootstrap.ps1';Write-Bytes $bootstrapFile '# pinned'
$runAuthPath=Join-Path $fixtureRoot 'run-authorization.json'
$admissionPath=Join-Path $fixtureRoot 'run-admission.json'
$admissionSigPath=Join-Path $fixtureRoot 'run-admission.sig'
$receiptPath=Join-Path $fixtureRoot 'admit-receipt.json'
$receiptSigPath=Join-Path $fixtureRoot 'admit-receipt.sig'
Write-Bytes $receiptPath '{}';Write-Bytes $receiptSigPath 'AA=='
$tempRuntime=Join-Path $fixtureRoot 'temp-runtime';[IO.Directory]::CreateDirectory($tempRuntime)|Out-Null
$t0=[DateTimeOffset]::UtcNow
$t0=$t0.AddTicks(-($t0.Ticks % [TimeSpan]::TicksPerSecond))
$runExpires=Stamp $t0.AddSeconds(40);$transferExpires=Stamp $t0.AddSeconds(40)
Write-Bytes $runAuthPath (ConvertTo-OrderedMinifiedJson ([ordered]@{
  scopeCore=[ordered]@{expiresAt=$runExpires;transfer=[ordered]@{expiresAt=$transferExpires}}
}))

$script:AdmissionKeys=@(
  'schemaVersion','kind','id','authoritySessionId','monitorSessionId','w0RunId',
  'operatorExpectedConfigSha256','configSha256','prelaunchAssertionSha256',
  'postexecutionAttestationSha256','lock','authorizationInputExtension','currentState',
  'runAuthorization','receiver','authorizationChronology','sideEffectsStarted',
  'oneTimeAdmission','admitExecutionReceiptOutputs','enforcement',
  'admissionLifetimeSeconds','admissionExpiresAt','verdict')
$script:AdmitExecutionKeys=@(
  'schemaVersion','kind','id','runId','receiverNonce','authoritySessionId','monitorSessionId',
  'operatorExpectedConfigSha256','configSha256','runAdmission','receiptOutputs','lock',
  'admitHost','semanticValidator','oneTimeAdmissionConsumption','workerReady',
  'workerReadyCapability','productSideEffectsStarted','projectPackageSkillWriteCount',
  'authorizationEvidenceWritePolicy','bootstrapState','attestedAt','verdict')
$h1='1'*64;$h2='2'*64;$h3='3'*64;$h4='4'*64;$h5='5'*64;$h6='6'*64;$h7='7'*64
$runId='W0-RUN-TEST-0001';$receiverNonce='r'*32
$authoritySession='AUTHORITY-SESSION-0001';$monitorSession='MONITOR-SESSION-0001'
$admission=New-OrderedRecord $script:AdmissionKeys
$admission.schemaVersion='1.0.0';$admission.kind='w0-run-admission-v1'
$admission.id='W0-RUN-ADMISSION-TEST';$admission.authoritySessionId=$authoritySession
$admission.monitorSessionId=$monitorSession;$admission.w0RunId=$runId
$admission.operatorExpectedConfigSha256=$h1;$admission.configSha256=$h1
$admission.runAuthorization=[ordered]@{scopeCoreSha256=$h2}
$admission.receiver=[ordered]@{
  skillId='receiver-skill';skillVersion='1.0.0';skillPath='C:/receiver/SKILL.md';skillSha256=$h4
  receiverSkillTreeSha256=$h5;workerId='worker-1';requestedModel='model-a';resolvedModel='model-a'
  provider='provider';account='account';tool='tool';expectedLoadedProcessClosureSha256=$h6
  envelopeSha256=$h7}
$admission.authorizationChronology=[ordered]@{
  authorizedAt=Stamp $t0.AddSeconds(-11);admittedAt=Stamp $t0.AddSeconds(-10)
  authorizationExpiresAt=$runExpires}
$admission.sideEffectsStarted=$false
$admission.oneTimeAdmission=[ordered]@{
  registryAuthority='registry';registryId='registry-1';eventId='ADMISSION-EVENT-1'
  nonce='a'*32;tokenSha256=$h3;consumed=$false
  consumptionPolicy='authority-atomic-consume-after-admit-semantic-pass-before-suspended-worker-launch-v1'}
$admission.admissionLifetimeSeconds=[int64]50
$admission.admissionExpiresAt=Stamp $t0.AddSeconds(40)
$admission.verdict='ready-for-admit-semantic-pass-and-receipt'
Write-SignedRecord $admission $admissionPath $admissionSigPath
$context=[pscustomobject]@{Protected=@();Anchor=$anchor}
$admissionSigned=Read-VerifiedSignedJson $admissionPath $admissionSigPath $context `
  $script:AdmissionKeys 'signed run admission'

$script:ExpectedConfigSha256=$h1
$script:ConfigPath=$dummy;$script:PackagePath=$dummy;$script:ProjectRoot=$fixtureRoot
$script:LaunchChallengePath=$dummy;$script:PresentationPath=$dummy
$script:HumanChallengePath=$dummy;$script:TranscriptPath=$dummy;$script:StatementPath=$dummy
$script:CapturePath=$dummy;$script:CaptureProvenancePath=$dummy
$script:RunAuthorizationPath=$runAuthPath
$script:RunAdmissionAttestationPath=$admissionPath
$script:RunAdmissionSignaturePath=$admissionSigPath
$script:AdmitExecutionAttestationPath=$receiptPath
$script:AdmitExecutionSignaturePath=$receiptSigPath
$context=[pscustomobject]@{
  Protected=@();Anchor=$anchor;HostBinary=$dummy;BootstrapScript=$bootstrapFile
  Bootstrap=[ordered]@{hostFixedArgs=@('-NoLogo','-File');hostRuntimeRoots=@(
    [ordered]@{path='C:/runtime-host';treeSha256=$h1})}
  Runtime=[ordered]@{
    pythonExecutable=[ordered]@{sha256=$h2}
    validatorEntrypoint=[ordered]@{sha256=$h3}
    readOnlyLibraryRoots=@([ordered]@{path='C:/runtime-python';treeSha256=$h4})}
  Authority=[ordered]@{maxWorkerReadyLifetimeSeconds=[int64]60;maxClockSkewSeconds=[int64]5}
  ConfigPath=$dummy;Package=$dummy;Project=$fixtureRoot}
$challenge=[ordered]@{runId=$runId;receiverNonce=$receiverNonce;tempCopySetSha256=$h5}
$challengeContext=[pscustomobject]@{
  Value=$challenge;TempRoot=(ConvertTo-NormalizedPath $tempRuntime $true)}
$semanticValue=[ordered]@{
  pass=$true;errors=@();mode='run-authorization';authorizationId='W0-RUN-AUTH-TEST'
  admissionId=$admission.id;oneTimeTokenSha256=$h3}
$semanticResult=[pscustomobject]@{
  Value=$semanticValue;StartedAt=$t0.AddSeconds(-9);CompletedAt=$t0.AddSeconds(-8)}
$invocation=[ordered]@{Argv=@('C:/pinned/python.exe','validator.py');Environment=Get-ClosedEnvironment}
$fullRead=@();$fullIdentity=@()

$receipt=New-OrderedRecord $script:AdmitExecutionKeys
$receipt.schemaVersion='1.0.0';$receipt.kind='w0-runtime-admit-execution-v1'
$receipt.id='W0-RUNTIME-ADMIT-TEST';$receipt.runId=$runId;$receipt.receiverNonce=$receiverNonce
$receipt.authoritySessionId=$authoritySession;$receipt.monitorSessionId=$monitorSession
$receipt.operatorExpectedConfigSha256=$h1;$receipt.configSha256=$h1
$receipt.runAdmission=[ordered]@{
  id=$admission.id;path=$admissionSigned.Path;sha256=$admissionSigned.Sha256
  fileIdentity=$admissionSigned.FileIdentity;detachedSignaturePath=$admissionSigned.SignaturePath
  detachedSignatureSha256=$admissionSigned.SignatureSha256
  detachedSignatureFileIdentity=$admissionSigned.SignatureFileIdentity
  scopeCoreSha256=$h2;oneTimeTokenSha256=$h3}
$receipt.receiptOutputs=[ordered]@{
  attestationPath=(ConvertTo-NormalizedPath $receiptPath $false)
  detachedSignaturePath=(ConvertTo-NormalizedPath $receiptSigPath $false)}
$receipt.lock=[ordered]@{
  noGapFrom='prelaunch';through='bootstrap-pass-and-first-effect-release'
  enforcementSessionId=$monitorSession;enforcementActive=$true}
$hostClosure=@([ordered]@{path='C:/runtime-host';treeSha256=$h1})
$receipt.admitHost=[ordered]@{
  hostExecutableSha256=Get-Sha256File $dummy
  bootstrapScriptSha256=Get-Sha256File $bootstrapFile
  hostRuntimeClosureSha256=Get-CanonicalSha256 $hostClosure
  loadedClosureSha256=$h1;argvSha256=Get-JoinedSha256 (Get-AdmitHostArgv $context)
  cwdSha256=Get-Sha256Bytes ($script:Utf8.GetBytes((ConvertTo-NormalizedPath (Get-Location).Path $true)))
  envSha256=Get-EnvironmentSha256 (Get-ClosedEnvironment)
  loadedClosureMatchesConfig=$true;argvMatchesProtocol=$true;cwdMatches=$true;envClosed=$true
  monitorStartedBeforeProcess=$true}
$pythonClosure=@([ordered]@{path='C:/runtime-python';treeSha256=$h4})
$receipt.semanticValidator=[ordered]@{
  pythonExecutableSha256=$h2;validatorEntrypointSha256=$h3
  pythonRuntimeClosureSha256=Get-CanonicalSha256 $pythonClosure
  loadedClosureSha256=$h2;resolvedTempRoot=$challengeContext.TempRoot
  tempRootIdentity=Get-PathIdentity $challengeContext.TempRoot;tempCopySetSha256=$h5
  readInputSetSha256=Get-CanonicalSha256 $fullRead
  readInputIdentitySetSha256=Get-CanonicalSha256 $fullIdentity
  argvSha256=Get-JoinedSha256 $invocation.Argv
  cwdSha256=Get-Sha256Bytes ($script:Utf8.GetBytes($challengeContext.TempRoot))
  envSha256=Get-EnvironmentSha256 $invocation.Environment
  loadedClosureMatchesConfig=$true;tempCopySetMatches=$true;readInputClosureMatches=$true
  argvMatches=$true;cwdMatches=$true;envClosed=$true
  resultSha256=Get-CanonicalSha256 $semanticValue;result=$semanticValue
  startedAt=Stamp $t0.AddSeconds(-9);completedAt=Stamp $t0.AddSeconds(-8);exitCode=[int64]0}
$receipt.oneTimeAdmissionConsumption=[ordered]@{
  registryAuthority='registry';registryId='registry-1';admissionEventId='ADMISSION-EVENT-1'
  consumptionEventId='CONSUMPTION-EVENT-1';tokenSha256=$h3
  admissionExpiresAt=$admission.admissionExpiresAt;consumedAt=Stamp $t0.AddSeconds(-7)
  consumed=$true;atomic=$true;semanticPassCompletedBeforeConsumption=$true
  workerLaunchStartedAfterConsumption=$true}
$worker=[ordered]@{
  skillId='receiver-skill';skillVersion='1.0.0';skillPath='C:/receiver/SKILL.md';skillSha256=$h4
  receiverSkillTreeSha256=$h5;workerId='worker-1';requestedModel='model-a';resolvedModel='model-a'
  provider='provider';account='account';tool='tool';expectedLoadedProcessClosureSha256=$h6
  actualLoadedProcessClosureSha256=$h6;actualLoadedIdentitySha256='';envelopeSha256=$h7
  skillTreeMatchesAuthorization=$true;closureMatchesExpected=$true;identityMatchesAuthorization=$true
  launchMode='authority-suspended-pre-entry-under-scope-enforcement-v1'
  workerProcessIdentity='worker-process-1';launchedAt=Stamp $t0.AddSeconds(-6)
  observedAt=Stamp $t0.AddSeconds(-5);productEntryExecuted=$false}
$identityProjection=[ordered]@{
  skillSha256=$worker.skillSha256;receiverSkillTreeSha256=$worker.receiverSkillTreeSha256
  workerId=$worker.workerId;requestedModel=$worker.requestedModel;resolvedModel=$worker.resolvedModel
  provider=$worker.provider;account=$worker.account;tool=$worker.tool
  expectedLoadedProcessClosureSha256=$worker.expectedLoadedProcessClosureSha256
  actualLoadedProcessClosureSha256=$worker.actualLoadedProcessClosureSha256}
$worker.actualLoadedIdentitySha256=Get-CanonicalSha256 $identityProjection
$receipt.workerReady=$worker
$capability=[ordered]@{
  registryAuthority='registry';eventId='CAPABILITY-EVENT-1';nonce='c'*32;capabilitySha256=''
  issuedAt=Stamp $t0.AddSeconds(-4);lifetimeSeconds=[int64]30
  runAuthorizationExpiresAt=$runExpires;transferExpiresAt=$transferExpires
  admissionExpiresAt=$admission.admissionExpiresAt;effectiveExpiry=$runExpires
  expiresAt=Stamp $t0.AddSeconds(26);globalNonreuse=$true;consumed=$false
  consumptionPolicy='authority-atomic-consume-only-after-bootstrap-pass-before-one-scoped-first-effect-v1'}
$capabilityBytes=$script:Utf8.GetBytes(
  'W0-WORKER-READY-v1'+[char]0+$receipt.id+[char]0+$runId+[char]0+$h2+[char]0+
  $worker.workerProcessIdentity+[char]0+$capability.nonce)
$capability.capabilitySha256=Get-Sha256Bytes $capabilityBytes
$receipt.workerReadyCapability=$capability
$receipt.productSideEffectsStarted=$false;$receipt.projectPackageSkillWriteCount=[int64]0
$receipt.authorizationEvidenceWritePolicy=
  'only-predeclared-admit-receipt-and-detached-signature-after-semantic-pass-v1'
$receipt.bootstrapState=[ordered]@{
  semanticPassObserved=$true;bootstrapWaitingForReceipt=$true;bootstrapPassEmitted=$false
  workerSuspendedBeforeProductEntry=$true}
$receipt.attestedAt=Stamp $t0.AddSeconds(-3)
$receipt.verdict='ready-for-bootstrap-pass-and-one-scoped-first-effect'

Write-SignedRecord $receipt $receiptPath $receiptSigPath
$accepted=Assert-AdmitExecutionReceipt $context $challengeContext $admissionSigned `
  $semanticResult $invocation $fullRead $fullIdentity
if($null -eq $accepted -or $accepted.Value.id -cne $receipt.id){throw 'signed receipt not accepted'}

$validReceipt=ConvertTo-OrderedMinifiedJson $receipt
$tampered=$validReceipt.Replace('W0-RUNTIME-ADMIT-TEST','W0-RUNTIME-ADMIT-TESU')
[IO.File]::WriteAllBytes($receiptPath,$script:Utf8.GetBytes($tampered))
Assert-Rejected {Assert-AdmitExecutionReceipt $context $challengeContext $admissionSigned `
  $semanticResult $invocation $fullRead $fullIdentity} 'tampered detached signature'

$receipt.workerReadyCapability.eventId=$admission.oneTimeAdmission.eventId
Write-SignedRecord $receipt $receiptPath $receiptSigPath
Assert-Rejected {Assert-AdmitExecutionReceipt $context $challengeContext $admissionSigned `
  $semanticResult $invocation $fullRead $fullIdentity} 'signed replay'
$receipt.workerReadyCapability.eventId='CAPABILITY-EVENT-1'

$receipt.workerReadyCapability.nonce=('c'*31)+[char]0
Write-SignedRecord $receipt $receiptPath $receiptSigPath
Assert-Rejected {Assert-AdmitExecutionReceipt $context $challengeContext $admissionSigned `
  $semanticResult $invocation $fullRead $fullIdentity} 'signed NUL nonce'
$receipt.workerReadyCapability.nonce='c'*32

$receipt.workerReadyCapability.expiresAt=$receipt.attestedAt
Write-SignedRecord $receipt $receiptPath $receiptSigPath
Assert-Rejected {Assert-AdmitExecutionReceipt $context $challengeContext $admissionSigned `
  $semanticResult $invocation $fullRead $fullIdentity} 'signed expired capability'
'signed-admit-receipt-ok'
''')
            result = run_cli([
                pwsh, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", probe,
            ])
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("signed-admit-receipt-ok", result.stdout)

    def test_w0_frozen_paths_and_external_roots_are_machine_derived(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td).resolve()
            fixture = build_d5_fixture(root)
            errors: list[str] = []
            package = validate_d5.strict_json_file(
                fixture["package"], errors, "frozen fixture")
            self.assertIsNotNone(package)
            frozen = validate_d5._derive_w0_frozen_paths(
                root, fixture["package"], package, errors)
            self.assertEqual(errors, [])
            self.assertEqual(frozen, sorted(set(frozen)))
            self.assertIn(fixture["package"].relative_to(root).as_posix(), frozen)
            self.assertTrue(validate_d5._same_absolute_record_path(
                str(fixture["package"]).replace("/", "\\"), fixture["package"]))
            self.assertTrue(validate_d5._timestamp_at_or_before(
                "2026-08-20T00:00:00Z", "2026-08-20T00:00:01Z"))
            self.assertFalse(validate_d5._timestamp_at_or_before(
                "2026-08-20T00:00:02Z", "2026-08-20T00:00:01Z"))
            for key in ("b0", "b1", "b2"):
                self.assertIn(package["baselines"][key]["path"], frozen)

            overlap_errors: list[str] = []
            validate_d5._path_sets_are_disjoint(
                root, [frozen[0]], frozen, overlap_errors)
            self.assertTrue(any("overlaps immutable path" in error
                                for error in overlap_errors), overlap_errors)

            ancestor_errors: list[str] = []
            self.assertFalse(validate_d5.outside_roots(root.parent, (root,)))
            self.assertIsNone(validate_d5.external_path(
                str(root.parent), (root,), ancestor_errors, "operator root", file=False))
            self.assertTrue(any("outside project" in error or "must not contain" in error
                                for error in ancestor_errors), ancestor_errors)
            for invalid in ("../outside", "/absolute", "docs\\alias.md",
                            "docs/CON.txt", "docs/trailing."):
                self.assertFalse(validate_d5._run_auth_project_path(invalid), invalid)

            tree = root.parent / f"{root.name}-hardlink-tree"
            tree.mkdir()
            first = write(tree / "first.txt", "sealed\n")
            try:
                os.link(first, tree / "alias.txt")
            except OSError:
                pass
            else:
                hardlink_errors: list[str] = []
                self.assertIsNone(validate_d5._closed_tree_sha256(
                    tree, hardlink_errors, "hardlink tree"))
                self.assertTrue(any("hardlinked" in error or "identity" in error
                                    for error in hardlink_errors), hardlink_errors)

    def test_provenance_runner_rejects_empty_roots_and_loader_environment(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td).resolve()
            config_path = make_provenance_config(root)
            config = json.loads(config_path.read_text(encoding="utf-8"))
            runner = config["trustedRuntimeAdapters"][0]
            protected = (root, SCRIPT_DIR.parent.resolve())

            no_roots = json.loads(json.dumps(runner))
            no_roots["runtimeLibraryRoots"] = []
            errors: list[str] = []
            validate_d5.validate_runner_config(
                no_roots, protected, errors, "runner", signature=False)
            self.assertTrue(any("non-empty array" in error for error in errors), errors)

            bad_env = json.loads(json.dumps(runner))
            bad_env["allowedEnvNames"] = ["PATH"]
            errors = []
            validate_d5.validate_runner_config(
                bad_env, protected, errors, "runner", signature=False)
            self.assertTrue(any("loader/search-path" in error for error in errors), errors)

            errors = []
            validate_d5.validate_unique_library_roots(
                [{"_path": root.parent}, {"_path": root.parent}], errors,
                "duplicate roots")
            self.assertTrue(any("unique normalized root paths" in error
                                for error in errors), errors)

    def test_d5_closure_inventory_transition_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td).resolve()
            fixture = build_d5_fixture(root)
            source = root / "source"
            source.mkdir()
            progress = fixture["b1_snapshot_progress"]
            original = progress.read_text(encoding="utf-8")
            row = next(line for line in original.splitlines()
                       if line.startswith("| DVT-OPEN-001 |"))

            cases = [
                (original.replace(row + "\n", ""), "exactly once"),
                (original.replace(row, row + "\n" + row), "exactly once"),
                (original.replace("evidence/p0-result.json / ", "{TODO} / ", 1),
                 "actual closure evidence must be exact"),
                (original.replace(
                    hashlib.sha256(fixture["b0_snapshot_progress"].read_bytes()).hexdigest(),
                    "0" * 64), "inventory ID/B0 PROGRESS sha256 mismatch"),
                (original.replace("GDD D-12", "D-12"), "fully-qualified reference"),
                (original.replace("GDD D-12", "GDD D-99"), "resolve exactly once"),
                (original.replace("docs/preflight.txt / ", ""),
                 "affected canonical paths must exactly equal"),
            ]
            for changed, needle in cases:
                with self.subTest(needle=needle):
                    progress.write_text(changed, encoding="utf-8")
                    result = validate_fixture(root, fixture, source)
                    self.assertTrue(any(needle in error for error in result["errors"]),
                                    result["errors"])
            progress.write_text(original, encoding="utf-8")

            machine = fixture["b1_snapshot_machine"]
            machine.write_bytes(machine.read_bytes() + b"outside inventory")
            result = validate_fixture(root, fixture, source)
            self.assertTrue(any("outside the closure inventory" in error
                                for error in result["errors"]), result["errors"])

    def test_p0_start_scope_exactly_binds_verified_b0_inventory(self):
        for mutation, needle in (
                (lambda scope: scope["inventory"].update(sourceItemIds=[]),
                 "closed gate scope"),
                (lambda scope: scope.update(extraAuthority="product implementation"),
                 "closed gate scope"),
                (lambda scope: scope.update(additionalScope=True),
                 "closed gate scope")):
            with self.subTest(needle=needle), tempfile.TemporaryDirectory() as td:
                root = Path(td).resolve()
                fixture = build_d5_fixture(root)
                source = root / "source"
                source.mkdir()
                record = json.loads(
                    fixture["p0_start_record"].read_text(encoding="utf-8"))
                mutation(record["scope"])
                json_file(fixture["p0_start_record"], record)
                package = json.loads(fixture["package"].read_text(encoding="utf-8"))
                package["p0"]["startApprovalRecordSha256"] = sha_path(
                    fixture["p0_start_record"])
                json_file(fixture["package"], package)
                result = validate_fixture(root, fixture, source)
                self.assertTrue(any(needle in error for error in result["errors"]),
                                result["errors"])

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
            self.assertTrue(any("externally pinned Git" in error for error in errors), errors)

    def test_d5_rejects_unresolved_inventory_and_weak_decision_binding(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td).resolve()
            fixture = build_d5_fixture(root)
            source = root / "source"
            source.mkdir()

            machine = fixture["current_machine"]
            machine_before = machine.read_bytes()
            machine.write_bytes(machine_before + b"[OPEN blocking: yes]")
            result = validate_fixture(root, fixture, source)
            self.assertTrue(any("unresolved D5" in error
                                for error in result["errors"]), result["errors"])
            machine.write_bytes(machine_before)

            decisions = root / "DECISIONS.md"
            decisions_before = decisions.read_bytes()
            decisions.write_bytes(
                decisions_before.replace(b"human-direct", b"inspection-only"))
            result = validate_fixture(root, fixture, source)
            self.assertTrue(any("exact authorized sentinel block" in error
                                for error in result["errors"]), result["errors"])

    def test_d5_exact_log_blocks_and_first_wp_reject_content_smuggling(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td).resolve()
            fixture = build_d5_fixture(root)
            source = root / "source"
            source.mkdir()
            for rel in ("DECISIONS.md", "PROGRESS.md", "CHANGELOG.md"):
                path = root / rel
                original = path.read_bytes()
                path.write_bytes(original + b"\nextra product decision\n")
                result = validate_fixture(root, fixture, source)
                self.assertTrue(any(
                    f"{rel}: D5 transition must equal the exact authorized sentinel block" in error
                    for error in result["errors"]), result["errors"])
                path.write_bytes(original)

            wp = root / "docs" / "DVT_work_packages.md"
            original = wp.read_bytes()
            wp.write_bytes(original.replace(
                b"- Authorized by: D5-APP-001",
                b"- Authorized by: D5-APP-001 / extra authority"))
            result = validate_fixture(root, fixture, source)
            self.assertTrue(any("Authorized by must uniquely equal" in error
                                for error in result["errors"]), result["errors"])

    def test_state_aware_d5_scan_exempts_only_structured_history_closure_and_legends(self):
        sha = "a" * 64
        safe = (
            "## State tag legend\n\n- `[PROPOSAL]` means not approved.\n\n"
            "## Change History\n\n"
            f"| REC-001 | former assumption | Resolved | evidence/REC-001.json / {sha} | 2026-08-20T12:00:00+09:00 |\n\n"
            "## Completed\n\n### P0 closure records\n\n"
            "| Source item ID | Inventory | Decision | Evidence | Affected | Completed at |\n"
            "|---|---|---|---|---|---|\n"
            f"| SRC-1 | INV / {sha} | GDD D-12 | evidence/SRC-1.json / {sha} / pass | docs/a.md / {sha} | 2026-08-20T12:00:00+09:00 |\n\n"
            "```text\n[PROPOSAL]\n{{EXAMPLE}}\n```\n")
        self.assertEqual(state_readiness.scan_readiness_text(safe, ".md"), [])

        active = (
            "Historical note [PROPOSAL]\n"
            "## Change History\n| [ASSUMPTION] closed without record/timestamp |\n"
            "## Completed\n### P0 closure records\n"
            "| SRC-2 | INV | D-2 | [OPEN blocking: yes] | docs/a.md | yesterday |\n")
        issues = state_readiness.scan_readiness_text(active, ".md")
        self.assertEqual(
            [item["kind"] for item in issues], ["state", "state", "state"])
        completed_tag = (
            "## Completed\n\n### P0 closure records\n\n"
            f"| SRC-3 | INV / {sha} | GDD D-12 | [OPEN blocking: yes] evidence / "
            f"{sha} / pass | docs/a.md / {sha} | 2026-08-20T12:00:00+09:00 |\n")
        issues = state_readiness.scan_readiness_text(completed_tag, ".md")
        self.assertEqual([item["token"] for item in issues], ["[OPEN blocking: yes]"])
        nested_legend = (
            "## State tag legend\n\n"
            "- `[PROPOSAL]` means not approved.\n"
            "- WP-001 owner still has [ASSUMPTION] active.\n")
        issues = state_readiness.scan_readiness_text(nested_legend, ".md")
        self.assertEqual([item["token"] for item in issues], ["[ASSUMPTION]"])
        variants = state_readiness.scan_readiness_text(
            "[Proposal]\n[OPEN blocking:YES]\n{owner}\nDATA-{DOMAIN}-{NNN}\n", ".md")
        self.assertEqual(
            [(item["kind"], item["token"]) for item in variants],
            [("state", "[Proposal]"), ("state", "[OPEN blocking:YES]"),
             ("placeholder", "{owner}")])
        format_escape = state_readiness.scan_readiness_text(
            "{TODO}-{X}\nDATA-{DOMAIN}-{NNN}\n", ".md")
        self.assertEqual(
            [item["token"] for item in format_escape], ["{TODO}", "{X}"])

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
            result = validate_fixture(root, fixture, source)
            self.assertTrue(any("historical B1 formal Status" in error
                                for error in result["errors"]), result["errors"])
            old_index.write_bytes(old_bytes)

            current_index = root / "docs" / "DVT_docs_index.md"
            current_bytes = current_index.read_bytes()
            current_index.write_bytes(current_bytes.replace(
                b"D5-APP-001 approval", b"D5 approval"))
            result = validate_fixture(root, fixture, source)
            self.assertTrue(any("exactly one change-history row" in error
                                for error in result["errors"]), result["errors"])
            current_index.write_bytes(current_bytes)

            manifest_path = root / "docs" / "DVT_docs_manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["documents"] = [
                item for item in manifest["documents"]
                if item["path"] != "docs/schemas/DVT_machine.json"]
            json_file(manifest_path, manifest)
            result = validate_fixture(root, fixture, source)
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
                "--package", "docs/evidence/d5/missing.json",
                "--provenance-config", str((root / "missing-provenance.json").resolve()),
                "--installed-skill-root", str(SCRIPT_DIR.parent.resolve())])
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
