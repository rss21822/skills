-- UI theme shared by every screen: NIGHT WARD (escape from an abandoned hospital at night).
-- Colours and faces come from Motif/MotifSpec, which scripts/skin_preview.py generates from
-- design/night-ward.skin.json (edit the JSON, not the generated module). The helper API
-- (colors, create, corner, stroke, panel, label, button) is unchanged, so every screen that uses
-- it picks up the new look without edits. If the motif modules fail to load, the literals below
-- keep the same palette and nothing else changes.
local Theme = {}

local motif = script.Parent:WaitForChild("Motif", 5)
local okSpec, Spec = pcall(function() return require(motif:WaitForChild("MotifSpec", 5)) end)
if not okSpec or type(Spec) ~= "table" then Spec = nil end
local okKit, Kit = pcall(function() return require(motif:WaitForChild("MotifSkinKit", 5)) end)
if okKit and Spec and type(Kit) == "table" then
	local okNew, kit = pcall(Kit.new, Spec)
	Theme.kit = okNew and kit or nil
end

local P = Spec and Spec.palette or {}
local function pick(key, r, g, b) return P[key] or Color3.fromRGB(r, g, b) end

-- Existing keys keep their meaning: `panel` is a dark surface that takes light `text`.
Theme.colors = {
	background = pick("night", 11, 21, 18),   -- the corridor in the dark (green-black, not navy)
	panel = pick("wall", 23, 36, 31),         -- dark enamel signboard
	panelLight = pick("plate", 197, 204, 184), -- pale enamel door plate: default button face
	accent = pick("primary", 8, 122, 63),     -- 非常口 safety green: the call to action only
	text = pick("white", 241, 238, 224),      -- fluorescent-lit bone white (on dark surfaces)
	subtext = pick("subtext", 159, 178, 166), -- faded green-grey (on dark surfaces)
	danger = pick("danger", 178, 58, 38),     -- fire-alarm lamp red
	success = pick("success", 60, 116, 48),   -- moss
	-- Motif surfaces (additive keys).
	ink = pick("ink", 43, 42, 34),            -- typewriter ink on paper
	paper = pick("paper", 227, 217, 184),     -- yellowed chart paper
	paperLight = pick("panel", 239, 231, 203),
	paperPressed = pick("quiet", 214, 204, 168),
	muted = pick("muted", 94, 90, 72),        -- pencil grey (on paper)
	disabled = pick("disabled", 185, 178, 154),
	dim = pick("dim", 6, 16, 13),
	edge = pick("edge", 74, 97, 83),          -- worn paint edge of dark plates
	board = pick("board", 107, 86, 62),       -- clipboard masonite
	steel = pick("steel", 169, 178, 173),
	glow = pick("glow", 57, 226, 125),        -- lit exit sign / indicator lamp
	fluoro = pick("fluoro", 143, 214, 168),   -- fluorescent tube spill
	flashlight = pick("flashlight", 242, 227, 166),
	amber = pick("amber", 242, 192, 76),      -- reception LED digits (coins)
	stamp = pick("stamp", 154, 63, 30),       -- red rubber-stamp ink
	lampOff = pick("lampOff", 52, 64, 58),
}
local C = Theme.colors

-- Legacy Enum fonts stay for code that reads them; FontFace (set below) wins where supported.
-- Bold on purpose: Japanese falls back to the system face at the requested weight.
Theme.font = Enum.Font.ArimoBold
Theme.fontBold = Enum.Font.ArimoBold

local function create(className, props)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then object[key] = value end
	end
	object.Parent = props.Parent
	return object
end
Theme.create = create

-- Font role (display / title / button / body / strong / mono) through the motif kit. Latin-only
-- display faces switch to the title face for Japanese strings.
function Theme.setFont(object, role)
	if Theme.kit then pcall(Theme.kit.setFont, Theme.kit, object, role) end
	return object
end

-- Readable type for a fill: dark ink or bone white, whichever stands off the fill more.
function Theme.textOn(fill)
	if Theme.kit then
		local ok, color = pcall(Theme.kit.textOn, Theme.kit, fill, 18)
		if ok and color then return color end
	end
	local lum = 0.2126 * fill.R + 0.7152 * fill.G + 0.0722 * fill.B
	return lum > 0.5 and C.ink or C.text
end

function Theme.corner(object, radius)
	return create("UICorner", {CornerRadius = UDim.new(0, radius or 3), Parent = object})
end

-- An opaque painted edge (enamel plates, sign casings), never a faint hairline.
function Theme.stroke(object, color, thickness)
	return create("UIStroke", {Name = "MotifEdge", Color = color or C.edge, Thickness = thickness or 2, Transparency = 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = object})
end

function Theme.panel(parent, name, size, position)
	local frame = create("Frame", {Name = name, Size = size, Position = position or UDim2.new(),
		BackgroundColor3 = C.panel, BackgroundTransparency = 0, BorderSizePixel = 0, Parent = parent})
	Theme.corner(frame, 3)
	Theme.stroke(frame)
	return frame
end

-- options: bold, frameSize, align, color, role (font role), yAlign
function Theme.label(parent, name, text, size, options)
	options = options or {}
	local label = create("TextLabel", {Name = name, Text = text, TextSize = size or 16, Font = options.bold and Theme.fontBold or Theme.font,
		TextColor3 = options.color or C.text, BackgroundTransparency = 1, Size = options.frameSize or UDim2.new(1, 0, 0, (size or 16) + 8),
		TextXAlignment = options.align or Enum.TextXAlignment.Left, TextYAlignment = options.yAlign or Enum.TextYAlignment.Center,
		TextWrapped = true, Parent = parent})
	Theme.setFont(label, options.role or (options.bold and "strong" or "body"))
	return label
end

-- Face per button (weak keys) so a screen can re-colour a button (selected plate, stamped) and
-- hover / press still return to the right colour.
local faces = setmetatable({}, {__mode = "k"})

function Theme.setFace(button, face, textColor)
	local entry = faces[button]
	if entry then
		entry.face, entry.text = face, textColor or Theme.textOn(face)
		entry.paint()
	else
		button.BackgroundColor3, button.TextColor3 = face, textColor or Theme.textOn(face)
	end
end

-- options: primary, danger, size (UDim2), order, textSize, face, textColor, pressFace, pressText,
--          role (font role), corner, edge (colour), edgeThickness
-- Press darkens (or swaps to pressFace, e.g. a stamp inking in); nothing bounces or squashes.
function Theme.button(parent, name, text, onClick, options)
	options = options or {}
	local base = options.face or options.primary and C.accent or options.danger and C.danger or C.panelLight
	local button = create("TextButton", {Name = name, Text = text, TextSize = options.textSize or 18, Font = Theme.fontBold,
		TextColor3 = options.textColor or Theme.textOn(base), BackgroundColor3 = base, AutoButtonColor = false, BorderSizePixel = 0,
		Size = options.size or UDim2.new(1, 0, 0, 48), LayoutOrder = options.order or 0, Parent = parent})
	Theme.setFont(button, options.role or "button")
	Theme.corner(button, options.corner or 3)
	Theme.stroke(button, options.edge or C.ink, options.edgeThickness or 2)
	local entry = {face = base, text = options.textColor or Theme.textOn(base), hover = false, pressed = false}
	function entry.paint()
		local face, color = entry.face, entry.text
		if entry.pressed then
			face = options.pressFace or face:Lerp(C.dim, 0.28)
			color = options.pressText or (options.pressFace and Theme.textOn(options.pressFace)) or color
		elseif entry.hover then
			face = face:Lerp(C.flashlight, 0.18) -- a flashlight passing over it
		end
		button.BackgroundColor3, button.TextColor3 = face, color
	end
	faces[button] = entry
	local function isPress(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	button.MouseEnter:Connect(function() entry.hover = true; entry.paint() end)
	button.MouseLeave:Connect(function() entry.hover, entry.pressed = false, false; entry.paint() end)
	button.InputBegan:Connect(function(input) if isPress(input) then entry.pressed = true; entry.paint() end end)
	button.InputEnded:Connect(function(input) if isPress(input) then entry.pressed = false; entry.paint() end end)
	button.Activated:Connect(function() onClick(button) end)
	return button
end

return Theme
