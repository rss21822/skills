---
name: roblox-first-release
description: >
  Robloxゲームの初回本番リリースを、対象確認、非公開Experience、課金設定、
  自動翻訳、全Placeアップロード、公開準備判定まで一気通貫で進める。
  明示された場合だけ一般公開・Player検証を実行する。単独のStaging更新は対象外。
---

# Roblox First Release

本番初回リリースの管理担当。個別操作は専門Skillに任せ、対象・権限・依存関係・証拠・完了判定を管理する。Skillは実行APIではない。読み込んだだけで「実行済み」にせず、Codexが実際の手順を実行・照合する。

標準は **非公開での設定・全Placeアップロード完了**。Player検証、実購入、有料審査、広告、一般公開は自動追加しない。初回公開「準備」の依頼と、AudienceをPublicへ変更する依頼を区別する。

## 開始とカプセル化

最初に [references/execution-contract.md](references/execution-contract.md) を読む。独立した今回用の実行契約と記録ディレクトリを作る。各Skillは単独でも対象発見から終了確認まで実行可能とし、親からの呼出しも同じ入口を使う。

- カプセル化とは、意図した成果物・IDの受渡し以外に、別Skill・別実行の状態や許可を漏らさないこと。共有するCreator Hubの実状態まで影響ゼロにはできない。
- 各呼出しで対象と現在値を再読取する。前の会話、cwd、環境変数、Studio窓、APIキー、完了記録を暗黙の入力にしない。
- 子Skillの入力を限定し、出力を受け取って検証する。親専用の都合で子Skill本文やグローバル設定を実行時に書き換えない。呼出し後にcwd・一時変数・一時資格情報を片付け、永続的な成果だけ明示して引き渡す。
- 依頼の範囲内の通常作業は終了確認まで続行する。工程ごとの「続行してよいか」は不要。ただし対象不明・必要な選択・上位ルールの確認・安全な実行経路の欠如は具体的に報告して停止する。一気通貫は障害や未許可操作を無視する意味ではない。

## 対象と変更許可

所有者／グループ、認証アカウント、Universe、入口と全子Place、ローカル正本を確認する。新規なら「本番用の非公開Experience」の作成依頼を必要とする。既存本番の更新もIDで識別し、既知のSpinOut値などを初期値にしない。

項目ごとに現状値・希望値・許可範囲・未決定を記録する。商品内容／種別／価格／販売・外部掲載、原文／対象言語、年齢／地域／端末、Audience、コード編集／公開対象、実購入／有料処理は別項目。未指定は現状維持か必要な質問とし、全言語・全端末・最安価格などを補完しない。商品や翻訳を使わないゲームには、その工程を適用不要と記録する。

開始時に公式の現行公開要件、アカウント権限、対象Audienceの資格・審査・質問票を確認する。Private／Limited／Publicを区別し、入場失敗を理由に範囲を広げない。利用するアセットだけ、来歴・権利・対象Experience権限・審査状態を分けて確認する。権限、資格、有料審査が不足しても自動変更・支払いはしない。

## 専門Skillへの引渡し

利用する子Skillの現在のSKILL.mdと必須参照を読む。契約の対応範囲と本文ハッシュを記録する。未インストール、変更後に未確認、終了条件の衝突は、成功扱いも黙示の代替も禁止。

- 新規非公開本番作成: `create-roblox-private-experience`。`production-private` と今回だけ `execution_profile=configuration-upload` を明示する。依頼されたPlayer検証は完成版公開後の専用工程へ集約し、初期版作成時に重複実施しない。
- 既存非公開本番の設定・全Place更新: `prepare-roblox-private-production`。同じprofileと、今回担当する設定／アップロード項目を明示する。既に確認した対象も現在値を再照合する。子単独の `full-validation` 既定は変更しない。
- 商品設定: `roblox-monetization-setup`。承認済みの商品一覧、変更可能ファイル、販売／外部掲載の別許可を渡す。商品未使用なら呼ばない。
- 翻訳: `roblox-group-auto-localization`。今回のUniverse、全Place、原文／対象言語、追加対象、通常は「設定・登録・生成状態確認のみ。Player実機スキップ」と明示する。生成待ちを表示確認済みにしない。
- 指定Player検証: `roblox-experience-launcher`。アカウント・入口・シナリオ・期待結果を渡す。未指定なら呼ばない。
- 既存取引の確認が依頼された場合だけ: `roblox-purchase-revenue-check`。商品設定担当にしない。売上がまだない初回公開を失敗扱いしない。

`publish-roblox-private-staging` は本番変更禁止。名前やパラメータを変えて本番公開担当に転用しない。

## 実行順序

1. 対象・変更許可・早期ゲート・現在状態を確定。再開は古い記録より現在の外部状態を優先し、重複作成や別PCの変更を回避する。前回の一般公開が既に保存済みならID・版・設定を再照合し、依頼済みの公開完了として扱う。非公開工程を再実行するために勝手にPrivateへ戻さない。
2. 必要な場合だけ非公開本番Experience／Placeを作成。商品登録に先行公開が必要なら、購入導線を無効にした初期版を非公開で登録する。これは完成版公開とは別に記録する。
3. 商品を照合／登録しIDを確定。許可されたソースへ環境ID・商品IDと必要な設定を反映。付与経路を確認し、販売開始は完成版の付与処理と公開確認後まで保留する。
4. 全Placeの翻訳対象を確定。固定／動的／条件付きUI、Tutorial、エラー、購入、Result、Experience情報、商品文言を含める。名前・ID・入力を除外し、画像内文字を別扱いにする。原文混在を解消してから登録。既存手動翻訳とロックを保護する。
5. 最終ソース・設定・商品IDで全Placeをビルド／テストし、SHA-256を固定。子Placeを先に入口を最後に公開。各版を独立確認。一部失敗なら入口更新を止め、混在版・互換性・再開地点を残す。
6. 設定保存、商品連携、原文登録、生成状態を再読取。生成待ちや割当不足は未完了として分離し、無限待機しない。販売／外部掲載が依頼されている場合は、それぞれ必要条件を確認してから適用する。
7. 依頼された検証だけ実行。公開ゲートと任意改善を分けて判定し、未実施の実機・課金・権利確認を成功扱いしない。
8. 一般公開が明示された場合だけ、現在の資格・適用質問票・アセット・完成版・販売のゲートを再確認し、正確なUniverseのAudienceを変更、保存後再読取する。必要な操作時確認は省略しない。承認済みでもゲート未解決なら公開を止める。

翻訳登録等、依存しない工程は先行できる。全件を形式的に直列化せず、同一設定の競合変更は並行しない。

## 検証・再開・終了

[references/release-evidence.md](references/release-evidence.md) の完了区分、再試行、復旧、模擬ケースを使う。必要なときは `scripts/audit_release.py --manifest <絶対パス> --stage preflight|root|finish|public` でローカル記録の整合を検査する。これは読み取り専用の補助で、クラウド操作や実機の証明ではない。

最終報告: 対象ID／リンク、全Placeの版／ハッシュ、設定・アップロード、翻訳生成、実機受入、一般公開を別判定、未解決と再開地点。完了は依頼された範囲の終点と証拠がそろった時だけ。成功済みのPlaceだけで全体完了にしない。

## 現行仕様の確認先

- [Publishing requirements](https://create.roblox.com/docs/production/publishing/publish-games-and-places)
- [Developer Products](https://create.roblox.com/docs/production/monetization/developer-products)
- [Passes](https://create.roblox.com/docs/production/monetization/passes)
- [Automatic translation](https://create.roblox.com/docs/production/localization/automatic-translations)
