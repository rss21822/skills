--!nocheck
-- Build the real MainMenu (src/, mocked DataModel from tests/mock.luau) and dump the GUI tree as JSON
-- for render_preview.py. Run from the obby-rush folder:
--   lune run ../preview-tools/export_tree.luau <page|none> <width> <height> <out.json> [plain]
-- "plain" mounts src/ without the Harbor skin folder and HarborMenu (the before picture).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")
local rb = require("@lune/roblox")

local pageId, width, height, outPath, mode = process.args[1], tonumber(process.args[2]), tonumber(process.args[3]), process.args[4], process.args[5]
local plain = mode == "plain"
local Mock = luau.load(fs.readFile("tests/mock.luau"), {debugName = "mock"})()
local node = Mock.node

local game = node("DataModel", {Name = "Game"})
local replicated = node("Folder", {Name = "ReplicatedStorage", Parent = game})
local starterPlayer = node("Folder", {Name = "StarterPlayer", Parent = game})
local starterScripts = node("Folder", {Name = "StarterPlayerScripts", Parent = starterPlayer})
local playerGui = node("Folder", {Name = "PlayerGui"})
local localPlayer = {Name = "Tester", UserId = 1, PlayerGui = playerGui}
function localPlayer:WaitForChild(name) return name == "PlayerGui" and playerGui or nil end
local services = {
	ReplicatedStorage = replicated, StarterPlayer = starterPlayer, Players = {LocalPlayer = localPlayer},
	RunService = {Heartbeat = Mock.signal(), RenderStepped = Mock.signal()}, TweenService = Mock.tweenService(),
	-- reduced motion: the picture shows the resting pose (tweens would otherwise jump to their end)
	GuiService = {ReducedMotionEnabled = true},
	UserInputService = {TouchEnabled = false}, TextService = {},
}
function game:GetService(name) return services[name] end
local sources, cache = {}, {}
local requireModule
function requireModule(target)
	if cache[target] ~= nil then return cache[target] end
	local env = Mock.environment({services = services, require = function(t) return requireModule(t) end})
	env.game, env.script = game, target
	env.workspace = {CurrentCamera = {ViewportSize = rb.Vector2.new(width, height)}}
	local result = luau.load(fs.readFile(assert(sources[target], "not mounted: " .. tostring(target))), {debugName = sources[target], environment = env})()
	cache[target] = result
	return result
end
local function mount(dir, parent)
	for _, entry in ipairs(fs.readDir(dir)) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			if not (plain and entry == "Harbor") then mount(path, node("Folder", {Name = entry, Parent = parent})) end
		else
			local name, kind = string.match(entry, "^(.-)%.(%a+)%.luau?$")
			if not name then name = string.match(entry, "^(.-)%.luau?$") end
			if name and not (plain and name == "HarborMenu") then
				sources[node(kind == "client" and "LocalScript" or "ModuleScript", {Name = name, Parent = parent})] = path
			end
		end
	end
end
mount("src/shared", node("Folder", {Name = "Shared", Parent = replicated}))
mount("src/client", node("Folder", {Name = "Client", Parent = starterScripts}))

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
if pageId and pageId ~= "none" then MainMenu.open(gui, pageId) end

local PROPS = {"Name", "ClassName", "Active", "Visible", "Enabled", "Size", "Position", "AnchorPoint", "Rotation", "ZIndex",
	"BackgroundColor3", "BackgroundTransparency", "Text", "TextSize", "TextColor3", "TextTransparency", "TextXAlignment",
	"TextYAlignment", "TextWrapped", "TextScaled", "FontFace", "Font", "ClipsDescendants", "Color", "Thickness",
	"Transparency", "ApplyStrokeMode", "CornerRadius", "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom",
	"FillDirection", "HorizontalAlignment", "VerticalAlignment", "SortOrder", "Padding", "LayoutOrder", "Offset",
	"MaxSize", "MinSize", "MaxTextSize", "MinTextSize", "IgnoreGuiInset", "ScrollBarThickness", "ScrollBarImageColor3"}

local function ser(value)
	local kind = typeof(value)
	if kind == "UDim2" then return {t = "UDim2", v = {value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset}} end
	if kind == "UDim" then return {t = "UDim", v = {value.Scale, value.Offset}} end
	if kind == "Vector2" then return {t = "Vector2", v = {value.X, value.Y}} end
	if kind == "Color3" then return {t = "Color3", v = {value.R, value.G, value.B}} end
	if kind == "ColorSequence" then
		local points = {}
		for _, k in ipairs(value.Keypoints) do table.insert(points, {k.Time, k.Value.R, k.Value.G, k.Value.B}) end
		return {t = "CS", v = points}
	end
	if kind == "NumberSequence" then
		local points = {}
		for _, k in ipairs(value.Keypoints) do table.insert(points, {k.Time, k.Value}) end
		return {t = "NS", v = points}
	end
	if kind == "EnumItem" then return {t = "Enum", v = tostring(value)} end
	if type(value) == "table" then
		if rawget(value, "Family") then return {t = "Font", v = {rawget(value, "Family"), tostring(rawget(value, "Weight"))}} end
		return nil -- a child instance found by name, not a property
	end
	return value
end

local function dump(object)
	local out = {props = {}, children = {}}
	for _, key in ipairs(PROPS) do
		local ok, value = pcall(function() return object[key] end)
		if ok and value ~= nil then out.props[key] = ser(value) end
	end
	out.props.Name, out.props.ClassName = object.Name, object.ClassName
	for _, child in ipairs(object:GetChildren()) do table.insert(out.children, dump(child)) end
	return out
end
fs.writeFile(outPath, serde.encode("json", {width = width, height = height, page = pageId, root = dump(gui)}, false))
print("wrote " .. outPath)
