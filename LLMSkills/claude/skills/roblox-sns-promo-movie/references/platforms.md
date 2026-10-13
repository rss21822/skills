# 投稿先ごとの決まりと下書きの型（2026-10-12 調査）

各項目に出典を付けた。[公式] は各社のヘルプ、[二次] は第三者の記事、「未確認」は一次情報が見つからなかったもの。SNS の上限や画面はよく変わる。調査から半年以上たっていたら、投稿前に公式ページで確かめ直す。

reddit.com はこの環境のツールから読めない（Reddit がクローラーを拒否している）。サブレディットの規則は第三者の読み取りしか無い。

## 共通

- 投稿文は英語で書く。映っていないこと、試合の結果と違うことは書かない。宣伝でも誇張は信用を落とす。
- ゲームに「固定の紹介文」があれば（SpinOut は `spinout.md`）、どの投稿にもそのまま 1 回入れる。Reddit は案ごとの本文すべてに入れる。言い換えず、字数が足りなければ他の部分を削る。
- 実際のゲームプレイの録画なので、どの SNS でも AI 生成の申告やラベルは付けない。加工していない映像に AI のラベルを付けるのは、TikTok では規約違反になる。
- 添付するファイル:
  - X と Reddit: 16:9（30fps）
  - TikTok と YouTube ショート: 9:16
- このスキルが自分で行う送信は、TikTok と YouTube への非公開アップロードだけ（SKILL.md の手順 5〜6）。X と Reddit は下書きのファイルまでで、投稿はユーザーが行う。
- 各下書きの末尾に notes を付ける。書くこと:
  - 添付するファイル
  - 投稿前に決めること
  - BGM の権利（SpinOut は `spinout.md` の BGM の項）

## X（`post_x.txt`）

- **本文の長さ:** Premium でない場合、重み付きで 280 まで。英字と記号は 1、日本語と絵文字は 2、URL は長さに関係なく 23 と数える。添付ファイルは数えない。`scripts/x_count.py` で確かめる。固定の紹介文（SpinOut は 83 字）を入れると 250 前後になる（2026-10-12 の例は 251）。280 を超えないこと。 [公式] https://docs.x.com/fundamentals/counting-characters
- **ハッシュタグ:** 2 つまで（X の推奨）。 [公式] https://help.x.com/en/using-x/how-to-use-hashtags
- **Web から上げる動画の上限:** [公式] https://help.x.com/en/using-x/x-videos
  - 140 秒、512 MB
  - 1920x1200（縦は 1200x1900）、40fps、25 Mbps
  - 縦横比 1:2.39〜2.39:1
  - このため 16:9 は 30fps で書き出す。60fps の動画と 1080x1920 の縦動画はこの上限を超える。拒否されるのか変換されるのかは未確認。
- **「Allow video to be downloaded」:** 既定でオンで、投稿後は変えられない。notes に書き、ユーザーに決めてもらう。
- **下書き:** Web の下書き（Unsent posts / 未送信のポスト）に動画が残るかは、公式に書かれていない。保存したら開き直して確かめる、と notes に書く。
- **AI の表示:** 「Made with AI」は付けない。

型:

```
<1 行目: クリップで起きること（映っていることだけ）>

<固定の紹介文（そのまま）> <短い補足（任意）>
<ゲームの URL>
#<タグ1> #<タグ2>
# ---- notes (not part of the post) ----
# Attach: <16x9 のファイル名と仕様>
# Length: python scripts/x_count.py post_x.txt
# 投稿前に決めること / AI の表示はしない / BGM
```

## TikTok（`post_tiktok.txt`）

- **キャプション:** CapCut の共有パネルの欄は 150 字までと表示される。TikTok 本体は 2,200 字まで（API の値）。150 字以内にする。 [公式] https://developers.tiktok.com/doc/content-posting-api-reference-direct-post
  - 固定の紹介文（SpinOut は 83 字）を入れると、残りは 67 字。クリップの一言は 45 字前後、ハッシュタグは 2 つにする。
  - 例（149 字）: `Two ring-outs in 15 seconds 😱 One life left. <固定の紹介文> #roblox #robloxgames`
  - 絵文字は環境によって 2 字と数えられる。Python の `len` と UTF-16 の長さの両方が 150 以下になるようにする。TikTok Studio の文字数表示は UTF-16 の長さ（2026-10-12 に確かめた）。
- **上げた後のキャプションの編集:** TikTok Studio の投稿一覧の鉛筆のボタンから直せる。欄は 4,000 字まで。ただし、キャプションとカバーの編集は 1 日 1 回、投稿後 7 日以内だけ（編集画面の注意書き、2026-10-12）。
- **リンク:** キャプションのリンクは押せない（未確認。第三者の説明はどれも同じ）。リンクは書かず、「SpinOut! on Roblox」での検索かプロフィールのリンクへ誘導する。
- **公開範囲:** 新しい投稿は、直前の投稿の公開範囲を引き継ぐ。毎回、Only me（自分のみ、CapCut では Private）を明示して選ぶ。 [公式] https://www.tiktok.com/support/faq_detail?id=7581826684085606968&lang=en
- **宣伝の開示（Disclose video content → Your brand）:**
  - TikTok の方針では、自分や自分の事業の宣伝は開示をオンにする必要がある。付く「Promotional content」のラベルは、投稿後に変えられない。 [公式] https://www.tiktok.com/support/faq_detail?id=7636670088170904085&lang=en
  - SpinOut は Owner の判断（2026-10-12）でオフにしている。Owner が変えるまでオフで上げ、notes にそう書く。
- **AI のラベル:** 「AI-generated content」はオフ。C2PA の情報が付いた動画や、TikTok の AI エフェクトを使った動画には自動でラベルが付き、外せない。 [公式] https://www.tiktok.com/support/faq_detail?id=7636670084747893268&lang=en
- **動画:** MP4、H.264、23〜60fps（API の基準）。9:16 の 60fps でよい。 [公式] https://developers.tiktok.com/doc/content-posting-api-media-transfer-guide

型:
- 1 行の英語キャプション: クリップの一言 + 固定の紹介文 + ハッシュタグ 2 つ。
- notes には次を書く: 添付ファイル、公開範囲、開示、AI のラベル、BGM、アップロードの結果。

## YouTube ショート（`post_youtube_shorts.md`）

- **ショートの条件:** 縦か正方形で 3 分以内の動画がショートになる。16:9 で上げると通常の動画になる。 [公式] https://support.google.com/youtube/answer/15424877?hl=en
- **文字数:** タイトルは 100 字、説明は 5,000 字まで。 [公式] https://support.google.com/youtube/answer/57407?hl=en
- **ハッシュタグ:** タイトルの上には 3 つまで表示される。60 を超えると全部無視される。 [公式] https://support.google.com/youtube/answer/6390658?hl=en
- **公開範囲:** 18 歳以上のアカウントの既定は「公開」。必ず「非公開」を選ぶ。 [公式] https://support.google.com/youtube/answer/57407?hl=en
- **子ども向けかどうか:** [公式] https://support.google.com/youtube/answer/9528076?hl=en
  - 回答は必須。未回答のままだと、YouTube Studio の詳細ページでは他の項目の変更も保存できない。
  - SpinOut のチャンネルは、Owner の判断（2026-10-12）で「いいえ、子ども向けではありません」にする。
  - 既存のショート「SpinOut! Basic Rules Explained」は「はい、子ども向け」のまま。
- **AI の使用（旧称 Altered content）:** 「いいえ」。ゲームプレイの映像は、申告の要らない例に挙がっている。 [公式] https://support.google.com/youtube/answer/14328491?hl=en
- **有料プロモーション:** 自分のゲームの宣伝が対象かどうかは書かれていない（未確認）。触らない。
- **`#Shorts`:** 必要かどうかは公式に書かれていない（未確認）。付けても害はない。

型:
- Title（100 字以内）
- Description: 起きたこと、固定の紹介文（＋短い補足）、▶ Play の URL、X、Discord、ハッシュタグ
- notes: 添付ファイル、公開範囲、子ども向け、AI の使用、BGM、アップロードの結果

## Reddit（`post_reddit.md`）

- **タイトル:** 投稿後に変えられない（本文だけ編集できる）。 [公式] https://support.reddithelp.com/hc/en-us/articles/205191195-Can-I-edit-my-posts-and-comments
- **動画:** Premium なしで 15 分まで。 [公式]
- **宣伝の扱い:** サブレディットごとに違う。Reddit は「宣伝は、そのサブレディットでの自分の投稿とコメントの 10% まで」という目安を紹介している。 [公式] https://support.reddithelp.com/hc/en-us/articles/28012014962580-How-do-I-keep-spam-out-of-my-community
- **モデレーターの設定:** フレアの必須、動画投稿の禁止、タイトルの制限、リンクできるドメインの制限を設定できる。投稿画面で確かめる。 [公式]
- **下書き:** ファイルに残す。Reddit の下書きに動画が残るかは未確認。
- **投稿先の候補:**
  - 規則は第三者（ThreadFox）が 2026-09-26〜10-05 に読み取ったもの。投稿前に本物のルールを読み直す。 https://threadfox.vip/rules/for/games
  - **r/roblox:** 規則は「作ったものを見せる。宣伝はしない」。リンクの宣伝ではなく作品を主役にする。同じ話題の重複投稿は禁止（3 日間）。AI の画像・動画・文章も禁止。→ 作品紹介の文にし、本文にリンクを入れない。
  - **r/robloxgamedev:** ゲームの宣伝だけの投稿は禁止。開発の話（仕組み、制作の過程、タイムラプス）として出す。
  - **r/RobloxDevelopers:** 作品のショーケースは可。行き過ぎた宣伝は削除される。
  - **r/indiegames:** 映像つきの宣伝は可。タイトルは疑問文にしない。投稿は週 2 回まで。リンクより先に映像を置く。
  - **r/IndieGaming:** 宣伝は 2 週間に 1 回まで。アカウントが 1 週間以上たっていて、投稿の履歴があること。
  - **r/gamedev:** ショーケースが禁止。使わない。
- 1 回の実行で全部に出さない。1〜2 か所ずつにする。

型:
- サブレディットごとに Title と Body の組を書く。どの Body にも、最初の文として固定の紹介文を入れる。
- 最後に「Before posting」として、ルールの読み直し、フレア、10% の目安、BGM を書く。
