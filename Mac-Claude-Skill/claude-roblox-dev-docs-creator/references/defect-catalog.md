# 再発欠陥カタログ

実プロジェクト（正本30本・約9,000行・独立照合62巡・3系統監査）で実際に検出された欠陥19種を、再発順・原因別に整理したもの。各項目は **症状 / 実例 / 検出方法 / 修正型**。

執筆 handoff を書く前にこの一覧を通読し、対象文書で起こりそうなものを handoff の制約条項へ先回りで入れると巡数が減る。

## 目次

- A. タグ・マーカー系（機械検出可能） … A-1〜A-4
- B. 正本境界系（機械検出しにくい・被害が大きい） … B-1〜B-4
- C. schema・契約系（主に照合。C-1 は lint で検出可能） … C-1〜C-5
- D. 計画・工程系 … D-1〜D-3
- E. 記録・索引系 … E-1〜E-3

---

## A. タグ・マーカー系

### A-1. 裸 `[OPEN]`

- **症状**: `blocking: yes|no` の併記がなく、その未決事項が作業を止めるのか止めないのか機械で判定できない。
- **実例**: asset pipeline spec で17件。rights・moderation・environment binding・budget gate を含んでいたため、単なる表記問題ではなく実装可否の判断が不能だった。
- **検出**: lint 規則 `bare-open`。
- **修正型**: 全件へ併記する。判定基準は「W1 実装または production 有効化を停止するか」。停止するなら `yes` と gate ID、しないなら `no`。

### A-2. blocking の極性矛盾

- **症状**: 同一対象が、ある節では `blocking: yes`、別の節では `no`。
- **実例**: analytics spec で3群（sampling/retention/frequency、crash source、machine-readable schema）。本文では「未確定のまま production activation を停止する」と書きながらタグは `no` だった。
- **検出**: lint 規則 `blocking-polarity`（同じ gate ID が両極性で出現）。
- **修正型**: 極性規則を文書内で**1箇所だけ**定義し（「production activation を停止する未決は出現箇所を問わず yes」）、全文走査で統一する。個別に直すと再発する。

### A-3. 陳腐化前提句 ★最頻出

- **症状**: 「`X.md` は未作成のため保留」「将来の `Y` が所有する」。書いた瞬間は正しく、`X.md` ができた瞬間に嘘になる。誰も直しに戻らない。
- **実例**: persistence spec :351 が最初の発見。その後の全体監査で physics・network・commerce・detailed_design・test_spec に15箇所以上が生存していた。**同一文書の同一節内で、同期済みの行と未同期の行が隣接**しているケースもあった。
- **検出**: lint 規則 `stale-premise`（「未作成」「作成予定」「将来の」＋ manifest に実在する文書名）。
- **修正型**: 理由を**実体条件**へ書き換える。「文書ができたか」ではなく「runner・fixture・evidence path・承認値が登録されたか」を closure 条件にする。文書の存在を条件にすると、存在した瞬間に条件が壊れる。

### A-4. 検証語彙の自己使用（執筆モデル側）

- **症状**: 実施していない検証を報告に書く。「独立照合 N 巡 Major 0」など。
- **実例**: 1セッションで7件。禁止語を追加するたび変形した（独立照合 → 別セッション → サブエージェントレビュー → 受入照合 → 読み取り専用レビュー → 指示役の検査結果を騙る「Fable構造検査」）。sha256 の誤報告も1件。
- **検出**: lint 規則 `self-verification-claim` を執筆モデルの報告ファイルへ適用。
- **修正型**: 争わない。記録して不採用にし、検証は自分のツール実行だけを正とする。詳細は `review-protocol.md`。

---

## B. 正本境界系

### B-1. 値の二重正本 ★被害最大

- **症状**: 数値の正本が data_definition と宣言されているのに、下流 Spec がリテラル値を再記述し、ID 参照を持たない。正本を改訂しても下流が静かに陳腐化する。
- **実例**: FR-2 引き渡し値（220ms・0.35s・2.5×4×7 studs・12/4 studs・0.05s・2.0/2.5s）が physics・detailed_design・network に literal で存在し、3文書の DATA ID 参照数は**0件**だった。文書ごとに個別照合していたため62巡を素通りし、体系横断監査で初めて出た。
- **検出**: lint 規則 `unreferenced-value`（単位つき数値リテラルが非所有文書にあり、同一行に DATA ID／所有 key 参照がない）。
- **修正型**: 台帳行へ参照列を追加し、リテラルは残したうえで「転記。正本は参照先」と明記する。読解性のために値を消す必要はない。消すべきは「参照のない値」。

### B-2. 決定 ID の名前空間衝突

- **症状**: 別文書が同じ `D-n` 体系を独立に使い、裸で参照すると誤った決定へ解決される。
- **実例**: `GDD D-9`（操作補助は視認のみ）と `Feasibility FR-2.6 D-9`（命中の早期確定）。さらに evidence 配下の gate 提案文書が独自の D-1〜D-10 を持ち、GDD 系と全面衝突していた。detailed_design と physics の裸 `D-4` は、規約どおり読むと GDD D-4（サイドグレード）へ誤解決する状態だった。
- **検出**: lint 規則 `bare-decision-id`（修飾子なしの `D-\d+`）。
- **修正型**: 完全修飾を規約化し、DECISIONS.md に**衝突している名前空間の一覧**を記録する。改番・収録は人間判断に送る（AI が勝手に採番しない）。

### B-3. 上流 `[PROPOSAL]` の昇格

- **症状**: 下流文書が、上流の未承認案を `[FACT]` や `[DECISION]` として引用する。
- **実例**: ugc spec が analytics spec の `[PROPOSAL]`（馬名の非収集）を `[FACT]` として記述。同文書が「上流 PROPOSAL は昇格しない」と自ら宣言している行と矛盾していた。
- **検出**: 照合（機械検出は困難）。
- **修正型**: 上流状態を明示して引用する。「Analytics Spec :322 は上流 `[PROPOSAL]` として〜を定める。本書の consumer rule も `[PROPOSAL]`」。さらに、走査で確認できた事実（「現行 event dictionary に該当 event が存在しない」）は別行の `[FACT]` に分離する。主張の強さが違うものを1文に混ぜない。

### B-4. 判断所有先の取り違え

- **症状**: 「配達先」を「所有先」と書いてしまう。値が届く文書と、値を決める文書は別。
- **実例**: clamp/rate の所有を Network Spec ではなく受け取り側に書いた handoff、窓・履歴長の所有を Physics に書いた handoff。いずれも照合で Major。
- **検出**: 照合。
- **修正型**: handoff の常設条項「配達先 ≠ 数値所有先 ≠ 判断所有先」。所有マトリクスは `ordering.md`。

---

## C. schema・契約系

### C-1. 受け口なき契約 ★Critical になりやすい

- **症状**: 文書 A が通知・イベント・gate を定義したが、受け取るべき文書 B/C/D に受信契約が無い。片側だけで完結したように見える。
- **実例**: rights ledger が権利失効・撤回・置換の通知 payload を定義したのに、asset・liveops・commerce のいずれにも受信・停止・ack の契約が無かった。「失効しても production の binding が生き残る」状態で、監査で Critical。
- **検出**: lint 規則 `contract-consumer`（設定の `contracts` レジストリに列挙した consumer 文書に marker が存在するか）。
- **修正型**: 通知を定義したら、同じ handoff の中で consumer 側の受信契約まで書く。payload の**正式 field 名を1箇所で固定**し、consumer は逐語参照する（言い換え表現は不一致の温床）。

### C-2. field の状態依存性の欠落

- **症状**: schema で `required` とした field が、ライフサイクルの初期状態では埋められない。
- **実例**: `quarantineLocation` が `Detected` 発行時から必須だったが、退避成功後にしか値が存在しない。同じ文書の手順と矛盾していた。
- **検出**: 照合。
- **修正型**: 状態依存の必須性へ変え、不変条件を明記する（「state が Quarantined 以降 ⇔ location が存在」）。非適用は省略や null ではなく `not_applicable` の明示記録にする。

### C-3. 識別子の欠落

- **症状**: レコードに id が無く、監査ログや相互参照が張れない。
- **実例**: `QuarantineRecord`／`RecoveryRecord` に識別子が無いのに、別の節が「recovery identity で相関する」と書いていた。
- **検出**: 照合。
- **修正型**: id field を追加し、相関規則（どの id で何と何を結ぶか）と、生成物の格納先参照まで定義する。

### C-4. composite 値の分解漏れ

- **症状**: 意味の異なる2値を1つの field へ入れ、照合条件が一意に決まらない。
- **実例**: commerce の `rightsDecisionRefs` が「決定参照」と「応答リビジョン」を同一集合に持ち、どの validation pass を失効させるか特定できなかった。
- **検出**: 照合。
- **修正型**: binding 型へ分解する（`{ rightsDecisionRef, responseRevision }` の集合）。状態の所有は上流に残し、下流は照合結果として自分の pass を失効させるだけにする。

### C-5. query identity の非固定

- **症状**: 集計式や参照先に固定 ID が無く、参照側の文字列と一致しない。
- **実例**: analytics の dashboard 集計式が無名で、alert 側は `AO-DASH-EXECUTIVE-KPI.match_completion` のような ID で参照していた。`completion=` と `.match_completion`、`same-session rematch` と `.same_session_rematch` など、変換規則も台帳も無かった。
- **検出**: lint（参照先 ID の存在確認は設定で拡張可能）／照合。
- **修正型**: subquery ID 台帳を作り、参照は**文字列完全一致**にする。wildcard や抽象式（`each §3.8 event`）は実在 event 名の明示列挙へ展開する。

---

## D. 計画・工程系

### D-1. 循環 gate

- **症状**: A の承認条件が B、B の前提が A。誰も着手できない。
- **実例**: P0 Work Package の `Authorized by` が「D5 承認」だったが、P0 は D5 到達のための前提作業だった。別例として、FR 計測用の暫定値 profile を、計測完了後の製品ビルドで再利用する時系列矛盾。
- **検出**: 照合（clean-room 監査が特に強い）。
- **修正型**: gate を分離する（P0 開始承認と D5 承認は別）。profile 系は一方向契約を明記する（measurement で計測 → 確定 → production を正本化、の逆流を禁止）。

### D-2. Work Package の粒度過大

- **症状**: 1つの WP に複数モジュール新設＋統合＋テスト＋Studio 検証が入り、1セッションで終わらない。
- **実例**: 21 WP で作成 → 照合指摘で34 → さらに3件を分割して40。目安は「新設モジュール1〜2＋そのテスト」で1 WP、統合と実機検証は別 WP。
- **検出**: 照合。
- **修正型**: 分割時は REQ 集合を保存し（分割前後で欠落・追加を0にする）、分割間の Prerequisites と index を同時更新する。

### D-3. coverage の見かけ

- **症状**: トレーサビリティ表の行は揃っているが、実際には要件を解決していない。validator は形式しか見ないので通ってしまう。
- **実例**: 全 WP の行が matrix に存在したが、19 WP で validator 実行ケースが未割当、2 WP で「登録確認」を要求されているのに「実行ケース」が割り当てられていた。3 WP は case の Requirement IDs を union しても要件を解決できなかった。
- **検出**: 照合（matrix → case → REQ の union を再計算させる）。
- **修正型**: 照合依頼に「union を自分で再計算せよ」と明記する。形式 validator の PASS は意味の検査を代替しないと、依頼文にも書く。

---

## E. 記録・索引系

### E-1. 人間作業台帳の網羅漏れ

- **症状**: `[HUMAN]` 作業の台帳が、各 Spec に散在する gate を取りこぼす。
- **実例**: 16件 → 照合指摘で104 → 再指摘で112 → さらに113 → 最終119。毎回、照合者自身の `[HUMAN]` 全文走査で新しい漏れが出た。
- **検出**: 全文書に対する `[HUMAN]`／`[OPEN blocking: yes]` の機械走査。
- **修正型**: 台帳作成時に走査を必須手順にし、照合依頼でも「照合者自身が走査して未収載を列挙せよ」と要求する。**サンプル検査ではなく全件**。

### E-2. 索引・manifest の手書き

- **症状**: ヘッダの転記漏れ、文書追加のたびの再同期。
- **実例**: Status の部分転記（「Draft」だけ書いて括弧内の判定状況を落とした）が Major。索引・manifest は結局3回再同期した。
- **検出**: lint（ヘッダと索引の突合を拡張可能）。
- **修正型**: `scripts/gen_index.py` で生成する。手書きしない。

### E-3. 行番号参照の失効

- **症状**: 是正で行がずれ、他文書の `:NN` 参照が別内容を指す。
- **実例**: liveops → commerce の参照2件、PROGRESS → feasibility の参照2件、HUMAN_ACTIONS → phase_plan／toolchain の参照2件。いずれも是正の副作用。
- **検出**: lint 規則 `line-ref-out-of-range`（範囲外・不正値・参照先不在を検出）。**行がずれて別内容を指す失効は検出できない**——内容照合が要るため。節アンカー参照へ移すのが根本策。
- **修正型**: 節アンカー参照（`#3-event-dictionary`）を優先する。行番号は変わるが節見出しは変わりにくい。行番号を使うなら、是正のたびに lint を回す。
