#!/usr/bin/env python3
"""Export + render the menu in several screens/pages and build before/after and size sheets.
Run: python make_previews.py <project_dir> <out_dir>"""
import subprocess, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

LUNE = r"C:\Users\ryufu\.rokit\tool-storage\lune-org\lune\0.10.5\lune.exe"
here = Path(__file__).resolve().parent
project, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
work = out / "preview-tools" / "renders"
work.mkdir(parents=True, exist_ok=True)
SCENES = [
    ("before_main_1280x720", 1280, 720, "none", "0"), ("before_shop_1280x720", 1280, 720, "Shop", "0"),
    ("main_1280x720", 1280, 720, "none", "1"), ("shop_1280x720", 1280, 720, "Shop", "1"),
    ("settings_1280x720", 1280, 720, "Settings", "1"), ("inventory_1280x720", 1280, 720, "Inventory", "1"),
    ("quests_1280x720", 1280, 720, "Quests", "1"),
    ("main_828x369", 828, 369, "none", "1"), ("shop_828x369", 828, 369, "Shop", "1"),
    ("main_366x820", 366, 820, "none", "1"), ("shop_366x820", 366, 820, "Shop", "1"),
]
for name, w, h, page, skin in SCENES:
    tree = work / f"{name}.json"
    subprocess.run([LUNE, "run", str(here / "export_menu.luau"), str(tree), str(w), str(h), page, skin], cwd=project, check=True)
    subprocess.run([sys.executable, str(here / "render_menu.py"), str(tree), str(work / f"{name}.html"), "--png", str(work / f"{name}.png")], check=True)

def sheet(names, path, cols, label=True):
    ims = [Image.open(work / f"{n}.png").convert("RGB") for n in names]
    cw = max(i.width for i in ims); chh = max(i.height for i in ims)
    rows = (len(ims) + cols - 1) // cols
    pad, lab = 16, 28
    S = Image.new("RGB", (cols * (cw + pad) + pad, rows * (chh + pad + lab) + pad), (58, 34, 26))
    d = ImageDraw.Draw(S)
    try:
        f = ImageFont.truetype("arial.ttf", 18)
    except OSError:
        f = ImageFont.load_default()
    for i, (n, im) in enumerate(zip(names, ims)):
        x = pad + (i % cols) * (cw + pad); y = pad + (i // cols) * (chh + pad + lab)
        d.text((x, y), n, fill=(246, 236, 214), font=f)
        S.paste(im, (x, y + lab))
    S.save(path)
    print("sheet:", path)

sheet(["before_main_1280x720", "main_1280x720", "before_shop_1280x720", "shop_1280x720"], out / "preview-before-after.png", 2)
sheet(["settings_1280x720", "inventory_1280x720", "quests_1280x720", "shop_828x369"], out / "preview-other-pages.png", 2)
sheet(["main_366x820", "shop_366x820", "main_828x369"], out / "preview-phone-sizes.png", 3)
for n in ["main_1280x720", "shop_1280x720"]:
    Image.open(work / f"{n}.png").save(out / f"preview-{n}.png")
