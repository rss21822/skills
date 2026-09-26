--!nocheck
-- Shared Lune harness for the dig-site skin test and the preview renderer.
-- Mounts src/ exactly like default.project.json (and like tests/test_main_menu.luau, whose mock it reuses
-- read-only), so the skin runs through the same require paths as in Roblox. Run from the project folder.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local rb = require("@lune/roblox")

local Mock = luau.load(fs.readFile("tests/mock.luau"), {debugName = "mock"})()
local node = Mock.node

local Harness = {Mock = Mock, rb = rb}

-- options: {reducedMotion = bool, root = "src" (source folder to mount)}
function Harness.new(options)
	options = options or {}
	local root = options.root or "src"
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

	local h = {game = game, playerGui = playerGui, services = services, tweens = tweenService.created, warnings = {}}
	local sources, cache = {}, {}
	local requireModule
	local function envFor(script)
		local env = Mock.environment({services = services, require = function(target) return requireModule(target) end})
		env.game, env.script = game, script
		env.workspace = {CurrentCamera = {ViewportSize = rb.Vector2.new(1280, 720)}}
		env.warn = function(...)
			local parts = {}
			for _, value in ipairs({...}) do table.insert(parts, tostring(value)) end
			table.insert(h.warnings, table.concat(parts, " "))
		end
		return env
	end
	function requireModule(target)
		if cache[target] ~= nil then return cache[target] end
		local path = sources[target]
		assert(path, "require of a module that is not mounted: " .. tostring(target))
		local chunk = luau.load(fs.readFile(path), {debugName = path, environment = envFor(target)})
		local result = chunk()
		cache[target] = result
		return result
	end
	local function mount(dir, parent)
		for _, entry in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. entry
			if fs.isDir(path) then
				local init = nil
				for _, name in ipairs({"init.luau", "init.lua"}) do
					if fs.isFile(path .. "/" .. name) then init = path .. "/" .. name end
				end
				local folder = node(init and "ModuleScript" or "Folder", {Name = entry, Parent = parent})
				if init then sources[folder] = init end
				mount(path, folder)
			elseif not string.match(entry, "^init%.luau?$") then
				local name, kind = string.match(entry, "^(.-)%.(%a+)%.luau?$")
				if not name then name = string.match(entry, "^(.-)%.luau?$") end
				if name then
					local class = kind == "client" and "LocalScript" or kind == "server" and "Script" or "ModuleScript"
					sources[node(class, {Name = name, Parent = parent})] = path
				end
			end
		end
	end
	mount(root .. "/shared", node("Folder", {Name = "Shared", Parent = replicated}))
	mount(root .. "/client", node("Folder", {Name = "Client", Parent = starterScripts}))
	h.client = starterScripts.Client
	h.shared = replicated.Shared
	h.require = requireModule

	function h.menu() return requireModule(h.client:FindFirstChild("MainMenu")) end
	function h.skin()
		local folder = h.client:FindFirstChild("DigSite")
		return folder and requireModule(folder:FindFirstChild("DinoDigSkin")) or nil
	end
	function h.theme() return requireModule(h.shared:FindFirstChild("UITheme")) end
	return h
end

Harness.handlers = function(calls)
	calls = calls or {play = 0, buy = {}, toggle = {}, navigate = {}}
	return {
		play = function() calls.play += 1 end,
		buy = function(id) table.insert(calls.buy, id) end,
		toggle = function(id, on) table.insert(calls.toggle, {id, on}) end,
		navigate = function(id) table.insert(calls.navigate, id) end,
	}, calls
end

-- Same data as src/client/MenuEntry.client.luau.
Harness.state = function()
	return {
		coins = 1250,
		products = {
			{id = "speed_coil", name = "スピードコイル", price = 300},
			{id = "rainbow_trail", name = "虹のトレイル", price = 450},
			{id = "double_jump", name = "ダブルジャンプ", price = 800},
		},
		settings = {music = true, sfx = true},
	}
end

function Harness.click(button)
	button.InputBegan:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1, UserInputState = rb.Enum.UserInputState.Begin})
	button.InputEnded:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1, UserInputState = rb.Enum.UserInputState.End})
	button.Activated:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1}, 1)
end

return Harness
