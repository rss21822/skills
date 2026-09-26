from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import build_context_bundle


class ContextBundleTests(unittest.TestCase):
    def test_builds_hash_attested_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "docs").mkdir()
            payload = "alpha\n日本語\n".encode()
            (root / "docs" / "a.md").write_bytes(payload)
            result = build_context_bundle.build_bundle(
                root,
                ["docs/a.md"],
                "out/context.md",
                20_000,
                list(build_context_bundle.DEFAULT_DENY),
            )
            bundle = (root / "out" / "context.md").read_bytes()
            sidecar = json.loads(
                (root / "out" / "context.md.attestation.json").read_text(
                    encoding="utf-8"
                )
            )
            self.assertIn(payload, bundle)
            self.assertEqual(result["bundleSha256"], hashlib.sha256(bundle).hexdigest())
            self.assertEqual(sidecar["manifest"]["files"][0]["path"], "docs/a.md")
            self.assertEqual(
                sidecar["manifest"]["files"][0]["sha256"],
                hashlib.sha256(payload).hexdigest(),
            )

    def test_rejects_denied_secret_path(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / ".env").write_text("TOKEN=nope", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "denied path"):
                build_context_bundle.build_bundle(
                    root,
                    [".env"],
                    "out/context.md",
                    20_000,
                    list(build_context_bundle.DEFAULT_DENY),
                )

    def test_rejects_traversal(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with self.assertRaisesRegex(ValueError, "traversal"):
                build_context_bundle.build_bundle(
                    root,
                    ["../outside.md"],
                    "out/context.md",
                    20_000,
                    list(build_context_bundle.DEFAULT_DENY),
                )

    def test_limit_is_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "a.md").write_text("x" * 100, encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "approved limit"):
                build_context_bundle.build_bundle(
                    root,
                    ["a.md"],
                    "out/context.md",
                    50,
                    list(build_context_bundle.DEFAULT_DENY),
                )
            self.assertFalse((root / "out" / "context.md").exists())

    def test_rejects_symlink_source(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "real.md").write_text("safe", encoding="utf-8")
            link = root / "link.md"
            try:
                link.symlink_to(root / "real.md")
            except OSError:
                self.skipTest("symlink creation is unavailable")
            with self.assertRaisesRegex(ValueError, "symlink"):
                build_context_bundle.build_bundle(
                    root,
                    ["link.md"],
                    "out/context.md",
                    20_000,
                    list(build_context_bundle.DEFAULT_DENY),
                )

    def test_rejects_non_utf8_source(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "binary.md").write_bytes(b"\xff\xfe")
            with self.assertRaisesRegex(ValueError, "UTF-8"):
                build_context_bundle.build_bundle(
                    root,
                    ["binary.md"],
                    "out/context.md",
                    20_000,
                    list(build_context_bundle.DEFAULT_DENY),
                )


if __name__ == "__main__":
    unittest.main()
