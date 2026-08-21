---
name: roblox-development-architect
description: Generate, audit, and maintain a production-ready document system for AI-assisted Roblox game development. Use for new Roblox game documentation, GDD体系, AI開発用設計書一式, document-driven development preparation, implementation-ready specifications, existing Roblox project document augmentation, repository readiness audits, Claude Code handoff, testing, release, rollback, or live-operations documentation.
argument-hint: "[新規コンセプト、既存プロジェクト、または監査対象]"
---

# Roblox Development Architect

このSkillは、Robloxゲームを「企画書がある」状態から、AIが安全にWork Package単位で実装を始められる状態へ変換する。成果物の長さではなく、正本境界、トレーサビリティ、実行可能テスト、セキュリティ、保存、性能、公開・復旧の完備性を優先する。

## 0. 絶対規則

1. ユーザー提供資料を一次入力とする。資料の用語、構成、判断を無断で置換・補正しない。
2. 外部知識で拡張・検証する場合は、`[EXTERNAL]` または `[PROPOSAL]` と明示する。
3. 同じ事実の二重正本を禁止する。正本境界は `references/document-system.md` に従う。
4. `[PROPOSAL]`、未検証の `[ASSUMPTION]`、ブロッキング `[OPEN]` が残る文書を承認済み正本にしない。
5. GDDの人間承認前に、下流仕様を確定しない。
6. 高リスク機能は全文書生成前にD1.5 Feasibility Gateを通す。
7. `[HUMAN]` は人間だけが実行する。Production公開、商品ID作成、Secrets設定、Group権限変更、Production DataStore変更は必ず `[HUMAN]` タスクへ送る。AIが実行可能な作業は `[AI-ACTION]` とし、`HUMAN_ACTIONS.md` へ混在させない。
8. 既存プロジェクトでは、Repository Audit前に構成を変更しない。既存文書を無断で上書きしない。
9. 実装開始可能と宣言できるのはD5の全ゲートに合格した場合だけ。
10. 実装中も文書を凍結しない。Work Package完了ごとにD6同期を行う。

## 1. 最初にモードを判定

- **GREENFIELD**: 新規ゲーム。コンセプトから文書体系を作る。
- **BROWNFIELD**: 既存ゲーム／既存リポジトリへ文書や機能を増補する。
- **AUDIT**: 既存文書体系がAI実装可能か監査する。
- **SUB-SPEC**: 承認済み体系へ領域特化仕様書だけ追加する。

不明なら質問する。ユーザーが既存ファイルを示した場合はBROWNFIELDまたはAUDITを優先する。

## 2. 必要時だけ読む補助資料

- 文書体系と正本境界: `references/document-system.md`
- D0〜D7の詳細: `references/workflow.md`
- 機能→必須仕様書: `references/trigger-matrix.md`
- サブエージェント配分: `references/agent-routing.md`
- 品質・承認ゲート: `references/quality-gates.md`
- 状態タグ、決定、変更伝播: `references/source-of-truth.md`
- Roblox固有完備性: `references/roblox-readiness.md`
- 既存リポジトリ監査: `references/repository-audit.md`
- 出力配置・命名: `references/output-layout.md`

詳細を推測せず、該当資料を読んでから進める。

## 3. D0 — コンセプト／技術ヒアリング

D0ではサブエージェントを起動しない。ユーザーへ、製品質問と技術質問をまとめて提示する。既に回答済みの項目は再質問しない。

### D0-A 製品質問

1. 一言コンセプトと一動詞
2. 参照ゲーム2〜3本、取る点／捨てる点
3. 独自軸3点以内
4. 1ラウンド／1セッション時間
5. キャラ・機体・クラス等の枠とカスタムスロット
6. ラン内ループ、メタループ、収集対象
7. 収益方針、P2W、RNG、Trading
8. IP・実在物・政治・史実リスク
9. 最大の操作・物理・ネットワーク・供給リスク
10. MVPで検証する問い3つ
11. 端末優先度、モバイル操作予算、最低性能
12. Non-Goals候補

### D0-B 技術・運用質問

1. Greenfieldか既存リポジトリか
2. Studio中心、Rojo、その他のToolchain
3. Universe／Place構成
4. Group所有、dev／staging／productionの分離
5. 対応端末、最低FPS・Memory目標
6. 永続化するデータ
7. PvP、通貨、取引、課金、ランダム報酬
8. Teleport、Reserved Server、Matchmaking
9. 外部API、Open Cloud、Secrets
10. UI、入力、Localization、Accessibility
11. 既存アセットと権利状態
12. 人間しか行えないDashboard／Studio作業
13. Release頻度、LiveOps
14. 障害時の停止・Rollback要件
15. 既存コード・文書・テストの信頼度

未回答には `[PROPOSAL]` を付けた提案値を出し、確認を得る。確認後に `intake.json` へ `[DECISION]` として固定する。

## 4. BROWNFIELD追加手順

既存プロジェクトではD1の前にRepository Auditを行う。

1. Repository tree、Place mapping、依存関係、Build/Testコマンドを確認する。
2. 既存CLAUDE.md、設計書、Config、Remote、DataStore、Commerce、Analyticsを棚卸しする。
3. 事実・推測・欠落を分離する。
4. Legacy名、宙に浮いた参照、Production接触経路を記録する。
5. `repository_audit.md` とGap Mapを人間へ提示する。
6. 増補範囲を承認されるまで既存正本を変更しない。

## 5. D1 — GDD生成と人間承認ゲート①

選定した worker に named role `product-gdd-writer` を明示的に割り当て、D0回答とGDDテンプレートを渡す。named role は固定プラグイン名ではなく、選定 worker が delegation packet に従って assume する責務名である。執筆 worker を確保できない場合は blocker として停止し、本コンテキストを正本執筆の fallback にしない。

必須条件:

- 一言、対象、Visceral Core、一動詞
- 取捨表、独自軸、コアループ、メタループ
- MVPと将来機能の境界
- Non-Goals 6件以上、理由つき
- D-n／F-n、切替条件、決定権者
- 測定可能な成功指標。ただし数値正本はデータ定義書へ参照化
- OQとブロッキング有無
- 収益・権利・年齢表現の方針

GDDを提示し、明示的な承認を得る。承認前にD2へ進まない。

## 6. D1.5 — Feasibility Gate

次のいずれかを含む場合は、設計文書一式より先に小さな技術検証を作る。

- 新規モバイル騎乗・飛行・船舶操作
- 大量破壊、大量NPC、大規模物理同期
- EditableImage、自由描画UGC、4D生成
- 複数乗員Vehicle、複雑なNetwork Ownership
- 高頻度Projectile、サーバー権威の高速PvP
- 未検証のMulti-Place／Teleport構成

Feasibility Reportには、仮説、最小実装、測定条件、端末、合格閾値、結果、D/F判断を記す。不合格なら上流GDDを改訂し、再承認する。失敗した前提のまま下流文書を量産しない。

## 7. D2 — 技術体系生成

承認済みGDD、Repository Audit、Feasibility結果を入力にする。独立可能な領域は並行化してよい。

- 選定 worker が `system-architect` を assume: 詳細設計、モジュール境界、依存方向、Place topology
- 選定 worker が `data-economy-writer` を assume: 数値、経済、Config、検算表
- 選定 worker が `ui-input-writer` を assume: UI、画面遷移、入力、端末、Accessibility
- 選定 worker が `platform-security-writer` を assume: Remote、権威、保存、課金、Policy、Analytics基盤

`references/trigger-matrix.md` を必ず適用し、該当補助仕様書を生成する。条件を満たした仕様書を「任意」として省略しない。

文章だけでなく、該当する機械可読契約を作る:

- Remote schema
- Save schema／Migration table
- Analytics event dictionary
- Asset ledger
- Commerce ledger
- Document manifest

## 8. D3 — 実装・テスト・運用文書

選定 worker に named role `dev-process-writer` を明示的に割り当て、D1〜D2全文書を渡して次を生成する。

1. 実装フェーズ計画
2. Work Package仕様
3. テスト仕様
4. Toolchain／Repository仕様
5. CLAUDE.md
6. WORKFLOW.md
7. Release／Rollback Runbook
8. PROGRESS.md
9. ASSET_TODO.md
10. HUMAN_ACTIONS.md
11. AI_ACTIONS.md
12. CHANGELOG.md
13. DECISIONS.md
14. Traceability Matrix
15. 設計フィードバックリスト

各Work Packageは1セッションで完了可能な大きさにし、対象ファイル、変更禁止範囲、入力、出力、公開Interface、自動テスト、Studio検証、性能確認、Rollback、Done条件を持たせる。

設計フィードバックは該当執筆者へ戻す。同一問題カテゴリの2回目、または承認済み製品方針を変える問題は人間へエスカレーションする。別カテゴリの新問題は、承認範囲内なら追加修正できる。

## 9. D4 — 3系統監査

監査者は修正しない。指摘を元執筆者へ差し戻す。

1. 独立した選定 worker が `consistency-auditor` を assume: 二重正本、参照切れ、矛盾、未解決状態、変更伝播
2. 独立した選定 worker が `roblox-readiness-auditor` を assume: Remote、保存、性能、UI/Input、課金、Policy、権利、公開、安全
3. 独立した選定 worker が `clean-room-auditor` を assume: 過去会話を知らないAIが最初のWork Packageを開始できるか

重大指摘ゼロまで再監査する。軽微修正も変更履歴へ記録する。

## 10. D5 — 人間承認ゲート②

P0 contracts/bootstrap を使うプロジェクトでは、D4合格後にP0を実行し、その結果をD5の入力にする。P0はD5の前提工程であり、P0内の承認や `[AI-APPROVED]` はD5承認そのものではない。P0はformal documentの `Status`／`Last approved` を変更しない。

次をすべて満たしたときだけ「実装開始可能」とする。

- ブロッキングOQ 0
- `[PROPOSAL]` 0、未検証 `[ASSUMPTION]` 0
- 要件トレース率100%
- Required Spec欠落0
- Remote／Save／Commerce／Analytics未定義0
- Work Package未テスト0
- Human owner不明0
- Build／Test／Serveコマンド確定
- Clean-room監査合格
- Release／Rollback確定
- 最初のWork Packageが即開始可能

ユーザーへ、生成ファイル、主要判断、P0結果（適用時）、残るHuman Actions、最初のWork Packageを提示し、**人間本人から直接の明示承認**を得る。委任AIの `[AI-APPROVED]`、過去の包括委任、無応答はD5を満たさない。

直接承認を得た同じ変更単位で、対象formal documentの `Status: Approved`、`Last approved`、change history、`DECISIONS.md` を同期し、docs index／manifestを再生成する。このD5遷移より前にformal documentをApprovedへ昇格させない。

## 11. D6 — 実装Bootstrapと継続同期

承認後、ユーザーが実装開始を依頼した場合のみ実行する。

1. 一度に1 Work Packageだけ着手する。
2. 変更前に対象ファイルと禁止範囲を再確認する。
3. Test-firstまたは契約-firstで実装する。
4. 完了時にコード、テスト、PROGRESS、CHANGELOG、Traceability、影響仕様書を同時更新する。
5. Last Known Good Commitを記録する。
6. WP外の改善を発見しても実装せず、DECISIONS／Backlogへ記録する。
7. Production公開やDashboard操作はHUMAN_ACTIONSへ送る。

## 12. D7 — 補助仕様・変更要求

承認済み体系への追加は、選定 worker に named role `sub-spec-writer` を明示的に割り当てる。

1. Change Requestを作る。
2. 影響文書一覧を出す。
3. 暫定正本が必要なら期限・取込先を宣言する。
4. 上流正本へ取り込んだ後、暫定節を取込済み記録へ変える。
5. 影響するテスト、Work Package、Traceabilityを更新する。
6. D4監査を再実行する。

## 13. 状態タグ

- `[FACT]`: 入力資料、コード、公式仕様で確認済み
- `[DECISION]`: 人間本人が直接承認済み。委任AIは作成できない
- `[AI-APPROVED]`: 人間が直接承認した委任決定の範囲内でAIが承認したP0等の工程内状態。人間承認、Gate 1、D5、formal document昇格の代替ではない
- `[PROPOSAL]`: AI提案、未承認
- `[ASSUMPTION]`: 検証前提
- `[OPEN]`: 未解決。`blocking: yes/no` を併記
- `[HUMAN]`: 人間だけが実行可能。AI実行候補へ付けない
- `[AI-ACTION]`: AIが現在の権限・能力・承認範囲内で実行可能な作業。`AI_ACTIONS.md`でauthority・input hash・evidence・cleanupを追跡し、`HUMAN_ACTIONS.md`へ混在させない
- `[EXTERNAL]`: 外部情報・外部サービス依存

## 14. 検証スクリプト

必要に応じて実行する。スクリプトは標準Pythonのみを使い、元ファイルを破壊しない。

```powershell
$architectSkillDir = (Resolve-Path -LiteralPath '${CLAUDE_SKILL_DIR}').Path
if (Get-Command python -ErrorAction SilentlyContinue) { $pythonExe='python'; $pythonPrefix=@() }
elseif (Get-Command py -ErrorAction SilentlyContinue) { $pythonExe='py'; $pythonPrefix=@('-3') }
else { throw 'Python interpreter not found' }
foreach ($script in @('scaffold_project.py','detect_triggers.py','validate_docs.py','validate_traceability.py','grep_residuals.py')) {
    $scriptPath = Join-Path $architectSkillDir "scripts\$script"
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "missing script: $scriptPath" }
    & $pythonExe @pythonPrefix $scriptPath --help
    if ($LASTEXITCODE -ne 0) { throw "script probe failed: $scriptPath" }
}
```

`${CLAUDE_SKILL_DIR}`はSKILL本文へ展開される値であり、OS環境変数ではない。supporting referenceでは展開されないため、上で得た`$architectSkillDir`を明示的に渡す。

複雑な変更では `analyze → plan file → validate → execute → verify` の順を守る。

## 15. 各Phaseの報告

各Phase完了時に、次を1段落で報告する。

- 作成・改訂ファイル
- 確定した重要判断
- 発動したTrigger Spec
- 重大リスクとD/F
- Human Action
- 次の承認または次のPhase

行数は参考情報に留め、品質合格の根拠にはしない。
