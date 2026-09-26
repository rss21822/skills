--!nocheck
-- Test/preview harness for the menu (Lune). Mounts src/ exactly like tests/test_main_menu.luau does
-- (src/shared -> ReplicatedStorage.Shared, src/client -> StarterPlayerScripts.Client) into the mock
-- DataModel from tests/mock.luau, with a configurable viewport, reduced motion and skin on/off.
-- Run tools from the project folder (paths are relative to it).
--
--   local Harness = luau.load(fs.readFile("tools/harness.luau"))()
--   local h = Harness.new({width = 1280, height = 720, reducedMotion = false, skin = true})
--   local gui = h.build()
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local rb = require("@lune/roblox")

local Mock = luau.load(fs.readFile("tests/mock.luau"), {debugName = "mock"})()
local node = Mock.node

local Harness = {Mock = Mock, rb = rb}

Harness.STATE = {
	coins = 1250,
	products = {
		{id = "speed_coil", name = "スピードコイル", price = 300},
		{id = "rainbow_trail", name = "虹のトレイル", price = 450},
		{id = "double_jump", name = "ダブルジャンプ", price = 800},
	},
	settings = {music = true, sfx = true},
}

function Harness.new(options)
	options = options or {}
	local h = {spawned = {}, calls = {play = 0, buy = {}, toggle = {}, navigate = {}}}
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
		ReplicatedStorage = replicated,
		StarterPlayer = starterPlayer,
		Players = {LocalPlayer = localPlayer},
		RunService = runService,
		TweenService = tweenService,
		GuiService = {ReducedMotionEnabled = options.reducedMotion == true},
		UserInputService = {TouchEnabled = false, GetLastInputType = function() return rb.Enum.UserInputType.MouseMovement end,
			InputBegan = Mock.signal(), InputEnded = Mock.signal()},
		SoundService = node("Folder", {Name = "SoundService"}),
		TextService = {},
		ContentProvider = {PreloadAsync = function() end},
	}
	function game:GetService(name) return services[name] end
	local viewport = rb.Vector2.new(options.width or 1280, options.height or 720)

	local sources, cache = {}, {}
	local requireModule
	local function envFor(script)
		local env = Mock.environment({services = services, require = function(target) return requireModule(target) end})
		env.game, env.script = game, script
		env.workspace = {CurrentCamera = {ViewportSize = viewport}}
		env.task = {
			spawn = function(fn, ...) table.insert(h.spawned, fn) end,
			defer = function() end, delay = function() end, wait = function() return 0 end,
		}
		return env
	end
	function requireModule(target)
		if cache[target] ~= nil then return cache[target] end
		local path = sources[target]
		assert(path, "require of a module that is not mounted from src/: " .. tostring(target))
		local chunk = luau.load(fs.readFile(path), {debugName = path, environment = envFor(target)})
		local result = chunk()
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
	mount("src/shared", node("Folder", {Name = "Shared", Parent = replicated}))
	local client = node("Folder", {Name = "Client", Parent = starterScripts})
	mount("src/client", client)
	if options.skin == false then
		local ui = client:FindFirstChild("ui")
		if ui then ui.Parent = nil end
	end

	h.services, h.tweenService, h.playerGui, h.client, h.replicated = services, tweenService, playerGui, client, replicated
	h.require = requireModule
	h.MainMenu = requireModule(client:FindFirstChild("MainMenu"))
	h.Theme = requireModule(replicated.Shared:FindFirstChild("UITheme"))
	local ui = client:FindFirstChild("ui")
	h.Skin = ui and ui:FindFirstChild("FamicomSkin") and requireModule(ui:FindFirstChild("FamicomSkin")) or nil
	h.handlers = {
		play = function() h.calls.play += 1 end,
		buy = function(id) table.insert(h.calls.buy, id) end,
		toggle = function(id, on) table.insert(h.calls.toggle, {id, on}) end,
		navigate = function(id) table.insert(h.calls.navigate, id) end,
	}
	function h.build(parent)
		return h.MainMenu.build(parent or playerGui, h.handlers, table.clone(Harness.STATE))
	end
	return h
end

function Harness.click(button)
	button.InputBegan:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1, UserInputState = rb.Enum.UserInputState.Begin})
	button.InputEnded:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1, UserInputState = rb.Enum.UserInputState.End})
	button.Activated:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1}, 1)
end

-- "Game.PlayerGui.MainMenu.Background.PlayButton:TextButton" for every instance not added by the skin
-- (names starting with "Motif", and anything under them, are presentation-only additions).
function Harness.contractPaths(gui)
	local paths = {}
	local function walk(object, prefix)
		for _, child in ipairs(object:GetChildren()) do
			if string.sub(child.Name, 1, 5) ~= "Motif" then
				local path = prefix .. "." .. child.Name .. ":" .. child.ClassName
				table.insert(paths, path)
				walk(child, prefix .. "." .. child.Name)
			end
		end
	end
	walk(gui, gui.Name)
	table.sort(paths)
	return paths
end

return Harness
