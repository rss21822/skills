--!nocheck
-- Builds the real MainMenu (src/ mounted exactly like tests/test_main_menu.luau does, on the project's own
-- tests/mock.luau) and dumps the resulting instance tree as JSON for render.html.
-- Usage: lune run dump_menu.luau <projectRoot> <out.js> <width> <height> <topInset> <page|none> <time> [actions]
--   actions: comma list of toggleMusic, toggleSfx, hoverPlay, pressPlay, hoverNavQuests
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local rb = require("@lune/roblox")
local serde = require("@lune/serde")

local args = process.args
local root, outFile = args[1], args[2]
local width, height, inset = tonumber(args[3]), tonumber(args[4]), tonumber(args[5])
local openPage, time, actions = args[6] or "none", tonumber(args[7]) or 0, args[8] or ""

local Mock = luau.load(fs.readFile(root .. "/tests/mock.luau"), {debugName = "mock"})()
local node = Mock.node

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
local guiService = {ReducedMotionEnabled = false}
function guiService:GetGuiInset() return rb.Vector2.new(0, inset), rb.Vector2.new(0, 0) end
local services = {
	ReplicatedStorage = replicated, StarterPlayer = starterPlayer, Players = {LocalPlayer = localPlayer},
	RunService = runService, TweenService = Mock.tweenService(), GuiService = guiService,
	UserInputService = {TouchEnabled = false, GetLastInputType = function() return rb.Enum.UserInputType.MouseMovement end,
		InputBegan = Mock.signal(), InputEnded = Mock.signal()},
	SoundService = node("Folder", {Name = "SoundService"}), TextService = {}, ContentProvider = {PreloadAsync = function() end},
}
function game:GetService(name) return services[name] end

local now = 0
local sources, cache = {}, {}
local requireModule
local function envFor(script)
	local env = Mock.environment({services = services, now = function() return now end,
		require = function(target) return requireModule(target) end})
	env.game, env.script = game, script
	env.workspace = {CurrentCamera = {ViewportSize = rb.Vector2.new(width, height)}}
	return env
end
function requireModule(target)
	if cache[target] ~= nil then return cache[target] end
	local chunk = luau.load(fs.readFile(sources[target]), {debugName = sources[target], environment = envFor(target)})
	cache[target] = chunk()
	return cache[target]
end
local function mount(dir, parent)
	for _, entry in ipairs(fs.readDir(dir)) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			mount(path, node("Folder", {Name = entry, Parent = parent}))
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
local handlers = {play = function() end, buy = function() end, toggle = function() end, navigate = function() end}
local state = {
	coins = 1250,
	products = {
		{id = "speed_coil", name = "スピードコイル", price = 300},
		{id = "rainbow_trail", name = "虹のトレイル", price = 450},
		{id = "double_jump", name = "ダブルジャンプ", price = 800},
	},
	settings = {music = true, sfx = true},
}
local gui = MainMenu.build(playerGui, handlers, state)

-- Give the tub water a realistic AbsoluteSize (the mock reports 200x50) so fish headings match the render.
local water = gui:FindFirstChild("Water", true)
if water then
	local s = math.clamp(math.min(height / 720, width / 1280), 0.55, 1)
	local used = inset + 6 + 56 + 4 + math.floor(88 * s) + 92
	water.AbsoluteSize = rb.Vector2.new(math.clamp(0.5 * width, 300, 640) - 22, math.clamp(height - used - 8, 104, 250) - 22)
end
if time > 0 then
	now = time
	runService.Heartbeat:Fire(1 / 60)
end

local function click(button)
	button.InputBegan:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
	button.InputEnded:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
	button.Activated:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1}, 1)
end
if openPage ~= "none" then
	local nav = gui:FindFirstChild("Nav_" .. openPage, true)
	if nav then click(nav) else MainMenu.open(gui, openPage) end
end
for action in string.gmatch(actions, "[^,]+") do
	if action == "toggleMusic" then click(gui:FindFirstChild("Toggle_Music", true))
	elseif action == "toggleSfx" then click(gui:FindFirstChild("Toggle_SFX", true))
	elseif action == "hoverPlay" then gui:FindFirstChild("PlayButton", true).MouseEnter:Fire()
	elseif action == "pressPlay" then gui:FindFirstChild("PlayButton", true).InputBegan:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
	elseif action == "hoverNavQuests" then gui:FindFirstChild("Nav_Quests", true).MouseEnter:Fire()
	end
end

-- Serialise --------------------------------------------------------------------------------------------
local KEYS = {"Size", "Position", "AnchorPoint", "Rotation", "Visible", "ZIndex", "BackgroundColor3", "BackgroundTransparency",
	"ClipsDescendants", "LayoutOrder", "SizeConstraint", "Text", "TextSize", "TextColor3", "TextTransparency", "TextScaled",
	"TextWrapped", "TextXAlignment", "TextYAlignment", "FontFace", "Font", "Enabled", "CornerRadius", "Color", "Thickness",
	"Transparency", "ApplyStrokeMode", "FillDirection", "Padding", "HorizontalAlignment", "VerticalAlignment", "SortOrder",
	"Scale", "AspectRatio", "MinSize", "MaxSize", "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight",
	"MaxTextSize", "MinTextSize", "ZIndexBehavior", "IgnoreGuiInset"}

local function isNode(value)
	return type(value) == "table" and rawget(value, "ClassName") == nil and getmetatable(value) ~= nil
		and value.GetChildren ~= nil and value.ClassName ~= nil
end

local function encodeValue(value)
	local kind = typeof(value)
	if kind == "UDim2" then return {t = "UDim2", xs = value.X.Scale, xo = value.X.Offset, ys = value.Y.Scale, yo = value.Y.Offset}
	elseif kind == "UDim" then return {t = "UDim", s = value.Scale, o = value.Offset}
	elseif kind == "Vector2" then return {t = "Vector2", x = value.X, y = value.Y}
	elseif kind == "Color3" then return {t = "Color3", r = value.R, g = value.G, b = value.B}
	elseif kind == "ColorSequence" then
		local keys = {}
		for _, k in ipairs(value.Keypoints) do table.insert(keys, {k.Time, k.Value.R, k.Value.G, k.Value.B}) end
		return {t = "ColorSequence", k = keys}
	elseif kind == "NumberSequence" then
		local keys = {}
		for _, k in ipairs(value.Keypoints) do table.insert(keys, {k.Time, k.Value}) end
		return {t = "NumberSequence", k = keys}
	elseif kind == "EnumItem" then return {t = "Enum", name = value.Name}
	elseif kind == "table" and value.Family then
		return {t = "Font", family = tostring(value.Family), weight = value.Weight and value.Weight.Name or "Regular"}
	elseif kind == "number" or kind == "string" or kind == "boolean" then return value
	end
	return nil
end

local function serialise(object)
	local props = {}
	for _, key in ipairs(KEYS) do
		local ok, value = pcall(function() return object[key] end)
		if ok and value ~= nil and not isNode(value) then props[key] = encodeValue(value) end
	end
	local children = {}
	for _, child in ipairs(object:GetChildren()) do table.insert(children, serialise(child)) end
	return {class = object.ClassName, name = object.Name, props = props, children = children}
end

local payload = {viewport = {x = width, y = height}, inset = inset, tree = serialise(gui)}
fs.writeFile(outFile, "window.MENU = " .. serde.encode("json", payload) .. ";\n")
print("wrote " .. outFile)
