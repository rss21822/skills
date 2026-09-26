--!nocheck
-- Ennichi (summer-festival fair) skin for the shared UITheme: runtime adapter.
--
-- Skin.apply(Theme) rewrites Theme.colors in place and wraps Theme.panel / label / button / stroke so
-- every screen built through the theme gets washi-paper panels, 3 px soot-brown edges, candy-coloured
-- buttons with a pressed-in lip and bold rounded type. It never renames, reparents or rewires anything:
-- the wrapped functions let the original ones build the instance (name, size, callbacks) and only
-- change how it looks afterwards. apply() is idempotent and restores the plain theme if it fails.
--
-- Colours, fonts and the goldfish come from EnnichiSpec (generated from design/ennichi-skin.json by
-- roblox-motif-ui/scripts/skin_preview.py). Edit the JSON and regenerate instead of editing the spec.
local Kit = require(script.Parent:WaitForChild("MotifSkinKit"))
local Spec = require(script.Parent:WaitForChild("EnnichiSpec"))

local kit = Kit.new(Spec)
local P = kit.P
local ICON = Spec.icons or {}

local Skin = {kit = kit, spec = Spec, P = P, icons = ICON}

-- Button Name -> face role. Nav tiles are stall fronts in the four fair colours; the pages use the same
-- colour as their tile so the player can tell where they are.
Skin.ROLES = {
	PlayButton = "primary", -- the glowing lantern: the only primary-coloured thing on screen
	Nav_Shop = "ringoame", -- candy-apple stall
	Nav_Inventory = "kingyo", -- goldfish-scooping stall (what you caught)
	Nav_Quests = "wakaba", -- shooting-gallery stall
	Nav_Settings = "ramune", -- ramune / wind-chime stall (sound settings)
	BuyButton = "kingyo",
	CloseButton = "paper",
}
Skin.PAGES = {
	Shop = {color = "ringoame", icon = ICON.shop},
	Inventory = {color = "kingyo", icon = ICON.inventory},
	Quests = {color = "wakaba", icon = ICON.quests},
	Settings = {color = "ramune", icon = ICON.settings},
}
Skin.BUTTON_ICONS = {Toggle_Music = ICON.music, Toggle_SFX = ICON.sfx}

function Skin.color(name)
	return P[name] or kit.candies[name]
end

-- Face colour for a themed button (nil = let the kit pick a pastel by order).
function Skin.faceFor(name, options)
	local role = Skin.ROLES[name]
	if role == "paper" then return P.panel end
	if role then return kit:faceFor(role) end
	options = options or {}
	if options.primary then return P.primary end
	if options.danger then return P.danger end
	return nil
end

-- Nearest ancestor that paints an opaque-ish fill (what a label actually sits on).
local function surfaceBehind(object)
	local node = object.Parent
	while node do
		local ok, fill = pcall(function()
			if node:IsA("GuiObject") and (node.BackgroundTransparency or 1) < 0.5 then return node.BackgroundColor3 end
			return nil
		end)
		if ok and fill then return fill end
		if not ok then return nil end
		node = node.Parent
	end
	return nil
end

-- Restyle one themed button. Keeps Name, Text, Size, Position, callbacks; returns the kit state table.
function Skin.styleButton(button, options)
	options = options or {}
	local face = Skin.faceFor(button.Name, options)
	local state = kit:styleButton(button, {
		face = face, order = options.order,
		emoji = Skin.BUTTON_ICONS[button.Name],
	})
	-- The plain theme's own MouseEnter / MouseLeave handlers write its old base colour back. Repaint
	-- after every handler of the same event has run so the skin face wins regardless of call order.
	local function repaint()
		task.defer(function() kit:paint(button, state) end)
	end
	pcall(function()
		button.MouseEnter:Connect(repaint)
		button.MouseLeave:Connect(repaint)
	end)
	Skin.states = Skin.states or setmetatable({}, {__mode = "k"})
	Skin.states[button] = state
	return state
end

function Skin.stateOf(button)
	return Skin.states and Skin.states[button]
end

-- Change a styled button's face (for example a settings row) and repaint it.
function Skin.setFace(button, face)
	kit.faces[button] = face
	kit:paint(button, Skin.stateOf(button) or {enabled = button.Active ~= false})
end

local function applyTo(Theme)
	local C = Theme.colors
	-- 1) Colours in place: modules that cached Theme.colors keep the same table and see the new values.
	C.background = P.quiet
	C.panel = P.paper
	C.panelLight = P.panel
	C.accent = P.primary
	C.text = P.ink
	C.subtext = P.muted
	C.danger = P.danger
	C.success = P.success

	-- 2) The plain edge is 1 px of translucent blue. The skin edge is 3 px of soot-brown ink, named so
	--    kit:panel / kit:styleButton reuse it instead of stacking a second border.
	Theme.stroke = function(object)
		local stroke = Instance.new("UIStroke")
		stroke.Name = "MotifEdge"
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color, stroke.Thickness, stroke.Transparency = P.outline, Spec.shape.stroke or 3, 0
		pcall(function() stroke.LineJoinMode = Enum.LineJoinMode.Round end)
		stroke.Parent = object
		return stroke
	end

	local panel, label, button = Skin.original.panel, Skin.original.label, Skin.original.button
	Theme.panel = function(parent, name, size, position)
		local frame = panel(parent, name, size, position)
		pcall(function()
			frame.BackgroundTransparency = 0
			kit:panel(frame, {color = P.paper})
		end)
		return frame
	end
	Theme.label = function(parent, name, text, size, options)
		local object = label(parent, name, text, size, options)
		pcall(function()
			kit:setFont(object, options and options.bold and "strong" or "body")
			if not (options and options.color) then
				local fill = surfaceBehind(object)
				if fill then
					local color, outline = kit:textOn(fill, object.TextSize)
					object.TextColor3 = color
					if outline then kit:outline(object, outline) end
				end
			end
		end)
		return object
	end
	Theme.button = function(parent, name, text, onClick, options)
		local object = button(parent, name, text, onClick, options)
		pcall(Skin.styleButton, object, options)
		return object
	end
	Theme.skin = Skin
end

-- Returns true when the theme wears the skin (now or already). Non-theme tables are left alone.
function Skin.apply(Theme)
	if type(Theme) ~= "table" or type(Theme.colors) ~= "table" or type(Theme.button) ~= "function"
		or type(Theme.panel) ~= "function" or type(Theme.label) ~= "function" then
		return false
	end
	if Theme.skin == Skin then return true end
	Skin.original = {
		colors = table.clone(Theme.colors), stroke = Theme.stroke,
		panel = Theme.panel, label = Theme.label, button = Theme.button,
	}
	local ok = pcall(applyTo, Theme)
	if not ok then
		Skin.revert(Theme)
		return false
	end
	return true
end

-- Put the plain theme back (used when apply fails half-way, and by tests).
function Skin.revert(Theme)
	local original = Skin.original
	if type(Theme) ~= "table" or not original then return end
	for key, value in pairs(original.colors) do Theme.colors[key] = value end
	Theme.stroke, Theme.panel, Theme.label, Theme.button = original.stroke, original.panel, original.label, original.button
	if Theme.skin == Skin then Theme.skin = nil end
end

return Skin
