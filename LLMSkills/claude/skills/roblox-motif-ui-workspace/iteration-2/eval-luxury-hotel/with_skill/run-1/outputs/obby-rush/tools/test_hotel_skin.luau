--!nocheck
-- Grand Hotel skin test (the contract test in tests/ pins names and behaviour; this pins the look).
-- Run from the project folder:  lune run tools/test_hotel_skin.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local rb = require("@lune/roblox")

local Harness = luau.load(fs.readFile("tools/harness.luau"), {debugName = "harness"})()

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
local function same(a, b)
	return a ~= nil and b ~= nil and near(a.R, b.R) and near(a.G, b.G) and near(a.B, b.B)
end

-- 1. The skin applies, once, and the menu decorates without errors ----------------------------------
local h = Harness.new()
local Theme = h.theme()
local Skin = Theme.skin
check("skin_applied", type(Skin) == "table" and type(Skin.kit) == "table")
if not Skin then process.exit(1) end
local P = Skin.P
local wrappedButton = Theme.button
check("apply_is_idempotent", Skin.apply(Theme) == true and Theme.button == wrappedButton)
check("apply_ignores_non_theme", Skin.apply({}) == false and Skin.apply(nil) == false)

local gui = h.build()
check("decorate_without_errors", Skin.lastErrors ~= nil and #Skin.lastErrors == 0, table.concat(Skin.lastErrors or {"(not run)"}, " | "))
h.resize(gui, 1280, 720)

local function find(name, root) return (root or gui):FindFirstChild(name, true) end

-- 2. Palette: the navy dashboard is gone ------------------------------------------------------------
local oldNavy = {rb.Color3.fromRGB(11, 20, 38), rb.Color3.fromRGB(19, 35, 63), rb.Color3.fromRGB(28, 50, 86), rb.Color3.fromRGB(63, 169, 245)}
local navyLeft = {}
for _, object in ipairs(gui:GetDescendants()) do
	for _, key in ipairs({"BackgroundColor3", "TextColor3", "Color"}) do
		local ok, value = pcall(function() return object[key] end)
		if ok and typeof(value) == "Color3" then
			for _, navy in ipairs(oldNavy) do
				if same(value, navy) and not (key == "BackgroundColor3" and object.BackgroundTransparency == 1) then
					table.insert(navyLeft, object.Name .. "." .. key)
				end
			end
		end
	end
end
check("no_old_navy_left", #navyLeft == 0, table.concat(navyLeft, ", "))
check("theme_colours_in_place", same(Theme.colors.background, P.paper) and same(Theme.colors.accent, P.primary) and same(Theme.colors.text, P.ink))

-- 3. Hotel vocabulary only: no sticker parts, opaque hairlines, square corners, no tilt ---------------
local sticker, faintStroke, roundButtons, tilted = {}, {}, {}, {}
for _, object in ipairs(gui:GetDescendants()) do
	if object.Name == "MotifGloss" or object.Name == "MotifLip" or object.Name == "MotifTextOutline" or object.Name == "MotifScale" then
		table.insert(sticker, object.Name)
	end
	if object.ClassName == "UIStroke" and object.Transparency ~= 0 and object.Transparency ~= 1 then
		table.insert(faintStroke, object.Parent.Name)
	end
	if object:IsA("GuiButton") then
		local corner = object:FindFirstChildOfClass("UICorner")
		if corner and (corner.CornerRadius.Scale > 0 or corner.CornerRadius.Offset > 2) then table.insert(roundButtons, object.Name) end
		if object.Rotation ~= 0 then table.insert(tilted, object.Name) end
	end
end
check("no_sticker_parts", #sticker == 0, table.concat(sticker, ", "))
check("no_semi_transparent_hairlines", #faintStroke == 0, table.concat(faintStroke, ", "))
check("buttons_near_square", #roundButtons == 0, table.concat(roundButtons, ", "))
check("buttons_not_tilted", #tilted == 0, table.concat(tilted, ", "))

-- Decorations never catch clicks and never draw Roblox's default border / grey face.
local loud = {}
for _, object in ipairs(gui:GetDescendants()) do
	if string.sub(object.Name, 1, 5) == "Hotel" and object:IsA("GuiObject") then
		if object.Active ~= false or object.BorderSizePixel ~= 0 then table.insert(loud, object.Name) end
		if object.ClassName == "TextLabel" and object.BackgroundTransparency ~= 1 then table.insert(loud, object.Name .. "(face)") end
	end
end
check("decorations_inert", #loud == 0, table.concat(loud, ", "))

-- 4. The lobby scene and the three pieces of hotel furniture --------------------------------------
local background = gui:FindFirstChild("Background")
check("lobby_opaque_marble", same(background.BackgroundColor3, P.paper) and background.BackgroundTransparency == 0)
local veins = 0
for _, object in ipairs(find("HotelVeins"):GetChildren()) do if object.Name == "HotelVein" then veins += 1 end end
check("marble_veins", veins >= 60, veins)
local chandelier = find("HotelChandelier")
local crystals, candles = 0, 0
for _, object in ipairs(chandelier:GetChildren()) do
	if object.Name == "HotelCrystal" then crystals += 1 end
	if object.Name == "HotelCandle" then candles += 1 end
end
check("chandelier_hangs_centre_top", chandelier.Position == rb.UDim2.fromScale(0.5, 0) and crystals >= 60 and candles == 21, crystals .. " crystals, " .. candles .. " candles")
check("chandelier_scale_follows_height", near(find("HotelScale", chandelier).Scale, 1))

local play = find("PlayButton")
check("cta_is_brass_door", same(play.BackgroundColor3, P.primary) and same(play.TextColor3, P.onLight) and play.BackgroundTransparency == 0)
check("cta_double_rule", play:FindFirstChild("HotelRule") ~= nil and same(play.HotelEdge.Color, P.goldLight))
check("cta_in_elevator_portal", find("HotelElevator") ~= nil and find("HotelElevator").Position == play.Position)
local needle = find("HotelDialNeedle")
check("floor_dial_rests_on_lobby", find("HotelFloorDial").Visible == true and near(needle.Rotation, -75))
play.MouseEnter:Fire()
check("hover_sends_needle_up_and_lights_brass", near(needle.Rotation, 75) and not same(play.BackgroundColor3, P.primary))
play.MouseLeave:Fire()
check("leave_returns_needle", near(needle.Rotation, -75) and same(play.BackgroundColor3, P.primary))
check("cta_most_prominent", (function()
	-- Only the CTA is a solid gold face on the lobby screen.
	for _, object in ipairs(background:GetDescendants()) do
		if object:IsA("GuiButton") and object ~= play and same(object.BackgroundColor3, P.primary) and object.BackgroundTransparency == 0 then
			return false
		end
	end
	return true
end)())

local captions = {Shop = "BOUTIQUE", Inventory = "CLOAKROOM", Quests = "CONCIERGE", Settings = "RECEPTION"}
for id, caption in pairs(captions) do
	local plaque = find("Nav_" .. id)
	local label = plaque and plaque:FindFirstChild("HotelNavCaption")
	check("directory_plaque_" .. id, label ~= nil and label.Text == caption and same(plaque.BackgroundColor3, P.plaque)
		and plaque:FindFirstChild("HotelRule") ~= nil)
end

-- Top bar clears Roblox's buttons, hotel name in the engraved face, coin token instead of tofu.
local top = find("TopBar")
check("topbar_below_roblox_bar", top.Position.Y.Offset >= 16 + 58)
check("hotel_name_face", string.find(find("Title", top).FontFace.Family, "RomanAntique", 1, true) ~= nil)
local coins = find("CoinLabel")
check("coins_ledger_and_token", coins.Text == "1,250" and coins:FindFirstChild("HotelCoin") ~= nil)
local tofu = {}
for _, object in ipairs(gui:GetDescendants()) do
	if type(object.Text) == "string" then
		for _, code in utf8.codes(object.Text) do
			if code >= 0x1FA70 and code <= 0x1FAFF then table.insert(tofu, object.Name) end
		end
	end
end
check("no_unicode13_emoji", #tofu == 0, table.concat(tofu, ", "))
check("japanese_asks_bold", (function()
	for _, object in ipairs(gui:GetDescendants()) do
		if type(object.Text) == "string" and string.find(object.Text, "[\227-\237]") and object.FontFace then
			local weight = object.FontFace.Weight
			if weight ~= rb.Enum.FontWeight.Bold and weight ~= rb.Enum.FontWeight.Heavy and weight ~= rb.Enum.FontWeight.ExtraBold then
				return false
			end
		end
	end
	return true
end)())

-- 5. Pages: framed marble, veil, selected plaque, menu card, lamps --------------------------------
local shopNav = find("Nav_Shop")
h.click(shopNav)
local shop = find("ShopPage")
check("page_framed_marble", same(shop.BackgroundColor3, P.panel) and shop.BackgroundTransparency == 0 and shop:FindFirstChild("HotelRule") ~= nil
	and shop:FindFirstChild("HotelCrest") ~= nil)
check("page_caption", find("HotelPageCaption", shop).Text == "BOUTIQUE")
local keys = 0
for _, object in ipairs(shop.HotelCrest:GetChildren()) do if object.Name == "HotelKey" then keys += 1 end end
check("crest_crossed_keys", keys == 2 and shop:FindFirstChild("HotelFooterRule") ~= nil)
check("veil_behind_open_page", find("HotelVeil").Visible == true and find("HotelVeil").ZIndex < shop.ZIndex)
check("open_page_lights_its_plaque", same(shopNav.TextColor3, P.goldLight) and same(find("Nav_Quests").TextColor3, P.ink))
local row = find("Product_rainbow_trail")
check("menu_card_line", row.BackgroundTransparency == 1 and row:FindFirstChild("HotelLeader") ~= nil and row:FindFirstChild("HotelRowRule") ~= nil)
check("price_with_token", row.Price.Text == "450" and row.Price:FindFirstChild("HotelCoin") ~= nil)
local buy = row.BuyButton
check("reserve_is_outlined", buy.BackgroundTransparency == 1 and same(buy.TextColor3, P.primary))
buy.MouseEnter:Fire()
check("reserve_fills_on_hover", buy.BackgroundTransparency == 0 and same(buy.TextColor3, P.onLight))
buy.MouseLeave:Fire()
check("reserve_restores", buy.BackgroundTransparency == 1)
h.click(find("Nav_Settings"))
check("switching_pages_moves_highlight", same(find("Nav_Settings").TextColor3, P.goldLight) and same(shopNav.TextColor3, P.ink))
local music = find("Toggle_Music")
local lamp = music:FindFirstChild("HotelLamp", true)
check("lamp_lit_when_on", lamp ~= nil and same(lamp.BackgroundColor3, P.candle) and music.HotelLampGlow.Visible == true)
h.click(music)
check("lamp_dark_when_off", same(lamp.BackgroundColor3, P.goldDeep) and music.HotelLampGlow.Visible == false
	and lamp.Position.X.Scale == 0 and music:FindFirstChild("HotelSwitch") ~= nil)
h.click(find("CloseButton", find("SettingsPage")))
check("veil_gone_when_closed", find("HotelVeil").Visible == false and same(find("Nav_Settings").TextColor3, P.ink))

-- 6. Layout follows the screen -------------------------------------------------------------------
h.resize(gui, 844, 390)
check("phone_landscape_scales_down", near(find("HotelScale", chandelier).Scale, 0.54166) and find("HotelFloorDial").Visible == false)
local inlays = 0
for _, object in ipairs(find("HotelFloorInlay"):GetChildren()) do if object.Name == "HotelInlay" then inlays += 1 end end
check("floor_inlay_redrawn_once", inlays == 24, inlays)

-- 7. Motion: one slow idle loop; none under reduced motion ---------------------------------------
local function loops(tweens)
	local n = 0
	for _, tween in ipairs(tweens) do
		if type(tween.info) == "table" and tween.info[4] == -1 then n += 1 end
	end
	return n
end
check("one_idle_loop", loops(h.tweens) == 1, loops(h.tweens))
local calm = Harness.new({reducedMotion = true})
calm.theme()
local calmGui = calm.build()
check("reduced_motion_no_loops", loops(calm.tweens) == 0 and calmGui:FindFirstChild("HotelVeil", true) ~= nil)

-- 8. Failure paths keep a working menu ------------------------------------------------------------
local bare = Harness.new({withoutSkin = true})
local bareTheme = bare.theme()
local bareGui = bare.build()
check("without_skin_original_look", bareTheme.skin == nil and bareGui:FindFirstChild("PlayButton", true) ~= nil
	and bareGui:FindFirstChild("CoinLabel", true).Text == "🪙 1250")
local broken = Harness.new()
broken.theme().skin.decorateMainMenu = function() error("boom") end
local okBroken, brokenGui = pcall(broken.build)
check("decorate_failure_is_contained", okBroken and brokenGui:FindFirstChild("PlayButton", true) ~= nil)

print(string.format("%s hotel skin: %d checks, %d failed", failures == 0 and "PASS" or "FAIL", count, failures))
process.exit(failures == 0 and 0 or 1)
