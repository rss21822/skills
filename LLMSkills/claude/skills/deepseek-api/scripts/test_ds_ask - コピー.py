import contextlib
import importlib.util
import io
import json
import os
import pathlib
import tempfile
import types
import unittest
from unittest import mock
import sys


SCRIPT = pathlib.Path(__file__).with_name("ds_ask.py")
SPEC = importlib.util.spec_from_file_location("ds_ask", SCRIPT)
ds_ask = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ds_ask)


def response(content="ok", finish="stop", model="deepseek-v4-pro"):
    return {
        "model": model,
        "choices": [{
            "finish_reason": finish,
            "message": {"content": content},
        }],
        "usage": {"prompt_tokens": 1, "completion_tokens": 1},
    }


class FakeHttpResponse:
    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self):
        return json.dumps({"data": [{"id": "deepseek-v4-pro"}]}).encode()


class DeepSeekContractTests(unittest.TestCase):
    def test_finish_reason_is_fail_closed(self):
        with self.assertRaisesRegex(ds_ask.RequestFailure, "finish_reason"):
            ds_ask.validate_response(response(finish="length"), [])

    def test_empty_output_is_fail_closed(self):
        with self.assertRaisesRegex(ds_ask.RequestFailure, "empty"):
            ds_ask.validate_response(response(content="  "), [])

    def test_missing_resolved_model_is_fail_closed(self):
        payload = response()
        payload.pop("model")
        with self.assertRaisesRegex(ds_ask.RequestFailure, "resolved model"):
            ds_ask.validate_response(payload, [])

    def test_expected_artifact_set_must_match_exactly(self):
        envelope = json.dumps({
            "schema_version": 1,
            "artifact": [{"path": "docs/a.md", "content": "A"}],
            "report": "done",
            "text": "",
        })
        with self.assertRaisesRegex(ds_ask.RequestFailure, "mismatch"):
            ds_ask.validate_response(response(content=envelope), ["docs/b.md"])

    def test_expected_artifact_success_returns_separate_fields(self):
        envelope = json.dumps({
            "schema_version": 1,
            "artifact": [{"path": "docs/a.md", "content": "A"}],
            "report": "done",
            "text": "note",
        })
        content, finish, model, structured = ds_ask.validate_response(
            response(content=envelope), ["docs/a.md"]
        )
        self.assertEqual(content, envelope)
        self.assertEqual(finish, "stop")
        self.assertEqual(model, "deepseek-v4-pro")
        self.assertEqual(structured["artifact"][0]["content"], "A")
        self.assertEqual(structured["report"], "done")

    def test_artifact_schema_version_is_required(self):
        envelope = json.dumps({
            "artifact": [{"path": "docs/a.md", "content": "A"}],
            "report": "done",
            "text": "",
        })
        with self.assertRaisesRegex(ds_ask.RequestFailure, "schema_version"):
            ds_ask.validate_response(response(content=envelope), ["docs/a.md"])

    def test_check_never_prints_key_value_or_prefix(self):
        with tempfile.TemporaryDirectory() as td:
            attestation = pathlib.Path(td) / "attestation.json"
            args = types.SimpleNamespace(
                auth_channel="env",
                attestation_out=str(attestation),
                model="deepseek-v4-pro",
                expect_client_version=ds_ask.CLIENT_VERSION,
                effort="high",
                sandbox="text-only",
                network="deepseek-api-only",
                max_tokens=16,
                expect_artifact=[],
            )
            secret = "sk-super-secret-value"
            output = io.StringIO()
            with mock.patch.dict(os.environ, {"DEEPSEEK_API_KEY": secret}), \
                    mock.patch.object(ds_ask.urllib.request, "urlopen",
                                      return_value=FakeHttpResponse()), \
                    contextlib.redirect_stdout(output):
                self.assertEqual(ds_ask.check(args), 0)
            rendered = output.getvalue()
            self.assertNotIn(secret, rendered)
            self.assertNotIn(secret[:6], rendered)
            saved = attestation.read_text(encoding="utf-8")
            self.assertNotIn(secret, saved)
            self.assertNotIn(secret[:6], saved)

    def test_main_artifact_mismatch_exits_nonzero_without_output(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            output = root / "raw.json"
            attestation = root / "attestation.json"
            envelope = json.dumps({
                "schema_version": 1,
                "artifact": [{"path": "docs/extra.md", "content": "X"}],
                "report": "done",
                "text": "",
            })
            argv = [
                str(SCRIPT),
                "--prompt", "write it",
                "--model", "deepseek-v4-pro",
                "--effort", "high",
                "--max-tokens", "16",
                "--json",
                "--expect-artifact", "docs/wanted.md",
                "--expect-client-version", ds_ask.CLIENT_VERSION,
                "--sandbox", "text-only",
                "--network", "deepseek-api-only",
                "--auth-channel", "env",
                "--out", str(output),
                "--attestation-out", str(attestation),
            ]
            with mock.patch.object(sys, "argv", argv), \
                    mock.patch.object(ds_ask, "find_key",
                                      return_value=("sk-test", "env")), \
                    mock.patch.object(ds_ask, "post",
                                      return_value=response(content=envelope)), \
                    contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    ds_ask.main()
            self.assertNotEqual(raised.exception.code, 0)
            self.assertFalse(output.exists())
            saved = json.loads(attestation.read_text(encoding="utf-8"))
            self.assertEqual(saved["status"], "failed")
            self.assertIn("mismatch", saved["error"])

    def test_context_bundle_is_inline_hash_labelled_and_project_scoped(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            source = root / "docs" / "source.md"
            source.parent.mkdir()
            source.write_text("source body", encoding="utf-8")
            previous = pathlib.Path.cwd()
            try:
                os.chdir(root)
                chunks, total, issues = ds_ask.collect_files(
                    ["docs/source.md"], 1000
                )
            finally:
                os.chdir(previous)
            self.assertEqual(issues, [])
            self.assertEqual(total, len("source body".encode()))
            self.assertIn("BEGIN docs/source.md", chunks[0])
            self.assertIn("sha256:", chunks[0])
            self.assertIn("source body", chunks[0])

    def test_secret_context_file_is_blocked(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            secret = root / ".env"
            secret.write_text("TOKEN=secret", encoding="utf-8")
            previous = pathlib.Path.cwd()
            try:
                os.chdir(root)
                chunks, _total, issues = ds_ask.collect_files([".env"], 1000)
            finally:
                os.chdir(previous)
            self.assertEqual(chunks, [])
            self.assertTrue(any("blocked" in issue for issue in issues))

    def test_non_utf8_context_is_fail_closed(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            source = root / "bad.md"
            source.write_bytes(b"\xff\xfe")
            previous = pathlib.Path.cwd()
            try:
                os.chdir(root)
                chunks, _total, issues = ds_ask.collect_files(["bad.md"], 1000)
            finally:
                os.chdir(previous)
            self.assertEqual(chunks, [])
            self.assertTrue(any("UTF-8" in issue for issue in issues))


if __name__ == "__main__":
    unittest.main()
