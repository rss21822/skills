--!nocheck
-- Deep-sea skin ("Abyss Lantern") test. Run from the project folder:  lune run tests/test_deep_sea_skin.luau
-- Mounts src/ exactly like tests/test_main_menu.luau (same mock), builds the real MainMenu and checks
-- that the skin actually ran (not just that pcall swallowed it): colours, looks per element, the
-- page / nav / scrim sync, the toggle switch, responsive layout, reduced motion, loop pausing,
-- idempotence, restore, section rollback and the fallback when the skin module fails to load.
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
		print("FAIL " .. name .. (detail ~= nil and (" :: " .. tostring(detail)) or ""))
	end
end
local function near(a, b) return math.abs(a - b) < 1e-3 end
local function sameColor(a, b)
	return a ~= nil and b ~= nil and near(a.R, b.R) and near(a.G, b.G) and near(a.B, b.B)
end

local STATE = {
	coins = 1250,
	products = {
		{id = "speed_coil", name = "スピードコイル", price = 300},
		{id = "rainbow_trail", name = "虹のトレイル", price = 450},
		{id = "double_jump", name = "ダブルジャンプ", price = 800},
	},
	settings = {music = true, sfx = true},
}

-- A fresh mock DataModel with src/ mounted. options: reducedMotion, overrides = {[module name] = fn}
local function boot(options)
	options = options or {}
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
	local warnings = {}
	local sources, cache = {}, {}
	local requireModule
	local function envFor(script)
		local env = Mock.environment({services = services, require = function(target) return requireModule(target) end})
		env.game, env.script = game, script
		env.workspace = {CurrentCamera = {ViewportSize = rb.Vector2.new(1280, 720)}}
		env.warn = function(...) table.insert(warnings, table.concat(table.pack(...), " ")) end
		-- Run deferred work at once so hover repaints are observable.
		env.task = {spawn = function() end, delay = function() end, wait = function() return 0 end,
			defer = function(fn, ...) fn(...) end}
		return env
	end
	function requireModule(target)
		if cache[target] ~= nil then return cache[target] end
		local override = options.overrides and options.overrides[target.Name]
		local result
		if override then
			result = override()
		else
			local path = assert(sources[target], "module not mounted: " .. tostring(target))
			result = luau.load(fs.readFile(path), {debugName = path, environment = envFor(target)})()
		end
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
					local class = kind == "client" and "LocalScript" or kind == "server" and "Script" or "ModuleScript"
					sources[node(class, {Name = name, Parent = parent})] = path
				end
			end
		end
	end
	local shared = node("Folder", {Name = "Shared", Parent = replicated})
	local client = node("Folder", {Name = "Client", Parent = starterScripts})
	mount("src/shared", shared)
	mount("src/client", client)
	return {require = requireModule, shared = shared, client = client, playerGui = playerGui, tweens = tweenService,
		warnings = warnings}
end

local function handlersInto(calls)
	return {
		play = function() calls.play += 1 end,
		buy = function(id) table.insert(calls.buy, id) end,
		toggle = function(id, on) table.insert(calls.toggle, {id, on}) end,
		navigate = function(id) table.insert(calls.navigate, id) end,
	}
end
local function click(button)
	button.InputBegan:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
	button.InputEnded:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
	button.Activated:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1}, 1)
end
local function looping(tweenService)
	local list = {}
	for _, tween in ipairs(tweenService.created) do
		if type(tween.info) == "table" and tween.info[4] == -1 then table.insert(list, tween) end
	end
	return list
end
-- Same rule as the skin_preview lint: dark, low/mid-saturation blue-slate = dashboard navy.
local function isNavy(color)
	local r, g, b = color.R, color.G, color.B
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local l = (max + min) / 2
	if max == min then return false end
	local d = max - min
	local s = l > 0.5 and d / (2 - max - min) or d / (max + min)
	local h
	if max == r then h = ((g - b) / d) % 6 elseif max == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
	h *= 60
	return h >= 195 and h <= 250 and l < 0.34 and s < 0.85
end
local function textsOf(root)
	local texts = {}
	for _, object in ipairs(root:GetDescendants()) do
		if type(object.Text) == "string" and object.Text ~= "" then table.insert(texts, {object, object.Text}) end
	end
	return texts
end
-- Roblox's emoji font stops at Unicode 12 (skill: references/fonts.md).
local UNICODE12_EXT_A = {}
for _, range in ipairs({{0x1FA70, 0x1FA73}, {0x1FA78, 0x1FA7A}, {0x1FA80, 0x1FA82}, {0x1FA90, 0x1FA95}}) do
	for cp = range[1], range[2] do UNICODE12_EXT_A[cp] = true end
end
local function tofu(text)
	for _, cp in utf8.codes(text) do
		if cp >= 0x1FA70 and cp <= 0x1FAFF and not UNICODE12_EXT_A[cp] then return true end
	end
	return false
end

-- 1. Normal build ------------------------------------------------------------------------------
local B = boot()
local okSkin, Skin = pcall(B.require, B.client.ui.DeepSeaSkin)
check("skin_module_loads", okSkin and type(Skin) == "table" and type(Skin.apply) == "function", Skin)
if not okSkin then process.exit(1) end
local kit, P, C = Skin.kit, Skin.kit.P, Skin.kit.candies
local Theme = B.require(B.shared.UITheme)
local MainMenu = B.require(B.client.MainMenu)
local calls = {play = 0, buy = {}, toggle = {}, navigate = {}}
local gui = MainMenu.build(B.playerGui, handlersInto(calls), STATE)
local function find(name) return gui:FindFirstChild(name, true) end

check("theme_is_skinned", Theme.skin == Skin)
check("gui_marked", gui:GetAttribute("MotifSkin") == "AbyssLantern")
local report, failed = Skin.lastReport or {}, {}
for _, section in ipairs({"water", "topBar", "lure", "dock", "pages", "responsive", "motion"}) do
	if report[section] ~= true then table.insert(failed, section) end
end
check("every_section_ran", #failed == 0, table.concat(failed, ", "))
check("no_warnings", #B.warnings == 0, B.warnings[1])

-- Colours: the old navy table is gone from every visible surface and edge.
local OLD = {rb.Color3.fromRGB(11, 20, 38), rb.Color3.fromRGB(19, 35, 63), rb.Color3.fromRGB(28, 50, 86), rb.Color3.fromRGB(63, 169, 245)}
local navy = {}
for _, object in ipairs(gui:GetDescendants()) do
	local visible = object:IsA("GuiObject") and (object.BackgroundTransparency or 1) < 0.95
	if visible and object.BackgroundColor3 then
		for _, old in ipairs(OLD) do if sameColor(object.BackgroundColor3, old) then table.insert(navy, object:GetFullName()) end end
		if isNavy(object.BackgroundColor3) then table.insert(navy, object:GetFullName() .. " (navy hue)") end
	end
	if object.ClassName == "UIStroke" and object.Color and sameColor(object.Color, OLD[4]) then table.insert(navy, object:GetFullName()) end
end
check("no_navy_surfaces_or_edges", #navy == 0, navy[1])
check("theme_colors_recoloured", sameColor(Theme.colors.panel, P.paper) and sameColor(Theme.colors.text, P.ink)
	and sameColor(Theme.colors.accent, P.primary))

-- Every styled button: type colour follows the kit rule for its face (readable on any fill).
local unreadable = {}
for object, _ in pairs(Skin.states) do
	if object:IsDescendantOf(gui) then
		local expected = kit:textOn(object.BackgroundColor3, object.TextSize)
		if not sameColor(object.TextColor3, expected) then table.insert(unreadable, object.Name) end
	end
end
check("button_type_follows_face", #unreadable == 0, table.concat(unreadable, ", "))

-- Hero: PLAY is the lure-lit sign.
local play = find("PlayButton")
local playCorner = play:FindFirstChildOfClass("UICorner")
check("play_is_lemon_pill", sameColor(play.BackgroundColor3, P.primary) and playCorner and playCorner.CornerRadius.Scale == 1)
check("play_dark_type", sameColor(play.TextColor3, P.onLight))
check("play_biggest", play.Size.X.Offset >= 300 and play.Size.Y.Offset >= 84 and play.Rotation ~= 0)
check("play_font_rounded", play.FontFace and string.find(play.FontFace.Family, "FredokaOne", 1, true) ~= nil)
check("lure_halo_and_light", find("MotifPlayHalo") ~= nil and find("MotifDiveTag") ~= nil and find("MotifAngler") and find("MotifAngler"):FindFirstChild("LureGlowFar") ~= nil)
local fish = find("MotifAngler")
check("anglerfish_with_lure", fish ~= nil and fish:FindFirstChild("Bulb") ~= nil and fish:FindFirstChild("StalkB") ~= nil
	and fish:FindFirstChild("Eye") and fish.Eye:FindFirstChild("Pupil") ~= nil)
check("fish_rim_light", fish and sameColor(fish.Body:FindFirstChildOfClass("UIStroke").Color, P.anglerRim))
check("background_jellies", find("MotifJellyA") ~= nil and find("MotifJellyB") ~= nil)
local bubbles = find("MotifBubbles")
check("bubbles_rise", bubbles ~= nil and #bubbles:GetChildren() == 14)
check("depth_gradient", find("Background"):FindFirstChild("MotifDepth") ~= nil)

-- Top bar: porthole, display title, coin pill without the tofu coin.
local topTitle = find("TopBar"):FindFirstChild("Title")
check("title_display_font", string.find(topTitle.FontFace.Family, "LuckiestGuy", 1, true) ~= nil and topTitle.MotifTextOutline ~= nil)
check("porthole_badge", find("MotifPorthole") ~= nil)
local coins = find("CoinLabel")
check("coin_text_kept", string.find(coins.Text, "1250", 1, true) ~= nil and string.find(coins.Text, "💰", 1, true) ~= nil, coins.Text)
local tofuTexts = {}
for _, entry in ipairs(textsOf(gui)) do if tofu(entry[2]) then table.insert(tofuTexts, entry[1].Name .. "=" .. entry[2]) end end
check("no_unicode13_emoji", #tofuTexts == 0, tofuTexts[1])

-- Dock: jellyfish tiles with tentacles, each in its page's creature glow.
for id, page in pairs(Skin.pages) do
	local tile = find("Nav_" .. id)
	local tentacles = tile and tile:FindFirstChild("MotifTentacles")
	check("jelly_tile_" .. id, tile and sameColor(tile.BackgroundColor3, Skin.tintOf(page.candy))
		and sameColor(tile.MotifEdge.Color, C[page.candy]) and tentacles and #tentacles:GetChildren() == 9
		and tile:FindFirstChild("MotifTileIcon") and tile.MotifTileIcon.Text == page.icon)
end

-- Hover: UITheme's own MouseEnter recolours the fill; the skin repaints it back.
local shopTile = find("Nav_Shop")
shopTile.MouseEnter:Fire()
check("hover_keeps_designed_face", sameColor(shopTile.BackgroundColor3, Skin.tintOf("kurage")))
shopTile.MouseLeave:Fire()

-- Shop rows, buy buttons, page ribbon.
local row = find("Product_rainbow_trail")
local buy = row and row:FindFirstChild("BuyButton")
check("row_dressed", row and row:FindFirstChild("MotifChip") ~= nil and sameColor(row.BackgroundColor3, P.panel))
check("buy_is_glow_cyan", buy and sameColor(buy.BackgroundColor3, C.umibotaru) and sameColor(buy.TextColor3, P.onLight))
local shopPage = find("ShopPage")
check("page_ribbon", shopPage:FindFirstChild("MotifRibbon") ~= nil and sameColor(shopPage.MotifRibbon.BackgroundColor3, C.kurage)
	and shopPage:FindFirstChild("MotifPageBadge") ~= nil)
check("page_title_japanese_in_title_font", string.find(shopPage.Title.FontFace.Family, "FredokaOne", 1, true) ~= nil
	and sameColor(shopPage.Title.TextColor3, P.white))
check("empty_state_jelly", find("InventoryPage"):FindFirstChild("MotifEmptyJelly") ~= nil)
check("body_text_bold_for_japanese", find("InventoryPage").Empty.FontFace.Weight == rb.Enum.FontWeight.Bold)

-- Page switching drives the scrim and the selected tile.
local scrim = find("MotifScrim")
check("scrim_hidden_at_start", scrim ~= nil and scrim.Visible == false)
click(shopTile)
check("nav_still_opens_shop", shopPage.Visible == true and calls.navigate[#calls.navigate] == "Shop")
check("scrim_shows_with_page", scrim.Visible == true)
check("selected_tile_lights_up", sameColor(shopTile.BackgroundColor3, C.kurage) and shopTile:GetAttribute("Selected") == true)
click(find("Nav_Settings"))
check("selection_moves", find("Nav_Settings"):GetAttribute("Selected") == true and shopTile:GetAttribute("Selected") == false
	and sameColor(shopTile.BackgroundColor3, Skin.tintOf("kurage")))

-- Toggle switch follows the button's own ON/OFF text.
local music = find("Toggle_Music")
local switch = music:FindFirstChild("MotifSwitch")
check("switch_starts_on", switch ~= nil and switch:GetAttribute("On") == true)
click(music)
check("toggle_still_reports", calls.toggle[1] and calls.toggle[1][1] == "music" and calls.toggle[1][2] == false)
check("switch_follows_text", switch:GetAttribute("On") == false and switch.Knob.Position.X.Scale == 0
	and string.find(music.Text, "OFF", 1, true) ~= nil)
click(find("SettingsPage"):FindFirstChild("CloseButton"))
check("close_hides_scrim", scrim.Visible == false and find("SettingsPage").Visible == false)
click(play)
check("play_still_calls_handler", calls.play == 1)

-- Responsive layout (the mock has no layout engine: set AbsoluteSize like Roblox would).
local background = find("Background")
background.AbsoluteSize = rb.Vector2.new(1280, 720)
check("desktop_layout", fish.Visible == true and near(fish.MotifMascotScale.Scale, 1)
	and near(shopPage.Size.X.Scale, 0.6) and find("MotifJellyB").Visible == true)
background.AbsoluteSize = rb.Vector2.new(366, 820)
check("portrait_phone_layout", fish.Visible == true and near(fish.MotifMascotScale.Scale, 0.8)
	and shopPage.Size.X.Scale == 1 and find("MotifJellyB").Visible == true and find("MotifPorthole").Visible == false)
background.AbsoluteSize = rb.Vector2.new(828, 369)
check("landscape_phone_layout", fish.Visible == true and near(fish.MotifMascotScale.Scale, 0.75)
	and shopPage.Size.Y.Scale == 1 and shopPage.Size.Y.Offset == -192 and near(play.Position.Y.Scale, 0.5)
	and find("NavBar").Size.Y.Offset == 72 and near(find("MotifPlayHalo").Position.Y.Scale, 0.5))
check("nav_fits_phone", find("NavBar").Size.X.Scale == 1 and find("NavBar"):FindFirstChild("MotifMaxWidth") ~= nil
	and find("Nav_Quests").Size.X.Scale == 0.25)

-- Motion: loops exist, and pause while the menu is not shown.
local loops = looping(B.tweens)
check("ambient_loops_exist", #loops >= 3, #loops)
local paused = 0
for _, tween in ipairs(loops) do tween.Pause = function() paused += 1 end end
gui.Enabled = false
check("loops_pause_when_hidden", paused == #Skin.lastContext.loops and paused > 0, paused)
gui.Enabled = true

-- Idempotent apply, restore, re-apply.
local wrapped = Theme.button
check("apply_idempotent", Skin.apply(Theme) == true and Theme.button == wrapped)
check("apply_rejects_non_theme", Skin.apply({}) == false and Skin.apply(nil) == false)
local originalButton = Theme.skinOriginal.button
check("restore", Skin.restore(Theme) == true and Theme.button == originalButton and Theme.skin == nil
	and sameColor(Theme.colors.panel, rb.Color3.fromRGB(19, 35, 63)))
check("reapply", Skin.apply(Theme) == true and Theme.skin == Skin)

-- A second menu (respawn) is dressed on its own; the first is not dressed twice.
local secondGui = node("Folder", {Name = "PlayerGui2"})
local second = MainMenu.build(secondGui, handlersInto({play = 0, buy = {}, toggle = {}, navigate = {}}), STATE)
check("second_menu_dressed", second:FindFirstChild("MotifAngler", true) ~= nil and Skin.decorate(gui) == nil)

-- Section rollback: a failing section removes what it added and reports false.
local probe = node("Frame", {Name = "Probe"})
local keep = node("Frame", {Name = "Keep", Parent = probe})
local okSection = Skin.section(probe, "probe", function()
	local added = node("Frame", {Name = "MotifAdded", Parent = probe})
	node("Frame", {Name = "Inner", Parent = added})
	node("UICorner", {Parent = keep})
	error("boom")
end)
check("section_rolls_back", okSection == false and probe:FindFirstChild("MotifAdded") == nil
	and keep:FindFirstChildOfClass("UICorner") == nil and probe:FindFirstChild("Keep") == keep)

-- 2. Reduced motion ------------------------------------------------------------------------------
local R = boot({reducedMotion = true})
local rGui = R.require(R.client.MainMenu).build(R.playerGui, handlersInto({play = 0, buy = {}, toggle = {}, navigate = {}}), STATE)
check("reduced_motion_no_loops", #looping(R.tweens) == 0, #looping(R.tweens))
local still = true
for _, bubble in ipairs(rGui:FindFirstChild("MotifBubbles", true):GetChildren()) do
	if bubble.Position.Y.Scale >= 1 then still = false end
end
check("reduced_motion_bubbles_scattered", still)
check("reduced_motion_keeps_look", rGui:FindFirstChild("MotifAngler", true) ~= nil and rGui:FindFirstChild("MotifPlayHalo", true) ~= nil)

-- 3. Skin fails to load: the plain menu still builds and works ---------------------------------------
local F = boot({overrides = {DeepSeaSkin = function() error("skin exploded") end}})
local okMenu, FMenu = pcall(F.require, F.client.MainMenu)
check("fallback_menu_loads", okMenu and type(FMenu) == "table", FMenu)
local fCalls = {play = 0, buy = {}, toggle = {}, navigate = {}}
local okBuild, fGui = pcall(FMenu.build, F.playerGui, handlersInto(fCalls), STATE)
check("fallback_builds", okBuild and fGui ~= nil and fGui.Name == "MainMenu", fGui)
local missing = {}
for _, name in ipairs({"PlayButton", "CoinLabel", "Nav_Shop", "Nav_Inventory", "Nav_Quests", "Nav_Settings", "ShopPage",
	"InventoryPage", "QuestsPage", "SettingsPage", "Product_speed_coil", "Toggle_Music", "Toggle_SFX"}) do
	if not fGui:FindFirstChild(name, true) then table.insert(missing, name) end
end
check("fallback_contract_names", #missing == 0, table.concat(missing, ", "))
click(fGui:FindFirstChild("PlayButton", true))
check("fallback_play_works", fCalls.play == 1)
local motifLeft = 0
for _, object in ipairs(fGui:GetDescendants()) do if string.sub(object.Name, 1, 5) == "Motif" then motifLeft += 1 end end
check("fallback_plain_look", motifLeft == 0 and F.require(F.shared.UITheme).skin == nil, motifLeft)
check("fallback_warns", string.find(F.warnings[1] or "", "deep-sea skin unavailable", 1, true) ~= nil, F.warnings[1])

print(string.format("%s deep-sea skin: %d checks, %d failed", failures == 0 and "PASS" or "FAIL", count, failures))
process.exit(failures == 0 and 0 or 1)
