# 公式情報の確認先

作成時確認日：2026-09-17。下記は同日に本文の関連箇所を確認した入口であり、未来の現行仕様を保証する固定ナレッジではない。実行時に重要なページを再取得し、URL・取得日・対象範囲をresearch.jsonへ記録する。閲覧失敗なら未検証とし、旧情報を現行として使わない。

この一覧は市場調査を実施した証拠ではない。調査案件ごとの `S` と `P` は、実際に読んだものだけを登録する。

| ID | 公式資料・URL | 確認する範囲 |
|---|---|---|
| R00 | OpenAI, Build skills — https://developers.openai.com/codex/skills/ （確認時転送先 https://learn.chatgpt.com/docs/build-skills ） | SKILL.md、name/description、.agents/skills、明示起動、agents/openai.yaml |
| R01 | Roblox, Discovery — https://create.roblox.com/docs/discovery | 推薦の対象、指標と期間、流入、ベンチマーク、メタデータ。古い /docs/production/discovery を前提にしない |
| R02 | Roblox, Optimizing Discovery — https://about.roblox.com/newsroom/2026/06/optimizing-discovery-great-games-reach-millions-players-roblox | 2026-06-15発表。過去の7日視点から28日視点への変更を説明する履歴。現在の詳細はR01で再確認 |
| R03 | Analytics dashboard — https://create.roblox.com/docs/production/analytics/analytics-dashboard | アクセス権、指標、比較集合、エクスポート、集計条件 |
| R04 | Acquisition — https://create.roblox.com/docs/production/analytics/acquisition | 流入別の獲得・帰属・リンク。別画面の同名KPIとの定義一致 |
| R05 | Retention — https://create.roblox.com/docs/production/analytics/retention | 新規コホート、D1/D7/D30、未成熟データ |
| R06 | Engagement — https://create.roblox.com/docs/production/analytics/engagement | セッション、初回体験、繰り返し遊ぶ価値、端末性能 |
| R07 | Funnel events — https://create.roblox.com/docs/production/analytics/funnel-events | 一回・反復ファネル、送信条件、計測の一貫性・検証 |
| R08 | Custom events — https://create.roblox.com/docs/production/analytics/custom-events | ゲーム固有イベント、集約、送信条件、フィールド・制限 |
| R09 | Monetization analytics — https://create.roblox.com/docs/production/analytics/monetization | 売上範囲、課金率、ARPPU、ARPDAU、閲覧権限 |
| R10 | Passes — https://create.roblox.com/docs/production/monetization/passes | 一度の購入での特典、Developer Productとの区別。関連する販売方式は文中リンクから確認 |
| R11 | Paid random items policy guidelines — https://create.roblox.com/docs/production/monetization/paid-random-items | 有料・間接購入の条件、開示、ユーザー別制限と取引 |
| R12 | Teleport between places — https://create.roblox.com/docs/projects/teleport | Place間移動、サーバー・権限・アクセス、実クライアントでの確認条件 |
| R13 | Design for performance — https://create.roblox.com/docs/performance-optimization/design | 対象の低性能端末、メモリ・描画負荷、開発中の性能検証 |
| R14 | Regional pricing — https://create.roblox.com/docs/production/monetization/regional-pricing | 地域別の価格、観測価格の条件、動的表示、ギフト・取引の考慮 |

## 実行時に追加確認するもの

API・機能が判断に必要な場合だけ、Creator Hubの現在の索引とリンクから、該当する公式リファレンスを確認する。
例：Paid Access、Developer Products、Subscriptions、Private Servers、Creator Rewards、Ads Manager、コミュニケーション・年齢条件、権利とCommunity Standards、MarketplaceとCreator Store、ローカライズ、保存・マッチング・不正対策。
未閲覧の上記項目を「確認済み」として登録しない。最新の公表値、DevEx等の条件・料率、特定アカウントの利用資格は、この一覧から推測しない。

## 根拠としての使い分け

公式機能の存在は、競合が使用している証拠ではない。公式の推奨は、今回の企画で効果が実測された証拠ではない。
特定ゲームの事実はそのゲームの公式ページ・制作者・実際の観察で調べる。ユーザーの声は原投稿、第三者統計は提供元の方法と時点を確認する。
