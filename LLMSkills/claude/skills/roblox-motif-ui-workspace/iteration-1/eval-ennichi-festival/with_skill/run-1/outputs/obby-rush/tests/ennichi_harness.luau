--!nocheck
-- Shared Lune harness for the Ennichi skin test and the UI preview dumper (run from the project folder).
-- Mounts src/ into a mock DataModel exactly like tests/test_main_menu.luau (default.project.json layout)
-- and adds two things that test does not need: a crude layout pass that fills AbsoluteSize (so the
-- skin's responsive code runs as it would in Roblox) and hooks for warn / task.defer / reduced motion.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local rb = require("@lune/roblox")

local Mock = luau.load(fs.readFile("tests/mock.luau"), {debugName = "mock"})()
local node = Mock.node

local Harness = {Mock = Mock, rb = rb}

-- options: {reducedMotion = bool, deferNow = bool (run task.defer callbacks immediately),
--           skip = {"src/client/Ennichi", ...} (paths not mounted), viewport = Vector2}
function Harness.world(options)
	options = options or {}
	local world = {warnings = {}}
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
		RunService = runService, TweenService = tweenService,
		GuiService = {ReducedMotionEnabled = options.reducedMotion == true},
		UserInputService = {TouchEnabled = false, GetLastInputType = function() return rb.Enum.UserInputType.MouseMovement end,
			InputBegan = Mock.signal(), InputEnded = Mock.signal()},
		SoundService = node("Folder", {Name = "SoundService"}), TextService = {}, ContentProvider = {PreloadAsync = function() end},
	}
	function game:GetService(name) return services[name] end
	local viewport = options.viewport or rb.Vector2.new(1280, 720)
	local camera = {ViewportSize = viewport}

	local sources, cache = {}, {}
	local requireModule
	local function envFor(script)
		local env = Mock.environment({services = services, require = function(target) return requireModule(target) end})
		env.game, env.script = game, script
		env.workspace = {CurrentCamera = camera}
		env.warn = function(...) table.insert(world.warnings, table.concat(table.pack(...), " ")) end
		if options.deferNow then
			env.task = {spawn = function() end, delay = function() end, wait = function() return 0 end,
				defer = function(fn, ...) fn(...) end}
		end
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
	local skip = {}
	for _, path in ipairs(options.skip or {}) do skip[path] = true end
	local function mount(dir, parent)
		for _, entry in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. entry
			if skip[path] then continue end
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
	mount("src/shared", node("Folder", {Name = "Shared", Parent = replicated}))
	mount("src/client", node("Folder", {Name = "Client", Parent = starterScripts}))

	world.game, world.services, world.playerGui, world.tweenService = game, services, playerGui, tweenService
	world.require = requireModule
	world.client = starterScripts:FindFirstChild("Client")
	world.shared = replicated:FindFirstChild("Shared")
	world.camera = camera
	function world.module(path)
		local target = world.client
		for part in string.gmatch(path, "[^%.]+") do target = target and target:FindFirstChild(part) end
		return target and requireModule(target)
	end
	return world
end

Harness.handlers = function(calls)
	return {
		play = function() calls.play = (calls.play or 0) + 1 end,
		buy = function(id) calls.buy = calls.buy or {}; table.insert(calls.buy, id) end,
		toggle = function(id, on) calls.toggle = calls.toggle or {}; table.insert(calls.toggle, {id, on}) end,
		navigate = function(id) calls.navigate = calls.navigate or {}; table.insert(calls.navigate, id) end,
	}
end

Harness.state = {
	coins = 1250,
	products = {
		{id = "speed_coil", name = "スピードコイル", price = 300},
		{id = "rainbow_trail", name = "虹のトレイル", price = 450},
		{id = "double_jump", name = "ダブルジャンプ", price = 800},
	},
	settings = {music = true, sfx = true},
}

-- Crude layout: AbsoluteSize from Size (scale of the parent's size minus UIPadding, plus offset),
-- clamped by UISizeConstraint. Children of a UIListLayout are measured the same way (their positions
-- are not needed by the skin). Run twice so size-dependent handlers settle.
function Harness.layout(gui, width, height)
	local function number(udim) return udim and udim.Offset or 0 end
	local function visit(object, parentWidth, parentHeight)
		local w, h = parentWidth, parentHeight
		if object:IsA("GuiObject") then
			local size = object.Size
			w = size.X.Scale * parentWidth + size.X.Offset
			h = size.Y.Scale * parentHeight + size.Y.Offset
			local limits = object:FindFirstChildOfClass("UISizeConstraint")
			if limits then
				w = math.clamp(w, limits.MinSize and limits.MinSize.X or 0, limits.MaxSize and limits.MaxSize.X or math.huge)
				h = math.clamp(h, limits.MinSize and limits.MinSize.Y or 0, limits.MaxSize and limits.MaxSize.Y or math.huge)
			end
			object.AbsoluteSize = rb.Vector2.new(w, h)
		elseif object.ClassName == "ScreenGui" then
			object.AbsoluteSize = rb.Vector2.new(width, height)
			w, h = width, height
		end
		local padding = object:FindFirstChildOfClass("UIPadding")
		local innerW, innerH = w, h
		if padding then
			innerW = w - number(padding.PaddingLeft) - number(padding.PaddingRight)
			innerH = h - number(padding.PaddingTop) - number(padding.PaddingBottom)
		end
		for _, child in ipairs(object:GetChildren()) do visit(child, innerW, innerH) end
	end
	for _ = 1, 3 do visit(gui, width, height) end
end

return Harness
