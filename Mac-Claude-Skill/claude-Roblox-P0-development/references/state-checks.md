# `check_p0_state.py` — 検査内容と設定

**文書内の整合は既存 lint が見る。本 script が見るのは文書をまたぐ不整合。** 実プロジェクトで独立照合が2巡かけて発見した型を機械化した。

```bash
python3 scripts/check_p0_state.py --project-root . --prefix CAV
python3 scripts/check_p0_state.py --project-root . --prefix CAV --json
python3 scripts/check_p0_state.py --list-rules
python3 scripts/check_p0_state.py --prefix CAV --only wp-status-cross-doc
```

設定は `.claude/p0-check.json`（既定）または `--config`。文書名の `{PREFIX}` は `--prefix` で置換される。

**設定が無い項目は検査せず note を出す。note が出ている観点は「検査して問題なし」ではなく「検査していない」。** PASS を全件確認と誤読しない。

exit code は次のとおり。**設定不備は検査結果ではなく設定の誤りなので、finding ではなく exit 2 で落とす。**

| exit | 意味 |
|---|---|
| 0 | error 0（warn はあってよい） |
| 1 | error あり（検査は成立した） |
| 2 | 設定不備。未知の設定キー／rule 名、`--config` の指す設定が無い、`wp_status_mirrors`・`status_vocabulary`・`git_fact_docs` が空 |

**指定した文書が存在しない場合は exit 1（error finding）** になる。設定は正しいが対象が無い、という状態を区別するため。検査しない意図なら `rules` で当該 rule を明示的に `false` にする。

---

## rule 1: `wp-status-cross-doc`

**何を見るか**: Work Package の Status が、正本（`work_packages`）とそれを写した運行記録（`PROGRESS` 等）で食い違っていないか。

**なぜ要るか**: 文書内 lint では検出できない。**正本の索引と詳細節が「どちらも旧値で一致」していると 0 件を返す**ためで、実際にそれで Major を見逃した。handoff の inScope に正本を入れ忘れると必ずこの形になる（→ `rework-catalog.md` C-1）。

**検出の仕方**: 正本から ID → Status を作り、mirror 側の次の3形式と突き合わせる。

- 表の Status 列（**ID が先頭セルにある行だけ**。説明セルに ID を含む別種の表を WP 行と誤認しないため）
- `- ... Status: X` の箇条書き
- 散文の `Status は \`X\`` という明示形。**状態語が出るだけの説明文は拾わない**（状態遷移を記述した履歴で大量に誤検出するため）。ID は marker 直前のものへ帰属させる

**履歴は除外する**: `history_markers` のいずれかを含む行は現況の宣言ではないので飛ばす。履歴行に旧値が残るのは正しい。

**設定**:

```json
{
  "wp_status_source": "docs/{PREFIX}_work_packages.md",
  "wp_status_mirrors": ["PROGRESS.md"],
  "wp_id_pattern": "WP-[A-Z0-9]+-\\d+[A-Z]?",
  "status_field": "Status",
  "status_vocabulary": ["Proposed", "Approved", "In progress", "Verified", "Superseded"],
  "history_markers": ["記録時点", "時点では", "時点の", "当時", "だった", "であった", "旧値"]
}
```

**Status の語彙は architect の Work Package template が正本**（`Proposed` / `Approved` / `In progress` / `Verified` / `Superseded`）。ここで勝手に増減すると、語彙外の値が黙って検査対象から外れる。

**実績**: 実プロジェクトで照合1巡目が Major と判定した箇所を、同じ行番号で検出することを確認済み。是正後は 0 件。

---

## rule 2: `git-current-facts`

**何を見るか**: 現況として宣言された commit hash・未 push 件数が実測と合っているか。

**なぜ要るか**: 「未 push N commit」型は commit のたびに失効する。実プロジェクトでは**3回連続で再発**し、毎回「全文走査した」と報告された後に照合で発見された。

**走査範囲**: **最初の `##` 見出しより前**（現況が宣言されるヘッダ区間）だけ。それ以降は履歴節であり、旧値が残っているのが正しい。

**検出する形**:

- `未 push N 件` / `未 push N commit` → 実測 `git rev-list --count <remote>..HEAD` と比較
- `origin/main = <hash>` / `origin/main は <hash>` → 実測と比較
- `HEAD = <hash>` → 実測と比較

**根本対処は形式を変えること**: 件数と hash を保持せず「実測コマンドの結果を正とする」と書けば二度と失効しない。本規則はその移行が済むまでの検出網である。保持してよいのは意図的なスナップショット（Last Known Good Commit のような「その時点で検証した」宣言）だけ。

**設定**: `git_fact_docs`（既定 `["PROGRESS.md"]`。空だと exit 2）、`git_remote_ref`（既定 `origin/main`。解決できないと error）。

---

## rule 3: `open-evidence`

**何を見るか**: `[OPEN]` に closure evidence と Owner が書かれているか。

**なぜ要るか**: 閉じる条件と担当が読めない open は放置される。**いつ閉じられるか誰にも分からない**まま下流が積み上がる。

**対象**: 生きた open だけ。**closure record や履歴行が open marker に言及しているだけのもの**は対象外（marker が行頭またはセル頭にあるものだけを見る）。閉じた open を毎回鳴らすと無視されるようになる。

**severity**: 散文形式は `error`、表のセルに収めた open は `warn`。どちらも「閉じる条件が読めない」点は同じだが、**表形式まで error にすると既存文書で鳴り続けて無視される**ため分けている。

**設定**: `open_docs`（**未設定だと無効**）、`open_pattern`、`open_required_terms`（既定 `["closure evidence", "Owner"]`）。

---

## rule 4: `decision-ref`

**何を見るか**: 参照された決定 ID が決定記録に存在するか。

**なぜ要るか**: **採番を予約しただけで起票していない**ことがある。実プロジェクトでは「採番候補 D-120」と書いただけで台帳に行が無く、照合で Minor になった。参照の綴り間違いも拾う。

**severity**: `warn`（決定記録の見出し書式が多様で、抽出漏れの可能性があるため）。

**裸参照は対象外**: 修飾のない `D-n` は docs-creator の lint 規則 `bare-decision-id` が担当する。ここで二重に鳴らすと本規則の信号が埋もれる。本規則が見るのは「修飾はあるが解決しない」参照であり、**番号だけ一致して修飾が違う**場合は名前空間衝突の兆候として別メッセージで報告する。

**設定**: `decision_record`、`decision_heading_pattern`、`decision_ref_pattern`、`decision_ref_docs`（**未設定だと無効**）。

---

## 設定例（実プロジェクト）

```json
{
  "wp_status_source": "docs/{PREFIX}_work_packages.md",
  "wp_status_mirrors": ["PROGRESS.md"],
  "open_docs": ["docs/{PREFIX}_toolchain_spec.md", "docs/{PREFIX}_work_packages.md"],
  "decision_ref_docs": ["PROGRESS.md", "docs/{PREFIX}_toolchain_spec.md", "HUMAN_ACTIONS.md"]
}
```

`open_docs` と `decision_ref_docs` は**プロジェクトごとに列挙が要る**。空のままだと該当規則が無効になり、note でその旨が出る。

---

## 他の検査との関係

| 検査 | 見るもの |
|---|---|
| architect の `validate_docs.py` / `validate_traceability.py` | 文書体系の形式・要件トレース |
| docs-creator の `lint_docs.py` | 文書内の定型欠陥（裸 `[OPEN]`、失効前提句、値の二重正本、索引ドリフト） |
| **本 script** | **文書をまたぐ状態不一致・現況値の失効・open の evidence・決定参照** |

3つとも走らせる。**照合へ出す前に**走らせるのが要点で、人間の目を機械で足りることに使わせない。
