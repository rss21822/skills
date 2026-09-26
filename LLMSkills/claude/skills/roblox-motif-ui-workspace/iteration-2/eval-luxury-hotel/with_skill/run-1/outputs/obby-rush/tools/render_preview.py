#!/usr/bin/env python3
"""Render a GUI tree dumped by tools/dump_menu.luau as HTML (and PNG through headless Chrome).

  python tools/render_preview.py menu.json out.html [--png out.png] [--audit audit.json]

A small layout engine for the subset of Roblox GUI the menu uses: UDim2 size/position with
AnchorPoint, UIListLayout, UIPadding, UIScale, UICorner, UIStroke (border and text), UIGradient
(colour x transparency on the face), ClipsDescendants, ZIndex (sibling order), Rotation (about the
centre), TextScaled + UITextSizeConstraint, AutomaticSize X for text. Fonts are the Google Fonts
look-alikes of the Roblox families; Japanese falls back to Noto Sans JP at the requested weight
(Roblox falls back to its CJK system face the same way).

--audit also writes what a Studio audit would flag, measured in the browser: text that does not
fit its box (FIT), buttons under 48 px (SMALL), buttons outside the screen (OFFSCREEN) and
overlapping buttons (OVERLAP). It approximates Studio; it does not replace it.
"""
import argparse
import html
import json
import os
import shutil
import subprocess
from pathlib import Path

FAMILY = {
    "RomanAntique": "Cinzel", "AccanthisADFStd": "Libre Bodoni", "Merriweather": "Merriweather",
    "GothamSSm": "Montserrat", "Montserrat": "Montserrat", "Nunito": "Nunito", "BuilderSans": "Inter",
    "Guru": "EB Garamond", "JosefinSans": "Josefin Sans", "FredokaOne": "Fredoka One",
}
ENUM_FONT = {"GothamMedium": ("Montserrat", 500), "GothamBold": ("Montserrat", 700), "Gotham": ("Montserrat", 400),
             "GothamBlack": ("Montserrat", 900), "SourceSans": ("Source Sans 3", 400), "SourceSansBold": ("Source Sans 3", 700)}
WEIGHT = {"Thin": 100, "ExtraLight": 200, "Light": 300, "Regular": 400, "Medium": 500, "SemiBold": 600,
          "Bold": 700, "ExtraBold": 800, "Heavy": 900}
CJK = '"Noto Sans JP","Yu Gothic UI",sans-serif'
TEXT_CLASSES = {"TextLabel", "TextButton", "TextBox"}
GUI_CLASSES = TEXT_CLASSES | {"Frame", "ScrollingFrame", "ImageLabel", "ImageButton", "ViewportFrame", "CanvasGroup"}
BUTTONS = {"TextButton", "ImageButton"}
DEFAULT_BORDER = (27 / 255, 42 / 255, 53 / 255)


def prop(node, key, default=None):
    value = node["props"].get(key)
    return default if value is None else value


def color(v, default=(1, 1, 1)):
    return tuple(v[1:4]) if isinstance(v, list) and v and v[0] == "c3" else default


def rgba(c, transparency=0.0):
    return "rgba(%d,%d,%d,%.3f)" % (round(c[0] * 255), round(c[1] * 255), round(c[2] * 255), max(0.0, 1 - transparency))


def udim2(v):
    return tuple(v[1:5]) if isinstance(v, list) and v and v[0] == "u2" else (0, 0, 0, 0)


def udim(v):
    return tuple(v[1:3]) if isinstance(v, list) and v and v[0] == "u" else (0, 0)


def vec2(v, default=(0, 0)):
    return tuple(v[1:3]) if isinstance(v, list) and v and v[0] == "v2" else default


def enum(v):
    return v[1] if isinstance(v, list) and v and v[0] == "enum" else None


def child(node, cls):
    for c in node["children"]:
        if c["class"] == cls:
            return c
    return None


def interp(points, t):
    """Piecewise-linear value of a sequence [[time, *values]] at t."""
    if t <= points[0][0]:
        return points[0][1:]
    for a, b in zip(points, points[1:]):
        if a[0] <= t <= b[0]:
            span = b[0] - a[0] or 1
            f = (t - a[0]) / span
            return [x + (y - x) * f for x, y in zip(a[1:], b[1:])]
    return points[-1][1:]


def face_css(node):
    """Background of a GuiObject, with a UIGradient multiplied in."""
    base = color(prop(node, "BackgroundColor3"))
    bt = prop(node, "BackgroundTransparency", 0)
    grad = child(node, "UIGradient")
    if bt >= 1:
        return ""
    if not grad or grad["props"].get("Enabled") is False:
        return f"background:{rgba(base, bt)};"
    cs = grad["props"].get("Color")
    ns = grad["props"].get("Transparency")
    cpoints = cs[1] if cs else [[0, 1, 1, 1], [1, 1, 1, 1]]
    npoints = ns[1] if ns else [[0, 0], [1, 0]]
    times = sorted({round(p[0], 4) for p in cpoints} | {round(p[0], 4) for p in npoints})
    stops = []
    for t in times:
        c = interp(cpoints, t)
        n = interp(npoints, t)[0]
        mixed = (base[0] * c[0], base[1] * c[1], base[2] * c[2])
        alpha_t = 1 - (1 - bt) * (1 - n)
        stops.append(f"{rgba(mixed, alpha_t)} {t * 100:.2f}%")
    angle = (grad["props"].get("Rotation") or 0) + 90
    return f"background:linear-gradient({angle}deg,{','.join(stops)});"


def font_css(node):
    face = prop(node, "FontFace")
    if isinstance(face, list) and face and face[0] == "font":
        family = FAMILY.get(family_of(node), "Montserrat")
        weight = WEIGHT.get(face[2], 400)
    else:
        family, weight = ENUM_FONT.get(enum(prop(node, "Font")) or "", ("Arimo", 400))
    return f'font-family:"{family}",{CJK};font-weight:{weight};'


def family_of(node):
    face = prop(node, "FontFace")
    if isinstance(face, list) and face and face[0] == "font":
        raw = face[1]
        return raw.split("/")[-1].replace(".json", "") if "/" in raw else raw
    return enum(prop(node, "Font")) or ""


class Renderer:
    def __init__(self, width, height):
        self.width, self.height = width, height
        self.buttons = []  # (name, x, y, w, h) in screen space (approximate: ignores rotation/scale)

    def size_of(self, node, pw, ph):
        xs, xo, ys, yo = udim2(prop(node, "Size", ["u2", 0, 200, 0, 50]))
        w, h = xs * pw + xo, ys * ph + yo
        limit = child(node, "UISizeConstraint")
        if limit:
            mn = vec2(limit["props"].get("MinSize"), (0, 0))
            mx = vec2(limit["props"].get("MaxSize"), (1e9, 1e9))
            w, h = min(max(w, mn[0]), mx[0]), min(max(h, mn[1]), mx[1])
        return w, h

    def padding(self, node, w, h):
        pad = child(node, "UIPadding")
        if not pad:
            return 0, 0, 0, 0
        def px(key, total):
            s, o = udim(pad["props"].get(key))
            return s * total + o
        return px("PaddingLeft", w), px("PaddingTop", h), px("PaddingRight", w), px("PaddingBottom", h)

    def render_children(self, node, w, h, screen_x, screen_y):
        pl, pt, pr, pb = self.padding(node, w, h)
        cw, ch = w - pl - pr, h - pt - pb
        kids = [c for c in node["children"] if c["class"] in GUI_CLASSES and prop(c, "Visible", True) is not False]
        layout = child(node, "UIListLayout")
        placed = []
        if layout:
            order = sorted(enumerate(kids), key=lambda item: (prop(item[1], "LayoutOrder", 0), item[0]))
            horizontal = enum(layout["props"].get("FillDirection")) == "Horizontal"
            gap_s, gap_o = udim(layout["props"].get("Padding"))
            gap = gap_s * (cw if horizontal else ch) + gap_o
            sizes = [self.size_of(k, cw, ch) for _, k in order]
            total = sum(s[0] if horizontal else s[1] for s in sizes) + gap * max(len(sizes) - 1, 0)
            align = enum(layout["props"].get("HorizontalAlignment" if horizontal else "VerticalAlignment")) or ("Left" if horizontal else "Top")
            start = {"Left": 0, "Top": 0, "Center": ((cw if horizontal else ch) - total) / 2,
                     "Right": cw - total, "Bottom": ch - total}.get(align, 0)
            cursor = start
            for (_, k), (sw, sh) in zip(order, sizes):
                x, y = (cursor, 0) if horizontal else (0, cursor)
                cursor += (sw if horizontal else sh) + gap
                placed.append((k, pl + x, pt + y, sw, sh))
        else:
            for k in kids:
                sw, sh = self.size_of(k, cw, ch)
                xs, xo, ys, yo = udim2(prop(k, "Position"))
                ax, ay = vec2(prop(k, "AnchorPoint"))
                placed.append((k, pl + xs * cw + xo - ax * sw, pt + ys * ch + yo - ay * sh, sw, sh))
        placed.sort(key=lambda item: prop(item[0], "ZIndex", 1))  # stable: sibling ZIndex, then order
        return "".join(self.render(k, x, y, sw, sh, screen_x + x, screen_y + y) for k, x, y, sw, sh in placed)

    def render(self, node, x, y, w, h, sx, sy):
        cls = node["class"]
        styles = [f"position:absolute;left:{x:.2f}px;top:{y:.2f}px;height:{h:.2f}px;box-sizing:border-box;"]
        auto_x = enum(prop(node, "AutomaticSize")) in ("X", "XY") and cls in TEXT_CLASSES
        styles.append("width:auto;min-width:0;" if auto_x else f"width:{w:.2f}px;")
        styles.append(face_css(node))
        shadows = []
        border = prop(node, "BorderSizePixel", 0) or 0
        bt = prop(node, "BackgroundTransparency", 0)
        if border > 0 and bt < 1:
            shadows.append(f"0 0 0 {border}px {rgba(color(prop(node, 'BorderColor3'), DEFAULT_BORDER), bt)}")
        corner = child(node, "UICorner")
        if corner:
            s, o = udim(corner["props"].get("CornerRadius") or ["u", 0, 8])
            radius = min(s * min(w, h) + o, min(w, h) / 2)
            styles.append(f"border-radius:{radius:.2f}px;")
        text_stroke = ""
        for stroke in (c for c in node["children"] if c["class"] == "UIStroke"):
            if stroke["props"].get("Enabled") is False:
                continue
            thickness = stroke["props"].get("Thickness") or 1
            t = stroke["props"].get("Transparency") or 0
            c = color(stroke["props"].get("Color"), (0, 0, 0))
            mode = enum(stroke["props"].get("ApplyStrokeMode"))
            if cls in TEXT_CLASSES and mode != "Border":
                text_stroke = f"-webkit-text-stroke:{thickness * 2:.1f}px {rgba(c, t)};paint-order:stroke fill;"
            elif t < 1:
                shadows.append(f"0 0 0 {thickness}px {rgba(c, t)}")
        if shadows:
            styles.append(f"box-shadow:{','.join(shadows)};")
        if prop(node, "ClipsDescendants", False) or cls == "ScrollingFrame":
            styles.append("overflow:hidden;")
        rotation = prop(node, "Rotation", 0) or 0
        scale_node = child(node, "UIScale")
        scale = scale_node["props"].get("Scale", 1) if scale_node else 1
        scale = 1 if scale is None else scale
        ax, ay = vec2(prop(node, "AnchorPoint"))
        if scale != 1:
            styles.append(f"transform-origin:{ax * 100}% {ay * 100}%;transform:scale({scale}) rotate({rotation}deg);")
        elif rotation:
            styles.append(f"transform:rotate({rotation}deg);")
        attrs = f' data-name="{html.escape(node["name"])}"'
        inner = ""
        if cls in TEXT_CLASSES:
            text = prop(node, "Text", "")
            pl, pt, pr, pb = self.padding(node, w, h)
            size = prop(node, "TextSize", 14)
            limit = child(node, "UITextSizeConstraint")
            scaled = bool(prop(node, "TextScaled", False))
            if scaled:
                size = (limit["props"].get("MaxTextSize") if limit else None) or 100
            xa = enum(prop(node, "TextXAlignment")) or "Center"
            ya = enum(prop(node, "TextYAlignment")) or "Center"
            wrap = bool(prop(node, "TextWrapped", False))
            tc = color(prop(node, "TextColor3"), (0, 0, 0))
            tt = prop(node, "TextTransparency", 0) or 0
            justify = {"Left": "flex-start", "Right": "flex-end"}.get(xa, "center")
            align = {"Top": "flex-start", "Bottom": "flex-end"}.get(ya, "center")
            styles.append(f"display:flex;justify-content:{justify};align-items:{align};padding:{pt}px {pr}px {pb}px {pl}px;")
            span_style = (f"{font_css(node)}font-size:{size}px;line-height:1.18;color:{rgba(tc, tt)};{text_stroke}"
                          f"white-space:{'pre-wrap' if wrap else 'pre'};text-align:{xa.lower() if xa in ('Left', 'Right') else 'center'};"
                          f"{'width:100%;' if wrap else ''}")
            min_size = (limit["props"].get("MinTextSize") if limit else None) or 6
            attrs += f' data-text="1" data-scaled="{1 if scaled else 0}" data-min="{min_size}" data-fam="{html.escape(family_of(node))}"'
            inner = f"<span style='{span_style}'>{html.escape(str(text))}</span>"
        if cls in BUTTONS:
            self.buttons.append((node["name"], sx, sy, w * scale, h * scale))
            attrs += ' data-button="1"'
        body = inner + self.render_children(node, w, h, sx, sy)
        return f"<div{attrs} style='{''.join(styles)}'>{body}</div>"

    def page(self, root, title):
        content = self.render_children(root, self.width, self.height, 0, 0)
        fonts = ("https://fonts.googleapis.com/css2?family=Cinzel:wght@400;700&family=Libre+Bodoni:wght@400;700"
                 "&family=Merriweather:wght@400;700;900&family=Montserrat:wght@400;500;700;900"
                 "&family=Noto+Sans+JP:wght@400;500;700;900&display=block")
        script = """
<script>
document.fonts.ready.then(() => {
  const issues = [];
  for (const el of document.querySelectorAll('[data-text]')) {
    const span = el.firstElementChild; if (!span || !span.textContent.trim()) continue;
    if (el.dataset.scaled === '1') {
      let size = parseFloat(span.style.fontSize); const min = parseFloat(el.dataset.min);
      const box = el.getBoundingClientRect();
      while (size > min && (span.scrollWidth > el.clientWidth - 1 || span.offsetHeight > box.height)) { size -= 1; span.style.fontSize = size + 'px'; }
    }
    const styles = getComputedStyle(el);
    const innerW = el.clientWidth - parseFloat(styles.paddingLeft) - parseFloat(styles.paddingRight);
    const innerH = el.clientHeight - parseFloat(styles.paddingTop) - parseFloat(styles.paddingBottom);
    if (el.style.width !== 'auto' && (span.scrollWidth > innerW + 1 || span.offsetHeight > innerH + 2)) {
      issues.push('FIT ' + el.dataset.name + ' "' + span.textContent.slice(0, 24) + '" ' + Math.round(span.scrollWidth) + 'x' + Math.round(span.offsetHeight) + ' in ' + Math.round(innerW) + 'x' + Math.round(innerH));
    }
  }
  document.getElementById('audit').textContent = JSON.stringify(issues);
  document.body.setAttribute('data-ready', '1');
});
</script>"""
        return (f"<!doctype html><html><head><meta charset='utf-8'><title>{html.escape(title)}</title>"
                f"<link rel='stylesheet' href='{fonts}'><style>html,body{{margin:0;background:#000;}}"
                f"#screen{{position:relative;width:{self.width}px;height:{self.height}px;overflow:hidden;background:#3a4a5a;}}"
                f"#audit{{display:none}}</style></head><body><div id='screen'>{content}</div><pre id='audit'></pre>{script}</body></html>")


def chrome():
    candidates = [shutil.which(n) for n in ("chrome", "google-chrome", "chromium", "msedge")]
    candidates += [r"C:\Program Files\Google\Chrome\Application\chrome.exe",
                   r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
                   r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"]
    return next((c for c in candidates if c and os.path.exists(c)), None)


def static_audit(renderer):
    issues = []
    for name, x, y, w, h in renderer.buttons:
        if w < 48 or h < 48:
            issues.append(f"SMALL {name} {w:.0f}x{h:.0f}")
        if x < 0 or y < 0 or x + w > renderer.width + 0.5 or y + h > renderer.height + 0.5:
            issues.append(f"OFFSCREEN {name} at {x:.0f},{y:.0f} {w:.0f}x{h:.0f}")
    for i, a in enumerate(renderer.buttons):
        for b in renderer.buttons[i + 1:]:
            ix = min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1])
            iy = min(a[2] + a[4], b[2] + b[4]) - max(a[2], b[2])
            if ix > 0 and iy > 0 and ix * iy > 0.2 * min(a[3] * a[4], b[3] * b[4]):
                issues.append(f"OVERLAP {a[0]} / {b[0]}")
    return issues


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dump")
    ap.add_argument("html")
    ap.add_argument("--png")
    ap.add_argument("--audit")
    args = ap.parse_args()
    data = json.loads(Path(args.dump).read_text(encoding="utf-8"))
    renderer = Renderer(data["width"], data["height"])
    Path(args.html).write_text(renderer.page(data["root"], f"{data['scene']} {data['width']}x{data['height']}"), encoding="utf-8")
    print("html:", args.html)
    exe = chrome()
    url = Path(args.html).resolve().as_uri()
    base = [exe, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--virtual-time-budget=15000",
            f"--window-size={data['width']},{data['height']}"] if exe else None
    if args.png and base:
        subprocess.run(base + [f"--screenshot={Path(args.png).resolve()}", url], check=True, timeout=120, capture_output=True)
        print("png:", args.png)
    if args.audit:
        issues = static_audit(renderer)
        if base:
            dom = subprocess.run(base + ["--dump-dom", url], check=True, timeout=120, capture_output=True).stdout.decode("utf-8", "replace")
            start = dom.find("<pre id=\"audit\">")
            end = dom.find("</pre>", start)
            if start >= 0 and end > start:
                raw = html.unescape(dom[start + len("<pre id=\"audit\">"):end])
                issues += json.loads(raw) if raw.strip() else ["AUDIT-SCRIPT-DID-NOT-RUN"]
        Path(args.audit).write_text(json.dumps({"scene": data["scene"], "size": [data["width"], data["height"]],
                                                "issues": issues}, ensure_ascii=False, indent=1), encoding="utf-8")
        print("audit:", args.audit, "-", len(issues), "issue(s)")
        for issue in issues:
            print("  ", issue)


if __name__ == "__main__":
    main()
