# skin spec JSON

1 ファイルで見た目の決定をまとめる。`scripts/skin_preview.py` が lint・style board・Luau モジュール（`MotifSkinKit` の入力）を生成する。色は "#RRGGBB"。完全な例は `assets/skin-spec.example.json`。

```jsonc
{
  "name": "Pop Rink",                       // スキン名（board の見出し）
  "motif": "candy-coloured ice rink ...",   // 投稿されたモチーフの要約
  "concept": "sticker-book arcade ...",     // 6 軸を 1 行にした翻訳
  "palette": {
    "ink": "#30163A",       // 紙の上の文字と縁。明るい紙なら暗色
    "paper": "#FFFAF2",     // パネルの面
    "panel": "#FFFFFF",     // 一段明るい面（カード・バナー）
    "quiet": "#F5EDFF",     // 入力欄・選択中の明るいボタン
    "primary": "#FFD033",   // CTA 専用の主役色
    "danger": "#F04058", "success": "#26D696",
    "muted": "#7A648A",     // 補足文字（紙に対して 4.5:1 以上）
    "disabled": "#E4DCEA",  // 無効ボタンの面
    "dim": "#401E68",       // モーダルの暗幕
    "outline": "#30163A",   // 省略可。縁と文字の縁取り（既定 = ink）。暗い紙のときは暗色を指定
    "onLight": "#30163A",   // 省略可。明るい面の上の文字（既定 = 暗い方）
    "candies": [["bubblegum", "#FF5EA0"], ["mint", "#26D696"]]  // 順序付き。名前はモチーフの言葉で
    // 他のキー（例 "honey"）も自由に足せる。Luau 側で kit.P.honey として使える
  },
  "pastels": ["#FFF4C4"],     // 省略可。一覧の行ボタン。省略時はキャンディを紙へ 75% 寄せる
  "fonts": {                  // 役割 → [family, weight]。family は references/fonts.md の一覧から
    "display": ["LuckiestGuy", "Regular"],
    "title": ["FredokaOne", "Bold"],
    "button": ["FredokaOne", "Bold"],
    "body": ["Nunito", "Bold"],
    "strong": ["Nunito", "Heavy"]
  },
  "latinOnly": ["display"],   // 日本語を含む文字列では title に切り替える役割
  "shape": {"corner": 16, "panelCorner": 20, "stroke": 3, "lip": 6, "tilt": -2},
  "icons": {"play": "▶️", "shop": "🛍️"},   // 動作 → 絵文字。コード側で Name → 絵文字の表に使う
  "mascot": {                 // 省略可。Frame で描くマスコット
    "name": "Penguin", "aspect": 1.12, "blink": ["EyeL", "EyeR"],
    "parts": [
      // [名前, x, y, 幅, 高さ, 色], 位置と大きさは親の比率（0〜1）、中心基準
      // 色は "#hex" か palette / candies のキー。オプション:
      //   stroke(縁取り), rotation(度), corner(0〜1 の角丸, 既定 1 = 円), transparency, parent(親の部品名)
      ["Body", 0.5, 0.52, 0.84, 0.86, "#2C2442", {"stroke": true}],
      ["EyeL", 0.37, 0.36, 0.2, 0.2, "white"],
      ["PupilL", 0.58, 0.55, 0.55, 0.55, "ink", {"parent": "EyeL"}]
    ]
  }
}
```

部品は配列の順に重なる（後ろほど手前）。`parent` を指定した部品は親の部品の中の比率で置かれる（瞳を目の中に置くなど）。

生成した Luau（`--luau MotifSpec.luau`）はゲーム側で `Kit.new(require(MotifSpec))` に渡す。spec を直したら生成し直す（生成物は手で編集しない）。
