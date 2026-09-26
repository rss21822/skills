# 検証

見た目の仕事は「壊れていない」と「魅力的か」の 2 つを別々に確かめる。前者は数値（コンパイル・テスト・監査）、後者は目（スクリーンショット）。どちらかだけでは足りない。

## 目次
1. コンパイルと既存テスト
2. スキンの Lune テスト
3. Studio 監査
4. 目視チェックリスト
5. Studio 検証の落とし穴

## 1. コンパイルと既存テスト

- 変更・追加した全 `.luau` を Lune でコンパイルする（`luau.compile(source)` を pcall）。Studio に入れる前に構文エラーを潰す。
  ```luau
  local fs, luau = require("@lune/fs"), require("@lune/luau")
  local process = require("@lune/process")
  for _, path in ipairs(process.args) do
  	local ok, err = pcall(luau.compile, fs.readFile(path))
  	print(ok and "OK  " or "FAIL", path, ok and "" or tostring(err))
  end
  ```
  型注釈付きのファイルは Roblox の Luau と同じく通る。`-> T` の関数戻り値注釈を式の位置に書くなどの誤りはここで出る。
- プロジェクトの既存テストを全部流す。UI の名前の契約を固定しているテストが落ちたら、スキン側を直す（テストを緩めない）。

## 2. スキンの Lune テスト

`assets/lune_gui_mock.luau`（最小の GUI モック）と `assets/test_skin_example.luau`（Kit の自己テスト）を雛形に、スキンのテストを 1 本書く。確かめること:

- **適用が冪等**: 2 回適用しても包みが二重にならない、テーマ以外を渡したら何もしない。
- **色の割り当て**: 主役・キャンセル系・一覧の行・無効のそれぞれが期待の面と文字色になる。旧配色（紺）が残っていない。
- **名前の契約**: 主役画面を作り直した後も、テストや他のコードが見る Name・親子関係・属性が同じ。
- **状態変化**: 押下で下縁が沈み、離すと戻る。無効化で灰色になり、有効に戻すと元の色。
- **reduced motion**: ループの tween が作られない。
- **失敗時の戻り**: 主役画面の専用組み立てが失敗したら、元の組み立てが呼ばれ、途中の Instance が残らない。

モックの注意:
- モックのプロパティは未設定なら nil（本物の既定値は無い）。コードが後で読むプロパティは作るときに明示しておく（例: UIStroke の `ApplyStrokeMode`）。
- `Vector2` / `UDim2` の値は float32。`0.05` と `==` で比べると一致しない。`math.abs(a - b) < 1e-4` で比べる。
- レイアウトは計算されない。`AbsoluteSize` に依存するコードは、テストで `AbsoluteSize` を設定してから呼ぶ。

## 3. Studio 監査

`scripts/studio_ui_audit.luau` を execute_luau（datamodel "Client"、Play 中）に貼り、CONFIG を画面に合わせて編集して実行する。確かめる項目:

- **FIT**: 表示中の文字で `TextFits == false`（切れている・はみ出している）。
- **SMALL**: 押せるボタンで幅か高さが 48 px 未満（スマホで押しにくい）。
- **CLIPPED / OVERFLOW-X / OFFSCREEN**: 親の切り抜きや画面の外へのはみ出し。
- **OVERLAP**: 押せるボタン同士の重なり。

サイズ: 画面を包む Frame の大きさを変えて 3 種（例: 1080x720 デスクトップ、828x369 横持ちスマホ、366x820 縦持ちスマホ）。本物の端末の見え方は Studio の Device Simulator（Test タブ → Device）で確認できる。

言語: 対応言語ごとに全画面を回す。日本語と英語では文字列の長さが大きく違う。

画面の開き方: ゲームの本物のナビゲーション関数を呼ぶのが一番確か。本物のサーバー状態が無いと開かない画面は、画面の View を直接作って偽のスナップショット（状態のテーブル）を流し込むハーネスを作る（execute_luau の Client VM では ReplicatedStorage のモジュールを require できる。Client VM のモジュールキャッシュは実行中の LocalScript とは別なので、スキンの適用もハーネス側で行う）。

失敗 0 まで直す。よくある直し方:
- 絵文字が FIT → 箱を TextSize の 1.5 倍以上に（22 pt → 36 px）。
- 見出しが FIT（狭い画面）→ `kit:fitHeading`。
- ボタンが SMALL → 最小サイズの制約（UISizeConstraint の MinSize）か、レイアウトのセル高さを上げる。
- OVERFLOW-X → 列を中央寄せで最大幅を付ける（UISizeConstraint MaxSize）か、グリッドの列数を幅で変える。

## 4. 目視チェックリスト

Studio の screen_capture（`mcp__Roblox_Studio__screen_capture`）かスクリーンショットで、画面ごとに見る:

- モチーフが 3 秒で伝わるか（説明なしで「何の世界か」わかるか）。
- CTA が画面で一番強いか。同じ強さの要素が並んでいないか。
- 読めない文字が無いか（面と文字の組、縁取りの有無）。
- 日本語が細く・ぼやけて見えないか（太さの要求）。
- 装飾が情報を隠していないか（マスコットが文字に重なる、ドットが文字の下で騒ぐ）。
- 押せるものと押せないものが見分けられるか（無効、近日公開）。
- 動き: 開いた瞬間の出現、押したときの手応え、待機ループがうるさくないか。reduced motion を有効にして止まるか。
- 暗幕越しの世界、ワールドの看板まで同じ世界観か。

## 5. Studio 検証の落とし穴

- **AlwaysOnTop の BillboardGui は screen_capture に写らない**。確認のときだけクライアント側で `AlwaysOnTop = false` にする。
- **screen_capture は直前の execute_luau の完了後に撮られる**。操作と撮影の間に 1 フレーム以上の待ちを入れる。
- **ローカルに保存した Place のコピーは DataStore 等のサービスに接続できない**。サーバーの起動処理が途中で止まり、その後に作られるはずの看板などが無いことがある（スキンの不具合ではない）。サーバー側の看板は Server の VM からモジュールを直接呼んで作って確かめる。
- **デスクトップの Studio は `TouchEnabled == false`**。タッチ専用の UI はそのままでは出ない。Device Simulator か、テストでの検証になる。
- **キー入力の送信は Play のビューポートにフォーカスが必要**。ウィンドウを前面にしてビューポートをクリックしてから。
- **Studio の MCP の VM は機能が制限される**（HTTP・任意ファイルの require 不可など）。ローカルのファイルを試すときは Edit で ModuleScript の Source に貼ってから Play する。
- **描画の再入**: 画面を開くと同じ内容が二重に出るなら、描画中に自分の大きさを変えて AbsoluteSize の監視から再入している（integration.md）。
