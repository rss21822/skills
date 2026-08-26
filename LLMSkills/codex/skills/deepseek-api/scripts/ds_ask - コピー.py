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
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.request

BASE_URL = os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com")
HOME_KEY = pathlib.Path.home() / ".deepseek" / "api_key"

# USD per 1M tokens, peak rates (off-peak is half; peak = 01:00-04:00 and
# 06:00-10:00 UTC). We quote peak so the estimate is a ceiling, never a surprise.
PRICING = {
    "deepseek-v4-pro":   {"hit": 0.044, "miss": 1.32, "out": 3.96},
    "deepseek-v4-flash": {"hit": 0.014, "miss": 0.44, "out": 1.32},
}

SKILL_DIR = pathlib.Path(__file__).resolve().parent.parent

# Files that are never useful as context and only burn input tokens.
SKIP_DIRS = {".git", "node_modules", "Packages", "ServerPackages", "DevPackages",
             "__pycache__", ".vscode", "out", "build", "dist", ".rojo"}
SKIP_EXT = {".rbxl", ".rbxlx", ".rbxm", ".rbxmx", ".png", ".jpg", ".jpeg", ".ogg",
            ".mp3", ".fbx", ".blend", ".zip", ".exe", ".dll", ".pdf"}


# ---------------------------------------------------------------- key handling

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
    paths = [HOME_KEY]
    root = repo_root()
    if root:
        paths.append(root / ".deepseek" / "api_key")
    paths.append(pathlib.Path.cwd() / ".deepseek" / "api_key")
    seen, out = set(), []
    for p in paths:
        s = str(p)
        if s not in seen:
            seen.add(s)
            out.append(p)
    return out


def find_key():
    """Return (key, source) or (None, None). Order is documented in SKILL.md."""
    env = _clean(os.environ.get("DEEPSEEK_API_KEY"))
    if env:
        return env, "env:DEEPSEEK_API_KEY"

    for path in key_candidates():
        if not path.exists():
            continue
        try:
            key = _clean(path.read_text(encoding="utf-8-sig", errors="replace"))
        except OSError:
            continue
        if key:
            return key, str(path)
    return None, None


def check():
    key, source = find_key()
    if not key:
        print("NOT FOUND: no DeepSeek API key available. Checked:")
        print("  env:DEEPSEEK_API_KEY")
        for p in key_candidates():
            print(f"  {p}")
        print("  -> See references/setup.md. Quickest fix on Windows:")
        print('     setx DEEPSEEK_API_KEY "sk-..."   then reopen the terminal.')
        return 1
    shape = "looks right" if key.startswith("sk-") else "WARNING: does not start with 'sk-'"
    print(f"found: source={source} len={len(key)} prefix={key[:6]}... ({shape})")
    req = urllib.request.Request(f"{BASE_URL}/models",
                                 headers={"Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        ids = [m.get("id") for m in data.get("data", [])]
        print(f"OK: authenticated. models available: {', '.join(ids) or '(none listed)'}")
        return 0
    except urllib.error.HTTPError as e:
        print(f"FAILED: HTTP {e.code} — {explain_status(e.code)}")
        return 1
    except Exception as e:  # network blocked, DNS, TLS...
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
    for pat in patterns:
        for path in sorted(globlib.glob(pat, recursive=True)):
            p = pathlib.Path(path)
            if not p.is_file() or path in seen:
                continue
            if set(p.parts) & SKIP_DIRS or p.suffix.lower() in SKIP_EXT:
                continue
            seen.add(path)
            try:
                text = p.read_text(encoding="utf-8", errors="replace")
            except OSError as e:
                skipped.append(f"{path} ({e.strerror})")
                continue
            size = len(text.encode("utf-8"))
            if total + size > max_bytes:
                skipped.append(f"{path} (would exceed --max-context-bytes)")
                continue
            total += size
            lang = {".lua": "lua", ".luau": "lua", ".py": "python",
                    ".json": "json", ".toml": "toml"}.get(p.suffix.lower(), "")
            chunks.append(f"--- FILE: {path} ---\n```{lang}\n{text}\n```")
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
            sys.exit(f"ERROR: {msg}")
        except Exception as e:
            if attempt <= retries:
                print(f"  [retry {attempt}/{retries}] {e.__class__.__name__}: {e} "
                      f"— sleeping {delay}s", file=sys.stderr)
                time.sleep(delay)
                delay *= 2
                continue
            sys.exit(f"ERROR: request failed ({e.__class__.__name__}: {e})")


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

    ap.add_argument("--model", default="deepseek-v4-pro")
    ap.add_argument("--system")
    ap.add_argument("--system-file")
    ap.add_argument("--system-preset", default="plain",
                    choices=["luau-impl", "luau-review", "design", "plain"])
    ap.add_argument("--no-thinking", action="store_true")
    ap.add_argument("--effort", default="high", choices=["low", "high", "max"])
    ap.add_argument("--temperature", type=float,
                    help="only takes effect with --no-thinking; ignored otherwise")
    ap.add_argument("--max-tokens", type=int, default=16000)
    ap.add_argument("--json", action="store_true", help="request JSON output mode")

    ap.add_argument("--out")
    ap.add_argument("--show-reasoning", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--retries", type=int, default=2)
    args = ap.parse_args()

    if args.check:
        sys.exit(check())

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
        if chunks:
            user_text = ("以下は対象プロジェクトの現行コードです。\n\n"
                         + "\n\n".join(chunks) + "\n\n---\n\n" + user_text)
            print(f"context: {len(chunks)} files, {total:,} bytes")
        else:
            print("context: no files matched — check the glob patterns", file=sys.stderr)
        for s in skipped:
            print(f"  skipped: {s}", file=sys.stderr)

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
        print("[dry-run] ---- prompt preview (first 2000 chars) ----")
        print(user_text[:2000])
        return

    key, source = find_key()
    if not key:
        sys.exit("ERROR: no API key. Run --check, then follow SKILL.md section 1.")

    print(f"-> {args.model} via {BASE_URL} (key from {source}), "
          f"~{approx_tokens:,} input tokens")
    started = time.time()
    data = post(payload, key, args.timeout, args.retries)
    elapsed = time.time() - started

    choice = (data.get("choices") or [{}])[0]
    message = choice.get("message") or {}
    content = message.get("content") or ""
    reasoning = message.get("reasoning_content") or ""
    finish = choice.get("finish_reason")

    print(f"<- {elapsed:.1f}s, finish_reason={finish}")
    if finish == "length":
        print("WARNING: output was truncated. Re-run with a larger --max-tokens.",
              file=sys.stderr)
    report_cost(args.model, data.get("usage") or {})

    out_path = pathlib.Path(args.out) if args.out else pathlib.Path(
        "out") / f"deepseek-{time.strftime('%Y%m%d-%H%M%S')}.md"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    body = content
    if args.show_reasoning and reasoning:
        body = f"<!-- reasoning_content -->\n{reasoning}\n\n<!-- answer -->\n{content}"
    out_path.write_text(body, encoding="utf-8")
    print(f"saved: {out_path} ({len(content)} chars)")

    lua_blocks = re.findall(r"```lua\n(.*?)```", content, re.S)
    if lua_blocks:
        print(f"note: response contains {len(lua_blocks)} Lua block(s). "
              f"Verify the Roblox APIs used before integrating.")


if __name__ == "__main__":
    main()
