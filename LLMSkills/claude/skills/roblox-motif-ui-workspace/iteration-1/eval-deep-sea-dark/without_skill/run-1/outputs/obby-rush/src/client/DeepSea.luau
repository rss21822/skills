-- Deep-sea scenery for the menus and the one animation driver that moves it.
--   DeepSea.backdrop(frame, viewport) : water column (petrol haze -> black), faint light shafts,
--                                       marine snow, rising bubbles, two far-off jellyfish
--   DeepSea.lure(parent, size, pos)   : the anglerfish around the PLAY bulb (halo, stalk, eye, teeth)
--   DeepSea.animate(gui)              : one RenderStepped loop over every descendant tagged with a
--                                       "Motion" attribute (Theme.tag). Off when Reduced Motion is on;
--                                       disconnects when the ScreenGui is destroyed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))

local DeepSea = {}
local C = Theme.colors
local create = Theme.create
local WHITE = Color3.new(1, 1, 1)

function DeepSea.viewportSize()
	local camera = workspace and workspace.CurrentCamera
	local size = camera and camera.ViewportSize
	-- Early in client start-up the camera can briefly report a 1x1 viewport; fall back to 720p then.
	if size and size.X >= 200 and size.Y >= 200 then
		return size
	end
	return Vector2.new(1280, 720)
end

function DeepSea.backdrop(background, viewport)
	viewport = viewport or DeepSea.viewportSize()
	background.BackgroundColor3 = WHITE -- the gradient carries the colour
	Theme.gradient(background, {{0, C.haze}, {0.42, C.deep}, {1, C.abyss}}, nil, 90)

	local layer = create("Frame", {Name = "Abyss", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		ClipsDescendants = true, ZIndex = 1, Parent = background})
	local rand = Theme.random(20260924)

	-- Light shafts: the last of the sun, fading long before the bottom of the screen.
	local shafts = {
		{x = 0.2, w = 90, r = 17, t = 0.9},
		{x = 0.43, w = 150, r = 12, t = 0.93},
		{x = 0.63, w = 64, r = 19, t = 0.9},
		{x = 0.84, w = 120, r = 14, t = 0.94},
	}
	for i, ray in ipairs(shafts) do
		local shaft = create("Frame", {Name = "Shaft" .. i, Size = UDim2.new(0, ray.w, 0.9, 0), AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(ray.x, 0, -0.12, 0), Rotation = ray.r, BackgroundColor3 = C.bioCyan:Lerp(WHITE, 0.55),
			BackgroundTransparency = 0, BorderSizePixel = 0, Parent = layer})
		Theme.gradient(shaft, nil, {{0, ray.t}, {0.55, 0.975}, {1, 1}}, 90)
		Theme.tag(shaft, "pulse", nil, 0.35 + i * 0.11, i * 1.9, 0.6)
	end

	-- Side vignettes pull the eye to the lure in the middle.
	for _, side in ipairs({{0, 0}, {1, 180}}) do
		local vignette = create("Frame", {Name = "Vignette", Size = UDim2.new(0.24, 0, 1, 0), AnchorPoint = Vector2.new(side[1], 0),
			Position = UDim2.fromScale(side[1], 0), BackgroundColor3 = C.abyss, BorderSizePixel = 0, Parent = layer})
		Theme.gradient(vignette, nil, {{0, 0.1}, {1, 1}}, side[2])
	end

	-- Two far-off jellyfish, dim and slow (smaller on short screens).
	local k = math.clamp(viewport.Y / 720, 0.55, 1.2)
	local far = Theme.jelly(layer, "FarJelly1", {width = math.floor(150 * k), hue = C.jellyViolet, tentacles = 5, length = 130 * k, dots = 7,
		dim = 0.55, phase = 0.4, anchor = Vector2.new(0.5, 0), position = UDim2.new(0.85, 0, 0.2, 0)})
	Theme.tag(far, "drift", 16, 0.32, 0.4)
	local near = Theme.jelly(layer, "FarJelly2", {width = math.floor(84 * k), hue = C.jellyPink, tentacles = 4, length = 84 * k, dots = 6,
		dim = 0.62, phase = 2.1, anchor = Vector2.new(0.5, 0), position = UDim2.new(0.11, 0, 0.3, 0)})
	Theme.tag(near, "drift", 11, 0.44, 2.1)

	-- Marine snow drifting down.
	for i = 1, 34 do
		local size = rand() < 0.3 and 3 or 2
		local flake = create("Frame", {Name = "Snow" .. i, Size = UDim2.fromOffset(size, size), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(rand(), rand()), BackgroundColor3 = C.snow, BackgroundTransparency = 0.45 + rand() * 0.4,
			BorderSizePixel = 0, Parent = layer})
		Theme.round(flake)
		Theme.tag(flake, "fall", 3 + rand() * 6, 5 + rand() * 9, rand() * 6.28)
	end

	-- Bubbles rising.
	for i = 1, 13 do
		local diameter = 6 + math.floor(rand() * 20)
		local bubble = Theme.bubble(layer, "Bubble" .. i, diameter, UDim2.fromScale(0.04 + rand() * 0.92, rand() * 1.05))
		Theme.tag(bubble, "rise", 3 + rand() * 6, 16 + rand() * 30, rand() * 6.28)
	end
	return layer
end

-- The anglerfish lurking lower-left of its lure; `size` is the PLAY bulb diameter.
-- options.roomBelow: pixels free under the bulb centre; without ~2.6 bulb radii the fish stays hidden
-- in the dark and only the lure, its stalk and its halo are drawn.
function DeepSea.lure(parent, size, position, options)
	options = options or {}
	local r = size / 2
	local showFish = (options.roomBelow or math.huge) >= r * 2.6
	local rig = create("Frame", {Name = "Lure", Size = UDim2.fromOffset(size, size), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position, BackgroundTransparency = 1, ZIndex = 2, Parent = parent})
	local function at(x, y)
		return UDim2.new(0.5, x, 0.5, y)
	end

	-- Head: barely there in the dark; only the brow facing the lure catches a rim of light.
	-- Geometry is in bulb radii (r) so the fish scales with the button.
	local headCenter, headRadius = Vector2.new(-r * 3.3, r * 2.9), r * 2.45
	local head = showFish and Theme.circle(rig, "Head", headRadius * 2, at(headCenter.X, headCenter.Y), C.haze:Lerp(C.lure, 0.1), 0)
	-- (A circle's nearest point to a 139-degree gradient's start sits at t ~ 0.146, so the lit arc lives
	-- between t = 0.146 and ~0.2: about +-35 degrees of brow.)
	if head then
		Theme.gradient(head, nil, {{0, 0.6}, {0.15, 0.62}, {0.3, 0.9}, {0.45, 1}, {1, 1}}, 139)
		local rim = Theme.stroke(head, {color = C.lure:Lerp(C.lureCore, 0.3), thickness = 2.5, transparency = 0})
		Theme.gradient(rim, nil, {{0, 0}, {0.15, 0.15}, {0.205, 1}, {1, 1}}, 139)
	end

	local halo = Theme.glow(rig, "Halo", size * 3, at(0, 0), C.lure, {rings = 6, strength = 0.88, inner = 0.34})
	Theme.tag(halo, "breathe", 0.045, 1.7, 0)

	-- Stalk (illicium): grows from the brow, arches over, glows as it nears the bulb.
	local brow = headCenter + Vector2.new(0.5, -0.866) * headRadius
	if not showFish then -- no head on screen: the stalk rises out of the dark lower-left instead
		brow = Vector2.new(-r * 1.9, r * 1.1)
	end
	local p0, p1, p2 = brow, Vector2.new(-r * 2.35, -r * 2.5), Vector2.new(0, -r * 0.96)
	local segments = 24
	local previous = p0
	for i = 1, segments do
		local s = i / segments
		local point = p0 * ((1 - s) * (1 - s)) + p1 * (2 * (1 - s) * s) + p2 * (s * s)
		local delta = point - previous
		local middle = (point + previous) / 2
		local segment = create("Frame", {Name = "Stalk" .. i, Size = UDim2.fromOffset(delta.Magnitude + 2, 4.5 - s * 1.5),
			AnchorPoint = Vector2.new(0.5, 0.5), Position = at(middle.X, middle.Y), Rotation = math.deg(math.atan2(delta.Y, delta.X)),
			BackgroundColor3 = C.lure:Lerp(C.haze, (1 - s) * 0.8), BackgroundTransparency = 0.12 + 0.75 * (1 - s) ^ 1.6,
			BorderSizePixel = 0, Parent = rig})
		Theme.round(segment)
		previous = point
	end

	if not showFish then
		return rig
	end

	-- Eye: a green glint in the dark, blinking now and then.
	local eyeAt = at(-r * 1.72, r * 1.62)
	Theme.glow(rig, "EyeGlow", 40, eyeAt, C.bioGreen, {rings = 3, strength = 0.86, inner = 0.4})
	local eye = Theme.circle(rig, "Eye", 14, eyeAt, C.lureCore:Lerp(C.bioGreen, 0.35), 0.1)
	Theme.circle(eye, "Pupil", 7, UDim2.fromScale(0.62, 0.55), C.abyss, 0)
	Theme.tag(eye, "blink", nil, 5.2, 1.3)

	-- Teeth: triangles catching the lure light. Each is a 45-degree square whose other half is clipped
	-- away by a small frame, so no image assets are needed. `down` = hangs from the upper jaw.
	local bone = C.lureCore:Lerp(C.snow, 0.45)
	local k = r / 84
	local function fang(name, x, y, width, down)
		local d = width / math.sqrt(2)
		local clip = create("Frame", {Name = name, Size = UDim2.fromOffset(width, width / 2 + 1),
			AnchorPoint = Vector2.new(0.5, down and 0 or 1), Position = at(r * x, r * y), BackgroundTransparency = 1,
			ClipsDescendants = true, Parent = rig})
		create("Frame", {Name = "Point", Size = UDim2.fromOffset(d, d), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, down and 0 or 1), Rotation = 45, BackgroundColor3 = bone,
			BackgroundTransparency = 0.2, BorderSizePixel = 0, Parent = clip})
		return clip
	end
	local upper = {{-1.9, 1.99, 11}, {-1.62, 1.97, 14}, {-1.33, 1.94, 16}, {-1.05, 1.91, 14}, {-0.8, 1.87, 11}}
	for i, t in ipairs(upper) do
		fang("FangUp" .. i, t[1], t[2], t[3] * k, true)
	end
	local lower = {{-2.0, 2.46, 12}, {-1.76, 2.49, 15}, {-1.48, 2.5, 18}, {-1.19, 2.46, 17}, {-0.92, 2.38, 14}, {-0.69, 2.27, 11}}
	for i, t in ipairs(lower) do
		fang("FangLow" .. i, t[1], t[2], t[3] * k, false)
	end
	return rig
end

local MOVERS = {sway = true, bob = true, drift = true, pulse = true, breathe = true, rise = true, fall = true, blink = true}

-- Pixel size of a GuiObject from its Size chain (independent of layout timing). UDim offsets are
-- integers, so small motions are applied through the float Scale part: pixels / parent size.
local function pixelSize(object, viewport)
	if object == nil or not object:IsA("GuiObject") then
		return viewport
	end
	local parent = pixelSize(object.Parent, viewport)
	local size = object.Size
	return Vector2.new(math.max(1, parent.X * size.X.Scale + size.X.Offset), math.max(1, parent.Y * size.Y.Scale + size.Y.Offset))
end

local function collect(root, viewport)
	local entries = {}
	for _, object in ipairs(root:GetDescendants()) do
		local kind = object:GetAttribute("Motion")
		if kind and MOVERS[kind] then
			table.insert(entries, {
				object = object,
				kind = kind,
				amp = object:GetAttribute("Amp") or 0,
				speed = object:GetAttribute("Speed") or 1,
				phase = object:GetAttribute("Phase") or 0,
				range = object:GetAttribute("Range") or 0,
				position = object.Position,
				size = object.Size,
				transparency = object.BackgroundTransparency or 0,
				parentSize = pixelSize(object.Parent, viewport),
				-- only pages hide; skip work for descendants of a hidden page
				gate = object:FindFirstAncestor("ShopPage") or object:FindFirstAncestor("SettingsPage")
					or object:FindFirstAncestor("InventoryPage") or object:FindFirstAncestor("QuestsPage"),
			})
		end
	end
	return entries
end

local function step(entries, t, dt, rand)
	for _, e in ipairs(entries) do
		if e.gate == nil or e.gate.Visible then
			local o, p = e.object, e.position
			local wave = math.sin(t * e.speed + e.phase)
			local ps = e.parentSize
			if e.kind == "sway" then
				o.Position = UDim2.new(p.X.Scale + wave * e.amp / ps.X, p.X.Offset, p.Y.Scale, p.Y.Offset)
			elseif e.kind == "bob" then
				o.Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale + wave * e.amp / ps.Y, p.Y.Offset)
			elseif e.kind == "drift" then
				o.Position = UDim2.new(p.X.Scale + wave * e.amp / ps.X, p.X.Offset,
					p.Y.Scale + math.cos(t * e.speed * 0.7 + e.phase) * e.amp * 0.6 / ps.Y, p.Y.Offset)
			elseif e.kind == "pulse" then
				o.BackgroundTransparency = math.min(1, e.transparency + e.range * (0.5 + 0.5 * wave))
			elseif e.kind == "breathe" then
				local k = 1 + e.amp * wave
				o.Size = UDim2.new(e.size.X.Scale * k, e.size.X.Offset * k, e.size.Y.Scale * k, e.size.Y.Offset * k)
			elseif e.kind == "blink" then
				local closed = (t + e.phase) % e.speed < 0.14
				o.Size = closed and UDim2.new(e.size.X.Scale, e.size.X.Offset, 0, 2) or e.size
			elseif e.kind == "rise" or e.kind == "fall" then
				local direction = e.kind == "rise" and -1 or 1
				e.y = (e.y or p.Y.Scale) + direction * e.speed * dt / ps.Y
				if e.kind == "rise" and e.y < -0.06 then
					e.y, e.x = 1.06, 0.04 + rand() * 0.92
				elseif e.kind == "fall" and e.y > 1.03 then
					e.y, e.x = -0.03, rand()
				end
				o.Position = UDim2.new((e.x or p.X.Scale) + wave * e.amp / ps.X, 0, e.y, 0)
			end
		end
	end
end
DeepSea.step = step

function DeepSea.animate(gui)
	if Theme.reducedMotion() then
		return nil
	end
	local entries = collect(gui, DeepSea.viewportSize())
	local rand = Theme.random(7)
	local t = 0
	local connection = game:GetService("RunService").RenderStepped:Connect(function(dt)
		if gui.Enabled == false then
			return
		end
		t += dt
		step(entries, t, dt, rand)
	end)
	gui.Destroying:Connect(function()
		connection:Disconnect()
	end)
	return connection
end

return DeepSea
