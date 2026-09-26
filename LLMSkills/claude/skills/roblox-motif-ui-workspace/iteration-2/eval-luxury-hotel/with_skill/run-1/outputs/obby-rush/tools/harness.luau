--!nocheck
-- Mounts a project's src/ into a mock DataModel the same way tests/test_main_menu.luau does and
-- builds the main menu. Shared by tools/test_hotel_skin.luau and tools/dump_menu.luau.
-- Run the tools from the project folder (paths are relative to it).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local rb = require("@lune/roblox")

local Harness = {}

-- options: root (project folder, default "."), mockPath, reducedMotion, withoutSkin
function Harness.new(options)
	options = options or {}
	local root = options.root or "."
	local Mock = luau.load(fs.readFile(options.mockPath or "tools/preview_mock.luau"), {debugName = "preview_mock"})()
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

	local sources, cache = {}, {}
	local requireModule
	local function envFor(script)
		local env = Mock.environment({services = services, require = function(target) return requireModule(target) end})
		env.game, env.script = game, script
		env.workspace = {CurrentCamera = {ViewportSize = rb.Vector2.new(1280, 720)}}
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
					local script = node(class, {Name = name, Parent = parent})
					sources[script] = path
				end
			end
		end
	end
	local shared = node("Folder", {Name = "Shared", Parent = replicated})
	local client = node("Folder", {Name = "Client", Parent = starterScripts})
	mount(root .. "/src/shared", shared)
	mount(root .. "/src/client", client)
	if options.withoutSkin then
		local skin = shared:FindFirstChild("HotelSkin")
		if skin then skin.Parent = nil end
	end

	local h = {Mock = Mock, rb = rb, game = game, services = services, playerGui = playerGui, shared = shared,
		client = client, tweens = tweenService.created, require = requireModule}

	h.state = {
		coins = 1250,
		products = {
			{id = "speed_coil", name = "スピードコイル", price = 300},
			{id = "rainbow_trail", name = "虹のトレイル", price = 450},
			{id = "double_jump", name = "ダブルジャンプ", price = 800},
		},
		settings = {music = true, sfx = true},
	}
	h.calls = {play = 0, buy = {}, toggle = {}, navigate = {}}
	h.handlers = {
		play = function() h.calls.play += 1 end,
		buy = function(id) table.insert(h.calls.buy, id) end,
		toggle = function(id, on) table.insert(h.calls.toggle, {id, on}) end,
		navigate = function(id) table.insert(h.calls.navigate, id) end,
	}

	function h.mainMenu()
		return requireModule(client:FindFirstChild("MainMenu"))
	end
	function h.theme()
		return requireModule(shared:FindFirstChild("UITheme"))
	end
	function h.build(parent)
		return h.mainMenu().build(parent or playerGui, h.handlers, h.state)
	end
	-- Pretend the engine laid the screen out at width x height (fires AbsoluteSize listeners).
	function h.resize(gui, width, height)
		local size = rb.Vector2.new(width, height)
		gui.AbsoluteSize = size
		local background = gui:FindFirstChild("Background")
		if background then background.AbsoluteSize = size end
	end
	function h.click(button)
		button.InputBegan:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1, UserInputState = rb.Enum.UserInputState.Begin})
		button.InputEnded:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1, UserInputState = rb.Enum.UserInputState.End})
		button.Activated:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1}, 1)
	end
	return h
end

return Harness
