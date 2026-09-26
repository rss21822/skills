--!nocheck
-- Preview renderer: builds the REAL menu (src/ through the same mock DataModel as the tests), opens a
-- screen, and writes the resulting Instance tree as absolutely-positioned HTML (UDim2 -> calc(), UICorner,
-- UIStroke, UIGradient, UIPadding, UIListLayout, UIScale, ZIndex, text alignment, fonts). Headless Chrome
-- then screenshots it and runs a layout audit (text fit, 48 px targets, overlaps, Roblox top bar).
-- It approximates Roblox's renderer (fonts are the Google Fonts equivalents, CJK falls back to Noto Sans
-- JP); it is a look check, not a substitute for Studio.
--
--   lune run skin-tests/render_preview.luau <out.html> <scenario> <width> <height> [srcRoot] [label]
--   scenario: home | shop | settings | inventory | quests
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local Harness = luau.load(fs.readFile("skin-tests/harness.luau"), {debugName = "harness"})()
local rb = Harness.rb

local outPath, scenario = process.args[1], process.args[2] or "home"
local W, H = tonumber(process.args[3]) or 1280, tonumber(process.args[4]) or 720
local srcRoot = process.args[5] or "src"
local caption = process.args[6] or ""

local h = Harness.new({root = srcRoot})
local MainMenu = h.menu()
local gui = MainMenu.build(h.playerGui, (Harness.handlers()), Harness.state())
-- The mock has no layout engine: tell size-driven code the screen size (fires AbsoluteSize listeners).
local background = gui:FindFirstChild("Background")
if background then background.AbsoluteSize = rb.Vector2.new(W, H) end
local PAGE = {shop = "Shop", settings = "Settings", inventory = "Inventory", quests = "Quests"}
if PAGE[scenario] then MainMenu.open(gui, PAGE[scenario]) end

local FAMILY = {
	Oswald = "'Oswald'", Montserrat = "'Montserrat'", SpecialElite = "'Special Elite'", GothamSSm = "'Montserrat'",
	BuilderSans = "'Inter'", FredokaOne = "'Fredoka'", Nunito = "'Nunito'", LuckiestGuy = "'Luckiest Guy'",
}
local ENUM_FONT = {GothamBold = {"GothamSSm", 700}, GothamMedium = {"GothamSSm", 500}, Gotham = {"GothamSSm", 400}}

local function num(v) return string.format("%.3f", v) end
local function rgba(c, alpha)
	return string.format("rgba(%d,%d,%d,%s)", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5), num(alpha))
end
local function calc(scale, offset) return string.format("calc(%s%% + %spx)", num(scale * 100), num(offset)) end
local function esc(s)
	return (string.gsub(string.gsub(string.gsub(tostring(s), "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end
local function enumName(item) return item and item.Name or nil end

local function childrenOf(node, class)
	local out = {}
	for _, child in ipairs(node:GetChildren()) do
		if child.ClassName == class then table.insert(out, child) end
	end
	return out
end

-- Sample a ColorSequence / NumberSequence at time t (linear).
local function sampleColor(seq, t)
	local k = seq.Keypoints
	if t <= k[1].Time then return k[1].Value end
	for i = 2, #k do
		if t <= k[i].Time then
			local a, b = k[i - 1], k[i]
			local f = (b.Time - a.Time) > 0 and (t - a.Time) / (b.Time - a.Time) or 0
			return a.Value:Lerp(b.Value, f)
		end
	end
	return k[#k].Value
end
local function sampleNumber(seq, t)
	local k = seq.Keypoints
	if t <= k[1].Time then return k[1].Value end
	for i = 2, #k do
		if t <= k[i].Time then
			local a, b = k[i - 1], k[i]
			local f = (b.Time - a.Time) > 0 and (t - a.Time) / (b.Time - a.Time) or 0
			return a.Value + (b.Value - a.Value) * f
		end
	end
	return k[#k].Value
end

local function background_css(node)
	local transparency = node.BackgroundTransparency or 0
	if transparency >= 1 then return "" end
	local color = node.BackgroundColor3 or rb.Color3.new(1, 1, 1)
	local gradient = childrenOf(node, "UIGradient")[1]
	if gradient and gradient.Enabled ~= false and (gradient.Color or gradient.Transparency) then
		local times = {}
		local seen = {}
		local function add(t) t = math.floor(t * 10000 + 0.5) / 10000; if not seen[t] then seen[t] = true; table.insert(times, t) end end
		add(0); add(1)
		if gradient.Color then for _, k in ipairs(gradient.Color.Keypoints) do add(k.Time) end end
		if gradient.Transparency then for _, k in ipairs(gradient.Transparency.Keypoints) do add(k.Time) end end
		table.sort(times)
		local stops = {}
		local offset = gradient.Offset and gradient.Offset.Y or 0
		for _, t in ipairs(times) do
			local mult = gradient.Color and sampleColor(gradient.Color, t) or rb.Color3.new(1, 1, 1)
			local c = rb.Color3.new(color.R * mult.R, color.G * mult.G, color.B * mult.B)
			local a = (1 - transparency) * (1 - (gradient.Transparency and sampleNumber(gradient.Transparency, t) or 0))
			table.insert(stops, rgba(c, a) .. " " .. num((t + offset) * 100) .. "%")
		end
		return string.format("background:linear-gradient(%sdeg,%s);", num((gradient.Rotation or 0) + 90), table.concat(stops, ","))
	end
	return "background:" .. rgba(color, 1 - transparency) .. ";"
end

local function font_css(node)
	local family, weight = "GothamSSm", 400
	if type(node.FontFace) == "table" and node.FontFace.Family then
		family = string.match(node.FontFace.Family, "families/(.-)%.json") or family
		weight = node.FontFace.Weight and node.FontFace.Weight.Value or 400
	elseif node.Font then
		local mapped = ENUM_FONT[enumName(node.Font)]
		if mapped then family, weight = mapped[1], mapped[2] end
	end
	return string.format("font-family:%s,'Segoe UI Emoji','Noto Sans JP',sans-serif;font-weight:%d;", FAMILY[family] or "'Montserrat'", weight)
end

local function path(node)
	local parts = {}
	local cur = node
	while cur and cur ~= gui do
		table.insert(parts, 1, cur.Name)
		cur = cur.Parent
	end
	return table.concat(parts, ".")
end

local GUI = {Frame = true, TextLabel = true, TextButton = true, ScrollingFrame = true, TextBox = true, ImageLabel = true, ImageButton = true, CanvasGroup = true}

local render
local function renderChildren(node, layout)
	local out = {}
	for _, child in ipairs(node:GetChildren()) do
		if GUI[child.ClassName] then table.insert(out, render(child, layout)) end
	end
	return table.concat(out)
end

function render(node, inLayout)
	if node.Visible == false then return "" end
	local style = {}
	local size, pos = node.Size or rb.UDim2.new(), node.Position or rb.UDim2.new()
	local anchor = node.AnchorPoint or rb.Vector2.new()
	local auto = enumName(node.AutomaticSize)
	if inLayout then
		table.insert(style, "position:relative;flex:none;")
	else
		table.insert(style, string.format("position:absolute;left:%s;top:%s;", calc(pos.X.Scale, pos.X.Offset), calc(pos.Y.Scale, pos.Y.Offset)))
	end
	if auto == "X" or auto == "XY" then
		table.insert(style, "width:max-content;")
	else
		table.insert(style, "width:" .. calc(size.X.Scale, size.X.Offset) .. ";")
	end
	table.insert(style, "height:" .. calc(size.Y.Scale, size.Y.Offset) .. ";box-sizing:border-box;")
	local scale = 1
	for _, s in ipairs(childrenOf(node, "UIScale")) do scale *= (s.Scale or 1) end
	local transform = {}
	if not inLayout and (anchor.X ~= 0 or anchor.Y ~= 0) then
		table.insert(transform, string.format("translate(%s%%,%s%%)", num(-anchor.X * 100), num(-anchor.Y * 100)))
	end
	if (node.Rotation or 0) ~= 0 then table.insert(transform, "rotate(" .. num(node.Rotation) .. "deg)") end
	if scale ~= 1 then table.insert(transform, "scale(" .. num(scale) .. ")") end
	if #transform > 0 then
		table.insert(style, "transform:" .. table.concat(transform, " ") .. ";")
		table.insert(style, string.format("transform-origin:%s%% %s%%;", num((scale ~= 1 and anchor.X or 0.5) * 100), num((scale ~= 1 and anchor.Y or 0.5) * 100)))
	end
	table.insert(style, "z-index:" .. tostring(node.ZIndex or 1) .. ";")
	table.insert(style, background_css(node))
	local cornerItem = childrenOf(node, "UICorner")[1]
	if cornerItem then
		local r = cornerItem.CornerRadius or rb.UDim.new(0, 8)
		if r.Scale >= 0.5 then
			table.insert(style, "border-radius:9999px;")
		elseif r.Scale > 0 then
			table.insert(style, "border-radius:" .. num(r.Scale * 100) .. "%;")
		else
			table.insert(style, "border-radius:" .. num(r.Offset) .. "px;")
		end
	end
	local textStroke = ""
	for _, s in ipairs(childrenOf(node, "UIStroke")) do
		if s.Enabled ~= false and (s.Transparency or 0) < 1 then
			local mode = enumName(s.ApplyStrokeMode)
			if mode == "Border" then
				table.insert(style, string.format("box-shadow:0 0 0 %spx %s;", num(s.Thickness or 1), rgba(s.Color or rb.Color3.new(), 1 - (s.Transparency or 0))))
			elseif mode == "Contextual" then
				textStroke = string.format("-webkit-text-stroke:%spx %s;paint-order:stroke fill;", num((s.Thickness or 1) * 2), rgba(s.Color or rb.Color3.new(), 1 - (s.Transparency or 0)))
			end
		end
	end
	if node.ClipsDescendants or node.ClassName == "ScrollingFrame" then table.insert(style, "overflow:hidden;") end

	local pad = childrenOf(node, "UIPadding")[1]
	local pl, pr, pt, pb = 0, 0, 0, 0
	if pad then
		pl, pr = pad.PaddingLeft and pad.PaddingLeft.Offset or 0, pad.PaddingRight and pad.PaddingRight.Offset or 0
		pt, pb = pad.PaddingTop and pad.PaddingTop.Offset or 0, pad.PaddingBottom and pad.PaddingBottom.Offset or 0
	end
	local content = string.format("position:absolute;left:%spx;right:%spx;top:%spx;bottom:%spx;", num(pl), num(pr), num(pt), num(pb))
	local layout = childrenOf(node, "UIListLayout")[1]
	if layout then
		local horizontal = enumName(layout.FillDirection) == "Horizontal"
		local ha, va = enumName(layout.HorizontalAlignment) or "Left", enumName(layout.VerticalAlignment) or "Top"
		local map = {Left = "flex-start", Top = "flex-start", Center = "center", Right = "flex-end", Bottom = "flex-end"}
		content ..= string.format("display:flex;flex-direction:%s;gap:%spx;justify-content:%s;align-items:%s;",
			horizontal and "row" or "column", num(layout.Padding and layout.Padding.Offset or 0),
			map[horizontal and ha or va], map[horizontal and va or ha])
	end

	local attrs = string.format(" data-path='%s' data-class='%s'", esc(path(node)), node.ClassName)
	if node.ClassName == "TextButton" or node.ClassName == "ImageButton" then attrs ..= " data-button='1'" end
	local body = {}
	if (node.ClassName == "TextLabel" or node.ClassName == "TextButton") and node.Text and node.Text ~= "" then
		local xa, ya = enumName(node.TextXAlignment) or "Center", enumName(node.TextYAlignment) or "Center"
		local justify = {Left = "flex-start", Center = "center", Right = "flex-end"}
		local align = {Top = "flex-start", Center = "center", Bottom = "flex-end"}
		local wrapped = node.TextWrapped == true
		local textSize = node.TextSize or 14
		local constraint = childrenOf(node, "UITextSizeConstraint")[1]
		if node.TextScaled and constraint then textSize = constraint.MaxTextSize or textSize end
		local color = node.TextColor3 or rb.Color3.new()
		table.insert(body, string.format(
			"<div data-text='1' data-path='%s' style=\"position:absolute;inset:0;display:flex;justify-content:%s;align-items:%s;text-align:%s;\">"
				.. "<span data-ts=\"%s\" style=\"display:inline-block;%s%sfont-size:%spx;line-height:1.12;color:%s;%s\">%s</span></div>",
			esc(path(node)), justify[xa] or "center", align[ya] or "center", string.lower(xa), num(textSize),
			wrapped and "max-width:100%;white-space:normal;word-break:normal;line-break:strict;" or "white-space:pre;",
			font_css(node), num(textSize), rgba(color, 1 - (node.TextTransparency or 0)), textStroke, esc(node.Text)))
	end
	table.insert(body, renderChildren(node, layout ~= nil))
	local order = inLayout and ("order:" .. tostring(node.LayoutOrder or 0) .. ";") or ""
	return string.format("<div%s style=\"%s%s\"><div style=\"%s\">%s</div></div>", attrs, table.concat(style), order, content, table.concat(body))
end

local screen = {}
for _, child in ipairs(gui:GetChildren()) do
	if GUI[child.ClassName] then table.insert(screen, render(child, false)) end
end

local html = [[<!doctype html><html><head><meta charset="utf-8"><title>MainMenu preview</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Oswald:wght@400;700&family=Montserrat:wght@400;500;700;800&family=Special+Elite&family=Noto+Sans+JP:wght@400;500;700;800;900&display=block">
<style>html,body{margin:0;padding:0;background:#1d1d1f}#screen{position:relative;width:]] .. W .. [[px;height:]] .. H .. [[px;overflow:hidden;background:#6f8a9a}
.rbx{position:absolute;top:8px;height:44px;border-radius:12px;background:rgba(18,18,21,.72);color:#fff;font:600 20px 'Segoe UI',sans-serif;display:flex;align-items:center;justify-content:center;z-index:100000}
#audit{white-space:pre;font:12px monospace;color:#ddd;padding:8px}#cap{font:13px 'Segoe UI',sans-serif;color:#bbb;padding:6px 8px}</style></head><body>
<div id="screen">]] .. table.concat(screen) .. [[
<div class="rbx" data-topbar="1" style="left:12px;width:44px">&#9776;</div><div class="rbx" data-topbar="1" style="left:64px;width:44px">&#128172;</div>
<div class="rbx" data-topbar="1" style="right:12px;width:44px">&#8943;</div></div>
<div id="cap">]] .. esc(caption) .. " — " .. scenario .. " " .. W .. "x" .. H .. [[ (rendered from the Luau instance tree)</div><div id="audit">pending</div>
<script>
function audit(){
  const out=[];const screen=document.getElementById('screen').getBoundingClientRect();const W=screen.width,H=screen.height;
  document.querySelectorAll('#screen [data-text]').forEach(box=>{const span=box.firstElementChild;const wrapped=span.style.whiteSpace==='normal';
    const ts=parseFloat(span.dataset.ts);const lines=Math.max(1,Math.round(span.offsetHeight/(ts*1.12)));
    const over=span.offsetWidth>box.clientWidth+1||lines*ts>box.clientHeight+2;
    if(over)out.push('FIT '+box.dataset.path+' "'+span.textContent.slice(0,28)+'" box '+box.clientWidth+'x'+box.clientHeight+' text '+span.offsetWidth+'x'+span.offsetHeight);});
  const rect=e=>{const r=e.getBoundingClientRect();return {l:r.left-screen.left,t:r.top-screen.top,r:r.right-screen.left,b:r.bottom-screen.top,w:r.width,h:r.height}};
  const topPath=(x,y)=>{let e=document.elementFromPoint(x,y);while(e&&!(e.dataset&&e.dataset.path))e=e.parentElement;return e?e.dataset.path:''};
  // Only buttons a player can actually hit count: skip ones under a page or scrolled out of view,
  // and report decorations that sit on top of a button.
  const buttons=[...document.querySelectorAll('#screen [data-button]')].filter(b=>{const r=b.getBoundingClientRect();
    const p=topPath((r.left+r.right)/2,(r.top+r.bottom)/2);if(p.startsWith(b.dataset.path))return true;
    const layer=q=>q.split('.')[0];
    if(/(^|\.)Motif/.test(p)&&!/MotifShade/.test(p)&&layer(p)===layer(b.dataset.path))out.push('DECOR-COVERS '+b.dataset.path+' by '+p);return false;});
  buttons.forEach(b=>{const r=rect(b);if(r.w<47.5||r.h<47.5)out.push('SMALL '+b.dataset.path+' '+Math.round(r.w)+'x'+Math.round(r.h));
    if(r.l<-1||r.t<-1||r.r>W+1||r.b>H+1)out.push('OFFSCREEN '+b.dataset.path);});
  for(let i=0;i<buttons.length;i++)for(let j=i+1;j<buttons.length;j++){const a=rect(buttons[i]),b=rect(buttons[j]);
    const ix=Math.min(a.r,b.r)-Math.max(a.l,b.l),iy=Math.min(a.b,b.b)-Math.max(a.t,b.t);
    if(ix>0&&iy>0&&ix*iy/Math.min(a.w*a.h,b.w*b.h)>0.2)out.push('OVERLAP '+buttons[i].dataset.path+' / '+buttons[j].dataset.path);}
  const zones=[{l:0,t:0,r:200,b:58},{l:W-110,t:0,r:W,b:58}];
  document.querySelectorAll('#screen [data-text],#screen [data-button]').forEach(e=>{const r=rect(e);
    zones.forEach(z=>{if(Math.min(r.r,z.r)-Math.max(r.l,z.l)>0&&Math.min(r.b,z.b)-Math.max(r.t,z.t)>0)out.push('TOPBAR '+e.dataset.path);});});
  const unique=[...new Set(out)];
  document.getElementById('audit').textContent=unique.length?unique.join('\n'):'AUDIT PASS';
}
document.fonts.ready.then(()=>setTimeout(audit,100));
</script></body></html>]]

fs.writeFile(outPath, html)
print("wrote " .. outPath)
