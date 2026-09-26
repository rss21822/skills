-- UI theme shared by every screen: "Abyss", a deep-sea expedition skin.
--
-- In the deep sea the only light comes from living things, so every colour here has a job:
--   * lure    (anglerfish esca, warm amber)      -> primary actions: PLAY, Buy
--   * jelly   (pink / violet / green glow)       -> navigation and the pages it opens
--   * bubble  (clear glass with a pale rim)      -> secondary actions: close, toggles
--   * the dark itself is ink-black with a petrol tint that deepens to black; never dashboard navy.
-- Shapes are organic (circles, bells, pills, dotted tentacles) instead of thin-bordered rectangles.
--
-- Decorative instances that should move carry a "Motion" attribute (see src/client/DeepSea.luau);
-- this module never touches RunService, so any screen can use it and tests can build it headless.
local Theme = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

Theme.palette = {
	abyss = rgb(3, 7, 8), -- bottom of the screen: black with a green-petrol cast
	deep = rgb(6, 18, 20),
	haze = rgb(15, 46, 47), -- the last trace of light from far above
	ink = rgb(8, 20, 22), -- membrane / page body
	membrane = rgb(15, 36, 38), -- bubble button body
	lure = rgb(255, 181, 71), -- anglerfish lure
	lureCore = rgb(255, 246, 205),
	lureDeep = rgb(255, 122, 26),
	jellyPink = rgb(255, 111, 216),
	jellyViolet = rgb(169, 139, 255),
	bioGreen = rgb(92, 255, 198),
	bioCyan = rgb(120, 232, 255),
	foam = rgb(234, 251, 246), -- main text
	mist = rgb(134, 169, 163), -- secondary text
	inkText = rgb(43, 21, 0), -- text sitting on the lure
	coral = rgb(255, 92, 112),
	snow = rgb(205, 232, 224), -- marine snow
}
local P = Theme.palette

-- Role names other screens already read (background, panel, accent...) plus the motif colours.
Theme.colors = {
	background = P.abyss,
	panel = P.ink,
	panelLight = P.membrane,
	accent = P.lure,
	text = P.foam,
	subtext = P.mist,
	danger = P.coral,
	success = P.bioGreen,
}
for key, value in pairs(P) do
	Theme.colors[key] = value
end

-- Legacy enum fonts (for screens that still set .Font) and the FontFace set the helpers use.
Theme.font = Enum.Font.Nunito
Theme.fontBold = Enum.Font.FredokaOne
Theme.faces = {
	body = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.SemiBold),
	bold = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.ExtraBold),
	display = Font.new("rbxasset://fonts/families/FredokaOne.json"),
}

local function create(className, props)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then
			object[key] = value
		end
	end
	object.Parent = props.Parent
	return object
end
Theme.create = create

-- Small deterministic generator so decorative scatter looks the same on every client and in previews.
function Theme.random(seed)
	local state = (seed or 1) % 2147483646 + 1
	return function()
		state = (state * 16807) % 2147483647
		return (state - 1) / 2147483646
	end
end

function Theme.formatNumber(value)
	local text = tostring(math.floor(tonumber(value) or 0))
	local sign, digits = string.match(text, "^(-?)(%d+)$")
	if not digits then
		return text
	end
	local out = string.reverse(digits)
	out = string.gsub(out, "(%d%d%d)", "%1,")
	out = string.reverse(out)
	out = string.gsub(out, "^,", "")
	return sign .. out
end

local function reducedMotion()
	local ok, value = pcall(function()
		return game:GetService("GuiService").ReducedMotionEnabled
	end)
	return ok and value == true
end
Theme.reducedMotion = reducedMotion

-- Tween that degrades to an instant set when the player asked for reduced motion.
function Theme.tween(object, seconds, props, style)
	if reducedMotion() then
		for key, value in pairs(props) do
			object[key] = value
		end
		return nil
	end
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local tween = game:GetService("TweenService"):Create(object, info, props)
	tween:Play()
	return tween
end

-- radius: number (pixels), UDim, or nil (8 px). Use Theme.round for pills and circles.
function Theme.corner(object, radius)
	local value = typeof(radius) == "UDim" and radius or UDim.new(0, radius or 8)
	return create("UICorner", {CornerRadius = value, Parent = object})
end

function Theme.round(object)
	return create("UICorner", {CornerRadius = UDim.new(1, 0), Parent = object})
end

local function colorSequence(points)
	local keypoints = {}
	for _, point in ipairs(points) do
		table.insert(keypoints, ColorSequenceKeypoint.new(point[1], point[2]))
	end
	return ColorSequence.new(keypoints)
end

local function numberSequence(points)
	local keypoints = {}
	for _, point in ipairs(points) do
		table.insert(keypoints, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	return NumberSequence.new(keypoints)
end

-- colors / transparency: lists of {time, value}; rotation 90 = top to bottom.
function Theme.gradient(object, colors, transparency, rotation)
	local props = {Rotation = rotation or 90, Parent = object}
	if colors then
		props.Color = colorSequence(colors)
	end
	if transparency then
		props.Transparency = numberSequence(transparency)
	end
	return create("UIGradient", props)
end

-- options: color, thickness, transparency, mode, fade (rim light: lit at the top, lost in the dark below)
function Theme.stroke(object, options)
	options = options or {}
	local stroke = create("UIStroke", {Color = options.color or P.bioCyan, Thickness = options.thickness or 1.5,
		Transparency = options.transparency or 0.5, ApplyStrokeMode = options.mode or Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round, Parent = object})
	if options.fade then
		Theme.gradient(stroke, nil, {{0, 0}, {0.55, 0.5}, {1, 0.92}}, 90)
	end
	return stroke
end

-- Round dot centred on `position`. diameter: pixels or a UDim2.
function Theme.circle(parent, name, diameter, position, color, transparency)
	local size = typeof(diameter) == "UDim2" and diameter or UDim2.fromOffset(diameter, diameter)
	local dot = create("Frame", {Name = name, Size = size, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position or UDim2.fromScale(0.5, 0.5), BackgroundColor3 = color or WHITE,
		BackgroundTransparency = transparency or 0, BorderSizePixel = 0, Parent = parent})
	Theme.round(dot)
	return dot
end

local function tag(object, kind, amp, speed, phase, range)
	object:SetAttribute("Motion", kind)
	if amp then object:SetAttribute("Amp", amp) end
	if speed then object:SetAttribute("Speed", speed) end
	if phase then object:SetAttribute("Phase", phase) end
	if range then object:SetAttribute("Range", range) end
	return object
end
Theme.tag = tag

-- Soft bioluminescent halo: concentric see-through discs, densest in the middle.
-- options: rings (5), strength (transparency of the inner ring, 0.86), inner (smallest ring as a fraction)
function Theme.glow(parent, name, diameter, position, color, options)
	options = options or {}
	local holder = create("Frame", {Name = name, Size = UDim2.fromOffset(diameter, diameter), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position or UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, Parent = parent})
	local rings = options.rings or 5
	local inner = options.inner or 0.35
	local strength = options.strength or 0.86
	for i = 1, rings do
		local f = inner + (1 - inner) * (i - 1) / math.max(rings - 1, 1)
		local transparency = strength + (1 - strength) * (i - 1) / rings
		Theme.circle(holder, "Ring" .. i, UDim2.fromScale(f, f), UDim2.fromScale(0.5, 0.5), color, transparency)
	end
	return holder
end

-- Decorative glass bubble: faint fill, bright rim, one glint.
function Theme.bubble(parent, name, diameter, position, tint)
	tint = tint or P.bioCyan
	local bubble = Theme.circle(parent, name, diameter, position, tint, 0.9)
	Theme.stroke(bubble, {color = tint:Lerp(WHITE, 0.45), thickness = diameter >= 16 and 1.5 or 1, transparency = 0.3})
	Theme.circle(bubble, "Glint", UDim2.fromScale(0.3, 0.3), UDim2.fromScale(0.34, 0.32), WHITE, 0.25)
	return bubble
end

-- Jellyfish drawn from primitives: dome bell, inner organ, margin lights, dotted glowing tentacles.
-- options: width, hue, tentacles, length, dots, dim (0..1 extra fade), phase, position, anchor
-- The bell occupies the returned frame (width x width/2); tentacles hang below it.
function Theme.jelly(parent, name, options)
	options = options or {}
	local w = options.width or 128
	local h = math.floor(w / 2)
	local hue = options.hue or P.jellyPink
	local dim = options.dim or 0
	local phase = options.phase or 0
	local count = options.tentacles or 4
	local length = options.length or 40
	local dots = options.dots or 5
	local function fade(t)
		return t + (1 - t) * dim
	end

	local root = create("Frame", {Name = name, Size = UDim2.fromOffset(w, h), Position = options.position or UDim2.new(),
		AnchorPoint = options.anchor or Vector2.new(0, 0), BackgroundTransparency = 1, Parent = parent})

	local halo = Theme.glow(root, "Halo", w * 1.6, UDim2.new(0.5, 0, 1, -h * 0.4), hue, {rings = 5, strength = fade(0.93), inner = 0.3})
	halo.ZIndex = 1

	local tentacles = create("Frame", {Name = "Tentacles", Size = UDim2.new(1, 0, 0, length), Position = UDim2.new(0, 0, 1, 2),
		BackgroundTransparency = 1, ZIndex = 1, Parent = root})
	for j = 1, count do
		local x = 0.2 + 0.6 * (j - 1) / math.max(count - 1, 1)
		for k = 1, dots do
			local p = k / dots
			local d = math.max(2, math.floor(w / 17 * (1 - p * 0.55) + 0.5))
			local dot = Theme.circle(tentacles, "T" .. j .. "_" .. k, d, UDim2.new(x, 0, 0, p * length), hue:Lerp(WHITE, 0.25), fade(0.15 + p * 0.55))
			tag(dot, "sway", 1.5 + p * w / 13, 1.8, phase + j * 1.3 - p * 2.4)
		end
	end
	for j, x in ipairs({0.43, 0.57}) do -- oral arms: soft ribbons under the middle of the bell
		local arm = create("Frame", {Name = "Arm" .. j, Size = UDim2.new(0, math.max(4, math.floor(w * 0.07)), 0, length * 0.75),
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, 0, 0, -2), BackgroundColor3 = hue,
			BackgroundTransparency = fade(0.45), BorderSizePixel = 0, Parent = tentacles})
		Theme.round(arm)
		Theme.gradient(arm, nil, {{0, 0}, {1, 1}}, 90)
		tag(arm, "sway", w / 30, 1.3, phase + j * 2)
	end

	-- Bell: a full circle clipped to its top half (3 px margin so the rim stroke survives the clip).
	local clip = create("Frame", {Name = "BellClip", Size = UDim2.new(1, 6, 1, 3), Position = UDim2.fromOffset(-3, -3),
		BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 2, Parent = root})
	local bell = Theme.circle(clip, "Bell", w, UDim2.fromOffset(3 + w / 2, 3 + w / 2), WHITE, fade(0.5))
	Theme.gradient(bell, {{0, hue:Lerp(WHITE, 0.55)}, {0.28, hue}, {0.5, hue:Lerp(BLACK, 0.3)}, {1, hue:Lerp(BLACK, 0.3)}}, nil, 90)
	Theme.stroke(bell, {color = hue:Lerp(WHITE, 0.35), thickness = 2, transparency = fade(0.1)})
	local core = Theme.circle(clip, "Core", UDim2.fromOffset(w * 0.36, w * 0.36), UDim2.fromOffset(3 + w / 2, 3 + h * 0.92), hue:Lerp(WHITE, 0.6), fade(0.7))
	core.ZIndex = 2
	local sheen = Theme.circle(clip, "Sheen", UDim2.fromOffset(w * 0.26, w * 0.09), UDim2.fromOffset(3 + w * 0.3, 3 + h * 0.34), WHITE, fade(0.62))
	sheen.Rotation = -30
	sheen.ZIndex = 3

	-- Margin lights chase around the rim like a comb jelly.
	local margin = create("Frame", {Name = "Margin", Size = UDim2.new(1, 0, 0, 0), Position = UDim2.new(0, 0, 1, 0),
		BackgroundTransparency = 1, ZIndex = 3, Parent = root})
	local lights = 7
	for i = 1, lights do
		local dot = Theme.circle(margin, "Light" .. i, math.max(3, math.floor(w / 20)), UDim2.new(0.05 + 0.9 * (i - 1) / (lights - 1), 0, 0, 0),
			hue:Lerp(WHITE, 0.55), fade(0.1))
		tag(dot, "pulse", nil, 3, phase - i * 0.8, 0.8)
	end
	return root
end

-- Page / card / bar surfaces.
-- options.variant: "membrane" (default: jellyfish-bell page), "capsule" (pill row), "clear" (layout only)
-- options.hue: the glow colour of the rim and inner light.
function Theme.panel(parent, name, size, position, options)
	options = options or {}
	local variant = options.variant or "membrane"
	local hue = options.hue or P.bioCyan
	local frame = create("Frame", {Name = name, Size = size, Position = position or UDim2.new(), BorderSizePixel = 0,
		BackgroundColor3 = P.ink, BackgroundTransparency = variant == "clear" and 1 or 0.08, Parent = parent})
	if variant == "clear" then
		return frame
	end
	if variant == "capsule" then
		frame.BackgroundColor3 = P.membrane
		frame.BackgroundTransparency = 0.25
		Theme.round(frame)
		Theme.stroke(frame, {color = hue, thickness = 1.5, transparency = 0.45, fade = true})
		local glint = Theme.circle(frame, "Glint", UDim2.fromOffset(18, 7), UDim2.fromOffset(24, 11), WHITE, 0.8)
		glint.Rotation = -25
		return frame
	end

	-- membrane: a lit bell top that sinks into black, rim light, lobed lower margin with chasing lights
	frame.BackgroundColor3 = WHITE
	frame.BackgroundTransparency = 0.03
	Theme.corner(frame, 28)
	Theme.gradient(frame, {{0, P.membrane:Lerp(hue, 0.1)}, {0.3, P.ink}, {1, P.abyss}}, nil, 90)
	Theme.stroke(frame, {color = hue, thickness = 2, transparency = 0.1, fade = true})
	local glow = create("Frame", {Name = "BellGlow", Size = UDim2.new(1, 0, 0, 120), BackgroundColor3 = hue,
		BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 1, Parent = frame})
	Theme.corner(glow, 28)
	Theme.gradient(glow, nil, {{0, 0.83}, {1, 1}}, 90)
	-- A few bubbles drift up inside the page (clipped to the body; animated only while it is open).
	local drift = create("Frame", {Name = "Bubbles", Size = UDim2.new(1, -40, 1, -80), Position = UDim2.new(0, 20, 0, 60),
		BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 1, Parent = frame})
	local rand = Theme.random(#name * 97 + 13)
	for i = 1, 6 do
		local bubble = Theme.bubble(drift, "Bubble" .. i, 6 + math.floor(rand() * 11), UDim2.fromScale(0.55 + rand() * 0.43, rand()), hue:Lerp(P.bioCyan, 0.5))
		tag(bubble, "rise", 2 + rand() * 4, 14 + rand() * 18, rand() * 6.28)
	end
	-- Lappets: the lower halves of a row of pills hanging under the edge, each tipped with a light.
	local lappets = create("Frame", {Name = "Lappets", Size = UDim2.new(1, -48, 0, 18), Position = UDim2.new(0, 24, 1, 0),
		BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 1, Parent = frame})
	local count = 12
	for i = 1, count do
		local x = (i - 0.5) / count
		local lobe = create("Frame", {Name = "Lobe" .. i, Size = UDim2.new(1 / count, -6, 0, 24), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, 0), BackgroundColor3 = P.abyss, BackgroundTransparency = 0.03, BorderSizePixel = 0, Parent = lappets})
		Theme.round(lobe)
		Theme.stroke(lobe, {color = hue, thickness = 1.5, transparency = 0.55})
		local light = Theme.circle(lappets, "Light" .. i, 5, UDim2.new(x, 0, 0, 12), hue:Lerp(WHITE, 0.45), 0.1)
		light.ZIndex = 2
		tag(light, "pulse", nil, 2.2, -i * 0.55, 0.8)
	end
	return frame
end

-- options: bold, display, color, align, frameSize, glow (Color3 outline glow)
function Theme.label(parent, name, text, size, options)
	options = options or {}
	local face = options.display and Theme.faces.display or options.bold and Theme.faces.bold or Theme.faces.body
	local label = create("TextLabel", {Name = name, Text = text, TextSize = size or 16, FontFace = face,
		TextColor3 = options.color or P.foam, BackgroundTransparency = 1, Size = options.frameSize or UDim2.new(1, 0, 0, (size or 16) + 8),
		TextXAlignment = options.align or Enum.TextXAlignment.Left, TextWrapped = true, ZIndex = 2, Parent = parent})
	if options.glow then
		create("UIStroke", {Name = "Glow", Color = options.glow, Thickness = options.glowThickness or 2.5, Transparency = 0.55,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = label})
	end
	return label
end

-- Toggle lamp: a photophore that is lit (green) or dark.
function Theme.setLit(button, on)
	button:SetAttribute("Lit", on == true)
	local lamp = button:FindFirstChild("Lamp")
	if lamp then
		lamp.BackgroundColor3 = on and P.bioGreen or P.membrane:Lerp(P.mist, 0.25)
		lamp.BackgroundTransparency = on and 0 or 0.1
		local halo = lamp:FindFirstChild("LampGlow")
		if halo then
			halo.Visible = on == true
		end
	end
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = on and P.bioGreen or P.mist
	end
	button.TextColor3 = on and P.foam or P.mist
end

-- options: primary (lure), danger, size (UDim2), order, textSize, hue (bubble rim colour),
--          shape ("pill" default, "orb" = round anglerfish bulb), lamp (toggle light) + lit
function Theme.button(parent, name, text, onClick, options)
	options = options or {}
	local kind = options.primary and "lure" or options.danger and "danger" or "bubble"
	local orb = options.shape == "orb"
	local hue = kind == "danger" and P.coral or options.hue or P.bioCyan
	local button = create("TextButton", {Name = name, Text = text, TextSize = options.textSize or 18,
		FontFace = kind == "lure" and Theme.faces.display or Theme.faces.bold,
		TextColor3 = kind == "lure" and P.inkText or kind == "danger" and P.coral:Lerp(WHITE, 0.4) or P.foam,
		BackgroundColor3 = P.membrane, BackgroundTransparency = 0.15, AutoButtonColor = false, BorderSizePixel = 0,
		Size = options.size or UDim2.new(1, 0, 0, 48), LayoutOrder = options.order or 0, ZIndex = 2, Parent = parent})
	Theme.round(button)

	local stroke, restStroke
	if kind == "lure" then
		button.BackgroundColor3 = WHITE
		button.BackgroundTransparency = 0
		-- UIGradient tints the label too; the ink text stays dark under every stop.
		Theme.gradient(button, {{0, P.lureCore}, {0.45, P.lure}, {1, P.lureDeep}}, nil, 90)
		stroke = Theme.stroke(button, {color = P.lureCore, thickness = orb and 3 or 2, transparency = orb and 0.15 or 0.3})
	else
		stroke = Theme.stroke(button, {color = hue, thickness = 1.5, transparency = 0.25, fade = true})
	end
	restStroke = stroke.Transparency

	local glint = Theme.circle(button, "Glint", orb and UDim2.fromScale(0.26, 0.13) or UDim2.new(0, 16, 0, 7),
		orb and UDim2.fromScale(0.32, 0.2) or UDim2.new(0, 22, 0, 11), WHITE, kind == "lure" and 0.3 or 0.72)
	glint.Rotation = -25

	if options.lamp then
		local lamp = Theme.circle(button, "Lamp", 18, UDim2.new(1, -30, 0.5, 0), P.bioGreen, 0)
		Theme.glow(lamp, "LampGlow", 44, UDim2.fromScale(0.5, 0.5), P.bioGreen, {rings = 3, strength = 0.8, inner = 0.45})
		Theme.setLit(button, options.lit ~= false)
	end

	local scale = create("UIScale", {Name = "Press", Scale = 1, Parent = button})
	local rest = button.BackgroundColor3
	button.MouseEnter:Connect(function()
		if kind == "lure" then
			Theme.tween(scale, 0.12, {Scale = 1.04})
		else
			button.BackgroundColor3 = rest:Lerp(hue, 0.16)
		end
		stroke.Transparency = math.max(0, restStroke - 0.2)
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = rest
		stroke.Transparency = restStroke
		Theme.tween(scale, 0.12, {Scale = 1})
	end)
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			Theme.tween(scale, 0.06, {Scale = 0.94})
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			Theme.tween(scale, 0.14, {Scale = 1}, Enum.EasingStyle.Back)
		end
	end)
	button.Activated:Connect(function()
		onClick(button)
	end)
	return button
end

-- Navigation jellyfish. The TextButton is the hit area (and keeps .Text for other scripts);
-- the drawn jelly lives in Body, which bobs without moving the hit area.
-- options: hue, size (UDim2 in pixels), order, textSize
function Theme.jellyButton(parent, name, text, onClick, options)
	options = options or {}
	local hue = options.hue or P.jellyPink
	local size = options.size or UDim2.fromOffset(128, 64)
	local order = options.order or 0
	local button = create("TextButton", {Name = name, Text = text, TextTransparency = 1, TextSize = options.textSize or 17,
		FontFace = Theme.faces.bold, BackgroundTransparency = 1, AutoButtonColor = false, BorderSizePixel = 0,
		Size = size, LayoutOrder = order, ZIndex = 2, Parent = parent})
	local body = create("Frame", {Name = "Body", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = button})
	tag(body, "bob", 3, 1.4, order * 1.7)
	local scale = create("UIScale", {Name = "Press", Scale = 1, Parent = body})
	Theme.jelly(body, "Jelly", {width = size.X.Offset, hue = hue, tentacles = 4, length = options.tentacleLength or 34, dots = 5, phase = order})
	local caption = create("TextLabel", {Name = "Caption", Text = text, TextSize = options.textSize or 17, FontFace = Theme.faces.bold,
		TextColor3 = P.foam, TextStrokeColor3 = P.abyss, TextStrokeTransparency = 0.35, BackgroundTransparency = 1,
		Size = UDim2.new(1, -16, 0, 26), Position = UDim2.new(0, 8, 1, -31), ZIndex = 4, Parent = body})
	button:GetPropertyChangedSignal("Text"):Connect(function()
		caption.Text = button.Text
	end)

	local bell = body.Jelly.BellClip.Bell
	local function paint()
		local selected = button:GetAttribute("Selected") == true
		local hover = button:GetAttribute("Hover") == true
		-- Selected = the jelly lights up: near-opaque bell with a dark caption (>= 4.8:1 on every hue);
		-- idle/hover keep a pale caption on a dimmer bell (>= 5.4:1). See DESIGN.md contrast table.
		bell.BackgroundTransparency = selected and 0.05 or hover and 0.38 or 0.5
		caption.TextColor3 = selected and P.abyss or P.foam
		caption.TextStrokeTransparency = selected and 1 or 0.35
		local rings = body.Jelly.Halo:GetChildren()
		local strength = selected and 0.84 or hover and 0.89 or 0.93
		for _, ring in ipairs(rings) do
			local index = tonumber(string.match(ring.Name, "%d+")) or 1
			ring.BackgroundTransparency = strength + (1 - strength) * (index - 1) / #rings
		end
	end
	button:SetAttribute("Selected", false)
	button:GetAttributeChangedSignal("Selected"):Connect(paint)
	paint()

	button.MouseEnter:Connect(function()
		button:SetAttribute("Hover", true)
		paint()
	end)
	button.MouseLeave:Connect(function()
		button:SetAttribute("Hover", false)
		paint()
		Theme.tween(scale, 0.12, {Scale = 1})
	end)
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			Theme.tween(scale, 0.06, {Scale = 0.92})
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			Theme.tween(scale, 0.18, {Scale = 1}, Enum.EasingStyle.Back)
		end
	end)
	button.Activated:Connect(function()
		onClick(button)
	end)
	return button
end

function Theme.setSelected(button, on)
	button:SetAttribute("Selected", on == true)
end

-- Page entrance: rises out of the dark with a small swell.
function Theme.popIn(frame)
	local scale = frame:FindFirstChild("OpenScale")
	if not scale then
		return
	end
	if reducedMotion() then
		scale.Scale = 1
		return
	end
	scale.Scale = 0.94
	Theme.tween(scale, 0.22, {Scale = 1}, Enum.EasingStyle.Back)
end

return Theme
