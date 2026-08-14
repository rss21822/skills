---
name: claude-Roblox-P0-development
description: >
  Roblox 開発の P0（contracts/bootstrap）フェーズを、手戻りを最小化して進めるための運行規約。D3 の文書体系が揃った後、W0 製品実装の前に、契約を「実装可能な状態」へ確定させる工程を扱う。Change Request の起草・承認記録・正本の実改訂・open closure・契約承認・Work Package の Verified 遷移という6つの作業単位と、各段で実際に起きた手戻り14種の防止策を提供する。
  「P0 を進めて」「P0 に着手」「P0 の Work Package を実施」「WP-P0-xxx」「Change Request を起草／承認」「open を閉じる」「契約承認」「Verified へ遷移」「契約整備フェーズ」といった依頼のほか、Roblox プロジェクトで実装前の契約確定・割当決定・gate closure・承認記録を扱うとき、Toolchain や Work Packages の open を閉じようとするとき、承認の委任下で AI が承認判断を行うときは必ずこの Skill を使うこと。ユーザーが「次の WP」「契約を確定して」「open の処理」とだけ言った場合も、対象が Roblox の P0 工程なら適用する。
  一方、D0〜D3 の文書体系そのものを新規作成する作業には `claude-roblox-dev-docs-creator` を、W0 以降の製品コード実装には別の規約を使う。単発の質問回答・誤字修正には適用しない。
---

# Roblox P0（contracts/bootstrap）開発

## 0. この Skill の位置づけ

**何を作るか**（文書体系・D0〜D7 の定義・Work Package の内容）は `roblox-development-architect` が正本。**文書をどう書くか**（執筆順序・handoff 契約・照合スコープ）は `claude-roblox-dev-docs-creator` が正本。

本 Skill が決めるのは**その次**——文書が揃った後、**契約を実装可能な状態へ確定させる工程**の運び方である。handoff の書き方・照合プロトコル・機械検査の基本は docs-creator に従い、**ここへ複製しない**。

**P0 とは何か**: D3 で文書体系が完成しても、そのままでは実装に入れない。「この module を誰が作るのか」「この path は誰が所有するのか」「この gate はいつ閉じるのか」が未確定のまま残っているためである。P0 はそれを**契約として確定させる**フェーズであり、製品コードは1行も書かない。

**なぜ専用の規約が要るか**: 実プロジェクトで P0 を進めた際、26便の handoff と16巡の独立照合を要した（抽出時点の実績。以後も増える）。その手戻りを原因別に分類すると、**文書の書き方の問題はほとんど無く、大半が「gate の設計」と「承認記録の構造」と「状態の同期」だった**。この3つは型が決まっており、先回りできる。

## 1. P0 の6つの作業単位

本 Skill は P0 の作業をこの6種へ分類する。**どの単位を今やっているのかを常に自覚する。** 単位が混ざると、承認していないものを実装したり、実装していないものを承認したりする。

| # | 作業単位 | 成果物 | 特徴的な失敗 |
|---|---|---|---|
| 1 | **契約整備** | 上流設計を物理へ写した契約節と、未確定を収録した `[OPEN]` | 循環 gate／open の粒度過大 |
| 2 | **Change Request 起草** | 選択肢と推奨を根拠つきで提示した CR（Status `Proposed`） | 担当の創作／承認済み決定の侵食／選択肢の未完成 |
| 3 | **承認記録** | `DECISIONS.md` の決定 ID と、台帳・CR ヘッダの同期 | 承認内訳の複製／委任と正本の承認者規定の不整合 |
| 4 | **正本の実改訂** | CR の inventory どおりに改訂された正本 | inScope に状態の正本を入れ忘れる／scope creep |
| 5 | **open closure** | closure record（evidence の成立記録） | evidence 未成立で閉じる／閉じてはならない open を閉じる |
| 6 | **契約承認と Verified 遷移** | 昇格記録と WP の状態遷移 | 判断材料の検証省略／遷移条件の未実測 |

**順序は「対象ごとの状態機械」として読む。** 1本の直線ではない。ある open／CR が 2→3→4→5 を進む間に、別の open のために 2 へ再入するのが普通である（実プロジェクトでは CR-002 の一巡を終えた後、client adapter のために CR-003 で 2→5 を再入し、そのうえで 6 へ進んだ）。

**飛ばせないのは1つの対象の中での 3→4→5 である。** 「承認しただけでは閉じない」という原則の帰結であり、ここを縮めると必ず後で戻る。

### 着手時に現在地を判定する

「P0 を進めて」と言われたら、まず次を読んで**どの対象がどの単位にいるか**を確定する。ここを飛ばすと、承認済みのものを再承認したり、未承認のものを実改訂したりする。

| 読むもの | 分かること |
|---|---|
| 進捗記録の Next authorized action | プロジェクトが次に何を待っているか |
| 各 CR の Status（`Proposed`／`Approved`） | 2 と 3 のどちらにいるか |
| 対象 open の本文 vs closure record | 4 と 5 のどちらにいるか |
| 契約節の `[PROPOSAL]`／`[DECISION]` | 6 に到達しているか |
| Work Package の Status（正本側） | 6 の後半（Verified 遷移）が済んでいるか |

**複数の対象が別々の単位にいることは普通である。** 対象を1つ選び、その単位の作業をする。

各単位の詳細と手戻り実例は `references/work-units.md`。

## 2. gate 設計 — 手戻りの最大要因

P0 の手戻りの半分はここから出る。詳細は `references/gate-design.md`。要点は3つ。

**循環を作らない。** 「A の承認条件が B、B の前提が A」は実際に2回起きた。契約の承認条件に**まだ存在しないもの**（実ツリー、build 成功、実装後の検査）を入れると、ほぼ確実に循環する。対処は**承認を2段に割る**こと——「契約としての承認（実体の存在を条件にしない）」と「実装後の適合確認（承認の前提ではない）」。

**open の粒度を closure 可能な単位にする。** 4つの entry file を1つの open にまとめた結果、そのうち2つが未確定の計測待ちだったせいで、確定済みの2つも閉じられなくなった。**closure 条件が違うものを同じ open に入れない。** 分割は後からでもできるが、分割する前に下流が「この open が閉じない」を前提に書かれ始めると被害が広がる。

**規定を書いたら、それを強制する場所まで配線する。** 「実装後に B を検査する」と書いただけでは効力がない。**どの WP の完了条件に入るのか**まで到達させる。実プロジェクトでは、規定を書いた本人が「追記が未了の間は効力を持たない」と正直に書いていたのに、その追記を担うはずの CR の改訂 inventory に入っておらず、経路が途中で切れていた。照合2巡かかった。

## 3. handoff の inScope — 状態の正本を必ず含める

**「Status を X へ更新せよ」と指示するなら、Status の正本ファイルを inScope に入れる。** 当たり前に見えるが、実際に事故った。

Work Package の Status は `work_packages.md` の index と詳細節が正本で、`PROGRESS.md` はその写しである。inScope に `work_packages.md` を入れ忘れたまま「Status を `In progress` へ」と指示した結果、実装モデルは inScope 内の `PROGRESS.md` だけを更新し、**正本と運行記録が二分した**。照合で Major になった。

一般化すると: **handoff の objective に書いた変更対象すべてについて、その値の正本がどのファイルかを確認し、inScope に含まれているかを発行前に検算する。** 値の所有先は docs-creator の所有マトリクスが正本。

同型の失敗として、**handoff 自体の指示が誤っている**ことがある（存在しない導出規則の適用を要求した、など）。その場合は**成果物を歪めて辻褄を合わせず、契約側の誤りとして記録して直す**。是正 handoff の冒頭に「§0 handoff 側の誤りの記録」を置くのが定型。

## 4. 承認記録 — 内訳の正本は1箇所

詳細は `references/approval-records.md`。要点は2つ。

**承認内訳を複製しない。** 「何を承認したか」の正本は `DECISIONS.md` の決定1件に集約し、Work Package・Toolchain・CR ヘッダ・台帳からは**参照だけ**を置く。複製すると、後で選択を変えたときに片側更新が起きる。P0 は選択の記録が多いので、ここが最も汚れやすい。

**承認を委任したら、正本側の承認者規定も同期する。** Owner が「以降は AI が承認判断してよい」と委任しても、Toolchain や各 Spec が「承認者は `[HUMAN]` Project Owner」と書いたままだと、**次工程の権限主体が二通りになり、authorized path が実際に止まる**。委任の内容は複製せず参照で表し、対象外（production 接触・publish・商品 ID・Secrets 等）は正本のまま維持することを明記する。

## 5. 失効値 — 記録に「変わる値」を保持しない

同じ型の欠陥が**3回連続で再発**した。記録行に現在形のまま残った commit hash、Status、件数である。

**対処は形式そのものを変えること。** 「未 push 3 commit（hash 列挙）」のように**変わる値を保持する記述は、commit のたびに失効する**。件数と hash を持たず「`git rev-list --count origin/main..HEAD` の実測を正とする」と書けば、二度と失効しない。

保持してよいのは**意図的なスナップショット**だけ（Last Known Good Commit のように「その時点で検証した」という宣言）。履歴行に旧値が残るのは正しく、**現況値へ上書きするのは過去の改変**である。時制を限定し、現在値の正本がどこかを示すのが正しい是正。

`claude-roblox-dev-docs-creator` の lint 規則 `status-index-drift` が文書内の索引と詳細節の食い違いを検出する。**ただし文書をまたぐ不一致（`work_packages` と `PROGRESS`）は検出しない。** そこは本 Skill の `scripts/check_p0_state.py` が担う。

## 6. 機械検査

照合へ出す前に走らせる。**跨文書の状態不一致・open の evidence 欠落・宣言された git 現況値の失効**を検出する。これらは実プロジェクトで人間の照合が2巡かけて見つけたもので、機械で先に潰せる。

```bash
python3 scripts/check_p0_state.py --project-root . --prefix CAV
python3 scripts/check_p0_state.py --project-root . --prefix CAV --json   # 機械可読
```

検出内容と設定は `python3 scripts/check_p0_state.py --help` と `references/state-checks.md`。

あわせて docs-creator の `lint_docs.py` と architect の validator も走らせる。**執筆モデルの報告は証拠にならないので、自分で実行する。**

## 7. 委任下での承認判断

**先に上流との整合を確認する。** architect は `[DECISION]` を「owner が承認したもの」と定義している。したがって「委任された AI が `[DECISION]` を作れるか」は、本 Skill が単独で決められる話ではない。

安全な運び方は次の2段。

1. **委任そのものを人間の `[DECISION]` として記録する。** これは人間承認なので定義と衝突しない
2. 以後の AI 承認は、**その委任決定を参照する形**で記録する。「AI が独自に決定した」ではなく「人間が承認した委任の行使」として書く

それでも「AI が記録した `[DECISION]`」が architect の定義に収まるかは解釈が残る。**プロジェクトで初めて委任を使うときは、この点を Owner へ確認し、必要なら architect 側へ「人間が記録した委任に基づく AI 承認も `[DECISION]` として扱う」旨の追加を求める。** 確認を取らずに運用を始めると、後の監査で承認主体が二通りあると判定されうる。

確認が取れない間は、**AI の判断を `[PROPOSAL]` または承認推奨に留め、確定は Owner に返す**のが安全側である。

委任下で承認する場合に守ること。

**判断材料を実測してから承認する。** 「§2.3.8 A の判断材料4点」のような条件が正本に書かれているなら、**それを自分で再計算してから**承認を記録する。1つでも不成立なら承認せず止まる。実プロジェクトでは、判断材料（30 module の全件対応、path 導出の一意性、`Create` 照合、Rojo 記法）をすべて実測してから昇格した。

**委任の範囲外を自分で判断しない。** production 接触・publish・商品 ID・Secrets・Group 権限・production DataStore は委任の対象外であり続ける。**委任されたのは文書承認であって、外部状態を変える権限ではない。**

**判断できないものは判断しない。** 実測を必要とする決定（実機計測の結果に依存するもの）や、承認済み `[DECISION]` の変更を伴うものは、材料を揃えて Owner へ返す。実プロジェクトでは、承認済み決定を侵食する選択肢を CR の提案から外し、「選択するには追加設計が必要」と明記した。

## 8. 人間境界の宣言

P0 に人間専権の前提（実機計測、テスター募集、アカウント発行、外部決裁）が含まれる場合、途中で必ず人間待ちになる。これらは AI が代替できない。

**AI 側で進められる作業が尽きたら、そう宣言する。** 曖昧に「進行中」と書き続けると、Owner は何を待たれているのか分からない。宣言には次を含める。

- どの WP まで完了したか
- 残りの WP が**どの人間作業に依存しているか**（根本ブロッカーへ辿った結果。中間 WP の連鎖ではなく根を示す）
- 並行して進められる AI 作業があるか（**無いと即断しない**。実測不要な決裁材料の準備が残っていることがある）

最後の点は実際に外した。「並行可能な AI 作業は無い」と宣言した直後、実測不要な設計決裁（schema versioning）の材料準備が残っていることに気づいた。**「人間待ち」と「AI にできることが無い」は違う。**

## 9. 参照ファイル

- `references/work-units.md` — 6作業単位の詳細、各段の入出力と完了条件
- `references/gate-design.md` — 循環 gate、open の粒度、closure evidence、配線
- `references/approval-records.md` — 決定 ID、正本一元化、委任、台帳同期
- `references/rework-catalog.md` — P0 で実際に起きた手戻り14種。症状／実例／検出／防止
- `references/state-checks.md` — `check_p0_state.py` の検査内容と設定
- `templates/` — **docs-creator の基本 handoff 雛形に対する P0 固有の差分**。基本の必須項目（`handoffId`／`phase`／`baseline`／`objective`／`inScope`／`outOfScope`／`requirements`／`dataIds`／`acceptance`／`commands`／`execution`／`rollback` と常設条項）は docs-creator の `templates/handoff.md` が正本であり、**そちらを土台にして本 Skill の差分を重ねる**。P0 雛形だけで発行すると必須項目が欠ける
- `templates/cr_draft.md` — Change Request 起草の handoff 雛形
- `templates/approval_record.md` — 承認記録の handoff 雛形
- `templates/revision_handoff.md` — 正本実改訂の handoff 雛形
- `templates/contract_approval.md` — 契約承認と Verified 遷移の handoff 雛形
- **単位1（契約整備）と単位5（open closure を単独便にする場合）に専用雛形は無い。** 前者は docs-creator の基本雛形＋`references/gate-design.md`、後者は `templates/revision_handoff.md` の closure 節を単独便へ切り出して使う
- `scripts/check_p0_state.py` — P0 状態の跨文書検査
