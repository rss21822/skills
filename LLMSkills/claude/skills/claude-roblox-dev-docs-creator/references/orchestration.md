# stage 連携 — 本 skill の内部 stage と、外部 skill への引き渡し

本書は **stage 間の前進条件と、外部 skill への引き渡し契約**を所有する。**stage router（どの機構で起動するか）は SKILL.md §4 が所有する。** 本書で再定義しない。

体系定義（各 phase が何を作るか）は `phase-definitions.md`。

## 1. stage 地図

```
   E0  capability preflight        本 skill 内（製品内容なしの固定 probe）
                                │
   D0 ─ D1 ─ D1.5 ─ D2 ─ D3      本 skill 内（文書制作）
                                │
   D4  3系統受入監査             本 skill 内。ただし clean context で起動
                                │
   P0  契約確定 → D4差分再監査   本 skill 内。B1成立がD5の前提
                                │
   D5  人間承認 + 状態の原子的同期  人間本人の明示承認が必須
                                │
   W0 ─ W1 ─ W2                 claude-roblox-mvp-buildout（別 skill）
        （単発 WP・局所修正だけ claude-roblox-development-delivery）
```

**full route は必ず E0 → D0→…→D3 → D4 → P0 → post-P0 D4 → D5 → W0。** post-P0 D4 は B0→candidate の3系統差分再監査で、影響範囲を限定できない場合は full D4 へ昇格する。P0 の契約承認、WP の `Verified`、AI による品質判定を **D5 の人間承認として扱わない**。D5 前に「実装開始可能」と書かない。

**W0 以降の実装 skill は `claude-roblox-mvp-buildout` だけ。** `claude-roblox-development-delivery` は、依頼自体が単発 WP・局所修正・不具合診断の場合だけ選ぶ。full 実装と同時発火させない。MVP 実行中に局所作業へ委譲する場合も、MVP の権限・worker・送信・baseline 契約を上位契約として明示継承する。

## 2. 到達点を最初に宣言する

E0 probe 後に使用者へ確認し、`docs/handoffs/out/E0_capability_probe.md` へ記録する。

| 宣言 | 終点 | 実装開始可能か |
|---|---|---|
| `docs` | D3 完了 | いいえ |
| `audit` | D4 合格 | いいえ |
| `contracts` | P0 core完了 + post-P0 D4合格 + B1成立 | いいえ |
| `ready` | D5 完了（明示承認＋状態同期） | はい |
| `full` | W2 完了 | D5 完了後のみ |

未指定時は `audit` を提案する。延ばすときは使用者の指示と変更時点を `DECISIONS.md` へ追加する。**黙って延長しない。**

## 3. 入口判定

| 現状 | 入口 |
|---|---|
| 何も無い | D0（GREENFIELD） |
| GDD だけある | D0 差分を先に取る |
| 動くゲーム／repo がある | Repository Audit を D1 前に（BROWNFIELD） |
| **他者作成の文書群がある** | **D4 監査から。正本を先に書き換えない** |
| B0 成立、P0 未着手 | P0開始承認 → P0 |
| P0 core完了、B1 未成立 | post-P0 D4差分再監査 |
| B1 成立、D5 未承認 | D5 |
| D5 承認・状態同期済み | `claude-roblox-mvp-buildout` へ |

入口判定は**実ファイル・承認記録・baseline・`git log`／snapshot manifest** で行う。ファイル名や会話上の申告だけで stage を飛ばさない。

## 4. baseline lineage

baseline 名は工程の意味を固定する。候補を合格前に B0/B1/B2 と呼ばない。

| 名称 | 内容 | 昇格条件 | 次の用途 |
|---|---|---|---|
| `D4-CAND-n` | D3 完了後、full D4 に出す immutable file set | なし。監査候補 | 3系統 full D4 |
| **B0** | 最後の `D4-CAND-n` と同一 hash の pre-P0 file set | 3系統 full D4 で Critical 0 / Major 0 | P0 開始承認の対象・P0 parent |
| `P0-CAND-n` | B0 を parent とする P0 改訂後 file set | なし。監査候補 | B0→候補の3系統 delta D4 |
| **B1** | 最後の `P0-CAND-n` と同一 hash の post-P0 file set | B0→候補 delta D4 で Critical 0 / Major 0 | 人間 D5 承認の対象 |
| **B2** | D5 承認後の原子的同期済み file set | B1→同期差分が許可済み metadata / ledger / 最初の WP authorization だけで、validator PASS | W0 handoff / D5 Last Known Good |

各 candidate / baseline lifecycle manifest は baseline ID、parent ID、file allowlist、各 sha256、生成時刻、commit または snapshot ID を持つ。過去候補を上書きしない。`B0` は `D4-CAND-n`、`B1` は `P0-CAND-n` と**同じ file-set hash**を参照し、監査後の内容変更を混ぜない。

### Historical bytes の再現性

B0/B1 は後続同期で working tree が変わっても、W0 側が全 bytes を再計算できなければならない。

- commit baseline: exact commit revision と project-relative path を記録し、`git show <revision>:<path>` 相当の blob bytes から再計算する。現在の working tree を代用しない
- snapshot baseline: project 内 `docs/evidence/baselines/<id>/snapshot/` のような immutable `snapshotRoot` に対象 bytes をコピーし、全 path は project-relative にする。元 working path だけを指さない
- candidate / baseline lifecycle manifest は source revision / snapshotRoot、各 file bytes/hash、file-set hash を記録する。自身を `files` / file-set hash に含めず、その manifest sha256 は外側の audit report・promotion/transition record・handoff package が束縛する
- W0 handoff 時、manifest の自己申告値を信用せず source blob / snapshot bytes から全 hash と file-set hash を再導出する。1件でも欠落・不一致なら停止する

candidate raw report と昇格記録は historical source を参照し、昇格後に raw report を編集しない。

## 5. 前進条件

前進条件の一覧は **SKILL.md §4** が所有する。本節はそこに書ききれない補足だけを置く。

### D3 → D4

D3 完了内容を immutable `D4-CAND-n` として固定する。commit または snapshot の**どちらか一方を明示**し、manifest と対象 hash を3監査系統で共用する。D4 へ commit を要求しない。

### D4 → P0

出口語彙は **`D4合格 / P0着手資格あり（人間P0開始承認待ち）`**。これはB0を対象にP0開始承認を求められる資格判定で、P0作業のauthorizationではない。`実装に入れる`・`implementation ready` は禁止（D5 前のため）。

D4 は findings-only・read-only。Critical/Major があれば執筆役へ `templates/correction_handoff.md` を発行する。**監査者は正本を修正せず、修正後は新しい `D4-CAND-(n+1)` を作り、過去所見を渡さない fresh clean context で3系統の full D4 をやり直す。** 文書単位照合の residual-only 規則を D4 gate 再監査へ流用しない。

3系統すべて Critical 0 / Major 0 の候補だけ、内容を変えず B0 へ昇格する。

### P0 → post-P0 D4 → D5

P0 開始前に、`templates/p0_start_handoff.md` で B0 と許可 scope を提示し、人間本人の P0 開始承認を記録する。D5 承認とは別 ID。P0 は formal document を `Approved` へ昇格しない。

P0 完了内容を `P0-CAND-n` として固定し、B0→候補の3系統 D4差分再監査を行う。changed file と canonical dependency closure を検査し、影響範囲を限定できなければ full D4 へ昇格する。Critical 0 / Major 0 の候補だけ同一 hash で B1 へ昇格する。**B1 成立後の結論だけが `D5提示可能`。**

### D5

手順は `phase-definitions.md` §9 と `templates/d5_approval_handoff.md` が所有する。要点だけ再掲する。

1. D5 の全条件を実測し、B1 の file tree・canonical 境界・triggered specs・残る Human Actions・最初の WP・validator 出力を使用者へ提示する。blocking OQ は 0 必須
2. **B1 を特定した明示承認**を得る。沈黙・AI 判断・P0 委任・過去の GDD 承認で代替しない
3. `templates/d5_approval_handoff.md` を**1便で**実行し、header Status・`Last approved`・change history・docs index・manifest・`DECISIONS.md`・`PROGRESS.md`・`CHANGELOG.md`・最初の authorized WP を**同時同期**する
4. generator・lint・validator・manifest 再生成・全 sha256 を再検査する。B1→同期後差分が次の allowlist だけか専用 validator で確認する。その他 content 差分があれば承認は無効
   - formal header の `Status` / `Last approved`
   - formal change history の D5 承認行1件
   - `DECISIONS.md` の D5 承認記録追記
   - `PROGRESS.md` / `CHANGELOG.md` の D5 遷移記録追記
   - 最初の WP 詳細節の Status / `Authorized by` と index / PROGRESS mirror
   - generator 出力の docs index / manifest
   - independent post-sync hash manifest、B2 lifecycle manifest、W0 handoff package という sealing artifacts
5. 合格した同期後 file set を B2 とし、許可済み commit または immutable snapshot を D5 Last Known Good として記録する

B2 の file set は同期後 canonical set と independent post-sync hash manifest を対象にし、B2 lifecycle manifest 自身と W0 handoff package は含めない。B2 manifest は外側の transition / handoff record、W0 package はその schema validation と package 外の記録で束縛し、自己参照を作らない。

以上が揃った時だけ `実装開始可能` と宣言する。

## 6. D5 → 外部 skill（W0 以降）

`claude-roblox-mvp-buildout` へ次を渡す。

- D5 承認記録（`DECISIONS.md` の決定 ID）
- Approved 文書の version / hash（post-sync hash manifest）
- D5 baseline B2 と、再計算可能な B0/B1 historical source
- 最初の authorized WP

**MVP 側の worker・送信先・OS 入力・capture・commit 等の承認は W0 開始時に取り直す。本 skill の承認を継承しない。**

引き渡しパッケージを `docs/evidence/d5/<D5-ID>_w0_handoff_package.json` として作り、B2 と再計算済み B0/B1 historical evidence を機械検査可能な形で渡す。package 自身は B2 file set に含めず、W0 は package 記載値だけでなく exact commit blob / immutable snapshot bytes から B0/B1/B2 を再計算してから受理する。

### W0 以降（D6/D7）

- WP 完了ごとに code・tests・evidence・`PROGRESS.md`・`CHANGELOG.md`・Traceability・影響 Spec・WP status を**同一完了単位で**同期する。commit 未許可時は snapshot/hash を Last Known Good にする
- 承認済み契約との衝突、新ルール、新 Tier 0 値、scope 変更を検出したら **WP を停止する**。D7 Change Request → 影響文書/test/traceability 更新 → D4 再監査 → 必要な P0 → 新 D5 承認を経るまで実装再開禁止
- 単なる実装欠陥で契約変更が無い場合だけ、同じ authorized WP 内で是正・再試験できる

## 7. worker と外部送信

worker 指定は stage 間で**自動継承しない**。各 stage 開始時に、能力・class・exact version・resolved model・送信先・auth/account・許可 path・secret 除外・cost cap を再確認する。共通形式は `worker-registry.md`。

**D4 は、file・validator・evidence を自身で検査できる Class A だけを gate 判定者に使う。** Class B は補助的 semantic review に使えるが、Critical 0 / Major 0、D4 合格判定を単独で出せない。

## 8. stage 遷移記録

各遷移を `DECISIONS.md` へ**追記**する（上書きしない）。

- source / target stage
- entry / exit verdict
- candidate ID / baseline ID / parent ID / manifest hash / commit または snapshot
- validator / audit / approval evidence
- 人間 gate なら承認者・日時・対象 revision
- worker 実行 attestation
- 未完了 Human Actions

## 9. 停止条件

- 宣言した到達点へ到達
- Critical > 0 または Major > 0
- 必須 validator 未解決
- D5 明示承認なし
- worker・送信承認・Class A 監査者を用意不能
- contract 変更を伴う D7 未完了
- 認証・production publish/data・課金・規約・権利処理等の human-only 境界

**停止は失敗扱いにせず、再開条件と必要 evidence を記録する。**
