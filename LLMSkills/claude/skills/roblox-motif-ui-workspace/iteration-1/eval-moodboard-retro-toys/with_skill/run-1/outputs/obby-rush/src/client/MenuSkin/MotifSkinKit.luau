--!nocheck
-- MotifSkinKit: presentation helpers for a motif skin (client only, no image assets).
--
-- Copy this file into the game (for example src/client/ui/MotifSkinKit.luau) and build one kit from
-- the spec module that `scripts/skin_preview.py --luau` generates:
--
--   local Kit = require(path.MotifSkinKit)
--   local kit = Kit.new(require(path.MotifSpec))
--   kit:styleButton(button, {role = "primary"})
--
-- Every helper is guarded: a missing font, class or property leaves the original look in place
-- instead of breaking a screen. Motion goes through TweenService and honours reduced motion.
-- Instance names created here all start with "Motif" so tests and cleanup can find them.
local TweenService = game:GetService("TweenService")

local Kit = {}
Kit.__index = Kit

local function create(className, parent, props)
	local object = Instance.new(className)
	for key, value in pairs(props or {}) do
		object[key] = value
	end
	object.Parent = parent
	return object
end
Kit.create = create

local function try(fn, ...)
	local ok, result = pcall(fn, ...)
	return ok and result or nil
end

-- "#RRGGBB" or {r, g, b} or a Color3 -> Color3.
function Kit.color(value)
	if typeof(value) == "Color3" then return value end
	if type(value) == "table" then return Color3.fromRGB(value[1], value[2], value[3]) end
	if type(value) == "string" then
		local hex = value:gsub("#", "")
		return Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
	end
	error("bad colour " .. tostring(value))
end

function Kit.luminance(color)
	return 0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B
end

-- Kana, kanji, hangul and full-width forms (UTF-8 lead bytes E3-ED, EF BC-BF). Emoji are not CJK.
function Kit.cjk(text)
	return type(text) == "string" and (string.find(text, "[\227-\237]") ~= nil or string.find(text, "\239[\188-\191]") ~= nil)
end

-- spec: {palette = {ink, paper, panel, quiet, primary, danger, success, muted, disabled, dim, white,
--        outline?, onLight?, candies = {{name, colour}, ...}}, pastels = {...}, fonts = {role = {family, weight}},
--        shape = {corner, panelCorner, stroke, lip}, latinOnly = {role = true}, reduceMotion = fn?}
function Kit.new(spec)
	local self = setmetatable({spec = spec, fontCache = {}, faces = setmetatable({}, {__mode = "k"})}, Kit)
	local P = {}
	for key, value in pairs(spec.palette) do
		if key ~= "candies" then P[key] = Kit.color(value) end
	end
	P.white = P.white or Color3.new(1, 1, 1)
	-- Dark motifs set paper dark and ink light; `outline` (sticker edges, text outlines) and
	-- `onLight` (type on bright fills) then stay dark. Light motifs leave both = ink.
	P.outline = P.outline or P.ink
	P.onLight = P.onLight or (Kit.luminance(P.ink) < 0.5 and P.ink or P.outline)
	P.shade = P.shade or P.white:Lerp(P.outline, 0.22) -- lip multiplier
	self.candies, self.candyOrder = {}, {}
	for _, entry in ipairs(spec.palette.candies or {}) do
		self.candies[entry[1]] = Kit.color(entry[2])
		table.insert(self.candyOrder, entry[1])
	end
	self.pastels = {}
	for _, value in ipairs(spec.pastels or {}) do table.insert(self.pastels, Kit.color(value)) end
	if #self.pastels == 0 then
		for _, name in ipairs(self.candyOrder) do table.insert(self.pastels, self.candies[name]:Lerp(P.paper, 0.75)) end
	end
	self.P = P
	self.shape = spec.shape or {}
	return self
end

-- Motion -----------------------------------------------------------------------------------------
function Kit:reduceMotion()
	if type(self.spec.reduceMotion) == "function" then
		local ok, reduced = pcall(self.spec.reduceMotion)
		if ok then return reduced == true end
	end
	local ok, reduced = pcall(function() return game:GetService("GuiService").ReducedMotionEnabled end)
	return ok and reduced == true
end

-- One-shot tween; applied at once under reduced motion.
function Kit:tween(instance, props, seconds, style, direction)
	if self:reduceMotion() then
		pcall(function() for key, value in pairs(props) do instance[key] = value end end)
		return nil
	end
	return try(function()
		local tween = TweenService:Create(instance, TweenInfo.new(seconds or 0.2, style or Enum.EasingStyle.Back, direction or Enum.EasingDirection.Out), props)
		tween:Play()
		return tween
	end)
end

-- Endless yo-yo loop the caller cancels (cancelled automatically when the instance is destroyed).
function Kit:loop(instance, props, seconds, delay)
	if self:reduceMotion() then return nil end
	return try(function()
		local tween = TweenService:Create(instance, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, delay or 0), props)
		tween:Play()
		instance.Destroying:Connect(function() tween:Cancel() end)
		return tween
	end)
end

-- Type -------------------------------------------------------------------------------------------
-- Built-in families have no CJK glyphs: Japanese falls back to the system font AT THE REQUESTED
-- WEIGHT, so body roles should ask for Bold/Heavy. Latin-only display faces (LuckiestGuy, Bangers,
-- Creepster, ...) are swapped to the "title" role for strings that contain CJK.
function Kit:font(role)
	local cached = self.fontCache[role]
	if cached ~= nil then return cached or nil end
	local spec = (self.spec.fonts or {})[role] or (self.spec.fonts or {}).body
	local font = spec and try(function()
		return Font.new("rbxasset://fonts/families/" .. spec[1] .. ".json", Enum.FontWeight[spec[2] or "Bold"])
	end)
	self.fontCache[role] = font or false
	return font
end

function Kit:setFont(object, role)
	local latinOnly = self.spec.latinOnly or {display = true}
	if latinOnly[role] and Kit.cjk(object.Text) then role = "title" end
	local font = self:font(role)
	if font then pcall(function() object.FontFace = font end) end
end

-- Sticker text: a round-joined outline around the glyphs (Contextual stroke on a text object).
function Kit:outline(object, thickness, color)
	return try(function()
		local stroke = object:FindFirstChild("MotifTextOutline") or create("UIStroke", object, {Name = "MotifTextOutline"})
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Color = color or self.P.outline
		stroke.Thickness = thickness or Kit.strokeFor(object.TextSize)
		stroke.Transparency = 0
		return stroke
	end)
end

function Kit.strokeFor(textSize)
	return math.clamp((textSize or 16) / 8.5, 1.5, 4)
end

-- Text colour for a fill: light fills take dark (onLight) type; bright fills take dark type at body
-- sizes; everything else takes white type with an outline. Returns colour, outline thickness or nil.
function Kit:textOn(fill, textSize)
	local lum = Kit.luminance(fill)
	if lum > 0.82 then return self.P.onLight, nil end
	if lum > 0.65 and (textSize or 16) < 24 then return self.P.onLight, nil end
	return self.P.white, Kit.strokeFor(textSize)
end

-- A heading that must stay on one line at phone width: scale down instead of clipping.
function Kit:fitHeading(label, maxSize, minSize)
	return try(function()
		label.TextWrapped, label.TextScaled = false, true
		local constraint = label:FindFirstChild("MotifHeadingSize") or create("UITextSizeConstraint", label, {Name = "MotifHeadingSize"})
		constraint.MaxTextSize, constraint.MinTextSize = maxSize or 34, minSize or 14
		return constraint
	end)
end

-- Surfaces ---------------------------------------------------------------------------------------
-- Pressed-in lip: a UIGradient MULTIPLIES the fill (and any text on the same object), so the bottom
-- `pixels` read one shade darker while the text band stays white-multiplied (unchanged).
function Kit:lip(object, pixels, shade)
	return try(function()
		local gradient = object:FindFirstChild("MotifLip")
		local fresh = gradient == nil
		if fresh then gradient = create("UIGradient", object, {Name = "MotifLip", Rotation = 90}) end
		local white, dark = self.P.white, shade or self.P.shade
		local function update()
			local height = object.AbsoluteSize.Y
			local cut = height > 1 and math.clamp(1 - (pixels or self.shape.lip or 6) / height, 0.6, 0.95) or 0.86
			gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, white), ColorSequenceKeypoint.new(cut - 0.002, white),
				ColorSequenceKeypoint.new(cut, dark), ColorSequenceKeypoint.new(1, dark),
			})
		end
		update()
		if fresh then object:GetPropertyChangedSignal("AbsoluteSize"):Connect(update) end
		return gradient
	end)
end

-- Soft highlight bar across the top of a coloured fill.
function Kit:gloss(object, radius, transparency)
	return try(function()
		local gloss = object:FindFirstChild("MotifGloss") or create("Frame", object, {
			Name = "MotifGloss", BackgroundColor3 = self.P.white, BackgroundTransparency = transparency or 0.8, BorderSizePixel = 0,
			Position = UDim2.new(0, 5, 0, 4), Size = UDim2.new(1, -10, 0.36, 0), Active = false, ZIndex = object.ZIndex,
		})
		if not gloss:FindFirstChildOfClass("UICorner") then create("UICorner", gloss, {CornerRadius = UDim.new(0, radius or 10)}) end
		return gloss
	end)
end

-- Alternating bands through one UIGradient (max 20 keypoints = 10 bands). Rotation 45 = diagonal.
function Kit:stripes(frame, a, b, bands, rotation)
	return try(function()
		local count = math.clamp(bands or 8, 2, 10)
		local points = {}
		for index = 0, count - 1 do
			local color = index % 2 == 0 and a or b
			table.insert(points, ColorSequenceKeypoint.new(index == 0 and 0 or index / count + 0.001, color))
			table.insert(points, ColorSequenceKeypoint.new(index == count - 1 and 1 or (index + 1) / count, color))
		end
		frame.BackgroundColor3 = self.P.white
		local gradient = frame:FindFirstChild("MotifStripes") or create("UIGradient", frame, {Name = "MotifStripes"})
		gradient.Color, gradient.Rotation = ColorSequence.new(points), rotation or 45
		return gradient
	end)
end

-- Deterministic sprinkle of round dots (scale-based, follows any size). Good for confetti, bubbles,
-- stars, snow: change colour, size and transparency to suit the motif.
function Kit:dots(parent, options)
	options = options or {}
	return try(function()
		local holder = create("Frame", parent, {
			Name = options.name or "MotifDots", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
			ZIndex = options.zIndex or parent.ZIndex, Active = false, ClipsDescendants = options.clip == true,
		})
		local columns, rows = options.columns or 10, options.rows or 4
		for row = 0, rows - 1 do
			for column = 0, columns - 1 do
				local size = options.size or 10
				local dot = create("Frame", holder, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale((column + (row % 2) * 0.5 + 0.25) / columns, (row + 0.5) / rows),
					Size = UDim2.fromOffset(size, size), BackgroundColor3 = options.color or self.P.white,
					BackgroundTransparency = options.transparency or 0.75, BorderSizePixel = 0, ZIndex = holder.ZIndex,
				})
				create("UICorner", dot, {CornerRadius = UDim.new(1, 0)})
			end
		end
		return holder
	end)
end

-- Paper panel with a thick ink border.
function Kit:panel(frame, options)
	options = options or {}
	return try(function()
		frame.BackgroundColor3 = options.color or self.P.paper
		frame.BorderSizePixel = 0
		local corner = frame:FindFirstChildOfClass("UICorner") or create("UICorner", frame)
		corner.CornerRadius = UDim.new(0, options.corner or self.shape.panelCorner or 20)
		local stroke = frame:FindFirstChild("MotifEdge") or create("UIStroke", frame, {Name = "MotifEdge"})
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color, stroke.Thickness, stroke.Transparency = options.edge or self.P.outline, options.thickness or self.shape.stroke or 3, 0
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		return frame
	end)
end

-- Round emoji badge. Emoji glyphs measure ~1.5x their TextSize: the icon uses 0.56 of the box.
function Kit:badge(parent, name, emoji, color, size, props)
	return try(function()
		local badge = create("Frame", parent, {Name = name, Size = UDim2.fromOffset(size, size), BackgroundColor3 = color or self.P.primary, BorderSizePixel = 0})
		create("UICorner", badge, {CornerRadius = UDim.new(1, 0)})
		create("UIStroke", badge, {Color = self.P.outline, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
		local icon = create("TextLabel", badge, {
			Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = emoji or "",
			TextSize = math.floor(size * 0.56), TextColor3 = self.P.white,
		})
		for key, value in pairs(props or {}) do badge[key] = value end
		icon.ZIndex = badge.ZIndex
		return badge
	end)
end

-- Left-edge emoji on a wide button (hidden when the button is too narrow to share its row).
-- 22 pt emoji measure ~30x33 px: keep the box at 36 px or TextFits fails.
function Kit:icon(button, emoji, minWidth)
	return try(function()
		local icon = button:FindFirstChild("MotifIcon") or create("TextLabel", button, {
			Name = "MotifIcon", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 12, 0.5, -2), Size = UDim2.fromOffset(36, 36), TextSize = 22,
			TextColor3 = self.P.white, ZIndex = button.ZIndex, Active = false,
		})
		icon.Text = emoji
		local function fit() icon.Visible = button.AbsoluteSize.X >= (minWidth or 220) end
		fit()
		button:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		return icon
	end)
end

-- Buttons ----------------------------------------------------------------------------------------
-- role: "primary" | "danger" | "success" | a candy name | "plain" (pastel by options.order)
function Kit:faceFor(role, order)
	local P = self.P
	if role == "primary" then return P.primary end
	if role == "danger" then return P.danger end
	if role == "success" then return P.success end
	if self.candies[role] then return self.candies[role] end
	return self.pastels[((order or 0) % #self.pastels) + 1]
end

-- Colours for a styled button from its designed face and state {enabled, selected, pressed}.
function Kit:paint(button, state)
	local face = self.faces[button]
	if not face then return end
	state = state or {}
	pcall(function()
		local P = self.P
		local enabled = state.enabled ~= false
		local outline = button:FindFirstChild("MotifTextOutline")
		local gloss = button:FindFirstChild("MotifGloss")
		local icon = button:FindFirstChild("MotifIcon")
		if icon then icon.TextTransparency = enabled and 0 or 0.55 end
		if not enabled then
			button.BackgroundColor3, button.TextColor3 = P.disabled, P.muted
			if outline then outline.Transparency = 1 end
			if gloss then gloss.Visible = false end
		else
			local fill = state.selected and Kit.luminance(face) > 0.82 and (P.quiet or face) or face
			button.BackgroundColor3 = fill
			local color, thickness = self:textOn(fill, button.TextSize)
			button.TextColor3 = color
			if thickness then
				outline = outline or self:outline(button, thickness)
				if outline then outline.Thickness, outline.Transparency = thickness, 0 end
			elseif outline then
				outline.Transparency = 1
			end
			if gloss then gloss.Visible = Kit.luminance(fill) <= 0.82 end
		end
		local lip = button:FindFirstChild("MotifLip")
		if lip then lip.Offset = Vector2.new(0, enabled and state.pressed and 0.05 or 0) end
	end)
end

-- Style a TextButton: face by role, rounded corners, ink border, lip, gloss, font, optional emoji.
-- Keeps the button's Name, Size, Position and callbacks: only presentation changes.
function Kit:styleButton(button, options)
	options = options or {}
	local P = self.P
	self.faces[button] = options.face or self:faceFor(options.role or "plain", options.order)
	pcall(function()
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		local corner = button:FindFirstChildOfClass("UICorner") or create("UICorner", button)
		corner.CornerRadius = options.pill and UDim.new(1, 0) or UDim.new(0, options.corner or self.shape.corner or 16)
		local edge = button:FindFirstChild("MotifEdge") or create("UIStroke", button, {Name = "MotifEdge"})
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Color, edge.Thickness, edge.Transparency = P.outline, options.edge or self.shape.stroke or 3, 0
	end)
	self:setFont(button, options.font or "button")
	if Kit.luminance(self.faces[button]) <= 0.82 then self:gloss(button, 12) end
	self:lip(button, (button.AbsoluteSize.Y >= 64 or (options.height or 0) >= 64) and 8 or 6)
	if options.emoji then self:icon(button, options.emoji) end
	local state = {enabled = button.Active ~= false, selected = options.selected == true, pressed = false}
	self:paint(button, state)
	if options.interactive ~= false then
		pcall(function()
			local scale = button:FindFirstChild("MotifScale") or create("UIScale", button, {Name = "MotifScale"})
			local function refresh() self:paint(button, state) end
			button.MouseEnter:Connect(function() if state.enabled then self:tween(scale, {Scale = 1.04}, 0.14) end end)
			button.MouseLeave:Connect(function() state.pressed = false; self:tween(scale, {Scale = 1}, 0.14); refresh() end)
			button.InputBegan:Connect(function(input)
				if state.enabled and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
					state.pressed = true; self:tween(scale, {Scale = 0.94}, 0.08, Enum.EasingStyle.Quad); refresh()
				end
			end)
			button.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					state.pressed = false; self:tween(scale, {Scale = 1}, 0.18); refresh()
				end
			end)
			button:GetPropertyChangedSignal("Active"):Connect(function() state.enabled = button.Active; refresh() end)
		end)
	end
	return state
end

-- Mascot -----------------------------------------------------------------------------------------
-- A character drawn from rounded frames (no image assets). parts = list of
-- {name, x, y, w, h, colour-or-palette-key, rotation?, corner? (0..1, default round), stroke?, parent?}
-- in unit coordinates of the root. blink = names of eye parts squashed now and then.
function Kit:mascot(parent, size, parts, options)
	options = options or {}
	local ok, root, made = pcall(function()
		local root = create("Frame", parent, {
			Name = options.name or "MotifMascot", BackgroundTransparency = 1, Active = false,
			Size = UDim2.fromOffset(size, math.floor(size * (options.aspect or 1.12))), AnchorPoint = Vector2.new(0.5, 1),
		})
		for key, value in pairs(options.props or {}) do root[key] = value end
		local made = {}
		for _, part in ipairs(parts) do
			local host = part.parent and made[part.parent] or root
			local color = type(part[6]) == "string" and (self.P[part[6]] or self.candies[part[6]] or Kit.color(part[6])) or Kit.color(part[6])
			local frame = create("Frame", host, {
				Name = part[1], AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(part[2], part[3]),
				Size = UDim2.fromScale(part[4], part[5]), BackgroundColor3 = color, BorderSizePixel = 0,
				Rotation = part.rotation or 0, ZIndex = root.ZIndex, BackgroundTransparency = part.transparency or 0,
			})
			create("UICorner", frame, {CornerRadius = UDim.new(part.corner or 1, 0)})
			if part.stroke then
				create("UIStroke", frame, {Color = self.P.outline, Thickness = math.max(1.5, size / 26), ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
			end
			made[part[1]] = frame
		end
		if not options.still then
			self:loop(root, {Rotation = root.Rotation + (options.sway or 6)}, options.swaySeconds or 1.6)
			local eyes = {}
			for _, name in ipairs(options.blink or {}) do if made[name] then table.insert(eyes, made[name]) end end
			if #eyes > 0 and not self:reduceMotion() then
				task.spawn(function()
					while root.Parent do
						task.wait(2.6 + (os.clock() % 1.7))
						if not root.Parent then break end
						local sizes = {}
						for index, eye in ipairs(eyes) do sizes[index] = eye.Size; eye.Size = UDim2.fromScale(eye.Size.X.Scale, eye.Size.Y.Scale * 0.15) end
						task.wait(0.11)
						for index, eye in ipairs(eyes) do eye.Size = sizes[index] end
					end
				end)
			end
		end
		return root, made
	end)
	if not ok then return nil, nil end
	return root, made
end

-- Gamepad / keyboard focus ring in the motif's accent.
function Kit:selectionRing(playerGui, color)
	return try(function()
		local ring = create("Frame", nil, {Name = "MotifSelection", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1)})
		create("UICorner", ring, {CornerRadius = UDim.new(0, self.shape.corner or 16)})
		create("UIStroke", ring, {Color = color or self.P.primary, Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
		playerGui.SelectionImageObject = ring
		return ring
	end)
end

return Kit
