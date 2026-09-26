-- Studio-only authoring tool (run in the Command Bar in Edit mode, NOT shipped): bakes the three strikes of
-- ReplicatedStorage.SwordCombo.Spec into KeyframeSequences under ServerStorage.SwordComboBaked, ready for the later
-- upload (right-click > Save to Roblox, or the Animation Editor's Import). Requires an R15 rig in the workspace
-- named "SwordRig" (e.g. Avatar > Rig Builder > R15 Block, renamed) for the leg IK.
--
-- What differs from the pose layer: a track cannot freeze itself, so the hit-stop becomes a KeyframeMarker "Contact"
-- (the game calls track:AdjustSpeed(0) for hitStop seconds on a confirmed hit, then AdjustSpeed(1)); chaining uses the
-- "ChainOpen" / "Chain" markers; the Animate hand-off is the fadeTime of track:Play(Spec.ENTER_FADE). Play the uploaded
-- tracks at Priority Action (set below) so they win over Animate's Idle/Movement tracks on every joint.
-- Runtime registration (KeyframeSequenceProvider:RegisterKeyframeSequence) is for Studio preview only: the temporary id
-- does not play in live servers. Upload the sequences and use the asset ids in production.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local folder = ReplicatedStorage:WaitForChild("SwordCombo")
local Spec = require(folder.Spec)
local Player = require(folder.Player)
local Kit = require(folder.AvatarPoseKit)

local rig = workspace:FindFirstChild("SwordRig")
assert(rig, "put an R15 rig named SwordRig in the workspace")
local joints = Kit.collectJoints(rig)
local FPS = 60

local out = ServerStorage:FindFirstChild("SwordComboBaked") or Instance.new("Folder")
out.Name = "SwordComboBaked"
out.Parent = ServerStorage

-- joint -> the part it drives, and that part's parent part (Pose hierarchy mirrors the part tree)
local partOf, parentOf = {}, {}
for name, joint in joints do
	local d = Kit.jointData(joint)
	partOf[name] = d.part1.Name
	parentOf[d.part1.Name] = (joint:IsA("Motor6D") and joint.Part0 or joint.Attachment0.Parent).Name
end

for index, strike in Spec.STRIKES do
	local seq = Instance.new("KeyframeSequence")
	seq.Name = "SwordCombo_" .. index .. "_" .. strike.name
	seq.Loop = false
	seq.Priority = Enum.AnimationPriority.Action
	local s = Player.new(joints) -- stance feet from this rig; legs are solved like the layer does
	local rootC0 = Kit.jointData(joints.Root).c0
	for frame = 0, math.floor(strike.duration * FPS + 0.5) do
		local t = math.min(frame / FPS, strike.duration)
		local upper, dy = Spec.sample(index, t)
		local pose = table.clone(upper)
		pose.Root = CFrame.new(rootC0:VectorToObjectSpace(Vector3.new(0, dy * s.scale, 0))) * upper.Root
		for _, side in { "Left", "Right" } do
			local h, k, a = Player.solveLeg(joints, pose.Root, side, s.stance[side])
			pose[side .. "Hip"], pose[side .. "Knee"], pose[side .. "Ankle"] = h, k, a
		end
		local kf = Instance.new("Keyframe")
		kf.Time = t
		local poses = { HumanoidRootPart = Instance.new("Pose") }
		poses.HumanoidRootPart.Name = "HumanoidRootPart"
		poses.HumanoidRootPart.Weight = 0
		poses.HumanoidRootPart.Parent = kf
		local pending = {}
		for name, cf in pose do table.insert(pending, { part = partOf[name], cf = cf }) end
		while #pending > 0 do
			local rest = {}
			for _, item in pending do
				local parentPose = poses[parentOf[item.part]]
				if parentPose then
					local p = Instance.new("Pose")
					p.Name = item.part
					p.CFrame = item.cf
					p.EasingStyle = Enum.PoseEasingStyle.Linear -- sampled at 60 fps; the curve shape is in the samples
					p.Parent = parentPose
					poses[item.part] = p
				else
					table.insert(rest, item)
				end
			end
			assert(#rest < #pending, "pose tree: a part's parent is missing")
			pending = rest
		end
		kf.Parent = seq
	end
	for _, m in { { "Contact", strike.contact }, { "ChainOpen", strike.inputOpen }, { "Chain", strike.chainAt } } do
		if m[2] <= strike.duration then
			local kf = Instance.new("Keyframe")
			kf.Time = m[2]
			local marker = Instance.new("KeyframeMarker")
			marker.Name = m[1]
			marker.Value = tostring(strike.hitStop)
			marker.Parent = kf
			kf.Parent = seq
		end
	end
	local old = out:FindFirstChild(seq.Name)
	if old then old:Destroy() end
	seq.Parent = out
	print("baked", seq.Name, #seq:GetKeyframes(), "keyframes")
end
