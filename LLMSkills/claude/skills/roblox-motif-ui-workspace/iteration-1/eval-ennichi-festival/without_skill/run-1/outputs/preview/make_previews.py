"""Dump MainMenu states with Lune and screenshot them through render.html in headless Chrome.

Run from the outputs folder:  python preview/make_previews.py [--gif]
Writes preview PNGs next to this folder's parent (the outputs root).
"""
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
OUT = HERE.parent
LUNE = r"C:\Users\ryufu\.rokit\tool-storage\lune-org\lune\0.10.5\lune.exe"
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
PROJECT = OUT / "obby-rush"
BEFORE = Path(sys.argv[sys.argv.index("--before") + 1]) if "--before" in sys.argv else None

# name, project, width, height, inset, page, time, actions
STATES = [
    ("main", PROJECT, 1280, 720, 58, "none", 0, ""),
    ("main_t3", PROJECT, 1280, 720, 58, "none", 3.1, ""),
    ("main_hover_play", PROJECT, 1280, 720, 58, "none", 0, "hoverPlay,pressPlay"),
    ("shop", PROJECT, 1280, 720, 58, "Shop", 0, ""),
    ("settings_music_off", PROJECT, 1280, 720, 58, "Settings", 0, "toggleMusic"),
    ("inventory", PROJECT, 1280, 720, 58, "Inventory", 0, ""),
    ("quests", PROJECT, 1280, 720, 58, "Quests", 0, ""),
    ("phone_main", PROJECT, 844, 390, 58, "none", 0, ""),
    ("phone_shop", PROJECT, 844, 390, 58, "Shop", 0, ""),
    ("tablet_main", PROJECT, 1024, 768, 58, "none", 0, ""),
]
if BEFORE:
    STATES.append(("before_main", BEFORE, 1280, 720, 58, "none", 0, ""))
    STATES.append(("before_shop", BEFORE, 1280, 720, 58, "Shop", 0, ""))


def dump(name, project, width, height, inset, page, time, actions):
    target = HERE / "out" / f"{name}.js"
    subprocess.run([LUNE, "run", str(HERE / "dump_menu.luau"), str(project), str(target), str(width), str(height),
                    str(inset), page, str(time), actions], check=True, capture_output=True, text=True)


def shoot(name, width, height, png):
    url = (HERE / "render.html").as_uri() + f"?state={name}"
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    f"--window-size={width},{height}", "--virtual-time-budget=8000", f"--screenshot={png}", url],
                   check=True, capture_output=True, text=True, timeout=120)


def main():
    shots = {}
    for state in STATES:
        name, project, width, height = state[0], state[1], state[2], state[3]
        dump(*state)
        png = OUT / f"preview_{name}.png"
        shoot(name, width, height, png)
        shots[name] = png
        print("shot", png.name)

    # Contact sheet of the key states.
    order = [n for n in ["before_main", "main", "shop", "settings_music_off", "inventory", "quests", "phone_main", "phone_shop"] if n in shots]
    thumbs = []
    for name in order:
        image = Image.open(shots[name]).convert("RGB")
        image.thumbnail((640, 360))
        canvas = Image.new("RGB", (640, 390), (30, 18, 26))
        canvas.paste(image, ((640 - image.width) // 2, 30))
        draw = ImageDraw.Draw(canvas)
        try:
            font = ImageFont.truetype("C:/Windows/Fonts/meiryob.ttc", 18)
        except OSError:
            font = ImageFont.load_default()
        draw.text((10, 5), name, fill=(255, 244, 222), font=font)
        thumbs.append(canvas)
    cols = 2
    rows = (len(thumbs) + cols - 1) // cols
    sheet = Image.new("RGB", (640 * cols, 390 * rows), (30, 18, 26))
    for index, thumb in enumerate(thumbs):
        sheet.paste(thumb, ((index % cols) * 640, (index // cols) * 390))
    sheet.save(OUT / "preview_contact_sheet.png")
    print("sheet written")

    if "--gif" in sys.argv:
        frames = []
        for index in range(24):
            name = f"anim_{index:02d}"
            dump(name, PROJECT, 1280, 720, 58, "none", 0.001 + index * 0.25, "")
            png = HERE / "out" / f"{name}.png"
            shoot(name, 1280, 720, png)
            frame = Image.open(png).convert("RGB")
            frame.thumbnail((640, 360))
            frames.append(frame)
        frames[0].save(OUT / "preview_idle_motion.gif", save_all=True, append_images=frames[1:], duration=250, loop=0)
        print("gif written")


if __name__ == "__main__":
    main()
