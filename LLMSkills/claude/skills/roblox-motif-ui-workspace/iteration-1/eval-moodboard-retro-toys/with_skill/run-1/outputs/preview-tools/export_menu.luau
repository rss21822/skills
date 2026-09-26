--!nocheck
-- Build the real MainMenu (src/ mounted like default.project.json, tests/mock.luau as the engine) at a
-- given screen size and dump the resulting GUI tree as JSON for render_menu.py. Run from the project:
--   lune run <this file> <out.json> <width> <height> <page: none|Shop|Inventory|Quests|Settings> <skin: 1|0>
-- This previews what the Luau code builds; it is NOT the Roblox renderer (no Studio in this run).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local rb = require("@lune/roblox")
local serde = require("@lune/serde")

local out, width, height, pageId, skinFlag = process.args[1], tonumber(process.args[2]), tonumber(process.args[3]), process.args[4], process.args[5]
local Mock = luau.load(fs.readFile("tests/mock.luau"), {debugName = "mock"})()
local node = Mock.node

local game = node("DataModel", {Name = "Game"})
local replicated = node("Folder", {Name = "ReplicatedStorage", Parent = game})
local starterPlayer = node("Folder", {Name = "StarterPlayer", Parent = game})
local starterScripts = node("Folder", {Name = "StarterPlayerScripts", Parent = starterPlayer})
local services = {
	ReplicatedStorage = replicated, StarterPlayer = starterPlayer, Players = {LocalPlayer = {Name = "Tester", UserId = 1}},
	RunService = {Heartbeat = Mock.signal(), RenderStepped = Mock.signal(), Stepped = Mock.signal()},
	TweenService = Mock.tweenService(), GuiService = {ReducedMotionEnabled = true},
	UserInputService = {TouchEnabled = false}, TextService = {}, ContentProvider = {PreloadAsync = function() end},
}
function game:GetService(name) return services[name] end
local sources, cache = {}, {}
local requireModule
function requireModule(target)
	if cache[target] ~= nil then return cache[target] end
	local env = Mock.environment({services = services, require = function(t) return requireModule(t) end})
	env.game, env.script = game, target
	env.workspace = {CurrentCamera = {ViewportSize = rb.Vector2.new(width, height)}}
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
			local name, kind = string.match(entry, "^(.-)%.(%a+)%.luau?$")
			if not name then name = string.match(entry, "^(.-)%.luau?$") end
			if name then
				sources[node(kind == "client" and "LocalScript" or "ModuleScript", {Name = name, Parent = parent})] = path
			end
		end
	end
end
mount("src/shared", node("Folder", {Name = "Shared", Parent = replicated}))
mount("src/client", node("Folder", {Name = "Client", Parent = starterScripts}))

local MainMenu = requireModule(starterScripts.Client.MainMenu)
MainMenu.useSkin = skinFlag ~= "0"
local playerGui = node("Folder", {Name = "PlayerGui"})
local noop = function() end
local gui = MainMenu.build(playerGui, {play = noop, buy = noop, toggle = noop}, {
	coins = 1250,
	products = {
		{id = "speed_coil", name = "スピードコイル", price = 300},
		{id = "rainbow_trail", name = "虹のトレイル", price = 450},
		{id = "double_jump", name = "ダブルジャンプ", price = 800},
	},
	settings = {music = true, sfx = false},
})
if pageId and pageId ~= "none" then MainMenu.open(gui, pageId) end

local PROPS = {"Size", "Position", "AnchorPoint", "Rotation", "Visible", "ZIndex", "LayoutOrder", "BackgroundColor3",
	"BackgroundTransparency", "Text", "TextSize", "TextColor3", "TextTransparency", "TextXAlignment", "TextYAlignment",
	"TextScaled", "TextWrapped", "FontFace", "Font", "ClipsDescendants", "Enabled", "CornerRadius", "Color", "Thickness",
	"Transparency", "ApplyStrokeMode", "Offset", "FillDirection", "Padding", "HorizontalAlignment", "VerticalAlignment",
	"PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight", "Scale", "MinSize", "MaxSize", "MinTextSize",
	"MaxTextSize", "ScrollBarThickness", "ScrollBarImageColor3", "GroupTransparency"}
local function conv(v)
	local t = typeof(v)
	if t == "Color3" then return {t = "c3", r = v.R, g = v.G, b = v.B} end
	if t == "UDim2" then return {t = "udim2", xs = v.X.Scale, xo = v.X.Offset, ys = v.Y.Scale, yo = v.Y.Offset} end
	if t == "UDim" then return {t = "udim", s = v.Scale, o = v.Offset} end
	if t == "Vector2" then return {t = "v2", x = v.X, y = v.Y} end
	if t == "EnumItem" then return v.Name end
	if t == "ColorSequence" then
		local k = {}
		for _, p in ipairs(v.Keypoints) do table.insert(k, {time = p.Time, r = p.Value.R, g = p.Value.G, b = p.Value.B}) end
		return {t = "cseq", k = k}
	end
	if t == "NumberSequence" then
		local k = {}
		for _, p in ipairs(v.Keypoints) do table.insert(k, {time = p.Time, value = p.Value}) end
		return {t = "nseq", k = k}
	end
	if t == "table" and v.Family then return {t = "font", family = v.Family, weight = v.Weight and v.Weight.Name or "Regular"} end
	if t == "number" or t == "string" or t == "boolean" then return v end
	return nil
end
local function dump(object)
	local entry = {class = object.ClassName, name = object.Name, props = {}, children = {}}
	for _, key in ipairs(PROPS) do
		local ok, value = pcall(function() return object[key] end)
		if ok and value ~= nil and not (type(value) == "table" and value.ClassName) then entry.props[key] = conv(value) end
	end
	for _, child in ipairs(object:GetChildren()) do table.insert(entry.children, dump(child)) end
	return entry
end
fs.writeFile(out, serde.encode("json", {width = width, height = height, page = pageId, skin = skinFlag ~= "0", root = dump(gui)}))
print("wrote " .. out)
