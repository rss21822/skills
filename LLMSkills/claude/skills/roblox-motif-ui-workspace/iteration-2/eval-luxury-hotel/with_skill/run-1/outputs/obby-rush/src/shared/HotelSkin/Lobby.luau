-- Grand Hotel lobby: the main menu's stage (black marble wall, chandelier, brass elevator, marble
-- floor with brass inlay) and the hotel furniture of each page (directory plaques, framed marble
-- pages with a crest, a room-service menu card, lamp switches).
--
-- Only adds children named "Hotel..." and changes presentation properties (colour, font, text size,
-- position, ZIndex). Names, parents, callbacks and Visible logic of the menu are left alone.
local Lobby = {}

-- The hotel's facilities behind each menu page (engraved in English, like hotel signage).
local CAPTIONS = {Shop = "BOUTIQUE", Inventory = "CLOAKROOM", Quests = "CONCIERGE", Settings = "RECEPTION"}
local PAGES = {"Shop", "Inventory", "Quests", "Settings"}

-- Marble veins on a fixed 1600 x 900 slab centred on the screen: {x, y, heading, steps, thickness}.
local VEINS = {
	{120, 40, 38, 22, 2}, {470, 20, 64, 18, 1.5}, {930, 90, 118, 15, 1.5}, {1260, 30, 72, 20, 2},
	{160, 520, 18, 12, 1}, {1400, 430, 152, 10, 1}, {700, 470, 36, 10, 1},
}

local function udim2Offset(base, dx, dy)
	return UDim2.new(base.X.Scale, base.X.Offset + dx, base.Y.Scale, base.Y.Offset + dy)
end

------------------------------------------------------------------------------------------------------
-- Wall, veins, panelling, sconces, floor
function Lobby.background(ctx, background)
	local P, O = ctx.P, ctx.O
	background.BackgroundColor3 = P.paper
	background.BackgroundTransparency = 0
	background.ClipsDescendants = true
	O.new("UIGradient", background, {
		Name = "HotelWallShade", Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 140, 146)),
	})

	-- Nero Marquina: thin white veins wandering diagonally, with a few branches.
	local marble = O.frame(background, {Name = "HotelMarble", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, ClipsDescendants = true})
	local slab = O.frame(marble, {
		Name = "HotelVeins", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1600, 900), ZIndex = 1,
	})
	local rand = O.random(1931)
	local function vein(x, y, heading, steps, thickness, transparency, depth)
		local base = heading
		for step = 1, steps do
			local kink = rand(0, 1) < 0.12
			heading = heading + (kink and rand(-38, 38) or rand(-13, 13))
			heading = heading + (base - heading) * 0.22
			local length = depth == 0 and rand(30, 54) or rand(14, 30)
			local nx, ny = x + math.cos(math.rad(heading)) * length, y + math.sin(math.rad(heading)) * length
			if depth == 0 and thickness >= 2 then
				O.segment(slab, x, y, nx, ny, thickness + 5, P.vein, 0.955, "HotelVeinHaze")
			end
			O.segment(slab, x, y, nx, ny, thickness, P.vein, transparency, "HotelVein")
			if depth == 0 and step % 7 == 4 then
				vein(nx, ny, heading + (rand(0, 1) < 0.5 and -1 or 1) * rand(24, 48), 6, 1, 0.87, 1)
			end
			x, y = nx, ny
		end
	end
	for _, v in ipairs(VEINS) do
		vein(v[1], v[2], v[3], v[4], v[5], v[5] >= 2 and 0.72 or (v[5] >= 1.5 and 0.78 or 0.85), 0)
	end

	-- Boiserie: two tall gold-lined wall panels framing the lobby, each with a candle sconce.
	local walls = O.frame(background, {Name = "HotelWallPanels", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1})
	for side = 0, 1 do
		local panel = O.frame(walls, {
			Name = side == 0 and "HotelPanelLeft" or "HotelPanelRight", BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(side, 0), Position = UDim2.new(side == 0 and 0.035 or 0.965, 0, 0, 158),
			Size = UDim2.new(0.18, 0, 0.76, -186), ZIndex = 1,
		})
		ctx.wallPanels = ctx.wallPanels or {}
		table.insert(ctx.wallPanels, panel)
		-- An inlaid slab: a shade deeper than the wall, framed by two brass lines.
		panel.BackgroundColor3, panel.BackgroundTransparency = P.dim, 0.3
		O.corner(panel)
		O.stroke(panel, P.goldDeep, 1)
		O.rule(panel, 9, P.goldDeep)
		local sconce = O.frame(panel, {
			Name = "HotelSconce", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 18), Size = UDim2.fromOffset(40, 64), ZIndex = 1,
		})
		for index = 1, 6 do
			O.circle(sconce, 20, 18, 160 - (index - 1) * 24, P.glow, 0.962, "HotelSconceGlow")
		end
		O.frame(sconce, {Name = "HotelSconceArm", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(20, 30), Size = UDim2.fromOffset(2, 30), BackgroundColor3 = P.gold})
		O.frame(sconce, {Name = "HotelSconceCup", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(20, 30), Size = UDim2.fromOffset(16, 4), BackgroundColor3 = P.gold})
		O.frame(sconce, {Name = "HotelSconceCandle", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(20, 28), Size = UDim2.fromOffset(4, 10), BackgroundColor3 = P.white})
		local flame = O.circle(sconce, 20, 13, 7, P.candle, 0, "HotelFlame")
		flame.Size = UDim2.fromOffset(6, 9)
		O.diamond(sconce, 6, P.gold, {Position = UDim2.fromOffset(20, 62)})
		-- Art Deco fan (sunburst) standing on the inner rule at the foot of the panel.
		local fan = O.frame(panel, {
			Name = "HotelFan", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.fromOffset(124, 62), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 1,
		})
		for _, diameter in ipairs({120, 76, 30}) do
			local arc = O.circle(fan, 62, 62, diameter, P.goldDeep, 1, "HotelFanArc")
			O.stroke(arc, P.goldDeep, 1)
		end
		for ray = 0, 6 do
			local angle = math.rad(-90 - 67.5 + ray * 22.5)
			O.segment(fan, 62 + math.cos(angle) * 17, 62 + math.sin(angle) * 17, 62 + math.cos(angle) * 58, 62 + math.sin(angle) * 58, 1, P.goldDeep, 0, "HotelFanRay")
		end
		ctx.fans = ctx.fans or {}
		table.insert(ctx.fans, fan)
	end

	-- Polished floor: darker, reflective, brass inlay lines in perspective (drawn in layout).
	local floor = O.frame(background, {
		Name = "HotelFloor", Position = UDim2.fromScale(0, 0.76), Size = UDim2.fromScale(1, 0.24),
		BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 2, ClipsDescendants = true,
	})
	O.new("UIGradient", floor, {
		Name = "HotelFloorShade", Rotation = 90,
		Color = ColorSequence.new(P.quiet, P.floor),
		Transparency = NumberSequence.new(0.14, 0.02),
	})
	-- Polished stone mirrors what stands on it: a gold streak under the brass doors, warm light under
	-- the chandelier (vertical fades, as reflections on a glossy floor stretch downwards).
	ctx.reflections = {}
	local streaks = {
		{"HotelReflectionGlow", 540, P.glow, 0.972}, {"HotelReflectionGlow", 440, P.glow, 0.972}, {"HotelReflectionGlow", 340, P.glow, 0.972},
		{"HotelReflection", 300, P.primary, 0.95}, {"HotelReflection", 250, P.primary, 0.93}, {"HotelReflection", 200, P.primary, 0.92},
	}
	for _, streak in ipairs(streaks) do
		local strip = O.frame(floor, {
			Name = streak[1], AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.new(0, streak[2], 0.85, 0), BackgroundColor3 = streak[3], ZIndex = 2,
		})
		O.new("UIGradient", strip, {
			Name = "HotelReflectionFade", Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, streak[4]), NumberSequenceKeypoint.new(0.5, 1 - (1 - streak[4]) * 0.4),
				NumberSequenceKeypoint.new(1, 1),
			}),
		})
		table.insert(ctx.reflections, {strip = strip, width = streak[2]})
	end
	ctx.inlay = O.frame(floor, {Name = "HotelFloorInlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2})
	O.frame(background, {Name = "HotelBaseboard", Position = UDim2.new(0, 0, 0.76, -1), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = P.gold, ZIndex = 3})
	O.frame(background, {Name = "HotelBaseboardDeep", Position = UDim2.new(0, 0, 0.76, 3), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = P.goldDeep, ZIndex = 3})
end

------------------------------------------------------------------------------------------------------
-- Crystal chandelier: chain, three gold tiers with candles, crystal strands cascading to a point.
function Lobby.chandelier(ctx, background)
	local P, O = ctx.P, ctx.O
	local cx = 150
	local holder = O.frame(background, {
		Name = "HotelChandelier", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(300, 290), ZIndex = 2,
	})
	ctx.chandelierScale = O.new("UIScale", holder, {Name = "HotelScale"})

	-- Warm light pooled on the marble around it.
	local glows = {}
	for index = 1, 9 do
		glows[index] = O.circle(holder, cx, 150, 580 - (index - 1) * 52, P.glow, 0.972, "HotelGlow")
	end
	ctx.breathe = glows[8]

	O.circle(holder, cx, 0, 34, P.goldDeep, 0, "HotelCeilingRose")
	O.frame(holder, {Name = "HotelChain", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(cx, 0), Size = UDim2.fromOffset(2, 58), BackgroundColor3 = P.goldDeep})
	for y = 12, 48, 9 do
		local link = O.frame(holder, {Name = "HotelChainLink", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, y), Size = UDim2.fromOffset(5, 8), BackgroundTransparency = 1})
		O.round(link)
		O.stroke(link, P.gold, 1)
	end
	O.frame(holder, {Name = "HotelCanopy", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, 56), Size = UDim2.fromOffset(30, 3), BackgroundColor3 = P.goldDeep})
	O.frame(holder, {Name = "HotelCanopy", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, 61), Size = UDim2.fromOffset(54, 4), BackgroundColor3 = P.gold})
	O.frame(holder, {Name = "HotelStem", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(cx, 61), Size = UDim2.fromOffset(3, 126), BackgroundColor3 = P.gold})

	-- Crystal chains along the bell-shaped silhouette.
	local outline = {{27, 61}, {60, 88}, {98, 132}, {131, 178}}
	for side = -1, 1, 2 do
		for index = 1, #outline - 1 do
			local a, b = outline[index], outline[index + 1]
			for k = 1, 5 do
				local t = k / 6
				O.circle(holder, cx + side * (a[1] + (b[1] - a[1]) * t), a[2] + (b[2] - a[2]) * t + math.sin(t * math.pi) * 5, 3, P.crystal, 0.4, "HotelBead")
			end
		end
	end

	local function strand(x, y, length)
		O.frame(holder, {Name = "HotelStrand", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(1, length), BackgroundColor3 = P.crystal, BackgroundTransparency = 0.62})
		O.diamond(holder, 4, P.crystal, {Name = "HotelCrystal", Position = UDim2.fromOffset(x, y + length * 0.5), BackgroundTransparency = 0.38})
		O.diamond(holder, 6, P.crystal, {Name = "HotelCrystal", Position = UDim2.fromOffset(x, y + length), BackgroundTransparency = 0.22})
	end
	local function candle(x, y)
		O.circle(holder, x, y - 16, 22, P.glow, 0.84, "HotelCandleHalo")
		O.frame(holder, {Name = "HotelCandle", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(x, y - 1), Size = UDim2.fromOffset(4, 11), BackgroundColor3 = P.white})
		local flame = O.circle(holder, x, y - 16, 6, P.candle, 0, "HotelFlame")
		flame.Size = UDim2.fromOffset(6, 9)
	end

	local tiers = {{y = 88, half = 60, candles = 5}, {y = 132, half = 98, candles = 7}, {y = 178, half = 131, candles = 9}}
	for index, tier in ipairs(tiers) do
		local nextTier = tiers[index + 1]
		local step = nextTier and 12 or 11
		local count = math.floor((tier.half * 2 - 12) / step)
		for k = 0, count do
			local dx = -tier.half + 6 + k * step
			local length
			if nextTier then
				length = nextTier.y - tier.y - 16 - (k % 2) * 6
			else
				local fall = 1 - (math.abs(dx) / tier.half) ^ 1.6
				length = 18 + 62 * math.max(fall, 0)
			end
			strand(cx + dx, tier.y + 2, length)
		end
		O.frame(holder, {Name = "HotelTier", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, tier.y), Size = UDim2.fromOffset(tier.half * 2, 3), BackgroundColor3 = P.gold})
		O.frame(holder, {Name = "HotelTierShine", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, tier.y - 2), Size = UDim2.fromOffset(tier.half * 2 - 4, 1), BackgroundColor3 = P.goldLight})
		for c = 0, tier.candles - 1 do
			candle(cx - tier.half + 8 + (tier.half * 2 - 16) * c / (tier.candles - 1), tier.y)
		end
	end
	O.circle(holder, cx, 190, 8, P.gold, 0, "HotelFinial")
	O.diamond(holder, 14, P.crystal, {Name = "HotelPendant", Position = UDim2.fromOffset(cx, 266), BackgroundTransparency = 0.25})
	O.diamond(holder, 7, P.crystal, {Name = "HotelPendant", Position = UDim2.fromOffset(cx, 282)})
	return holder
end

------------------------------------------------------------------------------------------------------
-- PLAY = brass elevator doors in a stepped gold portal, under an Art Deco floor dial.
function Lobby.elevator(ctx, background)
	local P, O, kit = ctx.P, ctx.O, ctx.kit
	local play = background:FindFirstChild("PlayButton")
	if not play then return end
	play.Position = UDim2.new(0.5, 0, 0.58, 0) -- one step lower: the chandelier hangs above it
	play.ZIndex = 5
	play.TextSize = 30
	local base = play.Position
	local width, height = play.Size.X.Offset, play.Size.Y.Offset
	-- Warm light spilling from the lit door frame (many faint layers read as a soft falloff).
	for ring = 1, 7 do
		local spill = O.frame(background, {
			Name = "HotelDoorLight", AnchorPoint = Vector2.new(0.5, 0.5), Position = base,
			Size = UDim2.fromOffset(width + 28 + ring * 10, height + 24 + ring * 10), BackgroundColor3 = P.glow,
			BackgroundTransparency = 0.975, ZIndex = 3,
		})
		O.corner(spill, UDim.new(0, 2 + ring * 5))
	end
	local portal = O.frame(background, {
		Name = "HotelElevator", AnchorPoint = Vector2.new(0.5, 0.5), Position = base,
		Size = UDim2.fromOffset(width + 28, height + 24), BackgroundColor3 = P.plaque, ZIndex = 4,
	})
	O.corner(portal)
	O.stroke(portal, P.gold, 1)
	O.rule(portal, 5, P.goldDeep)
	for _, at in ipairs({{0, 30}, {1, -30}}) do
		O.label(play, "strong", {
			Name = "HotelCallArrow", Text = "▲", TextSize = 12, TextColor3 = P.goldDeep, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(at[1], at[2], 0.5, 0), Size = UDim2.fromOffset(20, 20), ZIndex = play.ZIndex,
		})
	end

	-- Floor indicator: a half dial sitting on the portal, numerals L..5, a needle resting on L.
	local dial = O.frame(background, {
		Name = "HotelFloorDial", AnchorPoint = Vector2.new(0.5, 1), Position = udim2Offset(base, 0, -(height + 24) / 2),
		Size = UDim2.fromOffset(154, 78), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 4,
	})
	ctx.dial = dial
	ctx.dialScale = O.new("UIScale", dial, {Name = "HotelScale"})
	local c = 77
	local face = O.circle(dial, c, c, 150, P.plaque, 0, "HotelDialFace")
	O.stroke(face, P.gold, 1)
	local ring = O.circle(dial, c, c, 118, P.plaque, 1, "HotelDialRing")
	O.stroke(ring, P.goldDeep, 1)
	for index, mark in ipairs({"L", "1", "2", "3", "4", "5"}) do
		local angle = math.rad(-75 + (index - 1) * 30)
		O.label(dial, "display", {
			Name = "HotelDialMark", Text = mark, TextSize = 13, TextColor3 = index == 1 and P.goldLight or P.gold,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(c + math.sin(angle) * 66, c - math.cos(angle) * 66),
			Size = UDim2.fromOffset(16, 15), ZIndex = dial.ZIndex,
		})
		O.segment(dial, c + math.sin(angle) * 47, c - math.cos(angle) * 47, c + math.sin(angle) * 55, c - math.cos(angle) * 55, 1, P.gold, 0, "HotelDialTick")
	end
	-- GuiObjects rotate about their centre, so the needle is the upper half of an arm centred on the hub.
	local needle = O.frame(dial, {
		Name = "HotelDialNeedle", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(c, c),
		Size = UDim2.fromOffset(2, 88), BackgroundTransparency = 1, Rotation = -75, ZIndex = dial.ZIndex,
	})
	O.frame(needle, {Name = "HotelDialPointer", Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = P.goldLight, ZIndex = dial.ZIndex})
	O.circle(dial, c, c, 14, P.gold, 0, "HotelDialHub")
	ctx.needle = needle
	-- Hovering the doors sends the needle up the floors; leaving brings it back to the lobby.
	play.MouseEnter:Connect(function() kit:tween(needle, {Rotation = 75}, 0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut) end)
	play.MouseLeave:Connect(function() kit:tween(needle, {Rotation = -75}, 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut) end)
end

------------------------------------------------------------------------------------------------------
-- Top bar = the ceiling cornice: hotel name engraved in gold, the coin ledger on the right.
function Lobby.topBar(ctx, background)
	local P, O, kit = ctx.P, ctx.O, ctx.kit
	local top = background:FindFirstChild("TopBar")
	if not top then return end
	top.ZIndex = 5
	kit:clearTopbar(top) -- IgnoreGuiInset screen: keep the name clear of Roblox's menu buttons
	local title = top:FindFirstChild("Title")
	if title then
		title.Position = UDim2.new(0, 22, 0, 2)
		title.Size = UDim2.new(0.5, -180, 0, 40)
		title.TextColor3 = P.primary
		title.TextYAlignment = Enum.TextYAlignment.Center
		kit:setFont(title, "display")
		kit:fitHeading(title, 34, 16)
		ctx.title = title
	end
	ctx.titleCaption = O.label(top, "display", {
		Name = "HotelTitleCaption", Text = "G R A N D   H O T E L", TextSize = 13, TextColor3 = P.gold,
		Position = UDim2.new(0, 24, 0, 42), Size = UDim2.new(0.5, -180, 0, 16), TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = top.ZIndex,
	})
	local coins = top:FindFirstChild("CoinLabel")
	if coins then
		kit:setFont(coins, "strong")
		coins.TextSize, coins.TextColor3 = 22, P.ink
		O.new("UIPadding", coins, {Name = "HotelCoinPadding", PaddingRight = UDim.new(0, 34)})
		O.coin(coins, 24, {Position = UDim2.new(1, 10, 0.5, 0)})
	end
	-- Cornice: a gold double line along the ceiling, parted where the chandelier hangs.
	ctx.cornice = {}
	for _, side in ipairs({-1, 1}) do
		local parts = {
			line = O.frame(top, {Name = "HotelCornice", BackgroundColor3 = P.gold, ZIndex = top.ZIndex}),
			deep = O.frame(top, {Name = "HotelCorniceDeep", BackgroundColor3 = P.goldDeep, ZIndex = top.ZIndex}),
			diamond = O.diamond(top, 7, P.gold, {Name = "HotelCorniceDiamond"}),
			side = side,
		}
		table.insert(ctx.cornice, parts)
	end
end

------------------------------------------------------------------------------------------------------
-- Nav = the hotel directory: each plaque engraved with the facility's name above the Japanese label.
function Lobby.nav(ctx, background)
	local P, O = ctx.P, ctx.O
	local nav = background:FindFirstChild("NavBar")
	if not nav then return end
	nav.ZIndex = 7 -- above the page veil (ZIndex 6)
	for id, caption in pairs(CAPTIONS) do
		local button = nav:FindFirstChild("Nav_" .. id)
		if button then
			button.TextSize = 17
			button.TextYAlignment = Enum.TextYAlignment.Bottom
			O.new("UIPadding", button, {Name = "HotelNavPadding", PaddingBottom = UDim.new(0, 8)})
			O.label(button, "display", {
				Name = "HotelNavCaption", Text = caption, TextSize = 13, TextColor3 = P.goldLight, AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.new(1, -12, 0, 16), ZIndex = button.ZIndex,
			})
		end
	end
end

------------------------------------------------------------------------------------------------------
-- Pages = framed marble plaques with the hotel crest; a wine-dark veil dims the lobby behind them.
function Lobby.pages(ctx)
	local P, O, kit, gui = ctx.P, ctx.O, ctx.kit, ctx.gui
	-- The veil dims the lobby but not the directory (NavBar sits above it), so the lit plaque still
	-- shows which page is open. Pages live on the ScreenGui, above the whole lobby.
	local lobby = gui:FindFirstChild("Background") or gui
	local veil = O.frame(lobby, {
		Name = "HotelVeil", Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.dim, BackgroundTransparency = 0.3,
		Visible = false, ZIndex = 6,
	})
	local function refresh()
		local any = false
		for _, id in ipairs(PAGES) do
			local page = gui:FindFirstChild(id .. "Page")
			local open = page ~= nil and page.Visible == true
			any = any or open
			local plaque = gui:FindFirstChild("Nav_" .. id, true)
			if plaque then ctx.Skin.select(plaque, open) end
		end
		if any and not veil.Visible then
			veil.BackgroundTransparency = 1
			veil.Visible = true
			kit:tween(veil, {BackgroundTransparency = 0.3}, 0.35, Enum.EasingStyle.Quad)
		elseif not any then
			veil.Visible = false
		end
	end
	for _, id in ipairs(PAGES) do
		local page = gui:FindFirstChild(id .. "Page")
		if page then
			page.ZIndex = 20
			local title = page:FindFirstChild("Title")
			if title then
				title.Position = UDim2.new(0, 26, 0, 30)
				title.Size = UDim2.new(1, -150, 0, 32)
				title.TextSize, title.TextColor3 = 26, P.ink
				title.TextYAlignment = Enum.TextYAlignment.Center
				kit:setFont(title, "title")
			end
			O.label(page, "display", {
				Name = "HotelPageCaption", Text = CAPTIONS[id], TextSize = 13, TextColor3 = P.gold,
				Position = UDim2.new(0, 27, 0, 14), Size = UDim2.new(0.5, 0, 0, 15), TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = page.ZIndex,
			})
			O.divider(page, {Name = "HotelHeaderRule", Position = UDim2.new(0, 24, 0, 62), Size = UDim2.new(1, -48, 0, 9), ZIndex = page.ZIndex}, P.goldDeep)
			local crest = O.frame(page, {
				Name = "HotelCrest", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.fromOffset(48, 48), BackgroundColor3 = P.panel, ZIndex = page.ZIndex,
			})
			O.round(crest)
			O.stroke(crest, P.gold, 1)
			local ring = O.frame(crest, {
				Name = "HotelCrestRing", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(38, 38), BackgroundTransparency = 1, ZIndex = crest.ZIndex,
			})
			O.round(ring)
			O.stroke(ring, P.goldDeep, 1)
			-- Crossed golden keys: the concierge's emblem, the hotel's seal on every page.
			O.key(crest, 28, -45, P.primary)
			O.key(crest, 28, -135, P.primary)
			O.divider(page, {
				Name = "HotelFooterRule", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -42),
				Size = UDim2.new(0, 220, 0, 9), ZIndex = page.ZIndex,
			}, P.goldDeep)
			O.label(page, "display", {
				Name = "HotelFooterCaption", Text = "O B B Y   R U S H   ·   G R A N D   H O T E L", TextSize = 12,
				TextColor3 = P.gold, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -24),
				Size = UDim2.new(1, -60, 0, 15), ZIndex = page.ZIndex,
			})
			local close = page:FindFirstChild("CloseButton")
			if close then
				close.Position = UDim2.new(1, -116, 0, 14)
				close.TextSize = 16
			end
			local empty = page:FindFirstChild("Empty")
			if empty then
				empty.AnchorPoint = Vector2.new(0.5, 0.5)
				empty.Position = UDim2.new(0.5, 0, 0.56, 0)
				empty.Size = UDim2.new(1, -64, 0, 30)
				empty.TextXAlignment = Enum.TextXAlignment.Center
				empty.TextSize, empty.TextColor3 = 17, P.muted
				O.divider(page, {
					Name = "HotelEmptyOrnament", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.56, -34),
					Size = UDim2.fromOffset(150, 9), ZIndex = page.ZIndex,
				}, P.goldDeep)
			end
			-- Opening: the plaque settles 10 px into place with the veil (instant under reduced motion).
			local rest = page.Position
			page:GetPropertyChangedSignal("Visible"):Connect(function()
				if page.Visible then
					page.Position = udim2Offset(rest, 0, 10)
					kit:tween(page, {Position = rest}, 0.35, Enum.EasingStyle.Quad)
				end
				refresh()
			end)
		end
	end
	refresh()
end

------------------------------------------------------------------------------------------------------
-- Shop = room-service menu card: "name . . . . . (coin) price   [購入]".
function Lobby.shop(ctx)
	local P, O, kit = ctx.P, ctx.O, ctx.kit
	local page = ctx.gui:FindFirstChild("ShopPage")
	local list = page and page:FindFirstChild("ProductList")
	if not list then return end
	list.Position = UDim2.new(0, 16, 0, 76)
	list.Size = UDim2.new(1, -32, 1, -136) -- stops above the page footer
	list.ScrollBarThickness = 3
	pcall(function() list.ScrollBarImageColor3 = P.gold end)
	for _, row in ipairs(list:GetChildren()) do
		if string.match(row.Name, "^Product_") then
			local name, price = row:FindFirstChild("ProductName"), row:FindFirstChild("Price")
			local leader = O.frame(row, {
				Name = "HotelLeader", BackgroundTransparency = 1, ClipsDescendants = true, AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 20, 0.5, 3), Size = UDim2.new(0.5, -30, 0, 16), ZIndex = 2,
			})
			O.label(leader, "body", {
				Name = "HotelLeaderDots", Text = string.rep(". ", 120), TextSize = 13, TextColor3 = P.goldDeep,
				Size = UDim2.new(0, 2400, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 2,
			})
			if name then
				-- The name sits on an opaque chip of the page face so the leader dots stop at the text.
				name.TextWrapped = false
				name.AutomaticSize = Enum.AutomaticSize.X
				name.Position = UDim2.new(0, 12, 0, 6)
				name.Size = UDim2.new(0, 0, 1, -12)
				name.BackgroundTransparency, name.BackgroundColor3, name.BorderSizePixel = 0, P.panel, 0
				name.TextSize, name.TextColor3, name.ZIndex = 18, P.ink, 3
				kit:setFont(name, "strong")
				O.new("UIPadding", name, {Name = "HotelNamePadding", PaddingRight = UDim.new(0, 12)})
				O.new("UISizeConstraint", name, {Name = "HotelNameWidth", MaxSize = Vector2.new(320, 10000)})
			end
			if price then
				kit:setFont(price, "strong")
				price.TextSize, price.TextColor3 = 18, P.primary
				O.new("UIPadding", price, {Name = "HotelPricePadding", PaddingLeft = UDim.new(0, 26)})
				O.coin(price, 18, {Position = UDim2.new(0, -26, 0.5, 0)})
			end
		end
	end
end

------------------------------------------------------------------------------------------------------
-- Settings = the room's light switches: label on the left, a lamp that is lit when ON.
function Lobby.settings(ctx)
	local P, O = ctx.P, ctx.O
	local page = ctx.gui:FindFirstChild("SettingsPage")
	if not page then return end
	for index, name in ipairs({"Toggle_Music", "Toggle_SFX"}) do
		local toggle = page:FindFirstChild(name)
		if toggle then
			toggle.Position = UDim2.new(0, 24, 0, 84 + (index - 1) * 68)
			toggle.Size = UDim2.new(1, -48, 0, 56)
			toggle.TextXAlignment = Enum.TextXAlignment.Left
			toggle.TextSize = 18
			O.new("UIPadding", toggle, {Name = "HotelTogglePadding", PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20)})
			local glow = O.circle(toggle, 0, 0, 36, P.glow, 0.8, "HotelLampGlow")
			glow.Position = UDim2.new(1, -11, 0.5, 0)
			local track = O.frame(toggle, {
				Name = "HotelSwitch", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5),
				Size = UDim2.fromOffset(46, 22), BackgroundColor3 = P.plaque, ZIndex = toggle.ZIndex,
			})
			O.corner(track)
			O.stroke(track, P.gold, 1)
			local lamp = O.frame(track, {
				Name = "HotelLamp", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(16, 16),
				Position = UDim2.new(1, -11, 0.5, 0), BackgroundColor3 = P.candle, ZIndex = track.ZIndex,
			})
			O.corner(lamp)
			local ring = O.stroke(lamp, P.goldLight, 1)
			local function update()
				local text = string.upper(toggle.Text or "")
				local on = string.find(text, "OFF", 1, true) == nil and string.find(text, "ON", 1, true) ~= nil
				lamp.BackgroundColor3 = on and P.candle or P.goldDeep
				ring.Color = on and P.goldLight or P.goldDeep
				glow.Visible = on
				ctx.kit:tween(lamp, {Position = on and UDim2.new(1, -11, 0.5, 0) or UDim2.new(0, 11, 0.5, 0)}, 0.2, Enum.EasingStyle.Quad)
			end
			update()
			toggle:GetPropertyChangedSignal("Text"):Connect(update)
		end
	end
end

------------------------------------------------------------------------------------------------------
-- Size-dependent parts: chandelier / dial scale, cornice gap, floor inlay perspective.
function Lobby.bindLayout(ctx, background)
	local P, O = ctx.P, ctx.O
	local function layout()
		local size = background.AbsoluteSize
		local width, height = size.X, size.Y
		if width < 2 or height < 2 then return end
		local s = math.clamp(height / 720, 0.5, 1.35)
		if ctx.chandelierScale then ctx.chandelierScale.Scale = s end
		if ctx.dialScale then ctx.dialScale.Scale = s end
		if ctx.dial then ctx.dial.Visible = height >= 480 end
		local gap = math.floor(158 * s)
		for _, parts in ipairs(ctx.cornice or {}) do
			local left = parts.side < 0
			parts.line.Position = left and UDim2.new(0, 0, 1, -2) or UDim2.new(0.5, gap, 1, -2)
			parts.line.Size = UDim2.new(0.5, -gap, 0, 1)
			parts.deep.Position = left and UDim2.new(0, 0, 1, 2) or UDim2.new(0.5, gap, 1, 2)
			parts.deep.Size = UDim2.new(0.5, -gap, 0, 1)
			parts.diamond.Position = UDim2.new(0.5, left and -gap or gap, 1, 0)
		end
		local top = background:FindFirstChild("TopBar")
		local ceiling = top and (top.Position.Y.Offset + top.Size.Y.Offset + 12) or 158
		for _, panel in ipairs(ctx.wallPanels or {}) do
			panel.Position = UDim2.new(panel.Position.X.Scale, 0, 0, ceiling)
			panel.Size = UDim2.new(0.18, 0, 0.76, -(ceiling + 28))
			panel.Visible = height * 0.76 - ceiling - 28 >= 90
		end
		for _, fan in ipairs(ctx.fans or {}) do
			fan.Visible = height * 0.76 - ceiling - 28 >= 230
		end
		if ctx.title then ctx.title.Size = UDim2.new(0.5, -(gap + 30), 0, 40) end
		if ctx.titleCaption then ctx.titleCaption.Size = UDim2.new(0.5, -(gap + 30), 0, 16) end
		for _, reflection in ipairs(ctx.reflections or {}) do
			reflection.strip.Size = UDim2.new(0, math.floor(reflection.width * s), 0.85, 0)
		end
		local inlay = ctx.inlay
		if inlay then
			inlay:ClearAllChildren()
			local floorHeight = height * 0.24
			local vx, vy = width / 2, -1.4 * floorHeight
			local t = (0 - vy) / (floorHeight - vy)
			for k = -7, 14 do
				local bottomX = k * width / 7
				local horizonX = vx + t * (bottomX - vx)
				O.segment(inlay, horizonX, 0, bottomX, floorHeight, 1, P.goldDeep, 0.55, "HotelInlay")
			end
			for _, depth in ipairs({0.3, 0.66}) do
				O.frame(inlay, {Name = "HotelInlay", Position = UDim2.new(0, 0, depth, 0), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = P.goldDeep, BackgroundTransparency = 0.6, ZIndex = inlay.ZIndex})
			end
		end
	end
	ctx.layout = layout
	layout()
	background:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
end

-- One idle loop only: the chandelier's light breathes slowly. Paused while the menu is disabled.
function Lobby.bindMotion(ctx)
	local gui, kit = ctx.gui, ctx.kit
	if ctx.breathe then
		local tween = kit:loop(ctx.breathe, {BackgroundTransparency = 0.93}, 4.2)
		if tween then table.insert(ctx.loops, tween) end
	end
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		for _, tween in ipairs(ctx.loops) do
			pcall(function()
				if gui.Enabled then tween:Play() else tween:Pause() end
			end)
		end
	end)
end

function Lobby.decorate(Skin, gui)
	local errors = {}
	local ctx = {gui = gui, Skin = Skin, kit = Skin.kit, P = Skin.P, O = Skin.O, loops = {}}
	local function guard(label, fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then table.insert(errors, label .. ": " .. tostring(err)) end
	end
	guard("gui", function() gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
	local background = gui:FindFirstChild("Background")
	if background then
		guard("background", Lobby.background, ctx, background)
		guard("chandelier", Lobby.chandelier, ctx, background)
		guard("elevator", Lobby.elevator, ctx, background)
		guard("topBar", Lobby.topBar, ctx, background)
		guard("nav", Lobby.nav, ctx, background)
	end
	guard("pages", Lobby.pages, ctx)
	guard("shop", Lobby.shop, ctx)
	guard("settings", Lobby.settings, ctx)
	if background then guard("layout", Lobby.bindLayout, ctx, background) end
	guard("motion", Lobby.bindMotion, ctx)
	Skin.lastErrors = errors
	Skin.lastContext = ctx
	return errors
end

return Lobby
