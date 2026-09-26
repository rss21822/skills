"""Render previews of the obby-rush MainMenu without Roblox Studio.

1. Runs dump_menu.luau (Lune + the project's own tests/mock.luau) for each scenario, for the
   modified project ("after") and, if given, the untouched original ("before").
2. Writes outputs/preview.html: a gallery that lays the dumped GUI trees out with
   roblox_gui_preview.js (UDim2 / AnchorPoint / UIListLayout / UIPadding / UICorner / UIStroke /
   UIGradient / RichText emulation).
3. Screenshots every shot with headless Chrome into outputs/preview_*.png and builds a contact sheet.

usage: python render_preview.py <outputsDir> <projectDir> [originalProjectDir]
"""
import json
import os
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

LUNE = r"C:\Users\ryufu\.rokit\tool-storage\lune-org\lune\0.10.5\lune.exe"
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
HERE = Path(__file__).resolve().parent

SHOTS = [
    # id, source, scenario, viewport, caption
    ("lobby", "after", "lobby", (1280, 720), "Lobby / main menu (1280x720)"),
    ("shop", "after", "shop", (1280, 720), "Boutique = ShopPage (1280x720)"),
    ("settings", "after", "settings", (1280, 720), "Preferences = SettingsPage, music toggled OFF"),
    ("cloakroom", "after", "cloakroom", (1280, 720), "Cloakroom = InventoryPage (empty state)"),
    ("hover", "after", "hover", (1280, 720), "Hover: PLAY + Concierge placard"),
    ("phone_lobby", "after", "lobby", (844, 390), "Phone landscape 844x390, lobby"),
    ("phone_shop", "after", "shop", (844, 390), "Phone landscape 844x390, boutique"),
    ("before_lobby", "before", "lobby", (1280, 720), "BEFORE: original lobby"),
    ("before_shop", "before", "shop", (1280, 720), "BEFORE: original shop"),
]


def dump(project, scenario, out, viewport):
    subprocess.run([LUNE, "run", str(HERE / "dump_menu.luau"), str(project), str(out), scenario,
                    str(viewport[0]), str(viewport[1])],
                   check=True, cwd=HERE, capture_output=True, text=True)
    return json.loads(Path(out).read_text(encoding="utf-8"))


HTML = r"""<!doctype html>
<html lang="ja"><head><meta charset="utf-8">
<title>Obby Rush - Grand Lobby UI preview</title>
<style>
@font-face { font-family: 'Accanthis ADF Std'; src: url('preview-tools/fonts/AccanthisADFStd-Regular.otf'); }
@font-face { font-family: 'Josefin Sans'; src: url('preview-tools/fonts/JosefinSans.ttf'); font-weight: 100 700; }
@font-face { font-family: 'EB Garamond'; src: url('preview-tools/fonts/EBGaramond.ttf'); font-weight: 400 800; }
@font-face { font-family: 'Montserrat'; src: url('preview-tools/fonts/Montserrat.ttf'); font-weight: 100 900; }
html, body { margin: 0; background: #1b1b1d; color: #d9d4ca; font-family: 'Segoe UI', 'Noto Sans JP', sans-serif; }
.gallery { padding: 28px; display: flex; flex-wrap: wrap; gap: 28px; }
.shot { display: flex; flex-direction: column; gap: 8px; }
.shot h2 { font-size: 13px; font-weight: 600; margin: 0; letter-spacing: .04em; color: #bdb6a8; }
.frame { position: relative; overflow: hidden; box-shadow: 0 0 0 1px #333; }
.stage { position: absolute; left: 0; top: 0; overflow: hidden; transform-origin: 0 0; }
/* Stand-in for the live 3D world behind the menu (not part of this project). */
.world { position: absolute; inset: 0; background:
  radial-gradient(ellipse at 50% 35%, #4a4540 0%, #2c2a28 45%, #161515 100%); }
/* Approximate Roblox core UI buttons (top-left), to check the menu leaves them room. */
.core { position: absolute; left: 12px; top: 12px; width: 96px; height: 44px; border-radius: 22px;
  background: rgba(0,0,0,.45); z-index: 100000; }
.core::after { content: 'Roblox'; position: absolute; inset: 0; display: flex; align-items: center; justify-content: center;
  font: 600 11px 'Segoe UI', sans-serif; color: rgba(255,255,255,.55); }
body.single .gallery { padding: 0; }
body.single .intro { display: none; }
body.single .shot h2 { display: none; }
body.single .frame { box-shadow: none; }
.intro { padding: 28px 28px 0; max-width: 1100px; font-size: 13px; line-height: 1.6; color: #a9a295; }
.intro b { color: #e6dcc6; }
</style></head>
<body>
<div class="intro"><b>Obby Rush / Grand Lobby UI - preview.</b> Every frame below is laid out from the real
<code>MainMenu.build</code> output (run under Lune with the project's own <code>tests/mock.luau</code>) by a small
Roblox GUI emulator (<code>preview-tools/roblox_gui_preview.js</code>). The dark gradient behind the menu stands in
for the live 3D world; the pill at top-left marks Roblox's own core buttons. Fonts: Roblox <i>Bodoni</i> is drawn with
Accanthis ADF Std, <i>JosefinSans</i> with Josefin Sans, Japanese with Noto Sans JP (Roblox's CJK fallback is a sans too).
Hover over any element to see its instance name.</div>
<div class="gallery" id="gallery"></div>
<script src="preview-tools/roblox_gui_preview.js"></script>
<script>
const SHOTS = __SHOTS__;
const params = new URLSearchParams(location.search);
const only = params.get('shot');
if (only) document.body.classList.add('single');
document.fonts.load("20px 'Accanthis ADF Std'").then(() => document.fonts.load("20px 'Josefin Sans'"))
  .then(() => document.fonts.load("20px 'Montserrat'")).finally(draw);
function draw() {
  const gallery = document.getElementById('gallery');
  for (const shot of SHOTS) {
    if (only && shot.id !== only) continue;
    const [w, h] = shot.viewport;
    const scale = only ? 1 : (w > 1000 ? 0.62 : 0.8);
    const box = document.createElement('div'); box.className = 'shot';
    const title = document.createElement('h2'); title.textContent = shot.caption; box.appendChild(title);
    const frame = document.createElement('div'); frame.className = 'frame';
    frame.style.width = (w * scale) + 'px'; frame.style.height = (h * scale) + 'px';
    const stage = document.createElement('div'); stage.className = 'stage';
    stage.style.width = w + 'px'; stage.style.height = h + 'px'; stage.style.transform = `scale(${scale})`;
    const world = document.createElement('div'); world.className = 'world'; stage.appendChild(world);
    const core = document.createElement('div'); core.className = 'core'; stage.appendChild(core);
    window.renderRobloxGui(stage, shot.tree.root, shot.viewport);
    frame.appendChild(stage); box.appendChild(frame); gallery.appendChild(box);
  }
  if (only) document.body.style.overflow = 'hidden';
  document.title += ' ready';
}
</script>
</body></html>
"""


def main():
    outputs = Path(sys.argv[1]).resolve()
    project = Path(sys.argv[2]).resolve()
    original = Path(sys.argv[3]).resolve() if len(sys.argv) > 3 else None
    dumps = HERE / "dumps"
    dumps.mkdir(exist_ok=True)
    shots = []
    for sid, source, scenario, viewport, caption in SHOTS:
        src = project if source == "after" else original
        if src is None:
            continue
        tree = dump(src, scenario, dumps / f"{source}_{sid}.json", viewport)
        shots.append({"id": sid, "caption": caption, "viewport": list(viewport), "tree": tree})
    html_path = outputs / "preview.html"
    html_path.write_text(HTML.replace("__SHOTS__", json.dumps(shots, ensure_ascii=False)), encoding="utf-8")
    print("wrote", html_path)

    pngs = []
    for sid, source, scenario, (w, h), caption in SHOTS:
        if source == "before" and original is None:
            continue
        png = outputs / f"preview_{sid}.png"
        url = html_path.as_uri() + f"?shot={sid}"
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1", "--disable-lcd-text",
                        f"--window-size={w},{h}", "--virtual-time-budget=4000", "--allow-file-access-from-files",
                        f"--screenshot={png}", url], check=True, capture_output=True)
        pngs.append((png, caption))
        print("wrote", png)

    # Contact sheet: after shots first, then before.
    thumbs = []
    for png, caption in pngs:
        im = Image.open(png).convert("RGB")
        scale = 620 / im.width if im.width > 1000 else 520 / im.width
        thumbs.append((im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS), caption))
    cols, pad, cap = 3, 24, 26
    col_w = max(t.width for t, _ in thumbs)
    rows = [thumbs[i:i + cols] for i in range(0, len(thumbs), cols)]
    heights = [max(t.height for t, _ in row) + cap for row in rows]
    sheet = Image.new("RGB", (cols * col_w + (cols + 1) * pad, sum(heights) + (len(rows) + 1) * pad), (24, 24, 26))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 15)
    except OSError:
        font = ImageFont.load_default()
    y = pad
    for row, rh in zip(rows, heights):
        x = pad
        for im, caption in row:
            draw.text((x, y), caption, fill=(200, 192, 176), font=font)
            sheet.paste(im, (x, y + cap))
            x += col_w + pad
        y += rh + pad
    sheet.save(outputs / "preview_contact_sheet.png")
    print("wrote", outputs / "preview_contact_sheet.png")


if __name__ == "__main__":
    main()
