--!nocheck
-- Preview helper (not shipped; lives outside src/). Builds the real MainMenu with the same mock
-- DataModel the contract test uses, drives it into a few states, and writes the resulting GUI
-- instance trees as JSON for tools/preview/render.py to lay out and screenshot.
--   lune run tools/preview/dump_tree.luau <projectDir> <out.json> [width height] [motion]
-- By default Reduced Motion is on so ambient loops stay at their rest pose, and the viewport is 1280x720.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local rb = require("@lune/roblox")
local serde = require("@lune/serde")

local projectDir = process.args[1] or "."
local outPath = process.args[2] or "preview_tree.json"
local viewport = rb.Vector2.new(tonumber(process.args[3]) or 1280, tonumber(process.args[4]) or 720)
local motion = process.args[5] == "motion"

local Mock = luau.load(fs.readFile(projectDir .. "/tests/mock.luau"), {debugName = "mock"})()
local node = Mock.node

local game = node("DataModel", {Name = "Game"})
local replicated = node("Folder", {Name = "ReplicatedStorage", Parent = game})
local starterPlayer = node("Folder", {Name = "StarterPlayer", Parent = game})
local starterScripts = node("Folder", {Name = "StarterPlayerScripts", Parent = starterPlayer})
local services = {
	ReplicatedStorage = replicated,
	StarterPlayer = starterPlayer,
	Players = {LocalPlayer = {Name = "Preview", UserId = 1}},
	RunService = {Heartbeat = Mock.signal(), RenderStepped = Mock.signal(), IsClient = function() return true end,
		IsStudio = function() return false end},
	TweenService = Mock.tweenService(),
	GuiService = {ReducedMotionEnabled = not motion},
	UserInputService = {TouchEnabled = false, GetLastInputType = function() return rb.Enum.UserInputType.MouseMovement end,
		InputBegan = Mock.signal(), InputEnded = Mock.signal()},
	SoundService = node("Folder", {Name = "SoundService"}),
	TextService = {},
	ContentProvider = {PreloadAsync = function() end},
}
function game:GetService(name) return services[name] end

local sources, cache = {}, {}
local requireModule
function requireModule(target)
	if cache[target] ~= nil then return cache[target] end
	local env = Mock.environment({services = services, require = function(t) return requireModule(t) end})
	env.game, env.script = game, target
	env.workspace = {CurrentCamera = {ViewportSize = viewport}}
	local chunk = luau.load(fs.readFile(sources[target]), {debugName = sources[target], environment = env})
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
mount(projectDir .. "/src/shared", node("Folder", {Name = "Shared", Parent = replicated}))
mount(projectDir .. "/src/client", node("Folder", {Name = "Client", Parent = starterScripts}))
local MainMenu = requireModule(starterScripts.Client:FindFirstChild("MainMenu"))

local PROPS = {"Size", "Position", "AnchorPoint", "BackgroundColor3", "BackgroundTransparency", "BorderSizePixel", "Visible", "Rotation",
	"ZIndex", "LayoutOrder", "ClipsDescendants", "Text", "TextSize", "TextColor3", "TextTransparency", "TextXAlignment",
	"TextYAlignment", "TextWrapped", "TextScaled", "Font", "FontFace", "CornerRadius", "Color", "Thickness", "Transparency",
	"ApplyStrokeMode", "FillDirection", "Padding", "HorizontalAlignment", "VerticalAlignment", "SortOrder", "PaddingLeft",
	"PaddingRight", "PaddingTop", "PaddingBottom", "Scale", "Enabled", "ScrollBarThickness", "IgnoreGuiInset", "ZIndexBehavior"}

local function isInstance(value)
	return type(value) == "table" and getmetatable(value) ~= nil and value.GetChildren ~= nil
end

local function encode(value)
	local kind = typeof(value)
	if kind == "UDim2" then return {t = "UDim2", xs = value.X.Scale, xo = value.X.Offset, ys = value.Y.Scale, yo = value.Y.Offset}
	elseif kind == "UDim" then return {t = "UDim", s = value.Scale, o = value.Offset}
	elseif kind == "Vector2" then return {t = "Vector2", x = value.X, y = value.Y}
	elseif kind == "Color3" then return {t = "Color3", r = value.R, g = value.G, b = value.B}
	elseif kind == "ColorSequence" then
		local keys = {}
		for _, k in ipairs(value.Keypoints) do table.insert(keys, {k.Time, k.Value.R, k.Value.G, k.Value.B}) end
		return {t = "ColorSequence", keys = keys}
	elseif kind == "NumberSequence" then
		local keys = {}
		for _, k in ipairs(value.Keypoints) do table.insert(keys, {k.Time, k.Value}) end
		return {t = "NumberSequence", keys = keys}
	elseif kind == "EnumItem" then return {t = "Enum", name = value.Name}
	elseif kind == "number" or kind == "string" or kind == "boolean" then return value
	elseif kind == "table" and not isInstance(value) and value.Family then
		return {t = "Font", family = value.Family, weight = value.Weight and value.Weight.Name or "Regular"}
	end
	return nil
end

local function serialize(instance)
	local out = {ClassName = instance.ClassName, Name = instance.Name, children = {}}
	for _, key in ipairs(PROPS) do
		local ok, value = pcall(function() return instance[key] end)
		if ok and value ~= nil and not isInstance(value) then out[key] = encode(value) end
	end
	for _, child in ipairs(instance:GetChildren()) do table.insert(out.children, serialize(child)) end
	return out
end

local function freshMenu()
	local playerGui = node("Folder", {Name = "PlayerGui"})
	local state = {
		coins = 1250,
		products = {
			{id = "speed_coil", name = "スピードコイル", price = 300},
			{id = "rainbow_trail", name = "虹のトレイル", price = 450},
			{id = "double_jump", name = "ダブルジャンプ", price = 800},
		},
		settings = {music = true, sfx = true},
	}
	local handlers = {play = function() end, buy = function() end, toggle = function() end, navigate = function() end}
	return MainMenu.build(playerGui, handlers, state)
end
local function press(gui, name)
	local button = gui:FindFirstChild(name, true)
	if button then button.Activated:Fire() end
end

local scenes = {}
local home = freshMenu()
scenes.home = serialize(home)
for _, id in ipairs({"Shop", "Inventory", "Quests"}) do
	local gui = freshMenu()
	press(gui, "Nav_" .. id)
	scenes[string.lower(id)] = serialize(gui)
end
local settingsGui = freshMenu()
press(settingsGui, "Nav_Settings")
press(settingsGui, "Toggle_Music") -- show one toggle ON (flag C) and one OFF (flag N)
scenes.settings = serialize(settingsGui)
local settingsOn = freshMenu()
press(settingsOn, "Nav_Settings")
scenes.settings_on = serialize(settingsOn)

local count = 0
for _ in ipairs(home:GetDescendants()) do count += 1 end
fs.writeFile(outPath, serde.encode("json", {instanceCount = count, scenes = scenes}, false))
print(string.format("wrote %s (%d instances in the home menu)", outPath, count))
