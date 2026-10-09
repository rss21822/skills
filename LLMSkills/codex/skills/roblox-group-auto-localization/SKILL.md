---
name: roblox-group-auto-localization
description: >
  指定Robloxグループが所有するExperienceの自動翻訳を、対象確認・対応言語設定・
  原文登録・プレイヤー別表示確認まで一気通貫で行う。グループ内ゲームの多言語化、
  全対応言語への自動翻訳設定、日本語などで表示されない問題の調査に使う。
---

# Roblox Group Auto Localization

グループは対象ゲームを選ぶ単位。翻訳設定・クラウド翻訳テーブルはExperience（Universe）ごとに処理する。グループ全体へ一度適用すれば済むと扱わない。

## 対象と権限

- グループID/URL、対象Experience、対象の本番・Staging、原文言語、ローカルソースの所在を確認する。必要な情報だけ質問する。
- 「グループ全ゲーム」と明示された場合は、所有ゲームをページ末尾まで列挙し、その時点の対象一覧を固定する。曖昧な場合は対象ゲームを選んでもらう。新規ゲームや別グループを勝手に追加しない。
- ログイン済みアカウントとグループ所有関係を画面または公式サービスで確認し、Universe ID・root Place ID・子Placeを区別して記録する。SpinOutなど過去のIDを流用しない。
- 設定の実行依頼なら、通常の翻訳設定・追加原文登録は対象内で進める。Skill作成、調査のみの依頼は設定変更の許可ではない。
- 公開範囲、グループロール、認証、課金枠購入、Placeアップロードは別操作。必要な権限がない場合は権限付与を勝手に行わず、そのゲームだけ未完了として記録する。

## 実行

1. 公式ドキュメントと現在のCreator Dashboardで対応言語・設定名・割当を確認する。過去の17言語などの件数を固定しない。
2. 各Experienceの変更前設定を記録する。原文言語は実際のUIに合わせ、英語へ自動変更しない。原文言語と実装が不一致なら、翻訳生成前に解決方針を確認する。
3. 対象言語の自動翻訳を有効化する。「全対応言語」なら現在対応する原文以外の言語全部。Experience Strings & ProductsとExperience Informationの両方、Use Translated Content、Automatic Text Captureを確認する。既存の手動翻訳・ロック・削除設定は保護する。自動クリーンアップは依頼がなければ維持し、原文登録で削除を発生させない。
4. UI原文を登録する。操作・再試行の詳細は[references/registration-and-verification.md](references/registration-and-verification.md)を読む。既存の原文一覧、ソース、Studio captureを組み合わせ、既に英語だった文言・動的通知・子Place固有UIも対象にする。コード編集を伴う場合のみ、利用可能なRoblox開発Skillを読む。
5. プレイヤー別の表示経路を確認する。ネイティブUIはAutoLocalizeと翻訳テーブルの参照を調査。スクリプト翻訳はクライアントでGetTranslatorForPlayerAsync / FormatByKey等を確認し、サーバーで全員へ同一の翻訳済み文字列を送っていないか調べる。名前・ID・ユーザー入力は原則翻訳しない。必要な修正だけ行い、設定だけで直る場合はPlace再公開しない。
6. 保存した設定と原文登録を再読取し、翻訳生成状態を確認する。割当不足・サービス障害なら無限再試行せず、原因・再開地点を記録する。進捗確認は間隔を空け、数日かかるATCを同一ターンで待ち続けない。
7. 公開済みPlayerの新しいセッションで、利用可能な非原文言語を最低1つ確認する。全対応言語を実機確認したとは言わない。アカウント切替・言語変更が必要ならユーザーに依頼する。現在テスト中の試合を勝手に終了しない。設定のみ、実機スキップの明示は尊重する。

## 完了記録

Experienceごとに、対象ID、原文言語、設定済み言語、追加原文件数、既存翻訳保護、生成率、実機のアカウント言語・画面・結果、未確認事項を保存する。スクリーンショットと現在時点の証拠を添える。

「設定完了」「生成完了」「新セッション表示確認」を別々に判定する。100%は登録された文言の生成率であり、全UI網羅・翻訳品質・全言語実機検証の証明ではない。未完了ゲームを隠してグループ全体完了としない。

## 公式資料

- [Automatic translation](https://create.roblox.com/docs/production/localization/automatic-translations)
- [Add translations](https://create.roblox.com/docs/production/localization/add-translations)
- [Dynamic content](https://create.roblox.com/docs/production/localization/translate-dynamic-content)
- [Scripting localization](https://create.roblox.com/docs/production/localization/localize-with-scripting)
