--!strict
-- ComboPlayer: 3 連撃の状態機械とアニメ時計（ヒットストップ込み）。Roblox の API に依存しない純粋ロジック。
-- Roblox 側（SwordComboLayer）も Lune テストも同じこれを使う。
--
--  press()        : 攻撃入力。待機中なら 1 撃目開始、攻撃中なら次段を予約（先行入力）
--  step(dt)       : 時計を進める。ヒットストップ中は時計が止まり、余った dt だけ進む
--  registerHit()  : 当たり判定区間内の最初のヒットでヒットストップを開始（1 撃につき 1 回）
--  sample()       : 現在の関節 CFrame（Transform）表・左手 IK 重み・レイヤー重みを返す

type Strike = any

local ComboPlayer = {}
ComboPlayer.__index = ComboPlayer

export type Options = {
	inputOpen: number?, -- 攻撃開始から何秒後以降の入力を次段予約として受け付けるか
	fadeOut: number?, -- 最終キー後、レイヤー重みを 1→0 に落とす秒数
	hitShake: boolean?, -- ヒットストップ中の微振動
	shakeDeg: number?,
	shakeHz: number?,
}

function ComboPlayer.new(data: any, PoseMath: any, opts: Options?)
	local o = opts or {}
	local self = setmetatable({
		data = data,
		PM = PoseMath,
		joints = data.JOINTS,
		inputOpen = o.inputOpen or 0.10,
		fadeOut = o.fadeOut or 0.20,
		hitShake = if o.hitShake == nil then true else o.hitShake,
		shakeDeg = o.shakeDeg or 1.2,
		shakeHz = o.shakeHz or 32,
		-- 状態
		index = 0, -- 0 = 待機（レイヤー無効 or フェードアウト中）
		t = 0, -- 現在の段のアニメ時刻（ヒットストップ中は進まない）
		queued = false,
		hitDone = false,
		hitStopLeft = 0,
		hitStopTotal = 0,
		hitStopClock = 0,
		fade = 0, -- 1 = 完全にこのレイヤー
		fading = false,
		startPose = nil :: { [string]: CFrame }?,
		lastPose = nil :: { [string]: CFrame }?,
		lastLh = 0,
		events = {} :: { any },
	}, ComboPlayer)
	return self
end

function ComboPlayer:strike(): Strike?
	if self.index == 0 then
		return nil
	end
	return self.data.STRIKES[self.index]
end

function ComboPlayer:isBusy(): boolean
	return self.index ~= 0
end

function ComboPlayer:isHitStopped(): boolean
	return self.hitStopLeft > 0
end

-- 当たり判定区間中か（ヒットストップ中は判定しない）
function ComboPlayer:isActive(): boolean
	local s = self:strike()
	if not s or self.hitDone or self.hitStopLeft > 0 then
		return false
	end
	return self.t >= s.active[1] and self.t <= s.active[2]
end

function ComboPlayer:_begin(i: number, startPose: { [string]: CFrame }?)
	self.index = i
	self.t = 0
	self.queued = false
	self.hitDone = false
	self.hitStopLeft = 0
	self.fading = false
	self.fade = 1
	-- 連続性: 1 本目のキー（FROM_CURRENT）は「今画面に見えている姿勢」から始める
	self.startPose = startPose
	table.insert(self.events, { kind = "start", index = i })
end

-- visiblePose: 今画面に出ている各関節の Transform（待機中なら Animate の姿勢、フェード中なら合成後の姿勢）。
-- これを 1 本目のキーにするので、どこから押しても関節が跳ばない。
function ComboPlayer:press(visiblePose: { [string]: CFrame }?): boolean
	if self.index == 0 then
		self:_begin(1, visiblePose)
		return true
	end
	local s = self:strike()
	if s and s.chainAt and self.t >= self.inputOpen then
		self.queued = true
		return true
	end
	return false
end

function ComboPlayer:registerHit(info: any?): boolean
	local s = self:strike()
	if not s or not self:isActive() then
		return false
	end
	self.hitDone = true
	self.hitStopLeft = s.hitStop
	self.hitStopTotal = s.hitStop
	self.hitStopClock = 0
	table.insert(self.events, { kind = "hit", index = self.index, t = self.t, hitStop = s.hitStop, info = info })
	return true
end

function ComboPlayer:step(dt: number)
	if self.index == 0 then
		if self.fading then
			self.fade = math.max(0, self.fade - dt / self.fadeOut)
			if self.fade <= 0 then
				self.fading = false
				self.lastPose = nil
				table.insert(self.events, { kind = "end" })
			end
		end
		return
	end
	-- ヒットストップ: 時計を止める。余りは通常進行へ回す
	if self.hitStopLeft > 0 then
		local use = math.min(dt, self.hitStopLeft)
		self.hitStopLeft -= use
		self.hitStopClock += use
		dt -= use
		if self.hitStopLeft <= 1e-9 then
			self.hitStopLeft = 0
			table.insert(self.events, { kind = "hitstopEnd", index = self.index, t = self.t })
		end
		if dt <= 0 then
			return
		end
	end
	local s = self:strike()
	self.t += dt
	if self.queued and s.chainAt and self.t >= s.chainAt then
		-- 次段へ。現在の姿勢を開始姿勢に（sample 済みの lastPose）
		self:_sampleInto() -- 次段開始直前の姿勢を確定
		local nextIndex = self.index + 1
		self.index = nextIndex
		self.t = 0
		self.queued = false
		self.hitDone = false
		self.startPose = self.lastPose
		table.insert(self.events, { kind = "start", index = nextIndex })
		return
	end
	if self.t >= s.duration then
		self.t = s.duration
		self:_sampleInto()
		self.index = 0
		self.queued = false
		self.fading = true
		self.fade = 1
		table.insert(self.events, { kind = "recover" })
	end
end

function ComboPlayer:_sampleInto()
	local s = self:strike()
	if not s then
		return
	end
	local pose, lh = self.PM.sample(s.keys, self.t, self.joints, self.startPose)
	self.lastPose = pose
	self.lastLh = lh
end

-- 戻り値: pose(joint→CFrame), leftHandIK(0..1), layerWeight(0..1), shakeAngle(度, 表示用の微振動)
function ComboPlayer:sample(): ({ [string]: CFrame }?, number, number, number)
	if self.index == 0 then
		if self.fading and self.lastPose then
			return self.lastPose, self.lastLh, self.fade, 0
		end
		return nil, 0, 0, 0
	end
	self:_sampleInto()
	local shake = 0
	if self.hitStopLeft > 0 and self.hitShake then
		local k = self.hitStopLeft / math.max(self.hitStopTotal, 1e-6) -- 1→0 で減衰
		shake = self.shakeDeg * k * math.sin(self.hitStopClock * self.shakeHz * 2 * math.pi)
	end
	return self.lastPose, self.lastLh, 1, shake
end

function ComboPlayer:popEvents(): { any }
	local e = self.events
	self.events = {}
	return e
end

return ComboPlayer
