--!nocheck
-- Mounts src/ into the mock DataModel exactly like tests/test_main_menu.luau (and reuses its
-- tests/mock.luau, read-only) so design tools can build the real menu outside Studio.
-- Run the tools from the project folder, e.g.  lune run design/test_night_ward_skin.luau
--
--   local Harness = luau.load(fs.readFile("design/harness.luau"))()
--   local h = Harness({viewport = Vector2(1280, 720), reducedMotion = false, skip = {NightWardArt = true}})
--   local MainMenu = h.requireClient("MainMenu")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local rb = require("@lune/roblox")

local Mock = luau.load(fs.readFile("tests/mock.luau"), {debugName = "mock"})()
local node = Mock.node

return function(options)
	options = options or {}
	local skip = options.skip or {}
	local game = node("DataModel", {Name = "Game"})
	local replicated = node("Folder", {Name = "ReplicatedStorage", Parent = game})
	local starterPlayer = node("Folder", {Name = "StarterPlayer", Parent = game})
	local starterScripts = node("Folder", {Name = "StarterPlayerScripts", Parent = starterPlayer})
	local playerGui = node("Folder", {Name = "PlayerGui"})
	local localPlayer = {Name = options.playerName or "Tester", UserId = 1, PlayerGui = playerGui}
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

	local warnings = {}
	local sources, cache = {}, {}
	local requireModule
	local function envFor(script)
		local env = Mock.environment({services = services, require = function(target) return requireModule(target) end})
		env.game, env.script = game, script
		env.workspace = {CurrentCamera = {ViewportSize = options.viewport or rb.Vector2.new(1280, 720)}}
		env.warn = function(...)
			local parts = {}
			for _, value in ipairs({...}) do table.insert(parts, tostring(value)) end
			table.insert(warnings, table.concat(parts, " "))
		end
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
				mount(path, node("Folder", {Name = entry, Parent = parent}))
			else
				local name, kind = string.match(entry, "^(.-)%.(%a+)%.luau?$")
				if not name then name = string.match(entry, "^(.-)%.luau?$") end
				if name and not skip[name] then
					local class = kind == "client" and "LocalScript" or kind == "server" and "Script" or "ModuleScript"
					sources[node(class, {Name = name, Parent = parent})] = path
				end
			end
		end
	end
	mount("src/shared", node("Folder", {Name = "Shared", Parent = replicated}))
	mount("src/client", node("Folder", {Name = "Client", Parent = starterScripts}))

	local h = {Mock = Mock, rb = rb, game = game, services = services, playerGui = playerGui, warnings = warnings,
		tweens = tweenService.created, require = requireModule, starterScripts = starterScripts, replicated = replicated}
	function h.requireClient(name) return requireModule(starterScripts.Client:FindFirstChild(name)) end
	function h.requireShared(name) return requireModule(replicated.Shared:FindFirstChild(name)) end
	h.handlers = {play = function() end, buy = function() end, toggle = function() end, navigate = function() end}
	h.state = {
		coins = 1250,
		products = {
			{id = "speed_coil", name = "スピードコイル", price = 300},
			{id = "rainbow_trail", name = "虹のトレイル", price = 450},
			{id = "double_jump", name = "ダブルジャンプ", price = 800},
		},
		settings = {music = true, sfx = true},
	}
	return h
end
