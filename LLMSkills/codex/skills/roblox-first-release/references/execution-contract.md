# 呼出しごとの実行契約

## 入力を閉じる

開始ごとに新しいUUIDの `run_id` と絶対パスの記録先を作る。「最後のmanifest.json」や別Skillのインストール領域を作業領域にしない。再開も新契約を作り、旧run_idは参照に残す。

契約に必要な情報:

- 人間の依頼の範囲と根拠。設定・アップロード・一般公開・実機・購入等の許可は別項目。
- 所有者の種別／ID、認証アカウント、環境、Universe、入口と全PlaceのID／役割。新規ID未確定なら作成工程以外の外部変更を禁止し、取得後に契約版を確定。
- 間違えてはならない他環境のUniverse／Place一覧。存在しない環境を作って記入する必要はない。
- 正本・Git HEAD／差分／未保存状態、ビルド方法、編集可能ファイル、入力ファイルとハッシュ。
- 項目ごとの現在値／希望値／変更許可。商品、翻訳、Audience、端末・年齢・地域等。必要な選択が未確定なら該当工程を開始しない。
- 検証profile、必要な完了区分、公開資格・アセット・コンプライアンス根拠と未解決。
- 各子Skillの名前、今回読んだSKILL.mdのSHA-256、受け入れたprofile、担当操作、入力／出力／終了条件。

変更時は版を上げ、依存証拠を無効化する。子への契約は担当範囲に限定し、全許可を渡して「必要なら何でも」としない。

## 引渡し例

これは架空のAPIではない。Codexが実際のSkillを読み、工程を実施する。

```text
run_id: <今回のUUID>
child: prepare-roblox-private-production
execution_profile: configuration-upload
target: <所有者ID / production-private / Universe / root / 全Place>
operations: <承認済み設定項目と必要なら全Place公開>
inputs: <絶対パス / SHA-256 / 商品ID>
evidence_dir: <今回の子専用サブディレクトリ>
excluded: <他環境ID / 未許可ファイル / 一般公開 / Player / 実購入>
required_output: <設定再読取 / 各公開版と時刻 / 対応ハッシュ / 未完了>
```

子も対象と現在値を再確認し、矛盾した契約は拒否する。Profileは今回だけ有効で、後続実行や単独実行の既定値を変えない。親の指示は人間の許可を拡大しない。

## 各子の終了条件

- `create-roblox-private-experience`: standalone既定は `full-validation`。明示された `configuration-upload` はLOCAL+CLOUDと終了処理で完了、PLAYERは未依頼。対象は一つの非公開Experience。初期版と完成版を区別する。
- `prepare-roblox-private-production`: standalone既定は `full-validation`。`configuration-upload` は今回担当する設定・公開版・終了処理まで。PLAYERは未依頼。
- `roblox-monetization-setup`: 登録／連携／販売／掲載を別指定。親が最終公開担当なら連携結果を返す第一呼出しと、公開後の販売／掲載呼出しを分ける。依頼された販売が引渡し途中なら全体完了にしない。
- `roblox-group-auto-localization`: 「設定・原文登録・生成状態確認のみ」と明示してPlayerをスキップできる。生成待ちの出力は生成・表示確認完了ではない。
- `roblox-experience-launcher`: 指定実機シナリオが終了条件。設定／公開権限を渡さない。
- `roblox-purchase-revenue-check`: 指定取引の読取のみ。購入や商品作成を渡さない。

profile非対応・必須手順衝突なら、黙示的overrideで進めない。現行本文のハッシュが変われば契約を再点検し、機械的に承認済みハッシュを更新しない。

## 状態の漏出を防ぐ

- 選択中のブラウザ所有者／Universe、Studio接続先、ログインアカウントは契約ではない。外部変更直前に照合する。
- 共有ソース・Place・Cloud変更は許可された永続出力として一覧化する。他PC／Skillが同一項目を変更したら上書きせず差分と方針を確認する。
- 作業ファイル・変数はrun_id別。プロセス全体の環境変数を変えず、明示workdirを使うか終了時にcwdを戻す。
- 資格情報は最小権限・短寿命・対象限定。既存のユーザーキーを削除しない。今回作成した一時キーだけ失効・削除して不存在を確認。値は記録せず、cleanup失敗なら完了にしない。
- 別Skill本文、グローバル設定、グループ権限をリリースの副作用として変更しない。

## 補助監査用JSON

`scripts/audit_release.py` は読み取り専用のID・hash・記録上のゲート監査。記入された外部証拠の真実性や操作許可を保証せず、公式要件照合を代替しない。

必須トップレベル:

- `schema: 1`, `run_id: UUID`
- `target`: `owner_id`, `universe_id`, `root_place_id`, `environment: "production-private"`
- `observed`: 同じ3つのID、`audience`, `evidence`, `observed_at`。現在再読取した値のみ。
- `excluded`: `universe_ids`, `place_ids` の配列
- `requested`: `player`, `public`, `localization`, `monetization` のbool
- `inputs`: `path`, `sha256` の配列。検証根拠のソース／設定を含める。
- `children`: `name`, `path`（SKILL.md）, `accepted_sha256`, `profile`, `contract_accepted: true`
- `places`: `place_id`, `universe_id`, `role: "root"|"child"`, `path`, `sha256`, `published`
- `published`: 未実行はnull、実行済みは `uploaded_sha256`, `response_version`, `observed_version`, `evidence`, `observed_at`
- `checks`: 下記各項目が `status`, `evidence` を持つ。statusは `confirmed|not_applicable|pending|failed|unknown`。confirmedは実在する根拠への参照必須。

checks: `local_validation`, `settings_saved`, `source_language_consistent`, `localization_registered`, `translations_generated`, `monetization_ready`, `cleanup`, `player_acceptance`, `publication_eligibility`, `compliance`, `asset_rights`, `asset_access`, `public_saved`。

`requested.require_translation_generation: true` を指定すると生成完了も必須にする。未指定なら登録完了と生成待ちを分離する。`response_version` はStudio等で数値応答が得られない場合nullとし、時刻・独立履歴の根拠を残す。profile値はcreate／prepareが上記2種、課金が `setup`、翻訳が `settings-only|with-player`、Playerが `scenario`、収益読取が `read-only`。これらは記録上のモード名で、実際の子Skillへ自然文の範囲も明示する。

適用不要は不要な機能にのみ使う。必須設定・全Place版・cleanupを不明のまま置き換えない。新規ID未確定では監査を合格させない。

```powershell
python <skill-dir>/scripts/audit_release.py --manifest <run-dir>/release.json --stage root
```

`preflight` は対象照合、`root` は入口公開前、`finish` は設定・アップロード終了、`public` は一般公開ゲートの確認。公開変更前は `public_saved` を未確認に残し、一般公開完了にしない。監査自体は外部操作を実行しない。
