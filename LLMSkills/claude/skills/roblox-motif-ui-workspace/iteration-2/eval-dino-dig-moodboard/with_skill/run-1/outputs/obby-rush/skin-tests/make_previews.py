#!/usr/bin/env python3
"""Render the menu (real Luau instance tree -> HTML) for several screens and sizes, screenshot each with
headless Chrome, collect the layout audit, and compose comparison sheets.

  python skin-tests/make_previews.py --out <dir> [--before <path to original src>]

Run from the project folder (needs lune and Chrome). Writes <dir>/raw/*.html|png, <dir>/audit.txt and
the contact sheets named by --sheet-prefix in <dir>.
"""
import argparse
import html
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

LUNE = os.environ.get("LUNE", r"C:\Users\ryufu\.rokit\tool-storage\lune-org\lune\0.10.5\lune.exe")
CHROME_CANDIDATES = [r"C:\Program Files\Google\Chrome\Application\chrome.exe",
                     r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
                     r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"]
SCREENS = ["home", "shop", "settings", "inventory", "quests"]
SIZES = [(1280, 720), (844, 390), (1024, 768)]


def chrome():
    for c in CHROME_CANDIDATES + [shutil.which("chrome") or ""]:
        if c and os.path.exists(c):
            return c
    sys.exit("no Chrome/Edge found")


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, encoding="utf-8", errors="replace", **kw)


def render(out_html, screen, w, h, root, label):
    run([LUNE, "run", "skin-tests/render_preview.luau", str(out_html), screen, str(w), str(h), root, label])


def shoot(exe, html_path, png_path, w, h):
    url = Path(html_path).resolve().as_uri()
    run([exe, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
         "--virtual-time-budget=8000", f"--screenshot={Path(png_path).resolve()}", f"--window-size={w},{h}", url], timeout=120)
    dom = run([exe, "--headless=new", "--disable-gpu", "--virtual-time-budget=8000", f"--window-size={w},{h + 400}",
               "--dump-dom", url], timeout=120).stdout
    m = re.search(r'<div id="audit">(.*?)</div>', dom, re.S)
    return html.unescape(m.group(1)).strip() if m else "audit: not found"


def sheet(images, cols, out, title, pad=18, label_h=30):
    ims = [(Image.open(p).convert("RGB"), cap) for p, cap in images]
    cell_w = max(i.width for i, _ in ims)
    rows = (len(ims) + cols - 1) // cols
    row_h = [max(ims[r * cols + c][0].height for c in range(cols) if r * cols + c < len(ims)) for r in range(rows)]
    W = cols * cell_w + (cols + 1) * pad
    H = 56 + sum(row_h) + rows * (label_h + pad) + pad
    board = Image.new("RGB", (W, H), (32, 30, 26))
    draw = ImageDraw.Draw(board)
    try:
        font = ImageFont.truetype("segoeui.ttf", 22)
        small = ImageFont.truetype("segoeui.ttf", 17)
    except OSError:
        font = small = ImageFont.load_default()
    draw.text((pad, 14), title, fill=(240, 228, 196), font=font)
    y = 56
    for r in range(rows):
        for c in range(cols):
            i = r * cols + c
            if i >= len(ims):
                continue
            im, cap = ims[i]
            x = pad + c * (cell_w + pad)
            draw.text((x, y + 4), cap, fill=(200, 190, 165), font=small)
            board.paste(im, (x, y + label_h))
        y += row_h[r] + label_h + pad
    board.save(out)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--before")
    ap.add_argument("--moodboard")
    args = ap.parse_args()
    out = Path(args.out)
    raw = out / "raw"
    raw.mkdir(parents=True, exist_ok=True)
    exe = chrome()
    audit_lines = []
    shots = {}
    variants = [("after", "src", "Lost Valley Dig skin")]
    if args.before:
        variants.insert(0, ("before", args.before, "original theme"))
    for variant, root, label in variants:
        for (w, h) in SIZES:
            for screen in SCREENS:
                if variant == "before" and ((w, h) != (1280, 720) or screen not in ("home", "shop")):
                    continue
                name = f"{variant}-{screen}-{w}x{h}"
                page = raw / f"{name}.html"
                png = raw / f"{name}.png"
                render(page, screen, w, h, root, label)
                result = shoot(exe, page, png, w, h)
                shots[name] = png
                audit_lines.append(f"[{name}] {result}")
                print(f"{name}: {result.splitlines()[0] if result else ''}")
    (out / "audit.txt").write_text("\n".join(audit_lines) + "\n", encoding="utf-8")
    make_sheets(out, shots, args.moodboard, audit_lines)
    return shots


def make_sheets(out, shots, moodboard, audit_lines):
    top = out.parent if out.name == "preview" else out
    shutil.copy(shots["after-home-1280x720"], top / "preview-home.png")
    shutil.copy(shots["after-shop-1280x720"], top / "preview-shop.png")
    if "before-home-1280x720" in shots:
        sheet([(shots["before-home-1280x720"], "BEFORE  home (original UITheme)"), (shots["after-home-1280x720"], "AFTER  home (Lost Valley Dig)"),
               (shots["before-shop-1280x720"], "BEFORE  shop"), (shots["after-shop-1280x720"], "AFTER  shop")],
              2, top / "preview-before-after.png", "obby-rush main menu + shop: before / after (1280x720, rendered from the Luau instance tree)")
    sheet([(shots[f"after-{n}-1280x720"], f"{n}  1280x720") for n in SCREENS] + [(shots["after-home-1024x768"], "home  1024x768 (tablet)")],
          2, top / "preview-all-screens.png", "Lost Valley Dig: every menu screen")
    sheet([(shots[f"after-{n}-844x390"], f"{n}  844x390 (landscape phone)") for n in SCREENS] + [(shots["after-shop-1024x768"], "shop  1024x768 (tablet)")],
          2, top / "preview-small-screens.png", "Lost Valley Dig: phone and tablet sizes")
    if moodboard:
        mb = Image.open(moodboard).convert("RGB")
        mb = mb.resize((1280, int(mb.height * 1280 / mb.width)))
        tmp = out / "raw" / "_moodboard.png"
        mb.save(tmp)
        sheet([(tmp, "moodboard-dino-dig.png (the motif)"), (shots["after-home-1280x720"], "result: home"), (shots["after-shop-1280x720"], "result: shop")],
              3, top / "preview-moodboard-vs-menu.png", "Motif -> menu")
    figures = []
    for name in sorted(shots):
        figures.append(f"<figure><a href='preview/raw/{name}.html'><img src='preview/raw/{name}.png' loading='lazy'></a>"
                       f"<figcaption>{name}</figcaption></figure>")
    audit = html.escape("\n".join(audit_lines))
    page = f"""<!doctype html><meta charset='utf-8'><title>obby-rush - Lost Valley Dig previews</title>
<style>body{{margin:0;background:#201e1a;color:#f0e4c4;font:15px 'Segoe UI',sans-serif}}h1,h2{{font-family:Oswald,'Segoe UI',sans-serif;margin:18px}}
.sheet{{max-width:calc(100% - 36px);display:block;margin:0 18px 18px}}.grid{{display:flex;flex-wrap:wrap;gap:14px;margin:0 18px}}figure{{margin:0}}
figure img{{width:420px;border:3px solid #3a2616;border-radius:6px}}figcaption{{font:12px monospace;color:#c9b98f}}pre{{margin:18px;color:#c9b98f;white-space:pre-wrap}}</style>
<h1>obby-rush - Lost Valley Dig (恐竜の発掘調査をするジャングル)</h1>
<p style='margin:0 18px'>Every image is rendered from the real Luau instance tree (src/ built through the Lune mock DataModel) by
obby-rush/skin-tests/render_preview.luau; click a thumbnail for the live HTML render. Fonts are the Google Fonts equivalents of the
Roblox families and Japanese falls back to Noto Sans JP, so this approximates Roblox's text rendering. It is not a Studio capture.</p>
<h2>Motif to menu</h2><img class='sheet' src='preview-moodboard-vs-menu.png'>
<h2>Before / after</h2><img class='sheet' src='preview-before-after.png'>
<h2>All screens</h2><img class='sheet' src='preview-all-screens.png'>
<h2>Phone / tablet</h2><img class='sheet' src='preview-small-screens.png'>
<h2>Style board (spec lint)</h2><img class='sheet' src='style-board.png' style='max-width:600px'>
<h2>Individual renders</h2><div class='grid'>{''.join(figures)}</div>
<h2>Layout audit (text fit, 48 px targets, overlaps, decor over buttons, Roblox top bar)</h2><pre>{audit}</pre>"""
    (top / "preview.html").write_text(page, encoding="utf-8")


if __name__ == "__main__":
    main()
