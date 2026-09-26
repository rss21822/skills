--!nocheck
-- Retro Toy Box skin test. Run from the project folder:  lune run tests/test_menu_skin.luau
-- Complements test_main_menu.luau (the name/behaviour contract): checks that the skin really applies,
-- keeps every instance the plain build makes at the same path, leaves no old navy colour, paints the
-- designed faces (and keeps them through the theme's hover handlers), follows page/toggle state,
-- honours reduced motion, and falls back to the plain menu when a stage fails.
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

-- Mock DataModel (same mounting as test_main_menu.luau) --------------------------------------------
local game = node("DataModel", {Name = "Game"})
local replicated = node("Folder", {Name = "ReplicatedStorage", Parent = game})
local starterPlayer = node("Folder", {Name = "StarterPlayer", Parent = game})
local starterScripts = node("Folder", {Name = "StarterPlayerScripts", Parent = starterPlayer})
local localPlayer = {Name = "Tester", UserId = 1}
local tweenService = Mock.tweenService()
local guiService = {ReducedMotionEnabled = false}
local services = {
	ReplicatedStorage = replicated, StarterPlayer = starterPlayer, Players = {LocalPlayer = localPlayer},
	RunService = {Heartbeat = Mock.signal(), RenderStepped = Mock.signal(), Stepped = Mock.signal(),
		IsClient = function() return true end, IsStudio = function() return false end},
	TweenService = tweenService, GuiService = guiService,
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
mount("src/shared", node("Folder", {Name = "Shared", Parent = replicated}))
mount("src/client", node("Folder", {Name = "Client", Parent = starterScripts}))

local client = starterScripts.Client
local MainMenu = requireModule(client.MainMenu)
local Theme = requireModule(replicated.Shared.UITheme)
local Skin = requireModule(client.MenuSkin.RetroToySkin)
local P, C = Skin.kit.P, Skin.kit.candies

local calls = {toggle = {}}
local handlers = {
	play = function() end, buy = function() end, navigate = function() end,
	toggle = function(id, on) table.insert(calls.toggle, {id, on}) end,
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
local function build(skin)
	local playerGui = node("Folder", {Name = "PlayerGui"})
	MainMenu.useSkin = skin
	local gui = MainMenu.build(playerGui, handlers, state)
	MainMenu.useSkin = true
	return gui, playerGui
end
local function find(root, name) return root:FindFirstChild(name, true) end
local function isMotif(object)
	local current = object
	while current do
		if string.sub(tostring(current.Name), 1, 5) == "Motif" then return true end
		current = current.Parent
	end
	return false
end
local function click(button)
	button.InputBegan:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
	button.InputEnded:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
	button.Activated:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1}, 1)
end

-- 1. The skin applies (no silent fallback) -------------------------------------------------------------
local plain = build(false)
local tweensBefore = #tweenService.created
local gui, playerGui = build(true)
check("skin_applied", find(gui, "MotifLid") ~= nil and find(gui, "MotifRobot") ~= nil and find(gui, "MotifWindow") ~= nil)
check("plain_build_has_no_skin", find(plain, "MotifLid") == nil and plain.Background.BackgroundColor3 == Theme.colors.background)
check("one_menu_per_player_gui", #playerGui:GetChildren() == 1)

-- 2. Name contract: every GuiObject / layout / ScreenGui of the plain build is at the same path.
local function paths(root, skipMotif)
	local set = {}
	for _, object in ipairs(root:GetDescendants()) do
		if not (skipMotif and isMotif(object)) and (object:IsA("GuiObject") or object:IsA("UILayout")) then
			local key = object:GetFullName() .. " <" .. object.ClassName .. ">"
			set[key] = (set[key] or 0) + 1
		end
	end
	return set
end
local plainPaths, skinnedPaths = paths(plain, false), paths(gui, true)
local missing = {}
for key, n in pairs(plainPaths) do
	if skinnedPaths[key] ~= n then table.insert(missing, key) end
end
check("same_paths_as_plain_build", #missing == 0, table.concat(missing, ", "))
local extra = {}
for key in pairs(skinnedPaths) do
	if plainPaths[key] == nil then table.insert(extra, key) end
end
check("skin_adds_only_motif_named_instances", #extra == 0, table.concat(extra, ", "))
check("texts_unchanged", find(gui, "CoinLabel").Text == find(plain, "CoinLabel").Text
	and find(gui, "PlayButton").Text == find(plain, "PlayButton").Text
	and find(find(gui, "Product_speed_coil"), "Price").Text == find(find(plain, "Product_speed_coil"), "Price").Text)

-- 3. No old navy / accent colour left on a visible surface, text or edge.
local old = {}
for key, value in pairs(Theme.colors) do
	if key ~= "danger" and key ~= "success" then old[key] = value end
end
local leftovers = {}
for _, object in ipairs(gui:GetDescendants()) do
	for _, property in ipairs({"BackgroundColor3", "TextColor3", "Color"}) do
		local value = object[property]
		if typeof(value) == "Color3" then
			local hidden = (property == "BackgroundColor3" and object.BackgroundTransparency == 1)
				or (property == "TextColor3" and object.TextTransparency == 1)
				or (property == "Color" and object.Enabled == false)
			if not hidden then
				for key, colour in pairs(old) do
					if value == colour then table.insert(leftovers, object:GetFullName() .. "." .. property .. "=" .. key) end
				end
			end
		end
	end
end
check("no_old_theme_colours", #leftovers == 0, table.concat(leftovers, ", "))
local doubled = {}
for _, object in ipairs(gui:GetDescendants()) do
	local borders = 0
	for _, child in ipairs(object:GetChildren()) do
		if child.ClassName == "UIStroke" and child.ApplyStrokeMode ~= rb.Enum.ApplyStrokeMode.Contextual and child.Enabled ~= false then borders += 1 end
	end
	if borders > 1 then table.insert(doubled, object:GetFullName()) end
end
check("one_border_stroke_per_object", #doubled == 0, table.concat(doubled, ", "))

-- 4. Faces and text colours.
local play = find(gui, "PlayButton")
check("play_is_primary_pill", play.BackgroundColor3 == P.primary and play.MotifEdge.Thickness == 4 and play.UICorner.CornerRadius == rb.UDim.new(1, 0))
check("play_text_outlined_white", play.TextColor3 == P.white and play.MotifTextOutline.Transparency == 0)
check("flat_print_no_gloss", find(gui, "MotifGloss") == nil)
check("play_has_halo_shadow_star", find(gui, "MotifPlayHalo") ~= nil and find(gui, "MotifShadow_PlayButton") ~= nil and play:FindFirstChild("MotifPlayStar") ~= nil)
local tileFaces, distinct = {}, true
for _, id in ipairs({"Shop", "Inventory", "Quests", "Settings"}) do
	local tile = find(gui, "Nav_" .. id)
	for _, other in ipairs(tileFaces) do
		if other == tile.BackgroundColor3 then distinct = false end
	end
	table.insert(tileFaces, tile.BackgroundColor3)
	check("tile_" .. id .. "_icon_box_fits_emoji", tile.MotifTileIcon.Size.Y.Offset >= tile.MotifTileIcon.TextSize * 1.5)
end
check("nav_tiles_distinct_candies", distinct and tileFaces[1] == C.tincar)
local shop = find(gui, "ShopPage")
check("shop_frame_matches_shop_tile", shop.BackgroundColor3 == find(gui, "Nav_Shop").BackgroundColor3 and shop.MotifEdge.Thickness == 4)
local buy = find(find(gui, "Product_rainbow_trail"), "BuyButton")
check("buy_is_primary_with_ink_text", buy.BackgroundColor3 == P.primary and buy.TextColor3 == P.ink)
local rowA, rowB = find(gui, "Product_speed_coil"), find(gui, "Product_rainbow_trail")
check("product_rows_vary", rowA.BackgroundColor3 ~= rowB.BackgroundColor3 and rowA.MotifProductBadge ~= nil)
check("coin_emoji_not_drawn", find(gui, "CoinLabel").TextTransparency == 1 and find(gui, "MotifCoinText").Text == "1250"
	and find(gui, "MotifPriceText").Text == "300" and find(gui, "MotifCoin") ~= nil)
local coinLabel = find(gui, "CoinLabel")
coinLabel.Text = "🪙 1300"
check("coin_display_follows_label", coinLabel.MotifCoinText.Text == "1300")
check("page_title_outlined", shop.Title.TextColor3 == P.white and shop.Title.MotifTextOutline ~= nil)

-- 5. The theme's hover handler writes navy; the skin repaints the designed face.
play.MouseEnter:Fire()
check("hover_keeps_face", play.BackgroundColor3 == P.primary, play.BackgroundColor3)
play.MouseLeave:Fire()
check("leave_keeps_face", play.BackgroundColor3 == P.primary, play.BackgroundColor3)
play.InputBegan:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
check("press_sinks", near(play.MotifLip.Offset.Y, 0.05) and near(play.MotifScale.Scale, 0.94))
play.InputEnded:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
check("release_restores", near(play.MotifLip.Offset.Y, 0) and near(play.MotifScale.Scale, 1))

-- 6. Page state: dim, shadow, selected tile follow the page's Visible.
local dim = find(gui, "MotifDim")
check("dim_hidden_at_start", dim.Visible == false)
click(find(gui, "Nav_Shop"))
check("open_shows_dim_and_shadow", dim.Visible == true and find(gui, "MotifShadow_ShopPage").Visible == true)
check("open_marks_tile", find(gui, "Nav_Shop").MotifTileStar.Visible == true and find(gui, "Nav_Shop").Rotation ~= 0)
check("page_pop_settles", near(shop.MotifPop.Scale, 1))
click(shop.CloseButton)
check("close_clears_dim", dim.Visible == false and find(gui, "MotifShadow_ShopPage").Visible == false and find(gui, "Nav_Shop").Rotation == 0)

-- 7. Toggles repaint with their state.
local music = find(gui, "Toggle_Music")
check("toggle_on_face", music.BackgroundColor3 == C.gumdrop and music.MotifSwitch.BackgroundColor3 == C.ring)
click(music)
check("toggle_off_face", music.BackgroundColor3 == P.quiet and music.MotifSwitch.BackgroundColor3 == P.disabled
	and music.MotifSwitch.MotifKnob.Position.X.Scale == 0 and calls.toggle[1][2] == false)
click(music)
check("toggle_on_again", music.BackgroundColor3 == C.gumdrop and music.MotifSwitch.MotifKnob.Position.X.Scale == 1)

-- 8. Motion: loops exist normally, none under reduced motion; idempotent apply.
local function loopsSince(start)
	local n = 0
	for index = start + 1, #tweenService.created do
		local info = tweenService.created[index].info
		if info and info[4] == -1 then n += 1 end
	end
	return n
end
check("loops_when_motion_allowed", loopsSince(tweensBefore) > 0)
guiService.ReducedMotionEnabled = true
local start = #tweenService.created
local calm = build(true)
check("reduced_motion_no_loops", loopsSince(start) == 0 and find(calm, "MotifLid") ~= nil)
guiService.ReducedMotionEnabled = false
local before = #gui:GetDescendants()
check("apply_idempotent", Skin.apply(gui) == true and #gui:GetDescendants() == before)
check("apply_ignores_other_guis", Skin.apply(node("ScreenGui", {Name = "Hud"})) == false)

-- 9. A failing stage gives the plain menu, never a half-skinned one.
table.insert(Skin.stages, 5, {name = "boom", run = function() error("injected failure") end})
local fallback, fallbackGui = build(true)
table.remove(Skin.stages, 5)
local motif = 0
for _, object in ipairs(fallback:GetDescendants()) do
	if isMotif(object) then motif += 1 end
end
check("failure_falls_back_to_plain", motif == 0 and #fallbackGui:GetChildren() == 1 and fallback.Background.BackgroundColor3 == Theme.colors.background)
check("fallback_keeps_contract", find(fallback, "PlayButton") ~= nil and find(fallback, "Product_double_jump") ~= nil and find(fallback, "Toggle_SFX") ~= nil)

print(string.format("%s retro toy skin: %d checks, %d failed", failures == 0 and "PASS" or "FAIL", count, failures))
process.exit(failures == 0 and 0 or 1)
