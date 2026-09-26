--!nocheck
-- Preview renderer: runs the project's real MainMenu.build under tests/mock.luau (same mounting as the
-- contract test), optionally drives it (open a page, hover, toggle), then lays out the resulting
-- instance tree the way Roblox would (UDim2, AnchorPoint, UIListLayout, UIAspectRatio/SizeConstraint,
-- UIPadding, UICorner, UIStroke, UIGradient, UIScale, Rotation, ZIndex) and writes absolute-positioned
-- HTML. Approximation for previews only; Japanese renders in Noto Sans JP (Roblox's CJK fallback look).
--
-- usage: lune run render_menu.luau <projectRoot> <mockPath> <width> <height> <scenario> <out.html>
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local rb = require("@lune/roblox")

local root, mockPath, W, H, scenario, outPath = table.unpack(process.args)
W, H = tonumber(W), tonumber(H)

local Mock = luau.load(fs.readFile(mockPath), {debugName = "mock"})()
local node = Mock.node

-- Mock DataModel, mounted like tests/test_main_menu.luau ------------------------------------------
local game = node("DataModel", {Name = "Game"})
local replicated = node("Folder", {Name = "ReplicatedStorage", Parent = game})
local starterPlayer = node("Folder", {Name = "StarterPlayer", Parent = game})
local starterScripts = node("Folder", {Name = "StarterPlayerScripts", Parent = starterPlayer})
local playerGui = node("Folder", {Name = "PlayerGui"})
local localPlayer = {Name = "Tester", UserId = 1, PlayerGui = playerGui}
function localPlayer:WaitForChild(name) return name == "PlayerGui" and playerGui or nil end
local runService = {Heartbeat = Mock.signal(), RenderStepped = Mock.signal(), Stepped = Mock.signal()}
function runService:IsClient() return true end
function runService:IsStudio() return false end
local services = {
	ReplicatedStorage = replicated, StarterPlayer = starterPlayer, Players = {LocalPlayer = localPlayer},
	RunService = runService, TweenService = Mock.tweenService(), GuiService = {ReducedMotionEnabled = false},
	UserInputService = {TouchEnabled = false, GetLastInputType = function() return rb.Enum.UserInputType.MouseMovement end,
		InputBegan = Mock.signal(), InputEnded = Mock.signal()},
	SoundService = node("Folder", {Name = "SoundService"}), TextService = {}, ContentProvider = {PreloadAsync = function() end},
}
function game:GetService(name) return services[name] end

local sources, cache = {}, {}
local requireModule
local function envFor(script)
	local env = Mock.environment({services = services, require = function(target) return requireModule(target) end})
	env.game, env.script = game, script
	env.workspace = {CurrentCamera = {ViewportSize = rb.Vector2.new(W, H)}}
	return env
end
function requireModule(target)
	if cache[target] ~= nil then return cache[target] end
	local path = assert(sources[target], "module not mounted")
	local result = luau.load(fs.readFile(path), {debugName = path, environment = envFor(target)})()
	cache[target] = result
	return result
end
local function mount(dir, parent)
	for _, entry in ipairs(fs.readDir(dir)) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			local folder = node("Folder", {Name = entry, Parent = parent})
			mount(path, folder)
		else
			local name, kind = string.match(entry, "^(.-)%.(%a+)%.luau?$")
			if not name then name = string.match(entry, "^(.-)%.luau?$") end
			if name then
				local class = kind == "client" and "LocalScript" or kind == "server" and "Script" or "ModuleScript"
				sources[node(class, {Name = name, Parent = parent})] = path
			end
		end
	end
end
mount(root .. "/src/shared", node("Folder", {Name = "Shared", Parent = replicated}))
mount(root .. "/src/client", node("Folder", {Name = "Client", Parent = starterScripts}))

local MainMenu = requireModule(starterScripts.Client:FindFirstChild("MainMenu"))
local noop = function() end
local gui = MainMenu.build(playerGui, {play = noop, buy = noop, toggle = noop, navigate = noop}, {
	coins = 1250,
	products = {
		{id = "speed_coil", name = "スピードコイル", price = 300},
		{id = "rainbow_trail", name = "虹のトレイル", price = 450},
		{id = "double_jump", name = "ダブルジャンプ", price = 800},
	},
	settings = {music = true, sfx = true},
})

-- Scenario ------------------------------------------------------------------------------------------
local function find(name) return gui:FindFirstChild(name, true) end
local click = {UserInputType = rb.Enum.UserInputType.MouseButton1}
local function activate(name) local b = find(name); b.Activated:Fire(click, 1) end
if scenario == "hover" then
	find("Nav_Quests").MouseEnter:Fire()
	find("PlayButton").MouseEnter:Fire()
elseif scenario == "shop" then
	activate("Nav_Shop")
	local row = find("Product_rainbow_trail")
	row:FindFirstChild("BuyButton", true).MouseEnter:Fire()
elseif scenario == "settings" then
	activate("Nav_Settings")
	activate("Toggle_Music")
elseif scenario == "inventory" then
	activate("Nav_Inventory")
end

-- Layout ----------------------------------------------------------------------------------------------
local function enumName(value, default)
	if value == nil then return default end
	local s = tostring(value)
	return string.match(s, "([%w_]+)$") or default
end
local function child(object, class)
	for _, c in ipairs(object:GetChildren()) do if c.ClassName == class then return c end end
	return nil
end
local function isGui(o)
	local c = o.ClassName
	return c == "Frame" or c == "TextLabel" or c == "TextButton" or c == "TextBox" or c == "ScrollingFrame"
		or c == "ImageLabel" or c == "ImageButton" or c == "CanvasGroup"
end
local function udim(u, full) return u.Scale * full + u.Offset end

local function applyConstraints(o, w, h)
	local aspect = child(o, "UIAspectRatioConstraint")
	if aspect then
		local a = aspect.AspectRatio or 1
		if w / math.max(h, 1e-6) > a then w = h * a else h = w / a end
	end
	local sc = child(o, "UISizeConstraint")
	if sc then
		local mn, mx = sc.MinSize or rb.Vector2.new(0, 0), sc.MaxSize or rb.Vector2.new(math.huge, math.huge)
		w = math.clamp(w, mn.X, mx.X); h = math.clamp(h, mn.Y, mx.Y)
	end
	return w, h
end

local function paddingOf(o, w, h)
	local p = child(o, "UIPadding")
	if not p then return 0, 0, 0, 0 end
	local function v(u, full) return u and udim(u, full) or 0 end
	return v(p.PaddingLeft, w), v(p.PaddingTop, h), v(p.PaddingRight, w), v(p.PaddingBottom, h)
end

local function css(c, alpha)
	return string.format("rgba(%d,%d,%d,%.3f)", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5), math.clamp(alpha, 0, 1))
end

local function gradientCss(gradient, color, baseAlpha)
	local stops = {}
	local seq = gradient.Transparency
	local points = seq and seq.Keypoints or {{Time = 0, Value = 0}, {Time = 1, Value = 0}}
	for _, kp in ipairs(points) do
		table.insert(stops, string.format("%s %.1f%%", css(color, baseAlpha * (1 - kp.Value)), kp.Time * 100))
	end
	return string.format("linear-gradient(%.1fdeg, %s)", (gradient.Rotation or 0) + 90, table.concat(stops, ", "))
end

local function esc(s)
	s = string.gsub(s, "&", "&amp;")
	s = string.gsub(s, "<", "&lt;")
	s = string.gsub(s, ">", "&gt;")
	return s
end

local function fontStack(font)
	local name = enumName(font, "Legacy")
	local jp = "'Noto Sans JP', 'Yu Gothic', sans-serif"
	if name == "Garamond" then return "Garamond, 'EB Garamond', Georgia, " .. jp, 400 end
	if string.find(name, "Gotham") then return "'Montserrat', 'Segoe UI', Arial, " .. jp, string.find(name, "Bold") and 700 or 500 end
	return "'Segoe UI', Arial, " .. jp, 400
end

local function glyphCount(line)
	local em = 0
	for g in string.gmatch(line, "[\1-\127\194-\244][\128-\191]*") do
		em += (#g > 1) and 1.0 or 0.56
	end
	return em
end

local function richToHtml(text, color, alpha)
	-- supports <font transparency="x">...</font>
	local out = {}
	local pos = 1
	while true do
		local s, e, t, inner = string.find(text, '<font transparency="([%d%.]+)">(.-)</font>', pos)
		if not s then table.insert(out, esc(string.sub(text, pos))); break end
		table.insert(out, esc(string.sub(text, pos, s - 1)))
		table.insert(out, string.format('<span style="color:%s">%s</span>', css(color, alpha * (1 - tonumber(t))), esc(inner)))
		pos = e + 1
	end
	return table.concat(out)
end

local html = {}
local function emit(s) table.insert(html, s) end

local render
local function renderChildren(o, x, y, w, h, clipTarget)
	local kids = {}
	for index, c in ipairs(o:GetChildren()) do
		if isGui(c) and c.Visible ~= false then table.insert(kids, {c = c, i = index}) end
	end
	local pl, pt, pr, pb = 0, 0, 0, 0
	if o.ClassName ~= "TextButton" and o.ClassName ~= "TextLabel" then pl, pt, pr, pb = paddingOf(o, w, h) end
	local cx, cy, cw, ch = x + pl, y + pt, w - pl - pr, h - pt - pb
	local list = child(o, "UIListLayout")
	local placed = {}
	if list then
		local horizontal = enumName(list.FillDirection, "Vertical") == "Horizontal"
		table.sort(kids, function(a, b)
			local la, lb = a.c.LayoutOrder or 0, b.c.LayoutOrder or 0
			if la ~= lb then return la < lb end
			return a.i < b.i
		end)
		local gap = list.Padding and udim(list.Padding, horizontal and cw or ch) or 0
		local sizes, total = {}, 0
		for _, k in ipairs(kids) do
			local sw, sh = applyConstraints(k.c, udim(k.c.Size.X, cw), udim(k.c.Size.Y, ch))
			sizes[k] = {sw, sh}
			total += horizontal and sw or sh
		end
		total += gap * math.max(#kids - 1, 0)
		local ha, va = enumName(list.HorizontalAlignment, "Left"), enumName(list.VerticalAlignment, "Top")
		local cursor
		if horizontal then
			cursor = ha == "Center" and cx + (cw - total) / 2 or ha == "Right" and cx + cw - total or cx
		else
			cursor = va == "Center" and cy + (ch - total) / 2 or va == "Bottom" and cy + ch - total or cy
		end
		for _, k in ipairs(kids) do
			local sw, sh = sizes[k][1], sizes[k][2]
			local kx, ky
			if horizontal then
				kx = cursor
				ky = va == "Center" and cy + (ch - sh) / 2 or va == "Bottom" and cy + ch - sh or cy
				cursor += sw + gap
			else
				ky = cursor
				kx = ha == "Center" and cx + (cw - sw) / 2 or ha == "Right" and cx + cw - sw or cx
				cursor += sh + gap
			end
			placed[k] = {kx, ky, sw, sh}
		end
	end
	table.sort(kids, function(a, b)
		local za, zb = a.c.ZIndex or 1, b.c.ZIndex or 1
		if za ~= zb then return za < zb end
		return a.i < b.i
	end)
	for _, k in ipairs(kids) do
		local rect = placed[k]
		if not rect then
			local sw, sh = applyConstraints(k.c, udim(k.c.Size.X, cw), udim(k.c.Size.Y, ch))
			local ap = k.c.AnchorPoint or rb.Vector2.new(0, 0)
			local pos = k.c.Position or rb.UDim2.new()
			rect = {cx + udim(pos.X, cw) - ap.X * sw, cy + udim(pos.Y, ch) - ap.Y * sh, sw, sh}
		end
		render(k.c, rect[1], rect[2], rect[3], rect[4], x, y)
	end
end

function render(o, x, y, w, h, px, py)
	local styles = {string.format("position:absolute;left:%.2fpx;top:%.2fpx;width:%.2fpx;height:%.2fpx;box-sizing:border-box",
		x - px, y - py, w, h)}
	local transforms = {}
	if (o.Rotation or 0) ~= 0 then table.insert(transforms, string.format("rotate(%.2fdeg)", o.Rotation)) end
	local uiScale = child(o, "UIScale")
	if uiScale and (uiScale.Scale or 1) ~= 1 then table.insert(transforms, string.format("scale(%.3f)", uiScale.Scale)) end
	if #transforms > 0 then table.insert(styles, "transform:" .. table.concat(transforms, " ")) end
	table.insert(styles, "z-index:" .. tostring(o.ZIndex or 1))

	local isText = o.ClassName == "TextLabel" or o.ClassName == "TextButton"
	local corner = child(o, "UICorner")
	local radiusCss = nil
	if corner then
		local r = corner.CornerRadius or rb.UDim.new(0, 8)
		-- Roblox: scale is relative to the shorter side and caps at a full pill.
		local px = math.min(r.Scale * math.min(w, h) + r.Offset, math.min(w, h) / 2)
		radiusCss = string.format("%.2fpx", px)
		table.insert(styles, "border-radius:" .. radiusCss)
	end
	local bgT = o.BackgroundTransparency or 0
	local gradient = child(o, "UIGradient")
	if bgT < 1 then
		local color = o.BackgroundColor3 or rb.Color3.new(1, 1, 1)
		if gradient and not isText then
			table.insert(styles, "background:" .. gradientCss(gradient, color, 1 - bgT))
		else
			table.insert(styles, "background:" .. css(color, 1 - bgT))
		end
	end
	if gradient and isText then
		local stops = {}
		for _, kp in ipairs(gradient.Transparency.Keypoints) do
			table.insert(stops, string.format("rgba(0,0,0,%.3f) %.1f%%", 1 - kp.Value, kp.Time * 100))
		end
		table.insert(styles, string.format("-webkit-mask-image:linear-gradient(%.1fdeg, %s)", (gradient.Rotation or 0) + 90, table.concat(stops, ", ")))
	end
	if o.ClassName == "ScrollingFrame" or o.ClipsDescendants or o.ClassName == "CanvasGroup" then table.insert(styles, "overflow:hidden") end
	if o.ClassName == "CanvasGroup" and (o.GroupTransparency or 0) > 0 then
		table.insert(styles, string.format("opacity:%.3f", 1 - o.GroupTransparency))
	end
	emit(string.format('<div data-name="%s" style="%s">', esc(o.Name), table.concat(styles, ";")))

	-- UIStroke (outer border), with optional gradient
	for _, c in ipairs(o:GetChildren()) do
		if c.ClassName == "UIStroke" and not (isText and enumName(c.ApplyStrokeMode, "Contextual") == "Contextual") then
			local t = c.Thickness or 1
			local alpha = 1 - (c.Transparency or 0)
			local color = c.Color or rb.Color3.new(0, 0, 0)
			local g = child(c, "UIGradient")
			local rad = radiusCss and string.format("%.2fpx", tonumber(string.match(radiusCss, "[%d%.]+")) + t) or "0"
			local s = string.format("position:absolute;left:%.2fpx;top:%.2fpx;right:%.2fpx;bottom:%.2fpx;border-radius:%s;padding:%.2fpx;box-sizing:border-box;pointer-events:none", -t, -t, -t, -t, rad, t)
			if g then
				s ..= ";background:" .. gradientCss(g, color, alpha)
			else
				s ..= ";background:" .. css(color, alpha)
			end
			s ..= ";-webkit-mask:linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0);-webkit-mask-composite:xor;mask-composite:exclude"
			emit(string.format('<div style="%s"></div>', s))
		end
	end

	if isText and o.Text and o.Text ~= "" then
		local pl, pt, pr, pb = paddingOf(o, w, h)
		local tw, th = w - pl - pr, h - pt - pb
		local family, weight = fontStack(o.Font)
		local lineHeight = (o.LineHeight or 1) * 1.2
		local size = o.TextSize or 14
		local plain = string.gsub(o.Text, "<[^>]+>", "")
		if o.TextScaled then
			local lines, widest = 0, 0
			for line in string.gmatch(plain .. "\n", "(.-)\n") do
				lines += 1
				widest = math.max(widest, glyphCount(line))
			end
			size = math.min(th / (lines * lineHeight), tw / math.max(widest, 0.5), 100)
			local limit = child(o, "UITextSizeConstraint")
			if limit and limit.MaxTextSize then size = math.min(size, limit.MaxTextSize) end
			size = math.floor(size)
		end
		local xa = enumName(o.TextXAlignment, "Center")
		local ya = enumName(o.TextYAlignment, "Center")
		local justify = xa == "Left" and "flex-start" or xa == "Right" and "flex-end" or "center"
		local align = ya == "Top" and "flex-start" or ya == "Bottom" and "flex-end" or "center"
		local alpha = 1 - (o.TextTransparency or 0)
		local color = o.TextColor3 or rb.Color3.new(0, 0, 0)
		local body = o.RichText and richToHtml(o.Text, color, alpha) or esc(o.Text)
		emit(string.format('<div style="position:absolute;left:%.2fpx;top:%.2fpx;width:%.2fpx;height:%.2fpx;display:flex;justify-content:%s;align-items:%s;text-align:%s;font-family:%s;font-weight:%d;font-size:%dpx;line-height:%.2f;color:%s;white-space:%s;overflow:visible">%s</div>',
			pl, pt, tw, th, justify, align, string.lower(xa), family, weight, size, lineHeight, css(color, alpha),
			(o.TextWrapped and not o.TextScaled) and "pre-wrap" or "pre", body))
	end

	renderChildren(o, x, y, w, h)
	emit("</div>")
end

emit(string.format('<div class="stage" style="position:relative;width:%dpx;height:%dpx;overflow:hidden;background:#5b6470">', W, H))
renderChildren(gui, 0, 0, W, H)
emit("</div>")

local page = string.format([[<!doctype html><html><head><meta charset="utf-8"><title>%s</title>
<style>html,body{margin:0;padding:0;background:#222}</style></head><body>%s</body></html>]], scenario, table.concat(html, "\n"))
fs.writeFile(outPath, page)
print("wrote " .. outPath)
