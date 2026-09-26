#!/usr/bin/env python3
"""Grade roblox-motif-ui eval runs.

  python grade.py <iteration-dir> [--original <fixture-project>]

For every <eval>/<config>/outputs/obby-rush: runs the contract test, compiles all Luau, runs the runtime
probe (grade_probe.luau) and scores objective assertions. Writes grading.json next to outputs/.
"""
import colorsys
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

LUNE = r"C:\Users\ryufu\.rokit\tool-storage\lune-org\lune\0.10.5\lune.exe"
HERE = Path(__file__).resolve().parent
ROBLOX_FAMILIES = {
    "AccanthisADFStd", "AmaticSC", "Arial", "Arimo", "Balthazar", "Bangers", "BuilderSans", "ComicNeueAngular", "Creepster",
    "DenkOne", "Fondamento", "FredokaOne", "GothamSSm", "GrenzeGotisch", "Guru", "HighwayGothic", "Inconsolata", "IndieFlower",
    "JosefinSans", "Jura", "Kalam", "LegacyArial", "LuckiestGuy", "Merriweather", "Michroma", "Montserrat", "Nunito", "Oswald",
    "PatrickHand", "PermanentMarker", "PressStart2P", "Roboto", "RobotoCondensed", "RobotoMono", "RomanAntique", "Sarpanch",
    "SourceSansPro", "SpecialElite", "TitilliumWeb", "Ubuntu", "Zekton"}
DISPLAY_ONLY = {"LuckiestGuy", "Bangers", "Creepster", "PermanentMarker", "AmaticSC", "PressStart2P", "GrenzeGotisch",
                "Fondamento", "Michroma", "Sarpanch", "Zekton", "SpecialElite"}
BOLD = {"SemiBold", "Bold", "ExtraBold", "Heavy"}
CJK = re.compile(r"[\u3040-\u30ff\u3400-\u9fff\uff00-\uffef]")


def rel_lum(c):
    def ch(v):
        v = v / 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * ch(c[0]) + 0.7152 * ch(c[1]) + 0.0722 * ch(c[2])


def contrast(a, b):
    la, lb = sorted((rel_lum(a), rel_lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def hls(c):
    h, l, s = colorsys.rgb_to_hls(*(v / 255 for v in c))
    return h * 360, l, s


def is_navy(c):
    h, l, s = hls(c)
    return 205 <= h <= 250 and l < 0.34 and 0.15 <= s < 0.85  # near-neutral blacks are not navy


def run(cmd, cwd=None, timeout=180):
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except Exception as exc:  # noqa: BLE001
        return 99, str(exc)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest() if Path(path).exists() else None


def emoji_only(text):
    t = text.strip()
    if not t or CJK.search(t):
        return False
    pictograph = any(ord(ch) >= 0x1F000 for ch in t) or "\ufe0f" in t  # colour emoji, not text symbols like a star
    return pictograph and all(ord(ch) > 0x2000 or ch in " \ufe0f" for ch in t)


def font_family(font):
    if not font:
        return None
    fam = font.get("family")
    if fam and fam.startswith("enum:"):
        return None  # Font.fromEnum(Enum.Font.X): a built-in, always real
    if fam:
        m = re.search(r"families/(.+?)\.json", fam)
        return m.group(1) if m else fam
    return None


def is_bold(font):
    if not font:
        return False
    fam = font.get("family") or ""
    if fam.startswith("enum:"):
        return any(k in fam for k in ("Bold", "Black", "Heavy", "Semibold"))
    if fam:
        return (font.get("weight") or "Regular") in BOLD
    enum = font.get("enum") or ""
    return any(k in enum for k in ("Bold", "Black", "Heavy", "Semibold")) or enum in ("FredokaOne", "LuckiestGuy", "Bangers", "DenkOne")


def grade_run(run_dir, original):
    run_dir = run_dir.resolve()
    outputs = run_dir / "outputs"
    project = outputs / "obby-rush"
    exp = []
    meta_path = run_dir.parent.parent / "eval_metadata.json"
    profile = (json.loads(meta_path.read_text(encoding="utf-8")).get("profile") if meta_path.exists() else None) or {"palette": "rich"}

    def add(text, passed, evidence):
        exp.append({"text": text, "passed": bool(passed), "evidence": evidence})

    if not project.exists():
        add("modified project exists at outputs/obby-rush", False, "missing")
        return exp
    # 1. contract test unchanged and passing
    unchanged = all(sha(project / "tests" / f) == sha(original / "tests" / f) for f in ("test_main_menu.luau", "mock.luau"))
    code, out = run([LUNE, "run", "tests/test_main_menu.luau"], cwd=project)
    last = [line for line in out.splitlines() if "contract" in line][-1:] or out.splitlines()[-1:]
    add("Contract test (names, callbacks, pages, 48px targets) passes with the test files unmodified",
        code == 0 and unchanged, f"exit {code}, tests unchanged={unchanged}; {' '.join(last)[:200]}")
    # 2. compile
    files = [str(p) for p in (project / "src").rglob("*.luau")]
    code, out = run([LUNE, "run", str(HERE / "compile_all.luau")] + files, cwd=project)
    bad = [line for line in out.splitlines() if line.startswith("FAIL")]
    add("Every Luau file under src compiles", code == 0 and not bad, f"{len(files)} files; exit {code}; {'; '.join(bad)[:300] or ('all OK' if code == 0 else out[-200:])}")
    # 3. runtime probe
    probe_path = run_dir / "probe.json"
    code, out = run([LUNE, "run", str(HERE / "grade_probe.luau"), str(project), str(probe_path)])
    probe = json.loads(probe_path.read_text(encoding="utf-8")) if probe_path.exists() else {"ok": False, "error": out}
    if not probe.get("ok"):
        add("Menu builds in the runtime probe", False, probe.get("error", out)[:300])
        return exp
    objs = [dict(o, page=name) for name, page in probe["pages"].items() for o in page]
    by_path_page = {name: {o["path"]: o for o in page} for name, page in probe["pages"].items()}
    # dedupe by path+page-agnostic
    seen, uniq = set(), []
    for o in objs:
        key = (o["path"], o.get("text"))
        if key not in seen:
            seen.add(key)
            uniq.append(o)
    by_path = {o["path"]: o for o in uniq}

    page_objs = {}
    for name, page in probe["pages"].items():
        page_objs[name] = page

    def fill_of(o):
        c = o["bg"]
        if o.get("tint"):
            c = [round(c[i] * o["tint"][i]) for i in range(3)]
        return c

    def effective_bg(o, page):
        """Colour behind `o`'s glyphs: its own opaque fill, else the stack of fills painted before it under
        its centre, alpha-composited bottom-up (semi-transparent plates over dark doors count). Objects inside
        a UIListLayout/UIGridLayout have unknown rects, so they probe at the centre of their layout container."""
        if o.get("bg") and o.get("bgT", 0) < 0.5:
            return fill_of(o)  # a text object's own fill sits directly behind its glyphs
        paths = by_path_page[page]
        anchor = o
        if o.get("laidOut"):
            parts = o["path"].split(".")
            for i in range(len(parts) - 1, 0, -1):
                cand = paths.get(".".join(parts[:i]))
                if cand and not cand.get("laidOut"):
                    anchor = cand
                    break
        x, y, w, h = anchor["rect"]
        cx, cy = x + w / 2, y + h / 2

        def paint_key(obj_path):
            node = paths.get(obj_path)
            return (1 if node.get("z") is None else node["z"], node["order"]) if node else (1, 0)

        def below(c):
            """Sibling ZIndex rule: at the first differing ancestor, lower (ZIndex, order) paints first."""
            if o["path"].startswith(c["path"] + "."):
                return True
            a_parts, b_parts = c["path"].split("."), o["path"].split(".")
            i = 0
            while i < min(len(a_parts), len(b_parts)) and a_parts[i] == b_parts[i]:
                i += 1
            if i >= len(a_parts) or i >= len(b_parts):
                return False
            return paint_key(".".join(a_parts[:i + 1])) < paint_key(".".join(b_parts[:i + 1]))

        def rank(c):
            return tuple(paint_key(".".join(c["path"].split(".")[:k + 1])) for k in range(len(c["path"].split("."))))

        stack = []
        for c in page_objs[page]:
            if c is o or c["path"].startswith(o["path"] + ".") or not below(c):
                continue
            if c.get("laidOut") and not o["path"].startswith(c["path"] + "."):
                continue
            if not c.get("bg") or c.get("bgT", 0) >= 0.95 or c["class"] == "ViewportFrame":
                continue
            rx, ry, rw, rh = c["rect"]
            if (rx <= cx <= rx + rw and ry <= cy <= ry + rh) or o["path"].startswith(c["path"] + "."):
                stack.append(c)
        stack.sort(key=rank)
        base = None
        for c in stack:
            alpha = 1 - c.get("bgT", 0)
            col = fill_of(c)
            base = col if base is None or alpha >= 0.999 else [round(col[i] * alpha + base[i] * (1 - alpha)) for i in range(3)]
        return base

    def tinted(o):
        c = o["bg"]
        return [round(c[i] * o["tint"][i]) for i in range(3)] if o.get("tint") else c

    fills = [(tinted(o), max(o["abs"][0], 0) * max(o["abs"][1], 0)) for o in uniq
             if o.get("bg") and o.get("bgT", 0) < 0.5 and o["class"] not in ("ViewportFrame",)]
    total = sum(a for _, a in fills) or 1
    navy_area = sum(a for c, a in fills if is_navy(c))
    navy_colours = sorted({"#%02X%02X%02X" % tuple(c) for c, _ in fills if is_navy(c)})
    if not profile.get("navyOk"):
        add("No generic navy/slate fills: navy share of visible filled area < 5%",
            navy_area / total < 0.05, f"navy share {navy_area / total:.1%}; navy colours {navy_colours[:6]}")
    elif profile.get("navyRequired"):
        add("Navy is the posted motif and is kept: navy fills cover at least 10% of the filled area",
            navy_area / total >= 0.10, f"navy share {navy_area / total:.1%}; navy colours {navy_colours[:6]}")
    # 4. variety
    glow_fills = [(tinted(o), max(o["abs"][0], 0) * max(o["abs"][1], 0) * (1 - o.get("bgT", 0))) for o in uniq
                  if o.get("bg") and o.get("bgT", 0) < 0.85 and o["class"] != "ViewportFrame"]
    buckets = {}
    for c, a in glow_fills:
        h, l, s = hls(c)
        if s > 0.35 and 0.25 < l < 0.85:
            buckets[int(h // 30)] = buckets.get(int(h // 30), 0) + a
    strong = sorted(k * 30 for k, a in buckets.items() if a / total > 0.003)
    palette = profile.get("palette", "rich")
    if palette == "rich":
        add("Palette variety: at least 4 distinct saturated hue families (30 deg bins) in visible fills",
            len(strong) >= 4, f"hue bins {strong}")
    elif palette == "restrained":
        add("Restrained palette for an elegant motif: at most 3 saturated hue families (30 deg bins)",
            len(strong) <= 3, f"hue bins {strong}")
    elif palette == "only-red":
        extra = [b for b in strong if b not in (0, 330)]
        add("Only the posted colours: no saturated hue family besides vermilion/red (ink, paper and seal only)",
            not extra, f"hue bins {strong}; outside red {extra}")

    def hue_present(lo, hi):
        area = 0
        for c, a in glow_fills:
            h, l, s_ = hls(c)
            if s_ > 0.35 and 0.2 < l < 0.85 and (lo <= h < hi if lo < hi else (h >= lo or h < hi)):
                area += a
        return area / total
    ranges = {"red": (340, 20), "amber": (20, 55), "green": (75, 170)}
    for name in profile.get("hues", []):
        share = hue_present(*ranges[name])
        add(f"Motif colour from the prompt is present: {name} fills (>0.3% of filled area)", share > 0.003, f"{name} share {share:.2%}")
    # 5. fonts exist
    texts = [o for o in uniq if o.get("text") and (o.get("textT") or 0) < 0.9]
    families = sorted({font_family(o.get("font")) for o in texts if font_family(o.get("font"))})
    missing = [f for f in families if f not in ROBLOX_FAMILIES]
    add("Every FontFace family used is a real Roblox font family", not missing, f"families {families}; missing {missing}")
    # 6. bold CJK
    cjk = [o for o in texts if CJK.search(o["text"])]
    thin = [f"{o['path']}={o['text'][:12]}" for o in cjk if not is_bold(o.get("font"))]
    add("Japanese text requests a bold (SemiBold+) weight so the CJK fallback does not render thin",
        not thin, f"{len(cjk)} Japanese texts; thin: {thin[:5]}")
    # 7. no latin-only display on CJK
    wrong = [f"{o['path']}={font_family(o.get('font'))}" for o in cjk if font_family(o.get("font")) in DISPLAY_ONLY]
    add("No Latin-only decorative display font is applied to Japanese text", not wrong, f"{wrong[:5] or 'none'}")
    # 8. contrast
    low = []
    checked = 0
    for o in texts:
        bg = effective_bg(o, o["page"])
        if not bg or not o.get("textColor") or emoji_only(o["text"]):
            continue
        if not re.search(r"[A-Za-z0-9぀-ヿ㐀-鿿]", o["text"]):
            continue  # decorative symbols (stars, sparkles) carry no information
        if "shadow" in o["name"].lower():
            continue  # a duplicate text layer drawn behind the real one as a drop shadow
        checked += 1
        glyph = o["textColor"]
        if o.get("tint"):  # a UIGradient on a text object multiplies the glyph colour too
            glyph = [round(glyph[i] * o["tint"][i]) for i in range(3)]
        best = contrast(glyph, bg)
        for s in o.get("strokes", []):
            if s.get("mode") in ("Contextual", "default") and (s.get("transparency") or 0) < 0.5 and s.get("color") and (s.get("thickness") or 0) >= 1:
                best = max(best, min(contrast(s["color"], bg), 21) if contrast(glyph, s["color"]) >= 3 else best)
        if best < 3:
            low.append(f"{o['path']} {best:.1f}:1")
    add("Every visible text reaches 3:1 against its fill (glyph or its outline)", not low, f"{checked} texts checked; low: {low[:5]}")
    # 9. emoji boxes
    small = []
    for o in texts:
        if emoji_only(o["text"]) and o.get("size") and o["size"][2] == 0 and not o.get("textScaled"):
            if o["size"][3] < 1.4 * (o.get("textSize") or 14):
                small.append(f"{o['path']} {o['size'][3]}px@{o.get('textSize')}pt")
    add("Emoji-only labels get a box at least 1.4x their TextSize tall", not small, f"{small[:5] or 'ok'}")
    # 9b. emoji Roblox cannot draw (Unicode 13+ -> tofu box)
    ext12 = set(range(0x1FA70, 0x1FA74)) | set(range(0x1FA78, 0x1FA7B)) | set(range(0x1FA80, 0x1FA83)) | set(range(0x1FA90, 0x1FA96))
    newer = {0x1F972, 0x1F977, 0x1F978, 0x1F979, 0x1F90C, 0x1F9A3, 0x1F9A4, 0x1F9AB, 0x1F9AC, 0x1F9AD, 0x1F9CB, 0x1F9CC,
             0x1F6D6, 0x1F6D7, 0x1F6DC, 0x1F6DD, 0x1F6DE, 0x1F6DF, 0x1F6FB, 0x1F6FC, 0x1F7F0}
    tofu = sorted({f"{o['path']}={o['text'][:10]}" for o in texts for ch in o["text"]
                   if (0x1FA70 <= ord(ch) <= 0x1FAFF and ord(ch) not in ext12) or ord(ch) in newer})
    add("No emoji newer than Unicode 12 (Roblox draws them as tofu boxes) in visible text", not tofu, f"{tofu[:5] or 'none'}")
    # 10. reduced motion
    add("Reduced motion: no infinite tween loops are created when GuiService.ReducedMotionEnabled is true",
        (probe.get("reducedLoops") or 0) == 0, f"loops normal={probe.get('loops')} reduced={probe.get('reducedLoops')} (tweens {probe.get('tweens')}/{probe.get('reducedTweens')})")
    # 10b. top bar: Roblox's menu/chat buttons sit in the top-left 200x58 on an IgnoreGuiInset screen
    if probe.get("ignoreInset"):
        under = []
        for o in uniq:
            if o.get("laidOut") or o["class"] not in ("TextLabel", "TextButton", "ImageButton", "TextBox"):
                continue
            if o["class"] == "TextLabel" and not (o.get("text") or "").strip():
                continue
            x, y, w, h = o["rect"]
            if w > 0 and h > 0 and x < 200 and y < 58 and x + w > 0 and y + h > 0 and not (w >= 1200 and h >= 700):
                under.append(f"{o['path']} @({x:.0f},{y:.0f})")
        add("Nothing readable or pressable sits under Roblox's top-left buttons (x<200, y<58) on the IgnoreGuiInset screen",
            not under, f"{sorted(set(under))[:5] or 'clear'}")
    # 10c. motif-specific checks from the eval profile
    if profile.get("noGloss"):
        glossy = sorted({o["path"] for o in uniq if "gloss" in o["name"].lower()}
                        | {o["path"] for o in uniq if any("lip" in str(g).lower() for g in (o.get("gradNames") or []))})
        add("Material honesty: no sticker gloss bands or pressable lips on a motif that is not plastic or candy",
            not glossy, f"{glossy[:5] or 'none'}")
    if profile.get("noEmoji"):
        colourful = sorted({f"{o['path']}={o['text'][:10]}" for o in texts
                            if any(0x1F000 <= ord(ch) <= 0x1FAFF or ch == "\ufe0f" for ch in o["text"])})
        add("No colour emoji (the prompt asks for a restrained, non-cute look)", not colourful, f"{colourful[:5] or 'none'}")
    if profile.get("square"):
        rounded = sorted({f"{o['path']} r={o['corner']}" for o in uniq
                          if o.get("corner") and (o["corner"][0] > 0.02 or o["corner"][1] > 2)})
        add("Pixel windows: no rounded corners (UICorner radius <= 2 px) anywhere visible", not rounded, f"{rounded[:5] or 'none'}")
    if profile.get("font"):
        used = [f for f in families if f == profile["font"]]
        add(f"The motif's typeface {profile['font']} is used for visible text", bool(used), f"families {families}")
    if profile.get("dark"):
        backdrop = max(fills, key=lambda f: f[1])[0] if fills else None
        light = hls(backdrop)[1] if backdrop else 1
        add("Dark screen: the largest opaque backdrop has lightness < 0.22", light < 0.22,
            f"backdrop {'#%02X%02X%02X' % tuple(backdrop) if backdrop else None} lightness {light:.2f}")
    # 11. preview
    previews = [p.name for p in outputs.rglob("*") if p.suffix.lower() in (".png", ".html", ".jpg")
                and not p.name.startswith("studio-") and "obby-rush" not in p.parts]
    add("A visual preview (PNG/HTML) of the new look was produced for review", bool(previews), f"{previews[:4] or 'none'}")
    return exp


def main():
    iteration = Path(sys.argv[1])
    original = Path(os.path.expanduser("~/.claude/skills/roblox-motif-ui/evals/files/obby-rush"))
    for eval_dir in sorted(iteration.glob("eval-*")):
        for run_dir in sorted([p for p in eval_dir.iterdir() if p.is_dir()] + list(eval_dir.glob("*/run-*"))):
            if not (run_dir / "outputs").exists():
                continue
            exp = grade_run(run_dir, original)
            judge_path = iteration / "judge.json"
            if judge_path.exists():
                verdicts = json.loads(judge_path.read_text(encoding="utf-8"))
                for item in verdicts.get(f"{eval_dir.name}/{run_dir.parent.name}", []):
                    exp.append(item)
            passed = sum(e["passed"] for e in exp)
            grading = {"expectations": exp, "summary": {"passed": passed, "failed": len(exp) - passed, "total": len(exp),
                                                         "pass_rate": round(passed / len(exp), 3) if exp else 0}}
            (run_dir / "grading.json").write_text(json.dumps(grading, ensure_ascii=False, indent=2), encoding="utf-8")
            print(f"{eval_dir.name}/{run_dir.parent.name}/{run_dir.name}: {passed}/{len(exp)}")
            for e in exp:
                print(("  PASS " if e["passed"] else "  FAIL ") + e["text"] + " :: " + e["evidence"][:160])


if __name__ == "__main__":
    main()
