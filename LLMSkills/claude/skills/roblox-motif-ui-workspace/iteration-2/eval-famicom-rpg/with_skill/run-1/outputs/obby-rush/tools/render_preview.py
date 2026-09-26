#!/usr/bin/env python3
"""Render tools/dump_gui.luau JSON dumps to HTML + PNG previews and audit them.

  python tools/render_preview.py <out_dir> <name>=<dump.json> [<name>=<dump.json> ...]

For each dump: <out_dir>/<name>.html (absolutely positioned boxes, Google Fonts stand-ins for the Roblox
families: PressStart2P -> Press Start 2P, RobotoMono -> Roboto Mono, Japanese -> Noto Sans JP at the
requested weight, which is how Roblox falls back for CJK) and <name>.png via headless Chrome at the exact
viewport size. Also prints an audit: touch targets < 48 px, text or buttons under Roblox's top bar
(top 58 px), buttons off screen or overlapping, and text whose estimated width overflows its box.
"""
import html
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

CSS_FAMILY = {"PressStart2P": "'Press Start 2P'", "RobotoMono": "'Roboto Mono'", "GothamSSm": "'Montserrat'",
              "SourceSansPro": "'Source Sans 3'"}
CSS_WEIGHT = {"Thin": 100, "ExtraLight": 200, "Light": 300, "Regular": 400, "Medium": 500, "SemiBold": 600,
              "Bold": 700, "ExtraBold": 800, "Heavy": 900}
FONTS = ("https://fonts.googleapis.com/css2?family=Press+Start+2P&family=Roboto+Mono:wght@400;700"
         "&family=Noto+Sans+JP:wght@400;500;700;900&family=Montserrat:wght@500;700&display=block")
TOFU = {"\U0001FA99"}  # coin emoji: Unicode 13, drawn as a box by Roblox


def rgba(hex_colour, transparency):
    h = hex_colour.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return f"rgba({r},{g},{b},{1 - transparency:.3f})"


def render(dump):
    W, H = dump["width"], dump["height"]
    out = []
    for it in dump["items"]:
        style = [f"left:{it['x']:.1f}px", f"top:{it['y']:.1f}px", f"width:{it['w']:.1f}px", f"height:{it['h']:.1f}px",
                 f"z-index:{it['order']}"]
        if it.get("bg") and it["bgT"] < 1:
            style.append(f"background:{rgba(it['bg'], it['bgT'])}")
        if it.get("radius"):
            style.append(f"border-radius:{min(it['radius'], 9999)}px")
        if it.get("stroke"):
            s = it["stroke"]
            style.append(f"box-shadow:0 0 0 {s['w']}px {rgba(s['color'], s['t'])}")
        clip = it.get("clip")
        if clip:
            cx, cy, cw, ch = clip
            top = max(0, cy - it["y"])
            left = max(0, cx - it["x"])
            bottom = max(0, (it["y"] + it["h"]) - (cy + ch))
            right = max(0, (it["x"] + it["w"]) - (cx + cw))
            style.append(f"clip-path:inset({top:.1f}px {right:.1f}px {bottom:.1f}px {left:.1f}px)")
        inner = ""
        t = it.get("text")
        if t:
            value = "".join("\u25A1" if ch in TOFU else ch for ch in t["value"])
            family = CSS_FAMILY.get(t["family"], "'Roboto'")
            l, r, pt, pb = t["pad"]
            justify = {"Left": "flex-start", "Right": "flex-end"}.get(t["xa"], "center")
            align = {"Top": "flex-start", "Bottom": "flex-end"}.get(t["ya"], "center")
            text_align = {"Left": "left", "Right": "right"}.get(t["xa"], "center")
            wrap = "normal" if t["wrapped"] else "nowrap"
            inner = (f"<div style=\"position:absolute;left:{l}px;right:{r}px;top:{pt}px;bottom:{pb}px;display:flex;"
                     f"justify-content:{justify};align-items:{align};text-align:{text_align};white-space:{wrap};"
                     f"font-family:{family},'Noto Sans JP',sans-serif;font-weight:{CSS_WEIGHT.get(t['weight'], 400)};"
                     f"font-size:{t['size']}px;line-height:1.15;color:{rgba(t['color'], t['t'])};"
                     f"-webkit-font-smoothing:none;font-synthesis:none\">{html.escape(value)}</div>")
        out.append(f"<div title=\"{html.escape(it['path'])}\" style=\"position:absolute;{';'.join(style)}\">{inner}</div>")
    return (f"<!doctype html><html><head><meta charset='utf-8'><link rel='stylesheet' href='{FONTS}'>"
            f"<style>html,body{{margin:0;padding:0;background:#6B8E5A;overflow:hidden}}"
            f"#vp{{position:relative;width:{W}px;height:{H}px;overflow:hidden;"
            f"background:repeating-linear-gradient(135deg,#7FA36B 0 22px,#6B8E5A 22px 44px)}}</style></head>"
            f"<body><div id='vp'>{''.join(out)}</div></body></html>")


def audit(name, dump):
    W, H = dump["width"], dump["height"]
    issues = []
    buttons = [it for it in dump["items"] if it["button"]]
    def scrolled(b):  # inside a ScrollingFrame and not fully in its view: reachable by scrolling
        c = b.get("clip")
        return bool(c) and not (b["x"] >= c[0] - 0.5 and b["y"] >= c[1] - 0.5 and b["x"] + b["w"] <= c[0] + c[2] + 0.5
                                and b["y"] + b["h"] <= c[1] + c[3] + 0.5)
    buttons = [b for b in buttons if not scrolled(b)]
    for b in buttons:
        if b["w"] < 48 or b["h"] < 48:
            issues.append(f"SMALL {b['name']} {b['w']:.0f}x{b['h']:.0f}")
        if b["x"] < 0 or b["y"] < 0 or b["x"] + b["w"] > W + 0.5 or b["y"] + b["h"] > H + 0.5:
            issues.append(f"OFFSCREEN {b['name']} ({b['x']:.0f},{b['y']:.0f},{b['w']:.0f},{b['h']:.0f})")
    for it in dump["items"]:
        if (it.get("text") or it["button"]) and it["y"] < 58 and it["w"] > 0:
            issues.append(f"TOPBAR {it['name']} top={it['y']:.0f}")
        t = it.get("text")
        if t and not t["wrapped"]:
            l, r, _, _ = t["pad"]
            room = it["w"] - l - r
            if t["estWidth"] > room + 1 and not it["path"].endswith("MotifTitleShadow1") and not it["path"].endswith("MotifTitleShadow2"):
                issues.append(f"FIT {it['name']} '{t['value']}' est {t['estWidth']:.0f}px > {room:.0f}px")
    # Overlap between buttons that are both on top (ignore buttons covered by an opened page window).
    pages = [it for it in dump["items"] if it["name"].endswith("Page") and it["class"] == "Frame"]
    def covered(b):
        return any(p["order"] > b["order"] and p["x"] <= b["x"] and p["y"] <= b["y"] and p["x"] + p["w"] >= b["x"] + b["w"]
                   and p["y"] + p["h"] >= b["y"] + b["h"] for p in pages)
    live = [b for b in buttons if not covered(b)]
    for i, a in enumerate(live):
        for b in live[i + 1:]:
            if a["x"] < b["x"] + b["w"] and b["x"] < a["x"] + a["w"] and a["y"] < b["y"] + b["h"] and b["y"] < a["y"] + a["h"]:
                issues.append(f"OVERLAP {a['name']} x {b['name']}")
    print(f"[{name}] {W}x{H} page={dump['page']} hover={dump['hover']} skinned={dump['skinned']}: "
          f"{len(buttons)} buttons, {len(issues)} issue(s)")
    for issue in issues:
        print("   ", issue)
    return issues


def chrome():
    for c in [shutil.which("chrome"), r"C:\Program Files\Google\Chrome\Application\chrome.exe",
              r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"]:
        if c and os.path.exists(c):
            return c
    return None


def main():
    out_dir = Path(sys.argv[1])
    out_dir.mkdir(parents=True, exist_ok=True)
    exe = chrome()
    total = 0
    for arg in sys.argv[2:]:
        name, path = arg.split("=", 1)
        dump = json.loads(Path(path).read_text(encoding="utf-8"))
        html_path = out_dir / f"{name}.html"
        html_path.write_text(render(dump), encoding="utf-8")
        total += len(audit(name, dump))
        if exe:
            png = out_dir / f"{name}.png"
            subprocess.run([exe, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                            "--virtual-time-budget=8000", f"--window-size={dump['width']},{dump['height']}",
                            f"--screenshot={png.resolve()}", html_path.resolve().as_uri()],
                           check=True, timeout=120, capture_output=True)
            print("    png:", png)
    print(f"AUDIT: {total} issue(s)")


if __name__ == "__main__":
    main()
