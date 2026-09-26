#!/usr/bin/env python3
"""Render a GUI tree dumped by export_menu.luau to HTML (+ PNG via headless Chrome).

  python render_menu.py tree.json out.html [--png out.png]

A small re-implementation of the Roblox 2D layout rules the menu uses (UDim2 size/position,
AnchorPoint, Rotation about the centre, Sibling ZIndex, UIListLayout, UIPadding, UIScale,
UISizeConstraint, UICorner, Border/Contextual UIStroke, UIGradient, TextScaled + UITextSizeConstraint,
ClipsDescendants / CanvasGroup / ScrollingFrame clipping). It shows what the Luau code builds, with
Google-font stand-ins for the Roblox families. It is a preview, not Studio: glyph metrics, CJK
fallback, emoji art and the real lip/scroll behaviour differ in the engine.
"""
import argparse
import html
import json
import os
import shutil
import subprocess
from pathlib import Path

CSS_FAMILY = {
    "LuckiestGuy": "Luckiest Guy", "FredokaOne": "Fredoka One", "Nunito": "Nunito", "GothamSSm": "Montserrat",
    "Montserrat": "Montserrat", "BuilderSans": "Inter",
}
ENUM_FONT = {"GothamMedium": ("Montserrat", 500), "GothamBold": ("Montserrat", 700), "Gotham": ("Montserrat", 400)}
WEIGHT = {"Thin": 100, "ExtraLight": 200, "Light": 300, "Regular": 400, "Medium": 500, "SemiBold": 600, "Bold": 700,
          "ExtraBold": 800, "Heavy": 900}
CJK = '"M PLUS Rounded 1c","Noto Sans JP","Yu Gothic UI"'
GUI = {"Frame", "TextLabel", "TextButton", "ScrollingFrame", "CanvasGroup", "ImageLabel", "ImageButton", "TextBox",
       "ViewportFrame"}


def c3(v, alpha=1.0):
    return f"rgba({round(v['r'] * 255)},{round(v['g'] * 255)},{round(v['b'] * 255)},{alpha:.3f})"


def child(node, cls):
    for c in node["children"]:
        if c["class"] == cls:
            return c
    return None


def children_of(node, cls):
    return [c for c in node["children"] if c["class"] == cls]


def css_font(props):
    face = props.get("FontFace")
    if isinstance(face, dict) and face.get("t") == "font":
        fam = face["family"].split("/")[-1].replace(".json", "")
        return CSS_FAMILY.get(fam, fam), WEIGHT.get(face.get("weight", "Regular"), 400)
    font = props.get("Font")
    if isinstance(font, str) and font in ENUM_FONT:
        return ENUM_FONT[font]
    return "Montserrat", 500


def text_width_em(text):
    em = 0.0
    for ch in text:
        o = ord(ch)
        em += 1.0 if o > 0x2E80 else 0.62
    return max(em, 0.5)


class Renderer:
    def __init__(self, tree):
        self.tree = tree
        self.out = []

    def size_of(self, node, pw, ph):
        p = node["props"]
        s = p.get("Size") or {"xs": 0, "xo": 100, "ys": 0, "yo": 100}
        w, h = s["xs"] * pw + s["xo"], s["ys"] * ph + s["yo"]
        con = child(node, "UISizeConstraint")
        if con:
            mn, mx = con["props"].get("MinSize"), con["props"].get("MaxSize")
            if mx:
                w, h = min(w, mx["x"]), min(h, mx["y"])
            if mn:
                w, h = max(w, mn["x"]), max(h, mn["y"])
        return w, h

    def render(self):
        root = self.tree["root"]
        W, H = self.tree["width"], self.tree["height"]
        self.out.append(f"<div class='screen' style='width:{W}px;height:{H}px'>")
        self.children(root, W, H)
        self.out.append("</div>")
        return "".join(self.out)

    def content_box(self, node, w, h):
        pad = child(node, "UIPadding")
        if not pad:
            return 0, 0, w, h
        g = lambda k, base: (pad["props"].get(k) or {"s": 0, "o": 0})["s"] * base + (pad["props"].get(k) or {"s": 0, "o": 0})["o"]
        l, r, t, b = g("PaddingLeft", w), g("PaddingRight", w), g("PaddingTop", h), g("PaddingBottom", h)
        return l, t, max(0, w - l - r), max(0, h - t - b)

    def children(self, node, w, h):
        ox, oy, cw, ch = self.content_box(node, w, h)
        kids = [c for c in node["children"] if c["class"] in GUI and c["props"].get("Visible", True) is not False]
        layout = child(node, "UIListLayout")
        placed = []
        if layout:
            lp = layout["props"]
            horizontal = lp.get("FillDirection") == "Horizontal"
            pad = lp.get("Padding") or {"s": 0, "o": 0}
            gap = pad["s"] * (cw if horizontal else ch) + pad["o"]
            kids = sorted(kids, key=lambda c: c["props"].get("LayoutOrder", 0))
            sizes = [self.size_of(k, cw, ch) for k in kids]
            total = sum(s[0] if horizontal else s[1] for s in sizes) + gap * max(0, len(kids) - 1)
            cursor = 0
            if horizontal and lp.get("HorizontalAlignment") == "Center":
                cursor = (cw - total) / 2
            for k, (kw, kh) in zip(kids, sizes):
                if horizontal:
                    y = (ch - kh) / 2 if lp.get("VerticalAlignment") == "Center" else 0
                    placed.append((k, ox + cursor, oy + y, kw, kh))
                    cursor += kw + gap
                else:
                    x = (cw - kw) / 2 if lp.get("HorizontalAlignment") == "Center" else 0
                    placed.append((k, ox + x, oy + cursor, kw, kh))
                    cursor += kh + gap
        else:
            for k in kids:
                kw, kh = self.size_of(k, cw, ch)
                pos = k["props"].get("Position") or {"xs": 0, "xo": 0, "ys": 0, "yo": 0}
                anc = k["props"].get("AnchorPoint") or {"x": 0, "y": 0}
                x = pos["xs"] * cw + pos["xo"] - anc["x"] * kw
                y = pos["ys"] * ch + pos["yo"] - anc["y"] * kh
                placed.append((k, ox + x, oy + y, kw, kh))
        order = sorted(range(len(placed)), key=lambda i: (placed[i][0]["props"].get("ZIndex", 1), i))
        for i in order:
            self.element(*placed[i])

    def element(self, node, x, y, w, h):
        p = node["props"]
        cls = node["class"]
        style = [f"left:{x:.1f}px", f"top:{y:.1f}px", f"width:{w:.1f}px", f"height:{h:.1f}px", f"z-index:{p.get('ZIndex', 1) + 10}"]
        transforms = []
        rot = p.get("Rotation", 0) or 0
        if rot:
            transforms.append(f"rotate({rot}deg)")
        scale = child(node, "UIScale")
        if scale and abs(scale["props"].get("Scale", 1) - 1) > 1e-3:
            anc = p.get("AnchorPoint") or {"x": 0, "y": 0}
            style.append(f"transform-origin:{anc['x'] * 100:.0f}% {anc['y'] * 100:.0f}%")
            transforms.insert(0, f"scale({scale['props']['Scale']:.3f})")
        if transforms:
            style.append("transform:" + " ".join(transforms))
        bt = p.get("BackgroundTransparency", 0)
        if cls == "ScrollingFrame" and bt is None:
            bt = 0
        bg = p.get("BackgroundColor3")
        grad = child(node, "UIGradient")
        if bg and bt is not None and bt < 1:
            if grad and grad["props"].get("Enabled", True) is not False:
                style.append("background:" + self.gradient(bg, 1 - bt, grad))
            else:
                style.append("background:" + c3(bg, 1 - bt))
        corner = child(node, "UICorner")
        if corner:
            r = corner["props"].get("CornerRadius") or {"s": 0, "o": 8}
            radius = min(r["s"] * min(w, h) + r["o"], min(w, h) / 2)
            style.append(f"border-radius:{radius:.1f}px")
        text_stroke = None
        shadows = []
        for stroke in children_of(node, "UIStroke"):
            sp = stroke["props"]
            if sp.get("Enabled") is False:
                continue
            mode = sp.get("ApplyStrokeMode")
            has_text = cls in ("TextLabel", "TextButton", "TextBox")
            colour = c3(sp.get("Color") or {"r": 0, "g": 0, "b": 0}, 1 - (sp.get("Transparency") or 0))
            thick = sp.get("Thickness") or 1
            if mode == "Border" or (mode != "Contextual" and not has_text) or (mode is None and not has_text):
                shadows.append(f"0 0 0 {thick:.1f}px {colour}")
            elif has_text:
                text_stroke = (thick, colour)
        if shadows:
            style.append("box-shadow:" + ",".join(shadows))
        clip = p.get("ClipsDescendants") or cls in ("CanvasGroup", "ScrollingFrame")
        if clip:
            style.append("overflow:hidden")
        gt = p.get("GroupTransparency")
        if cls == "CanvasGroup" and gt:
            style.append(f"opacity:{1 - gt:.3f}")
        self.out.append(f"<div class='g' title='{html.escape(node['name'])}' style='{';'.join(style)}'>")
        if cls in ("TextLabel", "TextButton", "TextBox") and p.get("Text"):
            self.text(node, w, h, text_stroke)
        self.children(node, w, h)
        self.out.append("</div>")

    def gradient(self, bg, alpha, grad):
        gp = grad["props"]
        angle = 90 + (gp.get("Rotation") or 0)
        cs = gp.get("Color")
        ts = gp.get("Transparency")
        times = sorted({k["time"] for k in (cs["k"] if cs else [])} | {k["time"] for k in (ts["k"] if ts else [])} | {0, 1})

        def at(seq, t, field):
            ks = seq["k"]
            for a, b in zip(ks, ks[1:]):
                if a["time"] <= t <= b["time"]:
                    f = 0 if b["time"] == a["time"] else (t - a["time"]) / (b["time"] - a["time"])
                    return {k: a[k] + (b[k] - a[k]) * f for k in field}
            return {k: ks[-1][k] for k in field}

        stops = []
        for t in times:
            col = dict(bg)
            if cs:
                m = at(cs, t, ("r", "g", "b"))
                col = {k: bg[k] * m[k] for k in ("r", "g", "b")}
            a = alpha
            if ts:
                a *= 1 - at(ts, t, ("value",))["value"]
            stops.append(f"{c3(col, a)} {t * 100:.2f}%")
        return f"linear-gradient({angle}deg,{','.join(stops)})"

    def text(self, node, w, h, stroke):
        p = node["props"]
        family, weight = css_font(p)
        ox, oy, cw, ch = self.content_box(node, w, h)
        size = p.get("TextSize") or 14
        text = p["Text"]
        if p.get("TextScaled"):
            con = child(node, "UITextSizeConstraint")
            mx = con["props"].get("MaxTextSize", 100) if con else 100
            mn = con["props"].get("MinTextSize", 1) if con else 1
            size = max(mn, min(mx, ch * 0.92, cw / (text_width_em(text) * 1.02)))
        colour = c3(p.get("TextColor3") or {"r": 0, "g": 0, "b": 0}, 1 - (p.get("TextTransparency") or 0))
        if (p.get("TextTransparency") or 0) >= 1:
            return
        ha = {"Left": "flex-start", "Right": "flex-end"}.get(p.get("TextXAlignment"), "center")
        va = {"Top": "flex-start", "Bottom": "flex-end"}.get(p.get("TextYAlignment"), "center")
        wrap = "normal" if p.get("TextWrapped") and not p.get("TextScaled") else "nowrap"
        st = ""
        if stroke:
            st = f"-webkit-text-stroke:{stroke[0] * 2:.1f}px {stroke[1]};paint-order:stroke fill;"
        self.out.append(
            f"<div class='t' style='left:{ox:.1f}px;top:{oy:.1f}px;width:{cw:.1f}px;height:{ch:.1f}px;justify-content:{ha};align-items:{va};"
            f"text-align:{ {'flex-start': 'left', 'flex-end': 'right'}.get(ha, 'center') };white-space:{wrap};"
            f"font-family:\"{family}\",{CJK},\"Segoe UI Emoji\",sans-serif;font-weight:{weight};font-size:{size:.1f}px;color:{colour};{st}'>"
            f"<span>{html.escape(text)}</span></div>")


def page(tree):
    body = Renderer(tree).render()
    fonts = ("https://fonts.googleapis.com/css2?family=Luckiest+Guy&family=Fredoka+One&family=Nunito:wght@700;900"
             "&family=Montserrat:wght@500;700&family=M+PLUS+Rounded+1c:wght@700;800&display=swap")
    return f"""<!doctype html><html><head><meta charset='utf-8'><link rel='stylesheet' href='{fonts}'>
<style>html,body{{margin:0;padding:0;background:#6b6b6b}} .screen{{position:relative;overflow:hidden;background:#7d8f6e}}
.g{{position:absolute;box-sizing:border-box}} .t{{position:absolute;display:flex;line-height:1.05}}</style></head>
<body>{body}</body></html>"""


def screenshot(html_path, png_path, w, h):
    exe = next((c for c in [shutil.which("chrome"), r"C:\Program Files\Google\Chrome\Application\chrome.exe",
                            r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"] if c and os.path.exists(c)), None)
    if not exe:
        print("no chrome")
        return
    subprocess.run([exe, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--virtual-time-budget=6000",
                    f"--screenshot={Path(png_path).resolve()}", f"--window-size={w},{h}", Path(html_path).resolve().as_uri()],
                   check=True, timeout=120, capture_output=True)
    print("png:", png_path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tree")
    ap.add_argument("html")
    ap.add_argument("--png")
    args = ap.parse_args()
    tree = json.loads(Path(args.tree).read_text(encoding="utf-8"))
    Path(args.html).write_text(page(tree), encoding="utf-8")
    print("html:", args.html)
    if args.png:
        screenshot(args.html, args.png, tree["width"], tree["height"])


if __name__ == "__main__":
    main()
