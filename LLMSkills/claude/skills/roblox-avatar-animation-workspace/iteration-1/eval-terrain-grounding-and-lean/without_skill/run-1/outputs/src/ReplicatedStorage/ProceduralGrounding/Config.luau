--[[
	ProceduralGrounding/Config
	手続き接地 + 旋回リーンの調整値。単位は stud / rad / 秒。
	値を変えるときは tests/grounding.spec.luau を再実行して数値を確認すること。
]]

return {
	-- 対象の選別 -------------------------------------------------------------
	maxDistance = 120, -- カメラからこの距離より遠いキャラは処理しない (Animator の値そのまま)
	maxCharacters = 24, -- 近い順にこの人数まで処理 (1 人あたり毎フレーム レイ 6 本)
	autoDetectHumanoids = true, -- workspace 内の R15 Humanoid (NPC 含む) を自動で対象にする
	tagName = "ProceduralGrounding", -- autoDetect=false のとき NPC はこのタグで登録
	disableAttribute = "ProceduralGroundingDisabled", -- モデルに true を付けると除外
	debugAttributes = false, -- true でモデルに PG_Lean(度) / PG_Drop / PG_Weight 属性を毎フレーム書く (Studio 検証用)

	-- 足の接地 -----------------------------------------------------------------
	probeUp = 1.6, -- 基準地面 (HRP が想定する床) からこれだけ上からレイを撃つ
	probeDown = 2.2, -- 基準地面からこれだけ下まで探す
	maxFootUp = 1.4, -- 足を持ち上げる上限
	maxFootDown = 1.6, -- 足を下げる上限
	maxPelvisDrop = 1.2, -- 骨盤 (LowerTorso) を下げる上限
	dropReleaseRate = 8, -- 骨盤を元の高さへ戻す速さ (1/秒, 指数)。下げる方向は即時
	hrpRiseFollowSpeed = 12, -- HRP の上昇がこの速さ (stud/s) を超えた分は段差の跳ね上がりとみなし骨盤で相殺
	footGroundRate = 25, -- 足下の地面高さの追従速さ (1/秒, 指数)。段差で足がワープしない
	footGroundSnap = 3, -- これ以上の地面高さの変化はテレポートとみなし即時追従
	maxFootPitch = math.rad(35), -- 足首で地面に合わせる前後傾の上限
	maxFootRoll = math.rad(25), -- 足首で地面に合わせる左右傾の上限
	minGroundNormalY = 0.3, -- 法線の Y がこれ未満の面 (壁・急斜面) は足の傾き合わせに使わない
	plantClearanceLo = 0.08, -- アニメ上の足裏高さがこれ以下なら「接地中」= 傾き合わせ 100%
	plantClearanceHi = 0.45, -- これ以上なら「振り上げ中」= 傾き合わせ 0%
	weightRate = 12, -- 空中⇔接地の切り替えブレンド速さ (1/秒, 指数)

	-- 旋回リーン -------------------------------------------------------------
	leanGain = 1.0, -- 物理的な傾き atan(v*ω/g) に掛ける係数
	maxLean = math.rad(18), -- 体全体の傾き上限
	leanOmega = 9, -- 傾きのばね (臨界減衰) の角周波数。大きいほど機敏
	leanSpeedMin = 4, -- この水平速度以下では傾かない (その場旋回で傾かない)
	leanSpeedFull = 12, -- この速度で傾きが 100%
	maxYawRate = 10, -- ヨー角速度の上限 (rad/s)。ネット補間の跳ねを抑える
	waistLeanShare = 0.25, -- 上半身 (Waist) を追加で傾ける割合
	headStabilize = 0.6, -- 頭 (Neck) で打ち消す割合。1 で頭は常に水平
}
