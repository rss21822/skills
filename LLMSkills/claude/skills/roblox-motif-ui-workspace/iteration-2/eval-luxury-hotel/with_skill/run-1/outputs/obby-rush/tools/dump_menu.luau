--!nocheck
-- Build the real main menu (src/ code, mock engine) and dump its GUI tree as JSON for
-- tools/render_preview.py. Run from the project folder:
--   lune run tools/dump_menu.luau <project-root> <width> <height> <scene> <out.json>
-- scene: lobby | hover | shop | settings | quests. Reduced motion is on so the dump is the settled state.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Harness = luau.load(fs.readFile("tools/harness.luau"), {debugName = "harness"})()
local root, width, height, scene, out = process.args[1] or ".", tonumber(process.args[2]) or 1280,
	tonumber(process.args[3]) or 720, process.args[4] or "lobby", process.args[5] or "menu.json"

local h = Harness.new({root = root, reducedMotion = true})
local gui = h.build()
h.resize(gui, width, height)
local function find(name) return gui:FindFirstChild(name, true) end
if scene == "hover" then
	find("PlayButton").MouseEnter:Fire()
elseif scene == "shop" then
	h.click(find("Nav_Shop"))
elseif scene == "settings" then
	h.click(find("Nav_Settings"))
	h.click(find("Toggle_SFX"))
elseif scene == "quests" then
	h.click(find("Nav_Quests"))
end

local SKIP = {Parent = true, AbsolutePosition = true, AbsoluteSize = true, TextFits = true}
local function value(v)
	local kind = typeof(v)
	if kind == "Color3" then return {"c3", v.R, v.G, v.B} end
	if kind == "UDim2" then return {"u2", v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset} end
	if kind == "UDim" then return {"u", v.Scale, v.Offset} end
	if kind == "Vector2" then return {"v2", v.X, v.Y} end
	if kind == "EnumItem" then return {"enum", v.Name} end
	if kind == "ColorSequence" then
		local points = {}
		for _, p in ipairs(v.Keypoints) do table.insert(points, {p.Time, p.Value.R, p.Value.G, p.Value.B}) end
		return {"cs", points}
	end
	if kind == "NumberSequence" then
		local points = {}
		for _, p in ipairs(v.Keypoints) do table.insert(points, {p.Time, p.Value}) end
		return {"ns", points}
	end
	if kind == "number" or kind == "string" or kind == "boolean" then return v end
	if kind == "table" and v.Family then
		return {"font", v.Family, v.Weight and v.Weight.Name or "Regular"}
	end
	return nil
end
local function dump(node)
	local props = {}
	for key, v in pairs(node.__props) do
		if not SKIP[key] then props[key] = value(v) end
	end
	local children = {}
	for _, child in ipairs(node:GetChildren()) do table.insert(children, dump(child)) end
	return {class = node.ClassName, name = node.Name, props = props, children = children}
end
fs.writeFile(out, serde.encode("json", {width = width, height = height, scene = scene, root = dump(gui)}, false))
print("dump: " .. out)
