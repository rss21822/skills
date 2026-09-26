--!nocheck
-- Ennichi skin test. Run from the project folder:  lune run tests/test_ennichi_skin.luau
-- The contract test (test_main_menu.luau) pins names and behaviour; this one checks the look actually
-- applies (the skin is pcall-guarded, so a broken skin would otherwise fail silently), that it keeps
-- the contract, and that it falls back cleanly.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local Harness = luau.load(fs.readFile("tests/ennichi_harness.luau"), {debugName = "ennichi_harness"})()
local rb = Harness.rb

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
local function same(a, b) return a ~= nil and b ~= nil and near(a.R, b.R) and near(a.G, b.G) and near(a.B, b.B) end
local function click(button)
	button.InputBegan:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
	button.InputEnded:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
	button.Activated:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1}, 1)
end

local OLD = { -- the plain theme's navy dashboard colours
	rb.Color3.fromRGB(11, 20, 38), rb.Color3.fromRGB(19, 35, 63), rb.Color3.fromRGB(28, 50, 86), rb.Color3.fromRGB(63, 169, 245),
}

-- 1. Skin applies and the scene dresses the menu ------------------------------------------------------
local world = Harness.world({deferNow = true})
local Theme = world.require(world.shared:FindFirstChild("UITheme"))
local MainMenu = world.module("MainMenu")
local Skin = world.module("Ennichi.EnnichiSkin")
local P, kit = Skin.P, Skin.kit
local calls = {}
local gui = MainMenu.build(world.playerGui, Harness.handlers(calls), Harness.state)
Harness.layout(gui, 1280, 720)

check("skin_applied_to_theme", Theme.skin == Skin)
check("no_scene_warning", #world.warnings == 0, world.warnings[1])
local wrapped = Theme.button
check("apply_is_idempotent", Skin.apply(Theme) == true and Theme.button == wrapped)
check("apply_ignores_non_theme", Skin.apply({}) == false and Skin.apply(nil) == false)
local navyLeft = {}
for key, value in pairs(Theme.colors) do
	for _, old in ipairs(OLD) do if same(value, old) then table.insert(navyLeft, key) end end
end
check("theme_colours_rewritten_in_place", #navyLeft == 0 and same(Theme.colors.text, P.ink) and same(Theme.colors.accent, P.primary),
	table.concat(navyLeft, ","))

local function find(name) return gui:FindFirstChild(name, true) end
local background = gui:FindFirstChild("Background")
for _, name in ipairs({"MotifSky", "MotifStars", "MotifLanternString", "MotifStall", "MotifPlayGlow", "MotifStallGoods"}) do
	check("scene_" .. name, background:FindFirstChild(name) ~= nil)
end
check("zindex_behaviour_sibling", gui.ZIndexBehavior == rb.Enum.ZIndexBehavior.Sibling)
check("scene_scrim_under_tiles", background:FindFirstChild("MotifScrim") ~= nil
	and background.MotifScrim.ZIndex < background.NavBar.ZIndex and background.MotifScrim.ZIndex > background.PlayButton.ZIndex)

-- 2. Contract kept: names, parents and direct-child relations other scripts may rely on -------------------
local top = background:FindFirstChild("TopBar")
check("contract_topbar_children", top and top:FindFirstChild("Title") and top:FindFirstChild("CoinLabel") and top.CoinLabel.Parent == top)
check("contract_play_parent", background:FindFirstChild("PlayButton") ~= nil and background.PlayButton:IsA("GuiButton"))
local nav = background:FindFirstChild("NavBar")
for _, id in ipairs({"Shop", "Inventory", "Quests", "Settings"}) do
	local tile = nav and nav:FindFirstChild("Nav_" .. id)
	local page = gui:FindFirstChild(id .. "Page")
	check("contract_nav_" .. id, tile ~= nil and tile.Parent == nav)
	check("contract_page_" .. id, page ~= nil and page.Parent == gui and page:FindFirstChild("Title") and page:FindFirstChild("CloseButton"))
end
local list = gui.ShopPage:FindFirstChild("ProductList")
for _, product in ipairs(Harness.state.products) do
	local row = list and list:FindFirstChild("Product_" .. product.id)
	check("contract_row_" .. product.id, row and row:FindFirstChild("ProductName") and row:FindFirstChild("Price") and row:FindFirstChild("BuyButton"))
end
check("contract_toggles", gui.SettingsPage:FindFirstChild("Toggle_Music") and gui.SettingsPage:FindFirstChild("Toggle_SFX"))
check("nav_children_are_tiles_only", (function()
	for _, child in ipairs(nav:GetChildren()) do
		if child:IsA("GuiObject") and string.sub(child.Name, 1, 4) ~= "Nav_" then return false end
	end
	return true
end)())
check("coin_text_has_no_unicode13_coin", not string.find(top.CoinLabel.Text, "🪙", 1, true) and string.find(top.CoinLabel.Text, "1,250", 1, true) ~= nil,
	top.CoinLabel.Text)

-- 3. Look: faces, type colours, edges -------------------------------------------------------------------
local play = background.PlayButton
check("play_is_the_lantern", same(play.BackgroundColor3, P.primary) and play:FindFirstChild("MotifCapTop") and play:FindFirstChild("MotifCord"))
check("play_text_white_with_ink_outline", same(play.TextColor3, P.white) and play.MotifTextOutline.Transparency == 0)
local expected = {Shop = "ringoame", Inventory = "kingyo", Quests = "wakaba", Settings = "ramune"}
for id, candy in pairs(expected) do
	local tile = nav["Nav_" .. id]
	check("tile_face_" .. id, same(tile.BackgroundColor3, kit.candies[candy]) and tile:FindFirstChild("MotifAwning") and tile:FindFirstChild("MotifTileIcon"))
	check("tile_touch_" .. id, tile.Size.X.Offset >= 48 and tile.Size.Y.Offset >= 48)
end
check("tile_text_outlined_white", same(nav.Nav_Shop.TextColor3, P.white) and nav.Nav_Shop.MotifTextOutline.Transparency == 0)
local buy = list.Product_speed_coil.BuyButton
check("buy_is_kingyo", same(buy.BackgroundColor3, kit.candies.kingyo))
local close = gui.ShopPage.CloseButton
check("close_is_paper_with_ink", same(close.BackgroundColor3, P.panel) and same(close.TextColor3, P.ink))
check("rows_are_pastel", same(list.Product_speed_coil.BackgroundColor3, kit.pastels[1]) and same(list.Product_rainbow_trail.BackgroundColor3, kit.pastels[2]))
check("page_has_noren_and_badge", gui.ShopPage:FindFirstChild("MotifNoren") and gui.ShopPage:FindFirstChild("MotifPageBadge"))
local thinBlue, oldFill = {}, {}
for _, object in ipairs(gui:GetDescendants()) do
	if object.ClassName == "UIStroke" and (object.Thickness or 0) < 2 and object.Transparency ~= 1 and object.Parent.ClassName ~= "TextLabel" then
		table.insert(thinBlue, object.Parent.Name)
	end
	if object:IsA("GuiObject") and object.BackgroundTransparency ~= nil and object.BackgroundTransparency < 1 then
		for _, old in ipairs(OLD) do
			if same(object.BackgroundColor3, old) then table.insert(oldFill, object.Name) end
		end
	end
end
check("no_thin_translucent_edges", #thinBlue == 0, table.concat(thinBlue, ","))
check("no_navy_fills_left", #oldFill == 0, table.concat(oldFill, ","))
for _, name in ipairs({"Toggle_Music", "Toggle_SFX"}) do
	local toggle = gui.SettingsPage[name]
	check("ink_text_on_pastel_" .. name, same(toggle.TextColor3, P.ink) and kit.luminance(toggle.BackgroundColor3) > 0.65)
end

-- 4. Behaviour of the dressing ---------------------------------------------------------------------------
local scrim = gui:FindFirstChild("MotifScrim", true) or {Visible = "missing"}
local function lit(id)
	local dot = nav["Nav_" .. id]:FindFirstChild("MotifLit")
	return dot and dot.Visible
end
check("pages_closed_scrim_hidden", scrim.Visible == false)
click(nav.Nav_Shop)
check("open_page_shows_scrim_and_lit_tile", scrim.Visible == true and lit("Shop") == true and lit("Settings") == false
	and calls.navigate[1] == "Shop")
local tile = nav.Nav_Inventory
tile.MouseEnter:Fire()
check("hover_keeps_stall_colour", same(tile.BackgroundColor3, kit.candies.kingyo), tile.BackgroundColor3)
tile.MouseLeave:Fire()
check("leave_keeps_stall_colour", same(tile.BackgroundColor3, kit.candies.kingyo), tile.BackgroundColor3)
tile.InputBegan:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
check("press_sinks_lip", near(tile.MotifLip.Offset.Y, 0.05) and near(tile.MotifScale.Scale, 0.94))
tile.InputEnded:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
check("release_restores", near(tile.MotifLip.Offset.Y, 0) and near(tile.MotifScale.Scale, 1))
click(nav.Nav_Settings)
local music = gui.SettingsPage.Toggle_Music
local switch = music:FindFirstChild("MotifSwitch")
check("switch_on_initially", switch and same(switch.BackgroundColor3, P.success) and switch.Knob.Position.X.Scale == 1)
click(music)
check("switch_follows_toggle_off", switch and string.find(music.Text, "OFF", 1, true) and same(switch.BackgroundColor3, P.disabled)
	and switch.Knob.Position.X.Scale == 0 and calls.toggle[1][2] == false)
click(gui.SettingsPage.CloseButton)
check("close_hides_scrim", scrim.Visible == false and gui.SettingsPage.Visible == false)
click(play)
check("play_still_calls_handler", calls.play == 1)

-- 5. Responsive placement ----------------------------------------------------------------------------------
local function cta(gui)
	local b = gui.Background
	local centerY = b.PlayButton.Position.Y.Offset
	local half = b.PlayButton.Size.Y.Offset / 2
	return centerY - half, centerY + half
end
for _, size in ipairs({{1280, 720}, {1080, 720}, {828, 369}, {366, 820}}) do
	local w, h = size[1], size[2]
	Harness.layout(gui, w, h)
	local b = gui.Background
	local topY, bottomY = cta(gui)
	local navScale = b.NavBar.MotifNavScale.Scale
	local navTop = h - 12 - (96 + 16) * navScale
	local navWidth = (4 * 120 + 3 * 14) * navScale
	local label = string.format("%dx%d", w, h)
	check("cta_between_lanterns_and_stall_" .. label, topY > 80 and bottomY < navTop, string.format("%d..%d nav %d", topY, bottomY, navTop))
	check("tiles_fit_width_" .. label, navWidth <= w - 20 and 96 * navScale >= 48, string.format("%.0f px, scale %.2f", navWidth, navScale))
	check("cta_touch_" .. label, b.PlayButton.Size.X.Offset >= 48 and b.PlayButton.Size.Y.Offset >= 48)
	local roomy, tall = w >= 900 and h >= 560, h >= 640 and h >= w * 1.2
	local goods = b.MotifStallGoods
	check("goods_placement_" .. label, goods.Visible == (roomy or tall) and goods.MotifShelf.Visible == (tall and not roomy))
	if goods.Visible then
		local bag = goods.MotifKingyoBag
		local bagTop = bag.Position.Y.Offset - 158 * bag.MotifPropScale.Scale
		check("goods_clear_of_lantern_" .. label, bagTop > bottomY + 8, string.format("bag top %d, lantern bottom %d", bagTop, bottomY))
	end
	local lanterns = 0
	for _, child in ipairs(b.MotifLanternString:GetChildren()) do
		if child.Name == "Lantern" and child.Visible then lanterns += 1 end
	end
	check("lanterns_scale_with_width_" .. label, lanterns >= 3 and lanterns <= 11 and lanterns <= math.floor(w / 100), lanterns)
	local coins = b.TopBar.CoinLabel
	check("coin_pill_fits_" .. label, coins.Size.X.Offset + 64 + 40 <= w - 32, coins.Size.X.Offset)
end

-- 6. Reduced motion: no endless loops ---------------------------------------------------------------------
local calm = Harness.world({reducedMotion = true})
local calmGui = calm.module("MainMenu").build(calm.playerGui, Harness.handlers({}), Harness.state)
local loops = 0
for _, tween in ipairs(calm.tweenService.created) do
	if tween.info and tween.info[4] == -1 then loops += 1 end
end
check("reduced_motion_builds_scene", calmGui.Background:FindFirstChild("MotifLanternString") ~= nil and #calm.warnings == 0, calm.warnings[1])
check("reduced_motion_no_loops", loops == 0, loops)
local lively = 0
for _, tween in ipairs(world.tweenService.created) do
	if tween.info and tween.info[4] == -1 then lively += 1 end
end
check("normal_motion_has_idle_loops", lively > 0, lively)

-- 7. Failure of the scene removes its pieces and leaves a working menu -------------------------------------
local broken = Harness.world({})
local brokenSkin = broken.module("Ennichi.EnnichiSkin")
brokenSkin.PAGES = setmetatable({}, {__index = function() error("simulated scene failure") end})
local brokenCalls = {}
local brokenGui = broken.module("MainMenu").build(broken.playerGui, Harness.handlers(brokenCalls), Harness.state)
local leftovers = {}
for _, object in ipairs(brokenGui:GetDescendants()) do
	for _, name in ipairs({"MotifLanternString", "MotifStall", "MotifPlayGlow", "MotifScrim", "MotifStars", "MotifAwning", "MotifSky"}) do
		if object.Name == name then table.insert(leftovers, name) end
	end
end
check("scene_failure_reported", #broken.warnings == 1 and string.find(broken.warnings[1], "simulated scene failure", 1, true) ~= nil, broken.warnings[1])
check("scene_failure_cleans_up", #leftovers == 0, table.concat(leftovers, ","))
local brokenPlay = brokenGui:FindFirstChild("PlayButton", true)
click(brokenPlay)
click(brokenGui:FindFirstChild("Nav_Quests", true))
check("scene_failure_menu_still_works", brokenCalls.play == 1 and brokenGui.QuestsPage.Visible == true)

-- 8. Without the Ennichi folder the menu builds with the plain theme ----------------------------------------
local plain = Harness.world({skip = {"src/client/Ennichi"}})
local plainTheme = plain.require(plain.shared:FindFirstChild("UITheme"))
local okPlain, plainGui = pcall(plain.module("MainMenu").build, plain.playerGui, Harness.handlers({}), Harness.state)
check("plain_fallback_builds", okPlain and plainGui and plainGui:FindFirstChild("PlayButton", true) ~= nil and plainTheme.skin == nil, plainGui)

print(string.format("%s ennichi skin: %d checks, %d failed", failures == 0 and "PASS" or "FAIL", count, failures))
process.exit(failures == 0 and 0 or 1)
