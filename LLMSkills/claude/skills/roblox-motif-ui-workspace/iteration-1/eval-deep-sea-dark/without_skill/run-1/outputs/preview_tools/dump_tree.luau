--!nocheck
-- Preview helper (not part of the game). Run from the obby-rush folder:
--   lune run ../preview_tools/dump_tree.luau <scenario> <width> <height> <seconds> <out.json>
-- Mounts src/ exactly like tests/test_main_menu.luau does (same mock), builds the real MainMenu,
-- plays a scenario (home / shop / settings / inventory / quests), advances the RenderStepped
-- animation driver by <seconds>, then serialises the instance tree for render_preview.py.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local rb = require("@lune/roblox")
local serde = require("@lune/serde")

local scenario = process.args[1] or "home"
local width = tonumber(process.args[2]) or 1280
local height = tonumber(process.args[3]) or 720
local seconds = tonumber(process.args[4]) or 2.4
local outPath = process.args[5] or ("../preview_tools/tree_" .. scenario .. ".json")

local Mock = luau.load(fs.readFile("tests/mock.luau"), {debugName = "mock"})()
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
	env.workspace = {CurrentCamera = {ViewportSize = rb.Vector2.new(width, height)}}
	return env
end
function requireModule(target)
	if cache[target] ~= nil then return cache[target] end
	local path = sources[target]
	assert(path, "require of a module that is not mounted from src/: " .. tostring(target))
	local result = luau.load(fs.readFile(path), {debugName = path, environment = envFor(target)})()
	cache[target] = result
	return result
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
mount("src/shared", node("Folder", {Name = "Shared", Parent = replicated}))
mount("src/client", node("Folder", {Name = "Client", Parent = starterScripts}))

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

local function click(name)
	local button = gui:FindFirstChild(name, true)
	assert(button, "missing " .. name)
	button.Activated:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1}, 1)
end
if scenario == "shop" then click("Nav_Shop") end
if scenario == "settings" then click("Nav_Settings"); click("Toggle_Music") end
if scenario == "inventory" then click("Nav_Inventory") end
if scenario == "quests" then click("Nav_Quests") end
if scenario == "hover" then
	gui:FindFirstChild("Nav_Quests", true).MouseEnter:Fire()
end

local dt = 1 / 30
for _ = 1, math.floor(seconds / dt + 0.5) do
	runService.RenderStepped:Fire(dt)
end

local PROPS = {"Size", "Position", "AnchorPoint", "Rotation", "Visible", "BackgroundColor3", "BackgroundTransparency",
	"Text", "TextSize", "TextColor3", "TextTransparency", "TextStrokeColor3", "TextStrokeTransparency", "TextXAlignment",
	"TextYAlignment", "TextWrapped", "FontFace", "ZIndex", "ClipsDescendants", "CornerRadius", "Color", "Thickness",
	"Transparency", "ApplyStrokeMode", "Scale", "Padding", "FillDirection", "HorizontalAlignment", "VerticalAlignment",
	"SortOrder", "LayoutOrder", "Enabled", "ScrollBarThickness", "ScrollBarImageColor3"}

local function ser(value)
	local kind = typeof(value)
	if kind == "UDim2" then return {t = "UDim2", xs = value.X.Scale, xo = value.X.Offset, ys = value.Y.Scale, yo = value.Y.Offset}
	elseif kind == "UDim" then return {t = "UDim", s = value.Scale, o = value.Offset}
	elseif kind == "Vector2" then return {t = "Vector2", x = value.X, y = value.Y}
	elseif kind == "Color3" then return {t = "Color3", r = value.R, g = value.G, b = value.B}
	elseif kind == "ColorSequence" or kind == "NumberSequence" then
		local points = {}
		for _, k in ipairs(value.Keypoints) do table.insert(points, {k.Time, ser(k.Value)}) end
		return {t = kind, points = points}
	elseif kind == "EnumItem" then return tostring(value)
	elseif type(value) == "table" and value.Family then
		return {t = "Font", family = value.Family, weight = value.Weight and tostring(value.Weight) or nil}
	elseif type(value) == "number" or type(value) == "string" or type(value) == "boolean" then return value
	end
	return nil
end

local function dump(object)
	local out = {ClassName = object.ClassName, Name = object.Name, props = {}, attributes = {}, children = {}}
	for _, key in ipairs(PROPS) do
		local value = object[key]
		if value ~= nil and not (type(value) == "table" and value.ClassName) then
			out.props[key] = ser(value)
		end
	end
	for key, value in pairs(object:GetAttributes()) do out.attributes[key] = ser(value) end
	for _, child in ipairs(object:GetChildren()) do table.insert(out.children, dump(child)) end
	return out
end

fs.writeFile(outPath, serde.encode("json", {scenario = scenario, width = width, height = height, seconds = seconds, root = dump(gui)}))
print("wrote " .. outPath)
