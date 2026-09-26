--[[
	LocalScript (StarterPlayerScripts)
	自分・他プレイヤー・NPC (workspace 内の R15 Humanoid) の足の接地と旋回リーンを有効にする。
	既定の Animate スクリプトはそのまま。アニメーションのアップロードは不要。
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProceduralGrounding = require(ReplicatedStorage:WaitForChild("ProceduralGrounding"))

local controller = ProceduralGrounding.new({
	-- 調整値は ReplicatedStorage.ProceduralGrounding.Config を参照。ここで上書きもできる:
	-- maxLean = math.rad(14),
	-- debugAttributes = true,
})
controller:start()
