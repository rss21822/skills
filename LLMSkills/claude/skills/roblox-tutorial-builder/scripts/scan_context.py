#!/usr/bin/env python3
"""Draft a tutorial context sheet for a Roblox project (roblox-tutorial-builder, step 1).

Greps the repository for what a tutorial has to fit: design docs, controls (key codes, bound actions, touch
buttons), the movement model, Places and teleports, persistence and the "played before" signal, environments,
UI vocabulary, the text language, existing onboarding and force flags, tests and build tools. Test files are kept
apart so they do not drown the game code.

The output is a STARTING POINT: open the files it points at before writing the context sheet -- a grep cannot
tell which binding is live, which doc is current or which flag is on in production.

Usage:
  python scan_context.py <repo-root> [--out context-draft.md] [--max-files 8000]
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import re
import sys
from pathlib import Path

SKIP_DIRS = {".git", ".claude", "worktrees", "node_modules", "Packages", "DevPackages", "ServerPackages", ".codex-tmp",
             "artifacts", "build", "dist", "out", "__pycache__", ".venv", "venv", "roblox_packages", "wally_packages",
             ".pesde", "vendor"}
CODE_EXT = {".luau", ".lua"}
DOC_EXT = {".md", ".txt"}
MAX_BYTES = 2_000_000
TOOL_FILES = ("rokit.toml", "aftman.toml", "foreman.toml", "wally.toml", "pesde.toml", "selene.toml", "stylua.toml",
              ".luaurc", "package.json", "Makefile", "justfile", "lune.yml")

DOC_NAME = re.compile(r"(gdd|design|spec|readme|decision|concept|plan|controls|onboard|tutorial|playtest|feedback|"
                      r"仕様|企画|設計)", re.I)
TEST_PATH = re.compile(r"(^|/)(tests?|specs?|__tests__|fixtures)(/|$)|(^|/)test_[^/]*$|[._-](spec|test)\.luau?$", re.I)
PATTERNS = {
    "keycodes": re.compile(r"Enum\.KeyCode\.(\w+)"),
    "input_types": re.compile(r"Enum\.UserInputType\.(\w+)"),
    "bind_action": re.compile(r"BindAction(?:AtPriority)?\(\s*([\"'][^\"']+[\"']|[\w.]+)"),
    "touch_button": re.compile(r"CreateTouchButton|SetTitle\(|TouchEnabled|TouchTapInWorld|Thumbstick|"
                               r"TouchMovementMode|ModalEnabled"),
    "input_events": re.compile(r"\b(InputBegan|InputEnded|InputChanged|JumpRequest|LastInputTypeChanged)\b"),
    "humanoid_move": re.compile(r"\b(MoveDirection|WalkSpeed|JumpPower|JumpHeight|Humanoid:Move\b|:Move\(|"
                                r"GetControls|ControlModule)"),
    "custom_move": re.compile(r"\b(VehicleSeat|LinearVelocity|VectorForce|AlignOrientation|AlignPosition|BodyVelocity|"
                              r"BodyGyro|AssemblyLinearVelocity|ApplyImpulse|PlatformStand|AutoRotate\s*=\s*false|"
                              r"ClickToMove|MoveToFinished)\b"),
    "camera": re.compile(r"\b(CameraType|CameraSubject|CameraMode|LockFirstPerson|MouseBehavior|"
                         r"DevComputerCameraMode|DevTouchCameraMode)\b"),
    "datastore": re.compile(r"Get(?:Ordered)?DataStore\(\s*([^)]*)\)"),
    "store_names": re.compile(r"\b(\w*(?:STORE|Store|DATASTORE|DataStore)\w*)\s*=\s*\"([^\"]{3,})\""),
    "profile_libs": re.compile(r"\b(ProfileService|ProfileStore|DataStore2|Suphi\w*|schemaVersion|SCHEMA_VERSION|"
                               r"DATA_VERSION|migrat\w+)\b"),
    "played_signals": re.compile(r"\b((?:matches|games|rounds|races|runs|levels|stages)(?:Played|Completed|Won|Cleared)|"
                                 r"total(?:Matches|Games|Wins|Runs|Plays)|tutorial\w*|hasPlayed|firstJoin\w*|"
                                 r"firstLogin\w*|onboard\w*|joinCount|visits|playCount|plays)\b"),
    "teleport": re.compile(r"\b(TeleportAsync|TeleportToPrivateServer|ReserveServer|ShouldReserveServer|"
                           r"TeleportPartyAsync|GetJoinData|SourcePlaceId|TeleportData|TeleportInitFailed)\b"),
    "env": re.compile(r"\b(GameId|PlaceId|PrivateServerId|IsStudio|STAGING|PRODUCTION|Staging|Production)\b"),
    "ui_theme": re.compile(r"\b(Font\.new|Enum\.Font\.\w+|FontFace|UICorner|UIStroke|UIGradient|Color3\.fromRGB|"
                           r"Color3\.fromHex)\b"),
    "localization": re.compile(r"\b(LocalizationTable|LocalizationService|AutoLocalize|GetTranslator|"
                               r"RootLocalizationTable)\b"),
    "remotes": re.compile(r"\b(RemoteEvent|RemoteFunction|UnreliableRemoteEvent)\b"),
    "onboarding": re.compile(r"(tutorial|onboard|coach|how.?to.?play|first.?time|ftue|newbie|beginner|"
                             r"チュートリアル|初回|はじめて)", re.I),
    "force_flags": re.compile(r"\b([A-Z0-9_]*(?:ALWAYS|FORCE|DEBUG|SKIP|EVERY)[A-Z0-9_]*|"
                              r"(?:force|always|debug|skip|every|show|test)[A-Z]\w*)\s*=\s*(true|false)\b"),
    "tests": re.compile(r"(@lune/|TestEZ|describe\(|expect\(|\bcheck\(|\bassertEq)"),
}
UI_TEXT = re.compile(r"(?:\.Text|\bText|\b(?:title|text|body|message|label|hint|caption|subtitle|heading|prompt|"
                     r"desc|description))\s*=\s*\"((?:[^\"\\\n]|\\.){2,})\"|SetTitle\(\s*[\w.]+\s*,\s*\""
                     r"((?:[^\"\\\n]|\\.){1,})\"", re.I)
BIG_ID = re.compile(r"\b(\w*(?:PLACE|Place|UNIVERSE|Universe|GAME|Game)\w*)\s*=\s*.*?\b(\d{6,})\b")
CJK = re.compile(r"[぀-ヿ一-鿿가-힯]")
LETTERS = re.compile(r"[A-Za-z぀-ヿ一-鿿가-힯]")


def walk(root: Path, limit: int):
    count = 0
    for folder, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        for name in sorted(files):
            count += 1
            if count > limit:
                return
            yield Path(folder) / name


def read(path: Path) -> str:
    try:
        if path.stat().st_size > MAX_BYTES:
            return ""
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def strip_comments(src: str) -> str:
    src = re.sub(r"--\[(=*)\[.*?\]\1\]", "", src, flags=re.S)
    return re.sub(r"--[^\n]*", "", src)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("root")
    ap.add_argument("--out")
    ap.add_argument("--max-files", type=int, default=8000)
    args = ap.parse_args()
    root = Path(args.root).resolve()
    if not root.is_dir():
        print(f"not a directory: {root}", file=sys.stderr)
        return 2

    docs, projects, places, tools = [], [], [], []
    hits = {name: collections.Counter() for name in PATTERNS}  # name -> Counter(file), game code only
    test_hits = collections.Counter()
    values = {name: collections.Counter() for name in ("keycodes", "input_types", "bind_action", "datastore",
                                                        "store_names", "played_signals", "force_flags")}
    ids = []
    ui_strings, ui_cjk = 0, 0
    ui_files, cjk_files = collections.Counter(), collections.Counter()
    code_files = test_files = 0

    for path in walk(root, args.max_files):
        rel = path.relative_to(root).as_posix()
        suffix = path.suffix.lower()
        depth = rel.count("/")
        if path.name in TOOL_FILES and depth <= 1 or rel.startswith(".github/workflows/"):
            tools.append(rel)
        if path.name.endswith(".project.json"):
            try:
                tree = json.loads(read(path)).get("tree", {})
                projects.append(f"{rel} (top: {', '.join(k for k in tree if not k.startswith('$'))})")
            except (ValueError, AttributeError):
                projects.append(rel)
        elif suffix in (".rbxl", ".rbxlx"):
            places.append(f"{rel} ({path.stat().st_size // 1024} KB)")
        elif suffix in DOC_EXT and DOC_NAME.search(path.name) and depth <= 3:
            first = next((line.strip("#> ").strip() for line in read(path).splitlines() if line.strip()), "")
            docs.append(f"{rel} — {first[:90]}")
        elif suffix in CODE_EXT:
            src = read(path)
            code = strip_comments(src)
            if TEST_PATH.search(rel):
                test_files += 1
                found = PATTERNS["tests"].findall(code)
                if found:
                    test_hits[rel] += len(found)
                continue
            code_files += 1
            for name, pattern in PATTERNS.items():
                if name == "tests":
                    continue
                found = pattern.findall(src + "\n" + rel if name == "onboarding" else code)
                if found:
                    hits[name][rel] += len(found)
                    if name in values:
                        for item in found:
                            values[name][item if isinstance(item, str) else " = ".join(item)] += 1
            for match in BIG_ID.finditer(code):
                ids.append(f"{rel}: {match.group(1)} = {match.group(2)}")
            for match in UI_TEXT.finditer(code):
                text = match.group(1) or match.group(2) or ""
                if LETTERS.search(text) and not re.fullmatch(r"[\w.:/%-]+", text):
                    ui_strings += 1
                    ui_files[rel] += 1
                    if CJK.search(text):
                        ui_cjk += 1
                        cjk_files[rel] += 1
    if code_files + test_files == 0:
        print("no .luau/.lua files found under the root", file=sys.stderr)

    out = []
    w = out.append
    w(f"# Tutorial context draft — {root.name}")
    w("")
    w(f"Scanned {code_files} game code files and {test_files} test files (skipped folders: "
      f"{', '.join(sorted(SKIP_DIRS))}). Every line below is a lead, not a fact: open the file, then fill the context "
      "sheet (references/context-inventory.md) from what the code really does.")

    def section(title, rows, empty="(nothing found)"):
        w("")
        w(f"## {title}")
        for row in rows or [empty]:
            w(f"- {row}")

    def top(counter, n=12):
        return [f"{name} ×{count}" for name, count in counter.most_common(n)]

    section("Design docs (read these first)", sorted(docs)[:30])
    section("Rojo projects / Place files", projects + places)
    section("Build / test tooling", sorted(tools))
    section("Controls: key codes used", top(values["keycodes"], 30))
    section("Controls: input types", top(values["input_types"], 15))
    section("Controls: bound actions (ContextActionService)", top(values["bind_action"], 20))
    section("Controls: files with input handling (open the top ones)",
            top(hits["input_events"] + hits["bind_action"] + hits["keycodes"]))
    section("Touch / mobile input", top(hits["touch_button"]))
    section("Movement: default Humanoid / PlayerModule", top(hits["humanoid_move"]))
    section("Movement: custom physics (vehicle / skating / flying / click-to-move?)", top(hits["custom_move"]))
    section("Camera", top(hits["camera"]))
    section("Persistence: DataStore calls", top(values["datastore"], 15))
    section("Persistence: store name constants", top(values["store_names"], 15))
    section("Persistence: profile libraries / schema versions", top(hits["profile_libs"]))
    section("'Played before' signal candidates (fields a profile may already keep)", top(values["played_signals"], 15))
    section("Places & teleports", top(hits["teleport"]))
    section("Place / universe id constants", ids[:20])
    section("Environment checks", top(hits["env"], 10))
    section("UI vocabulary (theme / style modules: open the top ones)", top(hits["ui_theme"], 12))
    if ui_strings:
        share = ui_cjk / ui_strings
        verdict = ("mostly CJK: the source language may be Japanese / Chinese / Korean"
                   if share > 0.5 else "mostly Latin script: the source language is probably English"
                   if share < 0.2 else "mixed: decide with the Owner which language is the source")
        lang = [f"{ui_cjk}/{ui_strings} UI text literals contain CJK ({share:.0%}) — {verdict}. Confirm from the docs, "
                "the LocalizationTable and the Creator Hub source language."]
    else:
        lang = ["no UI text literals found (text may live in a LocalizationTable or data files)"]
    lang += [f"CJK UI text in {name} ×{count}" for name, count in cjk_files.most_common(6)]
    section("Text language (player-facing text assignments only)", lang)
    section("Localization", top(hits["localization"]))
    section("Remotes (a new one needs server-side checks)", top(hits["remotes"], 10))
    section("Existing onboarding / tutorial code", top(hits["onboarding"], 15))
    section("Force / debug flags (an 'always show' flag left on shows the tutorial to everyone)",
            top(values["force_flags"], 15))
    section("Tests / harness", top(test_hits, 10))
    w("")
    w("## Still to find by reading (a grep cannot tell)")
    for line in ("the one thing new players fail at first (docs, playtest notes, analytics, the Owner)",
                 "which bindings are live on each device, rebindable, and how the HUD names them",
                 "the movement model the player actually uses (default walk vs custom) and the camera",
                 "how players arrive (direct join, friends, parties, teleports between Places, private servers)",
                 "the profile's 'played before' signal, its schema rules and how a new field is added",
                 "the UI components to reuse and the safe areas the HUD already keeps (top bar, thumbstick, jump)",
                 "how scripts reach the Places (Rojo build vs Studio-saved Places) and the test command"):
        w(f"- {line}")
    text = "\n".join(out) + "\n"
    if args.out:
        Path(args.out).write_text(text, encoding="utf-8")
        print(f"wrote {args.out}")
    else:
        sys.stdout.buffer.write(text.encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
