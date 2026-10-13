# CapCut デスクトップの操作（Windows、版 9.5.0.4050 で確認、2026-10-12）

画面は英語 UI（ユーザーの環境）。

ここに書く座標は、3840x2160 の画面をスクリーンショットの座標系 1456x819 で見たときの値。「どのあたりか」の目安でしかない。画面の大きさ・ウィンドウの位置・CapCut の版で変わるので、毎回スクリーンショットで位置を確かめてからクリックする。

## 許可と起動

1. `request_access` に `["CapCut"]` を渡す。ランチャー `...\CapCut\Apps\CapCut.exe` が許可される。
2. `open_application("CapCut")` で起動し、5 秒ほど待つ。
3. スクリーンショットで CapCut が隠れている（「capcut.exe ... were also hidden」と出る）なら、編集画面の本体 `...\Apps\<版>\CapCut.exe` がまだ許可されていない。
   - `request_access` に `["capcut.exe"]` を渡す。`reason` には「CapCut の編集画面の本体（版ごとのフォルダの CapCut.exe）」と書く。
   - ユーザーは 1 つ目と同じものだと思って拒否しやすい。拒否されたら AskUserQuestion で説明してから出し直す。
4. すでに CapCut が開いていて、別のプロジェクトを編集中のこともある。そのプロジェクトには触らない。ユーザーの作業中のプロジェクトを閉じる前には確認する。

### 「Textinputhost is in front」と言われて操作できないとき

Windows の入力補助（TextInputHost の「Windows 入力エクスペリエンス」）の透明なウィンドウが前面を握り続けることがある。入力欄に文字を入れたあとに起きやすい。

- `open_application` を何度呼んでも、PowerShell の SetForegroundWindow や SwitchToThisWindow を使っても、前面は取り戻せない（Windows の前面ロック）。
- textinputhost の許可は求めない（ユーザーが拒否済み）。入力も送らない。
- AskUserQuestion で「CapCut のウィンドウを 1 回クリックして」と頼む。答えが返ったら CapCut の中（パネルの見出しなど、押しても何も起きない場所）を 1 回クリックしてから続ける。
- 前面のウィンドウは、`GetForegroundWindow` とプロセス名を出す小さな PowerShell で確かめられる。

## 新規プロジェクトと読み込み

1. ホームの「Create project」を押す。編集画面が最大化で開く。右の Details に Frame rate（既定 30.00fps）が出る。
2. メディア欄の「Import」→「From device」で、Windows のファイルダイアログが開く。
3. 「ファイル名(N)」の欄をクリックし、元動画のフルパスを `type` で入れて Enter。
   - 日本語キーボードでは `\` が `¥` に見えるが、それで正しい。
   - 長い文字列の `type` はクリップボード経由で入る（ユーザーのクリップボードを上書きする。報告で伝える）。
4. 右下に「Keyboard shortcut conflicts with an existing one」が出たら × で閉じる。
5. メディア欄のサムネイルを、タイムラインの「Drag material here and start to create」へドラッグする。主トラックの 0:00 から並ぶ。

## 30 秒を切り出す（フレーム単位で正確に）

時刻はプレイヤーの左下に `現在 / 合計` の形で出る（例 `00:03:01:26 / 00:05:05:08`。最後の 2 桁はプロジェクトのフレーム番号）。目安の位置は (503, 416)、幅 125、高さ 14。この欄はクリックしても編集できない。

1. 定規（タイムライン上端の目盛り）をクリックすると、再生位置がそこへ飛ぶ。目盛りのラベルの位置から「1 分あたりの横幅」を測り、開始時刻の位置を計算してクリックする。
2. 時刻を読む。
   - `python scripts/read_screen.py --frame 1456x819 --rect <X,Y,W,H> --out <scratch>/tc.png` を実行し、PNG を Read で見る。
   - 撮る直前にスクリーンショットを撮り、CapCut が最前面にあることを確かめる。他のアプリが前にあると、そのアプリが写る。
3. ←/→ は 1 フレーム動く（プロジェクトのフレームレートで。既定の 30fps なら 1/30 秒）。
   - 読み取った時刻との差をフレーム数にし、`key` の `repeat` で押す（1 回の呼び出しで最大 100 回）。
   - もう一度読み、開始ちょうど（例 `00:01:20:00`）になったか確かめる。
4. Ctrl+B で、選択中のクリップを再生位置で分割する（追加した直後のクリップは選択されている）。
5. 終了時刻（開始 + 30 秒）でも 1〜4 を繰り返す。
6. 後ろの部分（選択中）を Delete し、前の部分をクリックして Delete する。主トラックは磁石つきなので、残った 30 秒が 0:00 へ詰まる。
7. 時刻の表示が `00:00:30:00 / 00:00:30:00` になったことを read_screen.py で確かめる。

## 書き出し

1. 右上の「Export」を押すと、書き出し画面が開く。
2. **Name:** 開くたびにプロジェクト名（例 `1012 (1)`）に戻る。欄を triple_click → Ctrl+A → `type` で名前（拡張子なし）を入れる。
3. **Export to:** 前回の場所を覚えている。
   - 実行フォルダでなければ、右のフォルダアイコンでフォルダ選択のダイアログを開く。
   - 「フォルダー:」の欄には文字を入れられない。ドラッグもできない。
   - 左の一覧（GitHub など）と、右の項目のダブルクリックでたどる。スクロールは、スクロールバーの溝をクリックする。
   - 実行フォルダを開いたら「フォルダーの選択」を押す。
   - うまくいかないときは、既定の書き出し先へ書き出してから PowerShell の `Move-Item` で実行フォルダへ移す（中身は変わらない）。
4. **Video** にチェックを入れて、各項目を設定する。
   - Resolution: 1080P
   - Bit rate: Higher（選択肢は Lower / Recommended / Higher / Custom。前回の値を覚えている）
   - Codec: H.264
   - Format: mp4
   - Frame rate: 開くたびに 30fps に戻る（選択肢は 24 / 25 / 29.97 / 30 / 50 / 59.94 / 60fps）。16:9 は 30fps、9:16 は元に合わせる（60fps の元なら 60fps）。
5. 「Sync exported videos to space」はオフにする（クラウドへ上げない）。下の「Audio」のチェックは音声だけを別のファイルで書き出す設定なので、オフのままにする（動画には音声が入る）。
6. 左下に「Duration: 30s」と出ているのを確かめて「Export」を押す。30 秒なら十数秒で終わる。
   - 同じ名前のファイルがあると「File already exists … replace it?」と出る。上書きしてよいときだけ OK を押す。
7. 終わると、「Video is saved to your desktop or laptop. You can share it now.」という共有パネルが開く。共有しないときは「Close」を押す。

結果（参考）: 30 秒の 1080P・Higher で、30fps は約 12.6 Mbps（約 48 MB）、60fps は約 17.8 Mbps（約 68 MB）。音声は AAC 44.1 kHz、192 kbps。

## 9:16 版

同じプロジェクトで続ける。

1. プレイヤーの右下にある比率のメニュー（目安 (963, 423)）から 9:16 を選ぶ。
   - 選択肢: Original / Custom / 16:9 / 4:3 / 2.35:1 / 2:1 / 1.85:1 / 9:16 / 3:4 / 5.8-inch / 1:1
2. クリップを選び、右のパネルの Video > Basic > Transform で Scale を 316% にする（1920 ÷ 607.5 = 高さいっぱい）。
   - 数値の欄に `type` で数字を入れると、日本語 IME が入力を横取りして入らない。
   - スライダーをドラッグして近くまで寄せる（目安: 100% が x≈1080、307% が x≈1230）。
   - そのあと、欄の右の ▲（目安 (1418, 114)、1 回で 1%）を押して 316% にする。
   - Position は X 0、Y 0 のまま。
3. プレビューで縦いっぱいに映り、上下に黒帯が無く、プレイヤーのキャラクターが中央にいるのを確かめる。
4. 書き出し画面で、Name の末尾を `_9x16` にする。Resolution 1080P（9:16 なら 1080x1920 になる）、Bit rate Higher、フレームレートは元に合わせる。
5. 書き出し後の共有パネルは閉じずに残す（SKILL.md の手順 6）。

## 共有パネル（TikTok / YouTube への非公開アップロード）

ユーザーの確認（SKILL.md の手順 5）が取れているときだけ使う。

- 右に「TikTok」と「YouTube」のタブがある。下に「Open folder」「Share」「Close」。
- **1 回共有すると「Your video has been shared」の画面になり、OK で閉じる。** もう一方の SNS へは、同じ設定で書き出し直して（上書き）パネルを開き直す。
- サインイン（「Sign in」）は Chrome で開く。ユーザーにサインインと許可をしてもらう。パスワードは入力しない。

### TikTok タブ

- **Account:** サインインしているアカウント（例 `roblox_spinout`）と「Log out」。
- **「Go to TikTok Studio for full settings」:** ブラウザ側の詳細設定へのリンク。
- **Name:** キャプション。
  - 最初は CapCut の宣伝文が入っている。消してから入れる。
  - 文字数の表示（例 156/150）は、入れ直しても古い値のまま変わらないことがある。実際に送られるのは欄の文字。
- **Visibility:** 既定は Private。Private のままにする。
- **Allow:** Comment / Duet / Stitch。既定はすべてオフ。
- **Disclose video content:** オンにすると「Your brand」「Branded content」を選ぶ欄と、「TikTok's Music Usage Confirmation」に同意する旨の文が出る。SpinOut は Owner の判断でオフ。
- **Check copyright?:** 既定はオフ。
- **Share を押した後:**
  - 「Sharing...」の画面にアカウント・Name・Resolution・Visibility・Allow が出る。ここでキャプションと Private を確かめる。
  - 30 秒（約 68 MB）で 30 秒ほどかかった。

### YouTube タブ

上から順に次の項目がある。さらに下にも項目があり、スクロールで確かめる。

1. 「Also share to TikTok」: 動画のタイトルとカバーを TikTok にも送る設定。オフにする。
2. 「TikTok Ads Manager」と「Go to TikTok Studio for full settings」のリンク。
3. Account（「Sign in」）
4. Name（0/100）: タイトル。最初は空。
5. Description（156/5000）: 最初から CapCut の招待文「Invite friends to download CapCut Desktop and get free Pro together. Add invitation link」が入っている。必ず消してから入れる。
6. Playlist（None）
7. Category

**順番に注意。** 2026-10-12、YouTube のサインインが終わった直後に共有が始まった。タイトルは空（YouTube 上では「unknown」）、説明は CapCut の宣伝文「#CapCut I made this amazing video with CapCut…」のまま、公開で上がった。

だから、サインインより前に次を全部済ませる:
- タイトル
- 説明
- 公開範囲（下へスクロールして探す。非公開にする）
- 「Also share to TikTok」をオフ

公開範囲の欄が見つからなければ、CapCut からは上げない。

**Private を選んでも公開で上がることがある（2026-10-12、CapCut 9.6）。**
- Visibility の既定は Public。Private を選んで共有したのに、YouTube Studio では「公開」になっていた。
- 共有したら、すぐユーザーの Chrome で YouTube Studio の「ショート」を開き、公開範囲を確かめる。「公開」なら、動画一覧の公開設定の欄から非公開にする。
- 上がったショートが一覧に出るまで、20 秒ほどかかった。

**Description の文字:** 初めは灰色の文字（CapCut の招待文）が入っている。Ctrl+A と BackSpace では消えなかった（灰色の表示が残った）。何か 1 文を入れると、表示が入れた文に置き換わる。空のままにしないで、固定の紹介文などを入れる。

版 9.6.0.4097 でも、操作の流れと画面の配置は 9.5 と同じだった。

## プロジェクトをゴミ箱へ移して終了（2026-10-12 に確認）

1. 編集画面を右上の × で閉じる。ホーム（プロジェクト一覧）に戻る。保存の確認は出なかった。
2. ホームの Projects で、今回のプロジェクトのサムネイルを右クリックする。名前は日付の数字で、例は `1012 (1)`。サイズと長さ（例 `257.1M | 00:30`）でも見分けられる。
3. メニュー（Upload / Rename / Duplicate / Delete）の「Delete」を押す。「Move to Trash? Items moved to Trash will appear here and be deleted after 30 days.」に OK を押す。
   - 一覧の右上の「Trash」から戻せる。
   - 今回作ったもの以外は触らない。
4. ホームのウィンドウを右上の × で閉じると、CapCut が終了する。1 回目のクリックは前面に出すだけで効かないことがあった。保存を聞かれたら「保存しない」を選ぶ。
5. CapCut のプロセスが残っていないか確かめる（`Get-Process` で Path に CapCut を含むもの）。残っていても、自分が起動したものでなければ止めない。
