--!strict
-- KeyframeSequenceExport: ComboData から KeyframeSequence を組み立てる（後でアップロードする用）。
-- Studio のコマンドバーで:
--   local E = require(game.ReplicatedStorage.SwordCombo.KeyframeSequenceExport)
--   E.buildAll(workspace.Rig)           -- R15 リグ（脚 IK の計算に使う）。ServerStorage に 3 本出力
-- 出力を右クリック →「Save to Roblox」または Animation Editor で読み込んでアップロードする。
--
-- 変換の約束
--   * Pose.CFrame = Motor6D.Transform（ComboData の値そのまま）。FROM_CURRENT のキーは構え（READY）で代用。
--   * 脚は実行時 IK なので、ここで各キーの脚 IK を解いて焼き込む（骨盤を沈めても足が床に残る）。
--   * 左手の両手持ちは焼き込み済みの FK をそのまま使う（キー間はわずかに柄から離れうる。REPORT 参照）。
--   * イージング: ComboData の ease は「そのキーへ入る区間」。KFS の Pose.EasingStyle は「そのキーから出る区間」
--     なので 1 つ前のキーの Pose に書く。Quad/Cubic/Quart/Sine は CubicV2 の In/Out/InOut に丸める。
--   * KeyframeMarker: "ActiveStart"/"ActiveEnd"（当たり判定区間）, "Hit"（Value=ヒットストップ秒）, "Chain"。
--   * ヒットストップは AnimationTrack では track:AdjustSpeed(0) → hitStop 秒後に AdjustSpeed(1)（hitStop() 参照）。

local PoseMath = require(script.Parent:WaitForChild("PoseMath"))
local ComboData = require(script.Parent:WaitForChild("ComboData"))

local Export = {}

-- パーツ階層（Pose の親子）: Pose 名 = Part1 名、Pose.CFrame = その Part1 を動かす Motor6D の Transform
local TREE = {
	{ part = "LowerTorso", joint = "Root", children = {
		{ part = "UpperTorso", joint = "Waist", children = {
			{ part = "Head", joint = "Neck" },
			{ part = "RightUpperArm", joint = "RightShoulder", children = {
				{ part = "RightLowerArm", joint = "RightElbow", children = { { part = "RightHand", joint = "RightWrist" } } },
			} },
			{ part = "LeftUpperArm", joint = "LeftShoulder", children = {
				{ part = "LeftLowerArm", joint = "LeftElbow", children = { { part = "LeftHand", joint = "LeftWrist" } } },
			} },
		} },
		{ part = "RightUpperLeg", joint = "RightHip", children = {
			{ part = "RightLowerLeg", joint = "RightKnee", children = { { part = "RightFoot", joint = "RightAnkle" } } },
		} },
		{ part = "LeftUpperLeg", joint = "LeftHip", children = {
			{ part = "LeftLowerLeg", joint = "LeftKnee", children = { { part = "LeftFoot", joint = "LeftAnkle" } } },
		} },
	} },
}

local EASE_MAP: { [string]: { Enum.PoseEasingStyle | Enum.PoseEasingDirection } } = {
	linear = { Enum.PoseEasingStyle.Linear, Enum.PoseEasingDirection.In },
	inQuad = { Enum.PoseEasingStyle.CubicV2, Enum.PoseEasingDirection.In },
	inCubic = { Enum.PoseEasingStyle.CubicV2, Enum.PoseEasingDirection.In },
	inQuart = { Enum.PoseEasingStyle.CubicV2, Enum.PoseEasingDirection.In },
	outQuad = { Enum.PoseEasingStyle.CubicV2, Enum.PoseEasingDirection.Out },
	outCubic = { Enum.PoseEasingStyle.CubicV2, Enum.PoseEasingDirection.Out },
	outQuart = { Enum.PoseEasingStyle.CubicV2, Enum.PoseEasingDirection.Out },
	inOutSine = { Enum.PoseEasingStyle.CubicV2, Enum.PoseEasingDirection.InOut },
	inOutCubic = { Enum.PoseEasingStyle.CubicV2, Enum.PoseEasingDirection.InOut },
}

local function rigFrom(character: Model): { [string]: any }
	local rig = {}
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") then
			rig[d.Name] = { C0 = d.C0, C1 = d.C1 }
		end
	end
	return rig
end

local function addPoses(parentPose: Instance, nodes: { any }, cframes: { [string]: CFrame }, ease: string?)
	for _, n in nodes do
		local p = Instance.new("Pose")
		p.Name = n.part
		p.CFrame = cframes[n.joint] or CFrame.identity
		p.Weight = 1
		local e = EASE_MAP[ease or "linear"] or EASE_MAP.linear
		p.EasingStyle = e[1] :: Enum.PoseEasingStyle
		p.EasingDirection = e[2] :: Enum.PoseEasingDirection
		p.Parent = parentPose
		if n.children then
			addPoses(p, n.children, cframes, ease)
		end
	end
end

function Export.build(strikeIndex: number, rigCharacter: Model): KeyframeSequence
	local s = ComboData.STRIKES[strikeIndex]
	assert(s, "strike index")
	local rig = rigFrom(rigCharacter)
	local targets = PoseMath.legRestTargets(rig)
	local kfs = Instance.new("KeyframeSequence")
	kfs.Name = string.format("SwordCombo%d_%s", strikeIndex, s.name)
	kfs.Loop = false
	kfs.Priority = Enum.AnimationPriority.Action
	for i, key in s.keys do
		local src = if key.pose == "FROM_CURRENT" then ComboData.READY else key.pose
		local cframes: { [string]: CFrame } = {}
		for _, j in ComboData.JOINTS do
			cframes[j] = PoseMath.keyToCFrame(src[j])
		end
		local legs = PoseMath.solveLegs(rig, cframes.Root, targets)
		for j, cf in legs do
			cframes[j] = cf
		end
		local nextKey = s.keys[i + 1]
		local kf = Instance.new("Keyframe")
		kf.Time = key.t
		kf.Name = key.phase or ""
		local root = Instance.new("Pose")
		root.Name = "HumanoidRootPart"
		root.Weight = 0
		root.Parent = kf
		addPoses(root, TREE, cframes, nextKey and nextKey.ease or "linear")
		kf.Parent = kfs
	end
	local function marker(name: string, t: number, value: string)
		local kf = Instance.new("Keyframe")
		kf.Time = t
		kf.Name = name
		local m = Instance.new("KeyframeMarker")
		m.Name = name
		m.Value = value
		m.Parent = kf
		kf.Parent = kfs
	end
	marker("ActiveStart", s.active[1], "")
	marker("ActiveEnd", s.active[2], "")
	marker("Hit", s.hitTime, tostring(s.hitStop))
	if s.chainAt then
		marker("Chain", s.chainAt, tostring(strikeIndex + 1))
	end
	return kfs
end

function Export.buildAll(rigCharacter: Model, parent: Instance?): { KeyframeSequence }
	local out = {}
	for i = 1, #ComboData.STRIKES do
		local kfs = Export.build(i, rigCharacter)
		kfs.Parent = parent or game:GetService("ServerStorage")
		table.insert(out, kfs)
	end
	return out
end

-- AnimationTrack 版のヒットストップ（アップロード後に使う）
function Export.hitStop(track: AnimationTrack, duration: number)
	local speed = track.Speed
	track:AdjustSpeed(0)
	task.delay(duration, function()
		if track.IsPlaying then
			track:AdjustSpeed(if speed == 0 then 1 else speed)
		end
	end)
end

return Export
