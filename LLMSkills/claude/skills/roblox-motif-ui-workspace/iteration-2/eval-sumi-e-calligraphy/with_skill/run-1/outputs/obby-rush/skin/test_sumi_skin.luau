--!nocheck
-- Tests of the Sumi & Washi skin (the menu contract itself is tests/test_main_menu.luau).
-- Run from the project folder:  lune run skin/test_sumi_skin.luau
-- Uses the project's own GUI mock (tests/mock.luau) and mounts src/ the same way the contract test does.
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
local function hex(c) return string.format("#%02X%02X%02X", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255)) end

-- 0. Every Luau file compiles --------------------------------------------------------------------------
local function walk(dir, out)
	for _, entry in ipairs(fs.readDir(dir)) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then walk(path, out) elseif string.match(entry, "%.luau$") then table.insert(out, path) end
	end
	return out
end
for _, path in ipairs(walk("src", {})) do
	local ok, err = pcall(luau.compile, fs.readFile(path))
	check("compiles " .. path, ok, err)
end

-- Harness -------------------------------------------------------------------------------------------------
-- options: reduced (bool), skipUi (mount without src/client/ui), viewport {w, h}
local function world(options)
	options = options or {}
	local game = node("DataModel", {Name = "Game"})
	local replicated = node("Folder", {Name = "ReplicatedStorage", Parent = game})
	local starterPlayer = node("Folder", {Name = "StarterPlayer", Parent = game})
	local starterScripts = node("Folder", {Name = "StarterPlayerScripts", Parent = starterPlayer})
	local playerGui = node("Folder", {Name = "PlayerGui"})
	local localPlayer = {Name = "Tester", UserId = 1, PlayerGui = playerGui}
	function localPlayer:WaitForChild(name) return name == "PlayerGui" and playerGui or nil end
	local tweenService = Mock.tweenService()
	local services = {
		ReplicatedStorage = replicated, StarterPlayer = starterPlayer, Players = {LocalPlayer = localPlayer},
		RunService = {Heartbeat = Mock.signal(), RenderStepped = Mock.signal()}, TweenService = tweenService,
		GuiService = {ReducedMotionEnabled = options.reduced == true},
		UserInputService = {TouchEnabled = false, InputBegan = Mock.signal(), InputEnded = Mock.signal()},
		TextService = {},
	}
	function game:GetService(name) return services[name] end
	local warnings, sources, cache = {}, {}, {}
	local requireModule
	local viewport = options.viewport or {1280, 720}
	local function envFor(script)
		local env = Mock.environment({services = services, require = function(target) return requireModule(target) end})
		env.game, env.script = game, script
		env.workspace = {CurrentCamera = {ViewportSize = rb.Vector2.new(viewport[1], viewport[2])}}
		env.warn = function(...) table.insert(warnings, table.concat({...}, " ")) end
		return env
	end
	function requireModule(target)
		if cache[target] ~= nil then return cache[target] end
		assert(sources[target], "unmounted module " .. tostring(target))
		local result = luau.load(fs.readFile(sources[target]), {debugName = sources[target], environment = envFor(target)})()
		cache[target] = result
		return result
	end
	local function mount(dir, parent)
		for _, entry in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. entry
			if fs.isDir(path) then
				if not (options.skipUi and entry == "ui") then mount(path, node("Folder", {Name = entry, Parent = parent})) end
			else
				local name, kind = string.match(entry, "^(.-)%.(%a+)%.luau$")
				if not name then name = string.match(entry, "^(.-)%.luau$") end
				if name then
					local class = kind == "client" and "LocalScript" or kind == "server" and "Script" or "ModuleScript"
					sources[node(class, {Name = name, Parent = parent})] = path
				end
			end
		end
	end
	mount("src/shared", node("Folder", {Name = "Shared", Parent = replicated}))
	mount("src/client", node("Folder", {Name = "Client", Parent = starterScripts}))
	local client = starterScripts:FindFirstChild("Client")
	local w = {playerGui = playerGui, tweens = tweenService.created, warnings = warnings, calls = {play = 0, buy = {}, toggle = {}}}
	w.MainMenu = requireModule(client:FindFirstChild("MainMenu"))
	w.Theme = requireModule(replicated:FindFirstChild("Shared"):FindFirstChild("UITheme"))
	local ui = client:FindFirstChild("ui")
	w.Skin = ui and requireModule(ui:FindFirstChild("SumiSkin"))
	w.gui = w.MainMenu.build(playerGui, {
		play = function() w.calls.play += 1 end,
		buy = function(id) table.insert(w.calls.buy, id) end,
		toggle = function(id, on) table.insert(w.calls.toggle, {id, on}) end,
	}, {
		coins = 1250,
		products = {{id = "speed_coil", name = "スピードコイル", price = 300}, {id = "rainbow_trail", name = "虹のトレイル", price = 450}},
		settings = {music = true, sfx = true},
	})
	return w
end

local function find(gui, name) return gui:FindFirstChild(name, true) end
local function fire(button, signal, kind)
	button[signal]:Fire({UserInputType = kind or rb.Enum.UserInputType.MouseButton1, UserInputState = rb.Enum.UserInputState.Begin})
end

-- Palette discipline: the only colours on screen are ink tones, washi tones and the seal vermilion.
local function classify(c)
	local maxc, minc = math.max(c.R, c.G, c.B), math.min(c.R, c.G, c.B)
	local chroma = maxc - minc
	local hue = 0
	if chroma > 0 then
		if maxc == c.R then hue = 60 * (((c.G - c.B) / chroma) % 6)
		elseif maxc == c.G then hue = 60 * ((c.B - c.R) / chroma + 2)
		else hue = 60 * ((c.R - c.G) / chroma + 4) end
	end
	if chroma < 0.15 and (chroma < 0.03 or (hue >= 15 and hue <= 60)) then return "sumi-washi" end
	if chroma > 0.35 and (hue <= 15 or hue >= 350) and c.R > 0.45 then return "shu" end
	return "other"
end

local function visibleIn(object, root)
	local current = object
	while current and current ~= root.Parent do
		if current.Visible == false then return false end
		current = current.Parent
	end
	return true
end

-- Every painted colour under `root`: {object, colour, what}
local function paints(root)
	local list = {}
	for _, object in ipairs(root:GetDescendants()) do
		local class = object.ClassName
		if (class == "Frame" or class == "TextLabel" or class == "TextButton" or class == "ScrollingFrame") and visibleIn(object, root) then
			if (object.BackgroundTransparency or 0) < 1 and object.BackgroundColor3 then
				table.insert(list, {object, object.BackgroundColor3, "fill"})
			end
			if (class == "TextLabel" or class == "TextButton") and object.Text ~= "" and (object.TextTransparency or 0) < 1 then
				table.insert(list, {object, object.TextColor3, "text"})
			end
		elseif class == "UIStroke" and object.Enabled ~= false and (object.Transparency or 0) < 1 and visibleIn(object.Parent, root) then
			table.insert(list, {object, object.Color, "stroke"})
		end
	end
	return list
end

-- 1. Build, palette and the single seal -------------------------------------------------------------------
local w = world()
local gui, P = w.gui, w.Skin and w.Skin.kit.P
check("skin_loaded_without_warnings", w.Skin ~= nil and #w.warnings == 0, table.concat(w.warnings, " | "))
check("theme_marked_skinned", w.Theme.skin == w.Skin)
local background = gui.Background
check("washi_background_opaque", background.BackgroundColor3 == P.paper and background.BackgroundTransparency == 0)
check("zindex_sibling", gui.ZIndexBehavior == rb.Enum.ZIndexBehavior.Sibling)

local others, shu = {}, {}
for _, entry in ipairs(paints(background)) do
	local kind = classify(entry[2])
	if kind == "other" then table.insert(others, entry[1]:GetFullName() .. " " .. entry[3] .. " " .. hex(entry[2])) end
	if kind == "shu" and entry[3] == "fill" then table.insert(shu, entry[1].Name) end
end
check("home_only_ink_washi_and_shu", #others == 0, table.concat(others, ", "))
check("home_exactly_one_vermilion_seal", #shu == 1 and shu[1] == "PlayButton", table.concat(shu, ","))
check("no_navy_left", classify(w.Theme.colors.accent) ~= "other" and classify(w.Theme.colors.panel) ~= "other")

for _, name in ipairs({"ShopPage", "SettingsPage", "InventoryPage", "QuestsPage"}) do
	w.MainMenu.open(gui, string.gsub(name, "Page$", ""))
	local page = gui[name]
	local pageOthers, pageShu = {}, {}
	for _, entry in ipairs(paints(page)) do
		local kind = classify(entry[2])
		if kind == "other" then table.insert(pageOthers, entry[1].Name .. " " .. hex(entry[2])) end
		if kind == "shu" and entry[3] == "fill" then table.insert(pageShu, entry[1].Name) end
	end
	check(name .. "_only_ink_washi_and_shu", #pageOthers == 0, table.concat(pageOthers, ", "))
	check(name .. "_one_seal", #pageShu == 1 and pageShu[1] == "MotifPageSeal", table.concat(pageShu, ","))
	check(name .. "_is_a_hanging_scroll", page:FindFirstChild("MotifMounting") ~= nil and page.MotifMounting:FindFirstChild("Jiku") ~= nil)
end
gui.QuestsPage.CloseButton.Activated:Fire()

-- 2. Contract: the skin adds no buttons and keeps names ---------------------------------------------------
local expected = {PlayButton = true, Nav_Shop = true, Nav_Inventory = true, Nav_Quests = true, Nav_Settings = true,
	CloseButton = true, BuyButton = true, Toggle_Music = true, Toggle_SFX = true}
local strays = {}
for _, object in ipairs(gui:GetDescendants()) do
	if object:IsA("GuiButton") and not expected[object.Name] then table.insert(strays, object.Name) end
	if object:IsA("GuiObject") and string.sub(object.Name, 1, 5) == "Motif" and object:IsA("GuiButton") then table.insert(strays, object.Name) end
end
check("skin_adds_no_buttons", #strays == 0, table.concat(strays, ","))
check("topbar_below_roblox_buttons", background.TopBar.Position.Y.Offset >= 58 + 8)

-- 3. Coin: the Unicode-13 emoji becomes an ink coin, also on later updates ---------------------------------
local coins = find(gui, "CoinLabel")
check("coin_emoji_removed", coins.Text == "1250" and coins:FindFirstChild("MotifCoin") ~= nil, coins.Text)
coins.Text = "\240\159\170\153 2000"
check("coin_emoji_removed_on_update", coins.Text == "2000", coins.Text)
local price = find(gui, "Price")
check("price_coin_inside_padding", price.Text == "300" and price.MotifCoin.Position.X.Offset == -price.MotifPadding.PaddingLeft.Offset)

-- 4. States ---------------------------------------------------------------------------------------------------
local play = background.PlayButton
check("seal_face_and_text", play.BackgroundColor3 == P.primary and play.TextColor3 == P.white and play:FindFirstChild("MotifSealLine") ~= nil)
play.MouseEnter:Fire()
check("seal_hover_deepens_not_theme", play.BackgroundColor3 == P.primary:Lerp(P.ink, 0.1), hex(play.BackgroundColor3))
fire(play, "InputBegan")
check("seal_press_sinks", near(play.MotifScale.Scale, 0.97) and play.BackgroundColor3 == P.primary:Lerp(P.ink, 0.22))
fire(play, "InputEnded")
play.Activated:Fire()
check("seal_release_and_callback", near(play.MotifScale.Scale, 1) and w.calls.play == 1)
play.MouseLeave:Fire()
play.Active = false
check("seal_disabled_greys", play.BackgroundColor3 == P.disabled and play.TextColor3 == P.muted)
play.Active = true
check("seal_reenabled", play.BackgroundColor3 == P.primary)

local buy = find(gui, "BuyButton")
check("buy_is_ink_stamp", buy.BackgroundColor3 == P.ink and buy.TextColor3 == P.white and buy:FindFirstChild("MotifSealWear") ~= nil)
local close = gui.ShopPage.CloseButton
check("close_is_brush_not_box", close.BackgroundTransparency == 1 and close:FindFirstChild("MotifBrush") ~= nil
	and close:FindFirstChild("MotifEdge") == nil)
buy.MouseEnter:Fire() -- the theme's own hover handler also runs and would paint its accent
check("buy_hover_stays_ink", buy.BackgroundColor3 == P.ink:Lerp(P.paper, 0.2), hex(buy.BackgroundColor3))
buy.MouseLeave:Fire()

local navShop = find(gui, "Nav_Shop")
local hair = navShop.MotifBrush.Hair1
local idle = hair.BackgroundTransparency
navShop.Activated:Fire()
check("nav_selected_brush_full", hair.BackgroundTransparency < idle and near(hair.BackgroundTransparency, 0))
check("veil_behind_open_scroll", gui.MotifVeil.Visible == true and gui.ShopPage.Visible == true)
local moon = background.MotifScenery.MotifEnso
check("moon_steps_behind_scroll", moon.Visible == false)
gui.ShopPage.CloseButton.Activated:Fire()
check("veil_gone_when_closed", gui.MotifVeil.Visible == false and near(hair.BackgroundTransparency, idle) and moon.Visible == true)

local music = find(gui, "Toggle_Music")
local mark = music.MotifToggleMark.Body.Ink
local dot = music.MotifToggleMark.Dot
check("toggle_on_is_dark_circle_with_dot", mark.Color == P.ink and dot.Visible == true)
music.Activated:Fire()
check("toggle_off_pale_empty_circle", mark.Color == P.usuzumi and dot.Visible == false
	and string.find(music.Text, "OFF", 1, true) ~= nil and w.calls.toggle[1][2] == false)
local lift = mark:FindFirstChild("Lift")
check("toggle_circle_has_no_gap", lift ~= nil and #lift.Transparency.Keypoints == 2
	and lift.Transparency.Keypoints[1].Value == lift.Transparency.Keypoints[2].Value)

-- 5. Type: Japanese at Bold or heavier, the Latin display face only on Latin -------------------------------
local thin = {}
for _, object in ipairs(gui:GetDescendants()) do
	if (object.ClassName == "TextLabel" or object.ClassName == "TextButton") and w.Skin.kit.cjk and w.Skin.kit.cjk(object.Text) then
		local face = object.FontFace
		local weight = face and face.Weight and face.Weight.Name
		if not face or not (weight == "Bold" or weight == "ExtraBold" or weight == "Heavy") then table.insert(thin, object.Name) end
		if face and string.find(face.Family, "AccanthisADFStd", 1, true) then table.insert(thin, object.Name .. "(display)") end
	end
end
check("japanese_bold_or_heavier", #thin == 0, table.concat(thin, ","))
check("title_latin_display_face", string.find(background.TopBar.Title.FontFace.Family, "AccanthisADFStd", 1, true) ~= nil)

-- 6. Motion -----------------------------------------------------------------------------------------------------
local loops = 0
for _, tween in ipairs(w.tweens) do if tween.info[4] == -1 then loops += 1 end end
check("one_idle_loop", loops == 1, loops)
local calm = world({reduced = true})
local calmLoops = 0
for _, tween in ipairs(calm.tweens) do if tween.info[4] == -1 then calmLoops += 1 end end
local calmPlay = calm.gui.Background.PlayButton
check("reduced_motion_no_loops_no_tweens", calmLoops == 0 and #calm.tweens == 0, #calm.tweens)
check("reduced_motion_seal_final_state", calmPlay.BackgroundTransparency == 0 and near(calmPlay.MotifScale.Scale, 1))

-- 7. Robustness ---------------------------------------------------------------------------------------------------
local themeButton = w.Theme.button
check("apply_idempotent", w.Skin.apply(w.Theme) == true and w.Theme.button == themeButton)
check("apply_rejects_non_theme", w.Skin.apply({}) == false)
local phone = world({viewport = {828, 369}})
check("landscape_phone_hides_inscription", phone.gui.Background.MotifScenery.MotifInscription.Visible == false)
check("desktop_shows_inscription", background.MotifScenery.MotifInscription.Visible == true)
local plain = world({skipUi = true})
check("menu_builds_without_skin", plain.Skin == nil and plain.gui:FindFirstChild("PlayButton", true) ~= nil
	and plain.gui:FindFirstChild("MotifVeil") == nil)

print(string.format("%s sumi skin: %d checks, %d failed", failures == 0 and "PASS" or "FAIL", count, failures))
process.exit(failures == 0 and 0 or 1)
