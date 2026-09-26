--!nocheck
-- Menu contract test. Run from the project folder:  lune run tests/test_main_menu.luau
-- Mounts src/ like default.project.json (src/shared -> ReplicatedStorage.Shared,
-- src/client -> StarterPlayerScripts.Client) into a mock DataModel, so new modules added under src/
-- are requireable exactly as in Roblox. Pins what other systems rely on: instance names, callbacks,
-- page switching and touch sizes. It does not judge the look.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local rb = require("@lune/roblox")

local Mock = luau.load(fs.readFile("tests/mock.luau"), {debugName = "mock"})()
local node = Mock.node

local failures, count = 0, 0
local function check(name, ok, detail)
	count += 1
	if ok then
		print("PASS " .. name)
	else
		failures += 1
		print("FAIL " .. name .. (detail and (" :: " .. tostring(detail)) or ""))
	end
end

-- Mock DataModel ----------------------------------------------------------------------------------
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
local services = {
	ReplicatedStorage = replicated,
	StarterPlayer = starterPlayer,
	Players = {LocalPlayer = localPlayer},
	RunService = runService,
	TweenService = Mock.tweenService(),
	GuiService = {ReducedMotionEnabled = false},
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
mount("src/shared", node("Folder", {Name = "Shared", Parent = replicated}))
mount("src/client", node("Folder", {Name = "Client", Parent = starterScripts}))

-- Contract -------------------------------------------------------------------------------------------
local mainMenuModule = starterScripts.Client:FindFirstChild("MainMenu")
check("main_menu_module_mounted", mainMenuModule ~= nil and mainMenuModule.ClassName == "ModuleScript")
local okLoad, MainMenu = pcall(requireModule, mainMenuModule)
check("main_menu_module_loads", okLoad and type(MainMenu) == "table" and type(MainMenu.build) == "function", MainMenu)
if not okLoad then process.exit(1) end

local calls = {play = 0, buy = {}, toggle = {}, navigate = {}}
local handlers = {
	play = function() calls.play += 1 end,
	buy = function(id) table.insert(calls.buy, id) end,
	toggle = function(id, on) table.insert(calls.toggle, {id, on}) end,
	navigate = function(id) table.insert(calls.navigate, id) end,
}
local state = {
	coins = 1250,
	products = {
		{id = "speed_coil", name = "スピードコイル", price = 300},
		{id = "rainbow_trail", name = "虹のトレイル", price = 450},
		{id = "double_jump", name = "ダブルジャンプ", price = 800},
	},
	settings = {music = true, sfx = true},
}
local okBuild, gui = pcall(MainMenu.build, playerGui, handlers, state)
check("build_succeeds", okBuild and gui ~= nil, gui)
if not okBuild then process.exit(1) end
check("screen_gui_named_MainMenu", gui.ClassName == "ScreenGui" and gui.Name == "MainMenu" and gui.Parent == playerGui)

local function find(name, class)
	local found = gui:FindFirstChild(name, true)
	return found and (class == nil or found:IsA(class)) and found or nil
end
local function click(button)
	button.InputBegan:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1, UserInputState = rb.Enum.UserInputState.Begin})
	button.InputEnded:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1, UserInputState = rb.Enum.UserInputState.End})
	button.Activated:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1}, 1)
end

local play = find("PlayButton", "GuiButton")
check("play_button_exists", play ~= nil)
local coin = find("CoinLabel")
check("coin_label_shows_coins", coin ~= nil and type(coin.Text) == "string" and (string.find(coin.Text, "1250", 1, true) or string.find(coin.Text, "1,250", 1, true)) ~= nil,
	coin and coin.Text)
for _, id in ipairs({"Shop", "Inventory", "Quests", "Settings"}) do
	check("nav_button_" .. id, find("Nav_" .. id, "GuiButton") ~= nil)
	check("page_" .. id, find(id .. "Page") ~= nil and find(id .. "Page"):IsA("GuiObject"))
end
for _, product in ipairs(state.products) do
	local row = find("Product_" .. product.id)
	check("product_row_" .. product.id, row ~= nil and row:FindFirstChild("BuyButton", true) ~= nil)
end
check("toggle_music", find("Toggle_Music", "GuiButton") ~= nil)
check("toggle_sfx", find("Toggle_SFX", "GuiButton") ~= nil)

-- Behaviour
if play then click(play) end
check("play_calls_handler_once", calls.play == 1, calls.play)
local shopNav = find("Nav_Shop", "GuiButton")
if shopNav then click(shopNav) end
check("nav_opens_shop_only", find("ShopPage") and find("ShopPage").Visible == true
	and not find("SettingsPage").Visible and not find("InventoryPage").Visible and not find("QuestsPage").Visible)
check("navigate_handler", calls.navigate[#calls.navigate] == "Shop")
local rainbow = find("Product_rainbow_trail")
local buy = rainbow and rainbow:FindFirstChild("BuyButton", true)
if buy then click(buy) end
check("buy_calls_handler_with_id", calls.buy[1] == "rainbow_trail" and #calls.buy == 1, calls.buy[1])
local settingsNav = find("Nav_Settings", "GuiButton")
if settingsNav then click(settingsNav) end
check("nav_switches_to_settings", find("SettingsPage").Visible == true and find("ShopPage").Visible == false)
local music = find("Toggle_Music", "GuiButton")
if music then click(music) end
check("toggle_reports_off", calls.toggle[1] and calls.toggle[1][1] == "music" and calls.toggle[1][2] == false)
check("toggle_text_shows_state", music and string.find(string.upper(music.Text), "OFF", 1, true) ~= nil, music and music.Text)
local close = find("SettingsPage"):FindFirstChild("CloseButton", true)
if close then click(close) end
check("close_hides_page", close ~= nil and find("SettingsPage").Visible == false)

-- Touch targets: every button sized in pixels must be at least 48 x 48.
local small = {}
for _, object in ipairs(gui:GetDescendants()) do
	if object:IsA("GuiButton") and object.Size then
		local size = object.Size
		if (size.X.Scale == 0 and size.X.Offset < 48) or (size.Y.Scale == 0 and size.Y.Offset < 48) then
			table.insert(small, object.Name .. " " .. tostring(size))
		end
	end
end
check("touch_targets_at_least_48px", #small == 0, table.concat(small, ", "))

-- A second menu (respawn / another PlayerGui) builds independently.
local secondGui = node("Folder", {Name = "PlayerGui2"})
local okSecond = pcall(MainMenu.build, secondGui, handlers, state)
check("builds_again", okSecond and secondGui:FindFirstChild("MainMenu") ~= nil)

print(string.format("%s main menu contract: %d checks, %d failed", failures == 0 and "PASS" or "FAIL", count, failures))
process.exit(failures == 0 and 0 or 1)
