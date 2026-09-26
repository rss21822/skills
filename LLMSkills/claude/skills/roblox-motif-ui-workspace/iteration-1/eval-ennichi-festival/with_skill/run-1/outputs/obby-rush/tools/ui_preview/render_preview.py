#!/usr/bin/env python3
"""Draw dumped Roblox GUI trees (tools/ui_preview/dump_menu.luau) as HTML, screenshot them with headless
Chrome/Edge and run a DOM audit (text fit, 48 px touch targets, off-screen, overlapping buttons).

  python tools/ui_preview/render_preview.py <dump-dir> <out-dir>

An approximation of Roblox layout, not a replacement for Studio: UDim2/AnchorPoint/Rotation/UIScale,
UICorner, UIStroke (Border as outer ring, Contextual as text outline), UIGradient (colour x fill,
transparency), UIListLayout, UIPadding, UISizeConstraint, TextScaled + UITextSizeConstraint, Visible,
ZIndex (sibling order). Roblox fonts are drawn with their Google Fonts twins; Japanese with Noto Sans JP
at the requested weight (Roblox also falls back to a system CJK face at the requested weight).
"""
import html
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

CSS_FAMILY = {
    "LuckiestGuy": "Luckiest Guy", "FredokaOne": "Fredoka One", "Nunito": "Nunito", "DenkOne": "Denk One",
    "PermanentMarker": "Permanent Marker", "Bangers": "Bangers", "Montserrat": "Montserrat", "GothamSSm": "Montserrat",
    "BuilderSans": "Inter", "SourceSansPro": "Source Sans 3",
}
ENUM_FONT = {"GothamMedium": ("Montserrat", 500), "GothamBold": ("Montserrat", 700), "Gotham": ("Montserrat", 400),
             "SourceSans": ("Source Sans 3", 400), "SourceSansBold": ("Source Sans 3", 700)}
WEIGHT = {"Thin": 100, "ExtraLight": 200, "Light": 300, "Regular": 400, "Medium": 500, "SemiBold": 600, "Bold": 700,
          "ExtraBold": 800, "Heavy": 900}
CJK = '"Noto Sans JP","Yu Gothic UI",sans-serif'
EMOJI = '"Segoe UI Emoji","Noto Color Emoji"'


def rgba(c, t=0.0):
    c = c or [1, 1, 1]
    return f"rgba({round(c[0] * 255)},{round(c[1] * 255)},{round(c[2] * 255)},{max(0.0, min(1.0, 1 - (t or 0))):.3f})"


def calc(scale, offset):
    return f"calc({scale * 100:.4f}% + {offset:.2f}px)"


def child(node, cls):
    for k in node["k"]:
        if k["c"] == cls:
            return k
    return None


def children(node, cls):
    return [k for k in node["k"] if k["c"] == cls]


def interp(points, t, width):
    points = sorted(points, key=lambda p: p[0])
    if t <= points[0][0]:
        return points[0][1:1 + width]
    for a, b in zip(points, points[1:]):
        if a[0] <= t <= b[0]:
            f = 0 if b[0] == a[0] else (t - a[0]) / (b[0] - a[0])
            return [a[1 + i] + (b[1 + i] - a[1 + i]) * f for i in range(width)]
    return points[-1][1:1 + width]


def gradient_css(fill, fill_t, grad):
    colors = grad["p"].get("Color") or [[0, 1, 1, 1], [1, 1, 1, 1]]
    trans = grad["p"].get("Transparency") or [[0, 0], [1, 0]]
    times = sorted({round(p[0], 4) for p in colors} | {round(p[0], 4) for p in trans})
    stops = []
    for t in times:
        cr, cg, cb = interp(colors, t, 3)
        (gt,) = interp(trans, t, 1)
        col = [fill[0] * cr, fill[1] * cg, fill[2] * cb]
        alpha_t = 1 - (1 - (fill_t or 0)) * (1 - gt)
        stops.append(f"{rgba(col, alpha_t)} {t * 100:.2f}%")
    angle = (grad["p"].get("Rotation") or 0) + 90
    return f"linear-gradient({angle}deg,{','.join(stops)})"


def font_css(p):
    face = p.get("FontFace")
    if face and face[0]:
        family = face[0].split("/")[-1].replace(".json", "")
        name = CSS_FAMILY.get(family, family)
        weight = WEIGHT.get(face[1] or "Regular", 400)
    else:
        name, weight = ENUM_FONT.get(p.get("Font") or "", ("Source Sans 3", 400))
    return f"font-family:\"{name}\",{EMOJI},{CJK};font-weight:{weight};"


def render(node, in_list=False, parent_rotation=0):
    cls, p = node["c"], node["p"]
    if cls not in ("Frame", "TextLabel", "TextButton", "TextBox", "ScrollingFrame", "ImageLabel", "ImageButton", "ViewportFrame", "CanvasGroup"):
        return ""
    if p.get("Visible") is False:
        return ""
    size = p.get("Size") or [0, 100, 0, 100]
    pos = p.get("Position") or [0, 0, 0, 0]
    anchor = p.get("AnchorPoint") or [0, 0]
    rot = p.get("Rotation") or 0
    z = p.get("ZIndex") or 1
    style = [f"width:{calc(size[0], size[1])};height:{calc(size[2], size[3])};z-index:{z};box-sizing:border-box;"]
    limits = child(node, "UISizeConstraint")
    if limits:
        mn, mx = limits["p"].get("MinSize") or [0, 0], limits["p"].get("MaxSize") or [1e9, 1e9]
        style.append(f"min-width:{mn[0]}px;min-height:{mn[1]}px;max-width:{min(mx[0], 99999)}px;max-height:{min(mx[1], 99999)}px;")
    ax, ay = anchor
    scale = child(node, "UIScale")
    s = scale["p"].get("Scale", 1) if scale else 1
    if in_list:
        style.append("position:relative;flex:none;")
        transform = f"translate({(ax - .5) * 100}%,{(ay - .5) * 100}%) scale({s}) translate({(.5 - ax) * 100}%,{(.5 - ay) * 100}%) rotate({rot}deg)"
    else:
        style.append(f"position:absolute;left:{calc(pos[0], pos[1])};top:{calc(pos[2], pos[3])};")
        transform = (f"translate({-ax * 100}%,{-ay * 100}%) translate({(ax - .5) * 100}%,{(ay - .5) * 100}%) scale({s}) "
                     f"translate({(.5 - ax) * 100}%,{(.5 - ay) * 100}%) rotate({rot}deg)")
    style.append(f"transform:{transform};")
    fill, fill_t = p.get("BackgroundColor3") or [1, 1, 1], p.get("BackgroundTransparency")
    if fill_t is None:
        fill_t = 0
    grad = next((g for g in children(node, "UIGradient") if g["p"].get("Enabled") is not False), None)
    if fill_t < 1:
        style.append(f"background:{gradient_css(fill, fill_t, grad) if grad else rgba(fill, fill_t)};")
    corner = child(node, "UICorner")
    attrs = ""
    if corner:
        cs, co = corner["p"].get("CornerRadius") or [0, 8]
        if cs > 0:
            attrs += f" data-crs='{cs}' data-cro='{co}'"
        style.append(f"border-radius:{co}px;")
    text_stroke = None
    for stroke in children(node, "UIStroke"):
        sp = stroke["p"]
        if sp.get("Enabled") is False or (sp.get("Transparency") or 0) >= 1:
            continue
        mode = sp.get("ApplyStrokeMode") or ("Contextual" if cls in ("TextLabel", "TextButton", "TextBox") else "Border")
        if mode == "Border" or cls not in ("TextLabel", "TextButton", "TextBox"):
            style.append(f"box-shadow:0 0 0 {sp.get('Thickness') or 1}px {rgba(sp.get('Color'), sp.get('Transparency'))};")
        else:
            text_stroke = sp
    if p.get("ClipsDescendants") or cls == "ScrollingFrame":
        style.append("overflow:hidden;")
    pad = child(node, "UIPadding")
    inset = [0, 0, 0, 0]
    if pad:
        inset = [(pad["p"].get(k) or [0, 0])[1] for k in ("PaddingTop", "PaddingRight", "PaddingBottom", "PaddingLeft")]
    content_style = f"position:absolute;top:{inset[0]}px;right:{inset[1]}px;bottom:{inset[2]}px;left:{inset[3]}px;"
    layout = child(node, "UIListLayout")
    if layout:
        lp = layout["p"]
        horizontal = (lp.get("FillDirection") or "Vertical") == "Horizontal"
        gap = (lp.get("Padding") or [0, 0])[1]
        ha = {"Left": "flex-start", "Center": "center", "Right": "flex-end"}[lp.get("HorizontalAlignment") or "Left"]
        va = {"Top": "flex-start", "Center": "center", "Bottom": "flex-end"}[lp.get("VerticalAlignment") or "Top"]
        content_style += f"display:flex;flex-direction:{'row' if horizontal else 'column'};gap:{gap}px;"
        content_style += f"justify-content:{ha if horizontal else va};align-items:{va if horizontal else ha};"
    inner = []
    kind = "button" if cls in ("TextButton", "ImageButton") else ("text" if cls in ("TextLabel", "TextBox") else "frame")
    if cls in ("TextLabel", "TextButton", "TextBox") and (p.get("Text") or "") != "":
        tx = {"Left": "flex-start", "Center": "center", "Right": "flex-end"}[p.get("TextXAlignment") or "Center"]
        ty = {"Top": "flex-start", "Center": "center", "Bottom": "flex-end"}[p.get("TextYAlignment") or "Center"]
        align = {"flex-start": "left", "center": "center", "flex-end": "right"}[tx]
        wrap = "pre-wrap" if p.get("TextWrapped") else "pre"
        tsc = child(node, "UITextSizeConstraint")
        size_px = p.get("TextSize") or 14
        text_attrs = ""
        if p.get("TextScaled"):
            mx = (tsc["p"].get("MaxTextSize") if tsc else None) or 100
            mn = (tsc["p"].get("MinTextSize") if tsc else None) or 1
            text_attrs = f" data-scaled='1' data-max='{mx}' data-min='{mn}'"
            size_px = mx
        stroke_css = ""
        if text_stroke:
            stroke_css = (f"-webkit-text-stroke:{2 * (text_stroke.get('Thickness') or 1):.2f}px {rgba(text_stroke.get('Color'), text_stroke.get('Transparency'))};"
                          "paint-order:stroke fill;")
        inner.append(f"<div class='tbox' data-name='{html.escape(node['n'])}' style='position:absolute;inset:0;display:flex;justify-content:{tx};"
                     f"align-items:{ty};text-align:{align};'><span class='t'{text_attrs} style='{font_css(p)}font-size:{size_px}px;line-height:1.12;"
                     f"white-space:{wrap};color:{rgba(p.get('TextColor3') or [0, 0, 0], p.get('TextTransparency'))};{stroke_css}'>"
                     f"{html.escape(p.get('Text'))}</span></div>")
    list_children = layout is not None
    ordered = node["k"]
    if list_children:
        ordered = sorted(node["k"], key=lambda k: (k["p"].get("LayoutOrder") or 0))
    for k in ordered:
        inner.append(render(k, in_list=list_children))
    return (f"<div class='g {kind}' data-name='{html.escape(node['n'])}'{attrs} style='{''.join(style)}'>"
            f"<div class='c' style='{content_style}'>{''.join(inner)}</div></div>")


SCRIPT = r"""
<script>
function fitAll(){
  for (const el of document.querySelectorAll('[data-crs]')){
    const s=parseFloat(el.dataset.crs), o=parseFloat(el.dataset.cro), r=el.getBoundingClientRect();
    const m=Math.min(el.offsetWidth, el.offsetHeight);
    el.style.borderRadius = Math.min(m/2, s*m + o) + 'px';
  }
  for (const t of document.querySelectorAll('span[data-scaled]')){
    const box=t.parentElement, mx=parseFloat(t.dataset.max), mn=parseFloat(t.dataset.min);
    let s=mx; t.style.fontSize=s+'px';
    while (s>mn && (t.scrollWidth>box.clientWidth+0.5 || t.offsetHeight>box.clientHeight+0.5)){ s-=1; t.style.fontSize=s+'px'; }
  }
}
function path(el){ const names=[]; let n=el; while(n && n.dataset){ if(n.dataset.name) names.unshift(n.dataset.name); n=n.parentElement.closest('.g'); } return names.join('.'); }
function visible(el){ return el.offsetParent !== null || getComputedStyle(el).position==='fixed'; }
function audit(){
  const S=document.querySelector('.screen').getBoundingClientRect();
  const W=S.width, H=S.height, out={fit:[], small:[], offscreen:[], overlap:[], fontsLoaded: document.fonts.status};
  for (const box of document.querySelectorAll('.tbox')){
    const g=box.closest('.g'); if(!visible(g)) continue;
    const t=box.firstElementChild;
    if (t.scrollWidth>box.clientWidth+1 || t.offsetHeight>box.clientHeight+1) out.fit.push(path(g)+' ('+t.textContent+')');
  }
  const buttons=[...document.querySelectorAll('.g.button')].filter(visible);
  for (const b of buttons){
    const r=b.getBoundingClientRect();
    if (r.width<47.5 || r.height<47.5) out.small.push(path(b)+' '+Math.round(r.width)+'x'+Math.round(r.height));
    if (r.left<-1 || r.top<-1 || r.right>W+1 || r.bottom>H+1) out.offscreen.push(path(b));
  }
  for (const t of document.querySelectorAll('.tbox')){
    const g=t.closest('.g'); if(!visible(g) || g.dataset.name.startsWith('Motif') || g.closest('[data-name^=Motif]')) continue;
    const r=t.firstElementChild.getBoundingClientRect();
    if (r.width>0 && (r.left<-1 || r.top<-1 || r.right>W+1 || r.bottom>H+1)) out.offscreen.push(path(g)+' (text)');
  }
  const layer=b=>{ let n=b; while(n.parentElement && !n.parentElement.classList.contains('screen')) n=n.parentElement; return n; };
  for (let i=0;i<buttons.length;i++) for (let j=i+1;j<buttons.length;j++){
    const a=buttons[i], b=buttons[j]; if (a.contains(b)||b.contains(a)||layer(a)!==layer(b)) continue;
    const r1=a.getBoundingClientRect(), r2=b.getBoundingClientRect();
    const w=Math.min(r1.right,r2.right)-Math.max(r1.left,r2.left), h=Math.min(r1.bottom,r2.bottom)-Math.max(r1.top,r2.top);
    if (w>2 && h>2) out.overlap.push(path(a)+' x '+path(b));
  }
  document.getElementById('audit').textContent=JSON.stringify(out);
}
fitAll(); audit();
document.fonts.ready.then(()=>{ fitAll(); audit(); document.body.dataset.ready='1'; });
</script>"""


def page_html(dump):
    w, h = dump["width"], dump["height"]
    tree = dump["tree"]
    body = "".join(render(k) for k in tree["k"])
    fonts = ("https://fonts.googleapis.com/css2?family=Fredoka+One&family=Denk+One&family=Permanent+Marker&family=Luckiest+Guy"
             "&family=Nunito:wght@700;800;900&family=Montserrat:wght@500;700&family=Noto+Sans+JP:wght@500;700;900&display=swap")
    return (f"<!doctype html><html><head><meta charset='utf-8'><title>{html.escape(dump['name'])}</title>"
            f"<link rel='stylesheet' href='{fonts}'><style>html,body{{margin:0;padding:0;background:#222;overflow:hidden}}"
            f".screen{{position:relative;width:{w}px;height:{h}px;overflow:hidden;background:#6b6b6b}}</style></head><body>"
            f"<div class='screen'>{body}</div><pre id='audit' style='display:none'></pre>{SCRIPT}</body></html>")


def browser():
    candidates = [shutil.which(n) for n in ("chrome", "google-chrome", "chromium", "msedge")]
    candidates += [r"C:\Program Files\Google\Chrome\Application\chrome.exe", r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
                   r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"]
    return next((c for c in candidates if c and os.path.exists(c)), None)


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass
    dump_dir, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)
    exe = browser()
    names = json.loads((dump_dir / "index.json").read_text(encoding="utf-8"))
    report = {}
    for name in names:
        dump = json.loads((dump_dir / f"{name}.json").read_text(encoding="utf-8"))
        page = out_dir / f"preview-{name}.html"
        page.write_text(page_html(dump), encoding="utf-8")
        if not exe:
            print("no Chrome/Edge: html only", page)
            continue
        base = [exe, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                "--virtual-time-budget=15000", f"--window-size={dump['width']},{dump['height']}"]
        png = out_dir / f"preview-{name}.png"
        subprocess.run(base + [f"--screenshot={png.resolve()}", page.resolve().as_uri()], check=True, timeout=120, capture_output=True)
        dom = subprocess.run(base + ["--dump-dom", page.resolve().as_uri()], check=True, timeout=120, capture_output=True).stdout.decode("utf-8", "replace")
        start = dom.find("<pre id=\"audit\"")
        audit = {}
        if start >= 0:
            text = dom[dom.find(">", start) + 1: dom.find("</pre>", start)]
            try:
                audit = json.loads(html.unescape(text)) if text.strip() else {"error": "audit did not run"}
            except json.JSONDecodeError:
                audit = {"error": text[:200]}
        audit["luau_warnings"] = dump.get("warnings", [])
        report[name] = audit
        issues = sum(len(v) for k, v in audit.items() if isinstance(v, list))
        if audit.get("fontsLoaded") != "loaded":
            print(f"   note: web fonts {audit.get('fontsLoaded')} when audited (metrics approximate)")
        print(f"{name}: {'OK' if issues == 0 else str(issues) + ' issue(s)'}  {png.name}")
        for key in ("fit", "small", "offscreen", "overlap", "luau_warnings"):
            for item in audit.get(key, []) if isinstance(audit.get(key), list) else []:
                print(f"   {key.upper():9} {item}")
        if "error" in audit:
            print("   AUDIT ERROR", audit["error"])
    (out_dir / "preview-audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
