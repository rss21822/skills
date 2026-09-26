-- The Grand Hotel lobby drawn behind the main menu: a crystal-strand chandelier hanging from the
-- masthead with its warm light, white veins in the black marble, two gold art-deco pilasters and the
-- floor rule above the directory (nav bar).
-- Decoration only: nothing here is interactive (Active = false) or looked up by other scripts, and every
-- piece is placed in scale (the chandelier keeps its proportions with a UIAspectRatioConstraint) so the
-- same lobby works on a phone in landscape and on a monitor.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))

local LobbyBackdrop = {}
local create = Theme.create
local colors = Theme.colors

local CHANDELIER_ASPECT = 1.8 -- width / height

-- A crystal: a diamond sized as a fraction of the chandelier width, so it scales with it.
local function crystal(parent, name, widthScale, position, transparency, edge)
	local frame = create("Frame", {Name = name, Size = UDim2.new(widthScale, 0, 1, 0), Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45, BackgroundColor3 = colors.crystal,
		BackgroundTransparency = transparency, BorderSizePixel = 0, Active = false, Parent = parent})
	create("UIAspectRatioConstraint", {AspectRatio = 1, Parent = frame})
	if edge then Theme.stroke(frame, edge, colors.goldBright) end
	return frame
end

-- Bottom of the crystal cascade at horizontal position x (0..1): an inverted dome.
local function dropDepth(x)
	local u = math.clamp((x - 0.5) / 0.27, -1, 1)
	return 0.46 + 0.48 * (1 - u * u) ^ 0.7
end

local function chandelier(parent)
	local holder = create("Frame", {Name = "Chandelier", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80), Size = UDim2.new(0.5, 0, 0.46, -80), BackgroundTransparency = 1,
		BorderSizePixel = 0, Active = false, ZIndex = 2, Parent = parent})
	create("UIAspectRatioConstraint", {AspectRatio = CHANDELIER_ASPECT, Parent = holder})

	-- Candle light: many stacked, almost clear discs (smaller ones nearer the middle) add up to one soft
	-- radial glow without visible banding. ~20% warm light at the centre.
	local DISCS = 16
	for index = 0, DISCS - 1 do
		local diameter = 0.3 + 1.6 * (1 - index / (DISCS - 1)) ^ 1.5
		local disc = create("Frame", {Name = "Glow" .. index, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.52, 0), Size = UDim2.new(diameter, 0, diameter * 2, 0),
			BackgroundColor3 = colors.glow, BackgroundTransparency = 0.987, BorderSizePixel = 0, Active = false,
			ZIndex = 0, Parent = holder})
		Theme.corner(disc, UDim.new(0.5, 0))
		create("UIAspectRatioConstraint", {AspectRatio = 1, Parent = disc})
	end

	-- Chain from the masthead ornament, crown, and two rods down to the ring.
	create("Frame", {Name = "Chain", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 5),
		Size = UDim2.new(0, 1, 0.13, -5), BackgroundColor3 = colors.accent, BackgroundTransparency = 0.15,
		BorderSizePixel = 0, Active = false, Parent = holder})
	Theme.diamond(holder, "Crown", 9, UDim2.new(0.5, 0, 0.14, 0), {outline = true})
	for side, x in ipairs({0.355, 0.645}) do
		-- From the crown (0.5, 0.14) to the ring end (0.21 / 0.79, 0.22), in a 1.8 : 1 box.
		create("Frame", {Name = "Rod" .. side, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, 0, 0.18, 0),
			Size = UDim2.new(0.294, 0, 0, 1), Rotation = side == 1 and -8.7 or 8.7, BackgroundColor3 = colors.accent,
			BackgroundTransparency = 0.25, BorderSizePixel = 0, Active = false, Parent = holder})
	end
	local ring = create("Frame", {Name = "Ring", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.22, 0),
		Size = UDim2.new(0.6, 0, 0, 2), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Active = false,
		Parent = holder})
	Theme.gradient(ring, {{0, colors.goldDeep}, {0.5, colors.goldBright}, {1, colors.goldDeep}}, 0)

	-- Candle points along the ring.
	for index = 0, 6 do
		local flame = create("Frame", {Name = "Candle" .. index, AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.23 + index * (0.54 / 6), 0, 0.216, 0), Size = UDim2.new(0.011, 0, 1, 0),
			BackgroundColor3 = colors.crystal, BorderSizePixel = 0, Active = false, Parent = holder})
		Theme.corner(flame, UDim.new(0.5, 0))
		create("UIAspectRatioConstraint", {AspectRatio = 1, Parent = flame})
	end

	-- Crystal strands: a back row (fainter, shorter) and a front row with beads and a cut drop.
	local strands = create("Frame", {Name = "Strands", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
		BorderSizePixel = 0, Active = false, Parent = holder})
	local FRONT, BACK = 19, 18
	for index = 0, BACK - 1 do
		local x = 0.245 + index * (0.51 / (BACK - 1))
		local bottom = 0.225 + (dropDepth(x) - 0.225) * 0.86
		create("Frame", {Name = "Back" .. index, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, 0, 0.225, 0),
			Size = UDim2.new(0, 1, bottom - 0.225, 0), BackgroundColor3 = colors.goldBright, BackgroundTransparency = 0.72,
			BorderSizePixel = 0, Active = false, Parent = strands})
		crystal(strands, "BackDrop" .. index, 0.011, UDim2.new(x, 0, bottom, 0), 0.55)
	end
	for index = 0, FRONT - 1 do
		local x = 0.23 + index * (0.54 / (FRONT - 1))
		local bottom = dropDepth(x)
		local line = create("Frame", {Name = "Strand" .. index, AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(x, 0, 0.225, 0), Size = UDim2.new(0, 1, bottom - 0.225, 0),
			BackgroundColor3 = colors.goldBright, BackgroundTransparency = 0.35, BorderSizePixel = 0, Active = false,
			Parent = strands})
		Theme.gradient(line, nil, 90, {{0, 0.1}, {1, 0.6}})
		-- Beads, staggered between neighbouring strands so they read as cut glass, not a grid.
		local step = 0.15
		local y = 0.225 + (index % 2 == 0 and step or step * 1.5)
		local bead = 1
		while y < bottom - 0.06 do
			crystal(strands, "Bead" .. index .. "_" .. bead, 0.0075, UDim2.new(x, 0, y, 0), 0.3)
			y += step
			bead += 1
		end
		crystal(strands, "Drop" .. index, 0.018, UDim2.new(x, 0, bottom, 0), 0.08, 0.45)
	end
	return holder
end

-- Nero Marquina veins on the lobby wall: wandering polylines with branches, drawn in a 16:9 box that
-- scales with the screen width (so segments stay joined) and is clipped by the Background.
local WALL_ASPECT = 16 / 9
local WALL_VEINS = { -- {transparency, points (x, y in the 16:9 box)}
	{0.915, {{-0.05, 0.16}, {0.1, 0.27}, {0.23, 0.32}, {0.37, 0.45}, {0.5, 0.5}, {0.64, 0.61}, {0.79, 0.65}, {1.05, 0.83}}},
	{0.94, {{0.23, 0.32}, {0.29, 0.27}, {0.37, 0.25}}},
	{0.94, {{0.64, 0.61}, {0.69, 0.72}, {0.74, 0.79}}},
	{0.93, {{0.71, -0.03}, {0.79, 0.1}, {0.85, 0.19}, {0.9, 0.33}, {1.03, 0.45}}},
	{0.93, {{-0.03, 0.68}, {0.09, 0.75}, {0.19, 0.85}, {0.33, 0.9}, {0.45, 1.03}}},
	{0.95, {{0.09, 0.75}, {0.13, 0.66}, {0.2, 0.62}}},
}
local function veins(parent)
	local wall = create("Frame", {Name = "Veins", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Active = false, ZIndex = 1,
		Parent = parent})
	create("UIAspectRatioConstraint", {AspectRatio = WALL_ASPECT, AspectType = Enum.AspectType.ScaleWithParentSize,
		DominantAxis = Enum.DominantAxis.Width, Parent = wall})
	for veinIndex, vein in ipairs(WALL_VEINS) do
		local points = vein[2]
		for index = 1, #points - 1 do
			local a, b = points[index], points[index + 1]
			local dx, dy = (b[1] - a[1]) * WALL_ASPECT, b[2] - a[2] -- in box-height units
			local length = math.sqrt(dx * dx + dy * dy) / WALL_ASPECT -- in box-width units
			-- Segments near the ends of a vein fade out.
			local edge = math.min(index - 1, #points - 1 - index)
			local transparency = edge == 0 and math.min(0.97, vein[1] + 0.04) or vein[1]
			create("Frame", {Name = "Vein" .. veinIndex .. "_" .. index, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new((a[1] + b[1]) / 2, 0, (a[2] + b[2]) / 2, 0), Size = UDim2.new(length, 1, 0, 1),
				Rotation = math.deg(math.atan2(dy, dx)), BackgroundColor3 = colors.vein, BackgroundTransparency = transparency,
				BorderSizePixel = 0, Active = false, Parent = wall})
		end
	end
end

-- Gold pilaster: twin fluting lines with a stepped (ziggurat) capital and base.
local function pilaster(parent, name, x)
	local holder = create("Frame", {Name = name, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, 0, 0.22, 0),
		Size = UDim2.new(0, 26, 0.56, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Active = false, ZIndex = 1,
		Parent = parent})
	for index, dx in ipairs({-3, 3}) do
		Theme.hairline(holder, "Flute" .. index, UDim.new(1, -34), UDim2.new(0.5, dx, 0.5, 0),
			{vertical = true, transparency = 0.45, fadeCurve = {{0, 0.5}, {0.5, 0}, {1, 0.5}}})
	end
	for step, width in ipairs({22, 14, 6}) do
		create("Frame", {Name = "Capital" .. step, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 16 - (step - 1) * 4), Size = UDim2.new(0, width, 0, 1),
			BackgroundColor3 = colors.accent, BackgroundTransparency = 0.25, BorderSizePixel = 0, Active = false, Parent = holder})
		create("Frame", {Name = "Base" .. step, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 1, -16 + (step - 1) * 4), Size = UDim2.new(0, width, 0, 1),
			BackgroundColor3 = colors.accent, BackgroundTransparency = 0.25, BorderSizePixel = 0, Active = false, Parent = holder})
	end
	Theme.diamond(holder, "Finial", 5, UDim2.new(0.5, 0, 0, 1))
	Theme.diamond(holder, "Foot", 5, UDim2.new(0.5, 0, 1, -1))
end

-- background: the full-screen "Background" frame of the menu.
function LobbyBackdrop.build(background)
	veins(background)
	pilaster(background, "PilasterLeft", 0.055)
	pilaster(background, "PilasterRight", 0.945)
	chandelier(background)
	local floor = Theme.rule(background, "FloorRule", UDim.new(0.62, 0), UDim2.new(0.5, 0, 1, -104), {transparency = 0.4})
	floor.ZIndex = 2
end

return LobbyBackdrop
