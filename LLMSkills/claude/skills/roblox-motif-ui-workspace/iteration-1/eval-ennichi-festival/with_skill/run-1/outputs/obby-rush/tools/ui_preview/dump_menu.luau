--!nocheck
-- Dump the real MainMenu instance tree (built by the game's Luau under the Lune mock) to JSON so
-- tools/ui_preview/render_preview.py can draw it in a browser. This is a stand-in for Studio screenshots
-- when Studio is not available: layout is approximated by CSS, fonts by their Google Fonts twins.
--   lune run tools/ui_preview/dump_menu.luau <out-dir> [--plain]   (from the project folder)
-- --plain renders the menu without src/client/Ennichi (the original theme) for before/after shots.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Harness = luau.load(fs.readFile("tests/ennichi_harness.luau"), {debugName = "ennichi_harness"})()
local rb = Harness.rb
local outDir = process.args[1] or "preview-out"
local plain = process.args[2] == "--plain"
if not fs.isDir(outDir) then fs.writeDir(outDir) end

local TEXT = {TextLabel = true, TextButton = true, TextBox = true}
local GUI = {Frame = true, TextLabel = true, TextButton = true, TextBox = true, ScrollingFrame = true, ImageLabel = true,
	ImageButton = true, ViewportFrame = true, CanvasGroup = true}

local function udim2(v) return v and {v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset} or nil end
local function udim(v) return v and {v.Scale, v.Offset} or nil end
local function vec2(v) return v and {v.X, v.Y} or nil end
local function color(v) return v and {v.R, v.G, v.B} or nil end
local function enum(v) return v and v.Name or nil end
local function raw(object, key)
	local value = object[key]
	if typeof(value) == "table" and value.ClassName then return nil end -- a child named like the property
	return value
end

local function dump(object)
	local class = object.ClassName
	local p = {}
	if GUI[class] then
		p.Size, p.Position, p.AnchorPoint = udim2(raw(object, "Size")), udim2(raw(object, "Position")), vec2(raw(object, "AnchorPoint"))
		p.Rotation, p.Visible, p.ZIndex = raw(object, "Rotation"), raw(object, "Visible"), raw(object, "ZIndex")
		p.BackgroundColor3, p.BackgroundTransparency = color(raw(object, "BackgroundColor3")), raw(object, "BackgroundTransparency")
		p.ClipsDescendants, p.LayoutOrder = raw(object, "ClipsDescendants"), raw(object, "LayoutOrder")
		p.Active = raw(object, "Active")
	end
	if TEXT[class] then
		p.Text, p.TextSize, p.TextColor3 = raw(object, "Text"), raw(object, "TextSize"), color(raw(object, "TextColor3"))
		p.TextTransparency, p.TextWrapped, p.TextScaled = raw(object, "TextTransparency"), raw(object, "TextWrapped"), raw(object, "TextScaled")
		p.TextXAlignment, p.TextYAlignment = enum(raw(object, "TextXAlignment")), enum(raw(object, "TextYAlignment"))
		local face = raw(object, "FontFace")
		if type(face) == "table" then p.FontFace = {face.Family, face.Weight and face.Weight.Name} end
		p.Font = enum(raw(object, "Font"))
	end
	if class == "UICorner" then p.CornerRadius = udim(raw(object, "CornerRadius")) end
	if class == "UIStroke" then
		p.Color, p.Thickness, p.Transparency = color(raw(object, "Color")), raw(object, "Thickness"), raw(object, "Transparency")
		p.ApplyStrokeMode, p.Enabled = enum(raw(object, "ApplyStrokeMode")), raw(object, "Enabled")
	end
	if class == "UIGradient" then
		local c, t = raw(object, "Color"), raw(object, "Transparency")
		if c then
			p.Color = {}
			for _, k in ipairs(c.Keypoints) do table.insert(p.Color, {k.Time, k.Value.R, k.Value.G, k.Value.B}) end
		end
		if t then
			p.Transparency = {}
			for _, k in ipairs(t.Keypoints) do table.insert(p.Transparency, {k.Time, k.Value}) end
		end
		p.Rotation, p.Offset, p.Enabled = raw(object, "Rotation"), vec2(raw(object, "Offset")), raw(object, "Enabled")
	end
	if class == "UIListLayout" then
		p.FillDirection, p.Padding = enum(raw(object, "FillDirection")), udim(raw(object, "Padding"))
		p.HorizontalAlignment, p.VerticalAlignment = enum(raw(object, "HorizontalAlignment")), enum(raw(object, "VerticalAlignment"))
	end
	if class == "UIPadding" then
		p.PaddingLeft, p.PaddingRight = udim(raw(object, "PaddingLeft")), udim(raw(object, "PaddingRight"))
		p.PaddingTop, p.PaddingBottom = udim(raw(object, "PaddingTop")), udim(raw(object, "PaddingBottom"))
	end
	if class == "UIScale" then p.Scale = raw(object, "Scale") end
	if class == "UISizeConstraint" then p.MinSize, p.MaxSize = vec2(raw(object, "MinSize")), vec2(raw(object, "MaxSize")) end
	if class == "UITextSizeConstraint" then p.MinTextSize, p.MaxTextSize = raw(object, "MinTextSize"), raw(object, "MaxTextSize") end
	if class == "ScreenGui" then p.Enabled = raw(object, "Enabled") end
	local children = {}
	for _, child in ipairs(object:GetChildren()) do table.insert(children, dump(child)) end
	return {c = class, n = object.Name, p = p, k = children}
end

local function click(button)
	button.InputBegan:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
	button.InputEnded:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1})
	button.Activated:Fire({UserInputType = rb.Enum.UserInputType.MouseButton1}, 1)
end

local SCENARIOS = {
	{"main", 1280, 720}, {"shop", 1280, 720}, {"settings", 1280, 720, true}, {"inventory", 1280, 720}, {"quests", 1280, 720},
	{"main", 828, 369}, {"shop", 828, 369}, {"settings", 828, 369},
	{"main", 366, 820}, {"shop", 366, 820}, {"inventory", 366, 820},
}
if plain then SCENARIOS = {{"main", 1280, 720}, {"shop", 1280, 720}} end
local index = {}
for _, scenario in ipairs(SCENARIOS) do
	local screen, w, h, toggleOff = scenario[1], scenario[2], scenario[3], scenario[4]
	-- Reduced motion: loops are not started, so the dump shows the rest pose.
	local world = Harness.world({reducedMotion = true, deferNow = true, viewport = rb.Vector2.new(w, h),
		skip = plain and {"src/client/Ennichi"} or nil})
	local gui = world.module("MainMenu").build(world.playerGui, Harness.handlers({}), Harness.state)
	Harness.layout(gui, w, h)
	if screen ~= "main" then
		local nav = gui:FindFirstChild("Nav_" .. string.upper(string.sub(screen, 1, 1)) .. string.sub(screen, 2), true)
		click(nav)
	end
	if toggleOff then click(gui:FindFirstChild("Toggle_Music", true)) end
	Harness.layout(gui, w, h)
	local name = string.format("%s%s-%dx%d", plain and "before-" or "", screen, w, h)
	fs.writeFile(outDir .. "/" .. name .. ".json", serde.encode("json", {width = w, height = h, name = name, warnings = world.warnings, tree = dump(gui)}))
	table.insert(index, name)
	print("dumped " .. name .. (#world.warnings > 0 and ("  WARN " .. world.warnings[1]) or ""))
end
fs.writeFile(outDir .. "/index.json", serde.encode("json", index))
