-- Lune: outputs/ をカレントにして  lune run tools/spec_tables.luau > (SPEC.md の表部分)
-- ComboData（焼き込み済みの正本）から SPEC.md 用の Markdown 表を出す。表とコードの食い違いを防ぐため手書きしない。
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
getfenv(0).CFrame = roblox.CFrame
getfenv(0).Vector3 = roblox.Vector3
local Data = luau.load(fs.readFile("src/SwordCombo/ComboData.luau"), { chunkName = "ComboData", injectGlobals = true, environment = getfenv(0) })()

local function a3(k) return string.format("%.1f / %.1f / %.1f", k[1], k[2], k[3]) end
local function root(k) return string.format("%.1f / %.1f / %.1f ; %.2f / %.2f / %.2f", k[1], k[2], k[3], k[4] or 0, k[5] or 0, k[6] or 0) end
local UP = { "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist" }

local out = {}
local function w(s) table.insert(out, s) end
w("#### 構え（READY）: 連撃の戻り先・KFS 書き出し時の開始ポーズ")
w("")
w("| 関節 | rx / ry / rz (度) |")
w("|---|---|")
w("| Root | " .. root(Data.READY.Root) .. " (度 ; stud) |")
for _, j in UP do w("| " .. j .. " | " .. a3(Data.READY[j]) .. " |") end
w("")
for i, s in Data.STRIKES do
	w(string.format("#### %d 撃目 %s — 全長 %.2f s（%d f@60fps）/ 当たり判定 %.3f–%.3f s / 当たり基準 %.3f s / ヒットストップ %.3f s（%d f）/ 次段へ %s",
		i, s.name, s.duration, math.round(s.duration * 60), s.active[1], s.active[2], s.hitTime, s.hitStop, math.round(s.hitStop * 60),
		s.chainAt and string.format("%.2f s 以降", s.chainAt) or "なし（最終段）"))
	w("")
	w("| t (s) | f@60 | 区間 ease | 左手IK | 段階 |")
	w("|---|---|---|---|---|")
	for _, k in s.keys do
		w(string.format("| %.3f | %d | %s | %s | %s |", k.t, math.round(k.t * 60), k.ease or "—", k.lhIK and tostring(k.lhIK) or "—", k.phase))
	end
	w("")
	local head = "| 関節 / t (s) |"
	local sep = "|---|"
	for _, k in s.keys do
		head ..= string.format(" %.3f |", k.t)
		sep ..= "---|"
	end
	w(head)
	w(sep)
	local rowR = "| Root (rx/ry/rz ; px/py/pz) |"
	for _, k in s.keys do
		rowR ..= " " .. (k.pose == "FROM_CURRENT" and "現在" or root(k.pose.Root)) .. " |"
	end
	w(rowR)
	for _, j in UP do
		local row = "| " .. j .. " |"
		for _, k in s.keys do
			row ..= " " .. (k.pose == "FROM_CURRENT" and "現在" or a3(k.pose[j])) .. " |"
		end
		w(row)
	end
	w("")
end
print(table.concat(out, "\n"))
