--!nocheck
-- SumiParts: the sumi-e / calligraphy pieces of the "Sumi & Washi" skin, drawn only from Frames,
-- UIStroke, UIGradient and TextLabels (no image assets):
--   brush   - a tapered brush stroke (layered hairs, dry-brush streaks in the tail)
--   enso    - a hand-drawn circle whose ink thins out and leaves a gap
--   peak    - a distant mountain whose foot dissolves into mist
--   sealFace / seal - a vermilion seal impression (carved inner line, worn edge, paper flecks)
--   coin    - an ink 穴銭 (coin with a square hole), replacing the coin emoji
--   scroll  - hanging-scroll rods, end knobs and cord for a page
-- Colours come from the kit palette: ink tones, washi paper and, for seals only, vermilion.
-- Every decorative instance is named "Motif*" or lives under one, is not Active, and never a button.
local Parts = {}

local function create(className, parent, props)
	local object = Instance.new(className)
	for key, value in pairs(props or {}) do
		object[key] = value
	end
	object.Parent = parent
	return object
end
Parts.create = create

local function kp(time, value)
	return NumberSequenceKeypoint.new(time, math.clamp(value, 0, 1))
end

-- Deterministic Park-Miller generator: the same seed always draws the same stroke (and some
-- sandboxes have no Random).
function Parts.rng(seed)
	local state = math.floor(seed or 1) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function(a, b)
		state = (state * 16807) % 2147483647
		return a + (b - a) * ((state - 1) / 2147483646)
	end
end

-- Brush --------------------------------------------------------------------------------------------
local hairs = setmetatable({}, {__mode = "k"}) -- holder -> {{frame, base transparency}}

-- A horizontal brush stroke filling its holder. options: size, position, anchor, rotation, zIndex,
-- color, alpha (base transparency of the darkest hair), seed, layers, kasure (dry-brush streaks).
function Parts.brush(parent, name, options)
	options = options or {}
	local rand = Parts.rng(options.seed or 7)
	local holder = create("Frame", parent, {
		Name = name or "MotifBrush", BackgroundTransparency = 1, BorderSizePixel = 0, Active = false,
		Size = options.size or UDim2.fromScale(1, 1), Position = options.position or UDim2.new(),
		AnchorPoint = options.anchor or Vector2.new(0, 0), Rotation = options.rotation or 0, ZIndex = options.zIndex or 1,
	})
	local list = {}
	for index = 1, options.layers or 4 do
		local base = math.clamp((options.alpha or 0) + (index - 1) * 0.17, 0, 0.96)
		local hair = create("Frame", holder, {
			Name = "Hair" .. index, BorderSizePixel = 0, BackgroundColor3 = options.color, BackgroundTransparency = base,
			AnchorPoint = Vector2.new(0, 0.5), Active = false, ZIndex = holder.ZIndex,
			Position = UDim2.new(rand(-0.01, 0.025), 0, 0.5 + (index == 1 and 0 or rand(-0.16, 0.16)), 0),
			Size = UDim2.new(rand(0.9, 1), 0, index == 1 and 1 or rand(0.3, 0.75), 0),
			Rotation = rand(-0.5, 0.5),
		})
		create("UICorner", hair, {CornerRadius = UDim.new(0.5, 0)})
		-- Entry (the brush lands heavy), body, and the lifting tail.
		create("UIGradient", hair, {Name = "Taper", Transparency = NumberSequence.new({
			kp(0, 0.6), kp(0.035, 0), kp(0.6, 0.04), kp(0.84, 0.3 + rand(0, 0.25)), kp(1, 1),
		})})
		table.insert(list, {hair, base})
	end
	if options.kasure then
		-- 飛白: paper showing through the tail where the brush ran dry.
		for index = 1, 3 do
			local streak = create("Frame", holder, {
				Name = "Kasure" .. index, BorderSizePixel = 0, BackgroundColor3 = options.paper, BackgroundTransparency = 0.15,
				AnchorPoint = Vector2.new(0, 0.5), Active = false, ZIndex = holder.ZIndex,
				Position = UDim2.new(rand(0.45, 0.62), 0, rand(0.28, 0.72), 0), Size = UDim2.new(rand(0.3, 0.5), 0, 0.07, 0),
			})
			create("UIGradient", streak, {Transparency = NumberSequence.new({kp(0, 1), kp(0.25, 0.2), kp(1, 0)})})
		end
	end
	hairs[holder] = list
	return holder
end

-- Fade a whole brush stroke: opacity 0..1 multiplies every hair's own opacity.
function Parts.setBrushOpacity(holder, opacity)
	local list = hairs[holder]
	if not list then return end
	for _, entry in ipairs(list) do
		entry[1].BackgroundTransparency = 1 - (1 - entry[2]) * math.clamp(opacity, 0, 1)
	end
end

-- Ensō ---------------------------------------------------------------------------------------------
-- options: size (max box, UDim2), position, anchor, zIndex, color, alpha, thickness (px) or
-- thicknessRatio (of the diameter), gap (gradient rotation: the stroke lifts off towards this angle;
-- -45 = a gap at the upper right).
-- A UIStroke is one even line, so the brush is faked with three rings slightly off-centre: where they
-- part the band is fat (the loaded brush), where they meet it is thin, and each fades out on its own.
function Parts.enso(parent, name, options)
	options = options or {}
	local holder = create("Frame", parent, {
		Name = name or "MotifEnso", BackgroundTransparency = 1, Active = false, ZIndex = options.zIndex or 1,
		Size = options.size or UDim2.fromScale(1, 1), Position = options.position or UDim2.new(),
		AnchorPoint = options.anchor or Vector2.new(0.5, 0.5),
	})
	create("UIAspectRatioConstraint", holder, {AspectRatio = 1, AspectType = Enum.AspectType.FitWithinMaxSize,
		DominantAxis = Enum.DominantAxis.Width})
	local alpha, gap = options.alpha or 0.1, options.gap or -45
	-- inset / shift in units of the stroke thickness
	local rings = {
		{name = "Body", inset = 0, dx = 0, dy = 0, width = 0.62, alpha = alpha, rotation = gap},
		{name = "Bristle", inset = 0.3, dx = 0.2, dy = -0.15, width = 0.5, alpha = alpha, rotation = gap + 22},
		{name = "Fray", inset = -0.5, dx = -0.12, dy = 0.12, width = 0.16, alpha = alpha + 0.25, rotation = gap - 25},
	}
	local strokes = {}
	for _, ring in ipairs(rings) do
		local frame = create("Frame", holder, {
			Name = ring.name, BackgroundTransparency = 1, Active = false, ZIndex = holder.ZIndex,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
		})
		create("UICorner", frame, {CornerRadius = UDim.new(0.5, 0)})
		local stroke = create("UIStroke", frame, {Name = "Ink", ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = options.color, Thickness = 1, Transparency = 0, LineJoinMode = Enum.LineJoinMode.Round})
		-- Heaviest where the brush lands, dry towards the end, gone before the circle closes. `closed`
		-- keeps a dry but unbroken tail (small circles with a gap read as a loading spinner).
		local tail = options.closed and math.min(1, ring.alpha + 0.5) or 1
		create("UIGradient", stroke, {Name = "Lift", Rotation = ring.rotation, Transparency = NumberSequence.new({
			kp(0, ring.alpha + 0.12), kp(0.2, ring.alpha), kp(0.5, ring.alpha + 0.05), kp(0.62, ring.alpha + 0.35),
			kp(0.74, tail), kp(1, tail),
		})})
		table.insert(strokes, {frame = frame, stroke = stroke, ring = ring})
	end
	local function fit(diameter)
		local thickness = options.thickness or math.clamp(diameter * (options.thicknessRatio or 0.06), 3, 26)
		for _, entry in ipairs(strokes) do
			local ring = entry.ring
			local inset = ring.inset * thickness
			entry.frame.Size = UDim2.new(1, -2 * inset, 1, -2 * inset)
			entry.frame.Position = UDim2.new(0.5, ring.dx * thickness, 0.5, ring.dy * thickness)
			entry.stroke.Thickness = math.max(1, thickness * ring.width)
		end
	end
	fit(options.diameterHint or 120)
	pcall(function()
		holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			local size = holder.AbsoluteSize
			if size and size.X > 8 then fit(math.min(size.X, size.Y)) end
		end)
	end)
	return holder
end

-- Mountains ----------------------------------------------------------------------------------------
-- A rounded rectangle turned 45 degrees: its top corner is the summit, and a gradient running
-- straight down the screen dissolves everything below the waist into mist.
function Parts.peak(parent, name, cx, cy, w, h, alpha, color, zIndex)
	local frame = create("Frame", parent, {
		Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(cx, cy), Size = UDim2.fromScale(w, h),
		Rotation = 45, BackgroundColor3 = color, BackgroundTransparency = 0, BorderSizePixel = 0, Active = false,
		ZIndex = zIndex or 1,
	})
	create("UICorner", frame, {CornerRadius = UDim.new(0.26, 0)})
	-- Rotation 45 in the frame's own space = straight down on screen.
	create("UIGradient", frame, {Name = "Mist", Rotation = 45, Transparency = NumberSequence.new({
		kp(0, alpha), kp(0.16, alpha + 0.02), kp(0.33, alpha + 0.16), kp(0.46, 1), kp(1, 1),
	})})
	return frame
end

-- Seals --------------------------------------------------------------------------------------------
-- Turn a vermilion rectangle into a stamped impression: a carved inner line, a worn edge and a few
-- flecks where the paste did not take. `paper` is the colour showing through.
function Parts.sealFace(frame, paper, options)
	options = options or {}
	local rand = Parts.rng(options.seed or 11)
	local inset = options.inset or 5
	local line = frame:FindFirstChild("MotifSealLine") or create("Frame", frame, {
		Name = "MotifSealLine", BackgroundTransparency = 1, Active = false, ZIndex = frame.ZIndex,
		Position = UDim2.fromOffset(inset, inset), Size = UDim2.new(1, -2 * inset, 1, -2 * inset),
	})
	if not line:FindFirstChildOfClass("UIStroke") then
		create("UIStroke", line, {ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = paper,
			Thickness = options.line or 1.5, Transparency = 0.12, LineJoinMode = Enum.LineJoinMode.Miter})
	end
	if frame:FindFirstChild("MotifSealWear") then return frame end
	local wear = create("Frame", frame, {Name = "MotifSealWear", BackgroundTransparency = 1, Active = false,
		Size = UDim2.fromScale(1, 1), ZIndex = frame.ZIndex})
	-- Flecks: small, mostly near the rim.
	for index = 1, options.flecks or 9 do
		local edge = index % 2 == 0
		local size = rand(1.5, options.fleck or 4)
		create("Frame", wear, {
			Name = "Fleck" .. index, BorderSizePixel = 0, BackgroundColor3 = paper, BackgroundTransparency = rand(0.05, 0.45),
			AnchorPoint = Vector2.new(0.5, 0.5), Active = false, ZIndex = wear.ZIndex, Rotation = rand(0, 90),
			Position = edge and UDim2.new(rand(0.03, 0.97), 0, rand(0, 1) < 0.5 and 0.06 or 0.94, 0)
				or UDim2.new(rand(0.02, 0.98) < 0.5 and rand(0.02, 0.1) or rand(0.9, 0.98), 0, rand(0.1, 0.9), 0),
			Size = UDim2.fromOffset(size, size * rand(0.6, 1.4)),
		})
	end
	-- Chips in the rim: paper-coloured nicks that straddle the edge.
	for index = 1, options.chips or 4 do
		local side = index % 4
		local along = rand(0.12, 0.88)
		local length, depth = rand(4, 10), rand(1.5, 3)
		local position = side == 0 and UDim2.new(along, 0, 0, 0) or side == 1 and UDim2.new(1, 0, along, 0)
			or side == 2 and UDim2.new(along, 0, 1, 0) or UDim2.new(0, 0, along, 0)
		local size = (side == 0 or side == 2) and UDim2.fromOffset(length, depth) or UDim2.fromOffset(depth, length)
		create("Frame", wear, {Name = "Chip" .. index, BorderSizePixel = 0, BackgroundColor3 = paper, BackgroundTransparency = 0,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = position, Size = size, Active = false, ZIndex = wear.ZIndex})
	end
	return frame
end

-- A small standalone seal (引首印 beside a page title). Decorative only.
function Parts.seal(parent, name, glyph, size, colors, font, options)
	options = options or {}
	local seal = create("Frame", parent, {
		Name = name, Size = UDim2.fromOffset(size, math.floor(size * (options.aspect or 1.15))), BorderSizePixel = 0,
		BackgroundColor3 = colors.shu, Active = false, Rotation = options.rotation or -1.5, ZIndex = options.zIndex or 1,
		Position = options.position or UDim2.new(), AnchorPoint = options.anchor or Vector2.new(0, 0),
	})
	create("UICorner", seal, {CornerRadius = UDim.new(0, 2)})
	local text = create("TextLabel", seal, {
		Name = "Glyph", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = glyph, TextSize = math.floor(size * 0.62),
		TextColor3 = colors.paper, ZIndex = seal.ZIndex, Active = false,
	})
	if font then pcall(function() text.FontFace = font end) end
	Parts.sealFace(seal, colors.paper, {inset = 2.5, line = 1, flecks = 5, fleck = 2.5, chips = 2, seed = options.seed or #glyph})
	return seal
end

-- Coin ---------------------------------------------------------------------------------------------
-- 穴銭: an ink disc with a square hole of paper. Replaces the coin emoji, which Roblox cannot draw
-- (Unicode 13) and which would add a colour.
function Parts.coin(parent, name, size, ink, paper)
	local coin = create("Frame", parent, {
		Name = name or "MotifCoin", Size = UDim2.fromOffset(size, size), BackgroundColor3 = ink, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5), Active = false, ZIndex = parent.ZIndex,
	})
	create("UICorner", coin, {CornerRadius = UDim.new(0.5, 0)})
	local rim = create("Frame", coin, {Name = "Rim", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -5, 1, -5), Active = false, ZIndex = coin.ZIndex})
	create("UICorner", rim, {CornerRadius = UDim.new(0.5, 0)})
	create("UIStroke", rim, {ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = paper, Thickness = 1, Transparency = 0.55})
	local hole = math.max(4, math.floor(size * 0.32))
	create("Frame", coin, {Name = "Hole", BackgroundColor3 = paper, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(hole, hole), Active = false, ZIndex = coin.ZIndex})
	return coin
end

-- Hanging scroll -----------------------------------------------------------------------------------
-- The page is the 本紙 (the painting). Around it: the mounting band (a UIStroke the caller adds), 天
-- above and 地 below in the mounting cloth, 一文字 strips against the paper, two 風帯 hanging from the
-- top rod (八双), the lower roller with its knobs (軸先), and the cord. colors = {ink, knob, mount,
-- ichimonji, futai}; options = {ten, chi, band} in pixels (band = the mounting stroke thickness).
function Parts.scroll(page, colors, options)
	if page:FindFirstChild("MotifMounting") then return page end
	options = options or {}
	local band, ten, chi = options.band or 7, options.ten or 22, options.chi or 30
	local rollerHeight = options.roller or 10
	local z = page.ZIndex
	local holder = create("Frame", page, {Name = "MotifMounting", BackgroundTransparency = 1, Active = false,
		Size = UDim2.fromScale(1, 1), ZIndex = z})
	local function piece(name, position, size, color, props)
		local frame = create("Frame", holder, {Name = name, BackgroundColor3 = color, BorderSizePixel = 0, Active = false,
			Position = position, Size = size, ZIndex = z})
		for key, value in pairs(props or {}) do
			frame[key] = value
		end
		return frame
	end
	piece("Ten", UDim2.new(0, -band, 0, -band - ten), UDim2.new(1, 2 * band, 0, ten), colors.mount)
	if chi > 0 then
		piece("Chi", UDim2.new(0, -band, 1, band), UDim2.new(1, 2 * band, 0, chi), colors.mount)
	end
	piece("IchimonjiTop", UDim2.new(0, 0, 0, -band - 1), UDim2.new(1, 0, 0, math.max(3, band - 2)), colors.ichimonji)
	piece("IchimonjiBottom", UDim2.new(0, 0, 1, 3), UDim2.new(1, 0, 0, math.max(3, band - 2)), colors.ichimonji)
	for _, x in ipairs({0.27, 0.73}) do
		local futai = piece(x < 0.5 and "FutaiL" or "FutaiR", UDim2.new(x, 0, 0, -band - ten),
			UDim2.new(0, 9, 0, math.floor(ten * 0.85)), colors.futai, {AnchorPoint = Vector2.new(0.5, 0)})
		-- the weighted tip at the end of each hanging band
		create("Frame", futai, {Name = "Tip", BackgroundColor3 = colors.ink, BackgroundTransparency = 0.35, BorderSizePixel = 0,
			Active = false, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(1, 0, 0, 2),
			ZIndex = z})
	end
	local top = piece("Hasso", UDim2.new(0, -band, 0, -band - ten - 6), UDim2.new(1, 2 * band, 0, 6), colors.ink)
	create("UICorner", top, {CornerRadius = UDim.new(0, 2)})
	local roller = piece("Jiku", UDim2.new(0, -band - 2, 1, band + chi), UDim2.new(1, 2 * band + 4, 0, rollerHeight), colors.ink)
	create("UICorner", roller, {CornerRadius = UDim.new(0, 3)})
	for _, side in ipairs({0, 1}) do
		local knob = create("Frame", roller, {Name = side == 0 and "JikusakiL" or "JikusakiR", BackgroundColor3 = colors.knob,
			BorderSizePixel = 0, Active = false, AnchorPoint = Vector2.new(side == 0 and 1 or 0, 0.5),
			Position = UDim2.new(side, 0, 0.5, 0), Size = UDim2.fromOffset(10, rollerHeight + 6), ZIndex = z})
		create("UICorner", knob, {CornerRadius = UDim.new(0, 3)})
	end
	-- Cord: two thin lines meeting above the centre of the rod.
	for _, sign in ipairs({-1, 1}) do
		create("Frame", top, {Name = sign < 0 and "CordL" or "CordR", BackgroundColor3 = colors.ink, BackgroundTransparency = 0.3,
			BorderSizePixel = 0, Active = false, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, sign * 13, 0, -8), Size = UDim2.fromOffset(32, 1.5), Rotation = sign * 30, ZIndex = z})
	end
	return page
end

return Parts
