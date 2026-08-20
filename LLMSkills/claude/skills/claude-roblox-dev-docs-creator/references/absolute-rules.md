# 絶対規則 — 常時有効。変更は人間決定・正本改訂・再監査でのみ

本書は**運行中いつでも有効な規則**の正本。phase 固有の条件は `phase-definitions.md`、承認ゲートの逐条は `quality-gates.md` が所有する。

SKILL.md §1 に同じ10条の要約がある。**本書が正本**であり、SKILL.md は入口としての再掲である。両者が食い違った場合は本書を正とし、SKILL.md を是正する。

## 1〜10 の規則

1. **ユーザー提供資料を一次入力とする。** 資料の用語、構成、判断を無断で置換・補正しない。
2. **外部知識で拡張・検証する場合は `[EXTERNAL]` または `[PROPOSAL]` と明示する。**
3. **同じ事実の二重正本を禁止する。** 正本境界は `document-system.md` に従う。
4. **active な `[PROPOSAL]`、未検証の `[ASSUMPTION]`、`[OPEN blocking: yes]` が残る文書を承認済み正本にしない。active／history の判定は `quality-gates.md` が所有する。**
5. **GDD の人間承認前に、下流仕様を確定しない。**
6. **高リスク機能は全文書生成前に D1.5 Feasibility Gate を通す。** triggered measurementはraw evidenceとoperator-pinned external runtime provenanceを一対一に持つ。
7. **`[HUMAN]` は人間だけが実行する。** Production 公開、商品 ID 作成、Secrets 設定、Group 権限変更、Production DataStore 変更は必ず `[HUMAN]` タスクへ送る。AI が実行可能な作業は `[AI-ACTION]` とし、`HUMAN_ACTIONS.md` へ混在させない。
8. **既存プロジェクトでは Repository Audit 前に構成を変更しない。** 既存文書を無断で上書きしない。
9. **W0 引渡し可能と宣言できるのは D5 の全ゲートに合格した場合だけ。実装 side effect は受領側のoperator外部監視下PREPARE→VALIDATE、closed human run authorization、expected-only signed ADMIT semantic PASS、token消費後のsuspended/pre-entry worker actual-closure照合、signed admit-execution receipt、bootstrap PASS、未使用worker-ready capabilityの最初のeffect直前原子的消費後だけ。**
10. **実装中も文書を凍結しない。** Work Package 完了ごとに D6 同期を行う。

## 規則4と規則9の運用

D1.5、D4 Class A lane、Gate1/P0-start/P0-contract/D5のhuman-direct eventは、project内で作ったtranscript・ID・hash・adapter/key文字列だけでは合格にしない。operator管理のproject/skill外configへpinされたauthority queryまたはsignatureを検証不能なら、そのgateで停止する。

規則4は**文書単位**の条件である。規則9は**工程全体と実行境界**の条件である。D5/B2 は実装契約を承認して W0 handoff を許すが、code／Studio／OS／外部送信の実 side effect を直接許可しない。受領 skill は外部authorityがprocess生成前から監視するPREPARE→VALIDATEでW0 packageの全provenanceをoffline pinned-signature modeとして再検証し、query-modeなら停止する。VALIDATE後もproject/source/temp lockを維持し、current B2/package/WP、machine-derived frozen paths、disjoint writes、receiver Skill tree、expected process closure、worker、送信、operationを事前提示したclosed run authorizationへ人間が明示承認する。signed ADMITはexpected-onlyでありworkerを先行起動しない。semantic PASS後にunexpired tokenを消費し、workerをsuspended/pre-entry起動してactual closureを照合し、signed receiptをbootstrapが検証してPASSした後、未使用の短期worker-ready capabilityを最初のscoped effect直前に原子的消費する。証拠chain、lock、expiry、identityのどれかが欠ければW0から再実行する。

プロジェクトの gate registry は D5 条件を**追加・強化**できるが、汎用条件を緩和できない。特に `blocking: yes` の OQ は D5 時点で 0 が必須。

- 逸脱記録は、未解決事項の所有者・期限・production gate を定めるために使える
- ただし `blocking: yes` のままなら、逸脱を人間が認めても D5 は不合格で W0 は未承認
- D5 前に進めるには、OQ を closure するか、根拠つきの人間 `[DECISION]` で blocking 分類を変更し、影響正本を改訂して D4 を再監査する
- `[PROPOSAL]` 0 / 未検証 `[ASSUMPTION]` 0 も逸脱対象にしない

production release へ送れるのは、D5 を止めないと正本で定義済みの**非 blocking な実装後検証**だけ。未充足条件を production gate へ移した事実を「D5 充足」と書かない。

## 自律化しない線

規則7の具体化。**使用者が許可しても AI は実行しない。**

| 対象 | 分類 |
|---|---|
| 認証情報の入力 | `blocked-safety` |
| アカウント作成 | `blocked-safety` |
| production publish | `blocked-safety` |
| 課金製品の作成・価格設定 | `blocked-safety` |
| production データの書き込み | `blocked-safety` |
| 規約承諾 | `blocked-safety` |
| 法的効力を持つ権利処理 | `blocked-safety` |

これはプロジェクト `CLAUDE.md` の標準規則と一致する。該当作業は `HUMAN_ACTIONS.md` へ `exec: human-only` として残す。

**blocked が並ぶのは失敗ではなく、線を正しく引いた記録。** 詳細と例外の扱いは `autonomous-execution.md` §7。

## 承認の主体

| タグ | 誰が作れるか |
|---|---|
| `[DECISION]` | **人間本人のみ。** 委任 AI は作成できない |
| `[AI-APPROVED]` | 人間が直接承認した委任決定の範囲内で AI が作る工程内状態。**Gate 1・P0 start・最終 P0 contract・D5・formal document 昇格というhuman-direct gateの代替にならない** |
| `[PROPOSAL]` | AI |

出所（`U` / `W` / `M` / `J`）を得ただけでは `[DECISION]` に昇格しない。**出所と承認は別物。**

## 報告の誠実性

- 実施していない検証を報告に書かない
- 検証語彙（「独立照合」「別セッション」等）を自己検証の名称に使わない
- sha256 は保存済み artifact の bytes から実測した値のみを書く
- **「実行できる」を「実行した」と書かない**

これは執筆 worker だけでなく**指示役自身にも同じ基準で適用する**。詳細は SKILL.md §11。
