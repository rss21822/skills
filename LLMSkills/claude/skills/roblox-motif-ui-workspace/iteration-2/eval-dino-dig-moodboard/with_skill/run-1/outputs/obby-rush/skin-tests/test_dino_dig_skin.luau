--!nocheck
-- Lune test of the "Lost Valley Dig" skin. Run from the project folder:
--   lune run skin-tests/test_dino_dig_skin.luau
-- tests/test_main_menu.luau pins the names and behaviour; this one pins the skin: it applies cleanly,
-- recolours everything (no navy left), keeps the name contract and the button count, reacts to page /
-- toggle / coin changes, honours reduced motion, and falls back to the plain menu when it cannot load.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local Harness = luau.load(fs.readFile("skin-tests/harness.luau"), {debugName = "harness"})()
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
local function same(a, b) return a and b and math.abs(a.R - b.R) < 1e-3 and math.abs(a.G - b.G) < 1e-3 and math.abs(a.B - b.B) < 1e-3 end

local ORIGINAL = { -- the old dashboard palette (UITheme before the skin)
	rb.Color3.fromRGB(11, 20, 38), rb.Color3.fromRGB(19, 35, 63), rb.Color3.fromRGB(28, 50, 86),
	rb.Color3.fromRGB(63, 169, 245), rb.Color3.fromRGB(230, 240, 255), rb.Color3.fromRGB(140, 160, 190),
}

-- Build ------------------------------------------------------------------------------------------------
local h = Harness.new()
local Theme = h.theme()
local MainMenu = h.menu()
local handlers, calls = Harness.handlers()
local state = Harness.state()
local gui = MainMenu.build(h.playerGui, handlers, state)
local Skin = h.skin()
local kit = Skin.kit
local P = kit.P

check("skin_loaded_and_applied", Skin ~= nil and Theme.skin == Skin)
check("decorate_no_errors", #Skin.errors == 0, table.concat(Skin.errors, " | "))
check("no_warnings", #h.warnings == 0, table.concat(h.warnings, " | "))

-- Theme adapter
local wrappedButton = Theme.button
check("theme_idempotent", Skin.theme(Theme) == true and Theme.button == wrappedButton)
check("theme_rejects_non_theme", Skin.theme({}) == false and Skin.theme(nil) == false)
check("theme_colors_recoloured", same(Theme.colors.accent, P.amber) and same(Theme.colors.text, P.ink)
	and same(Theme.colors.panel, P.paper) and same(Theme.colors.background, P.sand))

-- No trace of the old palette on any surface, text or edge.
local leftovers = {}
for _, object in ipairs(gui:GetDescendants()) do
	for _, key in ipairs({"BackgroundColor3", "TextColor3", "Color"}) do
		local ok, value = pcall(function() return object[key] end)
		if ok and typeof(value) == "Color3" then
			for _, old in ipairs(ORIGINAL) do
				if same(value, old) then table.insert(leftovers, object.Name .. "." .. key) end
			end
		end
	end
end
check("no_old_navy_left", #leftovers == 0, table.concat(leftovers, ", "))

-- Name contract (same names, same parents) and no extra buttons
local function find(name) return gui:FindFirstChild(name, true) end
local background = gui:FindFirstChild("Background")
check("contract_parents", find("PlayButton").Parent == background and find("CoinLabel").Parent == background.TopBar
	and find("Nav_Shop").Parent == background.NavBar and gui:FindFirstChild("ShopPage") ~= nil
	and find("Product_speed_coil").Parent.Name == "ProductList" and gui.SettingsPage:FindFirstChild("Toggle_Music") ~= nil)
local buttons, motifButtons, activeDecor = 0, {}, {}
for _, object in ipairs(gui:GetDescendants()) do
	if object:IsA("GuiButton") then
		buttons += 1
		if string.sub(object.Name, 1, 5) == "Motif" then table.insert(motifButtons, object.Name) end
	elseif string.sub(object.Name, 1, 5) == "Motif" and object:IsA("GuiObject") and object.Active == true then
		table.insert(activeDecor, object.Name)
	end
end
check("button_count_unchanged", buttons == 14, buttons) -- PLAY + 4 nav + 4 close + 3 buy + 2 toggles
check("decor_is_not_interactive", #motifButtons == 0 and #activeDecor == 0, table.concat(activeDecor, ","))

-- Hero parts
local play = find("PlayButton")
check("cta_is_amber_with_dark_text", same(play.BackgroundColor3, P.amber) and same(play.TextColor3, P.ink))
check("cta_has_trapped_bug_and_dig_plot", play:FindFirstChild("MotifTrappedBug") ~= nil and background:FindFirstChild("MotifDigPlot") ~= nil
	and background.MotifDigPlot:FindFirstChild("MotifSoilBed") ~= nil)
check("cta_is_the_biggest_button", (function()
	local area = play.Size.X.Offset * play.Size.Y.Offset
	for _, object in ipairs(gui:GetDescendants()) do
		if object:IsA("GuiButton") and object ~= play and object.Size.X.Scale == 0 and object.Size.X.Offset * object.Size.Y.Offset >= area then return false end
	end
	return true
end)())
check("scene_built", background:FindFirstChild("MotifCanopy") ~= nil and background:FindFirstChild("MotifStrata") ~= nil
	and background.MotifStrata:FindFirstChild("MotifSkeleton") ~= nil and background:FindFirstChild("MotifVineLeft") ~= nil)
check("title_below_roblox_topbar", background.TopBar.Position.Y.Offset >= 58 + 8)
check("title_font_oswald", string.find(background.TopBar.Title.FontFace.Family, "Oswald", 1, true) ~= nil)

-- Readability: every button's text against its face >= 4.5:1
local unreadable = {}
for _, object in ipairs(gui:GetDescendants()) do
	if object:IsA("GuiButton") then
		local ratio = kit.contrast(object.TextColor3, object.BackgroundColor3)
		if ratio < 4.5 then table.insert(unreadable, string.format("%s %.1f", object.Name, ratio)) end
	end
end
check("button_text_contrast", #unreadable == 0, table.concat(unreadable, ", "))

-- Type: the typewriter face never gets Japanese; Japanese text asks for Bold or heavier
local badType = {}
for _, object in ipairs(gui:GetDescendants()) do
	if (object:IsA("TextLabel") or object:IsA("TextButton")) and type(object.FontFace) == "table" then
		local family, weight = object.FontFace.Family, object.FontFace.Weight
		if kit.cjk(object.Text) then
			if string.find(family, "SpecialElite", 1, true) then table.insert(badType, object.Name .. " typewriter-on-CJK") end
			if weight and weight.Value < 700 then table.insert(badType, object.Name .. " thin-CJK") end
		end
	end
end
check("japanese_type_rules", #badType == 0, table.concat(badType, ", "))

-- Emoji: nothing newer than Unicode 12 (Roblox draws those as a box)
local tofu = {}
for _, object in ipairs(gui:GetDescendants()) do
	if object:IsA("TextLabel") or object:IsA("TextButton") then
		for _, code in utf8.codes(object.Text) do
			if code >= 0x1FA70 and code <= 0x1FAFF and not ((code >= 0x1FA70 and code <= 0x1FA73) or (code >= 0x1FA78 and code <= 0x1FA7A)
				or (code >= 0x1FA80 and code <= 0x1FA82) or (code >= 0x1FA90 and code <= 0x1FA95)) then
				table.insert(tofu, object.Name)
			end
		end
	end
end
check("no_unicode13_emoji", #tofu == 0, table.concat(tofu, ", "))

-- Coin: the tofu coin is replaced by drawn amber, also on later updates
local coin = find("CoinLabel")
check("coin_text_clean", coin.Text == "1250" and coin:FindFirstChild("MotifAmber") ~= nil, coin.Text)
coin.Text = "\240\159\170\153 2000"
check("coin_updates_stay_clean", coin.Text == "2000", coin.Text)
check("prices_clean", find("Product_speed_coil").Price.Text == "300")

-- Pages: shade, nav selection and the glow follow the pages' Visible
local tweens = h.tweens
local glowRing = background.MotifDigPlot.MotifAmberGlow.MotifGlowRing
local function glowing()
	for _, tween in ipairs(tweens) do
		if tween.instance == glowRing and not tween.cancelled then return true end
	end
	return false
end
check("glow_loops_on_home", glowing())
Harness.click(find("Nav_Shop"))
check("shop_opens_with_shade", gui.ShopPage.Visible and background.MotifShade.Visible)
check("nav_marks_open_page", same(find("Nav_Shop").BackgroundColor3, P.jungle) and same(find("Nav_Settings").BackgroundColor3, P.slab)
	and same(find("Nav_Shop").TextColor3, P.white))
check("glow_paused_under_page", not glowing())
check("open_page_takes_clicks", gui.ShopPage.Active == true and gui.ShopPage.ZIndex > background.ZIndex)
Harness.click(gui.ShopPage:FindFirstChild("CloseButton", true))
check("close_clears_shade_and_selection", not background.MotifShade.Visible and same(find("Nav_Shop").BackgroundColor3, P.slab))
check("glow_resumes", glowing())

-- Buy button keeps its handler and its green face
Harness.click(find("Product_double_jump").BuyButton)
check("buy_still_fires", calls.buy[#calls.buy] == "double_jump")
check("buy_face_jungle", same(find("Product_double_jump").BuyButton.BackgroundColor3, P.jungle))

-- Toggles repaint from their text (ON = leaf, OFF = paper)
local music = find("Toggle_Music")
check("toggle_on_leaf", same(music.BackgroundColor3, P.leaf))
Harness.click(music)
check("toggle_off_paper", same(music.BackgroundColor3, P.quiet) and string.find(music.Text, "OFF", 1, true) ~= nil)
Harness.click(music)
check("toggle_back_on", same(music.BackgroundColor3, P.leaf))

-- Hover on a skinned button: UITheme's own recolour stands down, the kit face stays
play.MouseEnter:Fire()
play.MouseLeave:Fire()
check("hover_keeps_amber", same(play.BackgroundColor3, P.amber))

-- Second build is independent
local second = Harness.Mock.node("Folder", {Name = "PlayerGui2"})
local okSecond = pcall(MainMenu.build, second, handlers, state)
check("second_build", okSecond and second:FindFirstChild("MainMenu") ~= nil and #Skin.errors == 0)

-- Reduced motion: no tweens at all (loops, press squash, page settle)
local calm = Harness.new({reducedMotion = true})
local calmGui = calm.menu().build(calm.playerGui, (Harness.handlers()), Harness.state())
Harness.click(calmGui:FindFirstChild("Nav_Shop", true))
Harness.click(calmGui:FindFirstChild("PlayButton", true))
check("reduced_motion_no_tweens", #calm.tweens == 0, #calm.tweens)

-- Fallbacks: decorate throwing, and the skin missing entirely, both still give a working menu
local broken = Harness.new()
local brokenSkin = broken.skin()
brokenSkin.decorate = function() error("boom") end
local okBroken, brokenGui = pcall(broken.menu().build, broken.playerGui, (Harness.handlers()), Harness.state())
check("decorate_failure_keeps_menu", okBroken and brokenGui:FindFirstChild("PlayButton", true) ~= nil and #broken.warnings == 1, broken.warnings[1])
local plain = Harness.new()
plain.client.DigSite.Parent = nil
local plainHandlers, plainCalls = Harness.handlers()
local okPlain, plainGui = pcall(plain.menu().build, plain.playerGui, plainHandlers, Harness.state())
local plainPlay = okPlain and plainGui:FindFirstChild("PlayButton", true)
if plainPlay then Harness.click(plainPlay) end
check("missing_skin_falls_back_to_plain_theme", okPlain and plainPlay and plainCalls.play == 1
	and same(plainPlay.BackgroundColor3, rb.Color3.fromRGB(63, 169, 245)) and string.find(plain.warnings[1] or "", "unavailable", 1, true) ~= nil)

print(string.format("%s dino dig skin: %d checks, %d failed", failures == 0 and "PASS" or "FAIL", count, failures))
process.exit(failures == 0 and 0 or 1)
