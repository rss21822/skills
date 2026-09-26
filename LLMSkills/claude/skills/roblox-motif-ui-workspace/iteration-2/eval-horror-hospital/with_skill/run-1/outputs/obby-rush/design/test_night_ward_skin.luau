--!nocheck
-- NIGHT WARD skin test (the look; tests/test_main_menu.luau pins the contract).
-- Run from the project folder:  lune run design/test_night_ward_skin.luau
-- Checks: every motif step installs without warnings, the world-in-the-UI parts exist, colours by
-- role, press / hover / selected / on-off states, reduced motion and hidden-menu loops, layouts
-- for desktop, landscape phone and portrait phone, and that the menu still builds (with the same
-- names) if the motif layer is missing or one of its steps throws.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local rb = require("@lune/roblox")

local Harness = luau.load(fs.readFile("design/harness.luau"), {debugName = "harness"})()

local count, failures = 0, 0
local function check(name, ok, detail)
	count += 1
	if not ok then
		failures += 1
		print("FAIL " .. name .. (detail ~= nil and (" :: " .. tostring(detail)) or ""))
	end
end
local function near(a, b) return math.abs(a - b) < 1e-3 end
local function same(a, b) return near(a.R, b.R) and near(a.G, b.G) and near(a.B, b.B) end
local function contrast(a, b)
	local function ch(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
	local function rel(c) return 0.2126 * ch(c.R) + 0.7152 * ch(c.G) + 0.0722 * ch(c.B) end
	local la, lb = rel(a), rel(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end
local function hsl(c)
	local maxc, minc = math.max(c.R, c.G, c.B), math.min(c.R, c.G, c.B)
	local l = (maxc + minc) / 2
	if maxc == minc then return 0, l, 0 end
	local d = maxc - minc
	local s = l > 0.5 and d / (2 - maxc - minc) or d / (maxc + minc)
	local h
	if maxc == c.R then h = (c.G - c.B) / d % 6 elseif maxc == c.G then h = (c.B - c.R) / d + 2 else h = (c.R - c.G) / d + 4 end
	return h * 60, l, s
end
local function press(button) button.InputBegan:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1}) end
local function release(button) button.InputEnded:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1}) end
local function click(button) press(button); release(button); button.Activated:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1}, 1) end

local function build(options)
	local h = Harness(options)
	local MainMenu = h.requireClient("MainMenu")
	local gui = MainMenu.build(h.playerGui, h.handlers, h.state)
	local function find(name) return gui:FindFirstChild(name, true) end
	return h, gui, find, h.requireShared("UITheme")
end

-- Desktop, motion on ---------------------------------------------------------------------------------
local h, gui, find, Theme = build({})
local C = Theme.colors
check("no_motif_warnings", #h.warnings == 0, table.concat(h.warnings, " | "))
check("theme_uses_motif_kit", Theme.kit ~= nil and Theme.kit.P.primary ~= nil)
check("zindex_sibling", gui.ZIndexBehavior == rb.Enum.ZIndexBehavior.Sibling)

-- Palette: no dashboard navy on any big surface; the CTA colour is used by the CTA only.
for _, key in ipairs({"background", "panel", "dim", "paper", "board"}) do
	local hue, light, sat = hsl(C[key])
	check("not_navy_" .. key, not (hue >= 205 and hue <= 250 and light < 0.34 and sat < 0.85), string.format("h%.0f l%.2f", hue, light))
end
local accentUsers = {}
for _, object in ipairs(gui:GetDescendants()) do
	if object:IsA("GuiObject") and object.BackgroundTransparency ~= nil and object.BackgroundTransparency < 1
		and object.BackgroundColor3 and same(object.BackgroundColor3, C.accent) and object.Name ~= "Opening" then
		table.insert(accentUsers, object.Name)
	end
end
check("accent_only_on_cta", #accentUsers == 1 and accentUsers[1] == "PlayButton", table.concat(accentUsers, ","))

-- World-in-the-UI parts
local play = find("PlayButton")
check("cta_is_exit_sign", play:FindFirstChild("MotifExitPicto") ~= nil and play.MotifExitPicto:FindFirstChild("Door") ~= nil
	and play.MotifExitPicto:FindFirstChild("Head") ~= nil and find("MotifExitGlow") ~= nil)
check("cta_text_mirrored", play.Text == "脱出する" and play.MotifExitText.Text == "脱出する" and play.TextTransparency == 1)
play.Text = "脱出する!"
check("cta_mirror_follows_text", play.MotifExitText.Text == "脱出する!")
play.Text = "脱出する"
check("cta_face_and_type", same(play.BackgroundColor3, C.accent) and same(play.MotifExitText.TextColor3, C.text)
	and contrast(C.text, C.accent) >= 4.5, contrast(C.text, C.accent))
for _, id in ipairs({"Shop", "Inventory", "Quests", "Settings"}) do
	local pageFrame = find(id .. "Page")
	check("chart_on_clipboard_" .. id, pageFrame:FindFirstChild("MotifClip") ~= nil and pageFrame:FindFirstChild("MotifSheet") ~= nil
		and pageFrame.MotifSheet:FindFirstChild("MotifChartHead") ~= nil)
	check("chart_text_on_paper_" .. id, same(pageFrame.Title.TextColor3, C.ink) and contrast(C.ink, C.paper) >= 7)
	local plate = find("Nav_" .. id)
	check("room_plate_" .. id, plate:FindFirstChild("MotifRoomNo") ~= nil and plate:FindFirstChild("MotifLamp") ~= nil
		and same(plate.BackgroundColor3, C.panelLight) and same(plate.TextColor3, C.ink))
end
check("stamps_on_empty_charts", find("InventoryPage"):FindFirstChild("MotifStamp") ~= nil and find("QuestsPage"):FindFirstChild("MotifStamp") ~= nil)
local top = find("TopBar")
check("topbar_below_roblox_bar", top.Position.Y.Offset >= 58 + 8, top.Position)
check("coin_led", find("CoinLabel").Text == "1,250" and same(find("CoinLabel").TextColor3, C.amber)
	and find("CoinLabel"):FindFirstChild("MotifCoinToken") ~= nil)
check("no_tofu_emoji", not string.find(find("CoinLabel").Text, "\240\159\170", 1, true))

-- States: the exit sign dims when pressed, hover is a passing flashlight, nothing squashes.
press(play)
check("press_dims_cta", Theme.kit.luminance(play.BackgroundColor3) < Theme.kit.luminance(C.accent))
release(play)
check("release_restores_cta", same(play.BackgroundColor3, C.accent))
check("no_bounce_scale", play:FindFirstChild("MotifScale") == nil)
play.MouseEnter:Fire()
check("hover_warms", not same(play.BackgroundColor3, C.accent))
play.MouseLeave:Fire()
check("leave_restores", same(play.BackgroundColor3, C.accent))
local buy = find("Product_rainbow_trail").BuyButton
check("buy_is_stamp", same(buy.BackgroundColor3, C.paperLight) and same(buy.TextColor3, C.stamp) and buy:FindFirstChild("MotifStampInner") ~= nil)
press(buy)
check("stamp_inks_in_on_press", same(buy.BackgroundColor3, C.stamp) and same(buy.TextColor3, C.paperLight))
release(buy)
check("stamp_releases", same(buy.BackgroundColor3, C.paperLight))

-- Opening a chart dims the corridor and lights its door plate; closing reverses it.
local scrim = gui:FindFirstChild("MotifScrim")
check("scrim_hidden_at_start", scrim ~= nil and scrim.Visible == false and scrim.Active == false)
local shopBase = find("ShopPage").Position
check("chart_between_sign_and_dock", shopBase.Y.Scale == 0 and shopBase.Y.Offset - find("ShopPage").Size.Y.Offset / 2 >= 58 + 8 + 64
	and shopBase.Y.Offset + find("ShopPage").Size.Y.Offset / 2 <= 720 - 24 - 64, shopBase)
click(find("Nav_Shop"))
check("open_shows_scrim", scrim.Visible == true)
check("open_lights_plate", same(find("Nav_Shop").BackgroundColor3, C.paperLight) and same(find("Nav_Shop").MotifLamp.BackgroundColor3, C.glow)
	and same(find("Nav_Settings").MotifLamp.BackgroundColor3, C.lampOff))
check("chart_slides_to_base", find("ShopPage").Position == shopBase, find("ShopPage").Position)
click(find("Nav_Settings"))
check("switching_moves_lamp", same(find("Nav_Shop").MotifLamp.BackgroundColor3, C.lampOff) and same(find("Nav_Settings").MotifLamp.BackgroundColor3, C.glow))
local music = find("Toggle_Music")
check("switch_on_at_start", same(music.MotifLamp.BackgroundColor3, C.glow) and music.MotifSwitch.Slot.Lever.Position.Y.Scale == 0)
click(music)
check("switch_follows_off", string.find(music.Text, "OFF", 1, true) ~= nil and same(music.MotifLamp.BackgroundColor3, C.lampOff)
	and near(music.MotifSwitch.Slot.Lever.Position.Y.Scale, 0.5))
click(find("SettingsPage").CloseButton)
check("close_hides_scrim_and_lamp", scrim.Visible == false and same(find("Nav_Settings").MotifLamp.BackgroundColor3, C.lampOff))
find("InventoryPage").Visible = true -- another script opening a page directly
check("direct_open_tracked", scrim.Visible == true and same(find("Nav_Inventory").MotifLamp.BackgroundColor3, C.glow))
find("InventoryPage").Visible = false

-- Motion: two slow loops, none faster than 2.5 s per swing; they stop (and reset) when hidden.
local loops = {}
for _, tween in ipairs(h.tweens) do
	if tween.info and tween.info[4] == -1 then table.insert(loops, tween) end
end
check("two_loops", #loops == 2, #loops)
local slowest = math.huge
for _, tween in ipairs(loops) do slowest = math.min(slowest, tween.info[1]) end
check("loops_are_slow", slowest >= 2.5, slowest)
local glowRing = find("MotifExitGlow").MotifGlowRing
gui.Enabled = false
local allCancelled = true
for _, tween in ipairs(loops) do allCancelled = allCancelled and tween.cancelled end
check("hidden_menu_stops_loops", allCancelled and near(glowRing.Transparency, 0.74) and glowRing.Thickness == 10)
gui.Enabled = true
local restarted = 0
for _, tween in ipairs(h.tweens) do if tween.info and tween.info[4] == -1 and not tween.cancelled then restarted += 1 end end
check("shown_menu_restarts_loops", restarted == 2, restarted)

-- Reduced motion: no loops at all, charts appear in place.
local hr, guiR, findR = build({reducedMotion = true})
local loopsR = 0
for _, tween in ipairs(hr.tweens) do if tween.info and tween.info[4] == -1 then loopsR += 1 end end
check("reduced_motion_no_loops", loopsR == 0, loopsR)
local baseR = guiR.ShopPage.Position
guiR.ShopPage.Visible = true
check("reduced_motion_chart_in_place", guiR.ShopPage.Position == baseR)
check("reduced_motion_no_warnings", #hr.warnings == 0, table.concat(hr.warnings, " | "))

-- Layouts ------------------------------------------------------------------------------------------------
local hp, guiP, findP = build({viewport = rb.Vector2.new(366, 820)})
check("portrait_no_warnings", #hp.warnings == 0, table.concat(hp.warnings, " | "))
check("portrait_dock_wraps_2x2", findP("NavBar").UIListLayout.Wraps == true and findP("Nav_Shop").Size == rb.UDim2.fromOffset(160, 64)
	and findP("NavBar").Size.X.Offset * findP("NavBar").MotifFit.Scale <= 366 - 20 + 1e-3)
check("portrait_headline_two_lines", string.find(findP("MotifHeadline").Text, "\n", 1, true) ~= nil)
check("portrait_doors_hidden", findP("MotifDoor").Visible == false)
check("portrait_topbar_two_rows", findP("TopBar").Size.Y.Offset == 96 and findP("CoinLabel").AnchorPoint == rb.Vector2.new(1, 1))
local pageP, navP = findP("ShopPage"), findP("NavBar")
check("portrait_chart_clears_dock", pageP.Position.Y.Offset + pageP.Size.Y.Offset / 2 <= 820 - 24 - navP.Size.Y.Offset * navP.MotifFit.Scale,
	pageP.Position.Y.Offset + pageP.Size.Y.Offset / 2)
local hl, guiL, findL = build({viewport = rb.Vector2.new(828, 369)})
check("landscape_no_warnings", #hl.warnings == 0, table.concat(hl.warnings, " | "))
check("landscape_compact", findL("MotifKicker").Visible == false and near(findL("PlayButton").MotifFit.Scale, 0.8)
	and near(findL("NavBar").MotifFit.Scale, 0.84) and findL("Nav_Shop").Size.Y.Offset * 0.84 >= 48)
check("desktop_doors_visible", find("MotifDoor").Visible == true and find("NavBar").UIListLayout.Wraps == false)

-- Fallbacks ------------------------------------------------------------------------------------------------
local function contractNames(g)
	for _, name in ipairs({"Background", "TopBar", "Title", "CoinLabel", "PlayButton", "NavBar", "Nav_Shop", "Nav_Inventory", "Nav_Quests",
		"Nav_Settings", "ShopPage", "InventoryPage", "QuestsPage", "SettingsPage", "ProductList", "Product_speed_coil", "BuyButton",
		"Toggle_Music", "Toggle_SFX", "CloseButton"}) do
		if not g:FindFirstChild(name, true) then return false, name end
	end
	return true
end
local hn, guiN = build({skip = {NightWardArt = true}})
local okN, missingN = contractNames(guiN)
check("builds_without_motif_layer", okN and guiN:FindFirstChild("MotifScrim", true) == nil, missingN)
check("plain_build_keeps_readable_text", same(guiN:FindFirstChild("PlayButton", true).TextColor3, Theme.colors.text))
do
	local hf = Harness({})
	local Art = hf.requireClient("NightWardArt")
	Art.corridor = function() error("simulated failure") end
	local MainMenu = hf.requireClient("MainMenu")
	local guiF = MainMenu.build(hf.playerGui, hf.handlers, hf.state)
	local okF, missingF = contractNames(guiF)
	check("one_failing_step_is_isolated", okF and #hf.warnings == 1 and guiF:FindFirstChild("MotifExitPicto", true) ~= nil
		and guiF:FindFirstChild("MotifClip", true) ~= nil, missingF or table.concat(hf.warnings, " | "))
end

print(string.format("%s night ward skin: %d checks, %d failed", failures == 0 and "PASS" or "FAIL", count, failures))
process.exit(failures == 0 and 0 or 1)
