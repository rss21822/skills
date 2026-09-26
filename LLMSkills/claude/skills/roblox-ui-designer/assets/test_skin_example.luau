--!nocheck
-- Example Lune test for a motif skin, and the self-test of MotifSkinKit.
--   lune run test_skin_example.luau            (from this assets/ folder, or copy next to your tests)
-- In a game repo, copy lune_gui_mock.luau next to the test and point KIT at the copied kit.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local rb = require("@lune/roblox")

local here = string.match(debug.info(1, "s"), "^(.*)[/\\]") or "."
local Mock = luau.load(fs.readFile(here .. "/lune_gui_mock.luau"), {debugName = "lune_gui_mock"})()
local KIT = here .. "/MotifSkinKit.luau"

local count = 0
local function check(name, ok)
	if not ok then
		print("FAIL " .. name)
		process.exit(1)
	end
	count += 1
end
local function near(a, b) return math.abs(a - b) < 1e-3 end

local spec = {
	palette = {
		ink = "#30163A", paper = "#FFFAF2", panel = "#FFFFFF", quiet = "#F5EDFF", primary = "#FFD033",
		danger = "#F04058", success = "#26D696", muted = "#7A648A", disabled = "#E4DCEA", dim = "#401E68",
		candies = {{"bubblegum", "#FF5EA0"}, {"mint", "#26D696"}, {"sky", "#40C4FF"}},
	},
	fonts = {display = {"LuckiestGuy", "Regular"}, title = {"FredokaOne", "Bold"}, button = {"FredokaOne", "Bold"}, body = {"Nunito", "Bold"}},
	latinOnly = {display = true},
	shape = {corner = 16, panelCorner = 20, stroke = 3, lip = 6},
}

local function kitWith(reducedMotion)
	local env = Mock.environment({reducedMotion = reducedMotion})
	local Kit = luau.load(fs.readFile(KIT), {environment = env, debugName = "MotifSkinKit"})()
	return Kit, Kit.new(spec), env
end

local Kit, kit, env = kitWith(false)
local P = kit.P

-- Palette and helpers
check("hex_colours", P.ink == rb.Color3.fromRGB(48, 22, 58) and kit.candies.sky == rb.Color3.fromRGB(64, 196, 255))
check("pastels_derived_from_candies", #kit.pastels == 3 and Kit.luminance(kit.pastels[1]) > 0.82)
check("cjk_detection", Kit.cjk("プレイ") and Kit.cjk("設定") and not Kit.cjk("⚙️ SETTINGS") and not Kit.cjk("Play"))

-- Type
local label = Mock.node("TextLabel", {Text = "ショップ"})
kit:setFont(label, "display")
check("latin_only_display_swaps_for_japanese", label.FontFace.Family:find("FredokaOne") ~= nil)
label.Text = "SHOP"
kit:setFont(label, "display")
check("display_face_for_latin", label.FontFace.Family:find("LuckiestGuy") ~= nil)

-- Text colour rule
local inkColour = kit:textOn(P.paper, 18)
local white, stroke = kit:textOn(kit.candies.bubblegum, 30)
check("ink_on_light", inkColour == P.ink)
check("outlined_white_on_candy", white == P.white and stroke and stroke >= 1.5)
check("ink_on_bright_candy_at_body_size", kit:textOn(P.primary, 18) == P.ink)

-- Buttons
local gui = Mock.node("ScreenGui")
local play = Mock.node("TextButton", {Name = "PlayButton", Text = "PLAY", TextSize = 36, Parent = gui, AbsoluteSize = rb.Vector2.new(260, 80)})
local state = kit:styleButton(play, {role = "primary", pill = true, emoji = "▶️"})
check("button_face_primary", play.BackgroundColor3 == P.primary)
check("button_keeps_name", play.Name == "PlayButton" and play.Parent == gui)
check("button_edge_and_lip", play.MotifEdge.Color == P.ink and play.MotifLip ~= nil and play.MotifLip.Rotation == 90)
check("big_primary_gets_outlined_white", play.TextColor3 == P.white and play.MotifTextOutline.Transparency == 0)
check("emoji_icon_box_36", play.MotifIcon.Size == rb.UDim2.fromOffset(36, 36) and play.MotifIcon.TextSize == 22)
play.InputBegan:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
check("press_sinks_lip", near(play.MotifLip.Offset.Y, 0.05) and near(play.MotifScale.Scale, 0.94))
play.InputEnded:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
check("release_restores", near(play.MotifLip.Offset.Y, 0) and near(play.MotifScale.Scale, 1))
play.Active = false
check("disabled_greys", play.BackgroundColor3 == P.disabled and play.TextColor3 == P.muted and state.enabled == false)
local plain = Mock.node("TextButton", {Name = "Row", Text = "Row", TextSize = 18, Parent = gui})
kit:styleButton(plain, {order = 1})
check("plain_rows_take_pastels_with_ink", plain.BackgroundColor3 == kit.pastels[2] and plain.TextColor3 == P.ink)

-- Surfaces
local panel = kit:panel(Mock.node("Frame", {Parent = gui}))
check("panel_paper_ink_edge", panel.BackgroundColor3 == P.paper and panel.MotifEdge.Thickness == 3)
local stripes = kit:stripes(Mock.node("Frame"), P.primary, P.paper, 10, 45)
check("stripes_twenty_keypoints", #stripes.Color.Keypoints == 20)
local heading = Mock.node("TextLabel", {Text = "Settings", TextSize = 34})
kit:fitHeading(heading, 34, 14)
check("heading_scales_down", heading.TextScaled == true and heading.MotifHeadingSize.MaxTextSize == 34)
local badge = kit:badge(gui, "Badge", "🎟️", P.primary, 52)
check("badge_icon_ratio", badge.Icon.TextSize == 29)

-- Mascot and motion
local tweensBefore = #env.game:GetService("TweenService").created
local mascot, parts = kit:mascot(gui, 60, {
	{"Body", 0.5, 0.52, 0.84, 0.86, "ink", stroke = true},
	{"EyeL", 0.37, 0.36, 0.2, 0.2, "white"},
	{"PupilL", 0.58, 0.55, 0.55, 0.55, "ink", parent = "EyeL"},
}, {blink = {"EyeL"}})
check("mascot_parts", mascot and parts.Body and parts.PupilL.Parent == parts.EyeL)
check("mascot_sways", #env.game:GetService("TweenService").created > tweensBefore)
local _, calmKit, calmEnv = kitWith(true)
calmKit:mascot(Mock.node("ScreenGui"), 60, {{"Body", 0.5, 0.5, 1, 1, "ink"}}, {})
check("reduced_motion_no_loops", #calmEnv.game:GetService("TweenService").created == 0)

-- Shape flags switch the sticker vocabulary off (pixel / luxury / horror motifs)
do
	local flatSpec = table.clone(spec)
	flatSpec.shape = {corner = 0, stroke = 1, lip = 0, gloss = false, textOutline = false, press = "none"}
	local FlatKit = luau.load(fs.readFile(KIT), {environment = Mock.environment({}), debugName = "MotifSkinKit"})()
	local flat = FlatKit.new(flatSpec)
	local b = Mock.node("TextButton", {Name = "Flat", Text = "START", TextSize = 36, AbsoluteSize = rb.Vector2.new(260, 80)})
	flat:styleButton(b, {role = "primary"})
	check("flat_has_no_gloss_or_lip", b:FindFirstChild("MotifGloss") == nil and b:FindFirstChild("MotifLip") == nil)
	check("flat_has_no_text_outline", b:FindFirstChild("MotifTextOutline") == nil)
	check("flat_square_corner_and_hairline", b.UICorner.CornerRadius == rb.UDim.new(0, 0) and b.MotifEdge.Thickness == 1)
	b.MouseEnter:Fire()
	check("flat_no_hover_squash", b.MotifScale.Scale == nil or near(b.MotifScale.Scale, 1))
	check("flat_text_picks_contrast", flat:textOn(flat.P.primary, 36) == flat.P.onLight and flat:textOn(flat.P.ink, 36) == flat.P.white)
end

-- Top bar: titles on an IgnoreGuiInset screen move below Roblox's buttons, with or without GuiService data
do
	local title = Mock.node("TextLabel", {Name = "Title", Text = "OBBY", Position = rb.UDim2.new(0.5, 0, 0, 10), Parent = gui})
	kit:clearTopbar(title)
	check("topbar_fallback_58", title.Position.Y.Offset == 10 + 58 + 8 and title.Name == "Title" and title.Parent == gui)
	local barEnv = Mock.environment({services = {GuiService = {ReducedMotionEnabled = false,
		TopbarInset = {Min = rb.Vector2.new(160, 0), Max = rb.Vector2.new(1180, 44)}}}})
	local BarKit = luau.load(fs.readFile(KIT), {environment = barEnv, debugName = "MotifSkinKit"})()
	local barKit = BarKit.new(spec)
	local label = Mock.node("TextLabel", {Name = "Coins", Position = rb.UDim2.new(0, 0, 0, 0)})
	barKit:clearTopbar(label, 4)
	check("topbar_uses_inset", label.Position.Y.Offset == 48 and barKit:topbar().left == 160)
end

-- Robustness: a bad font role or missing property must not throw
check("unknown_role_falls_back", pcall(function() kit:setFont(Mock.node("TextLabel", {Text = "x"}), "nope") end))

print(string.format("PASS motif skin kit: %d assertions", count))
