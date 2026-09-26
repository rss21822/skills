"""Render a dumped MainMenu instance tree (dump_tree.luau) to HTML and a Chrome screenshot.

This is an approximation of Roblox's GUI renderer, good enough to judge composition, colour,
layering and text fit without Studio:
  UDim2 layout, AnchorPoint, Rotation (inherited), ZIndex (Sibling), ClipsDescendants,
  UIListLayout, UICorner, UIStroke (Border -> gradient ring, Contextual -> text glow),
  UIGradient (colour x transparency, also tints text), UIScale, TextStroke.
Fonts are substitutes (Fredoka One / Nunito are not installed here): Segoe UI + Yu Gothic UI.

usage: python render_preview.py tree.json out.png   (writes out.html next to out.png)
"""
import html
import json
import os
import subprocess
import sys

CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
GUI_CLASSES = {"Frame", "TextLabel", "TextButton", "ScrollingFrame", "ImageLabel", "ImageButton", "CanvasGroup"}
TEXT_CLASSES = {"TextLabel", "TextButton"}


def udim2(v, pw, ph):
    return pw * v["xs"] + v["xo"], ph * v["ys"] + v["yo"]


def rgba(c, a):
    return "rgba(%d,%d,%d,%.3f)" % (round(c["r"] * 255), round(c["g"] * 255), round(c["b"] * 255), max(0.0, min(1.0, a)))


def mul(c, k):
    return {"r": c["r"] * k["r"], "g": c["g"] * k["g"], "b": c["b"] * k["b"]}


def sample(points, t, is_color):
    pts = sorted(points, key=lambda p: p[0])
    if t <= pts[0][0]:
        return pts[0][1]
    for (t0, v0), (t1, v1) in zip(pts, pts[1:]):
        if t0 <= t <= t1:
            f = 0 if t1 == t0 else (t - t0) / (t1 - t0)
            if is_color:
                return {k: v0[k] + (v1[k] - v0[k]) * f for k in ("r", "g", "b")}
            return v0 + (v1 - v0) * f
    return pts[-1][1]


def child(node, cls):
    for c in node["children"]:
        if c["ClassName"] == cls:
            return c
    return None


def gradient_css(color, alpha, grad):
    """CSS linear-gradient for a base colour/alpha modulated by a UIGradient dump."""
    p = grad["props"]
    cseq = p.get("Color")
    tseq = p.get("Transparency")
    times = {0.0, 1.0}
    if cseq:
        times |= {pt[0] for pt in cseq["points"]}
    if tseq:
        times |= {pt[0] for pt in tseq["points"]}
    stops = []
    for t in sorted(times):
        c = sample(cseq["points"], t, True) if cseq else {"r": 1, "g": 1, "b": 1}
        tr = sample(tseq["points"], t, False) if tseq else 0
        stops.append("%s %.1f%%" % (rgba(mul(color, c), alpha * (1 - tr)), t * 100))
    angle = (p.get("Rotation") or 0) + 90
    return "linear-gradient(%.1fdeg, %s)" % (angle, ", ".join(stops))


def radius_px(corner, w, h):
    if not corner:
        return 0
    r = corner["props"].get("CornerRadius", {"s": 0, "o": 8})
    px = r["s"] * min(w, h) + r["o"]
    return min(px, min(w, h) / 2)


def font_css(face):
    fam = (face or {}).get("family", "")
    weight = 600
    if "FredokaOne" in fam:
        return "'Segoe UI Black','Segoe UI','Yu Gothic UI',sans-serif", 900
    w = (face or {}).get("weight") or ""
    if "ExtraBold" in w:
        weight = 800
    elif "Bold" in w:
        weight = 700
    return "'Segoe UI','Yu Gothic UI',sans-serif", weight


ALIGN_X = {"Left": "flex-start", "Right": "flex-end", "Center": "center"}
ALIGN_Y = {"Top": "flex-start", "Bottom": "flex-end", "Center": "center"}


def enum_name(v, default):
    return v.split(".")[-1] if isinstance(v, str) else default


def render(node, pw, ph, placed=None, out=None):
    """Emit a div for a GuiObject (recursively). placed = (x, y) from a parent UIListLayout."""
    p = node["props"]
    if node["ClassName"] not in GUI_CLASSES:
        return
    w, h = udim2(p.get("Size", {"xs": 0, "xo": 100, "ys": 0, "yo": 100}), pw, ph)
    if placed:
        x, y = placed
    else:
        px, py = udim2(p.get("Position", {"xs": 0, "xo": 0, "ys": 0, "yo": 0}), pw, ph)
        a = p.get("AnchorPoint", {"x": 0, "y": 0})
        x, y = px - a["x"] * w, py - a["y"] * h
    styles = ["position:absolute", "left:%.2fpx" % x, "top:%.2fpx" % y, "width:%.2fpx" % w, "height:%.2fpx" % h,
              "z-index:%d" % p.get("ZIndex", 1), "box-sizing:border-box"]
    if p.get("Visible") is False:
        styles.append("display:none")
    transforms = []
    if p.get("Rotation"):
        transforms.append("rotate(%.2fdeg)" % p["Rotation"])
    scale = child(node, "UIScale")
    if scale and scale["props"].get("Scale", 1) != 1:
        transforms.append("scale(%.3f)" % scale["props"]["Scale"])
    if transforms:
        styles.append("transform:" + " ".join(transforms))
    corner = child(node, "UICorner")
    rad = radius_px(corner, w, h)
    if rad:
        styles.append("border-radius:%.2fpx" % rad)
    grad = child(node, "UIGradient")
    bt = p.get("BackgroundTransparency", 1)
    bg = p.get("BackgroundColor3", {"r": 1, "g": 1, "b": 1})
    if bt < 1:
        if grad:
            styles.append("background:" + gradient_css(bg, 1 - bt, grad))
        else:
            styles.append("background:" + rgba(bg, 1 - bt))
    if p.get("ClipsDescendants") or node["ClassName"] == "ScrollingFrame":
        styles.append("overflow:hidden")

    inner = []
    # UIStroke
    for s in node["children"]:
        if s["ClassName"] != "UIStroke":
            continue
        sp = s["props"]
        mode = enum_name(sp.get("ApplyStrokeMode"), "Contextual")
        color = sp.get("Color", {"r": 0, "g": 0, "b": 0})
        thick = sp.get("Thickness", 1)
        alpha = 1 - sp.get("Transparency", 0)
        if node["ClassName"] in TEXT_CLASSES and mode == "Contextual":
            c = rgba(color, alpha)
            styles.append("text-shadow:0 0 %.1fpx %s,0 0 %.1fpx %s,0 0 %.1fpx %s" % (thick, c, thick * 2.5, c, thick * 5, c))
            continue
        sg = child(s, "UIGradient")
        fill = gradient_css(color, alpha, sg) if sg else rgba(color, alpha)
        inner.append(
            '<div class="stroke" style="position:absolute;left:%.2fpx;top:%.2fpx;width:%.2fpx;height:%.2fpx;padding:%.2fpx;'
            'border-radius:%.2fpx;background:%s;box-sizing:border-box;z-index:0;pointer-events:none;'
            '-webkit-mask:linear-gradient(#000 0 0) content-box,linear-gradient(#000 0 0);-webkit-mask-composite:xor;'
            'mask-composite:exclude"></div>' % (-thick, -thick, w + 2 * thick, h + 2 * thick, thick, rad + thick if rad else 0, fill))

    text_html = ""
    if node["ClassName"] in TEXT_CLASSES and p.get("Text"):
        tc = p.get("TextColor3", {"r": 0, "g": 0, "b": 0})
        if grad and grad["props"].get("Color"):
            tc = mul(tc, sample(grad["props"]["Color"]["points"], 0.5, True))
        ta = 1 - p.get("TextTransparency", 0)
        fam, weight = font_css(p.get("FontFace"))
        xa = ALIGN_X[enum_name(p.get("TextXAlignment"), "Center")]
        ya = ALIGN_Y[enum_name(p.get("TextYAlignment"), "Center")]
        wrap = "normal" if p.get("TextWrapped") else "nowrap"
        tstyle = ["position:absolute", "inset:0", "display:flex", "align-items:%s" % ya, "justify-content:%s" % xa,
                  "text-align:%s" % {"flex-start": "left", "flex-end": "right", "center": "center"}[xa],
                  "font-family:%s" % fam, "font-weight:%d" % weight, "font-size:%dpx" % p.get("TextSize", 14),
                  "line-height:1.15", "color:%s" % rgba(tc, ta), "white-space:%s" % wrap, "z-index:0"]
        if p.get("TextStrokeTransparency", 1) < 1 and ta > 0:
            sc = rgba(p.get("TextStrokeColor3", {"r": 0, "g": 0, "b": 0}), 1 - p["TextStrokeTransparency"])
            tstyle.append("text-shadow:1px 0 %s,-1px 0 %s,0 1px %s,0 -1px %s" % (sc, sc, sc, sc))
        text_html = '<span class="txt" data-name="%s" style="%s">%s</span>' % (
            html.escape(node["Name"]), ";".join(tstyle), html.escape(p["Text"]))

    kids = []
    layout = child(node, "UIListLayout")
    gui_children = [c for c in node["children"] if c["ClassName"] in GUI_CLASSES]
    if layout:
        lp = layout["props"]
        pad = lp.get("Padding", {"s": 0, "o": 0})
        horizontal = enum_name(lp.get("FillDirection"), "Vertical") == "Horizontal"
        items = [c for c in gui_children if c["props"].get("Visible", True) is not False]
        items.sort(key=lambda c: c["props"].get("LayoutOrder", 0))
        sizes = [udim2(c["props"]["Size"], w, h) for c in items]
        gap = pad["s"] * (w if horizontal else h) + pad["o"]
        if horizontal:
            total = sum(s[0] for s in sizes) + gap * max(0, len(items) - 1)
            ha = enum_name(lp.get("HorizontalAlignment"), "Left")
            cursor = {"Left": 0, "Center": (w - total) / 2, "Right": w - total}[ha]
            for c, s in zip(items, sizes):
                kids.append(render(c, w, h, (cursor, 0)))
                cursor += s[0] + gap
        else:
            cursor = 0
            for c, s in zip(items, sizes):
                kids.append(render(c, w, h, (0, cursor)))
                cursor += s[1] + gap
        for c in gui_children:
            if c not in items:
                kids.append(render(c, w, h))
    else:
        for c in gui_children:
            kids.append(render(c, w, h))

    return '<div data-name="%s" style="%s">%s%s%s</div>' % (
        html.escape(node["Name"]), ";".join(styles), "".join(inner), text_html, "".join(k for k in kids if k))


def main():
    tree_path, png_path = sys.argv[1], sys.argv[2]
    data = json.load(open(tree_path, encoding="utf-8"))
    W, H = data["width"], data["height"]
    root = data["root"]
    body = "".join(render(c, W, H) or "" for c in root["children"])
    check = """<pre id="report"></pre><script>
const bad=[];for(const el of document.querySelectorAll('span.txt')){
 const box=el.parentElement; if(getComputedStyle(box).display==='none')continue;
 let hidden=false;for(let a=box;a;a=a.parentElement){if(a.style&&a.style.display==='none'){hidden=true;break}} if(hidden)continue;
 const r=document.createRange();r.selectNodeContents(el);const tr=r.getBoundingClientRect();const br=box.getBoundingClientRect();
 if(tr.width>br.width+1||tr.height>br.height+1)bad.push(el.dataset.name+' text '+tr.width.toFixed(0)+'x'+tr.height.toFixed(0)+' box '+br.width.toFixed(0)+'x'+br.height.toFixed(0));}
document.getElementById('report').textContent='OVERFLOW:'+JSON.stringify(bad);</script>"""
    page = ("<!doctype html><html><head><meta charset='utf-8'><style>html,body{margin:0;padding:0;background:#556;"
            "width:%dpx;height:%dpx;overflow:hidden}#report{position:absolute;left:-9999px}</style></head>"
            "<body><div style='position:absolute;left:0;top:0;width:%dpx;height:%dpx;overflow:hidden;"
            "background:linear-gradient(#6a8a7a,#34503f)'>%s</div>%s</body></html>") % (W, H, W, H, body, check)
    html_path = os.path.splitext(png_path)[0] + ".html"
    open(html_path, "w", encoding="utf-8").write(page)
    url = "file:///" + os.path.abspath(html_path).replace("\\", "/")
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    "--window-size=%d,%d" % (W, H), "--screenshot=" + os.path.abspath(png_path), url],
                   check=True, capture_output=True)
    dom = subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--window-size=%d,%d" % (W, H), "--dump-dom", url],
                         check=True, capture_output=True, text=True, encoding="utf-8").stdout
    start = dom.find("OVERFLOW:")
    print(os.path.basename(png_path), dom[start:dom.find("</pre>", start)] if start >= 0 else "no report")


if __name__ == "__main__":
    main()
