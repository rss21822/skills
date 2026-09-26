#!/usr/bin/env python3
"""Render a GUI tree dumped by export_tree.luau as HTML (and PNG through headless Chrome).

This is a stand-in for a Studio screenshot (Studio is not used in this run): it lays out the Instance
tree the real Luau code built, mapping UDim2 / AnchorPoint / Rotation / UIListLayout / UIPadding /
UICorner / UIStroke(Border) / UIGradient / UISizeConstraint / TextScaled to CSS. Fonts come from Google
Fonts (Oswald, Montserrat; Noto Sans JP stands in for Roblox's CJK fallback). It also runs an audit in
the page (text that does not fit, buttons < 48 px, overlapping buttons, buttons off screen, text or
buttons under the Roblox top bar) and writes the result into #audit (read back with --dump-dom).

  python render_preview.py tree.json out.html [--png out.png] [--audit]
"""
import argparse
import html
import json
import os
import re
import subprocess
import sys
from pathlib import Path

GUI = {"Frame", "TextLabel", "TextButton", "TextBox", "ScrollingFrame", "ImageLabel", "ImageButton", "ViewportFrame", "CanvasGroup"}
TEXT = {"TextLabel", "TextButton", "TextBox"}
CSS_FAMILY = {"Oswald": "Oswald", "Montserrat": "Montserrat", "GothamSSm": "Montserrat", "BuilderSans": "Inter",
              "Nunito": "Nunito", "FredokaOne": "Fredoka One"}
CSS_WEIGHT = {"Thin": 100, "ExtraLight": 200, "Light": 300, "Regular": 400, "Medium": 500, "SemiBold": 600,
              "Bold": 700, "ExtraBold": 800, "Heavy": 900}
ENUM_FONT = {"GothamMedium": ("Montserrat", 500), "GothamBold": ("Montserrat", 700), "Gotham": ("Montserrat", 400)}
CJK = '"Noto Sans JP","Yu Gothic UI",sans-serif'
CHROME = [r"C:\Program Files\Google\Chrome\Application\chrome.exe", r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
          r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"]


def children(n):
    c = n.get("children") or []
    return c if isinstance(c, list) else []


def prop(n, key, default=None):
    v = n["props"].get(key)
    if v is None:
        return default
    if isinstance(v, dict) and "t" in v:
        return v["v"]
    return v


def enum(n, key, default=""):
    v = n["props"].get(key)
    if isinstance(v, dict) and v.get("t") == "Enum":
        return v["v"].split(".")[-1]
    return default


def rgba(c, t=0.0):
    r, g, b = (round(x * 255) for x in c)
    return f"rgba({r},{g},{b},{max(0.0, min(1.0, 1 - t)):.3f})"


def dim(scale, offset):
    if not scale:
        return f"{offset:g}px"
    return f"calc({scale * 100:g}% + {offset:g}px)"


def zi(n):
    z = n["props"].get("ZIndex")
    return 1 if z is None else z


def child_of(n, cls, name=None):
    for c in children(n):
        if c["props"]["ClassName"] == cls and (name is None or c["props"].get("Name") == name):
            return c
    return None


def gradient_css(n, grad, base_color, base_t):
    rot = prop(grad, "Rotation", 0) or 0
    cs = prop(grad, "Color") or [[0, 1, 1, 1], [1, 1, 1, 1]]
    ns = prop(grad, "Transparency") or [[0, 0], [1, 0]]
    times = sorted({round(p[0], 4) for p in cs} | {round(p[0], 4) for p in ns})

    def at_color(t):
        for a, b in zip(cs, cs[1:]):
            if a[0] <= t <= b[0]:
                f = 0 if b[0] == a[0] else (t - a[0]) / (b[0] - a[0])
                return [a[i] + (b[i] - a[i]) * f for i in (1, 2, 3)]
        return cs[-1][1:4] if t >= cs[-1][0] else cs[0][1:4]

    def at_t(t):
        for a, b in zip(ns, ns[1:]):
            if a[0] <= t <= b[0]:
                f = 0 if b[0] == a[0] else (t - a[0]) / (b[0] - a[0])
                return a[1] + (b[1] - a[1]) * f
        return ns[-1][1] if t >= ns[-1][0] else ns[0][1]

    offset = prop(grad, "Offset") or [0, 0]
    shift = offset[0] if abs(((rot + 45) % 180) - 45) < 45 else offset[1]
    stops = []
    for t in times:
        c = at_color(t)
        col = [c[i] * base_color[i] for i in range(3)]
        alpha_t = 1 - (1 - base_t) * (1 - at_t(t))
        stops.append(f"{rgba(col, alpha_t)} {(t + shift) * 100:.2f}%")
    return f"linear-gradient({rot + 90}deg, {', '.join(stops)})"


class Renderer:
    def __init__(self, width, height):
        self.w, self.h = width, height
        self.uid = 0

    def font_css(self, n):
        face = prop(n, "FontFace")
        if face:
            fam = re.search(r"families/([A-Za-z0-9]+)\.json", face[0])
            fam = fam.group(1) if fam else "Montserrat"
            weight = CSS_WEIGHT.get(face[1].split(".")[-1], 400)
        else:
            fam, weight = ENUM_FONT.get(enum(n, "Font", "GothamMedium"), ("Montserrat", 400))
        return f'font-family:"{CSS_FAMILY.get(fam, fam)}",{CJK};font-weight:{weight};'

    def node(self, n, in_layout=False):
        p = n["props"]
        cls = p["ClassName"]
        if cls not in GUI or prop(n, "Visible", True) is False:
            return ""
        self.uid += 1
        size = prop(n, "Size", [0, 100, 0, 100])
        pos = prop(n, "Position", [0, 0, 0, 0])
        anchor = prop(n, "AnchorPoint", [0, 0])
        rot = prop(n, "Rotation", 0) or 0
        bg = prop(n, "BackgroundColor3", [1, 1, 1])
        bgt = prop(n, "BackgroundTransparency", 0)
        style = [f"width:{dim(size[0], size[1])}", f"height:{dim(size[2], size[3])}", "box-sizing:border-box"]
        if in_layout:
            style += ["position:relative", "flex:none", f"order:{prop(n, 'LayoutOrder', 0) or 0}"]
            if rot:
                style.append(f"transform:rotate({rot}deg)")
        else:
            style += ["position:absolute", f"left:{dim(pos[0], pos[1])}", f"top:{dim(pos[2], pos[3])}",
                      f"transform:translate({-anchor[0] * 100:g}%,{-anchor[1] * 100:g}%) rotate({rot}deg)"]
        grad = child_of(n, "UIGradient")
        if bgt < 1:
            style.append(f"background:{gradient_css(n, grad, bg, bgt)}" if grad else f"background:{rgba(bg, bgt)}")
        corner = child_of(n, "UICorner")
        if corner:
            cr = prop(corner, "CornerRadius", [0, 8])
            style.append("border-radius:" + ("9999px" if cr[0] >= 0.5 else (f"{cr[1]:g}px" if not cr[0] else f"{cr[0] * 100:g}%")))
        for stroke in [c for c in children(n) if c["props"]["ClassName"] == "UIStroke"]:
            mode = enum(stroke, "ApplyStrokeMode", "Contextual" if cls in TEXT else "Border")
            t = prop(stroke, "Transparency", 0) or 0
            if t >= 1:
                continue
            color = rgba(prop(stroke, "Color", [0, 0, 0]), t)
            th = prop(stroke, "Thickness", 1)
            if mode == "Border":
                style.append(f"box-shadow:0 0 0 {th}px {color}")
            else:
                style.append(f"-webkit-text-stroke:{th * 2}px {color};paint-order:stroke fill")
        sc = child_of(n, "UISizeConstraint")
        if sc:
            mx, mn = prop(sc, "MaxSize"), prop(sc, "MinSize")
            if mx:
                if mx[0] < 1e8:
                    style.append(f"max-width:{mx[0]}px")
                if mx[1] < 1e8:
                    style.append(f"max-height:{mx[1]}px")
            if mn:
                style.append(f"min-width:{mn[0]}px;min-height:{mn[1]}px")
        if prop(n, "ClipsDescendants", cls == "ScrollingFrame") or cls == "ScrollingFrame":
            style.append("overflow:hidden")
        pad = child_of(n, "UIPadding")
        pl = pr = pt = pb = 0
        if pad:
            pl, pr = (prop(pad, "PaddingLeft", [0, 0])[1], prop(pad, "PaddingRight", [0, 0])[1])
            pt, pb = (prop(pad, "PaddingTop", [0, 0])[1], prop(pad, "PaddingBottom", [0, 0])[1])
        sinks = cls in ("TextButton", "ImageButton", "ScrollingFrame") or (cls == "Frame" and prop(n, "Active", False) is True)
        style.append("pointer-events:" + ("auto" if sinks else "none"))
        attrs = f' data-name="{html.escape(p.get("Name", ""))}" data-class="{cls}"'
        if cls in ("TextButton", "ImageButton"):
            attrs += " data-btn=1"
        inner = []
        # text sits under the children (Roblox draws children over their parent's text)
        if cls in TEXT and prop(n, "Text", ""):
            xa = {"Left": "flex-start", "Right": "flex-end"}.get(enum(n, "TextXAlignment", "Center"), "center")
            ya = {"Top": "flex-start", "Bottom": "flex-end"}.get(enum(n, "TextYAlignment", "Center"), "center")
            talign = {"Left": "left", "Right": "right"}.get(enum(n, "TextXAlignment", "Center"), "center")
            wrap = "normal" if prop(n, "TextWrapped", False) else "nowrap"
            size_px = prop(n, "TextSize", 14)
            scaled = prop(n, "TextScaled", False)
            tsc = child_of(n, "UITextSizeConstraint")
            data = ""
            if scaled:
                mx = prop(tsc, "MaxTextSize", 100) if tsc else 100
                mn = prop(tsc, "MinTextSize", 1) if tsc else 1
                data = f' data-scaled="{mx},{mn}"'
                size_px = mx
            color = rgba(prop(n, "TextColor3", [0, 0, 0]), prop(n, "TextTransparency", 0) or 0)
            inner.append(f"<div class='tx' data-text=1{data} style='position:absolute;inset:0;display:flex;justify-content:{xa};align-items:{ya};'>"
                         f"<span style='{self.font_css(n)}font-size:{size_px}px;line-height:1.12;color:{color};white-space:{wrap};text-align:{talign};'>"
                         f"{html.escape(prop(n, 'Text', ''))}</span></div>")
        layout = child_of(n, "UIListLayout")
        kids = sorted(enumerate(children(n)), key=lambda e: (zi(e[1]), e[0]))
        rendered = "".join(self.node(c, in_layout=layout is not None) for _, c in kids)
        if layout:
            horizontal = enum(layout, "FillDirection", "Vertical") == "Horizontal"
            ha = {"Center": "center", "Right": "flex-end"}.get(enum(layout, "HorizontalAlignment", "Left"), "flex-start")
            va = {"Center": "center", "Bottom": "flex-end"}.get(enum(layout, "VerticalAlignment", "Top"), "flex-start")
            gap = prop(layout, "Padding", [0, 0])[1]
            flex = (f"display:flex;flex-direction:{'row' if horizontal else 'column'};gap:{gap}px;"
                    f"justify-content:{ha if horizontal else va};align-items:{va if horizontal else ha};")
            inner.append(f"<div style='position:absolute;inset:0;{flex}'>{rendered}</div>")
        else:
            inner.append(rendered)
        content = f"<div style='position:absolute;left:{pl}px;right:{pr}px;top:{pt}px;bottom:{pb}px'>{''.join(inner)}</div>"
        return f"<div{attrs} style='{';'.join(style)}'>{content}</div>"

    def page(self, tree, title):
        root = tree["root"]
        body = "".join(self.node(c) for _, c in sorted(enumerate(children(root)), key=lambda e: (zi(e[1]), e[0])))
        w, h = self.w, self.h
        topbar = (f"<div data-overlay=1 style='position:absolute;left:0;top:0;width:{w}px;height:58px;pointer-events:none'>"
                  "<div style='position:absolute;left:12px;top:7px;width:44px;height:44px;border-radius:12px;background:rgba(18,18,21,.62)'></div>"
                  "<div style='position:absolute;left:62px;top:7px;width:44px;height:44px;border-radius:12px;background:rgba(18,18,21,.62)'></div>"
                  f"<div style='position:absolute;left:{w - 56}px;top:7px;width:44px;height:44px;border-radius:12px;background:rgba(18,18,21,.62)'></div>"
                  "<svg style='position:absolute;left:24px;top:19px' width='20' height='20'><rect x='3' y='3' width='14' height='14' rx='2' transform='rotate(15 10 10)' fill='none' stroke='#fff' stroke-width='2.4'/></svg>"
                  "<svg style='position:absolute;left:74px;top:19px' width='20' height='20'><path d='M3 4h14v9H8l-4 3v-3H3z' fill='none' stroke='#fff' stroke-width='2'/></svg>"
                  "</div>")
        audit_js = r"""
<script>
function fitScaled(){document.querySelectorAll('[data-scaled]').forEach(function(box){var sp=box.firstElementChild;var p=box.dataset.scaled.split(',');var mx=+p[0],mn=+p[1];var s=Math.min(mx,box.clientHeight);while(s>mn&&(sp.scrollWidth>box.clientWidth+0.5||sp.offsetHeight>box.clientHeight+1)){s-=1;sp.style.fontSize=s+'px';}});}
function r(el){var b=el.getBoundingClientRect();var q={left:b.left,top:b.top,right:b.right,bottom:b.bottom};var a=el.parentElement;
 while(a&&a.id!=='root'){if(getComputedStyle(a).overflow==='hidden'){var c=a.getBoundingClientRect();q.left=Math.max(q.left,c.left);q.top=Math.max(q.top,c.top);q.right=Math.min(q.right,c.right);q.bottom=Math.min(q.bottom,c.bottom);}a=a.parentElement;}
 q.width=Math.max(0,q.right-q.left);q.height=Math.max(0,q.bottom-q.top);return q;}
function visible(el){var b=r(el);return b.width>0&&b.height>0;}
function reachable(el){var b=r(el);var x=(b.left+b.right)/2,y=(b.top+b.bottom)/2;var hit=document.elementFromPoint(x,y);return hit&&(hit===el||el.contains(hit));}
function audit(){var W=%W%,H=%H%,out=[];
 document.querySelectorAll('[data-text]').forEach(function(box){if(!visible(box))return;var sp=box.firstElementChild;var owner=box.parentElement.parentElement.dataset.name;
  if(sp.scrollWidth>box.clientWidth+1||sp.offsetHeight>box.clientHeight+2)out.push('FIT '+owner+' "'+sp.textContent+'" '+sp.scrollWidth+'x'+sp.offsetHeight+' in '+box.clientWidth+'x'+box.clientHeight);});
 var btns=[].slice.call(document.querySelectorAll('[data-btn]')).filter(visible).filter(reachable);
 btns.forEach(function(b){var q=r(b),o=b.getBoundingClientRect();if(o.width<48||o.height<48)out.push('SMALL '+b.dataset.name+' '+Math.round(q.width)+'x'+Math.round(q.height));
  if(q.left<0||q.top<0||q.right>W+0.5||q.bottom>H+0.5)out.push('OFFSCREEN '+b.dataset.name);});
 for(var i=0;i<btns.length;i++)for(var j=i+1;j<btns.length;j++){var a=r(btns[i]),c=r(btns[j]);var ix=Math.max(0,Math.min(a.right,c.right)-Math.max(a.left,c.left)),iy=Math.max(0,Math.min(a.bottom,c.bottom)-Math.max(a.top,c.top));
  var s=Math.min(a.width*a.height,c.width*c.height);if(s>0&&ix*iy/s>0.2)out.push('OVERLAP '+btns[i].dataset.name+' / '+btns[j].dataset.name);}
 var zones=[[0,0,200,58],[W-120,0,W,58]];
 [].slice.call(document.querySelectorAll('[data-text] span')).concat(btns).forEach(function(el){if(!visible(el))return;var q=r(el);zones.forEach(function(z){if(q.left<z[2]&&q.right>z[0]&&q.top<z[3]&&q.bottom>z[1]){var n=el.dataset&&el.dataset.name?el.dataset.name:el.textContent;out.push('TOPBAR '+n);}});});
 document.getElementById('audit').textContent=(out.length?out.join('\n'):'PASS')+'\n';}
document.fonts.ready.then(function(){fitScaled();audit();});
</script>""".replace("%W%", str(w)).replace("%H%", str(h))
        fonts = ("https://fonts.googleapis.com/css2?family=Oswald:wght@400;700&family=Montserrat:wght@500;700;800;900"
                 "&family=Noto+Sans+JP:wght@700;800;900&display=block")
        return (f"<!doctype html><html><head><meta charset='utf-8'><title>{html.escape(title)}</title>"
                f"<link rel='stylesheet' href='{fonts}'><style>body{{margin:0;background:#222}}</style></head><body>"
                f"<div id='root' style='position:relative;width:{w}px;height:{h}px;overflow:hidden;background:#3a3f4a'>{body}{topbar}</div>"
                f"<pre id='audit' style='position:absolute;top:{h + 20}px;left:0;color:#ddd'></pre>{audit_js}</body></html>")


def chrome():
    return next((c for c in CHROME if os.path.exists(c)), None)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tree")
    ap.add_argument("out")
    ap.add_argument("--png")
    ap.add_argument("--audit", action="store_true")
    ap.add_argument("--title", default="preview")
    a = ap.parse_args()
    tree = json.loads(Path(a.tree).read_text(encoding="utf-8"))
    r = Renderer(tree["width"], tree["height"])
    Path(a.out).write_text(r.page(tree, a.title), encoding="utf-8")
    exe = chrome()
    url = Path(a.out).resolve().as_uri()
    if a.png and exe:
        subprocess.run([exe, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--virtual-time-budget=8000",
                        f"--screenshot={Path(a.png).resolve()}", f"--window-size={tree['width']},{tree['height']}", url],
                       check=True, timeout=120, capture_output=True)
        print("png:", a.png)
    if a.audit and exe:
        res = subprocess.run([exe, "--headless=new", "--disable-gpu", "--virtual-time-budget=8000", "--dump-dom",
                              f"--window-size={tree['width']},{tree['height'] + 400}", url],
                             capture_output=True, timeout=120, text=True, encoding="utf-8")
        m = re.search(r"<pre id=\"audit\"[^>]*>(.*?)</pre>", res.stdout, re.S)
        text = html.unescape(m.group(1)).strip() if m else "AUDIT NOT RUN"
        print(f"audit {tree['width']}x{tree['height']} page={tree.get('page')}: {text}")
        return 0 if text == "PASS" else 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
