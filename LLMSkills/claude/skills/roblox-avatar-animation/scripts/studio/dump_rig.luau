-- Studio (execute_luau, datamodel_type = "Client" during Play): dump the local character's rig as JSON for offline tests.
-- Output format (what scripts/test_pose_kit.luau and the offline harness read):
--   { "<JointName>": { "c0": [12 numbers], "c1": [12], "s1": [x, y, z] (Part1 size), "p0": part0 name, "p1": part1 name },
--     "_hipHeight": Humanoid.HipHeight, "_rootSize": [x, y, z], "_rigType": "R15", "_constraints": true/false }
-- AnimationConstraint rigs (Server Authority) report Attachment0.CFrame / Attachment1.CFrame as c0 / c1.
-- Save the returned string to a .json file. Measure the avatar you actually ship (blocky default, scaled, Rthro),
-- not an idealised rig: joint offsets differ by avatar and every contact number depends on them.
-- Set TARGET to dump another model (an NPC) instead.
local TARGET = nil -- e.g. workspace.NPCs.NPC_01

local character = TARGET or game:GetService("Players").LocalPlayer.Character
if not character then return "no character (is Play running? is CharacterAutoLoads off?)" end
local humanoid = character:FindFirstChildOfClass("Humanoid")
local root = character:FindFirstChild("HumanoidRootPart")

local function num(x) return string.format("%.6g", x) end
local function cfArray(cf)
	local t = { cf:GetComponents() }
	for i, v in t do t[i] = num(v) end
	return "[" .. table.concat(t, ",") .. "]"
end
local function vecArray(v) return "[" .. num(v.X) .. "," .. num(v.Y) .. "," .. num(v.Z) .. "]" end

local rows, constraints = {}, false
local seen = {}
local joints = {}
for _, d in character:GetDescendants() do
	if d:IsA("AnimationConstraint") then joints[d.Name] = d; constraints = true
	elseif d:IsA("Motor6D") and not joints[d.Name] then joints[d.Name] = d end
end
for name, j in joints do
	local c0, c1, p0, p1
	if j:IsA("Motor6D") then
		c0, c1, p0, p1 = j.C0, j.C1, j.Part0, j.Part1
	else
		c0, c1 = j.Attachment0.CFrame, j.Attachment1.CFrame
		p0, p1 = j.Attachment0.Parent, j.Attachment1.Parent
	end
	if p1 and p1:IsA("BasePart") and not seen[name] then
		seen[name] = true
		table.insert(rows, string.format('"%s":{"c0":%s,"c1":%s,"s1":%s,"p0":"%s","p1":"%s"}',
			name, cfArray(c0), cfArray(c1), vecArray(p1.Size), p0 and p0.Name or "", p1.Name))
	end
end
table.sort(rows)
table.insert(rows, '"_hipHeight":' .. num(humanoid and humanoid.HipHeight or 0))
table.insert(rows, '"_rootSize":' .. (root and vecArray(root.Size) or "null"))
table.insert(rows, '"_rigType":"' .. (humanoid and humanoid.RigType.Name or "?") .. '"')
table.insert(rows, '"_constraints":' .. tostring(constraints))
return "{" .. table.concat(rows, ",") .. "}"
