#!/usr/bin/env python3
"""Render a GUI tree dumped by dump_menu.luau to HTML/PNG and audit it (no Studio needed).

  python render_preview.py tree.json out.html [--png out.png] [--audit out.audit.json] [--scale 1]

Layout follows Roblox rules for what the menu uses: UDim2 size/position, AnchorPoint, Rotation,
UIListLayout, UIPadding, UISizeConstraint, UIAspectRatioConstraint (FitWithinMaxSize), UICorner,
UIStroke (Border = outer, with an optional UIGradient on the stroke), UIGradient transparency/colour,
ZIndex (Sibling), Visible, ClipsDescendants, TextScaled + UITextSizeConstraint. Fonts: the Google
equivalents of Roblox families; Japanese falls back to Noto Sans JP at the requested weight.
Audit (in the browser, from real text metrics): FIT (text larger than its box), SMALL (button < 48 px),
OFFSCREEN, TOPBAR (text/button under Roblox's top-left buttons, 200x58 px), OVERLAP (buttons, or
text over text / a button, inside the same top-level layer).
"""
import argparse
import html
import json
import os
import subprocess
import sys
from pathlib import Path

CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
FAMILY = {"Merriweather": "Merriweather", "AccanthisADFStd": "Libre Bodoni", "GothamSSm": "Montserrat",
          "BuilderSans": "Inter", "Nunito": "Nunito", "SourceSansPro": "Source Sans 3"}
WEIGHT = {"Thin": 100, "ExtraLight": 200, "Light": 300, "Regular": 400, "Medium": 500, "SemiBold": 600,
          "Bold": 700, "ExtraBold": 800, "Heavy": 900}
ENUM_FONT = {"GothamMedium": ("Montserrat", 500), "GothamBold": ("Montserrat", 700), "Gotham": ("Montserrat", 400)}
GUI = {"Frame", "TextLabel", "TextButton", "ScrollingFrame", "TextBox", "ImageLabel", "ImageButton", "CanvasGroup"}
TEXT = {"TextLabel", "TextButton", "TextBox"}


def udim2(v, pw, ph):
    return v["xs"] * pw + v["xo"], v["ys"] * ph + v["yo"]


def rgba(c, transparency=0.0):
    return "rgba(%d,%d,%d,%.3f)" % (round(c["r"] * 255), round(c["g"] * 255), round(c["b"] * 255), max(0.0, 1 - transparency))


def child(node, cls):
    return [c for c in node["children"] if c["class"] == cls]


def first(node, cls):
    found = child(node, cls)
    return found[0] if found else None


def mask_css(gradient):
    """CSS mask for a UIGradient's Transparency (Roblox Rotation 0 = left->right, CSS 90deg)."""
    seq = gradient["props"].get("Transparency")
    if not seq or not isinstance(seq, dict):
        return ""
    angle = 90 + gradient["props"].get("Rotation", 0)
    stops = ",".join("rgba(0,0,0,%.3f) %.2f%%" % (1 - v, t * 100) for t, v in seq["k"])
    image = "linear-gradient(%.1fdeg,%s)" % (angle, stops)
    return "-webkit-mask-image:%s;mask-image:%s;" % (image, image)


def font_css(props):
    face = props.get("FontFace")
    if isinstance(face, dict):
        fam = face["family"].split("/")[-1].replace(".json", "")
        family, weight = FAMILY.get(fam, fam), WEIGHT.get(face.get("weight", "Regular"), 400)
    else:
        family, weight = ENUM_FONT.get(props.get("Font", "GothamMedium"), ("Montserrat", 500))
    return "font-family:'%s','Noto Sans JP',sans-serif;font-weight:%d;" % (family, weight)


def est_width(text, size):
    width = 0.0
    for ch in text:
        width += size * (1.0 if ord(ch) > 0x2E80 else 0.32 if ch in " ,.:" else 0.62)
    return width


class Renderer:
    def __init__(self, data):
        self.data = data
        self.W, self.H = data["viewport"]
        self.out = []
        self.counter = 0

    def size_of(self, node, pw, ph):
        p = node["props"]
        w, h = udim2(p.get("Size", {"xs": 0, "xo": 100, "ys": 0, "yo": 100}), pw, ph)
        sc = first(node, "UISizeConstraint")
        if sc:
            mn, mx = sc["props"].get("MinSize"), sc["props"].get("MaxSize")
            if mx:
                w, h = min(w, mx["x"]), min(h, mx["y"])
            if mn:
                w, h = max(w, mn["x"]), max(h, mn["y"])
        ar = first(node, "UIAspectRatioConstraint")
        if ar:
            ratio = ar["props"].get("AspectRatio", 1)
            if h > 0 and w / h > ratio:
                w = h * ratio
            else:
                h = w / ratio
        return w, h

    def padding(self, node, w, h):
        pad = first(node, "UIPadding")
        if not pad:
            return 0, 0, 0, 0
        p = pad["props"]

        def g(key, ref):
            v = p.get(key)
            return v["s"] * ref + v["o"] if v else 0
        return g("PaddingLeft", w), g("PaddingTop", h), g("PaddingRight", w), g("PaddingBottom", h)

    def place_children(self, node, w, h):
        """Absolute-within-parent rects (x, y, w, h) for GUI children, honouring UIListLayout."""
        l, t, r, b = self.padding(node, w, h)
        cw, ch = w - l - r, h - t - b
        kids = [c for c in node["children"] if c["class"] in GUI]
        rects = {}
        layout = first(node, "UIListLayout")
        sizes = {id(c): self.size_of(c, cw, ch) for c in kids}
        if layout:
            lp = layout["props"]
            visible = [c for c in kids if c["props"].get("Visible", True)]
            visible = sorted(enumerate(visible), key=lambda e: (e[1]["props"].get("LayoutOrder", 0), e[0]))
            visible = [c for _, c in visible]
            horizontal = lp.get("FillDirection") == "Horizontal"
            pad = lp.get("Padding") or {"s": 0, "o": 0}
            gap = pad["s"] * (cw if horizontal else ch) + pad["o"]
            total = sum(sizes[id(c)][0 if horizontal else 1] for c in visible) + gap * max(0, len(visible) - 1)
            main_len = cw if horizontal else ch
            align = lp.get("HorizontalAlignment" if horizontal else "VerticalAlignment", "Left" if horizontal else "Top")
            cursor = {"Center": (main_len - total) / 2, "Right": main_len - total, "Bottom": main_len - total}.get(align, 0)
            for c in visible:
                sw, sh = sizes[id(c)]
                if horizontal:
                    va = lp.get("VerticalAlignment", "Top")
                    y = {"Center": (ch - sh) / 2, "Bottom": ch - sh}.get(va, 0)
                    rects[id(c)] = (l + cursor, t + y, sw, sh)
                    cursor += sw + gap
                else:
                    ha = lp.get("HorizontalAlignment", "Left")
                    x = {"Center": (cw - sw) / 2, "Right": cw - sw}.get(ha, 0)
                    rects[id(c)] = (l + x, t + cursor, sw, sh)
                    cursor += sh + gap
        for c in kids:
            if id(c) in rects:
                continue
            sw, sh = sizes[id(c)]
            px, py = udim2(c["props"].get("Position", {"xs": 0, "xo": 0, "ys": 0, "yo": 0}), cw, ch)
            a = c["props"].get("AnchorPoint", {"x": 0, "y": 0})
            rects[id(c)] = (l + px - a["x"] * sw, t + py - a["y"] * sh, sw, sh)
        return rects

    def corner(self, node, w, h):
        c = first(node, "UICorner")
        if not c:
            return 0
        v = c["props"].get("CornerRadius", {"s": 0, "o": 8})
        return min(v["s"] * min(w, h) + v["o"], min(w, h) / 2)

    def text_size(self, node, w, h):
        p = node["props"]
        size = p.get("TextSize", 14)
        if p.get("TextScaled"):
            cons = first(node, "UITextSizeConstraint")
            mx = cons["props"].get("MaxTextSize", 100) if cons else 100
            mn = cons["props"].get("MinTextSize", 1) if cons else 1
            text = p.get("Text", "")
            lines = text.split("\n")
            by_w = min((w - 2) / max(1e-3, est_width(line, 1)) for line in lines)
            by_h = h / (len(lines) * 1.25)
            size = max(mn, min(mx, by_w, by_h))
        return size

    def node_html(self, node, x, y, w, h, path, layer, abs_x, abs_y):
        p = node["props"]
        if not p.get("Visible", True):
            return ""
        self.counter += 1
        rot = p.get("Rotation", 0) or 0
        radius = self.corner(node, w, h)
        parts = []
        attrs = 'data-path="%s" data-layer="%s" data-class="%s"' % (html.escape(path), html.escape(layer), node["class"])
        if node["class"] in ("TextButton",) and p.get("Active", True) is not False:
            attrs += " data-button=1"
        style = "left:%.2fpx;top:%.2fpx;width:%.2fpx;height:%.2fpx;" % (x, y, max(0, w), max(0, h))
        if rot:
            style += "transform:rotate(%.3fdeg);" % rot
        grad = next((g for g in child(node, "UIGradient") if g["props"].get("Enabled", True) is not False), None)
        gmask = mask_css(grad) if grad else ""
        bt = p.get("BackgroundTransparency", 0)
        if node["class"] in GUI and bt < 1 and p.get("BackgroundColor3"):
            bg = rgba(p["BackgroundColor3"], bt)
            colors = grad["props"].get("Color") if grad else None
            if isinstance(colors, dict):
                c = p["BackgroundColor3"]
                stops = ",".join("rgba(%d,%d,%d,%.3f) %.2f%%" % (round(c["r"] * r * 255), round(c["g"] * g * 255),
                                 round(c["b"] * b * 255), 1 - bt, t * 100) for t, r, g, b in colors["k"])
                bg = "linear-gradient(%.1fdeg,%s)" % (90 + grad["props"].get("Rotation", 0), stops)
            parts.append('<div class="bg" style="background:%s;border-radius:%.2fpx;%s"></div>' % (bg, radius, gmask))
        text_stroke = ""
        for s in child(node, "UIStroke"):
            sp = s["props"]
            if sp.get("Enabled", True) is False or sp.get("Transparency", 0) >= 1 or sp.get("Thickness", 1) <= 0:
                continue
            mode = sp.get("ApplyStrokeMode") or ("Contextual" if node["class"] in TEXT else "Border")
            if mode == "Contextual" and node["class"] in TEXT:
                text_stroke = "-webkit-text-stroke:%.1fpx %s;paint-order:stroke fill;" % (sp["Thickness"] * 2, rgba(sp["Color"], sp.get("Transparency", 0)))
                continue
            th = sp.get("Thickness", 1)
            sg = first(s, "UIGradient")
            smask = mask_css(sg) if sg else ""
            parts.append('<div class="stroke" style="inset:%.2fpx;border:%.2fpx solid %s;border-radius:%.2fpx;%s"></div>' % (
                -th, th, rgba(sp["Color"], sp.get("Transparency", 0)), (radius + th) if radius > 0 else 0, smask))
        if node["class"] in TEXT and p.get("Text"):
            l, t, r, b = self.padding(node, w, h)
            size = self.text_size(node, w - l - r, h - t - b)
            ja = {"Left": "flex-start", "Right": "flex-end"}.get(p.get("TextXAlignment", "Center"), "center")
            va = {"Top": "flex-start", "Bottom": "flex-end"}.get(p.get("TextYAlignment", "Center"), "center")
            talign = {"Left": "left", "Right": "right"}.get(p.get("TextXAlignment", "Center"), "center")
            wrap = "pre-wrap" if p.get("TextWrapped") else "pre"
            lh = p.get("LineHeight", 1) * 1.22
            parts.append('<div class="text" data-fit="%s" style="left:%.2fpx;top:%.2fpx;right:%.2fpx;bottom:%.2fpx;justify-content:%s;align-items:%s;%s">'
                         '<span style="font-size:%.2fpx;line-height:%.3f;color:%s;white-space:%s;text-align:%s;%s%s">%s</span></div>' % (
                             "scaled" if p.get("TextScaled") else "fixed", l, t, r, b, ja, va, gmask, size, lh,
                             rgba(p.get("TextColor3", {"r": 0, "g": 0, "b": 0}), p.get("TextTransparency", 0)), wrap, talign,
                             font_css(p), text_stroke, html.escape(p["Text"])))
        rects = self.place_children(node, w, h)
        kids = [c for c in node["children"] if c["class"] in GUI]
        order = sorted(enumerate(kids), key=lambda e: (e[1]["props"].get("ZIndex", 1), e[0]))
        inner = []
        for _, c in order:
            cx, cy, cw, ch = rects[id(c)]
            inner.append(self.node_html(c, cx, cy, cw, ch, path + "." + c["name"], layer, abs_x + cx, abs_y + cy))
        clip = "overflow:hidden;" if (p.get("ClipsDescendants") or node["class"] == "ScrollingFrame") else ""
        parts.append('<div class="kids" style="border-radius:%.2fpx;%s">%s</div>' % (radius if clip else 0, clip, "".join(inner)))
        return '<div class="node" %s style="%s">%s</div>' % (attrs, style, "".join(parts))

    def render(self, title):
        tree = self.data["tree"]
        W, H = self.W, self.H
        body = []
        kids = [c for c in tree["children"] if c["class"] in GUI]
        rects = self.place_children({"children": kids, "props": {}}, W, H)
        order = sorted(enumerate(kids), key=lambda e: (e[1]["props"].get("ZIndex", 1), e[0]))
        for _, c in order:
            x, y, w, h = rects[id(c)]
            body.append(self.node_html(c, x, y, w, h, tree["name"] + "." + c["name"], c["name"], x, y))
        return PAGE % {"title": html.escape(title), "W": W, "H": H, "body": "".join(body)}


PAGE = """<!doctype html><html><head><meta charset="utf-8"><title>%(title)s</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Merriweather:wght@400;700;900&family=Libre+Bodoni:wght@400;700&family=Montserrat:wght@400;500;700&family=Noto+Sans+JP:wght@400;700;900&display=block">
<style>
html,body{margin:0;padding:0;background:#6b6b6b}
#screen{position:relative;width:%(W)dpx;height:%(H)dpx;overflow:hidden;background:#7d8a96}
/* stand-in for the 3D world behind the menu: coloured so any see-through shows */
#screen::before{content:"";position:absolute;inset:0;background:linear-gradient(160deg,#6fb3e0 0%%,#9fd18b 55%%,#d9a55c 100%%)}
.node{position:absolute;box-sizing:border-box;transform-origin:50%% 50%%}
.bg,.stroke,.kids{position:absolute;box-sizing:border-box}
.bg,.kids{inset:0}
.text{position:absolute;display:flex;box-sizing:border-box}
#topbar{position:absolute;left:0;top:0;width:200px;height:58px;border:1px dashed rgba(255,0,0,.0);pointer-events:none}
</style></head><body><div id="screen">%(body)s</div>
<pre id="audit"></pre>
<script>
function audit(){
  const W=%(W)d,H=%(H)d, out=[];
  const screen=document.getElementById('screen').getBoundingClientRect();
  const rel=r=>({x:r.left-screen.left,y:r.top-screen.top,w:r.width,h:r.height});
  const hit=(a,b,m=1)=>a.x+m<b.x+b.w&&b.x+m<a.x+a.w&&a.y+m<b.y+b.h&&b.y+m<a.y+a.h;
  const texts=[],buttons=[];
  document.querySelectorAll('.node').forEach(n=>{
    const path=n.dataset.path, layer=n.dataset.layer;
    const box=rel(n.getBoundingClientRect());
    if(n.dataset.button){buttons.push({path,layer,box});
      if(box.w<47.5||box.h<47.5) out.push('SMALL '+path+' '+box.w.toFixed(0)+'x'+box.h.toFixed(0));}
    const t=n.querySelector(':scope > .text');
    if(t){const span=t.firstElementChild, s=rel(span.getBoundingClientRect()), c=rel(t.getBoundingClientRect());
      texts.push({path,layer,box:s,button:!!n.dataset.button});
      if(t.dataset.fit==='fixed'&&(s.w>c.w+1.5||s.h>c.h+1.5)) out.push('FIT '+path+' text '+s.w.toFixed(0)+'x'+s.h.toFixed(0)+' in '+c.w.toFixed(0)+'x'+c.h.toFixed(0));
      if(s.x<-1||s.y<-1||s.x+s.w>W+1||s.y+s.h>H+1) out.push('OFFSCREEN '+path);
      if(hit(s,{x:0,y:0,w:200,h:58},0)) out.push('TOPBAR '+path);}
    if(n.dataset.button&&(box.x<-1||box.y<-1||box.x+box.w>W+1||box.y+box.h>H+1)) out.push('OFFSCREEN '+path);
    if(n.dataset.button&&hit(box,{x:0,y:0,w:200,h:58},0)) out.push('TOPBAR '+path);
  });
  for(let i=0;i<buttons.length;i++)for(let j=i+1;j<buttons.length;j++){const a=buttons[i],b=buttons[j];
    if(a.layer===b.layer&&hit(a.box,b.box,2)) out.push('OVERLAP button '+a.path+' / '+b.path);}
  for(let i=0;i<texts.length;i++)for(let j=i+1;j<texts.length;j++){const a=texts[i],b=texts[j];
    if(a.layer===b.layer&&hit(a.box,b.box,1)) out.push('OVERLAP text '+a.path+' / '+b.path);}
  for(const t of texts)for(const b of buttons){
    if(t.layer===b.layer&&!t.path.startsWith(b.path)&&hit(t.box,b.box,2)) out.push('OVERLAP text-on-button '+t.path+' / '+b.path);}
  document.getElementById('audit').textContent=JSON.stringify({issues:out,texts:texts.length,buttons:buttons.length});
}
document.fonts.ready.then(()=>setTimeout(audit,50));
</script></body></html>"""


def chrome(args):
    return subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--virtual-time-budget=9000"] + args,
                          capture_output=True, timeout=120, text=True, encoding="utf-8", errors="replace")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tree")
    ap.add_argument("html")
    ap.add_argument("--png")
    ap.add_argument("--audit")
    ap.add_argument("--title", default="preview")
    args = ap.parse_args()
    data = json.loads(Path(args.tree).read_text(encoding="utf-8"))
    r = Renderer(data)
    Path(args.html).write_text(r.render(args.title), encoding="utf-8")
    url = Path(args.html).resolve().as_uri()
    result = {"issues": ["audit did not run"]}
    dom = chrome(["--dump-dom", url]).stdout
    start = dom.find('<pre id="audit">')
    if start >= 0:
        raw = dom[start + len('<pre id="audit">'):dom.find("</pre>", start)]
        try:
            result = json.loads(html.unescape(raw))
        except Exception:  # noqa: BLE001
            result = {"issues": ["audit unreadable: " + raw[:200]]}
    result["warnings"] = data.get("warnings", [])
    if args.audit:
        Path(args.audit).write_text(json.dumps(result, ensure_ascii=False, indent=1), encoding="utf-8")
    if args.png:
        chrome(["--screenshot=" + str(Path(args.png).resolve()), "--window-size=%d,%d" % (r.W, r.H), url])
    print("%s: %d issue(s), %d text, %d buttons%s" % (Path(args.html).name, len(result["issues"]), result.get("texts", 0),
          result.get("buttons", 0), "" if not result["issues"] else "\n  " + "\n  ".join(result["issues"])))


if __name__ == "__main__":
    main()
