# Roblox の書体

## 実在する書体（Studio 実測 2026-09）

`Font.new("rbxasset://fonts/families/<Family>.json", Enum.FontWeight.<Weight>)` で使える family 名。`Enum.Font` の各項目が指す family を `Font.fromEnum` で列挙し、さらに候補名を TextService で確かめた。**これ以外の名前（Lobster、Poppins、Inter、Noto Sans JP、Pacifico、Righteous、Orbitron、Bungee、Anton、Cinzel など Web フォント）は Roblox に無い**。存在しない family は黙って既定の書体で描かれるので、エラーにならず気付きにくい。

性格ごとに:

- **丸い・かわいい**: FredokaOne（見出し・ボタンの定番）、Nunito（本文）、ComicNeueAngular（= Enum.Font.Cartoon）
- **太い漫画の見出し（英字専用）**: LuckiestGuy、Bangers
- **手書き**: PermanentMarker（マーカー、英字専用）、IndieFlower、PatrickHand、Kalam、AmaticSC（細長い手書き、英字専用）
- **スポーティ・硬い見出し**: DenkOne、Oswald、RobotoCondensed、HighwayGothic（= Highway）
- **ファンタジー・古風**: Fondamento（カリグラフィ、英字専用）、GrenzeGotisch（ゴシック体、英字専用）、Merriweather（セリフ）、AccanthisADFStd（= Bodoni）、Guru（= Garamond）、RomanAntique（= Antique）、Balthazar（= Fantasy）
- **SF・テック**: Michroma（英字専用）、Sarpanch（英字専用）、Zekton（= SciFi）、Jura、TitilliumWeb
- **ドット**: PressStart2P（= Arcade、英字専用）
- **タイプライター**: SpecialElite（英字専用）
- **ホラー**: Creepster（英字専用）
- **読みやすい本文**: Nunito、BuilderSans（Roblox 標準 UI の書体）、Montserrat、GothamSSm（= Gotham）、Ubuntu、Roboto、Arimo、SourceSansPro、JosefinSans、Arial、LegacyArial
- **等幅**: Inconsolata（= Code）、RobotoMono

`scripts/skin_preview.py` の lint は同じ一覧で書体名を検査する。一覧を更新したらスクリプトの `ROBLOX_FAMILIES` も直す。

## 日本語（CJK）の扱い

- 内蔵 family のどれにも日本語グリフは無い。日本語の部分だけ Roblox がシステムの CJK 書体へフォールバックする。
- フォールバックは **要求した FontWeight で描かれる**。Regular を要求すると日本語が細く頼りなく見えるので、本文・ボタン・見出しは Bold（強調は Heavy / ExtraBold）を要求する。family がその太さを持っていなくても指定してよい（英字は最も近い太さで描かれ、日本語は太く描かれる）。
- 英字専用の飾り書体（上の「英字専用」）に日本語を流すと、飾りの英字の横に素っ気ない日本語が並んで壊れて見える。日本語を含む文字列は丸い見出し書体（title）に切り替える（`Kit:setFont` が `latinOnly` の役割で自動的に切り替える）。
- 絵文字はカラーで描かれる。TextSize の約 1.5 倍の高さを取るので箱を大きめに（22 pt → 36 px）。

## 絵文字は Unicode 12 まで

Roblox のカラー絵文字フォントは Unicode 12（2019）までしか持っていない。それより新しい絵文字は豆腐（□）になる（Studio 実測 2026-09）:

- 描けない例: 🪙 コイン、🪄 魔法の杖、🫧 泡、🪼 クラゲ、🪭 扇子、🧋 タピオカ、🪸 サンゴ（いずれも Unicode 13〜15）
- 描ける例: 🪁 凧（12）、🏮🍎🐟🎯🐡🐙🦑🤿🐚🎟️🛍️🧪🦉📜⚙️🎒⚔️🍜🐈💾⭐🎁🍬🍭🧸🤖🚀🎐🍡🎆🥤🐠💎🏆🔒🎵🔊🛒🏠↩️✅❌

代わりの例: コイン → 💰 / 🟡 か Frame で描いた丸、泡 → Frame のドット、クラゲ → 🎐 か Frame で描く、魔法の杖 → ✨。ZWJ で合成する絵文字（🐈‍⬛ など）も崩れることがあるので Studio で確かめる。`skin_preview.py` は spec の icons にある Unicode 13 以降の絵文字をエラーにする。コード中の文字列（ボタンの文言やラベル）も同じ注意が要る。

## 書体の実在確認（Studio、Edit でも可）

```lua
local TextService = game:GetService("TextService")
local function exists(family)
	local params = Instance.new("GetTextBoundsParams")
	params.Text, params.Size, params.Width = "Wg Play 123", 40, 10000
	params.Font = Font.new("rbxasset://fonts/families/" .. family .. ".json")
	return (pcall(function() return TextService:GetTextBoundsAsync(params) end))
end
print(exists("FredokaOne"), exists("Lobster")) --> true false
```

存在しない family では GetTextBoundsAsync がエラーになる。新しい書体が Roblox に追加されたらこれで確かめてから一覧に足す。
