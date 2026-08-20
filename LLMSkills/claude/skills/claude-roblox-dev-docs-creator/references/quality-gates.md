# 承認ゲート・状態タグ・変更伝播

本書は3つを単独所有する。

1. **各ゲートの逐条条件**（Gate 1〜5）
2. **状態タグの定義**（`[FACT]` / `[DECISION]` / `[AI-APPROVED]` 等）
3. **変更伝播の順序**

phase の定義そのものは `phase-definitions.md`、handoff の常設条項は SKILL.md §8 が所有する。**それらは本書のタグ定義を参照するだけで、再定義しない。**

---

## 第1部 — 承認ゲート

### Gate 1 — GDD approval

- 製品ステートメントと一動詞が曖昧でない
- 対象プレイヤーと価値が具体的
- 参照ゲームに取捨表がある
- MVP 境界が明示されている
- Non-Goals 6件以上、理由つき
- D/F ペアが最大リスクを覆っている
- 成功指標が測定可能
- 収益・RNG・P2W・IP・maturity 方針が決まっている
- ブロッキング製品 OQ が 0

Gate 1 はapproved intake、そこから再導出したrequired specs、exact Draft GDD path/hash/revisionを同じclosed scopeでD1.5 / D2入力として承認するhuman-direct工程 gate。closed challenge → trusted presentation/response transcriptとexact statement → human capture → external query/signature `provenance_verification` → type `gdd-gate1` machine recordの順で固定し、record `sourceEvidence`をcapture、`sourceVerification`をその外部proofへ束縛する。required specs bytesはintakeから再生成して一致させる。project内のlocal transcript/ID/hashだけではhuman-directと数えない。`DECISIONS.md` の同一ID記録と全fieldが一致しても、formal header はB1まで `Status: Draft` のままbyte-immutable。`Approved` / `Last approved` / exact historyはGate 5 external verification後のfixed metadata-only transformationだけが設定し、normalized body digestを変えない。

### Feasibility gate（D1.5）

- required specsの`feasibility_report` triggerが無ければbinding 0件、あれば`feasibility_report-combined-v1` bindingがexactly 1件。approved intakeから導出したsorted required-subcheck ID/hash setをcombined suiteが重複・欠落・余分0でexact-coverし、全件を実測している
- priority device 固有の仮説は実機で計測している。実機不足なら `INCONCLUSIVE`
- 端末固有差へ依存しない仮説だけ、計測前に固定した代替環境と適用範囲で限定 PASS 可。実機 PASS と表現しない
- evidence が保存されている
- evidenceのrequest/command/raw output/pre-fixed thresholdを実bytesからrehashし、trigger/experiment/resultとexternal provenance claimsがexact一致する
- **合格・不合格の規則が計測前に設定されている**
- 不合格が、文書化された fallback を発動させるか、プロジェクトを止める

### Gate 2 — Architecture completeness

- モジュール所有と依存方向が定義されている
- サーバー権威マトリクスが定義されている
- 全 Trigger Spec が生成されている
- 該当箇所に空でない機械可読 contract instance が存在し、対応 JSON Schema で warning / note なしに検証済み
- 二重正本が無い
- 全要件が design 参照を持つ

### Gate 3 — Implementation planning

- 全 Phase に entry / exit 条件がある
- 全 WP が1セッションに収まる
- file scope と do-not-touch scope がある
- テストと evidence が名指しされている
- rollback がある
- human-only 作業に owner と due gate がある

### Gate 4 — Audit（D4）

次の3系統すべてで **Critical = 0 かつ Major = 0**。

- consistency
- Roblox readiness
- clean-room handoff

**1系統だけでは全体の Critical 0 / Major 0 や合格を宣言しない。** 実行手順は `audit-d4.md`。

初回 D4 の B0 候補には、canonical operating file `PROGRESS.md` § Proposed P0 closure inventory に列挙された `[PROPOSAL]` / `[OPEN blocking: yes]` / 未検証 `[ASSUMPTION]` だけ残してよい。各項目は source ID/path、正確に境界づけた P0 closure question/scope、owner、closure evidence/pass rule、影響正本を持ち、P0 開始承認後に現在の文書・実測だけで閉じられなければならない。Gate 1 承認済み intake/GDD の変更を要求する項目は inventory へ入れず D0/D1へ戻す。未登録、所有者不明、W0 実装後でないと閉じない項目、P0 scope 外の未決は Major 以上。D4 合格は内容承認ではなく P0 着手資格判定であり、代替案は P0 の CR 起草で作る。

post-P0 D4 では `[PROPOSAL]` / `[OPEN blocking: yes]` / 未検証 `[ASSUMPTION]` は 0 必須。さらに B0 historical inventory の全 ID が P0-CAND `PROGRESS.md` の Completed record、actual closure evidence、影響正本の post-change hash へ一対一で解決されていなければ B1 へ昇格しない。

### Gate 5 — W0 handoff ready（D5）

- **人間本人の直接・明示の D5 承認が、closed challenge／trusted transcript／exact statement／human capture／external query/signature provenance／machine gate recordの検証可能な鎖で記録されている。** `[AI-APPROVED]` は代替にならない
- GDD Gate 1、B0を対象とする人間P0開始承認、planned candidate ID／承認前normalized digest／B0 `sourceBaselineRevision`を対象とする**人間direct P0契約承認**と、その後一度だけfreezeしたactual `P0-CAND-n`へ結ぶmachine record、B1を対象とするD5が別々のrecord/capture/provenanceで記録され、4 gate ID・challenge/capture/provenance・interaction/message・statementが相互distinct。人間へ未来candidate hash/revisionを要求しない。委任 `[AI-APPROVED]` はP0個別選択に限り、最終 `p0-contract` recordを作れない
- P0 core、post-P0 D4、B1 昇格までの P0 route が完了し、**D5 そのものではなく前提**として記録されている
- P0 lifecycle transition attestation／外部provenanceが、B0と一致する監視開始状態、canonical target全域、P0-start verification後の全pre-approval write、payload作成、P0-contract verification後の固定metadata、snapshot全file freeze、actual-candidate machine record、exact frozen-byte apply、final seal、未記録書込み0、seal後書込み0、P0-CAND結果をauthority側actual eventsで証明している
- D5 承認対象 B1 が、B0→`P0-CAND-n` の3系統差分再監査すべてで Critical 0 / Major 0 の合格 candidate と同一 file-set hash である
- ブロッキング OQ = 0
- 未承認 proposal = 0
- 未検証 assumption = 0
- triggered machine-readable contract instance の active recordに `proposed` status = 0（Remote / Save / Analytics / Commerce は `approved` または明示的な非active履歴状態）
- traceability = 100%
- required files = 100%
- build / test / serve コマンドが確定
- release / rollback が確定
- 最初の WP が新たな製品・契約判断なしに W0 へ引き渡せる。実 side effect は受領側のexternally monitored PREPARE→VALIDATE、closed human run authorization、expected-only signed ADMIT semantic PASS、admission token消費後のsuspended/pre-entry actual-closure signed receipt、bootstrap PASS、worker-ready capabilityの原子的消費後だけ
- formal document の Status・Last approved・change history・decision log・docs index・manifest が、**その人間承認の後にだけ**同期された。GDDの変更はGate1-approved B1 Draft bytesへのfixed metadata-only transformationで、normalized body digestは同一
- D5 lifecycle transition attestation／外部provenanceが、B1と一致する監視開始状態、同期対象全域、D5 verification後の全actual sync event、allowed-diff/post-sync生成、snapshot-only B2全file copy、未記録書込み0、exact allowlist diff、final sealとseal後書込み0、B2結果を証明している

プロジェクト側 gate registry は条件の追加・強化だけ可能。`blocking: yes` の OQ への逸脱記録は Gate 5 を満たさず、0になるまで W0 を authorization しない。詳細は `phase-definitions.md` §9。

### 品質ゲートに使ってはいけないもの

- 総行数
- 文書数だけ
- 「網羅的に見える」
- モデルの確信度
- 検証なしの生成成功

---

## 第2部 — 状態タグ

承認済みの製品本文でない記述には、すべてタグを付ける。

| タグ | 意味 | 作れる主体 |
|---|---|---|
| `[FACT]` | 入力資料・コード・公式仕様で確認済み | AI 可 |
| `[DECISION]` | **人間本人が直接承認済み** | **人間のみ。委任 AI は作成できない** |
| `[AI-APPROVED]` | 参照済みの人間 `[DECISION]` の範囲内で AI が行った工程内承認 | AI 可。ただし**Gate 1・P0 start・最終P0 contract・D5・formal document 昇格というhuman-direct gateの代替にならない** |
| `[PROPOSAL]` | AI 提案、未承認 | AI 可 |
| `[ASSUMPTION]` | 検証前の前提 | AI 可 |
| `[OPEN blocking: yes\|no]` | 未解決。**極性の併記が必須** | AI 可 |
| `[HUMAN]` | 人間だけが実行可能 | **AI 実行候補へ付けない** |
| `[AI-ACTION]` | 現在の権限・能力・承認範囲内で AI が実行可能 | `AI_ACTIONS.md` で authority・input hash・evidence・cleanup を追跡。`HUMAN_ACTIONS.md` へ混在させない |
| `[EXTERNAL]` | 外部情報・外部サービス依存 | AI 可 |

**文書は、active な `[PROPOSAL]`・`[OPEN blocking: yes]`・未検証 `[ASSUMPTION]` を含む間、Draft から Approved へ変えられない。** formal document を Approved へ昇格できるのは人間の直接 D5 承認だけで、`[AI-APPROVED]` にはできない。

### active state の機械判定

active occurrence は、現在の製品本文・current operating section の通常行、list、table cell にある上記タグ。次だけは**非状態の表記**として集計から除く。

- fenced code と、タグ構文を定義する固定 legend/example row。legend heading 配下を丸ごと除外せず、token＋定義だけの既知 row に限定する。子sectionの通常行・list・state ID/owner/scopeを持つrowはactive判定する

Change/Decision history と Completed closure record でも literal active tag は除外しない。履歴・closure は角括弧タグを再掲せず、qualified source ID、terminal status、時刻、approval/closure evidence の project-relative path、実ファイルから再計算した evidence SHA-256、影響正本 hash の固定fieldで表す。単に行内へ `historical` / `resolved` / `pass` と書くだけでは除外・closure と認めない。`validate_docs.py` と `validate_d5_acceptance.py` は同じ parser を使い、同じ bytes に別判定を出さない。raw D4 report、capsule、attestation等の lifecycle artifact は製品 docs manifest 外だが、検証対象へ明示的に含める場合もこの状態判定を使う。

### 決定の記法

```text
D-12 [DECISION] Server owns hit confirmation.
Reason: competitive PvP and client tampering risk.
Evidence: NET test SV-14.
F-12: server validates a client-predicted candidate hit.
Switch condition: mobile latency P95 exceeds approved threshold after compensation test.
Approver: project owner.
Revision: 1.2.0.
```

各 fallback は switch condition・承認者・影響文書を持つ。

**決定 ID は常に完全修飾する。** 独自採番を持つ文書が複数ある場合、`GDD D-12` と `Feasibility FR-2.6 D-12` は別物。裸の `D-12` を書かない。運用は `gdd-and-intake.md` §2。

---

## 第3部 — 変更伝播

変更ごとに影響表を作る。

| 変更した事実 | 正本 | 下流参照 | テスト | WP | 移行・互換性 |
|---|---|---|---|---|---|

更新はこの順序で行う。

1. 承認済み決定
2. 正本
3. 機械可読 contract instance（validation shape 自体が変わる場合だけ JSON Schema も更新）
4. 下流参照
5. テスト
6. work package
7. progress / changelog

### 暫定正本の規則

下流に暫定的な権限を置いてよいのは、**上流文書をまだ編集できない場合だけ**。その暫定節は次を名指しする。

- 上流の取込先
- 正確な規則
- 失効イベント
- owner
- status

取り込み後は「Data Definition v1.3 §4.2 へ YYYY-MM-DD に取込済み」のような記録へ置き換える。**暫定節をそのまま残さない。**
