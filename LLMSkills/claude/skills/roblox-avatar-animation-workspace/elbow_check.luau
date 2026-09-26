local fs = require("@lune/fs")
local rbx = require("@lune/roblox")
local serde = require("@lune/serde")
local CFrame = rbx.CFrame
local d = serde.decode("json", fs.readFile("assets/rig-r15-sample.json"))
local function j(n) return CFrame.new(table.unpack(d[n].c0)), CFrame.new(table.unpack(d[n].c1)) end
local function hand(shoulderX, elbowX, kneeX)
	local s0, s1 = j("RightShoulder"); local e0, e1 = j("RightElbow"); local w0, w1 = j("RightWrist")
	local upper = s0 * CFrame.Angles(math.rad(shoulderX), 0, 0) * s1:Inverse()
	local lower = upper * e0 * CFrame.Angles(math.rad(elbowX), 0, 0) * e1:Inverse()
	local h = lower * w0 * w1:Inverse()
	return h.Position
end
for _, e in { -30, 0, 30 } do local p = hand(0, e); print(string.format("elbow %+d -> hand y=%.3f z=%.3f (z<0 = forward)", e, p.Y, p.Z)) end
local h0, h1 = CFrame.new(table.unpack(d.RightHip.c0)), CFrame.new(table.unpack(d.RightHip.c1))
local k0, k1 = CFrame.new(table.unpack(d.RightKnee.c0)), CFrame.new(table.unpack(d.RightKnee.c1))
local a0 = CFrame.new(table.unpack(d.RightAnkle.c0))
for _, k in { -30, 30 } do
	local ankle = h0 * h1:Inverse() * k0 * CFrame.Angles(math.rad(k), 0, 0) * k1:Inverse() * a0
	print(string.format("knee %+d -> ankle z=%.3f (z>0 = back = normal knee flex)", k, ankle.Position.Z))
end
