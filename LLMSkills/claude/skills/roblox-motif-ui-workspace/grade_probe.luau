--!nocheck
-- Runtime probe for grading: mounts an obby-rush project (like tests/test_main_menu.luau), builds the
-- menu, opens each page and dumps every visible GUI object with its look to JSON.
--   lune run grade_probe.luau <projectDir> <out.json>
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")
local rb = require("@lune/roblox")

local projectDir, outPath = process.args[1], process.args[2]
local Mock = luau.load(fs.readFile(projectDir .. "/tests/mock.luau"), {debugName = "mock"})()
local node = Mock.node

local function makeWorld(reduced)
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
	local tweenService = Mock.tweenService()
	local services = {
		ReplicatedStorage = replicated, StarterPlayer = starterPlayer, Players = {LocalPlayer = localPlayer},
		RunService = runService, TweenService = tweenService,
		GuiService = {ReducedMotionEnabled = reduced, TopbarInset = {Min = rb.Vector2.new(200, 0), Max = rb.Vector2.new(1080, 58)},
			GetPropertyChangedSignal = function() return Mock.signal() end},
		UserInputService = {TouchEnabled = false, GetLastInputType = function() return rb.Enum.UserInputType.MouseMovement end,
			InputBegan = Mock.signal(), InputEnded = Mock.signal()},
		SoundService = node("Folder", {Name = "SoundService"}), TextService = {}, ContentProvider = {PreloadAsync = function() end},
	}
	function game:GetService(name) return services[name] end
	local sources, cache = {}, {}
	local requireModule
	local function envFor(script)
		local env = Mock.environment({services = services, reducedMotion = reduced, require = function(t) return requireModule(t) end})
		env.game, env.script = game, script
		env.workspace = {CurrentCamera = {ViewportSize = rb.Vector2.new(1280, 720)}}
		env.TweenInfo = {new = function(...) return {args = table.pack(...)} end}
		return env
	end
	function requireModule(target)
		if cache[target] ~= nil then return cache[target] end
		local path = assert(sources[target], "unmounted module")
		local result = luau.load(fs.readFile(path), {debugName = path, environment = envFor(target)})()
		cache[target] = result
		return result
	end
	local function mount(dir, parent)
		for _, entry in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. entry
			if fs.isDir(path) then
				local init = nil
				for _, name in ipairs({"init.luau", "init.lua"}) do if fs.isFile(path .. "/" .. name) then init = path .. "/" .. name end end
				local folder = node(init and "ModuleScript" or "Folder", {Name = entry, Parent = parent})
				if init then sources[folder] = init end
				mount(path, folder)
			elseif not string.match(entry, "^init%.luau?$") then
				local name, kind = string.match(entry, "^(.-)%.(%a+)%.luau?$")
				if not name then name = string.match(entry, "^(.-)%.luau?$") end
				if name then
					local script = node(kind == "client" and "LocalScript" or kind == "server" and "Script" or "ModuleScript", {Name = name, Parent = parent})
					sources[script] = path
				end
			end
		end
	end
	mount(projectDir .. "/src/shared", node("Folder", {Name = "Shared", Parent = replicated}))
	mount(projectDir .. "/src/client", node("Folder", {Name = "Client", Parent = starterScripts}))
	local MainMenu = requireModule(starterScripts.Client:FindFirstChild("MainMenu"))
	local gui = MainMenu.build(playerGui, {play = function() end, buy = function() end, toggle = function() end, navigate = function() end}, {
		coins = 1250,
		products = {{id = "speed_coil", name = "スピードコイル", price = 300}, {id = "rainbow_trail", name = "虹のトレイル", price = 450},
			{id = "double_jump", name = "ダブルジャンプ", price = 800}},
		settings = {music = true, sfx = true},
	})
	return MainMenu, gui, tweenService
end

local function rgb(c) return c and {math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)} or nil end
local function udim2(u) return u and {u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset} or nil end
local function fontInfo(object)
	local face = object.FontFace
	if type(face) == "table" and face.Family then
		local weight = face.Weight
		return {family = tostring(face.Family), weight = weight and (tostring(weight):match("[^.]+$")) or nil}
	end
	if object.Font ~= nil then return {enum = tostring(object.Font):match("[^.]+$")} end
	return nil
end

local function visible(object, gui)
	local n = object
	while n and n ~= gui.Parent do
		if n.Visible == false then return false end
		if n.ClassName == "ScreenGui" and n.Enabled == false then return false end
		n = n.Parent
	end
	return true
end

local function absSize(object, gui)
	if object == gui or object.ClassName == "ScreenGui" then return 1280, 720 end
	local pw, ph = 1280, 720
	if object.Parent then pw, ph = absSize(object.Parent, gui) end
	local s = object.Size
	if not s then return pw, ph end
	return pw * s.X.Scale + s.X.Offset, ph * s.Y.Scale + s.Y.Offset
end

local function layoutParent(object)
	local parent = object.Parent
	return parent ~= nil and (parent:FindFirstChildWhichIsA("UIGridStyleLayout") ~= nil or parent.ClassName == "ScrollingFrame")
end

-- Absolute rect without a layout engine; `laidOut` marks rects under a UIListLayout/UIGridLayout
-- or a ScrollingFrame, whose real positions the mock cannot know.
local function rectOf(object, gui)
	if object == gui or object.ClassName == "ScreenGui" or not object.Parent then return 0, 0, 1280, 720, false end
	local px, py, pw, ph, laid = rectOf(object.Parent, gui)
	local size, pos, anchor = object.Size, object.Position, object.AnchorPoint
	if not size then return px, py, pw, ph, laid end
	local w, h = pw * size.X.Scale + size.X.Offset, ph * size.Y.Scale + size.Y.Offset
	local x, y = px, py
	if pos then x, y = px + pw * pos.X.Scale + pos.X.Offset, py + ph * pos.Y.Scale + pos.Y.Offset end
	if anchor then x, y = x - anchor.X * w, y - anchor.Y * h end
	return x, y, w, h, laid or layoutParent(object)
end

local function gradientTint(object)
	for _, child in ipairs(object:GetChildren()) do
		if child.ClassName == "UIGradient" and child.Enabled ~= false and child.Color and child.Color.Keypoints then
			-- Time-weighted mean of the piecewise-linear sequence (a lip's thin dark band barely counts).
			local kps = child.Color.Keypoints
			local r, g, b = 0, 0, 0
			for i = 1, #kps - 1 do
				local a0, a1 = kps[i], kps[i + 1]
				local span = a1.Time - a0.Time
				r += span * (a0.Value.R + a1.Value.R) / 2
				g += span * (a0.Value.G + a1.Value.G) / 2
				b += span * (a0.Value.B + a1.Value.B) / 2
			end
			if #kps >= 2 then return {r, g, b} end
		end
	end
	return nil
end

local function gradientAlpha(object)
	for _, child in ipairs(object:GetChildren()) do
		if child.ClassName == "UIGradient" and child.Enabled ~= false and child.Transparency and child.Transparency.Keypoints then
			local kps, t = child.Transparency.Keypoints, 0
			for i = 1, #kps - 1 do t += (kps[i + 1].Time - kps[i].Time) * (kps[i].Value + kps[i + 1].Value) / 2 end
			if #kps >= 2 then return t end
		end
	end
	return 0
end

local function snapshot(gui)
	local out = {}
	for order, object in ipairs(gui:GetDescendants()) do
		if object:IsA("GuiObject") and visible(object, gui) then
			local w, h = absSize(object, gui)
			local strokes, gradient, corner, gradNames = {}, false, nil, {}
			for _, child in ipairs(object:GetChildren()) do
				if child.ClassName == "UICorner" and child.CornerRadius then
					corner = {child.CornerRadius.Scale, child.CornerRadius.Offset}
				end
				if child.ClassName == "UIGradient" then table.insert(gradNames, child.Name) end
				if child.ClassName == "UIStroke" and child.Enabled ~= false then
					table.insert(strokes, {color = rgb(child.Color), thickness = child.Thickness, transparency = child.Transparency or 0,
						mode = child.ApplyStrokeMode and tostring(child.ApplyStrokeMode):match("[^.]+$") or "default"})
				elseif child.ClassName == "UIGradient" then
					gradient = true
				end
			end
			local ancestry, n = {}, object
			while n and n ~= gui do table.insert(ancestry, 1, n.Name); n = n.Parent end
			local isText = object.ClassName == "TextLabel" or object.ClassName == "TextButton" or object.ClassName == "TextBox"
			local rx, ry, rw, rh, laid = rectOf(object, gui)
			table.insert(out, {
				order = order, rect = {rx, ry, rw, rh}, laidOut = laid, tint = gradientTint(object), z = object.ZIndex,
				class = object.ClassName, name = object.Name, path = table.concat(ancestry, "."),
				bg = rgb(object.BackgroundColor3), bgT = 1 - (1 - (object.BackgroundTransparency or 0)) * (1 - gradientAlpha(object)), size = udim2(object.Size), abs = {w, h},
				text = isText and object.Text or nil, textSize = isText and object.TextSize or nil, textColor = isText and rgb(object.TextColor3) or nil,
				textScaled = isText and object.TextScaled or nil, textT = isText and (object.TextTransparency or 0) or nil,
				font = isText and fontInfo(object) or nil, strokes = strokes, gradient = gradient,
				corner = corner, gradNames = gradNames, rotation = object.Rotation or 0,
			})
		end
	end
	return out
end

local function loops(tweenService)
	local infinite = 0
	for _, tween in ipairs(tweenService.created) do
		local info = tween.info
		local args = type(info) == "table" and (info.args or info) or {}
		if type(args[4]) == "number" and args[4] < 0 then infinite += 1 end
	end
	return infinite, #tweenService.created
end

local result = {ok = true, pages = {}}
local ok, err = pcall(function()
	local MainMenu, gui, tweens = makeWorld(false)
	result.ignoreInset = gui.IgnoreGuiInset == true
	result.pages.home = snapshot(gui)
	for _, page in ipairs({"Shop", "Settings", "Inventory", "Quests"}) do
		MainMenu.open(gui, page)
		result.pages[page] = snapshot(gui)
	end
	result.loops, result.tweens = loops(tweens)
	local _, _, calmTweens = makeWorld(true)
	result.reducedLoops, result.reducedTweens = loops(calmTweens)
end)
if not ok then result.ok, result.error = false, tostring(err) end
fs.writeFile(outPath, serde.encode("json", result, true))
print(ok and "probe ok" or ("probe failed: " .. tostring(err)))
