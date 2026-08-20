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

**成果物**: `templates/p0_start_handoff.md` による人間本人の P0 開始承認記録。B0 ID/hash、B0 に固定された inventory ID/path/section/file hash と完全一致する許可 scope、禁止範囲、承認者、日時を持つ

**完了条件**: 承認対象 B0 と scope が一意で、P0-contract / D5 承認と異なる ID。inventory の追記・拡張や scope の再解釈はせず、新しい対象が必要なら D0〜D4 へ戻る。無応答、D4 合格、Gate 1、P0 内 `[AI-APPROVED]` で代替しない

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
- **閉じてはならない open を巻き込まない**。条件が違う open は別々に扱う

**典型的な失敗**: evidence 未成立で閉じる、閉じてはならない open を閉じる（A-4）

---

## 6. P0契約承認の適用・P0-CAND固定・管理WPの Verified 遷移

**入力**: closure 済みの open 群、正本が定める判断材料、既に得た人間本人の直接承認または有効な委任元 `[DECISION]`

**成果物**: 人間直接承認なら `[PROPOSAL]` → `[DECISION]`、委任AIなら `[PROPOSAL]` → `[AI-APPROVED]` の記録、P0管理WPのStatus遷移、これら最終metadataを含む immutable `P0-CAND-n`、candidate に束縛した type `p0-contract` machine approval record

**完了条件**: 判断材料とWP遷移条件が全件成立し、最終canonical bytesを先にcandidateへ固定し、その後でmachine approval recordをcandidate ID/path/outer hash/file-set hash/revisionへ束縛し、両者をrollback可能な一単位で反映している

**やること**:
- **判断材料を自分で実測してから承認入力を適用する**。正本が4点挙げているなら4点とも再計算する。1つでも不成立なら**何も記録せず止まる**
- 承認主体を混ぜない。人間本人だけが `[DECISION]`、委任AIは `[AI-APPROVED]`。後者はD5を満たさない
- Verifiedへ遷移できるのは `WP-P0-*` または正本が明示したP0管理WPだけ。製品実装WPはD5前にVerifiedへ遷移させない
- P0管理WPの遷移条件を実測する。Done definitionにvalidatorが含まれるなら実際に走らせる（追跡ファイルを上書きしない一時出力先で）
- formal documentのヘッダ `Status`／`Last approved` は変更しない。これは人間D5承認後の遷移である
- 承認記録、管理WP遷移、`DECISIONS.md`／`PROGRESS.md`／`CHANGELOG.md` 追記を private staging へ完成させ、その**最終canonical file setを先に** `P0-CAND-n` snapshot/commitとして固定する。candidate manifest自身とmachine approval recordはcandidate `files`へ含めない
- candidate固定後にだけ type `p0-contract` machine approval recordを作り、candidateのID/path/outer hash/`fileSetSha256`/revisionへ束縛する。candidate側から未来のrecord hashを参照しない
- candidate snapshot/manifest、machine record、staging済みcanonical metadataをrollback可能な一単位で反映する。途中失敗時は全対象を反映前bytesへ戻す
- 「照合の承認可」「P0管理WPのVerified」「P0契約承認」「人間D5承認」は**別の事象**として書き分ける
- §6 完了時の出口は `P0-CAND固定済み / post-P0 D4待ち`。B1 成立前に `D5提示可能` や実装開始可能を宣言しない

**典型的な失敗**: 判断材料の検証省略、遷移条件の未実測、範囲を超えた昇格

---

## 7. P0-CAND-n 検証・post-P0 D4・B1昇格

**入力**: B0、§6で固定・反映済みの immutable `P0-CAND-n`、P0開始承認 record、candidate に束縛済みのP0契約承認 record

**成果物**: B0→candidate diff、3系統 D4差分監査記録、合格candidateから同一file-set hashで昇格したB1

**完了条件**: 3系統すべて Critical 0 / Major 0。candidate の file-set hash を変えず B1 へ昇格

**やること**:
- P0 scope 外変更 0、allowlist 外変更 0、checker/lint/validator warning・note 0 を確認する
- P0開始承認がB0へ、P0契約承認がこのcandidateへ正しく束縛され、両IDが別であることを確認する
- changed canonical file から下流の test/WP/traceability/machine-readable instance/index/manifest まで dependency closure を作る
- fresh clean context の3監査系統へ B0、candidate、diff、closure の同一 capsule を渡す。過去 findings は渡さない
- canonical owner、GDD、security boundary、trigger、first WP/gate topology に影響する場合は full D4 へ昇格する
- いずれかが Critical / Major なら P0 改訂へ戻す。§6の順序で新しい `P0-CAND-(n+1)` とそれに束縛する新しいP0契約承認recordを固定・反映し、fresh 3系統を再実行する。旧 candidate / approval record / raw report は上書きせず、residual-only にしない
- 合格後だけ B1 と `D5提示可能` を記録する。B1 が人間 D5 承認の対象

差分監査の詳細は `audit-d4.md` §6。これは文書単位の residual-only 照合ではない。

---

## 単位をまたぐ共通事項

**各単位の終わりにcommitするのは、人間が今回の作業について明示許可した場合だけ。** 許可がなければ編集前snapshot（対象・不変対象のsha256 manifest、`git status --short`生出力、取得可能なHEAD）をbaselineにし、単位後もcommitしない。許可がある場合のcommit messageには独立照合の結果（巡数と記録path）を書く。pushは別途明示許可が必要。

**照合は単位ごとに1巡以上。** 是正が入ったら残存点のみで2巡目。commit許可がある場合も、承認可になってからcommitする。

baseline lineage は `B0 → P0-CAND-n → B1`。§1〜6 の途中 snapshot は作業証拠であり B1 ではない。candidate と baseline の過去 manifest を上書きしない。

**報告を信用しない。** 実装モデルの報告は要約であって証拠ではない。sha256・scope・validator・phase 境界（製品ディレクトリの不存在）は自分で実行して確認する。
