"""Preview renderer (not part of the game).

Takes the instance trees dumped by dump_tree.luau (the real MainMenu/UITheme/ToyDecor code run in the
test mock) and lays them out with a small re-implementation of the Roblox GUI rules the menu uses
(UDim2 size/position, AnchorPoint, UIPadding, UIListLayout, AutomaticSize, UIAspectRatioConstraint
FitWithinMaxSize, UISizeConstraint, UIScale, Rotation, ClipsDescendants, UICorner, UIStroke outer
border / contextual text stroke, TextScaled, Sibling ZIndex). Then Chrome headless screenshots it.

It is an approximation: Roblox's text shaping, CJK fallback font and stroke anti-aliasing differ.
Fonts: FredokaOne / Nunito Regular from the local Roblox install; Japanese falls back to Yu Gothic.
"""
import base64
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.dirname(HERE)
ROBLOX_FONTS = r"C:\Users\ryufu\AppData\Local\Roblox\Versions\version-8afc5a7d5e894d22\content\fonts"
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"


def font_b64(name):
    with open(os.path.join(ROBLOX_FONTS, name), "rb") as handle:
        return base64.b64encode(handle.read()).decode()


HTML = r"""<!doctype html><html><head><meta charset="utf-8"><style>
@font-face { font-family: 'FredokaRbx'; src: url(data:font/ttf;base64,__FREDOKA__) format('truetype'); font-weight: 100 900; }
@font-face { font-family: 'NunitoRbx'; src: url(data:font/ttf;base64,__NUNITO__) format('truetype'); font-weight: 400; }
html, body { margin: 0; padding: 0; overflow: hidden; background: #222; }
#screen { position: absolute; left: 0; top: 0; overflow: hidden; }
.n { position: absolute; box-sizing: border-box; }
.skin { position: absolute; inset: 0; }
.txt { position: absolute; inset: 0; display: flex; line-height: 1; }
.kids { position: absolute; inset: 0; }
#measure { position: absolute; left: -9999px; top: -9999px; white-space: pre; line-height: 1; }
</style></head><body><div id="screen"></div><span id="measure"></span><script>
const STATES = __STATES__;
const q = new URLSearchParams(location.search);
const W = +q.get('w'), H = +q.get('h'), stateName = q.get('state');
const GUI = new Set(['Frame','TextLabel','TextButton','ScrollingFrame','ImageLabel','ImageButton','CanvasGroup','TextBox']);
const WEIGHTS = {Thin:100, ExtraLight:200, Light:300, Regular:400, Medium:500, SemiBold:600, Bold:700, ExtraBold:800, Heavy:900};
const col = (c, a) => `rgba(${Math.round(c.r*255)},${Math.round(c.g*255)},${Math.round(c.b*255)},${a === undefined ? 1 : a})`;
function fontOf(n) {
  const ff = n.FontFace || {family: 'SourceSans', weight: 'Regular'};
  let fam = /Fredoka/i.test(ff.family) ? "'FredokaRbx'" : /Nunito/i.test(ff.family) ? "'NunitoRbx'" : "Arial";
  return {family: fam + ", 'Yu Gothic', 'Meiryo', 'Segoe UI Symbol', sans-serif", weight: WEIGHTS[ff.weight] || 400};
}
const measureEl = document.getElementById('measure');
function measure(text, f, size) {
  measureEl.style.fontFamily = f.family; measureEl.style.fontWeight = f.weight; measureEl.style.fontSize = size + 'px';
  measureEl.textContent = text; const r = measureEl.getBoundingClientRect(); return [r.width, r.height];
}
function mods(n) {
  const m = {};
  for (const c of childrenOf(n)) {
    const k = {UICorner:'corner', UIStroke:'stroke', UIListLayout:'list', UIPadding:'pad', UIAspectRatioConstraint:'aspect',
      UISizeConstraint:'sizec', UIScale:'scale'}[c.ClassName];
    if (k) m[k] = c;
  }
  return m;
}
const ud = (u, len) => u ? u.s * len + u.o : 0;
function isText(n) { return (n.ClassName === 'TextLabel' || n.ClassName === 'TextButton') && typeof n.Text === 'string'; }
function childrenOf(n) { return Array.isArray(n.Children) ? n.Children : []; }
function kidsOf(n) { return childrenOf(n).filter(c => GUI.has(c.ClassName) && c.Visible !== false); }

// Returns own size; lays out descendants (positions relative to the node box).
function layout(n, pw, ph) {
  const m = mods(n);
  let w = n.Size ? n.Size.xs * pw + n.Size.xo : pw, h = n.Size ? n.Size.ys * ph + n.Size.yo : ph;
  if (m.aspect) { const r = m.aspect.AspectRatio || 1; if (w / h > r) w = h * r; else h = w / r; }
  const pad = m.pad || {};
  let padL = ud(pad.PaddingLeft, w), padR = ud(pad.PaddingRight, w), padT = ud(pad.PaddingTop, h), padB = ud(pad.PaddingBottom, h);
  const auto = n.AutomaticSize || 'None';
  const kids = kidsOf(n);
  if (auto !== 'None') {
    if (isText(n) && n.Text !== '') {
      const [tw, th] = measure(n.Text, fontOf(n), n.TextSize || 14);
      if (auto.includes('X') || auto === 'XY') w = Math.max(w, tw + padL + padR);
    }
    if (m.list) {
      const horiz = m.list.FillDirection === 'Horizontal';
      let sum = 0, cross = 0;
      kids.forEach((c, i) => { layout(c, w - padL - padR, h - padT - padB); sum += horiz ? c._w : c._h; if (i) sum += ud(m.list.Padding, horiz ? w : h); cross = Math.max(cross, horiz ? c._h : c._w); });
      if (horiz && (auto === 'X' || auto === 'XY')) w = Math.max(w, sum + padL + padR);
      if (!horiz && (auto === 'Y' || auto === 'XY')) h = Math.max(h, sum + padT + padB);
    }
  }
  if (m.sizec) {
    if (m.sizec.MaxSize) { w = Math.min(w, m.sizec.MaxSize.x); h = Math.min(h, m.sizec.MaxSize.y); }
    if (m.sizec.MinSize) { w = Math.max(w, m.sizec.MinSize.x); h = Math.max(h, m.sizec.MinSize.y); }
  }
  n._w = w; n._h = h;
  padL = ud(pad.PaddingLeft, w); padR = ud(pad.PaddingRight, w); padT = ud(pad.PaddingTop, h); padB = ud(pad.PaddingBottom, h);
  const cw = w - padL - padR, ch = h - padT - padB;
  kids.forEach(c => layout(c, cw, ch));
  if (m.list) {
    const horiz = m.list.FillDirection === 'Horizontal';
    const gap = ud(m.list.Padding, horiz ? cw : ch);
    const sorted = kids.map((c, i) => [c, i]).sort((a, b) => ((a[0].LayoutOrder || 0) - (b[0].LayoutOrder || 0)) || (a[1] - b[1])).map(x => x[0]);
    let total = sorted.reduce((s, c) => s + (horiz ? c._w : c._h), 0) + gap * Math.max(0, sorted.length - 1);
    const mainAlign = horiz ? (m.list.HorizontalAlignment || 'Left') : (m.list.VerticalAlignment || 'Top');
    const crossAlign = horiz ? (m.list.VerticalAlignment || 'Top') : (m.list.HorizontalAlignment || 'Left');
    const mainLen = horiz ? cw : ch, crossLen = horiz ? ch : cw;
    let cursor = /Center/.test(mainAlign) ? (mainLen - total) / 2 : /Right|Bottom/.test(mainAlign) ? mainLen - total : 0;
    for (const c of sorted) {
      const cs = horiz ? c._h : c._w;
      const off = /Center/.test(crossAlign) ? (crossLen - cs) / 2 : /Right|Bottom/.test(crossAlign) ? crossLen - cs : 0;
      if (horiz) { c._x = padL + cursor; c._y = padT + off; cursor += c._w + gap; }
      else { c._x = padL + off; c._y = padT + cursor; cursor += c._h + gap; }
    }
  } else {
    for (const c of kids) {
      const p = c.Position || {xs:0, xo:0, ys:0, yo:0}, a = c.AnchorPoint || {x:0, y:0};
      c._x = padL + p.xs * cw + p.xo - a.x * c._w;
      c._y = padT + p.ys * ch + p.yo - a.y * c._h;
    }
  }
  return [w, h];
}

function fitText(text, f, w, h) {
  let lo = 1, hi = 100;
  while (hi - lo > 0.5) { const mid = (lo + hi) / 2; const [tw, th] = measure(text, f, mid); if (tw <= w && th <= h) lo = mid; else hi = mid; }
  return lo;
}

function render(n, parentEl) {
  if (!GUI.has(n.ClassName) || n.Visible === false) return;
  const m = mods(n);
  const el = document.createElement('div'); el.className = 'n';
  el.style.left = n._x + 'px'; el.style.top = n._y + 'px'; el.style.width = n._w + 'px'; el.style.height = n._h + 'px';
  const tf = [];
  if (n.Rotation) tf.push(`rotate(${n.Rotation}deg)`);
  if (m.scale && m.scale.Scale !== 1) tf.push(`scale(${m.scale.Scale})`);
  if (tf.length) { el.style.transform = tf.join(' '); const a = n.AnchorPoint || {x:0.5, y:0.5}; el.style.transformOrigin = m.scale ? `${a.x*100}% ${a.y*100}%` : '50% 50%'; }
  const skin = document.createElement('div'); skin.className = 'skin';
  const bt = n.BackgroundTransparency === undefined ? 0 : n.BackgroundTransparency;
  if (bt < 1 && n.BackgroundColor3) skin.style.background = col(n.BackgroundColor3, 1 - bt);
  if (m.corner && m.corner.CornerRadius) { const r = m.corner.CornerRadius.s * Math.min(n._w, n._h) + m.corner.CornerRadius.o; skin.style.borderRadius = Math.min(r, Math.min(n._w, n._h) / 2) + 'px'; }
  const textStroke = m.stroke && m.stroke.ApplyStrokeMode === 'Contextual' && isText(n);
  if (m.stroke && !textStroke) skin.style.boxShadow = `0 0 0 ${m.stroke.Thickness}px ${col(m.stroke.Color, 1 - (m.stroke.Transparency || 0))}`;
  el.appendChild(skin);
  if (isText(n) && n.Text !== '' && (n.TextTransparency || 0) < 1) {
    const t = document.createElement('div'); t.className = 'txt';
    // UIPadding also insets the text of TextLabels/TextButtons.
    const tp = m.pad || {};
    const pl = ud(tp.PaddingLeft, n._w), pr = ud(tp.PaddingRight, n._w), pt = ud(tp.PaddingTop, n._h), pb = ud(tp.PaddingBottom, n._h);
    t.style.left = pl + 'px'; t.style.right = pr + 'px'; t.style.top = pt + 'px'; t.style.bottom = pb + 'px';
    const f = fontOf(n);
    const size = n.TextScaled ? fitText(n.Text, f, n._w - pl - pr, n._h - pt - pb) : (n.TextSize || 14);
    t.style.fontFamily = f.family; t.style.fontWeight = f.weight; t.style.fontSize = size + 'px';
    t.style.color = col(n.TextColor3, 1 - (n.TextTransparency || 0));
    t.style.justifyContent = {Left: 'flex-start', Right: 'flex-end'}[n.TextXAlignment] || 'center';
    t.style.alignItems = {Top: 'flex-start', Bottom: 'flex-end'}[n.TextYAlignment] || 'center';
    t.style.textAlign = {Left: 'left', Right: 'right'}[n.TextXAlignment] || 'center';
    const span = document.createElement('span'); span.textContent = n.Text;
    if (n.TextWrapped && !n.TextScaled) { span.style.whiteSpace = 'normal'; span.style.width = '100%'; } else span.style.whiteSpace = 'pre';
    if (n.TextTruncate === 'AtEnd') { span.style.overflow = 'hidden'; span.style.textOverflow = 'ellipsis'; span.style.maxWidth = '100%'; }
    if (textStroke) { span.style.webkitTextStroke = `${m.stroke.Thickness * 2}px ${col(m.stroke.Color)}`; span.style.paintOrder = 'stroke fill'; }
    t.appendChild(span); el.appendChild(t);
  }
  const kidsEl = document.createElement('div'); kidsEl.className = 'kids';
  if (n.ClipsDescendants || n.ClassName === 'ScrollingFrame') kidsEl.style.overflow = 'hidden';
  const kids = kidsOf(n).map((c, i) => [c, i]).sort((a, b) => ((a[0].ZIndex || 1) - (b[0].ZIndex || 1)) || (a[1] - b[1])).map(x => x[0]);
  for (const c of kids) render(c, kidsEl);
  if (n.ClassName === 'ScrollingFrame') {
    let bottom = 0; for (const c of kidsOf(n)) bottom = Math.max(bottom, c._y + c._h);
    const pad = m.pad || {}; bottom += ud(pad.PaddingBottom, n._h);
    if (bottom > n._h + 1 && n.ScrollBarThickness) {
      const bar = document.createElement('div'); const t = n.ScrollBarThickness;
      bar.style.cssText = `position:absolute;right:0;top:0;width:${t}px;height:${n._h * n._h / bottom}px;border-radius:${t/2}px;background:${col(n.ScrollBarImageColor3 || {r:0,g:0,b:0})}`;
      kidsEl.appendChild(bar);
    }
  }
  el.appendChild(kidsEl);
  parentEl.appendChild(el);
}

document.fonts.ready.then(() => {
  const state = STATES.find(s => s.name === stateName + '@' + W + 'x' + H) || STATES.find(s => s.name.startsWith(stateName + '@1280x720'));
  const root = state.tree;
  const screen = document.getElementById('screen');
  screen.style.width = W + 'px'; screen.style.height = H + 'px';
  root._w = W; root._h = H;
  const kids = kidsOf(root);
  kids.forEach(c => layout(c, W, H));
  for (const c of kids) { const p = c.Position || {xs:0,xo:0,ys:0,yo:0}, a = c.AnchorPoint || {x:0,y:0}; c._x = p.xs*W + p.xo - a.x*c._w; c._y = p.ys*H + p.yo - a.y*c._h; }
  kids.map((c, i) => [c, i]).sort((a, b) => ((a[0].ZIndex || 1) - (b[0].ZIndex || 1)) || (a[1] - b[1])).forEach(x => render(x[0], screen));
  document.title = 'ready';
});
</script></body></html>"""


def build_html(tree_path, html_path):
    with open(tree_path, encoding="utf-8") as handle:
        states = json.load(handle)
    html = (HTML.replace("__FREDOKA__", font_b64("FredokaOne-Regular.ttf"))
            .replace("__NUNITO__", font_b64("Nunito-Regular.ttf"))
            .replace("__STATES__", json.dumps(states, ensure_ascii=False)))
    with open(html_path, "w", encoding="utf-8") as handle:
        handle.write(html)


def shoot(html_path, state, width, height, png_path):
    url = "file:///" + html_path.replace("\\", "/") + f"?state={state}&w={width}&h={height}"
    profile = tempfile.mkdtemp(prefix="chrome-preview-")
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    f"--user-data-dir={profile}", f"--window-size={width},{height}", "--virtual-time-budget=5000",
                    f"--screenshot={png_path}", url], check=True, capture_output=True, timeout=120)


def main():
    tree = os.path.join(HERE, "tree.json")
    html = os.path.join(OUT, "preview.html")
    build_html(tree, html)
    shots = [("home", 1280, 720), ("shop", 1280, 720), ("settings", 1280, 720), ("inventory", 1280, 720),
             ("quests", 1280, 720), ("home", 844, 390), ("shop", 844, 390), ("settings", 844, 390),
             ("home", 667, 375), ("home", 1920, 1080), ("interact", 1280, 720),
             ("inventory", 844, 390), ("quests", 667, 375), ("shop", 667, 375)]
    only = set(sys.argv[1:])
    for state, width, height in shots:
        name = f"preview_{state}_{width}x{height}.png"
        if only and name not in only and state not in only:
            continue
        shoot(html, state, width, height, os.path.join(OUT, name))
        print("wrote", name)


if __name__ == "__main__":
    main()
