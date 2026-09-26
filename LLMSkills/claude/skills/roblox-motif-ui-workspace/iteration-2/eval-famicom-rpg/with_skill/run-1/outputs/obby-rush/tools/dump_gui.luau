--!nocheck
-- Builds the menu in the Lune mock and dumps what it would draw as JSON (absolute rects, colours, text,
-- fonts, paint order) for tools/render_preview.py. A small layout engine resolves UDim2 / AnchorPoint /
-- UIPadding / UIListLayout (incl. Wraps) / AutomaticSize / TextScaled + UITextSizeConstraint, so previews
-- and the audit come from the real Luau output, not a redrawn mock-up. Text widths are estimates.
--
--   lune run tools/dump_gui.luau <out.json> <width> <height> [page|-] [hover|-] [skin|plain]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Harness = luau.load(fs.readFile("tools/harness.luau"), {debugName = "harness"})()
local rb = Harness.rb
local E = rb.Enum

local out, width, height = process.args[1], tonumber(process.args[2] or "1280"), tonumber(process.args[3] or "720")
local pageId, hoverName = process.args[4] or "-", process.args[5] or "-"
local skinned = (process.args[6] or "skin") ~= "plain"

local h = Harness.new({width = width, height = height, skin = skinned})
local gui = h.build()
if pageId ~= "-" then h.MainMenu.open(gui, pageId) end
if hoverName ~= "-" then
	local target = gui:FindFirstChild(hoverName, true)
	if target then target.MouseEnter:Fire() end
end

local function cjkCount(text) return select(2, string.gsub(text, "[\227-\237\239][\128-\191][\128-\191]", "")) end
local function charCount(text) return select(2, string.gsub(text, "[^\128-\191]", "")) end
local LEGACY = {
	GothamMedium = {"GothamSSm", "Medium"}, GothamBold = {"GothamSSm", "Bold"}, Gotham = {"GothamSSm", "Regular"},
	Arcade = {"PressStart2P", "Regular"}, SourceSans = {"SourceSansPro", "Regular"},
}
local function fontOf(object)
	local face = object.FontFace
	if type(face) == "table" and face.Family then
		local family = string.match(tostring(face.Family), "families/(.-)%.json") or tostring(face.Family)
		local weight = face.Weight and string.match(tostring(face.Weight), "([%a]+)$") or "Regular"
		return family, weight
	end
	local legacy = object.Font and LEGACY[string.match(tostring(object.Font), "([%a]+)$") or ""]
	if legacy then return legacy[1], legacy[2] end
	return "SourceSansPro", "Regular"
end
local function estimate(text, size, family)
	local cjk = cjkCount(text)
	local other = charCount(text) - cjk
	local latin = family == "PressStart2P" and 1 or (family == "RobotoMono" and 0.6 or 0.56)
	return (cjk + other * latin) * size
end
local function hex(c)
	if c == nil then return nil end
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
local function udim(u, total) return u.Scale * total + u.Offset end
local function paddingOf(object, w, hgt)
	local pad = object:FindFirstChildOfClass("UIPadding")
	if not pad then return 0, 0, 0, 0 end
	local function v(u, total) return u and udim(u, total) or 0 end
	return v(pad.PaddingLeft, w), v(pad.PaddingRight, w), v(pad.PaddingTop, hgt), v(pad.PaddingBottom, hgt)
end
local function isGui(object) return object:IsA("GuiObject") end
local function textual(object) return object.ClassName == "TextLabel" or object.ClassName == "TextButton" or object.ClassName == "TextBox" end

local items, order = {}, 0

local function sizeOf(object, box)
	local s = object.Size or rb.UDim2.new()
	local w, hh = udim(s.X, box.w), udim(s.Y, box.h)
	if object.AutomaticSize == E.AutomaticSize.X or object.AutomaticSize == E.AutomaticSize.XY then
		local family = fontOf(object)
		local l, r = paddingOf(object, w, hh)
		w = math.max(w, estimate(object.Text or "", object.TextSize or 14, family) + l + r)
	end
	return w, hh
end

local function emit(object, x, y, w, hh, clip)
	order += 1
	local entry = {
		order = order, name = object.Name, class = object.ClassName, path = object:GetFullName(),
		x = x, y = y, w = w, h = hh, clip = clip,
		bg = hex(object.BackgroundColor3), bgT = object.BackgroundTransparency or 0,
		button = object:IsA("GuiButton"),
	}
	local corner = object:FindFirstChildOfClass("UICorner")
	if corner and corner.CornerRadius then entry.radius = corner.CornerRadius.Scale >= 0.5 and 9999 or corner.CornerRadius.Offset end
	for _, child in ipairs(object:GetChildren()) do
		if child.ClassName == "UIStroke" and (child.Transparency or 0) < 1 and child.Enabled ~= false
			and child.ApplyStrokeMode == E.ApplyStrokeMode.Border then
			entry.stroke = {color = hex(child.Color), t = child.Transparency or 0, w = child.Thickness or 1}
		end
	end
	if textual(object) and (object.Text or "") ~= "" then
		local family, weight = fontOf(object)
		local l, r, t, b = paddingOf(object, w, hh)
		local size = object.TextSize or 14
		if object.TextScaled then
			local constraint = object:FindFirstChildOfClass("UITextSizeConstraint")
			local maxSize = constraint and constraint.MaxTextSize or 100
			local minSize = constraint and constraint.MinTextSize or 1
			local unit = estimate(object.Text, 1, family)
			size = math.floor(math.max(minSize, math.min(maxSize, (w - l - r) / math.max(unit, 0.01), hh - t - b)))
		end
		local xa = object.TextXAlignment and string.match(tostring(object.TextXAlignment), "(%a+)$") or "Center"
		local ya = object.TextYAlignment and string.match(tostring(object.TextYAlignment), "(%a+)$") or "Center"
		entry.text = {
			value = object.Text, color = hex(object.TextColor3), t = object.TextTransparency or 0, size = size,
			family = family, weight = weight, xa = xa, ya = ya, wrapped = object.TextWrapped == true,
			pad = {l, r, t, b}, estWidth = estimate(object.Text, size, family),
		}
	end
	table.insert(items, entry)
end

local function intersect(a, b)
	if not a then return b end
	if not b then return a end
	local x1, y1 = math.max(a[1], b[1]), math.max(a[2], b[2])
	local x2, y2 = math.min(a[1] + a[3], b[1] + b[3]), math.min(a[2] + a[4], b[2] + b[4])
	return {x1, y1, math.max(0, x2 - x1), math.max(0, y2 - y1)}
end

local visit
local function layoutChildren(parent, box, clip)
	local kids = {}
	for index, child in ipairs(parent:GetChildren()) do
		if isGui(child) then table.insert(kids, {child = child, index = index}) end
	end
	local list = parent:FindFirstChildOfClass("UIListLayout")
	local placed = {}
	if list then
		local flow = {}
		for _, k in ipairs(kids) do if k.child.Visible ~= false then table.insert(flow, k) end end
		table.sort(flow, function(a, b)
			local la, lb = a.child.LayoutOrder or 0, b.child.LayoutOrder or 0
			if la ~= lb then return la < lb end
			return a.index < b.index
		end)
		local pad = list.Padding and udim(list.Padding, box.w) or 0
		local horizontal = list.FillDirection == E.FillDirection.Horizontal
		local ha = list.HorizontalAlignment and string.match(tostring(list.HorizontalAlignment), "(%a+)$") or "Left"
		local va = list.VerticalAlignment and string.match(tostring(list.VerticalAlignment), "(%a+)$") or "Top"
		local lines, line = {}, {items = {}, main = 0, cross = 0}
		for _, k in ipairs(flow) do
			local w, hh = sizeOf(k.child, box)
			local main, cross = horizontal and w or hh, horizontal and hh or w
			local limit = horizontal and box.w or box.h
			if list.Wraps and #line.items > 0 and line.main + pad + main > limit + 0.5 then
				table.insert(lines, line)
				line = {items = {}, main = 0, cross = 0}
			end
			line.main += (#line.items > 0 and pad or 0) + main
			line.cross = math.max(line.cross, cross)
			table.insert(line.items, {k = k, w = w, h = hh})
		end
		if #line.items > 0 then table.insert(lines, line) end
		local crossTotal = 0
		for i, l in ipairs(lines) do crossTotal += l.cross + (i > 1 and pad or 0) end
		local crossStart
		if horizontal then
			crossStart = va == "Center" and box.y + (box.h - crossTotal) / 2 or va == "Bottom" and box.y + box.h - crossTotal or box.y
		else
			crossStart = ha == "Center" and box.x + (box.w - crossTotal) / 2 or ha == "Right" and box.x + box.w - crossTotal or box.x
		end
		for _, l in ipairs(lines) do
			local mainStart
			if horizontal then
				mainStart = ha == "Center" and box.x + (box.w - l.main) / 2 or ha == "Right" and box.x + box.w - l.main or box.x
			else
				mainStart = va == "Center" and box.y + (box.h - l.main) / 2 or va == "Bottom" and box.y + box.h - l.main or box.y
			end
			for _, it in ipairs(l.items) do
				if horizontal then
					placed[it.k.child] = {mainStart, crossStart + (l.cross - it.h) / 2, it.w, it.h}
					mainStart += it.w + pad
				else
					placed[it.k.child] = {crossStart, mainStart, it.w, it.h}
					mainStart += it.h + pad
				end
			end
			crossStart += l.cross + pad
		end
	end
	table.sort(kids, function(a, b)
		local za, zb = a.child.ZIndex or 1, b.child.ZIndex or 1
		if za ~= zb then return za < zb end
		return a.index < b.index
	end)
	for _, k in ipairs(kids) do
		local child = k.child
		if child.Visible ~= false then
			local rect = placed[child]
			if not rect then
				local w, hh = sizeOf(child, box)
				local p = child.Position or rb.UDim2.new()
				local ap = child.AnchorPoint or rb.Vector2.new(0, 0)
				rect = {box.x + udim(p.X, box.w) - ap.X * w, box.y + udim(p.Y, box.h) - ap.Y * hh, w, hh}
			end
			visit(child, rect, clip)
		end
	end
end

function visit(object, rect, clip)
	local x, y, w, hh = rect[1], rect[2], rect[3], rect[4]
	emit(object, x, y, w, hh, clip)
	local l, r, t, b = paddingOf(object, w, hh)
	local childClip = clip
	if object.ClassName == "ScrollingFrame" or object.ClipsDescendants then childClip = intersect(clip, {x, y, w, hh}) end
	layoutChildren(object, {x = x + l, y = y + t, w = w - l - r, h = hh - t - b}, childClip)
end

layoutChildren(gui, {x = 0, y = 0, w = width, h = height}, nil)
fs.writeFile(out, serde.encode("json", {width = width, height = height, page = pageId, hover = hoverName,
	skinned = skinned, items = items}, true))
print(string.format("dumped %d drawables -> %s", #items, out))
