--!strict
-- Studio Play 検証用 LocalScript（StarterPlayerScripts に一時的に置く。本番の SwordComboClient は Disabled にする）。
-- 前提: 自キャラの正面 4 stud に R15 ダミー（Avatar > Rig Builder > R15 / Block Rig）を置いておく。
-- 動作: 3 秒待って 1→2→3 撃目を自動入力（各段 t=0.25 s で次を先行入力）し、毎フレーム
--       RightHand の位置・段・ヒットを記録。終了後に Output へ実測値を出す。
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Layer = require(ReplicatedStorage:WaitForChild("SwordCombo"):WaitForChild("SwordComboLayer"))
local character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
local hand = character:WaitForChild("RightHand") :: BasePart
local rightShoulder = character:FindFirstChild("RightShoulder", true) :: Motor6D

local hits = {}
local starts = {}
local t0 = 0
local layer = Layer.new(character, {
	createSword = true,
	hitShake = false, -- 静止判定を厳密にするため振動なし
	onStrikeStart = function(i) table.insert(starts, { i = i, t = os.clock() - t0 }) end,
	onHit = function(i, inst, _, hs) table.insert(hits, { i = i, t = os.clock() - t0, inst = inst:GetFullName(), hs = hs }) end,
})

task.wait(3)
-- Animate の待機ポーズ（比較用）
local idleShoulder = rightShoulder.Transform
t0 = os.clock()
local log = {}
local conn = RunService.RenderStepped:Connect(function()
	table.insert(log, { t = os.clock() - t0, p = hand.Position, busy = layer:isBusy(), idx = layer.player.index, hs = layer.player:isHitStopped() })
end)
layer:press()
local pressed = { false, false }
while os.clock() - t0 < 4 do
	local p = layer.player
	if p.index >= 1 and p.index <= 2 and not pressed[p.index] and p.t >= 0.25 then
		pressed[p.index] = true
		layer:press()
	end
	RunService.PreSimulation:Wait()
end
conn:Disconnect()

print("==== SwordCombo Studio verify ====")
for _, s in starts do print(string.format("strike %d start @ %.3f s", s.i, s.t)) end
for _, h in hits do print(string.format("HIT strike %d @ %.3f s  %s  hitStop=%.3f", h.i, h.t, h.inst, h.hs)) end
-- ヒットストップ中の RightHand 移動量と実測の停止時間
local runStart, frozen = nil, {}
for k = 2, #log do
	local a, b = log[k - 1], log[k]
	if b.hs then
		runStart = runStart or a.t
		table.insert(frozen, (b.p - a.p).Magnitude)
	elseif runStart then
		print(string.format("hitstop run: %.3f s, max hand move per frame %.4f stud", b.t - runStart, math.max(0, table.unpack(frozen))))
		runStart, frozen = nil, {}
	end
end
-- フレームごとの最大移動（跳び検出の目安）
local maxStep, at = 0, 0
for k = 2, #log do
	local d = (log[k].p - log[k - 1].p).Magnitude
	if d > maxStep then maxStep, at = d, log[k].t end
end
print(string.format("max RightHand move per rendered frame: %.3f stud @ %.3f s", maxStep, at))
task.wait(0.5)
print(string.format("after fade-out: RightShoulder.Transform vs idle before combo = %.2f deg (Animate に戻っていれば数度以内)",
	math.deg(select(2, (idleShoulder:ToObjectSpace(rightShoulder.Transform)):ToAxisAngle()))))
