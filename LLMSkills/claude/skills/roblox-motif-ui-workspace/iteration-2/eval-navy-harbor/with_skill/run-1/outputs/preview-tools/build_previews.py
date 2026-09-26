#!/usr/bin/env python3
"""Build every preview of the night-harbour menu from the real Luau code and audit each render.

  python preview-tools/build_previews.py        (from the outputs folder)

For each (screen, size): lune export_tree.luau -> render_preview.py (HTML + PNG + in-page audit).
Writes the top-level preview_*.png, a before/after sheet and preview.html (index with audit results).
"""
import html
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent.parent
PROJECT = OUT / "obby-rush"
TOOLS = OUT / "preview-tools"
WORK = TOOLS / "work"
LUNE = r"C:\Users\ryufu\.rokit\tool-storage\lune-org\lune\0.10.5\lune.exe"

SCREENS = [("none", "Main menu"), ("Shop", "Shop"), ("Settings", "Settings"), ("Inventory", "Inventory"), ("Quests", "Quests")]
SIZES = [(1280, 720, "desktop 1280x720"), (1920, 1080, "desktop 1920x1080"), (1366, 768, "laptop 1366x768"),
         (1024, 768, "tablet 1024x768"), (844, 390, "phone landscape 844x390")]


def export(page, w, h, name, plain=False):
    tree = WORK / f"{name}.json"
    args = [LUNE, "run", str(TOOLS / "export_tree.luau"), page, str(w), str(h), str(tree)] + (["plain"] if plain else [])
    subprocess.run(args, cwd=PROJECT, check=True, capture_output=True, text=True)
    return tree


def render(tree, name, title):
    htm, png = WORK / f"{name}.html", WORK / f"{name}.png"
    res = subprocess.run([sys.executable, str(TOOLS / "render_preview.py"), str(tree), str(htm), "--png", str(png), "--audit", "--title", title],
                         capture_output=True, text=True, encoding="utf-8")
    line = [l for l in res.stdout.splitlines() if l.startswith("audit")]
    rest = res.stdout[res.stdout.find("audit"):].split(": ", 1)[1].strip() if line else "AUDIT MISSING"
    return png, htm, rest


def label(img, text):
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("arialbd.ttf", 22)
    except OSError:
        font = ImageFont.load_default()
    d.rectangle([0, 0, img.width, 34], fill=(0, 0, 0))
    d.text((12, 5), text, fill=(255, 255, 255), font=font)
    return img


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    results = []
    for w, h, size_name in SIZES:
        for page, screen in SCREENS:
            if (w, h) != (1280, 720) and page in ("Inventory", "Quests"):
                continue
            name = f"{page}_{w}x{h}"
            png, htm, audit = render(export(page, w, h, name), name, f"{screen} {size_name}")
            results.append({"screen": screen, "size": size_name, "png": png, "html": htm, "audit": audit})
            print(f"{screen:10s} {size_name:26s} {audit}")
    # top-level previews (desktop 1280x720) + phone
    for page, screen in SCREENS:
        Image.open(WORK / f"{page}_1280x720.png").save(OUT / f"preview_{screen.lower().replace(' ', '_')}.png")
    phone = Image.new("RGB", (844 * 2 + 20, 390), (30, 30, 30))
    phone.paste(Image.open(WORK / "none_844x390.png"), (0, 0))
    phone.paste(Image.open(WORK / "Shop_844x390.png"), (864, 0))
    phone.save(OUT / "preview_phone_landscape.png")
    # before / after (before = the same src without the Harbor skin: UITheme's navy dashboard look)
    before_png, _, before_audit = render(export("none", 1280, 720, "before_none", plain=True), "before_none", "before")
    before_shop, _, _ = render(export("Shop", 1280, 720, "before_shop", plain=True), "before_shop", "before shop")
    sheet = Image.new("RGB", (1280 * 2 + 20, 720 * 2 + 20), (30, 30, 30))
    sheet.paste(label(Image.open(before_png).convert("RGB"), "BEFORE  (UITheme stock look)"), (0, 0))
    sheet.paste(label(Image.open(WORK / "none_1280x720.png").convert("RGB"), "AFTER  night harbour navy"), (1300, 0))
    sheet.paste(label(Image.open(before_shop).convert("RGB"), "BEFORE  shop"), (0, 740))
    sheet.paste(label(Image.open(WORK / "Shop_1280x720.png").convert("RGB"), "AFTER  shop"), (1300, 740))
    sheet.save(OUT / "preview_before_after.png")
    # index page
    rows = "".join(f"<tr><td>{html.escape(r['screen'])}</td><td>{html.escape(r['size'])}</td>"
                   f"<td class='{'ok' if r['audit'] == 'PASS' else 'bad'}'>{html.escape(r['audit'])}</td>"
                   f"<td><a href='preview-tools/work/{r['html'].name}'>live HTML</a></td></tr>" for r in results)
    imgs = "".join(f"<figure><img src='{p}'><figcaption>{c}</figcaption></figure>" for p, c in [
        ("preview_main_menu.png", "Main menu 1280x720"), ("preview_shop.png", "Shop"), ("preview_settings.png", "Settings (音楽 ON, 効果音 OFF)"),
        ("preview_inventory.png", "Inventory"), ("preview_quests.png", "Quests"), ("preview_phone_landscape.png", "Phone landscape 844x390: main + shop"),
        ("preview_before_after.png", "Before / after"), ("style-board.png", "Spec style board (skin_preview.py)")])
    (OUT / "preview.html").write_text(f"""<!doctype html><html><head><meta charset='utf-8'><title>Obby Rush - night harbour navy</title>
<style>body{{background:#0b1426;color:#f4efe4;font-family:Montserrat,'Noto Sans JP',sans-serif;margin:24px}}
h1{{font-family:Oswald,sans-serif;letter-spacing:1px}} figure{{margin:0 0 28px}} img{{max-width:100%;border:2px solid #c9a24a}}
figcaption{{color:#c9a24a;margin-top:6px}} table{{border-collapse:collapse}} td{{border:1px solid #35507f;padding:4px 10px}}
.ok{{color:#9fe0a8}} .bad{{color:#ff8a8a}} a{{color:#f0d48a}}</style></head><body>
<h1>OBBY RUSH — 夜の港と海軍 (night harbour navy)</h1>
<p>Rendered from the real Luau (src/ built in Lune with the project's mock, laid out by preview-tools/render_preview.py).
Not a Studio screenshot: Roblox's own renderer was not used in this run. The dark rounded squares at the top corners mark
Roblox's top-bar buttons.</p>
<h2>Layout audit (text fit, 48 px touch, overlap, off-screen, top bar)</h2><table><tr><th>screen</th><th>size</th><th>audit</th><th></th></tr>{rows}
<tr><td>before (stock)</td><td>desktop 1280x720</td><td>{html.escape(before_audit)}</td><td></td></tr></table>
<h2>Screens</h2>{imgs}</body></html>""", encoding="utf-8")
    failed = [r for r in results if r["audit"] != "PASS"]
    print("ALL AUDITS PASS" if not failed else f"{len(failed)} audit(s) failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
