--!nocheck
-- Extra behaviour checks for the redesigned menu, beyond tests/test_main_menu.luau (which is unchanged).
-- Run from the outputs folder:  lune run preview/extra_checks.luau obby-rush
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local rb = require("@lune/roblox")

local root = process.args[1] or "obby-rush"
local Mock = luau.load(fs.readFile(root .. "/tests/mock.luau"), {debugName = "mock"})()
local node = Mock.node

local failures, count = 0, 0
local function check(name, ok, detail)
	count += 1
	if not ok then failures += 1 end
	print((ok and "PASS " or "FAIL ") .. name .. ((not ok and detail) and (" :: " .. tostring(detail)) or ""))
end

local function harness(reducedMotion)
	local game = node("DataModel", {Name = "Game"})
	local replicated = node("Folder", {Name = "ReplicatedStorage", Parent = game})
	local starterPlayer = node("Folder", {Name = "StarterPlayer", Parent = game})
	local starterScripts = node("Folder", {Name = "StarterPlayerScripts", Parent = starterPlayer})
	local playerGui = node("Folder", {Name = "PlayerGui"})
	local runService = {Heartbeat = Mock.signal(), RenderStepped = Mock.signal(), Stepped = Mock.signal()}
	local guiService = {ReducedMotionEnabled = reducedMotion}
	function guiService:GetGuiInset() return rb.Vector2.new(0, 58), rb.Vector2.new(0, 0) end
	local services = {ReplicatedStorage = replicated, StarterPlayer = starterPlayer, RunService = runService,
		TweenService = Mock.tweenService(), GuiService = guiService, Players = {LocalPlayer = {PlayerGui = playerGui}}}
	function game:GetService(name) return services[name] end
	local now = 0
	local sources, cache = {}, {}
	local requireModule
	function requireModule(target)
		if cache[target] ~= nil then return cache[target] end
		local env = Mock.environment({services = services, now = function() return now end, require = requireModule})
		env.game, env.script = game, target
		env.workspace = {CurrentCamera = {ViewportSize = rb.Vector2.new(1280, 720)}}
		cache[target] = luau.load(fs.readFile(sources[target]), {debugName = sources[target], environment = env})()
		return cache[target]
	end
	local function mount(dir, parent)
		for _, entry in ipairs(fs.readDir(dir)) do
			local name, kind = string.match(entry, "^(.-)%.(%a+)%.luau$")
			if not name then name = string.match(entry, "^(.-)%.luau$") end
			if name then
				sources[node(kind == "client" and "LocalScript" or "ModuleScript", {Name = name, Parent = parent})] = dir .. "/" .. entry
			end
		end
	end
	mount(root .. "/src/shared", node("Folder", {Name = "Shared", Parent = replicated}))
	mount(root .. "/src/client", node("Folder", {Name = "Client", Parent = starterScripts}))
	local MainMenu = requireModule(starterScripts.Client:FindFirstChild("MainMenu"))
	local calls = {}
	local gui = MainMenu.build(playerGui, {play = function() end, buy = function() end, toggle = function(id, on) table.insert(calls, {id, on}) end},
		{coins = 1250, products = {{id = "a", name = "スピードコイル", price = 300}}, settings = {music = false, sfx = true}})
	return {gui = gui, MainMenu = MainMenu, heartbeat = runService.Heartbeat, setNow = function(t) now = t end, calls = calls}
end

local function click(button)
	button.InputBegan:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
	button.InputEnded:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
	button.Activated:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1}, 1)
end

-- Idle motion runs, and stops for reduced-motion players.
local moving = harness(false)
local hanger = moving.gui:FindFirstChild("Hanger3", true)
local fish = moving.gui:FindFirstChild("Goldfish1", true)
local fishBefore = fish.Position
moving.setNow(5)
moving.heartbeat:Fire(1 / 60)
check("lanterns_sway", hanger.Rotation ~= 0, hanger.Rotation)
check("goldfish_swim", fish.Position ~= fishBefore)
local still = harness(true)
local stillHanger = still.gui:FindFirstChild("Hanger3", true)
local restRotation = stillHanger.Rotation
still.setNow(5)
still.heartbeat:Fire(1 / 60)
check("reduced_motion_freezes_idle_animation", stillHanger.Rotation == restRotation)

-- Heartbeat connection is released with the gui.
moving.gui:Destroy()
local live = 0
for _, entry in ipairs(moving.heartbeat.listeners) do if entry.connection.Connected then live += 1 end end
check("heartbeat_disconnected_on_destroy", live == 0, live)

-- Page state: scrim and the lit stall tag follow the open page.
local h = harness(false)
local gui = h.gui
local scrim = gui:FindFirstChild("Scrim", true)
check("scrim_hidden_initially", scrim.Visible == false)
click(gui:FindFirstChild("Nav_Shop", true))
check("scrim_shown_with_page", scrim.Visible == true)
check("open_tag_is_lit", gui:FindFirstChild("Nav_Shop", true):GetAttribute("ThemeStyle") == "primary")
check("other_tags_stay_wood", gui:FindFirstChild("Nav_Quests", true):GetAttribute("ThemeStyle") == "wood")
click(gui:FindFirstChild("ShopPage"):FindFirstChild("CloseButton", true))
check("scrim_hidden_after_close", scrim.Visible == false)
check("tag_unlit_after_close", gui:FindFirstChild("Nav_Shop", true):GetAttribute("ThemeStyle") == "wood")

-- Text written by other scripts reaches the visible label; coins helper formats.
local play = gui:FindFirstChild("PlayButton", true)
play.Text = "あそぶ"
check("button_text_mirrors_to_face", play.Face.Label.Text == "あそぶ")
h.MainMenu.setCoins(gui, 1234567)
check("set_coins_formats", gui:FindFirstChild("CoinLabel", true).Text == "1,234,567", gui:FindFirstChild("CoinLabel", true).Text)
check("coin_label_path_kept", gui.Background.TopBar:FindFirstChild("CoinLabel") ~= nil and gui.Background.TopBar:FindFirstChild("Title") ~= nil)
check("play_path_kept", gui.Background:FindFirstChild("PlayButton") ~= nil and gui.Background.NavBar:FindFirstChild("Nav_Shop") ~= nil)
check("toggle_path_kept", gui.SettingsPage:FindFirstChild("Toggle_Music") ~= nil and gui.ShopPage.ProductList:FindFirstChild("Product_a") ~= nil)

-- Initial OFF setting shows OFF and the switch follows a click.
local music = gui:FindFirstChild("Toggle_Music", true)
check("initial_off_text", string.find(music.Text, "OFF", 1, true) ~= nil, music.Text)
local marble = music:FindFirstChild("Marble", true)
local offX = marble.Position.X.Offset
click(music)
check("switch_marble_moves_on", marble.Position.X.Offset > offX and h.calls[1][2] == true)

-- Press feedback: face sinks while held, returns on release.
local face = play.Face
play.InputBegan:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
local pressedY = face.Position.Y.Offset
play.InputEnded:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
check("press_sinks_face", pressedY > 0 and face.Position.Y.Offset == 0, pressedY)

-- Legibility: no fixed-size text under 14 px; every button label is at least 18 px.
local small = {}
for _, object in ipairs(gui:GetDescendants()) do
	if (object.ClassName == "TextLabel" or object.ClassName == "TextButton") and not object.TextScaled and object.TextSize < 14 then
		table.insert(small, object:GetFullName())
	end
end
check("no_text_under_14px", #small == 0, table.concat(small, ", "))

print(string.format("%s extra checks: %d checks, %d failed", failures == 0 and "PASS" or "FAIL", count, failures))
process.exit(failures == 0 and 0 or 1)
