"""Lay out a GUI tree dumped by dump_tree.luau and write it as static HTML (one file per scene).

It mirrors the Roblox rules the menu relies on: UDim2 size/position, AnchorPoint, UIPadding,
UIListLayout, UICorner, UIStroke (outer border stroke, gradient strokes), UIGradient (colour and
transparency sequences multiplied into the background), Rotation about the centre (children
inherit it), ClipsDescendants (ignored when the object or an ancestor is rotated), ZIndexBehavior
Sibling, and Visible. It is a preview, not an emulator: text metrics come from the browser.

    python render.py <tree.json> <outDir> <prefix> [width height] [fontsCssHref]
"""
import html
import json
import math
import os
import sys

GUI = {"Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame", "CanvasGroup"}
TEXT = {"TextLabel", "TextButton", "TextBox"}
WEIGHTS = {"Thin": 100, "ExtraLight": 200, "Light": 300, "Regular": 400, "Medium": 500, "SemiBold": 600, "Bold": 700,
           "ExtraBold": 800, "Heavy": 900}
JP = "'Noto Sans JP', 'Yu Gothic', 'Segoe UI Emoji', sans-serif"


def udim2(u, w, h):
    if not u:
        return 0.0, 0.0
    return u["xs"] * w + u["xo"], u["ys"] * h + u["yo"]


def udim(u, ref):
    return (u["s"] * ref + u["o"]) if u else 0.0


def kids(node, cls=None):
    return [c for c in node.get("children", []) if cls is None or c["ClassName"] == cls]


def first(node, cls):
    for c in node.get("children", []):
        if c["ClassName"] == cls:
            return c
    return None


def enum(node, key, default=None):
    v = node.get(key)
    return v["name"] if isinstance(v, dict) and v.get("t") == "Enum" else default


def rgba(r, g, b, transparency):
    a = max(0.0, min(1.0, 1.0 - transparency))
    return f"rgba({round(r * 255)},{round(g * 255)},{round(b * 255)},{a:.3f})"


def sample(keys, t, n):
    """Piecewise-linear sample of a sequence given as [[time, v1, ...], ...]."""
    if t <= keys[0][0]:
        return keys[0][1:1 + n]
    for a, b in zip(keys, keys[1:]):
        if a[0] <= t <= b[0]:
            f = 0 if b[0] == a[0] else (t - a[0]) / (b[0] - a[0])
            return [a[i] + (b[i] - a[i]) * f for i in range(1, 1 + n)]
    return keys[-1][1:1 + n]


def gradient_css(grad, base_rgb, base_t):
    ckeys = grad.get("Color", {}).get("keys") or [[0, 1, 1, 1], [1, 1, 1, 1]]
    tkeys = grad.get("Transparency", {}).get("keys") if isinstance(grad.get("Transparency"), dict) else None
    tkeys = tkeys or [[0, 0], [1, 0]]
    times = sorted({k[0] for k in ckeys} | {k[0] for k in tkeys})
    stops = []
    for t in times:
        r, g, b = sample(ckeys, t, 3)
        (gt,) = sample(tkeys, t, 1)
        alpha_t = 1 - (1 - base_t) * (1 - gt)
        stops.append(f"{rgba(r * base_rgb[0], g * base_rgb[1], b * base_rgb[2], alpha_t)} {t * 100:.2f}%")
    angle = (grad.get("Rotation") or 0) + 90
    return f"linear-gradient({angle}deg, {', '.join(stops)})"


def font_css(node):
    ff = node.get("FontFace")
    family, weight = "'Source Sans 3'", 400
    if isinstance(ff, dict) and ff.get("t") == "Font":
        fam = ff.get("family", "")
        weight = WEIGHTS.get(ff.get("weight"), 400)
        if "Oswald" in fam:
            family = "'Oswald'"
        elif "Gotham" in fam or "Montserrat" in fam:
            family = "'Montserrat'"
    else:
        name = enum(node, "Font", "SourceSans")
        if name.startswith("Gotham"):
            family = "'Montserrat'"
            weight = 700 if "Bold" in name or "Black" in name else 500
        elif name.startswith("Oswald"):
            family = "'Oswald'"
        elif name.startswith("SourceSans"):
            weight = 700 if name.endswith("Bold") else 600 if name.endswith("Semibold") else 400
    return f"font-family: {family}, {JP}; font-weight: {weight};"


class Renderer:
    def __init__(self):
        self.out = []
        self.count = 0

    def node(self, n, pw, ph, pad, forced=None, rotated=False):
        if n["ClassName"] not in GUI or n.get("Visible") is False:
            return
        self.count += 1
        w, h = udim2(n.get("Size"), pw, ph)
        if forced is not None:
            x, y = forced
        else:
            px, py = udim2(n.get("Position"), pw, ph)
            ap = n.get("AnchorPoint") or {"x": 0, "y": 0}
            x, y = pad[0] + px - ap["x"] * w, pad[1] + py - ap["y"] * h
        rotation = n.get("Rotation") or 0
        rotated_here = rotated or abs(rotation) > 1e-6
        clips = bool(n.get("ClipsDescendants")) and not rotated_here
        if n["ClassName"] == "ScrollingFrame":
            clips = not rotated_here

        style = [f"left:{x:.2f}px", f"top:{y:.2f}px", f"width:{w:.2f}px", f"height:{h:.2f}px", f"z-index:{n.get('ZIndex', 1)}"]
        bg = n.get("BackgroundColor3") or {"r": 1, "g": 1, "b": 1}
        bgt = n.get("BackgroundTransparency", 0)
        base = (bg["r"], bg["g"], bg["b"])
        grad = first(n, "UIGradient")
        if bgt < 1:
            if grad is not None:
                style.append(f"background:{gradient_css(grad, base, bgt)}")
            else:
                style.append(f"background:{rgba(*base, bgt)}")
            if (n.get("BorderSizePixel") or 0) > 0:
                style.append(f"box-shadow:0 0 0 {n['BorderSizePixel']}px {rgba(27 / 255, 42 / 255, 53 / 255, bgt)}")
        corner = first(n, "UICorner")
        radius = 0
        if corner is not None:
            radius = min(udim(corner.get("CornerRadius"), min(w, h)), min(w, h) / 2)
            style.append(f"border-radius:{radius:.2f}px")
        if abs(rotation) > 1e-6:
            style.append(f"transform:rotate({rotation}deg)")
        if clips:
            style.append("overflow:hidden")

        inner = []
        stroke = first(n, "UIStroke")
        is_text = n["ClassName"] in TEXT
        if stroke is not None and stroke.get("Enabled", True) is not False:
            thick = stroke.get("Thickness", 1)
            st = stroke.get("Transparency", 0)
            sc = stroke.get("Color") or {"r": 0, "g": 0, "b": 0}
            mode = enum(stroke, "ApplyStrokeMode", "Contextual")
            sgrad = first(stroke, "UIGradient")
            if is_text and mode != "Border":
                style.append(f"--text-stroke:{thick}px {rgba(sc['r'], sc['g'], sc['b'], st)}")
            elif sgrad is not None and not clips:
                inner.append(
                    f'<div class="ring" style="left:{-thick}px;top:{-thick}px;width:{w + 2 * thick:.2f}px;'
                    f'height:{h + 2 * thick:.2f}px;padding:{thick}px;border-radius:{radius + thick:.2f}px;'
                    f'opacity:{1 - st:.3f};background:{gradient_css(sgrad, (sc["r"], sc["g"], sc["b"]), 0)}"></div>')
            else:
                color = (sc["r"], sc["g"], sc["b"])
                if sgrad is not None:
                    keys = sgrad["Color"]["keys"]
                    color = tuple(sum(k[i] for k in keys) / len(keys) * color[i - 1] for i in (1, 2, 3))
                style.append(f"outline:{thick}px solid {rgba(*color, st)}")

        padding = first(n, "UIPadding")
        pl = udim(padding.get("PaddingLeft"), w) if padding else 0
        pr = udim(padding.get("PaddingRight"), w) if padding else 0
        ptop = udim(padding.get("PaddingTop"), h) if padding else 0
        pb = udim(padding.get("PaddingBottom"), h) if padding else 0
        cw, ch = w - pl - pr, h - ptop - pb

        if is_text and n.get("Text"):
            tc = n.get("TextColor3") or {"r": 0, "g": 0, "b": 0}
            xa = enum(n, "TextXAlignment", "Center")
            ya = enum(n, "TextYAlignment", "Center")
            justify = {"Left": "flex-start", "Right": "flex-end"}.get(xa, "center")
            align = {"Top": "flex-start", "Bottom": "flex-end"}.get(ya, "center")
            wrap = "normal" if n.get("TextWrapped") or n.get("TextScaled") else "nowrap"
            inner.append(
                f'<div class="txt" style="left:{pl:.2f}px;top:{ptop:.2f}px;width:{cw:.2f}px;height:{ch:.2f}px;'
                f'justify-content:{justify};align-items:{align};text-align:{xa.lower() if xa != "Center" else "center"};'
                f'white-space:{wrap};font-size:{n.get("TextSize", 14)}px;{font_css(n)}'
                f'color:{rgba(tc["r"], tc["g"], tc["b"], n.get("TextTransparency", 0))}">'
                f'<span>{html.escape(n["Text"])}</span></div>')

        self.out.append(f'<div class="g" data-name="{html.escape(n.get("Name", ""))}" style="{";".join(style)}">')
        self.out.extend(inner)
        self.children(n, cw, ch, (pl, ptop), rotated_here)
        self.out.append("</div>")

    def children(self, n, cw, ch, pad, rotated):
        gui_kids = [c for c in n.get("children", []) if c["ClassName"] in GUI and c.get("Visible") is not False]
        layout = first(n, "UIListLayout")
        forced = {}
        if layout is not None and gui_kids:
            horizontal = enum(layout, "FillDirection", "Vertical") == "Horizontal"
            gap = udim(layout.get("Padding"), cw if horizontal else ch)
            order = gui_kids
            if enum(layout, "SortOrder", "LayoutOrder") == "LayoutOrder":
                order = sorted(gui_kids, key=lambda c: c.get("LayoutOrder", 0))
            sizes = [udim2(c.get("Size"), cw, ch) for c in order]
            total = sum(s[0] if horizontal else s[1] for s in sizes) + gap * (len(order) - 1)
            ha = enum(layout, "HorizontalAlignment", "Left")
            va = enum(layout, "VerticalAlignment", "Top")
            if horizontal:
                cursor = {"Left": 0, "Center": (cw - total) / 2, "Right": cw - total}[ha]
            else:
                cursor = {"Top": 0, "Center": (ch - total) / 2, "Bottom": ch - total}[va]
            for c, (sw, sh) in zip(order, sizes):
                if horizontal:
                    cy = {"Top": 0, "Center": (ch - sh) / 2, "Bottom": ch - sh}[va]
                    forced[id(c)] = (pad[0] + cursor, pad[1] + cy)
                    cursor += sw + gap
                else:
                    cx = {"Left": 0, "Center": (cw - sw) / 2, "Right": cw - sw}[ha]
                    forced[id(c)] = (pad[0] + cx, pad[1] + cursor)
                    cursor += sh + gap
        for c in n.get("children", []):
            self.node(c, cw, ch, pad, forced.get(id(c)), rotated)


# Shared CSS for any page that embeds rendered scenes (.screen is one Roblox viewport).
SCENE_CSS = """
.screen{position:relative;overflow:hidden;background:#000;}
.g,.txt,.ring{position:absolute;box-sizing:border-box;}
.txt{display:flex;z-index:0;line-height:1.12;overflow:visible;pointer-events:none;}
.txt span{display:block;}
.ring{z-index:0;-webkit-mask:linear-gradient(#000 0 0) content-box,linear-gradient(#000 0 0);-webkit-mask-composite:xor;mask-composite:exclude;}
"""

PAGE = """<!doctype html><html><head><meta charset="utf-8"><title>{title}</title>
<link rel="stylesheet" href="{fonts}">
<style>html,body{{margin:0;padding:0;background:#000;}}{css}</style></head>
<body><div class="screen" style="width:{w}px;height:{h}px">{body}</div></body></html>
"""


def render_body(tree, width, height):
    r = Renderer()
    for c in tree.get("children", []):
        r.node(c, width, height, (0, 0))
    return "\n".join(r.out), r.count


def render_scene(tree, width, height, title, fonts_href):
    body, count = render_body(tree, width, height)
    return PAGE.format(title=html.escape(title), fonts=fonts_href, css=SCENE_CSS, w=width, h=height, body=body), count


def main():
    tree_path, out_dir, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
    width = int(sys.argv[4]) if len(sys.argv) > 4 else 1280
    height = int(sys.argv[5]) if len(sys.argv) > 5 else 720
    fonts_href = sys.argv[6] if len(sys.argv) > 6 else "fonts/fonts.css"
    data = json.load(open(tree_path, encoding="utf-8"))
    os.makedirs(out_dir, exist_ok=True)
    for scene, tree in data["scenes"].items():
        page, count = render_scene(tree, width, height, f"{prefix} {scene}", fonts_href)
        path = os.path.join(out_dir, f"{prefix}_{scene}.html")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(page)
        print(f"{path}: {count} visible GUI objects")


if __name__ == "__main__":
    main()
