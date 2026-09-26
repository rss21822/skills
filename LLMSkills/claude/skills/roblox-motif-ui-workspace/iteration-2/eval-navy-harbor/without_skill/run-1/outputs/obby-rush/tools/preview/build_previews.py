"""Dump -> render -> screenshot -> compose the menu previews.

    python tools/preview/build_previews.py <outDir> [--before <originalProjectDir>]

Run from the project folder. Needs lune (LUNE env var, the rokit tool-storage binary, or PATH),
Chrome (CHROME env var or the default install path) and Pillow. Writes into <outDir>:
  preview.html                 interactive preview (click the tabs / 閉じる / toggles in the render)
  preview_<scene>.png          1280x720 screenshots of home / shop / settings / inventory / quests
  preview_sheet.png            the five scenes on one sheet
  preview_sizes.png            tablet 1024x768, wide 1920x1080 and phone-landscape 844x390
  preview_before_after.png     original theme vs this one (with --before)
  preview_dom/                 the per-scene HTML renders + the fonts they use
"""
import argparse
import html
import json
import os
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import render  # noqa: E402

# The rokit shim on PATH refuses to run lune outside a manifest, so prefer the stored binary.
_STORED_LUNE = os.path.expanduser(r"~\.rokit\tool-storage\lune-org\lune\0.10.5\lune.exe")
LUNE = os.environ.get("LUNE") or (_STORED_LUNE if os.path.exists(_STORED_LUNE) else shutil.which("lune"))
CHROME = os.environ.get("CHROME") or r"C:\Program Files\Google\Chrome\Application\chrome.exe"
SCENES = ["home", "shop", "settings", "inventory", "quests"]
CAPTIONS = {"home": "ホーム", "shop": "ショップ", "settings": "設定（音楽 OFF = N旗）", "inventory": "持ち物（空）", "quests": "クエスト（空）"}
DESKTOP, TABLET, WIDE, PHONE = (1280, 720), (1024, 768), (1920, 1080), (844, 390)


def dump(project, out_json, size=DESKTOP):
    subprocess.run([LUNE, "run", os.path.join(HERE, "dump_tree.luau"), project, out_json, str(size[0]), str(size[1])], check=True)
    return json.load(open(out_json, encoding="utf-8"))


def shoot(html_path, png_path, size):
    url = "file:///" + os.path.abspath(html_path).replace("\\", "/")
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    f"--window-size={size[0]},{size[1]}", "--virtual-time-budget=6000", f"--screenshot={os.path.abspath(png_path)}", url],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    img = Image.open(png_path)
    if img.size != tuple(size):
        img.crop((0, 0, size[0], size[1])).save(png_path)
    return png_path


def write_dom(data, dom_dir, prefix, size, scenes=SCENES):
    paths = {}
    for scene in scenes:
        page, _ = render.render_scene(data["scenes"][scene], size[0], size[1], f"{prefix} {scene}", "fonts/fonts.css")
        paths[scene] = os.path.join(dom_dir, f"{prefix}_{scene}.html")
        with open(paths[scene], "w", encoding="utf-8") as fh:
            fh.write(page)
    return paths


def label_font(size):
    for name in ("C:/Windows/Fonts/YuGothB.ttc", "C:/Windows/Fonts/meiryob.ttc", "C:/Windows/Fonts/arialbd.ttf"):
        if os.path.exists(name):
            return ImageFont.truetype(name, size)
    return ImageFont.load_default()


def sheet(images, captions, columns, out_path, title, scale=0.5):
    cells = [(img, cap, (int(img.size[0] * scale), int(img.size[1] * scale))) for img, cap in zip(images, captions)]
    pad, head, cap_h = 24, 64, 34
    rows = [cells[i:i + columns] for i in range(0, len(cells), columns)]
    width = pad + max(sum(c[2][0] + pad for c in row) for row in rows)
    height = head + sum(max(c[2][1] for c in row) + cap_h + pad for row in rows)
    canvas = Image.new("RGB", (width, height), (13, 17, 28))
    draw = ImageDraw.Draw(canvas)
    draw.text((pad, 18), title, fill=(243, 240, 231), font=label_font(26))
    y = head
    for row in rows:
        x = pad
        for img, caption, (tw, th) in row:
            draw.text((x, y + 4), caption, fill=(172, 186, 216), font=label_font(18))
            canvas.paste(img.resize((tw, th), Image.LANCZOS), (x, y + cap_h))
            x += tw + pad
        y += max(c[2][1] for c in row) + cap_h + pad
    canvas.save(out_path)


INTERACTIVE = """<!doctype html><html lang="ja"><head><meta charset="utf-8">
<title>OBBY RUSH — 夜の港と海軍 preview</title>
<link rel="stylesheet" href="preview_dom/fonts/fonts.css">
<style>
body{{margin:0;background:#0b0f1a;color:#f3f0e7;font-family:'Source Sans 3','Noto Sans JP',sans-serif;}}
header{{display:flex;flex-wrap:wrap;gap:8px;align-items:center;padding:12px 18px;}}
header h1{{font:700 20px 'Oswald','Noto Sans JP',sans-serif;margin:0 16px 0 0;letter-spacing:.02em;}}
header button{{background:#1d3468;color:#f3f0e7;border:1px solid rgba(243,240,231,.5);border-radius:6px;padding:6px 12px;cursor:pointer;font:600 14px 'Source Sans 3','Noto Sans JP',sans-serif;}}
header button.on{{background:#cc2231;border-color:#f3f0e7;}}
header a{{color:#acbad8;font-size:13px;margin-left:6px;}}
#toast{{position:fixed;right:18px;bottom:18px;background:#cc2231;color:#fff;padding:8px 14px;border-radius:6px;opacity:0;transition:opacity .2s;font:600 14px monospace;}}
#wrap{{padding:0 18px 18px;}}
#stage{{transform-origin:top left;width:{w}px;height:{h}px;}}
.scene{{display:none;}} .scene.on{{display:block;}}
.scene [data-name^="Nav_"],.scene [data-name="CloseButton"],.scene [data-name^="Toggle_"],.scene [data-name="PlayButton"],.scene [data-name="BuyButton"]{{cursor:pointer;}}
p.note{{color:#acbad8;font-size:13px;margin:10px 0 0;max-width:1100px;line-height:1.5;}}
{css}
</style></head><body>
<header><h1>OBBY RUSH · 夜の港と海軍</h1>{buttons}
<a href="preview_sheet.png">sheet</a><a href="preview_sizes.png">sizes</a><a href="preview_before_after.png">before/after</a></header>
<div id="wrap"><div id="stage">{scenes}</div>
<p class="note">These screens are the instance trees that <code>MainMenu.build</code> actually produces (run through the
contract test's mock with Lune), laid out with Roblox's UDim2 / AnchorPoint / UIListLayout / UIPadding / UICorner / UIStroke /
UIGradient rules. Click the tabs, 閉じる, the music toggle, プレイ or 購入 inside the render. Text metrics come from the browser
(Noto Sans JP stands in for Roblox's CJK fallback), so treat spacing as approximate.</p></div>
<div id="toast"></div>
<script>
const scenes=[...document.querySelectorAll('.scene')];
function show(name){{scenes.forEach(s=>s.classList.toggle('on',s.dataset.scene===name));
 document.querySelectorAll('header button').forEach(b=>b.classList.toggle('on',b.dataset.scene===name));}}
function toast(t){{const el=document.getElementById('toast');el.textContent=t;el.style.opacity=1;clearTimeout(el._t);el._t=setTimeout(()=>el.style.opacity=0,1400);}}
document.querySelectorAll('header button').forEach(b=>b.onclick=()=>show(b.dataset.scene));
document.getElementById('stage').addEventListener('click',e=>{{
 const nav=e.target.closest('[data-name^="Nav_"]'); if(nav){{const id=nav.dataset.name.slice(4).toLowerCase(); show(id); toast('navigate("'+nav.dataset.name.slice(4)+'")'); return;}}
 if(e.target.closest('[data-name="CloseButton"]')){{show('home');return;}}
 if(e.target.closest('[data-name="Toggle_Music"]')){{const cur=document.querySelector('.scene.on').dataset.scene; show(cur==='settings'?'settings_on':'settings'); toast('toggle("music", '+(cur==='settings')+')'); return;}}
 if(e.target.closest('[data-name="PlayButton"]')){{toast('play()');return;}}
 const row=e.target.closest('[data-name^="Product_"]'); if(row&&e.target.closest('[data-name="BuyButton"]')){{toast('buy("'+row.dataset.name.slice(8)+'")');}}
}});
function fit(){{const s=Math.min(1,(window.innerWidth-36)/{w});document.getElementById('stage').style.transform='scale('+s+')';
 document.getElementById('stage').style.marginBottom=({h}*s-{h})+'px';}}
window.addEventListener('resize',fit);fit();show('home');
</script></body></html>
"""


def interactive(data, out_path, size):
    names = SCENES + ["settings_on"]
    blocks, buttons = [], []
    for scene in names:
        body, _ = render.render_body(data["scenes"][scene], size[0], size[1])
        blocks.append(f'<div class="scene" data-scene="{scene}"><div class="screen" style="width:{size[0]}px;height:{size[1]}px">{body}</div></div>')
        if scene in CAPTIONS:
            buttons.append(f'<button data-scene="{scene}">{html.escape(CAPTIONS[scene])}</button>')
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(INTERACTIVE.format(w=size[0], h=size[1], css=render.SCENE_CSS, buttons="".join(buttons), scenes="\n".join(blocks)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("out")
    parser.add_argument("--before")
    args = parser.parse_args()
    project = os.getcwd()
    out = os.path.abspath(args.out)
    dom = os.path.join(out, "preview_dom")
    work = os.path.join(out, "_work")
    os.makedirs(dom, exist_ok=True)
    os.makedirs(work, exist_ok=True)

    after = dump(project, os.path.join(work, "after.json"))
    phone = dump(project, os.path.join(work, "after_phone.json"), PHONE)
    print("home menu instances:", after["instanceCount"])

    desktop_paths = write_dom(after, dom, "after_1280x720", DESKTOP)
    desktop = [Image.open(shoot(desktop_paths[s], os.path.join(out, f"preview_{s}.png"), DESKTOP)).convert("RGB") for s in SCENES]
    sheet(desktop, [CAPTIONS[s] for s in SCENES], 2, os.path.join(out, "preview_sheet.png"),
          "OBBY RUSH — 夜の港と海軍 / Night Harbour & Navy (1280×720)")

    sized = []
    for size, data, scenes in ((TABLET, after, ["home", "shop"]), (WIDE, after, ["home", "shop"]), (PHONE, phone, ["home", "shop", "inventory"])):
        tag = f"{size[0]}x{size[1]}"
        paths = write_dom(data, dom, f"after_{tag}", size, scenes)
        for scene in scenes:
            png = shoot(paths[scene], os.path.join(work, f"after_{tag}_{scene}.png"), size)
            sized.append((Image.open(png).convert("RGB"), f"{tag} {CAPTIONS[scene]}", size))
    # normalise to a common height so the sheet stays readable
    images = [img.resize((int(img.size[0] * 360 / img.size[1]), 360), Image.LANCZOS) for img, _, _ in sized]
    sheet(images, [cap for _, cap, _ in sized], 3, os.path.join(out, "preview_sizes.png"),
          "Other viewports (phone landscape uses compact mode: hoist, captions and illustrations hidden)", scale=1)

    interactive(after, os.path.join(out, "preview.html"), DESKTOP)

    if args.before:
        before = dump(os.path.abspath(args.before), os.path.join(work, "before.json"))
        paths = write_dom(before, dom, "before_1280x720", DESKTOP, ["home", "shop"])
        pairs = []
        for scene in ("home", "shop"):
            png = shoot(paths[scene], os.path.join(work, f"before_{scene}.png"), DESKTOP)
            pairs += [Image.open(png).convert("RGB"), desktop[SCENES.index(scene)]]
        sheet(pairs, ["BEFORE ホーム", "AFTER ホーム", "BEFORE ショップ", "AFTER ショップ"], 2,
              os.path.join(out, "preview_before_after.png"), "Before → After")


if __name__ == "__main__":
    main()
