-- Night harbour scenery behind the main menu: navy sky with stars and a moon, a lighthouse painted
-- red and white with a slowly sweeping beam, the dark skyline of the port (sheds, a crane, a moored
-- ship with lit portholes), a red harbour light, and water carrying their reflections.
-- Pure Frames; ambient motion is a handful of looping tweens and is skipped under Reduced Motion.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))

local P = Theme.palette
local create = Theme.create
local rgb = Color3.fromRGB

local HORIZON = 0.7 -- screen-height fraction where the water begins
local SILHOUETTE = rgb(3, 7, 17)
local LAMP = rgb(255, 246, 222)

local HarborBackdrop = {}

local function box(parent, name, props)
	props.Name = name
	props.BorderSizePixel = 0
	props.Parent = parent
	if props.BackgroundColor3 == nil then props.BackgroundColor3 = SILHOUETTE end
	return create("Frame", props)
end

local function disc(parent, name, diameter, color, transparency, position)
	local frame = box(parent, name, {AnchorPoint = Vector2.new(0.5, 0.5), Position = position, Size = UDim2.fromOffset(diameter, diameter),
		BackgroundColor3 = color, BackgroundTransparency = transparency or 0})
	Theme.corner(frame, UDim.new(0.5, 0))
	return frame
end

-- A soft glow without images: concentric discs, each faint, so the overlap builds a radial falloff.
-- `strength` is the opacity reached at the centre.
local function glow(parent, name, diameter, color, strength, position)
	local layers = {1, 0.82, 0.66, 0.52, 0.4, 0.29, 0.2}
	local alpha = 1 - (1 - strength) ^ (1 / #layers)
	for index, scale in ipairs(layers) do
		disc(parent, name .. index, math.max(2, diameter * scale), color, 1 - alpha, position)
	end
end

-- Deterministic scatter so every client sees the same sky.
local function scatter(seed)
	local state = seed
	return function()
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
end

local function sky(background)
	background.BackgroundColor3 = Color3.new(1, 1, 1)
	Theme.gradient(background, {{0, rgb(4, 8, 20)}, {0.42, rgb(9, 19, 44)}, {HORIZON - 0.005, rgb(26, 48, 94)}, {1, rgb(6, 12, 28)}}, 90)

	local random = scatter(20260924)
	local stars = box(background, "Stars", {Size = UDim2.fromScale(1, HORIZON), BackgroundTransparency = 1})
	for index = 1, 34 do
		local x, y = 0.02 + random() * 0.96, 0.05 + random() * 0.8
		local size = random() < 0.25 and 3 or 2
		local star = box(stars, "Star", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = P.white, BackgroundTransparency = 0.25 + random() * 0.45})
		Theme.corner(star, UDim.new(0.5, 0))
		if index % 4 == 0 then Theme.loop(star, 1.6 + random() * 2, {BackgroundTransparency = 0.85}, random() * 2) end
	end

	local moonAt = UDim2.fromScale(0.84, 0.25)
	glow(background, "MoonGlow", 300, rgb(176, 196, 240), 0.17, moonAt)
	local moon = disc(background, "Moon", 58, rgb(240, 236, 222), 0, moonAt)
	disc(moon, "Mare1", 14, rgb(212, 208, 194), 0.3, UDim2.new(0.38, 0, 0.42, 0))
	disc(moon, "Mare2", 9, rgb(212, 208, 194), 0.35, UDim2.new(0.64, 0, 0.62, 0))

	local haze = box(background, "HorizonGlow", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, HORIZON),
		Size = UDim2.new(1, 0, 0, 110), BackgroundColor3 = rgb(70, 100, 160)})
	Theme.gradient(haze, {{0, Color3.new(1, 1, 1)}, {1, Color3.new(1, 1, 1)}}, 90, {{0, 1}, {1, 0.8}})
end

local function lighthouse(parent)
	local tower = box(parent, "Lighthouse", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.085, 0, 1, -8),
		Size = UDim2.fromOffset(40, 126), BackgroundTransparency = 1})

	-- The beam pivots on the lamp: a wide invisible frame centred on it, rotated back and forth.
	local pivot = box(tower, "BeamPivot", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 15),
		Size = UDim2.fromOffset(1200, 8), BackgroundTransparency = 1, Rotation = -13})
	for index, spec in ipairs({{6, 540, 6, 0.55}, {50, 500, 18, 0.8}, {130, 420, 34, 0.88}, {230, 330, 56, 0.93}}) do
		local ray = box(pivot, "Beam" .. index, {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, spec[1], 0.5, 0),
			Size = UDim2.fromOffset(spec[2], spec[3]), BackgroundColor3 = rgb(226, 234, 255)})
		Theme.gradient(ray, {{0, Color3.new(1, 1, 1)}, {1, Color3.new(1, 1, 1)}}, 0, {{0, spec[4]}, {0.7, 0.97}, {1, 1}})
	end
	Theme.loop(pivot, 7, {Rotation = -4})

	glow(tower, "LampGlow", 140, LAMP, 0.32, UDim2.new(0.5, 0, 0, 15))
	local roof = box(tower, "Roof", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(22, 9),
		BackgroundColor3 = P.red})
	Theme.corner(roof, 5)
	box(tower, "Lantern", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(16, 14),
		BackgroundColor3 = LAMP})
	box(tower, "Gallery", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22), Size = UDim2.fromOffset(32, 4)})
	for band = 1, 4 do
		local paint = box(tower, "Band" .. band, {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 26 + (band - 1) * 24),
			Size = UDim2.fromOffset(22 + band * 3, 24), BackgroundColor3 = band % 2 == 1 and P.red or P.white})
		-- moonlight from the right, night on the left: shade the left of every band
		box(paint, "Shade", {Size = UDim2.fromScale(0.42, 1), BackgroundColor3 = P.ink, BackgroundTransparency = 0.5})
	end
	box(tower, "Base", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(40, 4)})
end

local function skyline(background)
	local port = box(background, "Skyline", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, HORIZON),
		Size = UDim2.new(1, 0, 0, 150), BackgroundTransparency = 1})
	box(port, "Breakwater", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(0.26, 0, 0, 8)})

	-- warehouses: {x, width, height}. The middle of the quay stays low so the PLAY caption reads clean.
	local random = scatter(7)
	for index, shed in ipairs({{0.285, 92, 34}, {0.345, 58, 46}, {0.395, 128, 18}, {0.5, 96, 13}, {0.575, 64, 24},
		{0.9, 64, 30}, {0.945, 90, 44}}) do
		local building = box(port, "Shed" .. index, {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(shed[1], 0, 1, 0),
			Size = UDim2.fromOffset(shed[2], shed[3])})
		for _ = 1, math.floor(shed[2] / 30) do
			box(building, "Window", {Position = UDim2.fromOffset(6 + math.floor(random() * (shed[2] - 12)), 6 + math.floor(random() * (shed[3] - 12))),
				Size = UDim2.fromOffset(3, 2), BackgroundColor3 = LAMP, BackgroundTransparency = 0.35 + random() * 0.3})
		end
	end

	-- a gantry crane
	local crane = box(port, "Crane", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0.655, 0, 1, 0), Size = UDim2.fromOffset(60, 96),
		BackgroundTransparency = 1})
	box(crane, "LegA", {Position = UDim2.fromOffset(4, 22), Size = UDim2.new(0, 4, 1, -22)})
	box(crane, "LegB", {Position = UDim2.fromOffset(40, 22), Size = UDim2.new(0, 4, 1, -22)})
	box(crane, "Beam", {Position = UDim2.fromOffset(0, 22), Size = UDim2.fromOffset(48, 6)})
	box(crane, "Boom", {Position = UDim2.fromOffset(-30, 14), Size = UDim2.fromOffset(170, 4)})
	box(crane, "Cab", {Position = UDim2.fromOffset(18, 8), Size = UDim2.fromOffset(14, 14)})
	box(crane, "Cable", {Position = UDim2.fromOffset(128, 18), Size = UDim2.fromOffset(1, 30)})

	-- a moored ship, its portholes lit
	local ship = box(port, "Ship", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0.725, 0, 1, 2), Size = UDim2.fromOffset(200, 90),
		BackgroundTransparency = 1})
	box(ship, "Hull", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromOffset(196, 18)})
	box(ship, "Bow", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 196, 1, -12), Size = UDim2.fromOffset(15, 15), Rotation = 45})
	box(ship, "Deckhouse", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 48, 1, -18), Size = UDim2.fromOffset(72, 16)})
	box(ship, "Bridge", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 64, 1, -34), Size = UDim2.fromOffset(38, 14)})
	box(ship, "Funnel", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 40, 1, -34), Size = UDim2.fromOffset(16, 18)})
	box(ship, "Mast", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 82, 1, -48), Size = UDim2.fromOffset(3, 40)})
	glow(ship, "MastheadGlow", 22, P.red, 0.55, UDim2.new(0, 83, 1, -88))
	disc(ship, "Masthead", 4, P.red, 0, UDim2.new(0, 83, 1, -88))
	for index = 1, 7 do
		disc(ship, "Porthole", 3, LAMP, 0.25, UDim2.new(0, 20 + index * 20, 1, -10))
	end

	-- red harbour light at the end of the breakwater
	box(port, "LightPost", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.255, 0, 1, -8), Size = UDim2.fromOffset(3, 12)})
	glow(port, "HarbourLightGlow", 34, P.red, 0.6, UDim2.new(0.255, 0, 1, -21))
	disc(port, "HarbourLight", 5, rgb(255, 90, 100), 0, UDim2.new(0.255, 0, 1, -21))

	lighthouse(port)
end

local function water(background)
	local sea = box(background, "Water", {Position = UDim2.fromScale(0, HORIZON), Size = UDim2.fromScale(1, 1 - HORIZON),
		BackgroundColor3 = Color3.new(1, 1, 1)})
	Theme.gradient(sea, {{0, rgb(20, 40, 82)}, {0.25, rgb(11, 23, 50)}, {1, rgb(4, 9, 21)}}, 90)
	box(sea, "HorizonLine", {Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = P.white, BackgroundTransparency = 0.8})

	local random = scatter(99)
	for index = 1, 12 do
		box(sea, "Swell" .. index, {Position = UDim2.new(random() * 0.8, 0, 0.08 + random() * 0.85, 0), Size = UDim2.new(0.1 + random() * 0.25, 0, 0, 1),
			BackgroundColor3 = P.white, BackgroundTransparency = 0.93})
	end

	-- reflections: {x, colour, bars, first width, last width, first transparency}; the bars spread out
	-- towards the viewer and wobble sideways like broken light on swell
	for _, column in ipairs({{0.84, rgb(236, 232, 218), 10, 14, 70, 0.45}, {0.085, LAMP, 6, 8, 30, 0.5},
		{0.255, P.red, 5, 6, 22, 0.45}, {0.79, LAMP, 3, 8, 18, 0.7}}) do
		for bar = 1, column[3] do
			local t = (bar - 1) / math.max(column[3] - 1, 1)
			local width = (column[4] + (column[5] - column[4]) * t) * (0.6 + random() * 0.7)
			local streak = box(sea, "Reflection", {AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = column[2],
				Position = UDim2.new(column[1], (random() - 0.5) * (8 + 20 * t), 0, 4 + ((bar - 1) ^ 1.35) * 11),
				Size = UDim2.fromOffset(width, bar > column[3] * 0.6 and 3 or 2),
				BackgroundTransparency = column[6] + t * 0.3})
			Theme.corner(streak, 1)
			Theme.loop(streak, 1.2 + random() * 1.4, {BackgroundTransparency = math.min(0.97, column[6] + t * 0.3 + 0.2)}, random())
		end
	end
end

-- Builds the scene into `background` (a full-screen Frame). Order matters: later draws on top.
function HarborBackdrop.build(background)
	sky(background)
	skyline(background)
	water(background)
	return background
end

return HarborBackdrop
