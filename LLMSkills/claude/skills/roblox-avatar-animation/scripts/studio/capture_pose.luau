-- Studio (execute_luau, "Client" during Play): record joint Transforms every frame as a JSON fixture for offline tests.
-- Records what is drawn: the value after every writer (Animator + any pose layer), read in PostSimulation.
-- To capture a RAW animation track (e.g. a purchased Run whose legs your layer must follow), make sure no pose layer
-- rewrites those joints while recording (turn the layer off, or play the track on a cloned mannequin that has only
-- an Animator), then play the track and run this.
-- Output: { "fps": 60, "source": "...", "frames": [ { "t": seconds, "<Joint>": [rx, ry, rz, px, py, pz], ... } ] }
-- (rx, ry, rz = ToEulerAnglesXYZ radians; p = Transform position). Rebuild with CFrame.new(px,py,pz) * CFrame.Angles(rx,ry,rz).
local TARGET = nil -- default: local character
local FRAMES = 150 -- ~2.5 s at 60 fps; cover at least one full cycle of a looped track
local JOINTS = { "Root", "Waist", "Neck", "LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow", "RightWrist",
	"LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle" }
local SOURCE = "describe the track, speed and avatar here"

local RunService = game:GetService("RunService")
local character = TARGET or game:GetService("Players").LocalPlayer.Character
if not character then return "no character" end
local byName = {}
for _, d in character:GetDescendants() do
	if d:IsA("AnimationConstraint") then byName[d.Name] = d
	elseif d:IsA("Motor6D") and not byName[d.Name] then byName[d.Name] = d end
end

local function num(x) return string.format("%.5g", x) end
local frames, started = {}, os.clock()
local done = false
local conn
conn = RunService.PostSimulation:Connect(function()
	local parts = { '"t":' .. num(os.clock() - started) }
	for _, name in JOINTS do
		local j = byName[name]
		if j then
			local cf = j.Transform
			local rx, ry, rz = cf:ToEulerAnglesXYZ()
			table.insert(parts, string.format('"%s":[%s,%s,%s,%s,%s,%s]', name, num(rx), num(ry), num(rz), num(cf.X), num(cf.Y), num(cf.Z)))
		end
	end
	table.insert(frames, "{" .. table.concat(parts, ",") .. "}")
	if #frames >= FRAMES then conn:Disconnect(); done = true end
end)
while not done do task.wait() end
local elapsed = os.clock() - started
return string.format('{"fps":%s,"source":"%s","frames":[%s]}', num(#frames / elapsed), SOURCE, table.concat(frames, ","))
