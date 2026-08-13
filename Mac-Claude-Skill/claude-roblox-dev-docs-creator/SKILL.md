---
name: claude-roblox-dev-docs-creator
description: >
  Roblox ゲームの LLM 開発用ドキュメント体系（GDD 下流の詳細設計・データ定義・各種 Spec・Work Package・テスト仕様・運用文書）を、手戻りを最小化して作成するための運行規約。別モデル（Codex 等）へ執筆させ、機械検査と独立照合で品質を担保する分業ワークフローを提供する。
  「開発ドキュメント群を作成」「設計書・仕様書を書いて」「D2 を進めて」「Codex に書かせて」といった依頼のほか、Roblox プロジェクトで GDD より下流の文書を新規作成・改訂・監査するとき、既存ドキュメントの二重正本・陳腐化参照・タグ不整合・決定 ID 衝突を点検するとき、handoff ベースで文書を量産するときは必ずこの Skill を使うこと。ユーザーが「ドキュメント」「仕様書」「Spec」「Work Package」とだけ言った場合も、対象が Roblox 開発文書体系なら適用する。
  一方、既存文書の誤字修正・文言の微修正・単発の質問回答・README 程度の更新には適用しない（外部モデルへの委譲と独立照合を伴う運行規約であり、単純な編集には重すぎる）。
---

# Roblox 開発ドキュメント制作

## 0. この Skill の位置づけ

**何を作るか**は `roblox-development-architect` skill（文書体系・テンプレート・D0〜D7 の定義）が決める。本 Skill が決めるのは**どう作れば手戻りが出ないか**——執筆順序、handoff 契約、検査の順番、照合のスコープ規約。

両者が競合したら architect 側が正本。本 Skill は運行規約であり、成果物の内容を規定しない。

**なぜ運行規約が要るか**: 実プロジェクトでこの体系（正本30本・約9,000行）を作った際、独立照合を62巡回した。その指摘を原因別に分類すると、上位は「文書の書き方が悪い」ではなく**順序の誤りと定型欠陥**だった。前者は執筆順を変えるだけ、後者は正規表現で消える。この2つを先に潰せば、LLM 照合という高コストな検査を本当に必要な意味論的欠陥へ集中できる。

## 1. 開始ゲート

作業前に2つ宣言する。後から「どのモデルが何を書いたか」を再構成できなくなるため。

- **モデル宣言**: 指示役（自分）のモデルをユーザーへ伝える。自己モデルの検証手段はないので「宣言」であって「検証」ではない。
- **執筆モデルの pin**: 既定値への暗黙依存は handoff 違反として扱う。起動ごとに明示する。

```bash
codex --version
```
未導入・版違いなら、必要な版と導入方法をユーザーへ提示して承認を得る。グローバル
インストールを勝手に実行しない——外部状態を変える上に、再現性の記録も残らない。

**依存の解決確認**: 本 Skill は文書体系の定義を `roblox-development-architect`（または
同等の体系定義）に依存する。着手前に、その skill と `document-system.md`・
`trigger-matrix.md`・テンプレート・validator の**実際の所在**を確認し、handoff へ
書く参照パスをその解決済みパスに置き換える。見つからない場合は成果物の作成を
始めず、導入または場所の指定をユーザーへ求める。前提が解決できないまま書き始めると、
存在しない規約を参照する文書ができる。

さらに、着手前に `scripts/lint_docs.py` の設定ファイル（`.claude/doc-lint.json`）をプロジェクトへ用意する。これが無いと機械検査が動かず、防げるはずの手戻りが全部 LLM 照合へ流れる。雛形は `templates/doc-lint.json`、記入例は `references/config-example.md`。

## 2. 執筆順序 — 手戻りの最大要因

**所有者を先に、消費者を後に書く。** これが本 Skill で最も効果が大きい規則。

```
Tier 0  判断・数値の所有者   data_definition / rights_provenance_ledger
Tier 1  構造                 detailed_design
Tier 2  Tier0-1 の消費者     physics / network / persistence / ui_ux
Tier 3  Tier2 の消費者       multi_place / commerce / analytics / performance /
                             asset / ugc / localization / liveops
Tier 4  生成物               docs_index / manifest（手書きせずスクリプトで生成）

D3      phase_plan → work_packages → test_spec → toolchain
        → traceability（wp/test 参照まで一括記入）
        → CLAUDE.md / workflow → release runbook → 記録類
```

**なぜ**: 順序を守らないと、先に書いた文書が「まだ無い文書」を前提に語り出す。「`X.md` は未作成のため保留」という一文は、書いた瞬間は正しく、`X.md` ができた瞬間に嘘になる。そして誰も直しに戻らない。実プロジェクトではこの陳腐化前提句が15箇所以上残り、最終監査まで生き延びた。

**どうしても順序を崩す場合**: 前方参照を `.claude/doc-lint.json` の `forward_refs` へ登録する。lint が「参照先が実在するようになったら理由句を書き換えよ」と警告してくれる。登録しない前方参照は禁止。

**もう一つの順序規則**: traceability CSV は work_packages と test_spec の**後に一度だけ**書く。骨格を先に作って後から参照列を埋めると、242行を2回触ることになる（実際にそうなった）。

## 3. 1文書のサイクル

```
handoff 発行
  → 執筆モデルが作成
  → 自分が機械検査（lint + validator + sha256 + scope）   ← 照合より先
  → 独立照合（別セッション・読み取り専用）1巡目=全面
  → 是正 handoff → 照合 N 巡目=残存点のみ
  → 承認可 → commit（ユーザー承認後）
```

各段の詳細は必要になった時点で参照する。

- handoff の必須項目と常設条項 → `templates/handoff.md`、是正便は `templates/correction_handoff.md`
- 照合依頼の書き方 → `templates/review_round1.md` / `templates/review_roundN.md`
- 巡ごとのスコープ規約と発散判定 → `references/review-protocol.md`
- 再発する欠陥19種と修正型 → `references/defect-catalog.md`
- 順序と所有境界の詳細 → `references/ordering.md`

## 4. handoff の書き方

必須項目（欠けると執筆モデルが埋め合わせに創作を始める）:

`handoffId` / `phase` / `baseline`（sha256 pin つき）/ `objective`（観測可能な形で）/ `inScope` / `outOfScope` / `requirements`（読む順序つき）/ `dataIds` / `acceptance` / `commands` / `execution`（model・effort・sandbox・approvalPolicy・network）/ `rollback`

これに加えて、実運用で失敗のたびに足していった**常設条項**を最初から入れる。個別に書かず `templates/handoff.md` をそのまま使う。中身の要点:

- 数値創作の全面禁止（DATA ID または承認済み値の参照のみ）
- **配達先 ≠ 数値所有先 ≠ 判断所有先**。値を届ける先と、値を所有する文書は別
- 決定 ID の完全修飾（裸の `D-9` を禁止。`GDD D-9` と `Feasibility FR-2.6 D-9` は別物）
- 裸 `[OPEN]` 禁止（`blocking: yes|no` 併記が必須）
- 陳腐化前提句の禁止（「未作成のため」で理由を書かない）
- 上流の `[PROPOSAL]` を `[FACT]`／`[DECISION]` へ昇格しない
- 前方参照は forward_refs へ登録
- **報告の誠実性**: 実施していない検証を書かない。検証語彙（「独立照合」「別セッション」等）を自己検証の名称に使わない。sha256 は実測値のみ

**handoff 自体の誤りは handoff を直す。** 指示が間違っていた場合（範囲指定ミス、存在しない値の要求など）、成果物を歪めて辻褄を合わせず、契約側を訂正して記録する。これを曖昧にすると、誤った指示が正本に固定される。

## 5. 機械検査を照合より先に

**`scripts/lint_docs.py` を必ず先に走らせる。** LLM 照合が見つけた指摘の相当割合は正規表現で検出できる。裸 `[OPEN]`、blocking の極性矛盾、陳腐化前提句、裸の決定 ID、行番号参照の範囲外、値の二重正本（単位つき数値が非所有文書に DATA ID 参照なしで存在）、検証語彙の自己使用。

```bash
python3 scripts/lint_docs.py --project-root . --config .claude/doc-lint.json
python3 scripts/lint_docs.py --project-root . --config .claude/doc-lint.json --files docs/specs/CAV_new_spec.md   # 単一文書
```

自分でも必ず走らせる検査（執筆モデルの報告は証拠にならない）:

```bash
git status --short          # 変更範囲が inScope 内か
shasum -a 256 <対象>        # 報告された hash と一致するか
<プロジェクトの validator>   # architect skill の validate_docs / validate_traceability
```

lint と validator が通ってから照合へ出す。通らないものを照合に出すのは、人間の目を機械で足りることに使わせる浪費。

**index と manifest は手で書かない。** `scripts/gen_index.py` がヘッダから生成する。手書きすると転記漏れが発生し（実際に Status の部分転記が Major になった）、文書が増えるたびに再同期が要る。

## 6. 独立照合のプロトコル

照合は別セッション・読み取り専用で発注する。同じセッションの自己レビューは構造上ここでは検証にならない。

**巡ごとにスコープを変える。**

- **1巡目**: 全面。観点を明示列挙する（正本準拠・独立再計算・決定トレース・トリガ行の実質・上流整合・実装可能性）
- **2巡目以降**: 残存指摘＋差分の回帰のみ。解消済み観点は「再精読不要」と明記する

なぜスコープを絞るか: 全面再読を繰り返すと、前巡で合格した領域に新しい指摘が出続けて収束しない。実プロジェクトで、スコープ限定を始めてから収束が明確に速くなった（5巡かかった文書と、2巡で終わった文書の差はほぼこれ）。

**是正の方針を照合依頼へ書く。** 「確定可能な構造は閉じる／確定不能は gate 付きレジスタへ変換する」のような方針を判定基準として渡すと、照合者が未確定事項の推測 closure を要求しなくなる。方針を渡さないと、照合者は「決めていないこと」を欠陥として報告し続ける。

**照合者には自分で実行させる。** validator、テスト、タグ集計を照合者自身に走らせる。作成側の申告値を検算させると、実数の食い違いが実際に見つかる。

発散したときの判断基準は `references/review-protocol.md`。

## 7. 報告を信用しない

執筆モデルは、実施していない検証を報告に書くことがある。実プロジェクトでは1セッション中に7件発生し、禁止語を追加するたびに表現が変形した（「独立照合」→「別セッション」→「サブエージェントレビュー」→「受入照合」→ 最終的に指示役の検査結果を騙る「Fable構造検査」まで）。sha256 の誤報告も起きた。

**対処は構造的に行う。争わない。**

- 執筆モデルの報告は要約であって証拠ではない。検証は必ず自分のツール実行で行う
- 未発注の検証を騙る行を見つけたら、`<handoff>_fable_note.md`（または相当の記録）へ「不採用」として残すだけにする。執筆モデルへ訂正を求めるやり取りは費用に見合わない
- 禁止語の列挙は抑止として書くが、効果は限定的と理解しておく

この方針で運用した結果、捏造報告が成果物へ影響した例は無かった。コストは記録の手間だけ。

## 8. commit と baseline

**承認可になるたび commit する。** 溜めると baseline が commit hash で一意に決まらなくなり、sha256 pin とスナップショットで代用する羽目になる。

実プロジェクトではユーザー承認待ちで commit を溜めた結果、最終監査で「Last Known Good Commit に正本が1バイトも入っておらず rollback 契約が空文」という Critical 指摘を受けた。文書体系は git 履歴に載って初めて体系として機能する。

未 commit 期間が生じる場合の代替手段:

- 是正前に必ずスナップショットを取る（`docs/handoffs/out/<id>_pre_correction_*`）。untracked ファイルには `git checkout` が効かない
- baseline は sha256 で pin する
- commit メッセージには実装内容に加えて**独立照合の結果**（巡数と記録パス）を書く

## 9. 参照ファイル

- `references/ordering.md` — 執筆順序と所有境界の全体設計、順序を崩す場合の手続き
- `references/defect-catalog.md` — 再発欠陥19種。症状 / 実例 / 検出方法 / 修正型
- `references/review-protocol.md` — 巡ごとのスコープ、発散判定、監査フェーズの設計
- `templates/handoff.md`, `templates/correction_handoff.md` — handoff 雛形
- `templates/review_round1.md`, `templates/review_roundN.md` — 照合依頼雛形
- `references/config-example.md` — lint 設定の記入例（実プロジェクトでどう決めたか）
- `templates/doc-lint.json` — lint 設定の雛形（空。コピーして埋める）
- `scripts/lint_docs.py`, `scripts/gen_index.py` — 機械検査と索引生成
