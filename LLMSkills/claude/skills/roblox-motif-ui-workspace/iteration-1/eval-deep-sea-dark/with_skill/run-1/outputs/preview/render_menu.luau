--!nocheck
-- Offline preview of the REAL MainMenu instance tree (no Studio): builds the menu with the project's
-- Lune mock, runs a small Roblox-like layout pass (UDim2 + AnchorPoint, UIPadding, UIListLayout,
-- UISizeConstraint, UIScale, AutomaticSize X), feeds AbsoluteSize back so the skin's listeners
-- (responsive layout, kit icons, lips) react, then writes one HTML file per scenario.
-- Approximation: Google-font stand-ins for Roblox faces, CSS box-shadow for UIStroke(Border),
-- CSS gradients for UIGradient, estimated TextScaled sizes. It shows composition, colour and
-- hierarchy; it is not a pixel-exact Roblox render.
--
--   (from the obby-rush folder)  lune run ../preview/render_menu.luau [outDir = ..]   -> <outDir>/render-*.html
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local rb = require("@lune/roblox")

local OUT = process.args[1] or ".."
if not fs.isDir(OUT) then fs.writeDir(OUT) end
local Mock = luau.load(fs.readFile("tests/mock.luau"), {debugName = "mock"})()
local node = Mock.node

local STATE = {
	coins = 1250,
	products = {
		{id = "speed_coil", name = "スピードコイル", price = 300},
		{id = "rainbow_trail", name = "虹のトレイル", price = 450},
		{id = "double_jump", name = "ダブルジャンプ", price = 800},
	},
	settings = {music = true, sfx = false},
}

local function boot(skinned)
	local game = node("DataModel", {Name = "Game"})
	local replicated = node("Folder", {Name = "ReplicatedStorage", Parent = game})
	local starterPlayer = node("Folder", {Name = "StarterPlayer", Parent = game})
	local starterScripts = node("Folder", {Name = "StarterPlayerScripts", Parent = starterPlayer})
	local playerGui = node("Folder", {Name = "PlayerGui"})
	local services = {
		ReplicatedStorage = replicated, StarterPlayer = starterPlayer,
		Players = {LocalPlayer = {Name = "Tester", UserId = 1, PlayerGui = playerGui}},
		RunService = {Heartbeat = Mock.signal()}, TweenService = Mock.tweenService(),
		-- Rest pose: no loops, so the mock's instant tweens do not jump bubbles/halo to their ends.
		GuiService = {ReducedMotionEnabled = true},
		UserInputService = {TouchEnabled = false},
	}
	function game:GetService(name) return services[name] end
	local sources, cache = {}, {}
	local requireModule
	function requireModule(target)
		if cache[target] ~= nil then return cache[target] end
		if not skinned and target.Name == "DeepSeaSkin" then error("skin disabled for the before render") end
		local env = Mock.environment({services = services, require = function(t) return requireModule(t) end})
		env.game, env.script = game, target
		local result = luau.load(fs.readFile(sources[target]), {debugName = sources[target], environment = env})()
		cache[target] = result
		return result
	end
	local function mount(dir, parent)
		for _, entry in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. entry
			if fs.isDir(path) then
				mount(path, node("Folder", {Name = entry, Parent = parent}))
			else
				local name = string.match(entry, "^(.-)%.luau$")
				if name and not string.find(name, "%.client$") then
					sources[node("ModuleScript", {Name = name, Parent = parent})] = path
				end
			end
		end
	end
	mount("src/shared", node("Folder", {Name = "Shared", Parent = replicated}))
	local client = node("Folder", {Name = "Client", Parent = starterScripts})
	mount("src/client", client)
	local MainMenu = requireModule(client.MainMenu)
	local noop = function() end
	local gui = MainMenu.build(playerGui, {play = noop, buy = noop, toggle = noop, navigate = noop}, STATE)
	return MainMenu, gui
end

-- Layout ------------------------------------------------------------------------------------------
local E = rb.Enum
local function udim(u, size) return u and (u.Scale * size + u.Offset) or 0 end
local function padding(obj, w, h)
	local p = obj:FindFirstChildOfClass("UIPadding")
	if not p then return 0, 0, 0, 0 end
	return udim(p.PaddingLeft, w), udim(p.PaddingTop, h), udim(p.PaddingRight, w), udim(p.PaddingBottom, h)
end
local function isGui(obj) return obj:IsA("GuiObject") end

local function charWidth(cp, display)
	if cp == 0xFE0F or cp == 0x200D then return 0 end
	if cp >= 0x1F000 or (cp >= 0x2190 and cp <= 0x2BFF) then return 1.3 end
	if cp >= 0x2E80 then return 1.0 end
	if cp == 32 then return 0.3 end
	return display and 0.66 or 0.58
end
local function textUnits(text, display)
	local units = 0
	for _, cp in utf8.codes(text) do units += charWidth(cp, display) end
	return units
end
local function familyOf(obj)
	local face = obj.FontFace
	if type(face) == "table" and face.Family then
		return string.match(face.Family, "families/(.-)%.json") or "Nunito", tostring(face.Weight or "")
	end
	local enum = tostring(obj.Font or "")
	if string.find(enum, "Gotham") then return "GothamSSm", string.find(enum, "Bold") and "Bold" or "Medium" end
	return "Arial", "Regular"
end

local layout = {}
local changed = false
local function setAbs(obj, w, h)
	local old = obj.AbsoluteSize
	if not old or math.abs(old.X - w) > 0.5 or math.abs(old.Y - h) > 0.5 then
		changed = true
		obj.AbsoluteSize = rb.Vector2.new(w, h)
	end
end

local compute
local function sizeOf(obj, pw, ph)
	local s = obj.Size or rb.UDim2.new()
	local w, h = udim(s.X, pw), udim(s.Y, ph)
	local c = obj:FindFirstChildOfClass("UISizeConstraint")
	if c then
		if c.MaxSize then w, h = math.min(w, c.MaxSize.X), math.min(h, c.MaxSize.Y) end
		if c.MinSize then w, h = math.max(w, c.MinSize.X), math.max(h, c.MinSize.Y) end
	end
	if obj.AutomaticSize == E.AutomaticSize.X and type(obj.Text) == "string" then
		local l, _, r = padding(obj, w, h)
		w = math.max(w, textUnits(obj.Text, false) * (obj.TextSize or 14) + l + r)
	end
	return w, h
end

function compute(obj, x, y, w, h)
	layout[obj] = {x = x, y = y, w = w, h = h}
	setAbs(obj, w, h)
	local l, t, r, b = padding(obj, w, h)
	local cw, ch = w - l - r, h - t - b
	local list = obj:FindFirstChildOfClass("UIListLayout")
	local kids = {}
	for _, child in ipairs(obj:GetChildren()) do if isGui(child) then table.insert(kids, child) end end
	if list then
		table.sort(kids, function(a, c) return (a.LayoutOrder or 0) < (c.LayoutOrder or 0) end)
		local horizontal = list.FillDirection == E.FillDirection.Horizontal
		local gap = udim(list.Padding, horizontal and cw or ch)
		local sizes, total = {}, 0
		for i, child in ipairs(kids) do
			if child.Visible ~= false then
				local kw, kh = sizeOf(child, cw, ch)
				sizes[i] = {kw, kh}
				total += (horizontal and kw or kh) + (total > 0 and gap or 0)
			end
		end
		local cursor = 0
		if horizontal and list.HorizontalAlignment == E.HorizontalAlignment.Center then cursor = (cw - total) / 2 end
		for i, child in ipairs(kids) do
			if sizes[i] then
				local kw, kh = sizes[i][1], sizes[i][2]
				if horizontal then compute(child, l + cursor, t, kw, kh); cursor += kw + gap
				else compute(child, l, t + cursor, kw, kh); cursor += kh + gap end
			end
		end
	else
		for _, child in ipairs(kids) do
			local kw, kh = sizeOf(child, cw, ch)
			local p = child.Position or rb.UDim2.new()
			local a = child.AnchorPoint or rb.Vector2.new(0, 0)
			compute(child, l + udim(p.X, cw) - a.X * kw, t + udim(p.Y, ch) - a.Y * kh, kw, kh)
		end
	end
end

local function layoutPass(gui, width, height)
	for _ = 1, 6 do
		changed = false
		layout = {}
		layout[gui] = {x = 0, y = 0, w = width, h = height}
		for _, child in ipairs(gui:GetChildren()) do
			if isGui(child) then
				local kw, kh = sizeOf(child, width, height)
				local p, a = child.Position or rb.UDim2.new(), child.AnchorPoint or rb.Vector2.new(0, 0)
				compute(child, udim(p.X, width) - a.X * kw, udim(p.Y, height) - a.Y * kh, kw, kh)
			end
		end
		if not changed then break end
	end
end

-- HTML --------------------------------------------------------------------------------------------
local CSS_FAMILY = {LuckiestGuy = "Luckiest Guy", FredokaOne = "Fredoka One", Nunito = "Nunito", GothamSSm = "Montserrat", Arial = "Arimo"}
local WEIGHT = {Regular = 400, Medium = 500, SemiBold = 600, Bold = 700, ExtraBold = 800, Heavy = 900}
local function rgba(c, transparency)
	return string.format("rgba(%d,%d,%d,%.3f)", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5), 1 - (transparency or 0))
end
local function sampleColor(seq, t)
	local kps = seq.Keypoints
	for i = 1, #kps - 1 do
		local a, b = kps[i], kps[i + 1]
		if t >= a.Time and t <= b.Time then
			local f = b.Time > a.Time and (t - a.Time) / (b.Time - a.Time) or 0
			return a.Value:Lerp(b.Value, f)
		end
	end
	return kps[#kps].Value
end
local function sampleNumber(seq, t)
	local kps = seq.Keypoints
	for i = 1, #kps - 1 do
		local a, b = kps[i], kps[i + 1]
		if t >= a.Time and t <= b.Time then
			local f = b.Time > a.Time and (t - a.Time) / (b.Time - a.Time) or 0
			return a.Value + (b.Value - a.Value) * f
		end
	end
	return kps[#kps].Value
end
local function background(obj)
	local transparency = obj.BackgroundTransparency or 0
	if transparency >= 0.999 or not obj.BackgroundColor3 then return "" end
	local grad = obj:FindFirstChildOfClass("UIGradient")
	if not grad or grad.Enabled == false then return "background:" .. rgba(obj.BackgroundColor3, transparency) .. ";" end
	local times = {}
	local seen = {}
	for _, key in ipairs({"Color", "Transparency"}) do
		local seq = grad[key]
		if seq then for _, kp in ipairs(seq.Keypoints) do if not seen[kp.Time] then seen[kp.Time] = true; table.insert(times, kp.Time) end end end
	end
	table.sort(times)
	local offset = grad.Offset and grad.Offset.Y or 0
	local stops = {}
	for _, t in ipairs(times) do
		local color = obj.BackgroundColor3
		if grad.Color then local g = sampleColor(grad.Color, t); color = rb.Color3.new(color.R * g.R, color.G * g.G, color.B * g.B) end
		local alpha = (1 - transparency) * (1 - (grad.Transparency and sampleNumber(grad.Transparency, t) or 0))
		table.insert(stops, string.format("%s %.2f%%", rgba(color, 1 - alpha), (t + offset) * 100))
	end
	return string.format("background:linear-gradient(%ddeg,%s);", math.floor((grad.Rotation or 0) + 90), table.concat(stops, ","))
end

local function emit(obj, out)
	local L = layout[obj]
	if not L or obj.Visible == false then return end
	local style = {string.format("left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx;z-index:%d;", L.x, L.y, L.w, L.h, obj.ZIndex or 1)}
	table.insert(style, background(obj))
	local corner = obj:FindFirstChildOfClass("UICorner")
	if corner then
		local radius = math.min(udim(corner.CornerRadius, math.min(L.w, L.h)), math.min(L.w, L.h) / 2)
		table.insert(style, string.format("border-radius:%.1fpx;", radius))
	end
	local textStroke = ""
	for _, child in ipairs(obj:GetChildren()) do
		if child.ClassName == "UIStroke" and (child.Enabled ~= false) and (child.Transparency or 0) < 0.999 then
			local contextual = child.ApplyStrokeMode == E.ApplyStrokeMode.Contextual
				or (child.ApplyStrokeMode == nil and type(obj.Text) == "string")
			if contextual and type(obj.Text) == "string" then
				textStroke = string.format("-webkit-text-stroke:%.1fpx %s;paint-order:stroke fill;", child.Thickness * 2, rgba(child.Color, child.Transparency))
			elseif not contextual then
				table.insert(style, string.format("box-shadow:0 0 0 %.1fpx %s;", child.Thickness, rgba(child.Color, child.Transparency)))
			end
		end
	end
	local transforms = {}
	if obj.Rotation and obj.Rotation ~= 0 then table.insert(transforms, string.format("rotate(%.1fdeg)", obj.Rotation)) end
	local scale = obj:FindFirstChildOfClass("UIScale")
	if scale and scale.Scale and scale.Scale ~= 1 then
		local a = obj.AnchorPoint or rb.Vector2.new(0, 0)
		table.insert(style, string.format("transform-origin:%.0f%% %.0f%%;", a.X * 100, a.Y * 100))
		table.insert(transforms, string.format("scale(%.3f)", scale.Scale))
	end
	if #transforms > 0 then table.insert(style, "transform:" .. table.concat(transforms, " ") .. ";") end
	if obj.ClipsDescendants or obj.ClassName == "ScrollingFrame" then table.insert(style, "overflow:hidden;") end
	table.insert(out, string.format('<div class="g" data-name="%s" style="%s">', obj.Name, table.concat(style)))
	if type(obj.Text) == "string" and obj.Text ~= "" and (obj.TextTransparency or 0) < 1 then
		local family, weight = familyOf(obj)
		local display = family == "LuckiestGuy"
		local l, t, r, b = padding(obj, L.w, L.h)
		local size = obj.TextSize or 14
		if obj.TextScaled then
			local c = obj:FindFirstChildOfClass("UITextSizeConstraint")
			local maxSize, minSize = c and c.MaxTextSize or 100, c and c.MinTextSize or 1
			size = math.clamp(math.min((L.h - t - b) * 0.9, (L.w - l - r) / math.max(textUnits(obj.Text, display), 1)), minSize, maxSize)
		end
		local jx = ({[tostring(E.TextXAlignment.Left)] = "flex-start", [tostring(E.TextXAlignment.Right)] = "flex-end"})[tostring(obj.TextXAlignment)] or "center"
		local jy = ({[tostring(E.TextYAlignment.Top)] = "flex-start", [tostring(E.TextYAlignment.Bottom)] = "flex-end"})[tostring(obj.TextYAlignment)] or "center"
		local weightName = string.match(weight, "FontWeight%.(%a+)") or weight
		table.insert(out, string.format(
			'<div class="t" style="left:%.1fpx;top:%.1fpx;right:%.1fpx;bottom:%.1fpx;justify-content:%s;align-items:%s;text-align:%s;font-family:\'%s\',\'Noto Sans JP\',\'Segoe UI Emoji\',sans-serif;font-weight:%d;font-size:%.1fpx;color:%s;white-space:%s;%s">%s</div>',
			l, t, r, b, jx, jy, jx == "flex-start" and "left" or jx == "flex-end" and "right" or "center",
			CSS_FAMILY[family] or family, WEIGHT[weightName] or 700, size, rgba(obj.TextColor3 or rb.Color3.new(), obj.TextTransparency),
			obj.TextWrapped and "normal" or "nowrap", textStroke, (string.gsub(obj.Text, "<", "&lt;"))))
	end
	for _, child in ipairs(obj:GetChildren()) do
		if isGui(child) then emit(child, out) end
	end
	table.insert(out, "</div>")
end

local function page(gui, width, height, title)
	layoutPass(gui, width, height)
	local out = {}
	for _, child in ipairs(gui:GetChildren()) do if isGui(child) then emit(child, out) end end
	return string.format([[<!doctype html><html><head><meta charset="utf-8"><title>%s</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Luckiest+Guy&family=Fredoka+One&family=Nunito:wght@700;900&family=Montserrat:wght@500;700&family=Noto+Sans+JP:wght@500;700;900&display=swap">
<style>html,body{margin:0;width:%dpx;height:%dpx;overflow:hidden;background:#3a4a3a}
.g{position:absolute;box-sizing:border-box}.t{position:absolute;display:flex;line-height:1.05;pointer-events:none}</style></head>
<body><div class="g" style="left:0;top:0;width:%dpx;height:%dpx;overflow:hidden;background:repeating-linear-gradient(135deg,#6d7f5e 0 40px,#7d8f6c 40px 80px)">%s</div></body></html>]],
		title, width, height, width, height, table.concat(out))
end

local SCENES = {
	{"after_desktop_main", true, 1280, 720, nil},
	{"after_desktop_shop", true, 1280, 720, "Shop"},
	{"after_desktop_settings", true, 1280, 720, "Settings"},
	{"after_desktop_inventory", true, 1280, 720, "Inventory"},
	{"after_landscape_main", true, 828, 369, nil},
	{"after_landscape_shop", true, 828, 369, "Shop"},
	{"after_portrait_main", true, 366, 820, nil},
	{"after_portrait_shop", true, 366, 820, "Shop"},
	{"before_desktop_main", false, 1280, 720, nil},
	{"before_desktop_shop", false, 1280, 720, "Shop"},
}
for _, scene in ipairs(SCENES) do
	local MainMenu, gui = boot(scene[2])
	-- first pass sizes everything; opening a page then re-lays out
	layoutPass(gui, scene[3], scene[4])
	if scene[5] then MainMenu.open(gui, scene[5]) end
	fs.writeFile(OUT .. "/render-" .. scene[1] .. ".html", page(gui, scene[3], scene[4], scene[1]))
	print("wrote", scene[1], scene[3] .. "x" .. scene[4])
end
