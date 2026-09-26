# P0 の開始ゲート・6作業単位・出口監査

各単位の入力・成果物・完了条件・典型的な失敗。**今どの単位にいるかを自覚する**ためのもの。単位が混ざると、承認していないものを実装したり、実装していないものを承認したりする。

## 依存の全体像

```
0 P0開始承認 ─→ 1 契約整備 ─→ 2 CR 起草 ─→ 3 承認記録 ─→ 4 実改訂 ─→ 5 open closure ─→ 6 契約承認適用
   （B0+scope）    （open）       （選択肢）      （DECISIONS）    （正本）          （evidence）       （WP Verified）
                                                                                                      │
                                                                                                      ▼
                                                                                       P0-CAND-n固定
                                                                                         → 7 B0差分D4
                                                                                         → B1昇格
                                                                                                      │
                                                                                                      ▼
                                                                                             D5 承認へ提出
```

**3→4→5 を縮めない。** 「承認しただけでは閉じない」は原則であって手続きの冗長ではない。承認は選択の確定、実改訂は正本への反映、closure は evidence の成立であり、**3つは別の事象**である。実プロジェクトでは照合が繰り返しこの区別を検査した。

---

## 0. P0 開始ゲート

**入力**: 3系統 full D4 合格済み B0、その manifest、B0 の `PROGRESS.md` § Proposed P0 closure inventory と historical file hash

**成果物**: `templates/p0_start_handoff.md` による人間本人の P0 開始承認記録。B0 ID/hash、B0 に固定された inventory ID/path/section/file hash と全行に限定した製品内容 closure scope、固定 P0 procedure scope、禁止範囲、承認者、日時を持つ

**完了条件**: 承認対象 B0 と scope が一意で、P0-contract / D5 承認と異なる ID。P0-start presentationより前にoperator-pinned external monitorが開始され、canonical source-baseline projection/file-setがB0とexact一致し、canonical-project／private-staging／result-artifactsの3対象についてinclude set上のactual before-state digest、authority session/event ID、全in-scope mutation scopeが固定されている。inventory の追記・拡張や製品変更 scope の再解釈はせず、新しい対象が必要なら D0〜D4 へ戻る。Gate 1 が承認した intake、そこから再導出したrequired specs、GDDの path・bytes・revision と Gate 1 chain は P0 全体で immutable とし、inventory 行にも入れない。変更が必要なら現 P0 を破棄し、D0/D1 → unique new Gate 1 → D1.5/D2/D3 → new initial D4/B0 へ戻る。inventory 0 行でも既存契約検証・承認記録・P0管理WP遷移・candidate固定という固定手続は実施できるが、製品内容は変更しない。無応答、D4 合格、Gate 1、P0 内 `[AI-APPROVED]` で代替しない

P0 は B0 の正本を変える工程。開始承認なしに §1〜6 を実行しない。承認は P0 改訂だけを許可し、formal document の `Approved` 昇格、W0 実装、commit/push、production 操作を許可しない。

---

## 1. 契約整備

**入力**: 上流設計（module map、依存方向）、既存の物理構成、実測した tree

**成果物**: 上流の論理を物理へ写した契約節。確定できないものは `[OPEN blocking: yes|no]` として収録

**完了条件**: 論理側の全項目が物理側と対応づいている（差集合 0）。対応づけられないものが open として理由・closure evidence・Owner つきで収録されている

**やること**:
- 論理 module → 物理 path の導出規則を**先に**決める（個別に名前を決めない）
- 導出規則から機械的に導けるものと、導けないもの（adapter のような派生物）を区別する
- 未確定は open として収録する。**担当を創作して埋めない**

**典型的な失敗**: 循環 gate（A-1）、open の粒度過大（A-2）

**注意**: この段で「承認条件」を書くとき、**まだ存在しないものを使う検査を条件に入れない**。入れると循環する。承認は2段（契約としての承認／実装後の適合確認）に割る。

---

## 2. Change Request 起草

**入力**: 契約整備で立てた open、現行の Work Packages の実記述

**成果物**: Status `Proposed` の CR。対象・選択肢・推奨・影響 inventory・closure 経路・承認 gate

**完了条件**: Owner が**実際に決裁できる**状態。すなわち、各選択肢について「選んだら次に何が起きるか」が読める

**やること**:
- 対象は open からの**転記**にする。新たな対象を CR で作らない
- 割当の提案は**現行文書の実記述から根拠3点以上**。根拠を示せないものは提案しない
- 選択肢は最低2案。**推奨を明示**する
- 各案が既存の承認済み `[DECISION]` に触れるかを確認する。触れるなら「選択するには追加設計が必要」と書き、**何を決めれば選択可能になるか**を列挙する
- 影響 inventory は**欄単位**で書く（`Create` だけでなく `Objective`／`Public interfaces`／`Automatic tests` まで）。closure evidence が要求する欄を漏らさない
- 値（rate・payload・閾値・Remote 名）を**創作しない**。CR が扱うのは割当と配置であって値ではない

**典型的な失敗**: 担当の創作（E-2）、承認済み決定の侵食（E-1）、選択肢の未完成、規定の未配線（A-3）

**未配線の防止**: 契約整備で「実装後にこれを検査する」と書いたなら、**その検査を WP の完了条件へ追記する作業を、この CR の改訂 inventory に入れる**。

---

## 3. 承認記録

**入力**: 人間Owner本人の直接承認、または人間の委任 `[DECISION]` の範囲内で行ったAI判断

**成果物**: 直接承認なら `DECISIONS.md` の `[DECISION]` 1件、委任AIなら `[AI-APPROVED]` 1件。CRヘッダ・進捗記録の同期

**完了条件**: 承認内訳が1箇所に集約され、他はすべて参照になっている

**やること**:
- **選択内訳の正本は `DECISIONS.md` の当該記録**。本文に「選択内訳の正本は本記録である」と書く
- Work Packages・Toolchain・CR ヘッダ・台帳へは**参照だけ**を置く
- 人間本人が実行した `[HUMAN]` 行だけを `Completed` にし、closure evidence欄も同期する。AI判断で人間作業を完了扱いにしない
- 委任による承認なら `[AI-APPROVED]` とし、**委任の人間 `[DECISION]` IDを参照**する。`[DECISION]` へ昇格しない
- 委任を新たに記録しても、`[HUMAN]` 規定へAI経路を足さない。AI承認可能範囲は `[AI-APPROVED]` 側だけに記す

**典型的な失敗**: 承認内訳の複製（B-1）、委任AIと人間承認タグの衝突（B-2）、台帳 evidence の旧状態（B-3）

---

## 4. 正本の実改訂

**入力**: 承認された CR の影響 inventory

**成果物**: inventory どおりに改訂された正本

**完了条件**: inventory の全項目が反映され、**それ以外が変わっていない**

**やること**:
- **handoff の inScope に、変更対象の値の正本ファイルをすべて含める**（C-1）。発行前に検算する
- inventory 外の改善を見つけても実装しない。別 CR へ送る
- approved intake、再導出required specs、GDD、Gate 1 scope/target/path/hash/revision/record/capture/provenance chain は改訂しない。必要性を検出した時点で現 candidate を不合格にし、D0/D1 から新しい Gate 1 route を開始する
- 不変であるべき文書は **baseline sha256 を handoff に書き、報告で不変を証明させる**
- WP Status の唯一正本である詳細節を更新し、同じ変更単位で Package index と `PROGRESS.md` の再掲を同期する（片側更新は D-2／D-3 の原因）

**典型的な失敗**: inScope の漏れ（C-1）、scope creep

**照合での確認**: 変更行数が大きい場合、「**承認されていない改訂が混ざっていないか diff を全件走査せよ**」と照合依頼に書く。

---

## 5. open closure

**入力**: 実改訂の結果、closure evidence の各項

**成果物**: closure record（open 本文を置き換える）

**完了条件**: closure evidence の**全項**が実際に成立し、record から各項へ辿れる

**やること**:
- evidence を**1項ずつ**成立確認する。「承認した」だけで閉じない
- 一致確認は**自分で再計算**する（論理側と物理側の全件対応、差集合 0 など）
- closure record に、項番ごとに何がどこで成立したかを書く（日付・決定 ID・実測値）
- B0 historical `PROGRESS.md` の inventory ID/source ID を保ったまま、P0-CAND 用 staging `PROGRESS.md` の Completed recordへ actual evidence・影響正本の post-change hash・完了時刻を一対一で記録する。B0 historical bytes は変えない
- **閉じてはならない open を巻き込まない**。条件が違う open は別々に扱う

**典型的な失敗**: evidence 未成立で閉じる、閉じてはならない open を閉じる（A-4）

---

## 6. 人間 P0契約承認の適用・P0-CAND固定・管理WPの Verified 遷移

**入力**: closure 済みの open 群、正本が定める判断材料、§3で記録した個別選択、人間本人へ提示する最終 P0 contract approval payload

**成果物**: 人間本人の最終 P0契約 `[DECISION]`、P0管理WPのStatus遷移、これらの固定 metadata を含む immutable `P0-CAND-n`、candidate に束縛した type `p0-contract` human-direct machine approval record、candidate外のP0 lifecycle transition attestation／外部actual-event provenance。§3の個別 `[AI-APPROVED]` が存在しても、この最終 gate の代替にならない

**完了条件**: 判断材料とWP遷移条件が全件成立し、承認前stagingの正規化digestを人間が直接承認した後だけ固定procedural metadataを適用し、その最終canonical bytesをcandidateへ一度だけ固定する。その後でmachine approval recordをcandidate ID/path/outer hash/file-set hash/revisionへ束縛し、全成果物をrollback可能な一単位で反映している。外部authorityがB0開始状態・監視全域・P0-start/P0-contractの順序・全actual write・未記録書込み0・candidate結果を証明している

**やること**:
- §0から継続しているoperator-pinned external monitorのsession／target／scopeを保ち、途中の再開始や観測穴を許さない。local timestamp、別root、部分監視、自己作成logの再署名は不可
- **判断材料を自分で実測してから承認入力を適用する**。正本が4点挙げているなら4点とも再計算する。1つでも不成立なら**何も記録せず止まる**
- 承認主体を混ぜない。§3の個別判断には委任 `[AI-APPROVED]` を使えても、**最終 `p0-contract` gate は人間本人の直接承認だけ**。`delegated-process` machine recordを作らない
- Verifiedへ遷移できるのは `WP-P0-*` または正本が明示したP0管理WPだけ。製品実装WPはD5前にVerifiedへ遷移させない
- P0管理WPの遷移条件を実測する。Done definitionにvalidatorが含まれるなら実際に走らせる（追跡ファイルを上書きしない一時出力先で）
- formal documentのヘッダ `Status`／`Last approved` は変更しない。これは人間D5承認後の遷移である
- B0 historical inventory の全 ID が staging `PROGRESS.md` の Completed record へ一対一で解決され、Proposed P0 closure inventory の data row が 0 であることを実測する。欠落・重複・evidence/hash不足なら candidate を固定しない
- 承認前 private staging では、inventory closureとP0判断材料を完成させるが、最終P0契約ledger blockと管理WPの固定承認metadataはまだ適用しない。`strip-fixed-p0-approval-procedure-v1` のpre-approval modeで、この実在stagingから `approvedContentFileSetSha256` を計算する
- 人間へ planned candidate ID、実在するstaging approval payload、正規化digest、既知の `sourceBaselineRevision`（B0.revision）を提示して直接承認を capture し、operator-pinned external channel query/signature provenanceでactual actor/message/content/timeを検証する。freeze後のcandidate revision/hashを未来入力として要求しない。外部検証まで成立した後だけ、固定形の承認ledger／管理WP metadataをprivate stagingへ各1回適用する
- その最終canonical file setを**一度だけ** snapshot-only `P0-CAND-n`としてfreezeする。result-artifacts配下のsnapshot全file copyをsource/result path・bytes/hash・event IDでexact-coverし、candidate manifest outer hashとraw `fileSetSha256`を計算する。snapshot memberはsymlink／junction／reparse point／hardlink不可、link count 1、相互にuniqueなOS identity、canonical/staging sourceとのidentity交差0でなければならない。candidate manifest自身、capture chain、machine approval recordはcandidate `files`へ含めない。validatorはcandidateをcandidate modeで正規化し、承認時のpath set／digestへexact一致させる。commit-backed candidateはW0 lifecycle v1では不合格
- type `p0-contract` human-direct machine recordを、capture/provenanceとactual candidate ID/path/outer hash/`fileSetSha256`/revisionへ束縛する。candidate側から未来のrecord/provenance hashを参照しない
- freeze後にactual candidate ID/path/outer hash/fileSet/revisionへ束縛したmachine recordを作り、canonical changed pathごとexactly 1回のatomic source→frozen-result replaceでstaging済みbytesを反映する。同一pathへの複数write、任意の中間body、write-and-restore、candidate以外のbytesは禁止。途中失敗時は全対象を反映前bytesへ戻し、失敗candidateは履歴保存する。承認前freezeや承認後refreezeは行わない
- canonical apply後にfinal `p0-seal`をexactly 1件記録し、その後のin-scope mutationを0とする。candidate/B1の外側へclosed write-log付きlifecycle transition attestationを固定する。時系列は monitor開始／B0実測状態 ≤ P0-start presentation < response ≤ external verification ≤ 全pre-approval write ≤ approval payload実作成 < P0-contract presentation < response ≤ external verification ≤ 固定metadata write ≤ snapshot全file `p0-freeze` ≤ `p0-postfreeze-record` ≤ exact frozen-byte `p0-apply` ≤ `p0-seal` ≤ monitor完了。各rowはoperation/event ID・source/result path・before/after hash・rule/source inventory ID・phase・時刻を持ち、inventory mutation件数と全pre-approval手続書込み件数を分離する。inventory 0行でも手続書込みを0と偽らない
- 「照合の承認可」「P0管理WPのVerified」「P0契約承認」「人間D5承認」は**別の事象**として書き分ける
- §6 完了時の出口は `P0-CAND固定済み / post-P0 D4待ち`。B1 成立前に `D5提示可能` や `W0引渡し可能` を宣言しない

**典型的な失敗**: 判断材料の検証省略、遷移条件の未実測、範囲を超えた昇格

---

## 7. P0-CAND-n 検証・post-P0 D4・B1昇格

**入力**: B0、§6で固定・反映済みの snapshot-only immutable `P0-CAND-n`、P0開始承認 record、candidate に束縛済みのP0契約承認 record、candidate外のP0 lifecycle transition attestation／外部provenance

**成果物**: B0→candidate diff、3系統 D4差分監査記録、合格candidateから同一file-set hashで昇格したB1

**完了条件**: P0 actual-event transition proofがschema/semantic検査PASS、かつ3系統すべて Critical 0 / Major 0。candidate の file-set hash を変えず B1 へ昇格

**やること**:
- P0 scope 外変更 0、allowlist 外変更 0、checker/lint/validator warning・note 0 を確認する
- B0 と candidate の approved intake bytes、再導出required specs bytes、GDD bytes/path/revision、Gate 1 challenge/presentation/capture/provenance/record refs が完全一致することを再計算する。1 byte でも異なれば full D4 へ昇格せず現 P0 を不合格にし、D0/D1 → new Gate 1 routeへ戻す
- P0開始承認がB0へ、人間P0契約captureがplanned candidate ID／pre-freeze normalized digest／B0 source revisionへ、freeze後のmachine recordがこのactual candidateへ正しく束縛され、両gate IDが別であることを確認する
- lifecycle transition proofをoperator-pinned authorityへfresh queryまたは署名検証し、監視開始状態、対象全域、承認時系列、snapshot全file、post-freeze record、changed pathごと1回のatomic apply、final seal、全write row、未記録書込み0、seal後書込み0、candidate hashを再導出する。local attestation/hashだけなら不合格
- changed canonical file から下流の test/WP/traceability/machine-readable instance/index/manifest まで dependency closure を作る
- fresh clean context の3監査系統へ B0、candidate、diff、closure の同一 capsule を渡す。過去 findings は渡さない
- approved intake／required specs／GDD を変えない範囲でも、canonical owner、D2/D3 の Non-Goals・製品判断、security boundary、trigger、first WP/gate topology に影響する場合は full D4 へ昇格する
- いずれかが Critical / Major なら P0 改訂へ戻す。§6の順序で新しい `P0-CAND-(n+1)` とそれに束縛する新しいP0契約承認recordを固定・反映し、fresh 3系統を再実行する。旧 candidate / approval record / raw report は上書きせず、residual-only にしない
- 合格後だけ B1 と `D5提示可能` を記録する。B1 が人間 D5 承認の対象

差分監査の詳細は `audit-d4.md` §6。これは文書単位の residual-only 照合ではない。

---

## 単位をまたぐ共通事項

**各単位の一般作業履歴をcommitするのは、人間が今回の作業について明示許可した場合だけ。** ただしW0 lifecycle v1のD4-CAND/B0/P0-CAND/B1/B2は許可の有無にかかわらずsnapshot-onlyで、commit-backed lifecycle baselineはSTOP。一般commit許可がなければ編集前snapshot（対象・不変対象のsha256 manifest、`git status --short`生出力、取得可能なHEAD）を作業baselineにし、単位後もcommitしない。許可がある場合のcommit messageには独立照合の結果（巡数と記録path）を書く。pushは別途明示許可が必要。

**照合は単位ごとに1巡以上。** 是正が入ったら残存点のみで2巡目。commit許可がある場合も、承認可になってからcommitする。

baseline lineage は `B0 → P0-CAND-n → B1`。§1〜6 の途中 snapshot は作業証拠であり B1 ではない。candidate と baseline の過去 manifest を上書きしない。

**報告を信用しない。** 実装モデルの報告は要約であって証拠ではない。sha256・scope・validator・phase 境界（製品ディレクトリの不存在）は自分で実行して確認する。
