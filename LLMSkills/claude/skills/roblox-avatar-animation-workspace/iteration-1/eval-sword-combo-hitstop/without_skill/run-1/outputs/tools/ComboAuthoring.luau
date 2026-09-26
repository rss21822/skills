-- ComboAuthoring: 3 連撃の「作画意図」（剣の握り位置と刃の向き）を HumanoidRootPart 空間で書いたもの。
-- tools/bake_combo.luau がこれを rig-r15.json の FK でオフライン IK し、関節角（度）へ焼き込んで
-- src/SwordCombo/ComboData.luau を生成する（実行時は焼き込んだ角度だけを使う = KeyframeSequence 化できる）。
--
-- 座標: +X = 右, +Y = 上, -Z = 前。HRP 中心が原点。地面 y = -3.2248（hipHeight 2.2248 + HRP 半高 1.0）
--        頭の中心 y≈1.33 / 肩 y≈0.34 / 腰（LowerTorso）y≈-0.79
-- grip   : 右手の握り点（RightHand 空間 (0,-0.15,0)）の目標位置
-- dir    : 刃の向き（= RightHand の -Z）
-- waist  : Waist.Transform {rx, ry, rz}（度）
-- root   : Root.Transform {rx, ry, rz, px, py, pz}（度 / stud）… 骨盤の沈み込み・前後移動・ひねり
-- left   : 左腕 FK {LeftShoulder=, LeftElbow=, LeftWrist=} または "HILT"（両手持ち: 柄頭側へ左手をオフライン IK で焼き込み）
-- lhIK   : 実行時の左手 IK 重み（省略時 HILT=1 / それ以外=0）。IK→FK の受け渡しキーでは 0 にする
-- ease   : このキーへ向かう区間のイージング（PoseMath.EASE）
-- phase  : 仕様書用のラベル

local READY = {
	waist = { 2, -8, 0 },
	root = { 0, 0, 0, 0, -0.10, 0 },
	grip = { 0.55, -0.50, -1.30 },
	dir = { 0.10, 0.55, -0.83 },
	left = { LeftShoulder = { 18, 0, 12 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 0, 0, 0 } },
}

local function ready(t: number, ease: string, phase: string)
	return {
		t = t, ease = ease, phase = phase, isReady = true,
		waist = READY.waist, root = READY.root, grip = READY.grip, dir = READY.dir, left = READY.left,
	}
end

return {
	ready = READY,
	gripOffset = { 0, -0.15, 0 }, -- RightHand / LeftHand 空間の握り点
	pommelBack = 0.50, -- 両手持ち時、左手は右手の握り点から刃と逆向きへ 0.55 stud
	bladeLength = 4.0, -- 握り点から切っ先まで
	strikes = {
		{
			name = "Kesa", -- 1 撃目: 右上からの袈裟斬り
			duration = 0.64,
			active = { 0.215, 0.33 },
			hitTime = 0.27,
			hitStop = 0.07,
			chainAt = 0.42,
			keys = {
				{ t = 0.00, from = true, phase = "開始（現在ポーズから）" },
				{ t = 0.15, ease = "inOutSine", phase = "予備動作: 右肩上へ振りかぶる",
					waist = { 6, -30, -6 }, root = { 0, -6, 0, 0, -0.12, 0.10 },
					grip = { 0.95, 1.50, 0.00 }, dir = { -0.35, 0.55, 0.76 },
					left = { LeftShoulder = { 70, 0, 22 }, LeftElbow = { 25, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
				{ t = 0.20, ease = "inOutSine", phase = "溜め（静止に近い保持）",
					waist = { 7, -34, -7 }, root = { 0, -7, 0, 0, -0.14, 0.12 },
					grip = { 1.00, 1.58, 0.08 }, dir = { -0.33, 0.52, 0.79 },
					left = { LeftShoulder = { 74, 0, 24 }, LeftElbow = { 22, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
				{ t = 0.24, ease = "inQuad", phase = "振り: 頭の右上を通過",
					waist = { 2, -16, -2 }, root = { 0, -3, 0, 0, -0.18, 0.02 },
					grip = { 0.85, 1.30, -0.85 }, dir = { 0.35, 0.80, -0.49 },
					left = { LeftShoulder = { 45, 0, 10 }, LeftElbow = { 35, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
				{ t = 0.27, ease = "linear", phase = "当たり（ヒット基準フレーム）",
					waist = { -4, 4, 4 }, root = { 0, 2, 0, 0, -0.24, -0.08 },
					grip = { 0.40, 0.35, -1.55 }, dir = { 0.15, 0.10, -0.98 },
					left = { LeftShoulder = { 12, 0, -8 }, LeftElbow = { 45, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
				{ t = 0.34, ease = "outQuad", phase = "フォロースルー: 左下へ振り抜く",
					waist = { -14, 30, 8 }, root = { 0, 6, 0, 0, -0.30, -0.14 },
					grip = { -0.50, -1.00, -1.00 }, dir = { -0.75, -0.35, -0.55 },
					left = { LeftShoulder = { -25, 0, -18 }, LeftElbow = { 35, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
				{ t = 0.42, ease = "outCubic", phase = "振り抜きの余韻（わずかに戻る）",
					waist = { -11, 26, 6 }, root = { 0, 5, 0, 0, -0.27, -0.12 },
					grip = { -0.40, -0.92, -1.05 }, dir = { -0.70, -0.30, -0.65 },
					left = { LeftShoulder = { -18, 0, -14 }, LeftElbow = { 38, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
				ready(0.64, "inOutSine", "戻り（構えへ）"),
			},
		},
		{
			name = "Yokonagi", -- 2 撃目: 横薙ぎ（左→右の逆袈裟ぎみの水平）
			duration = 0.66,
			active = { 0.20, 0.31 },
			hitTime = 0.25,
			hitStop = 0.08,
			chainAt = 0.44,
			keys = {
				{ t = 0.00, from = true, phase = "開始（現在ポーズから）" },
				{ t = 0.14, ease = "inOutSine", phase = "予備動作: 左へ巻き込む",
					waist = { 0, 38, 5 }, root = { 0, 8, 0, 0, -0.20, 0.04 },
					grip = { -0.75, -0.15, -0.65 }, dir = { -0.80, 0.05, 0.60 },
					left = { LeftShoulder = { -20, 0, -28 }, LeftElbow = { 50, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
				{ t = 0.19, ease = "inOutSine", phase = "溜め",
					waist = { 0, 42, 6 }, root = { 0, 9, 0, 0, -0.21, 0.06 },
					grip = { -0.80, -0.12, -0.55 }, dir = { -0.75, 0.05, 0.66 },
					left = { LeftShoulder = { -24, 0, -30 }, LeftElbow = { 52, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
				{ t = 0.22, ease = "inQuad", phase = "振り: 左前を通過",
					waist = { -2, 22, 3 }, root = { 0, 4, 0, 0, -0.23, 0.00 },
					grip = { -0.40, -0.18, -1.25 }, dir = { -0.70, -0.12, -0.71 },
					left = { LeftShoulder = { 5, 0, -10 }, LeftElbow = { 48, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
				{ t = 0.25, ease = "linear", phase = "当たり（ヒット基準フレーム）",
					waist = { -3, 0, 0 }, root = { 0, 0, 0, 0, -0.25, -0.08 },
					grip = { 0.30, -0.12, -1.45 }, dir = { 0.00, -0.10, -1.00 },
					left = { LeftShoulder = { 30, 0, 10 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
				{ t = 0.36, ease = "outQuad", phase = "フォロースルー: 右後ろへ振り抜く",
					waist = { -4, -40, -4 }, root = { 0, -8, 0, 0, -0.28, -0.10 },
					grip = { 1.25, 0.00, -0.45 }, dir = { 0.85, 0.05, 0.50 },
					left = { LeftShoulder = { 62, 0, 30 }, LeftElbow = { 22, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
				{ t = 0.44, ease = "outCubic", phase = "振り抜きの余韻",
					waist = { -3, -36, -3 }, root = { 0, -7, 0, 0, -0.26, -0.08 },
					grip = { 1.20, -0.05, -0.55 }, dir = { 0.80, 0.00, 0.58 },
					left = { LeftShoulder = { 55, 0, 26 }, LeftElbow = { 26, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
				ready(0.66, "inOutSine", "戻り（構えへ）"),
			},
		},
		{
			name = "Kabuto", -- 3 撃目: 両手で振りかぶって叩きつけ
			duration = 1.08,
			active = { 0.44, 0.53 },
			hitTime = 0.49,
			hitStop = 0.14,
			chainAt = nil, -- 最終段
			groundImpact = true, -- 刃先が地面に届いたらヒット扱い（叩きつけ）
			keys = {
				{ t = 0.00, from = true, phase = "開始（現在ポーズから）" },
				{ t = 0.16, ease = "inOutSine", phase = "予備動作 前半: 両手で柄を取り持ち上げ",
					waist = { 4, -4, 0 }, root = { 0, 0, 0, 0, -0.10, 0.04 },
					grip = { 0.25, 1.05, -0.90 }, dir = { 0.00, 0.95, -0.30 },
					left = "HILT" },
				{ t = 0.32, ease = "outCubic", phase = "予備動作 後半: 頭上へ振りかぶる（反る）",
					waist = { 14, -6, 0 }, root = { 0, 0, 0, 0, -0.03, 0.10 },
					grip = { 0.05, 1.85, 0.25 }, dir = { 0.00, 0.30, 0.95 },
					left = "HILT" },
				{ t = 0.40, ease = "inOutSine", phase = "溜め（頂点で保持）",
					waist = { 16, -6, 0 }, root = { 0, 0, 0, 0, -0.02, 0.12 },
					grip = { 0.05, 1.90, 0.32 }, dir = { 0.00, 0.20, 0.98 },
					left = "HILT" },
				{ t = 0.445, ease = "inQuad", phase = "振り下ろし: 頭の前上を通過",
					waist = { -6, -3, 0 }, root = { 0, 0, 0, 0, -0.20, -0.05 },
					grip = { 0.20, 1.35, -1.30 }, dir = { 0.00, 0.62, -0.78 },
					left = "HILT" },
				{ t = 0.49, ease = "linear", phase = "当たり: 地面へ叩きつけ（ヒット基準フレーム）",
					waist = { -28, 0, 0 }, root = { 0, 0, 0, 0, -0.55, -0.20 },
					grip = { 0.15, -0.55, -1.85 }, dir = { 0.00, -0.66, -0.75 },
					left = "HILT" },
				{ t = 0.56, ease = "outQuad", phase = "フォロースルー: 反動で少し跳ね上がる",
					waist = { -24, 0, 0 }, root = { 0, 0, 0, 0, -0.48, -0.18 },
					grip = { 0.15, -0.35, -1.85 }, dir = { 0.00, -0.55, -0.83 },
					left = "HILT" },
				{ t = 0.70, ease = "inOutSine", phase = "沈み込んで残心",
					waist = { -26, 0, 0 }, root = { 0, 0, 0, 0, -0.52, -0.18 },
					grip = { 0.15, -0.45, -1.80 }, dir = { 0.00, -0.60, -0.80 },
					left = "HILT" },
				{ t = 0.80, ease = "inOutSine", phase = "左手を柄から離す（ここから FK のみ）", lhIK = 0,
					waist = { -18, -2, 0 }, root = { 0, 0, 0, 0, -0.40, -0.12 },
					grip = { 0.20, -0.40, -1.65 }, dir = { 0.00, -0.35, -0.94 },
					left = "HILT" },
				ready(1.08, "inOutSine", "戻り（構えへ・片手に戻す）"),
			},
		},
	},
}
