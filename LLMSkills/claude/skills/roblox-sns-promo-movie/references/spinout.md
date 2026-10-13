# SpinOut!（Roblox）の広報情報と映像の見方

リポジトリ: `C:\Users\ryufu\OneDrive\ドキュメント\GitHub\SpinOut`。movie フォルダは `artifacts/movie/`。既存の広報動画もここにあり、git で追跡されている。

## 投稿に使う値（2026-10-12 時点）

古くなったら、公開記録 `artifacts/qa/` で確かめて直す。

- **名前:** SpinOut!（Creator Hub での表示名は `[Beta] SpinOut!`）
- **ゲームのページ:** https://www.roblox.com/games/131935467331925
  - 本番 universe `10769273081` の開始 Place（= Lobby）。
  - 2026-10-11 の公開記録では、本番は Public。
  - 投稿文に「Play now」と書く前に、ブラウザでページを開き、公開されて遊べる状態か確かめる。非公開に戻っていたら「in development / coming soon」という言い方にする。
- **公式 X:** https://x.com/roblox_spinout（@roblox_spinout）
- **Discord:** https://discord.gg/fKmaff7V
- **TikTok:** @roblox_spinout。CapCut の共有パネルでサインイン済み。
  - 過去の投稿は英語で、絵文字つきの短い説明とハッシュタグ（#Roblox #robloxgames など）。
- **YouTube:** チャンネル「SpinOut!」（`UCNKYTNW8NpXHYpQ1qbIxWzA`）。2026-10-12 から CapCut の共有パネルでサインイン済み。
  - YouTube Studio: https://studio.youtube.com/channel/UCNKYTNW8NpXHYpQ1qbIxWzA/videos/short
- **制作:** Roblox グループ「SpinOut」

## 固定の紹介文（どの投稿にも必ず入れる）

```
SpinOut! is an ice-skating fighting game where players battle like human Beyblades!
```

- Owner の指定（2026-10-12）。X の本文・TikTok のキャプション・YouTube ショートの説明・Reddit の本文（サブレディットごとの案すべて）に、この 1 文をそのまま 1 回入れる。
- 言い換え・短縮・翻訳・大文字小文字の変更はしない。末尾の「!」も残す。
- 前に使っていた「SpinOut! is an ice-skating battle game on Roblox (beta).」は使わない。
- 長さは英字 83 字。
  - X: 280 字のうち残りは 197 字（URL は 23 字と数える）。
  - TikTok: CapCut の欄の 150 字のうち、残りは 67 字。クリップの一言は 45 字前後、ハッシュタグは 2 つにする。
- この文には「Roblox」も「beta」も入っていない。Roblox で遊べることは、URL・ハッシュタグ・タイトルなど別の場所で伝える。
- 同じ投稿の中で呼び方がずれないよう、タイトルなどでもジャンルは「fighting game」と書く（「battle game」は使わない）。

## Owner が決めたこと（アップロードの設定）

- **TikTok:** 宣伝の開示（Disclose video content / Your brand）はオフ（2026-10-12）。
  - TikTok の方針では、自分の宣伝には開示が要る（`platforms.md`）。Owner が変えるまでオフで上げる。
- **YouTube:** 「子ども向けか」は「いいえ、子ども向けではありません」（2026-10-12）。
  - 既存のショート「SpinOut! Basic Rules Explained」は「はい」のまま。そちらは変えていない。
- **AI の使用・AI 生成のラベル:** どの SNS でもオフ / いいえ（実際のゲームプレイの映像のため）。
- **公開範囲:** アップロードは非公開だけ。公開への切り替えは Owner が行う。

## どんなゲームか（投稿文の材料）

- 氷のリンクで最大 6 人が滑りながら戦うバトルロイヤル（FFA）。1 試合 4 分 30 秒、残機 5（`src/shared/RivalsModeCatalog.luau`）。
  - スピンで相手を弾き飛ばし、リンクの外（イエローラインの外）へ押し出す「リングアウト」で倒す。
- **モード:** Classic と Death Ball。人数が足りないときは NPC で埋まる。
  - Death Ball はペンギンボールが飛び交う。
  - どの試合でもペンギンボールが出る（2026-10 時点）。
  - 敵のボールは狙った相手を追いかける。スピンで弾き返せて、弾き返したボールは自分のものになる。
- **攻め方:** スピン攻撃とダッシュで攻める。相手の攻撃に合わせると「PERFECT COUNTER」で返せる。
- **勝敗:** 残機（ハート）が尽きると脱落。順位は撃破数と残り残機の合計で決まる。
- **BGM:** Roblox Creator Store の APM Music（APMOfficial）。
  - 試合ごとに次の 5 曲から 1 曲が流れる（`src/pa/shared/MatchConfig.luau` の `ROUND_BGM_TRACKS`）: ヴィヴァルディ「四季」の冬・夏・秋、グリーグ「山の魔王の宮殿にて」、ホルスト「Holst Recomposed」。
  - 終盤とリザルトにも APM の曲が流れる。
  - Creator Store の無料アセットで、Roblox の外（SNS）で使う権利は確かめていない（2026-10-12 時点）。
  - 報告で毎回伝える。プラットフォームから著作権の通知やミュートが来たら、Owner に判断してもらう。

## 映像の見方（白熱した場面を探すとき）

- **画面の配置:**
  - 画面中央の下がプレイヤー（追いかけるカメラ）。
  - 左下が残機（ハート）と数字、ゲージ。右下がスキルのボタン。上の中央が試合の残り時間。
- **ペンギン:**
  - 赤く光るペンギン = 自分に敵対しているペンギン。
  - スケーターの足元のピンクの輪と矢印 = ペンギンにロックオンされている。危険の予兆なので、冒頭に置くとよい。
- **リングアウト:**
  - 黄色の線 = リングアウトの線。板に「RING OUT 0.5s」と出たら、線まであと 0.5 秒の警告。
  - 「RingOut!」の文字 = 誰かが場外へ出た。直後に復帰のカウントダウン（2、1、GO）が出る。
- **その他の表示:**
  - 「PERFECT COUNTER」の帯 = 攻撃した側が完璧にカウンターされた（攻撃が成功したのではない）。
  - 「ELIMINATED <名前>」= 脱落の通知。右側に倒した / 倒された記録が流れる。
  - 残機の数字が減る瞬間 = 自分がやられた。相手を倒した場面と合わせて、決着の山場になる。
- **使わない区間:**
  - 試合の最初（スタジアムの俯瞰と READY）と最後（FINISH → Winning Run → リザルト）。
  - 1 人で滑っているだけの時間は長い。敵が 2 人以上映る区間を優先する。

## 過去の切り出し（参考）

- **2026-10-06 16-39-30.mp4**（Death Ball、4:30 の試合）
  - 3:00–3:30 を採用（スキルを作る前の手作業）。
    - 3:06–3:13 に複数人の乱戦。3:13 にセンターで衝突し、3:16 に RingOut、3:19 に復帰。
  - 候補だった 1:56–2:26（自分のリングアウト 2 回）は、敵がほとんど映らないので外した。
  - CapCut のプロジェクト「1012」は残っている。
- **2026-10-06 16-47-05.mp4**（スキルの最初の実行、`artifacts/movie/[DailyPV] 2026-10-12_121532/`）
  - 1:20–1:50 を採用。
    - 0:02 に接触、0:05 に RingOut（残機 3→2）。
    - 0:14–0:18 にペンギンのロックオン、0:19 に RingOut（残機 2→1）。
  - 2:06 の脱落は区間の外。
  - TikTok と YouTube に非公開で上げた。YouTube は一度公開で上がってしまい、直した（`clip_report.md`）。
