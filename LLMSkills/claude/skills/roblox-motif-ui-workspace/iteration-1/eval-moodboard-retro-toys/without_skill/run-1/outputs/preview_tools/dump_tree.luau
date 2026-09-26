--!nocheck
-- Preview helper (not part of the game). Run from the obby-rush folder:
--   lune run ../preview_tools/dump_tree.luau <out.json>
-- Mounts src/ exactly like tests/test_main_menu.luau, builds the real MainMenu in the mock DataModel,
-- drives a few UI states through the real code (MainMenu.open, a toggle click) and dumps the
-- instance tree of each state to JSON for render_preview.py.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")
local rb = require("@lune/roblox")

local Mock = luau.load(fs.readFile("tests/mock.luau"), {debugName = "mock"})()
local node = Mock.node

local game = node("DataModel", {Name = "Game"})
local replicated = node("Folder", {Name = "ReplicatedStorage", Parent = game})
local starterPlayer = node("Folder", {Name = "StarterPlayer", Parent = game})
local starterScripts = node("Folder", {Name = "StarterPlayerScripts", Parent = starterPlayer})
local playerGui = node("Folder", {Name = "PlayerGui"})
local localPlayer = {Name = "Tester", UserId = 1, PlayerGui = playerGui}
function localPlayer:WaitForChild(name) return name == "PlayerGui" and playerGui or nil end
-- Reduced motion ON for the dump so idle tweens do not leave decorations at their extreme pose.
local services = {
	ReplicatedStorage = replicated, StarterPlayer = starterPlayer, Players = {LocalPlayer = localPlayer},
	RunService = {Heartbeat = Mock.signal(), RenderStepped = Mock.signal()},
	TweenService = Mock.tweenService(), GuiService = {ReducedMotionEnabled = true},
	UserInputService = {TouchEnabled = false, GetLastInputType = function() return rb.Enum.UserInputType.MouseMovement end},
}
function game:GetService(name) return services[name] end

-- One workspace table shared by every module env so the dump can pick the screen size per build.
local sharedWorkspace = {CurrentCamera = {ViewportSize = rb.Vector2.new(1280, 720)}}
local sources, cache = {}, {}
local requireModule
local function envFor(script)
	local env = Mock.environment({services = services, require = function(target) return requireModule(target) end})
	env.game, env.script = game, script
	env.workspace = sharedWorkspace
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
		if not fs.isDir(path) then
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
local STATE = {
	coins = 1250,
	products = {
		{id = "speed_coil", name = "スピードコイル", price = 300},
		{id = "rainbow_trail", name = "虹のトレイル", price = 450},
		{id = "double_jump", name = "ダブルジャンプ", price = 800},
	},
	settings = {music = true, sfx = true},
}

local PROPS = {"Name", "ClassName", "Size", "Position", "AnchorPoint", "BackgroundColor3", "BackgroundTransparency", "Visible",
	"ZIndex", "Rotation", "ClipsDescendants", "Text", "TextSize", "TextColor3", "TextTransparency", "TextXAlignment",
	"TextYAlignment", "TextScaled", "TextWrapped", "TextTruncate", "AutomaticSize", "FontFace", "LayoutOrder", "CornerRadius",
	"Color", "Thickness", "Transparency", "ApplyStrokeMode", "FillDirection", "Padding", "HorizontalAlignment",
	"VerticalAlignment", "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom", "AspectRatio", "MaxSize", "MinSize",
	"Scale", "ScrollBarThickness", "ScrollBarImageColor3", "ZIndexBehavior", "Active"}

local function convert(value)
	local kind = typeof(value)
	if kind == "UDim2" then return {t = "UDim2", xs = value.X.Scale, xo = value.X.Offset, ys = value.Y.Scale, yo = value.Y.Offset} end
	if kind == "UDim" then return {t = "UDim", s = value.Scale, o = value.Offset} end
	if kind == "Color3" then return {t = "Color3", r = value.R, g = value.G, b = value.B} end
	if kind == "Vector2" then return {t = "Vector2", x = value.X, y = value.Y} end
	if kind == "EnumItem" then return value.Name end
	if kind == "table" then
		if value.Family then return {t = "Font", family = tostring(value.Family), weight = value.Weight and value.Weight.Name or "Regular"} end
		return nil
	end
	if kind == "boolean" or kind == "number" or kind == "string" then return value end
	return nil
end

local function dump(inst)
	local out = {}
	for _, prop in ipairs(PROPS) do
		local raw = rawget(inst, prop) -- always nil (mock keeps data in a closure); use the metatable read
		local ok, value = pcall(function() return inst[prop] end)
		if ok and value ~= nil and not (typeof(value) == "table" and value.ClassName ~= nil) then
			local converted = convert(value)
			if converted ~= nil then out[prop] = converted end
		end
	end
	local attrs = inst:GetAttributes()
	if next(attrs) then out.Attributes = attrs end
	local children = {}
	for _, child in ipairs(inst:GetChildren()) do table.insert(children, dump(child)) end
	out.Children = children
	return out
end

local states = {}
local VIEWPORTS = {{1280, 720}, {844, 390}, {667, 375}, {1920, 1080}}
for _, viewport in ipairs(VIEWPORTS) do
	sharedWorkspace.CurrentCamera.ViewportSize = rb.Vector2.new(viewport[1], viewport[2])
	local playerGui = node("Folder", {Name = "PlayerGui"})
	local gui = MainMenu.build(playerGui, {play = function() end, buy = function() end, toggle = function() end}, STATE)
	local tag = "@" .. viewport[1] .. "x" .. viewport[2]
	local function snap(name) table.insert(states, {name = name .. tag, tree = dump(gui)}) end
	snap("home")
	MainMenu.open(gui, "Shop"); snap("shop")
	MainMenu.open(gui, "Settings")
	local sfx = gui:FindFirstChild("Toggle_SFX", true)
	sfx.Activated:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1}, 1) -- show one switch OFF
	snap("settings")
	MainMenu.open(gui, "Inventory"); snap("inventory")
	MainMenu.open(gui, "Quests"); snap("quests")
	-- Interaction states: hover on a nav tab, PLAY held down.
	if not pcall(MainMenu.open, gui, nil) then -- the pre-reskin menu has no "close all"
		gui:FindFirstChild("QuestsPage").Visible = false
	end
	gui:FindFirstChild("Nav_Quests", true).MouseEnter:Fire()
	gui:FindFirstChild("PlayButton", true).InputBegan:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
	snap("interact")
end

local outPath = process.args[1] or "tree.json"
fs.writeFile(outPath, serde.encode("json", states, false))
print("wrote " .. outPath .. " (" .. #states .. " states)")
