--!nocheck
-- Build the obby-rush MainMenu in Lune (same mount + mock as tests/test_main_menu.luau) and dump
-- the resulting GUI tree as JSON for render_preview.py. Nothing in the project is written.
--   lune run dump_menu.luau <projectDir> <width> <height> <page|-> <reduced 0|1> <out.json>
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local rb = require("@lune/roblox")
local serde = require("@lune/serde")

local root, width, height, pageId, reduced, outPath = table.unpack(process.args)
width, height = tonumber(width) or 1280, tonumber(height) or 720

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
local tweenService = Mock.tweenService()
local services = {
	ReplicatedStorage = replicated, StarterPlayer = starterPlayer, Players = {LocalPlayer = localPlayer},
	RunService = runService, TweenService = tweenService, GuiService = {ReducedMotionEnabled = reduced == "1"},
	UserInputService = {TouchEnabled = false, GetLastInputType = function() return rb.Enum.UserInputType.MouseMovement end,
		InputBegan = Mock.signal(), InputEnded = Mock.signal()},
	SoundService = node("Folder", {Name = "SoundService"}), TextService = {}, ContentProvider = {PreloadAsync = function() end},
}
function game:GetService(name) return services[name] end

local warnings = {}
local sources, cache = {}, {}
local requireModule
local function envFor(script)
	local env = Mock.environment({services = services, require = function(target) return requireModule(target) end})
	env.game, env.script = game, script
	env.workspace = {CurrentCamera = {ViewportSize = rb.Vector2.new(width, height)}}
	env.warn = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
		table.insert(warnings, table.concat(parts, " "))
	end
	return env
end
function requireModule(target)
	if cache[target] ~= nil then return cache[target] end
	local path = sources[target]
	assert(path, "require of an unmounted module: " .. tostring(target))
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
local gui = MainMenu.build(playerGui, {play = function() end, buy = function() end, toggle = function() end}, {
	coins = 1250,
	products = {
		{id = "speed_coil", name = "スピードコイル", price = 300},
		{id = "rainbow_trail", name = "虹のトレイル", price = 450},
		{id = "double_jump", name = "ダブルジャンプ", price = 800},
	},
	settings = {music = true, sfx = false},
})
if pageId and pageId ~= "-" then MainMenu.open(gui, pageId) end

local PROPS = {"Size", "Position", "AnchorPoint", "Rotation", "Visible", "ZIndex", "BackgroundColor3", "BackgroundTransparency",
	"Text", "TextSize", "TextColor3", "TextTransparency", "TextXAlignment", "TextYAlignment", "TextWrapped", "TextScaled",
	"FontFace", "Font", "ClipsDescendants", "LayoutOrder", "LineHeight", "CornerRadius", "Color", "Thickness", "Transparency",
	"ApplyStrokeMode", "Enabled", "Offset", "FillDirection", "Padding", "HorizontalAlignment", "VerticalAlignment", "SortOrder",
	"PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom", "MinSize", "MaxSize", "AspectRatio", "AspectType",
	"DominantAxis", "MaxTextSize", "MinTextSize", "Scale", "ScrollBarThickness", "IgnoreGuiInset", "ZIndexBehavior", "Active"}

local function value(v)
	local kind = typeof(v)
	if kind == "UDim2" then return {t = "UDim2", xs = v.X.Scale, xo = v.X.Offset, ys = v.Y.Scale, yo = v.Y.Offset} end
	if kind == "UDim" then return {t = "UDim", s = v.Scale, o = v.Offset} end
	if kind == "Vector2" then return {t = "Vector2", x = v.X, y = v.Y} end
	if kind == "Color3" then return {t = "Color3", r = v.R, g = v.G, b = v.B} end
	if kind == "EnumItem" then return v.Name end
	if kind == "NumberSequence" then
		local list = {}
		for _, k in ipairs(v.Keypoints) do table.insert(list, {k.Time, k.Value}) end
		return {t = "NumberSequence", k = list}
	end
	if kind == "ColorSequence" then
		local list = {}
		for _, k in ipairs(v.Keypoints) do table.insert(list, {k.Time, k.Value.R, k.Value.G, k.Value.B}) end
		return {t = "ColorSequence", k = list}
	end
	if kind == "number" or kind == "boolean" or kind == "string" then return v end
	if type(v) == "table" then
		local ok, class = pcall(function() return rawget(v, "ClassName") or v.ClassName end)
		if ok and class then return nil end
		if v.Family then return {t = "Font", family = v.Family, weight = v.Weight and v.Weight.Name or "Regular"} end
	end
	return nil
end

local function dump(object)
	local out = {class = object.ClassName, name = object.Name, props = {}, children = {}}
	for _, key in ipairs(PROPS) do
		local ok, v = pcall(function() return object[key] end)
		if ok and v ~= nil then out.props[key] = value(v) end
	end
	for _, child in ipairs(object:GetChildren()) do table.insert(out.children, dump(child)) end
	return out
end

local result = {viewport = {width, height}, page = pageId, reduced = reduced == "1", warnings = warnings,
	tweens = #tweenService.created, tree = dump(gui)}
fs.writeFile(outPath, serde.encode("json", result, false))
print(string.format("dumped %dx%d page=%s warnings=%d tweens=%d -> %s", width, height, tostring(pageId), #warnings,
	#tweenService.created, outPath))
for _, w in ipairs(warnings) do print("WARN " .. w) end
