# UI と文言

## 文言
- **ゲームのソース言語**で書く（文脈シート）。翻訳はゲームの仕組み（LocalizationTable 等）へ。設計書の言語ではなく、ゲーム内の文字の言語。
- 短く: 見出し 1〜3 語、本文 1 行。操作名は HUD のボタン/ラベルと同じ呼び方。
- キーは `{key:W}` と書く → `GetStringForKeyCode` で配列（AZERTY 等）に合わせた表示。リバインド対応のゲームは設定から取る。
- `prompt = { keyboard, gamepad, touch }` を全部用意。最後の入力（`Detector.device`）で切り替え、入力が変わったら貼り替える。
- 救済で進んだときに責める文言を出さない。

## UI
- 新しい汎用カード（紺の半透明パネル、薄い枠、細い白文字）を作らない。HUD のパネル・ボタン・見出し・メーターの生成関数、書体、色、角の扱いをそのまま使う。モチーフの翻訳が要るなら roblox-ui-designer。
- `TutorialGuideController` の `view` は 4 関数（stage / step / progress / hide）。UI は一度作り、文字と大きさだけ更新する（毎フレーム生成しない、PlayerGui への大量追加を避ける）。
- 進捗メーターは戻さない。
- 安全域: Roblox のトップバー（上 58 px）、タッチの親指スティックとジャンプボタン、ゲームの HUD の主要表示を隠さない。スマホ幅でも収まるか（TextFits / TextService）。
- 日本語は Bold 以上を要求（CJK はシステムフォントに落ちる）。
- reduced motion を尊重、点滅しない。
