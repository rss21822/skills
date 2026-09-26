"""Screenshot every render-*.html (outputs root) at its own viewport with headless Chrome, then compose
contact sheets (before/after at desktop, and all sizes).  python preview/shoot.py"""
import re
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
OUT = ROOT
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"


def shoot(html):
    text = html.read_text(encoding="utf-8")
    w, h = map(int, re.search(r"html,body\{margin:0;width:(\d+)px;height:(\d+)px", text).groups())
    png = html.with_suffix(".png")
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    "--virtual-time-budget=8000", f"--window-size={w},{h}", f"--screenshot={png}", html.resolve().as_uri()],
                   check=True, timeout=120, capture_output=True)
    return png


def label(img, text):
    font = ImageFont.truetype("C:/Windows/Fonts/meiryob.ttc", 22)
    canvas = Image.new("RGB", (img.width, img.height + 40), (20, 20, 20))
    canvas.paste(img, (0, 40))
    ImageDraw.Draw(canvas).text((10, 8), text, fill=(240, 240, 240), font=font)
    return canvas


def sheet(names, path, columns):
    imgs = [label(Image.open(OUT / f"render-{n}.png").convert("RGB"), n) for n in names]
    rows = [imgs[i:i + columns] for i in range(0, len(imgs), columns)]
    width = max(sum(i.width for i in r) + 16 * (len(r) - 1) for r in rows)
    height = sum(max(i.height for i in r) for r in rows) + 16 * (len(rows) - 1)
    out = Image.new("RGB", (width, height), (40, 40, 40))
    y = 0
    for r in rows:
        x = 0
        for i in r:
            out.paste(i, (x, y))
            x += i.width + 16
        y += max(i.height for i in r) + 16
    out.save(path)
    print("sheet", path, out.size)


for html in sorted(OUT.glob("render-*.html")):
    print("png", shoot(html).name)
sheet(["before_desktop_main", "after_desktop_main", "before_desktop_shop", "after_desktop_shop"], ROOT / "preview-before-after.png", 2)
sheet(["after_desktop_settings", "after_desktop_inventory"], ROOT / "preview-pages.png", 2)
sheet(["after_landscape_main", "after_landscape_shop", "after_portrait_main", "after_portrait_shop"], ROOT / "preview-phones.png", 4)
