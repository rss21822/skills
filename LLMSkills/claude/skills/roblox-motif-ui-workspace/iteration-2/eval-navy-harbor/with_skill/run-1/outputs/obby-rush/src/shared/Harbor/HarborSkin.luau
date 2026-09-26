--!nocheck
-- HarborSkin: the "night harbour navy" skin for UITheme (runtime adapter, UITheme.luau is untouched).
--
--   local Skin = require(Shared.Harbor.HarborSkin)
--   Skin.apply(Theme)        -- idempotent; repaints Theme.colors in place and wraps the builders
--
-- After apply, every screen built through Theme gets opaque navy serge panels with white collar
-- piping, canvas-white plain buttons, signal-red primary buttons and Oswald / Montserrat type.
-- Names, parents, sizes, callbacks and enabled logic stay exactly as UITheme made them: only colour,
-- font, corners and edges change. Every step is pcall-guarded, so a skin error leaves the stock look.
local Kit = require(script.Parent:WaitForChild("MotifSkinKit"))
local Spec = require(script.Parent:WaitForChild("HarborSpec"))
local Parts = require(script.Parent:WaitForChild("HarborParts"))

local Skin = {}
Skin.name = "NightHarbour"
Skin.spec = Spec
Skin.kit = Kit.new(Spec)
Skin.P = Skin.kit.P
Skin.parts = Parts.new(Skin.kit)

local kit, P = Skin.kit, Skin.P
local states = setmetatable({}, {__mode = "k"})

-- Button roles. Faces are cloth or canvas (no gloss, no lip, no squash): the naval tone presses by
-- darkening the cloth and shows hover with a brass edge.
--   primary  signal-flag red, canvas type      (PLAY, buy)
--   danger   darker red                        (cancel / leave)
--   plain    canvas white, navy type           (default for other screens, nav cards)
--   quiet    raised navy with white piping     (setting rows)
--   ghost    serge navy with white piping      (close)
local FACES = {primary = "primary", danger = "danger", plain = "canvas", quiet = "quiet", ghost = "paper"}

local function faceOf(state)
	return P[FACES[state.role] or "canvas"] or P.canvas
end

local function edgeOf(state, face)
	if state.enabled and state.hover then return P.brass, 2 end
	if state.selected then return P.primary, 3 end
	if state.role == "quiet" or state.role == "ghost" then return P.canvas, 2 end
	return face:Lerp(P.outline, 0.35), 2 -- hem: a darker shade of the same cloth
end

function Skin.paint(button)
	local state = states[button]
	if not state then return end
	state.busy = true
	pcall(function()
		local face = faceOf(state)
		if not state.enabled then
			face = P.disabled
		elseif state.pressed then
			face = face:Lerp(P.outline, 0.2)
		elseif state.hover then
			face = face:Lerp(P.white, 0.06)
		end
		button.BackgroundColor3 = face
		button.BackgroundTransparency = 0
		button.TextColor3 = state.enabled and (kit:textOn(face, button.TextSize)) or P.muted
		local edge = button:FindFirstChild("MotifEdge")
		if edge then
			local color, thickness = edgeOf(state, face)
			edge.Color, edge.Thickness, edge.Transparency = color, thickness, 0
		end
	end)
	state.busy = false
end

function Skin.state(button)
	return states[button]
end

-- Style a TextButton made by UITheme (or anyone). options: role, selected, corner, font.
function Skin.styleButton(button, options)
	options = options or {}
	local state = states[button]
	local fresh = state == nil
	if fresh then
		state = {role = "plain", enabled = button.Active ~= false, pressed = false, hover = false, selected = false, busy = false}
		states[button] = state
	end
	if options.role ~= nil then state.role = options.role end
	if options.selected ~= nil then state.selected = options.selected end
	pcall(function()
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		local corner = button:FindFirstChildOfClass("UICorner") or Parts.make("UICorner", button)
		corner.CornerRadius = UDim.new(0, options.corner or kit.shape.corner or 4)
		-- Re-use the theme's hairline UIStroke as the cloth hem (opaque, 2 px) instead of stacking a second one.
		local edge = button:FindFirstChild("MotifEdge") or button:FindFirstChildOfClass("UIStroke") or Parts.make("UIStroke", button)
		edge.Name = "MotifEdge"
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.LineJoinMode = Enum.LineJoinMode.Round
	end)
	kit:setFont(button, options.font or "button")
	if fresh then
		pcall(function()
			local function isPointer(input)
				return input and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch)
			end
			button.MouseEnter:Connect(function() state.hover = true; Skin.paint(button) end)
			button.MouseLeave:Connect(function() state.hover = false; state.pressed = false; Skin.paint(button) end)
			button.InputBegan:Connect(function(input)
				if state.enabled and isPointer(input) then state.pressed = true; Skin.paint(button) end
			end)
			button.InputEnded:Connect(function(input)
				if isPointer(input) then state.pressed = false; Skin.paint(button) end
			end)
			button:GetPropertyChangedSignal("Active"):Connect(function() state.enabled = button.Active ~= false; Skin.paint(button) end)
			-- UITheme's own hover handlers write BackgroundColor3; repaint after them so the skin wins.
			button:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
				if not state.busy then Skin.paint(button) end
			end)
		end)
	end
	Skin.paint(button)
	return state
end

-- Navy serge panel with opaque white piping (never the translucent 1 px dashboard edge).
function Skin.stylePanel(frame, options)
	options = options or {}
	frame.BackgroundColor3 = options.color or P.paper
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	local corner = frame:FindFirstChildOfClass("UICorner") or Parts.make("UICorner", frame)
	corner.CornerRadius = UDim.new(0, options.corner or kit.shape.panelCorner or 6)
	local edge = frame:FindFirstChild("MotifEdge") or frame:FindFirstChildOfClass("UIStroke") or Parts.make("UIStroke", frame)
	edge.Name = "MotifEdge"
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Color, edge.Thickness, edge.Transparency = options.edge or P.canvas, options.thickness or 2, 0
	return frame
end

-- Fonts by weight: bold labels of 22 pt and up speak in Oswald, other bold labels in Montserrat
-- ExtraBold, the rest Montserrat Bold (Japanese falls back at the requested weight, so never Regular).
function Skin.styleLabel(label, options)
	options = options or {}
	local role = options.role or (options.bold and ((label.TextSize or 16) >= 22 and "title" or "strong") or "body")
	kit:setFont(label, role)
	return label
end

function Skin.apply(Theme)
	if type(Theme) ~= "table" or type(Theme.button) ~= "function" or type(Theme.colors) ~= "table" then
		return false
	end
	if Theme.skin == Skin then return true end -- idempotent: never wrap twice
	local ok = pcall(function()
		-- 1) Colours, in place: modules holding a reference to Theme.colors see the new values.
		local C = Theme.colors
		C.background, C.panel, C.panelLight, C.accent = P.night, P.paper, P.canvas, P.primary
		C.text, C.subtext, C.danger, C.success = P.ink, P.muted, P.danger, P.success
		-- 2) Builders: the original makes the object (names, sizes, callbacks), the skin restyles it.
		local stroke, panel, label, button = Theme.stroke, Theme.panel, Theme.label, Theme.button
		Theme.stroke = function(object, ...)
			local made = stroke(object, ...)
			pcall(function() made.Color, made.Thickness, made.Transparency = P.canvas, 2, 0 end)
			return made
		end
		Theme.panel = function(...)
			local frame = panel(...)
			pcall(Skin.stylePanel, frame)
			return frame
		end
		Theme.label = function(parent, name, text, size, options, ...)
			local made = label(parent, name, text, size, options, ...)
			pcall(Skin.styleLabel, made, options)
			return made
		end
		Theme.button = function(parent, name, text, onClick, options, ...)
			local made = button(parent, name, text, onClick, options, ...)
			local role = options and (options.primary and "primary" or options.danger and "danger") or "plain"
			pcall(Skin.styleButton, made, {role = role})
			return made
		end
		Theme.skin = Skin
	end)
	return ok and Theme.skin == Skin
end

return Skin
