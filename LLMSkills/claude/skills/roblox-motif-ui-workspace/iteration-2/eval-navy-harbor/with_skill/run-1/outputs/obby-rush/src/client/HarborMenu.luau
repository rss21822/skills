--!nocheck
-- HarborMenu: dresses the main menu as a navy ship at a night harbour.
--
--   * Background  the harbour at night: stars, moon, far shore with cranes and lit windows, a red and
--                 white lighthouse whose beam sweeps slowly, reflections and wave lines on the water.
--   * TopBar      the ship's brass nameplate ("OBBY RUSH") with an anchor medallion; the coin count
--                 sits behind a brass porthole.
--   * PlayButton  a red signal flag with a canvas hoist tape and brass grommets, bent onto a white
--                 rope halyard: "出航" (set sail). The cloth ripples slowly.
--   * NavBar      a dressing line of signal flags (S / N / X / C) hung from a rope; the open page's
--                 flag gets a red edge.
--   * Pages       navy serge with the three white stripes of a sailor collar, a red scarf knot, the
--                 page's signal flag and a brass rule under the heading.
--   * Shop        products are canvas cargo tags with a brass eyelet and rope tie, price beside a
--                 brass coin, a red "購入" flag button.
--   * Settings    navy rows with white piping and a brass deck lamp that is lit when ON.
--
-- Presentation only: every name, parent, callback and enabled rule built by MainMenu stays as is.
-- Decorations are named "Harbor*", are Frames/TextLabels with Active = false and never buttons (the one
-- exception is HarborScrim, the modal backdrop, which sinks clicks like the opaque pages do).
-- Motion: two slow loops (lighthouse beam, flag ripple), none under reduced motion, paused while the
-- menu is disabled.
local Menu = {}

local FLAGS = {Shop = "S", Inventory = "N", Quests = "X", Settings = "C"}
local CAPTIONS = {Shop = "SHIP'S STORE", Inventory = "SEA BAG", Quests = "ORDERS OF THE DAY", Settings = "SHIP SETTINGS"}

-- Deterministic scatter (no Random needed): 0..1
local function hash(i, k)
	local v = math.sin(i * k) * 43758.5453
	return v - math.floor(v)
end

local function commas(value)
	local text = tostring(math.floor(tonumber(value) or 0))
	local sign, digits = string.match(text, "^(-?)(%d+)$")
	if not digits then return text end
	local out = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then out = string.sub(out, 2) end
	return sign .. out
end

local function padding(object, left, right, top, bottom)
	local pad = object:FindFirstChild("HarborPadding") or Instance.new("UIPadding")
	pad.Name = "HarborPadding"
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, left or 0), UDim.new(0, right or 0)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, top or 0), UDim.new(0, bottom or 0)
	pad.Parent = object
	return pad
end

-- A decoration layer covering the whole of a padded object (UIPadding also moves children).
local function fullLayer(parts, object, name, left, right, top, bottom)
	return parts:frame(object, name, {
		Position = UDim2.fromOffset(-(left or 0), -(top or 0)),
		Size = UDim2.new(1, (left or 0) + (right or 0), 1, (top or 0) + (bottom or 0)),
	})
end

local function viewport()
	local ok, size = pcall(function() return workspace.CurrentCamera.ViewportSize end)
	return ok and size or Vector2.new(1280, 720)
end

-- Background: the harbour at night ------------------------------------------------------------------
local HORIZON = 0.63

local function harbour(ctx, background)
	local P, parts, kit = ctx.P, ctx.parts, ctx.kit
	background.BackgroundColor3 = P.white -- the sky gradient below carries the colour
	background.BackgroundTransparency = 0
	local sky = Instance.new("UIGradient")
	sky.Name = "HarborSky"
	sky.Rotation = 90
	sky.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(5, 11, 28)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(12, 27, 60)),
		ColorSequenceKeypoint.new(HORIZON - 0.002, Color3.fromRGB(30, 50, 92)),
		ColorSequenceKeypoint.new(HORIZON, P.sea),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 10, 24)),
	})
	sky.Parent = background

	local scene = parts:frame(background, "HarborScene", {Size = UDim2.fromScale(1, 1), ZIndex = 0})
	-- stars
	for i = 1, 44 do
		local size = hash(i, 3.7) > 0.8 and 3 or 2
		parts:frame(scene, "HarborStar", {AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.02 + hash(i, 12.9898) * 0.96, 0.03 + hash(i, 78.233) * (HORIZON - 0.14)),
			Size = UDim2.fromOffset(size, size), BackgroundColor3 = P.ink, BackgroundTransparency = 0.25 + hash(i, 5.1) * 0.5})
	end
	-- moon, its halo and its path on the water
	local moonX = 0.72
	parts:circle(scene, "HarborMoonHalo", 170, P.ink, {Position = UDim2.fromScale(moonX, 0.25), BackgroundTransparency = 0.93})
	parts:circle(scene, "HarborMoon", 58, P.ink, {Position = UDim2.fromScale(moonX, 0.25), BackgroundTransparency = 0.06})
	for i = 0, 6 do
		parts:frame(scene, "HarborMoonPath", {AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(moonX, (i % 2 == 0) and -4 or 5, HORIZON + 0.025 + i * 0.045, 0),
			Size = UDim2.fromOffset(70 - i * 8, 2), BackgroundColor3 = P.ink, BackgroundTransparency = 0.55 + i * 0.05})
	end
	-- far shore: warehouses with lit windows, and two gantry cranes with red warning lights
	local shore = Color3.fromRGB(7, 15, 36)
	parts:frame(scene, "HarborShore", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, HORIZON),
		Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = shore, BackgroundTransparency = 0})
	local x = 0.0
	local i = 0
	while x < 0.7 do
		i += 1
		local w = 0.02 + hash(i, 9.1) * 0.035
		local h = 10 + math.floor(hash(i, 4.3) * 26)
		local block = parts:frame(scene, "HarborShed", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(x, HORIZON),
			Size = UDim2.new(w, 0, 0, h), BackgroundColor3 = shore, BackgroundTransparency = 0})
		for j = 1, 2 do
			if hash(i * 7 + j, 2.9) > 0.45 then
				local wx = 0.2 + hash(i * 3 + j, 6.7) * 0.6
				parts:frame(block, "HarborWindow", {Position = UDim2.new(wx, 0, 0, 4 + j * 5), Size = UDim2.fromOffset(2, 2),
					BackgroundColor3 = P.lamp, BackgroundTransparency = 0.15})
				-- the light's reflection on the water
				parts:frame(scene, "HarborReflection", {AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(x + w * wx, 0, HORIZON, 4 + j * 3), Size = UDim2.fromOffset(2, 8 + math.floor(hash(i + j, 1.3) * 20)),
					BackgroundColor3 = P.lamp, BackgroundTransparency = 0.72})
			end
		end
		x += w + 0.004
	end
	for index, cx in ipairs({0.14, 0.47}) do
		local crane = parts:frame(scene, "HarborCrane", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(cx, HORIZON), Size = UDim2.fromOffset(64, 70)})
		for _, leg in ipairs({0.25, 0.75}) do
			parts:frame(crane, "Leg", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(leg, 1), Size = UDim2.new(0, 3, 0.72, 0), BackgroundColor3 = shore, BackgroundTransparency = 0})
		end
		parts:frame(crane, "Boom", {Position = UDim2.new(index == 1 and -0.45 or 0.1, 0, 0.24, 0), Size = UDim2.new(1.35, 0, 0, 3), BackgroundColor3 = shore, BackgroundTransparency = 0})
		parts:frame(crane, "Cab", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(16, 9), BackgroundColor3 = shore, BackgroundTransparency = 0})
		parts:circle(crane, "HarborWarningLight", 4, P.primary, {Position = UDim2.fromScale(0.5, 0.16)})
	end
	-- breakwater and lighthouse (red and white bands, brass lamp room)
	parts:frame(scene, "HarborBreakwater", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0.74, 0, HORIZON, 3),
		Size = UDim2.new(0.26, 0, 0, 7), BackgroundColor3 = shore, BackgroundTransparency = 0})
	local lighthouse = parts:frame(scene, "HarborLighthouse", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.9, 0, HORIZON, -3), Size = UDim2.fromOffset(40, 120)})
	local tower = parts:frame(lighthouse, "Tower", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(18, 88), BackgroundTransparency = 0, BackgroundColor3 = P.white})
	kit:stripes(tower, P.primary, P.canvas, 6, 90)
	parts:frame(lighthouse, "Gallery", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -88), Size = UDim2.fromOffset(28, 4), BackgroundColor3 = P.brassDark, BackgroundTransparency = 0})
	local lampRoom = parts:frame(lighthouse, "LampRoom", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -92), Size = UDim2.fromOffset(16, 13), BackgroundColor3 = P.brass, BackgroundTransparency = 0})
	parts:frame(lampRoom, "Glass", {Position = UDim2.fromOffset(3, 2), Size = UDim2.new(1, -6, 1, -4), BackgroundColor3 = P.lamp, BackgroundTransparency = 0})
	parts:frame(lighthouse, "Roof", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -105), Size = UDim2.fromOffset(20, 6), BackgroundColor3 = P.primary, BackgroundTransparency = 0})
	parts:circle(lighthouse, "LampHalo", 46, P.lamp, {Position = UDim2.new(0.5, 0, 1, -98), BackgroundTransparency = 0.8})
	-- the beam: a pivot centred on the lamp, beams in its left half, rotated slowly
	local beamLength = 560
	local pivot = parts:frame(scene, "HarborBeam", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.9, 0, HORIZON, -101),
		Size = UDim2.fromOffset(beamLength * 2, 2), Rotation = -6})
	for _, beam in ipairs({{64, 0.8}, {34, 0.62}, {12, 0.45}}) do
		local ray = parts:frame(pivot, "Ray", {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(0.5, 0, 0, beam[1]), BackgroundColor3 = P.lamp, BackgroundTransparency = 0})
		local fade = Instance.new("UIGradient")
		fade.Name = "HarborBeamFade"
		fade.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.55, 0.96), NumberSequenceKeypoint.new(1, beam[2])})
		fade.Parent = ray
		parts.round(ray, UDim.new(0.5, 0))
	end
	ctx.keep(kit:loop(pivot, {Rotation = 8}, 4.8))
	-- wave lines
	for w = 1, 18 do
		parts:frame(scene, "HarborWave", {AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.04 + hash(w, 21.7) * 0.92, HORIZON + 0.03 + hash(w, 33.1) * (0.95 - HORIZON)),
			Size = UDim2.fromOffset(30 + math.floor(hash(w, 8.8) * 90), (w % 3 == 0) and 2 or 1),
			BackgroundColor3 = P.ink, BackgroundTransparency = 0.84})
	end
	return scene
end

-- Top bar: nameplate and porthole ---------------------------------------------------------------------
local function topBar(ctx, refs, state)
	local P, parts, kit = ctx.P, ctx.parts, ctx.kit
	local top = refs.top
	top.Position = UDim2.new(0, 16, 0, 0)
	kit:clearTopbar(top) -- below Roblox's menu / chat buttons (background stays full-bleed)
	top.BackgroundTransparency = 1
	local edge = top:FindFirstChild("MotifEdge") or top:FindFirstChildOfClass("UIStroke")
	if edge then edge.Transparency = 1 end

	local title = refs.title
	title.AnchorPoint = Vector2.new(0, 0.5)
	title.Position = UDim2.new(0, 30, 0.5, 0)
	title.Size = UDim2.fromOffset(250, 50)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextSize = 30
	title.TextColor3 = P.outline
	kit:setFont(title, "display")
	parts:brassPlate(title, 3)
	kit:fitHeading(title, 30, 16)
	-- anchor medallion riveted over the plate's left end
	local medal = parts:circle(top, "HarborMedallion", 60, P.brass, {Position = UDim2.new(0, 30, 0.5, 0)})
	parts.border(medal, P.brassDark, 2)
	local face = parts:circle(medal, "Face", 46, P.paper, {Position = UDim2.fromScale(0.5, 0.5)})
	parts.border(face, P.brassDark, 1.5)
	parts:anchor(face, "HarborAnchor", 30, P.canvas, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52)})

	local coins = refs.coins
	coins.AnchorPoint = Vector2.new(1, 0.5)
	coins.Position = UDim2.new(1, -4, 0.5, 0)
	coins.Size = UDim2.fromOffset(170, 46)
	coins.BackgroundColor3 = P.paper
	coins.BackgroundTransparency = 0
	coins.TextXAlignment = Enum.TextXAlignment.Right
	coins.TextSize = 24
	coins.TextColor3 = P.ink
	coins.TextWrapped = false
	kit:setFont(coins, "strong")
	parts.round(coins)
	parts.border(coins, P.brass, 3)
	padding(coins, 0, 20, 0, 0)
	-- the coin count reads through a brass porthole (drawn: 🪙 would be a box in Roblox)
	local porthole, glass = parts:porthole(top, "HarborPorthole", 62, {Position = UDim2.new(1, -174, 0.5, 0)})
	parts:coin(glass, "HarborCoin", 26, {Position = UDim2.fromScale(0.5, 0.52)})
	-- keep the count tidy if another script writes "🪙 1300" into it
	local function tidy()
		local digits = string.match(coins.Text or "", "%-?[%d,]+")
		local wanted = digits and commas((string.gsub(digits, ",", ""))) or nil
		if wanted and coins.Text ~= wanted then coins.Text = wanted end
	end
	tidy()
	coins:GetPropertyChangedSignal("Text"):Connect(tidy)
	return porthole
end

-- PLAY: the red signal flag on its halyard ---------------------------------------------------------
local function ctaFlag(ctx, refs)
	local P, parts, kit, Skin = ctx.P, ctx.parts, ctx.kit, ctx.Skin
	local play = refs.play
	play.Size = UDim2.fromOffset(300, 88)
	play.Text = "出航"
	play.TextSize = 40
	Skin.styleButton(play, {role = "primary", corner = 2})
	kit:setFont(play, "title")
	local padL, padT = 16, 16
	padding(play, padL, 0, padT, 0)
	-- the cloth ripples: soft bands of a UIGradient drift across the flag (multiplies the white type
	-- by at most 8%, so it stays readable)
	local ripple = Instance.new("UIGradient")
	ripple.Name = "HarborRipple"
	ripple.Rotation = 18
	local shade = Color3.fromRGB(226, 226, 226)
	ripple.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, P.white), ColorSequenceKeypoint.new(0.2, shade), ColorSequenceKeypoint.new(0.42, P.white),
		ColorSequenceKeypoint.new(0.64, shade), ColorSequenceKeypoint.new(0.86, P.white), ColorSequenceKeypoint.new(1, shade),
	})
	ripple.Offset = Vector2.new(-0.12, 0)
	ripple.Parent = play
	ctx.keep(kit:loop(ripple, {Offset = Vector2.new(0.12, 0)}, 3.4))

	local cloth = fullLayer(parts, play, "HarborCloth", padL, 0, padT, 0)
	-- halyard: white rope running past the hoist, with a brass ring at each end
	parts:rope(cloth, "HarborHalyard", 176, 5, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Rotation = 90})
	for _, y in ipairs({-44, 132}) do
		local ring = parts:circle(cloth, "HarborRing", 12, P.brass, {Position = UDim2.new(0, 8, 0, y), BackgroundTransparency = 1})
		parts.border(ring, P.brass, 3)
	end
	-- canvas hoist tape with two brass grommets
	local tape = parts:frame(cloth, "HarborHoistTape", {Size = UDim2.new(0, 16, 1, 0), BackgroundColor3 = P.canvas, BackgroundTransparency = 0})
	parts:frame(tape, "Stitch", {Position = UDim2.new(1, -3, 0, 3), Size = UDim2.new(0, 1, 1, -6), BackgroundColor3 = P.ropeShade, BackgroundTransparency = 0})
	for _, y in ipairs({0.2, 0.8}) do
		local grommet = parts:circle(tape, "HarborGrommet", 11, P.brass, {Position = UDim2.fromScale(0.5, y)})
		parts.border(grommet, P.brassDark, 1)
		parts:circle(grommet, "Hole", 4, P.outline, {Position = UDim2.fromScale(0.5, 0.5)})
	end
	-- kicker so "出航" is never mistaken for flavour text
	local kicker = parts:frame(cloth, "HarborKicker", {Position = UDim2.fromOffset(16, 9), Size = UDim2.new(1, -16, 0, 16)})
	local text = Instance.new("TextLabel")
	text.Name = "Label"
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Text = "▶  PLAY"
	text.TextSize = 15
	text.TextColor3 = P.canvas
	text.TextTransparency = 0.1
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.Active = false
	kit:setFont(text, "display")
	text.Parent = kicker
	return play
end

-- Nav: flags on a dressing line ----------------------------------------------------------------------
local NAV_W, NAV_GAP = 141, 16

local function navFlags(ctx, refs)
	local P, parts, kit, Skin = ctx.P, ctx.parts, ctx.kit, ctx.Skin
	refs.navLayout.Padding = UDim.new(0, NAV_GAP)
	refs.navLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	-- the line itself lives beside the NavBar (a UIListLayout would treat it as a fifth item)
	ctx.dressLine = parts:rope(refs.background, "HarborDressLine", 700, 6, {AnchorPoint = Vector2.new(0.5, 0.5)})
	ctx.shackles = {}
	for _, side in ipairs({-1, 1}) do
		local ring = parts:circle(refs.background, "HarborShackle", 14, P.brass, {BackgroundTransparency = 1})
		parts.border(ring, P.brass, 3)
		table.insert(ctx.shackles, {ring, side})
	end
	ctx.navFlags = {}
	for id, button in pairs(refs.navButtons) do
		button.TextYAlignment = Enum.TextYAlignment.Bottom
		Skin.styleButton(button, {role = "plain", corner = 4})
		kit:setFont(button, "title")
		ctx.navFlags[id] = parts:flag(button, "HarborFlag", FLAGS[id], {AnchorPoint = Vector2.new(0.5, 0)})
		-- toggles bending the card onto the rope
		for _, tx in ipairs({0.22, 0.78}) do
			parts:frame(button, "HarborToggle", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(tx, 0, 0, 0), Size = UDim2.fromOffset(2, 11), BackgroundColor3 = P.rope, BackgroundTransparency = 0})
			local ring = parts:circle(button, "HarborToggleRing", 6, P.brass, {Position = UDim2.new(tx, 0, 0, 0)})
			parts.border(ring, P.brassDark, 1)
		end
	end
end

-- Pages: sailor collars --------------------------------------------------------------------------------
local function collarPage(ctx, id, page, heading, close)
	local P, parts, kit, Skin = ctx.P, ctx.parts, ctx.kit, ctx.Skin
	page.AnchorPoint = Vector2.new(0.5, 0)
	page.ZIndex = 3
	page.Active = true -- an opaque panel: clicks must not fall through to PLAY underneath
	local constraint = Instance.new("UISizeConstraint")
	constraint.Name = "HarborPageSize"
	constraint.MaxSize = Vector2.new(820, 640)
	constraint.MinSize = Vector2.new(420, 0)
	constraint.Parent = page
	Skin.stylePanel(page, {edge = P.outline, thickness = 2})
	parts:collar(page, {8, 14, 20}, P.canvas, 2)
	parts:neckerchief(page, {Position = UDim2.new(0.5, 0, 0, -12)})

	local part = {heading = heading, close = close}
	part.flag = parts:flag(page, "HarborFlag", FLAGS[id])
	heading.Size = UDim2.new(1, -94 - 150, 0, 34)
	heading.TextColor3 = P.ink
	heading.TextYAlignment = Enum.TextYAlignment.Center
	heading.TextWrapped = false
	kit:setFont(heading, "title")
	local caption = Instance.new("TextLabel")
	caption.Name = "HarborCaption"
	caption.BackgroundTransparency = 1
	caption.Position = UDim2.fromOffset(95, 62)
	caption.Size = UDim2.new(1, -95 - 150, 0, 16)
	caption.Text = CAPTIONS[id] or ""
	caption.TextSize = 14
	caption.TextColor3 = P.brass
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Active = false
	kit:setFont(caption, "display")
	caption.Parent = page
	part.caption = caption
	-- brass rule under the heading
	part.rule = parts:frame(page, "HarborRule", {Size = UDim2.new(1, -60, 0, 2), BackgroundColor3 = P.brass, BackgroundTransparency = 0})
	part.ruleShade = parts:frame(page, "HarborRuleShade", {Size = UDim2.new(1, -60, 0, 1), BackgroundColor3 = P.brassDark, BackgroundTransparency = 0})
	Skin.styleButton(close, {role = "ghost"})
	close.TextSize = 18
	kit:setFont(close, "title")
	ctx.pageParts[id] = part
end

local function shop(ctx, refs)
	local P, parts, kit, Skin = ctx.P, ctx.parts, ctx.kit, ctx.Skin
	local list = refs.list
	list.ScrollBarImageColor3 = P.brass
	list.ScrollBarThickness = 6
	padding(list, 16, 10, 2, 2) -- room for the rope ties on the left and the scroll bar on the right
	refs.listLayout.Padding = UDim.new(0, 12)
	for _, entry in ipairs(refs.rows) do
		local row = entry.row
		row.Size = UDim2.new(1, 0, 0, 70)
		Skin.stylePanel(row, {color = P.canvas, edge = P.canvas:Lerp(P.outline, 0.3), corner = 4})
		-- cargo tag: rope tie through a brass eyelet
		parts:rope(row, "HarborTie", 30, 4, {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -14, 0.5, 0)})
		local eyelet = parts:circle(row, "HarborEyelet", 20, P.brass, {Position = UDim2.new(0, 20, 0.5, 0)})
		parts.border(eyelet, P.brassDark, 1.5)
		parts:circle(eyelet, "Hole", 8, P.paper, {Position = UDim2.fromScale(0.5, 0.5)})
		entry.name.Position = UDim2.fromOffset(44, 0)
		entry.name.Size = UDim2.new(0.5, -44, 1, 0)
		entry.name.TextColor3 = P.onLight
		entry.name.TextSize = 19
		entry.name.TextYAlignment = Enum.TextYAlignment.Center
		kit:setFont(entry.name, "strong")
		parts:coin(row, "HarborCoin", 22, {Position = UDim2.new(0.5, 14, 0.5, 0)})
		entry.price.Text = commas(entry.product.price)
		entry.price.Position = UDim2.new(0.5, 32, 0, 0)
		entry.price.Size = UDim2.new(0.22, -32, 1, 0)
		entry.price.TextColor3 = P.onLight
		entry.price.TextSize = 19
		entry.price.TextYAlignment = Enum.TextYAlignment.Center
		kit:setFont(entry.price, "strong")
		-- perforation between the tag and its stub
		for d = 0, 6 do
			parts:frame(row, "HarborPerforation", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(1, -132, 0, 8 + d * 8),
				Size = UDim2.fromOffset(3, 3), BackgroundColor3 = P.canvas:Lerp(P.outline, 0.35), BackgroundTransparency = 0})
		end
		entry.buy.Position = UDim2.new(1, -116, 0.5, -24)
		Skin.styleButton(entry.buy, {role = "primary"})
		entry.buy.TextSize = 20
		kit:setFont(entry.buy, "title")
	end
end

local function settings(ctx, refs)
	local P, parts, kit, Skin = ctx.P, ctx.parts, ctx.kit, ctx.Skin
	for _, entry in ipairs(refs.toggles) do
		local toggle = entry.button
		toggle.Size = UDim2.new(1, -60, 0, 58)
		toggle.TextXAlignment = Enum.TextXAlignment.Left
		toggle.TextSize = 20
		Skin.styleButton(toggle, {role = "quiet"})
		kit:setFont(toggle, "strong")
		local padL, padR = 20, 72
		padding(toggle, padL, padR, 0, 0)
		local layer = fullLayer(parts, toggle, "HarborLampLayer", padL, padR, 0, 0)
		local _, setLamp = parts:lamp(layer, "HarborLamp", 22, {Position = UDim2.new(1, -36, 0.5, 0)})
		local function sync()
			local text = string.upper(toggle.Text or "")
			setLamp(string.find(text, "ON", 1, true) ~= nil and string.find(text, "OFF", 1, true) == nil)
		end
		sync()
		toggle:GetPropertyChangedSignal("Text"):Connect(sync)
	end
end

local function emptyPages(ctx, refs)
	local P, parts, kit = ctx.P, ctx.parts, ctx.kit
	for id, label in pairs(refs.empties) do
		label.Size = UDim2.new(1, -60, 0, 28)
		label.TextColor3 = P.muted
		kit:setFont(label, "body")
		local page = refs.pages[id]
		local props = {AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -44, 1, -40)}
		if id == "Quests" then
			ctx.pageParts[id].emblem = parts:wheel(page, "HarborEmblem", 150, P.quiet, props)
		else
			ctx.pageParts[id].emblem = parts:anchor(page, "HarborEmblem", 150, P.quiet, props)
		end
	end
end

-- Geometry for the current screen. Regular: the page sits under the TopBar. Compact (height < 560,
-- phones held sideways): smaller flag cards, the page starts right under Roblox's bar and its header
-- tightens so the list keeps room for rows.
local function layout(ctx, refs)
	local compact = viewport().Y < 560
	local bar = ctx.kit:topbar()
	local cardH = compact and 58 or 76
	local reserve = 20 + cardH + 12 + (compact and 10 or 20) -- nav margin, flag cards, rope, gap

	refs.nav.Size = UDim2.fromOffset(NAV_W * 4 + NAV_GAP * 3, cardH + 4)
	refs.nav.Position = UDim2.new(0.5, 0, 1, -20)
	local lineY = -20 - cardH - 12
	ctx.dressLine.Position = UDim2.new(0.5, 0, 1, lineY)
	for _, entry in ipairs(ctx.shackles) do
		entry[1].Position = UDim2.new(0.5, entry[2] * 352, 1, lineY)
	end
	for id, button in pairs(refs.navButtons) do
		button.Size = UDim2.fromOffset(NAV_W, cardH)
		button.TextSize = compact and 15 or 18
		padding(button, 0, 0, 0, compact and 5 or 7)
		local flag = ctx.navFlags[id]
		flag.Position = UDim2.new(0.5, 0, 0, compact and 6 or 8)
		flag.Size = compact and UDim2.fromOffset(42, 28) or UDim2.fromOffset(56, 38)
	end

	refs.play.Position = UDim2.new(0.5, 0, compact and 0.58 or 0.55, 0)

	local topY = compact and (bar.height + 8) or (bar.height + 8 + 64 + 12)
	local headerY = compact and 22 or 28
	local contentY = compact and 84 or 104
	for id, pageFrame in pairs(refs.pages) do
		pageFrame.Position = UDim2.new(0.5, 0, 0, topY)
		pageFrame.Size = UDim2.new(0.64, 0, 1, -(topY + reserve))
		local part = ctx.pageParts[id]
		part.flag.Position = UDim2.fromOffset(34, headerY + (compact and 4 or 6))
		part.flag.Size = compact and UDim2.fromOffset(40, 28) or UDim2.fromOffset(46, 32)
		part.heading.Position = UDim2.fromOffset(compact and 86 or 94, headerY)
		part.heading.TextSize = compact and 24 or 28
		part.caption.Visible = not compact
		local ruleY = contentY - (compact and 8 or 14)
		part.rule.Position = UDim2.fromOffset(30, ruleY)
		part.ruleShade.Position = UDim2.fromOffset(30, ruleY + 2)
		part.close.Position = UDim2.new(1, -130, 0, headerY + 2)
		if part.emblem then part.emblem.Visible = not compact end
	end
	refs.list.Position = UDim2.fromOffset(30, contentY)
	refs.list.Size = UDim2.new(1, -60, 1, -(contentY + 22))
	for _, entry in ipairs(refs.toggles) do
		entry.button.Position = UDim2.fromOffset(30, contentY + (entry.index - 1) * (compact and 64 or 70))
	end
	for _, label in pairs(refs.empties) do
		label.Position = UDim2.fromOffset(30, contentY + 4)
	end
	ctx.scrim.Position = UDim2.fromOffset(0, topY - 8)
	ctx.scrim.Size = UDim2.new(1, 0, 1, -(topY - 8) - reserve)
end

-- Entry ---------------------------------------------------------------------------------------------------
function Menu.dress(refs, Skin, state)
	local kit = Skin.kit
	local loops = {}
	local ctx = {Skin = Skin, kit = kit, P = Skin.P, parts = Skin.parts, pageParts = {}, keep = function(tween)
		if tween then table.insert(loops, tween) end
	end}
	local gui = refs.gui
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui:SetAttribute("Skin", Skin.name)

	harbour(ctx, refs.background)
	topBar(ctx, refs, state)
	ctaFlag(ctx, refs)
	navFlags(ctx, refs)
	for id, pageFrame in pairs(refs.pages) do
		collarPage(ctx, id, pageFrame, refs.pageTitles[id], refs.closeButtons[id])
	end
	shop(ctx, refs)
	settings(ctx, refs)
	emptyPages(ctx, refs)

	-- modal wash over the harbour while a page is open (top bar and nav stay bright). Like the page it
	-- sinks clicks, so the dimmed PLAY flag cannot be pressed through it.
	local scrim = ctx.parts:frame(gui, "HarborScrim", {BackgroundColor3 = ctx.P.dim, BackgroundTransparency = 0.35, ZIndex = 2, Visible = false})
	scrim.Active = true
	local wash = Instance.new("UIGradient")
	wash.Rotation = 90
	wash.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.1)})
	wash.Parent = scrim
	ctx.scrim = scrim

	layout(ctx, refs)
	pcall(function()
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function() pcall(layout, ctx, refs) end)
	end)

	local function refresh()
		local any = false
		for id, pageFrame in pairs(refs.pages) do
			local open = pageFrame.Visible == true
			any = any or open
			local button = refs.navButtons[id]
			if button then Skin.styleButton(button, {selected = open, corner = 4}) end
		end
		scrim.Visible = any
	end
	for _, pageFrame in pairs(refs.pages) do
		pageFrame:GetPropertyChangedSignal("Visible"):Connect(refresh)
	end
	refresh()

	-- loops stop while the menu is hidden
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		for _, tween in ipairs(loops) do
			pcall(function()
				if gui.Enabled then tween:Play() else tween:Pause() end
			end)
		end
	end)
	return gui
end

return Menu
