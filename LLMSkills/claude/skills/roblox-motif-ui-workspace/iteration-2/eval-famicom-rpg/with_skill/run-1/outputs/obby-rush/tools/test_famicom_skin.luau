--!nocheck
-- Lune test of the Famicom RPG skin. Run from the project folder:  lune run tools/test_famicom_skin.luau
-- (tests/test_main_menu.luau pins the name/behaviour contract; this one checks that the skin really ran,
-- looks the way the motif asks, keeps the hierarchy, handles state/motion, and reverts on failure.)
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local Harness = luau.load(fs.readFile("tools/harness.luau"), {debugName = "harness"})()
local rb = Harness.rb
local click = Harness.click

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
local function same(a, b) -- Color3 compare with float tolerance
	return a ~= nil and b ~= nil and math.abs(a.R - b.R) < 1e-3 and math.abs(a.G - b.G) < 1e-3 and math.abs(a.B - b.B) < 1e-3
end
local function family(object)
	local face = object.FontFace
	return face and tostring(face.Family) or ""
end
local function find(gui, name) return gui:FindFirstChild(name, true) end
local function visibleIn(object, root)
	local n = object
	while n and n ~= root do
		if n:IsA("GuiObject") and n.Visible == false then return false end
		n = n.Parent
	end
	return n == root
end
local function visibleCursors(gui)
	local list = {}
	for _, object in ipairs(gui:GetDescendants()) do
		if object.Name == "MotifCursor" and visibleIn(object, gui) then table.insert(list, object.Parent.Name) end
	end
	return list
end

local OLD_NAVY = {rb.Color3.fromRGB(11, 20, 38), rb.Color3.fromRGB(19, 35, 63), rb.Color3.fromRGB(28, 50, 86), rb.Color3.fromRGB(63, 169, 245)}

-- 1. The skin loads and is applied ------------------------------------------------------------------
local h = Harness.new({width = 1280, height = 720})
local Skin, Theme = h.Skin, h.Theme
local P = Skin and Skin.P
check("skin_module_loads", type(Skin) == "table" and type(Skin.apply) == "function")
if not Skin then process.exit(1) end
check("theme_skinned_in_place", Theme.skin == Skin and same(Theme.colors.background, P.paper) and same(Theme.colors.accent, P.primary)
	and same(Theme.colors.text, P.ink))
check("apply_is_idempotent", Skin.apply(Theme) == true and Skin.apply({}) == false)

local gui = h.build()
local background = gui:FindFirstChild("Background")
check("black_screen", same(background.BackgroundColor3, P.paper) and background.BackgroundTransparency == 0)
check("decoration_ran", find(gui, "MotifCoinWindow") ~= nil and find(gui, "MotifNavWindow") ~= nil and find(gui, "MotifPixelScene") ~= nil)
check("zindex_sibling", gui.ZIndexBehavior == rb.Enum.ZIndexBehavior.Sibling)

-- 2. Windows: black, white pixel frame with notched corners, no rounded corners, no old stroke ----------
local shop = gui:FindFirstChild("ShopPage")
local function isWindow(frame)
	local top, left = frame:FindFirstChild("MotifEdgeTop"), frame:FindFirstChild("MotifEdgeLeft")
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	local corner = frame:FindFirstChildOfClass("UICorner")
	return same(frame.BackgroundColor3, P.paper) and frame.BackgroundTransparency == 0 and top ~= nil and top.Visible
		and same(top.BackgroundColor3, P.ink) and top.Position.X.Offset == Skin.DOT and left.Position.Y.Offset == Skin.DOT
		and (stroke == nil or stroke.Transparency == 1) and (corner == nil or corner.CornerRadius.Offset == 0)
end
for _, name in ipairs({"ShopPage", "SettingsPage", "InventoryPage", "QuestsPage"}) do
	check("window_" .. name, isWindow(gui:FindFirstChild(name)))
end
check("coin_and_nav_windows", isWindow(find(gui, "MotifCoinWindow")) and isWindow(find(gui, "MotifNavWindow")))
local row = find(gui, "Product_speed_coil")
check("rows_are_lines_not_nested_windows", row.BackgroundTransparency == 1 and row:FindFirstChild("MotifEdgeTop") == nil)
check("page_title_set_into_frame_line", shop.Title.Position.Y.Offset == Skin.DOT / 2 and shop.Title.AnchorPoint.Y == 0.5
	and shop.Title.BackgroundTransparency == 0 and same(shop.Title.BackgroundColor3, P.paper))

-- 3. No generic navy anywhere that draws ---------------------------------------------------------------
local navy = {}
for _, object in ipairs(gui:GetDescendants()) do
	if object:IsA("GuiObject") and object.BackgroundTransparency ~= nil and object.BackgroundTransparency < 1 then
		for _, color in ipairs(OLD_NAVY) do
			if same(object.BackgroundColor3, color) then table.insert(navy, object:GetFullName()) end
		end
	end
	if object.ClassName == "UIStroke" and object.Transparency ~= 1 then table.insert(navy, "stroke " .. object:GetFullName()) end
end
check("no_old_navy_or_hairline_strokes", #navy == 0, table.concat(navy, ", "))

-- 4. Copy and type -------------------------------------------------------------------------------------
local play = find(gui, "PlayButton")
check("start_in_pixel_font", play.Text == "START" and string.find(family(play), "PressStart2P", 1, true) ~= nil and play.TextSize == 32)
check("kana_commands", find(gui, "Nav_Shop").Text == "おみせ" and find(gui, "Nav_Inventory").Text == "どうぐ"
	and find(gui, "Nav_Settings").Text == "せってい" and find(gui, "CloseButton").Text == "とじる")
check("gold_counter", find(gui, "CoinLabel").Text == "G 1250" and string.find(family(find(gui, "CoinLabel")), "PressStart2P", 1, true) ~= nil)
local tofu = {}
for _, object in ipairs(gui:GetDescendants()) do
	if type(object.Text) == "string" and string.find(object.Text, "\240\159\170", 1, true) then table.insert(tofu, object.Name) end
end
check("no_unicode13_emoji", #tofu == 0, table.concat(tofu, ", "))
local nav = find(gui, "Nav_Shop")
check("japanese_heavy", string.find(family(nav), "RobotoMono", 1, true) ~= nil and nav.FontFace.Weight == rb.Enum.FontWeight.Heavy)
check("japanese_body_bold", find(gui, "Empty").FontFace.Weight == rb.Enum.FontWeight.Bold)
check("latin_on_8px_grid", find(row, "Price").TextSize % 8 == 0 and find(row, "Price").Text == "300G")

-- 5. The CTA is the one gold thing on the title screen ---------------------------------------------------
local gold = {}
for _, object in ipairs(background:GetDescendants()) do
	if visibleIn(object, gui) and object.TextColor3 ~= nil and same(object.TextColor3, P.primary) then table.insert(gold, object.Name) end
end
check("cta_only_gold_text", #gold == 1 and gold[1] == "PlayButton", table.concat(gold, ", "))
check("cta_framed_window", play.BackgroundTransparency == 0 and play.MotifEdgeTop.Visible and find(gui, "Nav_Quests").MotifEdgeTop.Visible == false
	and find(gui, "Nav_Quests").BackgroundTransparency == 1)

-- 6. One blinking cursor, following hover / pages / press ---------------------------------------------------
local cursors = visibleCursors(gui)
check("one_cursor_on_start", #cursors == 1 and cursors[1] == "PlayButton", table.concat(cursors, ","))
local quests = find(gui, "Nav_Quests")
quests.MouseEnter:Fire()
cursors = visibleCursors(gui)
check("hover_moves_cursor", #cursors == 1 and cursors[1] == "Nav_Quests", table.concat(cursors, ","))
quests.MouseLeave:Fire()
cursors = visibleCursors(gui)
check("leave_returns_to_start", #cursors == 1 and cursors[1] == "PlayButton", table.concat(cursors, ","))
local cursor = play.MotifCursor
check("cursor_left_of_start_inside_window", cursor.Position.X.Scale == 0.5 and cursor.Position.X.Offset < -80
	and 140 + cursor.Position.X.Offset >= 4 and cursor.Size.X.Offset == 16 and cursor.Size.Y.Offset == 28)
check("cursor_is_white_system_mark", same(cursor.Column1.BackgroundColor3, P.ink) and same(play.TextColor3, P.primary))
check("cursor_about_one_kana_tall", find(gui, "Nav_Quests").MotifCursor.Size.Y.Offset == 21
	and find(gui, "Nav_Quests").MotifCursor.Size.Y.Offset <= find(gui, "Nav_Quests").TextSize + 2)

play.MouseEnter:Fire() -- UITheme's own hover repaints the face gold; the skin must put the window back
check("theme_hover_does_not_leak", same(play.BackgroundColor3, P.paper) and same(play.TextColor3, P.primary))
play.MouseLeave:Fire()

click(find(gui, "Nav_Shop"))
cursors = visibleCursors(gui)
local firstBuy = find(gui, "Product_speed_coil"):FindFirstChild("BuyButton", true)
local focusState = Skin._screens[gui]
check("page_open_moves_cursor_inside", focusState.shown == firstBuy and firstBuy.MotifCursor.Visible, table.concat(cursors, ","))
check("chosen_command_keeps_cursor", #cursors == 2 and find(gui, "Nav_Shop").MotifCursor.Visible, table.concat(cursors, ","))
Skin.step(gui)
check("only_active_cursor_blinks", firstBuy.MotifCursor.Visible == false and find(gui, "Nav_Shop").MotifCursor.Visible == true)
Skin.step(gui)
check("nav_navigates", h.calls.navigate[1] == "Shop")
check("window_hugs_rows", shop.Size.Y.Offset == 64 + 3 * 64 + 2 * 8 + 16, shop.Size.Y.Offset)
do -- a small window still covers the sprite + START band completely and stays below the logo
	local quests = gui:FindFirstChild("QuestsPage")
	local qTop, qBottom = quests.Position.Y.Offset, quests.Position.Y.Offset + quests.Size.Y.Offset
	local playTop, playBottom = 720 * 0.6 - 36, 720 * 0.6 + 36
	local s0 = find(gui, "MotifPixelScene")
	check("small_window_covers_band", qTop <= s0.Position.Y.Offset and qBottom >= playBottom and qTop >= 70 + 80 + 64
		and quests.Size.Y.Offset < shop.Size.Y.Offset + 1, string.format("%d..%d", qTop, qBottom))
	check("shop_window_covers_start", shop.Position.Y.Offset <= playTop and shop.Position.Y.Offset + shop.Size.Y.Offset >= playBottom)
end

local buy = find(gui, "Product_rainbow_trail"):FindFirstChild("BuyButton", true)
buy.InputBegan:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
check("press_inverts", buy.BackgroundTransparency == 0 and same(buy.BackgroundColor3, P.primary) and same(buy.TextColor3, P.onLight))
buy.InputEnded:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
check("release_restores", buy.BackgroundTransparency == 1 and same(buy.TextColor3, P.primary))
click(shop:FindFirstChild("CloseButton"))
cursors = visibleCursors(gui)
check("close_returns_cursor_to_start", shop.Visible == false and #cursors == 1 and cursors[1] == "PlayButton", table.concat(cursors, ","))

click(find(gui, "Nav_Settings"))
local music = find(gui, "Toggle_Music")
check("wide_line_left_aligned_with_cursor_slot", music.TextXAlignment == rb.Enum.TextXAlignment.Left
	and music.MotifPadding.PaddingLeft.Offset > 0 and music.MotifCursor.Position.X.Offset < 0)
click(music)
check("toggle_copy_stays_kana", music.Text == "おんがく: OFF", music.Text)
local sfx = find(gui, "Toggle_SFX")
sfx.Active = false
check("disabled_is_grey", same(sfx.TextColor3, P.disabled) and same(sfx.MotifCursor.Column1.BackgroundColor3, P.disabled))
sfx.Active = true
check("enabled_again", same(sfx.TextColor3, P.ink))
click(gui:FindFirstChild("SettingsPage"):FindFirstChild("CloseButton"))

-- 7. Stepwise motion on one 0.5 s tick; reduced motion holds still ----------------------------------------
local scene = find(gui, "MotifPixelScene")
check("scene_visible_on_desktop", scene.Visible == true and scene.Size.X.Offset == 480 and scene.Position.Y.Offset + scene.Size.Y.Offset < 720 * 0.6 - 36)
check("one_loop_per_screen", #h.spawned == 1, #h.spawned)
check("no_tweens", #h.tweenService.created == 0, #h.tweenService.created)
Skin.step(gui)
check("tick_blinks_cursor_off", play.MotifCursor.Visible == false)
check("tick_swaps_legs", scene.RunnerLegsA.Visible == false and scene.RunnerLegsB.Visible == true)
Skin.step(gui)
check("tick_blinks_cursor_on", play.MotifCursor.Visible == true and scene.RunnerLegsA.Visible == true)

local calm = Harness.new({width = 1280, height = 720, reducedMotion = true})
local calmGui = calm.build()
calm.Skin.step(calmGui)
calm.Skin.step(calmGui)
calm.Skin.step(calmGui)
local calmPlay = find(calmGui, "PlayButton")
check("reduced_motion_cursor_lit", calmPlay.MotifCursor.Visible == true)
check("reduced_motion_sprite_still", find(calmGui, "RunnerLegsA").Visible == true and find(calmGui, "RunnerLegsB").Visible == false)

-- 8. Names and hierarchy are exactly the unskinned ones ------------------------------------------------------
local plain = Harness.new({width = 1280, height = 720, skin = false})
check("unskinned_fallback_builds", plain.Skin == nil and plain.Theme.skin == nil)
local plainGui = plain.build()
local a, b = Harness.contractPaths(gui), Harness.contractPaths(plainGui)
local diff = {}
local setB = {}
for _, p in ipairs(b) do setB[p] = true end
local setA = {}
for _, p in ipairs(a) do
	setA[p] = true
	if not setB[p] then table.insert(diff, "+" .. p) end
end
for _, p in ipairs(b) do if not setA[p] then table.insert(diff, "-" .. p) end end
check("hierarchy_identical_to_unskinned", #diff == 0 and #a == #b, table.concat(diff, " "))
check("unskinned_copy_is_original", find(plainGui, "PlayButton").Text == "プレイ" and find(plainGui, "Nav_Inventory").Text == "持ち物")

-- 9. Top bar and responsive layouts ---------------------------------------------------------------------------
local top = background:FindFirstChild("TopBar")
check("clear_of_roblox_top_bar", top.Position.Y.Offset >= 58 + 8)
local phone = Harness.new({width = 828, height = 369})
local phoneGui = phone.build()
local phoneTitle = find(phoneGui, "TopBar"):FindFirstChild("Title")
local phonePlay = find(phoneGui, "PlayButton")
check("compact_hides_scene", find(phoneGui, "MotifPixelScene").Visible == false)
check("compact_title_row", phoneTitle.TextXAlignment == rb.Enum.TextXAlignment.Left and phoneTitle.Size.Y.Offset == 56)
local navTop = 369 - 20 - (64 + 24)
check("compact_start_between_rows", phonePlay.Position.Y.Offset - 36 > 70 + 56 and phonePlay.Position.Y.Offset + 36 < navTop,
	phonePlay.Position.Y.Offset)
local tall = Harness.new({width = 390, height = 844})
local tallGui = tall.build()
local tallNav = find(tallGui, "NavBar")
check("narrow_nav_is_2x2_command_grid", tallNav.Size.X.Offset == 280 and tallNav:FindFirstChildOfClass("UIListLayout").Wraps == true)
check("narrow_pages_fit", find(tallGui, "ShopPage").Size.X.Offset == 390 - 24)

-- 10. A failure part-way through the title-screen layout reverts everything -----------------------------------
local broken = Harness.new({width = 1280, height = 720})
local original = broken.Skin.pixelFrame
broken.Skin.pixelFrame = function(frame, ...)
	if frame.Name == "MotifNavWindow" then error("simulated failure") end
	return original(frame, ...)
end
local okBroken, brokenGui = pcall(broken.build)
broken.Skin.pixelFrame = original
check("build_survives_decoration_failure", okBroken and brokenGui ~= nil and find(brokenGui, "PlayButton") ~= nil, brokenGui)
if okBroken then
	local leftovers = {}
	for _, name in ipairs({"MotifCoinWindow", "MotifNavWindow", "MotifPixelScene", "MotifTitleShadow1", "MotifHeadingSize"}) do
		if find(brokenGui, name) then table.insert(leftovers, name) end
	end
	check("decoration_reverted", #leftovers == 0 and brokenGui.Background.BackgroundTransparency == 0.25
		and brokenGui.Background.TopBar.MotifEdgeTop.Visible == true and brokenGui.Background.TopBar.Size.Y.Offset == 64,
		table.concat(leftovers, ","))
	check("generic_skin_still_there", isWindow(brokenGui:FindFirstChild("ShopPage")) and find(brokenGui, "PlayButton").Text == "START")
end

print(string.format("%s famicom skin: %d checks, %d failed", failures == 0 and "PASS" or "FAIL", count, failures))
process.exit(failures == 0 and 0 or 1)
