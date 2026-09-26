--!nocheck
-- Lune test of the night-harbour skin. Run from the project folder:  lune run checks/test_harbor_skin.luau
-- Complements tests/test_main_menu.luau (the name contract, untouched): this one checks that the skin
-- is really applied (not silently falling back), the colour roles, contrast, fonts, states, reduced
-- motion, loop pausing, the fallback path and the no-skin path. Uses tests/mock.luau read-only.
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
	return a and b and math.abs(a.R - b.R) < 2 / 255 and math.abs(a.G - b.G) < 2 / 255 and math.abs(a.B - b.B) < 2 / 255
end
local function rgb(r, g, b) return rb.Color3.fromRGB(r, g, b) end
local function contrast(a, b)
	local function ch(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
	local function rel(c) return 0.2126 * ch(c.R) + 0.7152 * ch(c.G) + 0.0722 * ch(c.B) end
	local la, lb = rel(a), rel(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end

-- A fresh mock DataModel with src/ mounted like default.project.json (same as the contract test).
-- options: reducedMotion, skip = {folderName = true}, override = {moduleName = table}
local function world(options)
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
		if options.override and options.override[target.Name] then
			cache[target] = options.override[target.Name]
			return cache[target]
		end
		local path = sources[target]
		assert(path, "require of a module that is not mounted from src/: " .. tostring(target))
		local result = luau.load(fs.readFile(path), {debugName = path, environment = envFor(target)})()
		cache[target] = result
		return result
	end
	local function mount(dir, parent)
		for _, entry in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. entry
			if fs.isDir(path) then
				if not (options.skip and options.skip[entry]) then
					mount(path, node("Folder", {Name = entry, Parent = parent}))
				end
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
	mount("src/client", node("Folder", {Name = "Client", Parent = starterScripts}))
	return {
		require = requireModule, services = services, tweens = tweenService.created, playerGui = playerGui,
		mainMenu = function() return requireModule(starterScripts.Client:FindFirstChild("MainMenu")) end,
		shared = function(name) return requireModule(replicated.Shared:FindFirstChild(name, true)) end,
	}
end

local function state()
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
local calls = {play = 0, buy = {}, toggle = {}}
local handlers = {
	play = function() calls.play += 1 end,
	buy = function(id) table.insert(calls.buy, id) end,
	toggle = function(id, on) table.insert(calls.toggle, {id, on}) end,
	navigate = function() end,
}
local mouse = {UserInputType = rb.Enum.UserInputType.MouseButton1}

-- Build the dressed menu ------------------------------------------------------------------------
local W = world()
local MainMenu = W.mainMenu()
local okBuild, gui = pcall(MainMenu.build, W.playerGui, handlers, state())
check("build_succeeds", okBuild and gui ~= nil, gui)
if not okBuild then process.exit(1) end
local Skin = W.shared("HarborSkin")
local P = Skin.P
local function find(name) return gui:FindFirstChild(name, true) end

check("skin_really_applied_not_fallback", gui:GetAttribute("Skin") == "NightHarbour" and find("HarborScene") ~= nil and find("HarborCloth") ~= nil)
check("theme_wrapped_once", W.shared("UITheme").skin == Skin)

-- Name contract beyond the test's list
local pages = {"ShopPage", "SettingsPage", "InventoryPage", "QuestsPage"}
for _, name in ipairs(pages) do
	local page = find(name)
	check("page_keeps_title_and_close_" .. name, page and page:FindFirstChild("Title") and page:FindFirstChild("CloseButton") and page.Parent == gui)
end
for _, id in ipairs({"speed_coil", "rainbow_trail", "double_jump"}) do
	local row = find("Product_" .. id)
	check("row_keeps_parts_" .. id, row and row.Parent and row.Parent.Name == "ProductList" and row:FindFirstChild("ProductName")
		and row:FindFirstChild("Price") and row:FindFirstChild("BuyButton"))
end
check("topbar_keeps_title_and_coins", find("TopBar"):FindFirstChild("Title") and find("TopBar"):FindFirstChild("CoinLabel"))

-- Only the original 14 buttons exist; every decoration is inert
local buttons, activeDecor = 0, {}
for _, object in ipairs(gui:GetDescendants()) do
	if object:IsA("GuiButton") then buttons += 1 end
	if string.sub(object.Name, 1, 6) == "Harbor" and object.Name ~= "HarborScrim" and object:IsA("GuiObject") and object.Active ~= false then
		table.insert(activeDecor, object.Name)
	end
end
check("no_extra_buttons", buttons == 14, buttons)
check("decorations_never_eat_clicks", #activeDecor == 0, table.concat(activeDecor, ","))

-- Colours: none of the old dashboard palette survives, no translucent hairlines
local OLD = {rgb(11, 20, 38), rgb(19, 35, 63), rgb(28, 50, 86), rgb(63, 169, 245), rgb(140, 160, 190)}
local stale, hairlines = {}, {}
for _, object in ipairs(gui:GetDescendants()) do
	for _, key in ipairs({"BackgroundColor3", "TextColor3", "Color"}) do
		local ok, value = pcall(function() return object[key] end)
		if ok and typeof(value) == "Color3" and object.ClassName ~= "UIGradient" then
			for _, old in ipairs(OLD) do
				if sameColor(value, old) then table.insert(stale, object:GetFullName() .. "." .. key) end
			end
		end
	end
	if object.ClassName == "UIStroke" and object.Transparency and object.Transparency > 0.05 and object.Transparency < 0.95 then
		table.insert(hairlines, object.Parent and object.Parent.Name or "?")
	end
end
check("no_old_dashboard_colours", #stale == 0, table.concat(stale, ", "))
check("no_translucent_hairlines", #hairlines == 0, table.concat(hairlines, ", "))

-- Roles
local play = find("PlayButton")
check("cta_is_signal_red_flag", sameColor(play.BackgroundColor3, P.primary) and play.Text == "出航" and play.HarborCloth.HarborHoistTape ~= nil)
check("cta_type_is_white_on_red", sameColor(play.TextColor3, P.white) and contrast(play.TextColor3, play.BackgroundColor3) >= 4.5)
check("cta_biggest_button", play.Size.X.Offset >= 280 and play.Size.Y.Offset >= 80)
local navShop = find("Nav_Shop")
check("nav_is_canvas_flag_card", sameColor(navShop.BackgroundColor3, P.canvas) and sameColor(navShop.TextColor3, P.onLight) and navShop:FindFirstChild("HarborFlag") ~= nil)
check("dressing_line_beside_navbar", find("HarborDressLine") ~= nil and find("HarborDressLine").Parent.Name == "Background")
check("navbar_has_only_buttons_and_layout", (function()
	for _, child in ipairs(find("NavBar"):GetChildren()) do
		if not (child:IsA("GuiButton") or child.ClassName == "UIListLayout") then return false end
	end
	return true
end)())
local music = find("Toggle_Music")
check("toggle_is_quiet_navy_with_piping", sameColor(music.BackgroundColor3, P.quiet) and sameColor(music.MotifEdge.Color, P.canvas) and music.MotifEdge.Transparency == 0)
local buy = find("Product_speed_coil").BuyButton
check("buy_is_primary", sameColor(buy.BackgroundColor3, P.primary))
check("rows_are_canvas_tags", sameColor(find("Product_speed_coil").BackgroundColor3, P.canvas) and find("Product_speed_coil"):FindFirstChild("HarborEyelet") ~= nil)
check("pages_opaque_serge_with_collar", find("ShopPage").BackgroundTransparency == 0 and sameColor(find("ShopPage").BackgroundColor3, P.paper)
	and find("ShopPage"):FindFirstChild("HarborCollar3") ~= nil and find("ShopPage"):FindFirstChild("HarborNeckerchief") ~= nil)
check("coins_formatted_behind_porthole", find("CoinLabel").Text == "1,250" and find("HarborPorthole") ~= nil)
check("prices_formatted", find("Product_double_jump").Price.Text == "800")
find("CoinLabel").Text = "🪙 1300"
check("coin_text_tidied_when_rewritten", find("CoinLabel").Text == "1,300")

-- Emoji Roblox cannot draw (Unicode 13+: U+1FA70..U+1FAFF) never appear
local tofu = {}
for _, object in ipairs(gui:GetDescendants()) do
	local text = object.Text
	if type(text) == "string" and string.find(text, "\240\159[\169\170\171]") then table.insert(tofu, object.Name .. "=" .. text) end
end
check("no_tofu_emoji", #tofu == 0, table.concat(tofu, ", "))

-- Contrast: text against the nearest opaque surface (sky counts as the night colour)
local function surface(object)
	local nodeAt = object
	while nodeAt and nodeAt ~= gui do
		if nodeAt:IsA("GuiObject") and (nodeAt.BackgroundTransparency or 1) < 0.5 then
			if nodeAt.Name == "Background" then return P.night end
			return nodeAt.BackgroundColor3
		end
		nodeAt = nodeAt.Parent
	end
	return P.night
end
local lowContrast = {}
for _, object in ipairs(gui:GetDescendants()) do
	if (object.ClassName == "TextLabel" or object.ClassName == "TextButton") and object.Text ~= "" then
		local ratio = contrast(object.TextColor3, surface(object))
		local need = (object.TextSize or 14) >= 24 and 3 or 4.5
		if ratio < need then table.insert(lowContrast, string.format("%s %.1f", object.Name, ratio)) end
	end
end
check("text_contrast", #lowContrast == 0, table.concat(lowContrast, ", "))

-- Fonts: spec families only, Bold or heavier (Japanese falls back at the requested weight)
local badFonts = {}
for _, object in ipairs(gui:GetDescendants()) do
	if (object.ClassName == "TextLabel" or object.ClassName == "TextButton") and object.Text ~= "" then
		local face = object.FontFace
		local family = face and face.Family or ""
		local weight = face and tostring(face.Weight) or ""
		if not (string.find(family, "Oswald", 1, true) or string.find(family, "Montserrat", 1, true))
			or not (string.find(weight, "Bold", 1, true) or string.find(weight, "Heavy", 1, true)) then
			table.insert(badFonts, object.Name .. " " .. family .. " " .. weight)
		end
	end
end
check("fonts_from_spec_bold", #badFonts == 0, table.concat(badFonts, ", "))

-- Top bar: the TopBar sits below Roblox's 58 px bar; the background stays full-bleed
check("topbar_clears_roblox_bar", find("TopBar").Position.Y.Offset >= 58 and gui.IgnoreGuiInset == true)

-- States: hover (theme handler + skin), press, disabled
play.MouseEnter:Fire()
check("hover_brass_edge_and_skin_face", sameColor(play.MotifEdge.Color, P.brass) and sameColor(play.BackgroundColor3, P.primary:Lerp(P.white, 0.06)))
play.MouseLeave:Fire()
check("leave_restores", sameColor(play.MotifEdge.Color, P.primary:Lerp(P.outline, 0.35)) and sameColor(play.BackgroundColor3, P.primary))
play.InputBegan:Fire(mouse)
check("press_darkens_cloth", sameColor(play.BackgroundColor3, P.primary:Lerp(P.outline, 0.2)))
play.InputEnded:Fire(mouse)
check("release_restores", sameColor(play.BackgroundColor3, P.primary))
play.Activated:Fire(mouse, 1)
check("play_still_calls_handler", calls.play == 1)
buy.Active = false
check("disabled_greys", sameColor(buy.BackgroundColor3, P.disabled) and sameColor(buy.TextColor3, P.muted))
buy.Active = true
check("enabled_again", sameColor(buy.BackgroundColor3, P.primary))

-- Navigation: the open page's flag gets a red edge; the harbour dims behind the page
MainMenu.open(gui, "Shop")
check("open_page_marks_its_flag", sameColor(navShop.MotifEdge.Color, P.primary) and navShop.MotifEdge.Thickness == 3
	and not sameColor(find("Nav_Settings").MotifEdge.Color, P.primary))
check("scrim_shows_with_page", find("HarborScrim").Visible == true and find("HarborScrim").ZIndex < find("ShopPage").ZIndex)
find("ShopPage").CloseButton.Activated:Fire(mouse, 1)
check("scrim_hides_on_close", find("HarborScrim").Visible == false and not sameColor(navShop.MotifEdge.Color, P.primary))

-- Settings lamp follows the toggle
local lampGlass = music.HarborLampLayer.HarborLamp.Cage.Glass
check("lamp_lit_when_on", sameColor(lampGlass.BackgroundColor3, P.lamp))
music.Activated:Fire(mouse, 1)
check("lamp_dark_when_off", string.find(music.Text, "OFF", 1, true) ~= nil and sameColor(lampGlass.BackgroundColor3, P.disabled)
	and music.HarborLampLayer.HarborLamp.Glow.Visible == false and calls.toggle[1][2] == false)

-- Motion: exactly two slow loops; they pause when the menu is disabled
local loops = {}
for _, tween in ipairs(W.tweens) do
	if tween.info and tween.info[4] == -1 then table.insert(loops, tween) end
end
check("two_slow_loops", #loops == 2 and loops[1].info[1] >= 3 and loops[2].info[1] >= 3, #loops)
for _, tween in ipairs(loops) do
	tween.Pause = function(self) self.pausedByTest = true end
end
gui.Enabled = false
check("loops_pause_when_hidden", loops[1] and loops[1].pausedByTest and loops[2] and loops[2].pausedByTest)

-- Idempotent across rebuilds
local second = node("Folder", {Name = "PlayerGui2"})
local okAgain, gui2 = pcall(MainMenu.build, second, handlers, state())
check("second_build_dressed_again", okAgain and gui2:GetAttribute("Skin") == "NightHarbour" and W.shared("UITheme").skin == Skin)

-- Reduced motion: no loops at all
local calm = world({reducedMotion = true})
local okCalm = pcall(calm.mainMenu().build, calm.playerGui, handlers, state())
local calmLoops = 0
for _, tween in ipairs(calm.tweens) do
	if tween.info and tween.info[4] == -1 then calmLoops += 1 end
end
check("reduced_motion_no_loops", okCalm and calmLoops == 0, calmLoops)

-- Fallback: a dressing error still yields the full menu, plain, with nothing half-dressed left over
local broken = world({override = {HarborMenu = {dress = function(refs)
	refs.background:SetAttribute("halfDressed", true)
	error("boom")
end}}})
local okBroken, plainGui = pcall(broken.mainMenu().build, broken.playerGui, handlers, state())
local leftovers = 0
for _, child in ipairs(broken.playerGui:GetChildren()) do
	if child.Name == "MainMenu" then leftovers += 1 end
end
check("fallback_builds_plain_menu", okBroken and plainGui and plainGui:FindFirstChild("PlayButton", true) ~= nil
	and plainGui:FindFirstChild("Nav_Shop", true) ~= nil and plainGui:GetAttribute("Skin") == nil and leftovers == 1
	and plainGui.Background:GetAttribute("halfDressed") == nil)

-- No skin folder at all (e.g. a Place without ReplicatedStorage.Shared.Harbor): the stock menu builds
local bare = world({skip = {Harbor = true}})
local okBare, bareGui = pcall(bare.mainMenu().build, bare.playerGui, handlers, state())
check("builds_without_skin_folder", okBare and bareGui and bareGui:FindFirstChild("PlayButton", true) ~= nil and bareGui:GetAttribute("Skin") == nil)

print(string.format("%s harbour skin: %d checks, %d failed", failures == 0 and "PASS" or "FAIL", count, failures))
process.exit(failures == 0 and 0 or 1)
