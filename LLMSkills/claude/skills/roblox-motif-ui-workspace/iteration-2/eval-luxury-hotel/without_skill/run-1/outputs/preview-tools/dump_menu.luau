--!nocheck
-- Builds the MainMenu with the project's own test mock (tests/mock.luau) and dumps the resulting
-- GUI tree as JSON so render_preview.py can lay it out in a browser. Read-only on the project.
--
--   lune run dump_menu.luau <projectDir> <outJson> <scenario> [viewportWidth viewportHeight]
--   scenario: lobby | shop | settings | cloakroom | concierge | hover
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")
local rb = require("@lune/roblox")

local projectDir, outPath, scenario = process.args[1], process.args[2], process.args[3] or "lobby"
local viewport = rb.Vector2.new(tonumber(process.args[4]) or 1280, tonumber(process.args[5]) or 720)
assert(projectDir and outPath, "usage: dump_menu.luau <projectDir> <outJson> <scenario>")

local Mock = luau.load(fs.readFile(projectDir .. "/tests/mock.luau"), {debugName = "mock"})()
local node = Mock.node

-- Mock DataModel, mounted exactly like tests/test_main_menu.luau does.
local game = node("DataModel", {Name = "Game"})
local replicated = node("Folder", {Name = "ReplicatedStorage", Parent = game})
local starterPlayer = node("Folder", {Name = "StarterPlayer", Parent = game})
local starterScripts = node("Folder", {Name = "StarterPlayerScripts", Parent = starterPlayer})
local playerGui = node("Folder", {Name = "PlayerGui"})
local localPlayer = {Name = "Preview", UserId = 1, PlayerGui = playerGui}
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
	env.workspace = {CurrentCamera = {ViewportSize = viewport}}
	return env
end
function requireModule(target)
	if cache[target] ~= nil then return cache[target] end
	local path = assert(sources[target], "module not mounted: " .. tostring(target))
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
mount(projectDir .. "/src/shared", node("Folder", {Name = "Shared", Parent = replicated}))
mount(projectDir .. "/src/client", node("Folder", {Name = "Client", Parent = starterScripts}))

local MainMenu = requireModule(starterScripts.Client:FindFirstChild("MainMenu"))
local gui = MainMenu.build(playerGui, {
	play = function() end, buy = function() end, toggle = function() end, navigate = function() end,
}, {
	coins = 1250,
	products = {
		{id = "speed_coil", name = "スピードコイル", price = 300},
		{id = "rainbow_trail", name = "虹のトレイル", price = 450},
		{id = "double_jump", name = "ダブルジャンプ", price = 800},
	},
	settings = {music = true, sfx = true},
})

local function find(name) return gui:FindFirstChild(name, true) end
local function click(name)
	local button = find(name)
	if button then button.Activated:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1}, 1) end
end
if scenario == "shop" then
	click("Nav_Shop")
elseif scenario == "settings" then
	click("Nav_Settings"); click("Toggle_Music")
elseif scenario == "cloakroom" then
	click("Nav_Inventory")
elseif scenario == "concierge" then
	click("Nav_Quests")
elseif scenario == "hover" then
	local play = find("PlayButton")
	if play then play.MouseEnter:Fire() end
	local nav = find("Nav_Quests")
	if nav then nav.MouseEnter:Fire() end
end

-- Serialise ------------------------------------------------------------------------------------------
local PROPS = {
	"Size", "Position", "AnchorPoint", "Visible", "BackgroundColor3", "BackgroundTransparency", "BorderSizePixel",
	"BorderColor3", "Rotation", "ZIndex", "ClipsDescendants", "LayoutOrder", "Text", "TextSize", "TextColor3",
	"TextTransparency", "Font", "FontFace", "TextXAlignment", "TextYAlignment", "TextWrapped", "TextScaled", "RichText",
	"LineHeight", "TextStrokeTransparency", "TextStrokeColor3", "ScrollBarThickness", "ScrollBarImageColor3",
	"ScrollBarImageTransparency", "CanvasSize", "Image", "ImageColor3", "ImageTransparency", "IgnoreGuiInset", "Enabled",
	"CornerRadius", "Color", "Thickness", "Transparency", "ApplyStrokeMode", "Offset", "FillDirection", "Padding",
	"HorizontalAlignment", "VerticalAlignment", "SortOrder", "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom",
	"AspectRatio", "AspectType", "DominantAxis", "Scale", "ZIndexBehavior",
}

local function value(v)
	local kind = typeof(v)
	if kind == "UDim2" then
		return {t = "UDim2", xs = v.X.Scale, xo = v.X.Offset, ys = v.Y.Scale, yo = v.Y.Offset}
	elseif kind == "UDim" then
		return {t = "UDim", s = v.Scale, o = v.Offset}
	elseif kind == "Vector2" then
		return {t = "Vector2", x = v.X, y = v.Y}
	elseif kind == "Color3" then
		return {t = "Color3", r = v.R, g = v.G, b = v.B}
	elseif kind == "EnumItem" then
		return {t = "Enum", v = v.Name}
	elseif kind == "ColorSequence" then
		local points = {}
		for _, k in ipairs(v.Keypoints) do table.insert(points, {k.Time, k.Value.R, k.Value.G, k.Value.B}) end
		return {t = "ColorSequence", k = points}
	elseif kind == "NumberSequence" then
		local points = {}
		for _, k in ipairs(v.Keypoints) do table.insert(points, {k.Time, k.Value}) end
		return {t = "NumberSequence", k = points}
	elseif kind == "boolean" or kind == "number" or kind == "string" then
		return v
	elseif kind == "table" then
		if getmetatable(v) ~= nil then return nil end -- an Instance (mock node)
		local out = {}
		for key, inner in pairs(v) do out[tostring(key)] = value(inner) end
		return out
	end
	return nil
end

local function dump(object)
	local entry = {cls = object.ClassName, name = object.Name, props = {}, children = {}}
	for _, key in ipairs(PROPS) do
		local ok, v = pcall(function() return object[key] end)
		if ok and v ~= nil then
			local encoded = value(v)
			if encoded ~= nil then entry.props[key] = encoded end
		end
	end
	for _, child in ipairs(object:GetChildren()) do table.insert(entry.children, dump(child)) end
	return entry
end

fs.writeFile(outPath, serde.encode("json", {scenario = scenario, root = dump(gui)}, false))
print("wrote " .. outPath)
