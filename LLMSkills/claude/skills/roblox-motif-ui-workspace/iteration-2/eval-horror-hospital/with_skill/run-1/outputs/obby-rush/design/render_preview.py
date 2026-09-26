#!/usr/bin/env python3
"""Draw a GUI tree dumped by design/dump_menu.luau the way Roblox lays it out, and audit it.

  python design/render_preview.py dump.json --html out.html [--png out.png] [--audit]

Layout follows Roblox rules for what the menu uses: UDim2 size/position relative to the parent's
content box, AnchorPoint, UIPadding, UIListLayout (horizontal / vertical, alignment, padding,
Wraps), UISizeConstraint, UIScale (around the anchor point), ZIndex in Sibling mode, UICorner,
UIStroke (Border = outside the edge, Contextual = text outline), UIGradient (multiplies colour and
transparency), TextScaled with UITextSizeConstraint, ClipsDescendants. Fonts use the Google Fonts
twins of the Roblox families; Japanese falls back to Noto Sans JP at the requested weight, as
Roblox falls back to the system CJK face.

Audit (printed, and in the HTML): text contrast against what is actually painted behind it,
touch targets >= 48 px after UIScale, nothing interactive or textual under Roblox's top bar
(top 58 px), nothing interactive off-screen, overlapping buttons, and text that does not fit its
box (measured by the browser, via --dump-dom).
"""
import argparse
import html
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

TOPBAR = 58
WORLD = (0.14, 0.16, 0.15)  # the 3D scene behind the 8 % see-through background
GUI_CLASSES = {"Frame", "TextLabel", "TextButton", "TextBox", "ScrollingFrame", "ImageLabel", "ImageButton", "ViewportFrame", "CanvasGroup"}
TEXT_CLASSES = {"TextLabel", "TextButton", "TextBox"}
BUTTONS = {"TextButton", "ImageButton"}
CSS_FAMILY = {"SpecialElite": "Special Elite", "Oswald": "Oswald", "Arimo": "Arimo", "RobotoMono": "Roboto Mono",
              "FredokaOne": "Fredoka One", "Nunito": "Nunito", "GothamSSm": "Montserrat", "BuilderSans": "Inter"}
LEGACY_FONT = {"ArimoBold": ("Arimo", 700), "Arimo": ("Arimo", 400), "GothamBold": ("Montserrat", 700), "GothamMedium": ("Montserrat", 500)}
WEIGHT = {"Thin": 100, "ExtraLight": 200, "Light": 300, "Regular": 400, "Medium": 500, "SemiBold": 600, "Bold": 700, "ExtraBold": 800, "Heavy": 900}
CJK = '"Noto Sans JP","Yu Gothic UI","Meiryo",sans-serif'
DECORATIVE_TEXT = {"Room"}  # door numbers far in the backdrop, deliberately faint


class Node:
    def __init__(self, data, parent=None, index=0):
        self.name, self.cls, self.p = data["name"], data["class"], data["props"]
        self.parent, self.index = parent, index
        self.children = [Node(c, self, i) for i, c in enumerate(data["children"])]

    def child(self, cls):
        return next((c for c in self.children if c.cls == cls), None)

    def is_gui(self):
        return self.cls in GUI_CLASSES

    def path(self):
        parts, n = [], self
        while n is not None and n.cls != "ScreenGui":
            parts.append(n.name)
            n = n.parent
        return ".".join(reversed(parts))


def u2(v, default=(0, 0, 0, 0)):
    return (v["xs"], v["xo"], v["ys"], v["yo"]) if v else default


def col(v, default=(1, 1, 1)):
    return (v["r"], v["g"], v["b"]) if v else default


def enum(v, default=None):
    return v["name"] if isinstance(v, dict) and v.get("t") == "Enum" else default


def udim(v):
    return (v["s"], v["o"]) if v else (0, 0)


def rgba(c, alpha=1.0):
    return "rgba(%d,%d,%d,%.3f)" % (round(c[0] * 255), round(c[1] * 255), round(c[2] * 255), max(0, min(1, alpha)))


def lerp_seq(keys, t):
    if t <= keys[0][0]:
        return keys[0][1:]
    for a, b in zip(keys, keys[1:]):
        if a[0] <= t <= b[0]:
            f = 0 if b[0] == a[0] else (t - a[0]) / (b[0] - a[0])
            return tuple(x + (y - x) * f for x, y in zip(a[1:], b[1:]))
    return keys[-1][1:]


def rel(c):
    def ch(v):
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * ch(c[0]) + 0.7152 * ch(c[1]) + 0.0722 * ch(c[2])


def contrast(a, b):
    la, lb = sorted((rel(a), rel(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def blend(top, under, alpha):
    return tuple(t * alpha + u * (1 - alpha) for t, u in zip(top, under))


class Layout:
    """Computes each GuiObject's box in its parent's content space and its transform to the screen."""

    def __init__(self, root, width, height):
        self.root, self.W, self.H = root, width, height
        self.box = {}    # node -> (x, y, w, h) in the parent's content space
        self.xf = {}     # node -> (scale, ox, oy): node-local -> screen
        self.pad = {}    # node -> (l, t, r, b)
        self.scale = {}  # node -> UIScale
        self.paint = []  # paint order of visible GuiObjects: (node, screen rect)
        self.visible = set()
        for top in root.children:
            if top.is_gui():
                self.place(top, width, height, (1.0, 0.0, 0.0))

    def padding(self, node, w, h):
        pad = node.child("UIPadding")
        if not pad:
            return (0, 0, 0, 0)
        l, t, r, b = (udim(pad.p.get(k)) for k in ("PaddingLeft", "PaddingTop", "PaddingRight", "PaddingBottom"))
        return (l[0] * w + l[1], t[0] * h + t[1], r[0] * w + r[1], b[0] * h + b[1])

    def size_of(self, node, pw, ph):
        xs, xo, ys, yo = u2(node.p.get("Size"), (0, 100, 0, 100))
        w, h = pw * xs + xo, ph * ys + yo
        cons = node.child("UISizeConstraint")
        if cons:
            mn, mx = cons.p.get("MinSize"), cons.p.get("MaxSize")
            if mx:
                w, h = min(w, mx["x"]), min(h, mx["y"])
            if mn:
                w, h = max(w, mn["x"]), max(h, mn["y"])
        return w, h

    # Recursive placement: `node` gets box (x, y, w, h) in parent content space, parent_xf maps that space to screen.
    def place(self, node, pw, ph, parent_xf, x=None, y=None, w=None, h=None):
        if node.p.get("Visible") is False:
            return
        if w is None:
            w, h = self.size_of(node, pw, ph)
        if x is None:
            px_s, px_o, py_s, py_o = u2(node.p.get("Position"))
            anchor = node.p.get("AnchorPoint") or {"x": 0, "y": 0}
            x = pw * px_s + px_o - anchor["x"] * w
            y = ph * py_s + py_o - anchor["y"] * h
        self.box[node] = (x, y, w, h)
        anchor = node.p.get("AnchorPoint") or {"x": 0, "y": 0}
        scale_node = node.child("UIScale")
        k = scale_node.p.get("Scale", 1) if scale_node else 1
        self.scale[node] = k
        pivot = (x + anchor["x"] * w, y + anchor["y"] * h)
        s0, ox0, oy0 = parent_xf
        # local p -> parent space: pivot + k * ((x, y) + p - pivot)
        lx, ly = pivot[0] + k * (x - pivot[0]), pivot[1] + k * (y - pivot[1])
        xf = (s0 * k, s0 * lx + ox0, s0 * ly + oy0)
        self.xf[node] = xf
        self.visible.add(node)
        self.paint.append((node, (xf[1], xf[2], w * xf[0], h * xf[0])))
        pad = self.padding(node, w, h)
        self.pad[node] = pad
        cw, ch = w - pad[0] - pad[2], h - pad[1] - pad[3]
        child_xf = (xf[0], xf[1] + xf[0] * pad[0], xf[2] + xf[0] * pad[1])
        guis = [c for c in node.children if c.is_gui()]
        order = sorted(guis, key=lambda c: (c.p.get("ZIndex", 1), c.index))
        layout = node.child("UIListLayout")
        placed = {}
        if layout:
            placed = self.list_layout(layout, [c for c in guis if c.p.get("Visible") is not False], cw, ch)
        for c in order:
            if c in placed:
                bx, by, bw, bh = placed[c]
                self.place(c, cw, ch, child_xf, bx, by, bw, bh)
            else:
                self.place(c, cw, ch, child_xf)

    def list_layout(self, layout, items, cw, ch):
        horizontal = enum(layout.p.get("FillDirection"), "Vertical") == "Horizontal"
        ps, po = udim(layout.p.get("Padding"))
        gap = ps * (cw if horizontal else ch) + po
        halign = enum(layout.p.get("HorizontalAlignment"), "Left")
        valign = enum(layout.p.get("VerticalAlignment"), "Top")
        items = sorted(items, key=lambda c: (c.p.get("LayoutOrder", 0), c.index))
        sizes = {c: self.size_of(c, cw, ch) for c in items}
        main_len = cw if horizontal else ch
        lines, line, used = [], [], 0
        for c in items:
            m = sizes[c][0] if horizontal else sizes[c][1]
            if layout.p.get("Wraps") and line and used + gap + m > main_len + 0.5:
                lines.append(line)
                line, used = [], 0
            used = m if not line else used + gap + m
            line.append(c)
        if line:
            lines.append(line)
        fac = {"Left": 0, "Top": 0, "Center": 0.5, "Right": 1, "Bottom": 1}
        main_f = fac[halign] if horizontal else fac[valign]
        cross_f = fac[valign] if horizontal else fac[halign]
        cross_sizes = [max((sizes[c][1] if horizontal else sizes[c][0]) for c in ln) for ln in lines]
        cross_total = sum(cross_sizes) + gap * (len(lines) - 1)
        cross_len = ch if horizontal else cw
        cross_pos = (cross_len - cross_total) * cross_f if len(lines) > 1 else 0
        out = {}
        for ln, csize in zip(lines, cross_sizes):
            total = sum((sizes[c][0] if horizontal else sizes[c][1]) for c in ln) + gap * (len(ln) - 1)
            pos = (main_len - total) * main_f
            for c in ln:
                w, h = sizes[c]
                m, cr = (w, h) if horizontal else (h, w)
                span = csize if len(lines) > 1 else cross_len
                off = cross_pos + (span - cr) * cross_f
                out[c] = (pos, off, w, h) if horizontal else (off, pos, w, h)
                pos += m + gap
            cross_pos += csize + gap
        return out


def gradient_css(node, base, alpha):
    grad = node.child("UIGradient")
    if not grad:
        return None
    cs = grad.p.get("Color")
    ns = grad.p.get("Transparency")
    ckeys = cs["k"] if cs else [[0, 1, 1, 1], [1, 1, 1, 1]]
    nkeys = ns["k"] if ns else [[0, 0], [1, 0]]
    times = sorted({k[0] for k in ckeys} | {k[0] for k in nkeys})
    stops = []
    for t in times:
        c = lerp_seq(ckeys, t)
        tr = lerp_seq(nkeys, t)[0]
        colour = tuple(b * m for b, m in zip(base, c))
        stops.append("%s %.2f%%" % (rgba(colour, alpha * (1 - tr)), t * 100))
    return "linear-gradient(%.0fdeg,%s)" % (grad.p.get("Rotation", 0) + 90, ",".join(stops))


def gradient_at(node, base, alpha, fx, fy):
    """Colour and alpha of a gradient-filled node at fractional point (fx, fy)."""
    grad = node.child("UIGradient")
    if not grad:
        return base, alpha
    rot = grad.p.get("Rotation", 0) % 360
    t = {0: fx, 90: fy, 180: 1 - fx, 270: 1 - fy}.get(round(rot), fx)
    cs, ns = grad.p.get("Color"), grad.p.get("Transparency")
    c = lerp_seq(cs["k"], t) if cs else (1, 1, 1)
    tr = lerp_seq(ns["k"], t)[0] if ns else 0
    return tuple(b * m for b, m in zip(base, c)), alpha * (1 - tr)


def font_css(node):
    face = node.p.get("FontFace")
    if face:
        fam = face["family"].split("/")[-1].replace(".json", "")
        return CSS_FAMILY.get(fam, fam), WEIGHT.get(face.get("weight", "Regular"), 400)
    legacy = enum(node.p.get("Font"))
    return LEGACY_FONT.get(legacy, ("Arimo", 700))


def is_text_stroke(node, stroke):
    return node.cls in TEXT_CLASSES and enum(stroke.p.get("ApplyStrokeMode"), "Contextual") != "Border"


def render_node(lay, node):
    if node not in lay.visible:
        return ""
    x, y, w, h = lay.box[node]
    ppad = lay.pad.get(node.parent, (0, 0, 0, 0))  # box is in the parent's padded content space
    x, y = x + ppad[0], y + ppad[1]
    p = node.p
    styles = [f"left:{x:.1f}px", f"top:{y:.1f}px", f"width:{w:.1f}px", f"height:{h:.1f}px", f"z-index:{p.get('ZIndex', 1)}"]
    anchor = p.get("AnchorPoint") or {"x": 0, "y": 0}
    transforms = []
    k = lay.scale.get(node, 1)
    if abs(k - 1) > 1e-4:
        transforms.append(f"scale({k:.4f})")
        styles.append(f"transform-origin:{anchor['x'] * 100:.0f}% {anchor['y'] * 100:.0f}%")
    if p.get("Rotation"):
        transforms.append(f"rotate({p['Rotation']:.2f}deg)")
    if transforms:
        styles.append("transform:" + " ".join(transforms))
    bt = p.get("BackgroundTransparency", 1 if node.cls in TEXT_CLASSES else 0)
    base = col(p.get("BackgroundColor3"))
    if node.cls != "ScrollingFrame" and bt < 1:
        g = gradient_css(node, base, 1 - bt)
        styles.append(f"background:{g}" if g else f"background:{rgba(base, 1 - bt)}")
    corner = node.child("UICorner")
    if corner:
        s, o = udim(corner.p.get("CornerRadius"))
        r = min(s * min(w, h) + o, min(w, h) / 2)
        styles.append(f"border-radius:{r:.1f}px")
    for stroke in [c for c in node.children if c.cls == "UIStroke"]:
        if stroke.p.get("Enabled") is False or is_text_stroke(node, stroke):
            continue
        t = stroke.p.get("Thickness", 1)
        styles.append(f"box-shadow:0 0 0 {t:.1f}px {rgba(col(stroke.p.get('Color'), (0, 0, 0)), 1 - stroke.p.get('Transparency', 0))}")
        break
    if p.get("ClipsDescendants") or node.cls == "ScrollingFrame":
        styles.append("overflow:hidden")
    inner = ""
    if node.cls in TEXT_CLASSES and p.get("Text"):
        pad = lay.pad.get(node, (0, 0, 0, 0))
        fam, weight = font_css(node)
        xa = enum(p.get("TextXAlignment"), "Center")
        ya = enum(p.get("TextYAlignment"), "Center")
        just = {"Left": "flex-start", "Center": "center", "Right": "flex-end"}[xa]
        align = {"Top": "flex-start", "Center": "center", "Bottom": "flex-end"}[ya]
        colour = rgba(col(p.get("TextColor3"), (0, 0, 0)), 1 - p.get("TextTransparency", 0))
        tstroke = ""
        for stroke in [c for c in node.children if c.cls == "UIStroke"]:
            if is_text_stroke(node, stroke) and stroke.p.get("Enabled") is not False:
                tstroke = (f"-webkit-text-stroke:{stroke.p.get('Thickness', 1) * 2:.1f}px "
                           f"{rgba(col(stroke.p.get('Color'), (0, 0, 0)), 1 - stroke.p.get('Transparency', 0))};paint-order:stroke fill;")
        size = p.get("TextSize", 14)
        scaled = ""
        if p.get("TextScaled"):
            cons = node.child("UITextSizeConstraint")
            mx = cons.p.get("MaxTextSize", 100) if cons else 100
            mn = cons.p.get("MinTextSize", 1) if cons else 1
            scaled = f" data-scaled='1' data-max='{mx}' data-min='{mn}'"
            size = mx
        wrap = "pre-wrap" if p.get("TextWrapped") and not p.get("TextScaled") else "pre"
        inner = (f"<div class='t' data-path='{html.escape(node.path())}'{scaled} style='left:{pad[0]:.1f}px;top:{pad[1]:.1f}px;"
                 f"width:{w - pad[0] - pad[2]:.1f}px;height:{h - pad[1] - pad[3]:.1f}px;justify-content:{just};align-items:{align};"
                 f"text-align:{xa.lower()};font-family:\"{fam}\",{CJK};font-weight:{weight};font-size:{size}px;color:{colour};"
                 f"white-space:{wrap};{tstroke}'>{html.escape(p['Text'])}</div>")
    kids = "".join(render_node(lay, c) for c in node.children if c.is_gui())
    return f"<div class='n' title='{html.escape(node.path())}' style='{';'.join(styles)}'>{inner}{kids}</div>"


FIT_JS = """
<script>
document.fonts.ready.then(() => {
  const fits = [];
  document.querySelectorAll('.t').forEach(el => {
    if (el.dataset.scaled) {
      let size = +el.dataset.max; const min = +el.dataset.min;
      el.style.fontSize = size + 'px';
      while (size > min && (el.scrollWidth > el.clientWidth + 1 || el.scrollHeight > el.clientHeight + 1)) {
        size -= 1; el.style.fontSize = size + 'px';
      }
    }
    const over = el.scrollWidth - el.clientWidth, overY = el.scrollHeight - el.clientHeight;
    if (over > 2 || overY > 4) fits.push('FIT ' + el.dataset.path + ' over by ' + Math.max(over, 0) + 'x' + Math.max(overY, 0) + 'px');
  });
  document.getElementById('fit').textContent = fits.join('\\n') || 'fit ok';
  document.body.dataset.done = '1';
});
</script>"""


def audit(lay, root):
    issues, notes = [], []
    paint = lay.paint
    index = {n: i for i, (n, _) in enumerate(paint)}
    layer = {}
    for n, _ in paint:
        a = n
        while a.parent is not None and a.parent.cls != "ScreenGui":
            a = a.parent
        layer[n] = a
    rect = {n: r for n, r in paint}

    def descendant(a, b):
        n = a.parent
        while n is not None:
            if n is b:
                return True
            n = n.parent
        return False

    def backdrop(node, px, py):
        colour = WORLD
        for other, (x, y, w, h) in paint[: index[node] + 1]:
            bt = other.p.get("BackgroundTransparency", 1 if other.cls in TEXT_CLASSES else 0)
            if other.cls == "ScrollingFrame" or bt >= 1 or not (x <= px <= x + w and y <= py <= y + h):
                continue
            c, a = gradient_at(other, col(other.p.get("BackgroundColor3")), 1 - bt, (px - x) / max(w, 1), (py - y) / max(h, 1))
            colour = blend(c, colour, a)
        return colour

    checked = 0
    for node, (x, y, w, h) in paint:
        p = node.p
        if node.cls in TEXT_CLASSES and p.get("Text") and p.get("TextTransparency", 0) < 1 and node.name not in DECORATIVE_TEXT:
            pad = lay.pad.get(node, (0, 0, 0, 0))
            s = lay.xf[node][0]
            px, py = x + s * (pad[0] + (w / s - pad[0] - pad[2]) / 2), y + s * (pad[1] + (h / s - pad[1] - pad[3]) / 2)
            bg = backdrop(node, px, py)
            fg = blend(col(p.get("TextColor3"), (0, 0, 0)), bg, 1 - p.get("TextTransparency", 0))
            ratio = contrast(fg, bg)
            size = p.get("TextSize", 14) * s
            need = 3.0 if size >= 24 or p.get("TextScaled") else 4.5
            checked += 1
            if ratio < need:
                issues.append(f"CONTRAST {node.path()} {ratio:.2f}:1 < {need} (text {size:.0f}px)")
        if node.cls in BUTTONS:
            if w < 48 - 0.5 or h < 48 - 0.5:
                issues.append(f"SMALL {node.path()} {w:.0f}x{h:.0f}")
        interactive_or_text = node.cls in BUTTONS or (node.cls in TEXT_CLASSES and p.get("Text") and node.name not in DECORATIVE_TEXT)
        if interactive_or_text and p.get("TextTransparency", 0) < 1 or node.cls in BUTTONS:
            if y < TOPBAR - 0.5:
                issues.append(f"TOPBAR {node.path()} top at {y:.0f}px (< {TOPBAR})")
            if x < -0.5 or y < -0.5 or x + w > lay.W + 0.5 or y + h > lay.H + 0.5:
                issues.append(f"OFFSCREEN {node.path()} {x:.0f},{y:.0f} {w:.0f}x{h:.0f}")
    buttons = [(n, r) for n, r in paint if n.cls in BUTTONS]
    for i, (a, ra) in enumerate(buttons):
        for b, rb_ in buttons[i + 1:]:
            if layer[a] is not layer[b] or descendant(a, b) or descendant(b, a):
                continue
            ix = min(ra[0] + ra[2], rb_[0] + rb_[2]) - max(ra[0], rb_[0])
            iy = min(ra[1] + ra[3], rb_[1] + rb_[3]) - max(ra[1], rb_[1])
            if ix > 1 and iy > 1:
                issues.append(f"OVERLAP {a.path()} x {b.path()}")
    texts = [(n, r) for n, r in paint if n.cls == "TextLabel" and n.p.get("Text") and n.name not in DECORATIVE_TEXT]
    for t, rt in texts:
        for b, rb_ in buttons:
            if layer[t] is not layer[b] or descendant(t, b):
                continue
            ix = min(rt[0] + rt[2], rb_[0] + rb_[2]) - max(rt[0], rb_[0])
            iy = min(rt[1] + rt[3], rb_[1] + rb_[3]) - max(rt[1], rb_[1])
            if ix > 1 and iy > 1:
                issues.append(f"OVERLAP text {t.path()} over button {b.path()}")
    notes.append(f"{checked} text elements checked for contrast, {len(buttons)} buttons for size/position")
    return issues, notes


def find_browser():
    for c in [shutil.which(n) for n in ("chrome", "google-chrome", "chromium", "msedge")] + [
            r"C:\Program Files\Google\Chrome\Application\chrome.exe", r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
            r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"]:
        if c and os.path.exists(c):
            return c
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dump")
    ap.add_argument("--html", required=True)
    ap.add_argument("--png")
    ap.add_argument("--label", default="")
    args = ap.parse_args()
    data = json.loads(Path(args.dump).read_text(encoding="utf-8"))
    width, height = data["viewport"]
    root = Node(data["tree"])
    lay = Layout(root, width, height)
    issues, notes = audit(lay, root)
    for w in data.get("warnings") or []:
        issues.append("LUAU WARN " + w)
    body = "".join(render_node(lay, c) for c in root.children if c.is_gui())
    fonts = ("https://fonts.googleapis.com/css2?family=Special+Elite&family=Oswald:wght@500;700&family=Arimo:wght@400;700"
             "&family=Roboto+Mono:wght@700&family=Noto+Sans+JP:wght@700;900&display=block")
    audit_text = "\n".join(issues + notes)
    doc = f"""<!doctype html><html><head><meta charset='utf-8'><title>{html.escape(args.label or 'preview')}</title>
<link rel='stylesheet' href='{fonts}'>
<style>html,body{{margin:0;padding:0;background:#111}} #stage{{position:relative;width:{width}px;height:{height}px;overflow:hidden;
background:{rgba(WORLD)}}} .n{{position:absolute;box-sizing:border-box;isolation:isolate}}
.t{{position:absolute;display:flex;line-height:1.12;overflow:visible}} pre{{display:none}}</style></head>
<body><div id='stage'>{body}</div><pre id='audit'>{html.escape(audit_text)}</pre><pre id='fit'></pre>{FIT_JS}</body></html>"""
    Path(args.html).write_text(doc, encoding="utf-8")
    browser = find_browser()
    fit_lines = []
    if browser:
        url = Path(args.html).resolve().as_uri()
        try:
            dom = subprocess.run([browser, "--headless=new", "--disable-gpu", "--virtual-time-budget=8000", "--dump-dom", url],
                                 capture_output=True, timeout=120).stdout.decode("utf-8", "replace")
            m = re.search(r"<pre id=\"fit\">(.*?)</pre>", dom, re.S)
            fit_lines = [l for l in html.unescape(m.group(1)).splitlines() if l.startswith("FIT")] if m else ["FIT audit did not run"]
        except Exception as exc:  # noqa: BLE001
            fit_lines = [f"FIT audit failed: {exc}"]
        if args.png:
            subprocess.run([browser, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--virtual-time-budget=8000",
                            f"--window-size={width},{height}", f"--screenshot={Path(args.png).resolve()}", url],
                           capture_output=True, timeout=120)
    issues += fit_lines
    label = args.label or Path(args.dump).stem
    print(f"[{label}] {width}x{height}: {len(issues)} issue(s)")
    for line in issues + notes:
        print("   " + line)
    return len(issues)


if __name__ == "__main__":
    sys.exit(1 if main() else 0)
