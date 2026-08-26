#!/usr/bin/env python3
"""DeepSeek API client for the deepseek-api skill (Claude Code / local).

Handles key resolution, context file collection, the request itself (with retries
and long-reasoning-safe timeouts), and cost reporting.

Run with --check first; it tells you whether a usable key is present before you
spend time assembling a prompt that would only 401.

Stdlib only, so it runs anywhere Python does — including Git Bash on Windows
without a virtualenv.
"""
import argparse
import glob as globlib
import hashlib
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.request

OFFICIAL_BASE_URL = "https://api.deepseek.com"
BASE_URL = os.environ.get("DEEPSEEK_BASE_URL", OFFICIAL_BASE_URL).rstrip("/")
HOME_KEY = pathlib.Path.home() / ".deepseek" / "api_key"
CLIENT_VERSION = "2.0.0"
SANDBOX_MODE = "text-only"
NETWORK_MODE = "deepseek-api-only"
AUTH_CHANNELS = ("env", "home-file", "repo-file", "cwd-file")

# USD per 1M tokens, peak rates (off-peak is half; peak = 01:00-04:00 and
# 06:00-10:00 UTC). We quote peak so the estimate is a ceiling, never a surprise.
PRICING = {
    "deepseek-v4-pro":   {"hit": 0.044, "miss": 1.32, "out": 3.96},
    "deepseek-v4-flash": {"hit": 0.014, "miss": 0.44, "out": 1.32},
}

SKILL_DIR = pathlib.Path(__file__).resolve().parent.parent

# Files that are never useful as context and only burn input tokens.
SKIP_DIRS = {".git", "node_modules", "Packages", "ServerPackages", "DevPackages",
             "__pycache__", ".vscode", "out", "build", "dist", ".rojo",
             ".deepseek", ".ssh", ".aws"}
SKIP_EXT = {".rbxl", ".rbxlx", ".rbxm", ".rbxmx", ".png", ".jpg", ".jpeg", ".ogg",
            ".mp3", ".fbx", ".blend", ".zip", ".exe", ".dll", ".pdf",
            ".pem", ".key", ".p12", ".pfx"}
SKIP_NAMES = {".env", ".env.local", ".env.production", "api_key",
              "credentials.json", "secrets.json"}


# ---------------------------------------------------------------- key handling


class RequestFailure(RuntimeError):
    """A request or response violated the fail-closed execution contract."""

def _clean(raw):
    """Strip BOM/whitespace/quotes. Editors love to add these and they cause 401s
    that look like a wrong key."""
    if raw is None:
        return None
    key = raw.replace("﻿", "").strip().strip('"').strip("'")
    return key or None


def repo_root(start=None):
    """Walk up looking for a .git directory so a project-local key works from
    any subdirectory, not just the repo root."""
    cur = (start or pathlib.Path.cwd()).resolve()
    for candidate in [cur, *cur.parents]:
        if (candidate / ".git").exists():
            return candidate
    return None


def key_candidates():
    candidates = [("home-file", HOME_KEY)]
    root = repo_root()
    if root:
        candidates.append(("repo-file", root / ".deepseek" / "api_key"))
    candidates.append(("cwd-file", pathlib.Path.cwd() / ".deepseek" / "api_key"))
    return candidates


def find_key(auth_channel):
    """Resolve only the explicitly selected channel; never silently fall back."""
    if auth_channel not in AUTH_CHANNELS:
        raise ValueError(f"unsupported auth channel: {auth_channel}")
    if auth_channel == "env":
        return _clean(os.environ.get("DEEPSEEK_API_KEY")), "env"

    paths = dict(key_candidates())
    path = paths.get(auth_channel)
    if path is None or not path.exists():
        return None, auth_channel
    try:
        key = _clean(path.read_text(encoding="utf-8-sig", errors="replace"))
    except OSError:
        return None, auth_channel
    return key, auth_channel


def write_json(path, payload):
    target = pathlib.Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
                      encoding="utf-8")


def base_attestation(args, status):
    return {
        "schema_version": 1,
        "status": status,
        "client": {"name": "ds_ask.py", "version": CLIENT_VERSION},
        "requested": {
            "model": args.model,
            "version": args.expect_client_version,
            "thinking": args.effort != "none",
            "effort": args.effort,
            "sandbox": args.sandbox,
            "network": args.network,
            "auth_channel": args.auth_channel,
            "max_tokens": args.max_tokens,
            "expected_artifact": list(args.expect_artifact),
        },
    }


def check(args):
    key, channel = find_key(args.auth_channel)
    if not key:
        write_json(args.attestation_out, {
            **base_attestation(args, "failed"),
            "error": "selected authentication channel is unavailable",
            "resolved": {"version": CLIENT_VERSION, "auth_channel": channel},
        })
        print(f"NOT FOUND: selected DeepSeek auth channel unavailable: {channel}")
        return 1
    print(f"credential: available via auth_channel={channel} (value and prefix suppressed)")
    req = urllib.request.Request(f"{BASE_URL}/models",
                                 headers={"Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        ids = [m.get("id") for m in data.get("data", [])]
        if args.model not in ids:
            write_json(args.attestation_out, {
                **base_attestation(args, "failed"),
                "error": "requested model not listed by provider",
                "resolved": {"version": CLIENT_VERSION, "auth_channel": channel,
                             "available_models": ids},
            })
            print(f"FAILED: requested model is not available: {args.model}")
            return 1
        write_json(args.attestation_out, {
            **base_attestation(args, "authenticated"),
            "resolved": {
                "model": args.model,
                "version": CLIENT_VERSION,
                "thinking": args.effort != "none",
                "effort": args.effort,
                "max_tokens": args.max_tokens,
                "sandbox": SANDBOX_MODE,
                "network": NETWORK_MODE,
                "endpoint": BASE_URL,
                "auth_channel": channel,
            },
        })
        print(f"OK: authenticated. models available: {', '.join(ids) or '(none listed)'}")
        return 0
    except urllib.error.HTTPError as e:
        write_json(args.attestation_out, {
            **base_attestation(args, "failed"),
            "error": f"HTTP {e.code}: {explain_status(e.code)}",
            "resolved": {"version": CLIENT_VERSION, "auth_channel": channel},
        })
        print(f"FAILED: HTTP {e.code} — {explain_status(e.code)}")
        return 1
    except Exception as e:  # network blocked, DNS, TLS...
        write_json(args.attestation_out, {
            **base_attestation(args, "failed"),
            "error": f"{e.__class__.__name__}: {e}",
            "resolved": {"version": CLIENT_VERSION, "auth_channel": channel},
        })
        print(f"FAILED: cannot reach {BASE_URL} ({e.__class__.__name__}: {e})")
        print("  Connection (not auth) failure: check proxy settings "
              "(HTTPS_PROXY) or corporate TLS inspection — see SKILL.md section 5.")
        return 1


def explain_status(code):
    return {
        400: "invalid request body",
        401: "auth failed — check for stray whitespace/BOM, or a stale env var "
             "(reopen the terminal after setx)",
        402: "insufficient balance — the DeepSeek account needs a top-up",
        422: "invalid parameters",
        429: "concurrency limit — reduce parallel requests rather than waiting",
        500: "server error — retryable",
        503: "server overloaded — retryable",
    }.get(code, "unexpected status")


# ------------------------------------------------------------ context building

def collect_files(patterns, max_bytes):
    """Gather source files into a single labelled block.

    Labelling each file with its path matters: without it the model invents
    file boundaries and returns edits you cannot map back onto the project.
    """
    seen, chunks, total, skipped = set(), [], 0, []
    cwd = pathlib.Path.cwd().resolve()
    for pat in patterns:
        matches = sorted(globlib.glob(pat, recursive=True))
        if not matches:
            skipped.append(f"{pat} (no files matched)")
            continue
        for path in matches:
            p = pathlib.Path(path)
            if not p.is_file():
                continue
            resolved = p.resolve()
            try:
                rel = resolved.relative_to(cwd).as_posix()
            except ValueError:
                skipped.append(f"{path} (outside project cwd)")
                continue
            if resolved in seen:
                continue
            if (set(p.parts) & SKIP_DIRS or p.suffix.lower() in SKIP_EXT or
                    p.name.lower() in SKIP_NAMES):
                skipped.append(f"{rel} (blocked file type or directory)")
                continue
            seen.add(resolved)
            try:
                raw = resolved.read_bytes()
            except OSError as e:
                skipped.append(f"{rel} ({e.strerror})")
                continue
            try:
                text = raw.decode("utf-8", errors="strict")
            except UnicodeDecodeError:
                skipped.append(f"{rel} (not strict UTF-8 text)")
                continue
            size = len(raw)
            if total + size > max_bytes:
                skipped.append(f"{rel} (would exceed --max-context-bytes)")
                continue
            total += size
            lang = {".lua": "lua", ".luau": "lua", ".py": "python",
                    ".json": "json", ".toml": "toml"}.get(p.suffix.lower(), "")
            digest = hashlib.sha256(raw).hexdigest()
            chunks.append(
                f"--- BEGIN {rel} ---\nsha256: {digest}\nbytes: {size}\n"
                f"```{lang}\n{text}\n```\n--- END {rel} ---"
            )
    return chunks, total, skipped


def load_system(args):
    if args.system_file:
        return pathlib.Path(args.system_file).read_text(encoding="utf-8")
    if args.system:
        return args.system
    preset = SKILL_DIR / "references" / "presets" / f"{args.system_preset}.md"
    if preset.exists():
        return preset.read_text(encoding="utf-8")
    return None


# ------------------------------------------------------------------ the request

def post(payload, key, timeout, retries):
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        f"{BASE_URL}/chat/completions", data=body, method="POST",
        headers={"Authorization": f"Bearer {key}",
                 "Content-Type": "application/json"})
    delay = 4
    for attempt in range(1, retries + 2):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", errors="replace")[:600]
            msg = f"HTTP {e.code}: {explain_status(e.code)}\n{detail}"
            # 429 is a concurrency signal, not a token-rate one; retrying a lone
            # request usually clears it, but hammering makes it worse.
            if e.code in (429, 500, 503) and attempt <= retries:
                print(f"  [retry {attempt}/{retries}] {msg.splitlines()[0]} "
                      f"— sleeping {delay}s", file=sys.stderr)
                time.sleep(delay)
                delay *= 2
                continue
            raise RequestFailure(msg)
        except Exception as e:
            if attempt <= retries:
                print(f"  [retry {attempt}/{retries}] {e.__class__.__name__}: {e} "
                      f"— sleeping {delay}s", file=sys.stderr)
                time.sleep(delay)
                delay *= 2
                continue
            raise RequestFailure(
                f"request failed ({e.__class__.__name__}: {e})"
            ) from e


def normalize_artifact_path(raw):
    value = str(raw).replace("\\", "/").strip()
    path = pathlib.PurePosixPath(value)
    if (not value or path.is_absolute() or value.startswith("/") or
            any(part in ("", ".", "..") for part in path.parts)):
        raise RequestFailure(f"invalid artifact path: {raw!r}")
    return path.as_posix()


def parse_artifact_envelope(content, expected_paths):
    """Validate the class-B envelope and return normalized structured fields."""
    try:
        envelope = json.loads(content)
    except json.JSONDecodeError as exc:
        raise RequestFailure(
            "expected artifact response is not valid JSON"
        ) from exc
    if not isinstance(envelope, dict):
        raise RequestFailure("artifact response must be a JSON object")
    if envelope.get("schema_version") != 1:
        raise RequestFailure("artifact response requires schema_version=1")

    artifacts = envelope.get("artifact")
    if not isinstance(artifacts, list):
        raise RequestFailure("artifact response requires an 'artifact' array")

    normalized = []
    seen = set()
    for item in artifacts:
        if not isinstance(item, dict):
            raise RequestFailure("each artifact must be an object")
        path = normalize_artifact_path(item.get("path", ""))
        body = item.get("content")
        if path in seen:
            raise RequestFailure(f"duplicate artifact path: {path}")
        if not isinstance(body, str) or not body.strip():
            raise RequestFailure(f"artifact content is empty: {path}")
        seen.add(path)
        normalized.append({"path": path, "content": body})

    expected = [normalize_artifact_path(p) for p in expected_paths]
    if len(expected) != len(set(expected)):
        raise RequestFailure("duplicate --expect-artifact path")
    if set(expected) != seen:
        missing = sorted(set(expected) - seen)
        extra = sorted(seen - set(expected))
        raise RequestFailure(
            f"artifact set mismatch: missing={missing}, extra={extra}"
        )

    report = envelope.get("report", "")
    text = envelope.get("text", "")
    if not isinstance(report, str) or not isinstance(text, str):
        raise RequestFailure("artifact response text/report must be strings")
    return {"text": text, "artifact": normalized, "report": report}


def validate_response(data, expected_paths):
    choices = data.get("choices") or []
    if not choices:
        raise RequestFailure("response contains no choices")
    choice = choices[0]
    finish = choice.get("finish_reason")
    if finish != "stop":
        raise RequestFailure(f"finish_reason must be 'stop', got {finish!r}")
    message = choice.get("message") or {}
    content = message.get("content")
    if not isinstance(content, str) or not content.strip():
        raise RequestFailure("response content is empty")
    resolved_model = data.get("model")
    if not isinstance(resolved_model, str) or not resolved_model.strip():
        raise RequestFailure("response does not attest the resolved model")

    structured = ({"text": content, "artifact": [], "report": ""}
                  if not expected_paths
                  else parse_artifact_envelope(content, expected_paths))
    return content, finish, resolved_model, structured


def report_cost(model, usage):
    p = PRICING.get(model)
    hit = usage.get("prompt_cache_hit_tokens", 0)
    miss = usage.get("prompt_cache_miss_tokens", usage.get("prompt_tokens", 0))
    out = usage.get("completion_tokens", 0)
    reasoning = (usage.get("completion_tokens_details") or {}).get("reasoning_tokens", 0)
    line = (f"tokens: prompt={usage.get('prompt_tokens', 0)} "
            f"(cache hit {hit} / miss {miss}), completion={out}")
    if reasoning:
        line += f" (reasoning {reasoning})"
    print(line)
    if p:
        cost = (hit * p["hit"] + miss * p["miss"] + out * p["out"]) / 1_000_000
        print(f"est. cost: ${cost:.4f} at peak rates "
              f"(off-peak is half — peak is 01:00-04:00 and 06:00-10:00 UTC)")


def main():
    ap = argparse.ArgumentParser(description="Send a request to the DeepSeek API.")
    ap.add_argument("--check", action="store_true", help="verify the API key and exit")

    ap.add_argument("--prompt")
    ap.add_argument("--prompt-file")
    ap.add_argument("--files", action="append", default=[], metavar="GLOB",
                    help="source files to include as context (repeatable)")
    ap.add_argument("--max-context-bytes", type=int, default=400_000)

    ap.add_argument("--model", required=True,
                    help="explicit model id; implicit defaults are forbidden")
    ap.add_argument("--system")
    ap.add_argument("--system-file")
    ap.add_argument("--system-preset", default="plain",
                    choices=["luau-impl", "luau-review", "design", "plain"])
    ap.add_argument("--no-thinking", action="store_true")
    ap.add_argument("--effort", required=True,
                    choices=["none", "low", "high", "max"])
    ap.add_argument("--temperature", type=float,
                    help="only takes effect with --no-thinking; ignored otherwise")
    ap.add_argument("--max-tokens", type=int, default=16000)
    ap.add_argument("--json", action="store_true", help="request JSON output mode")

    ap.add_argument("--out")
    ap.add_argument("--attestation-out", required=True,
                    help="write requested/resolved execution facts as JSON")
    ap.add_argument("--expect-artifact", action="append", default=[], metavar="PATH",
                    help="require an exact path in the JSON artifact envelope; repeatable")
    ap.add_argument("--expect-client-version", required=True)
    ap.add_argument("--sandbox", required=True, choices=[SANDBOX_MODE])
    ap.add_argument("--network", required=True, choices=[NETWORK_MODE])
    ap.add_argument("--auth-channel", required=True, choices=AUTH_CHANNELS)
    ap.add_argument("--show-reasoning", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--show-prompt-preview", action="store_true",
                    help="explicitly allow the dry-run to print prompt content")
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--retries", type=int, default=2)
    args = ap.parse_args()

    if args.expect_client_version != CLIENT_VERSION:
        ap.error(f"client version mismatch: required {args.expect_client_version}, "
                 f"installed {CLIENT_VERSION}")
    if BASE_URL != OFFICIAL_BASE_URL:
        ap.error(f"network contract requires {OFFICIAL_BASE_URL}; resolved {BASE_URL}")
    if args.no_thinking != (args.effort == "none"):
        ap.error("use --no-thinking together with --effort none; otherwise choose low/high/max")
    if args.expect_artifact and not args.json:
        ap.error("--expect-artifact requires --json")
    if args.expect_artifact and args.show_reasoning:
        ap.error("--show-reasoning is forbidden with --expect-artifact")
    if not args.check and not args.dry_run and not args.out:
        ap.error("--out is required for a live request")
    if args.out and pathlib.Path(args.out).resolve() == pathlib.Path(args.attestation_out).resolve():
        ap.error("--out and --attestation-out must be different files")

    if args.check:
        sys.exit(check(args))

    if args.prompt_file:
        user_text = pathlib.Path(args.prompt_file).read_text(encoding="utf-8")
    elif args.prompt:
        user_text = args.prompt
    else:
        if sys.stdin.isatty():
            ap.error("provide --prompt, --prompt-file, or pipe text on stdin")
        user_text = sys.stdin.read()

    if args.files:
        chunks, total, skipped = collect_files(args.files, args.max_context_bytes)
        if skipped or not chunks:
            reason = skipped or ["no readable files matched"]
            write_json(args.attestation_out, {
                **base_attestation(args, "failed"),
                "error": "context bundle is incomplete",
                "context_issues": reason,
                "resolved": {
                    "version": CLIENT_VERSION,
                    "sandbox": SANDBOX_MODE,
                    "network": NETWORK_MODE,
                    "endpoint": BASE_URL,
                    "auth_channel": None,
                },
            })
            sys.exit("ERROR: context bundle incomplete: " + "; ".join(reason))
        user_text = ("CONTEXT_BUNDLE_V1\n\n"
                     + "\n\n".join(chunks) + "\n\n--- REQUEST ---\n\n" + user_text)
        print(f"context: {len(chunks)} files, {total:,} bytes")

    messages = []
    system = load_system(args)
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": user_text})

    payload = {
        "model": args.model,
        "messages": messages,
        "max_tokens": args.max_tokens,
        "thinking": {"type": "disabled" if args.no_thinking else "enabled"},
    }
    if not args.no_thinking:
        payload["reasoning_effort"] = args.effort
    elif args.temperature is not None:
        # temperature is silently ignored in thinking mode, so only send it where
        # it actually does something.
        payload["temperature"] = args.temperature
    if args.json:
        payload["response_format"] = {"type": "json_object"}

    approx_tokens = len(user_text) // 3 + len(system or "") // 3
    if args.dry_run:
        p = PRICING.get(args.model, {})
        est_in = approx_tokens * p.get("miss", 0) / 1_000_000
        est_out = args.max_tokens * p.get("out", 0) / 1_000_000
        print(f"[dry-run] model={args.model} thinking="
              f"{'off' if args.no_thinking else args.effort}")
        print(f"[dry-run] approx input tokens: {approx_tokens:,} "
              f"(~${est_in:.4f}); max output {args.max_tokens:,} (~${est_out:.4f} worst case)")
        write_json(args.attestation_out, {
            **base_attestation(args, "dry-run"),
            "resolved": {
                "model": None,
                "version": CLIENT_VERSION,
                "thinking": args.effort != "none",
                "effort": args.effort,
                "max_tokens": args.max_tokens,
                "sandbox": SANDBOX_MODE,
                "network": NETWORK_MODE,
                "endpoint": BASE_URL,
                "auth_channel": args.auth_channel,
            },
            "approx_input_tokens": approx_tokens,
        })
        if args.show_prompt_preview:
            print("[dry-run] ---- prompt preview (first 2000 chars) ----")
            print(user_text[:2000])
        else:
            print("[dry-run] prompt preview suppressed; use --show-prompt-preview to opt in")
        return

    key, channel = find_key(args.auth_channel)
    if not key:
        write_json(args.attestation_out, {
            **base_attestation(args, "failed"),
            "error": "selected authentication channel is unavailable",
            "resolved": {"version": CLIENT_VERSION, "auth_channel": channel},
        })
        sys.exit("ERROR: selected API key channel unavailable. Run --check with the same explicit channel.")

    print(f"-> {args.model} via {BASE_URL} (auth_channel={channel}), "
          f"~{approx_tokens:,} input tokens")
    started = time.time()
    try:
        data = post(payload, key, args.timeout, args.retries)
        content, finish, resolved_model, structured = validate_response(
            data, args.expect_artifact
        )
    except RequestFailure as exc:
        write_json(args.attestation_out, {
            **base_attestation(args, "failed"),
            "error": str(exc),
            "resolved": {
                "version": CLIENT_VERSION,
                "auth_channel": channel,
                "thinking": args.effort != "none",
                "effort": args.effort,
                "max_tokens": args.max_tokens,
                "sandbox": SANDBOX_MODE,
                "network": NETWORK_MODE,
                "endpoint": BASE_URL,
            },
        })
        sys.exit(f"ERROR: {exc}")
    elapsed = time.time() - started

    choice = (data.get("choices") or [{}])[0]
    message = choice.get("message") or {}
    reasoning = message.get("reasoning_content") or ""

    print(f"<- {elapsed:.1f}s, finish_reason={finish}")
    report_cost(args.model, data.get("usage") or {})

    out_path = pathlib.Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    body = content
    if args.show_reasoning and reasoning:
        body = f"<!-- reasoning_content -->\n{reasoning}\n\n<!-- answer -->\n{content}"
    out_path.write_text(body, encoding="utf-8")
    print(f"saved: {out_path} ({len(content)} chars)")

    artifact_summary = [
        {
            "path": item["path"],
            "sha256": hashlib.sha256(item["content"].encode("utf-8")).hexdigest(),
            "bytes": len(item["content"].encode("utf-8")),
        }
        for item in structured["artifact"]
    ]
    usage = data.get("usage") or {}
    write_json(args.attestation_out, {
        **base_attestation(args, "completed"),
        "resolved": {
            "model": resolved_model,
            "version": CLIENT_VERSION,
            "thinking": args.effort != "none",
            "effort": args.effort,
            "max_tokens": args.max_tokens,
            "sandbox": SANDBOX_MODE,
            "network": NETWORK_MODE,
            "endpoint": BASE_URL,
            "auth_channel": channel,
        },
        "result": {
            "finish_reason": finish,
            "text_present": bool(structured["text"].strip()),
            "artifact": artifact_summary,
            "report_present": bool(structured["report"].strip()),
            "tokens": usage,
            "output": str(out_path),
        },
    })
    print(f"attestation: {args.attestation_out}")

    lua_blocks = re.findall(r"```lua\n(.*?)```", content, re.S)
    if lua_blocks:
        print(f"note: response contains {len(lua_blocks)} Lua block(s). "
              f"Verify the Roblox APIs used before integrating.")


if __name__ == "__main__":
    main()
