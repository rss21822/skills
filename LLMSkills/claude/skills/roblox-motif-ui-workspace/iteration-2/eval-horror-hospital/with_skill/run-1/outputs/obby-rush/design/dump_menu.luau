--!nocheck
-- Builds the real main menu in the Lune mock (design/harness.luau) and prints its instance tree as
-- JSON, for design/render_preview.py to lay out and draw outside Studio.
--   lune run design/dump_menu.luau <width> <height> [page: Shop|Inventory|Quests|Settings] [out.json]
-- Motion is rendered at rest (reduced motion), which is also the look between light dips.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")
local rb = require("@lune/roblox")

local width, height = tonumber(process.args[1]) or 1280, tonumber(process.args[2]) or 720
local pageId = process.args[3]
if pageId == "" or pageId == "none" then pageId = nil end
local out = process.args[4]

local Harness = luau.load(fs.readFile("design/harness.luau"), {debugName = "harness"})()
local h = Harness({viewport = rb.Vector2.new(width, height), reducedMotion = true})
local MainMenu = h.requireClient("MainMenu")
local gui = MainMenu.build(h.playerGui, h.handlers, h.state)
if pageId then
	local nav = gui:FindFirstChild("Nav_" .. pageId, true)
	nav.Activated:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1}, 1)
end

local PROPS = {"Visible", "Enabled", "Size", "Position", "AnchorPoint", "BackgroundColor3", "BackgroundTransparency", "Text",
	"TextSize", "TextColor3", "TextTransparency", "TextXAlignment", "TextYAlignment", "TextWrapped", "TextScaled", "FontFace", "Font",
	"ZIndex", "Rotation", "ClipsDescendants", "CornerRadius", "Color", "Thickness", "Transparency", "ApplyStrokeMode", "Offset",
	"FillDirection", "Padding", "HorizontalAlignment", "VerticalAlignment", "SortOrder", "LayoutOrder", "Wraps", "Scale", "MinSize",
	"MaxSize", "MaxTextSize", "MinTextSize", "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom", "ScrollBarThickness",
	"Active", "IgnoreGuiInset"}

local function encode(value)
	local kind = typeof(value)
	if kind == "number" or kind == "boolean" or kind == "string" then return value end
	if kind == "UDim2" then return {t = "UDim2", xs = value.X.Scale, xo = value.X.Offset, ys = value.Y.Scale, yo = value.Y.Offset} end
	if kind == "UDim" then return {t = "UDim", s = value.Scale, o = value.Offset} end
	if kind == "Vector2" then return {t = "Vector2", x = value.X, y = value.Y} end
	if kind == "Color3" then return {t = "Color3", r = value.R, g = value.G, b = value.B} end
	if kind == "EnumItem" then return {t = "Enum", name = value.Name} end
	if kind == "ColorSequence" then
		local keys = {}
		for _, k in ipairs(value.Keypoints) do table.insert(keys, {k.Time, k.Value.R, k.Value.G, k.Value.B}) end
		return {t = "CS", k = keys}
	end
	if kind == "NumberSequence" then
		local keys = {}
		for _, k in ipairs(value.Keypoints) do table.insert(keys, {k.Time, k.Value}) end
		return {t = "NS", k = keys}
	end
	if kind == "table" and type(value.Family) == "string" then
		return {t = "Font", family = value.Family, weight = value.Weight and value.Weight.Name or "Regular"}
	end
	return nil
end

local function dump(object)
	local entry = {name = object.Name, class = object.ClassName, props = {}, children = {}}
	for _, key in ipairs(PROPS) do
		local ok, value = pcall(function() return rawget(object, key) or object[key] end)
		if ok and value ~= nil then
			local encoded = encode(value)
			if encoded ~= nil then entry.props[key] = encoded end
		end
	end
	for _, child in ipairs(object:GetChildren()) do table.insert(entry.children, dump(child)) end
	return entry
end

local json = serde.encode("json", {viewport = {width, height}, page = pageId or "", warnings = h.warnings, tree = dump(gui)}, false)
if out then fs.writeFile(out, json) else print(json) end
